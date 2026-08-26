--[[
	InventoryController.lua — the hotbar. What you are carrying, along the bottom.

	WHAT THE SLOTS SAY, AND WHAT THEY DELIBERATELY DO NOT.
	A slot shows the ITEM: its name, in its rarity colour. That is all. The obvious
	temptation is to hang the whole decay apparatus off every slot — a draining fuse
	bar, a condition tint, the value — and it is the wrong call. Twenty slots each running
	their own countdown is twenty things moving in the corner of your eye while you
	are trying to read the ground, and the eye stops being able to find any of them.
	The hotbar answers "what have I got"; press a number and the card answers
	everything else.

	THE COUNTDOWN IS COMPUTED HERE, NOT STREAMED.
	CarryState sends `elapsed` and the satchel's fuse multiplier and fires only when
	the bag changes. The card's ticking clock comes from running Shared/Decay against
	those locally, every frame. That is the same reason Decay is a shared module at
	all (ARCHITECTURE.md): the number the player watches and the number the server
	enforces come out of one function, so they cannot drift apart.

	SLOT COUNT IS `capacity`, NOT THE NUMBER OF ITEMS. Empty slots are the point —
	they are how a player sees the headroom a suit upgrade bought them, and PLAN §3.4
	makes capacity one of the six tracks. A hotbar that only draws what you own hides
	the entire upgrade.

	THE DETAIL CARD USED TO BE HAND-TUNED AGAINST DetectorController'S PRIVATE
	NUMBERS — a comment here used to read "if DetectorController's stack moves, this
	number moves with it," which was true and unenforced. It now reads its position
	off UIKit.Dock.CARD_BOTTOM, the same shared table DetectorController and
	HudController read theirs from. No file has to know another file's layout again.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Decay = require(Shared.Decay)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local StationController = require(script.Parent.StationController)

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

--- $2.00/sec under a thousand, $5.2K/sec into the thousands — same convention
--- StationController's own formatRate uses for the same number on the pedestal
--- panel; duplicated rather than shared for the same reason CashController's
--- formatCash is duplicated everywhere else it appears.
local function formatRate(perSecond: number): string
	if perSecond >= 1_000 then
		return string.format("$%.1fK/sec", perSecond / 1_000)
	end
	return string.format("$%.2f/sec", perSecond)
end

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
local drift = 0

-- Reused so the per-frame card render does not allocate a table sixty times a second
-- just to add one number to one field.
local scratch = { uid = "", rarity = "", modifier = "None", elapsed = 0, frozen = false }

-- The lowest remaining-time this condition has shown, so a correction can never push the
-- countdown UP.
--
-- The server's clock and this one do not tick the same way, and that is not a bug in
-- either. Shared/Util/Ticker runs a FIXED timestep — it advances decay in nominal
-- 0.1s steps and, past five steps in one frame, throws the backlog away rather than
-- firing fifty ticks at once. `drift` here is wall-clock. Under load the two diverge,
-- always in the same direction: this one runs ahead.
--
-- Snapping to each correction therefore shows a countdown that occasionally jumps
-- backwards, which is the one thing a countdown may never do. So corrections are
-- accepted only DOWNWARD. The error that survives is showing slightly less time than
-- you really have, which is the safe direction to be wrong about a decay clock.
local floorFor: { [string]: { condition: string, remaining: number } } = {}

--- The item as it would be RIGHT NOW, rather than as of the last broadcast.
local function asOfNow(item: any): any
	if item.frozen then
		return item -- a frozen clock is not running, so there is nothing to predict
	end
	scratch.uid = item.uid
	scratch.rarity = item.rarity
	scratch.modifier = item.modifier
	scratch.elapsed = item.elapsed + drift
	scratch.frozen = false
	return scratch
end

local ui = {}
local slots: { any } = {}
local selected: string? = nil -- uid, NOT an index: the bag reorders when you sell

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

local function buildCard(parent: Instance): Frame
	-- Position derived from UIKit.Dock.CARD_BOTTOM — see the file header. Nothing
	-- here has to know DetectorController's numbers any more.
	local card, cardStroke = UIKit.panel(parent, {
		name = "Detail",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -Dock.CARD_BOTTOM),
		size = Dock.CARD_SIZE,
		color = COLOR.panel,
		transparency = 0.08,
		cornerRadius = UIKit.Radius.card,
		visible = false,
	})
	ui.cardStroke = cardStroke

	-- Row heights stacked top-down (title/sub/decay/dirt), each Y derived from
	-- the one above it instead of its own hardcoded offset. That's what let the
	-- worth row silently overlap the dirt row above it when CARD_SIZE last
	-- shrunk 136 -> 118: every row's offset was tuned against the old height
	-- and nothing moved when it changed. Shrink TITLE_H/SUB_H/DECAY_H/DIRT_H/
	-- WORTH_H or the pads below and the rows still stack without touching.
	local TOP_PAD, BOTTOM_PAD = 6, 6
	local TITLE_H, SUB_H, DECAY_H, DIRT_H, WORTH_H = 24, 16, 18, 18, 20

	local titleY = TOP_PAD
	local subY = titleY + TITLE_H
	local decayY = subY + SUB_H
	local dirtY = decayY + DECAY_H

	ui.cardTitle = UIKit.label(card, {
		name = "Title",
		position = UDim2.fromOffset(16, titleY),
		size = UDim2.new(1, -32, 0, TITLE_H),
		font = UIKit.Font.body,
		textSize = 22,
		color = COLOR.text,
	})

	ui.cardSub = UIKit.label(card, {
		name = "Sub",
		position = UDim2.fromOffset(16, subY),
		size = UDim2.new(1, -32, 0, SUB_H),
		font = UIKit.Font.body,
		textSize = 14,
	})

	ui.cardDecay = UIKit.label(card, {
		name = "Decay",
		position = UDim2.fromOffset(16, decayY),
		size = UDim2.new(1, -32, 0, DECAY_H),
		font = UIKit.Font.body,
		textSize = 16,
	})

	ui.cardDirt = UIKit.label(card, {
		name = "Dirt",
		position = UDim2.fromOffset(16, dirtY),
		size = UDim2.new(1, -32, 0, DIRT_H),
		font = UIKit.Font.body,
		textSize = 16,
	})

	ui.cardWorth = UIKit.label(card, {
		name = "Worth",
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, 16, 1, -BOTTOM_PAD),
		size = UDim2.new(1, -32, 0, WORTH_H),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.green,
	})

	return card
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

	ui.card = buildCard(gui)

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

