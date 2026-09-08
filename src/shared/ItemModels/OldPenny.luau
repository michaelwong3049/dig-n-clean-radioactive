--!strict
-- A worn copper penny, upright in XY, with raised rims and a geometric wheat reverse.
-- All face details are physical metal so they scale and wash with the coin.
local OldPenny = {}

local COPPER = Color3.fromHex("9B5838")
local EDGE = Color3.fromHex("6B3929")
local RELIEF = Color3.fromHex("BF8053")
local PATINA = Color3.fromHex("705541")
local CENTER_Y = 1.1

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

function OldPenny.create(): Model
	local model = Instance.new("Model")
	model.Name = "OldPenny"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "OldPenny")
	model:SetAttribute("DisplayName", "Old Penny")
	model:SetAttribute("GallerySize", 2.4)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(-10), math.rad(20), math.rad(7)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(-8), math.rad(-18), 0))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(-8), math.rad(-20), 0))

	-- Roblox cylinders use local X as their axis; turn that axis toward the viewer.
	local cylinder = CFrame.Angles(0, math.rad(90), 0)
	part(model, "CoinBlank", Vector3.new(0.15, 2.2, 2.2), CFrame.new(0, CENTER_Y, 0) * cylinder, EDGE, Enum.PartType.Cylinder)
	for _, side in { -1, 1 } do
		part(model, `Face{side}`, Vector3.new(0.025, 2.08, 2.08), CFrame.new(0, CENTER_Y, side * 0.076) * cylinder, COPPER, Enum.PartType.Cylinder)
		-- Continuous raised rims, with a slightly uneven aged finish around the edge.
		for index = 1, 48 do
			local angle = (index - 1) * math.pi * 2 / 48
			local frame = CFrame.new(math.cos(angle) * 1.04, CENTER_Y + math.sin(angle) * 1.04, side * 0.093)
				* CFrame.Angles(0, 0, angle)
			part(model, `Rim{side}_{index}`, Vector3.new(0.06, 0.143, 0.036), frame, if index % 7 == 0 then COPPER else RELIEF)
		end
	end

	-- A large embossed numeral is readable even when held at gameplay scale.
	part(model, "OneStem", Vector3.new(0.15, 0.86, 0.036), CFrame.new(0.05, 1.27, 0.104), RELIEF)
	part(model, "OneFlag", Vector3.new(0.31, 0.14, 0.036), CFrame.new(-0.04, 1.65, 0.104) * CFrame.Angles(0, 0, math.rad(30)), RELIEF)
	part(model, "OneFoot", Vector3.new(0.48, 0.12, 0.036), CFrame.new(0.05, 0.86, 0.104), RELIEF)
	-- Two wheat ears frame the numeral; a matching pair decorates the reverse.
	for _, face in { -1, 1 } do
		for _, side in { -1, 1 } do
			part(model, `WheatStem{face}_{side}`, Vector3.new(0.035, 0.95, 0.028), CFrame.new(side * 0.65, 1.15, face * 0.107) * CFrame.Angles(0, 0, side * math.rad(-12)), RELIEF)
			for index = 1, 5 do
				local y = 0.83 + index * 0.14
				local x = side * (0.59 + (y - 0.83) * 0.21)
				part(model, `WheatGrain{face}_{side}_{index}`, Vector3.new(0.12, 0.23, 0.035), CFrame.new(x, y, face * 0.118) * CFrame.Angles(0, 0, side * math.rad(38)), RELIEF, Enum.PartType.Ball)
			end
		end
	end
	-- Small rubbed patches stay brown, distinct from the removable green grime.
	for index, detail in { Vector3.new(-0.32, 0.48, 0.092), Vector3.new(0.45, 1.83, 0.092), Vector3.new(-0.28, 1.6, -0.092) } do
		part(model, `Wear{index}`, Vector3.new(0.22, 0.075, 0.012), CFrame.new(detail) * CFrame.Angles(0, 0, math.rad(index * 29)), PATINA, Enum.PartType.Ball)
	end

	return model
end

return OldPenny
