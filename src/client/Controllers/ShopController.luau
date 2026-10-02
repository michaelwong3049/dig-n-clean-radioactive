--[[
	ShopController.lua — the Shop tile, and the panel it opens. The tile is the
	top-right square of the right-edge 2x2 grid, built by HudTile like the other three.

	THE PANEL IS THE ROBUX SHOP (PLAN §11), not the gear stalls: gear is bought by
	walking up to a stall on the plaza (StationController). One scrolling body, five
	sections: the PACKS (Config/Packs) first, two once-per-player bundles that turn to
	OWNED off the Player attribute PackService writes; the PASSES (Config/GamePasses), seven permanent upgrades on top, which
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
local Packs = require(ReplicatedStorage.Shared.Config.Packs)
local CashBoost = require(ReplicatedStorage.Shared.Config.CashBoost)

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

-- The panel. BRIGHT, on request (2026-10-02): a sky-blue to violet wash behind
-- everything, and every card in its own saturated colour with a gloss gradient,
-- instead of the FIELD slate it started as. White ink-outlined text reads on all of it.
local PANEL = {
	card = Color3.fromHex("2EA552"),
	cardEdge = Color3.fromHex("1A1A1A"),
	well = Color3.fromHex("1E7A3A"),
	light = Color3.fromHex("DDF8D2"),
	dim = Color3.fromHex("F1F5FF"),
	-- StationController's FIELD.robux: every Robux button in the game is this purple.
	buy = Color3.fromHex("7B3FE4"),
	buyHover = Color3.fromHex("9257F5"),
	-- An owned pass's button: the clover's green, so "you have this" reads at a glance.
	buyOwned = Color3.fromHex("2F9E4A"),
	-- Card colours. Each pass has its own (PASS_TINT); cash is green, crates by kind.
	tileEdge = Color3.fromHex("1A1A1A"),
	cashTile = Color3.fromHex("2EA552"),
	nukeTile = Color3.fromHex("E8711C"),
	liquidTile = Color3.fromHex("1E88E5"),
	cash = Color3.fromHex("C8FF8A"),
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
local SERVER_BOOST_H = 132
-- The Violet Aurora's purple, so the card reads as "the server event".
local SERVER_BOOST_TINT = Color3.fromHex("7A3FC8")
local SECTION_H = 30
-- The CASH cards: green with a sunburst behind a picture that grows up the ladder
-- (bundle, stack, money bag, vault), the amount big over the art's foot and a green R$
-- button underneath, after a cash-shop reference the user sent (2026-10-02). Three to a
-- row; a leftover card runs the full width.
local CASH_H = 236
local CASH_PER_ROW = 3
local CASH_CARD = {
	top = Color3.fromHex("5BD63E"),
	middle = Color3.fromHex("8CF06A"),
	edge = Color3.fromHex("2B2B33"),
	buy = Color3.fromHex("6FDB2A"),
	buyHover = Color3.fromHex("86EC45"),
	buyEdge = Color3.fromHex("1F6E12"),
}
local CRATE_H = 216
-- Every Robux button: the R$ is Roblox's own Robux glyph (private-use U+E002, which
-- every Roblox font draws as the hexagon icon), big enough to read across the room.
local ROBUX = utf8.char(0xE002)
local BUY_H = 54
local BUY_TEXT = 28
-- Each pass card's colour, keyed by Config/GamePasses key, picked to sit behind its picture.
local PASS_TINT: { [string]: Color3 } = {
	cash = Color3.fromHex("2EA552"),
	luck = Color3.fromHex("17A589"),
	digPower = Color3.fromHex("E0413A"),
	speed = Color3.fromHex("F0A20F"),
	backpack = Color3.fromHex("EE7A1E"),
	bombDamage = Color3.fromHex("D81B60"),
	instantClean = Color3.fromHex("1E88E5"),
}
-- Flat pictures of crates (art/crates), drawn instead of the live 3D model so the card
-- never sits blank waiting on meshes. A crate with none falls back to the viewport.
local CRATE_IMAGE: { [string]: string } = {
	nuke3 = "rbxassetid://117104417851806", -- Void Nuke Crate
	liquid2 = "rbxassetid://107641217252136", -- Isotope Chem Crate
}
-- The Mystery crates have no picture of their own yet; each borrows one of its kind's.
local MYSTERY_IMAGE: { [string]: string } = {
	nuke = CRATE_IMAGE.nuke3,
	liquid = CRATE_IMAGE.liquid2,
}

--- A crate picture filling `well`, `inset` in from its edges.
local function crateImage(well: Frame, image: string, inset: number, z: number)
	local picture = Instance.new("ImageLabel")
	picture.Name = "Picture"
	picture.BackgroundTransparency = 1
	picture.Image = image
	picture.ScaleType = Enum.ScaleType.Fit
	picture.AnchorPoint = Vector2.new(0.5, 0.5)
	picture.Position = UDim2.fromScale(0.5, 0.5)
	picture.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	picture.ZIndex = z
	picture.Parent = well
end
local PASS_H = 200
local PASS_ART = 140
-- Each pack's card colour, keyed by Config/Packs key: warm for the cheap one, royal
-- for the big one.
local PACK_TINT: { [string]: Color3 } = {
	starter = Color3.fromHex("F08A12"),
	pro = Color3.fromHex("7A2FD6"),
}
local PACK_H = 236
local PACK_ART = 104
local PASSES_PER_ROW = 2
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

--- A top-to-bottom gloss over a card: full colour at the top, a shade darker below.
local function gloss(parent: Instance)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	gradient.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

-- One pass over the card, then a rest before the next.
local SHINE = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 2.6)

--- A white glint that sweeps across `card` on a loop: a rounded white sheet the card's
--- size, masked to a narrow diagonal band by a gradient whose offset slides across.
--- `delay` staggers neighbouring cards so they don't all flash at once.
local function shine(card: GuiObject, corner: number, delay: number)
	local sheet = Instance.new("Frame")
	sheet.Name = "Shine"
	sheet.Size = UDim2.fromScale(1, 1)
	sheet.BackgroundColor3 = Color3.new(1, 1, 1)
	sheet.BorderSizePixel = 0
	sheet.ZIndex = 15
	sheet.Parent = card
	round(sheet, corner)
	local band = Instance.new("UIGradient")
	band.Rotation = 20
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	band.Offset = Vector2.new(-1, 0)
	band.Parent = sheet
	task.delay(delay, function()
		TweenService:Create(band, SHINE, { Offset = Vector2.new(1, 0) }):Play()
	end)
end

--- A purple R$ button for `productId`, parented to `parent`. Its price is read off the
--- product, so a dashboard change needs no code change; the bare glyph stands in until then. An
--- id of 0 (not set up on the dashboard) gives a grey COMING SOON that does nothing.
--- `isPass` sells a game pass (Config/GamePasses) instead of a developer product.
--- `color` / `hover` swap the purple for another pair (the cash cards' green).
local function robuxButton(parent: Instance, productId: number, isPass: boolean?, color: Color3?, hover: Color3?): TextButton
	local live = productId ~= 0
	local base = color or PANEL.buy
	local lit = hover or PANEL.buyHover
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AutoButtonColor = false
	buy.BackgroundColor3 = if live then base else PANEL.off
	buy.Font = PANEL.headline
	buy.TextSize = if live then 24 else 18
	buy.TextColor3 = PANEL.white
	buy.Text = if live then ROBUX else "COMING SOON"
	buy.ZIndex = 15
	buy.Parent = parent
	round(buy, 12)
	-- A touch smaller than the slot each card gives it (scales about its AnchorPoint).
	local shrink = Instance.new("UIScale")
	shrink.Scale = 0.9
	shrink.Parent = buy
	-- Border mode: on a TextButton the default (Contextual) stroke only outlines the text.
	local buyEdge = Instance.new("UIStroke")
	buyEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buyEdge.Color = Color3.new(0, 0, 0)
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
			buy:SetAttribute("Price", `{ROBUX} {info.PriceInRobux}`)
			if buy.Active then
				buy.Text = `{ROBUX} {info.PriceInRobux}`
			end
		end
	end)
	-- An owned pass turns its button off (Active = false); hover and click both respect it.
	buy.MouseEnter:Connect(function()
		if buy.Active then
			TweenService:Create(buy, HOVER, { BackgroundColor3 = lit }):Play()
		end
	end)
	buy.MouseLeave:Connect(function()
		if buy.Active then
			TweenService:Create(buy, HOVER, { BackgroundColor3 = base }):Play()
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
	card.LayoutOrder = 0
	card.BackgroundColor3 = PANEL.card
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = parent
	round(card, 16)
	edge(card, PANEL.cardEdge, 3)
	gloss(card)

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
	buy.Size = UDim2.fromOffset(230, BUY_H + 4)
	buy.TextSize = BUY_TEXT + 4
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position = UDim2.new(1, -16, 1, -14)
end

--- The Server Luck Boost card under the clover: everyone on the server gets the
--- Violet Aurora's luck for SERVER_SECONDS, and the buyer is named to all of them.
local function buildServerBoostCard(parent: Frame)
	local card = Instance.new("Frame")
	card.Name = "ServerLuckBoost"
	card.Size = UDim2.new(1, -8, 0, SERVER_BOOST_H)
	card.LayoutOrder = 1
	card.BackgroundColor3 = SERVER_BOOST_TINT
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = parent
	round(card, 16)
	edge(card, PANEL.cardEdge, 3)
	gloss(card)

	local minutes = math.floor(LuckBoost.SERVER_SECONDS / 60)
	inked(card, {
		Name = "Name",
		Text = "SERVER LUCK BOOST",
		Font = PANEL.headline,
		TextSize = 30,
		Size = UDim2.new(1, -280, 0, 36),
		Position = UDim2.fromOffset(20, 14),
		ZIndex = 14,
	})
	inked(card, {
		Name = "Pitch",
		Text = `{LuckBoost.MULT}x LUCK for EVERYONE here, {minutes} minutes`,
		Font = PANEL.label,
		TextSize = 20,
		TextColor3 = PANEL.light,
		Size = UDim2.new(1, -280, 0, 24),
		Position = UDim2.fromOffset(20, 52),
		ZIndex = 14,
	})
	inked(card, {
		Name = "Details",
		Text = `Starts the {LuckBoost.EVENT_NAME}, or adds {minutes} min to it. Stacks with your clover.`,
		Font = PANEL.label,
		TextSize = 16,
		TextColor3 = PANEL.dim,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -280, 0, 40),
		Position = UDim2.fromOffset(20, 82),
		ZIndex = 14,
	})

	local buy = robuxButton(card, LuckBoost.SERVER_PRODUCT_ID)
	buy.Size = UDim2.fromOffset(230, BUY_H + 4)
	buy.TextSize = BUY_TEXT + 4
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, -16, 0.5, 0)
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
local function tile(parent: Instance, order: number, name: string, productId: number, color: Color3): Frame
	local card = Instance.new("Frame")
	card.Name = name
	card.LayoutOrder = order
	card.BackgroundColor3 = color
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = parent
	round(card, 14)
	edge(card, PANEL.tileEdge, 3)
	gloss(card)
	local buy = robuxButton(card, productId)
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -10)
	buy.Size = UDim2.new(1, -16, 0, BUY_H)
	buy.TextSize = BUY_TEXT
	return card
