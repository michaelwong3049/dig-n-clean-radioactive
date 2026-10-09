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
Tuning.EXPOSURE_CAP = 100 -- a full meter: heavy sickness (SICKNESS_FULL_METER)
Tuning.EXPOSURE_WARN = 0.50 -- vignette + click bed
Tuning.EXPOSURE_DANGER = 0.80 -- distortion, false pings
Tuning.SHOWER_FLUSH_RATE = 200 -- rads/sec removed while standing in a decon shower
-- Rads/sec removed anywhere outside every stage (Base Camp, any site camp). A full
-- meter clears in ~4 s; the shower is still the instant flush. A crater orb's fallout
-- (CRATER_RADS_PER_BURN) still lands on top, so standing in one there still fills.
Tuning.CAMP_FLUSH_RATE = 25
-- Base Camp's two heal pads (build/HealPads): a shower anyone can use, which also
-- heals this fraction of your MAX health per second -- full from empty in ~2 s at any
-- aura tier, where the camp's plain regen takes the better part of a minute late on.
Tuning.HEAL_PAD_HEAL_FRAC = 0.5
-- A detonated nuke's crater orb fills the meter as well as burning health: rads/sec
-- = the orb's HP/sec burn on you * this, capped. A Common's orb (20 HP/sec at the
-- centre, 7 at the rim) fills an empty meter in ~5s at the centre, ~14s at the rim;
-- the cap stops a far-stage Anomaly's orb filling it faster than ~2.5s.
Tuning.CRATER_RADS_PER_BURN = 1.0
Tuning.CRATER_RADS_MAX = 40 -- rads/sec

