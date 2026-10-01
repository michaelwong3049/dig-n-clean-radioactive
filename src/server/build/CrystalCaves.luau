--!strict
--[[
	CrystalCaves.luau — Stage 10, Toxic Crystal Caves: a cave floor with the roof long
	since fallen in, dark basalt and uranium-green crystal growing out of every crack.

	    called from build/Scenery's buildStageScenery (Stage 10)

	WHAT IS OUT HERE, landmarks first:

	  * ROCK ARCHES — what is left of the roof: two studded basalt legs and a broken
	    span, crystals hanging off its underside and crowding its feet. Off the lane,
	    so the walk east never runs under one it would have to duck.
	  * CRYSTAL CLUSTERS — big leaning uranium-green and teal prisms, glowing. Green on
	    purpose: Glass Barrens next door is ice-cyan, so these keep to the hot end.
	  * GEODES — split boulders with a glowing crystal core showing in the break.
	  * SEEP POOLS — the stage's green `ooze` puddled in low spots, motes drifting off
	    a couple of them.
	  * THE GROUND — dark gravel, green mineral streaks and stray shards.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps (the crystals are the HOT bits here, so they get the Neon).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local CrystalCaves = {}

local SEED = 10200

local ARCHES = 5
local ARCH_LIGHTS = 3
local CLUSTERS = 9
local CLUSTER_LIGHTS = 3
local GEODES = 4
local SEEP_POOLS = 3
local POOL_MOTES = 1

local CELL = 13
local GRIT_CHANCE = 0.06
local STREAK_CHANCE = 0.05
local SHARD_CHANCE = 0.05

local BASALT = { K.hex("2B302C"), K.hex("363C37"), K.hex("22271F") }
local CRYSTAL = { K.hex("7CFF3A"), K.hex("4FE87A"), K.hex("3FE0B0"), K.hex("A6FF4F") }
local CORE = K.hex("9CFF5A")
local STREAK = { K.hex("2F5A2A"), K.hex("3C6B34"), K.hex("24452A") }
local GRIT = { K.hex("1C201D"), K.hex("454B44"), K.hex("2F4A2C") }

type Palette = { seep: Color3, seepDeep: Color3 }

local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	return { seep = K.hex(def.ooze.bright), seepDeep = K.hex(def.ooze.deep) }
end

--- A spray of crystals round `at`. `down` hangs them point-first off a ceiling instead.
local function spray(parent: Instance, at: Vector3, count: number, maxH: number, rng: Random, down: boolean?)
	for _ = 1, count do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, maxH * 0.25)
		local h = rng:NextNumber(0.4, 1) * maxH
		local tilt = rng:NextNumber(6, 32)
		if down then
			tilt = 180 - tilt
		end
		K.crystal(parent, "Crystal", at + Vector3.new(math.cos(t) * d, 0, math.sin(t) * d), h, h * rng:NextNumber(0.18, 0.26), math.deg(t) + 90, tilt, K.pick(rng, CRYSTAL), { neon = true })
	end
end

-- ── Rock arches ────────────────────────────────────────────────────────────────

local function arch(parent: Instance, at: Vector3, rng: Random, light: boolean)
	local model = Instance.new("Model")
	model.Name = "RockArch"
	local span = rng:NextNumber(14, 20)
	local height = rng:NextNumber(12, 16)
	local legW = rng:NextNumber(4, 5.5)
	-- Runs along the lane more often than across it, so it frames the walk.
	local frame = CFrame.new(at) * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25) + (if rng:NextNumber() < 0.3 then 90 else 0)), 0)
	for _, side in { -1, 1 } do
		local x = side * span / 2
		-- Each leg two blocks, the upper one kicked in toward the span.
		K.block(model, "Leg", frame * CFrame.new(x, height * 0.3, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-10, 10)), 0), Vector3.new(legW, height * 0.62, legW * 1.1), K.pick(rng, BASALT), { studs = true })
		K.block(model, "Leg", frame * CFrame.new(x - side * 0.9, height * 0.72, 0) * CFrame.Angles(0, 0, math.rad(side * 12)), Vector3.new(legW * 0.9, height * 0.4, legW), K.pick(rng, BASALT), { studs = true })
		local scree = (frame * CFrame.new(x + side * 2.5, 0, rng:NextNumber(-2, 2))).Position
		K.rock(model, scree.X, scree.Z, at.Y, rng:NextNumber(2, 3.2), BASALT, rng, "Scree")
		spray(model, (frame * CFrame.new(x + side * legW * 0.6, 0, legW * 0.5)).Position, rng:NextInteger(2, 4), 3.2, rng)
	end
	-- The span: two slabs meeting a little off true, as if it settled when the roof went.
	local lintelY = height + 0.6
	for _, side in { -1, 1 } do
		K.block(model, "Span", frame * CFrame.new(side * span * 0.24, lintelY, 0) * CFrame.Angles(0, 0, math.rad(side * -rng:NextNumber(3, 8))), Vector3.new(span * 0.58, 2.6, legW * 1.05), K.pick(rng, BASALT), { studs = true })
	end
	-- Crystals hanging off its underside.
	local hangY = lintelY - 1.3
	local lit: BasePart? = nil
	for i = 1, rng:NextInteger(2, 3) do
		local x = rng:NextNumber(-span * 0.3, span * 0.3)
		spray(model, (frame * CFrame.new(x, hangY + 0.3, rng:NextNumber(-0.8, 0.8))).Position, rng:NextInteger(2, 3), 2.6, rng, true)
		if i == 1 then
			lit = K.anchor(model, "Glow", (frame * CFrame.new(x, hangY - 1.2, 0)).Position)
		end
	end
	if light and lit then
		K.glow(lit, CRYSTAL[1], 16, 1.2)
	end
	model.Parent = parent
