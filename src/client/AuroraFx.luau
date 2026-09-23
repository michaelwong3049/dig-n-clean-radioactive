--!strict
--[[
	AuroraFx.luau — the lights in the sky while the Violet Aurora is up (Config/
	LuckBoost). AtmosphereController turns the sky violet; this hangs the aurora in it
	and lets sparkles drift down out of it. LuckBoostController switches it on and off.

	CLIENT-ONLY, UNDER THE CAMERA. Everything here is parented to CurrentCamera, which
	never replicates: an aurora is weather each player looks at, not world geometry, and
	it follows each player's own camera.

	IT FOLLOWS THE CAMERA ON PURPOSE. A real aurora is a hundred kilometres up and has
	no parallax at all when you walk under it; ribbons pinned to the world would slide
	overhead like low cloud and give the scale away. So the rig rides the camera, and
	only drifts on its own slow clock.

	A RING, NOT A CANOPY. The first draft laid the ribbons straight overhead, and from
	the game's own third-person camera -- which looks at the horizon, not the zenith --
	they were simply not on screen. They now stand in a loose ring a few hundred studs
	out, 20-35 degrees above the horizon, so whichever way a player faces there is an
	arc in the top of their view. Further out than ~450 the Atmosphere's haze eats them.

	NO TEXTURE ASSETS. Each ribbon is two untextured additive Beams of the same curve --
	a narrow bright core and a wide faint halo -- which is enough to soften the edge of
	a flat band into a glow without shipping an image somebody could get moderated out
	from under the game (Config/Sky's header, on marketplace skyboxes). The sparkles are
	the engine's own `sparkles_main` particle texture, already used by the game.

	FADES, NEVER SNAPS. `setActive` eases a master level over FADE seconds, and every
	ribbon's Brightness and the sparkle rate ride that level; at zero the whole rig is
	parked (not destroyed) so the next event is a fade-in, not a rebuild.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AuroraFx = {}

local HEIGHT = 190 -- the rig's centre, studs above the camera
local FADE = 4 -- seconds for the whole display to come up or die away
local SPARKLE_HEIGHT = 70
local SPARKLE_RATE = 26

-- Each ribbon: which way round the ring it stands (`bearing`, degrees), how far out
-- (`radius`) and up (`lift`, above the rig) it is, how long it runs along the ring,
-- its core width, colours along its length, and its own wave.
type RibbonDef = {
	bearing: number,
	radius: number,
	lift: number,
	length: number,
	width: number,
	colors: { Color3 },
	speed: number,
	amp: number,
	brightness: number,
}

local VIOLET = Color3.fromHex("9B5CFF")
local ORCHID = Color3.fromHex("D46BFF")
local ROSE = Color3.fromHex("FF7AD9")
local ICE = Color3.fromHex("8FD8FF")
local LILAC = Color3.fromHex("C9A8FF")

-- Tuned live in Studio against the Sky.AURORA night: at these distances a core much
-- under ~80 wide is a hairline, and much brighter blows out into a flat sheet.
local RIBBONS: { RibbonDef } = {
	{ bearing = 20, radius = 380, lift = 150, length = 640, width = 90, colors = { ICE, VIOLET, ORCHID }, speed = 0.21, amp = 140, brightness = 2.0 },
	{ bearing = 95, radius = 420, lift = 200, length = 700, width = 100, colors = { VIOLET, ORCHID, ROSE }, speed = 0.17, amp = 170, brightness = 2.3 },
	{ bearing = 165, radius = 360, lift = 140, length = 580, width = 80, colors = { LILAC, VIOLET, ICE }, speed = 0.26, amp = 120, brightness = 1.8 },
	{ bearing = 235, radius = 410, lift = 185, length = 660, width = 95, colors = { ROSE, ORCHID, VIOLET }, speed = 0.19, amp = 160, brightness = 2.1 },
	{ bearing = 305, radius = 390, lift = 165, length = 620, width = 85, colors = { ICE, LILAC, ORCHID }, speed = 0.23, amp = 150, brightness = 1.9 },
}

-- The halo is the same curve, this much wider and this much fainter.
local HALO_WIDTH = 2.5
local HALO_BRIGHTNESS = 0.35
local CORE_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.18, 0.5),
	NumberSequenceKeypoint.new(0.5, 0.3),
	NumberSequenceKeypoint.new(0.82, 0.5),
	NumberSequenceKeypoint.new(1, 1),
})
local HALO_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.8),
	NumberSequenceKeypoint.new(0.5, 0.7),
	NumberSequenceKeypoint.new(0.8, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})

type Ribbon = {
	def: RibbonDef,
	core: Beam,
	halo: Beam,
	phase: number,
}

local rig: Model? = nil
local root: BasePart? = nil
local sparkles: ParticleEmitter? = nil
local sparkleSource: BasePart? = nil
local ribbons: { Ribbon } = {}

local target = 0 -- 0 or 1: what setActive asked for
local level = 0 -- eased 0..1
local connection: RBXScriptConnection? = nil
local clock = 0

