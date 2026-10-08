--!strict
--[[
	TraderPanel.luau — the trader's buyback counter, drawn inside StationController's panel.

	PICKED FROM BROWSER MOCKUPS (option 2, "receipt counter"), replacing the field-kit
	tile grid. Square corners throughout, like the Gear and Nukes panels.

	TWO PIECES, LEFT TO RIGHT:
	  the bag      one row per item in the bag: its model on a grey block, its name in
	               its rarity colour, rarity and stars under it, a CRUSTED tag while it
	               is "???", its sale price and a tick box. Clicking a row ticks it.
	               Ordered by the header's SORT pill (pref `traderSort`): price high-low,
	               price low-high, or rarest first. The receipt follows the same order.
	  the receipt  a paper slip listing every ticked item and their total, then SELL,
	               the only button that actually sells. Under it SELL ALL, SELL ALL CLEAN
	               and SELL ALL UNCLEAN, which only TICK -- they put that group on the
	               receipt so the player sees the bill before confirming it.

	THE MODEL IS THE REAL ONE, OR THE CRUST (client/ItemArt, shared with the locker
	panel): ItemModels' model once the item is identified, ItemCrust.lump seeded on its
	uid while it is "???". Built once per row per item, not on every StationState tick.

	Everything here is presentation. The client asks for a sale by a list of uids;
	EconomyService re-derives each price and checks each item is still in the bag.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Payload = require(Shared.Config.Payload)
local Merge = require(Shared.Config.Merge)
local Tuning = require(Shared.Config.Tuning)
local Mastery = require(Shared.Mastery) -- Mastery.short: "$360M"

local UIKit = require(script.Parent.UIKit)
local StarLine = require(script.Parent.StarLine)
local Prefs = require(script.Parent.Prefs)
local ItemArt = require(script.Parent.ItemArt)
local Studded = require(script.Parent.Studded)

local TraderPanel = {}

-- The shop panel's FIELD palette, the subset this panel uses, plus the receipt's paper.
-- StationController keeps its copy file-local on purpose (see its note), so this is a
-- copy rather than a reach.
local SKIN = {
	-- Near-black like the Nukes panel's rows, to stand off the dark studded backdrop
	-- StationController lays under the trader since 2026-10-05.
	row = Color3.fromHex("16181C"),
	block = Color3.fromHex("3A3E45"),
	-- The glossy L-stud title bar (2026-10-05, on request), dark navy like the Nukes
	-- panel's rather than the gear shop's purple.
	header = ColorSequence.new(Color3.fromHex("2C3E6B"), Color3.fromHex("1C2848")),
	edge = Color3.fromHex("343B42"),
	amber = Color3.fromHex("F2A93B"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA0A6"),
	muted = Color3.fromHex("6C737A"),
	button = Color3.fromHex("2A3036"),
	sell = UIKit.House.buy,
	cash = UIKit.House.cash,
	crustChip = Color3.fromHex("6B4A2B"),
	crustText = Color3.fromHex("F3D9B0"),
	paper = Color3.fromHex("EFE9DC"),
	paperInk = Color3.fromHex("222222"),
	paperDim = Color3.fromHex("77716A"),
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.GothamBlack,
	label = Enum.Font.GothamBlack,
	receipt = Enum.Font.RobotoMono,
}
-- The hotbar's heart pink (InventoryController's HEART_RED).
local HEARTED_CHIP = Color3.fromHex("FF4D6D")
local HEARTED_W = 74

local HEADER_H = 58
-- The header box sits this far up into the panel's top padding.
local HEADER_LIFT = 8
local HEADER_PAD = 14
-- Where the list and the receipt start.
local BODY_TOP = HEADER_H - HEADER_LIFT + 12
local BODY_GAP = 12
local BODY_H = 460
local ROW_H = 62
local ROW_GAP = 6
local ART_W = 70
local TICK = 26
local SCROLLBAR = 6
local RECEIPT_W = 280
local RECEIPT_PAD = 16
local LINE_H = 18
local SELL_H = 52
local BULK_H = 34
local BULK_GAP = 6
local WALLET_INSET = 44
-- The header's SORT pill, the gear shop's filter pill size.
local SORT_W = 190
local SORT_H = 34

local SORT_OPTIONS = { "high", "low", "rarity" }
local SORT_TEXT = { high = "PRICE: HIGH-LOW", low = "PRICE: LOW-HIGH", rarity = "SORT: RARITY" }

--- The widest the trader's panel is allowed to get, padding included. StationController
--- sets the panel's MaxSize to this in trader mode.
TraderPanel.WIDTH = 860

local function money(amount: number): string
	if math.abs(amount) >= 1e6 then
		return "$" .. Mastery.short(amount) -- "$360M", not "$360,000,000"
	end
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

local function rarityColor(name: string?): Color3
	local def = if name then Rarity.DEFS[name] else nil
	return if def then def.color else SKIN.dim
end

--- This find's star rating: its rarity tier, nudged by its quality, size roll and
--- home stage (drawn with half stars by StarLine).
local function ratingOf(item: any): number
	local payload = if type(item.uid) == "string" then Payload.forUid(item.uid) else nil
	return Rarity.stars(item.rarity, item.modifier, payload, item.bonus, Items.stageOf(item.itemId))
end

--- Where a rarity sits on the ladder (Scrap 1 .. Anomaly 8), 0 when unknown.
local function rarityRank(name: string?): number
	return (if name then table.find(Rarity.ORDER, name) else nil) or 0
end

--- The bag in the SORT pill's order (pref `traderSort`): a sorted COPY, so the state's
--- own list is left alone. Ties fall back on the name and then the uid, so rows never
--- shuffle between StationState ticks.
local function sortedItems(items: { any }): { any }
	local mode = Prefs.get("traderSort")
	local out = table.clone(items)
	table.sort(out, function(a, b)
		local va, vb = a.value or 0, b.value or 0
		if mode == "rarity" then
			local ra, rb = rarityRank(a.rarity), rarityRank(b.rarity)
			if ra ~= rb then
				return ra > rb
			end
			if va ~= vb then
				return va > vb
			end
		elseif va ~= vb then
			return if mode == "low" then va < vb else va > vb
		end
		local na, nb = tostring(a.name or ""), tostring(b.name or "")
		if na ~= nb then
			return na < nb
		end
		return tostring(a.uid) < tostring(b.uid)
	end)
	return out
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	return UIKit.label(parent, {
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
		strokeTransparency = 1,
	})
end

local function edge(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
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

local function button(parent: Instance, name: string, color: Color3, textSize: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Font = SKIN.headline
	b.TextSize = textSize
	b.TextColor3 = SKIN.text
	b.Parent = parent
	return b
end

-- ── Build ───────────────────────────────────────────────────────────────

export type Panel = {
	frame: Frame,
	paint: (state: any) -> (),
	onSellMany: (callback: (uids: { string }) -> ()) -> (),
}

local function makeRow(parent: Instance, order: number): TextButton
	local row = Instance.new("TextButton")
	row.Name = `Row{order}`
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -(SCROLLBAR + 6), 0, ROW_H)
	row.Text = ""
	row.AutoButtonColor = false
	row.BorderSizePixel = 0
	row.BackgroundColor3 = SKIN.row
	row.Parent = parent
	local stroke = edge(row, SKIN.sell, 3)
	stroke.Name = "Edge"

	local art = frame(row, "Art", SKIN.block)
	art.Size = UDim2.fromOffset(ART_W, ROW_H)
	ItemArt.newViewport(art)

	local nameLabel = text(row, {
		name = "ItemName",
		position = UDim2.fromOffset(ART_W + 12, 9),
		size = UDim2.new(1, -(ART_W + 12 + 170), 0, 22),
		textSize = 17,
	})
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local sub = text(row, {
		name = "Sub",
		position = UDim2.fromOffset(ART_W + 12, 33),
		size = UDim2.new(1, -(ART_W + 12 + 170), 0, 16),
		textSize = 12,
	})
	sub.RichText = true

	local crusted = text(row, {
		name = "Crusted",
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -168, 0.5, 0),
		size = UDim2.fromOffset(64, 18),
		textSize = 11,
		color = SKIN.crustText,
		xAlign = Enum.TextXAlignment.Center,
		text = "CRUSTED",
	})
	crusted.BackgroundColor3 = SKIN.crustChip
	crusted.BackgroundTransparency = 0

	-- A hearted nuke (Shared/Bag) can't go on the receipt: this chip takes its tick
	-- box's place and says why (paintRow shifts the price left to fit it).
	local hearted = text(row, {
		name = "Hearted",
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -12, 0.5, 0),
		size = UDim2.fromOffset(HEARTED_W, 22),
		textSize = 12,
		color = SKIN.text,
		xAlign = Enum.TextXAlignment.Center,
		text = "HEARTED",
	})
	hearted.BackgroundColor3 = HEARTED_CHIP
	hearted.BackgroundTransparency = 0
	hearted.Visible = false

	text(row, {
		name = "Price",
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -(TICK + 24), 0.5, 0),
		size = UDim2.fromOffset(110, 24),
		textSize = 20,
		color = SKIN.cash,
		xAlign = Enum.TextXAlignment.Right,
	})

	-- The tick box. The check is two bars, not a glyph: no game font has U+2713.
	local tick = frame(row, "Tick", SKIN.sell)
	tick.AnchorPoint = Vector2.new(1, 0.5)
	tick.Position = UDim2.new(1, -12, 0.5, 0)
	tick.Size = UDim2.fromOffset(TICK, TICK)
	local tickEdge = edge(tick, SKIN.muted, 3)
	tickEdge.Name = "Edge"
	local check = frame(tick, "Check")
	check.Size = UDim2.fromScale(1, 1)
	local short = frame(check, "Short", SKIN.text)
	short.AnchorPoint = Vector2.new(0.5, 0.5)
	short.Position = UDim2.fromOffset(8, 15)
	short.Size = UDim2.fromOffset(9, 4)
	short.Rotation = 45
	local long = frame(check, "Long", SKIN.text)
	long.AnchorPoint = Vector2.new(0.5, 0.5)
	long.Position = UDim2.fromOffset(15, 12)
	long.Size = UDim2.fromOffset(16, 4)
	long.Rotation = -50
	return row
