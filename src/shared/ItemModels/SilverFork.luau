--!strict
-- A pressed silver dinner fork, upright in XY with four open tines toward +Y.
-- Primitive geometry keeps the asset portable and compatible with ItemGrime.
local SilverFork = {}

local SILVER = Color3.fromHex("C5CBCD")
local LIGHT = Color3.fromHex("E5EAEC")
local SHADOW = Color3.fromHex("929C9F")

local function part(model: Model, name: string, size: Vector3, frame: CFrame, color: Color3, shape: Enum.PartType?): Part
	local result = Instance.new("Part")
	result.Name = name
	result.Size = size
	result.CFrame = frame
	result.Color = color
	result.Material = Enum.Material.Metal
	result.Shape = shape or Enum.PartType.Block
	result.Anchored = true
	result.CanCollide = false
	result.CanQuery = false
	result.CanTouch = false
	result.TopSurface = Enum.SurfaceType.Smooth
	result.BottomSurface = Enum.SurfaceType.Smooth
	result.Parent = model
	return result
end

function SilverFork.create(): Model
	local model = Instance.new("Model")
	model.Name = "SilverFork"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "SilverFork")
	model:SetAttribute("DisplayName", "Silver Fork")
	model:SetAttribute("GallerySize", 3.5)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(-8), math.rad(16), math.rad(9)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(-6), math.rad(-18), math.rad(-9)))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(-8), math.rad(-20), math.rad(-10)))

	-- Overlapping ellipsoids make a rounded teardrop handle that narrows at the neck.
	part(model, "Handle", Vector3.new(0.43, 2.05, 0.17), CFrame.new(0, 1.025, 0), SILVER, Enum.PartType.Ball)
	part(model, "HandleInset", Vector3.new(0.25, 1.52, 0.035), CFrame.new(0, 0.93, 0.078), SHADOW, Enum.PartType.Ball)
	part(model, "HandleHighlight", Vector3.new(0.16, 1.36, 0.025), CFrame.new(0, 0.94, 0.098), LIGHT, Enum.PartType.Ball)
	part(model, "Neck", Vector3.new(0.17, 0.8, 0.12), CFrame.new(0, 1.99, 0.035) * CFrame.Angles(math.rad(7), 0, 0), SILVER)
	part(model, "Shoulder", Vector3.new(0.92, 0.64, 0.15), CFrame.new(0, 2.38, 0.08), SILVER, Enum.PartType.Ball)
	part(model, "TineRoot", Vector3.new(0.87, 0.22, 0.13), CFrame.new(0, 2.55, 0.08), SILVER)

	-- Each tine is separate above the root: all three slots remain truly open.
	for index, x in { -0.345, -0.115, 0.115, 0.345 } do
		local length = if index == 1 or index == 4 then 0.86 else 0.94
		local frame = CFrame.new(x, 2.61, 0.08) * CFrame.Angles(math.rad(7), 0, 0)
		part(model, `Tine{index}`, Vector3.new(0.14, length, 0.105), frame * CFrame.new(0, length / 2, 0), SILVER)
		part(model, `TineTip{index}`, Vector3.new(0.14, 0.20, 0.105), frame * CFrame.new(0, length, 0), LIGHT, Enum.PartType.Ball)
	end

	return model
end

return SilverFork
