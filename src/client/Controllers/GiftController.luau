--[[
	GiftController.luau — gifting the nuke in your hands (Config/Gift, Services/GiftService).

	TWO HALVES.
	  * THE PROMPT. A "Gift nuke" ProximityPrompt on every OTHER player's root, made on
	    this client so nobody ever sees one on themselves. It is on only while you are
	    GiftReady (past Toxic Twilight, holding a nuke) and they are GiftUnlocked --
	    both attributes the server publishes. Holding T fires Gift("offer", them); the
	    server re-checks all of it.
	  * THE CARD. The receiver's popup, in FloorPurchaseController's dark-slab voice:
	    "GIFT FROM <name>", the nuke turning in a well, its rarity / stars / kg and what
	    it would earn, a lapse countdown, then ACCEPT and DECLINE.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Gift = require(Shared.Config.Gift)
local Rarity = require(Shared.Config.Rarity)
local Mastery = require(Shared.Mastery) -- Mastery.short: "$360M"
local ItemModels = require(Shared.ItemModels)

local UIKit = require(script.Parent.Parent.UIKit)
local ItemArt = require(script.Parent.Parent.ItemArt)

local GiftController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

local STYLE = {
	card = Color3.fromHex("12161D"),
	rim = Color3.fromHex("2C3644"),
	well = Color3.fromHex("1C232D"),
	money = Color3.fromHex("7CF25A"),
	sub = Color3.fromHex("C9D3DE"),
	bad = Color3.fromHex("FF6B6B"),
	accept = UIKit.House.buy,
	acceptHover = UIKit.House.buyHover,
	decline = Color3.fromHex("4A5462"),
	declineHover = Color3.fromHex("5D6879"),
	off = Color3.fromHex("8A8F96"),
	title = Enum.Font.GothamBlack,
	body = Enum.Font.GothamBold,
}

-- Design px, on a centred 1280x720 box.
local L = {
	cardW = 460,
	cardH = 430,
	outline = 4,
	rim = 4,
	shadow = 7,
	titleY = 20,
	titleSize = 34,
	wellY = 66,
	wellSize = 150,
	nameY = 224,
	nameSize = 28,
	tagsY = 260,
	tagsSize = 18,
	worthY = 286,
	worthSize = 18,
	buttonsY = 322,
	buttonH = 58,
	acceptW = 200,
	declineW = 160,
	buttonGap = 14,
	statusY = 392,
	statusSize = 16,
}

local CARD_SCALE = 1.1
local POP_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOVER = TweenInfo.new(0.12)
local DIM_ALPHA = 0.55

local PROMPT_NAME = "GiftPrompt"

local remote: RemoteEvent = nil
local card: any = nil -- the open card's parts; nil when none is up

-- ── The prompt ───────────────────────────────────────────────────────

local prompts: { [Player]: ProximityPrompt } = {}

local function refreshPrompt(other: Player)
	local prompt = prompts[other]
	if prompt == nil then
		return
	end
	prompt.Enabled = Players.LocalPlayer:GetAttribute(Gift.ATTR_READY) == true and other:GetAttribute(Gift.ATTR_UNLOCKED) == true
end

local function refreshAll()
	for other in prompts do
		refreshPrompt(other)
	end
end

local function attachPrompt(other: Player, character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root == nil or other.Character ~= character then
		return
	end
	local old = prompts[other]
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Gift nuke"
	prompt.ObjectText = other.DisplayName
	prompt.KeyboardKeyCode = Gift.KEY
	prompt.GamepadKeyCode = Gift.GAMEPAD_KEY
	prompt.HoldDuration = Gift.HOLD_SECONDS
	prompt.MaxActivationDistance = Gift.OFFER_RANGE
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Triggered:Connect(function()
		remote:FireServer("offer", other)
	end)
	prompt.Parent = root
	prompts[other] = prompt
	refreshPrompt(other)
end

local function watchPlayer(other: Player)
	if other == Players.LocalPlayer then
		return
	end
	other.CharacterAdded:Connect(function(character)
		attachPrompt(other, character)
	end)
	if other.Character then
		task.spawn(attachPrompt, other, other.Character)
	end
	other:GetAttributeChangedSignal(Gift.ATTR_UNLOCKED):Connect(function()
		refreshPrompt(other)
	end)
end

-- ── The card ─────────────────────────────────────────────────────────

local function withCommas(n: number): string
	if math.abs(n) >= 1e6 then
		return "$" .. Mastery.short(n) -- "$360M", not "$360,000,000"
	end
	local digits = tostring(math.floor(n))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. grouped:gsub("^,", "")
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
		text = props.text,
		font = props.font or STYLE.title,
		textSize = props.textSize,
		color = props.color or WHITE,
		xAlign = Enum.TextXAlignment.Center,
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

local function shake(group: GuiObject)
	local home = group.Position
	for _, dx in { -10, 9, -6, 4, 0 } do
		group.Position = home + UDim2.fromOffset(dx, 0)
		task.wait(0.035)
	end
	group.Position = home
end

local function close()
	local c = card
	if c == nil or c.closing then
		return
	end
	c.closing = true
	for _, connection in c.connections do
		connection:Disconnect()
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

--- "LEGENDARY  ·  7.5★  ·  Fused  ·  120 kg"
local function tagsFor(item: any): string
	local parts = { string.upper(tostring(item.rarity)) }
	if type(item.stars) == "number" then
		table.insert(parts, `{item.stars}\u{2605}`)
	end
	if type(item.modifier) == "string" and item.modifier ~= "None" then
		table.insert(parts, item.modifier)
	end
	if type(item.weight) == "number" then
		table.insert(parts, `{math.floor(item.weight + 0.5)} kg`)
	end
	return table.concat(parts, "  \u{00B7}  ")
end

local function worthFor(item: any): string
	local value = if type(item.value) == "number" then withCommas(item.value) else "?"
	if type(item.perSecond) == "number" then
		return `Worth {value}  \u{00B7}  {withCommas(item.perSecond)}/s on a stand`
	end
	if item.identified == false then
		return `Crusted \u{2014} wash it to find out (sells for {value})`
	end
	return `Worth {value}`
end

local function open(message: any)
	local player = Players.LocalPlayer
	local item = message.item
	local rarity = Rarity.DEFS[item.rarity]

	local gui = Instance.new("ScreenGui")
	gui.Name = "GiftHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 97
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
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

	local pad = 20
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
		size = UDim2.new(1, -20, 0, 40),
		position = UDim2.fromOffset(10, L.titleY),
		text = `GIFT FROM {string.upper(tostring(message.from))}`,
		textSize = L.titleSize,
		stroke = 3.5,
		zIndex = 12,
	})

	-- The nuke itself, in a rarity-edged well.
	local well = blob(face, "Well", { (L.cardW - L.wellSize) / 2, L.wellY, L.wellSize, L.wellSize }, STYLE.well, 8, L.outline)
	local wellEdge = well:FindFirstChildOfClass("UIStroke")
	if wellEdge and rarity then
		wellEdge.Color = rarity.color
	end
	local viewport = ItemArt.newViewport(well)
	viewport.ZIndex = 9
	if item.identified and type(item.itemId) == "string" then
		ItemModels.request({ item.itemId })
	end
	ItemArt.paint(viewport, item, 1)

	inkLabel(face, {
		name = "ItemName",
		size = UDim2.new(1, -20, 0, 34),
		position = UDim2.fromOffset(10, L.nameY),
		text = tostring(item.name),
		textSize = L.nameSize,
		color = if rarity then rarity.color else WHITE,
		stroke = 3,
		zIndex = 12,
	})
	plainLabel(face, {
		name = "Tags",
		size = UDim2.new(1, -20, 0, 22),
		position = UDim2.fromOffset(10, L.tagsY),
		text = tagsFor(item),
		textSize = L.tagsSize,
		zIndex = 12,
	})
	plainLabel(face, {
		name = "Worth",
		size = UDim2.new(1, -20, 0, 22),
		position = UDim2.fromOffset(10, L.worthY),
		text = worthFor(item),
		textSize = L.worthSize,
		color = STYLE.money,
		zIndex = 12,
	})

	local buttonsLeft = (L.cardW - L.acceptW - L.buttonGap - L.declineW) / 2
	local accept = makeButton(face, "Accept", buttonsLeft, L.buttonsY, L.acceptW, L.buttonH, STYLE.accept, "ACCEPT", 28)
	local decline = makeButton(face, "Decline", buttonsLeft + L.acceptW + L.buttonGap, L.buttonsY, L.declineW, L.buttonH, STYLE.decline, "DECLINE", 24)

	local status = plainLabel(face, {
		name = "Status",
		size = UDim2.new(1, -24, 0, 20),
		position = UDim2.fromOffset(12, L.statusY),
		text = "",
		textSize = L.statusSize,
		zIndex = 12,
	})

	card = {
		gui = gui,
		dim = dim,
		group = group,
		popScale = popScale,
		title = title,
		accept = accept,
		status = status,
		busy = false,
		closing = false,
		failed = false,
		endsAt = os.clock() + (tonumber(message.seconds) or Gift.OFFER_SECONDS),
		connections = {} :: { RBXScriptConnection },
	}
	local c = card

	local function hover(button: TextButton, normal: Color3, lit: Color3)
		button.MouseEnter:Connect(function()
			if not c.busy then
				TweenService:Create(button, HOVER, { BackgroundColor3 = lit }):Play()
			end
		end)
		button.MouseLeave:Connect(function()
			if not c.busy then
				TweenService:Create(button, HOVER, { BackgroundColor3 = normal }):Play()
			end
		end)
	end
	hover(accept, STYLE.accept, STYLE.acceptHover)
	hover(decline, STYLE.decline, STYLE.declineHover)

	accept.Activated:Connect(function()
		if c.busy or c.closing then
			return
		end
		c.busy = true
		accept.BackgroundColor3 = STYLE.off
		c.failed = false
		status.Text = ""
		remote:FireServer("accept")
	end)
	local function sayNo()
		if c.closing or (c.busy and not c.failed) then
			return
		end
		remote:FireServer("decline")
		close()
	end
	decline.Activated:Connect(sayNo)
	table.insert(c.connections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
			sayNo()
		end
	end))

	-- The lapse countdown. The server lapses it too; this is only the readout.
	table.insert(c.connections, RunService.Heartbeat:Connect(function()
		if c.busy and not c.failed then
			return
		end
		local left = math.ceil(c.endsAt - os.clock())
		if left <= 0 then
			close()
		elseif not c.failed then
			status.Text = `Offer ends in {left}s`
			status.TextColor3 = STYLE.sub
		end
	end))

	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = DIM_ALPHA }):Play()
	TweenService:Create(group, TweenInfo.new(0.2), { GroupTransparency = 0 }):Play()
	TweenService:Create(popScale, POP_IN, { Scale = CARD_SCALE }):Play()
