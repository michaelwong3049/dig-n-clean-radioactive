--!strict
--[[
	ImportedNukeYard.luau — a small showcase platform for the 16 hand-imported
	reference nuke meshes (Shared.Config.ImportedNukeMeshes), planted at the
	camp's own datum (Hub.CAMP_ORIGIN) — the middle of the map — in place of the
	old catalogue-driven ModelGallery yard that used to live out past the
	perimeter wall.

	    require(game.ServerScriptService.Server.build.ImportedNukeYard).rebuild()
	    require(game.ServerScriptService.Server.build.ImportedNukeYard).remove()

	Each of the 16 is also a real catalogue item's model now (Shared.ItemModels
	wires ImportedNukeMeshes.build() into ItemModels.create() ahead of the
	procedural rarity capsule) — this yard is just a showcase of them, built
	from the same shared data rather than a separate copy of either. Scaled up
	onto a pedestal the same way ExhibitService's locker normalises arbitrary
	item art to a target size.

	THIS IS ALSO WHERE THE TEMPLATES GET (RE)BUILT. MeshPart.MeshId can only be
	written from an elevated (Studio/plugin/command-bar) thread — every rebuild
	here calls ImportedNukeMeshes.installTemplates() first, which is the ONE
	place that actually happens, before the plain gameplay-safe Clone() path
	(ItemModels.create, WashService, ToolService, ExhibitService) has anything
	to clone. Skipping a command-bar World.rebuild() after this file changes
	means those 16 items fall back to the plain rarity capsule at runtime —
	not broken, just not showing the real mesh yet.

	No floor slab of its own — unlike the old outside-the-wall yard, this one
	stands directly on the plaza tiles that are already there, so it only adds a
	thin hazard border to mark the showcase footprint instead of laying a second
	floor over the first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ImportedNukeMeshes = require(ReplicatedStorage.Shared.Config.ImportedNukeMeshes)

local Hub = require(script.Parent.Hub)
local Kit = require(script.Parent.Kit)

local ImportedNukeYard = {}

local NAME = "ModelYard"
local BUILDER_SOURCE = "src/server/build/ImportedNukeYard.luau"
local BUILDER_VERSION = 1

local GRID_COLUMNS = 4
local GRID_SPACING = 10
local PEDESTAL_TOP = 2.5
local MODEL_SIZE = 6.5 -- longest edge once scaled and standing on its pedestal

local EDGE_MARGIN = 4
local HEADER_CLEARANCE = 5

local MODELS = ImportedNukeMeshes.MODELS
local MODEL_COUNT = #MODELS
local GRID_ROWS = math.max(1, math.ceil(MODEL_COUNT / GRID_COLUMNS))

local LAND_WIDTH = GRID_COLUMNS * GRID_SPACING + EDGE_MARGIN * 2
local LAND_DEPTH = GRID_ROWS * GRID_SPACING + EDGE_MARGIN * 2 + HEADER_CLEARANCE

-- The plaza surface, in BaseCamp's own local-Y (mirrors BaseCamp.luau's trader
-- kiosk math: the plaza sits 0.9 below the camp datum, plus the raised plaza
-- floor's own lift).
local GROUND_Y = -0.9 + Hub.PLAZA_LIFT

local function buildTrim(gallery: Model, origin: CFrame)
	-- A thin hazard border marking the showcase footprint, standing proud of the
	-- plaza tiles rather than a full slab laid over them (nothing under this yard
	-- needs replacing — the plaza floor is already there).
	for _, edge in {
		{ pos = { 0, GROUND_Y + 0.03, -LAND_DEPTH / 2 + 0.5 }, size = { LAND_WIDTH, 0.06, 1 } },
		{ pos = { 0, GROUND_Y + 0.03, LAND_DEPTH / 2 - 0.5 }, size = { LAND_WIDTH, 0.06, 1 } },
		{ pos = { -LAND_WIDTH / 2 + 0.5, GROUND_Y + 0.03, 0 }, size = { 1, 0.06, LAND_DEPTH } },
		{ pos = { LAND_WIDTH / 2 - 0.5, GROUND_Y + 0.03, 0 }, size = { 1, 0.06, LAND_DEPTH } },
	} do
		Kit.build(gallery, origin, {
			name = "YardTrim",
			pos = edge.pos,
			size = edge.size,
			color = Kit.C.hazard,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end
end

--- Normalise an arbitrary imported assembly onto a fixed footprint and rest it
--- on the pedestal at `target` — the same normalise-to-a-target-dimension trick
--- ExhibitService's locker uses for arbitrary item art.
local function placeOnPedestal(model: Model, target: CFrame)
	model:PivotTo(CFrame.identity)

	local size = model:GetExtentsSize()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		model:ScaleTo(MODEL_SIZE / longest)
	end

	model:PivotTo(target)
	local bounds, extent = model:GetBoundingBox()
	local bottom = bounds.Position.Y - extent.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, PEDESTAL_TOP - bottom + 0.08, 0))
end

local function buildStand(gallery: Model, origin: CFrame, def: ImportedNukeMeshes.ModelDef, index: number, total: number)
	local columns = math.min(GRID_COLUMNS, math.max(1, total))
	local rows = math.ceil(total / GRID_COLUMNS)
	local row = math.floor((index - 1) / GRID_COLUMNS) + 1
	local column = ((index - 1) % GRID_COLUMNS) + 1
	local rowCount = if row < rows then GRID_COLUMNS else total - (rows - 1) * GRID_COLUMNS

	local x = (column - (rowCount + 1) / 2) * GRID_SPACING
	local z = (row - (rows + 1) / 2) * GRID_SPACING
	if rows == 1 then
		x = (column - (columns + 1) / 2) * GRID_SPACING
	end

	local pedestal = Kit.build(gallery, origin, {
		name = `Stand_{def.itemId}`,
		pos = { x, GROUND_Y + PEDESTAL_TOP / 2, z },
		size = { 4.5, PEDESTAL_TOP, 4.5 },
		color = Kit.C.plazaWarm,
		material = "Marble",
		attributes = { ImportedNukeId = def.itemId },
	})

	Kit.billboard(pedestal, 150, 5, string.upper(def.label), def.itemId, Kit.C.hazard, 60)

	-- installTemplates just ran (createGallery), so this always has something
	-- to clone -- the assert catches a future caller that forgets that order.
	local assembly = assert(ImportedNukeMeshes.build(def), `no template installed for {def.itemId}`)
	assembly.Parent = gallery
	placeOnPedestal(assembly, origin * CFrame.new(x, GROUND_Y, z))
end

local function buildHeader(gallery: Model, origin: CFrame, count: number)
	local sign = Kit.build(gallery, origin, {
		name = "GallerySign",
		pos = { 0, GROUND_Y + 4.5, LAND_DEPTH / 2 - 1.5 },
		size = { 26, 4.5, 0.6 },
		color = Kit.C.hazard,
		material = "Metal",
		canCollide = false,
	})
	Kit.surfaceText(sign, Enum.NormalId.Front, `MODEL YARD  /  {count} READY`, Kit.C.hazardBlack, true)
	Kit.surfaceText(sign, Enum.NormalId.Back, `MODEL YARD  /  {count} READY`, Kit.C.hazardBlack, true)
end

local function createGallery(origin: CFrame): Model
	-- Elevated-context write: rebuilds the 16 template Models this whole
	-- catalogue integration clones from (see the header). Must happen before
	-- buildStand below, which relies on a template already existing to clone.
	ImportedNukeMeshes.installTemplates(ReplicatedStorage.Shared.ItemModels)

	local gallery = Instance.new("Model")
	gallery.Name = NAME
	Kit.stamp(gallery, BUILDER_SOURCE, BUILDER_VERSION)
	gallery:SetAttribute("SpawnBaseYard", true)

	buildTrim(gallery, origin)
	for index, def in MODELS do
		buildStand(gallery, origin, def, index, MODEL_COUNT)
	end
	buildHeader(gallery, origin, MODEL_COUNT)

	return gallery
end

function ImportedNukeYard.build(origin: CFrame, parent: Instance?): Model
	local gallery = createGallery(origin)
	gallery.Parent = parent or Workspace
	return gallery
end

function ImportedNukeYard.rebuild(origin: CFrame, parent: Instance?): Model
	local target = parent or Workspace:FindFirstChild("BaseCamp") or Workspace
	local gallery = Kit.swap(NAME, function()
		return createGallery(origin)
	end, target) :: Model

	if target ~= Workspace then
		local duplicate = Workspace:FindFirstChild(NAME)
		if duplicate then
			duplicate:Destroy()
		end
	end

	print(`[build] model yard rebuilt — {MODEL_COUNT} imported nuke model(s)`)
	return gallery
end

function ImportedNukeYard.remove(parent: Instance?): boolean
	local target = parent or Workspace
	local gallery = target:FindFirstChild(NAME)
	if gallery == nil then
		return false
	end
	gallery:Destroy()
	print("[build] model yard removed")
	return true
end

return ImportedNukeYard
