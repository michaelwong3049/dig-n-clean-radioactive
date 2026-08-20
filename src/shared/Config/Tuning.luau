--!strict
--[[
	Tuning.lua — global knobs.

	RULE FOR THIS WHOLE FOLDER: data only, no game logic, no requires of anything
	outside Config/. Every magic number in the game lives here or in a sibling file.

	PLAN.md §16 says every number in the design is an unvalidated guess. That is the
	entire reason this layer exists: you will be retuning constantly against live data,
	and retuning must never mean touching a service.
]]

local Tuning = {}

-- ── Simulation ────────────────────────────────────────────────────────────────
Tuning.TICK_RATE = 10 -- Hz. Exposure, decay and exhibition all run on this one clock.
-- 10 Hz is deliberate: rates are per-second and none of these systems need frame
-- accuracy. Running them at 60 Hz costs 6x the CPU for zero perceptible difference.

-- ── Exposure (PLAN §3.1) ──────────────────────────────────────────────────────
Tuning.EXPOSURE_CAP = 100 -- "rads" to blackout
Tuning.EXPOSURE_WARN = 0.50 -- vignette + click bed
Tuning.EXPOSURE_DANGER = 0.80 -- distortion, false pings
Tuning.SHOWER_FLUSH_RATE = 200 -- rads/sec removed while standing in a decon shower

-- ── Radiation burn / suit failure (PLAN §3.5) ─────────────────────────────────
-- healthBurn (HP/sec) = BURN_COEF * (ambientRads - suitTolerance) ^ BURN_EXPONENT
--
-- These two constants were fitted so that the model reproduces the design targets:
--   * unsuited survival matches §3.5's table (50s / 15s / 7s / 3s / instant)
--   * ONE TIER UNDER lands at ~35s in every zone — the "one dig" window §3.5 asks for
--   * a full Containment Rig buys 1:30 in the Crater — §4's "timed heist"
--
-- Run Shared.Util.TuningReport to regenerate that matrix after any change here.
Tuning.BURN_COEF = 2.0
Tuning.BURN_EXPONENT = 0.75
Tuning.MAX_HEALTH = 100

-- Burn does NOT also amplify exposure gain. The original design text had it doing both;
-- that turned out to be double jeopardy that made the survivability numbers impossible
-- to fit and impossible for a player to reason about. One over-tier penalty, one meter.
-- Over-tier deaths are HEALTH deaths (white screen), in-tier deaths are EXPOSURE
-- deaths (green screen). Two states, two colors, no overlap.

-- ── Decay clock (PLAN §3.6) ───────────────────────────────────────────────────
-- Stage boundaries are multiples of the item's fuse (T): Fresh <T, Hot <2T, Critical <3T, Slag.
Tuning.DECAY_STAGES = {
	{ name = "Fresh", atFuseMultiple = 0, emission = 1.0, valueRetained = 1.00 },
	{ name = "Hot", atFuseMultiple = 1, emission = 2.5, valueRetained = 0.90 },
	{ name = "Critical", atFuseMultiple = 2, emission = 5.0, valueRetained = 0.55 },
	{ name = "Slag", atFuseMultiple = 3, emission = 8.0, valueRetained = 0.10 },
}

-- Base rads/sec a carried item contributes at Fresh stage, by rarity order (1..8).
-- Multiplied by the stage emission above, and shielded by the SATCHEL (not the suit —
-- see the header of Shared/Radiation.lua for why).
--
-- Calibrated against three checks, all asserted in Shared/Util/Spec. Measured in
-- Zone 3 with a rated (Lead-Lined) suit and an unshielded Canvas Bag:
--   * 8x Rare, all Fresh (a full bag)      -> 2:44. Comfortable; the walk home is ~35s.
--   * 1x Irradiated Legendary at Critical  -> 27s.  Scary, survivable, RUN.
--   * 1x Anomaly at Fresh                  -> 54s.  And it goes Hot at 75s, so the
--                                             panic compounds right as it matters.
-- Re-run Shared.Util.TuningReport after touching these; it prints all three.
Tuning.CARRY_EMISSION = { 0.006, 0.012, 0.03, 0.07, 0.16, 0.36, 0.8, 1.8 }

-- Decay freezes permanently once an item reaches a decon station or the locker.
-- It ALSO freezes on logout — see ARCHITECTURE.md, "The logout rule". Slagging a
-- player's bag while they were offline is the fastest way to lose them.
Tuning.FREEZE_ON_LOGOUT = true

-- ── Economy (PLAN §2 step 5) ──────────────────────────────────────────────────
-- ── The signal field (PLAN §2 steps 1-2) ────────────────────────────────
--
-- These lived as bare locals inside DigService, which put the numbers that decide
-- how deep an item buries in a different file from the plate thickness that has to
-- contain it. Shared/Util/Spec now checks the two against each other, and it can
-- only do that if both are data.
--
-- SIGNALS_PER_ZONE is GLOBAL and does not scale with zone area. That makes zone
-- area the only lever on search density -- see the coverage note in Config/Zones.
Tuning.SIGNALS_PER_ZONE = 45
Tuning.DIG_RADIUS = 5 -- studs you must be within to get a magnet onto a signal
Tuning.DIG_DEPTH_BASE = 1.0
Tuning.DIG_DEPTH_PER_RARITY = 1.6 -- rarer buries deeper, which is what makes depth a gate
Tuning.DIG_DEPTH_JITTER = 1.0

Tuning.DIRTY_SELL_MULTIPLIER = 0.20
Tuning.ASSAY_FEE_FRACTION = 0.02

-- ── Exhibition (PLAN §8.2) ────────────────────────────────────────────────────
Tuning.EXHIBIT_OFFLINE_RATE = 0.25
Tuning.EXHIBIT_OFFLINE_BANK_HOURS = 4
Tuning.EXHIBIT_DUPLICATE_YIELD = { 1.0, 0.40, 0.15, 0.05 } -- 4th+ uses the last entry
Tuning.EXHIBIT_UNCRATE_SECONDS = 60
Tuning.EXHIBIT_STARTING_SLOTS = 3
Tuning.EXHIBIT_MAX_SLOTS = 40
-- Hard ceiling on passive income per real hour, as a multiple of Contractor Level.
-- PLAN §16: ship this LOW. Raising an income cap is a beloved patch note.
Tuning.EXHIBIT_HOURLY_CAP_PER_LEVEL = 250

-- ── Progression (PLAN §9.2) ───────────────────────────────────────────────────
Tuning.LEVEL_CAP = 100
Tuning.RESIST_PER_LEVEL = 0.01
Tuning.RESIST_CAP = 0.40
Tuning.CAPACITY_EVERY_N_LEVELS = 5

return Tuning
