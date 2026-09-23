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
	price card above it and its own E prompt (build/Shops). That E opens THIS panel
	with just that one tier's card in it — see `rackCard`. The one thing the price
	cards cannot show on their own is whether YOU own that tier — they are single
	shared instances — so the owned-check is written locally, off the same `offer` this
	panel is already receiving. See "The rack beside the stand" below for what it costs.
	The panel does not open on approach any more: press E on the stand for the whole
	row, or on a rack hook for one card. See `dismissed`.

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
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)
local ToolModels = require(Shared.ToolModels)

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

-- ── Shop carousel ───────────────────────────────────────────────────
-- The shop is a storefront, not a one-line upgrade prompt: every tier of the track
-- laid out worst-to-best, side by side in one row, so the ladder you are climbing is
-- there to scroll along before you have climbed it.
--
-- ONE CARD AT A TIME, ON REQUEST. This was a 4x2 grid of 258-wide spec cards, which
-- fit the longest track on screen at once but made every card small enough that eight
-- of them read as a price list. Now one card holds the middle of the panel at hero
-- size, and its neighbours peek in, dimmed, at either edge — the sliver is what tells
-- you there is more to the left and right. Arrows, the mouse wheel, a drag, the pager
-- dots or a click on a peeking card move along the row; it always settles with one
-- card centred.
--
-- CARD_SLOTS IS A CEILING OVER ALL SIX TRACKS, NOT A GUESS. The longest is Detector
-- at 8 tiers (Config/Gear); the rest run 5-7. Cards are built once at that count and
-- hidden, the same reuse the item ROWS above have always used, because a shop panel
-- that rebuilds its children on every StationState tick would churn 8 frames' worth
-- of instances ten times a second.
local CARD_SLOTS = 8
local CARD_WIDTH = 500
local CARD_HEIGHT = 500
local CARD_GAP = 18
-- How much of each neighbour shows at the panel's edges on a full-width panel. On a
-- viewport too narrow for the ceiling, the panel narrows and the peeks go first; the
-- focused card stays whole and centred because the row is placed from the carousel's
-- own centre (Scale 0.5), not from its left edge.
local CARD_PEEK = 64
-- Distance from one card's centre to the next — one "notch" of the carousel.
local CAROUSEL_STEP = CARD_WIDTH + CARD_GAP
-- A few px taller than a card so the focused card's stroke is never clipped.
local CAROUSEL_HEIGHT = CARD_HEIGHT + 8
-- Neighbours sit slightly smaller and behind a slate veil, so the focused card is the
-- only thing on the row that reads as in front of you.
local NEIGHBOUR_SCALE = 0.92
local NEIGHBOUR_VEIL = 0.35
local CAROUSEL_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
-- A drag must travel this far (design px) before it counts as a drag and not a click,
-- and past this fraction of a step it moves one card even if it did not reach halfway.
local DRAG_SLOP = 6
local DRAG_FLICK = 0.18
-- Past either end the row follows the pointer at this rate, so it gives but plainly
-- stops.
local DRAG_RUBBER = 0.35
-- One wheel notch is one card. Trackpads fire a burst of small wheel events per swipe,
-- and without a cooldown one swipe would run the whole ladder.
local WHEEL_COOLDOWN = 0.15
-- Pager dots: a dot per tier, the focused one stretched into a pill.
local DOT_SIZE = 9
local DOT_FOCUS_WIDTH = 26
-- The close badge's 32px plus the 14px it is inset by, less the panel pad it shares.
local WALLET_INSET = 34

