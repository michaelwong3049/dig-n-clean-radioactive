--!strict
-- Zones.lua — PLAN §4.
--
-- NOTE: `ratedSuitTier` is documentation, not enforcement. There is no gate anywhere
-- in this codebase that reads it to deny entry. Zones are open (PLAN §3.5); the only
-- thing that stops a player is the arithmetic in Shared/Radiation.lua.
--
-- ── SPATIAL FIELDS ──────────────────────────────────────────────────────────
-- `center` / `size` are the zone's footprint in world XZ. They are the source of
-- truth for build/ZoneFields.luau, which turns them into the plates that
-- DigService and ZoneService both read. Two independent lookups have to agree:
--
--     DigService.zonePart   Workspace.Zones:FindFirstChild("Zone" .. id)   -- by NAME
--     ZoneService.zoneAt    iterates children reading attribute ZoneId     -- by ATTRIBUTE
--
-- The generator writes both from the same loop index so they cannot drift apart.
--
-- ── HOW SIZE WAS CHOSEN, WHICH IS NOT ARBITRARY ─────────────────────────────
-- DigService keeps SIGNALS_PER_ZONE = 45 buried signals per zone. That is a GLOBAL
-- constant — it does not scale with area — so area is the only lever on how hard a
-- zone is to search. Define coverage:
--
--     c = 45 * pi * r^2 / area
--
-- Under the reveal detector c has a much more direct reading than it used to: it is
-- the EXPECTED NUMBER OF CONTACTS lit up around a player standing still. c = 0.11
-- means nine times out of ten you are looking at empty ground and have to walk.
--
-- THE METRIC THAT ACTUALLY DRIVES THE FEEL IS TIME, NOT AREA. A reveal detector
-- sweeps a corridor of width 2r as the player walks, so what a player experiences is
-- the gap between one glow going out and the next coming up:
--
--     seconds between contacts = (area / 45) / (2 * r * walkSpeed)
--
-- That is Zones.secondsBetweenContacts, and it is the number to tune against. PLAN
-- §2 wants a 20-40s loop at the low end; the walk is supposed to be a chunk of that,
-- not all of it.
--
--     zone   size       rated r   c      walk to next contact (16 studs/sec)
--     1      660x320    13 (T1)   0.23    5.6s
--     2      220x280    16 (T2)   1.18    1.3s
--     3      260x320    19 (T3)   1.23    1.5s
--     4      290x260    22 (T4)   1.81    1.2s
--     5      600x520    25 (T5)   0.57    4.3s
--     6      360x320    28 (T6)   1.92    1.4s
--
-- STALE, AND FLAGGED RATHER THAN GUESSED AT. The UNIFORM WIDTH PASS below put
-- every zone at 495 wide, so every "size" and everything the "size" column feeds
-- (c, walk-to-next-contact) here is now wrong: Zone 1 and Zone 5 got smaller and
-- got FASTER to search (confirmed — Spec's own "still has to walk >= 2s" check on
-- Zone 1 fails post-resize), Zones 2/3/4/6 got wider and got SLOWER. Recomputing
-- six rows properly means pulling each zone's rated-tier detector radius from
-- Config/Gear too, which is a real pass, not a five-minute edit — left undone on
-- purpose rather than half-done. Use `World.coverageReport()` for live numbers
-- until this table gets that pass.
--
-- ALL SIX ARE BUILT NOW, BUT ONLY ZONE 1 HAS EVER BEEN PLAYED, and the distinction
-- still matters. The other five were sized against a c ~= 0.26 target back when the
-- detector was a needle and c meant "fraction of ground where the arrow points at
-- something" — a reading that no longer exists. Their numbers are recomputed here so
-- the table is not lying, NOT endorsed: at c > 1 you are never without a target, so
-- 2, 3, 4 and 6 are farms rather than searches and they want re-sizing against the
-- time column. Doubling SIGNALS_PER_ZONE made that worse, not better.
--
-- Building them did not fix that and was not meant to. Every zone kept its exact
-- configured SIZE through the move — only centres changed — precisely so this table
-- stays true and the re-sizing decision stays open rather than being quietly
-- pre-empted by a build pass.
--
-- ── WHERE THEY ARE, AND WHY THEY MOVED ──────────────────────────────────────
-- There is no terrain in this world: off the built parts is void, so a zone that
-- touches nothing walkable is a zone nobody can reach. Four of the five needed
-- moving for that reason or because they overlapped Zone 1.
--
--     camp ═══> [ 1 Ash Flats ] [ 2 Suburbs ] [ 3 Fallout ] [ 4 Exclusion ] [ 5 Reactor ] [ 6 Crater ]
--       x            100-595      595-1090     1090-1585    1585-2080       2080-2575     2575-3070
--
-- ONE STRAIGHT CHAIN NOW, TIER-ORDERED, NOT A SIDE SPUR. Zone 4 used to sit north of
-- Zone 1, touching only its west edge — close enough to camp that a fresh player
-- crossed into it by accident, which was the point: PLAN §3.5's "the Dive" wants the
-- lethal field to be somewhere you are standing anyway, not an expedition. Pulled out
-- of the camp's doorstep and slotted between Zone 3 and Zone 5 instead, so walking
-- straight into it now means passing through Zones 1-3 first — a deliberate 1-2-3-4-
-- 5-6 tier progression rather than a spur. That trades away the accidental-dive
-- framing PLAN §3.5 describes; see the note on the Zone 4 def below.
--
-- ALL SIX NOW SHARE ONE WIDTH, 495 STUDS — 0.75x Zone 1's own former width, applied
-- uniformly rather than each zone keeping its own. The old spread (220 to 660) read
-- as "overwhelmingly large and uneven" walking the chain; 495 is not a shrink for
-- every zone — only Zone 1 (was 660) and Zone 5 (was 600) actually got smaller,
-- Zones 2, 3, 4 and 6 (220/260/290/360) all grew to meet it — but it does mean every
-- zone now takes the same distance to cross, which is the actual thing being fixed.
-- Depth (size[2], the north-south dimension) is untouched on all six; this is a
-- width-only pass.
--
-- The chain shares edges exactly, the same way the plaza's east edge already lands
-- on Zone 1's west edge: `rectsOverlap` fails on `<`, not `<=`, so a shared edge is
-- touching rather than overlapping and World.verify() accepts it. Every centre below
-- is just "previous zone's east edge + 247.5" now that width is uniform.
--
-- ── THE COLOUR TURNS AT ZONE 4 ──────────────────────────────────────────────
-- Zones 1-3 are the known world and stay green. From Zone 4 the ground goes plum,
-- then hot pink, then violet — a different KIND of place rather than more of the same
-- one, which is the thing a player reads before they read any number.
--
-- The muted-plate / bright-Neon rule below is not suspended for them, it is the
-- reason they work: the plate is a deep plum or violet and the POOLS are the bright
-- magenta. Keep the dominant channel dominant when tuning these. The colour note
-- explains why a yellow-green plate blooms to cream; the same arithmetic turns a
-- balanced pink to white and a pale violet to lavender-grey. Pink stays red-dominant,
-- violet stays blue-dominant.
--
-- The header used to carry a hard ceiling of area <= 785 * r^2, i.e. c >= 0.18. Zone
-- 1 has been over that ceiling since the field was grown to 660x320 — it was already
-- at c = 0.096 under the old radius — so the rule described a zone layout that no
-- longer exists and is left here as history rather than as a check. Use the time
-- column.
--
-- COLOUR NOTE: the plate is the SLUDGE and it is deliberately deep and muted. The
-- bright colour belongs to the pools and spills in build/Scenery, which are Neon —
-- each zone's own, from its `ooze` field, since the field stopped being green at Zone
-- 4. Making the plate pale too was the first attempt and it read as a golf course
-- from ground level: with no tonal gap between ground and pool, nothing glowed and
-- nothing looked toxic. Contrast is what sells "radioactive", not brightness.
--
-- Zone 4 is the deliberate inversion. It is a dive, not a farm (PLAN §3.5): you get
-- roughly 35 seconds in it one tier under. A field where you nearly always have a
-- ping is exactly right for "grab one thing and run", and it means that window is
-- spent hauling rather than searching. Without the inversion the Zone 4 dive would
-- fail its own validation test (PLAN §15, question 2) for the wrong reason.
--
-- `stationDistance` is measured, not aspirational — see the note on it below.
--
-- ── HOW THE LOOT WEIGHTS WERE RE-DERIVED, WHICH IS ALSO NOT ARBITRARY ────────
-- These are RELATIVE weights, normalised at roll time, so only their ratios matter.
--
-- Zones 1-3 were re-weighted when SIGNALS_PER_ZONE doubled to 90. The reason is one
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
-- Net effect in zone 1: ~2x the pulls, ~2.9x the Commons, ~1.7x the Scrap, and Rare
-- or better unchanged. Shared/Util/Spec pins that last property — it asserts the
-- field holds ~4.9 Rare-or-better signals across the three stages, which is what it
-- held before the change.
--
-- ZONES 4-6 WERE DELIBERATELY NOT RE-WEIGHTED, AND THAT DEBT IS NOW LIVE. Their
-- identity is "everything here is good" (PLAN §4 — the Crater is 18% Legendary on
-- purpose), and halving their top end to hold a wall-clock rate would be a redesign of
-- the zones rather than a rebalance of this one. The old note said to decide it when
-- they are built and playable. They are built: Zone 4 is stocked and diggable TODAY at
-- double its intended rare rate. Zones 5 and 6 are not stocked yet, so their share of
-- the debt is still deferred. See TODO.md.
--
-- CAVEAT ON ALL OF THE ABOVE: DigService.rollItemId steps DOWN when Config/Items does
-- not stock the rolled rarity in that zone, so the delivered distribution is always
-- at least as common as this table says, never rarer. Zone 1 stocks no Mythic or
-- Anomaly, so its top two rows are aspirational.
--
-- AND ZONES 5 AND 6 STOCK NOTHING AT ALL. rollItemId finds no pool at any rarity,
-- warns once and returns nil, so no signals spawn there. Both fields are real, both
-- irradiate, both can be walked and neither has anything buried in it. That is a
-- content gap held open on purpose — building the world and writing the catalogue are
-- separate jobs — and it is the one thing to fix before either zone is playable.

