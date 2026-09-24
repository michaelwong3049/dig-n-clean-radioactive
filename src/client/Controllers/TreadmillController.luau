--[[
	TreadmillController.lua — the belt you are standing on, and what it is buying you.

	TWO JOBS, AND THEY ARE DELIBERATELY BOTH SMALL:

	  1. THE CARD. While you are training, a card above the hotbar shows your speed
	     level, the Speed you have against the next level's requirement, what the belt
	     pays per second, roughly how long until the next level, and what the next belt
	     costs. It pops in on arrival and out on departure. It is drawn from
	     SpeedController's copy of SpeedState — the same number the HUD badge counts, so
	     the two can never disagree — and computes no part of the curve itself.

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
	world billboard keeps showing its OWNER's level, exactly as the luck button shows
	its owner's multiplier, and the two never claim to be the same thing.

	THE RUN ANIMATION IS BORROWED, NOT AUTHORED. The id is read off the character's own
	`Animate` script at play time rather than hardcoded, so this cannot ship a broken
	asset reference and it automatically matches whatever rig (R6/R15) the player is on.
	If the script is not there — a custom rig, a future avatar change — the belt still
	scrolls and the card still works, and nobody sees an error. It is decoration, and
	decoration is not allowed to be load-bearing.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local UIKit = require(script.Parent.Parent.UIKit)
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

-- ── The card ──────────────────────────────────────────────────────────────

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

-- The speed badge's palette (SpeedController), so the card reads as the same system.
local STYLE = {
	card = Color3.fromHex("33AEFF"),
	cardShine = Color3.fromHex("8AD4FF"),
	pill = Color3.fromHex("2445B8"),
	trough = Color3.fromHex("123A7A"),
	fill = Color3.fromHex("FFE45C"),
	caption = Color3.fromHex("DDF3FF"),
	valueFont = Enum.Font.LuckiestGuy,
	bodyFont = Enum.Font.FredokaOne,
}

local CARD_W, CARD_H = 380, 122
local ROUND = UDim.new(0.5, 0)
local POP_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function formatCash(amount: number): string
	if amount >= 1_000_000 then
		return string.format("$%.1fM", amount / 1_000_000)
	elseif amount >= 1_000 then
		return string.format("$%.1fK", amount / 1_000)
	end
	return string.format("$%d", amount)
end

--- "45s", "3m 20s", "1h 05m" — how long the belt still has to run for the next level.
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
	return UIKit.label(parent, {
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
	-- column where the rad meter lives. An invisible footprint holds the card and its
	-- hard shadow, so one UIScale pops the lot.
	local root = Instance.new("Frame")
	root.Name = "Card"
	root.Size = UDim2.fromOffset(CARD_W, CARD_H + 5)
	root.Position = UDim2.new(0.5, 0, 1, -170)
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = canvas
	ui.panel = root
	ui.scale = Instance.new("UIScale")
	ui.scale.Parent = root

	local radius = UDim.new(0, 20)
	blob(root, "Shadow", { 0, 5, CARD_W, CARD_H }, INK, 1, radius)
	local card = blob(root, "Body", { 0, 0, CARD_W, CARD_H }, STYLE.card, 2, radius, 4)
	blob(card, "Shine", { 12, 6, CARD_W - 24, 12 }, STYLE.cardShine, 3, ROUND)

	ui.level = text(card, "Level", { 16, 10, 170, 38 }, { font = STYLE.valueFont, textSize = 34 })
	local stroke = ui.level:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 3.5
	end
	ui.walk = text(card, "Walk", { 18, 46, CARD_W - 36, 16 }, { textSize = 14, color = STYLE.caption })

	-- What the belt pays, on a pill in the top-right corner.
	local pill = blob(card, "RatePill", { CARD_W - 16 - 156, 14, 156, 30 }, STYLE.pill, 4, ROUND, 3)
	ui.rate = text(pill, "Rate", { 0, 0, 156, 30 }, { textSize = 17, xAlign = Enum.TextXAlignment.Center, zIndex = 6 })

	-- The bar to the next requirement, with the two numbers written across it.
	local trough = blob(card, "Trough", { 16, 66, CARD_W - 32, 24 }, STYLE.trough, 4, ROUND, 3)
	ui.fill = blob(trough, "Fill", { 0, 0, 0, 24 }, STYLE.fill, 5, ROUND)
	ui.fill.Size = UDim2.fromScale(0, 1)
	ui.need = text(trough, "Need", { 0, 0, CARD_W - 32, 24 }, { textSize = 15, xAlign = Enum.TextXAlignment.Center, zIndex = 6 })

	ui.belt = text(card, "Belt", { 18, 96, CARD_W - 36, 18 }, { textSize = 13, color = STYLE.caption })

	return root
end

local function ensure()
	if ui.panel == nil or ui.panel.Parent == nil then
		build()
	end
end

--- Repaint from the latest readout and the locally counted Speed. Every frame while the
--- card is up, so the bar and the numbers run with the badge's counter.
local function paint()
	local view = Speed.view()
	if view == nil or ui.panel == nil then
		return
	end
	local points = Speed.shownPoints()

	if view.level >= view.maxLevel then
		ui.level.Text = "MAX LV"
		ui.walk.Text = `WALK SPEED {view.walk}  |  NOTHING LEFT TO TRAIN`
		ui.fill.Size = UDim2.fromScale(1, 1)
		ui.need.Text = `{Speed.format(points)} SPEED`
	else
		local from, to = view.current or 0, view.nextReq or 1
		local progress = math.clamp((points - from) / math.max(to - from, 1), 0, 1)
		ui.level.Text = `LV {view.level}`
		local eta = if view.rate > 0 then `  |  LV {view.level + 1} IN {formatEta((to - points) / view.rate)}` else ""
		ui.walk.Text = `WALK SPEED {view.walk}{eta}`
		ui.fill.Size = UDim2.fromScale(progress, 1)
		ui.need.Text = `{Speed.format(points)} / {Speed.format(to)}`
	end

	ui.rate.Text = `+{view.rate} SPEED/S`
	ui.belt.Text = if view.nextName
		then string.upper(`{view.tierName}  |  next: {view.nextName} {formatCash(view.nextCost)} (+{view.nextRate}/s)`)
		else string.upper(`{view.tierName}  |  the fastest belt there is`)
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
		if model == nil then
			continue
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

-- ── Wiring ────────────────────────────────────────────────────────────────

function Treadmill.start()
	Players.LocalPlayer.CharacterAdded:Connect(onCharacter)

	Speed.onChanged(function(view, previous)
		local wasTraining = previous ~= nil and previous.training
		if view.training and not wasTraining then
			startRunning()
			show(true)
		elseif not view.training and wasTraining then
			stopRunning()
			show(false)
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
	end)
end

return Treadmill
