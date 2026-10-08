--[[
	RobuxGiftController.luau — buying a Robux product for someone else (Config/RobuxGifts,
	Services/RobuxGiftService).

	  button(parent, productId)   the purple gift button beside a green R$ BUY. Pressing
	                              it opens the picker for that product.
	  open(productId)             the picker: everyone else in the server (tap one) or
	                              any username typed in the box. The server checks the
	                              name and opens Roblox's purchase window. Its answer
	                              closes the picker or shows the reason in red.
	  clear()                     a plain BUY was pressed. It tells the server to forget
	                              any pending gift, so this purchase goes to the buyer.

	It also shows the two toasts: "Gift sent to X!" for the buyer, and "<name> gifted
	you <item>!" for the recipient, whenever their gift is opened (online now, or on
	their next join).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local RobuxGifts = require(Shared.Config.RobuxGifts)

local Artwork = require(script.Parent.Parent.HudArtwork)
local Studded = require(script.Parent.Parent.Studded)
local UIKit = require(script.Parent.Parent.UIKit)

local RobuxGiftController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)
-- The gift button and SEND: every Robux button's purple (UIKit.House.robux).
local PURPLE = UIKit.House.robux
local PURPLE_HOVER = Color3.fromHex("9257F5")
local STYLE = {
	card = Color3.fromHex("12161D"),
	rim = Color3.fromHex("2C3644"),
	row = Color3.fromHex("232A35"),
	rowHover = Color3.fromHex("2E3746"),
	field = Color3.fromHex("0B0E13"),
	sub = Color3.fromHex("C9D3DE"),
	bad = Color3.fromHex("FF6B6B"),
	good = Color3.fromHex("7CF25A"),
	gold = Color3.fromHex("FFD34D"),
	title = Enum.Font.GothamBlack,
	body = Enum.Font.GothamBold,
}

-- Design px, on a centred 1280x720 box.
local CARD_W = 480
local CARD_H = 560
local ROW_H = 54
local LIST_Y = 128
local LIST_H = 236
local POP_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(0.12)

local remote: RemoteEvent? = nil
local picker: any = nil -- the open picker's parts; nil when none is up
local toastGui: ScreenGui? = nil

-- Fetched on first use: ShopController builds its buttons before this controller starts.
local function net(): RemoteEvent
	if remote == nil then
		remote = Net.get("RobuxGift")
	end
	return remote :: RemoteEvent
end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function border(parent: Instance, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = INK
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function label(parent: Instance, props: any): TextLabel
	return UIKit.label(parent, {
		name = props.name,
		size = props.size,
		position = props.position,
		anchorPoint = props.anchorPoint,
		text = props.text,
		font = props.font or STYLE.title,
		textSize = props.textSize,
		color = props.color or WHITE,
		xAlign = props.xAlign or Enum.TextXAlignment.Center,
		outline = props.outline,
		strokeTransparency = if props.outline == false then 1 else nil,
		wrapped = props.wrapped,
		zIndex = props.zIndex,
	})
end

local function hover(button: GuiButton, normal: Color3, lit: Color3)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, HOVER, { BackgroundColor3 = lit }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, HOVER, { BackgroundColor3 = normal }):Play()
	end)
end

-- ── The picker ──────────────────────────────────────────────────────────────

local function close()
	local p = picker
	if p == nil then
		return
	end
	picker = nil
	if p.keys then
		p.keys:Disconnect()
	end
	for _, connection in p.roster do
		connection:Disconnect()
	end
	p.gui:Destroy()
end

local function send(recipient: number | string)
	local p = picker
	if p == nil or p.busy then
		return
	end
	if type(recipient) == "string" and #recipient < 3 then
		p.status.TextColor3 = STYLE.bad
		p.status.Text = "Type a username first"
		return
	end
	p.busy = true
	p.status.TextColor3 = STYLE.sub
	p.status.Text = "Checking..."
	net():FireServer("send", p.productId, recipient)
	-- An answer that never comes must not lock the picker.
	local mine = p
	task.delay(10, function()
		if picker == mine and mine.busy then
			mine.busy = false
			mine.status.Text = ""
		end
	end)
end

