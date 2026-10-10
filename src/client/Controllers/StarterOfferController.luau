--!strict
--[[
	StarterOfferController — the Starter Pack offer card in the top-right corner, under
	the Settings / Daily / Potions row: spinning light rays behind it and, floating on
	them with no card behind, the pack's crate with cash and a luck clover either side,
	its R$ price and a red X.

	WHO SEES IT: everyone who is done with the walkthrough and hasn't bought the pack.
	`TutorialActive` (TutorialService, every tick) must read false, so a new player only
	gets it once the tutorial ends or is skipped, and every existing player (their save
	is marked done) gets it on join. `Pack_starter` (PackService's mirror) must read
	false; buying the pack turns it true and the card goes for good. Both attributes are
	nil until the save loads, and nil counts as "not yet".

	THE X HIDES IT FOR THIS SESSION ONLY: it comes back next join, until it is bought.

	The whole offer is ONE click target (the X aside): pressing anywhere on it opens the
	CONTENTS PANEL, a tile per thing in the pack (cash, each crate, luck time), with the
	R$ button under them that opens the purchase prompt (the Shop's PACKS row sells the
	same product; PackService grants it either way).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packs = require(ReplicatedStorage.Shared.Config.Packs)
local Crates = require(ReplicatedStorage.Shared.Config.Crates)
local LuckBoost = require(ReplicatedStorage.Shared.Config.LuckBoost)
local CashBoost = require(ReplicatedStorage.Shared.Config.CashBoost)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local Artwork = require(script.Parent.Parent.HudArtwork)
local RobuxButton = require(script.Parent.Parent.RobuxButton)
local Sfx = require(script.Parent.Parent.Sfx)
local Studded = require(script.Parent.Parent.Studded)
local HudTile = require(script.Parent.Parent.HudTile)
local CloverArt = require(script.Parent.Parent.CloverArt)
local ItemArt = require(script.Parent.Parent.ItemArt)

local StarterOfferController = {}

local PACK_KEY = "starter"

-- Smaller, on request (2026-10-07): 168 x 156 -> 140 x 128. A little bigger again
-- (2026-10-10): 168 x 176, the extra height for the struck-out "was" price.
local CARD_W = 168
local CARD_H = Dock.STARTER_CARD_H
local RAYS = 370
local ART = 72
-- The crate's centre, down from the card's top.
local ART_Y = 80
-- The cash bundle and clover lean on the crate's sides (on request, 2026-10-07: they
-- floated off at the card's edges): their centres this far out from the crate's, and
-- this far below it.
local SIDE_OUT = 36
local SIDE_DROP = 16
local BUNDLE = 50
local CLOVER = 40
-- The pack's own picture (Config/Packs `image`) fills the space the crate, bundle and
-- clover shared, between the title and the price.
local PICTURE = 84
local BUY_H = 30
-- The struck-out "was" price (Config/Packs `wasPrice`), on a row just over the live one.
local WAS_H = 20
local ROBUX = utf8.char(0xE002)
local CLOSE = 26
-- Never smaller than this on a short screen, where the card must squeeze in above the
-- right-edge tile column.
local MIN_FIT = 0.6
-- Smaller on a phone or tablet, on request (2026-10-06): it covered too much of a small
-- screen. Multiplies the fit below.
local TOUCH_FIT = Dock.STARTER_TOUCH_FIT

local COLOR = {
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	gold = Color3.fromRGB(255, 214, 92),
	cash = Color3.fromRGB(150, 255, 140),
	was = Color3.new(1, 1, 1),
	strike = Color3.fromHex("E5484D"),
	close = Color3.fromHex("E5484D"),
	closeHover = Color3.fromHex("FF6A6E"),
}

-- Crate pictures (Config/Crates `image`); a crate without one is drawn live.
local CRATE_IMAGE: { [string]: string } = Crates.IMAGES

-- THE CONTENTS PANEL the offer opens: what is in the pack, one tile each, and the R$
-- button under them. Centred like every other HUD panel, one open at a time (HudTile).
local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	tile = Color3.fromHex("252A30"),
}
local PAD = 20
local HEADER_H = 74
local TILE_W = 128
local TILE_H = 168
local TILE_GAP = 12
local TILE_ART = 84
local PANEL_BUY_H = 62
local PANEL_LIFT = 20
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHRINK = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local dismissed = false
local shown = false

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function stroke(parent: Instance, thickness: number, border: boolean?)
	local s = Instance.new("UIStroke")
	s.Color = COLOR.ink
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
end

local function label(parent: Instance, name: string, text: string, size: number, color: Color3, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 1
	l.ZIndex = z
	l.Parent = parent
	stroke(l, math.max(1.5, size * 0.1))
	return l
end

--- One layer of rays, spinning forever. `period` seconds a turn; negative turns back.
local function rays(parent: Instance, name: string, size: number, color: Color3, transparency: number, period: number, z: number, y: number?)
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.Image = Artwork.IMAGE.sunburst
	image.ImageColor3 = color
	image.ImageTransparency = transparency
	image.ScaleType = Enum.ScaleType.Fit
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, y or 0.42)
	image.Size = UDim2.fromOffset(size, size)
	image.ZIndex = z
	image.Parent = parent
	local turn = if period > 0 then 360 else -360
	TweenService:Create(image, TweenInfo.new(math.abs(period), Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = turn }):Play()
end

--- $200K / $5M, like the Shop's pack card.
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

type Reward = { title: string, caption: string, draw: (Frame) -> () }

local function picture(well: Frame, image: string)
	local art = Instance.new("ImageLabel")
	art.Name = "Picture"
	art.BackgroundTransparency = 1
	art.Image = image
	art.ScaleType = Enum.ScaleType.Fit
	art.Size = UDim2.fromScale(1, 1)
	art.ZIndex = 14
	art.Parent = well
end

--- Everything in `pack`, in the order the Shop card lists it.
local function rewardsOf(pack: Packs.Pack): { Reward }
	local out: { Reward } = {}
	if pack.cash > 0 then
		table.insert(out, {
			title = shortCash(pack.cash),
			caption = "Cash",
			draw = function(well)
				picture(well, Artwork.IMAGE.cashBundle)
			end,
		})
	end
	for _, entry in Packs.crateCounts(pack) do
		local crateId = entry.crateId
		table.insert(out, {
			title = `x{entry.count}`,
			caption = Crates.get(crateId).name,
			draw = function(well)
				local image = CRATE_IMAGE[crateId]
				if image then
					picture(well, image)
					return
				end
				local viewport = ItemArt.newViewport(well)
				viewport.ZIndex = 14
				local function paint()
					local size = well.AbsoluteSize
					if size.X < 1 or size.Y < 1 then
						return
					end
					ItemArt.clear(viewport)
					ItemArt.paint(viewport, { uid = `offer-{crateId}`, crateId = crateId }, size.X / size.Y)
				end
				well:GetPropertyChangedSignal("AbsoluteSize"):Connect(paint)
				task.defer(paint)
			end,
		})
	end
	if pack.luckSeconds > 0 then
		table.insert(out, {
			title = duration(pack.luckSeconds),
			caption = `{LuckBoost.MULT}x Luck`,
			draw = function(well)
				local clover = CloverArt.build(well, TILE_ART - 8, 14)
				clover.AnchorPoint = Vector2.new(0.5, 0.5)
				clover.Position = UDim2.fromScale(0.5, 0.5)
			end,
		})
	end
	if pack.cashBoostSeconds > 0 then
		table.insert(out, {
			title = duration(pack.cashBoostSeconds),
			caption = `{CashBoost.MULT}x Cash`,
			draw = function(well)
				picture(well, Artwork.IMAGE.cashBundle)
			end,
		})
	end
	return out
end

local panelRoot: Frame? = nil
local panelScale: UIScale? = nil

local function closePanel()
	if panelRoot then
		panelRoot.Visible = false
	end
end

local function openPanel()
	local root = panelRoot
	-- One HUD panel at a time, like every other open path.
	if root == nil or root.Visible or HudTile.blocked("StarterPack") then
		return
	end
	root.Visible = true
	if panelScale then
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, OPEN, { Scale = 1 }):Play()
	end
end

--- The contents panel: header, a tile per reward, the R$ button, on light rays.
local function buildPanel(pack: Packs.Pack): ScreenGui
	local rewards = rewardsOf(pack)
	local count = #rewards
	local panelW = PAD * 2 + count * TILE_W + (count - 1) * TILE_GAP
	local panelH = PAD * 2 + HEADER_H + TILE_H + PAD + PANEL_BUY_H

	local gui = Instance.new("ScreenGui")
	gui.Name = "StarterPackPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	-- The root holds the rays and the panel, so one Visible opens and closes both.
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.5, -PANEL_LIFT)
	root.Size = UDim2.fromOffset(panelW, panelH)
	root.Visible = false
	root.Parent = canvas
	local scale = Instance.new("UIScale")
	scale.Parent = root

	rays(root, "RaysGold", panelW * 1.9, COLOR.gold, 0.25, 18, 1, 0.5)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = PANEL.panel
	panel.BorderSizePixel = 0
	panel.ZIndex = 10
	panel.Parent = root
	round(panel, 8)
	stroke(panel, 4, true)
	Studded.darkPanel(panel, 8) -- the Shop's dark grey studded backdrop

	local title = label(panel, "Title", string.upper(pack.name), 38, COLOR.white, 11)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, -PAD * 2 - 50, 0, 46)
	title.Position = UDim2.fromOffset(PAD, PAD - 6)
	local once = label(panel, "Once", "ONE TIME ONLY - everything below, in one purchase", 14, COLOR.cash, 11)
	once.TextXAlignment = Enum.TextXAlignment.Left
	once.Size = UDim2.new(1, -PAD * 2 - 50, 0, 18)
	once.Position = UDim2.fromOffset(PAD + 2, PAD + 40)

	local close = UIKit.closeButton(panel, {
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -PAD, 0, PAD - 4),
		size = 40,
		zIndex = 11,
	})
	close.Activated:Connect(function()
		Sfx.play("click")
		closePanel()
	end)

	local top = PAD + HEADER_H
	for index, reward in rewards do
		local tile = Instance.new("Frame")
		tile.Name = `Reward{index}`
		tile.Position = UDim2.fromOffset(PAD + (index - 1) * (TILE_W + TILE_GAP), top)
		tile.Size = UDim2.fromOffset(TILE_W, TILE_H)
		tile.BackgroundColor3 = PANEL.tile
		tile.BorderSizePixel = 0
		tile.ClipsDescendants = true
		tile.ZIndex = 11
		tile.Parent = panel
		round(tile, 8)
		stroke(tile, 3, true)
		-- The Shop cards' glossy L-studs, under the rays and the art.
		Studded.pattern(tile, { radius = 8, bands = { 0.2, 0.47, 0.56, 0.64 }, bandTransparency = 0.55, glowTransparency = 0.72 })
		-- White rays behind each picture, like the Shop's cash cards.
		local glow = Instance.new("ImageLabel")
		glow.Name = "Rays"
		glow.BackgroundTransparency = 1
		glow.Image = Artwork.IMAGE.sunburst
		glow.ImageTransparency = 0.55
		glow.ScaleType = Enum.ScaleType.Fit
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.new(0.5, 0, 0, 12 + TILE_ART / 2)
		glow.Size = UDim2.fromOffset(TILE_ART * 2, TILE_ART * 2)
		glow.ZIndex = 12
		glow.Parent = tile

		local well = Instance.new("Frame")
		well.Name = "Art"
		well.BackgroundTransparency = 1
		well.AnchorPoint = Vector2.new(0.5, 0)
		well.Position = UDim2.new(0.5, 0, 0, 12)
		well.Size = UDim2.fromOffset(TILE_ART, TILE_ART)
		well.ZIndex = 13
		well.Parent = tile
		reward.draw(well)

		local amount = label(tile, "Amount", reward.title, 24, COLOR.gold, 15)
		amount.Size = UDim2.new(1, -8, 0, 28)
		amount.Position = UDim2.fromOffset(4, 12 + TILE_ART + 4)
		local caption = label(tile, "Caption", reward.caption, 14, COLOR.white, 15)
		caption.TextWrapped = true
		caption.TextYAlignment = Enum.TextYAlignment.Top
		caption.Size = UDim2.new(1, -10, 0, 34)
		caption.Position = UDim2.fromOffset(5, 12 + TILE_ART + 32)
	end

	local buy = RobuxButton.product(panel, function()
		return pack.id
	end)
	buy.button.AnchorPoint = Vector2.new(0.5, 1)
	buy.button.Position = UDim2.new(0.5, 0, 1, -PAD)
	buy.button.Size = UDim2.new(1, -PAD * 2, 0, PANEL_BUY_H)
	buy.button.ZIndex = 11
	buy.price.ZIndex = 12

	panelRoot = root
	panelScale = scale
	HudTile.registerPanel("StarterPack", root)
	return gui
