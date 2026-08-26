--!strict
--[[
	Wristwatch.luau — a stopped silver analog wristwatch.

	A raised case, aged dial, individual hour markers and hands fixed at 8:14 make
	the face readable at gallery scale. The bracelet is a real linked oval beneath
	the case rather than a flat decorative strip, echoing the supplied metal-band
	reference while remaining a versioned, upload-free Roblox primitive model.

	Authored face-up with its dial pointing +Y and the clasp resting near Y = 0.
	Callers own placement and move the complete Model with PivotTo.
]]

local Wristwatch = {}

local CYLINDER_UP = CFrame.Angles(0, 0, math.rad(90))
local BRACELET_LINKS = 20

local STEEL = Color3.fromHex("AEB4B8")
local STEEL_LIGHT = Color3.fromHex("E4E8EA")
local STEEL_DARK = Color3.fromHex("5E666B")
local DIAL = Color3.fromHex("9EAEA8")
local INK = Color3.fromHex("273237")
local SECOND_HAND = Color3.fromHex("8B4B3E")

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

local function addCylinder(
	model: Model,
	name: string,
	height: number,
	diameter: number,
	y: number,
	color: Color3,
	material: Enum.Material?
): Part
	local part = basePart(
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(0, y, 0) * CYLINDER_UP,
		color,
		material,
		Enum.PartType.Cylinder
	)
	part.Parent = model
	return part
end

local function dialDirection(clockMinutes: number): Vector3
	local angle = (clockMinutes / 60) * math.pi * 2
	return Vector3.new(math.sin(angle), 0, -math.cos(angle))
end

local function addHand(model: Model, name: string, clockMinutes: number, length: number, width: number, y: number, color: Color3)
	local direction = dialDirection(clockMinutes)
	local centre = Vector3.new(0, y, 0) + direction * (length / 2 - 0.035)
	local hand = basePart(
		name,
		Vector3.new(width, 0.018, length),
		CFrame.lookAt(centre, centre - direction, Vector3.yAxis),
		color,
		Enum.Material.Metal,
		nil
	)
	hand.Parent = model
end

