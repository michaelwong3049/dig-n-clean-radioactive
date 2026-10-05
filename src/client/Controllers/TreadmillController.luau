--[[
	TreadmillController.lua — the belt you are standing on, and what it is buying you.

	TWO JOBS, AND THEY ARE DELIBERATELY BOTH SMALL:

	  1. THE BAR. While you are training, a big blue bar floats above the hotbar, with
	     no card behind it: the Speed you have against what the next walk-speed point
	     needs, your walk speed and roughly how long until it goes up, and what the next
	     belt costs. Every Speed push floats a shoe and "+10" off a random spot around
	     the bar, and filling it floats "Walk speed 35!". Levels are never named on
	     screen: what the player hears about is walk speed. It pops in on arrival and out
	     on departure. It is drawn from SpeedController's copy of SpeedState — the same
	     number the HUD badge counts, so the two can never disagree — and computes no
	     part of the curve itself.

	  2. THE MACHINE. Every belt near the camera scrolls its chevrons and turns its
	     rollers all the time. All of it is LOCAL: the parts moved here are cosmetic
	     children of a server-built model (see build/Plots.buildTreadmill — the Belt
	     part itself, the one thing a service reads, is never touched). The runner's
	     run-on-the-spot animation is NOT here: TreadmillService plays it on the server
	     so every player sees it, not just the runner.

	WHY THE CARD IS A SCREEN PANEL AND NOT A BILLBOARD, when LiquidController's
	readout is the opposite: what is loaded in your hose is a fact about a machine on
	YOUR plot, so the machine can answer for it. Training is not — any belt on any base
	trains whoever is standing on it, at their own rung (TreadmillService's header), so
	the numbers here belong to the player rather than to the plot. The console's own
	world billboard keeps showing its OWNER's walk speed, exactly as the luck button
	shows its owner's multiplier, and the two never claim to be the same thing.

	3. THE HINT. No spotlight walkthrough: the belt is usable straight away, and while
	   you train a small card above the bar (the walkthrough's dark/amber skin) says what
	   it is for ("Gain permanent walk speed by leveling up your speed"), until its X
	   reports it seen. A LOCKED machine (`Locked` attribute,
	   build/Plots) stands still: its belt is not scrolled.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Artwork = require(script.Parent.Parent.HudArtwork)
local UIKit = require(script.Parent.Parent.UIKit)
local Speed = require(script.Parent.SpeedController)
local RobuxButton = require(script.Parent.Parent.RobuxButton)

local Treadmill = {}

--- Belt speed in studs/sec, purely cosmetic. Fast enough to read as "running", slow
--- enough not to strobe against the slat pitch at 60fps.
local BELT_SPEED = 9

--- Belts further than this from the camera are left still. Far enough that the one
--- across the plot you are looking at runs, near enough that the other five bases in
--- the ring are not all scrolling for nobody.
local ANIM_RANGE = 90
local RANGE_REFRESH = 0.5

local ui: any = {}
local shown = false

-- ── The first-use hint ───────────────────────────────────────────────────

--- The treadmill used to open a full-screen spotlight walkthrough (LockerTutorial)
--- the first time the player walked up to it. Now the belt is simply usable, and the
--- explanation is a small card above the bar while they train. It stays while
--- SpeedState's `tutorial` says it is owed; its X reports it seen, which retires it
--- for good (and, locally, at once, without waiting for the next push).
local actionRemote: any = nil
local hintDismissed = false

local function hintWanted(): boolean
	local view = Speed.view()
	return not hintDismissed and view ~= nil and view.tutorial == true
end

local function dismissHint()
	if hintDismissed then
		return
	end
	hintDismissed = true
	if ui.hint then
		ui.hint.Visible = false
	end
	actionRemote:FireServer({ action = "tutorialSeen", id = "treadmill" })
end

-- ── The bar ───────────────────────────────────────────────────────────────

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

-- The speed badge's palette (SpeedController), so the bar reads as the same system.
local STYLE = {
	trough = Color3.fromHex("0F2F66"),
	fillTop = Color3.fromHex("5CC2FF"),
	fillBottom = Color3.fromHex("1C8CF0"),
	caption = Color3.fromHex("DDF3FF"),
	gain = Color3.fromHex("8AD4FF"),
	walkUp = Color3.fromHex("FFE45C"),
	valueFont = Enum.Font.GothamBlack,
	bodyFont = Enum.Font.GothamBlack,
}

-- The first-use explainer card wears the walkthrough's colours (client/LockerTutorial).
local HINT_TEXT = "Gain permanent walk speed by leveling up your speed"
local HINT_SKIN = {
	card = Color3.fromHex("22272C"),
	amber = Color3.fromHex("F2A93B"),
}

-- Design px. Nothing sits behind any of it, so every line of text wears a heavier ink
-- outline to read against the floor, the grass or the sky.
local LAYOUT = {
	barW = 400,
	barH = 36,
	outline = 4,
	shadowDrop = 5,
	needTextSize = 20,
	-- The walk-speed line sits just ABOVE the bar (negative: the footprint's top edge
	-- is the bar's top edge, which the popups are placed against).
	walkTop = -26,
	-- The explainer card, just above the walk-speed line.
	hintGap = 6,
	hintH = 30,
	hintPadX = 16,
	hintTextSize = 15,
	hintClose = 22, -- the X badge on its top-right corner
	height = 52,
	stripeGap = 22, -- px between the fill's diagonal hazard stripes
	stripeW = 9,
	stripeSpeed = 30, -- px/sec the stripes crawl along the fill
	textStroke = 2.5,
	shoe = 28,
	gainTextSize = 22,
	gainEvery = 0.1, -- seconds between gain popups while the belt runs
	-- The 2x Speed pass button, off the bar's right end and centred on it.
	passGap = 10,
	passW = 100,
	passH = 40,
}

local ROUND = UDim.new(0.5, 0)
-- The bar itself is squared off: just enough corner that the ink outline doesn't alias.
local SQUARE = UDim.new(0, 3)
local POP_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PUNCH_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--- "45s", "3m 20s", "1h 05m" — how long the belt still has to run for the next walk
--- speed point.
local function formatEta(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s < 60 then
		return `{s}s`
	elseif s < 3600 then
		return string.format("%dm %02ds", s // 60, s % 60)
	end
	return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
end

local function blob(parent: Instance, name: string, rect: { number }, color: Color3, zIndex: number, radius: UDim, stroke: number?): Frame
	local frame = UIKit.panel(parent, {
		name = name,
		position = UDim2.fromOffset(rect[1], rect[2]),
		size = UDim2.fromOffset(rect[3], rect[4]),
		color = color,
		transparency = 0,
		cornerRadius = radius,
		strokeColor = INK,
		strokeThickness = stroke or 0,
		zIndex = zIndex,
	})
	return frame
end

local function text(parent: Instance, name: string, rect: { number }, props: any): TextLabel
	local label = UIKit.label(parent, {
		name = name,
		position = UDim2.fromOffset(rect[1], rect[2]),
		size = UDim2.fromOffset(rect[3], rect[4]),
		font = props.font or STYLE.bodyFont,
		textSize = props.textSize,
		color = props.color or WHITE,
		xAlign = props.xAlign or Enum.TextXAlignment.Left,
		shadow = false,
		text = props.text or "",
		zIndex = props.zIndex or 5,
	})
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = props.stroke or LAYOUT.textStroke
	end
	return label
end

local function build(): Frame?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "TreadmillCard"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	ui.screen = screen

	-- 1280x720 design pixels on the shared canvas, like every other HUD surface.
	local canvas = UIKit.canvas(screen)

	-- Bottom centre, sat above the hotbar. The player is looking down the belt while
	-- this is up, so it wants to be in the middle rather than off in the instrument
	-- column where the rad meter lives. An invisible footprint holds the bar, its lines
	-- and the popups, so one UIScale pops the lot. Its top edge IS the bar's top edge.
	local L = LAYOUT
	local root = Instance.new("Frame")
	root.Name = "SpeedBar"
	root.Size = UDim2.fromOffset(L.barW, L.height)
	root.Position = UDim2.new(0.5, 0, 1, -UIKit.Dock.VITALS_CLEAR)
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = canvas
	ui.panel = root
	ui.scale = Instance.new("UIScale")
	ui.scale.Parent = root

	-- The hard shadow is the whole outlined bar dropped a few px, so it shows under the
	-- ink outline rather than hiding inside it.
	blob(root, "BarShadow", { 0, L.shadowDrop, L.barW, L.barH }, INK, 2, SQUARE, L.outline)
	local trough = blob(root, "Trough", { 0, 0, L.barW, L.barH }, STYLE.trough, 3, SQUARE, L.outline)
	ui.punch = Instance.new("UIScale")
	ui.punch.Parent = trough

	-- The fill is white under a top-to-bottom gradient, with a glassy shine along its top.
	ui.fill = blob(trough, "Fill", { 0, 0, 0, L.barH }, WHITE, 4, SQUARE)
	ui.fill.Size = UDim2.fromScale(0, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(STYLE.fillTop, STYLE.fillBottom)
	gradient.Rotation = 90
	gradient.Parent = ui.fill
	ui.shine = blob(ui.fill, "Shine", { 8, 5, 0, 9 }, WHITE, 5, ROUND)
	ui.shine.Size = UDim2.new(1, -16, 0, 9)
	ui.shine.BackgroundTransparency = 0.55

	-- Diagonal stripes across the fill. Rotated frames ignore ClipsDescendants, so they
	-- live in a CanvasGroup (which does clip them) laid out at the full bar width: the
	-- fill grows over them rather than squashing them.
	local stripes = Instance.new("CanvasGroup")
	stripes.Name = "Stripes"
	stripes.Size = UDim2.fromScale(1, 1)
	stripes.BackgroundTransparency = 1
	stripes.ZIndex = 5
	stripes.Parent = ui.fill
	local corner = Instance.new("UICorner")
	corner.CornerRadius = SQUARE
	corner.Parent = stripes
	-- The stripes ride on a holder that slides one gap and wraps, so they crawl forever.
	ui.stripes = Instance.new("Frame")
	ui.stripes.Name = "Holder"
	ui.stripes.Size = UDim2.fromScale(1, 1)
	ui.stripes.BackgroundTransparency = 1
	ui.stripes.Parent = stripes
	for x = -L.barH, L.barW + L.barH + L.stripeGap, L.stripeGap do
		local stripe = Instance.new("Frame")
		stripe.Name = "Stripe"
		stripe.AnchorPoint = Vector2.new(0.5, 0.5)
		stripe.Position = UDim2.fromOffset(x, L.barH / 2)
		stripe.Size = UDim2.fromOffset(L.stripeW, L.barH * 2)
		stripe.Rotation = 35
		stripe.BackgroundColor3 = WHITE
		stripe.BackgroundTransparency = 0.78
		stripe.BorderSizePixel = 0
		stripe.ZIndex = 5
		stripe.Parent = ui.stripes
	end

	ui.need = text(trough, "Need", { 0, 0, L.barW, L.barH }, {
		font = STYLE.valueFont,
		textSize = L.needTextSize,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 6,
	})

	ui.walk = text(root, "Walk", { 4, L.walkTop, L.barW - 8, 22 }, {
		textSize = 18,
		xAlign = Enum.TextXAlignment.Center,
	})

	-- The explainer, on a small card in the walkthrough's skin (client/LockerTutorial):
	-- dark fill, amber outline, an X on its top-right corner to put it away for good.
	local hintW = TextService:GetTextSize(HINT_TEXT, L.hintTextSize, STYLE.bodyFont, Vector2.new(1000, 100)).X
		+ 2 * L.hintPadX
	local hint = Instance.new("Frame")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.fromOffset(L.barW / 2, L.walkTop - L.hintGap)
	hint.Size = UDim2.fromOffset(hintW, L.hintH)
	hint.BackgroundColor3 = HINT_SKIN.card
	hint.BorderSizePixel = 0
	hint.Visible = false
	hint.ZIndex = 6
	hint.Parent = root
	local hintCorner = Instance.new("UICorner")
	hintCorner.CornerRadius = UDim.new(0, 10)
	hintCorner.Parent = hint
	local hintStroke = Instance.new("UIStroke")
	hintStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	hintStroke.Color = HINT_SKIN.amber
	hintStroke.Thickness = 2
	hintStroke.Parent = hint
	ui.hint = hint
	text(hint, "Body", { 0, 0, hintW, L.hintH }, {
		textSize = L.hintTextSize,
		xAlign = Enum.TextXAlignment.Center,
		stroke = 1.5,
		text = HINT_TEXT,
		zIndex = 7,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -2, 0, 2)
	close.Size = UDim2.fromOffset(L.hintClose, L.hintClose)
	close.BackgroundColor3 = UIKit.House.close
	close.AutoButtonColor = true
	close.Font = UIKit.House.font
	close.Text = "X"
	close.TextSize = 13
	close.TextColor3 = WHITE
	close.ZIndex = 8
	close.Parent = hint
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = ROUND
	closeCorner.Parent = close
	local closeStroke = Instance.new("UIStroke")
	closeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	closeStroke.Color = UIKit.House.ink
	closeStroke.Thickness = 2
	closeStroke.Parent = close
	close.Activated:Connect(dismissHint)

	-- The 2x Speed pass (Config/GamePasses: training x2) right where it pays off, on
	-- request. Purple with its Robux price; a grey OWNED once bought.
	local pass = RobuxButton.pass(root, "speed", "2x Speed")
	pass.button.Name = "SpeedPass"
	pass.button.Position = UDim2.fromOffset(L.barW + L.passGap, (L.barH - L.passH) / 2)
	pass.button.Size = UDim2.fromOffset(L.passW, L.passH)

	return root
end

local function ensure()
	if ui.panel == nil or ui.panel.Parent == nil then
		build()
	end
end

--- Repaint from the latest readout and the locally counted Speed. Every frame while the
--- bar is up, so the fill and the numbers run with the badge's counter. The bar is the
--- way to the next walk-speed point; levels stay internal and are never named here.
local function paint()
	local view = Speed.view()
	if view == nil or ui.panel == nil then
		return
	end
	local points = Speed.shownPoints()

	local progress = 1
	if view.nextReq == nil then
		-- No top level any more (Config/Treadmill), so this is only a readout that has
		-- not arrived whole. Show the total rather than a bar to nowhere.
		ui.walk.Text = `Walk Speed {view.walk}`
		ui.need.Text = `{Speed.format(points)} Speed`
	else
		local from, to = view.current or 0, view.nextReq or 1
		-- The fill glides on the unstepped count; only the number steps.
		progress = math.clamp((Speed.smoothPoints() - from) / math.max(to - from, 1), 0, 1)
		local eta = if view.rate > 0 then `  |  {view.walk + 1} in {formatEta((to - points) / view.rate)}` else ""
		ui.walk.Text = `Walk Speed {view.walk}{eta}`
		-- Counted from 0 each level: Speed earned into THIS level over what it costs,
		-- never the lifetime total.
		ui.need.Text = `{Speed.format(math.max(points - from, 0))} / {Speed.format(to - from)}`
	end
	ui.hint.Visible = hintWanted()
	ui.fill.Size = UDim2.fromScale(progress, 1)
	-- The shine is inset 8 px each side, so a sliver of fill would turn it inside out.
	ui.shine.Visible = progress * LAYOUT.barW > 28
	local gap = LAYOUT.stripeGap
	ui.stripes.Position = UDim2.fromOffset((os.clock() * LAYOUT.stripeSpeed) % gap - gap, 0)
end

-- ── The popups ────────────────────────────────────────────────────────────

local sinceGain = 0

--- The "+10"s ride a billboard on the runner's own body. They cycle through these
--- fixed spots (billboard px, centre-anchored) in order, so they read as a steady
--- pattern around the torso rather than a spray.
local GAIN_W, GAIN_H = 240, 260
local GAIN_SPOTS = {
	Vector2.new(60, 70),
	Vector2.new(180, 110),
	Vector2.new(70, 150),
	Vector2.new(170, 190),
	Vector2.new(55, 220),
	Vector2.new(185, 60),
}
local gainIndex = 0
local gainBoard: BillboardGui? = nil

--- The billboard on the local character, rebuilt after a respawn.
local function gainHost(): BillboardGui?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return nil
	end
	if gainBoard and gainBoard.Parent == root then
		return gainBoard
	end
	if gainBoard then
		gainBoard:Destroy()
	end
	local board = Instance.new("BillboardGui")
	board.Name = "SpeedGains"
	board.Size = UDim2.fromOffset(GAIN_W, GAIN_H)
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.ResetOnSpawn = false
	board.Adornee = root
	board.Parent = root
	gainBoard = board
	return board
end

--- Grow in, rise `rise` px over `life` seconds, fade out for the last stretch, then go.
--- Every text, its outline and every picture inside fades together.
local function float(popup: GuiObject, rise: number, life: number)
	local grow = Instance.new("UIScale")
	grow.Scale = 0.4
	grow.Parent = popup
	TweenService:Create(grow, PUNCH_TWEEN, { Scale = 1 }):Play()
	TweenService:Create(popup, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = popup.Position - UDim2.fromOffset(0, rise),
	}):Play()
	task.delay(life * 0.6, function()
		local parts = popup:GetDescendants()
		table.insert(parts, popup)
		for _, part in parts do
			if part:IsA("TextLabel") then
				TweenService:Create(part, FADE_TWEEN, { TextTransparency = 1 }):Play()
			elseif part:IsA("UIStroke") then
				TweenService:Create(part, FADE_TWEEN, { Transparency = 1 }):Play()
			elseif part:IsA("ImageLabel") then
				TweenService:Create(part, FADE_TWEEN, { ImageTransparency = 1 }):Play()
			end
		end
		task.wait(FADE_TWEEN.Time)
		popup:Destroy()
	end)
end

--- A shoe and "+10" or "+11" popping on the next spot around the runner's body. A steady
--- stream of them while training. Each shows what the belt pays per popup (so +10 on
--- the Scrap Belt, bigger on faster belts), randomly bumped 10% for variety.
local function popGain(rate: number)
	local L = LAYOUT
	local amount = rate * L.gainEvery * (if math.random() < 0.5 then 1 else 1.1)
	local label = `+{Speed.format(amount)}`
	local textW = TextService:GetTextSize(label, L.gainTextSize, STYLE.valueFont, Vector2.new(400, 60)).X + 6
	local width = L.shoe + 2 + textW
	local host = gainHost()
	if host == nil then
		return
	end
	gainIndex = gainIndex % #GAIN_SPOTS + 1
	local spot = GAIN_SPOTS[gainIndex]

	local popup = Instance.new("Frame")
	popup.Name = "GainPopup"
	popup.Size = UDim2.fromOffset(width, 32)
	popup.Position = UDim2.fromOffset(spot.X, spot.Y)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundTransparency = 1
	popup.ZIndex = 8
	popup.Parent = host

	local shoe = Artwork.picture(popup, "Shoe", Artwork.IMAGE.speedShoe, L.shoe, WHITE)
	shoe.Position = UDim2.fromOffset(0, (32 - L.shoe) / 2)
	shoe.ZIndex = 8
	text(popup, "Amount", { L.shoe + 2, 0, textW, 32 }, {
		font = STYLE.valueFont,
		textSize = L.gainTextSize,
		color = STYLE.gain,
		text = label,
		zIndex = 9,
	})
	float(popup, 10, 0.7)
end

--- The bar just filled: "Walk speed 35!" over its middle, and a punch on the bar.
local function popWalkUp(walk: number)
	local L = LAYOUT
	local popup = text(ui.panel, "WalkUpPopup", { L.barW / 2, -30, 360, 40 }, {
		font = STYLE.valueFont,
		textSize = 30,
		color = STYLE.walkUp,
		xAlign = Enum.TextXAlignment.Center,
		text = `Walk Speed {walk}!`,
		stroke = 3.5,
		zIndex = 10,
	})
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Rotation = -6
	float(popup, 44, 1.6)

	ui.punch.Scale = 1.06
	TweenService:Create(ui.punch, PUNCH_TWEEN, { Scale = 1 }):Play()
end

local function show(visible: boolean)
	ensure()
	if ui.panel == nil or visible == shown then
		return
	end
	shown = visible
	if visible then
		paint()
		ui.panel.Visible = true
		ui.scale.Scale = 0.6
		TweenService:Create(ui.scale, POP_IN, { Scale = 1 }):Play()
	else
		-- Destroy nothing: the card comes back every time the player steps on, which
		-- for an AFK grind may be hundreds of times a session.
		TweenService:Create(ui.scale, POP_OUT, { Scale = 0 }):Play()
		task.delay(POP_OUT.Time, function()
			if not shown and ui.panel then
				ui.panel.Visible = false
			end
		end)
	end
end

-- ── The machine ───────────────────────────────────────────────────────────
--
-- EVERY BELT IN RANGE RUNS, ALL THE TIME. It used to scroll only the belt the local
-- player was training on; on request the tread now moves on every treadmill near the
-- camera, so a base reads as a working machine whether or not anyone is on it. Still
-- purely local and purely cosmetic -- the `Belt` part a service reads is never moved.

--- One belt, resolved into the terms the scroll needs, captured once per model:
---
---   travel   the belt's own +Z in WORLD space. Every plot in the ring is yawed to face
---            the centre, so there is no shared axis to hardcode.
---   start    the world point at the belt's -Z end, which distances are measured from.
---   length   the belt's own length, and therefore the period of the whole pattern.
---
--- Each chevron keeps `along` (how far down the belt it started) and `lateral` (its
--- offset across and above the belt, which never changes). Scrolling is then "advance
--- `along`, wrap it modulo `length`, rebuild the position" — the chevron cannot walk
--- off the end of the belt, because the wrap is in belt space.
---
--- IT IS NOT `home * CFrame.new(0, 0, -d)`. That offsets each part along its OWN axis,
--- and the two arms of a chevron are yawed ~53 degrees apart — so instead of the
--- pattern moving down the belt, every chevron slid apart into a diagonal streak.
type Machine = {
	slats: { { part: BasePart, home: CFrame, along: number, lateral: Vector3 } },
	rollers: { { part: BasePart, home: CFrame } },
	travel: Vector3,
	start: Vector3,
	length: number,
	centre: Vector3,
}

--- Resolved machines, by model. Weak keys: a plot rebuilt mid-session drops its old
--- model and this lets go of it.
local machines: { [Instance]: Machine } = setmetatable({}, { __mode = "k" }) :: any
--- The ones currently near enough to animate, refreshed every RANGE_REFRESH seconds.
local active: { Machine } = {}
local sinceRefresh = math.huge
--- How far the belt surface has run, unwrapped. One clock for every belt: they all
--- run at the same speed, so there is nothing per-machine to keep.
local travelled = 0

local function resolve(model: Instance): Machine?
	local belt = model:FindFirstChild("Belt", true)
	if belt == nil or not belt:IsA("BasePart") then
		return nil -- not streamed in yet, or a world built before the belt existed
	end
	-- LookVector is the part's -Z, so negating it gives the +Z the chevrons scroll
	-- toward: backwards under a runner who is facing -Z, which is the way a real belt
	-- moves. Size.Z is the long axis because the builder sizes it {width, _, length}.
	local travel = -belt.CFrame.LookVector
	local length = belt.Size.Z
	local start = belt.Position - travel * (length / 2)
	local machine: Machine = {
		slats = {},
		rollers = {},
		travel = travel,
		start = start,
		length = length,
		centre = belt.Position,
	}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Name == "Slat" then
				local rel = part.Position - start
				local along = rel:Dot(travel)
				table.insert(machine.slats, { part = part, home = part.CFrame, along = along, lateral = rel - travel * along })
			elseif part.Name == "Roller" then
				table.insert(machine.rollers, { part = part, home = part.CFrame })
			end
		end
	end
	if #machine.slats == 0 then
		return nil -- slats still streaming in; try again on the next refresh
	end
	return machine
end

--- Re-pick the belts near the camera. Cheap (six plots), and twice a second is far
--- more often than anyone crosses ANIM_RANGE.
local function refreshActive()
	table.clear(active)
	local camera = Workspace.CurrentCamera
	local plots = Workspace:FindFirstChild("Plots")
	if camera == nil or plots == nil then
		return
	end
	local eye = camera.CFrame.Position
	for _, plot in plots:GetChildren() do
		local model = plot:FindFirstChild("Treadmill", true)
		if model == nil or model:GetAttribute("Locked") == true then
			continue -- a locked machine stands still until its owner buys it
		end
		local machine = machines[model]
		if machine and machine.slats[1].part.Parent == nil then
			machine = nil -- streamed out and back in as new parts; resolve them afresh
		end
		if machine == nil then
			machine = resolve(model)
			if machine == nil then
				continue
			end
			machines[model] = machine
		end
		if (machine.centre - eye).Magnitude <= ANIM_RANGE then
			table.insert(active, machine)
		end
	end
end

--- Run every chevron down its belt, wrapping at the far end, and turn the drums. The
--- rollers spin about their own long axis -- a Cylinder's axis is its local X, so the
--- turn is about X. The angle is rebuilt from `travelled` rather than accumulated onto
--- the CFrame, so it cannot drift, and at the belt's own surface speed the drum's top
--- moves with the tread.
---
--- `home.Rotation + position` keeps each arm's authored yaw and moves only where it
--- sits. The pattern is seamless because build/Plots lays the chevrons at a pitch
--- that divides the belt length exactly, so a chevron that wraps lands precisely
--- where its neighbour was.
local function animate(dt: number)
	sinceRefresh += dt
	if sinceRefresh >= RANGE_REFRESH then
		sinceRefresh = 0
		refreshActive()
	end
	if #active == 0 then
		return
	end
	travelled += BELT_SPEED * dt

	for _, machine in active do
		local offset = travelled % machine.length
		for _, slat in machine.slats do
			if slat.part.Parent == nil then
				continue -- streamed out under us; the next resolve picks up the new one
			end
			local along = (slat.along + offset) % machine.length
			slat.part.CFrame = slat.home.Rotation + (machine.start + machine.travel * along + slat.lateral)
		end
		for _, roller in machine.rollers do
			local radius = math.max(roller.part.Size.Y / 2, 0.05)
			roller.part.CFrame = roller.home * CFrame.Angles((travelled / radius) % (2 * math.pi), 0, 0)
		end
	end
end

-- ── Wiring ────────────────────────────────────────────────────────────────

function Treadmill.start()
	actionRemote = Net.get("StationAction")

	Speed.onChanged(function(view, previous)
		local wasTraining = previous ~= nil and previous.training
		if view.training and not wasTraining then
			show(true)
		elseif not view.training and wasTraining then
			show(false)
		end
		-- The popups belong to the bar, so they only fly while it is up.
		if shown and previous ~= nil then
			if view.level > previous.level then
				popWalkUp(view.walk)
			end
		end
	end)

	-- One connection for the life of the session, and it does next to nothing unless a
	-- belt is near the camera or the card is up. Connecting and disconnecting per session
	-- would be the same work plus a leak the first time an edge is missed — and the
	-- client bootstrap never calls a `stop` on anything, so there would be nowhere
	-- honest to undo it.
	RunService.RenderStepped:Connect(function(dt)
		animate(dt)
		if shown then
			paint()
			local view = Speed.view()
			sinceGain += dt
			if view and view.training and sinceGain >= LAYOUT.gainEvery then
				sinceGain = 0
				popGain(view.rate)
			end
		end
	end)
end

return Treadmill
