--[[
	UIKit.luau — the palette, the type scale, and the dock every HUD piece stands on.

	WHY THIS EXISTS.
	Four controllers (Hud, Detector, Inventory, Station) each hand-roll their own GUI
	with raw Instance.new calls, and each independently redefines a nearly-identical
	COLOR table — same seven-odd hex values, copy-pasted four times. That is exactly
	the drift problem server/build/Kit.luau was built to prevent on the world-geometry
	side, just never fixed here. This is that fix, sized to what four files actually
	need: a palette, a type scale, corner/stroke constants, three thin builder
	helpers, and the dock layout. Not a component framework — nothing here owns an
	instance after handing it back to the caller, and no file's own `ui` table shape
	changes because of this module.

	THE DOCK REPLACES A REAL BUG, NOT JUST A REAL EYESORE.
	InventoryController's detail card used to sit at a literal `-178`, with a comment
	explaining that number was hand-tuned against DetectorController's own private
	`-152`/`-96` offsets so the two would not overlap — "if DetectorController's stack
	moves, this number moves with it." Nothing enforced that; it was two files' worth
	of magic numbers standing in an unspoken agreement. `UIKit.Dock` is that agreement
	made structural: every position downstream is a formula over these numbers, so no
	controller has to know another controller's private layout again.

	require(script.Parent.Parent.UIKit) from any file under Controllers/ — this module
	lives one level up, deliberately outside script.Controllers, so init.client.luau's
	orphan-module warning ("exists but is not in ORDER") never fires on it. It is not a
	controller: it has no init(), no start(), nothing to boot.

	EVERY SIZE IN HERE IS A DESIGN PIXEL, NOT A SCREEN PIXEL — see "Scale" below. Each
	HUD builds onto a UIKit.canvas(), which lays these numbers out for a 1280x720 screen
	and blows the result up to fill whatever screen it is actually on.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UIKit = {}

-- ── Palette ───────────────────────────────────────────────────────────────────
-- The union of all four controllers' old COLOR tables. They already agreed on every
-- shared key before this existed, so this is a dedup, not a re-design.
UIKit.C = {
	panel = Color3.fromHex("0C0F0A"),
	stroke = Color3.fromHex("2A3324"),
	text = Color3.fromHex("E4E9DE"),
	dim = Color3.fromHex("7C8874"),
	empty = Color3.fromHex("1E241A"),
	selected = Color3.fromHex("3E5A2E"),
	green = Color3.fromHex("22C55E"),
	amber = Color3.fromHex("F59E0B"),
	red = Color3.fromHex("EF4444"),
	blue = Color3.fromHex("6FA8C7"),
	scope = Color3.fromHex("8FD8FF"),
	-- HudController's old WHITE. Named for what it MEANS, not what it looks like:
	-- PLAN's ONE COLOUR RULE says this hex is suit-failure and nothing else, ever. A
	-- shared table named "white" invites some future caller to grab it for an
	-- unrelated highlight and quietly break the rule the original comment protected.
	burn = Color3.fromHex("FFFFFF"),
	-- The dark navigation cards: WarpController's BASE / SHOPS and IndexController's
	-- Index tile. Neutral near-black on purpose, so the white logo each one
	-- carries is the only thing on it with any colour. `navIcon` is that logo at rest;
	-- it goes to pure white on hover.
	navFill = Color3.fromRGB(18, 20, 24),
	navFillHover = Color3.fromRGB(29, 32, 38),
	navEdge = Color3.fromRGB(49, 53, 61),
	navEdgeHover = Color3.fromRGB(88, 94, 105),
	navIcon = Color3.fromRGB(232, 242, 255),
	navShadow = Color3.fromRGB(3, 7, 12),
	-- The heavy text/button outline below — pure black, matching the one place this
	-- already shipped (IndexController's tile caption) before this file made it the default.
	outline = Color3.new(0, 0, 0),
}

-- ── Type scale ───────────────────────────────────────────────────────────────────
-- ONE FAMILY IN THREE WEIGHTS, which is the formal-typography move and the opposite
-- of what this used to be. The old pair was LuckiestGuy (a heavy all-caps poster
-- face) over FredokaOne (a rounded workhorse) — two unrelated novelty families whose
-- only relationship was "both are chunky". That reads as a toy, and the shop's card
-- grid is where it showed worst: a price ladder wants to look like a storefront, not
-- a birthday card.
--
-- Gotham is the replacement across the board. Hierarchy now comes from WEIGHT + SIZE
-- inside one family instead of from swapping to a different typeface, so a heading
-- and the line under it visibly belong together. `hero` is still reserved for the
-- same short, one-off, celebratory strings it always was (the blackout headline, the
-- loot banner's item name) — it is a weight now, not a different font, but the rule
-- that nothing repeated or sentence-length uses it is unchanged.
--
-- SIZES WERE CALIBRATED FOR THE OLD FACES AND ARE NOW SLIGHTLY UNDERSET. LuckiestGuy
-- and FredokaOne render wider glyphs and a taller x-height than Gotham at the same
-- TextSize, so everything reads a touch smaller than it did. That is a deliberate
-- "change one thing at a time" — retune UIKit.TextSize after looking at it in
-- Studio, rather than pre-compensating blind here.
UIKit.Font = {
	hero = Enum.Font.GothamBlack, -- ONLY short, one-off, celebratory strings
	title = Enum.Font.GothamBold, -- panel titles, card names, primary buttons
	body = Enum.Font.GothamMedium, -- everything else: rows, status lines, readouts
}

UIKit.TextSize = {
	hero = 40, -- curtain headline, banner item name
	title = 26, -- panel / station titles
	header = 19, -- buttons, captions, sub-headers
	body = 15, -- status / info lines, item names
	caption = 13, -- smallest secondary text (slot keys, sub-labels)
}

-- ── Text outline + shadow ────────────────────────────────────────────────────────
-- THE "JUICY" TREATMENT, PROMOTED FROM A ONE-OFF TO THE DEFAULT. IndexController's
-- tile caption already shipped exactly this — a heavy black UIStroke on the text,
-- with TextStrokeTransparency forced to 1 so Roblox's own built-in stroke (a soft
-- ~1px hairline that reads as blur, not an outline) never doubles up underneath it.
-- UIKit.label/button now do this for every caller by default instead of it being
-- one controller's private trick.
--
-- THICKNESS SCALES WITH TEXT SIZE, ONE TABLE, KEYED LIKE TextSize ABOVE, because a
-- flat thickness looks right at one size and wrong at every other: thin enough here
-- and `hero` reads weedy; thick enough for `hero` and `caption` turns to a black
-- blob. strokeThicknessFor() below buckets any TextSize against these breakpoints,
-- so a one-off custom size still gets a sane answer instead of needing its own entry.
UIKit.TextStroke = {
	hero = 3,
	title = 2.5,
	header = 2,
	body = 2,
	caption = 1.5,
}

--- The stroke thickness for a given TextSize, bucketed against UIKit.TextSize's
--- breakpoints (largest-first) rather than matched exactly, so a custom one-off
--- size still gets a sensible answer.
function UIKit.strokeThicknessFor(textSize: number): number
	if textSize >= UIKit.TextSize.hero then
		return UIKit.TextStroke.hero
	elseif textSize >= UIKit.TextSize.title then
		return UIKit.TextStroke.title
	elseif textSize >= UIKit.TextSize.header then
		return UIKit.TextStroke.header
	elseif textSize >= UIKit.TextSize.body then
		return UIKit.TextStroke.body
	else
		return UIKit.TextStroke.caption
	end
end

-- THE DROP SHADOW IS A SEPARATE SIBLING INSTANCE, NOT A SECOND STROKE — a UIStroke
-- traces the glyph edge uniformly and cannot be offset, so an actual drop shadow
-- (the reference image has one) needs its own duplicate text instance, offset,
-- dark, behind. It defaults ON for `hero`/`title` tier text (the showcase moments —
-- banner headline, panel titles, card names, primary buttons) and OFF elsewhere
-- (status lines, per-slot readouts), so the extra instance only exists where it
-- earns its keep; either default can be overridden per call site via `shadow`.
UIKit.TextShadow = {
	offset = Vector2.new(2, 2),
	color = Color3.new(0, 0, 0),
	transparency = 0.55,
}

-- ── Corner radius / stroke ───────────────────────────────────────────────────────
UIKit.Radius = {
	panel = UDim.new(0, 20), -- station panel, banner
	card = UDim.new(0, 16), -- detail card, meter panel
	button = UDim.new(0, 14), -- haul panel / station action / shop buttons
	slot = UDim.new(0, 12), -- hotbar slots
	pill = UDim.new(1, 0), -- fully round — scope dial and its rings
}

UIKit.Stroke = {
	thin = 2, -- unselected hotbar slot, secondary rings
	normal = 3, -- panels, buttons, haul panel, station panel
	thick = 4, -- banner
	selected = 5, -- selected hotbar slot
}

-- ── Scale ────────────────────────────────────────────────────────────────────────
-- THE HUD WAS DRAWN IN FIXED PIXELS, WHICH IS WHY IT LOOKED SMALL. A 64px hotbar slot
-- is a ninth of a 720p screen's height and a seventeenth of a 1440p one: the same
-- number read as a chunky button on a laptop and as a postage stamp on a desktop.
-- "Make all the GUI bigger" is really "stop shrinking it as the screen grows".
--
-- So every number in this file, and every Offset in every controller, is a DESIGN
-- pixel now — the unit of a 1280x720 screen (DESIGN_SCREEN) — and each HUD builds onto
-- a canvas (UIKit.canvas below) that lays its children out in those units and then
-- draws them UIKit.scale() times bigger. 1080p gets 1.5x, 1440p 2x; it is the SAME
-- layout on all of them, just larger, so no Dock formula had to change.
--
-- SMALL SCREENS SHRINK TOO, DOWN TO A FLOOR. The viewport ratio used to be clamped at
-- 1, so anything smaller than the design screen (a docked Studio viewport, a phone)
-- kept the full 1280x720 layout at 0.8x and simply ran off the edges: on an 844x390
-- phone that is a 1024x576 HUD. The scale now follows the screen all the way down and
-- stops at MIN_SCALE, the smallest size text is still readable at (15px body text
-- lands at ~9 screen px). Above 1280x720 nothing changed: 1080p is still 1.5x0.8.
-- min() over both axes so a tall-but-narrow window is never scaled past what its width
-- can hold.
--
-- TOUCH GETS ITS OWN MULTIPLIER. GLOBAL_SCALE's 0.8 was a "smaller, please" asked for
-- on a monitor with a mouse. A finger needs bigger targets than a cursor, so a phone or
-- tablet uses TOUCH_SCALE in its place: a tablet reads larger than a laptop of the same
-- resolution, and a phone sits at the MIN_SCALE floor either way.
--
-- THE FLOOR IS ALSO WHAT KEEPS A PHONE'S LAYOUT FITTING. At 0.6 an 844x390 phone gets a
-- ~1400x650 design canvas, which still holds the tallest HUD stack (the haul widget,
-- 442 tall above a 132 dock). Raise MIN_SCALE and that stops being true on the
-- shortest phones — check a 375-tall screen before moving it.
--
-- WHAT A CANVAS COSTS ITS CALLER: anything that reads AbsoluteSize / AbsolutePosition
-- (screen pixels) and writes the answer back into an Offset (design pixels) has to
-- divide by UIKit.canvasScale() in between. Two places do — InventoryController's slot
-- fit and StationController's close button — and both say so. RadFx stays OFF the
-- canvas on purpose: it already sizes itself from the camera viewport.
UIKit.DESIGN_SCREEN = Vector2.new(1280, 720)

-- A flat multiplier on the viewport-derived scale above, so every canvas can be shrunk
-- (or grown) uniformly without retuning a single Offset anywhere. Mouse and keyboard
-- only; touch uses TOUCH_SCALE (see the section header).
UIKit.GLOBAL_SCALE = 0.8
UIKit.TOUCH_SCALE = 1
-- The smallest the HUD is ever drawn, on any screen. See the section header before
-- raising it.
UIKit.MIN_SCALE = 0.6

-- Every live canvas, plus — for a billboard's canvas — the gui and design size to
-- resize along with it. A STRONG table, pruned by ancestry (see track()). The first
-- draft was weak-keyed and silently lost canvases: Roblox is free to collect an
-- Instance's Lua handle whenever no script holds one, even while the Instance itself is
-- on screen, and a weak key goes with it. Any canvas that only ever lived in a local
-- dropped out of the table and stopped following the screen — frozen at the scale it
-- was built at, so it never grew when the real viewport arrived after load.
type Fit = { billboard: BillboardGui?, size: Vector2? }
local fitted: { [Frame]: Fit } = {}
local watching = false
local viewportConn: RBXScriptConnection? = nil

--- A phone or tablet: a touch screen with no keyboard. TouchEnabled alone is true on
--- touchscreen laptops too, and those are played with a mouse.
function UIKit.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function viewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.zero
end

--- Screen pixels per design pixel on the current viewport. See the section header.
function UIKit.scale(): number
	local viewport = viewportSize()
	local multiplier = if UIKit.isTouch() then UIKit.TOUCH_SCALE else UIKit.GLOBAL_SCALE
	-- Studio reports a zero viewport for a frame or two on load (RadFx.viewport hit the
	-- same thing); treat that as "no room yet" rather than dividing by it.
	if viewport.X < 1 or viewport.Y < 1 then
		return multiplier
	end
	local fit = math.min(viewport.X / UIKit.DESIGN_SCREEN.X, viewport.Y / UIKit.DESIGN_SCREEN.Y)
	return math.max(UIKit.MIN_SCALE, multiplier * fit)
end

-- ── Touch controls ───────────────────────────────────────────────────────────────
-- ON A PHONE, ROBLOX DRAWS ITS OWN CONTROLS IN BOTH BOTTOM CORNERS: the jump button on
-- the right, the thumbstick on the left. Anything of ours in those corners is either
-- hidden under them or, worse, eats the touch meant for them. These are the corner
-- boxes they take, in SCREEN px, copied from the default PlayerModule (TouchJump):
-- a 70px button inset 25 from the right and 20 from the bottom when the short side of
-- the screen is 500 or less, otherwise a 120px button inset 50 and 90. The thumbstick
-- gets the same box mirrored onto the left, which covers its resting ring.
local TOUCH_CORNER_SMALL = Vector2.new(95, 90)
local TOUCH_CORNER_LARGE = Vector2.new(170, 210)

--- The box each bottom corner's touch control takes, in DESIGN px: X in from the side
--- edge, Y up from the bottom edge. Zero off touch, so a caller can max() against it
--- unconditionally. It changes with the viewport, so read it from an onScaleChanged
--- callback, not once at build time.
function UIKit.touchCorner(): Vector2
	if not UIKit.isTouch() then
		return Vector2.zero
	end
	local viewport = viewportSize()
	local corner = if math.min(viewport.X, viewport.Y) <= 500 then TOUCH_CORNER_SMALL else TOUCH_CORNER_LARGE
	return corner / UIKit.scale()
end

local function fit(canvas: Frame, spec: Fit, s: number)
	local scaler = canvas:FindFirstChildOfClass("UIScale")
	if scaler then
		scaler.Scale = s
	end
	canvas.Size = UDim2.fromScale(1 / s, 1 / s)
	if spec.billboard and spec.size then
		spec.billboard.Size = UDim2.fromOffset(spec.size.X * s, spec.size.Y * s)
	end
end

local listeners: { () -> () } = {}

local function refresh()
	local s = UIKit.scale()
	for canvas, spec in fitted do
		fit(canvas, spec, s)
	end
	for _, listener in listeners do
		task.spawn(listener)
	end
end

--- One listener for every canvas, re-bound if the camera itself is swapped out.
local function watchViewport()
	if watching then
		return
	end
	watching = true
	local function bind()
		if viewportConn then
			viewportConn:Disconnect()
		end
		local camera = Workspace.CurrentCamera
		viewportConn = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh) else nil
		refresh()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bind)
	bind()
end

--- Keep `canvas` in `fitted` for exactly as long as it is in the game. Out of it (a
--- name tag's character despawned, a readout rebuilt) it leaves; back in, it rejoins
--- and catches up on any resize it missed while it was gone. Registered from birth,
--- because every caller builds onto its gui first and parents the gui after.
local function track(canvas: Frame, spec: Fit)
	fitted[canvas] = spec
	canvas.AncestryChanged:Connect(function()
		if canvas:IsDescendantOf(game) then
			fitted[canvas] = spec
			fit(canvas, spec, UIKit.scale())
		else
			fitted[canvas] = nil
		end
	end)
	watchViewport()
end

local function newCanvas(parent: Instance, zIndex: number?, spec: Fit): Frame
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.ZIndex = zIndex or 1

	local scaler = Instance.new("UIScale")
	scaler.Parent = canvas

	fit(canvas, spec, UIKit.scale())
	canvas.Parent = parent
	track(canvas, spec)
	return canvas
end

--- A transparent frame that covers `parent` exactly on screen but is laid out in
--- design pixels: sized 1/scale of its parent and blown back up by a UIScale of
--- `scale`, so a child's Offsets and TextSizes grow while its Scale positions (0.5 =
--- centre, 1 = far edge) still land where they always did. Build a HUD onto this
--- instead of straight onto its ScreenGui. It passes input through: an inactive Frame
--- never sinks a click, so the world behind it stays clickable.
---
--- `zIndex` only matters when the canvas has siblings that are NOT on it — HudController
--- keeps RadFx's damage overlay beside it, and the canvas has to draw above that.
function UIKit.canvas(parent: Instance, zIndex: number?): Frame
	return newCanvas(parent, zIndex, {})
end

--- Call `listener` now and again after every viewport change, once the canvases have
--- been refitted. For layout that depends on the scale itself (UIKit.touchCorner())
--- rather than on a canvas's size. Listeners live as long as the game does, so this
--- is for HUD built once, not for anything rebuilt.
function UIKit.onScaleChanged(listener: () -> ())
	table.insert(listeners, listener)
	watchViewport()
	listener()
end

--- The scale `canvas` is drawing at right now — what to divide a screen-pixel reading
--- (AbsoluteSize / AbsolutePosition of anything on it) by to get design pixels back.
function UIKit.canvasScale(canvas: Frame): number
	local scaler = canvas:FindFirstChildOfClass("UIScale")
	return if scaler then scaler.Scale else 1
end

--- The same for a world-space BillboardGui whose Size is in pixels. A pixel-sized
--- billboard holds a constant on-screen size, so it has exactly the HUD's problem and
--- gets exactly the HUD's fix: `size` is its design-pixel footprint, the gui is sized
--- to that times the scale, and its contents go on the returned canvas.
function UIKit.billboardCanvas(gui: BillboardGui, size: Vector2): Frame
	return newCanvas(gui, nil, { billboard = gui, size = size })
end

-- ── The notch ────────────────────────────────────────────────────────────────────
-- EVERY HUD GUI ALREADY STAYS OUT OF IT. A ScreenGui with IgnoreGuiInset = true gets
-- ScreenInsets = DeviceSafeInsets from the engine (and one without it, CoreUISafe-
-- Insets), so on a notched phone the whole gui — canvas and all — is already inset
-- clear of the camera cut-out, the rounded corners and the home bar.
--
-- A FULL-SCREEN LAYER MUST NOT BE. A wipe or a blackout that stops at the safe area
-- leaves a strip of the world showing down the notch side, and a layer placed in
-- viewport pixels (WorldToViewportPoint) lands off by the inset. Those guis set
-- ScreenInsets = None, and the few edge-hugging widgets on them add safeInsets() to
-- their margins so they still clear the notch themselves.
--
-- Two empty guis measured against each other: one with the HUD's own insets, whose
-- rect IS the safe area, and one with none, whose rect is the whole screen. Measured
-- against each other rather than against ViewportSize because AbsolutePosition is
-- reported below the topbar inset, not from the top of the screen.
local probes: { safe: ScreenGui, full: ScreenGui }? = nil

local function makeProbe(playerGui: Instance, name: string, insets: Enum.ScreenInsets): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = insets
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
	gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(refresh)
	gui.Parent = playerGui
	return gui
end

--- The device safe area's inset from each screen edge, in DESIGN px. Zero on a screen
--- without a notch, and until the first layout pass. Read it from an onScaleChanged
--- callback: rotating a phone swaps which side the notch is on.
function UIKit.safeInsets(): { left: number, top: number, right: number, bottom: number }
	local none = { left = 0, top = 0, right = 0, bottom = 0 }
	if probes == nil then
		local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui == nil then
			return none
		end
		probes = {
			safe = makeProbe(playerGui, "SafeAreaProbe", Enum.ScreenInsets.DeviceSafeInsets),
			full = makeProbe(playerGui, "FullScreenProbe", Enum.ScreenInsets.None),
		}
	end
	local safe, full = (probes :: any).safe, (probes :: any).full
	if safe.AbsoluteSize.X < 1 or full.AbsoluteSize.X < 1 then
		return none
	end
	local s = UIKit.scale()
	local topLeft = safe.AbsolutePosition - full.AbsolutePosition
	local bottomRight = (full.AbsolutePosition + full.AbsoluteSize) - (safe.AbsolutePosition + safe.AbsoluteSize)
	return {
		left = math.max(0, topLeft.X) / s,
		top = math.max(0, topLeft.Y) / s,
		right = math.max(0, bottomRight.X) / s,
		bottom = math.max(0, bottomRight.Y) / s,
	}
end

-- ── The dock ─────────────────────────────────────────────────────────────────────
-- The instrument band — just the METER now — with the status line above it, bag count
-- below it, hotbar at the screen edge, a bottom-LEFT column stacking [INDEX] over
-- [CASH] over the meter, and the detail card floating above all of it when a slot is
-- selected. The bottom-RIGHT corner is empty at rest — only the haul panel occupies
-- it, and only while a signal is being pulled:
--
--     ┌───────────────────────────────────────┐  <- Detail card (only if selected)
--     │[INDEX]        Status line               │
--     │[CASH ]                                  │
--     │[METER]                          (HAUL)  │  <- band 144px; haul panel is NOT in
--     │              Bag count                  │     it, and only up while hauling
--     │   [1][2][3][4][5][6][7][8][9]...        │  <- hotbar, screen edge
--     └───────────────────────────────────────┘
--
-- THE DIG BUTTON USED TO SIT DEAD-CENTRE OF THAT BAND AND IS GONE. It was permanent
-- furniture for something that only matters in the seconds you are stood on a glow —
-- on screen the whole time you were in a stage, saying GET CLOSER, directly above the
-- hotbar it competed with. Locking on is a ProximityPrompt over the glow itself now
-- (DetectorController), and the haul panel carries the mash bar, so the dock has no
-- dig widget at all. Nothing moved when it went: INSTRUMENT_HEIGHT was a max() that
-- the meter already won.
--
-- THE RADAR SCOPE IS GONE. It used to sit inside the instrument band, then alone in
-- the bottom-right corner — a dial with a ring for the detector radius and a blip per
-- registered contact. It was removed on request as unnecessary: the world (aura wells
-- + FieldController's range ring) answers "where", and its per-player rarity/odds
-- readout moved onto the floating pick-up card and the haul panel's title. Neither
-- `SCOPE_DIAL` nor `DIAL_LEFT_OFFSET` is positioned relative to the row any more
-- because neither exists.
--
-- INDEX MOVED FROM THE SCOPE'S CORNER TO THE CASH BADGE'S COLUMN, THEN TO THE RIGHT
-- EDGE. It briefly stacked above CashController's badge on the left; it now sits
-- standalone on the MIDDLE-RIGHT as the square Index tile, its top edge level
-- with the top of the cash/meter column (Dock.SIDE_TOP_Y; centred instead on a short
-- screen, Dock.SIDE_TOP_MIN_HEIGHT), which itself moved to the middle-left
-- (Dock.CASH_MID_Y / Dock.METER_MID_Y). Its own size lives in IndexController.
--
-- ONE WIDE BAND, NOT STACKED ROWS. What lives in the band sits side by side inside one
-- INSTRUMENT_HEIGHT-tall row rather than stacking vertically, which would cost roughly
-- 200px on its own. That choice is the entire reason "bigger and centered" does not
-- also mean "covers the ground you are digging" — see RESERVE below, which is the
-- dock's total reserved height with no card open. Anything added to this row later
-- goes BESIDE the meter, not under it.
--
-- EVERY DOWNSTREAM POSITION IS A FORMULA OVER THESE, NEVER A FRESH NUMBER. That is
-- the whole point: the old `-178` in InventoryController existed because nothing
-- here did.
local Dock = {}
UIKit.Dock = Dock

-- Base sizes.
Dock.MARGIN_BOTTOM = 18 -- screen bottom edge -> hotbar
Dock.GAP = 10 -- vertical gap between stacked dock bands
Dock.INSTRUMENT_GAP = 20 -- horizontal gap inside the meter / button / dial row

Dock.HOTBAR_HEIGHT = 76 -- was InventoryController.SLOT_HEIGHT 62
Dock.SLOT_MAX = 96 -- was 78
Dock.SLOT_MIN = 64 -- was 52
Dock.SLOT_GAP = 8 -- was 6
Dock.ROW_SIDE_MARGIN = 24 -- hotbar row width = 1 scale minus 2x this, in offset
Dock.ROW_MAX_WIDTH = 1400 -- absolute cap so an ultrawide monitor does not stretch it

Dock.BAGCOUNT_HEIGHT = 18

-- was 240x46, then 280x60 (HEALTH joined RADS), then 144 before the DEPTH row, then 170
-- before HEALTH/RADS got breathing room between them, then 184. Now 142: the cartoon
-- panel (header strip + health + rads = 104) at its TALLEST, with the countdown strip
-- showing. It is anchored by its top edge (METER_TOP_Y) and only grows downward when the
-- countdown appears, so this is the room the left column reserves for it.
Dock.METER_SIZE = UDim2.fromOffset(280, 142)

Dock.STATUS_HEIGHT = 24
Dock.CARD_SIZE = UDim2.fromOffset(350, 118) -- was 400x136, then 330x116 before that — a size request, on purpose

-- THE HAUL WIDGET. Up only while a player is locked onto a signal and mashing it out.
-- It is deliberately OUT OF THE MIDDLE OF THE SCREEN, in both axes, and for one
-- reason: the payoff of a haul is watching the thing rise out of the ground in front
-- of your character. That happens at screen centre, so anything drawn there is drawn
-- over the only part of the haul the player actually came for. It sits as LOW as it
-- can (HAULPANEL_BOTTOM) and just right of centre (HAULPANEL_CENTRE_GAP), stopping
-- short of the Index/Shop tiles on a narrow screen (HAULPANEL_RIGHT).
--
-- NAMED "PANEL" AND IT IS NOT ONE ANY MORE. There is no fill and no stroke behind the
-- contents: this is the bounding box of a floating stack, not a slab. The 420x230 slab
-- it used to draw was the bulk of what the haul cost the screen — the content inside
-- it was never the problem — and 240x210 with nothing drawn behind it is roughly a
-- quarter of the pixels the old one covered. The name stays because HAULPANEL_BOTTOM,
-- ui.haul and every caller already read it and a rename buys nothing.
--
-- THE SOIL SHAFT INSIDE IT SETS BOTH NUMBERS. The haul is drawn as a cut-away of the
-- ground (HaulShaft) with the nuke hauled up it from the floor, so the widget is as
-- tall as the shaft needs to make the climb and its depth ruler readable, plus REEL IN
-- under it; the readout (rarity, odds, metres to the surface) sits beside it,
-- right-aligned against the shaft, so naming what you hooked costs no height.
-- DetectorController's SHAFT_* / READOUT_* derive the whole interior from this one size.
--
-- 386x442, UP FROM 320x290, and the taller box is the price of the shaft. It is still
-- a floating stack with nothing drawn behind it, and it still keeps off the middle:
-- see HAULPANEL_CENTRE_GAP for where it sits and HAULPANEL_RIGHT for the tiles.
--
-- ITS BOX OVERLAPS THE STATUS LINE'S BAND (STATUS_BOTTOM). That is safe rather than
-- lucky: DigService releases the lock the instant the bag fills (its RELEASE 3), and
-- the only other line the status can carry is the buried-too-deep one, which needs
-- `not hasSignal` -- so the two are never on screen in the same frame.
Dock.HAULPANEL_SIZE = UDim2.fromOffset(386, 442)

-- Derived. Every "-178 hand-tuned against another file" number becomes a read of one
-- of these instead.
-- Just the meter now. This was a math.max over the meter and the dig button until the
-- dig button was removed from the dock entirely (lock-on moved to a world prompt over
-- the glow, and the haul panel carries the mash bar). The max() resolved to the meter's
-- 144 anyway, so RESERVE and everything positioned off it are UNCHANGED by that
-- removal -- worth stating, because a shifting RESERVE would have moved the hotbar,
-- the station panel and the haul panel all at once.
--
-- PINNED AT 184, NO LONGER A READ OF METER_SIZE. The meter left this bottom band for
-- the middle-left column long ago, so it was only still coupled by this line — and when
-- the cartoon panel shrank METER_SIZE to 142, reading it would have dropped the
-- detector status line (STATUS_BOTTOM) and every card above it by 42px for no reason.
-- 184 is the height they were all laid out against.
Dock.INSTRUMENT_HEIGHT = 184

Dock.HOTBAR_BOTTOM = Dock.MARGIN_BOTTOM
Dock.BAGCOUNT_BOTTOM = Dock.HOTBAR_BOTTOM + Dock.HOTBAR_HEIGHT + Dock.GAP
Dock.INSTRUMENT_BOTTOM = Dock.BAGCOUNT_BOTTOM + Dock.BAGCOUNT_HEIGHT + Dock.GAP
Dock.STATUS_BOTTOM = Dock.INSTRUMENT_BOTTOM + Dock.INSTRUMENT_HEIGHT + Dock.GAP
-- A REQUESTED LOWER POSITION, WITH AN HONEST COST. The stack above this point (hotbar
-- -> bagcount -> instrument -> status) has no slack in it — every band sits Dock.GAP
-- above the one before it, contiguously, all the way from the screen edge. "Lower"
-- therefore has nowhere to come from except the status line's own reserved height, so
-- this drops the "+ Dock.STATUS_HEIGHT" term that used to clear it entirely. The card's
-- bottom slice now sits over the LAST ~14px of the status line's band instead of fully
-- above it. Acceptable because the card is a transient popup (only up while a hotbar
-- item is selected) over a single line of read-only text, not over the meter or the dig
-- button — reconsider this the moment that stops being true.
Dock.CARD_BOTTOM = Dock.STATUS_BOTTOM + Dock.GAP

-- The LEFT column: cash badge on top, the speed badge one GAP below it, the meter one
-- GAP below that (SPEED_SIZE, added with the Speed unit), the stack centred on the
-- vertical (Dock.CASH_MID_Y / Dock.METER_MID_Y — defined just below CASH_BOTTOM). It
-- was bottom-anchored in the corner until "middle left" was requested. (The
-- loaded-liquid badge used to top this stack — it is a BillboardGui on the wash pad
-- now, LiquidController — and the index button that briefly replaced it as the top
-- element has since moved to the RIGHT screen edge, IndexController. The left column
-- ends at the cash badge.)
--
-- CASH_SIZE WAS A PRIVATE LOCAL IN CashController until the index button stacked on
-- top of it here. WIDTH IS A READ OF METER_SIZE, NOT A SEPARATE NUMBER — it used to be
-- a hand-picked 216 while the comment here claimed "same width as the meter", which
-- was false (the meter is 280); deriving it outright is the only way that claim stays
-- true. Height grew 52 -> 64 alongside CashController's bigger balance text, then
-- 64 -> 86 for the cartoon gold-coin badge: the card itself is still 64 tall, but the
-- "+$/s" income pill hangs off its bottom edge and the column has to reserve that
-- overhang or the pill lands on the meter. CASH_BOTTOM is the old bottom-corner
-- baseline — kept as the reference point the SIDE_* offsets below are documented
-- against, and in case the column ever moves back.
Dock.CASH_SIZE = UDim2.fromOffset(Dock.METER_SIZE.X.Offset, 86)
-- THE SPEED BADGE (SpeedController), between the cash badge and the meter: a 48-tall
-- card plus the level pill hanging off its bottom edge, the same overhang shape as the
-- cash badge's income pill. Same width as the column, read off the meter like CASH_SIZE.
Dock.SPEED_SIZE = UDim2.fromOffset(Dock.METER_SIZE.X.Offset, 64)
Dock.CASH_BOTTOM = Dock.INSTRUMENT_BOTTOM + Dock.METER_SIZE.Y.Offset + Dock.GAP

-- MIDDLE-LEFT / MIDDLE-RIGHT PLACEMENT. On request the cash+meter column and the
-- INDEX button left the bottom corners for the vertical centre of their screen edge.
-- The column stays one rigid stack — cash badge on top, meter one GAP below it —
-- placed by each panel's OWN centre (anchorPoint y = 0.5) at a fixed offset from
-- screen middle, so it packs the same way however either element is resized. These
-- are offsets from 0.5-scale, negative = above centre.
Dock.SIDE_STACK_HEIGHT = Dock.CASH_SIZE.Y.Offset
	+ Dock.GAP
	+ Dock.SPEED_SIZE.Y.Offset
	+ Dock.GAP
	+ Dock.METER_SIZE.Y.Offset
Dock.CASH_MID_Y = Dock.CASH_SIZE.Y.Offset / 2 - Dock.SIDE_STACK_HEIGHT / 2
Dock.SPEED_MID_Y = Dock.CASH_SIZE.Y.Offset + Dock.GAP + Dock.SPEED_SIZE.Y.Offset / 2 - Dock.SIDE_STACK_HEIGHT / 2
Dock.METER_MID_Y = Dock.SIDE_STACK_HEIGHT / 2 - Dock.METER_SIZE.Y.Offset / 2
-- The column's TOP edge, as the same kind of offset from screen middle. IndexController
-- hangs the Index tile from it on the right edge, so both sides start on one line.
--
-- TOP-ALIGNED RATHER THAN CENTRED. This was first done so the Index tile would clear
-- the haul widget's rarity readout, back when the two shared the right edge; the haul
-- widget now stops short of the tile column entirely (HAULPANEL_RIGHT), but the tiles
-- stay hung from this line so both sides of the screen start level.
Dock.SIDE_TOP_Y = -Dock.SIDE_STACK_HEIGHT / 2
-- The meter's TOP edge, one GAP under the speed badge. HudController anchors the panel
-- here rather than on METER_MID_Y because its height changes (the countdown strip), and
-- it must grow away from the badges above, not into them.
Dock.METER_TOP_Y = Dock.SIDE_TOP_Y + Dock.CASH_SIZE.Y.Offset + Dock.GAP + Dock.SPEED_SIZE.Y.Offset + Dock.GAP
-- ...and the shortest design screen that line is used on. Below it the hang stops
-- working in both directions: the readout climbs into it as the screen shortens, and
-- under ~460 the tile rises into the Settings gear in the corner above. So a shorter
-- screen gets the tile back on the vertical centre, where the old pill sat and where
-- both leave it room. Every screen the HUD scales up on is DESIGN_SCREEN.Y (720) tall
-- or more in design pixels, so this only bites on a small window or a phone, where
-- the MIN_SCALE floor leaves the design canvas shorter than that.
Dock.SIDE_TOP_MIN_HEIGHT = 700

-- The Index and Shop tiles on the right edge (IndexController / ShopController): one
-- square size for both, and what the haul widget measures its clearance against.
Dock.SIDE_TILE_SIZE = 80

-- The dock's total reserved height with no card open. Nothing anchors against it today
-- — StationController and IndexController both centre their panels on the screen itself
-- now (see their headers) and the left column moved to the middle-left — but it stays
-- as the honest measure of how much bottom-edge space the dock claims.
Dock.RESERVE = Dock.STATUS_BOTTOM + Dock.STATUS_HEIGHT

-- RIGHT ABOVE THE HOTBAR, on request. Its bottom edge sits one GAP above the bag-count
-- line (which is itself one GAP above the hotbar), so the whole hotbar cluster stays
-- visible underneath and the widget drops as low as it possibly can without covering
-- it.
--
-- This is a deliberate reversal of the old "clear the entire dock" placement
-- (RESERVE + GAP). The widget now overlays the instrument band's vertical space — but
-- that band is the meter / cash column, which is LEFT-anchored, and this sits right
-- of centre (HAULPANEL_CENTRE_GAP below). Anchored off the hotbar rather than a
-- screen fraction for the same reason everything else here is: a fraction that looked
-- right at 1080p collided with the dock on shorter viewports.
Dock.HAULPANEL_BOTTOM = Dock.BAGCOUNT_BOTTOM + Dock.BAGCOUNT_HEIGHT + Dock.GAP

-- AND JUST RIGHT OF CENTRE, on request. Its LEFT edge sits this far right of screen
-- centre (DetectorController.placeHaul). Centred, the stack sat straight over the
-- character and the thing climbing out of the soil in front of them; hard in the right
-- corner, the reading was a long way from where the player is looking. This keeps it
-- beside the action: the readout is right-aligned, so the visible text starts another
-- ~50-90px further out, past a character that is only ~70px wide on screen.
Dock.HAULPANEL_CENTRE_GAP = 100

-- ...UNLESS THAT WOULD RUN IT UNDER THE INDEX/SHOP TILES. The shaft is 442 tall, which
-- reaches up past the tiles hung on the right edge (Dock.SIDE_TOP_Y down), so on a
-- screen too narrow to fit the panel between centre + CENTRE_GAP and the tile column,
-- it slides left only as far as it must to stop one GAP short of that column. This is
-- that clearance, as an inset from the right screen edge.
--
-- THE COST IS PAID ON NARROW VIEWPORTS: once it has to slide, it slides toward centre,
-- and on a design width much under ~1100 (a 4:3 window, a phone held upright) it starts
-- to overlap the surfacing item; further in it tucks behind the meter (DisplayOrder 100
-- against DetectorHud's 60). The fix if it ever matters is a narrower widget under some
-- width, not a different anchor.
Dock.HAULPANEL_RIGHT = Dock.ROW_SIDE_MARGIN + Dock.SIDE_TILE_SIZE + Dock.GAP

-- ── Builders ─────────────────────────────────────────────────────────────────────
-- Spec-table-in, instance-out, same shape as server/build/Kit.build. These replace
-- the 10-15 lines of Instance.new / UICorner / UIStroke boilerplate each call site
-- used to hand-roll — they do not touch any caller's own `ui` table, and the caller
-- still owns and stores whatever reference it needs.

export type PanelProps = {
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchorPoint: Vector2?,
	color: Color3?,
	transparency: number?,
	strokeColor: Color3?,
	strokeThickness: number?,
	cornerRadius: UDim?,
	automaticSizeY: boolean?,
	zIndex: number?,
	visible: boolean?,
}

function UIKit.panel(parent: Instance, props: PanelProps): (Frame, UIStroke)
	local frame = Instance.new("Frame")
	frame.Name = props.name or "Panel"
	frame.Size = props.size
	frame.Position = props.position or UDim2.fromOffset(0, 0)
	frame.AnchorPoint = props.anchorPoint or Vector2.zero
	frame.BackgroundColor3 = props.color or UIKit.C.panel
	frame.BackgroundTransparency = if props.transparency ~= nil then props.transparency else 0.1
	frame.BorderSizePixel = 0
	frame.ZIndex = props.zIndex or 1
	frame.Visible = if props.visible ~= nil then props.visible else true
	if props.automaticSizeY then
		frame.AutomaticSize = Enum.AutomaticSize.Y
	end
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = props.cornerRadius or UIKit.Radius.card
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = props.strokeColor or UIKit.C.stroke
	stroke.Thickness = props.strokeThickness or UIKit.Stroke.normal
	stroke.Parent = frame

	return frame, stroke
end

export type LabelProps = {
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchorPoint: Vector2?,
	text: string?,
	font: Enum.Font?,
	textSize: number,
	color: Color3?,
	xAlign: Enum.TextXAlignment?,
	yAlign: Enum.TextYAlignment?,
	wrapped: boolean?,
	zIndex: number?,
	strokeTransparency: number?,
	visible: boolean?,
	-- `outline` defaults ON (the heavy black UIStroke). The handful of existing
	-- soft-stroke callers (a deliberate glow on a gauge/liquid readout, a different
	-- visual language from outlined text) pass `outline = false` to keep their old
	-- look and their own `strokeTransparency` untouched.
	outline: boolean?,
	-- `shadow` defaults to the font: on for hero/title (the showcase text), off
	-- elsewhere. Either can be forced explicitly.
	shadow: boolean?,
}

function UIKit.label(parent: Instance, props: LabelProps): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.name or "Label"
	label.Size = props.size
	label.Position = props.position or UDim2.fromOffset(0, 0)
	label.AnchorPoint = props.anchorPoint or Vector2.zero
	label.BackgroundTransparency = 1
	local font = props.font or UIKit.Font.body
	label.Font = font
	label.TextSize = props.textSize
	label.TextColor3 = props.color or UIKit.C.text
	label.TextXAlignment = props.xAlign or Enum.TextXAlignment.Left
	label.TextYAlignment = props.yAlign or Enum.TextYAlignment.Center
	label.TextWrapped = props.wrapped == true
	label.Text = props.text or ""
	label.ZIndex = props.zIndex or 1
	label.Visible = if props.visible ~= nil then props.visible else true

	local outline = props.outline ~= false
	if outline then
		-- The hard UIStroke is the outline; the old soft built-in one would just
		-- blur underneath it, so it's forced off rather than left at the caller's
		-- (or the 0.6 default's) value.
		label.TextStrokeTransparency = 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = UIKit.C.outline
		stroke.Thickness = UIKit.strokeThicknessFor(props.textSize)
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
	else
		label.TextStrokeTransparency = if props.strokeTransparency ~= nil then props.strokeTransparency else 0.6
	end

	label.Parent = parent

	local shadow = props.shadow
	if shadow == nil then
		shadow = font == UIKit.Font.hero or font == UIKit.Font.title
	end
	if shadow then
		local shadowLabel = Instance.new("TextLabel")
		shadowLabel.Name = label.Name .. "Shadow"
		shadowLabel.Size = label.Size
		shadowLabel.Position = label.Position + UDim2.fromOffset(UIKit.TextShadow.offset.X, UIKit.TextShadow.offset.Y)
		shadowLabel.AnchorPoint = label.AnchorPoint
		shadowLabel.BackgroundTransparency = 1
		shadowLabel.Font = label.Font
		shadowLabel.TextSize = label.TextSize
		shadowLabel.TextColor3 = UIKit.TextShadow.color
		shadowLabel.TextTransparency = UIKit.TextShadow.transparency
		shadowLabel.TextStrokeTransparency = 1
		shadowLabel.TextXAlignment = label.TextXAlignment
		shadowLabel.TextYAlignment = label.TextYAlignment
		shadowLabel.TextWrapped = label.TextWrapped
		shadowLabel.Text = label.Text
		shadowLabel.ZIndex = label.ZIndex - 1
		shadowLabel.Visible = label.Visible
		shadowLabel.Parent = parent
		-- Bound live so any later `label.Text = ...` (every controller does this
		-- constantly — cash ticking up, status lines, item names) keeps the shadow
		-- in sync without the caller ever knowing it exists.
		label:GetPropertyChangedSignal("Text"):Connect(function()
			shadowLabel.Text = label.Text
		end)
		label:GetPropertyChangedSignal("Visible"):Connect(function()
			shadowLabel.Visible = label.Visible
		end)
	end

	return label
end

export type ButtonProps = {
	name: string?,
	size: UDim2,
	position: UDim2?,
	anchorPoint: Vector2?,
	text: string?,
	font: Enum.Font?,
	textSize: number,
	color: Color3?,
	fillColor: Color3?,
	fillTransparency: number?,
	strokeColor: Color3?,
	strokeThickness: number?,
	cornerRadius: UDim?,
	zIndex: number?,
	visible: boolean?,
	-- Defaults ON: recolors the box's existing UIStroke to `UIKit.C.outline`, which
	-- — since Roblox strokes a TextButton's own glyphs the same as its box border —
	-- outlines the button's text too, in one instance. `strokeColor` still wins if a
	-- caller passes one explicitly.
	outline: boolean?,
	-- Same default-by-font rule as UIKit.label (on for hero/title). Implemented as a
	-- child TextLabel rather than a sibling: a child renders above the button's own
	-- fill but, given a lower ZIndex than the button, still behind the button's own
	-- native text — confirmed live in Studio before relying on it here.
	shadow: boolean?,
}

function UIKit.button(parent: Instance, props: ButtonProps): (TextButton, UIStroke)
	local button = Instance.new("TextButton")
	button.Name = props.name or "Button"
	button.Size = props.size
	button.Position = props.position or UDim2.fromOffset(0, 0)
	button.AnchorPoint = props.anchorPoint or Vector2.zero
	button.BackgroundColor3 = props.fillColor or UIKit.C.panel
	button.BackgroundTransparency = if props.fillTransparency ~= nil then props.fillTransparency else 0.15
	button.BorderSizePixel = 0
	button.AutoButtonColor = false -- every caller drives its own hover/press state
	local font = props.font or UIKit.Font.body
	button.Font = font
	button.TextSize = props.textSize
	button.TextColor3 = props.color or UIKit.C.text
	button.Text = props.text or ""
	button.ZIndex = props.zIndex or 1
	button.Visible = if props.visible ~= nil then props.visible else true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = props.cornerRadius or UIKit.Radius.button
	corner.Parent = button

	local outline = props.outline ~= false
	local stroke = Instance.new("UIStroke")
	stroke.Color = props.strokeColor or (if outline then UIKit.C.outline else UIKit.C.stroke)
	stroke.Thickness = props.strokeThickness or UIKit.Stroke.normal
	stroke.Parent = button
	if outline then
		button.TextStrokeTransparency = 1
	end

	local shadow = props.shadow
	if shadow == nil then
		shadow = font == UIKit.Font.hero or font == UIKit.Font.title
	end
	if shadow then
		local shadowLabel = Instance.new("TextLabel")
		shadowLabel.Name = "TextShadow"
		shadowLabel.Size = UDim2.fromScale(1, 1)
		shadowLabel.Position = UDim2.fromOffset(UIKit.TextShadow.offset.X, UIKit.TextShadow.offset.Y)
		shadowLabel.BackgroundTransparency = 1
		shadowLabel.Font = button.Font
		shadowLabel.TextSize = button.TextSize
		shadowLabel.TextColor3 = UIKit.TextShadow.color
		shadowLabel.TextTransparency = UIKit.TextShadow.transparency
		shadowLabel.TextStrokeTransparency = 1
		shadowLabel.TextXAlignment = button.TextXAlignment
		shadowLabel.TextYAlignment = button.TextYAlignment
		shadowLabel.Text = button.Text
		shadowLabel.ZIndex = button.ZIndex - 1
		shadowLabel.Parent = button
		-- Bound live for the same reason as UIKit.label's shadow: StationController
		-- and friends reassign `.Text` on these buttons constantly post-creation
		-- (EQUIP/EQUIPPED, PURCHASE price, etc.) and never need to know this exists.
		button:GetPropertyChangedSignal("Text"):Connect(function()
			shadowLabel.Text = button.Text
		end)
	end

	return button, stroke
end

-- ── Formatting ───────────────────────────────────────────────────────────────────

--- A RECORD weight: "0.12 kg", "16.2 kg", "461 kg". One more digit than the banners'
--- whole-kilo ladder, because a record is compared against the last one — "7 kg, was
--- 7 kg" is what the coarse ladder says about a 7.4 beating a 6.9.
function UIKit.formatKg(kg: number): string
	if kg < 1 then
		return string.format("%.2f kg", kg)
	elseif kg < 100 then
		return string.format("%.1f kg", kg)
	end
	return string.format("%d kg", math.floor(kg + 0.5))
end

return UIKit
