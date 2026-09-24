--!strict
--[[
	LockerPanel.luau — the Quarantine Locker, drawn inside StationController's panel.

	PICKED FROM BROWSER MOCKUPS (option 3, "specimen tubes", over a bay grid and a
	two-column transfer bench), with the tube rack in the world to match
	(build/Plots.buildQuarantineLocker). It wears the trader's field-kit slate so the
	station panels read as one set, with the hazard tape as its accent bar.

	THREE PIECES, TOP TO BOTTOM:
	  the rack     one glass tube per locker slot (Tuning.LOCKER_SLOTS, two tiers of four
	               in the world, one row here). A filled tube glows in its find's rarity
	               colour (a crusted "???" in the crust's brown, its cap still in the
	               rarity colour), with the find's own model standing in it. Under each
	               tube: what washes it at full speed, and a gauge -- one pip per point of
	               crust hardness, green where your hose already reaches, red where it
	               falls short. A washed find just says WASHED.
	  the bag      your bag as a scrolling row of tiles, to pick something to seal in.
	  the action   the selected find, and the one button for it: SEAL IN TUBE for a bag
	               find, TAKE OUT for a tube, each greyed with the reason when there is no
	               room on the other side.

	THE LOCKER IS WHERE YOU PARK A FIND instead of carrying it: the bag fills up
	(Config/Gear's Suit capacity), a stored find's decay clock stops for good, and a
	crust your hose only grinds through slowly can wait for a better hose. Nothing in
	here earns and nothing sells; the trader still sells a locker find by uid.

	Everything here is presentation. The client asks to store or take by uid;
	DeconService re-derives the station (your own rack), the room on either side and
	the item's whereabouts itself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)

local UIKit = require(script.Parent.UIKit)
local ItemArt = require(script.Parent.ItemArt)

local LockerPanel = {}

-- TraderPanel's field palette, plus the tube glass and the gauge's two states.
local SKIN = {
	card = Color3.fromHex("22272C"),
	well = Color3.fromHex("1A1E22"),
	rack = Color3.fromHex("14181B"),
	edge = Color3.fromHex("343B42"),
	rule = Color3.fromHex("30373D"),
	amber = Color3.fromHex("F2A93B"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA0A6"),
	muted = Color3.fromHex("6C737A"),
	take = Color3.fromHex("3FBF5A"),
	store = Color3.fromHex("F2A93B"),
	off = Color3.fromHex("2A3036"),
	glass = Color3.fromHex("CFE8FF"),
	glassEdge = Color3.fromHex("9FB3BF"),
	cap = Color3.fromHex("59636D"),
	crust = Color3.fromHex("8A6440"),
	crustChip = Color3.fromHex("6B4A2B"),
	crustText = Color3.fromHex("F3D9B0"),
	pipOn = Color3.fromHex("3FBF5A"),
	pipShort = Color3.fromHex("EF4444"),
	pipOff = Color3.fromHex("333A41"),
	ready = Color3.fromHex("8FF0A6"),
	needs = Color3.fromHex("FF9B8F"),
	hazard = Color3.fromHex("E8C33C"),
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.LuckiestGuy,
	label = Enum.Font.FredokaOne,
}

--- The widest the locker's panel is allowed to get, padding included. StationController
--- sets the panel's MaxSize to this in locker mode. Same as the trader's.
LockerPanel.WIDTH = 860

local HEADER_H = 58
local WALLET_INSET = 44

-- One tube, top to bottom: cap, glass, hazard base, label, gauge.
local TUBE_W = 88
local TUBE_GAP = 10
local CAP_H = 14
local GLASS_W = 72
local GLASS_H = 168
local BASE_H = 16
local GLASS_Y = CAP_H - 3
local BASE_Y = GLASS_Y + GLASS_H - 3
local LABEL_Y = BASE_Y + BASE_H + 4
local GAUGE_Y = LABEL_Y + 20
local TUBE_H = GAUGE_Y + 10
local RACK_PAD = 12
local RACK_H = TUBE_H + 2 * RACK_PAD
-- Pips on the gauge: crust hardness runs 1 (Scrap) to 7 (Anomaly), the same scale as
-- the seven hoses' power (Config/Gear.Cleaner), which is what makes one pip per point
-- honest on both sides.
local PIPS = 7
local PIP_W = 9
local PIP_GAP = 2

local STRIP_H = 150
local ACTION_W = 250
local BAG_TILE_W = 86
local BAG_TILE_H = 100

local PULSE = TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local function rarityColor(name: string?): Color3
	local def = if name then Rarity.DEFS[name] else nil
	return if def then def.color else SKIN.dim
end

--- The shop's inkShopText recipe: a rounded INK stroke on the glyphs, scaled to the text.
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

--- Yellow/black bands across `parent`, clipped to it. `vertical` stacks them top to
--- bottom (the header's tape), otherwise left to right (a tube's base).
local function hazardBands(parent: Frame, count: number, vertical: boolean)
	parent.ClipsDescendants = true
	for index = 0, count - 1 do
		local band = frame(parent, `Band{index}`, if index % 2 == 0 then SKIN.hazard else SKIN.ink)
		if vertical then
			band.Position = UDim2.fromScale(0, index / count)
			band.Size = UDim2.fromScale(1, 1 / count)
		else
			band.Position = UDim2.fromScale(index / count, 0)
			band.Size = UDim2.fromScale(1 / count, 1)
		end
	end
end

local function chip(parent: Instance, name: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 20)
	label.BorderSizePixel = 0
	label.Font = SKIN.label
	label.TextSize = 13
	label.TextColor3 = SKIN.ink
	label.Parent = parent
	corner(label, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = label
	return label
end

--- The hardest patch left on a find, or 0 once it is washed.
local function hardestPatch(item: any): number
	local worst = 0
	for _, hardness in item.patches or {} do
		if type(hardness) == "number" and hardness > worst then
			worst = hardness
		end
	end
	return worst
end

--- What a find's tube says under it, and in what colour.
local function statusOf(item: any): (string, Color3)
	if item.clean then
		return "WASHED", rarityColor(item.rarity)
	end
	if item.blockedBy == nil then
		return "READY TO WASH", SKIN.ready
	end
	return string.upper(item.needs or "a better hose"), SKIN.needs
end

-- ── Build ───────────────────────────────────────────────────────────────

export type Panel = {
	frame: Frame,
	paint: (state: any) -> (),
	onStore: (callback: (uid: string) -> ()) -> (),
	onTake: (callback: (uid: string) -> ()) -> (),
}

type Tube = {
	button: TextButton,
	cap: Frame,
	glass: Frame,
	glassEdge: UIStroke,
	glow: Frame,
	viewport: ViewportFrame,
	empty: TextLabel,
	label: TextLabel,
	gauge: Frame,
	pips: { Frame },
	motion: { Tween },
	lit: boolean,
}

local function makeTube(parent: Instance, order: number): Tube
	local button = Instance.new("TextButton")
	button.Name = `Tube{order}`
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(TUBE_W, TUBE_H)
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Parent = parent

	local glass = frame(button, "Glass", SKIN.glass)
	glass.AnchorPoint = Vector2.new(0.5, 0)
	glass.Position = UDim2.new(0.5, 0, 0, GLASS_Y)
	glass.Size = UDim2.fromOffset(GLASS_W, GLASS_H)
	glass.BackgroundTransparency = 0.93
	glass.ClipsDescendants = true
	corner(glass, 30)
	local glassEdge = edge(glass, SKIN.glassEdge, 2)
	glassEdge.Transparency = 0.35

	-- The fluid: a rarity-coloured wash, strongest at the foot of the tube.
	local glow = frame(glass, "Glow", SKIN.crust)
	glow.Size = UDim2.fromScale(1, 1)
	glow.BackgroundTransparency = 0.45
	-- Its own rounding: the glass clips to a rectangle, not to its corners.
	corner(glow, 30)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.55, 0.75),
		NumberSequenceKeypoint.new(1, 0),
	})
	fade.Parent = glow

	local art = frame(glass, "Art")
	art.AnchorPoint = Vector2.new(0.5, 1)
	art.Position = UDim2.new(0.5, 0, 1, -8)
	art.Size = UDim2.fromOffset(GLASS_W - 6, 104)
	art.ZIndex = 3
	local viewport = ItemArt.newViewport(art)
	viewport.ZIndex = 3

	-- Bubbles rising through the fluid, and a highlight down the glass.
	local motion: { Tween } = {}
	for index = 1, 3 do
		local bubble = frame(glass, `Bubble{index}`, Color3.new(1, 1, 1))
		bubble.Size = UDim2.fromOffset(6, 6)
		bubble.ZIndex = 2
		corner(bubble, 3)
		local x = 0.22 + (index - 1) * 0.26
		bubble.Position = UDim2.new(x, 0, 1, -10)
		bubble.BackgroundTransparency = 0.35
		bubble.Visible = false -- setLit shows them once the tube holds something
		local rise = TweenInfo.new(2.4 + index * 0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false, (order * 0.37 + index * 0.8) % 2)
		table.insert(motion, TweenService:Create(bubble, rise, { Position = UDim2.new(x, 0, 0, 10), BackgroundTransparency = 1 }))
	end
	table.insert(motion, TweenService:Create(glow, PULSE, { BackgroundTransparency = 0.7 }))

	local shine = frame(glass, "Shine", Color3.new(1, 1, 1))
	shine.Position = UDim2.fromOffset(12, 14)
	shine.Size = UDim2.new(0, 4, 1, -34)
	shine.BackgroundTransparency = 0.78
	shine.ZIndex = 4
	corner(shine, 2)

	local empty = text(glass, {
		name = "Empty",
		size = UDim2.fromScale(1, 1),
		textSize = 13,
		color = SKIN.muted,
		xAlign = Enum.TextXAlignment.Center,
		text = "EMPTY",
		ink = false,
	})
	empty.ZIndex = 4

	-- Cap and base sit over the glass's ends.
	local cap = frame(button, "Cap", SKIN.cap)
	cap.AnchorPoint = Vector2.new(0.5, 0)
	cap.Position = UDim2.fromScale(0.5, 0)
	cap.Size = UDim2.fromOffset(TUBE_W - 8, CAP_H)
	cap.ZIndex = 5
	corner(cap, 5)
	edge(cap, SKIN.ink, 2)

	local base = frame(button, "Base", SKIN.hazard)
	base.Position = UDim2.fromOffset(0, BASE_Y)
	base.Size = UDim2.fromOffset(TUBE_W, BASE_H)
	base.ZIndex = 5
	hazardBands(base, 8, false)
	corner(base, 4)
	edge(base, SKIN.ink, 2)

	local label = text(button, {
		name = "Status",
		position = UDim2.fromOffset(-6, LABEL_Y),
		size = UDim2.fromOffset(TUBE_W + 12, 16),
		textSize = 12,
		xAlign = Enum.TextXAlignment.Center,
		ink = false,
	})
	label.TextTruncate = Enum.TextTruncate.AtEnd

	local gaugeW = PIPS * PIP_W + (PIPS - 1) * PIP_GAP
	local gauge = frame(button, "Gauge")
	gauge.AnchorPoint = Vector2.new(0.5, 0)
	gauge.Position = UDim2.new(0.5, 0, 0, GAUGE_Y)
	gauge.Size = UDim2.fromOffset(gaugeW, 8)
	local pips: { Frame } = {}
	for index = 1, PIPS do
		local pip = frame(gauge, `Pip{index}`, SKIN.pipOff)
		pip.Position = UDim2.fromOffset((index - 1) * (PIP_W + PIP_GAP), 0)
		pip.Size = UDim2.fromOffset(PIP_W, 8)
		corner(pip, 2)
		pips[index] = pip
	end

	return {
		button = button,
		cap = cap,
		glass = glass,
		glassEdge = glassEdge,
		glow = glow,
		viewport = viewport,
		empty = empty,
		label = label,
		gauge = gauge,
		pips = pips,
		motion = motion,
		lit = false,
	}
end

--- Start or stop a tube's bubbles and pulse. Tweens that repeat forever are only left
--- running on tubes that hold something.
local function setLit(tube: Tube, lit: boolean)
	if tube.lit == lit then
		return
	end
	tube.lit = lit
	for _, tween in tube.motion do
		if lit then
			tween:Play()
		else
			tween:Cancel()
		end
	end
	for _, child in tube.glass:GetChildren() do
		if child:IsA("Frame") and string.sub(child.Name, 1, 6) == "Bubble" then
			child.Visible = lit
		end
	end
end

local function makeBagTile(parent: Instance, order: number): TextButton
	local tile = Instance.new("TextButton")
	tile.Name = `Tile{order}`
	tile.LayoutOrder = order
	tile.Size = UDim2.fromOffset(BAG_TILE_W, BAG_TILE_H)
	tile.Text = ""
	tile.AutoButtonColor = false
	tile.BorderSizePixel = 0
	tile.BackgroundColor3 = SKIN.card
	tile.Parent = parent
	corner(tile, 10)
	edge(tile, SKIN.edge, 2).Name = "Edge"

	local strip = frame(tile, "RarityStrip", SKIN.dim)
	strip.Position = UDim2.fromOffset(10, 6)
	strip.Size = UDim2.new(1, -20, 0, 4)
	corner(strip, 2)

	local art = frame(tile, "Art")
	art.Position = UDim2.fromOffset(6, 12)
	art.Size = UDim2.new(1, -12, 0, 60)
	ItemArt.newViewport(art)

	text(tile, {
		name = "ItemName",
		position = UDim2.new(0, 4, 1, -24),
		size = UDim2.new(1, -8, 0, 18),
		textSize = 12,
		xAlign = Enum.TextXAlignment.Center,
		ink = false,
	}).TextTruncate = Enum.TextTruncate.AtEnd
	return tile
end

function LockerPanel.new(parent: Instance, layoutOrder: number): Panel
	local root = frame(parent, "Locker")
	root.LayoutOrder = layoutOrder
	root.Size = UDim2.new(1, 0, 0, HEADER_H + 14 + RACK_H + 12 + STRIP_H)
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
	hazardBands(tape, 6, true)

	text(header, {
		name = "Title",
		position = UDim2.fromOffset(18, 2),
		size = UDim2.fromOffset(420, 36),
		font = SKIN.headline,
		textSize = 34,
		text = "QUARANTINE LOCKER",
	})
	text(header, {
		name = "Subtitle",
		position = UDim2.fromOffset(18, 36),
		size = UDim2.fromOffset(480, 16),
		textSize = 14,
		color = SKIN.dim,
		text = "Sealed finds stop decaying. Take one out when your hose can crack it.",
		ink = false,
	})

	text(header, {
		name = "CountLabel",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 6),
		size = UDim2.fromOffset(120, 14),
		textSize = 12,
		xAlign = Enum.TextXAlignment.Right,
		text = "TUBES",
	})
	local count = text(header, {
		name = "Count",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 21),
		size = UDim2.fromOffset(120, 30),
		font = SKIN.headline,
		textSize = 28,
		color = SKIN.amber,
		xAlign = Enum.TextXAlignment.Right,
	})

	-- ── The rack ───────────────────────────────────────────────────────
	local rack = Instance.new("ScrollingFrame")
	rack.Name = "Rack"
	rack.Position = UDim2.fromOffset(0, HEADER_H + 14)
	rack.Size = UDim2.new(1, 0, 0, RACK_H)
	rack.BackgroundColor3 = SKIN.rack
	rack.BorderSizePixel = 0
	rack.ScrollingDirection = Enum.ScrollingDirection.X
	rack.ScrollBarThickness = 5
	rack.ScrollBarImageColor3 = SKIN.edge
	rack.CanvasSize = UDim2.new()
	rack.AutomaticCanvasSize = Enum.AutomaticSize.X
	rack.Parent = root
	corner(rack, 14)
	edge(rack, SKIN.edge, 2)

	local rackPad = Instance.new("UIPadding")
	rackPad.PaddingTop = UDim.new(0, RACK_PAD)
	rackPad.PaddingLeft = UDim.new(0, RACK_PAD)
	rackPad.PaddingRight = UDim.new(0, RACK_PAD)
	rackPad.Parent = rack

	local rackLayout = Instance.new("UIListLayout")
	rackLayout.FillDirection = Enum.FillDirection.Horizontal
	rackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rackLayout.Padding = UDim.new(0, TUBE_GAP)
	rackLayout.Parent = rack

	local tubes: { Tube } = {}

	-- ── The bag strip ──────────────────────────────────────────────────
	local stripY = HEADER_H + 14 + RACK_H + 12
	local bag = frame(root, "Bag", SKIN.well)
	bag.Position = UDim2.fromOffset(0, stripY)
	bag.Size = UDim2.new(1, -(ACTION_W + 12), 0, STRIP_H)
	corner(bag, 12)
	edge(bag, SKIN.edge, 2)

	local bagTitle = text(bag, {
		name = "Title",
		position = UDim2.fromOffset(12, 8),
		size = UDim2.new(1, -24, 0, 16),
		textSize = 13,
		color = SKIN.dim,
		ink = false,
	})

	local bagRow = Instance.new("ScrollingFrame")
	bagRow.Name = "Row"
	bagRow.Position = UDim2.fromOffset(10, 30)
	bagRow.Size = UDim2.new(1, -20, 0, BAG_TILE_H + 10)
	bagRow.BackgroundTransparency = 1
	bagRow.BorderSizePixel = 0
	bagRow.ScrollingDirection = Enum.ScrollingDirection.X
	bagRow.ScrollBarThickness = 5
	bagRow.ScrollBarImageColor3 = SKIN.edge
	bagRow.CanvasSize = UDim2.new()
	bagRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	bagRow.Parent = bag

	local bagLayout = Instance.new("UIListLayout")
	bagLayout.FillDirection = Enum.FillDirection.Horizontal
	bagLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bagLayout.Padding = UDim.new(0, 8)
	bagLayout.Parent = bagRow

	local bagEmpty = text(bag, {
		name = "Empty",
		position = UDim2.fromOffset(12, 30),
		size = UDim2.new(1, -24, 0, BAG_TILE_H),
		textSize = 15,
		color = SKIN.muted,
		xAlign = Enum.TextXAlignment.Center,
		text = "Your bag is empty.",
		ink = false,
	})

	local bagTiles: { TextButton } = {}

	-- ── The action card ────────────────────────────────────────────────
	local action = frame(root, "Action", SKIN.card)
	action.AnchorPoint = Vector2.new(1, 0)
	action.Position = UDim2.new(1, 0, 0, stripY)
	action.Size = UDim2.fromOffset(ACTION_W, STRIP_H)
	corner(action, 12)
	edge(action, SKIN.edge, 2)

	local well = frame(action, "ArtWell", SKIN.well)
	well.Position = UDim2.fromOffset(10, 10)
	well.Size = UDim2.fromOffset(62, 62)
	corner(well, 10)
	local actionViewport = ItemArt.newViewport(well)

	local actionName = text(action, {
		name = "ItemName",
		position = UDim2.fromOffset(82, 12),
		size = UDim2.new(1, -92, 0, 26),
		font = SKIN.headline,
		textSize = 22,
	})
	actionName.TextTruncate = Enum.TextTruncate.AtEnd
	local rarityChip = chip(action, "Rarity")
	rarityChip.Position = UDim2.fromOffset(82, 44)

	local actionStatus = text(action, {
		name = "Status",
		position = UDim2.fromOffset(10, 78),
		size = UDim2.new(1, -20, 0, 16),
		textSize = 13,
		ink = false,
	})
	actionStatus.TextTruncate = Enum.TextTruncate.AtEnd

	local button = Instance.new("TextButton")
	button.Name = "Move"
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, 10, 1, -10)
	button.Size = UDim2.new(1, -20, 0, 42)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = SKIN.headline
	button.TextSize = 22
	button.TextColor3 = SKIN.text
	button.Parent = action
	corner(button, 12)
	ink(button)
	edge(button, SKIN.ink, 3)

	local hint = text(action, {
		name = "Hint",
		position = UDim2.fromOffset(14, 0),
		size = UDim2.new(1, -28, 1, 0),
		textSize = 15,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = "Pick a tube to take a find out, or a bag find to seal it in.",
		ink = false,
	})

	-- ── Behaviour ───────────────────────────────────────────────────────
	local selected: string? = nil
	local storeCallback: ((uid: string) -> ())? = nil
	local takeCallback: ((uid: string) -> ())? = nil
	local lastState: any = nil
	-- What the button would do right now, set by paint: "store", "take" or nil.
	local verb: string? = nil
	local paint: (state: any) -> ()

	local function choose(uid: any)
		if type(uid) == "string" then
			selected = if selected == uid then nil else uid
			if lastState then
				paint(lastState)
			end
		end
	end

	local function tubeAt(index: number): Tube
		local tube = tubes[index]
		if tube == nil then
			tube = makeTube(rack, index)
			tubes[index] = tube
			local tubeButton = tube.button
			tubeButton.MouseButton1Click:Connect(function()
				choose(tubeButton:GetAttribute("Uid"))
			end)
		end
		return tube
	end

	local function bagTileAt(index: number): TextButton
		local tile = bagTiles[index]
		if tile == nil then
			tile = makeBagTile(bagRow, index)
			bagTiles[index] = tile
			tile.MouseButton1Click:Connect(function()
				choose(tile:GetAttribute("Uid"))
			end)
		end
		return tile
	end

	local function paintTube(tube: Tube, item: any?, isSelected: boolean)
		tube.button.Visible = true
		tube.glassEdge.Color = if isSelected then SKIN.amber else SKIN.glassEdge
		tube.glassEdge.Thickness = if isSelected then 3 else 2
		tube.glassEdge.Transparency = if isSelected then 0 else 0.35

		if item == nil then
			tube.button:SetAttribute("Uid", nil)
			tube.cap.BackgroundColor3 = SKIN.cap
			tube.glow.Visible = false
			tube.empty.Visible = true
			tube.label.Text = ""
			tube.gauge.Visible = false
			ItemArt.clear(tube.viewport)
			setLit(tube, false)
			return
		end

		tube.button:SetAttribute("Uid", item.uid)
		tube.cap.BackgroundColor3 = rarityColor(item.rarity)
		tube.glow.Visible = true
		tube.glow.BackgroundColor3 = if item.clean then rarityColor(item.rarity) else SKIN.crust
		tube.empty.Visible = false
		local status, color = statusOf(item)
		tube.label.Text = status
		tube.label.TextColor3 = color

		-- One pip per point of hardness left; green where the hose you own reaches.
		local need = hardestPatch(item)
		local have = math.floor(if type(lastState.potency) == "number" then lastState.potency else 0)
		tube.gauge.Visible = need > 0
		for index, pip in tube.pips do
			pip.BackgroundColor3 = if index > need then SKIN.pipOff elseif index <= have then SKIN.pipOn else SKIN.pipShort
		end

		ItemArt.paint(tube.viewport, item, (GLASS_W - 6) / 104)
		setLit(tube, true)
	end

	local function paintBagTile(tile: TextButton, item: any, isSelected: boolean)
		tile.Visible = true
		tile:SetAttribute("Uid", item.uid)
		local stroke = tile:FindFirstChild("Edge") :: UIStroke
		stroke.Color = if isSelected then SKIN.amber else SKIN.edge
		stroke.Thickness = if isSelected then 3 else 2
		local strip = tile:FindFirstChild("RarityStrip") :: Frame
		strip.BackgroundColor3 = rarityColor(item.rarity)
		local name = tile:FindFirstChild("ItemName") :: TextLabel
		name.Text = item.name
		name.TextColor3 = if item.clean then SKIN.text else SKIN.crustText
		local viewport = (tile:FindFirstChild("Art") :: Frame):FindFirstChild("Model") :: ViewportFrame
		ItemArt.paint(viewport, item, (BAG_TILE_W - 12) / 60)
	end

	local function paintAction(item: any?, inLocker: boolean, lockerFull: boolean, bagFull: boolean)
		local has = item ~= nil
		well.Visible = has
		actionName.Visible = has
		rarityChip.Visible = has
		actionStatus.Visible = has
		button.Visible = has
		hint.Visible = not has
		verb = nil
		if item == nil then
			ItemArt.clear(actionViewport)
			return
		end

		actionName.Text = item.name
		actionName.TextColor3 = if item.clean then SKIN.text else SKIN.crustText
		rarityChip.Text = string.upper(item.rarity or "")
		rarityChip.BackgroundColor3 = rarityColor(item.rarity)
		local status, color = statusOf(item)
		actionStatus.Text = if item.clean or item.blockedBy == nil then status else `Full speed with {item.needs}`
		actionStatus.TextColor3 = color
		ItemArt.paint(actionViewport, item, 1)

		local blocked = if inLocker then bagFull else lockerFull
		verb = if blocked then nil elseif inLocker then "take" else "store"
		button.Text = if inLocker
			then (if bagFull then "BAG FULL" else "TAKE OUT")
			else (if lockerFull then "LOCKER FULL" else "SEAL IN TUBE")
		button.BackgroundColor3 = if blocked then SKIN.off elseif inLocker then SKIN.take else SKIN.store
		button.TextColor3 = if blocked then SKIN.muted else SKIN.text
	end

	paint = function(state: any)
		lastState = state
		local locker = state.locker or {}
		local items = state.items or {}
		local slots = if type(state.lockerSlots) == "number" then state.lockerSlots else #locker
		local capacity = if type(state.capacity) == "number" then state.capacity else #items

		-- The selection follows its find across the two lists; one that left both (sold,
		-- or the panel reopened after it was washed and taken) just drops.
		local chosen, chosenInLocker = nil, false
		for _, item in locker do
			if item.uid == selected then
				chosen, chosenInLocker = item, true
			end
		end
		for _, item in items do
			if item.uid == selected then
				chosen = item
			end
		end
		if chosen == nil then
			selected = nil
		end

		local shown = math.max(slots, #locker)
		for index = 1, shown do
			local item = locker[index]
			paintTube(tubeAt(index), item, item ~= nil and item.uid == selected)
		end
		for index = shown + 1, #tubes do
			tubes[index].button.Visible = false
			ItemArt.clear(tubes[index].viewport)
			setLit(tubes[index], false)
		end

		for index, item in items do
			paintBagTile(bagTileAt(index), item, item.uid == selected)
		end
		for index = #items + 1, #bagTiles do
			bagTiles[index].Visible = false
			ItemArt.clear((bagTiles[index]:FindFirstChild("Art") :: Frame):FindFirstChild("Model") :: ViewportFrame)
		end
		bagEmpty.Visible = #items == 0
		bagTitle.Text = `YOUR BAG  {#items}/{capacity}  \u{00B7}  pick a find, then SEAL IN TUBE`

		paintAction(chosen, chosenInLocker, #locker >= slots, #items >= capacity)
		count.Text = `{#locker}/{slots}`
		count.TextColor3 = if #locker >= slots then SKIN.needs else SKIN.amber
	end

	button.MouseButton1Click:Connect(function()
		if selected == nil then
			return
		end
		if verb == "store" and storeCallback then
			storeCallback(selected)
		elseif verb == "take" and takeCallback then
			takeCallback(selected)
		end
	end)

	return {
		frame = root,
		paint = function(state: any)
			paint(state)
		end,
		onStore = function(callback: (uid: string) -> ())
			storeCallback = callback
		end,
		onTake = function(callback: (uid: string) -> ())
			takeCallback = callback
		end,
	}
end

return LockerPanel
