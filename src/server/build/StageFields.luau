--!strict
--[[
	StageFields.luau — the dig plates. The strictest generator in the build.

	    require(game.ServerScriptService.Server.build.StageFields).rebuild()

	Named StageFields rather than Stages so that requiring it next to
	Shared/Config/Stages does not produce two locals called `Stages` in one file.

	THIS MODULE EXISTS TO SATISFY TWO INDEPENDENT LOOKUPS THAT MUST AGREE:

	    DigService.stagePart   Workspace.Stages:FindFirstChild("Stage" .. id)  -- by NAME
	    StageService.stageAt    GetChildren(), reading attribute StageId       -- by ATTRIBUTE

	Miss the name and there are no signals. Miss the attribute and nobody is ever
	considered to be standing in the stage. Both are written from the same loop index
	below, and asserted before parenting, so they cannot drift.

	THE INVARIANT WORTH PROTECTING: Workspace.Stages contains EXACTLY these plates and
	nothing else. Not one barrel, not one folder. Scenery lives in Workspace.Scenery.
	Two reasons, and the second is the real one:

	  1. StageService walks those children at 10 Hz per player.
	  2. A decoration that accidentally carried a StageId attribute would register as
	     a stage, and overlapping stages resolve as "smallest XZ area wins" — so a
	     stray 4-stud barrel would silently become the stage every player standing
	     near it is in. That is a genuinely horrible bug to chase, and the cheapest
	     way to never have it is to keep this folder pure.

	FLAT, ALWAYS. DigService buries at part.CFrame:PointToWorldSpace(x, size.Y/2, z)
	— the plate's flat top face. Tilt or bump a plate and items surface underground
	or float above it. Rotation is asserted to be identity.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Tuning = require(Shared.Config.Tuning)

local Kit = require(script.Parent.Kit)

local StageFields = {}
local BUILDER_SOURCE = "src/server/build/StageFields.luau"
local BUILDER_VERSION = 3

--- The deepest an item is ever buried. The plate has to be thicker than this or a
--- haul in progress is visible poking out of the underside of the world.
local function maxBurialDepth(): number
	return Tuning.DIG_DEPTH_BASE + 7 * Tuning.DIG_DEPTH_PER_RARITY + Tuning.DIG_DEPTH_JITTER
end

local function createFields(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Stages"
	Kit.stamp(folder, BUILDER_SOURCE, BUILDER_VERSION)

	local needed = maxBurialDepth() + 2
	assert(
		Stages.PLATE_THICKNESS >= needed,
		`plate thickness {Stages.PLATE_THICKNESS} cannot contain a {maxBurialDepth()}-stud burial; need >= {needed}`
	)

	for _, id in Stages.builtIds() do
		local def = Stages.get(id)
		local size = Stages.plateSize(id)
		local cframe = Stages.plateCFrame(id)

		-- Built through Kit like everything else, but positioned absolutely: a stage's
		-- centre is world space, not an offset from some origin, because the plates
		-- are the frame everything else is measured against.
		-- Painted with the stage's ooze tint baked in (Stages.GROUND_OOZE_TINT), not
		-- the raw def.color -- see that constant's comment. There is no separate
		-- OozeSurface any more to supply the bright half of the ground's colour,
		-- so this plate is the whole of it now.
		local plate = Kit.build(folder, cframe, {
			name = `Stage{id}`,
			pos = { 0, 0, 0 },
			size = { size.X, size.Y, size.Z },
			color = Kit.blendHex(def.color, def.ooze.bright, Stages.GROUND_OOZE_TINT),
			material = def.material,
			rot = Kit.R.flat,
			attributes = {
				StageId = id,
				StageName = def.name,
				-- Not read by anything; here so someone inspecting a plate in Studio
				-- can see what it is without going and finding the config. BaseRads
				-- is now specifically the entrance rate, DeepRads the far-edge one --
				-- see Stages.radsAt.
				BaseRads = def.baseRads,
				DeepRads = def.deepRads,
			},
		})

		-- The two lookups, checked against each other at the point they are created.
		assert(plate.Name == `Stage{id}`, `stage {id} name/attribute mismatch`)
		assert(plate:GetAttribute("StageId") == id, `stage {id} attribute did not stick`)

		local topY = plate.Position.Y + plate.Size.Y / 2
		assert(
			math.abs(topY - Stages.SURFACE_Y) < 0.001,
			`stage {id} top face is at {topY}, expected {Stages.SURFACE_Y} — items would surface underground`
		)
	end

	return folder
end

--- Build the plates under `parent` without removing anything.
function StageFields.build(parent: Instance?): Folder
	local folder = createFields()
	folder.Parent = parent or Workspace
	return folder
end

--- Replace Workspace.Stages. Atomic: a throw leaves the existing fields alone.
function StageFields.rebuild(parent: Instance?): Folder
	local folder = Kit.swap("Stages", createFields, parent) :: Folder
	local ids = {}
	for _, plate in folder:GetChildren() do
		table.insert(ids, plate.Name)
	end
	table.sort(ids)
	print(`[build] Stages rebuilt — {table.concat(ids, ", ")}`)
	return folder
end

return StageFields
