--!strict
--[[
	DataService.lua — the persistence layer. ProfileStore wrapper, session locked.

	Session locking is not optional in this game. Two servers writing one player's
	exhibit and cash would duplicate income, and duplicated income in a game with
	passive earnings is unrecoverable. See ARCHITECTURE.md, "Persistence".

	Every other service asks this one for a player's data and never touches DataStores
	directly. If you find yourself calling DataStoreService anywhere else, stop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Gear = require(Shared.Config.Gear)
local Decay = require(Shared.Decay)

local ProfileStore = require(script.Parent.Parent.lib.ProfileStore)

local DataService = {}

-- ── The profile template (ARCHITECTURE.md, "Data schemas") ────────────────────
--
-- ProfileStore hard-copies this for new players and Reconcile() fills in any keys
-- added here later, so adding a field is safe for existing saves. REMOVING one is
-- not — bump STORE_VERSION instead if you ever need a clean slate.
--
-- ProfileStore's constraints on this table: no gaps in numeric arrays, no mixed
-- numeric/string keys in one table, no Instances, no userdata (Vector3/CFrame/etc).
-- Serialize before you store.
local TEMPLATE = {
	cash = 0,
	xp = 0,
	level = 1,

	-- WHICH TIER OF EACH TRACK IS EQUIPPED — the one in your hands, the one
	-- StatResolver reads. It is NOT "the best you have bought" any more; see
	-- `gearOwned` below. Everything that consumes gear (StatResolver, ToolService's
	-- re-equip poll) reads exactly this field and needed no change when ownership
	-- split off it, which is the whole reason equipping writes here rather than
	-- somewhere new. `luck` is not a track and has no tiers — it is a level that only
	-- ever counts up, so it has no entry in `gearOwned`.
	gear = { detector = 1, magnet = 1, cleaner = 1, suit = 1, boots = 1, satchel = 1, luck = 1 },

	-- EVERY TIER YOU ACTUALLY BOUGHT, per track: `gearOwned.detector = {1, 4, 8}`,
	-- ascending. Buying tier 8 straight from tier 1 used to make you "own" 2 through
	-- 7 as a side effect, because ownership WAS the equipped number and the shop asked
	-- `tier <= current`. It is a real set now, so the shop can only claim you own what
	-- you paid for, and you can drop back to a tier you kept.
	--
	-- ARRAYS OF NUMBERS, NOT `{[4] = true}` SETS, and that is a storage constraint
	-- rather than a taste: the note at the top of this table forbids gaps in numeric
	-- arrays and mixed key types, and a sparse boolean set is exactly that. Tracks run
	-- to at most 8 tiers, so a linear scan for membership costs nothing.
	--
	-- IT STARTS EMPTY AND IS FILLED PER TRACK ON FIRST LOAD, which is what migrates
	-- old saves without a version bump or a marker field. Reconcile() gives an
	-- existing save this empty table; `backfillGearOwned` then seeds any track whose
	-- key is still nil from that track's equipped tier, so a legacy tier-6 detector
	-- becomes {1,2,3,4,5,6} — exactly what the old model claimed the player owned, so
	-- nobody loses anything they were told they had. A track that already has an array
	-- is never touched, so a player who legitimately owns only {1, 8} keeps that.
	gearOwned = {},

	carry = {}, -- array of Decay.CarriedItem. The backpack.
	locker = {}, -- Quarantine Locker (PLAN §10.2): found but not yet cleanable.

	exhibit = {
		slots = Tuning.EXHIBIT_MAX_SLOTS, -- every stand is free; kept as a field so a save always carries it
		pedestals = {},
		bankedCash = 0, -- sub-dollar income remainder; ExhibitService sweeps whole dollars straight into `cash`
		bankedAt = 0, -- os.time() of the last accrual, for the offline-earnings catch-up
	},

	-- The wash pad (Config/Liquids). `liquids` is liquid id -> charges remaining;
	-- Plain Water is deliberately NOT in here, because "no entries" already means
	-- "on water" and storing an infinite charge count is how math.huge ends up in a
	-- DataStore. `equippedLiquid` is "" for water, never nil -- ProfileStore's
	-- Reconcile fills a missing key from the template, and a template nil is not a
	-- key at all.
	liquids = {},
	equippedLiquid = "",

	-- Which carried item is physically IN YOUR HANDS (ToolService welds it there).
	-- "" is empty-handed, never nil, same reason as equippedLiquid above. The tub
	-- refuses to wash anything you are not holding, which is what turned this from
	-- the hotbar's client-only selection into real state.
	heldUid = "",

	discovered = {}, -- itemId -> true. Drives the museum (PLAN §10.10).
	perks = {}, -- perkId -> true. Read by StatResolver.

	-- Rebirth / gamepass / pet multipliers, pre-summed by whoever grants them.
	-- StatResolver reads this key; the schema in ARCHITECTURE.md omits it, which
	-- would have left every multiplier in the game with nowhere to live.
	multipliers = {},

	cleanTokens = 0,
	rebirths = 0,

	railStations = {}, -- stageId -> parts found (PLAN §5.3)

	stats = { deepestStage = 1, itemsCleaned = 0, slagged = 0, dives = 0, rolls = 0 },
}

local STORE_VERSION = 1 -- bump to abandon all existing saves
local store = ProfileStore.New(`PlayerData_v{STORE_VERSION}`, TEMPLATE)

local profiles: { [Player]: any } = {}
local loadedCallbacks: { (player: Player, data: any) -> () } = {}

-- ── The logout rule ───────────────────────────────────────────────────────────
--
-- ARCHITECTURE.md: freeze every carried item on session end. Slagging a player's
-- bag while they were offline is the fastest way to lose them, and it punishes a
-- thing that isn't play.
--
-- DELIBERATE DEVIATION, flagged for review: we thaw the bag again on rejoin.
-- Decay.freeze() is one-way, so a literal permanent freeze would make "dig a
-- Legendary, immediately log out, log back in" a zero-risk way to defuse any item
-- — strictly optimal, and it would gut PLAN §3.6 entirely. Thawing on load keeps
-- the promise that matters (nothing rots while you are away) without paying for it
-- with the whole mechanic. ARCHITECTURE's own wording agrees: "logging out mid-run
-- is just a very slow trip home" — you still have to make the trip.
--
-- To restore the literal reading, delete thawCarry() and its call site.
local function freezeCarry(data: any)
	for _, item in data.carry do
		Decay.freeze(item)
	end
end

--- Seed `gearOwned` for any track that has never had it, from that track's equipped
--- tier. This is the whole migration from "ownership is the equipped number" to
--- "ownership is a set", and it is deliberately keyed on the per-track key being nil
--- rather than on a version field or a `migrated` flag:
---
---   * an old save reaches here with `gearOwned = {}` (Reconcile filled it from the
---     template) and an equipped tier of, say, 6 -> it is seeded {1,...,6}, which is
---     precisely what the old `tier <= currentTier` rule told that player they owned.
---     Nothing is taken away by the change.
---   * a new save has every equipped tier at 1 -> seeded {1}, the free starting rung.
---   * a save that has ALREADY been through this has a real array on every track, so
---     the nil test fails and nothing is rewritten. That matters: a player who bought
---     tier 8 straight off owns {1, 8}, and re-running a naive 1..equipped seed would
---     silently hand them the six tiers this whole change exists to stop granting.
---
--- `luck` is skipped because it is not in Gear.TRACKS: it is a level, not a ladder.
local function backfillGearOwned(data: any)
	if data.gearOwned == nil then
		data.gearOwned = {}
	end
	for _, track in Gear.TRACKS do
		local key = Gear.profileKey(track)
		if data.gearOwned[key] == nil then
			local equipped = data.gear[key] or 1
			local owned = {}
			for tier = 1, math.max(1, equipped) do
				table.insert(owned, tier)
			end
			data.gearOwned[key] = owned
		end
	end
end

local function thawCarry(data: any)
	for _, item in data.carry do
		item.frozen = false
	end
end

-- ── Session lifecycle ─────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		warn(`[data] {player.Name}: StartSessionAsync returned nil`)
		player:Kick("Couldn't load your save — please rejoin.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR association
	profile:Reconcile() -- fill in keys added to TEMPLATE since this save was made
	backfillGearOwned(profile.Data)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your save was opened on another server — please rejoin.")
	end)

	-- They may have left while StartSessionAsync was yielding.
	if player.Parent ~= Players then
		warn(`[data] {player.Name} left during load — ending session`)
		profile:EndSession()
		return
	end

	thawCarry(profile.Data)
	profiles[player] = profile
	print(`[data] {player.Name} LOADED — cash {profile.Data.cash}, level {profile.Data.level}, carrying {#profile.Data.carry}`)

	for _, fn in loadedCallbacks do
		task.spawn(fn, player, profile.Data)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end

	if Tuning.FREEZE_ON_LOGOUT then
		freezeCarry(profile.Data) -- must happen BEFORE EndSession so it is saved
	end

	profile:EndSession()
	profiles[player] = nil
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- The live Profile object. Prefer DataService.data() unless you need :Save() etc.
function DataService.get(player: Player): any
	return profiles[player]
end

--- The player's save table, or nil if it hasn't loaded yet.
function DataService.data(player: Player): any
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

--- Yields until this player's data is loaded. Returns nil if they leave first or
--- the timeout elapses — callers must handle nil rather than assuming.
function DataService.awaitData(player: Player, timeout: number?): any
	local deadline = os.clock() + (timeout or 30)
	while os.clock() < deadline do
		local data = DataService.data(player)
		if data then
			return data
		end
		if player.Parent ~= Players then
			return nil
		end
		task.wait()
	end
	return nil
end

--- Register a callback fired once per player as their data becomes available.
--- Fires immediately for anyone already loaded, so registration order never matters.
function DataService.onLoaded(fn: (player: Player, data: any) -> ())
	table.insert(loadedCallbacks, fn)
	for player, profile in profiles do
		task.spawn(fn, player, profile.Data)
	end
end

--- "Access" once DataStores are reachable; "NoAccess" in Studio without API
--- services enabled, in which case ProfileStore runs against an in-memory mock and
--- nothing survives restarting Studio. Surfaced so the boot log can say which.
function DataService.dataStoreState(): string
	return ProfileStore.DataStoreState
end

-- ── Bootstrap ─────────────────────────────────────────────────────────────────

function DataService.init() end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Anyone who joined before this service started (Studio play-solo races this).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
