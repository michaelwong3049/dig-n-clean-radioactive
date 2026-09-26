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

	THERE IS NO PATCH FURNITURE IN THIS FILE ANY MORE, AND THAT IS THE BIG ONE.
	It used to draw a green marble over each dirty area — sized by the patch's hardness,
	shrinking on its own soak, keyed by zone id so a surviving patch's ball held still
	when a different one cleared. Every bit of that was a LABEL pointing at an area of an
	object that had nothing visibly wrong with it, because contamination was a green tint
	on the item's own parts and a tint cannot be pointed at.

	The dirt is real geometry now: WashService wraps the item in one chunk of irradiated
	slag per patch (Shared/ItemCrust), and those chunks are the zones. The thing you aim
	at is the thing that is dirty, it erodes under the water on its own bank, and when
	its patch pops it comes off the item and takes part of the mystery with it — because
	what is under there is also what the item IS. A marble drawn on top of that would be
	a label on something that no longer needs one.

	SO THE ZONE ATTRIBUTE IS THE WHOLE MECHANISM. The server stamps `WashZone` on every
	chunk, and "which patch is the water on" is answered by reading the part the impact
	ray already returned (`patchAt`). Aim is a real thing you can miss. `anchor` still
	rides along on every patch for one job: the sub-stud proximity rounding when water
	lands in the gap between two chunks.

	GREEN SURVIVES IN ONE PLACE, the reticle's lock colour (PATCH_GREEN). A contamination
	patch is the SAME SUBSTANCE as the ooze — PLAN §2 step 4 calls them "glowing
	hotspots" — so "the water would count here" is said in the fallout's own colour.

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

	IT USED TO ALSO ORBIT THE MAST'S OWN POSITION, and that was a real bug, not a
	trade. `aimNozzle` swung the barrel on a ball joint fixed at wherever
	build/Plots.buildHoseRig actually bolted the mast -- the tub's near corner, chosen
	to stay clear of the bath and the walk-up (see that file's own note). Measured from
	the player's head, that corner sits 60-70 degrees off the line to the item. The
	swing itself was fine at any angle; the WATER was not, because the jet has to
	physically travel from wherever the muzzle is to wherever the reticle points, and a
	muzzle 65 degrees off to the side means every shot visibly entered from off to one
	side of the screen and swept across to the crosshair -- reported, accurately, as
	"not shooting from the middle." Per-viewer aim is what makes the fix free: `mount`
	is now a point near the CAMERA (`HELD_OFFSET`, rebuilt from `eye` every frame), the
	same real model is pivoted there instead of at the mast, and the muzzle ends up
	close enough to the crosshair that the water reads as coming from where you are
	standing. The mast itself never moves -- a bystander, or the same player before and
	after their own session, still finds the machine parked exactly where the world
	built it.

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

	── v8, THE DENSITY PASS ──────────────────────────────────────────────

	v7 read as WATER but it read as GHOSTLY water. Photographed at the wash mark it
	was a wide pale haze with a couple of faint threads in it -- because the widest,
	most-visible layer, the sheath, is 70-95% transparent, and the strands it was
	meant to have a spine of are 0.05 studs thick wound around an empty centre. And
	the impact it landed with -- a see-through dome, a nearly-invisible wet ring, nine
	faint slivers and a mist you had to look for -- had no force in it. A pressure
	hose hitting an object a metre away does not look like that. Two additions and a
	round of tuning:

	  * IT HAS A CORE NOW. A straight capsule chain down the spine -- not wound like
	    the strands -- 0.09 studs thick and only 8-45% transparent, running the same
	    liquid->white aeration as everything else. This is the "rope of water" the
	    three strands were reaching for and could not be while there was nothing
	    between them. The v7 note argued a solid tube is a pipe; it is right, and the
	    answer is that the core is not alone -- the sheath still softens its edge, the
	    strands still fray off it, the tip still dissolves, and it now SPLITS into
	    backspray where it lands. A rod that shatters on contact is not a pipe.

	  * IT SPLITS ON THE SURFACE. BACKSPRAY -- a couple dozen short slivers flung back
	    off the impact toward the viewer and down and out, on their own brief ballistic
	    arcs, staggered and fading in and out like the shed drops -- plus RIVULETS,
	    thin runs of water sheeting DOWN the face below the contact point. Both are the
	    same discipline v2's fog failed: they live at the impact and nowhere else,
	    the backspray is thrown clear of the item's own silhouette (which sits above
	    and behind the contact point from the eye), and the rivulets are strictly
	    below it. Nothing is added along the length of the cone.

	  * THE IMPACT HITS HARDER. The crown is scattered wide instead of spaced evenly
	    (an even ring is a spoked wheel however many spokes), at half the transparency,
	    thrown further and flatter so it peels along the surface instead of firing
	    back at the lens as a starburst. The dome and the wet ring are opaque enough
	    to actually show. The mist goes from a veil (rate 26) to a burst (rate 88),
	    bigger and slower and drifting DOWN off the surface rather than lifting like
	    campfire smoke -- still never opaque, still only at the impact.

	  * SHADING. WATER_REFLECT is up (a real wet glint is the cheapest "not plastic"
	    cue), knocked back only on the faint wide parts -- the sheath and the dome --
	    where a specular would just sparkle. The muzzle end keeps more of the liquid's
	    own colour (WATER_WHITE_NEAR down) now that there is a coherent core there to
	    show it: Plain Water and Solvent are still told apart at a glance, and more
	    clearly than before.

	── v9, THE BREAK-UP IS PARTICLES AGAIN ─────────────────────────────────

	v8 photographed at the wash mark had three artefacts, and every one of them was a
	PART trying to be spray. The frayed strand tips plus the shed slivers splayed off
	the end of the jet like a hand of white fingers. The splash dome and its halo were
	a glass bubble stuck on the item. The backspray and rivulets were two dozen
	identical capsules raining down its face: pills. A primitive part has a hard,
	countable silhouette however thin or faint it is drawn, and a real break-up is
	hundreds of droplets too small to count.

	So the break-up is ParticleEmitters, and the reason this is not v2's fog is what
	the particles are and where they are. v2 was round dots along the whole cone. These
	are STREAKS (a square stretched along its own velocity by Squash, which is what a
	fast droplet looks like on film), tiny, short-lived, and in two places only:

	  * AT THE IMPACT, a dense fan of streaks thrown off the surface normal at a wide
	    angle, so most of it peels ALONG the face, with drag and gravity so it stalls
	    and rains instead of starbursting across the frame. A few soft beads and the
	    mist ride with it. This replaces the dome, the halo, the crown, the backspray
	    and the rivulets.
	  * OFF THE JET, droplets launched from the muzzle at the jet's own velocity under
	    the jet's own gravity, so they fly the exact ballistic arc the stream is drawn
	    on and die at the landing. Invisible for the first third of their life (the jet
	    is coherent there), then fanned a few degrees off it. This replaces the shed
	    slivers, and because a particle is free once emitted, swinging the nozzle
	    leaves a real trail of water behind instead of dragging a rigid shape.

	The core, sheath and braid stay parts: a solid rope of water is the one thing a
	part draws well. The braid now fades out by STRAND_END, before its fray opens far
	enough to read as fingers. The textures are Studio's own built-ins, so there is no
	asset to upload or moderate.

]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local WashFluidBar = require(script.Parent.Parent.WashFluidBar)
local WashReveal = require(script.Parent.Parent.WashReveal)

local Wash = {}

