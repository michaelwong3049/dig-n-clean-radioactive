--[[
	StationController.lua — the base camp panel.

	Appears at the trader, the shops, and the display stands. Select a row, then act
	on it. The one verb left on the list itself is SELL — scrubbing and racking both
	left this file, see below.

	TWO MODES NOW, AND THE SHRINKING IS THE POINT. shop and pedestal each replace the
	list with their own body; trader is the list itself. Both arrive on the SAME
	StationState tick (DeconService fills `offer` / `standView` depending on where you
	stand), which is why adding a station kind has never needed a new remote and
	should not start needing one. The plot claim board was a third mode until exhibit
	income went auto-deposit — with nothing left to COLLECT, the board and its panel
	both went.

	TWO MODES WERE DELETED, ON REQUEST, AND BOTH DELETIONS FIXED SOMETHING.

	The wash pad used to open a panel listing all ten liquids and their live odds.
	Stepping on a big lit button in the world and having a menu appear over the screen
	is a menu wearing a button's clothes; the pad answers in the world now (it flashes
	the rolled liquid's colour and names it on its own billboard, LiquidService).

	The decon station used to open the bag list with a HOLD TO SCRUB button. All of
	that moved to the tub — hold the item, press E, hose it — and removing the panel
	turned out to be load-bearing rather than cosmetic: it sat under the crosshair, so
	the click meant to start the spray arrived with `gameProcessedEvent` true and the
	hose never fired. "I press E and nothing happens" was this panel eating the input.

	WHAT WENT WITH THE DECON PANEL, stated plainly because it is a real loss: the RACK
	button and the Quarantine Locker rows. The locker still exists in the profile and
	DeconService still implements `rack`, but nothing in the world triggers it any
	more. PLAN §10.2 wants a physical locker anyway; see TODO §5b.

	PANEL_KINDS IS AN ALLOWLIST, NOT A FALLTHROUGH, and that is not stylistic. The
	trader branch is last and unguarded, so any station kind this file does not know
	about lands in it — which is exactly what happened the first time a mode was
	deleted: the wash pad started opening a panel titled TRADER.


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

	AND THE SHOP IS ALSO A RACK IN THE WORLD NOW, WHICH THIS FILE PAINTS BUT DOES NOT
	OWN. Every tier of the three tool tracks hangs on the wing beside its stand with a
	price card above it and its own E prompt (build/Shops), so a player who knows which
	detector they want buys it without ever opening this panel. The one thing those
	cards cannot show on their own is whether YOU own that tier — they are single
	shared instances — so the owned-check is written locally, off the same `offer` this
	panel is already receiving. See "The rack beside the stand" below for what it costs.
	The panel is still there and still holds the stat blocks, but it does not open on
	approach any more: press E on the stand for it. The rack is the fast path, the
	panel the one you ask for. See `dismissed`.

	THE SHOP PANEL IS A STOREFRONT, NOT A ONE-LINE OFFER. It used to render exactly
	one thing —
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
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

-- No `Dock` alias any more: this panel is centred on the screen rather than on the
-- space above the dock, so it no longer reads Dock.RESERVE. See the header.
local UIKit = require(script.Parent.Parent.UIKit)

local Station = {}

-- Same fields UIKit.C already carries (panel/stroke/selected/text/dim/green/amber/
-- red/blue), aliased so every COLOR.xxx read below keeps working unchanged.
local COLOR = UIKit.C

local ROWS = 9

-- WHICH STATION KINDS THIS PANEL HAS A BODY FOR, and it is an allowlist rather than
-- a fallthrough for a reason that bit immediately. The decon/trader branch is LAST in
-- render(), with no guard of its own, so it is what every unrecognised kind lands in
-- — and the moment the roller branch was deleted, standing on the wash pad opened a
-- panel titled TRADER. A station kind with no panel must open NOTHING, and the wash
-- pad is deliberately the first one: it is a button in the world, and the whole point
-- of this pass was that pressing it shows no UI at all.
--
-- DECON IS NOT IN HERE ANY MORE, ON REQUEST. Walking up to the cleansing station used
-- to open a panel over the screen; now the only thing there is the E prompt on the
-- tub, which is the whole interaction. It also fixed a bug nobody had diagnosed yet:
-- that panel sat under the crosshair, so the click that was supposed to start the
-- hose arrived with `gameProcessedEvent` true and the spray never began. "Nothing
-- happens" was the panel eating the input.
local PANEL_KINDS: { [string]: boolean } = {
	trader = true,
	shop = true,
	pedestal = true,
}

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

-- Hold-to-place on a pedestal (see the header's "Pedestal mode" note below). Kept
-- independent of `state`/`selected` because it is driven off-tick, every frame, and
-- has nothing to do with which row the trader panel has selected.
local heldUid: string = ""
local eKeyDown = false
local holdProgress = 0 -- seconds
local holdFired = false -- refuse to refire until E is released, once a hold lands

-- Player-closed, independent of whether the server still has you standing in the
-- station's radius. Walking away always closed the panel because that also zeroed
-- `state.station`; a CLOSE button doesn't move you, so it needs its own flag rather
-- than piggybacking on that field. `lastKey` is what clears it again: it fingerprints
-- "which station, which id" so the panel's open/closed state is decided ONCE the
-- moment that changes -- leaving and coming back, or walking straight from one
-- station into another -- without being re-decided on every one of the ~10Hz
-- StationState ticks this same station keeps sending while you stand still.
--
-- A SHOP ARRIVES DISMISSED, AND THAT IS THE WHOLE "PRESS E TO VIEW" FEATURE. Every
-- station kind used to un-dismiss on arrival, so walking within ten studs of a stall
-- put a full-screen panel over you whether you had come to buy or were cutting
-- across the plaza. Shops now start closed and open on the stand's own E prompt
-- (build/Shops' "ViewShop"); trader and pedestal still open on approach, because
-- neither has a prompt to open it with and neither is something you walk past.
--
-- This is the same call the wash pad and the decon station already went through, in
-- the same direction and for the same reason -- see the header. The panel is a place
-- you choose to go, not a thing that happens to you.
local dismissed = false
local lastKey: string? = nil

--- The name build/Shops gives the stand's own prompt. Hardcoded here for the same
--- reason RACK_TAG below is: this is a client script and build/Kit lives in
--- ServerScriptService, so it cannot be required.
local BROWSE_PROMPT = "ViewShop"

--- Does THIS shop actually have a browse prompt standing in the world?
---
--- THIS FUNCTION EXISTS BECAUSE CODE AND WORLD SHIP THROUGH DIFFERENT DOORS, and
--- getting that wrong took the whole shop off the map once. Scripts reach a place
--- through Rojo/publish the moment they are merged; the geometry in Workspace.Shops
--- only changes when somebody runs build/Shops.rebuild() in Edit and SAVES the place.
--- So the two can be any distance apart, and for a while they were: a world still
--- built to the version before the stand existed, running the client that had already
--- learned to wait for the stand's E.
---
--- The result was not a cosmetic mismatch. `dismissed` started true for every shop and
--- nothing in that world could ever set it false, so no shop panel could open at all —
--- and the Outfitter's three counters have never had rack prompts, which made Suit,
--- Boots and Satchel unbuyable outright. The Suit gates every stage in the game.
---
--- So the press-E behaviour is now CONDITIONAL ON THE THING THAT IMPLEMENTS IT being
--- present. A shop with a browse prompt opens on E; a shop without one falls back to
--- opening on approach, exactly as it did before any of this. A stale world is then
--- merely old, never broken, and the same is true in reverse for anyone who rebuilds
--- their world ahead of pulling the code.
---
--- Checked per station rather than "does this world have any prompts anywhere", so a
--- half-rebuilt world degrades per shop instead of all-or-nothing. It runs only when
--- the station fingerprint CHANGES, not on the ~10Hz tick.
local function shopHasBrowsePrompt(stationId: any): boolean
	if type(stationId) ~= "string" then
		return false
	end
	local shops = Workspace:FindFirstChild("Shops")
	if shops == nil then
		return false
	end
	for _, d in shops:GetDescendants() do
		if
			d:IsA("BasePart")
			and d:GetAttribute("StationKind") == "shop"
			and d:GetAttribute("StationId") == stationId
			and d:FindFirstChild(BROWSE_PROMPT) ~= nil
		then
			return true
		end
	end
	return false
end

local function rarityColor(name: string): Color3
	local def = Rarity.DEFS[name]
	return if def then def.color else COLOR.text
end

-- ── Build ───────────────────────────────────────────────────────────

--- One item row. USED TO BE ONE TextButton whose whole Text was a single
--- string.format("%-22s %-7s %-7s $%d", ...) call — columns only lined up because
--- Font.Code is monospace, and no rounded display font has fixed character widths.
--- Four child labels instead: name flexes, condition/pips/value are fixed-width. The
--- button itself and its Uid attribute are unchanged — only what is drawn INSIDE it
--- changes. Reached via Roblox's child-by-name lookup (row.ItemNameLabel, ...), so
--- every existing row.Visible / row:SetAttribute call elsewhere needs no changes.
---
--- The scrub-progress `Fill` that used to sit behind these labels is gone with the
--- scrub button: washing happens at the tub now and draws its progress there, on the
--- object being washed, where the player is actually looking.
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

	-- Plots have no panel any more: exhibit income auto-deposits into the owner's
	-- wallet (server-side ExhibitService), so the claim board — whose only verb was
	-- COLLECT — was removed along with the "plot" station kind.

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

	-- Replaces the old item-picker rows + DISPLAY button: placing is now "hold the
	-- item, hold E facing this stand", so the panel's only job here is to show that
	-- hold filling up. Track + fill rather than a button, since there is nothing to
	-- click any more.
	local holdTrack = UIKit.panel(pedestal, {
		name = "HoldTrack",
		size = UDim2.new(1, 0, 0, 10),
		color = COLOR.panel,
		transparency = 0.3,
		strokeThickness = 0,
		cornerRadius = UIKit.Radius.pill,
	})
	holdTrack.LayoutOrder = 2
	ui.holdTrack = holdTrack

	local holdFill = Instance.new("Frame")
	holdFill.Name = "Fill"
	holdFill.BackgroundColor3 = COLOR.blue
	holdFill.BorderSizePixel = 0
	holdFill.Size = UDim2.fromScale(0, 1)
	holdFill.Parent = holdTrack
	local holdFillCorner = Instance.new("UICorner")
	holdFillCorner.CornerRadius = UIKit.Radius.pill
	holdFillCorner.Parent = holdFill
	ui.holdFill = holdFill

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

	local actions = Instance.new("Frame")
	actions.LayoutOrder = 60
	actions.Size = UDim2.new(1, 0, 0, 48)
	actions.BackgroundTransparency = 1
	actions.Parent = panel
	-- Hiding the three buttons individually is not enough: UIListLayout skips
	-- INVISIBLE children, so an empty-but-visible container still charges the panel
	-- its full 48px plus a gap. Shop and pedestal modes both hide every button in
	-- here, and the shop is the tallest mode in the panel, so that dead band is the
	-- cheapest 54px available.
	ui.actions = actions

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Padding = UDim.new(0, 8)
	actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionLayout.Parent = actions

	-- The only button left in this row: RACK went with the decon panel.
	ui.sellButton = UIKit.button(actions, {
		name = "Sell",
		size = UDim2.fromScale(1, 1),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.amber,
		text = "SELL",
	})
	ui.sellButton.LayoutOrder = 2

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

local function paintRow(row: TextButton, item, isSelected: boolean)
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
	row:SetAttribute("Uid", item.uid)
end

--- Three states, and ALL THREE are now a button you can press.
---
--- OWNED STOPPED BEING DEAD CHROME, because it stopped meaning "behind you". While
--- ownership was a high-water mark, a greyed OWNED card was a rung you had walked
--- past and could never want again, so there was nothing to press. Ownership is a set
--- now: an owned card that is not the one in your hands is a tool you paid for and
--- are not currently holding, and the only sensible thing to draw on it is EQUIP.
---
--- current  -> EQUIPPED, green wash, inert (pressing it would be a no-op)
--- owned    -> EQUIP, live, neutral: yours, one press from being in your hands
--- buyable  -> its own price, live, green/red on whether you can afford THIS tier
local function paintShopCard(card: Frame, entry)
	local nameLabel = card.CardName :: TextLabel
	local stats = card.CardStats :: TextLabel
	local buy = card.CardBuy :: TextButton
	local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	local buyStroke = buy:FindFirstChildOfClass("UIStroke") :: UIStroke

	nameLabel.Text = entry.name
	stats.Text = table.concat(entry.stats, "\n")
	card:SetAttribute("Buyable", entry.buyable == true)
	card:SetAttribute("Equippable", entry.equippable == true)
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
		-- Yours, not in your hands. Drawn as a real affordance rather than the greyed
		-- slab this used to be: full-strength name, a normal-weight stroke and a
		-- pressable button. Deliberately NOT green — green is "this is the one you are
		-- holding" everywhere on this panel, and two greens would make the card you
		-- are using indistinguishable from the six you are not.
		nameLabel.TextColor3 = COLOR.text
		cardStroke.Color = COLOR.stroke
		cardStroke.Thickness = UIKit.Stroke.normal
		buy.Text = "EQUIP"
		buy.TextColor3 = COLOR.text
		buy.BackgroundColor3 = COLOR.panel
		buy.BackgroundTransparency = 0.35
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
	-- No trailing `else`: current, owned and buyable are exhaustive over every tier.
	-- `current` is checked first and `owned` second, so the equipped tier takes the
	-- EQUIPPED branch even though it is also owned, and `buyable` is by construction
	-- `not owned` — every tier lands in exactly one of the three.
end

-- ── The rack beside the stand ────────────────────────────────────────────────
--
-- THE OWNED-CHECK IS THE ONE PER-PLAYER THING ON A SHARED OBJECT. Every tier of the
-- three tool tracks hangs on a rail beside its shop's stand with its price on a card
-- above it (build/Shops' rack). That card is world geometry — one instance, seen by
-- everybody — so the server cannot write "you own this" onto it for one player. The
-- client can, locally, and nothing it writes replicates anywhere.
--
-- IT DRAWS OFF THE OFFER THIS PANEL IS ALREADY RECEIVING, and that is the whole
-- reason this lives here rather than in a controller of its own. `state.offer.tiers`
-- already carries an owned/current/buyable/affordable flag per tier, computed by
-- ShopService from the profile, and it already arrives on every StationState tick
-- while you are standing at the shop. So the checks cost no new remote, no new
-- replicated state and no client-side guess about what the player owns.
--
-- WHAT THAT COSTS, STATED PLAINLY: the checks only render while you are inside the
-- stall's station radius, because that is the only time the offer exists. Walk away
-- and the rack goes back to showing prices. That is the right trade at this size —
-- the cards' own MaxDistance is 28 studs, so they are barely legible from further
-- out anyway — but it is a trade, and the fix if it ever stops being one is to
-- replicate the gear tiers rather than to start guessing here.
--
-- AND IT IS WHY A STALL EMITS TWO STATION CIRCLES. When the rack moved off the
-- counter onto its own wing, a single tight circle on the stand would have blanked
-- every tick of this the moment a player walked over to the tools — the exact moment
-- the ticks are worth drawing. build/Shops answers that on its side, by putting the
-- same StationKind/StationId on the wing's shelf as well; nothing here had to change,
-- but this paragraph is why that duplication is load-bearing and not tidy-up bait.

--- Matches Kit.UPGRADE_TAG and ShopService's own copy. Hardcoded a third time for
--- the reason ShopService's copy gives: build/Kit lives in ServerScriptService and
--- cannot be required from a client script. The server's two are checked against
--- each other by World.verify(); this one announces a mismatch by the rack simply
--- never lighting up.
local RACK_TAG = "Upgrade"

--- U+2713 first, the word after it. FredokaOne has no check glyph of its own, so
--- this leans on Roblox's font fallback — and if that ever fails, what is left on the
--- card is the word, which still says the thing. A bare check would leave a tofu box.
---
--- TWO WORDS, NOT ONE, SINCE OWNERSHIP BECAME A SET. The rack used to paint one green
--- tick on every tier at or below yours, which is exactly the complaint that started
--- this: eight identical ticks after buying one detector, and no way to tell which
--- tool you were actually holding. EQUIPPED is the one in your hands; OWNED is a tool
--- you bought and are not using, and its hook's E switches to it rather than charging
--- you for it again.
local EQUIPPED_TEXT = "✓ EQUIPPED"
local OWNED_TEXT = "✓ OWNED"

--- Which (track, owned-through-tier) pair is currently painted onto the world.
--- StationState fires at ~10Hz for as long as you stand at a counter and almost
--- every one of those ticks says exactly what the last one did; without this the
--- tag index gets walked and 21 labels rewritten ten times a second to no effect.
local rackKey: string? = nil

--- Paint the per-player state onto `track`'s rack, and restore every other hook in
--- the world to the price it was built showing. `tiers` nil restores all of them —
--- that is what leaving a shop does.
---
--- THREE STATES OUT HERE NOW, MATCHING THE PANEL'S THREE. The equipped tier gets the
--- green EQUIPPED tick; a tier you own but are not holding gets a neutral OWNED tick
--- and its prompt flips from "Buy $x" to "Equip"; everything else keeps the price it
--- was built with. That prompt rewrite is the reason this function touches
--- ProximityPrompts at all — a prompt is a single shared instance and the server
--- cannot word it per player, exactly like the price cards.
---
--- WHAT THE PROMPT SAYS IS COSMETIC, AND THE SERVER DOES NOT TRUST IT. ShopService's
--- own handler re-reads ownership from the profile and picks buy-or-equip there. If
--- this paint is stale, the worst case is a prompt that says the wrong verb for one
--- tick, never a wrong purchase.
---
--- RESTORE READS RestText / RestColor OFF THE LABEL (and RestActionText off the
--- prompt), the same trick LiquidService uses to put the wash pad's sign back after
--- it announces a roll: the builder stamps the as-built values onto the instance
--- itself, so whatever overwrites it never has to remember what was there. A hook
--- with no SellsTier is skipped entirely rather than restored — that is the Luck
--- button, whose subtitle is owned by ExhibitService and must not be touched here.
local function paintRack(track: string?, tiers: { any }?)
	for _, part in CollectionService:GetTagged(RACK_TAG) do
		local tier = part:GetAttribute("SellsTier")
		if type(tier) ~= "number" then
			continue
		end

		local sign = part:FindFirstChild("Sign")
		local sub = if sign then sign:FindFirstChild("Subtitle") else nil
		if sub == nil or not sub:IsA("TextLabel") then
			continue
		end

		local entry = if tiers ~= nil and part:GetAttribute("SellsTrack") == track then tiers[tier] else nil
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")

		-- Stamp the as-built wording if the BUILDER did not. A world built before the
		-- rack learned about equipping has prompts with no RestActionText, and without
		-- this the first repaint would overwrite "Buy $4700" with "Equip" and have
		-- nothing to put back — the price would be gone from that hook until the next
		-- world rebuild. Doing it here, before any overwrite, makes the restore path
		-- correct in a stale world as well as a fresh one.
		if prompt and prompt:GetAttribute("RestActionText") == nil then
			prompt:SetAttribute("RestActionText", prompt.ActionText)
		end

		if entry ~= nil and entry.current then
			sub.Text = EQUIPPED_TEXT
			sub.TextColor3 = COLOR.green
			if prompt then
				-- Nothing to do to a tool you are already holding. The prompt stays
				-- visible rather than being disabled, because a hook with no E at all
				-- reads as broken next to seven that have one; pressing it is refused
				-- server-side with "already in your hands".
				prompt.ActionText = "Equipped"
			end
		elseif entry ~= nil and entry.owned then
			sub.Text = OWNED_TEXT
			sub.TextColor3 = COLOR.text
			if prompt then
				prompt.ActionText = "Equip"
			end
		else
			sub.Text = (sub:GetAttribute("RestText") :: string?) or sub.Text
			sub.TextColor3 = (sub:GetAttribute("RestColor") :: Color3?) or sub.TextColor3
			if prompt then
				prompt.ActionText = (prompt:GetAttribute("RestActionText") :: string?) or prompt.ActionText
			end
		end
	end
end

--- Repaint the rack only when the answer actually moved. Price and name are as-built
--- and affordability deliberately is not shown out here (that is what the panel's
--- cards are for), so the only things this rack can draw are which tiers are owned and
--- which one is equipped — and the key is exactly those two.
---
--- THE KEY IS THE WHOLE OWNED SET NOW, NOT ITS MAXIMUM. It used to be the top owned
--- tier, which was a complete description of an offer while ownership was a high-water
--- mark. With a set, {1,4,8} and {1,8} share a maximum and are different racks, and
--- equipping changes the paint without changing ownership at all. Both go in the
--- fingerprint or the repaint gets skipped and the rack lies until you walk away.
local function refreshRack()
	local atShop = state.station == "shop"
	local tiers = if atShop and state.offer then state.offer.tiers else nil

	local owned = {}
	local equipped = 0
	if tiers then
		for _, entry in tiers do
			if entry.owned then
				table.insert(owned, entry.tier)
			end
			if entry.current then
				equipped = entry.tier
			end
		end
	end

	local key = if tiers then `{tostring(state.stationId)}:{equipped}:{table.concat(owned, ",")}` else nil
	if key == rackKey then
		return
	end
	rackKey = key
	paintRack(state.stationId, tiers)
end

local function render()
	if state.station == nil or dismissed or not PANEL_KINDS[state.station] then
		ui.panel.Visible = false
		ui.closeButton.Visible = false
		return
	end

	ui.panel.Visible = true
	ui.closeButton.Visible = true

	-- Shop mode replaces the item list entirely: you are not carrying anything
	-- relevant to this transaction, so showing your backpack is noise.
	local atShop = state.station == "shop"
	local atPedestal = state.station == "pedestal"
	ui.shop.Visible = atShop
	ui.pedestal.Visible = atPedestal
	-- Shop mode carries its own wallet line under the card row, so the header's
	-- subtitle would just print the same number twice.
	ui.subtitle.Visible = not atShop
	ui.actions.Visible = not (atShop or atPedestal)
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
		ui.sellButton.Visible = false
		return
	end

	if atPedestal then
		local view = state.standView
		ui.title.Text = if view then `STAND {view.slot}` else "STAND"
		ui.title.TextColor3 = COLOR.blue
		ui.panelStroke.Color = COLOR.blue
		ui.subtitle.Text = if view and view.isOwner then "your plot" else "not your plot"

		-- Hold-to-place only makes sense on your own, empty stand -- every other
		-- case is a status message with nothing to fill.
		local canPlaceHere = view ~= nil and view.isOwner and not view.occupied

		if view == nil or not view.isOwner then
			ui.standInfo.Text = "not your plot"
			ui.standInfo.TextColor3 = COLOR.dim
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
		elseif heldUid == "" then
			ui.standInfo.Text = "empty \u{2014} hold an item, then hold E facing this stand"
			ui.standInfo.TextColor3 = COLOR.dim
			ui.undisplayButton.Visible = false
		else
			ui.standInfo.Text = "empty \u{2014} hold E to place what you're carrying"
			ui.standInfo.TextColor3 = COLOR.dim
			ui.undisplayButton.Visible = false
		end

		ui.holdTrack.Visible = canPlaceHere
		if not canPlaceHere then
			holdProgress = 0
			ui.holdFill.Size = UDim2.fromScale(0, 1)
		end

		for _, row in ui.rows do
			row.Visible = false
		end
		ui.sellButton.Visible = false
		return
	end

	-- TRADER ONLY down here now. This used to be the decon/trader fork; the decon half
	-- moved into the world (the tub's E prompt) and took the Quarantine Locker rows and
	-- the RACK button with it -- see this file's header.
	ui.title.Text = "TRADER"
	ui.title.TextColor3 = COLOR.amber
	ui.panelStroke.Color = COLOR.amber
	ui.subtitle.Text = string.format("$%d    dirty items sell at 20%%", state.cash or 0)

	-- keep the selection valid
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
		if item then
			paintRow(row, item, item.uid == selected)
		else
			row.Visible = false
		end
	end

	local chosen = nil
	for _, item in state.items do
		if item.uid == selected then
			chosen = item
			break
		end
	end

	ui.sellButton.Visible = true
	ui.sellButton.Text = if chosen then `SELL  ${chosen.value}` else "SELL"
end

--- Read by InventoryController: the hotbar detail card hides itself while this
--- panel is actually on screen, which is "the server says you're at a station" AND
--- "you haven't closed it" -- either one alone would either leave the card hidden
--- forever after a CLOSE click, or bring it back overlapping a panel you're still
--- standing in front of.
function Station.isOpen(): boolean
	return state.station ~= nil and PANEL_KINDS[state.station] == true and not dismissed
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
		-- ONE BUTTON, TWO VERBS. Which one this card is showing is already decided in
		-- paintShopCard and stamped on the card, so this reads the stamp rather than
		-- re-deriving it from an offer that may have ticked since. The server decides
		-- again regardless -- ShopService re-checks ownership on both paths -- so a
		-- stale attribute here can only ever produce a refused action, never a wrong one.
		buy.MouseButton1Click:Connect(function()
			if state.stationId == nil then
				return
			end
			if card:GetAttribute("Buyable") then
				actionRemote:FireServer({ action = "buy", track = state.stationId, tier = card:GetAttribute("Tier") })
			elseif card:GetAttribute("Equippable") then
				actionRemote:FireServer({ action = "equip", track = state.stationId, tier = card:GetAttribute("Tier") })
			end
		end)
	end

	ui.undisplayButton.MouseButton1Click:Connect(function()
		actionRemote:FireServer({ action = "undisplay" })
	end)

	ui.closeButton.MouseButton1Click:Connect(function()
		dismissed = true
		render()
	end)

	-- THE STAND'S E. Fires locally for the local player, so there is no remote in this
	-- path at all -- the panel was always drawn from a `StationState` the server is
	-- already sending, and all this does is stop hiding it.
	--
	-- IT TOGGLES rather than only opening, so E is a way back out as well as in: the
	-- prompt stays on screen while the panel is up (you have not moved), and reaching
	-- for the X with the mouse to close something you opened with a keypress is a
	-- worse exit than pressing the same key again.
	--
	-- MATCHED ON NAME, because this same event carries the rack's "Upgrade" prompts,
	-- which spend money. Anything that is not the stand's own prompt is not ours.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeredBy)
		if triggeredBy ~= Players.LocalPlayer or prompt.Name ~= "ViewShop" then
			return
		end
		dismissed = not dismissed
		render()
	end)

	-- HOLD E ON A PEDESTAL. No ProximityPrompt here — which stand qualifies depends
	-- on facing, not on standing at one fixed part (StationService.facedStation), and
	-- a native prompt is anchored to a single part and can't do that. This works
	-- whether or not the status panel above is open (closing it with the X doesn't
	-- stop you interacting with the stand you're standing at), and the server is
	-- still the only one that can actually place anything — ExhibitService.display
	-- re-derives both the faced stand and the held item itself, so this loop only
	-- ever decides WHEN to ask, never what happens.
	Net.get("CarryState").OnClientEvent:Connect(function(payload)
		heldUid = payload.heldUid or ""
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.E then
			return
		end
		eKeyDown = true
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.E then
			return
		end
		eKeyDown = false
		holdProgress = 0
		holdFired = false
		if ui.holdFill then
			ui.holdFill.Size = UDim2.fromScale(0, 1)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local view = state.standView
		local eligible = state.station == "pedestal"
			and state.facedPedestalId ~= nil
			and view ~= nil
			and view.isOwner
			and not view.occupied
			and heldUid ~= ""

		if not eligible or not eKeyDown then
			holdProgress = 0
			holdFired = false
			if ui.holdFill then
				ui.holdFill.Size = UDim2.fromScale(0, 1)
			end
			return
		end

		if holdFired then
			return
		end

		holdProgress += dt
		local fraction = math.clamp(holdProgress / Tuning.EXHIBIT_PLACE_HOLD_SECONDS, 0, 1)
		if ui.holdFill then
			ui.holdFill.Size = UDim2.fromScale(fraction, 1)
		end

		if fraction >= 1 then
			holdFired = true
			actionRemote:FireServer({ action = "display" })
		end
	end)

	Net.get("StationState").OnClientEvent:Connect(function(payload)
		-- Fingerprint "which station, which id" rather than comparing tables: this
		-- fires at TICK_RATE (~10Hz) the whole time you stand still, and payload is a
		-- new table every tick, so an equality check on it would never match and
		-- `dismissed` would clear itself on the very next tick after the click above.
		local key = if payload.station then `{payload.station}:{tostring(payload.stationId)}` else nil
		if key ~= lastKey then
			-- Arriving at a shop leaves it CLOSED until you press E on the stand --
			-- but ONLY if that stand actually exists in this world to be pressed. A
			-- world older than this script has no browse prompt, and starting
			-- dismissed there means the panel can never open at all; see
			-- shopHasBrowsePrompt for what that cost. Every other station kind still
			-- opens on approach.
			--
			-- Reads `payload.station`, not `state.station` -- `state` is not assigned
			-- until two lines below, so the old value is still in it here.
			dismissed = payload.station == "shop" and shopHasBrowsePrompt(payload.stationId)
			lastKey = key
		end

		state = payload
		state.items = payload.items or {}
		state.locker = payload.locker or {}

		-- BEFORE render, AND NOT INSIDE IT. The rack is in the world, not in the
		-- panel: dismissing the panel with the X must not wipe the checks off the
		-- counter you are still standing at. render() bails early on `dismissed`,
		-- so anything the world needs has to happen out here.
		local rackOk, rackErr = pcall(refreshRack)
		if not rackOk then
			warn(`[station] rack repaint failed: {rackErr}`)
		end

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
