--!strict
--[[
	SpotCracks.luau — the starburst of glowing cracks around a revealed signal.

	The aura itself (server build/SignalAura) is only the shared anchor: a hot spot,
	a light, some motes. The cracks are built HERE, on each client, because they carry
	rarity — more cracks, forking, pulsing faster the rarer the find
	(Tuning.AURA_CRACKS) — and rarity is per-player: signal X can be Rare for one
	player and Common for the next, so a shared part could never show both.

	SAME SHAPE FOR EVERYONE. The crack layout is seeded off the aura's surface point,
	so two players standing over one signal see cracks running the same way; only the
	COUNT differs with each player's own reading. It also means a spot keeps its shape
	if this client ever rebuilds it.

	Everything is matte (the de-neon rule, build/SignalAura) — each crack is a dark
	gash with a thinner rarity-coloured strip down the middle, and the "light" is that
	strip's colour swinging from dim to bright as a pulse runs out to the tips. The
	aura's own PointLight and motes do the rest.

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
	-- the colour skips the property write. There are up to ~70 strips per spot.
	level: number,
}

export type Burst = {
	model: Model,
	segments: { Segment },
	dim: Color3,
	bright: Color3,
}

local GASH = Color3.fromHex("241A10")

local SEGMENTS = 4 -- per main crack
local FORK_SEGMENTS = 3
local JAG = 0.9 -- radians of random turn allowed per segment (±half this)
local TAPER = 0.7 -- a crack loses this fraction of its width from root to tip
local FORK_CHANCE = 0.6 -- per crack, once the rarity forks at all
local GLOW_SHARE = 0.45 -- glow strip width as a share of the gash's
local LEVELS = 24 -- brightness quantisation; see Segment.level

-- Heights above the surface. Everything has to clear Stage 1's opaque ground skim
-- (0.06, build/Scenery GROUND_SKIM) and OozePool's rim (0.14) or the cracks vanish on
-- exactly those floors — the range ring learned that the hard way (FieldController,
-- RING_HEIGHT). And everything has to stay under the aura's hot spot (bottom 0.19,
-- build/SignalAura CORE_LIFT) so the crack roots tuck under it.
local GASH_Y = 0.18
local GASH_THICKNESS = 0.06
local GLOW_Y = 0.225
local GLOW_THICKNESS = 0.02
-- Adjacent strips overlap at each bend and each is its own colour mid-pulse, so a
-- coplanar pair would z-fight. Alternate segments sit a step higher, forks higher still.
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

type Path = { points: { Vector2 }, root: number, fork: boolean }

--- The crack layout, in studs on the ground plane relative to the centre, at WellScale
--- 1. Main cracks fan evenly round the spot (plus a random spin so no two spots line
--- up), each wandering a little per segment; a forking rarity sprouts a shorter
--- branch off some of them partway out.
local function layout(rng: Random, count: number, forks: boolean): { Path }
	local paths: { Path } = {}
	local spin = rng:NextNumber() * 2 * math.pi

	for i = 1, count do
		local angle = spin + (i - 1) / count * 2 * math.pi + (rng:NextNumber() - 0.5) * 0.5
		local length = Tuning.AURA_CRACK_LENGTH * (0.7 + rng:NextNumber() * 0.5)
		local step = length / SEGMENTS
		local x, z = 0, 0
		local points = { Vector2.zero }
		for _ = 1, SEGMENTS do
			angle += (rng:NextNumber() - 0.5) * JAG
			x += math.cos(angle) * step
			z += math.sin(angle) * step
			table.insert(points, Vector2.new(x, z))
		end
		table.insert(paths, { points = points, root = Tuning.AURA_CRACK_WIDTH, fork = false })

		-- Drawn even when unused so a rarity that forks and one that does not still
		-- walk the generator the same way for every crack before this one.
		local forkRoll = rng:NextNumber()
		local forkAt = 2 + rng:NextInteger(0, 1)
		local forkTurn = (if rng:NextNumber() < 0.5 then -1 else 1) * (0.6 + rng:NextNumber() * 0.5)
		if forks and forkRoll < FORK_CHANCE then
			local from = points[forkAt + 1]
			local fx, fz = from.X, from.Y
			local fa = angle + forkTurn
			local forkPoints = { from }
			for _ = 1, FORK_SEGMENTS do
				fa += (rng:NextNumber() - 0.5) * JAG
				fx += math.cos(fa) * length / 7
				fz += math.sin(fa) * length / 7
				table.insert(forkPoints, Vector2.new(fx, fz))
			end
			-- A fork leaves at the parent's width at that joint, a bit thinner.
			local parentWidth = Tuning.AURA_CRACK_WIDTH * (1 - forkAt / SEGMENTS * TAPER)
			table.insert(paths, { points = forkPoints, root = parentWidth * 0.8, fork = true })
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
	}

	for _, path in paths do
		local n = #path.points - 1
		for k = 1, n do
			local p0, p1 = path.points[k], path.points[k + 1]
			local a = Vector3.new(surface.X + p0.X * scale, 0, surface.Z + p0.Y * scale)
			local b = Vector3.new(surface.X + p1.X * scale, 0, surface.Z + p1.Y * scale)
			local width = path.root * scale * (1 - (k - 1) / n * TAPER)

			local gash = flatPart("Gash", GASH)
			local gy = surface.Y + GASH_Y
			lay(gash, a + Vector3.yAxis * gy, b + Vector3.yAxis * gy, width, GASH_THICKNESS, width)
			gash.Parent = model

			local lift = if path.fork then 2 * GLOW_STEP else (k % 2) * GLOW_STEP
			local ly = surface.Y + GLOW_Y + lift
			local glow = flatPart("Glow", burst.dim)
			lay(glow, a + Vector3.yAxis * ly, b + Vector3.yAxis * ly, width * GLOW_SHARE, GLOW_THICKNESS, width * GLOW_SHARE)
			glow.Parent = model

			table.insert(burst.segments, {
				glow = glow,
				reach = ((p0 + p1) / 2).Magnitude,
				level = -1,
			})
		end
	end

	model.Parent = folder
	return burst
end

--- Recolour one burst for this frame. `loud` is the rarity's 0..1 loudness
--- (FieldController), `phase` the aura's own offset so a field of spots does not
--- pulse in lockstep, and `close` whether the player is standing on it: then every
--- crack burns near-full with a fast flicker instead of pulsing — the "you are on it"
--- tell.
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
end

return SpotCracks
