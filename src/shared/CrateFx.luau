--!strict
--[[
	CrateFx.luau — subtle ambient effects on the supply crates (Config/Crates).

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

local CollectionService = game:GetService("CollectionService")

local ItemFx = require(script.Parent.ItemFx)

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

type Parts = { core: BasePart, top: BasePart, peak: Attachment, extents: Vector3 }

--- Every crate: faint sparkles in the crate's own colour drifting up round it, a
--- little denser the better the crate, so the tier reads at a glance.
local AURA_RATE = { 0.8, 1.4, 2.4, 3, 3.8, 4.6, 5.4 }

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
	-- Scrap: no effects on purpose -- a battered junk box, it just sits there.

	-- Field: a red light blinking on the antenna tip, and the odd glint off the
	-- steel.
	nuke2 = function(p)
		blinker(p.peak, "FF3B30", 0.3, 0.8)
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

	-- Void: a soft halo breathing round the dome, purple motes lifting off it, and
	-- the whole box lit from inside.
	nuke3 = function(p)
		light(p.core, "B26BFF", math.max(p.extents.X, p.extents.Z) * 2, 0.8)
		emitter(p.peak, {
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

	-- Nitro: fuel bubbling up behind the glass, a heat-haze of orange fume off the
	-- tank, and the odd spark jumping off the valve.
	liquid1 = function(p)
		emitter(p.core, {
			name = "Bubbles",
			texture = SPARKLE,
			color = colour("FFB15C", "FFE2B0"),
			size = seq(0.06, 0.12, 0),
			transparency = seq(0.1, 0.5),
			rate = 2.5,
			lifetime = NumberRange.new(0.7, 1.1),
			speed = NumberRange.new(0.5, 0.9),
			lightEmission = 0.8,
			locked = true,
		})
		emitter(p.top, {
			name = "Fume",
			texture = SMOKE,
			color = colour("FF8A3D", "FFD2A8"),
			size = seq(0.4, 1.2),
			transparency = seq(0.82, 1),
			rate = 0.9,
			lifetime = NumberRange.new(2, 3),
			speed = NumberRange.new(0.25, 0.5),
			spread = 20,
			rotSpeed = NumberRange.new(-15, 15),
		})
		emitter(p.peak, {
			name = "Spark",
			texture = SPARKLE,
			color = colour("FFF1C2", "FF6A1F"),
			size = seq(0.18, 0),
			transparency = seq(0),
			rate = 0.5,
			lifetime = NumberRange.new(0.25, 0.4),
			speed = NumberRange.new(1.5, 3),
			spread = 60,
			acceleration = Vector3.new(0, -10, 0),
			lightEmission = 1,
		})
		light(p.core, "FF6A1F", math.max(p.extents.X, p.extents.Z) * 1.4, 0.5)
	end,

	-- Isotope: vapour curling off the canister on the lid, blue motes rising
	-- through the tubes, and a cold blue glow.
	-- Potion: violet bubbles popping off the lid and a soft purple glow.
	potion1 = function(p)
		emitter(p.top, {
			name = "Bubbles",
			texture = SPARKLE,
			color = colour("B455FF", "F3D9FF"),
			size = seq(0.08, 0.16, 0),
			transparency = seq(0.1, 0.5),
			rate = 3,
			lifetime = NumberRange.new(0.9, 1.5),
			speed = NumberRange.new(0.6, 1.1),
			spread = 25,
			lightEmission = 1,
		})
		light(p.core, "B455FF", math.max(p.extents.X, p.extents.Z) * 1.5, 0.6)
	end,

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
		emitter(p.core, {
			name = "Motes",
			texture = SPARKLE,
			color = colour("3D6BFF", "BFD4FF"),
			size = seq(0.07, 0.1, 0),
			transparency = seq(0.1, 0.6),
			rate = 2.5,
			lifetime = NumberRange.new(0.8, 1.3),
			speed = NumberRange.new(0.4, 0.8),
			lightEmission = 1,
			locked = true,
		})
		light(p.core, "3D6BFF", math.max(p.extents.X, p.extents.Z) * 1.5, 0.5)
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

	-- Cobalt: blue glow breathing out of the vents, a blinking edge light, and cold
	-- blue motes lifting off the launch deck.
	nuke4 = function(p)
		light(p.core, "2F6BFF", math.max(p.extents.X, p.extents.Z) * 2, 0.8)
		blinker(p.peak, "6FA0FF", 0.32, 0.9)
		emitter(p.top, {
			name = "Motes",
			texture = SPARKLE,
			color = colour("2F6BFF", "D6E4FF"),
			size = seq(0.14, 0.08, 0),
			transparency = seq(0.1, 1),
			rate = 3,
			lifetime = NumberRange.new(1.4, 2.4),
			speed = NumberRange.new(0.4, 0.9),
			spread = 25,
			lightEmission = 1,
			rotSpeed = NumberRange.new(-60, 60),
		})
	end,

	-- Fusion: a hot gold core lighting the box from inside, a slow halo pulsing over
	-- the plinth, and embers rising off the radiators.
	nuke5 = function(p)
		light(p.core, "FFB020", math.max(p.extents.X, p.extents.Z) * 2.2, 1)
		emitter(p.peak, {
			name = "Halo",
			texture = SPARKLE,
			color = colour("FFE08A"),
			size = seq(0.6, 1.3),
			transparency = seq(0.5, 1),
			rate = 1.1,
			lifetime = NumberRange.new(1.2),
			speed = NumberRange.new(0),
			lightEmission = 1,
			locked = true,
		})
		emitter(p.top, {
			name = "Embers",
			texture = SPARKLE,
			color = colour("FFB020", "FFF4D0"),
			size = seq(0.15, 0.08, 0),
			transparency = seq(0.05, 1),
			rate = 4,
			lifetime = NumberRange.new(1.4, 2.4),
			speed = NumberRange.new(0.5, 1),
			spread = 25,
			lightEmission = 1,
			rotSpeed = NumberRange.new(-60, 60),
		})
	end,

	-- Ground Zero (Mythic jackpot): a red-orange glow from the magma cracks, embers
	-- rising off the case and a slow plume of dark smoke off the mushroom cloud.
	nuke6 = function(p)
		light(p.core, "FF5A2E", math.max(p.extents.X, p.extents.Z) * 2.4, 1.1)
		emitter(p.top, {
			name = "Embers",
			texture = SPARKLE,
			color = colour("FF5A2E", "FFD27A"),
			size = seq(0.16, 0.08, 0),
			transparency = seq(0.05, 1),
			rate = 5,
			lifetime = NumberRange.new(1.4, 2.4),
			speed = NumberRange.new(0.6, 1.1),
			spread = 30,
			lightEmission = 1,
			rotSpeed = NumberRange.new(-60, 60),
		})
		emitter(p.peak, {
			name = "Plume",
			texture = SMOKE,
			color = colour("5A4038", "2A2220"),
			size = seq(0.4, 1.2),
			transparency = seq(0.75, 1),
			rate = 1.2,
			lifetime = NumberRange.new(2, 3),
			speed = NumberRange.new(0.3, 0.5),
			spread = 15,
			rotSpeed = NumberRange.new(-20, 20),
		})
	end,

	-- Rift (Anomaly jackpot): white-violet stars spilling out of the portal, a halo
	-- pulsing at the top, and a cold white light.
	nuke7 = function(p)
		light(p.core, "D8C8FF", math.max(p.extents.X, p.extents.Z) * 2.4, 1.1)
		emitter(p.core, {
			name = "Stars",
			texture = SPARKLE,
			color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHex("FFFFFF")),
				ColorSequenceKeypoint.new(0.5, Color3.fromHex("B98CFF")),
				ColorSequenceKeypoint.new(1, Color3.fromHex("6FE0FF")),
			}),
			size = seq(0, 0.18, 0),
			transparency = seq(0.05),
			rate = 4,
			lifetime = NumberRange.new(0.8, 1.4),
			speed = NumberRange.new(0.3, 0.7),
			spread = 180,
			lightEmission = 1,
		})
		emitter(p.peak, {
			name = "Halo",
			texture = SPARKLE,
			color = colour("FFFFFF", "D8C8FF"),
			size = seq(0.6, 1.4),
			transparency = seq(0.45, 1),
			rate = 1.2,
			lifetime = NumberRange.new(1.2),
			speed = NumberRange.new(0),
			lightEmission = 1,
			locked = true,
		})
	end,

	-- Quicksilver: bright beads glinting round the orb, a faint silver sheen in the
	-- air, and a cool white light.
	liquid4 = function(p)
		emitter(p.core, {
			name = "Beads",
			texture = SPARKLE,
			color = colour("FFFFFF", "C9D3DE"),
			size = seq(0, 0.16, 0),
			transparency = seq(0.05),
			rate = 2.5,
			lifetime = NumberRange.new(0.5, 0.8),
			speed = NumberRange.new(0),
			lightEmission = 1,
			locked = true,
		})
		emitter(p.top, {
			name = "Sheen",
			texture = SMOKE,
			color = colour("E8EEF4"),
			size = seq(0.35, 1),
			transparency = seq(0.8, 1),
			rate = 1,
			lifetime = NumberRange.new(1.8, 2.6),
			speed = NumberRange.new(0.15, 0.3),
			spread = 30,
			rotSpeed = NumberRange.new(-20, 20),
		})
		light(p.core, "DDE6F0", math.max(p.extents.X, p.extents.Z) * 1.5, 0.55)
	end,

	-- Plasma: arcs snapping off the coil's top, pink motes swirling up, and a
	-- magenta glow.
	liquid5 = function(p)
		emitter(p.peak, {
			name = "Arc",
			texture = SPARKLE,
			color = colour("FFFFFF", "FF4FD8"),
			size = seq(0.35, 0),
			transparency = seq(0),
			rate = 1.6,
			lifetime = NumberRange.new(0.12, 0.2),
			speed = NumberRange.new(2, 4),
			spread = 90,
			lightEmission = 1,
		})
		emitter(p.top, {
			name = "Motes",
			texture = SPARKLE,
			color = colour("FF4FD8", "FFD6F6"),
			size = seq(0.12, 0.07, 0),
			transparency = seq(0.1, 1),
			rate = 3,
			lifetime = NumberRange.new(1.2, 2),
			speed = NumberRange.new(0.4, 0.8),
			spread = 30,
			lightEmission = 1,
			rotSpeed = NumberRange.new(-90, 90),
		})
		light(p.core, "FF4FD8", math.max(p.extents.X, p.extents.Z) * 1.8, 0.7)
	end,
}

