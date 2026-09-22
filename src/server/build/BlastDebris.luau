--!strict
--[[
	BlastDebris.luau — the dirt and wreckage strewn across a stage that has craters on it.

	    called from build/Scenery's buildStageScenery (Stage 6, after build/CraterField)

	Three kinds of thing, dealt off one jittered grid so the field is covered without
	clumping or bald patches (the same reasoning as every other scatter in build/Scenery):

	  * DIRT -- flat patches of ash and pale dust lying on the checkerboard, each a few
	    overlapping ovals in one colour, so it reads as one smear of ground, not a stack
	    of discs.
	  * GRAVEL -- a handful of small stones, knocked loose and scattered.
	  * WRECKAGE -- what the blast threw: concrete chunks (some with rebar sticking out),
	    sheets of metal bent up off the ground, broken girders, tangles of bent rebar.

	DENSER NEAR THE BLAST. Gravel and wreckage get likelier the closer a cell is to a
	crater's outer foot, and far likelier near the big one (`nearBlast`), so the debris
	thins out across the plain the way thrown material would. Dirt does not; it is the
	ground itself.

	KEPT OFF THE CRATERS. Nothing lands inside a crater's footprint: under a rim it would
	be buried in the berm, and the big crater's floor has its own ground-zero dressing
	(build/CraterField).

	LOW, FLAT AND WALK-THROUGH, BECAUSE THIS IS DUG GROUND. Signals spawn anywhere out
	here, so this file keeps to build/Scenery's two standing rules for anything over a
	dig plate: CanCollide false (walk through it) and low enough that a haul rising
	underneath still shows -- nothing stands much over a stud and a half, and the only
	pieces that do are rebar, a finger thick. The dirt stays flat under a detector spot's
	cracks and the range ring (see DIRT_* below).

	ITS OWN SEED. Never the stage rng, so adding or retuning this cannot move a single
	crater, bone or drum anywhere else.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local StageCraters = require(Shared.Config.StageCraters)

local BlastDebris = {}

type Crater = StageCraters.Crater

local SEED = 7300

--- The grid: one roll per CELL-stud cell, held EDGE_MARGIN clear of the plate's edges
--- (the side walls, the Stage 5 seam's border strip, Toxic Twilight's gate). Was 15,
--- which shot live as too sparse to read as a debris field.
local CELL = 12
local EDGE_MARGIN = 6

--- Per-cell chances. `*_NEAR` is added on top at a crater's outer foot and fades out
--- by NEAR_FALLOFF per unit of rho past it; a pock counts POCK_BLAST as hard as the
--- big crater.
local DIRT_CHANCE = 0.24
local GRAVEL_CHANCE = 0.16
local GRAVEL_NEAR = 0.22
local WRECK_CHANCE = 0.05
local WRECK_NEAR = 0.4
--- Share of dirt patches that are pale dust rather than dark ash.
local DUST_SHARE = 0.4
local NEAR_FALLOFF = 1.1
local POCK_BLAST = 0.35
--- How far past a crater's outer foot (rho) the scatter keeps clear.
local CRATER_CLEARANCE = 0.08
--- Radius at which a crater counts as the big one (build/CraterField's DETAILED_RADIUS).
local BIG_RADIUS = 20

--- Dirt heights over the checker cap. A patch tops out ~0.047 over it (0.107 over the
--- plate): under the range ring's rim and a detector spot's cracks (client/SpotCracks,
--- 0.15 and up), so a signal under a patch still shows. DIRT_STEP separates a patch's
--- own ovals, DIRT_LIFT neighbouring patches -- ovals at one height would z-fight.
local DIRT_BASE = 0.008
local DIRT_STEP = 0.0025
local DIRT_LIFT = 0.003
local DIRT_THICK = 0.04

-- ── Colour ─────────────────────────────────────────────────────────────────────
-- The ground's own violet pushed toward ash or dust for the dirt and gravel; the
-- wreckage is what it was made of -- grey concrete, dark steel, rust -- because it came
-- from somewhere else. The amber sky warms all of it.
local ASH = Color3.fromHex("3A3342")
local SCORCH = Color3.fromHex("1C0E2E")
local DUST = Color3.fromHex("9A8FA0")

type Palette = {
	ash: Color3,
	dust: Color3,
	gravel: { Color3 },
	concrete: { Color3 },
	steel: { Color3 },
	rust: { Color3 },
}

local function paletteFor(stageId: number): Palette
	local base = Color3.fromHex(Stages.get(stageId).color)
	return {
		ash = base:Lerp(SCORCH, 0.45),
		-- 0.38, not more: at 0.55 the dust shot live as bright blobs, read as puddles or
		-- snow from across the field rather than as ground.
		dust = base:Lerp(DUST, 0.38),
		gravel = { base:Lerp(ASH, 0.55), base:Lerp(ASH, 0.35), base:Lerp(SCORCH, 0.4) },
		concrete = { Color3.fromHex("8E8894"), Color3.fromHex("77727E") },
		steel = { Color3.fromHex("4A4852"), Color3.fromHex("3A3840") },
		rust = { Color3.fromHex("7A4430"), Color3.fromHex("5E3526") },
	}
end

local function pick(rng: Random, list: { Color3 }): Color3
	return list[rng:NextInteger(1, #list)]
end

-- ── Parts ──────────────────────────────────────────────────────────────────────

local function block(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, studded: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if studded then
		-- Concrete wears the studs like every rock in this world (build/Scenery `rock`);
		-- studs only render on Plastic.
		p.Material = Enum.Material.Plastic
		for _, face in { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" } do
			(p :: any)[face] = Enum.SurfaceType.Studs
		end
	else
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
	end
	p.Parent = parent
	return p
end

--- A flattened ellipsoid lying on the ground (a Sphere SpecialMesh -- a round Shape
--- forces a circle; see build/Scenery's oozeDisc).
local function disc(parent: Instance, at: Vector3, a: number, b: number, yaw: number, color: Color3)
	local p = block(parent, "Dirt", CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0), Vector3.one, color)
	p.CastShadow = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(a, DIRT_THICK, b)
	mesh.Parent = p
end

local function yawCF(x: number, y: number, z: number, yawDeg: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yawDeg), 0)
end

-- ── The three kinds ────────────────────────────────────────────────────────────

local function dirtPatch(parent: Instance, x: number, z: number, groundY: number, lift: number, rng: Random, palette: Palette)
	local color = if rng:NextNumber() < DUST_SHARE then palette.dust else palette.ash
	local size = rng:NextNumber(3, 9)
	local yaw = rng:NextNumber(0, 360)
	for i = 1, rng:NextInteger(2, 4) do
		local a = if i == 1 then size else size * rng:NextNumber(0.35, 0.7)
		local b = a / rng:NextNumber(1.3, 2.2)
		local ox, oz = 0, 0
		if i > 1 then
			-- Lobes off the body's long axis, the same way the ooze puddles grow theirs, so
			-- a patch stretches into a smear instead of rounding into a blob.
			local along = math.rad(yaw + (if i % 2 == 0 then 0 else 180) + rng:NextNumber(-25, 25))
			local reach = size * rng:NextNumber(0.2, 0.42)
			ox, oz = math.cos(along) * reach, math.sin(along) * reach
		end
		local y = groundY + DIRT_BASE + lift + i * DIRT_STEP
		disc(parent, Vector3.new(x + ox, y, z + oz), a, b, yaw + rng:NextNumber(-30, 30), color)
	end
end

local function gravel(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette)
	for _ = 1, rng:NextInteger(4, 8) do
		local s = rng:NextNumber(0.25, 0.8)
		local size = Vector3.new(s * rng:NextNumber(0.8, 1.3), s * rng:NextNumber(0.5, 0.8), s * rng:NextNumber(0.8, 1.3))
		local t = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, 1.8)
		local cf = CFrame.new(x + math.cos(t) * d, groundY + size.Y * 0.3, z + math.sin(t) * d)
			* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-25, 25)))
		block(parent, "Gravel", cf, size, pick(rng, palette.gravel))
	end
end

--- Broken concrete, one to three chunks, the biggest sometimes still holding a stub of
--- rebar leaning out of it.
local function concrete(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette)
	local s = rng:NextNumber(0.9, 2)
	for i = 1, rng:NextInteger(1, 3) do
		local k = 1 - (i - 1) * 0.25
		local size = Vector3.new(s * k * rng:NextNumber(0.8, 1.3), s * k * rng:NextNumber(0.45, 0.7), s * k * rng:NextNumber(0.8, 1.4))
		local ox = if i == 1 then 0 else rng:NextNumber(-1, 1) * s
		local oz = if i == 1 then 0 else rng:NextNumber(-1, 1) * s
		local cf = CFrame.new(x + ox, groundY + size.Y * 0.35, z + oz)
			* CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-20, 20)))
		block(parent, "Concrete", cf, size, pick(rng, palette.concrete), true)
		if i == 1 and rng:NextNumber() < 0.6 then
			local len = rng:NextNumber(1.1, 1.8)
			local root = cf * CFrame.new(rng:NextNumber(-0.3, 0.3) * size.X, size.Y * 0.3, rng:NextNumber(-0.3, 0.3) * size.Z)
			local bar = CFrame.new(root.Position)
				* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
				* CFrame.Angles(math.rad(rng:NextNumber(35, 70)), 0, 0)
				* CFrame.new(0, len / 2, 0)
			block(parent, "Rebar", bar, Vector3.new(0.14, len, 0.14), pick(rng, palette.rust))
		end
	end
