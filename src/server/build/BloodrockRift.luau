--!strict
--[[
	BloodrockRift.luau — Stage 11, Bloodrock Rift: crimson rock split open, the heat
	coming up red through the cracks.

	    called from build/Scenery's buildStageScenery (Stage 11)

	WHAT IS OUT HERE, landmarks first:

	  * THE RIFT — a long fissure wandering the length of the field north of the lane,
	    and a shorter branch to the south: a dark chasm between jagged studded lips, a
	    glowing seam of the stage's red `ooze` down the bottom of it, lights along it and
	    sparks rising off it here and there. Both keep off the lane, so the route east
	    never has to step over it.
	  * SPIRES — jagged crimson pillars, broken into stacked slabs, the tall things you
	    steer by.
	  * BASALT — tight clusters of dark hexagonal columns at stepped heights.
	  * BOULDERS — crimson rock clusters.
	  * THE GROUND — red dust drifts, dark grit and short hot cracks glowing in the plate.

	THE CHASM IS FLAT. The plate cannot be dug into, so the depth is painted: a near-black
	strip, the glow down its middle, and lips raised on both sides so the eye reads the
	dark between them as a drop.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local BloodrockRift = {}

local SEED = 11300

--- The rift's polyline: one point every RIFT_STEP studs, wandering in z by up to
--- RIFT_WANDER each step, held between the two z limits.
local RIFT_STEP = 11
local RIFT_WANDER = 6
--- A light on every Nth segment, sparks on every Mth.
local RIFT_LIGHT_EVERY = 4
local RIFT_SPARK_EVERY = 9

local SPIRES = 8
local BASALT = 5
local BOULDERS = 14

local CELL = 13
local DUST_CHANCE = 0.15
local GRIT_CHANCE = 0.1
local CRACK_CHANCE = 0.05

local ROCK = { K.hex("6E1224"), K.hex("8A1A2E"), K.hex("5A0E1C"), K.hex("B02438") }
local BASALT_COLORS = { K.hex("2A1216"), K.hex("3A1A1E"), K.hex("22101A") }
local CHASM = K.hex("1A0508")
--- The chasm's inner band: the ooze's own deep red lit up like the plate in daylight,
--- so it is held near black and only warmed a touch.
local CHASM_DEEP = K.hex("33060C")
local GRIT = { K.hex("4A0E18"), K.hex("7A2030"), K.hex("2A1216") }

type Palette = { glow: Color3, hot: Color3, deep: Color3, dustLight: Color3, dustDark: Color3 }

local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	local ground = K.hex(def.color)
	local glow = K.hex(def.ooze.bright)
	return {
		glow = glow,
		-- Pushed toward orange: on the crimson ground a red seam shot live as one more
		-- shade of the floor, and a paler one bloomed to a white-pink line.
		hot = glow:Lerp(K.hex("FF9A3A"), 0.45),
		deep = K.hex(def.ooze.deep),
		-- Darker only: a lighter drift on crimson shot live as pink spilled paint.
		dustLight = K.shade(ground, -0.18),
		dustDark = K.shade(ground, -0.35),
	}
end

-- ── The rift ───────────────────────────────────────────────────────────────────

local function riftPath(f: K.Field, x0: number, x1: number, zMin: number, zMax: number, rng: Random): { Vector3 }
	local pts = {}
	local z = rng:NextNumber(zMin, zMax)
	local x = x0
	while x <= x1 do
		table.insert(pts, Vector3.new(x, f.groundY, z))
		x += RIFT_STEP
		z = math.clamp(z + rng:NextNumber(-RIFT_WANDER, RIFT_WANDER), zMin, zMax)
	end
	return pts
end

--- Lay the rift along `pts`. Width swells in the middle and pinches to nothing at
--- both ends, so it opens out of the ground rather than stopping square.
local function rift(parent: Instance, name: string, pts: { Vector3 }, maxW: number, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = name
	local n = #pts - 1
	for i = 1, n do
		local a, b = pts[i], pts[i + 1]
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local t = (i - 0.5) / n
		local w = maxW * math.max(0.25, math.sin(t * math.pi)) * rng:NextNumber(0.85, 1.1)
		local seg = CFrame.lookAt(mid, b)
		-- +0.8 overlap closes the gap on the outside of each bend.
		K.block(model, "Chasm", seg * CFrame.new(0, 0.02, 0), Vector3.new(w, 0.06, len + 0.8), CHASM, { shadow = false })
		K.block(model, "ChasmDeep", seg * CFrame.new(0, 0.04, 0), Vector3.new(w * 0.6, 0.06, len + 0.8), CHASM_DEEP, { shadow = false })
		local seam = K.block(model, "Seam", seg * CFrame.new(rng:NextNumber(-0.1, 0.1) * w, 0.07, 0), Vector3.new(math.max(0.3, w * 0.22), 0.06, len + 0.6), palette.hot, { neon = true })
		if i % RIFT_LIGHT_EVERY == 2 then
			K.glow(seam, palette.glow, 16, 1.4)
		end
		if i % RIFT_SPARK_EVERY == 4 then
			local anchor = K.anchor(model, "SparkVent", mid + Vector3.new(0, 0.2, 0), Vector3.new(w * 0.3, 0.2, len * 0.6))
			K.smoke(anchor, "Sparks", {
				texture = K.SPARK_TEXTURE,
				from = palette.hot,
				to = palette.glow,
				size = { 0.35, 0.3, 0.1 },
				opacity = 1,
				lifetime = { 1.8, 3 },
				rate = 4,
				speed = { 2.5, 5 },
				spread = 20,
				accel = K.WIND + Vector3.new(0, 0.6, 0),
				light = 1,
			})
		end
		-- A second, wider glow band under the seam: the heat lighting the chasm walls.
		K.block(model, "SeamHalo", seg * CFrame.new(0, 0.05, 0), Vector3.new(w * 0.4, 0.06, len + 0.7), palette.deep, { neon = true, transparency = 0.35 })
		-- Jagged lips down both edges: studded wedges with their sheer face on the
		-- chasm and their slope running away from it, like a crater rim, one every
		-- couple of studs, varying in height.
		local lips = math.max(2, math.floor(len / 2.2))
		for side = -1, 1, 2 do
			for j = 1, lips do
				local along = -len / 2 + (j - 0.5) * (len / lips) + rng:NextNumber(-0.4, 0.4)
				local h = rng:NextNumber(0.8, 2) * (0.5 + 0.5 * math.sin(t * math.pi))
				local lw = rng:NextNumber(1.1, 1.9)
				-- A WedgePart is tall at +Z: turn it so +Z faces the chasm.
				local cf = seg
					* CFrame.new(side * (w / 2 + lw * 0.35), h / 2 - 0.1, along)
					* CFrame.Angles(0, math.rad(-side * 90 + rng:NextNumber(-15, 15)), 0)
				K.wedge(model, "Lip", cf, Vector3.new(rng:NextNumber(1.6, 2.4), h, lw), K.pick(rng, ROCK), { studs = true })
			end
		end
	end
	model.Parent = parent
end

-- ── Spires, basalt, boulders ───────────────────────────────────────────────────

local function spire(parent: Instance, at: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "RockSpire"
	local height = rng:NextNumber(7, 14)
	local w = rng:NextNumber(2.6, 3.8)
	local segs = rng:NextInteger(3, 4)
	local segH = height / segs
	local frame = CFrame.new(at) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	for i = 1, segs do
		local k = 1 - (i - 1) * 0.2
		-- Each slab twisted and knocked off-centre against the one below: broken rock.
		frame = frame
			* CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), math.rad(rng:NextNumber(15, 40)), math.rad(rng:NextNumber(-4, 4)))
		local cf = frame * CFrame.new(rng:NextNumber(-0.2, 0.2) * w, segH / 2, rng:NextNumber(-0.2, 0.2) * w)
		K.block(model, "Spire", cf, Vector3.new(w * k * rng:NextNumber(0.85, 1.1), segH + 0.3, w * k * rng:NextNumber(0.7, 0.95)), K.pick(rng, ROCK), { studs = true })
		frame = frame * CFrame.new(0, segH, 0)
	end
	local topW = w * (1 - segs * 0.2)
	K.wedge(model, "SpireTip", frame * CFrame.new(0, 0.9, 0), Vector3.new(topW, 1.8, topW), K.pick(rng, ROCK), { studs = true })
	-- Fallen slabs at its foot.
	for _ = 1, rng:NextInteger(2, 3) do
		local t = rng:NextNumber(0, math.pi * 2)
		K.rock(model, at.X + math.cos(t) * w * 1.1, at.Z + math.sin(t) * w * 1.1, at.Y, rng:NextNumber(1, 1.8), ROCK, rng, "Scree")
	end
	model.Parent = parent
end

--- A hexagonal column: three rectangles at 0/60/120 degrees (see build/SulfurFlats'
--- hexPlate), stood up.
local function hexColumn(parent: Instance, base: CFrame, r: number, h: number, color: Color3)
	for k = 0, 2 do
		K.block(parent, "Basalt", base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, math.rad(k * 60), 0), Vector3.new(r, h, r * math.sqrt(3)), color, { studs = true })
	end
end

local function basalt(parent: Instance, at: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "BasaltColumns"
	local r = rng:NextNumber(0.9, 1.3)
	local step = math.sqrt(3) * r + 0.05
	local frame = CFrame.new(at) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 60)), 0)
	-- A ring of six round a centre, then a few from the next ring out.
	local cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { 0, -1 }, { 1, -1 }, { 2, -1 }, { 2, 0 }, { 1, 1 }, { -2, 1 } }
	local peak = rng:NextNumber(3.2, 4.8)
	for i, c in cells do
		if i > 7 and rng:NextNumber() < 0.45 then
			continue
		end
		local q, s = c[1], c[2]
		local x = step * (q + s / 2)
		local z = step * (s * math.sqrt(3) / 2)
		local ring = math.max(math.abs(q), math.abs(s), math.abs(q + s))
		-- Tallest in the middle, stepping down outward: the organ-pipe look.
		local h = math.max(0.5, peak * (1 - ring * 0.3) * rng:NextNumber(0.75, 1.1))
		hexColumn(model, frame * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(30), 0), r, h, K.pick(rng, BASALT_COLORS))
	end
	model.Parent = parent
