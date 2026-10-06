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
	Twilight's north-west slot is the Detector Shop (Shops.buildCampStall), selling that camp's
	six detectors, the south-west slot is its Magnet Shop, selling its five magnets, and
	the south-east slot is its Hose Shop, selling its five hoses, and its Aura Shop (the
	Outfitter's building, Shops.buildCampOutfitter) stands in the north-east slot, east of
	the Detector Shop, selling its five auras. Every other stall is Shops.buildStallShell -- the frame and steel roof
	with NO station attributes -- because the gear they will sell does not exist yet. They
	say COMING SOON rather than opening a panel for nothing.

	A COMING SOON CAMP (Config/Camps `comingSoon`, Zone 3 past Stage 12) is the same
	formation with nothing working in it: every stall a shell, no trader kiosk, an empty
	wash deck and no CampAnchor (so CampService offers no warp to it). A barricade with
	an invisible collider stands across its ENTRANCE, so it is seen and never entered.

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
	(Scenery.buildCampWallLayer) is written against Plots.CAMP's outline and the camp-green
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
	    ...<Key>.Stalls.MagnetShop    the same, in the south-west slot, where Gear sells
	                                  magnet rungs at this camp
	    ...<Key>.Stalls.CleanerShop   the same, in the south-east slot, for hose rungs
	    ...<Key>.Stalls.AuraShop      its Aura counter carries StationId "Aura" and
	                                  ShopCamp = <Key>; east of the Detector Shop
	    ...<Key>.MergeReactor         StationKind = "merge", StationId = <Key>, on the
	                                  MergeDeck south of the plaza; only where Config/Camps
	                                  sets `mergeReactor`
	    ...<Key>.ReforgeStation       StationKind = "reforge", StationId = <Key>, on the
	                                  north deck where the cleansing station stands
	                                  elsewhere; only where Config/Camps sets `reforge`.
	                                  The cleansing station then moves to the WashYard
	                                  deck north-west of the plaza, on a spur off the
	                                  entry path, so you wash right as you come in.
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
local MergeReactor = require(script.Parent.MergeReactor)
local ReforgeStation = require(script.Parent.ReforgeStation)

local CampSite = {}
CampSite.MODEL_NAME = Camps.MODEL_NAME
CampSite.ANCHOR_NAME = Camps.ANCHOR_NAME
local BUILDER_SOURCE = "src/server/build/CampSite.luau"
local BUILDER_VERSION = 33

local C = Kit.C
local build = Kit.build

-- ── Layout ────────────────────────────────────────────────────────────────────

local TILE = Hub.TILE_SIZE
local FLOOR_Y = Stages.SURFACE_Y -- the lawn; flush with the stage it opens off
-- Rows of wall sunk BELOW the surface, so the wall's foot reaches the underside of the
-- ground slabs (stage plates bottom out 16 studs down) and seen from outside the map the
-- wall hides the slab edge instead of the ground overhanging a floating wall.
local WALL_FOOT_ROWS = 4
local PLAZA_Y = FLOOR_Y + Hub.PLAZA_LIFT -- the octagon, its paths and the shop square

--- The structural body under the tiles, laid as thin bands clipped to the disc (a
--- Cylinder would be a true circle but cannot be cut off at the clip line, and the
--- sliver west of it would hang out past the stage's corridor wall).
local SLAB_THICKNESS = 8
local SLAB_BAND = 2

--- The octagon, from the plaza centre. HALF is 4k + 2 and DIAG a multiple of 4 -- the
--- same rule Hub's own octagon follows (see PLAZA_OCT_* there), so the axis sides fall
--- on tile lines and the diagonals run corner to corner through the cells they cut.
--- 110 * sqrt 2 = 155.6, so 156 is near-regular. Grown from 70 on request.
local OCT_HALF = 110
local OCT_DIAG = 156

--- Half-width of the gate paths: in from the stage on the west, and north up to the
--- wash deck. 10 either side of centre lands both edges on tile lines.
local PATH_HALF = 10

--- The paver square, from the plaza centre. Both edges on tile lines; a half-tile kerb (buildKerb).
--- Grown from 42 x 38 on request, then trimmed a little from 78.
local SHOP_HALF_X, SHOP_HALF_Z = 66, 66

--- The trader stands at the square's middle with the four shops pinwheeled around it on
--- the diagonals, each facing the kiosk (buildStalls). Slot order = SLOT_ANGLES order;
--- angles are compass bearings off +Z (north), clockwise toward +X (east).
--- Aura and Detector swapped places on request (Detector NW, Aura NE).
local SLOT_TRACKS = { "Detector", "Aura", "Cleaner", "Magnet" }
local SLOT_ANGLES = { -45, 45, 135, -135 } -- NW, NE, SE, SW
--- Ring radius = widest shop's half-width + this, so neighbours' front corners never meet.
--- Was 28. Trimmed when the Aura Shop grew to six mannequins (Seraph, Crimson Vortex):
--- at 28 its back corner ran 1.5 past the paver square. The ring still sits ~3 further
--- out than it did, so every aisle is wider than before.
local RING_AISLE = 25
local STALL_WIDTH = 24
local STALL_LABEL = "COMING SOON"
--- How far west of the kiosk a warp lands you.
local ANCHOR_WEST = 70

--- The wash deck, north of the octagon, one plot-pad step (1.5) above the lawn so the
--- cleansing station stands at the height it was built for (Plots.PAD.topY). The bay
--- sits far enough back that WashService's big-lump stand-off (up to ~14 in front of
--- the tub) still lands the player on the deck.
local DECK_HALF_X = 22
local DECK_MIN_Z, DECK_MAX_Z = 114, 146
local DECK_THICKNESS = 3
local BAY_Z = 134

--- The Merge Reactor's deck, the wash deck's mirror image south of the octagon, on a
--- south path of its own. The machine stands at the deck's back half facing north, so
--- the reach of its E (MergeReactor.RADIUS) is all on the deck in front of it.
local MERGE_DECK_HALF_X = 18
local MERGE_DECK_MIN_Z, MERGE_DECK_MAX_Z = 114, 146
local MERGE_Z = 134

--- WHERE THE CLEANSING STATION GOES WHEN THE REFORGE STATION TAKES THE NORTH DECK
--- (Config/Camps `reforge`): its own deck, the wash deck's size, north-west of the
--- octagon, clear of its diagonal side. A paved spur runs north to it off the west
--- entry path, so a player coming in dirty from the stage washes before the plaza.
--- Every edge is ox/oz + (2 mod 4), on a tile line; the bay keeps the wash deck's
--- 20 studs of deck in front of the tub for WashService's stand-off.
local YARD_MIN_X, YARD_MAX_X = -146, -102
local YARD_MIN_Z, YARD_MAX_Z = 94, 126
local YARD_BAY_X, YARD_BAY_Z = -124, 114
local SPUR_MIN_X, SPUR_MAX_X = -134, -114

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
--- Kit.surfaceText draws at 50 px/stud and TextScaled stops at 100 px, so its text can
--- never stand taller than 2 studs -- a whisper on a 7-stud board. Fewer pixels per
--- stud lets the same cap fill it.
local GATE_TEXT_PPS = 22
--- A COMING SOON camp's barricade stands across its ENTRANCE instead (Camps.comingSoon):
--- just past the tape on the camp's floor, its collider a step behind the rails.
local ENTRY_GATE_INSET = 2

--- THE PLAZA'S OUTLINE AND THE SHOP KERB ARE PAINT, laid a hair above the paving (like
--- Hub's FloorEndBorder): not collidable, not queried, studded on top.
---
--- The kerb was one whole tile (4 studs) of kerb colour round the shop square; on
--- request it is half that, so the kerb cells are pavers (pairAt) and four 2-stud strips
--- cover their outer half. Four parts instead of a tile per cell.
---
--- The black border, on request ("a thin black stud border around the hexagons and
--- path"): a 1-stud line along the inside of every edge where the octagon and its paths
--- meet the lawn, gapped where a path joins the octagon. Path ends stop at the clip
--- lines and deck edges, which already draw their own edge.
local BORDER_W = 1
local KERB_W = TILE / 2
local PAINT_RAISE = 0.05
--- The octagon's diagonal lines sit lower than the straight ones: a smooth underlay the
--- edge's full length, and over it a studded strip a whole number of studs long that
--- stops short of each corner. Their ends tuck under the axis lines, so only one stud
--- texture draws at a joint (at one height they z-fought) and no stud is cut in half.
local DIAGONAL_DROP = 0.02
local UNDERLAY_DROP = 0.03

local function paint(
	parent: Instance,
	name: string,
	cx: number,
	cz: number,
	len: number,
	w: number,
	yaw: number,
	color: string,
	drop: number?,
	smooth: boolean?
)
	local part = build(parent, CFrame.new(0, 0, 0), {
		name = name,
		pos = { cx, PLAZA_Y + PAINT_RAISE - (drop or 0) - Hub.TILE_CAP / 2, cz },
		size = { len, Hub.TILE_CAP, w },
		rot = CFrame.Angles(0, yaw, 0),
		color = color,
		material = "Plastic",
		canCollide = false,
	})
	part.TopSurface = if smooth then Enum.SurfaceType.Smooth else Enum.SurfaceType.Studs
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function buildKerb(parent: Instance, L: Layout)
	local hx, hz = SHOP_HALF_X, SHOP_HALF_Z
	for _, s in { -1, 1 } do
		-- North/south strips run the full width; east/west fit between them.
		paint(parent, "Kerb", L.ox, L.oz + s * (hz - KERB_W / 2), 2 * hx, KERB_W, 0, L.palette.kerb)
		paint(parent, "Kerb", L.ox + s * (hx - KERB_W / 2), L.oz, 2 * (hz - KERB_W), KERB_W, math.pi / 2, L.palette.kerb)
	end
end

local function buildBorder(parent: Instance, L: Layout)
	local folder = Instance.new("Folder")
	folder.Name = "PlazaBorder"
	local w = BORDER_W
	local black = C.hazardBlack

	-- A line along X (z fixed) from local x0 to x1, its outer edge on `edgeZ`, `inward`
	-- the sign toward the paving. `alongZ` swaps the axes for a line along Z.
	local function alongX(x0: number, x1: number, edgeZ: number, inward: number)
		if x1 - x0 > 1e-3 then
			paint(folder, "Border", L.ox + (x0 + x1) / 2, L.oz + edgeZ + inward * w / 2, x1 - x0, w, 0, black)
		end
	end
	local function alongZ(z0: number, z1: number, edgeX: number, inward: number)
		if z1 - z0 > 1e-3 then
			paint(folder, "Border", L.ox + edgeX + inward * w / 2, L.oz + (z0 + z1) / 2, z1 - z0, w, math.pi / 2, black)
		end
	end

	-- Which octagon sides a path leaves through (local axis sign pairs).
	local west, east = true, L.exitX ~= nil
	local north, south = true, L.def.mergeReactor == true
	local t = OCT_DIAG - OCT_HALF -- the axis sides' half-length
	local function side(open: boolean, run: (number, number) -> ())
		if open then
			run(-t, -PATH_HALF)
			run(PATH_HALF, t)
		else
			run(-t, t)
		end
	end
	side(west, function(a, b)
		alongZ(a, b, -OCT_HALF, 1)
	end)
	side(east, function(a, b)
		alongZ(a, b, OCT_HALF, -1)
	end)
	side(north, function(a, b)
		alongX(a, b, OCT_HALF, -1)
	end)
	side(south, function(a, b)
		alongX(a, b, -OCT_HALF, 1)
	end)

	-- The four diagonals, inset w/2 along their inward normal. The underlay is exactly
	-- the edge's length: each end's outer corner is the octagon's vertex and its inner
	-- corner falls inside the axis line, which covers it. Any longer and the tip pokes
	-- out past the vertex onto the lawn. The studded strip on it is the largest even
	-- stud count that leaves a stud of smooth black at each end.
	local len = (OCT_HALF - t) * math.sqrt(2)
	local studded = 2 * math.floor((len - 2 * w) / 2)
	local mid = (OCT_HALF + t) / 2 - w / (2 * math.sqrt(2))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			-- Runs along (sx, -sz): a yaw of θ turns local +X onto (cos θ, -sin θ).
			local x, z, yaw = L.ox + sx * mid, L.oz + sz * mid, math.atan2(sz, sx)
			paint(folder, "BorderUnderlay", x, z, len, w, yaw, black, UNDERLAY_DROP, true)
			paint(folder, "Border", x, z, studded, w, yaw, black, DIAGONAL_DROP)
		end
	end

	-- The paths' long sides, from their far end to one stud inside the octagon edge (to
	-- fill the inside corner where the octagon's own line stops).
	local inner = OCT_HALF - w
	local clipW, exitE = L.clipX - L.ox, if L.exitX then L.exitX - L.ox else nil
	-- West: broken by the wash-yard spur where there is one.
	if L.def.reforge then
		alongX(clipW, SPUR_MIN_X, PATH_HALF, -1)
		alongX(SPUR_MAX_X, -inner, PATH_HALF, -1)
		alongZ(PATH_HALF - w, YARD_MIN_Z, SPUR_MIN_X, 1)
		alongZ(PATH_HALF - w, YARD_MIN_Z, SPUR_MAX_X, -1)
	else
		alongX(clipW, -inner, PATH_HALF, -1)
	end
	alongX(clipW, -inner, -PATH_HALF, 1)
	if exitE then
		alongX(inner, exitE, PATH_HALF, -1)
		alongX(inner, exitE, -PATH_HALF, 1)
	end
	alongZ(inner, DECK_MIN_Z, -PATH_HALF, 1)
	alongZ(inner, DECK_MIN_Z, PATH_HALF, -1)
	if south then
		alongZ(-MERGE_DECK_MIN_Z, -inner, -PATH_HALF, 1)
		alongZ(-MERGE_DECK_MIN_Z, -inner, PATH_HALF, -1)
	end

	folder.Parent = parent
end

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

--- The face opposite each studded face: walls are seen from both sides (the corridor
--- from inside, the fields and void from outside), so the back gets studs too.
local OPPOSITE_FACE = {
	FrontSurface = "BackSurface",
	BackSurface = "FrontSurface",
	LeftSurface = "RightSurface",
	RightSurface = "LeftSurface",
}

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
	-- South, down to (and on under) the Merge Reactor's deck.
	if L.def.mergeReactor and ax <= PATH_HALF and z <= L.oz and z >= L.oz - MERGE_DECK_MIN_Z - TILE then
		return true
	end
	-- North off the west path, up to (and on under) the wash yard.
	local dx = x - L.ox
	if L.def.reforge and dx >= SPUR_MIN_X and dx <= SPUR_MAX_X and z >= L.oz and z <= L.oz + YARD_MIN_Z + TILE then
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
			-- The kerb ring is paver too; buildKerb lays the half-tile kerb over its outer half.
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
	for row = -WALL_FOOT_ROWS, rows - 1 do
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
		(tile :: any)[face] = Enum.SurfaceType.Studs;
		(tile :: any)[OPPOSITE_FACE[face]] = Enum.SurfaceType.Studs
	end
end

--- PART BUDGET: a strip of wall columns as checker-material blocks (Kit.materialWall)
--- instead of a part per cell. `frameAt(s)` has local X along the strip and local Z its
--- thickness axis; `face` is the visible face in that frame (Front/Back); `columns`
--- are { s0, s1, col } ascending, `col` the index lipRowsOf and the checker read.
--- Returns the indices of columns whose pair has no material, for wallColumn instead.
local function materialWallStrip(folder: Instance, frameAt: (number) -> CFrame, face: string, columns: { { number } }, height: number, p: Camps.Palette, salt: number): { number }
	local rows = math.ceil(height / WALL_TILE)
	return Kit.materialWall(folder, {
		name = "Wall",
		frameAt = frameAt,
		face = face,
		columns = columns,
		baseY = FLOOR_Y,
		footRows = WALL_FOOT_ROWS,
		rows = rows,
		tile = WALL_TILE,
		thick = WALL_T,
		overhang = LIP_OVERHANG,
		pairAt = function(col: number, row: number)
			if row >= rows - lipRowsOf(col, salt) then
				return p.lipDark, p.lipLight, true
			end
			return p.wallDark, p.wallLight, false
		end,
	})
end

--- A crown strip on the checker material, two cells deep from local -Z, `reach` the
--- signed lip overhang along local Z; columns { s0, s1, ix } with (ix + cell) parity.
--- Columns Kit.materialCrown sheds (or all of them, if the lip pair has no material)
--- go down as the old studded cell parts.
local function materialCrownStrip(folder: Instance, frameAt: (number) -> CFrame, columns: { { number } }, capY: number, reach: number, p: Camps.Palette)
	local shed = Kit.materialCrown(folder, {
		name = "WallCap",
		frameAt = frameAt,
		columns = columns,
		z0 = -WALL_T / 2 + math.min(reach, 0),
		z1 = WALL_T / 2 + math.max(reach, 0),
		y = capY,
		thick = CAP_T,
		pairAt = function()
			return p.lipDark, p.lipLight
		end,
	})
	for _, i in shed do
		local c = columns[i]
		for cell = 0, 1 do
			local z0 = -WALL_T / 2 + cell * WALL_TILE
			local z1 = z0 + WALL_TILE
			if reach > 0 and cell == 1 then
				z1 += reach
			elseif reach < 0 and cell == 0 then
				z0 += reach
			end
			local cap = build(folder, frameAt((c[1] + c[2]) / 2), {
				name = "WallCap",
				pos = { 0, capY, (z0 + z1) / 2 },
				size = { c[2] - c[1], CAP_T, z1 - z0 },
				color = if (c[3] + cell) % 2 == 0 then p.lipDark else p.lipLight,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
			cap.CanQuery = false
		end
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
	-- Yawed 90 degrees so local X runs along z: world Left/Right (the faces a shoulder
	-- shows the camp) are the frame's Front/Back, and local +Z is world +X.
	local localFace = if face == "LeftSurface" then "FrontSurface" else "BackSurface"
	local function frameAt(z: number): CFrame
		return CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(90), 0)
	end
	for _, sign in { -1, 1 } do
		local walls: { { number } } = {}
		local crowns: { { number } } = {}
		for iz = 0, n - 1 do
			local a = z0 + (z1 - z0) * iz / n
			local b = z0 + (z1 - z0) * (iz + 1) / n
			local lo, hi = L.cz + sign * a, L.cz + sign * b
			if lo > hi then
				lo, hi = hi, lo
			end
			table.insert(walls, { lo, hi, 1000 + iz * sign })
			table.insert(crowns, { lo, hi, iz })
		end
		table.sort(walls, function(u, v)
			return u[1] < v[1]
		end)
		table.sort(crowns, function(u, v)
			return u[1] < v[1]
		end)
		for _, i in materialWallStrip(folder, frameAt, localFace, walls, layer.height, p, salt) do
			local c = walls[i]
			wallColumn(folder, CFrame.new(x, 0, (c[1] + c[2]) / 2), c[2] - c[1], layer.height, c[3], p, salt, face, inward)
		end
		-- Two cells across the crown; the camp-side one reaches out over the lip.
		materialCrownStrip(folder, frameAt, crowns, capY, inward.X * LIP_OVERHANG, p)
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
			local function columnFrame(): CFrame
				return origin
			end
			if #materialWallStrip(folder, columnFrame, "FrontSurface", { { -chord / 2, chord / 2, ix } }, layer.height, p, layer.salt) > 0 then
				wallColumn(folder, origin, chord, layer.height, ix, p, layer.salt, "FrontSurface", Vector3.new(0, 0, -1))
			end

			-- The crown: two radial cells, the inner one reaching over the lip (local -Z
			-- points at the centre).
			materialCrownStrip(folder, columnFrame, { { -chord / 2, chord / 2, ix } }, capY, -LIP_OVERHANG, p)

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
local function gateAt(parent: Instance, L: Layout, name: string, x: number, colliderX: number, text: string)
	local folder = Instance.new("Folder")
	folder.Name = name
	local h = L.corridorHalfZ

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
	local gui = Kit.surfaceText(board, Enum.NormalId.Left, text, C.barrelYellow).Parent :: SurfaceGui
	gui.PixelsPerStud = GATE_TEXT_PPS

	local block = build(folder, CFrame.new(0, 0, 0), {
		name = "GateCollider",
		pos = { colliderX, FLOOR_Y + WALL_H / 2, L.cz },
		size = { 1, WALL_H, 2 * h },
		color = C.hazardBlack,
		material = "SmoothPlastic",
		transparency = 1,
	})
	block.CanQuery = false
	block.CanTouch = false
	folder.Parent = parent
end

local function buildGate(parent: Instance, L: Layout)
	if L.def.comingSoon then
		local x = L.clipX + SEAM_WIDTH / 2
		gateAt(parent, L, "EntryGate", x + ENTRY_GATE_INSET, x + ENTRY_GATE_INSET + 1.5, `{string.upper(L.def.name)} · COMING SOON`)
	end
	local exitX = L.exitX
	if exitX == nil or L.nextBuilt then
		return
	end
	gateAt(parent, L, "ExitGate", exitX - SEAM_WIDTH / 2, exitX - 0.5, GATE_TEXT)
end

-- ── What stands on it ─────────────────────────────────────────────────────────

local function buildStalls(parent: Instance, L: Layout)
	local folder = Instance.new("Folder")
	folder.Name = "Stalls"
	local accents = L.palette.awnings

	-- THE PINWHEEL, ON REQUEST: the trader stands alone at the middle of the square and
	-- the four shops ring it on the diagonals, each turned to face the kiosk. A slot sells
	-- its track when Config/Gear sells any rung of it at this camp, else it is a shell.
	type Slot = { width: number, build: (origin: CFrame) -> () }
	local slots: { Slot } = {}
	for i, track in SLOT_TRACKS do
		local accent = accents[(i - 1) % #accents + 1]
		local shopColor = L.palette.shopColors and L.palette.shopColors[track]
		if #Gear.tiersAt(track, L.def.key) > 0 then
			if track == "Aura" then
				table.insert(slots, {
					width = Shops.campOutfitterWidth(L.def.key),
					build = function(origin)
						Shops.buildCampOutfitter(folder, origin, L.def.key, shopColor)
					end,
				})
			else
				table.insert(slots, {
					width = Shops.campStallWidth(track, L.def.key),
					build = function(origin)
						Shops.buildCampStall(folder, origin, track, L.def.key, shopColor)
					end,
				})
			end
		else
			table.insert(slots, {
				width = STALL_WIDTH,
				build = function(origin)
					Shops.buildStallShell(folder, origin, STALL_WIDTH, accent, STALL_LABEL)
				end,
			})
		end
	end

	-- One ring distance for all four, far enough out that the widest shop's front corners
	-- clear its neighbours' and the kiosk with an aisle to spare.
	local widest = 0
	for _, slot in slots do
		widest = math.max(widest, slot.width)
	end
	local ring = widest / 2 + RING_AISLE
	for i, slot in slots do
		local angle = math.rad(SLOT_ANGLES[i])
		local dx, dz = math.sin(angle) * ring, math.cos(angle) * ring
		-- A shop's customer side is local +Z; turn it to point back at the kiosk.
		local yaw = math.atan2(-dx, -dz)
		local reach = (slot.width / 2 + 12) / math.sqrt(2) + math.abs(dx)
		assert(reach <= SHOP_HALF_X, `{L.def.key}'s {SLOT_TRACKS[i]} shop runs off the paver square ({reach})`)
		slot.build(CFrame.new(L.ox + dx, PLAZA_Y, L.oz + dz) * CFrame.Angles(0, yaw, 0))
	end
	folder.Parent = parent

	-- The kiosk's frame is the camp datum, 0.9 above the unlifted floor (see
	-- BaseCamp.buildHubTrader); dead centre. Base Camp's four-sided kiosk, on request, so
	-- it sells to every shop around it.
	if not L.def.comingSoon then
		BaseCamp.buildHubTrader(parent, CFrame.new(L.ox, FLOOR_Y + 0.9, L.oz))
	end
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
	if L.def.comingSoon then
		return -- the deck is the formation; the station is a working one, so not yet
	end
	if L.def.reforge then
		-- The forge takes the deck, turned to face the plaza (it is authored facing +Z),
		-- and the cleansing station moves to the wash yard.
		ReforgeStation.build(parent, CFrame.new(L.ox, deckTop, L.oz + BAY_Z) * CFrame.Angles(0, math.pi, 0), L.def.key)
		return
	end
	local bay = CFrame.new(L.ox, 0, L.oz + BAY_Z)
	Plots.buildCleansingStation(parent, bay * CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(-26, 0, 32), p.awnings[1])
end

--- The cleansing station's own deck when the forge has the north one (`reforge`).
local function buildWashYard(parent: Instance, L: Layout)
	if not L.def.reforge then
		return
	end
	local p = L.palette
	local deckTop = Plots.PAD.topY
	local rect: Hub.Rect = {
		minX = L.ox + YARD_MIN_X,
		maxX = L.ox + YARD_MAX_X,
		minZ = L.oz + YARD_MIN_Z,
		maxZ = L.oz + YARD_MAX_Z,
	}
	local tint: Hub.TileOpts = { topY = deckTop, dark = p.deck, light = lighter(p.deck, 0.06) }
	local deck = Instance.new("Model")
	deck.Name = "WashYard"
	Hub.groundSlab(deck, rect, "Deck", DECK_THICKNESS, tint)
	local tiles = Instance.new("Folder")
	tiles.Name = "DeckTiles"
	Hub.tileRect(tiles, rect, tint)
	tiles.Parent = deck
	deck.Parent = parent

	if L.def.comingSoon then
		return
	end
	-- Same frame trick as buildWashDeck: the bay unturned, tub north, the player
	-- walking up the spur from the south.
	local bay = CFrame.new(L.ox + YARD_BAY_X, 0, L.oz + YARD_BAY_Z)
	Plots.buildCleansingStation(parent, bay * CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(-26, 0, 32), p.awnings[1])
end

--- The Merge Reactor on its own deck, south of the octagon, facing the plaza.
local function buildMergeDeck(parent: Instance, L: Layout)
	if not L.def.mergeReactor then
		return
	end
	local p = L.palette
	local deckTop = Plots.PAD.topY
	local rect: Hub.Rect = {
		minX = L.ox - MERGE_DECK_HALF_X,
		maxX = L.ox + MERGE_DECK_HALF_X,
		minZ = L.oz - MERGE_DECK_MAX_Z,
		maxZ = L.oz - MERGE_DECK_MIN_Z,
	}
	local tint: Hub.TileOpts = { topY = deckTop, dark = p.deck, light = lighter(p.deck, 0.06) }
	local deck = Instance.new("Model")
	deck.Name = "MergeDeck"
	Hub.groundSlab(deck, rect, "Deck", DECK_THICKNESS, tint)
	local tiles = Instance.new("Folder")
	tiles.Name = "DeckTiles"
	Hub.tileRect(tiles, rect, tint)
	tiles.Parent = deck
	deck.Parent = parent

	-- Unrotated: the machine is authored facing +Z, which is north, up the path.
	MergeReactor.build(parent, CFrame.new(L.ox, deckTop, L.oz - MERGE_Z), L.def.key)
end

--- Where WarpService puts you: on the west path, between the plaza's west edge and the
--- pinwheel (the kiosk now owns the middle).
local function buildAnchor(parent: Instance, L: Layout)
	if L.def.comingSoon then
		return -- nowhere to warp to: CampService finds no anchor, so no warp row opens
	end
	local anchor = build(parent, CFrame.new(0, 0, 0), {
		name = CampSite.ANCHOR_NAME,
		pos = { L.ox - ANCHOR_WEST, PLAZA_Y + 0.5, L.oz },
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
			-- Nor past the east clip line: the round plaza's grid reaches over it, and the
			-- bushes that landed there stood in the next stage's first stretch (Stage 5 off
			-- Twilight, Stage 9 off Magma), a camp shrub on a field that isn't the camp.
			if L.exitX and x > L.exitX - BUSH_WALL_CLEARANCE then
				continue
			end
			-- Off the paving and its edge, off the deck, and out of the corridor mouth.
			if paved(L, x, z) or paved(L, x + 6, z) or paved(L, x - 6, z) or paved(L, x, z + 6) or paved(L, x, z - 6) then
				continue
			end
			if math.abs(x - L.ox) <= DECK_HALF_X + 6 and z >= L.oz + DECK_MIN_Z - 6 and z <= L.oz + DECK_MAX_Z + 6 then
				continue
			end
			if
				L.def.reforge
				and x - L.ox >= YARD_MIN_X - 6
				and x - L.ox <= YARD_MAX_X + 6
				and z >= L.oz + YARD_MIN_Z - 6
				and z <= L.oz + YARD_MAX_Z + 6
			then
				continue
			end
			if
				L.def.mergeReactor
				and math.abs(x - L.ox) <= MERGE_DECK_HALF_X + 6
				and z <= L.oz - MERGE_DECK_MIN_Z + 6
				and z >= L.oz - MERGE_DECK_MAX_Z - 6
			then
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
	buildKerb(m:FindFirstChild("Tiles") :: Instance, L)
	buildBorder(m, L)
	buildSeam(m, L, "Seam", L.clipX - SEAM_WIDTH / 2)
	if L.exitX then
		buildSeam(m, L, "ExitSeam", if L.nextBuilt then L.exitX - SEAM_WIDTH / 2 else L.exitX - SEAM_WIDTH)
	end
	buildWalls(m, L)
	buildGate(m, L)
	buildStalls(m, L)
	buildWashDeck(m, L)
	buildWashYard(m, L)
	buildMergeDeck(m, L)
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
