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
--     c = 45 * pi * r^2 / area      (fraction of the surface inside some ping disk)
--
-- Zone 1 as originally hand-built is the known-good calibration point: 300x265 with
-- a tier-1 detector (radius 12) gives c = 0.256, and that is verified playable.
--
-- So every zone is sized so that ITS OWN RATED DETECTOR reproduces c ~= 0.26. Each
-- zone then feels the same to search, and the difficulty gradient comes entirely
-- from radiation — which is what PLAN §3 says the differentiator is supposed to be.
--
--     zone 1   300x265   r=12 (T1)   c = 0.256
--     zone 2   400x350   r=16 (T2)   c = 0.259
--     zone 3   510x460   r=21 (T3)   c = 0.266
--     zone 4   290x260   r=27 (T4)   c = 1.37   <- deliberately inverted, see below
--
-- Hard ceiling: area <= 785 * r^2. Past that a zone is unplayable at its rated tier,
-- and it presents as "the detector feels bad" rather than as any kind of error.
--
-- Zone 4 breaks the rule ON PURPOSE. It is a dive, not a farm (PLAN §3.5): you get
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
		stationDistance = 342,
		fogColor = Color3.fromHex("CFF3FF"),
		fogEnd = 900,
		loot = { Scrap = 55, Common = 28, Uncommon = 12, Rare = 4, Epic = 0.8, Legendary = 0.15, Mythic = 0.04, Anomaly = 0.002 },
		center = { 310, 0 },
		size = { 300, 265 },
		color = "9FE07A",
		material = "Sand",
		built = true,
	},
	{
		id = 2,
		name = "The Suburbs",
		baseRads = 2,
		soilHardness = 2,
		ratedSuitTier = 2,
		stationDistance = 460,
		fogColor = Color3.fromHex("D8F0B8"),
		fogEnd = 800,
		loot = { Scrap = 42, Common = 30, Uncommon = 18, Rare = 7, Epic = 2, Legendary = 0.5, Mythic = 0.1, Anomaly = 0.004 },
		center = { -470, 27 },
		size = { 400, 350 },
		color = "8CD95C",
		material = "Sand",
		built = true,
	},
	{
		id = 3,
		name = "Fallout Fields",
		baseRads = 6,
		soilHardness = 3,
		ratedSuitTier = 3,
		stationDistance = 592,
		fogColor = Color3.fromHex("A8F06A"),
		fogEnd = 700,
		loot = { Scrap = 28, Common = 30, Uncommon = 24, Rare = 12, Epic = 4.5, Legendary = 1.2, Mythic = 0.28, Anomaly = 0.01 },
		center = { 0, -490 },
		size = { 510, 460 },
		color = "7CE05A",
		material = "Glass",
		built = true,
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
		color = "5FD838",
		material = "Glass",
		built = true,
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

--- The coverage metric from the header. Spec asserts on it so a resize that makes
--- a zone unsearchable fails loudly instead of just feeling bad.
function Zones.coverage(id: number, detectorRadius: number, signalsPerZone: number): number
	return signalsPerZone * math.pi * detectorRadius * detectorRadius / Zones.area(id)
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
