--!strict
--[[
	CliffWall.luau — a boundary wall built as stacked slabs, not one flat checker face.

	On request (2026-10-08, from a reference shot): "make the walls structured like this".
	Instead of one flat face with a grass row painted on top, the wall is laid in RUNS of
	2-6 tiles along its length, and each run is:

	  • a DIRT body (the wall's own checker pair) whose face is set back 0-2 studs, so the
	    face steps in and out along the wall. Set back, never forward, so a run never
	    eats into walkable ground or a stage field;
	  • a thick GRASS slab on top, one or two tiles deep, standing 2-3.5 studs proud of the
	    dirt below it, its top 2-4 studs above the body line, so the overhang edge and the
	    skyline both jog from run to run;
	  • STEPPED DRIPS under the overhang: 2-3 tiers, each narrower, shallower and lighter
	    (grass, then MID_GREEN, then LIME_GREEN).

	A grey stone foot was tried in the same preview and dropped on request.

	Dirt and grass lay as one checker-material block each (Kit.checkerMaterialFor), with
	the flipped twin whenever the anchor cell lands on light, so a run stays one part.
	The dirt is the barrier (collidable, queryable, as the old wall body was); the grass
	slab collides too but never answers queries, like the old crown; drips are looks only.
]]

local Stages = require(game:GetService("ReplicatedStorage").Shared.Config.Stages)
local Kit = require(script.Parent.Kit)

local CliffWall = {}

-- Lighter greens the drips step down through, darkest tier first (the grass pair itself).
local MID_GREEN = "74A957"
local LIME_GREEN = "A7C64B"

local RUN_TILES = { min = 2, max = 6 } -- run length along the wall, in tiles
local RECESS = { 0, 0, 1, 2 } -- studs a run's dirt face sits back, picked per run
local GRASS_TILES = { 1, 1, 2 } -- grass slab depth below the body line, in tiles
local GRASS_RISE = { 2, 2, 3, 4 } -- studs the slab's top stands above the body line
local OVERHANG = { min = 2, max = 3.5 } -- studs the slab reaches past its run's dirt face
local DRIP = { chance = 0.3, threeTiers = 0.5, minW = 2.4, maxW = 3.4, minH = 1.2, maxH = 2.2 }

local SMOOTH_FACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }

export type Opts = {
	name: string,
	-- frame at along-wall coordinate s (world X or Z): local X along the wall, local Y
	-- world Y, local Z the thickness axis with the wall centred on z = 0
	frameAt: (number) -> CFrame,
	face: string, -- the visible face in that frame: "FrontSurface" (-Z) or "BackSurface" (+Z)
	s0: number,
	s1: number,
	height: number, -- the body line, above Stages.SURFACE_Y
	footRows: number, -- tiles sunk below the surface
	tile: number,
	thick: number,
	seed: number,
	body: { string }, -- { dark, light }
	grass: { string }, -- { dark, light }
	flat: { { number } }?, -- { s0, s1 } stretches whose face stays flush (no recess)
	recess: { number }?, -- overrides RECESS (the camp's outer layer passes { 0 })
}

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

--- One checker-material block, `y0..y1` tall and `z0..z1` deep in the run's frame. The
--- side face anchors on its top edge at one end (see Kit's wall notes); `anchorIx` and
--- the top row pick the plain map or its flipped twin so the run stays in register.
local function slab(parent: Instance, o: Opts, a: number, b: number, y0: number, y1: number, z0: number, z1: number, pair: { string }, anchorIx: number, collide: boolean): BasePart
	local part = Kit.build(parent, o.frameAt((a + b) / 2), {
		name = o.name,
		pos = { 0, (y0 + y1) / 2, (z0 + z1) / 2 },
		size = { b - a, y1 - y0, z1 - z0 },
		color = pair[2],
		material = "Plastic",
		canCollide = collide,
	})
	local topRow = math.floor((y1 - Stages.SURFACE_Y) / o.tile - 1e-3)
	local onDark = (anchorIx + topRow) % 2 == 0
	local variant = Kit.checkerMaterialFor(pair[1], pair[2], not onDark)
	if variant then
		part.MaterialVariant = variant
		for _, f in SMOOTH_FACES do
			(part :: any)[f] = Enum.SurfaceType.Smooth
		end
	else
		part.Color = Color3.fromHex(pair[1])
		for _, f in SMOOTH_FACES do
			(part :: any)[f] = Enum.SurfaceType.Studs
		end
	end
	return part
end

function CliffWall.build(parent: Instance, o: Opts)
	local faceSign = if o.face == "BackSurface" then 1 else -1
	local tile = o.tile
	local baseY = Stages.SURFACE_Y
	local bodyTop = baseY + o.height
	local footY = baseY - o.footRows * tile
	local backZ = -faceSign * o.thick / 2
	local faceZ = faceSign * o.thick / 2
	local rng = Random.new(o.seed)

	-- Which end of a block the side face anchors on, as Kit.materialWall works it out.
	local first = o.frameAt(o.s0)
	local localXWithS = (o.frameAt(o.s0 + 1).Position - first.Position):Dot(first.XVector) >= 0
	local anchorAtHighS = (o.face == "FrontSurface") == localXWithS

	local function isFlat(a: number, b: number): boolean
		for _, f in o.flat or {} do
			if a < f[2] and b > f[1] then
				return true
			end
		end
		return false
	end

	local parts: { BasePart } = {}
	local s = o.s0
	while s < o.s1 - 1e-3 do
		-- Runs break on the tile grid, so every block's anchor cell is a whole cell.
		local nextGrid = (math.floor(s / tile + 1e-3) + rng:NextInteger(RUN_TILES.min, RUN_TILES.max)) * tile
		local e = math.min(nextGrid, o.s1)
		local anchorIx = math.floor((if anchorAtHighS then e - tile / 2 else s + tile / 2) / tile)

		local recess = if isFlat(s, e) then 0 else pick(rng, o.recess or RECESS)
		local grassBottom = bodyTop - pick(rng, GRASS_TILES) * tile
		local grassTop = bodyTop + pick(rng, GRASS_RISE)
		local dirtFace = faceZ - faceSign * recess
		local grassFace = dirtFace + faceSign * rng:NextNumber(OVERHANG.min, OVERHANG.max)

		-- Dirt runs one tile into the slab so its anchor edge (top) sits on the grid.
		table.insert(parts, slab(parent, o, s, e, footY, grassBottom + tile, math.min(backZ, dirtFace), math.max(backZ, dirtFace), o.body, anchorIx, true))
		local grassBack = backZ + faceSign * 0.05 -- shy of the dirt's back face: no z-fight
		local grass = slab(parent, o, s, e, grassBottom, grassTop, math.min(grassBack, grassFace), math.max(grassBack, grassFace), o.grass, anchorIx, true)
		grass.CanQuery = false
		table.insert(parts, grass)

		-- Stepped drips hanging in the overhang, one roll per tile.
		local overhang = math.abs(grassFace - dirtFace)
		for c = s, e - tile + 1e-3, tile do
			if rng:NextNumber() >= DRIP.chance then
				continue
			end
			local xc = c + tile / 2 + rng:NextNumber(-0.5, 0.5)
			local w = rng:NextNumber(DRIP.minW, DRIP.maxW)
			local y = grassBottom + 0.05
			local tiers = if rng:NextNumber() < DRIP.threeTiers then 3 else 2
			local colours = { if rng:NextNumber() < 0.5 then o.grass[1] else o.grass[2], MID_GREEN, LIME_GREEN }
			local reach = overhang - rng:NextNumber(0.1, 0.5)
			for i = 1, tiers do
				local h = rng:NextNumber(DRIP.minH, DRIP.maxH)
				local d = reach * (1 - 0.22 * (i - 1))
				local z0 = dirtFace - faceSign * 0.05
				local drip = Kit.build(parent, o.frameAt(xc), {
					name = o.name .. "Drip",
					pos = { 0, y - h / 2, z0 + faceSign * d / 2 },
					size = { w, h, d },
					color = colours[i],
					material = "Plastic",
					canCollide = false,
				});
				(drip :: any)[o.face] = Enum.SurfaceType.Studs
				drip.CanQuery = false
				drip.CanTouch = false
				drip.CastShadow = false
				table.insert(parts, drip)
				y -= h
				w *= rng:NextNumber(0.55, 0.7)
			end
		end
		s = e
	end

	for _, p in parts do
		p.CanTouch = false
	end
end

return CliffWall
