--!strict
--[[
	FurnacePanel.luau — the Slag Furnace, drawn inside StationController's panel.

	It wears the Twilight stations' field-kit slate and hazard tape (client/ReforgePanel,
	client/MergePanel), with molten orange (Furnace.COLOR) for the accent.

	TOP TO BOTTOM:
	  the meter    the furnace's fill, 0..100%, with what you have picked shown on top
	               of it as a paler stretch ("+23%"), and the rolls banked at the right.
	  the reel     the prize reel (client/PrizeReel): every card is its tier's colour
	               under the L-stud pattern. ROLL spins it onto the prize the server
	               has already granted.
	  the buttons  SELECT (every pick below Furnace.CONFIRM_FROM), BURN (the picks, +%),
	               ROLL (one banked roll).
	  the nukes    every washed or Slagged nuke you own, bag and Quarantine Locker
	               together, cheapest fill first, each with the % it would add. Tap to
	               pick, tap again to drop.

	BURNING A LEGENDARY OR BETTER ASKS FIRST: BURN swaps the buttons for a confirm
	line naming how many. Everything else is presentation: FurnaceService re-derives
	the station, the copies, the fill and the prize.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Potions = require(Shared.Config.Potions)
local Furnace = require(Shared.Config.Furnace)
local Mastery = require(Shared.Mastery)

local UIKit = require(script.Parent.UIKit)
local ItemArt = require(script.Parent.ItemArt)
local PrizeReel = require(script.Parent.PrizeReel)
local HudArtwork = require(script.Parent.HudArtwork)
local CloverArt = require(script.Parent.CloverArt)
local Sfx = require(script.Parent.Sfx)

local FurnacePanel = {}

local SKIN = {
	card = Color3.fromHex("22272C"),
	well = Color3.fromHex("1A1E22"),
	edge = Color3.fromHex("343B42"),
	rule = Color3.fromHex("30373D"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA0A6"),
	muted = Color3.fromHex("6C737A"),
	go = UIKit.House.buy,
	bad = Color3.fromHex("E5484D"),
	off = Color3.fromHex("2A3036"),
	gold = Color3.fromHex("FFD24A"),
	molten = Furnace.COLOR,
	hot = Color3.fromHex("FFC24A"),
	deep = Color3.fromHex("D2451A"),
	bag = Color3.fromHex("4FD1C5"),
	locker = Color3.fromHex("A855FF"),
	hazard = Color3.fromHex("E8C33C"),
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.GothamBlack,
	label = Enum.Font.GothamBlack,
}

--- The widest the panel is allowed to get, padding included. Same as the forge's.
FurnacePanel.WIDTH = 860

local HEADER_H = 58
local WALLET_INSET = 44
local METER_H = 40
local REEL_H = 184
--- Seconds after a SKIP press during which the ROLL / SKIP button ignores presses.
local SKIP_GRACE = 0.75
local CARD = Vector2.new(108, 136)
local BUTTONS_H = 46
local GRID_H = 196
local TILE_W = 92
local TILE_H = 104
local GAP = 10

local TICK_SOUND = "rbxasset://sounds/volume_slider.ogg"
local LAND_SOUND = "rbxasset://sounds/electronicpingshort.wav"

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
		strokeTransparency = 1,
	})
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
	button.TextSize = 18
	button.TextColor3 = SKIN.text
	button.Parent = parent
	corner(button, 12)
	ink(button)
	edge(button, SKIN.ink, 3)
	return button
end

local function setButton(button: TextButton, label: string, color: Color3?)
	button.Text = label
	button.BackgroundColor3 = color or SKIN.off
	button.TextColor3 = if color then SKIN.text else SKIN.muted
end