--- One row per other player: avatar, display name, @username. Rebuilt on join/leave.
local function fillRoster(p: any)
	for _, child in p.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local me = Players.LocalPlayer
	local count = 0
	for _, other in Players:GetPlayers() do
		if other == me then
			continue
		end
		count += 1
		local row = Instance.new("TextButton")
		row.Name = other.Name
		row.AutoButtonColor = false
		row.Text = ""
		row.BackgroundColor3 = STYLE.row
		row.Size = UDim2.new(1, -12, 0, ROW_H)
		row.LayoutOrder = count
		row.ZIndex = 12
		row.Parent = p.list
		round(row, 10)
		border(row, 2)
		hover(row, STYLE.row, STYLE.rowHover)

		local face = Instance.new("ImageLabel")
		face.Name = "Avatar"
		face.BackgroundColor3 = STYLE.field
		face.Size = UDim2.fromOffset(ROW_H - 12, ROW_H - 12)
		face.Position = UDim2.fromOffset(6, 6)
		face.ZIndex = 13
		face.Parent = row
		round(face, 8)
		task.spawn(function()
			local ok, image = pcall(Players.GetUserThumbnailAsync, Players, other.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			if ok and face.Parent then
				face.Image = image
			end
		end)

		label(row, {
			name = "Name",
			size = UDim2.new(1, -ROW_H - 110, 0, 26),
			position = UDim2.fromOffset(ROW_H + 4, 4),
			text = other.DisplayName,
			textSize = 20,
			xAlign = Enum.TextXAlignment.Left,
			zIndex = 13,
		})
		label(row, {
			name = "User",
			size = UDim2.new(1, -ROW_H - 110, 0, 18),
			position = UDim2.fromOffset(ROW_H + 4, 30),
			text = `@{other.Name}`,
			font = STYLE.body,
			textSize = 14,
			color = STYLE.sub,
			xAlign = Enum.TextXAlignment.Left,
			outline = false,
			zIndex = 13,
		})
		local tag = Instance.new("Frame")
		tag.Name = "Tag"
		tag.BackgroundColor3 = PURPLE
		tag.AnchorPoint = Vector2.new(1, 0.5)
		tag.Position = UDim2.new(1, -8, 0.5, 0)
		tag.Size = UDim2.fromOffset(92, 36)
		tag.ZIndex = 13
		tag.Parent = row
		round(tag, 8)
		border(tag, 2)
		label(tag, { name = "Text", size = UDim2.fromScale(1, 1), text = "GIFT", textSize = 18, zIndex = 14 })

		row.Activated:Connect(function()
			send(other.UserId)
		end)
	end
	p.empty.Visible = count == 0
end

function RobuxGiftController.open(productId: number)
	local gift = RobuxGifts.get(productId)
	if gift == nil then
		return
	end
	close()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "RobuxGiftHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 130 -- over the Shop (110) and the crate popup (96)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.5
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

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = STYLE.card
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromOffset(640, 360)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.ZIndex = 5
	card.Parent = box
	round(card, 16)
	border(card, 4)
	Studded.darkPanel(card, 16)
	local pop = Instance.new("UIScale")
	pop.Scale = 0.6
	pop.Parent = card

	local icon = Instance.new("ImageLabel")
	icon.Name = "Gift"
	icon.BackgroundTransparency = 1
	icon.Image = Artwork.IMAGE.giftBox
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = UDim2.fromOffset(56, 56)
	icon.Position = UDim2.fromOffset(18, 14)
	icon.ZIndex = 12
	icon.Parent = card
	label(card, {
		name = "Title",
		size = UDim2.new(1, -150, 0, 36),
		position = UDim2.fromOffset(86, 14),
		text = "SEND A GIFT",
		textSize = 30,
		xAlign = Enum.TextXAlignment.Left,
		zIndex = 12,
	})
	label(card, {
		name = "Item",
		size = UDim2.new(1, -110, 0, 24),
		position = UDim2.fromOffset(86, 50),
		text = gift.name,
		textSize = 20,
		color = STYLE.gold,
		xAlign = Enum.TextXAlignment.Left,
		zIndex = 12,
	})
	label(card, {
		name = "ListHead",
		size = UDim2.new(1, -36, 0, 22),
		position = UDim2.fromOffset(18, LIST_Y - 30),
		text = "PLAYERS IN THIS SERVER",
		font = STYLE.body,
		textSize = 16,
		color = STYLE.sub,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		zIndex = 12,
	})

	local list = Instance.new("ScrollingFrame")
	list.Name = "Players"
	list.BackgroundColor3 = STYLE.field
	list.BackgroundTransparency = 0.2
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(18, LIST_Y)
	list.Size = UDim2.new(1, -36, 0, LIST_H)
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 11
	list.Parent = card
	round(list, 10)
	border(list, 2)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 6)
	listPad.PaddingBottom = UDim.new(0, 6)
	listPad.Parent = list
	local empty = label(card, {
		name = "Empty",
		size = UDim2.new(1, -60, 0, 60),
		position = UDim2.fromOffset(30, LIST_Y + LIST_H / 2 - 30),
		text = "No one else here. Type a username below!",
		font = STYLE.body,
		textSize = 16,
		color = STYLE.sub,
		outline = false,
		wrapped = true,
		zIndex = 12,
	})

	local typeY = LIST_Y + LIST_H + 16
	label(card, {
		name = "TypeHead",
		size = UDim2.new(1, -36, 0, 22),
		position = UDim2.fromOffset(18, typeY),
		text = "OR SEND TO ANY USERNAME",
		font = STYLE.body,
		textSize = 16,
		color = STYLE.sub,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		zIndex = 12,
	})
	local field = Instance.new("TextBox")
	field.Name = "Username"
	field.BackgroundColor3 = STYLE.field
	field.ClearTextOnFocus = false
	field.Font = STYLE.body
	field.PlaceholderText = "Username"
	field.PlaceholderColor3 = Color3.fromHex("6B7480")
	field.Text = ""
	field.TextColor3 = WHITE
	field.TextSize = 20
	field.TextXAlignment = Enum.TextXAlignment.Left
	field.Position = UDim2.fromOffset(18, typeY + 28)
	field.Size = UDim2.new(1, -36 - 140, 0, 52)
	field.ZIndex = 12
	field.Parent = card
	round(field, 10)
	border(field, 3)
	local fieldPad = Instance.new("UIPadding")
	fieldPad.PaddingLeft = UDim.new(0, 12)
	fieldPad.Parent = field
	local limit = RobuxGifts.NAME_MAX + 1 -- room for a leading "@"
	field:GetPropertyChangedSignal("Text"):Connect(function()
		if #field.Text > limit then
			field.Text = string.sub(field.Text, 1, limit)
		end
	end)

	local sendButton = Instance.new("TextButton")
	sendButton.Name = "Send"
	sendButton.AutoButtonColor = false
	sendButton.Text = ""
	sendButton.BackgroundColor3 = PURPLE
	sendButton.AnchorPoint = Vector2.new(1, 0)
	sendButton.Position = UDim2.new(1, -18, 0, typeY + 28)
	sendButton.Size = UDim2.fromOffset(128, 52)
	sendButton.ZIndex = 12
	sendButton.Parent = card
	round(sendButton, 10)
	border(sendButton, 3)
	Studded.button(sendButton, 10)
	label(sendButton, { name = "Text", size = UDim2.fromScale(1, 1), text = "SEND", textSize = 24, zIndex = 13 })
	hover(sendButton, PURPLE, PURPLE_HOVER)

	local status = label(card, {
		name = "Status",
		size = UDim2.new(1, -36, 0, 40),
		position = UDim2.fromOffset(18, typeY + 88),
		text = "",
		font = STYLE.body,
		textSize = 16,
		color = STYLE.sub,
		outline = false,
		wrapped = true,
		zIndex = 12,
	})

	local closeButton = UIKit.closeButton(card, {
		position = UDim2.fromOffset(CARD_W - 34 - 12, 12),
		size = 34,
		zIndex = 21,
	})

	picker = {
		gui = gui,
		productId = productId,
		list = list,
		empty = empty,
		status = status,
		busy = false,
		roster = {},
		keys = nil :: RBXScriptConnection?,
	}
	local p = picker
	fillRoster(p)
	table.insert(p.roster, Players.PlayerAdded:Connect(function()
		fillRoster(p)
	end))
	table.insert(p.roster, Players.PlayerRemoving:Connect(function()
		task.defer(fillRoster, p)
	end))

	local function typed()
		send(field.Text)
	end
	sendButton.Activated:Connect(typed)
	field.FocusLost:Connect(function(enter: boolean)
		if enter then
			typed()
		end
	end)
	closeButton.Activated:Connect(close)
	dim.Activated:Connect(close)
	p.keys = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
			close()
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(pop, POP_IN, { Scale = 1 }):Play()
end

