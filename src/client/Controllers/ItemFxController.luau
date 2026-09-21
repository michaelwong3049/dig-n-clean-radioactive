--!strict
--[[
	ItemFxController.luau — makes the imported nukes glow, go see-through and turn.

	WHAT IT READS. Any model tagged `ItemFx` (Shared/ItemFx.tag, called for every
	clone in ItemModels.create) with an `FxId` attribute naming its Config/ItemFx
	entry. That covers the wash stand, the off hand, exhibit stands, locker bays and
	the model yard, with no per-service wiring.

	NOTHING UNTIL THE CRUST IS GONE. A tracked model waits while ItemCrust.isCrusted
	is true, and switches on the moment it is not: at the wash reveal, when
	ItemCrust.clear takes the crust's light down. The first check waits a beat,
	because WashService parents the model before it encases it, and the rock can
	land on the client a moment after the item. After that a crust never comes back
	on the same model: ToolService builds a new one when the crust count changes.

	ALL OF IT IS LOCAL. Materials, colours, lights, particles and part motion are
	written on this client only. The server's parts are untouched, so nothing
	replicates per frame and each player culls by their own distance.

	SPINS NEED AN ANCHORED MODEL. A held item is welded into one body and hung off
	the hand (ToolService), and moving one of its parts would drag the assembly. It
	gets the glow, light and pulse; its rings stay still.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local ItemFx = require(Shared.ItemFx)
local ItemCrust = require(Shared.ItemCrust)
local ItemFxConfig = require(Shared.Config.ItemFx)

type Def = ItemFxConfig.ItemFxDef
type Anim = ItemFxConfig.Anim

local Controller = {}

--- Longest extent every imported template is baked to (import-nuke-models.luau's
--- NATURAL_SIZE). Particle sizes are authored for it and scale with each context's
--- display size.
local REFERENCE_SIZE = 7.02

--- How long a model waits after it arrives before the first crust check. Covers
--- WashService parenting the model before `encase` puts the rock on.
local ACTIVATE_GRACE = 0.4

--- Backstop re-check for a waiting model, in case a crust light's removal is
--- missed.
local POLL_INTERVAL = 0.5

--- The light eases up from nothing over this long, so the reveal visibly switches on.
local IGNITE_TIME = 0.8

--- Beyond this distance from the camera, animation stops and emitters switch off.
local AWAKE_RANGE = 150

--- How far a fully dimmed glow part drops toward black. Short of 1 so an "off"
--- lamp still reads as a coloured lens, not a hole.
local DIM_DEPTH = 0.85

--- Skip writing a part's colour/transparency again when the wave has moved less
--- than this since the last write.
local WRITE_EPSILON = 0.004

local PING_TIME = 0.9

local BLACK = Color3.new(0, 0, 0)
local TAU = math.pi * 2

type Channel = { value: number, nextAt: number, untilAt: number, last: number }

type AnimRun = {
	anim: Anim,
	parts: { BasePart },
	baseColor: { [BasePart]: Color3 },
	baseTransparency: { [BasePart]: number },
	channels: { Channel },
	phaseOf: { [BasePart]: number },
}

type SpinGroup = {
	pivot: BasePart,
	parts: { BasePart },
	rel: { CFrame },
	axis: Vector3,
	radPerSecond: number,
	angle: number,
	parent: number?,
}

type Entry = {
	model: Model,
	def: Def,
	active: boolean,
	checkAt: number,
	startedAt: number,
	rng: Random,
	awake: boolean,
	light: PointLight?,
	lightBase: number,
	lightRun: AnimRun?,
	emitters: { ParticleEmitter },
	anims: { AnimRun },
	spins: { SpinGroup },
	ping: CylinderHandleAdornment?,
	pingIndex: number,
	pingAt: number,
	pingReach: number,
	scale: number,
	connections: { RBXScriptConnection },
}

local entries: { [Model]: Entry } = {}

local function smoothstep(x: number): number
	local t = math.clamp(x, 0, 1)
	return t * t * (3 - 2 * t)
end

local function seedOf(model: Model): number
	-- Different models run out of step, so a row of the same nuke on exhibit does
	-- not blink in unison.
	return (math.floor(os.clock() * 1000) + #model:GetFullName() * 7919) % 2147483647
end

-- ── Finish ───────────────────────────────────────────────────────────────

local function applyFinish(model: Model, def: Def)
	for _, finish in def.finish or {} do
		local parts = ItemFx.partsNamed(model, finish.parts)
		for _, part in parts do
			if finish.material or finish.color then
				-- The SurfaceAppearance overrides both material and colour; it has to go
				-- for either to show.
				for _, child in part:GetChildren() do
					if child:IsA("SurfaceAppearance") then
						child:Destroy()
					end
				end
			end
			if finish.material then
				part.Material = (Enum.Material :: any)[finish.material]
			end
			if finish.color then
				part.Color = finish.color
			end
			if finish.transparency then
				part.Transparency = finish.transparency
			end
			local ramp = finish.ramp
			if ramp then
				local level = tonumber(string.match(part.Name, "%d+")) or 1
				local t = if ramp.levels > 1 then (level - 1) / (ramp.levels - 1) else 0
				part.Transparency = ramp.from + (ramp.to - ramp.from) * math.clamp(t, 0, 1)
			end
		end
	end
end

-- ── Particles ────────────────────────────────────────────────────────────
-- The same four shapes as the tool FX in PR #192 (Shared/ToolFX): LightEmission 1,
-- sizes and speeds authored at REFERENCE_SIZE and scaled per context.

local function emitter(color: Color3, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "ItemFxEmitter"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	return e
end

local PRESETS: { [string]: (Color3, number, number) -> ParticleEmitter } = {
	-- Slow upward drift, fading: a core quietly giving off light.
	drift = function(color, rate, s)
		local e = emitter(color, rate)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22 * s), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(1.0, 1.8)
		e.Speed = NumberRange.new(0.3 * s, 0.7 * s)
		e.SpreadAngle = Vector2.new(18, 18)
		e.EmissionDirection = Enum.NormalId.Top
		return e
	end,
	-- Quick twinkles in place.
	sparkle = function(color, rate, s)
		local e = emitter(color, rate)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.14 * s),
			NumberSequenceKeypoint.new(0.5, 0.2 * s),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.35, 0.7)
		e.Speed = NumberRange.new(0.1 * s, 0.3 * s)
		e.SpreadAngle = Vector2.new(180, 180)
		return e
	end,
	-- Short, punchy discharge.
	arcSpark = function(color, rate, s)
		local e = emitter(color, rate)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16 * s), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.08, 0.18)
		e.Speed = NumberRange.new(2 * s, 4 * s)
		e.SpreadAngle = Vector2.new(35, 35)
		return e
	end,
	-- Motes that hang close and shrink to nothing: pulling IN, not glowing out.
	shrinkMotes = function(color, rate, s)
		local e = emitter(color, rate)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3 * s), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.8, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(0.15 * s, 0.35 * s)
		e.SpreadAngle = Vector2.new(180, 180)
		return e
	end,
}