--- The imported crates' colours are baked into their meshes and render dark, and
--- BasePart.Color doesn't tint them. A soft Highlight in the crate's own colour lifts
--- every face without washing the hue out.
local BRIGHTEN_FILL = 0.82

local function brighten(model: Model, hex: string)
	local h = Instance.new("Highlight")
	h.Name = "Brighten"
	h.FillColor = Color3.fromHex(hex):Lerp(Color3.new(1, 1, 1), 0.55)
	h.FillTransparency = BRIGHTEN_FILL
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
end

--- Moving parts (Config/ItemFx CRATE_DEFS), run by the client's ItemFxController.
local function tagMotion(model: Model, crateId: string)
	local fxId = `crate_{crateId}`
	if ItemFx.get(fxId) == nil then
		return
	end
	model:SetAttribute(ItemFx.ATTRIBUTE, fxId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, ItemFx.TAG)
end

--- Fit this crate's effects to `model` (either kind of crate model). Call after the
--- model is built and before it is placed or scaled: Model:ScaleTo carries particle
--- sizes and speeds with it.
function CrateFx.apply(model: Model, crateId: string, hex: string, variant: number)
	brighten(model, hex)
	tagMotion(model, crateId)
	local build = EFFECTS[crateId]
	if build == nil then -- Scrap: bare on purpose, no aura either
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
	-- The model's highest point (an antenna tip, a dome), wherever the drawing put it.
	local tip = box.Position + Vector3.new(0, extents.Y / 2, 0)
	local best = -math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= core and part ~= top then
			local topY = part.Position.Y + part.Size.Y / 2
			if topY > best then
				best = topY
				tip = Vector3.new(part.Position.X, topY, part.Position.Z)
			end
		end
	end
	local peak = Instance.new("Attachment")
	peak.Name = "Peak"
	peak.WorldPosition = tip
	peak.Parent = core
	peak.WorldPosition = tip
	aura(core, hex, variant)
	build({ core = core, top = top, peak = peak, extents = extents })
end

--- Take every glow and particle off a crate model: the FxCore/FxTop carriers `apply`
--- added and any light a built crate carries on its own parts. For a crate still under
--- its crust (Shared/ItemCrust), where a tier-coloured sparkle through the rock would
--- say "crate" before the wash has. Call before the crust goes on -- the crust's own
--- light is added after, and this would take it too.
function CrateFx.strip(model: Model)
	CollectionService:RemoveTag(model, ItemFx.TAG)
	model:SetAttribute(ItemFx.ATTRIBUTE, nil)
	for _, name in { "FxCore", "FxTop" } do
		local carrierPart = model:FindFirstChild(name)
		if carrierPart then
			carrierPart:Destroy()
		end
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") or descendant:IsA("ParticleEmitter") or descendant:IsA("Highlight") then
			descendant:Destroy()
		end
	end
end

return CrateFx
