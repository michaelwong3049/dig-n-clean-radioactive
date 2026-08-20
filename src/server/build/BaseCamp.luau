--!strict
--[[
	BaseCamp.luau — THE SOURCE OF TRUTH for the base camp geometry.

	This is a build tool, not a service. Nothing requires it at boot; you run it by
	hand when the camp changes:

	    require(game.ServerScriptService.Server.build.BaseCamp).rebuild()

	WHY THIS FILE EXISTS
	The camp used to exist only as 101 instances inside the place file, which meant it
	was versioned nowhere and two people could not edit it without clobbering each
	other. The generator that originally produced it was run from the command bar and
	then lost — the same way the tool-tier generator was lost, leaving Config/ToolTiers
	as a recipe with no cook. Geometry that was born from code should stay as code.

	HOW TO EDIT
	Change a number here and re-run rebuild(). Do NOT drag parts in Studio: this file
	is authoritative, so the next rebuild silently reverts anything you moved by hand.
	That is the trade — you lose freehand dragging, you gain a camp that merges.

	The layout is deliberately expressed as loops and offsets rather than 101 literal
	positions, because that is what it actually is: 7 evenly spaced awning slats, 5
	jets on a 2.1-stud pitch, 4 posts at the corners. Editing "step" beats editing
	seven positions and hoping you got them all.

	THE WORLD CONTRACT lives here too — the StationKind / Shower / Radius attributes
	that DeconService and ExposureService read (see ARCHITECTURE.md). They are set
	below, on Counter, Basin and Grate. Removing one silently disables that station.
]]

local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Kit)

local BaseCamp = {}
local BUILDER_SOURCE = "src/server/build/BaseCamp.luau"
local BUILDER_VERSION = 2

-- Where the camp sits. This is the Floor's centre; everything else is relative to it,
-- so moving the whole camp is a one-line change (or an argument to build()).
local DEFAULT_ORIGIN = CFrame.new(0, 0.9, 136)

-- ── Primitives ────────────────────────────────────────────────────────────────
-- Lifted into build/Kit.luau so the hub, shops, plots, zones and scenery generators
-- all share one part-builder instead of four that drift. Aliased to the original
-- local names so every call site below is unchanged from the version that was
-- verified against the live place to the stud.
local C, R = Kit.C, Kit.R
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

export type Spec = Kit.Spec

-- ── The camp ──────────────────────────────────────────────────────────────────

local FLOOR = { width = 64, depth = 46 } -- also drives the wall spans below
local GATE_X = 10 -- the gap in the front wall is +/- this

local function buildShell(camp: Model, origin: CFrame)
	build(camp, origin, {
		name = "Floor",
		pos = { 0, 0, 0 },
		size = { FLOOR.width, 1.2, FLOOR.depth },
		color = C.floor,
		material = "Pavement",
	})

	-- Side and back walls run the full span; the front is split around the gate.
	build(camp, origin, { name = "WallLeft", pos = { -31.5, 3.1, 0 }, size = { 1, 5, 46 }, color = C.concrete, material = "Concrete" })
	build(camp, origin, { name = "WallRight", pos = { 31.5, 3.1, 0 }, size = { 1, 5, 46 }, color = C.concrete, material = "Concrete" })
	build(camp, origin, { name = "WallBack", pos = { 0, 3.1, 22.5 }, size = { 64, 5, 1 }, color = C.concrete, material = "Concrete" })
	build(camp, origin, { name = "WallFrontL", pos = { -21, 3.1, -22.5 }, size = { 22, 5, 1 }, color = C.concrete, material = "Concrete" })
	build(camp, origin, { name = "WallFrontR", pos = { 21, 3.1, -22.5 }, size = { 22, 5, 1 }, color = C.concrete, material = "Concrete" })

	-- Gate posts and their lamps, mirrored either side of the entrance.
	for _, side in { -1, 1 } do
		local x = GATE_X * side
		build(camp, origin, {
			name = `GatePost_{x}`,
			pos = { x, 5.1, -22.5 },
			size = { 2.4, 9, 2.4 },
			color = C.concrete,
			material = "Metal",
		})
		local lamp = build(camp, origin, {
			name = `GateLamp_{x}`,
			pos = { x, 9.8, -22.5 },
			size = { 1.6, 0.8, 1.6 },
			color = C.canvas,
			material = "Neon",
		})
		light(lamp, C.lampWarm, 34, 2.6)
	end

	-- The BASE CAMP sign over the gate.
	local sign = build(camp, origin, {
		name = "Sign",
		pos = { 0, 11.1, -22.5 },
		size = { 20, 3.6, 0.8 },
		color = C.canvas,
		material = "Metal",
	})
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.PixelsPerStud = 50
	signGui.AlwaysOnTop = false
	signGui.Parent = sign

	local signText = Instance.new("TextLabel")
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.Font = Enum.Font.GothamBlack
	signText.TextScaled = true
	signText.TextColor3 = Color3.fromHex(C.signText)
	signText.TextStrokeTransparency = 1
	signText.Text = "BASE CAMP"
	signText.Parent = signGui

	local spawn = build(camp, origin, {
		name = "SpawnLocation",
		class = "SpawnLocation",
		pos = { 0, 1.1, 16 },
		size = { 12, 1, 12 },
		color = "A8B0A0",
		material = "Pavement",
	})
	local decal = Instance.new("Decal")
	decal.Texture = "rbxasset://textures/SpawnLocation.png"
	decal.Face = Enum.NormalId.Top
	decal.Parent = spawn
