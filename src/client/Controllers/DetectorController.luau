--[[
	DetectorController.lua — the sweep, rendered.

	WHAT THIS DRAWS NOW, AND WHAT IT USED TO DRAW.
	It used to be a NEEDLE. The server sent one angle and one strength and the whole
	screen was derived from those two numbers, because the field was a secret and a
	direction was the most the client was allowed to know.

	The detector no longer works that way. Its radius REVEALS: every registerable
	signal inside it stands up out of the ground as an aura, and the server sends this
	client the ones it personally registers, as offsets from the player. So the dial
	is a RADAR SCOPE — you at the centre, your radius as the ring, a blip per contact.
	The direction problem the needle existed to solve does not exist any more; the
	world answers it directly.

	THE SCOPE IS NOT REDUNDANT WITH THE AURAS, and the reason is worth keeping.
	An aura is one shared part that every player in the server can see, so it cannot
	say anything that is supposed to be private — and rarity is private, gated per
	player by detectorClarity (PLAN §2 step 1). The aura says "something is here"; the
	BLIP is where "and it is Legendary" gets to live, because the blip is drawn from a
	payload only this client receives. Delete the scope and the entire clarity upgrade
	track loses its display.

	Hot/cold is still carried by SOUND. PLAN §10.7 wants a player able to sweep with
	their eyes half shut, so there are two cues: a CHIRP the moment a new contact
	enters the radius (the server counts them — the client has no uids to diff), and
	the old rate-and-pitch ping keyed to how close the nearest one is.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

local Detector = {}

local COLOR = {
	panel = Color3.fromHex("0C0F0A"),
	stroke = Color3.fromHex("2A3324"),
	text = Color3.fromHex("E4E9DE"),
	dim = Color3.fromHex("7C8874"),
	green = Color3.fromHex("8FE04A"),
	amber = Color3.fromHex("F59E0B"),
	red = Color3.fromHex("EF4444"),
	-- The instrument cyan the auras are built from, so the scope and the world are
	-- obviously the same instrument. See build/SignalAura.
	scope = Color3.fromHex("8FD8FF"),
}

-- Ping pacing. At strength 0 it is a slow lonely tick; at 1 it is a stutter.
local PING_INTERVAL_FAR = 1.10
local PING_INTERVAL_NEAR = 0.09
local PING_PITCH_FAR = 0.75
local PING_PITCH_NEAR = 1.85

-- The new-contact chirp. Same asset as the ping, deliberately: it is pitched and
-- loud enough to be unmistakable, and reusing it means the reveal cue cannot go
-- missing because an asset id rotted.
local CHIRP_PITCH = 2.3

local DIAL_SIZE = 150
local SCOPE_RADIUS = 62 -- px from the centre of the dial to the radius ring
local MAX_BLIPS = 12 -- matches DigService.MAX_CONTACTS; more would never arrive

type Contact = { dx: number, dz: number, rarity: string? }

local state = {
	inZone = false,
	hasSignal = false,
	strength = 0,
	radius = 0,
	contacts = {} :: { Contact },
	rarityHint = nil :: string?,
	inRange = false,
	blocked = nil :: string?,
	digProgress = 0,
	carrying = 0,
	capacity = 0,
}

local ui = {}
local blips: { Frame } = {}
local pingClock = 0
local isHolding = false

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ── Build ───────────────────────────────────────────────────────────

local function buildScope(parent: GuiObject)
	-- The radius ring. This is the stat you are buying, drawn at its actual size
	-- relative to the blips inside it, so a detector upgrade is legible on the HUD
	-- and not just in the shop.
	local edge = Instance.new("Frame")
	edge.Name = "RadiusRing"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.fromScale(0.5, 0.5)
	edge.Size = UDim2.fromOffset(SCOPE_RADIUS * 2, SCOPE_RADIUS * 2)
	edge.BackgroundTransparency = 1
	edge.Parent = parent

	local edgeCorner = Instance.new("UICorner")
	edgeCorner.CornerRadius = UDim.new(1, 0)
	edgeCorner.Parent = edge

	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Color = COLOR.scope
	edgeStroke.Transparency = 0.55
	edgeStroke.Thickness = 1
	edgeStroke.Parent = edge
	ui.edgeStroke = edgeStroke

	-- Half-radius ring, purely so distance on the scope is readable rather than just
	-- ordinal. Without it every blip is "somewhere in the circle".
	local inner = Instance.new("Frame")
	inner.Name = "HalfRing"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromOffset(SCOPE_RADIUS, SCOPE_RADIUS)
	inner.BackgroundTransparency = 1
	inner.Parent = parent

	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(1, 0)
	innerCorner.Parent = inner

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = COLOR.scope
	innerStroke.Transparency = 0.82
	innerStroke.Thickness = 1
	innerStroke.Parent = inner

	-- The sweep arm. One revolution per RANGE_RING_PERIOD, off the same clock as the
	-- range ring the detector throws on the ground, so the HUD and the world are
	-- visibly the same pulse rather than two unrelated animations.
	local arm = Instance.new("Frame")
	arm.Name = "SweepArm"
	arm.AnchorPoint = Vector2.new(0.5, 1)
	arm.Position = UDim2.fromScale(0.5, 0.5)
	arm.Size = UDim2.fromOffset(2, SCOPE_RADIUS)
	arm.BackgroundColor3 = COLOR.scope
	arm.BackgroundTransparency = 0.6
	arm.BorderSizePixel = 0
	arm.Parent = parent
	ui.arm = arm

	-- You. A fixed dot so the blips read as "relative to me" instantly.
	local origin = Instance.new("Frame")
	origin.Name = "Origin"
	origin.AnchorPoint = Vector2.new(0.5, 0.5)
	origin.Position = UDim2.fromScale(0.5, 0.5)
	origin.Size = UDim2.fromOffset(4, 4)
	origin.BackgroundColor3 = COLOR.text
	origin.BackgroundTransparency = 0.35
	origin.BorderSizePixel = 0
	origin.Parent = parent

	local originCorner = Instance.new("UICorner")
	originCorner.CornerRadius = UDim.new(1, 0)
	originCorner.Parent = origin

	-- Pooled. Contacts churn every tick as the player walks, and building and
	-- destroying twelve frames ten times a second to show the same twelve dots is
	-- pure garbage collection for no visible gain.
	for index = 1, MAX_BLIPS do
		local blip = Instance.new("Frame")
		blip.Name = `Blip{index}`
		blip.AnchorPoint = Vector2.new(0.5, 0.5)
		blip.Size = UDim2.fromOffset(8, 8)
		blip.BackgroundColor3 = COLOR.scope
		blip.BorderSizePixel = 0
		blip.Visible = false
		blip.ZIndex = 2
		blip.Parent = parent

		local blipCorner = Instance.new("UICorner")
		blipCorner.CornerRadius = UDim.new(1, 0)
		blipCorner.Parent = blip

		local blipStroke = Instance.new("UIStroke")
		blipStroke.Color = COLOR.panel
		blipStroke.Thickness = 1
		blipStroke.Parent = blip

		blips[index] = blip
	end
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DetectorHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Radar scope, bottom centre. Same frame the needle dial used to live in.
	local dial = Instance.new("Frame")
	dial.Name = "Scope"
	dial.AnchorPoint = Vector2.new(0.5, 1)
	dial.Position = UDim2.new(0.5, 0, 1, -128)
	dial.Size = UDim2.fromOffset(DIAL_SIZE, DIAL_SIZE)
	dial.BackgroundColor3 = COLOR.panel
	dial.BackgroundTransparency = 0.25
	dial.ClipsDescendants = true
	dial.Parent = gui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = dial

	local ring = Instance.new("UIStroke")
	ring.Color = COLOR.stroke
	ring.Thickness = 2
	ring.Parent = dial
	ui.ring = ring

	buildScope(dial)

	local centre = Instance.new("TextLabel")
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.Position = UDim2.new(0.5, 0, 0.5, 44)
	centre.Size = UDim2.fromOffset(140, 18)
	centre.BackgroundTransparency = 1
	centre.Font = Enum.Font.GothamBold
	centre.TextSize = 13
	centre.TextColor3 = COLOR.dim
	centre.ZIndex = 3
	centre.Text = ""
	centre.Parent = dial
	ui.centre = centre

	-- Status line
	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -104)
	status.Size = UDim2.fromOffset(460, 20)
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
	return COLOR.scope
end

--- Contacts arrive as WORLD-space offsets from the player. The scope is drawn in
--- camera space so "up" is wherever the player is looking — a radar that stays
--- locked to world north forces the player to do the rotation in their head, every
--- frame, forever.
---
--- The sign convention here is the needle's, kept deliberately: an angle measured
--- from the camera's look direction maps straight onto clockwise-from-up, which is
--- what both the old Rotation property and this offset use.
local function renderBlips()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local look = camera.CFrame.LookVector
	local cameraYaw = math.atan2(look.Z, look.X)
	local radius = if state.radius > 0 then state.radius else 1

	for index = 1, MAX_BLIPS do
		local blip = blips[index]
		local contact = state.contacts[index]

		if contact == nil then
			blip.Visible = false
			continue
		end

		local distance = math.sqrt(contact.dx * contact.dx + contact.dz * contact.dz)
		local relative = math.atan2(contact.dz, contact.dx) - cameraYaw
		-- Clamped, not hidden: a contact fractionally outside the ring because the
		-- player moved between ticks should sit ON the ring, not blink out.
		local reach = math.min(distance / radius, 1) * SCOPE_RADIUS

		blip.Position = UDim2.new(0.5, math.sin(relative) * reach, 0.5, -math.cos(relative) * reach)

		local def = if contact.rarity then Rarity.DEFS[contact.rarity] else nil
		blip.BackgroundColor3 = if def then def.color else COLOR.scope

		-- The nearest contact is the one every other part of the HUD is talking
		-- about, so it is drawn bigger. Without this the scope reads as a cloud and
		-- the status line appears to be describing an arbitrary member of it.
		local lead = index == 1
		blip.Size = UDim2.fromOffset(if lead then 11 else 7, if lead then 11 else 7)
		blip.Visible = true
	end
end

local function renderFrame(_dt: number)
	local colour = signalColor()

	renderBlips()

	-- One revolution per pulse period, sharing os.clock with FieldController's ground
	-- ring so the two land together without either one owning the other's timing.
	local phase = (os.clock() % Tuning.RANGE_RING_PERIOD) / Tuning.RANGE_RING_PERIOD
	ui.arm.Rotation = phase * 360
	ui.arm.BackgroundTransparency = if state.inZone then 0.6 else 0.9

	ui.ring.Color = if state.hasSignal then colour else COLOR.stroke
	ui.edgeStroke.Color = if state.hasSignal then colour else COLOR.scope
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
	ui.centre.Text = `{math.floor(state.radius + 0.5)} stud sweep`
	ui.centre.TextColor3 = COLOR.dim

	if not state.hasSignal then
		-- Standing in a glow that somebody else's detector put there. This is a real
		-- state, not an error: auras are public, the tier gates are not.
		if state.blocked == "unregistered" then
			ui.status.Text = "that signal is past your detector \u{2014} you cannot lock on"
			ui.status.TextColor3 = COLOR.red
			ui.digButton.Text = "CANNOT LOCK ON"
			ui.digButton.TextColor3 = COLOR.red
			ui.digStroke.Color = COLOR.red
			return
		end

		ui.status.Text = "sweeping\u{2026} nothing in range"
		ui.status.TextColor3 = COLOR.dim
		ui.digButton.Text = "HOLD  E  TO PULL"
		ui.digStroke.Color = COLOR.stroke
		ui.digButton.TextColor3 = COLOR.dim
		return
	end

	local count = #state.contacts
	local named = if state.rarityHint then ` \u{2014} nearest reads {string.lower(state.rarityHint)}` else ""

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
		ui.status.Text = `you are standing on it{named}`
		ui.status.TextColor3 = COLOR.green
		ui.digButton.Text = if isHolding then "PULLING\u{2026}" else "HOLD  E  TO PULL"
		ui.digButton.TextColor3 = COLOR.green
		ui.digStroke.Color = COLOR.green
	else
		local plural = if count == 1 then "signal" else "signals"
		ui.status.Text = `{count} {plural} in range \u{2014} walk to the glow{named}`
		ui.status.TextColor3 = COLOR.amber
		ui.digButton.Text = "GET CLOSER"
		ui.digButton.TextColor3 = COLOR.dim
		ui.digStroke.Color = COLOR.stroke
	end
end

-- ── Ping ────────────────────────────────────────────────────────────

local pingSound: Sound? = nil
local chirpSound: Sound? = nil

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

--- The reveal cue. The server counts new contacts because only the server has uids
--- to diff; the client would have to infer it from the contact count, which is wrong
--- every time one signal leaves the radius as another enters.
local function chirp(count: number)
	if chirpSound == nil or count <= 0 then
		return
	end
	chirpSound:Play()
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

--- Read by FieldController so the ground ring is drawn at the radius the server
--- actually resolved, rather than the client guessing from its own gear numbers —
--- perks fold into detectorRadius and only StatResolver knows the answer.
function Detector.radius(): number
	return if state.inZone then state.radius else 0
end

function Detector.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	pingSound = Instance.new("Sound")
	pingSound.Name = "DetectorPing"
	pingSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	pingSound.Volume = 0.45
	pingSound.Parent = gui

	chirpSound = Instance.new("Sound")
	chirpSound.Name = "DetectorChirp"
	chirpSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	chirpSound.Volume = 0.7
	chirpSound.PlaybackSpeed = CHIRP_PITCH
	chirpSound.Parent = gui

	digInput = Net.get("DigInput")

	Net.get("SweepState").OnClientEvent:Connect(function(payload)
		state.inZone = payload.inZone == true
		state.hasSignal = payload.hasSignal == true
		state.strength = payload.strength or 0
		state.radius = payload.radius or 0
		state.contacts = payload.contacts or {}
		state.rarityHint = payload.rarityHint
		state.inRange = payload.inRange == true
		state.blocked = payload.blocked
		state.digProgress = payload.digProgress or 0
		state.carrying = payload.carrying or state.carrying
		state.capacity = payload.capacity or state.capacity
		chirp(payload.newContacts or 0)
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
