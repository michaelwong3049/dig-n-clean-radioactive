--[[
	FloorPurchaseController.luau — the "Purchase floor" popup. Holding E on your own
	base's floor sign opens it (ExhibitService sends FloorPurchase { kind = "offer" });
	it used to buy on the spot, with a refusal written onto the sign for a moment.

	The dark slab in AwayEarningsController's voice: "FLOOR 2" over what it adds, the
	cash row's green bundle beside the price, what you have (or how much you are short,
	in red), then BUY and CANCEL. BUY sends FloorPurchase("buy", plot, floor); the
	server range-checks it and buyFloor does every other check, and its answer
	({ kind = "result" }) either closes the card with "FLOOR 2 BUILT!" or prints the
	reason in red under the buttons. Walking away from the sign closes it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Mastery = require(Shared.Mastery)
local Net = require(Shared.Net)

local Artwork = require(script.Parent.Parent.HudArtwork)
local UIKit = require(script.Parent.Parent.UIKit)

local FloorPurchaseController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

local STYLE = {
	card = Color3.fromHex("12161D"),
	rim = Color3.fromHex("2C3644"),
	money = Color3.fromHex("7CF25A"),
	sub = Color3.fromHex("C9D3DE"),
	short = Color3.fromHex("FF6B6B"),
	buy = UIKit.House.buy,
	buyHover = UIKit.House.buyHover,
	cancel = Color3.fromHex("4A5462"),
	cancelHover = Color3.fromHex("5D6879"),
	off = Color3.fromHex("8A8F96"),
	title = Enum.Font.GothamBlack,
	body = Enum.Font.GothamBold,
}

-- Design px, on a centred 1280x720 box.
local L = {
	cardW = 460,
	cardH = 330,
	outline = 4,
	rim = 4,
	shadow = 7,
	titleY = 24,
	titleSize = 44,
	subY = 76,
	subSize = 19,
	bundle = 70,
	bundleGap = 8,
	priceSize = 44,
	priceY = 146, -- centre of the bundle + price row
	haveY = 190,
	haveSize = 18,
	buttonsY = 228,
	buttonH = 58,
	buyW = 200,
	cancelW = 160,
	buttonGap = 14,
	statusY = 294,
	statusSize = 16,
	closeSize = 34,
}

local CARD_SCALE = 1.2
-- Past this many studs from the sign the card closes itself; the server refuses a BUY
-- past 16, so this stays under it.
local WALK_AWAY = 14

local POP_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER = TweenInfo.new(0.12)
local DIM_ALPHA = 0.55

local remote: RemoteEvent = nil
local card: any = nil -- the open card's parts; nil when none is up

--- "$40M" rather than "$40,000,000" (on request), matching the floor sign.
local function money(n: number): string
	return "$" .. Mastery.short(n)
end

local function blob(parent: Instance, name: string, rect: { number }, color: Color3, zIndex: number, stroke: number?): Frame
	return (UIKit.panel(parent, {
		name = name,
		position = UDim2.fromOffset(rect[1], rect[2]),
		size = UDim2.fromOffset(rect[3], rect[4]),
		color = color,
		transparency = 0,
		cornerRadius = UDim.new(0, 0),
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
		zIndex = props.zIndex,
	})
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke and props.stroke then
		stroke.Thickness = props.stroke
	end
	return label
end

local function plainLabel(parent: Instance, props: any): TextLabel
	return UIKit.label(parent, {
		name = props.name,
		size = props.size,
		position = props.position,
		text = props.text,
		font = STYLE.body,
		textSize = props.textSize,
		color = props.color or STYLE.sub,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		zIndex = props.zIndex,
	})
end

--- A chunky button: ink shadow, coloured face, ink border, outlined caption.
local function makeButton(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, text: string, textSize: number): TextButton
	blob(parent, name .. "Shadow", { x, y + 5, w, h }, INK, 20)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = color
	button.Position = UDim2.fromOffset(x, y)
	button.Size = UDim2.fromOffset(w, h)
	button.ZIndex = 21
	button.Parent = parent
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = INK
	edge.Thickness = L.outline
	edge.Parent = button
	inkLabel(button, {
		name = "Caption",
		size = UDim2.fromScale(1, 1),
		position = UDim2.fromOffset(0, 2),
		text = text,
		textSize = textSize,
		stroke = 3,
		zIndex = 22,
	})
	return button
end

local function canAfford(c: any): boolean
	return type(c.cash) == "number" and c.cash >= c.offer.price
end

--- The "You have $X" line and BUY's colour, from the latest balance.
local function refresh()
	local c = card
	if c == nil then
		return
	end
	local price = c.offer.price
	if type(c.cash) ~= "number" then
		c.have.Text = ""
	elseif c.cash >= price then
		c.have.Text = `You have {money(c.cash)}`
		c.have.TextColor3 = STYLE.sub
	else
		c.have.Text = `You need {money(price - c.cash)} more`
		c.have.TextColor3 = STYLE.short
	end
	c.buy.BackgroundColor3 = if c.busy or not canAfford(c) then STYLE.off else STYLE.buy
end

local function close()
	local c = card
	if c == nil or c.closing then
		return
	end
	c.closing = true
	if c.watch then
		c.watch:Disconnect()
	end
	if c.keys then
		c.keys:Disconnect()
	end
	TweenService:Create(c.group, POP_OUT, { GroupTransparency = 1 }):Play()
	TweenService:Create(c.popScale, POP_OUT, { Scale = 0.85 * CARD_SCALE }):Play()
	TweenService:Create(c.dim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
	task.delay(0.35, function()
		c.gui:Destroy()
		if card == c then
			card = nil
		end
	end)
end

--- A short side-to-side shake for a refused BUY.
local function shake(group: GuiObject)
	local home = group.Position
	for _, dx in { -10, 9, -6, 4, 0 } do
		group.Position = home + UDim2.fromOffset(dx, 0)
		task.wait(0.035)
	end
	group.Position = home
end

local function open(offer: any)
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "FloorPurchaseHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 96
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	-- A button, not a Frame, so it swallows clicks meant for the world behind it; a
	-- click on it (outside the card) cancels.
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

	local pad = 20 -- room in the group for the rim and the shadow
	local group = Instance.new("CanvasGroup")
	group.Name = "Card"
	group.Size = UDim2.fromOffset(L.cardW + pad * 2, L.cardH + pad * 2)
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromOffset(640, 360)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.ZIndex = 3
	group.Parent = box
	local popScale = Instance.new("UIScale")
	popScale.Scale = 0.5 * CARD_SCALE
	popScale.Parent = group

	blob(group, "CardShadow", { pad, pad + L.shadow, L.cardW, L.cardH }, INK, 4)
	blob(group, "Rim", { pad - L.rim, pad - L.rim, L.cardW + L.rim * 2, L.cardH + L.rim * 2 }, STYLE.rim, 4)
	local face = blob(group, "Face", { pad, pad, L.cardW, L.cardH }, STYLE.card, 5, L.outline)

	local title = inkLabel(face, {
		name = "Title",
		size = UDim2.new(1, 0, 0, 50),
		position = UDim2.fromOffset(0, L.titleY),
		text = `FLOOR {offer.floor}`,
		textSize = L.titleSize,
		stroke = 3.5,
		zIndex = 12,
	})
	plainLabel(face, {
		name = "Adds",
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromOffset(0, L.subY),
		text = `+{offer.stands} display stands for your nukes`,
		textSize = L.subSize,
		zIndex = 12,
	})

	-- The bundle and the price, centred as one group.
	local priceText = money(offer.price)
	local priceW = game:GetService("TextService"):GetTextSize(priceText, L.priceSize, STYLE.title, Vector2.new(4000, 200)).X
	local rowW = L.bundle + L.bundleGap + priceW
	local left = (L.cardW - rowW) / 2
	local bundle = Artwork.droppedPicture(face, "Bundle", Artwork.IMAGE.cashBundle, L.bundle, Vector2.new(3, 4), 8)
	bundle.Position = UDim2.fromOffset(left, L.priceY - L.bundle / 2)
	inkLabel(face, {
		name = "Price",
		size = UDim2.fromOffset(priceW + 20, 60),
		position = UDim2.fromOffset(left + L.bundle + L.bundleGap, L.priceY - 30),
		text = priceText,
		textSize = L.priceSize,
		color = STYLE.money,
		stroke = 4,
		xAlign = Enum.TextXAlignment.Left,
		zIndex = 11,
	})

	local have = plainLabel(face, {
		name = "Have",
		size = UDim2.new(1, 0, 0, 22),
		position = UDim2.fromOffset(0, L.haveY),
		text = "",
		textSize = L.haveSize,
		zIndex = 12,
	})

	local buttonsLeft = (L.cardW - L.buyW - L.buttonGap - L.cancelW) / 2
	local buy = makeButton(face, "Buy", buttonsLeft, L.buttonsY, L.buyW, L.buttonH, STYLE.buy, "BUY", 28)
	local cancel = makeButton(face, "Cancel", buttonsLeft + L.buyW + L.buttonGap, L.buttonsY, L.cancelW, L.buttonH, STYLE.cancel, "CANCEL", 24)
	local closeButton = makeButton(face, "Close", L.cardW - L.closeSize - 10, 10, L.closeSize, L.closeSize, STYLE.short, "X", 22)

	local status = plainLabel(face, {
		name = "Status",
		size = UDim2.new(1, -24, 0, 20),
		position = UDim2.fromOffset(12, L.statusY),
		text = "",
		textSize = L.statusSize,
		color = STYLE.short,
		zIndex = 12,
	})

	card = {
		gui = gui,
		dim = dim,
		group = group,
		popScale = popScale,
		title = title,
		have = have,
		buy = buy,
		status = status,
		offer = offer,
		cash = offer.cash,
		busy = false,
		closing = false,
		watch = nil :: RBXScriptConnection?,
		keys = nil :: RBXScriptConnection?,
	}
	local c = card
	refresh()

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
	hover(buy, STYLE.buy, STYLE.buyHover, function()
		return not c.busy and canAfford(c)
	end)
	hover(cancel, STYLE.cancel, STYLE.cancelHover, function()
		return true
	end)

	buy.Activated:Connect(function()
		if c.busy or c.closing then
			return
		end
		if not canAfford(c) then
			status.Text = "Not enough cash yet"
			task.spawn(shake, group)
			return
		end
		c.busy = true
		status.Text = ""
		refresh()
		remote:FireServer("buy", offer.plot, offer.floor)
	end)
	cancel.Activated:Connect(close)
	closeButton.Activated:Connect(close)
	dim.Activated:Connect(close)
	c.keys = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
			close()
		end
	end)

	-- Walk away from the sign and the card goes with you.
	local board = offer.board
	c.watch = RunService.Heartbeat:Connect(function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if typeof(board) ~= "Instance" or not board:IsA("BasePart") or not board:IsDescendantOf(workspace) then
			close()
		elseif root and ((root :: BasePart).Position - board.Position).Magnitude > WALK_AWAY then
			close()
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = DIM_ALPHA }):Play()
	TweenService:Create(group, TweenInfo.new(0.2), { GroupTransparency = 0 }):Play()
	TweenService:Create(popScale, POP_IN, { Scale = CARD_SCALE }):Play()
end

local function onResult(message: any)
	local c = card
	if c == nil or c.closing or message.floor ~= c.offer.floor then
		return
	end
	c.busy = false
	if type(message.cash) == "number" then
		c.cash = message.cash
	end
	if message.ok then
		c.busy = true -- nothing more to press
		c.title.Text = `FLOOR {c.offer.floor} BUILT!`
		c.title.TextColor3 = STYLE.money
		c.status.Text = ""
		refresh()
		task.delay(1.2, close)
		return
	end
	-- buyFloor's reasons are lower-case clauses ("you need $X more"); capitalise.
	local reason = if type(message.message) == "string" then message.message else "couldn't build that floor"
	c.status.Text = reason:sub(1, 1):upper() .. reason:sub(2)
	refresh()
	task.spawn(shake, c.group)
end

function FloorPurchaseController.start()
	remote = Net.get("FloorPurchase")
	remote.OnClientEvent:Connect(function(message: any)
		if type(message) ~= "table" then
			return
		end
		if message.kind == "offer" and type(message.floor) == "number" and type(message.price) == "number" then
			if card and not card.closing then
				return
			end
			open(message)
		elseif message.kind == "result" then
			onResult(message)
		end
	end)

	-- Keep "You have $X" live while the card is up.
	Net.get("CashState").OnClientEvent:Connect(function(amount: number)
		local c = card
		if c and not c.closing and type(amount) == "number" then
			c.cash = amount
			refresh()
		end
	end)
end

return FloorPurchaseController
