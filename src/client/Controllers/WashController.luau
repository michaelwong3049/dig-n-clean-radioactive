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
	(ToolService.wanted) instead of being fought over.

	`HeldTool` is still accepted as a fallback target below, for a place file saved
	before the hose existed: aiming the old sponge is a worse picture than aiming a
	nozzle, but it is a much better one than a session that quietly does nothing.

	THE HOSE POINTS WHERE YOU AIM, and this is the second thing done entirely on the
	client rather than by touching the character's skeleton. The nozzle is welded to
	the right hand by a rigid, server-owned WeldConstraint ("HoldWeld", the same name
	and the same convention ToolService uses) -- fine for a thing you merely CARRY,
	wrong for one you are meant to point. Re-aiming the actual shoulder/elbow joints
	would mean reproducing
	ToolService's own dual-rig handling (Motor6D characters vs AnimationConstraint
	ones, see its header) purely for a cosmetic effect, and getting that wrong reads as
	a broken arm, not a held hose -- a much worse failure than "the hose doesn't track
	perfectly." So the arm is left alone, swinging on its normal walk/idle animation
	exactly as it always has, and only the TOOL gets a second, LOCAL joint: this file's
	own Motor6D from the same hand to the tool's own PrimaryPart, added on top of
	(never fighting) ToolService's weld -- the server's weld is merely disabled
	(`Enabled = false`) for the session and restored after, so the moment this session
	ends the tool snaps back to its ordinary carried pose with no cleanup surprises.
	A player's own character is client-simulated by default, which is what makes a
	disable done here actually stick locally instead of being fought by replication.

	THE SPRAY IS A ROPE OF PARTS, AND IT TOOK FOUR TRIES TO GET THERE. Each one was
	fixing something real about the last, so the whole ladder is worth keeping:

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
	is no such thing as a dark Beam. And "darker, so it is easier to see" is exactly
	what was asked for, over a bright base under a bright sky.

	So v4 is fourteen overlapping Cylinder PARTS laid along an arc from the muzzle
	to the target. Parts shade and occlude like everything else in the world, which
	means they can be genuinely dark, and a chain of them is a solid rope of water
	-- the one thing droplets alone could never be. Repositioning fourteen parts per
	frame is nothing next to the particle systems this replaced.

	COLOUR: THE LIQUID, PUSHED DOWN TOWARD BLACK. The old spray was tinted only
	faintly toward the liquid because real spray aerates and reads white -- true,
	and it produced something invisible against a pale steel tub. Every liquid in
	the catalogue is a light pastel (Config/Liquids), so the raw hue was no rescue
	either. Down is the only direction with contrast left in it. Each segment is
	then lifted slightly back toward white the further out it is, because a jet
	really does pick up air as it travels, and that gradient is what stops a solid
	rope reading as a bent pipe.

	NO HAND-ROLLED WOBBLE, still. An early version jittered the stream's endpoint on a
	sine wave to fake liveliness; it read as a broken aim rather than as moving water.
	The GAMEPLAY aim (which patch is being worked) is computed from the stable mouse
	ray, upstream of everything drawn here, and never sees any of it.
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

local SPRAY_RANGE = 40

-- How far the spray's colour leans toward the liquid's true hue: 0 = pure white,
-- 1 = the liquid's raw colour. The dense core (the jet and the droplets inside it)
-- carries most of it; the aerated haze, the splash and the drips stay nearly white,
-- which is both what real water does and what keeps a coloured liquid from reading as
-- poster paint. See the header.
-- The jet: a chain of overlapping cylinders laid along an arc from muzzle to target.
-- See the header for why it is parts rather than a Beam or a particle cone.
local JET_SEGMENTS = 14
-- How far the liquid's own colour is pushed toward black, and how far the far end is
-- then lifted back toward white for aeration. See applySprayColor.
local JET_DARKEN = 0.45
local JET_AERATION = 0.16
-- Segments are cut this much longer than the gap they span, so each buries the flat
-- end cap of the one before it. Below about 1.2 the rope reads as linked sausages.
local JET_OVERLAP = 1.35
local JET_WIDTH_NEAR = 0.3
local JET_WIDTH_FAR = 0.85
-- How high the arc's control point rides above the midpoint, as a fraction of the
-- distance travelled.
local JET_ARC = 0.13
local JET_TRANSPARENCY = 0.1

