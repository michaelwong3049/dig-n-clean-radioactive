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
	of that, short rarity-coloured rays (Beams, the one non-matte thing here, like the
	motes) keep popping up out of the lit cracks. The aura's own PointLight and motes
	do the rest.

	This module only builds parts and recolours them. FieldController decides when a
	burst exists (a rarity has landed for the aura), when it goes (the aura does), and
	whether the player is standing on it.
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

-- One pooled ray. `born` is the os.clock() it popped, nil while it sits idle (and its
-- beam disabled) waiting to be reused.
type Ray = {
	beam: Beam,
	base: Attachment,
	top: Attachment,
	born: number?,
	height: number,
	width: number,
}

export type Burst = {
	model: Model,
	segments: { Segment },
	dim: Color3,
	bright: Color3,
	rays: { Ray },
	-- Anchor-local points on the lit strips a ray can pop up from.
	sources: { Vector3 },
	rayRate: number,
	rayHeight: number,
	-- Fractional pops owed, so a rate below the frame rate still comes out even.
	owed: number,
	last: number?,
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

-- The rays: thin rarity-coloured beams that pop up out of the lit cracks, stand for a
-- beat and thin away (rate and height per rarity: Tuning.AURA_CRACKS). Beams, not
-- parts: a Beam faces the camera and fades along its length, which is what makes a
-- ray read as light rather than as a stick standing in the dirt.
local RAY_LIFE = 0.9 -- seconds from pop to gone
local RAY_RISE = 0.16 -- seconds to shoot up to full height (eased, so it pops)
local RAY_FADE_FROM = 0.45 -- share of its life after which a ray starts thinning out
local RAY_WIDTH = 0.45 -- studs across at the base; the top is 30% of that
local RAY_BASE_Y = 0.25 -- rays start just above the glow strips
local CLOSE_RAY_RATE = 2.5 -- standing on the spot: rays pop this much more often...
local CLOSE_RAY_HEIGHT = 1.25 -- ...and this much taller
-- Solid at the foot, gone at the tip. Kept solid most of the way up: the stage floors
-- are bright, and a ray that starts see-through just vanishes into them.
local RAY_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.6, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

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
		sources = {},
		rayRate = row.rays,
		rayHeight = row.rayHeight,
		owed = 0,
		last = nil,
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

			if k <= path.lit then
				local ly = surface.Y + GLOW_Y + path.lift + (k % 2) * GLOW_STEP
				local glow = flatPart("Glow", burst.dim)
				lay(glow, a + Vector3.yAxis * ly, b + Vector3.yAxis * ly, width * GLOW_SHARE, GLOW_THICKNESS, width * GLOW_SHARE)
				glow.Parent = model

				table.insert(burst.segments, {
					glow = glow,
					reach = ((p0 + p1) / 2).Magnitude,
					level = -1,
				})
				table.insert(burst.sources, Vector3.new((p0.X + p1.X) / 2 * scale, 0, (p0.Y + p1.Y) / 2 * scale))
			end
		end
	end

	-- The rays hang off one invisible anchor at the surface point, so a source offset
	-- IS an attachment position. Pooled: enough beams for the busiest this rarity gets
	-- (standing on it), reused as they fade, never created mid-frame.
	local anchor = flatPart("RayAnchor", GASH)
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(surface)
	anchor.Parent = model

	-- Mostly the rarity hue, only a touch of white at the foot: the rays ARE the colour
	-- reading, and full additive glow on a bright floor washes a hue out to white.
	local rayColor = ColorSequence.new(hue:Lerp(Color3.new(1, 1, 1), 0.15), hue)
	local pool = math.ceil(row.rays * CLOSE_RAY_RATE * RAY_LIFE) + 1
	for _ = 1, pool do
		local base = Instance.new("Attachment")
		base.Parent = anchor
		local top = Instance.new("Attachment")
		top.Parent = anchor

		local beam = Instance.new("Beam")
		beam.Attachment0 = base
		beam.Attachment1 = top
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Color = rayColor
		beam.Transparency = RAY_TRANSPARENCY
		beam.LightEmission = 0.6
		beam.LightInfluence = 0
		beam.Brightness = 3
		beam.Enabled = false
		beam.Parent = anchor

		table.insert(burst.rays, { beam = beam, base = base, top = top, born = nil, height = 0, width = 0 })
	end

	model.Parent = folder
	return burst
end

--- Pop new rays as they come due and move the live ones through their life: shoot up,
--- hold, thin away. Standing on the spot pops them faster and taller.
local function stepRays(burst: Burst, now: number, close: boolean)
	local dt = if burst.last then math.min(now - burst.last, 0.1) else 0
	burst.last = now

	burst.owed += burst.rayRate * (if close then CLOSE_RAY_RATE else 1) * dt
	while burst.owed >= 1 do
		burst.owed -= 1
		-- A pop with no idle beam to take it is dropped, not queued: the pool is sized
		-- for the busiest case, so this only trims a burst of bad frame timing.
		for _, ray in burst.rays do
			if ray.born == nil and #burst.sources > 0 then
				local at = burst.sources[math.random(1, #burst.sources)]
				ray.base.Position = at + Vector3.new(0, RAY_BASE_Y, 0)
				ray.top.Position = ray.base.Position
				ray.height = burst.rayHeight * (if close then CLOSE_RAY_HEIGHT else 1) * (0.7 + math.random() * 0.5)
				ray.width = RAY_WIDTH * (0.75 + math.random() * 0.5)
				ray.born = now
				ray.beam.Enabled = true
				break
			end
		end
	end

	for _, ray in burst.rays do
		local born = ray.born
		if born == nil then
			continue
		end
		local age = now - born
		if age >= RAY_LIFE then
			ray.born = nil
			ray.beam.Enabled = false
			continue
		end
		local rise = 1 - (1 - math.min(1, age / RAY_RISE)) ^ 3
		local life = age / RAY_LIFE
		local thin = if life > RAY_FADE_FROM then 1 - (life - RAY_FADE_FROM) / (1 - RAY_FADE_FROM) else 1
		ray.top.Position = ray.base.Position + Vector3.new(0, ray.height * rise, 0)
		ray.beam.Width0 = ray.width * thin
		ray.beam.Width1 = ray.width * 0.3 * thin
	end
end

--- Recolour one burst for this frame. `loud` is the rarity's 0..1 loudness
--- (FieldController), `phase` the aura's own offset so a field of spots does not
--- pulse in lockstep, and `close` whether the player is standing on it: then every
--- crack burns near-full with a fast flicker instead of pulsing, and the rays pop
--- faster and taller — the "you are on it" tell.
function SpotCracks.step(burst: Burst, now: number, loud: number, phase: number, close: boolean)
	local speed = 3 + 2 * loud
	local flicker = 0.85 + 0.15 * math.sin(now * 12 + phase)

	for _, segment in burst.segments do
		local brightness = if close
			then flicker
			else 0.35 + 0.65 * math.max(0, math.sin(now * speed + phase - segment.reach * 2.2))
		local level = math.floor(brightness * LEVELS + 0.5)
		if level ~= segment.level then
			segment.level = level
			segment.glow.Color = burst.dim:Lerp(burst.bright, level / LEVELS)
		end
	end

	stepRays(burst, now, close)
end

return SpotCracks
