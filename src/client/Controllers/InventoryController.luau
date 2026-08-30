--[[
	InventoryController.lua — the hotbar. What you are carrying, along the bottom.

	WHAT THE SLOTS SAY, AND WHAT THEY DELIBERATELY DO NOT.
	A slot shows the ITEM: its name, in its rarity colour. That is all. The obvious
	temptation is to hang the whole decay apparatus off every slot — a draining fuse
	bar, a condition tint, the value — and it is the wrong call. Twenty slots each
	running their own countdown is twenty things moving in the corner of your eye while
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
	it any more, and there is no longer a Heartbeat connection in this file at all.

	SLOT COUNT IS `capacity`, NOT THE NUMBER OF ITEMS. Empty slots are the point —
	they are how a player sees the headroom a suit upgrade bought them, and PLAN §3.4
	makes capacity one of the six tracks. A hotbar that only draws what you own hides
	the entire upgrade.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Inventory = {}

-- Same fields UIKit.C already carries, aliased so every COLOR.xxx read below keeps
-- working unchanged.
local COLOR = UIKit.C

-- Slots shrink as capacity grows so a maxed satchel still fits one row. Below the
-- floor the name is unreadable anyway, so the row is allowed to run wider instead.
local SLOT_MAX = Dock.SLOT_MAX
local SLOT_MIN = Dock.SLOT_MIN
local SLOT_GAP = Dock.SLOT_GAP
local SLOT_HEIGHT = Dock.HOTBAR_HEIGHT

-- Number keys only reach so far. Slots past this are visible and perfectly usable,
-- they just have no key — which is the normal hotbar bargain.
local BINDABLE = 9
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
}

local state = {
	capacity = 0,
	fuseMult = 1,
	items = {} :: { any },
}

-- Seconds since the last CarryState landed.
--
-- THIS IS LOAD-BEARING AND THE FIRST DRAFT DID NOT HAVE IT. CarryState fires only
-- when the bag CHANGES, so `elapsed` on an item is a snapshot from whenever that
-- last happened — usually the moment it came out of the ground. Reading the clock
-- straight off it gives a countdown that sits perfectly still for two minutes and
-- then jumps a whole condition, which looks like the decay system is broken.
--
-- So the client predicts: advance a local offset every frame and add it to `elapsed`
-- before asking Shared/Decay anything. The server still owns the real number and
-- every CarryState resets this to zero, which is the correction half of the deal.
local ui = {}
local slots: { any } = {}
local selected: string? = nil -- uid, NOT an index: the bag reorders when you sell
local holdRemote: any = nil

local function rarityColor(name: string?): Color3
	local def = if name then Rarity.DEFS[name] else nil
	return if def then def.color else COLOR.dim
end

-- ── Build ───────────────────────────────────────────────────────────

local function makeSlot(parent: Instance, index: number)
	local slot = Instance.new("TextButton")
	slot.Name = `Slot{index}`
	slot.AutoButtonColor = false
	slot.BackgroundColor3 = COLOR.panel
	slot.BackgroundTransparency = 0.25
	slot.Text = ""
	slot.LayoutOrder = index
	slot.Size = UDim2.fromOffset(SLOT_MAX, SLOT_HEIGHT)
	slot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UIKit.Radius.slot
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR.stroke
	stroke.Thickness = UIKit.Stroke.thin
	stroke.Parent = slot

	-- The slot's number, top-left, dim. Present on every slot including the ones past
	-- the bindable range so the row does not look ragged.
	local key = UIKit.label(slot, {
		name = "Key",
		position = UDim2.fromOffset(7, 4),
		size = UDim2.fromOffset(18, 16),
		font = UIKit.Font.body,
		textSize = 13,
		color = COLOR.dim,
		text = tostring(index),
	})

	local name = UIKit.label(slot, {
		name = "ItemName",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -8),
		size = UDim2.new(1, -10, 0, 46),
		font = UIKit.Font.body,
		textSize = 14,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
		yAlign = Enum.TextYAlignment.Bottom,
		wrapped = true,
	})

	slot.MouseButton1Click:Connect(function()
		Inventory.select(index)
	end)

	slots[index] = { button = slot, stroke = stroke, key = key, name = name, uid = nil :: string? }
end


