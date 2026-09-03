--!strict
--[[
	WindUpFlashlight.luau — a heavy black cylindrical flashlight.

	Stepped housings form the flared head from the supplied reference. A recessed
	silver reflector, glass lens, ribbed bezel, textured handle, tail cap, and raised
	top switch keep the silhouette readable without an uploaded mesh or texture.

	Authored horizontally along the X axis, lens facing -X, with the head resting just
	above Y = 0. Callers own placement and move the complete Model with PivotTo.
]]

local WindUpFlashlight = {}

local CENTRE_Y = 0.7
local GRIP_RIB_COUNT = 14
local GRIP_RING_COUNT = 15
local BEZEL_RIB_COUNT = 20

local BLACK = Color3.fromHex("151719")
local BLACK_LIGHT = Color3.fromHex("24272A")
local BLACK_MID = Color3.fromHex("0E1011")
local BLACK_SHADOW = Color3.fromHex("08090A")
local REFLECTOR = Color3.fromHex("D7DCDD")
local REFLECTOR_LIGHT = Color3.fromHex("F4F6F6")
local REFLECTOR_SHADOW = Color3.fromHex("848D91")
local LENS = Color3.fromHex("DCECEF")
local BULB = Color3.fromHex("FFF4CE")

local function basePart(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function cylinder(
	model: Model,
	name: string,
	x: number,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material
): Part
	return basePart(
		model,
		name,
		Vector3.new(length, diameter, diameter),
		CFrame.new(x, CENTRE_Y, 0),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function addHandle(model: Model)
	local core = cylinder(model, "HandleCore", 0.72, 2.82, 0.67, BLACK, Enum.Material.SmoothPlastic)
	core.Reflectance = 0.025

	-- Long, shallow rails crossed by narrow collars approximate the reference's
	-- fine molded grip texture without relying on an image texture.
	for index = 0, GRIP_RIB_COUNT - 1 do
		local angle = (index / GRIP_RIB_COUNT) * math.pi * 2
		local radius = 0.342
		local rib = basePart(
			model,
			`GripRib{index + 1}`,
			Vector3.new(2.18, 0.024, 0.04),
			CFrame.new(0.84, CENTRE_Y + math.cos(angle) * radius, math.sin(angle) * radius)
				* CFrame.Angles(angle, 0, 0),
			if index % 3 == 0 then BLACK_LIGHT else BLACK_MID,
			Enum.Material.SmoothPlastic,
			nil
		)
		rib.Parent = model
	end

	for index = 1, GRIP_RING_COUNT do
		local alpha = (index - 1) / (GRIP_RING_COUNT - 1)
		local x = -0.2 + alpha * 2.08
		cylinder(
			model,
			`GripCrossBand{index}`,
			x,
			0.018,
			0.706,
			if index % 2 == 0 then BLACK_MID else BLACK_LIGHT,
			Enum.Material.SmoothPlastic
		)
	end

	-- A thick rear collar and slimmer end ring reproduce the screw-on tail cap.
	cylinder(model, "TailCap", 2.16, 0.28, 0.75, BLACK_MID, Enum.Material.SmoothPlastic)
	cylinder(model, "TailCapRing", 2.31, 0.055, 0.72, BLACK_SHADOW, Enum.Material.SmoothPlastic)
	cylinder(model, "TailFace", 2.345, 0.025, 0.64, BLACK_LIGHT, Enum.Material.SmoothPlastic)
end

local function addHead(model: Model)
	-- Overlapping steps read as one molded flare at item scale.
	cylinder(model, "Neck", -0.78, 0.44, 0.76, BLACK, Enum.Material.SmoothPlastic)
	cylinder(model, "FlareRear", -1.02, 0.3, 0.89, BLACK, Enum.Material.SmoothPlastic)
	cylinder(model, "FlareMiddle", -1.2, 0.32, 1.06, BLACK_MID, Enum.Material.SmoothPlastic)
	cylinder(model, "HeadHousing", -1.42, 0.38, 1.23, BLACK, Enum.Material.SmoothPlastic)
	cylinder(model, "Bezel", -1.64, 0.28, 1.38, BLACK_SHADOW, Enum.Material.SmoothPlastic)

	-- Raised longitudinal ribs provide the deep grip around the reference's bezel.
	for index = 0, BEZEL_RIB_COUNT - 1 do
		local angle = (index / BEZEL_RIB_COUNT) * math.pi * 2
		local radius = 0.7
		basePart(
			model,
			`BezelRib{index + 1}`,
			Vector3.new(0.3, 0.052, 0.09),
			CFrame.new(-1.63, CENTRE_Y + math.cos(angle) * radius, math.sin(angle) * radius)
				* CFrame.Angles(angle, 0, 0),
			if index % 2 == 0 then BLACK_LIGHT else BLACK_MID,
			Enum.Material.SmoothPlastic,
			nil
		)
	end

	-- The smaller silver face leaves the dark cylinder behind it visible as an
	-- annular bezel. Layered tones suggest a concave reflector behind the lens.
	local reflector = cylinder(model, "Reflector", -1.794, 0.035, 1.13, REFLECTOR, Enum.Material.Metal)
	reflector.Reflectance = 0.35
	local reflectorWell = cylinder(
		model,
		"ReflectorWell",
		-1.817,
		0.018,
		0.68,
		REFLECTOR_SHADOW,
		Enum.Material.Metal
	)
	reflectorWell.Reflectance = 0.28
	local reflectorCentre = cylinder(
		model,
		"ReflectorCentre",
		-1.829,
		0.014,
		0.36,
		REFLECTOR_LIGHT,
		Enum.Material.Metal
	)
	reflectorCentre.Reflectance = 0.42

	local bulb = basePart(
		model,
		"Bulb",
		Vector3.new(0.17, 0.2, 0.2),
		CFrame.new(-1.855, CENTRE_Y, 0),
		BULB,
		Enum.Material.Glass,
		Enum.PartType.Ball
	)
	bulb.Transparency = 0.08
	bulb.Reflectance = 0.18
	bulb.CastShadow = false

	local lens = cylinder(model, "GlassLens", -1.875, 0.025, 1.17, LENS, Enum.Material.Glass)
	lens.Transparency = 0.68
	lens.Reflectance = 0.16
	lens.CastShadow = false
end

local function addSwitch(model: Model)
	local switchSeat = basePart(
		model,
		"SwitchSeat",
		Vector3.new(0.52, 0.1, 0.32),
		CFrame.new(-0.47, CENTRE_Y + 0.355, 0),
		BLACK_SHADOW,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	switchSeat.Reflectance = 0.02

	local switch = basePart(
		model,
		"PowerSwitch",
		Vector3.new(0.4, 0.105, 0.24),
		CFrame.new(-0.47, CENTRE_Y + 0.407, 0) * CFrame.Angles(0, 0, math.rad(-7)),
		BLACK_LIGHT,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Ball
	)
	switch.Reflectance = 0.035
end

function WindUpFlashlight.create(): Model
	local model = Instance.new("Model")
	model.Name = "WindUpFlashlight"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "WindUpFlashlight")
	model:SetAttribute("DisplayName", "Wind-Up Flashlight")
	model:SetAttribute("GallerySize", 4.1)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(8), math.rad(24), math.rad(-10)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(-4), math.rad(-26), math.rad(-7)))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(7), math.rad(-28), math.rad(-9)))

	addHandle(model)
	addHead(model)
	addSwitch(model)
	return model
end

return WindUpFlashlight
