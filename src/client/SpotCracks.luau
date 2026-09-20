--!strict
--[[
	SpotCracks.luau — the starburst of glowing cracks around a revealed signal.

	The aura itself (server build/SignalAura) is only the shared anchor: a hot spot,
	a light, some motes. The cracks are built HERE, on each client, because they carry
	rarity — more cracks, forking, pulsing faster the rarer the find
	(Tuning.AURA_CRACKS) — and rarity is per-player: signal X can be Rare for one
	player and Common for the next, so a shared part could never show both.

	SEEDED, NOT RANDOM. The crack layout is seeded off the aura's surface point, so two
	players with the same reading on one signal see identical cracks, and a spot keeps
	its shape if this client ever rebuilds it. A different reading means a different
	count, which re-fans the whole layout — the count IS the message.

	Everything is matte (the de-neon rule, build/SignalAura) — each crack is a dark
	gash with a thinner rarity-coloured strip down the middle, and the "light" is that
	strip's colour swinging from dim to bright as a pulse runs out to the tips. On top
	of that, a fixed fan of rarity-coloured rays (Beams, the one non-matte thing here,
	like the motes) stands up out of the centre, each ray blinking on its own beat. The
	aura's own PointLight and motes do the rest.

	This module only builds parts, recolours them and fades them. FieldController decides
	when a burst exists (a rarity has landed for the aura), when it starts going out (the
	server flags the aura as unrevealed — SpotCracks.retire), and whether the player is
	standing on it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local SpotCracks = {}

type Segment = {
	glow: BasePart,
	-- Distance of the segment's midpoint from the centre at WellScale 1, so the pulse
	-- travels at the same pace down a heavy spot's long cracks as a light one's.
	reach: number,
	-- The last quantised brightness written, so a frame that would not visibly change
	-- the colour skips the property write. There are up to ~80 strips per spot.
	level: number,
}

-- One ray of the fan. Once grown it stays put and only how lit it is changes -- until
-- the spot is retired, when it slides back down the way it came up.
type Ray = {
	beam: Beam,
	-- Its tip, and where the tip ends up relative to the shared foot: the ray grows up
	-- out of the ground by sliding the tip out along `reach` when the spot appears.
	tip: Attachment,
	reach: Vector3,
	-- Seconds after the spot appears before this ray starts growing, so the fan comes
	-- up one ray after another rather than all in the same frame.
	delay: number,
	-- How far out of the ground the tip currently stands, 0..1 of `reach`, as last
	-- written. A ray at rest recomputes to exactly 1 every frame, so comparing against
	-- this skips the Attachment write on all but the frames it is actually moving.
	extend: number,
	-- Its own offset into the breathe, so the fan shimmers instead of pulsing as one.
	phase: number,
	-- The last lit level written (see RAY_LEVELS), to skip no-op property writes.
	level: number,
}

export type Burst = {
	model: Model,
	segments: { Segment },
	dim: Color3,
	bright: Color3,
	rays: { Ray },
	-- Every crack part, gash and glow strip alike, for the one thing they all do
	-- together: fade. Held flat rather than walked off the Model each frame so the
	-- opacity pass never allocates.
	crust: { BasePart },
	-- The last quantised opacity written across `crust`, like Segment.level.
	opacity: number,
	-- os.clock() of the first frame this burst was stepped: the reveal counts from it.
	born: number?,
	last: number?,
	-- 1 while the spot is live, eased to 0 once it is retired (the server says nobody
	-- is revealing it any more — Tuning.AURA_LINGER). Linear, smoothed where it is
	-- used, so reversing it mid-fade is just moving it back the other way.
	life: number,
	dying: boolean,
	-- 0..1, eased toward 1 while the player stands on the spot and back to 0 after, so
	-- stepping on and off blends into the flare instead of switching to it.
	onIt: number,
}

local GASH = Color3.fromHex("241A10")

-- The shape of a crack. Short straight runs, each kinked off the crack's heading, so it
-- reads as ground that SPLIT rather than a smooth wandering vein: a kink goes one side,
-- usually the other side next time (not always -- a tidy zigzag is a lightning bolt),
-- and the heading itself drifts a little underneath it all.
local SEGMENTS = 7 -- runs per main crack
local FORK_SEGMENTS = 4
local HAIRLINE_SEGMENTS = 2
local KINK_MIN = 0.25 -- radians a run kinks off the heading, least...
local KINK_MAX = 0.7 -- ...and most
local KINK_FLIP = 0.75 -- chance the next kink goes the other way
local DRIFT = 0.5 -- radians the heading can wander per run (±half this)
local RUN_JITTER = 0.8 -- each run is 0.6..1.4x the average run length
local TAPER = 0.85 -- a crack loses this fraction of its width from root to tip
local WIDTH_JITTER = 0.4 -- each run is 0.8..1.2x its tapered width -- a crack is not a tube
local DARK_TIPS = 2 -- the last runs are too thin to hold light: gash only, no glow strip
local FORK_CHANCE = 0.6 -- per crack, once the rarity forks at all
local HAIRLINE_CHANCE = 0.8 -- per crack, any rarity: a short thin unlit split off the side
local GLOW_SHARE = 0.45 -- glow strip width as a share of the gash's
local LEVELS = 24 -- brightness quantisation; see Segment.level

-- The rays: a fixed fan of rarity-coloured beams standing up out of the centre of the
-- spot (how many and how tall per rarity: Tuning.AURA_CRACKS), always out, each
-- blinking on its own beat. Narrow at the ground, wide and faded at the top, like light
-- spilling up out of the hole. Beams, not parts: a Beam faces the camera and fades
-- along its length, which is what makes a ray read as light rather than as a stick.
local RAY_TILT_MIN = math.rad(4) -- how far off vertical a ray leans, least...
local RAY_TILT_MAX = math.rad(20) -- ...and most, so the set fans out
local RAY_FOOT = 0.3 -- studs across where a ray leaves the ground
local RAY_SPREAD = 1.5 -- studs across at the top (each ray varies 0.7..1.3x)
local RAY_BASE_Y = 0.25 -- rays leave from just above the hot spot
local RAY_DIM = 0.35 -- how lit a ray still is at the bottom of its breathe (0 = gone)
local RAY_LEVELS = 32 -- lit quantisation: one cached NumberSequence per level. 12 read as visible steps
-- Trimmed with REVEAL (0.9 / 0.6) so the fan keeps its proportion to the cracks under
-- it: the whole spot now settles in ~1.15s rather than 1.5s. The fan is allowed to be
-- still rising when the player arrives -- a ray on its way up is motion, not absence,
-- and it is the CRACKS being missing that made the pick-up card look stranded.
local RAY_GROW = 0.7 -- seconds for one ray to grow up out of the ground
local RAY_STAGGER = 0.45 -- the last ray starts growing up to this long after the first

-- NOTHING SNAPS (on request: the first fan popped in at full strength and blinked
-- up hard, which read as sudden and awkward). A spot's cracks, core and light fade in
-- over REVEAL; its rays grow up one after another, fading in as they rise; each ray
-- then breathes on a slow plain sine, not a sharpened flash; and standing on or off the
-- spot eases into and out of the flare over ~1/ON_IT_EASE seconds.
-- AND NOTHING VANISHES EITHER (on request: walking out of range blinked the whole
-- starburst out between two frames, which was the most sudden thing left in the field).
-- The server now keeps an aura nobody is revealing alive for Tuning.AURA_LINGER seconds
-- with a flag on it (FieldController reads it and calls SpotCracks.retire), and that
-- window is what these two spend: the cracks fade to nothing instead of being deleted,
-- and the rays sink back down the way they came up rather than switching off.
--
-- FADE_OUT MUST STAY UNDER Tuning.AURA_LINGER (1.0). The part is destroyed at the end
-- of the linger whatever this module has managed by then, so the slack between the two
-- is the budget for the flag to replicate. Widen the linger before widening this.
--
-- Walking back in un-flags the aura and the same burst eases back up — faster than it
-- went out, because that one is answering an action the player just took.
-- REVEAL IS MEASURED AGAINST THE WALK, NOT PICKED (it was 0.6 and had never been
-- checked against one). A spot surfaces at the edge of your detector radius and you can
-- stand on it at Tuning.DIG_RADIUS, so the fade-in has to finish inside the time it
-- takes to cover the difference:
--
--   starting kit (Bent Coil r=13, Taped Boots 26 studs/s):  (13 - 5) / 26 = 0.31s
--   fastest arrival anywhere (r=13, Strider Rig 36):        (13 - 5) / 36 = 0.22s
--
-- The STARTING detector is the tight one — a wider radius only ever buys more walk —
-- and 0.6 lost that race twice over, so a new player walked onto a spot that was still
-- coming up and got a PICK UP card over near-nothing (DetectorController's
-- PROMPT_MIN_SHOWN, which is the other half of this fix). 0.4 puts the cracks at ~87%
-- by the time the starting kit arrives and ~58% at the fastest arrival in the game.
--
-- DO NOT close the rest of that gap by shortening this further. Under ~0.3 the reveal
-- stops reading as ground splitting open and starts reading as a part being switched
-- on, which is the snap the whole module is built to avoid. The card waiting a beat is
-- the cheaper half.
local REVEAL = 0.4 -- seconds for the cracks' glow (and FieldController's core + light) to fade in
local FADE_OUT = 0.6 -- seconds for a retired spot to fade away to nothing
local FADE_BACK = 0.3 -- seconds for a retired spot to come back if it is reached again
local ON_IT_EASE = 5 -- rate the standing-on-it flare eases in and out (1/s)
-- Opacity quantisation for the crack parts. Lower than the glow's LEVELS because this
-- writes ~80 parts in one go where a level change there writes one: 16 steps over a
-- 0.6s fade is a step every couple of frames, which no eye picks out of a fade.
local OPACITY_LEVELS = 16

-- The lit level is a Transparency change, and a NumberSequence is an allocation, so
-- every level is built once here and a ray only swaps between them. Lit 1: solid at the
-- foot, gone at the tip. Lit 0: gone everywhere.
local RAY_SEQUENCES: { NumberSequence } = {}
for level = 0, RAY_LEVELS do
	local lit = level / RAY_LEVELS
	RAY_SEQUENCES[level + 1] = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - lit),
		NumberSequenceKeypoint.new(0.5, 1 - lit * 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Heights above the surface. Everything has to clear Stage 1's opaque ground skim
-- (0.06, build/Scenery GROUND_SKIM) and OozePool's rim (0.14) or the cracks vanish on
-- exactly those floors — the range ring learned that the hard way (FieldController,
-- RING_HEIGHT). And everything has to stay under the top of the aura's hot spot (0.29,
-- build/SignalAura CORE_LIFT) so the crack roots tuck under it.
local GASH_Y = 0.18
local GASH_THICKNESS = 0.06
local GLOW_Y = 0.225
local GLOW_THICKNESS = 0.02
-- Adjacent strips overlap at each bend and each is its own colour mid-pulse, so a
-- coplanar pair would z-fight. Alternate runs sit a step higher, forks two steps higher.
local GLOW_STEP = 0.012

