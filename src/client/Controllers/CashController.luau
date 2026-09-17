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

	A CARTOON GOLD COIN CARD, picked from a round of mockups (option A of seven). The
	charcoal card it replaced matched the dark nav tiles and read as a bank statement.
	Everything here is the toy-shop voice instead: a thick INK outline on every shape, a
	hard offset shadow (a black copy dropped a few px, never a blur), a big coin that
	breaks out past the card's left end, the balance in LuckiestGuy, and the income on
	an orange pill hanging off the card's bottom edge. The whole Dock.CASH_SIZE footprint
	is an invisible frame: the coin's left edge sits on the column margin so the meter
	below still lines up with it, and the card starts at the coin's centre.

	A CHANGE IS SHOWN, NOT JUST APPLIED. The balance used to snap straight to its new
	value, so a $13M sale read exactly like a $5 one. Now the number counts to the new
	value, a "+$1.2K" / "-$500" pops off the badge's right edge and floats away, and the
	badge gives a small punch. Exhibit payouts (CashState's `source == "exhibit"`, every
	few seconds while stands are full) get a smaller popup and no punch: they are
	background income, and a loud pop every five seconds would drown out the sales.
	The load snapshot sets the number silently -- a returning player's balance is not
	a gain.

	THE INCOME PILL carries the combined $/s every nuke on your stands is paying
	(IncomeState, sent on change). It hides at $0/s, so a player with empty stands sees
	just the coin and the balance.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Cash = {}

-- Dock.CASH_SIZE, not a local number — see the header. The badge now rides the
-- vertical centre of the left edge (Dock.CASH_MID_Y), stacked directly above the meter.
local BADGE_SIZE = Dock.CASH_SIZE
local BADGE_W = BADGE_SIZE.X.Offset
local BADGE_H = BADGE_SIZE.Y.Offset

-- The same cartoon black every sign and outline in the game uses (Kit.C.hazardBlack).
local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

-- Gold and orange, never green: green is exposure's colour and nothing else's
-- (PLAN §14), however much "money" wants it.
local STYLE = {
	card = Color3.fromHex("FFCF3A"),
	cardShine = Color3.fromHex("FFE27F"),
	coin = Color3.fromHex("FFB81C"),
	coinFace = Color3.fromHex("FFD34D"),
	coinRim = Color3.fromHex("D98A00"),
	coinMark = Color3.fromHex("B36A00"),
	coinGlint = Color3.fromHex("FFF1B8"),
	pill = Color3.fromHex("FF7A1A"),
	gain = Color3.fromHex("FFCF3A"),
	spend = Color3.fromHex("FF5A4E"),
	valueFont = Enum.Font.LuckiestGuy,
	pillFont = Enum.Font.FredokaOne,
}

-- Design px inside the Dock.CASH_SIZE footprint (280 x 86).
local LAYOUT = {
	coin = 76, -- diameter; left edge on the column margin, centred on the card
	coinFace = 55,
	cardTop = 6,
	cardHeight = 64, -- 6 + 64 + the pill's overhang = the 86 Dock reserves
	cardRadius = 20,
	shadowDrop = 5,
	outline = 4,
	valueLeft = 86,
	valueTextSize = 30,
	valueMinTextSize = 18, -- floor for setValueText's shrink-to-fit
	valueStroke = 3.5,
	-- LuckiestGuy draws high inside its line box, so a vertically "centred" label
	-- reads as riding the top edge. Measured in Studio against the card and the coin.
	valueDrop = 3,
	markDrop = 5,
	pillHeight = 28,
	pillInset = 16, -- pill's right edge in from the card's
	pillPad = 13,
	pillMinWidth = 92,
	pillTextSize = 17,
}
local CARD_LEFT = LAYOUT.coin / 2

-- Where each kind of popup is born, as offsets from the footprint's left edge and
-- vertical centre. Sales and spends come off the card beside the balance; stand payouts
-- come off the income pill they are the income of, one lane lower, so a payout landing
-- mid-sale never spawns on top of the sale's popup.
local LANE = {
	loud = Vector2.new(BADGE_W, LAYOUT.cardTop + LAYOUT.cardHeight / 2 - BADGE_H / 2),
	quiet = Vector2.new(BADGE_W - LAYOUT.pillInset, BADGE_H / 2 - LAYOUT.pillHeight / 2),
}