end

--- A sheet of metal, one half flat on the ground and the other bent up off it at the fold.
local function sheet(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette)
	local w = rng:NextNumber(1.6, 3.2)
	local flatLen = rng:NextNumber(1, 2.2)
	local upLen = rng:NextNumber(0.8, 1.8)
	local thick = 0.08
	local color = if rng:NextNumber() < 0.5 then pick(rng, palette.steel) else pick(rng, palette.rust)
	local fold = yawCF(x, groundY + thick / 2 + 0.02, z, rng:NextNumber(0, 360))
	block(parent, "Sheet", fold * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6))) * CFrame.new(0, 0, -flatLen / 2), Vector3.new(w, thick, flatLen), color)
	-- Tilting about X by a negative angle lifts local +Z, so the far half rises off the
	-- fold instead of digging into the ground.
	local bent = fold * CFrame.Angles(math.rad(-rng:NextNumber(18, 50)), 0, math.rad(rng:NextNumber(-8, 8))) * CFrame.new(0, 0, upLen / 2)
	block(parent, "Sheet", bent, Vector3.new(w * rng:NextNumber(0.85, 1), thick, upLen), color)
end

--- A length of I-beam lying on its flange, one end nosed into the ground.
local function girder(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette)
	local len = rng:NextNumber(3.5, 7)
	local h = rng:NextNumber(0.6, 0.85)
	local t = 0.12
	local color = pick(rng, palette.rust)
	local cf = yawCF(x, groundY + h / 2 - 0.1, z, rng:NextNumber(0, 360)) * CFrame.Angles(math.rad(rng:NextNumber(3, 9)), 0, 0)
	block(parent, "Girder", cf, Vector3.new(t, h - 2 * t, len), color)
	block(parent, "Girder", cf * CFrame.new(0, h / 2 - t / 2, 0), Vector3.new(h * 0.9, t, len), color)
	block(parent, "Girder", cf * CFrame.new(0, -(h / 2 - t / 2), 0), Vector3.new(h * 0.9, t, len), color)
