--[[
	StationController.lua — the base camp panel.

	Appears at the trader, the shops and your own Quarantine Locker. The trader's body
	is its own module (client/TraderPanel, the buyback counter: a list of the bag with tick
	boxes, and a receipt that totals what is ticked above SELL), and so is the locker's
	(client/LockerPanel, a rack of specimen tubes over your bag); the shop's body is
	built here. Scrubbing left this file, see below.

	TWO BODIES ON ONE PANEL, AND THE SHRINKING IS THE POINT. The plot claim board was a mode until exhibit
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

	WHAT WENT WITH THE DECON PANEL: the RACK button and the Quarantine Locker rows. For
	a while nothing in the world could put a find in the locker at all; it came back as
	its own station (StationKind = "locker", the tube rack beside the tub) with its own
	E prompt and its own body here, LockerPanel.

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
	tall panel on a short viewport can still reach the hotbar. fitPanel() shrinks
	and lifts it clear. StationHud draws OVER the dock (DisplayOrder 102, above
	RadHud's 100), so the health/rads bars never cut across a card.

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
	"Bent Coil → Scrap Sweeper", the deltas between them, and a BUY button — which
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
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)
local GearProducts = require(Shared.Config.GearProducts)
local Camps = require(Shared.Config.Camps) -- a locked card's zone number
local Net = require(Shared.Net)
local Tutorial = require(Shared.Config.Tutorial)
local AuraLook = require(Shared.AuraLook)

-- No `Dock` alias any more: this panel is centred on the screen rather than on the
-- space above the dock, so it no longer reads Dock.RESERVE. See the header.
local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)
local GearArt = require(script.Parent.Parent.GearArt)
local Prefs = require(script.Parent.Parent.Prefs)
local Studded = require(script.Parent.Parent.Studded) -- the studded look's shared tiles
local TraderPanel = require(script.Parent.Parent.TraderPanel)
local LockerPanel = require(script.Parent.Parent.LockerPanel)
local MergePanel = require(script.Parent.Parent.MergePanel)
local ReforgePanel = require(script.Parent.Parent.ReforgePanel)
local FurnacePanel = require(script.Parent.Parent.FurnacePanel)
local LockerTutorial = require(script.Parent.Parent.LockerTutorial)

local Station = {}

-- Same fields UIKit.C already carries (panel/stroke/selected/text/dim/green/amber/
-- red/blue), aliased so every COLOR.xxx read below keeps working unchanged.
local COLOR = UIKit.C

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
--
-- THE LOCKER IS IN HERE, and opens only on its own E ("OpenLocker"), like a shop with
-- a browse prompt: it stands right beside the tub, and a panel that opened on
-- approach would sit over the screen every time you walked to the wash.
--
-- THE MERGE REACTOR (Toxic Twilight) opens the same way, on its own E ("OpenMerge"),
-- and so does the REFORGE STATION beside it ("OpenReforge"), and Magma Hollow's SLAG
-- FURNACE ("OpenFurnace").
local PANEL_KINDS: { [string]: boolean } = {
	trader = true,
	shop = true,
	locker = true,
	merge = true,
	reforge = true,
	furnace = true,
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
-- you there is more to the left and right. Arrows, the mouse wheel, a drag, the
-- scrollbar or a click on a peeking card move along the row; it always settles with one
-- card centred.
--
-- CARD_SLOTS IS A CEILING OVER EVERY TRACK, READ OFF CONFIG/GEAR. It was typed as 8
-- when Detector was the longest track at 8 tiers, and then the Rust Bucket made it 9
-- and Toxic Twilight's six made it 15: a typed ceiling one short is a card that never
-- draws (and, from a rack's E, an index into a nil card). A stall lists at most the whole
-- track, so the longest track is the most cards one can show. Cards are built once at
-- that count and hidden, the same reuse the trader's bag tiles use, because a shop panel
-- that rebuilds its children on every StationState tick would churn a dozen frames'
-- worth of instances ten times a second.
local CARD_SLOTS = 1
for _, track in Gear.TRACKS do
	CARD_SLOTS = math.max(CARD_SLOTS, Gear.maxTier(track))
end
local CARD_WIDTH = 340
-- 470 + the 20px the pager row gave back when the scrollbar replaced it (2026-10-05).
local CARD_HEIGHT = 490
local CARD_GAP = 18
-- How much of each neighbour shows at the panel's edges on a full-width panel. On a
-- viewport too narrow for the ceiling, the panel narrows and the peeks go first; the
-- focused card stays whole and centred because the row is placed from the carousel's
-- own centre (Scale 0.5), not from its left edge.
local CARD_PEEK = CARD_WIDTH -- THREE WHOLE CARDS ACROSS (2026-10-04, on request: the studded-card shop)
-- Distance from one card's centre to the next — one "notch" of the carousel.
local CAROUSEL_STEP = CARD_WIDTH + CARD_GAP
-- The scrollbar under the cards, inside the carousel window (2026-10-05, on request:
-- "one complete scroll bar" in place of the pager dots, so the cards could grow).
local SCROLL_HEIGHT = 12
local SCROLL_GAP = 6
-- A few px taller than a card so the focused card's stroke is never clipped.
local CARD_BAND = CARD_HEIGHT + 8
local CAROUSEL_HEIGHT = CARD_BAND + SCROLL_GAP + SCROLL_HEIGHT
-- Neighbours sit slightly smaller and behind a slate veil, so the focused card is the
-- only thing on the row that reads as in front of you.
local NEIGHBOUR_SCALE = 1
local NEIGHBOUR_VEIL = 1
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
-- The close badge's 32px plus the 14px it is inset by, less the panel pad it shares.
local WALLET_INSET = 58
-- The header's SORT / SHOW pills (see build).
local FILTER_PILL_WIDTH = 190
local FILTER_PILL_HEIGHT = 34
local FILTER_PILL_GAP = 10

local PANEL_PAD = 16
-- The focused card, a gap and a peek either side, and the panel's own padding.
local SHOP_PANEL_WIDTH = CARD_WIDTH + 2 * (CARD_GAP + CARD_PEEK) + 2 * PANEL_PAD + 10 -- + the outer cards' 4px edges
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
-- THE TEXT IS ALL GOTHAM BLACK, on request: the face the cash/speed HUD and the Gear
-- panel's tabs speak. It used to be Oswald and RobotoMono (a spec-sheet voice), then
-- LuckiestGuy + FredokaOne (the cartoon voice). `headline` and `label` are kept as two
-- keys so the pieces can split again without a hunt, but they are one face today, all
-- white-ish and all wearing the same rounded INK outline — see inkShopText.
local FIELD = {
	panel = Color3.fromHex("1B1F23"),
	card = Color3.fromHex("22272C"),
	well = Color3.fromHex("1A1E22"),
	-- The shop card's art well, top to bottom: brightest a third of the way down, where
	-- the framed model's middle sits.
	wellFade = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("22282E")),
		ColorSequenceKeypoint.new(0.36, Color3.fromHex("2B3238")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("16191C")),
	}),
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
	-- The Robux button (Config/GearProducts): the one purple thing on the panel, so
	-- paying real money never looks like the cash price beside it.
	robux = Color3.fromHex("7B3FE4"),
	robuxHover = Color3.fromHex("9257F5"),
	-- The cartoon black every chunky card in the game is outlined in (CashController's
	-- and StandCardController's INK, Kit.C.hazardBlack).
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.GothamBlack,
	label = Enum.Font.GothamBlack,
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

--- THE STUDDED-CARD SHOP (2026-10-04, on request, after a reference the user sent: a
--- purple striped title bar, a big red X, and three chunky studded cards across, each a
--- solid colour with the item standing on it, a dark stat strip and a lime button).
--- Each card is the GEAR'S OWN COLOUR, brightened (GearArt.tint; on request, 2026-10-04:
--- "make the background relevant to the color and aesthetic of the gear"), so a gold
--- detector stands on gold and a violet hose on violet. Where you stand with the rung
--- is the button's job: dark EQUIPPED, lime EQUIP or price, grey NEED $x. Only a rung
--- sold in another zone keeps a state colour, dark slate. Since 2026-10-05 the cards,
--- the purple title bar and the dark backdrop all wear Studded.pattern (glossy L-studs).
local STUDDED = {
	-- Inked like the title bar and the X (2026-10-05, the glossy L-stud pattern pass).
	cardEdge = Studded.INK,
	cardPlain = Color3.fromHex("48D63A"), -- a track with no tint (GearArt.tint is nil)
	cardLocked = Color3.fromHex("3D4452"), -- sold in another zone (entry.lockedZone)
	-- The panel's own fill, see-through at the shop since 2026-10-05 (the dark
	-- studded backdrop under it is the colour now); kept for anything read off it.
	panel = Color3.fromHex("E4E9F2"),
	-- The purple of the shop background the user sent (2026-10-05), under the pattern.
	header = ColorSequence.new(Color3.fromHex("D63BFF"), Color3.fromHex("B406E6")),
	-- The panel behind the cards: dark grey with the L-studs (2026-10-05, on request).
	backdrop = Color3.fromHex("2B2F36"),
	cash = UIKit.House.cash,
	-- Buttons are white under a UIGradient, so one gradient per state is the fill.
	-- A pure, saturated green sampled off a reference button the user sent (2026-10-04),
	-- in place of the old yellow-lime; the key keeps its name so the paint states don't move.
	lime = ColorSequence.new(Color3.fromHex("85FF01"), Color3.fromHex("3FFE01")),
	equipped = ColorSequence.new(Color3.fromHex("43474F"), Color3.fromHex("33363C")),
	dear = ColorSequence.new(Color3.fromHex("9AA3B0"), Color3.fromHex("7C8594")),
	locked = ColorSequence.new(Color3.fromHex("5A6272"), Color3.fromHex("454C5A")),
	robux = ColorSequence.new(Color3.fromHex("A866FF"), Color3.fromHex("7A2FEA")),
	equippedText = Color3.fromHex("D2D6DC"),
	chip = Color3.fromHex("000000"),
	chipTransparency = 0.62,
	closeRed = Color3.fromHex("E5281F"),
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
-- Sits this far above dead centre when the screen has the room (never past FIT_TOP),
-- so the trader and the gear stalls ride a little higher than the true middle.
local PANEL_LIFT = 32
-- The trader's counter rides higher still, on request.
local TRADER_LIFT = 64
-- The gear stalls grew ~104px taller (taller card, roomier header and gaps), and on
-- request all of it went UPWARD: lifting by half the growth keeps the bottom edge
-- exactly where it sat before.
local SHOP_LIFT = PANEL_LIFT + 52
local FIT_BOTTOM = UIKit.Dock.HOTBAR_BOTTOM + UIKit.Dock.HOTBAR_HEIGHT + UIKit.Dock.GAP

local ui = {}
local state = { station = nil, items = {}, locker = {} }
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

--- THE GEAR INTRO (Gear.OVERVIEW): which stall's intro is up, or nil. Only the
--- header's "?" opens it: a stall opens straight onto its cards, on request.
local introTrack: string? = nil

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

--- The name build/Plots gives the locker rack's prompt (Plots.lockerStation), and how
--- long an E on it waits for the server to say you are at the locker. The prompt can
--- fire a tick before StationState catches up, and arriving at a station resets
--- `dismissed`, so the press is remembered for that long rather than lost.
local LOCKER_PROMPT = "OpenLocker"
local LOCKER_PRESS_GRACE = 1.5
local lockerPressedAt = -math.huge

--- The Merge Reactor's prompt (build/MergeReactor), with the same press grace.
local MERGE_PROMPT = "OpenMerge"
local mergePressedAt = -math.huge

--- The Reforge Station's prompt (build/ReforgeStation), with the same press grace.
local REFORGE_PROMPT = "OpenReforge"
local reforgePressedAt = -math.huge

--- The Slag Furnace's prompt (build/SlagFurnace), with the same press grace.
local FURNACE_PROMPT = "OpenFurnace"
local furnacePressedAt = -math.huge

--- THE LOCKER'S FIRST-VISIT TUTORIAL (client/LockerTutorial): a spotlight walk over the
--- panel, owed while the server's `lockerTutorial` is true. `tutorial` is the running
--- one; `tutorialDone` stops it re-running this session in the tick or two before the
--- server's flag catches up with the "tutorialSeen" we sent.
local tutorial: { stop: () -> () }? = nil
local tutorialDone = false

--- THE WALKTHROUGH'S "UPGRADE YOUR DETECTOR" (Config/Tutorial), ON REQUEST: opening the
--- Detector shop on that step pins the row on the Bent Coil and dims the whole screen
--- but its buy button, so the only thing to do is click the $15. The same spotlight as
--- the locker's, as a `press` step (clicks go through the hole and nowhere else). It
--- lets go the moment the Bent Coil is owned, the step moves on, or the panel closes.
local buySpotlight: { stop: () -> () }? = nil
local buySpotlightCard: Frame? = nil

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
--- and the Outfitter's counters have never had rack prompts, which made Aura and
--- Satchel unbuyable outright. The Aura gates every stage in the game.
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

-- ── Build ───────────────────────────────────────────────────────────

--- A CEILING OVER EVERY TRACK'S COLUMN COUNT, deliberately above the current high
--- water mark rather than equal to it. It was exactly Boots' five (speed, haul,
--- stamina, vault, dash); that track is retired and the widest live block is now three,
--- but the number is left at five so adding a fourth column to a track is a one-line
--- change in Config/Gear rather than a layout change here too.
---
--- Chips are built once at this count and hidden, the same reuse the cards themselves
--- use — a stat block that rebuilt its children on every StationState tick would churn
--- forty frames' worth of instances ten times a second.
local STAT_ROWS = 5
local STAT_CHIP_HEIGHT = 60
local STAT_CHIP_GAP = 8
local STAT_CHIP_PAD = 7
local STAT_LABEL_SIZE = 12
local STAT_VALUE_SIZE = 19
local STAT_BAR_HEIGHT = 5
local BAR_FLOOR = 0.06