export type ZoneDef = {
	id: number,
	name: string,
	baseRads: number,
	soilHardness: number,
	ratedSuitTier: number,
	stationDistance: number,
	fogColor: Color3,
	fogEnd: number,
	loot: { [string]: number }, -- rarity name -> weight (normalised at roll time)

	-- Spatial. See the header.
	center: { number }, -- { x, z } world space
	size: { number }, -- { x, z } footprint in studs
	color: string, -- hex; the ooze colour of this zone's surface
	material: string, -- Enum.Material name

	-- The zone's Neon channel: the wading surface, the pools, their rims and their
	-- lights. Per-zone since the harder zones stopped being green — build/Scenery
	-- used to paint every field from three globals in Kit.C, which would have left
	-- The Crater's violet ground under acid-green puddles.
	ooze: { bright: string, deep: string, glow: string },

	built: boolean, -- false => the generator skips it and verify() ignores it
}

export type StageDef = {
	id: number,
	name: string,
	minX: number,
	maxX: number,
	unlockTier: number,
	loot: { [string]: number },
	itemZoneId: number,
	color: string,
}

local Zones = {}

--- The top face of every zone plate. One stud and a half BELOW the plaza, so you
--- physically step down into the sludge and the boundary reads from a distance
--- without any extra geometry. A humanoid clears 1.5 studs without a ramp.
Zones.SURFACE_Y = -1.5

