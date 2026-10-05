--[[
	HudTile — one HUD tile: the 2x3 button grid on the middle left (Shop, Index, Nukes, Gear,
	Warp, Gifts) in the dark "Grid" look, and the top-right corner buttons (Settings, Daily) in
	the dark "glow orb" look.

	The grid tile, on request (2026-10-03, from a reference picture): a dark navy rounded
	square with a light rim, a big picture that pokes up over its top edge, and the name in
	white GothamBlack across its foot.

	The glow orb: a small dark square with a soft glow in the tile's own colour behind a
	full-colour symbol (Artwork.IMAGE), picture only.
	These used to be hand-copied builders, one per controller; they differed only in
	name, picture and slot, so this builds all of them and each controller keeps its
	own badge and click handler.

	No radial gradients in Roblox UI, so the glow is a picture: a white disc whose alpha
	eases from solid in the middle to nothing at the rim (Artwork.IMAGE.glow), tinted to
	the tile's colour.

	PLACEMENT IS Dock's: the tile's slot in the grid (1-6, left to right, top to bottom)
	goes through Dock.sideTileCentre, re-run on every canvas resize. The button is
	anchored on its centre so the hover UIScale grows it evenly on every side.
]]

local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.UIKit)
local Dock = UIKit.Dock
local Artwork = require(script.Parent.HudArtwork)

local HudTile = {}

local SIZE = Dock.CORNER_TILE_SIZE
local FILL = Color3.fromRGB(14, 16, 20)
local FILL_TRANSPARENCY = 0.12
local CORNER = 8
local EDGE_THICKNESS = 1.5
local EDGE_TRANSPARENCY = 0.55
local EDGE_TRANSPARENCY_HOVER = 0.15

-- The picture's square box, centred in the tile. No caption under it, on request, so
-- the drawn symbol (which runs to the edge of its square) fills most of the tile.
local ICON_SIZE = 34

-- The glow picture's diameter and how see-through it is. Its alpha falls to nothing
-- at the rim, so it can be a little wider than the tile's top band without an edge.
-- At 0.3 it reads about as strong as the old disc stack did; hover brightens it.
local GLOW_SIZE = 42
local GLOW_TRANSPARENCY = 0.3
local GLOW_TRANSPARENCY_HOVER = 0.12

-- THE LEFT-EDGE GRID (Shop, Index, Nukes, Gear, Warp, Gifts), on request: a see-through
-- near-black fill lit faintly from the top inside a thin black outline (the grey rim and
-- the navy went, on request), the picture just poking up over the top edge by
-- Dock.SIDE_GRID_POKE, the name across the foot. The corner buttons
-- (Settings, Daily, placed by spec.position) keep the dark glow-orb look.
local GRID_SIZE = Dock.SIDE_GRID_TILE
local GRID_CORNER = 11
local GRID_TOP = Color3.fromRGB(34, 36, 42)
local GRID_FOOT = Color3.fromRGB(6, 7, 10)
local GRID_FILL_TRANSPARENCY = 0.35
local GRID_OUTLINE = Color3.new(0, 0, 0)
local GRID_OUTLINE_THICKNESS = 2
local GRID_OUTLINE_TRANSPARENCY = 0.25
local GRID_ICON = 52
-- The picture's centre, up from the tile's: its top then clears the edge by the poke.
local GRID_ICON_RISE = GRID_ICON / 2 + Dock.SIDE_GRID_POKE - GRID_SIZE / 2
local GRID_TEXT_SIZE = 15
local GRID_TEXT_STROKE = 3
local GRID_TEXT_DROP = Vector2.new(1, 2)

