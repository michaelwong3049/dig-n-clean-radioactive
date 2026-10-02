--[[
	HudTile — one right-edge HUD tile (Gear, Nukes, Warp): the "glow orb" look.

	A small dark square with a soft glow in the tile's own colour behind a full-colour
	symbol (Artwork.IMAGE), picture only: the name caption under it was dropped on request
	when the tiles went from a 2x2 grid to one smaller column. Index and Shop build the
	left-column bars through the same function (spec.leftRow), and keep their names.
	These used to be hand-copied builders, one per controller; they differed only in
	name, picture and slot, so this builds all of them and each controller keeps its
	own badge and click handler.

	No radial gradients in Roblox UI, so the glow is a picture: a white disc whose alpha
	eases from solid in the middle to nothing at the rim (Artwork.IMAGE.glow), tinted to
	the tile's colour. It was a stack of five see-through discs first; their edges read
	as rings ("chunky"), which a real gradient doesn't have.

	PLACEMENT IS Dock's: the tile's slot in the column (1-3, top to bottom)
	goes through Dock.sideTileCentre, re-run on every canvas resize. The button is
	anchored on its centre so the hover UIScale grows it evenly on every side.
]]

local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.UIKit)
local Dock = UIKit.Dock
local Artwork = require(script.Parent.HudArtwork)

local HudTile = {}

local SIZE = Dock.SIDE_TILE_SIZE
local FILL = Color3.fromRGB(14, 16, 20)
local FILL_TRANSPARENCY = 0.12
local CORNER = 9
local EDGE_THICKNESS = 1.5
local EDGE_TRANSPARENCY = 0.55
local EDGE_TRANSPARENCY_HOVER = 0.15

-- The picture's square box, centred in the tile. No caption under it, on request, so
-- the drawn symbol (which runs to the edge of its square) fills most of the tile.
local ICON_SIZE = 48

-- The glow picture's diameter and how see-through it is. Its alpha falls to nothing
-- at the rim, so it can be a little wider than the tile's top band without an edge.
-- At 0.3 it reads about as strong as the old disc stack did; hover brightens it.
local GLOW_SIZE = 60
local GLOW_TRANSPARENCY = 0.3
local GLOW_TRANSPARENCY_HOVER = 0.12

