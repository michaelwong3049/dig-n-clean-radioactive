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

	DRAG A SLOT ONTO ANOTHER TO SWAP THEM (onto an empty one to move it), across the
	hotbar and the bag panel alike. Mouse: press and pull past DRAG_THRESHOLD. Touch:
	hold for TOUCH_HOLD first, so a quick swipe still scrolls the row. Items keep their
	slot from then on -- selling slot 2 leaves a gap rather than shuffling 3-10 down a
	key -- and a new find takes the first empty slot. The arrangement is saved
	(Net.SlotOrder -> data.slotOrder) and adopted again from the first CarryState.
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
local Merge = require(Shared.Config.Merge)
local Bombing = require(Shared.Bombing)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local StarLine = require(script.Parent.Parent.StarLine)
local Sfx = require(script.Parent.Parent.Sfx)
local Prefs = require(script.Parent.Parent.Prefs)
local Studded = require(script.Parent.Parent.Studded)
local ItemArt = require(script.Parent.Parent.ItemArt)
local Dock = UIKit.Dock

local Inventory = {}

-- UIKit.C's fields with the house slate (UIKit.House) in place of its olive panel
-- greens, so the hotbar and bag panel match the other panels.
local House = UIKit.House
local COLOR = table.clone(UIKit.C)
COLOR.panel = House.panel
COLOR.empty = House.card
COLOR.stroke = House.ink
COLOR.text = House.white
COLOR.dim = House.dim

-- Slots shrink as the row fills so ten slots plus the bag tile fit one row. Below the
-- floor the name is unreadable anyway, so the row is allowed to run wider instead.
local SLOT_MAX = 64
local SLOT_MIN = 48
local SLOT_GAP = 6
local BORDER_PADDING = 3
-- See-through black, so the world shows through every slot (hotbar, bag, BAG tile).
local SLOT_FILL = Color3.fromHex("000000")
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
-- Drag-to-swap: how far (screen px) a mouse press travels before it is a drag rather
-- than a click, and how long a touch holds still before it picks the slot up.
local DRAG_THRESHOLD = 8
local TOUCH_HOLD = 0.35
-- A held finger may wander this far (screen px) before it counts as a swipe instead.
local TOUCH_SLOP = 12
local DRAG_TARGET = Color3.fromRGB(255, 255, 255)
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
local RATE_TAG_SIZE = UDim2.fromOffset(200, 56) -- star line (22) over the rate (34)
-- Dropping a nuke this rare or better asks "are you sure?" first.
local CONFIRM_FROM = Rarity.DEFS.Rare.order
local CONFIRM_WIDTH = 340
-- The DROP NUKE button right of the hotbar.
local DROP_WIDTH = 168
local DROP_HEIGHT = 50
local DROP_GAP = 14
local DROP_IDLE = Color3.fromHex("2A2F35")
local CONFIRM_HEIGHT = 210 -- room for the "Don't show again" box under the buttons

-- The bag panel's grid. BAG_COLS matches HOTBAR_SLOTS so the panel's top row IS the
-- hotbar, slot for slot; the backpack grid under it wraps at the same width and
-- scrolls past BAG_VISIBLE_ROWS.
local BAG_COLS = HOTBAR_SLOTS
-- Same size as a full-width hotbar slot, so a name wraps the same way in both.
local BAG_CELL = SLOT_MAX
local BAG_GAP = 6
local BAG_PAD = 16
local BAG_HEADER = 56 -- title, filter pills, SORT, count, close
local BAG_ROW_GAP = 12 -- the hotbar row (top) to the backpack grid under it
local BAG_FOOTER = 28 -- the controls hint along the bottom
local BAG_VISIBLE_ROWS = 4
local SLOT_TRANSPARENCY = 0.45
-- The held item's slot is a touch more solid, so the selection still reads.
local SELECTED_TRANSPARENCY = 0.25
-- The bag's filter pills, left to right. A cell that doesn't match is shaded, not
-- hidden, so slots never jump around under the cursor (and drags still land).
local BAG_FILTERS = {
	{ id = "all", text = "ALL", width = 58 },
	{ id = "hearted", text = "HEARTED", width = 112 },
	{ id = "clean", text = "CLEAN", width = 72 },
	{ id = "dirty", text = "???", width = 54 },
}
local PILL_IDLE = Color3.fromHex("14181D")

-- HEARTED NUKES (Shared/Bag): right-click a slot, or double-tap it on touch. The
-- chip sits on the slot's top-right corner; the server refuses to sell, gift, merge,
-- furnace or bomb anything wearing one.
local HEART_RED = Color3.fromHex("FF4D6D")
local HEART_PINK = ColorSequence.new(Color3.fromHex("FF8FA3"), Color3.fromHex("FF4D6D"))
local HEART_CHIP = 20
local DOUBLE_TAP = 0.35 -- seconds between two taps on one slot that make a heart

-- The Notice popup over the hotbar: pops in, holds, fades. The group is wider than
-- any message so the pill (auto-sized to its text) never clips.
-- The slot's kg readout.
local KG_GOLD = Color3.fromHex("FFC83D")

local NOTICE_WIDTH = 820
local NOTICE_HEIGHT = 50
local NOTICE_HOLD = 1.6
local NOTICE_IN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local NOTICE_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local NOTICE_CHIP = 30
local NOTICE_FILL = Color3.fromRGB(22, 24, 28)
-- White text on a dark pill; the round chip on the left says what kind of notice it
-- is. Anything not "success" or "info" is a refusal.
local NOTICE_KINDS = {
	error = { color = Color3.fromRGB(229, 72, 77), glyph = "X" },
	success = { color = Color3.fromRGB(48, 164, 108), glyph = "\u{2713}" },
	info = { color = Color3.fromRGB(245, 165, 36), glyph = "i" },
}

