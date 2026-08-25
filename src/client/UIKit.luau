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
	button = UDim.new(0, 14), -- dig button, station action / shop buttons
	slot = UDim.new(0, 12), -- hotbar slots
	pill = UDim.new(1, 0), -- fully round — scope dial and its rings
}

UIKit.Stroke = {
	thin = 2, -- unselected hotbar slot, secondary rings
	normal = 3, -- panels, buttons, dig button, station panel
	thick = 4, -- banner
	selected = 5, -- selected hotbar slot
}

-- ── The dock ─────────────────────────────────────────────────────────────────────
-- One horizontal instrument band — [METER | DIG BUTTON] — with the status line above
-- it, bag count below it, hotbar at the screen edge, the radar scope and the index
-- button stacked in the bottom-right corner, and the detail card floating above all
-- of it when a slot is selected:
--
--     ┌───────────────────────────────────────┐  <- Detail card (only if selected)
--     │              Status line       [INDEX] │
--     │    [METER]   [DIG BUTTON]      ( SCOPE)│  <- band 144px; scope is NOT in it
--     │              Bag count                  │
--     │   [1][2][3][4][5][6][7][8][9]...        │  <- hotbar, screen edge
--     └───────────────────────────────────────┘
--
-- THE SCOPE IS IN THE CORNER, NOT IN THE BAND, AND THAT IS THE WHOLE POINT OF THIS
-- LAYOUT. It used to sit inside the instrument band, to the dig button's right, where
-- being the tallest thing in the row (180 vs the meter's 144) pushed INSTRUMENT_HEIGHT
-- and therefore RESERVE up for everything else. It is now anchored to the bottom-right
-- corner on its own, sharing only the INSTRUMENT_BOTTOM baseline with the meter
-- opposite it, so `SCOPE_DIAL` is deliberately ABSENT from INSTRUMENT_HEIGHT below.
-- Put it back in that max() and the centred station panel loses 36px of headroom for
-- a widget that is no longer in the row.
--
-- `DIAL_LEFT_OFFSET` is gone for the same reason: the scope is corner-anchored now,
-- so it is not positioned relative to the dig button any more.
--
-- ONE WIDE BAND, NOT STACKED ROWS. Meter and dig button sit side by side inside one
-- INSTRUMENT_HEIGHT-tall band rather than stacking vertically, which would cost
-- roughly 200px on its own. That choice is the entire reason "bigger and centered"
-- does not also mean "covers the ground you are digging" — see RESERVE below, which
-- is the dock's total reserved height with no card open.
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
Dock.DIGBUTTON_SIZE = UDim2.fromOffset(260, 60) -- was 230x48
Dock.SCOPE_DIAL = 180 -- was DetectorController.DIAL_SIZE 150

Dock.STATUS_HEIGHT = 24
Dock.CARD_SIZE = UDim2.fromOffset(400, 136) -- was 330x116

-- Derived. Every "-178 hand-tuned against another file" number becomes a read of one
-- of these instead.
Dock.INSTRUMENT_HEIGHT = math.max(Dock.METER_SIZE.Y.Offset, Dock.DIGBUTTON_SIZE.Y.Offset)

Dock.HOTBAR_BOTTOM = Dock.MARGIN_BOTTOM
Dock.BAGCOUNT_BOTTOM = Dock.HOTBAR_BOTTOM + Dock.HOTBAR_HEIGHT + Dock.GAP
Dock.INSTRUMENT_BOTTOM = Dock.BAGCOUNT_BOTTOM + Dock.BAGCOUNT_HEIGHT + Dock.GAP
Dock.STATUS_BOTTOM = Dock.INSTRUMENT_BOTTOM + Dock.INSTRUMENT_HEIGHT + Dock.GAP
Dock.CARD_BOTTOM = Dock.STATUS_BOTTOM + Dock.STATUS_HEIGHT + Dock.GAP

-- The bottom-right stack, bottom-up: scope on the meter's baseline, index above it.
-- INDEX_BOTTOM is derived from SCOPE_DIAL rather than typed, so IndexController never
-- has to know how big the scope is — resize the dial and the button moves with it.
-- This is the same "no file hardcodes another file's layout" rule the whole dock
-- exists to enforce; it is exactly the class of bug the old `-178` was.
Dock.SCOPE_BOTTOM = Dock.INSTRUMENT_BOTTOM
Dock.INDEX_BOTTOM = Dock.SCOPE_BOTTOM + Dock.SCOPE_DIAL + Dock.GAP

-- The dock's total reserved height with no card open. IndexController still biases
-- its own anchor upward by half of this so it lands in the space the dock does not
-- cover; StationController deliberately does NOT any more (see its header — its
-- panel is centered on the screen itself now, and clears the dock on its own).
Dock.RESERVE = Dock.STATUS_BOTTOM + Dock.STATUS_HEIGHT

-- The dig button sits dead-center on X as the primary touch/click target. The meter
-- lives on its own at the bottom-left screen edge (see HudController), so it needs no
-- same-row offset from the button — and with the radar scope gone, nothing sits to
-- the button's right at all, which is why `DIAL_LEFT_OFFSET` no longer exists.

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
