--!strict
--[[
	HouseKey.luau — a plain pressed-silver house key.

	The reference has a large round bow with a true circular opening, a narrow blade,
	two stamped channels and an irregular stepped bitting edge. The bow is assembled
	from overlapping radial segments instead of hiding a dark decal on a solid disc,
	so the opening remains visible from the front, back and oblique gallery angles.

	Authored upright in the XY plane with its front pointing +Z and the blade tip at
	Y = 0. Callers own placement and move the complete Model with PivotTo.
]]

local HouseKey = {}

local BOW_SEGMENTS = 24
local BOW_CENTER = Vector3.new(0, 2.72, 0)
local BOW_OUTER_RADIUS = 0.8
local BOW_HOLE_RADIUS = 0.255
local KEY_THICKNESS = 0.14

local SILVER = Color3.fromHex("C9CDD0")
local SILVER_LIGHT = Color3.fromHex("EDF0F2")
local SILVER_SHADOW = Color3.fromHex("858B8F")

local function basePart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function addRing(
	model: Model,
	name: string,
	radius: number,
	radialWidth: number,
	depth: number,
	z: number,
	color: Color3
)
	-- Size every segment to meet at the outer edge. The inner corners overlap a
	-- little, yielding one continuous annulus while leaving the centre truly open.
	local tangentLength = 2 * (radius + radialWidth / 2) * math.tan(math.pi / BOW_SEGMENTS) + 0.006
	for index = 1, BOW_SEGMENTS do
		local angle = ((index - 1) / BOW_SEGMENTS) * math.pi * 2
		local position = BOW_CENTER + Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, z)
		local segment = basePart(
			`{name}{index}`,
			Vector3.new(radialWidth, tangentLength, depth),
			CFrame.new(position) * CFrame.Angles(0, 0, angle),
			color
		)
		segment.Parent = model
	end
end

local function addBlade(model: Model)
	-- Each band shares the same left edge while the right edge alternates. This
	-- produces the reference's cut-key silhouette without a runtime CSG operation.
	local left = -0.34
	local bands = {
		{ 0.00, 0.30, 0.14 },
		{ 0.30, 0.49, 0.32 },
		{ 0.49, 0.71, 0.16 },
		{ 0.71, 0.88, 0.29 },
		{ 0.88, 1.12, 0.12 },
		{ 1.12, 1.28, 0.31 },
		{ 1.28, 1.50, 0.13 },
		{ 1.50, 1.68, 0.35 },
		{ 1.68, 1.85, 0.20 },
		{ 1.85, 2.12, 0.39 },
	}

	for index, band in bands do
		local low, high, right = band[1], band[2], band[3]
		local bladeBand = basePart(
			`BladeBand{index}`,
			Vector3.new(right - left, high - low + 0.008, KEY_THICKNESS),
			CFrame.new((left + right) / 2, (low + high) / 2, 0),
			SILVER
		)
		bladeBand.Parent = model
	end

	-- A darker rear plate reads as the thin edge of a stamped metal blank whenever
	-- the key is turned away from the light.
	local spineShadow = basePart(
		"BladeEdgeShadow",
		Vector3.new(0.045, 2.08, KEY_THICKNESS + 0.015),
		CFrame.new(left + 0.02, 1.05, -0.008),
		SILVER_SHADOW
	)
	spineShadow.Parent = model

	-- Twin raised channels on both faces mirror the long pressed grooves in the
	-- supplied key. Short caps suggest the pointed ends of the stamped channels.
	for _, front in { -1, 1 } do
		local z = front * (KEY_THICKNESS / 2 + 0.014)
		for railIndex, x in { -0.19, 0.015 } do
			local rail = basePart(
				`BladeRail{if front > 0 then "Front" else "Back"}{railIndex}`,
				Vector3.new(0.055, 1.55, 0.026),
				CFrame.new(x, 1.01, z),
				SILVER_LIGHT
			)
			rail.Parent = model

			local railCap = basePart(
				`BladeRailCap{if front > 0 then "Front" else "Back"}{railIndex}`,
				Vector3.new(0.09, 0.13, 0.03),
				CFrame.new(x, 1.84, z),
				SILVER_LIGHT
			)
			railCap.Shape = Enum.PartType.Ball
			railCap.Parent = model
		end
	end
end

function HouseKey.create(): Model
	local model = Instance.new("Model")
	model.Name = "HouseKey"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "HouseKey")
	model:SetAttribute("DisplayName", "House Key")
	model:SetAttribute("GallerySize", 3.4)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(-9), math.rad(18), math.rad(7)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(-5), math.rad(-16), math.rad(-3)))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(-7), math.rad(-20), math.rad(-4)))

	addBlade(model)

	-- The main pressed face spans from the circular opening to the outer rim.
	local faceRadius = (BOW_OUTER_RADIUS + BOW_HOLE_RADIUS) / 2
	local faceWidth = BOW_OUTER_RADIUS - BOW_HOLE_RADIUS
	addRing(model, "BowFace", faceRadius, faceWidth, KEY_THICKNESS, 0, SILVER)

	-- Raised borders on the presentation face catch the light around the rolled
	-- outside edge and the circular hole lip. The rear stays plain pressed metal.
	local frontZ = KEY_THICKNESS / 2 + 0.014
	addRing(model, "OuterRimFront", 0.775, 0.05, 0.026, frontZ, SILVER_LIGHT)
	addRing(model, "HoleRimFront", 0.282, 0.055, 0.026, frontZ, SILVER_LIGHT)

	-- Three restrained bars suggest the reference's inset lower panel without a
	-- second full segmented ring (important when several keys are exhibited).
	for index, detail in {
		{ Vector3.new(0, 2.12, frontZ), Vector3.new(0.58, 0.022, 0.02), 0 },
		{ Vector3.new(-0.36, 2.28, frontZ), Vector3.new(0.38, 0.022, 0.02), math.rad(58) },
		{ Vector3.new(0.36, 2.28, frontZ), Vector3.new(0.38, 0.022, 0.02), math.rad(-58) },
	} do
		local panelLine = basePart(
			`BowPanelLine{index}`,
			detail[2],
			CFrame.new(detail[1]) * CFrame.Angles(0, 0, detail[3]),
			SILVER_SHADOW
		)
		panelLine.Parent = model
	end

	return model
end

return HouseKey
