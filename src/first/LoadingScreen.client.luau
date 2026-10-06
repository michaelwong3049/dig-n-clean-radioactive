--[[
	The loading screen. Lives in ReplicatedFirst so it runs before anything else
	replicates, and replaces Roblox's default one.

	The world isn't there yet when this shows, so the backdrop can't be a live blur of
	Base Camp: it's a screenshot of Base Camp blurred offline and uploaded as an image
	(source: art/ui/loading-basecamp.jpg). The title sits bottom-left over a left-dark
	shade, the bar under it, a rotating tip under that, and the % bottom-right.

	Any click / tap / key / gamepad button skips it. On first join it also asks
	"Mobile or PC?" and sets graphics to suit (see the device card below).
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

-- ── "Mobile or PC?" ──────────────────────────────────────────────────────────────
-- Asked once, on first join (the `device` pref is "unset"), on a studded card in the
-- middle. The pick sets graphics + fast mode to suit; Settings > Graphics changes them
-- later. Prefs and Studded live in StarterPlayerScripts.Client, so they're required
-- from there once it has replicated.
local DEVICES = {
	{
		id = "mobile",
		label = "MOBILE",
		sub = "Low graphics, fast mode on",
		colors = ColorSequence.new(Color3.fromHex("D9F51C"), Color3.fromHex("33D23F")),
		prefs = { graphics = "low", fastMode = true },
	},
	{
		id = "pc",
		label = "PC",
		sub = "Medium graphics",
		colors = ColorSequence.new(Color3.fromHex("C77BFF"), Color3.fromHex("8C3FE6")),
		prefs = { graphics = "med", fastMode = false },
	},
}

local closing = false
local prefsKnown = false -- the saved prefs have landed, so we know whether to ask
local asking = false -- the card is up and waiting for a pick
local canSkip = false

local function guessDevice(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled then
		return "mobile"
	end
	return "pc"
end

local function showCard(Prefs: any, Studded: any)
	asking = true
	local guess = guessDevice()

	local panel = Instance.new("Frame")
	panel.Name = "DeviceCard"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.45)
	panel.Size = UDim2.fromOffset(520, 310)
	panel.BackgroundColor3 = Color3.fromHex("1B1F23")
	panel.ZIndex = 20
	panel.Parent = gui
	Studded.edge(panel, 18, 4)
	Studded.tile(panel, Studded.STUDS, 34, 0.82, 18).ZIndex = 20

	-- shrink to fit a phone
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local view = gui.AbsoluteSize
		scale.Scale = math.min(1, (view.X - 32) / 520, (view.Y - 32) / 310)
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local heading = Studded.text(panel, "Heading", 30, 3)
	heading.Text = "ARE YOU ON MOBILE OR PC?"
	heading.Position = UDim2.fromOffset(0, 26)
	heading.Size = UDim2.new(1, 0, 0, 36)
	heading.ZIndex = 21

	local blurb = Studded.text(panel, "Blurb", 16, 2)
	blurb.Text = "We'll set your graphics to match. Change it any time in Settings."
	blurb.TextColor3 = Color3.fromHex("9AA3AD")
	blurb.Position = UDim2.fromOffset(30, 66)
	blurb.Size = UDim2.new(1, -60, 0, 40)
	blurb.TextWrapped = true
	blurb.ZIndex = 21

	local grow = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for i, device in DEVICES do
		local button = Instance.new("TextButton")
		button.Name = device.label
		button.Text = ""
		button.AutoButtonColor = false
		button.Position = UDim2.fromOffset(if i == 1 then 30 else 270, 144)
		button.Size = UDim2.fromOffset(220, 124)
		button.ZIndex = 22
		button.Parent = panel
		Studded.fill(button, device.colors)
		Studded.edge(button, 14, 4)

		local name = Studded.text(button, "Label", 40, 3.5)
		name.Text = device.label
		name.Position = UDim2.fromOffset(0, 24)
		name.Size = UDim2.new(1, 0, 0, 44)
		name.ZIndex = 23

		local sub = Studded.text(button, "Sub", 15, 2)
		sub.Text = device.sub
		sub.Position = UDim2.fromOffset(0, 76)
		sub.Size = UDim2.new(1, 0, 0, 20)
		sub.ZIndex = 23

		if device.id == guess then
			local tag = Instance.new("Frame")
			tag.Name = "YourDevice"
			tag.AnchorPoint = Vector2.new(0.5, 0.5)
			tag.Position = UDim2.fromScale(0.5, 0)
			tag.Size = UDim2.fromOffset(120, 24)
			tag.BackgroundColor3 = YELLOW
			tag.ZIndex = 24
			tag.Parent = button
			Studded.edge(tag, 12, 2.5)
			local tagText = Instance.new("TextLabel")
			tagText.BackgroundTransparency = 1
			tagText.Size = UDim2.fromScale(1, 1)
			tagText.Font = FONT
			tagText.TextSize = 13
			tagText.TextColor3 = INK
			tagText.Text = "YOUR DEVICE"
			tagText.ZIndex = 25
			tagText.Parent = tag
		end

		local buttonScale = Instance.new("UIScale")
		buttonScale.Parent = button
		button.MouseEnter:Connect(function()
			TweenService:Create(buttonScale, grow, { Scale = 1.05 }):Play()
		end)
		button.MouseLeave:Connect(function()
			TweenService:Create(buttonScale, grow, { Scale = 1 }):Play()
		end)
		button.Activated:Connect(function()
			if not asking then
				return
			end
			asking = false
			local changes = table.clone(device.prefs) :: { [string]: any }
			changes.device = device.id
			Prefs.setMany(changes)
			panel:Destroy()
			canSkip = true
		end)
	end
end

task.spawn(function()
	local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
	local Prefs = require(client:WaitForChild("Prefs")) :: any
	local Studded = require(client:WaitForChild("Studded")) :: any
	Prefs.onLoaded(function()
		if closing then
			return
		end
		prefsKnown = true
		if Prefs.get("device") == "unset" then
			showCard(Prefs, Studded)
		else
			canSkip = true
		end
	end)
end)

gui.Parent = playerGui
task.spawn(function()
	ContentProvider:PreloadAsync({ backdrop })
end)

-- Progress: creep toward 85% while the game loads, then fill once the game is
-- loaded and the character is in.
local started = os.clock()
local shown = 0

local function ready(): boolean
	return game:IsLoaded() and player.Character ~= nil
end

local function close()
	if closing then
		return
	end
	closing = true
	asking = false
	local info = TweenInfo.new(FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			TweenService:Create(d, info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
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

-- Clicks only skip once we know there's nothing to ask (or it's been answered), so
-- a first-joiner can't click past the device card before it appears.
local SKIP_INPUTS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.Touch] = true,
	[Enum.UserInputType.Keyboard] = true,
}
local skipConn = UserInputService.InputBegan:Connect(function(input)
	if not canSkip then
		return
	end
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
	skip.Visible = canSkip -- (a UIStroke still draws on fully transparent text)
	skip.TextTransparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(pulse * 3))

	-- Done loading: close, unless the device card is waiting for an answer. If the saved
	-- prefs never arrive, stop waiting at MAX_SHOW (it asks again next join).
	if shown >= 1 and elapsed >= MIN_SHOW and not asking and (prefsKnown or elapsed > MAX_SHOW) then
		close()
	end
end)
