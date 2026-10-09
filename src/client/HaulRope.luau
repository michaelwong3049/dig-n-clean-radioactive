--!strict
--[[
	HaulRope.luau — the tug-of-war rope the haul panel draws its progress on.

	THE NUKE IS THE PROGRESS BAR. A rope runs left to right: the dirt end on the left, in
	the stage's own soil, and the player's own magnet on the right with its poles turned
	at the rope. The nuke lies on the rope nose-first and slides from the dirt to the
	magnet; a wash of the signal's colour trails behind it. There is no other fill -- how
	far along the rope the nuke is IS the reading.

	THE FUSE IS A WICK. Along the top of the rope a lit wick burns down from the magnet
	end toward the dirt: the length still unburnt is the time left, the white tick on it
	is Config/Detonation's ARM_AT (past it the release stops working), and a chip riding
	on the spark says the seconds. The caller decides the chip's words and colour; this
	module only moves it. With no fuse at all (the tutorial's first dig) the wick is
	hidden and the chip says so.

	STRAIN IS CRACKS, NOT A WARNING. An outclassed magnet is never told it is too weak
	(DigService's over-tier grind); the soil round the nuke cracks in glowing orange and
	the nuke judders -- harder while nobody is yanking.

	Frames only, no uploaded images, like every other piece of HUD; the magnet is the
	player's own model in a viewport (GearArt.showHung, turned on its side).

	This module only builds and moves frames. DetectorController owns the panel, the
	readout over it, REEL IN / LET GO and when any of it is up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DetonationConfig = require(ReplicatedStorage.Shared.Config.Detonation)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)

local GearArt = require(script.Parent.GearArt)
local UIKit = require(script.Parent.UIKit)

local HaulRope = {}

-- ── Geometry, in design pixels ──────────────────────────────────────────────────
-- Everything horizontal is derived from the width build() is given; the height is the
-- rope's own and fixed, because the art down it (chip, wick, rope, magnet) is.
local CHIP_HEIGHT = 24
local WICK_Y = 34 -- the wick's top edge; the chip rides just over it
local WICK_HEIGHT = 8
local ROPE_Y = 52
local ROPE_HEIGHT = 64
local ROPE_MID = ROPE_Y + ROPE_HEIGHT / 2
HaulRope.HEIGHT = ROPE_Y + ROPE_HEIGHT + 4 -- the panel lays itself out around this
local MAGNET_BOX = Vector2.new(96, 96) -- the magnet's viewport, at the right edge
-- Open air between the rope's end and the magnet's box (on request: the magnet sat
-- tucked over the rope's end and read as part of it).
local MAGNET_GAP = 22
local NUKE_SIZE = Vector2.new(40, 62) -- drawn nose-up, then turned to lie nose-right
local NUKE_SCALE = 1.4 -- the glyph is drawn at 40x62 and blown up to fill the taller rope
local NUKE_LENGTH = NUKE_SIZE.Y * NUKE_SCALE
local NUKE_START = 8 + NUKE_LENGTH / 2 -- tail against the rope's dirt end
local NUKE_GAP = 8 -- the nose stops this short of the rope's magnet end
local WICK_INSET = 16 -- the wick starts and stops this far in from the rope's ends
local STRAND_PITCH = 8 -- one twist of the rope every this many px
local CHIP_MARGIN = 26 -- the chip's centre never comes closer to either end than this

-- ── Colour ──────────────────────────────────────────────────────────────────────
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local DARK = Color3.fromHex("120C08") -- what the soil darkens toward
local STEEL = Color3.fromHex("3B4048") -- the rope's magnet end
-- A floor darker than this (Stage 4's near-black) is lifted first, or the dirt end
-- vanishes into the black outline.
local MIN_SOIL_VALUE = 0.46
local CRACK_COLOR = Color3.fromHex("FF7A45")
local STRAND_LIGHT = Color3.fromHex("D9B779")
local STRAND_DARK = Color3.fromHex("A8844A")
local WICK_COLOR = Color3.fromHex("F4E3B5")
local WICK_BURNT = Color3.fromHex("2B1A0C")
local SPARK_COLORS = { Color3.fromHex("FF6A00"), Color3.fromHex("FFD23A"), WHITE }

export type Rope = {
	root: Frame,
	width: number,
	nukeEnd: number,
	ropeGradient: UIGradient,
	trail: Frame,
	nuke: Frame,
	magnet: ViewportFrame,
	magnetTier: number?,
	accentParts: { Frame },
	cracks: { Frame },
	wickTrack: Frame,
	wick: Frame,
	wickLength: number,
	armTick: Frame,
	spark: Frame,
	sparkParts: { Frame },
	chip: TextLabel,
	stageId: number?,
	accent: Color3?,
	rng: Random,
}

export type Input = {
	progress: number, -- 0 at the dirt end, 1 at the magnet
	strain: number, -- stages the soil outclasses the magnet (0 = rated)
	kick: number, -- 0..1, the per-yank jolt
	idle: boolean, -- no yank in the last moment: the soil is winning, judder harder
	now: number,
	fuse: number?, -- 0..1 through the window; nil = no fuse on this haul
	fuseText: string, -- the chip's words
	fuseColor: Color3, -- the chip's fill
}

local function box(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, z: number, round: UDim?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = round
		corner.Parent = f
	end
	return f
end

local function outline(parent: GuiObject, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

local OVAL = UDim.new(0.5, 0)
-- The rope, its trail and the chip are RECTANGLES with a small corner, not pills (on request).
local CORNER = UDim.new(0, 6)

--- A straight crack segment from `a` to `b`, laid as a thin rotated bar.
local function segment(parent: Instance, a: Vector2, b: Vector2, z: number): Frame
	local d = b - a
	local f = box(parent, "Crack", 0, 0, d.Magnitude + 2, 2.4, CRACK_COLOR, z, UDim.new(1, 0))
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	return f
end

-- Crack paths around the nuke, in nuke-local pixels (drawn nose-up: nose at y=0, axis
-- at x=20), reaching out into the soil on both flanks. They turn with the nuke.
local CRACK_PATHS: { { Vector2 } } = {
	{ Vector2.new(-2, 6), Vector2.new(-10, 12), Vector2.new(-8, 20), Vector2.new(-18, 26) },
	{ Vector2.new(-2, 30), Vector2.new(-12, 34), Vector2.new(-14, 44) },
	{ Vector2.new(42, 10), Vector2.new(50, 6), Vector2.new(56, 14), Vector2.new(64, 12) },
	{ Vector2.new(42, 36), Vector2.new(50, 42), Vector2.new(48, 50), Vector2.new(58, 56) },
}

--- The nuke on the rope: a soft glow in the signal's colour, the capsule body (the
--- same slag-grey gradient as the dug-up crust), fins, a band in the signal's colour
--- and two crust scabs. Drawn nose-up and turned a quarter to lie nose-right, centred
--- on its position (a GuiObject turns about its centre, children with it).
local function buildNuke(parent: Instance, z: number): (Frame, { Frame }, { Frame })
	local nuke = Instance.new("Frame")
	nuke.Name = "Nuke"
	nuke.AnchorPoint = Vector2.new(0.5, 0.5)
	nuke.Size = UDim2.fromOffset(NUKE_SIZE.X, NUKE_SIZE.Y)
	nuke.Rotation = 90
	nuke.BackgroundTransparency = 1
	nuke.ZIndex = z
	nuke.Parent = parent
	local nukeScale = Instance.new("UIScale")
	nukeScale.Scale = NUKE_SCALE
	nukeScale.Parent = nuke

	local accentParts = {}
	-- No radial gradients in Roblox UI, so the glow is three stacked ovals, each fainter
	-- and wider than the one inside it.
	for i, spec in { { 64, 96, 0.86 }, { 52, 80, 0.78 }, { 40, 66, 0.66 } } do
		local glow = box(nuke, "Glow" .. i, 0, 0, spec[1], spec[2], WHITE, z + i, OVAL)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromOffset(NUKE_SIZE.X / 2, 31)
		glow.BackgroundTransparency = spec[3]
		table.insert(accentParts, glow)
	end

	local finL = box(nuke, "FinLeft", 3, 40, 8, 18, Color3.fromHex("4B463B"), z + 4)
	finL.Rotation = 25
	local finR = box(nuke, "FinRight", 29, 40, 8, 18, Color3.fromHex("403B32"), z + 4)
	finR.Rotation = -25
	box(nuke, "Tail", 15, 54, 10, 8, Color3.fromHex("3B372F"), z + 4)

	local body = box(nuke, "Body", 5, 0, 30, 58, WHITE, z + 5, UDim.new(0, 15))
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("36332C")),
		ColorSequenceKeypoint.new(0.42, Color3.fromHex("8A836D")),
		ColorSequenceKeypoint.new(0.6, Color3.fromHex("6D6754")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("2E2B25")),
	})
	grad.Parent = body

	-- Across the capsule's straight flank, so a plain rectangle meets its sides exactly.
	table.insert(accentParts, box(nuke, "Band", 5, 37, 30, 6, WHITE, z + 6))
	box(nuke, "Scab", 10, 12, 10, 8, Color3.fromHex("5B4A35"), z + 6, OVAL)
	box(nuke, "Scab", 22, 23, 8, 10, Color3.fromHex("5B4A35"), z + 6, OVAL)

	local cracks = {}
	for _, path in CRACK_PATHS do
		for i = 1, #path - 1 do
			local seg = segment(nuke, path[i], path[i + 1], z + 7)
			seg.Visible = false
			table.insert(cracks, seg)
		end
	end

	return nuke, accentParts, cracks
end

--- The spark at the wick's burning end: three ovals, orange round yellow round white,
--- re-sized every frame so it flickers.
local function buildSpark(parent: Instance, z: number): (Frame, { Frame })
	local spark = Instance.new("Frame")
	spark.Name = "Spark"
	spark.AnchorPoint = Vector2.new(0.5, 0.5)
	spark.Size = UDim2.fromOffset(24, 24)
	spark.BackgroundTransparency = 1
	spark.ZIndex = z
	spark.Parent = parent
	local parts = {}
	for i, color in SPARK_COLORS do
		local dot = box(spark, "Glow" .. i, 0, 0, 0, 0, color, z + i, OVAL)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.BackgroundTransparency = if i == 1 then 0.35 else 0
		table.insert(parts, dot)
	end
	return spark, parts
end

--- Build the rope into `parent` at `position`, `width` wide and HaulRope.HEIGHT tall.
--- Uncoloured until paint() and setAccent(), magnet-less until setMagnet().
function HaulRope.build(parent: Instance, position: UDim2, width: number): Rope
	local root = Instance.new("Frame")
	root.Name = "TugRope"
	root.Position = position
	root.Size = UDim2.fromOffset(width, HaulRope.HEIGHT)
	root.BackgroundTransparency = 1
	root.Parent = parent

	-- THE ROPE BAR: dirt at the left end fading to steel at the magnet's.
	local ropeLength = width - MAGNET_BOX.X - MAGNET_GAP
	local bar = box(root, "Rope", 0, ROPE_Y, ropeLength, ROPE_HEIGHT, WHITE, 2, CORNER)
	outline(bar, UIKit.Stroke.normal)
	local ropeGradient = Instance.new("UIGradient")
	ropeGradient.Parent = bar

	-- The wash behind the nuke, in the signal's colour: from the dirt end up to the nuke.
	-- Its own corners, matching the bar's, rather than a clip on the bar.
	local trail = box(root, "Trail", 0, ROPE_Y, 0, ROPE_HEIGHT, WHITE, 3, CORNER)
	trail.BackgroundTransparency = 0.55

	-- The rope itself: a braided strip down the bar's middle, slanted twists clipped to
	-- a straight band with a black edge top and bottom.
	local strand = box(root, "Strand", 10, ROPE_MID - 7, ropeLength - 20, 14, STRAND_DARK, 4)
	strand.ClipsDescendants = true
	outline(strand, 2)
	for i = 0, math.ceil(strand.Size.X.Offset / STRAND_PITCH) do
		local twist = box(strand, "Twist", i * STRAND_PITCH - 2, -4, 5, 22, STRAND_LIGHT, 4)
		twist.Rotation = 30
	end

	-- THE WICK, over the rope, burning from the magnet end back toward the dirt.
	-- It spans the rope, not the magnet's gap.
	local wickStart = WICK_INSET
	local wickLength = ropeLength - WICK_INSET - wickStart
	local wickTrack = box(root, "WickTrack", wickStart, WICK_Y, wickLength, WICK_HEIGHT, WICK_BURNT, 5, UDim.new(0, 2))
	outline(wickTrack, 2)
	local wick = box(wickTrack, "Wick", 0, 0, wickLength, WICK_HEIGHT, WICK_COLOR, 6, UDim.new(0, 2))
	-- Point of no return: the wick left unburnt at ARM_AT.
	local armTick = box(wickTrack, "ArmLine", wickLength * (1 - DetonationConfig.ARM_AT), WICK_HEIGHT / 2, 3, 16, WHITE, 7)
	armTick.AnchorPoint = Vector2.new(0.5, 0.5)
	outline(armTick, 1.5)
	local spark, sparkParts = buildSpark(root, 8)

	local chip = Instance.new("TextLabel")
	chip.Name = "FuseChip"
	chip.AnchorPoint = Vector2.new(0.5, 1)
	chip.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.BackgroundColor3 = WHITE
	chip.BorderSizePixel = 0
	chip.Font = UIKit.Font.hero
	chip.TextSize = 17
	chip.TextColor3 = BLACK
	chip.ZIndex = 12
	chip.Parent = root
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = CORNER
	chipCorner.Parent = chip
	local chipPad = Instance.new("UIPadding")
	chipPad.PaddingLeft = UDim.new(0, 8)
	chipPad.PaddingRight = UDim.new(0, 8)
	chipPad.Parent = chip
	outline(chip, 2)

	-- THE MAGNET past the rope's right end, across a gap, poles turned at the nuke.
	local slot = Instance.new("Frame")
	slot.Name = "Magnet"
	slot.BackgroundTransparency = 1
	slot.Position = UDim2.fromOffset(width - MAGNET_BOX.X, ROPE_MID - MAGNET_BOX.Y / 2)
	slot.Size = UDim2.fromOffset(MAGNET_BOX.X, MAGNET_BOX.Y)
	slot.ZIndex = 9
	slot.Parent = root
	local magnet = GearArt.viewport(slot)
	magnet.ZIndex = 9

	local nuke, accentParts, cracks = buildNuke(root, 10)
	table.insert(accentParts, trail)

	return {
		root = root,
		width = width,
		nukeEnd = ropeLength - NUKE_GAP - NUKE_LENGTH / 2,
		ropeGradient = ropeGradient,
		trail = trail,
		nuke = nuke,
		magnet = magnet,
		magnetTier = nil,
		accentParts = accentParts,
		cracks = cracks,
		wickTrack = wickTrack,
		wick = wick,
		wickLength = wickLength,
		armTick = armTick,
		spark = spark,
		sparkParts = sparkParts,
		chip = chip,
		stageId = nil,
		accent = nil,
		rng = Random.new(),
	}
end

--- Draw magnet tier `tier` at the rope's end. A no-op for the tier already drawn, so it
--- is safe to call on every state update.
function HaulRope.setMagnet(rope: Rope, tier: number)
	if rope.magnetTier == tier then
		return
	end
	rope.magnetTier = tier
	GearArt.showHung(rope.magnet, tier, MAGNET_BOX.X / MAGNET_BOX.Y, true)
end

--- Colour the rope's dirt end in a stage's own soil. A no-op for the stage it is
--- already painted in, so it is safe to call on every state update.
function HaulRope.paint(rope: Rope, stageId: number)
	if rope.stageId == stageId then
		return
	end
	local def = Stages.get(stageId)
	if def == nil then
		return
	end
	rope.stageId = stageId
	local floor = Color3.fromHex(def.color)
	local h, s, v = floor:ToHSV()
	local soil = if v < MIN_SOIL_VALUE then Color3.fromHSV(h, s * 0.9, MIN_SOIL_VALUE) else floor
	rope.ropeGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, soil:Lerp(DARK, 0.45)),
		ColorSequenceKeypoint.new(0.35, soil:Lerp(DARK, 0.2)),
		ColorSequenceKeypoint.new(1, STEEL),
	})