--- Plate thickness. DERIVED, not chosen: DigService buries at up to
--- DEPTH_BASE + 7*DEPTH_PER_RARITY + DEPTH_JITTER = 13.2 studs, and the haul part
--- is drawn at signal.position - depth while it rises. At 16 the deepest haul sits
--- 2.8 studs above the plate's underside, so it is never visible poking out from
--- below. Tuning.DIG_DEPTH_* and this constant are checked against each other in
--- Shared/Util/Spec.
Zones.PLATE_THICKNESS = 16

Zones.DEFS = {
	{
		id = 1,
		name = "Ash Flats",
		baseRads = 0.5,
		soilHardness = 1,
		ratedSuitTier = 1,
		-- Was 230 before the hub-to-field connector shrank by 40 studs (Hub.luau's
		-- CampToRadiationRoad) so the plaza and the field read as one connected
		-- complex rather than two places joined by a long empty road. Re-measured
		-- by that same 40, not re-walked stud-for-stud — close enough to stay
		-- honest per the header's "measured, not aspirational" rule without
		-- re-deriving the whole number from scratch. Still holds after the width
		-- pass below: the west edge (x = 100) never moved, only the east one did.
		stationDistance = 190,
		fogColor = Color3.fromHex("CFF3FF"),
		fogEnd = 900,
		loot = { Scrap = 48, Common = 41, Uncommon = 8.4, Rare = 2, Epic = 0.4, Legendary = 0.075, Mythic = 0.02, Anomaly = 0.001 },
		-- UNIFORM WIDTH PASS: every zone is now 495 studs wide (0.75x Zone 1's own
		-- former 660) — see "ALL SIX NOW SHARE ONE WIDTH" in the header. Centre
		-- moves to keep the west edge at x = 100, flush on the plaza as always.
		center = { 347.5, 0 },
		size = { 495, 320 },
		-- Matches STAGES[3]'s colour below, not STAGES[1]'s: paintBands covers this
		-- plate edge-to-edge in stage bands, so this base colour is never actually
		-- seen — it is only the fallback under a seam gap, and the fallback should
		-- match the zone's OWN east/dead end, not its green west end, since that is
		-- what borders Zone 2 across the boundary blend. See "LIFE FADING INTO A
		-- DEAD WASTELAND" below for the whole Zone 1-3 palette.
		color = "C2A171",
		material = "Sand",
		-- Muted on purpose — see the note below. Nowhere near today's old 6BEE2E,
		-- and nowhere near Zones 4-6's neon-pink/violet territory either.
		ooze = { bright = "7CBF52", deep = "35501F", glow = "5C9A3C" },
		built = true,
	},
	{
		id = 2,
		name = "The Suburbs",
		baseRads = 2,
		soilHardness = 2,
		ratedSuitTier = 2,
		-- STALE after the width pass below (was measured against the old, narrower
		-- Zone 2) — flag for re-measuring in Studio, same honesty rule as Zone 4/6's
		-- placeholders rather than guessing a new number.
		stationDistance = 719,
		-- Was a pale yellow-green — clashed with the dun/tan ground once that
		-- stopped being green. Dusty tan haze instead.
		fogColor = Color3.fromHex("E8D9B0"),
		fogEnd = 800,
		loot = { Scrap = 43, Common = 39, Uncommon = 12.6, Rare = 3.5, Epic = 1, Legendary = 0.25, Mythic = 0.05, Anomaly = 0.002 },
		-- MOVED EAST, OUT OF ZONE 1. This used to sit at x = 470, which put it
		-- ENTIRELY INSIDE Zone 1 (x 100-760) — fine while it was never built, fatal
		-- the moment it was, because overlapping zones resolve smallest-area-wins and
		-- "which zone am I standing in" stops having an answer. Its west edge is now
		-- exactly Zone 1's east edge.
		--
		-- UNIFORM WIDTH PASS: 220 -> 495, same rule as every other zone — this one
		-- actually GREW (it was the narrowest zone by far). The header's coverage
		-- and seconds-between-contacts figures for this zone are now stale too;
		-- flagged in the header rather than recomputed here.
		center = { 842.5, 0 },
		size = { 495, 280 },
		-- Dun/tan, not green — see "LIFE FADING INTO A DEAD WASTELAND" below.
		color = "B8935F",
		material = "Sand",
		-- Corrected after a live look: the first pass (8FB358) was not green-DOMINANT
		-- enough — R was 80% of G, and Neon + bloom pushed it to cream, the exact
		-- failure this file's own header warns about ("a yellow-green like #B6FF6E
		-- comes out of Neon + bloom as cream and stops reading as toxic at all").
		-- Same family as Zone 1's ooze, just a touch deeper — R/G ratio close to
		-- Zone 1's ~0.65 instead of drifting toward yellow.
		ooze = { bright = "6FA84A", deep = "30481C", glow = "519438" },
		built = true,
	},
	{
		id = 3,
		name = "Fallout Fields",
		baseRads = 6,
		soilHardness = 3,
		ratedSuitTier = 3,
		-- STALE, same as Zone 2's — see that zone's note.
		stationDistance = 939,
		-- Was a bright yellow-green — same clash as Zone 2's, deeper. Warmer dusty
		-- khaki haze for the gradient's endpoint.
		fogColor = Color3.fromHex("D4B896"),
		fogEnd = 700,
		loot = { Scrap = 34, Common = 40, Uncommon = 16.8, Rare = 6, Epic = 2.25, Legendary = 0.6, Mythic = 0.14, Anomaly = 0.005 },
		-- Also moved east — its old centre at x = 760 was Zone 1's east EDGE, so half
		-- of it lay inside Zone 1. Butted onto Zone 2 instead.
		--
		-- UNIFORM WIDTH PASS: 260 -> 495, same rule as every other zone.
		center = { 1337.5, 0 },
		size = { 495, 320 },
		-- Deeper desert khaki-brown — the endpoint of the Zone 1-3 gradient. Slate
		-- read as dark grey rock and broke continuity with the sand family this
		-- whole stretch depends on, so material moved to Sand too.
		color = "A67C4E",
		material = "Sand",
		-- Same green-dominance fix as Zone 2's — see that zone's comment. Slightly
		-- darker again, the gradient's endpoint, but the same hue family throughout.
		ooze = { bright = "649C42", deep = "2C4018", glow = "488432" },
		built = true,
	},
	{
		id = 4,
		name = "The Exclusion Belt",
		baseRads = 15,
		soilHardness = 4,
		ratedSuitTier = 4,
		-- Deliberately SHORT. PLAN §15's second validation question is "do players
		-- cross into Zone 4 unrated, on purpose, more than once?" — that used to be
		-- answerable because the field sat right off the camp's doorstep. MOVED INTO
		-- THE EAST CHAIN, between Zone 3 and Zone 5, so the map reads as one straight
		-- tier-ordered progression instead of a side spur (see the header). That is a
		-- real trade: the accidental/impulsive dive PLAN §3.5 describes now requires
		-- walking past three zones first, so it reads more like "the next zone" than
		-- "a lethal thing twenty feet from home." The short-and-brutal tuning (15
		-- rads ambient) is unchanged and still makes it a real risk to under-tiered
		-- players passing through the chain, though the plate itself grew with the
		-- width pass below (was 290x260).
		--
		-- stationDistance below is STALE (was an interpolation for the old, narrower
		-- plate) — flag it for re-measuring in Studio next time someone is touching
		-- this file, same as Zone 6's honest placeholder.
		stationDistance = 1200,
		fogColor = Color3.fromHex("6FE04A"),
		fogEnd = 600,
		loot = { Scrap = 15, Common = 24, Uncommon = 28, Rare = 20, Epic = 9, Legendary = 3, Mythic = 0.8, Anomaly = 0.03 },
		-- Slotted flush between Zone 3's east edge and Zone 5's west edge — exactly
		-- its own width, zero gap either side, same as before. z centring (0,
		-- matching the rest of the chain) untouched.
		--
		-- UNIFORM WIDTH PASS: 290 -> 495, same rule as every other zone.
		center = { 1832.5, 0 },
		size = { 495, 260 },
		-- WHERE THE GREEN STOPS. See "THE COLOUR TURNS" in the header.
		color = "73246B",
		material = "Slate",
		ooze = { bright = "FF2FA8", deep = "6B0A47", glow = "FF2FA8" },
		built = true,
	},
	{
		id = 5,
		name = "Reactor Grounds",
		baseRads = 40,
		soilHardness = 5,
		ratedSuitTier = 5,
		stationDistance = 1489, -- STALE again after the width pass below; not re-walked
		fogColor = Color3.fromHex("C8E85A"),
		fogEnd = 500,
		loot = { Scrap = 7, Common = 15, Uncommon = 25, Rare = 26, Epic = 17, Legendary = 7, Mythic = 2.4, Anomaly = 0.1 },
		-- Was an island at (-700, -620) with several hundred studs of open void
		-- between it and the nearest floor. Moved onto the east chain, then shifted
		-- +290 when Zone 4 was inserted ahead of it — now butted against Zone 4
		-- instead of Zone 3 directly.
		--
		-- UNIFORM WIDTH PASS: 600 -> 495, same rule as every other zone — this is
		-- one of only two zones (with Zone 1) that actually got smaller.
		center = { 2327.5, 0 },
		size = { 495, 520 },
		color = "A02268",
		material = "Glass",
		ooze = { bright = "FF3D9A", deep = "7A0F45", glow = "FF3D9A" },
		-- NOTHING IS BURIED HERE YET. Config/Items stocks zones 1-4 only, so
		-- DigService.rollItemId finds no pool at any rarity, warns once and spawns no
		-- signals. The field is real, irradiates correctly and can be walked; it is
		-- empty until items are written for it. Deliberate, and flagged in TODO.md.
		built = true,
	},
	{
		id = 6,
		name = "The Crater",
		baseRads = 100,
		soilHardness = 6,
		ratedSuitTier = 6,
		-- The Crater is a heist, not a hike (PLAN §16) — but "short" has to mean
		-- short from its OWN on-site station, which still does not exist. This is the
		-- honest walk from the nearest cleansing station until that station is built,
		-- and it is now the far end of the east chain rather than an island, so the
		-- number went UP. Two minutes of walking to reach the endgame field is the
		-- strongest argument yet for building it its own station; until then this
		-- number is the warning, not the design. It went up AGAIN when Zone 4 was
		-- inserted earlier in the chain, and is STALE YET AGAIN after the width pass
		-- below — still not re-walked, same honesty caveat as before.
		stationDistance = 2089,
		fogColor = Color3.fromHex("FFD24A"),
		fogEnd = 400,
		loot = { Scrap = 2, Common = 6, Uncommon = 15, Rare = 24, Epic = 26, Legendary = 18, Mythic = 8, Anomaly = 0.8 },
		-- UNIFORM WIDTH PASS: 360 -> 495, same rule as every other zone.
		center = { 2822.5, 0 },
		size = { 495, 320 },
		color = "5B1FA8",
		-- Glass, not Neon. The plate used to be Neon gold, which at Brightness 2.4
		-- with bloom is a 360x320 light source rather than ground — survivable while
		-- it was theoretical, and the exact failure the header's colour note warns
		-- about. The violet reads as violet on Glass and the POOLS do the glowing,
		-- which is the rule every other zone already follows.
		material = "Glass",
		ooze = { bright = "A855FF", deep = "3B1070", glow = "A855FF" },
		-- Unstocked, exactly as Zone 5 — see the note there.
		built = true,
	},
} :: { ZoneDef }

