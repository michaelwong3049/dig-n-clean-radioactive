--[[
	IndexController.lua — the item index. Browse every nuke that can be found, stage by
	stage, and see which ones you have identified and the heaviest of each.

	THE DOSSIER LAYOUT (picked from five mockups). Three columns under one header:

	  RAIL    one row per stage: its found/total, a progress bar, and the stage's luck
	          reward once every nuke in it is identified (Tuning.INDEX_COMPLETE_LUCK,
	          applied server-side in DigService's rollFor).
	  GRID    the stage's nukes as cards, each a live render of the real model. A nuke
	          you have not identified is the same render blacked out: a silhouette, so
	          you know the shape you are hunting and nothing else. Filter chips above it:
	          All / Missing / Heaviest first, and one per rarity with its found count.
	  DETAIL  the selected nuke, turning slowly (drag to spin it), with its HEAVIEST
	          FOUND block front and centre: the record in kg, the payload roll that set
	          it, and a meter from the lightest to the heaviest that nuke can come out.
	          Under it value, find odds, times found and the date of the first one.

	The header carries the overall count and the HEAVIEST HAUL, your single heaviest
	record across the whole catalogue.

	THE RECORDS ARE THE SERVER'S (IdentifyService, `data.indexStats`, one
	Shared/IndexProgress.Entry per item). This file only ever reads them: one snapshot
	on load (IndexState) and the item's fresh record riding on every ItemIdentified /
	sealed Unearthed after that. The one thing it sends back is IndexSeen, when you open
	an entry still wearing its NEW badge.

	IT IS STILL WRITTEN WHEN YOU LEARN WHAT SOMETHING IS, NOT WHEN YOU DIG IT UP. An
	item comes out of the ground encased in slag and is "???" everywhere until it is
	cleaned (Services/IdentifyService); a catalogue that lit its card at the moment of the
	dig would be answering the question the wash bay is there to ask. Unidentified cards
	say nothing about rarity or odds for the same reason.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Weight = require(Shared.Config.Weight)
local Payload = require(Shared.Config.Payload)
local Tuning = require(Shared.Config.Tuning)
local IndexProgress = require(Shared.IndexProgress)
local ItemModels = require(Shared.ItemModels)
local ItemFx = require(Shared.ItemFx)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)

local Index = {}

-- THE INDEX TILE heads the right-edge 2x2 grid (top left; Shop, Nukes and Warp fill
-- the rest), built by HudTile in the grid's shared "glow orb" look: a violet glow for
-- the collection book. The grid's top is level with the top of the cash/meter column
-- on the left, or the whole grid is centred on a screen too short for that line
-- (Dock.sideColumnTop). Its own ScreenGui (IgnoreGuiInset = true), so those offsets
-- measure against the true screen as the left column's do; the detail panel keeps the
-- inset-aware gui it needs (see build()).
local TILE_SLOT = 1
local TILE_COLOR = Color3.fromRGB(164, 107, 255)
local TILE_LIGHT = Color3.fromRGB(212, 182, 255)

-- ── Panel geometry (design px, UIKit.canvas) ────────────────────────
-- "Viewport minus a margin, but never bigger than" like StationController's panel, so
-- it shrinks on a phone. The rail and the detail column are fixed widths (their text
-- wants a stable measure); the grid takes what is left and reflows its columns.
-- PANEL_MIN.X is rail + detail + two cards + the gaps and padding.
local SCREEN_MARGIN = 36
local PANEL_MAX = Vector2.new(1140, 640)
local PANEL_MIN = Vector2.new(780, 420)
local PAD = 18
local HEADER_H = 50
local BODY_TOP = HEADER_H + 14
local RAIL_W = 186
local DETAIL_W = 300
local GAP = 14
local FILTER_H = 30
local CARD_W = 100
local CARD_H = 128
local CARD_GAP = 8
local CARD_ART = 84
local STAGE_ROW_H = 62
local ART_H = 150
local HEAVY_H = 108
local STAT_H = 44

local COL = {
	well = Color3.fromHex("10150D"),
	card = Color3.fromHex("12170F"),
	cardEmpty = Color3.fromHex("0E120C"),
	edge = Color3.fromHex("263020"),
	rail = Color3.fromHex("151A12"),
	railOn = Color3.fromHex("1F2819"),
	railEdge = Color3.fromHex("232B1E"),
	railEdgeOn = Color3.fromHex("4B5C3D"),
	chip = Color3.fromHex("171D14"),
	chipOn = Color3.fromHex("2C3A22"),
	chipEdgeOn = Color3.fromHex("5B7A44"),
	cell = Color3.fromHex("161C12"),
	cellEdge = Color3.fromHex("222B1C"),
	record = Color3.fromHex("221B0C"),
	recordEdge = Color3.fromHex("5D4718"),
	gold = Color3.fromHex("F5C24B"),
	sand = Color3.fromHex("B6A57C"),
	newTag = Color3.fromHex("EF4444"),
	track = Color3.fromHex("0A0D09"),
	meterLow = Color3.fromHex("4A4B36"),
	silhouette = Color3.fromRGB(8, 10, 8),
	black = Color3.new(0, 0, 0),
	white = Color3.new(1, 1, 1),
}

-- The nuke renders. Lit like the shop card's art well (StationController's ART_LIGHT):
-- the ViewportFrame's default grey ambient washes every model to the same pale grey.
local ART_LIGHT = {
	ambient = Color3.fromRGB(90, 92, 98),
	color = Color3.fromRGB(255, 248, 235),
	direction = Vector3.new(-1, -1, -1),
}
local ART_FOV = 30
local ART_MARGIN = 1.1
-- Cards look from the front, a little right and above; the detail turns the model
-- under a camera a little above it.
local CARD_VIEW = Vector3.new(0.45, 0.3, 1).Unit
local DETAIL_RISE = 0.28
local SPIN_RATE = 0.6 -- rad/s while nobody is dragging
local DRAG_RATE = 0.012 -- rad per screen px

-- The filter chips. A rarity chip is `rarity:<name>` and shows only the IDENTIFIED
-- nukes of that rarity: an unidentified card never says what rarity it is.
local MODES = {
	{ id = "all", label = "All" },
	{ id = "missing", label = "Missing" },
	{ id = "heavy", label = "Heaviest first" },
}

-- ── State ───────────────────────────────────────────────────────────