end

local function onResult(message: any)
	local c = card
	if c == nil or c.closing then
		return
	end
	if message.ok then
		c.title.Text = "GIFT RECEIVED!"
		c.title.TextColor3 = STYLE.money
		c.status.Text = "It's in your bag"
		c.status.TextColor3 = STYLE.sub
		task.delay(1.2, close)
		return
	end
	local reason = if type(message.message) == "string" then message.message else "couldn't take that gift"
	c.status.Text = reason:sub(1, 1):upper() .. reason:sub(2)
	c.status.TextColor3 = STYLE.bad
	c.failed = true
	task.spawn(shake, c.group)
	if message.keep then
		c.busy = false
		c.accept.BackgroundColor3 = STYLE.accept
	else
		task.delay(1.6, close)
	end
end

function GiftController.start()
	remote = Net.get("Gift")
	remote.OnClientEvent:Connect(function(message: any)
		if type(message) ~= "table" then
			return
		end
		if message.kind == "offer" and type(message.item) == "table" then
			-- A re-offer from the same giver replaces the card outright, no pop-out.
			local old = card
			if old then
				for _, connection in old.connections do
					connection:Disconnect()
				end
				old.closing = true
				old.gui:Destroy()
				card = nil
			end
			open(message)
		elseif message.kind == "result" then
			onResult(message)
		elseif message.kind == "closed" then
			close()
		end
	end)

	local me = Players.LocalPlayer
	me:GetAttributeChangedSignal(Gift.ATTR_READY):Connect(refreshAll)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(other)
		local prompt = prompts[other]
		prompts[other] = nil
		if prompt then
			prompt:Destroy()
		end
	end)
end

return GiftController