-- One radiation field, three stages. Stage bounds are local X offsets from the
-- field centre, so the field can move without the stage boundaries drifting away
-- from the loot they divide. The later stages reuse the existing zone item pools
-- until the catalogue is split into an explicitly staged content model.
--
-- Bounds below are scaled by exactly 0.75, same as Zone 1's own width (660 ->
-- 495) in the UNIFORM WIDTH PASS above — clean scaling since 495 IS 660*0.75, so
-- each stage keeps the same proportional third of the (now smaller) field.
--
-- `color` is what actually separates them on the ground. There used to be a concrete
-- barrier at each boundary; build/Scenery paints the plate in these three colours
-- with a blended seam instead, because a wall standing in open ground read as
-- unnatural and gated nothing.
--
-- THESE HAVE TO BE FAR APART, AND THEY DID NOT USED TO BE. The first set was
-- 6F9636 / 538C28 / 3E7A1C — three shades of one green. LIFE FADING INTO A DEAD
-- WASTELAND (see PLAN.md §14's revision note) replaced that with a genuine family
-- change instead of three shades of one hue: vivid grass green -> khaki-olive dying
-- middle -> pale dead sand, matching Zone 2/3's own now-desaturated tan/khaki-brown
-- ground so Zone 1's own internal gradient hands off into the zone-to-zone one
-- seamlessly instead of two unrelated systems meeting at a coincidence.
--
-- The reading is also the fiction, same names, new meaning: Outer Ash is the
-- untouched edge right off camp's doorstep, barely ashen at all yet; Hot Wreckage is
-- where it is visibly dying; Deep Fallout is where the ecosystem lost. Keep them
-- distinguishable at a glance — the loot table changes at the seam, so a player has
-- to be able to see which one they are on.
Zones.STAGES = {
	{
		id = 1,
		name = "Outer Ash",
		minX = -247.5,
		maxX = -82.5,
		unlockTier = 1,
		loot = Zones.DEFS[1].loot,
		itemZoneId = 1,
		color = "5C9A34",
	},
	{
		id = 2,
		name = "Hot Wreckage",
		minX = -82.5,
		maxX = 75,
		unlockTier = 2,
		loot = Zones.DEFS[2].loot,
		itemZoneId = 2,
		color = "8E7C48",
	},
	{
		id = 3,
		name = "Deep Fallout",
		minX = 75,
		maxX = 247.5,
		unlockTier = 3,
		loot = Zones.DEFS[3].loot,
		itemZoneId = 3,
		color = "C2A171",
	},
}

function Zones.get(id: number): ZoneDef
	local z = Zones.DEFS[id]
	assert(z, `unknown zone {id}`)
	return z
end

--- Ids the world generator should actually place.
function Zones.builtIds(): { number }
	local ids = {}
	for _, z in Zones.DEFS do
		if z.built then
			table.insert(ids, z.id)
		end
	end
	return ids
end

--- THE ONE ZONE THAT IS SUBDIVIDED INTO STAGES.
---
--- Zone 1 is the graded starter field: three loot tables across one plate, so a new
--- player meets an escalating field before they meet a second zone. Every other zone
--- is a single place with a single table — that is what makes it a zone rather than a
--- stage.
---
--- THIS CONSTANT EXISTS BECAUSE THE SUBDIVISION WAS ACCIDENTALLY GLOBAL. DigService
--- resolved EVERY signal's loot through `stageAt`, which was invisibly correct while
--- Zone 1 was the only field in the world and quietly wrong the moment it was not:
--- stage bounds are LOCAL X offsets, so each new zone got sliced into stages by its
--- own width and handed out Zone 1, 2 and 3's items. The Crater's 18%-Legendary table
--- was never consulted by anything. Ask `lootAt`, not `stageAt`.
Zones.STAGED_ZONE = 1

function Zones.stageAt(zoneId: number, worldX: number): StageDef
	local zone = Zones.get(zoneId)
	local localX = worldX - zone.center[1]
	for _, stage in Zones.STAGES do
		if localX >= stage.minX and localX <= stage.maxX then
			return stage
		end
	end
	return Zones.STAGES[#Zones.STAGES]
end

--- What a signal at `worldX` in this zone should roll against: its rarity weights,
--- and the id whose item pool the rolled rarity is drawn from.
---
--- The two are separate because they diverge in exactly one place. Zone 1's stages
--- carry Zone 2 and Zone 3's loot tables and item pools — that is the whole point of
--- a graded field, and it is why `itemZoneId` exists on StageDef. Everywhere else the
--- zone answers for both.
function Zones.lootAt(zoneId: number, worldX: number): ({ [string]: number }, number)
	if zoneId == Zones.STAGED_ZONE then
		local stage = Zones.stageAt(zoneId, worldX)
		return stage.loot, stage.itemZoneId
	end
	local zone = Zones.get(zoneId)
	return zone.loot, zoneId
end

--- The plate's CFrame: centred in XZ, sunk so its TOP face lands on SURFACE_Y.
--- DigService buries items at the top face, so this is the walkable surface.
function Zones.plateCFrame(id: number): CFrame
	local z = Zones.get(id)
	return CFrame.new(z.center[1], Zones.SURFACE_Y - Zones.PLATE_THICKNESS / 2, z.center[2])
end

function Zones.plateSize(id: number): Vector3
	local z = Zones.get(id)
	return Vector3.new(z.size[1], Zones.PLATE_THICKNESS, z.size[2])
end

function Zones.area(id: number): number
	local z = Zones.get(id)
	return z.size[1] * z.size[2]
end

--- The coverage metric from the header: the expected number of signals lit up around
--- a player standing still.
function Zones.coverage(id: number, detectorRadius: number, signalsPerZone: number): number
	return signalsPerZone * math.pi * detectorRadius * detectorRadius / Zones.area(id)
end

--- Seconds of walking between one contact and the next, which is the number a player
--- actually feels. A reveal detector sweeps a corridor of width 2r, so this is the
--- area each signal has to itself divided by the area swept per second.
---
--- Deliberately ignores the fact that a real player walks in curves and re-covers
--- ground: it is a floor, not a prediction, and a zone that fails it on paper is
--- worse than it reads here rather than better.
function Zones.secondsBetweenContacts(id: number, detectorRadius: number, walkSpeed: number, signalsPerZone: number): number
	local perSignal = Zones.area(id) / signalsPerZone
	return perSignal / (2 * detectorRadius * walkSpeed)
end

--- Mean distance to the nearest buried signal, in studs.
function Zones.meanSignalGap(id: number, signalsPerZone: number): number
	return 0.5 * math.sqrt(Zones.area(id) / signalsPerZone)
end

--- Axis-aligned XZ bounds as (minX, minZ, maxX, maxZ). Used by overlap checks.
function Zones.bounds(id: number): (number, number, number, number)
	local z = Zones.get(id)
	local hx, hz = z.size[1] / 2, z.size[2] / 2
	return z.center[1] - hx, z.center[2] - hz, z.center[1] + hx, z.center[2] + hz
end

return Zones