-- The card's vertical stack, top to bottom: the name row, the art well, one row of stat
-- chips, the buy button. EVERY PIECE IS A FIXED HEIGHT, on request ("more space to
-- show the image"). The stats used to be one 30px row each with a long bar, and the
-- well took whatever they left, so the Aura's four rows cut the picture to 460x172 and
-- the Detector's three to 460x212. Now the stats share one row of chips whatever their
-- count, the name row lost its divider, the button lost 6px, and every track gets the
-- same 472x344 picture (the panel grew 80px upward for it, with roomier gaps).
local CARD_INSET = 14
local CARD_NAME_INSET = 18
local CARD_NAME_TOP = 12
local CARD_NAME_HEIGHT = 46
local CARD_ART_TOP = 68
local CARD_ROW_GAP = 16
local CARD_BUY_HEIGHT = 48
local CARD_BUY_BOTTOM = 18
local CARD_BUY_TOP = CARD_HEIGHT - CARD_BUY_BOTTOM - CARD_BUY_HEIGHT
-- Roblox's own Robux glyph (private-use U+E002), same as ShopController's Robux buttons.
local ROBUX = utf8.char(0xE002)
-- The purple Robux button splits the buy row on a tier sold for Robux: cash on the
-- left, this on the right.
local CARD_ROBUX_WIDTH = 104
local CARD_ROBUX_GAP = 10
local CARD_CHIPS_TOP = CARD_BUY_TOP - CARD_ROW_GAP - STAT_CHIP_HEIGHT
local CARD_ART_WIDTH = CARD_WIDTH - 2 * CARD_INSET
local CARD_ART_HEIGHT = CARD_CHIPS_TOP - CARD_ROW_GAP - CARD_ART_TOP

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
--
-- THE AURA'S ATOM IS THE ONE CARD THAT MOVES, also on request: AuraController circles
-- its camera and orbits its electrons (AuraLook.ICON_TAG). Nothing in this file knows;
-- it frames the atom like any other model.
-- The views, lighting and framing live in client/GearArt, shared with the Gear panel.
-- The card also asks for the tier's ToolFX (client/GearArtFx): the sparks, glow and
-- moving parts a held tool shows, which a ViewportFrame cannot render by itself.

--- Every card's stat tip, so closing the panel can put them all away: a chip that
--- vanishes under the mouse never gets its MouseLeave.
local statTips: { Frame } = {}

--- The card's stat explanation: a dark slip along the bottom of the art well, just
--- over the chip row, showing the hovered chip's Gear.STAT_META `tip`. One per card;
--- the chips find it through the card. `Chip` names the chip it is showing for, so
--- paintStats can keep it honest when the stall changes under the mouse.
local function makeStatTip(card: Frame): Frame
	local tip = UIKit.panel(card, {
		name = "StatTip",
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.fromOffset(CARD_INSET, CARD_CHIPS_TOP - 6),
		size = UDim2.fromOffset(CARD_ART_WIDTH, 40),
		color = FIELD.ink,
		transparency = 0.05,
		strokeColor = FIELD.edge,
		strokeThickness = 2,
		cornerRadius = UDim.new(0, 9),
		visible = false,
	})
	tip.ZIndex = 20
	local text = UIKit.label(tip, {
		name = "Text",
		position = UDim2.fromOffset(12, 3),
		size = UDim2.new(1, -24, 1, -6),
		font = FIELD.label,
		textSize = 15,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})
	text.TextWrapped = true
	text.ZIndex = 21
	table.insert(statTips, tip)
	return tip
end

--- Show `chip`'s tip on its card's slip, or hide the slip when `chip` is nil.
local function showStatTip(card: Instance, chip: Frame?)
	local tip = card:FindFirstChild("StatTip") :: Frame?
	if tip == nil then
		return
	end
	local line = if chip then chip:GetAttribute("Tip") else nil
	if chip == nil or typeof(line) ~= "string" or line == "" then
		tip.Visible = false
		tip:SetAttribute("Chip", nil)
		return
	end
	local text = tip:FindFirstChild("Text") :: TextLabel
	text.Text = line
	-- In the stat's own colour, so the line reads as belonging to the chip under it.
	local colour = chip:GetAttribute("TipColor")
	text.TextColor3 = if typeof(colour) == "Color3" then colour else FIELD.text
	tip:SetAttribute("Chip", chip.Name)
	tip.Visible = true
end

--- One chip of a card's stat row: the label small on top, the value under it, a thin
--- bar along the bottom. Chips are laid side by side and share the row's width, which
--- paintStats sets per track once it knows how many columns there are. A flag cell
--- reuses the same chip and simply fills its bar to 0 or 1.
---
--- NO LIVE TRACK USES A FLAG CELL any more: Boots' vault and dash were the only two,
--- and they were retired with it. The support is kept because `kind = "flag"` is still
--- a documented option in Gear.STAT_META and deleting the render path would make the
--- next boolean stat a two-file change instead of a one-line one.
local function makeStatChip(parent: Instance, order: number): Frame
	local chip = UIKit.panel(parent, {
		name = `Stat{order}`,
		size = UDim2.fromOffset(0, STAT_CHIP_HEIGHT),
		-- The reference's dark see-through strip, so the card's own colour shows through.
		color = STUDDED.chip,
		transparency = STUDDED.chipTransparency,
		strokeThickness = 0,
		cornerRadius = UDim.new(0, 7),
		visible = false,
	})

	local statLabel = UIKit.label(chip, {
		name = "StatLabel",
		position = UDim2.fromOffset(STAT_CHIP_PAD, 9),
		size = UDim2.new(1, -2 * STAT_CHIP_PAD, 0, 14),
		font = FIELD.label,
		textSize = STAT_LABEL_SIZE,
		color = FIELD.dim,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})

	local statValue = UIKit.label(chip, {
		name = "StatValue",
		position = UDim2.fromOffset(STAT_CHIP_PAD, 24),
		size = UDim2.new(1, -2 * STAT_CHIP_PAD, 0, 20),
		font = FIELD.label,
		textSize = STAT_VALUE_SIZE,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})
	-- Three cards across leave a five-stat track (the Aura) ~50px a chip, so both lines
	-- shrink to fit rather than run out of the chip; never larger than their design size.
	for _, pair in { { statLabel, STAT_LABEL_SIZE }, { statValue, STAT_VALUE_SIZE } } do
		pair[1].TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = pair[2]
		limit.Parent = pair[1]
	end

	-- The track, and the fill inside it. Two plain Frames rather than a UIKit helper:
	-- a 5px bar wants a corner and nothing else.
	local track = Instance.new("Frame")
	track.Name = "StatTrack"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, STAT_CHIP_PAD, 1, -9)
	track.Size = UDim2.new(1, -2 * STAT_CHIP_PAD, 0, STAT_BAR_HEIGHT)
	track.BackgroundColor3 = STUDDED.chip
	track.BackgroundTransparency = 0.45
	track.BorderSizePixel = 0
	track.Parent = chip

	local fill = Instance.new("Frame")
	fill.Name = "StatFill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = FIELD.amber
	fill.BorderSizePixel = 0
	fill.Parent = track

	-- The ghost: a pale slip over the start of the fill, as long as the same stat on
	-- the tier you have equipped. The gap between it and the fill's end is the upgrade.
	-- Hidden unless paintStats finds an equipped tier below this card.
	local ghost = Instance.new("Frame")
	ghost.Name = "StatGhost"
	ghost.Size = UDim2.fromScale(0, 1)
	ghost.BackgroundColor3 = Color3.new(1, 1, 1)
	ghost.BackgroundTransparency = 0.45
	ghost.BorderSizePixel = 0
	ghost.ZIndex = fill.ZIndex + 1
	ghost.Visible = false
	ghost.Parent = track

	for _, bar in { track, fill, ghost } do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = bar
	end

	-- Hover explains the stat (Gear.STAT_META `tip`, stamped on by paintStats). The
	-- slip lives on the card, two parents up: chip -> CardStats -> card.
	chip.Active = true
	chip.MouseEnter:Connect(function()
		showStatTip(parent.Parent :: Instance, chip)
	end)
	chip.MouseLeave:Connect(function()
		showStatTip(parent.Parent :: Instance, nil)
	end)
	-- Touch has no hover: a tap shows the same line, and goes away by itself since a
	-- finger never sends MouseLeave.
	chip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			showStatTip(parent.Parent :: Instance, chip)
			task.delay(3, function()
				local tip = (parent.Parent :: Instance):FindFirstChild("StatTip")
				if tip and tip:GetAttribute("Chip") == chip.Name then
					showStatTip(parent.Parent :: Instance, nil)
				end
			end)
		end
	end)

	return chip
