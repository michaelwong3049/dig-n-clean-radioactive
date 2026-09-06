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

	PATCH BLOBS SIT WHERE THE SERVER SAYS THE REAL PATCH IS. WashService bucket the
	item's own real parts (or a stand-in cluster of blocks for the rarity-coloured
	fallback) into one zone per patch and sends each patch's `anchor` — the zone's own
	position — over WashState. This file only draws a ball there; it used to place
	blobs itself with a golden-angle spiral scaled to the item's bounding box, which
	looked decorative rather than attached and reshuffled position whenever a patch
	other than the last cleared (the array compacting). Keying blobs by the patch's
	`zone` id rather than its array index is what makes a surviving patch's ball hold
	still when a different one clears.

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

	NOTHING IS IN THE PLAYER'S HAND. The hose is a MACHINE bolted to a mast at the
	corner of the tub (build/Plots.buildHoseRig) at whatever Cleaner rung its owner has
	bought, and the player operates it from the mark. It used to be a copy of that
	nozzle welded into the right hand for the session, with a second local Motor6D
	stacked on the server's weld to point it and the server's weld disabled underneath
	-- a rig whose every part existed to make a fixture behave like a held thing.

	SO THE AIM IS A CFrame WRITE ON AN ANCHORED PART, WHICH IS ALL IT EVER NEEDED TO
	BE. The nozzle is world geometry the server built and then never touches again, so
	a client rewriting its pivot moves it for that viewer alone -- no joint, no weld to
	disable, no character to accidentally bolt to the world (an anchored part anchors
	its whole assembly, which is exactly why the old rig could not simply point the
	parked nozzle and had to be handed a copy). Every session captures the model's
	`ParkedPivot` and puts it back on the way out.

	THAT MAKES THE AIM PER-VIEWER, and it is the same trade the spray already makes.
	A bystander sees the monitor sitting on its mast, not swinging; they see the item
	on the tub (server-side, WashService) and the machine's rung (server-side, world
	geometry), which are the two things worth seeing from outside. What they do not see
	is one player's aim, which is worth no traffic at all.

	THE ARMS ARE POSED, BUT NOT BY THIS FILE, and they still are even with the hands
	empty. Posing is server-side and ToolService owns it (it braces the whole upper
	body for the detector, on a rig-agnostic weld scheme that handles both Motor6D and
	AnimationConstraint characters); it braces for the wash from its own `isWashing`
	check. Without it a player at the mark stands slack with their arms swinging
	through an idle cycle while a machine beside them sprays on its own.

	THE SPRAY IS A BRAIDED STREAM ON A BALLISTIC ARC, AND IT TOOK SEVEN TRIES. Each
	one fixed something real about the last, so the whole ladder is worth keeping:

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
	stopping on the first surface it touches. That is still how it moves, and every
	version since has left it alone.

	v6 was the cartoon pass: eighteen OPAQUE overlapping balls, bright, with a white
	foam tip. It was legible and it was cheap and it was, photographed, a string of
	cyan gumballs. A chain of spheres has a scalloped silhouette wherever consecutive
	radii differ, and at two studs from the lens -- which is where the muzzle sits in
	first person -- that scalloping is the ONLY thing the eye reads. "Blocky" was the
	word, and it was the right one.

	v7, below, is the realism pass, and it is four changes. Note what it gives up:
	v6's own note argued a bright opaque stream belonged in a world of matte
	primaries, and that argument was not wrong -- this trades it for water that reads
	as water, because that is what was asked for. The liquid's colour still drives
	the tint, so Plain Water and Solvent are still told apart at a glance.

	  * THE STREAM IS A TUBE, NOT A BEAD CHAIN. Cylinders laid end to end with a ball
	    at each joint -- a capsule chain -- have a continuous silhouette by
	    construction, and the joint balls fill the wedge that opens on the outside of
	    every bend. This is also why the old "a blob may never be smaller than the
	    gap to its neighbour" floor is gone: a capsule spans its own gap. The
	    cylinders v4 abandoned failed for showing flat end caps at the joints, which
	    is exactly what the joint balls fix.

	  * IT IS TRANSLUCENT, AND IT IS BRAIDED. One tube of one flat colour is a pipe
	    no matter how well it is shaded, so the jet is a wide, barely-there SHEATH
	    with three thin STRANDS wound through it. The braid turns with time, so the
	    strands appear to spiral outward from the nozzle -- which is what reads as
	    speed, and it does the job v6's per-blob size lump was reaching for without
	    a lump anywhere. The strands also fray outward as they travel: together at
	    the muzzle, spread apart at the tip, because that is what a jet does.

	  * IT AERATES. Colour runs from the liquid's own at the muzzle to nearly white
	    at the tip, and transparency runs the same way, so the far end thins out into
	    spray instead of stopping. v6 had the colour half of this and none of the
	    other half, which is why its tip read as a painted white cap.

	  * IT SHEDS AND IT SPLASHES ON THE SURFACE. Droplets thrown clear of the cone
	    are drawn as SLIVERS along their own flight, not as dots -- a round dot is a
	    ball bearing, an elongated one is a thing moving fast, and v2's fog was dots.
	    They also TRAVEL, down the jet and outward from the impact, fading in and out
	    at the ends of each trip: a droplet pinned at a fixed point is a stud welded
	    to the stream, and six of them pinned around the impact is a spoked wheel.
	    The impact itself is built on the surface NORMAL the raycast already returns
	    -- a dome sunk into the surface so only its cap shows, a wider, fainter one
	    sunk further for the water spreading around it, that crown, and a thin mist.
	    The mist is the one thing here v2 also had, kept small and kept at the impact
	    only: it was the cone-length version of it that buried the item.

	THE WOBBLE IS NOISE, NOT RANDOM, and an early version got this wrong in the
	other direction. It jittered the stream's ENDPOINT on a sine wave to fake
	liveliness, which read as a broken aim rather than as moving water. What is here
	instead leaves the endpoint alone and displaces the path in between, sampled from
	math.noise at (distance along the jet - time) so the same ripple travels outward
	from the nozzle; a fresh math.random offset every frame would be static, not
	flow. It fades to nothing at the muzzle, because water leaves a nozzle coherent
	and breaks up as it goes, and wobble at the muzzle just reads as a loose grip.
	It is smaller than it was, because the braid now carries most of the motion.

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
-- ── The monitor on its mast ─────────────────────────────────────────
-- How far the barrel may swing off its parked aim before it stops following. A ball
-- joint is not a turret: past this the machine would be pointing back at its own
-- plumbing. Generous rather than tight, because the CAMERA is already clamped to a
-- +/-32 degree cone around the item (YAW_LIMIT) and the aim ray lives inside that --
-- these are the safety rail for a ray that escapes down a long sightline, not the
-- thing a player is meant to feel.
local NOZZLE_YAW_LIMIT = math.rad(80)
local NOZZLE_PITCH_LIMIT = math.rad(60)
-- How fast the barrel chases the aim, per second, as an exponential catch-up. Not
-- instant, and the lag is the point: a monitor is a heavy thing on a ball joint, and
-- a nozzle that snapped to the reticle would read as a cursor with a model on it. At
-- 14 it is within a couple of degrees inside a fifth of a second, so it never lags
-- the water anywhere a player would notice -- it only rounds off a whip.
local NOZZLE_EASE = 14
-- WHAT `volume` BUYS ON SCREEN. Config/Gear's Cleaner rungs run 1.0 to 3.8, and the
-- stream's girth is the square root of that, halved back toward 1 and capped: tier 1
-- is 1.00x, the middle of the ladder 1.19x, the Plasma Lance 1.48x.
--
-- BOTH SOFTENINGS WERE PAID FOR IN A PLAYTEST. Linear (3.8x) is obviously absurd. The
-- raw root (1.95x) looked reasonable as a number and was photographed swallowing the
-- frame: the far end of the stream is a 1.8-stud rope landing on a 1.4-stud item, from
-- a nozzle two studs off the lens. Halving the root is what leaves every rung visibly
-- fatter than the one below while the top one is still a stream rather than a wall.
--
-- GIRTH ONLY. JET_SPEED and JET_GRAVITY are untouched, so the arc a player learns to
-- lead with is the same arc at every rung -- a bought upgrade should not quietly
-- re-teach the aim.
local JET_GIRTH_MAX = 1.5

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