local discovered: { [string]: boolean } = {}
local stats: { [string]: IndexProgress.Entry } = {}
local currentStage = Stages.DEFS[1].id
local mode = "all"
local selectedId: string? = nil
local dirty = true

local seenRemote: RemoteEvent? = nil

local ui: any = {}
type CardRefs = { stroke: UIStroke, edgeColor: Color3, newTag: Frame }
local cards: { [string]: CardRefs } = {}

-- Not #Items.DEFS: a retired item (`stages = {}`) stays in the catalogue so old saves
-- can resolve it, but can never be dug again, so it would sit in this count as
-- permanently unreachable.
local totalItems = 0
for _, item in Items.DEFS do
	if #item.stages > 0 then
		totalItems += 1
	end
end

-- The spinning detail model.
local spin = {
	model = nil :: Model?,
	key = nil :: string?,
	base = CFrame.identity,
	center = Vector3.zero,
	yaw = 0,
	dragging = false,
	lastX = 0,
}

-- ── Helpers ─────────────────────────────────────────────────────────

--- "$340", "$5.2K", "$1.4M" — the compact convention CashController.formatCash uses on
--- the cash badge.
local function formatValue(n: number): string
	if n >= 1_000_000 then
		return string.format("$%.1fM", n / 1_000_000)
	elseif n >= 1_000 then
		return string.format("$%.1fK", n / 1_000)
	end
	return string.format("$%d", n)
end

local function stageColor(stage: any): Color3
	-- Lifted toward white: Stage 4's dead-brown floor is near-black on this panel.
	return Color3.fromHex(stage.color):Lerp(COL.white, 0.25)
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function box(parent: Instance, name: string, size: UDim2, position: UDim2?, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position or UDim2.new()
	f.BorderSizePixel = 0
	if color then
		f.BackgroundColor3 = color
	else
		f.BackgroundTransparency = 1
	end
	f.Parent = parent
	return f
end

--- A plain label: no outline or drop shadow unless asked. UIKit.label's shadow is a
--- SIBLING label, which a UIListLayout would lay out as an extra row.
local function text(parent: Instance, props: any): TextLabel
	if props.outline == nil then
		props.outline = false
	end
	if props.shadow == nil then
		props.shadow = false
	end
	return UIKit.label(parent, props)
end

local function listLayout(parent: Instance, direction: Enum.FillDirection, padding: number): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, padding)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.Parent = parent
	return l
end

local function clearChildren(parent: Instance, keep: { [string]: boolean }?)
	for _, child in parent:GetChildren() do
		if not (keep and keep[child.ClassName]) then
			child:Destroy()
		end
	end
end

