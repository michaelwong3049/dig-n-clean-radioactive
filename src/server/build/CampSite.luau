--!strict
--[[
	CampSite.luau — every camp after Base Camp, built from Config/Camps.

	    require(game.ServerScriptService.Server.build.CampSite).rebuild()

	A SMALLER BASE CAMP IN ITS OWN COLOURS, ON REQUEST. Each site camp is a walled disc
	of the same studded board the plaza is paved in, with an octagon plaza at its middle,
	a paver square of stalls, the trader and one shared cleansing station. No plots: a
	player's base stays at Base Camp, and every camp after it is somewhere you pass
	through -- dock the haul, wash it, sell it, and push on.

	WHAT IS REAL AND WHAT IS A SHELL. The trader (BaseCamp.buildTrader) and the cleansing
	station (Plots.buildCleansingStation) are the same builders Base Camp uses, carrying
	the same world contract, so the services find them by tag and they simply work here:
	sell at the counter, dock and shower at the tub, wash what you hold. A stall is real
	only where Config/Gear sells something at this camp (a rung's `camp` column): Toxic
	Twilight's north row is the Detector Shop (Shops.buildCampStall), selling that camp's
	six detectors. Every other stall is Shops.buildStallShell -- the frame and steel roof
	with NO station attributes -- because the gear they will sell does not exist yet. They
	say COMING SOON rather than opening a panel for nothing.

	ONE CAMP'S LAYOUT, RELATIVE TO ITS OWN PLAZA CENTRE. Config/Camps gives the disc
	(centre, radius, the clip lines where the stage chain comes in and goes on) and the
	palette; everything on the disc is placed off `plazaCentre`, the grid cell nearest
	the disc's own centre, so every edge below lands on a tile line. Moving a camp is a Config
	change and a rebuild.

	          two-layer wall: inner 48, outer 72 behind it (a stepped cliff)
	         .-'''''''''''''''''-.
	        /      [WASH DECK]    \          +Z ("north", this codebase's convention)
	  ====|         |path|         |====
	 STAGE   .-''''''''''''''''-.   | STAGE
	   6  =  | [shell]  [shell] |  ==  7   (the east mouth; a COMING SOON
	 ======  |   (anchor)       |  ==      barricade until Stage 7 is built)
	         | [shell][TRADER][shell]|====
	        \ `-..............-'  /
	         `-..................-'

	THE WALL IS ITS OWN CODE, NOT Scenery's, deliberately. Base Camp's perimeter
	(Scenery.buildCampWallLayer) is written against Plots.RING_CENTER and the camp-green
	palette, and rewiring it to take both as arguments would put Base Camp's walls at
	risk for a camp that only needs the same technique: columns sized to a 4-stud chord,
	studded on the face you can see, turf carried up over the crown. Same look, separate
	numbers.

	THE WORLD CONTRACT (checked by World.verify()):
	    Workspace.Camps.<Key>        one Model per site camp, carrying CampId + CampKey
	    ...<Key>.CampAnchor           where WarpService lands you -- CampId, CampKey.
	                                  Never inside a stage; CampService reads it.
	    ...<Key>.Trader               StationKind = "trader" (one per camp)
	    ...<Key>.CleansingStation     StationKind = "decon", Shower, IsWashStand, Hose
	    ...<Key>.Stalls.EmptyStall    NO StationKind, by contract
	    ...<Key>.Stalls.DetectorShop  StationKind = "shop", ShopCamp = <Key>; only where
	                                  Gear sells detector rungs at this camp
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Camps = require(Shared.Config.Camps)
local Gear = require(Shared.Config.Gear)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)
local Shops = require(script.Parent.Shops)
local BaseCamp = require(script.Parent.BaseCamp)
local Plots = require(script.Parent.Plots)

local CampSite = {}
CampSite.MODEL_NAME = Camps.MODEL_NAME
CampSite.ANCHOR_NAME = Camps.ANCHOR_NAME
local BUILDER_SOURCE = "src/server/build/CampSite.luau"
local BUILDER_VERSION = 6

local C = Kit.C
local build = Kit.build

-- ── Layout ────────────────────────────────────────────────────────────────────

local TILE = Hub.TILE_SIZE
local FLOOR_Y = Stages.SURFACE_Y -- the lawn; flush with the stage it opens off
local PLAZA_Y = FLOOR_Y + Hub.PLAZA_LIFT -- the octagon, its paths and the shop square

--- The structural body under the tiles, laid as thin bands clipped to the disc (a
--- Cylinder would be a true circle but cannot be cut off at the clip line, and the
--- sliver west of it would hang out past the stage's corridor wall).
local SLAB_THICKNESS = 8
local SLAB_BAND = 2

--- The octagon, from the plaza centre. HALF is 4k + 2 and DIAG a multiple of 4 -- the
--- same rule Hub's own octagon follows (see PLAZA_OCT_* there), so the axis sides fall
--- on tile lines and the diagonals run corner to corner through the cells they cut.
--- 70 * sqrt 2 = 99, so 100 is near-regular.
local OCT_HALF = 70
local OCT_DIAG = 100

--- Half-width of the gate paths: in from the stage on the west, and north up to the
--- wash deck. 10 either side of centre lands both edges on tile lines.
local PATH_HALF = 10

--- The paver square, from the plaza centre. Both edges on tile lines; a one-tile kerb.
local SHOP_HALF_X, SHOP_HALF_Z = 42, 38

--- Two rows of storefronts facing each other across the aisle, the Base Camp read:
--- the north row faces south, the south row faces north with the trader in its middle.
--- Stall shells' footprint runs local z -11.25..+2.75 (Shops.buildStallShell), so at
--- ROW_Z = 22 each row stays inside the square with the aisle between them ~38 wide.
local ROW_Z = 22
local STALL_WIDTH = 24
local NORTH_STALL_X = { -15, 15 }
local SOUTH_STALL_X = { -26, 26 }
local TRADER_Z = -26 -- the kiosk's deck is 13 deep, so its front lines up with the row
local STALL_LABEL = "COMING SOON"

--- The wash deck, north of the octagon, one plot-pad step (1.5) above the lawn so the
--- cleansing station stands at the height it was built for (Plots.PAD.topY). The bay
--- sits far enough back that WashService's big-lump stand-off (up to ~14 in front of
--- the tub) still lands the player on the deck.
local DECK_HALF_X = 22
local DECK_MIN_Z, DECK_MAX_Z = 74, 106
local DECK_THICKNESS = 3
local BAY_Z = 94

--- The perimeter wall. Height matches the stage corridor's (Scenery WALL_HEIGHT), so
--- the shoulder meets the Crater's wall flush.
local WALL_T = 8
local WALL_H = 48
local WALL_TILE = 4
local CAP_T = 2
local LIP_OVERHANG = 0.5
local CROWN_BUSH_EVERY = 5
local CROWN_BUSH_CHANCE = 0.4

--- THE WALL IS TWO LAYERS, ON REQUEST ("like how it is in base 1"): the original ring,
--- and a taller outer ring standing flush behind it, so from inside the camp the wall
--- reads as a stepped cliff -- the inner ring's turf crown becomes a ledge in front of
--- the outer face. Same height as Base Camp's outer ring (Scenery OUTER_WALL_HEIGHT).
local OUTER_WALL_H = 72

--- The barricade across the east mouth while the stage beyond it is unbuilt. It stands
--- on the camp's own floor just inside the clip line (there is nothing past it yet), and
--- an invisible wall-height collider behind it keeps anyone from hopping the rails.
local GATE_POST_EVERY = 17
local GATE_RAIL_Y = { 2.6, 5.2 }
local GATE_POST_H = 6.4
local GATE_SIGN_W, GATE_SIGN_H = 34, 7
local GATE_SIGN_Y = 9
local GATE_TEXT = "STAGE 7 · COMING SOON"

--- The hazard line on the seam where the stage chain opens into the camp, the same
--- tape Scenery.buildStageBorderLines lays between every pair of stages.
local SEAM_WIDTH = 3
local SEAM_ROWS = 2
local SEAM_CELL_Z = 3

--- Lawn foliage: a jittered grid, thinned hard, kept off the paving and the wall.
local BUSH_CELL = 24
local BUSH_CHANCE = 0.1
local BUSH_WALL_CLEARANCE = 8

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Deterministic 0..1 from an integer and a salt, so a rebuild never reshuffles.
local function hash01(n: number, salt: number): number
	local s = math.sin(n * 127.1 + salt * 311.7) * 43758.5453
	return s - math.floor(s)
end

local function lighter(hex: string, t: number): string
	return Kit.blendHex(hex, "FFFFFF", t)
end

type Layout = {
	def: Camps.CampDef,
	palette: Camps.Palette,
	cx: number, -- the disc
	cz: number,
	radius: number,
	clipX: number,
	exitX: number?, -- the east clip line, where the next stage opens out (nil = walled shut)
	nextBuilt: boolean, -- a built stage already starts at exitX, so the mouth is open
	ox: number, -- the plaza centre: the grid cell nearest the disc centre
	oz: number,
	corridorHalfZ: number, -- the stage chain's half-width, where it opens in
}

local function layoutOf(def: Camps.CampDef): Layout
	local center = def.center :: { number }
	local ox, oz = Hub.cellCentre(center[1], center[2])
	local exitX = def.exitX
	local corridorHalfZ = 0
	local nextBuilt = false
	for _, id in Stages.builtIds() do
		local minX, minZ, _, maxZ = Stages.bounds(id)
		corridorHalfZ = math.max(corridorHalfZ, -minZ, maxZ)
		if exitX and math.abs(minX - exitX) < 0.5 then
			nextBuilt = true
		end
	end
	return {
		def = def,
		palette = def.palette :: Camps.Palette,
		cx = center[1],
		cz = center[2],
		radius = def.radius :: number,
		clipX = def.clipX :: number,
		exitX = exitX,
		nextBuilt = nextBuilt,
		ox = ox,
		oz = oz,
		corridorHalfZ = corridorHalfZ,
	}
end

-- ── The floor ─────────────────────────────────────────────────────────────────

--- Is (x, z) on the paved floor -- the octagon or one of its two gate paths? A pure
--- shape test; Hub.coverOf turns it into whole and split cells.
local function paved(L: Layout, x: number, z: number): boolean
	local ax, az = math.abs(x - L.ox), math.abs(z - L.oz)
	if ax <= OCT_HALF and az <= OCT_HALF and ax + az <= OCT_DIAG then
		return true
	end
	-- West, in from the stage: the clip line to the octagon's west side.
	if az <= PATH_HALF and x >= L.clipX and x <= L.ox then
		return true
	end
	-- East, out to the next stage's mouth.
	if L.exitX and az <= PATH_HALF and x >= L.ox and x <= L.exitX then
		return true
	end
	-- North, up to (and on under) the wash deck.
	if ax <= PATH_HALF and z >= L.oz and z <= L.oz + DECK_MIN_Z + TILE then
		return true
	end
	return false
end

local function inShop(L: Layout, x: number, z: number): boolean
	return math.abs(x - L.ox) <= SHOP_HALF_X and math.abs(z - L.oz) <= SHOP_HALF_Z
end

local function buildFloor(parent: Instance, L: Layout)
	local p = L.palette
	local reach = L.radius + WALL_T / 2 -- tiles tuck under the wall's inner half

	local function inside(x: number, z: number): boolean
		return paved(L, x, z)
	end

	local function pairAt(x: number, z: number): (string, string, number)
		local cx, cz = Hub.cellCentre(x, z)
		if Hub.coverOf(inside, cx, cz) ~= "full" then
			return p.groundDark, p.groundLight, 0
		end
		if inShop(L, cx, cz) then
			local kerb = not (
				inShop(L, cx - TILE, cz)
				and inShop(L, cx + TILE, cz)
				and inShop(L, cx, cz - TILE)
				and inShop(L, cx, cz + TILE)
			)
			if kerb then
				return p.kerb, p.kerb, Hub.PLAZA_LIFT
			end
			return p.paverDark, p.paverLight, Hub.PLAZA_LIFT
		end
		return p.pathDark, p.pathLight, Hub.PLAZA_LIFT
	end

	local function splitAt(x: number, z: number): Hub.GroundSplit?
		local cx, cz = Hub.cellCentre(x, z)
		local cover, sx, sz = Hub.coverOf(inside, cx, cz)
		if cover ~= "split" then
			return nil
		end
		return {
			inner = { p.pathDark, p.pathLight },
			outer = { p.groundDark, p.groundLight },
			innerLift = Hub.PLAZA_LIFT,
			sx = sx,
			sz = sz,
		}
	end

	local tileMaxX = L.cx + reach
	if L.exitX then
		tileMaxX = math.min(tileMaxX, L.exitX)
	end
	local rect: Hub.Rect = { minX = L.clipX, maxX = tileMaxX, minZ = L.cz - reach, maxZ = L.cz + reach }

	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	Hub.tileRect(tiles, rect, {
		topY = FLOOR_Y,
		skip = function(x: number, z: number): boolean
			local dx, dz = x - L.cx, z - L.cz
			return dx * dx + dz * dz > reach * reach
		end,
		pairAt = pairAt,
		splitAt = splitAt,
	})
	tiles.Parent = parent

	-- The body: thin bands under the tiles, each spanning the disc's own chord (both
	-- wall layers included) at its z, so the island's cliff follows the circle rather
	-- than stepping out in big rectangles -- cut off at the clip lines where the chord
	-- reaches past them. Outside the corridor mouths the bands run one wall-thickness
	-- further, under the outer layer's shoulders, which stand beyond the clip lines.
	local slab = Instance.new("Folder")
	slab.Name = "Slab"
	local outer = L.radius + 2 * WALL_T
	local topY = FLOOR_Y - 0.4 -- Hub's CAP: the slab is recessed by exactly the tile cap
	local z = L.cz - outer
	while z < L.cz + outer - 1e-3 do
		local z1 = math.min(z + SLAB_BAND, L.cz + outer)
		local mid = (z + z1) / 2 - L.cz
		local half = math.sqrt(math.max(0, outer * outer - mid * mid))
		local beside = math.max(math.abs(z - L.cz), math.abs(z1 - L.cz)) > L.corridorHalfZ
		local pad = if beside then WALL_T else 0
		local minX = math.max(L.cx - half, L.clipX - pad)
		local maxX = L.cx + half
		if L.exitX then
			maxX = math.min(maxX, L.exitX + pad)
		end
		if maxX > minX + 0.5 then
			build(slab, CFrame.new(0, 0, 0), {
				name = "Slab",
				pos = { (minX + maxX) / 2, topY - SLAB_THICKNESS / 2, (z + z1) / 2 },
				size = { maxX - minX, SLAB_THICKNESS, z1 - z },
				color = p.wallDark,
				material = "SmoothPlastic",
			})
		end
		z = z1
	end
	slab.Parent = parent
end

--- The hazard tape across a corridor mouth, its west edge at `x0`. On a mouth with a
--- stage beyond it the tape is centred on the clip line -- half on the stage's floor,
--- half on the camp's, exactly like every stage seam. The east mouth has no floor past
--- it until Stage 7 exists, so there it lies wholly on the camp side.
local function buildSeam(parent: Instance, L: Layout, name: string, x0: number)
	local folder = Instance.new("Folder")
	folder.Name = name
	local rowWidth = SEAM_WIDTH / SEAM_ROWS
	local minZ, maxZ = -L.corridorHalfZ, L.corridorHalfZ
	local cols = math.ceil((maxZ - minZ) / SEAM_CELL_Z)
	for ix = 0, SEAM_ROWS - 1 do
		for iz = 0, cols - 1 do
			local z0 = minZ + iz * SEAM_CELL_Z
			local z1 = math.min(z0 + SEAM_CELL_Z, maxZ)
			if z1 - z0 <= 1e-3 then
				continue
			end
			local tape = build(folder, CFrame.new(0, 0, 0), {
				name = "SeamTape",
				pos = { x0 + (ix + 0.5) * rowWidth, FLOOR_Y + 0.26, (z0 + z1) / 2 },
				size = { rowWidth, 0.4, z1 - z0 },
				color = if (ix + iz) % 2 == 0 then C.barrelYellow else C.hazardBlack,
				material = "SmoothPlastic",
				canCollide = false,
			})
			tape.CanQuery = false
		end
	end
	folder.Parent = parent
end

-- ── The wall ──────────────────────────────────────────────────────────────────

--- A crown bush: three studded blocks, turf-coloured, sitting on the cap.
local function bush(parent: Instance, x: number, y: number, z: number, p: Camps.Palette, seed: number)
	local s = 1.6 + hash01(seed, 3) * 1.4
	for i = 0, 2 do
		local a = i * 2.1 + hash01(seed, 7 + i) * 0.8
		local r = s * 0.55
		local part = build(parent, CFrame.new(0, 0, 0), {
			name = "Bush",
			pos = { x + math.cos(a) * r, y + s * (0.5 + 0.25 * i), z + math.sin(a) * r },
			size = { s * 1.3, s * (1.1 - 0.15 * i), s * 1.3 },
			color = if i == 1 then p.bushDark else p.bush,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
		part.CanQuery = false
	end
end

--- The rows of one wall column: faces in the wall pair, the top row (and a random drip
--- of 0-2 more under it) in the turf pair, reaching LIP_OVERHANG proud of the face.
local function lipRowsOf(col: number, salt: number): number
	local h = hash01(col, salt)
	return 1 + (if h < 0.15 then 2 elseif h < 0.5 then 1 else 0)
end

--- One column of wall `width` wide and `height` tall at `origin`, whose `face` --
--- FrontSurface on an arc column, or whichever face the caller names -- is the one the
--- camp sees and carries the studs; `inward` is that face's normal, for the lip's nudge.
local function wallColumn(
	parent: Instance,
	origin: CFrame,
	width: number,
	height: number,
	col: number,
	p: Camps.Palette,
	salt: number,
	face: string,
	inward: Vector3
)
	local rows = math.ceil(height / WALL_TILE)
	local lipRows = lipRowsOf(col, salt)
	for row = 0, rows - 1 do
		local y0 = FLOOR_Y + row * WALL_TILE
		local y1 = math.min(y0 + WALL_TILE, FLOOR_Y + height)
		local grassy = row >= rows - lipRows
		local thick = if grassy then WALL_T + LIP_OVERHANG else WALL_T
		local shift = if grassy then inward * (LIP_OVERHANG / 2) else Vector3.zero
		local dark, light = p.wallDark, p.wallLight
		if grassy then
			dark, light = p.lipDark, p.lipLight
		end
		local tile = build(parent, origin, {
			name = "Wall",
			pos = { shift.X, (y0 + y1) / 2, shift.Z },
			size = if face == "FrontSurface" then { width, y1 - y0, thick } else { thick, y1 - y0, width },
			color = if (col + row) % 2 == 0 then dark else light,
			material = "Plastic",
			canCollide = true,
		});
		(tile :: any)[face] = Enum.SurfaceType.Studs
	end
end

--- Everything that differs between the two wall layers. Each layer is the same pieces:
--- the arc (split in two by the east mouth when the camp has one) and a pair of short
--- straight shoulders at each clip line, closing the gap between the arc's end and the
--- corridor that opens there.
type WallLayer = {
	name: string, -- the folder it builds into
	radius: number, -- the arc's centreline radius about the disc centre
	westX: number, -- the west shoulders' centreline X
	eastX: number?, -- the east shoulders' centreline X (nil: the arc closes the east)
	height: number,
	westFrom: number, -- |z| the west shoulders start at, off the camp's centre line
	eastFrom: number,
	salt: number,
}

--- A straight shoulder at `x` from |z| = `z0` out to `z1`, both sides of the centre
--- line, facing the camp across `face` (whose world normal is `inward`, +-X).
local function buildShoulders(
	folder: Instance,
	L: Layout,
	layer: WallLayer,
	x: number,
	z0: number,
	z1: number,
	face: string,
	inward: Vector3,
	salt: number
)
	local p = L.palette
	local capY = FLOOR_Y + layer.height + CAP_T / 2 - 0.1
	local n = math.max(1, math.ceil((z1 - z0) / WALL_TILE))
	for _, sign in { -1, 1 } do
		for iz = 0, n - 1 do
			local a = z0 + (z1 - z0) * iz / n
			local b = z0 + (z1 - z0) * (iz + 1) / n
			local mid = sign * (a + b) / 2
			wallColumn(folder, CFrame.new(x, 0, L.cz + mid), b - a, layer.height, 1000 + iz * sign, p, salt, face, inward)
			for cell = 0, 1 do
				-- Two cells across the crown; the camp-side one reaches out over the lip.
				local side = if cell == 0 then -1 else 1
				local reachIn = if side == inward.X then LIP_OVERHANG else 0
				local cap = build(folder, CFrame.new(0, 0, 0), {
					name = "WallCap",
					pos = { x + side * WALL_TILE / 2 + inward.X * reachIn / 2, capY, L.cz + mid },
					size = { WALL_TILE + reachIn, CAP_T, b - a },
					color = if (iz + cell) % 2 == 0 then p.lipDark else p.lipLight,
					material = "Plastic",
					studs = true,
					canCollide = false,
				})
				cap.CanQuery = false
			end
		end
	end
end

local function buildWallLayer(parent: Instance, L: Layout, layer: WallLayer)
	local p = L.palette
	local folder = Instance.new("Folder")
	folder.Name = layer.name

	local rw = layer.radius
	local capY = FLOOR_Y + layer.height + CAP_T / 2 - 0.1

	-- Where the centreline circle crosses a shoulder line: as a bearing in Scenery's
	-- convention (x = cx + r sin b, z = cz + r cos b), and as |z| off the centre line.
	local function crossingAt(x: number): (number, number)
		local b = math.deg(math.asin(math.clamp((x - L.cx) / rw, -1, 1)))
		return b, math.sqrt(math.max(0, rw * rw - (x - L.cx) ^ 2))
	end
	local w, westZ = crossingAt(layer.westX) -- w is negative: the west crossings are NW and SW

	-- THE ARC. With no east mouth it runs the long way round through due east (b = 90)
	-- between the two west crossings. With one it is two arcs, north and south, each
	-- from a west crossing to the matching east one. Columns are sized to a WALL_TILE
	-- chord and centred on the TRUE chord midpoint, so neighbours share exact corners.
	local arcs: { { number } } = {}
	local eastZ = 0
	if layer.eastX then
		local e
		e, eastZ = crossingAt(layer.eastX)
		table.insert(arcs, { w, e }) -- north, through b = 0
		table.insert(arcs, { 180 - e, 180 - w }) -- south, through b = 180
	else
		table.insert(arcs, { w, 180 - w })
	end

	local ix = 0 -- counts on across both arcs, so the checker and the bushes never restart
	for _, arc in arcs do
		local startB, total = arc[1], arc[2] - arc[1]
		local cols = math.max(1, math.ceil(total / math.deg(WALL_TILE / rw)))
		for i = 0, cols - 1 do
			local a0 = startB + i * (total / cols)
			local a1 = startB + (i + 1) * (total / cols)
			local aMid = math.rad((a0 + a1) / 2)
			local half = math.rad(a1 - a0) / 2
			local chord = 2 * rw * math.sin(half)
			local rMid = rw * math.cos(half)
			local origin = CFrame.new(L.cx + rMid * math.sin(aMid), 0, L.cz + rMid * math.cos(aMid)) * CFrame.Angles(0, aMid, 0)
			-- Local -Z points at the centre; its world direction, for the lip's nudge.
			wallColumn(folder, origin, chord, layer.height, ix, p, layer.salt, "FrontSurface", Vector3.new(0, 0, -1))

			for cell = 0, 1 do
				local rCell = rMid + (if cell == 0 then -WALL_TILE / 2 else WALL_TILE / 2)
				local reachIn = if cell == 0 then LIP_OVERHANG else 0
				local cellOrigin = CFrame.new(L.cx + rCell * math.sin(aMid), 0, L.cz + rCell * math.cos(aMid)) * CFrame.Angles(0, aMid, 0)
				local cap = build(folder, cellOrigin, {
					name = "WallCap",
					pos = { 0, capY, -reachIn / 2 },
					size = { chord, CAP_T, WALL_TILE + reachIn },
					color = if (ix + cell) % 2 == 0 then p.lipDark else p.lipLight,
					material = "Plastic",
					studs = true,
					canCollide = false,
				})
				cap.CanQuery = false
			end

			if ix % CROWN_BUSH_EVERY == 2 and hash01(ix, layer.salt + 18) < CROWN_BUSH_CHANCE then
				local bx, bz = L.cx + rMid * math.sin(aMid), L.cz + rMid * math.cos(aMid)
				bush(folder, bx, FLOOR_Y + layer.height + CAP_T - 0.1, bz, p, ix + layer.salt * 1000)
			end
			ix += 1
		end
	end

	-- THE SHOULDERS: short straight runs along z at each clip line, from the corridor
	-- side out to where the arc ends, each studded on the face the camp sees -- +X
	-- (RightSurface) on the west, -X (LeftSurface) on the east. A one-stud overlap into
	-- the arc, for the same reason Scenery's shoulders overlap the corridor: an
	-- exactly-touching seam between two computed edges is the one that opens first
	-- when either number moves.
	buildShoulders(folder, L, layer, layer.westX, layer.westFrom, westZ + 1, "RightSurface", Vector3.new(1, 0, 0), layer.salt + 6)
	local eastX = layer.eastX
	if eastX then
		buildShoulders(folder, L, layer, eastX, layer.eastFrom, eastZ + 1, "LeftSurface", Vector3.new(-1, 0, 0), layer.salt + 12)
	end

	folder.Parent = parent
end

--- Both wall layers, the Base Camp arrangement (Scenery buildBaseWalls). The inner one
--- is the original ring: inner face on the floor's edge, shoulders standing wholly on
--- the camp side of each clip line, starting at the corridor's inner edge. The outer
--- one is the same pieces grown one wall-thickness outward all round -- inner face on
--- the inner ring's outer face, shoulders flush behind the inner shoulders (so just
--- PAST each clip line) -- and OUTER_WALL_H tall. On the west its shoulders start at
--- the Crater's corridor wall's outer face, since that wall fills the slot between;
--- on the east there is no corridor wall until the next stage is built, so they run
--- in to the mouth's edge, and leave that slot to the corridor wall once it exists.
local function buildWalls(parent: Instance, L: Layout)
	local h = L.corridorHalfZ
	local exitX = L.exitX
	local layers: { WallLayer } = {
		{
			name = "Wall",
			radius = L.radius + WALL_T / 2,
			westX = L.clipX + WALL_T / 2,
			eastX = if exitX then exitX - WALL_T / 2 else nil,
			height = WALL_H,
			westFrom = h,
			eastFrom = h,
			salt = 11,
		},
		{
			name = "OuterWall",
			radius = L.radius + WALL_T * 1.5,
			westX = L.clipX - WALL_T / 2,
			eastX = if exitX then exitX + WALL_T / 2 else nil,
			height = OUTER_WALL_H,
			westFrom = h + WALL_T - 1,
			eastFrom = if L.nextBuilt then h + WALL_T - 1 else h,
			salt = 23,
		},
	}
	for _, layer in layers do
		buildWallLayer(parent, L, layer)
	end
end

--- Across the east mouth until the next stage exists: a run of hazard-striped rails
--- on posts with a COMING SOON board over the middle, and behind it an invisible
--- collider the height of the wall. All of it stands on the camp's floor, facing west.
local function buildGate(parent: Instance, L: Layout)
	local exitX = L.exitX
	if exitX == nil or L.nextBuilt then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "ExitGate"
	local h = L.corridorHalfZ
	local x = exitX - SEAM_WIDTH / 2 -- on the tape

	local posts = math.ceil(2 * h / GATE_POST_EVERY)
	for i = 0, posts do
		build(folder, CFrame.new(0, 0, 0), {
			name = "GatePost",
			pos = { x, PLAZA_Y + GATE_POST_H / 2, L.cz - h + 2 * h * i / posts },
			size = { 1.2, GATE_POST_H, 1.2 },
			color = C.hazardBlack,
			material = "SmoothPlastic",
		})
	end
	-- The rails, in yellow/black blocks a tile long, offset one block between the two.
	local cells = math.ceil(2 * h / WALL_TILE)
	for r, y in GATE_RAIL_Y do
		for iz = 0, cells - 1 do
			local z0 = -h + iz * WALL_TILE
			local z1 = math.min(z0 + WALL_TILE, h)
			build(folder, CFrame.new(0, 0, 0), {
				name = "GateRail",
				pos = { x, PLAZA_Y + y, L.cz + (z0 + z1) / 2 },
				size = { 0.8, 1, z1 - z0 },
				color = if (iz + r) % 2 == 0 then C.barrelYellow else C.hazardBlack,
				material = "SmoothPlastic",
			})
		end
	end
	-- The board, on two legs of its own.
	for _, dz in { -GATE_SIGN_W / 2 + 3, GATE_SIGN_W / 2 - 3 } do
		build(folder, CFrame.new(0, 0, 0), {
			name = "GateSignLeg",
			pos = { x + 0.2, PLAZA_Y + GATE_SIGN_Y / 2, L.cz + dz },
			size = { 1, GATE_SIGN_Y, 1 },
			color = C.hazardBlack,
			material = "SmoothPlastic",
		})
	end
	local board = build(folder, CFrame.new(0, 0, 0), {
		name = "GateSign",
		pos = { x - 0.4, PLAZA_Y + GATE_SIGN_Y + GATE_SIGN_H / 2, L.cz },
		size = { 0.6, GATE_SIGN_H, GATE_SIGN_W },
		color = L.palette.wallDark,
		material = "SmoothPlastic",
	})
	Kit.surfaceText(board, Enum.NormalId.Left, GATE_TEXT, C.barrelYellow)

	local block = build(folder, CFrame.new(0, 0, 0), {
		name = "GateCollider",
		pos = { exitX - 0.5, FLOOR_Y + WALL_H / 2, L.cz },
		size = { 1, WALL_H, 2 * h },
		color = C.hazardBlack,
		material = "SmoothPlastic",
		transparency = 1,
	})
	block.CanQuery = false
	block.CanTouch = false
	folder.Parent = parent
end

-- ── What stands on it ─────────────────────────────────────────────────────────

local function buildStalls(parent: Instance, L: Layout)
	local folder = Instance.new("Folder")
	folder.Name = "Stalls"
	local accents = L.palette.awnings
	local i = 0
	local function stall(dx: number, dz: number, yaw: number)
		i += 1
		local origin = CFrame.new(L.ox + dx, PLAZA_Y, L.oz + dz) * CFrame.Angles(0, math.rad(yaw), 0)
		Shops.buildStallShell(folder, origin, STALL_WIDTH, accents[(i - 1) % #accents + 1], STALL_LABEL)
	end
	-- North row faces south (yaw 180), south row faces north (yaw 0), across the aisle.
	--
	-- THE NORTH ROW IS THE DETECTOR SHOP, when Config/Gear sells any detector rung at this
	-- camp (`camp` on the row). It is one stall where two shells stood: a ladder of six
	-- makes a stall ~37 studs wide (Shops.campStallWidth), and the two shells' 24-stud
	-- slots (NORTH_STALL_X) only hold ~54 between them, so it takes both and stands at the
	-- row's middle. A camp Config/Gear sells nothing at keeps its shells.
	if #Gear.tiersAt("Detector", L.def.key) > 0 then
		local origin = CFrame.new(L.ox, PLAZA_Y, L.oz + ROW_Z) * CFrame.Angles(0, math.rad(180), 0)
		Shops.buildCampStall(folder, origin, "Detector", L.def.key)
		-- The two shells it replaced would have taken the first two awnings; skip them so
		-- the south row keeps the colours it had.
		i += #NORTH_STALL_X
	else
		for _, dx in NORTH_STALL_X do
			stall(dx, ROW_Z, 180)
		end
	end
	for _, dx in SOUTH_STALL_X do
		stall(dx, -ROW_Z, 0)
	end
	folder.Parent = parent

	-- The kiosk's frame is the camp datum, 0.9 above the unlifted floor (see
	-- BaseCamp.buildTrader); unrotated, so its counter faces north across the aisle.
	BaseCamp.buildTrader(parent, CFrame.new(L.ox, FLOOR_Y + 0.9, L.oz + TRADER_Z))
end

local function buildWashDeck(parent: Instance, L: Layout)
	local p = L.palette
	local deckTop = Plots.PAD.topY
	local rect: Hub.Rect = {
		minX = L.ox - DECK_HALF_X,
		maxX = L.ox + DECK_HALF_X,
		minZ = L.oz + DECK_MIN_Z,
		maxZ = L.oz + DECK_MAX_Z,
	}
	local tint: Hub.TileOpts = { topY = deckTop, dark = p.deck, light = lighter(p.deck, 0.06) }
	local deck = Instance.new("Model")
	deck.Name = "WashDeck"
	Hub.groundSlab(deck, rect, "Deck", DECK_THICKNESS, tint)
	local tiles = Instance.new("Folder")
	tiles.Name = "DeckTiles"
	Hub.tileRect(tiles, rect, tint)
	tiles.Parent = deck
	deck.Parent = parent

	-- The station is authored in a plot's frame: its bay lands at plotOrigin * (26, 0,
	-- -32), turned a quarter-turn (Plots.buildCleansingStation). This origin undoes both,
	-- so the bay sits at BAY_Z, unturned: the tub north, WashSpot 6 south of it facing
	-- north, i.e. the player walks up from the plaza. Y is the plot convention (0 = the
	-- pad top's frame), which is what Plots.PAD.topY already is.
	local bay = CFrame.new(L.ox, 0, L.oz + BAY_Z)
	Plots.buildCleansingStation(parent, bay * CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(-26, 0, 32), p.awnings[1])
end

--- Where WarpService puts you: the middle of the aisle between the two stall rows.
local function buildAnchor(parent: Instance, L: Layout)
	local anchor = build(parent, CFrame.new(0, 0, 0), {
		name = CampSite.ANCHOR_NAME,
		pos = { L.ox, PLAZA_Y + 0.5, L.oz },
		size = { 4, 1, 4 },
		color = C.cyan,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		attributes = { CampId = L.def.id, CampKey = L.def.key },
	})
	anchor.CanQuery = false
	anchor.CanTouch = false
end

local function buildFoliage(parent: Instance, L: Layout)
	local folder = Instance.new("Folder")
	folder.Name = "Foliage"
	local limit = L.radius - BUSH_WALL_CLEARANCE
	local n = math.ceil(L.radius / BUSH_CELL)
	for gx = -n, n do
		for gz = -n, n do
			local seed = (gx + 100) * 1000 + (gz + 100)
			if hash01(seed, 41) >= BUSH_CHANCE then
				continue
			end
			local x = L.cx + (gx + (hash01(seed, 43) - 0.5) * 0.8) * BUSH_CELL
			local z = L.cz + (gz + (hash01(seed, 47) - 0.5) * 0.8) * BUSH_CELL
			local dx, dz = x - L.cx, z - L.cz
			if dx * dx + dz * dz > limit * limit or x < L.clipX + BUSH_WALL_CLEARANCE then
				continue
			end
			-- Off the paving and its edge, off the deck, and out of the corridor mouth.
			if paved(L, x, z) or paved(L, x + 6, z) or paved(L, x - 6, z) or paved(L, x, z + 6) or paved(L, x, z - 6) then
				continue
			end
			if math.abs(x - L.ox) <= DECK_HALF_X + 6 and z >= L.oz + DECK_MIN_Z - 6 and z <= L.oz + DECK_MAX_Z + 6 then
				continue
			end
			bush(folder, x, FLOOR_Y, z, L.palette, seed)
		end
	end
	folder.Parent = parent
end

-- ── Entry points ──────────────────────────────────────────────────────────────

local function buildCamp(parent: Instance, def: Camps.CampDef)
	local L = layoutOf(def)
	local m = Instance.new("Model")
	-- "Twilight", not "twilight": a readable Explorer name; CampKey carries the wire spelling.
	m.Name = def.key:sub(1, 1):upper() .. def.key:sub(2)
	m:SetAttribute("CampId", def.id)
	m:SetAttribute("CampKey", def.key)

	buildFloor(m, L)
	buildSeam(m, L, "Seam", L.clipX - SEAM_WIDTH / 2)
	if L.exitX then
		buildSeam(m, L, "ExitSeam", if L.nextBuilt then L.exitX - SEAM_WIDTH / 2 else L.exitX - SEAM_WIDTH)
	end
	buildWalls(m, L)
	buildGate(m, L)
	buildStalls(m, L)
	buildWashDeck(m, L)
	buildAnchor(m, L)
	buildFoliage(m, L)

	-- Nothing in a camp may claim to be a stage -- same invariant Scenery asserts.
	for _, d in m:GetDescendants() do
		assert(d:GetAttribute("StageId") == nil, `camp part {d:GetFullName()} carries a StageId — it would register as a stage`)
	end

	m.Parent = parent
end

local function createCamps(): Model
	local root = Instance.new("Model")
	root.Name = CampSite.MODEL_NAME
	Kit.stamp(root, BUILDER_SOURCE, BUILDER_VERSION)
	for _, def in Camps.sites() do
		buildCamp(root, def)
	end
	return root
end

function CampSite.build(parent: Instance?): Model
	local root = createCamps()
	root.Parent = parent or Workspace
	return root
end

function CampSite.rebuild(parent: Instance?): Model
	local root = Kit.swap(CampSite.MODEL_NAME, createCamps, parent) :: Model
	print(`[build] Camps rebuilt — {#root:GetChildren()} site camp(s), {#root:GetDescendants()} descendants`)
	return root
end

return CampSite
