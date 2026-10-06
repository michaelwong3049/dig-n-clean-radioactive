--!strict
--[[
	BoostsController.luau — the bottom-right Boosts widget: a small stack of pills that
	says what your luck, cash and other multipliers add up to RIGHT NOW, with a card
	that lists every source behind each one.

	WHY IT EXISTS: luck comes from the Violet Aurora, the Lucky Clover, the 2x Luck pass
	and the Luck Potion, all stacking, and players lost track of what their total was.
	Cash has six sources. This puts the product in one place.

	IT DECIDES NOTHING. The list is StatResolver.boosts, sent by BoostsService whenever
	it changes. Countdowns come off the attributes the owner services already publish
	(each source's `timer`), so they tick smoothly without a remote per second.

	THE STACK: Luck and Cash always show; any other row shows while it is above x1, up
	to Dock.BOOSTS_ROWS pills (the last one turns into "+N MORE" if there are more).
	A pill shows its countdown when a timed source is running -- the soonest one, so it
	is the time until that number next changes -- and its name otherwise. The luck pill
	carries the clover, green up to x2 and purple past it; this replaced the old clover
	badge (LuckBoostController), so the last 30 seconds still pulse.

	THE CARD opens to the left of the stack on hover, and a click / tap pins it open
	(click again to close). It sits above the stack, so it never covers the vitals bars.
	GET MORE opens the Shop, as the old clover did.

	POSITION is the old clover's formula: hard in the right corner on the hotbar's top
	edge (above the jump button on touch), and never up into the right-hand tile grid
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
local ShopController = require(script.Parent.ShopController)
local Dock = UIKit.Dock
local House = UIKit.House

local BoostsController = {}

type Source = { name: string, mult: number, timer: string?, global: boolean? }
type Boost = { key: string, label: string, total: number, sources: { Source } }

-- Each row's picture, colour and pill caption. The pictures are the pass and potion
-- art the Shop already shows; luck draws the clover instead.
local function passImage(key: string): string
	local pass = GamePasses.byKey(key)
	return if pass then pass.image else ""
end

local LOOK: { [string]: { short: string, color: Color3, image: string? } } = {
	luck = { short = "LUCK", color = Color3.fromHex("6BE36A") },
	cash = { short = "CASH", color = House.cash, image = passImage("cash") },
	speed = { short = "SPEED", color = Color3.fromHex("6FA0FF"), image = Potions.get("speed").image },
	strength = { short = "POWER", color = Color3.fromHex("FF8A3D"), image = passImage("digPower") },
	clean = { short = "WASH", color = Color3.fromHex("25D3C9"), image = Potions.get("clean").image },
	training = { short = "TRAIN", color = Color3.fromHex("50C8FF"), image = passImage("speed") },
	bomb = { short = "BOMB", color = Color3.fromHex("FF5A4A"), image = passImage("bombDamage") },
	health = { short = "HEALTH", color = Color3.fromHex("FF6E78"), image = passImage("health") },
}
local LUCK_PURPLE = Color3.fromHex("B48CFF")

local ALWAYS = { luck = true, cash = true }

local W = Dock.BOOSTS_WIDTH
local ROW = Dock.BOOSTS_ROW
local ICON = 24
local CARD_W = 270
local WARN_SECONDS = 30
local WARN = Color3.fromHex("FF5C8A")

local gui: ScreenGui
local canvas: Frame
local stack: TextButton
local fit: UIScale
local card: Frame
local cardFit: UIScale
local cardBody: Frame

type Row = { frame: Frame, icon: GuiObject, caption: TextLabel, value: TextLabel, key: string? }
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

--- The soonest-ending timed source on a row: when its number next changes.
local function soonest(boost: Boost): number?
	local best: number? = nil
	for _, source in boost.sources do
		local left = secondsLeft(source)
		if left and (best == nil or left < best) then
			best = left
		end
	end
	return best
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

local function label(parent: Instance, name: string, size: number, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = House.font
	l.TextSize = size
	l.TextColor3 = House.white
	l.TextStrokeTransparency = 1
	l.ZIndex = z
	l.Parent = parent
	stroke(l, math.max(1, size * 0.1))
	return l
end

-- ── Build ─────────────────────────────────────────────────────────────

local function buildRow(index: number): Row
	local frame = Instance.new("Frame")
	frame.Name = `Row{index}`
	frame.LayoutOrder = index
	frame.Size = UDim2.fromOffset(W, ROW)
	frame.BackgroundColor3 = House.panel
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 20
	frame.Parent = stack
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = frame
	stroke(frame, 2.5, true)

	local caption = label(frame, "Caption", 12, 22)
	caption.AnchorPoint = Vector2.new(0, 0.5)
	caption.Position = UDim2.new(0, ICON + 10, 0.5, 0)
	caption.Size = UDim2.fromOffset(60, ROW)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.TextColor3 = House.dim

	local value = label(frame, "Value", 17, 22)
	value.AnchorPoint = Vector2.new(1, 0.5)
	value.Position = UDim2.new(1, -10, 0.5, 0)
	value.Size = UDim2.fromOffset(64, ROW)
	value.TextXAlignment = Enum.TextXAlignment.Right

	return { frame = frame, icon = frame, caption = caption, value = value }
end

--- Swap a row's picture for `key`'s: the clover for luck, an image otherwise.
local function setIcon(row: Row, key: string?)
	if row.key == key then
		return
	end
	row.key = key
	if row.icon ~= row.frame then
		row.icon:Destroy()
	end
	if key == nil then
		row.icon = row.frame
		return
	end
	local icon: GuiObject
	if key == "luck" then
		icon = CloverArt.build(row.frame, ICON, 23)
	else
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromOffset(ICON, ICON)
		image.Image = LOOK[key] and LOOK[key].image or ""
		image.ZIndex = 23
		image.Parent = row.frame
		icon = image
	end
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 5, 0.5, 0)
	row.icon = icon
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

	local more = Instance.new("TextButton")
	more.Name = "GetMore"
	more.LayoutOrder = 2
	more.Size = UDim2.fromOffset(150, 32)
	more.AutoButtonColor = false
	more.BackgroundColor3 = House.buy
	more.BorderSizePixel = 0
	more.Font = House.font
	more.TextSize = 16
	more.TextColor3 = House.white
	more.TextStrokeTransparency = 1
	more.Text = "GET MORE"
	more.ZIndex = 31
	more.Parent = card
	local moreRound = Instance.new("UICorner")
	moreRound.CornerRadius = UDim.new(0, 10)
	moreRound.Parent = more
	stroke(more, 2.5, true)
	local moreText = Instance.new("UIStroke")
	moreText.Color = House.ink
	moreText.Thickness = 2
	moreText.Parent = more
	more.MouseEnter:Connect(function()
		more.BackgroundColor3 = House.buyHover
	end)
	more.MouseLeave:Connect(function()
		more.BackgroundColor3 = House.buy
	end)
	more.Activated:Connect(function()
		pinned = false
		card.Visible = false
		ShopController.open()
	end)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Boosts"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Beside the Index/Shop tiles (55), where the clover badge sat.
	gui.DisplayOrder = 56
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
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

	for i = 1, Dock.BOOSTS_ROWS do
		rows[i] = buildRow(i)
	end
	buildCard()
end

local function place()
	local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
	-- On the hotbar's top edge, above the jump button and the speed/cash pair on touch,
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
	return ALWAYS[boost.key] == true or math.abs(boost.total - 1) > 1e-9
end

local function luckColor(total: number): Color3
	return if total > 2 then LUCK_PURPLE else LOOK.luck.color
end

--- The pills. Called every frame for the countdowns; it only writes what changed.
local function drawStack(t: number)
	local shown: { Boost } = {}
	for _, boost in boosts do
		if visible(boost) then
			table.insert(shown, boost)
		end
	end
	local overflow = #shown - Dock.BOOSTS_ROWS
	for i, row in rows do
		local boost = shown[i]
		local more = overflow > 0 and i == Dock.BOOSTS_ROWS
		row.frame.Visible = boost ~= nil
		if boost == nil then
			continue
		end
		if more then
			setIcon(row, nil)
			row.caption.Position = UDim2.new(0, 12, 0.5, 0)
			row.caption.Text = "TAP FOR ALL"
			row.caption.TextColor3 = House.dim
			row.value.Text = `+{overflow + 1}`
			row.value.TextColor3 = House.white
			continue
		end
		setIcon(row, boost.key)
		row.caption.Position = UDim2.new(0, ICON + 10, 0.5, 0)
		local look = LOOK[boost.key]
		local color = if boost.key == "luck" then luckColor(boost.total) elseif look then look.color else House.white
		local left = soonest(boost)
		if left then
			row.caption.Text = clock(left)
			local warn = left <= WARN_SECONDS
			local pulse = if warn then 0.5 + 0.5 * math.sin(t * 8) else 0
			row.caption.TextColor3 = House.white:Lerp(WARN, pulse)
		else
			row.caption.Text = if look then look.short else string.upper(boost.label)
			row.caption.TextColor3 = House.dim
		end
		row.value.Text = times(boost.total)
		row.value.TextColor3 = color
		if boost.key == "luck" then
			CloverArt.paint(row.icon, CloverArt.paletteFor(boost.total))
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

	-- The countdowns. A handful of property writes a frame; the card's text only while open.
	local lastCard = 0
	RunService.Heartbeat:Connect(function()
		if not stack.Visible then
			return
		end
		local t = now()
		drawStack(t)
		if card.Visible and os.clock() - lastCard > 0.25 then
			lastCard = os.clock()
			drawCard()
		end
	end)
end

return BoostsController
