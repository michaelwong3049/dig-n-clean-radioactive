--[[
	ShopController.lua — the Shop tile, and the panel it opens. Same card, same
	outlined-caption style as IndexController's Index tile, stacked one Dock.GAP below
	it on the right edge.

	THE PANEL IS THE ROBUX SHOP (PLAN §11), not the gear stalls: gear is bought by
	walking up to a stall on the plaza (StationController), and that stays the only
	way. Its first and so far only card is the LUCKY CLOVER (Config/LuckBoost): 2x luck
	for PRODUCT_SECONDS, bought as a repeatable developer product. The client only ever
	PROMPTS the purchase -- the grant is ProductService's receipt handler on the server,
	and the clover in the corner (LuckBoostController) lights up off the attribute that
	grant writes, so nothing here has to trust or wait on the prompt's own callback.

	With no product id configured (LuckBoost.PRODUCT_ID = 0) the card still shows, its
	button reads COMING SOON and does nothing.

	Its look is the gear panel's (StationController's FIELD): slate panel, the HUD's
	cartoon text on it (LuckiestGuy headlines, FredokaOne body, INK outlines), with the
	clover card in the clover's own green: green is x2, and x2 is what it sells
	(CloverArt's header -- purple is kept for the stacked x4).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LuckBoost = require(ReplicatedStorage.Shared.Config.LuckBoost)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local Artwork = require(script.Parent.Parent.HudArtwork)
local CloverArt = require(script.Parent.Parent.CloverArt)

local Shop = {}

-- Same tile as IndexController's: the size is Dock's (the haul widget measures its
-- clearance against it too); the caption size is a small copy rather than exported
-- from there, same as this codebase's other one-off dup helpers (see
-- IndexController.formatValue).
local TILE_SIZE = Dock.SIDE_TILE_SIZE
local TILE_CAPTION = "Shop"
local TILE_CAPTION_SIZE = 18
-- The cart picture's square box and its top inset. Bigger than the Index tile's book
-- (46) because this picture has more empty margin inside its square; at 54 the two
-- icons read as the same size, and the wheels still end around y=51, clear of the
-- caption band at 57.
local TILE_ICON_SIZE = 54
local TILE_ICON_TOP = 3
local TILE_HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The panel. StationController's FIELD slate, plus the clover's green for its card.
local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	card = Color3.fromHex("183020"),
	cardEdge = Color3.fromHex("4FB853"),
	well = Color3.fromHex("21452A"),
	light = Color3.fromHex("DDF8D2"),
	dim = Color3.fromHex("A9C9A3"),
	buy = Color3.fromHex("3FB35A"),
	buyHover = Color3.fromHex("52C96C"),
	off = Color3.fromHex("4A4F55"),
	close = Color3.fromHex("E5484D"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	headline = Enum.Font.LuckiestGuy,
	label = Enum.Font.FredokaOne,
}
local PANEL_W = 560
local PANEL_H = 330
local PAD = 20
local HEADER_H = 58
local ART = 170
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local panelFrame: Frame? = nil
local panelScale: UIScale? = nil
local statusLabel: TextLabel? = nil

--- A label in the panel's cartoon voice: white, INK-outlined. `props` are set as-is.
local function inked(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = PANEL.white
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(label :: any)[key] = value
	end
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = PANEL.ink
	stroke.Thickness = math.max(2, label.TextSize * 0.1)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

--- The Lucky Clover card: art well on the left, the pitch and the buy button right.
local function buildCloverCard(parent: Frame)
	local card = Instance.new("Frame")
	card.Name = "LuckyClover"
	card.Size = UDim2.new(1, 0, 1, -HEADER_H)
	card.Position = UDim2.fromOffset(0, HEADER_H)
	card.BackgroundColor3 = PANEL.card
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = parent
	round(card, 16)
	edge(card, PANEL.cardEdge, 3)

	local well = Instance.new("Frame")
	well.Name = "Art"
	well.Size = UDim2.fromOffset(ART, ART)
	well.Position = UDim2.new(0, 16, 0.5, 0)
	well.AnchorPoint = Vector2.new(0, 0.5)
	well.BackgroundColor3 = PANEL.well
	well.BorderSizePixel = 0
	well.ZIndex = 13
	well.Parent = card
	round(well, 14)
	edge(well, PANEL.ink, 3)
	local clover = CloverArt.build(well, 124, 14)
	clover.AnchorPoint = Vector2.new(0.5, 0.5)
	clover.Position = UDim2.fromScale(0.5, 0.5)
	clover.Rotation = -8
	inked(well, {
		Name = "Mult",
		Text = `{LuckBoost.MULT}x`,
		Font = PANEL.headline,
		TextSize = 40,
		Size = UDim2.fromOffset(ART, 44),
		Position = UDim2.new(0, 4, 0.5, -16),
		TextXAlignment = Enum.TextXAlignment.Center,
		Rotation = -8,
		ZIndex = 30,
	})

	local textLeft = 16 + ART + 18
	inked(card, {
		Name = "Name",
		Text = "LUCKY CLOVER",
		Font = PANEL.headline,
		TextSize = 30,
		Size = UDim2.new(1, -textLeft - 12, 0, 36),
		Position = UDim2.fromOffset(textLeft, 16),
		ZIndex = 14,
	})
	inked(card, {
		Name = "Pitch",
		Text = `{LuckBoost.MULT}x LUCK for {math.floor(LuckBoost.PRODUCT_SECONDS / 60)} minutes`,
		Font = PANEL.label,
		TextSize = 20,
		TextColor3 = PANEL.light,
		Size = UDim2.new(1, -textLeft - 12, 0, 24),
		Position = UDim2.fromOffset(textLeft, 54),
		ZIndex = 14,
	})
	inked(card, {
		Name = "Details",
		Text = table.concat({
			"• Rarer nukes when you dig",
			"• Rarer liquids on the wash pad",
			`• Stacks with the {LuckBoost.EVENT_NAME}: x{LuckBoost.MULT * LuckBoost.MULT}`,
			"• Only counts down while you play",
		}, "\n"),
		Font = PANEL.label,
		TextSize = 16,
		TextColor3 = PANEL.dim,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.1,
		Size = UDim2.new(1, -textLeft - 12, 0, 84),
		Position = UDim2.fromOffset(textLeft, 84),
		ZIndex = 14,
	})

	local configured = LuckBoost.PRODUCT_ID ~= 0
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AutoButtonColor = false
	buy.Size = UDim2.fromOffset(170, 46)
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position = UDim2.new(1, -16, 1, -14)
	buy.BackgroundColor3 = if configured then PANEL.buy else PANEL.off
	buy.Font = PANEL.headline
	buy.TextSize = if configured then 24 else 18
	buy.TextColor3 = PANEL.white
	buy.Text = if configured then "BUY" else "COMING SOON"
	buy.ZIndex = 15
	buy.Parent = card
	round(buy, 14)
	local buyEdge = Instance.new("UIStroke")
	buyEdge.Color = PANEL.ink
	buyEdge.Thickness = 3
	buyEdge.LineJoinMode = Enum.LineJoinMode.Round
	buyEdge.Parent = buy

	statusLabel = inked(card, {
		Name = "Status",
		Text = "",
		Font = PANEL.label,
		TextSize = 16,
		TextColor3 = PANEL.light,
		Size = UDim2.new(1, -textLeft - 196, 0, 46),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, textLeft, 1, -14),
		TextWrapped = true,
		ZIndex = 14,
	})

	if not configured then
		return
	end

	-- The Robux price comes from the product itself, so a dashboard price change never
	-- needs a code change. BUY stands in until it arrives (or if it cannot).
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(LuckBoost.PRODUCT_ID, Enum.InfoType.Product)
		end)
		if ok and info and info.PriceInRobux then
			buy.Text = `R$ {info.PriceInRobux}`
		end
	end)

	buy.MouseEnter:Connect(function()
		TweenService:Create(buy, TILE_HOVER, { BackgroundColor3 = PANEL.buyHover }):Play()
	end)
	buy.MouseLeave:Connect(function()
		TweenService:Create(buy, TILE_HOVER, { BackgroundColor3 = PANEL.buy }):Play()
	end)
	buy.Activated:Connect(function()
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, LuckBoost.PRODUCT_ID)
	end)
