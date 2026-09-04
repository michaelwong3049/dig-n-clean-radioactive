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
]]

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
	green = Color3.fromHex("8FE04A"),
	amber = Color3.fromHex("F59E0B"),
	red = Color3.fromHex("EF4444"),
	blue = Color3.fromHex("6FA8C7"),
	scope = Color3.fromHex("8FD8FF"),
	-- HudController's old WHITE. Named for what it MEANS, not what it looks like:
	-- PLAN's ONE COLOUR RULE says this hex is suit-failure and nothing else, ever. A
	-- shared table named "white" invites some future caller to grab it for an
	-- unrelated highlight and quietly break the rule the original comment protected.
	burn = Color3.fromHex("FFFFFF"),
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

-- ── The dock ─────────────────────────────────────────────────────────────────────
-- The instrument band — just the METER now — with the status line above it, bag count
-- below it, hotbar at the screen edge, a bottom-LEFT column stacking [INDEX] over
-- [CASH] over the meter, the radar scope alone in the bottom-right corner, and the
-- detail card floating above all of it when a slot is selected:
--
--     ┌───────────────────────────────────────┐  <- Detail card (only if selected)
--     │[INDEX]        Status line               │
--     │[CASH ]                                  │
--     │[METER]                         ( SCOPE )│  <- band 144px; scope is NOT in it
--     │              Bag count                  │
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
-- THE SCOPE IS IN THE CORNER, NOT IN THE BAND, AND THAT IS THE WHOLE POINT OF THIS
-- LAYOUT. It used to sit inside the instrument band, where being the tallest thing in
-- the row (180 vs the meter's 144) pushed INSTRUMENT_HEIGHT
-- and therefore RESERVE up for everything else. It is now anchored to the bottom-right
-- corner on its own, sharing only the INSTRUMENT_BOTTOM baseline with the meter
-- opposite it, so `SCOPE_DIAL` is deliberately ABSENT from INSTRUMENT_HEIGHT below.
-- Put it back in that max() and the centred station panel loses 36px of headroom for
-- a widget that is no longer in the row.
--
-- `DIAL_LEFT_OFFSET` is gone for the same reason: the scope is corner-anchored now, so
-- it is not positioned relative to anything else in the row.
--
-- INDEX MOVED FROM THE SCOPE'S CORNER TO THE CASH BADGE'S COLUMN. It now stacks
-- directly above CashController's badge, on the meter's own left margin, rather than
-- floating alone in the opposite corner — see Dock.INDEX_BOTTOM below.
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

Dock.METER_SIZE = UDim2.fromOffset(280, 144) -- was 240x46, then 280x60 before HEALTH joined RADS in one panel
Dock.SCOPE_DIAL = 180 -- was DetectorController.DIAL_SIZE 150

Dock.STATUS_HEIGHT = 24
Dock.CARD_SIZE = UDim2.fromOffset(350, 118) -- was 400x136, then 330x116 before that — a size request, on purpose

-- THE HAUL WIDGET. Up only while a player is locked onto a signal and mashing it out.
-- It is deliberately OUT OF THE MIDDLE OF THE SCREEN, in both axes, and for one
-- reason: the payoff of a haul is watching the thing rise out of the ground in front
-- of your character. That happens at screen centre, so anything drawn there is drawn
-- over the only part of the haul the player actually came for. It sits as LOW as it
-- can (HAULPANEL_BOTTOM) and as far to the RIGHT as it can (HAULPANEL_RIGHT).
--
-- NAMED "PANEL" AND IT IS NOT ONE ANY MORE. There is no fill and no stroke behind the
-- contents: this is the bounding box of a floating stack, not a slab. The 420x230 slab
-- it used to draw was the bulk of what the haul cost the screen — the content inside
-- it was never the problem — and 240x210 with nothing drawn behind it is roughly a
-- quarter of the pixels the old one covered. The name stays because HAULPANEL_BOTTOM,
-- ui.haul and every caller already read it and a rename buys nothing.
--
-- THE BAR INSIDE IT IS VERTICAL, which is what sets the height. A horizontal strip
-- said "progress"; a column says what the haul actually IS — the thing is under you
-- and it has to come all the way UP — and the fill climbing towards a top edge is a
-- target you can see, where a strip's right-hand end never read as one. The column
-- gets 216px of travel here, under the PULL button and over the magnet and the
-- release hint; the rarity/odds readout sits BESIDE the bar precisely so naming what
-- you hooked costs no height. DetectorController's HAULBAR_* / HAULTRACK_* derive the
-- whole interior from this one number — nothing in there re-hardcodes 380 or 370.
--
-- 380x370, UP FROM 320x290 (and 240x210 before that), on request: bigger again.
-- Stripping the panel took the widget's weight off with its bulk, and out in the
-- corner where it lives the result kept reading as a small quiet thing rather than as
-- the control you are hammering. The bar is the part that grew most, both times
-- (54x118 -> 72x161 -> 88x216), because the bar is what the player is actually
-- watching — the extra 80px of height is spent almost entirely on its travel. Still
-- narrower than the old 420x230 slab, and drawing none of it.
--
-- ITS BOX COVERS THE STATUS LINE'S BAND (STATUS_BOTTOM) OUTRIGHT now that it is both
-- taller and lifted; it used to only clip the band's last few px. Still safe rather
-- than lucky, and doubly so because the box draws nothing: DigService releases the
-- lock the instant the bag fills (its RELEASE 3), and the only other line the status
-- can carry is the buried-too-deep one, which needs `not hasSignal` — so the two
-- are never on screen in the same frame. The status line is centred and 640 wide, so
-- even if that stopped holding, the collision would only be this widget's left ~30px.
Dock.HAULPANEL_SIZE = UDim2.fromOffset(380, 370)

-- Derived. Every "-178 hand-tuned against another file" number becomes a read of one
-- of these instead.
-- Just the meter now. This was a math.max over the meter and the dig button until the
-- dig button was removed from the dock entirely (lock-on moved to a world prompt over
-- the glow, and the haul panel carries the mash bar). The max() resolved to the meter's
-- 144 anyway, so RESERVE and everything positioned off it are UNCHANGED by that
-- removal -- worth stating, because a shifting RESERVE would have moved the hotbar,
-- the station panel and the haul panel all at once.
Dock.INSTRUMENT_HEIGHT = Dock.METER_SIZE.Y.Offset

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

-- The bottom-RIGHT corner: just the scope, on the meter's baseline.
Dock.SCOPE_BOTTOM = Dock.INSTRUMENT_BOTTOM

-- The bottom-LEFT column, bottom-up: meter on the instrument baseline, cash badge
-- above it, index button above that, the loaded-liquid badge above that. Each one's
-- bottom is the previous one's top plus a gap, so the column stays packed however any
-- single element is resized.
--
-- CASH_SIZE/CASH_BOTTOM WERE PRIVATE LOCALS IN CashController until the index button
-- moved into this column. They had to come here the moment a second file needed to
-- stack on top of them — IndexController working out its own offset from the cash
-- badge's height would be precisely the "-178 hand-tuned against another file" bug
-- this table exists to prevent. Same width as the meter, so all three share edges.
Dock.CASH_SIZE = UDim2.fromOffset(Dock.METER_SIZE.X.Offset, 56)
Dock.CASH_BOTTOM = Dock.INSTRUMENT_BOTTOM + Dock.METER_SIZE.Y.Offset + Dock.GAP
Dock.INDEX_BOTTOM = Dock.CASH_BOTTOM + Dock.CASH_SIZE.Y.Offset + Dock.GAP

-- INDEX_SIZE WAS IndexController's PRIVATE `BUTTON_SIZE = 72` until the liquid badge
-- needed to stack on top of it — the same migration CASH_SIZE went through one
-- element earlier, for exactly the same reason. The square button is the only element
-- in this column that is not meter-width, so it needs its own entry rather than being
-- derivable from one.
--
-- The liquid badge is short on purpose: it carries one name and a charge count, and
-- it is the fourth thing in a column that already reaches ~480px up a 720px viewport.
-- If a fifth ever wants in, something here has to come out.
Dock.INDEX_SIZE = 72
Dock.LIQUID_SIZE = UDim2.fromOffset(Dock.METER_SIZE.X.Offset, 48)
Dock.LIQUID_BOTTOM = Dock.INDEX_BOTTOM + Dock.INDEX_SIZE + Dock.GAP

-- The dock's total reserved height with no card open. IndexController still biases
-- its own anchor upward by half of this so it lands in the space the dock does not
-- cover; StationController deliberately does NOT any more (see its header — its
-- panel is centered on the screen itself now, and clears the dock on its own).
Dock.RESERVE = Dock.STATUS_BOTTOM + Dock.STATUS_HEIGHT

-- RIGHT ABOVE THE HOTBAR, on request. Its bottom edge sits one GAP above the bag-count
-- line (which is itself one GAP above the hotbar), so the whole hotbar cluster stays
-- visible underneath and the widget drops as low as it possibly can without covering
-- it.
--
-- This is a deliberate reversal of the old "clear the entire dock" placement
-- (RESERVE + GAP). The widget now overlays the instrument band's vertical space — but
-- that band is the meter / cash / index column, which is LEFT-anchored, and
-- HAULPANEL_RIGHT below puts this hard right. Anchored off the hotbar rather than a
-- screen fraction for the same reason everything else here is: a fraction that looked
-- right at 1080p collided with the dock on shorter viewports.
--
-- HAULPANEL_LIFT THEN RAISES IT OFF THAT BASELINE, on request. Flush on the bag-count
-- line put the widget's whole mass down in the corner with the dock, where it read as
-- one more instrument in the tray rather than as the thing you are currently doing.
-- Still an offset from the hotbar cluster rather than a fresh number, so a change to
-- any band below it carries the widget with it. 70 is one dock GAP short of clearing
-- the instrument band entirely: the widget's foot stays inside the band it is already
-- allowed to overlay, so this buys height without opening a new collision.
Dock.HAULPANEL_LIFT = 70
Dock.HAULPANEL_BOTTOM = Dock.BAGCOUNT_BOTTOM + Dock.BAGCOUNT_HEIGHT + Dock.GAP + Dock.HAULPANEL_LIFT

-- AND AS FAR RIGHT AS IT GOES WITHOUT TOUCHING THE SCOPE, which is what gets it off
-- the surfacing item. It used to be centred, which put a 240px-wide stack straight over
-- the character and the thing climbing out of the soil in front of them.
--
-- RIGHT RATHER THAN LEFT because the two bottom corners are not the same size: the
-- scope is SCOPE_DIAL (180) wide against the meter column's METER_SIZE.X (280), so
-- going right leaves 100px more room to get clear of centre. Expressed as the scope's
-- own footprint plus a gap rather than a tuned offset, which is what makes it hold at
-- every viewport width instead of at the one it was eyeballed on: the widget's right
-- edge lands exactly one INSTRUMENT_GAP left of the scope, so the two share the
-- HAULPANEL_BOTTOM / SCOPE_BOTTOM baseline and can never overlap each other.
--
-- HAULPANEL_INSET THEN PULLS IT BACK IN OFF THAT EDGE, on request: hard right plus
-- hard low parked it in the corner of the screen. This is deliberately a SMALL step,
-- because the reason the widget is off-centre at all has not changed and every px of
-- inset is a px closer to the item climbing out of the soil. It leaves the widget's
-- right edge four INSTRUMENT_GAPs clear of the scope instead of one.
--
-- Its LEFT edge then clears screen centre by ~296px at 1920 and ~36 at 1400, and
-- reaches back over centre below that — against a character only ~70px wide on
-- screen, so ~1400 is where the dodge stops being comfortable (it was ~1050 when the
-- widget was 320 wide and hard right).
--
-- THE COST OF THE 380px WIDTH AND THE INSET IS PAID ON SMALL VIEWPORTS, and it is
-- worth stating plainly rather than discovering. The free band between the meter
-- column and the widget's right edge is (width - 304 - 284) px; below ~970 that is
-- narrower than the widget, so it starts tucking behind the meter as well (~92px at
-- 800). Nothing breaks — the meter is DisplayOrder 100 against DetectorHud's 60 and
-- stays readable on top — but the widget stops dodging the item it is hauling. That
-- is the honest floor for a fixed-size widget on a viewport that small; the fix if it
-- ever matters is a narrower widget under some width, not a different anchor.
Dock.HAULPANEL_INSET = 60
Dock.HAULPANEL_RIGHT = Dock.ROW_SIDE_MARGIN + Dock.SCOPE_DIAL + Dock.INSTRUMENT_GAP + Dock.HAULPANEL_INSET

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
}