local function flatPart(name: string, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	-- Born invisible, like the aura's own core (build/SignalAura): the first step fades
	-- it in, and a part that shipped opaque would show for the frame between being
	-- parented and that step.
	part.Transparency = 1
	return part
end

--- One straight stretch of crack from `a` to `b` (both on the ground plane at the
--- same Y), `width` across. Lengthened by `overlap` so the joins at each bend are
--- covered rather than notched.
local function lay(part: BasePart, a: Vector3, b: Vector3, width: number, thickness: number, overlap: number)
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	part.Size = Vector3.new(width, thickness, length + overlap)
	part.CFrame = CFrame.lookAt(mid, mid + (b - a))
end

--- A stable seed off the surface point. Every client reads the same replicated
--- position, so every client lays the same cracks.
local function seedFor(surface: Vector3): number
	return math.floor(surface.X * 97 + 0.5) * 7919 + math.floor(surface.Z * 89 + 0.5)
end

-- `widths[k]` is run k's gash width; `lit` how many leading runs carry a glow strip;
-- `lift` the glow's extra height (forks sit above the crack they leave).
type Path = { points: { Vector2 }, widths: { number }, lit: number, lift: number }

--- Walk one jagged crack out from `from` along `heading`: `runs` straight runs
--- totalling about `length`, tapering from `rootWidth`.
local function walk(rng: Random, from: Vector2, heading: number, length: number, runs: number, rootWidth: number): ({ Vector2 }, { number })
	local points = { from }
	local widths = {}
	local x, y = from.X, from.Y
	local step = length / runs
	local side = if rng:NextNumber() < 0.5 then -1 else 1

	for k = 1, runs do
		heading += (rng:NextNumber() - 0.5) * DRIFT
		local kink = side * (KINK_MIN + rng:NextNumber() * (KINK_MAX - KINK_MIN))
		if rng:NextNumber() < KINK_FLIP then
			side = -side
		end
		local run = step * (1 - RUN_JITTER / 2 + rng:NextNumber() * RUN_JITTER)
		x += math.cos(heading + kink) * run
		y += math.sin(heading + kink) * run
		table.insert(points, Vector2.new(x, y))
		widths[k] = rootWidth * (1 - (k - 1) / runs * TAPER) * (1 - WIDTH_JITTER / 2 + rng:NextNumber() * WIDTH_JITTER)
	end

	return points, widths
end

--- The crack layout, in studs on the ground plane relative to the centre, at WellScale
--- 1. Main cracks fan evenly round the spot (plus a random spin so no two spots line
--- up). Most split a short dark hairline off one side, whatever the rarity; a forking
--- rarity also sprouts a lit branch off some of them partway out.
local function layout(rng: Random, count: number, forks: boolean): { Path }
	local paths: { Path } = {}
	local spin = rng:NextNumber() * 2 * math.pi

	for i = 1, count do
		local heading = spin + (i - 1) / count * 2 * math.pi + (rng:NextNumber() - 0.5) * 0.5
		local length = Tuning.AURA_CRACK_LENGTH * (0.75 + rng:NextNumber() * 0.5)
		local points, widths = walk(rng, Vector2.zero, heading, length, SEGMENTS, Tuning.AURA_CRACK_WIDTH)
		table.insert(paths, { points = points, widths = widths, lit = SEGMENTS - DARK_TIPS, lift = 0 })

		if rng:NextNumber() < HAIRLINE_CHANCE then
			local at = rng:NextInteger(3, SEGMENTS - 2)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local turn = side * (0.7 + rng:NextNumber() * 0.6)
			local reach = length * (0.18 + rng:NextNumber() * 0.1)
			local hp, hw = walk(rng, points[at + 1], heading + turn, reach, HAIRLINE_SEGMENTS, widths[at] * 0.4)
			table.insert(paths, { points = hp, widths = hw, lit = 0, lift = 0 })
		end

		if forks and rng:NextNumber() < FORK_CHANCE then
			local at = rng:NextInteger(3, 5)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local turn = side * (0.6 + rng:NextNumber() * 0.5)
			local fp, fw = walk(rng, points[at + 1], heading + turn, length * 0.45, FORK_SEGMENTS, widths[at] * 0.75)
			table.insert(paths, { points = fp, widths = fw, lit = FORK_SEGMENTS - 1, lift = 2 * GLOW_STEP })
		end
	end

	return paths
end

--- Build the burst for one aura, parented under `folder`. `surface` is the ground
--- point the signal is buried under, `scale` the aura's WellScale, `hue` the rarity
--- colour, and `rarity` picks the count/fork row out of Tuning.AURA_CRACKS.
function SpotCracks.build(folder: Instance, surface: Vector3, scale: number, rarity: string, hue: Color3): Burst
	local row = Tuning.AURA_CRACKS[rarity] or Tuning.AURA_CRACKS.Common
	local paths = layout(Random.new(seedFor(surface)), row.count, row.forks)

	local model = Instance.new("Model")
	model.Name = "Cracks"

	local burst: Burst = {
		model = model,
		segments = {},
		-- Dim sinks the strip most of the way into the gash; bright lifts it toward
		-- white. The pulse sweeps between the two.
		dim = hue:Lerp(GASH, 0.55),
		bright = hue:Lerp(Color3.new(1, 1, 1), 0.3),
		rays = {},
		crust = {},
		opacity = -1,
		born = nil,
		last = nil,
		life = 1,
		dying = false,
		onIt = 0,
	}

	for _, path in paths do
		for k = 1, #path.points - 1 do
			local p0, p1 = path.points[k], path.points[k + 1]
			local a = Vector3.new(surface.X + p0.X * scale, 0, surface.Z + p0.Y * scale)
			local b = Vector3.new(surface.X + p1.X * scale, 0, surface.Z + p1.Y * scale)
			local width = path.widths[k] * scale

			local gash = flatPart("Gash", GASH)
			local gy = surface.Y + GASH_Y
			lay(gash, a + Vector3.yAxis * gy, b + Vector3.yAxis * gy, width, GASH_THICKNESS, width)
			gash.Parent = model
			table.insert(burst.crust, gash)

			if k <= path.lit then
				local ly = surface.Y + GLOW_Y + path.lift + (k % 2) * GLOW_STEP
				local glow = flatPart("Glow", burst.dim)
				lay(glow, a + Vector3.yAxis * ly, b + Vector3.yAxis * ly, width * GLOW_SHARE, GLOW_THICKNESS, width * GLOW_SHARE)
				glow.Parent = model
				table.insert(burst.crust, glow)

				table.insert(burst.segments, {
					glow = glow,
					reach = ((p0 + p1) / 2).Magnitude,
					level = -1,
				})
			end
		end
	end

	-- The fan hangs off one invisible anchor at the surface point, every ray sharing
	-- one foot attachment. Seeded like the cracks (its own stream off the same seed),
	-- so it keeps its shape across a rebuild too.
	local anchor = flatPart("RayAnchor", GASH)
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(surface)
	anchor.Parent = model

	local foot = Instance.new("Attachment")
	foot.Position = Vector3.new(0, RAY_BASE_Y, 0)
	foot.Parent = anchor

	local rng = Random.new(seedFor(surface) + 1)
	-- The rarity hue at the foot, paling toward the tip.
	local rayColor = ColorSequence.new(hue, hue:Lerp(Color3.new(1, 1, 1), 0.55))
	local spin = rng:NextNumber() * 2 * math.pi
	for i = 1, row.rays do
		local around = spin + (i - 1) / row.rays * 2 * math.pi + (rng:NextNumber() - 0.5) * 0.6
		local tilt = RAY_TILT_MIN + rng:NextNumber() * (RAY_TILT_MAX - RAY_TILT_MIN)
		local height = row.rayHeight * (0.8 + rng:NextNumber() * 0.4)
		local lean = Vector3.new(math.sin(tilt) * math.cos(around), math.cos(tilt), math.sin(tilt) * math.sin(around))

		-- Starts collapsed onto the foot; stepRays grows it out to `lean * height`.
		local tip = Instance.new("Attachment")
		tip.Position = foot.Position
		tip.Parent = anchor

		local beam = Instance.new("Beam")
		beam.Attachment0 = foot
		beam.Attachment1 = tip
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Width0 = RAY_FOOT
		beam.Width1 = RAY_SPREAD * (0.7 + rng:NextNumber() * 0.6)
		beam.Color = rayColor
		beam.Transparency = RAY_SEQUENCES[1]
		beam.LightEmission = 0.6
		beam.LightInfluence = 0
		beam.Brightness = 3
		beam.Parent = anchor

		table.insert(burst.rays, {
			beam = beam,
			tip = tip,
			reach = lean * height,
			delay = rng:NextNumber() * RAY_STAGGER,
			extend = 0,
			phase = rng:NextNumber() * 2 * math.pi,
			level = -1,
		})
	end

	model.Parent = folder
	return burst
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

--- Grow and breathe the fan. Each ray slides up out of the ground on its own delay
--- (eased in and out, fading in as it rises), then breathes on a slow sine -- rarer
--- spots a little quicker. Standing on the spot blends the whole fan up toward full and
--- a soft shimmer.
---
--- `alive` is the burst's eased life (see FADE_OUT): the rays ride it the same way they
--- ride their own growth, so a retired spot's fan sinks back into the ground and dims
--- out along the way instead of being switched off where it stands.
local function stepRays(burst: Burst, now: number, age: number, loud: number, alive: number)
	local speed = 1.6 + 0.8 * loud
	for _, ray in burst.rays do
		local grow = math.clamp((age - ray.delay) / RAY_GROW, 0, 1)
		-- Eased in AND out: an ease-out alone still leaves the ground at full speed,
		-- which is exactly the jolt this is here to remove.
		local extend = smooth(grow) * alive
		if extend ~= ray.extend then
			ray.extend = extend
			ray.tip.Position = Vector3.new(0, RAY_BASE_Y, 0) + ray.reach * math.max(extend, 0.01)
		end

		local breathe = RAY_DIM + (1 - RAY_DIM) * (0.5 + 0.5 * math.sin(now * speed + ray.phase))
		local flare = 0.9 + 0.1 * math.sin(now * 8 + ray.phase)
		local lit = (breathe + (flare - breathe) * burst.onIt) * extend

		local level = math.floor(lit * RAY_LEVELS + 0.5)
		if level ~= ray.level then
			ray.level = level
			ray.beam.Transparency = RAY_SEQUENCES[level + 1]
		end
	end
end

--- How present a burst is right now, 0..1: its fade-in on the way up, its eased life on
--- the way back down. FieldController drives the shared core, light and motes off this
--- so all three come up with the cracks and go out with them instead of snapping either
--- way. Only meaningful after the frame's SpotCracks.step.
function SpotCracks.shown(burst: Burst, now: number): number
	local born = burst.born
	return if born then smooth((now - born) / REVEAL) * smooth(burst.life) else 0
end

--- "Nobody is revealing this spot any more" (`dying` true), or "somebody reached it
--- again" (false). Only ever a flag: the fade itself runs in step, so calling this every
--- frame with the same answer costs nothing and reversing it mid-fade picks up from
--- wherever the fade got to. FieldController reads it off the aura's
--- Tuning.AURA_FADE_ATTR — the CLIENT NEVER DECIDES THIS. A client that retired a spot
--- on its own reading would hide auras other players had every right to see (see that
--- file's header).
function SpotCracks.retire(burst: Burst, dying: boolean)
	burst.dying = dying
end

--- Recolour one burst for this frame. `loud` is the rarity's 0..1 loudness
--- (FieldController), `phase` the aura's own offset so a field of spots does not
--- pulse in lockstep, and `close` whether the player is standing on it: then every
--- crack burns near-full with a soft flicker instead of pulsing, and the whole fan of
--- rays lights up with it — the "you are on it" tell. Both blend in and out rather than
--- switching (burst.onIt).
function SpotCracks.step(burst: Burst, now: number, loud: number, phase: number, close: boolean)
	local born = burst.born
	if born == nil then
		born = now
		burst.born = now
	end
	local dt = if burst.last then math.min(now - burst.last, 0.1) else 0
	burst.last = now
	burst.onIt += ((if close then 1 else 0) - burst.onIt) * math.min(1, dt * ON_IT_EASE)

	-- Life runs at a constant rate rather than easing exponentially toward its target:
	-- a fade that has to be FINISHED before the part is destroyed (FADE_OUT) cannot be
	-- one that only ever approaches zero.
	if burst.dying then
		burst.life = math.max(burst.life - dt / FADE_OUT, 0)
	else
		burst.life = math.min(burst.life + dt / FADE_BACK, 1)
	end
	local alive = smooth(burst.life)

	local age = now - born
	local shown = SpotCracks.shown(burst, now)

	-- Every crack part carries the same opacity: the gashes have to go with the glow
	-- strips, or a fading spot leaves its dark cracks painted on the ground at full
	-- strength and then deletes them, which is the pop this was built to remove.
	local opacity = math.floor(shown * OPACITY_LEVELS + 0.5)
	if opacity ~= burst.opacity then
		burst.opacity = opacity
		local transparency = 1 - opacity / OPACITY_LEVELS
		for _, part in burst.crust do
			part.Transparency = transparency
		end
	end

	local speed = 3 + 2 * loud
	local flicker = 0.85 + 0.15 * math.sin(now * 8 + phase)

	for _, segment in burst.segments do
		local pulse = 0.35 + 0.65 * math.max(0, math.sin(now * speed + phase - segment.reach * 2.2))
		local brightness = (pulse + (flicker - pulse) * burst.onIt) * shown
		local level = math.floor(brightness * LEVELS + 0.5)
		if level ~= segment.level then
			segment.level = level
			segment.glow.Color = burst.dim:Lerp(burst.bright, level / LEVELS)
		end
	end

	stepRays(burst, now, age, loud, alive)
end

return SpotCracks