-- Kit.C.oozeBright. Duplicated rather than required because build/ lives in
-- ServerScriptService and a client cannot reach it — the same reason Tuning.AURA_TAG
-- exists as a shared constant. If the ooze is ever retuned, this follows it.
--
-- IT IS THE RETICLE'S LOCK COLOUR AND NOTHING ELSE NOW. It used to paint the marker
-- balls this file drew over each dirty area; the dirty areas are real chunks of slag
-- on the item itself (WashService.placeOnStand, Shared/ItemCrust), so there is nothing
-- left to paint — but "the water would count here" still needs a colour, and the
-- fallout's own green is the one the player has been taught to read as contamination.
local PATCH_GREEN = Color3.fromHex("6BEE2E")

-- Plain Water, and the only place this file needs a liquid colour of its own: the
-- wipe can start a frame before a payload has been read.
local DEFAULT_LIQUID = "6FD5E8"

-- How far a patch may sit from where the water lands and still be the one being
-- worked, in the FALLBACK case only -- the primary answer is the `WashZone` attribute
-- on the chunk of crust the impact ray hit. It was 2.8 when proximity was the whole
-- mechanism, which on a 1.4-stud item meant every zone was always in range of every
-- impact; this is the width of a gap between two chunks, and nothing more. See
-- `patchAt`.
local PATCH_REACH = 0.9
-- THE AIM POINT IS PINNED TO THE TUB, and this is the fix for water crossing the
-- base. The reach used to be a flat 60 studs: a shot that missed the item -- through
-- the gap beside it, over it, out past the rim within the look clamp -- carried on
-- until it hit whatever plot wall or boundary was downrange, and the ballistic jet
-- was drawn all the way there. Reported, accurately, as "shooting across the map".
--
-- The reach is now "as far as the item on the stand, plus AIM_REACH_PAST", so every
-- drop lands in or right beside the tub. Point at nothing in that cone and the water
-- falls short in mid-air a few studs out -- which banks nothing on the server
-- (`workedIndex` needs a real `WashZone` hit) and is exactly what aiming at nothing
-- should do. AIM_RANGE stays as the ceiling for the degenerate frame where the item
-- cannot be located at all (its pose has not replicated yet); AIM_RANGE_MIN is the
-- floor so that frame still casts a usable ray.
local AIM_REACH_PAST = 3
local AIM_RANGE_MIN = 6
local AIM_RANGE = 60

-- ── The first-person shot ───────────────────────────────────────────
-- Studs the camera sits forward of the head's own centre, along the view. The head is
-- hidden anyway, so this is not about escaping it -- it is about not being able to see
-- the inside of your own shoulders when you pitch all the way down. In Tuning because
-- WashService frames the lump from this same eye (see WASH_FOV below).
local EYE_FORWARD = require(Shared.Config.Tuning).WASH_EYE_FORWARD
-- WIDER THAN THE DEFAULT 70, and it used to be narrower. 60 was a deliberate lean-in
-- chosen when the thing on the stand was the ITEM -- "a stud and a half across", per the
-- note this replaces -- and it made the patches bigger targets for free.
--
-- WHAT SITS THERE NOW IS THE ITEM WRAPPED IN ROCK (Shared/ItemCrust), and the crust is
-- sized off the item rather than off the stand: measured across every authored item it
-- runs two to five studs across and reaches over four studs above the stand. At 60,
-- from six studs away, the bigger ones filled the frame -- so the shot that was framing
-- an object was cropping a boulder, and the station it is standing in went with it.
--
-- 72 IS A DOLLY BACK THE CAMERA CANNOT DO. Backing the eye off is not available: it sits
-- at the character's own head and the head is the one part hidden for the session, so a
-- camera pulled behind it looks at a decapitated torso. Widening the angle buys the same
-- retreat -- everything at the stand comes back about a fifth -- without moving the eye
-- off the face it is supposed to be behind. See HELD_OFFSET for the one thing that had
-- to move with it.
--
-- THE DOLLY BACK IS AVAILABLE AFTER ALL, just not from here: WashService plants the
-- whole player further from the tub when the lump on it is big, so the head (and this
-- lens with it) backs off with them. It reads this same number to do the framing sums,
-- which is why it lives in Tuning. Required inline: this chunk is at the local ceiling.
local WASH_FOV = require(Shared.Config.Tuning).WASH_FOV
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
-- ── Holding the machine, per viewer ──────────────────────────────────
-- WHERE THE NOZZLE APPEARS TO A WASHING PLAYER, relative to their own eye: down and
-- to the side and out in front, the way a held tool sits at the bottom of a first-
-- person frame. NOT the mast's real position -- see the header and the note at
-- `aimNozzle` for why the two had to come apart. ~2 studs off the lens, which is the
-- distance JET_GIRTH_MAX's softening was tuned against (see its own note below), so
-- reusing that number here is what keeps the stream's width looking right rather than
-- introducing a second, disagreeing assumption about how far away the muzzle sits.
--
-- X AND Y MOVED WITH WASH_FOV, and they had to. A held offset is a position in the
-- WORLD, but where it lands on screen is that position divided by the frame the lens
-- cuts -- so widening the angle drags a fixed offset toward the middle of the picture.
-- Left alone at 60's numbers, the FOV change would have walked the nozzle up off the
-- bottom edge and in front of the item. Scaled by tan(36)/tan(30), it holds exactly the
-- screen position it had and only gets smaller, which is the whole point of the change.
--
-- Z DID NOT MOVE, and must not: the 1.7 is shared with JET_GIRTH_MAX, whose softening
-- was tuned against a muzzle roughly two studs off the lens (see its note). Pushing the
-- nozzle further out to shrink it would quietly re-tune the stream's width as well.
local HELD_OFFSET = CFrame.new(0.76, -1.07, -1.7)
-- How fast the barrel chases the aim, per second, as an exponential catch-up. Not
-- instant, and the lag is the point: a nozzle that snapped to the reticle would read
-- as a cursor with a model on it rather than a thing with some weight to swing. At 14
-- it is within a couple of degrees inside a fifth of a second, so it never lags the
-- water anywhere a player would notice -- it only rounds off a whip.
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

-- The jet: a near-solid CORE with a translucent SHEATH around it and three STRANDS
-- braided over it, all laid along the water's real flight path and fraying into flung
-- droplets as it goes. See the header for why it is parts rather than a Beam or a
-- particle cone, for the six shapes this one replaced, and (v8) for why the core came
-- back after v7 deliberately left the centre hollow.
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

-- THE CORE (v8): the near-solid rope of water down the middle of the spine, drawn
-- STRAIGHT rather than wound. This is what v7 left out on the "a solid tube is a pipe"
-- argument -- true, but a pipe does not fray, aerate, or shatter into backspray where
-- it lands, and this one does all three. Tapers from the muzzle to the tip and
-- dissolves on the same aeration curve as everything else. Girth-scaled like the sheath.
--
-- ONE TABLE, NOT A DOZEN loose `local`s: this file's module chunk is close enough to
-- Luau's 200-register-per-function ceiling that the flat style v7 used for every
-- constant no longer has room for another block of it. `CORE` and `SPRAY` are grouped
-- for that reason and nothing deeper.
local CORE = {
	RADIUS_NEAR = 0.092,
	RADIUS_FAR = 0.055,
	-- Solid most of the way, then gone: 0.08 out of the muzzle is 92% opaque, and the
	-- power curve holds it dense until the last third where it aerates into the sheath.
	ALPHA_NEAR = 0.08,
	ALPHA_FAR = 0.46,
	ALPHA_POWER = 1.7,
}