end

--- A few bars of rebar, each bent once, lying in a loose tangle.
local function rebar(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette)
	local color = pick(rng, palette.rust)
	for _ = 1, rng:NextInteger(3, 5) do
		local yaw = rng:NextNumber(0, math.pi * 2)
		local first = rng:NextNumber(1.2, 3)
		local second = rng:NextNumber(0.6, 1.6)
		local start = Vector3.new(x + rng:NextNumber(-1, 1), groundY + 0.07, z + rng:NextNumber(-1, 1))
		local dir1 = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
		local knee = start + dir1 * first
		local turn = yaw + math.rad(rng:NextNumber(20, 70) * (if rng:NextNumber() < 0.5 then 1 else -1))
		local dir2 = Vector3.new(math.cos(turn), rng:NextNumber(0.1, 0.5), math.sin(turn)).Unit
		block(parent, "Rebar", CFrame.lookAt(start + dir1 * first / 2, knee), Vector3.new(0.12, 0.12, first), color)
		block(parent, "Rebar", CFrame.lookAt(knee + dir2 * second / 2, knee + dir2 * second), Vector3.new(0.12, 0.12, second), color)
	end
end

local WRECKAGE: { { weight: number, build: (Instance, number, number, number, Random, Palette) -> () } } = {
	{ weight = 0.4, build = concrete },
	{ weight = 0.25, build = sheet },
	{ weight = 0.2, build = rebar },
	{ weight = 0.15, build = girder },
}

