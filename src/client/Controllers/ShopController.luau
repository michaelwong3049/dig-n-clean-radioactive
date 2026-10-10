--[[
	ShopController.lua — the Shop tile, and the panel it opens. The tile is the
	top-left square of the left-edge 2x3 grid, built by HudTile like the other five.

	THE PANEL IS THE ROBUX SHOP (PLAN §11), not the gear stalls: gear is bought by
	walking up to a stall on the plaza (StationController). One scrolling body: the
	NUKE PACK card (Config/NukePack) on top, a fixed five-nuke crate sold in x1/x3/x5/x10
	bundles; then five sections: the PACKS (Config/Packs), two once-per-player bundles that turn to
	OWNED off the Player attribute PackService writes; the PASSES (Config/GamePasses), seven permanent upgrades on top, which
	turn to OWNED off the Player attribute GamePassService writes; the SERVER LUCK BOOST
	(the Lucky Clover card beside it was removed 2026-10-10, on request); a CASH
	row of four packs (Config/ShopProducts, granted in EconomyService). The WALK SPEED
	packs that followed it were retired 2026-10-10 (on request): speed is bought at the
	Upgrades booth (Config/WalkSpeed). The Mystery crates that used to close the
	panel were retired 2026-10-05: their two products now sell the Fusion and Plasma
	crates on Base Camp's PREMIUM CRATES pad (Config/CrateShop). Every buy button is the gear
	cards' purple R$, so real money always looks the same. The client only ever
	PROMPTS the purchase -- the grant is ProductService's receipt handler on the server,
	so nothing here has to trust or wait on the prompt's own callback.

	With no product id configured (0) a card still shows, its button reads COMING SOON
	and does nothing.

	Its look is the gear panel's (StationController's FIELD): slate panel, the HUD's
	text on it (all Gotham Black, INK outlines).
]]

local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LuckBoost = require(ReplicatedStorage.Shared.Config.LuckBoost)
local ShopProducts = require(ReplicatedStorage.Shared.Config.ShopProducts)
local Crates = require(ReplicatedStorage.Shared.Config.Crates)
local GamePasses = require(ReplicatedStorage.Shared.Config.GamePasses)
local Packs = require(ReplicatedStorage.Shared.Config.Packs)
local NukePack = require(ReplicatedStorage.Shared.Config.NukePack)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local CashBoost = require(ReplicatedStorage.Shared.Config.CashBoost)
local GroupReward = require(ReplicatedStorage.Shared.Config.GroupReward)
local Net = require(ReplicatedStorage.Shared.Net)
local RobuxGift = require(script.Parent.RobuxGiftController)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)
local CloverArt = require(script.Parent.Parent.CloverArt)
local Studded = require(script.Parent.Parent.Studded)
local ItemArt = require(script.Parent.Parent.ItemArt)

local Shop = {}

-- THE SHOP TILE: the whole top row of the left-edge grid (HudTile, span 2), the basket.
local TILE_SLOT = 1
local TILE_COLOR = Color3.fromRGB(86, 212, 71)
local TILE_LIGHT = Color3.fromRGB(185, 245, 168)
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
	-- Every R$ button in the Shop is the gear shop buttons' pure green (on request,
	-- 2026-10-08; it was the purple every other Robux button wears). Purple stays on
	-- the gift buttons beside them (RobuxGiftController).
	buy = Color3.fromHex("5CFE01"),
	buyHover = Color3.fromHex("85FF01"),
	-- An owned pass's (or pack's) button: a deep green, so OWNED reads as done rather
	-- than as one more bright BUY.
	buyOwned = Color3.fromHex("1F6E12"),
	-- The CODES section's REDEEM button: not a Robux buy, so it keeps the old purple.
	redeem = Color3.fromHex("7B3FE4"),
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
-- TINTED GLASS: every card is its own colour, only lightly shaded and a touch
-- see-through. Brighter on request (2026-10-07), once the panel behind them wore the
-- studs: it was 0.5 shade / 0.3 see-through, which read muddy over the dark studs.
-- BRIGHTER again on request (2026-10-10): no shading at all and solid, so each card is
-- its own colour at full strength (it was 0.12 shade / 0.1 see-through).
local CARD_SHADE = 0 -- 0 = card colour as drawn, 1 = black
local CARD_SEE = 0 -- BackgroundTransparency of every card
local CARD_BRIGHT = 0.95 -- the lowest HSV value a card colour is drawn at