end

--- The trader. A till and nothing else — it does NOT stop the decay clock.
local function buildTrader(camp: Model, origin: CFrame)
	local m = Instance.new("Model")
	m.Name = "Trader"

	build(m, origin, { name = "Deck", pos = { 16, 0.8, 12 }, size = { 9, 0.4, 8 }, color = C.wood, material = "WoodPlanks", rot = R.yaw180 })

	-- Four corner posts holding the awning up.
	for _, dx in { -3.9, 3.9 } do
		for _, dz in { -2.6, 2.6 } do
			build(m, origin, {
				name = "Post",
				pos = { 16 + dx, 3.1, 12 + dz },
				size = { 0.4, 5, 0.4 },
				color = C.wood,
				material = "Wood",
				rot = R.yaw180,
			})
		end
	end

	-- Seven striped canvas slats, alternating, on a 1.25 pitch.
	for i = 0, 6 do
		build(m, origin, {
			name = "Awning",
			pos = { 12.25 + i * 1.25, 5.7, 12 },
			size = { 1.25, 0.3, 6.4 },
			color = if i % 2 == 0 then C.canvas else C.canvasPale,
			material = "Fabric",
			rot = R.yaw180,
			canCollide = false,
		})
	end
	build(m, origin, { name = "AwningLip", pos = { 16, 5.45, 8.8 }, size = { 9, 0.5, 0.4 }, color = C.wood, material = "Wood", rot = R.yaw180 })

	-- THE TILL. StationKind="trader" is what DeconService matches on.
	local counter = build(m, origin, {
		name = "Counter",
		pos = { 16, 2.1, 10.6 },
		size = { 7.5, 1.4, 2.6 },
		color = C.woodLight,
		material = "WoodPlanks",
		rot = R.yaw180,
		attributes = { StationKind = "trader", Radius = 12 },
	})
	billboard(counter, 240, 4.6, "TRADER", "turn it into cash", C.canvas)

	build(m, origin, { name = "CounterTop", pos = { 16, 2.9, 10.6 }, size = { 8.2, 0.3, 3.2 }, color = C.canvas, material = "WoodPlanks", rot = R.yaw180 })
	build(m, origin, { name = "CounterFront", pos = { 16, 1.5, 9.4 }, size = { 7.5, 1.6, 0.3 }, color = C.wood, material = "WoodPlanks", rot = R.yaw180 })

	-- Cash box, lid propped open, with a small stack of coins inside.
	build(m, origin, { name = "CashBox", pos = { 13.5, 3.5, 10.8 }, size = { 1.8, 0.9, 1.2 }, color = C.wood, material = "Wood", rot = R.yaw180 })
	build(m, origin, { name = "CashLid", pos = { 13.5, 4.2, 11.3 }, size = { 1.8, 0.15, 1.2 }, color = C.wood, material = "Wood", rot = R.lidTilt })
	for i = 0, 2 do
		build(m, origin, {
			name = "Coins",
			pos = { 13.5, 4 + i * 0.13, 10.8 },
			size = { 0.12, 0.75, 0.75 },
			color = C.gold,
			material = "Metal",
			shape = "Cylinder",
			rot = R.cylUpFlipped,
		})
	end

	-- Balance scale.
	build(m, origin, { name = "ScalePost", pos = { 18.4, 3.7, 10.8 }, size = { 0.25, 1.4, 0.25 }, color = C.steel, material = "Metal", rot = R.yaw180 })
	build(m, origin, { name = "ScaleBeam", pos = { 18.4, 4.4, 10.8 }, size = { 2.2, 0.18, 0.18 }, color = C.steel, material = "Metal", rot = R.yaw180 })
	for _, x in { 17.5, 19.3 } do
		build(m, origin, { name = "ScalePan", pos = { x, 4.1, 10.8 }, size = { 1.1, 0.12, 1.1 }, color = C.steel, material = "Metal", shape = "Cylinder", rot = R.cylUpFlipped })
	end

	-- Clutter. Irregular on purpose — a tidy stack reads as programmer art.
	build(m, origin, { name = "Crate", pos = { 19, 1.9, 14.2 }, size = { 1.8, 1.8, 1.8 }, color = C.woodLight, material = "WoodPlanks", rot = R.yaw180 })
	build(m, origin, { name = "Crate", pos = { 17.4, 1.8, 14.6 }, size = { 1.6, 1.6, 1.6 }, color = C.wood, material = "WoodPlanks", rot = R.yaw180 })
	build(m, origin, { name = "Crate", pos = { 19.1, 3.7, 14.3 }, size = { 1.5, 1.5, 1.5 }, color = C.wood, material = "WoodPlanks", rot = R.yaw180 })
	build(m, origin, { name = "Barrel", pos = { 12.9, 2.1, 14.4 }, size = { 2.2, 1.5, 1.5 }, color = C.canvas, material = "Metal", shape = "Cylinder", rot = R.cylUpFlipped })

	local lantern = build(m, origin, {
		name = "Lantern",
		pos = { 12.6, 5, 9.4 },
		size = { 0.7, 0.9, 0.7 },
		color = C.gold,
		material = "Neon",
		rot = R.yaw180,
		canCollide = false,
	})
	light(lantern, C.lampWarm, 24, 2.4)

	m.Parent = camp
