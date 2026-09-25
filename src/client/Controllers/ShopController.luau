--[[
	ShopController.lua — the Shop tile, and the panel it opens. The tile is the
	top-right square of the right-edge 2x2 grid, built by HudTile like the other three.

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
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)
local CloverArt = require(script.Parent.Parent.CloverArt)

local Shop = {}

-- THE SHOP TILE: top right of the right-edge 2x2 grid (HudTile), a green glow behind
-- the treasure chest.
local TILE_SLOT = 2
local TILE_COLOR = Color3.fromRGB(86, 212, 71)
local TILE_LIGHT = Color3.fromRGB(185, 245, 168)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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
		TweenService:Create(buy, HOVER, { BackgroundColor3 = PANEL.buyHover }):Play()
	end)
	buy.MouseLeave:Connect(function()
		TweenService:Create(buy, HOVER, { BackgroundColor3 = PANEL.buy }):Play()
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
	if panel == nil or panel.Visible or HudTile.blocked("Shop") then
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

local function build(): ScreenGui
	local gui = HudTile.build({
		name = "ShopButton",
		caption = "Shop",
		slot = TILE_SLOT,
		color = TILE_COLOR,
		light = TILE_LIGHT,
		image = Artwork.IMAGE.chest,
		onActivated = Shop.toggle,
	})
	return gui
end

function Shop.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	build().Parent = playerGui
	buildPanel().Parent = playerGui
	HudTile.registerPanel("Shop", panelFrame :: Frame)

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
