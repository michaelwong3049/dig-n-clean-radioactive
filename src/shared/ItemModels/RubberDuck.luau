--!strict
--[[
	RubberDuck.luau — a glossy, round rubber duck.

	Overlapping ellipsoids create the soft toy silhouette from the supplied
	reference: a low oval body, spherical head, two-piece orange bill, raised tail,
	and shallow teardrop wings. The eyes are modelled on both sides so the duck reads
	cleanly from any gallery or carry angle without relying on textures or an uploaded
	mesh.

	Authored upright, facing -Z, with its belly resting at Y = 0. Callers own
	placement and move the complete Model with PivotTo.
]]

local RubberDuck = {}

local GOLD = Color3.fromHex("D99B22")
local GOLD_LIGHT = Color3.fromHex("E3AA2D")
local GOLD_SHADOW = Color3.fromHex("C98516")
local BEAK = Color3.fromHex("E86622")
local BEAK_SHADOW = Color3.fromHex("C94B1B")
local EYE = Color3.fromHex("11110E")
local EYE_GLINT = Color3.fromHex("F7F3DF")

local function ellipsoid(
	model: Model,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	reflectance: number?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Shape = Enum.PartType.Ball
	part.Reflectance = reflectance or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function addBody(model: Model)
	-- The chest overlaps both body and head to keep the silhouette full through the
	-- neck instead of looking like a ball balanced on top of another ball.
	ellipsoid(
		model,
		"Body",
		Vector3.new(1.9, 1.55, 2.25),
		CFrame.new(0, 0.82, 0.15) * CFrame.Angles(math.rad(-4), 0, 0),
		GOLD,
		0.035
	)
	ellipsoid(
		model,
		"Chest",
		Vector3.new(1.52, 1.42, 1.48),
		CFrame.new(0, 1.22, -0.48) * CFrame.Angles(math.rad(8), 0, 0),
		GOLD,
		0.035
	)

	-- Three shrinking lobes give the rear a soft upward curl and a rounded point.
	-- Most of the root is hidden inside the body, avoiding a visible stalk.
	ellipsoid(
		model,
		"TailRoot",
		Vector3.new(1.42, 1.08, 1.08),
		CFrame.new(0, 1.16, 1.02) * CFrame.Angles(math.rad(-12), 0, 0),
		GOLD,
		0.035
	)
	ellipsoid(
		model,
		"TailCurl",
		Vector3.new(1.04, 0.95, 0.72),
		CFrame.new(0, 1.48, 1.38) * CFrame.Angles(math.rad(-20), 0, 0),
		GOLD_LIGHT,
		0.035
	)
	ellipsoid(
		model,
		"TailTip",
		Vector3.new(0.62, 0.73, 0.44),
		CFrame.new(0, 1.71, 1.58) * CFrame.Angles(math.rad(-27), 0, 0),
		GOLD_LIGHT,
		0.035
	)
end

local function addHead(model: Model)
	ellipsoid(
		model,
		"Head",
		Vector3.new(1.42, 1.42, 1.42),
		CFrame.new(0, 1.94, -0.72),
		GOLD_LIGHT,
		0.045
	)

	-- Separate upper and lower bill lobes preserve the dark orange mouth seam from
	-- the reference while keeping the entire bill soft and child-friendly.
	ellipsoid(
		model,
		"LowerBeak",
		Vector3.new(0.82, 0.25, 0.62),
		CFrame.new(0, 1.69, -1.39) * CFrame.Angles(math.rad(-5), 0, 0),
		BEAK_SHADOW,
		0.025
	)
	ellipsoid(
		model,
		"UpperBeak",
		Vector3.new(0.92, 0.28, 0.68),
		CFrame.new(0, 1.82, -1.41) * CFrame.Angles(math.rad(7), 0, 0),
		BEAK,
		0.03
	)

	for _, side in { -1, 1 } do
		local sideName = if side < 0 then "Left" else "Right"
		ellipsoid(
			model,
			`{sideName}Eye`,
			Vector3.new(0.105, 0.255, 0.205),
			CFrame.new(side * 0.68, 2.08, -0.91),
			EYE,
			0.08
		)
		ellipsoid(
			model,
			`{sideName}EyeGlint`,
			Vector3.new(0.035, 0.06, 0.052),
			CFrame.new(side * 0.738, 2.145, -0.955),
			EYE_GLINT,
			0.05
		)
	end
end

local function addWings(model: Model)
	for _, side in { -1, 1 } do
		local sideName = if side < 0 then "Left" else "Right"
		local wingFrame = CFrame.new(side * 0.925, 0.9, 0.28)
			* CFrame.Angles(math.rad(-12), 0, math.rad(side * -7))

		-- A broad oval forms the wing shoulder. The smaller rear lobe turns that oval
		-- into a tapered teardrop without using a hard-edged wedge or custom mesh.
		ellipsoid(
			model,
			`{sideName}Wing`,
			Vector3.new(0.2, 0.76, 1.28),
			wingFrame,
			GOLD_LIGHT,
			0.04
		)
		ellipsoid(
			model,
			`{sideName}WingTip`,
			Vector3.new(0.17, 0.48, 0.72),
			wingFrame * CFrame.new(0, -0.03, 0.48),
			GOLD_SHADOW,
			0.035
		)
	end
end

function RubberDuck.create(): Model
	local model = Instance.new("Model")
	model.Name = "RubberDuck"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "RubberDuck")
	model:SetAttribute("DisplayName", "Radioactive Rubber Duck")
	model:SetAttribute("GallerySize", 3.5)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(-6), math.rad(28), math.rad(-4)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(math.rad(-3), math.rad(30), 0))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(-5), math.rad(32), 0))

	addBody(model)
	addHead(model)
	addWings(model)
	return model
end

return RubberDuck