-- THE SHEATH: the soft outer volume of the spray. It is what gives the jet a body
-- without giving it an edge, and the edge is the whole difference between water and a
-- pipe. v8 pulled it IN (a tighter halo hugging the core) and up in density near the
-- muzzle -- v7's wide faint version was the whole reason the stream read as a ghost.
local SHEATH_RADIUS_NEAR = 0.075
local SHEATH_RADIUS_FAR = 0.24
-- The exponent between them: coherent out of the muzzle, then opening. Linear made a
-- cone, and a cone with a hard mouth is a megaphone.
local SHEATH_FLARE = 1.5
local SHEATH_ALPHA_NEAR = 0.52
local SHEATH_ALPHA_FAR = 0.92

-- THE STRANDS: three ropes of water wound around the flight path, together at the
-- muzzle and frayed apart by the tip. The braid ROTATES with time, which is what makes
-- the stream read as moving rather than as a static tapered tube. Thinner since v8 --
-- they are surface texture on the core now, not the only thing there.
local STRAND_COUNT = 3
local STRAND_RADIUS = 0.044
local STRAND_TAPER = 0.30 -- how much thinner a strand is by the far end
local STRAND_TWIST = 5.6 -- radians of winding across the whole flight
local STRAND_SWIRL = 3.0 -- radians per second the whole braid turns
local STRAND_FRAY = 0.185 -- how far off the spine a strand sits at the tip, in studs
local STRAND_FRAY_POWER = 1.8 -- ...and how late in the flight it happens
local STRAND_ALPHA_NEAR = 0.08
-- (v9) How far along the flight the braid has fully faded into the core, and is not
-- drawn past. v8 ran it to the tip at 70% transparent, which is where the fray is
-- widest, and three splayed ropes with a ball on every joint read as white fingers.
local STRAND_END = 0.62
local STRAND_ALPHA_POWER = 1.6

-- AERATION. How much white is mixed into the liquid's own colour at the muzzle and at
-- the tip: water driven through air turns white, and a jet that holds one flat colour
-- end to end is a painted rod. The sheath sits a little BEHIND the strands on this
-- curve so the braid stays the brighter thing inside it. v8 dropped the near value:
-- there is a coherent core at the muzzle now to carry the liquid's own colour, so
-- Plain Water and Solvent read apart more clearly than when the whole muzzle end was
-- already a third of the way to white.
local WATER_WHITE_NEAR = 0.20
local WATER_WHITE_FAR = 0.88
local SHEATH_WHITE_BIAS = -0.10
-- Water is the only thing in this game with a specular highlight, and it is what stops
-- SmoothPlastic from reading as plastic. v8 raised it: the wet glint on the core and
-- the strands is the cheapest "this is water" cue at the range this is shot from. It is
-- knocked back in `ensureSpray` on the parts where a specular only sparkles -- the wide
-- faint sheath and the impact dome.
local WATER_REFLECT = 0.27
local SHEATH_REFLECT = 0.12

-- THE BREAK-UP (v9): every piece of water that is no longer the rope is a particle. See
-- the header for the pills, the bubble and the fingers these replaced, and for why this
-- is not v2's fog. One table for the register-ceiling reason at `CORE`.
--
-- STREAK IS A PLAIN SQUARE, and that is deliberate: stretched along its own velocity
-- (Orientation VelocityParallel, negative Squash) at a few hundredths of a stud, a hard
-- square IS a motion-blurred droplet. Every soft built-in texture tried here turned into
-- a smudge at that size. BEAD is the soft round glow, for the few fat drops in the fan.
--
-- LIGHT_INFLUENCE IS LOW because a lit streak whose face turns from the sun renders
-- nearly black, and a black fleck in a splash is soot. Water in spray is lit from
-- inside by the light it scatters, which is the LIGHT_EMISSION half.
local SPRAY = {
	STREAK = "rbxasset://textures/particles/SquareParticle.png",
	BEAD = "rbxasset://textures/particles/forcefield_glow_main.dds",
	LIGHT_EMISSION = 0.6,
	LIGHT_INFLUENCE = 0.15,
	-- The impact carrier's footprint on the surface, in studs. Emitting from a POINT
	-- sends every streak out of one pixel, and a ring of lines meeting at a pixel is a
	-- cartoon sparkle; a jet a few tenths of a stud wide does not land on a point.
	IMPACT_FOOTPRINT = Vector3.new(0.3, 0.3, 0.02),

	-- THE FAN at the impact. Emitted along the surface normal with a spread wide enough
	-- that most of it leaves nearly flat to the face -- water hitting a wall runs
	-- outward along it -- and DRAG is what keeps it a burst AT the contact point: an
	-- earlier undragged pass at twice the speed flung streaks across the whole tub.
	-- Rates are per unit of girth, so a bigger Cleaner throws a heavier splash.
	FAN_RATE = 320,
	-- Dimmer than the jet drops: three hundred streaks a second crossing on one spot add
	-- up, and at the shared value the middle of the fan glowed like a flash.
	FAN_EMISSION = 0.4,
	FAN_SPEED = NumberRange.new(2.5, 7.5),
	FAN_LIFE = NumberRange.new(0.12, 0.34),
	FAN_SPREAD = 78,
	FAN_DRAG = 4,
	FAN_SIZE = NumberSequence.new(0.03, 0.018),
	FAN_STRETCH = NumberSequence.new(-2.6, -1.8),
	FAN_ALPHA = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	}),
	-- Studs/s^2 down. Steeper than the jet's own, so the fan rains off the face fast.
	GRAVITY = 45,

	BEAD_RATE = 140,
	BEAD_SPEED = NumberRange.new(3, 8),
	BEAD_LIFE = NumberRange.new(0.16, 0.38),
	BEAD_DRAG = 1.5,
	-- Small, faint and barely lit. A first pass at twice this size and full opacity was a
	-- glowing white ball on the impact, which is the v8 dome all over again.
	BEAD_SIZE = NumberSequence.new(0.07, 0.03),
	BEAD_STRETCH = NumberSequence.new(-0.8, -0.4),
	BEAD_ALPHA = NumberSequence.new(0.35, 1),
	BEAD_EMISSION = 0.3,

	-- THE JET DROPS: launched at the muzzle along the jet's own launch velocity, under
	-- JET_GRAVITY, so they fly the stream's arc exactly. Lifetime is set every frame to
	-- the flight time to wherever the water is landing, less up to LIFE_SHORT of it, so
	-- none of them sail on through the item. Invisible until a third of the way out:
	-- water leaves a nozzle coherent.
	JET_RATE = 160,
	JET_SPREAD = 3.5, -- degrees off the stream
	JET_SPEED_JITTER = NumberRange.new(0.96, 1.03), -- x the launch speed
	JET_LIFE_SHORT = 0.15,
	JET_SIZE = NumberSequence.new(0.015, 0.03),
	JET_STRETCH = NumberSequence.new(-2.8),
	JET_ALPHA = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(0.9, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	}),
}

-- THE MIST. The one thing here the particle version also had, and the reason it is
-- safe now is that it is ONLY at the impact: it was the cone-length version that
-- buried the item being washed. Still impact-only, still never opaque -- v8 just turned
-- a thin veil into an actual burst: more of it, bigger, slower, and drifting DOWN off
-- the surface rather than lifting like campfire smoke, with a little Drag so it puffs
-- and stalls instead of streaking away. v9 halved it again: next to the streak fan the
-- v8 burst read as a dust cloud, and the fan now carries the force it was there for.
local MIST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local MIST_RATE = 40
local MIST_GROW = 0.5 -- studs across at the end of a puff's life
local MIST_LIFE = NumberRange.new(0.3, 0.6)
local MIST_SPEED = NumberRange.new(1.5, 3.8)
local MIST_SPREAD = 58
local MIST_DRIFT = -3 -- studs/s^2 on world Y: negative, so the haze rolls DOWN off the surface
local MIST_DRAG = 2