local PANEL_PAD = 16
local PANEL_WIDTH = 620
-- The focused card, a gap and a peek either side, and the panel's own padding.
local SHOP_PANEL_WIDTH = CARD_WIDTH + 2 * (CARD_GAP + CARD_PEEK) + 2 * PANEL_PAD
-- The rack card (see `rackCard`): one card and nothing either side of it, with a few
-- px spare so the carousel window does not clip the card's outline.
local RACK_CARD_EDGE = 4
local RACK_PANEL_WIDTH = CARD_WIDTH + 2 * (PANEL_PAD + RACK_CARD_EDGE)
-- The card starts this much smaller and eases up to full size as it opens.
local RACK_CARD_POP = 0.94
local RACK_CARD_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- ── The field-kit skin ───────────────────────────────────────────────
-- The shop panel is the one screen in the game wearing this, and it is deliberately
-- NOT the cartoon voice the cash badge and the rad meter share: a storefront full of
-- salvage equipment reads better as issued kit than as merchandise, which is the call
-- made when this was picked out of a round of mockups. Kept file-local rather than
-- pushed into UIKit.C for the same reason CashController keeps its own STYLE table —
-- nothing else should reach for these, and a shared palette invites exactly that.
--
-- THE TEXT IS THE HUD'S CARTOON VOICE, on request, even though the slate is not. It
-- used to be Oswald and RobotoMono, a spec-sheet voice; now it is what the cash badge,
-- the rad meter and the stand cards speak: LuckiestGuy for the headline pieces (the
-- track, the tier's name, the price, the wallet), FredokaOne for everything else, all
-- white-ish and all wearing the same rounded INK outline — see inkShopText.
local FIELD = {
	panel = Color3.fromHex("1B1F23"),
	card = Color3.fromHex("22272C"),
	well = Color3.fromHex("1A1E22"),
	edge = Color3.fromHex("343B42"),
	rule = Color3.fromHex("30373D"),
	amber = Color3.fromHex("F2A93B"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA0A6"),
	muted = Color3.fromHex("8B9198"),
	ownedFill = Color3.fromHex("2A3036"),
	dearFill = Color3.fromHex("20262B"),
	-- NEED $x: the cash badge's own spend red, so a shortfall reads as the same money.
	short = Color3.fromHex("FF5A4E"),
	-- The cartoon black every chunky card in the game is outlined in (CashController's
	-- and StandCardController's INK, Kit.C.hazardBlack).
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.LuckiestGuy,
	label = Enum.Font.FredokaOne,
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

-- THE WIDTHS ABOVE ARE A CEILING, NOT A SIZE, and that distinction is load-bearing.
-- The panel is laid out as "the viewport minus a margin, but never wider than the
-- ceiling" (Size scale 1 + a UISizeConstraint), so a big screen gets exactly the
-- four-card row the ceiling describes and a small one gets a narrower panel that
-- still fits, with the card row simply scrolling sooner. Sizing it at a flat
-- SHOP_PANEL_WIDTH offset put 200px of panel off each side of an 800px viewport —
-- the cards do not shrink to fit, so the panel has to.
local SCREEN_MARGIN = 24

-- ...AND THE HEIGHT IS A CEILING TOO, on a short screen. The shop card alone is 500
-- design px tall and the whole panel ~660, which a phone at UIKit.MIN_SCALE does not
-- have: the panel ran off the top and bottom and the hotbar (drawn over it, see
-- build()) sat on the BUY button. So when the panel does not fit between FIT_TOP and
-- the top of the hotbar, fitPanel() shrinks it with its own UIScale until it does,
-- and lifts it clear of the hotbar. A screen with the room — any desktop at 1280x720
-- or more — never triggers either, and sees the panel exactly as before.
local FIT_TOP = 12
local FIT_BOTTOM = UIKit.Dock.HOTBAR_BOTTOM + UIKit.Dock.HOTBAR_HEIGHT + UIKit.Dock.GAP

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

--- THE RACK CARD: which rack hook's E opened this panel, or nil for the storefront.
---
--- Pressing E on a tier hanging on a shop's rack opens this same panel with ONLY that
--- tier's card in it — no neighbours, no arrows, no pager — the card the storefront
--- would have shown for it, with the same live model, stats and Buy / Equip button.
--- It is the same panel rather than a second one on purpose: the card, its button
--- binding and the StationAction it sends are all already here, and the server
--- treats a buy from it exactly like a buy from the storefront (it re-derives the
--- shop from where you stand).
---
--- Cleared by the X, by walking out of the shop's radius, and by the stand's E,
--- which swaps the one card for the whole row. The same rack hook's E again closes
--- it; another hook's E swaps to that hook's card.
local rackCard: { track: string, tier: number }? = nil

--- The name build/Shops gives every rack hook's prompt. Hardcoded for the same reason
--- as BROWSE_PROMPT above.
local RACK_PROMPT = "Upgrade"

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
--- and the Outfitter's counters have never had rack prompts, which made Suit and
--- Satchel unbuyable outright. The Suit gates every stage in the game.
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

--- A CEILING OVER EVERY TRACK'S COLUMN COUNT, deliberately above the current high
--- water mark rather than equal to it. It was exactly Boots' five (speed, haul,
--- stamina, vault, dash); that track is retired and the widest live block is now three,
--- but the number is left at five so adding a fourth column to a track is a one-line
--- change in Config/Gear rather than a layout change here too.
---
--- Rows are built once at this count and hidden, the same reuse the cards themselves
--- use — a stat block that rebuilt its children on every StationState tick would churn
--- forty frames' worth of instances ten times a second.
local STAT_ROWS = 5
local STAT_ROW_HEIGHT = 30
local STAT_ROW_GAP = 10
local STAT_LABEL_WIDTH = 130
local STAT_VALUE_WIDTH = 90
local STAT_TEXT_SIZE = 23
local BAR_FLOOR = 0.06

-- The card's vertical stack, top to bottom: the name strip, the art well, the stat
-- block, the buy button. The stat block and the button are pinned to the bottom edge;
-- the art well takes whatever height is left between them and the strip, so a track
-- with fewer stat columns gets a bigger picture rather than a gap (see paintShopCard).
local CARD_INSET = 20
local CARD_STRIP_HEIGHT = 54
local CARD_ART_TOP = CARD_STRIP_HEIGHT + 16
local CARD_ART_GAP = 18
local CARD_BUY_HEIGHT = 56
local CARD_BUY_BOTTOM = 18
local CARD_STATS_GAP = 16
-- The stat block's bottom edge, measured from the card's top.
local CARD_STATS_BOTTOM = CARD_HEIGHT - CARD_BUY_BOTTOM - CARD_BUY_HEIGHT - CARD_STATS_GAP

-- ── The art well's model ─────────────────────────────────────────────
-- A LIVE RENDER, NOT AN UPLOADED PICTURE. Every tier's model is already on the client
-- (Assets/Tools for Detector and Magnet, Shared/ToolModels for the hose), so a
-- ViewportFrame draws the real thing at any resolution, with nothing to upload or
-- moderate — and it cannot drift from the rack or the hand when a model is re-imported,
-- which a folder of screenshots would the first time anyone touched the art.
--
-- A STILL HERO SHOT, ON REQUEST — no turntable. One angle per track, picked from
-- rendered candidates. Each is a direction to look FROM and an `up`, both in the model's
-- own frame (its pivot put at the origin), and all three put the working end on the
-- right: the detector is laid along the well with its coil there, since stood up the
-- way it is carried it would be a thin stripe in a box this wide; the magnet and the
-- hose are three-quarter views from a little above.
--
-- EVERY TIER IS FRAMED TO FILL THE WELL, so a tier-1 horseshoe is as big on its card as
-- a Singularity Coil is on its own. Tier is carried by the model itself — it is the
-- card's picture, not a size chart.
type ArtView = { from: Vector3, up: Vector3 }
local ART_VIEW: { [string]: ArtView } = {
	Detector = { from = Vector3.new(1, 0.5, 0.3), up = Vector3.new(0, 0.6, -1) },
	Magnet = { from = Vector3.new(1, 0.6, 0.35), up = Vector3.yAxis },
	Cleaner = { from = Vector3.new(1, 0.55, -0.35), up = Vector3.yAxis },
}
-- Narrow, so a long detector does not bulge at the near end the way a wide lens makes
-- it; the camera just stands further back.
local ART_FOV = 25
-- How much bigger than the model the framed view is — the breathing room at the edges.
local ART_MARGIN = 1.12
-- The ViewportFrame's defaults (a 200 grey ambient under a 140 key) wash every tier out
-- to the same pale grey. A low ambient and a warm key over the camera's left shoulder
-- give the models back the colour that tells one tier from the next.
local ART_LIGHT = {
	ambient = Color3.fromRGB(90, 92, 98),
	color = Color3.fromRGB(255, 248, 235),
	direction = Vector3.new(-1, -1, -1),
}
-- Parts that only make sense in the hand: the same gag build/Shops' rack strips
-- (RACK_HIDE_ON_DISPLAY), hardcoded again because build/ cannot be required from here.
local ART_HIDE = { "Realistically Sized Magnet" }

--- One row of a card's stat block: label, bar, value. A flag cell reuses the same row
--- and simply fills its bar to 0 or 1 — same geometry, so a block of numeric rows and a
--- mixed block put the button on the same baseline.
---
--- NO LIVE TRACK USES A FLAG CELL any more: Boots' vault and dash were the only two,
--- and they were retired with it. The support is kept because `kind = "flag"` is still
--- a documented option in Gear.STAT_META and deleting the render path would make the
--- next boolean stat a two-file change instead of a one-line one.
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
		textSize = STAT_TEXT_SIZE,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})

	-- The track, and the fill inside it. Two plain Frames rather than a UIKit helper:
	-- an 8px bar wants no corner, no stroke and no text, which is all a helper would add.
	local track = Instance.new("Frame")
	track.Name = "StatTrack"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, STAT_LABEL_WIDTH + 10, 0.5, 0)
	track.Size = UDim2.new(1, -(STAT_LABEL_WIDTH + STAT_VALUE_WIDTH + 26), 0, 8)
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
		font = FIELD.label,
		textSize = STAT_TEXT_SIZE,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Right,
		outline = false,
		shadow = false,
	})

	return row
