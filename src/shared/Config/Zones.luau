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
--     1      660x320    13 (T1)   0.11   11.3s
--     2      220x280    16 (T2)   0.59    2.7s
--     3      260x320    19 (T3)   0.61    2.7s
--     4      290x260    22 (T4)   0.91    2.4s
--     5      600x520    25 (T5)   0.28    7.8s
--     6      360x320    28 (T6)   0.96    2.9s
--
-- ONLY ZONE 1 IS BUILT, and it is the only line above that has ever been played. The
-- other five were sized against a c ~= 0.26 target back when the detector was a
-- needle and c meant "fraction of ground where the arrow points at something" — a
-- reading that no longer exists. Their numbers are recomputed here so the table is
-- not lying, NOT endorsed: every one of them is a farm where you are never without a
-- target, and they want re-sizing against the time column before they are built.
--
-- The header used to carry a hard ceiling of area <= 785 * r^2, i.e. c >= 0.18. Zone
-- 1 has been over that ceiling since the field was grown to 660x320 — it was already
-- at c = 0.096 under the old radius — so the rule described a zone layout that no
-- longer exists and is left here as history rather than as a check. Use the time
-- column.
--
-- COLOUR NOTE: the plate is the SLUDGE and it is deliberately a deep, muted green.
-- The bright acid green belongs to the pools and spills in build/Scenery, which are
-- Neon. Making the plate pale too was the first attempt and it read as a golf course
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
		loot = { Scrap = 55, Common = 28, Uncommon = 12, Rare = 4, Epic = 0.8, Legendary = 0.15, Mythic = 0.04, Anomaly = 0.002 },
		center = { 430, 0 },
		size = { 660, 320 },
		color = "6F9636",
		material = "Sand",
		built = true,
	},
	{
		id = 2,
		name = "The Suburbs",
		baseRads = 2,
		soilHardness = 2,
		ratedSuitTier = 2,
		stationDistance = 470,
		fogColor = Color3.fromHex("D8F0B8"),
		fogEnd = 800,
		loot = { Scrap = 42, Common = 30, Uncommon = 18, Rare = 7, Epic = 2, Legendary = 0.5, Mythic = 0.1, Anomaly = 0.004 },
		center = { 470, 0 },
		size = { 220, 280 },
		color = "538C28",
		material = "Sand",
		built = false, -- loot pool retained for radiation stage 2
	},
	{
		id = 3,
		name = "Fallout Fields",
		baseRads = 6,
		soilHardness = 3,
		ratedSuitTier = 3,
		stationDistance = 760,
		fogColor = Color3.fromHex("A8F06A"),
		fogEnd = 700,
		loot = { Scrap = 28, Common = 30, Uncommon = 24, Rare = 12, Epic = 4.5, Legendary = 1.2, Mythic = 0.28, Anomaly = 0.01 },
		center = { 760, 0 },
		size = { 260, 320 },
		color = "3E7A1C",
		material = "Slate",
		built = false, -- loot pool retained for radiation stage 3
	},
	{
		id = 4,
		name = "The Exclusion Belt",
		baseRads = 15,
		soilHardness = 4,
		ratedSuitTier = 4,
		-- Deliberately SHORT. Zone 4 sits directly behind the camp's back wall,
		-- behind a fence with a hole in it, in plain sight of the trader's counter.
		-- PLAN §15's second validation question is "do players cross into Zone 4
		-- unrated, on purpose, more than once?" — putting the lethal field 200
		-- studs from the decon basin is what makes that question answerable.
		stationDistance = 209,
		fogColor = Color3.fromHex("6FE04A"),
		fogEnd = 600,
		loot = { Scrap = 15, Common = 24, Uncommon = 28, Rare = 20, Epic = 9, Legendary = 3, Mythic = 0.8, Anomaly = 0.03 },
		center = { 0, 310 },
		size = { 290, 260 },
		color = "2F6B14",
		material = "Slate",
		built = false, -- reserved for a future fourth stage
	},
	{
		id = 5,
		name = "Reactor Grounds",
		baseRads = 40,
		soilHardness = 5,
		ratedSuitTier = 5,
		stationDistance = 995, -- measured from the decon basin, not aspirational
		fogColor = Color3.fromHex("C8E85A"),
		fogEnd = 500,
		loot = { Scrap = 7, Common = 15, Uncommon = 25, Rare = 26, Epic = 17, Legendary = 7, Mythic = 2.4, Anomaly = 0.1 },
		center = { -700, -620 },
		size = { 600, 520 },
		color = "B6FF6E",
		material = "Glass",
		built = false, -- beyond the MVP slice; no items stock it yet
	},
	{
		id = 6,
		name = "The Crater",
		baseRads = 100,
		soilHardness = 6,
		ratedSuitTier = 6,
		-- The Crater is a heist, not a hike (PLAN §16) — but "short" has to mean
		-- short from its OWN on-site station, which does not exist yet. This is the
		-- honest walk from base camp until that station is built.
		stationDistance = 658,
		fogColor = Color3.fromHex("FFD24A"),
		fogEnd = 400,
		loot = { Scrap = 2, Common = 6, Uncommon = 15, Rare = 24, Epic = 26, Legendary = 18, Mythic = 8, Anomaly = 0.8 },
		center = { 0, 760 },
		size = { 360, 320 },
		color = "FFE066",
		material = "Neon",
		built = false, -- beyond the MVP slice; no items stock it yet
	},
} :: { ZoneDef }

-- One radiation field, three stages. Stage bounds are local X offsets from the
-- field centre, so the field can move without the progression walls drifting away
-- from the loot they protect. The later stages reuse the existing zone item pools
-- until the catalogue is split into an explicitly staged content model.
Zones.STAGES = {
	{
		id = 1,
		name = "Outer Ash",
		minX = -330,
		maxX = -110,
		unlockTier = 1,
		loot = Zones.DEFS[1].loot,
		itemZoneId = 1,
		color = "6F9636",
	},
	{
		id = 2,
		name = "Hot Wreckage",
		minX = -110,
		maxX = 100,
		unlockTier = 2,
		loot = Zones.DEFS[2].loot,
		itemZoneId = 2,
		color = "538C28",
	},
	{
		id = 3,
		name = "Deep Fallout",
		minX = 100,
		maxX = 330,
		unlockTier = 3,
		loot = Zones.DEFS[3].loot,
		itemZoneId = 3,
		color = "3E7A1C",
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
