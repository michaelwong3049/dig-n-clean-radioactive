--[[
	GearController.lua — the Gear tile, and the loadout panel it opens. The tile sits
	alone on the right-edge grid's third row, under Nukes, built by HudTile like the
	other four.

	THE PANEL IS EVERY TIER YOU OWN, ON EVERY TRACK, and a button to switch to it from
	anywhere. One tab per track (Gear.TRACKS order), one row per owned rung: its live
	model (GearArt, the shop card's own picture), its name and stats, and EQUIP -- or
	IN HAND / WEARING on the one you already have. Buying still happens at a stall; this
	only moves `gear[track]` between tiers you paid for (ShopService.equipAnywhere, which
	refuses mid-haul and mid-wash).

	NOTHING IS STREAMED. The loadout is asked for (GearAction "list") when the panel
	opens, and an EQUIP answers with the loadout after it. A shop purchase while the
	panel is up re-asks on the StationResult it produces.

	Its look is the Nukes panel's (the Shop's FIELD slate, LuckiestGuy / FredokaOne in
	INK outlines), with each tab in its stall's accent.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)
local GearArt = require(script.Parent.Parent.GearArt)

local GearPanel = {}

-- THE GEAR TILE: the grid's third row, left, under Nukes. An orange glow behind the
-- red toolbox (Index violet, Shop green, Nukes yellow, Warp cyan were taken).
local TILE_SLOT = 5
local TILE_COLOR = Color3.fromRGB(255, 128, 48)
local TILE_LIGHT = Color3.fromRGB(255, 208, 170)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	row = Color3.fromHex("252A30"),
	well = Color3.fromHex("14171A"),
	light = Color3.fromHex("E6EAF0"),
	dim = Color3.fromHex("9AA3AD"),
	gold = Color3.fromHex("F5C24B"),
	buy = Color3.fromHex("3FB35A"),
	buyHover = Color3.fromHex("52C96C"),
	off = Color3.fromHex("4A4F55"),
	close = Color3.fromHex("E5484D"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	headline = Enum.Font.LuckiestGuy,
	label = Enum.Font.FredokaOne,
}

-- The stall accents (StationController.STALL_ACCENT, build/Shops' awnings), and the
-- Aura's amber, which has no stall colour of its own.
local ACCENT: { [string]: Color3 } = {
	Detector = Color3.fromHex("E0714E"),
	Magnet = Color3.fromHex("4E9AAE"),
	Cleaner = Color3.fromHex("9560B0"),
	Aura = Color3.fromHex("F5C24B"),
}
-- What each tab says. The Cleaner rung is the hose on your bay's mast.
local TAB_TEXT: { [string]: string } = {
	Detector = "DETECTOR",
	Magnet = "MAGNET",
	Cleaner = "HOSE",
	Aura = "AURA",
}

local PANEL_W = 640
local PANEL_H = 500
local PAD = 20
local HEADER_H = 58
local TABS_H = 44
local NOTICE_H = 26
local LIST_TOP = HEADER_H + TABS_H + NOTICE_H + 8
local ROW_H = 76
local ART_W = 112
local ART_H = ROW_H - 12
local BUTTON_W = 132
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BUSY_TIMEOUT = 2

local actionRemote: RemoteEvent? = nil
local ui: any = {}
local latest: any = nil
local selected = Gear.TRACKS[1]
local busy = false

-- ── Helpers ─────────────────────────────────────────────────────────

--- A label in the panel's cartoon voice: white, INK-outlined. `props` are set as-is.
local function inked(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = PANEL.white
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(label :: any)[key] = value
	end
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = PANEL.ink
	stroke.Thickness = math.max(2, label.TextSize * 0.1)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

--- "RADIUS 16 · DEPTH 9 · LUCK 1.1" out of the server's stat cells.
local function statLine(stats: { any }): string
	local parts = {}
	for _, cell in stats do
		table.insert(parts, `{cell.label} {cell.value}`)
	end
	return table.concat(parts, "  \u{00B7}  ")
end

local function trackEntry(track: string): any
	if latest == nil then
		return nil
	end
	for _, entry in latest.tracks do
		if entry.track == track then
			return entry
		end
	end
	return nil
end

local function ask()
	if actionRemote then
		actionRemote:FireServer("list")
	end
end

local function setBusy(value: boolean)
	busy = value
	ui.notice.Text = if value then "..." else ui.notice.Text
end

-- ── Rows ────────────────────────────────────────────────────────────

--- One owned rung: live model in a well on the left, name + tier + stats, and EQUIP.
local function row(parent: Instance, order: number, track: string, entry: any)
	local accent = ACCENT[track] or PANEL.gold
	local frame = Instance.new("Frame")
	frame.Name = `Tier{entry.tier}`
	frame.Size = UDim2.new(1, -8, 0, ROW_H)
	frame.BackgroundColor3 = PANEL.row
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.ZIndex = 13
	frame.Parent = parent
	round(frame, 12)
	edge(frame, if entry.current then accent else PANEL.ink, if entry.current then 3 else 2)

	local well = Instance.new("Frame")
	well.Name = "Art"
	well.Position = UDim2.fromOffset(6, 6)
	well.Size = UDim2.fromOffset(ART_W, ART_H)
	well.BackgroundColor3 = PANEL.well
	well.BorderSizePixel = 0
	well.ClipsDescendants = true
	well.ZIndex = 14
	well.Parent = frame
	round(well, 9)
	local viewport = GearArt.viewport(well)
	viewport.ZIndex = 15
	GearArt.show(viewport, track, entry.tier, ART_W / ART_H)

	local textLeft = 6 + ART_W + 14
	local textWidth = -textLeft - BUTTON_W - 22
	inked(frame, {
		Name = "Name",
		Text = entry.name,
		Font = PANEL.label,
		TextSize = 21,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, textWidth, 0, 24),
		Position = UDim2.fromOffset(textLeft, 8),
		ZIndex = 14,
	})
	inked(frame, {
		Name = "Tier",
		Text = `TIER {entry.tier}`,
		Font = PANEL.label,
		TextSize = 14,
		TextColor3 = accent,
		Size = UDim2.new(1, textWidth, 0, 16),
		Position = UDim2.fromOffset(textLeft, 32),
		ZIndex = 14,
	})
	inked(frame, {
		Name = "Stats",
		Text = statLine(entry.stats),
		Font = PANEL.label,
		TextSize = 13,
		TextColor3 = PANEL.dim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, textWidth, 0, 16),
		Position = UDim2.fromOffset(textLeft, 50),
		ZIndex = 14,
	})

	local button = Instance.new("TextButton")
	button.Name = "Equip"
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -12, 0.5, 0)
	button.Size = UDim2.fromOffset(BUTTON_W, 42)
	button.Font = PANEL.headline
	button.TextSize = 19
	button.TextColor3 = PANEL.white
	button.ZIndex = 15
	button.Parent = frame
	round(button, 12)
	edge(button, PANEL.ink, 3)

	if entry.current then
		-- The one you have: a ghost button that says so, in the track's accent.
		button.Text = if track == "Aura" then "WEARING" else "IN HAND"
		button.BackgroundColor3 = PANEL.well
		button.TextColor3 = accent
		button.Active = false
		return
	end

	button.Text = "EQUIP"
	button.BackgroundColor3 = PANEL.buy
	button.MouseEnter:Connect(function()
		TweenService:Create(button, HOVER, { BackgroundColor3 = PANEL.buyHover }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, HOVER, { BackgroundColor3 = PANEL.buy }):Play()
	end)
	button.Activated:Connect(function()
		if busy or actionRemote == nil then
			return
		end
		setBusy(true)
		button.Text = "..."
		button.BackgroundColor3 = PANEL.off
		actionRemote:FireServer("equip", track, entry.tier)
		-- The answer is a GearList carrying `notice`; if it never comes (the server's
		-- cooldown swallowed a double-press) the panel un-sticks on its own.
		task.delay(BUSY_TIMEOUT, function()
			if busy then
				busy = false
				ask()
			end
		end)
	end)
end

local function paintTabs()
	for track, tab in ui.tabs do
		local on = track == selected
		local accent = ACCENT[track] or PANEL.gold
		tab.BackgroundColor3 = if on then accent else PANEL.well
		tab.TextColor3 = if on then PANEL.white else PANEL.dim
		local entry = trackEntry(track)
		local count = if entry then #entry.owned else 0
		tab.Text = if count > 0 then `{TAB_TEXT[track] or track} {count}` else TAB_TEXT[track] or track
	end
end

local function render()
	paintTabs()
	local scroll: ScrollingFrame = ui.scroll
	for _, child in scroll:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end

	local entry = trackEntry(selected)
	if entry == nil then
		return
	end
	-- Best first: the rung you most likely want sits at the top.
	local owned = table.clone(entry.owned)
	table.sort(owned, function(a, b)
		return a.tier > b.tier
	end)
	for index, item in owned do
		row(scroll, index, selected, item)
	end
	if #owned <= 1 then
		inked(scroll, {
			Name = "Hint",
			Text = "Buy more at the shops to switch between them here",
			Font = PANEL.label,
			TextSize = 15,
			TextColor3 = PANEL.dim,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = #owned + 1,
			ZIndex = 13,
		})
	end
	scroll.CanvasPosition = Vector2.zero
end

local function selectTrack(track: string)
	if selected == track then
		return
	end
	selected = track
	render()
end

-- ── Open / close ────────────────────────────────────────────────────

function GearPanel.open()
	local panel = ui.panel
	if panel == nil or panel.Visible or HudTile.blocked("Gear") then
		return
	end
	ui.notice.Text = ""
	panel.Visible = true
	ask()
	if ui.scale then
		ui.scale.Scale = 0.85
		TweenService:Create(ui.scale, OPEN, { Scale = 1 }):Play()
	end
end

function GearPanel.close()
	if ui.panel then
		ui.panel.Visible = false
	end
end

function GearPanel.toggle()
	if ui.panel and ui.panel.Visible then
		GearPanel.close()
	else
		GearPanel.open()
	end
end

local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "GearPanel"
	gui.ResetOnSpawn = false
	-- Same call as the Shop, Index and Nukes panels: a centred modal that respects the
	-- topbar inset and sits over the whole HUD (RadHud is 100).
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = PANEL.panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 10
	panel.Parent = canvas
	round(panel, 20)
	edge(panel, PANEL.ink, 4)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PAD - 6)
	padding.PaddingBottom = UDim.new(0, PAD)
	padding.PaddingLeft = UDim.new(0, PAD)
	padding.PaddingRight = UDim.new(0, PAD)
	padding.Parent = panel

	inked(panel, {
		Name = "Title",
		Text = "GEAR",
		Font = PANEL.headline,
		TextSize = 38,
		Size = UDim2.fromOffset(200, 46),
		ZIndex = 11,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 2)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = PANEL.close
	close.Font = PANEL.headline
	close.TextSize = 24
	close.TextColor3 = PANEL.white
	close.Text = "X"
	close.ZIndex = 11
	close.Parent = panel
	round(close, 12)
	edge(close, PANEL.ink, 3)
	close.Activated:Connect(GearPanel.close)

	-- One tab per track, sharing the row's width.
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.Position = UDim2.fromOffset(0, HEADER_H)
	tabs.Size = UDim2.new(1, 0, 0, TABS_H - 6)
	tabs.BackgroundTransparency = 1
	tabs.ZIndex = 11
	tabs.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabs

	ui.tabs = {}
	local count = #Gear.TRACKS
	for index, track in Gear.TRACKS do
		local tab = Instance.new("TextButton")
		tab.Name = track
		tab.AutoButtonColor = false
		tab.LayoutOrder = index
		tab.Size = UDim2.new(1 / count, -8 * (count - 1) / count, 1, 0)
		tab.Font = PANEL.headline
		tab.TextSize = 18
		tab.Text = TAB_TEXT[track] or track
		tab.ZIndex = 12
		tab.Parent = tabs
		round(tab, 12)
		edge(tab, PANEL.ink, 3)
		tab.Activated:Connect(function()
			selectTrack(track)
		end)
		ui.tabs[track] = tab
	end

	local notice = inked(panel, {
		Name = "Notice",
		Text = "",
		Font = PANEL.label,
		TextSize = 16,
		TextColor3 = PANEL.light,
		Size = UDim2.new(1, 0, 0, NOTICE_H - 4),
		Position = UDim2.fromOffset(4, HEADER_H + TABS_H + 2),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 11,
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(0, LIST_TOP)
	scroll.Size = UDim2.new(1, 0, 1, -LIST_TOP)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = PANEL.dim
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ZIndex = 12
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = scroll
	local inset = Instance.new("UIPadding")
	inset.PaddingLeft = UDim.new(0, 2)
	inset.PaddingTop = UDim.new(0, 2)
	inset.PaddingBottom = UDim.new(0, 4)
	inset.Parent = scroll

	ui.panel = panel
	ui.scale = scale
	ui.notice = notice
	ui.scroll = scroll
	paintTabs()
	return gui
end

-- ── The tile ────────────────────────────────────────────────────────

function GearPanel.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local tile = HudTile.build({
		name = "GearButton",
		caption = "Gear",
		slot = TILE_SLOT,
		color = TILE_COLOR,
		light = TILE_LIGHT,
		image = Artwork.IMAGE.toolbox,
		onActivated = GearPanel.toggle,
	})
	tile.Parent = playerGui
	buildPanel().Parent = playerGui
	HudTile.registerPanel("Gear", ui.panel)

	actionRemote = Net.get("GearAction")
	Net.get("GearList").OnClientEvent:Connect(function(list)
		latest = list
		busy = false
		ui.notice.Text = if list and list.notice then string.upper(list.notice) else ""
		render()
	end)

	-- A purchase at a stall while the panel is up adds a row: re-ask.
	Net.get("StationResult").OnClientEvent:Connect(function()
		if ui.panel and ui.panel.Visible then
			ask()
		end
	end)
end

return GearPanel
