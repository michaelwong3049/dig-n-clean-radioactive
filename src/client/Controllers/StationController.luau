--[[
	StationController.lua — the base camp panel.

	Appears when you are standing at the decon station or the trader, and lists what is
	in your bag. Select a row, then act on it. Placeholder art, real information: the
	point of Phase 1 is finding out whether the verbs feel good, and the verbs here are
	SCRUB, SELL and RACK.

	The panel deliberately shows the SAME list at both stations but offers different
	verbs, because that is the design's actual shape — the decon station is where the
	clock stops and dirt comes off, the trader is only a till.

	FIVE MODES, ONE PANEL, ONE REMOTE. decon/trader are the list above; shop, plot,
	pedestal and now roller each replace the list with their own body and hide the
	action row. Every one of them arrives on the SAME StationState tick (DeconService
	fills `offer` / `plotView` / `standView` / `rollerView` depending on where you
	stand), which is why adding a station kind has never needed a new remote and
	should not start needing one.

	ROLLER MODE SHOWS THE ODDS, and that is not generosity. The Luck track's entire
	product is a change in a probability, so a player who cannot watch Molten Lava go
	from 1.23% to 7.98% has no way to know the $6,640 charm did anything. It is the
	same argument the shop's card grid makes for drawing the whole ladder instead of
	only the next rung.

	THE PANEL SITS AT LITERAL SCREEN-CENTRE, AND IT DID NOT USED TO.
	It was anchored at `UDim2.new(0.5, 0, 0.5, -Dock.RESERVE / 2)` — centred in the
	space left ABOVE the dock rather than on the screen — because the dock's status
	line, dig button, radar scope and hotbar never hide, even away from a station.
	That bias is 173px of lift, and with the shop's cards it read as a panel stuck to
	the top of the screen rather than a panel in the middle of it.

	Two things make plain `fromScale(0.5, 0.5)` safe now. The radar scope moved out of
	the instrument band into its own bottom-right corner (see DetectorController), so
	the band lost 36px and RESERVE fell with it; and the status line is blank whenever
	you are out of a stage, which is exactly when a station panel is open (every
	station is in the zero-rad plaza). What is left below the centred panel is the dig
	button and the hotbar, both far enough down to clear it.

	This is the one thing here that is resolution-DEPENDENT rather than derived: a
	tall panel on a short viewport can still reach the dig button. StationHud's
	DisplayOrder (40) is below DetectorHud's (60), so the button wins that overlap
	rather than being hidden under the panel.

	THE SHOP IS A STOREFRONT, NOT A PROMPT. It used to render exactly one thing —
	"Bent Coil → Scavenger MkI", the deltas between them, and a BUY button — which
	answered "what can I buy right now" and nothing else. A player could not see that
	the Detector track runs eight tiers, what the top of it costs, or whether saving
	past the next rung was worth it. The panel now draws the WHOLE ladder as cards,
	worst on the left to best on the right, each with the tier's own stats and its
	price, with the one purchasable card the only solid-filled button on screen.

	ANY CARD YOU CAN AFFORD IS A LIVE BUTTON, NOT JUST THE NEXT ONE. `ShopService.buy`
	used to only ever sell `currentTier + 1`; now it sells whichever tier the clicked
	card names, at that tier's own price, as long as you do not already own it — buy
	The Oracle straight from Bent Coil and you pay The Oracle's price, nothing more.
	The shop still derives itself from the player's position server-side, so a card is
	still only ever a shop window into what THIS shop actually sells.

	THE ROW HEIGHT DID NOT GROW WITH EVERYTHING ELSE, ON PURPOSE. It multiplies across
	up to 12 rows (9 items + 3 locker) where every other element appears once — the
	"bigger" budget went into width, title, buttons and padding instead of a number
	that compounds twelve times. Even so, a maxed decon view (full bag, full locker) is
	the one case that can still reach into the dock's reserved band on a short
	viewport; DisplayOrder settles it (see build()) rather than the layout eliminating
	it outright, because it self-resolves the moment the player scrubs, sells or racks
	a single item.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Liquids = require(Shared.Config.Liquids)
local Net = require(Shared.Net)

-- No `Dock` alias any more: this panel is centred on the screen rather than on the
-- space above the dock, so it no longer reads Dock.RESERVE. See the header.
local UIKit = require(script.Parent.Parent.UIKit)

local Station = {}

-- Same fields UIKit.C already carries (panel/stroke/selected/text/dim/green/amber/
-- red/blue), aliased so every COLOR.xxx read below keeps working unchanged.
local COLOR = UIKit.C

local ROWS = 9
local LOCKER_ROWS = 3

-- The wash pad's shelf: one row per rollable liquid, plus Plain Water at the top.
-- Water is prepended CLIENT-SIDE rather than sent in the payload, because
-- LiquidService.viewFor is explicitly the ROLLABLE table and water is not rollable —
-- putting it in the server payload would mean either a weight-0 entry the roll code
-- has to keep skipping, or an odds column with a meaningless 0.00% in it.
local LIQUID_ROWS = #Liquids.ORDER

-- ── Shop card grid ──────────────────────────────────────────────────
-- The shop is a storefront now, not a one-line upgrade prompt: every tier of the
-- track laid out worst-to-best as cards in a horizontal scroller, so the ladder you
-- are climbing is visible before you have climbed it.
--
-- CARD_SLOTS IS A CEILING OVER ALL SIX TRACKS, NOT A GUESS. The longest is Detector
-- at 8 tiers (Config/Gear); the rest run 5-7. Cards are built once at that count and
-- hidden, the same reuse the item ROWS above have always used, because a shop panel
-- that rebuilds its children on every StationState tick would churn 8 frames' worth
-- of instances ten times a second.
local CARD_SLOTS = 8
local CARD_WIDTH = 270
local CARD_HEIGHT = 420
local CARD_GAP = 16

-- The panel widens for shop mode only, and the width is DERIVED from the card size
-- rather than typed: four whole cards, their three gaps, the panel's own padding, and
-- a deliberate 30px sliver of the fifth. The sliver is the scroll affordance — four
-- cards ending flush at the edge reads as "that is the whole stock", and nobody
-- scrolls a row they believe they can already see all of.
local PANEL_PAD = 16
local PANEL_WIDTH = 620
local SHOP_PANEL_WIDTH = 4 * CARD_WIDTH + 3 * CARD_GAP + 2 * PANEL_PAD + CARD_GAP + 30

-- THE WIDTHS ABOVE ARE A CEILING, NOT A SIZE, and that distinction is load-bearing.
-- The panel is laid out as "the viewport minus a margin, but never wider than the
-- ceiling" (Size scale 1 + a UISizeConstraint), so a big screen gets exactly the
-- four-card row the ceiling describes and a small one gets a narrower panel that
-- still fits, with the card row simply scrolling sooner. Sizing it at a flat
-- SHOP_PANEL_WIDTH offset put 200px of panel off each side of an 800px viewport —
-- the cards do not shrink to fit, so the panel has to.
local SCREEN_MARGIN = 24

local ui = {}
local state = { station = nil, items = {}, locker = {} }
local selected: string? = nil
local actionRemote: any = nil
local toastToken = 0

-- Player-closed, independent of whether the server still has you standing in the
-- station's radius. Walking away always closed the panel because that also zeroed
-- `state.station`; a CLOSE button doesn't move you, so it needs its own flag rather
-- than piggybacking on that field. `lastKey` is what clears it again: it fingerprints
-- "which station, which id" so the panel reopens the moment that changes -- leaving
-- and coming back, or walking straight from one station into another -- without
-- reopening on every one of the ~10Hz StationState ticks this same station keeps
-- sending while you stand still.
local dismissed = false
local lastKey: string? = nil

local function rarityColor(name: string): Color3
	local def = Rarity.DEFS[name]
	return if def then def.color else COLOR.text
end

-- ── Build ───────────────────────────────────────────────────────────

--- One item row. USED TO BE ONE TextButton whose whole Text was a single
--- string.format("%-22s %-7s %-7s $%d", ...) call — columns only lined up because
--- Font.Code is monospace, and no rounded display font has fixed character widths.
--- Four child labels instead: name flexes, condition/pips/value are fixed-width. The
--- button itself, its Uid attribute and its scrub-progress Fill are unchanged — only
--- what is drawn INSIDE it changes. Reached the same way Fill always was, via
--- Roblox's child-by-name lookup (row.ItemNameLabel, row.Fill, ...), so every
--- existing row.Visible / row:SetAttribute call elsewhere in this file needs no
--- changes at all.
--- One shelf row on the wash pad panel. Same shape as makeRow above — a TextButton
--- with fixed-width child labels rather than one monospaced string — and clicking it
--- IS the equip, exactly as clicking an item row is the selection. A separate LOAD
--- button per row would be nine more buttons for a verb the row already implies.
---
--- The colour chip is the row's real identity: nine liquid names in white are a list,
--- and the same nine with their own colours are a shelf you recognise at a glance,
--- matching the canisters on the pad's own geometry (build/Plots.buildWashPad).
local function makeLiquidRow(parent: Instance, order: number): TextButton
	local row = Instance.new("TextButton")
	row.Name = "LiquidRow"
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundColor3 = COLOR.selected
	row.BackgroundTransparency = 1
	row.AutoButtonColor = false
	row.Text = ""
	row.Visible = false
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.Size = UDim2.fromOffset(12, 12)
	chip.Position = UDim2.new(0, 6, 0.5, 0)
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.BorderSizePixel = 0
	chip.Parent = row

	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UIKit.Radius.pill
	chipCorner.Parent = chip

	UIKit.label(row, {
		name = "LiquidNameLabel",
		position = UDim2.fromOffset(26, 0),
		size = UDim2.fromOffset(150, 30),
		font = UIKit.Font.title,
		textSize = 15,
	})
	UIKit.label(row, {
		name = "LiquidStatLabel",
		position = UDim2.fromOffset(180, 0),
		size = UDim2.fromOffset(230, 30),
		font = UIKit.Font.body,
		textSize = 13,
		color = COLOR.dim,
	})
	UIKit.label(row, {
		name = "OddsLabel",
		position = UDim2.fromOffset(415, 0),
		size = UDim2.fromOffset(70, 30),
		font = UIKit.Font.body,
		textSize = 13,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Right,
	})
	UIKit.label(row, {
		name = "HeldLabel",
		position = UDim2.fromOffset(495, 0),
		size = UDim2.fromOffset(85, 30),
		font = UIKit.Font.body,
		textSize = 13,
		xAlign = Enum.TextXAlignment.Right,
	})

	return row
end

local function makeRow(parent: Instance, order: number): TextButton
	local row = Instance.new("TextButton")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundColor3 = COLOR.panel
	row.BackgroundTransparency = 1
	row.AutoButtonColor = false
	row.Text = ""
	row.Visible = false
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	-- scrub progress, drawn behind the labels
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COLOR.blue
	fill.BackgroundTransparency = 0.6
	fill.BorderSizePixel = 0
	fill.ZIndex = 0
	fill.Parent = row

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	UIKit.label(row, {
		name = "ItemNameLabel",
		position = UDim2.fromOffset(8, 0),
		size = UDim2.fromOffset(270, 26),
		font = UIKit.Font.body,
		textSize = 15,
	})
	UIKit.label(row, {
		name = "ConditionLabel",
		position = UDim2.fromOffset(286, 0),
		size = UDim2.fromOffset(90, 26),
		font = UIKit.Font.body,
		textSize = 15,
	})
	UIKit.label(row, {
		name = "PipsLabel",
		position = UDim2.fromOffset(384, 0),
		size = UDim2.fromOffset(80, 26),
		font = UIKit.Font.body,
		textSize = 15,
		xAlign = Enum.TextXAlignment.Center,
	})
	UIKit.label(row, {
		name = "ValueLabel",
		position = UDim2.fromOffset(472, 0),
		size = UDim2.fromOffset(108, 26),
		font = UIKit.Font.body,
		textSize = 15,
		xAlign = Enum.TextXAlignment.Right,
	})

	return row
end

--- One shop card: name, art well, stat block, purchase button.
---
--- THE ART WELL IS DELIBERATELY EMPTY. `CardArt` is a real ImageLabel with no Image
--- set, sized and positioned as the finished thing will be, so dropping in artwork
--- later is one assignment per tier and not a re-layout. It is not a placeholder
--- rectangle to be replaced — it is the frame the art goes in.
---
--- Children are reached by `card.CardXxx` at paint time, so none of them may be
--- named `Name`: every Instance already has a `.Name` property and Roblox never
--- falls back to child lookup when a property of that name exists, which would make
--- the label permanently unreachable. Hence `CardName`, matching `ItemNameLabel`
--- above for the same reason.
local function makeShopCard(parent: Instance, order: number): Frame
	local card = UIKit.panel(parent, {
		name = `Card{order}`,
		size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		color = COLOR.empty,
		transparency = 0.15,
		cornerRadius = UIKit.Radius.card,
		visible = false,
	})
	card.LayoutOrder = order

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = card

	-- 52 + 172 + 80 + 50 plus three 10px gaps = 384, inside the 388 the padding
	-- leaves. Fixed heights rather than AutomaticSize: every card in the row has to
	-- put its button on the same baseline, and a 2-line name on one card must not
	-- push that card's button below its neighbours'.
	local nameLabel = UIKit.label(card, {
		name = "CardName",
		size = UDim2.new(1, 0, 0, 52),
		font = UIKit.Font.title,
		textSize = 21,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
	})
	nameLabel.LayoutOrder = 1

	local art = Instance.new("ImageLabel")
	art.Name = "CardArt"
	art.LayoutOrder = 2
	art.Size = UDim2.new(1, 0, 0, 172)
	art.BackgroundColor3 = COLOR.panel
	art.BackgroundTransparency = 0.35
	art.BorderSizePixel = 0
	art.Image = ""
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = card

	local artCorner = Instance.new("UICorner")
	artCorner.CornerRadius = UDim.new(0, 12)
	artCorner.Parent = art

	local stats = UIKit.label(card, {
		name = "CardStats",
		size = UDim2.new(1, 0, 0, 80),
		font = UIKit.Font.body,
		textSize = 16,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
		yAlign = Enum.TextYAlignment.Top,
		wrapped = true,
	})
	stats.LayoutOrder = 3

	local buy = UIKit.button(card, {
		name = "CardBuy",
		size = UDim2.new(1, 0, 0, 50),
		font = UIKit.Font.title,
		textSize = 18,
		cornerRadius = UDim.new(0, 12),
		strokeThickness = UIKit.Stroke.thin,
	})
	buy.LayoutOrder = 4

	return card
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "StationHud"
	gui.ResetOnSpawn = false
	-- FALSE, AND THIS IS THE WHOLE "IT LOOKS TOO HIGH" BUG. IgnoreGuiInset = true
	-- shifts a ScreenGui's origin UP by the topbar inset (58px here), so a child at
	-- Position 0.5/AnchorPoint 0.5 centres in a coordinate space that starts above
	-- the screen — it measures as perfectly centred and renders 58px high. Every
	-- other HUD wants that, because they anchor to the BOTTOM edge where the inset
	-- does not matter. This panel is the only one anchored to the middle, so it is
	-- the only one the inset misplaces. With it off, the panel centres in the region
	-- the player can actually see, below the topbar.
	gui.IgnoreGuiInset = false
	-- Below the dock (60) on purpose — see the file header. The rad meter and the
	-- hotbar never hide, and exposure from a hot bag keeps accruing even while this
	-- panel is open, so the dock is the one thing that should never end up covered.
	gui.DisplayOrder = 40
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel, panelStroke = UIKit.panel(gui, {
		name = "Panel",
		size = UDim2.new(1, -2 * SCREEN_MARGIN, 0, 0),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = COLOR.panel,
		transparency = 0.08,
		cornerRadius = UIKit.Radius.panel,
		automaticSizeY = true,
		visible = false,
	})
	ui.panel = panel
	ui.panelStroke = panelStroke

	-- Parented to `gui`, a SIBLING of the panel, not a child of it. Every direct
	-- child of `panel` is claimed by the UIListLayout added near the bottom of this
	-- function -- a close button dropped in there would become another row in the
	-- stack, not a badge floating over a corner. Living outside that layout means
	-- tracking the panel's own corner by hand instead of getting it for free, hence
	-- repositionClose() below, re-run whenever the panel moves or resizes (it does
	-- both: automaticSizeY, and MaxSize swaps between shop/list widths per mode).
	local closeButton = UIKit.button(gui, {
		name = "Close",
		size = UDim2.fromOffset(32, 32),
		anchorPoint = Vector2.new(1, 0),
		font = UIKit.Font.title,
		textSize = 20,
		color = Color3.new(1, 1, 1),
		fillColor = COLOR.red,
		fillTransparency = 0,
		cornerRadius = UDim.new(0, 10),
		strokeThickness = 0,
		text = "\u{2715}",
	})
	closeButton.ZIndex = 10
	ui.closeButton = closeButton

	local function repositionClose()
		closeButton.Position = UDim2.fromOffset(
			panel.AbsolutePosition.X + panel.AbsoluteSize.X - 14,
			panel.AbsolutePosition.Y + 14
		)
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionClose)
	panel:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionClose)
	repositionClose()

	-- The ceiling half of "viewport minus a margin, but never wider than". render()
	-- retunes MaxSize.X per mode; MinSize stops a phone-width viewport collapsing the
	-- panel to something narrower than one card.
	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = Vector2.new(CARD_WIDTH + 2 * PANEL_PAD, 0)
	panelSize.MaxSize = Vector2.new(PANEL_WIDTH, math.huge)
	panelSize.Parent = panel
	ui.panelSize = panelSize

	-- ── Shop mode ────────────────────────────────────────────────────
	-- A shop IS a station, so it reuses this panel and the StationState /
	-- StationAction / StationResult triad rather than inventing a parallel one.
	-- The panel already "shows the same list at both stations but offers different
	-- verbs"; the shop is a third verb set on the same surface.
	local shop = Instance.new("Frame")
	shop.Name = "Shop"
	shop.LayoutOrder = 25
	shop.Size = UDim2.fromScale(1, 0)
	shop.AutomaticSize = Enum.AutomaticSize.Y
	shop.BackgroundTransparency = 1
	shop.Visible = false
	shop.Parent = panel
	ui.shop = shop

	local shopLayout = Instance.new("UIListLayout")
	shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
	shopLayout.Padding = UDim.new(0, 10)
	shopLayout.Parent = shop

	-- The storefront row. AutomaticCanvasSize.X + a horizontal UIListLayout means the
	-- canvas is whatever the visible cards add up to, so a 5-tier track scrolls less
	-- far than an 8-tier one without anyone computing a canvas width.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.LayoutOrder = 1
	scroll.Size = UDim2.new(1, 0, 0, CARD_HEIGHT + 18)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = COLOR.dim
	scroll.ScrollBarImageTransparency = 0.3
	scroll.Parent = shop
	ui.shopScroll = scroll

	local cardLayout = Instance.new("UIListLayout")
	cardLayout.FillDirection = Enum.FillDirection.Horizontal
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.Padding = UDim.new(0, CARD_GAP)
	cardLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	cardLayout.Parent = scroll

	ui.shopCards = {}
	for index = 1, CARD_SLOTS do
		table.insert(ui.shopCards, makeShopCard(scroll, index))
	end

	-- Shown instead of the row when a shop has no track behind it at all.
	ui.shopEmpty = UIKit.label(shop, {
		name = "Empty",
		size = UDim2.new(1, 0, 0, 28),
		font = UIKit.Font.body,
		textSize = 16,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
		text = "nothing for sale here",
		visible = false,
	})
	ui.shopEmpty.LayoutOrder = 2

	-- The wallet lives under the row, the way the reference storefront has it —
	-- last thing you read before you decide, rather than a number in the header.
	ui.shopCash = UIKit.label(shop, {
		name = "Cash",
		size = UDim2.new(1, 0, 0, 36),
		font = UIKit.Font.title,
		textSize = 25,
		color = COLOR.green,
	})
	ui.shopCash.LayoutOrder = 3

	-- ── Plot mode (claim board) ─────────────────────────────────────────
	-- Same reasoning as Shop mode: a claim board IS a station, so it reuses
	-- this panel and the StationAction triad rather than a parallel one.
	local plot = Instance.new("Frame")
	plot.Name = "Plot"
	plot.LayoutOrder = 26
	plot.Size = UDim2.fromScale(1, 0)
	plot.AutomaticSize = Enum.AutomaticSize.Y
	plot.BackgroundTransparency = 1
	plot.Visible = false
	plot.Parent = panel
	ui.plot = plot

	local plotLayout = Instance.new("UIListLayout")
	plotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	plotLayout.Padding = UDim.new(0, 8)
	plotLayout.Parent = plot

	ui.plotBanked = UIKit.label(plot, {
		name = "Banked",
		size = UDim2.new(1, 0, 0, 26),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.green,
	})
	ui.plotBanked.LayoutOrder = 1

	ui.collectButton = UIKit.button(plot, {
		name = "Collect",
		size = UDim2.new(1, 0, 0, 48),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.green,
		fillTransparency = 0.25,
		text = "COLLECT",
	})
	ui.collectButton.LayoutOrder = 2

	ui.slotsInfo = UIKit.label(plot, {
		name = "SlotsInfo",
		size = UDim2.new(1, 0, 0, 24),
		font = UIKit.Font.body,
		textSize = 15,
		color = COLOR.dim,
	})
	ui.slotsInfo.LayoutOrder = 3

	ui.buySlotButton = UIKit.button(plot, {
		name = "BuySlot",
		size = UDim2.new(1, 0, 0, 48),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.amber,
		fillTransparency = 0.25,
		text = "BUY SLOT",
	})
	ui.buySlotButton.LayoutOrder = 4

	-- ── Pedestal mode (stand) ────────────────────────────────────────────
	-- Empty+unlocked reuses the SAME carry rows the decon/trader panel already
	-- draws — "an item picker" is just those rows with a different verb attached,
	-- exactly like Shop mode reused the panel instead of inventing new list UI.
	local pedestal = Instance.new("Frame")
	pedestal.Name = "Pedestal"
	pedestal.LayoutOrder = 27
	pedestal.Size = UDim2.fromScale(1, 0)
	pedestal.AutomaticSize = Enum.AutomaticSize.Y
	pedestal.BackgroundTransparency = 1
	pedestal.Visible = false
	pedestal.Parent = panel
	ui.pedestal = pedestal

	local pedestalLayout = Instance.new("UIListLayout")
	pedestalLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pedestalLayout.Padding = UDim.new(0, 8)
	pedestalLayout.Parent = pedestal

	ui.standInfo = UIKit.label(pedestal, {
		name = "StandInfo",
		size = UDim2.new(1, 0, 0, 26),
		font = UIKit.Font.body,
		textSize = 16,
		color = COLOR.text,
	})
	ui.standInfo.LayoutOrder = 1

	ui.displayButton = UIKit.button(pedestal, {
		name = "Display",
		size = UDim2.new(1, 0, 0, 48),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.green,
		fillTransparency = 0.25,
		text = "DISPLAY",
	})
	ui.displayButton.LayoutOrder = 2

	ui.undisplayButton = UIKit.button(pedestal, {
		name = "Undisplay",
		size = UDim2.new(1, 0, 0, 48),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.amber,
		fillTransparency = 0.25,
		text = "UNDISPLAY",
	})
	ui.undisplayButton.LayoutOrder = 3

	-- ── Roller mode (the wash pad) ───────────────────────────────────────
	-- The whole shelf, worst at the top, with the live odds beside each row. Showing
	-- the odds is not generosity, it is the only thing that makes the Luck track
	-- legible: a player who cannot see 1.23% become 7.98% has no way to tell that the
	-- $6,640 charm did anything at all. Same argument the shop's card grid makes for
	-- drawing the whole ladder instead of just the next rung.
	local roller = Instance.new("Frame")
	roller.Name = "Roller"
	roller.LayoutOrder = 28
	roller.Size = UDim2.fromScale(1, 0)
	roller.AutomaticSize = Enum.AutomaticSize.Y
	roller.BackgroundTransparency = 1
	roller.Visible = false
	roller.Parent = panel
	ui.roller = roller

	local rollerLayout = Instance.new("UIListLayout")
	rollerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rollerLayout.Padding = UDim.new(0, 2)
	rollerLayout.Parent = roller

	ui.rollerHint = UIKit.label(roller, {
		name = "RollerHint",
		size = UDim2.new(1, 0, 0, 26),
		font = UIKit.Font.body,
		textSize = 15,
		color = COLOR.green,
	})
	ui.rollerHint.LayoutOrder = 1

	ui.liquidRows = {}
	for index = 1, LIQUID_ROWS do
		table.insert(ui.liquidRows, makeLiquidRow(roller, 10 + index))
	end

	ui.rollerFooter = UIKit.label(roller, {
		name = "RollerFooter",
		size = UDim2.new(1, 0, 0, 24),
		font = UIKit.Font.body,
		textSize = 14,
		color = COLOR.dim,
	})
	ui.rollerFooter.LayoutOrder = 90

	-- PANEL_PAD, not a literal 16: SHOP_PANEL_WIDTH is derived from this, so a typed
	-- number here would silently stop four cards fitting the moment it was retuned.
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PANEL_PAD)
	padding.PaddingBottom = UDim.new(0, PANEL_PAD)
	padding.PaddingLeft = UDim.new(0, PANEL_PAD)
	padding.PaddingRight = UDim.new(0, PANEL_PAD)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	ui.title = UIKit.label(panel, {
		name = "Title",
		size = UDim2.new(1, 0, 0, 44),
		font = UIKit.Font.title,
		textSize = 34,
		color = COLOR.text,
	})
	ui.title.LayoutOrder = 1

	ui.subtitle = UIKit.label(panel, {
		name = "Subtitle",
		size = UDim2.new(1, 0, 0, 20),
		font = UIKit.Font.body,
		textSize = 16,
		color = COLOR.dim,
	})
	ui.subtitle.LayoutOrder = 2

	ui.rows = {}
	for index = 1, ROWS do
		table.insert(ui.rows, makeRow(panel, 10 + index))
	end

	ui.lockerTitle = UIKit.label(panel, {
		name = "LockerTitle",
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.body,
		textSize = 15,
		color = COLOR.red,
		visible = false,
	})
	ui.lockerTitle.LayoutOrder = 40

	ui.lockerRows = {}
	for index = 1, LOCKER_ROWS do
		table.insert(ui.lockerRows, makeRow(panel, 40 + index))
	end

	local actions = Instance.new("Frame")
	actions.LayoutOrder = 60
	actions.Size = UDim2.new(1, 0, 0, 48)
	actions.BackgroundTransparency = 1
	actions.Parent = panel
	-- Hiding the three buttons individually is not enough: UIListLayout skips
	-- INVISIBLE children, so an empty-but-visible container still charges the panel
	-- its full 48px plus a gap. Shop/plot/pedestal modes all hide every button in
	-- here, and the shop is the tallest mode in the panel, so that dead band is the
	-- cheapest 54px available.
	ui.actions = actions

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Padding = UDim.new(0, 8)
	actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionLayout.Parent = actions

	ui.scrubButton = UIKit.button(actions, {
		name = "Scrub",
		size = UDim2.new(0.32, 0, 1, 0),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.blue,
		text = "HOLD TO SCRUB",
	})
	ui.scrubButton.LayoutOrder = 1

	ui.sellButton = UIKit.button(actions, {
		name = "Sell",
		size = UDim2.new(0.32, 0, 1, 0),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.amber,
		text = "SELL",
	})
	ui.sellButton.LayoutOrder = 2

	ui.rackButton = UIKit.button(actions, {
		name = "Rack",
		size = UDim2.new(0.32, 0, 1, 0),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.dim,
		text = "RACK",
	})
	ui.rackButton.LayoutOrder = 3

	ui.toast = UIKit.label(panel, {
		name = "Toast",
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.body,
		textSize = 16,
		color = COLOR.green,
	})
	ui.toast.LayoutOrder = 70

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

