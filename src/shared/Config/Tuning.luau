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
--   * unsuited survival matches the third-pass targets (17s / 5s / 2s / 1s / instant)
--     for stages 2-6 -- Stage 1 is a separate, exposure-only case, see Gear.luau's
--     Cloth Wrap `reduction` note for why it isn't in this list.
--   * ONE TIER UNDER lands at ~12s in every stage (3-6) -- tightened again, see the
--     note below on why this and the Stage 3 unsuited target could not both be hit
--     without moving this number a second time.
--   * a full Containment Rig buys 1:30 in the Crater — §4's "timed heist" (unaffected --
--     that scenario is exposure-bound, not burn-bound, so COEF doesn't touch it)
--
-- COEF raised 2.0 -> 3.0 -> 6.0 across two harshening passes today. The second raise
-- was driven by an explicit target: Stage 3 unsuited (Cloth Wrap) should die in well
-- under 5 seconds at the entrance, not the ~10s the first pass produced. Stage 3's own
-- ambient rate was deliberately NOT what moved to hit that -- raising Stage 3's
-- baseRads instead would have closed the gap between its entrance and deepest rates,
-- flattening exactly the within-stage depth gradient this file's earlier pass exists to
-- create. A global COEF raise scales every stage's entrance:deepest RATIO unchanged,
-- so the depth gradient stays exactly as pronounced, just faster everywhere.
--
-- THE UNAVOIDABLE COST: this also compresses the one-tier-under "Dive" window (stages
-- 3-6) from ~23s down to ~12s, because Stage 3's ambient (6 r/s) sits close enough to
-- both Cloth Wrap's tolerance (1.0) and Rubber Suit's (4.4) that no pure COEF or
-- tolerance scalar can push the Cloth Wrap number down without dragging the Rubber
-- Suit number down with it -- the two are locked to the same stage ambient, and their
-- burn values differ only by a ratio COEF cancels out of. Decoupling them for real
-- would mean widening the gap between suit tiers' tolerances, a much bigger change
-- than was asked for here. Flagged rather than hidden: the "one dig" pacing from
-- PLAN §3.5 is now noticeably tighter than originally designed.
--
-- EXPONENT deliberately untouched: raising it toward 1 would make small-`excess`
-- scenarios (the one-tier-under dive) comparatively LESS punishing while barely
-- affecting the already-near-instant over-tier deaths, the opposite of "more punishing."
--
-- Run Shared.Util.TuningReport to regenerate that matrix after any change here.
Tuning.BURN_COEF = 6.0
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
-- Stage 3 with a rated (Lead-Lined) suit and an unshielded Canvas Bag:
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
-- SIGNALS_PER_STAGE is GLOBAL and does not scale with stage area. That makes stage
-- area the only lever on search density -- see the coverage note in Config/Stages.
--
-- DOUBLED FROM 45 WHEN THE REVEAL LANDED. The needle always had something to point
-- at, so 45 read as "sparse but guided"; the reveal answers nothing at all outside
-- your radius, so the same field read as dead ground. 90 puts a contact roughly every
-- 5.6 seconds of walking at tier 1 instead of every 11.3, which is a search rather
-- than a commute.
--
-- THE LOOT TABLES WERE RE-WEIGHTED IN THE SAME BREATH AND THE TWO CANNOT BE SEPARATED.
-- Doubling density doubles the rate of EVERYTHING, Legendaries included, which is the
-- opposite of what a rarity economy wants. So every weight at Rare and above was
-- halved to cancel this multiplier exactly, and the freed share went to Scrap and
-- Common. Net effect: about twice as many pulls, nearly three times as many Commons,
-- and Rare-or-better arriving at the same wall-clock rate it always did.
--
-- If you change this number, you MUST re-weight Config/Stages to match or you have
-- quietly multiplied the top of the loot table. Shared/Util/Spec pins the invariant
-- ("the field holds ~4.9 Rare-or-better signals") and will fail if you do not.
Tuning.SIGNALS_PER_STAGE = 90
Tuning.DIG_RADIUS = 5 -- studs you must be within to get a magnet onto a signal
Tuning.DIG_DEPTH_BASE = 1.0
Tuning.DIG_DEPTH_PER_RARITY = 1.6 -- rarer buries deeper, which is what makes depth a gate
Tuning.DIG_DEPTH_JITTER = 1.0

-- ── The reveal (Gear.Detector.radius) ───────────────────────────────────
--
-- A signal inside your detector's radius that clears the maxRarity and depth gates
-- surfaces an AURA at its exact spot. The aura is a real Workspace part built by the
-- server, so EVERY player sees it, not only the one whose detector found it. That is
-- a deliberate design call and it has a known cost — a low-tier player tailing a
-- high-tier one gets to walk to glows they could never have revealed. maxRarity and
-- depth still gate the PULL, so the deep and rare stuff stays locked to them; what
-- leaks is the shallow common end. Do not "fix" this by making auras per-player
-- without saying so, because the shared-sighting moment is the point.
--
-- Rarity is NOT on the aura. The aura says "something is here" to the whole server;
-- the colour that says "and it is Legendary" lives on the client's radar blips, where
-- detectorClarity can still gate it per-player.
-- Tag and folder name live HERE rather than on the server builder because both sides
-- need them: the server creates and tags the auras, the client finds them by tag to
-- animate them, and a client cannot require a module out of ServerScriptService. Two
-- hardcoded copies of a tag string is how one of them quietly becomes "SignalAuras".
Tuning.AURA_TAG = "SignalAura"
Tuning.AURA_FOLDER = "SignalAuras"
Tuning.AURA_HEIGHT = 5.5 -- studs the pillar stands above the surface
Tuning.AURA_WIDTH = 0.55 -- pillar diameter
Tuning.AURA_RING = 2.4 -- ground ring diameter, marks the spot to stand on
Tuning.AURA_PULSE_HZ = 1.1 -- client-side breathe rate, cosmetic only

-- The range ring the detector draws on the ground around YOU. Client-side, so unlike
-- the auras it is yours alone — it answers "what am I actually sweeping right now",
-- which stopped being obvious the moment the needle went away.
Tuning.RANGE_RING_PERIOD = 1.0 -- seconds between expanding pulses
Tuning.RANGE_RING_SEGMENTS = 48 -- thin parts per ring; asset-free, so no texture to load

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
