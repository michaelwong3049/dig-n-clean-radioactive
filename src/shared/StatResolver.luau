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
]]

local Config = script.Parent.Config
local Tuning = require(Config.Tuning)
local Gear = require(Config.Gear)

local StatResolver = {}

export type Profile = {
	level: number,
	gear: { [string]: number },
	perks: { [string]: boolean },
	multipliers: { [string]: number }?, -- rebirth / gamepass / pet, all pre-summed
}

export type Stats = {
	-- radiation
	suitReduction: number,
	suitTolerance: number,
	satchelShielding: number,
	levelResist: number,
	capacity: number,
	-- movement
	walkSpeed: number,
	haulPenalty: number,
	stamina: number,
	canVault: boolean,
	canDash: boolean,
	-- loop
	detectorRadius: number,
	detectorMaxRarity: number,
	detectorDepth: number,
	detectorClarity: number,
	pullSpeed: number,
	maxGrip: number,
	cleanPotency: number,
	scrubRate: number,
	satchelFuseMult: number,
	-- economy
	sellMultiplier: number,
	luckMultiplier: number,
	yieldMultiplier: number,
}

local function mult(profile: Profile, key: string): number
	local m = profile.multipliers
	return if m and m[key] then m[key] else 1
end

function StatResolver.get(profile: Profile): Stats
	local g = profile.gear
	local perks = profile.perks

	local detector = Gear.tier("Detector", g.detector or 1)
	local magnet = Gear.tier("Magnet", g.magnet or 1)
	local cleaner = Gear.tier("Cleaner", g.cleaner or 1)
	local suit = Gear.tier("Suit", g.suit or 1)
	local boots = Gear.tier("Boots", g.boots or 1)
	local satchel = Gear.tier("Satchel", g.satchel or 1)

	local capacity = suit.capacity + math.floor(profile.level / Tuning.CAPACITY_EVERY_N_LEVELS)

	return {
		suitReduction = suit.reduction,
		suitTolerance = suit.tolerance,
		satchelShielding = satchel.shielding,
		levelResist = math.min(profile.level * Tuning.RESIST_PER_LEVEL, Tuning.RESIST_CAP),
		capacity = capacity,

		walkSpeed = boots.walkSpeed,
		-- Sure Footing (PLAN §9.2)
		haulPenalty = boots.haulPenalty * (if perks.sureFooting then 0.5 else 1),
		stamina = boots.stamina,
		canVault = boots.canVault,
		canDash = boots.canDash,

		detectorRadius = detector.radius,
		detectorMaxRarity = detector.maxRarity,
		detectorDepth = detector.depth,
		-- Bloodhound (PLAN §9.2)
		detectorClarity = detector.clarity + (if perks.bloodhound then 1 else 0),
		pullSpeed = magnet.pullSpeed,
		maxGrip = magnet.maxGrip,
		-- Steady Hands (PLAN §9.2)
		cleanPotency = cleaner.potency + (if perks.steadyHands then 1 else 0),
		scrubRate = cleaner.scrubRate,
		satchelFuseMult = satchel.fuseMult * mult(profile, "fuse"),

		sellMultiplier = mult(profile, "sell"),
		luckMultiplier = mult(profile, "luck"),
		-- Curator (PLAN §9.2)
		yieldMultiplier = mult(profile, "yield") * (if perks.curator then 1.15 else 1),
	}
end

--- Movement speed after the haul penalty. PLAN §5.1: carrying hot items should
--- physically slow you, which is what turns capacity from a bigger number into
--- a decision.
function StatResolver.effectiveWalkSpeed(stats: Stats, carriedCount: number, sprinting: boolean): number
	local speed = stats.walkSpeed - (carriedCount * stats.haulPenalty)
	if sprinting then
		speed *= Gear.SPRINT_MULTIPLIER
	end
	return math.max(6, speed) -- never fully immobilise a player
end

return StatResolver
