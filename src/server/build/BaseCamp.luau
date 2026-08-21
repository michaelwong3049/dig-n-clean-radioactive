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

	NO DECON STATION AND NO SHOWER HERE ANY MORE. Both moved to `build/Plots.luau`
	— one combined "cleansing station" per base instead of one shared pair at
	camp, so a player docks and flushes exposure right where they're about to
	rack the item, not on a round trip back here. See Plots.luau's
	`buildCleansingStation` for the replacement and the reasoning.

	NO WALLS AND NO TRADER HERE EITHER, as of this pass. The camp used to be a
	walled enclosure sitting inside the open plaza, boxing the trader off from the
	shops around it; both the walls and the trader are gone now, so the camp is
	just a floor pad with the entrance gate/sign and the join spawn — the plaza
	reads as one open shop area instead of a plaza with a smaller walled camp
	inside it. THIS MEANS THERE IS CURRENTLY NO `StationKind = "trader"` ANYWHERE
	IN THE WORLD — `EconomyService.sell` and the "sell" verb in `DeconService`'s
	action router are still there and still work, but nothing in the world can
	trigger them until a trader (or some other sell point) is placed again
	somewhere. Flagged, not silently dropped — see TODO.md.
]]

local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Kit)

local BaseCamp = {}
local BUILDER_SOURCE = "src/server/build/BaseCamp.luau"
local BUILDER_VERSION = 4

-- Where the camp sits. This is the Floor's centre; everything else is relative to it,
-- so moving the whole camp is a one-line change (or an argument to build()).
local DEFAULT_ORIGIN = CFrame.new(0, 0.9, 136)

-- ── Primitives ────────────────────────────────────────────────────────────────
-- Lifted into build/Kit.luau so the hub, shops, plots, zones and scenery generators
-- all share one part-builder instead of four that drift. Aliased to the original
-- local names so every call site below is unchanged from the version that was
-- verified against the live place to the stud.
local C = Kit.C
local build, light = Kit.build, Kit.light

export type Spec = Kit.Spec

-- ── The camp ──────────────────────────────────────────────────────────────────

local FLOOR = { width = 64, depth = 46 }
local GATE_X = 10 -- half-spacing between the two entrance posts

local function buildShell(camp: Model, origin: CFrame)
	build(camp, origin, {
		name = "Floor",
		pos = { 0, 0, 0 },
		size = { FLOOR.width, 1.2, FLOOR.depth },
		color = C.floor,
		material = "Pavement",
	})

	-- No enclosing walls any more — removed so the camp reads as part of the
	-- open shop area rather than a smaller walled box sitting inside it. The
	-- gate posts and their lamps stay, mirrored either side of the entrance, as
	-- a freestanding marker on the south approach.
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

-- ── Entry points ──────────────────────────────────────────────────────────────

--- Construct a complete, unparented camp. Keeping it out of the DataModel while it
--- is assembled makes rebuild atomic: an error here cannot destroy the working camp.
local function createCamp(origin: CFrame): Model
	local camp = Instance.new("Model")
	camp.Name = "BaseCamp"
	Kit.stamp(camp, BUILDER_SOURCE, BUILDER_VERSION)

	buildShell(camp, origin)

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
