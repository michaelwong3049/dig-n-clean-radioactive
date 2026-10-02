--!strict
--[[
	TreadmillSignController.luau — the face of every treadmill's upgrade sign.

	The sign itself is a studded navy board on a post beside the belt (build/Plots
	ensureUpgradeSign), put up on request in place of the console's E prompt, after a
	reference the user sent: "Upgrade", then "Level 1 > Level 2" in green, then a red
	cash button and a purple Robux one.

	DRAWN HERE, NOT ON THE SERVER, because a world gui's buttons only take input when
	the gui is under PlayerGui (memory: billboard buttons need PlayerGui). So each
	board gets a SurfaceGui in our PlayerGui, adorned to its front face, rebuilt when
	streaming swaps the board out.

	WHAT IT SAYS comes off the treadmill model's `Tier` / `Locked` attributes, which
	Plots.setTreadmillTier writes for the base's OWNER. "Level n" is the belt rung
	(Config/Treadmill.TIERS), not the hidden walk-speed level.

	ONLY YOUR OWN SIGN SELLS. Someone else's still shows its owner's rung, with no
	buttons — the same call FloorSignController makes for a floor prompt that was only
	ever going to be refused. The red button asks the server (Net.TreadmillBuy), which
	re-checks the base and the distance and answers on the hotbar notice; the purple
	one prompts the next rung's Developer Product (Treadmill.PRODUCTS).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Treadmill = require(Shared.Config.Treadmill)
local Mastery = require(Shared.Mastery) -- Mastery.short: "$950K", "$2.5B"
local Artwork = require(script.Parent.Parent.HudArtwork)
local RobuxButton = require(script.Parent.Parent.RobuxButton)

local TreadmillSignController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromHex("6CF24A")
local RED = Color3.fromHex("E5281F")
local RED_HOVER = Color3.fromHex("FF4A3D")

-- Board px: the face is laid out at W x H and stretched over whatever size the board
-- is (build/Plots UPGRADE_SIGN), so the sign can be resized without touching this.
local W, H = 400, 220
local LAYOUT = {
	titleY = 8,
	titleH = 50,
	levelY = 58,
	levelH = 38,
	buttonY = 108,
	buttonH = 92,
	cashX = 16,
	cashW = 236,
	robuxX = 264,
	robuxW = 120,
	icon = 58,
}
local DRAW_DISTANCE = 120
local PRESS = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local buyRemote: RemoteEvent? = nil
local myPlot: number? = nil

type Sign = {
	gui: SurfaceGui,
	treadmill: Instance,
	plot: number?,
	paint: () -> (),
}
local signs: { [BasePart]: Sign } = {}

local function plotIndexOf(row: Instance, inst: Instance): number?
	local node: Instance? = inst
	while node and node.Parent ~= row do
		node = node.Parent
	end
	return if node then tonumber(string.match(node.Name, "^Plot(%d+)$")) else nil
end

local function label(parent: Instance, name: string, rect: { number }, maxSize: number, color: Color3, stroke: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(rect[1], rect[2])
	l.Size = UDim2.fromOffset(rect[3], rect[4])
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.TextColor3 = color
	l.Text = ""
	l.ZIndex = 3
	l.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = l
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = stroke
	s.Parent = l
	return l
end

--- The red cash button: a shoe and the next rung's price.
local function cashButton(parent: Instance): (TextButton, TextLabel)
	local L = LAYOUT
	local button = Instance.new("TextButton")
	button.Name = "Cash"
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = RED
	button.Position = UDim2.fromOffset(L.cashX, L.buttonY)
	button.Size = UDim2.fromOffset(L.cashW, L.buttonH)
	button.ZIndex = 2
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 4
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = button
	local gloss = Instance.new("UIGradient")
	gloss.Rotation = 90
	gloss.Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 200))
	gloss.Parent = button
	local scale = Instance.new("UIScale")
	scale.Name = "Press"
	scale.Parent = button

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = Artwork.IMAGE.speedShoe
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.Size = UDim2.fromOffset(L.icon, L.icon)
	icon.ZIndex = 3
	icon.Parent = button

	local price = label(button, "Price", { L.icon + 16, 10, L.cashW - L.icon - 26, L.buttonH - 20 }, 46, WHITE, 3)
	return button, price
end

local function build(board: BasePart, treadmill: Instance, plot: number?): Sign?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local L = LAYOUT

	local gui = Instance.new("SurfaceGui")
	gui.Name = "TreadmillSign"
	gui.Adornee = board
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = W / board.Size.X
	gui.LightInfluence = 0
	gui.MaxDistance = DRAW_DISTANCE
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(W, H)
	root.Parent = gui

	local title = label(root, "Title", { 0, L.titleY, W, L.titleH }, 46, WHITE, 4)
	local level = label(root, "Level", { 0, L.levelY, W, L.levelH }, 34, GREEN, 3.5)
	local cash, cashPrice = cashButton(root)
	-- Locked or maxed, the purple button's place is empty; while there's a rung to buy
	-- it is that rung's product.
	local nextTier = 2
	local robux = RobuxButton.product(root, function()
		return Treadmill.productFor(nextTier)
	end)
	robux.button.Position = UDim2.fromOffset(L.robuxX, L.buttonY)
	robux.button.Size = UDim2.fromOffset(L.robuxW, L.buttonH)
	local maxed = label(root, "Maxed", { 0, L.buttonY, W, L.buttonH }, 56, GREEN, 4)

	local function paint()
		local tier = math.clamp(math.floor(tonumber(treadmill:GetAttribute("Tier")) or 1), 1, Treadmill.maxTier())
		local locked = treadmill:GetAttribute("Locked") == true
		local mine = plot ~= nil and plot == myPlot
		local price = Treadmill.priceFor(tier)
		nextTier = tier + 1

		if locked then
			title.Text = "Unlock"
			level.Text = "Treadmill"
		elseif price == nil then
			title.Text = "Treadmill"
			level.Text = `Level {tier}`
		else
			title.Text = "Upgrade"
			level.Text = `Level {tier} > Level {tier + 1}`
		end
		maxed.Visible = not locked and price == nil
		maxed.Text = "MAX LEVEL"
		cash.Visible = mine and (locked or price ~= nil)
		cashPrice.Text = if locked then Treadmill.unlockPriceText() else "$" .. Mastery.short(price or 0)
		robux.button.Visible = mine and not locked and price ~= nil
		robux.refresh()
		-- Not yours: no offer, so the rung line moves into the empty button row.
		if not mine and not maxed.Visible then
			level.Position = UDim2.fromOffset(0, L.buttonY + (L.buttonH - L.levelH) / 2 - 20)
		else
			level.Position = UDim2.fromOffset(0, L.levelY)
		end
	end

	local cashScale = cash:FindFirstChild("Press") :: UIScale
	cash.MouseEnter:Connect(function()
		TweenService:Create(cash, HOVER, { BackgroundColor3 = RED_HOVER }):Play()
	end)
	cash.MouseLeave:Connect(function()
		TweenService:Create(cash, HOVER, { BackgroundColor3 = RED }):Play()
	end)
	cash.Activated:Connect(function()
		if plot == nil or plot ~= myPlot or buyRemote == nil then
			return
		end
		cashScale.Scale = 0.9
		TweenService:Create(cashScale, PRESS, { Scale = 1 }):Play()
		buyRemote:FireServer()
	end)

	treadmill:GetAttributeChangedSignal("Tier"):Connect(paint)
	treadmill:GetAttributeChangedSignal("Locked"):Connect(paint)
	paint()
	return { gui = gui, treadmill = treadmill, plot = plot, paint = paint }
end

local function forget(board: BasePart)
	local sign = signs[board]
	if sign then
		signs[board] = nil
		sign.gui:Destroy()
	end
end

local function onDescendant(row: Instance, inst: Instance)
	if inst.Name ~= "Board" or not inst:IsA("BasePart") then
		return
	end
	local signModel = inst.Parent
	local treadmill = signModel and signModel.Parent
	if signModel == nil or signModel.Name ~= "UpgradeSign" or treadmill == nil or signs[inst] then
		return
	end
	local sign = build(inst, treadmill, plotIndexOf(row, inst))
	if sign == nil then
		return
	end
	signs[inst] = sign
	inst.AncestryChanged:Connect(function()
		if not inst:IsDescendantOf(row) then
			forget(inst)
		end
	end)
end

local function onPlot(index: any)
	if type(index) ~= "number" or index == myPlot then
		return
	end
	myPlot = index
	for _, sign in signs do
		sign.paint()
	end
end

--- Our plot from RespawnLocation, as OwnStationPromptController reads it: PlotState is
--- fired once on load and may reach another listener first.
local function fromSpawn()
	local spawn = Players.LocalPlayer.RespawnLocation
	onPlot(spawn and spawn:GetAttribute("PlotIndex"))
end

local function watch(row: Instance)
	for _, inst in row:GetDescendants() do
		onDescendant(row, inst)
	end
	row.DescendantAdded:Connect(function(inst)
		onDescendant(row, inst)
	end)
end

function TreadmillSignController.start()
	buyRemote = Net.get("TreadmillBuy")
	Net.get("PlotState").OnClientEvent:Connect(onPlot)
	fromSpawn()
	Players.LocalPlayer:GetPropertyChangedSignal("RespawnLocation"):Connect(fromSpawn)
	local row = Workspace:FindFirstChild("Plots")
	if row then
		watch(row)
	else
		task.spawn(function()
			watch(Workspace:WaitForChild("Plots"))
		end)
	end
end

return TreadmillSignController
