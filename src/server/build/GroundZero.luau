--!strict
--[[
	GroundZero.luau — Stage 12, Ground Zero: the hypocentre, the end of the chain. The
	ground is still molten.

	    called from build/Scenery's buildStageScenery (Stage 12)

	WHAT IS OUT HERE, landmarks first:

	  * THE HYPOCENTRE — north of the lane: a scorched disc of fused black glass with the
	    blast shadow streaking out of it, the four concrete footings of the tower the
	    device went off on with their girders twisted, and the shattered bomb casing
	    lying beside them, smoking.
	  * LAVA POOLS — the stage's yellow-white `ooze` at the core, molten orange round it,
	    cooled black crust at the rim and floating on top; lights on most of them, smoke
	    and sparks off a few.
	  * LAVA FLOWS — two tongues run out from the hypocentre, glowing, thinning as they go.
	  * COOLED LAVA — black studded rock with the heat still showing through a split.
	  * THE GROUND — scorch marks, ash, black glass beads and short hot cracks.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local GroundZero = {}

local SEED = 12400

local LAVA_POOLS = 7
local POOL_LIGHTS = 5
local POOL_SMOKE = 2
local POOL_SPARKS = 2
local FLOWS = 2
local COOLED_ROCKS = 12

--- The hypocentre's scorched disc and how many blast-shadow streaks come out of it.
local SCORCH_RADIUS = 14
local STREAKS = 34

local CELL = 13
local SCORCH_CHANCE = 0.13
local ASH_CHANCE = 0.08
local BEAD_CHANCE = 0.07
local CRACK_CHANCE = 0.05

local CRUST = { K.hex("2A1A14"), K.hex("1A1614"), K.hex("3A2A22") }
local SCORCH = K.hex("1C1210")
local CONCRETE = { K.hex("5E5860"), K.hex("48434A") }
local GIRDER = { K.hex("4A2A20"), K.hex("2E1E1A"), K.hex("5E3526") }
local CASING = K.hex("3A3F46")
local ASH = { K.hex("6E6A73"), K.hex("8C8791") }
local BLACK_GLASS = { K.hex("1E2A24"), K.hex("2A3A30"), K.hex("141C18") }

type Palette = { core: Color3, molten: Color3, deep: Color3 }

local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	return { core = K.hex(def.ooze.bright), molten = K.hex("FF8A1A"), deep = K.hex(def.ooze.deep) }
end

local function darkSmoke(anchor: BasePart, big: boolean)
	local s = if big then 1 else 0.7
	K.smoke(anchor, "Smoke", {
		from = K.hex("2A2224"),
		to = K.hex("5A5054"),
		size = { 1.4 * s, 4 * s, 9 * s },
		opacity = 0.55,
		lifetime = { 7, 10 },
		rate = if big then 4 else 2.5,
		speed = { 2.4 * s + 0.6, 3.6 * s + 0.6 },
		accel = K.WIND + Vector3.new(0, 0.1, 0),
	})
end

local function sparks(anchor: BasePart, palette: Palette)
	K.smoke(anchor, "Sparks", {
		texture = K.SPARK_TEXTURE,
		from = palette.core,
		to = palette.molten,
		size = { 0.4, 0.3, 0.1 },
		opacity = 1,
		lifetime = { 1.6, 2.8 },
		rate = 4,
		speed = { 2.5, 5 },
		spread = 25,
		accel = K.WIND + Vector3.new(0, 0.6, 0),
		light = 1,
	})
end

-- ── The hypocentre ─────────────────────────────────────────────────────────────

--- A girder twisted by the blast: two or three segments, each kinked off the last,
--- rising out of a footing.
local function twistedGirder(parent: Instance, base: CFrame, rng: Random)
	local frame = base * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	local lean = rng:NextNumber(8, 20)
	for i = 1, 3 do
		local len = rng:NextNumber(2.4, 3.6)
		frame = frame * CFrame.Angles(math.rad(lean + (i - 1) * rng:NextNumber(10, 25)), math.rad(rng:NextNumber(-25, 25)), 0)
		local mid = frame * CFrame.new(0, len / 2, 0)
		-- An I-beam: a web with a flange each side.
		K.block(parent, "GirderWeb", mid, Vector3.new(0.25, len, 1), GIRDER[1], { material = Enum.Material.Metal })
		for _, sx in { -1, 1 } do
			K.block(parent, "GirderFlange", mid * CFrame.new(sx * 0.5, 0, 0), Vector3.new(0.16, len, 1), K.pick(rng, GIRDER), { material = Enum.Material.Metal })
		end
		frame = frame * CFrame.new(0, len, 0)
	end
end

local function fallenGirder(parent: Instance, at: Vector3, bearing: number, rng: Random)
	local len = rng:NextNumber(4, 8)
	local cf = CFrame.new(at + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, math.rad(bearing), 0) * CFrame.Angles(0, 0, math.rad(90 + rng:NextNumber(-8, 8)))
	K.block(parent, "GirderWeb", cf, Vector3.new(0.18, 0.7, len), GIRDER[2], { material = Enum.Material.Metal })
	for _, s in { -1, 1 } do
		K.block(parent, "GirderFlange", cf * CFrame.new(s * 0.35, 0, 0), Vector3.new(0.12, 0.7, len), K.pick(rng, GIRDER), { material = Enum.Material.Metal })
	end
end

--- The device's casing, split open: the main body half sunk into the glass at an angle,
--- the tail with its fins thrown clear, and shell plates scattered between.
local function casing(parent: Instance, at: Vector3, rng: Random)
	local yaw = rng:NextNumber(0, 360)
	local body = CFrame.new(at + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(0, 0, math.rad(-12))
	K.block(parent, "Casing", body, Vector3.new(5, 2.2, 2.2), CASING, { shape = Enum.PartType.Cylinder, material = Enum.Material.Metal })
	-- The split: a dark gash along its top.
	K.block(parent, "CasingSplit", body * CFrame.new(0.4, 1.02, 0), Vector3.new(3.4, 0.2, 0.5), SCORCH)
	K.block(parent, "CasingNose", body * CFrame.new(-2.6, 0, 0), Vector3.new(1.4, 1.6, 1.6), CASING, { shape = Enum.PartType.Ball, material = Enum.Material.Metal })
	-- The tail, thrown a few studs off the end.
	local tailAt = body * CFrame.new(4.8, -0.2, rng:NextNumber(-1.5, 1.5))
	local tail = CFrame.new(tailAt.Position.X, at.Y + 0.8, tailAt.Position.Z) * CFrame.Angles(0, math.rad(yaw + rng:NextNumber(20, 60)), 0) * CFrame.Angles(math.rad(30), 0, 0)
	K.block(parent, "Tail", tail, Vector3.new(1.3, 1.3, 1.6), CASING, { material = Enum.Material.Metal })
	for k = 0, 3 do
		local fin = tail * CFrame.Angles(0, 0, math.rad(k * 90)) * CFrame.new(0, 0.95, 0.3)
		K.wedge(parent, "Fin", fin, Vector3.new(0.12, 0.9, 1.4), CASING, { material = Enum.Material.Metal })
	end
	for _ = 1, rng:NextInteger(4, 6) do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(2.5, 6)
		local cf = CFrame.new(at.X + math.cos(t) * d, at.Y + 0.12, at.Z + math.sin(t) * d) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), math.rad(rng:NextNumber(0, 360)), 0)
		K.block(parent, "ShellPlate", cf, Vector3.new(rng:NextNumber(0.8, 1.6), 0.14, rng:NextNumber(0.6, 1.2)), CASING, { material = Enum.Material.Metal })
	end
end

local function hypocentre(parent: Instance, at: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Hypocentre"
	local y = at.Y
	-- The fused disc and, under it, the blast shadow streaking out.
	-- No reflectance: shot live, even 0.25 mirrored the sky and turned the black glass
	-- pale blue.
	K.disc(model, "FusedGlass", at + Vector3.new(0, 0.03, 0), SCORCH_RADIUS * 2, SCORCH_RADIUS * 2 * 0.92, 0.05, rng:NextNumber(0, 360), BLACK_GLASS[1])
	for i = 1, STREAKS do
		local bearing = (i / STREAKS) * 360 + rng:NextNumber(-5, 5)
		-- Uneven and see-through, so the shadow reads as scorching thrown out by the
		-- blast rather than as a drawn sunburst (the first pass, sharp and solid, did).
		local len = rng:NextNumber(5, 15)
		local w = rng:NextNumber(1.2, 3.2)
		local start = SCORCH_RADIUS * 0.8
		-- A wedge tapers in its Y-Z profile; rolled 90 degrees onto its side, that taper
		-- lies flat, so the streak is widest at the disc (+Z, tall end) and runs out to a
		-- point.
		local cf = CFrame.new(at.X, y + 0.012 + (i % 3) * 0.003, at.Z)
			* CFrame.Angles(0, math.rad(bearing), 0)
			* CFrame.new(0, 0, -(start + len / 2))
			* CFrame.Angles(0, 0, math.rad(90))
		K.wedge(model, "BlastShadow", cf, Vector3.new(0.03, w, len), SCORCH, { shadow = false, transparency = rng:NextNumber(0.3, 0.55) })
	end
	-- The tower's four footings, each with what is left of its leg.
	local spin = CFrame.new(at) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 90)), 0)
	local half = 5.5
	for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local foot = spin * CFrame.new(c[1] * half, 0, c[2] * half)
		K.block(model, "Footing", foot * CFrame.new(0, 0.8, 0), Vector3.new(3.6, 1.6, 3.6), K.pick(rng, CONCRETE), { studs = true })
		K.block(model, "FootingScorch", foot * CFrame.new(0, 1.62, 0), Vector3.new(3, 0.04, 3), SCORCH)
		twistedGirder(model, foot * CFrame.new(0, 1.6, 0), rng)
	end
	-- Fallen members thrown outward.
	for _ = 1, rng:NextInteger(3, 5) do
		local bearing = rng:NextNumber(0, 360)
		local d = rng:NextNumber(8, 13)
		local p = at + Vector3.new(math.cos(math.rad(bearing)) * d, 0, -math.sin(math.rad(bearing)) * d)
		fallenGirder(model, p, bearing + rng:NextNumber(-30, 30), rng)
	end
	-- The casing beside the footings, on the side away from the lane.
	local side = if at.Z > 0 then 1 else -1
	local casingAt = at + Vector3.new(rng:NextNumber(-3, 3), 0, side * rng:NextNumber(9, 11))
	casing(model, casingAt, rng)
	darkSmoke(K.anchor(model, "CasingSmoke", casingAt + Vector3.new(0, 1, 0)), false)
	darkSmoke(K.anchor(model, "TowerSmoke", at + Vector3.new(0, 1.3, 0), Vector3.new(6, 0.2, 6)), true)
	model.Parent = parent
