--[[
	CashController.lua — the persistent cash readout. Bottom-left corner, directly under
	the speed row, always on screen.

	THERE WAS NO PERSISTENT CASH READOUT BEFORE THIS. data.cash only ever reached the
	client inside StationState's payload, which fires only while standing at a
	station -- walking around digging, a player had no live view of their own wallet.
	CashState (Shared/Net.luau) exists to fix exactly that: one snapshot on load
	(EconomyService.start()'s DataService.onLoaded hook) plus a fire on every real
	change (sell/spend/award, and DebugService's /cash), never per-tick.

	POSITION IS A FORMULA OVER Dock, NOT A FRESH NUMBER (UIKit.luau's own rule) --
	same left margin and width as the speed row, sitting directly below it
	(Dock.CASH_BOTTOM / Dock.SPEED_BOTTOM stack the pair up from the bottom edge, lifted
	clear of a phone's thumbstick by Dock.sideLift), so the two read as one instrument
	cluster in the corner rather than two unrelated floating panels.

	SIZE IS Dock.CASH_SIZE, NOT A LOCAL HERE. It moved into the shared table the moment
	IndexController needed to measure against this badge — a second file computing its
	offset from this file's private numbers would be exactly the cross-file
	magic-number coupling Dock exists to prevent. This file still OWNS the value in the
	sense that nothing else builds the badge, but the number itself now lives in Dock
	so a resize here is not a silent breakage there.

	NO BOX: A CASH BUNDLE AND A GREEN NUMBER. This was a gold coin on a gold card with
	the income on an orange pill. The user asked for just the icon with the number
	beside it, picked a banded bundle of green notes (#19 of a mockup round, after a
	reference picture), and asked for the numbers in green. GREEN IS A DELIBERATE
	EXCEPTION here: everywhere else green is exposure's colour (PLAN §14), but on the
	cash row it is money's, by request. Without a card behind it the number has to carry
	itself over bright sky and dark caves alike, so it gets a heavy INK outline plus a
	hard INK drop shadow (UIKit.hudNumber), and the bundle a dropped shadow of its own.
	The numbers are GOTHAM BLACK (picked from a font round, #3 of twelve), replacing
	LuckiestGuy. The whole Dock.CASH_SIZE footprint is an invisible frame: the
	bundle's left edge sits on the column margin, lined up with the shoe above it.

	A CHANGE IS SHOWN, NOT JUST APPLIED. The balance used to snap straight to its new
	value, so a $13M sale read exactly like a $5 one. Now the number counts to the new
	value, a "+$1.2K" / "-$500" pops off the end of the number and floats away, and the
	badge gives a small punch. Exhibit payouts (CashState's `source == "exhibit"`, every
	few seconds while stands are full) get a smaller popup and no punch: they are
	background income, and a loud pop every five seconds would drown out the sales.
	The load snapshot sets the number silently -- a returning player's balance is not
	a gain.

	THE INCOME LINE under the balance carries the combined $/s every nuke on your stands
	is paying (IncomeState, sent on change). It hides at $0/s. The balance never moves
	for it: it stays level with the bundle's middle and the line hangs below (lifting
	the balance to make room read as the money jumping).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local Artwork = require(script.Parent.Parent.HudArtwork)
local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local Sfx = require(script.Parent.Parent.Sfx)

local Cash = {}

-- Dock.CASH_SIZE, not a local number — see the header. The row sits in the bottom-left
-- corner (Dock.CASH_BOTTOM), directly under the speed row.
local BADGE_SIZE = Dock.CASH_SIZE
local BADGE_W = BADGE_SIZE.X.Offset
local BADGE_H = BADGE_SIZE.Y.Offset

-- The same cartoon black every sign and outline in the game uses (Kit.C.hazardBlack).
local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

-- Green for money on this row only (see the header); the spend popup stays red.
local STYLE = {
	value = Color3.fromHex("7CF25A"),
	rate = Color3.fromHex("C8F5AE"),
	gain = Color3.fromHex("7CF25A"),
	spend = Color3.fromHex("FF5A4E"),
	valueFont = Enum.Font.GothamBlack,
	rateFont = Enum.Font.GothamBlack,
}

-- Design px inside the Dock.CASH_SIZE footprint (380 x 104).
local LAYOUT = {
	icon = Dock.SIDE_ICON, -- the bundle; left edge on the column margin, top of the footprint
	iconDrop = Vector2.new(3, 4),
	valueLeft = Dock.SIDE_ICON + 10,
	-- The box is centred on the bundle's VISIBLE middle (Dock.SIDE_ICON_MIDDLE), a
	-- couple of px low so the digits sit level with the note's face; it never moves.
	-- Gotham Black's digits centre in their line box (measured in Studio), so the box's
	-- middle is the digits' middle.
	valueTop = math.floor(Dock.SIDE_ICON * Dock.SIDE_ICON_MIDDLE + 1.5) - 34,
	valueHeight = 68,
	valueTextSize = 56,
	valueMinTextSize = 32, -- floor for setValueText's shrink-to-fit
	valueStroke = 6,
	rateTop = 74,
	rateHeight = 30,
	rateTextSize = 24,
	rateStroke = 4,
	textDrop = Vector2.new(3, 4),
}

local COUNT_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local POPUP = {
	gap = 12, -- end of the number it comes off -> popup's left edge
	height = 72, -- the label box; its text is vertically centred in it
	pop =TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	riseTime = 1.2,
	fadeDelay = 0.75,
	fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	-- A second change of the same kind this soon after the last one folds into its
	-- popup instead of stacking a new one on top of it (selling a bag item by item).
	mergeWindow = 0.35,
	-- `rotation` is the gain's tilt; a spend tilts the other way.
	loud = { textSize = 60, stroke = 5.5, rise = 64, rotation = -8, sparkles = true },
	quiet = { textSize = 30, stroke = 3.5, rise = 28, rotation = 0, sparkles = false },
}

local ui = {}
local bottom = Dock.CASH_BOTTOM -- the row's bottom edge above the screen's, lift included
local balance: number? = nil -- last CashState amount; nil until the load snapshot lands
local lastPopup: any = nil

--- $340 under a thousand, $5.2K into the thousands, $1.4M into the millions, $2.1B into
--- the billions -- the reference image's own "$5K" convention, and compact enough to
--- still read at a glance at the values this economy actually reaches (post-rescale an
--- Anomaly sells up to ~$13M, and a built-out exhibit's banked $/hr runs into billions).
local function formatCash(amount: number): string
	if amount >= 1_000_000_000_000 then
		return string.format("$%.1fT", amount / 1_000_000_000_000)
	elseif amount >= 1_000_000_000 then
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
	if perSecond >= 1_000_000_000_000 then
		return string.format("+$%.1fT/s", perSecond / 1_000_000_000_000)
	elseif perSecond >= 1_000_000_000 then
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
	-- the bundle, the balance and the income line together.
	local badge = Instance.new("Frame")
	badge.Name = "CashBadge"
	badge.Size = BADGE_SIZE
	badge.AnchorPoint = Vector2.new(0, 1)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 2
	badge.Parent = canvas

	ui.punch = Instance.new("UIScale")
	ui.punch.Parent = badge

	local L = LAYOUT
	-- Re-placed on every viewport change: a phone's thumbstick corner grows and shrinks
	-- with the screen (Dock.sideLift).
	UIKit.onScaleChanged(function()
		bottom = Dock.CASH_BOTTOM + Dock.sideLift()
		badge.Position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 1, -bottom)
	end)

	Artwork.droppedPicture(badge, "Bundle", Artwork.IMAGE.cashBundle, L.icon, L.iconDrop, 3)

	ui.value = UIKit.hudNumber(badge, {
		name = "Value",
		position = UDim2.fromOffset(L.valueLeft, L.valueTop),
		size = UDim2.fromOffset(BADGE_W - L.valueLeft - 12, L.valueHeight),
		font = STYLE.valueFont,
		textSize = L.valueTextSize,
		color = STYLE.value,
		xAlign = Enum.TextXAlignment.Left,
		text = "$0",
		zIndex = 11,
	}, L.valueStroke, L.textDrop)

	-- Hidden until something is earning.
	ui.rate = UIKit.hudNumber(badge, {
		name = "Rate",
		position = UDim2.fromOffset(L.valueLeft + 2, L.rateTop),
		size = UDim2.fromOffset(BADGE_W - L.valueLeft - 12, L.rateHeight),
		font = STYLE.rateFont,
		textSize = L.rateTextSize,
		color = STYLE.rate,
		xAlign = Enum.TextXAlignment.Left,
		visible = false,
		zIndex = 11,
	}, L.rateStroke, Vector2.new(1, 2))

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
	-- Sales and spends come off the end of the balance; stand payouts come off the end
	-- of the income line they are the income of, one lane lower, so a payout landing
	-- mid-sale never spawns on top of the sale's popup.
	local source: TextLabel = if quiet and ui.rate.Visible then ui.rate else ui.value
	local textEnd = source.Position.X.Offset + textWidth(source.Text, source.TextSize, source.Font)
	local middle = source.Position.Y.Offset + source.Size.Y.Offset / 2
	local start = UDim2.new(0, Dock.ROW_SIDE_MARGIN + textEnd + POPUP.gap, 1, middle - BADGE_H - bottom)

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

-- CashState `source` -> the cue it plays (Sfx.luau). Untagged changes (the /cash
-- debug command, refunds) and exhibit income make no sound.
local SOURCE_CUE: { [string]: string } = {
	spend = "purchase",
	sell = "sell",
	sellAll = "sellAll",
	away = "awayCollect",
}

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
	-- The till's voice, keyed off WHY the balance moved (EconomyService tags every
	-- push). Exhibit payouts stay silent for the same reason they get no punch.
	local cue = SOURCE_CUE[source or ""]
	if cue then
		Sfx.play(cue)
	end
end

local function setRate(perSecond: number)
	local earning = perSecond > 0
	ui.rate.Visible = earning
	if earning then
		ui.rate.Text = formatRate(perSecond)
	end
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