local ROUND = UDim.new(0.5, 0)

local COUNT_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local POPUP = {
	gap = 12, -- badge's right edge -> popup's left edge
	height = 44, -- the label box; its text is vertically centred in it
	pop =TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	riseTime = 1.2,
	fadeDelay = 0.75,
	fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	-- A second change of the same kind this soon after the last one folds into its
	-- popup instead of stacking a new one on top of it (selling a bag item by item).
	mergeWindow = 0.35,
	-- `rotation` is the gain's tilt; a spend tilts the other way.
	loud = { textSize = 36, stroke = 3.5, rise = 46, rotation = -8, sparkles = true },
	quiet = { textSize = 22, stroke = 2.5, rise = 22, rotation = 0, sparkles = false },
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

--- One flat, outlined cartoon shape. `stroke` 0 (the default) is no outline -- the
--- hard shadows and the inner highlights have none.
local function blob(
	parent: Instance,
	name: string,
	rect: { number },
	color: Color3,
	zIndex: number,
	radius: UDim,
	stroke: number?,
	strokeColor: Color3?
): Frame
	local frame = UIKit.panel(parent, {
		name = name,
		position = UDim2.fromOffset(rect[1], rect[2]),
		size = UDim2.fromOffset(rect[3], rect[4]),
		color = color,
		transparency = 0,
		cornerRadius = radius,
		strokeColor = strokeColor or INK,
		strokeThickness = stroke or 0,
		zIndex = zIndex,
	})
	return frame
end

local function setStroke(label: TextLabel, thickness: number)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = thickness
	end
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	return TextService:GetTextSize(text, size, font, Vector2.new(2000, 200)).X
end

--- Set the balance, stepping its TextSize down only when a long number would overflow.
---
--- NOT TextScaled + UITextSizeConstraint, which is what this used to be: both measure in
--- REAL screen pixels and ignore the canvas's UIScale, so the balance was capped at a
--- fixed pixel height while the card around it scaled with the screen -- it filled the
--- card on a small window and shrank inside it on a big monitor. A plain TextSize is in
--- design px like everything else on the canvas, and GetTextSize measures in design px
--- too, so the fit check stays screen-independent.
local function setValueText(text: string)
	local L = LAYOUT
	local room = ui.value.Size.X.Offset - 8
	local size = L.valueTextSize
	while size > L.valueMinTextSize and textWidth(text, size, STYLE.valueFont) > room do
		size -= 1
	end
	ui.value.TextSize = size
	ui.value.Text = text
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

	-- The footprint. Invisible; every visible piece is a child, so one UIScale punches
	-- the card, coin, pill and all their shadows together.
	local badge = Instance.new("Frame")
	badge.Name = "CashBadge"
	badge.Size = BADGE_SIZE
	badge.Position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 0.5, Dock.CASH_MID_Y)
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 2
	badge.Parent = canvas

	ui.punch = Instance.new("UIScale")
	ui.punch.Parent = badge

	-- ZIndex below is sibling order inside the footprint: card shadow, card, pill
	-- shadow, pill, coin shadow, coin, balance.
	local L = LAYOUT
	local cardW = BADGE_W - CARD_LEFT
	local cardRadius = UDim.new(0, L.cardRadius)

	blob(badge, "CardShadow", { CARD_LEFT, L.cardTop + L.shadowDrop, cardW, L.cardHeight }, INK, 1, cardRadius)
	local card = blob(badge, "Card", { CARD_LEFT, L.cardTop, cardW, L.cardHeight }, STYLE.card, 2, cardRadius, L.outline)
	-- The flat lighter band along the top: the cartoon version of a shine, no gradient.
	local shineLeft = L.valueLeft - CARD_LEFT - 2
	blob(card, "Shine", { shineLeft, 7, cardW - shineLeft - 8, 18 }, STYLE.cardShine, 3, ROUND)

	-- The pill hangs off the card's bottom edge. Its width follows its text (setRate),
	-- so it and its shadow are placed there; hidden until something is earning.
	local pillTop = BADGE_H - L.pillHeight
	ui.pillShadow = blob(badge, "RateShadow", { 0, pillTop + 4, L.pillMinWidth, L.pillHeight }, INK, 4, ROUND)
	ui.pill = blob(badge, "RatePill", { 0, pillTop, L.pillMinWidth, L.pillHeight }, STYLE.pill, 5, ROUND, 3)
	ui.pillShadow.Visible = false
	ui.pill.Visible = false
	ui.rate = UIKit.label(ui.pill, {
		name = "Rate",
		size = UDim2.fromScale(1, 1),
		font = STYLE.pillFont,
		textSize = L.pillTextSize,
		color = WHITE,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
		zIndex = 6,
	})

	-- The coin, centred on the card's vertical middle and breaking out past its left end.
	local coinTop = L.cardTop + L.cardHeight / 2 - L.coin / 2
	blob(badge, "CoinShadow", { 0, coinTop + L.shadowDrop, L.coin, L.coin }, INK, 6, ROUND)
	local coin = blob(badge, "Coin", { 0, coinTop, L.coin, L.coin }, STYLE.coin, 7, ROUND, L.outline)
	local faceInset = (L.coin - L.coinFace) / 2
	blob(coin, "Face", { faceInset, faceInset, L.coinFace, L.coinFace }, STYLE.coinFace, 8, ROUND, 3, STYLE.coinRim)
	local glint = blob(coin, "Glint", { 16, 17, 15, 8 }, STYLE.coinGlint, 9, ROUND)
	glint.Rotation = -40
	UIKit.label(coin, {
		name = "Mark",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromOffset(0, L.markDrop),
		text = "$",
		font = STYLE.valueFont,
		textSize = 40,
		color = STYLE.coinMark,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		zIndex = 10,
	})

	-- Left-aligned just past the coin, vertically centred on the card (the user asked for
	-- the number to sit by the coin, not float mid-card). `shadow = false`: UIKit.label's
	-- drop-shadow is a separate sibling label that would not follow setValueText's
	-- shrink-to-fit, and the heavy outline already carries it.
	ui.value = UIKit.label(badge, {
		name = "Value",
		position = UDim2.fromOffset(L.valueLeft, L.cardTop + L.valueDrop),
		size = UDim2.fromOffset(BADGE_W - L.valueLeft - 12, L.cardHeight),
		font = STYLE.valueFont,
		textSize = L.valueTextSize,
		color = WHITE,
		xAlign = Enum.TextXAlignment.Left,
		shadow = false,
		text = "$0",
		zIndex = 11,
	})
	setStroke(ui.value, L.valueStroke)

	-- The number the label is currently SHOWING, which lags `balance` while it counts.
	-- A NumberValue so TweenService can drive it, and a new tween on it simply takes
	-- over from one still running.
	ui.shown = Instance.new("NumberValue")
	ui.shown.Changed:Connect(function(value: number)
		setValueText(formatCash(math.floor(value + 0.5)))
	end)

	return gui
