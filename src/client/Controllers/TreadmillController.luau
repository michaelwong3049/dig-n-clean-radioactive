--[[
	TreadmillController.lua — the belt you are standing on, and what it is buying you.

	TWO JOBS, AND THEY ARE DELIBERATELY BOTH SMALL:

	  1. THE BAR. While you are training, a big blue bar floats above the hotbar, with
	     no card behind it: the Speed you have against what the next walk-speed point
	     needs, your walk speed and roughly how long until it goes up, and what the next
	     belt costs. Every Speed push floats a shoe and "+10" off a random spot around
	     the bar, and filling it floats "WALK SPEED 35!". Levels are never named on
	     screen: what the player hears about is walk speed. It pops in on arrival and out
	     on departure. It is drawn from SpeedController's copy of SpeedState — the same
	     number the HUD badge counts, so the two can never disagree — and computes no
	     part of the curve itself.

	  2. THE MACHINE. Every belt near the camera scrolls its chevrons and turns its
	     rollers all the time, and while you train the character plays its own run
	     animation on the spot. All of it is
	     LOCAL: the parts moved here are cosmetic children of a server-built model (see
	     build/Plots.buildTreadmill — the Belt part itself, the one thing a service
	     reads, is never touched), and nothing about the animation crosses the wire.

	WHY THE CARD IS A SCREEN PANEL AND NOT A BILLBOARD, when LiquidController's
	readout is the opposite: what is loaded in your hose is a fact about a machine on
	YOUR plot, so the machine can answer for it. Training is not — any belt on any base
	trains whoever is standing on it, at their own rung (TreadmillService's header), so
	the numbers here belong to the player rather than to the plot. The console's own
	world billboard keeps showing its OWNER's walk speed, exactly as the luck button
	shows its owner's multiplier, and the two never claim to be the same thing.

	THE RUN ANIMATION IS BORROWED, NOT AUTHORED. The id is read off the character's own
	`Animate` script at play time rather than hardcoded, so this cannot ship a broken
	asset reference and it automatically matches whatever rig (R6/R15) the player is on.
	If the script is not there — a custom rig, a future avatar change — the belt still
	scrolls and the card still works, and nobody sees an error. It is decoration, and
	decoration is not allowed to be load-bearing.

	3. THE WALKTHROUGH. Buying treadmill access (Treadmill.UNLOCK_PRICE) is owed a short
	   spotlight walkthrough, the Quarantine Locker's (client/LockerTutorial): the
	   machine, the Speed badge, the console. SpeedState's `tutorial` says it is owed;
	   it starts once the player's own machine is near and on screen, and finishing or
	   skipping reports it seen. A LOCKED machine (`Locked` attribute, build/Plots)
	   stands still: its belt is not scrolled.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Artwork = require(script.Parent.Parent.HudArtwork)
local UIKit = require(script.Parent.Parent.UIKit)
local LockerTutorial = require(script.Parent.Parent.LockerTutorial)
local Speed = require(script.Parent.SpeedController)

local Treadmill = {}

--- Belt speed in studs/sec, purely cosmetic. Fast enough to read as "running", slow
--- enough not to strobe against the slat pitch at 60fps.
local BELT_SPEED = 9

--- Belts further than this from the camera are left still. Far enough that the one
--- across the plot you are looking at runs, near enough that the other five bases in
--- the ring are not all scrolling for nobody.
local ANIM_RANGE = 90
local RANGE_REFRESH = 0.5

local ui: any = {}
local shown = false

local runTrack: AnimationTrack? = nil

-- ── The bar ───────────────────────────────────────────────────────────────

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

-- The speed badge's palette (SpeedController), so the bar reads as the same system.
local STYLE = {
	trough = Color3.fromHex("0F2F66"),
	fillTop = Color3.fromHex("5CC2FF"),
	fillBottom = Color3.fromHex("1C8CF0"),
	caption = Color3.fromHex("DDF3FF"),
	gain = Color3.fromHex("8AD4FF"),
	walkUp = Color3.fromHex("FFE45C"),
	valueFont = Enum.Font.LuckiestGuy,
	bodyFont = Enum.Font.FredokaOne,
}

-- Design px. Nothing sits behind any of it, so every line of text wears a heavier ink
-- outline to read against the floor, the grass or the sky.
local LAYOUT = {
	barW = 400,
	barH = 36,
	outline = 4,
	shadowDrop = 5,
	needTextSize = 20,
	-- The walk and belt lines hang UNDER the bar: the air above it is where the
	-- popups float.
	walkTop = 52,
	beltTop = 74,
	height = 92,
	textStroke = 2.5,
	shoe = 28,
	gainTextSize = 22,
	gainGap = 70, -- a new "+10" never lands within this many px of the last one
}

local ROUND = UDim.new(0.5, 0)
local POP_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PUNCH_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function formatCash(amount: number): string
	if amount >= 1_000_000 then
		return string.format("$%.1fM", amount / 1_000_000)
	elseif amount >= 1_000 then
		return string.format("$%.1fK", amount / 1_000)
	end
	return string.format("$%d", amount)
end

--- "45s", "3m 20s", "1h 05m" — how long the belt still has to run for the next walk
--- speed point.
local function formatEta(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s < 60 then
		return `{s}s`
	elseif s < 3600 then
		return string.format("%dm %02ds", s // 60, s % 60)
	end
	return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
end

local function blob(parent: Instance, name: string, rect: { number }, color: Color3, zIndex: number, radius: UDim, stroke: number?): Frame
	local frame = UIKit.panel(parent, {
		name = name,
		position = UDim2.fromOffset(rect[1], rect[2]),
		size = UDim2.fromOffset(rect[3], rect[4]),
		color = color,
		transparency = 0,
		cornerRadius = radius,
		strokeColor = INK,
		strokeThickness = stroke or 0,
		zIndex = zIndex,
	})
	return frame
end

local function text(parent: Instance, name: string, rect: { number }, props: any): TextLabel
	local label = UIKit.label(parent, {
		name = name,
		position = UDim2.fromOffset(rect[1], rect[2]),
		size = UDim2.fromOffset(rect[3], rect[4]),
		font = props.font or STYLE.bodyFont,
		textSize = props.textSize,
		color = props.color or WHITE,
		xAlign = props.xAlign or Enum.TextXAlignment.Left,
		shadow = false,
		text = props.text or "",
		zIndex = props.zIndex or 5,
	})
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = props.stroke or LAYOUT.textStroke
	end
	return label
end

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
	-- column where the rad meter lives. An invisible footprint holds the bar, its lines
	-- and the popups, so one UIScale pops the lot. Its top edge IS the bar's top edge.
	local L = LAYOUT
	local root = Instance.new("Frame")
	root.Name = "SpeedBar"
	root.Size = UDim2.fromOffset(L.barW, L.height)
	root.Position = UDim2.new(0.5, 0, 1, -170)
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = canvas
	ui.panel = root
	ui.scale = Instance.new("UIScale")
	ui.scale.Parent = root

	-- The hard shadow is the whole outlined bar dropped a few px, so it shows under the
	-- ink outline rather than hiding inside it.
	blob(root, "BarShadow", { 0, L.shadowDrop, L.barW, L.barH }, INK, 2, ROUND, L.outline)
	local trough = blob(root, "Trough", { 0, 0, L.barW, L.barH }, STYLE.trough, 3, ROUND, L.outline)
	ui.punch = Instance.new("UIScale")
	ui.punch.Parent = trough

	-- The fill is white under a top-to-bottom gradient, with a glassy shine along its top.
	ui.fill = blob(trough, "Fill", { 0, 0, 0, L.barH }, WHITE, 4, ROUND)
	ui.fill.Size = UDim2.fromScale(0, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(STYLE.fillTop, STYLE.fillBottom)
	gradient.Rotation = 90
	gradient.Parent = ui.fill
	ui.shine = blob(ui.fill, "Shine", { 8, 5, 0, 9 }, WHITE, 5, ROUND)
	ui.shine.Size = UDim2.new(1, -16, 0, 9)
	ui.shine.BackgroundTransparency = 0.55

	ui.need = text(trough, "Need", { 0, 0, L.barW, L.barH }, {
		font = STYLE.valueFont,
		textSize = L.needTextSize,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 6,
	})

	ui.walk = text(root, "Walk", { 4, L.walkTop, L.barW - 8, 20 }, { textSize = 16 })
	ui.belt = text(root, "Belt", { 4, L.beltTop, L.barW - 8, 16 }, { textSize = 13, color = STYLE.caption })

	return root
end

local function ensure()
	if ui.panel == nil or ui.panel.Parent == nil then
		build()
	end
end

--- Repaint from the latest readout and the locally counted Speed. Every frame while the
--- bar is up, so the fill and the numbers run with the badge's counter. The bar is the
--- way to the next walk-speed point; levels stay internal and are never named here.
local function paint()
	local view = Speed.view()
	if view == nil or ui.panel == nil then
		return
	end
	local points = Speed.shownPoints()

	local progress = 1
	if view.level >= view.maxLevel then
		ui.walk.Text = `WALK SPEED {view.walk}  |  NOTHING LEFT TO TRAIN`
		ui.need.Text = `{Speed.format(points)} SPEED`
	else
		local from, to = view.current or 0, view.nextReq or 1
		progress = math.clamp((points - from) / math.max(to - from, 1), 0, 1)
		local eta = if view.rate > 0 then `  |  {view.walk + 1} IN {formatEta((to - points) / view.rate)}` else ""
		ui.walk.Text = `WALK SPEED {view.walk}{eta}`
		ui.need.Text = `{Speed.format(points)} / {Speed.format(to)}`
	end
	ui.fill.Size = UDim2.fromScale(progress, 1)
	-- The shine is inset 8 px each side, so a sliver of fill would turn it inside out.
	ui.shine.Visible = progress * LAYOUT.barW > 28

	ui.belt.Text = if view.nextName
		then string.upper(`{view.tierName}  |  next: {view.nextName} {formatCash(view.nextCost)} (+{view.nextRate}/s)`)
		else string.upper(`{view.tierName}  |  the fastest belt there is`)
end

-- ── The popups ────────────────────────────────────────────────────────────

--- Where the last "+10" floated from, so two in a row never land on one spot.
local lastGainX = math.huge

--- The centre of the next "+10", in the bar footprint's px: usually somewhere along
--- the air above the bar, sometimes off either end of it. Re-rolled (a few times at
--- most) when it lands within LAYOUT.gainGap of the last one.
local function gainSpot(): Vector2
	local L = LAYOUT
	local spot = Vector2.zero
	for _ = 1, 4 do
		local roll = math.random()
		local sideY = L.barH / 2 - 8 + 16 * math.random()
		if roll < 0.7 then
			spot = Vector2.new(L.barW * (0.08 + 0.84 * math.random()), -14 - 12 * math.random())
		elseif roll < 0.85 then
			spot = Vector2.new(L.barW + 52 + 16 * math.random(), sideY)
		else
			spot = Vector2.new(-52 - 16 * math.random(), sideY)
		end
		if math.abs(spot.X - lastGainX) >= L.gainGap then
			break
		end
	end
	lastGainX = spot.X
	return spot
end

--- Grow in, rise `rise` px over `life` seconds, fade out for the last stretch, then go.
--- Every text, its outline and every picture inside fades together.
local function float(popup: GuiObject, rise: number, life: number)
	local grow = Instance.new("UIScale")
	grow.Scale = 0.4
	grow.Parent = popup
	TweenService:Create(grow, PUNCH_TWEEN, { Scale = 1 }):Play()
	TweenService:Create(popup, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = popup.Position - UDim2.fromOffset(0, rise),
	}):Play()
	task.delay(life * 0.6, function()
		local parts = popup:GetDescendants()
		table.insert(parts, popup)
		for _, part in parts do
			if part:IsA("TextLabel") then
				TweenService:Create(part, FADE_TWEEN, { TextTransparency = 1 }):Play()
			elseif part:IsA("UIStroke") then
				TweenService:Create(part, FADE_TWEEN, { Transparency = 1 }):Play()
			elseif part:IsA("ImageLabel") then
				TweenService:Create(part, FADE_TWEEN, { ImageTransparency = 1 }):Play()
			end
		end
		task.wait(FADE_TWEEN.Time)
		popup:Destroy()
	end)
end

--- A shoe and "+10" floating off a random spot around the bar: one per Speed push.
local function popGain(amount: number)
	local L = LAYOUT
	local label = `+{Speed.format(amount)}`
	local textW = TextService:GetTextSize(label, L.gainTextSize, STYLE.valueFont, Vector2.new(400, 60)).X + 6
	local width = L.shoe + 2 + textW
	local spot = gainSpot()

	local popup = Instance.new("Frame")
	popup.Name = "GainPopup"
	popup.Size = UDim2.fromOffset(width, 32)
	popup.Position = UDim2.fromOffset(spot.X, spot.Y)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundTransparency = 1
	popup.ZIndex = 8
	popup.Parent = ui.panel

	local shoe = Artwork.picture(popup, "Shoe", Artwork.IMAGE.speedShoe, L.shoe, WHITE)
	shoe.Position = UDim2.fromOffset(0, (32 - L.shoe) / 2)
	shoe.ZIndex = 8
	text(popup, "Amount", { L.shoe + 2, 0, textW, 32 }, {
		font = STYLE.valueFont,
		textSize = L.gainTextSize,
		color = STYLE.gain,
		text = label,
		zIndex = 9,
	})
	float(popup, 30, 0.85)
end

--- The bar just filled: "WALK SPEED 35!" over its middle, and a punch on the bar.
local function popWalkUp(walk: number)
	local L = LAYOUT
	local popup = text(ui.panel, "WalkUpPopup", { L.barW / 2, -30, 360, 40 }, {
		font = STYLE.valueFont,
		textSize = 30,
		color = STYLE.walkUp,
		xAlign = Enum.TextXAlignment.Center,
		text = `WALK SPEED {walk}!`,
		stroke = 3.5,
		zIndex = 10,
	})
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Rotation = -6
	float(popup, 44, 1.6)

	ui.punch.Scale = 1.06
	TweenService:Create(ui.punch, PUNCH_TWEEN, { Scale = 1 }):Play()
end

local function show(visible: boolean)
	ensure()
	if ui.panel == nil or visible == shown then
		return
	end
	shown = visible
	if visible then
		paint()
		ui.panel.Visible = true
		ui.scale.Scale = 0.6
		TweenService:Create(ui.scale, POP_IN, { Scale = 1 }):Play()
	else
		-- Destroy nothing: the card comes back every time the player steps on, which
		-- for an AFK grind may be hundreds of times a session.
		TweenService:Create(ui.scale, POP_OUT, { Scale = 0 }):Play()
		task.delay(POP_OUT.Time, function()
			if not shown and ui.panel then
				ui.panel.Visible = false
			end
		end)
	end
end

-- ── The machine ───────────────────────────────────────────────────────────
--
-- EVERY BELT IN RANGE RUNS, ALL THE TIME. It used to scroll only the belt the local
-- player was training on; on request the tread now moves on every treadmill near the
-- camera, so a base reads as a working machine whether or not anyone is on it. Still
-- purely local and purely cosmetic -- the `Belt` part a service reads is never moved.

--- One belt, resolved into the terms the scroll needs, captured once per model:
---
---   travel   the belt's own +Z in WORLD space. Every plot in the ring is yawed to face
---            the centre, so there is no shared axis to hardcode.
---   start    the world point at the belt's -Z end, which distances are measured from.
---   length   the belt's own length, and therefore the period of the whole pattern.
---
--- Each chevron keeps `along` (how far down the belt it started) and `lateral` (its
--- offset across and above the belt, which never changes). Scrolling is then "advance
--- `along`, wrap it modulo `length`, rebuild the position" — the chevron cannot walk
--- off the end of the belt, because the wrap is in belt space.
---
--- IT IS NOT `home * CFrame.new(0, 0, -d)`. That offsets each part along its OWN axis,
--- and the two arms of a chevron are yawed ~53 degrees apart — so instead of the
--- pattern moving down the belt, every chevron slid apart into a diagonal streak.
type Machine = {
	slats: { { part: BasePart, home: CFrame, along: number, lateral: Vector3 } },
	rollers: { { part: BasePart, home: CFrame } },
	travel: Vector3,
	start: Vector3,
	length: number,
	centre: Vector3,
}

--- Resolved machines, by model. Weak keys: a plot rebuilt mid-session drops its old
--- model and this lets go of it.
local machines: { [Instance]: Machine } = setmetatable({}, { __mode = "k" }) :: any
--- The ones currently near enough to animate, refreshed every RANGE_REFRESH seconds.
local active: { Machine } = {}
local sinceRefresh = math.huge
--- How far the belt surface has run, unwrapped. One clock for every belt: they all
--- run at the same speed, so there is nothing per-machine to keep.
local travelled = 0

local function resolve(model: Instance): Machine?
	local belt = model:FindFirstChild("Belt", true)
	if belt == nil or not belt:IsA("BasePart") then
		return nil -- not streamed in yet, or a world built before the belt existed
	end
	-- LookVector is the part's -Z, so negating it gives the +Z the chevrons scroll
	-- toward: backwards under a runner who is facing -Z, which is the way a real belt
	-- moves. Size.Z is the long axis because the builder sizes it {width, _, length}.
	local travel = -belt.CFrame.LookVector
	local length = belt.Size.Z
	local start = belt.Position - travel * (length / 2)
	local machine: Machine = {
		slats = {},
		rollers = {},
		travel = travel,
		start = start,
		length = length,
		centre = belt.Position,
	}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if part.Name == "Slat" then
				local rel = part.Position - start
				local along = rel:Dot(travel)
				table.insert(machine.slats, { part = part, home = part.CFrame, along = along, lateral = rel - travel * along })
			elseif part.Name == "Roller" then
				table.insert(machine.rollers, { part = part, home = part.CFrame })
			end
		end
	end
	if #machine.slats == 0 then
		return nil -- slats still streaming in; try again on the next refresh
	end
	return machine
end

--- Re-pick the belts near the camera. Cheap (six plots), and twice a second is far
--- more often than anyone crosses ANIM_RANGE.
local function refreshActive()
	table.clear(active)
	local camera = Workspace.CurrentCamera
	local plots = Workspace:FindFirstChild("Plots")
	if camera == nil or plots == nil then
		return
	end
	local eye = camera.CFrame.Position
	for _, plot in plots:GetChildren() do
		local model = plot:FindFirstChild("Treadmill", true)
		if model == nil or model:GetAttribute("Locked") == true then
			continue -- a locked machine stands still until its owner buys it
		end
		local machine = machines[model]
		if machine and machine.slats[1].part.Parent == nil then
			machine = nil -- streamed out and back in as new parts; resolve them afresh
		end
		if machine == nil then
			machine = resolve(model)
			if machine == nil then
				continue
			end
			machines[model] = machine
		end
		if (machine.centre - eye).Magnitude <= ANIM_RANGE then
			table.insert(active, machine)
		end
	end
end

--- Run every chevron down its belt, wrapping at the far end, and turn the drums. The
--- rollers spin about their own long axis -- a Cylinder's axis is its local X, so the
--- turn is about X. The angle is rebuilt from `travelled` rather than accumulated onto
--- the CFrame, so it cannot drift, and at the belt's own surface speed the drum's top
--- moves with the tread.
---
--- `home.Rotation + position` keeps each arm's authored yaw and moves only where it
--- sits. The pattern is seamless because build/Plots lays the chevrons at a pitch
--- that divides the belt length exactly, so a chevron that wraps lands precisely
--- where its neighbour was.
local function animate(dt: number)
	sinceRefresh += dt
	if sinceRefresh >= RANGE_REFRESH then
		sinceRefresh = 0
		refreshActive()
	end
	if #active == 0 then
		return
	end
	travelled += BELT_SPEED * dt

	for _, machine in active do
		local offset = travelled % machine.length
		for _, slat in machine.slats do
			if slat.part.Parent == nil then
				continue -- streamed out under us; the next resolve picks up the new one
			end
			local along = (slat.along + offset) % machine.length
			slat.part.CFrame = slat.home.Rotation + (machine.start + machine.travel * along + slat.lateral)
		end
		for _, roller in machine.rollers do
			local radius = math.max(roller.part.Size.Y / 2, 0.05)
			roller.part.CFrame = roller.home * CFrame.Angles((travelled / radius) % (2 * math.pi), 0, 0)
		end
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
end

-- ── The walkthrough ──────────────────────────────────────────────────────

--- Start it once the player's own machine is this close and on screen. They have just
--- bought it at the console, so normally that is immediately.
local TUTORIAL_RANGE = 45
--- Walking this far off mid-way closes it, unmarked, so it comes back next visit.
local TUTORIAL_LEAVE = 70
local TUTORIAL_CHECK = 0.5

local tutorial: { stop: () -> () }? = nil
local tutorialDone = false
local tutorialPrompt: ProximityPrompt? = nil
local sinceTutorialCheck = 0
local actionRemote: any = nil

local function ownTreadmill(view: any): Instance?
	local plots = Workspace:FindFirstChild("Plots")
	local plot = plots and view.plot and plots:FindFirstChild(`Plot{view.plot}`)
	return plot and plot:FindFirstChild("Treadmill", true)
end

local function rootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function endTutorial(finished: boolean)
	tutorial = nil
	-- The console's prompt was held off so a stray E could not buy a belt mid-card.
	if tutorialPrompt then
		tutorialPrompt.Enabled = true
		tutorialPrompt = nil
	end
	if finished then
		tutorialDone = true
		actionRemote:FireServer({ action = "tutorialSeen", id = "treadmill" })
	end
end

local function checkTutorial()
	local view = Speed.view()
	local model = if view then ownTreadmill(view) else nil
	local look = model and model:FindFirstChild("Look")
	local console = model and model:FindFirstChild("Console")
	local here = rootPosition()

	if tutorial then
		if console == nil or here == nil or (here - (console :: BasePart).Position).Magnitude > TUTORIAL_LEAVE then
			tutorial.stop()
		end
		return
	end
	if tutorialDone or view == nil or view.tutorial ~= true then
		return
	end
	if look == nil or console == nil or not console:IsA("BasePart") or here == nil then
		return
	end
	local camera = Workspace.CurrentCamera
	local _, visible = camera:WorldToViewportPoint(console.Position)
	if (here - console.Position).Magnitude > TUTORIAL_RANGE or not visible then
		return
	end

	local hud = Players.LocalPlayer.PlayerGui:FindFirstChild("SpeedHud")
	local badge = hud and hud:FindFirstChild("SpeedBadge", true)
	local steps: { LockerTutorial.Step } = {
		{
			world = look,
			title = "YOUR TREADMILL",
			body = "Stand on the belt to train. Every second on it earns Speed, even while you're AFK.",
		},
	}
	if badge and badge:IsA("GuiObject") then
		table.insert(steps, {
			target = badge,
			title = "SPEED",
			body = "Your Speed adds up here. The more you have, the faster you walk, for good.",
		})
	end
	table.insert(steps, {
		world = console,
		title = "FASTER BELTS",
		body = "Press E at this screen to upgrade. Each belt earns Speed faster, and looks the part.",
	})

	local prompt = console:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = false
		tutorialPrompt = prompt
	end
	tutorial = LockerTutorial.run(steps, endTutorial)
end

-- ── Wiring ────────────────────────────────────────────────────────────────

function Treadmill.start()
	Players.LocalPlayer.CharacterAdded:Connect(onCharacter)
	actionRemote = Net.get("StationAction")

	Speed.onChanged(function(view, previous)
		local wasTraining = previous ~= nil and previous.training
		if view.training and not wasTraining then
			startRunning()
			show(true)
		elseif not view.training and wasTraining then
			stopRunning()
			show(false)
		end
		-- The popups belong to the bar, so they only fly while it is up.
		if shown and previous ~= nil then
			if view.level > previous.level then
				popWalkUp(view.walk)
			elseif view.points > previous.points + 0.5 then
				popGain(view.points - previous.points)
			end
		end
	end)

	-- One connection for the life of the session, and it does next to nothing unless a
	-- belt is near the camera or the card is up. Connecting and disconnecting per session
	-- would be the same work plus a leak the first time an edge is missed — and the
	-- client bootstrap never calls a `stop` on anything, so there would be nowhere
	-- honest to undo it.
	RunService.RenderStepped:Connect(function(dt)
		animate(dt)
		if shown then
			paint()
		end
		sinceTutorialCheck += dt
		if sinceTutorialCheck >= TUTORIAL_CHECK then
			sinceTutorialCheck = 0
			checkTutorial()
		end
	end)
end

return Treadmill
