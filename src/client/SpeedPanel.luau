--!strict
--[[
	SpeedPanel.luau — the Upgrades booth's walk-speed panel, drawn inside
	StationController's panel (the booth that used to be the Magnet Shop; Config/Booths).

	Walk speed is bought here now that the treadmill is gone (Config/WalkSpeed). One
	press of BUY adds a step of walk speed for one price; the step grows with the deepest
	stage you have reached, the price with the walk you have bought.

	TOP TO BOTTOM:
	  the header   UPGRADES, what it is for, and the wallet.
	  the card     the shoe, WALK SPEED "42 -> 45", the step chip, and how deep you
	               have to go for the next bigger step.
	  the buttons  green BUY $price (grey NEED $x when short) and the purple Robux
	               button (WalkSpeed.PRODUCT_ID: one purchase at your step).

	Everything here is presentation. SpeedService re-derives the price, the step and
	that you are at an Upgrades booth. The numbers come off SpeedState
	(SpeedController.view), the wallet off StationState.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local WalkSpeed = require(Shared.Config.WalkSpeed)
local Mastery = require(Shared.Mastery)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.UIKit)
local Studded = require(script.Parent.Studded)
local HudArtwork = require(script.Parent.HudArtwork)
local RobuxButton = require(script.Parent.RobuxButton)
local Sfx = require(script.Parent.Sfx)
local Speed = require(script.Parent.Controllers.SpeedController)

local SpeedPanel = {}

local SKIN = {
	card = Color3.fromHex("22272C"),
	well = Color3.fromHex("1A1E22"),
	edge = Color3.fromHex("343B42"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("9AA0A6"),
	muted = Color3.fromHex("6C737A"),
	speed = Color3.fromHex("9FE3FF"), -- the HUD's walk-speed blue
	go = Color3.fromHex("5CFE01"), -- the gear shop's buy green
	goEdge = Color3.fromHex("1F6E12"),
	off = Color3.fromHex("3A4047"),
	bad = Color3.fromHex("E5484D"),
	cash = UIKit.House.cash,
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.GothamBlack,
}

--- The widest the panel is allowed to get, padding included.
SpeedPanel.WIDTH = 640

local HEADER_H = 64
local CARD_H = 200
local BUTTONS_H = 64
local GAP = 12
local WALLET_INSET = 44
local SHOE = 150

local function ink(node: TextLabel | TextButton, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = SKIN.ink
	stroke.Thickness = thickness or math.clamp(node.TextSize / 9, 1.5, 3.5)
	stroke.Parent = node
	node.TextStrokeTransparency = 1
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local label = UIKit.label(parent, {
		name = props.name,
		position = props.position,
		size = props.size,
		anchorPoint = props.anchorPoint,
		font = props.font or SKIN.headline,
		textSize = props.textSize,
		color = props.color or SKIN.text,
		xAlign = props.xAlign or Enum.TextXAlignment.Left,
		yAlign = props.yAlign,
		wrapped = props.wrapped,
		text = props.text,
		outline = false,
		strokeTransparency = 1,
	})
	if props.ink ~= false then
		ink(label)
	end
	return label
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

local function frame(parent: Instance, name: string, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or SKIN.card
	f.BackgroundTransparency = if color then 0 else 1
	f.Parent = parent
	return f
end

--- "$1.2M": a price as the panel prints it.
local function money(amount: number): string
	return WalkSpeed.priceText(amount)
end

--- The next stage past `deepest` whose step is bigger than `step`, and that step.
local function nextBiggerStep(deepest: number, step: number): (number?, number?)
	for stage = math.floor(deepest) + 1, #WalkSpeed.STAGE_STEPS do
		local bigger = WalkSpeed.stepFor(stage)
		if bigger > step then
			return stage, bigger
		end
	end
	return nil, nil
end

export type Panel = {
	frame: Frame,
	paint: (state: any) -> (),
}

function SpeedPanel.new(parent: Instance, layoutOrder: number): Panel
	local root = frame(parent, "Speed")
	root.LayoutOrder = layoutOrder
	root.Size = UDim2.new(1, 0, 0, HEADER_H + GAP + CARD_H + GAP + BUTTONS_H)
	root.Visible = false

	-- ── Header ─────────────────────────────────────────────────────────
	local header = frame(root, "Header", Color3.new(1, 1, 1))
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	corner(header, 12)
	edge(header, SKIN.ink, 3)
	local headerFill = Instance.new("UIGradient")
	headerFill.Rotation = 90
	headerFill.Color = ColorSequence.new(Color3.fromHex("3E8BD6"), Color3.fromHex("1F4E86"))
	headerFill.Parent = header
	Studded.pattern(header, { radius = 12, tile = 22, bands = { 0.28, 0.5, 0.58, 0.64 } })
	text(header, {
		name = "Title",
		position = UDim2.fromOffset(20, 4),
		size = UDim2.fromOffset(300, 36),
		textSize = 34,
		text = "UPGRADES",
	})
	text(header, {
		name = "Subtitle",
		position = UDim2.fromOffset(20, 40),
		size = UDim2.fromOffset(380, 16),
		textSize = 14,
		color = Color3.fromHex("DDF3FF"),
		text = "Buy walk speed. Go deeper for bigger upgrades.",
		ink = false,
	})
	text(header, {
		name = "WalletLabel",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 8),
		size = UDim2.fromOffset(200, 14),
		textSize = 12,
		xAlign = Enum.TextXAlignment.Right,
		text = "ON HAND",
		ink = false,
	})
	local wallet = text(header, {
		name = "Cash",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -WALLET_INSET, 0, 24),
		size = UDim2.fromOffset(200, 30),
		textSize = 26,
		color = SKIN.cash,
		xAlign = Enum.TextXAlignment.Right,
	})

	-- ── The card ───────────────────────────────────────────────────────
	local y = HEADER_H + GAP
	local card = frame(root, "Card", SKIN.card)
	card.Position = UDim2.fromOffset(0, y)
	card.Size = UDim2.new(1, 0, 0, CARD_H)
	card.ClipsDescendants = true
	corner(card, 14)
	edge(card, SKIN.ink, 3)
	local cardFill = Instance.new("UIGradient")
	cardFill.Rotation = 90
	cardFill.Color = ColorSequence.new(Color3.fromHex("2A3A4C"), Color3.fromHex("1C232B"))
	cardFill.Parent = card

	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.Image = HudArtwork.IMAGE.sunburst
	rays.ImageTransparency = 0.7
	rays.ScaleType = Enum.ScaleType.Fit
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.new(0, 24 + SHOE / 2, 0.5, 0)
	rays.Size = UDim2.fromOffset(SHOE * 2, SHOE * 2)
	rays.Parent = card
	local shoe = Instance.new("ImageLabel")
	shoe.Name = "Shoe"
	shoe.BackgroundTransparency = 1
	shoe.Image = HudArtwork.IMAGE.speedShoe
	shoe.ScaleType = Enum.ScaleType.Fit
	shoe.AnchorPoint = Vector2.new(0, 0.5)
	shoe.Position = UDim2.new(0, 24, 0.5, 0)
	shoe.Size = UDim2.fromOffset(SHOE, SHOE)
	shoe.Parent = card

	local textLeft = 24 + SHOE + 28
	text(card, {
		name = "Caption",
		position = UDim2.fromOffset(textLeft, 22),
		size = UDim2.new(1, -textLeft - 16, 0, 20),
		textSize = 18,
		color = SKIN.dim,
		text = "WALK SPEED",
	})
	local walkLine = text(card, {
		name = "Walk",
		position = UDim2.fromOffset(textLeft, 44),
		size = UDim2.new(1, -textLeft - 16, 0, 64),
		textSize = 58,
	})
	walkLine.RichText = true
	local stepChip = text(card, {
		name = "Step",
		position = UDim2.fromOffset(textLeft, 116),
		size = UDim2.new(1, -textLeft - 16, 0, 26),
		textSize = 24,
		color = SKIN.go,
	})
	local hint = text(card, {
		name = "Hint",
		position = UDim2.fromOffset(textLeft, 148),
		size = UDim2.new(1, -textLeft - 16, 0, 36),
		textSize = 15,
		color = SKIN.dim,
		wrapped = true,
		ink = false,
	})
	hint.TextYAlignment = Enum.TextYAlignment.Top

	-- ── The buttons ────────────────────────────────────────────────────
	y += CARD_H + GAP
	local buttons = frame(root, "Buttons")
	buttons.Position = UDim2.fromOffset(0, y)
	buttons.Size = UDim2.new(1, 0, 0, BUTTONS_H)

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.AutoButtonColor = false
	buy.BorderSizePixel = 0
	buy.Font = SKIN.headline
	buy.TextSize = 30
	buy.TextColor3 = SKIN.text
	buy.Size = UDim2.new(0.68, -6, 1, 0)
	buy.Parent = buttons
	corner(buy, 12)
	ink(buy, 3)
	local buyEdge = edge(buy, SKIN.goEdge, 3)
	local buyGloss = Instance.new("UIGradient")
	buyGloss.Rotation = 90
	buyGloss.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
	buyGloss.Parent = buy
	Studded.pattern(buy, { radius = 12, tile = Studded.BUTTON_TILE, bands = { 0.28, 0.5, 0.58, 0.64 }, bandTransparency = 0.8, studTransparency = 0.35, glow = false })

	local robux = RobuxButton.product(buttons, function()
		return WalkSpeed.PRODUCT_ID
	end, "+1 UPGRADE")
	robux.button.AnchorPoint = Vector2.new(1, 0)
	robux.button.Position = UDim2.fromScale(1, 0)
	robux.button.Size = UDim2.new(0.32, -6, 1, 0)

	-- ── Behaviour ───────────────────────────────────────────────────────
	local lastState: any = nil
	local affordable = false

	local function paint(state: any)
		lastState = state
		local cash = if type(state.cash) == "number" then state.cash else 0
		wallet.Text = `${Mastery.short(cash)}`

		local view = Speed.view()
		if view == nil or type(view.walk) ~= "number" then
			walkLine.Text = "..."
			stepChip.Text = ""
			hint.Text = ""
			buy.Text = "LOADING"
			buy.BackgroundColor3 = SKIN.off
			affordable = false
			return
		end
		local step = tonumber(view.step) or 1
		local price = tonumber(view.price) or 0
		local after = view.walk + step
		walkLine.Text = `{view.walk}  <font color="#5CFE01">\u{2192}</font>  <font color="#9FE3FF">{after}</font>`
		stepChip.Text = `+{step} PER UPGRADE`
		if robux.caption then
			robux.caption.Text = `+{step} SPEED`
		end

		local deepest = tonumber(view.deepestStage) or 1
		local stage, bigger = nextBiggerStep(deepest, step)
		local lines = {}
		if stage and bigger then
			table.insert(lines, `Reach Stage {stage} for +{bigger} per upgrade.`)
		else
			table.insert(lines, "Deepest stage reached: the biggest upgrades there are.")
		end
		local discount = tonumber(view.discount) or 1
		if discount < 1 then
			table.insert(lines, `Runner mastery: -{math.floor((1 - discount) * 100 + 0.5)}% price.`)
		end
		hint.Text = table.concat(lines, "  ")

		affordable = cash >= price
		if affordable then
			buy.Text = `BUY  {money(price)}`
			buy.BackgroundColor3 = SKIN.go
			buyEdge.Color = SKIN.goEdge
		else
			buy.Text = `NEED {money(price - cash)} MORE`
			buy.BackgroundColor3 = SKIN.off
			buyEdge.Color = SKIN.ink
		end
	end

	buy.MouseEnter:Connect(function()
		if affordable then
			buy.BackgroundColor3 = Color3.fromHex("85FF01")
		end
	end)
	buy.MouseLeave:Connect(function()
		if lastState then
			paint(lastState)
		end
	end)
	buy.Activated:Connect(function()
		if not affordable then
			Sfx.play("denied")
			return
		end
		Net.get("SpeedBuy"):FireServer()
	end)

	-- A purchase, a deeper stage or a mastery tier moves the numbers between ticks.
	Speed.onChanged(function()
		if lastState and root.Visible then
			paint(lastState)
		end
	end)

	return {
		frame = root,
		paint = paint,
	}
end

return SpeedPanel