-- ── Waves ────────────────────────────────────────────────────────────────

--- 0..1 for the deterministic kinds at cycle position `u` (0..1).
local function shape(kind: string, u: number, anim: Anim): number
	if kind == "pulse" then
		return 0.5 - 0.5 * math.cos(u * TAU)
	elseif kind == "flash" then
		-- Up in a blink, then a long fall: bright, then fading away.
		if u < 0.06 then
			return u / 0.06
		end
		return math.exp(-(u - 0.06) * 5)
	elseif kind == "heartbeat" then
		local function bump(centre: number): number
			local d = (u - centre) / 0.045
			return math.exp(-d * d)
		end
		return math.max(bump(0.08), 0.7 * bump(0.26))
	elseif kind == "blink" then
		return if u < (anim.duty or 0.15) then 1 else 0
	end
	return 1
end

--- Advance a random channel (flicker / wink) and return its 0..1 value.
local function step(channel: Channel, anim: Anim, now: number, rng: Random): number
	if anim.kind == "flicker" then
		if now >= channel.nextAt then
			local on = rng:NextNumber() < (anim.onChance or 0.72)
			channel.value = if on then rng:NextNumber(0.6, 1) else 0
			channel.nextAt = now + anim.period * rng:NextNumber(0.4, 1.8)
			if not on and rng:NextNumber() < 0.15 then
				-- Now and then the connection drops out for a proper gap.
				channel.nextAt += anim.period * rng:NextNumber(2, 8)
			end
		end
	elseif anim.kind == "wink" then
		if channel.value == 0 and now >= channel.untilAt then
			channel.value = 1
		elseif channel.value == 1 and now >= channel.nextAt then
			channel.value = 0
			channel.untilAt = now + (anim.duration or 0.12)
			channel.nextAt = now + anim.period * rng:NextNumber(0.73, 1.27)
		end
	end
	return channel.value