--- A vertical fade of `color`, for the rarity glow behind a model.
local function glow(parent: GuiObject, color: Color3, top: number, radius: number)
	local g = box(parent, "Glow", UDim2.fromScale(1, 1), nil, color)
	corner(g, radius)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, top),
		NumberSequenceKeypoint.new(0.7, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = g
	return g
end

local function recordKg(itemId: string): number?
	return IndexProgress.bestKg(itemId, stats[itemId])
end

local function newCount(): number
	local n = 0
	for itemId, entry in stats do
		if entry.new and discovered[itemId] then
			n += 1
		end
	end
	return n
end

local function foundCount(): number
	local n = 0
	for itemId in discovered do
		if Items.has(itemId) and #Items.get(itemId).stages > 0 then
			n += 1
		end
	end
	return n
end

--- The heaviest record in the catalogue: (itemId, kg), or nil before there is one.
local function heaviestHaul(): (string?, number)
	local bestId, bestKg = nil, 0
	for itemId in stats do
		if discovered[itemId] and Items.has(itemId) then
			local kg = recordKg(itemId)
			if kg and kg > bestKg then
				bestId, bestKg = itemId, kg
			end
		end
	end
	return bestId, bestKg
end

-- ── The models ──────────────────────────────────────────────────────

--- A fresh copy of an item's model, stood up the way the model yard stands it, or the
--- rarity-coloured block every other display falls back to for an item with no art.
--- The ItemFx tag comes off: ItemFxController would otherwise hang lights and particles
--- on a model that lives in a ViewportFrame, where none of them render.
local function itemModel(itemId: string): Model
	local def = Items.get(itemId)
	local model = ItemModels.create(def.model, itemId)
	if model == nil then
		local block = Instance.new("Part")
		block.Name = "Placeholder"
		block.Size = Vector3.one
		block.Color = Rarity.get(def.rarity).color
		block.Material = Enum.Material.SmoothPlastic
		model = Instance.new("Model")
		block.Parent = model
		model.PrimaryPart = block
	end
	CollectionService:RemoveTag(model, ItemFx.TAG)
	model:PivotTo(ItemModels.rotation(model, "Gallery"))
	return model
end

local function newViewport(parent: Instance, name: string): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = name
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

local BOX_CORNERS = {}
for _, x in { -1, 1 } do
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(BOX_CORNERS, Vector3.new(x, y, z))
		end
	end
end

--- Aim a still camera so `model` fills a well `aspect` wide per unit tall. The box is
--- measured in the camera's own axes, same as the shop card's frameArt, so a
--- three-quarter view is framed tight rather than to the model's loose aligned box.
local function frameStill(camera: Camera, model: Model, aspect: number)
	local look = CFrame.lookAt(Vector3.zero, -CARD_VIEW, Vector3.yAxis)
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

--- Aim the detail camera for a model that TURNS about its vertical axis: fit the
--- widest it gets (the horizontal diagonal) as well as its height, so no angle of the
--- spin pokes out of the well.
local function frameSpin(camera: Camera, model: Model, aspect: number): Vector3
	local bounds, size = model:GetBoundingBox()
	local center = bounds.Position
	local across = math.sqrt(size.X * size.X + size.Z * size.Z) / 2
	local tanHalf = math.tan(math.rad(ART_FOV) / 2)
	local distance = math.max(size.Y / 2 / tanHalf, across / (tanHalf * aspect)) * ART_MARGIN + across
	local direction = Vector3.new(0, DETAIL_RISE, 1).Unit
	camera.CFrame = CFrame.lookAt(center + direction * distance, center)
	return center
end

-- ── Build: the tile ─────────────────────────────────────────────────

local function buildButton(): ScreenGui
	local buttonGui, button = HudTile.build({
		name = "IndexButton",
		caption = "Index",
		slot = TILE_SLOT,
		color = TILE_COLOR,
		light = TILE_LIGHT,
		image = Artwork.IMAGE.book,
	})
	-- NEW entries waiting to be looked at: a red count on the tile's corner.
	local badge, badgeText = HudTile.badge(button, COL.newTag, COL.black)

	ui.button = button
	ui.badge = badge
	ui.badgeText = badgeText
	return buttonGui
end

-- ── Build: the panel ────────────────────────────────────────────────

local function buildHeader(panel: Frame)
	local header = box(panel, "Header", UDim2.new(1, 0, 0, HEADER_H))

	UIKit.label(header, {
		name = "Title",
		size = UDim2.fromOffset(200, HEADER_H),
		font = UIKit.Font.hero,
		textSize = 30,
		color = COL.white,
		text = "THE INDEX",
	})

	local bar = box(header, "Progress", UDim2.fromOffset(170, 12), UDim2.new(0, 206, 0.5, 0), COL.track)
	bar.AnchorPoint = Vector2.new(0, 0.5)
	corner(bar, 6)
	edge(bar, COL.black, 2)
	local fill = box(bar, "Fill", UDim2.fromScale(0, 1), nil, UIKit.C.green)
	corner(fill, 6)
	ui.progressFill = fill
	ui.progressText = text(header, {
		name = "Count",
		position = UDim2.fromOffset(388, 0),
		size = UDim2.fromOffset(150, HEADER_H),
		font = UIKit.Font.title,
		textSize = 13,
		color = UIKit.C.dim,
	})

	-- THE HEAVIEST HAUL: the single heaviest record anywhere in the catalogue.
	local record = box(header, "HeaviestHaul", UDim2.fromOffset(0, 44), UDim2.new(1, -48, 0.5, 0), COL.record)
	record.AnchorPoint = Vector2.new(1, 0.5)
	record.AutomaticSize = Enum.AutomaticSize.X
	record.Visible = false
	corner(record, 12)
	edge(record, COL.recordEdge, 2)
	local recordPad = Instance.new("UIPadding")
	recordPad.PaddingLeft = UDim.new(0, 6)
	recordPad.PaddingRight = UDim.new(0, 14)
	recordPad.Parent = record
	listLayout(record, Enum.FillDirection.Horizontal, 8)

	local recordArt = box(record, "Art", UDim2.fromOffset(36, 36))
	recordArt.LayoutOrder = 1
	local recordWords = box(record, "Words", UDim2.fromOffset(0, 36))
	recordWords.AutomaticSize = Enum.AutomaticSize.X
	recordWords.LayoutOrder = 2
	text(recordWords, {
		name = "Caption",
		size = UDim2.fromOffset(160, 14),
		font = Enum.Font.GothamBlack,
		textSize = 11,
		color = UIKit.C.amber,
		text = "HEAVIEST HAUL",
	})
	local recordValue = text(recordWords, {
		name = "Value",
		position = UDim2.fromOffset(0, 15),
		size = UDim2.fromOffset(0, 20),
		font = UIKit.Font.title,
		textSize = 15,
		color = COL.white,
	})
	recordValue.AutomaticSize = Enum.AutomaticSize.X
	recordValue.RichText = true
	ui.record = record
	ui.recordArt = recordArt
	ui.recordValue = recordValue

	local close = UIKit.button(header, {
		name = "Close",
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.fromScale(1, 0.5),
		size = UDim2.fromOffset(36, 36),
		text = "X",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.text,
		fillColor = UIKit.C.empty,
		fillTransparency = 0,
		strokeColor = UIKit.C.stroke,
		strokeThickness = 2,
		cornerRadius = UDim.new(0, 9),
		outline = false,
		shadow = false,
	})
	ui.close = close
end

local function buildRail(panel: Frame)
	local rail = box(panel, "Rail", UDim2.new(0, RAIL_W, 1, -BODY_TOP), UDim2.fromOffset(0, BODY_TOP))
	listLayout(rail, Enum.FillDirection.Vertical, 7).VerticalAlignment = Enum.VerticalAlignment.Top

	ui.railRows = {}
	for order, stage in Stages.DEFS do
		local tint = stageColor(stage)
		local row = Instance.new("TextButton")
		row.Name = `Stage{stage.id}`
		row.AutoButtonColor = false
		row.Text = ""
		row.Size = UDim2.new(1, 0, 0, STAGE_ROW_H)
		row.BackgroundColor3 = COL.rail
		row.BorderSizePixel = 0
		row.ClipsDescendants = true
		row.LayoutOrder = order
		row.Parent = rail
		corner(row, 11)
		local stroke = edge(row, COL.railEdge, 2)

		box(row, "Stripe", UDim2.new(0, 6, 1, 0), nil, tint)
		text(row, {
			name = "StageName",
			position = UDim2.fromOffset(16, 7),
			size = UDim2.new(1, -24, 0, 16),
			font = UIKit.Font.title,
			textSize = 13,
			color = UIKit.C.text,
			text = stage.name,
		})
		local count = text(row, {
			name = "Count",
			position = UDim2.fromOffset(16, 25),
			size = UDim2.new(0.5, -16, 0, 14),
			font = UIKit.Font.title,
			textSize = 11,
			color = UIKit.C.dim,
		})
		local right = text(row, {
			name = "Right",
			anchorPoint = Vector2.new(1, 0),
			position = UDim2.new(1, -10, 0, 25),
			size = UDim2.new(0.6, 0, 0, 14),
			font = UIKit.Font.title,
			textSize = 11,
			color = UIKit.C.dim,
			xAlign = Enum.TextXAlignment.Right,
		})
		local track = box(row, "Track", UDim2.new(1, -26, 0, 6), UDim2.fromOffset(16, 45), COL.track)
		corner(track, 3)
		local fill = box(track, "Fill", UDim2.fromScale(0, 1), nil, tint)
		corner(fill, 3)

		row.MouseButton1Click:Connect(function()
			Index.showStage(stage.id)
		end)
		ui.railRows[stage.id] = { row = row, stroke = stroke, count = count, right = right, fill = fill, tint = tint }
	end

	local hint = text(rail, {
		name = "Reward",
		size = UDim2.new(1, 0, 0, 30),
		font = UIKit.Font.body,
		textSize = 11,
		color = UIKit.C.dim,
		wrapped = true,
		text = string.format("Identify every nuke in a stage for +%.2f dig luck there.", Tuning.INDEX_COMPLETE_LUCK),
	})
	hint.LayoutOrder = #Stages.DEFS + 1
end

local function buildMiddle(panel: Frame)
	local left = RAIL_W + GAP
	local width = RAIL_W + DETAIL_W + 2 * GAP
	local mid = box(panel, "Middle", UDim2.new(1, -width, 1, -BODY_TOP), UDim2.fromOffset(left, BODY_TOP))

	local filters = Instance.new("ScrollingFrame")
	filters.Name = "Filters"
	filters.Size = UDim2.new(1, 0, 0, FILTER_H)
	filters.BackgroundTransparency = 1
	filters.BorderSizePixel = 0
	filters.ScrollingDirection = Enum.ScrollingDirection.X
	filters.ScrollBarThickness = 0
	filters.CanvasSize = UDim2.new()
	filters.AutomaticCanvasSize = Enum.AutomaticSize.X
	filters.Parent = mid
	ui.filters = filters

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Position = UDim2.fromOffset(0, FILTER_H + 10)
	grid.Size = UDim2.new(1, 0, 1, -(FILTER_H + 10))
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = UIKit.C.dim
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = mid
	ui.grid = grid

	local gridPad = Instance.new("UIPadding")
	gridPad.PaddingTop = UDim.new(0, 3)
	gridPad.PaddingLeft = UDim.new(0, 3)
	gridPad.PaddingRight = UDim.new(0, 12)
	gridPad.Parent = grid

	local empty = text(mid, {
		name = "Empty",
		position = UDim2.fromOffset(0, FILTER_H + 30),
		size = UDim2.new(1, 0, 0, 40),
		font = UIKit.Font.body,
		textSize = 14,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		visible = false,
	})
	ui.gridEmpty = empty
end

--- One CAPTION / value cell of the detail's 2x2 stat block.
local function statCell(parent: Instance, order: number, caption: string): TextLabel
	local cell = box(parent, caption, UDim2.new(), nil, COL.cell)
	cell.LayoutOrder = order
	corner(cell, 10)
	edge(cell, COL.cellEdge, 2)
	text(cell, {
		name = "Caption",
		position = UDim2.fromOffset(9, 6),
		size = UDim2.new(1, -18, 0, 12),
		font = Enum.Font.GothamBlack,
		textSize = 10,
		color = UIKit.C.dim,
		text = caption,
	})
	return text(cell, {
		name = "Value",
		position = UDim2.fromOffset(9, 20),
		size = UDim2.new(1, -18, 0, 18),
		font = UIKit.Font.title,
		textSize = 15,
		color = UIKit.C.text,
	})
end

local function buildDetail(panel: Frame)
	local detail = Instance.new("ScrollingFrame")
	detail.Name = "Detail"
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, 0, 0, BODY_TOP)
	detail.Size = UDim2.new(0, DETAIL_W, 1, -BODY_TOP)
	detail.BackgroundColor3 = COL.well
	detail.BorderSizePixel = 0
	detail.ScrollingDirection = Enum.ScrollingDirection.Y
	detail.ScrollBarThickness = 4
	detail.ScrollBarImageColor3 = UIKit.C.dim
	detail.CanvasSize = UDim2.new()
	detail.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detail.Parent = panel
	corner(detail, 14)
	edge(detail, COL.edge, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = detail
	listLayout(detail, Enum.FillDirection.Vertical, 10).VerticalAlignment = Enum.VerticalAlignment.Top

	-- The art well: the model turning under the rarity's glow. A TextButton only so it
	-- takes the press that starts a drag.
	local art = Instance.new("TextButton")
	art.Name = "Art"
	art.AutoButtonColor = false
	art.Text = ""
	art.Size = UDim2.new(1, 0, 0, ART_H)
	art.BackgroundColor3 = Color3.fromHex("0C100A")
	art.BorderSizePixel = 0
	art.ClipsDescendants = true
	art.LayoutOrder = 1
	art.Parent = detail
	corner(art, 12)
	edge(art, COL.black, 2)
	local artGlow = glow(art, COL.white, 0.6, 12)
	local viewport = newViewport(art, "Model")
	text(art, {
		name = "DragHint",
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -8, 1, -4),
		size = UDim2.fromOffset(120, 14),
		font = UIKit.Font.body,
		textSize = 10,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Right,
		text = "drag to spin",
	})
	art.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			spin.dragging = true
			spin.lastX = input.Position.X
		end
	end)

	local name = text(detail, {
		name = "ItemName",
		size = UDim2.fromScale(1, 0),
		font = UIKit.Font.hero,
		textSize = 22,
		color = UIKit.C.text,
		wrapped = true,
		outline = true,
	})
	name.AutomaticSize = Enum.AutomaticSize.Y
	name.LayoutOrder = 2

	local pills = box(detail, "Pills", UDim2.new(1, 0, 0, 22))
	pills.LayoutOrder = 3
	listLayout(pills, Enum.FillDirection.Horizontal, 6)

	-- HEAVIEST FOUND: the record, the roll that set it, and where that roll sits
	-- between the lightest and heaviest this nuke can come out of the ground.
	local heavy = box(detail, "Heaviest", UDim2.new(1, 0, 0, HEAVY_H), nil, COL.record)
	heavy.LayoutOrder = 4
	corner(heavy, 12)
	edge(heavy, COL.recordEdge, 2)
	text(heavy, {
		name = "Caption",
		position = UDim2.fromOffset(12, 8),
		size = UDim2.new(1, -24, 0, 12),
		font = Enum.Font.GothamBlack,
		textSize = 11,
		color = UIKit.C.amber,
		text = "HEAVIEST FOUND",
	})
	local roll = text(heavy, {
		name = "Roll",
		position = UDim2.fromOffset(12, 8),
		size = UDim2.new(1, -24, 0, 12),
		font = UIKit.Font.title,
		textSize = 11,
		color = COL.sand,
		xAlign = Enum.TextXAlignment.Right,
	})
	local bigRow = box(heavy, "BigRow", UDim2.new(1, -24, 0, 36), UDim2.fromOffset(12, 24))
	listLayout(bigRow, Enum.FillDirection.Horizontal, 10)
	local big = text(bigRow, {
		name = "Kg",
		size = UDim2.fromOffset(0, 36),
		font = UIKit.Font.hero,
		textSize = 28,
		color = COL.white,
		outline = true,
	})
	big.AutomaticSize = Enum.AutomaticSize.X
	big.LayoutOrder = 1
	local sticker = box(bigRow, "Sticker", UDim2.fromOffset(0, 22), nil, UIKit.C.amber)
	sticker.AutomaticSize = Enum.AutomaticSize.X
	sticker.LayoutOrder = 2
	sticker.Rotation = -4
	corner(sticker, 6)
	edge(sticker, COL.black, 2)
	local stickerGrad = Instance.new("UIGradient")
	stickerGrad.Parent = sticker
	local stickerPad = Instance.new("UIPadding")
	stickerPad.PaddingLeft = UDim.new(0, 7)
	stickerPad.PaddingRight = UDim.new(0, 7)
	stickerPad.Parent = sticker
	local stickerText = text(sticker, {
		name = "Text",
		size = UDim2.fromScale(0, 1),
		font = Enum.Font.GothamBlack,
		textSize = 12,
		color = Color3.fromHex("111111"),
	})
	stickerText.AutomaticSize = Enum.AutomaticSize.X

	local meter = box(heavy, "Meter", UDim2.new(1, -24, 0, 12), UDim2.fromOffset(12, 68), COL.track)
	corner(meter, 6)
	edge(meter, COL.black, 2)
	local span = Payload.MAX - Payload.MIN
	local function frac(mult: number): number
		return math.clamp((mult - Payload.MIN) / span, 0, 1)
	end
	-- Zones from Payload.CALLOUTS, lowest first: plain, then OVERSIZED, then GIGA.
	local thresholds = {}
	for _, tier in Payload.CALLOUTS do
		table.insert(thresholds, tier.min)
	end
	table.sort(thresholds)
	local zoneColors = { COL.meterLow, UIKit.C.amber, COL.white }
	local from = 0
	for i = 1, #thresholds + 1 do
		local to = if thresholds[i] then frac(thresholds[i]) else 1
		local zone = box(meter, `Zone{i}`, UDim2.fromScale(to - from, 1), UDim2.fromScale(from, 0), zoneColors[i] or COL.white)
		if i == #thresholds + 1 then
			local rainbow = Instance.new("UIGradient")
			rainbow.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHex("FF4FD8")),
				ColorSequenceKeypoint.new(0.5, Color3.fromHex("FFD84F")),
				ColorSequenceKeypoint.new(1, Color3.fromHex("4FFFE0")),
			})
			rainbow.Parent = zone
		end
		if thresholds[i] then
			box(meter, `Tick{i}`, UDim2.new(0, 2, 1, 4), UDim2.new(to, -1, 0, -2), COL.black)
		end
		from = to
	end
	local marker = box(meter, "Marker", UDim2.fromOffset(5, 20), UDim2.fromScale(0, 0.5), COL.white)
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.ZIndex = 3
	corner(marker, 2)
	edge(marker, COL.black, 1.5)

	local range = box(heavy, "Range", UDim2.new(1, -24, 0, 14), UDim2.fromOffset(12, 86))
	local rangeLabels = {}
	for i, align in { Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right } do
		rangeLabels[i] = text(range, {
			name = `Range{i}`,
			size = UDim2.fromScale(1, 1),
			font = UIKit.Font.title,
			textSize = 10,
			color = COL.sand,
			xAlign = align,
		})
	end

	local statsGrid = box(detail, "Stats", UDim2.new(1, 0, 0, 2 * STAT_H + 6))
	statsGrid.LayoutOrder = 5
	local statsLayout = Instance.new("UIGridLayout")
	statsLayout.CellSize = UDim2.new(0.5, -3, 0, STAT_H)
	statsLayout.CellPadding = UDim2.fromOffset(6, 6)
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = statsGrid

	local flavor = text(detail, {
		name = "Flavor",
		size = UDim2.fromScale(1, 0),
		font = UIKit.Font.body,
		textSize = 12,
		color = Color3.fromHex("95A08D"),
		wrapped = true,
	})
	flavor.AutomaticSize = Enum.AutomaticSize.Y
	flavor.LayoutOrder = 6

	-- What an unidentified entry says: nothing but how to change that.
	local unknown = text(detail, {
		name = "Unknown",
		size = UDim2.fromScale(1, 0),
		font = UIKit.Font.body,
		textSize = 13,
		color = UIKit.C.dim,
		wrapped = true,
		text = "Not identified yet. Wash one clean, or sell one blind, to learn what it is.",
	})
	unknown.AutomaticSize = Enum.AutomaticSize.Y
	unknown.LayoutOrder = 3

	ui.detail = {
		frame = detail,
		art = art,
		artGlow = artGlow,
		viewport = viewport,
		name = name,
		pills = pills,
		heavy = heavy,
		roll = roll,
		big = big,
		sticker = sticker,
		stickerGrad = stickerGrad,
		stickerText = stickerText,
		marker = marker,
		frac = frac,
		range = rangeLabels,
		stats = statsGrid,
		value = statCell(statsGrid, 1, "VALUE"),
		odds = statCell(statsGrid, 2, "FIND ODDS"),
		count = statCell(statsGrid, 3, "TIMES FOUND"),
		first = statCell(statsGrid, 4, "FIRST FOUND"),
		flavor = flavor,
		unknown = unknown,
	}
