--!strict
--[[
	CinderField.luau — Stage 7, Cinder Fields: a forest that burned down and is still
	smouldering.

	    called from build/Scenery's buildStageScenery (Stage 7)

	WHAT IS OUT HERE, landmarks first:

	  * SNAGS — charred trunks burned down to their stems, a couple of broken arms, and
	    orange ember cracks still glowing in the bark. The tall things you steer by.
	  * STUMPS and FALLEN LOGS — what the fire already brought down, knee-high at most.
	  * EMBER BEDS — heaps of cinder with the fire still in them: glowing chips over a
	    hot underglow, a light on most of them, and sparks or smoke rising off a few.
	  * THE GROUND — pale ash drifts, black cinder grit, stray embers and burnt twigs,
	    all flat or ankle-high, dealt off a jittered grid.

	The ember orange is the stage's own `ooze.bright`, so the glow is the colour this
	field was given in Config/Stages rather than a second orange next to it.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps (walk-through, off the lane, glow only on the hot bits).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local CinderField = {}

local SEED = 7700

local SNAGS = 8
local STUMPS = 12
local LOGS = 6
local EMBER_BEDS = 10
--- How many of the beds carry a light, sparks, smoke. The rest glow by Neon alone.
local BED_LIGHTS = 7
local BED_SPARKS = 4
local BED_SMOKE = 3

--- The ground grid and its per-cell chances (sum 0.34 — one cell in three).
local CELL = 13
local ASH_CHANCE = 0.15
local CINDER_CHANCE = 0.09
local SPECK_CHANCE = 0.05
local TWIG_CHANCE = 0.05

local WOOD = { K.hex("1E1A1C"), K.hex("2A2426"), K.hex("352C29") }
local CHAR = K.hex("121012")
--- Only a step lighter than the charcoal ground: shot live, a pale grey drift on this
--- floor read as spilled paint from across the field (build/FieldLitter's lesson).
local ASH = { K.hex("55515A"), K.hex("4B474F"), K.hex("615D66") }
local CINDER = { K.hex("2B2729"), K.hex("4A3B36"), K.hex("3A3336") }

type Palette = { ember: Color3, hot: Color3, deep: Color3 }

local function paletteFor(stageId: number): Palette
	local ooze = Stages.get(stageId).ooze
	local ember = K.hex(ooze.bright)
	return { ember = ember, hot = K.shade(ember, 0.35), deep = K.hex(ooze.deep) }
end

-- ── Snags ──────────────────────────────────────────────────────────────────────

--- One ember crack: a thin glowing sliver set proud of a trunk face.
local function crack(parent: Instance, onto: CFrame, w: number, h: number, palette: Palette, rng: Random)
	local len = h * K.pick(rng, { 0.35, 0.5, 0.65 })
	local face = rng:NextInteger(0, 3) * 90
	local cf = onto
		* CFrame.Angles(0, math.rad(face), 0)
		* CFrame.new(rng:NextNumber(-0.25, 0.25) * w, rng:NextNumber(-0.2, 0.2) * h, -w / 2 - 0.02)
		* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-12, 12)))
	K.block(parent, "EmberCrack", cf, Vector3.new(0.16, len, 0.08), if rng:NextNumber() < 0.5 then palette.ember else palette.hot, { neon = true })
end

--- A charred trunk: three or four studded segments narrowing and bending a little as
--- they go up, a jagged broken top, one to three stub arms, ember cracks in the bark.
local function snag(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "CharredSnag"
	local height = rng:NextNumber(10, 16)
	local w = rng:NextNumber(1.8, 2.6)
	local segs = rng:NextInteger(3, 4)
	local frame = CFrame.new(at) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	local segH = height / segs
	for i = 1, segs do
		local k = 1 - (i - 1) * 0.16
		local sw = w * k
		-- Each segment tips a few degrees off the last, so the stem reads as grown, not stacked.
		frame = frame * CFrame.Angles(math.rad(rng:NextNumber(-5, 5)), 0, math.rad(rng:NextNumber(-5, 5)))
		local mid = frame * CFrame.new(0, segH / 2, 0)
		K.block(model, "Trunk", mid, Vector3.new(sw, segH + 0.3, sw), K.pick(rng, WOOD), { studs = true })
		if rng:NextNumber() < 0.7 then
			crack(model, mid, sw, segH, palette, rng)
		end
		-- An arm off the middle segments, snapped short and angled up.
		if i > 1 and rng:NextNumber() < 0.55 then
			local len = rng:NextNumber(1.8, 3.6)
			local arm = mid
				* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
				* CFrame.Angles(0, 0, math.rad(rng:NextNumber(40, 65)))
				* CFrame.new(0, len / 2 + sw * 0.3, 0)
			K.block(model, "Arm", arm, Vector3.new(sw * 0.38, len, sw * 0.38), K.pick(rng, WOOD), { studs = true })
		end
		frame = frame * CFrame.new(0, segH, 0)
	end
	-- The broken top: a wedge snapped off at an angle, black where it burned through.
	local topW = w * (1 - segs * 0.16)
	K.wedge(model, "BrokenTop", frame * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0), Vector3.new(topW, 1.1, topW), CHAR, { studs = true })
	-- A skirt of char and ash where it meets the ground.
	K.disc(model, "AshSkirt", at + Vector3.new(0, 0.012, 0), w * 3.2, w * 2.6, 0.04, rng:NextNumber(0, 360), ASH[2])
	model.Parent = parent
