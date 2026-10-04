--!strict
--[[
	PassOfferController — the 2x Luck and 2x Speed buy cards on the right edge, from
	the user's reference picture: a chunky stud-textured card, the pass's picture poking
	out over its top-left corner, a big outlined title, and "ONLY R$ 99" hung across
	the card's bottom edge (half on it, half off, on request). A light streak sweeps
	across each card every few seconds.

	Luck is on the lime card, Speed on the gold one (the reference's own colours). The
	price is read off the pass (RobuxButton.priceOf), so a dashboard change needs no
	code. Pressing a card opens the game-pass prompt; a card goes once you own its pass
	(GamePassService's `Pass_<key>` attribute), and the other closes up to the top.

	POSITION: hard right, between the Starter Pack offer above (whose bottom stops at
	Dock.sideColumnTop's line) and the luck clover badge above the hotbar below; on a
	screen too short for both cards the stack shrinks (`Fit`, floored at MIN_FIT).
	DisplayOrder 53 sits under the offer (54) and the haul panel, which may slide over
	it on a narrow screen mid-haul.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GamePasses = require(ReplicatedStorage.Shared.Config.GamePasses)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local RobuxButton = require(script.Parent.Parent.RobuxButton)
local Sfx = require(script.Parent.Parent.Sfx)

local PassOfferController = {}

local ROBUX = utf8.char(0xE002)

type Look = { key: string, title: string, top: Color3, bottom: Color3, edge: Color3 }

-- Top to bottom.
local CARDS: { Look } = {
	{ key = "luck", title = "2x LUCK", top = Color3.fromHex("C6F545"), bottom = Color3.fromHex("74C41B"), edge = Color3.fromHex("2B5405") },
	{ key = "speed", title = "2x SPEED", top = Color3.fromHex("FFD84A"), bottom = Color3.fromHex("F2A10F"), edge = Color3.fromHex("6B3C00") },
}

-- Design px.
local CARD_W = 148
local CARD_H = 44
local RADIUS = 10
local EDGE = 3
local ICON = 54
local ICON_OUT = Vector2.new(12, 14) -- how far the picture pokes past the left and top edges
local TITLE_SIZE = 19
local PRICE_SIZE = 15
local PRICE_H = 18
local STEP = CARD_H + PRICE_H / 2 + 10 -- card top to the next card's top
local STUD = 14 -- stud grid pitch
local STUD_D = 7
-- The luck clover badge's box above the hotbar (LuckBoostController: 80 clover + 34
-- pill), which the stack stays clear of even while the badge is hidden.
local LUCK_CLEAR = Dock.HOTBAR_BOTTOM + Dock.HOTBAR_HEIGHT + Dock.GAP + 114 + Dock.GAP
local MIN_FIT = 0.6

local INK = Color3.fromHex("15130F")
local ONLY = "FFE234"
local PRICE = "7DFF3A"
local WHITE = Color3.new(1, 1, 1)

local SWEEP = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SWEEP_EVERY = 3
local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MOVE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function outline(parent: Instance, color: Color3, thickness: number, border: boolean?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = parent
end

--- The faint LEGO-style studs, inset so none pokes past the rounded corners.
local function studs(card: Frame)
	local columns = math.floor((CARD_W - 8) / STUD)
	local rows = math.floor((CARD_H - 8) / STUD)
	local x0 = (CARD_W - (columns - 1) * STUD) / 2
	local y0 = (CARD_H - (rows - 1) * STUD) / 2
	for row = 0, rows - 1 do
		for column = 0, columns - 1 do
			local stud = Instance.new("Frame")
			stud.Name = "Stud"
			stud.AnchorPoint = Vector2.new(0.5, 0.5)
			stud.Position = UDim2.fromOffset(x0 + column * STUD, y0 + row * STUD)
			stud.Size = UDim2.fromOffset(STUD_D, STUD_D)
			stud.BackgroundColor3 = WHITE
			stud.BackgroundTransparency = 0.84
			stud.BorderSizePixel = 0
			stud.ZIndex = 2
			stud.Parent = card
			round(stud, STUD_D)
			local ring = Instance.new("UIStroke")
			ring.Color = Color3.new(0, 0, 0)
			ring.Transparency = 0.9
			ring.Thickness = 1
			ring.Parent = stud
		end
	end
end

--- The light streak: a white overlay the card's shape, see-through but for a narrow
--- slanted band its gradient slides across. Same corners as the card, so it never
--- shows outside them.
local function shine(card: Frame)
	local sheen = Instance.new("Frame")
	sheen.Name = "Shine"
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.BackgroundColor3 = WHITE
	sheen.BorderSizePixel = 0
	sheen.ZIndex = 3
	sheen.Parent = card
	round(sheen, RADIUS)
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
	band.Parent = sheen
	task.spawn(function()
		while sheen.Parent do
			band.Offset = Vector2.new(-1, 0)
			local tween = TweenService:Create(band, SWEEP, { Offset = Vector2.new(1, 0) })
			tween:Play()
			tween.Completed:Wait()
			task.wait(SWEEP_EVERY)
		end
	end)
end

type Built = { holder: Frame, refresh: () -> (), owned: () -> boolean }

local function build(parent: Instance, look: Look): Built?
	local pass = GamePasses.byKey(look.key)
	if pass == nil then
		return nil
	end
	local player = Players.LocalPlayer
	local attr = GamePasses.attr(look.key)

	-- The holder is the layout box (card + the price hanging under it); hover and press
	-- scale the card inside, so they never fight the slide when a card above goes.
	local holder = Instance.new("Frame")
	holder.Name = `Offer_{look.key}`
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0)
	holder.Size = UDim2.fromOffset(CARD_W, CARD_H + PRICE_H / 2)
	holder.Parent = parent

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.ZIndex = 1
	card.Parent = button
	round(card, RADIUS)
	outline(card, look.edge, EDGE, true)
	local fill = Instance.new("UIGradient")
	fill.Rotation = 90
	fill.Color = ColorSequence.new(look.top, look.bottom)
	fill.Parent = card
	studs(card)
	shine(card)

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = pass.image
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Position = UDim2.fromOffset(-ICON_OUT.X, -ICON_OUT.Y)
	icon.Size = UDim2.fromOffset(ICON, ICON)
	icon.ZIndex = 5
	icon.Parent = button

	local textLeft = ICON - ICON_OUT.X
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = look.title
	title.TextSize = TITLE_SIZE
	title.TextColor3 = WHITE
	title.Position = UDim2.fromOffset(textLeft, 4)
	title.Size = UDim2.new(0, CARD_W - textLeft - 6, 0, CARD_H - PRICE_H / 2 - 6)
	title.ZIndex = 6
	title.Parent = button
	outline(title, look.edge, 3)

	-- "ONLY R$ 99" centred on the card's bottom edge: half on it, half under it.
	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.BackgroundTransparency = 1
	price.Font = Enum.Font.GothamBlack
	price.RichText = true
	price.TextSize = PRICE_SIZE
	price.TextColor3 = WHITE
	price.AnchorPoint = Vector2.new(0.5, 0.5)
	price.Position = UDim2.fromOffset(CARD_W / 2, CARD_H)
	price.Size = UDim2.fromOffset(CARD_W, PRICE_H)
	price.ZIndex = 7
	price.Parent = button
	outline(price, INK, 2.5)

	local function owned(): boolean
		return player:GetAttribute(attr) == true
	end

	local refresh: () -> ()
	function refresh()
		local robux = RobuxButton.priceOf(pass.id, true, refresh)
		local amount = if robux then tostring(robux) else ""
		price.Text = `<font color="#{ONLY}">ONLY</font> <font color="#{PRICE}">{ROBUX}{amount}</font>`
	end

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, HOVER, { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, HOVER, { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		if owned() or pass.id == 0 then
			return
		end
		Sfx.play("click")
		scale.Scale = 0.92
		TweenService:Create(scale, PRESS, { Scale = 1 }):Play()
		RobuxButton.promptPass(pass.id)
	end)

	refresh()
	return { holder = holder, refresh = refresh, owned = owned }
end

function PassOfferController.start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "PassOffers"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 53
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	-- Anchored top-right, so the fit scale shrinks the stack into the right edge.
	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.BackgroundTransparency = 1
	stack.AnchorPoint = Vector2.new(1, 0)
	stack.Size = UDim2.fromOffset(CARD_W, STEP * #CARDS)
	stack.Parent = canvas
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = stack

	local built: { Built } = {}
	for _, look in CARDS do
		local card = build(stack, look)
		if card then
			card.holder.Position = UDim2.new(1, 0, 0, 0)
			table.insert(built, card)
		end
	end

	-- Owned cards go; the rest close up from the top.
	local function layout(animate: boolean)
		local slot = 0
		for _, card in built do
			card.holder.Visible = not card.owned()
			if card.holder.Visible then
				local target = UDim2.new(1, 0, 0, ICON_OUT.Y + slot * STEP)
				if animate then
					TweenService:Create(card.holder, MOVE, { Position = target }):Play()
				else
					card.holder.Position = target
				end
				slot += 1
			end
		end
	end

	local function place()
		local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
		local top = height / 2 + Dock.sideColumnTop(height)
		local room = height - LUCK_CLEAR - top
		local need = ICON_OUT.Y + STEP * #CARDS
		fit.Scale = math.clamp(room / need, MIN_FIT, 1)
		stack.Position = UDim2.new(1, -(Dock.ROW_SIDE_MARGIN + 4), 0, top)
	end
	UIKit.onScaleChanged(place)
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)

	for _, look in CARDS do
		player:GetAttributeChangedSignal(GamePasses.attr(look.key)):Connect(function()
			layout(true)
		end)
	end
	layout(false)
	place()
	gui.Parent = player:WaitForChild("PlayerGui")
end

return PassOfferController
