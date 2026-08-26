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

	    AMBIENT (the stage)   -> shielded by the SUIT     -> can cause BURN  (white)
	    CARRIED (your loot)  -> shielded by the SATCHEL  -> only fills EXPOSURE (green)

	Two consequences worth stating out loud, because both were bugs in the first draft:

	1. Suit tolerance is checked against AMBIENT ONLY. If carried emission counted
	   toward burn, a full backpack would trigger suit failure inside your own rated
	   stage — the white-screen "you should not be here" state firing while you are
	   exactly where you should be. Nonsense, and it collapses two clear signals
	   into one muddy one.

	2. The suit does NOT shield you from your own backpack. The loot is inside the
	   suit with you. If suit reduction applied to carried emission, a Lead-Lined
	   suit would erase 99.2% of a screaming Legendary and the greed dial (§3.3) —
	   the single mechanic the whole game is built on — would stop working the
	   moment you bought a mid-tier suit.

	That second point is what gives the Satchel track (§3.7) its real job. It was
	only slowing the decay clock; it should also be the thing standing between you
	and what you are carrying.
]]

local Config = script.Parent.Config
local Tuning = require(Config.Tuning)

local Radiation = {}

export type Stats = {
	suitReduction: number, -- fraction of AMBIENT rads blocked
	suitTolerance: number, -- ambient rads/sec before the suit fails
	satchelShielding: number, -- fraction of CARRIED rads blocked
	levelResist: number, -- 0..RESIST_CAP, applies to both
}

export type Reading = {
	ambient: number, -- raw stage rads/sec, before the suit
	carried: number, -- raw backpack rads/sec, before the satchel
	net: number, -- rads/sec actually accumulating on the exposure meter
	excess: number, -- ambient rads/sec past suit tolerance (0 = suit holding)
	healthBurn: number, -- HP/sec
	failing: boolean, -- true = white-screen state, NOT the green one
}

--- The core resolve. Everything on the HUD and every tick of the exposure meter
--- comes out of this one function.
function Radiation.resolve(ambient: number, carried: number, stats: Stats): Reading
	local resist = 1 - math.clamp(stats.levelResist, 0, Tuning.RESIST_CAP)

	local fromStage = ambient * (1 - math.clamp(stats.suitReduction, 0, 1)) * resist
	local fromBag = carried * (1 - math.clamp(stats.satchelShielding, 0, 1)) * resist

	-- AMBIENT ONLY. See the header.
	local excess = math.max(0, ambient - stats.suitTolerance)
	local healthBurn = if excess > 0 then Tuning.BURN_COEF * (excess ^ Tuning.BURN_EXPONENT) else 0

	return {
		ambient = ambient,
		carried = carried,
		net = fromStage + fromBag,
		excess = excess,
		healthBurn = healthBurn,
		failing = excess > 0,
	}
end

--- Stage rads/sec, including any hot pocket the player is standing in (PLAN §4).
function Radiation.ambientAt(stageBaseRads: number, hotPocketMult: number?): number
	return stageBaseRads * (hotPocketMult or 1)
end

--- Seconds until the player goes down, from either cause. This is the number that
--- renders as `SURVIVABLE: 0:14` (PLAN §3.5).
---
--- Returning the honest number is a deliberate design choice: a gamble where you
--- cannot see the odds is a trap, and traps make people quit.
function Radiation.survivableSeconds(reading: Reading, exposure: number, health: number): number
	local toBlackout = if reading.net > 1e-6 then (Tuning.EXPOSURE_CAP - exposure) / reading.net else math.huge
	local toBurnout = if reading.healthBurn > 1e-6 then health / reading.healthBurn else math.huge
	return math.min(toBlackout, toBurnout)
end

--- Which of the two failure states is actually closer. The HUD uses this to pick
--- its colour language: burn is white, exposure is green. PLAN §14.
function Radiation.dominantThreat(reading: Reading, exposure: number, health: number): string?
	local toBlackout = if reading.net > 1e-6 then (Tuning.EXPOSURE_CAP - exposure) / reading.net else math.huge
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
	local fromBag = reading.carried * (1 - math.clamp(stats.satchelShielding, 0, 1))
	return if reading.net > 1e-6 then math.clamp(fromBag / reading.net, 0, 1) else 0
end

--- 0 = clean, 1 = blackout. Drives the vignette and the audio bed.
function Radiation.exposureFraction(exposure: number): number
	return math.clamp(exposure / Tuning.EXPOSURE_CAP, 0, 1)
end

return Radiation