local state: any = nil
local blobs: { [number]: BasePart } = {}
local folder: Instance? = nil
local jetParts: { BasePart } = {}
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

--- Build the segment chain once. They are plain anchored cylinders parked at the
--- origin until the first frame of spraying moves them; nothing here needs to know
--- where the nozzle is yet.
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
--- and the gradient is what stops a solid rope reading as a bent pipe.
local function applySprayColor(hex: string)
	local dark = Color3.fromHex(hex):Lerp(Color3.new(0, 0, 0), JET_DARKEN)
	for index, part in jetParts do
		part.Color = dark:Lerp(Color3.new(1, 1, 1), JET_AERATION * (index / JET_SEGMENTS))
	end
end

--- Lay the chain along a quadratic Bezier from the nozzle to the target, with the
--- control point lifted above the midpoint -- water leaves the nozzle rising and
--- falls onto what it hits, and a dead-straight line between two points is the single
--- thing that most makes a jet look like a laser. The lift scales with the distance
--- so a two-stud shot does not droop like one thrown across the yard.
---
--- Segments are cut 35% LONGER than the gap they span, so consecutive cylinders
--- overlap and bury each other's flat end caps. Without that the rope is visibly a
--- string of sausages at every joint.
local function drawJet(from: Vector3, to: Vector3)
	local distance = (to - from).Magnitude
	local control = (from + to) / 2 + Vector3.new(0, distance * JET_ARC, 0)

	local function point(t: number): Vector3
		local u = 1 - t
		return from * (u * u) + control * (2 * u * t) + to * (t * t)
	end

	for index, part in jetParts do
		local a = point((index - 1) / JET_SEGMENTS)
		local b = point(index / JET_SEGMENTS)
		local span = (b - a).Magnitude
		if span < 0.01 then
			-- Degenerate: the player is aiming at their own muzzle. CFrame.lookAt with
			-- a zero direction returns garbage, so skip rather than scatter the chain.
			part.Transparency = 1
		else
			local width = JET_WIDTH_NEAR + (JET_WIDTH_FAR - JET_WIDTH_NEAR) * ((index - 0.5) / JET_SEGMENTS)
			part.Size = Vector3.new(span * JET_OVERLAP, width, width)
			-- A Cylinder's own axis is X and lookAt aims down -Z, so the extra yaw is
			-- what turns "pointing at b" into "lying along the segment".
			part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
			part.Transparency = JET_TRANSPARENCY
		end
	end
	jetShown = true
end

--- Cheap when already hidden, which is most frames of a session: the player aims far
--- more than they spray, and 14 property writes per frame to set a transparency that
--- is already 1 is 14 writes too many.
local function hideJet()
	if not jetShown then
		return
	end
	for _, part in jetParts do
		part.Transparency = 1
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

--- Which patch the player is pointing at: the reachable blob whose centre sits
--- closest to the aim ray. Nearest-to-ray rather than a raycast, because a 0.5-stud
--- ball at eight studs is a cruel thing to ask anyone to hit exactly.
local function aimAt(ray: Ray): number?
	local best: number? = nil
	local bestDistance = math.huge
	for index, blob in blobs do
		local toBlob = blob.Position - ray.Origin
		local along = toBlob:Dot(ray.Direction.Unit)
		if along > 0 and along < SPRAY_RANGE then
			local perpendicular = (toBlob - ray.Direction.Unit * along).Magnitude
			if perpendicular < bestDistance and perpendicular < 2.2 then
				best, bestDistance = index, perpendicular
			end
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
	local target = aimAt(aimRay)

	if target ~= aimedIndex then
		aimedIndex = target
		if inputRemote then
			inputRemote:FireServer({ spraying = spraying, patchIndex = aimedIndex })
		end
	end

	-- The one true aim point, shared by the hose rig and the beam below, so the
	-- nozzle is never visibly pointed anywhere other than where the stream lands.
	local blob = if aimedIndex then blobs[aimedIndex] else nil
	local hitPoint = if blob
		then blob.Position
		else aimRay.Origin + aimRay.Direction.Unit * 12

	-- Tracks the cursor continuously, spraying or not — a held hose reads as aimed
	-- the moment you look somewhere, same as a real one, not only while it is live.
	if aimMotor == nil then
		startAimRig()
	end
	updateAimRig(hitPoint)

	local nozzle = nozzleCFrame()
	if spraying and nozzle then
		drawJet(nozzle.Position, hitPoint)
	else
		hideJet()
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
