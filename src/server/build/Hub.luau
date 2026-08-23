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

	THE NORTH SIDE HAS NO ROAD, ON PURPOSE.
	The west side is a compact block of player plots. The camp and shop stalls sit in
	the small central rest area. The radioactive field sits directly east.

	NO CONNECTOR ROADS EITHER, as of this pass, AND NO SPINE/STUB NETWORK ON THE
	WEST SIDE EITHER, as of the one after it. The plaza used to be a fixed
	160x160 square with short paved strips running out to a plot spine and to
	the field. Per the requested layout (plots — shop area — radiation, directly
	touching, not places joined by roads), the plaza's own footprint now
	stretches far enough to reach both directly: its east edge lands exactly on
	Zone 1's west edge, and its west edge lands exactly on the plot pads' own
	east edge — not a spine's edge, the PADS' edge, so all six plots border the
	plaza along one continuous seam instead of feeding into it through a lane
	network. Zero gap on both sides, not a short one — `rectsOverlap` treats an
	exactly-shared edge as touching, not overlapping, so this is safe against
	the "no zone may overlap the plaza" check in `World.verify()`.
]]

local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Kit)

local Hub = {}
local BUILDER_SOURCE = "src/server/build/Hub.luau"
local BUILDER_VERSION = 4

local C = Kit.C
local build = Kit.build

-- ── Layout ────────────────────────────────────────────────────────────────────
-- Everything here is world space. The plaza's walking surface is at Y = 0, and
-- the zone plate sits 1.5 studs lower so you step DOWN into the sludge. See
-- Config/Zones.SURFACE_Y.
--
-- Not a square, and not centred on the origin any more -- it's sized to reach
-- exactly two things this file can't require without a circular dependency
-- (Plots.luau already requires Hub, so Hub can't require Plots back):
--   minX = -137  MUST equal Plots.PLOT_X + Plots.PAD.width/2  (-170 + 33)
--                -- the plot pads' own east edge.
--   minZ = -191  MUST equal the plot column's outer south edge
--   maxZ =  191  MUST equal the plot column's outer north edge
--                -- both from Plots.CENTERS' extremes (-165, 165) +/- half of
--                -- Plots.PAD.depth (26).
--   maxX =  100  Zone 1's west edge (Zones.get(1).center[1] - size[1]/2).
-- If any of Plots.PLOT_X, Plots.PAD, Plots.CENTERS, or Zone 1's position/size
-- change, these four numbers need updating by hand to match -- there is no
-- assertion that catches drift here the way `Plots.SPINE_X`'s comment used to
-- reference `Hub.PLAZA.halfX` (that whole spine is gone now anyway).
Hub.PLAZA = { minX = -137, maxX = 100, minZ = -191, maxZ = 191, thickness = 8, topY = 0 }
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

	-- A rim, purely so the plaza edge reads as an edge from ground level. Only
	-- on the north/south (Z) edges now -- east butts into the zone plate, west
	-- butts into the plot pads, and a rim on either would draw a false seam
	-- across a boundary that is supposed to read as continuous.
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
