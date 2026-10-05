--[[
	GearArtFx — the gear's own effects, drawn over a GearArt picture.

	A ViewportFrame renders parts and nothing else: no ParticleEmitter, no PointLight,
	and no ToolMotionController, which only moves welds under Workspace. So a shop card
	showed a Deep Core Array without its embers and a Singularity Coil standing still.

	THE CARD RUNS THE REAL ToolFX, THEN REDRAWS IT IN 2D. Shared/ToolFX.apply is called
	on the card's own copy of the model exactly as it is on a held tool or a rack, and
	this file reads back what it made:

	  * every ParticleEmitter becomes a small 2D particle system — its texture, colour,
	    size and transparency curves, rate, lifetime, speed, spread, drag, acceleration,
	    spin, squash, LockedToPart and Disc shape are simulated in 3D in the model's
	    frame and projected through the card's camera, so a spark leaves the same part
	    in the same direction it does in the hand;
	  * every PointLight becomes a soft halo in its colour BEHIND the model (a layer
	    under the transparent ViewportFrame), so the coil sits in its own light;
	  * every ToolMotion weld (ToolFX's moving parts) is posed each frame straight off
	    its anchor, the way ToolMotionController poses an anchored rack.

	Nothing is hand-copied per tier, so a new ToolFX spec shows up on its card for free,
	and a tier with no FX (the common rungs) gets nothing.

	Runs only while the picture is actually on screen, and every card cleans up after
	itself when GearArt swaps the model out.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ToolFX = require(ReplicatedStorage.Shared.ToolFX)
local Prefs = require(script.Parent.Prefs)

local GearArtFx = {}

local MOTION_TAG = "ToolMotion"
local FX_LAYER = "GearFx"
local GLOW_LAYER = "GearGlow"

-- A card's worth of sparks, never more — the emitters' rates are meant for one tool in
-- a big world, and a peeking neighbour card runs too.
local MAX_PARTICLES = 80
-- An unlit particle's colour is multiplied by its Brightness in the world; a GUI image
-- cannot go past its colour, so a bright emitter is nudged toward white instead.
local BRIGHT_WHITEN = 0.08
-- A light's halo is a fraction of its Range: at full range the halo would swallow the
-- whole card (Range 8 on a 4-stud detector).
local HALO_PER_RANGE = 0.16
-- ...and never wider than this share of the card's height, whatever the range.
local HALO_MAX = 0.8
-- Rings in a halo, largest first; each ring is a flat circle, and stacked they fake a
-- soft radial fall-off (a UIGradient cannot run radially).
local HALO_RINGS = { 1, 0.82, 0.64, 0.47, 0.3 }
local HALO_RING_ALPHA = 0.9

type Emitter = {
	emitter: ParticleEmitter,
	host: BasePart,
	attachment: Attachment?,
	carry: number,
}

type Particle = {
	label: ImageLabel,
	source: Emitter,
	age: number,
	life: number,
	-- In the host part's frame when the emitter is LockedToPart, else in the model's.
	pos: Vector3,
	vel: Vector3,
	rot: number,
	spin: number,
	shade: number,
}

type Halo = {
	frame: Frame,
	light: PointLight,
	host: BasePart,
	radius: number,
}

type Move = {
	part: BasePart,
	bend: BasePart,
	rest: CFrame,
	pivot: Vector3,
	axis: Vector3,
	spin: number,
	bob: number,
	hz: number,
	phase: number,
}

type Rig = {
	viewport: ViewportFrame,
	aspect: number,
	sparks: Frame,
	glow: Frame,
	emitters: { Emitter },
	particles: { Particle },
	halos: { Halo },
	moves: { Move },
	connection: RBXScriptConnection?,
	-- FAST MODE: the halos have been laid once and nothing moves after that.
	stilled: boolean?,
}

local rigs: { [ViewportFrame]: Rig } = {}

local function evalNumber(s: NumberSequence, t: number): number
	local points = s.Keypoints
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		if t <= b.Time then
			local span = b.Time - a.Time
			local k = if span > 0 then (t - a.Time) / span else 0
			return a.Value + (b.Value - a.Value) * k
		end
	end
	return points[#points].Value
end

local function evalColor(s: ColorSequence, t: number): Color3
	local points = s.Keypoints
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		if t <= b.Time then
			local span = b.Time - a.Time
			return a.Value:Lerp(b.Value, if span > 0 then (t - a.Time) / span else 0)
		end
	end
	return points[#points].Value
end

local function between(range: NumberRange): number
	return range.Min + (range.Max - range.Min) * math.random()
end

local function overlaps(a: GuiObject, b: GuiObject): boolean
	local aMin, bMin = a.AbsolutePosition, b.AbsolutePosition
	local aMax, bMax = aMin + a.AbsoluteSize, bMin + b.AbsoluteSize
	return aMin.X < bMax.X and bMin.X < aMax.X and aMin.Y < bMax.Y and bMin.Y < aMax.Y
end

--- Is `gui` drawn at all? Walks up through Visible and the ScreenGui's Enabled, and
--- out of any clipping frame it lies wholly outside — the shop carousel lays every
--- tier's card out in one strip and clips all but the focused one and its neighbours.
local function onScreen(gui: GuiObject): boolean
	local node: Instance? = gui.Parent
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible or (node.ClipsDescendants and not overlaps(gui, node)) then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

--- A point in the model's frame -> a point in the card as fractions of its width and
--- height, plus how many card-heights one stud is at that depth. nil behind the camera.
local function project(rig: Rig, point: Vector3): (number?, number?, number?)
	local camera = rig.viewport.CurrentCamera
	if camera == nil then
		return nil, nil, nil
	end
	local p = camera.CFrame:PointToObjectSpace(point)
	local depth = -p.Z
	if depth <= 0.05 then
		return nil, nil, nil
	end
	local half = math.tan(math.rad(camera.FieldOfView) / 2) * depth
	return 0.5 + p.X / (half * rig.aspect) / 2, 0.5 - p.Y / half / 2, 1 / (half * 2)
end

--- The face an emitter fires from, in its host's frame.
local function normalOf(id: Enum.NormalId): Vector3
	return Vector3.FromNormalId(id)
end

--- Two axes square to `n`, for spread and for the Disc shape.
local function basis(n: Vector3): (Vector3, Vector3)
	local helper = if math.abs(n.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local u = n:Cross(helper).Unit
	return u, n:Cross(u).Unit
end

--- Where a new particle is born, in the host part's frame.
local function birthPoint(source: Emitter, normal: Vector3): Vector3
	if source.attachment then
		return source.attachment.Position
	end
	local e = source.emitter
	local half = source.host.Size / 2
	if e.Shape == Enum.ParticleEmitterShape.Disc then
		-- A ring round the face the emitter fires from: ShapePartial is how far in from
		-- the rim it may reach, so ToolFX's rim glints stay on the ring.
		local u, v = basis(normal)
		local ru = math.abs(half:Dot(u))
		local rv = math.abs(half:Dot(v))
		local r = 1 - e.ShapePartial * math.random()
		local a = math.random() * math.pi * 2
		return u * (math.cos(a) * r * ru) + v * (math.sin(a) * r * rv)
	end
	return Vector3.new(
		(math.random() * 2 - 1) * half.X,
		(math.random() * 2 - 1) * half.Y,
		(math.random() * 2 - 1) * half.Z
	)
end

local function spawn(rig: Rig, source: Emitter)
	if #rig.particles >= MAX_PARTICLES then
		return
	end
	local e = source.emitter
	local normal = normalOf(e.EmissionDirection)
	local u, v = basis(normal)
	local spreadX = math.rad(e.SpreadAngle.X) * (math.random() * 2 - 1)
	local spreadY = math.rad(e.SpreadAngle.Y) * (math.random() * 2 - 1)
	local dir = (CFrame.fromAxisAngle(u, spreadX) * CFrame.fromAxisAngle(v, spreadY)):VectorToWorldSpace(normal)
	local localPos = birthPoint(source, normal)
	local localVel = dir * between(e.Speed)

	local pos, vel = localPos, localVel
	if not e.LockedToPart then
		local frame = source.host.CFrame
		pos = frame:PointToWorldSpace(localPos)
		vel = frame:VectorToWorldSpace(localVel)
	end

	local label = Instance.new("ImageLabel")
	label.Name = "Spark"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Image = e.Texture
	label.ImageTransparency = 1
	label.Parent = rig.sparks

	table.insert(rig.particles, {
		label = label,
		source = source,
		age = 0,
		life = math.max(between(e.Lifetime), 0.05),
		pos = pos,
		vel = vel,
		rot = between(e.Rotation),
		spin = between(e.RotSpeed),
		shade = math.random(),
	})
end

local function stepParticles(rig: Rig, dt: number)
	for _, source in rig.emitters do
		local e = source.emitter
		if not e.Enabled then
			continue
		end
		source.carry += e.Rate * dt
		while source.carry >= 1 do
			source.carry -= 1
			spawn(rig, source)
		end
	end

	local i = 1
	while i <= #rig.particles do
		local p = rig.particles[i]
		p.age += dt
		if p.age >= p.life or p.source.host.Parent == nil then
			p.label:Destroy()
			rig.particles[i] = rig.particles[#rig.particles]
			rig.particles[#rig.particles] = nil
			continue
		end
		i += 1

		local e = p.source.emitter
		local host = p.source.host.CFrame
		if e.Drag ~= 0 then
			p.vel *= math.exp(-e.Drag * dt)
		end
		local accel = e.Acceleration
		if e.LockedToPart then
			accel = host:VectorToObjectSpace(accel)
		end
		p.vel += accel * dt
		p.pos += p.vel * dt
		p.rot += p.spin * dt

		local world = if e.LockedToPart then host:PointToWorldSpace(p.pos) else p.pos
		local x, y, perStud = project(rig, world)
		local label = p.label
		if x == nil then
			label.Visible = false
			continue
		end
		local t = p.age / p.life
		local size = evalNumber(e.Size, t) * (perStud :: number)
		local squash = evalNumber(e.Squash, t)
		local w, h = size, size
		if squash > 0 then
			w, h = size * (1 + squash), size / (1 + squash)
		elseif squash < 0 then
			w, h = size / (1 - squash), size * (1 - squash)
		end
		-- A short-lived spark on a many-colour gradient (the Oracle's PRISM) keeps one
		-- colour of it, picked at birth: that is what ToolFX means it to read as.
		local color = evalColor(e.Color, if #e.Color.Keypoints > 2 and p.life < 0.6 then p.shade else t)
		if e.Brightness > 1 then
			color = color:Lerp(Color3.new(1, 1, 1), math.min((e.Brightness - 1) * BRIGHT_WHITEN, 0.3))
		end
		label.Visible = true
		label.Position = UDim2.fromScale(x :: number, y :: number)
		label.Size = UDim2.fromScale(w / rig.aspect, h)
		label.Rotation = p.rot
		label.ImageColor3 = color
		label.ImageTransparency = math.clamp(evalNumber(e.Transparency, t), 0, 1)
	end
end

local function stepHalos(rig: Rig, now: number)
	for index, halo in rig.halos do
		local x, y, perStud = project(rig, halo.host.Position)
		if x == nil or not halo.light.Enabled then
			halo.frame.Visible = false
			continue
		end
		-- A slow breath, out of step between lights, so the pool looks lit, not printed.
		local breath = 1 + 0.08 * math.sin(now * 1.6 + index * 1.7)
		local d = math.min(halo.radius * 2 * (perStud :: number), HALO_MAX) * breath
		halo.frame.Visible = true
		halo.frame.Position = UDim2.fromScale(x :: number, y :: number)
		halo.frame.Size = UDim2.fromScale(d / rig.aspect, d)
	end
end

local function stepMoves(rig: Rig, now: number)
	for _, m in rig.moves do
		local pose = m.rest
		if m.spin ~= 0 then
			pose = CFrame.new(m.pivot) * CFrame.fromAxisAngle(m.axis, (m.spin * now) % (math.pi * 2)) * CFrame.new(-m.pivot) * pose
		end
		if m.bob ~= 0 then
			pose = CFrame.new(0, m.bob * math.sin(now * m.hz * math.pi * 2 + m.phase), 0) * pose
		end
		m.part.CFrame = m.bend.CFrame * pose
	end
end

local function makeHalo(layer: Frame, light: PointLight): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Halo"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = layer
	for _, scale in HALO_RINGS do
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(scale, scale)
		ring.BackgroundColor3 = light.Color
		ring.BackgroundTransparency = HALO_RING_ALPHA
		ring.BorderSizePixel = 0
		ring.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring
	end
	return frame
end

--- The two layers a viewport's FX draw on, made once per viewport: sparks on top of
--- the model (children of the ViewportFrame draw over its 3D), halos under it (a
--- sibling below it, seen through its clear background).
local function layers(viewport: ViewportFrame): (Frame, Frame)
	local sparks = viewport:FindFirstChild(FX_LAYER) :: Frame?
	if sparks == nil then
		local made = Instance.new("Frame")
		made.Name = FX_LAYER
		made.Size = UDim2.fromScale(1, 1)
		made.BackgroundTransparency = 1
		made.ClipsDescendants = true
		made.Parent = viewport
		sparks = made
	end
	local parent = viewport.Parent :: Instance
	local glow = parent:FindFirstChild(GLOW_LAYER) :: Frame?
	if glow == nil then
		local made = Instance.new("Frame")
		made.Name = GLOW_LAYER
		made.Size = UDim2.fromScale(1, 1)
		made.BackgroundTransparency = 1
		made.ClipsDescendants = true
		made.ZIndex = viewport.ZIndex - 1
		made.Parent = parent
		glow = made
	end
	return sparks :: Frame, glow :: Frame
end

--- Stop drawing `viewport`'s FX and clear what it drew. Safe on a viewport with none.
function GearArtFx.clear(viewport: ViewportFrame)
	local rig = rigs[viewport]
	if rig == nil then
		return
	end
	rigs[viewport] = nil
	if rig.connection then
		rig.connection:Disconnect()
	end
	rig.sparks:ClearAllChildren()
	rig.glow:ClearAllChildren()
end

--- Give `model` (already in `viewport`, posed and framed by GearArt) its tier's ToolFX,
--- and start drawing them. `aspect` is the card's design width per unit height.
function GearArtFx.attach(viewport: ViewportFrame, model: Model, track: string, tier: number, aspect: number)
	GearArtFx.clear(viewport)
	ToolFX.apply(model, track, tier)

	local sparks, glow = layers(viewport)
	local rig: Rig = {
		viewport = viewport,
		aspect = aspect,
		sparks = sparks,
		glow = glow,
		emitters = {},
		particles = {},
		halos = {},
		moves = {},
		connection = nil,
	}

	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local parent = d.Parent
			local host = if parent and parent:IsA("Attachment") then parent.Parent else parent
			if host and host:IsA("BasePart") then
				table.insert(rig.emitters, {
					emitter = d,
					host = host,
					attachment = if parent and parent:IsA("Attachment") then parent else nil,
					-- Start part-way through a gap so a slow emitter shows something at once.
					carry = math.random(),
				})
			end
		elseif d:IsA("PointLight") then
			local host = d.Parent
			if host and host:IsA("BasePart") then
				table.insert(rig.halos, {
					frame = makeHalo(glow, d),
					light = d,
					host = host,
					radius = d.Range * HALO_PER_RANGE,
				})
			end
		elseif d:IsA("Weld") and d:HasTag(MOTION_TAG) and d.Part0 and d.Part1 then
			local spin = d:GetAttribute("Spin")
			local bob = d:GetAttribute("Bob")
			local pivot = d:GetAttribute("Pivot")
			local axis = d:GetAttribute("Axis")
			local hz = d:GetAttribute("Hz")
			local phase = d:GetAttribute("Phase")
			table.insert(rig.moves, {
				part = d.Part1,
				bend = d.Part0,
				rest = d.C0,
				pivot = if typeof(pivot) == "Vector3" then pivot else d.C0.Position,
				axis = if typeof(axis) == "Vector3" then axis else Vector3.yAxis,
				spin = if type(spin) == "number" then spin else 0,
				bob = if type(bob) == "number" then bob else 0,
				hz = if type(hz) == "number" then hz else 0.5,
				phase = if type(phase) == "number" then phase else 0,
			})
		end
	end

	if #rig.emitters == 0 and #rig.halos == 0 and #rig.moves == 0 then
		return
	end
	rigs[viewport] = rig

	rig.connection = RunService.RenderStepped:Connect(function(dt: number)
		if model.Parent ~= viewport then
			GearArtFx.clear(viewport)
			return
		end
		if not onScreen(viewport) then
			return
		end
		local now = os.clock()
		-- FAST MODE: no moving parts, sparks or pulsing glow. The halos are laid once so
		-- the card still has its static glow; every frame after that is skipped.
		if Prefs.get("fastMode") == true then
			if not rig.stilled then
				rig.stilled = true
				stepHalos(rig, now)
			end
			return
		end
		rig.stilled = nil
		stepMoves(rig, now)
		stepParticles(rig, math.min(dt, 0.1))
		stepHalos(rig, now)
	end)
end

return GearArtFx
