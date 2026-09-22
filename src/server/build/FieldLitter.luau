--!strict
--[[
	FieldLitter.luau — the dirt, grit, rubble and broken window glass lying on a field
	that was never cleared.

	    called from build/Scenery's buildStageScenery (Stage 3, after the drums)

	WHY A SECOND DEBRIS MODULE AND NOT build/BlastDebris.
	BlastDebris is the blast's OWN debris: everything in it is placed against the
	craters (`nearBlast`), it refuses to build for a stage with no craters, and the
	things it throws — girders, bent rebar, folded sheet steel — are wreckage that was
	standing until the fireball took it. Stage 3 has no craters and nothing was standing
	on it. What is out here is what BLEW IN and settled: drifted dirt, grit, broken
	concrete, and glass out of windows that shattered somewhere else. Same jittered-grid
	technique, different story and a different mix, so it is a sibling rather than a
	flag on that file.

	FOUR KINDS, dealt off one jittered grid so the field is covered without clumping or
	bald patches (the same reasoning as every other scatter in build/Scenery):

	  * DIRT — flat drifts of ash and pale dust lying on the checkerboard, each a few
	    overlapping ovals in one colour, so it reads as one smear of ground rather than
	    a stack of discs.
	  * GRIT — a handful of small stones and chips.
	  * GLASS — a spray of window shards thrown along one line, thickest where the pane
	    hit, sometimes with a bigger jagged plate stuck in the dirt at the head of it.
	  * RUBBLE — broken concrete, occasionally with a stub of rebar leaning out.

	LIGHT, ON REQUEST. Stage 3's identity is bare khaki ground with the drums as the
	only landmarks you steer by (see build/Scenery's THEME note for Stage 3), and that
	survives this pass: the ground should read as littered when you look DOWN and still
	read as empty from across the field. That is what the low per-cell chances below
	buy, and it is the constraint to retune against — not "is there enough debris".

	LOW, FLAT AND WALK-THROUGH, BECAUSE THIS IS DUG GROUND. Signals spawn anywhere out
	here, so this file keeps to build/Scenery's two standing rules for anything over a
	dig plate: CanCollide false (walk through it) and low enough that a haul rising
	underneath still shows. The dirt stays flat under a detector spot's cracks and the
	range ring (see DIRT_* below); nothing else reaches a stud and a half, and the only
	pieces that go over it are rebar stubs, a finger thick — the same exemption
	build/BlastDebris makes, for the same reason. MEASURED ON THE BUILT FIELD: dirt
	tops out 0.05 over the cap, grit 0.68, concrete 1.23, the canted glass plate 1.22
	(1.47 at the top of its range), rebar 1.91.

	THE WALK LANE STAYS CLEAR OF ANYTHING THAT STANDS UP. Flat litter crosses z = 0
	freely — dirt underfoot on the path is the point. Concrete chunks and the canted
	glass plate do not: they are the only pieces here tall enough to read as an
	obstacle, and one sitting in the middle of the route reads as a mistake the way a
	carcass laid across it does (build/Scenery's SKELETON_CENTRE_CLEARANCE).

	ITS OWN SEED. Never the stage rng, so adding or retuning this cannot move a single
	bone or drum anywhere else.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)

local FieldLitter = {}

local SEED = 8400

--- The grid: one roll per CELL-stud cell, held EDGE_MARGIN clear of the plate's edges
--- (the side walls and the stage seams' border strips).
local CELL = 14
local EDGE_MARGIN = 6

--- Per-cell chances. They sum to 0.30 — roughly one cell in three carries something,
--- which over Stage 3's 290 x 170 plate is about seventy sites in the whole field.
--- Read the header before raising any of them.
local DIRT_CHANCE = 0.14
local GRIT_CHANCE = 0.08
local GLASS_CHANCE = 0.05
local RUBBLE_CHANCE = 0.03

--- Share of dirt drifts that are pale dust rather than dark ash. Lower than an even
--- split because the ash is the one that works here: Stage 3's ground is already a
--- light khaki, so a drift DARKER than it reads as dirt immediately while a lighter one
--- has to be very subtle to avoid reading as a spill (see `dust` in paletteFor).
local DUST_SHARE = 0.35

--- Half-width of the open walk lane down z = 0. Matches build/Scenery's
--- BARREL_CENTRE_CLEARANCE — the drums are the other thing out here that has to keep
--- off the route, and two different lane widths on one field would read as neither.
local LANE_HALF = 16

--- Dirt heights over the checker cap, lifted straight from build/BlastDebris: a drift
--- tops out ~0.047 over it (0.107 over the plate), under the range ring's rim and a
--- detector spot's cracks (client/SpotCracks, 0.15 and up), so a signal under a drift
--- still shows. DIRT_STEP separates a drift's own ovals, DIRT_LIFT neighbouring drifts
--- — ovals at one height would z-fight.
local DIRT_BASE = 0.008
local DIRT_STEP = 0.0025
local DIRT_LIFT = 0.003
local DIRT_THICK = 0.04

--- Glass lies flatter than anything else here and is the one kind that regularly
--- overlaps itself (a spray is a line of pieces, and a line doubles back), so the
--- shards get their own thin height band over the dirt rather than sharing it. The top
--- of a shard lands 0.105 over the checker cap — still under the detector spot's
--- cracks, same ceiling the dirt respects.
local GLASS_BASE = 0.055
local GLASS_STEP = 0.004
local GLASS_THICK = 0.05

--- NOT Enum.Material.Glass, the same call build/CraterField's fused glass made and for
--- the same reason: shot live, that material mirrors the stage's bright hazy sky off
--- anything flat and upward-facing and washes the tint straight out of it. Smooth
--- plastic with a little transparency and a little reflectance keeps the colour and
--- still catches a sheen at a low angle.
local GLASS_TRANSPARENCY = 0.45
local GLASS_REFLECTANCE = 0.12

-- ── Colour ─────────────────────────────────────────────────────────────────────
-- The ground's own khaki pushed toward ash or dust for the dirt and grit, so a drift
-- reads as this field's own dirt moved around rather than as something dropped on it.
-- The concrete and the glass came from somewhere else and keep their own colours:
-- grey, and the pale green a pane of window glass shows edge-on.
local ASH = Color3.fromHex("4A3F32")
local DUST = Color3.fromHex("D8CDB6")

type Palette = {
	ash: Color3,
	dust: Color3,
	grit: { Color3 },
	concrete: { Color3 },
	rust: { Color3 },
	glass: { Color3 },
}

local function paletteFor(stageId: number): Palette
	local base = Color3.fromHex(Stages.get(stageId).color)
	return {
		ash = base:Lerp(ASH, 0.5),
		-- 0.26, NOT build/BlastDebris's 0.4, and the difference is the ground underneath:
		-- that file lifts its dust off a near-black violet, where 0.4 is a whisper. Stage 3
		-- is light khaki already, so the same lerp shot live here as cream blobs reading as
		-- spilled paint from across the field. 0.26 is the most separation this ground will
		-- take before a drift stops being ground.
		dust = base:Lerp(DUST, 0.26),
		grit = { base:Lerp(ASH, 0.6), base:Lerp(ASH, 0.38), base:Lerp(DUST, 0.25) },
		concrete = { Color3.fromHex("8E8894"), Color3.fromHex("77727E") },
		rust = { Color3.fromHex("7A4430"), Color3.fromHex("5E3526") },
		-- Window glass, seen through: the green a pane shows edge-on, a bluer sheet tone,
		-- and a paler chip.
		--
		-- SATURATED ENOUGH TO SEPARATE FROM BONE, which is the real constraint on these
		-- three and not "what colour is glass". This field is already littered with
		-- bleached bone (build/Scenery's scatterBones, denser here than anywhere), and a
		-- near-white shard at 0.45 transparency over tan ground washes out to exactly that
		-- cream — so from any distance the glass read as more bone chips. Cool and green
		-- is the one direction the bone palette never goes.
		glass = { Color3.fromHex("9CC7B2"), Color3.fromHex("8FB6C6"), Color3.fromHex("B9D4C6") },
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

--- A flattened ellipsoid lying on the ground (a Sphere SpecialMesh — a round Shape
--- forces a circle; see build/Scenery's oozeDisc).
local function disc(parent: Instance, at: Vector3, a: number, b: number, yaw: number, color: Color3)
	local p = block(parent, "Dirt", CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0), Vector3.one, color)
	p.CastShadow = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(a, DIRT_THICK, b)
	mesh.Parent = p
end

--- One shard: a WedgePart, so the piece is a TRIANGLE and not a rectangle. A broken
--- pane does not leave squares, and a flat rectangle at this size reads as a tile of
--- the floor lifted up — the diagonal edge is most of what says "broken" from standing
--- height. Thin, see-through and lightly reflective (see GLASS_* above).
local function shard(parent: Instance, cf: CFrame, w: number, len: number, color: Color3)
	local p = Instance.new("WedgePart")
	p.Name = "GlassShard"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = GLASS_TRANSPARENCY
	p.Reflectance = GLASS_REFLECTANCE
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Size = Vector3.new(w, GLASS_THICK, len)
	p.CFrame = cf
	p.Parent = parent
end

local function yawCF(x: number, y: number, z: number, yawDeg: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yawDeg), 0)
end

-- ── The four kinds ─────────────────────────────────────────────────────────────

local function dirtDrift(parent: Instance, x: number, z: number, groundY: number, lift: number, rng: Random, palette: Palette)
	local color = if rng:NextNumber() < DUST_SHARE then palette.dust else palette.ash
	local size = rng:NextNumber(3.5, 10)
	local yaw = rng:NextNumber(0, 360)
	for i = 1, rng:NextInteger(2, 4) do
		local a = if i == 1 then size else size * rng:NextNumber(0.35, 0.7)
		local b = a / rng:NextNumber(1.4, 2.4)
		local ox, oz = 0, 0
		if i > 1 then
			-- Lobes off the body's long axis, the same way the ooze puddles grow theirs, so a
			-- drift stretches into a smear instead of rounding into a blob.
			local along = math.rad(yaw + (if i % 2 == 0 then 0 else 180) + rng:NextNumber(-25, 25))
			local reach = size * rng:NextNumber(0.2, 0.44)
			ox, oz = math.cos(along) * reach, math.sin(along) * reach
		end
		local y = groundY + DIRT_BASE + lift + i * DIRT_STEP
		disc(parent, Vector3.new(x + ox, y, z + oz), a, b, yaw + rng:NextNumber(-30, 30), color)
	end
end

local function grit(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette)
	for _ = 1, rng:NextInteger(4, 7) do
		local s = rng:NextNumber(0.22, 0.7)
		local size = Vector3.new(s * rng:NextNumber(0.8, 1.3), s * rng:NextNumber(0.5, 0.8), s * rng:NextNumber(0.8, 1.3))
		local t = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(0, 1.7)
		local cf = CFrame.new(x + math.cos(t) * d, groundY + size.Y * 0.3, z + math.sin(t) * d)
			* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-25, 25)))
		block(parent, "Grit", cf, size, pick(rng, palette.grit))
	end
end

--- Broken concrete, one to three chunks, the biggest sometimes still holding a stub of
--- rebar leaning out of it.
local function rubble(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette)
	local s = rng:NextNumber(0.8, 1.7)
	for i = 1, rng:NextInteger(1, 3) do
		local k = 1 - (i - 1) * 0.25
		local size = Vector3.new(s * k * rng:NextNumber(0.8, 1.3), s * k * rng:NextNumber(0.45, 0.7), s * k * rng:NextNumber(0.8, 1.4))
		local ox = if i == 1 then 0 else rng:NextNumber(-1, 1) * s
		local oz = if i == 1 then 0 else rng:NextNumber(-1, 1) * s
		local cf = CFrame.new(x + ox, groundY + size.Y * 0.35, z + oz)
			* CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-20, 20)))
		block(parent, "Concrete", cf, size, pick(rng, palette.concrete), true)
		if i == 1 and rng:NextNumber() < 0.5 then
			local len = rng:NextNumber(1, 1.7)
			local root = cf * CFrame.new(rng:NextNumber(-0.3, 0.3) * size.X, size.Y * 0.3, rng:NextNumber(-0.3, 0.3) * size.Z)
			local bar = CFrame.new(root.Position)
				* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
				* CFrame.Angles(math.rad(rng:NextNumber(35, 70)), 0, 0)
				* CFrame.new(0, len / 2, 0)
			block(parent, "Rebar", bar, Vector3.new(0.14, len, 0.14), pick(rng, palette.rust))
		end
	end
