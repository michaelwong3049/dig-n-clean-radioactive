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
	sell at the counter, dock and shower at the tub, wash what you hold. The stalls are
	Shops.buildStallShell -- the frame and steel roof with NO station attributes -- because
	the gear they will sell does not exist yet. They say COMING SOON rather than opening
	a panel for nothing.

	ONE CAMP'S LAYOUT, RELATIVE TO ITS OWN PLAZA CENTRE. Config/Camps gives the disc
	(centre, radius, the clip line where the stage chain meets it) and the palette;
	everything on the disc is placed off `plazaCentre`, the grid cell nearest the disc's
	own centre, so every edge below lands on a tile line. Moving a camp is a Config
	change and a rebuild.

	              wall (closed east until Stage 7 exists)
	         .-'''''''''''''''''-.
	        /      [WASH DECK]    \          +Z ("north", this codebase's convention)
	  ====|         |path|         |
	 STAGE   .-''''''''''''''''-.  |
	   6  =  | [shell]  [shell] |  |
	 ======  |   (anchor)       |  |
	         | [shell][TRADER][shell]
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
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Camps = require(Shared.Config.Camps)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)
local Shops = require(script.Parent.Shops)
local BaseCamp = require(script.Parent.BaseCamp)
local Plots = require(script.Parent.Plots)

local CampSite = {}
CampSite.MODEL_NAME = Camps.MODEL_NAME
CampSite.ANCHOR_NAME = Camps.ANCHOR_NAME
local BUILDER_SOURCE = "src/server/build/CampSite.luau"
local BUILDER_VERSION = 4

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
local WALL_ROWS = math.ceil(WALL_H / WALL_TILE)
local CAP_T = 2
local LIP_OVERHANG = 0.5
local CROWN_BUSH_EVERY = 5
local CROWN_BUSH_CHANCE = 0.4

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
	ox: number, -- the plaza centre: the grid cell nearest the disc centre
	oz: number,
	corridorHalfZ: number, -- the stage chain's half-width, where it opens in
}