-- The jet: a translucent SHEATH with three STRANDS braided through it, laid along the
-- water's real flight path, fraying into flung droplets as it goes. See the header for
-- why it is parts rather than a Beam or a particle cone, and for the six shapes this
-- one replaced.
local JET_SEGMENTS = 12

-- A Cylinder's native axis is its own local X, and this is the rotation that sends
-- that X onto -Z -- which is where CFrame.lookAt points. Same constant, same reason,
-- as Shared/ToolModels/Hose's; see its note for why Kit.R.cylAlongZ is not it.
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)
-- How much longer than its own gap each tube is cut. Consecutive tubes then overlap
-- rather than butting, which hides the seam the joint balls do not cover.
local TUBE_OVERLAP = 0.015

-- THE FLIGHT. Studs per second the water leaves the nozzle at: the flight time -- and
-- so how far the arc sags -- falls out of this against the distance to the aim point,
-- which is the whole reason the jet droops more the further you point it.
local JET_SPEED = 26
-- Studs per second squared. Roblox's own gravity is 196.2, which over a wash bay's
-- couple of studs of flight is a vertical drop nobody would read as an arc; this is
-- the value that makes the sag legible at this scale. Not physics, staging.
local JET_GRAVITY = 46
-- Turbulence. `JET_WOBBLE` is how far a mid-jet segment may wander off the ideal path,
-- in studs, and `JET_CHURN` how fast that wander scrolls along the stream. Both fade to
-- nothing at the nozzle -- water leaves a nozzle coherent and breaks up as it travels,
-- and wobble at the muzzle just reads as a loose grip. The wobble is smaller than it
-- was: the braid below now carries most of the liveliness this used to have to fake.
local JET_WOBBLE = 0.10
local JET_CHURN = 3.4

-- THE SHEATH: the soft outer volume of the spray, wide and barely there. It is what
-- gives the jet a body without giving it an edge, and the edge is the whole difference
-- between water and a pipe.
local SHEATH_RADIUS_NEAR = 0.075
local SHEATH_RADIUS_FAR = 0.34
-- The exponent between them: coherent out of the muzzle, then opening. Linear made a
-- cone, and a cone with a hard mouth is a megaphone.
local SHEATH_FLARE = 1.5
local SHEATH_ALPHA_NEAR = 0.68
local SHEATH_ALPHA_FAR = 0.94

-- THE STRANDS: three ropes of water wound around the flight path, together at the
-- muzzle and frayed apart by the tip. The braid ROTATES with time, which is what makes
-- the stream read as moving rather than as a static tapered tube.
local STRAND_COUNT = 3
local STRAND_RADIUS = 0.052
local STRAND_TAPER = 0.30 -- how much thinner a strand is by the far end
local STRAND_TWIST = 5.6 -- radians of winding across the whole flight
local STRAND_SWIRL = 3.0 -- radians per second the whole braid turns
local STRAND_FRAY = 0.185 -- how far off the spine a strand sits at the tip, in studs
local STRAND_FRAY_POWER = 1.8 -- ...and how late in the flight it happens
local STRAND_ALPHA_NEAR = 0.08
local STRAND_ALPHA_FAR = 0.70
local STRAND_ALPHA_POWER = 1.6

-- AERATION. How much white is mixed into the liquid's own colour at the muzzle and at
-- the tip: water driven through air turns white, and a jet that holds one flat colour
-- end to end is a painted rod. The sheath sits a little BEHIND the strands on this
-- curve so the braid stays the brighter thing inside it.
local WATER_WHITE_NEAR = 0.30
local WATER_WHITE_FAR = 0.88
local SHEATH_WHITE_BIAS = -0.10
-- Water is the only thing in this game with a specular highlight, and it is what stops
-- SmoothPlastic from reading as plastic.
local WATER_REFLECT = 0.2

-- THE SHED DROPLETS: drawn as SLIVERS along their own flight rather than as dots. A
-- round dot at this size is a ball bearing; an elongated one is a thing moving fast,
-- and "a fog of little dots" is the exact report that killed the particle version.
local DROP_COUNT = 8
-- Nothing sheds while the jet is still coherent. From there they TRAVEL, at
-- `DROP_FLOW` trips down the jet a second, and the ring they hang off turns as well --
-- droplets pinned to fixed points on the stream read as studs welded to it, however
-- lively the stream itself is.
local DROP_START = 0.30
local DROP_FLOW = 0.55
local DROP_SPIN = 2.0
local DROP_SPREAD = 0.42 -- how far off the spine a droplet is by the tip, in studs
local DROP_FRAY_POWER = 1.8
local DROP_SPLAY = 0.55 -- how far a droplet's own heading tips outward from the flow
local DROP_LEN_NEAR = 0.20
local DROP_LEN_FAR = 0.56
local DROP_RADIUS = 0.028
-- Faintest at both ends of the trip and solid in the middle, which is what lets a
-- droplet appear and disappear without popping: it tears off the stream, and it
-- atomises away again before it reaches the end.
local DROP_ALPHA_PEAK = 0.18
local DROP_FADE_POWER = 1.5