local state = {
	-- How many slots to DRAW: the bag's size, or more when it holds more than that (a
	-- crate bought from the Shop always goes in, full bag or not). `limit` is the bag's
	-- real size, for the "6/4" counts.
	capacity = 0,
	limit = 0,
	items = {} :: { any },
	-- What sits in each slot, by index (sparse: nil is an empty slot). Built from
	-- `items` and `order` by layoutSlots; everything that asks "what is in slot N"
	-- reads this, never `items[N]`.
	slots = {} :: { [number]: any },
	-- The uid in each slot, "" for empty. nil until the first CarryState hands over
	-- the saved one; owned by this client after that.
	order = nil :: { string }?,
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
local slotOrderRemote: any = nil
local heartRemote: any = nil
local bagFilter = "all" -- one of BAG_FILTERS' ids
-- The last touch tap on a slot, for the double-tap heart: { entry, at, before }, where
-- `before` is what was held before that tap, so the pair can put it back.
local lastTap: any = nil
local bagCloseToken = 0 -- bumping it cancels a pending "picked up, close the bag"
-- Assigned below with the selection code; the slots' input handlers call through it.
local toggleHeart: (index: number, restore: boolean?, before: string?) -> () = function() end
-- The press that may become a drag: { entry, from, start, input, touch, active }.
local drag: any = nil
-- A drag that ends over its own slot still fires that slot's click; this eats it.
local suppressClickUntil = 0
-- Assigned below, once itemByUid exists; the slots' hover handlers call through it.
local showCard: (slot: any?) -> () = function() end
-- Assigned with the rest of the drag code; makeSlot's press handler calls through it.
local beginPress: (entry: any, input: InputObject) -> () = function() end

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

--- A heart drawn from frames (two round lobes on a square turned 45°), filling
--- `parent`. No glyph: Gotham has no reliable U+2665 (see the plain "X" on close).
local function heartIcon(parent: GuiObject, colour: Color3, zIndex: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = "HeartIcon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = zIndex
	holder.Parent = parent
	local function piece(name: string, x: number, y: number, size: number, round: boolean)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(x, y)
		frame.Size = UDim2.fromScale(size, size)
		frame.BackgroundColor3 = colour
		frame.BorderSizePixel = 0
		frame.ZIndex = zIndex
		if round then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = frame
		else
			frame.Rotation = 45
		end
		frame.Parent = holder
	end
	piece("Point", 0.5, 0.6, 0.5, false)
	piece("Left", 0.323, 0.423, 0.5, true)
	piece("Right", 0.677, 0.423, 0.5, true)
	return holder
end

local function makeSlot(parent: Instance, index: number, onClick: () -> ())
	local slot = Instance.new("TextButton")
	slot.Name = `Slot{index}`
	slot.AutoButtonColor = false
	slot.BackgroundColor3 = SLOT_FILL
	slot.BackgroundTransparency = SLOT_TRANSPARENCY
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
		font = House.font,
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

	-- The name over the lower half of the model.
	local name = UIKit.label(slot, {
		name = "ItemName",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -15),
		size = UDim2.new(1, -8, 0, 14),
		font = House.font,
		textSize = 12,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
		yAlign = Enum.TextYAlignment.Bottom,
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
		font = House.font,
		textSize = 12,
		color = KG_GOLD,
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
		font = House.font,
		textSize = 16,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
	})
	coolText.Visible = false
	coolText.ZIndex = 11

	-- The bag's filter shade: over everything but the heart, so a hearted nuke
	-- still says so under HEARTED's opposite.
	local shade = Instance.new("Frame")
	shade.Name = "FilterShade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = COOL_SHADE
	shade.BackgroundTransparency = 0.3
	shade.BorderSizePixel = 0
	shade.Visible = false
	shade.ZIndex = 12
	shade.Parent = slot
	local shadeCorner = Instance.new("UICorner")
	shadeCorner.CornerRadius = UDim.new(0, 7)
	shadeCorner.Parent = shade

	-- The heart chip: a white disc with an inked rim, top-right, inside the slot so
	-- the hotbar row's scroller cannot clip it.
	local heart = Instance.new("Frame")
	heart.Name = "Heart"
	heart.AnchorPoint = Vector2.new(1, 0)
	heart.Position = UDim2.new(1, -2, 0, 2)
	heart.Size = UDim2.fromOffset(HEART_CHIP, HEART_CHIP)
	heart.BackgroundColor3 = House.white
	heart.BorderSizePixel = 0
	heart.Visible = false
	heart.ZIndex = 13
	heart.Parent = slot
	local heartCorner = Instance.new("UICorner")
	heartCorner.CornerRadius = UDim.new(0.5, 0)
	heartCorner.Parent = heart
	local heartRim = Instance.new("UIStroke")
	heartRim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	heartRim.Color = House.ink
	heartRim.Thickness = 2
	heartRim.Parent = heart
	local heartArt = heartIcon(heart, HEART_RED, 14)
	heartArt.AnchorPoint = Vector2.new(0.5, 0.5)
	heartArt.Position = UDim2.fromScale(0.5, 0.52)
	heartArt.Size = UDim2.fromScale(0.68, 0.68)
	local heartScale = Instance.new("UIScale")
	heartScale.Parent = heart

	local entry = {
		index = index,
		button = slot,
		stroke = stroke,
		key = key,
		viewport = viewport,
		name = name,
		kg = kg,
		cool = cool,
		coolText = coolText,
		shade = shade,
		heart = heart,
		heartScale = heartScale,
		inBag = false,
		touched = false,
		uid = nil :: string?,
	}

	-- RIGHT-CLICK HEARTS. On touch there is no right button, so two quick taps on the
	-- same slot do it instead (lastTap); the first tap still picks the nuke up, and
	-- the second puts back whatever was held before it.
	slot.MouseButton2Click:Connect(function()
		toggleHeart(entry.index)
	end)
	slot.MouseButton1Click:Connect(function()
		if os.clock() < suppressClickUntil then
			return
		end
		if entry.touched then
			local tap = lastTap
			if tap and tap.entry == entry and os.clock() - tap.at < DOUBLE_TAP then
				lastTap = nil
				toggleHeart(entry.index, true, tap.before)
				return
			end
			lastTap = { entry = entry, at = os.clock(), before = selected }
		end
		onClick()
	end)

	slot.InputBegan:Connect(function(input)
		-- Read by the click handler above, which fires after this for the same press.
		if input.UserInputType == Enum.UserInputType.Touch then
			entry.touched = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			entry.touched = false
		end
		beginPress(entry, input)
	end)
	slot.MouseEnter:Connect(function()
		if drag == nil or not drag.active then
			showCard(entry)
		end
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
	tile.BackgroundTransparency = SLOT_TRANSPARENCY
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
		font = House.font,
		textSize = 14,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
		strokeTransparency = 1,
		text = "Bag",
	})

	local count = UIKit.label(tile, {
		name = "Count",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -5),
		size = UDim2.new(1, -6, 0, 14),
		font = House.font,
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
		text = "Drop Nuke",
		font = House.font,
		textSize = 22,
		color = COLOR.text,
		fillColor = COLOR.red,
		fillTransparency = 0,
		strokeThickness = 3,
		cornerRadius = UDim.new(0.5, 0),
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
		font = House.font,
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

	local pill, pillStroke = UIKit.panel(group, {
		name = "Pill",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.fromOffset(0, NOTICE_HEIGHT - 8),
		color = NOTICE_FILL,
		transparency = 0.08,
		cornerRadius = UDim.new(0.5, 0),
	})
	pillStroke.Enabled = false
	pill.AutomaticSize = Enum.AutomaticSize.X
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 22)
	padding.Parent = pill
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 10)
	row.Parent = pill

	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.Size = UDim2.fromOffset(NOTICE_CHIP, NOTICE_CHIP)
	chip.BorderSizePixel = 0
	chip.LayoutOrder = 1
	chip.Parent = pill
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = chip

	local glyph = UIKit.label(chip, {
		name = "Glyph",
		size = UDim2.fromScale(1, 1),
		font = House.font,
		textSize = 18,
		color = Color3.new(1, 1, 1),
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
	})

	local text = UIKit.label(pill, {
		name = "Text",
		size = UDim2.fromScale(0, 1),
		font = House.font,
		textSize = 20,
		color = Color3.new(1, 1, 1),
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
	})
	text.AutomaticSize = Enum.AutomaticSize.X
	text.LayoutOrder = 2

	ui.notice = group
	ui.noticeScale = scale
	ui.noticeText = text
	ui.noticeChip = chip
	ui.noticeGlyph = glyph
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

