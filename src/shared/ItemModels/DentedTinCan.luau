--!strict
--[[
	DentedTinCan.luau — an unlabelled, badly crushed food tin.

	Offset cylindrical bands form a real asymmetric dent: the left wall caves in
	through the middle while the opposite wall stays comparatively straight. Raised
	bands, rolled seams and a few corrosion freckles echo the supplied reference
	without relying on a texture or uploaded mesh.

	Authored upright with its base at Y = 0. Callers own placement and move the
	complete Model with PivotTo.
]]

local DentedTinCan = {}

local BODY_SLICES = 18
local CYLINDER_UP = CFrame.Angles(0, 0, math.rad(90))

local TIN = Color3.fromHex("BDB79C")
local TIN_LIGHT = Color3.fromHex("D8D3BA")
local TIN_SHADOW = Color3.fromHex("777466")
local CORROSION = Color3.fromHex("65483A")

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

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

local function radiusAt(t: number): number
	if t < 0.22 then
		return lerp(0.59, 0.55, t / 0.22)
	elseif t < 0.55 then
		return lerp(0.55, 0.43, (t - 0.22) / 0.33)
	elseif t < 0.78 then
		return lerp(0.43, 0.58, (t - 0.55) / 0.23)
	end
	return lerp(0.58, 0.60, (t - 0.78) / 0.22)
end

local function offsetAt(t: number): number
	-- Shifting the narrowest bands to +X caves in the -X silhouette without
	-- collapsing the far wall. The upper wall then drifts slightly back across.
	if t < 0.5 then
		return lerp(0, 0.14, t / 0.5)
	elseif t < 0.8 then
		return lerp(0.14, -0.035, (t - 0.5) / 0.3)
	end
	return lerp(-0.035, -0.02, (t - 0.8) / 0.2)
end

local function cylinderPart(
	model: Model,
	name: string,
	height: number,
	radius: number,
	y: number,
	x: number,
	color: Color3,
	material: Enum.Material?
): Part
	local part = basePart(
		name,
		Vector3.new(height, radius * 2, radius * 2),
		CFrame.new(x, y, 0) * CYLINDER_UP,
		color,
		material,
		Enum.PartType.Cylinder
	)
	part.Parent = model
	return part
end

local function addBody(model: Model)
	local bottom = 0.12
	local top = 1.86
	local sliceHeight = (top - bottom) / BODY_SLICES

	for index = 1, BODY_SLICES do
		local t = (index - 0.5) / BODY_SLICES
		local y = bottom + (index - 0.5) * sliceHeight
		local tone = if index % 5 == 0 then TIN_LIGHT else TIN
		cylinderPart(
			model,
			`BodyBand{index}`,
			sliceHeight + 0.012,
			radiusAt(t),
			y,
			offsetAt(t),
			tone,
			Enum.Material.Metal
		)
	end

	-- Thin overlaid cylinders project just beyond the body and create the familiar
	-- concentric reinforcing ribs around the can's crushed middle.
	for index, t in { 0.34, 0.40, 0.46, 0.52, 0.58, 0.64, 0.70, 0.76 } do
		local rib = cylinderPart(
			model,
			`RaisedRib{index}`,
			0.035,
			radiusAt(t) + 0.035,
			lerp(bottom, top, t),
			offsetAt(t),
			TIN_LIGHT,
			Enum.Material.Metal
		)
		rib.Reflectance = 0.04
	end
end

local function addEnds(model: Model)
	-- The broad rolled seams stay round even though the wall underneath has folded.
	-- Their slight horizontal disagreement helps sell the crushed S-shaped profile.
	cylinderPart(model, "BottomShadow", 0.055, 0.61, 0.055, 0, TIN_SHADOW, Enum.Material.Metal)
	cylinderPart(model, "BottomRolledSeam", 0.085, 0.625, 0.105, 0, TIN_LIGHT, Enum.Material.Metal)

	cylinderPart(model, "TopShoulder", 0.11, 0.595, 1.86, -0.02, TIN, Enum.Material.Metal)
	cylinderPart(model, "TopRolledSeam", 0.095, 0.635, 1.93, -0.02, TIN_LIGHT, Enum.Material.Metal)
	cylinderPart(model, "TopLid", 0.035, 0.57, 1.99, -0.02, TIN_SHADOW, Enum.Material.Metal)
	cylinderPart(model, "LidInset", 0.018, 0.515, 2.018, -0.02, TIN, Enum.Material.Metal)
end

local function addWear(model: Model)
	-- Sparse discoloration around the ribs, matching the reference's freckled wear
	-- while keeping the can readable as metal rather than a rusty prop.
	for index, spot in {
		{ -0.18, 0.77, 0.405, 0.038 },
		{ -0.08, 0.84, 0.423, 0.026 },
		{ 0.03, 0.91, 0.438, 0.032 },
		{ 0.17, 0.99, 0.425, 0.024 },
		{ 0.26, 1.06, 0.418, 0.034 },
		{ 0.34, 1.13, 0.431, 0.022 },
	} do
		local rust = basePart(
			`CorrosionSpot{index}`,
			Vector3.new(spot[4], spot[4] * 0.7, 0.012),
			CFrame.new(spot[1] + offsetAt(spot[2] / 2), spot[2], spot[3]),
			CORROSION,
			Enum.Material.CorrodedMetal,
			nil
		)
		rust.Parent = model
	end
end

function DentedTinCan.create(): Model
	local model = Instance.new("Model")
	model.Name = "DentedTinCan"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "DentedTinCan")
	model:SetAttribute("DisplayName", "Dented Tin Can")
	model:SetAttribute("GallerySize", 2.75)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(8), math.rad(20), math.rad(-7)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(-3), math.rad(22), math.rad(-4)))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(-8), math.rad(-24), math.rad(-7)))

	addBody(model)
	addEnds(model)
	addWear(model)
	return model
end

return DentedTinCan
