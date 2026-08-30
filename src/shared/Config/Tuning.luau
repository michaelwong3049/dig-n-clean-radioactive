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
-- Condition boundaries are multiples of the item's fuse (T): Fresh <T, Hot <2T, Critical <3T, Slag.
Tuning.DECAY_CONDITIONS = {
	{ name = "Fresh", atFuseMultiple = 0, emission = 1.0, valueRetained = 1.00 },
	{ name = "Hot", atFuseMultiple = 1, emission = 2.5, valueRetained = 0.90 },
	{ name = "Critical", atFuseMultiple = 2, emission = 5.0, valueRetained = 0.55 },
	{ name = "Slag", atFuseMultiple = 3, emission = 8.0, valueRetained = 0.10 },
}

-- Base rads/sec a carried item contributes at Fresh condition, by rarity order (1..8).
-- Multiplied by the condition emission above, and shielded by the SATCHEL (not the suit —
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
-- SIGNALS_PER_STAGE is GLOBAL -- one number for every stage -- but it is NOT free of
-- stage area: it is kept PROPORTIONAL to the uniform footprint by hand, so that
-- `area / SIGNALS_PER_STAGE` stays fixed at 1066.67. Every search metric in
-- Config/Stages (secondsBetweenContacts, coverage, meanSignalGap) is a function of
-- that ratio alone, so holding it means the search feels identical no matter how big
-- the footprint is. It was 96,000 / 90; the chain narrowed to 400 x 200 and it
-- became 80,000 / 75, same ratio, same feel.
--
-- WENT 45 -> 90 WHEN THE REVEAL LANDED (the reveal answers nothing outside your
-- radius, so 45 read as dead ground), THEN 90 -> 75 WITH THE 240 -> 200 WIDTH PASS.
-- Only the first move changed the search density; the second held it.
--
-- THE LOOT TABLES WERE RE-WEIGHTED WITH THE 45 -> 90 MOVE AND THAT PART CANNOT BE
-- UNDONE HERE. Raising density raised the rate of EVERYTHING, Legendaries included,
-- so every weight at Rare and above was halved to cancel it and the freed share went
-- to Scrap/Common. The 90 -> 75 move did NOT touch loot: per-dig rarity odds come
-- from the table weights alone, and holding `area / N` holds the dig rate, so the
-- per-second rate of every rarity is already unchanged.
--
-- RULE: change this number ONLY together with FOOTPRINT_Z in Config/Stages, keeping
-- `area / SIGNALS_PER_STAGE` at 1066.67. Change it alone (without a footprint move)
-- and you have re-scaled search density, which means re-weighting the loot tables
-- too -- Shared/Util/Spec pins "the field holds ~1.9 Rare-or-better signals" and
-- will fail if the two drift apart.
Tuning.SIGNALS_PER_STAGE = 75
Tuning.DIG_RADIUS = 5 -- studs you must be within to get a magnet onto a signal
Tuning.DIG_DEPTH_BASE = 1.0
Tuning.DIG_DEPTH_PER_RARITY = 1.6 -- rarer buries deeper, which is what makes depth a gate
Tuning.DIG_DEPTH_JITTER = 1.0

-- ── The pull (PLAN §Step 2) ─────────────────────────────────────────────
--
-- Extraction is a MASH, not a hold. Every click is a yank that lurches the item up
-- through the soil; the ground drags it back down continuously. Click faster than the
-- drag and it surfaces, stop clicking and it sinks. The three numbers here plus
-- Gear.Magnet's pullSpeed/draw are the whole mechanic.
--
--   progress += (draw - PULL_DRAG_RATE) * dt / required        -- every tick
--   progress += PULL_YANK_PER_CLICK * pullSpeed / required     -- every accepted yank
--   required  = PULL_SECONDS_PER_STUD * depth
--
-- so the clicks-per-second needed just to HOLD an item where it is comes out as
--   (PULL_DRAG_RATE - draw) / (PULL_YANK_PER_CLICK * pullSpeed)
-- and that expression is the real dial on this feature. See Gear.Magnet for the
-- resulting per-tier curve; Spec pins both ends of it.
--
-- NOTE pullSpeed deliberately does NOT divide `required` any more. It used to, back
-- when the pull was a hold. Leaving it there while also scaling the yank would make
-- the magnet track scale QUADRATICALLY -- the same stat counted twice. `required` is
-- now purely "how much rope is on this item", and every magnet stat lives on the
-- reeling side of the equation.
Tuning.PULL_SECONDS_PER_STUD = 1.2

-- How fast the soil takes it back, in pull-seconds per second. 0.75 means the ground
-- undoes three quarters of a second of hauling every second you are not yanking, so a
-- draw-less tier-1 magnet genuinely cannot be left alone for a moment.
Tuning.PULL_DRAG_RATE = 0.75

-- What one yank is worth, in pull-seconds, before pullSpeed scales it.
Tuning.PULL_YANK_PER_CLICK = 0.30

-- ── Yank rate limiting (anti-exploit) ───────────────────────────────────
--
-- READ THIS BEFORE RAISING ANY OF THEM. The hold-to-pull version of this feature was
-- exploit-proof for free: the client sent a boolean and the SERVER integrated over
-- real time, so a spoofed client gained exactly nothing. A per-click verb gives that
-- up -- a hacked client can fire this remote hundreds of times per frame -- so the
-- ceiling has to be re-imposed here, by hand.
--
-- A token bucket rather than a flat interval, because humans do not mash evenly: the
-- burst capacity lets a real player open with a fast flurry, while the refill rate is
-- what actually caps sustained cheating.
--
-- BURST MUST STAY WELL UNDER THE CLICKS A WHOLE PULL TAKES. This was measured wrong
-- the first time and it is the trap worth naming: at BURST = 14 an autoclicker never
-- reached the refill limit at all on a shallow item, because a Scrap only needs about
-- seven accepted yanks end to end and the bucket handed out fourteen for free. The
-- refill rate looked strict and did nothing -- the whole item fit inside the burst.
-- A shallow pull is the CHEAPEST thing to automate and therefore the case to size
-- against, not the deep one. Four is a real opening flurry and not a free Scrap.
--
-- The honest limit of all this, stated plainly so nobody thinks it is airtight: the cap
-- has to admit a strong human (~8/sec sustained), so it also admits a bot at ~8/sec.
-- Against a player mashing comfortably at 4/sec that is still roughly a 2x edge. That
-- is the floor for ANY click-driven verb and it cannot be tuned away -- only removed,
-- by giving up the click. What these numbers do buy is bounding it at 2x instead of
-- the 13x measured before the burst was fixed.
Tuning.PULL_YANK_MIN_INTERVAL = 0.1 -- hard floor between accepted yanks (10/sec)
Tuning.PULL_YANK_SUSTAINED_CPS = 8 -- bucket refill rate; a strong human's sustained mash
Tuning.PULL_YANK_BURST = 4 -- bucket capacity: an opening flurry, NOT a whole item

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
-- The aura is a PULSING WELL OF LIGHT now, not a pillar (on request). Low and wide:
-- a bright disc set into the ground with a soft dome over it, and ripple rings the
-- client sends expanding outward from it. The old tall thin pillar was too close to
-- PLAN 10.9's server-wide "Legendary pulled" beacon; a ground-hugging well cannot be
-- mistaken for it at any distance.
Tuning.AURA_RING = 2.4 -- the well's bright core disc, diameter in studs -- the spot to stand on
Tuning.AURA_DOME = 3.2 -- the soft light dome over the well, diameter -- a touch wider than the core
Tuning.AURA_PULSE_REACH = 5.0 -- how far the ripple rings travel out (== DIG_RADIUS, so the widest ripple shows the pickup range)
Tuning.AURA_PULSE_HZ = 0.8 -- client-side ripple rate, cosmetic only (was the pillar's breathe rate)

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
-- Every plot ships with all of its display stands usable — there is no slot to buy
-- or unlock. Matches Plots.VISIBLE_SLOTS (the stands actually built per base).
Tuning.EXHIBIT_MAX_SLOTS = 8
-- Hard ceiling on passive income per real hour, as a multiple of Contractor Level.
-- PLAN §16: ship this LOW. Raising an income cap is a beloved patch note.
Tuning.EXHIBIT_HOURLY_CAP_PER_LEVEL = 250

-- ── Progression (PLAN §9.2) ───────────────────────────────────────────────────
Tuning.LEVEL_CAP = 100
Tuning.RESIST_PER_LEVEL = 0.01
Tuning.RESIST_CAP = 0.40
Tuning.CAPACITY_EVERY_N_LEVELS = 5

return Tuning
