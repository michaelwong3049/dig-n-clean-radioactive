--!strict
--[[
	GoldRing.luau — a polished gold engagement ring.

	The band is sampled from overlapping ellipsoids around a tall oval, giving it a
	continuous rounded profile while keeping the asset upload-free. Its upper shoulders
	widen into a raised four-prong setting with a glass gemstone and twelve smaller
	stones inset along the front, following the supplied jewelry reference.

	Authored upright in the X/Y plane with its front facing -Z and its lowest edge at
	Y = 0. Callers own placement and move the complete Model with PivotTo.
]]

local GoldRing = {}

local BAND_SEGMENTS = 40
local SHOULDER_STONES_PER_SIDE = 6
local RADIUS_X = 0.82
local RADIUS_Y = 1.05
local RING_CENTRE_Y = 1.2
local CYLINDER_UP = CFrame.Angles(0, 0, math.rad(90))

local GOLD = Color3.fromHex("E5AA4F")
local GOLD_LIGHT = Color3.fromHex("F4CC7B")
local GOLD_SHADOW = Color3.fromHex("A96624")
local DIAMOND = Color3.fromHex("D9F2FF")
local DIAMOND_LIGHT = Color3.fromHex("F7FDFF")
local DIAMOND_BLUE = Color3.fromHex("A9D9EE")

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

local function goldEllipsoid(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3?): Part
	local part = basePart(
		model,
		name,
		size,
		cframe,
		color or GOLD,
		Enum.Material.Metal,
		Enum.PartType.Ball
	)
	part.Reflectance = 0.12
	return part
end