end

local function punch()
	ui.punch.Scale = 1.07
	TweenService:Create(ui.punch, PUNCH_TWEEN, { Scale = 1 }):Play()
end

local function popupText(amount: number): string
	return (if amount >= 0 then "+" else "-") .. formatCash(math.abs(amount))
end

--- The little outlined diamonds that twinkle round a loud gain. Children of the popup
--- label, so they tilt, pop and rise with it.
local function sparkle(parent: Instance, size: number, color: Color3): Frame
	local diamond = UIKit.panel(parent, {
		name = "Sparkle",
		size = UDim2.fromOffset(size, size),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = color,
		transparency = 0,
		cornerRadius = UDim.new(0, 2),
		strokeColor = INK,
		strokeThickness = 2,
		zIndex = 7,
	})
	diamond.Rotation = 45
	return diamond
end

--- Park the sparkles around wherever the text actually ends -- the label box is a
--- fixed width, the number inside it is not.
local function placeSparkles(record: any)
	if record.sparkles == nil then
		return
	end
	local width = textWidth(record.label.Text, record.label.TextSize, STYLE.valueFont)
	local mid = POPUP.height / 2
	record.sparkles[1].Position = UDim2.fromOffset(width + 12, mid - 16)
	record.sparkles[2].Position = UDim2.fromOffset(-10, mid - 12)
	record.sparkles[3].Position = UDim2.fromOffset(width + 22, mid + 14)