end

--- The decon STATION. This is the one that freezes decay clocks (PLAN §3.6).
local function buildDeconStation(camp: Model, origin: CFrame)
	local m = Instance.new("Model")
	m.Name = "DeconStation"

	build(m, origin, { name = "Pad", pos = { -16, 0.8, 12 }, size = { 9, 0.4, 8 }, color = C.steelDark, material = "DiamondPlate", rot = R.yaw180 })

	-- THE DOCK. StationKind="decon" is the win condition for a run.
	local basin = build(m, origin, {
		name = "Basin",
		pos = { -16, 1.9, 12 },
		size = { 6, 1.8, 4.4 },
		color = C.steel,
		material = "Metal",
		rot = R.yaw180,
		attributes = { StationKind = "decon", Radius = 12 },
	})
	billboard(basin, 240, 4.6, "DECON STATION", "scrub it clean", "6FA8C7")

	build(m, origin, { name = "Water", pos = { -16, 2.75, 12 }, size = { 5.5, 0.25, 3.9 }, color = C.cyan, material = "Neon", rot = R.yaw180, transparency = 0.35 })
	build(m, origin, { name = "BackPanel", pos = { -16, 3.9, 14.4 }, size = { 7, 5.5, 0.5 }, color = C.steel, material = "Metal", rot = R.yaw180 })

	-- Gantry: two uprights and the beam across them.
	for _, x in { -13.1, -18.9 } do
		build(m, origin, { name = "Gantry", pos = { x, 4.8, 14 }, size = { 0.5, 4.2, 0.5 }, color = C.steelDark, material = "Metal", rot = R.yaw180 })
	end
	build(m, origin, { name = "GantryBeam", pos = { -16, 6.8, 14 }, size = { 6.4, 0.5, 0.5 }, color = C.steelDark, material = "Metal", rot = R.yaw180 })

	-- Twin tanks, capped, feeding the shower head.
	for _, x in { -18.4, -13.6 } do
		build(m, origin, { name = "Tank", pos = { x, 4, 15.1 }, size = { 3.2, 1.5, 1.5 }, color = C.cyan, material = "Metal", shape = "Cylinder", rot = R.cylUpFlipped })
		build(m, origin, { name = "TankCap", pos = { x, 5.7, 15.1 }, size = { 0.5, 1.7, 1.7 }, color = C.steelDark, material = "Metal", shape = "Cylinder", rot = R.cylUpFlipped })
	end
	for _, x in { -14.6, -17.4 } do
		build(m, origin, { name = "Pipe", pos = { x, 4.6, 14.1 }, size = { 2.6, 0.35, 0.35 }, color = C.steel, material = "Metal", shape = "Cylinder", rot = R.cylUpFlipped })
	end

	build(m, origin, { name = "NozzleArm", pos = { -16, 6.8, 13 }, size = { 0.4, 0.4, 2.2 }, color = C.steelDark, material = "Metal", rot = R.yaw180 })
	build(m, origin, { name = "ShowerHead", pos = { -16, 6.5, 12 }, size = { 0.6, 2.2, 2.2 }, color = C.steel, material = "Metal", shape = "Cylinder", rot = R.cylUpFlipped, canCollide = false })

	-- Three jets on a 0.7 pitch.
	for i = -1, 1 do
		build(m, origin, {
			name = "Jet",
			pos = { -16 + i * 0.7, 4.7, 12 },
			size = { 0.18, 3.4, 0.18 },
			color = C.cyan,
			material = "Neon",
			rot = R.yaw180,
			transparency = 0.55,
			canCollide = false,
		})
	end

	-- Hazard chevrons on the deck, 3.4 apart.
	for i = -1, 1 do
		build(m, origin, {
			name = "HazardStripe",
			pos = { -16 + i * 3.4, 0.81, 12 },
			size = { 0.9, 0.44, 8 },
			color = C.hazard,
			material = "DiamondPlate",
			rot = R.yaw180,
		})
	end

	local lamp = build(m, origin, { name = "Lamp", pos = { -16, 7.4, 14 }, size = { 0.7, 0.7, 0.7 }, color = C.cyan, material = "Neon", shape = "Ball", rot = R.yaw180 })
	light(lamp, C.cyan, 20, 2)

	m.Parent = camp