end

--- A pane's worth of window glass, thrown along ONE line rather than scattered round a
--- point. That is the whole read: glass that fell where it broke makes a ring, glass
--- that BLEW here makes a streak, and a streak is what says this came from somewhere
--- off the field. The pieces spread wider and shrink down the streak (`t` drives both),
--- so the near end is where the pane came down.
---
--- `canStand` is false in the walk lane — see the header. The plate at the head of the
--- streak is the only piece of this that stands up at all.
local function glassSpray(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette, canStand: boolean)
	local color = pick(rng, palette.glass)
	local heading = rng:NextNumber(0, math.pi * 2)
	local reach = rng:NextNumber(4, 9)
	local dirX, dirZ = math.cos(heading), math.sin(heading)
	-- Across the streak, so a shard can drift off the line without the line bending.
	local sideX, sideZ = -dirZ, dirX

	local count = rng:NextInteger(5, 9)
	for i = 1, count do
		local t = (i - 1) / count
		local along = t * reach
		local side = rng:NextNumber(-1, 1) * (0.5 + t * 2.2)
		local w = rng:NextNumber(0.5, 1.5) * (1 - t * 0.5)
		local len = w * rng:NextNumber(1.1, 2.4)
		-- Every shard on its own step of the height band: a streak doubles back on itself
		-- often enough that two at one height would z-fight.
		local y = groundY + GLASS_BASE + (i % 5) * GLASS_STEP
		local cf = yawCF(x + dirX * along + sideX * side, y, z + dirZ * along + sideZ * side, rng:NextNumber(0, 360))
			-- A couple of degrees of roll, so the sheen breaks up across the streak instead
			-- of every shard catching the light at once.
			* CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, math.rad(rng:NextNumber(-4, 4)))
		shard(parent, cf, w, len, color)
	end

	-- The plate at the head of the streak: a bigger piece that went in edge-first and
	-- stuck rather than settling flat. Canted, never upright — a pane standing on end in
	-- open ground reads as placed.
	if canStand and rng:NextNumber() < 0.45 then
		local w = rng:NextNumber(1.6, 2.6)
		local len = rng:NextNumber(1.4, 2.0)
		local tilt = rng:NextNumber(32, 52)
		-- Rotating about the piece's own X by a NEGATIVE angle lifts its local +Z, so
		-- pushing it out along that axis buries the near corner and stands the rest out of
		-- the dirt. 0.3 of the length, not 0.5: at the steep end of the tilt range a half
		-- pushes the top corner past the stud-and-a-half ceiling this file keeps to.
		--
		-- THE THREE RANGES ABOVE ARE AGAINST THAT CEILING, NOT TASTE. A plate's top corner
		-- sits at 0.3*len*sin(tilt) + len/2*sin(tilt) + w/2*sin(roll) over the ground, so
		-- length and tilt both push it up and the width comes along through the roll. The
		-- first pass ran 1.8-3.2 x 1.6-2.4 at 38-62 degrees and measured 1.62 live; these
		-- measure 1.47. Raise any one of them and re-measure the built field.
		local cf = yawCF(x - dirX * 1.2, groundY, z - dirZ * 1.2, math.deg(heading) + rng:NextNumber(-25, 25))
			* CFrame.Angles(math.rad(-tilt), 0, math.rad(rng:NextNumber(-10, 10)))
			* CFrame.new(0, 0, len * 0.3)
		shard(parent, cf, w, len, color)
	end
