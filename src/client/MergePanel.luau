--!strict
--[[
	MergePanel.luau — the Merge Reactor, drawn inside StationController's panel.

	PICKED FROM BROWSER MOCKUPS (option 1, "Triple Hopper Reactor", with its three-slot
	panel, over a type-strip checklist and a merge triangle). It wears the trader's
	field-kit slate and the hazard tape, like the locker, so the station panels read as
	one set.

	TOP TO BOTTOM:
	  the slots    three big slots with "+" between them, filled in the order you pick,
	               and beside them the RESULT CARD: what a success makes (the nuke, its
	               rating stars in gold and its merge stars in pink), the odds bar
	               (+1 / crit +2 / fail), your pity and luck, and MERGE with the fee.
	  the copies   every washed nuke you own, bag and Quarantine Locker together, sorted
	               by nuke. Picking one locks the grid to that nuke; a nuke you have fewer
	               than three of, or a copy already at max merge stars, is dimmed.

	The odds on the card are Config/Merge.odds over the pity and luck the server put on
	the StationState payload (DeconService), so the bar is the roll. Everything else is
	presentation: the client asks to merge three uids, MergeService re-derives the
	station, the ownership, the fee and the roll itself.
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

local MergePanel = {}

local SKIN = {
	card = Color3.fromHex("22272C"),
	well = Color3.fromHex("1A1E22"),
	edge = Color3.fromHex("343B42"),
	rule = Color3.fromHex("30373D"),
	slot = Color3.fromHex("4A5058"),
	amber = Color3.fromHex("F2A93B"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA0A6"),
	muted = Color3.fromHex("6C737A"),
	go = Color3.fromHex("3FBF5A"),
	off = Color3.fromHex("2A3036"),
	fail = Color3.fromHex("6C737A"),
	purple = Color3.fromHex("A855FF"),
	gold = Color3.fromHex("FFD24A"),
	pink = Merge.COLOR,
	bag = Color3.fromHex("4FD1C5"),
	locker = Color3.fromHex("A855FF"),
	hazard = Color3.fromHex("E8C33C"),
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.GothamBlack,
	label = Enum.Font.GothamBlack,
}

--- The widest the panel is allowed to get, padding included. Same as the trader's.
MergePanel.WIDTH = 860

local HEADER_H = 58
local WALLET_INSET = 44
local TOP_H = 176
local SLOT_W = 128
local SLOT_H = TOP_H
local PLUS_W = 30
local CARD_W = 300
local GRID_H = 240
local TILE_W = 92
local TILE_H = 108

local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function money(amount: number): string
	local grouped = tostring(math.floor(amount))
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

--- The small line under a copy: its quality modifier, else its size sticker, else its size.
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

local function ink(node: TextLabel | TextButton)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = SKIN.ink
	stroke.Thickness = math.clamp(node.TextSize / 9, 1.5, 3.5)
	stroke.Parent = node
	node.TextStrokeTransparency = 1
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = UIKit.label(parent, {
		name = props.name,
		position = props.position,
		size = props.size,
		anchorPoint = props.anchorPoint,
		font = props.font or SKIN.label,
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
	f.BackgroundColor3 = color or SKIN.card
	f.BackgroundTransparency = if color then 0 else 1
	f.Parent = parent
	return f
end

local function hazardBands(parent: Frame, count: number)
	parent.ClipsDescendants = true
	for index = 0, count - 1 do
		local band = frame(parent, `Band{index}`, if index % 2 == 0 then SKIN.hazard else SKIN.ink)
		band.Position = UDim2.fromScale(0, index / count)
		band.Size = UDim2.fromScale(1, 1 / count)
	end
end

local function chip(parent: Instance, name: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 16)
	label.BorderSizePixel = 0
	label.Font = SKIN.label
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

-- ── Build ───────────────────────────────────────────────────────────────

export type Panel = {
	frame: Frame,
	paint: (state: any) -> (),
	onMerge: (callback: (uids: { string }) -> ()) -> (),
	showResult: (result: any) -> (),
}

type Slot = {
	button: TextButton,
	stroke: UIStroke,
	viewport: ViewportFrame,
	stars: TextLabel,
	detail: TextLabel,
	empty: TextLabel,
}

type Tile = {
	button: TextButton,
	stroke: UIStroke,
	strip: Frame,
	viewport: ViewportFrame,
	stars: TextLabel,
	detail: TextLabel,
	where: TextLabel,
}

local function makeSlot(parent: Instance, index: number): Slot
	local button = Instance.new("TextButton")
	button.Name = `Slot{index}`
	button.LayoutOrder = index * 2
	button.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = SKIN.well
	button.Parent = parent
	corner(button, 14)
	local stroke = edge(button, SKIN.slot, 3)

	local art = frame(button, "Art")
	art.Position = UDim2.fromOffset(8, 10)
	art.Size = UDim2.new(1, -16, 0, 104)
	local viewport = ItemArt.newViewport(art)

	local stars = text(button, {
		name = "Stars",
		position = UDim2.fromOffset(4, 118),
		size = UDim2.new(1, -8, 0, 20),
		textSize = 15,
		xAlign = Enum.TextXAlignment.Center,
		rich = true,
	})
	local detail = text(button, {
		name = "Detail",
		position = UDim2.fromOffset(4, 140),
		size = UDim2.new(1, -8, 0, 16),
		textSize = 12,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		ink = false,
	})
	local empty = text(button, {
		name = "Empty",
		size = UDim2.fromScale(1, 1),
		textSize = 14,
		color = SKIN.muted,
		xAlign = Enum.TextXAlignment.Center,
		text = "EMPTY",
		ink = false,
	})
	return { button = button, stroke = stroke, viewport = viewport, stars = stars, detail = detail, empty = empty }
end

local function makeTile(parent: Instance, index: number): Tile
	local button = Instance.new("TextButton")
	button.Name = `Tile{index}`
	button.LayoutOrder = index
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = SKIN.card
	button.Parent = parent
	corner(button, 10)
	local stroke = edge(button, SKIN.edge, 2)

	local strip = frame(button, "RarityStrip", SKIN.dim)
	strip.Position = UDim2.fromOffset(10, 5)
	strip.Size = UDim2.new(1, -20, 0, 4)
	corner(strip, 2)

	local art = frame(button, "Art")
	art.Position = UDim2.fromOffset(6, 11)
	art.Size = UDim2.new(1, -12, 0, 50)
	local viewport = ItemArt.newViewport(art)

	local stars = text(button, {
		name = "Stars",
		position = UDim2.fromOffset(2, 62),
		size = UDim2.new(1, -4, 0, 14),
		textSize = 11,
		xAlign = Enum.TextXAlignment.Center,
		rich = true,
		ink = false,
	})
	local detail = text(button, {
		name = "Detail",
		position = UDim2.fromOffset(2, 76),
		size = UDim2.new(1, -4, 0, 13),
		textSize = 10,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		ink = false,
	})
	detail.TextTruncate = Enum.TextTruncate.AtEnd
	local where = chip(button, "Where")
	where.AnchorPoint = Vector2.new(0.5, 0)
	where.Position = UDim2.new(0.5, 0, 0, 90)
	return { button = button, stroke = stroke, strip = strip, viewport = viewport, stars = stars, detail = detail, where = where }
end

function MergePanel.new(parent: Instance, layoutOrder: number): Panel
	local root = frame(parent, "Merge")
	root.LayoutOrder = layoutOrder
	root.Size = UDim2.new(1, 0, 0, HEADER_H + 14 + TOP_H + 12 + GRID_H)
	root.Visible = false

	-- ── Header ─────────────────────────────────────────────────────────
	local header = frame(root, "Header")
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	local rule = frame(header, "Rule", SKIN.rule)
	rule.AnchorPoint = Vector2.new(0, 1)
	rule.Position = UDim2.fromScale(0, 1)
	rule.Size = UDim2.new(1, 0, 0, 1)
	local tape = frame(header, "HazardBar", SKIN.hazard)
	tape.AnchorPoint = Vector2.new(0, 0.5)
	tape.Position = UDim2.new(0, 0, 0.5, -1)
	tape.Size = UDim2.fromOffset(6, 40)
	hazardBands(tape, 6)
	text(header, {
		name = "Title",
		position = UDim2.fromOffset(18, 2),
		size = UDim2.fromOffset(420, 36),
		font = SKIN.headline,
		textSize = 34,
		text = "MERGE REACTOR",
	})
	text(header, {
		name = "Subtitle",
		position = UDim2.fromOffset(18, 36),
		size = UDim2.fromOffset(560, 16),
		textSize = 14,
		color = SKIN.dim,
		text = `{Merge.INPUTS} of the same nuke go in, 1 comes out. A success adds merge stars: x{Merge.VALUE_STEP} value and income each.`,
		ink = false,
	})
	text(header, {
		name = "CashLabel",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 6),
		size = UDim2.fromOffset(160, 14),
		textSize = 12,
		xAlign = Enum.TextXAlignment.Right,
		text = "CASH",
	})
	local cash = text(header, {
		name = "Cash",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 21),
		size = UDim2.fromOffset(200, 30),
		font = SKIN.headline,
		textSize = 26,
		color = SKIN.amber,
		xAlign = Enum.TextXAlignment.Right,
	})

	-- ── The slots ──────────────────────────────────────────────────────
	local topY = HEADER_H + 14
	local slotRow = frame(root, "Slots")
	slotRow.Position = UDim2.fromOffset(0, topY)
	slotRow.Size = UDim2.new(1, -(CARD_W + 12), 0, TOP_H)
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Padding = UDim.new(0, 6)
	slotLayout.Parent = slotRow

	local slots: { Slot } = {}
	for index = 1, Merge.INPUTS do
		if index > 1 then
			local plus = text(slotRow, {
				name = `Plus{index}`,
				size = UDim2.fromOffset(PLUS_W, 40),
				font = SKIN.headline,
				textSize = 30,
				color = SKIN.purple,
				xAlign = Enum.TextXAlignment.Center,
				text = "+",
			})
			plus.LayoutOrder = index * 2 - 1
		end
		slots[index] = makeSlot(slotRow, index)
	end

	-- The reveal, laid over the slots after a merge.
	local reveal = frame(root, "Reveal", SKIN.well)
	reveal.Position = UDim2.fromOffset(0, topY)
	reveal.Size = UDim2.new(1, -(CARD_W + 12), 0, TOP_H)
	reveal.ZIndex = 20
	reveal.Visible = false
	corner(reveal, 14)
	local revealStroke = edge(reveal, SKIN.gold, 3)
	local revealScale = Instance.new("UIScale")
	revealScale.Parent = reveal
	local revealArt = frame(reveal, "Art")
	revealArt.Position = UDim2.fromOffset(16, 12)
	revealArt.Size = UDim2.fromOffset(150, TOP_H - 24)
	revealArt.ZIndex = 21
	local revealViewport = ItemArt.newViewport(revealArt)
	revealViewport.ZIndex = 21
	local revealTitle = text(reveal, {
		name = "Title",
		position = UDim2.fromOffset(180, 24),
		size = UDim2.new(1, -196, 0, 44),
		font = SKIN.headline,
		textSize = 38,
	})
	revealTitle.ZIndex = 22
	local revealStars = text(reveal, {
		name = "Stars",
		position = UDim2.fromOffset(180, 74),
		size = UDim2.new(1, -196, 0, 30),
		textSize = 24,
		rich = true,
	})
	revealStars.ZIndex = 22
	local revealLine = text(reveal, {
		name = "Line",
		position = UDim2.fromOffset(180, 108),
		size = UDim2.new(1, -196, 0, 40),
		textSize = 15,
		color = SKIN.dim,
		wrapped = true,
		ink = false,
	})
	revealLine.ZIndex = 22

	-- ── The result card ────────────────────────────────────────────────
	local card = frame(root, "Result", SKIN.card)
	card.AnchorPoint = Vector2.new(1, 0)
	card.Position = UDim2.new(1, 0, 0, topY)
	card.Size = UDim2.fromOffset(CARD_W, TOP_H)
	corner(card, 12)
	edge(card, SKIN.edge, 2)

	text(card, {
		name = "Caption",
		position = UDim2.fromOffset(12, 8),
		size = UDim2.new(1, -24, 0, 14),
		textSize = 12,
		color = SKIN.dim,
		text = "ON A SUCCESS",
		ink = false,
	})
	local cardName = text(card, {
		name = "ItemName",
		position = UDim2.fromOffset(12, 22),
		size = UDim2.new(1, -24, 0, 24),
		font = SKIN.headline,
		textSize = 21,
	})
	cardName.TextTruncate = Enum.TextTruncate.AtEnd
	local cardStars = text(card, {
		name = "Stars",
		position = UDim2.fromOffset(12, 47),
		size = UDim2.new(1, -24, 0, 20),
		textSize = 17,
		rich = true,
	})
	local cardGain = text(card, {
		name = "Gain",
		position = UDim2.fromOffset(12, 68),
		size = UDim2.new(1, -24, 0, 15),
		textSize = 12,
		color = Color3.fromHex("BFE9E4"),
		ink = false,
	})

	local bar = frame(card, "Odds", SKIN.fail)
	bar.Position = UDim2.fromOffset(12, 88)
	bar.Size = UDim2.new(1, -24, 0, 20)
	bar.ClipsDescendants = true
	corner(bar, 8)
	edge(bar, SKIN.ink, 2)
	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = bar
	local function segment(name: string, color: Color3, order: number, textColor: Color3): TextLabel
		local seg = Instance.new("TextLabel")
		seg.Name = name
		seg.LayoutOrder = order
		seg.BorderSizePixel = 0
		seg.BackgroundColor3 = color
		seg.Font = SKIN.label
		seg.TextSize = 11
		seg.TextColor3 = textColor
		seg.ClipsDescendants = true
		seg.Parent = bar
		return seg
	end
	local segCrit = segment("Crit", SKIN.pink, 1, SKIN.ink)
	local segWin = segment("Win", SKIN.go, 2, SKIN.ink)
	local segFail = segment("Fail", SKIN.fail, 3, SKIN.text)

	local cardPity = text(card, {
		name = "Pity",
		position = UDim2.fromOffset(12, 110),
		size = UDim2.new(1, -24, 0, 14),
		textSize = 11,
		color = SKIN.dim,
		ink = false,
		rich = true,
	})

	local button = Instance.new("TextButton")
	button.Name = "MergeButton"
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, 12, 1, -10)
	button.Size = UDim2.new(1, -24, 0, 40)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = SKIN.headline
	button.TextSize = 21
	button.TextColor3 = SKIN.text
	button.Parent = card
	corner(button, 12)
	ink(button)
	edge(button, SKIN.ink, 3)

	local cardHint = text(card, {
		name = "Hint",
		position = UDim2.fromOffset(16, 22),
		size = UDim2.new(1, -32, 0, 90),
		textSize = 14,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = `Pick {Merge.INPUTS} copies of one nuke below. A fail keeps your best copy and adds +{math.floor(Merge.PITY_STEP * 100 + 0.5)}% to that nuke's next try.`,
		ink = false,
	})

	-- ── The copies ─────────────────────────────────────────────────────
	local gridY = topY + TOP_H + 12
	local copies = frame(root, "Copies", SKIN.well)
	copies.Position = UDim2.fromOffset(0, gridY)
	copies.Size = UDim2.new(1, 0, 0, GRID_H)
	corner(copies, 12)
	edge(copies, SKIN.edge, 2)
	local gridTitle = text(copies, {
		name = "Title",
		position = UDim2.fromOffset(12, 7),
		size = UDim2.new(1, -24, 0, 16),
		textSize = 13,
		color = SKIN.dim,
		ink = false,
	})
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(10, 28)
	grid.Size = UDim2.new(1, -20, 1, -34)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 5
	grid.ScrollBarImageColor3 = SKIN.edge
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = copies
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, 2)
	gridPad.PaddingLeft = UDim.new(0, 2)
	gridPad.Parent = grid
	local gridEmpty = text(copies, {
		name = "Empty",
		position = UDim2.fromOffset(12, 28),
		size = UDim2.new(1, -24, 1, -34),
		textSize = 15,
		color = SKIN.muted,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = "No washed nukes in your bag or locker. Wash a find at a cleansing station first.",
		ink = false,
	})

	-- ── Behaviour ───────────────────────────────────────────────────────
	local tiles: { Tile } = {}
	local selected: { string } = {}
	local mergeCallback: ((uids: { string }) -> ())? = nil
	local lastState: any = nil
	local canMerge = false
	local revealToken = 0
	local paint: (state: any) -> ()

	local function repaint()
		if lastState then
			paint(lastState)
		end
	end

	local function toggle(uid: any)
		if type(uid) ~= "string" then
			return
		end
		local at = table.find(selected, uid)
		if at then
			table.remove(selected, at)
		elseif #selected < Merge.INPUTS then
			table.insert(selected, uid)
		end
		repaint()
	end

	for _, slot in slots do
		slot.button.MouseButton1Click:Connect(function()
			toggle(slot.button:GetAttribute("Uid"))
		end)
	end

	local function tileAt(index: number): Tile
		local tile = tiles[index]
		if tile == nil then
			tile = makeTile(grid, index)
			tiles[index] = tile
			local tileButton = tile.button
			tileButton.MouseButton1Click:Connect(function()
				if tileButton:GetAttribute("Pickable") == true or table.find(selected, tileButton:GetAttribute("Uid")) then
					toggle(tileButton:GetAttribute("Uid"))
				end
			end)
		end
		return tile
	end

	local function paintSlot(slot: Slot, item: any?)
		if item == nil then
			slot.button:SetAttribute("Uid", nil)
			slot.stroke.Color = SKIN.slot
			slot.empty.Visible = true
			slot.stars.Text = ""
			slot.detail.Text = ""
			ItemArt.clear(slot.viewport)
			return
		end
		slot.button:SetAttribute("Uid", item.uid)
		slot.stroke.Color = SKIN.purple
		slot.empty.Visible = false
		paintStars(slot.stars, ratingOf(item), item.merge or 0)
		slot.detail.Text = detailOf(item)
		ItemArt.paint(slot.viewport, item, (SLOT_W - 16) / 104)
	end

	paint = function(state: any)
		lastState = state
		local cashNow = if type(state.cash) == "number" then state.cash else 0
		cash.Text = money(cashNow)

		-- Every washed, unslagged nuke you own, with where it lives.
		local owned: { any } = {}
		local byUid: { [string]: any } = {}
		local counts: { [string]: number } = {}
		local function add(list: any, where: string)
			for _, item in list or {} do
				if item.clean and item.identified and item.itemId and item.modifier ~= "Slagged" then
					local entry = table.clone(item)
					entry.where = where
					entry.merge = if type(item.merge) == "number" then item.merge else 0
					table.insert(owned, entry)
					byUid[entry.uid] = entry
					counts[entry.itemId] = (counts[entry.itemId] or 0) + 1
				end
			end
		end
		add(state.items, "BAG")
		add(state.locker, "LOCKER")
		table.sort(owned, function(a, b)
			if a.name ~= b.name then
				return a.name < b.name
			end
			if a.merge ~= b.merge then
				return a.merge > b.merge
			end
			return (a.value or 0) > (b.value or 0)
		end)

		-- The selection follows its copies; one that left (sold, merged) just drops.
		for index = #selected, 1, -1 do
			if byUid[selected[index]] == nil then
				table.remove(selected, index)
			end
		end
		local lockedTo: string? = if #selected > 0 then byUid[selected[1]].itemId else nil

		for index, slot in slots do
			paintSlot(slot, if selected[index] then byUid[selected[index]] else nil)
		end

		for index, item in owned do
			local tile = tileAt(index)
			local isSelected = table.find(selected, item.uid) ~= nil
			local maxed = item.merge >= Merge.MAX_LEVEL
			local pickable = not maxed
				and (counts[item.itemId] or 0) >= Merge.INPUTS
				and (lockedTo == nil or lockedTo == item.itemId)
				and #selected < Merge.INPUTS
			tile.button.Visible = true
			tile.button:SetAttribute("Uid", item.uid)
			tile.button:SetAttribute("Pickable", pickable)
			tile.button.BackgroundTransparency = if isSelected or pickable then 0 else 0.55
			tile.stroke.Color = if isSelected then SKIN.purple else SKIN.edge
			tile.stroke.Thickness = if isSelected then 3 else 2
			tile.strip.BackgroundColor3 = rarityColor(item.rarity)
			paintStars(tile.stars, ratingOf(item), item.merge)
			tile.detail.Text = if maxed then "MAX STARS" else `{item.name} \u{00B7} {detailOf(item)}`
			tile.where.Text = item.where
			tile.where.BackgroundColor3 = if item.where == "BAG" then SKIN.bag else SKIN.locker
			ItemArt.paint(tile.viewport, item, (TILE_W - 12) / 50)
		end
		for index = #owned + 1, #tiles do
			tiles[index].button.Visible = false
			ItemArt.clear(tiles[index].viewport)
		end
		gridEmpty.Visible = #owned == 0
		gridTitle.Text = if lockedTo
			then `YOUR {string.upper(byUid[selected[1]].name)}S \u{00B7} {#selected}/{Merge.INPUTS} picked \u{00B7} click a slot to take one back out`
			else `YOUR WASHED NUKES (bag + locker) \u{00B7} pick {Merge.INPUTS} of one kind`

		-- The result card.
		local full = #selected == Merge.INPUTS
		local first = if lockedTo then byUid[selected[1]] else nil
		cardHint.Visible = first == nil
		for _, node in { cardName, cardStars, cardGain, bar, cardPity } :: { GuiObject } do
			node.Visible = first ~= nil
		end
		canMerge = false
		if first == nil then
			button.Text = "MERGE"
			button.BackgroundColor3 = SKIN.off
			button.TextColor3 = SKIN.muted
			return
		end

		-- What a success would make: the best modifier, the biggest roll, one level up.
		local from, bestModifier, bigUid, bigPayload = 0, first.modifier or "None", first.uid, -math.huge
		for _, uid in selected do
			local item = byUid[uid]
			from = math.max(from, item.merge)
			if Merge.modifierRank(item.modifier) < Merge.modifierRank(bestModifier) then
				bestModifier = item.modifier
			end
			local payload = Payload.forUid(uid)
			if payload > bigPayload then
				bigUid, bigPayload = uid, payload
			end
		end
		local pityTable = if type(state.mergePity) == "table" then state.mergePity else {}
		local pity = if type(pityTable[first.itemId]) == "number" then pityTable[first.itemId] else 0
		local luck = if type(state.luck) == "number" then state.luck else 1
		local bonus = if type(state.mergeBonus) == "number" then state.mergeBonus else 0
		local odds = Merge.odds(from, pity, luck, bonus)
		local fee = Merge.fee(first.itemId, from)

		cardName.Text = first.name
		if odds == nil then
			paintStars(cardStars, ratingOf(first), from)
			cardGain.Text = "Already at max merge stars"
			bar.Visible = false
			cardPity.Visible = false
			button.Text = "MAXED"
			button.BackgroundColor3 = SKIN.off
			button.TextColor3 = SKIN.muted
			return
		end
		local rating = Rarity.stars(first.rarity, bestModifier, Payload.forUid(bigUid), nil, Items.stageOf(first.itemId))
		paintStars(cardStars, rating, odds.target)
		cardGain.Text = `+1 merge star \u{00B7} x{multText(odds.target)} value & income`

		local critShare = odds.crit
		local winShare = odds.success - odds.crit
		local failShare = 1 - odds.success
		segCrit.Size = UDim2.fromScale(critShare, 1)
		segCrit.Visible = critShare > 0
		segCrit.Text = if critShare >= 0.08 then `+2 {math.floor(critShare * 100 + 0.5)}%` else ""
		segWin.Size = UDim2.fromScale(winShare, 1)
		segWin.Text = `+1 {math.floor(winShare * 100 + 0.5)}%`
		segFail.Size = UDim2.fromScale(failShare, 1)
		segFail.Visible = failShare > 0
		segFail.Text = if failShare >= 0.1 then `FAIL {math.floor(failShare * 100 + 0.5)}%` else ""

		local pityText = if pity > 0
			then `Pity <font color="{hex(SKIN.gold)}">+{math.floor(math.min(pity * Merge.PITY_STEP, 1) * 100 + 0.5)}%</font> from {pity} fail{if pity == 1 then "" else "s"}`
			else "No pity yet"
		local luckBonus = math.max(0, odds.crit - Merge.CRIT)
		cardPity.Text = if odds.crit > 0 and luckBonus > 0.004
			then `{pityText} \u{00B7} Luck +{math.floor(luckBonus * 100 + 0.5)}% crit`
			else pityText

		canMerge = full and cashNow >= fee
		button.Text = if not full
			then `PICK {Merge.INPUTS - #selected} MORE`
			elseif cashNow < fee then `NEED {money(fee)}`
			else `MERGE \u{00B7} {money(fee)}`
		button.BackgroundColor3 = if canMerge then SKIN.go else SKIN.off
		button.TextColor3 = if canMerge then SKIN.text else SKIN.muted
	end

	button.MouseButton1Click:Connect(function()
		if not canMerge or mergeCallback == nil then
			return
		end
		mergeCallback(table.clone(selected))
	end)

	local function showResult(result: any)
		if type(result) ~= "table" then
			return
		end
		table.clear(selected)
		local item = result.item
		local outcome = result.outcome
		local color = if outcome == "crit" then SKIN.pink elseif outcome == "success" then SKIN.gold else SKIN.dim
		revealStroke.Color = color
		revealTitle.TextColor3 = color
		revealTitle.Text = if outcome == "crit"
			then "CRITICAL! +2"
			elseif outcome == "success" then "SUCCESS! +1"
			else "FIZZLED"
		if type(item) == "table" then
			paintStars(revealStars, ratingOf(item), if type(item.merge) == "number" then item.merge else 0)
			revealLine.Text = if outcome == "fail"
				then `Your best {item.name} survived. Next try on this nuke: +{math.floor(Merge.PITY_STEP * 100 + 0.5)}% pity.`
				else `{item.name} now sells and pays on a stand at x{multText(item.merge or 0)}.`
			ItemArt.paint(revealViewport, item, 150 / (TOP_H - 24))
		end
		reveal.Visible = true
		revealScale.Scale = 0.6
		TweenService:Create(revealScale, POP, { Scale = 1 }):Play()
		revealToken += 1
		local token = revealToken
		task.delay(3.2, function()
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
