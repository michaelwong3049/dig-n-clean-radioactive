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
local Treadmill = require(Config.Treadmill)
local LuckBoost = require(Config.LuckBoost)

local StatResolver = {}

export type Profile = {
	level: number,
	gear: { [string]: number },
	perks: { [string]: boolean },
	-- The treadmill (Config/Treadmill). `speedPoints` is lifetime Speed, `treadmill`
	-- the belt rung owned. Both optional for the same reason `liquids` is: Util/Spec builds
	-- fake profiles by hand and every call site predates them. Absent means "untrained,
	-- on the free belt" -- a real starting state, not a degraded one.
	speedPoints: number?,
	treadmill: number?,
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
}

export type Stats = {
	-- radiation
	suitReduction: number,
	suitTolerance: number,
	levelResist: number,
	capacity: number,
	-- movement. `walkSpeed` is TRAINED (Config/Treadmill), not bought: it is the
	-- studs/sec of the speed level the player's lifetime `speedPoints` has reached.
	-- `speedProgress` is how far toward the next level's requirement they are (0..1),
	-- carried here rather than recomputed so nothing owns a second copy of the curve.
	--
	-- `stamina`, `canVault` and `canDash` USED TO BE HERE, off the Boots track. All
	-- three were resolved every tick and read by nothing at all; they went with the
	-- track (see Gear.Boots' header). Do not restore them as constants -- an inert
	-- field that every service can see is how a perk gets wired to nothing twice.
	walkSpeed: number,
	speedProgress: number,
	haulPenalty: number,
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
}

--- Is the server-wide Violet Aurora up right now? See the header's one outside read.
function StatResolver.luckEventActive(): boolean
	local endsAt = ReplicatedStorage:GetAttribute(LuckBoost.EVENT_ATTR)
	return type(endsAt) == "number" and endsAt > Workspace:GetServerTimeNow()
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
	local suit = Gear.tier("Suit", g.suit or 1)
	-- SPEED IS TRAINED, NOT EQUIPPED, so it is the one stat in this function that does
	-- not come out of `profile.gear` at all. The Boots track that used to answer this
	-- is retired (Gear.Boots' header); Config/Treadmill owns the number now.
	local walkSpeed, speedProgress = Treadmill.walkFor(profile.speedPoints or 0)
	local luckMultiplier = Gear.luckMultiplier(g.luck or 1)
	local luckBoost = LuckBoost.multiplier(StatResolver.luckEventActive(), (profile.luckBoostLeft or 0) > 0)
	local liquidId, liquid = liquidFor(profile)

	-- Steady Hands (PLAN §9.2) is a PERK on the tool, so it belongs to the permanent
	-- capability; the liquid bonus is deliberately kept out of `cleanPotency` and
	-- surfaced separately. Two numbers, because two questions get asked of them:
	-- "what can I clean at all" (the Locker's question, and the Cleaner shop's) and
	-- "what can I clean right now" (the wash bay's).
	local cleanPotency = cleaner.power + (if perks.steadyHands then 1 else 0)

	local capacity = suit.capacity + math.floor(profile.level / Tuning.CAPACITY_EVERY_N_LEVELS)

	return {
		suitReduction = suit.reduction,
		suitTolerance = suit.tolerance,
		levelResist = math.min(profile.level * Tuning.RESIST_PER_LEVEL, Tuning.RESIST_CAP),
		capacity = capacity,

		walkSpeed = walkSpeed,
		speedProgress = speedProgress,
		-- Sure Footing (PLAN §9.2). Reads off the SUIT now -- the perk halves the haul
		-- penalty wherever that stat lives, and it has moved tracks twice (Boots, then
		-- Satchel, then Suit) without changing what the perk means.
		haulPenalty = suit.haulPenalty * (if perks.sureFooting then 0.5 else 1),

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
		scrubRate = cleaner.volume,
		fuseMult = mult(profile, "fuse"),

		liquidId = liquidId,
		liquidPotency = liquid.potency,
		liquidRate = liquid.rateMult,
		liquidXp = liquid.xpMult,
		effectivePotency = cleanPotency + liquid.potency,

		sellMultiplier = mult(profile, "sell"),
		-- REPURPOSED, and it used to be inert. This was `mult(profile, "luck")` alone
		-- -- the PLAN §11 "2x Luck" gamepass slot -- and nothing in the game read it,
		-- because nothing in the game rolled anything a player could influence. The
		-- wash pad does, so the Luck button's own multiplier folds in here where every
		-- other piece of gear math already lives. The gamepass multiplier stacks on
		-- top of it exactly as it was always meant to, and so does 2x luck.
		luckMultiplier = luckMultiplier * mult(profile, "luck") * luckBoost,
		-- Curator (PLAN §9.2)
		yieldMultiplier = mult(profile, "yield") * (if perks.curator then 1.15 else 1),
		luckBoost = luckBoost,
	}
end

--- Movement speed after the haul penalty. PLAN §5.1: carrying hot items should
--- physically slow you, which is what turns capacity from a bigger number into
--- a decision.
---
--- UNCHANGED BY THE BOOTS RETIREMENT, which is the whole reason the treadmill was
--- wired into `walkSpeed` rather than added as a separate bonus anywhere downstream.
--- Both halves moved tracks underneath this function -- speed to Config/Treadmill,
--- the penalty to Gear.Suit -- and it did not have to notice, so neither did
--- ExposureService's tick loop, still the only thing in the game that writes
--- Humanoid.WalkSpeed.
function StatResolver.effectiveWalkSpeed(stats: Stats, carriedCount: number, sprinting: boolean): number
	local speed = stats.walkSpeed - (carriedCount * stats.haulPenalty)
	if sprinting then
		speed *= Gear.SPRINT_MULTIPLIER
	end
	return math.max(6, speed) -- never fully immobilise a player
end

return StatResolver
