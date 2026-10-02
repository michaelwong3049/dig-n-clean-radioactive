--[[
	ShopController.lua — the Shop tile, and the panel it opens. The tile is the
	top-right square of the right-edge 2x2 grid, built by HudTile like the other three.

	THE PANEL IS THE ROBUX SHOP (PLAN §11), not the gear stalls: gear is bought by
	walking up to a stall on the plaza (StationController). One scrolling body, four
	sections: the PASSES (Config/GamePasses), seven permanent upgrades on top, which
	turn to OWNED off the Player attribute GamePassService writes; the LUCKY CLOVER (Config/LuckBoost), 2x luck for PRODUCT_SECONDS; a CASH
	row of four packs; and a CRATES row with the two Mystery crates (Config/ShopProducts,
	whose grants live in EconomyService and CrateService). Every buy button is the gear
	cards' purple R$, so real money always looks the same. The client only ever
	PROMPTS the purchase -- the grant is ProductService's receipt handler on the server,
	and the clover in the corner (LuckBoostController) lights up off the attribute that
	grant writes, so nothing here has to trust or wait on the prompt's own callback.

	With no product id configured (LuckBoost.PRODUCT_ID = 0) the card still shows, its
	button reads COMING SOON and does nothing.

	Its look is the gear panel's (StationController's FIELD): slate panel, the HUD's
	text on it (all Gotham Black, INK outlines), with the
	clover card in the clover's own green: green is x2, and x2 is what it sells
	(CloverArt's header -- purple is kept for the stacked x4).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LuckBoost = require(ReplicatedStorage.Shared.Config.LuckBoost)
local ShopProducts = require(ReplicatedStorage.Shared.Config.ShopProducts)
local Crates = require(ReplicatedStorage.Shared.Config.Crates)
local GamePasses = require(ReplicatedStorage.Shared.Config.GamePasses)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)
local CloverArt = require(script.Parent.Parent.CloverArt)
local ItemArt = require(script.Parent.Parent.ItemArt)

local Shop = {}

-- THE SHOP TILE: top right of the right-edge 2x2 grid (HudTile), a green glow behind
-- the treasure chest.
local TILE_SLOT = 2
local TILE_COLOR = Color3.fromRGB(86, 212, 71)
local TILE_LIGHT = Color3.fromRGB(185, 245, 168)
-- The chest's dark lid makes it read high in its square; this settles it on the glow.
local TILE_ICON_DROP = 2
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The panel. StationController's FIELD slate, plus the clover's green for its card.
local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	card = Color3.fromHex("183020"),
	cardEdge = Color3.fromHex("4FB853"),
	well = Color3.fromHex("21452A"),
	light = Color3.fromHex("DDF8D2"),
	dim = Color3.fromHex("A9C9A3"),
	-- StationController's FIELD.robux: every Robux button in the game is this purple.
	buy = Color3.fromHex("7B3FE4"),
	buyHover = Color3.fromHex("9257F5"),
	-- An owned pass's button: the clover's green, so "you have this" reads at a glance.
	buyOwned = Color3.fromHex("2F9E4A"),
	-- The cash and crate cards: the panel's slate, a shade up.
	tile = Color3.fromHex("252A30"),
	tileEdge = Color3.fromHex("3A4148"),
	cash = Color3.fromHex("6BE36B"),
	off = Color3.fromHex("4A4F55"),
	close = Color3.fromHex("E5484D"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	headline = Enum.Font.GothamBlack,
	label = Enum.Font.GothamBlack,
}
local PANEL_W = 860
-- The panel's tallest; a short screen gets less, and the body scrolls.
local PANEL_H = 720
local CLOVER_H = 220
local SECTION_H = 30
local CASH_H = 168
local CRATE_H = 200
local PASS_H = 236
local PASSES_PER_ROW = 4
local GAP = 12
-- Sits this far above dead centre: a little higher than the true middle, on request.
local PANEL_LIFT = 40
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

--- A purple R$ button for `productId`, parented to `parent`. Its price is read off the
--- product, so a dashboard change needs no code change; "R$" stands in until then. An
--- id of 0 (not set up on the dashboard) gives a grey COMING SOON that does nothing.
--- `isPass` sells a game pass (Config/GamePasses) instead of a developer product.
local function robuxButton(parent: Instance, productId: number, isPass: boolean?): TextButton
	local live = productId ~= 0
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AutoButtonColor = false
	buy.BackgroundColor3 = if live then PANEL.buy else PANEL.off
	buy.Font = PANEL.headline
	buy.TextSize = if live then 24 else 18
	buy.TextColor3 = PANEL.white
	buy.Text = if live then "R$" else "COMING SOON"
	buy.ZIndex = 15
	buy.Parent = parent
	round(buy, 12)
	local buyEdge = Instance.new("UIStroke")
	buyEdge.Color = PANEL.ink
	buyEdge.Thickness = 3
	buyEdge.LineJoinMode = Enum.LineJoinMode.Round
	buyEdge.Parent = buy
	if not live then
		return buy
	end

	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)
		end)
		if ok and info and info.PriceInRobux then
			-- Kept as an attribute too, so an OWNED pass button can put it back.
			buy:SetAttribute("Price", `R$ {info.PriceInRobux}`)
			if buy.Active then
				buy.Text = `R$ {info.PriceInRobux}`
			end
		end
	end)
	-- An owned pass turns its button off (Active = false); hover and click both respect it.
	buy.MouseEnter:Connect(function()
		if buy.Active then
			TweenService:Create(buy, HOVER, { BackgroundColor3 = PANEL.buyHover }):Play()
		end
	end)
	buy.MouseLeave:Connect(function()
		if buy.Active then
			TweenService:Create(buy, HOVER, { BackgroundColor3 = PANEL.buy }):Play()
		end
	end)
	buy.Activated:Connect(function()
		if not buy.Active then
			return
		end
		if isPass then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, productId)
		else
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
		end
	end)
	return buy