-- Each card also wears the gear shop cards' glossy L-studs (on request, 2026-10-07),
-- under everything else on it.
local function darkGlass(card: GuiObject, radius: number)
	-- Lifted to at least CARD_BRIGHT value, hue and saturation kept, so a mid-tone tint
	-- (the clover's 2EA552) shows as its bright self.
	local h, s, v = card.BackgroundColor3:ToHSV()
	card.BackgroundColor3 = Color3.fromHSV(h, s, math.max(v, CARD_BRIGHT)):Lerp(Color3.new(0, 0, 0), CARD_SHADE)
	card.BackgroundTransparency = CARD_SEE
	Studded.pattern(card, { radius = radius, bands = { 0.2, 0.47, 0.56, 0.64 }, bandTransparency = 0.55, glowTransparency = 0.72 })
end

local PANEL_W = 860
-- The panel's tallest; a short screen gets less, and the body scrolls.
local PANEL_H = 720
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
	-- The gear shop buttons' pure green (a reference button the user sent, 2026-10-04):
	-- its gradient's middle, lifting to its top on hover. PANEL.buy is the same green.
	buy = Color3.fromHex("5CFE01"),
	buyHover = Color3.fromHex("85FF01"),
	buyEdge = Color3.fromHex("1F6E12"),
}
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
	autoMagnet = Color3.fromHex("3A6FD0"),
	backpack = Color3.fromHex("EE7A1E"),
	bombDamage = Color3.fromHex("D81B60"),
	instantClean = Color3.fromHex("1E88E5"),
	health = Color3.fromHex("C2185B"),
}
-- Flat pictures of crates (Config/Crates `image`), drawn instead of the live 3D model so
-- the card never sits blank waiting on meshes. A crate with none falls back to the viewport.
local CRATE_IMAGE: { [string]: string } = Crates.IMAGES

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
local PACK_H = 222
-- THE NUKE PACK card (Config/NukePack), first in the body: the pack's crate big on the
-- left, its five prizes in rarity frames with their odds, and an xN R$ button per bundle.
local NUKE_PACK_H = 268
local NUKE_PACK_ART = 196
-- The prize tiles grow left to right, most likely (smallest) to rarest (biggest), on
-- request (2026-10-10), bottoms lined up. Sizes run evenly between these two.
local PRIZE_SMALL = Vector2.new(84, 92)
local PRIZE_BIG = Vector2.new(128, 132)
-- How far each prize tile's camera zooms in past ItemArt's fit. Kept under ItemArt's
-- own 1.12 margin so every nuke stays wholly in its frame (on request: a stepped zoom
-- up to x1.62 cropped the Kraken and the Fulgurite's lightning).
local PRIZE_ZOOM = 1.1
-- Storm violet on the left through a lightning-yellow middle to bright sea blue on the
-- right, for Storm vs Abyss (was fire red -> gold -> blue for Inferno vs Abyss).
local NUKE_PACK_STORM = Color3.fromHex("8A3CFF")
local NUKE_PACK_MID = Color3.fromHex("FFD23F")
local NUKE_PACK_SEA = Color3.fromHex("1EA0FF")
local PACK_ART = 96
local PASSES_PER_ROW = 2
local GAP = 12
-- Sits this far above dead centre: a touch above the true middle, on request (was 40).
local PANEL_LIFT = 20
local PAD = 20
local HEADER_H = 58
local ART = 170
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local panelFrame: Frame? = nil
local panelScale: UIScale? = nil
local codeRemote: any = nil

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

--- A top-to-bottom gloss over a card: full colour at the top, a touch darker below
--- (was 190 grey at the foot; lifted with the brighter cards, 2026-10-10).
local function gloss(parent: Instance)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(228, 228, 228))
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