end

function StarterOfferController.start()
	local player = Players.LocalPlayer
	local pack = Packs.byKey(PACK_KEY)
	if pack == nil then
		return
	end
	local attr = Packs.attr(PACK_KEY)

	local gui = Instance.new("ScreenGui")
	gui.Name = "StarterOffer"
	gui.ResetOnSpawn = false
	-- Measured from the SCREEN top, like the corner row it hangs under.
	gui.IgnoreGuiInset = true
	-- Under the HUD tiles (55), so its rays never cover a tile.
	gui.DisplayOrder = 54
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	local canvas = UIKit.canvas(gui)

	-- The holder: anchored on its top-right corner, so the fit and pop scales grow and
	-- shrink it out of the corner.
	local holder = Instance.new("Frame")
	holder.Name = "Offer"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Size = UDim2.fromOffset(CARD_W, CARD_H)
	holder.Parent = canvas
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = holder
	-- The pop-in and close animation scale a second frame inside, so they never fight
	-- the fit scale.
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromScale(1, 1)
	body.Parent = holder
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Scale = 0
	pop.Parent = body

	-- Light rays: a wide gold layer turning one way, a tighter white one the other.
	rays(body, "RaysGold", RAYS, COLOR.gold, 0, 14, 1)
	rays(body, "RaysWhite", RAYS * 0.7, COLOR.white, 0.15, -10, 2)

	local card = Instance.new("TextButton")
	card.Name = "Card"
	card.AutoButtonColor = false
	card.Text = ""
	card.Size = UDim2.fromScale(1, 1)
	-- No card behind it, on request: the crate, cash and R$ price float on the rays. It is
	-- still the one button the whole offer clicks through to.
	card.BackgroundTransparency = 1
	card.ZIndex = 3
	card.Parent = body
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	local title = label(card, "Title", string.upper(pack.name), 18, COLOR.white, 6)
	title.Size = UDim2.new(1, -12, 0, 21)
	title.Position = UDim2.fromOffset(6, 6)

	local once = label(card, "Once", "ONE TIME ONLY", 12, COLOR.cash, 6)
	once.Size = UDim2.new(1, -12, 0, 13)
	once.Position = UDim2.fromOffset(6, 27)

	-- The pack's own picture (Config/Packs `image`) when it has one. Otherwise the crate,
	-- still (on request), a cash bundle leaning on its left and a luck clover on its
	-- right, both tucked against it and in front of it.
	if pack.image then
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		art.Image = pack.image
		art.ScaleType = Enum.ScaleType.Fit
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.new(0.5, 0, 0, ART_Y)
		art.Size = UDim2.fromOffset(PICTURE, PICTURE)
		art.ZIndex = 4
		art.Parent = card
	else
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		-- The best crate in the pack that has a picture (the last listed tops each ladder).
		for i = #pack.crates, 1, -1 do
			local image = CRATE_IMAGE[pack.crates[i]]
			if image then
				art.Image = image
				break
			end
		end
		art.ScaleType = Enum.ScaleType.Fit
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.new(0.5, 0, 0, ART_Y)
		art.Size = UDim2.fromOffset(ART, ART)
		art.ZIndex = 4
		art.Parent = card
		local bundle = Instance.new("ImageLabel")
		bundle.Name = "Bundle"
		bundle.BackgroundTransparency = 1
		bundle.Image = Artwork.IMAGE.cashBundle
		bundle.ScaleType = Enum.ScaleType.Fit
		bundle.AnchorPoint = Vector2.new(0.5, 0.5)
		bundle.Position = UDim2.new(0.5, -SIDE_OUT, 0, ART_Y + SIDE_DROP)
		bundle.Size = UDim2.fromOffset(BUNDLE, BUNDLE)
		bundle.Rotation = -12
		bundle.ZIndex = 5
		bundle.Parent = card
		local clover = CloverArt.build(card, CLOVER, 5)
		clover.Name = "Clover"
		clover.AnchorPoint = Vector2.new(0.5, 0.5)
		clover.Position = UDim2.new(0.5, SIDE_OUT, 0, ART_Y + SIDE_DROP)
		clover.Rotation = 12
	end

	local buy = RobuxButton.product(card, function()
		return pack.id
	end)
	buy.button.AnchorPoint = Vector2.new(0.5, 1)
	buy.button.Position = UDim2.new(0.5, 0, 1, -4)
	buy.button.Size = UDim2.new(1, -12, 0, BUY_H)
	buy.button.ZIndex = 6
	buy.price.ZIndex = 7
	-- Just the R$ price, no purple button behind it (on request), and not a button of its
	-- own: the whole offer is one click target, the card underneath.
	buy.button.BackgroundTransparency = 1
	local buyEdge = buy.button:FindFirstChildOfClass("UIStroke")
	if buyEdge then
		buyEdge:Destroy()
	end
	buy.button.Interactable = false
	-- "ONLY R$ 9": the live dashboard price with ONLY in front, re-read whenever the
	-- button's own price text loads or changes.
	local function only()
		local text = buy.price.Text
		if string.find(text, "%d") and not string.find(text, "^ONLY") then
			buy.price.Text = `ONLY {text}`
		end
	end
	buy.price:GetPropertyChangedSignal("Text"):Connect(only)
	only()

	-- The struck-out "was" price on its own row just over it, with a red slash through.
	if pack.wasPrice then
		local was = label(card, "Was", `{ROBUX} {pack.wasPrice}`, 19, COLOR.was, 6)
		was.AutomaticSize = Enum.AutomaticSize.X
		was.Size = UDim2.fromOffset(0, WAS_H)
		was.AnchorPoint = Vector2.new(0.5, 1)
		was.Position = UDim2.new(0.5, 0, 1, -4 - BUY_H)
		local strike = Instance.new("Frame")
		strike.Name = "Strike"
		strike.BackgroundColor3 = COLOR.strike
		strike.BorderSizePixel = 0
		strike.AnchorPoint = Vector2.new(0.5, 0.5)
		strike.Position = UDim2.fromScale(0.5, 0.5)
		strike.Size = UDim2.new(1, 8, 0, 3)
		strike.Rotation = -6
		strike.ZIndex = 7
		strike.Parent = was
		stroke(strike, 1, true)
	end

	-- The offer opens the contents panel; the panel's R$ button is the one that buys.
	card.Activated:Connect(function()
		Sfx.play("click")
		openPanel()
	end)
	card.MouseEnter:Connect(function()
		TweenService:Create(cardScale, HOVER, { Scale = 1.04 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(cardScale, HOVER, { Scale = 1 }):Play()
	end)

	-- The X, a red disc hung on the card's top-right corner.
	local close = UIKit.closeButton(body, {
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(1, -4, 0, 4),
		size = CLOSE,
		zIndex = 8,
	})
	close.MouseEnter:Connect(function()
		TweenService:Create(close, HOVER, { BackgroundColor3 = COLOR.closeHover }):Play()
	end)
	close.MouseLeave:Connect(function()
		TweenService:Create(close, HOVER, { BackgroundColor3 = COLOR.close }):Play()
	end)

	-- Under the corner row, hard right, dropped a little (Dock.STARTER_DROP) so its rays clear the
	-- corner tiles above it; shrunk on a short screen so it stays clear of the Nukes / Potions
	-- column below it (Dock.rightColumnTop).
	local function place()
		local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
		local top = Dock.STARTER_TOP
		local ceiling = height / 2 + Dock.rightColumnTop(height) - Dock.GAP
		local touch = if UIKit.isTouch() then TOUCH_FIT else 1
		fit.Scale = math.clamp((ceiling - top) / (CARD_H * touch), MIN_FIT, 1) * touch
		holder.Position = UDim2.new(1, -(Dock.CORNER_SIDE + 4), 0, top)
	end
	UIKit.onScaleChanged(place)
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	local function wanted(): boolean
		return not dismissed and player:GetAttribute("TutorialActive") == false and player:GetAttribute(attr) == false
	end

	local function refresh()
		local want = wanted()
		if want == shown then
			return
		end
		shown = want
		if want then
			gui.Enabled = true
			pop.Scale = 0
			TweenService:Create(pop, POP, { Scale = 1 }):Play()
		else
			local tween = TweenService:Create(pop, SHRINK, { Scale = 0 })
			tween.Completed:Connect(function()
				if not shown then
					gui.Enabled = false
				end
			end)
			tween:Play()
		end
	end

	close.Activated:Connect(function()
		Sfx.play("click")
		dismissed = true
		refresh()
	end)

	player:GetAttributeChangedSignal("TutorialActive"):Connect(refresh)
	player:GetAttributeChangedSignal(attr):Connect(refresh)
	local playerGui = player:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	buildPanel(pack).Parent = playerGui
	-- Bought: the offer goes (refresh) and so does the panel.
	player:GetAttributeChangedSignal(attr):Connect(function()
		if player:GetAttribute(attr) == true then
			closePanel()
		end
	end)
	refresh()
end

return StarterOfferController
