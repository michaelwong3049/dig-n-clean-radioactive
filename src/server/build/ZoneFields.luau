--!strict
--[[
	ZoneFields.luau — the dig plates. The strictest generator in the build.

	    require(game.ServerScriptService.Server.build.ZoneFields).rebuild()

	Named ZoneFields rather than Zones so that requiring it next to
	Shared/Config/Zones does not produce two locals called `Zones` in one file.

	THIS MODULE EXISTS TO SATISFY TWO INDEPENDENT LOOKUPS THAT MUST AGREE:

	    DigService.zonePart   Workspace.Zones:FindFirstChild("Zone" .. id)  -- by NAME
	    ZoneService.zoneAt    GetChildren(), reading attribute ZoneId       -- by ATTRIBUTE

	Miss the name and there are no signals. Miss the attribute and nobody is ever
	considered to be standing in the zone. Both are written from the same loop index
	below, and asserted before parenting, so they cannot drift.

	THE INVARIANT WORTH PROTECTING: Workspace.Zones contains EXACTLY these plates and
	nothing else. Not one barrel, not one folder. Scenery lives in Workspace.Scenery.
	Two reasons, and the second is the real one:

	  1. ZoneService walks those children at 10 Hz per player.
	  2. A decoration that accidentally carried a ZoneId attribute would register as
	     a zone, and overlapping zones resolve as "smallest XZ area wins" — so a
	     stray 4-stud barrel would silently become the zone every player standing
	     near it is in. That is a genuinely horrible bug to chase, and the cheapest
	     way to never have it is to keep this folder pure.

	FLAT, ALWAYS. DigService buries at part.CFrame:PointToWorldSpace(x, size.Y/2, z)
	— the plate's flat top face. Tilt or bump a plate and items surface underground
	or float above it. Rotation is asserted to be identity.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Zones = require(Shared.Config.Zones)
local Tuning = require(Shared.Config.Tuning)

local Kit = require(script.Parent.Kit)

local ZoneFields = {}
local BUILDER_SOURCE = "src/server/build/ZoneFields.luau"
local BUILDER_VERSION = 2

--- The deepest an item is ever buried. The plate has to be thicker than this or a
--- haul in progress is visible poking out of the underside of the world.
local function maxBurialDepth(): number
	return Tuning.DIG_DEPTH_BASE + 7 * Tuning.DIG_DEPTH_PER_RARITY + Tuning.DIG_DEPTH_JITTER
end

local function createFields(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Zones"
	Kit.stamp(folder, BUILDER_SOURCE, BUILDER_VERSION)

	local needed = maxBurialDepth() + 2
	assert(
		Zones.PLATE_THICKNESS >= needed,
		`plate thickness {Zones.PLATE_THICKNESS} cannot contain a {maxBurialDepth()}-stud burial; need >= {needed}`
	)

	for _, id in Zones.builtIds() do
		local def = Zones.get(id)
		local size = Zones.plateSize(id)
		local cframe = Zones.plateCFrame(id)

		-- Built through Kit like everything else, but positioned absolutely: a zone's
		-- centre is world space, not an offset from some origin, because the plates
		-- are the frame everything else is measured against.
		-- Painted with the zone's ooze tint baked in (Zones.GROUND_OOZE_TINT), not
		-- the raw def.color -- see that constant's comment. There is no separate
		-- OozeSurface any more to supply the bright half of the ground's colour,
		-- so this plate is the whole of it now.
		local plate = Kit.build(folder, cframe, {
			name = `Zone{id}`,
			pos = { 0, 0, 0 },
			size = { size.X, size.Y, size.Z },
			color = Kit.blendHex(def.color, def.ooze.bright, Zones.GROUND_OOZE_TINT),
			material = def.material,
			rot = Kit.R.flat,
			attributes = {
				ZoneId = id,
				ZoneName = def.name,
				-- Not read by anything; here so someone inspecting a plate in Studio
				-- can see what it is without going and finding the config. BaseRads
				-- is now specifically the entrance rate, DeepRads the far-edge one --
				-- see Zones.radsAt.
				BaseRads = def.baseRads,
				DeepRads = def.deepRads,
			},
		})

		-- The two lookups, checked against each other at the point they are created.
		assert(plate.Name == `Zone{id}`, `zone {id} name/attribute mismatch`)
		assert(plate:GetAttribute("ZoneId") == id, `zone {id} attribute did not stick`)

		local topY = plate.Position.Y + plate.Size.Y / 2
		assert(
			math.abs(topY - Zones.SURFACE_Y) < 0.001,
			`zone {id} top face is at {topY}, expected {Zones.SURFACE_Y} — items would surface underground`
		)
	end

	return folder
end

--- Build the plates under `parent` without removing anything.
function ZoneFields.build(parent: Instance?): Folder
	local folder = createFields()
	folder.Parent = parent or Workspace
	return folder
end

--- Replace Workspace.Zones. Atomic: a throw leaves the existing fields alone.
function ZoneFields.rebuild(parent: Instance?): Folder
	local folder = Kit.swap("Zones", createFields, parent) :: Folder
	local ids = {}
	for _, plate in folder:GetChildren() do
		table.insert(ids, plate.Name)
	end
	table.sort(ids)
	print(`[build] Zones rebuilt — {table.concat(ids, ", ")}`)
	return folder
end

return ZoneFields
