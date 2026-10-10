--!strict
--[[
	NukeRescueController.luau — the "NUKE LOST!" card that pops up when a nuke you were
	pulling blows up (DigService.offerRescues, Net.NukeLost), with a purple GET IT BACK
	button for Tuning.NUKE_RESCUE_PRODUCT_ID.

	Not modal: you have just been knocked flat in a field, possibly standing in the
	crater, so nothing here dims the screen or holds the pointer. A small see-through
	black card naming only the READING (rarity, modifier) -- the nuke is still a crusted
	find -- and a bar under it runs down the offer's seconds. Buying it, closing it or the bar running out
	takes it away; ProductService grants the nuke and the server's Notice confirms it.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Tuning = require(Shared.Config.Tuning)
local Rarity = require(Shared.Config.Rarity)

local RobuxButton = require(script.Parent.Parent.RobuxButton)
local UIKit = require(script.Parent.Parent.UIKit)

local NukeRescueController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromHex("FF4D4D")

-- Design px, on the centred 1280x720 canvas.
local L = {
	cardW = 270,
	cardH = 142,
	y = 132, -- the card's top edge, under the rare-drop band
	backdrop = 0.35, -- see-through black, like the Shop panel's
	titleY = 8,
	titleSize = 26,
	lineY = 38,
	lineSize = 15,
	buttonW = 170,
	buttonH = 48,
	buttonY = 62,
	barY = 122,
	barH = 7,
	closeSize = 24,
}

local POP_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local current: any = nil -- the open card; nil when none is up

local function close()
	local c = current
	if c == nil or c.closing then
		return
	end
	c.closing = true
	current = nil
	c.tick:Disconnect()
	TweenService:Create(c.group, POP_OUT, { GroupTransparency = 1 }):Play()
	TweenService:Create(c.popScale, POP_OUT, { Scale = 0.85 }):Play()
	task.delay(0.25, function()
		c.gui:Destroy()
	end)
end

local function open(offer: any)
	close()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "NukeRescueHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local pad = 4 -- room in the group for the button's press bounce
	local group = Instance.new("CanvasGroup")
	group.Name = "Card"
	group.AnchorPoint = Vector2.new(0.5, 0)
	group.Position = UDim2.new(0.5, 0, 0, L.y - pad)
	group.Size = UDim2.fromOffset(L.cardW + pad * 2, L.cardH + pad * 2)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Parent = canvas
	local popScale = Instance.new("UIScale")
	popScale.Scale = 0.5
	popScale.Parent = group

	local face = UIKit.panel(group, {
		name = "Face",
		position = UDim2.fromOffset(pad, pad),
		size = UDim2.fromOffset(L.cardW, L.cardH),
		color = Color3.new(0, 0, 0),
		transparency = L.backdrop,
		cornerRadius = UDim.new(0, 12),
		zIndex = 2,
	})

	UIKit.label(face, {
		name = "Title",
		size = UDim2.new(1, -24, 0, 40),
		position = UDim2.fromOffset(12, L.titleY),
		text = "NUKE LOST!",
		font = Enum.Font.GothamBlack,
		textSize = L.titleSize,
		color = RED,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 10,
	})

	local def = Rarity.DEFS[offer.rarity]
	local tint = if def then def.color:Lerp(WHITE, 0.25) else WHITE
	local what = if offer.modifier and offer.modifier ~= "None" then `{offer.modifier} {offer.rarity}` else offer.rarity
	UIKit.label(face, {
		name = "Line",
		size = UDim2.new(1, -24, 0, 26),
		position = UDim2.fromOffset(12, L.lineY),
		text = `Your {what} nuke blew up`,
		font = Enum.Font.GothamBlack,
		textSize = L.lineSize,
		color = tint,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 10,
	})
	local buy = RobuxButton.product(face, function()
		return Tuning.NUKE_RESCUE_PRODUCT_ID
	end, "GET IT BACK")
	buy.button.AnchorPoint = Vector2.new(0.5, 0)
	buy.button.Position = UDim2.new(0.5, 0, 0, L.buttonY)
	buy.button.Size = UDim2.fromOffset(L.buttonW, L.buttonH)
	buy.button.ZIndex = 10

	-- The offer's seconds, running down.
	local track = UIKit.panel(face, {
		name = "Timer",
		position = UDim2.fromOffset(18, L.barY),
		size = UDim2.new(1, -36, 0, L.barH),
		color = INK,
		transparency = 0,
		cornerRadius = UDim.new(1, 0),
		zIndex = 10,
	})
	local fill = UIKit.panel(track, {
		name = "Fill",
		size = UDim2.fromScale(1, 1),
		color = RED,
		transparency = 0,
		cornerRadius = UDim.new(1, 0),
		zIndex = 11,
	})

	local closeButton = UIKit.closeButton(face, {
		position = UDim2.fromOffset(L.cardW - L.closeSize - 6, 6),
		size = L.closeSize,
		zIndex = 12,
	})
	closeButton.Activated:Connect(close)

	local expiresAt: number = offer.expiresAt
	local span = math.max(expiresAt - Workspace:GetServerTimeNow(), 0.1)
	local c = {
		gui = gui,
		group = group,
		popScale = popScale,
		closing = false,
		tick = nil :: any,
	}
	c.tick = RunService.Heartbeat:Connect(function()
		local left = expiresAt - Workspace:GetServerTimeNow()
		-- Keep the card while Roblox's purchase window is up, however long it takes.
		if left <= 0 and not RobuxButton.prompting() then
			close()
			return
		end
		fill.Size = UDim2.fromScale(math.clamp(left / span, 0, 1), 1)
	end)
	current = c

	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(group, TweenInfo.new(0.2), { GroupTransparency = 0 }):Play()
	TweenService:Create(popScale, POP_IN, { Scale = 1 }):Play()
end

function NukeRescueController.start()
	Net.get("NukeLost").OnClientEvent:Connect(function(offer: any)
		if
			Tuning.NUKE_RESCUE_PRODUCT_ID == 0
			or type(offer) ~= "table"
			or type(offer.rarity) ~= "string"
			or type(offer.expiresAt) ~= "number"
		then
			return
		end
		open(offer)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
		if userId == Players.LocalPlayer.UserId and productId == Tuning.NUKE_RESCUE_PRODUCT_ID and purchased then
			close()
		end
	end)
end

return NukeRescueController