--- A rounded inked pill for the bag's header row. `Studded.button` lays the small
--- studs over it; the caller paints it on/off (paintFilters).
local function bagPill(parent: Instance, name: string, text: string, width: number, x: number): TextButton
	local pill = Instance.new("TextButton")
	pill.Name = name
	pill.AutoButtonColor = false
	pill.AnchorPoint = Vector2.new(0, 0.5)
	pill.Position = UDim2.fromOffset(x, BAG_HEADER / 2)
	pill.Size = UDim2.fromOffset(width, 32)
	pill.BackgroundColor3 = PILL_IDLE
	pill.BorderSizePixel = 0
	pill.Font = House.font
	pill.TextSize = 14
	pill.TextColor3 = House.white
	pill.Text = text
	pill.ZIndex = 3
	pill.Parent = parent
	local outline = Instance.new("UIStroke")
	outline.Color = House.ink
	outline.Thickness = 1.5
	outline.Parent = pill
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 9)
	corner.Parent = pill
	Studded.border(pill, 2.5)
	Studded.button(pill, 9)
	return pill
end

--- The bag panel. Its own ScreenGui so it can sit over the instrument band (the HUD
--- is 60-100) but under the Index/Shop panels (110), and still gets stowed with every
--- other LayerCollector when the wash bay hides the HUD.
---
--- OPTION 2 OF THE 2026-10-07 MOCK-UPS: the dark studded backdrop the Shop wears, a
--- header of filter pills (ALL / HEARTED / CLEAN / ???) and a SORT button, then ONE
--- ten-wide grid whose top row is the hotbar (keys 1-0) and whose rows under it are
--- the backpack. Cells are see-through black so the studs show between the nukes.
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
		transparency = 0,
		strokeColor = House.ink,
		strokeThickness = 3,
		cornerRadius = UDim.new(0, 18),
	})
	Studded.darkPanel(panel, 18)
	ui.bagPanel = panel

	local title = UIKit.label(panel, {
		name = "Title",
		position = UDim2.fromOffset(BAG_PAD, 0),
		size = UDim2.fromOffset(64, BAG_HEADER),
		font = House.font,
		textSize = UIKit.TextSize.header,
		text = "BAG",
		zIndex = 3,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- FILTERS. Shade, never hide (BAG_FILTERS' note).
	ui.bagPills = {}
	local x = BAG_PAD + 70
	for _, filter in BAG_FILTERS do
		local pill = bagPill(panel, `Filter_{filter.id}`, filter.text, filter.width, x)
		pill.MouseButton1Click:Connect(function()
			Inventory.setBagFilter(filter.id)
		end)
		ui.bagPills[filter.id] = pill
		x += filter.width + 6
	end

	-- SORT: a one-shot rearrange of the backpack rows (hotbar untouched), hearted
	-- first, then rarity, then value. It moves the saved slots, so it sticks.
	local sort = bagPill(panel, "Sort", "SORT", 70, x + 10)
	Studded.fill(sort, Studded.GOLD)
	sort.MouseButton1Click:Connect(function()
		Inventory.sortBag()
	end)

	-- A PLAIN "X", NOT U+2715 (see StationController's close badge).
	local close = UIKit.button(panel, {
		name = "Close",
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -BAG_PAD + 4, 0, BAG_HEADER / 2),
		size = UDim2.fromOffset(34, 34),
		text = "X",
		font = House.font,
		textSize = UIKit.TextSize.header,
		color = House.white,
		fillColor = House.close,
		fillTransparency = 0,
		strokeColor = House.ink,
		strokeThickness = 3,
		cornerRadius = UDim.new(0, 9),
		outline = false,
	})
	close.ZIndex = 3
	close.MouseButton1Click:Connect(function()
		Inventory.setBagOpen(false)
	end)

	ui.bagCount = UIKit.label(panel, {
		name = "Count",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -BAG_PAD - 40, 0, 0),
		size = UDim2.fromOffset(80, BAG_HEADER),
		font = House.font,
		textSize = 16,
		color = House.dim,
		xAlign = Enum.TextXAlignment.Right,
		zIndex = 3,
	})

	-- HOTBAR: the grid's top row, slot for slot, with its number keys.
	local hotbarRow = Instance.new("Frame")
	hotbarRow.Name = "HotbarRow"
	hotbarRow.BackgroundTransparency = 1
	hotbarRow.Position = UDim2.fromOffset(BAG_PAD, BAG_HEADER)
	hotbarRow.Size = UDim2.fromOffset(gridWidth, BAG_CELL)
	hotbarRow.ZIndex = 3
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
	local backpackTop = BAG_HEADER + BAG_CELL + BAG_ROW_GAP
	ui.bagBackpackTop = backpackTop
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Backpack"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.fromOffset(BAG_PAD - BORDER_PADDING, backpackTop - BORDER_PADDING)
	scroller.Size = UDim2.fromOffset(gridWidth + 2 * BORDER_PADDING + 6, BAG_CELL)
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.ScrollBarThickness = 4
	scroller.ScrollBarImageColor3 = House.dim
	scroller.ZIndex = 3
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

	-- How to drive it, for whichever hands are on the device.
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	ui.bagHint = UIKit.label(panel, {
		name = "Hint",
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, BAG_PAD, 1, -6),
		size = UDim2.new(1, -2 * BAG_PAD, 0, BAG_FOOTER - 8),
		font = House.font,
		textSize = 12,
		color = House.dim,
		strokeTransparency = 1,
		outline = false,
		zIndex = 3,
		text = if touchOnly
			then "TAP: HOLD   |   DOUBLE-TAP: HEART   |   PRESS + DRAG: MOVE   |   HEARTED CAN'T BE SOLD OR GIFTED"
			else "CLICK: HOLD   |   RIGHT-CLICK: HEART   |   DRAG: MOVE   |   HEARTED CAN'T BE SOLD OR GIFTED",
	})

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
		font = House.font,
		textSize = 16,
	})
	ui.cardTitle.TextTruncate = Enum.TextTruncate.AtEnd
	ui.cardStars = UIKit.label(card, {
		name = "Stars",
		position = UDim2.fromOffset(CARD_PAD, 28),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 18),
		font = House.font,
		textSize = 15,
		color = STAR_GOLD,
	})

	ui.cardRows = {}
	for index, caption in { "EARNS", "DAMAGE", "RADIUS", "FUSE", "COOLDOWN" } do
		local y = 52 + (index - 1) * CARD_ROW
		UIKit.label(card, {
			name = `{caption}Caption`,
			position = UDim2.fromOffset(CARD_PAD, y),
			size = UDim2.new(0.5, -CARD_PAD, 0, CARD_ROW),
			font = House.font,
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
			font = House.font,
			textSize = 14,
			xAlign = Enum.TextXAlignment.Right,
		})
	end

	ui.cardFooter = UIKit.label(card, {
		name = "Footer",
		position = UDim2.fromOffset(CARD_PAD, CARD_HEIGHT - 28),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 18),
		font = House.font,
		textSize = 13,
		color = COLOR.amber,
		xAlign = Enum.TextXAlignment.Center,
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
		font = House.font,
		textSize = 26,
		color = COLOR.red,
		xAlign = Enum.TextXAlignment.Center,
		text = "ARE YOU SURE?",
	})
	ui.confirmName = UIKit.label(confirm, {
		name = "ItemName",
		position = UDim2.fromOffset(CARD_PAD, 50),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 22),
		font = House.font,
		textSize = 19,
		xAlign = Enum.TextXAlignment.Center,
	})
	ui.confirmStars = UIKit.label(confirm, {
		name = "Stars",
		position = UDim2.fromOffset(CARD_PAD, 73),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 18),
		font = House.font,
		textSize = 16,
		color = STAR_GOLD,
		xAlign = Enum.TextXAlignment.Center,
	})
	UIKit.label(confirm, {
		name = "Warning",
		position = UDim2.fromOffset(CARD_PAD, 96),
		size = UDim2.new(1, -2 * CARD_PAD, 0, 18),
		font = House.font,
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
			position = UDim2.new(x, 0, 1, -48),
			size = UDim2.fromOffset(140, 42),
			text = text,
			font = House.font,
			textSize = 20,
			color = COLOR.text,
			fillColor = fill,
			fillTransparency = 0,
			strokeThickness = 2,
			cornerRadius = UDim.new(0, 10),
		})
	end
	confirmButton("Cancel", "CANCEL", 0.28, COLOR.empty).MouseButton1Click:Connect(function()
		Inventory.cancelDrop()
	end)
	ui.confirmDrop = confirmButton("Drop", "Drop Nuke", 0.72, COLOR.red)
	ui.confirmDrop.MouseButton1Click:Connect(function()
		Inventory.dropBomb(true)
	end)

	-- "Don't show again": ticks a box; only DROP NUKE saves it (Prefs confirmDrop),
	-- so ticking then CANCEL changes nothing. Settings > Graphics turns it back on.
	local skip = UIKit.button(confirm, {
		name = "DontShow",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -12),
		size = UDim2.fromOffset(200, 24),
		text = "[  ]  Don't show again",
		font = House.font,
		textSize = 15,
		color = COLOR.dim,
		fillTransparency = 1,
		strokeThickness = 0,
	})
	ui.confirmSkip = skip
	skip.MouseButton1Click:Connect(function()
		ui.confirmSkipOn = not ui.confirmSkipOn
		skip.Text = (if ui.confirmSkipOn then "[x]  " else "[  ]  ") .. "Don't show again"
		skip.TextColor3 = if ui.confirmSkipOn then COLOR.text else COLOR.dim
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

--- Seat every item in a slot: first wherever `order` already has it (inside the bag's
--- capacity), then anything new into the first empty slots, in bag order. Rewrites
--- `order` to match, so a find keeps the slot it landed in and a sale leaves a gap.
local function layoutSlots()
	local byUid = {}
	for _, item in state.items do
		byUid[item.uid] = item
	end
	local slotsNow = {}
	local seated = {}
	for index, uid in state.order or {} do
		local item = byUid[uid]
		if index <= state.capacity and item and not seated[uid] then
			slotsNow[index] = item
			seated[uid] = true
		end
	end
	local nextFree = 1
	for _, item in state.items do
		if not seated[item.uid] then
			while slotsNow[nextFree] do
				nextFree += 1
			end
			slotsNow[nextFree] = item
			seated[item.uid] = true
		end
	end
	state.slots = slotsNow

	local order = {}
	for index = 1, state.capacity do
		local item = slotsNow[index]
		order[index] = if item then item.uid else ""
	end
	state.order = order
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

	-- The Bomber mastery's damage, published by MasteryService, so the card reads the
	-- hit BombService will land.
	local bomberMult = Players.LocalPlayer:GetAttribute("MasteryBombDamage")
	local stats = Bombing.statsFor(item, if type(bomberMult) == "number" then bomberMult else nil)
	local unknown = item.identified == false
	ui.cardTitle.Text = if unknown then "???" else item.name
	tint(ui.cardTitle, "TextColor3", rarityColor(item.rarity), item.rarity)
	tint(ui.cardStroke, "Color", rarityColor(item.rarity), item.rarity)
	-- Merge Reactor stars trail the rating in their own colour, as on the Nukes panel.
	StarLine.set(ui.cardStars, stats.stars, {
		trail = if unknown then 0 else Merge.levelOf(item),
		trailColor = Merge.COLOR,
	})
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
	button.Text = if cooling then string.format("%.1f", left) else "Drop Nuke"
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
	if held.hearted == true then
		Inventory.cancelDrop()
		Inventory.notice("that nuke is hearted \u{2014} unheart it to drop it")
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
	if agreed and ui.confirm.Visible and ui.confirmSkipOn then
		Prefs.set("confirmDrop", false)
	end
	if precious and not agreed and Prefs.get("confirmDrop") ~= false then
		confirmUid = held.uid
		ui.confirmName.Text = held.name
		tint(ui.confirmName, "TextColor3", rarityColor(held.rarity), held.rarity)
		tint(ui.confirmStroke, "Color", rarityColor(held.rarity), held.rarity)
		StarLine.set(ui.confirmStars, Bombing.statsFor(held).stars, { after = string.upper(held.rarity) })
		ui.confirmSkipOn = false
		ui.confirmSkip.Text = "[  ]  Don't show again"
		ui.confirmSkip.TextColor3 = COLOR.dim
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
--- Does this slot's contents pass the bag's filter pill? Empty slots only pass ALL.
local function matchesFilter(item: any): boolean
	if bagFilter == "all" then
		return true
	elseif item == nil then
		return false
	elseif bagFilter == "hearted" then
		return item.hearted == true
	elseif bagFilter == "clean" then
		return item.clean == true
	elseif bagFilter == "dirty" then
		return item.identified == false
	end
	return true
end

--- The pills: the chosen one lit (HEARTED in pink, the rest gold), the others idle.
--- HEARTED carries its count.
local function paintFilters()
	local hearted = 0
	for _, item in state.items do
		if item.hearted == true then
			hearted += 1
		end
	end
	for _, filter in BAG_FILTERS do
		local pill = ui.bagPills[filter.id]
		local on = bagFilter == filter.id
		local gradient = pill:FindFirstChild("Fill")
		if on then
			Studded.fill(pill, if filter.id == "hearted" then HEART_PINK else Studded.GOLD)
		else
			if gradient then
				gradient:Destroy()
			end
			pill.BackgroundColor3 = PILL_IDLE
		end
		pill.Text = if filter.id == "hearted" then `{filter.text} {hearted}` else filter.text
	end
end

local function paintSlot(slot: any, index: number)
	slot.key.Text = keyText(index)

	local item = state.slots[index]
	slot.uid = if item then item.uid else nil
	slot.heart.Visible = item ~= nil and item.hearted == true
	slot.shade.Visible = slot.inBag and not matchesFilter(item)

	if item == nil then
		ItemArt.clear(slot.viewport)
		slot.name.Text = ""
		slot.kg.Text = ""
		slot.button.BackgroundColor3 = SLOT_FILL
		slot.button.BackgroundTransparency = SLOT_TRANSPARENCY
		tint(slot.stroke, "Color", SLOT_BORDER)
		slot.stroke.Thickness = 1.5
		return
	end

	-- An unidentified find draws as its slag lump (ItemArt), with no name under it.
	slot.name.Text = if item.identified == false then "" else item.name
	ItemArt.paint(slot.viewport, item, 1)
	slot.kg.Text = if type(item.weight) == "number" then UIKit.formatKg(item.weight) else ""
	slot.button.BackgroundColor3 = if item.uid == selected then SLOT_SELECTED else SLOT_FILL
	slot.button.BackgroundTransparency = if item.uid == selected then SELECTED_TRANSPARENCY else SLOT_TRANSPARENCY
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

	-- Items past the hotbar, counted by slot: with gaps in the row that is not
	-- simply #items - 10.
	local overflow = 0
	for index, _ in state.slots do
		if index > HOTBAR_SLOTS then
			overflow += 1
		end
	end
	ui.bagTileCount.Text = if overflow > 0 then `+{overflow}` else `{#state.items}/{state.limit}`
	ui.bagTileCount.TextColor3 = if overflow > 0 then COLOR.amber else COLOR.dim

	-- Holding something that lives in the bag: the tile wears its colour, so the
	-- selection is never invisible just because its slot is off the row.
	local heldIndex = nil
	for index, item in state.slots do
		if item.uid == selected then
			heldIndex = index
			break
		end
	end
	if heldIndex and heldIndex > HOTBAR_SLOTS then
		tile.BackgroundColor3 = SLOT_SELECTED
		local held = state.slots[heldIndex]
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
	ui.bagCount.Text = `{#state.items}/{state.limit}`
	paintFilters()

	local capacity = state.capacity
	for index = 1, math.max(#bagCells, capacity) do
		if bagCells[index] == nil and index <= capacity then
			local parent = if index <= HOTBAR_SLOTS then ui.bagHotbarRow else ui.bagScroller
			local cell
			cell = makeSlot(parent, index, function()
				Inventory.select(index)
				-- Picking something up is "grab and go": put the bag away. Putting the
				-- held item back down leaves it open. On touch it waits out the
				-- double-tap window, so a second tap can heart instead (and cancel this).
				if selected ~= nil then
					if cell.touched then
						bagCloseToken += 1
						local token = bagCloseToken
						task.delay(DOUBLE_TAP, function()
							if token == bagCloseToken and selected ~= nil then
								Inventory.setBagOpen(false)
							end
						end)
					else
						Inventory.setBagOpen(false)
					end
				end
			end)
			cell.button.Size = UDim2.fromOffset(BAG_CELL, BAG_CELL)
			cell.inBag = true
			bagCells[index] = cell
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
		ui.bagBackpackTop + gridHeight + BORDER_PADDING + BAG_FOOTER
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

-- ── Drag to swap ────────────────────────────────────────────────────

--- An input's spot in the same space as AbsolutePosition. Both start under the
--- topbar whatever a gui's IgnoreGuiInset says, so no inset goes on here (adding it
--- put every hit-test a topbar's height low).
local function pointerOf(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

--- An AbsolutePosition-space point as an Offset inside the drag gui, which (being
--- IgnoreGuiInset) has its origin a topbar higher.
local function dragOffset(point: Vector2): UDim2
	local origin = ui.dragGui.AbsolutePosition
	return UDim2.fromOffset(point.X - origin.X, point.Y - origin.Y)
end

local function inside(gui: GuiObject, point: Vector2): boolean
	local min = gui.AbsolutePosition
	local max = min + gui.AbsoluteSize
	return point.X >= min.X and point.X <= max.X and point.Y >= min.Y and point.Y <= max.Y
end

--- The slot under `point`: the hotbar row, or (open) the bag panel. A bag cell
--- scrolled out of its scroller's window does not count.
local function slotAt(point: Vector2): any
	for _, entry in slots do
		if entry.button.Visible and inside(ui.row, point) and inside(entry.button, point) then
			return entry
		end
	end
	if bagOpen then
		for _, entry in bagCells do
			if entry.button.Visible and inside(entry.button, point) then
				local clipped = entry.index > HOTBAR_SLOTS and not inside(ui.bagScroller, point)
				if not clipped then
					return entry
				end
			end
		end
	end
	return nil
end

--- Swap slots `a` and `b` (either may be empty), redraw, and save the arrangement.
local function swapSlots(a: number, b: number)
	local order = state.order
	if order == nil or a == b or a > state.capacity or b > state.capacity then
		return
	end
	order[a], order[b] = order[b], order[a]
	layoutSlots()
	renderSlots()
	Sfx.play("click")
	if slotOrderRemote then
		slotOrderRemote:FireServer(state.order)
	end
end

local function setScrolling(enabled: boolean)
	for _, frame in { ui.row, ui.bagScroller } do
		if frame and frame:IsA("ScrollingFrame") then
			frame.ScrollingEnabled = enabled
		end
	end
end

local function moveGhost(point: Vector2)
	ui.dragGhost.Position = dragOffset(point - ui.dragGhost.AbsoluteSize / 2)
	local target = slotAt(point)
	local highlight = ui.dragTarget
	if target and target.index ~= drag.from then
		local button = target.button
		highlight.Size = UDim2.fromOffset(button.AbsoluteSize.X, button.AbsoluteSize.Y)
		highlight.Position = dragOffset(button.AbsolutePosition)
		highlight.Visible = true
	else
		highlight.Visible = false
	end
end

--- The press turns into a drag: lift a copy of the slot onto the cursor.
local function startDrag(point: Vector2)
	local item = state.slots[drag.from]
	if item == nil then
		drag = nil
		return
	end
	drag.active = true
	showCard(nil)
	setScrolling(false)

	local source = drag.entry.button
	local ghost = ui.dragGhost
	ghost.Size = UDim2.fromOffset(source.AbsoluteSize.X, source.AbsoluteSize.Y)
	tint(ui.dragGhostStroke, "Color", itemColour(item), itemRarity(item))
	ItemArt.paint(ui.dragGhostViewport, item, 1)
	ui.dragGui.Enabled = true
	source.BackgroundTransparency = 0.6
	moveGhost(point)
end

local function endDrag(point: Vector2?)
	local current = drag
	drag = nil
	if current == nil or not current.active then
		return
	end
	ui.dragGui.Enabled = false
	ui.dragTarget.Visible = false
	ItemArt.clear(ui.dragGhostViewport)
	setScrolling(true)
	-- Released over its own slot: MouseButton1Click is still on its way. Eat it.
	suppressClickUntil = os.clock() + 0.2
	local target = if point then slotAt(point) else nil
	if target and target.index ~= current.from then
		swapSlots(current.from, target.index)
	else
		renderSlots() -- puts the faded source slot back
	end
end

beginPress = function(entry: any, input: InputObject)
	local touch = input.UserInputType == Enum.UserInputType.Touch
	if not touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if drag ~= nil or state.slots[entry.index] == nil then
		return
	end
	local press = {
		entry = entry,
		from = entry.index,
		start = pointerOf(input),
		input = input,
		touch = touch,
		active = false,
	}
	drag = press
	if touch then
		-- A finger has no hover-then-press: it holds still to pick up, so a swipe
		-- along the row still scrolls it.
		task.delay(TOUCH_HOLD, function()
			if drag == press and not press.active then
				startDrag(press.start)
			end
		end)
	end
end

local function buildDragGui(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "SlotDrag"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Over the hotbar (60), the bag panel (108) and its card.
	gui.DisplayOrder = 115
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	-- Where it will land: a white ring over the target slot.
	local target = Instance.new("Frame")
	target.Name = "Target"
	target.BackgroundColor3 = DRAG_TARGET
	target.BackgroundTransparency = 0.85
	target.BorderSizePixel = 0
	target.Visible = false
	target.Parent = gui
	local targetCorner = Instance.new("UICorner")
	targetCorner.CornerRadius = UDim.new(0, 7)
	targetCorner.Parent = target
	local targetStroke = Instance.new("UIStroke")
	targetStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	targetStroke.Color = DRAG_TARGET
	targetStroke.Thickness = 3
	targetStroke.Parent = target
	ui.dragTarget = target

	-- The lifted item, under the cursor.
	local ghost = Instance.new("Frame")
	ghost.Name = "Ghost"
	ghost.BackgroundColor3 = SLOT_SELECTED
	ghost.BackgroundTransparency = 0.15
	ghost.BorderSizePixel = 0
	ghost.ZIndex = 2
	ghost.Parent = gui
	local ghostCorner = Instance.new("UICorner")
	ghostCorner.CornerRadius = UDim.new(0, 7)
	ghostCorner.Parent = ghost
	local ghostStroke = Instance.new("UIStroke")
	ghostStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ghostStroke.Thickness = RARITY_STROKE_SELECTED
	ghostStroke.Parent = ghost
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.new(1, -8, 1, -8)
	art.ZIndex = 3
	art.Parent = ghost
	ui.dragGhost = ghost
	ui.dragGhostStroke = ghostStroke
	ui.dragGhostViewport = ItemArt.newViewport(art)
	return gui
end

local function watchDrag()
	UserInputService.InputChanged:Connect(function(input)
		local press = drag
		if press == nil then
			return
		end
		local moved = if press.touch
			then input == press.input
			else input.UserInputType == Enum.UserInputType.MouseMovement
		if not moved then
			return
		end
		local point = pointerOf(input)
		if press.active then
			moveGhost(point)
		elseif press.touch then
			if (point - press.start).Magnitude > TOUCH_SLOP then
				drag = nil -- a swipe: the row scrolls, nothing is picked up
			end
		elseif (point - press.start).Magnitude > DRAG_THRESHOLD then
			startDrag(point)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local press = drag
		if press == nil then
			return
		end
		local released = if press.touch
			then input == press.input
			else input.UserInputType == Enum.UserInputType.MouseButton1
		if released then
			endDrag(pointerOf(input))
		end
	end)
	-- A drag left hanging when the window loses focus mid-press: put it back.
	UserInputService.WindowFocusReleased:Connect(function()
		endDrag(nil)
	end)
end

-- ── Notice popup ────────────────────────────────────────────────────

--- Pop a notice up over the hotbar ("inventory full"). `kind` picks the chip:
--- "error" (default), "success" or "info". A new one restarts the clock rather than
--- queueing behind the last.
function Inventory.notice(message: string, kind: string?)
	-- A full bag gets its thunk here. Other refusals stay silent at this layer: a
	-- purchase short of cash already buzzes (SfxService's "denied" from the till).
	if string.find(string.lower(message), "full", 1, true) then
		Sfx.play("bagFull")
	end
	noticeToken += 1
	local token = noticeToken
	local group = ui.notice
	ui.noticeText.Text = string.upper(message)
	local look = NOTICE_KINDS[kind or "error"] or NOTICE_KINDS.error
	ui.noticeChip.BackgroundColor3 = look.color
	ui.noticeGlyph.Text = look.glyph
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
	local item = state.slots[index]
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

--- Heart or unheart the nuke in slot `index` (Shared/Bag). Painted at once, the
--- server's CarryState confirms it a tick later. `restore` (the touch double-tap)
--- puts the hands back to `before`, undoing the pick-up the first tap did.
toggleHeart = function(index: number, restore: boolean?, before: string?)
	local item = state.slots[index]
	-- A washed crate rides on its own list the server never hearts.
	if item == nil or item.crate then
		return
	end
	if restore then
		bagCloseToken += 1 -- the first tap's "close the bag" no longer applies
		if selected ~= before then
			selected = before
			if holdRemote then
				holdRemote:FireServer(selected)
			end
		end
	end
	item.hearted = not item.hearted
	if heartRemote then
		heartRemote:FireServer(item.uid)
	end
	Sfx.play("click")
	Inventory.notice(
		if item.hearted then "hearted \u{2014} it can't be sold or gifted" else "unhearted",
		if item.hearted then "success" else "info"
	)
	renderSlots()

	-- A little pop on every slot showing it (the hotbar and the bag can both be up).
	if item.hearted then
		for _, list in { slots, bagCells } do
			for _, entry in list do
				if entry.uid == item.uid then
					entry.heartScale.Scale = 0.4
					TweenService:Create(entry.heartScale, NOTICE_IN, { Scale = 1 }):Play()
				end
			end
		end
	end
end

--- One of BAG_FILTERS' ids: shade every bag cell that doesn't match it.
function Inventory.setBagFilter(id: string)
	bagFilter = id
	Sfx.play("click")
	renderSlots()
end

--- SORT: rearrange the backpack rows (slot 11 on) -- hearted first, then rarest,
--- then most valuable -- leaving the hotbar's ten where the player put them. It
--- rewrites the saved order, so it sticks like a drag does.
function Inventory.sortBag()
	local order = state.order
	if order == nil then
		return
	end
	local list = {}
	for index = HOTBAR_SLOTS + 1, state.capacity do
		local item = state.slots[index]
		if item then
			table.insert(list, item)
		end
	end
	local function rank(item: any): number
		local def = Rarity.DEFS[item.rarity]
		return if def then def.order else 0
	end
	table.sort(list, function(a, b)
		local ha, hb = a.hearted == true, b.hearted == true
		if ha ~= hb then
			return ha
		end
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra > rb
		end
		local va, vb = tonumber(a.value) or 0, tonumber(b.value) or 0
		if va ~= vb then
			return va > vb
		end
		return a.uid < b.uid
	end)
	for index = HOTBAR_SLOTS + 1, state.capacity do
		local item = list[index - HOTBAR_SLOTS]
		order[index] = if item then item.uid else ""
	end
	layoutSlots()
	renderSlots()
	Sfx.play("click")
	if slotOrderRemote then
		slotOrderRemote:FireServer(state.order)
	end
end

-- ── Held rate tag ───────────────────────────────────────────────────

--- Star rating + "+$X/s" over the nuke in YOUR hands. The BillboardGui lives in your PlayerGui and
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
	StarLine.set(ui.rateTagStars, Bombing.statsFor(item).stars)
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
	ui.rateTagStars = UIKit.label(tag, {
		name = "Stars",
		size = UDim2.new(1, 0, 0, 22),
		font = House.font,
		textSize = 20,
		color = STAR_GOLD,
		xAlign = Enum.TextXAlignment.Center,
	})
	ui.rateTagText = UIKit.label(tag, {
		name = "Rate",
		position = UDim2.fromOffset(0, 22),
		size = UDim2.new(1, 0, 0, 34),
		font = House.font,
		textSize = 26,
		color = COLOR.green,
		xAlign = Enum.TextXAlignment.Center,
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
	ui.dragGui = buildDragGui()
	ui.dragGui.Parent = playerGui
	watchDrag()

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
	slotOrderRemote = Net.get("SlotOrder")
	heartRemote = Net.get("HeartItem")

	Net.get("Notice").OnClientEvent:Connect(function(message, kind)
		Inventory.notice(tostring(message), if type(kind) == "string" then kind else nil)
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
		state.limit = payload.capacity or 0
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
					crate = true,
				})
			end
		end
		state.capacity = math.max(state.limit, #state.items)

		-- The saved arrangement, once: after that this client is the one moving
		-- things, and a payload that crossed a drag in flight must not undo it.
		if state.order == nil then
			state.order = {}
			for _, uid in payload.order or {} do
				table.insert(state.order, if type(uid) == "string" then uid else "")
			end
		end
		layoutSlots()
		-- Whatever was being dragged may have just left the bag.
		if drag and drag.active and state.slots[drag.from] == nil then
			endDrag(nil)
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