local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	ui.header = UIKit.label(gui, {
		name = "BagCount",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -Dock.BAGCOUNT_BOTTOM),
		size = UDim2.fromOffset(280, Dock.BAGCOUNT_HEIGHT),
		font = UIKit.Font.body,
		textSize = 14,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
	})

	-- Scale-based, not a fixed offset — a fixed 1080px row was fine bottom-centred
	-- alone, but the dock now packs the meter/button/dial band above it on the same
	-- centre line, and a narrower viewport needs the hotbar to shrink with it rather
	-- than run off the edges. UISizeConstraint caps it so an ultrawide monitor does
	-- not stretch it absurdly wide either.
	local row = Instance.new("Frame")
	row.Name = "Hotbar"
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -Dock.HOTBAR_BOTTOM)
	row.Size = UDim2.new(1, -2 * Dock.ROW_SIDE_MARGIN, 0, SLOT_HEIGHT)
	row.BackgroundTransparency = 1
	-- Safety net, not a fix: slotWidth()'s shrink-to-fit clamp can already run wider
	-- than its target at max capacity (SLOT_MIN floors before the row runs out of
	-- room) — pre-existing, invisible only because nothing clipped it. A narrower
	-- live target on small viewports widens that gap; this keeps it from spilling
	-- into whatever sits either side of the hotbar instead of fixing the clamp math.
	row.ClipsDescendants = true
	row.Parent = gui
	ui.row = row

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

--- Slot width for the current capacity. Shrinks toward SLOT_MIN as the bag grows so
--- a Containment Rig's twenty slots still land on one row.
---
--- READS THE ROW'S LIVE AbsoluteSize NOW, not a compile-time target — the row is
--- Scale-based (see build()), so its actual pixel width depends on the viewport.
--- AbsoluteSize can read 0 for one frame before the GUI's first layout pass
--- resolves; the fallback below is just "use the default until it does."
local function slotWidth(): number
	if state.capacity <= 0 then
		return SLOT_MAX
	end
	local available = ui.row.AbsoluteSize.X
	if available <= 0 then
		return SLOT_MAX
	end
	local fit = (available - SLOT_GAP * (state.capacity - 1)) / state.capacity
	return math.clamp(math.floor(fit), SLOT_MIN, SLOT_MAX)
end

local function renderSlots()
	local width = slotWidth()

	for index = 1, math.max(#slots, state.capacity) do
		if slots[index] == nil and index <= state.capacity then
			makeSlot(ui.row, index)
		end

		local slot = slots[index]
		if slot == nil then
			continue
		end

		if index > state.capacity then
			slot.button.Visible = false
			slot.uid = nil
			continue
		end

		slot.button.Visible = true
		slot.button.Size = UDim2.fromOffset(width, SLOT_HEIGHT)
		slot.key.Text = if index <= BINDABLE then tostring(index) else ""

		local item = state.items[index]
		slot.uid = if item then item.uid else nil

		if item == nil then
			slot.name.Text = ""
			slot.button.BackgroundColor3 = COLOR.empty
			slot.button.BackgroundTransparency = 0.55
			slot.stroke.Color = COLOR.stroke
			slot.stroke.Thickness = UIKit.Stroke.thin
			continue
		end

		local colour = rarityColor(item.rarity)
		slot.name.Text = item.name
		slot.name.TextColor3 = colour
		slot.button.BackgroundColor3 = COLOR.panel
		slot.button.BackgroundTransparency = 0.25
		slot.stroke.Color = colour
		slot.stroke.Thickness = if item.uid == selected then UIKit.Stroke.selected else UIKit.Stroke.thin
	end

	local count = #state.items
	ui.header.Text = `BAG  {count}/{state.capacity}`
	ui.header.TextColor3 = if count >= state.capacity and state.capacity > 0 then COLOR.red else COLOR.dim
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

-- ── Lifecycle ───────────────────────────────────────────────────────

function Inventory.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ROBLOX'S OWN BACKPACK HAS TO GO, AND NOT JUST BECAUSE IT IS REDUNDANT.
	-- CoreGui binds the number row to its hotbar slots. ToolService welds models to
	-- the character instead of using Tool instances, so that backpack is always empty
	-- and the keys currently fall through to us by luck — but the moment anything
	-- puts a real Tool in it, CoreGui consumes 1-9 first, `gameProcessedEvent` comes
	-- back true, and every slot key here silently stops working. Turning it off makes
	-- that impossible rather than unlikely, and removes an empty widget that competes
	-- with this one for the same corner of the screen.
	--
	-- pcall because SetCoreGuiEnabled throws if the CoreGui is not ready yet, and a
	-- hotbar that fails to build over a cosmetic call would be a bad trade.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	holdRemote = Net.get("HoldInput")

	Net.get("CarryState").OnClientEvent:Connect(function(payload)
		state.capacity = payload.capacity or 0
		state.fuseMult = payload.fuseMult or 1
		state.items = payload.items or {}

		-- A selection whose item just left the bag — sold, racked, slagged — must not
		-- keep a stale card on screen. Keyed by uid rather than index precisely so
		-- this is detectable at all: selling slot 2 shuffles everything after it.
		if itemByUid(selected) == nil then
			selected = nil
			-- The server clears its own heldUid when an item leaves the bag
			-- (CarryService's tick), so this is only keeping the two in step for the
			-- NEXT keypress -- it is not what unloads the hand.
		end

		renderSlots()
	end)

	-- New: the row is Scale-based now, so a viewport resize (window resize, phone
	-- rotation) changes how many pixels slotWidth() has to divide up.
	ui.row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		renderSlots()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
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
