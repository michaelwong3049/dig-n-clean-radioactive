--[[
	StationController.lua — the base camp panel.

	Appears when you are standing at the decon station or the trader, and lists what is
	in your bag. Select a row, then act on it. Placeholder art, real information: the
	point of Phase 1 is finding out whether the verbs feel good, and the verbs here are
	SCRUB, SELL and RACK.

	The panel deliberately shows the SAME list at both stations but offers different
	verbs, because that is the design's actual shape — the decon station is where the
	clock stops and dirt comes off, the trader is only a till.

	THE PANEL NOW SITS AT TRUE SCREEN-CENTRE, BIASED UPWARD. DetectorController's
	scope/status/dig-button and InventoryController's hotbar never hide, even away
	from a station — see UIKit.Dock.RESERVE — so a literal screen-centre anchor would
	sit inside the dock's reserved band more often than not. `Position = UDim2.new(0.5,
	0, 0.5, -Dock.RESERVE / 2)` centres this panel in whatever space is left ABOVE the
	dock instead, at any resolution — the offset is algebraically equivalent to
	`(screenHeight - RESERVE) / 2`, so it needs no per-resolution tuning.

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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Station = {}

-- Same fields UIKit.C already carries (panel/stroke/selected/text/dim/green/amber/
-- red/blue), aliased so every COLOR.xxx read below keeps working unchanged.
local COLOR = UIKit.C

local ROWS = 9
local LOCKER_ROWS = 3

local ui = {}
local state = { station = nil, items = {}, locker = {} }
local selected: string? = nil
local actionRemote: any = nil
local toastToken = 0

local function rarityColor(name: string): Color3
	local def = Rarity.DEFS[name]
	return if def then def.color else COLOR.text
end

-- ── Build ───────────────────────────────────────────────────────────

--- One item row. USED TO BE ONE TextButton whose whole Text was a single
--- string.format("%-22s %-7s %-7s $%d", ...) call — columns only lined up because
--- Font.Code is monospace, and no rounded display font has fixed character widths.
--- Four child labels instead: name flexes, stage/pips/value are fixed-width. The
--- button itself, its Uid attribute and its scrub-progress Fill are unchanged — only
--- what is drawn INSIDE it changes. Reached the same way Fill always was, via
--- Roblox's child-by-name lookup (row.ItemNameLabel, row.Fill, ...), so every
--- existing row.Visible / row:SetAttribute call elsewhere in this file needs no
--- changes at all.
local function makeRow(parent: Instance, order: number): TextButton
	local row = Instance.new("TextButton")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundColor3 = COLOR.panel
	row.BackgroundTransparency = 1
	row.AutoButtonColor = false
	row.Text = ""
	row.Visible = false
	row.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row

	-- scrub progress, drawn behind the labels
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = COLOR.blue
	fill.BackgroundTransparency = 0.6
	fill.BorderSizePixel = 0
	fill.ZIndex = 0
	fill.Parent = row

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = fill

	UIKit.label(row, {
		name = "ItemNameLabel",
		position = UDim2.fromOffset(8, 0),
		size = UDim2.fromOffset(270, 26),
		font = UIKit.Font.body,
		textSize = 15,
	})
	UIKit.label(row, {
		name = "StageLabel",
		position = UDim2.fromOffset(286, 0),
		size = UDim2.fromOffset(90, 26),
		font = UIKit.Font.body,
		textSize = 15,
	})
	UIKit.label(row, {
		name = "PipsLabel",
		position = UDim2.fromOffset(384, 0),
		size = UDim2.fromOffset(80, 26),
		font = UIKit.Font.body,
		textSize = 15,
		xAlign = Enum.TextXAlignment.Center,
	})
	UIKit.label(row, {
		name = "ValueLabel",
		position = UDim2.fromOffset(472, 0),
		size = UDim2.fromOffset(108, 26),
		font = UIKit.Font.body,
		textSize = 15,
		xAlign = Enum.TextXAlignment.Right,
	})

	return row
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "StationHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Below the dock (60) on purpose — see the file header. The rad meter and the
	-- hotbar never hide, and exposure from a hot bag keeps accruing even while this
	-- panel is open, so the dock is the one thing that should never end up covered.
	gui.DisplayOrder = 40
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel, panelStroke = UIKit.panel(gui, {
		name = "Panel",
		size = UDim2.fromOffset(620, 0),
		position = UDim2.new(0.5, 0, 0.5, -Dock.RESERVE / 2),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = COLOR.panel,
		transparency = 0.08,
		cornerRadius = UIKit.Radius.panel,
		automaticSizeY = true,
		visible = false,
	})
	ui.panel = panel
	ui.panelStroke = panelStroke

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
	shopLayout.Padding = UDim.new(0, 8)
	shopLayout.Parent = shop

	ui.shopUpgrade = UIKit.label(shop, {
		name = "Upgrade",
		size = UDim2.new(1, 0, 0, 28),
		font = UIKit.Font.body,
		textSize = 18,
		color = COLOR.amber,
	})
	ui.shopUpgrade.LayoutOrder = 1

	ui.shopDeltas = UIKit.label(shop, {
		name = "Deltas",
		size = UDim2.fromScale(1, 0),
		font = UIKit.Font.body,
		textSize = 15,
		color = COLOR.green,
		yAlign = Enum.TextYAlignment.Top,
		wrapped = true,
	})
	ui.shopDeltas.LayoutOrder = 2
	ui.shopDeltas.AutomaticSize = Enum.AutomaticSize.Y

	ui.buyButton = UIKit.button(shop, {
		name = "Buy",
		size = UDim2.new(1, 0, 0, 48),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.amber,
		fillTransparency = 0.25,
		text = "BUY",
	})
	ui.buyButton.LayoutOrder = 3

	-- ── Plot mode (claim board) ─────────────────────────────────────────
	-- Same reasoning as Shop mode: a claim board IS a station, so it reuses
	-- this panel and the StationAction triad rather than a parallel one.
	local plot = Instance.new("Frame")
	plot.Name = "Plot"
	plot.LayoutOrder = 26
	plot.Size = UDim2.fromScale(1, 0)
	plot.AutomaticSize = Enum.AutomaticSize.Y
	plot.BackgroundTransparency = 1
	plot.Visible = false
	plot.Parent = panel
	ui.plot = plot

	local plotLayout = Instance.new("UIListLayout")
	plotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	plotLayout.Padding = UDim.new(0, 8)
	plotLayout.Parent = plot

	ui.plotBanked = UIKit.label(plot, {
		name = "Banked",
		size = UDim2.new(1, 0, 0, 26),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.green,
	})
	ui.plotBanked.LayoutOrder = 1

	ui.collectButton = UIKit.button(plot, {
		name = "Collect",
		size = UDim2.new(1, 0, 0, 48),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.green,
		fillTransparency = 0.25,
		text = "COLLECT",
	})
	ui.collectButton.LayoutOrder = 2

	ui.slotsInfo = UIKit.label(plot, {
		name = "SlotsInfo",
		size = UDim2.new(1, 0, 0, 24),
		font = UIKit.Font.body,
		textSize = 15,
		color = COLOR.dim,
	})
	ui.slotsInfo.LayoutOrder = 3

	ui.buySlotButton = UIKit.button(plot, {
		name = "BuySlot",
		size = UDim2.new(1, 0, 0, 48),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.amber,
		fillTransparency = 0.25,
		text = "BUY SLOT",
	})
	ui.buySlotButton.LayoutOrder = 4

	-- ── Pedestal mode (stand) ────────────────────────────────────────────
	-- Empty+unlocked reuses the SAME carry rows the decon/trader panel already
	-- draws — "an item picker" is just those rows with a different verb attached,
	-- exactly like Shop mode reused the panel instead of inventing new list UI.
	local pedestal = Instance.new("Frame")
	pedestal.Name = "Pedestal"
	pedestal.LayoutOrder = 27
	pedestal.Size = UDim2.fromScale(1, 0)
	pedestal.AutomaticSize = Enum.AutomaticSize.Y
	pedestal.BackgroundTransparency = 1
	pedestal.Visible = false
	pedestal.Parent = panel
	ui.pedestal = pedestal

	local pedestalLayout = Instance.new("UIListLayout")
	pedestalLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pedestalLayout.Padding = UDim.new(0, 8)
	pedestalLayout.Parent = pedestal

	ui.standInfo = UIKit.label(pedestal, {
		name = "StandInfo",
		size = UDim2.new(1, 0, 0, 26),
		font = UIKit.Font.body,
		textSize = 16,
		color = COLOR.text,
	})
	ui.standInfo.LayoutOrder = 1

	ui.displayButton = UIKit.button(pedestal, {
		name = "Display",
		size = UDim2.new(1, 0, 0, 48),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.green,
		fillTransparency = 0.25,
		text = "DISPLAY",
	})
	ui.displayButton.LayoutOrder = 2

	ui.undisplayButton = UIKit.button(pedestal, {
		name = "Undisplay",
		size = UDim2.new(1, 0, 0, 48),
		font = UIKit.Font.body,
		textSize = 19,
		color = COLOR.amber,
		fillTransparency = 0.25,
		text = "UNDISPLAY",
	})
	ui.undisplayButton.LayoutOrder = 3

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = panel

	ui.title = UIKit.label(panel, {
		name = "Title",
		size = UDim2.new(1, 0, 0, 30),
		font = UIKit.Font.body,
		textSize = 26,
		color = COLOR.text,
	})
	ui.title.LayoutOrder = 1

	ui.subtitle = UIKit.label(panel, {
		name = "Subtitle",
		size = UDim2.new(1, 0, 0, 20),
		font = UIKit.Font.body,
		textSize = 16,
		color = COLOR.dim,
	})
	ui.subtitle.LayoutOrder = 2

	ui.rows = {}
	for index = 1, ROWS do
		table.insert(ui.rows, makeRow(panel, 10 + index))
	end

	ui.lockerTitle = UIKit.label(panel, {
		name = "LockerTitle",
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.body,
		textSize = 15,
		color = COLOR.red,
		visible = false,
	})
	ui.lockerTitle.LayoutOrder = 40

	ui.lockerRows = {}
	for index = 1, LOCKER_ROWS do
		table.insert(ui.lockerRows, makeRow(panel, 40 + index))
	end

	local actions = Instance.new("Frame")
	actions.LayoutOrder = 60
	actions.Size = UDim2.new(1, 0, 0, 48)
	actions.BackgroundTransparency = 1
	actions.Parent = panel

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.Padding = UDim.new(0, 8)
	actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionLayout.Parent = actions

	ui.scrubButton = UIKit.button(actions, {
		name = "Scrub",
		size = UDim2.new(0.32, 0, 1, 0),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.blue,
		text = "HOLD TO SCRUB",
	})
	ui.scrubButton.LayoutOrder = 1

	ui.sellButton = UIKit.button(actions, {
		name = "Sell",
		size = UDim2.new(0.32, 0, 1, 0),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.amber,
		text = "SELL",
	})
	ui.sellButton.LayoutOrder = 2

	ui.rackButton = UIKit.button(actions, {
		name = "Rack",
		size = UDim2.new(0.32, 0, 1, 0),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.dim,
		text = "RACK",
	})
	ui.rackButton.LayoutOrder = 3

	ui.toast = UIKit.label(panel, {
		name = "Toast",
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.body,
		textSize = 16,
		color = COLOR.green,
	})
	ui.toast.LayoutOrder = 70

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

local function patchPips(item): string
	if item.clean then
		return "clean"
	end
	local pips = string.rep("\u{25CF}", math.min(#item.patches, 6))
	return pips
end

local function paintRow(row: TextButton, item, isSelected: boolean, scrubUid: string?, scrubProgress: number)
	row.Visible = true

	local colour = rarityColor(item.rarity)
	-- All four keep the SAME single colour, exactly as the old one-string row did —
	-- this is a rendering restructure, not a new visual design for the row.
	local nameLabel = row.ItemNameLabel :: TextLabel
	local stageLabel = row.StageLabel :: TextLabel
	local pipsLabel = row.PipsLabel :: TextLabel
	local valueLabel = row.ValueLabel :: TextLabel

	nameLabel.Text = string.sub(item.name, 1, 26)
	nameLabel.TextColor3 = colour
	stageLabel.Text = string.lower(item.stage)
	stageLabel.TextColor3 = colour
	pipsLabel.Text = patchPips(item)
	pipsLabel.TextColor3 = colour
	valueLabel.Text = `${item.value}`
	valueLabel.TextColor3 = colour

	row.BackgroundTransparency = if isSelected then 0.55 else 1
	row.BackgroundColor3 = COLOR.selected
	row.Fill.Size = if scrubUid == item.uid then UDim2.fromScale(scrubProgress, 1) else UDim2.fromScale(0, 1)
	row:SetAttribute("Uid", item.uid)
end

local function render()
	if state.station == nil then
		ui.panel.Visible = false
		return
	end

	ui.panel.Visible = true

	-- Shop mode replaces the item list entirely: you are not carrying anything
	-- relevant to this transaction, so showing your backpack is noise.
	local atShop = state.station == "shop"
	local atPlot = state.station == "plot"
	local atPedestal = state.station == "pedestal"
	ui.shop.Visible = atShop
	ui.plot.Visible = atPlot
	ui.pedestal.Visible = atPedestal
	if atShop then
		local offer = state.offer
		ui.title.Text = `{string.upper(state.stationId or "SHOP")} SHOP`
		ui.title.TextColor3 = COLOR.amber
		ui.panelStroke.Color = COLOR.amber
		ui.subtitle.Text = string.format("$%d", state.cash or 0)

		if offer == nil then
			ui.shopUpgrade.Text = "nothing for sale here"
			ui.shopDeltas.Text = ""
			ui.buyButton.Visible = false
		elseif offer.maxed then
			ui.shopUpgrade.Text = `{offer.currentName} \u{2014} best there is`
			ui.shopUpgrade.TextColor3 = COLOR.green
			ui.shopDeltas.Text = ""
			ui.buyButton.Visible = false
		else
			ui.shopUpgrade.Text = `{offer.currentName}  \u{2192}  {offer.nextName}`
			ui.shopUpgrade.TextColor3 = COLOR.amber
			-- The deltas are the whole pitch. "radius 21 -> 27" sells the upgrade;
			-- the tier's NAME means nothing to someone who has not memorised the list.
			ui.shopDeltas.Text = table.concat(offer.deltas, "\n")
			ui.buyButton.Visible = true
			ui.buyButton.Text = `BUY  ${offer.price}`
			ui.buyButton.TextColor3 = if offer.affordable then COLOR.amber else COLOR.red
		end

		for _, row in ui.rows do
			row.Visible = false
		end
		for _, row in ui.lockerRows do
			row.Visible = false
		end
		ui.lockerTitle.Visible = false
		ui.scrubButton.Visible = false
		ui.rackButton.Visible = false
		ui.sellButton.Visible = false
		return
	end

	if atPlot then
		local view = state.plotView
		ui.title.Text = if view then `PLOT {view.plotIndex}` else "CLAIM BOARD"
		ui.title.TextColor3 = COLOR.green
		ui.panelStroke.Color = COLOR.green
		ui.subtitle.Text = if view and view.isOwner then "your plot" else "not your plot"

		if view and view.isOwner then
			ui.plotBanked.Text = string.format("banked  $%d", view.bankedCash)
			ui.collectButton.Visible = true
			ui.collectButton.Text = string.format("COLLECT  $%d", view.bankedCash)
			ui.collectButton.TextColor3 = if view.bankedCash > 0 then COLOR.green else COLOR.dim

			ui.slotsInfo.Text = string.format("slots %d / %d", view.slots, view.maxSlots)
			if view.nextSlotPrice then
				ui.buySlotButton.Visible = true
				ui.buySlotButton.Text = string.format("BUY SLOT  $%d", view.nextSlotPrice)
			else
				ui.buySlotButton.Visible = false
			end
		else
			ui.plotBanked.Text = ""
			ui.collectButton.Visible = false
			ui.slotsInfo.Text = view and string.format("slots %d / %d", view.slots, view.maxSlots) or ""
			ui.buySlotButton.Visible = false
		end

		for _, row in ui.rows do
			row.Visible = false
		end
		for _, row in ui.lockerRows do
			row.Visible = false
		end
		ui.lockerTitle.Visible = false
		ui.scrubButton.Visible = false
		ui.rackButton.Visible = false
		ui.sellButton.Visible = false
		return
	end

	if atPedestal then
		local view = state.standView
		ui.title.Text = if view then `STAND {view.slot}` else "STAND"
		ui.title.TextColor3 = COLOR.blue
		ui.panelStroke.Color = COLOR.blue
		ui.subtitle.Text = if view and view.isOwner then "your plot" else "not your plot"

		-- A picker only makes sense on your own, unlocked, empty stand -- every
		-- other case is a status message with at most one verb.
		local showPicker = view ~= nil and view.isOwner and not view.locked and not view.occupied

		if view == nil or not view.isOwner then
			ui.standInfo.Text = "not your plot"
			ui.standInfo.TextColor3 = COLOR.dim
			ui.displayButton.Visible = false
			ui.undisplayButton.Visible = false
		elseif view.locked then
			ui.standInfo.Text = "locked \u{2014} buy this slot at the claim board"
			ui.standInfo.TextColor3 = COLOR.red
			ui.displayButton.Visible = false
			ui.undisplayButton.Visible = false
		elseif view.occupied then
			local left = view.uncrateSecondsLeft or 0
			if left > 0 then
				ui.standInfo.Text = string.format("%s \u{2014} crating, %ds left", view.itemName or "item", left)
				ui.standInfo.TextColor3 = COLOR.amber
				ui.undisplayButton.Visible = false
			else
				ui.standInfo.Text = string.format("%s (%s)", view.itemName or "item", view.rarity or "")
				ui.standInfo.TextColor3 = rarityColor(view.rarity or "")
				ui.undisplayButton.Visible = true
			end
			ui.displayButton.Visible = false
		else
			ui.standInfo.Text = "empty \u{2014} pick an item below"
			ui.standInfo.TextColor3 = COLOR.dim
			ui.displayButton.Visible = true
			ui.undisplayButton.Visible = false
		end

		-- Keep the selection valid against carry, same rule the decon/trader
		-- path uses below -- this panel picks from the SAME list.
		local stillThere = false
		for _, item in state.items do
			if item.uid == selected then
				stillThere = true
				break
			end
		end
		if not stillThere then
			selected = if #state.items > 0 then state.items[1].uid else nil
		end

		for index, row in ui.rows do
			local item = state.items[index]
			if item and showPicker then
				paintRow(row, item, item.uid == selected, nil, 0)
			else
				row.Visible = false
			end
		end
		for _, row in ui.lockerRows do
			row.Visible = false
		end
		ui.lockerTitle.Visible = false
		ui.scrubButton.Visible = false
		ui.rackButton.Visible = false
		ui.sellButton.Visible = false
		return
	end

	local atDecon = state.station == "decon"
	ui.title.Text = if atDecon then "DECON STATION" else "TRADER"
	ui.title.TextColor3 = if atDecon then COLOR.blue else COLOR.amber
	ui.panelStroke.Color = if atDecon then COLOR.blue else COLOR.amber

	ui.subtitle.Text = if atDecon
		then string.format("$%d    %s (potency %d)    clocks stopped", state.cash or 0, state.cleanerName or "", state.potency or 1)
		else string.format("$%d    dirty items sell at 20%%", state.cash or 0)

	-- keep the selection valid
	local stillThere = false
	for _, item in state.items do
		if item.uid == selected then stillThere = true break end
	end
	for _, item in state.locker do
		if item.uid == selected then stillThere = true break end
	end
	if not stillThere then
		selected = if #state.items > 0 then state.items[1].uid else nil
	end

	for index, row in ui.rows do
		local item = state.items[index]
		if item then
			paintRow(row, item, item.uid == selected, state.scrubUid, state.scrubProgress or 0)
		else
			row.Visible = false
		end
	end

	ui.lockerTitle.Visible = #state.locker > 0
	ui.lockerTitle.Text = `QUARANTINE LOCKER \u{2014} {#state.locker} waiting on a better cleaner`
	for index, row in ui.lockerRows do
		local item = state.locker[index]
		if item then
			paintRow(row, item, item.uid == selected, nil, 0)
		else
			row.Visible = false
		end
	end

	-- Find the selected item to label the buttons honestly.
	local chosen = nil
	for _, item in state.items do
		if item.uid == selected then chosen = item break end
	end
	if chosen == nil then
		for _, item in state.locker do
			if item.uid == selected then chosen = item break end
		end
	end

	ui.scrubButton.Visible = atDecon
	ui.rackButton.Visible = atDecon
	ui.sellButton.Visible = not atDecon

	if chosen and chosen.blockedBy then
		ui.scrubButton.Text = `NEEDS {string.upper(chosen.needs or "")}`
		ui.scrubButton.TextColor3 = COLOR.red
	elseif chosen and chosen.clean then
		ui.scrubButton.Text = "CLEAN"
		ui.scrubButton.TextColor3 = COLOR.green
	else
		ui.scrubButton.Text = "HOLD TO SCRUB"
		ui.scrubButton.TextColor3 = COLOR.blue
	end

	ui.sellButton.Text = if chosen then `SELL  ${chosen.value}` else "SELL"
end

local function toast(message: string)
	ui.toast.Text = message
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
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	actionRemote = Net.get("StationAction")

	local function bindRow(row: TextButton)
		row.MouseButton1Click:Connect(function()
			selected = row:GetAttribute("Uid")
			render()
		end)
	end
	for _, row in ui.rows do
		bindRow(row)
	end
	for _, row in ui.lockerRows do
		bindRow(row)
	end

	ui.scrubButton.MouseButton1Down:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "scrub", uid = selected, holding = true })
		end
	end)
	ui.scrubButton.MouseButton1Up:Connect(function()
		actionRemote:FireServer({ action = "scrub", holding = false })
	end)
	ui.scrubButton.MouseLeave:Connect(function()
		actionRemote:FireServer({ action = "scrub", holding = false })
	end)

	ui.sellButton.MouseButton1Click:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "sell", uid = selected })
		end
	end)

	ui.buyButton.MouseButton1Click:Connect(function()
		-- Track only. The server re-derives which shop this is from where the
		-- player is standing, so a crafted payload buys nothing.
		if state.stationId then
			actionRemote:FireServer({ action = "buy", track = state.stationId })
		end
	end)

	ui.rackButton.MouseButton1Click:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "rack", uid = selected })
		end
	end)

	ui.collectButton.MouseButton1Click:Connect(function()
		actionRemote:FireServer({ action = "collect" })
	end)

	ui.buySlotButton.MouseButton1Click:Connect(function()
		actionRemote:FireServer({ action = "buySlot" })
	end)

	ui.displayButton.MouseButton1Click:Connect(function()
		if selected then
			actionRemote:FireServer({ action = "display", uid = selected })
		end
	end)

	ui.undisplayButton.MouseButton1Click:Connect(function()
		actionRemote:FireServer({ action = "undisplay" })
	end)

	Net.get("StationState").OnClientEvent:Connect(function(payload)
		state = payload
		state.items = payload.items or {}
		state.locker = payload.locker or {}
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
