--[[
	WashController.lua — the wash bay, rendered. First person, down the hose.

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
	arrive here as the same thing — a nil WashState — and `teardown()` is idempotent,
	so it does not matter how many times or in what order they land. CharacterAdded
	also calls it blind, because a respawn mid-wash is the one case where no remote
	fires.

	THE FIRST VERSION HAD NO EXIT AT ALL, and it shipped that way. Walking out of the
	leash was the only end condition, and the server pins WalkSpeed to 0 for the
	duration — so the single way out was the single thing the player could not do. Two
	were added: E and Q, both checked before `gameProcessedEvent` so no GUI can
	swallow them.

	BOTH ARE KEYBOARD, AND NEITHER GOES THROUGH THE PROMPT, on purpose and on a second
	pass. The first attempt reused the SAME ProximityPrompt that starts the session as
	the "press E again" exit — discoverable, since it is the same button that got you
	in, but wrong: Roblox's default prompt widget can also be fired by a MOUSE CLICK on
	its own icon, and this session is spent clicking, to spray. WashService now
	disables that prompt for the whole session, and E/Q here are the only way out —
	keyboard, not mouse, so nothing about where you are aiming can end the session by
	accident.

	── THE SHOT ──────────────────────────────────────────────────────────

	THE SHOT IS FIRST PERSON, FROM THE PLAYER'S OWN HEAD, and that is the second
	answer to this question. The first was a fixed SIDE-ON shot framed from a WashCam
	anchor out to the left of the tub: you watched your own character in profile
	holding the hose, with the item across from them and the stream crossing between
	the two. It composed well and it was the wrong picture, because the thing being
	asked of the player is AIM — and aim is not something you do while watching
	yourself from thirteen studs away. You aim down the hose.

	So the camera now sits at the character's Head, the base direction is a straight
	line from there to the item on the stand, and the mouse moves the VIEW rather than
	a cursor. The nozzle rises into the bottom of the frame out of the player's own
	braced hands (posed server-side, see below), the decon station fills the space
	around it, and the reticle marks where the water is going to land.

	THE LOOK IS CLAMPED, and the clamp is the whole reason the body does not have to
	turn with it. Yaw and pitch are offsets from "pointing at the item", held inside
	±32° and ±26° — enough to look over the whole station, nowhere near enough to end
	up staring at the sky with a hose you can no longer see. The alternative was to
	rotate the character's root to follow the view so the nozzle stays glued to the
	middle of the frame like an FPS weapon; that means writing CFrame to a
	physics-simulated character every frame, for a problem the clamp already solves.
	Inside that cone the hands never leave the bottom of the shot.

	WashCam IS STILL BUILT AND IS STILL READ, as the fallback for exactly one frame
	that genuinely happens: the head is gone (a respawn is landing) and the session has
	not been told yet. A camera frozen wherever it was last is worse than an
	unflattering angle, so that frame gets the old side-on shot.

	THE CUT IS HIDDEN BEHIND A WIPE, both ways. A panel sweeps in from the left, and at
	the instant it covers the screen — and only then — the camera changes. It keeps
	going and slides off the right edge to reveal the new shot. Leaving the bay runs
	the identical sweep with the identical hand-off in the middle, so the trip back to
	the ordinary over-the-shoulder camera is never seen either. Two halves of one
	motion: the first accelerates, the second decelerates, which is what makes it read
	as a single push rather than as two slides.

	THE WIPE IS DECORATION AND THE CUT IT HIDES IS NOT, which is the rule the whole
	transition is built around. `leave()` fires the real teardown from the middle of
	the sweep AND schedules it again unconditionally a beat later, because a player
	left in a Scriptable camera with WalkSpeed pinned at zero has no way out short of
	rejoining. Deferring a restore into an animation callback is exactly how someone
	ends up stranded; `teardown` being idempotent makes calling it twice the cheapest
	possible insurance.

	THE HEAD HAS TO GO, AND IT HAS TO GO AGAIN EVERY FRAME. Roblox's own
	TransparencyController (PlayerModule) runs at RenderPriority.Camera — one step
	ahead of this file — and unconditionally writes LocalTransparencyModifier on every
	character part it has cached. A single write at session start is stamped back to
	zero on the very next frame, and the player spends the wash looking at the inside
	of their own skull. Re-asserting it from `onRender`, which is bound at Camera + 1,
	is what makes it stick. Only the head and its accessories: the ARMS stay, because
	they are holding the nozzle and they are most of what makes this read as first
	person at all.

	Camera.Focus is set for the same reason and is not decoration either. That same
	controller measures the gap between CFrame and Focus to decide how see-through to
	make the local character, and a Focus left sitting on top of the camera dissolves
	the arms and the hose along with the head.

	── THE FURNITURE ─────────────────────────────────────────────────────

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
	and the arm stops moving under it. That is what puts the grip at chest height and
	the nozzle in the bottom of a first-person frame instead of down by a hip.

	THE SPRAY IS A CHAIN OF BLOBS ON A BALLISTIC ARC, AND IT TOOK SIX TRIES. Each one
	fixed something real about the last, so the whole ladder is worth keeping:

	v1 drew ONE thin, mostly transparent Beam from nozzle to target. It read as "a
	laser, dimmed", so the Beam came out and particles went in: real spray has no
	edge, it is a cone of droplets that scatters into a splash where it lands.

	v2 was those particles -- a stream cone, a muzzle haze, an impact splash and
	run-off drips. Physically that is what a hose does. On screen it was a fog of
	little dots that obscured the item being washed and never resolved into a
	stream, and the report was exactly that: get rid of the dots, leave the stream.

	v3 went back to Beams, two of them, on the theory that v1 failed for being ONE
	flat nearly-transparent ribbon rather than for being a Beam. It did not work,
	and the reason is a hard fact about the engine rather than a tuning miss: A BEAM
	RENDERS ADDITIVELY. Its colour is ADDED to whatever is behind it, so a Beam can
	only ever brighten the scene. Darkening the shell from 0.42 to 0.55 to 0.62
	toward black changed nothing on screen, because there is no such thing as a dark
	Beam -- and "darker, so it is easier to see" is what had been asked for.

	v4 was the same shape drawn as PARTS, which do shade and occlude and therefore
	can be dark. That fixed the colour and left two things reading as machinery: the
	sag was a fixed fraction of the distance, so the arc never behaved like something
	falling, and the far end SNAPPED to whichever contamination blob was nearest the
	cursor, going where the game had decided you meant.

	v5 made it a real flight -- fixed launch speed, gravity for the rest of the way,
	stopping on the first surface it touches. That is still how it moves.

	v6, below, is the cartoon pass, and it is two changes. The cylinders became
	BALLS: a chain of overlapping spheres has no flat end caps to show at the joints,
	needs no orientation solved per segment, and gives the soft round silhouette that
	drawn water has. And the colour came back up -- see applySprayColor. What was
	there before was a dark, naturalistic, slightly translucent stream in a world of
	bright matte primaries, which is exactly the "looks weird" that prompted this: it
	did not look bad, it looked like it belonged in a different game.

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

local UIKit = require(script.Parent.Parent.UIKit)

local Wash = {}

-- Kit.C.oozeBright. Duplicated rather than required because build/ lives in
-- ServerScriptService and a client cannot reach it — the same reason Tuning.AURA_TAG
-- exists as a shared constant. If the ooze is ever retuned, this follows it.
local PATCH_GREEN = Color3.fromHex("6BEE2E")
local PATCH_CRUSTED = Color3.fromHex("3A3128")

-- Plain Water, and the only place this file needs a liquid colour of its own: the
-- wipe can start a frame before a payload has been read.
local DEFAULT_LIQUID = "6FD5E8"

-- How far a patch may sit from where the water actually lands and still be the one
-- being worked. Generous, because the player is aiming a falling arc at a half-stud
-- ball -- see `patchAt`.
local PATCH_REACH = 2.8
-- How far the aim ray reaches into the world, and where the aim point goes when it
-- reaches nothing at all (open sky past the edge of the base).
local AIM_RANGE = 60
local AIM_FALLBACK = 16

-- ── The first-person shot ───────────────────────────────────────────
-- Studs the camera sits forward of the head's own centre, along the view. The head is
-- hidden anyway, so this is not about escaping it -- it is about not being able to see
-- the inside of your own shoulders when you pitch all the way down.
local EYE_FORWARD = 0.4
-- Narrower than the default 70. A wash is close work and the item is a stud and a
-- half across; this is a gentle lean-in that makes the patches bigger targets without
-- cropping the station out of the frame around them.
local WASH_FOV = 60
-- How far off "pointing at the item" the player may look, in each axis. See the
-- header for why this is a clamp rather than a body that turns.
local YAW_LIMIT = math.rad(32)
local PITCH_LIMIT = math.rad(26)
-- Radians per pixel of mouse travel, and radians per second at full thumbstick.
local MOUSE_SENS = 0.0032
local PAD_SENS = math.rad(115)
local PAD_DEADZONE = 0.16
-- Where Camera.Focus is parked, in studs ahead. Never allowed to collapse onto the
-- camera -- see the header on TransparencyController.
local FOCUS_AHEAD = 8
-- WHERE THE NOZZLE HANGS, in the neutral view's own axes: +X right, +Y up, -Z
-- forward. See startAimRig for why the hose is placed in the picture rather than
-- simply left wherever the carried pose put it.
--
-- MEASURED, NOT GUESSED. Against the live shot the carried pose landed the muzzle at
-- 10% right / 43% down of the half-frame, covering 34% of the screen's height -- on
-- top of an item that only covers 29%, dead centre. This puts it at 32% right / 66%
-- down at 32% of the height: a viewmodel in the lower-right corner, no bigger than
-- the thing it is being pointed at. The trade-off is a straight line -- pushing it
-- further out shrinks it but drags it back toward the middle, because everything
-- converges on the centre with distance -- and this is the knee of it. It also keeps
-- the nozzle within a stud of the hand it is welded to, so the offset still reads as
-- a grip rather than as a prop floating in front of the player.
local VIEW_HOLD = Vector3.new(1.5, -1.8, -1.6)

-- ── The wipe ────────────────────────────────────────────────────────
-- Two halves of one sweep: in to full cover, then out past the right edge. The cut
-- happens on the boundary between them.
local WIPE_IN = 0.22
local WIPE_OUT = 0.26
-- The bright bar on each edge of the panel, in pixels. It is what makes a moving
-- rectangle read as a film wipe rather than as a window shade.
local WIPE_EDGE = 8

-- ── The reticle ─────────────────────────────────────────────────────
local RETICLE_BOX = 56 -- px, the box the whole thing is centred in
local RETICLE_RING = 22 -- px, the ring's diameter
local RETICLE_GAP_IDLE = 21 -- px from centre to each tick, pointed at nothing
local RETICLE_GAP_LOCKED = 15 -- ...and with a patch under it: the ticks close in
local RETICLE_EASE = 16 -- how fast the gap chases its goal, per second

-- The jet: a chain of overlapping BALLS laid along the water's real flight path.
-- See the header for why it is parts rather than a Beam or a particle cone, and why
-- they are balls rather than the cylinders they started as.
local JET_SEGMENTS = 18
-- Cartoon water is BRIGHT. This is barely a darkening at all -- just enough to keep
-- the liquid's own pastel from washing into the pale steel of the tub behind it.
local JET_DARKEN = 0.18
-- Foam: how white the stream goes by the very tip, and where along its length it
-- starts turning. A white leading edge is the single most cartoon thing about drawn
-- water, and it doubles as the aeration cue that was there before.
local JET_FOAM = 0.6
local JET_FOAM_START = 0.6
local JET_RADIUS_NEAR = 0.17
local JET_RADIUS_FAR = 0.46
-- How much each blob's radius breathes with the churn below. Cartoon streams are
-- lumpy; a perfectly even tube is a pipe.
local JET_LUMP = 0.24
-- Opaque, on purpose. See-through water reads as glass or as a particle haze; a solid
-- shape with a hard silhouette is what makes it read as drawn.
local JET_TRANSPARENCY = 0
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
-- The splash blob where the water lands: diameter, and how much of that it breathes.
-- Kept just under the size of an item, so it reads as landing ON the thing rather
-- than swallowing it -- at 1.7 the white blob was the biggest object in the shot.
local SPLASH_SIZE = 1.25
local SPLASH_PULSE = 0.3

local state: any = nil
local blobs: { [number]: BasePart } = {}
local folder: Instance? = nil
local jetParts: { BasePart } = {}
local splashPart: BasePart? = nil
local jetShown = false
local spraying = false
local aimedIndex: number? = nil
local renderBound = false

-- The first-person view, as a thing that is either on or off. `viewActive` is what
-- makes enterView/exitView idempotent, and it is also how `leave()` tells "wipe out of
-- a live session" apart from "tidy up a session that never got a camera".
local viewActive = false
local leaving = false
local savedFov = 70
local lookYaw = 0
local lookPitch = 0
local padLook = Vector2.zero
-- The head and anything hanging off it, cached because it is re-asserted every frame.
local hiddenParts: { BasePart } = {}

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
		part.Shape = Enum.PartType.Ball
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
	splash.Shape = Enum.PartType.Ball
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

--- THE LIQUID'S OWN COLOUR, BARELY DARKENED, GOING WHITE AT THE TIP.
---
--- This has swung twice and the middle is where it belongs. It started tinted only
--- faintly toward the liquid, on the reasoning that real spray aerates and reads
--- white -- true, and against a pale steel tub the result was invisible. So it went
--- hard the other way, most of the way to black, which was legible and looked like
--- oil: a dark naturalistic stream in a world of bright matte primaries.
---
--- Cartoon water is BRIGHT and it FOAMS. So the body of the jet is the liquid at
--- nearly full strength -- these are all saturated enough to hold their own against
--- the tub without being dragged toward black -- and the last stretch turns white.
--- A white leading edge is the single most recognisable thing about drawn water; it
--- gives the stream a readable tip, it is the aeration cue the darkening was
--- reaching for, and it is what carries the contrast now.
local function applySprayColor(hex: string)
	local body = Color3.fromHex(hex):Lerp(Color3.new(0, 0, 0), JET_DARKEN)
	local white = Color3.new(1, 1, 1)
	for index, part in jetParts do
		local along = index / JET_SEGMENTS
		local foam = math.clamp((along - JET_FOAM_START) / (1 - JET_FOAM_START), 0, 1)
		part.Color = body:Lerp(white, JET_FOAM * foam)
	end
	if splashPart then
		-- The impact is all foam, always.
		splashPart.Color = body:Lerp(white, 0.72)
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
--- the end of the arc if it did not. That point, not the reticle, is what decides
--- which patch is being worked (see `patchAt`): you are cleaning what the water is
--- landing on, which is the only rule a player would ever guess.
local function drawJet(from: Vector3, to: Vector3, filter: RaycastParams): Vector3
	local now = os.clock()
	local path = jetPath(from, to, now)
	local landing = path[#path]
	local stopped = false

	-- BLOBS HAVE TO OVERLAP OR THE STREAM IS A STRING OF BEADS, and how far apart they
	-- sit depends entirely on how far the player is spraying: the same eighteen blobs
	-- cover two studs or twelve. So the radius has a floor derived from the spacing --
	-- a blob is never allowed to be smaller than it takes to touch its neighbours --
	-- and the tuned radii below are what it looks like once that floor is met.
	local spacing = (to - from).Magnitude / JET_SEGMENTS
	local floor = spacing * 0.62

	for index, part in jetParts do
		local a, b = path[index], path[index + 1]
		local span = (b - a).Magnitude

		if stopped or span < 0.01 then
			-- Either the water already hit something, or the player is aiming at their
			-- own muzzle and the path has collapsed to a point.
			part.Transparency = 1
		else
			-- Segment by segment, so the stream stops ON the surface it hits rather than
			-- passing through the tub and out the far side. One short ray per segment is
			-- the same total length as one long ray down the arc, and a straight ray
			-- cannot follow a curve.
			local hit = Workspace:Raycast(a, b - a, filter)
			if hit then
				landing = hit.Position
				stopped = true
			end

			local along = (index - 0.5) / JET_SEGMENTS
			-- Lumpy, and lumpy IN TIME: the same scrolling noise that bends the path
			-- also swells and pinches each blob as it passes, so the stream visibly
			-- pulses instead of sitting there as a static tapered tube.
			local lump = 1 + JET_LUMP * math.noise(along * 4.7 - now * JET_CHURN, 1.5)
			local radius = math.max(JET_RADIUS_NEAR + (JET_RADIUS_FAR - JET_RADIUS_NEAR) * along, floor) * lump
			local diameter = radius * 2

			part.Size = Vector3.new(diameter, diameter, diameter)
			-- At the segment's START, not its end, so the first blob sits at the muzzle
			-- and the stream visibly leaves the nozzle rather than a gap out from it.
			-- On an impact it moves to the contact point instead, which closes the gap
			-- to the splash.
			--
			-- A ball needs no orientation, which is half the reason for the switch: the
			-- cylinders this replaced had to be aimed down their own segment AND yawed
			-- to get their axis onto it, and every joint still showed a flat end cap.
			part.CFrame = CFrame.new(if hit then hit.Position else a)
			part.Transparency = JET_TRANSPARENCY
		end
	end

	-- The splash: one breathing blob at the point of impact, in the foam colour. Round
	-- rather than the flat disc it was, for the same reason the stream is round now --
	-- and it is doing real work either way. Without something at the end, the eye reads
	-- the stream as STOPPING in mid-air rather than as landing on something.
	local splash = splashPart
	if splash then
		if stopped then
			local size = SPLASH_SIZE * (1 + SPLASH_PULSE * math.noise(now * 6, 0.5))
			splash.Size = Vector3.new(size, size, size)
			splash.CFrame = CFrame.new(landing)
			splash.Transparency = 0.1
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

-- ── The screen: the wipe panel and the reticle ──────────────────────

local wipeGui: ScreenGui? = nil
local wipePanel: Frame? = nil
local reticle: Frame? = nil
local reticleRing: UIStroke? = nil
local reticleTicks: { { frame: Frame, dir: Vector2 } } = {}
local reticleGap = RETICLE_GAP_IDLE

local wipeConn: RBXScriptConnection? = nil
local wipeClock = 0
local wipeCovered = false
local wipeAtCover: (() -> ())? = nil
local wipeTint = DEFAULT_LIQUID

--- One ScreenGui for both, built once and never destroyed. The wipe outlives the
--- session it ends -- the reveal half plays AFTER teardown has run -- so tying its
--- lifetime to the session is how you get a black panel left across the screen.
---
--- IgnoreGuiInset, and it matters for the reticle specifically. The topbar pushes an
--- inset-respecting GUI down by ~36px, and this crosshair is claiming to mark the
--- exact spot the camera's own look ray leaves from: 36 pixels of disagreement between
--- where the water lands and where the sight says it will is the same subtle,
--- maddening miscalibration that ScreenPointToRay was fixed for on the old cursor aim.
local function ensureGui(): boolean
	if wipeGui and wipeGui.Parent then
		return true
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return false
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "WashBay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Above everything, including HudController's blackout curtain (100). A transition
	-- that something else can draw on top of is not covering the cut it exists to hide.
	gui.DisplayOrder = 200
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = playerGui
	wipeGui = gui

	-- ── The reticle ──
	local sight = Instance.new("Frame")
	sight.Name = "Reticle"
	sight.Size = UDim2.fromOffset(RETICLE_BOX, RETICLE_BOX)
	sight.Position = UDim2.fromScale(0.5, 0.5)
	sight.AnchorPoint = Vector2.new(0.5, 0.5)
	sight.BackgroundTransparency = 1
	sight.Visible = false
	sight.ZIndex = 1
	sight.Parent = gui
	reticle = sight

	-- A ring rather than a dot. A dot at this size disappears against a green blob,
	-- which is the one thing it has to stay readable on top of.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromOffset(RETICLE_RING, RETICLE_RING)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 1
	ring.Parent = sight

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = UIKit.C.text
	stroke.Transparency = 0.35
	stroke.Parent = ring
	reticleRing = stroke

	table.clear(reticleTicks)
	for _, dir in { Vector2.new(0, -1), Vector2.new(0, 1), Vector2.new(-1, 0), Vector2.new(1, 0) } do
		local tick = Instance.new("Frame")
		tick.Name = "Tick"
		tick.Size = if dir.X == 0 then UDim2.fromOffset(2, 7) else UDim2.fromOffset(7, 2)
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.BackgroundColor3 = UIKit.C.text
		tick.BackgroundTransparency = 0.2
		tick.BorderSizePixel = 0
		tick.ZIndex = 1
		tick.Parent = sight
		table.insert(reticleTicks, { frame = tick, dir = dir })
	end

	-- ── The wipe panel ──
	-- Parked off the RIGHT edge, which is where every completed sweep leaves it.
	local panel = Instance.new("Frame")
	panel.Name = "Wipe"
	panel.Size = UDim2.fromScale(1, 1)
	panel.Position = UDim2.fromScale(1, 0)
	panel.BackgroundColor3 = UIKit.C.panel
	panel.BorderSizePixel = 0
	panel.ZIndex = 10
	panel.Parent = gui
	wipePanel = panel

	-- BOTH edges, because both of them lead at some point in the sweep: the right edge
	-- is the one crossing the screen on the way in, and the left edge is the one
	-- uncovering it on the way out.
	for _, edge in { { name = "EdgeLeft", x = 0 }, { name = "EdgeRight", x = 1 } } do
		local bar = Instance.new("Frame")
		bar.Name = edge.name
		bar.Size = UDim2.new(0, WIPE_EDGE, 1, 0)
		bar.Position = UDim2.fromScale(edge.x, 0)
		bar.AnchorPoint = Vector2.new(edge.x, 0)
		bar.BorderSizePixel = 0
		bar.ZIndex = 11
		bar.Parent = panel
	end

	return true
end

--- The bright edges wear the loaded liquid, so the transition is already telling you
--- what is in the hose before the shot it reveals does.
local function applyWipeTint(hex: string)
	local panel = wipePanel
	if panel == nil then
		return
	end
	local color = Color3.fromHex(hex)
	for _, bar in panel:GetChildren() do
		if bar:IsA("Frame") then
			bar.BackgroundColor3 = color
		end
	end
end

--- Stop the sweep dead and put the panel back off-screen. Only ever called when the
--- animation itself has finished or has to be abandoned -- NOT from teardown, which
--- runs in the MIDDLE of a sweep and must leave the reveal half to play out.
local function wipePark()
	if wipeConn then
		wipeConn:Disconnect()
		wipeConn = nil
	end
	wipeAtCover = nil
	if wipePanel then
		wipePanel.Position = UDim2.fromScale(1, 0)
	end
end

--- Sweep left to right, calling `atCover` exactly once at the instant the screen is
--- fully covered.
---
--- RenderStepped and a clock rather than two chained Tweens, for one reason: the
--- hand-off in the middle is a CAMERA CUT, and chaining it off a tween's Completed
--- signal makes the most important line in the transition depend on an event that
--- fires on another thread. One connection, one closure, one place the cut can
--- happen. `wipeRun` also replaces any sweep already running, so entering and leaving
--- in quick succession restarts the wipe instead of stacking two of them.
---
--- The two halves ease in opposite directions (t² then 1-(1-t)²) so the panel
--- accelerates across the cut and decelerates off the far edge. Ease the same way
--- twice and it visibly stops dead in the middle, which draws attention to the exact
--- frame the wipe exists to hide.
local function wipeRun(atCover: () -> ())
	if not ensureGui() then
		-- No PlayerGui to draw on. The transition is decoration; the cut it hides is
		-- not, so fire it immediately rather than losing a session to a missing GUI.
		atCover()
		return
	end
	local panel = wipePanel :: Frame

	applyWipeTint(wipeTint)
	if wipeConn then
		wipeConn:Disconnect()
	end
	wipeClock = 0
	wipeCovered = false
	wipeAtCover = atCover
	panel.Position = UDim2.fromScale(-1, 0)

	wipeConn = RunService.RenderStepped:Connect(function(dt)
		wipeClock += dt
		if wipeClock < WIPE_IN then
			local t = wipeClock / WIPE_IN
			panel.Position = UDim2.fromScale(-1 + t * t, 0)
			return
		end

		if not wipeCovered then
			wipeCovered = true
			-- Cleared BEFORE the call, not after: `atCover` is teardown on the way out,
			-- and teardown is entitled to look at (and clear) this same field.
			local fire = wipeAtCover
			wipeAtCover = nil
			if fire then
				fire()
			end
		end

		local t = math.min((wipeClock - WIPE_IN) / WIPE_OUT, 1)
		if t >= 1 then
			wipePark()
			return
		end
		panel.Position = UDim2.fromScale(1 - (1 - t) * (1 - t), 0)
	end)
end

--- The ring and its four ticks. `locked` is "there is a patch under the sight", which
--- is the single thing a player needs to know before they pull the trigger, and it is
--- said in the same green the patch itself is wearing.
local function paintReticle(dt: number, locked: boolean)
	local sight = reticle
	if sight == nil or not sight.Visible then
		return
	end

	local goal = if locked then RETICLE_GAP_LOCKED else RETICLE_GAP_IDLE
	if spraying then
		goal -= 2
	end
	-- Chased rather than snapped. The lock flickers on and off as the arc wanders over
	-- the edge of a blob, and a reticle that pops between two sizes on every one of
	-- those reads as broken rather than as responsive.
	reticleGap += (goal - reticleGap) * math.min(dt * RETICLE_EASE, 1)

	local color = if locked then PATCH_GREEN else UIKit.C.text
	if reticleRing then
		reticleRing.Color = color
		reticleRing.Transparency = if locked then 0.05 else 0.35
	end
	for _, tick in reticleTicks do
		tick.frame.BackgroundColor3 = color
		tick.frame.BackgroundTransparency = if locked then 0 else 0.2
		tick.frame.Position = UDim2.new(0.5, tick.dir.X * reticleGap, 0.5, tick.dir.Y * reticleGap)
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
---
--- `neutral` is the camera at this session's base framing -- the shot with the
--- player's own look offsets taken back out -- and it is what decides where in the
--- picture the nozzle hangs. See the note on aimOffset below.
local function startAimRig(neutral: CFrame?)
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

	-- THE POINT THE NOZZLE ORBITS, captured once and kept for the session so the tool
	-- swings around one fixed spot in the grip rather than drifting.
	--
	-- IT IS A COMPOSITION DECISION NOW, NOT THE CARRIED POSE. In third person this was
	-- simply where the tool already was (`tool.PrimaryPart.Position` in hand space) and
	-- that was the right answer, because the shot contained the whole character and the
	-- nozzle had to stay in their hands to make sense. First person contains neither
	-- hand: measured off the live shot, the braced hose pose puts both of them 44
	-- degrees below the view axis, and the frame's bottom edge is 30. So what the
	-- carried pose actually bought was a nozzle swinging up out of nowhere across the
	-- MIDDLE of the picture -- at 2.9 studs it covered more screen height than the item
	-- being washed did at 4.5, which is a viewmodel occluding the only thing the player
	-- is trying to look at.
	--
	-- VIEW_HOLD places it where a held thing belongs instead: low and to the right,
	-- barrel angling up-left toward whatever the reticle is on. It is written in the
	-- NEUTRAL view's axes because that is the frame it was judged in, and converted to
	-- HAND space right here, once -- so from this line on the nozzle is rigidly bolted
	-- to the hand exactly as before and cannot come adrift from the character at any
	-- look angle. It is a different offset, not a looser joint.
	local held = if neutral then neutral * VIEW_HOLD else tool.PrimaryPart.Position
	aimOffset = hand.CFrame:PointToObjectSpace(held)
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

--- What the player is pointing AT, in the world -- a plain raycast down the middle of
--- the view.
---
--- This used to be cast from the mouse cursor through a fixed side-on camera, and
--- before that it returned a patch INDEX and snapped the aim to that patch's blob --
--- which is what made the stream jump from blob to blob as the mouse moved: the water
--- was not going where you pointed, it was going where the game had decided you meant.
--- Aim is now just aim, and in first person "just aim" is the camera's own look ray:
--- a symmetric projection puts the centre of the viewport exactly down LookVector, so
--- the reticle drawn at the middle of the screen and this ray are the same line by
--- construction rather than by a conversion that could drift out of step.
---
--- The blobs and the jet segments are all CanQuery = false, so this never hits the
--- effects themselves -- it finds the ITEM under the blob, which is where the
--- contamination is anyway. The character is filtered out because the ray starts
--- inside the player's own head.
local function aimPointAt(from: CFrame, filter: RaycastParams): Vector3
	local hit = Workspace:Raycast(from.Position, from.LookVector * AIM_RANGE, filter)
	if hit then
		return hit.Position
	end
	return from.Position + from.LookVector * AIM_FALLBACK
end

--- Which patch is being worked: the one nearest to where the water actually LANDS.
---
--- Not nearest to the reticle, and the difference is the whole point. The stream is a
--- falling arc that leaves a nozzle held below the eye and stops at the first thing it
--- touches, so the sight and the impact are genuinely different places -- and "you are
--- cleaning what you are hitting" is the only rule a player would ever guess from
--- watching it. PATCH_REACH is generous because a half-stud ball at five studs, hit
--- with a ballistic arc, is a cruel thing to ask anyone to be exact about.
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

-- ── The first-person view ────────────────────────────────────────────

--- The head, and anything hanging off it. Cached because `applyHidden` runs every
--- frame (see the header) and walking every accessory's descendants sixty times a
--- second to write five properties is pure waste.
local function cacheHidden()
	table.clear(hiddenParts)
	local character = Players.LocalPlayer.Character
	if character == nil then
		return
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		table.insert(hiddenParts, head)
	end
	for _, thing in character:GetChildren() do
		if thing:IsA("Accessory") then
			for _, part in thing:GetDescendants() do
				if part:IsA("BasePart") then
					table.insert(hiddenParts, part)
				end
			end
		end
	end
end

--- Re-assert the head's transparency. See the header: Roblox's own
--- TransparencyController writes this property from RenderPriority.Camera, one step
--- ahead of `onRender`, so this is not a one-time thing you can do at session start.
--- The cache is rebuilt whenever it has gone stale, which is what covers an accessory
--- that loads a beat after the character does.
local function applyHidden(value: number)
	if #hiddenParts == 0 or hiddenParts[1].Parent == nil then
		cacheHidden()
	end
	for _, part in hiddenParts do
		if part.Parent ~= nil then
			part.LocalTransparencyModifier = value
		end
	end
end

local function clampLook()
	lookYaw = math.clamp(lookYaw, -YAW_LIMIT, YAW_LIMIT)
	lookPitch = math.clamp(lookPitch, -PITCH_LIMIT, PITCH_LIMIT)
end

--- Where the camera sits and which way it is facing, and alongside it the NEUTRAL
--- version of the same shot -- the framing with the player's own look offsets taken
--- back out. The neutral frame is the one the hose's resting place is measured in
--- (startAimRig), which is why it comes back from here rather than being recomputed.
---
--- The base direction is a straight line from the player's own head to the item on
--- the stand, so a session that has just started is already looking at the thing it
--- is about to be spent looking at, with no settling and no swing. `lookYaw` and
--- `lookPitch` are the player's own offsets from that.
---
--- fromEulerAnglesYXZ, and the order is not incidental: yaw is applied first and
--- pitch second, about the already-yawed X axis, which is the composition that keeps
--- the horizon level. CFrame.Angles' native XYZ order tips it the moment both are
--- non-zero, and a head that rolls as you look diagonally is the kind of wrongness
--- players feel without being able to name.
local function eyeCFrame(): (CFrame?, CFrame?)
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return nil, nil
	end

	local pivot = itemPivot()
	local toward = if pivot then (pivot.Position - head.Position) else head.CFrame.LookVector
	if toward.Magnitude < 0.05 then
		toward = head.CFrame.LookVector
	end
	toward = toward.Unit

	local baseYaw = math.atan2(-toward.X, -toward.Z)
	local basePitch = math.asin(math.clamp(toward.Y, -1, 1))

	local rotation = CFrame.fromEulerAnglesYXZ(basePitch + lookPitch, baseYaw + lookYaw, 0)
	local eye = CFrame.new(head.Position + rotation.LookVector * EYE_FORWARD) * rotation

	-- Same eye POSITION, base rotation. Sharing the position matters: the neutral
	-- frame is only ever used to place an object in the picture, and one anchored a
	-- few inches from where the picture is actually taken would place it wrong.
	local neutralRotation = CFrame.fromEulerAnglesYXZ(basePitch, baseYaw, 0)
	local neutral = CFrame.new(eye.Position) * neutralRotation

	return eye, neutral
end

local function onRender(dt: number)
	if state == nil then
		return
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	-- THE POINTER LOCK IS RE-ASSERTED EVERY FRAME, for the same reason the head's
	-- transparency is. Roblox's PlayerModule calls UpdateMouseBehavior from its own
	-- camera step at RenderPriority.Camera -- one ahead of this one -- so a single
	-- write at session start is stamped back to Default on the very next frame and the
	-- cursor comes loose. Guarded on the read so it is not a property write per frame
	-- in the ordinary case where it already holds.
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end

	-- GAMEPAD LOOK IS INTEGRATED HERE rather than where the input arrives, because a
	-- thumbstick reports a POSITION that stays put for as long as it is held: turning
	-- that into a turn needs a clock, and this is the one place with a dt. The mouse
	-- reports a delta and is applied where it lands.
	if padLook.Magnitude > PAD_DEADZONE then
		lookYaw -= padLook.X * PAD_SENS * dt
		lookPitch += padLook.Y * PAD_SENS * dt
		clampLook()
	end

	local eye, neutral = eyeCFrame()
	if eye == nil then
		-- The head is gone: a respawn is landing and the session is about to end, but
		-- it has not been told yet. Fall back to the station's own side-on anchor --
		-- an unflattering angle for a frame beats a camera frozen wherever it was.
		local stand = state.stand
		local anchor = if stand and stand.Parent then stand.Parent:FindFirstChild("WashCam") else nil
		if anchor and anchor:IsA("BasePart") then
			camera.CFrame = anchor.CFrame
		end
		return
	end

	camera.CFrame = eye
	-- Kept well out in front, never on top of the lens. See the header: this is what
	-- stops TransparencyController dissolving the arms and the hose.
	camera.Focus = CFrame.new(eye.Position + eye.LookVector * FOCUS_AHEAD)
	applyHidden(1)

	paintBlobs()

	-- Rebuilt per frame rather than cached: the character is respawnable and the folder
	-- is destroyed on every teardown(), so a stale filter would either miss the
	-- character or hold a reference to a freed instance.
	local filter = RaycastParams.new()
	filter.FilterType = Enum.RaycastFilterType.Exclude
	filter.FilterDescendantsInstances = { Players.LocalPlayer.Character :: any, folder :: any }

	local aimPoint = aimPointAt(eye, filter)

	-- Tracks the view continuously, spraying or not — a held hose reads as aimed the
	-- moment you look somewhere, same as a real one, not only while it is live.
	if aimMotor == nil then
		startAimRig(neutral)
	end
	updateAimRig(aimPoint)

	-- The jet reports back where it landed, which is not the aim point whenever the
	-- falling arc clips something on the way. That impact, not the reticle, is what
	-- picks the patch.
	local nozzle = nozzleCFrame()
	local landing = aimPoint
	if spraying and nozzle then
		landing = drawJet(nozzle.Position, aimPoint, filter)
	else
		hideJet()
	end

	local target = patchAt(landing)
	paintReticle(dt, target ~= nil)

	if target ~= aimedIndex then
		aimedIndex = target
		if inputRemote then
			inputRemote:FireServer({ spraying = spraying, patchIndex = aimedIndex })
		end
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────

--- Take the camera. Called from the MIDDLE of the entry wipe, with the screen covered,
--- which is the only reason a cut this violent is invisible.
local function enterView()
	-- `state == nil` is the entry-then-immediate-exit race: the player pressed Q inside
	-- the 0.22s the panel takes to arrive, so the session this was queued for is
	-- already gone. Taking the camera now would strand them in it.
	if viewActive or state == nil then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	viewActive = true

	savedFov = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = WASH_FOV

	lookYaw, lookPitch = 0, 0
	padLook = Vector2.zero
	reticleGap = RETICLE_GAP_IDLE

	UserInputService.MouseIconEnabled = false
	cacheHidden()
	if reticle then
		reticle.Visible = true
	end

	if not renderBound then
		RunService:BindToRenderStep("WashBay", Enum.RenderPriority.Camera.Value + 1, onRender)
		renderBound = true
	end
end

--- The exact inverse, and every field it touches is restored whether or not this
--- file was the one that changed it. Idempotent: `viewActive` is the gate, and it is
--- the first thing cleared.
local function exitView()
	if not viewActive then
		return
	end
	viewActive = false

	if renderBound then
		RunService:UnbindFromRenderStep("WashBay")
		renderBound = false
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	applyHidden(0)
	table.clear(hiddenParts)
	if reticle then
		reticle.Visible = false
	end

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = savedFov
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

--- Idempotent on purpose — see the header. Every exit path calls this, sometimes
--- more than once, sometimes when no session was ever running.
---
--- It does NOT call wipePark. On the way out this runs from inside a sweep that still
--- has its reveal half to play, and killing the animation from here is how the panel
--- ends up parked across a screen nobody can clear.
local function teardown()
	-- Any cut still queued behind a sweep belongs to a session that no longer exists.
	wipeAtCover = nil

	exitView()
	state = nil
	spraying = false
	aimedIndex = nil
	leaving = false
	lookYaw, lookPitch = 0, 0
	padLook = Vector2.zero

	clearBlobs()
	stopAimRig()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(jetParts)
	splashPart = nil
	jetShown = false
end

local function beginSession()
	leaving = false
	ensureSpray()
	applySprayColor(wipeTint)
	wipeRun(enterView)
end

--- The way out, and it wipes on the way: `teardown` is fired from the middle of the
--- sweep, with the screen covered, so the cut back to the ordinary over-the-shoulder
--- camera is never seen.
---
--- THE SECOND CALL IS NOT PARANOIA. A player left in a Scriptable camera with their
--- WalkSpeed pinned at zero has no way out short of rejoining (see the header), and
--- deferring that restore into an animation callback is exactly the kind of thing
--- that strands one if the sweep is interrupted. `teardown` is idempotent, so simply
--- calling it again a beat later is the cheapest insurance there is.
local function leave()
	if not viewActive then
		-- Nothing has been taken yet (or it has already been given back). No cut to
		-- hide, so no wipe -- and if an entry sweep is still in the air, clearing its
		-- pending `enterView` inside teardown is what stops it firing into a session
		-- that has already ended.
		teardown()
		return
	end
	if leaving then
		return
	end
	leaving = true
	wipeRun(teardown)
	task.delay(WIPE_IN + 0.4, teardown)
end

function Wash.start()
	inputRemote = Net.get("WashInput")

	Net.get("WashState").OnClientEvent:Connect(function(payload)
		if payload == nil then
			leave()
			return
		end

		local fresh = state == nil
		state = payload
		-- The loaded liquid can change mid-wash: run a canister dry and you drop back
		-- to Plain Water, and both the spray and the wipe's edges have to say so.
		wipeTint = payload.liquidColor or DEFAULT_LIQUID
		if fresh then
			beginSession()
		else
			applySprayColor(wipeTint)
		end
	end)

	-- MOUSE LOOK. Delta, not Position: with the pointer locked to the middle of the
	-- screen there is no meaningful position, and Delta is the raw movement that lock
	-- exists to expose. Not gated on `gameProcessedEvent` — a locked, hidden cursor
	-- cannot be over a GUI for one to have swallowed it.
	UserInputService.InputChanged:Connect(function(input)
		if not viewActive then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			-- Both negated: dragging the mouse right turns the view right, which is a
			-- DECREASE in yaw (a positive rotation about +Y turns left), and dragging it
			-- down looks down.
			lookYaw -= input.Delta.X * MOUSE_SENS
			lookPitch -= input.Delta.Y * MOUSE_SENS
			clampLook()
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			padLook = Vector2.new(input.Position.X, input.Position.Y)
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
		-- is spent clicking, to spray. E is kept as the discoverable exit (same key
		-- that got you in); Q is the one that works even if a player never associates
		-- E with "leave" once they are staring down a hose.
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonB then
			inputRemote:FireServer({ stop = true })
			return
		end

		-- Spraying waits for the camera. During the entry wipe the screen is covered and
		-- there is nothing to aim at yet, so a click there would spend the player's
		-- charge on whichever patch the server picked by default, unseen.
		if processed or not viewActive then
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
		if input.KeyCode == Enum.KeyCode.Thumbstick2 then
			padLook = Vector2.zero
		end
	end)

	-- A respawn mid-wash fires no remote at all: the server's leash check sees a
	-- character with no root and ends the session silently. This is the only thing
	-- standing between that and a player left in a Scriptable camera.
	--
	-- Straight to teardown, not through leave(): the character this shot was framed on
	-- no longer exists, so there is no picture left worth wiping away from.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		teardown()
	end)
end

return Wash
