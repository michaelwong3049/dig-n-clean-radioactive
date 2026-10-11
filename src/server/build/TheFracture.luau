--!strict
--[[
	TheFracture.luau — Stage 15, The Fracture: the valley floor broken in straight lines,
	plates of it heaved up on edge, and cold cyan light coming up out of the break.

	    called from build/Scenery's buildStageScenery (Stage 15)

	WHAT IS OUT HERE, landmarks first:

	  * THE FRACTURE — one long break zig-zagging down the field south of the lane, in
	    straight runs with hard corners (build/BloodrockRift's rift wanders; this one
	    snaps), a black gap with the stage's cyan `ooze` lighting its floor and splinters
	    of the ground hanging in the air over it.
	  * HEAVED PLATES — slabs of the floor tipped up on one edge, studded side up, the
	    tall things you steer by, mostly along the north side of the break.
	  * SHARD STACKS — thin cyan glass blades jutting out of the ground in fans.
	  * THE GROUND — straight hairline cracks lit faintly cyan, dark grit.

	THE GAP IS FLAT. The plate cannot be dug into, so the depth is painted: a near-black
	strip, a glow down its middle, and the near edge of each run raised a little so the
	eye reads the dark as a drop.

	ITS OWN SEED, never build/Scenery's stage rng. See build/BiomeKit for the rules every
	far field keeps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local TheFracture = {}

local SEED = 15300

--- The fracture's runs: each one RUN_MIN..RUN_MAX studs long, turning by TURN_MIN..TURN_MAX
--- degrees at every corner, held between its two z limits.
local RUN_MIN, RUN_MAX = 18, 34
local TURN_MIN, TURN_MAX = 25, 55
local LIGHT_EVERY = 2

local PLATES = 4
local SHARD_FANS = 3

local CELL = 13
local CRACK_CHANCE = 0.012
local GRIT_CHANCE = 0.015

local ROCK = { K.hex("1F4450"), K.hex("173843"), K.hex("2A5260"), K.hex("12303A") }
local GAP = K.hex("040A0E")
local GRIT = { K.hex("0E242C"), K.hex("2E5A68"), K.hex("0A1A20") }

type Palette = { glow: Color3, deep: Color3, hot: Color3 }

local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	local glow = K.hex(def.ooze.bright)
	return { glow = glow, deep = K.hex(def.ooze.deep), hot = glow:Lerp(Color3.new(1, 1, 1), 0.4) }
end

-- ── The fracture ───────────────────────────────────────────────────────────────

local function fracturePath(f: K.Field, zMin: number, zMax: number, rng: Random): { Vector3 }
	local pts = {}
	local x = f.minX + 8
	local z = rng:NextNumber(zMin, zMax)
	local heading = 0
	local sign = if rng:NextNumber() < 0.5 then 1 else -1
	table.insert(pts, Vector3.new(x, f.groundY, z))
	while x < f.maxX - 8 do
		heading = sign * math.rad(rng:NextNumber(TURN_MIN, TURN_MAX))
		sign = -sign
		local len = rng:NextNumber(RUN_MIN, RUN_MAX)
		x = math.min(x + math.cos(heading) * len, f.maxX - 8)
		z = math.clamp(z + math.sin(heading) * len, zMin, zMax)
		table.insert(pts, Vector3.new(x, f.groundY, z))
	end
	return pts
end

local function fracture(parent: Instance, pts: { Vector3 }, w: number, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "Fracture"
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local seg = CFrame.lookAt(mid, b)
		local ww = w * rng:NextNumber(0.8, 1.15)
		-- +w overlap fills the outside of each hard corner.
		K.block(model, "Gap", seg * CFrame.new(0, 0.02, 0), Vector3.new(ww, 0.06, len + ww), GAP, { shadow = false })
		local floor = K.block(model, "GapLight", seg * CFrame.new(0, 0.05, 0), Vector3.new(math.max(0.3, ww * 0.25), 0.06, len + ww * 0.6), palette.glow, { neon = true })
		K.block(model, "GapHalo", seg * CFrame.new(0, 0.04, 0), Vector3.new(ww * 0.55, 0.06, len + ww * 0.8), palette.deep, { neon = true, transparency = 0.4 })
		if i % LIGHT_EVERY == 1 then
			K.glow(floor, palette.glow, 16, 1.3)
		end
		-- The near (north) lip raised: one long studded ledge per run, broken in two.
		for k = 0, 1 do
			local along = (k - 0.5) * len / 2
			K.block(model, "Ledge", seg * CFrame.new(ww / 2 + 0.7, 0.5, along), Vector3.new(1.4, 1 + rng:NextNumber(0, 0.6), len / 2 - 0.4), K.pick(rng, ROCK), { studs = true })
		end
		-- A splinter of the floor hanging over the gap, turned on edge, one per run.
		local h = rng:NextNumber(3, 7)
		local cf = seg * CFrame.new(rng:NextNumber(-0.2, 0.2) * ww, h, rng:NextNumber(-0.3, 0.3) * len)
			* CFrame.Angles(math.rad(rng:NextNumber(-40, 40)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(50, 80)))
		K.block(model, "Splinter", cf, Vector3.new(rng:NextNumber(1.6, 3), 0.5, rng:NextNumber(1, 2)), K.pick(rng, ROCK), { studs = true })
	end
	model.Parent = parent
end

-- ── Heaved plates and shard fans ───────────────────────────────────────────────

local function plate(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "HeavedPlate"
	local w = rng:NextNumber(10, 15)
	local d = rng:NextNumber(7, 11)
	local tilt = rng:NextNumber(28, 52)
	local yaw = rng:NextNumber(0, 360)
	-- Hinged on its -Z edge, which stays on the ground; the +Z edge is lifted (a
	-- negative turn about X tips local +Z up).
	local hinge = CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.new(0, 0, -d / 2)
	local cf = hinge * CFrame.Angles(math.rad(-tilt), 0, 0) * CFrame.new(0, 0.6, d / 2)
	K.block(model, "Plate", cf, Vector3.new(w, 1.2, d), K.pick(rng, ROCK), { studs = true })
	-- The torn edge it came out of: a dark hole and a glow line on the ground beside it.
	K.block(model, "Socket", hinge * CFrame.new(0, 0.03, d / 2), Vector3.new(w, 0.05, d), GAP, { shadow = false })
	K.block(model, "SocketGlow", hinge * CFrame.new(0, 0.06, d), Vector3.new(w * 0.9, 0.05, 0.3), palette.glow, { neon = true })
	model.Parent = parent
end

local function shardFan(parent: Instance, at: Vector3, rng: Random, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "ShardFan"
	local face = rng:NextNumber(0, 360)
	for i = 1, rng:NextInteger(4, 6) do
		local h = rng:NextNumber(2, 4.5)
		K.crystal(model, "Blade", at + Vector3.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6)), h, h * 0.16, face + (i - 3) * 22, rng:NextNumber(15, 40), if i % 2 == 0 then palette.hot else palette.glow, { material = Enum.Material.Glass, transparency = 0.2 })
	end
	model.Parent = parent
end

function TheFracture.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local f = K.field(stageId, groundY)

	local folder = Instance.new("Folder")
	folder.Name = "TheFracture"

	local taken: { { number } } = {}
	local path = fracturePath(f, -(f.maxZ - 14), -(K.LANE_HALF + 10), rng)
	fracture(folder, path, rng:NextNumber(8, 10), rng, palette)
	-- The polyline only has a point every 18-34 studs, so block along each run, not
	-- just at the corners.
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		for t = 0, 1, 0.25 do
			local p = a:Lerp(b, t)
			table.insert(taken, { p.X, p.Z, 9 })
		end
	end

	for _, at in K.sites(f, PLATES, 30, rng, 9, taken) do
		plate(folder, at, rng, palette)
		table.insert(taken, { at.X, at.Z, 12 })
	end
	for _, at in K.sites(f, SHARD_FANS, 18, rng, 3, taken) do
		shardFan(folder, at, rng, palette)
	end

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	K.grid(f, CELL, rng, function(x, z)
		local roll = rng:NextNumber()
		if roll < CRACK_CHANCE then
			-- A hairline: two straight slivers meeting at a hard angle.
			local heading = rng:NextNumber(0, 360)
			local px, pz = x, z
			for _ = 1, 2 do
				local len = rng:NextNumber(2, 4)
				local dx, dz = math.cos(math.rad(heading)), -math.sin(math.rad(heading))
				K.block(ground, "Hairline", CFrame.new(px + dx * len / 2, groundY + 0.06, pz + dz * len / 2) * CFrame.Angles(0, math.rad(heading), 0), Vector3.new(len, 0.05, 0.14), palette.glow:Lerp(GAP, 0.35), { neon = true })
				px, pz = px + dx * len, pz + dz * len
				heading += (if rng:NextNumber() < 0.5 then 1 else -1) * rng:NextNumber(35, 70)
			end
		elseif roll < CRACK_CHANCE + GRIT_CHANCE then
			K.grit(ground, x, z, groundY, GRIT, rng)
		end
	end)
	ground.Parent = folder

	folder.Parent = parent
end

return TheFracture