-- ── The toasts ──────────────────────────────────────────────────────────────

local function toast(title: string, body: string, color: Color3)
	local player = Players.LocalPlayer
	if toastGui == nil then
		local gui = Instance.new("ScreenGui")
		gui.Name = "RobuxGiftToast"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 131
		gui.Parent = player:WaitForChild("PlayerGui")
		toastGui = gui
	end
	local gui = toastGui :: ScreenGui
	for _, old in gui:GetChildren() do
		old:Destroy()
	end
	local canvas = UIKit.canvas(gui)
	local box = Instance.new("Frame")
	box.Name = "Toast"
	box.BackgroundColor3 = STYLE.card
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, -120)
	box.Size = UDim2.fromOffset(460, 96)
	box.ZIndex = 5
	box.Parent = canvas
	round(box, 14)
	border(box, 4)
	Studded.darkPanel(box, 14)
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = Artwork.IMAGE.giftBox
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = UDim2.fromOffset(70, 70)
	icon.Position = UDim2.fromOffset(14, 13)
	icon.ZIndex = 12
	icon.Parent = box
	label(box, {
		name = "Title",
		size = UDim2.new(1, -110, 0, 34),
		position = UDim2.fromOffset(96, 12),
		text = title,
		textSize = 26,
		color = color,
		xAlign = Enum.TextXAlignment.Left,
		zIndex = 12,
	})
	label(box, {
		name = "Body",
		size = UDim2.new(1, -110, 0, 40),
		position = UDim2.fromOffset(96, 46),
		text = body,
		font = STYLE.body,
		textSize = 17,
		color = STYLE.sub,
		xAlign = Enum.TextXAlignment.Left,
		outline = false,
		wrapped = true,
		zIndex = 12,
	})
	local down = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(box, down, { Position = UDim2.new(0.5, 0, 0, 90) }):Play()
	task.delay(5, function()
		if box.Parent then
			local up = TweenService:Create(box, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -120) })
			up:Play()
			up.Completed:Wait()
			box:Destroy()
		end
	end)