end

local function stump(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local h = rng:NextNumber(0.9, 2.6)
	local d = rng:NextNumber(1.4, 2.4)
	local base = CFrame.new(at) * CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, math.rad(rng:NextNumber(-4, 4)))
	K.column(parent, "Stump", base * CFrame.new(0, h / 2, 0), h, d, K.pick(rng, WOOD), { studs = true })
	-- Burned-out heart: a glowing ring on some, a black cap on the rest.
	if rng:NextNumber() < 0.45 then
		K.column(parent, "StumpEmbers", base * CFrame.new(0, h + 0.02, 0), 0.08, d * 0.62, palette.ember, { neon = true })
	else
		K.column(parent, "StumpChar", base * CFrame.new(0, h + 0.02, 0), 0.08, d * 0.7, CHAR)
	end
	-- Root flares.
	for i = 1, rng:NextInteger(2, 3) do
		local yaw = i * 120 + rng:NextNumber(-25, 25)
		local cf = base * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.new(0, 0.3, -d * 0.55)
		K.wedge(parent, "Root", cf, Vector3.new(0.6, 0.7, d * 0.55), K.pick(rng, WOOD), { studs = true })
	end
end

local function log(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local len = rng:NextNumber(6, 11)
	local d = rng:NextNumber(0.9, 1.5)
	local yaw = rng:NextNumber(0, 360)
	-- Cylinders lie along local X already: a yaw is all a fallen log needs.
	local cf = CFrame.new(at + Vector3.new(0, d / 2 - 0.15, 0)) * CFrame.Angles(0, math.rad(yaw), math.rad(rng:NextNumber(-3, 3)))
	K.block(parent, "Log", cf, Vector3.new(len, d, d), K.pick(rng, WOOD), { studs = true, shape = Enum.PartType.Cylinder })
	-- Glowing split along its top on some; a snapped stub arm on the rest.
	if rng:NextNumber() < 0.5 then
		K.block(parent, "LogEmbers", cf * CFrame.new(rng:NextNumber(-0.2, 0.2) * len, d / 2, 0), Vector3.new(len * 0.4, 0.08, 0.18), palette.ember, { neon = true })
	else
		local arm = cf * CFrame.new(rng:NextNumber(-0.3, 0.3) * len, d * 0.3, 0) * CFrame.Angles(math.rad(rng:NextNumber(20, 50)), 0, 0) * CFrame.new(0, 0.9, 0)
		K.block(parent, "Arm", arm, Vector3.new(0.4, 1.8, 0.4), K.pick(rng, WOOD), { studs = true })
	end
end

-- ── Ember beds ─────────────────────────────────────────────────────────────────

local function emberBed(parent: Instance, at: Vector3, rng: Random, palette: Palette, flags: { light: boolean, sparks: boolean, smoke: boolean })
	local model = Instance.new("Model")
	model.Name = "EmberBed"
	local r = rng:NextNumber(2.2, 3.8)
	local y = at.Y
	-- The underglow first, flattest: the heat showing through the ash.
	local glow = K.blob(model, "Underglow", at.X, at.Z, y + 0.012, r * 2.4, 0.04, palette.deep, rng)
	-- Small and pulled toward the deep orange: Neon blooms a shade hotter than its
	-- colour, and a big bright core shot live as a yellow puddle rather than embers.
	K.blob(model, "HotCore", at.X, at.Z, y + 0.03, r * 0.8, 0.05, palette.ember:Lerp(palette.deep, 0.35), rng, { neon = true, transparency = 0.3 })
	-- Cinder heaped round it, and glowing chips in among the cinder.
	for i = 1, rng:NextInteger(6, 9) do
		local t = (i / 8) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local d = r * rng:NextNumber(0.55, 1.05)
		local s = rng:NextNumber(0.6, 1.2)
		local cf = CFrame.new(at.X + math.cos(t) * d, y + s * 0.25, at.Z + math.sin(t) * d)
			* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-25, 25)))
		K.block(model, "Cinder", cf, Vector3.new(s, s * 0.6, s * rng:NextNumber(0.8, 1.2)), K.pick(rng, CINDER), { studs = true })
	end
	for _ = 1, rng:NextInteger(6, 10) do
		local t = rng:NextNumber(0, math.pi * 2)
		local d = r * rng:NextNumber(0, 0.75)
		local s = rng:NextNumber(0.25, 0.6)
		local cf = CFrame.new(at.X + math.cos(t) * d, y + 0.12 + s * 0.2, at.Z + math.sin(t) * d)
			* CFrame.Angles(math.rad(rng:NextNumber(-30, 30)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-30, 30)))
		K.block(model, "Ember", cf, Vector3.new(s, s * 0.5, s), if rng:NextNumber() < 0.6 then palette.ember else palette.hot, { neon = true })
	end
	if flags.light then
		K.glow(glow, palette.ember, 12, 1.3)
	end
	if flags.sparks or flags.smoke then
		local a = K.anchor(model, "Vent", at + Vector3.new(0, 0.3, 0), Vector3.new(r, 0.2, r))
		if flags.sparks then
			K.smoke(a, "Sparks", {
				texture = K.SPARK_TEXTURE,
				from = palette.hot,
				to = palette.ember,
				size = { 0.35, 0.3, 0.1 },
				opacity = 1,
				lifetime = { 1.8, 3 },
				rate = 3,
				speed = { 2, 4 },
				spread = 25,
				accel = K.WIND + Vector3.new(0, 0.6, 0),
				light = 1,
			})
		end
		if flags.smoke then
			K.smoke(a, "Smoke", {
				from = K.hex("2E2A30"),
				to = K.hex("6A6472"),
				size = { 1.2, 3.4, 7.5 },
				opacity = 0.5,
				lifetime = { 7, 10 },
				rate = 2.5,
				speed = { 2, 3.2 },
				accel = K.WIND + Vector3.new(0, 0.1, 0),
			})
		end
	end
	model.Parent = parent