function UIKit.label(parent: Instance, props: LabelProps): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = props.name or "Label"
	label.Size = props.size
	label.Position = props.position or UDim2.fromOffset(0, 0)
	label.AnchorPoint = props.anchorPoint or Vector2.zero
	label.BackgroundTransparency = 1
	label.Font = props.font or UIKit.Font.body
	label.TextSize = props.textSize
	label.TextColor3 = props.color or UIKit.C.text
	label.TextXAlignment = props.xAlign or Enum.TextXAlignment.Left
	label.TextYAlignment = props.yAlign or Enum.TextYAlignment.Center
	label.TextWrapped = props.wrapped == true
	label.TextStrokeTransparency = if props.strokeTransparency ~= nil then props.strokeTransparency else 0.6
	label.Text = props.text or ""
	label.ZIndex = props.zIndex or 1
	label.Visible = if props.visible ~= nil then props.visible else true
	label.Parent = parent
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
	button.Font = props.font or UIKit.Font.body
	button.TextSize = props.textSize
	button.TextColor3 = props.color or UIKit.C.text
	button.Text = props.text or ""
	button.ZIndex = props.zIndex or 1
	button.Visible = if props.visible ~= nil then props.visible else true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = props.cornerRadius or UIKit.Radius.button
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = props.strokeColor or UIKit.C.stroke
	stroke.Thickness = props.strokeThickness or UIKit.Stroke.normal
	stroke.Parent = button

	return button, stroke
end

return UIKit