end

function BloodrockRift.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "BloodrockRift"

	local taken: { { number } } = {}
	local main = riftPath(f, f.minX + 10, f.maxX - 10, 36, f.maxZ - 16, rng)
	local branchStart = f.minX + (f.maxX - f.minX) * rng:NextNumber(0.3, 0.45)
	local branch = riftPath(f, branchStart, branchStart + (f.maxX - f.minX) * 0.45, -(f.maxZ - 18), -34, rng)
	rift(folder, "Rift", main, rng:NextNumber(8, 10), rng, palette)
	rift(folder, "RiftBranch", branch, rng:NextNumber(5, 6.5), rng, palette)
	for _, list in { main, branch } do
		for _, p in list do
			table.insert(taken, { p.X, p.Z, 10 })
		end
	end

	for _, at in K.sites(f, SPIRES, 26, rng, 6, taken) do
		spire(folder, at, rng)
		table.insert(taken, { at.X, at.Z, 11 })
	end
	for _, at in K.sites(f, BASALT, 22, rng, 4, taken) do
		basalt(folder, at, rng)
		table.insert(taken, { at.X, at.Z, 9 })
	end
	for _, at in K.sites(f, BOULDERS, 10, rng, 2, taken) do
		K.rock(folder, at.X, at.Z, groundY, rng:NextNumber(1.4, 2.8), ROCK, rng, "Boulder")
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z, col, row)
		local roll = rng:NextNumber()
		if roll < DUST_CHANCE then
			local lift = ((2 * col + row) % 4) * 0.003
			local color = if rng:NextNumber() < 0.5 then palette.dustLight else palette.dustDark
			K.blob(ground, "RedDust", x, z, groundY + 0.008 + lift, rng:NextNumber(3.5, 9), 0.04, color, rng, nil, 0.0025)
		elseif roll < DUST_CHANCE + GRIT_CHANCE then
			K.grit(ground, x, z, groundY, GRIT, rng)
		elseif roll < DUST_CHANCE + GRIT_CHANCE + CRACK_CHANCE then
			-- A short hot crack: a zig of two or three glowing slivers.
			local heading = rng:NextNumber(0, 360)
			local px, pz = x, z
			for _ = 1, rng:NextInteger(2, 3) do
				local len = rng:NextNumber(1.2, 2.6)
				heading += rng:NextNumber(-40, 40)
				local dx, dz = math.cos(math.rad(heading)), -math.sin(math.rad(heading))
				K.block(ground, "HotCrack", CFrame.new(px + dx * len / 2, groundY + 0.07, pz + dz * len / 2) * CFrame.Angles(0, math.rad(heading), 0), Vector3.new(len, 0.06, 0.18), palette.hot, { neon = true })
				px, pz = px + dx * len, pz + dz * len
			end
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return BloodrockRift