-- ── The turntable ───────────────────────────────────────────────────
-- The item spins in place on the stand whenever the hose is OFF, so a patch on the far
-- side is not simply unreachable from a fixed first-person view -- it comes around.
-- Holding the spray stops it, so the patch under the stream stays put while you scrub
-- it; letting go starts it turning again. `RATE` is radians per second around a
-- WORLD-vertical axis through the item's own placement point, deliberately not the
-- item's own up axis: several items sit tilted for the camera ("Wash" rotation,
-- ItemModels), and spinning around a tilted axis wobbles like a dropped coin instead
-- of turning like it is on a turntable.
--
-- `speed` is the live 0..1 throttle on RATE, eased rather than switched so the stop
-- and the restart read as a motor braking and spinning up, not a frame skip. The stop
-- is quick (you pressed to aim at THAT spot), the restart a touch softer. Seconds, as
-- exponential time constants. A table for the register-ceiling reason at `CORE`.
local TURNTABLE = {
	RATE = math.rad(32),
	STOP_EASE = 0.08,
	START_EASE = 0.25,
	speed = 1,
}

local state: any = nil
local folder: Instance? = nil
-- The spray, preallocated once by `ensureSpray` and only moved from then on.
-- `sprayParts` is every one of them flat, and exists so the hide and teardown paths do
-- not have to know the layout.
local coreTubes: { BasePart } = {}
local sheathParts: { BasePart } = {}
local strandTubes: { BasePart } = {}
local strandJoints: { BasePart } = {}
local sprayParts: { BasePart } = {}
-- (v9) The break-up. Two invisible carriers -- one parked on the landing facing out
-- along the surface normal, one at the muzzle facing along the launch -- and every
-- emitter on them, flat in `sprayEmitters` for the same reason as `sprayParts`.
local impactPart: BasePart? = nil
local muzzlePart: BasePart? = nil
local jetDrops: ParticleEmitter? = nil
local sprayEmitters: { ParticleEmitter } = {}
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

-- The stand we made see-through to rays, and what it was before. See `openTheStand`.
local standOpened: BasePart? = nil
local standWasQueryable = true

local inputRemote: any = nil

-- Every other ScreenGui under PlayerGui, put away for the session and given back
-- exactly as found. The shot is first person and full-bleed on purpose (see the
-- header) -- a health bar and a cash badge sitting over a hose-aim view is exactly
-- the "still looks like the overworld" seam the camera cut is meant to erase. Keyed
-- by the instance rather than a name list so a HUD panel added later is covered for
-- free, and so a GUI that happened to be `.Enabled = false` already (nothing here
-- currently starts that way, but nothing guarantees one never will) comes back off
-- rather than being turned on by this file.
local hudGuis: { [LayerCollector]: boolean } = {}

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
		TURNTABLE.speed = 1
	end

	-- The reveal's kick-round wins over a held trigger: the wash is over by then, and a
	-- player still holding the button should not freeze the show.
	local held = spraying and not WashReveal.active()
	local tau = if held then TURNTABLE.STOP_EASE else TURNTABLE.START_EASE
	TURNTABLE.speed += ((if held then 0 else 1) - TURNTABLE.speed) * (1 - math.exp(-dt / tau))

	local rate = TURNTABLE.RATE * TURNTABLE.speed * WashReveal.spinRate()
	rotateAngle = (rotateAngle + rate * dt) % (2 * math.pi)
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

--- An invisible carrier for emitters. Not in `sprayParts`: nothing ever draws it, so
--- there is nothing for `hideJet` to hide.
local function carrierPart(name: string, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.05, 0.05, 0.05)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

--- One emitter of the break-up. Everything shared by all four is here; the caller
--- sets what makes it a fan, a bead, a jet drop or the mist.
local function sprayEmitter(name: string, texture: string, parent: Instance): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = texture
	emitter.Enabled = false
	-- The carriers are oriented so their own -Z is the way the water leaves: the surface
	-- normal at the impact, the launch direction at the muzzle. `Front` names -Z.
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.LightEmission = SPRAY.LIGHT_EMISSION
	emitter.LightInfluence = SPRAY.LIGHT_INFLUENCE
	emitter.Parent = parent
	table.insert(sprayEmitters, emitter)
	return emitter
end

--- Build every part the spray is made of, once. They are parked at the origin until the
--- first frame of spraying moves them; nothing here needs to know where the nozzle is.
---
--- PREALLOCATED, AND THERE ARE NINETY-SIX OF THEM against the old nineteen. What
--- costs anything in a wash session is the per-frame property writes, which is three
--- per part; Instance.new inside a render step is the thing that would actually show up
--- as a hitch, and this is the function that keeps it out of there.
local function ensureSpray()
	if #sheathParts == JET_SEGMENTS and sheathParts[1].Parent ~= nil then
		return
	end
	local parent = ensureFolder()
	table.clear(sprayParts)
	table.clear(coreTubes)
	table.clear(sheathParts)
	table.clear(strandTubes)
	table.clear(strandJoints)
	table.clear(sprayEmitters)

	-- THE CORE (v8): one straight cylinder per spine segment. No joint balls -- unlike
	-- the wound strands the spine only bends by the arc's own gentle sag over twelve
	-- steps, and TUBE_OVERLAP plus the sheath around it cover that with room to spare.
	for index = 1, JET_SEGMENTS do
		coreTubes[index] = waterPart(`Core{index}`, Enum.PartType.Cylinder, parent)
	end
	for index = 1, JET_SEGMENTS do
		local sheath = waterPart(`Sheath{index}`, Enum.PartType.Cylinder, parent)
		-- A specular on the wide faint sheath just sparkles -- the glint belongs on the
		-- core and the strands inside it. See WATER_REFLECT / SHEATH_REFLECT.
		sheath.Reflectance = SHEATH_REFLECT
		sheathParts[index] = sheath
	end
	-- Flat, STRAND_COUNT blocks of JET_SEGMENTS each: strand `s` owns
	-- `s * JET_SEGMENTS + i`. A joint ball sits at the START of every tube, including
	-- the first, where three of them converging is what rounds the muzzle off.
	for index = 1, JET_SEGMENTS * STRAND_COUNT do
		strandTubes[index] = waterPart(`Strand{index}`, Enum.PartType.Cylinder, parent)
		strandJoints[index] = waterPart(`StrandJoint{index}`, Enum.PartType.Ball, parent)
	end

	-- THE BREAK-UP (v9). See SPRAY.
	local impact = carrierPart("Impact", parent)
	impact.Size = SPRAY.IMPACT_FOOTPRINT
	impactPart = impact
	local muzzle = carrierPart("Muzzle", parent)
	muzzlePart = muzzle

	local fan = sprayEmitter("Fan", SPRAY.STREAK, impact)
	fan.Orientation = Enum.ParticleOrientation.VelocityParallel
	fan.Rate = SPRAY.FAN_RATE
	fan.Lifetime = SPRAY.FAN_LIFE
	fan.Speed = SPRAY.FAN_SPEED
	fan.SpreadAngle = Vector2.new(SPRAY.FAN_SPREAD, SPRAY.FAN_SPREAD)
	fan.Drag = SPRAY.FAN_DRAG
	fan.Acceleration = Vector3.new(0, -SPRAY.GRAVITY, 0)
	fan.Size = SPRAY.FAN_SIZE
	fan.Squash = SPRAY.FAN_STRETCH
	fan.Transparency = SPRAY.FAN_ALPHA
	fan.LightEmission = SPRAY.FAN_EMISSION

	local bead = sprayEmitter("Bead", SPRAY.BEAD, impact)
	bead.Orientation = Enum.ParticleOrientation.VelocityParallel
	bead.Rate = SPRAY.BEAD_RATE
	bead.Lifetime = SPRAY.BEAD_LIFE
	bead.Speed = SPRAY.BEAD_SPEED
	bead.SpreadAngle = Vector2.new(SPRAY.FAN_SPREAD, SPRAY.FAN_SPREAD)
	bead.Drag = SPRAY.BEAD_DRAG
	bead.Acceleration = Vector3.new(0, -SPRAY.GRAVITY, 0)
	bead.Size = SPRAY.BEAD_SIZE
	bead.Squash = SPRAY.BEAD_STRETCH
	bead.Transparency = SPRAY.BEAD_ALPHA
	bead.LightEmission = SPRAY.BEAD_EMISSION

	local drops = sprayEmitter("JetDrops", SPRAY.STREAK, muzzle)
	drops.Orientation = Enum.ParticleOrientation.VelocityParallel
	drops.Rate = SPRAY.JET_RATE
	drops.SpreadAngle = Vector2.new(SPRAY.JET_SPREAD, SPRAY.JET_SPREAD)
	drops.Acceleration = Vector3.new(0, -JET_GRAVITY, 0)
	drops.Size = SPRAY.JET_SIZE
	drops.Squash = SPRAY.JET_STRETCH
	drops.Transparency = SPRAY.JET_ALPHA
	jetDrops = drops

	local mist = sprayEmitter("Mist", MIST_TEXTURE, impact)
	mist.Rate = MIST_RATE
	mist.Lifetime = MIST_LIFE
	mist.Speed = MIST_SPEED
	mist.SpreadAngle = Vector2.new(MIST_SPREAD, MIST_SPREAD)
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-40, 40)
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, MIST_GROW),
	})
	-- Never denser than 0.6, anywhere in its life -- v8 took it down from 0.72, which is
	-- still translucent: the moment it is thick enough to READ as solid smoke it is
	-- hiding the item, and it sits dead centre of frame.
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.25, 0.58),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.LightEmission = 0.34
	mist.LightInfluence = 1
	mist.Drag = MIST_DRAG
	-- Down, not up: pressure spray rolls off a surface and rains, it does not lift like
	-- the campfire-smoke default this texture came with.
	mist.Acceleration = Vector3.new(0, MIST_DRIFT, 0)

	jetShown = false