local HOVER_SCALE = 1.07
local PRESS_SCALE = 0.94
local TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Spec = {
	-- The ScreenGui's and the button's name ("IndexButton").
	name: string,
	-- The name under the picture (grid tiles; a corner button shows none).
	caption: string,
	-- Where in the left-edge grid: 1-6, left to right, top to bottom.
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
	-- Optional: a fixed spot (the button's centre) instead of a slot in the column.
	-- `slot` is then unused.
	position: UDim2?,
	-- Optional: a place in the top-right corner row instead (Dock.cornerButtonCentre:
	-- 1 = Settings, 2 = Daily, 3 = Potions), re-placed when the scale changes. `slot`
	-- is then unused.
	corner: number?,
	-- Optional: the top LEFT instead, right after Roblox's own topbar buttons
	-- (Dock.topbarLeftCentre) -- the Settings gear. `slot` is then unused.
	topbarLeft: boolean?,
	-- Optional: the caption's text size, for a name too long for the default.
	captionSize: number?,
}

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

	local grid = spec.position == nil and spec.corner == nil and not spec.topbarLeft
	local button, edge = UIKit.button(canvas, {
		name = spec.name,
		size = if grid then UDim2.fromOffset(GRID_SIZE, GRID_SIZE) else UDim2.fromOffset(SIZE, SIZE),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = "",
		textSize = UIKit.TextSize.body,
		fillColor = FILL,
		fillTransparency = FILL_TRANSPARENCY,
		strokeColor = spec.color,
		strokeThickness = EDGE_THICKNESS,
		cornerRadius = UDim.new(0, if grid then GRID_CORNER else CORNER),
		zIndex = 4,
	})
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Transparency = EDGE_TRANSPARENCY
	if grid then
		edge.Color = GRID_OUTLINE
		edge.Thickness = GRID_OUTLINE_THICKNESS
		edge.Transparency = GRID_OUTLINE_TRANSPARENCY
		-- The fill is white so the gradient's colours are the colours drawn.
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.BackgroundTransparency = GRID_FILL_TRANSPARENCY
		local fill = Instance.new("UIGradient")
		fill.Rotation = 90
		fill.Color = ColorSequence.new(GRID_TOP, GRID_FOOT)
		fill.Parent = button
	end
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local glow, icon
	if grid then
		local function place()
			local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
			button.Position = Dock.sideTileCentre(spec.slot, height)
		end
		canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
		place()

		icon = Artwork.picture(button, "Icon", spec.image, GRID_ICON, Color3.new(1, 1, 1))
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, -GRID_ICON_RISE + (spec.iconDrop or 0))
		icon.ZIndex = 6

		UIKit.hudNumber(button, {
			name = "Caption",
			anchorPoint = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, 1),
			size = UDim2.new(1, 12, 0, (spec.captionSize or GRID_TEXT_SIZE) + 4),
			text = spec.caption,
			font = Enum.Font.GothamBlack,
			textSize = spec.captionSize or GRID_TEXT_SIZE,
			color = Color3.new(1, 1, 1),
			xAlign = Enum.TextXAlignment.Center,
			zIndex = 8,
		}, GRID_TEXT_STROKE, GRID_TEXT_DROP)
	else
		local corner = spec.corner
		if spec.topbarLeft then
			Dock.onTopbarChanged(function()
				button.Position = Dock.topbarLeftCentre()
			end)
		elseif corner then
			UIKit.onScaleChanged(function()
				button.Position = Dock.cornerButtonCentre(corner)
			end)
		else
			button.Position = spec.position :: UDim2
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
			Transparency = if grid then GRID_OUTLINE_TRANSPARENCY elseif hovered then EDGE_TRANSPARENCY_HOVER else EDGE_TRANSPARENCY,
		}):Play()
		-- The grid tiles have no glow.
		if glow then
			TweenService:Create(glow, TWEEN, {
				ImageTransparency = if hovered then GLOW_TRANSPARENCY_HOVER else GLOW_TRANSPARENCY,
			}):Play()
		end
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
-- The tiles' panels (Index, Shop, Nukes, Warp, Daily, Potions, Free Gifts ...) are
-- modals centred on the same spot, so only one may be open. Opening a second one
-- CLOSES THE FIRST and opens the new one: clicking another tile swaps the panel, the
-- player never has to close the old one by hand.
-- Every open path calls it, not just the tile clicks (the luck clover opens the Shop).

local panels: { [string]: GuiObject } = {}

--- Registers `panel` (the frame whose Visible opens and closes it) under `name`.
function HudTile.registerPanel(name: string, panel: GuiObject)
	panels[name] = panel
end

--- Closes every panel other than `name`'s that is open, so the caller can open. Always
--- returns false -- nothing blocks an open any more -- and is called at the top of every
--- open path, as `blocked` always was.
function HudTile.blocked(name: string): boolean
	for other, panel in panels do
		if other ~= name and panel.Visible then
			panel.Visible = false
		end
	end
	return false
end

return HudTile
