--[[
	StationMotionController.lua — the machines on a base doing something while you watch.

	The builders (build/Plots, via Kit.motion) stamp a `Motion` attribute and the
	"StationMotion" tag on anything that should move by itself:

	  spin     a Model or part turning steadily about its pivot's own axis -- the
	           treadmill cowl's fans, the ring of ticks round the wash pad's dial.
	  sway     a part wandering either side of rest about its pivot -- the pump gauge's
	           needle, which a pressure gauge that never twitches reads as a sticker.
	  ripples  rings spreading across a SurfaceGui laid over the tub's water.
	  screen   the stride-pulse bars on a treadmill console's readout.

	THIS FILE IS THE ONLY THING THAT MOVES THEM, AND IT ONLY EVER MOVES THEM HERE. Every
	part is anchored and server-built; the server never touches their CFrames and nothing
	about the animation crosses the wire. The rest pose is whatever the pivot was when
	the tag arrived, and everything is recomputed from that pose each frame rather than
	nudged, so nothing drifts over an AFK afternoon.

	CHEAP BY CONSTRUCTION. Only what is within NEAR of the camera animates, re-sorted a
	couple of times a second, and a spinning Model is one PivotTo.

	DISPLAYED NUKES ARE RATIONED. A `hover` nuke is 20-190 parts, and PivotTo moves
	every one of them each frame: a full three-floor base was 1,948 part moves and
	2.24 ms a frame on a dev PC, before the bases beside it. So only the nearest
	Config/ItemFx DETAIL fullBudget of them inside fullRange of the player turn and bob
	(the stands StandNukeController gives the full model); the rest hold their pose. The world streams
	(Workspace.StreamingEnabled), so tagged instances come and go: the builders stream
	each spinning Model atomically, a streamed-out one simply drops off the list, and a
	streamed-back one arrives at its server pose and is captured fresh. A world built
	before any of this existed has nothing tagged and stands still, which is the right
	way for it to be wrong.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFx = require(ReplicatedStorage.Shared.ItemFx)
local ItemFxConfig = require(ReplicatedStorage.Shared.Config.ItemFx)
local Prefs = require(script.Parent.Parent.Prefs)

local StationMotion = {}

--- Kit.MOTION_TAG. Kit is a server build module, so the string is spelled out here.
local MOTION_TAG = "StationMotion"

--- Studs from the camera inside which anything animates. The machines are a few studs
--- across; past this they are a handful of pixels and nobody can see a fan turn.
local NEAR = 90

--- Radians per second through the hover's bob (~4 s a cycle).
local HOVER_BOB_RATE = 1.5

--- Seconds between re-sorting what is near. Walking pace covers a couple of studs in
--- that time, which is nothing against NEAR.
local RESORT = 0.5

--- Ripples: how often a new ring starts, how long one lasts, how wide it grows (as a
--- fraction of the surface), and how many may be alive on one tub at once.
local RIPPLE = {
	gapMin = 0.45,
	gapMax = 1.1,
	life = 1.9,
	growMin = 0.28,
	growMax = 0.42,
	max = 5,
	stroke = 3,
	color = Color3.fromHex("F4FAFF"),
	startTransparency = 0.25,
}

--- The treadmill screen's pulse: how fast the bars wander and their floor height.
local PULSE_RATE = 2.6
local PULSE_FLOOR = 0.18

local AXES = {
	X = Vector3.xAxis,
	Y = Vector3.yAxis,
	Z = Vector3.zAxis,
}

type Entry = {
	target: Instance,
	kind: string,
	home: CFrame,
	axis: Vector3,
	rate: number,
	amp: number,
	seed: number,
	angle: number,
	-- hover: where the bob is in its cycle. Advances only while the entry animates,
	-- like `angle`, so a nuke that was held still carries on from where it stopped
	-- instead of jumping to wherever the clock says the bob should be.
	phase: number,
	nextRipple: number,
	rings: number,
}

local entries: { [Instance]: Entry } = {}
local active: { Entry } = {}
local sinceResort = math.huge
local rng = Random.new()

local function pivotOf(target: Instance): CFrame?
	if target:IsA("PVInstance") then
		return (target :: PVInstance):GetPivot()
	end
	return nil
end

local function register(target: Instance)
	local kind = target:GetAttribute("Motion")
	-- `MotionHome` when the owner gives one (StandNukeController): this runs deferred,
	-- after the frame that tagged the model, and by then a swapped-in copy has already
	-- been turned to match the one it replaced. Taking that as home turned it twice.
	local given = target:GetAttribute("MotionHome")
	local home = if typeof(given) == "CFrame" then given else pivotOf(target)
	if type(kind) ~= "string" or home == nil then
		return
	end
	local axisName = target:GetAttribute("MotionAxis")
	local amp = (target:GetAttribute("MotionAmp") :: number?) or 0.3
	-- Start from the pose it is actually in, so the first frame it animates doesn't
	-- snap it round. An owner swapping one copy for another passes the old copy's
	-- state (StationMotion.stateOf) as MotionAngle / MotionPhase.
	local angle = target:GetAttribute("MotionAngle") :: number?
	local phase = target:GetAttribute("MotionPhase") :: number?
	local pose = pivotOf(target)
	if kind == "hover" and pose then
		if angle == nil then
			local _, y, _ = (pose.Rotation * (home :: CFrame).Rotation:Inverse()):ToEulerAnglesYXZ()
			angle = y
		end
		if phase == nil then
			phase = math.asin(math.clamp((pose.Position.Y - (home :: CFrame).Position.Y) / math.max(amp, 1e-3), -1, 1))
		end
	end
	entries[target] = {
		target = target,
		kind = kind,
		home = home :: CFrame,
		axis = AXES[if type(axisName) == "string" then axisName else "Y"] or Vector3.yAxis,
		rate = (target:GetAttribute("MotionRate") :: number?) or 1,
		amp = amp,
		seed = rng:NextNumber(0, 1000),
		angle = angle or rng:NextNumber(0, math.pi * 2),
		phase = phase or rng:NextNumber(0, math.pi * 2),
		nextRipple = 0,
		rings = 0,
	}
	sinceResort = math.huge
end

local function unregister(target: Instance)
	entries[target] = nil
	sinceResort = math.huge
end

local function resort()
	table.clear(active)
	if Workspace.CurrentCamera == nil then
		return
	end
	local eye = ItemFx.viewerPosition()
	local detail = ItemFxConfig.DETAIL[Prefs.get("graphics")] or ItemFxConfig.DETAIL.med
	local hover = { range = detail.fullRange, budget = detail.fullBudget }
	local hovers: { { entry: Entry, distance: number } } = {}
	for target, entry in entries do
		if target.Parent == nil then
			continue
		end
		local distance = (entry.home.Position - eye).Magnitude
		if entry.kind == "hover" then
			if distance <= hover.range then
				table.insert(hovers, { entry = entry, distance = distance })
			end
		elseif distance <= NEAR then
			table.insert(active, entry)
		end
	end
	table.sort(hovers, function(a, b)
		return a.distance < b.distance
	end)
	for index = 1, math.min(#hovers, hover.budget) do
		table.insert(active, hovers[index].entry)
	end
end

--- A displayed nuke's pose: turned `angle` about world up through its pivot and bobbed
--- `amp` studs either side of rest at `phase` in the bob's cycle.
function StationMotion.hoverPose(home: CFrame, angle: number, phase: number, amp: number): CFrame
	return CFrame.new(home.Position + Vector3.new(0, math.sin(phase) * amp, 0)) * CFrame.Angles(0, angle, 0) * home.Rotation
end

--- A tagged hover model's current angle and bob phase, for an owner that replaces it
--- with another copy (StandNukeController) and wants the motion to carry straight on.
function StationMotion.stateOf(target: Instance): (number?, number?)
	local entry = entries[target]
	if entry == nil then
		return nil, nil
	end
	return entry.angle, entry.phase
end

local function turn(entry: Entry, angle: number)
	(entry.target :: PVInstance):PivotTo(entry.home * CFrame.fromAxisAngle(entry.axis, angle))
end

local function ripple(entry: Entry)
	local surface = entry.target:FindFirstChild("Ripples")
	if surface == nil or entry.rings >= RIPPLE.max then
		return
	end

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	-- Anywhere on the middle of the water. The rack's post stands in the centre, and a
	-- ring drawn over it just disappears into the post, which is what a real one does.
	ring.Position = UDim2.fromScale(rng:NextNumber(0.25, 0.75), rng:NextNumber(0.25, 0.75))
	ring.Size = UDim2.fromScale(0.03, 0.03)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = RIPPLE.color
	stroke.Thickness = RIPPLE.stroke
	stroke.Transparency = RIPPLE.startTransparency
	stroke.Parent = ring
	ring.Parent = surface

	local grow = rng:NextNumber(RIPPLE.growMin, RIPPLE.growMax)
	local info = TweenInfo.new(RIPPLE.life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = UDim2.fromScale(grow, grow) }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()

	entry.rings += 1
	task.delay(RIPPLE.life, function()
		ring:Destroy()
		entry.rings = math.max(entry.rings - 1, 0)
	end)
end

local function pulse(entry: Entry, now: number)
	local readout = entry.target:FindFirstChild("Readout")
	local bars = readout and readout:FindFirstChild("Pulse")
	if bars == nil then
		return
	end
	for index, bar in bars:GetChildren() do
		if bar:IsA("Frame") then
			-- Smooth noise per bar, so the row rolls like a level meter rather than
			-- flickering like static.
			local level = 0.5 + math.noise(now * PULSE_RATE, index * 0.37, entry.seed)
			local height = math.clamp(PULSE_FLOOR + (1 - PULSE_FLOOR) * level, PULSE_FLOOR, 1)
			bar.Size = UDim2.fromScale(bar.Size.X.Scale, height)
		end
	end
end

local function step(dt: number)
	-- Settings' GRAPHICS "low": pure decoration, so it simply holds still.
	if Prefs.get("graphics") == "low" then
		return
	end
	sinceResort += dt
	if sinceResort >= RESORT then
		sinceResort = 0
		resort()
	end

	local now = os.clock()
	for _, entry in active do
		if entry.target.Parent == nil then
			continue
		end
		local kind = entry.kind
		if kind == "spin" then
			entry.angle = (entry.angle + entry.rate * dt) % (math.pi * 2)
			turn(entry, entry.angle)
		elseif kind == "sway" then
			-- A wander, not a metronome: two octaves of noise, clamped to the swing.
			local wander = math.noise(now * entry.rate, entry.seed) + 0.4 * math.noise(now * entry.rate * 3.1, entry.seed + 17)
			turn(entry, math.clamp(wander * 1.6, -1, 1) * entry.amp)
		elseif kind == "hover" then
			-- A displayed nuke: a slow turn about world up through its pivot, plus a
			-- gentle bob of `amp` studs either side of rest (~4s period).
			entry.angle = (entry.angle + entry.rate * dt) % (math.pi * 2)
			entry.phase = (entry.phase + HOVER_BOB_RATE * dt) % (math.pi * 2);
			(entry.target :: PVInstance):PivotTo(StationMotion.hoverPose(entry.home, entry.angle, entry.phase, entry.amp))
		elseif kind == "ripples" then
			if now >= entry.nextRipple then
				entry.nextRipple = now + rng:NextNumber(RIPPLE.gapMin, RIPPLE.gapMax)
				ripple(entry)
			end
		elseif kind == "screen" then
			pulse(entry, now)
		end
	end
end

function StationMotion.start()
	for _, target in CollectionService:GetTagged(MOTION_TAG) do
		register(target)
	end
	CollectionService:GetInstanceAddedSignal(MOTION_TAG):Connect(register)
	CollectionService:GetInstanceRemovedSignal(MOTION_TAG):Connect(unregister)
	RunService.RenderStepped:Connect(step)
end

return StationMotion
