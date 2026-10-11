--!strict
--[[
	SpeedPanel.luau — the Upgrades booth's walk-speed panel, drawn inside
	StationController's panel (the booth that used to be the Magnet Shop; Config/Booths).

	Walk speed is bought here now that the treadmill is gone (Config/WalkSpeed), and
	max health beside it (Config/HealthUpgrade, 2026-10-10). Each is ONE ROW (on request,
	"make the speed purchases in one row, like 1 3 10 then robux"): green +1 / +3 / +10
	cash buttons, each "+N" over its price (grey when short), then the purple Robux +10.
	Speed's depth step makes every point cheaper deeper down (WalkSpeed.bulkPriceFor).

	TOP TO BOTTOM:
	  the header      UPGRADES, what it is for, and the wallet.
	  speed card      the shoe, WALK SPEED, the depth chip, the next cheaper stage.
	  speed row       +1 / +3 / +10 / Robux (WalkSpeed.PRODUCT_ID) on Net.SpeedBuy.
	  health card     the heart, MAX HEALTH (the HUD's), HP per point, bought so far.
	  health row      +1 / +3 / +10 / Robux (HealthUpgrade.PRODUCT_ID) on Net.HealthBuy.

	Everything here is presentation. SpeedService re-derives the price, the step and
	that you are at an Upgrades booth. The numbers come off SpeedState
	(SpeedController.view), the wallet off StationState, max health off the HUD.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local WalkSpeed = require(Shared.Config.WalkSpeed)
local HealthUpgrade = require(Shared.Config.HealthUpgrade)
local Mastery = require(Shared.Mastery)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.UIKit)
local Studded = require(script.Parent.Studded)
local HudArtwork = require(script.Parent.HudArtwork)
local RobuxButton = require(script.Parent.RobuxButton)
local Sfx = require(script.Parent.Sfx)
local Speed = require(script.Parent.Controllers.SpeedController)
local Hud = require(script.Parent.Controllers.HudController)

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
local CARD_H = 130
local ROW_H = 58
local GAP = 10
local SECTION_GAP = 16
local WALLET_INSET = 44
local ICON = 96

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
	root.Size = UDim2.new(1, 0, 0, HEADER_H + GAP + 2 * (CARD_H + GAP + ROW_H) + SECTION_GAP)
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
		text = "Walk speed and max health. Go deeper for cheaper speed.",
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

	-- ── A card + its row of buttons, once for speed and once for health ───
	local y = HEADER_H + GAP

	-- One stat's card: the icon on rays, a caption, the big value, a chip and a hint.
	type Card = { value: TextLabel, chip: TextLabel, hint: TextLabel }
	local function statCard(name: string, image: string, caption: string, top: Color3, bottom: Color3): Card
		local card = frame(root, name, SKIN.card)
		card.Position = UDim2.fromOffset(0, y)
		card.Size = UDim2.new(1, 0, 0, CARD_H)
		card.ClipsDescendants = true
		corner(card, 14)
		edge(card, SKIN.ink, 3)
		local cardFill = Instance.new("UIGradient")
		cardFill.Rotation = 90
		cardFill.Color = ColorSequence.new(top, bottom)
		cardFill.Parent = card

		local rays = Instance.new("ImageLabel")
		rays.Name = "Rays"
		rays.BackgroundTransparency = 1
		rays.Image = HudArtwork.IMAGE.sunburst
		rays.ImageTransparency = 0.7
		rays.ScaleType = Enum.ScaleType.Fit
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.new(0, 20 + ICON / 2, 0.5, 0)
		rays.Size = UDim2.fromOffset(ICON * 2, ICON * 2)
		rays.Parent = card
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Image = image
		icon.ScaleType = Enum.ScaleType.Fit
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 20, 0.5, 0)
		icon.Size = UDim2.fromOffset(ICON, ICON)
		icon.Parent = card

		local textLeft = 20 + ICON + 24
		text(card, {
			name = "Caption",
			position = UDim2.fromOffset(textLeft, 12),
			size = UDim2.new(1, -textLeft - 16, 0, 18),
			textSize = 16,
			color = SKIN.dim,
			text = caption,
		})
		local value = text(card, {
			name = "Value",
			position = UDim2.fromOffset(textLeft, 30),
			size = UDim2.new(1, -textLeft - 16, 0, 46),
			textSize = 42,
		})
		value.RichText = true
		local chip = text(card, {
			name = "Chip",
			position = UDim2.fromOffset(textLeft, 80),
			size = UDim2.new(1, -textLeft - 16, 0, 20),
			textSize = 18,
			color = SKIN.go,
		})
		local hint = text(card, {
			name = "Hint",
			position = UDim2.fromOffset(textLeft, 104),
			size = UDim2.new(1, -textLeft - 16, 0, 18),
			textSize = 14,
			color = SKIN.dim,
			wrapped = true,
			ink = false,
		})
		hint.TextYAlignment = Enum.TextYAlignment.Top
		y += CARD_H + GAP
		return { value = value, chip = chip, hint = hint }
	end

	-- A green studded cash button: "+N" over its price.
	type Cash = { amount: number, button: TextButton, edge: UIStroke, price: TextLabel, affordable: boolean }
	local function cashButton(host: Instance, amount: number): Cash
		local button = Instance.new("TextButton")
		button.Name = `Buy{amount}`
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Text = ""
		button.Parent = host
		corner(button, 12)
		local stroke = edge(button, SKIN.goEdge, 3)
		local gloss = Instance.new("UIGradient")
		gloss.Rotation = 90
		gloss.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
		gloss.Parent = button
		Studded.pattern(button, { radius = 12, tile = Studded.BUTTON_TILE, bands = { 0.28, 0.5, 0.58, 0.64 }, bandTransparency = 0.8, studTransparency = 0.35, glow = false })
		local label = text(button, {
			name = "Amount",
			position = UDim2.fromOffset(4, 4),
			size = UDim2.new(1, -8, 0, 28),
			textSize = 26,
			xAlign = Enum.TextXAlignment.Center,
			text = `+{amount}`,
		})
		label.ZIndex = 3
		local price = text(button, {
			name = "Price",
			position = UDim2.fromOffset(4, 32),
			size = UDim2.new(1, -8, 0, 20),
			textSize = 17,
			xAlign = Enum.TextXAlignment.Center,
		})
		price.ZIndex = 3
		return { amount = amount, button = button, edge = stroke, price = price, affordable = false }
	end

	-- One row: the cash buttons, then the purple Robux button, all one width.
	local function buyRow(name: string, amounts: { number }, getProduct: () -> number, robuxCaption: string): { Cash }
		local row = frame(root, name)
		row.Position = UDim2.fromOffset(0, y)
		row.Size = UDim2.new(1, 0, 0, ROW_H)
		local count = #amounts + 1
		local function place(node: GuiObject, i: number)
			node.AnchorPoint = Vector2.zero
			node.Size = UDim2.new(1 / count, -GAP * (count - 1) / count, 1, 0)
			node.Position = UDim2.new((i - 1) / count, GAP * (i - 1) / count, 0, 0)
		end
		local cash: { Cash } = {}
		for i, amount in amounts do
			local entry = cashButton(row, amount)
			place(entry.button, i)
			table.insert(cash, entry)
		end
		local robux = RobuxButton.product(row, getProduct, robuxCaption)
		place(robux.button, count)
		y += ROW_H + SECTION_GAP
		return cash
	end

	local speedCard = statCard("SpeedCard", HudArtwork.IMAGE.speedShoe, "WALK SPEED", Color3.fromHex("2A3A4C"), Color3.fromHex("1C232B"))
	local speedButtons = buyRow("SpeedRow", WalkSpeed.BULK, function()
		return WalkSpeed.PRODUCT_ID
	end, `+{WalkSpeed.ROBUX_WALK} SPEED`)
	local healthCard = statCard("HealthCard", HudArtwork.IMAGE.healthHeart, "MAX HEALTH", Color3.fromHex("4C2A30"), Color3.fromHex("2B1C1F"))
	local healthButtons = buyRow("HealthRow", HealthUpgrade.BULK, function()
		return HealthUpgrade.PRODUCT_ID
	end, `+{HealthUpgrade.ROBUX_POINTS * HealthUpgrade.HP_PER_POINT} HEALTH`)

	-- ── Behaviour ───────────────────────────────────────────────────────
	local lastState: any = nil

	local function paintButtons(buttons: { Cash }, prices: { any }, cash: number)
		for i, entry in buttons do
			local price = tonumber(prices[i]) or math.huge
			entry.affordable = cash >= price
			entry.price.Text = if price == math.huge then "..." else money(price)
			entry.button.BackgroundColor3 = if entry.affordable then SKIN.go else SKIN.off
			entry.edge.Color = if entry.affordable then SKIN.goEdge else SKIN.ink
		end
	end

	local function paint(state: any)
		lastState = state
		local cash = if type(state.cash) == "number" then state.cash else 0
		wallet.Text = `${Mastery.short(cash)}`

		local view = Speed.view()
		if view == nil or type(view.walk) ~= "number" then
			for _, card in { speedCard, healthCard } do
				card.value.Text = "..."
				card.chip.Text = ""
				card.hint.Text = ""
			end
			paintButtons(speedButtons, {}, cash)
			paintButtons(healthButtons, {}, cash)
			return
		end

		-- Speed: the walk, and how much cheaper the depth makes each point.
		local step = tonumber(view.step) or 1
		speedCard.value.Text = `<font color="#9FE3FF">{view.walk}</font>`
		speedCard.chip.Text = if step > 1 then `DEPTH BONUS: {step}x CHEAPER` else "+1 WALK SPEED PER POINT"
		local deepest = tonumber(view.deepestStage) or 1
		local stage, bigger = nextBiggerStep(deepest, step)
		speedCard.hint.Text = if stage and bigger
			then `Reach Stage {stage} and speed gets {bigger}x cheaper.`
			else "Deepest stage reached: the cheapest speed there is."
		paintButtons(speedButtons, if type(view.bulkPrices) == "table" then view.bulkPrices else {}, cash)

		-- Health: the max health you walk around with now, and what you have bought.
		local health = if type(view.health) == "table" then view.health else {}
		healthCard.value.Text = `<font color="#FF6B6B">{math.floor(Hud.vitals().maxHealth + 0.5)}</font>`
		healthCard.chip.Text = `+{HealthUpgrade.HP_PER_POINT} MAX HEALTH PER POINT`
		healthCard.hint.Text = `+{tonumber(health.bonus) or 0} bought so far. The 2x Health pass doubles it.`
		paintButtons(healthButtons, if type(health.prices) == "table" then health.prices else {}, cash)
	end

	local function wire(buttons: { Cash }, remote: string)
		for _, entry in buttons do
			entry.button.MouseEnter:Connect(function()
				if entry.affordable then
					entry.button.BackgroundColor3 = Color3.fromHex("85FF01")
				end
			end)
			entry.button.MouseLeave:Connect(function()
				if lastState then
					paint(lastState)
				end
			end)
			entry.button.Activated:Connect(function()
				if not entry.affordable then
					Sfx.play("denied")
					return
				end
				Net.get(remote):FireServer(entry.amount)
			end)
		end
	end
	wire(speedButtons, "SpeedBuy")
	wire(healthButtons, "HealthBuy")

	-- A purchase or a deeper stage moves the numbers between ticks. Max health reaches
	-- the HUD on ExposureService's next tick, so a push paints once more after it.
	Speed.onChanged(function()
		if lastState and root.Visible then
			paint(lastState)
			task.delay(0.6, function()
				if lastState and root.Visible then
					paint(lastState)
				end
			end)
		end
	end)

	return {
		frame = root,
		paint = paint,
	}
end

return SpeedPanel
