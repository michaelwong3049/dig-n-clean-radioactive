--!strict
--[[
	BoostsController.luau — the bottom-right Boosts widget: "CURRENT BOOSTS" over three
	lines of outlined text saying what your luck, cash and walk speed add up to RIGHT
	NOW, with a card that lists every source behind each one.

	WHY IT EXISTS: luck comes from the Violet Aurora, the Lucky Clover, the 2x Luck pass
	and the Luck Potion, all stacking, and players lost track of what their total was.
	Cash has six sources. This puts the product in one place.

	IT DECIDES NOTHING. The list is StatResolver.boosts, sent by BoostsService whenever
	it changes. Countdowns come off the attributes the owner services already publish
	(each source's `timer`), so they tick smoothly without a remote per second.

	THE STACK: no panels, like the boxless cash readout -- name, total and picture per
	line, right-aligned. Only Luck, Cash and Walk Speed show, always (x1 included);
	the other boosts StatResolver sends are left off on request (2026-10-06), and so
	are the potion / weather countdowns -- those live on the card. The luck line
	carries the clover, green up to x2 and purple past it; this replaced the old clover
	badge (LuckBoostController).

	THE CARD opens to the left of the stack on hover, and a click / tap pins it open
	(click again to close). It sits above the stack, so it never covers the vitals bars.
	It has no GET MORE button any more (removed on request, 2026-10-07).

	POSITION: hard in the bottom-right corner, level with the hotbar's bottom
	(above the jump button on touch), and never up into the right-hand tile grid
	(Dock.sideColumnBottom) -- on a short canvas it slides down, then shrinks (Dock.BOOSTS_MIN_FIT).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local GamePasses = require(Shared.Config.GamePasses)
local Potions = require(Shared.Config.Potions)

local UIKit = require(script.Parent.Parent.UIKit)
local CloverArt = require(script.Parent.Parent.CloverArt)
local TutorialGate = require(script.Parent.Parent.TutorialGate)
local Dock = UIKit.Dock
local House = UIKit.House

local BoostsController = {}

type Source = { name: string, mult: number, timer: string?, global: boolean? }
type Boost = { key: string, label: string, total: number, sources: { Source } }

-- Each line's picture, colour and caption. The pictures are the pass and potion
-- art the Shop already shows; luck draws the clover instead.
local function passImage(key: string): string
	local pass = GamePasses.byKey(key)
	return if pass then pass.image else ""
end

local LOOK: { [string]: { short: string, color: Color3, image: string? } } = {
	luck = { short = "LUCK", color = Color3.fromHex("6BE36A") },
	cash = { short = "CASH", color = House.cash, image = passImage("cash") },
	speed = { short = "SPEED", color = Color3.fromHex("6FA0FF"), image = Potions.get("speed").image },
}
local LUCK_PURPLE = Color3.fromHex("B48CFF")

-- The only boosts shown, top to bottom (Dock.BOOSTS_ROWS of them).
local ORDER = { "luck", "cash", "speed" }

local W = Dock.BOOSTS_WIDTH
local ROW = Dock.BOOSTS_ROW
local ICON = 30
local VALUE_SIZE = 30
local CAPTION_SIZE = 17
local CARD_W = 270

local gui: ScreenGui
local canvas: Frame
local stack: TextButton
local fit: UIScale
local card: Frame
local cardFit: UIScale
local cardBody: Frame

type Row = { frame: Frame, caption: TextLabel, value: TextLabel, key: string, icon: GuiObject? }
local rows: { Row } = {}

local boosts: { Boost } = {}
local hovering = false
local pinned = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

--- "9:42", or "1:04:10" past an hour.
local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h, m, r = s // 3600, (s % 3600) // 60, s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

--- "x2", "x1.5", "x2.42": two decimals at most, trailing zeros dropped.
local function times(n: number): string
	local text = string.format("%.2f", n)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return `x{text}`
end

--- Seconds left on a timed source, or nil if it is permanent or already over.
local function secondsLeft(source: Source): number?
	if source.timer == nil then
		return nil
	end
	local holder: Instance = if source.global then ReplicatedStorage else Players.LocalPlayer
	local endsAt = holder:GetAttribute(source.timer)
	if type(endsAt) ~= "number" then
		return nil
	end
	local left = endsAt - now()
	return if left > 0 then left else nil
end

local function stroke(parent: Instance, thickness: number, border: boolean?)
	local s = Instance.new("UIStroke")
	s.Color = House.ink
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
end

--- Outlined Gotham Black text; `thick` overrides the outline (size / 10 by default).
local function label(parent: Instance, name: string, size: number, z: number, thick: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = House.font
	l.TextSize = size
	l.TextColor3 = House.white
	l.TextStrokeTransparency = 1
	l.ZIndex = z
	l.Parent = parent
	stroke(l, thick or math.max(1, size * 0.1))
	return l
end

-- ── Build ─────────────────────────────────────────────────────────────

--- One line, right-aligned: caption, total, then the picture hard against the edge.
local function buildRow(index: number, key: string): Row
	local frame = Instance.new("Frame")
	frame.Name = `Row{index}`
	frame.LayoutOrder = index
	frame.Size = UDim2.fromOffset(W, ROW)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 20
	frame.Parent = stack
	local line = Instance.new("UIListLayout")
	line.FillDirection = Enum.FillDirection.Horizontal
	line.HorizontalAlignment = Enum.HorizontalAlignment.Right
	line.VerticalAlignment = Enum.VerticalAlignment.Center
	line.SortOrder = Enum.SortOrder.LayoutOrder
	line.Padding = UDim.new(0, 6)
	line.Parent = frame

	local caption = label(frame, "Caption", CAPTION_SIZE, 22, 2)
	caption.LayoutOrder = 1
	caption.AutomaticSize = Enum.AutomaticSize.X
	caption.Size = UDim2.fromOffset(0, ROW)
	caption.TextColor3 = House.white

	local value = label(frame, "Value", VALUE_SIZE, 22, 3)
	value.LayoutOrder = 2
	value.AutomaticSize = Enum.AutomaticSize.X
	value.Size = UDim2.fromOffset(0, ROW)

	-- The clover for luck, the Shop's pass / potion art otherwise.
	local icon: GuiObject
	if key == "luck" then
		icon = CloverArt.build(frame, ICON, 23)
	else
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromOffset(ICON, ICON)
		image.Image = LOOK[key].image or ""
		image.ZIndex = 23
		image.Parent = frame
		icon = image
	end
	icon.Name = "Icon"
	icon.LayoutOrder = 3

	return { frame = frame, caption = caption, value = value, key = key, icon = icon }
end

local function buildCard()
	card = Instance.new("Frame")
	card.Name = "BoostsCard"
	card.AnchorPoint = Vector2.new(1, 1)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.fromOffset(CARD_W, 0)
	card.BackgroundColor3 = House.panel
	card.BorderSizePixel = 0
	card.Visible = false
	card.ZIndex = 30
	card.Parent = canvas
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 14)
	round.Parent = card
	stroke(card, 3, true)
	cardFit = Instance.new("UIScale")
	cardFit.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.Parent = card
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = card

	local title = label(card, "Title", 18, 31)
	title.LayoutOrder = 0
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Text = "YOUR BOOSTS"

	cardBody = Instance.new("Frame")
	cardBody.Name = "Body"
	cardBody.LayoutOrder = 1
	cardBody.BackgroundTransparency = 1
	cardBody.AutomaticSize = Enum.AutomaticSize.Y
	cardBody.Size = UDim2.fromScale(1, 0)
	cardBody.Parent = card
	local bodyList = Instance.new("UIListLayout")
	bodyList.SortOrder = Enum.SortOrder.LayoutOrder
	bodyList.Padding = UDim.new(0, 2)
	bodyList.Parent = cardBody
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Boosts"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Beside the Index/Shop tiles (55), where the clover badge sat.
	gui.DisplayOrder = 56
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Hidden until the tutorial is over.
	TutorialGate.bind(gui)
	canvas = UIKit.canvas(gui)

	-- A button so it can be hovered and clicked; the pills inside draw it.
	stack = Instance.new("TextButton")
	stack.Name = "Stack"
	stack.Text = ""
	stack.AutoButtonColor = false
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(1, 1)
	stack.Size = UDim2.fromOffset(W, Dock.BOOSTS_HEIGHT)
	stack.Visible = false
	stack.Parent = canvas
	fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = stack
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, Dock.BOOSTS_ROW_GAP)
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Parent = stack

	local header = label(stack, "Header", 17, 22, 2)
	header.LayoutOrder = 0
	header.Size = UDim2.fromOffset(W, Dock.BOOSTS_HEADER)
	header.TextXAlignment = Enum.TextXAlignment.Right
	header.Text = "CURRENT BOOSTS"

	for i, key in ORDER do
		rows[i] = buildRow(i, key)
	end
	buildCard()
end

local function place()
	local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
	-- Hard in the corner, above the jump button on touch,
	-- shrunk on a short canvas (Dock.boostsLayout).
	local bottom, scale = Dock.boostsLayout(height)
	local right = Dock.ROW_SIDE_MARGIN
	fit.Scale = scale
	stack.Position = UDim2.new(1, -right, 1, -bottom)
	-- Above the stack, right edges flush: beside it, a small screen put it over the
	-- vitals bars. Covering the pass offers while it is open is fine.
	cardFit.Scale = scale
	card.Position = UDim2.new(1, -right, 1, -(bottom + Dock.BOOSTS_HEIGHT * scale + Dock.GAP))
end

-- ── Draw ──────────────────────────────────────────────────────────────

local function visible(boost: Boost): boolean
	return LOOK[boost.key] ~= nil
end

local function luckColor(total: number): Color3
	return if total > 2 then LUCK_PURPLE else LOOK.luck.color
end

--- The lines: name, total and picture, redrawn whenever the list arrives.
local function drawStack()
	for _, row in rows do
		local boost: Boost? = nil
		for _, b in boosts do
			if b.key == row.key then
				boost = b
				break
			end
		end
		local look = LOOK[row.key]
		local total = if boost then boost.total else 1
		row.caption.Text = look.short
		row.value.Text = times(total)
		row.value.TextColor3 = if row.key == "luck" then luckColor(total) else look.color
		if row.key == "luck" and row.icon then
			CloverArt.paint(row.icon, CloverArt.paletteFor(total))
		end
	end
end

-- The card's lines, pooled: one label per line, since a multi-line rich-text label
-- with mixed sizes measured its own height wrong and the lines overlapped.
local lines: { TextLabel } = {}

type Line = { text: string, size: number, color: Color3, indent: number }

--- The card: per boost a header line, then one line per source with its countdown.
local function drawCard()
	local want: { Line } = {}
	for _, boost in boosts do
		if not visible(boost) then
			continue
		end
		local look = LOOK[boost.key]
		local color = if boost.key == "luck" then luckColor(boost.total) elseif look then look.color else House.white
		local header = { text = `{string.upper(boost.label)}  {times(boost.total)}`, size = 16, color = color, indent = 0 }
		-- A gap above every section but the first.
		if #want > 0 then
			table.insert(want, { text = "", size = 4, color = House.white, indent = 0 })
		end
		table.insert(want, header)
		if #boost.sources == 0 then
			table.insert(want, { text = "nothing yet", size = 13, color = House.dim, indent = 10 })
		end
		for _, source in boost.sources do
			local left = secondsLeft(source)
			local tail = if left then `   {clock(left)}` else ""
			table.insert(want, { text = `{source.name}  {times(source.mult)}{tail}`, size = 13, color = House.white, indent = 10 })
		end
	end
	for i, line in want do
		local l = lines[i]
		if l == nil then
			l = label(cardBody, `Line{i}`, 13, 31)
			l.LayoutOrder = i
			l.TextXAlignment = Enum.TextXAlignment.Left
			lines[i] = l
		end
		l.Visible = true
		l.Text = line.text
		l.TextSize = line.size
		l.TextColor3 = line.color
		local pad = l:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, line.indent)
		pad.Parent = l
		l.Size = UDim2.new(1, 0, 0, line.size + 4)
	end
	for i = #want + 1, #lines do
		lines[i].Visible = false
	end
end

local function setCardOpen(open: boolean)
	if card.Visible == open then
		return
	end
	card.Visible = open
	if open then
		drawCard()
	end
end

local function onBoosts(list: { Boost })
	boosts = list
	stack.Visible = #list > 0
	drawStack()
	if card.Visible then
		drawCard()
	end
end

function BoostsController.start()
	build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	place()
	UIKit.onScaleChanged(place)
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	stack.MouseEnter:Connect(function()
		hovering = true
		setCardOpen(true)
	end)
	stack.MouseLeave:Connect(function()
		hovering = false
		setCardOpen(pinned)
	end)
	stack.Activated:Connect(function()
		pinned = not pinned
		setCardOpen(pinned or (hovering and not UIKit.isTouch()))
	end)

	Net.get("Boosts").OnClientEvent:Connect(onBoosts)

	-- The card's countdowns tick while it is open.
	local lastCard = 0
	RunService.Heartbeat:Connect(function()
		if card.Visible and os.clock() - lastCard > 0.25 then
			lastCard = os.clock()
			drawCard()
		end
	end)
end

return BoostsController
