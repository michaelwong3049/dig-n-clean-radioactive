--!strict
--[[
	HealPads.luau — Base Camp's two heal pads.

	    require(game.ServerScriptService.Server.build.HealPads).rebuild()

	ONE BEHIND EACH SHOP ROW, on request (2026-10-04): centred on the plaza's midline
	(x = 5.5, PLAZA_MID) in the paved strip between a row's stall backs (|z| = 44) and the
	north/south bases' front strips (|z| = 78). They mirror about the Trader's line (z = 0):
	south behind the Outfitter (Aura) + Hose Shop, north behind Magnet + Detector. Before
	this they sat either side of Stage 1's mouth at (85, +/-46), and before the square base
	layout behind the rows at (17.5, +/-68).

	A PAD IS A SHOWER ANYONE CAN USE, PLUS HEALING. The red core hex carries
	`Shower = true` (Kit.build tags it, ExposureService's shower cache finds it), and
	since it is on no plot it flushes everyone's rads, not just an owner's. `HealPad =
	true` is the extra: ExposureService heals Tuning.HEAL_PAD_HEAL_FRAC of max health a
	second while you stand in it. `Radius` is measured from the core to your
	HumanoidRootPart (about 3 studs up), so 10 reaches roughly the badge's outer hex.

	THE LOOK IS A HEART BADGE laid flat on the plaza (2026-10-03, from a reference image):
	a dark navy hexagon with a gear tooth off every corner, a purple bevelled ring, a red
	hex core and a glossy red heart outlined in near-black. Every layer is a slab from the
	plaza up to its own top, each a hair higher than the one under it, so the stack reads
	as flat paint with no z-fighting. Studded, like every other world prop.

	A HEXAGON IS THREE BLOCKS: an R x R*sqrt(3) rectangle at 0, 60 and 120 degrees unions
	to a regular hexagon of circumradius R exactly. Pointy along local Z, so the heart's
	tip and top sit on two corners.

	THE HEART'S TOP POINTS AWAY FROM THE PLAZA MIDDLE (out along +/-Z), so a player
	coming round the back of the shops sees it upright. Each pad's origin is yawed so its
	local +Z is that direction.

	SCALE shrinks the whole badge (0.8 since 2026-10-04, "slightly smaller"): every
	footprint size, offset and the heal Radius; layer heights stay as they are.

	NO LIGHTS: base camp already had too many (Shops' glowOutline note).
]]

local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local HealPads = {}

HealPads.MODEL_NAME = "HealPads"

local BUILDER_SOURCE = "src/server/build/HealPads.luau"
local BUILDER_VERSION = 10

local SCALE = 0.8 -- the whole badge; 1 reached ~12 studs to a tooth tip, 0.8 ~9.4
-- x 5.5 = PLAZA_MID, between each row's two booths. z 57 splits the gap between the shop
-- square's kerb (42) and the bases' fronts (72), so the ~9.4-stud teeth clear both
-- (2026-10-04, with the compact booths; was 61).
local PAD_X = 5.5
local PAD_Z = 57
local PADS = {
	{ name = "HealPadSouth", z = -PAD_Z, yaw = 180 }, -- behind the Aura booth + Trader row
	{ name = "HealPadNorth", z = PAD_Z, yaw = 0 }, -- behind the Magnet + Detector booths
}

local C = {
	outline = "1E1626",
	gear = "2E2D52",
	navy = "3A3866",
	purpleLight = "9277C9",
	purpleDark = "6E55A6",
	red = "A31C2A",
	redDeep = "861522",
	heart = "E3313E",
	shine = "FF8A7A",
}
local HEART_PX = 44
local REACH = 10 * SCALE

local SQRT3 = math.sqrt(3)
local LIFT = 0.04 -- each layer's top above the one under it

--- A regular hexagon of circumradius `r`, pointy along local Z, as a slab from the
--- floor up to `top`.
local function hex(parent: Instance, origin: CFrame, name: string, r: number, top: number, color: string, extra: { [string]: any }?): BasePart
	local first: BasePart? = nil
	for i, yaw in { 0, 60, 120 } do
		local part = Kit.build(parent, origin, {
			name = if i == 1 then name else `{name}{i}`,
			pos = { 0, top / 2, 0 },
			size = { r * SQRT3, top, r },
			color = color,
			material = "Plastic",
			studs = true,
			rot = Kit.ang(0, yaw, 0),
			canCollide = top <= 0.45,
			-- Station attributes go on ONE part only, or World.verify counts three pads.
			attributes = if i == 1 then extra else nil,
		})
		part.CastShadow = false
		first = first or part
	end
	return first :: BasePart
end

--- A flat disc of diameter `d` centred at local (x, z), from the floor up to `top`.
local function disc(parent: Instance, origin: CFrame, name: string, x: number, z: number, d: number, top: number, color: string)
	local part = Kit.build(parent, origin, {
		name = name,
		pos = { x, top / 2, z },
		size = { top, d, d },
		color = color,
		material = "Plastic",
		studs = true,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		canCollide = false,
	})
	part.CastShadow = false
end

--- The heart: a square turned 45 degrees with a disc on each upper edge. `grow` fattens
--- every piece by the same amount for the outline under it.
local function heart(parent: Instance, origin: CFrame, name: string, s: number, grow: number, top: number, color: string)
	-- Centred: the lobes reach 0.854s above the square's centre, the tip 0.707s below.
	local cz = -0.073 * s
	local square = Kit.build(parent, origin, {
		name = `{name}Body`,
		pos = { 0, top / 2, cz },
		size = { s + grow, top, s + grow },
		color = color,
		material = "Plastic",
		studs = true,
		rot = Kit.ang(0, 45, 0),
		canCollide = false,
	})
	square.CastShadow = false
	local off = s / (2 * math.sqrt(2))
	disc(parent, origin, `{name}LobeL`, off, cz + off, s + grow, top, color)
	disc(parent, origin, `{name}LobeR`, -off, cz + off, s + grow, top, color)
end

local function buildSparkles(part: BasePart)
	local e = Instance.new("ParticleEmitter")
	e.Name = "HealRise"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromHex(C.shine))
	e.LightEmission = 0.5
	e.LightInfluence = 0
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 10
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

local function buildSign(core: BasePart)
	local sign = Kit.billboard(core, 220, 7, "HEAL PAD", "Restores health & flushes rads", C.shine, 60, 28, 16)
	-- A red heart under the sign's text (on request).
	sign.Size += UDim2.fromOffset(0, HEART_PX)
	local label = Instance.new("TextLabel")
	label.Name = "Heart"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 1)
	label.Size = UDim2.fromOffset(HEART_PX, HEART_PX)
	label.BackgroundTransparency = 1
	label.Font = Kit.FONT
	label.TextSize = HEART_PX
	label.TextColor3 = Color3.fromHex(C.heart)
	label.TextStrokeTransparency = 1
	label.Text = "♥"
	label.Parent = sign
	Kit.textOutline(label, 2.5)
