--!strict
--[[
	Camps.luau — the safe zones strung along the stage chain.

	A CAMP IS WHERE THE WASTELAND STOPS. Standing in one means standing in no stage, so
	the rest-pocket rule (zero rads, 6x regen — ExposureService) already covers it for
	free, the same way it covers the plaza. Nothing here makes a camp safe; being
	outside every stage rectangle does. build/CampSite and World.verify() hold the
	footprints to that.

	BASE CAMP IS CAMP 1, AND IT HAS NO SITE HERE. Its geometry is the plaza, the plot
	ring and the shops (build/Hub, build/Plots, build/Shops), all of which predate this
	file and own their own numbers. It is listed so every camp has an id, a key and a
	name, and so "which camp is this" has an answer for the one everybody starts in.

	EVERY OTHER CAMP IS A SITE: a walled disc built by build/CampSite from the entry
	below. Toxic Twilight is the first, sitting on the Crater's east edge where the
	chain used to stop at open water. Stages 7+ will carry on east from it.

	`key` IS THE WIRE AND SAVE SPELLING. WarpService takes it as a destination and
	DataService stores `camps[key] = true` once a player has reached the camp on foot,
	which is what unlocks its warp button. Never rename a key once shipped — a saved
	unlock would point at nothing.
]]

local Stages = require(script.Parent.Stages)

export type Palette = {
	groundDark: string, -- the lawn's checker pair
	groundLight: string,
	lipDark: string, -- the turf carried up over the wall's crown and drips
	lipLight: string,
	wallDark: string, -- the wall faces and the island's cliff
	wallLight: string,
	pathDark: string, -- the plaza octagon and its paths
	pathLight: string,
	paverDark: string, -- the shop square
	paverLight: string,
	kerb: string, -- the shop square's one-tile edge
	deck: string, -- the cleansing station's raised deck
	bush: string,
	bushDark: string,
	awnings: { string }, -- one accent per stall shell, striped against white
	-- Per-track roof/sign accent for this camp's working shops (Detector, Magnet, Cleaner,
	-- Aura); a track missing here keeps its plaza colour.
	shopColors: { [string]: string }?,
}

--- How a camp looks on its row in the Warp panel (client CampWarpController): a little
--- postcard of the place -- sky, wall, lawn, path and two stall roofs -- in the camp's
--- own colours. Every camp carries one, Base Camp included, so a new camp only needs
--- its entry here to show up on the panel.
export type Card = {
	skyTop: string,
	skyBottom: string,
	wall: string,
	wallCap: string,
	lawn: string,
	path: string,
	roofs: { string }, -- left stall, right stall
	accent: string, -- the "CAMP N" caption over the name
}

export type CampDef = {
	id: number,
	key: string,
	name: string,
	blurb: string, -- the Warp panel's one line under the name
	card: Card,
	-- Site camps only (nil on Base Camp, whose footprint lives in build/Hub + Plots).
	center: { number }?, -- { x, z } of the disc
	radius: number?, -- the walkable floor's radius; the wall stands just outside it
	clipX: number?, -- the disc is cut off west of this line, where the stage chain meets it
	exitX: number?, -- and east of this one, where the next stage will open out of it
	palette: Palette?,
	-- Stands the Merge Reactor (build/MergeReactor, Services/MergeService) on its own
	-- deck south of the plaza. Reaching the camp is what unlocks merging.
	mergeReactor: boolean?,
	-- Stands the Reforge Station (build/ReforgeStation, Services/ReforgeService) on the
	-- north deck in the cleansing station's place; the cleansing station moves to its own
	-- deck north-west of the plaza, on a spur off the entry path (build/CampSite).
	reforge: boolean?,
	-- Built and seen, never entered: build/CampSite stands the formation with every stall a
	-- shell, no trader, station or warp anchor, and a COMING SOON barricade across the
	-- entrance. The Warp panel keeps showing it as the "???" row.
	comingSoon: boolean?,
}

local Camps = {}

--- How far east of a stage's east edge a site camp's disc centre sits. With a 225 floor
--- radius (1.5x the first cut, on request) the disc's chord at the clip line is ~153
--- wide either side of z = 0 -- a little past the corridor walls, so two short shoulder
--- walls close the gap the same way Base Camp's shoulders meet Stage 1 (build/Scenery
--- buildCampWallLayer). Twice this is Stages' CAMP_GAP.
local SITE_CENTRE_OFFSET = 165

--- FOUR STAGES PER ZONE (2026-10-03): a site camp sits off the east edge of every stage
--- in Stages.CAMP_AFTER -- Toxic Twilight past Stage 4, Magma Hollow past Stage 8. The
--- disc is cut off at that edge and at its mirror, where the next stage opens out of it
--- through a mouth exactly as wide as the one it is entered by.
local function siteAfter(stageId: number): (number, number, number)
	local clipX = select(3, Stages.bounds(stageId))
	return clipX + SITE_CENTRE_OFFSET, clipX, clipX + 2 * SITE_CENTRE_OFFSET
end

local TWILIGHT_X, TWILIGHT_CLIP_X, TWILIGHT_EXIT_X = siteAfter(4)
local MAGMA_X, MAGMA_CLIP_X, MAGMA_EXIT_X = siteAfter(8)

Camps.BASE = "base"

--- The world names both sides agree on: build/CampSite builds every site camp under
--- Workspace[MODEL_NAME], each with one part named ANCHOR_NAME (carrying CampKey) where
--- a warp lands you. Here rather than in the builder so CampService can find the anchor
--- without requiring the whole build/ chain at boot.
Camps.MODEL_NAME = "Camps"
Camps.ANCHOR_NAME = "CampAnchor"