end

local function onMessage(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.kind == "result" then
		local p = picker
		if p == nil or message.productId ~= p.productId then
			return
		end
		p.busy = false
		if message.ok then
			-- Roblox's purchase window takes over from here.
			close()
		else
			p.status.TextColor3 = STYLE.bad
			p.status.Text = tostring(message.message or "Couldn't send that gift")
		end
	elseif message.kind == "sent" then
		toast("GIFT SENT!", `{message.item} is on its way to {message.to}.`, STYLE.good)
	elseif message.kind == "received" then
		toast("YOU GOT A GIFT!", `{message.from} gifted you {message.item}!`, STYLE.gold)
	end
end

-- ── The button ──────────────────────────────────────────────────────────────

--- The purple gift button for `productId`. Size and position are the caller's.
--- Returns nil for a product that can't be gifted.
function RobuxGiftController.button(parent: Instance, productId: number): TextButton?
	if RobuxGifts.get(productId) == nil then
		return nil
	end
	local button = Instance.new("TextButton")
	button.Name = "Gift"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = PURPLE
	button.ZIndex = 15
	button.Parent = parent
	round(button, 12)
	local shrink = Instance.new("UIScale")
	shrink.Scale = 0.9
	shrink.Parent = button
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = Color3.new(0, 0, 0)
	edge.Thickness = 3
	edge.LineJoinMode = Enum.LineJoinMode.Round
	edge.Parent = button
	Studded.button(button, 12)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = Artwork.IMAGE.giftBox
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.78, 0.78)
	icon.ZIndex = 17
	icon.Parent = button
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = icon
	hover(button, PURPLE, PURPLE_HOVER)
	button.Activated:Connect(function()
		RobuxGiftController.open(productId)
	end)
	return button
end

--- A plain BUY was pressed: drop any pending gift so this purchase stays yours.
function RobuxGiftController.clear()
	net():FireServer("clear")
end

function RobuxGiftController.start()
	net().OnClientEvent:Connect(onMessage)
end

return RobuxGiftController