-- THE IMPACT, built on the surface normal the raycast already hands back. The dome is
-- a plain sphere pushed INTO the surface so that only its cap shows, which is what
-- makes it sit ON the geometry instead of floating in front of it.
--
-- BOTH SINKS ARE A FRACTION OF THE SPHERE'S RADIUS, not of its size, and the difference
-- is the whole thing: at 1.0 the sphere is exactly buried and nothing shows at all, so
-- anything written here as if it were a fraction of the diameter silently draws no
-- splash. What shows is a cap (1 - sink) of the radius tall.
--
-- SIZE HERE IS A FRAMING CONSTRAINT, NOT A STATEMENT ABOUT THE RUNG -- which is why
-- none of it scales with `girth`. It lands dead centre of the view on top of the one
-- object the player is trying to look at, and this is already at the edge of that: an
-- earlier 1.7 was photographed as the biggest thing in the shot.
local SPLASH_SIZE = 0.62
local SPLASH_SINK = 0.42
local SPLASH_PULSE = 0.22
local SPLASH_ALPHA = 0.32
-- The wet spread around the dome: a second, wider sphere sunk far enough that only a
-- shallow cap of it shows. A FLAT DISC was the obvious way to draw this and it was
-- wrong twice -- a hard-edged circle reads as a decal stuck on the item, and on
-- anything but a flat face half of it disappears inside the geometry.
local SPLASH_HALO = 1.8
local SPLASH_HALO_SINK = 0.62
local SPLASH_HALO_ALPHA = 0.88

-- THE CROWN: droplets thrown back off the surface, mostly along it and a little out
-- along the normal. Each one FLIES -- out from CROWN_INNER to CROWN_INNER + CROWN_REACH
-- over `CROWN_RATE` trips a second, fading in and out again at the two ends -- and they
-- are staggered so no two are at the same point in that trip.
--
-- WHICH IS THE FIX FOR THE THING THIS FIRST LOOKED LIKE. Six droplets pinned at fixed
-- radii around a point, however well shaded, is a spoked wheel, and with the flat film
-- disc that used to sit behind them it was a comic-book impact starburst. Motion and a
-- jittered ring are what turn the same six parts into a splash.
local CROWN_COUNT = 9
local CROWN_RATE = 2.2
local CROWN_JITTER = 0.9 -- radians a droplet may sit off its even share of the ring
local CROWN_RISE = 0.45 -- how much of each droplet's heading is along the normal
local CROWN_INNER = 0.18 -- where the ring starts, in studs from the impact
local CROWN_REACH = 0.45 -- ...and how far out it has got by the end of the trip
local CROWN_LEN = 0.18
local CROWN_RADIUS = 0.022
-- Faint even at its best. These sit dead centre of the view on top of the item, and an
-- opaque white sliver there is a chalk mark on the thing the player is inspecting.
local CROWN_ALPHA_PEAK = 0.30
local CROWN_FADE_POWER = 1.4

-- THE MIST. The one thing here the particle version also had, and the reason it is
-- safe now is that it is ONLY at the impact: it was the cone-length version that
-- buried the item being washed. Kept small, kept faint, and kept short-lived.
local MIST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local MIST_RATE = 26
local MIST_LIFE = NumberRange.new(0.22, 0.44)
local MIST_SPEED = NumberRange.new(1.5, 3.5)
local MIST_SPREAD = 38
local MIST_RISE = 6 -- studs/s^2 upward, so the haze lifts off the item rather than clinging

-- ── The turntable ───────────────────────────────────────────────────
-- The item spins in place on the stand for the whole session, so a patch on the far
-- side is not simply unreachable from a fixed first-person view -- it comes around.
-- Radians per second around a WORLD-vertical axis through the item's own placement
-- point, deliberately not the item's own up axis: several items sit tilted for the
-- camera ("Wash" rotation, ItemModels), and spinning around a tilted axis wobbles
-- like a dropped coin instead of turning like it is on a turntable.
local ROTATE_RATE = math.rad(32)

local state: any = nil
local blobs: { [number]: BasePart } = {}
local folder: Instance? = nil
-- The spray, preallocated once by `ensureSpray` and only moved from then on.
-- `sprayParts` is every one of them flat, and exists so the hide and teardown paths do
-- not have to know the layout.
local sheathParts: { BasePart } = {}
local strandTubes: { BasePart } = {}
local strandJoints: { BasePart } = {}
local dropTubes: { BasePart } = {}
local dropHeads: { BasePart } = {}
local crownParts: { BasePart } = {}
local sprayParts: { BasePart } = {}
local splashPart: BasePart? = nil
local haloPart: BasePart? = nil
local mistEmitter: ParticleEmitter? = nil
local jetShown = false
local spraying = false
local aimedZone: number? = nil
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

-- The machine's nozzle, and the pose to put it back on. Resolved lazily from
-- onRender rather than once at session start, and re-resolved whenever the model
-- IDENTITY changes -- a Cleaner purchase landing mid-wash destroys the monitor on the
-- mast and parents a new rung in its place (Plots.setHoseTier), and a stale reference
-- would spend the rest of the session swivelling a freed instance.
local nozzleModel: Model? = nil
local nozzleParked: CFrame? = nil

-- The turntable's own state. `rotateItem` is re-latched whenever the "WashItem" under
-- the stand changes identity -- a fresh session always gets a brand new instance
-- (WashService.placeOnStand), so this is also what resets the spin to a clean start
-- rather than continuing wherever a previous item left off.
local rotateItem: Instance? = nil
local rotateBase: CFrame = CFrame.identity
local rotateAngle = 0

local inputRemote: any = nil

-- Every other ScreenGui under PlayerGui, put away for the session and given back
-- exactly as found. The shot is first person and full-bleed on purpose (see the
-- header) -- a health bar and a cash badge sitting over a hose-aim view is exactly
-- the "still looks like the overworld" seam the camera cut is meant to erase. Keyed
-- by the instance rather than a name list so a HUD panel added later is covered for
-- free, and so a GUI that happened to be `.Enabled = false` already (nothing here
-- currently starts that way, but nothing guarantees one never will) comes back off
-- rather than being turned on by this file.
local hudGuis: { [ScreenGui]: boolean } = {}

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