end

function TraderPanel.new(parent: Instance, layoutOrder: number): Panel
	local root = frame(parent, "Trader")
	root.LayoutOrder = layoutOrder
	root.Size = UDim2.new(1, 0, 0, BODY_TOP + BODY_H)
	root.Visible = false

	-- ── Header ─────────────────────────────────────────────────────────
	-- Title and wallet on the Nukes panel's navy patterned header.
	local header = frame(root, "Header")
	header.Position = UDim2.fromOffset(0, -HEADER_LIFT)
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	Studded.fill(header, SKIN.header)
	edge(header, SKIN.ink, 2)
	local headerPad = Instance.new("UIPadding")
	headerPad.PaddingLeft = UDim.new(0, HEADER_PAD)
	headerPad.Parent = header
	-- Under the header's left padding like the labels, so pushed back out to its edge.
	local headerPattern = Studded.pattern(header, { tile = 22, bands = { 0.28, 0.5, 0.58, 0.64 } })
	headerPattern.Position = UDim2.fromOffset(-HEADER_PAD, 0)
	headerPattern.Size = UDim2.new(1, HEADER_PAD, 1, 0)

	text(header, {
		name = "Title",
		position = UDim2.fromOffset(0, 4),
		size = UDim2.fromOffset(300, 36),
		font = SKIN.headline,
		textSize = 32,
		text = "Trader",
	})
	local subtitle = text(header, {
		name = "Subtitle",
		position = UDim2.fromOffset(0, 37),
		size = UDim2.fromOffset(420, 16),
		textSize = 12,
		color = SKIN.dim,
	})

	-- Inset from the right by the close badge, which sits over this corner.
	text(header, {
		name = "WalletLabel",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 8),
		size = UDim2.fromOffset(200, 14),
		textSize = 11,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Right,
		text = "On hand",
	})
	local wallet = text(header, {
		name = "Wallet",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 22),
		size = UDim2.fromOffset(240, 30),
		font = SKIN.headline,
		textSize = 26,
		color = SKIN.cash,
		xAlign = Enum.TextXAlignment.Right,
	})

	-- The SORT pill, centred between the title and the wallet. Each press steps pref
	-- `traderSort` to its next option; the observer below repaints.
	local sortPill = UIKit.button(header, {
		name = "Sort",
		size = UDim2.fromOffset(SORT_W, SORT_H),
		font = SKIN.headline,
		textSize = 16,
		color = SKIN.text,
		fillColor = SKIN.edge,
		fillTransparency = 0,
		cornerRadius = UDim.new(0.5, 0),
		strokeColor = SKIN.ink,
		strokeThickness = 2,
		outline = false,
	})
	sortPill.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Back by half the header's left padding, so it centres on the box, not the inset.
	sortPill.Position = UDim2.new(0.5, -HEADER_PAD / 2, 0.5, 0)

	-- ── The bag list ────────────────────────────────────────────────────
	local list = Instance.new("ScrollingFrame")
	list.Name = "Bag"
	list.Position = UDim2.fromOffset(0, BODY_TOP)
	list.Size = UDim2.new(1, -(RECEIPT_W + BODY_GAP), 0, BODY_H)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = SCROLLBAR
	list.ScrollBarImageColor3 = SKIN.edge
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = root
	-- Room for the ticked rows' 3px border, which draws outside the row.
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 3)
	listPad.PaddingLeft = UDim.new(0, 3)
	listPad.Parent = list

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, ROW_GAP)
	listLayout.Parent = list

	local emptyBag = text(root, {
		name = "EmptyBag",
		position = UDim2.fromOffset(0, BODY_TOP),
		size = UDim2.new(1, -(RECEIPT_W + BODY_GAP), 0, BODY_H),
		textSize = 18,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		text = "Your bag is empty.",
	})

	local rows: { TextButton } = {}

	-- ── The receipt ─────────────────────────────────────────────────────
	local paper = frame(root, "Receipt", SKIN.paper)
	paper.AnchorPoint = Vector2.new(1, 0)
	paper.Position = UDim2.new(1, 0, 0, BODY_TOP)
	paper.Size = UDim2.fromOffset(RECEIPT_W, BODY_H)
	local inner = frame(paper, "Inner")
	inner.Position = UDim2.fromOffset(RECEIPT_PAD, RECEIPT_PAD)
	inner.Size = UDim2.new(1, -2 * RECEIPT_PAD, 1, -2 * RECEIPT_PAD)

	text(inner, {
		name = "Title",
		size = UDim2.new(1, 0, 0, 24),
		font = SKIN.headline,
		textSize = 20,
		color = SKIN.paperInk,
		xAlign = Enum.TextXAlignment.Center,
		text = "RECEIPT",
	})

	local function dashes(name: string, y: UDim): TextLabel
		local rule = text(inner, {
			name = name,
			position = UDim2.new(0, 0, y.Scale, y.Offset),
			size = UDim2.new(1, 0, 0, 12),
			font = SKIN.receipt,
			textSize = 12,
			color = SKIN.paperDim,
			xAlign = Enum.TextXAlignment.Center,
			text = string.rep("- ", 20),
		})
		rule.ClipsDescendants = true
		return rule
	end

	-- Everything under the line list, measured up from the bottom.
	local bulkBlock = 3 * BULK_H + 2 * BULK_GAP
	local sellTop = bulkBlock + 10 + SELL_H
	local totalTop = sellTop + 10 + 26
	local noteTop = totalTop + 16
	local lowerRuleTop = noteTop + 14

	dashes("RuleTop", UDim.new(0, 28))
	local lines = Instance.new("ScrollingFrame")
	lines.Name = "Lines"
	lines.Position = UDim2.fromOffset(0, 44)
	lines.Size = UDim2.new(1, 0, 1, -(44 + lowerRuleTop + 4))
	lines.BackgroundTransparency = 1
	lines.BorderSizePixel = 0
	lines.ScrollingDirection = Enum.ScrollingDirection.Y
	lines.ScrollBarThickness = 3
	lines.ScrollBarImageColor3 = SKIN.paperDim
	lines.CanvasSize = UDim2.new()
	lines.AutomaticCanvasSize = Enum.AutomaticSize.Y
	lines.Parent = inner
	local lineLayout = Instance.new("UIListLayout")
	lineLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lineLayout.Parent = lines

	local nothing = text(lines, {
		name = "Nothing",
		size = UDim2.new(1, 0, 0, LINE_H),
		font = SKIN.receipt,
		textSize = 13,
		color = SKIN.paperDim,
		text = "nothing selected",
	})
	nothing.LayoutOrder = 0

	local lineLabels: { Frame } = {}
	local function lineAt(index: number): Frame
		local line = lineLabels[index]
		if line == nil then
			line = frame(lines, `Line{index}`)
			line.LayoutOrder = index
			line.Size = UDim2.new(1, -6, 0, LINE_H)
			local name = text(line, {
				name = "ItemName",
				size = UDim2.new(1, -86, 1, 0),
				font = SKIN.receipt,
				textSize = 13,
				color = SKIN.paperInk,
			})
			name.TextTruncate = Enum.TextTruncate.AtEnd
			text(line, {
				name = "Price",
				anchorPoint = Vector2.new(1, 0),
				position = UDim2.fromScale(1, 0),
				size = UDim2.new(0, 84, 1, 0),
				font = SKIN.receipt,
				textSize = 13,
				color = SKIN.paperInk,
				xAlign = Enum.TextXAlignment.Right,
			})
			lineLabels[index] = line
		end
		return line
	end

	dashes("RuleBottom", UDim.new(1, -lowerRuleTop))
	-- Only shown when something crusted is ticked: what the blind sale gives up.
	local blindNote = text(inner, {
		name = "BlindNote",
		position = UDim2.new(0, 0, 1, -noteTop),
		size = UDim2.new(1, 0, 0, 14),
		font = SKIN.receipt,
		textSize = 11,
		color = SKIN.crustChip,
	})
	text(inner, {
		name = "TotalLabel",
		position = UDim2.new(0, 0, 1, -totalTop),
		size = UDim2.new(0.4, 0, 0, 26),
		font = SKIN.headline,
		textSize = 20,
		color = SKIN.paperInk,
		text = "TOTAL",
	})
	local total = text(inner, {
		name = "Total",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 1, -totalTop),
		size = UDim2.new(0.6, 0, 0, 26),
		font = SKIN.headline,
		textSize = 22,
		color = SKIN.paperInk,
		xAlign = Enum.TextXAlignment.Right,
	})

	local sell = button(inner, "Sell", SKIN.sell, 24)
	sell.Position = UDim2.new(0, 0, 1, -sellTop)
	sell.Size = UDim2.new(1, 0, 0, SELL_H)
	edge(sell, SKIN.ink, 3)

	local function bulkButton(name: string, index: number): TextButton
		local b = button(inner, name, SKIN.button, 14)
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.new(0, 0, 1, -(2 - index) * (BULK_H + BULK_GAP))
		b.Size = UDim2.new(1, 0, 0, BULK_H)
		return b
	end
	local bulkAll = bulkButton("SellAll", 0)
	local bulkClean = bulkButton("SellAllClean", 1)
	local bulkUnclean = bulkButton("SellAllUnclean", 2)

	-- ── Behaviour ───────────────────────────────────────────────────────
	-- The ticked uids. Pruned on every paint, so a sold or stored item drops off the
	-- receipt by itself.
	local ticked: { [string]: boolean } = {}
	local sellCallback: ((uids: { string }) -> ())? = nil
	local lastState: any = nil
	local paint: (state: any) -> ()

	local function repaint()
		if lastState then
			paint(lastState)
		end
	end

	local function rowAt(index: number): TextButton
		local row = rows[index]
		if row == nil then
			row = makeRow(list, index)
			rows[index] = row
			row.MouseButton1Click:Connect(function()
				local uid = row:GetAttribute("Uid")
				if type(uid) == "string" and not row:GetAttribute("Hearted") then
					ticked[uid] = if ticked[uid] then nil else true
					repaint()
				end
			end)
		end
		return row
	end

	local function paintRow(row: TextButton, item: any)
		local isTicked = ticked[item.uid] == true
		local isHearted = item.hearted == true
		row.Visible = true
		row:SetAttribute("Uid", item.uid)
		row:SetAttribute("Hearted", isHearted)
		row.BackgroundTransparency = if isHearted then 0.45 else 0
		;(row:FindFirstChild("Hearted") :: TextLabel).Visible = isHearted
		local color = rarityColor(item.rarity)
		local stroke = row:FindFirstChild("Edge") :: UIStroke
		stroke.Enabled = isTicked
		local nameLabel = row:FindFirstChild("ItemName") :: TextLabel
		nameLabel.Text = item.name
		nameLabel.TextColor3 = if item.clean then color else SKIN.crustText
		local sub = row:FindFirstChild("Sub") :: TextLabel
		local kg = if type(item.weight) == "number" then `<font color="#{SKIN.text:ToHex()}">{UIKit.formatKg(item.weight)}</font>` else ""
		StarLine.set(sub, ratingOf(item), {
			color = SKIN.amber,
			before = `<font color="#{color:ToHex()}">{item.rarity or ""}</font>`,
			trail = if type(item.merge) == "number" then item.merge else 0,
			trailColor = Merge.COLOR,
			after = kg,
		})
		;(row:FindFirstChild("Crusted") :: TextLabel).Visible = not item.clean
		local price = row:FindFirstChild("Price") :: TextLabel
		price.Text = money(item.value or 0)
		-- The HEARTED chip is wider than the tick box it replaces; the price makes room.
		price.Position = UDim2.new(1, -(TICK + 24) - (if isHearted then HEARTED_W - TICK else 0), 0.5, 0)
		local tick = row:FindFirstChild("Tick") :: Frame
		tick.Visible = not isHearted
		;(tick:FindFirstChild("Check") :: Frame).Visible = isTicked
		tick.BackgroundTransparency = if isTicked then 0 else 1
		;(tick:FindFirstChild("Edge") :: UIStroke).Color = if isTicked then SKIN.sell else SKIN.muted
		local viewport = (row:FindFirstChild("Art") :: Frame):FindFirstChild("Model") :: ViewportFrame
		ItemArt.paint(viewport, item, ART_W / ROW_H)
	end

	local function paintBulk(b: TextButton, label: string, count: number)
		local live = count > 0
		b.Active = live
		b.Text = if live then `{label} ({count})` else label
		b.TextColor3 = if live then SKIN.text else SKIN.muted
		b.BackgroundTransparency = if live then 0 else 0.4
	end

	paint = function(state: any)
		lastState = state
		local items = sortedItems(state.items or {})

		local present: { [string]: boolean } = {}
		for _, item in items do
			-- Hearted after it was ticked: off the receipt.
			if item.hearted ~= true then
				present[item.uid] = true
			end
		end
		for uid in ticked do
			if not present[uid] then
				ticked[uid] = nil
			end
		end

		for index, item in items do
			paintRow(rowAt(index), item)
		end
		for index = #items + 1, #rows do
			rows[index].Visible = false
			rows[index]:SetAttribute("Uid", nil)
			ItemArt.clear((rows[index]:FindFirstChild("Art") :: Frame):FindFirstChild("Model") :: ViewportFrame)
		end
		emptyBag.Visible = #items == 0

		-- The receipt, in the rows' order.
		local count, sum, blind, cleanCount, sellable = 0, 0, 0, 0, 0
		for _, item in items do
			if item.hearted == true then
				continue
			end
			sellable += 1
			if item.clean then
				cleanCount += 1
			end
			if ticked[item.uid] then
				count += 1
				sum += item.value or 0
				if not item.clean then
					blind += 1
				end
				local line = lineAt(count)
				line.Visible = true
				;(line:FindFirstChild("ItemName") :: TextLabel).Text = if item.clean then item.name else "??? (blind)"
				;(line:FindFirstChild("Price") :: TextLabel).Text = money(item.value or 0)
			end
		end
		for index = count + 1, #lineLabels do
			lineLabels[index].Visible = false
		end
		nothing.Visible = count == 0
		total.Text = money(sum)
		blindNote.Visible = blind > 0
		blindNote.Text = `{blind} crusted, sold blind at {math.floor(Tuning.DIRTY_SELL_MULTIPLIER * 100 + 0.5)}%`

		sell.Active = count > 0
		sell.Text = if count > 0 then `SELL {count}` else "SELL"
		sell.BackgroundColor3 = if count > 0 then SKIN.sell else SKIN.muted

		paintBulk(bulkAll, "Sell all", sellable)
		paintBulk(bulkClean, "Sell all clean", cleanCount)
		paintBulk(bulkUnclean, "Sell all unclean", sellable - cleanCount)

		wallet.Text = money(state.cash or 0)
		local capacity = if type(state.capacity) == "number" then state.capacity else #items
		subtitle.Text = `Trading post  ·  {#items}/{capacity} in bag`
	end

	-- The three bulk buttons only put a group on the receipt; SELL is the confirm.
	local function tickWhere(wants: (item: any) -> boolean)
		if lastState == nil then
			return
		end
		table.clear(ticked)
		for _, item in lastState.items or {} do
			if item.hearted ~= true and wants(item) then
				ticked[item.uid] = true
			end
		end
		repaint()
	end
	bulkAll.MouseButton1Click:Connect(function()
		tickWhere(function()
			return true
		end)
	end)
	bulkClean.MouseButton1Click:Connect(function()
		tickWhere(function(item)
			return item.clean == true
		end)
	end)
	bulkUnclean.MouseButton1Click:Connect(function()
		tickWhere(function(item)
			return not item.clean
		end)
	end)

	sortPill.MouseButton1Click:Connect(function()
		local at = table.find(SORT_OPTIONS, Prefs.get("traderSort")) or 0
		Prefs.set("traderSort", SORT_OPTIONS[at % #SORT_OPTIONS + 1])
	end)
	-- Fires now (painting the pill's text) and on every change, including the saved
	-- value landing after the panel was built.
	Prefs.observe("traderSort", function(mode)
		sortPill.Text = SORT_TEXT[mode] or SORT_TEXT.high
		repaint()
	end)

	sell.MouseButton1Click:Connect(function()
		if sellCallback == nil or lastState == nil then
			return
		end
		local uids = {}
		for _, item in lastState.items or {} do
			if ticked[item.uid] then
				table.insert(uids, item.uid)
			end
		end
		if #uids > 0 then
			sellCallback(uids)
		end
	end)

	return {
		frame = root,
		paint = function(state: any)
			paint(state)
		end,
		onSellMany = function(callback: (uids: { string }) -> ())
			sellCallback = callback
		end,
	}
end

return TraderPanel
