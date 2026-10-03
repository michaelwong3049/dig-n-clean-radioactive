--!strict
--[[
	ReforgePanel.luau — the Reforge Station, drawn inside StationController's panel.

	It wears the Merge Reactor's field-kit slate and hazard tape (client/MergePanel), so
	the Twilight station panels read as one set, with forge orange (Reforge.COLOR) where
	the reactor has pink.

	TOP TO BOTTOM:
	  the pick     the copy you picked: its art, name, rating stars and qualities, and how
	               many times it has been reforged.
	  the forge    its DAMAGE and RADIUS: the number, the roll as a signed percent, and a
	               meter across the whole forge band (Config/Reforge ROLL_MIN..ROLL_MAX).
	               After a reforge the new roll stands beside the old, green where it is
	               better and red where it is worse, and REFORGE splits into KEEP NEW and
	               REVERT.
	  the copies   every washed nuke you own, bag and Quarantine Locker together.

	The numbers are Shared/Bombing.statsFor over the described copy, with the new `forge`
	pair swapped in for the preview, so the panel reads the same maths the bomb does.
	Everything else is presentation: the client asks to reforge one uid and to keep or
	revert; ReforgeService re-derives the station, the copy, the price and the roll.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Payload = require(Shared.Config.Payload)
local Reforge = require(Shared.Config.Reforge)
local Bombing = require(Shared.Bombing)

local UIKit = require(script.Parent.UIKit)
local StarLine = require(script.Parent.StarLine)
local ItemArt = require(script.Parent.ItemArt)

local ReforgePanel = {}

local SKIN = {
	card = Color3.fromHex("22272C"),
	well = Color3.fromHex("1A1E22"),
	edge = Color3.fromHex("343B42"),
	rule = Color3.fromHex("30373D"),
	amber = Color3.fromHex("F2A93B"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA0A6"),
	muted = Color3.fromHex("6C737A"),
	go = Color3.fromHex("3FBF5A"),
	bad = Color3.fromHex("E5484D"),
	off = Color3.fromHex("2A3036"),
	gold = Color3.fromHex("FFD24A"),
	forge = Reforge.COLOR,
	bag = Color3.fromHex("4FD1C5"),
	locker = Color3.fromHex("A855FF"),
	hazard = Color3.fromHex("E8C33C"),
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.GothamBlack,
	label = Enum.Font.GothamBlack,
}

--- The widest the panel is allowed to get, padding included. Same as the reactor's.
ReforgePanel.WIDTH = 860

local HEADER_H = 58
local WALLET_INSET = 44
local TOP_H = 200
local PICK_W = 220
local GRID_H = 230
local TILE_W = 92
local TILE_H = 108
local ROW_H = 54

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

local function ratingOf(item: any): number
	local payload = if type(item.uid) == "string" then Payload.forUid(item.uid) else nil
	return Rarity.stars(item.rarity, item.modifier, payload, item.bonus, Items.stageOf(item.itemId))
end

local function rarityColor(name: string?): Color3
	local def = if name then Rarity.DEFS[name] else nil
	return if def then def.color else SKIN.dim
end

local function qualityText(item: any): string
	local qualities = Rarity.qualities(item.modifier, item.bonus)
	return if #qualities > 0 then table.concat(qualities, " ") else "No qualities"
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

local function bigButton(parent: Instance, name: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = SKIN.headline
	button.TextSize = 20
	button.TextColor3 = SKIN.text
	button.Parent = parent
	corner(button, 12)
	ink(button)
	edge(button, SKIN.ink, 3)
	return button
end

-- ── Build ───────────────────────────────────────────────────────────────

export type Panel = {
	frame: Frame,
	paint: (state: any) -> (),
	onReforge: (callback: (uid: string) -> ()) -> (),
	onSettle: (callback: (uid: string, keep: boolean) -> ()) -> (),
	showResult: (result: any) -> (),
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

type StatRow = {
	now: TextLabel,
	arrow: TextLabel,
	nextValue: TextLabel,
	nowMark: Frame,
	nextMark: Frame,
}

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

--- One stat line in the forge card: "DAMAGE  84 (+6%)  ->  97 (+18%)" over a meter.
local function makeRow(parent: Instance, name: string, y: number): StatRow
	local row = frame(parent, name)
	row.Position = UDim2.fromOffset(12, y)
	row.Size = UDim2.new(1, -24, 0, ROW_H)
	text(row, {
		name = "Label",
		size = UDim2.fromOffset(96, 28),
		textSize = 15,
		color = SKIN.dim,
		text = string.upper(name),
		ink = false,
	})
	local now = text(row, {
		name = "Now",
		position = UDim2.fromOffset(96, 0),
		size = UDim2.fromOffset(170, 28),
		font = SKIN.headline,
		textSize = 22,
		rich = true,
	})
	local arrow = text(row, {
		name = "Arrow",
		position = UDim2.fromOffset(266, 0),
		size = UDim2.fromOffset(30, 28),
		font = SKIN.headline,
		textSize = 22,
		color = SKIN.forge,
		xAlign = Enum.TextXAlignment.Center,
		text = "\u{2192}",
	})
	local nextValue = text(row, {
		name = "Next",
		position = UDim2.fromOffset(302, 0),
		size = UDim2.new(1, -302, 0, 28),
		font = SKIN.headline,
		textSize = 22,
		rich = true,
	})

	-- The meter: the whole forge band, the copy's roll as a white tick, the new one orange.
	local meter = frame(row, "Meter", SKIN.well)
	meter.Position = UDim2.fromOffset(96, 34)
	meter.Size = UDim2.new(1, -96, 0, 10)
	corner(meter, 5)
	edge(meter, SKIN.edge, 1)
	local natural = frame(meter, "Natural", SKIN.off)
	-- The natural wobble's slice of the band (Config/Bombing.VARIANCE = 0.12 around 1).
	natural.Position = UDim2.fromScale(Reforge.grade(0.88), 0)
	natural.Size = UDim2.fromScale(Reforge.grade(1.12) - Reforge.grade(0.88), 1)
	local nowMark = frame(meter, "NowMark", SKIN.text)
	nowMark.AnchorPoint = Vector2.new(0.5, 0.5)
	nowMark.Size = UDim2.fromOffset(4, 16)
	nowMark.Position = UDim2.fromScale(0.5, 0.5)
	local nextMark = frame(meter, "NextMark", SKIN.forge)
	nextMark.AnchorPoint = Vector2.new(0.5, 0.5)
	nextMark.Size = UDim2.fromOffset(6, 18)
	nextMark.Position = UDim2.fromScale(0.5, 0.5)
	corner(nextMark, 2)
	return { now = now, arrow = arrow, nextValue = nextValue, nowMark = nowMark, nextMark = nextMark }
end

local function deltaColor(new: number, old: number): Color3
	if math.abs(new - old) < 0.0005 then
		return SKIN.dim
	end
	return if new > old then SKIN.go else SKIN.bad
end

function ReforgePanel.new(parent: Instance, layoutOrder: number): Panel
	local root = frame(parent, "Reforge")
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
		text = "REFORGE STATION",
	})
	text(header, {
		name = "Subtitle",
		position = UDim2.fromOffset(18, 36),
		size = UDim2.fromOffset(600, 16),
		textSize = 14,
		color = SKIN.dim,
		text = `Reroll a nuke's bomb damage and radius ({Reforge.percentText(Reforge.ROLL_MIN)} to {Reforge.percentText(Reforge.ROLL_MAX)}). {math.floor(Reforge.QUALITY_CHANCE * 100 + 0.5)}% chance of a new quality.`,
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

	-- ── The pick ───────────────────────────────────────────────────────
	local topY = HEADER_H + 14
	local pick = frame(root, "Pick", SKIN.well)
	pick.Position = UDim2.fromOffset(0, topY)
	pick.Size = UDim2.fromOffset(PICK_W, TOP_H)
	corner(pick, 14)
	local pickStroke = edge(pick, SKIN.edge, 3)
	local pickArt = frame(pick, "Art")
	pickArt.Position = UDim2.fromOffset(10, 8)
	pickArt.Size = UDim2.new(1, -20, 0, 104)
	local pickViewport = ItemArt.newViewport(pickArt)
	local pickName = text(pick, {
		name = "ItemName",
		position = UDim2.fromOffset(8, 114),
		size = UDim2.new(1, -16, 0, 22),
		font = SKIN.headline,
		textSize = 18,
		xAlign = Enum.TextXAlignment.Center,
	})
	pickName.TextTruncate = Enum.TextTruncate.AtEnd
	local pickStars = text(pick, {
		name = "Stars",
		position = UDim2.fromOffset(8, 137),
		size = UDim2.new(1, -16, 0, 18),
		textSize = 15,
		xAlign = Enum.TextXAlignment.Center,
		rich = true,
	})
	local pickDetail = text(pick, {
		name = "Detail",
		position = UDim2.fromOffset(8, 157),
		size = UDim2.new(1, -16, 0, 34),
		textSize = 12,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		ink = false,
	})
	local pickEmpty = text(pick, {
		name = "Empty",
		position = UDim2.fromOffset(12, 0),
		size = UDim2.new(1, -24, 1, 0),
		textSize = 14,
		color = SKIN.muted,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = "PICK A NUKE BELOW",
		ink = false,
	})

	-- ── The forge card ─────────────────────────────────────────────────
	local card = frame(root, "Forge", SKIN.card)
	card.AnchorPoint = Vector2.new(1, 0)
	card.Position = UDim2.new(1, 0, 0, topY)
	card.Size = UDim2.new(1, -(PICK_W + 12), 0, TOP_H)
	corner(card, 12)
	edge(card, SKIN.edge, 2)
	local caption = text(card, {
		name = "Caption",
		position = UDim2.fromOffset(12, 8),
		size = UDim2.new(1, -24, 0, 14),
		textSize = 12,
		color = SKIN.dim,
		text = "BOMB STATS",
		ink = false,
	})
	local damageRow = makeRow(card, "Damage", 28)
	local radiusRow = makeRow(card, "Radius", 28 + ROW_H + 2)

	local buttonY = TOP_H - 10 - 44
	local reforgeButton = bigButton(card, "ReforgeButton")
	reforgeButton.Position = UDim2.fromOffset(12, buttonY)
	reforgeButton.Size = UDim2.new(1, -24, 0, 44)
	local keepButton = bigButton(card, "KeepButton")
	keepButton.Position = UDim2.fromOffset(12, buttonY)
	keepButton.Size = UDim2.new(0.5, -18, 0, 44)
	keepButton.BackgroundColor3 = SKIN.go
	keepButton.Text = "KEEP NEW"
	local revertButton = bigButton(card, "RevertButton")
	revertButton.AnchorPoint = Vector2.new(1, 0)
	revertButton.Position = UDim2.new(1, -12, 0, buttonY)
	revertButton.Size = UDim2.new(0.5, -18, 0, 44)
	revertButton.BackgroundColor3 = SKIN.off
	revertButton.Text = "REVERT"

	local cardHint = text(card, {
		name = "Hint",
		position = UDim2.fromOffset(20, 30),
		size = UDim2.new(1, -40, 0, 100),
		textSize = 15,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = "Pick a washed nuke below. Each reforge rolls new damage and radius \u{2014} keep them or revert, the cash is spent either way. Every reforge of the same nuke costs more.",
		ink = false,
	})

	-- The jackpot banner, laid over the pick card (the stats stay readable) when a
	-- reforge adds a quality.
	local banner = frame(root, "QualityBanner", SKIN.well)
	banner.Position = UDim2.fromOffset(0, topY)
	banner.Size = UDim2.fromOffset(PICK_W, TOP_H)
	banner.ZIndex = 20
	banner.Visible = false
	corner(banner, 12)
	edge(banner, SKIN.gold, 3)
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner
	local bannerText = text(banner, {
		name = "Text",
		position = UDim2.fromOffset(10, 0),
		size = UDim2.new(1, -20, 1, 0),
		font = SKIN.headline,
		textSize = 28,
		color = SKIN.gold,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
	})
	bannerText.ZIndex = 21

	-- ── The copies ─────────────────────────────────────────────────────
	local gridY = topY + TOP_H + 12
	local copies = frame(root, "Copies", SKIN.well)
	copies.Position = UDim2.fromOffset(0, gridY)
	copies.Size = UDim2.new(1, 0, 0, GRID_H)
	corner(copies, 12)
	edge(copies, SKIN.edge, 2)
	text(copies, {
		name = "Title",
		position = UDim2.fromOffset(12, 7),
		size = UDim2.new(1, -24, 0, 16),
		textSize = 13,
		color = SKIN.dim,
		text = "YOUR WASHED NUKES (bag + locker) \u{00B7} pick one to reforge",
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
	local selected: string? = nil
	-- The roll waiting on KEEP / REVERT: { uid, old = { dmg, rad }, new = { dmg, rad } }.
	local result: any = nil
	local reforgeCallback: ((uid: string) -> ())? = nil
	local settleCallback: ((uid: string, keep: boolean) -> ())? = nil
	local lastState: any = nil
	local canReforge = false
	local bannerToken = 0
	local paint: (state: any) -> ()

	local function repaint()
		if lastState then
			paint(lastState)
		end
	end

	--- Answer the waiting roll (REVERT when `keep` is false) and clear it.
	local function settle(keep: boolean)
		if result == nil then
			return
		end
		local uid = result.uid
		result = nil
		if settleCallback then
			settleCallback(uid, keep)
		end
	end

	local function tileAt(index: number): Tile
		local tile = tiles[index]
		if tile == nil then
			tile = makeTile(grid, index)
			tiles[index] = tile
			local tileButton = tile.button
			tileButton.MouseButton1Click:Connect(function()
				local uid = tileButton:GetAttribute("Uid")
				if type(uid) ~= "string" or uid == selected then
					return
				end
				-- Picking another copy with a roll still waiting reverts it.
				settle(false)
				selected = uid
				repaint()
			end)
		end
		return tile
	end

	local function paintRow(row: StatRow, nowValue: string, nowMult: number, nextValue: string?, nextMult: number?)
		row.now.Text = `{nowValue} <font size="14" color="#{SKIN.dim:ToHex()}">{Reforge.percentText(nowMult)}</font>`
		row.nowMark.Position = UDim2.fromScale(Reforge.grade(nowMult), 0.5)
		local showing = nextValue ~= nil and nextMult ~= nil
		row.arrow.Visible = showing
		row.nextValue.Visible = showing
		row.nextMark.Visible = showing
		if showing then
			local color = deltaColor(nextMult :: number, nowMult)
			row.nextValue.TextColor3 = color
			row.nextValue.Text = `{nextValue} <font size="14">{Reforge.percentText(nextMult :: number)}</font>`
			row.nextMark.Position = UDim2.fromScale(Reforge.grade(nextMult :: number), 0.5)
		end
	end

	paint = function(state: any)
		lastState = state
		local cashNow = if type(state.cash) == "number" then state.cash else 0
		cash.Text = money(cashNow)

		-- Every washed, unslagged nuke you own, with where it lives.
		local owned: { any } = {}
		local byUid: { [string]: any } = {}
		local function add(list: any, where: string)
			for _, item in list or {} do
				if item.clean and item.identified and item.itemId and item.modifier ~= "Slagged" then
					local entry = table.clone(item)
					entry.where = where
					table.insert(owned, entry)
					byUid[entry.uid] = entry
				end
			end
		end
		add(state.items, "BAG")
		add(state.locker, "LOCKER")
		table.sort(owned, function(a, b)
			local ra, rb = ratingOf(a), ratingOf(b)
			if ra ~= rb then
				return ra > rb
			end
			if a.name ~= b.name then
				return a.name < b.name
			end
			return (a.value or 0) > (b.value or 0)
		end)

		-- The pick follows its copy; one that left (sold, merged) just drops.
		if selected and byUid[selected] == nil then
			selected = nil
			result = nil
		end

		for index, item in owned do
			local tile = tileAt(index)
			local isSelected = item.uid == selected
			tile.button.Visible = true
			tile.button:SetAttribute("Uid", item.uid)
			tile.stroke.Color = if isSelected then SKIN.forge else SKIN.edge
			tile.stroke.Thickness = if isSelected then 3 else 2
			tile.strip.BackgroundColor3 = rarityColor(item.rarity)
			StarLine.set(tile.stars, ratingOf(item), { color = SKIN.gold })
			local stats = Bombing.statsFor(item)
			tile.detail.Text = `{stats.damage} dmg \u{00B7} {stats.radius} rad`
			tile.where.Text = item.where
			tile.where.BackgroundColor3 = if item.where == "BAG" then SKIN.bag else SKIN.locker
			ItemArt.paint(tile.viewport, item, (TILE_W - 12) / 50)
		end
		for index = #owned + 1, #tiles do
			tiles[index].button.Visible = false
			ItemArt.clear(tiles[index].viewport)
		end
		gridEmpty.Visible = #owned == 0

		local item = if selected then byUid[selected] else nil
		pickEmpty.Visible = item == nil
		for _, node in { pickName, pickStars, pickDetail } :: { GuiObject } do
			node.Visible = item ~= nil
		end
		cardHint.Visible = item == nil
		for _, node in { caption } :: { GuiObject } do
			node.Visible = item ~= nil
		end
		for _, row in { damageRow, radiusRow } do
			(row.now.Parent :: GuiObject).Visible = item ~= nil
		end
		canReforge = false
		-- Each button's Visible is written ONCE per paint, never false-then-true: this
		-- repaints at the StationState tick (~10 Hz), and hiding a button for even a
		-- moment drops a press in progress, so a click on KEEP/REVERT never landed.
		local waiting = item ~= nil and result ~= nil and result.uid == item.uid
		keepButton.Visible = waiting
		revertButton.Visible = waiting
		reforgeButton.Visible = not waiting

		if item == nil then
			pickStroke.Color = SKIN.edge
			ItemArt.clear(pickViewport)
			reforgeButton.Text = "REFORGE"
			reforgeButton.BackgroundColor3 = SKIN.off
			reforgeButton.TextColor3 = SKIN.muted
			return
		end

		pickStroke.Color = rarityColor(item.rarity)
		pickName.Text = item.name
		pickName.TextColor3 = rarityColor(item.rarity)
		StarLine.set(pickStars, ratingOf(item), { color = SKIN.gold })
		local count = if type(item.reforges) == "number" then item.reforges else 0
		pickDetail.Text = if count > 0
			then `{qualityText(item)}\nReforged {count} time{if count == 1 then "" else "s"}`
			else qualityText(item)
		ItemArt.paint(pickViewport, item, (PICK_W - 20) / 104)

		local nowDmg, nowRad = Bombing.forgeOf(item)
		local nowStats = Bombing.statsFor(item)
		if waiting then
			local preview = table.clone(item)
			preview.forge = { dmg = result.new.dmg, rad = result.new.rad }
			local nextStats = Bombing.statsFor(preview)
			paintRow(damageRow, tostring(nowStats.damage), nowDmg, tostring(nextStats.damage), result.new.dmg)
			paintRow(radiusRow, tostring(nowStats.radius), nowRad, tostring(nextStats.radius), result.new.rad)
			caption.Text = "BOMB STATS \u{00B7} NEW ROLL"
			return
		end

		paintRow(damageRow, tostring(nowStats.damage), nowDmg)
		paintRow(radiusRow, tostring(nowStats.radius), nowRad)
		caption.Text = "BOMB STATS"
		local price = Reforge.cost(if type(item.value) == "number" then item.value else 0, count)
		canReforge = cashNow >= price
		reforgeButton.Text = if canReforge then `REFORGE \u{00B7} {money(price)}` else `NEED {money(price)}`
		reforgeButton.BackgroundColor3 = if canReforge then SKIN.forge else SKIN.off
		reforgeButton.TextColor3 = if canReforge then SKIN.text else SKIN.muted
	end

	reforgeButton.MouseButton1Click:Connect(function()
		if not canReforge or selected == nil or reforgeCallback == nil then
			return
		end
		canReforge = false
		reforgeCallback(selected)
	end)
	keepButton.MouseButton1Click:Connect(function()
		settle(true)
		repaint()
	end)
	revertButton.MouseButton1Click:Connect(function()
		settle(false)
		repaint()
	end)

	local function showResult(payload: any)
		if type(payload) ~= "table" or type(payload.new) ~= "table" then
			return
		end
		selected = payload.uid
		result = { uid = payload.uid, old = payload.old, new = payload.new }
		if type(payload.quality) == "string" then
			bannerText.Text = `NEW QUALITY!\n{string.upper(payload.quality)}`
			banner.Visible = true
			bannerScale.Scale = 0.6
			TweenService:Create(bannerScale, POP, { Scale = 1 }):Play()
			bannerToken += 1
			local token = bannerToken
			task.delay(3, function()
				if token == bannerToken then
					banner.Visible = false
				end
			end)
		end
		repaint()
	end

	return {
		frame = root,
		paint = function(state: any)
			paint(state)
		end,
		onReforge = function(callback: (uid: string) -> ())
			reforgeCallback = callback
		end,
		onSettle = function(callback: (uid: string, keep: boolean) -> ())
			settleCallback = callback
		end,
		showResult = showResult,
	}
end

return ReforgePanel
