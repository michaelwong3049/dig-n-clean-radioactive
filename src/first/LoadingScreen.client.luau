--[[
	The loading screen. Lives in ReplicatedFirst so it runs before anything else
	replicates, and replaces Roblox's default one.

	The world isn't there yet when this shows, so the backdrop can't be a live blur of
	Base Camp: it's a screenshot of Base Camp blurred offline and uploaded as an image
	(source: art/ui/loading-basecamp.jpg). The title sits bottom-left over a left-dark
	shade, the bar under it, a rotating tip under that, and the % bottom-right.

	Any click / tap / key / gamepad button skips it.
]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local BACKDROP = "rbxassetid://85823430460635"
local FONT = Enum.Font.GothamBlack
local INK = Color3.fromHex("1A1A1A")
local YELLOW = Color3.fromHex("FFD21F")

local MIN_SHOW = 2.5 -- seconds, so a fast load doesn't just flash it
local MAX_SHOW = 25 -- never trap anyone behind it if something never finishes
local FADE = 0.6

local TIPS = {
	"Tip: better detectors find rarer nukes",
	"Tip: wash a nuke at your base before you sell it",
	"Tip: watch your rads and stay out of the red",
	"Tip: put nukes on your stands to earn cash every second",
	"Tip: upgrade your aura to survive deeper stages",
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function stroke(parent: Instance, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = thickness
	s.Parent = parent
	return s
end

local function label(name: string, text: string, color: Color3, pos: UDim2, size: UDim2, anchor: Vector2, align: Enum.TextXAlignment): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.TextXAlignment = align
	l.AnchorPoint = anchor
	l.Position = pos
	l.Size = size
	l.ZIndex = 5
	l.Parent = gui
	return l
end

local root = Instance.new("Frame")
root.Name = "Backing"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(11, 13, 18)
root.BorderSizePixel = 0
root.Parent = gui

local backdrop = Instance.new("ImageLabel")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundTransparency = 1
backdrop.Image = BACKDROP
backdrop.ImageTransparency = 0.3 -- see-through over the dark backing
backdrop.ScaleType = Enum.ScaleType.Crop
backdrop.ZIndex = 2
backdrop.Parent = gui

-- Dark on the left where the text sits, clear by 60% across.
local shade = Instance.new("Frame")
shade.Name = "Shade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BorderSizePixel = 0
shade.ZIndex = 3
shade.Parent = gui
local shadeGradient = Instance.new("UIGradient")
shadeGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(0.6, 0.85),
	NumberSequenceKeypoint.new(1, 0.85),
})
shadeGradient.Parent = shade

local LEFT = 0.06
local titleTop = label("TitleTop", "DIG A", Color3.new(1, 1, 1), UDim2.fromScale(LEFT, 0.5), UDim2.fromScale(0.5, 0.12), Vector2.zero, Enum.TextXAlignment.Left)
local titleBottom = label("TitleBottom", "NUKE!", YELLOW, UDim2.fromScale(LEFT, 0.595), UDim2.fromScale(0.5, 0.12), Vector2.zero, Enum.TextXAlignment.Left)
stroke(titleTop, 4)
stroke(titleBottom, 4)

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.Position = UDim2.fromScale(LEFT, 0.78)
bar.Size = UDim2.new(0.4, 0, 0, 18)
bar.BackgroundColor3 = Color3.new(0, 0, 0)
bar.BackgroundTransparency = 0.45
bar.BorderSizePixel = 0
bar.ZIndex = 5
bar.Parent = gui
local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = bar
stroke(bar, 3)
local barMax = Instance.new("UISizeConstraint")
barMax.MaxSize = Vector2.new(560, math.huge)
barMax.Parent = bar

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = YELLOW
fill.BorderSizePixel = 0
fill.ZIndex = 6
fill.Parent = bar
barCorner:Clone().Parent = fill

local tip = label("Tip", TIPS[math.random(#TIPS)], Color3.new(1, 1, 1), UDim2.fromScale(LEFT, 0.83), UDim2.fromScale(0.6, 0.04), Vector2.zero, Enum.TextXAlignment.Left)
local tipMax = Instance.new("UITextSizeConstraint")
tipMax.MaxTextSize = 22
tipMax.Parent = tip
stroke(tip, 2)

local pct = label("Percent", "0%", Color3.new(1, 1, 1), UDim2.fromScale(0.95, 0.93), UDim2.fromScale(0.2, 0.05), Vector2.new(1, 1), Enum.TextXAlignment.Right)
local pctMax = Instance.new("UITextSizeConstraint")
pctMax.MaxTextSize = 30
pctMax.Parent = pct
stroke(pct, 2.5)

local function skipText(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "TAP ANYWHERE TO SKIP"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "PRESS ANY BUTTON TO SKIP"
	end
	return "CLICK ANYWHERE TO SKIP"
end
local skip = label("Skip", skipText(), Color3.new(1, 1, 1), UDim2.fromScale(0.95, 0.85), UDim2.fromScale(0.3, 0.035), Vector2.new(1, 1), Enum.TextXAlignment.Right)
local skipMax = Instance.new("UITextSizeConstraint")
skipMax.MaxTextSize = 20
skipMax.Parent = skip
stroke(skip, 2)

gui.Parent = playerGui
task.spawn(function()
	ContentProvider:PreloadAsync({ backdrop })
end)

-- Progress: creep toward 85% while the game loads, then fill once the game is
-- loaded and the character is in.
local started = os.clock()
local shown = 0
local done = false
local closing = false

local function ready(): boolean
	return game:IsLoaded() and player.Character ~= nil
end

local function close()
	if closing then
		return
	end
	closing = true
	local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		elseif d:IsA("ImageLabel") then
			TweenService:Create(d, info, { ImageTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		end
	end
	task.delay(FADE, function()
		gui:Destroy()
	end)
end

local SKIP_INPUTS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.Touch] = true,
	[Enum.UserInputType.Keyboard] = true,
}
local skipConn = UserInputService.InputBegan:Connect(function(input)
	local isPadButton = input.UserInputType.Name:sub(1, 7) == "Gamepad"
		and input.KeyCode ~= Enum.KeyCode.Thumbstick1
		and input.KeyCode ~= Enum.KeyCode.Thumbstick2
	if SKIP_INPUTS[input.UserInputType] or isPadButton then
		close()
	end
end)

local tipIndex = table.find(TIPS, tip.Text) or 1
task.spawn(function()
	while not closing do
		task.wait(3)
		if closing then
			break
		end
		tipIndex = tipIndex % #TIPS + 1
		tip.Text = TIPS[tipIndex]
	end
end)

local pulse = 0
local stepConn
stepConn = RunService.RenderStepped:Connect(function(dt)
	if closing then
		stepConn:Disconnect()
		skipConn:Disconnect()
		return
	end
	local elapsed = os.clock() - started
	local target
	if ready() then
		target = 1
	else
		-- eases toward 0.85 and never quite gets there; the queue shrinking nudges it on
		local queue = ContentProvider.RequestQueueSize
		target = 0.85 * (1 - math.exp(-elapsed / 4)) * (queue > 0 and 0.97 or 1)
	end
	if elapsed > MAX_SHOW then
		target = 1
	end
	shown = math.max(shown, shown + (target - shown) * math.min(1, dt * 4))
	if target == 1 and shown > 0.995 then
		shown = 1
	end
	fill.Size = UDim2.fromScale(shown, 1)
	pct.Text = math.floor(shown * 100) .. "%"

	pulse += dt
	skip.TextTransparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(pulse * 3))

	if shown >= 1 and not done then
		done = true
		task.delay(math.max(0, MIN_SHOW - elapsed), close)
	end
end)
