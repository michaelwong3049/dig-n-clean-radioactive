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

	THE SCOPE, THE DIG BUTTON AND THE RAD METER SHARE ONE INSTRUMENT BAND NOW — see
	UIKit.Dock. DIAL_SIZE moved into that shared table (Dock.SCOPE_DIAL) because
	HudController's meter needs to know it too, to sit level with it; SCOPE_RADIUS
	stays local because nothing outside this file reads it, but it is DERIVED from
	the shared dial size rather than a second hardcode, because it drives the ring
	sizes, the sweep arm's length AND the blip polar-placement maths all at once —
	change the dial without updating this and blips cluster inside a ring that no
	longer matches what is drawn.
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

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Detector = {}

-- Same fields UIKit.C already carries (panel/stroke/text/dim/green/amber/red/scope),
-- so every COLOR.xxx read throughout render/state logic below keeps working
-- unchanged — this is an alias, not a copy, on purpose.
local COLOR = UIKit.C

-- Ping pacing. At strength 0 it is a slow lonely tick; at 1 it is a stutter.
local PING_INTERVAL_FAR = 1.10
local PING_INTERVAL_NEAR = 0.09
local PING_PITCH_FAR = 0.75
local PING_PITCH_NEAR = 1.85

-- The new-contact chirp. Same asset as the ping, deliberately: it is pitched and
-- loud enough to be unmistakable, and reusing it means the reveal cue cannot go
-- missing because an asset id rotted.
local CHIRP_PITCH = 2.3

local DIAL_SIZE = Dock.SCOPE_DIAL
local SCOPE_RADIUS = Dock.SCOPE_DIAL / 2 - 15 -- px from the centre of the dial to the radius ring
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
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Radar scope: right half of the instrument band, mirrored across the dig
	-- button from the rad meter — see UIKit.Dock. AnchorPoint(0,1) so
	-- Dock.DIAL_LEFT_OFFSET places its LEFT edge (not its centre), the same way
	-- HudController's meter anchors its right edge — the two stay symmetric around
	-- the button between them.
	local dial, ring = UIKit.panel(gui, {
		name = "Scope",
		size = UDim2.fromOffset(DIAL_SIZE, DIAL_SIZE),
		position = UDim2.new(0.5, Dock.DIAL_LEFT_OFFSET, 1, -Dock.INSTRUMENT_BOTTOM),
		anchorPoint = Vector2.new(0, 1),
		color = COLOR.panel,
		transparency = 0.25,
		cornerRadius = UIKit.Radius.pill,
		strokeColor = COLOR.stroke,
	})
	dial.ClipsDescendants = true
	ui.ring = ring

	buildScope(dial)

	ui.centre = UIKit.label(dial, {
		name = "Centre",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, 53),
		size = UDim2.fromOffset(170, 22),
		font = UIKit.Font.body,
		textSize = 15,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 3,
	})

	-- Status line: dead centre, above the instrument band.
	ui.status = UIKit.label(gui, {
		name = "Status",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -Dock.STATUS_BOTTOM),
		size = UDim2.fromOffset(640, Dock.STATUS_HEIGHT),
		font = UIKit.Font.body,
		textSize = 18,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
	})

	-- Dig button. Dead centre of the instrument band — the primary touch/click
	-- target, so it gets the middle rather than either instrument either side of it.
	local digButton, digStroke = UIKit.button(gui, {
		name = "DigButton",
		anchorPoint = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -Dock.INSTRUMENT_BOTTOM),
		size = Dock.DIGBUTTON_SIZE,
		font = UIKit.Font.body,
		textSize = 20,
		color = COLOR.dim,
		fillColor = COLOR.panel,
		fillTransparency = 0.15,
		strokeColor = COLOR.stroke,
		cornerRadius = UIKit.Radius.button,
		text = "HOLD  E  TO PULL",
	})
	ui.digButton = digButton
	ui.digStroke = digStroke

	-- Dig progress, drawn as a fill sliding under the button label. Scale-based, so
	-- it tracks the button's new size with no change of its own.
	local digFill = Instance.new("Frame")
	digFill.Size = UDim2.fromScale(0, 1)
	digFill.BackgroundColor3 = COLOR.green
	digFill.BackgroundTransparency = 0.7
	digFill.BorderSizePixel = 0
	digFill.ZIndex = 0
	digFill.Parent = digButton
	ui.digFill = digFill

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UIKit.Radius.button
	fillCorner.Parent = digFill

	-- Unearth banner: true centre, upper-third of the screen. Already lived there
	-- before this pass; only the size and type grew.
	local banner, bannerStroke = UIKit.panel(gui, {
		name = "Banner",
		size = UDim2.fromOffset(640, 160),
		position = UDim2.fromScale(0.5, 0.32),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = COLOR.panel,
		transparency = 0.1,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		visible = false,
	})
	ui.banner = banner
	ui.bannerStroke = bannerStroke

	ui.bannerRarity = UIKit.label(banner, {
		name = "Rarity",
		position = UDim2.fromOffset(0, 14),
		size = UDim2.new(1, 0, 0, 22),
		font = UIKit.Font.body,
		textSize = 18,
		xAlign = Enum.TextXAlignment.Center,
	})

	ui.bannerName = UIKit.label(banner, {
		name = "NameLabel", -- NOT "Name" — every Instance already has a .Name
		-- property, so a child actually named "Name" is unreachable by
		-- Banner.Name (that resolves to the property, a string, not the child).
		-- Harmless here since every reader uses the captured ui.bannerName
		-- reference, never a re-lookup, but it is a landmine for anyone who
		-- later does try to reach it by path.
		position = UDim2.fromOffset(0, 40),
		size = UDim2.new(1, 0, 0, 50),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.hero - 4,
		color = COLOR.text,
		xAlign = Enum.TextXAlignment.Center,
	})

	ui.bannerFlavor = UIKit.label(banner, {
		name = "Flavor",
		anchorPoint = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 96),
		size = UDim2.new(1, -40, 0, 50),
		font = UIKit.Font.body,
		textSize = 17,
		color = COLOR.dim,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
	})

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
		-- payload.carrying / payload.capacity are deliberately ignored: the hotbar
		-- (InventoryController, fed by CarryState) is the authority on the bag now,
		-- and two widgets answering "how full am I" from two different remotes is how
		-- they end up disagreeing by a tick.
		chirp(payload.newContacts or 0)
		renderState()
	end)

	Net.get("Unearthed").OnClientEvent:Connect(function(found)
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