local HOVER_SCALE = 1.07
local PRESS_SCALE = 0.94
local TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Spec = {
	-- The ScreenGui's and the button's name ("IndexButton").
	name: string,
	-- The bar's name (leftRow only; a square tile shows no caption).
	caption: string,
	-- Where in the right-edge column: 1-3, top to bottom.
	slot: number,
	-- The glow and edge colour, and the lighter caption tint.
	color: Color3,
	light: Color3,
	-- The symbol (Artwork.IMAGE).
	image: string,
	-- Design px to drop the symbol below the glow's centre, for a drawing whose weight
	-- sits high in its square.
	iconDrop: number?,
	-- Optional: a caller that wires its own click (IndexController) leaves it out.
	onActivated: (() -> ())?,
	-- Optional: a fixed spot (the button's centre) instead of a slot in the column —
	-- the Settings gear in the top-right corner. `slot` is then unused.
	position: UDim2?,
	-- Optional: build a wide bar in the LEFT column instead of a grid square, stacked
	-- up from the left edge's middle (1 = Index, 2 = Shop, 3 = Masteries, bottom to
	-- top). `slot` is then unused.
	leftRow: number?,
	-- Optional: the bar caption's text size, for a name too long for BAR_TEXT_SIZE.
	captionSize: number?,
	-- Optional, with leftRow: no box at all, on request — just the picture, big, with the
	-- caption centred under it (Masteries' medal).
	bare: boolean?,
}

-- THE LEFT-COLUMN BARS (Index, Shop, Masteries), on request: a solid dark rectangle on the middle
-- of the left edge, the picture on its left and the name beside it in the rows' own GothamBlack
-- (UIKit.hudNumber: same outline and drop shadow as the balance).
local BAR_W = 168
local BAR_H = 50
local BAR_ICON = 38
local BAR_CORNER = 3
local BAR_EDGE_THICKNESS = 2.5
local BAR_GLOW = 58
local BAR_TEXT_LEFT = 54
local BAR_TEXT_SIZE = 28
local BAR_TEXT_STROKE = 3
local BAR_TEXT_DROP = Vector2.new(2, 3)
-- The space between the two bars, and how far the pair sits ABOVE the left edge's
-- middle, both on request.
local BAR_GAP = 18
local BAR_RAISE = 20
-- A bare row (no box): the picture, the caption under it, and the button's whole size.
local BARE_ICON = 78
local BARE_GLOW = 112
-- Negative: the medal art has clear space under its disc, and the name sits right under it.
local BARE_CAPTION_GAP = -11
-- Just wider than "Masteries" at 20.
local BARE_W = 100
-- Extra space over the row below, on top of BAR_GAP, on request.
local BARE_LIFT = 28

--- Builds the tile in its own ScreenGui (IgnoreGuiInset, so the grid measures against
--- the true screen as the left column does). Returns the gui, unparented, and the button,
--- which a caller hangs a badge on.
function HudTile.build(spec: Spec): (ScreenGui, TextButton)
	local gui = Instance.new("ScreenGui")
	gui.Name = spec.name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- UNDER DetectorHud (60): if a narrow screen ever pushes the haul widget into the
	-- grid, the widget (only up mid-haul, when it is the thing being read) draws on top.
	-- Still over StationHud (40).
	gui.DisplayOrder = 55
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local bar = spec.leftRow ~= nil
	local button, edge = UIKit.button(canvas, {
		name = spec.name,
		size = if bar then UDim2.fromOffset(BAR_W, BAR_H) else UDim2.fromOffset(SIZE, SIZE),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = "",
		textSize = UIKit.TextSize.body,
		fillColor = FILL,
		fillTransparency = FILL_TRANSPARENCY,
		strokeColor = spec.color,
		strokeThickness = EDGE_THICKNESS,
		cornerRadius = UDim.new(0, if bar then BAR_CORNER else CORNER),
		zIndex = 4,
	})
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Transparency = EDGE_TRANSPARENCY
	if bar then
		-- A near-square box with a solid black outline, on request.
		edge.Color = Color3.new(0, 0, 0)
		edge.Thickness = BAR_EDGE_THICKNESS
		edge.Transparency = 0
	end
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local glow, icon
	if bar then
		local row = spec.leftRow :: number
		-- Rows 1 and 2 are centred as a pair BAR_RAISE over the left edge's middle, row 1
		-- under; row 3 (Masteries) stacks on top of them without moving the pair.
		local up = (row - 1.5) * (BAR_H + BAR_GAP) + BAR_RAISE
		if spec.bare then
			-- Its bottom edge BAR_GAP + BARE_LIFT over the top of the row below, its left edge on the
			-- bars' left edge (on request: further left than centring over the bar).
			local captionSize = spec.captionSize or BAR_TEXT_SIZE
			local height = BARE_ICON + BARE_CAPTION_GAP + captionSize + 4
			local belowTop = (row - 2.5) * (BAR_H + BAR_GAP) + BAR_RAISE + BAR_H / 2
			button.Size = UDim2.fromOffset(BARE_W, height)
			button.Position = UDim2.new(0, Dock.ROW_SIDE_MARGIN + BARE_W / 2, 0.5, -(belowTop + BAR_GAP + BARE_LIFT + height / 2))
			button.BackgroundTransparency = 1
			edge.Enabled = false

			glow = Artwork.picture(button, "Glow", Artwork.IMAGE.glow, BARE_GLOW, spec.color)
			glow.AnchorPoint = Vector2.new(0.5, 0.5)
			glow.Position = UDim2.new(0.5, 0, 0, BARE_ICON / 2)
			glow.ImageTransparency = GLOW_TRANSPARENCY
			glow.ZIndex = 5

			icon = Artwork.picture(button, "Icon", spec.image, BARE_ICON, Color3.new(1, 1, 1))
			icon.AnchorPoint = Vector2.new(0.5, 0)
			icon.Position = UDim2.new(0.5, 0, 0, spec.iconDrop or 0)
			icon.ZIndex = 6

			UIKit.hudNumber(button, {
				name = "Caption",
				anchorPoint = Vector2.new(0.5, 0),
				position = UDim2.new(0.5, 0, 0, BARE_ICON + BARE_CAPTION_GAP),
				size = UDim2.new(1, 0, 0, captionSize + 4),
				text = spec.caption,
				font = Enum.Font.GothamBlack,
				textSize = captionSize,
				color = spec.light,
				xAlign = Enum.TextXAlignment.Center,
				zIndex = 8,
			}, BAR_TEXT_STROKE, BAR_TEXT_DROP)
		else
			button.Position = UDim2.new(0, Dock.ROW_SIDE_MARGIN + BAR_W / 2, 0.5, -up)
			-- Solid, a dark (not near-black) shade of the bar's own colour.
			button.BackgroundColor3 = spec.color:Lerp(Color3.new(0, 0, 0), 0.6)
			button.BackgroundTransparency = 0

			local iconCentre = 6 + BAR_ICON / 2
			glow = Artwork.picture(button, "Glow", Artwork.IMAGE.glow, BAR_GLOW, spec.color)
			glow.AnchorPoint = Vector2.new(0.5, 0.5)
			glow.Position = UDim2.new(0, iconCentre, 0.5, 0)
			glow.ImageTransparency = GLOW_TRANSPARENCY
			glow.ZIndex = 5

			icon = Artwork.picture(button, "Icon", spec.image, BAR_ICON, Color3.new(1, 1, 1))
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0, iconCentre, 0.5, spec.iconDrop or 0)
			icon.ZIndex = 6

			UIKit.hudNumber(button, {
				name = "Caption",
				anchorPoint = Vector2.new(0, 0.5),
				position = UDim2.new(0, BAR_TEXT_LEFT, 0.5, -1),
				size = UDim2.new(1, -BAR_TEXT_LEFT - 6, 0, (spec.captionSize or BAR_TEXT_SIZE) + 4),
				text = spec.caption,
				font = Enum.Font.GothamBlack,
				textSize = spec.captionSize or BAR_TEXT_SIZE,
				color = spec.light,
				xAlign = Enum.TextXAlignment.Left,
				zIndex = 8,
			}, BAR_TEXT_STROKE, BAR_TEXT_DROP)
		end
	else
		if spec.position then
			button.Position = spec.position
		else
			local function place()
				local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
				button.Position = Dock.sideTileCentre(spec.slot, height)
			end
			canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
			place()
		end

		-- The glow and the picture, both on the tile's centre.
		glow = Artwork.picture(button, "Glow", Artwork.IMAGE.glow, GLOW_SIZE, spec.color)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.ImageTransparency = GLOW_TRANSPARENCY
		glow.ZIndex = 5

		icon = Artwork.picture(button, "Icon", spec.image, ICON_SIZE, Color3.new(1, 1, 1))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, spec.iconDrop or 0)
		icon.ZIndex = 6
	end

	local hovered, pressed = false, false
	local function refresh()
		local target = if pressed then PRESS_SCALE elseif hovered then HOVER_SCALE else 1
		TweenService:Create(scale, TWEEN, { Scale = target }):Play()
		TweenService:Create(edge, TWEEN, {
			Transparency = if bar then 0 elseif hovered then EDGE_TRANSPARENCY_HOVER else EDGE_TRANSPARENCY,
		}):Play()
		TweenService:Create(glow, TWEEN, {
			ImageTransparency = if hovered then GLOW_TRANSPARENCY_HOVER else GLOW_TRANSPARENCY,
		}):Play()
	end
	local function setHovered(on: boolean)
		hovered = on
		if not on then
			pressed = false
		end
		refresh()
	end
	button.MouseEnter:Connect(function()
		setHovered(true)
	end)
	button.MouseLeave:Connect(function()
		setHovered(false)
	end)
	button.SelectionGained:Connect(function()
		setHovered(true)
	end)
	button.SelectionLost:Connect(function()
		setHovered(false)
	end)
	button.MouseButton1Down:Connect(function()
		pressed = true
		refresh()
	end)
	button.MouseButton1Up:Connect(function()
		pressed = false
		refresh()
	end)
	if spec.onActivated then
		button.Activated:Connect(spec.onActivated)
	end

	return gui, button
