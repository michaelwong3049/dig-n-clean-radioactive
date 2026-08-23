--!strict
--[[
	Hub.luau — the plaza at the middle of the world.

	    require(game.ServerScriptService.Server.build.Hub).rebuild()

	THE HUB IS A REST POCKET, AND THAT IS A CODE FACT, NOT A DECORATION.
	A player standing in no zone gets zero rads and 6x health regen
	(ExposureService). The plaza and every road leading off it are deliberately
	OUTSIDE all four zone rectangles, so "the paths are safe, the green is not" is
	true by construction and costs nothing to enforce. For a young audience that is
	the single most legible rule in the game, and it is free.

	THE PLOTS RING IT ON THREE SIDES. Two north, two south, two west, each pad butted
	against the plaza edge and rotated to face inward. The east side is the radiation
	field and always will be, so the ring is open there — you walk out of the
	courtyard directly into the sludge.

	NO CONNECTOR ROADS. The plaza used to be a fixed 160x160 square with paved strips
	running out to a plot spine and to the field. Per the requested layout (plots —
	shop area — radiation, directly touching, not places joined by roads), the plaza's
	footprint reaches its neighbours directly: its east edge lands exactly on Zone 1's
	west edge, and the pads sit flush against its other three. Zero gap, not a short
	one — `rectsOverlap` treats an exactly-shared edge as touching, not overlapping,
	so this is safe against the "no zone may overlap the plaza" check in
	`World.verify()`.

	IT USED TO BE 237x382, AND THAT WAS NOT A DESIGN DECISION. It was that deep for
	one reason: all six plots were a single column down the west side, and the plaza
	had been stretched in Z until it spanned the whole column so they could all border
	it. Ringing the plots removed that constraint, and the plaza went back to being
	sized by what is actually standing on it — the camp and the stalls occupy roughly
	110x120 — rather than by the length of something parked beside it. 200x200 now,
	down from 237x382: a little under half the area.
]]

local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Kit)

local Hub = {}
local BUILDER_SOURCE = "src/server/build/Hub.luau"
local BUILDER_VERSION = 5

local C = Kit.C
local build = Kit.build

-- ── Layout ────────────────────────────────────────────────────────────────────
-- Everything here is world space. The plaza's walking surface is at Y = 0, and
-- the zone plate sits 1.5 studs lower so you step DOWN into the sludge. See
-- Config/Zones.SURFACE_Y.
--
-- THIS RECTANGLE IS NOW THE SOURCE, NOT THE FOLLOWER. It used to be hand-synced to
-- Plots.luau's constants through a comment, with four numbers that had to be edited
-- together and nothing to catch it if they were not. That is backwards: the plaza is
-- the thing the map is arranged around. Plots.luau requires this file and derives its
-- pad ring from these four numbers, so moving the plaza moves the plots with it and
-- there is no pair to keep in step. (Hub requires only Kit, so that direction is not
-- circular — do not add a require of Plots here or it becomes one.)
--
--   maxX = 100  is the one number NOT free to move: it is Zone 1's west edge
--               (Zones.get(1).center[1] - size[1]/2), and the plaza touching the
--               field directly is the whole point of the layout.
--
-- SYMMETRIC ABOUT X=0 ON PURPOSE, and it is worth 20 studs of extra width to keep it
-- that way. Everything standing on the plaza is centred on x=0 — the camp floor, the
-- three stalls, the outfitter bench — and the plot ring is DERIVED from this
-- rectangle, so an off-centre plaza puts the whole ring out of line with the shops it
-- is supposed to face. At minX = -80 the centre landed on x=10 and the pads sat ten
-- studs west of everything they framed. Shrink this by moving maxX, never minX.
Hub.PLAZA = { minX = -100, maxX = 100, minZ = -100, maxZ = 100, thickness = 8, topY = 0 }
Hub.CAMP_ORIGIN = CFrame.new(0, -0.6, 0) -- BaseCamp's floor top lands on Y = 0