end

--- $200K / $5M: the Shop's own short money, matching the cash packs' labels.
local function shortCash(amount: number): string
	local function trim(n: number): string
		return (string.format("%.1f", n):gsub("%.0$", ""))
	end
	if amount >= 1_000_000 then
		return `${trim(amount / 1_000_000)}M`
	elseif amount >= 1_000 then
		return `${trim(amount / 1_000)}K`
	end
	return `${amount}`
end

--- "30 min" / "1 hr".
local function duration(seconds: number): string
	if seconds >= 3600 and seconds % 3600 == 0 then
		return `{seconds // 3600} hr`
	end
	return `{math.floor(seconds / 60)} min`
end

--- What is inside a pack, one line each, in the order the user listed them.
local function packLines(pack: Packs.Pack): { string }
	local lines = {}
	if pack.cash > 0 then
		table.insert(lines, `{shortCash(pack.cash)} Cash`)
	end
	for _, entry in Packs.crateCounts(pack) do
		table.insert(lines, `{entry.count}x {Crates.get(entry.crateId).name}`)
	end
	if pack.luckSeconds > 0 then
		table.insert(lines, `{duration(pack.luckSeconds)} {LuckBoost.MULT}x Luck`)
	end
	if pack.cashBoostSeconds > 0 then
		table.insert(lines, `{duration(pack.cashBoostSeconds)} {CashBoost.MULT}x Cash`)
	end
	return lines
