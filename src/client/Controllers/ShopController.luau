--[[
	ShopController.lua — the Shop tile. Same card, same outlined-caption style as
	IndexController's Index tile, stacked one Dock.GAP below it on the right edge.

	NO CONTENT YET. This is the button only — no panel, no remote, no click
	behaviour. It exists so the tile is on screen and in the right spot ahead of
	whatever the Shop panel turns out to be.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local Artwork = require(script.Parent.Parent.HudArtwork)

local Shop = {}

-- Same numbers as IndexController's tile (TILE_SIZE / TILE_CAPTION_SIZE) — kept as
-- its own small copy rather than exported from there, same as this codebase's other
-- one-off dup helpers (see IndexController.formatValue).
local TILE_SIZE = 80
local TILE_CAPTION = "Shop"
local TILE_CAPTION_SIZE = 18
local TILE_HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopButton"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Same layer as IndexButton (55) — the two stack as one column, neither over the
	-- other.
	gui.DisplayOrder = 55
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local tileSize = UDim2.fromOffset(TILE_SIZE, TILE_SIZE)
	local shadow = UIKit.panel(canvas, {
		name = "ShopShadow",
		size = tileSize,
		color = UIKit.C.navShadow,
		transparency = 0.2,
		cornerRadius = UDim.new(0, 9),
		strokeThickness = 0,
		zIndex = 3,
	})
	local button, buttonStroke = UIKit.button(canvas, {
		name = "ShopButton",
		size = tileSize,
		text = "",
		textSize = UIKit.TextSize.body,
		fillColor = UIKit.C.navFill,
		fillTransparency = 0,
		strokeColor = UIKit.C.navEdge,
		strokeThickness = 2,
		cornerRadius = UDim.new(0, 9),
		zIndex = 4,
	})
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	-- Hung directly under the Index tile: same hang/centre switch at the same
	-- Dock.SIDE_TOP_MIN_HEIGHT breakpoint, one Dock.GAP below wherever the Index
	-- tile's own bottom edge falls in each case (see IndexController.place — the
	-- hang case ends at SIDE_TOP_Y + TILE_SIZE, the centred case at +TILE_SIZE/2).
	local function place()
		local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
		local hang = height >= Dock.SIDE_TOP_MIN_HEIGHT
		local indexBottom = if hang then Dock.SIDE_TOP_Y + TILE_SIZE else TILE_SIZE / 2
		local y = indexBottom + Dock.GAP
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 0.5, y)
		shadow.AnchorPoint = Vector2.new(1, 0)
		shadow.Position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 0.5, y + 4)
	end
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()

	-- The cart fills the top of the tile, centred; the bottom band is the name's —
	-- same split as the Index tile's book.
	local cart = Artwork.cart(button, UIKit.C.navIcon, UIKit.C.navFill)
	cart.icon.AnchorPoint = Vector2.new(0.5, 0)
	cart.icon.Position = UDim2.new(0.5, 0, 0, 8)

	UIKit.label(button, {
		name = "Caption",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -5),
		size = UDim2.new(1, 0, 0, 18),
		text = TILE_CAPTION,
		font = Enum.Font.GothamBlack,
		textSize = TILE_CAPTION_SIZE,
		color = Color3.new(1, 1, 1),
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 8,
	})

	local function setHighlighted(active: boolean)
		local fill = if active then UIKit.C.navFillHover else UIKit.C.navFill
		TweenService:Create(button, TILE_HOVER, { BackgroundColor3 = fill }):Play()
		TweenService:Create(buttonStroke, TILE_HOVER, {
			Color = if active then UIKit.C.navEdgeHover else UIKit.C.navEdge,
		}):Play()
		-- The basket/handle/rim brighten to white on hover, same as the book's pages;
		-- the wheels/slats are painted in the tile's own fill so they move with it —
		-- left behind, they'd turn into drawn lines on hover.
		for _, part in cart.body do
			TweenService:Create(part, TILE_HOVER, {
				BackgroundColor3 = if active then Color3.new(1, 1, 1) else UIKit.C.navIcon,
			}):Play()
		end
		for _, part in cart.accent do
			TweenService:Create(part, TILE_HOVER, { BackgroundColor3 = fill }):Play()
		end
	end
	button.MouseEnter:Connect(function()
		setHighlighted(true)
	end)
	button.MouseLeave:Connect(function()
		setHighlighted(false)
	end)
	button.SelectionGained:Connect(function()
		setHighlighted(true)
	end)
	button.SelectionLost:Connect(function()
		setHighlighted(false)
	end)

	return gui
end

function Shop.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return Shop
