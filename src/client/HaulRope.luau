--!strict
--[[
	HaulRope.luau — the slim pull bar the haul panel draws its progress on.

	ONE RECTANGLE, THE LENGTH OF THE HEALTH BAR. DetectorController lays it over the
	vitals bars at exactly their bar column (x and width), one row up. The dirt end is on
	the left, in the stage's own soil; the right end is a steel cell with a magnet icon in
	it, part of the same rectangle behind a black divider. The nuke lies in the bar
	nose-first and slides from the dirt into the magnet cell.

	THE PROGRESS IS A SOLID FILL (on request, 2026-10-09: the see-through wash was hard to
	read). Behind the nuke the bar fills opaque in the signal's own rarity colour, with a
	shine along its top, over the rope pattern; the rope only shows in the part still to
	go. An outlined percentage sits in the middle of the rope.

	THE FUSE IS A WICK on its own thin row JUST ABOVE the bar (moved off the bar's top
	edge, on request), burning from the magnet end back toward the dirt: the length left
	is the time left, the white tick is Config/Detonation's ARM_AT, and a spark rides the
	burning end. No seconds are drawn; once the fuse arms, the bar's black outline
	flashes red.

	REEL IN IS THE BAR. There is no separate button: the magnet cell wears an E keycap
	(keyboard only) that kicks on every yank, and DetectorController lays a clear button
	over the whole bar for touch.

	STRAIN IS CRACKS, NOT A WARNING. An outclassed magnet is never told it is too weak
	(DigService's over-tier grind); the soil round the nuke cracks in glowing orange and
	the nuke judders -- harder while nobody is yanking.

	Frames only, no uploaded images, like every other piece of HUD -- the magnet icon is
	built from a circle, two arms and a punched-out middle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DetonationConfig = require(ReplicatedStorage.Shared.Config.Detonation)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)

local UIKit = require(script.Parent.UIKit)

local HaulRope = {}

-- ── Geometry, in design pixels ──────────────────────────────────────────────────
-- Everything is derived from the size build() is given.
local CELL_ASPECT = 1.6 -- the magnet cell is this many bar-heights wide: the icon, then the E keycap beside it
local DIVIDER = 3 -- the black line between the rope and the magnet cell
local INSET = 6 -- the strand and the wick stop this far in from either end
local NUKE_SIZE = Vector2.new(40, 62) -- drawn nose-up, then turned to lie nose-right
local NUKE_PAD = 4 -- clear space above and below the lying nuke
local WICK_HEIGHT = 6
local WICK_GAP = 4 -- between the wick row and the bar's top edge
-- What the caller leaves free over the bar for the wick (its spark spills a little higher).
HaulRope.WICK_ROW = WICK_HEIGHT + WICK_GAP
local PERCENT_TEXT = 17
local SHEEN_HEIGHT = 5
local STRAND_HEIGHT = 8
local STRAND_PITCH = 7 -- one twist of the rope every this many px
local ICON_FILL = 0.78 -- the magnet icon's share of the cell's height
local ICON_X = 0.38 -- the icon's centre across the cell, leaving the right end to the keycap
local KEYCAP = 15

-- ── Colour ──────────────────────────────────────────────────────────────────────
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local DARK = Color3.fromHex("120C08") -- what the soil darkens toward
local STEEL = Color3.fromHex("4A4F57") -- the rope's magnet end
local CELL_TOP = Color3.fromHex("5D646E")
local CELL_BOTTOM = Color3.fromHex("2F343B")
local MAGNET_RED = Color3.fromHex("E3342F")
local POLE = Color3.fromHex("DFE6EE")
-- A floor darker than this (Stage 4's near-black) is lifted first, or the dirt end
-- vanishes into the black outline.
local MIN_SOIL_VALUE = 0.46
local CRACK_COLOR = Color3.fromHex("FF7A45")
local STRAND_LIGHT = Color3.fromHex("D9B779")
local STRAND_DARK = Color3.fromHex("A8844A")
local WICK_COLOR = Color3.fromHex("F4E3B5")
local WICK_BURNT = Color3.fromHex("2B1A0C")
local ALARM_RED = Color3.fromHex("FF3B2F") -- the outline's armed flash
local SPARK_COLORS = { Color3.fromHex("FF6A00"), Color3.fromHex("FFD23A"), WHITE }

export type Rope = {
	root: Frame,
	outline: UIStroke,
	width: number,
	height: number,
	nukeStart: number,
	nukeEnd: number,
	nukeLength: number,
	ropeGradient: UIGradient,
	trail: Frame,
	percent: TextLabel,
	wickX: number,
	wickY: number,
	nuke: Frame,
	accentParts: { Frame },
	cracks: { Frame },
	wickTrack: Frame,
	wick: Frame,
	wickLength: number,
	spark: Frame,
	sparkParts: { Frame },
	keycap: Frame,
	keycapKick: UIScale,
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
	alarm: number, -- 0..1, how red the bar's outline is (the armed flash)
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

local OVAL = UDim.new(0.5, 0)

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
-- at x=20), reaching out on both flanks. They turn and scale with the nuke.
local CRACK_PATHS: { { Vector2 } } = {
	{ Vector2.new(-2, 6), Vector2.new(-10, 12), Vector2.new(-8, 20), Vector2.new(-18, 26) },
	{ Vector2.new(-2, 30), Vector2.new(-12, 34), Vector2.new(-14, 44) },
	{ Vector2.new(42, 10), Vector2.new(50, 6), Vector2.new(56, 14), Vector2.new(64, 12) },
	{ Vector2.new(42, 36), Vector2.new(50, 42), Vector2.new(48, 50), Vector2.new(58, 56) },
}

--- The nuke in the bar: a soft glow in the signal's colour, the capsule body (the same
--- slag-grey gradient as the dug-up crust), fins, a band in the signal's colour and two
--- crust scabs. Drawn nose-up at 40x62, turned a quarter to lie nose-right and scaled
--- to the bar's height, centred on its position.
local function buildNuke(parent: Instance, scale: number, z: number): (Frame, { Frame }, { Frame })
	local nuke = Instance.new("Frame")
	nuke.Name = "Nuke"
	nuke.AnchorPoint = Vector2.new(0.5, 0.5)
	nuke.Size = UDim2.fromOffset(NUKE_SIZE.X, NUKE_SIZE.Y)
	nuke.Rotation = 90
	nuke.BackgroundTransparency = 1
	nuke.ZIndex = z
	nuke.Parent = parent
	local fit = Instance.new("UIScale")
	fit.Scale = scale
	fit.Parent = nuke

	local accentParts = {}
	-- No radial gradients in Roblox UI, so the glow is stacked ovals, each fainter and
	-- wider than the one inside it.
	for i, spec in { { 52, 80, 0.8 }, { 40, 66, 0.66 } } do
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
	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Color = BLACK
	bodyStroke.Thickness = 2
	bodyStroke.Parent = body

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

--- A horseshoe magnet, poles pointing LEFT at the nuke ("⊃"), `size` px square, drawn
--- from frames: a red disc for the bend, two red arms, silver pole tips, and the gap
--- between the arms punched out in the cell's own steel.
local function buildMagnetIcon(parent: Instance, size: number, z: number)
	local icon = Instance.new("Frame")
	icon.Name = "MagnetIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(ICON_X, 0.5)
	icon.Size = UDim2.fromOffset(size, size)
	icon.BackgroundTransparency = 1
	icon.ZIndex = z
	icon.Parent = parent

	local u = size / 28 -- drawn on a 28-unit grid
	local function piece(name: string, x: number, y: number, w: number, h: number, color: Color3, layer: number, round: UDim?): Frame
		return box(icon, name, x * u, y * u, w * u, h * u, color, z + layer, round)
	end
	local arm = 8 -- arm thickness, in grid units
	-- The black outline first: the same shape grown by one unit all round.
	piece("OutlineBend", 7, -1, 22, 30, BLACK, 0, OVAL)
	piece("OutlineTop", -1, -1, 18, arm + 2, BLACK, 0)
	piece("OutlineBottom", -1, 27 - arm, 18, arm + 2, BLACK, 0)
	-- Then the red shape over it.
	piece("Bend", 8, 0, 20, 28, MAGNET_RED, 1, OVAL)
	piece("ArmTop", 0, 0, 16, arm, MAGNET_RED, 1)
	piece("ArmBottom", 0, 28 - arm, 16, arm, MAGNET_RED, 1)
	-- The gap between the arms, in the steel behind. One unit short of each arm, so a
	-- line of the black outline underneath shows along both inner edges.
	piece("Gap", -2, arm + 1, 17, 26 - 2 * arm, CELL_BOTTOM:Lerp(CELL_TOP, 0.5), 2)
	-- Silver pole tips at the open end.
	piece("PoleTop", 0, 0, 6, arm, POLE, 3)
	piece("PoleBottom", 0, 28 - arm, 6, arm, POLE, 3)
end

--- The spark at the wick's burning end: three ovals, orange round yellow round white,
--- re-sized every frame so it flickers.
local function buildSpark(parent: Instance, z: number): (Frame, { Frame })
	local spark = Instance.new("Frame")
	spark.Name = "Spark"
	spark.AnchorPoint = Vector2.new(0.5, 0.5)
	spark.Size = UDim2.fromOffset(16, 16)
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

--- Build the bar into `parent` at `position`, `width` x `height`. Uncoloured until
--- paint() and setAccent().
function HaulRope.build(parent: Instance, position: UDim2, width: number, height: number): Rope
	local root = Instance.new("Frame")
	root.Name = "PullBar"
	root.Position = position
	root.Size = UDim2.fromOffset(width, height)
	root.BackgroundColor3 = WHITE
	root.BorderSizePixel = 0
	-- RECTANGULAR clipping (Roblox ignores UICorner when clipping); the radius is small
	-- enough that the square corners it leaves stay under the 3px stroke.
	root.ClipsDescendants = true
	root.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = UIKit.Stroke.normal
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = root
	local ropeGradient = Instance.new("UIGradient")
	ropeGradient.Parent = root

	local cell = math.round(height * CELL_ASPECT)
	local ropeLength = width - cell - DIVIDER


	-- The rope: a braided strip down the middle, slanted twists clipped to a straight
	-- band with a black edge top and bottom.
	local strand = box(root, "Strand", INSET, (height - STRAND_HEIGHT) / 2, ropeLength - 2 * INSET, STRAND_HEIGHT, STRAND_DARK, 3)
	strand.ClipsDescendants = true
	local strandStroke = Instance.new("UIStroke")
	strandStroke.Color = BLACK
	strandStroke.Thickness = 1.5
	strandStroke.Parent = strand
	for i = 0, math.ceil(strand.Size.X.Offset / STRAND_PITCH) do
		local twist = box(strand, "Twist", i * STRAND_PITCH - 2, -3, 4, STRAND_HEIGHT + 6, STRAND_LIGHT, 3)
		twist.Rotation = 30
	end

	-- THE FILL: solid, in the signal's colour, from the dirt end up to the nuke, over the
	-- rope pattern, with a shine along its top.
	local trail = box(root, "Fill", 0, 0, 0, height, WHITE, 4)
	local sheen = box(trail, "Sheen", 0, 2, 0, SHEEN_HEIGHT, WHITE, 5, UDim.new(0, 2))
	sheen.Size = UDim2.new(1, 0, 0, SHEEN_HEIGHT)
	sheen.BackgroundTransparency = 0.55

	-- The percentage, outlined, in the middle of the rope (not the magnet cell).
	local percent = Instance.new("TextLabel")
	percent.Name = "Percent"
	percent.AnchorPoint = Vector2.new(0.5, 0.5)
	percent.Position = UDim2.fromOffset(ropeLength / 2, height / 2)
	percent.Size = UDim2.fromOffset(80, height)
	percent.BackgroundTransparency = 1
	percent.Font = UIKit.Font.hero
	percent.TextSize = PERCENT_TEXT
	percent.TextColor3 = WHITE
	percent.TextStrokeColor3 = BLACK
	percent.TextStrokeTransparency = 0
	percent.Text = "0%"
	percent.ZIndex = 20
	percent.Parent = root

	-- THE WICK, on its own row just above the bar (in `parent`, outside the bar's clip),
	-- burning from the magnet end back toward the dirt.
	local wickLength = ropeLength - 2 * INSET
	local wickX = position.X.Offset + INSET
	local wickY = position.Y.Offset - WICK_GAP - WICK_HEIGHT
	local wickTrack = box(parent, "WickTrack", wickX, wickY, wickLength, WICK_HEIGHT, WICK_BURNT, 4, UDim.new(0, 3))
	local wickStroke = Instance.new("UIStroke")
	wickStroke.Color = BLACK
	wickStroke.Thickness = 1.5
	wickStroke.Parent = wickTrack
	local wick = box(wickTrack, "Wick", 0, 0, wickLength, WICK_HEIGHT, WICK_COLOR, 5, UDim.new(0, 3))
	-- Point of no return: the wick left unburnt at ARM_AT.
	local armTick = box(wickTrack, "ArmLine", wickLength * (1 - DetonationConfig.ARM_AT), WICK_HEIGHT / 2, 3, 14, WHITE, 6)
	armTick.AnchorPoint = Vector2.new(0.5, 0.5)
	local spark, sparkParts = buildSpark(parent, 12)

	-- THE MAGNET CELL: the bar's right end, steel, behind a black divider.
	local cellFrame = box(root, "MagnetCell", width - cell, 0, cell, height, WHITE, 8)
	local cellGradient = Instance.new("UIGradient")
	cellGradient.Rotation = 90
	cellGradient.Color = ColorSequence.new(CELL_TOP, CELL_BOTTOM)
	cellGradient.Parent = cellFrame
	box(root, "Divider", width - cell - DIVIDER, 0, DIVIDER, height, BLACK, 9)
	buildMagnetIcon(cellFrame, math.round(height * ICON_FILL), 9)

	-- The E keycap, tucked in the cell's corner (keyboard only; DetectorController hides
	-- it on touch). Kicks on every yank.
	local keycap = box(cellFrame, "Keycap", cell - 3, height - 3, KEYCAP, KEYCAP, WHITE, 14, UDim.new(0, 4))
	keycap.AnchorPoint = Vector2.new(1, 1)
	local keyStroke = Instance.new("UIStroke")
	keyStroke.Color = BLACK
	keyStroke.Thickness = 1.5
	keyStroke.Parent = keycap
	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "Key"
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Font = UIKit.Font.hero
	keyLabel.TextSize = 11
	keyLabel.TextColor3 = BLACK
	keyLabel.Text = "E"
	keyLabel.ZIndex = 15
	keyLabel.Parent = keycap
	local keycapKick = Instance.new("UIScale")
	keycapKick.Parent = keycap

	local scale = (height - 2 * NUKE_PAD) / NUKE_SIZE.X
	local nukeLength = NUKE_SIZE.Y * scale
	local nuke, accentParts, cracks = buildNuke(root, scale, 6)
	table.insert(accentParts, trail)

	return {
		root = root,
		outline = stroke,
		width = width,
		height = height,
		nukeStart = INSET + nukeLength / 2,
		nukeEnd = ropeLength - INSET - nukeLength / 2,
		nukeLength = nukeLength,
		ropeGradient = ropeGradient,
		trail = trail,
		percent = percent,
		wickX = wickX,
		wickY = wickY,
		nuke = nuke,
		accentParts = accentParts,
		cracks = cracks,
		wickTrack = wickTrack,
		wick = wick,
		wickLength = wickLength,
		spark = spark,
		sparkParts = sparkParts,
		keycap = keycap,
		keycapKick = keycapKick,
		stageId = nil,
		accent = nil,
		rng = Random.new(),
	}
end

--- Colour the bar's dirt end in a stage's own soil. A no-op for the stage it is already
--- painted in, so it is safe to call on every state update.
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
		ColorSequenceKeypoint.new(0, soil:Lerp(DARK, 0.65)),
		ColorSequenceKeypoint.new(0.35, soil:Lerp(DARK, 0.45)),
		ColorSequenceKeypoint.new(1, STEEL),
	})
