--!strict
--[[
	ModelGallery.luau — temporary editor-only land for reviewing item art.

	    require(game.ServerScriptService.Server.build.ModelGallery).rebuild()
	    require(game.ServerScriptService.Server.build.ModelGallery).remove()

	THIS IS NOT PART OF World.rebuild() AND NOTHING REQUIRES IT AT BOOT. It is a
	workbench beside the live map, not shipped game geometry. Run rebuild after adding
	an ItemModels factory and every catalogued item with a real model gets a labelled
	stand automatically. Run remove before saving/publishing if the lot is not wanted
	in the place file.

	The default lot sits west of the plot ring and meets its apron through the empty
	walkway between plots 1 and 6. Its footprint is derived from Hub.PLAZA and
	Plots.PAD, so moving the base moves the preview lot instead of leaving it behind.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local ItemModels = require(Shared.ItemModels)

local Hub = require(script.Parent.Hub)
local Kit = require(script.Parent.Kit)
local Plots = require(script.Parent.Plots)

local ModelGallery = {}

local NAME = "ModelGallery_TEMP"
local BUILDER_SOURCE = "src/server/build/ModelGallery.luau"
local BUILDER_VERSION = 2

local LAND_SIZE = 66
local LAND_THICKNESS = 4
local BRIDGE_GAP = 8
local BRIDGE_WIDTH = 12
local GRID_COLUMNS = 8
local GRID_SPACING = 7
local PEDESTAL_TOP = 2.5
local MAX_MODEL_SIZE = 3.6

-- The west edge of the apron wrapped around the plaza. The lot stops BRIDGE_GAP
-- studs before it, and the small bridge crosses only that gap.
local APRON_WEST = Hub.PLAZA.minX - Plots.PAD.depth
local LOT_EAST = APRON_WEST - BRIDGE_GAP
local DEFAULT_ORIGIN = CFrame.new(LOT_EAST - LAND_SIZE / 2, Hub.PLAZA.topY, (Hub.PLAZA.minZ + Hub.PLAZA.maxZ) / 2)

local function catalogueModels(): { any }
	local result = {}
	for _, item in Items.DEFS do
		if item.model and ItemModels.has(item.model) then
			table.insert(result, item)
		end
	end
	return result
end

local function buildLand(gallery: Model, origin: CFrame)
	Kit.build(gallery, origin, {
		name = "PreviewLand",
		pos = { 0, -LAND_THICKNESS / 2, 0 },
		size = { LAND_SIZE, LAND_THICKNESS, LAND_SIZE },
		color = Kit.C.baseTileDark,
		material = "Concrete",
	})

	-- Hazard-yellow trim makes the temporary footprint obvious in Studio and prevents
	-- it from being mistaken for a seventh player plot. Matte, like the real world --
	-- this lot is dev-only (never built by World.rebuild) but there is no reason for it
	-- to be the one Neon thing left in the codebase.
	for _, edge in {
		{ pos = { 0, 0.12, -LAND_SIZE / 2 + 0.5 }, size = { LAND_SIZE, 0.24, 1 } },
		{ pos = { 0, 0.12, LAND_SIZE / 2 - 0.5 }, size = { LAND_SIZE, 0.24, 1 } },
		{ pos = { -LAND_SIZE / 2 + 0.5, 0.12, 0 }, size = { 1, 0.24, LAND_SIZE } },
		{ pos = { LAND_SIZE / 2 - 0.5, 0.12, 0 }, size = { 1, 0.24, LAND_SIZE } },
	} do
		Kit.build(gallery, origin, {
			name = "TemporaryTrim",
			pos = edge.pos,
			size = edge.size,
			color = Kit.C.hazard,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end

	-- The default origin puts the lot west of the apron, so +X points straight at
	-- the gap between the western plots. Custom origins keep the same east-facing
	-- bridge, making the builder predictable when the yard is moved by hand.
	Kit.build(gallery, origin, {
		name = "PreviewBridge",
		pos = { LAND_SIZE / 2 + BRIDGE_GAP / 2, -0.5, 0 },
		size = { BRIDGE_GAP, 1, BRIDGE_WIDTH },
		color = Kit.C.baseTileLight,
		material = "Metal",
	})
end

local function placeOnPedestal(model: Model, target: CFrame)
	model:PivotTo(CFrame.identity)

	local size = model:GetExtentsSize()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		local requested = model:GetAttribute("GallerySize")
		local targetSize = if typeof(requested) == "number" and requested > 0 then requested else MAX_MODEL_SIZE
		model:ScaleTo(targetSize / longest)
	end

	model:PivotTo(target * ItemModels.rotation(model, "Gallery"))
	local bounds, extent = model:GetBoundingBox()
	local bottom = bounds.Position.Y - extent.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, PEDESTAL_TOP - bottom + 0.08, 0))
end

local function buildStand(gallery: Model, origin: CFrame, item: any, index: number, total: number)
	local columns = math.min(GRID_COLUMNS, math.max(1, total))
	local rows = math.ceil(total / GRID_COLUMNS)
	local row = math.floor((index - 1) / GRID_COLUMNS) + 1
	local column = ((index - 1) % GRID_COLUMNS) + 1
	local rowCount = if row < rows then GRID_COLUMNS else total - (rows - 1) * GRID_COLUMNS

	-- Centre every row independently, including a partially-filled last row.
	local x = (column - (rowCount + 1) / 2) * GRID_SPACING
	local z = (row - (rows + 1) / 2) * GRID_SPACING
	if rows == 1 then
		x = (column - (columns + 1) / 2) * GRID_SPACING
	end

	local pedestal = Kit.build(gallery, origin, {
		name = `Stand_{item.id}`,
		pos = { x, PEDESTAL_TOP / 2, z },
		size = { 4.5, PEDESTAL_TOP, 4.5 },
		color = Kit.C.plazaWarm,
		material = "Marble",
		attributes = {
			ItemId = item.id,
			ModelKey = item.model,
		},
	})

	Kit.billboard(pedestal, 180, 3.7, string.upper(item.name), `{item.id} / {item.model}`, Kit.C.hazard, 80)

	local itemModel = ItemModels.create(item.model)
	if itemModel then
		itemModel.Name = `Item_{item.id}`
		itemModel:SetAttribute("ItemId", item.id)
		itemModel.Parent = gallery
		placeOnPedestal(itemModel, origin * CFrame.new(x, 0, z))
	end
end

local function buildHeader(gallery: Model, origin: CFrame, count: number)
	local sign = Kit.build(gallery, origin, {
		name = "GallerySign",
		pos = { 0, 4.5, LAND_SIZE / 2 - 1.5 },
		size = { 30, 5, 0.6 },
		color = Kit.C.hazard,
		material = "Metal",
		canCollide = false,
	})
	Kit.surfaceText(sign, Enum.NormalId.Front, `MODEL YARD  /  {count} READY`, Kit.C.hazardBlack, true)
	Kit.surfaceText(sign, Enum.NormalId.Back, `MODEL YARD  /  {count} READY`, Kit.C.hazardBlack, true)
end

local function createGallery(origin: CFrame): Model
	local gallery = Instance.new("Model")
	gallery.Name = NAME
	Kit.stamp(gallery, BUILDER_SOURCE, BUILDER_VERSION)
	gallery:SetAttribute("Temporary", true)

	buildLand(gallery, origin)
	local modelItems = catalogueModels()
	for index, item in modelItems do
		buildStand(gallery, origin, item, index, #modelItems)
	end
	buildHeader(gallery, origin, #modelItems)

	return gallery
end

function ModelGallery.build(origin: CFrame?, parent: Instance?): Model
	local gallery = createGallery(origin or DEFAULT_ORIGIN)
	gallery.Parent = parent or Workspace
	return gallery
end

function ModelGallery.rebuild(origin: CFrame?, parent: Instance?): Model
	local gallery = Kit.swap(NAME, function()
		return createGallery(origin or DEFAULT_ORIGIN)
	end, parent) :: Model
	print(`[build] temporary model gallery rebuilt — {#catalogueModels()} item model(s)`)
	return gallery
end

function ModelGallery.remove(parent: Instance?): boolean
	local target = parent or Workspace
	local gallery = target:FindFirstChild(NAME)
	if gallery == nil then
		return false
	end
	gallery:Destroy()
	print("[build] temporary model gallery removed")
	return true
end

return ModelGallery