end

--- The two packs, one full-width row each at the top. Art on the left (the pack's best crate with
--- a cash bundle on it), contents on the right, the R$ button along the bottom. A bought
--- pack keeps its card and its button turns to a green OWNED, like a pass.
local function buildPacks(parent: Instance)
	section(parent, -30, "PACKS")
	local player = Players.LocalPlayer
	for index, pack in Packs.PACKS do
		local frame = row(parent, -30 + index, `Packs{index}`, PACK_H, 1)
		local card = Instance.new("Frame")
		card.Name = `Pack_{pack.key}`
		card.LayoutOrder = index
		card.BackgroundColor3 = PACK_TINT[pack.key] or PANEL.cashTile
		card.BorderSizePixel = 0
		card.ZIndex = 12
		card.Parent = frame
		round(card, 16)
		edge(card, PANEL.tileEdge, 3)
		gloss(card)

		inked(card, {
			Name = "PackName",
			Text = string.upper(pack.name),
			Font = PANEL.headline,
			TextSize = 30,
			Size = UDim2.new(1, -24, 0, 36),
			Position = UDim2.fromOffset(14, 10),
			ZIndex = 14,
		})
		inked(card, {
			Name = "Once",
			Text = "ONE TIME ONLY",
			Font = PANEL.label,
			TextSize = 14,
			TextColor3 = PANEL.cash,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(140, 18),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 20),
			ZIndex = 14,
		})

		local well = Instance.new("Frame")
		well.Name = "Art"
		well.Size = UDim2.fromOffset(PACK_ART, PACK_ART)
		well.Position = UDim2.fromOffset(14, 54)
		well.BackgroundColor3 = Color3.new(0, 0, 0)
		well.BackgroundTransparency = 0.75
		well.BorderSizePixel = 0
		well.ZIndex = 13
		well.Parent = card
		round(well, 14)
		edge(well, PANEL.ink, 3)
		-- The best crate in the pack with a picture; failing that, the best one drawn live
		-- (the last one listed is the top of each ladder).
		local pictured
		for i = #pack.crates, 1, -1 do
			if CRATE_IMAGE[pack.crates[i]] then
				pictured = pack.crates[i]
				break
			end
		end
		local best = pack.crates[#pack.crates]
		if pictured then
			crateImage(well, CRATE_IMAGE[pictured], 6, 14)
		elseif best and Crates.has(best) then
			local viewport = ItemArt.newViewport(well)
			viewport.ZIndex = 14
			local function paint()
				local size = well.AbsoluteSize
				if size.X < 1 or size.Y < 1 then
					return
				end
				ItemArt.clear(viewport)
				ItemArt.paint(viewport, { uid = `pack-{pack.key}`, crateId = best }, size.X / size.Y)
			end
			well:GetPropertyChangedSignal("AbsoluteSize"):Connect(paint)
			task.defer(paint)
		end
		local bundle = Instance.new("ImageLabel")
		bundle.Name = "Bundle"
		bundle.BackgroundTransparency = 1
		bundle.Image = Artwork.IMAGE.cashBundle
		bundle.ScaleType = Enum.ScaleType.Fit
		bundle.Size = UDim2.fromOffset(64, 64)
		bundle.AnchorPoint = Vector2.new(0, 1)
		bundle.Position = UDim2.new(0, -10, 1, 12)
		bundle.Rotation = -10
		bundle.ZIndex = 16
		bundle.Parent = well

		local textLeft = 14 + PACK_ART + 14
		inked(card, {
			Name = "Contents",
			Text = "• " .. table.concat(packLines(pack), "\n• "),
			Font = PANEL.label,
			TextSize = 19,
			TextColor3 = PANEL.white,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			LineHeight = 1.1,
			Size = UDim2.new(1, -textLeft - 10, 0, PACK_ART + 8),
			Position = UDim2.fromOffset(textLeft, 56),
			ZIndex = 14,
		})

		local buy = robuxButton(card, pack.id)
		buy.AnchorPoint = Vector2.new(0.5, 1)
		buy.Position = UDim2.new(0.5, 0, 1, -12)
		buy.Size = UDim2.new(1, -24, 0, BUY_H + 4)
		buy.TextSize = BUY_TEXT + 4
		local attr = Packs.attr(pack.key)
		local function refresh()
			if player:GetAttribute(attr) == true then
				buy.Active = false
				buy.Text = "OWNED"
				buy.BackgroundColor3 = PANEL.buyOwned
			elseif pack.id ~= 0 and not buy.Active then
				buy.Active = true
				buy.Text = buy:GetAttribute("Price") or ROBUX
				buy.BackgroundColor3 = PANEL.buy
			end
		end
		player:GetAttributeChangedSignal(attr):Connect(refresh)
		refresh()
	end
end

--- The seven passes, PASSES_PER_ROW to a row. A bought one keeps its card and swaps
--- the button for a green OWNED, off the attribute GamePassService sets.
local function buildPasses(parent: Instance)
	section(parent, -10, "PASSES")
	-- An odd count leaves the first pass (2x Cash) alone on a full-width row up top.
	local count = #GamePasses.PASSES
	local lead = count % PASSES_PER_ROW
	local spans = {}
	if lead > 0 then
		table.insert(spans, { first = 1, last = lead })
	end
	for first = lead + 1, count, PASSES_PER_ROW do
		table.insert(spans, { first = first, last = math.min(first + PASSES_PER_ROW - 1, count) })
	end
	local player = Players.LocalPlayer
	for r, span in spans do
		local frame = row(parent, -10 + r, `Passes{r}`, PASS_H, span.last - span.first + 1)
		for index = span.first, span.last do
			local slot = index - span.first + 1
			local pass = GamePasses.PASSES[index]
			local card = Instance.new("Frame")
			card.Name = `Pass_{pass.key}`
			card.LayoutOrder = slot
			card.BackgroundColor3 = PASS_TINT[pass.key] or PANEL.cashTile
			card.BorderSizePixel = 0
			card.ZIndex = 12
			card.Parent = frame
			round(card, 14)
			edge(card, PANEL.tileEdge, 3)
			gloss(card)
			shine(card, 14, index * 0.3)
			-- White light rays poking out from behind the picture, like the cash cards.
			card.ClipsDescendants = true
			local rays = Instance.new("ImageLabel")
			rays.Name = "Rays"
			rays.BackgroundTransparency = 1
			rays.Image = Artwork.IMAGE.sunburst
			rays.ImageTransparency = 0.45
			rays.ScaleType = Enum.ScaleType.Fit
			rays.AnchorPoint = Vector2.new(0.5, 0.5)
			rays.Position = UDim2.fromOffset(10 + PASS_ART / 2, 46 + PASS_ART / 2)
			rays.Size = UDim2.fromOffset(PASS_ART * 2, PASS_ART * 2)
			rays.ZIndex = 12
			rays.Parent = card
			local art = Instance.new("ImageLabel")
			art.Name = "Art"
			art.BackgroundTransparency = 1
			-- 2x Speed wears the HUD's walk-speed shoe, with an x2 beside it.
			art.Image = if pass.key == "speed" then Artwork.IMAGE.speedShoe else pass.image
			art.ScaleType = Enum.ScaleType.Fit
			art.Size = UDim2.fromOffset(PASS_ART, PASS_ART)
			art.Position = UDim2.fromOffset(10, 46)
			art.ZIndex = 13
			art.Parent = card
			if pass.key == "speed" then
				art.Size = UDim2.fromOffset(PASS_ART - 30, PASS_ART - 30)
				art.Position = UDim2.fromOffset(6, 61)
				inked(card, {
					Name = "Times",
					Text = "x2",
					Font = PANEL.headline,
					TextSize = 40,
					TextColor3 = PANEL.white,
					Size = UDim2.fromOffset(56, 44),
					Position = UDim2.fromOffset(PASS_ART - 30, 94),
					ZIndex = 14,
				})
			end
			inked(card, {
				Name = "PassName",
				Text = pass.name,
				Font = PANEL.headline,
				TextSize = 30,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -24, 0, 34),
				Position = UDim2.fromOffset(12, 8),
				ZIndex = 14,
			})
			inked(card, {
				Name = "Blurb",
				Text = pass.blurb,
				Font = PANEL.label,
				TextSize = 22,
				TextWrapped = true,
				TextColor3 = PANEL.white,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, -PASS_ART - 30, 0, 70),
				Position = UDim2.fromOffset(PASS_ART + 20, 52),
				ZIndex = 14,
			})
			local buy = robuxButton(card, pass.id, true)
			-- Name top-left, picture down the left, blurb and the R$ button stacked on the right.
			buy.AnchorPoint = Vector2.new(1, 1)
			buy.Position = UDim2.new(1, -10, 1, -12)
			buy.Size = UDim2.new(1, -PASS_ART - 30, 0, BUY_H + 6)
			buy.TextSize = BUY_TEXT + 4
			local attr = GamePasses.attr(pass.key)
			local function refresh()
				local owned = player:GetAttribute(attr) == true
				if owned then
					buy.Active = false
					buy.Text = "OWNED"
					buy.BackgroundColor3 = PANEL.buyOwned
				elseif pass.id ~= 0 and not buy.Active then
					buy.Active = true
					buy.Text = buy:GetAttribute("Price") or ROBUX
					buy.BackgroundColor3 = PANEL.buy
				end
			end
			player:GetAttributeChangedSignal(attr):Connect(refresh)
			refresh()
		end
	end
