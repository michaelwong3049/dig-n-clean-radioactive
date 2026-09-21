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

	THE GLINT IS A TEXTURE, NOT A LIGHT. A Texture on a MeshPart is projected onto
	the mesh itself, so it clips to the silhouette and follows every curve, and a
	Color3 above 1 makes it read as light rather than paint. A PointLight sweeping
	the surface was tried first and barely registers in daylight.

	WHY A VERTICAL STREAK, NOT A DIAGONAL. A face's texture only covers the part of
	a round mesh that faces that way, so a diagonal band stops dead where the front
	hands over to the top. A vertical streak is one world-space plane: the camera-
	facing side and the top both have a texture axis along the sweep, so the same
	plane lands on both and the streak runs unbroken up the side and over the dome.
	It is also what a real highlight on a round, polished thing looks like. Each
	part gets its own offset so the streak lines up across the whole group. It
	fades in and out at the ends of a pass, where it crosses into the sides the
	texture can't reach.
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
type Glint = ItemFxConfig.Glint

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

--- The glint streak, white with the shape in alpha: a bright core, a faint halo and
--- a thin twin line either side. It varies only across U and is symmetric, so it
--- reads the same whichever way a face's U runs. Generated for this effect and
--- uploaded 2026-09-21.
local GLINT_TEXTURE = "rbxassetid://82985290105398"

--- A streak along a face's V (only the Top face, when the sweep runs along Z)
--- can't use that image, so it uses the first one: one diagonal band per tile,
--- stood upright by stretching U out to GLINT_LONG. Its twin line is on one side
--- only.
local GLINT_TEXTURE_V = "rbxassetid://102040958373097"
local GLINT_LONG = 4096

--- The tile is this many times the group's width across the sweep, so one streak
--- crosses every part before the next copy of the tile reaches any of them. The
--- streak's thickness scales with it too.
local GLINT_TILE_SLACK = 1.8

--- The streak starts and ends this fraction of a tile beyond the group's edges.
local GLINT_MARGIN = 0.08

--- Fraction of a pass spent fading in, and again fading out.
local GLINT_FADE = 0.22

--- A star only flashes on a spot turned at least this far toward the camera; a
--- flare on the far side of the part would hang in the air at its silhouette.
local STAR_FACING = 0.2

--- Chance each star flashes as the band crosses it, so passes don't all look alike.
local STAR_CHANCE = 0.7

--- A soft flame tongue, white with the shape in alpha, tinted by the emitter.
--- Generated and uploaded 2026-09-21. The built-in fire_main.dds is only half of
--- the legacy Fire's art (its alpha lives in another file) and draws as a dull
--- speckled cloud; a Fire instance can't go under 2 studs, the size of a whole
--- nuke on the wash stand.
local FLAME_TEXTURE = "rbxassetid://80667240595677"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local TAU = math.pi * 2

type Channel = {
	value: number,
	nextAt: number,
	untilAt: number,
	last: number,
	color: Color3?,
}

type AnimRun = {
	anim: Anim,
	parts: { BasePart },
	baseColor: { [BasePart]: Color3 },
	baseTransparency: { [BasePart]: number },
	appearance: { [BasePart]: SurfaceAppearance },
	channels: { Channel },
	phaseOf: { [BasePart]: number },
}

type SpinGroup = {
	spin: ItemFxConfig.Spin,
	pivot: BasePart,
	-- The pivot's rest pose, held relative to a part no group moves. Read back
	-- through that part every frame, so the pivot can turn inside its own group and
	-- a server re-pivot still carries the whole rig along.
	pivotOffset: CFrame,
	parts: { BasePart },
	rel: { CFrame },
	axis: Vector3,
	angle: number,
	parent: number?,
	twitchAt: number,
	twitchUntil: number,
}

type Burst = { emitter: ParticleEmitter, every: number, count: number, nextAt: number }