--- A green R$ button for `productId`, parented to `parent`. Its price is read off the
--- product, so a dashboard change needs no code change; the bare glyph stands in until then. An
--- id of 0 (not set up on the dashboard) gives a grey COMING SOON that does nothing.
--- `isPass` sells a game pass (Config/GamePasses) instead of a developer product.
--- `color` / `hover` swap the green for another pair.
local function robuxButton(parent: Instance, productId: number, isPass: boolean?, color: Color3?, hover: Color3?): TextButton
	local live = productId ~= 0
	local base = color or PANEL.buy
	local lit = hover or PANEL.buyHover
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AutoButtonColor = false
	buy.BackgroundColor3 = if live then base else PANEL.off
	buy.Font = PANEL.headline
	buy.TextSize = if live then 28 else 18
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
	-- A second, Contextual stroke outlines the R$ glyph and price so they read heavy.
	local buyText = Instance.new("UIStroke")
	buyText.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	buyText.Color = Color3.new(0, 0, 0)
	buyText.Thickness = 3
	buyText.LineJoinMode = Enum.LineJoinMode.Round
	buyText.Parent = buy
	Studded.button(buy, 12)
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
			-- Bought for yourself: forget any gift this product was pressed for earlier.
			RobuxGift.clear()
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
		end
	end)
	return buy
end

--- The Server Luck Boost card: everyone on the server gets the
--- Violet Aurora's luck for SERVER_SECONDS, and the buyer is named to all of them.
local function buildServerBoostCard(parent: Frame)
	local card = Instance.new("Frame")
	card.Name = "ServerLuckBoost"
	card.Size = UDim2.new(1, -8, 0, SERVER_BOOST_H)
	card.LayoutOrder = -18
	card.BackgroundColor3 = SERVER_BOOST_TINT
	darkGlass(card, 16)
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = parent
	round(card, 16)
	edge(card, PANEL.cardEdge, 3)
	gloss(card)

	-- A purple clover in a small well on the left: purple is the server-wide aurora's colour.
	local wellSize = SERVER_BOOST_H - 28
	local well = Instance.new("Frame")
	well.Name = "Art"
	well.Size = UDim2.fromOffset(wellSize, wellSize)
	well.Position = UDim2.new(0, 16, 0.5, 0)
	well.AnchorPoint = Vector2.new(0, 0.5)
	well.BackgroundColor3 = PANEL.well
	well.BorderSizePixel = 0
	well.ZIndex = 13
	well.Parent = card
	round(well, 12)
	edge(well, PANEL.ink, 3)
	local clover = CloverArt.build(well, wellSize - 20, 14, CloverArt.PURPLE)
	clover.AnchorPoint = Vector2.new(0.5, 0.5)
	clover.Position = UDim2.fromScale(0.5, 0.5)
	clover.Rotation = -8
	local textLeft = 16 + wellSize + 16

	local minutes = math.floor(LuckBoost.SERVER_SECONDS / 60)
	inked(card, {
		Name = "Name",
		Text = "SERVER LUCK BOOST",
		Font = PANEL.headline,
		TextSize = 30,
		Size = UDim2.new(1, -textLeft - 260, 0, 36),
		Position = UDim2.fromOffset(textLeft, 14),
		ZIndex = 14,
	})
	inked(card, {
		Name = "Pitch",
		Text = `{LuckBoost.MULT}x LUCK for EVERYONE here, {minutes} minutes`,
		Font = PANEL.label,
		TextSize = 20,
		TextColor3 = PANEL.light,
		Size = UDim2.new(1, -textLeft - 260, 0, 24),
		Position = UDim2.fromOffset(textLeft, 52),
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
		Size = UDim2.new(1, -textLeft - 260, 0, 40),
		Position = UDim2.fromOffset(textLeft, 82),
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

--- The two packs, side by side on one row at the top. Art on the left (the pack's best crate
--- with a cash bundle on it), contents on the right, the R$ button along the bottom. A bought
--- pack keeps its card and its button turns to a green OWNED, like a pass.
local function buildPacks(parent: Instance)
	section(parent, -30, "PACKS")
	local player = Players.LocalPlayer
	local frame = row(parent, -29, "Packs", PACK_H, #Packs.PACKS)
	for index, pack in Packs.PACKS do
		local card = Instance.new("Frame")
		card.Name = `Pack_{pack.key}`
		card.LayoutOrder = index
		card.BackgroundColor3 = PACK_TINT[pack.key] or PANEL.cashTile
		darkGlass(card, 16)
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
			TextSize = 26,
			Size = UDim2.new(1, -24, 0, 32),
			Position = UDim2.fromOffset(14, 10),
			ZIndex = 14,
		})
		inked(card, {
			Name = "Once",
			Text = "ONE TIME ONLY",
			Font = PANEL.label,
			TextSize = 13,
			TextColor3 = PANEL.cash,
			TextXAlignment = Enum.TextXAlignment.Right,
			Size = UDim2.fromOffset(110, 16),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 18),
			ZIndex = 14,
		})

		local well = Instance.new("Frame")
		well.Name = "Art"
		well.Size = UDim2.fromOffset(PACK_ART, PACK_ART)
		well.Position = UDim2.fromOffset(14, 48)
		well.BackgroundColor3 = Color3.new(0, 0, 0)
		well.BackgroundTransparency = 0.75
		well.BorderSizePixel = 0
		well.ZIndex = 13
		well.Parent = card
		round(well, 14)
		edge(well, PANEL.ink, 3)
		-- The pack's own picture (Config/Packs `image`) when it has one. Otherwise the
		-- best crate in the pack with a picture; failing that, the best one drawn live
		-- (the last one listed is the top of each ladder), with a cash bundle on it.
		if pack.image then
			crateImage(well, pack.image, 4, 14)
		else
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
			bundle.Size = UDim2.fromOffset(56, 56)
			bundle.AnchorPoint = Vector2.new(0, 1)
			bundle.Position = UDim2.new(0, -10, 1, 12)
			bundle.Rotation = -10
			bundle.ZIndex = 16
			bundle.Parent = well
		end

		local textLeft = 14 + PACK_ART + 14
		inked(card, {
			Name = "Contents",
			Text = "• " .. table.concat(packLines(pack), "\n• "),
			Font = PANEL.label,
			TextSize = 16,
			TextColor3 = PANEL.white,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			LineHeight = 1.05,
			Size = UDim2.new(1, -textLeft - 10, 0, PACK_ART + 12),
			Position = UDim2.fromOffset(textLeft, 48),
			ZIndex = 14,
		})

		local buy = robuxButton(card, pack.id)
		local gift = RobuxGift.button(card, pack.id)
		buy.AnchorPoint = Vector2.new(0, 1)
		buy.Position = UDim2.new(0, 10, 1, -10)
		buy.Size = UDim2.new(1, -20 - (if gift then BUY_H + 4 else 0), 0, BUY_H)
		buy.TextSize = BUY_TEXT
		if gift then
			gift.AnchorPoint = Vector2.new(1, 1)
			gift.Position = UDim2.new(1, -10, 1, -10)
			gift.Size = UDim2.fromOffset(BUY_H, BUY_H)
		end
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

