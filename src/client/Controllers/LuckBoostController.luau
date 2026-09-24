--!strict
--[[
	LuckBoostController.luau — the 2x-luck clover in the bottom-right corner, the
	banner when the Violet Aurora arrives, and the aurora's lights (Config/LuckBoost).

	IT DECIDES NOTHING. Whether you are lucky is the server's answer (StatResolver,
	LuckBoostService); this reads the two clocks the server publishes as attributes --
	the event's end on ReplicatedStorage, the bought clover's end on the Player -- and
	draws them. Attributes rather than a remote because both are state a late joiner
	needs the instant they arrive (Config/LuckBoost's replication note).

	THE CLOVER shows only while a boost is running. It says the multiplier ON the
	clover (x2, or x4 with the aurora and a bought clover together) and the time UNDER
	it -- the time until that number next changes, which is the soonest of the two
	clocks. Green at x2, purple at x4 (CloverArt.paletteFor), timer pill to match. Hovering it names both; clicking it opens the Shop, which is where more
	clover time is sold. The last 30 seconds pulse.

	POSITION IS A FORMULA OVER Dock: the right column margin, one band above the hotbar
	(the haul widget's own floor, Dock.HAULPANEL_BOTTOM), and no wider than the haul
	widget's right-hand clearance (Dock.HAULPANEL_RIGHT) so the two never overlap. On a
	touch screen it lifts clear of the jump button (UIKit.touchCorner).

	AND NEVER UP INTO THE INDEX/SHOP/NUKES/WARP COLUMN (CampWarpController.columnBottom). On a short
	canvas -- the docked Studio viewport, a phone held sideways -- that column is centred
	rather than hung high, and the first draft's clover sat right on top of the Shop
	tile. Where the gap between the column and the hotbar is too short, the clover first
	slides down toward the hotbar, then shrinks (a `Fit` UIScale, floored at MIN_FIT).
	The pop-in animation rides a second UIScale on the inner `Body`, so the two never
	fight over one Scale.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local LuckBoost = require(Shared.Config.LuckBoost)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local CloverArt = require(script.Parent.Parent.CloverArt)
local AuroraFx = require(script.Parent.Parent.AuroraFx)
local ShopController = require(script.Parent.ShopController)
local CampWarpController = require(script.Parent.CampWarpController)

local LuckBoostController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

local STYLE = {
	-- The timer pill wears the clover's colour: its stem shade, dark enough for white
	-- text. Keyed by CloverArt palette.
	pill = {
		[CloverArt.GREEN] = Color3.fromHex("2E7D32"),
		[CloverArt.PURPLE] = Color3.fromHex("6A34C9"),
	} :: { [CloverArt.Palette]: Color3 },
	pillWarn = Color3.fromHex("C23B9A"),
	tip = Color3.fromHex("241640"),
	numberFont = Enum.Font.LuckiestGuy,
	textFont = Enum.Font.FredokaOne,
}

-- Design px. The footprint is exactly the haul widget's right-hand clearance wide.
local BADGE_W = Dock.HAULPANEL_RIGHT - Dock.ROW_SIDE_MARGIN
local CLOVER = 80
local PILL_H = 28
local PILL_GAP = 2
local BADGE_H = CLOVER + PILL_GAP + PILL_H + 4
local MIN_FIT = 0.6
local WARN_SECONDS = 30

local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHRINK = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BANNER_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BANNER_OUT = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BANNER_HOLD = 3.6

type Ui = {
	gui: ScreenGui,
	canvas: Frame,
	badge: TextButton,
	fit: UIScale,
	scale: UIScale,
	clover: Frame,
	mult: TextLabel,
	pill: Frame,
	time: TextLabel,
	tip: Frame,
	tipText: TextLabel,
	banner: CanvasGroup,
	bannerScale: UIScale,
	bannerTitle: TextLabel,
	bannerSub: TextLabel,
}

local ui: Ui
local shown = false
local hovering = false
local bannerToken = 0
-- The clover's last end time, and whether the first value has arrived yet: the one the
-- server publishes on load is a baseline, not a purchase.
local lastPersonal = 0
local seenPersonal = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function eventEndsAt(): number
	local value = ReplicatedStorage:GetAttribute(LuckBoost.EVENT_ATTR)
	return if type(value) == "number" then value else 0
end

local function personalEndsAt(): number
	local value = Players.LocalPlayer:GetAttribute(LuckBoost.PERSONAL_ATTR)
	return if type(value) == "number" then value else 0
end

--- "9:42", or "1:04:10" past an hour.
local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local r = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

local function ink(label: TextLabel, thickness: number)
	label.TextStrokeTransparency = 1
	local stroke = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
end

local function text(parent: Instance, name: string, font: Enum.Font, size: number, z: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = WHITE
	label.ZIndex = z
	label.Parent = parent
	ink(label, math.max(2, size * 0.1))
	return label
end

-- ── Build ─────────────────────────────────────────────────────────────

local function buildBadge(canvas: Frame): (TextButton, UIScale, UIScale, Frame, TextLabel, Frame, TextLabel)
	-- A button so it can be hovered and clicked; it draws nothing itself. Its UIScale
	-- is the layout fit (place); the pop lives on `Body` below.
	local badge = Instance.new("TextButton")
	badge.Name = "LuckBadge"
	badge.Text = ""
	badge.AutoButtonColor = false
	badge.BackgroundTransparency = 1
	badge.AnchorPoint = Vector2.new(1, 1)
	badge.Size = UDim2.fromOffset(BADGE_W, BADGE_H)
	badge.Visible = false
	badge.Parent = canvas
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = badge

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromScale(1, 1)
	body.Parent = badge
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = body

	local clover = CloverArt.build(body, CLOVER, 2)
	clover.AnchorPoint = Vector2.new(0.5, 0)
	clover.Position = UDim2.fromScale(0.5, 0)

	local mult = text(body, "Multiplier", STYLE.numberFont, 30, 20)
	mult.AnchorPoint = Vector2.new(0.5, 0.5)
	mult.Size = UDim2.fromOffset(BADGE_W, 34)
	-- LuckiestGuy draws high in its box (CashController's valueDrop); nudged down to sit
	-- on the clover's heart.
	mult.Position = UDim2.new(0.5, 3, 0, CLOVER / 2 + 4)
	mult.Rotation = -8
	mult.Text = "x2"
	ink(mult, 3.5)

	local pill = Instance.new("Frame")
	pill.Name = "Timer"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Size = UDim2.fromOffset(BADGE_W - 6, PILL_H)
	pill.Position = UDim2.new(0.5, 0, 0, CLOVER + PILL_GAP)
	pill.BackgroundColor3 = STYLE.pill[CloverArt.GREEN]
	pill.BorderSizePixel = 0
	pill.ZIndex = 20
	pill.Parent = body
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = pill
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = pill
	-- The hard shadow under the pill, same voice as the cash badge's.
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = pill.AnchorPoint
	shadow.Size = pill.Size
	shadow.Position = pill.Position + UDim2.fromOffset(2, 4)
	shadow.BackgroundColor3 = INK
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 19
	shadow.Parent = body
	local shadowRound = round:Clone()
	shadowRound.Parent = shadow

	local time = text(pill, "Time", STYLE.textFont, 19, 21)
	time.Size = UDim2.fromScale(1, 1)
	time.Position = UDim2.fromOffset(0, -1)
	time.Text = "10:00"

	return badge, fit, scale, clover, mult, pill, time
end

local function buildTip(canvas: Frame): (Frame, TextLabel)
	local tip = Instance.new("Frame")
	tip.Name = "LuckTip"
	tip.AnchorPoint = Vector2.new(1, 1)
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.BackgroundColor3 = STYLE.tip
	tip.BorderSizePixel = 0
	tip.Visible = false
	tip.ZIndex = 30
	tip.Parent = canvas
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 10)
	round.Parent = tip
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = tip
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = tip

	local label = text(tip, "Lines", STYLE.textFont, 16, 31)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.RichText = true
	return tip, label
end

local function buildBanner(canvas: Frame): (CanvasGroup, UIScale, TextLabel, TextLabel)
	-- A CanvasGroup so the whole card fades as one: UIKit-style UIStroke outlines do
	-- not fade with TextTransparency, GroupTransparency takes them too.
	local banner = Instance.new("CanvasGroup")
	banner.Name = "LuckBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.24)
	banner.Size = UDim2.fromOffset(620, 130)
	banner.BackgroundTransparency = 1
	banner.GroupTransparency = 1
	banner.Visible = false
	banner.ZIndex = 40
	banner.Parent = canvas

	local scale = Instance.new("UIScale")
	scale.Parent = banner

	local title = text(banner, "Title", STYLE.numberFont, 50, 42)
	title.Size = UDim2.new(1, 0, 0, 62)
	title.Position = UDim2.fromOffset(0, 6)
	ink(title, 4.5)

	local sub = text(banner, "Subtitle", STYLE.textFont, 26, 42)
	sub.Size = UDim2.new(1, 0, 0, 34)
	sub.Position = UDim2.fromOffset(0, 70)
	ink(sub, 3)

	-- A clover either side of the title.
	for i, side in { -1, 1 } do
		local c = CloverArt.build(banner, 54, 41)
		c.Name = `Clover{i}`
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.new(0.5, side * 262, 0, 38)
		c.Rotation = side * 14
	end

	return banner, scale, title, sub
end

local function place()
	local height = ui.canvas.AbsoluteSize.Y / UIKit.canvasScale(ui.canvas)
	local corner = UIKit.touchCorner()
	-- The lowest it may sit: above the hotbar, and above the jump button on touch.
	local floor = math.max(Dock.HOTBAR_BOTTOM + Dock.HOTBAR_HEIGHT + Dock.GAP, if corner.Y > 0 then corner.Y + Dock.GAP else 0)
	local bottom = math.max(Dock.HAULPANEL_BOTTOM, floor)
	-- The highest its top may reach, measured up from the bottom edge like `bottom`.
	local ceiling = height - CampWarpController.columnBottom(height) - Dock.GAP
	if ceiling - bottom < BADGE_H then
		bottom = math.max(floor, ceiling - BADGE_H)
	end
	local fit = math.clamp((ceiling - bottom) / BADGE_H, MIN_FIT, 1)
	local right = Dock.ROW_SIDE_MARGIN
	ui.fit.Scale = fit
	ui.badge.Position = UDim2.new(1, -right, 1, -bottom)
	ui.tip.Position = UDim2.new(1, -(right + BADGE_W * fit + Dock.GAP), 1, -(bottom + PILL_H * fit))
end

local function build(): Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = "LuckBoost"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Beside the Index/Shop tiles (55); the banner is a one-off over the field.
	gui.DisplayOrder = 56
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local badge, fit, scale, clover, mult, pill, time = buildBadge(canvas)
	local tip, tipText = buildTip(canvas)
	local banner, bannerScale, bannerTitle, bannerSub = buildBanner(canvas)

	return {
		gui = gui,
		canvas = canvas,
		badge = badge,
		fit = fit,
		scale = scale,
		clover = clover,
		mult = mult,
		pill = pill,
		time = time,
		tip = tip,
		tipText = tipText,
		banner = banner,
		bannerScale = bannerScale,
		bannerTitle = bannerTitle,
		bannerSub = bannerSub,
	}
end

-- ── Behaviour ─────────────────────────────────────────────────────────

local function currentMultiplier(): number
	local t = now()
	return LuckBoost.multiplier(eventEndsAt() > t, personalEndsAt() > t)
end

--- The banner's clovers and title in the colour of the multiplier it leaves you on.
local function showBanner(title: string, subtitle: string)
	bannerToken += 1
	local token = bannerToken
	local banner = ui.banner
	local palette = CloverArt.paletteFor(currentMultiplier())
	for _, child in banner:GetChildren() do
		if string.sub(child.Name, 1, 6) == "Clover" then
			CloverArt.paint(child, palette)
		end
	end
	ui.bannerTitle.TextColor3 = palette.shine
	ui.bannerTitle.Text = title
	ui.bannerSub.Text = subtitle
	banner.Visible = true
	banner.GroupTransparency = 1
	ui.bannerScale.Scale = 0.6
	TweenService:Create(banner, BANNER_IN, { GroupTransparency = 0 }):Play()
	TweenService:Create(ui.bannerScale, BANNER_IN, { Scale = 1 }):Play()
	task.delay(BANNER_HOLD, function()
		if token ~= bannerToken then
			return
		end
		TweenService:Create(banner, BANNER_OUT, { GroupTransparency = 1 }):Play()
		TweenService:Create(ui.bannerScale, BANNER_OUT, { Scale = 1.08 }):Play()
		task.delay(BANNER_OUT.Time, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end)
end

local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	if on then
		ui.badge.Visible = true
		ui.scale.Scale = 0
		TweenService:Create(ui.scale, POP, { Scale = 1 }):Play()
	else
		ui.tip.Visible = false
		local shrink = TweenService:Create(ui.scale, SHRINK, { Scale = 0 })
		shrink.Completed:Connect(function()
			if not shown then
				ui.badge.Visible = false
			end
		end)
		shrink:Play()
	end
end

--- Punch the badge when the multiplier changes (a clover bought mid-aurora -> x4).
local function punch()
	ui.scale.Scale = 1.25
	TweenService:Create(ui.scale, POP, { Scale = 1 }):Play()
end

local lastMult = 1
local lastText = ""
local palette = CloverArt.GREEN

local function refresh(t: number)
	local event = eventEndsAt() - t
	local personal = personalEndsAt() - t
	local eventOn = event > 0
	local personalOn = personal > 0
	local mult = LuckBoost.multiplier(eventOn, personalOn)

	AuroraFx.setActive(eventOn)
	setShown(mult > 1)
	if mult <= 1 then
		lastMult = 1
		return
	end

	if mult ~= lastMult then
		ui.mult.Text = `x{mult}`
		palette = CloverArt.paletteFor(mult)
		CloverArt.paint(ui.clover, palette)
		if lastMult > 1 then
			punch()
		end
		lastMult = mult
	end

	-- The time until the number on the clover next changes.
	local left = math.huge
	if eventOn then
		left = math.min(left, event)
	end
	if personalOn then
		left = math.min(left, personal)
	end
	local shownText = clock(left)
	if shownText ~= lastText then
		lastText = shownText
		ui.time.Text = shownText
	end

	local warn = left <= WARN_SECONDS
	local pulse = if warn then 0.5 + 0.5 * math.sin(t * 8) else 0
	ui.pill.BackgroundColor3 = STYLE.pill[palette]:Lerp(STYLE.pillWarn, pulse)

	if hovering then
		local lines = {}
		if eventOn then
			table.insert(lines, `{LuckBoost.EVENT_NAME}  <b>{clock(event)}</b>`)
		end
		if personalOn then
			table.insert(lines, `Lucky Clover  <b>{clock(personal)}</b>`)
		end
		ui.tipText.Text = table.concat(lines, "\n")
	end
end

local function onEventChanged()
	local t = now()
	local started = ReplicatedStorage:GetAttribute(LuckBoost.EVENT_START_ATTR)
	local ends = eventEndsAt()
	-- Only an aurora that has JUST begun gets the banner. Joining mid-event you see the
	-- sky and the clover; being told it "arrived" ten minutes late would be wrong.
	if ends > t and type(started) == "number" and t - started < 5 then
		showBanner(string.upper(LuckBoost.EVENT_NAME), `{LuckBoost.MULT}x LUCK for {clock(ends - started)}!`)
	end
end

local function onPersonalChanged()
	local value = Players.LocalPlayer:GetAttribute(LuckBoost.PERSONAL_ATTR)
	if type(value) ~= "number" then
		return
	end
	-- More time than before, by more than rounding: a purchase (or a debug grant).
	if seenPersonal then
		local before = math.max(lastPersonal, now())
		if value > before + 5 then
			showBanner("LUCKY CLOVER", `{LuckBoost.MULT}x LUCK  +{clock(value - before)}`)
		end
	end
	seenPersonal = true
	lastPersonal = value
end

function LuckBoostController.start()
	local player = Players.LocalPlayer
	ui = build()
	ui.gui.Parent = player:WaitForChild("PlayerGui")
	place()
	UIKit.onScaleChanged(place)
	ui.canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	ui.badge.MouseEnter:Connect(function()
		hovering = true
		ui.tip.Visible = true
	end)
	ui.badge.MouseLeave:Connect(function()
		hovering = false
		ui.tip.Visible = false
	end)
	ui.badge.Activated:Connect(ShopController.open)

	ReplicatedStorage:GetAttributeChangedSignal(LuckBoost.EVENT_ATTR):Connect(onEventChanged)
	player:GetAttributeChangedSignal(LuckBoost.PERSONAL_ATTR):Connect(onPersonalChanged)
	onPersonalChanged()

	-- The idle wobble and the countdown. Cheap: a handful of property writes a frame.
	RunService.Heartbeat:Connect(function()
		local t = now()
		refresh(t)
		if shown then
			ui.clover.Rotation = 5 * math.sin(os.clock() * 1.6)
		end
	end)
end

return LuckBoostController