-- ── Radiation sickness (out in the stages only) ────────────────────────────────
-- A high meter now costs HEALTH on the way to 100%, not just at it. Past
-- SICKNESS_NO_REGEN health stops regenerating; past SICKNESS_DRAIN_AT it drains,
-- ramping MIN -> MAX HP/sec from that notch to a full meter. Camps are exempt:
-- the meter only empties in a base's shower, so draining there would kill a
-- player standing at home. Walk back and the regen returns.
Tuning.SICKNESS_NO_REGEN = Tuning.EXPOSURE_WARN -- 50%
Tuning.SICKNESS_DRAIN_AT = Tuning.EXPOSURE_DANGER -- 80%
Tuning.SICKNESS_DRAIN_MIN = 1.0 -- HP/sec at 80%
Tuning.SICKNESS_DRAIN_MAX = 4.0 -- HP/sec just under 100%
-- A FULL meter no longer blacks you out on the spot: it is heavy sickness instead,
-- this fraction of your MAX health per second (so ~10s from full at any aura tier,
-- where a flat HP/sec would mean nothing to a late aura's extra health). Same
-- stages-only rule: a full meter in a camp does nothing until you walk out.
Tuning.SICKNESS_FULL_METER = 0.10

-- ── Radiation burn / aura failure (PLAN §3.5) ─────────────────────────────────
-- healthBurn (HP/sec) = BURN_COEF * (ambientRads - auraTolerance) ^ BURN_EXPONENT
--
-- These two constants were fitted so that the model reproduces the design targets:
--   * unshielded survival matches the third-pass targets (17s / 5s / 2s / 1s / instant)
--     for stages 2-6 -- Stage 1 is a separate, exposure-only case, see Gear.luau's
--     Faint Glow `reduction` note for why it isn't in this list.
--   * ONE TIER UNDER lands at ~12s in every stage (3-6) -- tightened again, see the
--     note below on why this and the Stage 3 unshielded target could not both be hit
--     without moving this number a second time.
--   * a full Containment Nimbus buys 1:30 in the Crater — §4's "timed heist" (unaffected --
--     that scenario is exposure-bound, not burn-bound, so COEF doesn't touch it)
--
-- COEF raised 2.0 -> 3.0 -> 6.0 across two harshening passes today. The second raise
-- was driven by an explicit target: Stage 3 unshielded (Faint Glow) should die in well
-- under 5 seconds at the entrance, not the ~10s the first pass produced. Stage 3's own
-- ambient rate was deliberately NOT what moved to hit that -- raising Stage 3's
-- baseRads instead would have closed the gap between its entrance and deepest rates,
-- flattening exactly the within-stage depth gradient this file's earlier pass exists to
-- create. A global COEF raise scales every stage's entrance:deepest RATIO unchanged,
-- so the depth gradient stays exactly as pronounced, just faster everywhere.
--
-- THE UNAVOIDABLE COST: this also compresses the one-tier-under "Dive" window (stages
-- 3-6) from ~23s down to ~12s, because Stage 3's ambient (6 r/s) sits close enough to
-- both Faint Glow's tolerance (1.0) and Static Veil's (4.4) that no pure COEF or
-- tolerance scalar can push the Faint Glow number down without dragging the Static
-- Veil number down with it -- the two are locked to the same stage ambient, and their
-- burn values differ only by a ratio COEF cancels out of. Decoupling them for real
-- would mean widening the gap between aura tiers' tolerances, a much bigger change
-- than was asked for here. Flagged rather than hidden: the "one dig" pacing from
-- PLAN §3.5 is now noticeably tighter than originally designed.
--
-- EXPONENT deliberately untouched: raising it toward 1 would make small-`excess`
-- scenarios (the one-tier-under dive) comparatively LESS punishing while barely
-- affecting the already-near-instant over-tier deaths, the opposite of "more punishing."
--
-- Run Shared.Util.TuningReport to regenerate that matrix after any change here.
-- 6.0 -> 4.8 on request ("entering a stage not for your aura should be slightly less
-- harsh, still fast"): 20% less burn everywhere. One tier under at a stage entrance
-- ~12s -> ~15s; Stage 2 with no aura ~28s -> ~35s. In-tier play is untouched (no burn).
Tuning.BURN_COEF = 4.8
Tuning.BURN_EXPONENT = 0.75

-- ── Zone survival curve (Radiation.zoneSurvival) ──────────────────────────────
-- REPLACES THE TOLERANCE BURN ABOVE AS THE AURA'S DAMAGE. The old burn switched on
-- the instant the air crossed your aura's tolerance, which landed at a different depth
-- in every stage and read as sudden jumps. Now the aura's damage is stated directly
-- as SECONDS A FULL HEALTH BAR LASTS (so the +50 HP per aura tier never skews it),
-- picked from where you stand and your aura against the stage's ratedAuraTier:
--
--   rated   : your aura is the stage's own. Minimal drain over the first BREAK of
--             the stage, then a steady, harsher one to the far edge. Not "failing".
--   under   : one tier too weak. 20-30s at the entrance, ~2-3s past BREAK. Failing.
--   wayUnder: two or more tiers too weak. About a second, anywhere. Failing.
--   (UNDER_GRACE is added on top of both failing rows, see below.)
--   lastAura: the top aura in a stage rated past the end of the ladder (unused
--             since the Molten Serpent gave Stage 12 its own rung).
--   raid    : the stage's own aura in a RAID stage (Ground Zero). Fails everywhere
--             in it, on its own row; see RAID below.
--   over    : one or two tiers too STRONG. The rated row stretched by OVER (x5, x25):
--             a slow wear you can watch tick down as you walk deeper, never failing.
--             Three or more tiers over takes no aura damage at all.
--
-- Each row is { at the entrance, at BREAK, at the far edge }, in seconds. Between
-- points the time is blended geometrically, so the drain climbs smoothly and never
-- steps. Stages HARSH_FROM_STAGE and on use `late`. The exposure meter's sickness
-- (above) still stacks on top; this curve is only the aura's share.
Tuning.ZONE_SURVIVAL = {
	BREAK = 0.6,
	-- 7 -> 6 on request ("the end of Stage 6 should do more damage"): the Crater's air is
	-- nearly flat (100 -> 104), so it is the curve that has to make its far rim bite.
	HARSH_FROM_STAGE = 6,
	early = { rated = { 900, 360, 120 }, under = { 30, 3, 1.5 } }, -- stages 1-5
	-- `grace` (late only) replaces the flat UNDER_GRACE with one that fades across the
	-- stage, on request ("the end of Stage 6 doesn't increase damage"): a flat +20s on
	-- top of a 2s -> 1s curve read as the same ~21-26s everywhere past a third of the
	-- way in. Same +20s at the entrance; one tier under is now ~10s at BREAK and ~3s at
	-- the far edge, so walking deeper visibly bites.
	late = { rated = { 480, 240, 75 }, under = { 20, 2, 1 }, grace = { 20, 8, 2 } }, -- stages 6-12
	wayUnder = 1,
	lastAura = { 75, 60, 45 },
	-- Flat seconds added to every UNDER and WAY-UNDER time, on request ("20 more seconds
	-- to stay in zones their aura can't handle"): one tier under is ~50s at a Stage 1-5
	-- entrance and ~21s past BREAK, two tiers under ~21s anywhere. Added after the
	-- blend, so it is the same 20s at every depth. lastAura (the Stage 12 raid) and the
	-- rated rows do not get it.
	UNDER_GRACE = 20,
	-- Extra flat seconds for ONE tier under only (the stage one above your aura), on
	-- request ("allow like 30 more seconds in that zone"). On top of the grace above:
	-- one under is ~80s at a Stage 1-5 entrance (~70s in 6-12), ~53s past BREAK, ~33s
	-- at a late stage's far edge. Two or more under (wayUnder) does not get it, and the
	-- dead zones at Stage 4 / 8 still blend down to their `edge`.
	UNDER_EXTRA = 30,
	-- OVERGEARED: one / two tiers ABOVE the stage's rating wear at the rated row's times
	-- multiplied by these, on request ("walked through stages 6 and 7 with no droppage,
	-- time no change"): before this, any aura over the rating took nothing, so a Stage 8
	-- aura crossed 6 and 7 with a dead clock. Now one over in a late stage is ~40m at the
	-- entrance down to ~6m at the far edge, so the clock falls with every step deeper,
	-- while a stage below your aura still farms comfortably (Spec: 5m+ at its far edge).
	-- Green wear (the aura holding), never failing. Three or more over takes nothing.
	OVER = { 5, 25 },
	-- RAID STAGES: stageId -> { entrance, BREAK, far edge } for the stage's OWN aura, which
	-- FAILS there everywhere (red, "TURN BACK": there is no aura above it). On request
	-- (2026-10-07, "make ground zero be able to die with max aura, right now you can
	-- basically stay there forever"): with the rated row the Molten Serpent wore 8m a bar
	-- at the entrance, so Ground Zero was a farm. Now it is a raid again, like the old
	-- Vortex lastAura: ~3m at the entrance, 1.5m at 60%, 40s at the far edge. Always
	-- kept above one tier under there (the Vortex: ~70s / 40s / 33s), so the Serpent
	-- still buys time.
	RAID = {
		[12] = { 180, 90, 40 },
	},
	-- DEAD ZONES: stageId -> the back of that stage, where even the stage's own aura
	-- fails. From `from` on, the time a bar lasts falls geometrically from whatever the
	-- normal curve gives there to `edge` seconds at the far edge -- the same SHARE
	-- shorter for every step, so it bites harder and harder but never jumps. Applies to
	-- the rated aura and everything under it (the shorter of this and the normal time
	-- wins); an aura above the stage's rating wears on the OVER rows instead.
	--
	-- Was a step (12s from the line at 60% on Stage 8), changed on request: "the death
	-- zones are too sudden, make heavy drops in survivability each step taken". Now it
	-- starts at 40% and roughly halves the time every tenth of the stage: Stage 8 is
	-- ~5m at 40%, ~1m at 60%, ~25s at 70%, ~10s at 80%, 2s at the gate. The sprint costs
	-- about the same as the old step did.
	--
	-- THE LAST STAGE OF EVERY ZONE (FOUR STAGES PER ZONE, 2026-10-03, on request: "remove
	-- the stage 6 dead zone and do so with stage 4 and 8"). Each one ends at a camp's gate
	-- -- Toxic Twilight past Stage 4, Magma Hollow past Stage 8 -- so its back is a
	-- sprint, not a dig site: the camp is reachable on foot from full health in the
	-- stage's own aura (Spec pins that), but stopping out there is how you die. Stage 4
	-- is early game and gentler.
	DEAD_ZONE = {
		[4] = { from = 0.4, edge = 6 },
		[8] = { from = 0.4, edge = 2 },
	},
}
-- SAFE STAGES: stageId -> true. Nothing in a listed stage costs health or fills the
-- meter -- no aura drain, no sickness, no crater orb, no blast -- and the meter drains
-- at CAMP_FLUSH_RATE as if you were in a camp, so a player there cannot die. On request
-- (2026-10-09, "make fading fields EXTREMELY easy like a player can't die").
Tuning.SAFE_STAGES = {
	[1] = true,
}
Tuning.MAX_HEALTH = 100
-- Every aura level past the first adds this much max health (tier 1 = 100, tier 2 = 150...).
Tuning.HEALTH_PER_AURA_TIER = 50

function Tuning.maxHealthFor(auraTier: number?): number
	return Tuning.MAX_HEALTH + math.max(0, (auraTier or 1) - 1) * Tuning.HEALTH_PER_AURA_TIER
end

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
-- Multiplied by the condition emission above, and shielded only by level resist (never
-- the aura — see the header of Shared/Radiation.lua for why).
--
-- Calibrated against three checks, all asserted in Shared/Util/Spec. Measured in
-- Stage 3 with a rated (Lead Halo) aura and an unshielded bag — which, with the
-- Satchel track retired, is now the only bag there is:
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

-- The Quarantine Locker's tubes: how many finds you can park at home instead of
-- carrying. build/Plots builds this many (two tiers of four) and every locker starts
-- with exactly this many slots. A profile racked past its cap before the cap existed
-- keeps everything (nothing is ever deleted); it just cannot store more until it
-- drops back under.
Tuning.LOCKER_SLOTS = 8

-- LOCKER UPGRADES: bought from the locker panel, +LOCKER_UPGRADE_STEP slots each, so
-- the six of them take a locker from 8 to 20. `data.lockerUpgrades` counts how many
-- are owned; the slot count is always derived from it (Tuning.lockerSlots), never
-- stored. Priced like a stage's gear, roughly one upgrade every other stage: S2-3,
-- S3-4, S5, S6-7, S8, S10 (compare Config/Gear's detector ladder). The rack in the
-- world still has 8 tubes; slots past it show only in the panel until the rack is
-- redesigned.
Tuning.LOCKER_UPGRADE_STEP = 2
Tuning.LOCKER_UPGRADE_PRICES = { 50000, 400000, 3000000, 20000000, 150000000, 1000000000 }
Tuning.LOCKER_MAX_SLOTS = Tuning.LOCKER_SLOTS + #Tuning.LOCKER_UPGRADE_PRICES * Tuning.LOCKER_UPGRADE_STEP

--- How many locker upgrades a save owns, clamped to a real count.
function Tuning.lockerUpgrades(data: any): number
	local n = if data ~= nil and type(data.lockerUpgrades) == "number" then data.lockerUpgrades else 0
	return math.clamp(math.floor(n), 0, #Tuning.LOCKER_UPGRADE_PRICES)
end

--- How many tubes this save's locker holds.
function Tuning.lockerSlots(data: any): number
	return Tuning.LOCKER_SLOTS + Tuning.lockerUpgrades(data) * Tuning.LOCKER_UPGRADE_STEP
end

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
--
-- 75 -> 40 ON REQUEST ("heavily reduce the amount of detector spawns; top tier
-- detectors should still see a lot but nowhere near as much"). `area / N` 657.33 ->
-- 1232.5: the starting detector walks ~1.8s between contacts (was 0.9s at walk 30)
-- and a maxed one ~0.5s (was 0.26s), back inside Spec's §2.1 bands; standing still,
-- a maxed detector lights ~4 glows instead of ~7.6. Per-dig odds are untouched, so
-- the loot tables were NOT re-weighted -- the field just holds fewer jackpots at once
-- (~1.2 Rare+ in Stage 1, was ~2.2), and Spec §7's floor moved with N to say so.
--
-- 40 -> 28 ON REQUEST (2026-10-03: "even mid tier detectors shouldn't have that many
-- detector spots show up"). 30% fewer everywhere: standing still in Stage 1 a Pulse
-- Array (r=22) lights ~0.95 glows (was ~1.36), The Oracle (r=34) ~2.3 (was ~3.3);
-- the starting detector walks ~2.2s between contacts (was ~1.7s). Same call as the
-- last pass: per-dig odds untouched, loot NOT re-weighted -- the field just holds
-- fewer jackpots at once (~0.74 Rare+ in Stage 1), and Spec §7's floor moved again.
--
-- 28 -> 20 WITH THE MAP-SHRINK PASS (2026-10-03: every stage 20% narrower and 10%
-- shorter, area x0.72). On request the count scales WITH the area, so `area / N`
-- (and so the walk between contacts) holds where the 28 left it. Per-dig odds
-- untouched again; the field holds ~0.53 Rare+ in Stage 1 and Spec §7's floor moved.
--
-- 20 -> 22 WITH THE 10%-WIDER PASS (2026-10-03: FOOTPRINT_Z 124 -> 136, area x1.097).
-- Same rule: the count follows the area so `area / N` holds.
--
-- 22 -> 28 WITH THE BACK-TO-170 PASS (2026-10-04: FOOTPRINT_Z 136 -> 170, area x1.25;
-- 27.5 rounded up).
--
-- 28 -> 25 WITH THE 10%-THINNER PASS (2026-10-04: FOOTPRINT_Z 170 -> 153, area x0.9;
-- 25.2 rounded down).
Tuning.SIGNALS_PER_STAGE = 25
-- THE FIELD RESHUFFLE (on request, 2026-10-05). Every this-many seconds every ordinary
-- signal goes stale, and a stale one is reburied somewhere else the moment nobody can
-- see it: no aura up (lit or fading), outside every detector radius, no magnet on it,
-- no lit fuse. Whatever a player is looking at stays put until they walk off it, and
-- the replacement is placed outside everyone's radius, so nothing ever swaps on screen.
-- Announced drops and the tutorial spot are never reshuffled. See DigService.refreshStale.
Tuning.SIGNAL_REFRESH_SECONDS = 60
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

-- ── Over-potency crust (Contamination.secondsFor) ──────────────────────
--
-- The hose's potency USED TO BE A HARD WALL: a patch harder than it banked nothing,
-- sat there in slate grey, and the session ended on "that's as far as this liquid
-- goes". An Epic or Legendary under a tier 2-3 hose simply would not move. It is now
-- the same steep soft gradient the magnet got above -- each point of hardness past
-- the stream's potency divides the patch's clock by this again:
--   seconds = base / WASH_POTENCY_FALLOFF ^ deficit    deficit = max(0, hardness - potency)
-- At 0.25 that is x4 at +1 (a slog), x16 at +2 (Epic on a Patched Fire Hose: ~40s on
-- its hardest chunk, against ~1.5s on its own rung), x64 at +3 (Legendary on the same
-- hose: ~3 minutes), x256 at +4 and x4096 at +6 (an Anomaly under a Garden Hose: about
-- five hours on one chunk -- possible, and nobody will). No message, no wall; the
-- stopwatch is the lesson. Spec §2 pins it.
Tuning.WASH_POTENCY_FALLOFF = 0.25

-- ── Weak points (WashService, Client/WashWeakSpots) ────────────────────
--
-- Every chunk of crust carries one glowing fallout-green blister on its outer face.
-- Water ON the blister soaks that chunk WASH_WEAK_MULT times faster, AND treats it as
-- WASH_WEAK_PIERCE points of hardness softer for the overmatch grind above -- which is
-- the under-tier hose's way in: a Legendary chunk on a Patched Fire Hose (+3, ~181s)
-- comes down to ~15s of blister time (181 / 4 / 3). Missing the blister is never worse
-- than the plain soak, so this is pure upside for aim.
--
-- A blister POPS after WASH_WEAK_POP seconds of water (banking an extra
-- WASH_WEAK_BURST seconds of blister-rate soak as it goes) and a fresh one grows
-- somewhere else on the same chunk WASH_WEAK_RESPAWN seconds later -- so the speed is
-- something you chase round the rock, not a spot you park the reticle on.
Tuning.WASH_WEAK_MULT = 3
Tuning.WASH_WEAK_PIERCE = 1
Tuning.WASH_WEAK_POP = 1.5
Tuning.WASH_WEAK_BURST = 0.4
Tuning.WASH_WEAK_RESPAWN = 1

-- ── Stage-scaled crust (Contamination.rollPatches) ─────────────────────
--
-- Crust hardness USED TO BE THE RARITY'S AND NOTHING ELSE, so a Stage 11 Legendary
-- came up exactly as soft as a Stage 4 one. Every patch on an item now gets this many
-- points on top of its rarity's hardness, by the stage it was dug in. Base Camp (1-6)
-- adds nothing -- its six hoses are fitted rung-for-rung to the rarity scale -- and
-- Toxic Twilight adds +1 a stage, which is what finally gives that camp's hoses
-- (power 8-12, Config/Gear.Cleaner) crust to be rated for: a Stage 11 Legendary is a
-- 10 (Quantum Rift), a Stage 12 Anomaly a 13 (one over Celestial Deluge, a liquid's
-- +2 covers it). Stages missing here add 0.
Tuning.CRUST_STAGE_BONUS = { [7] = 1, [8] = 2, [9] = 3, [10] = 4, [11] = 5, [12] = 6 }

-- ── Home-turf Common ease (DigService: `required`) ─────────────────────
--
-- The junk you pull most is Common, and in your own rated stage you pull a LOT of
-- it. At the starting magnet that mash runs ~7-11s a piece (a light cap ~7s, the
-- heavier "1 in 9" tin ~11s) -- too long for the thing that fills most of the bag.
-- This shortens `required` (the pull's rope length) for Common items by ~35%.
--
-- TWO CONDITIONS, BOTH CHECKED IN DigService, both deliberate:
--   * COMMON ONLY. Uncommon and up keep their full mash -- this is for the floor of
--     the catalogue, not a general pull buff. Keyed on the PER-PLAYER rolled rarity,
--     so a lucky detector's re-roll up to Rare pulls at Rare length.
--   * RATED SOIL ONLY (gripDeficit == 0). The moment the soil outclasses the magnet,
--     PULL_GRIP_FALLOFF is already grinding the haul down on purpose; an ease clawing
--     any of that back would blunt the exact gradient that pass exists to create. So
--     the two are mutually exclusive by construction -- this multiplier does not
--     apply over tier, at all.
--
-- `required` is the ONLY thing this touches, so clicks-to-hold (the mobile promise,
-- Spec §Step2) and the reveal/depth gate are untouched: an eased Common lands faster
-- once you are winning the mash, it is not easier to hold. Spec §Step2 pins the band.
Tuning.PULL_HOME_COMMON_EASE = 0.65 -- Common pulls ~35% faster in a stage the magnet is rated for

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

-- AN AURA NOBODY IS REVEALING ANY MORE DOES NOT VANISH, IT GOES OUT (on request: it
-- used to be destroyed on the first tick nobody's detector reached it, which meant
-- walking away blinked a whole starburst of cracks, a light and a fan of rays out of
-- existence between two frames -- the single most sudden thing in the field).
--
-- So the server keeps the model alive for AURA_LINGER seconds past its last reveal
-- with AURA_FADE_ATTR stamped true, and the client (client/SpotCracks) reads that flag
-- and eases the whole spot out -- cracks to transparent, rays sinking back into the
-- ground -- before the part ever leaves. The client's fade has to FINISH inside the
-- linger or the pop is back, so keep SpotCracks.FADE_OUT comfortably under this: the
-- difference is the ping budget for the attribute to replicate.
--
-- It doubles as hysteresis. Standing exactly on the radius boundary used to churn the
-- aura -- destroyed and rebuilt tick after tick, which rebuilt every crack part on
-- every client each time. Now the model survives the flicker and only the flag toggles,
-- and walking back in eases the same spot back up instead of re-fanning it.
--
-- A signal that is DUG still clears instantly (DigService.removeSignal). That is not a
-- reveal ending, it is the thing being gone, and a glow that lingers over empty ground
-- is a player walking to nothing.
Tuning.AURA_LINGER = 1.0 -- seconds an unrevealed aura stays in the world, fading
Tuning.AURA_FADE_ATTR = "Fading" -- attribute the server stamps on a lingering aura
-- Stamped with the puller's rarity reading while someone is LOCKED onto the spot, so
-- every client lights it, detector reading or not (DigService.reconcileAuras).
Tuning.AURA_PULLED_ATTR = "Pulled"
-- Stamped alongside it: the crack scale of the puller's nuke (Weight.crackScale), so
-- the cracks everyone sees are as big as the thing coming up.
Tuning.AURA_PULLED_SCALE_ATTR = "PulledScale"

-- The aura is a STARBURST OF GLOWING CRACKS now (on request; it was a pulsing well
-- with a dome and ripple rings, and before that a pillar). Flat on the ground: a hot
-- spot where the cracks meet, dark jagged cracks running out from it, and light
-- pulsing out along them to the tips. It hugs the ground on purpose -- the tall thin
-- pillar was too close to PLAN 10.9's server-wide "Legendary pulled" beacon.
--
-- All three sizes are at WellScale 1 and multiply by Config/Weight.crackScale
-- (0.75..~4.7), off the NUKE'S SIZE: an ordinary find's cracks reach ~3 studs out, a
-- heavy GIGA roll's well over 10, far past
-- DIG_RADIUS (you still have to stand on the hot spot).
Tuning.AURA_CORE = 0.8 -- the hot spot where the cracks meet, diameter in studs -- the spot to stand on
Tuning.AURA_CRACK_LENGTH = 3.1 -- a crack's length ALONG its jagged path, studs (each varies 0.75..1.25x); the kinks mean it reaches ~80% of that out from the centre
Tuning.AURA_CRACK_WIDTH = 0.45 -- a crack's width at its root, studs; it tapers to ~15% at the tip

-- "More lines of light for rarer finds." By the reading's rarity: how many cracks split
-- out of the spot and whether they fork, and how many rarity-coloured rays stand up out
-- of it (`rays`) and how tall (`rayHeight`, studs). Per-PLAYER, like the tint: the aura
-- is shared but the roll under it is not, so client/SpotCracks builds all of this
-- locally.
--
-- THE RAYS ARE A FIXED FAN THAT BLINKS (on request, after a version where they popped
-- up at random read as noise): always out, narrow at the ground and wide at the top,
-- each ray fading in and out on its own beat. Commons get a real fan too -- the ladder
-- is kept flat on purpose (5 rays -> 10); rarity is already loud in the crack count
-- and the colour, the rays only have to lean with it.
--
-- RARE AND UP GET A BIGGER FAN (on request): from Rare the rays climb steeply, 9 studs
-- for a Rare to 20 for an Anomaly, and `rayWidth` fattens them (foot and top) from
-- 1.35x to 3.2x, so a good spot throws a visibly larger burst of light. Commons and
-- Uncommons keep the small fan.
--
-- And the fan MOVES more the rarer it is: `raySpeed` multiplies how fast each ray
-- blinks, `raySpin` turns the whole fan around the spot (rad/s, direction picked per
-- spot), and `rayPump` is how far each ray's length surges and falls back on its own
-- beat (0.35 = down to 65% of full). All three are 1/0/0 below Rare, i.e. still.
-- `crackSpeed` does the same for the light running out along the cracks: it
-- multiplies how fast each pulse races from the hot spot to the tips (1 below Rare).
--
-- They stand ~6-20 studs, which does break the old "the spot hugs the ground" rule --
-- on request. That rule existed so a spot could never be mistaken for PLAN 10.9's
-- server-wide "Legendary pulled" beacon, which is not built yet. When it is, keep it a
-- single steady pillar, well taller than this, so a blinking fan and a beacon stay two
-- different things at a glance.
Tuning.AURA_CRACKS = {
	Scrap = { count = 3, forks = false, rays = 5, rayHeight = 6.0, rayWidth = 1.0, raySpeed = 1.0, raySpin = 0.0, rayPump = 0.0, crackSpeed = 1.0 },
	Common = { count = 3, forks = false, rays = 5, rayHeight = 6.0, rayWidth = 1.0, raySpeed = 1.0, raySpin = 0.0, rayPump = 0.0, crackSpeed = 1.0 },
	Uncommon = { count = 4, forks = false, rays = 6, rayHeight = 6.5, rayWidth = 1.0, raySpeed = 1.0, raySpin = 0.0, rayPump = 0.0, crackSpeed = 1.0 },
	Rare = { count = 5, forks = false, rays = 6, rayHeight = 9.0, rayWidth = 1.35, raySpeed = 1.4, raySpin = 0.25, rayPump = 0.15, crackSpeed = 1.5 },
	Epic = { count = 6, forks = true, rays = 7, rayHeight = 11.5, rayWidth = 1.7, raySpeed = 1.8, raySpin = 0.4, rayPump = 0.2, crackSpeed = 2.0 },
	Legendary = { count = 8, forks = true, rays = 8, rayHeight = 14.0, rayWidth = 2.1, raySpeed = 2.3, raySpin = 0.6, rayPump = 0.25, crackSpeed = 2.6 },
	Mythic = { count = 10, forks = true, rays = 9, rayHeight = 17.0, rayWidth = 2.6, raySpeed = 2.9, raySpin = 0.85, rayPump = 0.3, crackSpeed = 3.2 },
	Anomaly = { count = 12, forks = true, rays = 10, rayHeight = 20.0, rayWidth = 3.2, raySpeed = 3.6, raySpin = 1.2, rayPump = 0.35, crackSpeed = 4.0 },
} :: { [string]: { count: number, forks: boolean, rays: number, rayHeight: number, rayWidth: number, raySpeed: number, raySpin: number, rayPump: number, crackSpeed: number } }

-- The range ring the detector draws on the ground around YOU. Client-side, so unlike
-- the auras it is yours alone — it answers "what am I actually sweeping right now",
-- which stopped being obvious the moment the needle went away.
--
-- IT IS A SONAR SWEEP NOW (on request). It used to be two dashed circles: a faint one
-- sitting on the radius and a second that expanded out to it once a second. The circle
-- said how far, but it said it the way a decal would — nothing about it read as an
-- instrument doing work. So an arm turns around you dragging a fading wedge behind it,
-- and each dash of the rim lights as the arm goes past and cools off behind it.
--
-- THE EXPANDING PULSE IS GONE ON PURPOSE. Two things growing out of the player at once
-- read as noise, and a rim that lights in sequence already says "this is live" without
-- a second ring crossing the ground every second.
Tuning.RANGE_RING_PERIOD = 1.0 -- seconds; the HUD pick-up card's stroke shimmer still beats on this
Tuning.RANGE_RING_SEGMENTS = 48 -- thin parts per ring; asset-free, so no texture to load

-- One revolution takes SIX beats of RANGE_RING_PERIOD, deliberately: a radar that goes
-- round once a second reads as a spinner, and the sweep has to feel like it is looking
-- rather than hurrying. Slower than about 8s and it stops registering as motion at all.
Tuning.RANGE_SWEEP_PERIOD = 6.0 -- seconds for one full turn of the arm
Tuning.RANGE_SWEEP_SPAN = 1.25 -- radians of wedge trailing the arm (~72°)
Tuning.RANGE_SWEEP_SLICES = 12 -- wedge slices; the fade steps once per slice, so this is its smoothness
Tuning.RANGE_SWEEP_ALPHA = 0.26 -- opacity of the slice right behind the arm; the rest fall off as its square
Tuning.RANGE_SWEEP_COMET = 0.9 -- radians of rim left glowing behind the arm

-- ── The fluid spin (Config/Liquids) ─────────────────────────────────────
--
-- Press E on the fluid bottle beside the tub and a spin plays on your screen, landing
-- on a fluid (build/Plots.buildFluidBottle, Services/LiquidService, the client's
-- LiquidController). It replaced the wash pad's paid step-on roll, on request.
--
-- FREE, AND THE COOLDOWN IS THE ONLY THING STOPPING AN INFINITE RE-SPIN. The pad used
-- to charge $80 a roll with a 3s debounce; the user asked for a free spin on a longer
-- cooldown instead. A minute is long enough that you go and do something between
-- spins -- dig, wash, sell -- rather than standing at the bottle mashing E until
-- Stardust lands, and short enough that a spin is always nearly ready when you get
-- home. `charges` still limits how much value one good spin can be turned into.
Tuning.LIQUID_SPIN_COOLDOWN = 5 * 60 -- seconds between spins, per player (5 minutes)
-- BREWS BANK UP, on request: one brew is banked every LIQUID_SPIN_COOLDOWN (online or
-- off) and saved, so a player who comes back after a while can roll several in a row.
-- Capped so a day away is not a few hundred rolls; once full, the clock stops.
Tuning.BREW_MAX_STORED = 24 -- two hours' worth at 5 minutes
Tuning.BREW_START_STORED = 1 -- a brand-new player's first brew is ready
-- Skip Brew Timer: a Developer Product that ends the brew cooldown now (LiquidService).
-- 0 = not set up yet; the button under BREW shows SOON.
Tuning.BREW_SKIP_PRODUCT_ID = 3716086220
Tuning.LIQUID_INFINITE = true -- rolled fluids never run out (spendCharge is a no-op)

-- How long the spin runs on screen before it lands. The bottle recolours when it
-- lands, not when the server rolls, so the reveal is not spoilt by the world behind
-- the popup. Spec pins it under the cooldown.
Tuning.LIQUID_SPIN_SECONDS = 4

-- Charges stack when you spin the same liquid twice, up to this multiple of the
-- liquid's own `charges`. Without a ceiling, a player who spins every minute for an
-- hour accumulates an unbounded Stardust supply and the bottle stops being somewhere
-- you ever need to go back to — which is the exact failure the charge system exists
-- to prevent. Five spins' worth is generous enough that nobody hits it by accident.
Tuning.LIQUID_MAX_STACK = 5

Tuning.DIRTY_SELL_MULTIPLIER = 0.12
-- CLEAN nukes only sell for this much more (on request: heavily raised sell prices,
-- dirty/blind sales left as they were). Stand income is untouched.
Tuning.CLEAN_SELL_MULTIPLIER = 5
Tuning.ASSAY_FEE_FRACTION = 0.02

-- ── Exhibition (PLAN §8.2) ────────────────────────────────────────────────────
-- Offline stands pay this share of their live $/s. 0.15 -> 0.04 on request (AFK nerf).
-- Cap 4 h -> 12 h with the rate cut to a third (0.04 -> 0.013), so a full 12 h away
-- pays a touch less than the old 4 h maximum; time past 12 h earns nothing.
Tuning.EXHIBIT_OFFLINE_RATE = 0.013
Tuning.EXHIBIT_OFFLINE_BANK_HOURS = 12
-- Every copy of an item pays in full; the old 100/40/15/5% duplicate damping is gone.
Tuning.EXHIBIT_DUPLICATE_YIELD = { 1.0 }
-- The crating lock (a nuke just put up can't come off for this long) is off, on
-- request: 0 lets a take / swap / Unequip happen straight away.
Tuning.EXHIBIT_UNCRATE_SECONDS = 0
-- Every stand a base can ever have, across all of its floors (Config/Floors): the
-- ground floor's 12 are free from the start, and each floor bought on top adds 8
-- more. How many a given player has unlocked is `Floors.slotsFor(data.exhibit.floors)`
-- -- this is the ceiling loops that scan "every stand" walk up to.
Tuning.EXHIBIT_MAX_SLOTS = require(script.Parent.Floors).MAX_SLOTS
-- There is NO hourly cap on stand income any more (balance/economy-pacing-pass): stands
-- pay exactly what their nukes earn. See ExhibitService's header.

-- How long E has to be held on a stand's own ProximityPrompt (place/take/swap).
Tuning.EXHIBIT_STAND_HOLD_SECONDS = 0.6

-- ── Progression (PLAN §9.2) ───────────────────────────────────────────────────
Tuning.LEVEL_CAP = 100
Tuning.RESIST_PER_LEVEL = 0.01
Tuning.RESIST_CAP = 0.40
Tuning.CAPACITY_EVERY_N_LEVELS = 5

-- ── The wash reveal ───────────────────────────────────────────────────────────
-- How long the clean nuke holds the screen once the last chunk of crust comes off,
-- before the wash bay hands the camera back. WashService owns the real clock; the
-- client (WashReveal) reads the same number to pace its slow push-in across it. Long
-- enough for the name to land and the price to count up, short enough to be a beat
-- rather than a wait -- and E/Q skips it anyway.
Tuning.WASH_REVEAL_HOLD = 4

-- The wash bay's lens, vertical field of view in degrees. WashController shoots the
-- wash through it (see WASH_FOV there for why it is wider than the default 70), and
-- WashService reads it to decide how far back to plant the player so a big lump
-- still fits in the frame. One number, so the two cannot disagree about the picture.
Tuning.WASH_FOV = 72
-- ...and where that lens sits: studs forward of the head's centre, along the view.
-- Same reason it is here: WashService measures the frame from this point.
Tuning.WASH_EYE_FORWARD = 0.4

-- THE INDEX'S STAGE REWARD. Identify every nuke a stage stocks and your detector reads
-- that stage with this much more dig luck, forever (Shared/IndexProgress, applied in
-- DigService's rollFor). Added to the detector's own `luck`, not multiplied: a tier-1
-- Rust Bucket (1.00) becomes 1.10, just under the Scrap Sweeper's 1.12, so a completed
-- stage is worth most of the first real detector purchase there and a small nudge on an
-- Oracle. (The $15 Bent Coil between them is a tutorial step, not a rung this is sized
-- against -- see Config/Gear.) Items
-- stocked in two stages count toward both.
Tuning.INDEX_COMPLETE_LUCK = 0.10

--- FROM THIS STAGE ON, the luck reward is a MULTIPLIER instead: a completed index makes
--- the detector's luck in that stage x INDEX_COMPLETE_LUCK_MULT, in place of the flat
--- +INDEX_COMPLETE_LUCK. Stages 7-12 are dug with Twilight detectors (luck 2.80-4.30,
--- Config/Gear), where +0.10 is a rounding error; x1.1 there is worth +0.28 to +0.43.
--- Same scope as the flat bonus: that stage's signals only.
Tuning.INDEX_LUCK_MULT_FROM_STAGE = 7
Tuning.INDEX_COMPLETE_LUCK_MULT = 1.1

--- The CASH half of the same reward: every stage whose index is complete multiplies ALL
--- cash earned -- sales and stand income alike (and so away earnings) -- by this much.
--- Unlike the luck it is not tied to the stage: it stacks across stages, multiplied, so
--- two complete stages are x1.21. Folded into StatResolver's sellMultiplier and
--- yieldMultiplier via IndexProgress.cashMultiplier.
Tuning.INDEX_COMPLETE_CASH = 1.1

--- FROM THIS STAGE ON, a completed index pays INDEX_COMPLETE_CASH_LATE instead of
--- INDEX_COMPLETE_CASH: the far stages are much longer to finish, so they pay more.
--- Stacks the same way -- all twelve are 1.1^6 x 1.2^6, about x5.32.
Tuning.INDEX_CASH_LATE_FROM_STAGE = 7
Tuning.INDEX_COMPLETE_CASH_LATE = 1.2

--- WHO MAY STEAL A DROPPED BAG: only a player whose deepest stage reached
--- (data.stats.deepestStage, published as the DeepestStage attribute) is at least this.
--- Keeps the first three stages a safe place to learn; your OWN bag is always yours to
--- recover. ExposureService.giveBagTo enforces it; DroppedBagController words the prompt.
Tuning.STEAL_MIN_STAGE = 4

--- RECOVER BAG, the Robux product that puts a dropped bag's whole contents back in
--- your carry wherever you are (ExposureService; the button is on the death screen and
--- the bag tracker pill). 0 = not set up: the buttons read SOON and nothing registers.
Tuning.BAG_RECOVER_PRODUCT_ID = 3716083374

--- Seconds after a bag drops in which ONLY its owner may take from it, so they have
--- time to press Recover before anyone can grab it.
Tuning.BAG_STEAL_GRACE = 3

--- While the owner's Recover purchase dialog is open the bag is held: nobody can steal
--- it and it cannot time out, so a purchase never lands on a bag someone emptied
--- mid-dialog. Capped at this many seconds in total per bag, so pressing Recover and
--- leaving the dialog up cannot shield a bag from thieves for long.
Tuning.BAG_RECOVER_HOLD_MAX = 30

return Tuning
