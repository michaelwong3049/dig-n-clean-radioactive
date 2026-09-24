--!strict
--[[
	TraderPanel.luau — the trader's buyback counter, drawn inside StationController's panel.

	PICKED FROM BROWSER MOCKUPS (option 1, "field-kit counter"). It wears the gear shop's
	field-kit skin -- dark slate, LuckiestGuy/FredokaOne in the cartoon INK outline -- so
	the two panels on the plaza read as one set, with a hazard-striped accent bar for the
	booth's tape instead of a stall colour.

	THREE PIECES, LEFT TO RIGHT, TOP TO BOTTOM:
	  the bag      a 3-wide grid of item tiles, one per slot up to your capacity, each
	               with a rarity pill, the item's own model and its sale price. Empty
	               slots draw as empty tiles so "how full am I" is answered by looking.
	               It scrolls past three rows: a maxed suit and level carries 40.
	  the detail   the selected item, big: model, name, rarity and modifier chips,
	               condition, what it pays, and one SELL button. A crusted "???" also
	               says what the blind sale is trading away -- and, when the hose you
	               own cannot crack it at all, what would.
	  the footer   SELL ALL CLEAN and SELL ALL ???, each carrying its own total.

	THE MODEL IS THE REAL ONE, OR THE CRUST. A clean item's art is ItemModels' model for
	its id (the payload only carries `itemId` once it is identified, CarryService.describe);
	a "???" is ItemCrust.lump seeded on its uid, the same lump the dig pulled up. Both are
	built once per tile per item (`ArtKey`), not on every 10 Hz StationState tick.

	Everything here is presentation. The client asks for a sale by uid, or for a bulk sale
	by "clean"/"dirty"; EconomyService re-derives the price and the ownership itself.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Tuning = require(Shared.Config.Tuning)
local ItemModels = require(Shared.ItemModels)
local ItemCrust = require(Shared.ItemCrust)
local ItemFx = require(Shared.ItemFx)

local UIKit = require(script.Parent.UIKit)

local TraderPanel = {}

-- The shop panel's FIELD palette, the subset this panel uses. StationController keeps
-- its copy file-local on purpose (see its note), so this is a copy rather than a reach.
local SKIN = {
	card = Color3.fromHex("22272C"),
	well = Color3.fromHex("1A1E22"),
	edge = Color3.fromHex("343B42"),
	rule = Color3.fromHex("30373D"),
	amber = Color3.fromHex("F2A93B"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA0A6"),
	muted = Color3.fromHex("6C737A"),
	button = Color3.fromHex("2A3036"),
	sell = Color3.fromHex("3FBF5A"),
	crustChip = Color3.fromHex("6B4A2B"),
	crustText = Color3.fromHex("F3D9B0"),
	crustWell = Color3.fromHex("3A2C1F"),
	hazard = Color3.fromHex("E8C33C"),
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.LuckiestGuy,
	label = Enum.Font.FredokaOne,
}

local COLUMNS = 3
local TILE_W = 136
local TILE_H = 128
local TILE_GAP = 10
local VISIBLE_ROWS = 3
local SCROLLBAR = 6
local GRID_W = COLUMNS * TILE_W + (COLUMNS - 1) * TILE_GAP + SCROLLBAR + 6
local BODY_H = VISIBLE_ROWS * TILE_H + (VISIBLE_ROWS - 1) * TILE_GAP
local HEADER_H = 58
local FOOTER_H = 44
local DETAIL_PAD = 16
local DETAIL_ART_H = 130
-- The panel's own padding (StationController's PANEL_PAD) and the gap between the grid
-- and the detail card, for the detail well's aspect.
local PANEL_PAD = 16
local BODY_GAP = 12
local WALLET_INSET = 44

--- The widest the trader's panel is allowed to get, padding included. StationController
--- sets the panel's MaxSize to this in trader mode.
TraderPanel.WIDTH = 860
local DETAIL_ART_W = TraderPanel.WIDTH - 2 * PANEL_PAD - GRID_W - BODY_GAP - 2 * DETAIL_PAD

-- Same camera recipe as the shop cards and the index: a narrow lens from a little right
-- of front and above, and a low ambient under a warm key so rarities keep their colour.
local ART_FOV = 30
local ART_MARGIN = 1.12
local ART_FROM = Vector3.new(0.45, 0.3, 1).Unit
local ART_LIGHT = {
	ambient = Color3.fromRGB(90, 92, 98),
	color = Color3.fromRGB(255, 248, 235),
	direction = Vector3.new(-1, -1, -1),
}

local BOX_CORNERS = {}
for _, x in { -1, 1 } do
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(BOX_CORNERS, Vector3.new(x, y, z))
		end
	end
end

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

local function newViewport(parent: Instance): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Model"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = ART_LIGHT.ambient
	viewport.LightColor = ART_LIGHT.color
	viewport.LightDirection = ART_LIGHT.direction
	viewport.Parent = parent

	local camera = Instance.new("Camera")
	camera.FieldOfView = ART_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

--- Aim `camera` so `model` fills a well `aspect` wide per unit tall. The box is measured
--- in the camera's own axes (StationController.frameArt's reasoning), so a three-quarter
--- view is framed tight rather than to the model's loose aligned box.
local function frameModel(camera: Camera, model: Model, aspect: number)
	local look = CFrame.lookAt(Vector3.zero, -ART_FROM, Vector3.yAxis)
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local half = part.Size / 2
			for _, c in BOX_CORNERS do
				local point = look:PointToObjectSpace(part.CFrame * (half * c))
				lo = lo:Min(point)
				hi = hi:Max(point)
			end
		end
	end
	if lo.X > hi.X then
		return
	end
	local mid = (lo + hi) / 2
	local extent = (hi - lo) / 2
	local tanHalf = math.tan(math.rad(ART_FOV) / 2)
	local reach = math.max(extent.Y / tanHalf, extent.X / (tanHalf * aspect)) * ART_MARGIN
	camera.CFrame = look * CFrame.new(mid.X, mid.Y, hi.Z + reach)
end

--- A fresh model for one bag entry: the item itself once it is identified, its crust
--- until then. ItemFx comes off (its lights and particles do not render in a viewport).
local function modelFor(item: any): Model
	local model: Model? = nil
	if item.identified and type(item.itemId) == "string" and Items.has(item.itemId) then
		local def = Items.get(item.itemId)
		model = ItemModels.create(def.model, item.itemId)
		if model then
			CollectionService:RemoveTag(model, ItemFx.TAG)
			for _, node in model:GetDescendants() do
				CollectionService:RemoveTag(node, ItemFx.TAG)
			end
			model:PivotTo(ItemModels.rotation(model, "Gallery"))
		end
	end
	if model == nil and not item.identified then
		model = ItemCrust.lump(item.rarity, item.uid)
	end
	if model == nil then
		local block = Instance.new("Part")
		block.Name = "Placeholder"
		block.Size = Vector3.one
		block.Color = rarityColor(item.rarity)
		block.Material = Enum.Material.SmoothPlastic
		local holder = Instance.new("Model")
		block.Parent = holder
		holder.PrimaryPart = block
		model = holder
	end
	return model :: Model
end

--- Swap `item`'s model into `viewport`, unless it is already showing it.
local function paintArt(viewport: ViewportFrame, item: any, aspect: number)
	local key = `{item.uid}/{item.itemId or "crust"}`
	if viewport:GetAttribute("ArtKey") == key then
		return
	end
	viewport:SetAttribute("ArtKey", key)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	local model = modelFor(item)
	model.Parent = viewport
	frameModel(viewport.CurrentCamera :: Camera, model, aspect)
end

local function clearArt(viewport: ViewportFrame)
	if viewport:GetAttribute("ArtKey") == nil then
		return
	end
	viewport:SetAttribute("ArtKey", nil)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
end

--- A rounded chip that grows to its text. Used for rarity and modifier.
local function chip(parent: Instance, name: string, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 22)
	label.BorderSizePixel = 0
	label.Font = SKIN.label
	label.TextSize = 14
	label.TextColor3 = SKIN.ink
	label.Parent = parent
	corner(label, 11)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = label
	return label
end

-- ── Build ───────────────────────────────────────────────────────────────

export type Panel = {
	frame: Frame,
	paint: (state: any) -> (),
	onSell: (callback: (uid: string) -> ()) -> (),
	onSellAll: (callback: (which: string) -> ()) -> (),
}

local function makeTile(parent: Instance, order: number): TextButton
	local tile = Instance.new("TextButton")
	tile.Name = `Tile{order}`
	tile.LayoutOrder = order
	tile.Text = ""
	tile.AutoButtonColor = false
	tile.BorderSizePixel = 0
	tile.BackgroundColor3 = SKIN.card
	tile.Parent = parent
	corner(tile, 14)
	local stroke = edge(tile, SKIN.edge, 2)
	stroke.Name = "Edge"

	-- A pill, not a full-width band: Roblox clips to rectangles, so a band would square
	-- off the tile's rounded top corners.
	local strip = frame(tile, "RarityStrip", SKIN.dim)
	strip.Position = UDim2.fromOffset(12, 7)
	strip.Size = UDim2.new(1, -24, 0, 4)
	corner(strip, 2)

	local art = frame(tile, "Art")
	art.Position = UDim2.fromOffset(8, 14)
	art.Size = UDim2.new(1, -16, 0, 62)
	newViewport(art)

	local crusted = text(tile, {
		name = "Crusted",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -7, 0, 15),
		size = UDim2.fromOffset(62, 16),
		textSize = 11,
		color = SKIN.crustText,
		xAlign = Enum.TextXAlignment.Center,
		text = "CRUSTED",
		ink = false,
	})
	crusted.BackgroundColor3 = SKIN.crustChip
	crusted.BackgroundTransparency = 0
	crusted.ZIndex = 2
	corner(crusted, 6)

	text(tile, {
		name = "ItemName",
		position = UDim2.new(0, 8, 1, -50),
		size = UDim2.new(1, -16, 0, 18),
		textSize = 14,
		xAlign = Enum.TextXAlignment.Center,
	}).TextTruncate = Enum.TextTruncate.AtEnd

	text(tile, {
		name = "Price",
		position = UDim2.new(0, 0, 1, -30),
		size = UDim2.new(1, 0, 0, 24),
		font = SKIN.headline,
		textSize = 20,
		color = SKIN.amber,
		xAlign = Enum.TextXAlignment.Center,
	})
	return tile
