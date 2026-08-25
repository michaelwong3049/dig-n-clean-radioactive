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

	THE SCOPE IS GONE NOW, removed on request, and this is what went with it: the
	dial, its two range rings, the sweeping arm, the origin dot, the twelve pooled
	blips, the "N stud sweep" caption, and Dock.SCOPE_DIAL / Dock.DIAL_LEFT_OFFSET.

	READ THIS BEFORE BUILDING ANYTHING THAT NEEDS PER-PLAYER RARITY ON SCREEN.
	The scope was not redundant with the ground auras, and the reason it was not is
	now an unsolved problem rather than a solved one. An aura is one shared part that
	every player in the server can see, so it cannot say anything that is supposed to
	be private — and rarity IS private, gated per player by detectorClarity (PLAN §2
	step 1). The blip was where "and it is Legendary" got to live, because it was
	drawn from a payload only this client receives. With the scope deleted, the
	`clarity` stat on the Detector track has nowhere left to display: the server still
	computes it, still gates `rarityHint` by it, and the status line below still
	prints "nearest reads legendary" from it — but the PER-CONTACT rarity that only
	the blips could show is no longer drawn anywhere. If clarity needs to feel bought
	again, that is the hole to fill.

	Hot/cold is still carried by SOUND, and now carries more of the load than it used
	to. PLAN §10.7 wants a player able to sweep with their eyes half shut, so there
	are two cues: a CHIRP the moment a new contact enters the radius (the server
	counts them — the client has no uids to diff), and the old rate-and-pitch ping
	keyed to how close the nearest one is. Those, the ground auras and the status line
	are the whole of the sweep's feedback now.

	THE DIG BUTTON AND THE RAD METER SHARE ONE INSTRUMENT BAND — see UIKit.Dock. With
	the dial gone the band is 144px (the meter's height) rather than 180.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Workspace and Config/Tuning went with the scope: the camera was only ever read to
-- rotate blips into camera space, and Tuning only for RANGE_RING_PERIOD, which drove
-- the sweep arm. Rarity stays — the unearth banner still colours by it.
local Shared = ReplicatedStorage.Shared
local Rarity = require(Shared.Config.Rarity)
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
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- No radar scope. It used to sit to the dig button's right, mirroring the rad
	-- meter across it; nothing occupies that side of the band any more.

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

--- The dig fill is all that is left of the per-frame work. Blip placement, the sweep
--- arm's rotation and the two ring colours all lived here and all went with the
--- scope; `state.contacts` is still received and still counted by the status line
--- ("3 signals in range"), it is simply no longer PLOTTED anywhere.
local function renderFrame(_dt: number)
	ui.digFill.Size = UDim2.fromScale(state.digProgress, 1)
end

local function renderState()
	if not state.inZone then
		-- BLANK, AND THE BUTTON GOES WITH IT. Out of a zone means you are in the plaza
		-- shopping, banking or racking. A status line telling you that you cannot dig
		-- on the shop floor, and a PULL button that does nothing when pressed, are
		-- both noise printed over the top of whatever panel you actually came here to
		-- use — and between them they are what stopped the station panel from being
		-- able to sit at screen centre. Every other branch below still speaks,
		-- because every other branch is about a zone you are standing in.
		--
		-- The button costs nothing to lose here: it is inert out of a zone (the
		-- server has no signal to give), and E still works, so nothing is unreachable
		-- — it reappears the moment you step onto sludge, which is also the moment it
		-- starts meaning something.
		ui.status.Text = ""
		ui.digButton.Visible = false
		ui.digButton.Text = "HOLD  E  TO PULL"
		ui.digStroke.Color = COLOR.stroke
		return
	end

	ui.digButton.Visible = true

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
