--[[
	NukesController.lua — the Nukes tile, and the panel it opens. Same card and
	outlined caption as the Index and Shop tiles, stacked one Dock.GAP under Shop on
	the right edge.

	THE PANEL IS EVERY NUKE ON YOUR STANDS, ON ONE LIST: each with its rarity and what
	it pays per second, the rate its stand card prints (duplicate damping and all),
	best first. The bag is deliberately not listed -- the hotbar already shows it.

	EQUIP BEST is the panel's one verb (ExhibitService.equipBest): fill every stand
	with the set that earns the most, swapping weaker pieces back into the bag. It
	works from anywhere, which is the point of it living on the HUD -- wash a nuke,
	press it, keep going. The server picks everything; the button sends a bare verb.

	NOTHING IS STREAMED. The list is asked for (NukeAction "list") when the panel opens,
	and again whenever CarryState or IncomeState says something moved while it is
	showing. Closed, it costs nothing.

	Its look is the Shop panel's (StationController's FIELD slate, LuckiestGuy /
	FredokaOne in INK outlines), with each row wearing its rarity colour
	(Config/Rarity's `color`, the one rarity signal shared across the whole game).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Rarity = require(Shared.Config.Rarity)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local ShopController = require(script.Parent.ShopController)

local Nukes = {}

-- Same tile as the Shop's (see ShopController for why these are copies).
local TILE_SIZE = Dock.SIDE_TILE_SIZE
local TILE_CAPTION = "Nukes"
local TILE_CAPTION_SIZE = 18
-- The trefoil's box and its top inset: same band as the Index book, clear of the
-- caption at 57.
local TILE_ICON_SIZE = 46
local TILE_ICON_TOP = 7
local TILE_HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
local PANEL_W = 640
local PANEL_H = 500
local PAD = 20
local HEADER_H = 58
local SUMMARY_H = 56
local NOTICE_H = 26
local LIST_TOP = HEADER_H + SUMMARY_H + NOTICE_H + 8
local ROW_H = 52
local CHIP_W = 104
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
-- The fastest the panel re-asks for its list while CarryState / IncomeState chatter.
local REFRESH_GAP = 0.5

local actionRemote: RemoteEvent? = nil
local ui: any = {}
local latest: any = nil
local receivedAt = 0
local busy = false
local lastAsk = 0
local askQueued = false

-- ── Helpers ─────────────────────────────────────────────────────────

--- "+$2.00/s" up to "+$1.2M/s" -- CashController.formatRate's ladder.
local function formatRate(perSecond: number): string
	if perSecond >= 1_000_000_000 then
		return string.format("+$%.1fB/s", perSecond / 1_000_000_000)
	elseif perSecond >= 1_000_000 then
		return string.format("+$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 1000 then
		return string.format("+$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("+$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("+$%.1f/s", perSecond)
	end
	return string.format("+$%.2f/s", perSecond)
end

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

local function edge(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
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

-- ── The trefoil (tile icon) ─────────────────────────────────────────

--- The radiation trefoil from primitives, the same way HudController draws its RADS
--- badge: each blade a fan of thin rotated bars. No picture needed, and the Unicode
--- trefoil renders as a colour emoji that ignores TextColor3.
local function buildTrefoil(parent: Instance, size: number, color: Color3): (Frame, { Frame })
	local box = Instance.new("Frame")
	box.Name = "Trefoil"
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundTransparency = 1
	box.ZIndex = 6
	box.Parent = parent

	local pieces: { Frame } = {}
	local function bar(x: number, y: number, w: number, h: number, rotation: number, radius: UDim?)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(x, y)
		frame.Size = UDim2.fromOffset(w, h)
		frame.Rotation = rotation
		frame.BackgroundColor3 = color
		frame.BorderSizePixel = 0
		frame.ZIndex = 6
		frame.Parent = box
		if radius then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = radius
			corner.Parent = frame
		end
		table.insert(pieces, frame)
	end

	local centre = size / 2
	local inner, outer = size * 0.14, size * 0.48
	local mid, length = (inner + outer) / 2, outer - inner
	for _, blade in { 90, 210, 330 } do -- one blade pointing down, like the sign
		for spread = -26, 26, 4 do
			local angle = blade + spread
			local rad = math.rad(angle)
			bar(centre + mid * math.cos(rad), centre + mid * math.sin(rad), length, 3, angle)
		end
	end
	bar(centre, centre, size * 0.18, size * 0.18, 0, UDim.new(1, 0))
	return box, pieces
end

-- ── Rows ────────────────────────────────────────────────────────────

type RowSpec = {
	name: string,
	rarity: string,
	sub: string,
	rate: number?,
}

--- One nuke: rarity stripe + chip on the left, name over its stand line, rate right.
local function row(parent: Instance, order: number, spec: RowSpec): TextLabel
	local color = rarityColor(spec.rarity)
	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.Size = UDim2.new(1, -8, 0, ROW_H)
	frame.BackgroundColor3 = PANEL.row
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.ZIndex = 13
	frame.Parent = parent
	round(frame, 10)
	edge(frame, PANEL.ink, 2)

	local stripe = Instance.new("Frame")
	stripe.Name = "Stripe"
	stripe.Size = UDim2.new(0, 8, 1, 0)
	stripe.BackgroundColor3 = color
	stripe.BorderSizePixel = 0
	stripe.ZIndex = 14
	stripe.Parent = frame
	round(stripe, 10)

	local chip = Instance.new("TextLabel")
	chip.Name = "Rarity"
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, 18, 0.5, 0)
	chip.Size = UDim2.fromOffset(CHIP_W, 24)
	chip.BackgroundColor3 = color
	chip.BorderSizePixel = 0
	chip.Font = PANEL.label
	chip.TextSize = 14
	chip.TextColor3 = PANEL.ink
	chip.Text = string.upper(spec.rarity)
	chip.ZIndex = 14
	chip.Parent = frame
	round(chip, 12)
	edge(chip, PANEL.ink, 2)

	local textLeft = 18 + CHIP_W + 14
	inked(frame, {
		Name = "Name",
		Text = spec.name,
		Font = PANEL.label,
		TextSize = 20,
		TextColor3 = PANEL.white,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -textLeft - 130, 0, 24),
		Position = UDim2.fromOffset(textLeft, 4),
		ZIndex = 14,
	})
	local sub = inked(frame, {
		Name = "Where",
		Text = spec.sub,
		Font = PANEL.label,
		TextSize = 14,
		TextColor3 = PANEL.dim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -textLeft - 130, 0, 18),
		Position = UDim2.fromOffset(textLeft, 28),
		ZIndex = 14,
	})
	inked(frame, {
		Name = "Rate",
		Text = if spec.rate then formatRate(spec.rate) else "\u{2014}",
		Font = PANEL.headline,
		TextSize = 20,
		TextColor3 = if spec.rate then PANEL.gold else PANEL.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(120, 26),
		Position = UDim2.new(1, -14, 0.5, 0),
		ZIndex = 14,
	})
	return sub
end

local function withModifier(text: string, modifier: string?): string
	if modifier and modifier ~= "None" and modifier ~= "" then
		return `{text} \u{00B7} {modifier}`
	end
	return text
end

--- "Stand 4", "Stand 4 · crating 42s", "Stand 7 · copy 2 (40%)".
local function standText(entry: any, crating: number): string
	local text = `Stand {entry.slot}`
	if crating > 0 then
		text ..= ` \u{00B7} crating {crating}s`
	end
	if (entry.copy or 1) > 1 then
		text ..= ` \u{00B7} copy {entry.copy}`
	end
	return withModifier(text, entry.modifier)
end

-- Rows on stands that are still crating, so the countdown can tick without a redraw.
local cratingRows: { { label: TextLabel, entry: any } } = {}

local function render()
	local list = latest
	local scroll: ScrollingFrame = ui.scroll
	for _, child in scroll:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	table.clear(cratingRows)
	if list == nil then
		return
	end

	ui.count.Text = `ON DISPLAY {list.used}/{list.slots}`
	-- The rows are pre-cap; when the hourly cap (ExhibitService.cappedRatePerSecond) is
	-- what holds the total back, say so, or the rows and the total look like they
	-- disagree.
	if list.raw and list.raw > list.rate + 1e-6 then
		ui.count.Text ..= ` \u{00B7} HOURLY CAP`
	end
	ui.rate.Text = if list.rate > 0 then formatRate(list.rate) else "+$0/s"

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local displayed = table.clone(list.displayed)
	table.sort(displayed, function(a, b)
		return a.rate > b.rate
	end)
	if #displayed == 0 then
		inked(scroll, {
			Name = "Empty",
			Text = "Nothing on your stands yet",
			Font = PANEL.label,
			TextSize = 16,
			TextColor3 = PANEL.dim,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = nextOrder(),
			ZIndex = 13,
		})
	end
	for _, entry in displayed do
		local sub = row(scroll, nextOrder(), {
			name = entry.name,
			rarity = entry.rarity,
			sub = standText(entry, entry.crating),
			rate = entry.rate,
		})
		if entry.crating > 0 then
			table.insert(cratingRows, { label = sub, entry = entry })
		end
	end
end

--- Tick the crating countdowns in place.
local function tickCrating()
	local elapsed = math.floor(os.clock() - receivedAt)
	for _, entry in cratingRows do
		local left = math.max(0, entry.entry.crating - elapsed)
		entry.label.Text = standText(entry.entry, left)
	end
end

local function setBusy(value: boolean)
	busy = value
	ui.equip.Text = if value then "..." else "EQUIP BEST"
	ui.equip.BackgroundColor3 = if value then PANEL.off else PANEL.buy
end

-- ── Open / close ────────────────────────────────────────────────────

function Nukes.open()
	local panel = ui.panel
	if panel == nil or panel.Visible then
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

function Nukes.close()
	if ui.panel then
		ui.panel.Visible = false
	end
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
	-- Same call as the Shop and Index panels: a centred modal that respects the topbar
	-- inset and sits over the whole HUD (RadHud is 100).
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
		Text = "NUKES",
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
	local closeEdge = Instance.new("UIStroke")
	closeEdge.Color = PANEL.ink
	closeEdge.Thickness = 3
	closeEdge.Parent = close
	close.Activated:Connect(Nukes.close)

	-- The summary strip: how full the stands are and what they pay, and the button.
	local summary = Instance.new("Frame")
	summary.Name = "Summary"
	summary.Position = UDim2.fromOffset(0, HEADER_H)
	summary.Size = UDim2.new(1, 0, 0, SUMMARY_H)
	summary.BackgroundColor3 = PANEL.well
	summary.BorderSizePixel = 0
	summary.ZIndex = 11
	summary.Parent = panel
	round(summary, 14)
	edge(summary, PANEL.ink, 3)

	local count = inked(summary, {
		Name = "Count",
		Text = "ON DISPLAY",
		Font = PANEL.label,
		TextSize = 16,
		TextColor3 = PANEL.dim,
		Size = UDim2.fromOffset(360, 20),
		Position = UDim2.fromOffset(16, 6),
		ZIndex = 12,
	})
	local rate = inked(summary, {
		Name = "Rate",
		Text = "",
		Font = PANEL.headline,
		TextSize = 24,
		TextColor3 = PANEL.gold,
		Size = UDim2.fromOffset(260, 26),
		Position = UDim2.fromOffset(16, 25),
		ZIndex = 12,
	})

	local equip = Instance.new("TextButton")
	equip.Name = "EquipBest"
	equip.AutoButtonColor = false
	equip.AnchorPoint = Vector2.new(1, 0.5)
	equip.Position = UDim2.new(1, -8, 0.5, 0)
	equip.Size = UDim2.fromOffset(190, 42)
	equip.BackgroundColor3 = PANEL.buy
	equip.Font = PANEL.headline
	equip.TextSize = 22
	equip.TextColor3 = PANEL.white
	equip.Text = "EQUIP BEST"
	equip.ZIndex = 13
	equip.Parent = summary
	round(equip, 12)
	local equipEdge = Instance.new("UIStroke")
	equipEdge.Color = PANEL.ink
	equipEdge.Thickness = 3
	equipEdge.LineJoinMode = Enum.LineJoinMode.Round
	equipEdge.Parent = equip
	equip.MouseEnter:Connect(function()
		if not busy then
			TweenService:Create(equip, TILE_HOVER, { BackgroundColor3 = PANEL.buyHover }):Play()
		end
	end)
	equip.MouseLeave:Connect(function()
		if not busy then
			TweenService:Create(equip, TILE_HOVER, { BackgroundColor3 = PANEL.buy }):Play()
		end
	end)
	equip.Activated:Connect(function()
		if busy or actionRemote == nil then
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

	local notice = inked(panel, {
		Name = "Notice",
		Text = "",
		Font = PANEL.label,
		TextSize = 16,
		TextColor3 = PANEL.light,
		Size = UDim2.new(1, 0, 0, NOTICE_H - 4),
		Position = UDim2.fromOffset(4, HEADER_H + SUMMARY_H + 4),
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
	ui.count = count
	ui.rate = rate
	ui.equip = equip
	ui.notice = notice
	ui.scroll = scroll
	return gui
end

-- ── The tile ────────────────────────────────────────────────────────

--- The Nukes tile's top edge, in design px from the canvas's vertical centre: one
--- Dock.GAP under wherever the Shop tile ends on a canvas `height` design px tall.
local function tileTop(height: number): number
	return ShopController.columnBottom(height) - height / 2 + Dock.GAP
end

--- Where the right-hand tile column ends now: the Nukes tile's bottom edge, in design
--- px from the canvas TOP. LuckBoostController keeps the 2x-luck clover below it.
function Nukes.columnBottom(height: number): number
	return height / 2 + tileTop(height) + TILE_SIZE
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "NukesButton"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Same layer as the Index and Shop tiles (55): one column.
	gui.DisplayOrder = 55
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local tileSize = UDim2.fromOffset(TILE_SIZE, TILE_SIZE)
	local shadow = UIKit.panel(canvas, {
		name = "NukesShadow",
		size = tileSize,
		color = UIKit.C.navShadow,
		transparency = 0.2,
		cornerRadius = UDim.new(0, 9),
		strokeThickness = 0,
		zIndex = 3,
	})
	local button, buttonStroke = UIKit.button(canvas, {
		name = "NukesButton",
		size = tileSize,
		text = "",
		textSize = UIKit.TextSize.body,
		fillColor = UIKit.C.navFill,
		fillTransparency = 0,
		strokeColor = UIKit.C.navEdge,
		strokeThickness = 2,
		cornerRadius = UDim.new(0, 9),
		zIndex = 4,
	})
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local function place()
		local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
		local y = tileTop(height)
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 0.5, y)
		shadow.AnchorPoint = Vector2.new(1, 0)
		shadow.Position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 0.5, y + 4)
	end
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()

	local icon, pieces = buildTrefoil(button, TILE_ICON_SIZE, UIKit.C.navIcon)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, TILE_ICON_TOP)

	UIKit.label(button, {
		name = "Caption",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -5),
		size = UDim2.new(1, 0, 0, 18),
		text = TILE_CAPTION,
		font = Enum.Font.GothamBlack,
		textSize = TILE_CAPTION_SIZE,
		color = Color3.new(1, 1, 1),
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 8,
	})

	local function setHighlighted(active: boolean)
		local fill = if active then UIKit.C.navFillHover else UIKit.C.navFill
		TweenService:Create(button, TILE_HOVER, { BackgroundColor3 = fill }):Play()
		TweenService:Create(buttonStroke, TILE_HOVER, {
			Color = if active then UIKit.C.navEdgeHover else UIKit.C.navEdge,
		}):Play()
		-- The trefoil brightens to white, same as the Index book and the Shop cart.
		local tint = if active then Color3.new(1, 1, 1) else UIKit.C.navIcon
		for _, piece in pieces do
			TweenService:Create(piece, TILE_HOVER, { BackgroundColor3 = tint }):Play()
		end
	end
	button.MouseEnter:Connect(function()
		setHighlighted(true)
	end)
	button.MouseLeave:Connect(function()
		setHighlighted(false)
	end)
	button.SelectionGained:Connect(function()
		setHighlighted(true)
	end)
	button.SelectionLost:Connect(function()
		setHighlighted(false)
	end)
	button.Activated:Connect(Nukes.toggle)

	return gui
end

function Nukes.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	build().Parent = playerGui
	buildPanel().Parent = playerGui

	actionRemote = Net.get("NukeAction")
	Net.get("NukeList").OnClientEvent:Connect(function(list)
		latest = list
		receivedAt = os.clock()
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

	task.spawn(function()
		while true do
			task.wait(1)
			if ui.panel and ui.panel.Visible and #cratingRows > 0 then
				tickCrating()
			end
		end
	end)
end

return Nukes
