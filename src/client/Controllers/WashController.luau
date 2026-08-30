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

	GREEN, AND YES, DELIBERATELY. Kit.C's palette header says nothing outside a stage
	may use Neon in the hazard greens, so that "glowing green" only ever means the
	ooze. A contamination patch is the SAME SUBSTANCE — PLAN §2 step 4 calls them
	"glowing hotspots" and they are literally the fallout you are hosing off — so
	painting them any other colour would be the actual dilution of that rule, not the
	respect of it. The exception is narrow and stays narrow: client-local, only ever
	visible during a session you opted into, and never on world geometry.

	THE SPRAY IS CLIENT-LOCAL, which is against ToolService's "what you hold is public
	storytelling" rule. Defensible only because every cleansing station sits on its
	owner's own base, so there is no bystander to tell the story to — and the ITEM on
	the tub is server-side (WashService) precisely so the part that IS worth seeing
	from outside is seen. Written down so nobody re-derives it.

	THE HOSE POINTS WHERE YOU AIM, and this is the second thing done entirely on the
	client rather than by touching the character's skeleton. The equipped Cleaner tool
	is already welded to the right hand by ToolService (a rigid, server-owned
	WeldConstraint, "HoldWeld") -- fine for every OTHER tool, wrong for one you are
	meant to point. Re-aiming the actual shoulder/elbow joints would mean reproducing
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

	THE SPRAY IS PARTICLES NOW, NOT A Beam. The first version drew one thin, mostly
	transparent line from nozzle to target — accurate, and nothing like water: real
	spray has no edge, it is a cone of droplets that gets denser near the source and
	scatters into a visible splash wherever it lands. A single Beam cannot be both of
	those things at once, so it read as "a laser, dimmed" rather than "a hose."

	TWO ParticleEmitters, both parented to the SAME two Attachments the old Beam used
	(`SprayOrigin` at the nozzle, `SprayHit` at the target), so all the existing
	per-frame position tracking carries over unchanged:

	    stream   a narrow, forward-firing cone from the nozzle. `Speed` is recomputed
	             every frame from the live nozzle-to-target distance divided by the
	             emitter's own `Lifetime`, so droplets emitted THIS frame still land
	             roughly on target even as the player's aim moves.
	    splash   a wide, near-omnidirectional burst at the impact point, facing back
	             toward the nozzle. This is what the stream's own travel cannot sell —
	             the moment of hitting something — and it is what makes the target end
	             of the spray read as "landing" rather than "stopping."

	Both are tinted toward WHITE, not the liquid's raw hue. Real water sprays read as
	white/translucent even when what is in the tank has colour — aeration and light
	scattering wash it out — and matching that is what makes this look like water
	instead of a jet of paint. `Liquids.get(id).color` still shows up on the wash
	pad's own sign and the corner badge, which is where "which liquid is this"
	actually needs to be legible; the spray itself only needs a faint tint, blended in
	at PARTICLE_TINT toward the true hue so a Molten Lava spray still reads warm and a
	Nano-Foam one still reads cool, without either looking like solid dye.

	NO HAND-ROLLED WOBBLE ANY MORE. A real particle cone is already organic — each
	droplet's own random spread and lifetime does what the old sine-wave endpoint hack
	was trying to fake with one line. The GAMEPLAY aim (which patch is being worked)
	is still computed from the stable mouse ray, upstream of any of this, and never
	sees anything the particles do.
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

-- How far the spray's own colour leans toward the liquid's true hue, 0 = pure white,
-- 1 = the liquid's raw colour. See the header on why this stays low.
local PARTICLE_TINT = 0.30
-- Every stream particle is given this Lifetime (seconds); Speed is derived from it
-- each frame so newly-emitted droplets still roughly reach the current target.
local STREAM_LIFETIME = NumberRange.new(0.22, 0.3)

local state: any = nil
local blobs: { [number]: BasePart } = {}
local folder: Instance? = nil
local streamEmitter: ParticleEmitter? = nil
local splashEmitter: ParticleEmitter? = nil
local originAttach: Attachment? = nil
local hitAttach: Attachment? = nil
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

--- The forward jet, firing out of `originAttach`'s own orientation (its LookVector,
--- i.e. `EmissionDirection = Front`) — which onRender keeps pointed at the current
--- target, so the cone always fires the right way with no extra math here.
local function makeStreamEmitter(parent: Instance): ParticleEmitter
	local made = Instance.new("ParticleEmitter")
	made.Name = "Stream"
	-- Texture LEFT AT ENGINE DEFAULT, deliberately. rbxasset:// paths for the built-in
	-- particle textures are not something this session could verify render correctly
	-- (a wrong guess renders as the WRONG SHAPE, not as an error), and the default
	-- ParticleEmitter texture is guaranteed to exist and to read as a soft round
	-- droplet, which is exactly what a water spray needs.
	made.EmissionDirection = Enum.NormalId.Front
	made.Rate = 140
	made.Lifetime = STREAM_LIFETIME
	-- Speed is overwritten every frame in onRender against the live target distance;
	-- this is just a sane resting value before the first frame runs.
	made.Speed = NumberRange.new(14, 18)
	made.SpreadAngle = Vector2.new(4, 4)
	made.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.14),
		NumberSequenceKeypoint.new(0.6, 0.26),
		NumberSequenceKeypoint.new(1, 0.16),
	})
	made.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.85, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	made.Acceleration = Vector3.new(0, -22, 0)
	made.LightEmission = 0.15
	made.LightInfluence = 0
	made.Enabled = false
	made.Parent = parent
	return made
end