end

--- The decon SHOWER. Flushes the PLAYER only — it does not touch carried items,
--- which is why it is a separate structure from the station.
local function buildDeconShower(camp: Model, origin: CFrame)
	local m = Instance.new("Model")
	m.Name = "DeconShower"

	-- THE SHOWER. Shower=true / Radius=7 is what ExposureService scans for.
	local grate = build(m, origin, {
		name = "Grate",
		pos = { 0, 0.75, -14 },
		size = { 11, 0.3, 7 },
		color = C.showerSteel,
		material = "DiamondPlate",
		attributes = { Shower = true, Radius = 7 },
	})
	billboard(grate, 250, 3.2, "DECON SHOWER", "cleans you, not your loot", C.cyan)

	-- Four corner posts.
	for _, x in { -5, 5 } do
		for _, z in { -11, -17 } do
			build(m, origin, { name = "Post", pos = { x, 4.4, z }, size = { 0.9, 7, 0.9 }, color = C.showerSteel, material = "Metal" })
		end
		build(m, origin, { name = "Pipe", pos = { x, 4.8, -16.4 }, size = { 6.4, 0.4, 0.4 }, color = C.steel, material = "Metal", shape = "Cylinder", rot = R.cylUp })
		build(m, origin, { name = "SplashPanel", pos = { x, 4.4, -14 }, size = { 0.35, 6, 5.6 }, color = C.glass, material = "Glass", transparency = 0.55, canCollide = false })
	end

	build(m, origin, { name = "Gantry", pos = { 0, 8.2, -14 }, size = { 12, 1, 7.6 }, color = C.steel, material = "Metal" })
	build(m, origin, { name = "NozzleRail", pos = { 0, 7.6, -14 }, size = { 9.5, 0.35, 0.35 }, color = C.showerSteel, material = "Metal" })
	for _, z in { -17.6, -10.4 } do
		build(m, origin, { name = "GantryTrim", pos = { 0, 7.7, z }, size = { 12.4, 0.35, 0.5 }, color = C.hazard, material = "Metal", canCollide = false })
	end
	for _, z in { -17.2, -10.8 } do
		build(m, origin, { name = "HazardEdge", pos = { 0, 0.77, z }, size = { 11, 0.34, 0.7 }, color = C.hazard, material = "DiamondPlate", canCollide = false })
	end

	-- Five nozzles and the jets falling from them, on a 2.1 pitch.
	for i = -2, 2 do
		local x = i * 2.1
		build(m, origin, { name = "Nozzle", pos = { x, 7.3, -14 }, size = { 0.45, 0.8, 0.8 }, color = C.steel, material = "Metal", shape = "Cylinder", rot = R.cylUp, canCollide = false })
		build(m, origin, { name = "Jet", pos = { x, 4.7, -14 }, size = { 0.5, 5.1, 0.5 }, color = C.cyan, material = "Neon", shape = "Cylinder", transparency = 0.72, canCollide = false })
	end

	-- Five drain channels on a 1.8 pitch.
	for i = -2, 2 do
		build(m, origin, {
			name = "DrainChannel",
			pos = { i * 1.8, 0.76, -14 },
			size = { 0.5, 0.34, 6.4 },
			color = C.drain,
			material = "Metal",
			canCollide = false,
		})
	end

	-- Three bands of mist drifting front to back.
	for i = -1, 1 do
		build(m, origin, {
			name = "Mist",
			pos = { 0, 1.5, -14 + i * 1.6 },
			size = { 10, 0.9, 2.2 },
			color = C.cyan,
			material = "Neon",
			transparency = 0.88,
			canCollide = false,
		})
	end

	-- Header tank, lying across the top.
	build(m, origin, { name = "Tank", pos = { -3, 9.6, -14 }, size = { 4, 1.8, 1.8 }, color = C.cyan, material = "Metal", shape = "Cylinder", rot = R.cylAlongZ })
	build(m, origin, { name = "TankCap", pos = { -5.1, 9.6, -14 }, size = { 0.5, 2, 2 }, color = C.showerSteel, material = "Metal", shape = "Cylinder", rot = R.cylAlongZ })
	build(m, origin, { name = "TankFeed", pos = { -1, 8.9, -14 }, size = { 1.6, 0.45, 0.45 }, color = C.steel, material = "Metal", shape = "Cylinder", rot = R.cylUp })

	local lamp = build(m, origin, { name = "Lamp", pos = { 4.4, 9.1, -14 }, size = { 0.8, 0.8, 0.8 }, color = C.cyan, material = "Neon", shape = "Ball", canCollide = false })
	light(lamp, C.cyan, 26, 2.4)

	m.Parent = camp
