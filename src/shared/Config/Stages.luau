--!strict
-- Stages.lua — PLAN §4.
--
-- NOTE: `ratedSuitTier` is documentation, not enforcement. There is no gate anywhere
-- in this codebase that reads it to deny entry. Stages are open (PLAN §3.5); the only
-- thing that stops a player is the arithmetic in Shared/Radiation.lua.
--
-- ── SPATIAL FIELDS ──────────────────────────────────────────────────────────
-- `center` / `size` are the stage's footprint in world XZ. They are the source of
-- truth for build/StageFields.luau, which turns them into the plates that
-- DigService and StageService both read. Two independent lookups have to agree:
--
--     DigService.stagePart   Workspace.Stages:FindFirstChild("Stage" .. id)   -- by NAME
--     StageService.stageAt    iterates children reading attribute StageId     -- by ATTRIBUTE
--
-- The generator writes both from the same loop index so they cannot drift apart.
--
-- ── HOW SIZE WAS CHOSEN, WHICH IS NOT ARBITRARY ─────────────────────────────
-- DigService tops each stage up to its own `signals` count (a StageDef field below)
-- of buried signals. That count does not scale with area on its own, so for a fixed
-- footprint `signals` is the only lever on how hard a stage is to search. Every
-- stage shares one footprint since the uniform-length pass, so `area / signals` —
-- and every search metric below — is decided by `signals` alone.
--
-- IT USED TO BE ONE GLOBAL NUMBER (Tuning.SIGNALS_PER_STAGE, now deleted) held
-- proportional to the footprint: 96,000 / 90, then 80,000 / 75, both = 1066.67. It is
-- PER-STAGE now: the farm stages 1-3 run calmer at `signals = 60` (`area / 60` = 1333,
-- a contact about every 2.6s on the starting detector); the dive stages 4-6 stay dense
-- at 75, because a short lethal window (PLAN §3.5, §16) is time you want spent hauling,
-- not searching. Change a stage's footprint and you re-derive that feel; `signals` is
-- where you set it.
--
-- Define coverage:
--
--     c = N * pi * r^2 / area          (N / area held constant, so c is too)
--
-- Under the reveal detector c has a much more direct reading than it used to: it is
-- the EXPECTED NUMBER OF CONTACTS lit up around a player standing still. c = 0.11
-- means nine times out of ten you are looking at empty ground and have to walk.
--
-- THE METRIC THAT ACTUALLY DRIVES THE FEEL IS TIME, NOT AREA. A reveal detector
-- sweeps a corridor of width 2r as the player walks, so what a player experiences is
-- the gap between one glow going out and the next coming up:
--
--     seconds between contacts = (area / N) / (2 * r * walkSpeed)
--
-- That is Stages.secondsBetweenContacts, and it is the number to tune against. PLAN
-- §2 wants a 20-40s loop at the low end; the walk is supposed to be a chunk of that,
-- not all of it.
--
-- ── UNIFORM LENGTH PASS ────────────────────────────────────────────────────
-- Every stage is the SAME footprint: FOOTPRINT_X long (X, the walk axis) by
-- FOOTPRINT_Z wide (Z), 400 x 200. This finishes what the earlier uniform-depth
-- pass started — Stage 1 and Stage 5 used to be 600-660 long against 220-360 for
-- the rest, which read on the ground as long empty walks through the two big
-- stages and quick hops through the others. Identical footprints take the area
-- lever off the table, leaving each stage's `signals` count (below) as the one
-- clean knob for how hard THAT stage is to search.
--
--     farm 1-3:  400 x 200   area 80,000   60 signals   mean gap ~18 studs
--     dive 4-6:  400 x 200   area 80,000   75 signals   mean gap ~16 studs
--
-- WIDTH WENT 240 -> 200 (the whole chain got narrower, on request); the then-global
-- N went 90 -> 75 with it to hold the feel. Then the farm stages went 75 -> 60 on
-- request — a contact every ~2s read as too busy — while the dives held at 75, so
-- `signals` stopped being global. secondsBetweenContacts / coverage / meanSignalGap
-- all take it as a parameter, so callers pass `def.signals`.
--
-- WHAT 60 COSTS, RECORDED NOT HIDDEN: fewer buried signals means fewer digs per
-- minute, so a lower wall-clock rate of EVERY rarity in the farm zones (~20% under
-- 75). Per-dig rarity odds are UNCHANGED — those come from the loot weights alone
-- (see the loot-weight section below). Spec's Stage-1 `rarePlus` floor moved to
-- match the smaller buried-jackpot snapshot; its secondsBetweenContacts band
-- (1.2-5s) still holds at 60 (~2.6s). Retune a stage's search from its own
-- `signals`; footprints stay uniform.
--
-- ALL SIX ARE BUILT, BUT ONLY STAGE 1 HAS EVER BEEN PLAYED. The other five now
-- share Stage 1's footprint exactly, so whatever the search feels like there is
-- what it feels like everywhere — but 2-6 have never been walked to confirm it.
--
-- ── WHERE THEY ARE, AND WHY THEY MOVED ──────────────────────────────────────
-- There is no terrain in this world: off the built parts is void, so a stage that
-- touches nothing walkable is a stage nobody can reach. Four of the five needed
-- moving for that reason or because they overlapped Stage 1.
--
--     camp ═══> [ 1 Ash Flats ] [ 2 Suburbs ] [ 3 Fallout ] [ 4 Exclusion ] [ 5 Reactor ] [ 6 Crater ]
--       x            100-500      500-900      900-1300     1300-1700       1700-2100     2100-2500
--
-- ONE STRAIGHT CHAIN NOW, TIER-ORDERED, NOT A SIDE SPUR. Stage 4 used to sit north of
-- Stage 1, touching only its west edge — close enough to camp that a fresh player
-- crossed into it by accident, which was the point: PLAN §3.5's "the Dive" wants the
-- lethal field to be somewhere you are standing anyway, not an expedition. Pulled out
-- of the camp's doorstep and slotted between Stage 3 and Stage 5 instead, so walking
-- straight into it now means passing through Stages 1-3 first — a deliberate 1-2-3-4-
-- 5-6 tier progression rather than a spur. That trades away the accidental-dive
-- framing PLAN §3.5 describes; see the note on the Stage 4 def below.
--
-- The chain shares edges exactly, the same way the plaza's east edge already lands
-- on Stage 1's west edge: `rectsOverlap` fails on `<`, not `<=`, so a shared edge is
-- touching rather than overlapping and World.verify() accepts it. Walk east and it
-- gets worse; that is the whole layout. The uniform-length pass re-butted every
-- centre off Stage 1's fixed west edge (x = 100) at a flat 400 pitch, so every
-- stage from 2 on now sits at a different x than it did before.
--
-- ── THE COLOUR TURNS AT STAGE 4 ──────────────────────────────────────────────
-- Stages 1-3 are the known world and stay green-to-tan. Then each of the last three
-- is its own KIND of place rather than more of the same one — the thing a player
-- reads before they read any number (all changed from the original plum/magenta/
-- violet trio on request):
--   4  dead muddy brown  — nothing grows here
--   5  soft light pink   — candy-bright, wrong, after the brown
--   6  violet            — the Crater (unchanged)
--
-- The muted-plate / bright-Neon colour-note below was written for the old deep
-- plum/magenta plates and the Neon POOLS over them. It no longer bites here: the
-- floor is now an UNtinted studded checkerboard (build/Scenery), Plastic not Neon,
-- so there is no bloom to turn a balanced pink to white — Stage 5 gets to just be
-- light pink. Still worth reading before touching Stage 6's violet or the pools if
-- the scenery rework brings Neon back.
--
-- The header used to carry a hard ceiling of area <= 785 * r^2, i.e. c >= 0.18. Every
-- stage has been well over that ceiling for a long time (Stage 1 at c = 0.096 even
-- before it grew), and the uniform-length pass drops the area further still — so the
-- rule describes a stage layout that has not existed for many passes and is left here
-- as history, not a check. Use the time column, and a stage's own `signals` to move it.
--
-- COLOUR NOTE: the plate is the SLUDGE and it is deliberately deep and muted. The
-- bright colour belongs to the pools and spills in build/Scenery, which are Neon —
-- each stage's own, from its `ooze` field, since the field stopped being green at Stage
-- 4. Making the plate pale too was the first attempt and it read as a golf course
-- from ground level: with no tonal gap between ground and pool, nothing glowed and
-- nothing looked toxic. Contrast is what sells "radioactive", not brightness.
--
-- Stage 4 is the deliberate inversion. It is a dive, not a farm (PLAN §3.5): you get
-- roughly 35 seconds in it one tier under. A field where you nearly always have a
-- ping is exactly right for "grab one thing and run", and it means that window is
-- spent hauling rather than searching. Without the inversion the Stage 4 dive would
-- fail its own validation test (PLAN §15, question 2) for the wrong reason.
--
-- `stationDistance` is measured, not aspirational — see the note on it below.
--
-- ── HOW THE LOOT WEIGHTS WERE RE-DERIVED, WHICH IS ALSO NOT ARBITRARY ────────
-- These are RELATIVE weights, normalised at roll time, so only their ratios matter.
--
-- Stages 1-3 were re-weighted when signal density doubled to 90. The reason is one
-- line of arithmetic that is very easy to get wrong: doubling the number of buried
-- signals doubles the rate of every rarity in the table, Legendaries included. Left
-- alone, "more items" would silently have meant "twice as many Legendaries", which
-- is the one thing a rarity economy cannot afford.
--
-- So the transformation was:
--   * every weight at Rare and above    -> halved, cancelling the density multiplier
--                                          exactly, so Rare+ arrives at the same
--                                          wall-clock rate it did at 45 signals
--   * Uncommon                          -> x0.7, a partial increase (about 1.4x)
--   * Scrap and Common                  -> absorb everything freed up, tilted toward
--                                          Common so what you dig up is mostly worth
--                                          picking up rather than mostly junk
--
-- Net effect in stage 1: ~2x the pulls, ~2.9x the Commons, ~1.7x the Scrap, and Rare
-- or better unchanged. Shared/Util/Spec pins that last property — it asserts Stage 1's
-- field holds a set number of Rare-or-better signals at once.
--
-- THE FARM ZONES THEN WENT 75 -> 60 WITH NO RE-WEIGHT, ON REQUEST (contacts felt too
-- dense). Unlike the 45 -> 90 move, this one is NOT cancelled in the table: fewer
-- signals is fewer digs, so the wall-clock rate of everything in stages 1-3 drops
-- ~20% — Legendaries included, in proportion. That is the accepted cost of a calmer
-- field; the per-dig ratios above do not move, so each dig FEELS the same, there are
-- just fewer of them. The dives (4-6) held at 75 and are untouched.
--
-- STAGES 4-6 WERE DELIBERATELY NOT RE-WEIGHTED, AND THAT DEBT IS NOW LIVE. Their
-- identity is "everything here is good" (PLAN §4 — the Crater is 18% Legendary on
-- purpose), and halving their top end to hold a wall-clock rate would be a redesign of
-- the stages rather than a rebalance of this one. The old note said to decide it when
-- they are built and playable. They are built: Stage 4 is stocked and diggable TODAY at
-- double its intended rare rate. Stages 5 and 6 are not stocked yet, so their share of
-- the debt is still deferred. See TODO.md.
--
-- CAVEAT ON ALL OF THE ABOVE: DigService.rollItemId steps DOWN when Config/Items does
-- not stock the rolled rarity in that stage, so the delivered distribution is always
-- at least as common as this table says, never rarer. Stage 1 stocks no Mythic or
-- Anomaly, so its top two rows are aspirational.
--
-- STAGES 5 AND 6 ARE NOW STOCKED (Config/Items.luau), which means the debt this
-- header already warned about is live rather than deferred: their loot weights
-- above were never re-derived for the 45 -> 90 density jump the way 1-3 were (and
-- they sit at 75, not the farm zones' 60, so the doubling still stands in full),
-- and "decide when they're built and playable" was the whole plan for that
-- decision. They are. See TODO.md — re-weighting is a real pass against
-- Config/Gear's detector radii, not a quick edit, and is intentionally not part
-- of stocking the catalogue.

export type StageDef = {
	id: number,
	name: string,
	baseRads: number, -- rads/sec at this stage's ENTRANCE (west) edge. See Stages.radsAt.
	deepRads: number, -- rads/sec at this stage's DEEPEST (east) edge. See Stages.radsAt.
	soilHardness: number,
	ratedSuitTier: number,
	stationDistance: number,
	fogColor: Color3,
	fogEnd: number,
	loot: { [string]: number }, -- rarity name -> weight (normalised at roll time)
	signals: number, -- buried signals DigService keeps topped up here. Per-stage — see the header.

	-- Spatial. See the header.
	center: { number }, -- { x, z } world space
	size: { number }, -- { x, z } footprint in studs
	color: string, -- hex; the ooze colour of this stage's surface
	material: string, -- Enum.Material name

	-- The stage's Neon channel: the wading surface, the pools, their rims and their
	-- lights. Per-stage since the harder stages stopped being green — build/Scenery
	-- used to paint every field from three globals in Kit.C, which would have left
	-- The Crater's violet ground under acid-green puddles.
	ooze: { bright: string, deep: string, glow: string },

	built: boolean, -- false => the generator skips it and verify() ignores it
}

local Stages = {}

--- The top face of every stage plate. Used to sit 1.5 studs below the plaza on
--- purpose (a physical "step down into the sludge" cue) -- that step is gone now,
--- on request: Hub.PLAZA.topY was moved to match this value exactly instead, so
--- camp flows into Stage 1 at one level. See Hub.luau's own comment on Hub.PLAZA for
--- why. This constant itself is unchanged; it was always the target, not the thing
--- that moved.
Stages.SURFACE_Y = -1.5

--- How strongly each stage's bright `ooze` colour is baked into its ground
--- colour. Replaces the old `OozeSurface` -- a separate translucent Neon plate
--- floating WADE_HEIGHT above the real floor -- which was removed on request
--- (the wading effect was never approved; the tint it produced was liked and
--- is kept here instead, flush with the ground). 0.55 rather than the old
--- part's nominal 0.18 opacity (1 - 0.82 transparency): Neon is emissive and
--- bloom pushes a translucent plate's apparent colour well past its raw alpha
--- (see build/Scenery.luau's old OozeSurface comment), so a plain alpha-style
--- blend at 0.18 reads far too faint next to what the removed layer actually
--- looked like. Tuned live against Stage 1, the only stage anyone has stood in.
Stages.GROUND_OOZE_TINT = 0.55

--- Plate thickness. DERIVED, not chosen: DigService buries at up to
--- DEPTH_BASE + 7*DEPTH_PER_RARITY + DEPTH_JITTER = 13.2 studs, and the haul part
--- is drawn at signal.position - depth while it rises. At 16 the deepest haul sits
--- 2.8 studs above the plate's underside, so it is never visible poking out from
--- below. Tuning.DIG_DEPTH_* and this constant are checked against each other in
--- Shared/Util/Spec.
Stages.PLATE_THICKNESS = 16

--- The one footprint every stage shares (see the UNIFORM LENGTH PASS header). X is
--- the walk axis; Z is the corridor width. `area / signals` is what sets a stage's
--- search feel — with the footprint uniform, each stage's own `signals` (a StageDef
--- field) is the knob; move this footprint and every stage's feel shifts at once.
local FOOTPRINT_X, FOOTPRINT_Z = 400, 200

Stages.DEFS = {
	{
		id = 1,
		name = "Ash Flats",
		-- DEPTH-BASED RADIATION PASS. Entrance (baseRads) is UNCHANGED from the old
		-- flat rate on every stage, deliberately -- every existing Spec check that
		-- reads "how safe is this stage" samples the entrance, so leaving it alone
		-- means none of that carefully-fitted tuning silently breaks. deepRads is
		-- the new number, 2.2x-2.5x the entrance depending on the stage (thinner on
		-- Stage 5 specifically to leave Stage 6 room to clear it without also
		-- breaking Stage 6's own dive/Crater checks -- see Stage 5 and Stage 6's own
		-- notes). See Stages.radsAt for how the two combine.
		--
		-- STAGE 1'S OWN GAP, closed in the second harshening pass: entrance (0.5) is
		-- BELOW the starting Cloth Wrap suit's tolerance (1.0) by design -- Stage 1's
		-- rated suit tier IS the starting tier, so a no-gear player must be able to
		-- farm the entrance forever (Spec's own farmable check requires it, though
		-- as of the third pass "forever" at the entrance is actually a ~9min cap --
		-- see Gear.luau's Cloth Wrap `reduction` note; that's an EXPOSURE-track
		-- change and does not touch this deepRads value at all).
		--
		-- deepRads RAISED AGAIN in the third pass, for a target that turns out to be
		-- about THIS stage's OWN far end, not the separate, far-away Stage 3: by
		-- depthFrac 0.652 (about two-thirds of the way across this stage) a player is
		-- under 30s from death, and by depthFrac 1.0 (this stage's true deepest point,
		-- its east edge) that is down to ~17s -- while staying just under Stage 2's
		-- baseRads (2.0), a thin but real 1.5% ordering margin. Going any higher
		-- breaks "Stage 1 is the safest stage" outright (Stage 2's own entrance would no
		-- longer be the harsher of the two) -- see Spec.luau's own depthFrac check
		-- and Tuning.luau's BURN_COEF comment for why an earlier pass chased a
		-- DIFFERENT, wrong target (the real Stage 3) instead.
		baseRads = 0.5,
		deepRads = 1.97, -- 3.94x
		soilHardness = 1,
		ratedSuitTier = 1,
		-- Was 230 before the hub-to-field connector shrank by 40 studs (Hub.luau's
		-- CampToRadiationRoad) so the plaza and the field read as one connected
		-- complex rather than two places joined by a long empty road. Re-measured
		-- by that same 40, not re-walked stud-for-stud — close enough to stay
		-- honest per the header's "measured, not aspirational" rule without
		-- re-deriving the whole number from scratch.
		stationDistance = 190,
		fogColor = Color3.fromHex("CFF3FF"),
		fogEnd = 900,
		loot = { Scrap = 48, Common = 41, Uncommon = 8.4, Rare = 2, Epic = 0.4, Legendary = 0.075, Mythic = 0.02, Anomaly = 0.001 },
		signals = 60, -- farm zone: calmer than the dives. See the header.
		-- West edge pinned at x = 100 (Hub.PLAZA.maxX); centre = 100 + 400/2.
		center = { 300, 0 },
		-- UNIFORM LENGTH PASS: 400 x 200 (FOOTPRINT_X/Z), the shared footprint of all six stages —
		-- see the header. Was 660 long (and 320, then 240, then 200 wide); length is
		-- the axis that made Stage 1 a long empty walk. Stage 1's WEST edge did not move, so
		-- its entrance-side tuning (stationDistance, the deepRads/depthFrac notes
		-- above) is untouched; only the east half pulled in.
		size = { FOOTPRINT_X, FOOTPRINT_Z },
		-- The east-edge endpoint of buildStage1Checkerboard's plaza-to-here gradient
		-- (see Scenery.luau) — this base colour is never actually seen as a flat
		-- fill, only blended toward across the plate, and the fallback should match
		-- the stage's OWN east/dead end, not its green west end, since that is what
		-- borders Stage 2 across the boundary blend. See "LIFE FADING INTO A DEAD
		-- WASTELAND" below for the whole Stage 1-3 palette.
		color = "C2A171",
		-- GRASS, NOT SAND, ON REQUEST -- Stage 1 only. `material` applies to the whole
		-- plate uniformly (see Scenery.luau), so this reads as real grass under the
		-- green west end and as dry, dying grass under the tan east end -- not sand
		-- under either any more.
		--
		-- THIS BREAKS THE "SAND FAMILY" STAGES 1-3 USED TO SHARE. Stage 3's own
		-- comment below (`material = "Sand"`) explains why it moved off Slate onto
		-- Sand: continuity with the rest of this stretch. Stages 2 and 3 are still
		-- Sand, so Stage 1's own east edge meets Stage 2's Suburbs across a material
		-- seam even though `buildStageBlend` still blends their COLOUR smoothly --
		-- texture does not blend, only hue does. Left as the honest cost of a
		-- Stage-1-only change rather than silently reskinning stages nobody asked to
		-- change.
		material = "Grass",
		-- Muted on purpose — see the note below. Nowhere near today's old 6BEE2E, and
		-- nowhere near the last three stages' territory either (muddy brown, light
		-- pink, violet now — see the header).
		ooze = { bright = "7CBF52", deep = "35501F", glow = "5C9A3C" },
		built = true,
	},
	{
		id = 2,
		name = "The Suburbs",
		baseRads = 2,
		deepRads = 5.0, -- 2.5x
		soilHardness = 2,
		ratedSuitTier = 2,
		-- Was 719 when this stage's entrance sat at x = 760; the uniform-length pass
		-- pulled its west edge in to x = 500, so this is that walk minus ~260. Still
		-- an estimate, not re-walked — same caveat as before.
		stationDistance = 460,
		-- Was a pale yellow-green — clashed with the dun/tan ground once that
		-- stopped being green. Dusty tan haze instead.
		fogColor = Color3.fromHex("E8D9B0"),
		fogEnd = 800,
		loot = { Scrap = 43, Common = 39, Uncommon = 12.6, Rare = 3.5, Epic = 1, Legendary = 0.25, Mythic = 0.05, Anomaly = 0.002 },
		signals = 60, -- farm zone
		-- West edge = Stage 1's east edge (x = 500); centre = 500 + 400/2.
		center = { 700, 0 },
		-- UNIFORM LENGTH PASS: 400 x 200 (FOOTPRINT_X/Z), the shared footprint — see the header. Was
		-- 220 long, the shortest stage; it grew to match the rest.
		size = { FOOTPRINT_X, FOOTPRINT_Z },
		-- Dun/tan, not green — see "LIFE FADING INTO A DEAD WASTELAND" below.
		color = "B8935F",
		material = "Sand",
		-- Corrected after a live look: the first pass (8FB358) was not green-DOMINANT
		-- enough — R was 80% of G, and Neon + bloom pushed it to cream, the exact
		-- failure this file's own header warns about ("a yellow-green like #B6FF6E
		-- comes out of Neon + bloom as cream and stops reading as toxic at all").
		-- Same family as Stage 1's ooze, just a touch deeper — R/G ratio close to
		-- Stage 1's ~0.65 instead of drifting toward yellow.
		ooze = { bright = "6FA84A", deep = "30481C", glow = "519438" },
		built = true,
	},
	{
		id = 3,
		name = "Fallout Fields",
		baseRads = 6,
		deepRads = 14.4, -- 2.4x, not 2.5 -- clears Stage 2's deepest (5.0) with room,
		-- and 2.4 rather than 2.5 leaves Stage 4's unchanged entrance (15) a small
		-- but real margin over this stage's deepest instead of landing exactly on it.
		soilHardness = 3,
		ratedSuitTier = 3,
		-- Was 939 at an x = 980 entrance; uniform-length pulled the west edge to
		-- x = 900. Estimate, not re-walked.
		stationDistance = 860,
		-- Was a bright yellow-green — same clash as Stage 2's, deeper. Warmer dusty
		-- khaki haze for the gradient's endpoint.
		fogColor = Color3.fromHex("D4B896"),
		fogEnd = 700,
		-- NO SCRAP TIER, ON REQUEST (Config/Items.luau's own header) -- Stage 3's old
		-- Scrap weight (34) folded straight into Common (40 -> 74) rather than left
		-- allocated to a rarity the catalogue no longer stocks here, which would
		-- otherwise silently produce dead rolls (DigService.rollItemId's step-down
		-- bottoms out at Scrap with nothing below it to fall back to).
		loot = { Common = 74, Uncommon = 16.8, Rare = 6, Epic = 2.25, Legendary = 0.6, Mythic = 0.14, Anomaly = 0.005 },
		signals = 60, -- farm zone
		-- West edge = Stage 2's east edge (x = 900); centre = 900 + 400/2.
		center = { 1100, 0 },
		-- UNIFORM LENGTH PASS: 400 x 200 (FOOTPRINT_X/Z), the shared footprint — see the header.
		-- Was 260 long.
		size = { FOOTPRINT_X, FOOTPRINT_Z },
		-- Deeper desert khaki-brown — the endpoint of the Stage 1-3 gradient. Slate
		-- read as dark grey rock and broke continuity with the sand family this
		-- whole stretch depends on, so material moved to Sand too.
		color = "A67C4E",
		material = "Sand",
		-- Same green-dominance fix as Stage 2's — see that stage's comment. Slightly
		-- darker again, the gradient's endpoint, but the same hue family throughout.
		ooze = { bright = "649C42", deep = "2C4018", glow = "488432" },
		built = true,
	},
	{
		id = 4,
		name = "The Exclusion Belt",
		baseRads = 15,
		deepRads = 37.5, -- 2.5x
		soilHardness = 4,
		ratedSuitTier = 4,
		-- USED TO BE DELIBERATELY SHORT, AND IS NOT ANY MORE. PLAN §15's second
		-- validation question is "do players cross into Stage 4 unrated, on purpose,
		-- more than once?" — once answerable because the field sat off the camp's
		-- doorstep, then already traded away when Stage 4 moved into the east chain
		-- between 3 and 5 (a straight tier-ordered progression, not a side spur — see
		-- the header). The uniform-length pass finishes that trade: at 400 long like
		-- every other stage it reads purely as "the next stage." The brutality is
		-- unchanged — 15 rads at the entrance climbing to 37.5, now stretched across
		-- 400 studs instead of 290 — and still a real risk to under-tiered players
		-- passing through.
		--
		-- stationDistance: entrance moved from x = 1240 to x = 1300, so the old rough
		-- 1200 nudges up. Still NOT walked — re-measure in Studio next time someone
		-- is in this file, same as Stage 6's placeholder.
		stationDistance = 1260,
		fogColor = Color3.fromHex("6FE04A"),
		fogEnd = 600,
		-- NO SCRAP TIER, ON REQUEST -- see Stage 3's own comment on this above; same
		-- fold, this stage's old Scrap weight (15) folded into Common (24 -> 39).
		loot = { Common = 39, Uncommon = 28, Rare = 20, Epic = 9, Legendary = 3, Mythic = 0.8, Anomaly = 0.03 },
		signals = 75, -- dive: a ~35s window is time for hauling, not searching (PLAN §3.5). Stays dense.
		-- West edge = Stage 3's east edge (x = 1300); centre = 1300 + 400/2.
		center = { 1500, 0 },
		-- UNIFORM LENGTH PASS: 400 x 200 (FOOTPRINT_X/Z), the shared footprint — see the header. Was
		-- 290 long, the "deliberately short" dive; that framing is gone (comment
		-- above).
		size = { FOOTPRINT_X, FOOTPRINT_Z },
		-- WHERE THE GREEN STOPS. See "THE COLOUR TURNS" in the header. A dead muddy
		-- brown, on request (was a deep plum, "73246B") — nothing grows here any
		-- more; the pink/violet doesn't start until Stage 5. The checkerboard floor
		-- (build/Scenery buildStageCheckerboard) is UNtinted, so this is exactly the
		-- colour the ground reads as.
		color = "3F2D1D",
		material = "Slate",
		ooze = { bright = "FF2FA8", deep = "6B0A47", glow = "FF2FA8" },
		built = true,
	},
	{
		id = 5,
		name = "Reactor Grounds",
		baseRads = 40,
		deepRads = 88, -- 2.2x, not 2.5 -- Tier 5's suit tolerance (98.4) and Tier 6's
		-- (105) sit only 6.7% apart, so Stage 6's unchanged entrance (100) has very
		-- little headroom to clear this stage's deepest point without ALSO blowing
		-- past what a Sealed Exo-Suit or Containment Rig can absorb (breaking Stage
		-- 6's own dive/Crater checks). Softening this stage's own multiplier is what
		-- buys that room back, rather than inflating Stage 6 to compensate.
		soilHardness = 5,
		ratedSuitTier = 5,
		stationDistance = 1660, -- entrance moved x=1530 -> x=1700 in the uniform-length pass; est., not re-walked
		fogColor = Color3.fromHex("C8E85A"),
		fogEnd = 500,
		-- NO SCRAP TIER, ON REQUEST -- see Stage 3's own comment on this above; same
		-- fold, this stage's old Scrap weight (7) folded into Common (15 -> 22).
		loot = { Common = 22, Uncommon = 25, Rare = 26, Epic = 17, Legendary = 7, Mythic = 2.4, Anomaly = 0.1 },
		signals = 75, -- dive: stays dense
		-- West edge = Stage 4's east edge (x = 1700); centre = 1700 + 400/2.
		center = { 1900, 0 },
		-- UNIFORM LENGTH PASS: 400 x 200 (FOOTPRINT_X/Z), the shared footprint — see the header. Was
		-- 600 long, the second of the two big empty-walk stages; the biggest single
		-- shrink of the six.
		size = { FOOTPRINT_X, FOOTPRINT_Z },
		-- Light pink, on request (was a deep magenta, "A02268"). After Stage 4's dead
		-- brown the ground going soft candy-pink reads as a jump to a different KIND
		-- of place, not more of the same. The checkerboard floor is UNtinted
		-- (build/Scenery buildStageCheckerboard) so this is the colour the ground
		-- reads as; twoTone splits it just under white (R clips, G/B carry the two
		-- shades).
		color = "FFB6C1",
		material = "Glass",
		ooze = { bright = "FF3D9A", deep = "7A0F45", glow = "FF3D9A" },
		built = true,
	},
	{
		id = 6,
		name = "The Crater",
		-- Entrance unchanged at 100, clearing Stage 5's (softened) deepest of 88 with
		-- real room -- see that stage's note. deepRads is the steepest ramp of the
		-- six (2.5x) since nothing crosses OUT of the Crater, so its own far edge
		-- doesn't have to leave headroom for a stage 7 that doesn't exist -- the
		-- "never a farm, at any gear level, forever" stage gets to be the most
		-- extreme one, right where PLAN §16 already says it should be.
		baseRads = 100,
		deepRads = 250, -- 2.5x
		soilHardness = 6,
		ratedSuitTier = 6,
		-- The Crater is a heist, not a hike (PLAN §16) — but "short" has to mean
		-- short from its OWN on-site station, which still does not exist. This is the
		-- honest walk from the nearest cleansing station until that station is built,
		-- and it is now the far end of the east chain rather than an island, so the
		-- number went UP. Two minutes of walking to reach the endgame field is the
		-- strongest argument yet for building it its own station; until then this
		-- number is the warning, not the design. The uniform-length pass barely moved
		-- it: the Crater's entrance went x = 2130 -> x = 2100 (the whole chain still
		-- ends at almost exactly the same x, 2500 vs the old 2490), so this ~2060 is
		-- the old 2089 nudged down. Still not re-walked, same honesty caveat.
		stationDistance = 2060,
		fogColor = Color3.fromHex("FFD24A"),
		fogEnd = 400,
		-- NO SCRAP TIER, ON REQUEST -- see Stage 3's own comment on this above; same
		-- fold, this stage's old Scrap weight (2) folded into Common (6 -> 8).
		loot = { Common = 8, Uncommon = 15, Rare = 24, Epic = 26, Legendary = 18, Mythic = 8, Anomaly = 0.8 },
		signals = 75, -- heist, not a hike (PLAN §16): stays dense
		-- West edge = Stage 5's east edge (x = 2100); centre = 2100 + 400/2. The chain
		-- ends at x = 2500, within 10 studs of where it ended before.
		center = { 2300, 0 },
		-- UNIFORM LENGTH PASS: 400 x 200 (FOOTPRINT_X/Z), the shared footprint — see the header. Was
		-- 360 long.
		size = { FOOTPRINT_X, FOOTPRINT_Z },
		color = "5B1FA8",
		-- Glass, not Neon. The plate used to be Neon gold, which at Brightness 2.4
		-- with bloom is a 400x200 light source rather than ground — survivable while
		-- it was theoretical, and the exact failure the header's colour note warns
		-- about. The violet reads as violet on Glass and the POOLS do the glowing,
		-- which is the rule every other stage already follows.
		material = "Glass",
		ooze = { bright = "A855FF", deep = "3B1070", glow = "A855FF" },
		built = true,
	},
} :: { StageDef }

function Stages.get(id: number): StageDef
	local z = Stages.DEFS[id]
	assert(z, `unknown stage {id}`)
	return z
end

--- Ids the world generator should actually place.
function Stages.builtIds(): { number }
	local ids = {}
	for _, z in Stages.DEFS do
		if z.built then
			table.insert(ids, z.id)
		end
	end
	return ids
end

--- Ambient rads/sec for a given DEPTH into a stage, 0 (the entrance, west edge --
--- where you arrive from camp or the previous stage) to 1 (the deepest point, east
--- edge -- where the next stage begins). Linear between `baseRads` and `deepRads`.
---
--- StageService.ambientFor is the only live caller; Spec.luau and TuningReport.luau
--- call this directly with a fixed depthFrac (0 or 1) to test a specific point
--- rather than a moving player position.
function Stages.radsAt(stageId: number, depthFrac: number): number
	local stage = Stages.get(stageId)
	local t = math.clamp(depthFrac, 0, 1)
	return stage.baseRads + (stage.deepRads - stage.baseRads) * t
end

--- The plate's CFrame: centred in XZ, sunk so its TOP face lands on SURFACE_Y.
--- DigService buries items at the top face, so this is the walkable surface.
function Stages.plateCFrame(id: number): CFrame
	local z = Stages.get(id)
	return CFrame.new(z.center[1], Stages.SURFACE_Y - Stages.PLATE_THICKNESS / 2, z.center[2])
end

function Stages.plateSize(id: number): Vector3
	local z = Stages.get(id)
	return Vector3.new(z.size[1], Stages.PLATE_THICKNESS, z.size[2])
end

function Stages.area(id: number): number
	local z = Stages.get(id)
	return z.size[1] * z.size[2]
end

--- The coverage metric from the header: the expected number of signals lit up around
--- a player standing still.
function Stages.coverage(id: number, detectorRadius: number, signalsPerStage: number): number
	return signalsPerStage * math.pi * detectorRadius * detectorRadius / Stages.area(id)
end

--- Seconds of walking between one contact and the next, which is the number a player
--- actually feels. A reveal detector sweeps a corridor of width 2r, so this is the
--- area each signal has to itself divided by the area swept per second.
---
--- Deliberately ignores the fact that a real player walks in curves and re-covers
--- ground: it is a floor, not a prediction, and a stage that fails it on paper is
--- worse than it reads here rather than better.
function Stages.secondsBetweenContacts(id: number, detectorRadius: number, walkSpeed: number, signalsPerStage: number): number
	local perSignal = Stages.area(id) / signalsPerStage
	return perSignal / (2 * detectorRadius * walkSpeed)
end

--- Mean distance to the nearest buried signal, in studs.
function Stages.meanSignalGap(id: number, signalsPerStage: number): number
	return 0.5 * math.sqrt(Stages.area(id) / signalsPerStage)
end

--- Axis-aligned XZ bounds as (minX, minZ, maxX, maxZ). Used by overlap checks.
function Stages.bounds(id: number): (number, number, number, number)
	local z = Stages.get(id)
	local hx, hz = z.size[1] / 2, z.size[2] / 2
	return z.center[1] - hx, z.center[2] - hz, z.center[1] + hx, z.center[2] + hz
end

return Stages