end

local function build(): (ScreenGui, ScreenGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "IndexHud"
	gui.ResetOnSpawn = false
	-- FALSE, like StationController and for its reason: the panel is anchored to the
	-- screen CENTRE, and IgnoreGuiInset = true shifts a centred child up by half the
	-- topbar inset (it clipped ~18px off the panel's top on a short viewport). The INDEX
	-- button lives in its own gui precisely so it does NOT have to share this trade-off.
	gui.IgnoreGuiInset = false
	-- Over everything on the HUD (RadHud is 100): at this width the panel reaches the
	-- cash/meter column on the left and the hotbar along the bottom, and a modal the
	-- player opened should not have the meters drawn across its stage rail.
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local buttonGui = buildButton()

	-- Centred on screen, the call StationController's header describes settling on: a
	-- panel this size can't dodge the dock by biasing upward without clipping off the
	-- TOP of a short viewport.
	local canvas = UIKit.canvas(gui)
	local panel = UIKit.panel(canvas, {
		name = "Panel",
		size = UDim2.new(1, -2 * SCREEN_MARGIN, 1, -2 * SCREEN_MARGIN),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = UIKit.C.panel,
		-- Opaque: the hotbar sits under the panel's bottom edge and ghosted through.
		transparency = 0,
		cornerRadius = UDim.new(0, 18),
		strokeThickness = UIKit.Stroke.normal,
		zIndex = 10,
		visible = false,
	})
	ui.panel = panel

	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = PANEL_MIN
	panelSize.MaxSize = PANEL_MAX
	panelSize.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PAD - 4)
	padding.PaddingBottom = UDim.new(0, PAD)
	padding.PaddingLeft = UDim.new(0, PAD)
	padding.PaddingRight = UDim.new(0, PAD)
	padding.Parent = panel

	buildHeader(panel)
	buildRail(panel)
	buildMiddle(panel)
	buildDetail(panel)

	local function toggle()
		panel.Visible = not panel.Visible
		if panel.Visible and dirty then
			Index.render()
		end
	end
	ui.button.MouseButton1Click:Connect(toggle)
	ui.close.MouseButton1Click:Connect(toggle)

	return gui, buttonGui
end

-- ── Render ──────────────────────────────────────────────────────────

--- The current stage's nukes, filtered and sorted for the grid.
local function stageList(): { any }
	local list = {}
	for _, item in IndexProgress.stageItems(currentStage) do
		local found = discovered[item.id] == true
		local keep = true
		if mode == "missing" then
			keep = not found
		elseif string.sub(mode, 1, 7) == "rarity:" then
			keep = found and item.rarity == string.sub(mode, 8)
		end
		if keep then
			table.insert(list, item)
		end
	end

	local function byRarity(a, b): boolean
		local ra, rb = Rarity.DEFS[a.rarity].order, Rarity.DEFS[b.rarity].order
		if ra ~= rb then
			return ra < rb
		end
		if a.baseValue ~= b.baseValue then
			return a.baseValue < b.baseValue
		end
		return a.id < b.id
	end
	if mode == "heavy" then
		table.sort(list, function(a, b)
			local ka = if discovered[a.id] then recordKg(a.id) or 0 else -1
			local kb = if discovered[b.id] then recordKg(b.id) or 0 else -1
			if ka ~= kb then
				return ka > kb
			end
			return byRarity(a, b)
		end)
	else
		table.sort(list, byRarity)
	end
	return list
end

local function renderBadge()
	local n = newCount()
	ui.badge.Visible = n > 0
	ui.badgeText.Text = tostring(n)
end

local function renderHeader()
	local found = foundCount()
	ui.progressFill.Size = UDim2.fromScale(if totalItems > 0 then found / totalItems else 0, 1)
	ui.progressText.Text = `{found} / {totalItems} FOUND`

	local itemId, kg = heaviestHaul()
	ui.record.Visible = itemId ~= nil
	if itemId == nil then
		return
	end
	ui.recordValue.Text = `{Items.get(itemId).name} · <font color="#F5C24B">{UIKit.formatKg(kg)}</font>`
	if ui.recordArt:GetAttribute("ItemId") ~= itemId then
		ui.recordArt:SetAttribute("ItemId", itemId)
		clearChildren(ui.recordArt)
		local viewport = newViewport(ui.recordArt, "Model")
		local model = itemModel(itemId)
		model.Parent = viewport
		frameStill(viewport.CurrentCamera :: Camera, model, 1)
	end
end

local function renderRail()
	for _, stage in Stages.DEFS do
		local refs = ui.railRows[stage.id]
		local found, total = IndexProgress.stageCount(discovered, stage.id)
		local complete = total > 0 and found == total
		local on = stage.id == currentStage
		refs.row.BackgroundColor3 = if on then COL.railOn else COL.rail
		refs.stroke.Color = if complete then UIKit.C.green elseif on then COL.railEdgeOn else COL.railEdge
		refs.count.Text = `{found}/{total}`
		refs.fill.Size = UDim2.fromScale(if total > 0 then found / total else 0, 1)
		refs.fill.BackgroundColor3 = if complete then UIKit.C.green else refs.tint
		if complete then
			refs.right.Text = string.format("+%.2f LUCK", Tuning.INDEX_COMPLETE_LUCK)
			refs.right.TextColor3 = UIKit.C.green
		else
			refs.right.Text = `{if total > 0 then math.floor(found / total * 100) else 0}%`
			refs.right.TextColor3 = UIKit.C.dim
		end
	end
end

local function chip(order: number, id: string, label: string, dot: Color3?)
	local on = mode == id
	local button = Instance.new("TextButton")
	button.Name = `Chip_{id}`
	button.AutoButtonColor = false
	button.Text = ""
	button.Size = UDim2.fromOffset(0, FILTER_H - 4)
	button.AutomaticSize = Enum.AutomaticSize.X
	button.BackgroundColor3 = if on then COL.chipOn else COL.chip
	button.BorderSizePixel = 0
	button.LayoutOrder = order
	button.Parent = ui.filters
	corner(button, 13)
	edge(button, if on then COL.chipEdgeOn else UIKit.C.stroke, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 11)
	pad.PaddingRight = UDim.new(0, 11)
	pad.Parent = button
	listLayout(button, Enum.FillDirection.Horizontal, 5)
	if dot then
		local d = box(button, "Dot", UDim2.fromOffset(9, 9), nil, dot)
		d.LayoutOrder = 1
		corner(d, 5)
	end
	local words = text(button, {
		name = "Text",
		size = UDim2.fromOffset(0, FILTER_H - 4),
		font = UIKit.Font.title,
		textSize = 12,
		color = if on then COL.white else Color3.fromHex("B8C2B0"),
		text = label,
	})
	words.AutomaticSize = Enum.AutomaticSize.X
	words.LayoutOrder = 2
	button.MouseButton1Click:Connect(function()
		-- A second click on a rarity chip goes back to All.
		mode = if on and id ~= "all" then "all" else id
		Index.render()
	end)
end

local function renderFilters()
	clearChildren(ui.filters)
	listLayout(ui.filters, Enum.FillDirection.Horizontal, 6)
	for i, m in MODES do
		chip(i, m.id, m.label)
	end
	-- One chip per rarity this stage stocks: found/total, the colour as a dot.
	local counts: { [string]: { found: number, total: number } } = {}
	for _, item in IndexProgress.stageItems(currentStage) do
		local c = counts[item.rarity]
		if c == nil then
			c = { found = 0, total = 0 }
			counts[item.rarity] = c
		end
		c.total += 1
		if discovered[item.id] then
			c.found += 1
		end
	end
	for i, rarity in Rarity.ORDER do
		local c = counts[rarity]
		if c then
			chip(10 + i, `rarity:{rarity}`, `{c.found}/{c.total}`, Rarity.get(rarity).color)
		end
	end
end

local function paintCardSelection()
	for itemId, refs in cards do
		local on = itemId == selectedId
		refs.stroke.Color = if on then COL.white else refs.edgeColor
		refs.stroke.Thickness = if on then 3 else 2
		local entry = stats[itemId]
		refs.newTag.Visible = entry ~= nil and entry.new == true and discovered[itemId] == true
	end
end

local function buildCard(item: any, order: number)
	local found = discovered[item.id] == true
	local rarityColor = Rarity.get(item.rarity).color

	local card = Instance.new("TextButton")
	card.Name = `Card_{item.id}`
	card.AutoButtonColor = false
	card.Text = ""
	card.BackgroundColor3 = if found then COL.card else COL.cardEmpty
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Parent = ui.grid
	corner(card, 12)
	local edgeColor = if found then rarityColor:Lerp(COL.black, 0.3) else COL.edge
	local stroke = edge(card, edgeColor, 2)

	if found then
		glow(card, rarityColor, 0.72, 12)
	end

	local art = box(card, "Art", UDim2.fromOffset(CARD_ART, CARD_ART), UDim2.new(0.5, 0, 0, 4))
	art.AnchorPoint = Vector2.new(0.5, 0)
	local viewport = newViewport(art, "Model")
	if not found then
		-- THE SILHOUETTE: the real render, blacked out. The shape and nothing else.
		viewport.ImageColor3 = COL.silhouette
	end
	local model = itemModel(item.id)
	model.Parent = viewport
	frameStill(viewport.CurrentCamera :: Camera, model, 1)

	text(card, {
		name = "ItemName",
		position = UDim2.fromOffset(4, CARD_ART + 5),
		size = UDim2.new(1, -8, 0, 22),
		font = UIKit.Font.title,
		textSize = 11,
		color = if found then rarityColor else Color3.fromHex("4D5847"),
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = if found then item.name else "???",
	})

	local kg = if found then recordKg(item.id) else nil
	if kg then
		text(card, {
			name = "Best",
			anchorPoint = Vector2.new(0, 1),
			position = UDim2.new(0, 4, 1, -5),
			size = UDim2.new(1, -8, 0, 13),
			font = Enum.Font.GothamBlack,
			textSize = 11,
			color = COL.gold,
			xAlign = Enum.TextXAlignment.Center,
			text = `BEST {UIKit.formatKg(kg)}`,
		})
	end

	local newTag = box(card, "New", UDim2.fromOffset(30, 15), UDim2.new(1, -5, 0, 5), COL.newTag)
	newTag.AnchorPoint = Vector2.new(1, 0)
	newTag.ZIndex = 3
	corner(newTag, 5)
	edge(newTag, COL.black, 2)
	text(newTag, {
		name = "Text",
		size = UDim2.fromScale(1, 1),
		font = Enum.Font.GothamBlack,
		textSize = 9,
		color = COL.white,
		xAlign = Enum.TextXAlignment.Center,
		text = "NEW",
		zIndex = 4,
	})

	card.MouseButton1Click:Connect(function()
		Index.select(item.id)
	end)
	cards[item.id] = { stroke = stroke, edgeColor = edgeColor, newTag = newTag }
end

local function renderGrid(list: { any })
	clearChildren(ui.grid, { UIPadding = true })
	table.clear(cards)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	layout.CellPadding = UDim2.fromOffset(CARD_GAP, CARD_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = ui.grid

	for i, item in list do
		buildCard(item, i)
	end
	ui.grid.CanvasPosition = Vector2.zero

	ui.gridEmpty.Visible = #list == 0
	if mode == "missing" then
		ui.gridEmpty.Text = "Nothing missing here. Every nuke in this stage is identified."
	else
		ui.gridEmpty.Text = "Nothing identified here yet."
	end
	paintCardSelection()
end

local function pill(order: number, label: string, fill: Color3, ink: Color3, border: Color3)
	local p = box(ui.detail.pills, `Pill{order}`, UDim2.fromOffset(0, 22), nil, fill)
	p.AutomaticSize = Enum.AutomaticSize.X
	p.LayoutOrder = order
	corner(p, 11)
	edge(p, border, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 9)
	pad.PaddingRight = UDim.new(0, 9)
	pad.Parent = p
	local t = text(p, {
		name = "Text",
		size = UDim2.fromScale(0, 1),
		font = UIKit.Font.title,
		textSize = 11,
		color = ink,
		text = label,
	})
	t.AutomaticSize = Enum.AutomaticSize.X
end

local function setSpinModel(itemId: string?, found: boolean)
	local d = ui.detail
	local key = if itemId then `{itemId}/{found}` else nil
	if spin.key == key then
		return
	end
	spin.key = key
	if spin.model then
		spin.model:Destroy()
		spin.model = nil
	end
	d.viewport.ImageColor3 = if found then COL.white else COL.silhouette
	if itemId == nil then
		return
	end
	local model = itemModel(itemId)
	model.Parent = d.viewport
	spin.base = model:GetPivot()
	spin.center = frameSpin(d.viewport.CurrentCamera :: Camera, model, (DETAIL_W - 24) / ART_H)
	spin.yaw = 0
	spin.model = model
end

local function renderDetail()
	local d = ui.detail
	local item = if selectedId then Items.get(selectedId) else nil
	local found = item ~= nil and discovered[item.id] == true
	setSpinModel(if item then item.id else nil, found)
	d.frame.Visible = item ~= nil
	if item == nil then
		return
	end

	local rarityColor = Rarity.get(item.rarity).color
	d.artGlow.BackgroundColor3 = if found then rarityColor else COL.edge
	d.name.Text = if found then item.name else "UNKNOWN"
	d.name.TextColor3 = if found then rarityColor else COL.white

	d.pills.Visible = found
	d.heavy.Visible = found
	d.stats.Visible = found
	d.flavor.Visible = found
	d.unknown.Visible = not found
	if not found then
		return
	end

	for _, child in d.pills:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	pill(1, string.upper(item.rarity), rarityColor:Lerp(COL.black, 0.8), rarityColor, rarityColor)
	for i, stageId in item.stages do
		local stage = Stages.get(stageId)
		pill(1 + i, stage.name, Color3.fromHex("0C0F0A"), Color3.fromHex("E8DCCB"), stageColor(stage))
	end

	local entry = stats[item.id]
	local kg = recordKg(item.id)
	if kg and entry then
		d.big.Text = UIKit.formatKg(kg)
		d.roll.Text = string.format("%.2f\u{00D7} payload", entry.best)
		d.marker.Visible = true
		d.marker.Position = UDim2.fromScale(d.frac(entry.best), 0.5)
		local callout = Payload.calloutFor(entry.best)
		d.sticker.Visible = callout ~= nil
		if callout then
			d.stickerText.Text = callout
			local giga = callout == Payload.CALLOUTS[1].label
			d.sticker.BackgroundColor3 = if giga then COL.white else UIKit.C.amber
			d.stickerGrad.Enabled = giga
			d.stickerGrad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromHex("FF4FD8")),
				ColorSequenceKeypoint.new(0.5, Color3.fromHex("FFD84F")),
				ColorSequenceKeypoint.new(1, Color3.fromHex("4FFFE0")),
			})
		end
	else
		-- Found before records were kept, and no copy left to measure.
		d.big.Text = "—"
		d.roll.Text = "identify another to record it"
		d.marker.Visible = false
		d.sticker.Visible = false
	end
	d.range[1].Text = UIKit.formatKg(item.weight * Payload.MIN)
	d.range[2].Text = `usual {UIKit.formatKg(item.weight)}`
	d.range[3].Text = UIKit.formatKg(item.weight * Payload.MAX)

	-- Value carries the item's weight (Config/Weight): the sale floor is baseValue *
	-- valueMult. The odds are what the roll actually does (odds / rollBias).
	d.value.Text = formatValue(math.floor(item.baseValue * Weight.valueMult(item.weight) + 0.5))
	d.odds.Text = Items.oddsText(Items.shownOdds(item))
	d.count.Text = if entry and entry.count > 0 then `\u{00D7}{entry.count}` else "—"
	d.first.Text = if entry and entry.first > 0 then DateTime.fromUnixTimestamp(entry.first):FormatLocalTime("D MMM YYYY", "en-us") else "—"
	d.flavor.Text = `"{item.flavor}"`
