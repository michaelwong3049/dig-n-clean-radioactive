--!strict
--[[
	CobaltShelf.luau — Stage 8, Cobalt Shelf: a stepped mineral shelf split with cobalt
	ore, where a mine worked the seams before the coolant came through.

	    called from build/Scenery's buildStageScenery (Stage 8)

	WHAT IS OUT HERE, landmarks first:

	  * LEDGES — low terraced outcrops of blue-grey rock, two or three steps high, with
	    cobalt crystals breaking out of the top step. The shelf the stage is named for.
	  * CRYSTAL CLUSTERS — deep cobalt-blue crystals fanning out of a rock base, the
	    tallest few big enough to steer by.
	  * COOLANT PUDDLES — the stage's cyan `ooze`, glowing, with a dark rim where it has
	    stained the rock; a light on half of them, a cold mist off a few.
	  * THE OLD WORKINGS — a length of mine rail and a derelict ore cart tipped at the end
	    of it, its load of ore spilled out.
	  * THE GROUND — blue gravel, loose ore, pale mineral crust and the odd stray shard.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local CobaltShelf = {}

local SEED = 8800

local LEDGES = 7
local CLUSTERS = 10
--- How many of the clusters get the landmark scale.
local BIG_CLUSTERS = 4
local PUDDLES = 9
local PUDDLE_LIGHTS = 5
local PUDDLE_MIST = 3

local CELL = 13
local GRAVEL_CHANCE = 0.11
local ORE_CHANCE = 0.06
local CRUST_CHANCE = 0.1
local SHARD_CHANCE = 0.04

local COBALT = { K.hex("1F3FBF"), K.hex("2B4FD8"), K.hex("16308F"), K.hex("3A5FE8") }
local ROCK = { K.hex("4A5C78"), K.hex("36465E"), K.hex("566A88") }
local GRAVEL = { K.hex("2E3C52"), K.hex("5B6E8C"), K.hex("24334A") }
local CRUST = K.hex("7FA3D4") -- a step off the floor; paler shot live as white spills
local STEEL = K.hex("5A6270")
local RUST = { K.hex("7A4430"), K.hex("5E3526") }
local SLEEPER = K.hex("4A3A2E")
local WHEEL = K.hex("22262C")

local CRYSTAL_OPTS: K.PartOpts = { reflectance = 0.15 }

type Palette = { coolant: Color3, stain: Color3 }

local function paletteFor(stageId: number): Palette
	local ooze = Stages.get(stageId).ooze
	return { coolant = K.hex(ooze.bright), stain = K.hex(ooze.deep) }
end

--- A fan of crystals out of one point: the centre one tallest and straightest, the rest
--- leaning out round it.
local function crystalFan(parent: Instance, at: Vector3, tallest: number, count: number, rng: Random)
	local spin = rng:NextNumber(0, 360)
	K.crystal(parent, "Cobalt", at, tallest, tallest * 0.24, spin, rng:NextNumber(0, 8), K.pick(rng, COBALT), CRYSTAL_OPTS)
	for i = 1, count - 1 do
		local lean = spin + i * (360 / (count - 1)) + rng:NextNumber(-20, 20)
		local h = tallest * rng:NextNumber(0.35, 0.75)
		local off = Vector3.new(math.cos(math.rad(lean)), 0, math.sin(math.rad(lean))) * tallest * 0.08
		K.crystal(parent, "Cobalt", at + off, h, h * rng:NextNumber(0.22, 0.3), -lean + 90, rng:NextNumber(18, 38), K.pick(rng, COBALT), CRYSTAL_OPTS)
	end
end

-- ── Ledges ─────────────────────────────────────────────────────────────────────

--- A terraced outcrop. Each step is two or three rotated studded slabs overlapping, so
--- its outline is broken rock and not a rectangle; each step smaller than the one under
--- it and pushed off-centre, so the terrace climbs to one side.
local function ledge(parent: Instance, at: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Ledge"
	local w = rng:NextNumber(10, 16)
	local d = rng:NextNumber(7, 11)
	local yaw = rng:NextNumber(0, 360)
	local frame = CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0)
	local steps = rng:NextInteger(2, 3)
	local stepH = rng:NextNumber(0.55, 0.75)
	local ox = 0
	local topCF = frame
	for s = 1, steps do
		local k = 1 - (s - 1) * 0.3
		local color = ROCK[((s - 1) % #ROCK) + 1]
		for _ = 1, rng:NextInteger(2, 3) do
			local cf = frame
				* CFrame.new(ox + rng:NextNumber(-0.15, 0.15) * w * k, (s - 0.5) * stepH, rng:NextNumber(-0.15, 0.15) * d * k)
				* CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0)
			K.block(model, "Shelf", cf, Vector3.new(w * k * rng:NextNumber(0.6, 0.85), stepH, d * k * rng:NextNumber(0.6, 0.85)), color, { studs = true })
		end
		topCF = frame * CFrame.new(ox, s * stepH, 0)
		ox += w * 0.12
	end
	-- Cobalt breaking out of the top step.
	crystalFan(model, topCF.Position, rng:NextNumber(2.4, 4), rng:NextInteger(3, 5), rng)
	-- Scree at its foot, on the low side.
	for _ = 1, rng:NextInteger(2, 4) do
		local p = frame * CFrame.new(-w * 0.55 + rng:NextNumber(-1, 1), 0, rng:NextNumber(-0.5, 0.5) * d)
		K.rock(model, p.X, p.Z, at.Y, rng:NextNumber(0.8, 1.4), ROCK, rng, "Scree")
	end
	model.Parent = parent
end

-- ── Clusters and puddles ───────────────────────────────────────────────────────

local function cluster(parent: Instance, at: Vector3, big: boolean, rng: Random)
	local model = Instance.new("Model")
	model.Name = "CobaltCluster"
	local tallest = if big then rng:NextNumber(7, 10) else rng:NextNumber(2.8, 4.8)
	K.rock(model, at.X, at.Z, at.Y, tallest * 0.45, ROCK, rng, "ClusterRock")
	crystalFan(model, at + Vector3.new(0, tallest * 0.1, 0), tallest, rng:NextInteger(4, 7), rng)
	-- A couple of satellite crystals off to one side.
	for _ = 1, rng:NextInteger(1, 3) do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = tallest * rng:NextNumber(0.5, 0.8)
		local h = tallest * rng:NextNumber(0.2, 0.35)
		K.crystal(model, "Cobalt", at + Vector3.new(math.cos(t) * d, 0, math.sin(t) * d), h, h * 0.3, rng:NextNumber(0, 360), rng:NextNumber(10, 30), K.pick(rng, COBALT), CRYSTAL_OPTS)
	end
	model.Parent = parent
end

local function puddle(parent: Instance, at: Vector3, rng: Random, palette: Palette, light: boolean, mist: boolean)
	local model = Instance.new("Model")
	model.Name = "CoolantPuddle"
	local size = rng:NextNumber(5, 11)
	K.blob(model, "Stain", at.X, at.Z, at.Y + 0.01, size * 1.35, 0.04, palette.stain, rng)
	local head = K.blob(model, "Coolant", at.X, at.Z, at.Y + 0.03, size, 0.05, palette.coolant, rng, { neon = true, transparency = 0.15 })
	if light then
		K.glow(head, palette.coolant, 12, 1)
	end
	if mist then
		local a = K.anchor(model, "MistVent", at + Vector3.new(0, 0.2, 0), Vector3.new(size * 0.6, 0.2, size * 0.6))
		K.smoke(a, "ColdMist", {
			from = K.shade(palette.coolant, 0.6),
			to = K.hex("D8ECF5"),
			size = { 1.5, 3, 5 },
			opacity = 0.35,
			lifetime = { 5, 8 },
			rate = 2,
			speed = { 0.3, 0.8 },
			spread = 70,
			-- Cold mist creeps along the ground rather than rising.
			accel = K.WIND * 0.6 + Vector3.new(0, -0.05, 0),
			drag = 0.6,
		})
	end
	model.Parent = parent
end

-- ── The old workings ───────────────────────────────────────────────────────────

--- A length of mine rail running off toward the edge, then a derelict ore cart on its
--- side at the end of it, spilling its load. `at` is where the cart lies.
local function workings(parent: Instance, at: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "OldWorkings"
	-- The rail runs away from the lane, out toward the side wall.
	local outward = if at.Z > 0 then 1 else -1
	local yaw = rng:NextNumber(-35, 35)
	local dir = CFrame.Angles(0, math.rad(yaw), 0)
	local frame = CFrame.new(at) * dir
	local len = rng:NextNumber(18, 26)
	local gauge = 2.2
	-- Track laid along local Z, away from the cart (cart at z = 0, track toward +/-Z outward).
	for i = 0, math.floor(len / 2.2) do
		local z = outward * (3 + i * 2.2)
		-- A few sleepers are missing, which is most of what reads as abandoned.
		if rng:NextNumber() > 0.18 then
			K.block(model, "Sleeper", frame * CFrame.new(0, 0.15, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0), Vector3.new(gauge + 1.4, 0.3, 0.6), SLEEPER, { studs = true })
		end
	end
	local brokenAt = rng:NextNumber(0.45, 0.7) * len
	for _, side in { -1, 1 } do
		-- One rail runs the whole way; the other is snapped and its end kicked up.
		local full = side == 1
		local runLen = if full then len else brokenAt
		local mid = outward * (3 + runLen / 2)
		K.block(model, "Rail", frame * CFrame.new(side * gauge / 2, 0.42, mid), Vector3.new(0.25, 0.25, runLen), STEEL, { material = Enum.Material.Metal })
		if not full then
			local stubLen = rng:NextNumber(2.5, 4)
			local root = frame * CFrame.new(side * gauge / 2, 0.42, outward * (3 + brokenAt + 0.8))
			K.block(model, "BentRail", root * CFrame.Angles(math.rad(-outward * rng:NextNumber(18, 30)), math.rad(rng:NextNumber(-15, 15)), 0) * CFrame.new(0, 0, outward * stubLen / 2), Vector3.new(0.25, 0.25, stubLen), STEEL, { material = Enum.Material.Metal })
		end
	end

	-- The cart, tipped off the end of the rail onto its side: an open box built in its
	-- own frame (length along the track, mouth up), then rolled about the track's line so
	-- one side wall lies on the ground and the mouth faces sideways.
	local cw, ch, cl = 3.2, 2.2, 4.2
	local cart = frame * CFrame.new(0, cw / 2, 0) * CFrame.Angles(0, 0, math.rad(88))
	local wall = 0.25
	local body = K.pick(rng, RUST)
	K.block(model, "CartFloor", cart * CFrame.new(0, -ch / 2 + wall / 2, 0), Vector3.new(cw, wall, cl), STEEL, { studs = true })
	for _, sx in { -1, 1 } do
		K.block(model, "CartSide", cart * CFrame.new(sx * (cw / 2 - wall / 2), 0, 0), Vector3.new(wall, ch, cl), body, { studs = true })
		K.block(model, "CartEnd", cart * CFrame.new(0, 0, sx * (cl / 2 - wall / 2)), Vector3.new(cw, ch, wall), body, { studs = true })
		for _, sz in { -1, 1 } do
			local wheel = cart * CFrame.new(sx * (cw / 2 - 0.55), -ch / 2 - 0.3, sz * cl * 0.3)
			K.block(model, "Wheel", wheel, Vector3.new(0.35, 1.1, 1.1), WHEEL, { shape = Enum.PartType.Cylinder, material = Enum.Material.Metal })
		end
	end
	-- The spilled load, fanning out of the cart's mouth.
	local mouth = cart * CFrame.new(0, ch / 2, 0)
	local spillDir = (mouth.Position - (cart * CFrame.new(0, -ch / 2, 0)).Position).Unit
	for i = 1, rng:NextInteger(9, 14) do
		local t = (i / 12)
		local reach = 1 + t * rng:NextNumber(3, 6)
		local side = rng:NextNumber(-1, 1) * (0.6 + t * 1.8)
		local px = mouth.X + spillDir.X * reach - spillDir.Z * side
		local pz = mouth.Z + spillDir.Z * reach + spillDir.X * side
		local s = rng:NextNumber(0.5, 1.1)
		local cf = CFrame.new(px, at.Y + s * 0.3, pz) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-25, 25)))
		K.block(model, "Ore", cf, Vector3.new(s, s * 0.7, s * rng:NextNumber(0.8, 1.2)), K.pick(rng, COBALT), { studs = true })
	end
	model.Parent = parent
end

-- ── Build ──────────────────────────────────────────────────────────────────────

function CobaltShelf.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "CobaltShelf"

	-- The workings first, off the middle on the north side: it is the one set piece and
	-- everything else keeps clear of it.
	local cartAt = Vector3.new(f.cx + rng:NextNumber(-30, 30), groundY, rng:NextNumber(30, 38))
	workings(folder, cartAt, rng)
	local taken: { { number } } = { { cartAt.X, cartAt.Z + 10, 24 } }

	for _, at in K.sites(f, LEDGES, 30, rng, 6, taken) do
		ledge(folder, at, rng)
		table.insert(taken, { at.X, at.Z, 14 })
	end
	for i, at in K.sites(f, CLUSTERS, 18, rng, 2, taken) do
		-- Every other big one, so the landmarks spread down the field on both sides.
		cluster(folder, at, i % 2 == 1 and i <= BIG_CLUSTERS * 2, rng)
		table.insert(taken, { at.X, at.Z, 9 })
	end
	for i, at in K.sites(f, PUDDLES, 20, rng, -12, taken) do
		puddle(folder, at, rng, palette, i <= PUDDLE_LIGHTS, i % 3 == 0 and i <= PUDDLE_MIST * 3)
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z, col, row)
		local roll = rng:NextNumber()
		if roll < GRAVEL_CHANCE then
			K.grit(ground, x, z, groundY, GRAVEL, rng, "Gravel")
		elseif roll < GRAVEL_CHANCE + ORE_CHANCE then
			K.grit(ground, x, z, groundY, COBALT, rng, "LooseOre")
		elseif roll < GRAVEL_CHANCE + ORE_CHANCE + CRUST_CHANCE then
			local lift = ((2 * col + row) % 4) * 0.003
			K.blob(ground, "MineralCrust", x, z, groundY + 0.008 + lift, rng:NextNumber(3, 7), 0.04, CRUST, rng, { transparency = 0.2 }, 0.0025)
		elseif roll < GRAVEL_CHANCE + ORE_CHANCE + CRUST_CHANCE + SHARD_CHANCE and not K.onLane(z) then
			local h = rng:NextNumber(0.8, 1.5)
			K.crystal(ground, "StrayShard", Vector3.new(x, groundY, z), h, h * 0.3, rng:NextNumber(0, 360), rng:NextNumber(10, 35), K.pick(rng, COBALT), CRYSTAL_OPTS)
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return CobaltShelf