local function glassEllipsoid(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = basePart(model, name, size, cframe, color, Enum.Material.Glass, Enum.PartType.Ball)
	part.Transparency = 0.12
	part.Reflectance = 0.18
	part.CastShadow = false
	return part
end

local function cylinderBetween(
	model: Model,
	name: string,
	from: Vector3,
	to: Vector3,
	diameter: number,
	color: Color3
): Part
	local direction = to - from
	local midpoint = from + direction / 2
	local part = basePart(
		model,
		name,
		Vector3.new(direction.Magnitude, diameter, diameter),
		CFrame.lookAt(midpoint, to, Vector3.yAxis) * CFrame.Angles(0, math.rad(-90), 0),
		color,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	part.Reflectance = 0.12
	return part
end

local function addBand(model: Model)
	local angleStep = math.pi * 2 / BAND_SEGMENTS
	for index = 1, BAND_SEGMENTS do
		local angle = (index - 1) * angleStep
		local position = Vector3.new(
			RADIUS_X * math.cos(angle),
			RING_CENTRE_Y + RADIUS_Y * math.sin(angle),
			0
		)
		local tangent = Vector3.new(-RADIUS_X * math.sin(angle), RADIUS_Y * math.cos(angle), 0).Unit
		local outward = Vector3.new(tangent.Y, -tangent.X, 0)
		local zAxis = tangent:Cross(outward)
		local frame = CFrame.fromMatrix(position, tangent, outward, zAxis)

		-- The band broadens near the crown, like the raised shoulders in the reference.
		local shoulderAlpha = math.clamp((math.sin(angle) - 0.42) / 0.58, 0, 1)
		local radialThickness = 0.26 + shoulderAlpha * 0.11
		local depth = 0.22 + shoulderAlpha * 0.13
		local localArcSpeed = math.sqrt(
			(RADIUS_X * math.sin(angle)) ^ 2 + (RADIUS_Y * math.cos(angle)) ^ 2
		)
		local segmentLength = localArcSpeed * angleStep * 1.18

		goldEllipsoid(
			model,
			`BandSegment{index}`,
			Vector3.new(segmentLength, radialThickness, depth),
			frame,
			if shoulderAlpha > 0.72 then GOLD_LIGHT else GOLD
		)
	end
end

local function addShoulders(model: Model)
	for _, side in { -1, 1 } do
		local sideName = if side < 0 then "Left" else "Right"
		cylinderBetween(
			model,
			`{sideName}ShoulderBridge`,
			Vector3.new(side * 0.48, 2.06, 0),
			Vector3.new(side * 0.27, 2.46, 0),
			0.2,
			GOLD_LIGHT
		)

		for index = 1, SHOULDER_STONES_PER_SIDE do
			local angle = math.rad(28 + index * 7.5)
			local position = Vector3.new(
				side * RADIUS_X * math.cos(angle),
				RING_CENTRE_Y + RADIUS_Y * math.sin(angle),
				-0.18
			)

			-- A gold seat behind each glass bead keeps the stones legible against the
			-- brighter shoulder instead of letting them disappear into the band.
			goldEllipsoid(
				model,
				`{sideName}StoneSeat{index}`,
				Vector3.new(0.14, 0.14, 0.07),
				CFrame.new(position + Vector3.new(0, 0, 0.025)),
				GOLD_SHADOW
			)
			glassEllipsoid(
				model,
				`{sideName}ShoulderStone{index}`,
				Vector3.new(0.095, 0.095, 0.06),
				CFrame.new(position - Vector3.new(0, 0, 0.025)),
				DIAMOND_LIGHT
			)
		end
	end
end

local function addSetting(model: Model)
	local base = basePart(
		model,
		"SettingBase",
		Vector3.new(0.13, 0.58, 0.58),
		CFrame.new(0, 2.47, 0) * CYLINDER_UP,
		GOLD_SHADOW,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	base.Reflectance = 0.12

	-- The pavilion hangs into the basket while the crown and table rise above it.
	glassEllipsoid(model, "DiamondPavilion", Vector3.new(0.47, 0.3, 0.47), CFrame.new(0, 2.58, 0), DIAMOND_BLUE)
	glassEllipsoid(model, "DiamondCrown", Vector3.new(0.68, 0.42, 0.68), CFrame.new(0, 2.75, 0), DIAMOND)

	local tablePart = basePart(
		model,
		"DiamondTable",
		Vector3.new(0.065, 0.4, 0.4),
		CFrame.new(0, 2.95, 0) * CYLINDER_UP,
		DIAMOND_LIGHT,
		Enum.Material.Glass,
		Enum.PartType.Cylinder
	)
	tablePart.Transparency = 0.08
	tablePart.Reflectance = 0.22
	tablePart.CastShadow = false

	-- Thin intersecting glass planes catch light as internal facets without a mesh.
	for index = 1, 4 do
		local facet = basePart(
			model,
			`DiamondFacet{index}`,
			Vector3.new(0.025, 0.28, 0.56),
			CFrame.new(0, 2.76, 0) * CFrame.Angles(0, math.rad((index - 1) * 45), 0),
			if index % 2 == 0 then DIAMOND_BLUE else DIAMOND_LIGHT,
			Enum.Material.Glass,
			nil
		)
		facet.Transparency = 0.42
		facet.CastShadow = false
	end

	-- Four leaning prongs hold the stone at diagonal corners. Rounded caps keep the
	-- silhouette polished rather than ending each cylinder in a sharp cut.
	for index, angleDegrees in { 45, 135, 225, 315 } do
		local angle = math.rad(angleDegrees)
		local basePosition = Vector3.new(math.cos(angle) * 0.24, 2.45, math.sin(angle) * 0.24)
		local tipPosition = Vector3.new(math.cos(angle) * 0.34, 2.87, math.sin(angle) * 0.34)
		cylinderBetween(model, `Prong{index}`, basePosition, tipPosition, 0.075, GOLD_LIGHT)
		goldEllipsoid(model, `ProngTip{index}`, Vector3.new(0.11, 0.11, 0.11), CFrame.new(tipPosition), GOLD_LIGHT)
	end
end

function GoldRing.create(): Model
	local model = Instance.new("Model")
	model.Name = "GoldRing"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "GoldRing")
	model:SetAttribute("DisplayName", "Gold Ring")
	model:SetAttribute("GallerySize", 3.5)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(-9), math.rad(-28), math.rad(7)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(-4), math.rad(-24), math.rad(5)))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(-6), math.rad(-28), math.rad(7)))

	addBand(model)
	addShoulders(model)
	addSetting(model)
	return model
end

return GoldRing
