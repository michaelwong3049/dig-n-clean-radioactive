--!strict
--[[
	ModelGallery.luau — the permanent item-model yard inside the spawn base.

	    require(game.ServerScriptService.Server.build.ModelGallery).rebuild()
	    require(game.ServerScriptService.Server.build.ModelGallery).remove()

	BaseCamp builds this automatically, so World.rebuild() always ships every
	catalogued item with a real ItemModels factory on a labelled stand. The compact
	yard sits in the plaza's southwest corner, clear of the shops, central aisle,
	Stage 1 entrance, and the six player plots.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local ItemModels = require(Shared.ItemModels)

local Hub = require(script.Parent.Hub)
local Kit = require(script.Parent.Kit)

local ModelGallery = {}

local NAME = "ModelYard"
local BUILDER_SOURCE = "src/server/build/ModelGallery.luau"
local BUILDER_VERSION = 3

local LAND_WIDTH = 34
local LAND_DEPTH = 28
local LAND_THICKNESS = 0.12
local YARD_MARGIN = 3
local GRID_COLUMNS = 4
local GRID_SPACING = 7
local PEDESTAL_TOP = 2.5
local MAX_MODEL_SIZE = 3.6

-- Anchor the yard inside the southwest corner rather than to a bare world number.
-- BASE_OFFSET lets a caller that relocates BaseCamp carry the yard with it.
local DEFAULT_ORIGIN = CFrame.new(
	Hub.PLAZA.minX + YARD_MARGIN + LAND_WIDTH / 2,
	Hub.PLAZA.topY,
	Hub.PLAZA.minZ + YARD_MARGIN + LAND_DEPTH / 2
)
local BASE_OFFSET = Hub.CAMP_ORIGIN:ToObjectSpace(DEFAULT_ORIGIN)

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
		name = "YardFloor",
		pos = { 0, LAND_THICKNESS / 2, 0 },
		size = { LAND_WIDTH, LAND_THICKNESS, LAND_DEPTH },
		color = Kit.C.baseTileDark,
		material = "Concrete",
	})

	-- Hazard-yellow trim distinguishes the public showcase from a player plot while
	-- remaining low enough to step over from any side.
	for _, edge in {
		{ pos = { 0, 0.18, -LAND_DEPTH / 2 + 0.5 }, size = { LAND_WIDTH, 0.24, 1 } },
		{ pos = { 0, 0.18, LAND_DEPTH / 2 - 0.5 }, size = { LAND_WIDTH, 0.24, 1 } },
		{ pos = { -LAND_WIDTH / 2 + 0.5, 0.18, 0 }, size = { 1, 0.24, LAND_DEPTH } },
		{ pos = { LAND_WIDTH / 2 - 0.5, 0.18, 0 }, size = { 1, 0.24, LAND_DEPTH } },
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
		pos = { 0, 4.5, LAND_DEPTH / 2 - 1.5 },
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
	gallery:SetAttribute("SpawnBaseYard", true)

	buildLand(gallery, origin)
	local modelItems = catalogueModels()
	for index, item in modelItems do
		buildStand(gallery, origin, item, index, #modelItems)
	end
	buildHeader(gallery, origin, #modelItems)

	return gallery
end

function ModelGallery.originForBase(baseOrigin: CFrame): CFrame
	return baseOrigin * BASE_OFFSET
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
	print(`[build] model yard rebuilt — {#catalogueModels()} item model(s)`)
	return gallery
end

function ModelGallery.remove(parent: Instance?): boolean
	local target = parent or Workspace
	local gallery = target:FindFirstChild(NAME)
	if gallery == nil then
		return false
	end
	gallery:Destroy()
	print("[build] model yard removed")
	return true
end

return ModelGallery
