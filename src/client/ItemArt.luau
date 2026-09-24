--!strict
--[[
	ItemArt.luau — a bag entry's model in a ViewportFrame, for the panels that draw one.

	Lifted out of TraderPanel when the Quarantine Locker's panel (LockerPanel) became the
	second reader, so the two draw a find the same way: the real model once it is
	identified (the payload only carries `itemId` then, CarryService.describe), the slag
	lump ItemCrust.lump seeds on its uid while it is still "???".

	Same camera recipe as the shop cards and the index: a narrow lens from a little right
	of front and above, and a low ambient under a warm key so rarities keep their colour.
	A viewport's model is built once per item (`ArtKey`), not on every 10 Hz
	StationState tick.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local ItemModels = require(Shared.ItemModels)
local ItemCrust = require(Shared.ItemCrust)
local ItemFx = require(Shared.ItemFx)

local ItemArt = {}

local ART_FOV = 30
local ART_MARGIN = 1.12
local ART_FROM = Vector3.new(0.45, 0.3, 1).Unit
local ART_LIGHT = {
	ambient = Color3.fromRGB(90, 92, 98),
	color = Color3.fromRGB(255, 248, 235),
	direction = Vector3.new(-1, -1, -1),
}

local BOX_CORNERS = {}
for _, x in { -1, 1 } do
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(BOX_CORNERS, Vector3.new(x, y, z))
		end
	end
end

--- A transparent ViewportFrame named "Model" filling `parent`, with its own camera.
function ItemArt.newViewport(parent: Instance): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Model"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = ART_LIGHT.ambient
	viewport.LightColor = ART_LIGHT.color
	viewport.LightDirection = ART_LIGHT.direction
	viewport.Parent = parent

	local camera = Instance.new("Camera")
	camera.FieldOfView = ART_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

--- Aim `camera` so `model` fills a well `aspect` wide per unit tall. The box is measured
--- in the camera's own axes (StationController.frameArt's reasoning), so a three-quarter
--- view is framed tight rather than to the model's loose aligned box.
local function frameModel(camera: Camera, model: Model, aspect: number)
	local look = CFrame.lookAt(Vector3.zero, -ART_FROM, Vector3.yAxis)
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local half = part.Size / 2
			for _, c in BOX_CORNERS do
				local point = look:PointToObjectSpace(part.CFrame * (half * c))
				lo = lo:Min(point)
				hi = hi:Max(point)
			end
		end
	end
	if lo.X > hi.X then
		return
	end
	local mid = (lo + hi) / 2
	local extent = (hi - lo) / 2
	local tanHalf = math.tan(math.rad(ART_FOV) / 2)
	local reach = math.max(extent.Y / tanHalf, extent.X / (tanHalf * aspect)) * ART_MARGIN
	camera.CFrame = look * CFrame.new(mid.X, mid.Y, hi.Z + reach)
end

--- A fresh model for one bag entry: the item itself once it is identified, its crust
--- until then. ItemFx comes off (its lights and particles do not render in a viewport).
local function modelFor(item: any): Model
	local model: Model? = nil
	if item.identified and type(item.itemId) == "string" and Items.has(item.itemId) then
		local def = Items.get(item.itemId)
		model = ItemModels.create(def.model, item.itemId)
		if model then
			CollectionService:RemoveTag(model, ItemFx.TAG)
			for _, node in model:GetDescendants() do
				CollectionService:RemoveTag(node, ItemFx.TAG)
			end
			model:PivotTo(ItemModels.rotation(model, "Gallery"))
		end
	end
	if model == nil and not item.identified then
		model = ItemCrust.lump(item.rarity, item.uid)
	end
	if model == nil then
		local def = if item.rarity then Rarity.DEFS[item.rarity] else nil
		local block = Instance.new("Part")
		block.Name = "Placeholder"
		block.Size = Vector3.one
		block.Color = if def then def.color else Color3.fromHex("9AA0A6")
		block.Material = Enum.Material.SmoothPlastic
		local holder = Instance.new("Model")
		block.Parent = holder
		holder.PrimaryPart = block
		model = holder
	end
	return model :: Model
end

--- Swap `item`'s model into `viewport`, unless it is already showing it.
function ItemArt.paint(viewport: ViewportFrame, item: any, aspect: number)
	local key = `{item.uid}/{item.itemId or "crust"}`
	if viewport:GetAttribute("ArtKey") == key then
		return
	end
	viewport:SetAttribute("ArtKey", key)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	local model = modelFor(item)
	model.Parent = viewport
	frameModel(viewport.CurrentCamera :: Camera, model, aspect)
end

--- Empty `viewport`.
function ItemArt.clear(viewport: ViewportFrame)
	if viewport:GetAttribute("ArtKey") == nil then
		return
	end
	viewport:SetAttribute("ArtKey", nil)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
end

return ItemArt