-- One Texture of the glint. Each part carries two: one for whichever side faces
-- the camera, one for its top. The rest is set per pass.
type GlintLayer = {
	part: BasePart,
	texture: Texture,
	top: boolean,
	-- Whether this face shows the band this pass, whether the band runs along its
	-- U (else V), which way that axis points along the sweep (+1/-1), and the
	-- sweep coordinate of the texture's origin corner.
	live: boolean,
	onU: boolean,
	sign: number,
	origin: number,
}

type Star = {
	part: BasePart,
	emitter: ParticleEmitter,
	-- Where the spot sits and which way it faces, in the reference part's space.
	position: Vector3,
	normal: Vector3,
	-- The band coordinate of this spot on the current pass, and whether it has had
	-- its chance to flash yet.
	at: number,
	done: boolean,
}

type GlintRun = {
	def: Glint,
	ref: BasePart,
	layers: { GlintLayer },
	stars: { Star },
	nextAt: number,
	passAt: number?,
	lo: number,
	hi: number,
	tile: number,
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
	bursts: { Burst },
	anims: { AnimRun },
	spins: { SpinGroup },
	spinRef: BasePart?,
	glint: GlintRun?,
	seam: CylinderHandleAdornment?,
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
			if finish.reflectance then
				part.Reflectance = finish.reflectance
			end
			if finish.tint then
				-- Multiplies the painted colour map; the texture's detail stays.
				for _, child in part:GetChildren() do
					if child:IsA("SurfaceAppearance") then
						child.Color = finish.tint
					end
				end
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
-- The first four are the shapes of the tool FX in PR #192 (Shared/ToolFX):
-- LightEmission 1, sizes and speeds authored at REFERENCE_SIZE and scaled per
-- context. The rest are for heat, pressure and growth.

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
	-- A thin dark wisp rising and spreading: something still smouldering. Smoke is
	-- lit by the scene, not glowing, so LightEmission goes back to 0.
	smoke = function(color, rate, s)
		local e = emitter(color, rate)
		e.Texture = SMOKE_TEXTURE
		e.LightEmission = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2 * s), NumberSequenceKeypoint.new(1, 0.9 * s) })
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.3, 0.6),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(1.6, 2.6)
		e.Speed = NumberRange.new(0.3 * s, 0.6 * s)
		e.SpreadAngle = Vector2.new(12, 12)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-30, 30)
		e.EmissionDirection = Enum.NormalId.Top
		return e
	end,
	-- Hot flecks climbing and winking out.
	ember = function(color, rate, s)
		local e = emitter(color, rate)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.09 * s), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.6, 1.3)
		e.Speed = NumberRange.new(0.6 * s, 1.2 * s)
		e.SpreadAngle = Vector2.new(25, 25)
		e.Acceleration = Vector3.new(0, 0.4 * s, 0)
		e.EmissionDirection = Enum.NormalId.Top
		return e
	end,
	-- A pale puff out of a relief valve: fast, then gone.
	steam = function(color, rate, s)
		local e = emitter(color, rate)
		e.Texture = SMOKE_TEXTURE
		e.LightEmission = 0.2
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15 * s), NumberSequenceKeypoint.new(1, 0.8 * s) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(1.5 * s, 2.5 * s)
		e.Drag = 3
		e.SpreadAngle = Vector2.new(20, 20)
		e.Rotation = NumberRange.new(0, 360)
		e.EmissionDirection = Enum.NormalId.Top
		return e
	end,
	-- Slow lazy motes drifting off in every direction.
	spore = function(color, rate, s)
		local e = emitter(color, rate)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, 0.12 * s),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(2, 3.5)
		e.Speed = NumberRange.new(0.15 * s, 0.35 * s)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 0.05 * s, 0)
		return e
	end,
	-- Small tongues of flame licking up off torn metal: hot yellow at the root,
	-- `color` through the body, going dark red as they burn out. Short-lived, so
	-- they read as flames on the part rather than a fire beside it.
	flame = function(color, rate, s)
		local e = emitter(color, rate)
		e.Texture = FLAME_TEXTURE
		e.LightInfluence = 0
		e.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("FFE9A8")),
			ColorSequenceKeypoint.new(0.35, color),
			ColorSequenceKeypoint.new(1, Color3.fromHex("8A1E08")),
		})
		-- Sizes vary per tongue (the envelopes), and each one stretches tall and
		-- thin as it burns out, so the fire flickers instead of sitting like a
		-- candle flame.
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.16 * s, 0.05 * s),
			NumberSequenceKeypoint.new(0.35, 0.3 * s, 0.1 * s),
			NumberSequenceKeypoint.new(1, 0.04 * s),
		})
		e.Squash = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, -0.35) })
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.12, 0.1),
			NumberSequenceKeypoint.new(0.6, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(0.22, 0.45)
		e.Speed = NumberRange.new(0.6 * s, 1.5 * s)
		e.SpreadAngle = Vector2.new(22, 22)
		e.Acceleration = Vector3.new(0, 1.6 * s, 0)
		e.Rotation = NumberRange.new(-20, 20)
		e.RotSpeed = NumberRange.new(-70, 70)
		e.EmissionDirection = Enum.NormalId.Top
		-- Tongues stay upright however the camera tilts.
		e.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
		return e
	end,
}