local function buildPlaza(hub: Model)
	local p = Hub.PLAZA
	local origin = CFrame.new(0, 0, 0)
	local width, depth = p.maxX - p.minX, p.maxZ - p.minZ
	local centerX, centerZ = (p.minX + p.maxX) / 2, (p.minZ + p.maxZ) / 2

	build(hub, origin, {
		name = "Plaza",
		pos = { centerX, p.topY - p.thickness / 2, centerZ },
		size = { width, p.thickness, depth },
		color = C.plazaWarm,
		material = "Pavement",
	})

	-- A rim, purely so the plaza edge reads as an edge from ground level. On three
	-- sides now, not two: the plots no longer cover a whole edge between them, so the
	-- west side needs one as well. The EAST edge still gets none — it butts into the
	-- zone plate, and a rim there would draw a false seam across the one boundary
	-- that is supposed to read as continuous ground.
	for _, z in { p.minZ, p.maxZ } do
		build(hub, origin, {
			name = "PlazaRimZ",
			pos = { centerX, p.topY - 0.2, z + (if z == p.minZ then 0.6 else -0.6) },
			size = { width, 0.6, 1.2 },
			color = C.plazaEdge,
			material = "Concrete",
			canCollide = false,
		})
	end

	build(hub, origin, {
		name = "PlazaRimX",
		pos = { p.minX + 0.6, p.topY - 0.2, centerZ },
		size = { 1.2, 0.6, depth },
		color = C.plazaEdge,
		material = "Concrete",
		canCollide = false,
	})
end

--- THE BLACKOUT ANCHOR — see ExposureService.baseCampCFrame.
---
--- This is a named part, not a SpawnLocation, and the distinction matters. The old
--- lookup was Workspace:FindFirstChildWhichIsA("SpawnLocation"), which searches
--- DIRECT CHILDREN ONLY — and BaseCamp parents its spawn inside the camp model, so
--- the search failed and fell through to a hardcoded CFrame.new(0, 8, 0). With the
--- old layout that point was inside Zone 1: blacking out teleported you into the
--- radioactive field. Making it a search over a class that now has seven instances
--- in the world would have replaced one arbitrary answer with another.
---
--- It used to sit ON the camp's shower grate, so you woke up mid-flush — a
--- relief beat instead of a punishment one. The shower moved to a per-base
--- cleansing station on every plot (see Plots.buildCleansingStation) and isn't
--- at camp any more, so that instant flush is gone: a blacked-out player now
--- lands here with whatever exposure they had, same as anyone else who's just
--- standing in a zero-rad zone. Base camp is still "no zone" (zero rads, 6x
--- health regen per ExposureService), so exposure still drains here — just on
--- the normal passive curve, not an instant reset.
local function buildSpawns(hub: Model)
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"

	-- The offset is arbitrary now (there's no grate to sit on any more) — kept
	-- as "just inside the gate, not in the middle of the road" rather than
	-- recentred on nothing in particular.
	local grate = Hub.CAMP_ORIGIN * CFrame.new(0, 0.75, -14)
	build(spawns, CFrame.new(0, 0, 0), {
		name = "RespawnAnchor",
		pos = { grate.X, Hub.PLAZA.topY + 0.5, grate.Z },
		size = { 4, 1, 4 },
		color = C.cyan,
		material = "Neon",
		transparency = 1,
		canCollide = false,
	})

	spawns.Parent = hub
end

local function createHub(): Model
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	Kit.stamp(hub, BUILDER_SOURCE, BUILDER_VERSION)

	buildPlaza(hub)
	buildSpawns(hub)

	return hub
end

function Hub.build(parent: Instance?): Model
	local hub = createHub()
	hub.Parent = parent or Workspace
	return hub
end

function Hub.rebuild(parent: Instance?): Model
	local hub = Kit.swap("Hub", createHub, parent) :: Model
	print(`[build] Hub rebuilt — {#hub:GetDescendants()} descendants`)
	return hub
end

return Hub
