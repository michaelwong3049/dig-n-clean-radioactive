--[[
	DetectorController.lua — the sweep, rendered.

	The server sends a world-space ANGLE and a STRENGTH, ten times a second, and
	nothing else. It never sends where anything is buried. Everything on screen here
	is derived from those two numbers.

	Hot/cold is carried mostly by SOUND — ping rate and pitch both rise as you close
	in. PLAN §10.7 wants a player able to sweep with their eyes half shut, and the
	ping is the lead instrument. The visuals are the backup, not the other way round.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Net = require(Shared.Net)

local Detector = {}

local COLOR = {
	panel = Color3.fromHex("0C0F0A"),
	stroke = Color3.fromHex("2A3324"),
	text = Color3.fromHex("E4E9DE"),
	dim = Color3.fromHex("7C8874"),
	track = Color3.fromHex("1E241A"),
	green = Color3.fromHex("8FE04A"),
	amber = Color3.fromHex("F59E0B"),
	red = Color3.fromHex("EF4444"),
}

-- Ping pacing. At strength 0 it is a slow lonely tick; at 1 it is a stutter.
local PING_INTERVAL_FAR = 1.10
local PING_INTERVAL_NEAR = 0.09
local PING_PITCH_FAR = 0.75
local PING_PITCH_NEAR = 1.85

local state = {
	inZone = false,
	hasSignal = false,
	strength = 0,
	angle = 0,
	rarityHint = nil :: string?,
	inRange = false,
	blocked = nil :: string?,
	digProgress = 0,
	carrying = 0,
	capacity = 0,
}

local ui = {}
local displayedRotation = 0
local pingClock = 0
local isHolding = false

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ── Build ───────────────────────────────────────────────────────────

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DetectorHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Sweep dial, bottom centre
	local dial = Instance.new("Frame")
	dial.Name = "Dial"
	dial.AnchorPoint = Vector2.new(0.5, 1)
	dial.Position = UDim2.new(0.5, 0, 1, -150)
	dial.Size = UDim2.fromOffset(150, 150)
	dial.BackgroundColor3 = COLOR.panel
	dial.BackgroundTransparency = 0.25
	dial.Parent = gui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = dial

	local ring = Instance.new("UIStroke")
	ring.Color = COLOR.stroke
	ring.Thickness = 2
	ring.Parent = dial
	ui.ring = ring

	-- The needle. A glyph rather than a mesh: this is placeholder art and the
	-- rotation is the only part that has to be right.
	local needle = Instance.new("TextLabel")
	needle.Name = "Needle"
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.Position = UDim2.fromScale(0.5, 0.5)
	needle.Size = UDim2.fromScale(1, 1)
	needle.BackgroundTransparency = 1
	needle.Font = Enum.Font.GothamBold
	needle.Text = "\u{25B2}"
	needle.TextSize = 34
	needle.TextColor3 = COLOR.green
	needle.TextYAlignment = Enum.TextYAlignment.Top
	needle.Parent = dial
	ui.needle = needle

	local centre = Instance.new("TextLabel")
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.Position = UDim2.fromScale(0.5, 0.5)
	centre.Size = UDim2.fromScale(0.8, 0.4)
	centre.BackgroundTransparency = 1
	centre.Font = Enum.Font.GothamBold
	centre.TextSize = 15
	centre.TextColor3 = COLOR.dim
	centre.Text = ""
	centre.Parent = dial
	ui.centre = centre

	-- Signal strength (depth/proximity), directly under the dial
	local strengthTrack = Instance.new("Frame")
	strengthTrack.Name = "Strength"
	strengthTrack.AnchorPoint = Vector2.new(0.5, 1)
	strengthTrack.Position = UDim2.new(0.5, 0, 1, -128)
	strengthTrack.Size = UDim2.fromOffset(190, 8)
	strengthTrack.BackgroundColor3 = COLOR.track
	strengthTrack.BorderSizePixel = 0
	strengthTrack.Parent = gui

	local strengthFill = Instance.new("Frame")
	strengthFill.Name = "Fill"
	strengthFill.Size = UDim2.fromScale(0, 1)
	strengthFill.BackgroundColor3 = COLOR.green
	strengthFill.BorderSizePixel = 0
	strengthFill.Parent = strengthTrack
	ui.strengthFill = strengthFill

	-- Status line
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -104)
	status.Size = UDim2.fromOffset(420, 20)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextSize = 15
	status.TextColor3 = COLOR.dim
	status.Text = ""
	status.Parent = gui
	ui.status = status

	-- Dig button. Big and obvious — it is also the touch control.
	local digButton = Instance.new("TextButton")
	digButton.Name = "DigButton"
	digButton.AnchorPoint = Vector2.new(0.5, 1)
	digButton.Position = UDim2.new(0.5, 0, 1, -46)
	digButton.Size = UDim2.fromOffset(230, 48)
	digButton.BackgroundColor3 = COLOR.panel
	digButton.BackgroundTransparency = 0.15
	digButton.AutoButtonColor = false
	digButton.Font = Enum.Font.GothamBold
	digButton.TextSize = 17
	digButton.TextColor3 = COLOR.dim
	digButton.Text = "HOLD  E  TO PULL"
	digButton.Parent = gui
	ui.digButton = digButton

	local digCorner = Instance.new("UICorner")
	digCorner.CornerRadius = UDim.new(0, 8)
	digCorner.Parent = digButton

	local digStroke = Instance.new("UIStroke")
	digStroke.Color = COLOR.stroke
	digStroke.Thickness = 2
	digStroke.Parent = digButton
	ui.digStroke = digStroke

	-- Dig progress, drawn as a fill sliding under the button label
	local digFill = Instance.new("Frame")
	digFill.Size = UDim2.fromScale(0, 1)
	digFill.BackgroundColor3 = COLOR.green
	digFill.BackgroundTransparency = 0.7
	digFill.BorderSizePixel = 0
	digFill.ZIndex = 0
	digFill.Parent = digButton
	ui.digFill = digFill

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = digFill

	-- Carry counter
	local carry = Instance.new("TextLabel")
	carry.Name = "Carry"
	carry.AnchorPoint = Vector2.new(0.5, 1)
	carry.Position = UDim2.new(0.5, 0, 1, -14)
	carry.Size = UDim2.fromOffset(230, 18)
	carry.BackgroundTransparency = 1
	carry.Font = Enum.Font.Gotham
	carry.TextSize = 13
	carry.TextColor3 = COLOR.dim
	carry.Text = ""
	carry.Parent = gui
	ui.carry = carry

	-- Unearth banner
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.32)
	banner.Size = UDim2.fromOffset(440, 96)
	banner.BackgroundColor3 = COLOR.panel
	banner.BackgroundTransparency = 0.1
	banner.Visible = false
	banner.Parent = gui
	ui.banner = banner

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 10)
	bannerCorner.Parent = banner

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Thickness = 3
	bannerStroke.Color = COLOR.stroke
	bannerStroke.Parent = banner
	ui.bannerStroke = bannerStroke

	local bannerRarity = Instance.new("TextLabel")
	bannerRarity.Position = UDim2.fromOffset(0, 10)
	bannerRarity.Size = UDim2.new(1, 0, 0, 16)
	bannerRarity.BackgroundTransparency = 1
	bannerRarity.Font = Enum.Font.GothamBold
	bannerRarity.TextSize = 13
	bannerRarity.Text = ""
	bannerRarity.Parent = banner
	ui.bannerRarity = bannerRarity

	local bannerName = Instance.new("TextLabel")
	bannerName.Position = UDim2.fromOffset(0, 28)
	bannerName.Size = UDim2.new(1, 0, 0, 28)
	bannerName.BackgroundTransparency = 1
	bannerName.Font = Enum.Font.GothamBold
	bannerName.TextSize = 24
	bannerName.TextColor3 = COLOR.text
	bannerName.Text = ""
	bannerName.Parent = banner
	ui.bannerName = bannerName

	local bannerFlavor = Instance.new("TextLabel")
	bannerFlavor.AnchorPoint = Vector2.new(0.5, 0)
	bannerFlavor.Position = UDim2.new(0.5, 0, 0, 58)
	bannerFlavor.Size = UDim2.new(1, -24, 0, 32)
	bannerFlavor.BackgroundTransparency = 1
	bannerFlavor.Font = Enum.Font.GothamMedium
	bannerFlavor.TextSize = 14
	bannerFlavor.TextColor3 = COLOR.dim
	bannerFlavor.TextWrapped = true
	bannerFlavor.Text = ""
	bannerFlavor.Parent = banner
	ui.bannerFlavor = bannerFlavor

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

