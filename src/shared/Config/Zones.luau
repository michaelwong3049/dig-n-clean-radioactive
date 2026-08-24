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
--     camp ═══> [ 1 Ash Flats ] [ 2 Suburbs ] [ 3 Fallout ] [ 5 Reactor ] [ 6 Crater ]
--       ║          x 100-760      760-980      980-1240     1240-1840     1840-2200
--       ╚═> [ 4 Exclusion Belt ]   (north, z 152-412 — the dive, deliberately close)
--
-- The east chain shares edges exactly, the same way the plaza's east edge already
-- lands on Zone 1's west edge: `rectsOverlap` fails on `<`, not `<=`, so a shared
-- edge is touching rather than overlapping and World.verify() accepts it. Walk east
-- and it gets worse; that is the whole layout.
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
		-- re-deriving the whole number from scratch.
		stationDistance = 190,
		fogColor = Color3.fromHex("CFF3FF"),
		fogEnd = 900,
		loot = { Scrap = 48, Common = 41, Uncommon = 8.4, Rare = 2, Epic = 0.4, Legendary = 0.075, Mythic = 0.02, Anomaly = 0.001 },
		center = { 430, 0 },
		size = { 660, 320 },
		color = "6F9636",
		material = "Sand",
		ooze = { bright = "6BEE2E", deep = "2A6B10", glow = "4FD11A" },
		built = true,
	},
	{
		id = 2,
		name = "The Suburbs",
		baseRads = 2,
		soilHardness = 2,
		ratedSuitTier = 2,
		stationDistance = 719,
		fogColor = Color3.fromHex("D8F0B8"),
		fogEnd = 800,
		loot = { Scrap = 43, Common = 39, Uncommon = 12.6, Rare = 3.5, Epic = 1, Legendary = 0.25, Mythic = 0.05, Anomaly = 0.002 },
		-- MOVED EAST, OUT OF ZONE 1. This used to sit at x = 470, which put it
		-- ENTIRELY INSIDE Zone 1 (x 100-760) — fine while it was never built, fatal
		-- the moment it was, because overlapping zones resolve smallest-area-wins and
		-- "which zone am I standing in" stops having an answer. Its west edge is now
		-- exactly Zone 1's east edge. Size is untouched, so the header's coverage and
		-- seconds-between-contacts figures for this zone still hold.
		center = { 870, 0 },
		size = { 220, 280 },
		color = "538C28",
		material = "Sand",
		ooze = { bright = "6BEE2E", deep = "2A6B10", glow = "4FD11A" },
		built = true,
	},
	{
		id = 3,
		name = "Fallout Fields",
		baseRads = 6,
		soilHardness = 3,
		ratedSuitTier = 3,
		stationDistance = 939,
		fogColor = Color3.fromHex("A8F06A"),
		fogEnd = 700,
		loot = { Scrap = 34, Common = 40, Uncommon = 16.8, Rare = 6, Epic = 2.25, Legendary = 0.6, Mythic = 0.14, Anomaly = 0.005 },
		-- Also moved east — its old centre at x = 760 was Zone 1's east EDGE, so half
		-- of it lay inside Zone 1. Butted onto Zone 2 instead. Size untouched.
		center = { 1110, 0 },
		size = { 260, 320 },
		color = "3E7A1C",
		material = "Slate",
		ooze = { bright = "6BEE2E", deep = "2A6B10", glow = "4FD11A" },
		built = true,
	},
	{
		id = 4,
		name = "The Exclusion Belt",
		baseRads = 15,
		soilHardness = 4,
		ratedSuitTier = 4,
		-- Deliberately SHORT, and it got shorter. PLAN §15's second validation
		-- question is "do players cross into Zone 4 unrated, on purpose, more than
		-- once?", and it is only answerable if the lethal field is somewhere you are
		-- standing anyway rather than somewhere you make an expedition to.
		--
		-- The old description of where that was — behind the camp's back wall, behind
		-- a fence with a hole in it, in plain sight of the trader's counter — is three
		-- things that no longer exist. What puts it under your nose now is the plot
		-- ring: this field's south edge IS the north edge of the apron between the two
		-- north bases, so you step off your own doorstep into 15 rads. The cleansing
		-- station on that pad is 6 studs behind you, which is the point.
		stationDistance = 6,
		fogColor = Color3.fromHex("6FE04A"),
		fogEnd = 600,
		loot = { Scrap = 15, Common = 24, Uncommon = 28, Rare = 20, Epic = 9, Legendary = 3, Mythic = 0.8, Anomaly = 0.03 },
		-- Moved south and west to touch that apron edge (z = 152) and to stop dead on
		-- Zone 1's west edge (x = 100) rather than crossing it. Size untouched.
		center = { -45, 282 },
		size = { 290, 260 },
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
		stationDistance = 1199, -- measured from the nearest cleansing station
		fogColor = Color3.fromHex("C8E85A"),
		fogEnd = 500,
		loot = { Scrap = 7, Common = 15, Uncommon = 25, Rare = 26, Epic = 17, Legendary = 7, Mythic = 2.4, Anomaly = 0.1 },
		-- Was an island at (-700, -620) with several hundred studs of open void
		-- between it and the nearest floor. Moved onto the east chain, butted against
		-- Zone 3. Size untouched.
		center = { 1540, 0 },
		size = { 600, 520 },
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
		-- number is the warning, not the design.
		stationDistance = 1799,
		fogColor = Color3.fromHex("FFD24A"),
		fogEnd = 400,
		loot = { Scrap = 2, Common = 6, Uncommon = 15, Rare = 24, Epic = 26, Legendary = 18, Mythic = 8, Anomaly = 0.8 },
		center = { 2020, 0 },
		size = { 360, 320 },
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
-- `color` is what actually separates them on the ground. There used to be a concrete
-- barrier at each boundary; build/Scenery paints the plate in these three colours
-- with a blended seam instead, because a wall standing in open ground read as
-- unnatural and gated nothing.
--
-- THESE HAVE TO BE FAR APART, AND THEY DID NOT USED TO BE. The first set was
-- 6F9636 / 538C28 / 3E7A1C — three shades of one green, which was fine while the
-- colour only ever tinted a gate post, and completely invisible the moment it became
-- the ground: the field renders under a bright Neon ooze layer whose glow swallowed
-- the difference, and the first attempt at this came out one flat green. They now run
-- ashen olive -> green -> dark cool green, moving in LIGHTNESS and HUE together, which
-- is what survives being seen through that layer.
--
-- The reading is also the fiction: Outer Ash is dusty and barely contaminated, Deep
-- Fallout is dark and wet with it. Keep them distinguishable at a glance — the loot
-- table changes at the seam, so a player has to be able to see which one they are on.
Zones.STAGES = {
	{
		id = 1,
		name = "Outer Ash",
		minX = -330,
		maxX = -110,
		unlockTier = 1,
		loot = Zones.DEFS[1].loot,
		itemZoneId = 1,
		color = "9DA857",
	},
	{
		id = 2,
		name = "Hot Wreckage",
		minX = -110,
		maxX = 100,
		unlockTier = 2,
		loot = Zones.DEFS[2].loot,
		itemZoneId = 2,
		color = "5F8C2E",
	},
	{
		id = 3,
		name = "Deep Fallout",
		minX = 100,
		maxX = 330,
		unlockTier = 3,
		loot = Zones.DEFS[3].loot,
		itemZoneId = 3,
		color = "2B6135",
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