end

--- Drop every reference to parts the teardown has already destroyed. Separate from
--- `hideJet` because that one WRITES to them, and writing to a freed instance throws.
local function forgetSpray()
	table.clear(sprayParts)
	table.clear(coreTubes)
	table.clear(sheathParts)
	table.clear(strandTubes)
	table.clear(strandJoints)
	table.clear(sprayEmitters)
	impactPart = nil
	muzzlePart = nil
	jetDrops = nil
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

	-- The core carries the liquid's own colour furthest -- it is the coherent part, and
	-- (v8) the reason WATER_WHITE_NEAR could come down: a Solvent wash is visibly green
	-- here where a v7 stream was already half white by the muzzle.
	for index, tube in coreTubes do
		local along = (index - 0.5) / JET_SEGMENTS
		tube.Color = liquid:Lerp(white, aeration(along))
	end

	for index, tube in strandTubes do
		local along = (((index - 1) % JET_SEGMENTS) + 0.5) / JET_SEGMENTS
		local colour = liquid:Lerp(white, aeration(along))
		tube.Color = colour
		strandJoints[index].Color = colour
	end

	-- (v9) Everything that has broken up is mostly white, keeping a little of the liquid
	-- so a Solvent wash is not spitting plain foam. The impact fan and the mist are the
	-- most aerated, the fat beads and the drops off the jet a touch less.
	local tint = { Fan = 0.18, Bead = 0.25, JetDrops = 0.25, Mist = 0.18 }
	for _, emitter in sprayEmitters do
		emitter.Color = ColorSequence.new(white:Lerp(liquid, tint[emitter.Name] or 0.2))
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
--- The launch velocity and the flight time come back out too (v9): the jet drops are
--- fired along that same launch, which is how they fly the arc without being told it.
local function jetPath(from: Vector3, to: Vector3, now: number): ({ Vector3 }, Vector3, Vector3, Vector3, number)
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
	return path, side, up, launch, flight
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


