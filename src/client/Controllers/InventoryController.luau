--[[
	InventoryController.lua — the hotbar. What you are carrying, along the bottom.

	WHAT THE SLOTS SAY, AND WHAT THEY DELIBERATELY DO NOT.
	A slot shows the ITEM: a clear name with a rarity-coloured border. The obvious
	temptation is to hang the whole decay apparatus off every slot — a draining fuse
	bar, a condition tint, the value — and it is the wrong call. Ten slots each
	running their own countdown is ten things moving in the corner of your eye while
	you are trying to read the ground, and the eye stops being able to find any of them.

	PRESSING A NUMBER PICKS THE ITEM UP. That is the whole verb now. It fires HoldInput
	and ToolService welds the thing into your off hand, which is what the tub checks
	before it will wash anything.

	THERE WAS A DETAIL CARD AND IT IS GONE, along with roughly a third of this file.
	Selecting a slot used to open a panel listing the item's condition, its remaining
	clock, its patch count and its pedestal rate. It was accurate and nobody needed it:
	you are holding the object, you can see it, and the answer to "what do I do with
	this" is now a prompt on a tub rather than a number on a card.

	The card is also why this file used to run a per-frame decay PREDICTION — `drift`,
	a scratch item, and a per-uid monotonic floor so a correction could never push the
	countdown upward. All of it existed to make one label tick smoothly, and all of it
	went with the label. The server still owns the clock; nothing here second-guesses
	it any more. The only per-frame work left is the bomb cooldown shade and an
	Anomaly's cycling colour, and each one disconnects when it has nothing to do.

	SLOT COUNT IS `capacity`, NOT THE NUMBER OF ITEMS. Empty slots are the point —
	they are how a player sees the headroom an aura upgrade bought them, and PLAN §3.4
	makes capacity one of the six tracks. A hotbar that only draws what you own hides
	the entire upgrade.

	THE HOTBAR STOPS AT TEN, THE BAG DOES NOT. A Containment Nimbus plus the level bonus
	carries 50+ items, and one row of fifty slots is unreadable at any width. So the
	row holds slots 1-10 (keys 1-9 and 0), and once capacity passes ten a BAG tile
	joins the end of it. ` (or tapping the tile) opens the bag panel: every slot, the
	hotbar's ten on top and the rest of the backpack under them. Clicking any of them
	picks it up exactly like its number key would. Empty slots still draw in the
	panel, for the same headroom reason as above.

	G DROPS THE HELD CLEAN NUKE AS A BOMB (Services/BombService; or the DROP button
	just right of the hotbar; Rare or better asks "are you sure?" first). Hovering
	a slot (or holding it, on touch) pops the bomb card over it:
	stars, damage, radius, fuse and cooldown, out of Shared/Bombing -- the same
	function the server detonates with. While the drop cooldown runs, every clean nuke
	slot wears a draining shade and the seconds left.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Crates = require(Shared.Config.Crates)
local Bombing = require(Shared.Bombing)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)
local ItemArt = require(script.Parent.Parent.ItemArt)
local Dock = UIKit.Dock

local Inventory = {}

-- Same fields UIKit.C already carries, aliased so every COLOR.xxx read below keeps
-- working unchanged.
local COLOR = UIKit.C

-- Slots shrink as the row fills so ten slots plus the bag tile fit one row. Below the
-- floor the name is unreadable anyway, so the row is allowed to run wider instead.
local SLOT_MAX = 64
local SLOT_MIN = 48
local SLOT_GAP = 6
local BORDER_PADDING = 3
local SLOT_FILL = Color3.fromHex("090C10")
local SLOT_SELECTED = Color3.fromHex("18221C")
local SLOT_BORDER = Color3.fromHex("505B66")
-- A held item's rarity border: thick enough to read the colour at a glance, thicker
-- still on the selected slot. Empty slots keep the thin grey 1.5.
local RARITY_STROKE = 2.5
local RARITY_STROKE_SELECTED = 3.5

-- The hotbar's length, and exactly the number row: 1-9 then 0. Everything past it
-- lives in the bag panel.
local HOTBAR_SLOTS = 10
local KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}
local BAG_KEY = Enum.KeyCode.Backquote
local BOMB_KEY = Enum.KeyCode.G

-- The bomb card over a hovered slot (Shared/Bombing's stats).
local CARD_WIDTH = 210
local CARD_HEIGHT = 182
local CARD_PAD = 12
local CARD_ROW = 20
local STAR_GOLD = Color3.fromHex("FFD34D")
local COOL_SHADE = Color3.fromHex("000000")
-- The "+$X/s" tag over the nuke in your own hands (only you see it).
local HELD_ITEM_NAME = "HeldItem" -- ToolService's name for whatever is in your hands
local RATE_TAG_LIFT = 1.2 -- studs above the held model's bounding box
local RATE_TAG_SIZE = UDim2.fromOffset(200, 34)
-- Dropping a nuke this rare or better asks "are you sure?" first.
local CONFIRM_FROM = Rarity.DEFS.Rare.order
local CONFIRM_WIDTH = 340
-- The DROP NUKE button right of the hotbar.
local DROP_WIDTH = 168
local DROP_HEIGHT = 50
local DROP_GAP = 14
local DROP_IDLE = Color3.fromHex("2A2F35")
local CONFIRM_HEIGHT = 176

-- The bag panel's grid. BAG_COLS matches HOTBAR_SLOTS so the panel's top row IS the
-- hotbar, slot for slot; the backpack grid under it wraps at the same width and
-- scrolls past BAG_VISIBLE_ROWS.
local BAG_COLS = HOTBAR_SLOTS
-- Same size as a full-width hotbar slot, so a name wraps the same way in both.
local BAG_CELL = SLOT_MAX
local BAG_GAP = 6
local BAG_PAD = 16
local BAG_HEADER = 46
local BAG_CAPTION = 20
local BAG_SECTION_GAP = 12
local BAG_VISIBLE_ROWS = 4

-- The Notice popup over the hotbar: pops in, holds, fades. The group is wider than
-- any message so the pill (auto-sized to its text) never clips.
-- The slot's kg readout.
local KG_GOLD = Color3.fromHex("FFC83D")

local NOTICE_WIDTH = 640
local NOTICE_HEIGHT = 50
local NOTICE_HOLD = 1.6
local NOTICE_IN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local NOTICE_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local state = {
	capacity = 0,
	items = {} :: { any },
}

local ui = {}
local slots: { any } = {} -- the hotbar row, index 1..HOTBAR_SLOTS
local bagCells: { any } = {} -- the bag panel, index 1..capacity
local selected: string? = nil -- uid, NOT an index: the bag reorders when you sell
local bagOpen = false
local holdRemote: any = nil
local noticeToken = 0
local standPrompts: { [ProximityPrompt]: boolean } = {} -- exhibit stand prompts seen so far
local bombRemote: any = nil
local bombReadyAt = 0 -- Workspace:GetServerTimeNow() the next drop is allowed
local bombCooldown = 0 -- the full length of the running cooldown, for the shade
local coolConnection: RBXScriptConnection? = nil
local cardSlot: any = nil -- the slot the bomb card is showing for
local confirmUid: string? = nil -- the Rare+ nuke the "are you sure?" is asking about
-- Assigned below, once itemByUid exists; the slots' hover handlers call through it.
local showCard: (slot: any?) -> () = function() end

--- Is this bag entry something G can drop? Clean nukes only (Shared/Bombing).
local function droppable(item: any): boolean
	return Bombing.canDrop(item, item ~= nil and item.clean == true)
end

local function bombSecondsLeft(): number
	return math.max(0, bombReadyAt - Workspace:GetServerTimeNow())
end

local function rarityColor(name: string?): Color3
	local def = if name then Rarity.DEFS[name] else nil
	return if def then def.color else COLOR.dim
end

local function keyText(index: number): string
	if index < HOTBAR_SLOTS then
		return tostring(index)
	elseif index == HOTBAR_SLOTS then
		return "0"
	end
	return ""
end

local function hasBag(): boolean
	return state.capacity > HOTBAR_SLOTS
end

--- "$2.00/s" up to "$1.2M/s" -- the Nukes panel's ladder (NukesController.formatRate).
local function formatRate(perSecond: number): string
	if perSecond >= 1_000_000_000_000 then
		return string.format("$%.1fT/s", perSecond / 1_000_000_000_000)
	elseif perSecond >= 1_000_000_000 then
		return string.format("$%.1fB/s", perSecond / 1_000_000_000)
	elseif perSecond >= 1_000_000 then
		return string.format("$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 1000 then
		return string.format("$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("$%.1f/s", perSecond)
	end
	return string.format("$%.2f/s", perSecond)
end

local function itemColour(item: any): Color3
	return if item.crateId then Color3.fromHex(Crates.get(item.crateId).color) else rarityColor(item.rarity)
end

--- The rarity an item's colour comes from, or nil for a crate (which wears its own).
local function itemRarity(item: any): string?
	return if item.crateId then nil else item.rarity
end

-- ANOMALY CYCLES. Every rarity-coloured border and name here goes through `tint`; an
-- Anomaly's is registered with the property it sits on, and one RenderStepped walks
-- the spectrum through them (Rarity.anomalyHue), in step with every other Anomaly
-- surface. It connects only while something is registered. A strong table, not a weak
-- one: Roblox can collect an Instance's wrapper while the Instance lives, and a weak
-- key would silently drop it. Anything repainted in another colour unregisters.
local cycling: { [Instance]: string } = {}
local cycleConnection: RBXScriptConnection? = nil

local function stepCycling()
	local hue = Rarity.anomalyHue(os.clock() / Rarity.ANOMALY_CYCLE)
	for target, prop in cycling do
		if target.Parent == nil then
			cycling[target] = nil
		else
			local painted: any = target
			painted[prop] = hue
		end
	end
	if next(cycling) == nil and cycleConnection then
		cycleConnection:Disconnect()
		cycleConnection = nil
	end
end

local function tint(target: Instance, prop: string, colour: Color3, rarity: string?)
	local painted: any = target
	painted[prop] = colour
	if rarity == "Anomaly" then
		cycling[target] = prop
		if cycleConnection == nil then
			cycleConnection = RunService.RenderStepped:Connect(stepCycling)
		end
	else
		cycling[target] = nil
	end
end

-- ── Build ───────────────────────────────────────────────────────────

local function makeSlot(parent: Instance, index: number, onClick: () -> ())
	local slot = Instance.new("TextButton")
	slot.Name = `Slot{index}`
	slot.AutoButtonColor = false
	slot.BackgroundColor3 = SLOT_FILL
	slot.BackgroundTransparency = 0.05
	slot.BorderSizePixel = 0
	slot.Text = ""
	slot.LayoutOrder = index
	slot.Size = UDim2.fromOffset(SLOT_MAX, SLOT_MAX)
	slot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = SLOT_BORDER
	stroke.Thickness = 1.5
	stroke.Parent = slot

	-- A bright, compact key hint; blank past the number row.
	local key = UIKit.label(slot, {
		name = "Key",
		position = UDim2.fromOffset(7, 4),
		size = UDim2.fromOffset(18, 16),
		font = UIKit.Font.title,
		textSize = 12,
		color = Color3.fromHex("BBC5D0"),
		strokeTransparency = 1,
		text = keyText(index),
	})

	-- The item's own model instead of its name: a name read twice (the label and its
	-- outline copy) at hotbar size was noise, and the art says rarity and kind at a glance.
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.new(0.5, 0, 0.5, -6)
	art.Size = UDim2.new(1, -8, 1, -8)
	art.ZIndex = 1
	art.Parent = slot
	local viewport = ItemArt.newViewport(art)

	-- The name over the lower half of the model. `shadow = false`: UIKit's shadow is a
	-- sibling copy that never hears a Text change, which is what drew the name twice.
	local name = UIKit.label(slot, {
		name = "ItemName",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -15),
		size = UDim2.new(1, -8, 0, 14),
		font = UIKit.Font.title,
		textSize = 12,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
		yAlign = Enum.TextYAlignment.Bottom,
		shadow = false,
	})
	name.TextScaled = true
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local nameSize = Instance.new("UITextSizeConstraint")
	nameSize.MinTextSize = 8
	nameSize.MaxTextSize = 12
	nameSize.Parent = name

	-- Its kg, bottom right, in gold.
	local kg = UIKit.label(slot, {
		name = "Weight",
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -5, 1, -3),
		size = UDim2.new(1, -10, 0, 14),
		font = UIKit.Font.title,
		textSize = 12,
		color = KG_GOLD,
		shadow = false,
		xAlign = Enum.TextXAlignment.Right,
		yAlign = Enum.TextYAlignment.Bottom,
	})
	-- In front of the model, outline and all.
	for _, node in { kg, name, table.unpack(kg:GetDescendants()) } do
		if node:IsA("GuiObject") then
			node.ZIndex += 5
		end
	end

	-- The bomb cooldown: a shade draining down off the slot, and the seconds left.
	local cool = Instance.new("Frame")
	cool.Name = "Cooldown"
	cool.AnchorPoint = Vector2.new(0, 1)
	cool.Position = UDim2.fromScale(0, 1)
	cool.Size = UDim2.fromScale(1, 1)
	cool.BackgroundColor3 = COOL_SHADE
	cool.BackgroundTransparency = 0.45
	cool.BorderSizePixel = 0
	cool.Visible = false
	cool.ZIndex = 10
	cool.Parent = slot
	local coolCorner = Instance.new("UICorner")
	coolCorner.CornerRadius = UDim.new(0, 7)
	coolCorner.Parent = cool
	local coolText = UIKit.label(slot, {
		name = "CooldownText",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(1, 0, 0, 20),
		font = UIKit.Font.title,
		textSize = 16,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
	coolText.Visible = false
	coolText.ZIndex = 11

	slot.MouseButton1Click:Connect(onClick)

	local entry = {
		button = slot,
		stroke = stroke,
		key = key,
		viewport = viewport,
		name = name,
		kg = kg,
		cool = cool,
		coolText = coolText,
		uid = nil :: string?,
	}
	slot.MouseEnter:Connect(function()
		showCard(entry)
	end)
	slot.MouseLeave:Connect(function()
		if cardSlot == entry then
			showCard(nil)
		end
	end)
	return entry
end

--- The last tile on the hotbar once capacity passes ten: opens the bag panel, and
--- says how many of your items are in there rather than on the row.
local function buildBagTile(row: Frame)
	local tile = Instance.new("TextButton")
	tile.Name = "BagTile"
	tile.AutoButtonColor = false
	tile.BackgroundColor3 = SLOT_FILL
	tile.BackgroundTransparency = 0.05
	tile.BorderSizePixel = 0
	tile.Text = ""
	tile.LayoutOrder = HOTBAR_SLOTS + 1
	tile.Size = UDim2.fromOffset(SLOT_MAX, SLOT_MAX)
	tile.Visible = false
	tile.Parent = row

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = tile

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = SLOT_BORDER
	stroke.Thickness = 1.5
	stroke.Parent = tile

	-- No ` key hint here or on the panel, on request: players are expected to know
	-- the key. The panel's X closes it for anyone who doesn't.

	UIKit.label(tile, {
		name = "Title",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(1, -6, 0, 16),
		font = UIKit.Font.title,
		textSize = 14,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
		strokeTransparency = 1,
		text = "BAG",
	})

	local count = UIKit.label(tile, {
		name = "Count",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -5),
		size = UDim2.new(1, -6, 0, 14),
		font = UIKit.Font.title,
		textSize = 12,
		color = COLOR.amber,
		xAlign = Enum.TextXAlignment.Center,
		strokeTransparency = 1,
	})

	tile.MouseButton1Click:Connect(function()
		Inventory.setBagOpen(not bagOpen)
	end)

	ui.bagTile = tile
	ui.bagTileStroke = stroke
	ui.bagTileCount = count
end

--- The DROP button: its own control, not a slot -- a red pill parked just right of
--- the hotbar (placeDropButton keeps it there as the row grows and shrinks). Drops
--- the held clean nuke as a bomb, same as G. Always shown so players find it; dark
--- until a clean nuke is in your hands, and it counts the cooldown down while one runs.
local function buildDropButton(canvas: Frame)
	local button = UIKit.button(canvas, {
		name = "DropBomb",
		anchorPoint = Vector2.new(0, 0.5),
		size = UDim2.fromOffset(DROP_WIDTH, DROP_HEIGHT),
		text = "DROP NUKE",
		font = UIKit.Font.title,
		textSize = 22,
		color = COLOR.text,
		fillColor = COLOR.red,
		fillTransparency = 0,
		strokeThickness = 3,
		cornerRadius = UDim.new(0.5, 0),
		shadow = false,
	})
	button.AutoButtonColor = false
	button.Visible = false
	button.ClipsDescendants = false

	-- The key, as a little keycap hanging off the pill's top-left; touch has no keys.
	local cap = UIKit.panel(button, {
		name = "Keycap",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromOffset(8, 4),
		size = UDim2.fromOffset(22, 22),
		color = Color3.fromHex("1A1F24"),
		transparency = 0,
		strokeColor = COLOR.outline,
		strokeThickness = 2,
		cornerRadius = UDim.new(0, 6),
		zIndex = 3,
	})
	cap.Visible = not UIKit.isTouch()
	UIKit.label(cap, {
		name = "Key",
		size = UDim2.fromScale(1, 1),
		font = UIKit.Font.title,
		textSize = 13,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		zIndex = 4,
		text = "G",
	})

	button.MouseButton1Click:Connect(function()
		Inventory.dropBomb()
	end)

	ui.dropButton = button
end

--- The Notice popup: a red-edged pill just above the vitals bars over the hotbar. A CanvasGroup so the
--- whole thing fades as one -- UIKit's text outlines ignore TextTransparency.
local function buildNotice(canvas: Frame)
	local group = Instance.new("CanvasGroup")
	group.Name = "Notice"
	group.AnchorPoint = Vector2.new(0.5, 1)
	group.Position = UDim2.new(0.5, 0, 1, -Dock.VITALS_CLEAR)
	group.Size = UDim2.fromOffset(NOTICE_WIDTH, NOTICE_HEIGHT)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Visible = false
	group.ZIndex = 20
	group.Parent = canvas

	local scale = Instance.new("UIScale")
	scale.Parent = group

	-- Inset from the group's edges so the stroke is not clipped by the CanvasGroup.
	local pill = UIKit.panel(group, {
		name = "Pill",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromOffset(0, NOTICE_HEIGHT - 8),
		color = COLOR.panel,
		transparency = 0.04,
		strokeColor = COLOR.red,
		strokeThickness = 2.5,
		cornerRadius = UDim.new(0.5, 0),
	})
	pill.AutomaticSize = Enum.AutomaticSize.X
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 22)
	padding.PaddingRight = UDim.new(0, 22)
	padding.Parent = pill

	local text = UIKit.label(pill, {
		name = "Text",
		size = UDim2.fromScale(0, 1),
		font = UIKit.Font.title,
		textSize = 22,
		color = COLOR.red,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
	text.AutomaticSize = Enum.AutomaticSize.X

	ui.notice = group
	ui.noticeScale = scale
	ui.noticeText = text
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Scale-based, not a fixed offset — a fixed 1080px row was fine bottom-centred
	-- alone, but the dock now packs the meter/button/dial band above it on the same
	-- centre line, and a narrower viewport needs the hotbar to shrink with it rather
	-- than run off the edges. UISizeConstraint caps it so an ultrawide monitor does
	-- not stretch it absurdly wide either.
	local canvas = UIKit.canvas(gui)
	ui.canvas = canvas

	-- A SWIPEABLE ROW ON TOUCH. Between the thumbstick and the jump button ten slots
	-- plus the bag tile can run past the row at SLOT_MIN, and a phone has no number
	-- keys to reach a clipped slot with, so there the row scrolls sideways instead of
	-- clipping (renderSlots left-aligns it once it overflows). Not on desktop: a
	-- ScrollingFrame under the cursor would eat the mouse wheel the camera zooms with.
	local row: Frame
	if UIKit.isTouch() then
		local scroller = Instance.new("ScrollingFrame")
		scroller.ScrollingDirection = Enum.ScrollingDirection.X
		scroller.AutomaticCanvasSize = Enum.AutomaticSize.X
		scroller.CanvasSize = UDim2.new()
		scroller.ScrollBarThickness = 0
		scroller.BorderSizePixel = 0
		scroller.ElasticBehavior = Enum.ElasticBehavior.Always
		row = scroller :: any
	else
		row = Instance.new("Frame")
	end
	row.Name = "Hotbar"
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -Dock.HOTBAR_BOTTOM)
	-- Clear of the touch controls on a phone, the same inset both sides so the row
	-- stays centred under the character. Re-read on every resize: the corner boxes are
	-- fixed in screen px, so their size in design px moves with the scale.
	UIKit.onScaleChanged(function()
		local margin = math.max(Dock.ROW_SIDE_MARGIN, UIKit.touchCorner().X + Dock.GAP)
		row.Size = UDim2.new(1, -2 * margin, 0, SLOT_MAX + 2 * BORDER_PADDING)
	end)
	row.BackgroundTransparency = 1
	-- Safety net, not a fix: slotWidth()'s shrink-to-fit clamp can run wider than its
	-- target on a narrow viewport (SLOT_MIN floors before the row runs out of room).
	-- This keeps it from spilling into whatever sits either side of the hotbar.
	row.ClipsDescendants = true
	row.Parent = canvas
	ui.row = row
	-- Keep the outer strokes inside the row's clipping bounds.
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, BORDER_PADDING)
	padding.PaddingBottom = UDim.new(0, BORDER_PADDING)
	padding.PaddingLeft = UDim.new(0, BORDER_PADDING)
	padding.PaddingRight = UDim.new(0, BORDER_PADDING)
	padding.Parent = row

	local rowConstraint = Instance.new("UISizeConstraint")
	rowConstraint.MaxSize = Vector2.new(Dock.ROW_MAX_WIDTH, math.huge)
	rowConstraint.Parent = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.Parent = row
	ui.layout = layout

	buildBagTile(row)
	buildDropButton(canvas)
	buildNotice(canvas)

	return gui
