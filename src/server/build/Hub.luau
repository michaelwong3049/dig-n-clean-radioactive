--!strict
--[[
	Hub.luau — the plaza at the middle of the world, its roads, and the fence.

	    require(game.ServerScriptService.Server.build.Hub).rebuild()

	THE HUB IS A REST POCKET, AND THAT IS A CODE FACT, NOT A DECORATION.
	A player standing in no zone gets zero rads and 6x health regen
	(ExposureService). The plaza and every road leading off it are deliberately
	OUTSIDE all four zone rectangles, so "the paths are safe, the green is not" is
	true by construction and costs nothing to enforce. For a young audience that is
	the single most legible rule in the game, and it is free.

	THE NORTH SIDE HAS NO ROAD, ON PURPOSE.
	Zones 1-3 hang off the east, west and south gates on roads of increasing length.
	Zone 4 — the lethal one — sits directly behind the camp's back wall behind a
	fence with a hole in it, in plain sight of the trader's counter. PLAN §4 asks for
	"borders that are visible and legible, never solid", and PLAN §15's second
	validation question is "do players cross into Zone 4 unrated, on purpose, more
	than once?". Putting the lethal field where you can see it from the till is what
	makes that question answerable at all.

	At 15 rads/sec against a Cloth Wrap's tolerance of 1.0, Zone 4 is about seven
	seconds to blackout. That has to be a CHOICE, never an accident, which is why the
	fence has exactly one gap, the verge in front of it is wide and a different
	colour, and the sign is not subtle.
]]

local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Kit)

local Hub = {}
local BUILDER_SOURCE = "src/server/build/Hub.luau"
local BUILDER_VERSION = 1

local C = Kit.C
local build, light = Kit.build, Kit.light

-- ── Layout ────────────────────────────────────────────────────────────────────
-- Everything here is world space. The plaza is centred on the origin, its walking
-- surface at Y = 0, and the zone plates sit 1.5 studs lower so you step DOWN into
-- the sludge. See Config/Zones.SURFACE_Y.

Hub.PLAZA = { size = 260, thickness = 8, topY = 0 }
Hub.CAMP_ORIGIN = CFrame.new(0, -0.6, 90) -- BaseCamp's floor top lands on Y = 0

-- Gaps in the plaza edge that roads run through. Chosen to thread between the
-- six plots — see Plots.luau, which owns the other half of this arithmetic.
Hub.GATES = {
	east = { axis = "x", at = 130, along = 27, width = 34 },
	west = { axis = "x", at = -130, along = 27, width = 34 },
	south = { axis = "z", at = -130, along = 0, width = 40 },
}

Hub.FENCE_Z = 150 -- between the plaza edge (130) and Zone 4's near edge (180)
Hub.FENCE_GAP = 12 -- the hole. Exactly one, exactly this wide.

local function buildPlaza(hub: Model)
	local p = Hub.PLAZA
	local origin = CFrame.new(0, 0, 0)

	build(hub, origin, {
		name = "Plaza",
		pos = { 0, p.topY - p.thickness / 2, 0 },
		size = { p.size, p.thickness, p.size },
		color = C.plazaWarm,
		material = "Pavement",
	})

	-- A rim, purely so the plaza edge reads as an edge from ground level.
	for _, side in { -1, 1 } do
		build(hub, origin, {
			name = "PlazaRimX",
			pos = { side * (p.size / 2 - 0.6), p.topY - 0.2, 0 },
			size = { 1.2, 0.6, p.size },
			color = C.plazaEdge,
			material = "Concrete",
			canCollide = false,
		})
		build(hub, origin, {
			name = "PlazaRimZ",
			pos = { 0, p.topY - 0.2, side * (p.size / 2 - 0.6) },
			size = { p.size, 0.6, 1.2 },
			color = C.plazaEdge,
			material = "Concrete",
			canCollide = false,
		})
	end
end