local function signalColor(): Color3
	if state.rarityHint then
		local def = Rarity.DEFS[state.rarityHint]
		if def then
			return def.color
		end
	end
	return COLOR.green
end

local function renderFrame(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local colour = signalColor()

	if state.hasSignal then
		-- Server angle is world-space. Subtract the camera's yaw so the needle points
		-- where the player is actually looking.
		local look = camera.CFrame.LookVector
		local cameraYaw = math.atan2(look.Z, look.X)
		local relative = state.angle - cameraYaw
		local target = math.deg(relative)

		-- Shortest-path so it never spins the long way round the dial.
		local diff = (target - displayedRotation + 180) % 360 - 180
		displayedRotation += diff * math.min(1, dt * 12)

		ui.needle.Rotation = displayedRotation
		ui.needle.TextTransparency = 0
		ui.needle.TextColor3 = colour
	else
		ui.needle.TextTransparency = 0.85
	end

	ui.ring.Color = if state.hasSignal then colour else COLOR.stroke
	ui.strengthFill.Size = UDim2.fromScale(state.strength, 1)
	ui.strengthFill.BackgroundColor3 = colour
	ui.digFill.Size = UDim2.fromScale(state.digProgress, 1)
end

local function renderState()
	if not state.inZone then
		ui.centre.Text = ""
		ui.status.Text = "no ground to sweep here"
		ui.status.TextColor3 = COLOR.dim
		ui.digButton.Text = "HOLD  E  TO PULL"
		ui.digStroke.Color = COLOR.stroke
		return
	end

	ui.carry.Text = `bag {state.carrying}/{state.capacity}`

	if not state.hasSignal then
		ui.centre.Text = ""
		ui.status.Text = "sweeping\u{2026}"
		ui.status.TextColor3 = COLOR.dim
		ui.digButton.Text = "HOLD  E  TO PULL"
		ui.digStroke.Color = COLOR.stroke
		ui.digButton.TextColor3 = COLOR.dim
		return
	end

	ui.centre.Text = state.rarityHint or ""
	ui.centre.TextColor3 = signalColor()

	if state.blocked == "weak" then
		-- It still moves. It just will not come free — and the player can see that.
		ui.status.Text = "it shifts, then stops \u{2014} magnet is too weak"
		ui.status.TextColor3 = COLOR.red
		ui.digButton.Text = "MAGNET TOO WEAK"
		ui.digButton.TextColor3 = COLOR.red
		ui.digStroke.Color = COLOR.red
	elseif state.blocked == "full" then
		ui.status.Text = "bag is full"
		ui.status.TextColor3 = COLOR.red
		ui.digButton.Text = "BAG FULL"
		ui.digButton.TextColor3 = COLOR.red
		ui.digStroke.Color = COLOR.red
	elseif state.inRange then
		ui.status.Text = "something is right under you"
		ui.status.TextColor3 = COLOR.green
		ui.digButton.Text = if isHolding then "PULLING\u{2026}" else "HOLD  E  TO PULL"
		ui.digButton.TextColor3 = COLOR.green
		ui.digStroke.Color = COLOR.green
	else
		ui.status.Text = "signal \u{2014} follow the needle"
		ui.status.TextColor3 = COLOR.amber
		ui.digButton.Text = "GET CLOSER"
		ui.digButton.TextColor3 = COLOR.dim
		ui.digStroke.Color = COLOR.stroke
	end
end

-- ── Ping ────────────────────────────────────────────────────────────

local pingSound: Sound? = nil

local function stepPing(dt: number)
	if pingSound == nil or not state.hasSignal then
		return
	end

	pingClock -= dt
	if pingClock > 0 then
		return
	end

	pingClock = lerp(PING_INTERVAL_FAR, PING_INTERVAL_NEAR, state.strength)
	pingSound.PlaybackSpeed = lerp(PING_PITCH_FAR, PING_PITCH_NEAR, state.strength)
	pingSound:Play()
end

-- ── Banner ──────────────────────────────────────────────────────────

local bannerToken = 0

local function showUnearthed(found)
	local def = Rarity.DEFS[found.rarity]
	local colour = if def then def.color else COLOR.text

	local modifier = if found.modifier == "None" then "" else found.modifier .. " "
	ui.bannerRarity.Text = string.upper(modifier .. found.rarity)
	ui.bannerRarity.TextColor3 = colour
	ui.bannerName.Text = found.name
	ui.bannerFlavor.Text = found.flavor
	ui.bannerStroke.Color = colour
	ui.banner.Visible = true

	bannerToken += 1
	local token = bannerToken
	task.delay(3.5, function()
		if token == bannerToken then
			ui.banner.Visible = false
		end
	end)
end

-- ── Input ───────────────────────────────────────────────────────────

local digInput: any = nil

local function setHolding(value: boolean)
	if isHolding == value then
		return
	end
	isHolding = value
	digInput:FireServer(value)
	renderState()
end

-- ── Lifecycle ────────────────────────────────────────────────────────

function Detector.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	pingSound = Instance.new("Sound")
	pingSound.Name = "DetectorPing"
	pingSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	pingSound.Volume = 0.45
	pingSound.Parent = gui

	digInput = Net.get("DigInput")

	Net.get("SweepState").OnClientEvent:Connect(function(payload)
		state.inZone = payload.inZone == true
		state.hasSignal = payload.hasSignal == true
		state.strength = payload.strength or 0
		state.angle = payload.angle or 0
		state.rarityHint = payload.rarityHint
		state.inRange = payload.inRange == true
		state.blocked = payload.blocked
		state.digProgress = payload.digProgress or 0
		state.carrying = payload.carrying or state.carrying
		state.capacity = payload.capacity or state.capacity
		renderState()
	end)

	Net.get("Unearthed").OnClientEvent:Connect(function(found)
		state.carrying = found.carrying or state.carrying
		showUnearthed(found)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			setHolding(true)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.E then
			setHolding(false)
		end
	end)

	ui.digButton.MouseButton1Down:Connect(function()
		setHolding(true)
	end)
	ui.digButton.MouseButton1Up:Connect(function()
		setHolding(false)
	end)
	ui.digButton.MouseLeave:Connect(function()
		if isHolding then
			setHolding(false)
		end
	end)

	-- Heartbeat, NOT RenderStepped. RenderStepped only fires while the client is
	-- actually drawing frames — it stops dead if the viewport isn't being rendered,
	-- which took the needle AND the ping audio down with it. The ping is the lead
	-- instrument of this whole mechanic (PLAN §10.7); it must not be a passenger on
	-- the render loop. Heartbeat runs on the simulation step and keeps going.
	RunService.Heartbeat:Connect(function(dt)
		renderFrame(dt)
		stepPing(dt)
	end)

	renderState()
end

return Detector
