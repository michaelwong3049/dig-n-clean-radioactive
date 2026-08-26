--!strict
--[[
	SteelRod.luau — a short, ribbed reinforcing-steel offcut.

	The reference's diagonal raised pattern is approximated with closely spaced,
	tilted metal collars over a continuous dark core. Flat end caps expose the cut
	faces, while restrained highlights and oxidation keep it readable at item scale.

	Authored along the X axis just above Y = 0. Callers own placement and move the
	complete Model with PivotTo.
]]

local SteelRod = {}

local RIDGE_COUNT = 19
local LENGTH = 3.25
local CORE_RADIUS = 0.11
local CENTRE_Y = 0.18

local STEEL = Color3.fromHex("555E63")
local STEEL_LIGHT = Color3.fromHex("818A8E")
local STEEL_SHADOW = Color3.fromHex("2F373B")
local OXIDATION = Color3.fromHex("684A3E")

local function basePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.Metal
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function addCore(model: Model)
	local core = basePart(
		"SteelCore",
		Vector3.new(LENGTH, CORE_RADIUS * 2, CORE_RADIUS * 2),
		CFrame.new(0, CENTRE_Y, 0),
		STEEL,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	core.Parent = model

	-- A narrow intersecting cylinder leaves only a subtle bright strip visible
	-- along the upper surface, preventing the dark rod from reading as rubber.
	local highlight = basePart(
		"LengthwiseHighlight",
		Vector3.new(LENGTH - 0.12, 0.075, 0.075),
		CFrame.new(0, CENTRE_Y + 0.075, -0.015),
		STEEL_LIGHT,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	highlight.Parent = model
end

local function addRidges(model: Model)
	for index = 1, RIDGE_COUNT do
		local alpha = (index - 1) / (RIDGE_COUNT - 1)
		local x = -LENGTH / 2 + 0.13 + alpha * (LENGTH - 0.26)
		local ridge = basePart(
			`DiagonalRidge{index}`,
			Vector3.new(0.045, 0.285, 0.285),
			CFrame.new(x, CENTRE_Y, 0) * CFrame.Angles(0, 0, math.rad(24)),
			if index % 4 == 0 then STEEL_LIGHT else STEEL_SHADOW,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		ridge.Reflectance = 0.03
		ridge.Parent = model
	end
end

local function addEnds(model: Model)
	for _, side in { -1, 1 } do
		local cutFace = basePart(
			if side < 0 then "CutFaceLeft" else "CutFaceRight",
			Vector3.new(0.035, CORE_RADIUS * 1.88, CORE_RADIUS * 1.88),
			CFrame.new(side * (LENGTH / 2 + 0.012), CENTRE_Y, 0),
			STEEL_LIGHT,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		cutFace.Parent = model

		local cutCentre = basePart(
			if side < 0 then "CutCentreLeft" else "CutCentreRight",
			Vector3.new(0.042, 0.07, 0.07),
			CFrame.new(side * (LENGTH / 2 + 0.032), CENTRE_Y, 0),
			STEEL_SHADOW,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		cutCentre.Parent = model
	end
end

local function addWear(model: Model)
	for index, scar in {
		{ -1.08, 0.305, -0.01, 0.11 },
		{ -0.28, 0.31, 0.025, 0.08 },
		{ 0.54, 0.308, -0.02, 0.12 },
		{ 1.19, 0.304, 0.018, 0.07 },
	} do
		local oxidation = basePart(
			`OxidationScar{index}`,
			Vector3.new(scar[4], 0.018, 0.045),
			CFrame.new(scar[1], scar[2], scar[3]) * CFrame.Angles(0, math.rad(15 * index), 0),
			OXIDATION,
			Enum.Material.CorrodedMetal,
			nil
		)
		oxidation.Parent = model
	end
end

function SteelRod.create(): Model
	local model = Instance.new("Model")
	model.Name = "SteelRod"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "SteelRod")
	model:SetAttribute("DisplayName", "Steel Rod")
	model:SetAttribute("GallerySize", 3.25)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(6), math.rad(28), math.rad(22)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(0, math.rad(18), math.rad(-8)))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(8), math.rad(-24), math.rad(-16)))

	addCore(model)
	addRidges(model)
	addEnds(model)
	addWear(model)
	return model
end

return SteelRod
