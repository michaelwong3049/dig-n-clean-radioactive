--!strict
--[[
	EventHorizon.luau — Stage 16, Event Horizon: the end of the Rift Valley. Something
	hangs over the far end of the field that the light goes into and does not come out
	of, and everything on the ground is being stretched toward it.

	    called from build/Scenery's buildStageScenery (Stage 16)

	WHAT IS OUT HERE, landmarks first:

	  * THE SINGULARITY — high over the lane near the east end: a black sphere inside a
	    tilted accretion disc of the stage's coral `ooze` (two rings of short arcs, hot
	    inside, cooler out), a thin pale photon ring hugging the sphere, and one big light.
	    High enough that nothing of it is ever in the walk. It drifts: a slow float and
	    lean about where it was built (Kit.motion "drift", StationMotionController).
	  * THE SHADOW — under it, the ground itself going black in rings.
	  * SPAGHETTI — rocks pulled long and thin, hanging off the ground along lines that
	    all point at the singularity, smaller and higher the closer they are.
	  * THE GROUND — coral streaks raked toward the shadow, dark grit.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)
local Kit = require(script.Parent.Kit)

local EventHorizon = {}

local SEED = 16300

--- Where the singularity hangs: this far in from the field's east edge, this high.
local HOLE_FROM_EAST = 50
local HOLE_HEIGHT = 48
local HOLE_RADIUS = 14
--- The accretion disc: inner/outer ring radii and arc counts, and its tilt.
local DISC_INNER, DISC_OUTER = 20, 32
local ARCS_INNER, ARCS_OUTER = 28, 40
local DISC_TILT = 14
--- The drift: studs it wanders either side of rest, how fast, and from how far away
--- it still moves (it hangs over the whole field, so further than a base's machines).
local DRIFT_AMP = 3
local DRIFT_RATE = 0.12
local DRIFT_RANGE = 450

local SHADOW_RINGS = 4
local SPAGHETTI_LINES = 6
local PIECES_PER_LINE = 4
local BOULDERS = 3

local CELL = 13
local STREAK_CHANCE = 0.014
local GRIT_CHANCE = 0.015

local ROCK = { K.hex("2A2236"), K.hex("1E1828"), K.hex("342A42"), K.hex("16121E") }
local VOID = K.hex("030205")
local GRIT = { K.hex("120E18"), K.hex("3A2030"), K.hex("0A080E") }

type Palette = { glow: Color3, deep: Color3, hot: Color3, ground: Color3 }

local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	local glow = K.hex(def.ooze.bright)
	return {
		glow = glow,
		deep = K.hex(def.ooze.deep),
		hot = glow:Lerp(K.hex("FFE2B0"), 0.55),
		ground = K.hex(def.color),
	}
end

-- ── The singularity ────────────────────────────────────────────────────────────

local function ring(parent: Instance, frame: CFrame, r: number, arcs: number, width: number, color: Color3, transparency: number?)
	for i = 1, arcs do
		local t = (i - 0.5) / arcs * math.pi * 2
		local len = (2 * math.pi * r) / arcs * 1.04
		local p = frame * CFrame.new(math.cos(t) * r, 0, math.sin(t) * r)
		local cf = CFrame.lookAt(p.Position, (p * CFrame.new(-math.sin(t), 0, math.cos(t))).Position, frame.UpVector)
		K.block(parent, "Disc", cf, Vector3.new(width, 0.25, len), color, { neon = true, transparency = transparency })
	end
end

local function singularity(parent: Instance, at: Vector3, palette: Palette): Model
	local model = Instance.new("Model")
	model.Name = "Singularity"
	local centre = CFrame.new(at)
	K.block(model, "Hole", centre, Vector3.one * HOLE_RADIUS * 2, VOID, { shape = Enum.PartType.Ball, shadow = false })
	-- The photon ring: a thin pale band hugging the sphere, square to the view down the lane.
	ring(model, centre * CFrame.Angles(0, 0, math.rad(90)), HOLE_RADIUS + 0.8, 34, 0.7, palette.hot)
	-- The accretion disc, tilted toward the player walking in from the west.
	local disc = centre * CFrame.Angles(0, 0, math.rad(-DISC_TILT))
	ring(model, disc, DISC_INNER, ARCS_INNER, 7, palette.hot)
	ring(model, disc * CFrame.new(0, -0.05, 0), DISC_OUTER, ARCS_OUTER, 9, palette.glow, 0.25)
	local light = K.anchor(model, "HoleLight", at - Vector3.new(0, HOLE_RADIUS + 2, 0))
	K.glow(light, palette.glow, 60, 1.8)
	-- A slow glitter falling into the disc.
	local inflow = K.anchor(model, "Inflow", at + Vector3.new(0, 0, 0), Vector3.new(DISC_OUTER * 2, 0.2, DISC_OUTER * 2))
	K.smoke(inflow, "Inflow", {
		texture = K.SPARK_TEXTURE,
		from = palette.hot,
		to = palette.glow,
		size = { 0.4, 0.3, 0.1 },
		opacity = 0.9,
		lifetime = { 2.5, 4 },
		rate = 5,
		speed = { 0.5, 1.2 },
		spread = 180,
		accel = Vector3.zero,
		light = 1,
	})
	-- Streams in whole, so the controller never moves half of it.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.WorldPivot = centre
	Kit.motion(model, { kind = "drift", amp = DRIFT_AMP, rate = DRIFT_RATE, range = DRIFT_RANGE })
	model.Parent = parent
	return model
end

-- ── The shadow and the spaghetti ───────────────────────────────────────────────

local function shadow(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "HorizonShadow"
	for i = 0, SHADOW_RINGS - 1 do
		local t = i / (SHADOW_RINGS - 1)
		local r = 30 * (1 - t * 0.7)
		K.disc(model, "Shadow", at + Vector3.new(0, 0.02 + i * 0.012, 0), r * 2, r * 1.7, 0.05, rng:NextNumber(-8, 8), palette.ground:Lerp(VOID, 0.35 + t * 0.6))
	end
	model.Parent = parent
end

--- One line of stretched rocks from `from` toward the point under the hole, each piece
--- longer, thinner and higher the nearer it gets.
local function spaghetti(parent: Instance, from: Vector3, toward: Vector3, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "Spaghetti"
	local flat = Vector3.new(toward.X, from.Y, toward.Z)
	for i = 1, PIECES_PER_LINE do
		local t = (i - 1) / PIECES_PER_LINE
		local p = from:Lerp(flat, t * 0.6)
		local stretch = 1 + t * 3.5
		local s = rng:NextNumber(1, 1.6) * (1 - t * 0.45)
		local h = 0.6 + t * t * 9
		local cf = CFrame.lookAt(p + Vector3.new(0, h, 0), toward)
		K.block(model, "Stretched", cf, Vector3.new(s, s * 0.7, s * stretch), K.pick(rng, ROCK), { studs = true })
		-- The hot end facing the hole, where it is coming apart.
		K.block(model, "Tear", cf * CFrame.new(0, 0, -s * stretch / 2 - 0.15), Vector3.new(s * 0.6, s * 0.4, 0.3), palette.glow, { neon = true })
	end
	model.Parent = parent
end

function EventHorizon.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "EventHorizon"

	local under = Vector3.new(f.maxX - HOLE_FROM_EAST, groundY, 0)
	local hole = under + Vector3.new(0, HOLE_HEIGHT, 0)
	singularity(folder, hole, palette)
	shadow(folder, under, rng, palette)

	-- The spaghetti lines fan in from the west half and both sides, never on the lane.
	local taken: { { number } } = { { under.X, under.Z, 34 } }
	for _, at in K.sites(f, SPAGHETTI_LINES, 22, rng, 4, taken) do
		spaghetti(folder, at, hole, rng, palette)
		table.insert(taken, { at.X, at.Z, 10 })
	end
	for _, at in K.sites(f, BOULDERS, 12, rng, 2, taken) do
		K.rock(folder, at.X, at.Z, groundY, rng:NextNumber(1.6, 2.6), ROCK, rng, "Boulder")
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z)
		local roll = rng:NextNumber()
		if roll < STREAK_CHANCE then
			-- A streak raked toward the shadow, longer the nearer it is.
			local d = Vector3.new(under.X - x, 0, under.Z - z)
			if d.Magnitude < 32 then
				return
			end
			local len = math.clamp(260 / d.Magnitude, 1.5, 6)
			local p = Vector3.new(x, groundY + 0.06, z)
			K.block(ground, "Streak", CFrame.lookAt(p, p + d), Vector3.new(0.2, 0.05, len), palette.glow:Lerp(palette.deep, 0.4), { neon = true })
		elseif roll < STREAK_CHANCE + GRIT_CHANCE then
			K.grit(ground, x, z, groundY, GRIT, rng)
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return EventHorizon