Camps.DEFS = {
	{
		id = 1,
		key = "base",
		name = "Base Camp",
		blurb = "Your base, the shops and the trader",
		card = {
			skyTop = "7FB8DE",
			skyBottom = "D9E6C4",
			wall = "6B4A2E",
			wallCap = "8A6440",
			lawn = "5DAA3C",
			path = "B9B2A0",
			roofs = { "D8563B", "E5A53A" },
			accent = "4ADE80",
		},
	},
	{
		id = 2,
		key = "twilight",
		name = "Toxic Twilight",
		blurb = "Past the Ooze Marsh, at the end of Stage 4",
		-- Its palette below, under a dusk sky.
		card = {
			skyTop = "2B1D4A",
			skyBottom = "B0709A",
			wall = "3E2A5C",
			wallCap = "5B4382",
			lawn = "2F8A7D",
			path = "CBBBE9",
			roofs = { "A855FF", "4FD1C5" },
			accent = "C084FC",
		},
		center = { TWILIGHT_X, 0 },
		-- Near Base Camp's ring (Plots.RING_OUTER 230); 1.5x the first cut, lawn only. There are no plots here,
		-- only the plaza, the stalls, the trader and one shared cleansing station.
		radius = 225,
		clipX = TWILIGHT_CLIP_X,
		exitX = TWILIGHT_EXIT_X,
		mergeReactor = true,
		reforge = true,
		-- Mockup #3, picked from six on request: it carries the Crater's violet on into
		-- the camp instead of snapping back to Base Camp's green.
		palette = {
			-- Dark purple checker floor, on request (was teal 2F8A7D/379688). The wall
			-- crown's turf keeps its teal lip -- floor only.
			groundDark = "2B1A45",
			groundLight = "331F52",
			lipDark = "319585",
			lipLight = "3AA493",
			wallDark = "3E2A5C",
			wallLight = "473166",
			pathDark = "CBBBE9",
			pathLight = "D8CBF0",
			paverDark = "7C5AB0",
			paverLight = "8966BD",
			kerb = "57407E",
			deck = "4A3A52",
			bush = "52D6A8",
			bushDark = "3AAE86",
			awnings = { "A855FF", "4FD1C5", "FF7AC6", "FFD24A" },
			-- On request: the shops' own Twilight colours, darker tones, not the plaza's.
			shopColors = {
				Aura = "7B3FB8", -- deep violet
				Detector = "A8305F", -- dark raspberry
				Cleaner = "177F70", -- dark teal
				Magnet = "3F4BA8", -- deep indigo
			},
		},
	},
	{
		id = 3,
		key = "magma",
		name = "Magma Hollow",
		blurb = "Past the Cobalt Shelf, at the end of Stage 8",
		card = {
			skyTop = "2A1410",
			skyBottom = "C2481E",
			wall = "2C2624",
			wallCap = "D2541E",
			lawn = "3B3330",
			path = "75695F",
			roofs = { "D2541E", "8A3A1C" },
			accent = "FF7A2E",
		},
		-- FOUR STAGES PER ZONE (2026-10-03): what was the Zone 3 COMING SOON formation
		-- past Stage 12, moved to the end of Stage 8 and opened up as the lava camp.
		-- Basalt floor and walls, ember-orange crown. Stage 9 opens out of its east mouth.
		center = { MAGMA_X, 0 },
		radius = 225,
		clipX = MAGMA_CLIP_X,
		exitX = MAGMA_EXIT_X,
		-- Every pair is a 0.877 two-tone (dark = light x 0.877 per channel), so the
		-- shared StudChecker material covers them all with no new colour maps.
		palette = {
			groundDark = "342D2A", -- basalt lawn
			groundLight = "3B3330",
			lipDark = "B84A1A", -- glowing ember crust over the wall crown
			lipLight = "D2541E",
			wallDark = "272120", -- cooled black rock cliff
			wallLight = "2C2624",
			pathDark = "675C53", -- ash-grey plaza and paths
			pathLight = "75695F",
			paverDark = "443A35",
			paverLight = "4E423C",
			kerb = "FF6A1A",
			deck = "3A302C",
			bush = "FF7A2E",
			bushDark = "E06B28",
			awnings = { "D2541E", "8A3A1C", "FF9A3C", "4E423C" },
			shopColors = {
				Aura = "A8301C", -- deep magma red
				Detector = "C9601A", -- burnt orange
				Cleaner = "3E6E74", -- quench-water steel
				Magnet = "5E3A2A", -- rust
			},
		},
	},
} :: { CampDef }

local byKey: { [string]: CampDef } = {}
local byId: { [number]: CampDef } = {}
for _, def in Camps.DEFS do
	byKey[def.key] = def
	byId[def.id] = def
end

function Camps.get(key: string): CampDef?
	return byKey[key]
end

function Camps.byId(id: number): CampDef?
	return byId[id]
end

--- Every camp build/CampSite actually builds -- i.e. all but Base Camp.
function Camps.sites(): { CampDef }
	local out = {}
	for _, def in Camps.DEFS do
		if def.center ~= nil then
			table.insert(out, def)
		end
	end
	return out
end

--- The site camp whose floor contains world (x, z), or nil. Base Camp is never
--- returned: anywhere outside every stage and every site is Base Camp by default,
--- which is what the HUD already assumed before there was a second camp.
function Camps.at(x: number, z: number): CampDef?
	for _, def in Camps.DEFS do
		local c, r, clip = def.center, def.radius, def.clipX
		if c and r and clip and x >= clip and (def.exitX == nil or x <= def.exitX) then
			local dx, dz = x - c[1], z - c[2]
			if dx * dx + dz * dz <= r * r then
				return def
			end
		end
	end
	return nil
end

return Camps