--- Turn the item on the stand, and report how far it has turned so a patch's ball can
--- be rotated the same amount (see `spinPoint`). A no-op, cheaply, once no item is on
--- the stand -- the very first tick or two of a session, and every tick after it ends.
local function spinTurntable(dt: number)
	local stand = state and state.stand
	local item = if stand and stand:IsA("BasePart") then stand:FindFirstChild("WashItem") else nil
	if item == nil or not item:IsA("Model") then
		rotateItem = nil
		return
	end

	-- A FRESH instance every session (WashService.placeOnStand always builds a new
	-- one), which is what makes "different item" and "start the spin over" the same
	-- check: latching on identity rather than on `state.uid` also catches the rebuild
	-- a `finish()` -> `begin()` back-to-back produces on the very same item.
	if item ~= rotateItem then
		rotateItem = item
		rotateBase = item:GetPivot()
		rotateAngle = 0
	end

	rotateAngle = (rotateAngle + ROTATE_RATE * dt) % (2 * math.pi)
	local pivotPos = rotateBase.Position
	local spin = CFrame.new(pivotPos) * CFrame.Angles(0, rotateAngle, 0) * CFrame.new(-pivotPos)
	item:PivotTo(spin * rotateBase)
end

--- Carry a patch's own anchor (fixed in the world at the pose the item was PLACED at)
--- around the same turntable spin the item itself just got. Every ball would
--- otherwise stay put while the object span out from under it -- the anchor WashState
--- sends is the item's pose at `placeOnStand`, and this is the only thing that keeps
--- it agreeing with where the real geometry has since turned to.
local function spinPoint(point: Vector3): Vector3
	local pivotPos = rotateBase.Position
	return pivotPos + CFrame.Angles(0, rotateAngle, 0):VectorToWorldSpace(point - pivotPos)
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

--- One piece of water. Every part of the spray is the same recipe -- an unlit, faintly
--- specular, anchored, query-proof primitive -- so the only things the drawing code
--- ever has to write are position, size and transparency.
---
--- CanQuery IS LOAD-BEARING, not hygiene: `aimPointAt` and the per-segment stop rays
--- both cast through this folder, and a jet that raycast against its own first blob
--- would land the water half a stud out of the muzzle every frame.
local function waterPart(name: string, shape: Enum.PartType, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = WATER_REFLECT
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	table.insert(sprayParts, part)
	return part
end

--- Build every part the spray is made of, once. They are parked at the origin until the
--- first frame of spraying moves them; nothing here needs to know where the nozzle is.
---
--- PREALLOCATED, AND THERE ARE A HUNDRED-ODD OF THEM against the old nineteen. What
--- costs anything in a wash session is the per-frame property writes, which is three
--- per part; Instance.new inside a render step is the thing that would actually show up
--- as a hitch, and this is the function that keeps it out of there.
local function ensureSpray()
	if #sheathParts == JET_SEGMENTS and sheathParts[1].Parent ~= nil then
		return
	end
	local parent = ensureFolder()
	table.clear(sprayParts)
	table.clear(sheathParts)
	table.clear(strandTubes)
	table.clear(strandJoints)
	table.clear(dropTubes)
	table.clear(dropHeads)
	table.clear(crownParts)

	for index = 1, JET_SEGMENTS do
		sheathParts[index] = waterPart(`Sheath{index}`, Enum.PartType.Cylinder, parent)
	end
	-- Flat, STRAND_COUNT blocks of JET_SEGMENTS each: strand `s` owns
	-- `s * JET_SEGMENTS + i`. A joint ball sits at the START of every tube, including
	-- the first, where three of them converging is what rounds the muzzle off.
	for index = 1, JET_SEGMENTS * STRAND_COUNT do
		strandTubes[index] = waterPart(`Strand{index}`, Enum.PartType.Cylinder, parent)
		strandJoints[index] = waterPart(`StrandJoint{index}`, Enum.PartType.Ball, parent)
	end
	for index = 1, DROP_COUNT do
		dropTubes[index] = waterPart(`Drop{index}`, Enum.PartType.Cylinder, parent)
		dropHeads[index] = waterPart(`DropHead{index}`, Enum.PartType.Ball, parent)
	end
	for index = 1, CROWN_COUNT do
		crownParts[index] = waterPart(`Crown{index}`, Enum.PartType.Cylinder, parent)
	end

	splashPart = waterPart("Splash", Enum.PartType.Ball, parent)
	local halo = waterPart("SplashHalo", Enum.PartType.Ball, parent)
	-- The one piece of water here with no highlight. A specular on something this faint
	-- and this wide is a soap bubble sitting on the item.
	halo.Reflectance = 0
	haloPart = halo

	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Mist"
	mist.Texture = MIST_TEXTURE
	mist.Enabled = false
	mist.Rate = MIST_RATE
	mist.Lifetime = MIST_LIFE
	mist.Speed = MIST_SPEED
	mist.SpreadAngle = Vector2.new(MIST_SPREAD, MIST_SPREAD)
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-40, 40)
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	-- Never denser than 0.72, anywhere in its life. This is a hint of haze over the
	-- impact, and the moment it is thick enough to READ as smoke it is hiding the item.
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.86),
		NumberSequenceKeypoint.new(0.3, 0.72),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.LightEmission = 0.25
	-- The splash dome carries the emitter and is oriented to the surface normal, whose
	-- LookVector is the part's own -Z -- which is the face `Front` names. So the haze
	-- leaves the surface it landed on rather than the world's up.
	mist.EmissionDirection = Enum.NormalId.Front
	mist.Acceleration = Vector3.new(0, MIST_RISE, 0)
	mist.Parent = splashPart
	mistEmitter = mist

	jetShown = false
end

--- Drop every reference to parts the teardown has already destroyed. Separate from
--- `hideJet` because that one WRITES to them, and writing to a freed instance throws.
local function forgetSpray()
	table.clear(sprayParts)
	table.clear(sheathParts)
	table.clear(strandTubes)
	table.clear(strandJoints)
	table.clear(dropTubes)
	table.clear(dropHeads)
	table.clear(crownParts)
	splashPart = nil
	haloPart = nil
	mistEmitter = nil
	jetShown = false
end

--- How much white is mixed into the liquid at `along`. Water driven through air turns
--- white, and this is the whole reason the far end reads as spray rather than as the
--- same rod it started as.
local function aeration(along: number): number
	return WATER_WHITE_NEAR + (WATER_WHITE_FAR - WATER_WHITE_NEAR) * along
end