end

--- Everything, from the current state. Cheap enough to call on any change while the
--- panel is up (a stage is a dozen cards); while it is shut, changes only mark it
--- dirty and the next open pays.
function Index.render()
	dirty = false
	local list = stageList()
	if selectedId == nil or not table.find(list, Items.get(selectedId)) then
		selectedId = nil
		for _, item in list do
			if discovered[item.id] then
				selectedId = item.id
				break
			end
		end
		if selectedId == nil and list[1] then
			selectedId = list[1].id
		end
	end
	renderHeader()
	renderRail()
	renderFilters()
	renderGrid(list)
	renderBadge()
	Index.select(selectedId, true)
end

-- ── Selection ───────────────────────────────────────────────────────

--- Open an entry in the detail column. Opening one still marked NEW takes the badge
--- off here and tells the server, so it stays off.
function Index.select(id: string?, quiet: boolean?)
	selectedId = id
	if id then
		local entry = stats[id]
		if entry and entry.new and discovered[id] then
			entry.new = false
			if seenRemote then
				seenRemote:FireServer(id)
			end
			renderBadge()
		end
	end
	paintCardSelection()
	renderDetail()
	if not quiet then
		ui.detail.frame.CanvasPosition = Vector2.zero
	end
end

function Index.showStage(stageId: number)
	currentStage = stageId
	selectedId = nil
	-- A rarity chip belongs to the stage it was picked on.
	if string.sub(mode, 1, 7) == "rarity:" then
		mode = "all"
	end
	Index.render()
