--!strict
--[[
	BottleCap.luau — the first real catalogue model.

	This is deliberately built from Roblox primitives instead of an uploaded MeshId.
	It stays versioned with the game, cannot lose its asset permission, and can be
	instantiated both for the live haul and for exhibition pedestals. Twenty-one
	individual crimps give the silhouette the same scalloped edge as a crown cap;
	three are displaced to sell the catalogue's "bent double" description.

	Authored around the origin with the printed face pointing +Y. Callers own its
	placement and should move the complete Model with PivotTo.
]]

local BottleCap = {}

local CRIMP_COUNT = 21
local CYLINDER_UP = CFrame.Angles(0, 0, math.rad(90))

local SILVER = Color3.fromHex("AEB4B8")
local SILVER_LIGHT = Color3.fromHex("D7DBDD")
local SILVER_DARK = Color3.fromHex("666C70")
local OXIDATION = Color3.fromHex("75684F")
local PRINT = Color3.fromHex("315B61")

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

local function addLogo(face: BasePart)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "FadedLogo"
	-- A cylinder's circular caps are Left/Right before its CFrame rotation. The
	-- +X cap becomes the upward face after CYLINDER_UP.
	surface.Face = Enum.NormalId.Right
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 80
	surface.LightInfluence = 0.35
	surface.Parent = face

	local mark = Instance.new("TextLabel")
	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromScale(0.62, 0.3)
	mark.BackgroundTransparency = 1
	mark.Font = Enum.Font.GothamBold
	mark.Text = "DNC"
	mark.TextColor3 = PRINT
	mark.TextScaled = true
	mark.TextTransparency = 0.48
	mark.Rotation = -8
	mark.Parent = surface
end

function BottleCap.create(): Model
	local model = Instance.new("Model")
	model.Name = "BottleCap"
	model:SetAttribute("ItemModel", "BottleCap")
	model:SetAttribute("DisplayName", "Bottle Cap")
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(24), 0, math.rad(10)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(14), math.rad(25), math.rad(-8)))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(28), math.rad(25), math.rad(-10)))

	-- The dark underside peeks through between the crimps and keeps the cap from
	-- reading as one flat silver coin when it spins out of the soil.
	local underside = basePart(
		"Underside",
		Vector3.new(0.13, 1.58, 1.58),
		CFrame.new(0, -0.055, 0) * CYLINDER_UP,
		SILVER_DARK,
		Enum.PartType.Cylinder
	)
	underside.Parent = model

	local shell = basePart(
		"Shell",
		Vector3.new(0.19, 1.64, 1.64),
		CFrame.new(0, 0.015, 0) * CYLINDER_UP,
		SILVER,
		Enum.PartType.Cylinder
	)
	shell.Parent = model

	-- Crown caps conventionally carry 21 teeth. The ellipsoids overlap the shell,
	-- leaving only their outer lobes visible and producing a rounded pressed-metal
	-- flute without relying on external mesh data.
	for index = 1, CRIMP_COUNT do
		local angle = ((index - 1) / CRIMP_COUNT) * math.pi * 2
		local radial = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local radius = 0.79
		local y = 0.005
		local bend = 0
		local color = if index % 5 == 0 then SILVER_LIGHT else SILVER

		-- One crushed patch gives this specific collectible its story instead of
		-- producing a generic factory-new cap. Adjacent teeth move as a group so the
		-- damage reads as a dent, not random assembly error.
		if index == 12 then
			radius = 0.72
			y = -0.09
			bend = -18
			color = OXIDATION
		elseif index == 11 or index == 13 then
			radius = 0.75
			y = -0.045
			bend = -10
			color = SILVER_DARK
		end

		local position = radial * radius + Vector3.new(0, y, 0)
		local orientation = CFrame.lookAt(position, Vector3.new(0, y, 0), Vector3.yAxis)
			* CFrame.Angles(math.rad(bend), 0, 0)
		local crimp = basePart(
			`Crimp{index}`,
			Vector3.new(0.17, 0.24, 0.37),
			orientation,
			color,
			Enum.PartType.Ball
		)
		crimp.Parent = model
	end

	-- The inset printed face is slightly out of plane with the shell. Along with
	-- the crushed teeth, that tiny asymmetry catches highlights like bent sheet
	-- metal while keeping the cap readable at its small in-game scale.
	local face = basePart(
		"PrintedFace",
		Vector3.new(0.075, 1.46, 1.46),
		CFrame.new(0.012, 0.132, -0.01)
			* CFrame.Angles(math.rad(-1.8), 0, math.rad(2.4))
			* CYLINDER_UP,
		SILVER_LIGHT,
		Enum.PartType.Cylinder
	)
	face.Parent = model
	addLogo(face)

	-- A shallow oxidized crease makes the dent legible even under flat lighting.
	local crease = basePart(
		"DentCrease",
		Vector3.new(0.32, 0.025, 0.075),
		CFrame.new(-0.49, 0.181, -0.18) * CFrame.Angles(0, math.rad(-18), math.rad(4)),
		OXIDATION,
		Enum.PartType.Ball
	)
	crease.Material = Enum.Material.SmoothPlastic
	crease.Parent = model

	model:PivotTo(CFrame.new())
	return model
end

return BottleCap