--- "44%" / "5%" / "0.5%".
local function percent(p: number): string
	local pct = p * 100
	if pct >= 1 then
		return `{math.floor(pct + 0.5)}%`
	end
	return `{(string.format("%.1f", pct):gsub("%.0$", ""))}%`
end

--- The NUKE PACK card: title across the top, the pack crate on the left, its prizes
--- (most likely first) each in a frame of its rarity's colour with the odds in the
--- corner, and one R$ button per bundle along the bottom, "xN" on its shoulder.
local function buildNukePack(parent: Instance)
	local crateId = NukePack.crateId
	if not Crates.has(crateId) then
		return
	end
	local def = Crates.get(crateId)

	local card = Instance.new("Frame")
	card.Name = "NukePack"
	card.LayoutOrder = -40
	card.Size = UDim2.new(1, -8, 0, NUKE_PACK_H)
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = parent
	round(card, 16)
	edge(card, PANEL.tileEdge, 4)
	local wash = Instance.new("UIGradient")
	wash.Rotation = 20
	wash.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, NUKE_PACK_STORM),
		ColorSequenceKeypoint.new(0.5, NUKE_PACK_MID),
		ColorSequenceKeypoint.new(1, NUKE_PACK_SEA),
	})
	wash.Parent = card
	Studded.pattern(card, { radius = 16, bands = { 0.2, 0.47, 0.56, 0.64 }, bandTransparency = 0.7, glowTransparency = 0.8 })
	shine(card, 16, 0)

	inked(card, {
		Name = "PackName",
		Text = string.upper(def.name),
		Font = PANEL.headline,
		TextSize = 32,
		Size = UDim2.new(1, -28, 0, 38),
		Position = UDim2.fromOffset(14, 8),
		ZIndex = 14,
	})

	-- The pack crate, big, down the left side.
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Size = UDim2.fromOffset(NUKE_PACK_ART, NUKE_PACK_ART)
	art.Position = UDim2.fromOffset(6, 52)
	art.ZIndex = 13
	art.Parent = card
	if def.image then
		crateImage(art, def.image, 0, 14)
	end

	-- The prizes, most likely first.
	local prizes = {}
	for itemId, p in Crates.nukeOdds(crateId) do
		table.insert(prizes, { itemId = itemId, p = p })
	end
	table.sort(prizes, function(a, b)
		if a.p ~= b.p then
			return a.p > b.p
		end
		return a.itemId < b.itemId
	end)

	local right = Instance.new("Frame")
	right.Name = "Right"
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromOffset(NUKE_PACK_ART + 14, 50)
	right.Size = UDim2.new(1, -(NUKE_PACK_ART + 28), 1, -60)
	right.ZIndex = 13
	right.Parent = card

	local strip = Instance.new("Frame")
	strip.Name = "Prizes"
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.new(1, 0, 0, PRIZE_BIG.Y)
	strip.ZIndex = 13
	strip.Parent = right
	local stripList = Instance.new("UIListLayout")
	stripList.FillDirection = Enum.FillDirection.Horizontal
	stripList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stripList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	stripList.Padding = UDim.new(0, 10)
	stripList.SortOrder = Enum.SortOrder.LayoutOrder
	stripList.Parent = strip

	for index, prize in prizes do
		local item = Items.get(prize.itemId)
		local rarity = Rarity.get(item.rarity)
		local tile = Instance.new("Frame")
		tile.Name = `Prize_{prize.itemId}`
		tile.LayoutOrder = index
		local grow = if #prizes > 1 then (index - 1) / (#prizes - 1) else 1
		local size = PRIZE_SMALL:Lerp(PRIZE_BIG, grow)
		tile.Size = UDim2.fromOffset(math.round(size.X), math.round(size.Y))
		tile.BackgroundColor3 = Color3.new(0, 0, 0)
		tile.BackgroundTransparency = 0.45
		tile.BorderSizePixel = 0
		tile.ZIndex = 13
		tile.Parent = strip
		round(tile, 8)
		local frame = Instance.new("UIStroke")
		frame.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		frame.Color = rarity.color
		frame.Thickness = 4
		frame.Parent = tile
		-- A soft wash of the rarity's colour up from the floor of the tile.
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundColor3 = rarity.color
		glow.BackgroundTransparency = 0.35
		glow.BorderSizePixel = 0
		glow.ZIndex = 13
		glow.Parent = tile
		round(glow, 8)
		local fade = Instance.new("UIGradient")
		fade.Rotation = -90
		fade.Transparency = NumberSequence.new(0.2, 1)
		fade.Parent = glow

		local well = Instance.new("Frame")
		well.Name = "Art"
		well.BackgroundTransparency = 1
		well.Position = UDim2.fromOffset(2, 2)
		well.Size = UDim2.new(1, -4, 1, -4)
		well.ZIndex = 14
		well.Parent = tile
		local viewport = ItemArt.newViewport(well)
		viewport.ZIndex = 14
		-- ItemArt frames at its own fixed FOV, so a narrower one here zooms the fit in.
		local camera = viewport.CurrentCamera :: Camera
		camera.FieldOfView /= PRIZE_ZOOM
		local entry = { uid = `nukepack-{prize.itemId}`, itemId = prize.itemId, identified = true, rarity = item.rarity }
		local function paint()
			local size = well.AbsoluteSize
			if size.X < 1 or size.Y < 1 then
				return
			end
			ItemArt.paint(viewport, entry, size.X / size.Y)
		end
		well:GetPropertyChangedSignal("AbsoluteSize"):Connect(paint)
		task.defer(paint)

		inked(tile, {
			Name = "Rarity",
			Text = item.rarity,
			Font = PANEL.headline,
			TextSize = math.round(14 + 4 * grow),
			TextColor3 = rarity.color:Lerp(Color3.new(1, 1, 1), 0.35),
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, 2),
			Size = UDim2.new(1, 8, 0, 20),
			ZIndex = 16,
		})
		inked(tile, {
			Name = "Odds",
			Text = percent(prize.p),
			Font = PANEL.headline,
			TextSize = math.round(20 + 8 * grow),
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -4, 1, -2),
			Size = UDim2.new(1, -8, 0, math.round(22 + 8 * grow)),
			ZIndex = 16,
		})
	end

	-- The bundles: one R$ button each, "xN" sitting on its top-left shoulder.
	local buttons = Instance.new("Frame")
	buttons.Name = "Bundles"
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(0, 1)
	buttons.Position = UDim2.fromScale(0, 1)
	buttons.Size = UDim2.new(1, 0, 0, BUY_H + 14)
	buttons.ZIndex = 13
	buttons.Parent = right
	local count = #NukePack.BUNDLES
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(GAP, 0)
	grid.CellSize = UDim2.new(1 / count, -GAP * (count - 1) / count, 1, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = buttons
	for index, bundle in NukePack.BUNDLES do
		local slot = Instance.new("Frame")
		slot.Name = `Bundle_{bundle.count}`
		slot.LayoutOrder = index
		slot.BackgroundTransparency = 1
		slot.ZIndex = 13
		slot.Parent = buttons
		local color = Color3.fromHex(bundle.color)
		local buy = robuxButton(slot, bundle.productId, false, color, color:Lerp(Color3.new(1, 1, 1), 0.25))
		buy.AnchorPoint = Vector2.new(0.5, 1)
		buy.Position = UDim2.fromScale(0.5, 1)
		buy.Size = UDim2.new(1, 0, 0, BUY_H)
		buy.TextSize = if bundle.productId ~= 0 then BUY_TEXT else 16
		inked(slot, {
			Name = "Count",
			Text = `x{bundle.count}`,
			Font = PANEL.headline,
			TextSize = 20,
			Position = UDim2.fromOffset(2, -4),
			Size = UDim2.fromOffset(60, 22),
			ZIndex = 17,
		})
	end
end

--- The LUCK BOOST section above the passes: the Server Luck Boost. The Lucky Clover
--- card that sat above it was taken out on request (2026-10-10); clover time still
--- comes in the Starter / Pro packs, and its product still grants if bought elsewhere.
local function buildLuck(parent: Frame)
	section(parent, -20, "LUCK BOOST")
	buildServerBoostCard(parent)
end

--- The passes, PASSES_PER_ROW to a row. A bought one keeps its card and swaps
--- the button for a green OWNED, off the attribute GamePassService sets.
local function buildPasses(parent: Instance)
	section(parent, -10, "PASSES")
	-- An odd count leaves the first pass (2x Cash) alone on a full-width row up top. Eight
	-- now (Auto Magnet took the old 2x Speed slot), so every row is a pair again.
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
			darkGlass(card, 14)
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
			art.Image = pass.image
			art.ScaleType = Enum.ScaleType.Fit
			art.Size = UDim2.fromOffset(PASS_ART, PASS_ART)
			art.Position = UDim2.fromOffset(10, 46)
			art.ZIndex = 13
			art.Parent = card
			inked(card, {
				Name = "PassName",
				Text = pass.name,
				TextColor3 = pass.color,
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

--- A row of Robux packs, CASH_PER_ROW to a row, headed `title` at
--- LayoutOrder `order`. `image(index)` gives each card's picture.
local function buildPackRows(parent: Instance, order: number, title: string, packs: { ShopProducts.CashPack }, look: typeof(CASH_CARD), image: (number) -> string, dress: ((ImageLabel, number) -> ())?)
	section(parent, order, title)
	local rows = math.ceil(#packs / CASH_PER_ROW)
	for rowIndex = 1, rows do
		local first = (rowIndex - 1) * CASH_PER_ROW + 1
		local last = math.min(first + CASH_PER_ROW - 1, #packs)
		local frame = row(parent, order + rowIndex, `{title}{rowIndex}`, CASH_H, last - first + 1)
		for index = first, last do
			local pack = packs[index]
			local card = Instance.new("Frame")
			card.Name = `{title}{index}`
			card.LayoutOrder = index
			card.BackgroundColor3 = Color3.new(1, 1, 1)
			darkGlass(card, 14)
			card.BorderSizePixel = 0
			card.ClipsDescendants = true
			card.ZIndex = 12
			card.Parent = frame
			round(card, 14)
			edge(card, look.edge, 4)
			-- Brighter down the middle, where the rays come from.
			local shade = Instance.new("UIGradient")
			shade.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, look.top),
				ColorSequenceKeypoint.new(0.5, look.middle),
				ColorSequenceKeypoint.new(1, look.top),
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
			art.Image = image(index)
			art.ScaleType = Enum.ScaleType.Fit
			art.AnchorPoint = Vector2.new(0.5, 0)
			art.Position = UDim2.fromScale(0.5, 0)
			art.Size = UDim2.fromOffset(150, 150)
			art.ZIndex = 13
			art.Parent = card
			if dress then
				dress(art, index)
			end

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

			local buy = robuxButton(card, pack.id, false, look.buy, look.buyHover)
			local gift = RobuxGift.button(card, pack.id)
			buy.AnchorPoint = Vector2.new(0, 1)
			buy.Position = UDim2.new(0, 10, 1, -10)
			buy.Size = UDim2.new(1, -20 - (if gift then BUY_H + 4 else 0), 0, BUY_H)
			buy.TextSize = BUY_TEXT + 4
			if gift then
				gift.AnchorPoint = Vector2.new(1, 1)
				gift.Position = UDim2.new(1, -10, 1, -10)
				gift.Size = UDim2.fromOffset(BUY_H, BUY_H)
			end
			local box = Instance.new("UIStroke")
			box.Color = look.buyEdge
			box.Thickness = 3
			box.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			box.Parent = buy
			gloss(buy)
		end
	end
end

--- The four cash packs; the picture grows with the pack, so the cards read as a ladder.
local function buildCash(parent: Instance)
	buildPackRows(parent, 2, "CASH", ShopProducts.CASH, CASH_CARD, function(index)
		return Artwork.IMAGE.shopCash[index] or Artwork.IMAGE.cashBundle
	end)
end

-- ── Codes ────────────────────────────────────────────────────────────────────

local CODES_H = 138
local CODE_MESSAGES: { [string]: { string | Color3 } } = {
	invalid = { "That code isn't valid.", PANEL.close },
	used = { "You've already used that code.", Color3.fromHex("F0A20F") },
	busy = { "Slow down - try again in a moment.", Color3.fromHex("F0A20F") },
}
local codeBox: TextBox? = nil
local codeButton: TextButton? = nil
local codeStatus: TextLabel? = nil
local codeWaiting = false
local codePrompting = false
local lastCode = ""

local function setCodeStatus(text: string, color: Color3)
	if codeStatus then
		codeStatus.Text = text
		codeStatus.TextColor3 = color
	end
end

local function paintCodeButton()
	local button = codeButton
	if button == nil then
		return
	end
	button.Text = if codeWaiting then "..." else "REDEEM"
	button.BackgroundColor3 = if codeWaiting then PANEL.off else PANEL.redeem
	button.Active = not codeWaiting
	button.AutoButtonColor = false
end

local function sendCode(text: string)
	if codeWaiting or codeRemote == nil then
		return
	end
	lastCode = text
	codeWaiting = true
	paintCodeButton()
	setCodeStatus("Checking...", PANEL.white)
	codeRemote:FireServer(text)
	-- Never leave the button stuck on "..." if the answer goes missing.
	task.delay(8, function()
		if codeWaiting then
			codeWaiting = false
			paintCodeButton()
		end
	end)
end

--- Not in the group: Roblox's own join prompt, then the same code again.
local function askToJoin(groupId: number)
	if codePrompting then
		return
	end
	codePrompting = true
	local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, groupId)
	codePrompting = false
	if ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember) then
		sendCode(lastCode)
	elseif ok and status == Enum.GroupMembershipStatus.JoinRequestPending then
		setCodeStatus("Join request sent - redeem again once you're in!", Color3.fromHex("F0A20F"))
	else
		setCodeStatus("Codes are for group members - join the group, then redeem.", Color3.fromHex("F0A20F"))
	end
end

local function onCodeResult(payload: any)
	if type(payload) ~= "table" then
		return
	end
	codeWaiting = false
	paintCodeButton()
	if payload.result == "ok" then
		setCodeStatus(`Redeemed! +{payload.text or "reward"}`, PANEL.cash)
		if codeBox then
			codeBox.Text = ""
		end
	elseif payload.result == "join" then
		setCodeStatus("Codes are for group members - opening the group...", Color3.fromHex("F0A20F"))
		task.spawn(askToJoin, tonumber(payload.groupId) or GroupReward.GROUP_ID)
	else
		local message = CODE_MESSAGES[payload.result]
		if message then
			setCodeStatus(message[1] :: string, message[2] :: Color3)
		end
	end
end

--- The CODES section, under the crates: one card with the box and the REDEEM button.
local function buildCodes(parent: Instance)
	section(parent, 20, "CODES")
	local card = Instance.new("Frame")
	card.Name = "Codes"
	card.LayoutOrder = 21
	card.Size = UDim2.new(1, -8, 0, CODES_H)
	card.BackgroundColor3 = PANEL.cardEdge:Lerp(PANEL.liquidTile, 0.5)
	darkGlass(card, 14)
	card.BorderSizePixel = 0
	card.ZIndex = 12
	card.Parent = parent
	round(card, 14)
	edge(card, PANEL.tileEdge, 3)
	gloss(card)

	inked(card, {
		Name = "Hint",
		Text = "Group members only - type a code for a free reward",
		Font = PANEL.label,
		TextSize = 16,
		TextColor3 = PANEL.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -32, 0, 20),
		Position = UDim2.fromOffset(16, 10),
		ZIndex = 14,
	})

	local box = Instance.new("TextBox")
	box.Name = "CodeBox"
	box.Position = UDim2.fromOffset(16, 38)
	box.Size = UDim2.new(1, -196, 0, 48)
	box.BackgroundColor3 = Color3.new(0, 0, 0)
	box.BackgroundTransparency = 0.4
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = PANEL.label
	box.TextSize = 22
	box.TextColor3 = PANEL.white
	box.PlaceholderText = "ENTER CODE"
	box.PlaceholderColor3 = PANEL.dim
	box.Text = ""
	box.TextXAlignment = Enum.TextXAlignment.Center
	box.ZIndex = 14
	box.Parent = card
	round(box, 10)
	edge(box, PANEL.ink, 3)
	codeBox = box

	local button = Instance.new("TextButton")
	button.Name = "Redeem"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -16, 0, 38)
	button.Size = UDim2.fromOffset(150, 48)
	button.Font = PANEL.label
	button.TextSize = 22
	button.TextColor3 = PANEL.white
	button.ZIndex = 14
	button.Parent = card
	round(button, 10)
	edge(button, PANEL.ink, 3)
	codeButton = button
	paintCodeButton()

	codeStatus = inked(card, {
		Name = "Status",
		Text = "",
		Font = PANEL.label,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -32, 0, 22),
		Position = UDim2.fromOffset(16, 96),
		ZIndex = 14,
	})

	local function submit()
		local text = box.Text
		if string.match(text, "%S") == nil then
			setCodeStatus("Type a code first.", PANEL.close)
			return
		end
		sendCode(text)
	end
	button.Activated:Connect(submit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submit()
		end
	end)