end

--- A round red corner badge on `button` (the Index's NEW count, the Warp's "!"),
--- hidden until the caller shows it. Returns the badge and its label.
function HudTile.badge(button: GuiObject, color: Color3, ink: Color3): (Frame, TextLabel)
	local badge = Instance.new("Frame")
	badge.Name = "NewBadge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 5, 0, -5)
	badge.Size = UDim2.fromOffset(20, 20)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = color
	badge.BorderSizePixel = 0
	badge.Visible = false
	badge.ZIndex = 9
	badge.Parent = button
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 10)
	round.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.Color = ink
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = badge
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 5)
	pad.PaddingRight = UDim.new(0, 5)
	pad.Parent = badge
	local label = Instance.new("TextLabel")
	label.Name = "Mark"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 12
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	label.ZIndex = 10
	label.Parent = badge
	return badge, label
end

-- ── One panel at a time ─────────────────────────────────────────────
-- The tiles' panels (Index, Shop, Nukes, Warp) are modals centred on the same spot,
-- so only one may be open: the player closes it before another will open. An open
-- that is refused shakes the panel in the way, so the click visibly did something.
-- Every open path checks, not just the tile clicks (the luck clover opens the Shop).

local SHAKE_STEPS = { 8, -7, 5, -3, 0 }
local SHAKE_STEP = TweenInfo.new(0.04, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local panels: { [string]: GuiObject } = {}
local shaking: { [GuiObject]: boolean } = {}

--- Registers `panel` (the frame whose Visible opens and closes it) under `name`.
function HudTile.registerPanel(name: string, panel: GuiObject)
	panels[name] = panel
end

local function shake(panel: GuiObject)
	if shaking[panel] then
		return
	end
	shaking[panel] = true
	local home = panel.Position
	task.spawn(function()
		for _, dx in SHAKE_STEPS do
			local tween = TweenService:Create(panel, SHAKE_STEP, { Position = home + UDim2.fromOffset(dx, 0) })
			tween:Play()
			tween.Completed:Wait()
		end
		panel.Position = home
		shaking[panel] = nil
	end)
end

--- True when a panel other than `name`'s is open, and shakes that one: the caller
--- must not open. Call it at the top of every open path.
function HudTile.blocked(name: string): boolean
	for other, panel in panels do
		if other ~= name and panel.Visible then
			shake(panel)
			return true
		end
	end
	return false
end

return HudTile
