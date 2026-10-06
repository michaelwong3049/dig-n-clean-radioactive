--!strict
--[[
	MergeReactorController.luau — the Merge Reactor doing things you can watch
	(build/MergeReactor, Services/MergeService).

	THE SERVER NEVER MOVES A PART. A merge bumps `MergeSeq` on the reactor model and
	writes MergeItem / MergeModifier / MergeUid / MergeOutcome beside it; every client
	near the machine plays the same show off those attributes:

	  drop     one copy of the nuke appears over each hopper and sinks into its ooze,
	           which flashes pink
	  charge   the core ball swells, turns Neon and lights up (the only time this prop
	           glows -- Kit's matte rule holds while it idles)
	  burst    sparks, and the outcome's sound: a chime, a fanfare for a crit, a
	           dud for a fail
	  lift     the copy that came out rises from the lift pad inside the dome and turns
	           there for a few seconds, then sinks away

	IDLE, the ooze is alive: a shimmering ForceField skin that slowly heaves, glowing
	motes drifting through it, bubbles climbing the glass and fizzing at the top, and a
	wet gloss on the ooze itself. A reactor that streams out mid-show just stops; everything
	here is cleaned up per machine when the next show starts or the model leaves.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Merge = require(Shared.Config.Merge)
local ItemModels = require(Shared.ItemModels)

local Sfx = require(script.Parent.Parent.Sfx)

local MergeReactor = {}

local TAG = "MergeReactor"
local HOPPERS = 3

local OOZE = Color3.fromHex("A855FF")
local FLASH = Merge.COLOR
local CRIT_GOLD = Color3.fromHex("FFD24A")

--- The size (studs, longest side) a copy is shown at over a hopper and on the lift,
--- at the machine's authored size; scaleOf() blows them up with it.
local DROP_SIZE = 2.4
local LIFT_SIZE = 3.2
local LIFT_RISE = 2.6

local DROP_TIME = 0.7
local CHARGE_TIME = 1.5
local HOLD_TIME = 3.2

type Show = { token: number, bits: { Instance }, conns: { RBXScriptConnection } }

local shows: { [Model]: Show } = {}

--- How much bigger than authored build/MergeReactor made this machine (1 on a world
--- built before the reactor grew).
local function scaleOf(machine: Model): number
	local scale = machine:GetAttribute("Scale")
	return if type(scale) == "number" and scale > 0 then scale else 1
end

local function clear(machine: Model)
	local show = shows[machine]
	if show == nil then
		return
	end
	shows[machine] = nil
	for _, conn in show.conns do
		conn:Disconnect()
	end
	for _, bit in show.bits do
		bit:Destroy()
	end
	local core = machine:FindFirstChild("CoreGlow")
	if core and core:IsA("BasePart") then
		core.Material = Enum.Material.SmoothPlastic
		core.Color = OOZE
		core.Size = core:GetAttribute("RestSize") or core.Size
		core.Transparency = core:GetAttribute("RestTransparency") or core.Transparency
	end
	for index = 1, HOPPERS do
		local ooze = machine:FindFirstChild(`Ooze{index}`)
		if ooze and ooze:IsA("BasePart") then
			ooze.Color = OOZE
		end
	end
end

--- A loose, anchored copy of `itemId`, scaled so its longest side is `size`.
local function copyOf(itemId: string, modifier: string?, size: number): Model?
	if not Items.has(itemId) then
		return nil
	end
	local model = ItemModels.create(Items.get(itemId).model, itemId, modifier)
	if model == nil then
		return nil
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local extent = model:GetExtentsSize()
	local longest = math.max(extent.X, extent.Y, extent.Z)
	if longest > 0 then
		model:ScaleTo(model:GetScale() * size / longest)
	end
	return model
end

--- Move `model` so the middle of its box sits at `at`.
local function place(model: Model, at: CFrame)
	local box = model:GetBoundingBox()
	model:PivotTo(at * box:ToObjectSpace(model:GetPivot()))
end

local function sparks(parent: BasePart, color: Color3, count: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Speed = NumberRange.new(10, 20)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = parent
	emitter:Emit(count)
	task.delay(1.5, function()
		emitter:Destroy()
	end)
end

local function play(machine: Model)
	clear(machine)
	local itemId = machine:GetAttribute("MergeItem")
	local outcome = machine:GetAttribute("MergeOutcome")
	if type(itemId) ~= "string" or type(outcome) ~= "string" then
		return
	end
	local modifier = machine:GetAttribute("MergeModifier") :: string?
	local core = machine:FindFirstChild("CoreGlow") :: BasePart?
	local pad = machine:FindFirstChild("LiftPad") :: BasePart?
	if core == nil or pad == nil then
		return -- not streamed in; nothing to show
	end
	if core:GetAttribute("RestSize") == nil then
		core:SetAttribute("RestSize", core.Size)
		core:SetAttribute("RestTransparency", core.Transparency)
	end
	local rest = core:GetAttribute("RestSize") :: Vector3
	local scale = scaleOf(machine)
	local dropSize, liftSize, liftRise = DROP_SIZE * scale, LIFT_SIZE * scale, LIFT_RISE * scale

	-- A merge someone else watched may name a nuke this client has never drawn: give
	-- the server a moment to send its model (Shared/ItemModels) rather than show
	-- empty hoppers. A newer merge started meanwhile wins.
	local seq = machine:GetAttribute("MergeSeq")
	if not ItemModels.ready(itemId) and Items.has(itemId) and ItemModels.has(Items.get(itemId).model) then
		ItemModels.await(itemId, 1.5)
		if machine:GetAttribute("MergeSeq") ~= seq then
			return
		end
	end

	local show: Show = { token = (machine:GetAttribute("MergeSeq") :: number?) or 0, bits = {}, conns = {} }
	shows[machine] = show
	local function alive(): boolean
		return shows[machine] == show and machine.Parent ~= nil
	end

	-- ── Drop ──
	for index = 1, HOPPERS do
		local drop = machine:FindFirstChild(`Drop{index}`) :: BasePart?
		local ooze = machine:FindFirstChild(`Ooze{index}`) :: BasePart?
		if drop == nil or ooze == nil then
			continue
		end
		local copy = copyOf(itemId, modifier, dropSize)
		if copy then
			copy.Parent = machine
			table.insert(show.bits, copy)
			-- Positions only: the ooze is an upright cylinder, turned on its side in CFrame.
			local from = drop.Position
			local to = ooze.Position
			local began = os.clock() + (index - 1) * 0.12
			local conn: RBXScriptConnection
			conn = RunService.RenderStepped:Connect(function()
				local t = math.clamp((os.clock() - began) / DROP_TIME, 0, 1)
				local eased = t * t
				place(copy, CFrame.new(from:Lerp(to, eased)) * CFrame.Angles(0, t * math.pi * 2, 0))
				if t >= 1 then
					conn:Disconnect()
					copy:Destroy()
				end
			end)
			table.insert(show.conns, conn)
		end
		task.delay(DROP_TIME + (index - 1) * 0.12, function()
			if alive() then
				ooze.Color = FLASH
				TweenService:Create(ooze, TweenInfo.new(0.8), { Color = OOZE }):Play()
			end
		end)
	end
	Sfx.playAt("pour", core)

	-- ── Charge ──
	task.delay(DROP_TIME + 0.2, function()
		if not alive() then
			return
		end
		core.Material = Enum.Material.Neon
		core.Color = FLASH
		local light = Instance.new("PointLight")
		light.Color = FLASH
		light.Range = 0
		light.Brightness = 3
		light.Shadows = false
		light.Parent = core
		table.insert(show.bits, light)
		local grow = TweenInfo.new(CHARGE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(core, grow, { Size = rest * 2 }):Play()
		TweenService:Create(light, grow, { Range = 18 }):Play()
		Sfx.playAt("brew", core)
	end)

	-- ── Burst + lift ──
	task.delay(DROP_TIME + 0.2 + CHARGE_TIME, function()
		if not alive() then
			return
		end
		local color = if outcome == "crit" then CRIT_GOLD elseif outcome == "success" then FLASH else Color3.fromHex("9AA0A6")
		sparks(core, color, if outcome == "crit" then 80 elseif outcome == "success" then 45 else 15)
		Sfx.playAt(if outcome == "crit" then "rareDrop" elseif outcome == "success" then "cleaned" else "denied", core)
		core.Size = rest
		core.Material = Enum.Material.SmoothPlastic
		core.Color = OOZE
		core.Transparency = 1
		-- The flash in the outcome's colour, then the machine goes back to matte.
		local light = core:FindFirstChildOfClass("PointLight")
		if light then
			light.Color = color
			TweenService:Create(light, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Range = 0 }):Play()
		end

		local result = copyOf(itemId, modifier, liftSize)
		if result == nil then
			return
		end
		result.Parent = machine
		table.insert(show.bits, result)
		-- The pad is an upright cylinder too: its height is Size.X.
		local base = CFrame.new(pad.Position + Vector3.new(0, pad.Size.X / 2 + liftSize / 2, 0))
		local began = os.clock()
		local conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - began
			local rise = math.clamp(t / 0.8, 0, 1)
			local sink = math.clamp((t - HOLD_TIME) / 0.6, 0, 1)
			local y = liftRise * (1 - (1 - rise) ^ 3) * (1 - sink)
			place(result, base * CFrame.new(0, y, 0) * CFrame.Angles(0, t * 1.6, 0))
			if sink >= 1 and alive() then
				clear(machine)
			end
		end)
		table.insert(show.conns, conn)
	end)
end

local MOTE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FFD6F2")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("C9A2FF")),
})

--- An invisible, upright, non-colliding part to emit from. Emitter shapes follow the
--- part's own axes (Cylinder/Disc round Y), and the ooze is a cylinder turned on its
--- side, so the emitters ride these instead of the ooze.
local function emitterPart(name: string, cframe: CFrame, size: Vector3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Parent = parent
	return p
end

--- The ooze's living look, once per ooze part. Everything hangs off the ooze itself,
--- so it streams out with it. The ooze is opaque (see build/MergeReactor), so nothing
--- is emitted INSIDE it -- motes and bubbles ride its surface, against the glass.
local function enliven(machine: Model, ooze: BasePart)
	if ooze:FindFirstChild("OozeSheen") then
		return
	end
	local scale = scaleOf(machine)
	-- The cylinder is turned upright: Size.X is its height, Y its diameter.
	local height, across = ooze.Size.X, ooze.Size.Y
	local centre = ooze.Position

	-- A wet gloss on the ooze itself.
	ooze.Reflectance = 0.12

	-- A ForceField skin just proud of the ooze: an animated, refracting shimmer that
	-- reads as liquid moving under its surface. It heaves gently, so the level sloshes.
	local sheen = Instance.new("Part")
	sheen.Name = "OozeSheen"
	sheen.Shape = Enum.PartType.Cylinder
	sheen.Material = Enum.Material.ForceField
	sheen.Color = Color3.fromHex("E07BFF")
	sheen.Anchored = true
	sheen.CanCollide = false
	sheen.CanQuery = false
	sheen.CanTouch = false
	sheen.CastShadow = false
	local lift = 0.1 * scale
	local rest = ooze.Size + Vector3.new(2 * lift, 0.25 * scale, 0.25 * scale)
	sheen.Size = rest
	sheen.CFrame = ooze.CFrame * CFrame.new(lift, 0, 0) -- local X is up
	sheen.Parent = ooze
	local heave = TweenInfo.new(1.6 + math.random() * 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(sheen, heave, {
		Size = rest + Vector3.new(0.4 * scale, 0, 0),
		CFrame = sheen.CFrame * CFrame.new(0.2 * scale, 0, 0),
	}):Play()

	-- The ooze's shell, upright, just outside its skin: what motes and bubbles ride.
	local shell = emitterPart(
		"OozeVolume",
		CFrame.new(centre),
		Vector3.new(across + 0.3 * scale, height, across + 0.3 * scale),
		ooze
	)

	-- Glowing motes suspended in the ooze, drifting and turning slowly.
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Motes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = MOTE
	motes.LightEmission = 0.7
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.18 * scale),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Lifetime = NumberRange.new(2, 3.5)
	motes.Speed = NumberRange.new(0.05 * scale, 0.2 * scale)
	motes.Acceleration = Vector3.new(0, 0.12 * scale, 0)
	motes.RotSpeed = NumberRange.new(-60, 60)
	motes.Rotation = NumberRange.new(0, 360)
	motes.Shape = Enum.ParticleEmitterShape.Cylinder
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Rate = 8
	motes.Parent = shell

	-- Bubbles climbing the inside of the glass, swelling as they rise.
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bubbles"
	bubbles.Color = ColorSequence.new(Color3.fromHex("F1E4FF"))
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.07 * scale),
		NumberSequenceKeypoint.new(1, 0.2 * scale),
	})
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.85, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- Gone by the time they reach the surface, from anywhere up the side.
	local speed = 1.4 * scale
	bubbles.Lifetime = NumberRange.new(0.2 * height / speed, height / speed)
	bubbles.Speed = NumberRange.new(speed)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.Shape = Enum.ParticleEmitterShape.Cylinder
	bubbles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	bubbles.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	bubbles.SpreadAngle = Vector2.new(3, 3)
	bubbles.Rate = 6
	bubbles.Parent = shell

	-- Fizz where they break the surface: quick pops spat a little way up and falling back.
	local top = emitterPart(
		"OozeTop",
		CFrame.new(centre + Vector3.new(0, height / 2 + 0.1 * scale, 0)),
		Vector3.new(across, 0.1, across),
		ooze
	)
	local fizz = Instance.new("ParticleEmitter")
	fizz.Name = "Fizz"
	fizz.Color = ColorSequence.new(Color3.fromHex("F1E4FF"))
	fizz.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16 * scale),
		NumberSequenceKeypoint.new(1, 0.03 * scale),
	})
	fizz.Transparency = NumberSequence.new(0.3, 1)
	fizz.Lifetime = NumberRange.new(0.3, 0.6)
	fizz.Speed = NumberRange.new(0.6 * scale, 1.4 * scale)
	fizz.Acceleration = Vector3.new(0, -4 * scale, 0)
	fizz.EmissionDirection = Enum.NormalId.Top
	fizz.Shape = Enum.ParticleEmitterShape.Disc
	fizz.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	fizz.SpreadAngle = Vector2.new(25, 25)
	fizz.Rate = 5
	fizz.Parent = top
end

local function bubble(machine: Model)
	for index = 1, HOPPERS do
		local ooze = machine:FindFirstChild(`Ooze{index}`)
		if ooze and ooze:IsA("BasePart") then
			enliven(machine, ooze)
		end
	end
end

local function watch(machine: Instance)
	if not machine:IsA("Model") then
		return
	end
	bubble(machine)
	-- Parts stream in after the model; give the bubbles a second chance.
	machine.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and string.match(d.Name, "^Ooze%d+$") then
			bubble(machine)
		end
	end)
	machine:GetAttributeChangedSignal("MergeSeq"):Connect(function()
		local ok, err = pcall(play, machine)
		if not ok then
			warn(`[merge] reactor show failed: {err}`)
		end
	end)
	machine.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clear(machine)
		end
	end)
end

function MergeReactor.start()
	for _, machine in CollectionService:GetTagged(TAG) do
		watch(machine)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
end

return MergeReactor