end

-- ── Lava ───────────────────────────────────────────────────────────────────────

local function lavaPool(parent: Instance, at: Vector3, rng: Random, palette: Palette, flags: { light: boolean, smoke: boolean, sparks: boolean })
	local model = Instance.new("Model")
	model.Name = "LavaPool"
	local size = rng:NextNumber(6, 12)
	K.blob(model, "CrustRim", at.X, at.Z, at.Y + 0.01, size * 1.4, 0.05, CRUST[1], rng)
	K.blob(model, "Molten", at.X, at.Z, at.Y + 0.03, size * 1.12, 0.05, palette.molten, rng, { neon = true })
	local head = K.blob(model, "LavaCore", at.X, at.Z, at.Y + 0.05, size * 0.75, 0.05, palette.core, rng, { neon = true })
	-- Crust floating on it, and cooled chunks round the rim.
	for _ = 1, rng:NextInteger(2, 4) do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0.1, 0.4) * size
		local cf = CFrame.new(at.X + math.cos(t) * d, at.Y + 0.12, at.Z + math.sin(t) * d) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		K.block(model, "FloatingCrust", cf, Vector3.new(rng:NextNumber(0.9, 2), 0.18, rng:NextNumber(0.7, 1.5)), K.pick(rng, CRUST), { studs = true })
	end
	for _ = 1, rng:NextInteger(3, 5) do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = size * rng:NextNumber(0.62, 0.72)
		K.rock(model, at.X + math.cos(t) * d, at.Z + math.sin(t) * d, at.Y, rng:NextNumber(0.8, 1.4), CRUST, rng, "RimRock")
	end
	if flags.light then
		K.glow(head, palette.molten, 14, 1.5)
	end
	if flags.smoke or flags.sparks then
		local a = K.anchor(model, "Vent", at + Vector3.new(0, 0.3, 0), Vector3.new(size * 0.4, 0.2, size * 0.4))
		if flags.smoke then
			darkSmoke(a, false)
		end
		if flags.sparks then
			sparks(a, palette)
		end
	end
	model.Parent = parent