--- Walk a flight path until the water hits something, and say where and on what.
--- CLIPS THE PATH at the contact point, so every layer `drawJet` lays along it after
--- this ends on the surface without any of them having to know why.
---
--- One short ray per segment rather than one long ray down the arc: the total length
--- is the same, and a straight ray cannot follow a curve. Twelve of them is cheap
--- enough to run on a frame where nothing is being drawn at all, which is the whole
--- reason this is its own function -- see `onRender`. A reticle that reports the SIGHT
--- while the trigger is up and the WATER once it is down is a reticle that lies to you
--- for exactly as long as it takes to line a shot up: the arc sags the better part of
--- a stud over a wash bay, so "green ring, then the stream lands under the patch" was
--- a reproducible way to waste a canister.
--- Returns, in order: where the water stopped, the part it stopped on, THAT SURFACE'S
--- OWN NORMAL, how many segments of the path survive, and whether it hit anything at
--- all. The normal is passed out rather than re-derived from the flight direction --
--- see the note on the impact dome for why the surface's normal and the reverse of the
--- water's approach are not interchangeable.
local function traceJet(path: { Vector3 }, filter: RaycastParams): (Vector3, BasePart?, Vector3?, number, boolean)
	for index = 1, JET_SEGMENTS do
		local a, b = path[index], path[index + 1]
		local step = b - a
		if step.Magnitude < 1e-3 then
			-- The player is aiming at their own muzzle and the path has collapsed.
			return a, nil, nil, index - 1, false
		end
		local hit = Workspace:Raycast(a, step, filter)
		if hit then
			path[index + 1] = hit.Position
			return hit.Position, hit.Instance, hit.Normal, index, true
		end
	end
	return path[#path], nil, nil, JET_SEGMENTS, false
end

--- Draw the whole spray along the flight path, stopping at whatever the water hits.
---
--- Returns the point the water actually reached -- the impact if it hit something,
--- the end of the arc if it did not -- and the part it landed on, nil if it landed on
--- nothing. Those two, not the reticle, are what decide which patch is being worked
--- (see `patchAt`): you are cleaning what the water is landing on, which is the only
--- rule a player would ever guess from watching it.
local function drawJet(from: Vector3, to: Vector3, filter: RaycastParams): (Vector3, BasePart?)
	local now = os.clock()
	local path, side, up, launch, flight = jetPath(from, to, now)
	-- WHAT THE WATER IS STANDING ON, and how many segments of it survive to get there.
	-- Every layer below reads `reach`, so the sheath and the braid and the droplets all
	-- end in the same place. `struck` is handed back to the caller: `patchAt` reads that
	-- part's own `WashZone` attribute (WashService stamps one on every piece of the item
	-- belonging to a patch), which is how "you are cleaning what you are hitting" became
	-- literally true instead of nearest-ball-within-three-studs.
	local landing, struck, surfaceNormal, reach, stopped = traceJet(path, filter)

	-- Hitting nothing means there is no surface to build a splash on, and the splash is
	-- hidden in that case anyway; facing back down the jet is a harmless default that
	-- saves the orientation maths below from having to care.
	local normal = if surfaceNormal then surfaceNormal else from - landing
	normal = if normal.Magnitude > 1e-3 then normal.Unit else Vector3.yAxis

	-- HOW MUCH WATER THIS MACHINE THROWS (Config/Gear's `volume`, sent by
	-- WashService.push). Scales the stream's width and how much spray it throws, and
	-- NOTHING ELSE: the droplets themselves stay the same size, because a bigger machine
	-- throws more water, not bigger drops.
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

	-- THE CORE (v8): one straight cylinder per spine segment -- no winding, no fray. It is
	-- the solid part, so it is drawn nearly opaque and only aerates out near the tip.
	for index, tube in coreTubes do
		if index > reach then
			tube.Transparency = 1
		else
			local along = (index - 0.5) / JET_SEGMENTS
			local radius = (CORE.RADIUS_NEAR + (CORE.RADIUS_FAR - CORE.RADIUS_NEAR) * along) * girth
			if layTube(tube, path[index], path[index + 1], radius) then
				tube.Transparency = CORE.ALPHA_NEAR + (CORE.ALPHA_FAR - CORE.ALPHA_NEAR) * along ^ CORE.ALPHA_POWER
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
			local along = (index - 0.5) / JET_SEGMENTS
			if index > reach or along >= STRAND_END then
				tube.Transparency = 1
				joint.Transparency = 1
			else
				local a, b = woundAt(index), woundAt(index + 1)
				local radius = STRAND_RADIUS * (1 - STRAND_TAPER * along) * girth
				local alpha = STRAND_ALPHA_NEAR + (1 - STRAND_ALPHA_NEAR) * (along / STRAND_END) ^ STRAND_ALPHA_POWER
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

	-- THE BREAK-UP (v9). The carriers only move: every emitter on them was configured
	-- once in `ensureSpray`, and what changes per frame is where they are, which way they
	-- face, how much the machine throws, and how long a jet drop has to live.
	local impact, muzzle, drops = impactPart, muzzlePart, jetDrops
	if impact then
		-- Facing out along the surface normal: the fan, the beads and the mist all leave
		-- the face the water landed on, not the world's up.
		impact.CFrame = CFrame.lookAt(landing, landing + normal)
	end
	if muzzle and launch.Magnitude > 1e-3 then
		muzzle.CFrame = CFrame.lookAt(from, from + launch)
	end
	if drops then
		local speed = launch.Magnitude
		drops.Speed = NumberRange.new(speed * SPRAY.JET_SPEED_JITTER.Min, speed * SPRAY.JET_SPEED_JITTER.Max)
		-- The path's samples are equal slices of flight TIME, so the time to wherever
		-- the water stopped is the same fraction of the flight as `reach` is of the path.
		local life = math.max(flight * endAlong, 0.05)
		drops.Lifetime = NumberRange.new(life * (1 - SPRAY.JET_LIFE_SHORT), life)
		drops.Rate = SPRAY.JET_RATE * girth
	end
	for _, emitter in sprayEmitters do
		if emitter == drops then
			emitter.Enabled = true
		else
			-- Nothing to splash on when the water fell short in mid-air.
			emitter.Enabled = stopped
			if emitter.Name == "Fan" then
				emitter.Rate = SPRAY.FAN_RATE * girth
			elseif emitter.Name == "Bead" then
				emitter.Rate = SPRAY.BEAD_RATE * girth
			end
		end
	end

	jetShown = true
	return landing, struck
end

