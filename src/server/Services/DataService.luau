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

	gear = { detector = 1, magnet = 1, cleaner = 1, suit = 1, boots = 1, satchel = 1, luck = 1 },

	carry = {}, -- array of Decay.CarriedItem. The backpack.
	locker = {}, -- Quarantine Locker (PLAN §10.2): found but not yet cleanable.

	exhibit = {
		slots = Tuning.EXHIBIT_STARTING_SLOTS,
		pedestals = {},
		bankedCash = 0,
		bankedAt = 0,
	},

	-- The wash pad (Config/Liquids). `liquids` is liquid id -> charges remaining;
	-- Plain Water is deliberately NOT in here, because "no entries" already means
	-- "on water" and storing an infinite charge count is how math.huge ends up in a
	-- DataStore. `equippedLiquid` is "" for water, never nil -- ProfileStore's
	-- Reconcile fills a missing key from the template, and a template nil is not a
	-- key at all.
	liquids = {},
	equippedLiquid = "",

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