end

local function sectionCaption(parent: Instance, name: string, text: string, y: number): TextLabel
	return UIKit.label(parent, {
		name = name,
		position = UDim2.fromOffset(BAG_PAD, y),
		size = UDim2.new(1, -2 * BAG_PAD, 0, BAG_CAPTION - 4),
		font = UIKit.Font.title,
		textSize = 12,
		color = COLOR.dim,
		strokeTransparency = 1,
		outline = false,
		text = text,
	})
end

--- The bag panel. Its own ScreenGui so it can sit over the instrument band (the HUD
--- is 60-100) but under the Index/Shop panels (110), and still gets stowed with every
--- other LayerCollector when the wash bay hides the HUD.
local function buildBag(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "BagPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 108
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local canvas = UIKit.canvas(gui)
	local gridWidth = BAG_COLS * BAG_CELL + (BAG_COLS - 1) * BAG_GAP

	local panel = UIKit.panel(canvas, {
		name = "Bag",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, -30),
		size = UDim2.fromOffset(gridWidth + 2 * BAG_PAD, 200),
		color = COLOR.panel,
		transparency = 0.04,
		strokeThickness = 2,
	})
	ui.bagPanel = panel

	UIKit.label(panel, {
		name = "Title",
		position = UDim2.fromOffset(BAG_PAD, 0),
		size = UDim2.fromOffset(80, BAG_HEADER),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		text = "BAG",
	})
	ui.bagCount = UIKit.label(panel, {
		name = "Count",
		position = UDim2.fromOffset(BAG_PAD + 70, 0),
		size = UDim2.fromOffset(160, BAG_HEADER),
		font = UIKit.Font.title,
		textSize = 16,
		color = COLOR.dim,
		outline = false,
		strokeTransparency = 1,
	})

	-- A PLAIN "X", NOT U+2715 (see StationController's close badge).
	local close = UIKit.button(panel, {
		name = "Close",
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -BAG_PAD + 4, 0, BAG_HEADER / 2),
		size = UDim2.fromOffset(34, 34),
		text = "X",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		color = COLOR.text,
		fillColor = COLOR.empty,
		fillTransparency = 0,
		strokeColor = COLOR.stroke,
		strokeThickness = 2,
		cornerRadius = UDim.new(0, 9),
		outline = false,
		shadow = false,
	})
	close.MouseButton1Click:Connect(function()
		Inventory.setBagOpen(false)
	end)

	-- HOTBAR: the row, slot for slot, with its number keys.
	local hotbarTop = BAG_HEADER
	sectionCaption(panel, "HotbarCaption", "HOTBAR", hotbarTop)
	local hotbarRow = Instance.new("Frame")
	hotbarRow.Name = "HotbarRow"
	hotbarRow.BackgroundTransparency = 1
	hotbarRow.Position = UDim2.fromOffset(BAG_PAD, hotbarTop + BAG_CAPTION)
	hotbarRow.Size = UDim2.fromOffset(gridWidth, BAG_CELL)
	hotbarRow.Parent = panel
	local hotbarLayout = Instance.new("UIListLayout")
	hotbarLayout.FillDirection = Enum.FillDirection.Horizontal
	hotbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hotbarLayout.Padding = UDim.new(0, BAG_GAP)
	hotbarLayout.Parent = hotbarRow
	ui.bagHotbarRow = hotbarRow

	-- BACKPACK: slots 11 and up, wrapping at the hotbar's width and scrolling past
	-- BAG_VISIBLE_ROWS. The scroller is a few px wider than the grid so the cells'
	-- outer strokes are not clipped.
	local backpackTop = hotbarTop + BAG_CAPTION + BAG_CELL + BAG_SECTION_GAP
	ui.bagBackpackTop = backpackTop
	sectionCaption(panel, "BackpackCaption", "BACKPACK", backpackTop)
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Backpack"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.fromOffset(BAG_PAD - BORDER_PADDING, backpackTop + BAG_CAPTION - BORDER_PADDING)
	scroller.Size = UDim2.fromOffset(gridWidth + 2 * BORDER_PADDING + 6, BAG_CELL)
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.ScrollBarThickness = 4
	scroller.ScrollBarImageColor3 = COLOR.dim
	scroller.Parent = panel
	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingTop = UDim.new(0, BORDER_PADDING)
	scrollPadding.PaddingBottom = UDim.new(0, BORDER_PADDING)
	scrollPadding.PaddingLeft = UDim.new(0, BORDER_PADDING)
	scrollPadding.Parent = scroller
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(BAG_CELL, BAG_CELL)
	grid.CellPadding = UDim2.fromOffset(BAG_GAP, BAG_GAP)
	grid.FillDirectionMaxCells = BAG_COLS
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroller
	ui.bagScroller = scroller

	return gui