end

local function buildPad(parent: Instance, name: string, z: number, yaw: number)
	local pad = Instance.new("Model")
	pad.Name = name
	-- Local +Z points away from the plaza middle: the heart's top. On the grey path, so
	-- it sits on the plaza's raised floor.
	local origin = CFrame.new(PAD_X, Hub.PLAZA.topY + Hub.PLAZA_LIFT, z) * Kit.ang(0, yaw, 0)
	local k = SCALE

	local y = 0.3
	-- The gear: an outlined tooth off each corner, under the navy hex.
	for i = 0, 5 do
		local a = i * 60
		local dir = Kit.ang(0, a, 0)
		for _, layer in { { w = 3.4 * k, l = 3.2 * k, top = y, color = C.outline }, { w = 2.6 * k, l = 2.6 * k, top = y + LIFT, color = C.gear } } do
			local tooth = Kit.build(pad, origin * dir, {
				name = `Tooth{i + 1}`,
				pos = { 0, layer.top / 2, 10.2 * k },
				size = { layer.w, layer.top, layer.l },
				color = layer.color,
				material = "Plastic",
				studs = true,
				canCollide = true,
			})
			tooth.CastShadow = false
		end
	end
	hex(pad, origin, "Outline", 10.4 * k, y, C.outline)
	y += LIFT
	hex(pad, origin, "Gear", 9.8 * k, y, C.gear)
	y += LIFT
	hex(pad, origin, "Navy", 9.2 * k, y, C.navy)
	y += LIFT
	hex(pad, origin, "RingLine", 8.3 * k, y, C.outline)
	y += LIFT
	hex(pad, origin, "RingOuter", 7.9 * k, y, C.purpleLight)
	y += LIFT
	hex(pad, origin, "RingInner", 7.1 * k, y, C.purpleDark)
	y += LIFT
	hex(pad, origin, "CoreLine", 6.5 * k, y, C.outline)
	y += LIFT
	hex(pad, origin, "CoreDeep", 6.1 * k, y, C.redDeep)
	y += LIFT
	local core = hex(pad, origin, "Core", 5.6 * k, y, C.red, { Shower = true, HealPad = true, Radius = REACH })
	y += LIFT

	local s = 4.3 * k
	heart(pad, origin, "HeartLine", s, 0.8 * k, y, C.outline)
	y += LIFT
	heart(pad, origin, "Heart", s, 0, y, C.heart)
	y += LIFT
	-- Gloss on the lobe at the viewer's upper left (+X, facing local +Z), like the image.
	local off = s / (2 * math.sqrt(2))
	disc(pad, origin, "Shine", off + 0.35 * k, -0.073 * s + off + 0.45 * k, 1.1 * k, y, C.shine)
	disc(pad, origin, "ShineDot", off + 1.15 * k, -0.073 * s + off - 0.35 * k, 0.5 * k, y, C.shine)

	buildSparkles(core)
	buildSign(core)

	pad.Parent = parent
end

local function createHealPads(): Model
	local root = Instance.new("Model")
	root.Name = HealPads.MODEL_NAME
	Kit.stamp(root, BUILDER_SOURCE, BUILDER_VERSION)
	for _, spec in PADS do
		buildPad(root, spec.name, spec.z, spec.yaw)
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
