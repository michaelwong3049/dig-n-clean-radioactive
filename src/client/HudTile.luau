--[[
	HudTile — one right-edge HUD tile (Index, Shop, Nukes, Warp): the "glow orb" look.

	A small dark square with a soft glow in the tile's own colour behind a full-colour
	symbol (Artwork.IMAGE), and the tile's name under it in a light tint of that colour. Picked from a
	mockup round (option 11) when the four 80px column tiles became a 2x2 grid of
	smaller ones. The four used to be four hand-copied builders, one per controller;
	they differed only in name, picture and slot, so this builds all of them and each
	controller keeps its own badge and click handler.

	No radial gradients in Roblox UI, so the glow is a stack of concentric discs, each
	mostly see-through: where they overlap in the middle they add up to a bright core
	that fades out to the rim (the same trick as HaulShaft's nuke glow).

	PLACEMENT IS Dock's: the tile's slot in the grid (1-4, left to right, top to bottom)
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

-- The picture's square box and its top inset; the caption owns the bottom band.
-- The drawn symbols run to the edge of their square, so the box is most of the tile.
local ICON_SIZE = 36
local ICON_TOP = 4
local CAPTION_SIZE = 13
local CAPTION_BOTTOM = 4

-- The glow: disc diameters, largest first, each this see-through. Five at 0.86 make
-- a core about half opaque; hover lowers each disc's transparency to brighten it.
local GLOW_DISCS = { 46, 38, 30, 22, 14 }
local GLOW_TRANSPARENCY = 0.86
local GLOW_TRANSPARENCY_HOVER = 0.8

local HOVER_SCALE = 1.07
local PRESS_SCALE = 0.94
local TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Spec = {
	-- The ScreenGui's and the button's name ("IndexButton").
	name: string,
	caption: string,
	-- Where in the 2x2 grid: 1-4, left to right, top to bottom.
	slot: number,
	-- The glow and edge colour, and the lighter caption tint.
	color: Color3,
	light: Color3,
	-- The symbol (Artwork.IMAGE).
	image: string,
	-- Optional: a caller that wires its own click (IndexController) leaves it out.
	onActivated: (() -> ())?,
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

	local button, edge = UIKit.button(canvas, {
		name = spec.name,
		size = UDim2.fromOffset(SIZE, SIZE),
		anchorPoint = Vector2.new(0.5, 0.5),
		text = "",
		textSize = UIKit.TextSize.body,
		fillColor = FILL,
		fillTransparency = FILL_TRANSPARENCY,
		strokeColor = spec.color,
		strokeThickness = EDGE_THICKNESS,
		cornerRadius = UDim.new(0, CORNER),
		zIndex = 4,
	})
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Transparency = EDGE_TRANSPARENCY
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local function place()
		local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
		button.Position = Dock.sideTileCentre(spec.slot, height)
	end
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()

	-- The glow, centred on the picture.
	local iconCentre = ICON_TOP + ICON_SIZE / 2
	local discs: { Frame } = {}
	for i, diameter in GLOW_DISCS do
		local disc = Instance.new("Frame")
		disc.Name = "Glow" .. i
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.new(0.5, 0, 0, iconCentre)
		disc.Size = UDim2.fromOffset(diameter, diameter)
		disc.BackgroundColor3 = spec.color
		disc.BackgroundTransparency = GLOW_TRANSPARENCY
		disc.BorderSizePixel = 0
		disc.ZIndex = 5
		disc.Parent = button
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = disc
		table.insert(discs, disc)
	end

	local icon = Artwork.picture(button, "Icon", spec.image, ICON_SIZE, Color3.new(1, 1, 1))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0, iconCentre)
	icon.ZIndex = 6

	UIKit.label(button, {
		name = "Caption",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -CAPTION_BOTTOM),
		size = UDim2.new(1, 0, 0, CAPTION_SIZE),
		text = spec.caption,
		font = Enum.Font.FredokaOne,
		textSize = CAPTION_SIZE,
		color = spec.light,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 8,
	})

	local hovered, pressed = false, false
	local function refresh()
		local target = if pressed then PRESS_SCALE elseif hovered then HOVER_SCALE else 1
		TweenService:Create(scale, TWEEN, { Scale = target }):Play()
		TweenService:Create(edge, TWEEN, {
			Transparency = if hovered then EDGE_TRANSPARENCY_HOVER else EDGE_TRANSPARENCY,
		}):Play()
		local glow = if hovered then GLOW_TRANSPARENCY_HOVER else GLOW_TRANSPARENCY
		for _, disc in discs do
			TweenService:Create(disc, TWEEN, { BackgroundTransparency = glow }):Play()
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
