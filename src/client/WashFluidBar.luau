--!strict
--[[
	WashFluidBar.luau — the wash bay's clean bar, painted whatever is in the hose.

	ONE WIDGET FOR BOTH QUESTIONS. The wash view used to answer "how clean is it" with a
	thin dark bar bottom-centre and "what am I spraying" with the fluid's name alone in
	the bottom-right corner. They are one piece now: a fat striped pill filled with the
	loaded fluid's own colour, the fluid's name and how many patches it has left sitting
	on the bar's top-left, and a bottle standing on the bar's left end that drains as the
	canister does. Picked from browser mockups (option 2, variant B).

	THE COLOUR IS THE FLUID. The fill and its stripes (the same colour a shade darker)
	are whatever is loaded, so a canister running dry mid-wash is SEEN rather than read:
	the bar fades to Plain Water blue, the bottle refills blue, "RAN DRY!" pops off the
	name. Each cleared patch that spends a charge floats a "-1" off the bottle's cork,
	and every patch that pops punches the whole bar.

	Frames only, like the rest of the HUD. Roblox clips to rectangles, so the two round
	things that have to clip -- the bar's pill and the bottle's body -- are CanvasGroups
	with a UICorner, which do clip to the rounded shape.

	A singleton, like WashReveal: there is one wash view. WashController mounts it on its
	canvas, feeds it every WashState payload and shows or hides it; the numbers are all
	the server's (`percentClean`, `liquidHeld`). The motion -- stripes crawling, the
	sparkle riding the fill's edge, the slosh -- runs on its own RenderStepped connection,
	and only while it is showing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Liquids = require(ReplicatedStorage.Shared.Config.Liquids)

local UIKit = require(script.Parent.UIKit)

local WashFluidBar = {}

-- The cartoon black every outline in the HUD uses (HudController's INK).
local INK = Color3.fromHex("1A1A1A")

local STYLE = {
	track = Color3.fromHex("2B2230"),
	stripeShade = 0.8, -- the stripes are the fluid's colour times this
	surfaceLift = 0.35, -- the liquid's top edge, this far toward white
	cork = Color3.fromHex("C98B4B"),
	dry = Color3.fromHex("FF5A4E"),
	water = Color3.fromHex(Liquids.DEFS[Liquids.WATER].color),
	valueFont = Enum.Font.LuckiestGuy,
	pillFont = Enum.Font.FredokaOne,
}

-- Design px. The bar is `size` inside a 4px ink stroke, so 600 x 50 on the canvas.
local BAR = {
	size = Vector2.new(592, 42),
	bottom = 26, -- the stroke's bottom edge, up off the screen's
	outline = 4,
	shadowDrop = 5,
	stripeEvery = 34, -- stripe pitch along the bar
	stripeWidth = 12,
	stripeSpeed = 48, -- px/s, crawling left to right
	shineInset = 10,
	shineHeight = 7,
	textSize = 29,
	textStroke = 3.5,
	-- LuckiestGuy draws high in its line box (CashController measured the same), so a
	-- "centred" label rides the top edge unless it is nudged down.
	textDrop = 3,
	spark = 40,
}

-- The bottle stands on the bar's left end, hanging off it by `position`.
local BOTTLE = {
	size = Vector2.new(64, 95),
	position = UDim2.fromOffset(-46, 58), -- its bottom-left, against the bar's top-left
	body = 54, -- the round body's diameter
	full = 6, -- the liquid's top, in body px, when the canister is full
	empty = 56, -- ... and when it is dry (below the body: nothing shows)
	slosh = 7, -- degrees
	sloshSpeed = 2.4,
	-- Three bubbles rising through the body on a staggered loop: x, diameter, delay.
	bubbles = { { 20, 5, 0 }, { 34, 4, 0.6 }, { 28, 3, 1.2 } },
	bubblePeriod = 1.8,
	bubbleFrom = 48,
	bubbleRise = 40,
}

local TAG = {
	position = UDim2.fromOffset(34, -6), -- its bottom-left, just above the bar
	height = 30,
	nameSize = 24,
	nameStroke = 3,
	countSize = 14,
	countHeight = 20,
	countPad = 9,
	gap = 8,
}

local FX = {
	punch = 0.06, -- the bar grows this much when a patch pops
	punchTime = 0.22,
	shake = 7, -- px, when the canister runs dry
	shakeTime = 0.38,
	floatRise = 48,
	floatTime = 1.05,
	floatSize = 26,
	spendAt = UDim2.fromOffset(-14, -40), -- over the bottle's cork
	dryAt = UDim2.fromOffset(134, -44), -- over the name
	twinkle = 0.9, -- seconds per half-cycle of the sparkle
	sparkClear = 6, -- px past the number's edge before the sparkle starts to grow back
	sparkFade = 20, -- px it takes to grow back to full size
}

type Bar = {
	root: Frame,
	punch: UIScale,
	fill: Frame,
	stripes: Frame,
	stripeBars: { Frame },
	shine: Frame,
	spark: Frame,
	star: Frame,
	starScale: UIScale,
	percent: TextLabel,
	textHalf: number, -- half the number's width, design px
	bottle: Frame,
	liquid: Frame,
	surface: Frame,
	bubbles: { Frame },
	tag: Frame,
	name: TextLabel,
	count: Frame,
	countText: TextLabel,

	-- What the server last said, and what is on screen easing toward it.
	uid: string?,
	patchCount: number,
	liquidId: string,
	held: number?,
	pct: number,
	shownPct: number,
	level: number,
	shownLevel: number,
	color: Color3,
	shownColor: Color3,
	clock: number,
	punchAt: number?,
	shakeAt: number?,
}

local current: Bar? = nil
local stepping: RBXScriptConnection? = nil
local listening = false

-- ── Building ────────────────────────────────────────────────────────────────────

local function frame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function round(f: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = f
end

local function ink(f: GuiObject, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = f
	return stroke
end

--- A round window its children are cut to. A plain Frame's ClipsDescendants is a
--- rectangle whatever its corners say; a CanvasGroup honours its UICorner.
local function roundClip(parent: Instance, name: string, size: UDim2, position: UDim2, z: number): CanvasGroup
	local group = Instance.new("CanvasGroup")
	group.Name = name
	group.Size = size
	group.Position = position
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.ZIndex = z
	round(group)
	group.Parent = parent
	return group
end

local function barPosition(): UDim2
	return UDim2.new(0.5, 0, 1, -(BAR.bottom + BAR.outline) - UIKit.safeInsets().bottom)
end

local function buildBottle(root: Frame): (Frame, Frame, Frame, { Frame })
	local bottle = frame(root, "Bottle", UDim2.fromOffset(BOTTLE.size.X, BOTTLE.size.Y), BOTTLE.position, INK, 7)
	bottle.AnchorPoint = Vector2.new(0, 1)
	bottle.BackgroundTransparency = 1

	local neck = frame(bottle, "Neck", UDim2.fromOffset(16, 13), UDim2.new(0.5, 0, 0, 26), STYLE.track, 1)
	neck.AnchorPoint = Vector2.new(0.5, 0)
	ink(neck, 3.5)

	local cork = frame(bottle, "Cork", UDim2.fromOffset(23, 15), UDim2.new(0.5, 0, 0, 13), STYLE.cork, 2)
	cork.AnchorPoint = Vector2.new(0.5, 0)
	local corkCorner = Instance.new("UICorner")
	corkCorner.CornerRadius = UDim.new(0, 4)
	corkCorner.Parent = cork
	ink(cork, 3)

	local bodySize = UDim2.fromOffset(BOTTLE.body, BOTTLE.body)
	local bodyAt = UDim2.new(0.5, 0, 1, -2)

	local back = frame(bottle, "Body", bodySize, bodyAt, STYLE.track, 3)
	back.AnchorPoint = Vector2.new(0.5, 1)
	round(back)

	local clip = roundClip(bottle, "BodyClip", bodySize, bodyAt, 4)
	clip.AnchorPoint = Vector2.new(0.5, 1)

	-- Far wider than the body, so the slosh can tilt it without a corner showing.
	local liquid = frame(clip, "Liquid", UDim2.fromOffset(BOTTLE.body * 2, BOTTLE.body * 1.5), UDim2.new(0.5, 0, 0, BOTTLE.full), STYLE.water, 1)
	liquid.AnchorPoint = Vector2.new(0.5, 0)
	local surface = frame(liquid, "Surface", UDim2.new(1, 0, 0, 4), UDim2.fromOffset(0, 0), STYLE.water, 1)

	local bubbles = {}
	for index, spec in BOTTLE.bubbles do
		local bubble = frame(clip, `Bubble{index}`, UDim2.fromOffset(spec[2], spec[2]), UDim2.fromOffset(spec[1], BOTTLE.bubbleFrom), Color3.new(1, 1, 1), 2)
		bubble.AnchorPoint = Vector2.new(0.5, 0.5)
		bubble.BackgroundTransparency = 1
		round(bubble)
		table.insert(bubbles, bubble)
	end

	local shine = frame(clip, "Shine", UDim2.fromOffset(5, 18), UDim2.fromOffset(14, 14), Color3.new(1, 1, 1), 3)
	shine.Rotation = 35
	shine.BackgroundTransparency = 0.5
	round(shine)

	local rim = frame(bottle, "Rim", bodySize, bodyAt, INK, 5)
	rim.AnchorPoint = Vector2.new(0.5, 1)
	rim.BackgroundTransparency = 1
	round(rim)
	ink(rim, 4)

	return bottle, liquid, surface, bubbles
end

local function build(canvas: Instance): Bar
	local root = frame(canvas, "CleanBar", UDim2.fromOffset(BAR.size.X, BAR.size.Y), barPosition(), INK, 1)
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	local punch = Instance.new("UIScale")
	punch.Name = "Punch"
	punch.Parent = root

	-- The hard drop shadow every cartoon card in the HUD stands on.
	local shadow = frame(root, "Shadow", UDim2.fromScale(1, 1), UDim2.fromOffset(0, BAR.shadowDrop), INK, 1)
	round(shadow)
	ink(shadow, BAR.outline)

	local track = frame(root, "Track", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), STYLE.track, 2)
	round(track)
	ink(track, BAR.outline)

	local clip = roundClip(root, "Clip", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), 3)
	local fill = frame(clip, "Fill", UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), STYLE.water, 1)
	fill.ClipsDescendants = true

	-- Diagonal stripes: tall thin bars turned 45 degrees, one every `stripeEvery`, in a
	-- strip one pitch wider than the bar at each end so sliding it by up to a pitch
	-- never shows a gap. The fill's own ClipsDescendants cuts them at the fill's edge.
	local stripes = frame(fill, "Stripes", UDim2.new(0, BAR.size.X + BAR.stripeEvery * 2, 1, 0), UDim2.fromOffset(-BAR.stripeEvery, 0), INK, 1)
	stripes.BackgroundTransparency = 1
	local stripeBars = {}
	local stripeLength = math.ceil(BAR.size.Y * 1.5)
	for index = 0, math.ceil((BAR.size.X + BAR.stripeEvery * 2) / BAR.stripeEvery) do
		local stripe = frame(stripes, "Stripe", UDim2.fromOffset(BAR.stripeWidth, stripeLength), UDim2.new(0, index * BAR.stripeEvery, 0.5, 0), STYLE.water, 1)
		stripe.AnchorPoint = Vector2.new(0.5, 0.5)
		stripe.Rotation = 45
		table.insert(stripeBars, stripe)
	end

	local shine = frame(fill, "Shine", UDim2.new(1, -BAR.shineInset * 2, 0, BAR.shineHeight), UDim2.fromOffset(BAR.shineInset, 5), Color3.new(1, 1, 1), 2)
	shine.BackgroundTransparency = 0.6
	round(shine)

	-- The sparkle riding the fill's leading edge: two crossed pills, ink under white.
	local spark = frame(root, "Spark", UDim2.fromOffset(BAR.spark, BAR.spark), UDim2.fromScale(0, 0.5), INK, 4)
	spark.AnchorPoint = Vector2.new(0.5, 0.5)
	spark.BackgroundTransparency = 1
	local star = frame(spark, "Star", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), INK, 1)
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.BackgroundTransparency = 1
	local starScale = Instance.new("UIScale")
	starScale.Parent = star
	for _, arm in { { 8, 34, INK, 1 }, { 34, 8, INK, 1 }, { 4, 28, Color3.new(1, 1, 1), 2 }, { 28, 4, Color3.new(1, 1, 1), 2 } } do
		local piece = frame(star, "Arm", UDim2.fromOffset(arm[1], arm[2]), UDim2.fromScale(0.5, 0.5), arm[3], arm[4])
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		round(piece)
	end

	local percent = UIKit.label(root, {
		name = "Percent",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromOffset(0, BAR.textDrop),
		font = STYLE.valueFont,
		textSize = BAR.textSize,
		color = Color3.new(1, 1, 1),
		xAlign = Enum.TextXAlignment.Center,
		text = "0% CLEAN",
		zIndex = 6,
		shadow = true,
	})
	local percentStroke = percent:FindFirstChildOfClass("UIStroke")
	if percentStroke then
		percentStroke.Thickness = BAR.textStroke
	end

	local bottle, liquid, surface, bubbles = buildBottle(root)

	local tag = frame(root, "Tag", UDim2.fromOffset(BAR.size.X, TAG.height), TAG.position, INK, 7)
	tag.AnchorPoint = Vector2.new(0, 1)
	tag.BackgroundTransparency = 1
	local name = UIKit.label(tag, {
		name = "Name",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromOffset(0, BAR.textDrop),
		font = STYLE.valueFont,
		textSize = TAG.nameSize,
		color = STYLE.water,
		text = "Plain Water",
		zIndex = 2,
		shadow = true,
	})
	local nameStroke = name:FindFirstChildOfClass("UIStroke")
	if nameStroke then
		nameStroke.Thickness = TAG.nameStroke
	end
	local count = frame(tag, "Count", UDim2.fromOffset(60, TAG.countHeight), UDim2.fromScale(0, 0.5), INK, 3)
	count.AnchorPoint = Vector2.new(0, 0.5)
	round(count)
	local countText = UIKit.label(count, {
		name = "Text",
		size = UDim2.fromScale(1, 1),
		font = STYLE.pillFont,
		textSize = TAG.countSize,
		color = Color3.new(1, 1, 1),
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		zIndex = 4,
	})

	return {
		root = root,
		punch = punch,
		fill = fill,
		stripes = stripes,
		stripeBars = stripeBars,
		shine = shine,
		spark = spark,
		star = star,
		starScale = starScale,
		percent = percent,
		textHalf = TextService:GetTextSize(percent.Text, BAR.textSize, STYLE.valueFont, Vector2.new(2000, 200)).X / 2,
		bottle = bottle,
		liquid = liquid,
		surface = surface,
		bubbles = bubbles,
		tag = tag,
		name = name,
		count = count,
		countText = countText,

		uid = nil,
		patchCount = 0,
		liquidId = Liquids.WATER,
		held = nil,
		pct = 0,
		shownPct = 0,
		level = 1,
		shownLevel = 1,
		color = STYLE.water,
		shownColor = STYLE.water,
		clock = 0,
		punchAt = nil,
		shakeAt = nil,
	}
end

-- ── Drawing ─────────────────────────────────────────────────────────────────────

local function paint(bar: Bar)
	local color = bar.shownColor
	local shade = Color3.new(color.R * STYLE.stripeShade, color.G * STYLE.stripeShade, color.B * STYLE.stripeShade)
	bar.fill.BackgroundColor3 = color
	for _, stripe in bar.stripeBars do
		stripe.BackgroundColor3 = shade
	end
	bar.liquid.BackgroundColor3 = color
	bar.surface.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), STYLE.surfaceLift)
	bar.name.TextColor3 = color