--- One road, from the plaza edge out to a zone's near edge. Safe ground: no ZoneId,
--- so ExposureService treats it exactly like base camp.
local function buildRoad(hub: Model, name: string, from: Vector3, to: Vector3, width: number)
	local origin = CFrame.new(0, 0, 0)
	local mid = (from + to) / 2
	local span = (to - from).Magnitude
	local alongX = math.abs(to.X - from.X) > math.abs(to.Z - from.Z)

	build(hub, origin, {
		name = name,
		pos = { mid.X, Hub.PLAZA.topY - Hub.PLAZA.thickness / 2, mid.Z },
		size = {
			if alongX then span else width,
			Hub.PLAZA.thickness,
			if alongX then width else span,
		},
		color = C.road,
		material = "Pavement",
	})

	-- Verge strips either side, so the safe corridor is visually unambiguous
	-- against the ooze it runs through.
	for _, side in { -1, 1 } do
		build(hub, origin, {
			name = `{name}Verge`,
			pos = {
				mid.X + (if alongX then 0 else side * (width / 2 + 2)),
				Hub.PLAZA.topY - 0.3,
				mid.Z + (if alongX then side * (width / 2 + 2) else 0),
			},
			size = {
				if alongX then span else 4,
				0.8,
				if alongX then 4 else span,
			},
			color = C.grass,
			material = "Grass",
			canCollide = false,
		})
	end
end

local function buildRoads(hub: Model)
	local half = Hub.PLAZA.size / 2
	-- Out to each built zone's near edge. Lengths differ on purpose: the walk is
	-- the commitment, and it grows with the zone.
	buildRoad(hub, "EastRoad", Vector3.new(half, 0, 27), Vector3.new(162, 0, 27), 34)
	buildRoad(hub, "WestRoad", Vector3.new(-half, 0, 27), Vector3.new(-268, 0, 27), 34)
	buildRoad(hub, "SouthRoad", Vector3.new(0, 0, -half), Vector3.new(0, 0, -258), 40)
end

--- The north border: a wide grass verge, a fence with exactly one hole in it, and a
--- sign. Everything about this is trying to make crossing deliberate.
local function buildNorthBorder(hub: Model)
	local origin = CFrame.new(0, 0, 0)

	-- The dead verge. Wide, and a different green from the ooze beyond it.
	build(hub, origin, {
		name = "DeadVerge",
		pos = { 0, Hub.PLAZA.topY - 1, 0 + 155 },
		size = { 300, 2, 50 },
		color = C.grassDark,
		material = "Grass",
	})

	local gap = Hub.FENCE_GAP / 2
	local reach = 145

	-- Two runs of fence, leaving one gap dead centre.
	for _, side in { -1, 1 } do
		local inner = side * gap
		local outer = side * reach
		local mid = (inner + outer) / 2
		local span = math.abs(outer - inner)

		build(hub, origin, {
			name = "Fence",
			pos = { mid, Hub.PLAZA.topY + 3, Hub.FENCE_Z },
			size = { span, 6, 0.4 },
			color = C.steelDark,
			material = "DiamondPlate",
			transparency = 0.35,
		})
		-- Posts along it.
		local posts = math.max(2, math.floor(span / 12))
		for i = 0, posts do
			build(hub, origin, {
				name = "FencePost",
				pos = { inner + (outer - inner) * (i / posts), Hub.PLAZA.topY + 3.2, Hub.FENCE_Z },
				size = { 0.6, 6.6, 0.6 },
				color = C.steelDark,
				material = "Metal",
			})
		end
	end

	-- The sign. Hand-painted, unsubtle, and hung right beside the only way through.
	local sign = build(hub, origin, {
		name = "WarningSign",
		pos = { gap + 7, Hub.PLAZA.topY + 5, Hub.FENCE_Z - 1 },
		size = { 12, 5, 0.5 },
		color = C.barrelYellow,
		material = "Metal",
	})
	Kit.surfaceText(sign, Enum.NormalId.Back, "DO NOT\nENTER", C.signText)
	light(sign, C.barrelYellow, 18, 1.4)

	-- Hazard posts marking the gap itself, so the one way through is obvious.
	for _, side in { -1, 1 } do
		local post = build(hub, origin, {
			name = "GapMarker",
			pos = { side * gap, Hub.PLAZA.topY + 4, Hub.FENCE_Z },
			size = { 1.2, 8, 1.2 },
			color = C.barrelRust,
			material = "Neon",
		})
		light(post, C.barrelRust, 16, 2)
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
--- It sits ON the camp's shower grate, so you wake up mid-flush. That turns the
--- punishment beat into a relief beat, which for this audience is worth more than
--- the four studs it costs.
local function buildSpawns(hub: Model)
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"

	local grate = Hub.CAMP_ORIGIN * CFrame.new(0, 0.75, -14) -- BaseCamp's Grate, in world space
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
	buildRoads(hub)
	buildNorthBorder(hub)
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
