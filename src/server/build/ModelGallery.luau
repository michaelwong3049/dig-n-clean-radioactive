--!strict
--[[
	ModelGallery.luau — the permanent item-model yard inside the spawn base.

	    require(game.ServerScriptService.Server.build.ModelGallery).rebuild()
	    require(game.ServerScriptService.Server.build.ModelGallery).remove()

	BaseCamp builds this automatically, so World.rebuild() always ships every
	catalogued item with a real ItemModels factory on a labelled stand. The yard
	is a self-contained floating platform (it builds its own floor + trim) parked
	just outside the base's circular perimeter wall, due west of Plots.RING_CENTER
	-- off to the side of the playable map rather than competing for space with the
	shops, central aisle, Stage 1 entrance, or the six player plots.
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

local NAME = "ModelYard"
local BUILDER_SOURCE = "src/server/build/ModelGallery.luau"
local BUILDER_VERSION = 8

local GRID_COLUMNS = 8
-- Wide enough that a model at the full GallerySize (9.18 studs, whichever axis
-- lands horizontal on the pedestal) keeps a real gap from its neighbour.
-- LAND_WIDTH/LAND_DEPTH/YARD_RADIUS below all derive from this, so the yard's
-- footprint and placement grow to match automatically if this ever changes.
local GRID_SPACING = 16
local PEDESTAL_TOP = 2.5
local MAX_MODEL_SIZE = 3.6

-- EDGE_MARGIN keeps the outer rows/columns of stands clear of the trim; HEADER_CLEARANCE
-- is extra depth behind the last row so it doesn't crowd the GallerySign.
local EDGE_MARGIN = 6
local HEADER_CLEARANCE = 6

local function catalogueModels(): { any }
	local result = {}
	for _, item in Items.DEFS do
		if item.model and ItemModels.has(item.model) then
			table.insert(result, item)
		end
	end
	return result
end

-- feat/nuke-arsenal-retheme collapsed the catalogue onto 7 shared model factories, but
-- every item still gets its own labelled stand -- the yard's footprint scales off the
-- CATALOGUE size (Items.DEFS), not the model count, so it grows automatically as items
-- are added instead of needing another manual bump. Computed once at require time since
-- the catalogue is static for the life of the server.
local MODEL_COUNT = #catalogueModels()
local GRID_ROWS = math.max(1, math.ceil(MODEL_COUNT / GRID_COLUMNS))

local LAND_WIDTH = math.max(46, GRID_COLUMNS * GRID_SPACING + EDGE_MARGIN * 2)
local LAND_DEPTH = math.max(36, GRID_ROWS * GRID_SPACING + EDGE_MARGIN * 2 + HEADER_CLEARANCE)
local LAND_THICKNESS = 0.12

-- WALL_CLEARANCE mirrors Scenery.luau's private WALL_THICKNESS (8): the base's
-- curved perimeter wall sits at radius Plots.RING_OUTER + WALL_THICKNESS/2, so this
-- reproduces that same offset rather than importing an unexported local. YARD_GAP is
-- extra breathing room past the wall face so the platform's own trim clears it.
local WALL_CLEARANCE = 8
local YARD_GAP = 20

-- Anchor the yard due west of the ring's own centre, just outside the perimeter
-- wall, rather than inside the plaza footprint. It is a self-contained floating
-- platform (buildLand gives it its own floor), so nothing needs to exist under it.
-- BASE_OFFSET lets a caller that relocates BaseCamp carry the yard with it.
local YARD_RADIUS = Plots.RING_OUTER + WALL_CLEARANCE / 2 + YARD_GAP + LAND_WIDTH / 2
local DEFAULT_ORIGIN = CFrame.new(Plots.RING_CENTER.x - YARD_RADIUS, Hub.PLAZA.topY, Plots.RING_CENTER.z)
local BASE_OFFSET = Hub.CAMP_ORIGIN:ToObjectSpace(DEFAULT_ORIGIN)

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

	-- `GetScale()` multiplier: `ScaleTo` is ABSOLUTE relative to the model's TRUE
	-- native (unscaled) size, not whatever its current visual size happens to be
	-- (see NukeBase's own header, and Shops.luau:877's `ScaleTo(GetScale() * f)`
	-- for the same gotcha already solved once elsewhere in this repo). Every
	-- imported-mesh template arrives here ALREADY pre-scaled to NATURAL_SIZE by
	-- the migration script, so `targetSize / longest` alone would divide the
	-- target by that prior scale a second time -- multiplying by the model's
	-- current `GetScale()` compounds onto whatever scale it already had instead
	-- of overwriting it (a no-op for the cube-fallback/native-scale case).
	local size = model:GetExtentsSize()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		local requested = model:GetAttribute("GallerySize")
		local targetSize = if typeof(requested) == "number" and requested > 0 then requested else MAX_MODEL_SIZE
		model:ScaleTo(model:GetScale() * (targetSize / longest))
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

	-- Height offset of 15 clears even the tallest item (old_compass, ~10.6 studs
	-- of top clearance from pedestal-centre at the current GallerySize) with
	-- comfortable margin, so the tag reads as "above the model" rather than
	-- overlapping it. Smaller text (14/10 vs. the shared default 22/14) reads
	-- as a label, not a headline -- ModelGallery is the only caller that opts
	-- into non-default sizes, see Kit.billboard.
	Kit.billboard(pedestal, 120, 15, string.upper(item.name), `{item.id} / {item.model}`, Kit.C.hazard, 80, 14, 10)

	local itemModel = ItemModels.create(item.model, item.id)
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
	-- The permanent yard belongs to BaseCamp. Older command-bar usage built a second
	-- copy directly under Workspace, which put two of every model in the same place.
	local target = parent or Workspace:FindFirstChild("BaseCamp") or Workspace
	local targetOrigin = origin
	local existing = target:FindFirstChild(NAME)
	if targetOrigin == nil and existing then
		local floor = existing:FindFirstChild("YardFloor")
		if floor and floor:IsA("BasePart") then
			-- Preserve the platform's near corner when changing the yard dimensions.
			targetOrigin = floor.CFrame
				* CFrame.new((LAND_WIDTH - floor.Size.X) / 2, -floor.Size.Y / 2, (LAND_DEPTH - floor.Size.Z) / 2)
		end
	end

	local gallery = Kit.swap(NAME, function()
		return createGallery(targetOrigin or DEFAULT_ORIGIN)
	end, target) :: Model

	if target ~= Workspace then
		local duplicate = Workspace:FindFirstChild(NAME)
		if duplicate then
			duplicate:Destroy()
		end
	end

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