local function wreckage(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette)
	local roll = rng:NextNumber()
	for _, kind in WRECKAGE do
		if roll < kind.weight then
			kind.build(parent, x, z, groundY, rng, palette)
			return
		end
		roll -= kind.weight
	end
end

-- ── Placement ──────────────────────────────────────────────────────────────────

--- How close (x, z) is to the blast, 0..1, and whether it is clear of every crater.
local function nearBlast(craters: { Crater }, x: number, z: number): (number, boolean)
	local near = 0
	for _, c in craters do
		local past = StageCraters.rho(c, x, z) - c.outerFrac
		if past < CRATER_CLEARANCE then
			return 0, false
		end
		local weight = if c.radius >= BIG_RADIUS then 1 else POCK_BLAST
		near = math.max(near, weight * math.exp(-past * NEAR_FALLOFF))
	end
	return near, true
end

--- Scatter the stage's dirt and wreckage into `parent` (buildStageScenery's stage
--- folder). A stage with no craters gets nothing -- this is the blast's debris.
--- `groundY` is the top of the checkerboard cap.
function BlastDebris.build(parent: Instance, stageId: number, groundY: number)
	local craters = StageCraters.forStage(stageId)
	if #craters == 0 then
		return
	end

	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local minX, minZ, maxX, maxZ = Stages.bounds(stageId)
	local x0, x1 = minX + EDGE_MARGIN, maxX - EDGE_MARGIN
	local z0, z1 = minZ + EDGE_MARGIN, maxZ - EDGE_MARGIN
	local cols = math.max(1, math.floor((x1 - x0) / CELL))
	local rows = math.max(1, math.floor((z1 - z0) / CELL))
	local cellW, cellH = (x1 - x0) / cols, (z1 - z0) / rows

	local folder = Instance.new("Folder")
	folder.Name = "BlastDebris"

	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			local x = x0 + (col + 0.5 + rng:NextNumber(-0.45, 0.45)) * cellW
			local z = z0 + (row + 0.5 + rng:NextNumber(-0.45, 0.45)) * cellH
			local roll = rng:NextNumber()
			local near, clear = nearBlast(craters, x, z)
			if not clear then
				continue
			end

			local wreck = WRECK_CHANCE + WRECK_NEAR * near
			local stones = wreck + GRAVEL_CHANCE + GRAVEL_NEAR * near
			local dirt = stones + DIRT_CHANCE
			if roll < wreck then
				wreckage(folder, x, z, groundY, rng, palette)
			elseif roll < stones then
				gravel(folder, x, z, groundY, rng, palette)
			elseif roll < dirt then
				-- (2col + row) mod 4 differs between every pair of neighbouring cells,
				-- diagonals included, so two patches that overlap never share a height.
				dirtPatch(folder, x, z, groundY, ((2 * col + row) % 4) * DIRT_LIFT, rng, palette)
			end
		end
	end

	folder.Parent = parent
end

return BlastDebris
