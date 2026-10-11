--!strict
--[[
	GravityWells.luau — Stage 14, Gravity Wells: the ground pulls wrong here. Rock hangs
	in the air over every well and nothing that fell in has come back up.

	    called from build/Scenery's buildStageScenery (Stage 14)

	WHAT IS OUT HERE, landmarks first:

	  * THE WELLS — off the lane: rings of the ground sinking in toward a dark eye,
	    ringed in the stage's violet `ooze`, with a slow spiral of rock debris hanging
	    over each one at different heights, lit from below.
	  * FLOATING ROCKS — single studded boulders hanging a few studs up, with the
	    shadow of where they tore out still on the ground under them.
	  * PILLARS — leaning violet-black stone columns, bent toward the nearest well.
	  * THE GROUND — violet ripple rings, dark grit.

	THE WELL IS FLAT. The plate cannot be dug into, so the sink is painted: concentric
	discs, each a shade darker, each its own height step so none of them z-fight.

	Nothing here moves. Floating is height alone: every part is anchored and none of
	them collide (build/BiomeKit), so a player walks under the debris freely.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local GravityWells = {}

local SEED = 14300

local WELLS = 3
local DEBRIS_PER_WELL = 7
local FLOATERS = 3
local PILLARS = 2

local RINGS = 5

local CELL = 13
local RIPPLE_CHANCE = 0.006
local GRIT_CHANCE = 0.015

local ROCK = { K.hex("3A2E66"), K.hex("2E2452"), K.hex("45387A"), K.hex("241C40") }
local EYE = K.hex("08060E")
local GRIT = { K.hex("1E163A"), K.hex("4A3A78"), K.hex("120E22") }

type Palette = { glow: Color3, deep: Color3, ground: Color3 }

local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	return { glow = K.hex(def.ooze.bright), deep = K.hex(def.ooze.deep), ground = K.hex(def.color) }
end

-- ── The wells ──────────────────────────────────────────────────────────────────

local function floatingRock(parent: Instance, at: Vector3, s: number, rng: Random, name: string)
	-- K.rock sits a cluster on the ground at groundY; lifting groundY floats it.
	K.rock(parent, at.X, at.Z, at.Y, s, ROCK, rng, name)
end

local function well(parent: Instance, at: Vector3, r: number, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "GravityWell"
	local yaw = rng:NextNumber(0, 360)

	-- Concentric sink: outermost disc the ground's own colour pulled a touch violet,
	-- each ring in darker, the eye near black.
	for i = 0, RINGS - 1 do
		local t = i / (RINGS - 1)
		local rr = r * (1 - t * 0.82)
		local color = palette.ground:Lerp(palette.deep, 0.45 + t * 0.4):Lerp(EYE, t ^ 1.5)
		K.disc(model, "Sink", at + Vector3.new(0, 0.02 + i * 0.012, 0), rr * 2, rr * 2 * 0.92, 0.05, yaw + i * 9, color)
	end
	-- The glowing lip round the outside: a thin neon ring of short arcs.
	local arcs = math.floor(r * 2.4)
	for i = 1, arcs do
		local t = (i - 0.5) / arcs * math.pi * 2
		local len = (2 * math.pi * r) / arcs * 0.7
		local p = Vector3.new(at.X + math.cos(t) * r, at.Y + 0.09, at.Z + math.sin(t) * r * 0.92)
		local cf = CFrame.lookAt(p, p + Vector3.new(-math.sin(t), 0, math.cos(t)))
		K.block(model, "Lip", cf, Vector3.new(0.6, 0.06, len), palette.glow, { neon = true })
	end
	local eye = K.anchor(model, "EyeLight", at + Vector3.new(0, 1, 0))
	K.glow(eye, palette.glow, 26, 1.4)

	-- The debris spiral: rocks climbing as they circle in, smaller toward the top.
	local start = rng:NextNumber(0, math.pi * 2)
	for i = 1, DEBRIS_PER_WELL do
		local t = (i - 1) / (DEBRIS_PER_WELL - 1)
		local ang = start + t * math.pi * 2.6
		local rr = r * (0.85 - t * 0.55)
		local h = 4 + t * 18 + rng:NextNumber(-1, 1)
		floatingRock(model, Vector3.new(at.X + math.cos(ang) * rr, at.Y + h, at.Z + math.sin(ang) * rr), (2.6 - t * 1.3) * rng:NextNumber(0.85, 1.15), rng, "Debris")
	end
	-- Motes: a slow violet drift rising out of the eye.
	K.smoke(eye, "Motes", {
		texture = K.SPARK_TEXTURE,
		from = palette.glow,
		to = palette.deep,
		size = { 0.25, 0.2, 0.05 },
		opacity = 0.9,
		lifetime = { 3, 5 },
		rate = 2.5,
		speed = { 1, 2.2 },
		spread = 35,
		accel = Vector3.new(0, 0.3, 0),
		light = 1,
	})
	model.Parent = parent
end

-- ── Floaters and pillars ───────────────────────────────────────────────────────

local function floater(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "FloatingRock"
	local s = rng:NextNumber(3, 4.5)
	floatingRock(model, at + Vector3.new(0, rng:NextNumber(6, 11), 0), s, rng, "Floater")
	-- The scar it tore out of, still on the ground under it.
	K.disc(model, "Scar", at + Vector3.new(0, 0.03, 0), s * 1.8, s * 1.5, 0.05, rng:NextNumber(0, 360), palette.ground:Lerp(EYE, 0.5))
	model.Parent = parent
end

local function pillar(parent: Instance, at: Vector3, lean: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "BentPillar"
	local segs = rng:NextInteger(3, 4)
	local w = rng:NextNumber(2, 2.8)
	local segH = rng:NextNumber(2.6, 3.4)
	local frame = CFrame.new(at) * CFrame.Angles(0, lean, 0)
	for i = 1, segs do
		-- Each segment tips a little further over: the column bending toward the pull.
		frame = frame * CFrame.Angles(math.rad(-7 - i * 2), 0, 0)
		K.block(model, "Pillar", frame * CFrame.new(0, segH / 2, 0), Vector3.new(w * (1 - i * 0.08), segH + 0.3, w * (1 - i * 0.08)), K.pick(rng, ROCK), { studs = true })
		frame = frame * CFrame.new(0, segH, 0)
	end
	model.Parent = parent
end

function GravityWells.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "GravityWells"

	local taken: { { number } } = {}
	local wells: { Vector3 } = {}
	for _, at in K.sites(f, WELLS, 70, rng, 13, taken) do
		-- 12-15 (was 8-10.5): the first cut read as a ring on the floor from the lane.
		local r = rng:NextNumber(12, 15)
		well(folder, at, r, rng, palette)
		table.insert(taken, { at.X, at.Z, r + 8 })
		table.insert(wells, at)
	end
	for _, at in K.sites(f, FLOATERS, 18, rng, 3, taken) do
		floater(folder, at, rng, palette)
		table.insert(taken, { at.X, at.Z, 7 })
	end
	for _, at in K.sites(f, PILLARS, 20, rng, 4, taken) do
		-- Lean toward the nearest well (the pillar's -Z after the yaw is "toward").
		local lean = rng:NextNumber(0, math.pi * 2)
		local best = math.huge
		for _, w in wells do
			local d = (w - at).Magnitude
			if d < best then
				best = d
				lean = math.atan2(-(w.X - at.X), -(w.Z - at.Z))
			end
		end
		pillar(folder, at, lean, rng)
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z)
		local roll = rng:NextNumber()
		if roll < RIPPLE_CHANCE then
			-- A faint ripple: two thin rings, the ground's own violet a shade lifted.
			local r = rng:NextNumber(2.5, 4.5)
			for k = 1, 2 do
				local rr = r * (0.55 + k * 0.3)
				local segs = 10
				for i = 1, segs do
					local t = (i - 0.5) / segs * math.pi * 2
					local p = Vector3.new(x + math.cos(t) * rr, groundY + 0.05 + k * 0.004, z + math.sin(t) * rr)
					K.block(ground, "Ripple", CFrame.lookAt(p, p + Vector3.new(-math.sin(t), 0, math.cos(t))), Vector3.new(0.2, 0.04, rr * 0.5), K.shade(palette.ground:Lerp(palette.glow, 0.3), 0.05), { shadow = false })
				end
			end
		elseif roll < RIPPLE_CHANCE + GRIT_CHANCE then
			K.grit(ground, x, z, groundY, GRIT, rng)
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return GravityWells
