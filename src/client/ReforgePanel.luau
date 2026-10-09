--!strict
--[[
	ReforgePanel.luau — the Reforge Station, drawn inside StationController's panel.

	It wears the Merge Reactor's field-kit slate and hazard tape (client/MergePanel), so
	the Twilight station panels read as one set, with forge orange (Reforge.COLOR) where
	the reactor has pink.

	TOP TO BOTTOM:
	  the pick     the copy you picked: its art, name, rating stars, how many times it
	               has been reforged, and its EFFECTS (its qualities, or "None").
	  the forge    its DAMAGE and RADIUS, each over a roll meter: the whole forge band
	               (Config/Reforge ROLL_MIN..ROLL_MAX) split into BAD / OK / GOOD / GREAT /
	               PERFECT zones, the copy's roll a white tick. After a reforge an orange
	               diamond slides to the new roll, the new number stands beside the old
	               (green better, red worse) with its grade, and REFORGE splits into
	               KEEP NEW and REVERT.
	  the odds     EFFECT CHANCE: the chance one reforge adds a quality, over a bar split
	               into the qualities the copy can still get (Reforge.qualityOdds), each
	               segment in its WashReveal colour with its own percent.
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
local Mastery = require(Shared.Mastery) -- Mastery.short: "$360M"

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
	go = UIKit.House.buy,
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
local TOP_H = 322
local PICK_W = 220
local GRID_H = 230
local TILE_W = 92
local TILE_H = 108
local ROW_H = 80
local EFFECT_H = 64

-- The roll meter's zones, as cuts across Reforge.grade (0 = ROLL_MIN, 1 = ROLL_MAX): the
-- band's colour in each and the grade tag a roll landing there wears.
local GRADES = {
	{ upto = 0.2, name = "BAD", band = Color3.fromHex("5A2A2C"), tag = Color3.fromHex("FF6B6F") },
	{ upto = 0.45, name = "OK", band = Color3.fromHex("3A4148"), tag = Color3.fromHex("C9CED3") },
	{ upto = 0.7, name = "GOOD", band = Color3.fromHex("2D5A3A"), tag = Color3.fromHex("5FE07A") },
	{ upto = 0.9, name = "GREAT", band = Color3.fromHex("245A57"), tag = Color3.fromHex("4FD1C5") },
	{ upto = 1, name = "PERFECT", band = Color3.fromHex("6B5A1C"), tag = Color3.fromHex("FFD24A") },
}

-- WashReveal's stamp colours, so a quality reads the same here as when it was washed.
local QUALITY_COLOR: { [string]: Color3 } = {
	Pristine = Color3.fromHex("7DF9FF"),
	Irradiated = Color3.fromHex("A3FF3C"),
	Fused = Color3.fromHex("FF8A3D"),
	Cracked = Color3.fromHex("A7ADB4"),
}

local SLIDE = TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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

local function ratingOf(item: any): number
	local payload = if type(item.uid) == "string" then Payload.forUid(item.uid) else nil
	return Rarity.stars(item.rarity, item.modifier, payload, item.bonus, Items.stageOf(item.itemId))
end

local function rarityColor(name: string?): Color3
	local def = if name then Rarity.DEFS[name] else nil
	return if def then def.color else SKIN.dim
end

--- The pick card's EFFECTS list: one quality a line in its colour with its value
--- multiplier, or "None".
local function effectsText(item: any): string
	local qualities = Rarity.qualities(item.modifier, item.bonus)
	if #qualities == 0 then
		return `<font color="#{SKIN.muted:ToHex()}">None</font>`
	end
	local lines = {}
	for _, name in qualities do
		local color = QUALITY_COLOR[name] or SKIN.text
		local def = Rarity.MODIFIERS[name]
		local mult = if def then ` <font size="11" color="#{SKIN.dim:ToHex()}">x{def.valueMult} value</font>` else ""
		table.insert(lines, `<font color="#{color:ToHex()}">{name}</font>{mult}`)
	end
	return table.concat(lines, "\n")
end

local function gradeOf(mult: number)
	local g = Reforge.grade(mult)
	for _, grade in GRADES do
		if g <= grade.upto then
			return grade
		end
	end
	return GRADES[#GRADES]
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

--- Station panels read a size up (on request): small print +3, mid sizes +2, headlines
--- as they were. Every label, chip and button below goes through it.
local function bigger(size: number?): number?
	if size == nil then
		return nil
	elseif size <= 15 then
		return size + 3
	elseif size <= 22 then
		return size + 2
	end
	return size
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = UIKit.label(parent, {
		name = props.name,
		position = props.position,
		size = props.size,
		anchorPoint = props.anchorPoint,
		font = props.font or SKIN.label,
		textSize = bigger(props.textSize),
		color = props.color or SKIN.text,
		xAlign = props.xAlign or Enum.TextXAlignment.Left,
		yAlign = props.yAlign,
		wrapped = props.wrapped,
		text = props.text,
		outline = false,
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
	label.TextSize = bigger(11) :: number
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
	button.TextSize = bigger(20) :: number
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
	frame: Frame,
	now: TextLabel,
	arrow: TextLabel,
	nextValue: TextLabel,
	grade: TextLabel,
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

--- One stat in the forge card: "DAMAGE        84 +6%  ->  97 +18%  GREAT" over a roll
--- meter the width of the card, its zones coloured BAD..PERFECT (GRADES).
local function makeRow(parent: Instance, name: string, y: number): StatRow
	local row = frame(parent, name)
	row.Position = UDim2.fromOffset(12, y)
	row.Size = UDim2.new(1, -24, 0, ROW_H)
	text(row, {
		name = "Label",
		size = UDim2.fromOffset(130, 30),
		font = SKIN.headline,
		textSize = 20,
		text = string.upper(name),
	})

	-- The numbers, packed against the right edge; the arrow, the new roll and its grade
	-- only show while a roll waits on KEEP / REVERT.
	local values = frame(row, "Values")
	values.AnchorPoint = Vector2.new(1, 0)
	values.Position = UDim2.fromScale(1, 0)
	values.Size = UDim2.new(1, -130, 0, 30)
	local valuesLayout = Instance.new("UIListLayout")
	valuesLayout.FillDirection = Enum.FillDirection.Horizontal
	valuesLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	valuesLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	valuesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	valuesLayout.Padding = UDim.new(0, 6)
	valuesLayout.Parent = values
	local function value(key: string, order: number, size: number, color: Color3?): TextLabel
		local label = text(values, {
			name = key,
			size = UDim2.fromOffset(0, 30),
			font = SKIN.headline,
			textSize = size,
			color = color,
			xAlign = Enum.TextXAlignment.Center,
			rich = true,
		})
		label.AutomaticSize = Enum.AutomaticSize.X
		label.LayoutOrder = order
		return label
	end
	local now = value("Now", 1, 24)
	local arrow = value("Arrow", 2, 22, SKIN.forge)
	arrow.Text = "\u{2192}"
	local nextValue = value("Next", 3, 28)
	local grade = chip(values, "Grade")
	grade.LayoutOrder = 4
	grade.Size = UDim2.fromOffset(0, 20)
	grade.TextSize = bigger(13) :: number

	-- The meter: the whole forge band in its grade zones, a faint line at +0%, the
	-- copy's roll as a white tick and the new one as an orange diamond.
	local meter = frame(row, "Meter", SKIN.well)
	meter.Position = UDim2.fromOffset(0, 36)
	meter.Size = UDim2.new(1, 0, 0, 26)
	corner(meter, 8)
	edge(meter, SKIN.ink, 3)
	local zones = frame(meter, "Zones")
	zones.Size = UDim2.fromScale(1, 1)
	zones.ClipsDescendants = true
	local from = 0
	for index, zone in GRADES do
		local band = frame(zones, `Zone{index}`, zone.band)
		band.Position = UDim2.fromScale(from, 0)
		band.Size = UDim2.fromScale(zone.upto - from, 1)
		if index == 1 or index == #GRADES then
			corner(band, 7)
		end
		from = zone.upto
	end
	local zero = frame(meter, "Zero", SKIN.text)
	zero.AnchorPoint = Vector2.new(0.5, 0.5)
	zero.Position = UDim2.fromScale(Reforge.grade(1), 0.5)
	zero.Size = UDim2.new(0, 2, 1, 8)
	zero.BackgroundTransparency = 0.6
	local nowMark = frame(meter, "NowMark", SKIN.text)
	nowMark.AnchorPoint = Vector2.new(0.5, 0.5)
	nowMark.Size = UDim2.new(0, 6, 1, -4)
	nowMark.Position = UDim2.fromScale(0.5, 0.5)
	corner(nowMark, 3)
	edge(nowMark, SKIN.ink, 1)
	local nextMark = frame(meter, "NextMark", SKIN.forge)
	nextMark.AnchorPoint = Vector2.new(0.5, 0.5)
	nextMark.Size = UDim2.fromOffset(20, 20)
	nextMark.Rotation = 45
	nextMark.Position = UDim2.fromScale(0.5, 0.5)
	nextMark.ZIndex = 3
	corner(nextMark, 3)
	edge(nextMark, SKIN.ink, 3)

	local scale = frame(row, "Scale")
	scale.Position = UDim2.fromOffset(0, 65)
	scale.Size = UDim2.new(1, 0, 0, 13)
	local names = {}
	for _, zone in GRADES do
		table.insert(names, zone.name)
	end
	for _, spec in {
		{ Enum.TextXAlignment.Left, Reforge.percentText(Reforge.ROLL_MIN) },
		{ Enum.TextXAlignment.Center, table.concat(names, " \u{00B7} ") },
		{ Enum.TextXAlignment.Right, Reforge.percentText(Reforge.ROLL_MAX) },
	} do
		text(scale, {
			size = UDim2.fromScale(1, 1),
			textSize = 11,
			color = SKIN.dim,
			xAlign = spec[1],
			text = spec[2],
			ink = false,
		})
	end
	return {
		frame = row,
		now = now,
		arrow = arrow,
		nextValue = nextValue,
		grade = grade,
		nowMark = nowMark,
		nextMark = nextMark,
	}
end

type EffectRow = {
	frame: Frame,
	total: TextLabel,
	bar: Frame,
	segments: { [string]: Frame },
	full: TextLabel,
}

--- A chance as a short percent: 0.03 -> "3%", 0.0086 -> "0.9%".
local function percent(chance: number): string
	local pct = chance * 100
	return if pct >= 10 or math.abs(pct - math.floor(pct + 0.5)) < 0.05
		then `{math.floor(pct + 0.5)}%`
		else string.format("%.1f%%", pct)
end

--- The forge card's EFFECT CHANCE row: the total chance a reforge adds a quality, over
--- a bar split into one segment per quality the copy can still get, sized by its share.
local function makeEffectRow(parent: Instance, y: number): EffectRow
	local row = frame(parent, "EffectChance")
	row.Position = UDim2.fromOffset(12, y)
	row.Size = UDim2.new(1, -24, 0, EFFECT_H)
	text(row, {
		name = "Label",
		size = UDim2.fromOffset(260, 30),
		font = SKIN.headline,
		textSize = 20,
		text = "EFFECT CHANCE",
	})
	local total = text(row, {
		name = "Total",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.fromOffset(240, 30),
		font = SKIN.headline,
		textSize = 22,
		color = SKIN.gold,
		xAlign = Enum.TextXAlignment.Right,
		rich = true,
	})

	local meter = frame(row, "Meter", SKIN.well)
	meter.Position = UDim2.fromOffset(0, 36)
	meter.Size = UDim2.new(1, 0, 0, 26)
	corner(meter, 8)
	edge(meter, SKIN.ink, 3)
	local bar = frame(meter, "Segments")
	bar.Size = UDim2.fromScale(1, 1)
	bar.ClipsDescendants = true
	corner(bar, 7)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar
	local segments: { [string]: Frame } = {}
	for index, name in Reforge.QUALITIES do
		local segment = frame(bar, name, QUALITY_COLOR[name] or SKIN.dim)
		segment.LayoutOrder = index
		local divider = frame(segment, "Divider", SKIN.ink)
		divider.Size = UDim2.new(0, 2, 1, 0)
		local label = text(segment, {
			name = "Text",
			position = UDim2.fromOffset(6, 0),
			size = UDim2.new(1, -12, 1, 0),
			textSize = 12,
			color = SKIN.ink,
			xAlign = Enum.TextXAlignment.Center,
			ink = false,
		})
		label.TextTruncate = Enum.TextTruncate.AtEnd
		segments[name] = segment
	end
	local full = text(meter, {
		name = "Full",
		size = UDim2.fromScale(1, 1),
		textSize = 12,
		color = SKIN.muted,
		xAlign = Enum.TextXAlignment.Center,
		text = "HAS EVERY EFFECT \u{2014} NOTHING LEFT TO ADD",
		ink = false,
	})
	return { frame = row, total = total, bar = bar, segments = segments, full = full }
end

local function paintEffectRow(row: EffectRow, item: any)
	local odds = Reforge.qualityOdds(Rarity.qualities(item.modifier, item.bonus))
	local chances: { [string]: number } = {}
	local sum = 0
	for _, entry in odds do
		chances[entry.name] = entry.chance
		sum += entry.chance
	end
	row.total.Text = if sum > 0
		then `{percent(sum)} <font size="13" color="#{SKIN.dim:ToHex()}">per reforge</font>`
		else `<font color="#{SKIN.muted:ToHex()}">0%</font>`
	row.full.Visible = sum <= 0
	row.bar.Visible = sum > 0
	local first = true
	for _, name in Reforge.QUALITIES do
		local segment = row.segments[name]
		local chance = chances[name] or 0
		segment.Visible = chance > 0
		if chance > 0 then
			segment.Size = UDim2.fromScale(chance / sum, 1)
			local label = segment:FindFirstChild("Text") :: TextLabel
			label.Text = `{string.upper(name)} {percent(chance)}`
			local divider = segment:FindFirstChild("Divider") :: Frame
			divider.Visible = not first
			first = false
		end
	end
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
	pickArt.Size = UDim2.new(1, -20, 0, 96)
	local pickViewport = ItemArt.newViewport(pickArt)
	local pickName = text(pick, {
		name = "ItemName",
		position = UDim2.fromOffset(8, 104),
		size = UDim2.new(1, -16, 0, 22),
		font = SKIN.headline,
		textSize = 18,
		xAlign = Enum.TextXAlignment.Center,
	})
	pickName.TextTruncate = Enum.TextTruncate.AtEnd
	local pickStars = text(pick, {
		name = "Stars",
		position = UDim2.fromOffset(8, 127),
		size = UDim2.new(1, -16, 0, 18),
		textSize = 15,
		xAlign = Enum.TextXAlignment.Center,
		rich = true,
	})
	local pickDetail = text(pick, {
		name = "Detail",
		position = UDim2.fromOffset(8, 146),
		size = UDim2.new(1, -16, 0, 16),
		textSize = 12,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		ink = false,
	})
	-- EFFECTS: the copy's qualities, one a line, or "None".
	local effectsRule = frame(pick, "EffectsRule", SKIN.rule)
	effectsRule.Position = UDim2.fromOffset(14, 168)
	effectsRule.Size = UDim2.new(1, -28, 0, 1)
	local effectsLabel = text(pick, {
		name = "EffectsLabel",
		position = UDim2.fromOffset(14, 174),
		size = UDim2.new(1, -28, 0, 16),
		textSize = 14,
		text = "Effects:",
	})
	local effects = text(pick, {
		name = "Effects",
		position = UDim2.fromOffset(14, 192),
		size = UDim2.new(1, -28, 0, TOP_H - 200),
		textSize = 14,
		yAlign = Enum.TextYAlignment.Top,
		wrapped = true,
		rich = true,
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
	local damageRow = makeRow(card, "Damage", 12)
	local radiusRow = makeRow(card, "Radius", 12 + ROW_H + 8)
	local effectRow = makeEffectRow(card, 12 + 2 * (ROW_H + 8))

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
		text = "Pick a cleaned nuke. Reforge for stronger and rarer nukes.",
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
		text = "YOUR CLEANED NUKES (bag + locker)",
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
		text = "No cleaned nukes",
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
	-- While the diamonds slide to a fresh roll, the ~10 Hz repaint leaves them be.
	local slideUntil = 0
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
		row.grade.Visible = showing
		if showing then
			local color = deltaColor(nextMult :: number, nowMult)
			row.nextValue.TextColor3 = color
			row.nextValue.Text = `{nextValue} <font size="14">{Reforge.percentText(nextMult :: number)}</font>`
			local grade = gradeOf(nextMult :: number)
			row.grade.Text = grade.name
			row.grade.BackgroundColor3 = grade.tag
			if os.clock() >= slideUntil then
				row.nextMark.Position = UDim2.fromScale(Reforge.grade(nextMult :: number), 0.5)
			end
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
		for _, node in { pickName, pickStars, pickDetail, effectsRule, effectsLabel, effects } :: { GuiObject } do
			node.Visible = item ~= nil
		end
		cardHint.Visible = item == nil
		for _, row in { damageRow, radiusRow } do
			row.frame.Visible = item ~= nil
		end
		effectRow.frame.Visible = item ~= nil
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
			then `Reforged {count} time{if count == 1 then "" else "s"}`
			else "Never reforged"
		effects.Text = effectsText(item)
		paintEffectRow(effectRow, item)
		ItemArt.paint(pickViewport, item, (PICK_W - 20) / 96)

		local nowDmg, nowRad = Bombing.forgeOf(item)
		local nowStats = Bombing.statsFor(item)
		if waiting then
			local preview = table.clone(item)
			preview.forge = { dmg = result.new.dmg, rad = result.new.rad }
			local nextStats = Bombing.statsFor(preview)
			paintRow(damageRow, tostring(nowStats.damage), nowDmg, tostring(nextStats.damage), result.new.dmg)
			paintRow(radiusRow, tostring(nowStats.radius), nowRad, tostring(nextStats.radius), result.new.rad)
			return
		end

		paintRow(damageRow, tostring(nowStats.damage), nowDmg)
		paintRow(radiusRow, tostring(nowStats.radius), nowRad)
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
		slideUntil = os.clock() + SLIDE.Time
		repaint()
		-- The diamonds start on the old roll's tick and slide out to the new one.
		for _, pair in { { damageRow, payload.new.dmg }, { radiusRow, payload.new.rad } } do
			local row, mult = pair[1], pair[2]
			if type(mult) == "number" then
				row.nextMark.Position = row.nowMark.Position
				TweenService:Create(row.nextMark, SLIDE, { Position = UDim2.fromScale(Reforge.grade(mult), 0.5) }):Play()
			end
		end
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