end

--- One shop card: name and status, a big art well, the stat block, and the price
--- button — drawn at hero size, because the carousel shows one of these at a time
--- rather than eight in a grid.
---
--- THE ART WELL SHOWS THE REAL MODEL. `CardArt` is the well — an ImageLabel with no
--- Image, kept for its fill, corner and edge — and `CardModel` is a ViewportFrame
--- inside it that renders the tier's own model, the one the rack hangs and the one
--- ToolService puts in your hands. See "The art well's model" below for why it is a
--- live render and not an uploaded picture. A track with no model (the Outfitter's
--- Suit and Satchel) leaves the viewport empty and the well reads as it always did.
---
--- THE CARD IS PLACED BY HAND, NOT BY A LAYOUT. Its slot on the carousel row is a fixed
--- x (one CAROUSEL_STEP per tier) and it is anchored at its own centre, so the
--- neighbour `UIScale` shrinks it in place rather than toward a corner — a
--- UIListLayout would have to be fought for that.
---
--- `CardFocus` is a clear button over the whole card, shown only while the card is a
--- neighbour. It carries the veil that dims it and catches the click, so pressing a
--- peeking card brings it to the middle instead of buying something you have not
--- looked at.
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
		position = UDim2.new(0, (order - 1) * CAROUSEL_STEP + CARD_WIDTH / 2, 0.5, 0),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = FIELD.card,
		transparency = 0,
		strokeColor = FIELD.edge,
		strokeThickness = 1,
		cornerRadius = UDim.new(0, 8),
		visible = false,
	})
	card.LayoutOrder = order

	local scale = Instance.new("UIScale")
	scale.Name = "FocusScale"
	scale.Scale = NEIGHBOUR_SCALE
	scale.Parent = card

	-- ── The name strip ───────────────────────────────────────────────
	-- The tier's name on the left, its status word (ISSUED / OWNED / NEED $x) on the
	-- right, over a rule. No catalogue code and no blurb any more, on request: the card
	-- is the picture, the numbers and the price.
	local strip = Instance.new("Frame")
	strip.Name = "CardStrip"
	strip.Size = UDim2.new(1, 0, 0, CARD_STRIP_HEIGHT)
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
		name = "CardName",
		position = UDim2.fromOffset(CARD_INSET, 0),
		size = UDim2.new(1, -(2 * CARD_INSET + 150), 1, -1),
		font = FIELD.headline,
		textSize = 28,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})

	UIKit.label(strip, {
		name = "CardFlag",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -CARD_INSET, 0, 0),
		size = UDim2.new(0, 150, 1, -1),
		font = FIELD.label,
		textSize = 18,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Right,
		outline = false,
		shadow = false,
	})

	-- ── Art ──────────────────────────────────────────────────────────
	-- Full card width, from under the strip down to the stat block. Its height is set
	-- per tier in paintShopCard, once the number of stat rows is known.
	local art = Instance.new("ImageLabel")
	art.Name = "CardArt"
	art.Position = UDim2.fromOffset(CARD_INSET, CARD_ART_TOP)
	art.Size = UDim2.new(1, -2 * CARD_INSET, 0, CARD_STATS_BOTTOM - CARD_ART_GAP - CARD_ART_TOP)
	art.BackgroundColor3 = FIELD.well
	art.BackgroundTransparency = 0
	art.BorderSizePixel = 0
	art.Image = ""
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = card

	local artCorner = Instance.new("UICorner")
	artCorner.CornerRadius = UDim.new(0, 6)
	artCorner.Parent = art

	local artEdge = Instance.new("UIStroke")
	artEdge.Color = FIELD.rule
	artEdge.Thickness = 1
	artEdge.Parent = art

	-- Clear over the well, so the well's own fill is the backdrop. The camera is made
	-- once here and only ever moved; paintArt swaps the model in front of it.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "CardModel"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = ART_LIGHT.ambient
	viewport.LightColor = ART_LIGHT.color
	viewport.LightDirection = ART_LIGHT.direction
	viewport.Parent = art

	local camera = Instance.new("Camera")
	camera.FieldOfView = ART_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- ── Stat block ───────────────────────────────────────────────────
	-- Pinned by its BOTTOM edge just above the button and sized to its visible rows,
	-- so the rows sit together at the foot of the card and the art gets the rest.
	local stats = Instance.new("Frame")
	stats.Name = "CardStats"
	stats.AnchorPoint = Vector2.new(0, 1)
	stats.Position = UDim2.fromOffset(CARD_INSET, CARD_STATS_BOTTOM)
	stats.Size = UDim2.new(1, -2 * CARD_INSET, 0, 0)
	stats.AutomaticSize = Enum.AutomaticSize.Y
	stats.BackgroundTransparency = 1
	stats.Parent = card

	local statLayout = Instance.new("UIListLayout")
	statLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statLayout.Padding = UDim.new(0, STAT_ROW_GAP)
	statLayout.Parent = stats

	for index = 1, STAT_ROWS do
		makeStatRow(stats, index)
	end

	local buy = UIKit.button(card, {
		name = "CardBuy",
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, CARD_INSET, 1, -CARD_BUY_BOTTOM),
		size = UDim2.new(1, -2 * CARD_INSET, 0, CARD_BUY_HEIGHT),
		font = FIELD.headline,
		textSize = 22,
		cornerRadius = UDim.new(0, 5),
		strokeThickness = 1,
		outline = false,
		shadow = false,
	})
	buy.LayoutOrder = 9

	local focus = UIKit.button(card, {
		name = "CardFocus",
		size = UDim2.fromScale(1, 1),
		text = "",
		textSize = 1,
		fillColor = FIELD.panel,
		fillTransparency = NEIGHBOUR_VEIL,
		cornerRadius = UDim.new(0, 8),
		strokeThickness = 0,
		outline = false,
		shadow = false,
		zIndex = 20,
	})
	focus.Selectable = false

	return card
end