end

-- ── The ground ─────────────────────────────────────────────────────────────────

local function twig(parent: Instance, x: number, z: number, groundY: number, rng: Random)
	for _ = 1, rng:NextInteger(1, 3) do
		local len = rng:NextNumber(1.2, 3)
		local cf = CFrame.new(x + rng:NextNumber(-1, 1), groundY + 0.12, z + rng:NextNumber(-1, 1))
			* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
			* CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, 0)
		K.block(parent, "BurntTwig", cf, Vector3.new(0.22, 0.22, len), K.pick(rng, WOOD))
	end
end

function CinderField.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "CinderField"

	local snags = K.sites(f, SNAGS, 26, rng, 8)
	for _, at in snags do
		snag(folder, at, rng, palette)
	end
	local taken: { { number } } = {}
	for _, s in snags do
		table.insert(taken, { s.X, s.Z, 12 })
	end

	local beds = K.sites(f, EMBER_BEDS, 18, rng, 2, taken)
	for i, at in beds do
		emberBed(folder, at, rng, palette, {
			light = i <= BED_LIGHTS,
			-- Sparks and smoke on different beds, spread down the field by index.
			sparks = i % 3 == 1 and i <= BED_SPARKS * 3,
			smoke = i % 3 == 2 and i <= BED_SMOKE * 3,
		})
		table.insert(taken, { at.X, at.Z, 10 })
	end

	for _, at in K.sites(f, STUMPS, 12, rng, 3, taken) do
		stump(folder, at, rng, palette)
		table.insert(taken, { at.X, at.Z, 7 })
	end
	for _, at in K.sites(f, LOGS, 14, rng, 4, taken) do
		log(folder, at, rng, palette)
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z, col, row)
		local roll = rng:NextNumber()
		if roll < ASH_CHANCE then
			local lift = ((2 * col + row) % 4) * 0.003
			K.blob(ground, "Ash", x, z, groundY + 0.008 + lift, rng:NextNumber(3.5, 9), 0.04, K.pick(rng, ASH), rng, nil, 0.0025)
		elseif roll < ASH_CHANCE + CINDER_CHANCE then
			K.grit(ground, x, z, groundY, CINDER, rng, "Cinder")
		elseif roll < ASH_CHANCE + CINDER_CHANCE + SPECK_CHANCE then
			for _ = 1, rng:NextInteger(2, 4) do
				local s = rng:NextNumber(0.2, 0.4)
				local cf = CFrame.new(x + rng:NextNumber(-1.2, 1.2), groundY + 0.08, z + rng:NextNumber(-1.2, 1.2))
					* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
				K.block(ground, "Ember", cf, Vector3.new(s, 0.14, s), palette.ember, { neon = true })
			end
		elseif roll < ASH_CHANCE + CINDER_CHANCE + SPECK_CHANCE + TWIG_CHANCE then
			twig(ground, x, z, groundY, rng)
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return CinderField
