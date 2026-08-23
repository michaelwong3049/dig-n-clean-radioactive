--[[
	InventoryController.lua — the hotbar. What you are carrying, along the bottom.

	WHAT THE SLOTS SAY, AND WHAT THEY DELIBERATELY DO NOT.
	A slot shows the ITEM: its name, in its rarity colour. That is all. The obvious
	temptation is to hang the whole decay apparatus off every slot — a draining fuse
	bar, a stage tint, the value — and it is the wrong call. Twenty slots each running
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

local Inventory = {}

local COLOR = {
	panel = Color3.fromHex("0C0F0A"),
	stroke = Color3.fromHex("2A3324"),
	text = Color3.fromHex("E4E9DE"),
	dim = Color3.fromHex("7C8874"),
	empty = Color3.fromHex("1E241A"),
	green = Color3.fromHex("8FE04A"),
	amber = Color3.fromHex("F59E0B"),
	red = Color3.fromHex("EF4444"),
}

-- Slots shrink as capacity grows so a maxed satchel still fits one row. Below the
-- floor the name is unreadable anyway, so the row is allowed to run wider instead.
local SLOT_MAX = 78
local SLOT_MIN = 52
local SLOT_GAP = 6
local SLOT_HEIGHT = 62
local ROW_WIDTH_TARGET = 1080

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
-- then jumps a whole stage, which looks like the decay system is broken.
--
-- So the client predicts: advance a local offset every frame and add it to `elapsed`
-- before asking Shared/Decay anything. The server still owns the real number and
-- every CarryState resets this to zero, which is the correction half of the deal.
local drift = 0

-- Reused so the per-frame card render does not allocate a table sixty times a second
-- just to add one number to one field.
local scratch = { uid = "", rarity = "", modifier = "None", elapsed = 0, frozen = false }

-- The lowest remaining-time this stage has shown, so a correction can never push the
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
local floorFor: { [string]: { stage: string, remaining: number } } = {}

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
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = slot

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR.stroke
	stroke.Thickness = 2
	stroke.Parent = slot

	-- The slot's number, top-left, dim. Present on every slot including the ones past
	-- the bindable range so the row does not look ragged.
	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.Position = UDim2.fromOffset(5, 2)
	key.Size = UDim2.fromOffset(14, 12)
	key.BackgroundTransparency = 1
	key.Font = Enum.Font.GothamBold
	key.TextSize = 10
	key.TextXAlignment = Enum.TextXAlignment.Left
	key.TextColor3 = COLOR.dim
	key.Text = tostring(index)
	key.Parent = slot

	local name = Instance.new("TextLabel")
	name.Name = "ItemName"
	name.AnchorPoint = Vector2.new(0.5, 1)
	name.Position = UDim2.new(0.5, 0, 1, -6)
	name.Size = UDim2.new(1, -8, 0, 40)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 11
	name.TextWrapped = true
	name.TextYAlignment = Enum.TextYAlignment.Bottom
	name.TextColor3 = COLOR.text
	name.Text = ""
	name.Parent = slot

	slot.MouseButton1Click:Connect(function()
		Inventory.select(index)
	end)

	slots[index] = { button = slot, stroke = stroke, key = key, name = name, uid = nil :: string? }
end

local function buildCard(parent: Instance): Frame
	local card = Instance.new("Frame")
	card.Name = "Detail"
	card.AnchorPoint = Vector2.new(0.5, 1)
	-- Clear of the whole centre column, which stacks upward from the hotbar as
	-- hotbar (-14..-76) / bag count (-80) / pull button (-96..-144) / status
	-- (-172..-152, since it is bottom-anchored and 20 tall). At -92 this sat straight
	-- on top of the pull button; at -162 it still clipped the top ten pixels of the
	-- status line. If DetectorController's stack moves, this number moves with it.
	card.Position = UDim2.new(0.5, 0, 1, -178)
	card.Size = UDim2.fromOffset(330, 116)
	card.BackgroundColor3 = COLOR.panel
	card.BackgroundTransparency = 0.08
	card.Visible = false
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = COLOR.stroke
	stroke.Parent = card
	ui.cardStroke = stroke

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(12, 9)
	title.Size = UDim2.new(1, -24, 0, 20)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = COLOR.text
	title.Text = ""
	title.Parent = card
	ui.cardTitle = title

	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromOffset(12, 29)
	sub.Size = UDim2.new(1, -24, 0, 14)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 11
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = ""
	sub.Parent = card
	ui.cardSub = sub

	local decay = Instance.new("TextLabel")
	decay.Position = UDim2.fromOffset(12, 50)
	decay.Size = UDim2.new(1, -24, 0, 16)
	decay.BackgroundTransparency = 1
	decay.Font = Enum.Font.GothamMedium
	decay.TextSize = 13
	decay.TextXAlignment = Enum.TextXAlignment.Left
	decay.Text = ""
	decay.Parent = card
	ui.cardDecay = decay

	local dirt = Instance.new("TextLabel")
	dirt.Position = UDim2.fromOffset(12, 68)
	dirt.Size = UDim2.new(1, -24, 0, 16)
	dirt.BackgroundTransparency = 1
	dirt.Font = Enum.Font.GothamMedium
	dirt.TextSize = 13
	dirt.TextXAlignment = Enum.TextXAlignment.Left
	dirt.Text = ""
	dirt.Parent = card
	ui.cardDirt = dirt

	local worth = Instance.new("TextLabel")
	worth.AnchorPoint = Vector2.new(0, 1)
	worth.Position = UDim2.new(0, 12, 1, -8)
	worth.Size = UDim2.new(1, -24, 0, 18)
	worth.BackgroundTransparency = 1
	worth.Font = Enum.Font.GothamBold
	worth.TextSize = 15
	worth.TextXAlignment = Enum.TextXAlignment.Left
	worth.TextColor3 = COLOR.green
	worth.Text = ""
	worth.Parent = card
	ui.cardWorth = worth

	return card
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local header = Instance.new("TextLabel")
	header.Name = "BagCount"
	header.AnchorPoint = Vector2.new(0.5, 1)
	header.Position = UDim2.new(0.5, 0, 1, -80)
	header.Size = UDim2.fromOffset(240, 14)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.GothamBold
	header.TextSize = 11
	header.TextColor3 = COLOR.dim
	header.Text = ""
	header.Parent = gui
	ui.header = header

	local row = Instance.new("Frame")
	row.Name = "Hotbar"
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -14)
	row.Size = UDim2.fromOffset(ROW_WIDTH_TARGET, SLOT_HEIGHT)
	row.BackgroundTransparency = 1
	row.Parent = gui
	ui.row = row

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
local function slotWidth(): number
	if state.capacity <= 0 then
		return SLOT_MAX
	end
	local fit = (ROW_WIDTH_TARGET - SLOT_GAP * (state.capacity - 1)) / state.capacity
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
			slot.stroke.Thickness = 1
			continue
		end

		local colour = rarityColor(item.rarity)
		slot.name.Text = item.name
		slot.name.TextColor3 = colour
		slot.button.BackgroundColor3 = COLOR.panel
		slot.button.BackgroundTransparency = 0.25
		slot.stroke.Color = colour
		slot.stroke.Thickness = if item.uid == selected then 3 else 2
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
local function renderCard()
	local item = itemByUid(selected)
	if item == nil then
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
	local left = Decay.secondsToNextStage(now, state.fuseMult)
	local _, stage = Decay.stageOf(now, state.fuseMult)

	-- Monotonic within a stage; a new stage starts a fresh floor.
	if left ~= math.huge then
		local seen = floorFor[item.uid]
		if seen == nil or seen.stage ~= stage.name then
			floorFor[item.uid] = { stage = stage.name, remaining = left }
		else
			left = math.min(left, seen.remaining)
			seen.remaining = left
		end
	end

	if item.frozen then
		ui.cardDecay.Text = "clock stopped \u{2014} safe"
		ui.cardDecay.TextColor3 = COLOR.green
	elseif stage.name == "Slag" then
		ui.cardDecay.Text = "SLAG \u{2014} it is gone"
		ui.cardDecay.TextColor3 = COLOR.red
	else
		ui.cardDecay.Text = `{string.lower(stage.name)} \u{2014} {clockText(left)} to next stage`
		-- Under thirty seconds is the point where the honest advice is "run".
		ui.cardDecay.TextColor3 = if left < 30 then COLOR.red elseif stage.name ~= "Fresh" then COLOR.amber else COLOR.dim
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

	ui.cardWorth.Text = `${item.value}`
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