end

--- The bomb card and the touch DROP button. Their own ScreenGui, over the bag panel
--- (108), so a hovered bag cell's card is not drawn underneath it.
local function buildBombCard(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "BombCard"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 109
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local canvas = UIKit.canvas(gui)
	ui.cardCanvas = canvas

	local card, cardStroke = UIKit.panel(canvas, {
		name = "Card",
		anchorPoint = Vector2.new(0.5, 1),
		size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
		color = COLOR.panel,
		transparency = 0.04,
		strokeThickness = 2,
		cornerRadius = UDim.new(0, 12),
		visible = false,
	})
	ui.card = card
	ui.cardStroke = cardStroke

	ui.cardTitle = UIKit.label(card, {
		name = "Title",
		position = UDim2.fromOffset(CARD_PAD, 8),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 20),
		font = UIKit.Font.title,
		textSize = 16,
		shadow = false,
	})
	ui.cardTitle.TextTruncate = Enum.TextTruncate.AtEnd
	ui.cardStars = UIKit.label(card, {
		name = "Stars",
		position = UDim2.fromOffset(CARD_PAD, 28),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 18),
		font = UIKit.Font.title,
		textSize = 15,
		color = STAR_GOLD,
		shadow = false,
	})

	ui.cardRows = {}
	for index, caption in { "EARNS", "DAMAGE", "RADIUS", "FUSE", "COOLDOWN" } do
		local y = 52 + (index - 1) * CARD_ROW
		UIKit.label(card, {
			name = `{caption}Caption`,
			position = UDim2.fromOffset(CARD_PAD, y),
			size = UDim2.new(0.5, -CARD_PAD, 0, CARD_ROW),
			font = UIKit.Font.title,
			textSize = 13,
			color = COLOR.dim,
			outline = false,
			strokeTransparency = 1,
			text = caption,
		})
		ui.cardRows[index] = UIKit.label(card, {
			name = `{caption}Value`,
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, -CARD_PAD, 0, y),
			size = UDim2.new(0.5, -CARD_PAD, 0, CARD_ROW),
			font = UIKit.Font.title,
			textSize = 14,
			xAlign = Enum.TextXAlignment.Right,
			shadow = false,
		})
	end

	ui.cardFooter = UIKit.label(card, {
		name = "Footer",
		position = UDim2.fromOffset(CARD_PAD, CARD_HEIGHT - 28),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 18),
		font = UIKit.Font.title,
		textSize = 13,
		color = COLOR.amber,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})

	-- "ARE YOU SURE?" before a Rare-or-better nuke goes (CONFIRM_FROM). Centred over
	-- the screen; G or DROP again confirms, CANCEL (or holding something else) backs out.
	local confirm = UIKit.panel(canvas, {
		name = "Confirm",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, -40),
		size = UDim2.fromOffset(CONFIRM_WIDTH, CONFIRM_HEIGHT),
		color = COLOR.panel,
		transparency = 0.02,
		strokeThickness = 2.5,
		cornerRadius = UDim.new(0, 14),
		visible = false,
	})
	ui.confirm = confirm
	ui.confirmStroke = confirm:FindFirstChildOfClass("UIStroke")

	UIKit.label(confirm, {
		name = "Title",
		position = UDim2.fromOffset(0, 14),
		size = UDim2.new(1, 0, 0, 30),
		font = UIKit.Font.title,
		textSize = 26,
		color = COLOR.red,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
		text = "ARE YOU SURE?",
	})
	ui.confirmName = UIKit.label(confirm, {
		name = "ItemName",
		position = UDim2.fromOffset(CARD_PAD, 50),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 22),
		font = UIKit.Font.title,
		textSize = 19,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
	ui.confirmStars = UIKit.label(confirm, {
		name = "Stars",
		position = UDim2.fromOffset(CARD_PAD, 73),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 18),
		font = UIKit.Font.title,
		textSize = 16,
		color = STAR_GOLD,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
	UIKit.label(confirm, {
		name = "Warning",
		position = UDim2.fromOffset(CARD_PAD, 96),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 18),
		font = UIKit.Font.title,
		textSize = 14,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		text = "It blows up and is gone for good.",
	})

	local function confirmButton(name: string, text: string, x: number, fill: Color3): TextButton
		return UIKit.button(confirm, {
			name = name,
			anchorPoint = Vector2.new(0.5, 1),
			position = UDim2.new(x, 0, 1, -14),
			size = UDim2.fromOffset(140, 42),
			text = text,
			font = UIKit.Font.title,
			textSize = 20,
			color = COLOR.text,
			fillColor = fill,
			fillTransparency = 0,
			strokeThickness = 2,
			cornerRadius = UDim.new(0, 10),
			shadow = false,
		})
	end
	confirmButton("Cancel", "CANCEL", 0.28, COLOR.empty).MouseButton1Click:Connect(function()
		Inventory.cancelDrop()
	end)
	ui.confirmDrop = confirmButton("Drop", "DROP NUKE", 0.72, COLOR.red)
	ui.confirmDrop.MouseButton1Click:Connect(function()
		Inventory.dropBomb(true)
	end)

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

local function itemByUid(uid: string?): any
	if uid == nil then
		return nil
	end
	for _, item in state.items do
		if item.uid == uid then
			return item
		end
	end
	return nil
end

-- ── Bomb card + cooldown ────────────────────────────────────────────

--- Fill the card's footer: how to drop it, or how long until you can.
local function paintCardFooter(item: any)
	local footer = ui.cardFooter
	if not droppable(item) then
		footer.Text = "WASH IT TO USE AS A BOMB"
		footer.TextColor3 = COLOR.dim
		return
	end
	local left = bombSecondsLeft()
	if left > 0 then
		footer.Text = `READY IN {string.format("%.1f", left)}s`
		footer.TextColor3 = COLOR.amber
	else
		footer.Text = if UIKit.isTouch() then "TAP DROP NUKE" else "PRESS G TO DROP NUKE"
		footer.TextColor3 = COLOR.red
	end
end

--- Show the bomb card over `slot` (nil hides it). Nukes only; a crate has no card.
showCard = function(slot: any?)
	cardSlot = slot
	local card = ui.card
	if card == nil then
		return
	end
	local item = if slot then itemByUid(slot.uid) else nil
	if slot == nil or item == nil or item.crateId ~= nil or not slot.button.Visible then
		card.Visible = false
		return
	end

	local stats = Bombing.statsFor(item)
	local unknown = item.identified == false
	ui.cardTitle.Text = if unknown then "???" else item.name
	tint(ui.cardTitle, "TextColor3", rarityColor(item.rarity), item.rarity)
	tint(ui.cardStroke, "Color", rarityColor(item.rarity), item.rarity)
	ui.cardStars.Text = string.rep("\u{2605}", stats.stars)
	-- What it pays on a stand (CarryService's undamped `perSecond`): nil while it is
	-- still crusted (worth "???" like its name) or Slagged (a stand won't take it).
	local perSecond = item.perSecond
	if type(perSecond) == "number" then
		ui.cardRows[1].Text = formatRate(perSecond)
		ui.cardRows[1].TextColor3 = COLOR.green
	else
		ui.cardRows[1].Text = if unknown then "???" else "NOTHING"
		ui.cardRows[1].TextColor3 = COLOR.dim
	end
	ui.cardRows[2].Text = tostring(stats.damage)
	ui.cardRows[3].Text = `{stats.radius} studs`
	ui.cardRows[4].Text = `{stats.fuse}s`
	ui.cardRows[5].Text = `{stats.cooldown}s`
	paintCardFooter(item)

	-- Over the slot: its screen position, back into the card canvas's design pixels.
	local canvas = ui.cardCanvas
	local scale = UIKit.canvasScale(canvas)
	local button = slot.button
	local top = (button.AbsolutePosition - canvas.AbsolutePosition) / scale
	local width = button.AbsoluteSize.X / scale
	local x = math.clamp(top.X + width / 2, CARD_WIDTH / 2, canvas.AbsoluteSize.X / scale - CARD_WIDTH / 2)
	card.Position = UDim2.fromOffset(x, top.Y - 8)
	card.Visible = true
end

--- The DROP button: red while a clean nuke is in your hands and ready, dark
--- otherwise, and the seconds left while the cooldown runs.
local function paintDropButton(left: number)
	local button = ui.dropButton
	button.Visible = math.min(state.capacity, HOTBAR_SLOTS) > 0
	if not button.Visible then
		return
	end
	local ready = droppable(itemByUid(selected))
	local cooling = left > 0
	local lit = ready and not cooling
	button.Text = if cooling then string.format("%.1f", left) else "DROP NUKE"
	button.BackgroundColor3 = if lit then COLOR.red else DROP_IDLE
	button.TextColor3 = if lit then COLOR.text elseif cooling then COLOR.amber else COLOR.dim
end

--- Shade every clean nuke slot for the running cooldown; drops the Heartbeat once done.
local function paintCooldowns()
	local left = bombSecondsLeft()
	local through = if bombCooldown > 0 then math.clamp(left / bombCooldown, 0, 1) else 0
	paintDropButton(left)
	for _, list in { slots, bagCells } do
		for _, slot in list do
			local item = itemByUid(slot.uid)
			local cooling = left > 0 and droppable(item)
			slot.cool.Visible = cooling
			slot.coolText.Visible = cooling
			if cooling then
				slot.cool.Size = UDim2.fromScale(1, through)
				slot.coolText.Text = string.format("%.1f", left)
			end
		end
	end
	if cardSlot and ui.card.Visible then
		paintCardFooter(itemByUid(cardSlot.uid))
	end
	if left <= 0 and coolConnection then
		coolConnection:Disconnect()
		coolConnection = nil
	end
end

local function startCooldown(readyAt: number, cooldown: number)
	bombReadyAt = readyAt
	bombCooldown = math.max(cooldown, 0.1)
	if coolConnection == nil then
		coolConnection = RunService.Heartbeat:Connect(paintCooldowns)
	end
	paintCooldowns()
end

--- Put the "are you sure?" away without dropping anything.
function Inventory.cancelDrop()
	confirmUid = nil
	ui.confirm.Visible = false
end

--- Drop the held clean nuke as a bomb (G, or the DROP button). A Rare-or-better nuke
--- asks "are you sure?" first; `confirmed` is that dialog's DROP (or G pressed again
--- while it is up, for the same nuke). The server re-checks everything
--- (Services/BombService); this only saves a round trip for the obvious no.
function Inventory.dropBomb(confirmed: boolean?)
	local held = itemByUid(selected)
	if held == nil or not droppable(held) then
		Inventory.cancelDrop()
		Inventory.notice("hold a clean nuke to drop it")
		return
	end
	if bombSecondsLeft() > 0 then
		Inventory.cancelDrop()
		Inventory.notice("bomb still cooling down")
		return
	end

	local def = Rarity.DEFS[held.rarity]
	local precious = def ~= nil and def.order >= CONFIRM_FROM
	local agreed = confirmed == true or (confirmUid == held.uid and ui.confirm.Visible)
	if precious and not agreed then
		confirmUid = held.uid
		ui.confirmName.Text = held.name
		tint(ui.confirmName, "TextColor3", rarityColor(held.rarity), held.rarity)
		tint(ui.confirmStroke, "Color", rarityColor(held.rarity), held.rarity)
		ui.confirmStars.Text = `{string.rep("\u{2605}", Bombing.statsFor(held).stars)}  {string.upper(held.rarity)}`
		ui.confirm.Visible = true
		return
	end

	Inventory.cancelDrop()
	if bombRemote then
		bombRemote:FireServer()
	end
end

-- ── Stand prompt verb ───────────────────────────────────────────────

--- An exhibit stand's prompt, as THIS player should read it. The server can only
--- label a stand by what is on it (Place/Take, the same for everyone), so the
--- per-player half lives here: at an occupied stand, holding a nuke swaps it with the
--- one on display (ExhibitService.interact), so the prompt says so. A held crate is
--- refused there, so it keeps "Take".
local function standVerb(prompt: ProximityPrompt): string
	if prompt:GetAttribute("Occupied") ~= true then
		return "Place"
	end
	local held = itemByUid(selected)
	return if held ~= nil and held.crateId == nil then "Swap" else "Take"
end

--- A local ActionText write. The server's own writes replicate over it whenever the
--- stand fills or empties, which is why the ActionText listener below re-applies it.
local function relabelStand(prompt: ProximityPrompt)
	local verb = standVerb(prompt)
	if prompt.ActionText ~= verb then
		prompt.ActionText = verb
	end
end

local function relabelStands()
	for prompt in standPrompts do
		relabelStand(prompt)
	end
end

local function adoptStand(prompt: ProximityPrompt)
	if standPrompts[prompt] or prompt:GetAttribute("ExhibitStand") ~= true then
		return
	end
	standPrompts[prompt] = true
	local connections = {
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			relabelStand(prompt)
		end),
		prompt:GetAttributeChangedSignal("Occupied"):Connect(function()
			relabelStand(prompt)
		end),
	}
	prompt.Destroying:Connect(function()
		standPrompts[prompt] = nil
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	relabelStand(prompt)
end

--- How many tiles the hotbar row draws: up to ten slots, plus the bag tile.
local function rowCells(): number
	return math.min(state.capacity, HOTBAR_SLOTS) + (if hasBag() then 1 else 0)
end

--- Slot width for the current row. Shrinks toward SLOT_MIN as the row fills so ten
--- slots and the bag tile still land on one row.
---
--- READS THE ROW'S LIVE AbsoluteSize NOW, not a compile-time target — the row is
--- Scale-based (see build()), so its actual pixel width depends on the viewport.
--- AbsoluteSize can read 0 for one frame before the GUI's first layout pass
--- resolves; the fallback below is just "use the default until it does."
local function slotWidth(): number
	local cells = rowCells()
	if cells <= 0 then
		return SLOT_MAX
	end
	-- Screen pixels in, design pixels out: the row is on a UIKit canvas, so AbsoluteSize
	-- already carries the HUD scale, while the slot sizes this feeds are Offsets on that
	-- same canvas. Skip the divide and a scaled-up screen fits too few slots per row.
	local available = ui.row.AbsoluteSize.X / UIKit.canvasScale(ui.canvas)
	if available <= 0 then
		return SLOT_MAX
	end
	local fit = (available - 2 * BORDER_PADDING - SLOT_GAP * (cells - 1)) / cells
	return math.clamp(math.floor(fit), SLOT_MIN, SLOT_MAX)
end

--- Paints one slot (hotbar or bag cell) for bag index `index`.
local function paintSlot(slot: any, index: number)
	slot.key.Text = keyText(index)

	local item = state.items[index]
	slot.uid = if item then item.uid else nil

	if item == nil then
		ItemArt.clear(slot.viewport)
		slot.name.Text = ""
		slot.kg.Text = ""
		slot.button.BackgroundColor3 = SLOT_FILL
		slot.button.BackgroundTransparency = 0.05
		tint(slot.stroke, "Color", SLOT_BORDER)
		slot.stroke.Thickness = 1.5
		return
	end

	-- An unidentified find draws as its slag lump (ItemArt), with no name under it.
	slot.name.Text = if item.identified == false then "" else item.name
	ItemArt.paint(slot.viewport, item, 1)
	slot.kg.Text = if type(item.weight) == "number" then UIKit.formatKg(item.weight) else ""
	slot.button.BackgroundColor3 = if item.uid == selected then SLOT_SELECTED else SLOT_FILL
	slot.button.BackgroundTransparency = 0.05
	tint(slot.stroke, "Color", itemColour(item), itemRarity(item))
	slot.stroke.Thickness = if item.uid == selected then RARITY_STROKE_SELECTED else RARITY_STROKE
end

local function renderBagTile()
	local tile = ui.bagTile
	tile.Visible = hasBag()
	if not tile.Visible then
		return
	end
	tile.Size = UDim2.fromOffset(slotWidth(), slotWidth())

	local overflow = math.max(0, #state.items - HOTBAR_SLOTS)
	ui.bagTileCount.Text = if overflow > 0 then `+{overflow}` else `{#state.items}/{state.capacity}`
	ui.bagTileCount.TextColor3 = if overflow > 0 then COLOR.amber else COLOR.dim

	-- Holding something that lives in the bag: the tile wears its colour, so the
	-- selection is never invisible just because its slot is off the row.
	local heldIndex = nil
	for index, item in state.items do
		if item.uid == selected then
			heldIndex = index
			break
		end
	end
	if heldIndex and heldIndex > HOTBAR_SLOTS then
		tile.BackgroundColor3 = SLOT_SELECTED
		local held = state.items[heldIndex]
		tint(ui.bagTileStroke, "Color", itemColour(held), itemRarity(held))
		ui.bagTileStroke.Thickness = 3
	else
		tile.BackgroundColor3 = if bagOpen then SLOT_SELECTED else SLOT_FILL
		tint(ui.bagTileStroke, "Color", if bagOpen then COLOR.text else SLOT_BORDER)
		ui.bagTileStroke.Thickness = if bagOpen then 2 else 1.5
	end
end

local function renderBag()
	if not bagOpen then
		return
	end
	ui.bagCount.Text = `{#state.items}/{state.capacity}`

	local capacity = state.capacity
	for index = 1, math.max(#bagCells, capacity) do
		if bagCells[index] == nil and index <= capacity then
			local parent = if index <= HOTBAR_SLOTS then ui.bagHotbarRow else ui.bagScroller
			bagCells[index] = makeSlot(parent, index, function()
				Inventory.select(index)
				-- Picking something up is "grab and go": put the bag away. Putting the
				-- held item back down leaves it open.
				if selected ~= nil then
					Inventory.setBagOpen(false)
				end
			end)
			bagCells[index].button.Size = UDim2.fromOffset(BAG_CELL, BAG_CELL)
		end
		local cell = bagCells[index]
		if cell == nil then
			continue
		end
		cell.button.Visible = index <= capacity
		if index <= capacity then
			paintSlot(cell, index)
		else
			cell.uid = nil
		end
	end

	local backpackSlots = math.max(0, capacity - HOTBAR_SLOTS)
	local rows = math.ceil(backpackSlots / BAG_COLS)
	local visibleRows = math.min(rows, BAG_VISIBLE_ROWS)
	local gridHeight = visibleRows * BAG_CELL + math.max(0, visibleRows - 1) * BAG_GAP
	ui.bagScroller.Size = UDim2.fromOffset(ui.bagScroller.Size.X.Offset, gridHeight + 2 * BORDER_PADDING)
	-- Only show a scrollbar when there is something to scroll to.
	ui.bagScroller.ScrollBarThickness = if rows > BAG_VISIBLE_ROWS then 4 else 0
	ui.bagPanel.Size = UDim2.fromOffset(
		ui.bagPanel.Size.X.Offset,
		ui.bagBackpackTop + BAG_CAPTION + gridHeight + BAG_PAD
	)
end

--- Park the DROP button just right of the hotbar's last tile. The row centres its
--- tiles, so their right edge is the canvas centre plus half their width; on a
--- touch row that overflows (packed from the left, see renderSlots) it is the row's
--- own right edge.
local function placeDropButton(width: number)
	local cells = rowCells()
	local needed = cells * (width + SLOT_GAP) - SLOT_GAP + 2 * BORDER_PADDING
	local scale = UIKit.canvasScale(ui.canvas)
	local rowLeft = (ui.row.AbsolutePosition.X - ui.canvas.AbsolutePosition.X) / scale
	local rowWidth = ui.row.AbsoluteSize.X / scale
	local right = rowLeft + rowWidth / 2 + needed / 2
	if needed > rowWidth then
		right = rowLeft + rowWidth
	end
	local canvasWidth = ui.canvas.AbsoluteSize.X / scale
	local x = math.min(right + DROP_GAP, canvasWidth - DROP_WIDTH - Dock.GAP)
	local y = -(Dock.HOTBAR_BOTTOM + BORDER_PADDING + width / 2)
	ui.dropButton.Position = UDim2.new(0, x, 1, y)
end

local function renderSlots()
	local width = slotWidth()
	local shown = math.min(state.capacity, HOTBAR_SLOTS)
	-- Centred content wider than a ScrollingFrame spills off BOTH ends, and the left
	-- spill cannot be scrolled to, so the touch row packs from the left once it
	-- overflows (see build()).
	if ui.row:IsA("ScrollingFrame") then
		local available = ui.row.AbsoluteSize.X / UIKit.canvasScale(ui.canvas)
		local cells = rowCells()
		local needed = cells * (width + SLOT_GAP) - SLOT_GAP + 2 * BORDER_PADDING
		ui.layout.HorizontalAlignment = if needed > available + 0.5
			then Enum.HorizontalAlignment.Left
			else Enum.HorizontalAlignment.Center
	end

	for index = 1, HOTBAR_SLOTS do
		if slots[index] == nil and index <= shown then
			slots[index] = makeSlot(ui.row, index, function()
				Inventory.select(index)
			end)
		end

		local slot = slots[index]
		if slot == nil then
			continue
		end

		if index > shown then
			slot.button.Visible = false
			slot.uid = nil
			continue
		end

		slot.button.Visible = true
		slot.button.Size = UDim2.fromOffset(width, width)
		paintSlot(slot, index)
	end

	renderBagTile()
	renderBag()
	-- What you are holding just changed (or might have): a stand's Take/Swap follows.
	relabelStands()

	-- The bomb bits follow the bag: a new slot needs its cooldown shade, the DROP button
	-- follows what is in your hands, and on touch (no hover) the card shows for it.
	placeDropButton(width)
	paintCooldowns()
	-- Put down or swapped out the nuke the "are you sure?" was about: it no longer applies.
	if confirmUid ~= nil and confirmUid ~= selected then
		Inventory.cancelDrop()
	end
	if UIKit.isTouch() then
		local heldSlot = nil
		for _, slot in slots do
			if selected ~= nil and slot.uid == selected and slot.button.Visible then
				heldSlot = slot
			end
		end
		showCard(heldSlot)
	elseif cardSlot then
		showCard(cardSlot)
	end
end

-- ── Notice popup ────────────────────────────────────────────────────

--- Pop a refusal up over the hotbar ("inventory full"). A new one restarts the
--- clock rather than queueing behind the last.
function Inventory.notice(message: string)
	-- A full bag gets its thunk here. Other refusals stay silent at this layer: a
	-- purchase short of cash already buzzes (SfxService's "denied" from the till).
	if string.find(string.lower(message), "full", 1, true) then
		Sfx.play("bagFull")
	end
	noticeToken += 1
	local token = noticeToken
	local group = ui.notice
	ui.noticeText.Text = string.upper(message)
	group.Visible = true
	group.GroupTransparency = 0
	ui.noticeScale.Scale = 0.6
	TweenService:Create(ui.noticeScale, NOTICE_IN, { Scale = 1 }):Play()

	task.delay(NOTICE_HOLD, function()
		if token ~= noticeToken then
			return
		end
		local fade = TweenService:Create(group, NOTICE_OUT, { GroupTransparency = 1 })
		fade.Completed:Connect(function()
			if token == noticeToken then
				group.Visible = false
			end
		end)
		fade:Play()
	end)
end

-- ── Bag panel ───────────────────────────────────────────────────────

function Inventory.setBagOpen(open: boolean)
	open = open and hasBag()
	if open == bagOpen then
		return
	end
	bagOpen = open
	ui.bagGui.Enabled = open
	if open then
		ui.bagScroller.CanvasPosition = Vector2.zero
	else
		-- A hovered bag cell never hears MouseLeave once its panel is switched off.
		showCard(nil)
	end
	renderSlots()
end

-- ── Selection ───────────────────────────────────────────────────────

--- SELECTING IS NOW ALSO HOLDING, and that is the whole reason the tub can refuse
--- you. The hotbar has always been keyed by uid rather than by index (see `selected`
--- above), so the same keypress that opens the detail card can tell the server which
--- item is in your hands with no new input handling and no second concept for the
--- player to learn: the thing the card is describing is the thing you are holding.
---
--- Fires even when the selection clears, because empty-handed is a state the tub
--- checks for, not the absence of one.
function Inventory.select(index: number)
	local item = state.items[index]
	-- selene: allow(if_same_then_else)
	-- The empty-slot and same-key-again cases both clear the selection, but they are
	-- distinct player intents and read better kept apart than merged behind an `or`.
	if item == nil then
		selected = nil
	elseif selected == item.uid then
		selected = nil -- pressing the same key again puts the card away, and puts it down
	else
		selected = item.uid
	end

	if holdRemote then
		holdRemote:FireServer(selected)
	end

	renderSlots()
end

-- ── Held rate tag ───────────────────────────────────────────────────

--- "+$X/s" over the nuke in YOUR hands. The BillboardGui lives in your PlayerGui and
--- is adorned to the held model, so nobody else ever sees it. Hidden for crates, for
--- a crusted find (its worth is "???" until washed) and for anything a stand won't take.
local function refreshRateTag()
	local tag = ui.rateTag
	if tag == nil then
		return
	end
	local character = Players.LocalPlayer.Character
	local held = if character then character:FindFirstChild(HELD_ITEM_NAME) else nil
	local uid = if held then held:GetAttribute("Uid") else nil
	local item = if type(uid) == "string" then itemByUid(uid) else nil
	local anchor = if held and held:IsA("Model")
		then held.PrimaryPart or held:FindFirstChildWhichIsA("BasePart", true)
		else nil
	if item == nil or item.crateId ~= nil or type(item.perSecond) ~= "number" or anchor == nil then
		tag.Enabled = false
		tag.Adornee = nil
		return
	end

	-- Over the top of the model, not its pivot: a tall nuke would swallow the tag.
	local box, size = (held :: Model):GetBoundingBox()
	local top = box.Position.Y + size.Y / 2
	tag.Adornee = anchor
	tag.StudsOffsetWorldSpace = Vector3.new(0, top - anchor.Position.Y + RATE_TAG_LIFT, 0)
	ui.rateTagText.Text = `+{formatRate(item.perSecond)}`
	tag.Enabled = true
end

local function buildRateTag(playerGui: Instance)
	local tag = Instance.new("BillboardGui")
	tag.Name = "HeldRateTag"
	tag.Size = RATE_TAG_SIZE
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.ResetOnSpawn = false
	tag.Enabled = false
	tag.Parent = playerGui
	ui.rateTag = tag
	ui.rateTagText = UIKit.label(tag, {
		name = "Rate",
		size = UDim2.fromScale(1, 1),
		font = UIKit.Font.hero,
		textSize = 26,
		color = COLOR.green,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
end

local function watchHeld(character: Model)
	refreshRateTag()
	character.ChildAdded:Connect(function(child)
		if child.Name == HELD_ITEM_NAME then
			-- StreamingEnabled: parts/attributes can trail the model by a frame.
			task.defer(refreshRateTag)
			child:GetAttributeChangedSignal("Uid"):Connect(refreshRateTag)
			child.DescendantAdded:Connect(function(d)
				if d:IsA("BasePart") and not ui.rateTag.Enabled then
					refreshRateTag()
				end
			end)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child.Name == HELD_ITEM_NAME then
			refreshRateTag()
		end
	end)
end

-- ── Lifecycle ───────────────────────────────────────────────────────

function Inventory.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = build()
	gui.Parent = playerGui
	ui.bagGui = buildBag()
	ui.bagGui.Parent = playerGui
	ui.cardGui = buildBombCard()
	ui.cardGui.Parent = playerGui
	buildRateTag(playerGui)

	-- ROBLOX'S OWN BACKPACK HAS TO GO, AND NOT JUST BECAUSE IT IS REDUNDANT.
	-- CoreGui binds the number row to its hotbar slots (and ` to its inventory).
	-- ToolService welds models to the character instead of using Tool instances, so
	-- that backpack is always empty and the keys currently fall through to us by luck
	-- — but the moment anything puts a real Tool in it, CoreGui consumes 1-9 first,
	-- `gameProcessedEvent` comes back true, and every slot key here silently stops
	-- working. Turning it off makes that impossible rather than unlikely, and removes
	-- an empty widget that competes with this one for the same corner of the screen.
	--
	-- pcall because SetCoreGuiEnabled throws if the CoreGui is not ready yet, and a
	-- hotbar that fails to build over a cosmetic call would be a bad trade.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	holdRemote = Net.get("HoldInput")
	bombRemote = Net.get("BombDrop")

	Net.get("Notice").OnClientEvent:Connect(function(message)
		Inventory.notice(tostring(message))
	end)

	-- The server's answer to a drop: the cooldown it started, or why it refused.
	Net.get("BombState").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if type(payload.notice) == "string" then
			Inventory.notice(payload.notice)
		elseif type(payload.readyAt) == "number" then
			startCooldown(payload.readyAt, tonumber(payload.cooldown) or 0)
		end
	end)

	-- Stand prompts are adopted as they come into range: only a shown prompt's label
	-- matters, and the plots' stands stream in and out with the player.
	ProximityPromptService.PromptShown:Connect(adoptStand)

	Net.get("CarryState").OnClientEvent:Connect(function(payload)
		state.capacity = payload.capacity or 0
		state.items = payload.items or {}

		-- SUPPLY CRATES (Config/Crates) share the bag's slots, after the nukes. They
		-- arrive on their own field so nothing else that reads `items` meets one; here
		-- they become slots like any other, named for the crate and bordered in its
		-- colour. Selecting one holds it, and holding it is what offers "Open".
		for _, entry in payload.crates or {} do
			if Crates.has(entry.crateId) then
				local crate = Crates.get(entry.crateId)
				table.insert(state.items, {
					uid = entry.uid,
					crateId = entry.crateId,
					name = crate.short,
					rarity = crate.tier,
					weight = crate.pullWeight,
				})
			end
		end

		-- A selection whose item just left the bag — sold, racked, slagged — must not
		-- keep a stale card on screen. Keyed by uid rather than index precisely so
		-- this is detectable at all: selling slot 2 shuffles everything after it.
		if itemByUid(selected) == nil then
			selected = nil
			-- The server clears its own heldUid when an item leaves the bag
			-- (CarryService's tick), so this is only keeping the two in step for the
			-- NEXT keypress -- it is not what unloads the hand.
		end

		-- An aura swap back under ten slots takes the bag tile away; take its panel too.
		if bagOpen and not hasBag() then
			Inventory.setBagOpen(false)
		end

		renderSlots()
		-- The index multiplier (or a merge) can move the held nuke's rate.
		refreshRateTag()
	end)

	if player.Character then
		watchHeld(player.Character)
	end
	player.CharacterAdded:Connect(watchHeld)

	-- New: the row is Scale-based now, so a viewport resize (window resize, phone
	-- rotation) changes how many pixels slotWidth() has to divide up.
	ui.row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		renderSlots()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == BAG_KEY then
			Inventory.setBagOpen(not bagOpen)
			return
		end
		if input.KeyCode == BOMB_KEY then
			Inventory.dropBomb()
			return
		end
		local index = KEYS[input.KeyCode]
		if index then
			Inventory.select(index)
		end
	end)

	renderSlots()
end

return Inventory
