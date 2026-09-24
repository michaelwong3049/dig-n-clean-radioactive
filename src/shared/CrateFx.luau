--!strict
--[[
	CrateFx.luau — subtle ambient effects on the six supply crates (Config/Crates).

	FITTED TO THE MODEL, NOT TO ONE DRAWING. Every effect is placed from the crate's
	bounding box, not from named parts, so the same layer works on the studded crates
	in Shared/CrateModels AND on any model imported into
	ReplicatedStorage.Assets.CrateTemplates. Two invisible carrier parts are added:

	  FxCore — the crate's whole volume. Glows, motes and anything that should seem to
	           come from INSIDE the box emit from here.
	  FxTop  — a thin plate on the lid. Fumes, vapour and mist leave from here.

	Point effects (a blinking status light, a drip) hang off Attachments on FxCore at
	offsets measured in fractions of the box, so they land on the crate's surface
	whatever its size.

	SUBTLE ON PURPOSE. Low emission rates, small sizes and high transparency: a crate is
	loot in your hands, not a firework. Particles and lights only -- nothing here needs
	a script, so every context a crate appears in (the haul, your hands, the preview)
	gets the effect for free. ParticleEmitters don't render in a ViewportFrame, which is
	fine: the reveal popup has its own rays and burst.

	No Neon anywhere (the game's de-neon rule); glow is PointLight + LightEmission.
]]

local CrateFx = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function seq(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local points = {}
	for index, value in values do
		table.insert(points, NumberSequenceKeypoint.new((index - 1) / (#values - 1), value))
	end
	return NumberSequence.new(points)
end

local function colour(a: string, b: string?): ColorSequence
	return ColorSequence.new(Color3.fromHex(a), Color3.fromHex(b or a))
end

local function carrier(model: Model, name: string, size: Vector3, cf: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Parent = model
	return part
end

type EmitterSpec = {
	name: string,
	texture: string,
	color: ColorSequence,
	size: NumberSequence,
	transparency: NumberSequence,
	rate: number,
	lifetime: NumberRange,
	speed: NumberRange,
	spread: number?,
	direction: Enum.NormalId?,
	acceleration: Vector3?,
	lightEmission: number?,
	locked: boolean?,
	rotSpeed: NumberRange?,
	drag: number?,
}

local function emitter(parent: Instance, spec: EmitterSpec): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = spec.name
	e.Texture = spec.texture
	e.Color = spec.color
	e.Size = spec.size
	e.Transparency = spec.transparency
	e.Rate = spec.rate
	e.Lifetime = spec.lifetime
	e.Speed = spec.speed
	e.SpreadAngle = Vector2.new(spec.spread or 0, spec.spread or 0)
	e.EmissionDirection = spec.direction or Enum.NormalId.Top
	e.Acceleration = spec.acceleration or Vector3.zero
	e.LightEmission = spec.lightEmission or 0
	e.LightInfluence = if (spec.lightEmission or 0) > 0 then 0 else 1
	e.LockedToPart = spec.locked == true
	e.RotSpeed = spec.rotSpeed or NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.Drag = spec.drag or 0
	e.Parent = parent
	return e
end

local function light(parent: Instance, hex: string, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = Color3.fromHex(hex)
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

--- FxCore is this fraction of the crate's box, so glows and motes start inside it.
local CORE_FRACTION = 0.8

--- An attachment on FxCore at a point given in FRACTIONS of the whole box's
--- half-size (not FxCore's): (0, 1, -1) is the middle of the lid's front edge.
local function point(core: BasePart, name: string, fx: number, fy: number, fz: number): Attachment
	local half = core.Size / CORE_FRACTION / 2
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = Vector3.new(fx * half.X, fy * half.Y, fz * half.Z)
	a.Parent = core
	return a
end

--- A status light that blinks: a small glint that pops in and fades, on a steady beat.
local function blinker(at: Attachment, hex: string, size: number, rate: number)
	emitter(at, {
		name = "Blink",
		texture = SPARKLE,
		color = colour(hex),
		size = seq(size, size * 0.85),
		transparency = seq(0, 0.2, 1),
		rate = rate,
		lifetime = NumberRange.new(0.45),
		speed = NumberRange.new(0),
		lightEmission = 1,
		locked = true,
	})
end

type Parts = { core: BasePart, top: BasePart, extents: Vector3 }

--- Every crate: faint sparkles in the crate's own colour drifting up round it, a
--- little denser the better the crate, so the tier reads at a glance.
local AURA_RATE = { 0.8, 1.4, 2.4 }

local function aura(core: BasePart, hex: string, variant: number)
	emitter(core, {
		name = "Aura",
		texture = SPARKLE,
		color = colour(hex, "FFFFFF"),
		size = seq(0, 0.16, 0),
		transparency = seq(0.15),
		rate = AURA_RATE[variant] or AURA_RATE[1],
		lifetime = NumberRange.new(1.4, 2.2),
		speed = NumberRange.new(0.25, 0.5),
		spread = 12,
		lightEmission = 1,
		rotSpeed = NumberRange.new(-40, 40),
	})
end

local EFFECTS: { [string]: (Parts) -> () } = {
	-- Rusty: something inside is glowing through the gaps in the slats, and dust
	-- drifts off the rotten wood.
	nuke1 = function(p)
		light(p.core, "7CFC00", math.max(p.extents.X, p.extents.Z) * 1.8, 0.7)
		emitter(p.core, {
			name = "Dust",
			texture = SPARKLE,
			color = colour("E8C9A0", "A0693A"),
			size = seq(0.1, 0.07, 0),
			transparency = seq(0.2, 1),
			rate = 2,
			lifetime = NumberRange.new(2.5, 4),
			speed = NumberRange.new(0.1, 0.35),
			spread = 180,
			acceleration = Vector3.new(0, 0.05, 0),
			rotSpeed = NumberRange.new(-30, 30),
		})
	end,

	-- Military: a red status light on the lid that blinks, and the odd glint off
	-- the steel.
	nuke2 = function(p)
		blinker(point(p.core, "StatusLight", -0.55, 0.95, -1.02), "FF3B30", 0.35, 0.8)
		emitter(p.top, {
			name = "Glint",
			texture = SPARKLE,
			color = colour("FFFFFF"),
			size = seq(0, 0.22, 0),
			transparency = seq(0.2),
			rate = 0.35,
			lifetime = NumberRange.new(0.35),
			speed = NumberRange.new(0),
			lightEmission = 1,
			locked = true,
		})
	end,

	-- Reactor: a soft halo breathing round the core, purple motes lifting off the
	-- dome, and the whole box lit from inside.
	nuke3 = function(p)
		light(p.core, "B26BFF", math.max(p.extents.X, p.extents.Z) * 2, 0.8)
		local crown = point(p.core, "Core", 0, 1.05, 0)
		emitter(crown, {
			name = "Halo",
			texture = SPARKLE,
			color = colour("C9A2FF"),
			size = seq(0.5, 1.1),
			transparency = seq(0.55, 1),
			rate = 1,
			lifetime = NumberRange.new(1.2),
			speed = NumberRange.new(0),
			lightEmission = 1,
			locked = true,
		})
		emitter(p.top, {
			name = "Motes",
			texture = SPARKLE,
			color = colour("B26BFF", "F0E0FF"),
			size = seq(0.14, 0.08, 0),
			transparency = seq(0.1, 1),
			rate = 3,
			lifetime = NumberRange.new(1.5, 2.6),
			speed = NumberRange.new(0.4, 0.9),
			spread = 25,
			lightEmission = 1,
			rotSpeed = NumberRange.new(-60, 60),
		})
	end,

	-- Leaky: green drips running off the front, bubbles popping on the drums, and a
	-- thin chemical fume.
	liquid1 = function(p)
		local drip = point(p.core, "Drip", -0.35, 0.15, -1.02)
		emitter(drip, {
			name = "Drip",
			texture = SPARKLE,
			color = colour("7CFC00"),
			size = seq(0.13, 0.1),
			transparency = seq(0, 0.2),
			rate = 0.9,
			lifetime = NumberRange.new(0.55),
			speed = NumberRange.new(0.2),
			direction = Enum.NormalId.Bottom,
			acceleration = Vector3.new(0, -14, 0),
			lightEmission = 0.6,
		})
		emitter(p.top, {
			name = "Bubbles",
			texture = SPARKLE,
			color = colour("B6FF6A"),
			size = seq(0.06, 0.14, 0),
			transparency = seq(0.1, 0.6),
			rate = 2,
			lifetime = NumberRange.new(0.5, 0.9),
			speed = NumberRange.new(0.2, 0.5),
			spread = 20,
			lightEmission = 0.5,
		})
		light(p.core, "7CFC00", math.max(p.extents.X, p.extents.Z) * 1.4, 0.45)
		emitter(p.top, {
			name = "Fume",
			texture = SMOKE,
			color = colour("7CFC00"),
			size = seq(0.5, 1.4),
			transparency = seq(0.8, 1),
			rate = 0.8,
			lifetime = NumberRange.new(2.5, 3.5),
			speed = NumberRange.new(0.2, 0.45),
			spread = 20,
			rotSpeed = NumberRange.new(-15, 15),
		})
	end,

	-- Hazmat: cold vapour curling off the canister caps and an amber beacon blinking
	-- on the cage.
	liquid2 = function(p)
		emitter(p.top, {
			name = "Vapour",
			texture = SMOKE,
			color = colour("DDF6FF"),
			size = seq(0.3, 0.9),
			transparency = seq(0.72, 1),
			rate = 1.4,
			lifetime = NumberRange.new(1.8, 2.6),
			speed = NumberRange.new(0.15, 0.35),
			spread = 30,
			rotSpeed = NumberRange.new(-20, 20),
		})
		blinker(point(p.core, "Beacon", 0.9, 1.0, -0.9), "FFB020", 0.4, 0.6)
		light(p.core, "3DB8F5", math.max(p.extents.X, p.extents.Z) * 1.4, 0.35)
	end,

	-- Cryo: frost mist spilling over the edges and sinking, bubbles rising through the
	-- coolant, and ice catching the light.
	liquid3 = function(p)
		emitter(p.top, {
			name = "FrostMist",
			texture = SMOKE,
			color = colour("F0FCFF"),
			size = seq(0.45, 1.3),
			transparency = seq(0.7, 1),
			rate = 1.8,
			lifetime = NumberRange.new(2.2, 3),
			speed = NumberRange.new(0.15, 0.3),
			spread = 70,
			acceleration = Vector3.new(0, -0.7, 0),
			rotSpeed = NumberRange.new(-10, 10),
		})
		emitter(p.core, {
			name = "Bubbles",
			texture = SPARKLE,
			color = colour("FFFFFF", "8FF0FF"),
			size = seq(0.06, 0.1, 0),
			transparency = seq(0.1, 0.5),
			rate = 3,
			lifetime = NumberRange.new(0.8, 1.3),
			speed = NumberRange.new(0.5, 0.9),
			lightEmission = 1,
			locked = true,
		})
		emitter(p.top, {
			name = "IceGlint",
			texture = SPARKLE,
			color = colour("FFFFFF"),
			size = seq(0, 0.2, 0),
			transparency = seq(0.1),
			rate = 0.8,
			lifetime = NumberRange.new(0.4),
			speed = NumberRange.new(0),
			lightEmission = 1,
			locked = true,
		})
	end,
}

--- Fit this crate's effects to `model` (either kind of crate model). Call after the
--- model is built and before it is placed or scaled: Model:ScaleTo carries particle
--- sizes and speeds with it.
function CrateFx.apply(model: Model, crateId: string, hex: string, variant: number)
	local build = EFFECTS[crateId]
	if build == nil then
		return
	end
	local box, extents = model:GetBoundingBox()
	local core = carrier(model, "FxCore", extents * CORE_FRACTION, box)
	local top = carrier(
		model,
		"FxTop",
		Vector3.new(extents.X * 0.7, 0.1, extents.Z * 0.7),
		box * CFrame.new(0, extents.Y / 2 - 0.05, 0)
	)
	aura(core, hex, variant)
	build({ core = core, top = top, extents = extents })
end

return CrateFx