end

-- ── Crystal clusters and geodes ────────────────────────────────────────────────

local function cluster(parent: Instance, at: Vector3, rng: Random, light: boolean)
	local model = Instance.new("Model")
	model.Name = "CrystalCluster"
	K.blob(model, "ClusterBed", at.X, at.Z, at.Y + 0.012, rng:NextNumber(4, 6), 0.04, STREAK[1], rng)
	K.rock(model, at.X, at.Z, at.Y, rng:NextNumber(2.4, 3.4), BASALT, rng, "ClusterRock")
	-- One big master crystal and a crowd of smaller ones round it.
	local big = rng:NextNumber(9, 13)
	K.crystal(model, "Master", at, big, big * 0.24, rng:NextNumber(0, 360), rng:NextNumber(4, 14), K.pick(rng, CRYSTAL), { neon = true })
	spray(model, at, rng:NextInteger(6, 9), big * 0.6, rng)
	if light then
		K.glow(K.anchor(model, "Glow", at + Vector3.new(0, big * 0.4, 0)), CRYSTAL[1], 14, 1)
	end
	model.Parent = parent
end

local function geode(parent: Instance, at: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Geode"
	local s = rng:NextNumber(3.5, 5)
	local yaw = rng:NextNumber(0, 360)
	local frame = CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0)
	-- Two halves of shell fallen apart, the core between them.
	for _, side in { -1, 1 } do
		K.block(model, "Shell", frame * CFrame.new(side * s * 0.42, s * 0.36, 0) * CFrame.Angles(0, 0, math.rad(side * 16)), Vector3.new(s * 0.5, s * 0.8, s), K.pick(rng, BASALT), { studs = true })
	end
	K.block(model, "Core", frame * CFrame.new(0, s * 0.22, 0), Vector3.new(s * 0.34, s * 0.44, s * 0.8), CORE, { neon = true, shadow = false })
	spray(model, (frame * CFrame.new(0, s * 0.3, 0)).Position, rng:NextInteger(2, 4), s * 0.45, rng)
	model.Parent = parent
end

-- ── Seep pools ─────────────────────────────────────────────────────────────────

local function seepPool(parent: Instance, at: Vector3, rng: Random, palette: Palette, motes: boolean)
	local model = Instance.new("Model")
	model.Name = "SeepPool"
	local size = rng:NextNumber(6, 11)
	K.blob(model, "SeepRim", at.X, at.Z, at.Y + 0.01, size * 1.3, 0.05, STREAK[2], rng)
	K.blob(model, "SeepShallows", at.X, at.Z, at.Y + 0.025, size * 1.1, 0.05, palette.seepDeep, rng)
	K.blob(model, "Seep", at.X, at.Z, at.Y + 0.045, size, 0.05, palette.seep, rng, { neon = true, transparency = 0.2 })
	if motes then
		local a = K.anchor(model, "MoteVent", at + Vector3.new(0, 0.3, 0), Vector3.new(size * 0.5, 0.2, size * 0.5))
		K.smoke(a, "Motes", {
			texture = K.SPARK_TEXTURE,
			from = palette.seep,
			to = K.shade(palette.seep, 0.4),
			size = { 0.25, 0.35, 0.1 },
			opacity = 0.8,
			lifetime = { 3, 5 },
			rate = 3,
			speed = { 0.6, 1.4 },
			spread = 35,
			accel = Vector3.new(0, 0.4, 0),
			light = 1,
		})
	end
	model.Parent = parent
end

function CrystalCaves.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "CrystalCaves"

	local taken: { { number } } = {}
	-- Arches keep a wide berth of the lane: a 20-stud span turned across it must not reach it.
	for i, at in K.sites(f, ARCHES, 40, rng, 14) do
		arch(folder, at, rng, i <= ARCH_LIGHTS)
		table.insert(taken, { at.X, at.Z, 16 })
	end
	for i, at in K.sites(f, CLUSTERS, 20, rng, 4, taken) do
		cluster(folder, at, rng, i <= CLUSTER_LIGHTS)
		table.insert(taken, { at.X, at.Z, 9 })
	end
	for _, at in K.sites(f, GEODES, 18, rng, 3, taken) do
		geode(folder, at, rng)
		table.insert(taken, { at.X, at.Z, 7 })
	end
	for i, at in K.sites(f, SEEP_POOLS, 24, rng, -10, taken) do
		seepPool(folder, at, rng, palette, i % 3 == 1 and i <= POOL_MOTES * 3)
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z, col, row)
		local roll = rng:NextNumber()
		if roll < GRIT_CHANCE then
			K.grit(ground, x, z, groundY, GRIT, rng)
		elseif roll < GRIT_CHANCE + STREAK_CHANCE then
			local lift = ((2 * col + row) % 4) * 0.003
			K.blob(ground, "MineralStreak", x, z, groundY + 0.008 + lift, rng:NextNumber(3, 8), 0.04, K.pick(rng, STREAK), rng, nil, 0.0025)
		elseif roll < GRIT_CHANCE + STREAK_CHANCE + SHARD_CHANCE and not K.onLane(z) then
			spray(ground, Vector3.new(x, groundY, z), rng:NextInteger(1, 3), 2, rng)
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return CrystalCaves
