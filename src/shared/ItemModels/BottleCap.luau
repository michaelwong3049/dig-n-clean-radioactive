--!strict
--[[
	BottleCap.luau — a clean, unprinted crown cap.

	The reference shape is a shallow pressed-metal crown with a broad flat face,
	rounded shoulder and a deeper fluted skirt. It is built from Roblox primitives so
	the source stays in Git and never depends on an uploaded mesh permission. Twenty-one
	vertical crimps form the industry-standard crown silhouette.

	Authored around the origin with the blank face pointing +Y. Callers own placement
	and move the complete Model with PivotTo.
]]

local BottleCap = {}

local CRIMP_COUNT = 21
local CYLINDER_UP = CFrame.Angles(0, 0, math.rad(90))

local SILVER = Color3.fromHex("D4D8DA")
local SILVER_LIGHT = Color3.fromHex("EEF0F1")
local SILVER_SHADOW = Color3.fromHex("9DA4A8")

local function basePart(name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Metal
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

function BottleCap.create(): Model
	local model = Instance.new("Model")
	model.Name = "BottleCap"
	-- Lock an identity pivot before the first rotated cylinder is parented. Without
	-- this, Roblox inherits that cylinder's orientation as the Model pivot and a
	-- later PivotTo turns the finished cap onto its edge.
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "BottleCap")
	model:SetAttribute("DisplayName", "Bottle Cap")
	model:SetAttribute("GallerySize", 2.2)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(18), 0, math.rad(7)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(12), math.rad(25), math.rad(-5)))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(18), math.rad(25), math.rad(-6)))

	-- The shadowed underside is only visible at low angles, giving the thin metal a
	-- real edge rather than letting the bright skirt blend into the ground.
	local underside = basePart(
		"Underside",
		Vector3.new(0.1, 1.24, 1.24),
		CFrame.new(0, -0.245, 0) * CYLINDER_UP,
		SILVER_SHADOW,
		Enum.PartType.Cylinder
	)
	underside.Parent = model

	-- A continuous inner skirt prevents gaps between the flutes. The crimp lobes
	-- overlap it and provide the scalloped outer silhouette.
	local skirt = basePart(
		"Skirt",
		Vector3.new(0.42, 1.24, 1.24),
		CFrame.new(0, -0.07, 0) * CYLINDER_UP,
		SILVER,
		Enum.PartType.Cylinder
	)
	skirt.Parent = model

	for index = 1, CRIMP_COUNT do
		local angle = ((index - 1) / CRIMP_COUNT) * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = radial * 0.69 + Vector3.new(0, -0.07, 0)
		local orientation = CFrame.lookAt(position, Vector3.new(0, -0.07, 0), Vector3.yAxis)
			* CFrame.Angles(math.rad(-4), 0, 0)
		local crimp = basePart(
			`Crimp{index}`,
			Vector3.new(0.15, 0.48, 0.27),
			orientation,
			SILVER,
			nil
		)
		crimp.Parent = model
	end

	-- The broad shoulder hides the tops of the individual lobes, making them read
	-- as pressed flutes descending from one continuous cap instead of attached beads.
	local shoulder = basePart(
		"Shoulder",
		Vector3.new(0.18, 1.56, 1.56),
		CFrame.new(0, 0.105, 0) * CYLINDER_UP,
		SILVER_LIGHT,
		Enum.PartType.Cylinder
	)
	shoulder.Parent = model

	-- Blank and nearly flush with the shoulder, matching the supplied unprinted cap.
	local face = basePart(
		"BlankFace",
		Vector3.new(0.065, 1.42, 1.42),
		CFrame.new(0, 0.225, 0) * CYLINDER_UP,
		SILVER,
		Enum.PartType.Cylinder
	)
	face.Parent = model

	return model
end

return BottleCap
