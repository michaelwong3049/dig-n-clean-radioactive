--!strict
--[[
	CrateModels.luau — the six supply crates (Config/Crates), as geometry.

	MODELS AS CODE, like Shared/ItemModels and Shared/ToolModels/Hose: every crate is
	built from primitives here, in git, so nothing about it lives in the place file and
	nothing needs a World.rebuild() to change.

	STUDDED, ON PURPOSE. The toy-brick stud texture is the game's look, so every box,
	plank, post and drum is studded Plastic. Only glass, glowing cores and thin sign
	plates are smooth.

	THE LADDER, told in silhouette:
	  nuke1   Rusty    rotten wooden slats, rust brackets, a trefoil on a tin plate
	  nuke2   Military olive-steel ammo box, chamfered lid, ribs, latches, handles
	  nuke3   Reactor  graphite box on a hazard plinth, steel pillars, glowing windows
	           and a glass dome over a humming core
	  liquid1 Leaky    low wooden crate of three dripping green drums
	  liquid2 Hazmat   steel cage on a pallet, four striped blue canisters
	  liquid3 Cryo     frosted white frame round a glass tank of glowing coolant

	THE FRAME: authored at the ORIGIN with the box's centre there, about 2.4 studs a
	side; -Z is the front (the trefoil faces it). Every part is Anchored with no joints,
	the same contract ItemModels keeps: callers move the whole thing with PivotTo, and
	ToolService welds it together itself before it lets go of the anchor. PrimaryPart is
	`Body`. `CrateId` is stamped on the model.

	IMPORTED MODELS WIN. A model named after the crate id (`nuke1` ... `liquid3`) in
	ReplicatedStorage.Assets.CrateTemplates is cloned instead of the built one -- the
	same convention as Assets.ImportedNukeTemplates (see Shared/ItemModels). It is
	normalised on the way out: every part anchored and non-colliding, a PrimaryPart
	set, and centred on the origin like the built crates. Either way, Shared/CrateFx
	then fits the crate's ambient effects to its bounding box.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crates = require(script.Parent.Config.Crates)
local CrateFx = require(script.Parent.CrateFx)

local CrateModels = {}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- Cylinder's X axis -> Y
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- Cylinder's X axis -> Z

type Opts = {
	shape: string?, -- "Block" (default) | "Cylinder" | "Ball" | "Wedge"
	smooth: boolean?, -- no studs
	material: Enum.Material?,
	transparency: number?,
}

local FACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }

local function P(model: Model, name: string, size: Vector3, cf: CFrame, hex: string, opts: Opts?): BasePart
	local o: Opts = opts or {}
	local part: BasePart
	if o.shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local p = Instance.new("Part")
		p.Shape = Enum.PartType[o.shape or "Block"]
		part = p
	end
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = Color3.fromHex(hex)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.Transparency = o.transparency or 0

	if o.smooth or o.material then
		part.Material = o.material or Enum.Material.SmoothPlastic
		for _, face in FACES do
			(part :: any)[face] = Enum.SurfaceType.Smooth
		end
	else
		part.Material = Enum.Material.Plastic
		for _, face in FACES do
			(part :: any)[face] = Enum.SurfaceType.Studs
		end
	end

	part.Parent = model
	return part
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function light(part: BasePart, hex: string, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = Color3.fromHex(hex)
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

--- A radiation trefoil painted on one face of `part`: the same fan-of-bars drawing
--- build/Plots uses on the pump placard, so the symbol reads the same everywhere.
local function trefoil(part: BasePart, face: Enum.NormalId, studs: number, ink: string)
	local pps = 60
	local px = studs * pps
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Trefoil"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.MaxDistance = 60
	gui.LightInfluence = 1
	gui.Parent = part

	local color = Color3.fromHex(ink)
	local function box(name: string, x: number, y: number, w: number, h: number, rotation: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(x, y)
		frame.Size = UDim2.fromOffset(w, h)
		frame.Rotation = rotation
		frame.BackgroundColor3 = color
		frame.BorderSizePixel = 0
		frame.Parent = gui
		return frame
	end

	local centre = px / 2
	local inner, outer = px * 0.13, px * 0.42
	local mid, length = (inner + outer) / 2, outer - inner
	for _, blade in { 90, 210, 330 } do
		for spread = -26, 26, 4 do
			local angle = blade + spread
			local rad = math.rad(angle)
			box("Blade", centre + mid * math.cos(rad), centre + mid * math.sin(rad), length, px * 0.035, angle)
		end
	end
	local hub = box("Hub", centre, centre, px * 0.16, px * 0.16, 0)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = hub
end

-- ── Nuke crates ───────────────────────────────────────────────────────

local function rusty(model: Model): BasePart
	local body = P(model, "Body", Vector3.new(2.2, 1.9, 2.2), at(0, 0, 0), "6B4423")

	-- Slats round all four sides, alternating two plank shades so each board reads.
	for i, y in { -0.62, 0, 0.62 } do
		local shade = if i % 2 == 0 then "94602F" else "A0693A"
		P(model, "Slat", Vector3.new(2.3, 0.52, 0.14), at(0, y, -1.15), shade)
		P(model, "Slat", Vector3.new(2.3, 0.52, 0.14), at(0, y, 1.15), shade)
		P(model, "Slat", Vector3.new(0.14, 0.52, 2.3), at(-1.15, y, 0), shade)
		P(model, "Slat", Vector3.new(0.14, 0.52, 2.3), at(1.15, y, 0), shade)
	end
	for _, x in { -1.12, 1.12 } do
		for _, z in { -1.12, 1.12 } do
			P(model, "Post", Vector3.new(0.34, 2.0, 0.34), at(x, 0, z), "5C3A1E")
			P(model, "Bracket", Vector3.new(0.42, 0.34, 0.42), at(x, 0.86, z), "8E4B2A")
			P(model, "Bracket", Vector3.new(0.42, 0.34, 0.42), at(x, -0.86, z), "8E4B2A")
		end
	end

	-- A lid with two cross boards nailed over it, one knocked askew.
	P(model, "Lid", Vector3.new(2.4, 0.24, 2.4), at(0, 1.07, 0), "7A4E26")
	P(model, "LidBoard", Vector3.new(2.45, 0.14, 0.42), at(0, 1.26, -0.6), "A0693A")
	P(model, "LidBoard", Vector3.new(2.3, 0.14, 0.42), at(0.05, 1.26, 0.55) * CFrame.Angles(0, math.rad(8), 0), "94602F")

	-- The tin plate with the trefoil, a little rusty itself round the rim.
	P(model, "PlateRim", Vector3.new(1.12, 1.12, 0.06), at(0, 0.02, -1.25), "8E4B2A", { smooth = true })
	local plate = P(model, "Plate", Vector3.new(0.98, 0.98, 0.06), at(0, 0.02, -1.29), "F2C230", { smooth = true })
	trefoil(plate, Enum.NormalId.Front, 0.98, "1E1E1E")

	return body
end

local function military(model: Model): BasePart
	local body = P(model, "Body", Vector3.new(2.3, 1.6, 1.8), at(0, -0.1, 0), "556B2F")

	-- Chamfered lid: a flat top between two wedges along the long edges.
	P(model, "Lid", Vector3.new(2.3, 0.32, 1.2), at(0, 0.86, 0), "4B5F28")
	P(model, "Chamfer", Vector3.new(2.3, 0.32, 0.3), at(0, 0.86, -0.75), "4B5F28", { shape = "Wedge" })
	P(model, "Chamfer", Vector3.new(2.3, 0.32, 0.3), at(0, 0.86, 0.75) * CFrame.Angles(0, math.pi, 0), "4B5F28", { shape = "Wedge" })

	-- Two steel ribs wrapping the box, plus the stencil band between them.
	for _, x in { -0.72, 0.72 } do
		P(model, "Rib", Vector3.new(0.22, 1.7, 1.9), at(x, -0.08, 0), "3F4F22")
		P(model, "Latch", Vector3.new(0.34, 0.42, 0.14), at(x, 0.5, -0.97), "4A4F55")
		P(model, "LatchPin", Vector3.new(0.14, 0.14, 0.2), at(x, 0.35, -1.05), "B8BEC4", { smooth = true })
	end
	P(model, "Stencil", Vector3.new(1.18, 0.16, 1.84), at(0, -0.7, 0), "6F8A3C")

	-- Carry handles on the ends.
	for _, side in { -1, 1 } do
		P(model, "Handle", Vector3.new(0.9, 0.16, 0.16), at(side * 1.32, 0.12, 0) * ALONG_Z, "2F3336", { shape = "Cylinder", smooth = true })
		P(model, "HandleMount", Vector3.new(0.2, 0.24, 0.2), at(side * 1.22, 0.12, -0.38), "4A4F55")
		P(model, "HandleMount", Vector3.new(0.2, 0.24, 0.2), at(side * 1.22, 0.12, 0.38), "4A4F55")
	end

	-- Skids underneath.
	for _, x in { -0.85, 0.85 } do
		P(model, "Skid", Vector3.new(0.32, 0.16, 1.9), at(x, -0.98, 0), "2F3A1A")
	end

	local plate = P(model, "Plate", Vector3.new(0.8, 0.8, 0.06), at(0, -0.05, -0.93), "E8C547", { smooth = true })
	trefoil(plate, Enum.NormalId.Front, 0.8, "1E1E1E")

	return body
end

local function reactor(model: Model): BasePart
	-- Hazard-striped plinth: yellow slab with black bars across the front and back.
	P(model, "Plinth", Vector3.new(2.5, 0.3, 2.5), at(0, -1.0, 0), "F2C230")
	for i = -2, 2 do
		P(model, "Stripe", Vector3.new(0.22, 0.32, 0.4), at(i * 0.5, -1.0, -1.08) * CFrame.Angles(0, 0, math.rad(35)), "1E1E1E", { smooth = true })
		P(model, "Stripe", Vector3.new(0.22, 0.32, 0.4), at(i * 0.5, -1.0, 1.08) * CFrame.Angles(0, 0, math.rad(35)), "1E1E1E", { smooth = true })
	end

	local body = P(model, "Body", Vector3.new(2.05, 1.75, 2.05), at(0, 0, 0), "2B2F36")

	for _, x in { -1.03, 1.03 } do
		for _, z in { -1.03, 1.03 } do
			P(model, "Pillar", Vector3.new(2.05, 0.5, 0.5), at(x, 0.02, z) * UPRIGHT, "5A616B", { shape = "Cylinder" })
			P(model, "PillarCap", Vector3.new(0.58, 0.58, 0.58), at(x, 1.05, z), "8A939E", { shape = "Ball" })
		end
	end

	-- A glowing window on every side: a steel frame round a lit panel.
	local windows = {
		{ at(0, 0.05, -1.04), Vector3.new(1.2, 0.95, 0.08) },
		{ at(0, 0.05, 1.04), Vector3.new(1.2, 0.95, 0.08) },
		{ at(-1.04, 0.05, 0), Vector3.new(0.08, 0.95, 1.2) },
		{ at(1.04, 0.05, 0), Vector3.new(0.08, 0.95, 1.2) },
	}
	for _, w in windows do
		local frameSize = w[2] + Vector3.new(if w[2].X > 1 then 0.2 else 0.02, 0.2, if w[2].Z > 1 then 0.2 else 0.02)
		P(model, "WindowFrame", frameSize, w[1], "5A616B")
		local pane = P(model, "Window", w[2] + Vector3.new(if w[2].X > 1 then 0 else 0.06, 0, if w[2].Z > 1 then 0 else 0.06), w[1], "B26BFF", { material = Enum.Material.Glass, transparency = 0.15 })
		pane.CastShadow = false
	end

	-- Lid, then a glass dome over the core.
	P(model, "Lid", Vector3.new(2.25, 0.24, 2.25), at(0, 1.0, 0), "3A3F47")
	P(model, "DomeRing", Vector3.new(0.18, 1.3, 1.3), at(0, 1.18, 0) * UPRIGHT, "8A939E", { shape = "Cylinder" })
	local core = P(model, "Core", Vector3.new(0.62, 0.62, 0.62), at(0, 1.35, 0), "E3C4FF", { shape = "Ball", smooth = true })
	core.CastShadow = false
	light(core, "B26BFF", 10, 2)
	local dome = P(model, "Dome", Vector3.new(1.1, 1.1, 1.1), at(0, 1.3, 0), "C9A2FF", { shape = "Ball", material = Enum.Material.Glass, transparency = 0.55 })
	dome.CastShadow = false

	local plate = P(model, "Plate", Vector3.new(0.62, 0.62, 0.06), at(0, -0.62, -1.06), "F2C230", { smooth = true })
	trefoil(plate, Enum.NormalId.Front, 0.62, "1E1E1E")

	return body
end

-- ── Liquid crates ─────────────────────────────────────────────────────

local function drum(model: Model, x: number, z: number, height: number, dia: number, body: string, band: string, bottom: number)
	local y = bottom + height / 2
	P(model, "Drum", Vector3.new(height, dia, dia), at(x, y, z) * UPRIGHT, body, { shape = "Cylinder" })
	for _, f in { 0.22, 0.78 } do
		P(model, "DrumBand", Vector3.new(0.1, dia + 0.06, dia + 0.06), at(x, bottom + height * f, z) * UPRIGHT, band, { shape = "Cylinder" })
	end
	P(model, "DrumCap", Vector3.new(0.1, dia * 0.24, dia * 0.24), at(x + dia * 0.2, bottom + height + 0.05, z) * UPRIGHT, band, { shape = "Cylinder", smooth = true })
end

local function leaky(model: Model): BasePart
	local body = P(model, "Body", Vector3.new(2.4, 0.26, 2.4), at(0, -0.97, 0), "6B4423")
	for _, z in { -1.1, 1.1 } do
		P(model, "Wall", Vector3.new(2.4, 0.42, 0.2), at(0, -0.62, z), "A0693A")
		P(model, "Wall", Vector3.new(2.4, 0.42, 0.2), at(0, -0.18, z), "94602F")
	end
	for _, x in { -1.1, 1.1 } do
		P(model, "Wall", Vector3.new(0.2, 0.42, 2.0), at(x, -0.62, 0), "94602F")
		P(model, "Wall", Vector3.new(0.2, 0.42, 2.0), at(x, -0.18, 0), "A0693A")
	end
	for _, x in { -1.1, 1.1 } do
		for _, z in { -1.1, 1.1 } do
			P(model, "Post", Vector3.new(0.32, 1.14, 0.32), at(x, -0.34, z), "5C3A1E")
		end
	end

	-- Three drums standing in it, one leaning, all a bit too full.
	drum(model, -0.5, -0.42, 1.6, 0.92, "4CAF50", "2E7D32", -0.84)
	drum(model, 0.52, -0.4, 1.5, 0.92, "43A047", "2E7D32", -0.84)
	drum(model, 0, 0.5, 1.7, 0.92, "4CAF50", "2E7D32", -0.84)

	-- The leak: a drip run down the front drum and a puddle on the crate lip.
	P(model, "Drip", Vector3.new(0.1, 0.62, 0.06), at(-0.62, 0.3, -0.9), "7CFC00", { smooth = true })
	P(model, "Drip", Vector3.new(0.08, 0.36, 0.06), at(-0.36, 0.44, -0.9), "7CFC00", { smooth = true })
	P(model, "DripBead", Vector3.new(0.16, 0.16, 0.16), at(-0.62, -0.02, -0.92), "7CFC00", { shape = "Ball", smooth = true })
	local ooze = P(model, "Ooze", Vector3.new(0.06, 0.7, 0.9), at(-0.55, 0.04, -1.1) * UPRIGHT, "7CFC00", { shape = "Cylinder", smooth = true })
	light(ooze, "7CFC00", 5, 0.8)

	return body
end

local function hazmat(model: Model): BasePart
	local body = P(model, "Body", Vector3.new(2.4, 0.3, 2.0), at(0, -0.97, 0), "4A5561")
	for _, x in { -0.8, 0, 0.8 } do
		P(model, "PalletFoot", Vector3.new(0.3, 0.16, 2.0), at(x, -1.18, 0), "3A434D")
	end

	for _, x in { -1.1, 1.1 } do
		for _, z in { -0.9, 0.9 } do
			P(model, "CagePost", Vector3.new(0.24, 2.0, 0.24), at(x, 0.05, z), "8A96A3")
		end
	end
	for _, y in { 0.02, 1.0 } do
		for _, z in { -0.9, 0.9 } do
			P(model, "CageRail", Vector3.new(2.44, 0.18, 0.18), at(0, y, z), "8A96A3")
		end
		for _, x in { -1.1, 1.1 } do
			P(model, "CageRail", Vector3.new(0.18, 0.18, 1.84), at(x, y, 0), "8A96A3")
		end
	end

	-- Four canisters with a yellow hazard band and a white cap.
	for _, x in { -0.5, 0.5 } do
		for _, z in { -0.4, 0.4 } do
			P(model, "Canister", Vector3.new(1.5, 0.74, 0.74), at(x, -0.07, z) * UPRIGHT, "3DB8F5", { shape = "Cylinder" })
			P(model, "CanisterBand", Vector3.new(0.14, 0.78, 0.78), at(x, 0.25, z) * UPRIGHT, "F2C230", { shape = "Cylinder" })
			P(model, "CanisterShoulder", Vector3.new(0.5, 0.5, 0.5), at(x, 0.7, z), "3DB8F5", { shape = "Ball" })
			P(model, "CanisterCap", Vector3.new(0.18, 0.26, 0.26), at(x, 0.98, z) * UPRIGHT, "E6E6E6", { shape = "Cylinder", smooth = true })
		end
	end

	local plate = P(model, "Plate", Vector3.new(0.66, 0.66, 0.06), at(0, 0.5, -0.96) * CFrame.Angles(0, 0, math.rad(45)), "F2C230", { smooth = true })
	trefoil(plate, Enum.NormalId.Front, 0.66, "1E1E1E")

	return body
end

local function cryo(model: Model): BasePart
	local body = P(model, "Body", Vector3.new(2.3, 0.34, 2.3), at(0, -0.95, 0), "9FB3C2")
	P(model, "Top", Vector3.new(2.3, 0.3, 2.3), at(0, 1.0, 0), "E8F4FA")

	for _, x in { -0.95, 0.95 } do
		for _, z in { -0.95, 0.95 } do
			P(model, "Pillar", Vector3.new(1.64, 0.42, 0.42), at(x, 0.02, z) * UPRIGHT, "E8F4FA", { shape = "Cylinder" })
			P(model, "Frost", Vector3.new(0.5, 0.26, 0.5), at(x, 1.24, z), "CFF6FF")
		end
	end

	-- The tank: a glass cylinder round a column of glowing coolant.
	local liquid = P(model, "Coolant", Vector3.new(1.3, 1.26, 1.26), at(0, -0.02, 0) * UPRIGHT, "8FF0FF", { shape = "Cylinder", smooth = true })
	liquid.CastShadow = false
	light(liquid, "8FF0FF", 10, 1.6)
	local glass = P(model, "Tank", Vector3.new(1.64, 1.56, 1.56), at(0, 0.02, 0) * UPRIGHT, "BFEFFF", { shape = "Cylinder", material = Enum.Material.Glass, transparency = 0.6 })
	glass.CastShadow = false
	for _, y in { -0.78, 0.82 } do
		P(model, "TankRing", Vector3.new(0.14, 1.66, 1.66), at(0, y, 0) * UPRIGHT, "9FB3C2", { shape = "Cylinder" })
	end

	-- Valve and a frosted pipe off the top.
	P(model, "Valve", Vector3.new(0.3, 0.4, 0.4), at(0, 1.3, 0) * UPRIGHT, "9FB3C2", { shape = "Cylinder" })
	P(model, "ValveWheel", Vector3.new(0.08, 0.62, 0.62), at(0, 1.5, 0) * UPRIGHT, "3DB8F5", { shape = "Cylinder" })
	P(model, "FrostCap", Vector3.new(1.0, 0.2, 0.6), at(-0.6, 1.24, 0.2), "CFF6FF")

	return body
end

local BUILDERS: { [string]: (Model) -> BasePart } = {
	nuke1 = rusty,
	nuke2 = military,
	nuke3 = reactor,
	liquid1 = leaky,
	liquid2 = hazmat,
	liquid3 = cryo,
}

--- A fresh model for one crate, centred on the origin. Errors on an unknown id: a
--- crate id only ever comes from Config/Crates.
--- An imported crate for this id, normalised, or nil when none has been imported.
local function imported(crateId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("CrateTemplates")
	local template = folder and folder:FindFirstChild(crateId)
	if template == nil or not template:IsA("Model") then
		return nil
	end

	local model = template:Clone()
	local first: BasePart? = nil
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			first = first or part
		end
	end
	if first == nil then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = model.PrimaryPart or first
	-- Centre the box on the origin, like the built crates.
	local box = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - box.Position)
	return model
end

function CrateModels.create(crateId: string): Model
	local def = Crates.get(crateId)

	local model = imported(crateId)
	if model == nil then
		local build = BUILDERS[crateId]
		assert(build, `no model for crate "{crateId}"`)
		model = Instance.new("Model")
		model.PrimaryPart = build(model)
	end

	local crate = model :: Model
	crate.Name = def.name
	crate:SetAttribute("CrateId", crateId)
	CrateFx.apply(crate, crateId, def.color, def.variant)
	return crate
end

return CrateModels