end

--- The four cash packs, CASH_PER_ROW to a row; the picture grows with the pack, so the
--- cards read as a ladder.
local function buildCash(parent: Instance)
	section(parent, 2, "CASH")
	local packs = ShopProducts.CASH
	local rows = math.ceil(#packs / CASH_PER_ROW)
	for rowIndex = 1, rows do
		local first = (rowIndex - 1) * CASH_PER_ROW + 1
		local last = math.min(first + CASH_PER_ROW - 1, #packs)
		local frame = row(parent, 2 + rowIndex, `Cash{rowIndex}`, CASH_H, last - first + 1)
		for index = first, last do
			local pack = packs[index]
			local card = Instance.new("Frame")
			card.Name = `Cash{index}`
			card.LayoutOrder = index
			card.BackgroundColor3 = Color3.new(1, 1, 1)
			card.BorderSizePixel = 0
			card.ClipsDescendants = true
			card.ZIndex = 12
			card.Parent = frame
			round(card, 14)
			edge(card, CASH_CARD.edge, 4)
			-- Brighter down the middle, where the rays come from.
			local shade = Instance.new("UIGradient")
			shade.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, CASH_CARD.top),
				ColorSequenceKeypoint.new(0.5, CASH_CARD.middle),
				ColorSequenceKeypoint.new(1, CASH_CARD.top),
			})
			shade.Parent = card

			local rays = Instance.new("ImageLabel")
			rays.Name = "Rays"
			rays.BackgroundTransparency = 1
			rays.Image = Artwork.IMAGE.sunburst
			rays.ImageTransparency = 0.45
			rays.ScaleType = Enum.ScaleType.Fit
			rays.AnchorPoint = Vector2.new(0.5, 0.5)
			rays.Position = UDim2.new(0.5, 0, 0, 82)
			rays.Size = UDim2.fromOffset(340, 340)
			rays.ZIndex = 12
			rays.Parent = card

			local art = Instance.new("ImageLabel")
			art.Name = "Bundle"
			art.BackgroundTransparency = 1
			art.Image = Artwork.IMAGE.shopCash[index] or Artwork.IMAGE.cashBundle
			art.ScaleType = Enum.ScaleType.Fit
			art.AnchorPoint = Vector2.new(0.5, 0)
			art.Position = UDim2.fromScale(0.5, 0)
			art.Size = UDim2.fromOffset(150, 150)
			art.ZIndex = 13
			art.Parent = card

			inked(card, {
				Name = "Amount",
				Text = pack.label,
				Font = PANEL.headline,
				TextSize = 38,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 42),
				Position = UDim2.fromOffset(0, 124),
				ZIndex = 14,
			})

			local buy = robuxButton(card, pack.id, false, CASH_CARD.buy, CASH_CARD.buyHover)
			buy.AnchorPoint = Vector2.new(0.5, 1)
			buy.Position = UDim2.new(0.5, 0, 1, -10)
			buy.Size = UDim2.new(1, -20, 0, BUY_H)
			buy.TextSize = BUY_TEXT + 4
			local box = Instance.new("UIStroke")
			box.Color = CASH_CARD.buyEdge
			box.Thickness = 3
			box.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			box.Parent = buy
			gloss(buy)
		end
	end
