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
local GuiService = game:GetService("GuiService")
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
	-- PLAN's ONE COLOUR RULE says this hex is aura-failure and nothing else, ever. A
	-- shared table named "white" invites some future caller to grab it for an
	-- unrelated highlight and quietly break the rule the original comment protected.
	burn = Color3.fromHex("FFFFFF"),
	-- The dark navigation cards: the right-edge tiles (Index, Shop, Nukes, Warp).
	-- Neutral near-black on purpose, so the white logo each one
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

-- ── House style ──────────────────────────────────────────────────────────────────
-- What most panels already wear (Daily, Gear, Masteries, Gifts, Potions, the station
-- panels...): Gotham Black in white with a black outline on slate. Each of those still
-- copies these hexes into its own table; new and migrated GUIs read them from here, so
-- the same meaning gets the same colour everywhere. UIKit.C above is the older olive
-- HUD palette and UIKit.Font below the older three-weight scale.
UIKit.House = {
	font = Enum.Font.GothamBlack,
	panel = Color3.fromHex("1B1F23"),
	card = Color3.fromHex("22272C"),
	ink = Color3.fromHex("1A1A1A"), -- outlines and edges (Kit.C.hazardBlack)
	white = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA3AD"), -- secondary text
	close = Color3.fromHex("E5484D"), -- every panel's "X"
	buy = Color3.fromHex("3FB35A"), -- buy / claim / equip buttons
	buyHover = Color3.fromHex("52C96C"),
	cash = Color3.fromHex("7CF25A"), -- money amounts (the HUD's cash readout)
	robux = Color3.fromHex("7B3FE4"),
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

-- ── Text outline ───────────────────────────────────────────────────────────────
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
-- standalone on the MIDDLE-RIGHT in the tile column, centred on the right edge
-- (Dock.sideColumnTop). The
-- speed/cash column it once lined up with is in the bottom-left corner now
-- (Dock.CASH_BOTTOM / Dock.SPEED_BOTTOM). Its own size lives in IndexController.
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

-- The left column's width (cash + speed badges). It used to be read off the rad meter
-- card that sat under them (METER_SIZE, 280 wide), until health and rads moved down to
-- the vitals bars above the hotbar. 280 -> 340 -> 380 as the rows' numbers grew to 56px,
-- so a "$1.23M" still fits at full size. The vitals bars' left edge stays clear of it on
-- every screen the HUD scales for (~1330 design px wide at the least).
-- 380 -> 320 when the rows shrank ~18% (icons 88 -> 72, numbers 56 -> 46).
Dock.SIDE_WIDTH = 320

-- THE VITALS BARS (HudController): health + rads as two slim cartoon bars, with the
-- countdown (top left) and stage + depth (top right) on a label row above them.
-- Centred over the hotbar, sitting where the bag-count line's band starts, so its
-- bottom is one GAP above the hotbar's top. A fixed width, not the hotbar's live
-- length: a starter suit's 6 slots would make it too short to read. HudController
-- narrows it on a screen that cannot fit it.
Dock.VITALS_WIDTH = 640
Dock.VITALS_HEIGHT = 74 -- label row 18 + 3 + rads 26 + 1 + health 26

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
-- THE TUG-OF-WAR ROPE INSIDE IT SETS BOTH NUMBERS. The haul is drawn as a rope
-- (HaulRope) with the nuke sliding along it from the dirt into the player's magnet, so
-- the widget is as wide as the slide needs to read, and three rows tall: the readout
-- (rarity word, metres to go) over the rope, LET GO and REEL IN under it.
-- DetectorController's PANEL_* / ROPE_TOP / HAULBUTTON_* derive the interior from
-- this one size: 34 of readout + HaulRope.HEIGHT 88 + 8 of gap + 46 of buttons = 176.
--
-- 440x176, on request (2026-10-09: the soil shaft's 340x474 column became this wide,
-- short strip). It is still a floating stack with nothing drawn behind it, and it still
-- keeps off the middle: see HAULPANEL_CENTRE_GAP for where it sits and HAULPANEL_RIGHT
-- for the tiles.
--
-- ITS BOX OVERLAPS THE STATUS LINE'S BAND (STATUS_BOTTOM). That is safe rather than
-- lucky: DigService releases the lock the instant the bag fills (its RELEASE 3), and
-- the only other line the status can carry is the buried-too-deep one, which needs
-- `not hasSignal` -- so the two are never on screen in the same frame.
Dock.HAULPANEL_SIZE = UDim2.fromOffset(440, 176)

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
-- The vitals bars start where the bag-count band does and reach up into the instrument
-- band, which has been empty since the meter moved out of it, so nothing above them
-- (the status line, the item card) moves. VITALS_CLEAR is the floor for anything that
-- pops up bottom-centre and must not land on the bars.
Dock.VITALS_BOTTOM = Dock.BAGCOUNT_BOTTOM
Dock.VITALS_CLEAR = Dock.VITALS_BOTTOM + Dock.VITALS_HEIGHT + Dock.GAP
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

-- The LEFT column, in the BOTTOM-LEFT CORNER: the speed row on top (SPEED_SIZE, added
-- with the Speed unit), the cash row under it, both icon-plus-number with no card
-- behind them. The corner has held this column before (CASH_BOTTOM was its old
-- baseline), then the vertical centre of the left edge ("middle left" was requested),
-- and now the corner again, by request, once the cards were gone. The corner is free:
-- the hotbar and the vitals bars are centred, and every screen the HUD scales for is
-- at least ~1330 design px wide, which leaves the vitals' left edge well clear of the
-- column's text. The rad meter card used to hang under the speed badge; it is the
-- vitals bars over the hotbar now (VITALS_*). (The loaded-liquid badge and then the
-- index button once topped this column; the first is a BillboardGui on the wash pad
-- now, LiquidController, and the second a tile on the RIGHT edge, IndexController.)
--
-- CASH_SIZE WAS A PRIVATE LOCAL IN CashController until the index button stacked on
-- top of it here. WIDTH IS A READ OF SIDE_WIDTH, NOT A SEPARATE NUMBER — it used to be
-- a hand-picked 216 while the comment here claimed "same width as the meter", which
-- was false (the meter was 280); deriving it outright is the only way that claim stays
-- true. Height grew 52 -> 64 alongside CashController's bigger balance text, then
-- 64 -> 86 for the cartoon gold-coin badge, then 86 -> 78 when the card shrank to 56,
-- then 78 -> 72 when the card went, then 72 -> 80 when the balance was pinned level
-- with the bundle's middle and the "+$/s" line hung under it (it used to lift the
-- balance to make room, which read as the money jumping), then 80 -> 96 -> 102 -> 104 as
-- the rows were resized (icons 64 -> 96 -> 88, balance 32 -> 48 -> 56), then 104 -> 74
-- when the "+$/s" line was dropped (the user asked for it gone) and the rows shrank ~18%:
-- the bundle fills it now.
Dock.CASH_SIZE = UDim2.fromOffset(Dock.SIDE_WIDTH, 74)
-- THE SPEED ROW (SpeedController), over the cash row: the sneaker plus its drop
-- shadow, with the WALK SPEED caption and the number beside it. Same width as the
-- column, SIDE_WIDTH like CASH_SIZE. 60 -> 72 -> 88 -> 80 -> 66 with the cash row's
-- resizes; the sneaker fills it.
Dock.SPEED_SIZE = UDim2.fromOffset(Dock.SIDE_WIDTH, 66)
-- The width of the icon slot both rows share: the cash bundle fills it, the sneaker is
-- centred in it, and both numbers start just past it.
Dock.SIDE_ICON = 72
-- Where each picture's visible drawing is centred, as a fraction of its height: both
-- PNGs carry more transparent margin on top than below (the bundle's art spans 17%..89%,
-- the sneaker's 21%..85%). Each row centres its number on this line, not on the box,
-- or the balance read high against the bundle and walk speed low against the sneaker.
Dock.SIDE_ICON_MIDDLE = 0.53
-- NEGATIVE: the rows overlap. Most of the space between them is transparent margin
-- inside the two pictures (~12px under the sneaker's sole, ~15px over the bundle's top
-- edge at these sizes), so a positive gap reads as a big hole. -8 leaves ~19px of air
-- between the sole and the bundle. Tuned by eye in both directions: -22 (~7px) and -12
-- (~15px) were each "a little looser", then -4 (~23px) "a bit smaller". -6 after the
-- ~18% shrink (the margins shrank with the pictures), still ~16px of air.
Dock.PAIR_GAP = -6
-- Each row's BOTTOM edge as an offset UP from the screen's bottom edge (Position y is
-- 1-scale minus this, anchor y = 1), before Dock.sideLift(). Speed stacks on cash;
-- SIDE_COLUMN_TOP is the pair's top edge.
--
-- TUCKED DEEPER INTO THE CORNER than the hotbar's margins (MARGIN_BOTTOM 18 /
-- ROW_SIDE_MARGIN 24), as the user asked: the pictures carry their own transparent
-- margin (~8px under the bundle), so these small offsets still leave the art clear of
-- the screen edge. SIDE_CORNER_X is the column's left edge; everything on the column
-- (both rows, the aura tip above them) lines up on it.
Dock.SIDE_CORNER_X = 8
Dock.CASH_BOTTOM = 4
Dock.SPEED_BOTTOM = Dock.CASH_BOTTOM + Dock.CASH_SIZE.Y.Offset + Dock.PAIR_GAP
Dock.SIDE_COLUMN_TOP = Dock.SPEED_BOTTOM + Dock.SPEED_SIZE.Y.Offset

--- How far the left column rises off the bottom edge, in design px: the height of the
--- thumbstick's corner box on a phone or tablet (UIKit.touchCorner), so the numbers are
--- never under the stick, and 0 everywhere else. It moves with the viewport, so read it
--- from UIKit.onScaleChanged.
function Dock.sideLift(): number
	return UIKit.touchCorner().Y
end

-- ON A PHONE OR TABLET THE PAIR SITS HARD IN THE BOTTOM-LEFT CORNER, smaller, on request
-- (2026-10-06, after a round on the jump button bottom-right): no thumbstick lift, so it
-- tucks into the corner like the mouse layout, drawn TOUCH_PAIR_SCALE times its size
-- (each row's own UIScale). The dynamic thumbstick still starts anywhere above it; the
-- rows are plain labels, so a thumb on them steers (only the pencil takes a tap).
Dock.TOUCH_PAIR_SCALE = 0.7

--- The size the speed/cash rows are drawn at (their UIScale's resting value).
function Dock.pairScale(): number
	return if UIKit.isTouch() then Dock.TOUCH_PAIR_SCALE else 1
end

--- The cash row's bottom edge, design px up from the screen's bottom edge.
function Dock.cashBottom(): number
	return Dock.CASH_BOTTOM
end

--- The speed row's bottom edge, stacked on the cash row at the pair's scale.
function Dock.speedBottom(): number
	return Dock.cashBottom() + (Dock.SPEED_BOTTOM - Dock.CASH_BOTTOM) * Dock.pairScale()
end

--- The pair's top edge (the speed row's top), up from the screen's bottom edge.
function Dock.pairTop(): number
	return Dock.cashBottom() + (Dock.SIDE_COLUMN_TOP - Dock.CASH_BOTTOM) * Dock.pairScale()
end

--- Position for a pair row (or anything lined up on the column, AnchorPoint (0, 1))
--- whose bottom edge sits `bottom` design px up from the screen's bottom edge.
function Dock.pairPosition(bottom: number): UDim2
	return UDim2.new(0, Dock.SIDE_CORNER_X, 1, -bottom)
end

--- The top of whatever stands in the bottom-LEFT corner, up from the screen's bottom
--- edge: the pair, or the thumbstick's box on touch if that is taller. The aura tip
--- sits on it.
function Dock.leftCornerTop(): number
	return math.max(Dock.pairTop(), Dock.sideLift())
end

-- THE BUTTON GRID on the middle of the LEFT edge, on request (2026-10-03, after a
-- reference of a 2x3 grid of dark tiles with big 3D pictures and the name across the
-- foot): Shop | Index, Nukes | Gear, Warp | Free Gifts, slots 1-6 left to right, top to
-- bottom (HudTile builds them). It was one column of 58px Gear/Nukes/Warp squares on the
-- right, with Shop and Index as bars on the left. Masteries' bare medal stood on top of
-- it until it took Gear's slot (2026-10-05, the Gear panel removed on request).
-- 76 -> 66 -> 58, smaller, on request (with the AI pictures).
-- BIGGER OFF TOUCH, on request (2026-10-06: "make the gui bigger on the left, not for
-- phone players"): every grid measure (tile, gap, poke, and HudTile's picture, caption
-- and corners) is multiplied by SIDE_GRID_SCALE, which is 1 on a phone or tablet.
Dock.SIDE_GRID_SCALE = if UIKit.isTouch() then 1 else 1.3
Dock.SIDE_GRID_TILE = math.round(58 * Dock.SIDE_GRID_SCALE)
Dock.SIDE_GRID_COLUMNS = 2
-- Two rows since Nukes and Potions moved to the right edge (2026-10-07, on request):
-- the wide Shop over Index | Gifts.
-- WIDE BARS since 2026-10-09 (on request, from a reference: two chunky pills, the
-- picture on the left and the name beside it): Free Gifts gone, Shop over Index, each
-- bar both columns wide and SIDE_BAR_HEIGHT tall, so a row is a bar, not a square.
Dock.SIDE_GRID_ROWS = 2
-- 44 -> 36, shorter on request (2026-10-09).
Dock.SIDE_BAR_HEIGHT = math.round(36 * Dock.SIDE_GRID_SCALE)
-- The space between two tiles. Tight, like the reference: the pictures poke up over the
-- tile's top edge, so the rows need a little room for that.
Dock.SIDE_TILE_GAP = math.round(9 * Dock.SIDE_GRID_SCALE)
-- How far a tile's picture pokes up over its top edge (HudTile): "barely sticking out", on request.
Dock.SIDE_GRID_POKE = math.round(4 * Dock.SIDE_GRID_SCALE)
-- How far below the canvas's middle the grid's middle sits, on request ("lower them a little").
Dock.SIDE_GRID_DROP = 28
Dock.SIDE_GRID_WIDTH = Dock.SIDE_GRID_COLUMNS * Dock.SIDE_GRID_TILE + (Dock.SIDE_GRID_COLUMNS - 1) * Dock.SIDE_TILE_GAP
Dock.SIDE_GRID_HEIGHT = Dock.SIDE_GRID_ROWS * Dock.SIDE_BAR_HEIGHT + (Dock.SIDE_GRID_ROWS - 1) * Dock.SIDE_TILE_GAP
-- THE HIDE-NUKES TOGGLE over the Shop tile (2026-10-08, on request: "put the hide other
-- nukes thing above the shop"): a bar as wide as the grid, SIDE_TOGGLE_GAP over its top.
-- The grid keeps room for it under the top-left buttons (leftGridTop).
Dock.SIDE_TOGGLE_HEIGHT = math.round(26 * Dock.SIDE_GRID_SCALE)
Dock.SIDE_TOGGLE_GAP = math.round(8 * Dock.SIDE_GRID_SCALE)
-- THE TOP-RIGHT CORNER ROW, up in the topbar band on request: Daily rewards, Potions to
-- its left. (Settings moved to the top LEFT, beside Roblox's own buttons: topbarLeftCentre.) Measured from the SCREEN top (their guis ignore the
-- topbar inset). WAY SMALLER, on request (2026-10-03): about the size of Roblox's own
-- 44px topbar buttons and level with them (theirs run 12-56 screen px).
Dock.CORNER_TILE_SIZE = 40
Dock.CORNER_TOP = 14
Dock.CORNER_SIDE = 12
Dock.CORNER_GAP = 8
-- HARD IN THE TOP-RIGHT CORNER on every screen, on request (2026-10-04); it used to
-- start left of Roblox's player list on a keyboard screen.
-- The corner row's bottom edge, from the screen top.
Dock.CORNER_BUTTON_BOTTOM = Dock.CORNER_TOP + Dock.CORNER_TILE_SIZE

--- How far in from the right edge the top-right row's `count` buttons reach, in design px.
function Dock.cornerRowWidth(count: number): number
	return Dock.CORNER_SIDE + count * Dock.CORNER_TILE_SIZE + (count - 1) * Dock.CORNER_GAP
end

--- The centre of corner button `index` (1 = Daily, 2 = Potions left of it),
--- on a canvas that ignores the topbar inset.
function Dock.cornerButtonCentre(index: number): UDim2
	local half = Dock.CORNER_TILE_SIZE / 2
	local fromRight = Dock.CORNER_SIDE + half + (index - 1) * (Dock.CORNER_TILE_SIZE + Dock.CORNER_GAP)
	return UDim2.new(1, -fromRight, 0, Dock.CORNER_TOP + half)
end

-- ROBLOX'S OWN TOPBAR BUTTONS (the menu, chat, the microphone), in SCREEN px: a fixed
-- 44px square whose top sits 12 px down, 12 px apart, whatever our UI scale is.
-- GuiService.TopbarInset starts 4 px after the last of them.
Dock.ROBLOX_BUTTON = 44
Dock.ROBLOX_TOP = 12
Dock.ROBLOX_GAP = 12
local ROBLOX_INSET_PAD = 4

-- OUR TOP-LEFT BUTTON (Settings; Info moved to the top right) a little SMALLER than Roblox's, on request
-- (2026-10-09, so they crowd the HOME/SELL/WARP bar less on a phone): TOPBAR_LEFT_BUTTON
-- screen px, centred on the same line as Roblox's buttons, TOPBAR_LEFT_GAP apart.
Dock.TOPBAR_LEFT_BUTTON = 36
Dock.TOPBAR_LEFT_GAP = 8
local TOPBAR_LEFT_TOP = Dock.ROBLOX_TOP + (Dock.ROBLOX_BUTTON - Dock.TOPBAR_LEFT_BUTTON) / 2

--- The centre of top-left button `index` (1 = Settings): in the
--- topbar band on the LEFT, right after Roblox's own buttons, on request. A FIXED SCREEN
--- SIZE on every screen (2026-10-08: "always scale it so it's the same size"), so
--- measured in screen px and divided by the scale. The inset moves when Roblox adds or
--- drops a button, so re-read it on its change signal (Dock.onTopbarChanged).
function Dock.topbarLeftCentre(index: number?): UDim2
	local half = Dock.TOPBAR_LEFT_BUTTON / 2
	local step = ((index or 1) - 1) * (Dock.TOPBAR_LEFT_BUTTON + Dock.TOPBAR_LEFT_GAP)
	local x = GuiService.TopbarInset.Min.X + Dock.ROBLOX_GAP - ROBLOX_INSET_PAD + half + step
	local scale = UIKit.scale()
	return UDim2.fromOffset(x / scale, (TOPBAR_LEFT_TOP + half) / scale)
end

--- The right edge of the last of our `count` top-left buttons, in design px from the
--- canvas's left. Anything centred along the top (the HOME/SELL/WARP bar) starts past it.
function Dock.topbarLeftRight(count: number): number
	local x = GuiService.TopbarInset.Min.X + Dock.ROBLOX_GAP - ROBLOX_INSET_PAD
		+ count * Dock.TOPBAR_LEFT_BUTTON + (count - 1) * Dock.TOPBAR_LEFT_GAP
	return x / UIKit.scale()
end

--- What a CORNER_TILE_SIZE tile is scaled by to stand exactly TOPBAR_LEFT_BUTTON screen px.
function Dock.topbarLeftScale(): number
	return Dock.TOPBAR_LEFT_BUTTON / UIKit.scale() / Dock.CORNER_TILE_SIZE
end

--- The top-left buttons' bottom edge, in design px from the screen top.
function Dock.topbarLeftBottom(): number
	return (TOPBAR_LEFT_TOP + Dock.TOPBAR_LEFT_BUTTON) / UIKit.scale()
end

--- Call `listener` now and whenever the scale or Roblox's topbar buttons change.
function Dock.onTopbarChanged(listener: () -> ())
	UIKit.onScaleChanged(listener)
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(listener)
end

--- The right-hand tile grid's TOP edge, in design px from the vertical centre of a
--- canvas `height` design px tall. CENTRED ON THE RIGHT EDGE, on request (it used to
--- hang from a fixed line, SIDE_TOP_Y -68, a little above centre) -- but never so high
--- that the top row runs up into the corner buttons above it, which only
--- bites on a short window or a phone. Every tile places itself from this one line
--- (Dock.sideTileCentre).
function Dock.sideColumnTop(height: number): number
	local underGear = Dock.CORNER_BUTTON_BOTTOM + Dock.GAP + Dock.SIDE_GRID_POKE - height / 2
	return math.max(-Dock.SIDE_GRID_HEIGHT / 2 + Dock.SIDE_GRID_DROP, underGear)
end

--- The LEFT grid's top edge, like sideColumnTop (design px from the canvas's vertical
--- centre). Off touch it IS sideColumnTop. ON A PHONE the speed/cash pair is lifted over
--- the thumbstick (sideLift) and ran up into the grid's bottom row, so the grid rises
--- until its bottom clears the pair by GAP, on request ("speed and money overlap").
--- The right-edge cards keep reading sideColumnTop, so they don't move with it.
function Dock.leftGridTop(height: number): number
	local toggle = Dock.SIDE_TOGGLE_HEIGHT + Dock.SIDE_TOGGLE_GAP
	-- Never so high that the hide-nukes toggle over the Shop runs into the top-left buttons.
	local underButtons = Dock.topbarLeftBottom() + Dock.GAP + toggle - height / 2
	local top = math.max(Dock.sideColumnTop(height), underButtons)
	local lift = Dock.sideLift()
	if lift <= 0 then
		return top
	end
	local pairTop = height / 2 - Dock.leftCornerTop()
	local clear = pairTop - Dock.GAP - Dock.SIDE_GRID_HEIGHT
	-- Never up into Roblox's topbar band (screen px there, so divided by the scale).
	local band = GuiService.TopbarInset.Max.Y / UIKit.scale() + Dock.GAP + toggle - height / 2
	return math.max(math.min(top, clear), band)
end

--- The CENTRE of the hide-nukes toggle: over the grid's top row, as wide as the grid.
function Dock.sideToggleCentre(height: number): UDim2
	local down = Dock.leftGridTop(height) - Dock.SIDE_TOGGLE_GAP - Dock.SIDE_TOGGLE_HEIGHT / 2
	return UDim2.new(0, Dock.ROW_SIDE_MARGIN + Dock.SIDE_GRID_WIDTH / 2, 0.5, down)
end

--- The CENTRE of grid tile `slot` (1-6, left to right, top to bottom), as a position on
--- a canvas `height` design px tall: offset in from the LEFT edge, and down from the
--- vertical centre. Centred so a tile's hover UIScale grows it evenly on every side.
function Dock.sideTileCentre(slot: number, height: number): UDim2
	local column = (slot - 1) % Dock.SIDE_GRID_COLUMNS
	local row = (slot - 1) // Dock.SIDE_GRID_COLUMNS
	local step = Dock.SIDE_GRID_TILE + Dock.SIDE_TILE_GAP
	local fromLeft = Dock.ROW_SIDE_MARGIN + column * step + Dock.SIDE_GRID_TILE / 2
	local down = Dock.leftGridTop(height) + row * (Dock.SIDE_BAR_HEIGHT + Dock.SIDE_TILE_GAP) + Dock.SIDE_BAR_HEIGHT / 2
	return UDim2.new(0, fromLeft, 0.5, down)
end

--- Where the tile grid ends: its bottom row's bottom edge, in design px from the canvas
--- TOP. BoostsController keeps the Boosts widget below it.
function Dock.sideColumnBottom(height: number): number
	return height / 2 + Dock.leftGridTop(height) + Dock.SIDE_GRID_HEIGHT
end

-- THE RIGHT-EDGE COLUMN (2026-10-07, on request: "put the nukes and potions on the right
-- side of the screen, make them slightly smaller, and remove the text under them"): Nukes
-- over Potions, the grid's studded tiles at RIGHT_TILE_SCALE with no caption, centred on
-- the right edge like the grid on the left. The Starter Pack offer hangs above it and the
-- Boosts widget keeps below it. It replaced the 2x Luck / 2x Speed pass cards.
-- Captions put back 2026-10-08 ("put nukes and potions under nukes and potion gui").
-- 0.85 -> 0.72 with double the gap, on request ("smaller, space them out a little more").
Dock.RIGHT_TILE_SCALE = 0.72
Dock.RIGHT_TILE = math.round(Dock.SIDE_GRID_TILE * Dock.RIGHT_TILE_SCALE)
Dock.RIGHT_TILE_GAP = Dock.SIDE_TILE_GAP * 2
Dock.RIGHT_TILES = 2
Dock.RIGHT_COLUMN_HEIGHT = Dock.RIGHT_TILES * Dock.RIGHT_TILE + (Dock.RIGHT_TILES - 1) * Dock.RIGHT_TILE_GAP

--- The right column's TOP edge, in design px from the canvas's vertical centre: centred
--- (dropped like the left grid), never up into the corner row.
function Dock.rightColumnTop(height: number): number
	local underCorner = Dock.CORNER_BUTTON_BOTTOM + Dock.GAP + Dock.SIDE_GRID_POKE - height / 2
	return math.max(-Dock.RIGHT_COLUMN_HEIGHT / 2 + Dock.SIDE_GRID_DROP, underCorner)
end

--- The CENTRE of right-column tile `index` (1 = top), offset in from the RIGHT edge and
--- down from the vertical centre.
function Dock.rightTileCentre(index: number, height: number): UDim2
	local down = Dock.rightColumnTop(height) + (index - 1) * (Dock.RIGHT_TILE + Dock.RIGHT_TILE_GAP) + Dock.RIGHT_TILE / 2
	return UDim2.new(1, -(Dock.ROW_SIDE_MARGIN + Dock.RIGHT_TILE / 2), 0.5, down)
end

--- The right column's bottom edge, in design px from the canvas TOP.
function Dock.rightColumnBottom(height: number): number
	return height / 2 + Dock.rightColumnTop(height) + Dock.RIGHT_COLUMN_HEIGHT
end

-- The dock's total reserved height with no card open. Nothing anchors against it today
-- — StationController and IndexController both centre their panels on the screen itself
-- now (see their headers) and the left column moved to the middle-left — but it stays
-- as the honest measure of how much bottom-edge space the dock claims.
Dock.RESERVE = Dock.STATUS_BOTTOM + Dock.STATUS_HEIGHT

-- RIGHT ABOVE THE HOTBAR, on request. Its bottom edge sits one GAP above the vitals
-- bars (VITALS_CLEAR, which sit on the hotbar), so the whole hotbar cluster and the
-- health/rads readout stay visible underneath -- rads matter most mid-haul -- and the
-- widget drops as low as it possibly can without covering them.
--
-- This is a deliberate reversal of the old "clear the entire dock" placement
-- (RESERVE + GAP). The widget now overlays the instrument band's vertical space — but
-- that band is the meter / cash column, which is LEFT-anchored, and this sits right
-- of centre (HAULPANEL_CENTRE_GAP below). Anchored off the hotbar rather than a
-- screen fraction for the same reason everything else here is: a fraction that looked
-- right at 1080p collided with the dock on shorter viewports.
Dock.HAULPANEL_BOTTOM = Dock.VITALS_CLEAR

-- AND JUST RIGHT OF CENTRE, on request. Its LEFT edge sits this far right of screen
-- centre (DetectorController.placeHaul). Centred, the stack sat straight over the
-- character and the thing climbing out of the soil in front of them; hard in the right
-- corner, the reading was a long way from where the player is looking. This keeps it
-- beside the action: the readout is right-aligned, so the visible text starts another
-- ~50-90px further out, past a character that is only ~70px wide on screen.
Dock.HAULPANEL_CENTRE_GAP = 100

-- ...UNLESS THAT WOULD RUN IT UNDER THE INDEX/SHOP TILES. The shaft is 442 tall, which
-- reaches up past the tiles hung on the right edge (Dock.sideColumnTop down), so on a
-- screen too narrow to fit the panel between centre + CENTRE_GAP and the tile column,
-- it slides left only as far as it must to stop one GAP short of that column. This is
-- that clearance, as an inset from the right screen edge.
--
-- THE COST IS PAID ON NARROW VIEWPORTS: once it has to slide, it slides toward centre,
-- and on a design width much under ~1100 (a 4:3 window, a phone held upright) it starts
-- to overlap the surfacing item; further in it tucks behind the meter (DisplayOrder 100
-- against DetectorHud's 60). The fix if it ever matters is a narrower widget under some
-- width, not a different anchor.
-- THE BOOSTS WIDGET (BoostsController): the bottom-right "CURRENT BOOSTS" header over the
-- Luck / Cash / Walk Speed totals, just above the hotbar. The haul panel keeps clear of
-- its width.
Dock.BOOSTS_WIDTH = 200
Dock.BOOSTS_HEADER = 20
Dock.BOOSTS_ROW = 34
Dock.BOOSTS_ROW_GAP = 2
Dock.BOOSTS_ROWS = 3
Dock.BOOSTS_HEIGHT = Dock.BOOSTS_HEADER + Dock.BOOSTS_ROWS * (Dock.BOOSTS_ROW + Dock.BOOSTS_ROW_GAP)

--- The lowest the Boosts widget's bottom edge may sit, up from the screen's bottom edge:
--- hard in the corner, level with the hotbar's bottom (on request, 2026-10-06), and above
--- the jump button on touch. Read on scale changes.
function Dock.boostsFloor(): number
	local floor = Dock.HOTBAR_BOTTOM
	local corner = UIKit.touchCorner()
	if corner.Y > 0 then
		floor = math.max(floor, corner.Y + Dock.GAP)
	end
	return floor
end

-- The smallest the Boosts widget shrinks to on a short canvas.
Dock.BOOSTS_MIN_FIT = 0.6

--- Where the Boosts widget sits on a canvas `height` design px tall: its bottom edge (up
--- from the screen's bottom edge) and its UIScale. It rests on boostsFloor and keeps
--- under the left grid's bottom row (sideColumnBottom) and the right column's
--- (rightColumnBottom): on a short canvas it slides
--- down, then shrinks. BoostsController draws it here.
function Dock.boostsLayout(height: number): (number, number)
	local floor = Dock.boostsFloor()
	local bottom = floor
	-- The highest its top may reach, measured up from the bottom edge like `bottom`.
	local ceiling = height - math.max(Dock.sideColumnBottom(height), Dock.rightColumnBottom(height)) - Dock.GAP
	local tall = Dock.BOOSTS_HEIGHT
	if ceiling - bottom < tall then
		bottom = math.max(floor, ceiling - tall)
	end
	return bottom, math.clamp((ceiling - bottom) / tall, Dock.BOOSTS_MIN_FIT, 1)
end

--- The top of the Boosts widget's box, up from the screen's bottom edge.
function Dock.boostsTop(height: number): number
	local bottom, scale = Dock.boostsLayout(height)
	return bottom + Dock.BOOSTS_HEIGHT * scale
end

-- THE STARTER PACK CARD (StarterOfferController), hanging hard right under the corner
-- row, DROP lower so its rays clear the corner tiles, above the right column. Smaller on
-- touch (TOUCH_FIT), on request (2026-10-06); smaller everywhere (2026-10-07).
Dock.STARTER_DROP = 24
Dock.STARTER_CARD_H = 128
Dock.STARTER_TOUCH_FIT = 0.7
Dock.STARTER_TOP = Dock.CORNER_BUTTON_BOTTOM + Dock.GAP + Dock.STARTER_DROP
-- With the button grid on the LEFT edge, the right corner only holds the Boosts widget.
Dock.HAULPANEL_RIGHT = Dock.ROW_SIDE_MARGIN + Dock.BOOSTS_WIDTH + Dock.GAP

-- AND NEVER TALLER THAN THE SCREEN HAS ROOM FOR. On a landscape phone (~625-650 design
-- px tall) HAULPANEL_BOTTOM + 474 ran the widget's top off the screen, under the
-- topbar. DetectorController.placeHaul shrinks it (its own UIScale) until its top sits
-- this far below the screen top -- clear of the Settings/Daily corner row, which sits
-- level with Roblox's topbar -- but never below MIN_FIT, where REEL IN stops being a
-- comfortable thumb target. Desktop windows of 720+ design px tall are untouched.
Dock.HAULPANEL_TOP_CLEAR = Dock.CORNER_BUTTON_BOTTOM + Dock.GAP
Dock.HAULPANEL_MIN_FIT = 0.6

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

	return label
end

--- A big HUD number standing straight on the world with no panel behind it (the cash
--- and speed rows): an outlined UIKit.label, `stroke` design px thick, over a solid
--- `outline`-coloured copy of itself (stroke and all) dropped `drop` px down-right.
--- Text, TextSize, Position and Visible are mirrored live, so a caller only ever
--- touches the returned label.
function UIKit.hudNumber(parent: Instance, props: LabelProps, stroke: number, drop: Vector2): TextLabel
	local label = UIKit.label(parent, props)
	local uiStroke = label:FindFirstChildOfClass("UIStroke")
	if uiStroke then
		uiStroke.Thickness = stroke
	end

	local shadow = label:Clone()
	shadow.Name = label.Name .. "Shadow"
	shadow.TextColor3 = UIKit.C.outline
	shadow.ZIndex = label.ZIndex - 1
	shadow.Parent = parent
	local offset = UDim2.fromOffset(drop.X, drop.Y)
	local function sync()
		shadow.Text = label.Text
		shadow.TextSize = label.TextSize
		shadow.Position = label.Position + offset
		shadow.Visible = label.Visible
	end
	sync()
	for _, property in { "Text", "TextSize", "Position", "Visible" } do
		label:GetPropertyChangedSignal(property):Connect(sync)
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

	return button, stroke
end

export type CloseButtonProps = {
	name: string?,
	size: number?, -- square side in design px; 40 is the panel default
	position: UDim2?,
	anchorPoint: Vector2?,
	zIndex: number?,
}

--- THE ONE CLOSE "X". Every panel used to hand-roll its own -- some with an ink
--- border and a bare glyph, some with an outlined glyph and no border, square,
--- rounder or a disc -- so two open at once looked like two games. This is the
--- only look now: a House.close square, an ink border, and a white Gotham Black
--- "X" with its own ink outline. A PLAIN "X", NOT U+2715: Gotham has no cross
--- glyph and draws a missing-glyph box. Corner, border and type all scale off
--- `size`, so a small hint chip is the same badge, just smaller.
function UIKit.closeButton(parent: Instance, props: CloseButtonProps?): TextButton
	local p: CloseButtonProps = props or {}
	local side = p.size or 40
	local zIndex = p.zIndex or 1

	local button = Instance.new("TextButton")
	button.Name = p.name or "Close"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = UIKit.House.close
	button.BorderSizePixel = 0
	button.AnchorPoint = p.anchorPoint or Vector2.zero
	button.Position = p.position or UDim2.fromOffset(0, 0)
	button.Size = UDim2.fromOffset(side, side)
	button.ZIndex = zIndex
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.round(side * 0.2))
	corner.Parent = button

	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = UIKit.House.ink
	border.Thickness = if side >= 28 then UIKit.Stroke.normal else UIKit.Stroke.thin
	border.Parent = button

	-- The glyph is its own label: a UIStroke on the button can outline the box OR
	-- the text, not both.
	local textSize = math.round(side * 0.6)
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Font = UIKit.House.font
	glyph.Text = "X"
	glyph.TextSize = textSize
	glyph.TextColor3 = UIKit.House.white
	glyph.TextStrokeTransparency = 1
	glyph.ZIndex = zIndex
	glyph.Parent = button
	local ink = Instance.new("UIStroke")
	ink.Color = UIKit.House.ink
	ink.Thickness = UIKit.strokeThicknessFor(textSize)
	ink.LineJoinMode = Enum.LineJoinMode.Round
	ink.Parent = glyph

	-- Callers often raise ZIndex after building; under Global ZIndexBehavior the
	-- glyph would then sink behind its own button.
	button:GetPropertyChangedSignal("ZIndex"):Connect(function()
		glyph.ZIndex = button.ZIndex
	end)

	return button
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