local function patchPips(item): string
	if item.clean then
		return "clean"
	end
	local pips = string.rep("\u{25CF}", math.min(#item.patches, 6))
	return pips
end

local function paintRow(row: TextButton, item, isSelected: boolean, scrubUid: string?, scrubProgress: number)
	row.Visible = true

	local colour = rarityColor(item.rarity)
	-- All four keep the SAME single colour, exactly as the old one-string row did —
	-- this is a rendering restructure, not a new visual design for the row.
	local nameLabel = row.ItemNameLabel :: TextLabel
	local conditionLabel = row.ConditionLabel :: TextLabel
	local pipsLabel = row.PipsLabel :: TextLabel
	local valueLabel = row.ValueLabel :: TextLabel

	nameLabel.Text = string.sub(item.name, 1, 26)
	nameLabel.TextColor3 = colour
	conditionLabel.Text = string.lower(item.condition)
	conditionLabel.TextColor3 = colour
	pipsLabel.Text = patchPips(item)
	pipsLabel.TextColor3 = colour
	valueLabel.Text = `${item.value}`
	valueLabel.TextColor3 = colour

	row.BackgroundTransparency = if isSelected then 0.55 else 1
	row.BackgroundColor3 = COLOR.selected
	row.Fill.Size = if scrubUid == item.uid then UDim2.fromScale(scrubProgress, 1) else UDim2.fromScale(0, 1)
	row:SetAttribute("Uid", item.uid)
end

--- Three states, and two of them are a button you can press.
---
--- Every tier past what you already own is buyable now — there is no locked-because-
--- you-skipped-a-rung state left to draw, so this is only ever current / owned /
--- buyable. OWNED still renders as dead chrome (bought, greyed, price gone) so it
--- reads as behind you rather than as a goal; buyable always shows its own price and
--- is always a live button, just split green/red by whether THIS tier's price fits
--- what you have right now.
local function paintShopCard(card: Frame, entry)
	local nameLabel = card.CardName :: TextLabel
	local stats = card.CardStats :: TextLabel
	local buy = card.CardBuy :: TextButton
	local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	local buyStroke = buy:FindFirstChildOfClass("UIStroke") :: UIStroke

	nameLabel.Text = entry.name
	stats.Text = table.concat(entry.stats, "\n")
	card:SetAttribute("Buyable", entry.buyable == true)
	card:SetAttribute("Tier", entry.tier)

	if entry.current then
		nameLabel.TextColor3 = COLOR.green
		cardStroke.Color = COLOR.green
		cardStroke.Thickness = UIKit.Stroke.normal
		buy.Text = "EQUIPPED"
		-- Light text on a green WASH, not green text on black. Saturated green at
		-- 14px bold over near-black smears into an illegible bar at play-window
		-- scale — the green still reads as "this one is yours" through the fill and
		-- the card's stroke, where it has area to be seen in.
		buy.TextColor3 = COLOR.text
		buy.BackgroundColor3 = COLOR.green
		buy.BackgroundTransparency = 0.78
		buyStroke.Color = COLOR.green
	elseif entry.owned then
		nameLabel.TextColor3 = COLOR.dim
		cardStroke.Color = COLOR.stroke
		cardStroke.Thickness = UIKit.Stroke.thin
		buy.Text = "OWNED"
		buy.TextColor3 = COLOR.dim
		buy.BackgroundColor3 = COLOR.panel
		buy.BackgroundTransparency = 0.6
		buyStroke.Color = COLOR.stroke
	elseif entry.buyable then
		nameLabel.TextColor3 = COLOR.text
		cardStroke.Color = if entry.affordable then COLOR.green else COLOR.red
		cardStroke.Thickness = UIKit.Stroke.normal
		buy.Text = `Purchase  ${entry.price}`
		-- Affordable is the ONE solid fill anywhere on this panel. Everything else
		-- is outlined or washed, so the single thing worth clicking is the single
		-- thing that looks clickable.
		--
		-- Can't-afford gets the same light-text-on-a-wash treatment as EQUIPPED, for
		-- the same reason: saturated red at 14px bold over near-black smears into an
		-- unreadable bar. The colour lives in the fill and the card stroke, where it
		-- has the area to carry it.
		buy.TextColor3 = if entry.affordable then COLOR.panel else COLOR.text
		buy.BackgroundColor3 = if entry.affordable then COLOR.green else COLOR.red
		buy.BackgroundTransparency = if entry.affordable then 0 else 0.8
		buyStroke.Color = if entry.affordable then COLOR.green else COLOR.red
	end
	-- No trailing `else`: current, owned and buyable are exhaustive over every tier
	-- (current ⊂ owned by tier number, buyable is everything else), so there is no
	-- fourth case left to paint.
end

--- The wash pad's shelf. Water first and always, then every rollable liquid worst to
--- best in Liquids.ORDER.
---
--- WATER IS SYNTHESISED HERE, and it is the only row not present in the payload —
--- see LIQUID_ROWS above for why the server does not send it. It gets an infinity
--- glyph rather than a count and a blank odds cell rather than 0.00%, because both
--- of those are statements about a liquid the pad cannot hand you and never charges
--- you for.
local function paintShelf(view)
	local water = Liquids.get(Liquids.WATER)
	local rows: { any } = {
		{
			id = Liquids.WATER,
			name = water.name,
			color = water.color,
			potency = water.potency,
			rateMult = water.rateMult,
			xpMult = water.xpMult,
			charges = 0,
			odds = nil,
			held = -1, -- the sentinel for "unlimited", never rendered as a number
		},
	}
	for _, entry in view.liquids or {} do
		table.insert(rows, entry)
	end

	for index, row in ui.liquidRows do
		local entry = rows[index]
		if entry == nil then
			row.Visible = false
			continue
		end

		row.Visible = true
		local colour = Color3.fromHex(entry.color)
		local loaded = entry.id == view.equipped
		-- Held is what makes a row clickable, and water is always held. Anything at
		-- zero is a preview of something you do not own -- readable, and deliberately
		-- not a button, so a click never silently does nothing.
		local owned = entry.held ~= 0

		row.Chip.BackgroundColor3 = colour

		local nameLabel = row.LiquidNameLabel :: TextLabel
		nameLabel.Text = entry.name
		nameLabel.TextColor3 = if owned then colour else COLOR.dim

		local statLabel = row.LiquidStatLabel :: TextLabel
		local parts = {}
		if entry.potency > 0 then
			table.insert(parts, `+{entry.potency} pot`)
		end
		table.insert(parts, string.format("%.2gx speed", entry.rateMult))
		if entry.xpMult ~= 1 then
			table.insert(parts, string.format("%.2gx XP", entry.xpMult))
		end
		if entry.charges > 0 then
			table.insert(parts, `{entry.charges}/roll`)
		end
		statLabel.Text = table.concat(parts, "  ")

		local oddsLabel = row.OddsLabel :: TextLabel
		oddsLabel.Text = if entry.odds then string.format("%.2f%%", entry.odds * 100) else ""

		local heldLabel = row.HeldLabel :: TextLabel
		if entry.held < 0 then
			heldLabel.Text = if loaded then "\u{221E}  LOADED" else "\u{221E}"
		elseif entry.held == 0 then
			heldLabel.Text = ""
		else
			heldLabel.Text = if loaded then `x{entry.held}  LOADED` else `x{entry.held}`
		end
		heldLabel.TextColor3 = if loaded then COLOR.green else COLOR.dim

		row.BackgroundTransparency = if loaded then 0.55 else 1
		row:SetAttribute("Liquid", if owned then entry.id else nil)
	end
end

local function render()
	if state.station == nil or dismissed then
		ui.panel.Visible = false
		ui.closeButton.Visible = false
		return
	end

	ui.panel.Visible = true
	ui.closeButton.Visible = true

	-- Shop mode replaces the item list entirely: you are not carrying anything
	-- relevant to this transaction, so showing your backpack is noise.
	local atShop = state.station == "shop"
	local atPlot = state.station == "plot"
	local atPedestal = state.station == "pedestal"
	local atRoller = state.station == "roller"
	ui.shop.Visible = atShop
	ui.plot.Visible = atPlot
	ui.pedestal.Visible = atPedestal
	ui.roller.Visible = atRoller
	-- Shop mode carries its own wallet line under the card row, so the header's
	-- subtitle would just print the same number twice.
	ui.subtitle.Visible = not atShop
	ui.actions.Visible = not (atShop or atPlot or atPedestal or atRoller)
	-- Storefronts centre their sign; a station panel that is really a list keeps its
	-- title on the same left margin as the rows underneath it.
	ui.title.TextXAlignment = if atShop then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	ui.panelSize.MaxSize = Vector2.new(if atShop then SHOP_PANEL_WIDTH else PANEL_WIDTH, math.huge)
	if atShop then
		local offer = state.offer
		local tiers = if offer then offer.tiers else nil

		ui.title.Text = `{string.upper(state.stationId or "SHOP")} SHOP`
		ui.title.TextColor3 = COLOR.amber
		ui.panelStroke.Color = COLOR.amber

		local count = if tiers then #tiers else 0
		ui.shopScroll.Visible = count > 0
		ui.shopEmpty.Visible = count == 0

		for index, card in ui.shopCards do
			local entry = if tiers then tiers[index] else nil
			card.Visible = entry ~= nil
			if entry then
				paintShopCard(card, entry)
			end
		end

		-- Reads as the wallet, not as a stat line: this is the number the whole
		-- row of prices is being compared against.
		ui.shopCash.Text = string.format("You have  $%d", state.cash or 0)
		ui.shopCash.TextColor3 = if offer and offer.maxed then COLOR.green else COLOR.text

		for _, row in ui.rows do
			row.Visible = false
		end
		for _, row in ui.lockerRows do
			row.Visible = false
		end
		ui.lockerTitle.Visible = false
		ui.scrubButton.Visible = false
		ui.rackButton.Visible = false
		ui.sellButton.Visible = false
		return
	end

	if atPlot then
		local view = state.plotView
		ui.title.Text = if view then `PLOT {view.plotIndex}` else "CLAIM BOARD"
		ui.title.TextColor3 = COLOR.green
		ui.panelStroke.Color = COLOR.green
		ui.subtitle.Text = if view and view.isOwner then "your plot" else "not your plot"

		if view and view.isOwner then
			ui.plotBanked.Text = string.format("banked  $%d", view.bankedCash)
			ui.collectButton.Visible = true
			ui.collectButton.Text = string.format("COLLECT  $%d", view.bankedCash)
			ui.collectButton.TextColor3 = if view.bankedCash > 0 then COLOR.green else COLOR.dim

			ui.slotsInfo.Text = string.format("slots %d / %d", view.slots, view.maxSlots)
			if view.nextSlotPrice then
				ui.buySlotButton.Visible = true
				ui.buySlotButton.Text = string.format("BUY SLOT  $%d", view.nextSlotPrice)
			else
				ui.buySlotButton.Visible = false
			end
		else
			ui.plotBanked.Text = ""
			ui.collectButton.Visible = false
			ui.slotsInfo.Text = view and string.format("slots %d / %d", view.slots, view.maxSlots) or ""
			ui.buySlotButton.Visible = false
		end

		for _, row in ui.rows do
			row.Visible = false
		end
		for _, row in ui.lockerRows do
			row.Visible = false
		end
		ui.lockerTitle.Visible = false
		ui.scrubButton.Visible = false
		ui.rackButton.Visible = false
		ui.sellButton.Visible = false
		return
	end

	if atPedestal then
		local view = state.standView
		ui.title.Text = if view then `STAND {view.slot}` else "STAND"
		ui.title.TextColor3 = COLOR.blue
		ui.panelStroke.Color = COLOR.blue
		ui.subtitle.Text = if view and view.isOwner then "your plot" else "not your plot"

		-- A picker only makes sense on your own, unlocked, empty stand -- every
		-- other case is a status message with at most one verb.
		local showPicker = view ~= nil and view.isOwner and not view.locked and not view.occupied

		if view == nil or not view.isOwner then
			ui.standInfo.Text = "not your plot"
			ui.standInfo.TextColor3 = COLOR.dim
			ui.displayButton.Visible = false
			ui.undisplayButton.Visible = false
		elseif view.locked then
			ui.standInfo.Text = "locked \u{2014} buy this slot at the claim board"
			ui.standInfo.TextColor3 = COLOR.red
			ui.displayButton.Visible = false
			ui.undisplayButton.Visible = false
		elseif view.occupied then
			local left = view.uncrateSecondsLeft or 0
			if left > 0 then
				ui.standInfo.Text = string.format("%s \u{2014} crating, %ds left", view.itemName or "item", left)
				ui.standInfo.TextColor3 = COLOR.amber
				ui.undisplayButton.Visible = false
			else
				ui.standInfo.Text = string.format("%s (%s)", view.itemName or "item", view.rarity or "")
				ui.standInfo.TextColor3 = rarityColor(view.rarity or "")
				ui.undisplayButton.Visible = true
			end
			ui.displayButton.Visible = false
		else
			ui.standInfo.Text = "empty \u{2014} pick an item below"
			ui.standInfo.TextColor3 = COLOR.dim
			ui.displayButton.Visible = true
			ui.undisplayButton.Visible = false
		end

		-- Keep the selection valid against carry, same rule the decon/trader
		-- path uses below -- this panel picks from the SAME list.
		local stillThere = false
		for _, item in state.items do
			if item.uid == selected then
				stillThere = true
				break
			end
		end
		if not stillThere then
			selected = if #state.items > 0 then state.items[1].uid else nil
		end

		for index, row in ui.rows do
			local item = state.items[index]
			if item and showPicker then
				paintRow(row, item, item.uid == selected, nil, 0)
			else
				row.Visible = false
			end
		end
		for _, row in ui.lockerRows do
			row.Visible = false
		end
		ui.lockerTitle.Visible = false
		ui.scrubButton.Visible = false
		ui.rackButton.Visible = false
		ui.sellButton.Visible = false
		return
	end

	if atRoller then
		local view = state.rollerView
		ui.title.Text = "WASH PAD"
		ui.title.TextColor3 = COLOR.green
		ui.panelStroke.Color = COLOR.green

		if view == nil then
			ui.subtitle.Text = ""
			ui.rollerHint.Text = ""
			ui.rollerFooter.Text = ""
			for _, row in ui.liquidRows do
				row.Visible = false
			end
		else
			ui.subtitle.Text = string.format("$%d    luck %.2gx    $%d a roll", state.cash or 0, view.luck, view.cost)
			ui.rollerHint.Text = if (state.cash or 0) >= view.cost
				then "step off and back onto the plate to roll"
				else `you need ${view.cost} to roll \u{2014} Plain Water is always free`
			ui.rollerHint.TextColor3 = if (state.cash or 0) >= view.cost then COLOR.green else COLOR.red

			paintShelf(view)

			local bonus = (view.effectivePotency or 0) - (view.potency or 0)
			ui.rollerFooter.Text = if bonus > 0
				then string.format("loaded: %s \u{2014} potency %d (+%d from the hose)", view.equippedName, view.effectivePotency, bonus)
				else string.format("loaded: %s \u{2014} potency %d", view.equippedName, view.effectivePotency or 0)
		end

		for _, row in ui.rows do
			row.Visible = false
		end
		for _, row in ui.lockerRows do
			row.Visible = false
		end
		ui.lockerTitle.Visible = false
		ui.scrubButton.Visible = false
		ui.rackButton.Visible = false
		ui.sellButton.Visible = false
		return
	end

	local atDecon = state.station == "decon"
	ui.title.Text = if atDecon then "DECON STATION" else "TRADER"
	ui.title.TextColor3 = if atDecon then COLOR.blue else COLOR.amber
	ui.panelStroke.Color = if atDecon then COLOR.blue else COLOR.amber

	-- THE HOSE IS ON THE SUBTITLE, NEXT TO THE TOOL, because the two are added
	-- together and the player has to be able to see the sum. Showing only the
	-- cleaner's potency here while DeconService clears patches against
	-- cleaner + liquid is exactly the drift CarryService's own header warns about,
	-- one file up from the payload instead of inside it.
	local bonus = (state.effectivePotency or 0) - (state.potency or 0)
	ui.subtitle.Text = if atDecon
		then (
			if bonus > 0
				then string.format(
					"$%d    %s + %s (potency %d)    clocks stopped",
					state.cash or 0,
					state.cleanerName or "",
					state.liquidName or "",
					state.effectivePotency or 1
				)
				else string.format("$%d    %s (potency %d)    clocks stopped", state.cash or 0, state.cleanerName or "", state.potency or 1)
		)
		else string.format("$%d    dirty items sell at 20%%", state.cash or 0)

	-- keep the selection valid
	local stillThere = false
	for _, item in state.items do
		if item.uid == selected then stillThere = true break end
	end
	for _, item in state.locker do
		if item.uid == selected then stillThere = true break end
	end
	if not stillThere then
		selected = if #state.items > 0 then state.items[1].uid else nil
	end

	for index, row in ui.rows do
		local item = state.items[index]
		if item then
			paintRow(row, item, item.uid == selected, state.scrubUid, state.scrubProgress or 0)
		else
			row.Visible = false
		end
	end

	ui.lockerTitle.Visible = #state.locker > 0
	ui.lockerTitle.Text = `QUARANTINE LOCKER \u{2014} {#state.locker} waiting on a better cleaner`
	for index, row in ui.lockerRows do
		local item = state.locker[index]
		if item then
			paintRow(row, item, item.uid == selected, nil, 0)
		else
			row.Visible = false
		end
	end

	-- Find the selected item to label the buttons honestly.
	local chosen = nil
	for _, item in state.items do
		if item.uid == selected then chosen = item break end
	end
	if chosen == nil then
		for _, item in state.locker do
			if item.uid == selected then chosen = item break end
		end
	end

	ui.scrubButton.Visible = atDecon
	ui.rackButton.Visible = atDecon
	ui.sellButton.Visible = not atDecon

	if chosen and chosen.blockedBy then
		-- Name the liquid when one would close the gap. A player three feet from a
		-- wash pad can act on "NEEDS MOLTEN LAVA" this minute; "NEEDS CHEM BATH" is
		-- a savings target. Both are true, and the actionable one goes on the button.
		ui.scrubButton.Text = if chosen.rescueLiquid
			then `ROLL FOR {string.upper(chosen.rescueLiquid)}`
			else `NEEDS {string.upper(chosen.needs or "")}`
		ui.scrubButton.TextColor3 = COLOR.red
	elseif chosen and chosen.clean then
		ui.scrubButton.Text = "CLEAN"
		ui.scrubButton.TextColor3 = COLOR.green
	elseif chosen and chosen.unlockedByLiquid then
		-- The hose is the ONLY reason this item is scrubbable, so say so: without
		-- it the player reads a green button and concludes their cleaner got better,
		-- then watches the same item lock again when the canister empties.
		ui.scrubButton.Text = "HOLD \u{2014} HOSE ONLY"
		ui.scrubButton.TextColor3 = COLOR.amber
	else
		ui.scrubButton.Text = "HOLD TO SCRUB"
		ui.scrubButton.TextColor3 = COLOR.blue
	end

	ui.sellButton.Text = if chosen then `SELL  ${chosen.value}` else "SELL"
end

--- Read by InventoryController: the hotbar detail card hides itself while this
--- panel is actually on screen, which is "the server says you're at a station" AND
--- "you haven't closed it" -- either one alone would either leave the card hidden
--- forever after a CLOSE click, or bring it back overlapping a panel you're still
--- standing in front of.
function Station.isOpen(): boolean
	return state.station ~= nil and not dismissed
end

local function toast(message: string)
	ui.toast.Text = message
	toastToken += 1
	local token = toastToken
	task.delay(3.5, function()
		if token == toastToken then
			ui.toast.Text = ""
		end
	end)
end

-- ── Lifecycle ────────────────────────────────────────────────────────

function Station.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	actionRemote = Net.get("StationAction")

	local function bindRow(row: TextButton)
		row.MouseButton1Click:Connect(function()
			selected = row:GetAttribute("Uid")
			render()
		end)
	end
	for _, row in ui.rows do
		bindRow(row)
	end
	for _, row in ui.lockerRows do
		bindRow(row)
	end

	-- Clicking a shelf row IS the equip. Rows you do not own carry no Liquid
	-- attribute (paintShelf), so this fires on exactly the rows that can act.
	for _, row in ui.liquidRows do
		row.MouseButton1Click:Connect(function()
			local id = row:GetAttribute("Liquid")
			if id ~= nil then
				actionRemote:FireServer({ action = "equipLiquid", liquid = id })
			end
		end)
	end

	ui.scrubButton.MouseButton1Down:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "scrub", uid = selected, holding = true })
		end
	end)
	ui.scrubButton.MouseButton1Up:Connect(function()
		actionRemote:FireServer({ action = "scrub", holding = false })
	end)
	ui.scrubButton.MouseLeave:Connect(function()
		actionRemote:FireServer({ action = "scrub", holding = false })
	end)

	ui.sellButton.MouseButton1Click:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "sell", uid = selected })
		end
	end)

	-- Every card's button is bound, and now more than one can be live at once — any
	-- tier past what you own is a real purchase, not a preview. The request carries
	-- the clicked card's own tier; `Buyable` is presentation only (it is false on
	-- OWNED/EQUIPPED cards so clicking them is a no-op), never the security boundary
	-- — ShopService independently re-derives the shop you are standing at, validates
	-- the tier is real and not already owned, and prices it off Gear.tier() itself,
	-- so a crafted tier number buys nothing a genuine click could not.
	for _, card in ui.shopCards do
		local buy = card.CardBuy :: TextButton
		buy.MouseButton1Click:Connect(function()
			if card:GetAttribute("Buyable") and state.stationId then
				actionRemote:FireServer({ action = "buy", track = state.stationId, tier = card:GetAttribute("Tier") })
			end
		end)
	end

	ui.rackButton.MouseButton1Click:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "rack", uid = selected })
		end
	end)

	ui.collectButton.MouseButton1Click:Connect(function()
		actionRemote:FireServer({ action = "collect" })
	end)

	ui.buySlotButton.MouseButton1Click:Connect(function()
		actionRemote:FireServer({ action = "buySlot" })
	end)

	ui.displayButton.MouseButton1Click:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "display", uid = selected })
		end
	end)

	ui.undisplayButton.MouseButton1Click:Connect(function()
		actionRemote:FireServer({ action = "undisplay" })
	end)

	ui.closeButton.MouseButton1Click:Connect(function()
		dismissed = true
		render()
	end)

	Net.get("StationState").OnClientEvent:Connect(function(payload)
		-- Fingerprint "which station, which id" rather than comparing tables: this
		-- fires at TICK_RATE (~10Hz) the whole time you stand still, and payload is a
		-- new table every tick, so an equality check on it would never match and
		-- `dismissed` would clear itself on the very next tick after the click above.
		local key = if payload.station then `{payload.station}:{tostring(payload.stationId)}` else nil
		if key ~= lastKey then
			dismissed = false
			lastKey = key
		end

		state = payload
		state.items = payload.items or {}
		state.locker = payload.locker or {}
		local ok, err = pcall(render)
		if not ok then
			warn(`[station] render failed: {err}`)
		end
	end)

	Net.get("StationResult").OnClientEvent:Connect(function(message)
		toast(tostring(message))
	end)
end

return Station
