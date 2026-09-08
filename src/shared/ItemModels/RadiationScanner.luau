--!strict
--[[
	RadiationScanner.luau — a compact black handheld survey meter.

	The supplied reference is carried by the silhouette: a softly rounded pistol
	grip flows into a broad rear shell, while a stepped cylindrical bezel presents
	a black sensor face and an orange radiation mark. A recessed trigger, molded
	side panels, top ridge, and grip dimples keep the dark body readable without an
	uploaded mesh or texture.

	Authored upright, facing -Z, with the handle resting at Y = 0. Callers own
	placement and move the complete Model with PivotTo.
]]

local RadiationScanner = {}

local CYLINDER_FRONT = CFrame.Angles(0, math.rad(90), 0)
local CYLINDER_UP = CFrame.Angles(0, 0, math.rad(90))

local BLACK = Color3.fromHex("17191B")
local BLACK_LIGHT = Color3.fromHex("292C2F")
local BLACK_MID = Color3.fromHex("101214")
local BLACK_SHADOW = Color3.fromHex("070809")
local SENSOR_GLASS = Color3.fromHex("050607")
local TRIGGER = Color3.fromHex("34383B")
local HAZARD_ORANGE = Color3.fromHex("F59A23")

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

local function ellipsoid(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	reflectance: number?
): Part
	local part = basePart(model, name, size, cframe, color, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	part.Reflectance = reflectance or 0
	return part
end

local function frontCylinder(
	model: Model,
	name: string,
	position: Vector3,
	length: number,
	diameter: number,
	color: Color3,
	material: Enum.Material
): Part
	return basePart(
		model,
		name,
		Vector3.new(length, diameter, diameter),
		CFrame.new(position) * CYLINDER_FRONT,
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local function addGrip(model: Model)
	-- Overlapping ellipsoids produce the reference's molded, slightly back-heavy
	-- handle. The narrow shoulder disappears into the body instead of meeting it
	-- at a hard right angle.
	ellipsoid(
		model,
		"GripCore",
		Vector3.new(0.76, 2.25, 0.7),
		CFrame.new(0, 1.18, 0.24) * CFrame.Angles(math.rad(-3), 0, 0),
		BLACK,
		0.025
	)
	ellipsoid(
		model,
		"GripPalmSwell",
		Vector3.new(0.82, 1.34, 0.74),
		CFrame.new(0, 1.03, 0.29) * CFrame.Angles(math.rad(-4), 0, 0),
		BLACK_LIGHT,
		0.018
	)
	ellipsoid(
		model,
		"GripShoulder",
		Vector3.new(1.0, 1.18, 0.86),
		CFrame.new(0, 2.08, 0.15) * CFrame.Angles(math.rad(5), 0, 0),
		BLACK,
		0.025
	)

	-- A shallow cylinder gives the otherwise soft grip a stable, flat heel.
	local heel = basePart(
		model,
		"GripHeel",
		Vector3.new(0.12, 0.64, 0.64),
		CFrame.new(0, 0.09, 0.19) * CYLINDER_UP,
		BLACK_MID,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)
	heel.Reflectance = 0.02

	-- The reference has three restrained molded depressions down the grip front.
	-- Dark raised pills read as the same detail at Roblox item scale.
	for index, y in { 0.72, 0.98, 1.24 } do
		ellipsoid(
			model,
			`GripDimple{index}`,
			Vector3.new(0.28, 0.075, 0.045),
			CFrame.new(0, y, -0.125) * CFrame.Angles(0, 0, math.rad(-4)),
			BLACK_SHADOW,
			0.01
		)
	end
end

local function addTrigger(model: Model)
	-- Layering two flattened ellipsoids makes a deep-looking trigger opening while
	-- keeping the model primitive-only and safe for every display context.
	ellipsoid(
		model,
		"TriggerRim",
		Vector3.new(0.58, 0.76, 0.085),
		CFrame.new(0, 2.02, -0.245) * CFrame.Angles(math.rad(-4), 0, 0),
		BLACK_LIGHT,
		0.02
	)
	ellipsoid(
		model,
		"TriggerRecess",
		Vector3.new(0.45, 0.62, 0.055),
		CFrame.new(0, 2.03, -0.292) * CFrame.Angles(math.rad(-4), 0, 0),
		BLACK_SHADOW,
		0
	)
	ellipsoid(
		model,
		"Trigger",
		Vector3.new(0.15, 0.34, 0.08),
		CFrame.new(0, 2.12, -0.34) * CFrame.Angles(math.rad(-9), 0, 0),
		TRIGGER,
		0.035
	)
end

local function addHousing(model: Model)
	-- The rounded rear shell is wider and taller than the circular sensor tube,
	-- matching the reference's protective rubber body rather than a plain barrel.
	ellipsoid(
		model,
		"RearShell",
		Vector3.new(1.52, 1.72, 1.18),
		CFrame.new(0, 2.78, 0.18) * CFrame.Angles(math.rad(-2), 0, 0),
		BLACK,
		0.03
	)
	ellipsoid(
		model,
		"RearShellHighlight",
		Vector3.new(1.25, 1.43, 1.0),
		CFrame.new(0, 2.82, 0.28),
		BLACK_LIGHT,
		0.018
	)

	-- Molded panels on both sides break up the all-black shell when it is viewed
	-- obliquely on a pedestal or while being hauled.
	for _, side in { -1, 1 } do
		local sideName = if side < 0 then "Left" else "Right"
		ellipsoid(
			model,
			`{sideName}SidePanel`,
			Vector3.new(0.045, 0.72, 0.56),
			CFrame.new(side * 0.762, 2.74, 0.16),
			BLACK_MID,
			0.01
		)
		ellipsoid(
			model,
			`{sideName}PanelInset`,
			Vector3.new(0.025, 0.48, 0.38),
			CFrame.new(side * 0.79, 2.7, 0.12),
			BLACK_SHADOW,
			0
		)
	end

	local crown = ellipsoid(
		model,
		"TopCrown",
		Vector3.new(0.9, 0.22, 0.68),
		CFrame.new(0, 3.6, 0.13) * CFrame.Angles(math.rad(-5), 0, 0),
		BLACK_MID,
		0.025
	)
	crown.CastShadow = false

	frontCylinder(
		model,
		"SensorTube",
		Vector3.new(0, 2.84, -0.17),
		0.72,
		1.43,
		BLACK,
		Enum.Material.SmoothPlastic
	)
	frontCylinder(
		model,
		"FrontBezel",
		Vector3.new(0, 2.84, -0.56),
		0.24,
		1.55,
		BLACK_SHADOW,
		Enum.Material.SmoothPlastic
	)
	local bevel = frontCylinder(
		model,
		"BezelHighlight",
		Vector3.new(0, 2.84, -0.69),
		0.045,
		1.43,
		BLACK_LIGHT,
		Enum.Material.SmoothPlastic
	)
	bevel.Reflectance = 0.03

	local face = frontCylinder(
		model,
		"SensorFace",
		Vector3.new(0, 2.84, -0.72),
		0.035,
		1.28,
		SENSOR_GLASS,
		Enum.Material.Glass
	)
	face.Reflectance = 0.08
	face.Transparency = 0.04
	face.CastShadow = false
end

local function addRadiationMark(model: Model)
	local centre = Vector3.new(0, 2.84, -0.75)

	-- Each blade is three widening bars. Together they make a crisp, stepped fan
	-- shape that remains recognizable after the item is scaled down in the world.
	for blade = 0, 2 do
		local angle = math.rad(90 + blade * 120)
		local radial = Vector3.new(math.cos(angle), math.sin(angle), 0)
		for segment = 1, 3 do
			local radius = 0.16 + (segment - 1) * 0.105
			local width = 0.08 + (segment - 1) * 0.055
			local piece = basePart(
				model,
				`RadiationBlade{blade + 1}_{segment}`,
				Vector3.new(width, 0.105, 0.035),
				CFrame.new(centre + radial * radius) * CFrame.Angles(0, 0, angle - math.pi / 2),
				HAZARD_ORANGE,
				Enum.Material.SmoothPlastic,
				nil
			)
			piece.Reflectance = 0.025
			piece.CastShadow = false
		end
	end

	local hub = frontCylinder(
		model,
		"RadiationHub",
		centre,
		0.04,
		0.14,
		HAZARD_ORANGE,
		Enum.Material.SmoothPlastic
	)
	hub.Reflectance = 0.025
	hub.CastShadow = false
end

function RadiationScanner.create(): Model
	local model = Instance.new("Model")
	model.Name = "RadiationScanner"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "RadiationScanner")
	model:SetAttribute("DisplayName", "Radiation Scanner")
	model:SetAttribute("GallerySize", 3.8)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(-7), math.rad(28), math.rad(-5)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(-3), math.rad(-28), 0))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(-4), math.rad(-32), 0))

	addGrip(model)
	addTrigger(model)
	addHousing(model)
	addRadiationMark(model)
	return model
end

return RadiationScanner