--- THE LIQUID'S OWN COLOUR AT THE MUZZLE, AERATING TO NEARLY WHITE AT THE TIP.
---
--- This has swung three times and this is where it belongs. It started tinted only
--- faintly toward the liquid -- true to life, and against a pale steel tub, invisible.
--- So it went hard the other way, most of the way to black, which was legible and
--- looked like oil. Then it went bright and OPAQUE, which was legible and looked like a
--- rope. What none of them had was a gradient with any physics in it: water is the
--- liquid's colour while it is still a solid stream and white once it has broken into
--- air, and running the colour AND the transparency down that same axis is what makes
--- the far end dissolve instead of end.
---
--- Set once per session rather than per frame, because every one of these is a pure
--- function of a part's fixed place along the jet -- only position, size and
--- transparency actually move.
local function applySprayColor(hex: string)
	local liquid = Color3.fromHex(hex)
	local white = Color3.new(1, 1, 1)

	for index, part in sheathParts do
		local along = (index - 0.5) / JET_SEGMENTS
		part.Color = liquid:Lerp(white, math.clamp(aeration(along) + SHEATH_WHITE_BIAS, 0, 1))
	end

	for index, tube in strandTubes do
		local along = (((index - 1) % JET_SEGMENTS) + 0.5) / JET_SEGMENTS
		local colour = liquid:Lerp(white, aeration(along))
		tube.Color = colour
		strandJoints[index].Color = colour
	end

	-- A shed droplet is water that has ALREADY broken up, so it is mostly white wherever
	-- along the jet it left from -- it just keeps a little of the liquid, so a Solvent
	-- wash is not spitting plain foam.
	local spray = white:Lerp(liquid, 0.25)
	for index, tube in dropTubes do
		tube.Color = spray
		dropHeads[index].Color = spray
	end

	-- The impact is all foam, always.
	for _, part in crownParts do
		part.Color = white
	end
	if splashPart then
		splashPart.Color = white:Lerp(liquid, 0.22)
	end
	if haloPart then
		haloPart.Color = white:Lerp(liquid, 0.35)
	end
	if mistEmitter then
		mistEmitter.Color = ColorSequence.new(white:Lerp(liquid, 0.18))
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
---
--- THE TWO SIDEWAYS AXES COME BACK OUT WITH THE PATH, because everything wound around
--- it -- the braid, the shed droplets -- needs the same frame the wobble used, and
--- re-deriving it in each of them is how they end up disagreeing by a cross product.
local function jetPath(from: Vector3, to: Vector3, now: number): ({ Vector3 }, Vector3, Vector3)
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
	return path, side, up
end

--- Lay one tube between two points. Returns false, having hidden it, for a segment
--- short enough that CFrame.lookAt would be looking at its own origin.
local function layTube(part: BasePart, a: Vector3, b: Vector3, radius: number): boolean
	local length = (b - a).Magnitude
	if length < 1e-3 then
		part.Transparency = 1
		return false
	end
	local diameter = radius * 2
	part.Size = Vector3.new(length + TUBE_OVERLAP, diameter, diameter)
	part.CFrame = CFrame.lookAt((a + b) * 0.5, b) * ALONG_Z
	return true
end

local function layBall(part: BasePart, at: Vector3, radius: number)
	local diameter = radius * 2
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = CFrame.new(at)
end

--- Where along the jet droplet `index` is right now. It travels: the whole set slides
--- down the stream together and wraps at the end, which is what makes the break-up read
--- as water leaving the nozzle rather than as a fixed pattern hanging off it.
---
--- The golden ratio staggers them, rather than an even split or a random draw: even
--- puts them in a marching comb, and random re-rolls every frame and makes them
--- flicker. This spreads them without any two ever sitting on top of each other.
local function dropAlong(index: number, now: number): number
	return DROP_START + (1 - DROP_START) * ((index * 0.6180339887 + now * DROP_FLOW) % 1)
end

