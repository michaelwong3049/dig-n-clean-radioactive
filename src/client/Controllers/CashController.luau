--[[
	CashController.lua — the persistent cash badge. Middle-left, stacked directly
	above the health/rads meter, always on screen.

	THERE WAS NO PERSISTENT CASH READOUT BEFORE THIS. data.cash only ever reached the
	client inside StationState's payload, which fires only while standing at a
	station -- walking around digging, a player had no live view of their own wallet.
	CashState (Shared/Net.luau) exists to fix exactly that: one snapshot on load
	(EconomyService.start()'s DataService.onLoaded hook) plus a fire on every real
	change (sell/spend/award, and DebugService's /cash), never per-tick.

	POSITION IS A FORMULA OVER Dock, NOT A FRESH NUMBER (UIKit.luau's own rule) --
	same left margin as the meter, same width, sitting directly above it with one
	Dock.GAP between them (Dock.CASH_MID_Y / Dock.METER_MID_Y place the pair around the
	vertical centre), so the two read as one stacked instrument cluster on the edge
	rather than two unrelated floating panels.

	SIZE IS Dock.CASH_SIZE, NOT A LOCAL HERE. It moved into the shared table the moment
	IndexController needed to measure against this badge — a second file computing its
	offset from this file's private numbers would be exactly the cross-file
	magic-number coupling Dock exists to prevent. This file still OWNS the value in the
	sense that nothing else builds the badge, but the number itself now lives in Dock
	so a resize here is not a silent breakage there.

	A compact charcoal balance card matches the darker navigation HUD.

	A CHANGE IS SHOWN, NOT JUST APPLIED. The balance used to snap straight to its new
	value, so a $13M sale read exactly like a $5 one. Now the number counts to the new
	value, a "+$1.2K" / "-$500" pops off the badge's right edge and floats away, and the
	badge gives a small punch. Exhibit payouts (CashState's `source == "exhibit"`, every
	few seconds while stands are full) get a smaller popup and no punch: they are
	background income, and a loud pop every five seconds would drown out the sales.
	The load snapshot sets the number silently -- a returning player's balance is not
	a gain.

	THE "BALANCE" CAPTION IS GONE; the $ icon already says what the number is. Its
	line now carries the combined $/s every nuke on your stands is paying (IncomeState,
	sent on change), and it hides at $0/s so a player with empty stands sees just the
	balance, centred.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Cash = {}

-- Dock.CASH_SIZE, not a local number — see the header. The badge now rides the
-- vertical centre of the left edge (Dock.CASH_MID_Y), stacked directly above the meter.
local BADGE_SIZE = Dock.CASH_SIZE

-- The value label's two resting spots: centred in the badge when there is no income
-- line, lifted to make room for it when there is.
local VALUE_ALONE = UDim2.fromOffset(60, 15)
local VALUE_WITH_RATE = UDim2.fromOffset(60, 5)

-- Gains share the plinth yield tags' amber (ExhibitService RATE_COLOR), so "money
-- coming in" is one colour on the stands and on the HUD. Never green: green is
-- exposure's colour and nothing else's (PLAN §14).
local GAIN_COLOR = UIKit.C.amber
local SPEND_COLOR = UIKit.C.red

local COUNT_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LAYOUT_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local POPUP = {
	gap = 12, -- badge's right edge -> popup's left edge
	pop = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	riseTime = 1.2,
	fadeDelay = 0.75,
	fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	-- A second change of the same kind this soon after the last one folds into its
	-- popup instead of stacking a new one on top of it (selling a bag item by item).
	mergeWindow = 0.35,
	loud = { textSize = 28, rise = 46 },
	quiet = { textSize = 20, rise = 30 },
}

local ui = {}
local balance: number? = nil -- last CashState amount; nil until the load snapshot lands
local lastPopup: any = nil

--- $340 under a thousand, $5.2K into the thousands, $1.4M into the millions, $2.1B into
--- the billions -- the reference image's own "$5K" convention, and compact enough to
--- still read at a glance at the values this economy actually reaches (post-rescale an
--- Anomaly sells up to ~$13M, and a built-out exhibit's banked $/hr runs into billions).
local function formatCash(amount: number): string
	if amount >= 1_000_000_000 then
		return string.format("$%.1fB", amount / 1_000_000_000)
	elseif amount >= 1_000_000 then
		return string.format("$%.1fM", amount / 1_000_000)
	elseif amount >= 1_000 then
		return string.format("$%.1fK", amount / 1_000)
	end
	return string.format("$%d", math.floor(amount))
end

--- "+$2.00/s" up to "+$1.2M/s" -- ExhibitService.formatRate's ladder (what the plinth
--- tags print), carried on into millions and billions like formatCash above.
local function formatRate(perSecond: number): string
	if perSecond >= 1_000_000_000 then
		return string.format("+$%.1fB/s", perSecond / 1_000_000_000)
	elseif perSecond >= 1_000_000 then
		return string.format("+$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 1000 then
		return string.format("+$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("+$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("+$%.1f/s", perSecond)
	end
	return string.format("+$%.2f/s", perSecond)
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "CashHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local canvas = UIKit.canvas(gui)
	ui.canvas = canvas

	local shadow = UIKit.panel(canvas, {
		name = "CashShadow",
		size = BADGE_SIZE,
		position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 0.5, Dock.CASH_MID_Y + 4),
		anchorPoint = Vector2.new(0, 0.5),
		color = Color3.fromRGB(3, 7, 12),
		transparency = 0.2,
		cornerRadius = UDim.new(0, 9),
		strokeThickness = 0,
		zIndex = 2,
	})
	local badge = UIKit.panel(canvas, {
		name = "CashBadge",
		size = BADGE_SIZE,
		position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 0.5, Dock.CASH_MID_Y),
		anchorPoint = Vector2.new(0, 0.5),
		color = Color3.new(1, 1, 1),
		transparency = 0,
		cornerRadius = UDim.new(0, 9),
		strokeColor = Color3.fromRGB(57, 65, 79),
		strokeThickness = 1,
		zIndex = 3,
	})

	-- One UIScale each on the badge and its shadow, driven together, for the punch.
	-- Both anchor at (0, 0.5), so they grow off the same left edge and stay stacked.
	ui.punch = {}
	for _, frame in { badge, shadow } do
		local scaler = Instance.new("UIScale")
		scaler.Parent = frame
		table.insert(ui.punch, scaler)
	end

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(29, 35, 46), Color3.fromRGB(13, 18, 27))
	gradient.Rotation = 90
	gradient.Parent = badge

	local icon = UIKit.panel(badge, {
		name = "CurrencyIcon",
		size = UDim2.fromOffset(38, 38),
		position = UDim2.fromOffset(13, 13),
		color = Color3.fromRGB(43, 40, 32),
		transparency = 0,
		cornerRadius = UDim.new(0, 8),
		strokeColor = Color3.fromRGB(91, 78, 50),
		strokeThickness = 1,
		zIndex = 4,
	})
	UIKit.label(icon, {
		name = "Symbol",
		size = UDim2.fromScale(1, 1),
		text = "$",
		font = Enum.Font.GothamBold,
		textSize = 24,
		color = Color3.fromRGB(219, 192, 130),
		xAlign = Enum.TextXAlignment.Center,
		strokeTransparency = 1,
		zIndex = 5,
	})

	-- `shadow = false`: this label flips TextScaled + a UITextSizeConstraint on
	-- right below (to shrink long balances so they never overflow the badge), and
	-- UIKit.label's default drop-shadow for a GothamBold ("title" tier) label is a
	-- SEPARATE sibling TextLabel built before that scaling is applied — it never
	-- gets TextScaled or the constraint, so it kept rendering at the fixed 30px
	-- size while the real label shrank to fit, which showed as two overlapping
	-- numbers at two different sizes (misread as "two fonts"). No shadow needed on
	-- a small stacked readout anyway; the heavy outline (still on) already carries it.
	ui.value = UIKit.label(badge, {
		name = "Value",
		size = UDim2.new(1, -72, 0, 34),
		position = VALUE_ALONE,
		font = Enum.Font.GothamBold,
		textSize = 30,
		color = Color3.fromRGB(237, 242, 250),
		xAlign = Enum.TextXAlignment.Left,
		strokeTransparency = 1,
		shadow = false,
		text = "$0",
		zIndex = 4,
	})

	ui.value.TextScaled = true
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MinTextSize = 20
	textLimit.MaxTextSize = 30
	textLimit.Parent = ui.value

	ui.rate = UIKit.label(badge, {
		name = "Rate",
		size = UDim2.new(1, -72, 0, 18),
		position = UDim2.fromOffset(60, 39),
		font = Enum.Font.GothamBold,
		textSize = 16,
		color = GAIN_COLOR,
		xAlign = Enum.TextXAlignment.Left,
		shadow = false,
		visible = false,
		zIndex = 4,
	})

	-- The number the label is currently SHOWING, which lags `balance` while it counts.
	-- A NumberValue so TweenService can drive it, and a new tween on it simply takes
	-- over from one still running.
	ui.shown = Instance.new("NumberValue")
	ui.shown.Changed:Connect(function(value: number)
		ui.value.Text = formatCash(math.floor(value + 0.5))
	end)

	return gui
end

local function punch()
	for _, scaler in ui.punch do
		scaler.Scale = 1.07
		TweenService:Create(scaler, PUNCH_TWEEN, { Scale = 1 }):Play()
	end
end

local function popupText(amount: number): string
	return (if amount >= 0 then "+" else "-") .. formatCash(math.abs(amount))
end

--- Float "+$X" / "-$X" off the badge's right edge. Parented to the canvas, not the
--- badge, so the badge's punch never drags a popup around with it.
local function popup(delta: number, quiet: boolean)
	local now = os.clock()
	local positive = delta >= 0

	if
		lastPopup
		and lastPopup.label.Parent
		and lastPopup.positive == positive
		and lastPopup.quiet == quiet
		and now - lastPopup.bornAt < POPUP.mergeWindow
	then
		lastPopup.amount += delta
		lastPopup.label.Text = popupText(lastPopup.amount)
		lastPopup.scaler.Scale = 1.25
		TweenService:Create(lastPopup.scaler, POPUP.pop, { Scale = 1 }):Play()
		return
	end

	local style = if quiet then POPUP.quiet else POPUP.loud
	local start = UDim2.new(0, Dock.ROW_SIDE_MARGIN + BADGE_SIZE.X.Offset + POPUP.gap, 0.5, Dock.CASH_MID_Y)

	local label = UIKit.label(ui.canvas, {
		name = "CashPopup",
		size = UDim2.fromOffset(240, 36),
		position = start,
		anchorPoint = Vector2.new(0, 0.5),
		font = Enum.Font.GothamBold,
		textSize = style.textSize,
		color = if positive then GAIN_COLOR else SPEND_COLOR,
		xAlign = Enum.TextXAlignment.Left,
		shadow = false,
		text = popupText(delta),
		zIndex = 6,
	})

	local scaler = Instance.new("UIScale")
	scaler.Scale = 0.4
	scaler.Parent = label
	TweenService:Create(scaler, POPUP.pop, { Scale = 1 }):Play()

	-- Gains drift up, spends sink: the direction says which way the wallet moved
	-- before the colour or the sign has been read.
	local rise = if positive then -style.rise else style.rise
	TweenService:Create(
		label,
		TweenInfo.new(POPUP.riseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = start + UDim2.fromOffset(0, rise) }
	):Play()

	lastPopup = {
		label = label,
		scaler = scaler,
		amount = delta,
		positive = positive,
		quiet = quiet,
		bornAt = now,
	}

	task.delay(POPUP.fadeDelay, function()
		TweenService:Create(label, POPUP.fade, { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, POPUP.fade, { Transparency = 1 }):Play()
		end
		task.wait(POPUP.fade.Time)
		label:Destroy()
	end)
end

local function setBalance(amount: number, source: string?)
	local previous = balance
	balance = amount

	-- The load snapshot: take the number as it is, no count and no popup.
	if previous == nil then
		ui.shown.Value = amount
		ui.value.Text = formatCash(amount)
		return
	end

	local delta = amount - previous
	if delta == 0 then
		return
	end

	TweenService:Create(ui.shown, COUNT_TWEEN, { Value = amount }):Play()

	local quiet = source == "exhibit"
	popup(delta, quiet)
	if not quiet then
		punch()
	end
end

local function setRate(perSecond: number)
	local earning = perSecond > 0
	ui.rate.Visible = earning
	if earning then
		ui.rate.Text = formatRate(perSecond)
	end
	TweenService:Create(ui.value, LAYOUT_TWEEN, { Position = if earning then VALUE_WITH_RATE else VALUE_ALONE }):Play()
end

function Cash.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("CashState").OnClientEvent:Connect(function(amount: number, source: string?)
		setBalance(amount or 0, source)
	end)

	Net.get("IncomeState").OnClientEvent:Connect(function(perSecond: number)
		setRate(perSecond or 0)
	end)
end

return Cash
