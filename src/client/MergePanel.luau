--!strict
--[[
	MergePanel.luau — the Merge Reactor, drawn inside StationController's panel.

	REWORKED 2026-10-06 (the user picked option 3 of 4 browser mockups, "Before -> After",
	in the grey studded skin the shop and the trader wear). Every merge succeeds now
	(Config/Merge), so the panel is no longer an odds bar; it is a picker and a receipt.

	  the nukes    LEFT: one tile per nuke you own (bag and Quarantine Locker together),
	               with how many copies and a READY / n/3 / MAX chip. Tapping a READY one
	               AUTO-FILLS its best three copies: most merge stars first, then the most
	               value (Merge-wise the best copy, MergeService keeps the most valuable).
	  the merge    RIGHT: the three copies GOING IN (tap one to swap in the next copy),
	               an arrow down to what COMES OUT (the nuke, its rating stars in gold and
	               merge stars in pink, its quality), the before -> after of its sell value,
	               stand income and merge stars, then AUTO-FILL and MERGE with the fee.

	The preview is Config/Merge.result over the same three records the server will get,
	scaled off the copy that survives (Merge.valueRatio), so the numbers are the merge.
	Everything else is presentation: the client asks to merge three uids, MergeService
	re-derives the station, the ownership, the fee and the crit roll itself.

	The dark L-stud backdrop under this panel is StationController's (ShopBackdrop); the
	navy patterned title bar is the trader's.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Merge = require(Shared.Config.Merge)
local Payload = require(Shared.Config.Payload)

local UIKit = require(script.Parent.UIKit)
local StarLine = require(script.Parent.StarLine)
local ItemArt = require(script.Parent.ItemArt)
local Studded = require(script.Parent.Studded)

local MergePanel = {}

local SKIN = {
	-- Near-black like the trader's rows, to stand off the dark studded backdrop.
	row = Color3.fromHex("16181C"),
	well = Color3.fromHex("101215"),
	-- The trader's navy glossy L-stud title bar.
	header = ColorSequence.new(Color3.fromHex("2C3E6B"), Color3.fromHex("1C2848")),
	-- What comes out stands on a dark gold plate with the same pattern.
	result = Color3.fromHex("4A3A12"),
	edge = Color3.fromHex("343B42"),
	rule = Color3.fromHex("30373D"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA0A6"),
	muted = Color3.fromHex("6C737A"),
	cash = UIKit.House.cash,
	go = Studded.LIME,
	auto = Studded.PURPLE,
	off = ColorSequence.new(Color3.fromHex("2F343B"), Color3.fromHex("25292F")),
	purple = Color3.fromHex("A855FF"),
	gold = Color3.fromHex("FFD24A"),
	pink = Merge.COLOR,
	ready = Color3.fromHex("52C96C"),
	notReady = Color3.fromHex("3A4148"),
	bag = Color3.fromHex("4FD1C5"),
	locker = Color3.fromHex("A855FF"),
	ink = Studded.INK,
	font = Enum.Font.GothamBlack,
}

--- The widest the panel is allowed to get, padding included. Same as the trader's.
MergePanel.WIDTH = 860

local HEADER_H = 58
-- The header box sits this far up into the panel's top padding (as the trader's does).
local HEADER_LIFT = 8
local HEADER_PAD = 14
local WALLET_INSET = 44
local BODY_TOP = HEADER_H - HEADER_LIFT + 12
local BODY_H = 432
local SIDE_W = 330
local TILE_W = 112
local TILE_H = 134
local IN_W = 96
local IN_H = 112

--- Both halves say this when you own no washed nukes at all.
local EMPTY_TEXT = "No cleaned nukes equipped."
local PICK_TEXT = `Tap a nuke with a READY chip. Its best {Merge.INPUTS} copies fill in by themselves, and a merge always adds a merge star.`

local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function money(amount: number): string
	local grouped = tostring(math.floor(amount + 0.5))
	while true do
		local nextText, count = string.gsub(grouped, "^(%-?%d+)(%d%d%d)", "%1,%2")
		grouped = nextText
		if count == 0 then
			break
		end
	end
	return `${grouped}`
end

--- A merge multiplier as short text: 1.5, 2.25, 3.38.
local function multText(level: number): string
	local s = string.format("%.2f", Merge.valueMult(level))
	s = (string.gsub(s, "0+$", ""))
	s = (string.gsub(s, "%.$", ""))
	return s
end

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

--- Rating stars in gold (half stars drawn by StarLine), then merge stars in pink.
local function paintStars(label: TextLabel, rating: number, merge: number?)
	StarLine.set(label, rating, { color = SKIN.gold, trail = merge, trailColor = SKIN.pink })
end

local function ratingOf(item: any): number
	local payload = if type(item.uid) == "string" then Payload.forUid(item.uid) else nil
	return Rarity.stars(item.rarity, item.modifier, payload, item.bonus, Items.stageOf(item.itemId))
end

--- The small line under a copy: its qualities, else its size sticker, else its size.
local function detailOf(item: any): string
	local qualities = Rarity.qualities(item.modifier, item.bonus)
	if #qualities > 0 then
		return table.concat(qualities, " ")
	end
	local payload = if type(item.uid) == "string" then Payload.forUid(item.uid) else 1
	return Payload.calloutFor(payload) or string.format("%.1fx", payload)
end

local function rarityColor(name: string?): Color3
	local def = if name then Rarity.DEFS[name] else nil
	return if def then def.color else SKIN.dim
end

local function ink(node: TextLabel | TextButton, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = SKIN.ink
	stroke.Thickness = thickness or math.clamp(node.TextSize / 9, 1.5, 3.5)
	stroke.Parent = node
	node.TextStrokeTransparency = 1
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = UIKit.label(parent, {
		name = props.name,
		position = props.position,
		size = props.size,
		anchorPoint = props.anchorPoint,
		font = SKIN.font,
		textSize = props.textSize,
		color = props.color or SKIN.text,
		xAlign = props.xAlign or Enum.TextXAlignment.Left,
		yAlign = props.yAlign,
		wrapped = props.wrapped,
		text = props.text,
		outline = false,
		shadow = false,
		strokeTransparency = 1,
	})
	if props.rich then
		label.RichText = true
	end
	if props.zIndex then
		label.ZIndex = props.zIndex
	end
	if props.ink ~= false then
		ink(label)
	end
	return label
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

local function frame(parent: Instance, name: string, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or SKIN.row
	f.BackgroundTransparency = if color then 0 else 1
	f.Parent = parent
	return f
end

local function chip(parent: Instance, name: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 16)
	label.BorderSizePixel = 0
	label.Font = SKIN.font
	label.TextSize = 11
	label.TextColor3 = SKIN.ink
	label.Parent = parent
	corner(label, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = label
	return label
end

--- A chunky studded button: white under a gradient (Studded.fill), inked edge and text.
local function bigButton(parent: Instance, name: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = SKIN.font
	button.TextSize = 18
	button.TextColor3 = SKIN.text
	button.Parent = parent
	corner(button, 12)
	ink(button, 2.5)
	edge(button, SKIN.ink, 3)
	return button
end

-- ── Build ───────────────────────────────────────────────────────────────

export type Panel = {
	frame: Frame,
	paint: (state: any) -> (),
	onMerge: (callback: (uids: { string }) -> ()) -> (),
	showResult: (result: any) -> (),
}

type Tile = {
	button: TextButton,
	stroke: UIStroke,
	strip: Frame,
	viewport: ViewportFrame,
	name: TextLabel,
	count: TextLabel,
	badge: TextLabel,
}

type Input = {
	button: TextButton,
	viewport: ViewportFrame,
	stars: TextLabel,
	detail: TextLabel,
	where: TextLabel,
}

type StatRow = { name: TextLabel, value: TextLabel }

--- One nuke the player owns, with every washed copy of it.
type Group = {
	itemId: string,
	name: string,
	rarity: string?,
	copies: { any },
	usable: { any }, -- the copies under MAX_LEVEL, best first (the auto-fill order)
}

local function makeTile(parent: Instance, index: number): Tile
	local button = Instance.new("TextButton")
	button.Name = `Tile{index}`
	button.LayoutOrder = index
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = SKIN.row
	button.Parent = parent
	corner(button, 12)
	local stroke = edge(button, SKIN.ink, 2)

	local strip = frame(button, "RarityStrip", SKIN.dim)
	strip.Position = UDim2.fromOffset(12, 6)
	strip.Size = UDim2.new(1, -24, 0, 4)
	corner(strip, 2)

	local art = frame(button, "Art")
	art.Position = UDim2.fromOffset(8, 14)
	art.Size = UDim2.new(1, -16, 0, 62)
	local viewport = ItemArt.newViewport(art)

	local name = text(button, {
		name = "ItemName",
		position = UDim2.fromOffset(4, 78),
		size = UDim2.new(1, -8, 0, 16),
		textSize = 13,
		xAlign = Enum.TextXAlignment.Center,
	})
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local count = text(button, {
		name = "Count",
		position = UDim2.fromOffset(4, 95),
		size = UDim2.new(1, -8, 0, 13),
		textSize = 11,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		ink = false,
	})
	local badge = chip(button, "Badge")
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, 112)
	return { button = button, stroke = stroke, strip = strip, viewport = viewport, name = name, count = count, badge = badge }
end

local function makeInput(parent: Instance, index: number): Input
	local button = Instance.new("TextButton")
	button.Name = `Input{index}`
	button.LayoutOrder = index
	button.Size = UDim2.fromOffset(IN_W, IN_H)
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = SKIN.well
	button.Parent = parent
	corner(button, 12)
	edge(button, SKIN.purple, 2)

	local art = frame(button, "Art")
	art.Position = UDim2.fromOffset(6, 4)
	art.Size = UDim2.new(1, -12, 0, 58)
	local viewport = ItemArt.newViewport(art)
	local stars = text(button, {
		name = "Stars",
		position = UDim2.fromOffset(2, 62),
		size = UDim2.new(1, -4, 0, 14),
		textSize = 10,
		xAlign = Enum.TextXAlignment.Center,
		rich = true,
		ink = false,
	})
	local detail = text(button, {
		name = "Detail",
		position = UDim2.fromOffset(2, 77),
		size = UDim2.new(1, -4, 0, 12),
		textSize = 10,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		ink = false,
	})
	detail.TextTruncate = Enum.TextTruncate.AtEnd
	local where = chip(button, "Where")
	where.AnchorPoint = Vector2.new(0.5, 0)
	where.Position = UDim2.new(0.5, 0, 0, 92)
	return { button = button, viewport = viewport, stars = stars, detail = detail, where = where }
end

function MergePanel.new(parent: Instance, layoutOrder: number): Panel
	local root = frame(parent, "Merge")
	root.LayoutOrder = layoutOrder
	root.Size = UDim2.new(1, 0, 0, BODY_TOP + BODY_H)
	root.Visible = false

	-- ── Header ─────────────────────────────────────────────────────────
	local header = frame(root, "Header")
	header.Position = UDim2.fromOffset(0, -HEADER_LIFT)
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	Studded.fill(header, SKIN.header)
	corner(header, 12)
	edge(header, SKIN.ink, 2)
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, HEADER_PAD)
	headerPad.Parent = header
	-- Under the header's left padding like the labels, so pushed back out to its edge.
	local headerPattern = Studded.pattern(header, { radius = 12, tile = 22, bands = { 0.28, 0.5, 0.58, 0.64 } })
	headerPattern.Position = UDim2.fromOffset(-HEADER_PAD, 0)
	headerPattern.Size = UDim2.new(1, HEADER_PAD, 1, 0)
	text(header, {
		name = "Title",
		position = UDim2.fromOffset(0, 4),
		size = UDim2.fromOffset(420, 36),
		textSize = 32,
		text = "Merge Reactor",
	})
	text(header, {
		name = "Subtitle",
		position = UDim2.fromOffset(0, 37),
		size = UDim2.fromOffset(520, 16),
		textSize = 12,
		color = Color3.fromHex("C9D3E6"),
		text = `{Merge.INPUTS} of the same nuke in, 1 out \u{00B7} always +1 merge star (x{Merge.VALUE_STEP} value & income)`,
		ink = false,
	})
	text(header, {
		name = "CashLabel",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 8),
		size = UDim2.fromOffset(200, 14),
		textSize = 12,
		xAlign = Enum.TextXAlignment.Right,
		text = "CASH",
	})
	local cash = text(header, {
		name = "Cash",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 22),
		size = UDim2.fromOffset(220, 30),
		textSize = 26,
		color = SKIN.cash,
		xAlign = Enum.TextXAlignment.Right,
	})

	-- ── The nukes (left) ───────────────────────────────────────────────
	local nukes = frame(root, "Nukes", SKIN.well)
	nukes.BackgroundTransparency = 0.25
	nukes.Position = UDim2.fromOffset(0, BODY_TOP)
	nukes.Size = UDim2.new(1, -(SIDE_W + 12), 0, BODY_H)
	corner(nukes, 12)
	edge(nukes, SKIN.ink, 2)
	local gridTitle = text(nukes, {
		name = "Title",
		position = UDim2.fromOffset(12, 8),
		size = UDim2.new(1, -24, 0, 16),
		textSize = 13,
		color = SKIN.dim,
		text = `YOUR WASHED NUKES (bag + locker) \u{00B7} tap a READY one`,
		ink = false,
	})
	gridTitle.TextTruncate = Enum.TextTruncate.AtEnd
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(10, 30)
	grid.Size = UDim2.new(1, -20, 1, -38)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 5
	grid.ScrollBarImageColor3 = SKIN.edge
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = nukes
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, 3)
	gridPad.PaddingLeft = UDim.new(0, 3)
	gridPad.Parent = grid
	local gridEmpty = text(nukes, {
		name = "Empty",
		position = UDim2.fromOffset(16, 30),
		size = UDim2.new(1, -32, 1, -38),
		textSize = 15,
		color = SKIN.muted,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = EMPTY_TEXT,
		ink = false,
	})

	-- ── The merge (right) ──────────────────────────────────────────────
	local side = frame(root, "Merge", SKIN.row)
	side.AnchorPoint = Vector2.new(1, 0)
	side.Position = UDim2.new(1, 0, 0, BODY_TOP)
	side.Size = UDim2.fromOffset(SIDE_W, BODY_H)
	corner(side, 12)
	edge(side, SKIN.ink, 2)

	local filled = frame(side, "Filled")
	filled.Size = UDim2.fromScale(1, 1)

	text(filled, {
		name = "GoingIn",
		position = UDim2.fromOffset(12, 8),
		size = UDim2.new(1, -24, 0, 14),
		textSize = 11,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		text = "GOING IN \u{00B7} tap one to swap it",
		ink = false,
	})
	local inputRow = frame(filled, "Inputs")
	inputRow.Position = UDim2.fromOffset(0, 26)
	inputRow.Size = UDim2.new(1, 0, 0, IN_H)
	local inputLayout = Instance.new("UIListLayout")
	inputLayout.FillDirection = Enum.FillDirection.Horizontal
	inputLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	inputLayout.SortOrder = Enum.SortOrder.LayoutOrder
	inputLayout.Padding = UDim.new(0, 8)
	inputLayout.Parent = inputRow
	local inputs: { Input } = {}
	for index = 1, Merge.INPUTS do
		inputs[index] = makeInput(inputRow, index)
	end

	text(filled, {
		name = "Arrow",
		position = UDim2.fromOffset(0, 140),
		size = UDim2.new(1, 0, 0, 20),
		textSize = 20,
		color = SKIN.purple,
		xAlign = Enum.TextXAlignment.Center,
		text = "\u{25BC}",
	})

	local out = frame(filled, "Out", SKIN.result)
	out.Position = UDim2.fromOffset(12, 164)
	out.Size = UDim2.new(1, -24, 0, 92)
	corner(out, 12)
	edge(out, SKIN.gold, 3)
	Studded.pattern(out, { radius = 12, tile = 22, bands = { 0.2, 0.47, 0.56, 0.64 }, bandTransparency = 0.75, glowTransparency = 0.7 })
	local outArt = frame(out, "Art")
	outArt.Position = UDim2.fromOffset(6, 4)
	outArt.Size = UDim2.fromOffset(84, 84)
	local outViewport = ItemArt.newViewport(outArt)
	local outName = text(out, {
		name = "ItemName",
		position = UDim2.fromOffset(96, 12),
		size = UDim2.new(1, -104, 0, 22),
		textSize = 19,
	})
	outName.TextTruncate = Enum.TextTruncate.AtEnd
	local outStars = text(out, {
		name = "Stars",
		position = UDim2.fromOffset(96, 38),
		size = UDim2.new(1, -104, 0, 18),
		textSize = 15,
		rich = true,
	})
	local outDetail = text(out, {
		name = "Detail",
		position = UDim2.fromOffset(96, 60),
		size = UDim2.new(1, -104, 0, 14),
		textSize = 12,
		color = Color3.fromHex("F3E2B0"),
		ink = false,
	})
	outDetail.TextTruncate = Enum.TextTruncate.AtEnd

	local function statRow(order: number, label: string): StatRow
		local row = frame(filled, `Stat{order}`)
		row.Position = UDim2.fromOffset(14, 264 + (order - 1) * 24)
		row.Size = UDim2.new(1, -28, 0, 22)
		local rule = frame(row, "Rule", SKIN.rule)
		rule.AnchorPoint = Vector2.new(0, 1)
		rule.Position = UDim2.fromScale(0, 1)
		rule.Size = UDim2.new(1, 0, 0, 1)
		local name = text(row, {
			name = "Name",
			size = UDim2.new(0.5, 0, 1, 0),
			textSize = 13,
			color = SKIN.dim,
			text = label,
			ink = false,
		})
		local value = text(row, {
			name = "Value",
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.fromScale(1, 0),
			size = UDim2.new(0.7, 0, 1, 0),
			textSize = 13,
			xAlign = Enum.TextXAlignment.Right,
			rich = true,
		})
		return { name = name, value = value }
	end
	local statValue = statRow(1, "Sell value")
	local statIncome = statRow(2, "Stand income")
	local statStars = statRow(3, "Merge stars")

	local buttons = frame(filled, "Buttons")
	buttons.Position = UDim2.fromOffset(12, 344)
	buttons.Size = UDim2.new(1, -24, 0, 46)
	local autoButton = bigButton(buttons, "AutoFill")
	autoButton.Size = UDim2.new(0.42, -4, 1, 0)
	autoButton.Text = "AUTO-FILL"
	Studded.fill(autoButton, SKIN.auto)
	local mergeButton = bigButton(buttons, "MergeButton")
	mergeButton.AnchorPoint = Vector2.new(1, 0)
	mergeButton.Position = UDim2.fromScale(1, 0)
	mergeButton.Size = UDim2.new(0.58, -4, 1, 0)

	local footer = text(filled, {
		name = "Footer",
		position = UDim2.fromOffset(12, 398),
		size = UDim2.new(1, -24, 0, 26),
		textSize = 11,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		rich = true,
		ink = false,
	})

	local sideHint = text(side, {
		name = "Hint",
		position = UDim2.fromOffset(24, 0),
		size = UDim2.new(1, -48, 1, 0),
		textSize = 15,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = PICK_TEXT,
		ink = false,
	})

	-- The reveal, laid over the merge side after a merge.
	local reveal = frame(side, "Reveal", SKIN.row)
	reveal.Size = UDim2.fromScale(1, 1)
	reveal.ZIndex = 20
	reveal.Visible = false
	corner(reveal, 12)
	local revealStroke = edge(reveal, SKIN.gold, 3)
	local revealScale = Instance.new("UIScale")
	revealScale.Parent = reveal
	local revealTitle = text(reveal, {
		name = "Title",
		position = UDim2.fromOffset(12, 40),
		size = UDim2.new(1, -24, 0, 44),
		textSize = 36,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 22,
	})
	local revealArt = frame(reveal, "Art")
	revealArt.AnchorPoint = Vector2.new(0.5, 0)
	revealArt.Position = UDim2.new(0.5, 0, 0, 96)
	revealArt.Size = UDim2.fromOffset(180, 160)
	revealArt.ZIndex = 21
	local revealViewport = ItemArt.newViewport(revealArt)
	revealViewport.ZIndex = 21
	local revealStars = text(reveal, {
		name = "Stars",
		position = UDim2.fromOffset(12, 266),
		size = UDim2.new(1, -24, 0, 28),
		textSize = 22,
		xAlign = Enum.TextXAlignment.Center,
		rich = true,
		zIndex = 22,
	})
	local revealLine = text(reveal, {
		name = "Line",
		position = UDim2.fromOffset(20, 302),
		size = UDim2.new(1, -40, 0, 44),
		textSize = 14,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		ink = false,
		zIndex = 22,
	})

	-- ── Behaviour ───────────────────────────────────────────────────────
	local tiles: { Tile } = {}
	local selectedId: string? = nil
	local picks: { string } = {}
	local mergeCallback: ((uids: { string }) -> ())? = nil
	local lastState: any = nil
	local groups: { [string]: Group } = {}
	local byUid: { [string]: any } = {}
	local canMerge = false
	local revealToken = 0
	local paint: (state: any) -> ()

	local function repaint()
		if lastState then
			paint(lastState)
		end
	end

	--- The best three copies of the picked nuke, or none if it cannot merge.
	local function autofill()
		table.clear(picks)
		local group = if selectedId then groups[selectedId] else nil
		if group == nil or #group.usable < Merge.INPUTS then
			return
		end
		for index = 1, Merge.INPUTS do
			table.insert(picks, group.usable[index].uid)
		end
	end

	--- Swap the copy in input `index` for the next usable copy not already going in.
	local function cycle(index: number)
		local group = if selectedId then groups[selectedId] else nil
		local current = picks[index]
		if group == nil or current == nil then
			return
		end
		local at = 0
		for i, item in group.usable do
			if item.uid == current then
				at = i
			end
		end
		for step = 1, #group.usable - 1 do
			local candidate = group.usable[(at + step - 1) % #group.usable + 1]
			if not table.find(picks, candidate.uid) then
				picks[index] = candidate.uid
				repaint()
				return
			end
		end
	end

	for index, input in inputs do
		input.button.MouseButton1Click:Connect(function()
			cycle(index)
		end)
	end

	local function tileAt(index: number): Tile
		local tile = tiles[index]
		if tile == nil then
			tile = makeTile(grid, index)
			tiles[index] = tile
			local tileButton = tile.button
			tileButton.MouseButton1Click:Connect(function()
				local itemId = tileButton:GetAttribute("ItemId")
				if tileButton:GetAttribute("Ready") == true and type(itemId) == "string" then
					selectedId = itemId
					autofill()
					repaint()
				end
			end)
		end
		return tile
	end

	autoButton.MouseButton1Click:Connect(function()
		if selectedId then
			autofill()
			repaint()
		end
	end)

	paint = function(state: any)
		lastState = state
		local cashNow = if type(state.cash) == "number" then state.cash else 0
		cash.Text = money(cashNow)

		-- Every washed, unslagged, unhearted copy you own, grouped by nuke. A hearted
		-- one (Shared/Bag) is the player's keep pile: auto-fill must never reach it.
		table.clear(groups)
		table.clear(byUid)
		local order: { Group } = {}
		local function add(list: any, where: string)
			for _, item in list or {} do
				if item.clean and item.identified and item.itemId and item.modifier ~= "Slagged" and item.hearted ~= true then
					local entry = table.clone(item)
					entry.where = where
					entry.merge = if type(item.merge) == "number" then item.merge else 0
					byUid[entry.uid] = entry
					local group = groups[entry.itemId]
					if group == nil then
						group = { itemId = entry.itemId, name = entry.name, rarity = entry.rarity, copies = {}, usable = {} }
						groups[entry.itemId] = group
						table.insert(order, group)
					end
					table.insert(group.copies, entry)
					if entry.merge < Merge.MAX_LEVEL then
						table.insert(group.usable, entry)
					end
				end
			end
		end
		add(state.items, "BAG")
		add(state.locker, "LOCKER")
		for _, group in order do
			table.sort(group.usable, function(a, b)
				if a.merge ~= b.merge then
					return a.merge > b.merge
				end
				return (a.value or 0) > (b.value or 0)
			end)
		end
		-- READY first, then the dearer nuke, then by name.
		table.sort(order, function(a, b)
			local readyA, readyB = #a.usable >= Merge.INPUTS, #b.usable >= Merge.INPUTS
			if readyA ~= readyB then
				return readyA
			end
			local valueA = if a.copies[1] then a.copies[1].value or 0 else 0
			local valueB = if b.copies[1] then b.copies[1].value or 0 else 0
			if valueA ~= valueB then
				return valueA > valueB
			end
			return a.name < b.name
		end)

		-- The selection follows its copies: one that left (sold, merged) re-fills the
		-- three, and a nuke that is no longer READY lets go.
		local group = if selectedId then groups[selectedId] else nil
		if group == nil or #group.usable < Merge.INPUTS then
			selectedId = nil
			table.clear(picks)
		else
			local stale = #picks ~= Merge.INPUTS
			for _, uid in picks do
				local item = byUid[uid]
				if item == nil or item.itemId ~= selectedId or item.merge >= Merge.MAX_LEVEL then
					stale = true
				end
			end
			if stale then
				autofill()
			end
		end

		for index, entry in order do
			local tile = tileAt(index)
			local usable = #entry.usable
			local ready = usable >= Merge.INPUTS
			local maxed = usable == 0
			local isSelected = entry.itemId == selectedId
			tile.button.Visible = true
			tile.button:SetAttribute("ItemId", entry.itemId)
			tile.button:SetAttribute("Ready", ready)
			tile.button.BackgroundTransparency = if ready then 0 else 0.45
			tile.stroke.Color = if isSelected then SKIN.purple else SKIN.ink
			tile.stroke.Thickness = if isSelected then 3 else 2
			tile.strip.BackgroundColor3 = rarityColor(entry.rarity)
			tile.name.Text = entry.name
			tile.count.Text = `\u{00D7}{#entry.copies} owned`
			tile.badge.Text = if ready then "READY" elseif maxed then "MAX" else `{usable}/{Merge.INPUTS}`
			tile.badge.BackgroundColor3 = if ready then SKIN.ready elseif maxed then SKIN.pink else SKIN.notReady
			tile.badge.TextColor3 = if ready or maxed then SKIN.ink else SKIN.dim
			ItemArt.paint(tile.viewport, entry.copies[1], (TILE_W - 16) / 62)
		end
		for index = #order + 1, #tiles do
			tiles[index].button.Visible = false
			ItemArt.clear(tiles[index].viewport)
		end
		gridEmpty.Visible = #order == 0
		sideHint.Text = if #order == 0 then EMPTY_TEXT else PICK_TEXT

		-- The merge side.
		local full = #picks == Merge.INPUTS
		filled.Visible = full
		sideHint.Visible = not full
		canMerge = false
		if not full then
			return
		end

		local records: { any } = {}
		local keep: any = nil
		local from = 0
		for index, uid in picks do
			local item = byUid[uid]
			records[index] = item
			from = math.max(from, item.merge)
			-- MergeService keeps the copy worth most as it stands.
			if keep == nil or (item.value or 0) > (keep.value or 0) then
				keep = item
			end
			local input = inputs[index]
			paintStars(input.stars, ratingOf(item), item.merge)
			input.detail.Text = detailOf(item)
			input.where.Text = item.where
			input.where.BackgroundColor3 = if item.where == "BAG" then SKIN.bag else SKIN.locker
			ItemArt.paint(input.viewport, item, (IN_W - 12) / 58)
		end

		local result = Merge.result(records, 1)
		local made = table.clone(keep)
		made.uid = result.uid
		made.modifier = result.modifier
		made.bonus = result.bonus
		made.merge = result.level
		local ratio = Merge.valueRatio(keep, result)
		outName.Text = keep.name
		paintStars(outStars, ratingOf(made), result.level)
		local qualities = Rarity.qualities(made.modifier, made.bonus)
		outDetail.Text = if #qualities > 0 then table.concat(qualities, " ") else detailOf(made)
		ItemArt.paint(outViewport, made, 1)

		local function change(before: number, after: number, suffix: string): string
			return `<font color="{hex(SKIN.muted)}"><s>{money(before)}{suffix}</s></font>  <font color="{hex(SKIN.cash)}">{money(after)}{suffix}</font>`
		end
		statValue.value.Text = change(keep.value or 0, (keep.value or 0) * ratio, "")
		statIncome.value.Text = change(keep.perSecond or 0, (keep.perSecond or 0) * ratio, "/s")
		statStars.value.Text =
			`<font color="{hex(SKIN.pink)}">{from} \u{2192} {result.level}</font>  <font color="{hex(SKIN.dim)}">(x{multText(result.level)})</font>`

		local odds = Merge.odds(from, if type(state.luck) == "number" then state.luck else 1)
		local fee = Merge.fee(keep.itemId, from, if type(state.mergeFeeMult) == "number" then state.mergeFeeMult else 1)
		local critText = if odds and odds.crit > 0
			then `  \u{00B7}  <font color="{hex(SKIN.pink)}">{math.floor(odds.crit * 100 + 0.5)}% chance of +2</font>`
			else ""
		footer.Text = `<font color="{hex(SKIN.ready)}">\u{2714} Always succeeds</font>{critText}`

		canMerge = cashNow >= fee
		mergeButton.Text = if canMerge then `MERGE \u{00B7} {money(fee)}` else `NEED {money(fee)}`
		Studded.fill(mergeButton, if canMerge then SKIN.go else SKIN.off)
		mergeButton.TextColor3 = if canMerge then SKIN.text else SKIN.muted
	end

	mergeButton.MouseButton1Click:Connect(function()
		if not canMerge or mergeCallback == nil or #picks ~= Merge.INPUTS then
			return
		end
		mergeCallback(table.clone(picks))
	end)

	local function showResult(result: any)
		if type(result) ~= "table" then
			return
		end
		-- The three went in; the next paint re-fills from what is left.
		table.clear(picks)
		local item = result.item
		local crit = result.outcome == "crit"
		local color = if crit then SKIN.pink else SKIN.gold
		revealStroke.Color = color
		revealTitle.TextColor3 = color
		revealTitle.Text = if crit then "CRITICAL! +2" else "MERGED! +1"
		if type(item) == "table" then
			paintStars(revealStars, ratingOf(item), if type(item.merge) == "number" then item.merge else 0)
			revealLine.Text = `{item.name} now sells and pays on a stand at x{multText(item.merge or 0)}.`
			ItemArt.paint(revealViewport, item, 180 / 160)
		end
		reveal.Visible = true
		revealScale.Scale = 0.6
		TweenService:Create(revealScale, POP, { Scale = 1 }):Play()
		revealToken += 1
		local token = revealToken
		task.delay(2.6, function()
			if token == revealToken then
				reveal.Visible = false
			end
		end)
		repaint()
	end

	return {
		frame = root,
		paint = function(state: any)
			paint(state)
		end,
		onMerge = function(callback: (uids: { string }) -> ())
			mergeCallback = callback
		end,
		showResult = showResult,
	}
end

return MergePanel