end

--- The two Mystery crates. The art is the best crate of the kind: the top of the roll.
local function buildCrates(parent: Instance)
	section(parent, 10, "CRATES")
	local frame = row(parent, 11, "Crates", CRATE_H, #ShopProducts.CRATES)
	for index, product in ShopProducts.CRATES do
		local card = tile(frame, index, `Crate{index}`, product.id, if product.kind == "liquid" then PANEL.liquidTile else PANEL.nukeTile)
		local well = Instance.new("Frame")
		well.Name = "Art"
		well.BackgroundTransparency = 1
		well.Size = UDim2.new(1, -20, 0, 92)
		well.Position = UDim2.fromOffset(10, 8)
		well.ZIndex = 13
		well.Parent = card
		local best = `{product.kind}{#product.weights}`
		if MYSTERY_IMAGE[product.kind] then
			crateImage(well, MYSTERY_IMAGE[product.kind], 0, 13)
		elseif Crates.has(best) then
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
	-- See-through black, so the world shows behind the cards.
	panel.BackgroundColor3 = Color3.new(0, 0, 0)
	panel.BackgroundTransparency = 0.35
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
	body.ScrollBarImageColor3 = PANEL.white
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

	buildPacks(body)
	buildPasses(body)
	buildCloverCard(body)
	buildServerBoostCard(body)
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