--- Put every piece of shop text in the cartoon outline: a rounded INK stroke scaled
--- to the text, the same recipe StandCardController's `text` uses. One pass over the
--- finished shop rather than a flag on each of its dozen labels, so a label added
--- later picks it up without anyone remembering to ask. Buttons with no text (the
--- arrows, dots and veils are all `textSize = 1`) are skipped.
---
--- On a TextButton the stroke's default Contextual mode outlines the GLYPHS, not the
--- box, which is what the buy button wants — paintShopCard no longer recolours it.
local function inkShopText(root: Instance)
	for _, node in root:GetDescendants() do
		if not (node:IsA("TextLabel") or node:IsA("TextButton")) or node.TextSize <= 1 then
			continue
		end
		local stroke = node:FindFirstChildOfClass("UIStroke")
		if stroke == nil then
			stroke = Instance.new("UIStroke")
			stroke.Parent = node
		end
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Color = FIELD.ink
		stroke.Thickness = math.clamp(node.TextSize / 9, 1.5, 3.5)
		node.TextStrokeTransparency = 1
	end
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
	ui.canvas = canvas

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

	-- The panel's own shrink-to-fit on a short screen (fitPanel below). The close badge
	-- is not inside the panel, so it wears the same factor by hand, or a full-size badge
	-- lands on the shrunken wallet beside it.
	local fitScale = Instance.new("UIScale")
	fitScale.Parent = panel
	ui.panelFit = fitScale
	local closeFit = Instance.new("UIScale")
	closeFit.Parent = closeButton

	local function repositionClose()
		-- AbsolutePosition / AbsoluteSize are SCREEN pixels and the button's Offset is a
		-- design pixel on the same UIKit canvas, so measure from the canvas's own corner
		-- and divide by its scale — or the badge drifts off the corner as the HUD scales.
		local s = UIKit.canvasScale(canvas)
		local inset = 14 * fitScale.Scale
		local corner = (panel.AbsolutePosition - canvas.AbsolutePosition) / s
		closeButton.Position = UDim2.fromOffset(corner.X + panel.AbsoluteSize.X / s - inset, corner.Y + inset)
		closeFit.Scale = fitScale.Scale
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionClose)
	panel:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionClose)
	repositionClose()

	-- See FIT_TOP. Everything is measured unscaled (divided back out of AbsoluteSize),
	-- so setting the scale does not feed back into the next measurement.
	local function fitPanel()
		local s = UIKit.canvasScale(canvas)
		local screenHeight = canvas.AbsoluteSize.Y / s
		local height = panel.AbsoluteSize.Y / (s * fitScale.Scale)
		if screenHeight <= 0 or height <= 0 then
			return
		end
		local room = screenHeight - FIT_TOP - FIT_BOTTOM
		local fit = math.min(1, math.floor(room / height * 1000) / 1000)
		if math.abs(fitScale.Scale - fit) > 0.001 then
			fitScale.Scale = fit
		end
		-- Centred as always, unless that leaves its bottom edge under the hotbar.
		local overlap = (screenHeight + height * fit) / 2 - (screenHeight - FIT_BOTTOM)
		panel.Position = UDim2.new(0.5, 0, 0.5, -math.max(0, overlap))
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel)
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel)
	fitPanel()

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
	-- accent bar in the stall's own colour, the track name, and the wallet on the
	-- right. (The "N units on the rail" stock line under the name was cut on request.) Building it inside `ui.shop` rather than reshaping the
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
	header.Size = UDim2.new(1, 0, 0, 48)
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
	accentBar.Position = UDim2.new(0, 0, 0.5, -1)
	accentBar.Size = UDim2.fromOffset(4, 32)
	accentBar.BackgroundColor3 = FIELD.amber
	accentBar.BorderSizePixel = 0
	accentBar.Parent = header
	ui.shopAccent = accentBar

	-- LuckiestGuy is all-caps already; render() upper-cases the track name anyway so
	-- a font swap never silently turns it back into "Detector".
	ui.shopTitle = UIKit.label(header, {
		name = "ShopTitle",
		position = UDim2.fromOffset(16, 0),
		size = UDim2.new(1, -230, 1, -1),
		font = FIELD.headline,
		textSize = 30,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})

	-- Inset from the panel's right edge by the close badge's width, which sits over
	-- this corner (repositionClose) and used to cover the top of the wallet.
	UIKit.label(header, {
		name = "WalletLabel",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 3),
		size = UDim2.fromOffset(200, 14),
		font = FIELD.label,
		textSize = 12,
		color = FIELD.text,
		text = "ON HAND",
		xAlign = Enum.TextXAlignment.Right,
		outline = false,
		shadow = false,
	})

	ui.shopCash = UIKit.label(header, {
		name = "Cash",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 18),
		size = UDim2.fromOffset(200, 30),
		font = FIELD.headline,
		textSize = 26,
		color = FIELD.amber,
		xAlign = Enum.TextXAlignment.Right,
		outline = false,
		shadow = false,
	})

	-- ── The carousel ─────────────────────────────────────────────────
	-- A clipping window over one long row. The row (`Strip`) is every card side by
	-- side at a fixed CAROUSEL_STEP, and moving along it is moving the ROW, placed from
	-- the window's centre (Scale 0.5) so the focused card is centred at any panel
	-- width. Not a ScrollingFrame: it has no snap, its CanvasPosition is in screen
	-- pixels under the canvas's UIScale, and its own wheel handling scrolls vertically.
	-- Every way of moving the row goes through setShopFocus instead — see Station.start.
	--
	-- Active so the mouse wheel over it is marked game-processed and does not also
	-- zoom the camera.
	local carousel = Instance.new("Frame")
	carousel.Name = "Cards"
	carousel.LayoutOrder = 1
	carousel.Size = UDim2.new(1, 0, 0, CAROUSEL_HEIGHT)
	carousel.BackgroundTransparency = 1
	carousel.ClipsDescendants = true
	carousel.Active = true
	carousel.Parent = shop
	ui.shopCarousel = carousel

	local row = Instance.new("Frame")
	row.Name = "Strip"
	row.AnchorPoint = Vector2.new(0, 0.5)
	row.Position = UDim2.new(0.5, -CARD_WIDTH / 2, 0.5, 0)
	row.Size = UDim2.fromOffset(CARD_SLOTS * CAROUSEL_STEP, CARD_HEIGHT)
	row.BackgroundTransparency = 1
	row.Parent = carousel
	ui.shopRow = row

	ui.shopCards = {}
	for index = 1, CARD_SLOTS do
		table.insert(ui.shopCards, makeShopCard(row, index))
	end

	-- The two arrows, over the peeks at either edge. The chevron is two rotated bars
	-- rather than a glyph: ◀/▶ render as colour emoji on some clients (the ☢ on the
	-- rad meter did), and a "<" in any of this panel's faces reads as code.
	local function makeArrow(name: string, side: number): TextButton
		local arrow = UIKit.button(carousel, {
			name = name,
			anchorPoint = Vector2.new(if side < 0 then 0 else 1, 0.5),
			position = UDim2.new(if side < 0 then 0 else 1, -side * 6, 0.5, 0),
			size = UDim2.fromOffset(42, 76),
			text = "",
			textSize = 1,
			fillColor = FIELD.panel,
			fillTransparency = 0.1,
			strokeColor = FIELD.edge,
			strokeThickness = 1,
			cornerRadius = UDim.new(0, 6),
			outline = false,
			shadow = false,
			zIndex = 30,
		})
		-- The apex points `side`; each bar's centre sits half a bar back from it and
		-- half a bar above or below, turned 45° toward the apex.
		for _, up in { -1, 1 } do
			local bar = Instance.new("Frame")
			bar.Name = "Chevron"
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.new(0.5, 0, 0.5, up * 5)
			bar.Size = UDim2.fromOffset(16, 3)
			bar.Rotation = -side * up * 45
			bar.BackgroundColor3 = FIELD.text
			bar.BorderSizePixel = 0
			bar.ZIndex = 31
			bar.Parent = arrow
		end
		return arrow
	end
	ui.shopPrev = makeArrow("Prev", -1)
	ui.shopNext = makeArrow("Next", 1)

	-- ── The pager ────────────────────────────────────────────────────
	-- One dot per tier, the focused one stretched into a pill, and "3 / 8" beside it.
	-- Each dot is a button straight to that tier. Dots carry ownership as well
	-- (amber = in hand, light = owned), so the row can be read without paging it.
	local pager = Instance.new("Frame")
	pager.Name = "Pager"
	pager.LayoutOrder = 2
	pager.Size = UDim2.new(1, 0, 0, 22)
	pager.BackgroundTransparency = 1
	pager.Parent = shop
	ui.shopPager = pager

	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.Size = UDim2.fromScale(1, 1)
	dots.BackgroundTransparency = 1
	dots.Parent = pager

	local dotLayout = Instance.new("UIListLayout")
	dotLayout.FillDirection = Enum.FillDirection.Horizontal
	dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	dotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dotLayout.Padding = UDim.new(0, 8)
	dotLayout.Parent = dots

	ui.shopDots = {}
	for index = 1, CARD_SLOTS do
		local dot = UIKit.button(dots, {
			name = `Dot{index}`,
			size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE),
			text = "",
			textSize = 1,
			fillColor = FIELD.edge,
			fillTransparency = 0,
			cornerRadius = UDim.new(0.5, 0),
			strokeThickness = 0,
			outline = false,
			shadow = false,
		})
		dot.LayoutOrder = index
		dot.Visible = false
		table.insert(ui.shopDots, dot)
	end

	ui.shopCounter = UIKit.label(pager, {
		name = "Counter",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.new(0, 80, 1, 0),
		font = FIELD.label,
		textSize = 15,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Right,
		outline = false,
		shadow = false,
	})

	-- Shown instead of the carousel when a shop has no track behind it at all.
	ui.shopEmpty = UIKit.label(shop, {
		name = "Empty",
		size = UDim2.new(1, 0, 0, 28),
		font = FIELD.label,
		textSize = 16,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Center,
		text = "nothing for sale here",
		visible = false,
		outline = false,
		shadow = false,
	})
	ui.shopEmpty.LayoutOrder = 3

	inkShopText(shop)

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
--- A FLAG CELL KEEPS THE BAR'S GEOMETRY AND THROWS AWAY ITS MEANING: a capability is
--- not an amount, so the row prints YES/NO and fills its track whole or not at all.
--- Sharing the row shape is what keeps the button on the same baseline whether a track
--- has two numeric stats or a mix. Currently exercised by no track — see makeStatRow.
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