--- The impact burst. Wide SpreadAngle so it scatters rather than continuing the
--- stream's own narrow cone — this is the part of the reference image the stream
--- alone cannot sell: the moment of actually hitting something.
local function makeSplashEmitter(parent: Instance): ParticleEmitter
	local made = Instance.new("ParticleEmitter")
	made.Name = "Splash"
	-- Same reasoning as the stream emitter above: engine default texture.
	made.EmissionDirection = Enum.NormalId.Front
	made.Rate = 70
	made.Lifetime = NumberRange.new(0.15, 0.32)
	made.Speed = NumberRange.new(3, 8)
	made.SpreadAngle = Vector2.new(65, 65)
	made.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(1, 0.03),
	})
	made.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	made.Acceleration = Vector3.new(0, -38, 0)
	made.LightEmission = 0.15
	made.LightInfluence = 0
	made.Enabled = false
	made.Parent = parent
	return made
end

local function ensureSpray()
	if streamEmitter and streamEmitter.Parent and splashEmitter and splashEmitter.Parent then
		return
	end
	local parent = ensureFolder()

	local originPart = Instance.new("Part")
	originPart.Name = "SprayOrigin"
	originPart.Size = Vector3.new(0.1, 0.1, 0.1)
	originPart.Transparency = 1
	originPart.Anchored = true
	originPart.CanCollide = false
	originPart.Parent = parent
	originAttach = Instance.new("Attachment")
	originAttach.Parent = originPart
	streamEmitter = makeStreamEmitter(originAttach)

	local hitPart = Instance.new("Part")
	hitPart.Name = "SprayHit"
	hitPart.Size = Vector3.new(0.1, 0.1, 0.1)
	hitPart.Transparency = 1
	hitPart.Anchored = true
	hitPart.CanCollide = false
	hitPart.Parent = parent
	hitAttach = Instance.new("Attachment")
	hitAttach.Parent = hitPart
	splashEmitter = makeSplashEmitter(hitAttach)
end

--- Both emitters read as WATER, not as the liquid itself — see the header. Blended
--- toward the liquid's hue by PARTICLE_TINT rather than snapped to it outright.
local function applySprayColor(hex: string)
	local tinted = Color3.new(1, 1, 1):Lerp(Color3.fromHex(hex), PARTICLE_TINT)
	local sequence = ColorSequence.new(tinted)
	if streamEmitter then
		streamEmitter.Color = sequence
	end
	if splashEmitter then
		splashEmitter.Color = sequence
	end
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
	streamEmitter, splashEmitter, originAttach, hitAttach = nil, nil, nil, nil

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
			blob.Material = Enum.Material.Neon
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
		blob.Material = if patch.blocked then Enum.Material.Slate else Enum.Material.Neon
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
	local tool = character:FindFirstChild("HeldTool")
	if tool == nil or not tool:IsA("Model") or tool.PrimaryPart == nil then
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
	if aimHand.Parent == nil or aimMotor.Parent == nil or aimTool == nil or aimTool.Parent == nil then
		-- The tool changed under us (a mid-wash Cleaner upgrade, most likely) and
		-- took this rig's Parent with it. Clear our half; the next call to
		-- startAimRig rebuilds against whatever is equipped now.
		aimMotor, aimHand, aimTool, aimOffset, aimHoldWeld = nil, nil, nil, nil, nil
		return
	end

	local origin = aimHand.CFrame:PointToWorldSpace(aimOffset)
	local aimCFrame = if (target - origin).Magnitude > 0.05
		then CFrame.lookAt(origin, target)
		else CFrame.new(origin) * aimHand.CFrame.Rotation
	aimMotor.C1 = aimCFrame:Inverse() * aimHand.CFrame
end

--- The hose muzzle. The Cleaner models are hand-authored and gitignored
--- (ARCHITECTURE.md's "remaining gap"), so they have a PrimaryPart but almost
--- certainly no muzzle point. Prefer a `Nozzle` attachment if one is ever added in
--- Studio; fall back to the front face of the model's own primary part, then to the
--- hand. No code change needed the day the attachment appears.
local function nozzleCFrame(): CFrame?
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil
	end
	local tool = character:FindFirstChild("HeldTool")
	if tool and tool:IsA("Model") and tool.PrimaryPart then
		local nozzle = tool.PrimaryPart:FindFirstChild("Nozzle")
		if nozzle and nozzle:IsA("Attachment") then
			return nozzle.WorldCFrame
		end
		return tool.PrimaryPart.CFrame * CFrame.new(0, 0, -tool.PrimaryPart.Size.Z * 0.5)
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
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

	if streamEmitter and splashEmitter and originAttach and hitAttach then
		local nozzle = nozzleCFrame()
		local show = spraying and nozzle ~= nil
		streamEmitter.Enabled = show
		splashEmitter.Enabled = show
		if show and nozzle then
			-- The stream fires along originAttach's own forward axis (EmissionDirection
			-- = Front on the emitter, set once at creation), so pointing the ATTACHMENT
			-- at the target is the whole job -- no per-particle direction math here.
			originAttach.WorldCFrame = CFrame.lookAt(nozzle.Position, hitPoint)

			-- Speed is distance/lifetime, recomputed every frame, so a droplet emitted
			-- THIS frame still lands close to a target that may be moving (a tracked
			-- patch) or may have just gotten farther or nearer as the player re-aims.
			local distance = (hitPoint - nozzle.Position).Magnitude
			local lifetime = (STREAM_LIFETIME.Min + STREAM_LIFETIME.Max) / 2
			local speed = math.clamp(distance / lifetime, 4, 60)
			streamEmitter.Speed = NumberRange.new(speed * 0.9, speed * 1.1)

			-- The splash faces back toward the nozzle, so its wide cone scatters
			-- generally away from the surface it hit -- the same "bounced off the
			-- barrel toward camera" read the reference splash has.
			hitAttach.WorldCFrame = CFrame.lookAt(hitPoint, nozzle.Position)
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
