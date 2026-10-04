--!strict
--[[
	HoseSignController.luau — the face of every base's hose upgrade sign.

	THE HOSE SHOPS ARE GONE (2026-10-04, on request): every hose is bought off this sign,
	a studded navy board beside your own wash bay's reel (build/Plots.setHoseSign). It is
	the treadmill sign's twin (TreadmillSignController): "Upgrade Hose", the next hose's
	name in green, then a red cash button and a purple Robux one.

	DRAWN HERE, NOT ON THE SERVER, because a world gui's buttons only take input when the
	gui is under PlayerGui. Each board gets a SurfaceGui in our PlayerGui, adorned to its
	front face, rebuilt when streaming swaps the board out.

	WHAT IT SAYS comes off the sign model's attributes, which the server writes for the
	base's owner: `Tier` (the hose on the mast), `Next` (the rung above their best, 0 when
	maxed) and `LockedCamp` (the camp they still have to reach for it, "" when buyable).
	A locked rung shows "Reach <camp>" where the buttons go.

	ONLY YOUR OWN SIGN SELLS. Someone else's shows its owner's hose, with no buttons. The
	red button asks the server (Net.HoseBuy), which re-derives the rung, the camp and the
	distance and answers on the hotbar notice; the purple one prompts that rung's
	Developer Product (Config/GearProducts).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Gear = require(Shared.Config.Gear)
local GearProducts = require(Shared.Config.GearProducts)
local Camps = require(Shared.Config.Camps)
local Mastery = require(Shared.Mastery) -- Mastery.short: "$950K", "$2.5B"
local RobuxButton = require(script.Parent.Parent.RobuxButton)

local HoseSignController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromHex("6CF24A")
local ORANGE = Color3.fromHex("FFB13B")
local RED = Color3.fromHex("E5281F")
local RED_HOVER = Color3.fromHex("FF4A3D")

-- Board px, as the treadmill sign: laid out at W x H and stretched over the board.
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
}
local DRAW_DISTANCE = 120
local PRESS = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local buyRemote: RemoteEvent? = nil
local myPlot: number? = nil

type Sign = {
	gui: SurfaceGui,
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

	local price = label(button, "Price", { 12, 10, L.cashW - 24, L.buttonH - 20 }, 46, WHITE, 3)
	return button, price
end

local function hoseName(tier: number): string
	return Gear.tier("Cleaner", math.clamp(tier, 1, Gear.maxTier("Cleaner"))).name
end

local function build(board: BasePart, sign: Instance, plot: number?): Sign?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local L = LAYOUT

	local gui = Instance.new("SurfaceGui")
	gui.Name = "HoseSign"
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
	local level = label(root, "Level", { 12, L.levelY, W - 24, L.levelH }, 34, GREEN, 3.5)
	local cash, cashPrice = cashButton(root)
	local nextTier = 0
	local robux = RobuxButton.product(root, function()
		return if nextTier > 0 then GearProducts.idFor("Cleaner", nextTier) or 0 else 0
	end)
	robux.button.Position = UDim2.fromOffset(L.robuxX, L.buttonY)
	robux.button.Size = UDim2.fromOffset(L.robuxW, L.buttonH)
	-- MAX HOSE, or "Reach <camp>" for a rung whose camp is still ahead of you.
	local banner = label(root, "Banner", { 12, L.buttonY, W - 24, L.buttonH }, 50, GREEN, 4)

	local function paint()
		local tier = tonumber(sign:GetAttribute("Tier")) or 1
		nextTier = tonumber(sign:GetAttribute("Next")) or 0
		local lockedKey = sign:GetAttribute("LockedCamp")
		local locked = type(lockedKey) == "string" and lockedKey ~= ""
		local mine = plot ~= nil and plot == myPlot and sign:GetAttribute("Owned") == true
		local maxed = nextTier <= 0

		if maxed or not mine then
			title.Text = "Hose"
			level.Text = hoseName(tier)
		else
			title.Text = "Upgrade Hose"
			level.Text = hoseName(nextTier)
		end

		local offer = mine and not maxed and not locked
		cash.Visible = offer
		robux.button.Visible = offer
		if offer then
			cashPrice.Text = "$" .. Mastery.short(Gear.tier("Cleaner", nextTier).price)
		end
		robux.refresh()

		if mine and maxed then
			banner.Visible = true
			banner.TextColor3 = GREEN
			banner.Text = "MAX HOSE"
		elseif mine and locked then
			local camp = Camps.get(lockedKey :: string)
			banner.Visible = true
			banner.TextColor3 = ORANGE
			banner.Text = `Reach {if camp then camp.name else lockedKey}`
		else
			banner.Visible = false
		end
		-- Not yours: no offer, so the hose name moves down into the empty button row.
		if not mine then
			level.Position = UDim2.fromOffset(12, L.buttonY + (L.buttonH - L.levelH) / 2 - 20)
		else
			level.Position = UDim2.fromOffset(12, L.levelY)
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

	for _, name in { "Tier", "Next", "LockedCamp", "Owned" } do
		sign:GetAttributeChangedSignal(name):Connect(paint)
	end
	paint()
	return { gui = gui, plot = plot, paint = paint }
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
	if signModel == nil or signModel.Name ~= "HoseSign" or signs[inst] then
		return
	end
	local sign = build(inst, signModel, plotIndexOf(row, inst))
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

--- Our plot from RespawnLocation, as TreadmillSignController reads it.
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

function HoseSignController.start()
	buyRemote = Net.get("HoseBuy")
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

return HoseSignController