local function sound(parent: Instance, id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	Sfx.adopt(s, "ui")
	s.Parent = parent
	return s
end

--- One server prize card (FurnaceService) as a reel entry.
function FurnacePanel.entryFor(card: any): PrizeReel.Entry
	local entry: PrizeReel.Entry = { name = tostring(card.name or "?"), tier = card.tier }
	local kind = card.kind
	if kind == "potion" and Potions.has(card.potion) then
		entry.image = Potions.get(card.potion).image
	elseif kind == "potionPack" then
		entry.image = Potions.TILE_IMAGE
		entry.caption = "x3"
	elseif kind == "crate" and type(card.crate) == "string" then
		entry.item = { uid = `furnace-{card.crate}`, crateId = card.crate }
	elseif kind == "cash" then
		entry.image = HudArtwork.IMAGE.cashBundle
		entry.caption = if type(card.amount) == "number" then `${Mastery.short(card.amount)}` else nil
	elseif kind == "luckBoost" then
		entry.image = CloverArt.GREEN.image
		entry.caption = "15 MIN"
	elseif kind == "cashBoost" then
		entry.image = HudArtwork.IMAGE.cashBundle
		entry.caption = "2x 15 MIN"
	elseif kind == "nuke" then
		if type(card.item) == "table" then
			entry.item = card.item
		elseif type(card.itemId) == "string" then
			entry.item = { uid = `furnace-{card.itemId}`, itemId = card.itemId, identified = true, rarity = card.tier }
		end
	end
	return entry
end

-- ── Build ───────────────────────────────────────────────────────────────

export type Panel = {
	frame: Frame,
	paint: (state: any) -> (),
	onDump: (callback: (uids: { string }) -> ()) -> (),
	onRoll: (callback: () -> ()) -> (),
	onSkip: (callback: () -> ()) -> (),
	showResult: (result: any) -> (),
}

type Tile = {
	button: TextButton,
	stroke: UIStroke,
	strip: Frame,
	viewport: ViewportFrame,
	fill: TextLabel,
	name: TextLabel,
	where: TextLabel,
	check: TextLabel,
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
	art.Size = UDim2.new(1, -12, 0, 48)
	local viewport = ItemArt.newViewport(art)

	local name = text(button, {
		name = "ItemName",
		position = UDim2.fromOffset(3, 60),
		size = UDim2.new(1, -6, 0, 14),
		textSize = 10,
		xAlign = Enum.TextXAlignment.Center,
		ink = false,
	})
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local fill = text(button, {
		name = "Fill",
		position = UDim2.fromOffset(2, 73),
		size = UDim2.new(1, -4, 0, 14),
		textSize = 13,
		color = SKIN.molten,
		xAlign = Enum.TextXAlignment.Center,
	})
	local where = chip(button, "Where")
	where.AnchorPoint = Vector2.new(0.5, 0)
	where.Position = UDim2.new(0.5, 0, 0, 87)

	local check = text(button, {
		name = "Check",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -4, 0, 10),
		size = UDim2.fromOffset(20, 20),
		textSize = 18,
		color = SKIN.molten,
		xAlign = Enum.TextXAlignment.Right,
		text = "\u{2714}",
	})
	return { button = button, stroke = stroke, strip = strip, viewport = viewport, fill = fill, name = name, where = where, check = check }
end

function FurnacePanel.new(parent: Instance, layoutOrder: number): Panel
	local root = frame(parent, "Furnace")
	root.LayoutOrder = layoutOrder
	root.Size = UDim2.new(1, 0, 0, HEADER_H + GAP + METER_H + GAP + REEL_H + GAP + BUTTONS_H + GAP + GRID_H)
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
		color = SKIN.molten,
		text = "SLAG FURNACE",
	})
	text(header, {
		name = "Subtitle",
		position = UDim2.fromOffset(18, 36),
		size = UDim2.fromOffset(600, 16),
		textSize = 14,
		color = SKIN.dim,
		text = `Burn nukes to fill the meter. Every {Furnace.FULL}% banks a roll: potions, crates, cash, boosts, nukes.`,
		ink = false,
	})
	text(header, {
		name = "RollsLabel",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 6),
		size = UDim2.fromOffset(160, 14),
		textSize = 12,
		xAlign = Enum.TextXAlignment.Right,
		text = "ROLLS BANKED",
	})
	local rollsText = text(header, {
		name = "Rolls",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 21),
		size = UDim2.fromOffset(200, 30),
		font = SKIN.headline,
		textSize = 28,
		color = SKIN.hot,
		xAlign = Enum.TextXAlignment.Right,
	})

	-- ── The meter ──────────────────────────────────────────────────────
	local y = HEADER_H + GAP
	local meter = frame(root, "Meter", Color3.fromHex("1B1714"))
	meter.Position = UDim2.fromOffset(0, y)
	meter.Size = UDim2.new(1, 0, 0, METER_H)
	meter.ClipsDescendants = true
	corner(meter, 10)
	edge(meter, SKIN.ink, 3)
	local preview = frame(meter, "Preview", SKIN.hot)
	preview.BackgroundTransparency = 0.55
	preview.Size = UDim2.fromScale(0, 1)
	corner(preview, 8)
	local bar = frame(meter, "Fill", Color3.new(1, 1, 1))
	bar.Size = UDim2.fromScale(0, 1)
	corner(bar, 8)
	local barGradient = Instance.new("UIGradient")
	barGradient.Rotation = 90
	barGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("FFD36B")),
		ColorSequenceKeypoint.new(0.45, Color3.fromHex("FF8A2E")),
		ColorSequenceKeypoint.new(1, SKIN.deep),
	})
	barGradient.Parent = bar
	local meterText = text(meter, {
		name = "Percent",
		size = UDim2.fromScale(1, 1),
		font = SKIN.headline,
		textSize = 20,
		xAlign = Enum.TextXAlignment.Center,
	})
	meterText.ZIndex = 5

	-- ── The reel ───────────────────────────────────────────────────────
	y += METER_H + GAP
	local well = frame(root, "ReelWell", Color3.fromHex("140D0A"))
	well.Position = UDim2.fromOffset(0, y)
	well.Size = UDim2.new(1, 0, 0, REEL_H)
	corner(well, 12)
	edge(well, SKIN.edge, 2)
	local glow = Instance.new("UIGradient")
	glow.Rotation = 90
	glow.Color = ColorSequence.new(Color3.fromHex("140D0A"), Color3.fromHex("4A1E10"))
	glow.Parent = well
	local reelHolder = frame(well, "ReelHolder")
	reelHolder.Size = UDim2.new(1, 0, 1, -28)
	reelHolder.ClipsDescendants = true
	local reel = PrizeReel.new(reelHolder, {
		size = UDim2.fromScale(1, 1),
		widthHint = FurnacePanel.WIDTH - 32,
		cardSize = CARD,
		gap = 8,
		fade = Color3.fromHex("1C110C"),
		marker = SKIN.hot,
	})
	local resultText = text(well, {
		name = "Result",
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, 0, 1, -6),
		size = UDim2.new(1, 0, 0, 20),
		font = SKIN.headline,
		textSize = 17,
		xAlign = Enum.TextXAlignment.Center,
	})
	local idleText = text(well, {
		name = "Idle",
		position = UDim2.fromOffset(20, 0),
		size = UDim2.new(1, -40, 1, -28),
		textSize = 18,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
	})

	-- ── Buttons ────────────────────────────────────────────────────────
	y += REEL_H + GAP
	local buttons = frame(root, "Buttons")
	buttons.Position = UDim2.fromOffset(0, y)
	buttons.Size = UDim2.new(1, 0, 0, BUTTONS_H)
	local selectButton = bigButton(buttons, "SelectButton")
	selectButton.Size = UDim2.new(0.3, -8, 1, 0)
	local burnButton = bigButton(buttons, "BurnButton")
	burnButton.Position = UDim2.new(0.3, 4, 0, 0)
	burnButton.Size = UDim2.new(0.4, -8, 1, 0)
	local rollButton = bigButton(buttons, "RollButton")
	rollButton.AnchorPoint = Vector2.new(1, 0)
	rollButton.Position = UDim2.fromScale(1, 0)
	rollButton.Size = UDim2.new(0.3, -8, 1, 0)

	-- The confirm line that replaces the buttons before a Legendary+ burns.
	local confirm = frame(root, "Confirm", SKIN.well)
	confirm.Position = UDim2.fromOffset(0, y)
	confirm.Size = UDim2.new(1, 0, 0, BUTTONS_H)
	confirm.Visible = false
	corner(confirm, 12)
	edge(confirm, SKIN.bad, 3)
	local confirmText = text(confirm, {
		name = "Question",
		position = UDim2.fromOffset(14, 0),
		size = UDim2.new(0.55, -14, 1, 0),
		textSize = 15,
		wrapped = true,
	})
	local yesButton = bigButton(confirm, "Yes")
	yesButton.AnchorPoint = Vector2.new(1, 0.5)
	yesButton.Position = UDim2.new(1, -150, 0.5, 0)
	yesButton.Size = UDim2.fromOffset(200, BUTTONS_H - 10)
	setButton(yesButton, "BURN THEM", SKIN.bad)
	local noButton = bigButton(confirm, "No")
	noButton.AnchorPoint = Vector2.new(1, 0.5)
	noButton.Position = UDim2.new(1, -6, 0.5, 0)
	noButton.Size = UDim2.fromOffset(136, BUTTONS_H - 10)
	setButton(noButton, "CANCEL", SKIN.off)
	noButton.TextColor3 = SKIN.text

	-- ── The nukes ──────────────────────────────────────────────────────
	y += BUTTONS_H + GAP
	local copies = frame(root, "Copies", SKIN.well)
	copies.Position = UDim2.fromOffset(0, y)
	copies.Size = UDim2.new(1, 0, 0, GRID_H)
	corner(copies, 12)
	edge(copies, SKIN.edge, 2)
	text(copies, {
		name = "Title",
		position = UDim2.fromOffset(12, 7),
		size = UDim2.new(1, -24, 0, 16),
		textSize = 13,
		color = SKIN.dim,
		text = "YOUR NUKES",
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
		text = "No nukes to burn.",
		ink = false,
	})

	local tickSound = sound(root, TICK_SOUND, 0.25)
	local landSound = sound(root, LAND_SOUND, 0.5)

	-- ── Behaviour ───────────────────────────────────────────────────────
	local tiles: { Tile } = {}
	local picked: { [string]: boolean } = {}
	local byUid: { [string]: any } = {}
	local owned: { any } = {}
	local lastState: any = nil
	local dumpCallback: ((uids: { string }) -> ())? = nil
	local rollCallback: (() -> ())? = nil
	local skipCallback: (() -> ())? = nil
	local spinning = false
	-- The reel itself is running (the server's answer came back), so ROLL is SKIP.
	local reeling = false
	-- When SKIP was last pressed: a quick double press must not fall through to ROLL
	-- once the reel has landed and spend another banked roll.
	local skippedAt = -math.huge
	local hasRolled = false
	-- ROLL pressed, no reel back yet. A refusal (StationResult) never answers here.
	local awaiting = 0
	local asking = false
	local paint: (state: any) -> ()

	local function repaint()
		if lastState then
			paint(lastState)
		end
	end

	local function pickedList(): ({ string }, number, number)
		local uids: { string } = {}
		local sum, risky = 0, 0
		for _, item in owned do
			if picked[item.uid] then
				table.insert(uids, item.uid)
				sum += Furnace.fillOf(item)
				if Furnace.needsConfirm(item) then
					risky += 1
				end
			end
		end
		return uids, sum, risky
	end

	local function tileAt(index: number): Tile
		local tile = tiles[index]
		if tile == nil then
			tile = makeTile(grid, index)
			tiles[index] = tile
			local tileButton = tile.button
			tileButton.MouseButton1Click:Connect(function()
				local uid = tileButton:GetAttribute("Uid")
				if type(uid) ~= "string" then
					return
				end
				picked[uid] = if picked[uid] then nil else true
				asking = false
				repaint()
			end)
		end
		return tile
	end

	--- Every pick below the confirm line, or none if they are all picked already.
	local function selectableAll(): boolean
		local any = false
		for _, item in owned do
			if not Furnace.needsConfirm(item) then
				any = true
				if not picked[item.uid] then
					return false
				end
			end
		end
		return any
	end

	paint = function(state: any)
		lastState = state
		local fill = if type(state.furnaceFill) == "number" then state.furnaceFill else 0
		local rolls = if type(state.furnaceRolls) == "number" then state.furnaceRolls else 0
		rollsText.Text = tostring(rolls)

		-- Every washed or Slagged nuke you own, with where it lives. Not hearted ones
		-- (Shared/Bag): the server refuses them, so they never get a card here.
		table.clear(owned)
		table.clear(byUid)
		local function add(list: any, where: string)
			for _, item in list or {} do
				local usable = (item.clean and item.identified and item.itemId) or item.modifier == "Slagged"
				if usable and item.crateId == nil and item.hearted ~= true then
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
			local fa, fb = Furnace.fillOf(a), Furnace.fillOf(b)
			if fa ~= fb then
				return fa < fb
			end
			if a.name ~= b.name then
				return (a.name or "") < (b.name or "")
			end
			return a.uid < b.uid
		end)
		-- Picks that left (burned, sold, merged) just drop.
		for uid in picked do
			if byUid[uid] == nil then
				picked[uid] = nil
			end
		end

		for index, item in owned do
			local tile = tileAt(index)
			local isPicked = picked[item.uid] == true
			tile.button.Visible = true
			tile.button:SetAttribute("Uid", item.uid)
			tile.stroke.Color = if isPicked then SKIN.molten else SKIN.edge
			tile.stroke.Thickness = if isPicked then 3 else 2
			tile.check.Visible = isPicked
			tile.strip.BackgroundColor3 = rarityColor(item.rarity)
			tile.name.Text = item.name or "???"
			tile.name.TextColor3 = rarityColor(item.rarity)
			tile.fill.Text = `+{Furnace.fillOf(item)}%`
			tile.where.Text = item.where
			tile.where.BackgroundColor3 = if item.where == "BAG" then SKIN.bag else SKIN.locker
			ItemArt.paint(tile.viewport, item, (TILE_W - 12) / 48)
		end
		for index = #owned + 1, #tiles do
			tiles[index].button.Visible = false
			ItemArt.clear(tiles[index].viewport)
		end
		gridEmpty.Visible = #owned == 0

		local uids, sum, risky = pickedList()
		bar.Size = UDim2.fromScale(math.clamp(fill / Furnace.FULL, 0, 1), 1)
		preview.Size = UDim2.fromScale(math.clamp((fill + sum) / Furnace.FULL, 0, 1), 1)
		local after = fill + sum
		local gain = math.floor(after / Furnace.FULL)
		meterText.Text = if sum > 0
			then `{fill}%  +{sum}%{if gain > 0 then `  \u{2192}  +{gain} ROLL{if gain == 1 then "" else "S"}` else ""}`
			else `{fill}%`

		-- Each button's text and colour are written once per paint (10 Hz StationState),
		-- and none is ever hidden and shown again, so a press in progress always lands.
		setButton(selectButton, if selectableAll() then "CLEAR" else "SELECT BELOW LEGENDARY", SKIN.off)
		selectButton.TextColor3 = SKIN.text
		selectButton.TextSize = 14
		if #uids > 0 then
			setButton(burnButton, `BURN {#uids} \u{00B7} +{sum}%`, SKIN.molten)
		else
			setButton(burnButton, "PICK NUKES TO BURN", nil)
		end
		if reeling then
			-- SKIP, on request: lands the reel on the prize now.
			setButton(rollButton, "SKIP", SKIN.deep)
		elseif spinning then
			setButton(rollButton, "ROLLING\u{2026}", nil)
		elseif rolls > 0 then
			setButton(rollButton, `ROLL \u{00D7}{rolls}`, SKIN.go)
		else
			setButton(rollButton, "NO ROLLS", nil)
		end

		confirm.Visible = asking and risky > 0
		buttons.Visible = not confirm.Visible
		if confirm.Visible then
			confirmText.Text = `Burn {risky} Legendary-or-better nuke{if risky == 1 then "" else "s"}? They're gone for good.`
		end

		idleText.Visible = not hasRolled and not spinning
		if idleText.Visible then
			idleText.Text = if rolls > 0
				then "You have a roll banked \u{2014} press ROLL!"
				else `Fill the meter to {Furnace.FULL}% to bank a roll.`
		end
	end

	local function burn()
		local uids = pickedList()
		if #uids == 0 or dumpCallback == nil then
			return
		end
		asking = false
		table.clear(picked)
		dumpCallback(uids)
		repaint()
	end

	selectButton.MouseButton1Click:Connect(function()
		local all = selectableAll()
		for _, item in owned do
			if not Furnace.needsConfirm(item) then
				picked[item.uid] = if all then nil else true
			end
		end
		asking = false
		repaint()
	end)
	burnButton.MouseButton1Click:Connect(function()
		local uids, _, risky = pickedList()
		if #uids == 0 then
			return
		end
		if risky > 0 then
			asking = true
			repaint()
			return
		end
		burn()
	end)
	yesButton.MouseButton1Click:Connect(burn)
	noButton.MouseButton1Click:Connect(function()
		asking = false
		repaint()
	end)
	rollButton.MouseButton1Click:Connect(function()
		if os.clock() - skippedAt < SKIP_GRACE then
			return
		end
		if reeling then
			skippedAt = os.clock()
			reeling = false
			if reel.skip() and skipCallback then
				skipCallback()
			end
			repaint()
			return
		end
		local rolls = if lastState and type(lastState.furnaceRolls) == "number" then lastState.furnaceRolls else 0
		if spinning or rolls < 1 or rollCallback == nil then
			return
		end
		spinning = true
		awaiting += 1
		local mine = awaiting
		repaint()
		rollCallback()
		-- If the server refuses, never leave the button stuck.
		task.delay(2, function()
			if awaiting == mine then
				awaiting += 1
				spinning = false
				repaint()
			end
		end)
	end)

	local function showResult(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if lastState then
			lastState.furnaceFill = payload.fill
			lastState.furnaceRolls = payload.rolls
		end
		if payload.kind ~= "roll" or type(payload.reel) ~= "table" then
			repaint()
			return
		end
		local entries: { PrizeReel.Entry } = {}
		for index, card in payload.reel do
			entries[index] = FurnacePanel.entryFor(card)
		end
		local prize = payload.prize or {}
		awaiting += 1
		spinning = true
		reeling = true
		hasRolled = true
		resultText.Text = ""
		repaint()
		reel.spin(entries, tonumber(payload.land) or #entries, tonumber(payload.seconds) or Furnace.ROLL_SECONDS, {
			onTick = function()
				tickSound:Play()
			end,
			onLand = function()
				spinning = false
				reeling = false
				landSound:Play()
				local detail = if type(prize.detail) == "string"
					then ` ({prize.detail})`
					elseif type(prize.amount) == "number" then ` (${Mastery.short(prize.amount)})`
					else ""
				resultText.Text = `YOU GOT: {string.upper(tostring(prize.name or "?"))}{detail}`
				resultText.TextColor3 = rarityColor(prize.tier)
				repaint()
			end,
		})
	end

	return {
		frame = root,
		paint = function(state: any)
			paint(state)
		end,
		onDump = function(callback: (uids: { string }) -> ())
			dumpCallback = callback
		end,
		onRoll = function(callback: () -> ())
			rollCallback = callback
		end,
		onSkip = function(callback: () -> ())
			skipCallback = callback
		end,
		showResult = showResult,
	}
end

return FurnacePanel
