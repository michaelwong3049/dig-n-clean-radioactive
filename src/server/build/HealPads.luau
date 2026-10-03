--!strict
--[[
	HealPads.luau — Base Camp's two heal pads.

	    require(game.ServerScriptService.Server.build.HealPads).rebuild()

	ONE BEHIND EACH ROW OF SHOPS, in the aisle between the pair (on request): south of
	the Outfitter (Aura) and the Hose Shop, north of the Magnet and Detector shops. Both
	sit on the plaza's centre line (x = 17.5, the Trader's x), just past the rows' back
	edges (the stall footprints reach |z| = 44.1, measured in Studio), so they mirror
	about the Trader the same way the four shops do (see build/Shops' header). Move the
	shops, move these.

	A PAD IS A SHOWER ANYONE CAN USE, PLUS HEALING. The glowing disc carries
	`Shower = true` (Kit.build tags it, ExposureService's shower cache finds it), and
	since it is on no plot it flushes everyone's rads, not just an owner's. `HealPad =
	true` is the extra: ExposureService heals Tuning.HEAL_PAD_HEAL_FRAC of max health a
	second while you stand in it. `Radius` is measured from the disc to your
	HumanoidRootPart (about 3 studs up), so 10 reaches roughly the glow's own 8.5-stud rim.

	NO LIGHTS: base camp already had too many (Shops' glowOutline note). Neon reads as lit.
]]

local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local HealPads = {}

HealPads.MODEL_NAME = "HealPads"

local BUILDER_SOURCE = "src/server/build/HealPads.luau"
local BUILDER_VERSION = 2

local PAD_X = 17.5
local PAD_Z = 55 -- either side: stall backs end at 44.1, the rim's edge at 55 - 9.5
local PADS = {
	{ name = "HealPadSouth", z = -PAD_Z }, -- behind the Outfitter (Aura) + Hose Shop
	{ name = "HealPadNorth", z = PAD_Z }, -- behind the Magnet + Detector shops
}

local RIM_COLOR = "2B3138"
local GLOW_COLOR = "39FF7A"
local CROSS_COLOR = "FFFFFF"
local HEART_COLOR = "FF3B4E"
local HEART_PX = 44
local RIM = 19 -- studs across the steel rim; the glow is 2 narrower
local REACH = 10 -- from the disc to a HumanoidRootPart ~3 up: about the glow's 8.5 rim

local function buildSparkles(part: BasePart)
	local e = Instance.new("ParticleEmitter")
	e.Name = "HealRise"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromHex(GLOW_COLOR))
	e.LightEmission = 0.6
	e.LightInfluence = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 12
	e.Lifetime = NumberRange.new(1.2, 2)
	e.Speed = NumberRange.new(2, 3.5)
	e.SpreadAngle = Vector2.new(8, 8)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Parent = part
end

local function buildPad(parent: Instance, name: string, z: number)
	local pad = Instance.new("Model")
	pad.Name = name
	local origin = CFrame.new(PAD_X, Hub.PLAZA.topY + Hub.PLAZA_LIFT, z)

	-- A dark steel rim a hair proud of the plaza, so the glow sits in a ring.
	Kit.build(pad, origin, {
		name = "Rim",
		pos = { 0, 0.2, 0 },
		size = { 0.4, RIM, RIM },
		color = RIM_COLOR,
		material = "Metal",
		shape = "Cylinder",
		rot = Kit.R.cylUp,
	})

	-- The glowing disc IS the station: Shower + HealPad + Radius live here.
	local glow = Kit.build(pad, origin, {
		name = "Glow",
		pos = { 0, 0.45, 0 },
		size = { 0.1, RIM - 2, RIM - 2 },
		color = GLOW_COLOR,
		material = "Neon",
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		transparency = 0.15,
		canCollide = false,
		attributes = { Shower = true, HealPad = true, Radius = REACH },
	})
	glow.CastShadow = false
	buildSparkles(glow)

	-- A white medical cross on the disc.
	for i, size in { { 9, 0.1, 2.7 }, { 2.7, 0.1, 9 } } do
		local bar = Kit.build(pad, origin, {
			name = `Cross{i}`,
			pos = { 0, 0.52, 0 },
			size = size,
			color = CROSS_COLOR,
			material = "Neon",
			canCollide = false,
		})
		bar.CastShadow = false
	end

	local sign = Kit.billboard(glow, 220, 7, "HEAL PAD", "Restores health & flushes rads", GLOW_COLOR, 60, 28, 16)
	-- A red heart under the sign's text (on request).
	sign.Size += UDim2.fromOffset(0, HEART_PX)
	local heart = Instance.new("TextLabel")
	heart.Name = "Heart"
	heart.AnchorPoint = Vector2.new(0.5, 1)
	heart.Position = UDim2.fromScale(0.5, 1)
	heart.Size = UDim2.fromOffset(HEART_PX, HEART_PX)
	heart.BackgroundTransparency = 1
	heart.Font = Kit.FONT
	heart.TextSize = HEART_PX
	heart.TextColor3 = Color3.fromHex(HEART_COLOR)
	heart.TextStrokeTransparency = 1
	heart.Text = "♥"
	heart.Parent = sign
	Kit.textOutline(heart, 2.5)

	pad.Parent = parent
end

local function createHealPads(): Model
	local root = Instance.new("Model")
	root.Name = HealPads.MODEL_NAME
	Kit.stamp(root, BUILDER_SOURCE, BUILDER_VERSION)
	for _, spec in PADS do
		buildPad(root, spec.name, spec.z)
	end
	return root
end

function HealPads.build(parent: Instance?): Model
	local root = createHealPads()
	root.Parent = parent or Workspace
	return root
end

function HealPads.rebuild(parent: Instance?): Model
	local root = Kit.swap(HealPads.MODEL_NAME, createHealPads, parent) :: Model
	print(`[build] HealPads rebuilt — {#root:GetChildren()} pads`)
	return root
end

return HealPads