end

function TraderPanel.new(parent: Instance, layoutOrder: number): Panel
	local root = frame(parent, "Trader")
	root.LayoutOrder = layoutOrder
	root.Size = UDim2.new(1, 0, 0, HEADER_H + 14 + BODY_H + 12 + FOOTER_H)
	root.Visible = false

	-- ── Header ─────────────────────────────────────────────────────────
	local header = frame(root, "Header")
	header.Size = UDim2.new(1, 0, 0, HEADER_H)

	local rule = frame(header, "Rule", SKIN.rule)
	rule.AnchorPoint = Vector2.new(0, 1)
	rule.Position = UDim2.fromScale(0, 1)
	rule.Size = UDim2.new(1, 0, 0, 1)

	-- The booth's hazard tape, as the accent bar the shop gives its stall colour.
	local tape = frame(header, "HazardBar")
	tape.AnchorPoint = Vector2.new(0, 0.5)
	tape.Position = UDim2.new(0, 0, 0.5, -1)
	tape.Size = UDim2.fromOffset(6, 40)
	tape.ClipsDescendants = true
	for index = 0, 5 do
		local band = frame(tape, `Band{index}`, if index % 2 == 0 then SKIN.hazard else SKIN.ink)
		band.Position = UDim2.fromOffset(0, index * 7)
		band.Size = UDim2.fromOffset(6, 7)
	end

	text(header, {
		name = "Title",
		position = UDim2.fromOffset(18, 2),
		size = UDim2.fromOffset(300, 36),
		font = SKIN.headline,
		textSize = 34,
		text = "TRADER",
	})
	local subtitle = text(header, {
		name = "Subtitle",
		position = UDim2.fromOffset(18, 36),
		size = UDim2.fromOffset(360, 16),
		textSize = 14,
		color = SKIN.dim,
		ink = false,
	})

	-- Inset from the right by the close badge (32px, inset 14 from the panel's edge,
	-- which sits over this corner) plus a little air.
	text(header, {
		name = "WalletLabel",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 6),
		size = UDim2.fromOffset(200, 14),
		textSize = 12,
		xAlign = Enum.TextXAlignment.Right,
		text = "ON HAND",
	})
	local wallet = text(header, {
		name = "Wallet",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 21),
		size = UDim2.fromOffset(240, 30),
		font = SKIN.headline,
		textSize = 28,
		color = SKIN.amber,
		xAlign = Enum.TextXAlignment.Right,
	})

	-- ── The bag grid ────────────────────────────────────────────────────
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Bag"
	grid.Position = UDim2.fromOffset(0, HEADER_H + 14)
	grid.Size = UDim2.fromOffset(GRID_W, BODY_H)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = SCROLLBAR
	grid.ScrollBarImageColor3 = SKIN.edge
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = root

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	gridLayout.CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	local tiles: { TextButton } = {}

	-- ── The detail card ─────────────────────────────────────────────────
	local detail = frame(root, "Detail", SKIN.card)
	detail.Position = UDim2.fromOffset(GRID_W + BODY_GAP, HEADER_H + 14)
	detail.Size = UDim2.new(1, -(GRID_W + BODY_GAP), 0, BODY_H)
	corner(detail, 14)
	edge(detail, SKIN.edge, 2)

	local well = frame(detail, "ArtWell", SKIN.well)
	well.Position = UDim2.fromOffset(DETAIL_PAD, DETAIL_PAD)
	well.Size = UDim2.new(1, -2 * DETAIL_PAD, 0, DETAIL_ART_H)
	corner(well, 10)
	local detailViewport = newViewport(well)

	local detailName = text(detail, {
		name = "ItemName",
		position = UDim2.fromOffset(DETAIL_PAD, DETAIL_PAD + DETAIL_ART_H + 8),
		size = UDim2.new(1, -2 * DETAIL_PAD, 0, 32),
		font = SKIN.headline,
		textSize = 28,
	})
	detailName.TextTruncate = Enum.TextTruncate.AtEnd

	local chips = frame(detail, "Chips")
	chips.Position = UDim2.fromOffset(DETAIL_PAD, DETAIL_PAD + DETAIL_ART_H + 44)
	chips.Size = UDim2.new(1, -2 * DETAIL_PAD, 0, 22)
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Padding = UDim.new(0, 6)
	chipLayout.Parent = chips
	local rarityChip = chip(chips, "Rarity", 1)
	local modifierChip = chip(chips, "Modifier", 2)
	modifierChip.BackgroundColor3 = SKIN.dim

	-- Label on the left, value on the right, three lines.
	local facts = frame(detail, "Facts")
	facts.Position = UDim2.fromOffset(DETAIL_PAD, DETAIL_PAD + DETAIL_ART_H + 74)
	facts.Size = UDim2.new(1, -2 * DETAIL_PAD, 0, 72)
	local factValues: { TextLabel } = {}
	for index, name in { "Condition", "Payout", "On a stand" } do
		local y = (index - 1) * 24
		text(facts, {
			name = `{name}Label`,
			position = UDim2.fromOffset(0, y),
			size = UDim2.new(0.5, 0, 0, 24),
			textSize = 15,
			color = SKIN.dim,
			text = name,
			ink = false,
		})
		factValues[index] = text(facts, {
			name = `{name}Value`,
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, 0, 0, y),
			size = UDim2.new(0.5, 0, 0, 24),
			textSize = 15,
			xAlign = Enum.TextXAlignment.Right,
			ink = false,
		})
	end

	-- The crust's warning: what the blind sale gives up, and what would crack it.
	local warning = text(detail, {
		name = "Warning",
		position = UDim2.fromOffset(DETAIL_PAD, DETAIL_PAD + DETAIL_ART_H + 74),
		size = UDim2.new(1, -2 * DETAIL_PAD, 0, 72),
		textSize = 14,
		color = SKIN.crustText,
		wrapped = true,
		yAlign = Enum.TextYAlignment.Center,
		ink = false,
	})
	warning.BackgroundColor3 = SKIN.crustWell
	warning.BackgroundTransparency = 0
	corner(warning, 8)
	local warnPad = Instance.new("UIPadding")
	warnPad.PaddingLeft = UDim.new(0, 10)
	warnPad.PaddingRight = UDim.new(0, 10)
	warnPad.Parent = warning

	local sell = Instance.new("TextButton")
	sell.Name = "Sell"
	sell.AnchorPoint = Vector2.new(0, 1)
	sell.Position = UDim2.new(0, DETAIL_PAD, 1, -DETAIL_PAD)
	sell.Size = UDim2.new(1, -2 * DETAIL_PAD, 0, 58)
	sell.AutoButtonColor = false
	sell.BorderSizePixel = 0
	sell.BackgroundColor3 = SKIN.sell
	sell.Font = SKIN.headline
	sell.TextSize = 28
	sell.TextColor3 = SKIN.text
	sell.Parent = detail
	corner(sell, 14)
	ink(sell)
	-- The ink stroke on a TextButton outlines the glyphs; the box's own border is a
	-- second stroke in Border mode.
	edge(sell, SKIN.ink, 3)

	local empty = text(detail, {
		name = "Empty",
		size = UDim2.fromScale(1, 1),
		textSize = 18,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = "Your bag is empty.",
		ink = false,
	})

	-- ── Footer ─────────────────────────────────────────────────────────
	local footer = frame(root, "Footer")
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, FOOTER_H)

	local function footButton(name: string, x: number): TextButton
		local button = Instance.new("TextButton")
		button.Name = name
		button.Position = UDim2.new(x, if x > 0 then 5 else 0, 0, 0)
		button.Size = UDim2.new(0.5, -5, 1, 0)
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.BackgroundColor3 = SKIN.button
		button.Font = SKIN.label
		button.TextSize = 17
		button.TextColor3 = SKIN.text
		button.Parent = footer
		corner(button, 12)
		edge(button, SKIN.edge, 2)
		ink(button)
		return button
	end
	local sellClean = footButton("SellAllClean", 0)
	local sellDirty = footButton("SellAllDirty", 0.5)

	-- ── Behaviour ───────────────────────────────────────────────────────
	local selected: string? = nil
	local sellCallback: ((uid: string) -> ())? = nil
	local sellAllCallback: ((which: string) -> ())? = nil
	local lastState: any = nil
	local paint: (state: any) -> ()

	local function tileAt(index: number): TextButton
		local tile = tiles[index]
		if tile == nil then
			tile = makeTile(grid, index)
			tiles[index] = tile
			tile.MouseButton1Click:Connect(function()
				local uid = tile:GetAttribute("Uid")
				if type(uid) == "string" then
					selected = uid
					if lastState then
						paint(lastState)
					end
				end
			end)
		end
		return tile
	end

	local function paintTile(tile: TextButton, item: any?, isSelected: boolean)
		tile.Visible = true
		local stroke = tile:FindFirstChild("Edge") :: UIStroke
		local strip = tile:FindFirstChild("RarityStrip") :: Frame
		local viewport = (tile:FindFirstChild("Art") :: Frame):FindFirstChild("Model") :: ViewportFrame
		local crusted = tile:FindFirstChild("Crusted") :: TextLabel
		local nameLabel = tile:FindFirstChild("ItemName") :: TextLabel
		local price = tile:FindFirstChild("Price") :: TextLabel

		if item == nil then
			tile:SetAttribute("Uid", nil)
			tile.BackgroundColor3 = SKIN.well
			tile.Active = false
			stroke.Color = SKIN.edge
			stroke.Thickness = 2
			stroke.Transparency = 0.4
			strip.Visible = false
			crusted.Visible = false
			nameLabel.Text = ""
			price.Text = ""
			clearArt(viewport)
			return
		end

		tile:SetAttribute("Uid", item.uid)
		tile.BackgroundColor3 = SKIN.card
		tile.Active = true
		stroke.Color = if isSelected then SKIN.amber else SKIN.edge
		stroke.Thickness = if isSelected then 3 else 2
		stroke.Transparency = 0
		strip.Visible = true
		strip.BackgroundColor3 = rarityColor(item.rarity)
		crusted.Visible = not item.clean
		nameLabel.Text = item.name
		price.Text = money(item.value or 0)
		paintArt(viewport, item, (TILE_W - 16) / 62)
	end

	local function paintDetail(item: any?)
		local has = item ~= nil
		well.Visible = has
		detailName.Visible = has
		chips.Visible = has
		sell.Visible = has
		empty.Visible = not has
		if item == nil then
			facts.Visible = false
			warning.Visible = false
			clearArt(detailViewport)
			return
		end

		detailName.Text = item.name
		detailName.TextColor3 = if item.clean then SKIN.text else SKIN.crustText
		rarityChip.Text = string.upper(item.rarity or "")
		rarityChip.BackgroundColor3 = rarityColor(item.rarity)
		local modifier = item.modifier
		modifierChip.Visible = type(modifier) == "string" and modifier ~= "None"
		modifierChip.Text = if type(modifier) == "string" then string.upper(modifier) else ""

		-- A clean item gets the facts; a crusted one gets the gamble spelt out instead.
		facts.Visible = item.clean
		warning.Visible = not item.clean
		if item.clean then
			factValues[1].Text = item.condition or "-"
			factValues[2].Text = "full price"
			factValues[3].Text = if type(item.perSecond) ~= "number"
				then "won't earn"
				elseif item.perSecond < 10 then string.format("$%.1f/s", item.perSecond)
				else `{money(item.perSecond)}/s`
		else
			local percent = math.floor(Tuning.DIRTY_SELL_MULTIPLIER * 100 + 0.5)
			local times = math.floor(1 / Tuning.DIRTY_SELL_MULTIPLIER + 0.5)
			warning.Text = if item.blockedBy ~= nil and item.needs
				then `This crust is tougher than your hose: it will wash, slowly, or fast with {item.needs}. Sell it blind for {percent}% and find out what it was.`
				else `Still crusted. Sell it blind for {percent}% and find out what it was, or wash it at the tub for {times}x this.`
		end

		sell.Text = `SELL {money(item.value or 0)}`
		paintArt(detailViewport, item, DETAIL_ART_W / DETAIL_ART_H)
	end

	local function paintFootButton(button: TextButton, label: string, count: number, total: number)
		local live = count > 0
		button.Active = live
		button.Text = if live then `{label}  ·  {money(total)}` else label
		button.TextColor3 = if live then SKIN.text else SKIN.muted
		button.BackgroundTransparency = if live then 0 else 0.5
	end

	paint = function(state: any)
		lastState = state
		local items = state.items or {}

		local stillThere = false
		for _, item in items do
			if item.uid == selected then
				stillThere = true
				break
			end
		end
		if not stillThere then
			selected = if #items > 0 then items[1].uid else nil
		end

		local capacity = if type(state.capacity) == "number" then state.capacity else #items
		local slots = math.max(capacity, #items)
		local chosen = nil
		for index = 1, slots do
			local item = items[index]
			paintTile(tileAt(index), item, item ~= nil and item.uid == selected)
			if item and item.uid == selected then
				chosen = item
			end
		end
		for index = slots + 1, #tiles do
			tiles[index].Visible = false
			clearArt((tiles[index]:FindFirstChild("Art") :: Frame):FindFirstChild("Model") :: ViewportFrame)
		end

		paintDetail(chosen)

		local cleanCount, cleanTotal, dirtyCount, dirtyTotal = 0, 0, 0, 0
		for _, item in items do
			if item.clean then
				cleanCount += 1
				cleanTotal += item.value or 0
			else
				dirtyCount += 1
				dirtyTotal += item.value or 0
			end
		end
		paintFootButton(sellClean, "Sell all clean", cleanCount, cleanTotal)
		paintFootButton(sellDirty, "Sell all ???", dirtyCount, dirtyTotal)

		wallet.Text = money(state.cash or 0)
		subtitle.Text = `Buyback counter  ·  {#items}/{capacity} in bag`
	end

	sell.MouseButton1Click:Connect(function()
		if selected and sellCallback then
			sellCallback(selected)
		end
	end)
	sellClean.MouseButton1Click:Connect(function()
		if sellClean.Active and sellAllCallback then
			sellAllCallback("clean")
		end
	end)
	sellDirty.MouseButton1Click:Connect(function()
		if sellDirty.Active and sellAllCallback then
			sellAllCallback("dirty")
		end
	end)

	return {
		frame = root,
		paint = function(state: any)
			paint(state)
		end,
		onSell = function(callback: (uid: string) -> ())
			sellCallback = callback
		end,
		onSellAll = function(callback: (which: string) -> ())
			sellAllCallback = callback
		end,
	}
end

return TraderPanel
