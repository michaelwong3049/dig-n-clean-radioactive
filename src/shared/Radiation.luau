--!strict
--[[
	Radiation.lua — PURE MATH. No state, no services, no RunService.

	This module is `require`d by BOTH the server (authority) and the client
	(prediction + the SURVIVABLE countdown in PLAN §3.5). That is the whole point of
	putting it in Shared: the number on the player's HUD and the number the server
	kills them with are produced by the same function, so they can never disagree.

	The server still owns the truth. The client is only allowed to *display* it.

	── TWO SOURCES, TWO SHIELDS, TWO FAILURE STATES ──────────────────────────────

	The design has two different ways to die and they must not bleed into each other
	(PLAN §14: green screen vs white screen). This module keeps them separate by
	construction:

	    AMBIENT (the stage)   -> shielded by the AURA            -> can cause BURN  (white)
	    CARRIED (your loot)  -> shielded by LEVEL RESIST only  -> only fills EXPOSURE (green)

	Two consequences worth stating out loud, because both were bugs in the first draft:

	1. Aura tolerance is checked against AMBIENT ONLY. If carried emission counted
	   toward burn, a full backpack would trigger aura failure inside your own rated
	   stage — the white-screen "you should not be here" state firing while you are
	   exactly where you should be. Nonsense, and it collapses two clear signals
	   into one muddy one.

	2. The aura does NOT shield you from your own backpack. The loot is inside the
	   aura with you. If aura reduction applied to carried emission, a Lead Halo
	   aura would erase 99.2% of a screaming Legendary and the greed dial (§3.3) —
	   the single mechanic the whole game is built on — would stop working the
	   moment you bought a mid-tier aura.

	The Satchel track (§3.7) used to sell a partial shield against your own loot.
	It is retired (Config/Gear's RETIRED block), so the bag's rads now meet only
	level resist -- exactly what the free Canvas Bag always gave you. Rule 2 above
	still stands on its own: the aura never shields what you are carrying.
]]

local Config = script.Parent.Config
local Gear = require(Config.Gear)
local Stages = require(Config.Stages)
local Tuning = require(Config.Tuning)

local Radiation = {}

export type Stats = {
	auraReduction: number, -- fraction of AMBIENT rads blocked
	auraTolerance: number, -- ambient rads/sec before the aura fails
	levelResist: number, -- 0..RESIST_CAP, applies to both
}

export type Reading = {
	ambient: number, -- raw stage rads/sec, before the aura
	carried: number, -- raw backpack rads/sec, before level resist
	net: number, -- rads/sec actually accumulating on the exposure meter
	excess: number, -- ambient rads/sec past aura tolerance (0 = aura holding); 0 with a Zone
	healthBurn: number, -- HP/sec from the aura FAILING (white)
	drain: number, -- HP/sec of rated-aura wear: the aura holding, but not forever (green)
	over: number, -- 0..1, how far out of its depth the aura is (0 = holding)
	failing: boolean, -- true = white-screen state, NOT the green one
}

--- Where a player stands, for the zone survival curve. Without one, resolve falls
--- back to the old tolerance burn (kept for the offline tuning reports).
export type Zone = {
	stageId: number,
	depthFrac: number, -- 0 = the stage's entrance edge, 1 = its far edge
	auraTier: number,
	maxHealth: number,
}

-- ── The zone survival curve (Tuning.ZONE_SURVIVAL) ─────────────────────────

--- Geometric blend: equal steps of `t` multiply the time by equal factors, so the
--- drain climbs smoothly with no knee you can feel.
local function blend(a: number, b: number, t: number): number
	return a * (b / a) ^ math.clamp(t, 0, 1)
end

--- { entrance, BREAK, far edge } -> seconds at `depthFrac`.
local function along(points: { number }, depthFrac: number): number
	local d = math.clamp(depthFrac, 0, 1)
	local brk = Tuning.ZONE_SURVIVAL.BREAK
	if d <= brk then
		return blend(points[1], points[2], d / brk)
	end
	return blend(points[2], points[3], (d - brk) / (1 - brk))
end

--- "over" | "rated" | "raid" | "under" | "wayUnder" | "lastAura" | nil (an aura more tiers
--- above the stage's rating than Tuning.ZONE_SURVIVAL.OVER covers takes no damage).
function Radiation.zoneCase(stageId: number, auraTier: number): string?
	local rated = Stages.get(stageId).ratedAuraTier
	local gap = rated - auraTier
	if gap < -#Tuning.ZONE_SURVIVAL.OVER then
		return nil
	elseif gap <= -1 then
		return "over"
	elseif gap == 0 then
		return if Tuning.ZONE_SURVIVAL.RAID[stageId] then "raid" else "rated"
	elseif gap == 1 and rated > #Gear.Aura and auraTier == #Gear.Aura then
		return "lastAura"
	elseif gap == 1 then
		return "under"
	end
	return "wayUnder"
end

local function curveSurvival(stageId: number, depthFrac: number, auraTier: number): number
	local Z = Tuning.ZONE_SURVIVAL
	local case = Radiation.zoneCase(stageId, auraTier)
	if case == nil then
		return math.huge
	elseif case == "lastAura" then
		return along(Z.lastAura, depthFrac)
	elseif case == "raid" then
		return along(Z.RAID[stageId], depthFrac)
	end
	local band = if stageId >= Z.HARSH_FROM_STAGE then Z.late else Z.early
	if case == "over" then
		local tiersOver = auraTier - Stages.get(stageId).ratedAuraTier
		return along(band.rated, depthFrac) * Z.OVER[tiersOver]
	end
	-- A band with its own `grace` row fades it with depth; otherwise it is flat.
	local grace = if band.grace then along(band.grace, depthFrac) else Z.UNDER_GRACE
	if case == "wayUnder" then
		return Z.wayUnder + grace
	end
	local seconds = along(band[case], depthFrac)
	return if case == "under" then seconds + grace + Z.UNDER_EXTRA else seconds
end

--- Seconds a full health bar lasts in the stage's dead zone (Tuning.ZONE_SURVIVAL
--- DEAD_ZONE), or nil when this spot isn't in one or the aura is over the stage's
--- rating. Starts at the normal curve's own time on the line, so there is no jump,
--- and falls geometrically to `edge` at the far edge.
function Radiation.deadZone(stageId: number, depthFrac: number, auraTier: number): number?
	local dz = Tuning.ZONE_SURVIVAL.DEAD_ZONE[stageId]
	local case = Radiation.zoneCase(stageId, auraTier)
	if dz == nil or depthFrac < dz.from or case == nil or case == "over" then
		return nil
	end
	local onLine = curveSurvival(stageId, dz.from, auraTier)
	return blend(onLine, math.min(dz.edge, onLine), (depthFrac - dz.from) / (1 - dz.from))
end

--- Seconds a FULL health bar lasts against the aura's share of the damage here.
--- math.huge when the aura is more tiers over the stage than ZONE_SURVIVAL.OVER covers.
function Radiation.zoneSurvival(stageId: number, depthFrac: number, auraTier: number): number
	local seconds = curveSurvival(stageId, depthFrac, auraTier)
	local dead = Radiation.deadZone(stageId, depthFrac, auraTier)
	return if dead then math.min(seconds, dead) else seconds
end

--- 0..1 out-of-depth grade for the HUD/RadFx: 0 at the gentlest under-tier time
--- (~80s with the grace and UNDER_EXTRA), 1 at the way-under floor (~21s). 0 whenever
--- the aura is not failing.
local function overGrade(seconds: number): number
	local Z = Tuning.ZONE_SURVIVAL
	local top = Z.early.under[1] + Z.UNDER_GRACE + Z.UNDER_EXTRA
	local bottom = Z.wayUnder + Z.UNDER_GRACE
	return math.clamp(math.log(top / seconds) / math.log(top / bottom), 0, 1)
end

--- The core resolve. Everything on the HUD and every tick of the exposure meter
--- comes out of this one function.
function Radiation.resolve(ambient: number, carried: number, stats: Stats, zone: Zone?): Reading
	local resist = 1 - math.clamp(stats.levelResist, 0, Tuning.RESIST_CAP)

	local fromStage = ambient * (1 - math.clamp(stats.auraReduction, 0, 1)) * resist
	local fromBag = carried * resist
	local net = fromStage + fromBag

	if zone then
		local seconds = Radiation.zoneSurvival(zone.stageId, zone.depthFrac, zone.auraTier)
		local case = Radiation.zoneCase(zone.stageId, zone.auraTier)
		local perSec = if seconds == math.huge then 0 else zone.maxHealth / seconds
		-- Rated and over wear is the aura HOLDING, so it stays green; everything under is failing,
		-- and so is the rated aura in a dead zone (white screen, UPGRADE AURA warning) and
		-- the stage's own aura in a raid stage (Tuning.ZONE_SURVIVAL.RAID).
		local dead = Radiation.deadZone(zone.stageId, zone.depthFrac, zone.auraTier) ~= nil
		local failing = case ~= nil and case ~= "over" and (case ~= "rated" or dead)
		return {
			ambient = ambient,
			carried = carried,
			net = net,
			excess = 0,
			healthBurn = if failing then perSec else 0,
			drain = if failing then 0 else perSec,
			over = if failing then overGrade(seconds) else 0,
			failing = failing,
		}
	end

	-- AMBIENT ONLY. See the header.
	local excess = math.max(0, ambient - stats.auraTolerance)
	local healthBurn = if excess > 0 then Tuning.BURN_COEF * (excess ^ Tuning.BURN_EXPONENT) else 0

	return {
		ambient = ambient,
		carried = carried,
		net = net,
		excess = excess,
		healthBurn = healthBurn,
		drain = 0,
		over = if excess > 0 then math.clamp(excess / math.max(stats.auraTolerance, 0.5) / 3, 0, 1) else 0,
		failing = excess > 0,
	}
end

--- Stage rads/sec, including any hot pocket the player is standing in (PLAN §4).
function Radiation.ambientAt(stageBaseRads: number, hotPocketMult: number?): number
	return stageBaseRads * (hotPocketMult or 1)
end

--- Seconds until a filling meter kills you: the time to fill it, plus the heavy
--- full-meter sickness taking a full health bar (1 / SICKNESS_FULL_METER). An
--- estimate on purpose: it ignores the lighter 80%+ drain on the way up, which the
--- server's live clock already takes the min against (ExposureService).
local function toFullMeterDeath(reading: Reading, exposure: number): number
	if reading.net <= 1e-6 and exposure < Tuning.EXPOSURE_CAP then
		return math.huge
	end
	local toFull = math.max(0, Tuning.EXPOSURE_CAP - exposure) / math.max(reading.net, 1e-6)
	return toFull + 1 / Tuning.SICKNESS_FULL_METER
end

--- Seconds until the player goes down, from either cause. This is the number that
--- renders as `SURVIVABLE: 0:14` (PLAN §3.5).
---
--- Returning the honest number is a deliberate design choice: a gamble where you
--- cannot see the odds is a trap, and traps make people quit.
function Radiation.survivableSeconds(reading: Reading, exposure: number, health: number): number
	local toBlackout = toFullMeterDeath(reading, exposure)
	local hpLoss = reading.healthBurn + reading.drain
	local toBurnout = if hpLoss > 1e-6 then health / hpLoss else math.huge
	return math.min(toBlackout, toBurnout)
end

--- Which of the two failure states is actually closer. The HUD uses this to pick
--- its colour language: burn is white, exposure is green. PLAN §14.
function Radiation.dominantThreat(reading: Reading, exposure: number, health: number): string?
	local toBlackout = toFullMeterDeath(reading, exposure)
	local toBurnout = if reading.healthBurn > 1e-6 then health / reading.healthBurn else math.huge
	if toBlackout == math.huge and toBurnout == math.huge then
		return nil
	end
	return if toBurnout < toBlackout then "burn" else "exposure"
end

--- How much of the player's incoming rads is coming from their own greed rather
--- than from the world. Drives the "drop something" nudge in the HUD, and is the
--- cleanest single number for telemetry on whether §3.3 is actually working.
function Radiation.greedFraction(reading: Reading, stats: Stats): number
	local fromBag = reading.carried * (1 - math.clamp(stats.levelResist, 0, Tuning.RESIST_CAP))
	return if reading.net > 1e-6 then math.clamp(fromBag / reading.net, 0, 1) else 0
end

--- HP/sec lost to radiation sickness at a given meter fraction (0..1). Zero below
--- SICKNESS_DRAIN_AT, then a straight ramp up to SICKNESS_DRAIN_MAX, then a full
--- meter jumps to SICKNESS_FULL_METER of `maxHealth` per second (heavy damage).
--- The caller decides WHERE it applies (stages only, see Tuning).
function Radiation.sicknessDrain(exposureFrac: number, maxHealth: number): number
	if exposureFrac < Tuning.SICKNESS_DRAIN_AT then
		return 0
	end
	if exposureFrac >= 1 then
		return maxHealth * Tuning.SICKNESS_FULL_METER
	end
	local t = math.clamp((exposureFrac - Tuning.SICKNESS_DRAIN_AT) / (1 - Tuning.SICKNESS_DRAIN_AT), 0, 1)
	return Tuning.SICKNESS_DRAIN_MIN + (Tuning.SICKNESS_DRAIN_MAX - Tuning.SICKNESS_DRAIN_MIN) * t
end

--- 0 = clean, 1 = a full meter (heavy sickness). Drives the vignette and the audio bed.
function Radiation.exposureFraction(exposure: number): number
	return math.clamp(exposure / Tuning.EXPOSURE_CAP, 0, 1)
end

return Radiation