end

--- "Active: 9:42 left" while a bought clover is running, else nothing.
local function refreshStatus()
	local label = statusLabel
	if label == nil then
		return
	end
	local ends = Players.LocalPlayer:GetAttribute(LuckBoost.PERSONAL_ATTR)
	local left = if type(ends) == "number" then ends - Workspace:GetServerTimeNow() else 0
	if left <= 0 then
		label.Text = ""
		return
	end
	local s = math.ceil(left)
	local h, m, r = s // 3600, (s % 3600) // 60, s % 60
	local clock = if h > 0 then string.format("%d:%02d:%02d", h, m, r) else string.format("%d:%02d", m, r)
	label.Text = `Active: {clock} left`
end

--- Open the Shop panel. Also what clicking the 2x-luck clover does (LuckBoostController).
function Shop.open()
	local panel = panelFrame
	if panel == nil or panel.Visible then
		return
	end
	refreshStatus()
	panel.Visible = true
	if panelScale then
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, OPEN, { Scale = 1 }):Play()
	end
end

function Shop.close()
	if panelFrame then
		panelFrame.Visible = false
	end
end

function Shop.toggle()
	if panelFrame and panelFrame.Visible then
		Shop.close()
	else
		Shop.open()
	end
end

local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopPanel"
	gui.ResetOnSpawn = false
	-- Same call as IndexController's panel: a centred modal respects the topbar inset
	-- rather than ignoring it, and sits over the whole HUD (RadHud is 100).
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = PANEL.panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 10
	panel.Parent = canvas
	round(panel, 20)
	edge(panel, PANEL.ink, 4)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PAD - 6)
	padding.PaddingBottom = UDim.new(0, PAD)
	padding.PaddingLeft = UDim.new(0, PAD)
	padding.PaddingRight = UDim.new(0, PAD)
	padding.Parent = panel

	inked(panel, {
		Name = "Title",
		Text = "SHOP",
		Font = PANEL.headline,
		TextSize = 38,
		Size = UDim2.fromOffset(200, 46),
		ZIndex = 11,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 2)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = PANEL.close
	close.Font = PANEL.headline
	close.TextSize = 24
	close.TextColor3 = PANEL.white
	close.Text = "X"
	close.ZIndex = 11
	close.Parent = panel
	round(close, 12)
	local closeEdge = Instance.new("UIStroke")
	closeEdge.Color = PANEL.ink
	closeEdge.Thickness = 3
	closeEdge.Parent = close
	close.Activated:Connect(Shop.close)

	buildCloverCard(panel)

	panelFrame = panel
	panelScale = scale
	return gui
end

--- The Shop tile's top edge, in design px from the canvas's vertical centre, on a
--- canvas `height` design px tall. Hung directly under the Index tile: same hang/centre
--- switch at the same Dock.SIDE_TOP_MIN_HEIGHT breakpoint, one Dock.GAP below wherever
--- the Index tile's own bottom edge falls in each case (see IndexController.place — the
--- hang case ends at SIDE_TOP_Y + TILE_SIZE, the centred case at +TILE_SIZE/2).
local function tileTop(height: number): number
	local hang = height >= Dock.SIDE_TOP_MIN_HEIGHT
	local indexBottom = if hang then Dock.SIDE_TOP_Y + TILE_SIZE else TILE_SIZE / 2
	return indexBottom + Dock.GAP
