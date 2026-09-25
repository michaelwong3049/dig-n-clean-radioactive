--[[
	AwayEarningsController.luau — the "While you were away" card. Shows once on login
	when your stands earned something while you were offline (Config/AwayEarnings,
	Services/AwayEarningsService).

	THE GOLD COIN CARD, option 1 of seven mockups: the cash badge's own toy-shop voice
	(CashController's STYLE), a thick ink outline on every shape, hard offset shadows,
	an orange ribbon across the top, a spinning coin beside the amount counting up,
	two pills (time away, offline $/s), and the buttons. A red BANK FULL! sticker
	shows when the time away ran past the offline cap.

	COLLECT and DOUBLE IT. The amount waits on the server until COLLECT; the coins fly
	from the button into the cash badge and the collect request goes out as they land,
	so the badge's own count-up and "+$X" popup (CashState) play as they arrive.
	DOUBLE IT prompts the Robux product; the card waits for the server to say the
	receipt was granted (AwayEarnings { collected, doubled }) before paying out, and
	comes back to life if the prompt is closed without buying. With no product id
	configured it shows COMING SOON and does nothing.

	Drawn on a centred 1280x720 box inside the canvas (the canvas is wider than 1280
	off 16:9), in a CanvasGroup so the whole card fades as one.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local AwayEarnings = require(Shared.Config.AwayEarnings)

local UIKit = require(script.Parent.Parent.UIKit)

local AwayEarningsController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

-- CashController's gold, so the card reads as the badge's own.
local STYLE = {
	card = Color3.fromHex("FFCF3A"),
	cardShine = Color3.fromHex("FFE27F"),
	ribbon = Color3.fromHex("FF7A1A"),
	coin = Color3.fromHex("FFB81C"),
	coinFace = Color3.fromHex("FFD34D"),
	coinRim = Color3.fromHex("D98A00"),
	coinMark = Color3.fromHex("B36A00"),
	pillText = Color3.fromHex("FFE27A"),
	collect = Color3.fromHex("45C845"),
	collectHover = Color3.fromHex("5CDD5C"),
	double = Color3.fromHex("3D7BF5"),
	doubleHover = Color3.fromHex("5A92FF"),
	off = Color3.fromHex("8A8F96"),
	sticker = Color3.fromHex("EF4444"),
	chip = Color3.fromHex("8DFF8D"),
	title = Enum.Font.LuckiestGuy,
	body = Enum.Font.FredokaOne,
}

-- Design px. The CanvasGroup is bigger than the card so the ribbon and the sticker,
-- which hang off its edges, are not clipped.
local L = {
	groupW = 560,
	groupH = 400,
	cardW = 470,
	cardH = 316,
	cardTop = 60,
	radius = 30,
	outline = 4,
	shadow = 7,
	ribbonW = 380,
	ribbonH = 54,
	coin = 96,
	coinGap = 16,
	amountSize = 58,
	amountMin = 30,
	amountY = 92, -- centre of the coin + amount row, from the card's top
	pillsY = 162,
	pillH = 34,
	pillPad = 16,
	pillGap = 10,
	buttonsY = 224,
	buttonH = 62,
	collectW = 190,
	doubleW = 230,
	buttonGap = 14,
}

local POP_IN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local COUNT = TweenInfo.new(1.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(0.12)
local DIM_ALPHA = 0.5

local remote: RemoteEvent = nil
local card: any = nil -- the open card's parts; nil when none is up

local function textWidth(text: string, size: number, font: Enum.Font): number
	return TextService:GetTextSize(text, size, font, Vector2.new(4000, 400)).X
end

--- "$400,320" in full up to the millions, where the commas stop helping: "$12.4M".
local function formatAmount(amount: number): string
	amount = math.floor(amount + 0.5)
	if amount >= 1_000_000_000 then
		return string.format("$%.2fB", amount / 1_000_000_000)
	elseif amount >= 10_000_000 then
		return string.format("$%.1fM", amount / 1_000_000)
	end
	local digits = tostring(amount)
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. grouped:gsub("^,", "")
end

--- CashController's rate ladder: "+$34.75/s", "+$139/s", "+$1.2K/s".
local function formatRate(perSecond: number): string
	if perSecond >= 1_000_000 then
		return string.format("+$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 1000 then
		return string.format("+$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("+$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("+$%.1f/s", perSecond)
	end
	return string.format("+$%.2f/s", perSecond)
end

--- "3h 12m", "4h", "20m", "45s".
local function formatAway(seconds: number): string
	seconds = math.floor(seconds)
	if seconds < 60 then
		return `{seconds}s`
	end
	local h, m = seconds // 3600, (seconds % 3600) // 60
	if h == 0 then
		return `{m}m`
	end
	return if m > 0 then `{h}h {m}m` else `{h}h`
end

--- One flat, outlined cartoon shape (CashController's blob).
local function blob(parent: Instance, name: string, rect: { number }, color: Color3, zIndex: number, radius: UDim, stroke: number?): Frame
	return (UIKit.panel(parent, {
		name = name,
		position = UDim2.fromOffset(rect[1], rect[2]),
		size = UDim2.fromOffset(rect[3], rect[4]),
		color = color,
		transparency = 0,
		cornerRadius = radius,
		strokeColor = INK,
		strokeThickness = stroke or 0,
		zIndex = zIndex,
	}))
end

local function inkLabel(parent: Instance, props: any): TextLabel
	local label = UIKit.label(parent, {
		name = props.name,
		size = props.size,
		position = props.position,
		anchorPoint = props.anchorPoint,
		text = props.text,
		font = props.font or STYLE.title,
		textSize = props.textSize,
		color = props.color or WHITE,
		xAlign = props.xAlign or Enum.TextXAlignment.Center,
		shadow = false,
		outline = props.outline,
		zIndex = props.zIndex,
	})
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke and props.stroke then
		stroke.Thickness = props.stroke
	end
	return label
end

--- A chunky button: ink shadow, coloured face, ink border, outlined caption.
local function makeButton(parent: Instance, name: string, x: number, y: number, w: number, color: Color3, text: string): (TextButton, TextLabel)
	local round = UDim.new(0, 18)
	blob(parent, name .. "Shadow", { x, y + 5, w, L.buttonH }, INK, 20, round)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = color
	button.Position = UDim2.fromOffset(x, y)
	button.Size = UDim2.fromOffset(w, L.buttonH)
	button.ZIndex = 21
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = round
	corner.Parent = button
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = INK
	edge.Thickness = L.outline
	edge.Parent = button
	local caption = inkLabel(button, {
		name = "Caption",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromOffset(0, 3),
		text = text,
		textSize = 28,
		stroke = 3,
		zIndex = 22,
	})
	return button, caption
end

-- ── The coin burst ───────────────────────────────────────────────────────────

--- Where the cash badge's coin is, in this card's canvas px, so the coins land on it.
local function badgeTarget(canvas: Frame): Vector2
	local scale = UIKit.canvasScale(canvas)
	local hud = Players.LocalPlayer.PlayerGui:FindFirstChild("CashHud")
	local coin = hud and hud:FindFirstChild("Coin", true)
	if coin and coin:IsA("GuiObject") then
		local centre = coin.AbsolutePosition + coin.AbsoluteSize / 2
		return (centre - canvas.AbsolutePosition) / scale
	end
	return Vector2.new(60, canvas.AbsoluteSize.Y / scale / 2)
end

--- Coins burst out of `from` and fly into the cash badge. Returns when the first lands.
local function flyCoins(canvas: Frame, from: GuiObject, count: number): number
	local scale = UIKit.canvasScale(canvas)
	local start = (from.AbsolutePosition + from.AbsoluteSize / 2 - canvas.AbsolutePosition) / scale
	local target = badgeTarget(canvas)
	local rng = Random.new()
	local burstTime, flyTime, stagger = 0.25, 0.55, 0.04
	for i = 1, count do
		local coin = blob(canvas, "FlyingCoin", { 0, 0, 32, 32 }, STYLE.coin, 40, UDim.new(0.5, 0), 3)
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Position = UDim2.fromOffset(start.X, start.Y)
		blob(coin, "Face", { 6, 6, 20, 20 }, STYLE.coinFace, 41, UDim.new(0.5, 0))
		local out = start + Vector2.new(rng:NextNumber(-110, 110), rng:NextNumber(-110, -30))
		task.delay((i - 1) * stagger, function()
			local burst = TweenService:Create(
				coin,
				TweenInfo.new(burstTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(out.X, out.Y) }
			)
			burst:Play()
			burst.Completed:Wait()
			local fly = TweenService:Create(
				coin,
				TweenInfo.new(flyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.fromOffset(target.X, target.Y), Size = UDim2.fromOffset(20, 20) }
			)
			fly:Play()
			fly.Completed:Wait()
			coin:Destroy()
		end)
	end
	return burstTime + flyTime
end

-- ── The card ─────────────────────────────────────────────────────────────────

local function close()
	local c = card
	if c == nil or c.closing then
		return
	end
	c.closing = true
	if c.spin then
		c.spin:Disconnect()
	end
	TweenService:Create(c.group, POP_OUT, { GroupTransparency = 1 }):Play()
	TweenService:Create(c.popScale, POP_OUT, { Scale = 0.85 }):Play()
	TweenService:Create(c.dim, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	task.delay(1.6, function()
		c.gui:Destroy()
		if card == c then
			card = nil
		end
	end)
end

local function setBusy(busy: boolean)
	local c = card
	if c == nil then
		return
	end
	c.busy = busy
	c.collect.BackgroundColor3 = if busy then STYLE.off else STYLE.collect
	if c.doubleLive then
		c.double.BackgroundColor3 = if busy then STYLE.off else STYLE.double
	end
end

--- Pay out from `button`: coins to the badge, and `onLand` as the first one arrives.
local function payOut(button: GuiObject, coins: number, onLand: (() -> ())?)
	local c = card
	if c == nil or c.closing then
		return
	end
	local land = flyCoins(c.canvas, button, coins)
	task.delay(0.12, close)
	if onLand then
		task.delay(land, onLand)
	end
end

local function setAmount(amount: number)
	local c = card
	if c == nil then
		return
	end
	c.amount = amount
	local text = formatAmount(amount)
	local room = L.cardW - 56 - L.coin - L.coinGap
	local size = L.amountSize
	while size > L.amountMin and textWidth(text, size, STYLE.title) > room do
		size -= 2
	end
	c.amountLabel.TextSize = size
	-- Centre the coin + number as one group, measured at the final value.
	local groupW = L.coin + L.coinGap + textWidth(text, size, STYLE.title)
	local left = (L.cardW - groupW) / 2
	c.coinHolder.Position = UDim2.fromOffset(left, L.amountY - L.coin / 2)
	c.amountLabel.Position = UDim2.fromOffset(left + L.coin + L.coinGap, L.amountY - 40)
	c.amountLabel.Size = UDim2.fromOffset(groupW - L.coin - L.coinGap + 20, 80)
	TweenService:Create(c.shown, COUNT, { Value = amount }):Play()
end

local function pill(parent: Instance, name: string, text: string): Frame
	local width = textWidth(text, 20, STYLE.body) + L.pillPad * 2
	local frame = blob(parent, name, { 0, L.pillsY, width, L.pillH }, INK, 12, UDim.new(0.5, 0))
	UIKit.label(frame, {
		name = "Text",
		size = UDim2.fromScale(1, 1),
		text = text,
		font = STYLE.body,
		textSize = 20,
		color = STYLE.pillText,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		zIndex = 13,
	})
	return frame
end

local function open(offer: any)
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "AwayEarningsHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	-- A button, not a Frame, so it swallows clicks meant for the world behind it.
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = 1
	dim.Parent = canvas

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.Size = UDim2.fromOffset(1280, 720)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.BackgroundTransparency = 1
	box.ZIndex = 2
	box.Parent = canvas

	local group = Instance.new("CanvasGroup")
	group.Name = "Card"
	group.Size = UDim2.fromOffset(L.groupW, L.groupH)
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromOffset(640, 350)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.ZIndex = 3
	group.Parent = box
	local popScale = Instance.new("UIScale")
	popScale.Scale = 0.5
	popScale.Parent = group

	-- The card's own frame inside the group; everything below is placed on it.
	local cardX = (L.groupW - L.cardW) / 2
	local radius = UDim.new(0, L.radius)
	blob(group, "CardShadow", { cardX, L.cardTop + L.shadow, L.cardW, L.cardH }, INK, 4, radius)
	local face = blob(group, "Face", { cardX, L.cardTop, L.cardW, L.cardH }, STYLE.card, 5, radius, L.outline)
	blob(face, "Shine", { 16, 12, L.cardW - 32, 26 }, STYLE.cardShine, 6, UDim.new(0.5, 0))

	-- The ribbon across the top edge.
	local ribbonX = (L.groupW - L.ribbonW) / 2
	local ribbonY = L.cardTop - L.ribbonH / 2 - 4
	local ribbonRound = UDim.new(0, 16)
	blob(group, "RibbonShadow", { ribbonX, ribbonY + 5, L.ribbonW, L.ribbonH }, INK, 30, ribbonRound)
	local ribbon = blob(group, "Ribbon", { ribbonX, ribbonY, L.ribbonW, L.ribbonH }, STYLE.ribbon, 31, ribbonRound, L.outline)
	inkLabel(ribbon, {
		name = "Title",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromOffset(0, 3),
		text = "WHILE YOU WERE AWAY",
		textSize = 30,
		stroke = 3,
		zIndex = 32,
	})

	if offer.capped then
		local sticker = blob(group, "Sticker", { cardX + L.cardW - 108, L.cardTop + 34, 138, 40 }, STYLE.sticker, 33, UDim.new(0, 12), 3)
		sticker.Rotation = 12
		inkLabel(sticker, {
			name = "Text",
			size = UDim2.fromScale(1, 1),
			position = UDim2.fromOffset(0, 2),
			text = "BANK FULL!",
			textSize = 20,
			stroke = 2.5,
			zIndex = 34,
		})
	end

	-- The coin: a holder the spin squeezes the coin inside, so it turns in place.
	local coinHolder = Instance.new("Frame")
	coinHolder.Name = "CoinHolder"
	coinHolder.BackgroundTransparency = 1
	coinHolder.Size = UDim2.fromOffset(L.coin, L.coin)
	coinHolder.ZIndex = 7
	coinHolder.Parent = face
	local coinShadow = blob(coinHolder, "CoinShadow", { 0, 0, L.coin, L.coin }, INK, 7, UDim.new(0.5, 0))
	local coin = blob(coinHolder, "Coin", { 0, 0, L.coin, L.coin }, STYLE.coin, 8, UDim.new(0.5, 0), L.outline)
	for _, part in { coinShadow, coin } do
		part.AnchorPoint = Vector2.new(0.5, 0.5)
		part.Position = UDim2.new(0.5, 0, 0.5, if part == coinShadow then 5 else 0)
	end
	local coinFace = blob(coin, "Face", { 0, 0, 0, 0 }, STYLE.coinFace, 9, UDim.new(0.5, 0), 3)
	coinFace.AnchorPoint = Vector2.new(0.5, 0.5)
	coinFace.Position = UDim2.fromScale(0.5, 0.5)
	coinFace.Size = UDim2.fromScale(0.72, 0.72)
	coinFace:FindFirstChildOfClass("UIStroke").Color = STYLE.coinRim
	local mark = UIKit.label(coin, {
		name = "Mark",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromOffset(0, 6),
		text = "$",
		font = STYLE.title,
		textSize = 50,
		color = STYLE.coinMark,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		zIndex = 10,
	})

	local amountLabel = inkLabel(face, {
		name = "Amount",
		size = UDim2.fromOffset(300, 80),
		text = "$0",
		textSize = L.amountSize,
		stroke = 4,
		xAlign = Enum.TextXAlignment.Left,
		zIndex = 11,
	})
	local shown = Instance.new("NumberValue")
	shown.Changed:Connect(function(value: number)
		amountLabel.Text = formatAmount(value)
	end)

	-- The pills, centred as a row.
	local awayPill = pill(face, "AwayPill", `Away {formatAway(offer.away)}`)
	local ratePill = pill(face, "RatePill", formatRate(offer.rate))
	local pillsW = awayPill.Size.X.Offset + L.pillGap + ratePill.Size.X.Offset
	local pillsLeft = (L.cardW - pillsW) / 2
	awayPill.Position = UDim2.fromOffset(pillsLeft, L.pillsY)
	ratePill.Position = UDim2.fromOffset(pillsLeft + awayPill.Size.X.Offset + L.pillGap, L.pillsY)

	-- The buttons.
	local live = AwayEarnings.PRODUCT_ID ~= 0
	local buttonsLeft = (L.cardW - L.collectW - L.buttonGap - L.doubleW) / 2
	local collect = makeButton(face, "Collect", buttonsLeft, L.buttonsY, L.collectW, STYLE.collect, "COLLECT")
	local double, doubleCaption = makeButton(
		face,
		"Double",
		buttonsLeft + L.collectW + L.buttonGap,
		L.buttonsY,
		L.doubleW,
		if live then STYLE.double else STYLE.off,
		if live then "DOUBLE IT" else "COMING SOON"
	)
	if not live then
		doubleCaption.TextSize = 22
	else
		-- The price chip, filled in from the product itself so a dashboard price change
		-- never needs a code change.
		doubleCaption.Size = UDim2.new(1, -70, 1, 0)
		local chip = blob(double, "Price", { L.doubleW - 74, 15, 62, 32 }, INK, 23, UDim.new(0, 10))
		local price = UIKit.label(chip, {
			name = "Text",
			size = UDim2.fromScale(1, 1),
			text = "R$",
			font = STYLE.body,
			textSize = 17,
			color = STYLE.chip,
			xAlign = Enum.TextXAlignment.Center,
			outline = false,
			strokeTransparency = 1,
			shadow = false,
			zIndex = 24,
		})
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(AwayEarnings.PRODUCT_ID, Enum.InfoType.Product)
			end)
			if ok and info and info.PriceInRobux then
				price.Text = `R$ {info.PriceInRobux}`
			end
		end)
	end

	card = {
		gui = gui,
		canvas = canvas,
		dim = dim,
		group = group,
		popScale = popScale,
		coinHolder = coinHolder,
		amountLabel = amountLabel,
		shown = shown,
		collect = collect,
		double = double,
		doubleLive = live,
		amount = 0,
		busy = false,
		buying = false,
		closing = false,
		spin = nil :: RBXScriptConnection?,
	}
	local c = card

	-- The coin turns: squeeze it to its edge and back, fading the $ as it goes thin.
	local born = os.clock()
	c.spin = RunService.RenderStepped:Connect(function()
		local k = math.max(0.1, math.abs(math.cos((os.clock() - born) * 2.4)))
		coin.Size = UDim2.fromScale(k, 1)
		coinShadow.Size = coin.Size
		mark.TextTransparency = if k < 0.45 then 1 else 0
	end)

	local function hover(button: TextButton, normal: Color3, lit: Color3, isLive: () -> boolean)
		button.MouseEnter:Connect(function()
			if isLive() then
				TweenService:Create(button, HOVER, { BackgroundColor3 = lit }):Play()
			end
		end)
		button.MouseLeave:Connect(function()
			if isLive() then
				TweenService:Create(button, HOVER, { BackgroundColor3 = normal }):Play()
			end
		end)
	end
	hover(collect, STYLE.collect, STYLE.collectHover, function()
		return not c.busy
	end)
	hover(double, STYLE.double, STYLE.doubleHover, function()
		return live and not c.busy
	end)

	collect.Activated:Connect(function()
		if c.busy or c.closing then
			return
		end
		c.busy = true
		payOut(collect, 12, function()
			remote:FireServer("collect")
		end)
	end)
	double.Activated:Connect(function()
		if not live or c.busy or c.closing then
			return
		end
		setBusy(true)
		c.buying = true
		MarketplaceService:PromptProductPurchase(player, AwayEarnings.PRODUCT_ID)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	setAmount(offer.amount)
	TweenService:Create(dim, TweenInfo.new(0.35), { BackgroundTransparency = DIM_ALPHA }):Play()
	TweenService:Create(group, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	TweenService:Create(popScale, POP_IN, { Scale = 1 }):Play()
end

local function onMessage(message: any)
	if type(message) ~= "table" then
		return
	end

	if message.collected then
		-- The DOUBLE IT receipt went through (or the server paid out some other way
		-- while the card was up): fly the coins and close.
		local c = card
		if c and not c.closing then
			local from = if message.doubled then c.double else c.collect
			payOut(from, if message.doubled then 22 else 12, nil)
		end
		return
	end

	if type(message.amount) ~= "number" or message.amount < 1 then
		return
	end
	if card and not card.closing then
		setAmount(message.amount)
		return
	end
	open(message)
end

function AwayEarningsController.start()
	remote = Net.get("AwayEarnings")
	remote.OnClientEvent:Connect(onMessage)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local c = card
		if userId ~= Players.LocalPlayer.UserId or productId ~= AwayEarnings.PRODUCT_ID then
			return
		end
		if c == nil or not c.buying then
			return
		end
		c.buying = false
		-- Bought: the server's { collected, doubled } push closes the card. Not bought:
		-- the card comes back to life.
		if not purchased then
			setBusy(false)
		end
	end)

	-- In case the profile loaded (and the offer was pushed) before this connected.
	remote:FireServer("ask")
end

return AwayEarningsController
