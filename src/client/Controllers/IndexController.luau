--[[
	IndexController.lua — the item index. Browse every item that can be found, by
	zone, and see which ones you've actually held.

	THIS IS THE GUI HALF OF PLAN §10.10, NOT THE WHOLE THING. The full "Museum /
	Collection Wall" — a physical base-camp gallery, zone-completion luck bonuses —
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
local Zones = require(Shared.Config.Zones)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Index = {}

local BUTTON_SIZE = 72

local discovered: { [string]: boolean } = {}
local totalItems = #Items.DEFS

local ui = {}

-- An item can belong to more than one zone (several span {3, 4}), so it gets a
-- SEPARATE row built per zone section it appears in — this has to be a list per
-- item, not one row, or discovering it would only ever repaint whichever zone's
-- row happened to be built last.
type ItemRow = { nameLabel: TextLabel, flavorLabel: TextLabel }
local itemRows: { [string]: { ItemRow } } = {}
local zoneCountLabels: { [number]: TextLabel } = {}

--- itemId -> its ZoneDef list, precomputed once. Items.DEFS is small (41 at MVP
--- scope) so this is cheap, and it means the panel build below is a lookup per
--- item rather than an `zones` array scan per item per zone.
local itemsByZone: { [number]: { any } } = {}
for _, zone in Zones.DEFS do
	itemsByZone[zone.id] = {}
end
for _, item in Items.DEFS do
	for _, zoneId in item.zones do
		if itemsByZone[zoneId] then
			table.insert(itemsByZone[zoneId], item)
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
		size = UDim2.new(1, -24, 0, 20),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		text = "???",
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
	table.insert(rows, { nameLabel = nameLabel, flavorLabel = flavorLabel })
end

--- One zone section: a header (name + this zone's own discovered count) and its
--- item rows, or an honest "nothing catalogued here yet" line for zones 5-6, which
--- stock nothing at MVP scope — flagged rather than silently skipped, same ethic
--- DigService's own console warnings already use for the same gap.
local function buildZoneSection(parent: Instance, layoutOrder: number, zone: any)
	local section = Instance.new("Frame")
	section.Name = `Zone{zone.id}`
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
		name = "ZoneName",
		size = UDim2.new(1, -80, 1, 0),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.text,
		text = string.upper(zone.name),
		zIndex = 2,
	})

	local zoneItems = itemsByZone[zone.id]
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

	if #zoneItems == 0 then
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
		zoneCountLabels[zone.id] = countLabel
		return
	end

	table.sort(zoneItems, function(a, b)
		return Rarity.DEFS[a.rarity].order < Rarity.DEFS[b.rarity].order
	end)

	for i, item in zoneItems do
		buildItemRow(section, i + 1, item)
	end

	zoneCountLabels[zone.id] = countLabel
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "IndexHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- The button. Bottom-right, mirroring HudController's meter at bottom-left —
	-- both anchor to the same INSTRUMENT_BOTTOM baseline so the dock reads as one
	-- deliberate row, not two unrelated floating pieces.
	local button, buttonStroke = UIKit.button(gui, {
		name = "IndexButton",
		size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 1, -Dock.INSTRUMENT_BOTTOM),
		anchorPoint = Vector2.new(1, 1),
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

	for i, zone in Zones.DEFS do
		buildZoneSection(scroller, i, zone)
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
	end
end

local function renderZoneCount(zoneId: number)
	local label = zoneCountLabels[zoneId]
	if label == nil then
		return
	end

	local found, total = 0, 0
	for _, item in itemsByZone[zoneId] do
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
	for _, zone in Zones.DEFS do
		renderZoneCount(zone.id)
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
			for _, zoneId in item.zones do
				renderZoneCount(zoneId)
			end
			ui.totalLabel.Text = string.format("%d / %d found", discoveredCount(), totalItems)
		end
	end)

	renderAll()
end

return Index