--- Cheap when already hidden, which is most frames of a session: the player aims far
--- more than they spray, and a chain of writes to set a transparency that is already
--- 1 is a chain of writes too many.
---
--- The emitters are switched OFF rather than cleared, so the last of the spray already
--- in the air finishes its flight instead of blinking out the instant the trigger comes
--- up -- which is what a real hose does when you let go of it.
local function hideJet()
	if not jetShown then
		return
	end
	for _, part in sprayParts do
		part.Transparency = 1
	end
	for _, emitter in sprayEmitters do
		emitter.Enabled = false
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
	-- And no notch inset, for the same two reasons (UIKit's "The notch"): the reticle
	-- marks the camera's own centre, and the wipe has to cover the whole screen. The
	-- two corner widgets add the inset back themselves.
	gui.ScreenInsets = Enum.ScreenInsets.None
	-- Above everything, including the death screen (DeathScreen, 120). A transition
	-- that something else can draw on top of is not covering the cut it exists to hide.
	gui.DisplayOrder = 200
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = playerGui
	wipeGui = gui
	-- The scaled canvas (UIKit.canvas). Everything below is centred or edge-anchored by
	-- Scale, so the reticle still sits dead on the look ray at any HUD scale.
	local canvas = UIKit.canvas(gui)

	-- ── The reticle ──
	local sight = Instance.new("Frame")
	sight.Name = "Reticle"
	sight.Size = UDim2.fromOffset(RETICLE_BOX, RETICLE_BOX)
	sight.Position = UDim2.fromScale(0.5, 0.5)
	sight.AnchorPoint = Vector2.new(0.5, 0.5)
	sight.BackgroundTransparency = 1
	sight.Visible = false
	sight.ZIndex = 1
	sight.Parent = canvas
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

	-- ── The clean bar ──
	-- Bottom-centre, and it answers both "how clean is the ITEM" (not any one patch) and
	-- "what am I spraying": a striped pill filled with the loaded fluid's own colour,
	-- the fluid's name and charges left on its top-left, a bottle on its end that drains
	-- as the canister does. The wash pad's own billboard readout (LiquidController) is
	-- hidden with the rest of the HUD for the session, so this is the only fluid cue
	-- inside the shot. All of it lives in WashFluidBar; this file only feeds and shows it.
	WashFluidBar.mount(canvas)

	-- ── The wipe panel ──
	-- Parked off the RIGHT edge, which is where every completed sweep leaves it.
	local panel = Instance.new("Frame")
	panel.Name = "Wipe"
	panel.Size = UDim2.fromScale(1, 1)
	panel.Position = UDim2.fromScale(1, 0)
	panel.BackgroundColor3 = UIKit.C.panel
	panel.BorderSizePixel = 0
	panel.ZIndex = 10
	panel.Parent = canvas
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

--- Put away every OTHER GUI layer under PlayerGui -- `wipeGui` (this file's own
--- reticle/wipe layer) is the one thing that must stay on, since it is what the
--- session is about to look through.
---
--- LayerCollector, not ScreenGui: any client BillboardGui under PlayerGui hangs in the
--- world where the shot can see it. This view shows the fluid on its own clean bar
--- (WashFluidBar) instead.
local function hideHud()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("LayerCollector") and gui ~= wipeGui and hudGuis[gui] == nil then
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

--- LET THE RAYS THROUGH THE PEDESTAL, for the length of the session.
---
--- WashStand is a one-stud marker part with Transparency 1 and CanQuery TRUE, and the
--- item is pivoted to its CENTRE — so the invisible box does not sit under the item,
--- it ENCLOSES it. Every aim ray and every drop of water stopped dead on a box nobody
--- can see, half a stud before reaching the thing being washed.
---
--- THAT IS WHY AIM NEVER MATTERED. The old `patchAt` took the nearest blob within 2.8
--- studs of wherever the water stopped, so stopping on the invisible box counted as
--- hitting whatever was inside it, and the feature appeared to work while being
--- physically nonsense: point anywhere near the pedestal, hold the button, watch the
--- item clean itself. Reading the zone off the part the ray actually hit only means
--- something if the ray can get to the item at all.
---
--- CLIENT-LOCAL AND RESTORED, rather than fixed where the marker is built. CanQuery on
--- an invisible marker is arguably wrong in build/Plots too, but that is world geometry
--- outside the place file's git history: changing it there does nothing until someone
--- runs a World.rebuild() by hand (see ARCHITECTURE.md). This is the same per-viewer
--- trade the spray and the nozzle aim already make, and it costs one property write.
local function openTheStand(stand: BasePart?)
	if standOpened ~= nil and standOpened ~= stand then
		if standOpened.Parent ~= nil then
			standOpened.CanQuery = standWasQueryable
		end
		standOpened = nil
	end
	if stand == nil or standOpened == stand then
		return
	end
	standWasQueryable = stand.CanQuery
	stand.CanQuery = false
	standOpened = stand
end

--- Give it back. Idempotent, and safe on a stand that has been destroyed underneath us
--- by a World.rebuild mid-session — a freed part's Parent is nil, which is the check.
local function closeTheStand()
	local stand = standOpened
	standOpened = nil
	if stand ~= nil and stand.Parent ~= nil then
		stand.CanQuery = standWasQueryable
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

--- Point the barrel at `target` from `mount`, eased toward it.
---
--- `mount` USED TO BE THE MAST'S OWN FIXED WORLD POSITION -- `nozzleParked.Position`,
--- read once at session start and never moved -- with the swing clamped to a ball-
--- joint cone around it. That was the bug the whole rework exists to fix: the mast
--- sits at the tub's near corner (build/Plots.buildHoseRig), which measures out to
--- 60-70 degrees off the player's own line to the item. A ball joint out there can
--- point wherever it likes; the WATER still has to travel that whole angle to reach
--- the reticle, which is what "shooting from the left" actually was -- not a bug in
--- the aim maths (the arc genuinely converges on the aim point every time), but the
--- water visibly entering from a machine bolted 65 degrees off to the side of where
--- the player is looking, every single shot.
---
--- `mount` IS NOW A POINT NEAR THE CAMERA instead (`onRender` builds it fresh every
--- frame from `eye * HELD_OFFSET`), so this just points the model at the target from
--- there -- no clamp, because a point that already rides the camera never needs one:
--- the old cone existed to keep a FIXED-origin ball joint from winding up staring at
--- its own plumbing, and an origin that moves with the view has nothing to wind up
--- against. The real mast stays exactly where it was for anyone not washing -- see
--- the header and `restoreNozzle` -- this only ever moves the copy the washing
--- player's own client is looking at.
local function aimNozzle(mount: CFrame, target: Vector3, dt: number)
	local hose = latchNozzle()
	if hose == nil then
		return
	end

	local offset = target - mount.Position
	if offset.Magnitude < 0.05 then
		return
	end

	-- Frame-rate independent catch-up: 1 - e^(-k*dt) is the same fraction of the gap
	-- closed per SECOND at any refresh rate, where a plain alpha would swing twice as
	-- fast at 120fps as at 60.
	local goal = CFrame.lookAt(mount.Position, target)
	hose:PivotTo(hose:GetPivot():Lerp(goal, 1 - math.exp(-NOZZLE_EASE * dt)))
end

--- Where the water leaves. Every hose carries a real `Muzzle` attachment on its
--- primary part, out at the brass tip (Shared/ToolModels/Hose makes it a contract that
--- World.verify enforces), so the stream starts at the end of the barrel rather than
--- somewhere inside the machine -- and because `aimNozzle` already pivoted the model
--- to `mount` and pointed it at the target THIS SAME FRAME, the muzzle is already
--- sitting near the camera and pointing wherever the player is, not out at the mast.
---
--- THE FALLBACK IS `mount` ITSELF, for a place with no hose rig at all -- the same
--- point the model would have been pivoted to, had there been a model. Water out of
--- nowhere is a bad picture; a session where holding the button does visibly nothing
--- is a worse one, and the clock on the server runs either way.
local function nozzleCFrame(mount: CFrame): CFrame?
	local hose = sessionNozzle()
	local core = if hose then hose.PrimaryPart else nil
	if core then
		local muzzle = core:FindFirstChild("Muzzle")
		if muzzle and muzzle:IsA("Attachment") then
			return muzzle.WorldCFrame
		end
		return core.CFrame * CFrame.new(0, 0, -core.Size.Z * 0.5)
	end
	return mount
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
--- The jet segments are all CanQuery = false, so this never hits the
--- effects themselves -- it finds the ITEM under the blob, which is where the
--- contamination is anyway. The character is filtered out because the ray starts
--- inside the player's own head.
local function aimPointAt(from: CFrame, filter: RaycastParams): (Vector3, BasePart?)
	-- Reach only as far as the item on the stand, plus a little -- never the whole
	-- 60 studs. See AIM_REACH_PAST for why: past that the water was flying across the
	-- base. `ahead` is the item's distance projected onto the view, so looking a touch
	-- off the item still clamps to roughly the item's own range rather than the sky.
	--
	-- ...OR PAST HALF THE LUMP, whichever is further. A big payload roll puts a lump
	-- on the rack wider than AIM_REACH_PAST is deep (WashService.placeOnStand), and a
	-- shot at its far flank has to reach that far or the flank cannot be washed. Every
	-- ordinary lump is narrower, so for them nothing changes.
	local pivot, size = itemPivot()
	local reach = AIM_RANGE
	if pivot and size then
		local ahead = (pivot.Position - from.Position):Dot(from.LookVector)
		local past = math.max(AIM_REACH_PAST, math.max(size.X, size.Z) * 0.5)
		reach = math.clamp(ahead + past, AIM_RANGE_MIN, AIM_RANGE)
	end
	local hit = Workspace:Raycast(from.Position, from.LookVector * reach, filter)
	if hit then
		return hit.Position, hit.Instance
	end
	return from.Position + from.LookVector * reach, nil
end

--- Is that zone still a patch at all? The server's own list is the authority on what is
--- standing; it used to be answered by "does a marker ball exist for this zone", which
--- was the same question asked of furniture this file no longer owns.
local function livePatch(zone: number): boolean
	for _, patch in (state and state.patches) or {} do
		if patch.zone == zone then
			return true
		end
	end
	return false
end

--- Which patch is being worked: THE ONE THE WATER PHYSICALLY LANDED ON.
---
--- Not the one nearest the reticle, and not the one nearest the impact either. The
--- stream is a falling arc that leaves a nozzle held below the eye and stops at the
--- first thing it touches, so the sight and the impact are genuinely different places
--- -- and "you are cleaning what you are hitting" is the only rule a player would ever
--- guess from watching it.
---
--- `hit` IS THE ANSWER WHENEVER IT HAS ONE. WashService stamps a `WashZone` attribute
--- on every chunk of crust the item is wearing, so the part the impact ray already
--- returned names its own dirty area exactly. A chunk is DESTROYED the moment its patch
--- clears, so a hit on a live chunk is proof the area is still dirty — but the payload
--- is checked anyway, because a ray can return a part one tick after the server took it
--- away and a stale zone is a tick of water banked against a patch that no longer
--- exists.
---
--- THE PROXIMITY FALLBACK IS NOW A ROUNDING, NOT THE MECHANISM. It used to be the
--- whole of it, at 2.8 studs against a 1.4-stud item -- which, with every zone's ball
--- stacked near the model's centre back when zones were round-robin slices, meant
--- anything in the postcode of the tub counted as a hit on all of them. It survives at
--- a third of that reach for one honest case: water landing in the gap between two
--- chunks of crust, close enough to either that "you missed entirely" would be a lie.
--- It measures from the anchor WashService sent, carried round the turntable — the
--- chunk itself has been shrinking as it soaks, and its centre has not moved.
local function patchAt(point: Vector3, hit: BasePart?): number?
	if hit then
		local zone = hit:GetAttribute("WashZone")
		if type(zone) == "number" and livePatch(zone) then
			return zone
		end
	end

	local best: number? = nil
	local bestDistance = PATCH_REACH
	for _, patch in (state and state.patches) or {} do
		if patch.anchor then
			local distance = (spinPoint(patch.anchor) - point).Magnitude
			if distance < bestDistance then
				best, bestDistance = patch.zone, distance
			end
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

	-- BEFORE the camera reads it, so the shot frames the item's post-turn pose this
	-- frame rather than last frame's. Held still while spraying; kicked round faster for
	-- a moment at the reveal.
	spinTurntable(dt)

	-- Re-asserted per frame rather than once at session start, for the same reason the
	-- nozzle is re-resolved per frame: a World.rebuild() from the command bar destroys
	-- this stand and parents a new one, and the new one arrives queryable.
	local stand = state.stand
	openTheStand(if stand and stand:IsA("BasePart") then stand else nil)

	local eye = eyeCFrame()
	if eye == nil then
		-- The head is gone: a respawn is landing and the session is about to end, but
		-- it has not been told yet. Fall back to the station's own side-on anchor --
		-- an unflattering angle for a frame beats a camera frozen wherever it was.
		local anchor = if stand and stand.Parent then stand.Parent:FindFirstChild("WashCam") else nil
		if anchor and anchor:IsA("BasePart") then
			camera.CFrame = anchor.CFrame
		end
		return
	end

	-- THE REVEAL OWNS THE CAMERA once the last chunk is off (WashReveal): same eye, but
	-- swung onto the nuke and zoomed in, with no aim, jet or patch to track.
	if WashReveal.active() then
		local pivot = itemPivot()
		WashReveal.drive(camera, eye.Position, if pivot then pivot.Position else eye.Position + eye.LookVector * 6)
		local lowered = eye * WashReveal.HOSE_DROP
		aimNozzle(lowered, lowered.Position + eye.LookVector * 3 - Vector3.yAxis * 3, dt)
		applyHidden(1)
		hideJet()
		return
	end

	camera.CFrame = eye
	-- Kept well out in front, never on top of the lens. See the header: this is what
	-- stops TransparencyController dissolving the arms and the hose.
	camera.Focus = CFrame.new(eye.Position + eye.LookVector * FOCUS_AHEAD)
	applyHidden(1)


	-- Rebuilt per frame rather than cached: the character is respawnable and the folder
	-- is destroyed on every teardown(), so a stale filter would either miss the
	-- character or hold a reference to a freed instance.
	local filter = RaycastParams.new()
	filter.FilterType = Enum.RaycastFilterType.Exclude
	filter.FilterDescendantsInstances = { Players.LocalPlayer.Character :: any, folder :: any }

	local aimPoint, aimPart = aimPointAt(eye, filter)

	-- WHERE THE NOZZLE RIDES FOR THIS VIEWER, recomputed every frame from the eye
	-- rather than cached: it has to track pitch and yaw the same instant the camera
	-- does, or the model visibly lags the view it is supposed to be bolted under. See
	-- HELD_OFFSET and the note on `aimNozzle` for why this replaced the mast's own
	-- fixed position as the thing the barrel swings from.
	local mount = eye * HELD_OFFSET

	-- Tracks the view continuously, spraying or not — a machine you are standing at the
	-- controls of reads as aimed the moment you look somewhere, not only while it is
	-- live. It is also the only feedback that says the thing is listening to you before
	-- you pull the trigger.
	aimNozzle(mount, aimPoint, dt)

	-- The jet reports back where it landed, which is not the aim point whenever the
	-- falling arc clips something on the way. That impact, not the reticle, is what
	-- picks the patch.
	local nozzle = nozzleCFrame(mount)
	local landing, landingPart = aimPoint, aimPart
	if nozzle then
		if spraying then
			landing, landingPart = drawJet(nozzle.Position, aimPoint, filter)
		else
			hideJet()
			-- WHERE THE WATER WOULD GO IF YOU PULLED THE TRIGGER NOW. The same ballistic
			-- path, walked with the same rays, drawn by nobody -- twelve short casts on a
			-- frame that is otherwise doing very little.
			--
			-- IT IS USUALLY THE SIGHT LINE AND SOMETIMES IT IS NOT, and the sometimes is
			-- why this is here. `jetPath` solves the launch so the arc ARRIVES at the aim
			-- point, so the sag lives in the belly of the flight and the water lands where
			-- you pointed -- unless that belly clips something first, which across a tub
			-- with a raised rim and an item up on a stand is most of the shots taken from
			-- the far side of the object. Reading the sight while dry would then close the
			-- ring on a patch the stream is about to hand to the rim instead: a reticle
			-- that lies for exactly as long as it takes to line a shot up. Both states
			-- answer the same question now -- where does the water end up.
			local path = jetPath(nozzle.Position, aimPoint, os.clock())
			landing, landingPart = traceJet(path, filter)
		end
	else
		hideJet()
	end

	local target = patchAt(landing, landingPart)

	-- EVERY CRUSTED PATCH IS A LOCK NOW. The ring used to stay open on a patch past
	-- this liquid's potency, because the server banked nothing for it; it banks a slow
	-- trickle now (WashService.soakTarget), so the water IS shifting grime there, and
	-- the slate-grey rock eroding at a crawl is what says how slowly.
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
	WashFluidBar.show(true)

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
	WashFluidBar.show(false)

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

	WashReveal.stop()
	exitView()
	state = nil
	spraying = false
	aimedZone = nil
	leaving = false
	lookYaw, lookPitch = 0, 0
	padLook = Vector2.zero

	restoreNozzle()
	closeTheStand()
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
	TURNTABLE.speed = 1
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

		-- Every payload, not just the first: the loaded liquid can change mid-wash (a
		-- canister runs dry and drops you back to Plain Water) and `percentClean` climbs
		-- every tick. SERVER-COMPUTED, like `soak` on each patch: the bar draws the
		-- numbers, it does not derive them. beginSession has already run ensureGui by here
		-- on a fresh session, so the bar is mounted.
		WashFluidBar.update(payload)
	end)

	-- THE REVEAL. WashService announces the name the moment the last chunk pops, marked
	-- `staged` because this bay shows it itself, on the real model still turning on the
	-- stand -- the overworld banner stands down for those. The aim furniture goes; the
	-- server has already stopped counting spray.
	Net.get("ItemIdentified").OnClientEvent:Connect(function(found)
		if type(found) ~= "table" or found.staged ~= true or not viewActive or state == nil then
			return
		end
		local camera = Workspace.CurrentCamera
		local pivot, size = itemPivot()
		if camera == nil or pivot == nil or size == nil then
			return
		end
		spraying = false
		hideJet()
		if reticle then
			reticle.Visible = false
		end
		WashFluidBar.show(false)
		WashReveal.play(found, camera, pivot.Position, math.max(size.X, size.Y, size.Z))
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
