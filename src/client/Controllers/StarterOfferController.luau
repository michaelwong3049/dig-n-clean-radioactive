--!strict
--[[
	StarterOfferController — the Starter Pack offer card in the top-right corner, under
	the Settings / Daily / Potions row: spinning light rays behind it and, floating on
	them with no card behind, the pack's crate and cash, its R$ price and a red X.

	WHO SEES IT: everyone who is done with the walkthrough and hasn't bought the pack.
	`TutorialActive` (TutorialService, every tick) must read false, so a new player only
	gets it once the tutorial ends or is skipped, and every existing player (their save
	is marked done) gets it on join. `Pack_starter` (PackService's mirror) must read
	false; buying the pack turns it true and the card goes for good. Both attributes are
	nil until the save loads, and nil counts as "not yet".

	THE X HIDES IT FOR THIS SESSION ONLY: it comes back next join, until it is bought.

	The whole offer is ONE click target (the X aside): pressing anywhere on it opens the
	purchase prompt (the Shop's PACKS row sells the same product; PackService grants it
	either way).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Packs = require(ReplicatedStorage.Shared.Config.Packs)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local Artwork = require(script.Parent.Parent.HudArtwork)
local RobuxButton = require(script.Parent.Parent.RobuxButton)
local Sfx = require(script.Parent.Parent.Sfx)

local StarterOfferController = {}

local PACK_KEY = "starter"

local CARD_W = 168
local CARD_H = 156
local RAYS = 380
local ART = 74
local BUY_H = 34
local CLOSE = 30
-- Never smaller than this on a short screen, where the card must squeeze in above the
-- right-edge tile column.
local MIN_FIT = 0.6

local COLOR = {
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	gold = Color3.fromRGB(255, 214, 92),
	cash = Color3.fromRGB(150, 255, 140),
	close = Color3.fromHex("E5484D"),
	closeHover = Color3.fromHex("FF6A6E"),
}

-- The Starter Pack's Isotope Chem crate (ShopController's CRATE_IMAGE.liquid2).
local CRATE_IMAGE = "rbxassetid://107641217252136"

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
local function rays(parent: Instance, name: string, size: number, color: Color3, transparency: number, period: number, z: number)
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.Image = Artwork.IMAGE.sunburst
	image.ImageColor3 = color
	image.ImageTransparency = transparency
	image.ScaleType = Enum.ScaleType.Fit
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.42)
	image.Size = UDim2.fromOffset(size, size)
	image.ZIndex = z
	image.Parent = parent
	local turn = if period > 0 then 360 else -360
	TweenService:Create(image, TweenInfo.new(math.abs(period), Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = turn }):Play()
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

	local title = label(card, "Title", string.upper(pack.name), 17, COLOR.white, 6)
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.fromOffset(8, 8)

	local once = label(card, "Once", "ONE TIME ONLY", 11, COLOR.cash, 6)
	once.Size = UDim2.new(1, -16, 0, 12)
	once.Position = UDim2.fromOffset(8, 30)

	-- The crate with a cash bundle leaning on it, bobbing gently.
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Image = CRATE_IMAGE
	art.ScaleType = Enum.ScaleType.Fit
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.new(0.5, 6, 0, 46 + ART / 2 - 4)
	art.Size = UDim2.fromOffset(ART, ART)
	art.ZIndex = 4
	art.Parent = card
	TweenService:Create(art, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = art.Position + UDim2.fromOffset(0, -4),
	}):Play()
	local bundle = Instance.new("ImageLabel")
	bundle.Name = "Bundle"
	bundle.BackgroundTransparency = 1
	bundle.Image = Artwork.IMAGE.cashBundle
	bundle.ScaleType = Enum.ScaleType.Fit
	bundle.AnchorPoint = Vector2.new(0.5, 1)
	bundle.Position = UDim2.new(0, 38, 1, -BUY_H - 6)
	bundle.Size = UDim2.fromOffset(50, 50)
	bundle.Rotation = -12
	bundle.ZIndex = 5
	bundle.Parent = card

	local buy = RobuxButton.product(card, function()
		return pack.id
	end)
	buy.button.AnchorPoint = Vector2.new(0.5, 1)
	buy.button.Position = UDim2.new(0.5, 0, 1, -8)
	buy.button.Size = UDim2.new(1, -16, 0, BUY_H)
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

	card.Activated:Connect(buy.press)
	card.MouseEnter:Connect(function()
		TweenService:Create(cardScale, HOVER, { Scale = 1.04 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(cardScale, HOVER, { Scale = 1 }):Play()
	end)

	-- The X, a red disc hung on the card's top-right corner.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.Size = UDim2.fromOffset(CLOSE, CLOSE)
	close.BackgroundColor3 = COLOR.close
	close.Font = Enum.Font.GothamBlack
	close.Text = "X"
	close.TextSize = 18
	close.TextColor3 = COLOR.white
	close.ZIndex = 8
	close.Parent = body
	round(close, CLOSE)
	stroke(close, 3, true)
	close.MouseEnter:Connect(function()
		TweenService:Create(close, HOVER, { BackgroundColor3 = COLOR.closeHover }):Play()
	end)
	close.MouseLeave:Connect(function()
		TweenService:Create(close, HOVER, { BackgroundColor3 = COLOR.close }):Play()
	end)

	-- Under the corner row, hard right; shrunk on a short screen so it stays clear of
	-- the tile column below it (Dock.sideColumnTop).
	local function place()
		local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
		local top = Dock.CORNER_BUTTON_BOTTOM + Dock.GAP + 6
		local ceiling = height / 2 + Dock.sideColumnTop(height) - Dock.GAP
		fit.Scale = math.clamp((ceiling - top) / CARD_H, MIN_FIT, 1)
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
	gui.Parent = player:WaitForChild("PlayerGui")
	refresh()
end

return StarterOfferController