end

local function isRandom(kind: string): boolean
	return kind == "flicker" or kind == "wink"
end

local function writePart(run: AnimRun, part: BasePart, factor: number)
	if run.anim.mode == "transparency" then
		local base = run.baseTransparency[part] or 0
		part.Transparency = base + (1 - base) * (1 - factor)
	else
		local base = run.baseColor[part] or part.Color
		part.Color = base:Lerp(BLACK, (1 - factor) * DIM_DEPTH)
	end
end

local function colorAt(colors: { Color3 }, u: number): Color3
	local count = #colors
	if count == 0 then
		return BLACK
	elseif count == 1 then
		return colors[1]
	end
	local pos = (u % 1) * count
	local index = math.floor(pos)
	local from = colors[index + 1]
	local to = colors[(index + 1) % count + 1]
	return from:Lerp(to, smoothstep(pos - index))
end

local function makeRun(model: Model, anim: Anim, now: number, rng: Random): AnimRun
	local parts = if anim.parts then ItemFx.partsNamed(model, anim.parts) else {}
	local run: AnimRun = {
		anim = anim,
		parts = parts,
		baseColor = {},
		baseTransparency = {},
		channels = {},
		phaseOf = {},
	}
	local highest = 1
	for _, part in parts do
		run.baseColor[part] = part.Color
		run.baseTransparency[part] = part.Transparency
		highest = math.max(highest, tonumber(string.match(part.Name, "%d+")) or 1)
	end
	for _, part in parts do
		-- colorCycle staggers by the number in the part's name, so a ribbon's end caps
		-- stay in step with the ribbon they belong to.
		local number = tonumber(string.match(part.Name, "%d+")) or 1
		run.phaseOf[part] = (number - 1) / highest
	end
	local channelCount = if anim.perPart then math.max(#parts, 1) else 1
	for _ = 1, channelCount do
		table.insert(run.channels, {
			value = 1,
			nextAt = now + anim.period * rng:NextNumber(0.2, 1.5),
			untilAt = 0,
			last = -1,
		})
	end
	return run
end

--- Drive one run's parts; returns its (shared) 0..1 factor for the light.
local function stepRun(run: AnimRun, t: number, now: number, rng: Random): number
	local anim = run.anim
	local low = anim.min or 0

	if anim.kind == "colorCycle" then
		for _, part in run.parts do
			part.Color = colorAt(anim.colors or {}, t / anim.period + run.phaseOf[part])
		end
		return 1
	end

	if anim.perPart and isRandom(anim.kind) then
		for index, part in run.parts do
			local channel = run.channels[index]
			local factor = low + (1 - low) * step(channel, anim, now, rng)
			if math.abs(factor - channel.last) > WRITE_EPSILON then
				channel.last = factor
				writePart(run, part, factor)
			end
		end
		return 1
	end

	local raw = if isRandom(anim.kind)
		then step(run.channels[1], anim, now, rng)
		else shape(anim.kind, (t / anim.period) % 1, anim)
	local factor = low + (1 - low) * raw
	local channel = run.channels[1]
	if math.abs(factor - channel.last) > WRITE_EPSILON then
		channel.last = factor
		for _, part in run.parts do
			writePart(run, part, factor)
		end
	end
	return factor
end

-- ── Spins ────────────────────────────────────────────────────────────────

local AXES: { [string]: Vector3 } = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }

local function buildSpins(model: Model, def: Def): { SpinGroup }
	local groups: { SpinGroup } = {}
	if def.spins == nil then
		return groups
	end
	local claimed: { [BasePart]: boolean } = {}

	for _, spin in def.spins do
		local pivot = ItemFx.firstPart(model, spin.pivot)
		if pivot == nil or not pivot.Anchored then
			-- Held (welded, unanchored) or missing its pivot: no spins at all, rather
			-- than half a gimbal turning.
			return {}
		end
		claimed[pivot] = true

		local candidates: { BasePart }
		if spin.parts then
			candidates = ItemFx.partsNamed(model, spin.parts)
		else
			candidates = {}
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					local excluded = false
					for _, name in spin.except or {} do
						if ItemFx.matches(descendant.Name, name) then
							excluded = true
							break
						end
					end
					if not excluded then
						table.insert(candidates, descendant)
					end
				end
			end
		end

		local axis = AXES[spin.axis or "Y"] or Vector3.yAxis
		if spin.axisParts and #spin.axisParts == 2 then
			local from = ItemFx.firstPart(model, spin.axisParts[1])
			local to = ItemFx.firstPart(model, spin.axisParts[2])
			if from and to and (to.Position - from.Position).Magnitude > 1e-3 then
				axis = pivot.CFrame:VectorToObjectSpace(to.Position - from.Position).Unit
			end
		end

		local group: SpinGroup = {
			pivot = pivot,
			parts = {},
			rel = {},
			axis = axis,
			radPerSecond = spin.rpm * TAU / 60,
			angle = 0,
			parent = spin.parent,
		}
		for _, part in candidates do
			if not claimed[part] then
				claimed[part] = true
				table.insert(group.parts, part)
				table.insert(group.rel, pivot.CFrame:ToObjectSpace(part.CFrame))
			end
		end
		table.insert(groups, group)
	end
	return groups
end

local function stepSpins(groups: { SpinGroup }, dt: number)
	-- Parents come before children in Config (Spec checks it), so each group's
	-- chain is ready by the time a child asks for it.
	local chains: { CFrame } = {}
	for index, group in groups do
		group.angle = (group.angle + group.radPerSecond * dt) % TAU
		local own = CFrame.fromAxisAngle(group.axis, group.angle)
		local parentChain = if group.parent then chains[group.parent] else nil
		local chain = if parentChain then parentChain * own else own
		chains[index] = chain

		local base = group.pivot.CFrame * chain
		for i, part in group.parts do
			part.CFrame = base * group.rel[i]
		end
	end
end

-- ── Lifecycle ────────────────────────────────────────────────────────────

local function activate(entry: Entry, now: number)
	local model, def = entry.model, entry.def
	local longest = 0
	do
		local extents = model:GetExtentsSize()
		longest = math.max(extents.X, extents.Y, extents.Z)
	end
	entry.scale = math.max(longest / REFERENCE_SIZE, 0.05)

	applyFinish(model, def)

	if def.light then
		local part = ItemFx.firstPart(model, def.light.part)
		if part then
			local light = Instance.new("PointLight")
			light.Name = "ItemFxLight"
			light.Color = def.light.color
			light.Range = math.clamp(longest * def.light.range, 3, 60)
			light.Brightness = 0
			light.Shadows = false
			light.Parent = part
			entry.light = light
			entry.lightBase = def.light.brightness
		end
	end

	for _, particles in def.particles or {} do
		local part = ItemFx.firstPart(model, particles.part)
		local build = PRESETS[particles.preset]
		if part and build then
			local e = build(particles.color, particles.rate, entry.scale)
			e.Parent = part
			table.insert(entry.emitters, e)
		end
	end

	for _, anim in def.anims or {} do
		local run = makeRun(model, anim, now, entry.rng)
		table.insert(entry.anims, run)
		if anim.light then
			entry.lightRun = run
		end
	end

	entry.spins = buildSpins(model, def)

	if def.ping then
		local part = ItemFx.firstPart(model, def.ping.part)
		if part then
			local ring = Instance.new("CylinderHandleAdornment")
			ring.Name = "ItemFxPing"
			ring.Adornee = part
			-- The cylinder's axis is its local Z; turned onto Y the ring lies flat.
			ring.CFrame = CFrame.Angles(math.rad(90), 0, 0)
			ring.Color3 = def.ping.color
			ring.Height = 0.04 * entry.scale
			ring.Radius = 0.1
			ring.InnerRadius = 0
			ring.Transparency = 1
			ring.AlwaysOnTop = false
			ring.ZIndex = 0
			ring.Parent = part
			entry.ping = ring
			local extents = model:GetExtentsSize()
			entry.pingReach = math.max(extents.X, extents.Z) * 0.9
		end
	end

	entry.active = true
	entry.startedAt = now
	entry.awake = true