end

local function near(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.01
end

--- The name, and the pill with the charges in it sat just past the name's last letter.
local function setTag(bar: Bar, name: string, count: string)
	local bounds = Vector2.new(2000, 200)
	if bar.name.Text ~= name then
		bar.name.Text = name
	end
	bar.countText.Text = count
	local nameWidth = TextService:GetTextSize(name, TAG.nameSize, STYLE.valueFont, bounds).X
	local countWidth = TextService:GetTextSize(count, TAG.countSize, STYLE.pillFont, bounds).X
	bar.count.Size = UDim2.fromOffset(countWidth + TAG.countPad * 2, TAG.countHeight)
	bar.count.Position = UDim2.new(0, nameWidth + TAG.gap, 0.5, 0)
end

--- A word that rises off the bar and fades. Built by hand rather than with UIKit.label,
--- whose outline and shadow do not fade with TextTransparency.
local function float(bar: Bar, text: string, at: UDim2, color: Color3)
	local label = Instance.new("TextLabel")
	label.Name = "Float"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(220, FX.floatSize + 10)
	label.Position = at
	label.Font = STYLE.valueFont
	label.TextSize = FX.floatSize
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	label.Text = text
	label.ZIndex = 9
	local stroke = ink(label, 3)
	label.Parent = bar.root

	local rise = TweenInfo.new(FX.floatTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fade = TweenInfo.new(FX.floatTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(label, rise, { Position = at - UDim2.fromOffset(0, FX.floatRise) }):Play()
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	task.delay(FX.floatTime, function()
		label:Destroy()
	end)
end

local function step(dt: number)
	local bar = current
	if bar == nil then
		return
	end
	bar.clock += dt
	local clock = bar.clock

	-- Eased toward the server's ten-hertz numbers, so the fill glides between them.
	bar.shownPct += (bar.pct - bar.shownPct) * (1 - math.exp(-dt * 10))
	bar.shownLevel += (bar.level - bar.shownLevel) * (1 - math.exp(-dt * 6))
	if bar.shownColor ~= bar.color then
		bar.shownColor = if near(bar.shownColor, bar.color) then bar.color else bar.shownColor:Lerp(bar.color, 1 - math.exp(-dt * 8))
		paint(bar)
	end

	local pct = bar.shownPct
	bar.fill.Size = UDim2.fromScale(pct, 1)
	bar.shine.Visible = pct * BAR.size.X > BAR.shineInset * 2 + 8
	bar.stripes.Position = UDim2.fromOffset(-BAR.stripeEvery + (clock * BAR.stripeSpeed) % BAR.stripeEvery, 0)
	local text = `{math.floor(pct * 100 + 0.5)}% CLEAN`
	if bar.percent.Text ~= text then
		bar.percent.Text = text
		bar.textHalf = TextService:GetTextSize(text, BAR.textSize, STYLE.valueFont, Vector2.new(2000, 200)).X / 2
	end

	-- THE SPARKLE SHRINKS AWAY WHILE IT PASSES BEHIND THE NUMBER. Drawn under the text,
	-- it still shows through the gaps between the letters, where it reads as a stray
	-- apostrophe ("47%'CLEAN") rather than a sparkle.
	local clear = math.abs(pct - 0.5) * BAR.size.X - bar.textHalf - FX.sparkClear
	local away = math.clamp(clear / FX.sparkFade, 0, 1)
	bar.spark.Visible = away > 0 and pct > 0.02 and pct < 0.995
	bar.spark.Position = UDim2.fromScale(pct, 0.5)
	local twinkle = (math.sin(clock * math.pi / FX.twinkle) + 1) / 2
	bar.star.Rotation = 45 * twinkle
	bar.starScale.Scale = (0.75 + 0.35 * twinkle) * away

	local scale = 1
	local punchAt = bar.punchAt
	if punchAt then
		local t = clock - punchAt
		if t < FX.punchTime then
			scale = 1 + FX.punch * math.sin(math.pi * t / FX.punchTime)
		else
			bar.punchAt = nil
		end
	end
	bar.punch.Scale = scale

	local surfaceY = BOTTLE.full + (1 - bar.shownLevel) * (BOTTLE.empty - BOTTLE.full)
	bar.liquid.Position = UDim2.new(0.5, 0, 0, surfaceY)
	bar.liquid.Rotation = math.sin(clock * BOTTLE.sloshSpeed) * BOTTLE.slosh
	for index, bubble in bar.bubbles do
		local spec = BOTTLE.bubbles[index]
		local phase = ((clock + spec[3]) % BOTTLE.bubblePeriod) / BOTTLE.bubblePeriod
		local y = BOTTLE.bubbleFrom - phase * BOTTLE.bubbleRise
		bubble.Position = UDim2.fromOffset(spec[1], y)
		local alpha = if phase < 0.2 then phase / 0.2 else (1 - phase) / 0.8
		bubble.BackgroundTransparency = if y > surfaceY + 4 then 1 - 0.6 * alpha else 1
	end

	local dx = 0
	local shakeAt = bar.shakeAt
	if shakeAt then
		local t = clock - shakeAt
		if t < FX.shakeTime then
			dx = math.sin(t * 55) * FX.shake * (1 - t / FX.shakeTime)
		else
			bar.shakeAt = nil
		end
	end
	bar.bottle.Position = BOTTLE.position + UDim2.fromOffset(dx, 0)
	bar.tag.Position = TAG.position + UDim2.fromOffset(dx, 0)
end

-- ── API ─────────────────────────────────────────────────────────────────────────

--- Build the bar onto the wash view's canvas, replacing any earlier one (the wash GUI
--- is rebuilt if a respawn took it). Hidden until `show`.
function WashFluidBar.mount(canvas: Instance)
	local old = current
	if old then
		old.root:Destroy()
	end
	current = build(canvas)
	if not listening then
		listening = true
		-- Registered once: UIKit's listeners live for the whole game, and this one
		-- always moves whichever bar is current.
		UIKit.onScaleChanged(function()
			local bar = current
			if bar and bar.root.Parent then
				bar.root.Position = barPosition()
			end
		end)
	end
end

--- Feed it a WashState payload. Every number on it is the server's; what this adds is
--- noticing the moments between two payloads -- a patch popped, a charge was spent,
--- the canister ran dry -- and making each one visible.
function WashFluidBar.update(payload: any)
	local bar = current
	if bar == nil or type(payload) ~= "table" then
		return
	end

	local id = if type(payload.liquidId) == "string" then payload.liquidId else Liquids.WATER
	local held: number? = if type(payload.liquidHeld) == "number" then payload.liquidHeld else nil
	local def = Liquids.DEFS[id]
	local water = id == Liquids.WATER or held == nil
	local patchCount = if type(payload.patches) == "table" then #payload.patches else 0
	local color = if type(payload.liquidColor) == "string" then Color3.fromHex(payload.liquidColor) else STYLE.water

	bar.pct = math.clamp(tonumber(payload.percentClean) or 0, 0, 1)
	bar.level = if water or def == nil or def.charges <= 0 then 1 else math.clamp((held :: number) / def.charges, 0, 1)
	bar.color = color

	if payload.uid ~= bar.uid then
		-- A new session: straight to its numbers, nothing to celebrate yet.
		bar.uid = payload.uid
		bar.shownPct = bar.pct
		bar.shownLevel = bar.level
		bar.shownColor = color
		bar.punchAt = nil
		bar.shakeAt = nil
		paint(bar)
	else
		if patchCount < bar.patchCount then
			bar.punchAt = bar.clock
		end
		local before = bar.held
		if held ~= nil and before ~= nil and id == bar.liquidId and held < before then
			float(bar, "-1", FX.spendAt, bar.shownColor)
		elseif id ~= bar.liquidId and id == Liquids.WATER and bar.liquidId ~= Liquids.WATER then
			-- The last charge went and the hose fell back to water in the same push.
			float(bar, "-1", FX.spendAt, bar.shownColor)
			float(bar, "RAN DRY!", FX.dryAt, STYLE.dry)
			bar.shakeAt = bar.clock
		end
	end
	bar.patchCount = patchCount
	bar.liquidId = id
	bar.held = held

	local name = if type(payload.liquidName) == "string" then payload.liquidName elseif def then def.name else "Plain Water"
	setTag(bar, name, if water then "\u{221E} FREE" else `{held} LEFT`)
end

--- Show or hide it, and run the motion only while it shows. Hiding also forgets the
--- session, so the next payload after it snaps rather than easing from stale numbers.
function WashFluidBar.show(visible: boolean)
	local bar = current
	if bar == nil then
		return
	end
	bar.root.Visible = visible
	if visible then
		if stepping == nil then
			stepping = RunService.RenderStepped:Connect(step)
		end
		step(0)
	else
		bar.uid = nil
		local connection = stepping
		if connection then
			connection:Disconnect()
			stepping = nil
		end
	end
end

return WashFluidBar