end

--- The Lucky Clover card: art well on the left, the pitch and the buy button right.
local function buildCloverCard(parent: Frame)
	local card = Instance.new("Frame")
	card.Name = "LuckyClover"
	card.Size = UDim2.new(1, -8, 0, CLOVER_H)
	card.LayoutOrder = 1
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

	local buy = robuxButton(card, LuckBoost.PRODUCT_ID)
	buy.Size = UDim2.fromOffset(170, 46)
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position = UDim2.new(1, -16, 1, -14)
end

--- A section heading in the body ("CASH", "CRATES").
local function section(parent: Instance, order: number, text: string)
	inked(parent, {
		Name = `{text}Heading`,
		Text = text,
		Font = PANEL.headline,
		TextSize = 24,
		Size = UDim2.new(1, -8, 0, SECTION_H),
		LayoutOrder = order,
		ZIndex = 12,
	})
end

--- A row of `count` equal cards across the body, `height` tall.
local function row(parent: Instance, order: number, name: string, height: number, count: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(1, -8, 0, height)
	frame.BackgroundTransparency = 1
	frame.LayoutOrder = order
	frame.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(GAP, 0)
	grid.CellSize = UDim2.new(1 / count, -GAP * (count - 1) / count, 1, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = frame
	return frame
end

--- One card on a row: the slate tile, with its purple button along the bottom.
local function tile(parent: Instance, order: number, name: string, productId: number): Frame
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = order
	card.BackgroundColor3 = PANEL.tile
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = parent
	round(card, 14)
	edge(card, PANEL.tileEdge, 2)
	local buy = robuxButton(card, productId)
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -10)
	buy.Size = UDim2.new(1, -20, 0, 40)
	buy.TextSize = 20
	return card
end

--- The seven passes, PASSES_PER_ROW to a row. A bought one keeps its card and swaps
--- the button for a green OWNED, off the attribute GamePassService sets.
local function buildPasses(parent: Instance)
	section(parent, -10, "PASSES")
	local rows = math.ceil(#GamePasses.PASSES / PASSES_PER_ROW)
	local player = Players.LocalPlayer
	for r = 1, rows do
		local frame = row(parent, -10 + r, `Passes{r}`, PASS_H, PASSES_PER_ROW)
		for slot = 1, PASSES_PER_ROW do
			local index = (r - 1) * PASSES_PER_ROW + slot
			local pass = GamePasses.PASSES[index]
			if pass == nil then
				break
			end
			local card = Instance.new("Frame")
			card.Name = `Pass_{pass.key}`
			card.LayoutOrder = slot
			card.BackgroundColor3 = PANEL.tile
			card.BorderSizePixel = 0
			card.ZIndex = 12
			card.Parent = frame
			round(card, 14)
			edge(card, PANEL.tileEdge, 2)
			local art = Instance.new("ImageLabel")
			art.Name = "Art"
			art.BackgroundTransparency = 1
			art.Image = pass.image
			art.ScaleType = Enum.ScaleType.Fit
			art.AnchorPoint = Vector2.new(0.5, 0)
			art.Size = UDim2.fromOffset(92, 92)
			art.Position = UDim2.new(0.5, 0, 0, 8)
			art.ZIndex = 13
			art.Parent = card
			inked(card, {
				Name = "PassName",
				Text = pass.name,
				Font = PANEL.headline,
				TextSize = 20,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -12, 0, 26),
				Position = UDim2.fromOffset(6, 104),
				ZIndex = 14,
			})
			inked(card, {
				Name = "Blurb",
				Text = pass.blurb,
				Font = PANEL.label,
				TextSize = 15,
				TextWrapped = true,
				TextColor3 = PANEL.dim,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -12, 0, 34),
				Position = UDim2.fromOffset(6, 132),
				ZIndex = 14,
			})
			local buy = robuxButton(card, pass.id, true)
			buy.AnchorPoint = Vector2.new(0.5, 1)
			buy.Position = UDim2.new(0.5, 0, 1, -10)
			buy.Size = UDim2.new(1, -20, 0, 40)
			buy.TextSize = 18
			local attr = GamePasses.attr(pass.key)
			local function refresh()
				local owned = player:GetAttribute(attr) == true
				if owned then
					buy.Active = false
					buy.Text = "OWNED"
					buy.BackgroundColor3 = PANEL.buyOwned
				elseif pass.id ~= 0 and not buy.Active then
					buy.Active = true
					buy.Text = buy:GetAttribute("Price") or "R$"
					buy.BackgroundColor3 = PANEL.buy
				end
			end
			player:GetAttributeChangedSignal(attr):Connect(refresh)
			refresh()
		end
	end