--- A star flare for the glint: a four-point sparkle that blooms and shrinks in a
--- blink, in place, drawn a little toward the camera so the surface can't clip it.
local function starEmitter(color: Color3, size: number): ParticleEmitter
	local e = emitter(color, 0)
	e.Name = "ItemFxStar"
	e.LightInfluence = 0
	e.Brightness = 2
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0)
	e.Lifetime = NumberRange.new(0.3, 0.45)
	e.Speed = NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 45)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.ZOffset = size
	e.LockedToPart = true
	return e
end

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

--- Kinds that always give every part its own stream: a glitter in unison is just a
--- flash, and embers breathing together read as one lamp.
local function isPerPart(anim: Anim): boolean
	return anim.perPart == true or anim.stagger == true or anim.kind == "glitter" or anim.kind == "smoulder"
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
		appearance = {},
		channels = {},
		phaseOf = {},
	}
	local highest = 1
	for _, part in parts do
		run.baseColor[part] = part.Color
		run.baseTransparency[part] = part.Transparency
		run.appearance[part] = part:FindFirstChildWhichIsA("SurfaceAppearance")
		highest = math.max(highest, tonumber(string.match(part.Name, "%d+")) or 1)
	end
	if anim.kind == "smoulder" then
		-- Each ember on its own random phase: no two breathe in step.
		for _, part in parts do
			run.phaseOf[part] = rng:NextNumber()
		end
	elseif anim.stagger then
		-- Evenly round one period in name order: Key11, Key12 ... Key33 chase.
		table.sort(parts, function(a, b)
			return a.Name < b.Name
		end)
		for index, part in parts do
			run.phaseOf[part] = (index - 1) / #parts
		end
	else
		for _, part in parts do
			-- colorCycle staggers by the number in the part's name, so a ribbon's end
			-- caps stay in step with the ribbon they belong to.
			local number = tonumber(string.match(part.Name, "%d+")) or 1
			run.phaseOf[part] = (number - 1) / highest
		end
	end
	local channelCount = if isPerPart(anim) then math.max(#parts, 1) else 1
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
			local color = colorAt(anim.colors or {}, t / anim.period + run.phaseOf[part])
			if anim.mode == "tint" then
				local appearance = run.appearance[part]
				if appearance then
					appearance.Color = color
				end
			else
				part.Color = color
			end
		end
		return 1
	end

	if anim.kind == "smoulder" then
		-- Three sines at unrelated rates: never repeats visibly, never jumps.
		local total = 0
		local u = t / anim.period
		for index, part in run.parts do
			local phase = run.phaseOf[part]
			local wave = 0.55 * math.sin(TAU * (u + phase))
				+ 0.3 * math.sin(TAU * (u * 2.37 + phase * 7.3))
				+ 0.15 * math.sin(TAU * (u * 5.13 + phase * 13.1))
			local factor = low + (1 - low) * (0.5 + 0.5 * wave)
			total += factor
			local channel = run.channels[index]
			if math.abs(factor - channel.last) > WRITE_EPSILON then
				channel.last = factor
				writePart(run, part, factor)
			end
		end
		return if #run.parts > 0 then total / #run.parts else 1
	end

	if anim.kind == "glitter" then
		-- Each part, on its own timer, flashes from its colour toward white (or one
		-- of `colors`, picked per flash): up in a blink, then fading back.
		local duration = anim.duration or 0.25
		local colors = anim.colors
		for index, part in run.parts do
			local channel = run.channels[index]
			if now >= channel.nextAt then
				channel.untilAt = now + duration
				channel.nextAt = now + anim.period * rng:NextNumber(0.5, 1.5)
				channel.color = if colors and #colors > 0 then colors[rng:NextInteger(1, #colors)] else WHITE
			end
			local amount = 0
			local left = channel.untilAt - now
			if left > 0 then
				local into = 1 - left / duration
				amount = if into < 0.15 then into / 0.15 else (1 - into) / 0.85
			end
			if math.abs(amount - channel.last) > WRITE_EPSILON then
				channel.last = amount
				part.Color = run.baseColor[part]:Lerp(channel.color or WHITE, amount)
			end
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

	if anim.stagger and not isRandom(anim.kind) then
		for index, part in run.parts do
			local channel = run.channels[index]
			local u = (t / anim.period + run.phaseOf[part]) % 1
			local factor = low + (1 - low) * shape(anim.kind, u, anim)
			if math.abs(factor - channel.last) > WRITE_EPSILON then
				channel.last = factor
				writePart(run, part, factor)
			end
		end
		-- A light on a staggered run follows the unshifted wave.
		return low + (1 - low) * shape(anim.kind, (t / anim.period) % 1, anim)
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

local function axisFor(model: Model, spin: ItemFxConfig.Spin, pivot: BasePart): Vector3
	if spin.axisParts and #spin.axisParts == 2 then
		local from = ItemFx.firstPart(model, spin.axisParts[1])
		local to = ItemFx.firstPart(model, spin.axisParts[2])
		if from and to and (to.Position - from.Position).Magnitude > 1e-3 then
			return pivot.CFrame:VectorToObjectSpace(to.Position - from.Position).Unit
		end
	end
	if spin.axisVector and spin.axisVector.Magnitude > 1e-6 then
		return spin.axisVector.Unit
	end
	return AXES[spin.axis or "Y"] or Vector3.yAxis
end

--- Returns the groups and the part every pivot is held relative to (one no group
--- moves), or nothing for a model that must not spin.
local function buildSpins(model: Model, def: Def, now: number, rng: Random): ({ SpinGroup }, BasePart?)
	local groups: { SpinGroup } = {}
	if def.spins == nil then
		return groups, nil
	end
	local claimed: { [BasePart]: boolean } = {}

	for _, spin in def.spins do
		local pivot = ItemFx.firstPart(model, spin.pivot)
		if pivot == nil or not pivot.Anchored then
			-- Held (welded, unanchored) or missing its pivot: no spins at all, rather
			-- than half a gimbal turning.
			return {}, nil
		end

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

		local group: SpinGroup = {
			spin = spin,
			pivot = pivot,
			pivotOffset = CFrame.identity,
			parts = {},
			rel = {},
			axis = axisFor(model, spin, pivot),
			angle = 0,
			parent = spin.parent,
			twitchAt = now + (spin.period or 3) * rng:NextNumber(0.3, 1.2),
			twitchUntil = 0,
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

	-- THE REFERENCE: a part nothing turns, preferring the model's primary. Pivots
	-- are re-derived from it every frame, never read off the pivot itself, which
	-- may be turning in its own group.
	local ref: BasePart? = nil
	if model.PrimaryPart and not claimed[model.PrimaryPart] then
		ref = model.PrimaryPart
	else
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") and not claimed[descendant] then
				ref = descendant
				break
			end
		end
	end
	if ref == nil then
		return {}, nil
	end
	for _, group in groups do
		group.pivotOffset = ref.CFrame:ToObjectSpace(group.pivot.CFrame)
	end
	return groups, ref
end

--- This group's own rotation angle right now.
local function spinAngle(group: SpinGroup, t: number, now: number, dt: number, rng: Random): number
	local spin = group.spin
	local mode = spin.mode or "spin"
	if mode == "swing" then
		local period = spin.period or 2
		return math.rad(spin.deg or 10) * math.sin((t / period + (spin.phase or 0)) * TAU)
	elseif mode == "twitch" then
		if now >= group.twitchAt then
			group.twitchUntil = now + (spin.duration or 0.12)
			group.twitchAt = now + (spin.period or 3) * rng:NextNumber(0.6, 1.4)
		end
		return if now < group.twitchUntil then math.rad(spin.deg or 6) else 0
	end
	group.angle = (group.angle + (spin.rpm or 0) * TAU / 60 * dt) % TAU
	if mode == "tick" then
		local notch = TAU / math.max(spin.steps or 60, 1)
		return math.floor(group.angle / notch) * notch
	end
	return group.angle
end

local function stepSpins(groups: { SpinGroup }, ref: BasePart, t: number, now: number, dt: number, rng: Random)
	-- Parents come before children in Config (Spec checks it), so each group's
	-- chain is ready by the time a child asks for it.
	local chains: { CFrame } = {}
	local refFrame = ref.CFrame
	for index, group in groups do
		local own = CFrame.fromAxisAngle(group.axis, spinAngle(group, t, now, dt, rng))
		local parentChain = if group.parent then chains[group.parent] else nil
		local chain = if parentChain then parentChain * own else own
		chains[index] = chain

		local base = refFrame * group.pivotOffset * chain
		for i, part in group.parts do
			part.CFrame = base * group.rel[i]
		end
	end
end

-- ── Glint ────────────────────────────────────────────────────────────────

--- How a Texture sits on each face, in the part's own space: the outward normal,
--- the texture's U (rightward as you face it) and V (downward). Measured in Studio
--- (2026-09-21): a side face's texture is upright; the Top face's "up" points to
--- +Z. On a plain Part the texture starts from the corner at normal - u - v (in
--- half-sizes); on a MeshPart, from the middle of the face. The underside is left
--- out: nobody sees a glint from below.
type FaceFrame = { face: Enum.NormalId, normal: Vector3, u: Vector3, v: Vector3 }

local FACE_FRAMES: { FaceFrame } = {
	{ face = Enum.NormalId.Front, normal = -Vector3.zAxis, u = -Vector3.xAxis, v = -Vector3.yAxis },
	{ face = Enum.NormalId.Back, normal = Vector3.zAxis, u = Vector3.xAxis, v = -Vector3.yAxis },
	{ face = Enum.NormalId.Right, normal = Vector3.xAxis, u = -Vector3.zAxis, v = -Vector3.yAxis },
	{ face = Enum.NormalId.Left, normal = -Vector3.xAxis, u = Vector3.zAxis, v = -Vector3.yAxis },
	{ face = Enum.NormalId.Top, normal = Vector3.yAxis, u = -Vector3.xAxis, v = -Vector3.zAxis },
}

--- The face whose normal lies closest to `direction` (in the same space).
local function faceToward(direction: Vector3): FaceFrame
	local best, bestDot = FACE_FRAMES[1], -math.huge
	for _, frame in FACE_FRAMES do
		local dot = frame.normal:Dot(direction)
		if dot > bestDot then
			best, bestDot = frame, dot
		end
	end
	return best
end

--- How far a part reaches along `axis` (in the reference part's space) either side
--- of its centre, given where it sits relative to the reference.
local function halfReach(rel: CFrame, size: Vector3, axis: Vector3): number
	return (
		math.abs(rel.XVector:Dot(axis)) * size.X
		+ math.abs(rel.YVector:Dot(axis)) * size.Y
		+ math.abs(rel.ZVector:Dot(axis)) * size.Z
	) / 2
end

--- Scatter the star spots over the glint's surfaces: pick a target part, aim just
--- off its centre from a random direction (never from below), keep the hit if it
--- isn't crowding another star.
local function placeStars(model: Model, def: Glint, ref: BasePart, scale: number, rng: Random): { Star }
	local count = def.stars or 0
	local targets = ItemFx.partsNamed(model, def.starParts or def.parts)
	if count <= 0 or #targets == 0 then
		return {}
	end

	-- Item parts are CanQuery false so they never eat a detector or wash ray. Open
	-- them to these casts only, on this client only, then close them again.
	local reopened: { BasePart } = {}
	for _, part in targets do
		if not part.CanQuery then
			part.CanQuery = true
			table.insert(reopened, part)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = targets
	local _, size = model:GetBoundingBox()
	local reach = size.Magnitude
	local apart = size.Magnitude * 0.12
	local starSize = (def.starSize or 0.5) * scale
	local color = def.starColor or def.color

	local stars: { Star } = {}
	for _ = 1, count * 8 do
		if #stars >= count then
			break
		end
		local target = targets[rng:NextInteger(1, #targets)]
		local direction = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.35, 1), rng:NextNumber(-1, 1))
		if direction.Magnitude > 1e-3 then
			direction = direction.Unit
			local aim = target.CFrame
				* Vector3.new(
					rng:NextNumber(-0.25, 0.25) * target.Size.X,
					rng:NextNumber(-0.25, 0.25) * target.Size.Y,
					rng:NextNumber(-0.25, 0.25) * target.Size.Z
				)
			local hit = Workspace:Raycast(aim + direction * reach, -direction * reach * 2, params)
			if hit and hit.Instance:IsA("BasePart") then
				local crowded = false
				for _, star in stars do
					if (ref.CFrame * star.position - hit.Position).Magnitude < apart then
						crowded = true
						break
					end
				end
				if not crowded then
					local attachment = Instance.new("Attachment")
					attachment.Name = "ItemFxStar"
					attachment.Parent = hit.Instance
					attachment.WorldPosition = hit.Position + hit.Normal * 0.02 * scale
					local e = starEmitter(color, starSize)
					e.Parent = attachment
					table.insert(stars, {
						part = hit.Instance :: BasePart,
						emitter = e,
						position = ref.CFrame:PointToObjectSpace(hit.Position),
						normal = ref.CFrame:VectorToObjectSpace(hit.Normal),
						at = 0,
						done = true,
					})
				end
			end
		end
	end

	for _, part in reopened do
		part.CanQuery = false
	end
	return stars
end

local function buildGlint(model: Model, def: Glint, scale: number, now: number, rng: Random): GlintRun?
	local ref = ItemFx.firstPart(model, def.parts[1])
	local parts = ItemFx.partsNamed(model, def.parts)
	if ref == nil or #parts == 0 then
		return nil
	end
	local r, g, b = def.color.R * def.strength, def.color.G * def.strength, def.color.B * def.strength
	local layers: { GlintLayer } = {}
	for _, part in parts do
		for _, top in { false, true } do
			local texture = Instance.new("Texture")
			texture.Name = "ItemFxGlint"
			texture.Texture = GLINT_TEXTURE
			-- Above 1 the texture is brighter than the lit surface under it: light, not paint.
			texture.Color3 = Color3.new(r, g, b)
			texture.Transparency = 1
			texture.Parent = part
			table.insert(layers, {
				part = part,
				texture = texture,
				top = top,
				live = false,
				onU = true,
				sign = 1,
				origin = 0,
			})
		end
	end
	return {
		def = def,
		ref = ref,
		layers = layers,
		stars = placeStars(model, def, ref, scale, rng),
		nextAt = now + def.period * rng:NextNumber(0.3, 1),
		passAt = nil,
		lo = 0,
		hi = 1,
		tile = 1,
	}
end

local function hideGlint(glint: GlintRun)
	glint.passAt = nil
	for _, layer in glint.layers do
		layer.texture.Transparency = 1
	end
end

--- Set up one pass on the side the camera is looking at: a vertical streak moving
--- left to right as the camera sees it. Everything is worked out in the reference
--- part's space, so a held item can swing mid-pass.
local function startPass(glint: GlintRun, now: number, cameraPosition: Vector3)
	local refFrame = glint.ref.CFrame
	local toCamera = refFrame:PointToObjectSpace(cameraPosition)
	if toCamera.Magnitude < 1e-3 then
		return
	end
	local flat = Vector3.new(toCamera.X, 0, toCamera.Z)
	-- Straight overhead has no "side"; any will do.
	local side = faceToward(if flat.Magnitude > 1e-3 then flat.Unit else -Vector3.zAxis)
	local axis = side.u
	if (-toCamera):Cross(Vector3.yAxis):Dot(axis) < 0 then
		axis = -axis
	end

	local lo, hi = math.huge, -math.huge
	for _, layer in glint.layers do
		local part = layer.part
		local rel = refFrame:ToObjectSpace(part.CFrame)
		-- The same outward direction on this part, whatever its own rotation.
		local want = if layer.top then Vector3.yAxis else side.normal
		local frame = faceToward(rel:VectorToObjectSpace(want))
		local u = rel:VectorToWorldSpace(frame.u)
		local v = rel:VectorToWorldSpace(frame.v)
		local alongU, alongV = u:Dot(axis), v:Dot(axis)
		layer.live = math.abs(alongU) > 0.9 or math.abs(alongV) > 0.9
		if layer.live then
			layer.onU = math.abs(alongU) > 0.9
			layer.sign = if (if layer.onU then alongU else alongV) > 0 then 1 else -1
			-- A MeshPart's texture starts from the middle of the face; a plain
			-- Part's from its corner. Both measured in Studio (2026-09-21).
			local start = if part:IsA("MeshPart") then frame.normal else frame.normal - frame.u - frame.v
			layer.origin = rel:PointToWorldSpace(start * part.Size / 2):Dot(axis)
			layer.texture.Face = frame.face
		end
		layer.texture.Transparency = 1
		if not layer.top then
			local centre = rel.Position:Dot(axis)
			local reach = halfReach(rel, part.Size, axis)
			lo = math.min(lo, centre - reach)
			hi = math.max(hi, centre + reach)
		end
	end
	if hi <= lo then
		return
	end

	local tile = (hi - lo) * GLINT_TILE_SLACK
	for _, layer in glint.layers do
		local texture = layer.texture
		local image = if layer.onU then GLINT_TEXTURE else GLINT_TEXTURE_V
		if texture.Texture ~= image then
			texture.Texture = image
		end
		texture.StudsPerTileU = if layer.onU then tile else GLINT_LONG
		texture.StudsPerTileV = tile
		texture.OffsetStudsU = 0
		texture.OffsetStudsV = 0
	end
	local towardCamera = toCamera.Unit
	for _, star in glint.stars do
		star.at = star.position:Dot(axis)
		-- Spots turned away get no turn this pass rather than a flare at the rim.
		star.done = star.normal:Dot(towardCamera) < STAR_FACING
	end
	glint.lo, glint.hi, glint.tile = lo, hi, tile
	glint.passAt = now
end

local function stepGlint(glint: GlintRun, now: number, cameraPosition: Vector3, rng: Random)
	local passAt = glint.passAt
	if passAt == nil then
		if now >= glint.nextAt then
			startPass(glint, now, cameraPosition)
			glint.nextAt = now + glint.def.period * rng:NextNumber(0.75, 1.25)
			passAt = glint.passAt
		end
		if passAt == nil then
			return
		end
	end

	local progress = (now - passAt) / glint.def.sweep
	if progress >= 1 then
		hideGlint(glint)
		return
	end
	local margin = glint.tile * GLINT_MARGIN
	local band = glint.lo - margin + (glint.hi - glint.lo + 2 * margin) * progress
	local transparency = 1 - smoothstep(math.min(progress, 1 - progress) / GLINT_FADE)
	for _, layer in glint.layers do
		if layer.live then
			-- The stripe sits where the texture coordinate plus its offset wraps to
			-- zero. Along the sweep that coordinate is sign * (band - origin).
			local offset = (layer.sign * (layer.origin - band)) % glint.tile
			if layer.onU then
				layer.texture.OffsetStudsU = offset
			else
				layer.texture.OffsetStudsV = offset
			end
			layer.texture.Transparency = transparency
		end
	end
	for _, star in glint.stars do
		if not star.done and band >= star.at then
			star.done = true
			if rng:NextNumber() < STAR_CHANCE then
				star.emitter:Emit(1)
			end
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

	local box = model:GetBoundingBox()
	for _, particles in def.particles or {} do
		local part = ItemFx.firstPart(model, particles.part)
		local build = PRESETS[particles.preset]
		if part and build then
			local e = build(particles.color, particles.rate, entry.scale)
			local host: Instance = part
			if particles.outward then
				-- A part flush on the shell has half its box inside it, and anything
				-- born there rises into the shell and is never seen. Emit from a point
				-- just off the surface instead: straight out from the model's axis.
				local offset = box:PointToObjectSpace(part.Position) * Vector3.new(1, 0, 1)
				local out = if offset.Magnitude > 1e-3 then box:VectorToWorldSpace(offset.Unit) else box.UpVector
				local attachment = Instance.new("Attachment")
				attachment.Name = "ItemFxEmitPoint"
				attachment.Parent = part
				attachment.WorldPosition = part.Position + out * part.Size.Magnitude * particles.outward
				host = attachment
			end
			if particles.burstEvery then
				-- On a timer instead of a stream: idle, then a puff all at once.
				e.Rate = 0
				table.insert(entry.bursts, {
					emitter = e,
					every = particles.burstEvery,
					count = particles.burstCount or 8,
					nextAt = now + particles.burstEvery * entry.rng:NextNumber(0.3, 1),
				})
			end
			e.Parent = host
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

	entry.spins, entry.spinRef = buildSpins(model, def, now, entry.rng)

	if def.glint then
		entry.glint = buildGlint(model, def.glint, entry.scale, now, entry.rng)
	end

	if def.seam then
		local part = ItemFx.firstPart(model, def.seam.part)
		if part then
			-- A band hugging the part's mid-height, a hair proud of the surface so it
			-- reads as a seam of light rather than a ring floating off it. Upright
			-- parts only: the band's axis is the part's local Y.
			local radius = math.min(part.Size.X, part.Size.Z) / 2
			local band = Instance.new("CylinderHandleAdornment")
			band.Name = "ItemFxSeam"
			band.Adornee = part
			band.CFrame = CFrame.Angles(math.rad(90), 0, 0)
			band.Color3 = def.seam.color
			band.Radius = radius * 1.015
			band.InnerRadius = radius * 0.97
			band.Height = part.Size.Y * def.seam.thickness
			band.Transparency = 0.2
			band.AlwaysOnTop = false
			band.ZIndex = 0
			band.Parent = part
			entry.seam = band
		end
	end

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
		bursts = {},
		anims = {},
		spins = {},
		spinRef = nil,
		glint = nil,
		seam = nil,
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
		if not awake and entry.glint then
			hideGlint(entry.glint)
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

	local ref = entry.spinRef
	if ref and #entry.spins > 0 then
		stepSpins(entry.spins, ref, t, now, dt, entry.rng)
	end

	local glint = entry.glint
	if glint then
		stepGlint(glint, now, cameraPosition, entry.rng)
	end

	for _, burst in entry.bursts do
		if now >= burst.nextAt then
			burst.nextAt = now + burst.every * entry.rng:NextNumber(0.8, 1.2)
			burst.emitter:Emit(burst.count)
		end
	end

	local seam = entry.seam
	local seamDef = entry.def.seam
	if seam and seamDef then
		local breath = 0.5 - 0.5 * math.cos(t / seamDef.period * TAU)
		seam.Transparency = 0.55 - 0.5 * breath
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