end

-- ── Placement ──────────────────────────────────────────────────────────────────

--- Scatter the stage's litter into `parent` (buildStageScenery's stage folder).
--- `groundY` is the top of the checkerboard cap.
function FieldLitter.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED + stageId)
	local palette = paletteFor(stageId)
	local minX, minZ, maxX, maxZ = Stages.bounds(stageId)
	local x0, x1 = minX + EDGE_MARGIN, maxX - EDGE_MARGIN
	local z0, z1 = minZ + EDGE_MARGIN, maxZ - EDGE_MARGIN
	local cols = math.max(1, math.floor((x1 - x0) / CELL))
	local rows = math.max(1, math.floor((z1 - z0) / CELL))
	local cellW, cellH = (x1 - x0) / cols, (z1 - z0) / rows

	local folder = Instance.new("Folder")
	folder.Name = "FieldLitter"

	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			local x = x0 + (col + 0.5 + rng:NextNumber(-0.45, 0.45)) * cellW
			local z = z0 + (row + 0.5 + rng:NextNumber(-0.45, 0.45)) * cellH
			-- The walk lane runs down z = 0 in WORLD z, which is every stage's own
			-- centreline (Config/Stages `center` puts all six on it).
			local onLane = math.abs(z) < LANE_HALF

			local roll = rng:NextNumber()
			local gritEnd = DIRT_CHANCE + GRIT_CHANCE
			local glassEnd = gritEnd + GLASS_CHANCE
			local rubbleEnd = glassEnd + RUBBLE_CHANCE
			if roll < DIRT_CHANCE then
				-- (2col + row) mod 4 differs between every pair of neighbouring cells,
				-- diagonals included, so two drifts that overlap never share a height.
				dirtDrift(folder, x, z, groundY, ((2 * col + row) % 4) * DIRT_LIFT, rng, palette)
			elseif roll < gritEnd then
				grit(folder, x, z, groundY, rng, palette)
			elseif roll < glassEnd then
				glassSpray(folder, x, z, groundY, rng, palette, not onLane)
			elseif roll < rubbleEnd and not onLane then
				rubble(folder, x, z, groundY, rng, palette)
			end
		end
	end

	folder.Parent = parent
end

return FieldLitter
