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
	palette: Palette?,
}

local Camps = {}

--- Stage 6's east edge. The Crater's corridor opens straight into the Twilight disc
--- here, so it is read off the stage rather than typed twice.
local CRATER_EAST_X = select(3, Stages.bounds(6))

--- How far east of the Crater's edge the disc's centre sits. With a 150 floor radius
--- the disc's chord at the clip line is ~102 wide either side of z = 0 -- a little past
--- the corridor walls (z = +-89), so two short shoulder walls close the gap the same
--- way Base Camp's shoulders meet Stage 1 (build/Scenery buildCampWallLayer).
local TWILIGHT_CENTRE_OFFSET = 110

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
		blurb = "Past the Crater, at the end of Stage 6",
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
		center = { CRATER_EAST_X + TWILIGHT_CENTRE_OFFSET, 0 },
		-- About 65% of Base Camp's ring (Plots.RING_OUTER 230). There are no plots here,
		-- only the plaza, the stalls, the trader and one shared cleansing station.
		radius = 150,
		clipX = CRATER_EAST_X,
		-- Mockup #3, picked from six on request: it carries the Crater's violet on into
		-- the camp instead of snapping back to Base Camp's green.
		palette = {
			groundDark = "2F8A7D",
			groundLight = "379688",
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
		if c and r and clip and x >= clip then
			local dx, dz = x - c[1], z - c[2]
			if dx * dx + dz * dz <= r * r then
				return def
			end
		end
	end
	return nil
end

return Camps