--- A fresh copy of one tier's model, or nil for a track with no art. Code-authored
--- first, the place's Assets/Tools second — the order build/Shops' `tierTemplate` uses
--- and for its reason: Assets/Tools/Cleaner still holds the retired brushes and sponges,
--- and they must not win over the hoses ToolModels builds.
local function artModel(track: string, tier: number): Model?
	if ToolModels.has(track) then
		return ToolModels.create(track, tier)
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local library = if assets then assets:FindFirstChild("Tools") else nil
	local folder = if library then library:FindFirstChild(track) else nil
	local template = if folder then folder:FindFirstChild(`T{tier}`) else nil
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return nil
end

local BOX_CORNERS = {}
for _, x in { -1, 1 } do
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(BOX_CORNERS, Vector3.new(x, y, z))
		end
	end
end

--- Aim `camera` so `model` fills a well `aspect` wide per unit tall, seen from `view`.
---
--- THE BOX IS MEASURED IN THE CAMERA'S OWN AXES: every visible part's eight corners are
--- turned into the view's frame, then min/max. `GetBoundingBox` would hand back a box
--- aligned to the model, whose corners overstate a three-quarter view and leave the
--- model floating small in the middle of the well. Invisible parts (every tool's Grip)
--- are skipped, or a hidden handle nub would decide the framing.
---
--- The fit is taken at the box's NEAR face, where perspective makes things largest, so
--- nothing can poke past the edge.
local function frameArt(camera: Camera, model: Model, view: ArtView, aspect: number)
	local look = CFrame.lookAt(Vector3.zero, -view.from.Unit, view.up)
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local half = part.Size / 2
			for _, corner in BOX_CORNERS do
				local point = look:PointToObjectSpace(part.CFrame * (half * corner))
				lo = lo:Min(point)
				hi = hi:Max(point)
			end
		end
	end
	if lo.X > hi.X then
		return
	end

	local mid = (lo + hi) / 2
	local extent = (hi - lo) / 2
	local tanHalf = math.tan(math.rad(ART_FOV) / 2)
	local reach = math.max(extent.Y / tanHalf, extent.X / (tanHalf * aspect)) * ART_MARGIN
	camera.CFrame = look * CFrame.new(mid.X, mid.Y, hi.Z + reach)
end

--- Put `track`'s tier `tier` in the card's well. Cards are REUSED across stalls and
--- this runs on every StationState tick, so the model is only rebuilt when the card is
--- asked for a different tier or track than it already shows (`ArtKey`) — which is
--- once, the first time a stall is opened.
---
--- The well's height is per track (paintShopCard sizes it to the stat block), so the
--- aspect comes from that design height rather than from AbsoluteSize, which reads 0
--- until the panel has been laid out once.
local function paintArt(card: Frame, track: string, tier: number, artHeight: number)
	local key = `{track}/{tier}`
	if card:GetAttribute("ArtKey") == key then
		return
	end
	card:SetAttribute("ArtKey", key)

	local viewport = card.CardArt.CardModel :: ViewportFrame
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end

	local view = ART_VIEW[track]
	local model = if view then artModel(track, tier) else nil
	if model == nil or view == nil then
		return
	end

	for _, name in ART_HIDE do
		local extra = model:FindFirstChild(name)
		if extra then
			extra:Destroy()
		end
	end
	-- The views are written in the model's own frame, so its pivot goes to the origin.
	model:PivotTo(CFrame.identity)
	model.Parent = viewport
	frameArt(viewport.CurrentCamera :: Camera, model, view, (CARD_WIDTH - 2 * CARD_INSET) / artHeight)
end

--- Four states, and all four are drawn on the same card rather than on four layouts.
---
--- ISSUED    the one in your hands. Amber edge, a ghost button that says so.
--- OWNED     bought and not held. The button is a live EQUIP — see ShopService's note
---           on why ownership being a set is what makes that a real verb.
--- (buyable) no flag at all. The price button already says it is for sale, and a word
---           saying the same thing on every unbought card was noise — this is where
---           "AVAILABLE" used to be.
--- NEED $x   buyable, unaffordable. The flag carries the SHORTFALL against your wallet
---           rather than the price, because the price is already on the button and the
---           gap is the thing you do not know.
local function paintShopCard(card: Frame, entry, track: string, accent: Color3, cash: number)
	local nameLabel = card.CardStrip.CardName :: TextLabel
	local flag = card.CardStrip.CardFlag :: TextLabel
	local art = card.CardArt :: ImageLabel
	local buy = card.CardBuy :: TextButton
	local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke

	nameLabel.Text = entry.name
	-- The art well fills everything the stat block does not use.
	local rows = math.min(#entry.stats, STAT_ROWS)
	local statsHeight = if rows > 0 then rows * STAT_ROW_HEIGHT + (rows - 1) * STAT_ROW_GAP else 0
	local artHeight = CARD_STATS_BOTTOM - statsHeight - CARD_ART_GAP - CARD_ART_TOP
	art.Size = UDim2.new(1, -2 * CARD_INSET, 0, artHeight)
	paintArt(card, track, entry.tier, artHeight)
	card:SetAttribute("Buyable", entry.buyable == true)
	card:SetAttribute("Equippable", entry.equippable == true)
	card:SetAttribute("Tier", entry.tier)

	local affordable = entry.affordable == true
	local dear = entry.buyable == true and not affordable

	-- The bar colour is the card's whole mood: amber for the one you hold, the stall's
	-- accent for anything live, grey for a rung you cannot pay for yet.
	local barColour = if entry.current then FIELD.amber elseif dear then FIELD.muted else accent
	paintStats(card, entry, barColour)

	nameLabel.TextColor3 = FIELD.text

	if entry.current then
		cardStroke.Color = FIELD.amber
		flag.Text = "ISSUED"
		flag.TextColor3 = FIELD.amber
		buy.Text = "IN HAND"
		buy.TextColor3 = FIELD.amber
		buy.BackgroundTransparency = 1
	elseif entry.owned then
		cardStroke.Color = FIELD.edge
		flag.Text = "OWNED"
		flag.TextColor3 = FIELD.text
		buy.Text = "EQUIP"
		buy.TextColor3 = FIELD.text
		buy.BackgroundColor3 = FIELD.ownedFill
		buy.BackgroundTransparency = 0
	elseif dear then
		cardStroke.Color = FIELD.edge
		flag.Text = `NEED {money(entry.price - cash)}`
		flag.TextColor3 = FIELD.short
		buy.Text = money(entry.price)
		buy.TextColor3 = FIELD.muted
		buy.BackgroundColor3 = FIELD.dearFill
		buy.BackgroundTransparency = 0
	else
		cardStroke.Color = FIELD.edge
		flag.Text = ""
		-- Affordable is the ONE solid fill anywhere on this panel. Everything else is
		-- outlined, ghosted or muted, so the things worth clicking are the only things
		-- that look clickable.
		buy.Text = money(entry.price)
		buy.TextColor3 = FIELD.text
		buy.BackgroundColor3 = FIELD.amber
		buy.BackgroundTransparency = 0
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

--- U+2713 first, the word after it. The price card's fonts have no check glyph, so
--- this leans on Roblox's font fallback — and if that ever fails, what is left on the
--- card is the word, which still says the thing. A bare check would leave a tofu box.
---
--- TWO WORDS, NOT ONE, SINCE OWNERSHIP BECAME A SET. The rack used to paint one green
--- tick on every tier at or below yours, which is exactly the complaint that started
--- this: eight identical ticks after buying one detector, and no way to tell which
--- tool you were actually holding. EQUIPPED is the one in your hands; OWNED is a tool
--- you bought and are not using, and its card's button equips it rather than
--- charging you for it again.
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
--- green EQUIPPED tick; a tier you own but are not holding gets a neutral OWNED tick;
--- everything else keeps the price it was built with.
---
--- THE PROMPT IS NOT TOUCHED ANY MORE. It used to flip from "Buy $x" to "Equip" per
--- player, because its E did whichever of the two applied. Now its E only opens the
--- tier's card (see `rackCard`), so it says "View" to everyone and the card's button
--- carries the verb.
---
--- RESTORE READS RestText / RestColor OFF THE LABEL, the same trick LiquidService uses
--- to put the wash pad's sign back after it announces a roll: the builder stamps the
--- as-built values onto the instance itself, so whatever overwrites it never has to
--- remember what was there. A hook with no SellsTier is skipped entirely rather than
--- restored — that is the Luck button, whose subtitle is owned by ExhibitService and
--- must not be touched here.
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
		if entry ~= nil and entry.current then
			sub.Text = EQUIPPED_TEXT
			sub.TextColor3 = COLOR.green
		elseif entry ~= nil and entry.owned then
			sub.Text = OWNED_TEXT
			sub.TextColor3 = COLOR.text
		else
			sub.Text = (sub:GetAttribute("RestText") :: string?) or sub.Text
			sub.TextColor3 = (sub:GetAttribute("RestColor") :: Color3?) or sub.TextColor3
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

-- ── Carousel focus ───────────────────────────────────────────────────────────
--
-- WHICH CARD IS IN THE MIDDLE IS CLIENT STATE, AND ONLY CLIENT STATE. The server's
-- offer is the whole ladder every tick and knows nothing about paging; every way of
-- moving along the row — arrows, wheel, drag, dots, a click on a peeking card — ends
-- in setShopFocus, and render() only ever re-picks the focus when the panel opens.
local carousel = {
	focus = 1,
	count = 0,
	-- Design px the row is currently dragged off its resting place.
	drag = 0,
	-- The shop the focus was last chosen for. Cleared whenever the panel is not
	-- showing a shop, so opening it again starts on a fresh card instead of wherever
	-- you left it last visit.
	openedFor = nil :: string?,
	tiers = nil :: { any }?,
	accent = FIELD.amber,
	-- Showing one rack card rather than the row (see `rackCard`), and which tier it
	-- was last put up for, so the open pop plays once per card rather than per tick.
	single = false,
	singleFor = nil :: string?,
}
local rowTween: Tween? = nil

local function placeRow(animate: boolean)
	if rowTween then
		rowTween:Cancel()
		rowTween = nil
	end
	local target = UDim2.new(0.5, -CARD_WIDTH / 2 - (carousel.focus - 1) * CAROUSEL_STEP + carousel.drag, 0.5, 0)
	if animate then
		rowTween = TweenService:Create(ui.shopRow, CAROUSEL_TWEEN, { Position = target })
		rowTween:Play()
	else
		ui.shopRow.Position = target
	end
end

--- Dots, counter and arrows. Plain property writes with no tweens, so render() can
--- call this on every tick — buying a tier recolours its dot without the focus moving.
local function paintPager()
	local tiers = carousel.tiers
	for index, dot in ui.shopDots do
		local entry = if tiers then tiers[index] else nil
		dot.Visible = entry ~= nil
		if entry == nil then
			continue
		end
		local focused = index == carousel.focus
		dot.Size = UDim2.fromOffset(if focused then DOT_FOCUS_WIDTH else DOT_SIZE, DOT_SIZE)
		dot.BackgroundColor3 = if focused
			then carousel.accent
			elseif entry.current then FIELD.amber
			elseif entry.owned then FIELD.dim
			else FIELD.edge
	end
	ui.shopCounter.Text = if carousel.count > 0 then `{carousel.focus} / {carousel.count}` else ""
	ui.shopPrev.Visible = carousel.focus > 1
	ui.shopNext.Visible = carousel.focus < carousel.count
end

--- Neighbours shrink and go behind the veil; the focused card comes forward. The
--- veil is also what catches a click on a neighbour, so it is hidden outright on the
--- focused card once its fade finishes — or it would sit over the buy button.
local function paintFocus(animate: boolean)
	for index, card in ui.shopCards do
		local focused = index == carousel.focus
		local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
		local veil = card.CardFocus :: TextButton
		local scaleTarget = if focused then 1 else NEIGHBOUR_SCALE
		local veilTarget = if focused then 1 else NEIGHBOUR_VEIL
		if not focused then
			veil.Visible = true
		end
		if animate then
			TweenService:Create(scale, CAROUSEL_TWEEN, { Scale = scaleTarget }):Play()
			local fade = TweenService:Create(veil, CAROUSEL_TWEEN, { BackgroundTransparency = veilTarget })
			if focused then
				fade.Completed:Connect(function(playback)
					if playback == Enum.PlaybackState.Completed and carousel.focus == index then
						veil.Visible = false
					end
				end)
			end
			fade:Play()
		else
			scale.Scale = scaleTarget
			veil.BackgroundTransparency = veilTarget
			veil.Visible = not focused
		end
	end
end

local function setShopFocus(index: number, animate: boolean)
	carousel.focus = math.clamp(index, 1, math.max(carousel.count, 1))
	carousel.drag = 0
	placeRow(animate)
	paintFocus(animate)
	paintPager()
end

--- Where the row opens: the first rung past the one in your hands that you do not
--- own yet — the upgrade you most likely walked over for, with your own tool peeking
--- in on its left. Owning everything above it, the one in your hands.
local function defaultShopFocus(tiers: { any }): number
	local current = 0
	for index, entry in tiers do
		if entry.current then
			current = index
		end
	end
	for index = current + 1, #tiers do
		if not tiers[index].owned then
			return index
		end
	end
	return math.max(current, 1)
end

local function render()
	if state.station == nil or dismissed or not PANEL_KINDS[state.station] then
		ui.panel.Visible = false
		ui.closeButton.Visible = false
		carousel.openedFor = nil
		carousel.singleFor = nil
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

	-- One rack card, if a rack hook's E opened this and it is for the shop you are at.
	local offerTiers = if atShop and state.offer then state.offer.tiers else nil
	local single = atShop
		and rackCard ~= nil
		and rackCard.track == state.stationId
		and offerTiers ~= nil
		and offerTiers[rackCard.tier] ~= nil
	carousel.single = single

	local shopWidth = if single then RACK_PANEL_WIDTH else SHOP_PANEL_WIDTH
	ui.panelSize.MaxSize = Vector2.new(if atShop then shopWidth else PANEL_WIDTH, math.huge)

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

		ui.shopCarousel.Visible = count > 0
		ui.shopPager.Visible = count > 0 and not single
		ui.shopEmpty.Visible = count == 0

		for index, card in ui.shopCards do
			local entry = if tiers then tiers[index] else nil
			-- A rack card shows its own tier and nothing either side of it.
			card.Visible = entry ~= nil and (not single or index == (rackCard :: any).tier)
			if entry then
				paintShopCard(card, entry, track, accent, cash)
			end
		end

		ui.shopCash.Text = money(cash)

		-- Re-pick the focus only on opening (or when the offer first arrives with
		-- tiers in it); every other tick keeps the card you paged to and just repaints
		-- the pager. A changed count clamps rather than resets.
		local previous = carousel.count
		carousel.tiers = tiers
		carousel.accent = accent
		carousel.count = count
		if single then
			-- Focused on the rack card's tier, which also leaves the storefront there if
			-- the stand's E swaps this card for the whole row.
			local tier = (rackCard :: any).tier
			local key = `{track}/{tier}`
			if carousel.focus ~= tier or carousel.singleFor ~= key then
				setShopFocus(tier, false)
			end
			if carousel.singleFor ~= key then
				carousel.singleFor = key
				local pop = ui.shopCards[tier]:FindFirstChildOfClass("UIScale") :: UIScale
				pop.Scale = RACK_CARD_POP
				TweenService:Create(pop, RACK_CARD_TWEEN, { Scale = 1 }):Play()
			end
			ui.shopPrev.Visible = false
			ui.shopNext.Visible = false
		elseif tiers and count > 0 and (carousel.openedFor ~= track or previous == 0) then
			setShopFocus(defaultShopFocus(tiers), false)
		elseif count ~= previous then
			setShopFocus(carousel.focus, false)
		else
			paintPager()
		end
		if not single then
			carousel.singleFor = nil
		end
		carousel.openedFor = track

		for _, row in ui.rows do
			row.Visible = false
		end
		ui.sellButton.Visible = false
		return
	end

	carousel.openedFor = nil

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

	-- ── Moving along the carousel ────────────────────────────────────
	-- All of it goes through setShopFocus. The wheel and the drag are read off
	-- UserInputService with `gameProcessed` ignored — over a GUI it is always true —
	-- and hit-tested against the carousel's own rect instead. InputObject.Position is
	-- below the topbar inset, the same space as this gui's AbsolutePosition
	-- (IgnoreGuiInset is false, see build()).
	-- A rack card is one card with nothing to page to, so it takes none of this input.
	local function shopShowing(): boolean
		return ui.panel.Visible and ui.shop.Visible and carousel.count > 0 and not carousel.single
	end
	local function overCarousel(position: Vector3): boolean
		local corner = ui.shopCarousel.AbsolutePosition
		local size = ui.shopCarousel.AbsoluteSize
		return position.X >= corner.X
			and position.X <= corner.X + size.X
			and position.Y >= corner.Y
			and position.Y <= corner.Y + size.Y
	end

	ui.shopPrev.MouseButton1Click:Connect(function()
		setShopFocus(carousel.focus - 1, true)
	end)
	ui.shopNext.MouseButton1Click:Connect(function()
		setShopFocus(carousel.focus + 1, true)
	end)
	for index, dot in ui.shopDots do
		dot.MouseButton1Click:Connect(function()
			setShopFocus(index, true)
		end)
	end

	-- A DRAG IS NOT A CLICK. Releasing a drag over a button still fires its
	-- MouseButton1Click, so `dragMoved` stays set from the moment a press passes
	-- DRAG_SLOP until the next press, and every button on the row checks it.
	local dragInput: InputObject? = nil
	local dragStartX = 0
	local dragMoved = false
	local lastWheel = 0

	for index, card in ui.shopCards do
		(card.CardFocus :: TextButton).MouseButton1Click:Connect(function()
			if not dragMoved then
				setShopFocus(index, true)
			end
		end)
	end

	UserInputService.InputBegan:Connect(function(input)
		if not shopShowing() then
			return
		end
		-- Shoulder buttons page on a gamepad; the stick is still walking you around.
		if input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.ButtonR1 then
			setShopFocus(carousel.focus + (if input.KeyCode == Enum.KeyCode.ButtonR1 then 1 else -1), true)
			return
		end
		local kind = input.UserInputType
		if (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and overCarousel(input.Position) then
			dragInput = input
			dragStartX = input.Position.X
			dragMoved = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseWheel then
			if shopShowing() and overCarousel(input.Position) and os.clock() - lastWheel >= WHEEL_COOLDOWN then
				lastWheel = os.clock()
				-- Wheel down (towards you) is next, the way a sideways list scrolls.
				setShopFocus(carousel.focus + (if input.Position.Z < 0 then 1 else -1), true)
			end
			return
		end
		if dragInput == nil then
			return
		end
		-- A mouse drag reports through separate MouseMovement objects; a touch
		-- updates the object it began with.
		local byMouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
		if (byMouse and kind ~= Enum.UserInputType.MouseMovement) or (not byMouse and input ~= dragInput) then
			return
		end
		-- Screen px to the row's own design px: the canvas scale, and the fit scale the
		-- panel wears on a short screen (fitPanel).
		local dx = (input.Position.X - dragStartX) / (UIKit.canvasScale(ui.canvas) * ui.panelFit.Scale)
		if not dragMoved and math.abs(dx) < DRAG_SLOP then
			return
		end
		dragMoved = true
		-- Where along the row the pointer has taken you, with anything past either
		-- end followed at DRAG_RUBBER.
		local rest = (carousel.focus - 1) * CAROUSEL_STEP
		local limit = (carousel.count - 1) * CAROUSEL_STEP
		local along = rest - dx
		if along < 0 then
			along *= DRAG_RUBBER
		elseif along > limit then
			along = limit + (along - limit) * DRAG_RUBBER
		end
		carousel.drag = rest - along
		placeRow(false)
	end)

	UserInputService.InputEnded:Connect(function(input)
		if dragInput == nil then
			return
		end
		local sameMouse = dragInput.UserInputType == Enum.UserInputType.MouseButton1
			and input.UserInputType == Enum.UserInputType.MouseButton1
		if input ~= dragInput and not sameMouse then
			return
		end
		dragInput = nil
		if not dragMoved then
			return
		end
		-- Settle on the nearest card, but a flick past DRAG_FLICK of a step always
		-- moves at least one.
		local steps = -carousel.drag / CAROUSEL_STEP
		local moved = math.floor(steps + 0.5)
		if moved == 0 and math.abs(steps) >= DRAG_FLICK then
			moved = if steps > 0 then 1 else -1
		end
		setShopFocus(carousel.focus + moved, true)
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
			-- `dragMoved` is left over from the last drag of the row, and a rack card
			-- cannot be dragged (shopShowing), so it never resets there: ignore it.
			if state.stationId == nil or (dragMoved and not carousel.single) then
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
		rackCard = nil
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
	-- MATCHED ON NAME: the stand's own prompt, and the rack hooks' (below). Anything
	-- else on this event is not ours.
	--
	-- WITH A RACK CARD UP, THE STAND'S E OPENS THE WHOLE ROW rather than closing, so
	-- "show me the rest" is one press from the card you were looking at. The row opens
	-- on that same tier (render leaves the focus where the card put it).
	--
	-- A RACK HOOK'S E OPENS ITS OWN CARD (see `rackCard`), and toggles it like the
	-- stand's does. The tier comes off the hook the prompt is parented to; Luck's
	-- button has no SellsTier and is left to ShopService, which buys on it.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeredBy)
		if triggeredBy ~= Players.LocalPlayer then
			return
		end
		if prompt.Name == BROWSE_PROMPT then
			local showingCard = rackCard ~= nil and not dismissed
			rackCard = nil
			if not showingCard then
				dismissed = not dismissed
			end
			render()
		elseif prompt.Name == RACK_PROMPT then
			local hook = prompt.Parent
			local track = if hook then hook:GetAttribute("SellsTrack") else nil
			local tier = if hook then hook:GetAttribute("SellsTier") else nil
			if type(track) ~= "string" or type(tier) ~= "number" then
				return
			end
			if rackCard ~= nil and rackCard.track == track and rackCard.tier == tier and not dismissed then
				rackCard = nil
				dismissed = true
			else
				rackCard = { track = track, tier = tier }
				dismissed = false
			end
			render()
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
			--
			-- A RACK CARD OPENED FOR THIS SHOP SURVIVES ARRIVING. A rack hook's reach
			-- can put its E under you a moment before the server's tick says you are in
			-- the shop's radius, so a card asked for just before that tick is kept open
			-- rather than dismissed by it. Any other change of station drops it.
			if rackCard ~= nil and payload.station == "shop" and payload.stationId == rackCard.track then
				dismissed = false
			else
				rackCard = nil
				dismissed = payload.station == "shop" and shopHasBrowsePrompt(payload.stationId)
			end
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
