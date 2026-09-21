--!strict
--[[
	Detonation.luau — PURE MATH for the pull fuse and the craters it leaves (numbers in
	Config/Detonation). No state, no services, no instances.

	Shared for the reason Radiation and Decay are: the server decides when a nuke arms,
	when it goes off and how hard a crater burns, and the client draws the fuse bar, the
	shrinking orb and the countdown. If those were two copies of the arithmetic, the
	orb's visible edge and the edge that actually burns would drift apart -- and a hazard
	you cannot read is a trap.
]]

local Config = script.Parent.Config
local Cfg = require(Config.Detonation)
local Tuning = require(Config.Tuning)
local Gear = require(Config.Gear)
local Weight = require(Config.Weight)

local Detonation = {}

export type Blast = {
	hit: number,
	blastRadius: number,
	orbRadius: number,
	orbBurn: number,
	orbLife: number,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ── The fuse ───────────────────────────────────────────────────────────

--- The cheapest magnet rated for this soil (maxGrip >= soil), or the top tier if the
--- soil outclasses the whole track. The fairness floor is sized off this, never off
--- the player's own magnet -- see Config/Detonation.
function Detonation.ratedMagnet(soil: number): any
	for index = 1, Gear.maxTier("Magnet") do
		local magnet = Gear.tier("Magnet", index)
		if magnet.maxGrip >= soil then
			return magnet
		end
	end
	return Gear.tier("Magnet", Gear.maxTier("Magnet"))
end

--- Pull-seconds per second the rated magnet makes at REF_CPS (DigService's tick,
--- with gripEff = 1).
function Detonation.refPullRate(soil: number): number
	local magnet = Detonation.ratedMagnet(soil)
	return (magnet.draw - Tuning.PULL_DRAG_RATE) + Cfg.REF_CPS * Tuning.PULL_YANK_PER_CLICK * magnet.pullSpeed
end

--- The pull's rope length (`required` in DigService) as the RATED magnet sees it:
--- depth times the weight factor, with the home-turf Common ease -- which a rated
--- magnet always gets. Mirrors DigService exactly; Spec pulls against the same sum.
function Detonation.ratedRope(rarity: string, kg: number, depth: number): number
	local rope = Tuning.PULL_SECONDS_PER_STUD * depth * Weight.pullFactor(kg)
	if rarity == "Common" then
		rope *= Tuning.PULL_HOME_COMMON_EASE
	end
	return rope
end

--- The rarity/weight window alone, before the fairness floor.
function Detonation.baseWindow(rarity: string, kg: number): number
	local mult = Cfg.RARITY_WINDOW[rarity] or 1
	local heft = Weight.pullFactor(kg) / Weight.pullFactor(Cfg.WEIGHT_REF_KG)
	return Cfg.BASE_WINDOW * mult * heft ^ Cfg.WEIGHT_WINDOW_EXP
end

--- Seconds from lock-on to detonation for this nuke, in this soil, buried this deep.
--- The rarity/weight window, lifted where needed so the rated magnet at REF_CPS lands
--- it by SAFE_AT (Config/Detonation, "The fairness floor").
function Detonation.windowFor(rarity: string, kg: number, depth: number, soil: number): number
	local window = Detonation.baseWindow(rarity, kg)
	local rate = Detonation.refPullRate(soil)
	if rate > 0 then
		window = math.max(window, Detonation.ratedRope(rarity, kg, depth) / rate / Cfg.SAFE_AT)
	end
	return window
end

--- One tick of a fuse. `burning` is true while anybody's magnet is on it OR once it
--- has armed (an armed fuse never cools). Otherwise it cools at COOL_RATE.
function Detonation.stepHeat(heat: number, dt: number, window: number, burning: boolean): number
	if window <= 0 then
		return heat
	end
	if burning then
		return heat + dt / window
	end
	return math.max(0, heat - dt * Cfg.COOL_RATE / window)
end

function Detonation.isArmed(heat: number): boolean
	return heat >= Cfg.ARM_AT
end

--- Seconds until a burning fuse reaches 1.
function Detonation.secondsLeft(heat: number, window: number): number
	return math.max(0, (1 - heat) * window)
end

-- ── The blast ──────────────────────────────────────────────────────────

--- Radius multiplier for how big the nuke looked (Config/Detonation, SIZE_*).
function Detonation.sizeMult(visualScale: number): number
	local ratio = math.max(visualScale, 0.01) / Cfg.SIZE_REF
	return math.clamp(ratio ^ Cfg.SIZE_EXP, Cfg.SIZE_MIN, Cfg.SIZE_MAX)
end

--- Everything a detonation does, for this rarity at this visual scale.
function Detonation.blastFor(rarity: string, visualScale: number): Blast
	local def = Cfg.BLAST[rarity] or Cfg.BLAST.Common
	local size = Detonation.sizeMult(visualScale)
	local orbRadius = def.orbRadius * size
	return {
		hit = def.hit,
		blastRadius = orbRadius * Cfg.BLAST_REACH,
		orbRadius = orbRadius,
		orbBurn = def.orbBurn,
		orbLife = def.orbLife,
	}
end

--- Health taken off someone `distance` studs from ground zero, once.
function Detonation.hitAt(distance: number, blast: Blast): number
	if distance > blast.blastRadius then
		return 0
	end
	return blast.hit * lerp(1, Cfg.BLAST_EDGE, distance / blast.blastRadius)
end

--- Knockback (horizontal speed, lift) in studs/sec at this distance; zero past the rim.
function Detonation.knockbackAt(distance: number, blastRadius: number): (number, number)
	if blastRadius <= 0 or distance > blastRadius then
		return 0, 0
	end
	local falloff = 1 - distance / blastRadius
	return Cfg.KNOCKBACK_SPEED * falloff, Cfg.KNOCKBACK_LIFT * falloff
end

-- ── The crater ─────────────────────────────────────────────────────────

--- 0..1: how much of an orb is left `age` seconds into a `life`-second lifetime. Full
--- until ORB_FADE_FROM, then linear down to nothing. Radius AND heat both scale by it.
function Detonation.orbStrength(age: number, life: number): number
	if life <= 0 or age >= life then
		return 0
	end
	local fadeFrom = life * Cfg.ORB_FADE_FROM
	if age <= fadeFrom then
		return 1
	end
	return 1 - (age - fadeFrom) / (life - fadeFrom)
end

--- The orb's radius right now.
function Detonation.orbRadiusAt(orbRadius: number, strength: number): number
	return orbRadius * strength
end

--- Health/sec at `distance` studs from the orb's centre.
function Detonation.orbBurnAt(distance: number, orbRadius: number, orbBurn: number, strength: number): number
	local radius = Detonation.orbRadiusAt(orbRadius, strength)
	if radius <= 0 or distance > radius then
		return 0
	end
	return orbBurn * strength * lerp(1, Cfg.ORB_EDGE, distance / radius)
end

return Detonation