end

--- The signal's colour on the nuke's band and glow and the fill behind it. Cheap to
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

--- Show or hide the E keycap (keyboard only). With no keycap the magnet icon takes
--- the middle of its cell.
function HaulRope.showKeycap(rope: Rope, shown: boolean)
	rope.keycap.Visible = shown
	local icon = (rope.keycap.Parent :: Instance):FindFirstChild("MagnetIcon")
	if icon and icon:IsA("Frame") then
		icon.Position = UDim2.fromScale(if shown then ICON_X else 0.5, 0.5)
	end
end

--- Move the nuke, burn the wick and kick the keycap to where the haul is, every frame.
function HaulRope.step(rope: Rope, input: Input)
	local x = rope.nukeStart + (rope.nukeEnd - rope.nukeStart) * math.clamp(input.progress, 0, 1)

	-- The judder: the soil fighting an outclassed magnet (harder while it is winning),
	-- plus a small jolt on each yank so the click lands on the nuke too.
	local strain = math.clamp(input.strain, 0, 3)
	local rng = rope.rng
	local jitter = (rng:NextNumber() - 0.5) * strain * (if input.idle then 1.4 else 0.5)
		+ (rng:NextNumber() - 0.5) * 3 * input.kick
	rope.nuke.Position = UDim2.fromOffset(x + jitter, rope.height / 2 + jitter * 0.3)
	rope.trail.Size = UDim2.fromOffset(x, rope.height)
	rope.percent.Text = `{math.floor(math.clamp(input.progress, 0, 1) * 100 + 0.5)}%`
	rope.keycapKick.Scale = 1 + 0.3 * input.kick
	rope.outline.Color = BLACK:Lerp(ALARM_RED, input.alarm)

	local cracked = strain > 0
	local glow = if cracked then 1 - (strain / 3) * (0.55 + 0.45 * math.sin(input.now * 14)) else 1
	for _, seg in rope.cracks do
		seg.Visible = cracked
		seg.BackgroundTransparency = glow
	end

	local lit = input.fuse ~= nil
	rope.wickTrack.Visible = lit
	rope.spark.Visible = lit
	if input.fuse then
		local left = rope.wickLength * (1 - math.clamp(input.fuse, 0, 1))
		rope.wick.Size = UDim2.fromOffset(left, WICK_HEIGHT)
		rope.spark.Position = UDim2.fromOffset(rope.wickX + left, rope.wickY + WICK_HEIGHT / 2)
		for i, dot in rope.sparkParts do
			local d = (22 - i * 6) * (0.8 + rng:NextNumber() * 0.45)
			dot.Size = UDim2.fromOffset(d, d)
		end
	end
end

return HaulRope