end

--- Where the right-hand tile column ends: the Shop tile's bottom edge, in design px
--- from the canvas TOP. LuckBoostController keeps the 2x-luck clover below it.
function Shop.columnBottom(height: number): number
	return height / 2 + tileTop(height) + TILE_SIZE
end

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

	-- Hung directly under the Index tile -- see tileTop.
	local function place()
		local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
		local y = tileTop(height)
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 0.5, y)
		shadow.AnchorPoint = Vector2.new(1, 0)
		shadow.Position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 0.5, y + 4)
	end
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()

	-- The cart fills the top of the tile, centred; the bottom band is the name's —
	-- same split as the Index tile's book.
	local cart = Artwork.picture(button, "CartIcon", Artwork.IMAGE.cart, TILE_ICON_SIZE, UIKit.C.navIcon)
	cart.AnchorPoint = Vector2.new(0.5, 0)
	cart.Position = UDim2.new(0.5, 0, 0, TILE_ICON_TOP)

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
		-- The cart brightens to white, same as the Index tile's book.
		TweenService:Create(cart, TILE_HOVER, {
			ImageColor3 = if active then Color3.new(1, 1, 1) else UIKit.C.navIcon,
		}):Play()
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
	button.Activated:Connect(Shop.toggle)

	return gui
end

function Shop.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	build().Parent = playerGui
	buildPanel().Parent = playerGui

	player:GetAttributeChangedSignal(LuckBoost.PERSONAL_ATTR):Connect(refreshStatus)
	task.spawn(function()
		while true do
			task.wait(1)
			if panelFrame and panelFrame.Visible then
				refreshStatus()
			end
		end
	end)
end

return Shop