end

--- The four cash packs. The bundle grows with the pack, so the row reads as a ladder.
local function buildCash(parent: Instance)
	section(parent, 2, "CASH")
	local frame = row(parent, 3, "Cash", CASH_H, #ShopProducts.CASH)
	for index, pack in ShopProducts.CASH do
		local card = tile(frame, index, `Cash{index}`, pack.id)
		local icon = Instance.new("ImageLabel")
		icon.Name = "Bundle"
		icon.BackgroundTransparency = 1
		icon.Image = Artwork.IMAGE.cashBundle
		local size = 44 + index * 8
		icon.Size = UDim2.fromOffset(size, size)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0, 46)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 13
		icon.Parent = card
		inked(card, {
			Name = "Amount",
			Text = pack.label,
			Font = PANEL.headline,
			TextSize = 26,
			TextColor3 = PANEL.cash,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 82),
			ZIndex = 14,
		})
	end
end

--- The two Mystery crates. The art is the best crate of the kind: the top of the roll.
local function buildCrates(parent: Instance)
	section(parent, 4, "CRATES")
	local frame = row(parent, 5, "Crates", CRATE_H, #ShopProducts.CRATES)
	for index, product in ShopProducts.CRATES do
		local card = tile(frame, index, `Crate{index}`, product.id)
		local well = Instance.new("Frame")
		well.Name = "Art"
		well.BackgroundTransparency = 1
		well.Size = UDim2.new(1, -20, 0, 92)
		well.Position = UDim2.fromOffset(10, 8)
		well.ZIndex = 13
		well.Parent = card
		local best = `{product.kind}{#product.weights}`
		if Crates.has(best) then
			local viewport = ItemArt.newViewport(well)
			viewport.ZIndex = 13
			-- Framed to the well's real aspect, so it is (re)painted whenever the grid
			-- lays the card out; at build time the well has no width yet.
			local function paint()
				local size = well.AbsoluteSize
				if size.X < 1 or size.Y < 1 then
					return
				end
				ItemArt.clear(viewport)
				ItemArt.paint(viewport, { uid = `shop-{best}`, crateId = best }, size.X / size.Y)
			end
			well:GetPropertyChangedSignal("AbsoluteSize"):Connect(paint)
			task.defer(paint)
		end
		inked(card, {
			Name = "CrateName",
			Text = product.name,
			Font = PANEL.headline,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -12, 0, 24),
			Position = UDim2.fromOffset(6, 100),
			ZIndex = 14,
		})
		local first = Crates.get(`{product.kind}1`).short
		local last = if Crates.has(best) then Crates.get(best).short else first
		inked(card, {
			Name = "Range",
			Text = `Random: {first} to {last}`,
			Font = PANEL.label,
			TextSize = 14,
			TextColor3 = PANEL.dim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -12, 0, 18),
			Position = UDim2.fromOffset(6, 124),
			ZIndex = 14,
		})
	end
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
	panel.Position = UDim2.new(0.5, 0, 0.5, -PANEL_LIFT)
	panel.Size = UDim2.new(0, PANEL_W, 1, -110)
	local cap = Instance.new("UISizeConstraint")
	cap.MaxSize = Vector2.new(PANEL_W, PANEL_H)
	cap.Parent = panel
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

	-- Everything under the header scrolls, so a short screen loses nothing.
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, HEADER_H)
	body.Size = UDim2.new(1, 0, 1, -HEADER_H)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 6
	body.ScrollBarImageColor3 = PANEL.tileEdge
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.ZIndex = 11
	body.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, GAP)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body
	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, 4)
	bodyPad.PaddingLeft = UDim.new(0, 4)
	bodyPad.PaddingBottom = UDim.new(0, 4)
	bodyPad.Parent = body

	buildPasses(body)
	buildCloverCard(body)
	buildCash(body)
	buildCrates(body)

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
		iconDrop = TILE_ICON_DROP,
		onActivated = Shop.toggle,
		leftRow = 2,
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