end

-- ── Entry points ──────────────────────────────────────────────────────────────

--- Construct a complete, unparented camp. Keeping it out of the DataModel while it
--- is assembled makes rebuild atomic: an error here cannot destroy the working camp.
local function createCamp(origin: CFrame): Model
	local camp = Instance.new("Model")
	camp.Name = "BaseCamp"
	Kit.stamp(camp, BUILDER_SOURCE, BUILDER_VERSION)

	buildShell(camp, origin)
	buildTrader(camp, origin)
	buildDeconStation(camp, origin)
	buildDeconShower(camp, origin)

	return camp
end

--- Construct the camp under `parent` (default Workspace) without removing anything.
function BaseCamp.build(origin: CFrame?, parent: Instance?): Model
	local camp = createCamp(origin or DEFAULT_ORIGIN)
	camp.Parent = parent or Workspace
	return camp
end

--- Replace the camp in the world. This is the one you run after editing this file.
--- Kit.swap builds first and only then destroys, so a bad edit that throws leaves
--- the camp currently in the world untouched.
function BaseCamp.rebuild(origin: CFrame?, parent: Instance?): Model
	local camp = Kit.swap("BaseCamp", function()
		return createCamp(origin or DEFAULT_ORIGIN)
	end, parent) :: Model
	print(`[build] BaseCamp rebuilt — {#camp:GetDescendants()} descendants`)
	return camp
end

return BaseCamp