end

--- A tongue of lava running out on `bearing`: a chain of overlapping blobs narrowing as
--- it goes, crusted black at the far end where it has slowed and cooled.
local function lavaFlow(parent: Instance, f: K.Field, from: Vector3, bearing: number, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "LavaFlow"
	local count = rng:NextInteger(10, 13)
	local x, z = from.X, from.Z
	for i = 1, count do
		local t = (i - 1) / (count - 1)
		local w = 5 * (1 - t * 0.65)
		bearing += rng:NextNumber(-18, 18)
		-- Half a width per step: at 0.8 the crust showed between the blobs and the flow
		-- shot live as a string of beads.
		x += math.cos(math.rad(bearing)) * w * 0.5
		z -= math.sin(math.rad(bearing)) * w * 0.5
		x, z = K.clamp(f, x, z, w)
		local color = if t < 0.7 then palette.molten else K.pick(rng, CRUST)
		-- Over the blast shadow it runs across (streak tops at ~0.035), never level with it.
		K.disc(model, "FlowCrust", Vector3.new(x, from.Y + 0.045 + (i % 3) * 0.003, z), w * 1.3, w * 1.0, 0.05, bearing, CRUST[1])
		local blob = K.disc(model, "Flow", Vector3.new(x, from.Y + 0.07 + (i % 3) * 0.003, z), w * 1.1, w * 0.85, 0.05, bearing, color, { neon = t < 0.7 })
		if i == 2 then
			K.glow(blob, palette.molten, 12, 1.2)
		end
	end
	model.Parent = parent
end

local function cooledRock(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local s = rng:NextNumber(1.4, 2.6)
	K.rock(parent, at.X, at.Z, at.Y, s, CRUST, rng, "CooledLava")
	-- The heat still showing through a split in the top.
	local cf = CFrame.new(at.X, at.Y + s * 0.62, at.Z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	K.block(parent, "LavaSplit", cf, Vector3.new(s * 0.8, 0.1, 0.2), palette.molten, { neon = true })
end

function GroundZero.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "GroundZero"

	-- North of the lane, far enough out that the scorch disc's edge meets the lane
	-- rather than covering it, and in the east half: the last thing you reach.
	local hypo = Vector3.new(f.cx + rng:NextNumber(10, 45), groundY, rng:NextNumber(40, 46))
	hypocentre(folder, hypo, rng)
	local taken: { { number } } = { { hypo.X, hypo.Z, SCORCH_RADIUS + 16 } }

	for i = 1, FLOWS do
		-- One west, one south-east toward the lane, both starting at the disc's edge.
		-- Bearings run (cos b, -sin b), so 20-50 is east-south-east.
		local bearing = if i == 1 then rng:NextNumber(170, 190) else rng:NextNumber(20, 50)
		local start = hypo + Vector3.new(math.cos(math.rad(bearing)), 0, -math.sin(math.rad(bearing))) * SCORCH_RADIUS
		lavaFlow(folder, f, start, bearing, rng, palette)
	end

	for i, at in K.sites(f, LAVA_POOLS, 26, rng, 0, taken) do
		lavaPool(folder, at, rng, palette, {
			light = i <= POOL_LIGHTS,
			smoke = i % 3 == 0 and i <= POOL_SMOKE * 3,
			sparks = i % 3 == 1 and i <= POOL_SPARKS * 3,
		})
		table.insert(taken, { at.X, at.Z, 13 })
	end
	for _, at in K.sites(f, COOLED_ROCKS, 12, rng, 0, taken) do
		cooledRock(folder, at, rng, palette)
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z, col, row)
		-- Nothing loose on the hypocentre's disc: it is glass.
		if (Vector3.new(x, 0, z) - Vector3.new(hypo.X, 0, hypo.Z)).Magnitude < SCORCH_RADIUS + 2 then
			return
		end
		local roll = rng:NextNumber()
		local lift = ((2 * col + row) % 4) * 0.003
		if roll < SCORCH_CHANCE then
			K.blob(ground, "Scorch", x, z, groundY + 0.008 + lift, rng:NextNumber(3.5, 9), 0.04, SCORCH, rng, { transparency = 0.2 }, 0.0025)
		elseif roll < SCORCH_CHANCE + ASH_CHANCE then
			K.blob(ground, "Ash", x, z, groundY + 0.008 + lift, rng:NextNumber(3, 7), 0.04, K.pick(rng, ASH), rng, nil, 0.0025)
		elseif roll < SCORCH_CHANCE + ASH_CHANCE + BEAD_CHANCE then
			for i = 1, rng:NextInteger(4, 7) do
				local a = rng:NextNumber(0.3, 1)
				K.disc(ground, "GlassBead", Vector3.new(x + rng:NextNumber(-2, 2), groundY + 0.02 + (i % 4) * 0.004, z + rng:NextNumber(-2, 2)), a, a / rng:NextNumber(1, 1.6), 0.08, rng:NextNumber(0, 360), K.pick(rng, BLACK_GLASS))
			end
		elseif roll < SCORCH_CHANCE + ASH_CHANCE + BEAD_CHANCE + CRACK_CHANCE then
			local heading = rng:NextNumber(0, 360)
			local px, pz = x, z
			for _ = 1, rng:NextInteger(2, 3) do
				local len = rng:NextNumber(1.2, 2.6)
				heading += rng:NextNumber(-40, 40)
				local dx, dz = math.cos(math.rad(heading)), -math.sin(math.rad(heading))
				K.block(ground, "HotCrack", CFrame.new(px + dx * len / 2, groundY + 0.07, pz + dz * len / 2) * CFrame.Angles(0, math.rad(heading), 0), Vector3.new(len, 0.06, 0.18), palette.molten, { neon = true })
				px, pz = px + dx * len, pz + dz * len
			end
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return GroundZero
