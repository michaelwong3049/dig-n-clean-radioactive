--[[
	IndexController.lua — the item index. Browse every item that can be found, by
	stage, and see which ones you've actually held.

	THIS IS THE GUI HALF OF PLAN §10.10, NOT THE WHOLE THING. The full "Museum /
	Collection Wall" — a physical base-camp gallery, stage-completion luck bonuses —
	is explicitly a long-term / post-MVP feature there. This is scoped to exactly
	what was asked for: a small button, bottom-left, that opens a browsable panel.
	No new world geometry, no completion bonus.

	THE LAYOUT IS A CARD GRID NOW, NOT A TEXT LIST. Each stage is a section of square
	tiles — a dim "?" until you have held the item, its name in its rarity colour once
	you have. Selecting a discovered tile fills the DETAIL column on the left with that
	item's rarity, value, find-odds, appeal and flavour: the per-item story the old
	inline rows carried, moved somewhere it does not have to fight the grid for width.
	Everything the detail column shows is authored config (Items / Rarity / Stages),
	so there is still no second remote — just the one snapshot below.

	THE DATA WAS ALREADY HALF-BUILT. DigService.unearth() has set
	`data.discovered[itemId] = true` since before this controller existed — the
	profile schema comment even says "Drives the museum (PLAN §10.10)" — it just had
	no reader. This file is that reader, plus a button and a panel.

	ONE SNAPSHOT, THEN FREE UPDATES. IndexState fires exactly once, on load, with
	the player's current discovered set (DigService.start()). Every discovery AFTER
	that arrives for free: this controller also listens to Unearthed, which already
	carries the itemId of everything newly dug up, and just adds it to the local set
	— no second remote, no polling.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Index = {}

-- Dock.INDEX_SIZE, not a local number: LiquidController stacks its badge directly on
-- top of this button, and a second file deriving its offset from this file's private
-- constant is the exact coupling UIKit.Dock exists to prevent. Same migration
-- CashController's own header describes for CASH_SIZE.
local BUTTON_SIZE = Dock.INDEX_SIZE

-- ── Panel geometry ──────────────────────────────────────────────────
-- Responsive like StationController's panel rather than a fixed box: width is
-- "viewport minus a margin, but never wider/taller than", so the grid reflows on a
-- phone instead of running off the edge. The left column is a fixed width (the detail
-- text wants a stable measure); the scroller takes whatever is left.
local SCREEN_MARGIN = 40
local PANEL_MAX = Vector2.new(880, 620)
-- MIN.X keeps the grid usable on small viewports (detail column + gap + a few
-- tiles + the panel's 48px padding); it only bites below a ~940px client.
local PANEL_MIN = Vector2.new(470, 380)
local HEADER_H = 72 -- title band; both columns start below it
local DETAIL_WIDTH = 210
local COLUMN_GAP = 16
local TILE = 84
local TILE_GAP = 6

local discovered: { [string]: boolean } = {}
local totalItems = #Items.DEFS
local selectedId: string? = nil

local ui = {}

-- An item can belong to more than one stage (several span {3, 4}), so it gets a
-- SEPARATE tile built per stage section it appears in — this has to be a list per
-- item, not one tile, or discovering it would only ever repaint whichever stage's
-- tile happened to be built last.
type Tile = { button: TextButton, nameLabel: TextLabel, mark: TextLabel, stroke: UIStroke }
local itemTiles: { [string]: { Tile } } = {}
local stageCountLabels: { [number]: TextLabel } = {}

--- stageId -> its item list, precomputed once. Items.DEFS is small so this is cheap,
--- and it means the panel build below is a lookup per item rather than a `stages`
--- array scan per item per stage.
local itemsByStage: { [number]: { any } } = {}
for _, stage in Stages.DEFS do
	itemsByStage[stage.id] = {}
end
for _, item in Items.DEFS do
	for _, stageId in item.stages do
		if itemsByStage[stageId] then
			table.insert(itemsByStage[stageId], item)
		end
	end
end

-- ── Helpers ─────────────────────────────────────────────────────────

local function discoveredCount(): number
	local n = 0
	for _ in discovered do
		n += 1
	end
	return n
end

--- "$340", "$5.2K", "$1.4M" — the compact convention CashController.formatCash uses on
--- the cash badge, duplicated here (~6 lines) rather than pulling that file into this
--- diff. If a third caller wants it, lift it to UIKit then.
local function formatValue(n: number): string
	if n >= 1_000_000 then
		return string.format("$%.1fM", n / 1_000_000)
	elseif n >= 1_000 then
		return string.format("$%.1fK", n / 1_000)
	end
	return string.format("$%d", n)
end

-- ── Build ───────────────────────────────────────────────────────────

--- One tile: a "?" until discovered, the item's name in its rarity colour after.
--- Discovered tiles are clickable and drive the detail column; "?" tiles are inert
--- (Index.select refuses undiscovered ids, so the click just does nothing).
local function buildItemTile(parent: Instance, layoutOrder: number, item: any)
	local button = Instance.new("TextButton")
	button.Name = `Tile_{item.id}`
	button.AutoButtonColor = false
	button.BackgroundColor3 = UIKit.C.empty
	button.BackgroundTransparency = 0.45
	button.Text = ""
	button.LayoutOrder = layoutOrder
	button.ZIndex = 12
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UIKit.Radius.slot
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = UIKit.C.stroke
	stroke.Thickness = UIKit.Stroke.thin
	stroke.Parent = button

	local mark = UIKit.label(button, {
		name = "Mark",
		size = UDim2.fromScale(1, 1),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.hero,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Center,
		text = "?",
		zIndex = 13,
	})

	local nameLabel = UIKit.label(button, {
		name = "ItemName",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		size = UDim2.new(1, -8, 1, -8),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.text,
		xAlign = Enum.TextXAlignment.Center,
		text = "",
		wrapped = true,
		visible = false,
		zIndex = 13,
	})

	button.MouseButton1Click:Connect(function()
		Index.select(item.id)
	end)

	local tiles = itemTiles[item.id]
	if tiles == nil then
		tiles = {}
		itemTiles[item.id] = tiles
	end
	table.insert(tiles, { button = button, nameLabel = nameLabel, mark = mark, stroke = stroke })
end

--- One stage section: a header (name + this stage's own discovered count) and a grid
--- of its tiles, or an honest "nothing catalogued here yet" line for a stage that
--- stocks nothing — flagged rather than silently skipped, same ethic DigService's own
--- console warnings use for the same gap. (All six stages are stocked today.)
local function buildStageSection(parent: Instance, layoutOrder: number, stage: any)
	local section = Instance.new("Frame")
	section.Name = `Stage{stage.id}`
	section.Size = UDim2.fromScale(1, 0)
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.BackgroundTransparency = 1
	section.LayoutOrder = layoutOrder
	section.Parent = parent

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Padding = UDim.new(0, 8)
	sectionLayout.Parent = section

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 28)
	header.BackgroundTransparency = 1
	header.LayoutOrder = 1
	header.Parent = section

	UIKit.label(header, {
		name = "StageName",
		size = UDim2.new(1, -80, 1, 0),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.text,
		text = string.upper(stage.name),
		zIndex = 12,
	})

	local stageItems = itemsByStage[stage.id]
	local countLabel = UIKit.label(header, {
		name = "Count",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.fromOffset(70, 28),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Right,
		text = "",
		zIndex = 12,
	})
	stageCountLabels[stage.id] = countLabel

	if #stageItems == 0 then
		UIKit.label(section, {
			name = "Empty",
			size = UDim2.new(1, 0, 0, 24),
			font = UIKit.Font.body,
			textSize = UIKit.TextSize.body,
			color = UIKit.C.dim,
			text = "nothing catalogued here yet",
			zIndex = 12,
		})
		countLabel.Text = ""
		return
	end

	table.sort(stageItems, function(a, b)
		return Rarity.DEFS[a.rarity].order < Rarity.DEFS[b.rarity].order
	end)

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.LayoutOrder = 2
	grid.Parent = section

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(TILE, TILE)
	gridLayout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gridLayout.Parent = grid

	for i, item in stageItems do
		buildItemTile(grid, i, item)
	end
end

--- One "CAPTION / value" block in the detail column. Returns the value label for the
--- render step to fill; the caption is static.
local function detailField(parent: Instance, layoutOrder: number, caption: string): TextLabel
	local field = Instance.new("Frame")
	field.Name = caption
	field.Size = UDim2.fromScale(1, 0)
	field.AutomaticSize = Enum.AutomaticSize.Y
	field.BackgroundTransparency = 1
	field.LayoutOrder = layoutOrder
	field.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = field

	UIKit.label(field, {
		name = "Caption",
		size = UDim2.new(1, 0, 0, 14),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		text = caption,
		zIndex = 12,
	})

	local value = UIKit.label(field, {
		name = "Value",
		size = UDim2.new(1, 0, 0, 18),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.text,
		text = "",
		wrapped = true,
		zIndex = 12,
	})
	value.AutomaticSize = Enum.AutomaticSize.Y
	return value
end

--- The left column. A "select something" hint, or the selected item's card.
local function buildDetailColumn(panel: Instance)
	local column = Instance.new("Frame")
	column.Name = "Detail"
	column.Position = UDim2.fromOffset(0, HEADER_H)
	column.Size = UDim2.new(0, DETAIL_WIDTH, 1, -HEADER_H)
	column.BackgroundTransparency = 1
	column.ZIndex = 11
	column.Parent = panel

	local columnLayout = Instance.new("UIListLayout")
	columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnLayout.Padding = UDim.new(0, 14)
	columnLayout.Parent = column

	local total = UIKit.label(column, {
		name = "Total",
		size = UDim2.new(1, 0, 0, 20),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		text = "",
		zIndex = 12,
	})
	total.LayoutOrder = 0

	local hint = UIKit.label(column, {
		name = "Hint",
		size = UDim2.new(1, 0, 0, 40),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		text = "Select a discovered item to see its details.",
		wrapped = true,
		zIndex = 12,
	})
	hint.LayoutOrder = 1
	hint.AutomaticSize = Enum.AutomaticSize.Y

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.LayoutOrder = 2
	body.Visible = false
	body.Parent = column

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 12)
	bodyLayout.Parent = body

	local name = UIKit.label(body, {
		name = "ItemName",
		size = UDim2.fromScale(1, 0),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.title,
		color = UIKit.C.text,
		text = "",
		wrapped = true,
		zIndex = 12,
	})
	name.LayoutOrder = 1
	name.AutomaticSize = Enum.AutomaticSize.Y

	local meta = Instance.new("Frame")
	meta.Name = "Meta"
	meta.Size = UDim2.fromScale(1, 0)
	meta.AutomaticSize = Enum.AutomaticSize.Y
	meta.BackgroundTransparency = 1
	meta.LayoutOrder = 2
	meta.Parent = body

	local metaLayout = Instance.new("UIListLayout")
	metaLayout.SortOrder = Enum.SortOrder.LayoutOrder
	metaLayout.Padding = UDim.new(0, 8)
	metaLayout.Parent = meta

	local flavor = UIKit.label(body, {
		name = "Flavor",
		size = UDim2.fromScale(1, 0),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		text = "",
		wrapped = true,
		zIndex = 12,
	})
	flavor.LayoutOrder = 3
	flavor.AutomaticSize = Enum.AutomaticSize.Y

	ui.detail = {
		total = total,
		hint = hint,
		body = body,
		name = name,
		rarity = detailField(meta, 1, "RARITY"),
		value = detailField(meta, 2, "VALUE"),
		odds = detailField(meta, 3, "FIND ODDS"),
		appeal = detailField(meta, 4, "APPEAL"),
		foundIn = detailField(meta, 5, "FOUND IN"),
		flavor = flavor,
	}
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "IndexHud"
	gui.ResetOnSpawn = false
	-- FALSE, like StationController and for its reason: the panel is the only thing in
	-- here anchored to the screen CENTRE, and IgnoreGuiInset = true shifts a centred
	-- child up by half the topbar inset (it clipped ~18px off the panel's top on a
	-- short viewport). The INDEX button is bottom-anchored, so the inset doesn't move it.
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 90
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- The button. BOTTOM-LEFT, stacked directly above the cash badge, which sits
	-- directly above the meter, on the meter's own left margin.
	--
	-- Dock.INDEX_BOTTOM, never a typed offset. It is derived from Dock.CASH_BOTTOM
	-- and Dock.CASH_SIZE, so this file still does not need to know either the cash
	-- badge's or the meter's height — resize either one and the button follows.
	local button, buttonStroke = UIKit.button(gui, {
		name = "IndexButton",
		size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 1, -Dock.INDEX_BOTTOM),
		anchorPoint = Vector2.new(0, 1),
		text = "INDEX",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.text,
		fillColor = UIKit.C.panel,
		fillTransparency = 0.1,
		cornerRadius = UIKit.Radius.card,
		zIndex = 4,
	})
	ui.button = button
	ui.buttonStroke = buttonStroke

	-- The panel. Centred on screen — the same call StationController's header
	-- describes settling on, for the same reason: a panel this size can't dodge the
	-- dock by biasing upward (the old -Dock.RESERVE/2) without clipping off the TOP of
	-- a short viewport — it did, by 173px on a 480px play window. The dock's own
	-- column is LEFT-anchored and this panel is centred, so on any real viewport they
	-- don't overlap; on a tiny one the panel wins on DisplayOrder anyway.
	local panel = UIKit.panel(gui, {
		name = "Panel",
		size = UDim2.new(1, -2 * SCREEN_MARGIN, 1, -2 * SCREEN_MARGIN),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = UIKit.C.panel,
		transparency = 0.05,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		zIndex = 10,
		visible = false,
	})
	ui.panel = panel

	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = PANEL_MIN
	panelSize.MaxSize = PANEL_MAX
	panelSize.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.Parent = panel

	UIKit.label(panel, {
		name = "Title",
		position = UDim2.fromOffset(0, 0),
		size = UDim2.new(1, -40, 0, 40),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.hero,
		color = UIKit.C.text,
		text = "THE INDEX",
		zIndex = 11,
	})

	local close = UIKit.button(panel, {
		name = "Close",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.fromOffset(32, 32),
		text = "X",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.text,
		fillColor = UIKit.C.empty,
		cornerRadius = UIKit.Radius.slot,
		zIndex = 12,
	})

	buildDetailColumn(panel)

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroller"
	scroller.Position = UDim2.fromOffset(DETAIL_WIDTH + COLUMN_GAP, HEADER_H)
	scroller.Size = UDim2.new(1, -(DETAIL_WIDTH + COLUMN_GAP), 1, -HEADER_H)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = UIKit.C.dim
	scroller.CanvasSize = UDim2.fromScale(0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ZIndex = 11
	scroller.Parent = panel

	-- Keep the canvas (headers, their right-aligned count, and the last grid column)
	-- clear of the scrollbar that sits on the scroller's right edge.
	local scrollerPad = Instance.new("UIPadding")
	scrollerPad.PaddingRight = UDim.new(0, 12)
	scrollerPad.Parent = scroller

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 14)
	listLayout.Parent = scroller

	for i, stage in Stages.DEFS do
		buildStageSection(scroller, i, stage)
	end

	local function toggle()
		panel.Visible = not panel.Visible
	end
	button.MouseButton1Click:Connect(toggle)
	close.MouseButton1Click:Connect(toggle)

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

--- Repaint every tile for one item (there can be more than one — see itemTiles'
--- comment) from the current discovered set and selection. Called once per item on
--- every discovery — cheap, since a player finds new items far less than once a
--- second, and it keeps the panel correct live without having to be open to update.
local function renderItem(item: any)
	local tiles = itemTiles[item.id]
	if tiles == nil then
		return
	end

	local found = discovered[item.id] == true
	local rarityColor = Rarity.get(item.rarity).color
	local isSelected = selectedId == item.id

	for _, tile in tiles do
		tile.mark.Visible = not found
		tile.nameLabel.Visible = found
		if found then
			tile.nameLabel.Text = item.name
			tile.nameLabel.TextColor3 = rarityColor
			tile.button.BackgroundColor3 = UIKit.C.panel
			tile.button.BackgroundTransparency = 0.15
			tile.stroke.Color = rarityColor
			tile.stroke.Thickness = if isSelected then UIKit.Stroke.selected else UIKit.Stroke.thin
		else
			tile.button.BackgroundColor3 = UIKit.C.empty
			tile.button.BackgroundTransparency = 0.45
			tile.stroke.Color = UIKit.C.stroke
			tile.stroke.Thickness = UIKit.Stroke.thin
		end
	end
end

local function renderDetail()
	local d = ui.detail
	if selectedId == nil or not discovered[selectedId] then
		d.body.Visible = false
		d.hint.Visible = true
		return
	end

	local item = Items.get(selectedId)
	local rarity = Rarity.get(item.rarity)
	d.hint.Visible = false
	d.body.Visible = true

	d.name.Text = item.name
	d.name.TextColor3 = rarity.color

	d.rarity.Text = item.rarity
	d.rarity.TextColor3 = rarity.color
	d.value.Text = formatValue(item.baseValue)
	d.odds.Text = Items.oddsText(item.odds)
	d.appeal.Text = item.appeal

	local names = {}
	for _, stageId in item.stages do
		table.insert(names, Stages.get(stageId).name)
	end
	d.foundIn.Text = table.concat(names, ", ")

	d.flavor.Text = item.flavor
end

local function renderStageCount(stageId: number)
	local label = stageCountLabels[stageId]
	if label == nil then
		return
	end

	local found, total = 0, 0
	for _, item in itemsByStage[stageId] do
		total += 1
		if discovered[item.id] then
			found += 1
		end
	end
	label.Text = string.format("%d/%d", found, total)
end

local function renderTotal()
	ui.detail.total.Text = string.format("%d / %d found", discoveredCount(), totalItems)
end

local function renderAll()
	for _, item in Items.DEFS do
		renderItem(item)
	end
	for _, stage in Stages.DEFS do
		renderStageCount(stage.id)
	end
	renderTotal()
	renderDetail()
end

-- ── Selection ───────────────────────────────────────────────────────

--- Click handler for a tile. "?" tiles are inert — an undiscovered id is refused
--- here rather than gated on the button, so there is one place the rule lives.
--- Clicking the selected tile again clears the detail column.
function Index.select(id: string)
	if not discovered[id] then
		return
	end

	local previous = selectedId
	selectedId = if previous == id then nil else id

	if previous ~= nil and previous ~= selectedId then
		renderItem(Items.get(previous))
	end
	if selectedId ~= nil then
		renderItem(Items.get(selectedId))
	end
	renderDetail()
end

-- ── Lifecycle ────────────────────────────────────────────────────────

function Index.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("IndexState").OnClientEvent:Connect(function(payload)
		discovered = payload or {}
		renderAll()
	end)

	-- The free top-up: every Unearthed fire already carries the itemId of whatever
	-- was just dug up, discovered or not before this moment.
	Net.get("Unearthed").OnClientEvent:Connect(function(info)
		if info and info.itemId and not discovered[info.itemId] then
			discovered[info.itemId] = true
			local item = Items.get(info.itemId)
			renderItem(item)
			for _, stageId in item.stages do
				renderStageCount(stageId)
			end
			renderTotal()
		end
	end)

	renderAll()
end

return Index
