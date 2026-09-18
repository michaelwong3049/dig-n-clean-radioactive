--[[
	StationController.lua — the base camp panel.

	Appears at the trader and the shops. Select a row, then act on it. The one verb
	left on the list itself is SELL — scrubbing and racking both left this file, see
	below.

	ONE MODE NOW, AND THE SHRINKING IS THE POINT. shop replaces the list with its own
	body; trader is the list itself. The plot claim board was a mode until exhibit
	income went auto-deposit — with nothing left to COLLECT, the board and its panel
	both went.

	THREE MODES WERE DELETED, ON REQUEST, AND ALL THREE DELETIONS FIXED SOMETHING.

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

	The pedestal panel used to open on approach with an item-picker list and a
	DISPLAY button, then (briefly) a hold-progress bar for a hold-E-to-place redesign.
	Both are gone: placing and taking an item back off a stand are now a "Place"/
	"Take" ProximityPrompt on the stand itself (ExhibitService), the same plain
	default-styled prompt the wash tub already used — no panel involved at all.

	PANEL_KINDS IS AN ALLOWLIST, NOT A FALLTHROUGH, and that is not stylistic. The
	trader branch is last and unguarded, so any station kind this file does not know
	about lands in it — which is exactly what happened the first time a mode was
	deleted: the wash pad started opening a panel titled TRADER.


	THE PANEL SITS AT LITERAL SCREEN-CENTRE, AND IT DID NOT USED TO.
	It was anchored at `UDim2.new(0.5, 0, 0.5, -Dock.RESERVE / 2)` — centred in the
	space left ABOVE the dock rather than on the screen — because the dock's status
	line and hotbar never hide, even away from a station. That bias is 173px of lift,
	and with the shop's cards it read as a panel stuck to the top of the screen rather
	than a panel in the middle of it.

	Two things make plain `fromScale(0.5, 0.5)` safe now. The instrument band shed its
	tallest widgets (the dig button, then the radar scope — see DetectorController), so
	the band is just the meter and RESERVE fell with it; and the status line is blank
	whenever you are out of a stage, which is exactly when a station panel is open
	(every station is in the zero-rad plaza). What is left below the centred panel is
	the hotbar, far enough down to clear it.

	This is the one thing here that is resolution-DEPENDENT rather than derived: a
	tall panel on a short viewport can still reach the hotbar. StationHud's
	DisplayOrder (40) is below DetectorHud's (60), so the hotbar wins that overlap
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

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
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
-- DECON AND PEDESTAL ARE NOT IN HERE ANY MORE, ON REQUEST. Walking up to the
-- cleansing station or a display stand used to open a panel over the screen; now
-- the only thing there is a prompt in the world (the tub's "Wash", a stand's
-- "Place"/"Take"), which is the whole interaction. Decon's removal also fixed a
-- bug nobody had diagnosed yet: that panel sat under the crosshair, so the click
-- that was supposed to start the hose arrived with `gameProcessedEvent` true and
-- the spray never began. "Nothing happens" was the panel eating the input.
local PANEL_KINDS: { [string]: boolean } = {
	trader = true,
	shop = true,
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
local CARD_COLS = 4
local CARD_ROWS = 2
local CARD_WIDTH = 258
local CARD_HEIGHT = 243
local CARD_GAP = 14

-- THE SLIVER IS GONE, AND SO IS THE SCROLLING IT ADVERTISED. The row used to be a
-- horizontal scroller sized to show four cards plus 30px of a fifth, because eight
-- 270-wide cards could not fit a screen. They fit now: the cards are 258 wide in a
-- 4x2 grid, so the longest track in the game (Detector, 8 tiers) is entirely on screen
-- with nothing behind an edge. What made the room was dropping the six-track rail the
-- mockup carried — the panel shows only the stall you walked up to, so every pixel of
-- it belongs to that one track's ladder.
--
-- CARD_SLOTS is still a ceiling over all six tracks and still the number of cards
-- built once and reused; CARD_COLS x CARD_ROWS is what fits without scrolling. A track
-- longer than that would scroll VERTICALLY rather than not fitting, which is the one
-- failure mode worth leaving a door open for.
local PANEL_PAD = 16
local PANEL_WIDTH = 620
-- Four whole cards, their three gaps, the panel's own padding, and 8px of gutter so a
-- scrollbar (narrow viewports only) never sits on top of the fourth column.
local SHOP_PANEL_WIDTH = CARD_COLS * CARD_WIDTH + (CARD_COLS - 1) * CARD_GAP + 2 * PANEL_PAD + 8
local SHOP_GRID_HEIGHT = CARD_ROWS * CARD_HEIGHT + (CARD_ROWS - 1) * CARD_GAP

-- ── The field-kit skin ───────────────────────────────────────────────
-- The shop panel is the one screen in the game wearing this, and it is deliberately
-- NOT the cartoon voice the cash badge and the rad meter share: a storefront full of
-- salvage equipment reads better as issued kit than as merchandise, which is the call
-- made when this was picked out of a round of mockups. Kept file-local rather than
-- pushed into UIKit.C for the same reason CashController keeps its own STYLE table —
-- nothing else should reach for these, and a shared palette invites exactly that.
--
-- THE FONTS DIVERGE FROM UIKit.Font ON PURPOSE. UIKit's rule is one family (Gotham) in
-- three weights, and it is the right rule for the HUD. This panel is a spec sheet:
-- Oswald is condensed enough to fit a stat label in a 62px gutter without abbreviating
-- it to noise, and RobotoMono keeps eight prices in a grid on the same digit width so
-- the column scans as a ladder. Both are stock Enum.Font values — no FontFace, no
-- asset ids. If this look ever spreads past the shop, move these into UIKit rather
-- than copying them.
local FIELD = {
	panel = Color3.fromHex("1B1F23"),
	card = Color3.fromHex("22272C"),
	well = Color3.fromHex("1A1E22"),
	edge = Color3.fromHex("343B42"),
	rule = Color3.fromHex("30373D"),
	amber = Color3.fromHex("F2A93B"),
	text = Color3.fromHex("E8E6E1"),
	dim = Color3.fromHex("9AA0A6"),
	faint = Color3.fromHex("7E868D"),
	muted = Color3.fromHex("8B9198"),
	ownedFill = Color3.fromHex("2A3036"),
	dearFill = Color3.fromHex("20262B"),
	dearEdge = Color3.fromHex("2C3339"),
	label = Enum.Font.Oswald,
	mono = Enum.Font.RobotoMono,
}

--- The stall's own accent, the same three hexes build/Shops paints each stall's
--- awning, trim cap and floor marker with (Kit.C.shopDetector / shopMagnet /
--- shopCleaner). A player navigates the plaza by those colours, so the panel that
--- opens there wears the same one — it is the only per-stall colour on the screen.
--- Tracks with no stall of their own (the bench trio) fall back to amber.
local STALL_ACCENT: { [string]: Color3 } = {
	Detector = Color3.fromHex("E0714E"),
	Magnet = Color3.fromHex("4E9AAE"),
	Cleaner = Color3.fromHex("9560B0"),
}

--- The two-letter code stamped on every card ("DT-05"). Spelled out rather than taken
--- as the first two letters, because Suit and Satchel both start "SA"/"SU" closely
--- enough to collide once you are reading them at 13px out of the corner of your eye.
--- Pure flavour, but it gives a grid of eight cards a fixed left edge to scan down.
local CODE_PREFIX: { [string]: string } = {
	Detector = "DT",
	Magnet = "MG",
	Cleaner = "HS",
	Suit = "ST",
	Boots = "BT",
	Satchel = "SC",
}

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
-- "which station, which id" so the panel's open/closed state is decided ONCE the
-- moment that changes -- leaving and coming back, or walking straight from one
-- station into another -- without being re-decided on every one of the ~10Hz
-- StationState ticks this same station keeps sending while you stand still.
--
-- A SHOP ARRIVES DISMISSED, AND THAT IS THE WHOLE "PRESS E TO VIEW" FEATURE. Every
-- station kind used to un-dismiss on arrival, so walking within ten studs of a stall
-- put a full-screen panel over you whether you had come to buy or were cutting
-- across the plaza. Shops now start closed and open on the stand's own E prompt
-- (build/Shops' "ViewShop"); trader still opens on approach, because it has no
-- prompt to open it with and is not something you walk past.
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

--- The most stat rows any one track shows (Boots: speed, haul, stamina, vault, dash).
--- Rows are built once at this count and hidden, the same reuse the cards themselves
--- use — a stat block that rebuilt its children on every StationState tick would churn
--- forty frames' worth of instances ten times a second.
local STAT_ROWS = 5
local STAT_ROW_HEIGHT = 17
local STAT_LABEL_WIDTH = 62
local STAT_VALUE_WIDTH = 34
local BAR_FLOOR = 0.06

--- One row of a card's stat block: label, bar, value. A flag cell (Boots' vault and
--- dash) reuses the same row and simply fills its bar to 0 or 1 — same geometry, so
--- five numeric rows and three-plus-two mixed rows put the button on the same
--- baseline.
local function makeStatRow(parent: Instance, order: number): Frame
	local row = Instance.new("Frame")
	row.Name = `Stat{order}`
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, STAT_ROW_HEIGHT)
	row.BackgroundTransparency = 1
	row.Visible = false
	row.Parent = parent

	UIKit.label(row, {
		name = "StatLabel",
		size = UDim2.fromOffset(STAT_LABEL_WIDTH, STAT_ROW_HEIGHT),
		font = FIELD.label,
		textSize = 13,
		color = FIELD.dim,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})

	-- The track, and the fill inside it. Two plain Frames rather than a UIKit helper:
	-- a 4px bar wants no corner, no stroke and no text, which is all a helper would add.
	local track = Instance.new("Frame")
	track.Name = "StatTrack"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, STAT_LABEL_WIDTH + 8, 0.5, 0)
	track.Size = UDim2.new(1, -(STAT_LABEL_WIDTH + STAT_VALUE_WIDTH + 22), 0, 4)
	track.BackgroundColor3 = FIELD.rule
	track.BorderSizePixel = 0
	track.Parent = row

	local fill = Instance.new("Frame")
	fill.Name = "StatFill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = FIELD.amber
	fill.BorderSizePixel = 0
	fill.Parent = track

	UIKit.label(row, {
		name = "StatValue",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.fromOffset(STAT_VALUE_WIDTH, STAT_ROW_HEIGHT),
		font = FIELD.mono,
		textSize = 13,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Right,
		outline = false,
		shadow = false,
	})

	return row
end

--- One shop card: unit code and status, art beside the name and its one line of copy,
--- the stat block, and the price button.
---
--- THE ART WELL IS DELIBERATELY EMPTY. `CardArt` is a real ImageLabel with no Image
--- set, sized and positioned as the finished thing will be, so dropping in artwork
--- later is one assignment per tier and not a re-layout. It is not a placeholder
--- rectangle to be replaced — it is the frame the art goes in. It moved beside the
--- name rather than above it when the card became a spec sheet: a 78x46 plate reads as
--- an inventory thumbnail, which is what a tool in a catalogue wants to be, and the
--- height it gave up is what the stat bars and the blurb now stand in.
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
		color = FIELD.card,
		transparency = 0,
		strokeColor = FIELD.edge,
		strokeThickness = 1,
		cornerRadius = UDim.new(0, 6),
		visible = false,
	})
	card.LayoutOrder = order

	-- ── The code strip ───────────────────────────────────────────────
	-- A rule across the top carrying the unit's catalogue code on the left and its
	-- status word on the right. The code is pure flavour and it earns its place: it
	-- gives the eye a fixed left edge to run down a grid of eight cards by, which the
	-- names (2 to 16 characters, centred before this) never did.
	local strip = Instance.new("Frame")
	strip.Name = "CardStrip"
	strip.Size = UDim2.new(1, 0, 0, 33)
	strip.BackgroundTransparency = 1
	strip.Parent = card

	local stripRule = Instance.new("Frame")
	stripRule.Name = "StripRule"
	stripRule.AnchorPoint = Vector2.new(0, 1)
	stripRule.Position = UDim2.fromScale(0, 1)
	stripRule.Size = UDim2.new(1, 0, 0, 1)
	stripRule.BackgroundColor3 = FIELD.rule
	stripRule.BorderSizePixel = 0
	stripRule.Parent = strip

	UIKit.label(strip, {
		name = "CardCode",
		position = UDim2.fromOffset(14, 0),
		size = UDim2.new(0, 70, 1, -1),
		font = FIELD.mono,
		textSize = 13,
		color = FIELD.faint,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})

	UIKit.label(strip, {
		name = "CardFlag",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -14, 0, 0),
		size = UDim2.new(1, -90, 1, -1),
		font = FIELD.label,
		textSize = 14,
		color = FIELD.dim,
		xAlign = Enum.TextXAlignment.Right,
		outline = false,
		shadow = false,
	})

	-- ── Art, name, blurb ─────────────────────────────────────────────
	local art = Instance.new("ImageLabel")
	art.Name = "CardArt"
	art.Position = UDim2.fromOffset(14, 45)
	art.Size = UDim2.fromOffset(78, 46)
	art.BackgroundColor3 = FIELD.well
	art.BackgroundTransparency = 0
	art.BorderSizePixel = 0
	art.Image = ""
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = card

	local artEdge = Instance.new("UIStroke")
	artEdge.Color = FIELD.rule
	artEdge.Thickness = 1
	artEdge.Parent = art

	-- Fixed heights, not AutomaticSize: every card in the grid has to put its button on
	-- the same baseline, and a 2-line name on one card must not push that card's button
	-- below its neighbours'.
	UIKit.label(card, {
		name = "CardName",
		position = UDim2.fromOffset(102, 43),
		size = UDim2.new(1, -116, 0, 25),
		font = FIELD.label,
		textSize = 23,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})

	UIKit.label(card, {
		name = "CardBlurb",
		position = UDim2.fromOffset(102, 68),
		size = UDim2.new(1, -116, 0, 30),
		font = UIKit.Font.body,
		textSize = 12,
		color = FIELD.muted,
		xAlign = Enum.TextXAlignment.Left,
		yAlign = Enum.TextYAlignment.Top,
		wrapped = true,
		outline = false,
		shadow = false,
	})

	-- ── Stat block ───────────────────────────────────────────────────
	local stats = Instance.new("Frame")
	stats.Name = "CardStats"
	stats.Position = UDim2.fromOffset(14, 106)
	stats.Size = UDim2.new(1, -28, 0, STAT_ROWS * STAT_ROW_HEIGHT + (STAT_ROWS - 1) * 6)
	stats.BackgroundTransparency = 1
	stats.Parent = card

	local statLayout = Instance.new("UIListLayout")
	statLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statLayout.Padding = UDim.new(0, 6)
	statLayout.Parent = stats

	for index = 1, STAT_ROWS do
		makeStatRow(stats, index)
	end

	local buy = UIKit.button(card, {
		name = "CardBuy",
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, 14, 1, -13),
		size = UDim2.new(1, -28, 0, 44),
		font = FIELD.mono,
		textSize = 16,
		cornerRadius = UDim.new(0, 4),
		strokeThickness = 1,
		outline = false,
		shadow = false,
	})
	buy.LayoutOrder = 9

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

	local canvas = UIKit.canvas(gui)

	local panel, panelStroke = UIKit.panel(canvas, {
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

	-- Parented to the canvas, a SIBLING of the panel, not a child of it. Every direct
	-- child of `panel` is claimed by the UIListLayout added near the bottom of this
	-- function -- a close button dropped in there would become another row in the
	-- stack, not a badge floating over a corner. Living outside that layout means
	-- tracking the panel's own corner by hand instead of getting it for free, hence
	-- repositionClose() below, re-run whenever the panel moves or resizes (it does
	-- both: automaticSizeY, and MaxSize swaps between shop/list widths per mode).
	local closeButton = UIKit.button(canvas, {
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
		-- AbsolutePosition / AbsoluteSize are SCREEN pixels and the button's Offset is a
		-- design pixel on the same UIKit canvas, so measure from the canvas's own corner
		-- and divide by its scale — or the badge drifts off the corner as the HUD scales.
		local s = UIKit.canvasScale(canvas)
		local corner = (panel.AbsolutePosition - canvas.AbsolutePosition) / s
		closeButton.Position = UDim2.fromOffset(corner.X + panel.AbsoluteSize.X / s - 14, corner.Y + 14)
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

	-- ── The shop's own header ────────────────────────────────────────
	-- SHOP MODE DOES NOT USE `ui.title` / `ui.subtitle`. Those two are the trader's,
	-- centred-then-left-aligned per mode, and this header is a different object: an
	-- accent bar in the stall's own colour, the track name, a stock line, and the
	-- wallet on the right. Building it inside `ui.shop` rather than reshaping the
	-- shared pair means the trader keeps exactly the header it has today and render()
	-- simply hides one or the other — no mode-specific repainting of a widget two
	-- modes share.
	--
	-- THE WALLET LIVES HERE NOW. It used to sit under the card row, which was right
	-- while the mockup had a left rail to anchor the panel's chrome; with the rail
	-- gone the header is the only chrome there is, and the number the whole grid of
	-- prices is compared against belongs in it.
	local header = Instance.new("Frame")
	header.Name = "ShopHeader"
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, 56)
	header.BackgroundTransparency = 1
	header.Parent = shop
	ui.shopHeader = header

	local headerRule = Instance.new("Frame")
	headerRule.Name = "HeaderRule"
	headerRule.AnchorPoint = Vector2.new(0, 1)
	headerRule.Position = UDim2.fromScale(0, 1)
	headerRule.Size = UDim2.new(1, 0, 0, 1)
	headerRule.BackgroundColor3 = FIELD.rule
	headerRule.BorderSizePixel = 0
	headerRule.Parent = header

	-- The stall's accent, and the only per-stall colour on the panel. render() repaints
	-- it from STALL_ACCENT.
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.AnchorPoint = Vector2.new(0, 0.5)
	accentBar.Position = UDim2.new(0, 0, 0.5, -2)
	accentBar.Size = UDim2.fromOffset(4, 38)
	accentBar.BackgroundColor3 = FIELD.amber
	accentBar.BorderSizePixel = 0
	accentBar.Parent = header
	ui.shopAccent = accentBar

	-- Oswald at 30 and no letter-spacing: Roblox TextLabels have no tracking property,
	-- and the usual workaround (spacing the glyphs out by hand, "D E T E C T O R S")
	-- breaks the moment a track name wraps. The condensed face carries it alone.
	ui.shopTitle = UIKit.label(header, {
		name = "ShopTitle",
		position = UDim2.fromOffset(16, 2),
		size = UDim2.new(1, -230, 0, 30),
		font = FIELD.label,
		textSize = 30,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})

	ui.shopStock = UIKit.label(header, {
		name = "ShopStock",
		position = UDim2.fromOffset(16, 31),
		size = UDim2.new(1, -230, 0, 18),
		font = UIKit.Font.body,
		textSize = 13,
		color = FIELD.dim,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})

	UIKit.label(header, {
		name = "WalletLabel",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 3),
		size = UDim2.fromOffset(200, 14),
		font = FIELD.label,
		textSize = 12,
		color = FIELD.faint,
		text = "ON HAND",
		xAlign = Enum.TextXAlignment.Right,
		outline = false,
		shadow = false,
	})

	ui.shopCash = UIKit.label(header, {
		name = "Cash",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 18),
		size = UDim2.fromOffset(200, 30),
		font = FIELD.mono,
		textSize = 26,
		color = FIELD.amber,
		xAlign = Enum.TextXAlignment.Right,
		outline = false,
		shadow = false,
	})

	-- The storefront grid. AutomaticCanvasSize.Y + a UIGridLayout means the canvas is
	-- whatever the visible cards add up to, so a 5-tier track reserves one row less
	-- than an 8-tier one without anyone computing a canvas height — and on a viewport
	-- wide enough for four columns (the ceiling the panel is sized to) nothing scrolls
	-- at all. The direction flipped from X with the sliver: see CARD_COLS above.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.LayoutOrder = 1
	scroll.Size = UDim2.new(1, 0, 0, SHOP_GRID_HEIGHT)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = FIELD.edge
	scroll.ScrollBarImageTransparency = 0.3
	scroll.Parent = shop
	ui.shopScroll = scroll

	local cardLayout = Instance.new("UIGridLayout")
	cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardLayout.CellSize = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	cardLayout.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	cardLayout.FillDirectionMaxCells = CARD_COLS
	cardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	cardLayout.Parent = scroll

	ui.shopCards = {}
	for index = 1, CARD_SLOTS do
		table.insert(ui.shopCards, makeShopCard(scroll, index))
	end

	-- Shown instead of the grid when a shop has no track behind it at all.
	ui.shopEmpty = UIKit.label(shop, {
		name = "Empty",
		size = UDim2.new(1, 0, 0, 28),
		font = UIKit.Font.body,
		textSize = 16,
		color = FIELD.dim,
		xAlign = Enum.TextXAlignment.Center,
		text = "nothing for sale here",
		visible = false,
		outline = false,
		shadow = false,
	})
	ui.shopEmpty.LayoutOrder = 2

	-- Plots have no panel any more: exhibit income auto-deposits into the owner's
	-- wallet (server-side ExhibitService), so the claim board — whose only verb was
	-- COLLECT — was removed along with the "plot" station kind. Pedestals never got
	-- one back either: placing and taking an item off a stand are both a
	-- ProximityPrompt on the stand itself (ExhibitService), not a panel.

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
	-- its full 48px plus a gap. Shop mode hides every button in here, and it is the
	-- tallest mode in the panel, so that dead band is the cheapest 54px available.
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
--- `$150000` is a number; `$150,000` is a price. Eight of them stacked in a grid are
--- read against each other, and unseparated digits at that length are read wrong.
local function money(amount: number): string
	local text = tostring(math.floor(amount))
	local grouped = text
	while true do
		local next, count = string.gsub(grouped, "^(%-?%d+)(%d%d%d)", "%1,%2")
		grouped = next
		if count == 0 then
			break
		end
	end
	return `${grouped}`
end

--- Paint one card's stat block. Rows are reused, so every row past the track's own
--- column count is hidden rather than destroyed — see STAT_ROWS.
---
--- A FLAG CELL KEEPS THE BAR'S GEOMETRY AND THROWS AWAY ITS MEANING. Boots' vault and
--- dash are capabilities, not amounts, so the row prints YES/NO and fills its track
--- whole or not at all. Sharing the row shape is what keeps the button on the same
--- baseline whether a track has two numeric stats or three numeric plus two flags.
local function paintStats(card: Frame, entry, accent: Color3)
	local stats = card.CardStats :: Frame
	for index = 1, STAT_ROWS do
		local row = stats:FindFirstChild(`Stat{index}`) :: Frame?
		if row == nil then
			continue
		end
		local cell = entry.stats[index]
		row.Visible = cell ~= nil
		if cell == nil then
			continue
		end

		local label = row.StatLabel :: TextLabel
		local value = row.StatValue :: TextLabel
		local track = row.StatTrack :: Frame
		local fill = track.StatFill :: Frame

		label.Text = cell.label
		value.Text = cell.value
		-- THE BOTTOM RUNG KEEPS A SLIVER. ShopService measures a bar from the worst
		-- value on the ladder, so tier 1 is honestly 0.0 on every column — and an
		-- entirely empty track reads as "no data" rather than "lowest". A floor here
		-- rather than in the payload keeps the number the server sends honest and puts
		-- the fudge where it belongs, in the drawing.
		local shown = math.clamp(cell.fraction, 0, 1)
		if cell.kind ~= "flag" then
			shown = math.max(shown, BAR_FLOOR)
		end
		fill.Size = UDim2.fromScale(shown, 1)
		fill.BackgroundColor3 = accent
		-- An unlit flag is the one cell that should read as absent rather than as low:
		-- dimming the value keeps "NO" from being mistaken for a small amount.
		value.TextColor3 = if cell.kind == "flag" and not cell.on then FIELD.muted else FIELD.text
	end
end

--- Four states, and all four are drawn on the same card rather than on four layouts.
---
--- ISSUED    the one in your hands. Amber edge, amber art, a ghost button that says so.
--- OWNED     bought and not held. The button is a live EQUIP — see ShopService's note
---           on why ownership being a set is what makes that a real verb.
--- (buyable) no flag at all. The price button already says it is for sale, and a word
---           saying the same thing on every unbought card was noise — this is where
---           "AVAILABLE" used to be.
--- NEED $x   buyable, unaffordable. The flag carries the SHORTFALL against your wallet
---           rather than the price, because the price is already on the button and the
---           gap is the thing you do not know.
local function paintShopCard(card: Frame, entry, accent: Color3, cash: number, prefix: string)
	local nameLabel = card.CardName :: TextLabel
	local blurb = card.CardBlurb :: TextLabel
	local code = card.CardStrip.CardCode :: TextLabel
	local flag = card.CardStrip.CardFlag :: TextLabel
	local art = card.CardArt :: ImageLabel
	local buy = card.CardBuy :: TextButton
	local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke
	local buyStroke = buy:FindFirstChildOfClass("UIStroke") :: UIStroke

	nameLabel.Text = entry.name
	blurb.Text = entry.blurb or ""
	code.Text = string.format("%s-%02d", prefix, entry.tier)
	card:SetAttribute("Buyable", entry.buyable == true)
	card:SetAttribute("Equippable", entry.equippable == true)
	card:SetAttribute("Tier", entry.tier)

	local affordable = entry.affordable == true
	local dear = entry.buyable == true and not affordable

	-- The bar colour is the card's whole mood: amber for the one you hold, the stall's
	-- accent for anything live, grey for a rung you cannot pay for yet.
	local barColour = if entry.current then FIELD.amber elseif dear then FIELD.muted else accent
	paintStats(card, entry, barColour)

	art.ImageColor3 = barColour
	nameLabel.TextColor3 = FIELD.text

	if entry.current then
		cardStroke.Color = FIELD.amber
		flag.Text = "ISSUED"
		flag.TextColor3 = FIELD.amber
		buy.Text = "IN HAND"
		buy.TextColor3 = FIELD.amber
		buy.BackgroundTransparency = 1
		buyStroke.Color = FIELD.amber
	elseif entry.owned then
		cardStroke.Color = FIELD.edge
		flag.Text = "OWNED"
		flag.TextColor3 = FIELD.dim
		buy.Text = "EQUIP"
		buy.TextColor3 = FIELD.text
		buy.BackgroundColor3 = FIELD.ownedFill
		buy.BackgroundTransparency = 0
		buyStroke.Color = FIELD.edge
	elseif dear then
		cardStroke.Color = FIELD.edge
		flag.Text = `NEED {money(entry.price - cash)}`
		flag.TextColor3 = FIELD.muted
		buy.Text = money(entry.price)
		buy.TextColor3 = FIELD.muted
		buy.BackgroundColor3 = FIELD.dearFill
		buy.BackgroundTransparency = 0
		buyStroke.Color = FIELD.dearEdge
	else
		cardStroke.Color = FIELD.edge
		flag.Text = ""
		-- Affordable is the ONE solid fill anywhere on this panel. Everything else is
		-- outlined, ghosted or muted, so the things worth clicking are the only things
		-- that look clickable.
		buy.Text = money(entry.price)
		buy.TextColor3 = FIELD.panel
		buy.BackgroundColor3 = FIELD.amber
		buy.BackgroundTransparency = 0
		buyStroke.Color = FIELD.amber
	end
	-- current, owned and buyable are exhaustive over every tier: `current` is checked
	-- first and `owned` second, so the equipped tier takes the ISSUED branch even
	-- though it is also owned, and `buyable` is by construction `not owned` — the
	-- trailing two branches split that last case on affordability alone.
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
	ui.shop.Visible = atShop
	-- SHOP MODE HIDES THE SHARED HEADER ENTIRELY. `ui.title`/`ui.subtitle` are the
	-- trader's; the shop builds its own (ui.shopHeader) with the accent bar, the stock
	-- line and the wallet. Hiding rather than repainting is what keeps the trader's
	-- header exactly as it was — see the shop header's own note.
	ui.title.Visible = not atShop
	ui.subtitle.Visible = not atShop
	ui.actions.Visible = not atShop
	ui.panelSize.MaxSize = Vector2.new(if atShop then SHOP_PANEL_WIDTH else PANEL_WIDTH, math.huge)

	-- THE PANEL FRAME IS SHARED, SO ITS SKIN IS PER MODE. The shop wears the field-kit
	-- slate; the trader keeps the near-black it always had. Both are set on every
	-- render rather than once at build, because a player can walk from one straight
	-- into the other without the panel ever being rebuilt.
	ui.panel.BackgroundColor3 = if atShop then FIELD.panel else COLOR.panel
	ui.panel.BackgroundTransparency = if atShop then 0.02 else 0.08

	if atShop then
		local offer = state.offer
		local tiers = if offer then offer.tiers else nil
		local track = state.stationId or "Shop"
		local accent = STALL_ACCENT[track] or FIELD.amber
		local cash = state.cash or 0

		ui.panelStroke.Color = FIELD.edge
		ui.shopAccent.BackgroundColor3 = accent
		ui.shopTitle.Text = string.upper(track)

		local count = if tiers then #tiers else 0
		local owned = 0
		if tiers then
			for _, entry in tiers do
				if entry.owned then
					owned += 1
				end
			end
		end
		ui.shopStock.Text = if offer and offer.maxed
			then `{count} units on the rail \u{00B7} you own every one`
			else `{count} units on the rail \u{00B7} you own {owned} \u{00B7} buy any of them, in any order`

		ui.shopScroll.Visible = count > 0
		ui.shopEmpty.Visible = count == 0

		-- Two letters off the track name: Detector -> DT, Magnet -> MG, Cleaner -> CL.
		-- Consonant-first rather than the first two letters, so Satchel and Suit do not
		-- both come out "SU".
		local prefix = CODE_PREFIX[track] or string.upper(string.sub(track, 1, 2))

		for index, card in ui.shopCards do
			local entry = if tiers then tiers[index] else nil
			card.Visible = entry ~= nil
			if entry then
				paintShopCard(card, entry, accent, cash, prefix)
			end
		end

		ui.shopCash.Text = money(cash)

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