end

-- ── Lifecycle ────────────────────────────────────────────────────────

local function refresh()
	if ui.panel.Visible then
		Index.render()
	else
		dirty = true
		renderBadge()
	end
end

function Index.start()
	local player = Players.LocalPlayer
	local gui, buttonGui = build()
	local playerGui = player:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	buttonGui.Parent = playerGui
	seenRemote = Net.get("IndexSeen")

	Net.get("IndexState").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		discovered = if type(payload.discovered) == "table" then payload.discovered else {}
		stats = if type(payload.stats) == "table" then payload.stats else {}
		refresh()
	end)

	-- The free top-up, off the REVEAL rather than off the dig. ItemIdentified fires when
	-- the crust comes off at the wash bay or a trader names a find bought blind, and it
	-- carries the item's record after the write (`index`), so a new heaviest shows up
	-- here as well as a new discovery.
	local function found(info)
		if type(info) ~= "table" or type(info.itemId) ~= "string" or not Items.has(info.itemId) then
			return
		end
		discovered[info.itemId] = true
		if type(info.index) == "table" then
			stats[info.itemId] = info.index
		end
		refresh()
	end

	Net.get("ItemIdentified").OnClientEvent:Connect(found)
	-- Prewar Sealed needs no cleaning, so it is identified where it is dug and the
	-- discovery rides on the dig payload. Every other pull leaves `itemId` nil.
	Net.get("Unearthed").OnClientEvent:Connect(found)

	-- The detail model: turned by drag, or slowly by itself.
	UserInputService.InputChanged:Connect(function(input)
		if not spin.dragging then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
			spin.yaw += (input.Position.X - spin.lastX) * DRAG_RATE
			spin.lastX = input.Position.X
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			spin.dragging = false
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local model = spin.model
		if model == nil or not ui.panel.Visible then
			return
		end
		if not spin.dragging then
			spin.yaw += dt * SPIN_RATE
		end
		local c = spin.center
		model:PivotTo(CFrame.new(c) * CFrame.Angles(0, spin.yaw, 0) * CFrame.new(-c) * spin.base)
	end)

	renderBadge()
end

return Index