--- Draw the whole spray along the flight path, stopping at whatever the water hits.
---
--- Returns the point the water actually reached -- the impact if it hit something,
--- the end of the arc if it did not. That point, not the reticle, is what decides
--- which patch is being worked (see `patchAt`): you are cleaning what the water is
--- landing on, which is the only rule a player would ever guess.
local function drawJet(from: Vector3, to: Vector3, filter: RaycastParams): Vector3
	local now = os.clock()
	local path, side, up = jetPath(from, to, now)
	local landing = path[#path]
	-- Hitting nothing means there is no surface to build a splash on, and the splash is
	-- hidden in that case anyway; facing back down the jet is a harmless default that
	-- saves the orientation maths below from having to care.
	local normal = from - landing
	normal = if normal.Magnitude > 1e-3 then normal.Unit else Vector3.yAxis

	-- How many segments survive. Every layer reads it, so the sheath and the braid and
	-- the droplets all end in the same place.
	local reach = JET_SEGMENTS
	local stopped = false

	-- Segment by segment, so the stream stops ON the surface it hits rather than
	-- passing through the tub and out the far side. One short ray per segment is the
	-- same total length as one long ray down the arc, and a straight ray cannot follow
	-- a curve. The segment that hit is then CLIPPED to the contact point, which is what
	-- lets every layer end at the surface without any of them knowing why.
	for index = 1, JET_SEGMENTS do
		local a, b = path[index], path[index + 1]
		local step = b - a
		if step.Magnitude < 1e-3 then
			-- The player is aiming at their own muzzle and the path has collapsed.
			reach = index - 1
			break
		end
		local hit = Workspace:Raycast(a, step, filter)
		if hit then
			landing = hit.Position
			normal = hit.Normal
			path[index + 1] = hit.Position
			reach = index
			stopped = true
			break
		end
	end

	-- HOW MUCH WATER THIS MACHINE THROWS (Config/Gear's `volume`, sent by
	-- WashService.push). Scales the stream and the break-up and NOTHING ELSE -- see
	-- SPLASH_SIZE for why the impact is deliberately left out of it.
	local girth = math.clamp(1 + (math.sqrt(if state and state.volume then state.volume else 1) - 1) * 0.5, 1, JET_GIRTH_MAX)
	local endAlong = reach / JET_SEGMENTS

	-- THE SHEATH: the soft body of the spray, drawn first because everything else sits
	-- inside it.
	for index, part in sheathParts do
		if index > reach then
			part.Transparency = 1
		else
			local along = (index - 0.5) / JET_SEGMENTS
			local radius = (SHEATH_RADIUS_NEAR + (SHEATH_RADIUS_FAR - SHEATH_RADIUS_NEAR) * along ^ SHEATH_FLARE) * girth
			if layTube(part, path[index], path[index + 1], radius) then
				part.Transparency = SHEATH_ALPHA_NEAR + (SHEATH_ALPHA_FAR - SHEATH_ALPHA_NEAR) * along
			end
		end
	end

	-- THE BRAID, turned a little further every frame so the strands appear to spiral
	-- outward from the muzzle. It is the trick a barber's pole plays, and at two studs
	-- from the lens it is the strongest "this is moving fast" cue on screen.
	local swirl = now * STRAND_SWIRL
	for strand = 0, STRAND_COUNT - 1 do
		local phase = swirl + (strand / STRAND_COUNT) * math.pi * 2
		local base = strand * JET_SEGMENTS
		-- Point `k` of this strand, k running 1..JET_SEGMENTS+1 over the same samples
		-- the spine used, wound onto a helix that opens out as it travels.
		local function woundAt(k: number): Vector3
			local fraction = (k - 1) / JET_SEGMENTS
			local angle = phase + fraction * STRAND_TWIST
			local fray = STRAND_FRAY * girth * fraction ^ STRAND_FRAY_POWER
			return path[k] + (side * math.cos(angle) + up * math.sin(angle)) * fray
		end

		for index = 1, JET_SEGMENTS do
			local tube, joint = strandTubes[base + index], strandJoints[base + index]
			if index > reach then
				tube.Transparency = 1
				joint.Transparency = 1
			else
				local a, b = woundAt(index), woundAt(index + 1)
				local along = (index - 0.5) / JET_SEGMENTS
				local radius = STRAND_RADIUS * (1 - STRAND_TAPER * along) * girth
				local alpha = STRAND_ALPHA_NEAR + (STRAND_ALPHA_FAR - STRAND_ALPHA_NEAR) * along ^ STRAND_ALPHA_POWER
				if layTube(tube, a, b, radius) then
					tube.Transparency = alpha
				end
				-- Fills the wedge that opens on the outside of the bend. The braid turns
				-- hard enough per segment that without these a strand is visibly a row of
				-- separate dashes.
				layBall(joint, a, radius)
				joint.Transparency = alpha
			end
		end
	end

	-- THE SHED DROPLETS, each a sliver along its own heading. The ring they sit on turns
	-- with time, so the break-up churns instead of hanging there as a fixed spray of
	-- studs welded to the stream.
	for index = 1, DROP_COUNT do
		local tube, head = dropTubes[index], dropHeads[index]
		local along = dropAlong(index, now)
		if along >= endAlong then
			tube.Transparency = 1
			head.Transparency = 1
		else
			-- Which spine sample this droplet left from, and where between it and the
			-- next one.
			local scaled = along * JET_SEGMENTS
			local lower = math.clamp(math.floor(scaled) + 1, 1, reach)
			local point = path[lower]:Lerp(path[lower + 1], math.clamp(scaled - (lower - 1), 0, 1))

			local angle = index * 2.399 + now * DROP_SPIN
			local out = side * math.cos(angle) + up * math.sin(angle)
			local jitter = 0.5 + math.abs(math.noise(index * 1.7, 3.3))
			point += out * (DROP_SPREAD * girth * along ^ DROP_FRAY_POWER * jitter)

			local tangent = path[lower + 1] - path[lower]
			tangent = if tangent.Magnitude > 1e-3 then tangent.Unit else Vector3.new(0, 0, -1)
			-- Thrown a little wide of the flow it came from, which is what opens the cone
			-- out instead of running the droplets parallel to the stream forever.
			local flow = (tangent + out * (DROP_SPLAY * along)).Unit
			local half = flow * ((DROP_LEN_NEAR + (DROP_LEN_FAR - DROP_LEN_NEAR) * along) * 0.5)
			local radius = DROP_RADIUS * girth
			-- Faint at both ends of its trip, solid in the middle. A droplet that simply
			-- wrapped round to the start at full opacity would pop, once per lap, in the
			-- one place the eye is already watching.
			local trip = (along - DROP_START) / (1 - DROP_START)
			local alpha = DROP_ALPHA_PEAK + (1 - DROP_ALPHA_PEAK) * math.abs(2 * trip - 1) ^ DROP_FADE_POWER

			if layTube(tube, point - half, point + half, radius) then
				tube.Transparency = alpha
			end
			-- A leading head, so the sliver reads as a droplet with a tail rather than as
			-- a stick of water cut off at both ends.
			layBall(head, point + half, radius)
			head.Transparency = alpha
		end
	end

	-- THE IMPACT, built on the surface's own normal. Without something at the end the
	-- eye reads the stream as STOPPING in mid-air rather than as landing on something,
	-- and without the normal it reads as a ball parked in front of the item.
	local surface = CFrame.lookAt(landing, landing + normal)
	local splash, halo, mist = splashPart, haloPart, mistEmitter
	-- Both spheres breathe on the SAME noise, so the spread and the dome inside it move
	-- together: a static cap on a moving one is a ring drawn around a splash.
	local pulse = 1 + SPLASH_PULSE * math.noise(now * 6, 0.5)
	if splash then
		if stopped then
			local size = SPLASH_SIZE * pulse
			splash.Size = Vector3.new(size, size, size)
			-- Pushed INTO the surface so only the cap of the sphere shows. `+Z` is into
			-- it: a lookAt's LookVector is its own -Z, and here that is the way back out
			-- along the normal.
			splash.CFrame = surface * CFrame.new(0, 0, size * 0.5 * SPLASH_SINK)
			splash.Transparency = SPLASH_ALPHA
		else
			splash.Transparency = 1
		end
	end
	if halo then
		if stopped then
			local width = SPLASH_SIZE * SPLASH_HALO * pulse
			halo.Size = Vector3.new(width, width, width)
			-- Sunk deeper than the dome, so what shows is a wide shallow cap of it: the
			-- water spreading out from where the jet is standing on the item.
			halo.CFrame = surface * CFrame.new(0, 0, width * 0.5 * SPLASH_HALO_SINK)
			halo.Transparency = SPLASH_HALO_ALPHA
		else
			halo.Transparency = 1
		end
	end
	for index, part in crownParts do
		if not stopped then
			part.Transparency = 1
		else
			-- Its even share of the ring, knocked off it by a fixed amount. Evenly spaced
			-- is the spoked wheel; jittered is a splash.
			local angle = (index / CROWN_COUNT) * math.pi * 2 + math.noise(index * 4.1, 0.7) * CROWN_JITTER
			-- Mostly ALONG the surface, only a little off it: water hitting a wall runs
			-- outward from the point it hit, and a crown fired straight back at the
			-- camera is a comic-book starburst rather than a splash.
			local out = surface.RightVector * math.cos(angle) + surface.UpVector * math.sin(angle)
			local heading = (out + normal * CROWN_RISE).Unit
			-- Where this one is in its own flight out. Staggered by the golden ratio so
			-- the ring never fires as a ring.
			local trip = (now * CROWN_RATE + index * 0.6180339887) % 1
			local point = landing + heading * (CROWN_INNER + CROWN_REACH * trip)
			-- Fixed per droplet, so no two are the same length. Nine identical slivers
			-- is the spoked wheel again, just a moving one.
			local heft = 0.6 + 0.8 * math.abs(math.noise(index * 2.7, 5.1))
			local half = heading * (CROWN_LEN * heft * 0.5)
			if layTube(part, point - half, point + half, CROWN_RADIUS * heft) then
				part.Transparency = CROWN_ALPHA_PEAK + (1 - CROWN_ALPHA_PEAK) * math.abs(2 * trip - 1) ^ CROWN_FADE_POWER
			end
		end
	end
	if mist then
		mist.Enabled = stopped
	end

	jetShown = true
	return landing
end

--- Cheap when already hidden, which is most frames of a session: the player aims far
--- more than they spray, and a chain of writes to set a transparency that is already
--- 1 is a chain of writes too many.
---
--- The mist is switched OFF rather than cleared, so the last puff finishes fading where
--- it was instead of blinking out the instant the trigger comes up.
local function hideJet()
	if not jetShown then
		return
	end
	for _, part in sprayParts do
		part.Transparency = 1
	end
	if mistEmitter then
		mistEmitter.Enabled = false
	end
	jetShown = false
end

--- Swing the monitor back to where the world put it. Safe to call when no session
--- ever aimed anything (both fields are already nil) and safe to call when the model
--- has been destroyed underneath us (a purchase mid-wash, a World.rebuild) -- a freed
--- Model's Parent is nil, which is the check, and PivotTo on one would throw.
---
--- CALLED ON EVERY EXIT PATH, because the alternative is a machine left permanently
--- staring at wherever the last player happened to be looking. It is a local-only
--- write, so a missed restore is not a world bug -- it is one viewer's plot quietly
--- looking wrong until they rejoin, which is worse, because nobody else can see it to
--- report it.
local function restoreNozzle()
	local model, parked = nozzleModel, nozzleParked
	if model and model.Parent and parked then
		model:PivotTo(parked)
	end
	nozzleModel, nozzleParked = nil, nil
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

--- Put away every OTHER ScreenGui under PlayerGui -- `wipeGui` (this file's own
--- reticle/wipe layer) is the one thing that must stay on, since it is what the
--- session is about to look through.
local function hideHud()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui ~= wipeGui and hudGuis[gui] == nil then
			hudGuis[gui] = gui.Enabled
			gui.Enabled = false
		end
	end
end

--- The exact inverse. Restores whatever `Enabled` actually was rather than stamping
--- `true` on everything, so a GUI that was legitimately hidden going in (nothing
--- does this today, but nothing rules it out) does not pop on because a wash session
--- happened to run.
local function restoreHud()
	for gui, enabled in hudGuis do
		if gui.Parent then
			gui.Enabled = enabled
		end
	end
	table.clear(hudGuis)
end

-- ── Render ──────────────────────────────────────────────────────────

local function paintBlobs()
	if state == nil then
		return
	end

	local live: { [number]: boolean } = {}
	for _, patch in state.patches do
		live[patch.zone] = true

		local blob = blobs[patch.zone]
		if blob == nil or blob.Parent == nil then
			blob = Instance.new("Part")
			blob.Name = `Patch{patch.zone}`
			blob.Shape = Enum.PartType.Ball
			blob.Anchored = true
			blob.CanCollide = false
			blob.CanQuery = false
			blob.Material = Enum.Material.SmoothPlastic
			blob.Parent = ensureFolder()
			blobs[patch.zone] = blob
		end

		-- Harder patches are bigger, so "which one is the wall" is legible before you
		-- ever aim at it. A blocked patch is crusted and matte — the stream visibly
		-- does nothing to it, which is the Quarantine Locker taught in 3D.
		local base = 0.30 + patch.hardness * 0.07
		local scale = base
		if patch.zone == state.targetZone and (state.progress or 0) > 0 then
			scale = base * (1 - 0.65 * state.progress)
		end

		blob.Size = Vector3.new(scale, scale, scale) * 2
		-- WHERE THE SERVER SAYS THE REAL SPOT IS, CARRIED AROUND THE TURNTABLE.
		-- WashService builds this patch's zone from the item's own real geometry (or a
		-- stand-in cluster of blocks for the rarity-coloured fallback) and hands back
		-- its position at the pose the item was PLACED at -- no bounding-box guesswork
		-- here any more, and no reshuffle when an earlier patch clears out from under
		-- this one: `zone` is a stable id, not an array index. `spinPoint` is what
		-- keeps it agreeing with the real geometry once `spinTurntable` starts turning
		-- the item away from that placement pose.
		blob.Position = spinPoint(patch.anchor)
		blob.Color = if patch.blocked then PATCH_CRUSTED else PATCH_GREEN
		blob.Material = if patch.blocked then Enum.Material.Slate else Enum.Material.SmoothPlastic
		blob.Transparency = if patch.blocked then 0.1 else 0.15
	end

	for zone, blob in blobs do
		if not live[zone] then
			blob:Destroy()
			blobs[zone] = nil
		end
	end
end

-- ── Aiming the machine ───────────────────────────────────────────────

--- The monitor this session is pointing. WashService names it in the state payload
--- (re-read every push, so a rung bought mid-wash arrives here as a different model);
--- the fallback re-derives it from the stand's own parent for the one frame before the
--- first payload lands, and for a payload from a server older than the field.
---
--- Returns nil on a place file with no hose rig at all, which is a real degrade rather
--- than an error: the session still runs, the jet just leaves from the fallback origin
--- nozzleCFrame picks.
local function sessionNozzle(): Model?
	local named = state and state.hose
	if named and named:IsA("Model") and named.Parent and named.PrimaryPart then
		return named
	end
	local stand = state and state.stand
	local station = if stand and stand.Parent then stand.Parent else nil
	local found = if station then station:FindFirstChild("Hose") else nil
	if found and found:IsA("Model") and found.PrimaryPart then
		return found
	end
	return nil
end

--- Latch onto whatever nozzle is live, remembering the pose to put it back on. Cheap
--- to call every frame: it does nothing once the model it is holding is still the
--- current one.
---
--- `ParkedPivot` IS READ FROM THE MODEL, NOT MEASURED. The attribute is stamped on by
--- build/Plots and re-stamped by Plots.setHoseTier, and the server never moves the
--- nozzle after that -- so it is the one value that stays true no matter how long this
--- client has been swinging the thing around. Measuring `GetPivot()` instead would
--- capture whatever angle the barrel happened to be at, and after one re-latch (a
--- mid-session upgrade, a rebuild) the machine would park somewhere it was never
--- built to point. The measured value survives only as the fallback for a place file
--- built before the attribute existed, where the nozzle has not been touched yet and
--- so its current pose IS its parked one.
local function latchNozzle(): Model?
	local hose = sessionNozzle()
	if hose == nil then
		nozzleModel, nozzleParked = nil, nil
		return nil
	end
	if hose == nozzleModel then
		return hose
	end
	-- A different model than the one we were holding: put the old one back first, if
	-- it is somehow still alive, then take the new one at whatever it says its rest is.
	restoreNozzle()
	local stamped = hose:GetAttribute("ParkedPivot")
	nozzleModel = hose
	nozzleParked = if typeof(stamped) == "CFrame" then stamped else hose:GetPivot()
	return hose
end

--- Point the barrel at `target`, clamped to the ball joint's cone and eased toward it.
---
--- THE CLAMP IS DONE IN THE PARKED FRAME, not in world space, because the mast is
--- rotated with the plot and every plot sits at a different yaw around the ring. Yaw
--- and pitch are pulled out of the aim direction expressed in the nozzle's own resting
--- axes (-Z forward, the same convention the model is authored in and the same one
--- CFrame.lookAt writes), clamped there, and rebuilt -- so "80 degrees off its rest"
--- means the same thing on all six bases without anyone doing trigonometry per plot.
local function aimNozzle(target: Vector3, dt: number)
	local hose = latchNozzle()
	local parked = nozzleParked
	if hose == nil or parked == nil then
		return
	end

	local origin = parked.Position
	local offset = target - origin
	if offset.Magnitude < 0.05 then
		return
	end

	local rel = parked:VectorToObjectSpace(offset.Unit)
	-- -Z is forward, so a target dead ahead is (0, 0, -1) and both angles come out 0.
	local yaw = math.clamp(math.atan2(rel.X, -rel.Z), -NOZZLE_YAW_LIMIT, NOZZLE_YAW_LIMIT)
	local pitch = math.clamp(math.asin(math.clamp(rel.Y, -1, 1)), -NOZZLE_PITCH_LIMIT, NOZZLE_PITCH_LIMIT)
	local flat = math.cos(pitch)
	local aimed = parked:VectorToWorldSpace(Vector3.new(math.sin(yaw) * flat, math.sin(pitch), -math.cos(yaw) * flat))

	-- Frame-rate independent catch-up: 1 - e^(-k*dt) is the same fraction of the gap
	-- closed per SECOND at any refresh rate, where a plain alpha would swing twice as
	-- fast at 120fps as at 60.
	local goal = CFrame.lookAt(origin, origin + aimed)
	hose:PivotTo(hose:GetPivot():Lerp(goal, 1 - math.exp(-NOZZLE_EASE * dt)))
end

--- Where the water leaves. Every hose carries a real `Muzzle` attachment on its
--- primary part, out at the brass tip (Shared/ToolModels/Hose makes it a contract that
--- World.verify enforces), so the stream starts at the end of the barrel rather than
--- somewhere inside the machine -- and because the barrel is what this file has been
--- swivelling, the muzzle is already pointing wherever the player is.
---
--- THE FALLBACK IS OFF THE PLAYER'S OWN SHOULDER, and it is for a place with no hose
--- rig at all. Water out of nowhere is a bad picture; a session where holding the button
--- does visibly nothing is a worse one, and the clock on the server runs either way. The
--- offset is down and to the right of the eye rather than the head's bare CFrame,
--- because the camera sits AT the head during a wash: a jet starting exactly on the lens
--- is a jet nobody can see.
local function nozzleCFrame(): CFrame?
	local hose = sessionNozzle()
	local core = if hose then hose.PrimaryPart else nil
	if core then
		local muzzle = core:FindFirstChild("Muzzle")
		if muzzle and muzzle:IsA("Attachment") then
			return muzzle.WorldCFrame
		end
		return core.CFrame * CFrame.new(0, 0, -core.Size.Z * 0.5)
	end
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.CFrame * CFrame.new(0.8, -0.9, -0.6)
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

--- Where the camera sits and which way it is facing.
---
--- IT USED TO RETURN A SECOND FRAME, the NEUTRAL one -- the same shot with the
--- player's own look offsets taken back out -- because the held nozzle was placed in
--- the PICTURE rather than in the world, and the picture is what its offset was
--- measured in. A machine bolted to a mast stands where the mast stands, so there is
--- nothing left to compose against and the second return went with the rig.
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
local function eyeCFrame(): CFrame?
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if head == nil or not head:IsA("BasePart") then
		return nil
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
	return CFrame.new(head.Position + rotation.LookVector * EYE_FORWARD) * rotation
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

	-- BEFORE the camera and the blobs, so both read the item's post-turn pose this
	-- frame rather than last frame's.
	spinTurntable(dt)

	local eye = eyeCFrame()
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

	-- Tracks the view continuously, spraying or not — a machine you are standing at the
	-- controls of reads as aimed the moment you look somewhere, not only while it is
	-- live. It is also the only feedback that says the thing is listening to you before
	-- you pull the trigger.
	aimNozzle(aimPoint, dt)

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

	if target ~= aimedZone then
		aimedZone = target
		if inputRemote then
			inputRemote:FireServer({ spraying = spraying, zone = aimedZone })
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
	hideHud()
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
	restoreHud()
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
	aimedZone = nil
	leaving = false
	lookYaw, lookPitch = 0, 0
	padLook = Vector2.zero

	clearBlobs()
	restoreNozzle()
	if folder then
		folder:Destroy()
		folder = nil
	end
	forgetSpray()

	-- Not strictly load-bearing -- `spinTurntable` re-latches on identity the moment a
	-- new WashItem appears regardless -- but holding a reference to a freed instance
	-- between sessions is the kind of thing that looks like a bug later.
	rotateItem = nil
	rotateAngle = 0
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
			inputRemote:FireServer({ spraying = true, zone = aimedZone })
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
			spraying = false
			if state ~= nil then
				inputRemote:FireServer({ spraying = false, zone = aimedZone })
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
