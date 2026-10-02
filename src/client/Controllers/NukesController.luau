--[[
	NukesController.lua — the Nukes tile, and the panel it opens. The tile is the
	middle of the right-edge column (Gear, Nukes, Warp), built by HudTile like the others.

	THE PANEL SLIDES IN FROM THE RIGHT EDGE and docks a small gap short of it, over the
	tile column (on request, after a reference picture): a tall near-black tray under a
	lighter grey header box, one row per nuke on your stands, best first. Each row is
	the nuke's own model, its name and what it pays per second -- the rate its stand
	card prints, duplicate damping and all -- in its RARITY COLOUR (Config/Rarity's
	`color`; Anomaly cycles Rarity.anomalyHue), and a red UNEQUIP that sends it back
	to the bag (ExhibitService.unequip, the stand prompt's own plain take). The bag is
	deliberately not listed -- the hotbar already shows it.

	EQUIP BEST hangs under the tray (ExhibitService.equipBest): fill every stand with the
	set that earns the most, swapping weaker pieces back into the bag. It works from
	anywhere, which is the point of it living on the HUD -- wash a nuke, press it, keep
	going. The server picks everything; the buttons send bare verbs (+ a uid).

	NOTHING IS STREAMED. The list is asked for (NukeAction "list") when the panel opens,
	and again whenever CarryState or IncomeState says something moved while it is
	showing. Closed, it costs nothing. Rows are keyed by uid and kept across refreshes,
	so a model is framed once, not on every answer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Payload = require(Shared.Config.Payload)
local Merge = require(Shared.Config.Merge)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)
local ItemArt = require(script.Parent.Parent.ItemArt)

local Nukes = {}

-- THE NUKES TILE: middle of the right-edge column (HudTile), a hazard-yellow
-- glow behind the green nuke.
local TILE_SLOT = 2
local TILE_COLOR = Color3.fromRGB(255, 207, 31)
local TILE_LIGHT = Color3.fromRGB(255, 240, 160)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The reference's look: a near-black tray under a lighter grey header box, blacker
-- rows with a grey well behind each model, chunky red / green buttons, every word in
-- FredokaOne with a black outline.
local PANEL = {
	tray = Color3.fromHex("17191C"),
	header = Color3.fromHex("3A3E45"),
	row = Color3.fromHex("0C0D0F"),
	well = Color3.fromHex("4A4F57"),
	dim = Color3.fromHex("A9B0B8"),
	gold = Color3.fromHex("F5C24B"),
	red = Color3.fromHex("E3201B"),
	redHover = Color3.fromHex("F5433D"),
	green = Color3.fromHex("33D62F"),
	greenHover = Color3.fromHex("52E84E"),
	-- Equip Best wears the Gear panel's EQUIP (GearController): its green, square,
	-- a 3px black edge, plain white Gotham Black caps.
	equip = Color3.fromHex("3FB35A"),
	equipHover = Color3.fromHex("52C96C"),
	equipFont = Enum.Font.GothamBlack,
	off = Color3.fromHex("5C6167"),
	ink = Color3.fromHex("111214"),
	white = Color3.new(1, 1, 1),
	font = Enum.Font.FredokaOne,
}

-- Design px (UIKit.canvas: a 1280x720 screen).
-- Right up to the screen edge, a small gap short of it: open, it covers the tile
-- column (Gear / Nukes / Warp) on request; the ">" tab closes it.
local SIDE_MARGIN = 12
local PANEL_W = 430
local PANEL_H = 470
-- The pair (tray + Equip Best under it) sits this far above the right edge's middle.
local RAISE = 30
local PAD = 10
-- The lighter header box across the tray's top: title + rate left, count right.
local HEADER_H = 48
local NOTICE_H = 20
local LIST_TOP = HEADER_H + 4 + NOTICE_H + 4
local ROW_H = 82
local ART_W = 86
local UNEQUIP_W = 118
local UNEQUIP_H = 46
local EQUIP_W = 240
local EQUIP_H = 58
local EQUIP_GAP = 18
local TAB_W = 34
local TAB_H = 52
-- Air between the ">" tab and the tray.
local TAB_GAP = 16
-- The names' moving rarity shimmer: how far the bright band lifts the colour toward
-- white, and seconds per sweep.
local SHIMMER_LIGHT = 0.75
local SHIMMER_PERIOD = 2.2

-- The slide: a quick ease out on the way in, a quicker ease in on the way out.
local SLIDE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local OPEN_POS = UDim2.new(1, -SIDE_MARGIN, 0.5, -RAISE)
local CLOSED_POS = UDim2.new(1, PANEL_W + TAB_W + TAB_GAP + 40, 0.5, -RAISE)

-- The fastest the panel re-asks for its list while CarryState / IncomeState chatter.
local REFRESH_GAP = 0.5

local actionRemote: RemoteEvent? = nil
local ui: any = {}
local latest: any = nil
local busy = false
local lastAsk = 0
local askQueued = false
local slideToken = 0

-- ── Helpers ─────────────────────────────────────────────────────────

--- "$2.00/s" up to "$1.2M/s" -- ExhibitService.formatRate's ladder, carried into millions and billions.
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

local function edge(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	-- Square corners everywhere, on request: mitred, so the outline stays sharp too.
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Parent = parent
	return stroke
end

--- A label in the panel's voice: FredokaOne, black-outlined. `props` are set as-is.
local function inked(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = PANEL.font
	label.TextColor3 = PANEL.white
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(label :: any)[key] = value
	end
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = PANEL.ink
	stroke.Thickness = math.max(2, label.TextSize * 0.11)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = parent
	return label
end

--- A chunky button: `fill` face, black outline, outlined white label, hover tint.
local function chunky(parent: Instance, name: string, text: string, size: Vector2, textSize: number, fill: Color3, hover: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(size.X, size.Y)
	button.BackgroundColor3 = fill
	button.BorderSizePixel = 0
	button.Text = ""
	button.Parent = parent
	edge(button, PANEL.ink, 3)
	-- A lighter lip along the top, the reference's bevel.
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BackgroundColor3 = PANEL.white
	lip.BackgroundTransparency = 0.78
	lip.BorderSizePixel = 0
	lip.Position = UDim2.fromOffset(4, 3)
	lip.Size = UDim2.new(1, -8, 0.32, 0)
	lip.Parent = button
	inked(button, {
		Name = "Label",
		Text = text,
		TextSize = textSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	})
	button:SetAttribute("Fill", fill)
	button.MouseEnter:Connect(function()
		if button.Active then
			TweenService:Create(button, HOVER, { BackgroundColor3 = hover }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		if button.Active then
			TweenService:Create(button, HOVER, { BackgroundColor3 = button:GetAttribute("Fill") }):Play()
		end
	end)
	return button
end

--- Grey a chunky button out (or bring it back) and set its label.
local function setButton(button: TextButton, enabled: boolean, text: string)
	button.Active = enabled
	button.AutoButtonColor = false
	button.BackgroundColor3 = if enabled then button:GetAttribute("Fill") else PANEL.off
	local label = button:FindFirstChild("Label") :: TextLabel
	label.Text = text
end

local function rarityColor(name: string): Color3
	local ok, def = pcall(Rarity.get, name)
	return if ok and def then def.color else PANEL.dim
end

--- Ask the server for a fresh list, at most once per REFRESH_GAP; a burst of asks
--- collapses into one trailing request.
local function ask()
	local remote = actionRemote
	if remote == nil then
		return
	end
	local wait = REFRESH_GAP - (os.clock() - lastAsk)
	if wait <= 0 then
		lastAsk = os.clock()
		remote:FireServer("list")
	elseif not askQueued then
		askQueued = true
		task.delay(wait, function()
			askQueued = false
			if ui.panel and ui.panel.Visible then
				lastAsk = os.clock()
				remote:FireServer("list")
			end
		end)
	end
end

-- ── Rows ────────────────────────────────────────────────────────────

type Row = {
	frame: Frame,
	art: ViewportFrame,
	name: TextLabel,
	stars: TextLabel,
	unequip: TextButton,
	entry: any,
	pending: boolean,
}

-- Rows on screen, by uid, kept across refreshes.
local rows: { [string]: Row } = {}

--- The stand line under the name: stars, Merge Reactor stars, modifier.
local function starLine(entry: any): string
	local text = Rarity.starText(entry.rarity, entry.modifier, Payload.forUid(entry.uid), entry.bonus, Items.stageOf(entry.itemId))
	local merged = entry.merge or 0
	if merged > 0 then
		text ..= ` <font color="#{Merge.COLOR:ToHex()}">{Merge.text(merged)}</font>`
	end
	local qualities = Rarity.qualities(entry.modifier, entry.bonus)
	if #qualities > 0 then
		text ..= ` <font color="#{PANEL.dim:ToHex()}">{table.concat(qualities, " ")}</font>`
	end
	return text
end

local function paintUnequip(row: Row)
	if row.pending then
		setButton(row.unequip, false, "...")
	else
		setButton(row.unequip, true, "Unequip")
	end
end

local function newRow(parent: Instance, uid: string): Row
	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.Size = UDim2.new(1, -10, 0, ROW_H)
	frame.BackgroundColor3 = PANEL.row
	frame.BorderSizePixel = 0
	frame.Parent = parent
	edge(frame, PANEL.ink, 2)

	-- The model on its own grey block, filling the row's left end edge to edge.
	local well = Instance.new("Frame")
	well.Name = "Well"
	well.Size = UDim2.new(0, ART_W, 1, 0)
	well.BackgroundColor3 = PANEL.well
	well.BorderSizePixel = 0
	well.ClipsDescendants = true
	well.Parent = frame
	edge(well, PANEL.ink, 2)
	local art = ItemArt.newViewport(well)
	art.ZIndex = 2

	local textLeft = ART_W + 10
	local textW = -(textLeft + UNEQUIP_W + 16)
	local name = inked(frame, {
		Name = "Name",
		Text = "",
		TextSize = 21,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.fromOffset(textLeft, 4),
		Size = UDim2.new(1, textW, 0, 52),
	})
	-- The rarity shimmer: the name is white under a gradient in its rarity colour
	-- with a bright band that sweeps across it (RenderStepped moves `Offset`).
	local shimmer = Instance.new("UIGradient")
	shimmer.Name = "Shimmer"
	shimmer.Parent = name
	local stars = Instance.new("TextLabel")
	stars.Name = "Stars"
	stars.BackgroundTransparency = 1
	stars.Font = PANEL.font
	stars.TextSize = 16
	stars.TextColor3 = PANEL.gold
	stars.TextXAlignment = Enum.TextXAlignment.Left
	stars.TextTruncate = Enum.TextTruncate.AtEnd
	stars.RichText = true
	stars.Position = UDim2.fromOffset(textLeft, 56)
	stars.Size = UDim2.new(1, textW, 0, 20)
	stars.Parent = frame

	local unequip = chunky(frame, "Unequip", "Unequip", Vector2.new(UNEQUIP_W, UNEQUIP_H), 27, PANEL.red, PANEL.redHover)
	unequip.AnchorPoint = Vector2.new(1, 0.5)
	unequip.Position = UDim2.new(1, -10, 0.5, 0)

	local row: Row = {
		frame = frame,
		art = art,
		name = name,
		stars = stars,
		unequip = unequip,
		entry = nil,
		pending = false,
	}
	unequip.Activated:Connect(function()
		if not unequip.Active or row.pending or actionRemote == nil then
			return
		end
		row.pending = true
		paintUnequip(row)
		actionRemote:FireServer("unequip", uid)
		-- The answer is a NukeList with `notice`; if the server's cooldown swallowed
		-- it, the button comes back on its own.
		task.delay(2, function()
			if row.pending then
				row.pending = false
				paintUnequip(row)
			end
		end)
	end)
	return row
end

--- The name's shimmer gradient: its rarity colour with a lighter band in the middle
--- (Anomaly: the spectrum itself, re-hued every frame so it keeps cycling).
local function tint(row: Row, now: number)
	local shimmer = row.name:FindFirstChild("Shimmer") :: UIGradient
	if row.entry.rarity == "Anomaly" then
		local keys = {}
		for i = 0, 4 do
			local x = i / 4
			keys[i + 1] = ColorSequenceKeypoint.new(x, Rarity.anomalyHue(now / Rarity.ANOMALY_CYCLE + x * 0.5))
		end
		shimmer.Color = ColorSequence.new(keys)
		return
	end
	local color = rarityColor(row.entry.rarity)
	local bright = color:Lerp(PANEL.white, SHIMMER_LIGHT)
	shimmer.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.32, color),
		ColorSequenceKeypoint.new(0.5, bright),
		ColorSequenceKeypoint.new(0.68, color),
		ColorSequenceKeypoint.new(1, color),
	})
end

--- Slide every name's bright band across it, once per SHIMMER_PERIOD. The gradient is
--- twice the label's width of travel (-1 to 1), so the band enters and leaves cleanly.
local function sweep(now: number)
	local offset = ((now / SHIMMER_PERIOD) % 1) * 2 - 1
	for _, row in rows do
		local shimmer = row.name:FindFirstChild("Shimmer") :: UIGradient?
		if shimmer then
			shimmer.Offset = Vector2.new(if row.entry and row.entry.rarity == "Anomaly" then 0 else offset, 0)
		end
	end
end

local function render()
	local list = latest
	if list == nil then
		return
	end
	local scroll: ScrollingFrame = ui.scroll

	ui.count.Text = `{list.used}/{list.slots} on display`
	ui.rate.Text = `+{formatRate(list.rate)}`

	local displayed = table.clone(list.displayed)
	table.sort(displayed, function(a, b)
		return a.rate > b.rate
	end)

	local keep: { [string]: boolean } = {}
	for order, entry in displayed do
		keep[entry.uid] = true
		local row = rows[entry.uid]
		if row == nil then
			row = newRow(scroll, entry.uid)
			rows[entry.uid] = row
		end
		row.entry = entry
		row.pending = false
		row.frame.LayoutOrder = order
		row.name.Text = `{entry.name} ({formatRate(entry.rate)})`
		row.stars.Text = starLine(entry)
		tint(row, os.clock())
		paintUnequip(row)
		ItemArt.paint(row.art, {
			uid = entry.uid,
			itemId = entry.itemId,
			rarity = entry.rarity,
			identified = true,
		}, ART_W / (ROW_H - 12))
	end
	for uid, row in rows do
		if not keep[uid] then
			row.frame:Destroy()
			rows[uid] = nil
		end
	end
	ui.empty.Visible = #displayed == 0
end

local function setBusy(value: boolean)
	busy = value
	setButton(ui.equip, not value, if value then "..." else "EQUIP BEST")
end

-- ── Open / close ────────────────────────────────────────────────────

function Nukes.open()
	local panel = ui.panel
	if panel == nil or panel.Visible or HudTile.blocked("Nukes") then
		return
	end
	slideToken += 1
	ui.notice.Text = ""
	panel.Position = CLOSED_POS
	panel.Visible = true
	ask()
	TweenService:Create(panel, SLIDE_IN, { Position = OPEN_POS }):Play()
end

function Nukes.close()
	local panel = ui.panel
	if panel == nil or not panel.Visible then
		return
	end
	slideToken += 1
	local token = slideToken
	local tween = TweenService:Create(panel, SLIDE_OUT, { Position = CLOSED_POS })
	tween.Completed:Connect(function()
		if token == slideToken then
			panel.Visible = false
		end
	end)
	tween:Play()
end

function Nukes.toggle()
	if ui.panel and ui.panel.Visible then
		Nukes.close()
	else
		Nukes.open()
	end
end

local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "NukesPanel"
	gui.ResetOnSpawn = false
	-- Same call as the Shop and Index panels: respects the topbar inset and sits over
	-- the whole HUD (RadHud is 100).
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	-- The whole slide: tray, its close tab and Equip Best under it move as one.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = CLOSED_POS
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H + EQUIP_GAP + EQUIP_H)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = canvas

	local tray = Instance.new("Frame")
	tray.Name = "Tray"
	tray.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	tray.BackgroundColor3 = PANEL.tray
	tray.BorderSizePixel = 0
	tray.ZIndex = 2
	tray.Parent = panel
	edge(tray, PANEL.ink, 4)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PAD)
	padding.PaddingBottom = UDim.new(0, PAD)
	padding.PaddingLeft = UDim.new(0, PAD)
	padding.PaddingRight = UDim.new(0, PAD)
	padding.Parent = tray

	-- The header box: a lighter grey plate over the list. The title with what the
	-- stands pay beside it on the left; how full they are, on its own, on the right.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.BackgroundColor3 = PANEL.header
	header.BorderSizePixel = 0
	header.ZIndex = 3
	header.Parent = tray
	edge(header, PANEL.ink, 2)

	local title = inked(header, {
		Name = "Title",
		Text = "Nukes",
		TextSize = 30,
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromScale(0, 1),
		ZIndex = 4,
	})
	local rate = inked(header, {
		Name = "Rate",
		Text = "",
		TextSize = 22,
		TextColor3 = PANEL.gold,
		Position = UDim2.fromOffset(12, 2),
		Size = UDim2.new(0, 170, 1, 0),
		ZIndex = 4,
	})
	-- Beside the title, however wide the title draws.
	local function besideTitle()
		local scale = UIKit.canvasScale(canvas)
		rate.Position = UDim2.fromOffset(12 + title.AbsoluteSize.X / scale + 10, 2)
	end
	title:GetPropertyChangedSignal("AbsoluteSize"):Connect(besideTitle)
	besideTitle()
	local count = inked(header, {
		Name = "Count",
		Text = "",
		TextSize = 20,
		TextColor3 = PANEL.white,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 2),
		Size = UDim2.new(0, 170, 1, 0),
		ZIndex = 4,
	})
	local notice = inked(tray, {
		Name = "Notice",
		Text = "",
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(2, HEADER_H + 4),
		Size = UDim2.new(1, -4, 0, NOTICE_H),
		ZIndex = 3,
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
	scroll.ZIndex = 3
	scroll.Parent = tray
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll
	local inset = Instance.new("UIPadding")
	inset.PaddingLeft = UDim.new(0, 2)
	inset.PaddingTop = UDim.new(0, 2)
	inset.PaddingBottom = UDim.new(0, 4)
	inset.Parent = scroll
	local empty = inked(scroll, {
		Name = "Empty",
		Text = "Nothing on your stands yet",
		TextSize = 16,
		TextColor3 = PANEL.dim,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = -1,
		Visible = false,
	})

	-- The close tab: a red ">" TAB_GAP off the tray's left edge, halfway down, pointing
	-- the way the tray slides out.
	local tab = chunky(panel, "Close", ">", Vector2.new(TAB_W, TAB_H), 26, PANEL.red, PANEL.redHover)
	tab.Position = UDim2.fromOffset(-TAB_W - TAB_GAP, (PANEL_H - TAB_H) / 2)
	tab.ZIndex = 1
	tab.Activated:Connect(Nukes.close)

	local equip = chunky(panel, "EquipBest", "EQUIP BEST", Vector2.new(EQUIP_W, EQUIP_H), 26, PANEL.equip, PANEL.equipHover)
	equip.AnchorPoint = Vector2.new(1, 0)
	equip.Position = UDim2.fromOffset(PANEL_W, PANEL_H + EQUIP_GAP)
	-- The Gear panel's EQUIP look: no bevel lip, no outline on the words.
	equip.Lip:Destroy()
	local equipLabel = equip.Label :: TextLabel
	equipLabel.Font = PANEL.equipFont
	local wordStroke = equipLabel:FindFirstChildOfClass("UIStroke")
	if wordStroke then
		wordStroke:Destroy()
	end
	equip.Activated:Connect(function()
		if busy or not equip.Active or actionRemote == nil then
			return
		end
		setBusy(true)
		actionRemote:FireServer("equipBest")
		-- The answer is a NukeList carrying `notice`; if it never comes (the server's
		-- cooldown swallowed a double-press) the button comes back on its own.
		task.delay(2, function()
			if busy then
				setBusy(false)
			end
		end)
	end)

	ui.panel = panel
	ui.count = count
	ui.rate = rate
	ui.equip = equip
	ui.notice = notice
	ui.scroll = scroll
	ui.empty = empty
	return gui
end

-- ── The tile ────────────────────────────────────────────────────────

local function build(): ScreenGui
	local gui = HudTile.build({
		name = "NukesButton",
		caption = "Nukes",
		slot = TILE_SLOT,
		color = TILE_COLOR,
		light = TILE_LIGHT,
		image = Artwork.IMAGE.nuke,
		onActivated = Nukes.toggle,
	})
	return gui
end

function Nukes.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	build().Parent = playerGui
	buildPanel().Parent = playerGui
	HudTile.registerPanel("Nukes", ui.panel)

	actionRemote = Net.get("NukeAction")
	Net.get("NukeList").OnClientEvent:Connect(function(list)
		latest = list
		if list and list.notice then
			ui.notice.Text = list.notice
			setBusy(false)
		end
		render()
	end)

	-- Something moved: re-ask, but only while anyone is looking.
	local function onChange()
		if ui.panel and ui.panel.Visible then
			ask()
		end
	end
	Net.get("CarryState").OnClientEvent:Connect(onChange)
	Net.get("IncomeState").OnClientEvent:Connect(onChange)

	-- The names' shimmer sweeps and Anomaly names cycle their spectrum; only while the
	-- panel is up.
	RunService.RenderStepped:Connect(function()
		if not (ui.panel and ui.panel.Visible) then
			return
		end
		local now = os.clock()
		for _, row in rows do
			if row.entry and row.entry.rarity == "Anomaly" then
				tint(row, now)
			end
		end
		sweep(now)
	end)
end

return Nukes
