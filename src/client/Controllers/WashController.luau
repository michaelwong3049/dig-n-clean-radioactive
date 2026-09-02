--[[
	WashController.lua — the wash bay, rendered. Camera, blobs, and the stream.

	THE SERVER OWNS EVERYTHING THAT COUNTS. This file reports aim and intent — "I am
	spraying, at patch 3" — and draws whatever WashState comes back. It never decides
	that a patch came off. That is the same boundary the old scrub timer had
	(ARCHITECTURE.md, "Server/client boundary"), and it is why a modified client can
	pick a different patch to work on (which it could always do by clicking a different
	row) but cannot clean an Anomaly instantly.

	THE CAMERA MUST COME BACK ON EVERY PATH, and this is the one thing in here that is
	genuinely dangerous. A player stuck in a Scriptable camera has no way out short of
	rejoining. Sessions end six ways: finishing, pressing E at the tub again, pressing
	Q, walking out of the leash, the item leaving the bag, and a respawn. All of them
	arrive here as the same thing — a nil WashState — and `stop()` is idempotent, so it
	does not matter how many times or in what order they land. CharacterAdded also
	calls it blind, because a respawn mid-wash is the one case where no remote fires.

	THE FIRST VERSION HAD NO EXIT AT ALL, and it shipped that way. Walking out of the
	leash was the only end condition, and the server pins WalkSpeed to 0 for the
	duration — so the single way out was the single thing the player could not do. Two
	were added: E and Q, both checked before `gameProcessedEvent` so no GUI can
	swallow them.

	BOTH ARE KEYBOARD, AND NEITHER GOES THROUGH THE PROMPT, on purpose and on a second
	pass. The first attempt reused the SAME ProximityPrompt that starts the session as
	the "press E again" exit — discoverable, since it is the same button that got you
	in, but wrong: Roblox's default prompt widget can also be fired by a MOUSE CLICK on
	its own icon, and this session is spent clicking, to spray, often toward wherever
	that icon renders once the camera cuts to the side-on shot. Aiming the hose was
	accidentally re-triggering "leave." WashService now disables that prompt for the
	whole session, and E/Q here are the only way out — keyboard, not mouse, so nothing
	about where you are aiming can end the session by accident.

	THE SHOT IS SIDE-ON, framed from a WashCam anchor off to the left of a WashSpot the
	player is planted on (build/Plots). The first version framed from in FRONT of the
	tub, which put the camera roughly where the player was standing: you saw a tub
	filling the screen, no character, and no hose. You are meant to see yourself in
	profile holding the hose with the item across from you and the stream crossing
	between the two.

	PATCH BLOBS ARE PLACED DETERMINISTICALLY, from the patch's index through a
	golden-angle spiral. They have to be: WashState arrives at 10 Hz, and blobs placed
	with math.random would swarm over the item like flies. Same index in, same point
	on the item out, every tick.

	GREEN, AND YES, DELIBERATELY. A contamination patch is the SAME SUBSTANCE as the
	ooze — PLAN §2 step 4 calls them "glowing hotspots" and they are literally the
	fallout you are hosing off — so it wears the ooze's own green (Kit.C.oozeBright),
	matte like every surface in the world since the de-neon pass. Painting it any other
	colour would break the "this is the fallout" read.

	THE SPRAY IS CLIENT-LOCAL, which is against ToolService's "what you hold is public
	storytelling" rule. Defensible only because every cleansing station sits on its
	owner's own base, so there is no bystander to tell the story to — and the ITEM on
	the tub is server-side (WashService) precisely so the part that IS worth seeing
	from outside is seen. Written down so nobody re-derives it.

	WHAT IS ACTUALLY IN THE PLAYER'S HAND IS A FIRE HOSE, and it is a real object that
	the server put there: `WashHose`, a copy of the nozzle parked on the pump beside
	the tub (build/Plots.buildHoseRig), welded into the right hand by WashService for
	the length of the session, with the reel's own green Beam running back to the drum.
	This file does not create it and does not own it — it only POINTS it. That split is
	why the hose is visible to everyone on the base while the spray is not, and it is
	why the ordinary Cleaner tool steps out of that hand for the duration
	(see its stepPlayer) instead of being fought over.

	`HeldTool` is still accepted as a fallback target below, for a place file saved
	before the hose existed: aiming the old sponge is a worse picture than aiming a
	nozzle, but it is a much better one than a session that quietly does nothing.

	THE HOSE POINTS WHERE YOU AIM, and this is done entirely on the client rather
	than by touching the character's skeleton. The nozzle is welded to the right hand
	by a rigid, server-owned WeldConstraint ("HoldWeld", the same name and the same
	convention ToolService uses) -- fine for a thing you merely CARRY, wrong for one
	you are meant to point. So the tool gets a second, LOCAL joint: a Motor6D from
	the same hand to the nozzle's own PrimaryPart, added on top of (never fighting)
	the server's weld, which is merely disabled (`Enabled = false`) for the session
	and restored after -- so the moment this session ends the nozzle snaps back to its
	ordinary carried pose with no cleanup surprises. A player's own character is
	client-simulated by default, which is what makes a disable done here stick
	locally instead of being fought by replication.

	THE ARMS ARE POSED, BUT NOT BY THIS FILE. Aiming only the nozzle used to leave it
	hanging off an arm still swinging through its idle walk cycle -- the nozzle
	pointed at the item while the hand it was welded to drifted around, which reads as
	a prop stuck to a mannequin. Posing is server-side and ToolService already owns it
	(it braces the whole upper body for the detector, on a rig-agnostic weld scheme
	that handles both Motor6D and AnimationConstraint characters). It braces for the
	hose too, from its own `isWashing` check, so both hands come up onto the nozzle
	and the arm stops moving under it. That leaves this file rotating a nozzle held in
	a hand that is genuinely still, which is the whole reason the aim reads now.

	THE SPRAY IS A ROPE OF PARTS ON A BALLISTIC ARC, AND IT TOOK FIVE TRIES. Each one
	fixed something real about the last, so the whole ladder is worth keeping:

	v1 drew ONE thin, mostly transparent Beam from nozzle to target. It read as "a
	laser, dimmed", so the Beam came out and particles went in: real spray has no
	edge, it is a cone of droplets that scatters into a splash where it lands.

	v2 was those particles -- a stream cone, a muzzle haze, an impact splash and
	run-off drips. Physically that is what a hose does. On screen it was a fog of
	little dots that obscured the item being washed and never resolved into a
	stream, and the report was exactly that: get rid of the dots, leave the stream.

	v3 went back to Beams, two of them, on the theory that v1 failed for being ONE
	flat nearly-transparent ribbon rather than for being a Beam -- a wide dark shell
	with a pale core inside it to fake the shading a camera-facing ribbon cannot
	have. It did not work, and the reason is a hard fact about the engine rather
	than a tuning miss: A BEAM RENDERS ADDITIVELY. Its colour is ADDED to whatever
	is behind it, so a Beam can only ever brighten the scene. Darkening the shell
	from 0.42 to 0.55 to 0.62 toward black changed nothing on screen, because there
	is no such thing as a dark Beam -- and "darker, so it is easier to see" is what
	was asked for, over a bright base under a bright sky.

	v4 was the same shape drawn as PARTS, which do shade and occlude and therefore
	can be dark. That fixed the colour, and left two things still reading as
	machinery. It was a fixed-proportion Bezier -- the sag was always the same
	fraction of the distance, so the arc never behaved like something falling. And
	the far end was SNAPPED to whichever contamination blob was nearest the cursor,
	so the stream jumped from patch to patch as the mouse moved, going where the
	game had decided you meant rather than where you were pointing.

	v5, below, is a real flight. The water leaves the nozzle at a fixed speed toward
	the point the cursor's raycast found, falls under gravity for the whole way, and
	stops on the first surface it touches. A long shot therefore sags more than a
	short one because it is in the air longer, which is the cue that reads as weight.
	Nothing snaps: aim is aim. And which patch is being cleaned is decided by where
	the water LANDS, which is the only rule a player would guess from watching it.

	COLOUR: THE LIQUID, PUSHED DOWN TOWARD BLACK. The old spray was tinted only
	faintly toward the liquid because real spray aerates and reads white -- true,
	and it produced something invisible against a pale steel tub. Every liquid in
	the catalogue is a light pastel (Config/Liquids), so the raw hue was no rescue
	either. Down is the only direction with contrast left in it. Each segment is
	then lifted slightly back toward white the further out it is, because a jet
	really does pick up air as it travels, and that gradient is what stops a solid
	rope reading as a bent pipe.

	THE WOBBLE IS NOISE, NOT RANDOM, and an early version got this wrong in the
	other direction. It jittered the stream's ENDPOINT on a sine wave to fake
	liveliness, which read as a broken aim rather than as moving water. What is here
	instead leaves the endpoint alone and displaces the path in between, sampled from
	math.noise at (distance along the jet - time) so the same ripple travels outward
	from the nozzle; a fresh math.random offset every frame would be static, not
	flow. It fades to nothing at the muzzle, because water leaves a nozzle coherent
	and breaks up as it goes, and wobble at the muzzle just reads as a loose grip.

]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local Wash = {}

-- Kit.C.oozeBright. Duplicated rather than required because build/ lives in
-- ServerScriptService and a client cannot reach it — the same reason Tuning.AURA_TAG
-- exists as a shared constant. If the ooze is ever retuned, this follows it.
local PATCH_GREEN = Color3.fromHex("6BEE2E")
local PATCH_CRUSTED = Color3.fromHex("3A3128")

-- How far a patch may sit from where the water actually lands and still be the one
-- being worked. Generous, because the player is aiming a falling arc at a half-stud
-- ball -- see `patchAt`.
local PATCH_REACH = 2.8
-- How far the aim ray reaches into the world, and where the aim point goes when it
-- reaches nothing at all (open sky past the edge of the base).
local AIM_RANGE = 60
local AIM_FALLBACK = 16

-- The jet: a chain of overlapping cylinders laid along the water's real flight path.
-- See the header for why it is parts rather than a Beam or a particle cone.
local JET_SEGMENTS = 16
-- How far the liquid's own colour is pushed toward black, and how far the far end is
-- then lifted back toward white for aeration. See applySprayColor.
local JET_DARKEN = 0.45
local JET_AERATION = 0.16
-- Segments are cut this much longer than the gap they span, so each buries the flat
-- end cap of the one before it. Below about 1.2 the rope reads as linked sausages.
local JET_OVERLAP = 1.4
local JET_WIDTH_NEAR = 0.3
local JET_WIDTH_FAR = 0.85
local JET_TRANSPARENCY = 0.1
-- Studs per second the water leaves the nozzle at. The flight time -- and so how far
-- the arc sags -- falls out of this against the distance to the aim point, which is
-- the whole reason the jet droops more the further you point it.
local JET_SPEED = 26
-- Studs per second squared. Roblox's own gravity is 196.2, which over a wash bay's
-- couple of studs of flight is a vertical drop nobody would read as an arc; this is
-- the value that makes the sag legible at this scale. Not physics, staging.
local JET_GRAVITY = 46
-- Turbulence. `JET_WOBBLE` is how far a mid-jet segment may wander off the ideal
-- path, in studs, and `JET_CHURN` how fast that wander scrolls along the stream. Both
-- fade to nothing at the nozzle -- water leaves a nozzle coherent and breaks up as it
-- travels, and wobble at the muzzle just reads as a loose grip.
local JET_WOBBLE = 0.16
local JET_CHURN = 3.4
-- The splash disc where the water lands: diameter, and how much of that it breathes.
local SPLASH_SIZE = 1.5
local SPLASH_PULSE = 0.28

local state: any = nil
local blobs: { [number]: BasePart } = {}
local folder: Instance? = nil
local jetParts: { BasePart } = {}
local splashPart: BasePart? = nil
local jetShown = false
local spraying = false
local aimedIndex: number? = nil
local renderBound = false

-- The hose-aim rig (see the header). All five reset together, in stopAimRig, and are
-- (re)built lazily from onRender rather than once at session start -- self-healing if
-- the equipped tool changes mid-wash (a mid-session Cleaner upgrade swaps the model,
-- which destroys the old HoldWeld and this rig right along with it as its children).
local aimMotor: Motor6D? = nil
local aimHand: BasePart? = nil
local aimTool: Model? = nil
local aimOffset: Vector3? = nil
local aimHoldWeld: WeldConstraint? = nil

local inputRemote: any = nil

-- ── Geometry helpers ────────────────────────────────────────────────

local function itemPivot(): (CFrame?, Vector3?)
	local stand = state and state.stand
	if stand == nil or not stand:IsA("BasePart") then
		return nil, nil
	end
	local item = stand:FindFirstChild("WashItem")
	if item == nil then
		-- The server places it; on the very first tick it may not have replicated yet.
		return stand.CFrame, Vector3.new(1.4, 1.4, 1.4)
	end
	if item:IsA("BasePart") then
		return item.CFrame, item.Size
	end
	if item:IsA("Model") then
		local cf, size = item:GetBoundingBox()
		return cf, size
	end
	return stand.CFrame, Vector3.new(1.4, 1.4, 1.4)
end

--- A stable point on the item's surface for patch `index`. Golden-angle spiral over
--- a sphere, scaled to the item's own bounding box, so patches spread evenly and
--- land in the same place every tick regardless of how many are left.
local function patchPoint(index: number, pivot: CFrame, size: Vector3): Vector3
	local golden = 2.39996323
	local t = (index - 0.5) / 8 -- 8, not #patches: removing one must not move the rest
	local y = 1 - 2 * math.min(t, 1)
	local radius = math.sqrt(math.max(0, 1 - y * y))
	local theta = golden * index
	local dir = Vector3.new(math.cos(theta) * radius, y, math.sin(theta) * radius)
	local extent = (size * 0.5) + Vector3.new(0.12, 0.12, 0.12)
	return (pivot * CFrame.new(dir * extent)).Position
end

-- ── Build / tear down ───────────────────────────────────────────────

local function clearBlobs()
	for _, blob in blobs do
		blob:Destroy()
	end
	table.clear(blobs)
end

local function ensureFolder(): Instance
	if folder == nil or folder.Parent == nil then
		local made = Instance.new("Folder")
		made.Name = "WashBayFX"
		made.Parent = Workspace
		folder = made
	end
	return folder :: Instance
end

--- Build the segment chain and the splash disc once. They are plain anchored parts
--- parked at the origin until the first frame of spraying moves them; nothing here
--- needs to know where the nozzle is yet.
local function ensureSpray()
	if #jetParts == JET_SEGMENTS and jetParts[1].Parent ~= nil then
		return
	end
	local parent = ensureFolder()
	table.clear(jetParts)
	for index = 1, JET_SEGMENTS do
		local part = Instance.new("Part")
		part.Name = `Jet{index}`
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = parent
		jetParts[index] = part
	end

	local splash = Instance.new("Part")
	splash.Name = "Splash"
	splash.Shape = Enum.PartType.Cylinder
	splash.Material = Enum.Material.SmoothPlastic
	splash.Transparency = 1
	splash.Anchored = true
	splash.CanCollide = false
	splash.CanQuery = false
	splash.CastShadow = false
	splash.Parent = parent
	splashPart = splash

	jetShown = false
end

--- The liquid's own colour, pushed DOWN toward black.
---
--- The old spray was tinted only faintly toward the liquid, on the reasoning that
--- real spray aerates and reads white. True, and the result over a bright base under
--- a bright sky was something you could not see at all. Every liquid in the catalogue
--- is a light pastel (Config/Liquids), so the raw hue was never going to rescue it
--- either -- these are all about as bright as the tub they are being sprayed into.
--- Down toward black is the only direction with contrast left in it.
---
--- Each segment is then lifted slightly back toward white the further from the
--- nozzle it is: a jet picks up air as it travels, so the far end really is paler,
--- and the gradient is what stops a solid rope reading as a bent pipe. The splash
--- goes further still, because the water at an impact is all foam.
local function applySprayColor(hex: string)
	local dark = Color3.fromHex(hex):Lerp(Color3.new(0, 0, 0), JET_DARKEN)
	for index, part in jetParts do
		part.Color = dark:Lerp(Color3.new(1, 1, 1), JET_AERATION * (index / JET_SEGMENTS))
	end
	if splashPart then
		splashPart.Color = dark:Lerp(Color3.new(1, 1, 1), 0.45)
	end
end

--- WHERE THE WATER ACTUALLY GOES, and this is the part that stopped it looking like
--- a machine. The stream used to be a fixed-shape curve drawn between the muzzle and
--- whichever contamination blob was nearest the cursor -- so the far end SNAPPED from
--- patch to patch as you moved the mouse, and the curve's sag was a constant fraction
--- of the distance rather than anything to do with falling.
---
--- This is a real ballistic flight instead. The water leaves the nozzle at JET_SPEED
--- along whatever direction is needed to reach the aim point in the time that speed
--- allows, and then falls at JET_GRAVITY for the rest of the way:
---
---     to = from + v*T + 0.5*g*T^2        solved for v, with T = distance / SPEED
---
--- Two things fall out of that for free. A far shot has a longer flight time, so it
--- sags visibly more than a near one -- which is exactly the cue that reads as "this
--- is water and it is heavy". And the aim point is a plain raycast into the world, so
--- the stream lands where the player is pointing and nowhere else; nothing snaps.
---
--- Gravity here is NOT Workspace.Gravity. At 196.2 over a wash bay's few studs the
--- drop is a couple of inches -- correct, and invisible. This is staging, tuned until
--- the arc reads.
local function jetPath(from: Vector3, to: Vector3, now: number): { Vector3 }
	local delta = to - from
	local flight = math.max(delta.Magnitude / JET_SPEED, 0.05)
	local gravity = Vector3.new(0, -JET_GRAVITY, 0)
	local launch = (delta - gravity * 0.5 * flight * flight) / flight

	-- Sideways axes to wobble in. Any pair perpendicular to the flight will do; these
	-- are just the ones that stay stable as the player sweeps the nozzle around.
	local forward = if delta.Magnitude > 0.01 then delta.Unit else Vector3.new(0, 0, -1)
	local side = forward:Cross(Vector3.new(0, 1, 0))
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.new(1, 0, 0)
	local up = side:Cross(forward).Unit

	local path = table.create(JET_SEGMENTS + 1)
	for index = 0, JET_SEGMENTS do
		local fraction = index / JET_SEGMENTS
		local t = flight * fraction
		local point = from + launch * t + gravity * (0.5 * t * t)

		-- TURBULENCE, SCROLLING ALONG THE STREAM. math.noise rather than math.random:
		-- a fresh random offset every frame is static, not water. Sampling smooth noise
		-- at (position along the jet - time) makes the same wave travel outward from the
		-- nozzle, which is what moving water looks like. Scaled by `fraction` so the
		-- muzzle end stays coherent and the break-up grows with distance.
		local churn = fraction * JET_WOBBLE
		point += side * (math.noise(fraction * 3.1 - now * JET_CHURN, 0.5) * churn)
		point += up * (math.noise(0.5, fraction * 3.1 - now * JET_CHURN) * churn)

		path[index + 1] = point
	end
	return path
end

--- Lay the chain along `path`, stopping at whatever the water hits first.
---
--- Segments are cut 40% LONGER than the gap they span, so consecutive cylinders
--- overlap and bury each other's flat end caps. Without that the rope is visibly a
--- string of sausages at every joint.
---
--- Returns the point the water actually reached -- the impact if it hit something,
--- the end of the arc if it did not. That point, not the cursor, is what decides
--- which patch is being worked (see `patchAt`): you are cleaning what the water is
--- landing on, which is the only rule a player would ever guess.
local function drawJet(from: Vector3, to: Vector3, filter: RaycastParams): Vector3
	local now = os.clock()
	local path = jetPath(from, to, now)
	local landing = path[#path]
	local stopped = false

	for index, part in jetParts do
		local a, b = path[index], path[index + 1]
		local span = (b - a).Magnitude

		if stopped or span < 0.01 then
			-- Either the water already hit something, or the player is aiming at their
			-- own muzzle: CFrame.lookAt on a zero direction returns garbage.
			part.Transparency = 1
		else
			-- Segment by segment, so the stream stops ON the surface it hits rather than
			-- passing through the tub and out the far side. One short ray per segment is
			-- the same total length as one long ray down the arc, and a straight ray
			-- cannot follow a curve.
			local hit = Workspace:Raycast(a, b - a, filter)
			local tip = if hit then hit.Position else b
			local reach = (tip - a).Magnitude
			if hit then
				landing = hit.Position
				stopped = true
			end

			if reach < 0.01 then
				part.Transparency = 1
			else
				local width = JET_WIDTH_NEAR + (JET_WIDTH_FAR - JET_WIDTH_NEAR) * ((index - 0.5) / JET_SEGMENTS)
				-- The overlap is only safe on segments that run the full span; a segment
				-- cut short by an impact would otherwise poke out the back of the wall.
				local length = if hit then reach else reach * JET_OVERLAP
				part.Size = Vector3.new(length, width, width)
				-- A Cylinder's own axis is X and lookAt aims down -Z, so the extra yaw is
				-- what turns "pointing at the next point" into "lying along the segment".
				part.CFrame = CFrame.lookAt(a + (tip - a) * 0.5, tip) * CFrame.Angles(0, math.rad(90), 0)
				part.Transparency = JET_TRANSPARENCY
			end
		end
	end

	-- The splash. One breathing disc laid flat against whatever was hit, not a burst of
	-- particles -- the particles were the thing that had to go. It matters more than it
	-- sounds: without it the stream ends at a hard flat cylinder cap, and the eye reads
	-- that as the water STOPPING in mid-air rather than as it landing on something.
	local splash = splashPart
	if splash then
		if stopped then
			local size = SPLASH_SIZE * (1 + SPLASH_PULSE * math.noise(now * 6, 0.5))
			splash.Size = Vector3.new(0.08, size, size)
			splash.CFrame = CFrame.lookAt(landing, landing + (from - landing).Unit) * CFrame.Angles(0, math.rad(90), 0)
			splash.Transparency = 0.35
		else
			splash.Transparency = 1
		end
	end

	jetShown = true
	return landing
end

--- Cheap when already hidden, which is most frames of a session: the player aims far
--- more than they spray, and a chain of writes to set a transparency that is already
--- 1 is a chain of writes too many.
local function hideJet()
	if not jetShown then
		return
	end
	for _, part in jetParts do
		part.Transparency = 1
	end
	if splashPart then
		splashPart.Transparency = 1
	end
	jetShown = false
end

--- Undo startAimRig, restoring the tool to ToolService's own carried pose. Safe to
--- call when the rig was never built (every field is already nil) and safe to call
--- when the tool it was built on is already gone (Destroy() on a freed Instance is a
--- no-op, never an error).
local function stopAimRig()
	if aimMotor then
		aimMotor:Destroy()
	end
	if aimHoldWeld then
		aimHoldWeld.Enabled = true
	end
	aimMotor, aimHand, aimTool, aimOffset, aimHoldWeld = nil, nil, nil, nil, nil
end

--- Idempotent on purpose — see the header. Every exit path calls this, sometimes
--- more than once, sometimes when no session was ever running.
local function stop()
	state = nil
	spraying = false
	aimedIndex = nil

	clearBlobs()
	stopAimRig()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(jetParts)
	splashPart = nil
	jetShown = false

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

-- ── Render ──────────────────────────────────────────────────────────

local function paintBlobs()
	if state == nil then
		return
	end
	local pivot, size = itemPivot()
	if pivot == nil or size == nil then
		return
	end

	local live: { [number]: boolean } = {}
	for _, patch in state.patches do
		live[patch.index] = true

		local blob = blobs[patch.index]
		if blob == nil or blob.Parent == nil then
			blob = Instance.new("Part")
			blob.Name = `Patch{patch.index}`
			blob.Shape = Enum.PartType.Ball
			blob.Anchored = true
			blob.CanCollide = false
			blob.CanQuery = false
			blob.Material = Enum.Material.SmoothPlastic
			blob.Parent = ensureFolder()
			blobs[patch.index] = blob
		end

		-- Harder patches are bigger, so "which one is the wall" is legible before you
		-- ever aim at it. A blocked patch is crusted and matte — the stream visibly
		-- does nothing to it, which is the Quarantine Locker taught in 3D.
		local base = 0.30 + patch.hardness * 0.07
		local scale = base
		if patch.index == state.targetIndex and (state.progress or 0) > 0 then
			scale = base * (1 - 0.65 * state.progress)
		end

		blob.Size = Vector3.new(scale, scale, scale) * 2
		blob.Position = patchPoint(patch.index, pivot, size)
		blob.Color = if patch.blocked then PATCH_CRUSTED else PATCH_GREEN
		blob.Material = if patch.blocked then Enum.Material.Slate else Enum.Material.SmoothPlastic
		blob.Transparency = if patch.blocked then 0.1 else 0.15
	end

	for index, blob in blobs do
		if not live[index] then
			blob:Destroy()
			blobs[index] = nil
		end
	end
end

-- ── The hose-aim rig ─────────────────────────────────────────────────

--- The thing in the player's right hand to point. `WashHose` is the fire hose
--- WashService welds there for the session (build/Plots.buildHoseRig); `HeldTool` is
--- the fallback for a place file saved before the hose existed — see the header.
--- Returns nil while the weld is still catching up, which is normal on the first
--- frame or two and is why every caller re-asks rather than caching.
local function heldHose(): Model?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end
	local held = character:FindFirstChild("WashHose") or character:FindFirstChild("HeldTool")
	if held == nil or not held:IsA("Model") or held.PrimaryPart == nil then
		return nil
	end
	return held
end

--- Build the second, LOCAL joint from hand to tool -- see the header. Cheap to call
--- every frame the rig is missing: it does nothing when the tool is not there yet
--- (equip is still catching up) or already there (nothing to build twice).
local function startAimRig()
	if aimMotor then
		return
	end
	local character = Players.LocalPlayer.Character
	if character == nil then
		return
	end
	local tool = heldHose()
	if tool == nil or tool.PrimaryPart == nil then
		return
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if hand == nil or not hand:IsA("BasePart") then
		return
	end

	-- Disable, never destroy, ToolService's own weld. Destroying it would delete the
	-- server's record of how to carry this tool the moment the wash ends; disabling
	-- is what makes `stopAimRig` a clean, total restore.
	local existing = tool.PrimaryPart:FindFirstChild("HoldWeld")
	if existing and existing:IsA("WeldConstraint") then
		aimHoldWeld = existing
		aimHoldWeld.Enabled = false
	end

	-- The tool's CURRENT carried position, relative to the hand, at the moment
	-- aiming starts. Kept fixed for the rest of the session so the tool orbits that
	-- one point in the player's grip rather than drifting -- only its ROTATION
	-- changes as the aim moves, matching how a person actually holds a hose.
	aimOffset = hand.CFrame:PointToObjectSpace(tool.PrimaryPart.Position)
	aimHand = hand
	aimTool = tool

	local motor = Instance.new("Motor6D")
	motor.Name = "WashAim"
	motor.Part0 = hand
	motor.Part1 = tool.PrimaryPart
	motor.Parent = tool.PrimaryPart
	aimMotor = motor
end

--- Point the tool at `target`. Motor6D enforces `Part1.CFrame = Part0.CFrame * C0 *
--- C1:Inverse()`; with C0 left at the default identity, solving for the C1 that
--- makes Part1.CFrame equal the CFrame we actually want reduces to
--- `C1 = desired:Inverse() * Part0.CFrame`. Recomputed every frame because Part0 (the
--- hand) is still animating normally underneath this the whole time.
local function updateAimRig(target: Vector3)
	if aimMotor == nil or aimHand == nil or aimOffset == nil then
		return
	end
	if aimHand.Parent == nil or aimMotor.Parent == nil or aimTool == nil or aimTool.Parent == nil or aimTool ~= heldHose() then
		-- The tool changed under us and took this rig's Parent with it, or a better
		-- candidate turned up in the hand. Both happen for real: the fire hose and the
		-- Cleaner it displaces replicate independently at the start of a session, so
		-- the first frame or two can rig the sponge before the hose arrives. Clear our
		-- half; the next call to startAimRig rebuilds against whatever is there now.
		-- Through stopAimRig rather than by clearing the fields, so a tool that is
		-- still ALIVE (the displaced Cleaner) gets its own weld switched back on
		-- instead of being left hanging off a hand it is no longer jointed to.
		stopAimRig()
		return
	end

	local origin = aimHand.CFrame:PointToWorldSpace(aimOffset)
	local aimCFrame = if (target - origin).Magnitude > 0.05
		then CFrame.lookAt(origin, target)
		else CFrame.new(origin) * aimHand.CFrame.Rotation
	aimMotor.C1 = aimCFrame:Inverse() * aimHand.CFrame
end

--- Where the water leaves. The fire hose carries a real `Muzzle` attachment on its
--- primary part, sat out at the brass tip (build/Plots.buildHoseRig), so the stream
--- starts at the end of the nozzle rather than somewhere inside the player's fist.
---
--- The two fallbacks below are for the `HeldTool` case: the Cleaner models are
--- hand-authored and gitignored (ARCHITECTURE.md's "remaining gap") and have no
--- muzzle point of their own, so the front face of their primary part is the best
--- guess available, and the hand is the last resort.
local function nozzleCFrame(): CFrame?
	local tool = heldHose()
	if tool and tool.PrimaryPart then
		local muzzle = tool.PrimaryPart:FindFirstChild("Muzzle")
		if muzzle and muzzle:IsA("Attachment") then
			return muzzle.WorldCFrame
		end
		return tool.PrimaryPart.CFrame * CFrame.new(0, 0, -tool.PrimaryPart.Size.Z * 0.5)
	end
	local character = Players.LocalPlayer.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if hand and hand:IsA("BasePart") then
		return hand.CFrame
	end
	return nil
end

--- What the player is pointing AT, in the world -- a plain raycast from the cursor.
---
--- This used to return a patch index, and the aim point was then snapped to that
--- patch's blob. That is what made the stream jump from blob to blob as the mouse
--- moved: the water was not going where you pointed, it was going where the game had
--- decided you meant. Aim is now just aim.
---
--- The blobs and the jet segments are all CanQuery = false, so this never hits the
--- effects themselves -- it finds the ITEM under the blob, which is where the
--- contamination is anyway. The character is filtered out because the ray starts
--- behind the player's own shoulder.
local function aimPointAt(ray: Ray, filter: RaycastParams): Vector3
	local hit = Workspace:Raycast(ray.Origin, ray.Direction.Unit * AIM_RANGE, filter)
	if hit then
		return hit.Position
	end
	return ray.Origin + ray.Direction.Unit * AIM_FALLBACK
end

--- Which patch is being worked: the one nearest to where the water actually LANDS.
---
--- Not nearest to the cursor, and the difference is the whole point. The stream is a
--- falling arc that stops at the first thing it touches, so the cursor and the impact
--- are genuinely different places -- and "you are cleaning what you are hitting" is
--- the only rule a player would ever guess from watching it. PATCH_REACH is generous
--- because a half-stud ball at eight studs, hit with a ballistic arc, is a cruel thing
--- to ask anyone to be exact about.
local function patchAt(point: Vector3): number?
	local best: number? = nil
	local bestDistance = PATCH_REACH
	for index, blob in blobs do
		local distance = (blob.Position - point).Magnitude
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

local function onRender()
	if state == nil then
		return
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	-- The camera anchor is a part in the station, so framing is tuned in Studio
	-- against live geometry rather than by editing numbers here.
	local stand = state.stand
	local anchor = if stand and stand.Parent then stand.Parent:FindFirstChild("WashCam") else nil
	if anchor and anchor:IsA("BasePart") then
		camera.CFrame = anchor.CFrame
	end

	paintBlobs()

	-- ScreenPointToRay, NOT ViewportPointToRay. GetMouseLocation() returns a point
	-- that INCLUDES the topbar inset, and ViewportPointToRay expects one that does
	-- not — pairing those two puts the aim ray ~36px above the cursor, which reads as
	-- the hose being subtly, maddeningly miscalibrated.
	local mouse = UserInputService:GetMouseLocation()
	local aimRay = camera:ScreenPointToRay(mouse.X, mouse.Y)

	-- Rebuilt per frame rather than cached: the character is respawnable and the folder
	-- is destroyed on every stop(), so a stale filter would either miss the character
	-- or hold a reference to a freed instance.
	local filter = RaycastParams.new()
	filter.FilterType = Enum.RaycastFilterType.Exclude
	filter.FilterDescendantsInstances = { Players.LocalPlayer.Character :: any, folder :: any }

	local aimPoint = aimPointAt(aimRay, filter)

	-- Tracks the cursor continuously, spraying or not — a held hose reads as aimed
	-- the moment you look somewhere, same as a real one, not only while it is live.
	if aimMotor == nil then
		startAimRig()
	end
	updateAimRig(aimPoint)

	-- The jet reports back where it landed, which is not the aim point whenever the
	-- falling arc clips something on the way. That impact, not the cursor, is what
	-- picks the patch.
	local nozzle = nozzleCFrame()
	local landing = aimPoint
	if spraying and nozzle then
		landing = drawJet(nozzle.Position, aimPoint, filter)
	else
		hideJet()
	end

	local target = patchAt(landing)
	if target ~= aimedIndex then
		aimedIndex = target
		if inputRemote then
			inputRemote:FireServer({ spraying = spraying, patchIndex = aimedIndex })
		end
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────

local function beginSession()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	ensureSpray()
	applySprayColor(state.liquidColor or "6FD5E8")

	if not renderBound then
		RunService:BindToRenderStep("WashBay", Enum.RenderPriority.Camera.Value + 1, onRender)
		renderBound = true
	end
end

function Wash.start()
	inputRemote = Net.get("WashInput")

	Net.get("WashState").OnClientEvent:Connect(function(payload)
		if payload == nil then
			if renderBound then
				RunService:UnbindFromRenderStep("WashBay")
				renderBound = false
			end
			stop()
			return
		end

		local fresh = state == nil
		state = payload
		if fresh then
			beginSession()
		else
			-- The loaded liquid can change mid-wash: run a canister dry and you drop
			-- back to Plain Water, and the spray has to say so.
			applySprayColor(payload.liquidColor or "6FD5E8")
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if state == nil then
			return
		end

		-- THE ESCAPE HATCH, and it is checked BEFORE `processed` on purpose. Every
		-- other input here is a game action that a GUI is entitled to swallow; "let me
		-- out" is not. Being stuck in a Scriptable camera with the character pinned in
		-- place is unrecoverable short of rejoining, so the way out must not depend on
		-- no other UI happening to be under the cursor.
		--
		-- E AND Q, BOTH KEYBOARD-ONLY, NEITHER ROUTED THROUGH THE PROMPT ANY MORE.
		-- The prompt that started this session is disabled server-side for its whole
		-- duration (WashService.begin) precisely because Roblox's default prompt
		-- widget can ALSO be fired by a mouse click on its own icon -- and this session
		-- is spent clicking, to spray, often toward wherever that icon would have
		-- rendered once the camera cut to the side-on shot. E is kept as the
		-- discoverable exit (same key that got you in); Q is the one that works even
		-- if a player never associates E with "leave" once they are staring at a hose.
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
			inputRemote:FireServer({ stop = true })
			return
		end

		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			spraying = true
			inputRemote:FireServer({ spraying = true, patchIndex = aimedIndex })
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			spraying = false
			if state ~= nil then
				inputRemote:FireServer({ spraying = false, patchIndex = aimedIndex })
			end
		end
	end)

	-- A respawn mid-wash fires no remote at all: the server's leash check sees a
	-- character with no root and ends the session silently. This is the only thing
	-- standing between that and a player left in a Scriptable camera.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		if renderBound then
			RunService:UnbindFromRenderStep("WashBay")
			renderBound = false
		end
		stop()
	end)
end

return Wash
