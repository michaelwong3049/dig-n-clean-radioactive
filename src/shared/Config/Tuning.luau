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
-- SIGNALS_PER_STAGE is GLOBAL -- one number for every stage. It USED to be kept
-- proportional to the uniform footprint by hand, so `area / SIGNALS_PER_STAGE`
-- stayed fixed at 1066.67 and the search felt identical no matter the footprint
-- size. It was 96,000 / 90; the 240 -> 200 width pass took it to 80,000 / 75, same
-- ratio, same feel.
--
-- THEN TWO FOOTPRINT PASSES LEFT N AT 75, ON REQUEST EACH TIME. The 15% pass
-- (400x200 -> 340x170) took `area / N` 1066.67 -> 770.67; the length-only pass
-- (340 -> 290 on X, Z held at 170) took it 770.67 -> 657.33. The search is ~38%
-- denser than the 1066.67 days: the starting detector turns up a contact about
-- every 1.3s now (was ~2.0s). Every search metric in Config/Stages
-- (secondsBetweenContacts, coverage, meanSignalGap) moved with that one ratio.
--
-- WENT 45 -> 90 WHEN THE REVEAL LANDED (the reveal answers nothing outside your
-- radius, so 45 read as dead ground), THEN 90 -> 75 WITH THE 240 -> 200 WIDTH PASS.
-- The 45->90 move changed search density; the 90->75 held it; the two footprint
-- passes since changed it again by holding N while the area shrank.
--
-- THE LOOT TABLES WERE RE-WEIGHTED WITH THE 45 -> 90 MOVE AND THAT PART CANNOT BE
-- UNDONE HERE. Raising density raised the rate of EVERYTHING, Legendaries included,
-- so every weight at Rare and above was halved to cancel it and the freed share went
-- to Scrap/Common. None of the 90 -> 75 move, the 15% pass or the length pass
-- touched loot: N itself held at 75 across all three, so per-dig odds AND the count
-- of jackpots buried at once are both unchanged -- only the walk between digs got
-- shorter.
--
-- RULE: this is now the sole search-density knob. Raise it and you re-scale density
-- (and must re-weight the loot tables -- Shared/Util/Spec pins "the field holds
-- ~1.9 Rare-or-better signals" on N alone and will fail if the two drift apart);
-- lower it to walk `area / N` back up toward where the search feel used to sit --
-- but Spec §7's Rare+ floor means N cannot go below ~69 without that re-weight.
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

-- ── Over-tier grip (Gear.Magnet.maxGrip vs Stages.soilHardness) ─────────
--
-- maxGrip USED TO BE A HARD WALL: soil > maxGrip clamped the haul at a quarter and
-- painted "MAGNET TOO WEAK". It is now a STEEP SOFT GRADIENT. The magnet's whole side
-- of the tug-of-war -- the yank impulse AND the passive draw -- is multiplied by
--   gripEff = PULL_GRIP_FALLOFF ^ deficit        deficit = max(0, soilHardness - maxGrip)
-- while PULL_DRAG_RATE (the soil's pull) is untouched. So the clicks-per-second just
-- to HOLD an item becomes
--   (PULL_DRAG_RATE - draw*gripEff) / (PULL_YANK_PER_CLICK * pullSpeed * gripEff)
-- which blows up fast: at 0.5, one stage over tier roughly doubles the mash a weak
-- magnet needs (a real grind, still winnable at ~8/sec), two stages over puts it past
-- what a human sustains (the item lurches on the opening burst, then sinks), three
-- over is net-negative even at the rate cap -- an unspoken wall, no message. A
-- slightly better magnet claws out a deficit the tier below cannot. There is NO
-- ceiling clamp any more. Spec §Step2 pins the +1 / +2 / +3 behaviour off this number.
Tuning.PULL_GRIP_FALLOFF = 0.5

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
-- A signal inside your detector's radius that clears the depth gate surfaces an AURA
-- at its exact spot. The aura is a real Workspace part built by the server, so EVERY
-- player sees it, not only the one whose detector found it. That is a deliberate design
-- call and it has a known cost — a low-tier player tailing a high-tier one gets to walk
-- to glows they could never have revealed, and (now that maxRarity is gone) pull them.
-- What still separates the tiers: depth gates the reveal, the magnet's maxGrip gates
-- the pull, and detector luck bends each player's OWN roll toward Rare+ (Config/Items).
-- Do not "fix" the shared aura by making auras per-player without saying so — the
-- shared-sighting moment is the point.
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

-- ── The wash pad (Config/Liquids) ───────────────────────────────────────
--
-- Stepping onto the pad IS the roll — it fires off StationService's entry edge, not
-- off a button in a panel, because "step on it and something happens" is the whole
-- charm and a confirmation dialog would kill it.
--
-- WHICH MEANS THE COST IS THE ONLY THING STOPPING AN INFINITE RE-ROLL. A free pad is
-- farmed: you hop on and off until Stardust lands, and every number in Liquids.luau
-- becomes decoration. The fee is what makes the Luck button an actual purchase —
-- better odds per dollar spent — rather than a formality you buy once for completeness.
-- Deliberately FLAT rather than scaling with luck or with rolls-this-session: a
-- scaling fee punishes the player who engages with the mechanic most, and `charges`
-- already limits how much value a good roll can be turned into.
--
-- The cooldown is not a balance lever, it is a debounce. Walking on and off the pad
-- repeatedly would otherwise fire one roll per crossing, and the reveal animation is
-- roughly this long, so a second roll landing mid-reveal reads as a dropped one.
--
-- 80, NOT 170, AND Util/Spec IS WHY. A Common sells for 35-170, so a fee up near the
-- top of that band meant the pad cost a brand-new player their single best find per
-- pull -- and a mechanic nobody can afford to try is a mechanic nobody discovers. At
-- 80 it is roughly half a mid Common: cheap enough to be the first thing a new player
-- spends money on, and still non-zero, which is all the fee has to be. It is irrelevant
-- either way to a rich player, whose real limiter is `charges`, never cash.
-- (Economy rescale: was 12 against the old 5-25 Common band; 12 * 20/3 ~= 80.)
Tuning.LIQUID_ROLL_COST = 80
Tuning.LIQUID_ROLL_COOLDOWN = 3 -- seconds between rolls, per player

-- Charges stack when you roll the same liquid twice, up to this multiple of the
-- liquid's own `charges`. Without a ceiling, an idle player parked on the pad
-- accumulates an unbounded Stardust supply and the pad stops being somewhere you
-- ever need to go back to — which is the exact failure the charge system exists to
-- prevent. Five rolls' worth is generous enough that nobody hits it by accident.
Tuning.LIQUID_MAX_STACK = 5

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
-- Economy rescale: 250 -> 500000. Item baseValues moved x6.667 and Rarity.displayYield
-- moved x300, so per-displayed-item income rose x2000 overall -- this moved x2000 to
-- match, so the guard still bites exactly as hard as it did before (a lucky early
-- Legendary is clamped ~18x at level 1, un-clamping as you level).
Tuning.EXHIBIT_HOURLY_CAP_PER_LEVEL = 500000

-- ── Progression (PLAN §9.2) ───────────────────────────────────────────────────
Tuning.LEVEL_CAP = 100
Tuning.RESIST_PER_LEVEL = 0.01
Tuning.RESIST_CAP = 0.40
Tuning.CAPACITY_EVERY_N_LEVELS = 5

return Tuning