local function layoutOf(def: Camps.CampDef): Layout
	local center = def.center :: { number }
	local ox, oz = Hub.cellCentre(center[1], center[2])
	local corridorHalfZ = 0
	for _, id in Stages.builtIds() do
		local _, minZ, _, maxZ = Stages.bounds(id)
		corridorHalfZ = math.max(corridorHalfZ, -minZ, maxZ)
	end
	return {
		def = def,
		palette = def.palette :: Camps.Palette,
		cx = center[1],
		cz = center[2],
		radius = def.radius :: number,
		clipX = def.clipX :: number,
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

	local rect: Hub.Rect = { minX = L.clipX, maxX = L.cx + reach, minZ = L.cz - reach, maxZ = L.cz + reach }

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

	-- The body: thin bands under the tiles, each running from the clip line to the
	-- disc's edge (wall included) at its own z, so the island's cliff follows the
	-- circle rather than stepping out in big rectangles.
	local slab = Instance.new("Folder")
	slab.Name = "Slab"
	local outer = L.radius + WALL_T
	local topY = FLOOR_Y - 0.4 -- Hub's CAP: the slab is recessed by exactly the tile cap
	local z = L.cz - outer
	while z < L.cz + outer - 1e-3 do
		local z1 = math.min(z + SLAB_BAND, L.cz + outer)
		local mid = (z + z1) / 2 - L.cz
		local half = math.sqrt(math.max(0, outer * outer - mid * mid))
		local maxX = L.cx + half
		if maxX > L.clipX + 0.5 then
			build(slab, CFrame.new(0, 0, 0), {
				name = "Slab",
				pos = { (L.clipX + maxX) / 2, topY - SLAB_THICKNESS / 2, (z + z1) / 2 },
				size = { maxX - L.clipX, SLAB_THICKNESS, z1 - z },
				color = p.wallDark,
				material = "SmoothPlastic",
			})
		end
		z = z1
	end
	slab.Parent = parent
end

--- The hazard tape across the mouth of the stage corridor, centred on the clip line --
--- half on the stage's floor, half on the camp's, exactly like every stage seam.
local function buildSeam(parent: Instance, L: Layout)
	local folder = Instance.new("Folder")
	folder.Name = "Seam"
	local rowWidth = SEAM_WIDTH / SEAM_ROWS
	local x0 = L.clipX - SEAM_WIDTH / 2
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

--- One column of wall `width` wide at `origin`, whose local -Z faces the walkable side
--- (so `face` -- FrontSurface on an arc column, or whichever face the caller names --
--- carries the studs).
local function wallColumn(parent: Instance, origin: CFrame, width: number, col: number, p: Camps.Palette, salt: number, face: string, inward: Vector3)
	local lipRows = lipRowsOf(col, salt)
	for row = 0, WALL_ROWS - 1 do
		local y0 = FLOOR_Y + row * WALL_TILE
		local y1 = math.min(y0 + WALL_TILE, FLOOR_Y + WALL_H)
		local grassy = row >= WALL_ROWS - lipRows
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

local function buildWall(parent: Instance, L: Layout)
	local p = L.palette
	local folder = Instance.new("Folder")
	folder.Name = "Wall"

	local rw = L.radius + WALL_T / 2 -- the wall's centreline radius
	local shoulderX = L.clipX + WALL_T / 2 -- the shoulders stand wholly on the camp side
	local crossing = math.sqrt(math.max(0, rw * rw - (shoulderX - L.cx) ^ 2))

	-- THE ARC, in Scenery's bearing convention (x = cx + r sin b, z = cz + r cos b),
	-- the long way round through due east (b = 90) between the two points where the
	-- centreline circle crosses the shoulder line. Columns are sized to a WALL_TILE
	-- chord and centred on the TRUE chord midpoint, so neighbours share exact corners.
	local s = math.deg(math.asin(math.clamp((shoulderX - L.cx) / rw, -1, 1)))
	local startB, endB = s, 180 - s -- s is negative: the arc spans the east side
	local total = endB - startB
	local cols = math.max(1, math.ceil(total / math.deg(WALL_TILE / rw)))
	local capY = FLOOR_Y + WALL_H + CAP_T / 2 - 0.1
	for ix = 0, cols - 1 do
		local a0 = startB + ix * (total / cols)
		local a1 = startB + (ix + 1) * (total / cols)
		local aMid = math.rad((a0 + a1) / 2)
		local half = math.rad(a1 - a0) / 2
		local chord = 2 * rw * math.sin(half)
		local rMid = rw * math.cos(half)
		local origin = CFrame.new(L.cx + rMid * math.sin(aMid), 0, L.cz + rMid * math.cos(aMid)) * CFrame.Angles(0, aMid, 0)
		-- Local -Z points at the centre; its world direction, for the lip's nudge.
		wallColumn(folder, origin, chord, ix, p, 11, "FrontSurface", Vector3.new(0, 0, -1))

		for cell = 0, 1 do
			local rCell = rMid + (if cell == 0 then -WALL_TILE / 2 else WALL_TILE / 2)
			local reachIn = if cell == 0 then LIP_OVERHANG else 0
			local cap = build(folder, CFrame.new(L.cx + rCell * math.sin(aMid), 0, L.cz + rCell * math.cos(aMid)) * CFrame.Angles(0, aMid, 0), {
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

		if ix % CROWN_BUSH_EVERY == 2 and hash01(ix, 29) < CROWN_BUSH_CHANCE then
			bush(folder, L.cx + rMid * math.sin(aMid), FLOOR_Y + WALL_H + CAP_T - 0.1, L.cz + rMid * math.cos(aMid), p, ix)
		end
	end

	-- THE TWO SHOULDERS: short straight runs along z at shoulderX, from the stage
	-- corridor's own wall (its inner face at +-corridorHalfZ) out to where the arc ends.
	-- They face east, into the camp, so their +X face (RightSurface) takes the studs.
	-- A one-stud overlap into the arc, for the same reason Scenery's shoulders overlap
	-- the corridor: an exactly-touching seam between two computed edges is the one that
	-- opens first when either number moves.
	for _, sign in { -1, 1 } do
		local z0, z1 = L.corridorHalfZ, crossing + 1
		local n = math.max(1, math.ceil((z1 - z0) / WALL_TILE))
		for iz = 0, n - 1 do
			local a = z0 + (z1 - z0) * iz / n
			local b = z0 + (z1 - z0) * (iz + 1) / n
			local mid = sign * (a + b) / 2
			local origin = CFrame.new(shoulderX, 0, L.cz + mid)
			wallColumn(folder, origin, b - a, 1000 + iz * sign, p, 17, "RightSurface", Vector3.new(1, 0, 0))
			for cell = 0, 1 do
				local reachIn = if cell == 1 then LIP_OVERHANG else 0
				local cap = build(folder, CFrame.new(0, 0, 0), {
					name = "WallCap",
					pos = { shoulderX + (cell - 0.5) * WALL_TILE + reachIn / 2, capY, L.cz + mid },
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
	for _, dx in NORTH_STALL_X do
		stall(dx, ROW_Z, 180)
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
	buildSeam(m, L)
	buildWall(m, L)
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
