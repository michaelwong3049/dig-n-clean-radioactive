--!strict
--[[
	StarfallCrater.luau — Stage 13, Starfall Crater: the first field of the Rift Valley,
	where pieces of the sky came down and are still burning gold in the dark ground.

	    called from build/Scenery's buildStageScenery (Stage 13)

	WHAT IS OUT HERE, landmarks first:

	  * IMPACT CRATERS — a few scorched bowls off the lane: a ring of studded rim wedges
	    thrown up round a dark floor, and in the middle the meteorite itself, a lump of
	    black rock split open on the stage's gold `ooze`, lit and throwing off sparks.
	  * STAR SHARDS — small gold crystals stuck in the ground where splinters landed.
	  * BOULDERS — midnight-blue rock clusters.
	  * THE GROUND — gold stardust drifts, dark grit and short burnt streaks pointing the
	    way the fragments skidded.

	THE BOWL IS FLAT. The plate cannot be dug into, so the depth is painted the same way
	build/BloodrockRift paints its chasm: a dark floor and a raised rim round it.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local StarfallCrater = {}

local SEED = 13300

-- Minimal decor, matching the far fields' 2026-10-03 pass: one landmark and a handful
-- of everything else.
local CRATERS = 3
local SHARD_CLUSTERS = 4
local BOULDERS = 3

local CELL = 13
local DUST_CHANCE = 0.006
local GRIT_CHANCE = 0.015
local STREAK_CHANCE = 0.006

local ROCK = { K.hex("2E3660"), K.hex("252C52"), K.hex("38406E"), K.hex("1C2244") }
local METEOR = { K.hex("1A1820"), K.hex("24202A"), K.hex("2E2830") }
local CRATER_FLOOR = K.hex("12152A")
local SCORCH = K.hex("0C0E1C")
local GRIT = { K.hex("1A1F3A"), K.hex("3A4270"), K.hex("12152A") }

type Palette = { glow: Color3, hot: Color3, deep: Color3, dust: Color3 }

local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	local glow = K.hex(def.ooze.bright)
	return {
		glow = glow,
		hot = glow:Lerp(Color3.new(1, 1, 1), 0.35),
		deep = K.hex(def.ooze.deep),
		-- Gold dust held dark: a bright drift on the midnight floor reads as spilled paint.
		dust = K.hex(def.color):Lerp(glow, 0.22),
	}
end

-- ── Impact craters ─────────────────────────────────────────────────────────────

local function crater(parent: Instance, at: Vector3, r: number, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "ImpactCrater"
	local y = at.Y

	-- The floor: a scorched ring and the darker bowl inside it.
	K.disc(model, "Scorch", at + Vector3.new(0, 0.02, 0), r * 2.6, r * 2.4, 0.05, rng:NextNumber(0, 360), SCORCH)
	K.disc(model, "Bowl", at + Vector3.new(0, 0.04, 0), r * 1.9, r * 1.8, 0.05, rng:NextNumber(0, 360), CRATER_FLOOR)

	-- The rim: wedges round the bowl, sheer face in, slope running away, highest on the
	-- side the meteor came in from.
	local rimCount = math.floor(r * 2.2)
	local heading = rng:NextNumber(0, math.pi * 2)
	for i = 1, rimCount do
		local t = (i - 0.5) / rimCount * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local lift = 0.75 + 0.35 * math.cos(t - heading)
		local h = rng:NextNumber(1.4, 2.6) * lift
		local w = rng:NextNumber(2.8, 3.8)
		local d = rng:NextNumber(1.8, 2.8)
		local px, pz = at.X + math.cos(t) * (r + d * 0.3), at.Z + math.sin(t) * (r + d * 0.3)
		-- A WedgePart is tall at its +Z face: point +Z at the bowl's centre.
		local cf = CFrame.lookAt(Vector3.new(px, y + h / 2 - 0.1, pz), Vector3.new(at.X, y + h / 2 - 0.1, at.Z))
			* CFrame.Angles(0, math.rad(180), 0)
		K.wedge(model, "Rim", cf, Vector3.new(w, h, d), K.pick(rng, ROCK), { studs = true })
	end

	-- The meteorite: two or three black blocks with the gold showing between them.
	-- Gold, not the paler `hot`: Neon blooms, and the paler one shot live as plain white.
	local core = K.block(model, "MeteorCore", CFrame.new(at.X, y + 1, at.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Vector3.new(r * 0.5, 1.8, r * 0.45), palette.glow, { neon = true })
	K.glow(core, palette.glow, 24, 1.8)
	for i = 1, rng:NextInteger(2, 3) do
		local t = rng:NextNumber(0, math.pi * 2)
		local s = r * rng:NextNumber(0.32, 0.45)
		local cf = CFrame.new(at.X + math.cos(t) * r * 0.22, y + s * 0.38, at.Z + math.sin(t) * r * 0.22)
			* CFrame.Angles(math.rad(rng:NextNumber(-18, 18)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-18, 18)))
		K.block(model, "Meteor", cf, Vector3.new(s, s * 0.8, s * rng:NextNumber(0.8, 1.1)), METEOR[(i - 1) % #METEOR + 1], { studs = true })
	end

	local anchor = K.anchor(model, "SparkVent", Vector3.new(at.X, y + 1.2, at.Z), Vector3.new(r * 0.4, 0.2, r * 0.4))
	K.smoke(anchor, "Sparks", {
		texture = K.SPARK_TEXTURE,
		from = palette.hot,
		to = palette.glow,
		size = { 0.3, 0.25, 0.08 },
		opacity = 1,
		lifetime = { 1.6, 2.8 },
		rate = 3,
		speed = { 2, 4.5 },
		spread = 25,
		accel = K.WIND + Vector3.new(0, 0.5, 0),
		light = 1,
	})

	-- Ejecta: a few chunks thrown out past the rim.
	for _ = 1, rng:NextInteger(3, 5) do
		local t = heading + math.pi + rng:NextNumber(-0.9, 0.9)
		local dist = r * rng:NextNumber(1.5, 2.3)
		K.rock(model, at.X + math.cos(t) * dist, at.Z + math.sin(t) * dist, y, rng:NextNumber(0.7, 1.3), ROCK, rng, "Ejecta")
	end
	model.Parent = parent
end

-- ── Star shards ────────────────────────────────────────────────────────────────

local function shardCluster(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "StarShards"
	for i = 1, rng:NextInteger(3, 5) do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = if i == 1 then 0 else rng:NextNumber(0.8, 2.2)
		local h = if i == 1 then rng:NextNumber(2.4, 3.4) else rng:NextNumber(1, 2.2)
		local base = Vector3.new(at.X + math.cos(t) * d, at.Y, at.Z + math.sin(t) * d)
		local color = if i == 1 then palette.hot else palette.glow
		K.crystal(model, "Shard", base, h, h * 0.28, math.deg(t), rng:NextNumber(8, 28), color, { neon = i == 1, material = Enum.Material.Glass, transparency = if i == 1 then 0 else 0.15 })
	end
	model.Parent = parent
end

function StarfallCrater.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "StarfallCrater"

	local taken: { { number } } = {}
	for _, at in K.sites(f, CRATERS, 70, rng, 14, taken) do
		-- 10-13 (was 7-9.5): the first cut shot live as a puck on the floor.
		local r = rng:NextNumber(10, 13)
		crater(folder, at, r, rng, palette)
		table.insert(taken, { at.X, at.Z, r * 2.6 })
	end
	for _, at in K.sites(f, SHARD_CLUSTERS, 24, rng, 3, taken) do
		shardCluster(folder, at, rng, palette)
		table.insert(taken, { at.X, at.Z, 6 })
	end
	for _, at in K.sites(f, BOULDERS, 12, rng, 2, taken) do
		K.rock(folder, at.X, at.Z, groundY, rng:NextNumber(1.6, 2.8), ROCK, rng, "Boulder")
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z, col, row)
		local roll = rng:NextNumber()
		if roll < DUST_CHANCE then
			local lift = ((2 * col + row) % 4) * 0.003
			K.blob(ground, "Stardust", x, z, groundY + 0.008 + lift, rng:NextNumber(3.5, 8), 0.04, palette.dust, rng, nil, 0.0025)
		elseif roll < DUST_CHANCE + GRIT_CHANCE then
			K.grit(ground, x, z, groundY, GRIT, rng)
		elseif roll < DUST_CHANCE + GRIT_CHANCE + STREAK_CHANCE and not K.onLane(z) then
			-- A burnt skid mark with a gold splinter at the end of it.
			local heading = rng:NextNumber(0, 360)
			local len = rng:NextNumber(3, 6)
			local dx, dz = math.cos(math.rad(heading)), -math.sin(math.rad(heading))
			K.block(ground, "Skid", CFrame.new(x, groundY + 0.06, z) * CFrame.Angles(0, math.rad(heading), 0), Vector3.new(len, 0.05, 0.6), SCORCH, { shadow = false })
			K.block(ground, "Splinter", CFrame.new(x + dx * len / 2, groundY + 0.15, z + dz * len / 2) * CFrame.Angles(0, math.rad(heading + 30), math.rad(20)), Vector3.new(0.5, 0.3, 0.3), palette.glow, { neon = true })
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return StarfallCrater