local function clockText(seconds: number): string
	if seconds == math.huge then
		return "held"
	end
	local whole = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

--- The one part that runs every frame. Everything else waits for CarryState.
--
-- Checking StationController.isOpen() here rather than caching it off a
-- StationState listener means there is nothing to keep in sync: a CLOSE click sets
-- StationController's own `dismissed` flag same-frame, and the very next Heartbeat
-- reads it back true, no second signal required.
local function renderCard()
	local item = itemByUid(selected)
	if item == nil or StationController.isOpen() then
		ui.card.Visible = false
		return
	end

	ui.card.Visible = true

	local colour = rarityColor(item.rarity)
	local modifier = if item.modifier == "None" then "" else item.modifier .. " "

	ui.cardTitle.Text = item.name
	ui.cardTitle.TextColor3 = colour
	ui.cardSub.Text = string.upper(modifier .. item.rarity)
	ui.cardSub.TextColor3 = colour
	ui.cardStroke.Color = colour

	-- Run the clock locally off `elapsed` + drift. The server sent the item, not the
	-- ticking; see the note on `drift`.
	local now = asOfNow(item)
	local left = Decay.secondsToNextCondition(now, state.fuseMult)
	local _, condition = Decay.conditionOf(now, state.fuseMult)

	-- Monotonic within a condition; a new condition starts a fresh floor.
	if left ~= math.huge then
		local seen = floorFor[item.uid]
		if seen == nil or seen.condition ~= condition.name then
			floorFor[item.uid] = { condition = condition.name, remaining = left }
		else
			left = math.min(left, seen.remaining)
			seen.remaining = left
		end
	end

	if item.frozen then
		ui.cardDecay.Text = "clock stopped \u{2014} safe"
		ui.cardDecay.TextColor3 = COLOR.green
	elseif condition.name == "Slag" then
		ui.cardDecay.Text = "SLAG \u{2014} it is gone"
		ui.cardDecay.TextColor3 = COLOR.red
	else
		ui.cardDecay.Text = `{string.lower(condition.name)} \u{2014} {clockText(left)} to next condition`
		-- Under thirty seconds is the point where the honest advice is "run".
		ui.cardDecay.TextColor3 = if left < 30 then COLOR.red elseif condition.name ~= "Fresh" then COLOR.amber else COLOR.dim
	end

	if item.clean then
		ui.cardDirt.Text = "clean"
		ui.cardDirt.TextColor3 = COLOR.green
	elseif item.needs then
		ui.cardDirt.Text = `{#item.patches} patch(es) \u{2014} needs {item.needs}`
		ui.cardDirt.TextColor3 = COLOR.red
	else
		ui.cardDirt.Text = `{#item.patches} patch(es) \u{2014} scrubbable`
		ui.cardDirt.TextColor3 = COLOR.amber
	end

	-- The rate only ever rides along when CarryService actually computed one —
	-- dirty and Slagged items get perSecond = nil, matching exactly what
	-- ExhibitService.display would refuse, so this line never promises a payout
	-- the game won't honour if you walk it to a pedestal instead of selling it.
	ui.cardWorth.Text = if item.perSecond
		then string.format("$%d \u{2022} %s", item.value, formatRate(item.perSecond))
		else `${item.value}`
	ui.cardWorth.TextColor3 = if item.clean then COLOR.green else COLOR.dim
end

-- ── Selection ───────────────────────────────────────────────────────

function Inventory.select(index: number)
	local item = state.items[index]
	if item == nil then
		selected = nil
	elseif selected == item.uid then
		selected = nil -- pressing the same key again puts the card away
	else
		selected = item.uid
	end
	renderSlots()
	renderCard()
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

	Net.get("CarryState").OnClientEvent:Connect(function(payload)
		state.capacity = payload.capacity or 0
		state.fuseMult = payload.fuseMult or 1
		state.items = payload.items or {}
		drift = 0 -- the server just told us the truth; stop predicting from the old one

		-- A selection whose item just left the bag — sold, racked, slagged — must not
		-- keep a stale card on screen. Keyed by uid rather than index precisely so
		-- this is detectable at all: selling slot 2 shuffles everything after it.
		if itemByUid(selected) == nil then
			selected = nil
		end

		-- Sold, racked and slagged items must not keep a floor around: uids are
		-- unique, so this is a slow leak rather than a correctness bug, but a
		-- long session is a lot of dead entries.
		for uid in floorFor do
			if itemByUid(uid) == nil then
				floorFor[uid] = nil
			end
		end

		renderSlots()
		renderCard()
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

	-- Only the card animates, and only while something is selected. `drift` still has
	-- to advance regardless, or opening the card after a minute of not looking at it
	-- would show a clock a minute behind.
	RunService.Heartbeat:Connect(function(dt)
		drift += dt
		if selected ~= nil then
			renderCard()
		end
	end)

	renderSlots()
end

return Inventory
