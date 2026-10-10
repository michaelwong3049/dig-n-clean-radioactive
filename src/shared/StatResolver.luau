--!strict
--[[
	StatResolver.lua — ONE function, ONE source of truth for "what are this player's
	numbers right now".

	Every service asks this. Nothing computes gear math inline, ever.

	This is the module that prevents the single most common bug in a Roblox game of
	this shape: a perk or gamepass that works in one system and silently doesn't in
	another, because two places both tried to add up the player's bonuses. Perks,
	rebirth multipliers, pets, and gamepasses are all just more entries folded in
	here, so they cannot be applied inconsistently — there is only one place to apply
	them.

	Pure and side-effect free. Cheap enough to call every tick; cache it per-player
	per-tick if profiling ever says otherwise.

	ONE READ FROM OUTSIDE THE PROFILE: whether the Violet Aurora is up (Config/
	LuckBoost). It is a server-wide clock, not a per-player field, so it cannot ride
	on the profile -- it is read off the ReplicatedStorage attribute LuckBoostService
	writes, against the synced server clock. Still side-effect free, and still the
	only place the boost is applied, which is the point: the dig roll, the wash pad's
	roll and the odds it displays all get the same number.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = script.Parent.Config
local Tuning = require(Config.Tuning)
local Gear = require(Config.Gear)
local Liquids = require(Config.Liquids)
local WalkSpeed = require(Config.WalkSpeed)
local LuckBoost = require(Config.LuckBoost)
local GamePasses = require(Config.GamePasses)
local CashBoost = require(Config.CashBoost)
local GroupReward = require(Config.GroupReward)
local FriendBoost = require(Config.FriendBoost)
local Potions = require(Config.Potions)
local Weather = require(Config.Weather)
local IndexProgress = require(script.Parent.IndexProgress)
local Mastery = require(script.Parent.Mastery)

local StatResolver = {}

export type Profile = {
	level: number,
	gear: { [string]: number },
	perks: { [string]: boolean },
	-- Walk speed bought at the Upgrades booth (Config/WalkSpeed), on top of START_WALK.
	-- Optional for the same reason `liquids` is: Util/Spec builds fake profiles by hand
	-- and every call site predates it. Absent means "nothing bought", a real starting state.
	walkBought: number?,
	multipliers: { [string]: number }?, -- rebirth / gamepass / pet, all pre-summed
	-- The wash pad's rolled liquids (Config/Liquids). Both optional because
	-- Util/Spec builds fake profiles by hand and every existing call site predates
	-- them -- an absent pair means "on Plain Water", which is a real, correct state
	-- rather than a degraded one.
	liquids: { [string]: number }?, -- liquid id -> charges remaining
	equippedLiquid: string?,
	-- Banked seconds of the bought Lucky Clover (Config/LuckBoost). Optional for the
	-- same reason as the two above; absent means no clover running.
	luckBoostLeft: number?,
	-- Banked seconds of 2x cash from a pack (Config/CashBoost). Optional for the same
	-- reason; absent means none running.
	cashBoostLeft: number?,
	-- The index's found set (itemId -> true). Optional for the same reason; absent
	-- means no stage complete, so no index cash bonus.
	discovered: { [string]: boolean }?,
	-- The lifetime counters the masteries read (Config/Masteries, Shared/Mastery).
	-- Optional for the same reason; absent means nothing reached, every reward at base.
	stats: { [string]: number }?,
	cashEarned: number?,
	-- Permanent Robux passes owned (Config/GamePasses), key -> true. Optional for the
	-- same reason; absent means none.
	passes: { [string]: boolean }?,
	-- The group chest's one-time claim (Config/GroupReward). Optional for the same
	-- reason; absent means not claimed, no permanent cash bonus.
	groupRewardClaimed: boolean?,
	-- How many Roblox friends are in the server right now (Config/FriendBoost). LIVE,
	-- never saved: FriendBoostService sets and clears it. Absent means no friend here.
	friendBoost: number?,
	-- Banked seconds per running potion (Config/Potions), id -> seconds. Optional for
	-- the same reason; absent means none running.
	potionLeft: { [string]: number }?,
}

export type Stats = {
	-- radiation
	auraReduction: number,
	auraTolerance: number,
	levelResist: number,
	capacity: number,
	-- movement. `walkSpeed` is BOUGHT (Config/WalkSpeed) at the Upgrades booth: the
	-- studs/sec the profile's `walkBought` adds up to.
	--
	-- `stamina`, `canVault` and `canDash` USED TO BE HERE, off the Boots track. All
	-- three were resolved every tick and read by nothing at all; they went with the
	-- track (see Gear.Boots' header). Do not restore them as constants -- an inert
	-- field that every service can see is how a perk gets wired to nothing twice.
	walkSpeed: number,
	haulPenalty: number,
	-- The worn aura's walk-speed bonus as a fraction (Gear.Aura speedBonus, 0.03 = +3%).
	-- Kept OUT of `walkSpeed` so the bought number (the HUD, the picker, the
	-- leaderboard) stays the player's own; effectiveWalkSpeed applies it last.
	auraSpeedBonus: number,
	-- loop
	detectorRadius: number,
	detectorLuck: number, -- dig roll only; Config/Items.luckBias. NOT the wash pad's luck.
	detectorDepth: number,
	detectorClarity: number,
	pullSpeed: number,
	draw: number,
	maxGrip: number,
	cleanPotency: number,
	scrubRate: number,
	-- The decay clock's fuse stretch (Shared/Decay). 1 unless a profile multiplier
	-- says otherwise; the Satchel track that used to sell it is retired (Config/Gear).
	fuseMult: number,
	-- the wash pad
	liquidId: string,
	liquidPotency: number,
	liquidRate: number,
	liquidXp: number,
	effectivePotency: number,
	-- economy
	sellMultiplier: number,
	luckMultiplier: number,
	yieldMultiplier: number,
	-- 2x luck (Config/LuckBoost): 1, 2 or 4. Already folded into `luckMultiplier`;
	-- the dig roll reads it separately because dig luck is applied as a weight on
	-- Rare+ rather than on the detector's `luck` stat (Config/LuckBoost's header).
	luckBoost: number,
	-- The completed-index cash bonus (IndexProgress.cashMultiplier). Already folded
	-- into BOTH sellMultiplier and yieldMultiplier; carried on its own for display.
	indexCashMultiplier: number,
	-- MASTERY REWARDS (Config/Masteries) that land outside this function, each read by
	-- the one service that owns the number it scales. Cash, luck, bag slots and walk
	-- speed are folded into the other fields instead, so nothing downstream had to learn
	-- about them; `masteryCash` is carried on its own for display, like indexCash.
	masteryCash: number,
	bombDamageMult: number, -- BombService (the Bomber mastery x the 1.5x Bomb Damage pass; the hotbar card via MasteryBombDamage)
	radDamageMult: number, -- ExposureService: aura wear, aura failure and sickness
	mergeFeeMult: number, -- Config/Merge.fee's discount (the Reactor mastery)
	brewCooldownMult: number, -- LiquidService
	awayRate: number, -- ExhibitService's offline share of $/s
	-- GAME PASSES (Config/GamePasses) that need a field of their own. The rest fold
	-- into capacity, luckBoost, bombDamageMult and the two cash ones.
	digPower: number, -- DigService: scales the magnet's side of a haul (yank + draw)
	instantClean: boolean, -- WashService: a patch breaks the moment water touches it
	healthMult: number, -- ExposureService: max health (the 2x Health pass)
	-- The Speed Potion (Config/Potions) and the Thief mastery: multiply walk
	-- speed alongside the aura's bonus, in effectiveWalkSpeed (walkBonus). 1 when none.
	walkMult: number,
}

--- Is the server-wide Violet Aurora up right now? See the header's one outside read.
function StatResolver.luckEventActive(): boolean
	local endsAt = ReplicatedStorage:GetAttribute(LuckBoost.EVENT_ATTR)
	return type(endsAt) == "number" and endsAt > Workspace:GetServerTimeNow()
end

--- Golden Hour's cash multiplier right now (Config/Weather): GOLDEN_MULT while it is
--- up, else 1. Like luckEventActive, a read of a ReplicatedStorage attribute.
function StatResolver.goldenHourMult(): number
	return if Weather.active("golden") then Weather.GOLDEN_MULT else 1
end

local function mult(profile: Profile, key: string): number
	local m = profile.multipliers
	return if m and m[key] then m[key] else 1
end

--- The equipped liquid, but only if it is actually loaded. An id with no charges
--- left is the same thing as no id at all, and resolving that HERE rather than at
--- each call site is the whole point of this module: DeconService, CarryService and
--- the panel would otherwise each need their own copy of "...unless it ran out",
--- and the first one to forget it hands the player a free Stardust forever.
---
--- Plain Water is the floor and carries no charges (Config/Liquids), so it is
--- returned unconditionally when nothing else is live. The id comes back alongside
--- the def because "which liquid is loaded" stops agreeing with "what the equipped
--- field says" the moment charges run out, and every surface that labels the hose
--- needs the first answer, not the second.
local function liquidFor(profile: Profile): (string, Liquids.LiquidDef)
	local id = profile.equippedLiquid
	if id == nil or id == "" or not Liquids.isRollable(id) then
		return Liquids.WATER, Liquids.get(Liquids.WATER)
	end

	local charges = profile.liquids and profile.liquids[id] or 0
	if charges <= 0 then
		return Liquids.WATER, Liquids.get(Liquids.WATER)
	end
	return id, Liquids.get(id)
end

function StatResolver.get(profile: Profile): Stats
	local g = profile.gear
	local perks = profile.perks

	local detector = Gear.tier("Detector", g.detector or 1)
	local magnet = Gear.tier("Magnet", g.magnet or 1)
	local cleaner = Gear.tier("Cleaner", g.cleaner or 1)
	local aura = Gear.tier("Aura", g.aura or 1)
	-- SPEED IS BOUGHT, NOT EQUIPPED, so it is the one stat in this function that does
	-- not come out of `profile.gear` at all: Config/WalkSpeed owns the number.
	local walkSpeed = WalkSpeed.walkFor(profile.walkBought or 0)
	local luckMultiplier = Gear.luckMultiplier(g.luck or 1)
	-- The 2x Luck pass is one more source on the same boost, so it reaches the dig
	-- roll and the wash pad exactly like the aurora and the clover (Config/GamePasses).
	local luckBoost = LuckBoost.multiplier(StatResolver.luckEventActive(), (profile.luckBoostLeft or 0) > 0)
		* (if GamePasses.owns(profile, "luck") then GamePasses.LUCK else 1)
		-- The Luck Potion (Config/Potions) is one more source on the same boost.
		* Potions.multiplier(profile.potionLeft, "luck")
	-- The 2x Cash pass and a pack's timed 2x cash stack (x4), like luck's sources do.
	local passCash = (if GamePasses.owns(profile, "cash") then GamePasses.CASH else 1)
		* CashBoost.multiplier((profile.cashBoostLeft or 0) > 0)
		-- The group chest's permanent +10% (Config/GroupReward), on the same two payouts.
		* GroupReward.cashMultiplier(profile.groupRewardClaimed)
		-- Friends in the server (Config/FriendBoost), on the same two payouts.
		* FriendBoost.cashMultiplier(profile.friendBoost)
		-- The Cash Potion (Config/Potions), on the same two payouts.
		* Potions.multiplier(profile.potionLeft, "cash")
		-- Golden Hour (Config/Weather), server-wide, on the same two payouts.
		* StatResolver.goldenHourMult()
	local liquidId, liquid = liquidFor(profile)
	-- A completed stage's index pays in cash (Tuning.INDEX_COMPLETE_CASH), on every
	-- sale and every stand's income alike -- both multipliers below take it.
	local indexCash = if profile.discovered then IndexProgress.cashMultiplier(profile.discovered) else 1
	-- Masteries (Config/Masteries). Cash stacks on the index bonus like everything else
	-- that multiplies a payout.
	local masteryCash = Mastery.value(profile, "cash")

	-- Steady Hands (PLAN §9.2) is a PERK on the tool, so it belongs to the permanent
	-- capability; the liquid bonus is deliberately kept out of `cleanPotency` and
	-- surfaced separately. Two numbers, because two questions get asked of them:
	-- "what can I clean at all" (the Locker's question, and the Cleaner shop's) and
	-- "what can I clean right now" (the wash bay's).
	local cleanPotency = cleaner.power + (if perks.steadyHands then 1 else 0)

	local capacity = aura.capacity
		+ math.floor(profile.level / Tuning.CAPACITY_EVERY_N_LEVELS)
		+ Mastery.value(profile, "capacity")
		+ (if GamePasses.owns(profile, "backpack") then GamePasses.BACKPACK_SLOTS else 0)

	return {
		auraReduction = aura.reduction,
		auraTolerance = aura.tolerance,
		levelResist = math.min(profile.level * Tuning.RESIST_PER_LEVEL, Tuning.RESIST_CAP),
		capacity = capacity,

		walkSpeed = walkSpeed,
		-- Sure Footing (PLAN §9.2). Reads off the AURA now -- the perk halves the haul
		-- penalty wherever that stat lives, and it has moved tracks twice (Boots, then
		-- Satchel, then Aura) without changing what the perk means.
		haulPenalty = aura.haulPenalty * (if perks.sureFooting then 0.5 else 1),
		auraSpeedBonus = aura.speedBonus or 0,

		detectorRadius = detector.radius,
		detectorLuck = detector.luck,
		detectorDepth = detector.depth,
		-- INERT since the ping ungate (DigService.hintFor): nothing reads detectorClarity
		-- any more, so the Bloodhound perk (PLAN §9.2, +1 here) currently does nothing.
		-- Kept resolved so a repurpose does not have to re-thread it.
		detectorClarity = detector.clarity + (if perks.bloodhound then 1 else 0),
		pullSpeed = magnet.pullSpeed,
		draw = magnet.draw,
		maxGrip = magnet.maxGrip,
		cleanPotency = cleanPotency,
		-- THE MACHINE'S `volume`, UNDER THE MATH'S OWN NAME. Config/Gear renamed this
		-- column when the Cleaner track became the mast beside your tub rather than a
		-- sponge in your fist -- "how much water it throws" is what the player buys --
		-- but the thing it divides is still Contamination.secondsFor's scrub rate, and
		-- the liquid's `rateMult` multiplies it on the way in. One number, two honest
		-- names: `volume` where it is sold, `scrubRate` where it is spent. The wash bay
		-- reads it back off here to size the stream (WashService.push -> `volume`).
		-- The Cleaning Potion (Config/Potions) speeds the scrub the same way.
		scrubRate = cleaner.volume * Potions.multiplier(profile.potionLeft, "clean"),
		fuseMult = mult(profile, "fuse"),

		liquidId = liquidId,
		liquidPotency = liquid.potency,
		liquidRate = liquid.rateMult,
		liquidXp = liquid.xpMult,
		effectivePotency = cleanPotency + liquid.potency,

		sellMultiplier = mult(profile, "sell") * indexCash * masteryCash * passCash,
		-- REPURPOSED, and it used to be inert. This was `mult(profile, "luck")` alone
		-- -- the PLAN §11 "2x Luck" gamepass slot -- and nothing in the game read it,
		-- because nothing in the game rolled anything a player could influence. The
		-- wash pad does, so the Luck button's own multiplier folds in here where every
		-- other piece of gear math already lives. The gamepass multiplier stacks on
		-- top of it exactly as it was always meant to, and so does 2x luck.
		luckMultiplier = luckMultiplier * mult(profile, "luck") * luckBoost * Mastery.value(profile, "luck"),
		-- Curator (PLAN §9.2)
		yieldMultiplier = mult(profile, "yield") * (if perks.curator then 1.15 else 1) * indexCash * masteryCash * passCash,
		luckBoost = luckBoost,
		indexCashMultiplier = indexCash,

		masteryCash = masteryCash,
		bombDamageMult = Mastery.value(profile, "bombDamage")
			* (if GamePasses.owns(profile, "bombDamage") then GamePasses.BOMB_DAMAGE else 1),
		radDamageMult = Mastery.value(profile, "radDamage"),
		mergeFeeMult = Mastery.value(profile, "mergeFee"),
		brewCooldownMult = Mastery.value(profile, "brewCooldown"),
		awayRate = Mastery.value(profile, "awayRate"),

		digPower = (if GamePasses.owns(profile, "digPower") then GamePasses.DIG_POWER else 1)
			* Potions.multiplier(profile.potionLeft, "strength"),
		instantClean = GamePasses.owns(profile, "instantClean"),
		healthMult = if GamePasses.owns(profile, "health") then GamePasses.HEALTH else 1,
		-- The Thief mastery's walk speed rides on the potion's multiplier.
		walkMult = Potions.multiplier(profile.potionLeft, "speed") * (1 + Mastery.value(profile, "walkSpeed")),
	}
end

-- ── The boosts breakdown ──────────────────────────────────────────────────────

export type BoostSource = {
	name: string,
	mult: number,
	-- The attribute holding this source's end time (server time), when it runs out:
	-- on the Player, or on ReplicatedStorage when `global`. Absent = permanent.
	timer: string?,
	global: boolean?,
}

export type Boost = {
	key: string,
	label: string,
	total: number,
	sources: { BoostSource },
}

-- Rows that show even at x1, so a fresh player can see where luck and cash stand.
StatResolver.ALWAYS_SHOWN = { luck = true, cash = true }

--- EVERY MULTIPLIER, SOURCE BY SOURCE, for the bottom-right Boosts widget
--- (BoostsController). Players stack potions, passes, the aurora and the clover and
--- lose track of what their luck actually is; this answers it with the same numbers
--- `get` folds in, from the same helpers, so the widget cannot disagree with the dig
--- roll (Spec checks each total against `get`).
---
--- `total` is the product of `sources`; a source at x1 is left out. Only what a
--- player would call a boost is here -- Luck is `luckBoost` (digs AND the wash pad),
--- not the wash-only gear button.
function StatResolver.boosts(profile: Profile): { Boost }
	local stats = StatResolver.get(profile)
	local list: { Boost } = {}

	local function add(key: string, label: string, sources: { BoostSource })
		local kept = {}
		local total = 1
		for _, source in sources do
			if math.abs(source.mult - 1) > 1e-9 then
				table.insert(kept, source)
				total *= source.mult
			end
		end
		table.insert(list, { key = key, label = label, total = total, sources = kept })
	end

	local function pass(key: string, mult: number): number
		return if GamePasses.owns(profile, key) then mult else 1
	end

	local function potion(id: string): BoostSource
		return { name = Potions.get(id).name, mult = Potions.multiplier(profile.potionLeft, id), timer = Potions.attrFor(id) }
	end

	add("luck", "Luck", {
		{
			name = LuckBoost.EVENT_NAME,
			mult = if StatResolver.luckEventActive() then LuckBoost.MULT else 1,
			timer = LuckBoost.EVENT_ATTR,
			global = true,
		},
		{ name = "Lucky Clover", mult = if (profile.luckBoostLeft or 0) > 0 then LuckBoost.MULT else 1, timer = LuckBoost.PERSONAL_ATTR },
		{ name = "2x Luck Pass", mult = pass("luck", GamePasses.LUCK) },
		potion("luck"),
	})
	add("cash", "Cash", {
		{ name = "2x Cash Pass", mult = pass("cash", GamePasses.CASH) },
		{ name = "2x Cash Boost", mult = CashBoost.multiplier((profile.cashBoostLeft or 0) > 0), timer = CashBoost.PERSONAL_ATTR },
		potion("cash"),
		{ name = Weather.DEFS.golden.name, mult = StatResolver.goldenHourMult(), timer = Weather.DEFS.golden.endsAttr, global = true },
		{ name = "Group Bonus", mult = GroupReward.cashMultiplier(profile.groupRewardClaimed) },
		{ name = "Friend Boost", mult = FriendBoost.cashMultiplier(profile.friendBoost) },
		{ name = "Index Complete", mult = stats.indexCashMultiplier },
		{ name = "Masteries", mult = stats.masteryCash },
	})
	add("speed", "Walk Speed", {
		{ name = "Aura", mult = 1 + stats.auraSpeedBonus },
		potion("speed"),
		{ name = "Masteries", mult = 1 + Mastery.value(profile, "walkSpeed") },
	})
	add("strength", "Dig Power", {
		{ name = "2x Dig Power Pass", mult = pass("digPower", GamePasses.DIG_POWER) },
		potion("strength"),
	})
	add("clean", "Wash Speed", { potion("clean") })
	add("bomb", "Bomb Damage", {
		{ name = "1.5x Bomb Damage Pass", mult = pass("bombDamage", GamePasses.BOMB_DAMAGE) },
		{ name = "Masteries", mult = Mastery.value(profile, "bombDamage") },
	})
	add("health", "Health", { { name = "2x Health Pass", mult = stats.healthMult } })

	return list
end

--- Movement speed after the haul penalty. PLAN §5.1: carrying hot items should
--- physically slow you, which is what turns capacity from a bigger number into
--- a decision.
---
--- UNCHANGED BY THE BOOTS RETIREMENT OR THE TREADMILL'S, which is why speed is wired
--- into `walkSpeed` rather than added as a separate bonus anywhere downstream. Speed
--- moved to Config/WalkSpeed and the penalty to Gear.Aura underneath this function and
--- it did not have to notice, so neither did ExposureService's tick loop, still the
--- only thing in the game that writes Humanoid.WalkSpeed.
---
--- `picked` is the walk-speed picker's cap (profile `walkCap`, WalkSpeed.chosenWalk). It
--- trims the bought speed BEFORE the haul penalty, so a full bag still slows you down
--- from the speed you chose. The worn aura's `speedBonus` and the Speed Potion multiply
--- the result last (walkBonus).
--- Every multiplier on top of the chosen walk: the worn aura's bonus and the Speed
--- Potion (Config/Potions). The Walk Speed badge prints the chosen walk times this.
function StatResolver.walkBonus(stats: Stats): number
	return (1 + stats.auraSpeedBonus) * (stats.walkMult or 1)
end

function StatResolver.effectiveWalkSpeed(stats: Stats, carriedCount: number, sprinting: boolean, picked: number?): number
	local speed = WalkSpeed.chosenWalk(stats.walkSpeed, picked) - (carriedCount * stats.haulPenalty)
	-- The aura's bonus and the Speed Potion ride on what is left, so a slowed-down pick
	-- or a full bag is still scaled by them rather than handed a flat top-up.
	speed *= StatResolver.walkBonus(stats)
	if sprinting then
		speed *= Gear.SPRINT_MULTIPLIER
	end
	return math.max(6, speed) -- never fully immobilise a player
end

return StatResolver