end

--- The signal's colour on the nuke's band and glow and the trail behind it. Cheap to
--- call every tick.
function HaulRope.setAccent(rope: Rope, color: Color3)
	if rope.accent == color then
		return
	end
	rope.accent = color
	for _, part in rope.accentParts do
		part.BackgroundColor3 = color
	end
end

--- Move the nuke and burn the wick to where the haul is, every frame.
function HaulRope.step(rope: Rope, input: Input)
	local x = NUKE_START + (rope.nukeEnd - NUKE_START) * math.clamp(input.progress, 0, 1)

	-- The judder: the soil fighting an outclassed magnet (harder while it is winning),
	-- plus a small jolt on each yank so the click lands on the nuke too.
	local strain = math.clamp(input.strain, 0, 3)
	local rng = rope.rng
	local jitter = (rng:NextNumber() - 0.5) * strain * (if input.idle then 1.4 else 0.5)
		+ (rng:NextNumber() - 0.5) * 3 * input.kick
	rope.nuke.Position = UDim2.fromOffset(x + jitter, ROPE_MID + jitter * 0.5)
	rope.trail.Size = UDim2.fromOffset(x, ROPE_HEIGHT)

	local cracked = strain > 0
	local glow = if cracked then 1 - (strain / 3) * (0.55 + 0.45 * math.sin(input.now * 14)) else 1
	for _, seg in rope.cracks do
		seg.Visible = cracked
		seg.BackgroundTransparency = glow
	end

	-- The wick. Its burning end is where the spark and the chip ride.
	local lit = input.fuse ~= nil
	rope.wickTrack.Visible = lit
	rope.spark.Visible = lit
	local trackX = rope.wickTrack.Position.X.Offset
	local burnX = trackX + rope.wickLength
	if input.fuse then
		local left = rope.wickLength * (1 - math.clamp(input.fuse, 0, 1))
		rope.wick.Size = UDim2.fromOffset(left, WICK_HEIGHT)
		burnX = trackX + left
		rope.spark.Position = UDim2.fromOffset(burnX, WICK_Y + WICK_HEIGHT / 2)
		for i, dot in rope.sparkParts do
			local d = (32 - i * 8) * (0.8 + rng:NextNumber() * 0.45)
			dot.Size = UDim2.fromOffset(d, d)
		end
	end
	local chipX = math.clamp(burnX, CHIP_MARGIN, rope.width - CHIP_MARGIN)
	rope.chip.Position = UDim2.fromOffset(chipX, WICK_Y - 4)
	rope.chip.Text = input.fuseText
	rope.chip.BackgroundColor3 = input.fuseColor
end

return HaulRope