end

--- One shop card: name and status, a big art well, a row of stat chips, and the price
--- button — drawn at hero size, because the carousel shows one of these at a time
--- rather than eight in a grid.
---
--- THE ART WELL SHOWS THE REAL MODEL. `CardArt` is the well — an ImageLabel with no
--- Image, kept for its fill, corner and edge — and `CardModel` is a ViewportFrame
--- inside it that renders the tier's own model, the one the rack hangs and the one
--- ToolService puts in your hands. See "The art well's model" below for why it is a
--- live render and not an uploaded picture. The Outfitter's Aura is worn rather than
--- held, so its well shows AuraLook's still atom model instead (see `artModel`).
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
		color = STUDDED.cardPlain,
		transparency = 0,
		strokeColor = STUDDED.cardEdge,
		strokeThickness = 4,
		cornerRadius = UDim.new(0, 12),
		visible = false,
	})
	card.LayoutOrder = order

	-- The glossy L-stud pattern over whatever colour the card is painted
	-- (paintShopCard), under everything else on it. The glow is kept faint so the
	-- gear's colour still reads at full strength.
	Studded.pattern(card, { radius = 12, zIndex = 0, bands = { 0.2, 0.47, 0.56, 0.64 }, bandTransparency = 0.55, glowTransparency = 0.72 })

	local scale = Instance.new("UIScale")
	scale.Name = "FocusScale"
	scale.Scale = NEIGHBOUR_SCALE
	scale.Parent = card

	-- ── The name row ─────────────────────────────────────────────────
	-- The tier's name on the left, its status word (ISSUED / OWNED / NEED $x) on the
	-- right. No catalogue code and no blurb any more, on request: the card is the
	-- picture, the numbers and the price. No rule under it either -- the well's own
	-- edge starts right below, and the rule was 16px the picture wanted.
	local strip = Instance.new("Frame")
	strip.Name = "CardStrip"
	strip.Position = UDim2.fromOffset(0, CARD_NAME_TOP)
	strip.Size = UDim2.new(1, 0, 0, CARD_NAME_HEIGHT)
	strip.BackgroundTransparency = 1
	strip.Parent = card

	-- Centred over the card, the reference's big white title; the flag (NEED $x) is a
	-- small line under it, only on a rung you cannot pay for yet.
	local cardName = UIKit.label(strip, {
		name = "CardName",
		position = UDim2.fromOffset(CARD_NAME_INSET, 0),
		size = UDim2.new(1, -2 * CARD_NAME_INSET, 0, 32),
		font = FIELD.headline,
		textSize = 26,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		shadow = false,
	})
	cardName.TextScaled = true
	local nameLimit = Instance.new("UITextSizeConstraint")
	nameLimit.MaxTextSize = 26
	nameLimit.Parent = cardName

	UIKit.label(strip, {
		name = "CardFlag",
		position = UDim2.fromOffset(CARD_NAME_INSET, 32),
		size = UDim2.new(1, -2 * CARD_NAME_INSET, 0, 18),
		font = FIELD.label,
		textSize = 15,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		shadow = false,
	})

	-- ── Art ──────────────────────────────────────────────────────────
	-- Full card width, from under the name row down to the stat chips, the same size on
	-- every card. The fill is a vertical fade (FIELD.wellFade), lit a third of the way
	-- down where the model sits, so the model reads as standing in light rather than
	-- pasted on a flat box. The fill is white because a UIGradient multiplies into it.
	local art = Instance.new("ImageLabel")
	art.Name = "CardArt"
	art.Position = UDim2.fromOffset(CARD_INSET, CARD_ART_TOP)
	art.Size = UDim2.fromOffset(CARD_ART_WIDTH, CARD_ART_HEIGHT)
	-- Clear: the item stands straight on the studded card, as in the reference.
	art.BackgroundTransparency = 1
	art.BorderSizePixel = 0
	art.Image = ""
	art.ScaleType = Enum.ScaleType.Fit
	art.Parent = card

	-- Clear over the well, so the well's own fill is the backdrop. The camera is made
	-- once here and only ever moved; paintArt swaps the model in front of it.
	local viewport = GearArt.viewport(art)
	viewport.Name = "CardModel"

	-- ── Stat chips ───────────────────────────────────────────────────
	-- One row between the well and the button. Placed by hand, not by a layout:
	-- paintStats divides the row's width between however many chips the track shows.
	local stats = Instance.new("Frame")
	stats.Name = "CardStats"
	stats.Position = UDim2.fromOffset(CARD_INSET, CARD_CHIPS_TOP)
	stats.Size = UDim2.fromOffset(CARD_ART_WIDTH, STAT_CHIP_HEIGHT)
	stats.BackgroundTransparency = 1
	stats.Parent = card

	for index = 1, STAT_ROWS do
		makeStatChip(stats, index)
	end
	makeStatTip(card)

	local buy = UIKit.button(card, {
		name = "CardBuy",
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, CARD_INSET, 1, -CARD_BUY_BOTTOM),
		size = UDim2.new(1, -2 * CARD_INSET, 0, CARD_BUY_HEIGHT),
		font = FIELD.headline,
		textSize = 22,
		cornerRadius = UDim.new(0, 8),
		strokeThickness = 1,
		outline = false,
		shadow = false,
	})
	buy.LayoutOrder = 9
	-- The fill is white under a vertical gradient that paintShopCard swaps per state
	-- (lime to buy or equip, dark grey when equipped, grey when you cannot pay yet).
	local buyFill = Instance.new("UIGradient")
	buyFill.Name = "Fill"
	buyFill.Rotation = 90
	buyFill.Color = STUDDED.lime
	buyFill.Parent = buy

	-- Hidden until paintShopCard finds a product for the tier.
	local robux = UIKit.button(card, {
		name = "CardRobux",
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -CARD_INSET, 1, -CARD_BUY_BOTTOM),
		size = UDim2.fromOffset(CARD_ROBUX_WIDTH, CARD_BUY_HEIGHT),
		text = ROBUX,
		font = FIELD.headline,
		textSize = 22,
		color = FIELD.text,
		fillColor = FIELD.robux,
		fillTransparency = 0,
		cornerRadius = UDim.new(0, 8),
		strokeThickness = 1,
		outline = false,
		shadow = false,
		visible = false,
	})
	robux.AutoButtonColor = false
	robux.BackgroundColor3 = Color3.new(1, 1, 1)
	local robuxFill = Instance.new("UIGradient")
	robuxFill.Rotation = 90
	robuxFill.Color = STUDDED.robux
	robuxFill.Parent = robux
	robux.MouseEnter:Connect(function()
		robux.BackgroundColor3 = Color3.fromHex("E6D6FF")
	end)
	robux.MouseLeave:Connect(function()
		robux.BackgroundColor3 = Color3.new(1, 1, 1)
	end)

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
	-- OVER the health/rads bars (RadHud, 100) and the aura warning (101), on request:
	-- the bars used to draw across the bottom of the card. Every station is in the
	-- zero-rad plaza, so nothing on them is changing while this is open. Still under
	-- the brew/bag panels (105+) and the Index/Shop/Gear/Nukes panels (110). The
	-- hotbar (60) is under it too; fitPanel() already lifts the panel clear of it.
	gui.DisplayOrder = 102
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
	--
	-- A PLAIN "X", NOT U+2715. No font this badge could wear has the multiplication
	-- cross glyph, so it drew as a missing-glyph box on every panel. Gotham Black's X
	-- is the Robux shop's close badge (ShopController), so the two read as one.
	local closeButton, closeInk = UIKit.button(canvas, {
		name = "Close",
		size = UDim2.fromOffset(40, 40), -- the reference's big red X (STUDDED)
		anchorPoint = Vector2.new(1, 0),
		font = FIELD.headline,
		textSize = 26,
		color = Color3.new(1, 1, 1),
		fillColor = STUDDED.closeRed,
		fillTransparency = 0,
		cornerRadius = UDim.new(0, 8),
		strokeThickness = 2,
		strokeColor = FIELD.ink,
		shadow = false,
		text = "X",
	})
	-- UIKit.button's stroke is Contextual, which on a TextButton outlines the GLYPH:
	-- the ink outline every other piece of field-kit text wears.
	closeInk.LineJoinMode = Enum.LineJoinMode.Round
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

	-- THE SHOP'S DARK STUDDED BACKDROP (2026-10-05, on request: "make the background a
	-- dark grey stud version" of the pattern). Another sibling for the same reason as the
	-- close badge -- the panel's UIListLayout would make it a row -- so it tracks the
	-- panel's box by hand under the panel, which goes see-through over it at the shop.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "ShopBackdrop"
	backdrop.BackgroundColor3 = STUDDED.backdrop
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = panel.ZIndex - 1
	backdrop.Visible = false
	backdrop.Parent = canvas
	local backdropCorner = Instance.new("UICorner")
	backdropCorner.CornerRadius = UIKit.Radius.panel
	backdropCorner.Parent = backdrop
	local backdropFit = Instance.new("UIScale")
	backdropFit.Parent = backdrop
	Studded.pattern(backdrop, {
		radius = UIKit.Radius.panel.Offset,
		bands = { 0.15, 0.42, 0.52, 0.58 },
		bandTransparency = 0.93,
		studTransparency = 0.1,
		glow = false,
	})
	ui.shopBackdrop = backdrop

	local function repositionClose()
		-- AbsolutePosition / AbsoluteSize are SCREEN pixels and the button's Offset is a
		-- design pixel on the same UIKit canvas, so measure from the canvas's own corner
		-- and divide by its scale — or the badge drifts off the corner as the HUD scales.
		local s = UIKit.canvasScale(canvas)
		local inset = 14 * fitScale.Scale
		local corner = (panel.AbsolutePosition - canvas.AbsolutePosition) / s
		closeButton.Position = UDim2.fromOffset(corner.X + panel.AbsoluteSize.X / s - inset, corner.Y + inset)
		closeFit.Scale = fitScale.Scale
		-- Unscaled size under the same UIScale, so its corners round like the panel's.
		local fit = math.max(fitScale.Scale, 0.01)
		backdrop.Position = UDim2.fromOffset(corner.X, corner.Y)
		backdrop.Size = UDim2.fromOffset(panel.AbsoluteSize.X / (s * fit), panel.AbsoluteSize.Y / (s * fit))
		backdropFit.Scale = fit
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
		-- Centred, then lifted PANEL_LIFT (as far as FIT_TOP allows), and further still if
		-- that leaves its bottom edge under the hotbar.
		local overlap = (screenHeight + height * fit) / 2 - (screenHeight - FIT_BOTTOM)
		local headroom = (screenHeight - height * fit) / 2 - FIT_TOP
		local want = if ui.trader ~= nil and ui.trader.frame.Visible
			then TRADER_LIFT
			elseif ui.shop ~= nil and ui.shop.Visible then SHOP_LIFT
			else PANEL_LIFT
		local lift = math.max(0, overlap, math.min(want, headroom))
		panel.Position = UDim2.new(0.5, 0, 0.5, -lift)
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel)
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPanel)
	fitPanel()
	ui.fitPanel = fitPanel

	-- The ceiling half of "viewport minus a margin, but never wider than". render()
	-- retunes MaxSize.X per mode; MinSize stops a phone-width viewport collapsing the
	-- panel to something narrower than one card.
	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = Vector2.new(CARD_WIDTH + 2 * PANEL_PAD, 0)
	panelSize.MaxSize = Vector2.new(TraderPanel.WIDTH, math.huge)
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
	shopLayout.Padding = UDim.new(0, 16)
	shopLayout.Parent = shop

	-- ── The shop's own header ────────────────────────────────────────
	-- The trader builds its own header too (TraderPanel), so neither mode repaints a
	-- widget the other one owns: an accent bar in the stall's own colour, the track
	-- name, and the wallet on the right. (The "N units on the rail" stock line under the
	-- name was cut on request.)
	--
	-- THE WALLET LIVES HERE NOW. It used to sit under the card row, which was right
	-- while the mockup had a left rail to anchor the panel's chrome; with the rail
	-- gone the header is the only chrome there is, and the number the whole grid of
	-- prices is compared against belongs in it.
	local header = Instance.new("Frame")
	header.Name = "ShopHeader"
	header.LayoutOrder = 0
	header.Size = UDim2.new(1, 0, 0, 64)
	-- The purple title bar: a vertical purple fade with the glossy L-stud pattern
	-- over it (Studded.pattern, below), inked round the edge (STUDDED).
	header.BackgroundColor3 = Color3.new(1, 1, 1)
	header.BackgroundTransparency = 0
	header.Parent = shop
	ui.shopHeader = header
	local headerFill = Instance.new("UIGradient")
	headerFill.Rotation = 90
	headerFill.Color = STUDDED.header
	headerFill.Parent = header
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 12)
	headerCorner.Parent = header
	local headerInk = Instance.new("UIStroke")
	headerInk.Color = FIELD.ink
	headerInk.Thickness = 3
	headerInk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	headerInk.Parent = header
	-- The glossy L-stud pattern in purple (2026-10-05), reshaped for a thin bar: smaller
	-- studs, and bands that land mid-bar, clear of the title and the wallet.
	Studded.pattern(header, { radius = 12, tile = 22, bands = { 0.28, 0.5, 0.58, 0.64 } })

	local headerRule = Instance.new("Frame")
	headerRule.Name = "HeaderRule"
	headerRule.AnchorPoint = Vector2.new(0, 1)
	headerRule.Position = UDim2.fromScale(0, 1)
	headerRule.Size = UDim2.new(1, 0, 0, 1)
	headerRule.BackgroundColor3 = FIELD.rule
	headerRule.BorderSizePixel = 0
	headerRule.Visible = false -- the purple bar is its own edge now
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
	accentBar.Visible = false -- the purple bar carries the title now
	accentBar.Parent = header
	ui.shopAccent = accentBar

	-- The track name as written: Detector, Magnet, Cleaner.
	ui.shopTitle = UIKit.label(header, {
		name = "ShopTitle",
		position = UDim2.fromOffset(20, 0),
		size = UDim2.new(1, -230, 1, -1),
		font = FIELD.headline,
		textSize = 36,
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
		position = UDim2.new(1, -WALLET_INSET, 0, 8),
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
		position = UDim2.new(1, -WALLET_INSET, 0, 24),
		size = UDim2.fromOffset(200, 30),
		font = FIELD.headline,
		textSize = 26,
		color = STUDDED.cash,
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
	row.Position = UDim2.new(0.5, -CARD_WIDTH / 2, 0, CARD_BAND / 2) -- over the scrollbar
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
			position = UDim2.new(if side < 0 then 0 else 1, -side * 6, 0, CARD_BAND / 2),
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

	-- ── The scrollbar ────────────────────────────────────────────────
	-- One full-width track along the bottom of the card window, with a thumb as wide as
	-- the share of the row on screen. It replaced the pager dots and "3 / 8" counter
	-- (2026-10-05, on request), whose own row went to taller cards. Press or drag
	-- anywhere on the track to page there (Station.start); the thumb follows a row drag
	-- too (paintScroll).
	local scroll = Instance.new("Frame")
	scroll.Name = "Scrollbar"
	scroll.AnchorPoint = Vector2.new(0.5, 1)
	scroll.Position = UDim2.fromScale(0.5, 1)
	scroll.Size = UDim2.new(1, -8, 0, SCROLL_HEIGHT)
	scroll.BackgroundColor3 = Color3.fromHex("1A1D22")
	scroll.BorderSizePixel = 0
	scroll.Visible = false
	scroll.ZIndex = 30
	scroll.Parent = carousel
	ui.shopScroll = scroll
	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = UDim.new(0.5, 0)
	scrollCorner.Parent = scroll

	local thumb = Instance.new("Frame")
	thumb.Name = "Thumb"
	thumb.Size = UDim2.fromScale(0.25, 1)
	thumb.BackgroundColor3 = Color3.fromHex("C9CED6")
	thumb.BorderSizePixel = 0
	thumb.ZIndex = 31
	thumb.Parent = scroll
	ui.shopThumb = thumb
	local thumbCorner = Instance.new("UICorner")
	thumbCorner.CornerRadius = UDim.new(0.5, 0)
	thumbCorner.Parent = thumb

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

	-- ── The gear intro ───────────────────────────────────────────────
	-- What this track is for (Gear.OVERVIEW) and what each of its stats does (the
	-- STAT_META tips), over the carousel. A solid scrim the size of the window hides
	-- the peeking cards; Active so a click on it does not reach the row underneath.
	local introScrim = Instance.new("Frame")
	introScrim.Name = "GearIntro"
	introScrim.Size = UDim2.fromScale(1, 1)
	introScrim.BackgroundColor3 = FIELD.panel
	introScrim.BorderSizePixel = 0
	introScrim.Active = true
	introScrim.ZIndex = 40
	introScrim.Visible = false
	introScrim.Parent = carousel

	local introCard = Instance.new("Frame")
	introCard.Name = "Card"
	introCard.AnchorPoint = Vector2.new(0.5, 0.5)
	introCard.Position = UDim2.fromScale(0.5, 0.5)
	introCard.Size = UDim2.fromOffset(CARD_WIDTH, 0)
	introCard.AutomaticSize = Enum.AutomaticSize.Y
	introCard.BackgroundColor3 = FIELD.card
	introCard.BorderSizePixel = 0
	introCard.Parent = introScrim
	local introCorner = Instance.new("UICorner")
	introCorner.CornerRadius = UDim.new(0, 14)
	introCorner.Parent = introCard
	local introEdge = Instance.new("UIStroke")
	introEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	introEdge.Color = FIELD.amber
	introEdge.Thickness = 2
	introEdge.Parent = introCard
	local introPad = Instance.new("UIPadding")
	introPad.PaddingTop = UDim.new(0, 28)
	introPad.PaddingBottom = UDim.new(0, 28)
	introPad.PaddingLeft = UDim.new(0, 30)
	introPad.PaddingRight = UDim.new(0, 30)
	introPad.Parent = introCard
	local introLayout = Instance.new("UIListLayout")
	introLayout.SortOrder = Enum.SortOrder.LayoutOrder
	introLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	introLayout.Padding = UDim.new(0, 14)
	introLayout.Parent = introCard

	local introKicker = UIKit.label(introCard, {
		name = "Kicker",
		size = UDim2.new(1, 0, 0, 22),
		font = FIELD.headline,
		textSize = 20,
		color = FIELD.amber,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		shadow = false,
	})
	introKicker.LayoutOrder = 1

	local introBody = UIKit.label(introCard, {
		name = "Body",
		size = UDim2.fromScale(1, 0),
		font = FIELD.label,
		textSize = 24,
		color = FIELD.text,
		xAlign = Enum.TextXAlignment.Left,
		yAlign = Enum.TextYAlignment.Top,
		wrapped = true,
		outline = false,
		shadow = false,
	})
	introBody.AutomaticSize = Enum.AutomaticSize.Y
	introBody.LayoutOrder = 2

	local introRule = Instance.new("Frame")
	introRule.Name = "Rule"
	introRule.Size = UDim2.new(1, 0, 0, 1)
	introRule.BackgroundColor3 = FIELD.rule
	introRule.BorderSizePixel = 0
	introRule.LayoutOrder = 3
	introRule.Parent = introCard

	-- One row per stat, the most any track sells (Aura's five); paintIntro hides the rest.
	local introRows = {}
	for index = 1, 5 do
		local statRow = Instance.new("Frame")
		statRow.Name = `Stat{index}`
		statRow.Size = UDim2.fromScale(1, 0)
		statRow.AutomaticSize = Enum.AutomaticSize.Y
		statRow.BackgroundTransparency = 1
		statRow.LayoutOrder = 3 + index
		statRow.Parent = introCard
		local statName = UIKit.label(statRow, {
			name = "StatName",
			size = UDim2.fromOffset(130, 24),
			font = FIELD.label,
			textSize = 20,
			color = FIELD.text,
			xAlign = Enum.TextXAlignment.Left,
			yAlign = Enum.TextYAlignment.Top,
			outline = false,
			shadow = false,
		})
		local statTip = UIKit.label(statRow, {
			name = "StatTip",
			position = UDim2.fromOffset(130, 1),
			size = UDim2.new(1, -130, 0, 0),
			font = FIELD.label,
			textSize = 19,
			color = FIELD.dim,
			xAlign = Enum.TextXAlignment.Left,
			yAlign = Enum.TextYAlignment.Top,
			wrapped = true,
			outline = false,
			shadow = false,
		})
		statTip.AutomaticSize = Enum.AutomaticSize.Y
		table.insert(introRows, { frame = statRow, name = statName, tip = statTip })
	end

	local introOk = UIKit.button(introCard, {
		name = "GotIt",
		size = UDim2.fromOffset(200, 50),
		text = "GOT IT",
		font = FIELD.headline,
		textSize = 22,
		color = FIELD.text,
		fillColor = FIELD.amber,
		fillTransparency = 0,
		cornerRadius = UDim.new(0, 10),
		strokeColor = FIELD.ink,
		strokeThickness = 2,
		outline = false,
		shadow = false,
	})
	introOk.LayoutOrder = 20

	ui.intro = {
		scrim = introScrim,
		edge = introEdge,
		kicker = introKicker,
		body = introBody,
		rows = introRows,
		ok = introOk,
	}

	-- The header's way back to it, beside the track name (placed off the title's
	-- TextBounds in render).
	ui.introButton = UIKit.button(header, {
		name = "AboutGear",
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.new(0, 200, 0.5, -1),
		size = UDim2.fromOffset(30, 30),
		text = "?",
		font = FIELD.headline,
		textSize = 20,
		color = FIELD.text,
		fillColor = FIELD.edge,
		fillTransparency = 0,
		cornerRadius = UDim.new(0.5, 0),
		strokeThickness = 0,
		outline = false,
		shadow = false,
		visible = false,
	})

	-- The row's SORT and SHOW pills, centred in the header between the title and the
	-- wallet. Each press steps its pref to the next option (prefs `shopSort`,
	-- `shopShow`); their text is painted by paintShopFilters.
	local filters = Instance.new("Frame")
	filters.Name = "ShopFilters"
	filters.AnchorPoint = Vector2.new(0.5, 0.5)
	filters.Position = UDim2.new(0.5, 0, 0.5, -1)
	filters.Size = UDim2.fromOffset(2 * FILTER_PILL_WIDTH + FILTER_PILL_GAP, FILTER_PILL_HEIGHT)
	filters.BackgroundTransparency = 1
	filters.Visible = false
	filters.Parent = header
	local filtersLayout = Instance.new("UIListLayout")
	filtersLayout.FillDirection = Enum.FillDirection.Horizontal
	filtersLayout.SortOrder = Enum.SortOrder.LayoutOrder
	filtersLayout.Padding = UDim.new(0, FILTER_PILL_GAP)
	filtersLayout.Parent = filters
	local function filterPill(name: string, order: number): TextButton
		local pill = UIKit.button(filters, {
			name = name,
			size = UDim2.fromOffset(FILTER_PILL_WIDTH, FILTER_PILL_HEIGHT),
			font = FIELD.headline,
			textSize = 16,
			color = FIELD.text,
			fillColor = FIELD.edge,
			fillTransparency = 0,
			cornerRadius = UDim.new(0.5, 0),
			strokeColor = FIELD.ink,
			strokeThickness = 2,
			outline = false,
			shadow = false,
		})
		pill.LayoutOrder = order
		return pill
	end
	ui.shopFilters = filters
	ui.shopSort = filterPill("Sort", 1)
	ui.shopShow = filterPill("Show", 2)

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

	-- The trader's whole body. It sizes itself; the panel's MaxSize is set to its width
	-- in render().
	ui.trader = TraderPanel.new(panel, 20)
	-- The locker's, the same way.
	ui.locker = LockerPanel.new(panel, 21)
	-- And the Merge Reactor's.
	ui.merge = MergePanel.new(panel, 22)
	-- And the Reforge Station's.
	ui.reforge = ReforgePanel.new(panel, 23)
	-- And the Slag Furnace's.
	ui.furnace = FurnacePanel.new(panel, 24)

	-- No drop shadow: UIKit draws it as a SIBLING label, and every child of `panel` is a
	-- row of its list layout, so the shadow used to turn up as a faint copy of the
	-- message at the top of the panel. Centred and inked instead, like the reference's
	-- "NEW SHOVEL EQUIPPED!" line (STUDDED).
	ui.toast = UIKit.label(panel, {
		name = "Toast",
		size = UDim2.new(1, 0, 0, 26),
		font = FIELD.label,
		textSize = 20,
		color = COLOR.green,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
	ui.toast.LayoutOrder = 70
	local toastInk = ui.toast:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	toastInk.Color = FIELD.ink
	toastInk.Thickness = 2
	toastInk.LineJoinMode = Enum.LineJoinMode.Round
	toastInk.Parent = ui.toast

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

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

--- Paint one card's stat chips. Chips are reused, so every chip past the track's own
--- column count is hidden rather than destroyed — see STAT_ROWS — and the ones shown
--- split the row's width evenly: three across for a Detector, four for the Aura.
---
--- A FLAG CELL KEEPS THE BAR'S GEOMETRY AND THROWS AWAY ITS MEANING: a capability is
--- not an amount, so the chip prints YES/NO and fills its track whole or not at all.
--- Currently exercised by no track — see makeStatChip.
---
--- `held` is the equipped tier's entry (nil when nothing on the track is equipped). On
--- a card above it, each bar gets a ghost as long as the held tier's own bar, so the
--- upgrade reads as the coloured stretch past it. Cards at or below it show no ghost:
--- a ghost longer than the fill would read as part of this tier's bar.
local function paintStats(card: Frame, entry, track: string, dear: boolean, held)
	local stats = card.CardStats :: Frame
	local meta = Gear.STAT_META[track] or {}
	local count = math.min(#entry.stats, STAT_ROWS)
	local heldByKey = {}
	if held and held.tier < entry.tier then
		for _, heldCell in held.stats do
			heldByKey[heldCell.key] = heldCell
		end
	end
	local width = if count > 0 then (CARD_ART_WIDTH - (count - 1) * STAT_CHIP_GAP) / count else 0
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
		row.Position = UDim2.fromOffset((index - 1) * (width + STAT_CHIP_GAP), 0)
		row.Size = UDim2.fromOffset(width, STAT_CHIP_HEIGHT)

		local label = row.StatLabel :: TextLabel
		local value = row.StatValue :: TextLabel
		local bar = row.StatTrack :: Frame
		local fill = bar.StatFill :: Frame
		-- Each stat in its own colour (Gear.STAT_META), label and bar alike; a rung you
		-- cannot pay for yet keeps the colour, washed toward grey.
		local field = meta[cell.key]
		local colour = if field and field.color then field.color else FIELD.amber
		if dear then
			colour = colour:Lerp(FIELD.muted, 0.55)
		end

		label.Text = cell.label
		label.TextColor3 = colour
		row:SetAttribute("Tip", if field then field.tip else nil)
		-- The undimmed colour: the tip explains the stat, not whether you can afford it.
		row:SetAttribute("TipColor", if field and field.color then field.color else FIELD.amber)
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
		fill.BackgroundColor3 = colour

		local ghost = bar.StatGhost :: Frame
		local heldCell = heldByKey[cell.key]
		ghost.Visible = heldCell ~= nil and cell.kind ~= "flag"
		if ghost.Visible then
			local was = math.max(math.clamp(heldCell.fraction, 0, 1), BAR_FLOOR)
			ghost.Size = UDim2.fromScale(math.min(was, shown), 1)
		end
		-- An unlit flag is the one cell that should read as absent rather than as low:
		-- dimming the value keeps "NO" from being mistaken for a small amount.
		value.TextColor3 = if cell.kind == "flag" and not cell.on then FIELD.muted else FIELD.text
	end
	-- A repaint under the mouse (the carousel stepping to another track) keeps the open
	-- tip on the same chip in step with what that chip now shows.
	local tip = card:FindFirstChild("StatTip")
	if tip and tip.Visible then
		local chipName = tip:GetAttribute("Chip")
		local chip = if typeof(chipName) == "string" then stats:FindFirstChild(chipName) :: Frame? else nil
		showStatTip(card, if chip and chip.Visible then chip else nil)
	end
end

--- Put `track`'s tier `tier` in the card's well. Cards are REUSED across stalls and
--- this runs on every StationState tick, so the model is only rebuilt when the card is
--- asked for a different tier or track than it already shows (`ArtKey`) — which is
--- once, the first time a stall is opened.
---
--- The aspect comes from the well's design size rather than from AbsoluteSize, which
--- reads 0 until the panel has been laid out once.
local function paintArt(card: Frame, track: string, tier: number)
	local key = `{track}/{tier}`
	if card:GetAttribute("ArtKey") == key then
		return
	end
	card:SetAttribute("ArtKey", key)

	GearArt.show(card.CardArt.CardModel :: ViewportFrame, track, tier, CARD_ART_WIDTH / CARD_ART_HEIGHT, true)
end

-- Robux prices, read off each product once (so a dashboard price change needs no code
-- change). `false` = asked and still waiting, or the lookup failed.
local robuxPrices: { [number]: number | false } = {}

--- The Robux glyph and price, or the bare glyph until the price arrives. The first ask
--- starts the lookup, and the answer repaints whichever card is showing that product.
local function robuxText(productId: number): string
	local price = robuxPrices[productId]
	if price then
		return `{ROBUX} {price}`
	end
	if price == nil then
		robuxPrices[productId] = false
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
			end)
			if not (ok and info and info.PriceInRobux) then
				return
			end
			robuxPrices[productId] = info.PriceInRobux
			for _, card in ui.shopCards or {} do
				if card:GetAttribute("ProductId") == productId then
					(card.CardRobux :: TextButton).Text = `{ROBUX} {info.PriceInRobux}`
				end
			end
		end)
	end
	return ROBUX
end

--- FAST MODE's still aura card: AuraController holds the atom on a chosen pose, and this
--- makes the card worth looking at without drawing a frame more. A soft glow in the
--- aura's colour behind the atom (a few stacked circles, static), the card's edge and
--- the name in that colour, and a locked rung dimmed less so its shape still reads. All
--- of it is painted once per refresh. Anything else (not FAST MODE, not the Aura track)
--- has the glow taken away again.
local GLOW_RINGS = {
	{ size = 0.95, transparency = 0.93 },
	{ size = 0.78, transparency = 0.88 },
	{ size = 0.6, transparency = 0.8 },
	{ size = 0.42, transparency = 0.7 },
}

local function paintStillAura(card: Frame, tier: number, locked: boolean, nameLabel: TextLabel, cardStroke: UIStroke, on: boolean)
	local art = card.CardArt :: ImageLabel
	local glow = art:FindFirstChild("StillGlow") :: Frame?
	if not on then
		if glow then
			glow:Destroy()
		end
		return
	end

	local color = AuraLook.get(tier).color
	if glow == nil then
		glow = Instance.new("Frame")
		glow.Name = "StillGlow"
		glow.BackgroundTransparency = 1
		glow.Size = UDim2.fromScale(1, 1)
		glow.ZIndex = 0
		glow.Parent = art
		for index, ring in GLOW_RINGS do
			local disc = Instance.new("Frame")
			disc.Name = `Disc{index}`
			disc.AnchorPoint = Vector2.new(0.5, 0.5)
			disc.Position = UDim2.fromScale(0.5, 0.5)
			-- Square on the art's HEIGHT, so each disc is a circle.
			disc.SizeConstraint = Enum.SizeConstraint.RelativeYY
			disc.Size = UDim2.fromScale(ring.size, ring.size)
			disc.BorderSizePixel = 0
			disc.ZIndex = 0
			disc.Parent = glow
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0.5, 0)
			round.Parent = disc
		end
	end
	local fade = if locked then 0.55 else 0
	for index, ring in GLOW_RINGS do
		local disc = (glow :: Frame):FindFirstChild(`Disc{index}`) :: Frame
		disc.BackgroundColor3 = color
		disc.BackgroundTransparency = 1 - (1 - ring.transparency) * (1 - fade)
	end

	cardStroke.Color = if locked then cardStroke.Color:Lerp(color, 0.4) else color
	nameLabel.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45)
end

--- Four states, and all four are drawn on the same card rather than on four layouts.
---
--- ISSUED    the one in your hands. Amber edge, a ghost button that says so: IN HAND,
---           or WEARING for the Aura, which is worn rather than held.
--- OWNED     bought and not held. The button is a live EQUIP — see ShopService's note
---           on why ownership being a set is what makes that a real verb.
--- (buyable) no flag at all. The price button already says it is for sale, and a word
---           saying the same thing on every unbought card was noise — this is where
---           "AVAILABLE" used to be.
--- NEED $x   buyable, unaffordable. The flag carries the SHORTFALL against your wallet
---           rather than the price, because the price is already on the button and the
---           gap is the thing you do not know.
local function paintShopCard(card: Frame, entry, track: string, cash: number, held)
	local nameLabel = card.CardStrip.CardName :: TextLabel
	local flag = card.CardStrip.CardFlag :: TextLabel
	local buy = card.CardBuy :: TextButton
	local cardStroke = card:FindFirstChildOfClass("UIStroke") :: UIStroke

	nameLabel.Text = entry.name
	paintArt(card, track, entry.tier)
	card:SetAttribute("Buyable", entry.buyable == true)
	card:SetAttribute("Equippable", entry.equippable == true)
	card:SetAttribute("Tier", entry.tier)

	local affordable = entry.affordable == true
	local dear = entry.buyable == true and not affordable

	paintStats(card, entry, track, dear, held)

	nameLabel.TextColor3 = FIELD.text

	-- THE CARD IS THE GEAR'S COLOUR (see STUDDED); the button carries the state, white
	-- under its state's gradient.
	local fill = buy:FindFirstChild("Fill") :: UIGradient
	card.BackgroundColor3 = GearArt.tint(track, entry.tier) or STUDDED.cardPlain
	cardStroke.Color = STUDDED.cardEdge
	buy.BackgroundColor3 = Color3.new(1, 1, 1)
	buy.BackgroundTransparency = 0
	flag.Text = ""
	if entry.current then
		buy.Text = if track == "Aura" then "WEARING" else "EQUIPPED"
		buy.TextColor3 = STUDDED.equippedText
		fill.Color = STUDDED.equipped
	elseif entry.owned then
		buy.Text = "EQUIP"
		buy.TextColor3 = FIELD.text
		fill.Color = STUDDED.lime
	elseif entry.lockedZone then
		-- Sold in another zone (ShopService lists the whole ladder). The button names
		-- where: a later zone unlocks it, an earlier one is just where it is sold.
		local zone = entry.lockedZone :: number
		local here = (Camps.get((state.offer and state.offer.camp) or "base") or { id = 1 }).id
		card.BackgroundColor3 = STUDDED.cardLocked
		flag.Text = "LOCKED"
		flag.TextColor3 = STUDDED.equippedText
		buy.Text = if zone > here then `UNLOCKED IN ZONE {zone}` else `SOLD IN ZONE {zone}`
		buy.TextColor3 = STUDDED.equippedText
		fill.Color = STUDDED.locked
	elseif dear then
		flag.Text = `NEED {money(entry.price - cash)}`
		flag.TextColor3 = FIELD.short
		buy.Text = money(entry.price)
		buy.TextColor3 = FIELD.text
		fill.Color = STUDDED.dear
	else
		buy.Text = money(entry.price)
		buy.TextColor3 = FIELD.text
		fill.Color = STUDDED.lime
	end
	-- A locked rung's item is shown dimmed, a hint of what is waiting further on.
	(card.CardArt.CardModel :: ViewportFrame).ImageColor3 = if entry.lockedZone then Color3.fromRGB(80, 84, 96) else Color3.new(1, 1, 1)

	if track == "Aura" then
		local still = Prefs.get("fastMode") == true
		if still and entry.lockedZone then
			(card.CardArt.CardModel :: ViewportFrame).ImageColor3 = Color3.fromRGB(150, 154, 166)
		end
		paintStillAura(card, entry.tier, entry.lockedZone ~= nil, nameLabel, cardStroke, still)
	end

	-- current, owned and buyable are exhaustive over every tier: `current` is checked
	-- first and `owned` second, so the equipped tier takes the ISSUED branch even
	-- though it is also owned, and `buyable` is by construction `not owned` — the
	-- trailing two branches split that last case on affordability alone.

	-- THE ROBUX HALF. Only on a tier you can still buy that has a product; then the
	-- cash button gives up the right side of the row to it.
	local robux = card.CardRobux :: TextButton
	local productId = if entry.buyable then GearProducts.idFor(track, entry.tier) else nil
	robux.Visible = productId ~= nil
	card:SetAttribute("ProductId", productId)
	if productId then
		buy.Size = UDim2.new(1, -(2 * CARD_INSET + CARD_ROBUX_WIDTH + CARD_ROBUX_GAP), 0, CARD_BUY_HEIGHT)
		robux.Text = robuxText(productId)
	else
		buy.Size = UDim2.new(1, -2 * CARD_INSET, 0, CARD_BUY_HEIGHT)
	end
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
--- Where tier number `tier` sits in an offer's list, or nil when this stall does not list
--- it. THE POSITION IS NOT THE TIER: a stall lists what it sells plus what you own, so
--- Toxic Twilight's Detector stall opens on tier 10 as its first card, and this is the one
--- place that turns a tier (a rack hook's `SellsTier`, a rack card) into a card.
local function tierIndex(tiers: { any }, tier: number): number?
	for index, entry in tiers do
		if entry.tier == tier then
			return index
		end
	end
	return nil
end

--- The offer's ladder in the player's chosen order (the header's SORT pill, pref
--- `shopSort`): a sorted COPY, so the server's worst-first list that the rack reads is
--- left alone. Equal prices fall back on the tier, so the order never shuffles a tick.
local function sortedTiers(tiers: { any }): { any }
	local cheapFirst = Prefs.get("shopSort") == "low"
	local out = table.clone(tiers)
	table.sort(out, function(a, b)
		local pa, pb = a.price or 0, b.price or 0
		if pa ~= pb then
			return if cheapFirst then pa < pb else pa > pb
		end
		return if cheapFirst then a.tier < b.tier else a.tier > b.tier
	end)
	return out
end

local SORT_TEXT = { high = "PRICE: HIGH-LOW", low = "PRICE: LOW-HIGH" }
local SHOW_TEXT = { all = "SHOW: ALL", unowned = "SHOW: NOT OWNED", affordable = "SHOW: CAN AFFORD" }

--- The header pills' text, off the current prefs. Hidden on a rack card.
local function paintShopFilters(visible: boolean)
	ui.shopFilters.Visible = visible
	ui.shopSort.Text = SORT_TEXT[Prefs.get("shopSort")] or SORT_TEXT.high
	ui.shopShow.Text = SHOW_TEXT[Prefs.get("shopShow")] or SHOW_TEXT.all
end

--- `tiers` narrowed by the header's SHOW pill (pref `shopShow`).
local function filteredTiers(tiers: { any }): { any }
	local show = Prefs.get("shopShow")
	if show ~= "unowned" and show ~= "affordable" then
		return tiers
	end
	local out = {}
	for _, entry in tiers do
		local keep = if show == "unowned"
			then not entry.owned
			else entry.buyable == true and entry.affordable == true
		if keep then
			table.insert(out, entry)
		end
	end
	return out
end

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

		local index = if tiers ~= nil and part:GetAttribute("SellsTrack") == track then tierIndex(tiers, tier) else nil
		local entry = if index then (tiers :: { any })[index] else nil
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
local thumbTween: Tween? = nil

-- Cards on screen at once: three across, or the whole row when it is shorter.
local SCROLL_VISIBLE = 3

--- The scrollbar thumb: as wide as the share of the row on screen, sitting over the
--- cards that are showing, and following a row drag while it is held.
local function paintScroll(animate: boolean)
	local count = carousel.count
	if thumbTween then
		thumbTween:Cancel()
		thumbTween = nil
	end
	if count <= SCROLL_VISIBLE then
		return
	end
	local width = SCROLL_VISIBLE / count
	local first = carousel.focus - 1 - carousel.drag / CAROUSEL_STEP -- 1 short of the leftmost card
	local left = math.clamp((first - 1) / count, 0, 1 - width)
	local position = UDim2.fromScale(left, 0)
	ui.shopThumb.Size = UDim2.fromScale(width, 1)
	if animate then
		thumbTween = TweenService:Create(ui.shopThumb, CAROUSEL_TWEEN, { Position = position })
		thumbTween:Play()
	else
		ui.shopThumb.Position = position
	end
end

local function placeRow(animate: boolean)
	if rowTween then
		rowTween:Cancel()
		rowTween = nil
	end
	local target = UDim2.new(0.5, -CARD_WIDTH / 2 - (carousel.focus - 1) * CAROUSEL_STEP + carousel.drag, 0, CARD_BAND / 2)
	if animate then
		rowTween = TweenService:Create(ui.shopRow, CAROUSEL_TWEEN, { Position = target })
		rowTween:Play()
	else
		ui.shopRow.Position = target
	end
	paintScroll(animate)
end

--- The arrows, and whether the scrollbar shows at all. Plain property writes with no
--- tweens, so render() can call this on every tick.
local function paintPager()
	ui.shopScroll.Visible = carousel.count > SCROLL_VISIBLE and not carousel.single
	local edge = if carousel.count >= 3 then 1 else 0 -- three across (setShopFocus)
	ui.shopPrev.Visible = carousel.focus > 1 + edge
	ui.shopNext.Visible = carousel.focus < carousel.count - edge
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
			veil.Visible = false -- three across: every card is live (see CARD_PEEK)
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
			veil.Visible = false
		end
	end
end

--- The card the walkthrough pins the row on, or nil when it is not pinning: the
--- Detector shop, on the "upgrade" step, with the Bent Coil listed and not yet owned.
local function tutorialPinnedIndex(): number?
	local tiers = carousel.tiers
	if
		tiers == nil
		or state.station ~= "shop"
		or state.stationId ~= "Detector"
		or dismissed
		or not Tutorial.isActive(Players.LocalPlayer)
		or Players.LocalPlayer:GetAttribute("TutorialStep") ~= "upgrade"
		-- A rack hook's one card: only the Bent Coil's own is pinned, or the row would
		-- page to a card that is not drawn.
		or carousel.single and (rackCard == nil or (rackCard :: any).tier ~= Tutorial.UPGRADE_TIER)
	then
		return nil
	end
	local index = tierIndex(tiers, Tutorial.UPGRADE_TIER)
	if index == nil or tiers[index].owned then
		return nil
	end
	return index
end

local function setShopFocus(index: number, animate: boolean)
	-- Every way of paging ends here, so pinning the row is this one line.
	index = tutorialPinnedIndex() or index
	-- Three cards across: the middle one never sits on the first or last rung, so the
	-- row is always three full cards (one or two when the stall sells fewer).
	local count = carousel.count
	local three = count >= 3 and not carousel.single -- a rack card shows just its own tier
	local low = if three then 2 else 1
	local high = if three then count - 1 else math.max(count, 1)
	carousel.focus = math.clamp(index, low, high)
	carousel.drag = 0
	placeRow(animate)
	paintFocus(animate)
	paintPager()
end

--- Where the row opens: the next tier up from the one in your hands that you do not
--- own yet — the upgrade you most likely walked over for. Owning everything above it,
--- the one in your hands. Picked by TIER, not position, so it holds whichever way the
--- SORT pill orders the row (and whatever SHOW leaves in it).
local function defaultShopFocus(tiers: { any }): number
	local currentTier = 0
	local currentIndex: number? = nil
	for index, entry in tiers do
		if entry.current then
			currentTier = entry.tier
			currentIndex = index
		end
	end
	local best: number?, bestTier = nil, math.huge
	for index, entry in tiers do
		if not entry.owned and entry.tier > currentTier and entry.tier < bestTier then
			best, bestTier = index, entry.tier
		end
	end
	return best or currentIndex or 1
end

--- Start the locker tutorial the first time its panel is on screen, and drop it the
--- moment the panel is not (walked off, closed). Deferred a frame on start, so the
--- panel has laid out before the spotlight measures it.
local function syncTutorial()
	local lockerOpen = state.station == "locker" and not dismissed
	if not lockerOpen then
		if tutorial then
			tutorial.stop()
		end
		return
	end
	if tutorial or tutorialDone or state.lockerTutorial ~= true then
		return
	end
	local parts = ui.locker.parts
	tutorial = LockerTutorial.run({
		{
			target = parts.header,
			title = "QUARANTINE LOCKER",
			body = "Store clean or uncleaned nukes here",
		},
	}, function(finished)
		tutorial = nil
		if finished then
			tutorialDone = true
			actionRemote:FireServer({ action = "tutorialSeen", id = "locker" })
		end
	end)
end

--- Ring the pinned card's buy button, or let go. Deferred like syncTutorial, so the
--- card has laid out before the spotlight measures it.
local function syncBuySpotlight()
	local index = tutorialPinnedIndex()
	local card = if index then ui.shopCards[index] else nil
	if card and not card.Visible then
		card = nil
	end
	if buySpotlight and buySpotlightCard == card then
		return
	end
	if buySpotlight then
		buySpotlight.stop()
		buySpotlight = nil
		buySpotlightCard = nil
	end
	if card == nil then
		return
	end
	buySpotlightCard = card
	buySpotlight = LockerTutorial.run({
		{
			target = card.CardBuy :: GuiObject,
			title = "BUY THE BENT COIL",
			body = `Purchase the detector for {money(Gear.Detector[Tutorial.UPGRADE_TIER].price)}`,
			press = true,
		},
	}, function() end)
end

--- Fill the intro card for `track`: its Gear.OVERVIEW line, then each stat it sells in
--- the stat's own colour beside that stat's STAT_META tip, in the card's order.
local function paintIntro(track: string, accent: Color3)
	local overview = Gear.OVERVIEW[track]
	local meta = Gear.STAT_META[track]
	local intro = ui.intro
	local name = string.upper(overview.name)
	intro.kicker.Text = `WHAT {if string.match(name, "^[AEIOU]") then "AN" else "A"} {name} DOES`
	intro.kicker.TextColor3 = accent
	intro.edge.Color = accent
	intro.ok.BackgroundColor3 = accent
	intro.body.Text = overview.body
	for index, parts in intro.rows do
		local key = if meta then meta.order[index] else nil
		local stat = if key then meta[key] else nil
		parts.frame.Visible = stat ~= nil
		if stat then
			parts.name.Text = string.upper(stat.label)
			parts.name.TextColor3 = stat.color
			parts.tip.Text = stat.tip or ""
		end
	end
end

local function render()
	task.defer(syncTutorial)
	task.defer(syncBuySpotlight)
	if state.station ~= "shop" or dismissed then
		introTrack = nil
	end
	if state.station == nil or dismissed or not PANEL_KINDS[state.station] then
		ui.panel.Visible = false
		ui.shopBackdrop.Visible = false
		ui.closeButton.Visible = false
		for _, tip in statTips do
			tip.Visible = false
		end
		carousel.openedFor = nil
		carousel.singleFor = nil
		return
	end

	ui.panel.Visible = true
	ui.closeButton.Visible = true

	-- One body of three: the shop's storefront, the locker's tube rack, or the trader's
	-- buyback counter. Each builds its own header, so there is nothing shared to repaint
	-- between them.
	local atShop = state.station == "shop"
	local atLocker = state.station == "locker"
	local atMerge = state.station == "merge"
	local atReforge = state.station == "reforge"
	local atFurnace = state.station == "furnace"
	ui.shop.Visible = atShop
	ui.locker.frame.Visible = atLocker
	ui.merge.frame.Visible = atMerge
	ui.reforge.frame.Visible = atReforge
	ui.furnace.frame.Visible = atFurnace
	ui.trader.frame.Visible = not atShop and not atLocker and not atMerge and not atReforge and not atFurnace
	ui.fitPanel() -- the trader and the stalls each sit higher than the rest (TRADER_LIFT, SHOP_LIFT)

	-- One rack card, if a rack hook's E opened this and it is for the shop you are at.
	local offerTiers = if atShop and state.offer and state.offer.tiers then sortedTiers(state.offer.tiers) else nil
	-- The rack card's position in THIS stall's list (see tierIndex), nil when it is not
	-- listed here, which is what makes it not a rack card at all.
	local rackIndex: number? = if atShop
			and rackCard ~= nil
			and rackCard.track == state.stationId
			and offerTiers ~= nil
		then tierIndex(offerTiers, (rackCard :: any).tier)
		else nil
	local single = rackIndex ~= nil
	carousel.single = single

	local shopWidth = if single then RACK_PANEL_WIDTH else SHOP_PANEL_WIDTH
	ui.panelSize.MaxSize = Vector2.new(
		if atShop then shopWidth
			elseif atLocker then LockerPanel.WIDTH
			elseif atMerge then MergePanel.WIDTH
			elseif atReforge then ReforgePanel.WIDTH
			elseif atFurnace then FurnacePanel.WIDTH
			else TraderPanel.WIDTH,
		math.huge
	)

	-- BOTH MODES WEAR THE FIELD-KIT SLATE now; the trader used to keep the near-black
	-- list panel it always had, until it was rebuilt as a counter in the shop's skin.
	-- Still set on every render, because the stroke is repainted per stall below.
	ui.panel.BackgroundColor3 = FIELD.panel
	ui.panel.BackgroundTransparency = 0 -- solid: it sits over the depth readout and vitals bars now
	-- The dark studded backdrop sits under the shop, the trader and the reactor alike.
	local atTrader = not (atShop or atLocker or atMerge or atReforge or atFurnace)
	ui.shopBackdrop.Visible = atShop or atTrader or atMerge or atReforge or atFurnace

	if atShop then
		-- The row in the SORT pill's order, narrowed by SHOW. A rack card keeps the whole
		-- (sorted) list: SHOW never hides the one card a rack hook opened.
		local tiers = if offerTiers == nil then nil elseif single then offerTiers else filteredTiers(offerTiers)
		local track = state.stationId or "Shop"
		local accent = STALL_ACCENT[track] or FIELD.amber
		local cash = state.cash or 0

		ui.panel.BackgroundColor3 = STUDDED.panel
		ui.panel.BackgroundTransparency = 1 -- the dark studded backdrop shows through
		ui.panelStroke.Color = STUDDED.cardEdge
		ui.shopAccent.BackgroundColor3 = accent
		ui.shopTitle.Text = track

		local count = if tiers then #tiers else 0

		-- The gear intro: only the "?" opens it (no first-visit popup).
		local overview = Gear.OVERVIEW[track]
		if introTrack ~= nil and introTrack ~= track then
			introTrack = nil
		end
		local listed = if offerTiers then #offerTiers else 0
		ui.introButton.Visible = overview ~= nil and listed > 0
		paintShopFilters(listed > 0 and not single)
		-- Measured in design px: TextBounds is screen px, under the canvas and fit scales.
		local titleWidth = TextService:GetTextSize(track, ui.shopTitle.TextSize, ui.shopTitle.Font, Vector2.new(1000, 100)).X
		ui.introButton.Position = UDim2.new(0, 20 + titleWidth + 14, 0.5, -1)
		ui.intro.scrim.Visible = introTrack == track
		if introTrack == track then
			paintIntro(track, accent)
		end

		ui.shopCarousel.Visible = count > 0
		-- A rack card has nothing to scroll, so its window drops the scrollbar's strip.
		ui.shopCarousel.Size = UDim2.new(1, 0, 0, if single then CARD_BAND else CAROUSEL_HEIGHT)
		ui.shopEmpty.Visible = count == 0
		ui.shopEmpty.Text = if listed > 0 then "nothing matches this filter" else "nothing for sale here"

		-- The equipped tier, for the ghost bars on every card above it.
		local held = nil
		for _, entry in tiers or {} do
			if entry.current then
				held = entry
			end
		end

		for index, card in ui.shopCards do
			local entry = if tiers then tiers[index] else nil
			-- A rack card shows its own tier and nothing either side of it.
			card.Visible = entry ~= nil and (not single or index == rackIndex)
			if entry then
				paintShopCard(card, entry, track, cash, held)
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
			local slot = rackIndex :: number
			local key = `{track}/{tier}`
			if carousel.focus ~= slot or carousel.singleFor ~= key then
				setShopFocus(slot, false)
			end
			if carousel.singleFor ~= key then
				carousel.singleFor = key
				local pop = ui.shopCards[slot]:FindFirstChildOfClass("UIScale") :: UIScale
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
		return
	end

	carousel.openedFor = nil

	if atLocker then
		ui.panelStroke.Color = FIELD.edge
		ui.locker.paint(state)
		return
	end

	if atMerge then
		ui.panel.BackgroundTransparency = 1 -- the dark studded backdrop shows through
		ui.panelStroke.Color = STUDDED.cardEdge
		ui.merge.paint(state)
		return
	end

	if atReforge then
		ui.panel.BackgroundTransparency = 1 -- the dark studded backdrop shows through
		ui.panelStroke.Color = STUDDED.cardEdge
		ui.reforge.paint(state)
		return
	end

	if atFurnace then
		ui.panel.BackgroundTransparency = 1 -- the dark studded backdrop shows through
		ui.panelStroke.Color = STUDDED.cardEdge
		ui.furnace.paint(state)
		return
	end

	-- TRADER ONLY down here now. This used to be the decon/trader fork; the decon half
	-- moved into the world (the tub's E prompt) and took the Quarantine Locker rows and
	-- the RACK button with it -- see this file's header. The body is TraderPanel's.
	ui.panel.BackgroundTransparency = 1 -- the dark studded backdrop shows through
	ui.panelStroke.Color = STUDDED.cardEdge
	ui.trader.paint(state)
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
	ui.toast.Text = string.upper(message)
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
	-- FAST MODE changes how the aura cards look: repaint an open panel straight away.
	Prefs.observe("fastMode", function()
		if ui.panel and ui.panel.Visible then
			render()
		end
	end)
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	actionRemote = Net.get("StationAction")

	-- The trader's one verb, the receipt's SELL. The server re-derives the price, the ownership and the
	-- station itself (DeconService / EconomyService), so these only ever ask.
	ui.trader.onSellMany(function(uids)
		actionRemote:FireServer({ action = "sellMany", uids = uids })
	end)
	-- The locker's three, the same way: DeconService re-derives that you are at your own
	-- rack and that there is room on the other side.
	ui.locker.onStore(function(uid)
		actionRemote:FireServer({ action = "store", uid = uid })
	end)
	ui.locker.onTake(function(uid)
		actionRemote:FireServer({ action = "take", uid = uid })
	end)
	ui.locker.onUpgrade(function()
		actionRemote:FireServer({ action = "upgradeLocker" })
	end)
	-- The reactor's one verb. MergeService re-derives the station, the copies, the fee
	-- and the roll; MergeResult brings the outcome back for the panel's reveal.
	ui.merge.onMerge(function(uids)
		actionRemote:FireServer({ action = "merge", uids = uids })
	end)
	Net.get("MergeResult").OnClientEvent:Connect(function(result)
		ui.merge.showResult(result)
	end)
	-- The forge's two verbs. ReforgeService re-derives the station, the copy, the price
	-- and the roll; ReforgeResult brings the old and new pair back for KEEP / REVERT.
	ui.reforge.onReforge(function(uid)
		actionRemote:FireServer({ action = "reforge", uid = uid })
	end)
	ui.reforge.onSettle(function(uid, keep)
		actionRemote:FireServer({ action = "reforgeKeep", uid = uid, keep = keep })
	end)
	Net.get("ReforgeResult").OnClientEvent:Connect(function(result)
		ui.reforge.showResult(result)
	end)
	-- The furnace's two verbs. FurnaceService re-derives the station, the copies, the
	-- fill and the prize; FurnaceResult brings the meter back, and a roll's reel.
	ui.furnace.onDump(function(uids)
		actionRemote:FireServer({ action = "furnaceDump", uids = uids })
	end)
	ui.furnace.onRoll(function()
		actionRemote:FireServer({ action = "furnaceRoll" })
	end)
	Net.get("FurnaceResult").OnClientEvent:Connect(function(result)
		ui.furnace.showResult(result)
	end)

	-- ── Moving along the carousel ────────────────────────────────────
	-- All of it goes through setShopFocus. The wheel and the drag are read off
	-- UserInputService with `gameProcessed` ignored — over a GUI it is always true —
	-- and hit-tested against the carousel's own rect instead. InputObject.Position is
	-- below the topbar inset, the same space as this gui's AbsolutePosition
	-- (IgnoreGuiInset is false, see build()).
	-- A rack card is one card with nothing to page to, so it takes none of this input.
	local function shopShowing(): boolean
		return ui.panel.Visible
			and ui.shop.Visible
			and carousel.count > 0
			and not carousel.single
			and not ui.intro.scrim.Visible
	end

	-- The gear intro's two buttons: GOT IT puts it away, the header's "?" brings it back.
	ui.intro.ok.MouseButton1Click:Connect(function()
		introTrack = nil
		render()
	end)
	-- The SORT / SHOW pills: each press steps its pref to the next option. The prefs'
	-- observers (below) repaint the row and re-pick its opening card.
	local function stepPref(key: string, options: { string })
		local at = table.find(options, Prefs.get(key)) or 0
		Prefs.set(key, options[at % #options + 1])
	end
	ui.shopSort.MouseButton1Click:Connect(function()
		stepPref("shopSort", { "high", "low" })
	end)
	ui.shopShow.MouseButton1Click:Connect(function()
		stepPref("shopShow", { "all", "unowned", "affordable" })
	end)
	for _, key in { "shopSort", "shopShow" } do
		Prefs.observe(key, function()
			if ui.panel.Visible and state.station == "shop" then
				carousel.openedFor = nil -- the row moved under you: open on the next upgrade again
				render()
			end
		end)
	end
	ui.introButton.MouseButton1Click:Connect(function()
		introTrack = if introTrack == nil then state.stationId else nil
		render()
	end)
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
	-- The scrollbar: a press on the track glides the thumb to the pointer, and a drag
	-- slides the row with it smoothly, not a card at a time (2026-10-05, on request); it
	-- snaps to the nearest card on release. Grabbing the thumb itself keeps the point
	-- you grabbed under the pointer. It sits inside the carousel's rect, so it is tested
	-- first and a press on it never starts a row drag.
	local scrollInput: InputObject? = nil
	-- Track fraction between the pointer and the thumb's centre, held for the drag.
	local scrollGrab = 0
	-- Where the row was last slid to, as a fractional focus index.
	local scrollFocus = 1
	local function overScroll(position: Vector3): boolean
		local bar = ui.shopScroll
		if not bar.Visible then
			return false
		end
		local corner = bar.AbsolutePosition
		local size = bar.AbsoluteSize
		local slop = 6 -- a 12px bar is a small target for a thumb
		return position.X >= corner.X
			and position.X <= corner.X + size.X
			and position.Y >= corner.Y - slop
			and position.Y <= corner.Y + size.Y + slop
	end
	local function trackFraction(position: Vector3): number
		local bar = ui.shopScroll
		return (position.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1)
	end
	--- Slides the row so the thumb's centre sits at `along` (a track fraction), with
	--- no snapping: carousel.focus stays put and the row rides on carousel.drag.
	local function scrollTo(along: number, animate: boolean)
		local count = carousel.count
		local width = SCROLL_VISIBLE / count
		local left = math.clamp(along - width / 2, 0, 1 - width)
		-- The thumb's left edge sits one card short of the focus (see paintScroll).
		scrollFocus = left * count + 2
		carousel.drag = -(scrollFocus - carousel.focus) * CAROUSEL_STEP
		placeRow(animate)
	end
	local function scrollPress(position: Vector3)
		local along = trackFraction(position)
		local thumb = ui.shopThumb
		local onThumb = position.X >= thumb.AbsolutePosition.X
			and position.X <= thumb.AbsolutePosition.X + thumb.AbsoluteSize.X
		local centre = thumb.Position.X.Scale + thumb.Size.X.Scale / 2
		scrollGrab = if onThumb then along - centre else 0
		scrollTo(along - scrollGrab, not onThumb)
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
		local press = kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
		if press and overScroll(input.Position) then
			scrollInput = input
			scrollPress(input.Position)
		elseif press and overCarousel(input.Position) then
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
		if scrollInput ~= nil then
			local byMouse = scrollInput.UserInputType == Enum.UserInputType.MouseButton1
			if (byMouse and kind == Enum.UserInputType.MouseMovement) or (not byMouse and input == scrollInput) then
				if shopShowing() then
					scrollTo(trackFraction(input.Position) - scrollGrab, false)
				end
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
		if
			scrollInput ~= nil
			and (
				input == scrollInput
				or (
					scrollInput.UserInputType == Enum.UserInputType.MouseButton1
					and input.UserInputType == Enum.UserInputType.MouseButton1
				)
			)
		then
			scrollInput = nil
			-- Settle on the nearest card from wherever the slide left the row.
			if shopShowing() then
				setShopFocus(math.floor(scrollFocus + 0.5), true)
			end
			return
		end
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
				if state.stationId ~= "Aura" then
					Sfx.play("gearEquip")
				end
			end
		end)

		-- The purple half. Roblox's own purchase dialog takes it from here, and the
		-- grant arrives through ProductService on the server.
		local robux = card.CardRobux :: TextButton
		robux.MouseButton1Click:Connect(function()
			if state.stationId == nil or (dragMoved and not carousel.single) then
				return
			end
			local productId = card:GetAttribute("ProductId")
			if type(productId) == "number" then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
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
		if prompt.Name == MERGE_PROMPT then
			if state.station == "merge" then
				dismissed = not dismissed
				render()
			else
				mergePressedAt = os.clock()
			end
		elseif prompt.Name == REFORGE_PROMPT then
			if state.station == "reforge" then
				dismissed = not dismissed
				render()
			else
				reforgePressedAt = os.clock()
			end
		elseif prompt.Name == FURNACE_PROMPT then
			if state.station == "furnace" then
				dismissed = not dismissed
				render()
			else
				furnacePressedAt = os.clock()
			end
		elseif prompt.Name == LOCKER_PROMPT then
			-- Toggles like the stand's E. Somebody else's rack reaches here too; the
			-- server never reports it as a station (DeconService.ownsLocker), so the
			-- panel stays shut and ExhibitService tells them why.
			if state.station == "locker" then
				dismissed = not dismissed
				render()
			else
				lockerPressedAt = os.clock()
			end
		elseif prompt.Name == BROWSE_PROMPT then
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
			--
			-- THE LOCKER ARRIVES DISMISSED too, and opens on its E -- unless that E came
			-- a moment before this tick did (LOCKER_PRESS_GRACE).
			if rackCard ~= nil and payload.station == "shop" and payload.stationId == rackCard.track then
				dismissed = false
			elseif payload.station == "locker" then
				rackCard = nil
				dismissed = os.clock() - lockerPressedAt > LOCKER_PRESS_GRACE
				lockerPressedAt = -math.huge
			elseif payload.station == "merge" then
				-- The reactor arrives dismissed too, and opens on its E.
				rackCard = nil
				dismissed = os.clock() - mergePressedAt > LOCKER_PRESS_GRACE
				mergePressedAt = -math.huge
			elseif payload.station == "reforge" then
				-- The forge too.
				rackCard = nil
				dismissed = os.clock() - reforgePressedAt > LOCKER_PRESS_GRACE
				reforgePressedAt = -math.huge
			elseif payload.station == "furnace" then
				-- And the furnace.
				rackCard = nil
				dismissed = os.clock() - furnacePressedAt > LOCKER_PRESS_GRACE
				furnacePressedAt = -math.huge
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