local function ghostPart(name: string, size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function colorSequence(colors: { Color3 }): ColorSequence
	local keys = {}
	for i, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keys)
end

local function beam(a0: Attachment, a1: Attachment, width: number, colors: ColorSequence, transparency: NumberSequence): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.Segments = 24
	b.Width0 = width
	b.Width1 = width
	b.Color = colors
	b.Transparency = transparency
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Brightness = 0
	b.Parent = a0.Parent
	return b
end

local function build()
	local camera = Workspace.CurrentCamera
	local model = Instance.new("Model")
	model.Name = "VioletAurora"

	local anchor = ghostPart("AuroraRoot", Vector3.one, model)
	for index, def in RIBBONS do
		-- The ribbon runs along the ring (tangent to it) at its bearing. Both ends'
		-- attachments turn their Axis to point out along the radius, so CurveSize bows
		-- the band toward and away from the player -- a curtain folding -- rather than
		-- up and down the sky.
		local theta = math.rad(def.bearing)
		local radial = Vector3.new(math.cos(theta), 0, math.sin(theta))
		local tangent = Vector3.new(-radial.Z, 0, radial.X)
		local centre = radial * def.radius + Vector3.new(0, def.lift, 0)
		local function endAt(side: number): CFrame
			local at = centre + tangent * (side * def.length / 2)
			return CFrame.lookAt(at, at + radial) * CFrame.Angles(0, math.rad(90), 0)
		end
		local a0 = Instance.new("Attachment")
		a0.Name = `Ribbon{index}A`
		a0.CFrame = endAt(-1)
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Name = `Ribbon{index}B`
		a1.CFrame = endAt(1)
		a1.Parent = anchor

		local colors = colorSequence(def.colors)
		table.insert(ribbons, {
			def = def,
			core = beam(a0, a1, def.width, colors, CORE_TRANSPARENCY),
			halo = beam(a0, a1, def.width * HALO_WIDTH, colors, HALO_TRANSPARENCY),
			phase = index * 1.7,
		})
	end

	-- A wide flat sheet the sparkles fall out of.
	local source = ghostPart("AuroraSparkles", Vector3.new(260, 1, 260), model)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, LILAC),
		ColorSequenceKeypoint.new(0.5, ORCHID),
		ColorSequenceKeypoint.new(1, ROSE),
	})
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, 0.7),
		NumberSequenceKeypoint.new(0.85, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.15),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(10, 16)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(20, 20)
	emitter.Acceleration = Vector3.new(0, -0.4, 0)
	emitter.RotSpeed = NumberRange.new(-60, 60)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Drag = 0.2
	emitter.Rate = 0
	emitter.Parent = source

	model.Parent = camera
	rig = model
	root = anchor
	sparkles = emitter
	sparkleSource = source
end

local function park()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if rig then
		rig.Parent = nil
	end
end

local function step(dt: number)
	level = if target > level then math.min(target, level + dt / FADE) else math.max(target, level - dt / FADE)
	if level <= 0 and target <= 0 then
		park()
		return
	end
	clock += dt

	local camera = Workspace.CurrentCamera
	if camera == nil or root == nil then
		return
	end
	if rig and rig.Parent ~= camera then
		rig.Parent = camera
	end

	local eased = level * level * (3 - 2 * level)
	local at = camera.CFrame.Position
	root.CFrame = CFrame.new(at.X, at.Y + HEIGHT, at.Z) * CFrame.Angles(0, clock * 0.012, 0)
	if sparkleSource then
		sparkleSource.CFrame = CFrame.new(at.X, at.Y + SPARKLE_HEIGHT, at.Z)
	end
	if sparkles then
		sparkles.Rate = SPARKLE_RATE * eased
	end

	for _, ribbon in ribbons do
		local def = ribbon.def
		local t = clock * def.speed + ribbon.phase
		-- Two slow waves out of step, so the band snakes rather than rocks.
		local curve0 = math.sin(t) * def.amp
		local curve1 = math.sin(t * 1.37 + 2.1) * def.amp
		-- The shimmer: brightness breathes on its own faster clock.
		local shimmer = 0.75 + 0.25 * math.sin(clock * (0.9 + def.speed) + ribbon.phase * 2)
		local glow = def.brightness * shimmer * eased
		ribbon.core.CurveSize0 = curve0
		ribbon.core.CurveSize1 = curve1
		ribbon.halo.CurveSize0 = curve0
		ribbon.halo.CurveSize1 = curve1
		ribbon.core.Brightness = glow
		ribbon.halo.Brightness = glow * HALO_BRIGHTNESS
	end
end

--- Bring the aurora up (true) or let it die away (false). Idempotent.
function AuroraFx.setActive(on: boolean)
	target = if on then 1 else 0
	if not on and level <= 0 then
		return
	end
	if rig == nil then
		build()
	end
	if connection == nil then
		connection = RunService.RenderStepped:Connect(step)
	end
end

--- The eased 0..1 level, for anything that wants to ride the same fade.
function AuroraFx.level(): number
	return level
end

return AuroraFx
