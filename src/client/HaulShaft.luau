--!strict
--[[
	HaulShaft.luau — the soil shaft the haul panel draws its progress in.

	THE NUKE IS THE PROGRESS BAR. A cut-away of the ground: a strip of sky, the stage's
	grass line, five bands of the stage's own soil, and down the middle a shaft with the
	magnet hanging over it. The nuke sits in the shaft at the depth it has left to come
	up, hung off the magnet on a cable, with a dotted trail below it where it has been.
	There is no fill anywhere -- the distance between the nuke's nose and the grass IS
	the reading.

	TRUE DEPTH, NOT A FITTED BAR. The ruler runs from the surface to the deepest burial
	any signal can have (RULER_METRES, derived from Tuning's DIG_DEPTH_* and the rarity
	count), and the nuke is drawn at its real depth on it. So a Common starts a hand's
	width under the grass and an Anomaly starts near the floor: how far down the nuke
	begins says how deep it was buried, before a single yank.

	THE STAGE'S OWN SOIL. paint() recolours the cut-away from Config/Stages: the bands are
	the stage's floor colour darkening with depth, the sky strip is its fog, the grass is
	the lip colour its walls wear (Scenery.wallCapPair). Stage 4 also gets a seam of its
	ooze through the middle band, the only field whose ooze is out on the ground.

	STRAIN IS CRACKS, NOT A WARNING. An outclassed magnet is never told it is too weak
	(DigService's over-tier grind); what the shaft does instead is crack the soil around
	the nuke in glowing orange and make it judder -- harder while nobody is yanking.

	Frames only, no uploaded images, like every other piece of HUD. Roblox has no curves,
	so the wavy band edges are rows of overlapping ovals rather than a real wave.

	This module only builds and moves frames. DetectorController owns the panel, the
	readout beside it, the REEL IN button and when any of it is up.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Stages = require(Shared.Config.Stages)
local Tuning = require(Shared.Config.Tuning)

local UIKit = require(script.Parent.UIKit)

local HaulShaft = {}

-- The deepest any signal can be buried: the top rarity at full jitter (DigService's
-- depth roll). The ruler reaches it, rounded up to a half metre so it ends on a tick.
local MAX_DEPTH_STUDS = Tuning.DIG_DEPTH_BASE
	+ (#Rarity.ORDER - 1) * Tuning.DIG_DEPTH_PER_RARITY
	+ Tuning.DIG_DEPTH_JITTER
HaulShaft.RULER_METRES = math.ceil(MAX_DEPTH_STUDS / Stages.STUDS_PER_METRE * 2) / 2

-- ── Geometry, in design pixels ──────────────────────────────────────────────────
-- Everything vertical is derived from the height build() is given; the width is the
-- shaft's own and fixed, because the art across it (channel, magnet, ruler) is.
local SKY_HEIGHT = 46 -- the surface line: the nuke's nose sits here at 0 m
local FLOOR_MARGIN = 72 -- the nose at full ruler depth still leaves the whole nuke in view
local BANDS = 5
local AXIS_X = 83 -- centre of the shaft channel, and of everything hung down it
local CHANNEL_WIDTH = 42
local NUKE_SIZE = Vector2.new(40, 62)
local MAGNET_TOP = 6
local CABLE_TOP = 22 -- tucked under the magnet's bend, so the cable reads as tied on
local TRAIL_PITCH = 9 -- one dot of the "where it has been" trail every this many px
local RULER_MAJOR, RULER_MINOR = 18, 9 -- tick lengths, whole and half metres

-- ── Colour ──────────────────────────────────────────────────────────────────────
local DARK = Color3.fromHex("120C08") -- what the soil darkens toward as it deepens
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
-- Stage 1's walls wear the camp apron's green on their lip (Scenery.wallCapPair); every
-- other stage caps its walls in its own floor colour, and the grass line follows suit.
local CAMP_GRASS = Color3.fromHex("5AA34A")
-- Only Stage 4 lays its ooze out on the ground (Scenery.scatterOozePools), so only its
-- soil carries a seam of it.
local OOZE_SEAM_STAGES = { [4] = true }
-- A floor darker than this (Stage 4's near-black) is lifted before banding, or all five
-- bands land on one black.
local MIN_SOIL_VALUE = 0.46
local CRACK_COLOR = Color3.fromHex("FF7A45")
local CABLE_COLOR = Color3.fromHex("1D1D1D")
local FRAME_COLOR = Color3.fromHex("1C140D")
local MAGNET_RED = UIKit.C.red
local MAGNET_TIP = UIKit.C.text

export type Shaft = {
	root: Frame,
	height: number,
	floorY: number,
	skyGradient: UIGradient,
	bands: { Frame },
	bumps: { { Frame } },
	pebbles: { { frame: Frame, light: boolean } },
	seam: { Frame },
	lip: { Frame },
	trail: Frame,
	cable: Frame,
	nuke: Frame,
	accentParts: { Frame },
	cracks: { Frame },
	stageId: number?,
	accent: Color3?,
	rng: Random,
}

export type Input = {
	-- Metres still to come up. nil when the server has not sent a depth, and the nuke
	-- falls back to climbing the full shaft on `progress` alone.
	toGo: number?,
	progress: number,
	strain: number, -- stages the soil outclasses the magnet (0 = rated)
	kick: number, -- 0..1, the per-yank jolt
	idle: boolean, -- no yank in the last moment: the soil is winning, judder harder
	now: number,
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

-- Crack paths around the nuke, in nuke-local pixels (nose at y=0, axis at x=20): two
-- up each flank, reaching out into the soil.
local CRACK_PATHS: { { Vector2 } } = {
	{ Vector2.new(-2, 6), Vector2.new(-10, 12), Vector2.new(-8, 20), Vector2.new(-18, 26) },
	{ Vector2.new(-2, 30), Vector2.new(-12, 34), Vector2.new(-14, 44) },
	{ Vector2.new(42, 10), Vector2.new(50, 6), Vector2.new(56, 14), Vector2.new(64, 12) },
	{ Vector2.new(42, 36), Vector2.new(50, 42), Vector2.new(48, 50), Vector2.new(58, 56) },
}

--- The nuke that climbs the shaft: a soft glow in the signal's colour, the capsule body
--- (the same slag-grey gradient as the dug-up crust), fins, a band in the signal's
--- colour and two crust scabs. Positioned by its nose (AnchorPoint 0.5, 0).
local function buildNuke(parent: Instance, z: number): (Frame, { Frame }, { Frame })
	local nuke = Instance.new("Frame")
	nuke.Name = "Nuke"
	nuke.AnchorPoint = Vector2.new(0.5, 0)
	nuke.Size = UDim2.fromOffset(NUKE_SIZE.X, NUKE_SIZE.Y)
	nuke.BackgroundTransparency = 1
	nuke.ZIndex = z
	nuke.Parent = parent

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

--- The magnet hanging over the shaft, poles DOWN at the nuke: the red horseshoe and
--- pale tips build/Shops' magnet prop leans on too, so it reads as "magnet" at a glance.
--- Built upside-down piece by piece, because a parent's Rotation does not turn its
--- children in Roblox UI.
local function buildMagnet(parent: Instance, z: number)
	local x = AXIS_X - 16.5
	box(parent, "MagnetBend", x, MAGNET_TOP, 33, 12, MAGNET_RED, z, UDim.new(0, 6))
	box(parent, "MagnetLegLeft", x, MAGNET_TOP + 6, 10, 16, MAGNET_RED, z)
	box(parent, "MagnetLegRight", x + 23, MAGNET_TOP + 6, 10, 16, MAGNET_RED, z)
	box(parent, "MagnetTipLeft", x, MAGNET_TOP + 20, 10, 6, MAGNET_TIP, z, UDim.new(0, 1))
	box(parent, "MagnetTipRight", x + 23, MAGNET_TOP + 20, 10, 6, MAGNET_TIP, z, UDim.new(0, 1))
end

--- Build the cut-away into `parent` at `position`, `width` fixed by the art and
--- `height` whatever the panel has. Uncoloured until paint() and setAccent().
function HaulShaft.build(parent: Instance, position: UDim2, height: number): Shaft
	local width = 166
	local floorY = height - FLOOR_MARGIN
	local root = Instance.new("Frame")
	root.Name = "SoilShaft"
	root.Position = position
	root.Size = UDim2.fromOffset(width, height)
	root.BackgroundColor3 = DARK
	root.BorderSizePixel = 0
	-- RECTANGULAR clipping (Roblox ignores UICorner when clipping). The radius is kept
	-- small enough that the square corners it leaves stay under the 3px frame stroke.
	root.ClipsDescendants = true
	root.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = root
	local stroke = Instance.new("UIStroke")
	stroke.Color = FRAME_COLOR
	stroke.Thickness = UIKit.Stroke.normal
	stroke.Parent = root

	local sky = box(root, "Sky", 0, 0, width, SKY_HEIGHT + 4, WHITE, 1)
	local skyGradient = Instance.new("UIGradient")
	skyGradient.Rotation = 90
	skyGradient.Parent = sky

	-- Five bands, each running from its own top edge to the shaft's floor, so a deeper
	-- band simply lies over the rest of the one above it. The wavy edge is a row of ovals
	-- in the band's colour straddling that top edge, alternately high and low.
	local rng = Random.new(3)
	local bandHeight = (height - SKY_HEIGHT) / BANDS
	local bands, bumps, pebbles = {}, {}, {}
	for k = 0, BANDS - 1 do
		local top = SKY_HEIGHT + k * bandHeight
		local band = box(root, "Band" .. k, 0, top, width, height - top, WHITE, 2 + k)
		table.insert(bands, band)
		local row = {}
		if k > 0 then
			for i = 0, 3 do
				local lift = if (i + k) % 2 == 0 then -6 else -3
				table.insert(row, box(band, "Wave", -14 + i * 48, lift, 60, 12, WHITE, 2 + k, OVAL))
			end
		end
		table.insert(bumps, row)
		for _ = 1, 3 do
			local r = 2.5 + rng:NextNumber() * 3.5
			local pebble = box(band, "Pebble", 6 + rng:NextNumber() * (width - 18), 8 + rng:NextNumber() * (bandHeight - 18), r * 2 + 3, r * 2, WHITE, 2 + k, OVAL)
			pebble.BackgroundTransparency = 0.4
			table.insert(pebbles, { frame = pebble, light = rng:NextNumber() > 0.5 })
		end
	end

	-- The ooze seam: three thin slanted runs across the middle band (Stage 4 only).
	local seam = {}
	local seamBand = bands[3]
	for i = 0, 2 do
		local run = box(seamBand, "OozeSeam", -6 + i * 58, bandHeight * 0.5 + (if i == 1 then -4 else 0), 62, 4, WHITE, 4, UDim.new(1, 0))
		run.Rotation = if i == 1 then 5 else -4
		run.Visible = false
		table.insert(seam, run)
	end

	local channel = box(root, "Channel", AXIS_X - CHANNEL_WIDTH / 2, SKY_HEIGHT + 4, CHANNEL_WIDTH, height, BLACK, 10)
	channel.BackgroundTransparency = 0.7

	-- The grass line and its tufts (little diamonds along the top edge).
	local lip = { box(root, "Grass", 0, SKY_HEIGHT - 4, width, 10, WHITE, 11) }
	for x = 0, width, 8 do
		local tuft = box(root, "Tuft", x, SKY_HEIGHT - 7, 6, 6, WHITE, 11)
		tuft.Rotation = 45
		table.insert(lip, tuft)
	end

	-- The ruler down the right edge: a tick every half metre, labelled every whole one.
	-- Metre m is where the nuke's NOSE sits with m metres still to come up.
	for i = 0, HaulShaft.RULER_METRES * 2 do
		local m = i / 2
		local y = SKY_HEIGHT + (m / HaulShaft.RULER_METRES) * (floorY - SKY_HEIGHT)
		local major = i % 2 == 0
		local len = if major then RULER_MAJOR else RULER_MINOR
		local tick = box(root, "Tick", width - len, y - 1, len, 2, WHITE, 12)
		tick.BackgroundTransparency = if major then 0.2 else 0.45
		if major then
			local label = Instance.new("TextLabel")
			label.Name = "TickLabel"
			label.AnchorPoint = Vector2.new(1, 0.5)
			label.Position = UDim2.fromOffset(width - len - 3, y)
			label.Size = UDim2.fromOffset(40, 14)
			label.BackgroundTransparency = 1
			label.Font = UIKit.Font.title
			label.TextSize = 11
			label.TextColor3 = WHITE
			label.TextTransparency = 0.15
			label.TextStrokeTransparency = 0.35
			label.TextXAlignment = Enum.TextXAlignment.Right
			label.Text = `{m} m`
			label.ZIndex = 12
			label.Parent = root
		end
	end

	-- The trail: a column of dots pinned to the shaft's floor, clipped to the stretch
	-- below the nuke, so it shortens as the nuke climbs instead of the dots crawling.
	local trail = Instance.new("Frame")
	trail.Name = "Trail"
	trail.AnchorPoint = Vector2.new(0.5, 1)
	trail.Position = UDim2.new(0, AXIS_X, 1, 0)
	trail.Size = UDim2.fromOffset(3, 0)
	trail.BackgroundTransparency = 1
	trail.ClipsDescendants = true
	trail.ZIndex = 13
	trail.Parent = root
	for i = 0, math.ceil(height / TRAIL_PITCH) do
		local dot = box(trail, "Dot", 0, 0, 3, 3, WHITE, 13, OVAL)
		dot.AnchorPoint = Vector2.new(0, 1)
		dot.Position = UDim2.new(0, 0, 1, -4 - i * TRAIL_PITCH)
		dot.BackgroundTransparency = 0.6
	end

	local cable = box(root, "Cable", AXIS_X - 1.5, CABLE_TOP, 3, 0, CABLE_COLOR, 13)
	buildMagnet(root, 15)
	local nuke, accentParts, cracks = buildNuke(root, 16)

	return {
		root = root,
		height = height,
		floorY = floorY,
		skyGradient = skyGradient,
		bands = bands,
		bumps = bumps,
		pebbles = pebbles,
		seam = seam,
		lip = lip,
		trail = trail,
		cable = cable,
		nuke = nuke,
		accentParts = accentParts,
		cracks = cracks,
		stageId = nil,
		accent = nil,
		rng = Random.new(),
	}
end

--- Recolour the cut-away in a stage's own soil, sky and grass. A no-op for the stage
--- it is already painted in, so it is safe to call on every state update.
function HaulShaft.paint(shaft: Shaft, stageId: number)
	if shaft.stageId == stageId then
		return
	end
	local def = Stages.get(stageId)
	if def == nil then
		return
	end
	shaft.stageId = stageId

	local floor = Color3.fromHex(def.color)
	local h, s, v = floor:ToHSV()
	local soil = if v < MIN_SOIL_VALUE then Color3.fromHSV(h, s * 0.9, MIN_SOIL_VALUE) else floor

	shaft.skyGradient.Color = ColorSequence.new(
		def.fogColor:Lerp(Color3.fromHex("7F8F78"), 0.45),
		def.fogColor:Lerp(Color3.fromHex("FFF7DC"), 0.35)
	)
	for k, band in shaft.bands do
		local c = soil:Lerp(DARK, 0.18 + 0.14 * (k - 1))
		band.BackgroundColor3 = c
		for _, bump in shaft.bumps[k] do
			bump.BackgroundColor3 = c
		end
	end
	local light, dark = soil:Lerp(WHITE, 0.2), soil:Lerp(BLACK, 0.6)
	for _, p in shaft.pebbles do
		p.frame.BackgroundColor3 = if p.light then light else dark
	end

	local seamOn = OOZE_SEAM_STAGES[stageId] == true
	local ooze = Color3.fromHex(def.ooze.bright)
	for _, run in shaft.seam do
		run.Visible = seamOn
		run.BackgroundColor3 = ooze
	end

	local grass = if stageId == 1 then CAMP_GRASS else floor:Lerp(WHITE, 0.1)
	for _, part in shaft.lip do
		part.BackgroundColor3 = grass
	end
end

--- The signal's colour on the nuke's band and glow. Cheap to call every tick.
function HaulShaft.setAccent(shaft: Shaft, color: Color3)
	if shaft.accent == color then
		return
	end
	shaft.accent = color
	for _, part in shaft.accentParts do
		part.BackgroundColor3 = color
	end
end

--- Move the nuke to where the haul is, every frame.
function HaulShaft.step(shaft: Shaft, input: Input)
	local nose
	if input.toGo then
		nose = SKY_HEIGHT + math.clamp(input.toGo / HaulShaft.RULER_METRES, 0, 1) * (shaft.floorY - SKY_HEIGHT)
	else
		nose = shaft.floorY + (SKY_HEIGHT - shaft.floorY) * math.clamp(input.progress, 0, 1)
	end

	-- The judder: the soil fighting an outclassed magnet (harder while it is winning),
	-- plus a small jolt on each yank so the click lands on the nuke too.
	local strain = math.clamp(input.strain, 0, 3)
	local rng = shaft.rng
	local jitter = (rng:NextNumber() - 0.5) * strain * (if input.idle then 1.4 else 0.5)
		+ (rng:NextNumber() - 0.5) * 3 * input.kick
	shaft.nuke.Position = UDim2.fromOffset(AXIS_X + jitter, nose)
	shaft.cable.Size = UDim2.fromOffset(3, math.max(0, nose - CABLE_TOP))
	shaft.trail.Size = UDim2.fromOffset(3, math.max(0, shaft.height - nose - NUKE_SIZE.Y))

	local cracked = strain > 0
	local glow = if cracked then 1 - (strain / 3) * (0.55 + 0.45 * math.sin(input.now * 14)) else 1
	for _, seg in shaft.cracks do
		seg.Visible = cracked
		seg.BackgroundTransparency = glow
	end
end

return HaulShaft
