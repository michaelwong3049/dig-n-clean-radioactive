--[[
	IndexController.lua — the item index. Browse every item that can be found, by
	stage, and see which ones you've actually held.

	THIS IS THE GUI HALF OF PLAN §10.10, NOT THE WHOLE THING. The full "Museum /
	Collection Wall" — a physical base-camp gallery, stage-completion luck bonuses —
	is explicitly a long-term / post-MVP feature there. This is scoped to exactly
	what was asked for: a small button, bottom-right, that opens a browsable list.
	No new world geometry, no completion bonus.

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

local discovered: { [string]: boolean } = {}
local totalItems = #Items.DEFS

local ui = {}

-- An item can belong to more than one stage (several span {3, 4}), so it gets a
-- SEPARATE row built per stage section it appears in — this has to be a list per
-- item, not one row, or discovering it would only ever repaint whichever stage's
-- row happened to be built last.
type ItemRow = { nameLabel: TextLabel, flavorLabel: TextLabel, oddsLabel: TextLabel }
local itemRows: { [string]: { ItemRow } } = {}
local stageCountLabels: { [number]: TextLabel } = {}

--- itemId -> its StageDef list, precomputed once. Items.DEFS is small (41 at MVP
--- scope) so this is cheap, and it means the panel build below is a lookup per
--- item rather than an `stages` array scan per item per stage.
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

-- ── Build ───────────────────────────────────────────────────────────

local function discoveredCount(): number
	local n = 0
	for _ in discovered do
		n += 1
	end
	return n
end

--- One item row: the name (rarity-coloured if discovered, dim "???" otherwise) and
--- its flavor text underneath, only shown once discovered — PLAN's own framing for
--- the museum is "have you ever held it", not "do you know it exists".
local function buildItemRow(parent: Instance, layoutOrder: number, item: any)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundTransparency = 1
	row.LayoutOrder = layoutOrder
	row.Parent = parent

	local nameLabel = UIKit.label(row, {
		name = "Name",
		position = UDim2.fromOffset(12, 0),
		size = UDim2.new(1, -140, 0, 20),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		text = "???",
		zIndex = 2,
	})

	-- The authored "1 in N", right-aligned on the name line. Blank until the item is
	-- discovered, same reveal rule the name and flavor already follow -- the odds are
	-- part of an item's identity, so you learn them by holding it.
	local oddsLabel = UIKit.label(row, {
		name = "Odds",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -12, 0, 0),
		size = UDim2.fromOffset(116, 20),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Right,
		text = "",
		zIndex = 2,
	})

	local flavorLabel = UIKit.label(row, {
		name = "Flavor",
		position = UDim2.fromOffset(12, 20),
		size = UDim2.new(1, -24, 0, 18),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		text = "",
		zIndex = 2,
	})

	local rows = itemRows[item.id]
	if rows == nil then
		rows = {}
		itemRows[item.id] = rows
	end
	table.insert(rows, { nameLabel = nameLabel, flavorLabel = flavorLabel, oddsLabel = oddsLabel })
end

--- One stage section: a header (name + this stage's own discovered count) and its
--- item rows, or an honest "nothing catalogued here yet" line for stages 5-6, which
--- stock nothing at MVP scope — flagged rather than silently skipped, same ethic
--- DigService's own console warnings already use for the same gap.
local function buildStageSection(parent: Instance, layoutOrder: number, stage: any)
	local section = Instance.new("Frame")
	section.Name = `Stage{stage.id}`
	section.Size = UDim2.new(1, 0, 0, 0)
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.BackgroundTransparency = 1
	section.LayoutOrder = layoutOrder
	section.Parent = parent

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
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
		zIndex = 2,
	})

	local stageItems = itemsByStage[stage.id]
	local countLabel = UIKit.label(header, {
		name = "Count",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 0),
		size = UDim2.fromOffset(70, 28),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Right,
		text = "",
		zIndex = 2,
	})

	if #stageItems == 0 then
		UIKit.label(section, {
			name = "Empty",
			size = UDim2.new(1, 0, 0, 24),
			font = UIKit.Font.body,
			textSize = UIKit.TextSize.body,
			color = UIKit.C.dim,
			text = "nothing catalogued here yet",
			zIndex = 2,
		})
		countLabel.Text = ""
		stageCountLabels[stage.id] = countLabel
		return
	end

	table.sort(stageItems, function(a, b)
		return Rarity.DEFS[a.rarity].order < Rarity.DEFS[b.rarity].order
	end)

	for i, item in stageItems do
		buildItemRow(section, i + 1, item)
	end

	stageCountLabels[stage.id] = countLabel
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "IndexHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- The button. BOTTOM-LEFT now, not bottom-right — stacked directly above the cash
	-- badge, which sits directly above the meter, on the meter's own left margin. It
	-- has moved twice: first from inside the instrument band out to the (then empty)
	-- bottom-right corner beside the newly-relocated radar scope, and now across to
	-- the left column entirely, out of the scope's way, above the money.
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

	-- The panel. Same true-screen-centre-biased-upward formula StationController
	-- uses, so it never sits inside the dock's own reserved band.
	local panel, panelStroke = UIKit.panel(gui, {
		name = "Panel",
		size = UDim2.fromOffset(720, 640),
		position = UDim2.new(0.5, 0, 0.5, -Dock.RESERVE / 2),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = UIKit.C.panel,
		transparency = 0.05,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		zIndex = 10,
		visible = false,
	})
	ui.panel = panel

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

	ui.totalLabel = UIKit.label(panel, {
		name = "Total",
		position = UDim2.fromOffset(0, 44),
		size = UDim2.new(1, -40, 0, 20),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		text = "",
		zIndex = 11,
	})

	local close, closeStroke = UIKit.button(panel, {
		name = "Close",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 0),
		size = UDim2.fromOffset(32, 32),
		text = "X",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.text,
		fillColor = UIKit.C.empty,
		cornerRadius = UIKit.Radius.slot,
		zIndex = 12,
	})

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroller"
	scroller.Position = UDim2.fromOffset(0, 76)
	scroller.Size = UDim2.new(1, 0, 1, -76)
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = UIKit.C.dim
	scroller.CanvasSize = UDim2.fromScale(0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ZIndex = 11
	scroller.Parent = panel

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

--- Repaint every row for one item (there can be more than one — see itemRows'
--- comment) from the current discovered set. Called once per item on every
--- discovery — cheap, since a player finds new items far less than once a second,
--- and it keeps the panel correct live without having to be open to update.
local function renderItem(item: any)
	local rows = itemRows[item.id]
	if rows == nil then
		return
	end

	local found = discovered[item.id] == true
	local color = if found then Rarity.get(item.rarity).color else UIKit.C.dim
	for _, row in rows do
		row.nameLabel.Text = if found then item.name else "???"
		row.nameLabel.TextColor3 = color
		row.flavorLabel.Text = if found then item.flavor else ""
		row.oddsLabel.Text = if found then Items.oddsText(item.odds) else ""
	end
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

local function renderAll()
	for _, item in Items.DEFS do
		renderItem(item)
	end
	for _, stage in Stages.DEFS do
		renderStageCount(stage.id)
	end
	ui.totalLabel.Text = string.format("%d / %d found", discoveredCount(), totalItems)
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
			ui.totalLabel.Text = string.format("%d / %d found", discoveredCount(), totalItems)
		end
	end)

	renderAll()
end

return Index
