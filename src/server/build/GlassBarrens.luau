--!strict
--[[
	GlassBarrens.luau — Stage 9, Glass Barrens: sand fused to glass by a heat that has
	long since gone, trinitite green shot through the pale ground.

	    called from build/Scenery's buildStageScenery (Stage 9)

	WHAT IS OUT HERE, landmarks first:

	  * SPIRES — fans of tall glass blades pushed up out of the sand, translucent
	    trinitite green, twinkling where they catch the light. The tall things you steer
	    by.
	  * SHARD CLUSTERS — the same blades at knee height, scattered wide.
	  * FUSED POOLS — a rim of dark fused glass round a pool of the stage's teal `ooze`,
	    glowing; a light on the biggest few.
	  * FULGURITES — branching glass tubes lying half out of the sand where lightning
	    went into it.
	  * SAND RIPPLES — rows of low wind ridges the glass never reached.
	  * THE GROUND — flat glass beads and flakes, pale grit, sheets of glassy crust.

	GLASS IS SMOOTH PLASTIC WITH TRANSPARENCY AND REFLECTANCE, never Enum.Material.Glass:
	build/CraterField found that material mirrors a bright hazy sky off anything flat
	and washes the tint out. Reflectance itself does the same to FLAT pieces (Ground
	Zero's black glass shot live as pale blue at 0.25), so everything lying on the
	ground keeps it near zero; only the standing blades catch the light. The glass is not hot, so it does not glow; only the ooze
	pools do.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local GlassBarrens = {}

local SEED = 9900

local SPIRES = 9
local SPIRE_GLINTS = 4
local SHARD_CLUSTERS = 16
local POOLS = 6
local POOL_LIGHTS = 3
local FULGURITES = 7
local RIPPLE_PATCHES = 8

local CELL = 13
local BEAD_CHANCE = 0.13
local GRIT_CHANCE = 0.08
local CRUST_CHANCE = 0.1

--- Deeper than the glass is in life: on this pale ice-cyan floor the lighter greens
--- shot live as barely-there ghosts.
local TRINITITE = { K.hex("2F8A74"), K.hex("237060"), K.hex("3E9E8A"), K.hex("1C5F50") }
local FUSED = K.hex("1F5E52")
local FULGURITE = { K.hex("C8B89A"), K.hex("9E8F74"), K.hex("B3A382") }
local GRIT = { K.hex("C9D6D2"), K.hex("8FA9A6"), K.hex("E1EBE8") }

local GLASS: K.PartOpts = { transparency = 0.15, reflectance = 0.2, shadow = false }

type Palette = { ooze: Color3, deep: Color3, rippleLight: Color3, rippleDark: Color3 }

local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	local ground = K.hex(def.color)
	return {
		ooze = K.hex(def.ooze.bright),
		deep = K.hex(def.ooze.deep),
		rippleLight = K.shade(ground, 0.35),
		rippleDark = K.shade(ground, -0.18),
	}
end

--- One glass blade: a flat slab with a slanted point, standing on `base`, leaning `tilt`
--- degrees toward `lean`. The point is one WedgePart turned so its slope cuts across the
--- blade's width — a broken edge, not a spearhead.
local function blade(parent: Instance, base: Vector3, h: number, w: number, lean: number, tilt: number, color: Color3)
	local t = math.max(0.25, w * 0.28)
	local frame = CFrame.new(base) * CFrame.Angles(0, math.rad(lean), 0) * CFrame.Angles(0, 0, math.rad(tilt))
	local body = h * 0.7
	local tip = h - body
	K.block(parent, "Blade", frame * CFrame.new(0, body / 2 - 0.3, 0), Vector3.new(w, body, t), color, GLASS)
	local flip = if (lean // 1) % 2 == 0 then 0 else 180
	K.wedge(parent, "BladeTip", frame * CFrame.new(0, body - 0.3 + tip / 2, 0) * CFrame.Angles(0, math.rad(90 + flip), 0), Vector3.new(t, tip, w), color, GLASS)
end

local function bladeFan(parent: Instance, at: Vector3, tallest: number, count: number, rng: Random)
	local spin = rng:NextNumber(0, 360)
	blade(parent, at, tallest, tallest * 0.34, spin, rng:NextNumber(-6, 6), K.pick(rng, TRINITITE))
	for i = 1, count - 1 do
		local lean = spin + rng:NextNumber(-70, 70)
		local h = tallest * rng:NextNumber(0.4, 0.8)
		local side = if i % 2 == 0 then 1 else -1
		local off = Vector3.new(math.cos(math.rad(spin)), 0, -math.sin(math.rad(spin))) * side * tallest * rng:NextNumber(0.06, 0.16)
		blade(parent, at + off, h, h * rng:NextNumber(0.24, 0.34), lean, side * rng:NextNumber(12, 30), K.pick(rng, TRINITITE))
	end
end

local function spire(parent: Instance, at: Vector3, rng: Random, glint: boolean)
	local model = Instance.new("Model")
	model.Name = "GlassSpire"
	local tallest = rng:NextNumber(9, 15)
	-- Fused glass where it came up through the sand.
	K.blob(model, "FusedBase", at.X, at.Z, at.Y + 0.01, tallest * 0.9, 0.05, FUSED, rng, { reflectance = 0.06 })
	bladeFan(model, at, tallest, rng:NextInteger(3, 5), rng)
	if glint then
		local a = K.anchor(model, "GlintVolume", at + Vector3.new(0, tallest * 0.45, 0), Vector3.new(tallest * 0.35, tallest * 0.8, tallest * 0.35))
		local e = Instance.new("ParticleEmitter")
		e.Name = "Glint"
		e.Texture = K.SPARK_TEXTURE
		e.Color = ColorSequence.new(K.hex("E8FFFB"))
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Rate = 1.5
		e.Speed = NumberRange.new(0, 0)
		e.Rotation = NumberRange.new(0, 90)
		e.Parent = a
	end
	model.Parent = parent
end

local function shardCluster(parent: Instance, at: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "ShardCluster"
	bladeFan(model, at, rng:NextNumber(1.2, 2.4), rng:NextInteger(2, 4), rng)
	model.Parent = parent
end

local function pool(parent: Instance, at: Vector3, rng: Random, palette: Palette, light: boolean)
	local model = Instance.new("Model")
	model.Name = "FusedPool"
	local size = rng:NextNumber(6, 12)
	K.blob(model, "FusedRim", at.X, at.Z, at.Y + 0.01, size * 1.4, 0.05, FUSED, rng, { reflectance = 0.06 })
	local head = K.blob(model, "Ooze", at.X, at.Z, at.Y + 0.035, size, 0.05, palette.ooze, rng, { neon = true, transparency = 0.2 })
	if light then
		K.glow(head, palette.ooze, 12, 0.9)
	end
	-- A few blades round the rim, where the glass ran and set.
	for _ = 1, rng:NextInteger(2, 4) do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = size * rng:NextNumber(0.6, 0.75)
		local h = rng:NextNumber(0.8, 1.5)
		blade(model, at + Vector3.new(math.cos(t) * d, 0, math.sin(t) * d), h, h * 0.35, math.deg(t), rng:NextNumber(-25, 25), K.pick(rng, TRINITITE))
	end
	model.Parent = parent
end

--- A lightning tube: a thin glass trunk lying in the sand with two or three branches off
--- it, each sunk to half its thickness.
local function fulgurite(parent: Instance, at: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Fulgurite"
	local color = K.pick(rng, FULGURITE)
	local opts: K.PartOpts = { reflectance = 0.12, shape = Enum.PartType.Cylinder }
	local x, z = at.X, at.Z
	local heading = rng:NextNumber(0, 360)
	local d = rng:NextNumber(0.35, 0.55)
	for i = 1, rng:NextInteger(3, 4) do
		local len = rng:NextNumber(1.8, 3.4)
		heading += rng:NextNumber(-35, 35)
		local dx, dz = math.cos(math.rad(heading)), -math.sin(math.rad(heading))
		local mx, mz = x + dx * len / 2, z + dz * len / 2
		K.block(model, "Tube", CFrame.new(mx, at.Y + d * 0.25, mz) * CFrame.Angles(0, math.rad(heading), 0), Vector3.new(len + d * 0.5, d, d), color, opts)
		-- A branch off the joint, thinner.
		if i > 1 and rng:NextNumber() < 0.7 then
			local bh = heading + (if rng:NextNumber() < 0.5 then 1 else -1) * rng:NextNumber(35, 70)
			local bl = len * rng:NextNumber(0.4, 0.7)
			local bx, bz = math.cos(math.rad(bh)), -math.sin(math.rad(bh))
			K.block(model, "Branch", CFrame.new(x + bx * bl / 2, at.Y + d * 0.18, z + bz * bl / 2) * CFrame.Angles(0, math.rad(bh), 0), Vector3.new(bl, d * 0.6, d * 0.6), color, opts)
		end
		x, z = x + dx * len, z + dz * len
		d *= 0.85
	end
	model.Parent = parent
end

local function ripples(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local yaw = rng:NextNumber(-25, 25) + (if rng:NextNumber() < 0.5 then 0 else 90)
	local frame = CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0)
	local rows = rng:NextInteger(4, 7)
	for i = 1, rows do
		local len = rng:NextNumber(6, 12) * (1 - math.abs(i - rows / 2) / rows)
		local cf = frame * CFrame.new(rng:NextNumber(-1, 1), 0.07, (i - rows / 2) * 1.5)
		K.block(parent, "Ripple", cf, Vector3.new(len, 0.14, 0.5), palette.rippleLight)
		K.block(parent, "RippleShade", cf * CFrame.new(0, -0.02, 0.4), Vector3.new(len * 0.95, 0.1, 0.35), palette.rippleDark)
	end
end

function GlassBarrens.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "GlassBarrens"

	local taken: { { number } } = {}
	for i, at in K.sites(f, SPIRES, 26, rng, 8) do
		spire(folder, at, rng, i % 2 == 0 and i <= SPIRE_GLINTS * 2)
		table.insert(taken, { at.X, at.Z, 11 })
	end
	for i, at in K.sites(f, POOLS, 26, rng, 0, taken) do
		pool(folder, at, rng, palette, i <= POOL_LIGHTS)
		table.insert(taken, { at.X, at.Z, 13 })
	end
	for _, at in K.sites(f, SHARD_CLUSTERS, 10, rng, 0, taken) do
		shardCluster(folder, at, rng)
		table.insert(taken, { at.X, at.Z, 5 })
	end
	for _, at in K.sites(f, FULGURITES, 16, rng, 2, taken) do
		fulgurite(folder, at, rng)
		table.insert(taken, { at.X, at.Z, 9 })
	end
	-- Ripples lie flat, so they may cross the lane.
	for _, at in K.sites(f, RIPPLE_PATCHES, 22, rng, -16, taken) do
		ripples(folder, at, rng, palette)
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z, col, row)
		local roll = rng:NextNumber()
		if roll < BEAD_CHANCE then
			for i = 1, rng:NextInteger(4, 8) do
				local a = rng:NextNumber(0.3, 1.1)
				K.disc(ground, "GlassBead", Vector3.new(x + rng:NextNumber(-2, 2), groundY + 0.02 + (i % 4) * 0.004, z + rng:NextNumber(-2, 2)), a, a / rng:NextNumber(1, 1.7), 0.08, rng:NextNumber(0, 360), K.pick(rng, TRINITITE), { reflectance = 0.06 })
			end
		elseif roll < BEAD_CHANCE + GRIT_CHANCE then
			K.grit(ground, x, z, groundY, GRIT, rng)
		elseif roll < BEAD_CHANCE + GRIT_CHANCE + CRUST_CHANCE then
			local lift = ((2 * col + row) % 4) * 0.003
			K.blob(ground, "GlassCrust", x, z, groundY + 0.008 + lift, rng:NextNumber(3, 7), 0.04, K.pick(rng, TRINITITE), rng, { transparency = 0.45, reflectance = 0.06 }, 0.0025)
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return GlassBarrens
