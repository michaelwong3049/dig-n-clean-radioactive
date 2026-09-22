--[[
	TreadmillController.lua — the belt you are standing on, and what it is buying you.

	TWO JOBS, AND THEY ARE DELIBERATELY BOTH SMALL:

	  1. THE CARD. While you are training, a panel above the hotbar shows the speed you
	     are at, the bar to the next point, what the belt is paying per second and what
	     the next rung costs. It fades in on arrival and out on departure, and it is
	     drawn from SpeedState — this file computes no part of the curve, because
	     Config/Treadmill owns it and a second copy would drift.

	  2. THE MACHINE. The belt's slats scroll and its rollers turn while a session is
	     live, and the character plays its own run animation on the spot. All of it is
	     LOCAL: the parts moved here are cosmetic children of a server-built model (see
	     build/Plots.buildTreadmill — the Belt part itself, the one thing a service
	     reads, is never touched), and nothing about the animation crosses the wire.

	WHY THE CARD IS A SCREEN PANEL AND NOT A BILLBOARD, when LiquidController's
	readout is the opposite: what is loaded in your hose is a fact about a machine on
	YOUR plot, so the machine can answer for it. Training is not — any belt on any base
	trains whoever is standing on it, at their own rung (TreadmillService's header), so
	the numbers here belong to the player rather than to the plot. The console's own
	world billboard keeps showing its OWNER's rung, exactly as the luck button shows
	its owner's multiplier, and the two never claim to be the same thing.

	THE RUN ANIMATION IS BORROWED, NOT AUTHORED. The id is read off the character's own
	`Animate` script at play time rather than hardcoded, so this cannot ship a broken
	asset reference and it automatically matches whatever rig (R6/R15) the player is on.
	If the script is not there — a custom rig, a future avatar change — the belt still
	scrolls and the card still works, and nobody sees an error. It is decoration, and
	decoration is not allowed to be load-bearing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local Treadmill = {}

--- How far a slat travels before it wraps back to the start, in studs. One slat
--- pitch: build/Plots spaces them at beltL/10, so a slat that has travelled exactly
--- this far is sitting where its neighbour was and the loop is invisible.
local SLAT_PITCH = 1.0

--- Belt speed in studs/sec, purely cosmetic. Fast enough to read as "running", slow
--- enough not to strobe against the slat pitch at 60fps.
local BELT_SPEED = 9

--- How far from the character we will look for the belt they are standing on. The
--- station radius is 5 and the machine is 10 studs long, so anything inside 9 of the
--- root is the one they are on; nothing else on a plot is named "Belt".
local BELT_SEARCH = 9

local ui = {}
local state: any = nil

--- The parts we are animating this session, resolved once on arrival: the model, its
--- slats and their home positions. Cleared on departure, which is also what puts
--- every slat back exactly where the server built it.
local machine: { model: Instance?, slats: { { part: BasePart, home: CFrame } }, rollers: { BasePart } } =
	{ model = nil, slats = {}, rollers = {} }

local runTrack: AnimationTrack? = nil
local travelled = 0

-- ── The card ──────────────────────────────────────────────────────────────

local function build(): Frame?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "TreadmillCard"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui
	ui.screen = screen

	-- 1280x720 design pixels on the shared canvas, like every other HUD surface.
	local canvas = UIKit.canvas(screen)

	-- Bottom centre, sat above the hotbar. The player is looking down the belt while
	-- this is up, so it wants to be in the middle rather than off in the instrument
	-- column where the rad meter lives.
	local panel = UIKit.panel(canvas, {
		name = "Card",
		size = UDim2.fromOffset(330, 92),
		position = UDim2.new(0.5, 0, 1, -170),
		anchorPoint = Vector2.new(0.5, 1),
		color = UIKit.C.panel,
		transparency = 0.12,
		cornerRadius = UIKit.Radius.card,
		strokeThickness = UIKit.Stroke.normal,
	})
	ui.panel = panel

	ui.speed = UIKit.label(panel, {
		name = "Speed",
		size = UDim2.fromOffset(150, 34),
		position = UDim2.fromOffset(16, 10),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.title,
		color = UIKit.C.text,
		xAlign = Enum.TextXAlignment.Left,
		text = "SPEED 26",
	})

	ui.rate = UIKit.label(panel, {
		name = "Rate",
		size = UDim2.fromOffset(148, 34),
		position = UDim2.new(1, -164, 0, 10),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.green,
		xAlign = Enum.TextXAlignment.Right,
		text = "",
	})

	-- The bar. A dark trough with a green fill, the same two-frame shape the wash
	-- bay's clean-percent bar uses.
	local trough = UIKit.panel(panel, {
		name = "Trough",
		size = UDim2.new(1, -32, 0, 10),
		position = UDim2.fromOffset(16, 50),
		color = UIKit.C.empty,
		transparency = 0,
		cornerRadius = UIKit.Radius.pill,
		strokeThickness = 0,
	})
	ui.fill = UIKit.panel(trough, {
		name = "Fill",
		size = UDim2.fromScale(0, 1),
		position = UDim2.fromScale(0, 0),
		color = UIKit.C.green,
		transparency = 0,
		cornerRadius = UIKit.Radius.pill,
		strokeThickness = 0,
	})

	ui.belt = UIKit.label(panel, {
		name = "Belt",
		size = UDim2.new(1, -32, 0, 18),
		position = UDim2.fromOffset(16, 66),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Left,
		text = "",
	})

	panel.Visible = false
	return panel
end

local function ensure()
	if ui.panel == nil or ui.panel.Parent == nil then
		ui.panel = build()
	end
end

local function paint(view: any)
	ensure()
	if ui.panel == nil then
		return
	end

	ui.speed.Text = `SPEED {view.speed}`
	ui.fill.Size = UDim2.fromScale(math.clamp(view.progress or 0, 0, 1), 1)

	if view.speed >= view.maxSpeed then
		-- The one line in this whole feature that ever stops counting. Say so plainly
		-- rather than leaving a full bar and a rate that is buying nothing.
		ui.rate.Text = "MAXED"
		ui.rate.TextColor3 = UIKit.C.amber
		ui.fill.Size = UDim2.fromScale(1, 1)
		ui.belt.Text = `{view.tierName} — nothing left to train`
		return
	end

	ui.rate.Text = if view.training then string.format("+%.2f/s", view.rate) else "STEP ON"
	ui.rate.TextColor3 = if view.training then UIKit.C.green else UIKit.C.dim

	-- OVER-RATED IS THE ONE THING THE PLAYER MUST BE ABLE TO SEE. The falloff is
	-- multiplicative and silent (Config/Treadmill.rateFor) — a player grinding at a
	-- sixteenth rate with no explanation just thinks the feature is broken. Naming the
	-- belt's rating next to their speed is what turns it back into a decision.
	local over = view.speed >= view.rated
	if over then
		ui.belt.Text = if view.nextCost
			then `{view.tierName} is rated {view.rated} — next belt $ {view.nextCost}`
			else `{view.tierName} — past its rating`
		ui.belt.TextColor3 = UIKit.C.amber
	else
		ui.belt.Text = if view.nextCost
			then `{view.tierName} — rated {view.rated}, next belt $ {view.nextCost}`
			else `{view.tierName} — the last belt there is`
		ui.belt.TextColor3 = UIKit.C.dim
	end
end

local function show(visible: boolean)
	ensure()
	if ui.panel == nil then
		return
	end
	if visible then
		ui.panel.Visible = true
	end
	-- Fade rather than snap, and destroy nothing: the card comes back every time the
	-- player steps on, which for an AFK grind may be hundreds of times a session.
	TweenService:Create(ui.panel, TweenInfo.new(0.25), {
		BackgroundTransparency = if visible then 0.12 else 1,
	}):Play()
	for _, child in ui.panel:GetDescendants() do
		if child:IsA("TextLabel") then
			TweenService:Create(child, TweenInfo.new(0.25), { TextTransparency = if visible then 0 else 1 }):Play()
		elseif child:IsA("Frame") then
			TweenService:Create(child, TweenInfo.new(0.25), { BackgroundTransparency = if visible then 0 else 1 }):Play()
		end
	end
	if not visible then
		task.delay(0.3, function()
			if ui.panel and state and not state.training then
				ui.panel.Visible = false
			end
		end)
	end
end

-- ── The machine ───────────────────────────────────────────────────────────

--- The treadmill model the local character is standing on, or nil. Found by distance
--- rather than by plot index on purpose: you can train on anyone's belt, so "which
--- plot is mine" is the wrong question to ask here.
local function findMachine(): Instance?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local plots = Workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end

	local best, bestDistance = nil, BELT_SEARCH * BELT_SEARCH
	for _, plot in plots:GetChildren() do
		local model = plot:FindFirstChild("Treadmill", true)
		local belt = model and model:FindFirstChild("Belt", true)
		if belt and belt:IsA("BasePart") then
			local distance = (belt.Position - root.Position).Magnitude
			if distance * distance < bestDistance then
				best, bestDistance = model, distance * distance
			end
		end
	end
	return best
end

--- Latch onto a machine: cache its slats' home CFrames so the scroll below is always
--- an offset from where the SERVER put them, never from wherever they drifted to.
--- That is what makes `release` exact rather than approximately exact.
local function latch()
	local model = findMachine()
	if model == nil then
		return
	end
	machine.model = model
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Name == "Slat" then
				table.insert(machine.slats, { part = part, home = part.CFrame })
			elseif part.Name == "Roller" then
				table.insert(machine.rollers, part)
			end
		end
	end
	travelled = 0
end

local function release()
	for _, slat in machine.slats do
		slat.part.CFrame = slat.home
	end
	machine.model = nil
	table.clear(machine.slats)
	table.clear(machine.rollers)
	travelled = 0
end

--- Slide every slat one notch along the belt's own local -Z (the direction the runner
--- faces), wrapping at a full pitch. Rollers spin about their own long axis.
local function animate(dt: number)
	if machine.model == nil then
		return
	end
	travelled = (travelled + BELT_SPEED * dt) % SLAT_PITCH

	for _, slat in machine.slats do
		slat.part.CFrame = slat.home * CFrame.new(0, 0, -travelled)
	end
	local spin = CFrame.Angles(0, 0, -BELT_SPEED * dt)
	for _, roller in machine.rollers do
		roller.CFrame = roller.CFrame * spin
	end
end

--- Play the character's own run animation on the spot. Borrowed off the default
--- Animate script rather than hardcoded — see this file's header.
local function startRunning()
	if runTrack then
		runTrack:Play(0.2)
		return
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animateScript = character and character:FindFirstChild("Animate")
	local source = animateScript and animateScript:FindFirstChild("run")
	local anim = source and source:FindFirstChildWhichIsA("Animation")
	if animator == nil or anim == nil then
		return -- custom rig, or the character is still assembling. Decoration only.
	end

	local clone = anim:Clone()
	local ok, track = pcall(function()
		return animator:LoadAnimation(clone)
	end)
	if not ok or track == nil then
		return
	end
	runTrack = track
	track.Priority = Enum.AnimationPriority.Movement
	track.Looped = true
	track:Play(0.2)
end

local function stopRunning()
	if runTrack then
		runTrack:Stop(0.2)
	end
end

--- The character is rebuilt on every respawn, so a track loaded onto the old
--- Animator is dead and must not be reused. Dropping the reference is enough:
--- `startRunning` reloads from whatever rig exists at the time.
local function onCharacter()
	runTrack = nil
	release()
end

-- ── Wiring ────────────────────────────────────────────────────────────────

function Treadmill.start()
	Players.LocalPlayer.CharacterAdded:Connect(onCharacter)

	Net.get("SpeedState").OnClientEvent:Connect(function(view)
		if type(view) ~= "table" then
			return
		end
		local wasTraining = state ~= nil and state.training
		state = view
		paint(view)

		if view.training and not wasTraining then
			latch()
			startRunning()
			show(true)
		elseif not view.training and wasTraining then
			release()
			stopRunning()
			show(false)
		end
	end)

	-- One connection for the life of the session, and it does nothing at all unless a
	-- machine is latched. Connecting and disconnecting per session would be the same
	-- work plus a leak the first time an edge is missed — and the client bootstrap
	-- never calls a `stop` on anything, so there would be nowhere honest to undo it.
	RunService.RenderStepped:Connect(animate)
end

return Treadmill