end

--- Open the Shop panel.
function Shop.open()
	local panel = panelFrame
	if panel == nil or panel.Visible or HudTile.blocked("Shop") then
		return
	end
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
	panel.BackgroundTransparency = 0.25
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
	-- Plain see-through black, no studs (on request, 2026-10-10: the L-stud pattern it
	-- wore from 2026-10-07 came off), so the world shows behind the cards.

	inked(panel, {
		Name = "Title",
		Text = "SHOP",
		Font = PANEL.headline,
		TextSize = 38,
		Size = UDim2.fromOffset(200, 46),
		ZIndex = 11,
	})

	local close = UIKit.closeButton(panel, {
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 2),
		size = 40,
		zIndex = 11,
	})
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

	buildNukePack(body)
	buildPacks(body)
	buildLuck(body)
	buildPasses(body)
	buildCash(body)
	buildCodes(body)

	panelFrame = panel
	panelScale = scale
	return gui
end

local function build(): ScreenGui
	local gui = HudTile.build({
		name = "ShopButton",
		caption = "Shop",
		slot = TILE_SLOT,
		-- The whole top row of the grid, on request (2026-10-06: "enlongate shop to
		-- take up two gui spots").
		span = 2,
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
	codeRemote = Net.get("RedeemCode")
	codeRemote.OnClientEvent:Connect(onCodeResult)
	build().Parent = playerGui
	buildPanel().Parent = playerGui
	HudTile.registerPanel("Shop", panelFrame :: Frame)
end

return Shop