end

local function fadeOut(record: any)
	TweenService:Create(record.label, POPUP.fade, { TextTransparency = 1 }):Play()
	local stroke = record.label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, POPUP.fade, { Transparency = 1 }):Play()
	end
	for _, diamond in record.sparkles or {} do
		TweenService:Create(diamond, POPUP.fade, { BackgroundTransparency = 1 }):Play()
		local edge = diamond:FindFirstChildOfClass("UIStroke")
		if edge then
			TweenService:Create(edge, POPUP.fade, { Transparency = 1 }):Play()
		end
	end
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
		placeSparkles(lastPopup)
		lastPopup.scaler.Scale = 1.25
		TweenService:Create(lastPopup.scaler, POPUP.pop, { Scale = 1 }):Play()
		return
	end

	local style = if quiet then POPUP.quiet else POPUP.loud
	local lane = if quiet then LANE.quiet else LANE.loud
	local start = UDim2.new(0, Dock.ROW_SIDE_MARGIN + lane.X + POPUP.gap, 0.5, Dock.CASH_MID_Y + lane.Y)

	local label = UIKit.label(ui.canvas, {
		name = "CashPopup",
		size = UDim2.fromOffset(260, POPUP.height),
		position = start,
		anchorPoint = Vector2.new(0, 0.5),
		font = STYLE.valueFont,
		textSize = style.textSize,
		color = if positive then STYLE.gain else STYLE.spend,
		xAlign = Enum.TextXAlignment.Left,
		shadow = false,
		text = popupText(delta),
		zIndex = 6,
	})
	label.Rotation = if positive then style.rotation else -style.rotation
	setStroke(label, style.stroke)

	local scaler = Instance.new("UIScale")
	scaler.Scale = 0.4
	scaler.Parent = label
	TweenService:Create(scaler, POPUP.pop, { Scale = 1 }):Play()

	local record = {
		label = label,
		scaler = scaler,
		amount = delta,
		positive = positive,
		quiet = quiet,
		bornAt = now,
		sparkles = nil :: { Frame }?,
	}
	if style.sparkles and positive then
		record.sparkles = { sparkle(label, 14, WHITE), sparkle(label, 9, WHITE), sparkle(label, 8, STYLE.gain) }
		placeSparkles(record)
	end
	lastPopup = record

	-- Gains drift up, spends sink: the direction says which way the wallet moved
	-- before the colour or the sign has been read.
	local rise = if positive then -style.rise else style.rise
	TweenService:Create(
		label,
		TweenInfo.new(POPUP.riseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = start + UDim2.fromOffset(0, rise) }
	):Play()

	task.delay(POPUP.fadeDelay, function()
		fadeOut(record)
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
		setValueText(formatCash(amount))
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
	ui.pill.Visible = earning
	ui.pillShadow.Visible = earning
	if not earning then
		return
	end

	local L = LAYOUT
	local text = formatRate(perSecond)
	ui.rate.Text = text
	local width = math.max(L.pillMinWidth, textWidth(text, L.pillTextSize, STYLE.pillFont) + L.pillPad * 2)
	local left = BADGE_W - L.pillInset - width
	ui.pill.Size = UDim2.fromOffset(width, L.pillHeight)
	ui.pill.Position = UDim2.fromOffset(left, ui.pill.Position.Y.Offset)
	ui.pillShadow.Size = ui.pill.Size
	ui.pillShadow.Position = UDim2.fromOffset(left, ui.pillShadow.Position.Y.Offset)
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
