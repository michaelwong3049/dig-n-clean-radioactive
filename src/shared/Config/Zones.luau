--!strict
-- Zones.lua — PLAN §4.
--
-- NOTE: `ratedSuitTier` is documentation, not enforcement. There is no gate anywhere
-- in this codebase that reads it to deny entry. Zones are open (PLAN §3.5); the only
-- thing that stops a player is the arithmetic in Shared/Radiation.lua.
--
-- `stationDistance` is the design's primary tension lever (PLAN §4, zone design rules)
-- and should be tuned BEFORE rad rates. It is the distance in studs from the zone's
-- good dirt to its nearest decon station — i.e. how long the decay clock runs.

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
}

local Zones = {}

Zones.DEFS = {
	{
		id = 1,
		name = "Ash Flats",
		baseRads = 0.5,
		soilHardness = 1,
		ratedSuitTier = 1,
		stationDistance = 90,
		fogColor = Color3.fromHex("B8B5AE"),
		fogEnd = 550,
		loot = { Scrap = 55, Common = 28, Uncommon = 12, Rare = 4, Epic = 0.8, Legendary = 0.15, Mythic = 0.04, Anomaly = 0.002 },
	},
	{
		id = 2,
		name = "The Suburbs",
		baseRads = 2,
		soilHardness = 2,
		ratedSuitTier = 2,
		stationDistance = 190,
		fogColor = Color3.fromHex("A8AC9C"),
		fogEnd = 460,
		loot = { Scrap = 42, Common = 30, Uncommon = 18, Rare = 7, Epic = 2, Legendary = 0.5, Mythic = 0.1, Anomaly = 0.004 },
	},
	{
		id = 3,
		name = "Fallout Fields",
		baseRads = 6,
		soilHardness = 3,
		ratedSuitTier = 3,
		stationDistance = 340,
		fogColor = Color3.fromHex("8FA37A"),
		fogEnd = 380,
		loot = { Scrap = 28, Common = 30, Uncommon = 24, Rare = 12, Epic = 4.5, Legendary = 1.2, Mythic = 0.28, Anomaly = 0.01 },
	},
	{
		id = 4,
		name = "The Exclusion Belt",
		baseRads = 15,
		soilHardness = 4,
		ratedSuitTier = 4,
		stationDistance = 520,
		fogColor = Color3.fromHex("7E9668"),
		fogEnd = 300,
		loot = { Scrap = 15, Common = 24, Uncommon = 28, Rare = 20, Epic = 9, Legendary = 3, Mythic = 0.8, Anomaly = 0.03 },
	},
	{
		id = 5,
		name = "Reactor Grounds",
		baseRads = 40,
		soilHardness = 5,
		ratedSuitTier = 5,
		stationDistance = 700,
		fogColor = Color3.fromHex("9C8A4E"),
		fogEnd = 240,
		loot = { Scrap = 7, Common = 15, Uncommon = 25, Rare = 26, Epic = 17, Legendary = 7, Mythic = 2.4, Anomaly = 0.1 },
	},
	{
		id = 6,
		name = "The Crater",
		baseRads = 100,
		soilHardness = 6,
		ratedSuitTier = 6,
		stationDistance = 260, -- deliberately SHORT: the Crater is a heist, not a hike (PLAN §16)
		fogColor = Color3.fromHex("C4762F"),
		fogEnd = 170,
		loot = { Scrap = 2, Common = 6, Uncommon = 15, Rare = 24, Epic = 26, Legendary = 18, Mythic = 8, Anomaly = 0.8 },
	},
} :: { ZoneDef }

function Zones.get(id: number): ZoneDef
	local z = Zones.DEFS[id]
	assert(z, `unknown zone {id}`)
	return z
end

return Zones