end

local function untrack(model: Model)
	local entry = entries[model]
	if entry == nil then
		return
	end
	entries[model] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or entries[instance] then
		return
	end
	local model = instance :: Model
	local def = ItemFx.get(model:GetAttribute(ItemFx.ATTRIBUTE) :: string?)
	if def == nil then
		return
	end

	local now = os.clock()
	local entry: Entry = {
		model = model,
		def = def,
		active = false,
		checkAt = now + ACTIVATE_GRACE,
		startedAt = now,
		rng = Random.new(seedOf(model)),
		awake = false,
		light = nil,
		lightBase = 0,
		lightRun = nil,
		emitters = {},
		anims = {},
		spins = {},
		ping = nil,
		pingIndex = -1,
		pingAt = -math.huge,
		pingReach = 1,
		scale = 1,
		connections = {},
	}
	entries[model] = entry

	-- The crust coming off is the cue; check again straight after it goes.
	table.insert(
		entry.connections,
		model.DescendantRemoving:Connect(function(descendant)
			if descendant.Name == ItemCrust.GLOW_NAME and not entry.active then
				entry.checkAt = math.min(entry.checkAt, os.clock() + 0.05)
			end
		end)
	)
	table.insert(
		entry.connections,
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(game) then
				untrack(model)
			end
		end)
	)
end

local function stepEntry(entry: Entry, now: number, dt: number, cameraPosition: Vector3)
	local model = entry.model

	if not entry.active then
		if now >= entry.checkAt then
			entry.checkAt = now + POLL_INTERVAL
			if model.Parent and not ItemCrust.isCrusted(model) then
				activate(entry, now)
			end
		end
		return
	end

	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local awake = anchor ~= nil and (anchor.Position - cameraPosition).Magnitude <= AWAKE_RANGE
	if awake ~= entry.awake then
		entry.awake = awake
		for _, e in entry.emitters do
			e.Enabled = awake
		end
	end
	if not awake then
		return
	end

	local t = now - entry.startedAt
	local lightFactor = 1
	for _, run in entry.anims do
		local factor = stepRun(run, t, now, entry.rng)
		if run == entry.lightRun then
			lightFactor = factor
		end
	end

	local light = entry.light
	if light then
		light.Brightness = entry.lightBase * lightFactor * smoothstep(t / IGNITE_TIME)
	end

	if #entry.spins > 0 then
		stepSpins(entry.spins, dt)
	end

	local ping = entry.ping
	local pingDef = entry.def.ping
	if ping and pingDef then
		local index = math.floor(t / pingDef.period)
		if index ~= entry.pingIndex then
			entry.pingIndex = index
			entry.pingAt = now
		end
		local p = (now - entry.pingAt) / PING_TIME
		if p >= 1 then
			ping.Transparency = 1
		else
			local eased = 1 - (1 - p) * (1 - p)
			local radius = 0.1 + entry.pingReach * eased
			ping.Radius = radius
			ping.InnerRadius = math.max(radius - 0.14 * entry.scale, 0)
			ping.Transparency = 0.25 + 0.75 * p
		end
	end
end

function Controller.start()
	for _, instance in CollectionService:GetTagged(ItemFx.TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(ItemFx.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(ItemFx.TAG):Connect(function(instance)
		if instance:IsA("Model") then
			untrack(instance :: Model)
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		if next(entries) == nil then
			return
		end
		local camera = Workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		local now = os.clock()
		for _, entry in entries do
			stepEntry(entry, now, dt, cameraPosition)
		end
	end)
end

return Controller
