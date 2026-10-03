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
local Prefs = require(Shared.Config.Prefs)
local Treadmill = require(Shared.Config.Treadmill)
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
	-- Lifetime cash earned: every credit EconomyService pays out, never reduced by
	-- spending. The global Top Cash board ranks on this (Services/LeaderboardService).
	cashEarned = 0,
	xp = 0,
	level = 1,

	-- WHICH TIER OF EACH TRACK IS EQUIPPED — the one in your hands, the one
	-- StatResolver reads. It is NOT "the best you have bought" any more; see
	-- `gearOwned` below. Everything that consumes gear (StatResolver, ToolService's
	-- re-equip poll) reads exactly this field and needed no change when ownership
	-- split off it, which is the whole reason equipping writes here rather than
	-- somewhere new. `luck` is not a track and has no tiers — it is a level that only
	-- ever counts up, so it has no entry in `gearOwned`.
	gear = { detector = 1, magnet = 1, cleaner = 1, aura = 1, boots = 1, luck = 1 },

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
	-- Locker upgrades bought (Tuning.LOCKER_UPGRADE_PRICES); slots = Tuning.lockerSlots.
	lockerUpgrades = 0,
	-- Supply crates (Config/Crates), { uid, crateId }. Their own list, NOT in `carry`,
	-- but they share its slots -- Shared/Bag.used counts both.
	crates = {},

	exhibit = {
		-- How many floors this base has been built up to (Config/Floors): 1 is the free
		-- ground floor, each one bought on top adds stands. `slots` is always derived
		-- from it (Floors.slotsFor) -- ExhibitService re-derives it on every load.
		floors = 1,
		slots = 12, -- the ground floor's stands; see `floors`
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
	-- os.time() of the last brew, so the brew cooldown survives a rejoin. 0 = never.
	lastBrewAt = 0,
	-- liquidId -> true for every fluid this player has ever rolled (brew or crate).
	-- Drives the brew panel's FLUIDS tab; nothing else reads it.
	fluidsSeen = {},

	-- Which carried item is physically IN YOUR HANDS (ToolService welds it there).
	-- "" is empty-handed, never nil, same reason as equippedLiquid above. The tub
	-- refuses to wash anything you are not holding, which is what turned this from
	-- the hotbar's client-only selection into real state.
	heldUid = "",

	discovered = {}, -- itemId -> true. Drives the museum (PLAN §10.10).
	-- itemId -> Shared/IndexProgress.Entry: heaviest payload identified, times found,
	-- first-found time, NEW flag. Written by IdentifyService only. Kept beside
	-- `discovered` rather than replacing it: every existing save and reader keys off
	-- that set, and a record is extra detail about a discovery, not the discovery.
	indexStats = {},
	perks = {}, -- perkId -> true. Read by StatResolver.
	-- itemId -> failed Merge Reactor attempts on that nuke since its last success
	-- (Config/Merge PITY_STEP). Written by MergeService only; a success clears the key.
	mergePity = {},
	-- Which one-time walkthroughs this player has finished or skipped, by id ("locker"
	-- and "treadmill", both run by client/LockerTutorial). An array of strings, not a set, for the
	-- same no-gaps storage rule as everything else here.
	tutorialsSeen = {},

	-- THE NEW-PLAYER TUTORIAL (Config/Tutorial, Services/TutorialService). "active" for a save
	-- still being walked through it, "done" once it has been finished or skipped. It is a
	-- FLAG, not the step: which step you are on is read live off the bag, the stands and
	-- the gear (TutorialService.stepFor), so losing the nuke half-way sends you back a
	-- step instead of stranding you on one you can no longer do.
	--
	-- Only a brand-new save starts "active". An existing save predates the key, so
	-- onPlayerAdded sees it missing BEFORE Reconcile and writes "done", and a
	-- veteran never sees the tutorial.
	onboarding = "active",

	-- Which Detector ladder this save's tier numbers are written against. 2 is the
	-- ladder with the Rust Bucket at tier 1 (Config/Gear). A save from before it has no
	-- key at all, so it is detected before Reconcile, the same way as `onboarding`, and
	-- shifted up one tier by shiftDetectorLadder.
	detectorLadder = 2,

	-- Rebirth / gamepass / pet multipliers, pre-summed by whoever grants them.
	-- StatResolver reads this key; the schema in ARCHITECTURE.md omits it, which
	-- would have left every multiplier in the game with nowhere to live.
	multipliers = {},
	-- Permanent Robux passes owned (Config/GamePasses), key -> true. A mirror of what
	-- Roblox says, rewritten on every join by GamePassService; StatResolver reads it.
	passes = {},

	cleanTokens = 0,
	rebirths = 0,

	-- THE TREADMILL (Config/Treadmill, Services/TreadmillService). `speedPoints` is
	-- lifetime SPEED -- the visible unit a belt pays per second -- and it is the ONLY
	-- thing that decides how fast this player walks: the speed level is read off it
	-- against Treadmill.REQUIREMENTS. `treadmill` is the belt rung they own, 1-based
	-- like every gear track's tier.
	--
	-- A FLOAT, AND DELIBERATELY NOT A LEVEL. Banking the input and resolving the level
	-- on read keeps the progress bar across saves and lets the requirement curve be
	-- retuned without rewriting anyone's save.
	--
	-- NO `speedXp` HERE ANY MORE. Saves from before the Speed unit carry it; see
	-- convertLegacySpeed, which is keyed on it being present. Leaving it in the template
	-- would make Reconcile hand every new save one to convert.
	speedPoints = 0,
	treadmill = 1,
	-- Which belt ladder `treadmill` is numbered against: 4 is the four-belt ladder, one
	-- imported model per rung (Config/Treadmill). A save from the six-belt days has no
	-- key, is detected before Reconcile like `detectorLadder`, and is collapsed once by
	-- collapseTreadmillLadder.
	treadmillLadder = 4,
	-- Whether this player has treadmill access. No belt trains them until they have.
	-- Free now (Treadmill.UNLOCK_PRICE = 0), so every save starts with it, and
	-- TreadmillService unlocks older `false` saves on load; only `/train lock` clears it.
	treadmillUnlocked = true,

	-- The player's chosen base accent colour, "RRGGBB" hex (no leading "#"). "" means
	-- they have never picked one, which renders the same neutral grey as an unclaimed
	-- plot until they choose in the Settings GUI. NOT per-plot: plots are assigned per
	-- session (see ExhibitService's header), so this follows the player onto whichever
	-- physical plot they land on. Set via Net.PlotColor -> ExhibitService.setPlotColor.
	plotColor = "",

	-- Settings' HIDE MY AURA. true = AuraService stops publishing this player's
	-- AuraTier, so their aura is drawn for nobody. Cosmetic only: the aura still
	-- protects (its stats come from gear.aura). Set via Net.HideAura -> AuraService.
	hideAura = false,

	-- Settings' SOUND EFFECTS switch. true = the client mutes every effect (Sfx.luau's
	-- master SoundGroup). Set via Net.SfxMuted -> SfxService.
	sfxMuted = false,

	-- The rest of the Settings panel (Config/Prefs: graphics, shake, rad effects,
	-- flashing, volumes, rare drop lines). All client-side in effect; the server only
	-- stores and echoes them. Set via Net.Prefs -> PrefsService.
	prefs = Prefs.defaults(),

	-- The walk-speed picker (the pencil by the HUD's WALK SPEED). 0 = walk at your full
	-- trained speed; a number caps it there (Treadmill.chosenWalk). Set via Net.WalkCap
	-- -> TreadmillService.
	walkCap = 0,

	railStations = {}, -- stageId -> parts found (PLAN §5.3)

	-- Camp key (Config/Camps) -> true, once this player has stood in that camp on foot.
	-- That is what unlocks its warp button (CampService / WarpService). Base Camp is never
	-- stored -- everyone starts there. String keys only, so ProfileStore is happy.
	camps = {},

	-- BANKED SECONDS OF 2x LUCK from the Lucky Clover (Config/LuckBoost), bought with
	-- Robux. Seconds LEFT rather than an end time, because it only counts down while the
	-- player is in a server (LuckBoostService's tick) -- logging off must never burn
	-- what somebody paid for. Capped at LuckBoost.MAX_BANKED_SECONDS on every grant.
	luckBoostLeft = 0,

	-- BANKED SECONDS OF 2x CASH (Config/CashBoost), from a pack. Same rules as
	-- luckBoostLeft: seconds left, counted down only while in a server (CashBoostService).
	cashBoostLeft = 0,

	-- Packs bought (Config/Packs), key -> true. Once per player; PackService sets it.
	packs = {},

	-- The daily login calendar (Config/DailyRewards, DailyRewardService): the day the
	-- next claim pays (1-7) and the os.time() of the last claim (0 = never).
	dailyDay = 1,
	dailyLastAt = 0,

	-- The group chest on Stage 1 (Config/GroupReward): paid out once, ever.
	groupRewardClaimed = false,

	-- Shop codes already redeemed (Config/Codes, CodeService): NORMALIZED code -> true.
	-- Once per player per code.
	redeemedCodes = {},

	-- What the stands earned while the player was offline, waiting for COLLECT on the
	-- "While you were away" card (AwayEarningsService). On the save so leaving with the
	-- card up loses nothing. `awayLast` is the last amount the card showed, which a
	-- late DOUBLE IT receipt pays the extra on.
	awayPending = 0,
	awayLast = 0,

	-- The last few Robux PurchaseIds granted to this profile (ProductService). Kept IN
	-- the save because that is the only way a retried receipt -- Roblox re-sends until
	-- it hears PurchaseGranted -- can be told apart from a new purchase. A short FIFO
	-- of strings; ProductService trims it.
	receipts = {},

	-- Lifetime counters. The masteries (Config/Masteries) read most of them: itemsCleaned
	-- (WashService), kills (ExposureService.creditKill), dug (DigService), deepestStage
	-- (MasteryService), merges (MergeService), bagsStolen (ExposureService.giveBagTo) and
	-- rolls (LiquidService). They only ever count up -- a mastery tier is read off them,
	-- never stored, so a counter going down would take a reward away.
	stats = {
		deepestStage = 1,
		itemsCleaned = 0,
		slagged = 0,
		dives = 0,
		rolls = 0,
		cratesOpened = 0,
		kills = 0,
		dug = 0,
		merges = 0,
		bagsStolen = 0,
	},
}

local STORE_VERSION = 4 -- bump to abandon all existing saves
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

--- THE DETECTOR LADDER SHIFT, a one-time migration keyed on `detectorLadder` being
--- missing from the save before Reconcile runs.
---
--- The Rust Bucket went in as the new free tier 1 (Config/Gear), so every detector a
--- save refers to by number moved up one: what was tier 1 (the Bent Coil) is tier 2,
--- what was tier 8 (The Oracle) is tier 9. Without this an old save would silently
--- be handed the detector one rung below what it paid for.
---
--- The equipped tier and every owned tier move up one, and tier 1 (the Rust Bucket,
--- free) is added to what the save owns, so the owned list stays a true list of rungs.
--- Runs strictly after backfillGearOwned, so a save that has never had `gearOwned` is
--- seeded against the OLD numbering first and then shifted along with everything else.
local function shiftDetectorLadder(data: any)
	data.gear.detector = (data.gear.detector or 1) + 1
	local owned = { 1 }
	for _, tier in data.gearOwned.detector or {} do
		table.insert(owned, tier + 1)
	end
	data.gearOwned.detector = owned
	data.detectorLadder = 2
end

local function thawCarry(data: any)
	for _, item in data.carry do
		item.frozen = false
	end
end

--- THE BOOTS REFUND — a one-time, self-erasing migration.
---
--- The Boots track was retired when speed became something you train rather than buy
--- (Config/Treadmill). A player who had spent up to $140,000 climbing that ladder
--- would otherwise log in one day to find the purchase gone and the cash with it,
--- which is the single most trust-destroying thing a live game can do.
---
--- So: hand back the list price of every rung they actually bought, as cash they can
--- spend on belts.
---
--- KEYED ON `gearOwned.boots` BEING NON-NIL, not on a version field or a `refunded`
--- flag, for the same reason backfillGearOwned is keyed the way it is: the evidence
--- IS the state. Clearing both keys is what makes it one-time, and a save that has
--- already been through it has no `gearOwned.boots` to find. Note the ORDER below --
--- this must run AFTER backfillGearOwned, or a legacy save that has never had
--- `gearOwned` populated would present no boots to refund and silently lose them.
---
--- `gear.boots` (the EQUIPPED rung) is cleared alongside it. Nothing reads it any
--- more -- StatResolver stopped, and Gear.TRACKS no longer lists the track -- but
--- leaving a stale equipped tier behind invites exactly the sort of "this field looks
--- live" mistake the retirement is trying to avoid.
local function refundRetiredBoots(data: any): number
	local owned = data.gearOwned and data.gearOwned.boots
	if owned == nil then
		return 0
	end

	local refund = 0
	for _, tier in owned do
		refund += Gear.tier("Boots", tier).price
	end

	data.gearOwned.boots = nil
	data.gear.boots = nil
	data.cash += refund
	return refund
end

--- THE SPEED CONVERSION — one-time, self-erasing, same shape as the Boots refund.
---
--- Before Speed was a visible unit, training was banked as hidden `speedXp` on a
--- different curve. Treadmill.fromLegacyXp turns it into lifetime Speed that lands
--- the player on the SAME walk speed with the same fraction of the bar filled, so
--- nobody loses a level to the rework. Keyed on `speedXp` being present (the evidence
--- IS the state); clearing it is what makes this run once.
local function convertLegacySpeed(data: any): number?
	local legacy = data.speedXp
	if legacy == nil then
		return nil
	end
	data.speedXp = nil
	data.speedPoints = math.max(data.speedPoints or 0, Treadmill.fromLegacyXp(legacy))
	return data.speedPoints
end

--- THE FOUR-BELT COLLAPSE — one-time, keyed on `treadmillLadder` being missing before
--- Reconcile, the same way as shiftDetectorLadder.
---
--- The treadmill ladder went from six belts to four when each rung got its own
--- imported model. Treadmill.fromSixRungLadder puts the player on the best new belt
--- their old spend covers and returns the remainder, which is paid back as cash.
local function collapseTreadmillLadder(data: any): number
	local tier, refund = Treadmill.fromSixRungLadder(data.treadmill or 1)
	data.treadmill = tier
	data.cash += refund
	data.treadmillLadder = 4
	return refund
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
	-- Read BEFORE Reconcile, which would fill both keys from the template and make
	-- an old save look exactly like a new one. A brand-new save is a hard copy of
	-- TEMPLATE and already has them.
	local predatesTutorial = profile.Data.onboarding == nil
	local predatesRustBucket = profile.Data.detectorLadder == nil
	local predatesFourBelts = profile.Data.treadmillLadder == nil
	profile:Reconcile() -- fill in keys added to TEMPLATE since this save was made
	backfillGearOwned(profile.Data)
	if predatesTutorial then
		profile.Data.onboarding = "done"
	end
	if predatesRustBucket then
		shiftDetectorLadder(profile.Data)
		print(`[data] {player.Name}: detector ladder shifted, now tier {profile.Data.gear.detector}`)
	end
	if predatesFourBelts then
		local refund = collapseTreadmillLadder(profile.Data)
		print(`[data] {player.Name}: treadmill ladder collapsed to belt {profile.Data.treadmill}, refunded ${refund}`)
	end
	-- Strictly after the backfill — see refundRetiredBoots for why the order matters.
	local refunded = refundRetiredBoots(profile.Data)
	if refunded > 0 then
		print(`[data] {player.Name}: refunded ${refunded} for the retired Boots track`)
	end
	local converted = convertLegacySpeed(profile.Data)
	if converted then
		print(`[data] {player.Name}: converted old treadmill training to {math.floor(converted)} Speed`)
	end

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