local function addDial(model: Model)
	addCylinder(model, "CaseBack", 0.3, 1.48, 1.08, STEEL_DARK, Enum.Material.Metal)
	addCylinder(model, "Case", 0.28, 1.42, 1.15, STEEL, Enum.Material.Metal)
	addCylinder(model, "RaisedBezel", 0.13, 1.28, 1.315, STEEL_LIGHT, Enum.Material.Metal)
	addCylinder(model, "AgedDial", 0.035, 1.12, 1.388, DIAL, Enum.Material.SmoothPlastic)

	-- Twelve applied indices keep the watch legible without relying on a texture.
	for index = 0, 11 do
		local angle = (index / 12) * math.pi * 2
		local direction = Vector3.new(math.sin(angle), 0, -math.cos(angle))
		local cardinal = index % 3 == 0
		local length = if cardinal then 0.17 else 0.105
		local radius = if cardinal then 0.43 else 0.455
		local position = Vector3.new(0, 1.42, 0) + direction * radius
		local marker = basePart(
			`HourMarker{index + 1}`,
			Vector3.new(if cardinal then 0.045 else 0.026, 0.022, length),
			CFrame.lookAt(position, position - direction, Vector3.yAxis),
			STEEL_LIGHT,
			Enum.Material.Metal,
			nil
		)
		marker.Parent = model
	end

	-- The catalogue flavor says 8:14. The hour hand is advanced proportionally
	-- between eight and nine instead of pointing at an exact numeral.
	addHand(model, "HourHand", 41.17, 0.31, 0.07, 1.452, INK)
	addHand(model, "MinuteHand", 14, 0.47, 0.045, 1.464, INK)
	addHand(model, "SecondHand", 32, 0.50, 0.018, 1.476, SECOND_HAND)

	local pin = basePart(
		"HandPin",
		Vector3.new(0.055, 0.055, 0.055),
		CFrame.new(0, 1.49, 0),
		STEEL_LIGHT,
		Enum.Material.Metal,
		Enum.PartType.Ball
	)
	pin.Parent = model

	local glass = addCylinder(model, "WatchGlass", 0.025, 1.08, 1.505, Color3.fromHex("D9EDF0"), Enum.Material.Glass)
	glass.Transparency = 0.55
	glass.Reflectance = 0.08

	-- Small ridged crown on the three-o'clock side.
	local crown = basePart(
		"Crown",
		Vector3.new(0.17, 0.22, 0.22),
		CFrame.new(0.79, 1.17, 0),
		STEEL_LIGHT,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	crown.Parent = model
	for index = -1, 1 do
		local ridge = basePart(
			`CrownRidge{index + 2}`,
			Vector3.new(0.03, 0.245, 0.245),
			CFrame.new(0.76 + index * 0.055, 1.17, 0),
			STEEL_DARK,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)
		ridge.Parent = model
	end
end

local function addBracelet(model: Model)
	-- Four squared lugs bridge the round case into the first bracelet links.
	for _, zSide in { -1, 1 } do
		for _, xSide in { -1, 1 } do
			local lug = basePart(
				`Lug_{xSide}_{zSide}`,
				Vector3.new(0.25, 0.18, 0.34),
				CFrame.new(xSide * 0.43, 1.11, zSide * 0.72),
				STEEL,
				Enum.Material.Metal,
				nil
			)
			lug.Parent = model
		end
	end

	-- Sample the bracelet around the lower 290 degrees of an ellipse. Keeping a
	-- gap at the top leaves room for the case while the bottom links meet at a clasp.
	local startAngle = math.rad(35)
	local endAngle = math.rad(325)
	local centreY = 0.68
	local radiusY = 0.55
	local radiusZ = 1.55

	for index = 1, BRACELET_LINKS do
		local alpha = (index - 1) / (BRACELET_LINKS - 1)
		local angle = startAngle + (endAngle - startAngle) * alpha
		local position = Vector3.new(0, centreY + radiusY * math.cos(angle), radiusZ * math.sin(angle))
		local tangent = Vector3.new(0, -radiusY * math.sin(angle), radiusZ * math.cos(angle)).Unit
		local xAxis = Vector3.xAxis
		local yAxis = tangent:Cross(xAxis).Unit
		local orientation = CFrame.fromMatrix(position, xAxis, yAxis, tangent)

		local centreLink = basePart(
			`BraceletCentre{index}`,
			Vector3.new(0.48, 0.105, 0.255),
			orientation,
			if index % 2 == 0 then STEEL_LIGHT else STEEL,
			Enum.Material.Metal,
			nil
		)
		centreLink.Parent = model

		for _, side in { -1, 1 } do
			local edgeLink = basePart(
				`BraceletEdge{index}_{side}`,
				Vector3.new(0.14, 0.115, 0.255),
				orientation * CFrame.new(side * 0.33, 0, 0),
				if index % 2 == 0 then STEEL else STEEL_DARK,
				Enum.Material.Metal,
				nil
			)
			edgeLink.Parent = model
		end
	end

	-- A broad polished clasp bridges the bottom links and makes the loop read as a
	-- functional bracelet rather than two loose tails.
	local clasp = basePart(
		"BraceletClasp",
		Vector3.new(0.82, 0.13, 0.5),
		CFrame.new(0, 0.1, 0),
		STEEL_LIGHT,
		Enum.Material.Metal,
		nil
	)
	clasp.Parent = model
	local claspInset = basePart(
		"ClaspInset",
		Vector3.new(0.56, 0.025, 0.33),
		CFrame.new(0, 0.171, 0),
		STEEL_DARK,
		Enum.Material.Metal,
		nil
	)
	claspInset.Parent = model
end

function Wristwatch.create(): Model
	local model = Instance.new("Model")
	model.Name = "Wristwatch"
	model.WorldPivot = CFrame.identity
	model:SetAttribute("ItemModel", "Wristwatch")
	model:SetAttribute("DisplayName", "Stopped Wristwatch")
	model:SetAttribute("GallerySize", 3.6)
	model:SetAttribute("HaulRotation", CFrame.Angles(math.rad(18), math.rad(22), math.rad(5)))
	model:SetAttribute("DisplayRotation", CFrame.Angles(0, math.rad(18), 0))
	model:SetAttribute("GalleryRotation", CFrame.Angles(math.rad(34), math.rad(-18), math.rad(4)))

	addBracelet(model)
	addDial(model)
	return model
end

return Wristwatch
