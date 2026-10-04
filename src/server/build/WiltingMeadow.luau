--!strict
--[[
	WiltingMeadow.luau — Stage 1 (Fading Fields) as a wildflower meadow wilting from
	west to east: alive where you walk in from camp, dead by the Stage 2 seam.

	    called from build/Scenery's buildStageScenery (Stage 1, after the bushes, the
	    dead snags and the grass/rock ground detail)

	WHAT IS OUT HERE, landmarks first:

	  * THE CREEK — comes out from under the north wall near camp and runs east along
	    the north side, drying up as it goes: running water with reeds and cattails in
	    the west, then damp mud with stepping stones, then a cracked dry bed with a dead
	    fish on it where it gives out. A little plank footbridge crosses the wet stretch.
	  * THE HALF-DEAD TREE — one big tree at the middle of the field, where the ground
	    turns from green to tan. The limbs reaching WEST still carry a green canopy, the
	    ones pointing straight up or down the field have gone yellow, and the ones
	    reaching EAST are bare. Its dead leaves lie under the east side.
	  * THE FALLEN LOG — a mossy log lying near the creek, hollow at the ends, with
	    mushrooms growing round it.
	  * THE PICNIC — a checked blanket somebody left in a hurry: a basket with the lid
	    up, plates, a knocked-over cup, apples rolled off, and a gas mask.
	  * TWO SUNFLOWER PATCHES — one bright and upright in the west, one drooped, brown
	    and snapped in the east. The same flower at both ends of the field.
	  * THE FLOWERS — wildflower clumps across the whole field, one colour per clump,
	    wilting with the ground: fresh and upright in the west, faded and drooping in
	    the middle, dead stems and fallen petals in the east.

	The field's own bushes, grass tufts, rocks and dead snags (build/Scenery's
	scatterBushes / scatterDeadBushes / scatterStage1GroundDetail) stay exactly where
	they were; this module reads where they landed (the parent folder's own parts) and
	keeps its set pieces and flower clumps off them, rather than moving a single one.

	NOTHING GLOWS. The first Neon on the chain stays Stage 4's ooze.

	THE PARTS ARE build/BiomeKit's, and so are its standing rules: every part
	CanCollide/CanQuery/CanTouch false, so a player walks through all of it and
	FieldController's range-ring raycast and DigService's burial pass straight to the
	plate; anything that stands up keeps off the walk lane down z = 0; studs on wood,
	rock and foliage, smooth on water, petals and the picnic things.

	FLAT THINGS STAY UNDER A DETECTOR SPOT'S CRACKS (0.15 over the cap, see
	build/FieldLitter's header): the creek bank tops out 0.04, the water 0.07, the dry
	bed's cracks 0.09, the blanket 0.07.

	ITS OWN SEED, never the stage rng, so this cannot move a bush or a snag.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)

local WiltingMeadow = {}

local SEED = 8100

--- Flower clumps: one roll per CELL-stud cell. The chance falls off to the east (the
--- meadow thins out as it dies), from FLOWER_WEST at the camp edge to FLOWER_EAST at
--- the Stage 2 seam. Both x0.8 since the middle lane opened up (#377), which holds
--- the field to its old part count instead of adding clumps. x0.45 again on request
--- ("remove a lot of the flowers"), and clumps cut to 1-3 heads so they stop repeating.
--- x0.35 again in the minimal-decor pass (2026-10-03): a few clumps, not a meadow.
--- Then on request (2026-10-04, "remove... some flowers"), every KEEP_EVERYth clump
--- only: at these odds a field is a handful of clumps, and scaling the odds again
--- emptied it outright instead of thinning it.
local CELL = 14
local FLOWER_WEST = 0.42 * 0.8 * 0.45 * 0.35
local FLOWER_EAST = 0.2 * 0.8 * 0.45 * 0.35
local KEEP_EVERY = 2

--- Where along the field (0 = camp edge, 1 = Stage 2 seam) the flowers start to wilt,
--- and how far on they are fully dead.
local WILT_START = 0.3
local WILT_SPAN = 0.55

--- Where along the creek (0 = the spring, 1 = where it gives out) the water ends and
--- the mud begins, and where the mud has dried to a cracked bed.
local CREEK_WET = 0.42
local CREEK_DAMP = 0.66
--- Distance between creek samples, in studs along the path.
local CREEK_STEP = 1

-- ── Colour ─────────────────────────────────────────────────────────────────────

local hex = K.hex

-- The world's own wood and foliage (build/Scenery's DEAD_WOOD / WITHERED_WOOD /
-- BUSH_GREEN), so the tree and the log match the snags and the bushes.
local BARK = { hex("6E5A42"), hex("5F4C37") }
local BARK_DEAD = { hex("8A7C69"), hex("584E40") }
local LEAF_ALIVE = { hex("5AA83A"), hex("47872A"), hex("63B83A") }
local LEAF_TURNING = { hex("A9B04A"), hex("8E9A3C"), hex("C2A34A") }
local LEAF_FALLEN = { hex("C98A3A"), hex("A8643A"), hex("B89A4A"), hex("8A5A34") }

-- Water is dark and matte: reflectance on a flat face mirrors the sky pale (the lesson
-- Glass Barrens shot live), and a pale blue on this pale ground reads as paint.
local WATER = hex("3F7F95")
local BANK_WET = hex("5E4E36")
local MUD = hex("7A6446")
-- A step darker than the tan floor, never paler: a pale drift on the ground reads as
-- spilled paint.
local DRY_BED = hex("A88C62")
local CRACK = hex("6A563F")

local REED = hex("5E8A36")
local REED_DRY = hex("9A8458")
local CATTAIL = hex("6B4A2E")

local WOOD = { hex("7A6446"), hex("6A563C"), hex("85704F") }
local STONE = { hex("9C958A"), hex("6B655B"), hex("827C72") }
local MOSS = { hex("6E9A3A"), hex("5A8430") }
local SAPWOOD = hex("B39468")
local HOLLOW = hex("3A2E22")
local MUSHROOM_CAP = { hex("B5452F"), hex("C7854A") }
local MUSHROOM_STEM = hex("E8E0CC")

local STEM = hex("4C8A2E")
local STEM_DEAD = hex("6A5A3C")
local PETAL_DEAD = hex("7A6048")
local PETALS = { hex("E84A5F"), hex("F2C14E"), hex("9B6BD6"), hex("F2EEE4"), hex("F28AB2") }
local FLOWER_EYE = hex("E8B53A")
local FLOWER_EYE_DEAD = hex("4A3A28")

local SUN_PETAL = hex("F2C230")
local SUN_PETAL_DEAD = hex("6E5230")
local SUN_FACE = hex("5A3A1E")
local SUN_FACE_DEAD = hex("3E2E22")
local SUN_LEAF = hex("5E9E35")
local SUN_LEAF_DEAD = hex("8B7550")
-- A hung head's back faces the sky and catches the full sun, so it is dark to begin
-- with: at the stem's own colour it read pale khaki, like a paper plate.
local SUN_BACK = hex("4C7F2C")
local SUN_BACK_DEAD = hex("4A3824")

local BLANKET = hex("EDE6DA")
local BLANKET_CHECK = hex("C8423A")
local WICKER = hex("A87B45")
local WICKER_DARK = hex("7E5A30")
local PLATE = hex("F4F1EA")
local CUP = hex("3F7FBF")
local APPLE = hex("C0392B")
local MASK = hex("3B4046")
local MASK_LENS = hex("9FB8C0")
local MASK_FILTER = hex("5C6B4A")
local THERMOS = hex("2F6D5A")
local THERMOS_CAP = hex("C9CCCF")
local BONE = hex("DCD3C0")

-- ── Helpers ────────────────────────────────────────────────────────────────────

type Taken = { { number } }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- A square-section beam from `a` to `b`, `t` thick.
local function beam(parent: Instance, name: string, a: Vector3, b: Vector3, t: number, color: Color3, opts: K.PartOpts?): Part?
	local d = b - a
	local len = d.Magnitude
	if len < 0.05 then
		return nil
	end
	local mid = (a + b) / 2
	local up = if math.abs(d.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return K.block(parent, name, CFrame.lookAt(mid, b, up), Vector3.new(t, t, len), color, opts)
end

--- A frame at `at` whose local X axis points along `dir` -- what a flat Cylinder (axis
--- along X) needs to face that way.
local function facing(at: Vector3, dir: Vector3): CFrame
	local up = if math.abs(dir.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(at, at + dir, up) * CFrame.Angles(0, math.rad(90), 0)
end

--- A unit vector `pitch` degrees off straight up, toward `yaw` degrees.
local function tilted(yaw: number, pitch: number): Vector3
	local y, p = math.rad(yaw), math.rad(pitch)
	return Vector3.new(math.cos(y) * math.sin(p), math.cos(p), math.sin(y) * math.sin(p))
end

--- A flat round disc (a Cylinder on its side), `d` across and `t` thick, facing `dir`.
local function roundel(parent: Instance, name: string, at: Vector3, dir: Vector3, d: number, t: number, color: Color3): Part
	return K.block(parent, name, facing(at, dir), Vector3.new(t, d, d), color, { shape = Enum.PartType.Cylinder })
end

local function clearOf(taken: Taken, x: number, z: number, r: number): boolean
	for _, t in taken do
		local dx, dz = x - t[1], z - t[2]
		local need = r + t[3]
		if dx * dx + dz * dz < need * need then
			return false
		end
	end
	return true
end

--- Try up to 80 random points in the box for one that keeps `r` clear of everything
--- taken, and take it.
local function place(taken: Taken, r: number, rng: Random, x0: number, x1: number, z0: number, z1: number): Vector3?
	for _ = 1, 80 do
		local x, z = rng:NextNumber(x0, x1), rng:NextNumber(z0, z1)
		if clearOf(taken, x, z, r) then
			table.insert(taken, { x, z, r })
			return Vector3.new(x, 0, z)
		end
	end
	return nil
end

--- Where the field's existing scatter landed: every bush block, snag, rock and grass
--- blade already in the stage folder, with a clearance sized to what it is.
local CLEARANCE = { Bush = 3.2, DeadBush = 2, Tip = 1, Rock = 1.6, GrassBlade = 0.8 }
local function existing(parent: Instance): Taken
	local out: Taken = {}
	for _, p in parent:GetChildren() do
		local r = CLEARANCE[p.Name]
		if r and p:IsA("BasePart") then
			table.insert(out, { p.Position.X, p.Position.Z, r })
		end
	end
	return out
end

--- 0 at the camp edge, 1 at the Stage 2 seam.
local function along(x: number): number
	local minX, _, maxX = Stages.bounds(1)
	return math.clamp((x - minX) / (maxX - minX), 0, 1)
end

--- The world X `t` of the way from the camp edge to the Stage 2 seam -- every layout
--- number in this file is one of these, so the meadow follows the footprint.
local function fx(t: number): number
	local minX, _, maxX = Stages.bounds(1)
	return minX + t * (maxX - minX)
end

-- ── The creek ──────────────────────────────────────────────────────────────────

local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2, t3 = t * t, t * t * t
	return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
end

--- Evenly spaced samples (every CREEK_STEP studs) along a Catmull-Rom path through
--- `pts`, each with its tangent.
local function sampleCreek(pts: { Vector3 }): { { at: Vector3, dir: Vector3 } }
	local dense: { Vector3 } = {}
	for i = 1, #pts - 1 do
		local p0 = pts[math.max(1, i - 1)]
		local p3 = pts[math.min(#pts, i + 2)]
		for s = 0, 19 do
			table.insert(dense, catmull(p0, pts[i], pts[i + 1], p3, s / 20))
		end
	end
	table.insert(dense, pts[#pts])

	local out = {}
	local carry = 0
	for i = 1, #dense - 1 do
		local a, b = dense[i], dense[i + 1]
		local seg = (b - a).Magnitude
		local dir = if seg > 0 then (b - a).Unit else Vector3.xAxis
		while carry <= seg do
			table.insert(out, { at = a:Lerp(b, if seg > 0 then carry / seg else 0), dir = dir })
			carry += CREEK_STEP
		end
		carry -= seg
	end
	return out
end

--- The creek's control points for a centreline at `zb`: out from under the north wall
--- `sx` of the way along the field, then east along the north side with a lazy meander.
local function creekPath(zb: number, zWall: number, sx: number): { Vector3 }
	return {
		Vector3.new(fx(sx), 0, zWall + 2),
		Vector3.new(fx(sx + 0.021), 0, zWall - 6),
		Vector3.new(fx(math.max(0.159, sx + 0.06)), 0, zb + 5),
		Vector3.new(fx(0.262), 0, zb - 4),
		Vector3.new(fx(0.372), 0, zb + 5),
		Vector3.new(fx(0.483), 0, zb - 5),
		Vector3.new(fx(0.593), 0, zb + 3),
		Vector3.new(fx(0.703), 0, zb - 5),
		Vector3.new(fx(0.807), 0, zb + 2),
		Vector3.new(fx(0.883), 0, zb - 2),
	}
end

--- How wide the creek is at `p` along it: widest at the spring, a trickle at the end.
local function creekWidth(p: number): number
	return lerp(7, 2.2, p)
end

local function reeds(parent: Instance, x: number, z: number, groundY: number, rng: Random, dry: boolean)
	for _ = 1, rng:NextInteger(3, 5) do
		local h = if dry then rng:NextNumber(1.2, 2.4) else rng:NextNumber(2.4, 4)
		local yaw, lean = rng:NextNumber(0, 360), rng:NextNumber(3, if dry then 30 else 12)
		local base = Vector3.new(x + rng:NextNumber(-0.9, 0.9), groundY - 0.1, z + rng:NextNumber(-0.9, 0.9))
		local top = base + tilted(yaw, lean) * h
		beam(parent, "Reed", base, top, 0.18, if dry then REED_DRY else REED)
		if not dry and rng:NextNumber() < 0.45 then
			local d = tilted(yaw, lean)
			beam(parent, "Cattail", top - d * 1.1, top - d * 0.15, 0.36, CATTAIL)
		end
	end
end

local function footbridge(parent: Instance, at: Vector3, dir: Vector3, span: number, groundY: number, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Footbridge"
	-- Across the creek: the bridge's length runs perpendicular to the flow.
	local across = Vector3.new(-dir.Z, 0, dir.X)
	local F = CFrame.lookAt(Vector3.new(at.X, groundY, at.Z), Vector3.new(at.X, groundY, at.Z) + across)
	local len = span + 3
	for _, s in { -1, 1 } do
		K.block(folder, "Stringer", F * CFrame.new(s * 1.1, 0.35, 0), Vector3.new(0.4, 0.4, len), WOOD[2], { studs = true })
	end
	local n = math.floor(len / 0.9)
	for i = 0, n - 1 do
		local off = -len / 2 + (i + 0.5) * (len / n)
		local tilt = CFrame.Angles(0, 0, math.rad(rng:NextNumber(-3, 3)))
		K.block(folder, "Plank", F * CFrame.new(0, 0.62, off) * tilt, Vector3.new(3, 0.18, 0.78), K.pick(rng, WOOD), { studs = true })
	end
	-- One handrail, the other side's posts only (it lost its rail).
	for _, off in { -len / 2 + 0.4, len / 2 - 0.4 } do
		K.block(folder, "Post", F * CFrame.new(1.35, 1.2, off), Vector3.new(0.3, 1.9, 0.3), WOOD[2], { studs = true })
		K.block(folder, "Post", F * CFrame.new(-1.35, 0.95, off), Vector3.new(0.3, 1.4, 0.3), WOOD[2], { studs = true })
	end
	K.block(folder, "Rail", F * CFrame.new(1.35, 2.05, 0), Vector3.new(0.25, 0.25, len - 0.5), WOOD[1], { studs = true })
	folder.Parent = parent
end

local function steppingStones(parent: Instance, at: Vector3, dir: Vector3, span: number, groundY: number, rng: Random)
	local across = Vector3.new(-dir.Z, 0, dir.X)
	local n = 4
	for i = 1, n do
		local off = -span / 2 - 0.6 + (i - 0.5) * ((span + 1.2) / n)
		local p = at + across * off + dir * rng:NextNumber(-0.5, 0.5)
		local s = rng:NextNumber(1.2, 1.6)
		local cf = CFrame.new(p.X, groundY + 0.12, p.Z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		K.block(parent, "SteppingStone", cf, Vector3.new(s, 0.4, s * rng:NextNumber(0.75, 1)), K.pick(rng, STONE), { studs = true })
	end
end

--- A fish skeleton on the dry bed where the creek gave out.
local function deadFish(parent: Instance, at: Vector3, groundY: number, rng: Random)
	local F = CFrame.new(at.X, groundY + 0.1, at.Z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	K.block(parent, "FishSpine", F, Vector3.new(0.14, 0.14, 2.6), BONE)
	K.wedge(parent, "FishHead", F * CFrame.new(0, 0.1, -1.55) * CFrame.Angles(0, math.rad(180), 0), Vector3.new(0.6, 0.35, 0.7), BONE)
	K.wedge(parent, "FishTail", F * CFrame.new(0, 0.05, 1.5) * CFrame.Angles(math.rad(90), 0, 0), Vector3.new(0.1, 0.6, 0.5), BONE)
	for i = 0, 3 do
		for _, s in { -1, 1 } do
			local z = -0.8 + i * 0.5
			local len = 0.75 - math.abs(i - 1.2) * 0.12
			K.block(parent, "FishRib", F * CFrame.new(s * len / 2, 0, z) * CFrame.Angles(0, math.rad(s * 18), 0), Vector3.new(len, 0.08, 0.08), BONE)
		end
	end
end

--- The creek: a ribbon of round discs along the path, packed close (CREEK_STEP) so
--- the edge runs smooth instead of beading, water over a wet bank while
--- it still runs, mud, then a cracked dry bed. Returns the samples it laid (for the
--- taken list).
local function creek(parent: Instance, samples: { { at: Vector3, dir: Vector3 } }, groundY: number, rng: Random): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Creek"
	local bed = Instance.new("Folder")
	bed.Name = "Bed"
	bed.Parent = folder

	local n = #samples
	for i, s in samples do
		local p = (i - 1) / math.max(1, n - 1)
		local w = creekWidth(p)
		local yaw = math.deg(math.atan2(-s.dir.Z, s.dir.X))
		-- Neighbours alternate height by a hair so their overlap never z-fights.
		local lift = (i % 2) * 0.004

		if p < CREEK_WET then
			K.disc(bed, "Bank", Vector3.new(s.at.X, groundY + 0.015 + lift, s.at.Z), w + 2.6, w + 2.6, 0.03, yaw, BANK_WET)
			K.disc(bed, "Water", Vector3.new(s.at.X, groundY + 0.05 + lift, s.at.Z), w, w, 0.03, yaw, WATER)
		elseif p < CREEK_DAMP then
			-- The water pulls back into puddles along a mud channel.
			local k = (p - CREEK_WET) / (CREEK_DAMP - CREEK_WET)
			K.disc(bed, "Mud", Vector3.new(s.at.X, groundY + 0.015 + lift, s.at.Z), w + 1.8, w + 1.8, 0.03, yaw, BANK_WET:Lerp(MUD, k))
			if rng:NextNumber() < lerp(0.8, 0.15, k) * 0.4 then
				local pw = w * rng:NextNumber(0.4, 0.8) * (1 - k * 0.5)
				K.disc(bed, "Puddle", Vector3.new(s.at.X, groundY + 0.05 + lift, s.at.Z), pw, pw, 0.03, yaw, WATER)
			end
		else
			local k = (p - CREEK_DAMP) / (1 - CREEK_DAMP)
			K.disc(bed, "DryBed", Vector3.new(s.at.X, groundY + 0.015 + lift, s.at.Z), w + 1.4, w + 1.4, 0.03, yaw, MUD:Lerp(DRY_BED, math.min(1, k * 1.6)))
			if i % 5 == 0 then
				for _ = 1, rng:NextInteger(1, 3) do
					local across = Vector3.new(-s.dir.Z, 0, s.dir.X) * rng:NextNumber(-w / 2, w / 2)
					local c = s.at + across + s.dir * rng:NextNumber(-1, 1)
					local cf = CFrame.new(c.X, groundY + 0.075, c.Z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
					K.block(bed, "Crack", cf, Vector3.new(0.14, 0.02, rng:NextNumber(0.9, 2.2)), CRACK)
				end
			end
			if i % 12 == 0 then
				K.grit(folder, s.at.X + rng:NextNumber(-1, 1), s.at.Z + rng:NextNumber(-1, 1), groundY, STONE, rng, "Pebble")
			end
		end

		-- Reeds on the banks, green where there is water, dry stubble after.
		if i > 8 and rng:NextNumber() < (if p < CREEK_DAMP then 0.09 else 0.04) then
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local off = Vector3.new(-s.dir.Z, 0, s.dir.X) * side * (w / 2 + 1.4)
			reeds(folder, s.at.X + off.X, s.at.Z + off.Z, groundY, rng, p >= CREEK_WET)
		end
	end

	-- The spring: rocks at the foot of the wall where the water comes out.
	local head = samples[1].at
	K.rock(folder, head.X - 3, head.Z + 1, groundY, 3.6, STONE, rng, "SpringRock")
	K.rock(folder, head.X + 3.2, head.Z + 0.5, groundY, 2.8, STONE, rng, "SpringRock")

	local bridgeAt = samples[math.max(1, math.floor(n * 0.24))]
	footbridge(folder, bridgeAt.at, bridgeAt.dir, creekWidth(0.24) + 2.6, groundY, rng)
	local stonesAt = samples[math.floor(n * 0.54)]
	steppingStones(folder, stonesAt.at, stonesAt.dir, creekWidth(0.54) + 1.8, groundY, rng)
	local fishAt = samples[math.floor(n * 0.9)]
	deadFish(folder, fishAt.at, groundY, rng)

	folder.Parent = parent
	return folder
end


--- Moving water on the wet stretch: an invisible emitter pad every few samples with
--- sun glints winking on the surface, pale foam flecks drifting downstream, and soft
--- rings spreading flat on the water. A splash of droplets at the spring. All matte
--- whites and blues, nothing Neon, nothing lit.
local function waterFx(parent: Instance, samples: { { at: Vector3, dir: Vector3 } }, groundY: number)
	local folder = Instance.new("Folder")
	folder.Name = "WaterFx"
	local n = #samples
	local function pad(at: Vector3, dir: Vector3, w: number, len: number): Part
		local p = Instance.new("Part")
		p.Name = "WaterFxPad"
		p.Anchored = true
		p.Transparency = 1
		p.Size = Vector3.new(w, 0.05, len)
		p.CFrame = CFrame.lookAt(Vector3.new(at.X, groundY + 0.09, at.Z), Vector3.new(at.X, groundY + 0.09, at.Z) + dir)
		p.Parent = folder
		return p
	end
	local wetEnd = math.floor(n * CREEK_WET)
	for i = 4, wetEnd, 6 do
		local s = samples[i]
		local w = creekWidth((i - 1) / math.max(1, n - 1)) * 0.8
		local p = pad(s.at, s.dir, w, 6)

		local glint = Instance.new("ParticleEmitter")
		glint.Name = "Glint"
		glint.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		glint.Color = ColorSequence.new(Color3.fromRGB(235, 250, 255))
		glint.LightEmission = 0.4
		glint.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 0) })
		glint.Transparency = NumberSequence.new(0.15)
		glint.Lifetime = NumberRange.new(0.4, 0.8)
		glint.Rate = 3
		glint.Speed = NumberRange.new(0)
		glint.Rotation = NumberRange.new(0, 360)
		glint.EmissionDirection = Enum.NormalId.Top
		glint.Parent = p

		local foam = Instance.new("ParticleEmitter")
		foam.Name = "Foam"
		foam.Color = ColorSequence.new(Color3.fromRGB(225, 240, 242))
		foam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.28) })
		foam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.35), NumberSequenceKeypoint.new(1, 1) })
		foam.Lifetime = NumberRange.new(2.5, 4)
		foam.Rate = 4
		foam.Speed = NumberRange.new(1.6, 2.4)
		foam.EmissionDirection = Enum.NormalId.Back -- downstream, along the pad's look
		foam.SpreadAngle = Vector2.new(0, 0)
		foam.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		foam.Parent = p

		local ring = Instance.new("ParticleEmitter")
		ring.Name = "Ripple"
		ring.Color = ColorSequence.new(Color3.fromRGB(170, 215, 228))
		ring.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1.6) })
		ring.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		ring.Lifetime = NumberRange.new(1.4, 2)
		ring.Rate = 0.8
		ring.Speed = NumberRange.new(0.01)
		ring.EmissionDirection = Enum.NormalId.Top
		ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		ring.Parent = p
	end

	-- The spring: droplets kicking up where the water comes out from under the wall.
	local head = samples[math.min(n, 3)]
	local sp = pad(head.at, head.dir, 3, 3)
	local drop = Instance.new("ParticleEmitter")
	drop.Name = "Splash"
	drop.Color = ColorSequence.new(Color3.fromRGB(200, 232, 240))
	drop.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0.05) })
	drop.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	drop.Lifetime = NumberRange.new(0.5, 0.8)
	drop.Rate = 14
	drop.Speed = NumberRange.new(3, 5)
	drop.SpreadAngle = Vector2.new(35, 35)
	drop.Acceleration = Vector3.new(0, -workspace.Gravity * 0.1, 0)
	drop.EmissionDirection = Enum.NormalId.Top
	drop.Parent = sp

	folder.Parent = parent
end

--- The field's bushes that the creek's route runs over: clump build/Scenery's `Bush`
--- blocks into bushes (blocks within a few studs of each other), and slide any bush
--- sitting on the creek out sideways (toward the lane) from the nearest sample until it
--- clears the bank. Whole bushes move as one, so nothing comes apart.
local function clearBushesOffCreek(parent: Instance, samples: { { at: Vector3, dir: Vector3 } })
	local blocks = {}
	for _, p in parent:GetChildren() do
		if p.Name == "Bush" and p:IsA("BasePart") then
			table.insert(blocks, p)
		end
	end
	local group = {}
	for i = 1, #blocks do
		group[i] = i
	end
	local function root(i: number): number
		while group[i] ~= i do
			i = group[i]
		end
		return i
	end
	for i = 1, #blocks do
		for j = i + 1, #blocks do
			local d = blocks[i].Position - blocks[j].Position
			if Vector2.new(d.X, d.Z).Magnitude < 3.2 then
				group[root(i)] = root(j)
			end
		end
	end
	local bushes: { [number]: { BasePart } } = {}
	for i, b in blocks do
		local r = root(i)
		bushes[r] = bushes[r] or {}
		table.insert(bushes[r], b)
	end
	local n = #samples
	for _, parts in bushes do
		local c = Vector3.zero
		for _, b in parts do
			c += b.Position
		end
		c /= #parts
		for _ = 1, 20 do
			local best, bestD, bestReach = nil, math.huge, 0
			for i, s in samples do
				local reach = creekWidth((i - 1) / math.max(1, n - 1)) / 2 + 1.3 + 3.4
				local d = Vector2.new(c.X - s.at.X, c.Z - s.at.Z).Magnitude - reach
				if d < bestD then
					best, bestD, bestReach = s, d, reach
				end
			end
			if best == nil or bestD >= 0 then
				break
			end
			local across = Vector3.new(-best.dir.Z, 0, best.dir.X)
			-- Always toward the lane: the creek hugs the north wall, so the other way is a wall.
			local side = if across.Z * c.Z <= 0 then 1 else -1
			local shift = across * side * (-bestD + 0.5)
			for _, b in parts do
				b.CFrame += shift
			end
			c += shift
		end
	end
end

-- ── The half-dead tree ─────────────────────────────────────────────────────────

--- A canopy clump: chunky studded blocks round a point, like build/Scenery's `bush`
--- scaled up and hung in the air.
local function canopy(parent: Instance, at: Vector3, s: number, colors: { Color3 }, n: number, rng: Random)
	for i = 1, n do
		local k = 1 - (i - 1) * 0.12
		local size = Vector3.new(s * k * rng:NextNumber(0.85, 1.1), s * k * rng:NextNumber(0.7, 0.9), s * k * rng:NextNumber(0.85, 1.1))
		local off = if i == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-1, 1) * s * 0.45, rng:NextNumber(-0.2, 0.5) * s * 0.5, rng:NextNumber(-1, 1) * s * 0.45)
		local cf = CFrame.new(at + off) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-12, 12)))
		K.block(parent, "Canopy", cf, size, K.pick(rng, colors), { studs = true })
	end
end

local function tree(parent: Instance, at: Vector3, groundY: number, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "HalfDeadTree"

	local p0 = Vector3.new(at.X, groundY - 0.5, at.Z)
	local p1 = p0 + Vector3.new(rng:NextNumber(-0.4, 0.4), 11, rng:NextNumber(-0.4, 0.4))
	-- The crown leans a little east, toward the dead side, as if it is going over.
	local p2 = p1 + Vector3.new(rng:NextNumber(0.4, 1.1), 8, rng:NextNumber(-0.5, 0.5))
	beam(folder, "Trunk", p0, p1, 3.8, BARK[1], { studs = true })
	beam(folder, "Trunk", p1 - Vector3.new(0, 0.4, 0), p2, 2.9, BARK[2], { studs = true })

	-- Root flare.
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45 + rng:NextNumber(-20, 20))
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		beam(folder, "Root", p0 + Vector3.new(0, 2.6, 0) + out * 0.8, Vector3.new(at.X, groundY - 0.2, at.Z) + out * rng:NextNumber(3, 4), 1.4, BARK[2], { studs = true })
	end

	-- Seven limbs round the crown. Which way each one reaches decides what it carries:
	-- west (toward camp, -X) is still in leaf, across the field is turning, east is bare.
	local yaw0 = rng:NextNumber(0, 51)
	for i = 0, 6 do
		local a = math.rad(yaw0 + i * (360 / 7) + rng:NextNumber(-10, 10))
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local start = p1:Lerp(p2, rng:NextNumber(0.3, 1))
		local len = rng:NextNumber(8, 11)
		local tip = start + out * len + Vector3.new(0, len * rng:NextNumber(0.45, 0.75), 0)
		local west = out.X < -0.3
		local east = out.X > 0.3
		beam(folder, "Limb", start, tip, 1.5, if east then K.pick(rng, BARK_DEAD) else BARK[1], { studs = true })

		if east then
			-- Bare: twigs forking off the end, each with a snapped point, and one more
			-- off the middle of the limb.
			local forks = { { tip, a }, { start:Lerp(tip, 0.55), a + math.rad(if rng:NextNumber() < 0.5 then -60 else 60) } }
			for f, fork in forks do
				for _ = 1, if f == 1 then 3 else 1 do
					local ta = fork[2] + math.rad(rng:NextNumber(-50, 50))
					local from = fork[1]
					local twigTip = from + Vector3.new(math.cos(ta), 0, math.sin(ta)) * rng:NextNumber(2.6, 4.4) + Vector3.new(0, rng:NextNumber(1.6, 3.4), 0)
					beam(folder, "Twig", from, twigTip, 0.75, K.pick(rng, BARK_DEAD), { studs = true })
					K.wedge(folder, "Tip", CFrame.lookAt(twigTip, twigTip + (twigTip - from)) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, 0.5, 0), Vector3.new(0.55, 1.1, 0.55), BARK_DEAD[2], { studs = true })
				end
			end
		elseif west then
			canopy(folder, tip + Vector3.new(0, 1.2, 0), rng:NextNumber(6.5, 8), LEAF_ALIVE, 4, rng)
		else
			canopy(folder, tip + Vector3.new(0, 1, 0), rng:NextNumber(5, 6), LEAF_TURNING, 3, rng)
		end
	end
	-- The crown itself, off the top of the trunk: full on the west side, thinning east.
	canopy(folder, p2 + Vector3.new(-2.5, 2.2, 0), 8, LEAF_ALIVE, 4, rng)
	canopy(folder, p2 + Vector3.new(2, 1.6, rng:NextNumber(-1, 1)), 5, LEAF_TURNING, 2, rng)

	-- What the dead side dropped: leaves on the ground under the east limbs.
	local leaves = Instance.new("Folder")
	leaves.Name = "FallenLeaves"
	for _ = 1, 34 do
		local x = at.X + rng:NextNumber(-1, 12)
		local z = at.Z + rng:NextNumber(-9, 9)
		local cf = CFrame.new(x, groundY + rng:NextNumber(0.015, 0.07), z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		K.block(leaves, "Leaf", cf, Vector3.new(rng:NextNumber(0.6, 0.9), 0.03, rng:NextNumber(0.4, 0.6)), K.pick(rng, LEAF_FALLEN))
	end
	leaves.Parent = folder

	folder.Parent = parent
end

-- ── The fallen log ─────────────────────────────────────────────────────────────

local function mushroom(parent: Instance, base: Vector3, s: number, rng: Random)
	local tilt = CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-10, 10)))
	local F = CFrame.new(base) * tilt
	K.block(parent, "MushroomStem", F * CFrame.new(0, 0.3 * s, 0), Vector3.new(0.32, 0.7, 0.32) * s, MUSHROOM_STEM)
	local cap = K.pick(rng, MUSHROOM_CAP)
	K.block(parent, "MushroomCap", F * CFrame.new(0, 0.7 * s, 0), Vector3.new(1, 0.32, 1) * s, cap)
	K.block(parent, "MushroomCap", F * CFrame.new(0, 0.92 * s, 0), Vector3.new(0.66, 0.16, 0.66) * s, cap)
end

local function fallenLog(parent: Instance, at: Vector3, groundY: number, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "FallenLog"

	local len, th = rng:NextNumber(14, 17), rng:NextNumber(2.7, 3.2)
	local F = CFrame.new(at.X, groundY + th * 0.4, at.Z)
		* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8)))
	K.block(folder, "Log", F, Vector3.new(th, th, len), BARK[1], { studs = true })
	for _, s in { -1, 1 } do
		K.block(folder, "LogEnd", F * CFrame.new(0, 0, s * (len / 2 + 0.05)), Vector3.new(th * 0.84, th * 0.84, 0.12), SAPWOOD)
		K.block(folder, "LogHollow", F * CFrame.new(0, 0, s * (len / 2 + 0.1)), Vector3.new(th * 0.46, th * 0.46, 0.1), HOLLOW)
	end
	-- Moss along the top.
	for _ = 1, rng:NextInteger(2, 4) do
		local cf = F * CFrame.new(rng:NextNumber(-0.25, 0.25) * th, th / 2 + 0.12, rng:NextNumber(-0.4, 0.4) * len)
		K.block(folder, "Moss", cf, Vector3.new(th * rng:NextNumber(0.5, 0.8), 0.3, rng:NextNumber(1.5, 3)), K.pick(rng, MOSS), { studs = true })
	end
	-- A snapped branch stub.
	local stubBase = (F * CFrame.new(0, th / 2 - 0.2, rng:NextNumber(-0.3, 0.3) * len)).Position
	beam(folder, "Stub", stubBase, stubBase + (F.RightVector * 0.8 + Vector3.new(0, 2.2, 0)), 0.8, BARK[2], { studs = true })

	-- Mushrooms at the foot of the log, both sides, nearer the ends.
	for _ = 1, rng:NextInteger(4, 6) do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local p = (F * CFrame.new(side * (th / 2 + rng:NextNumber(0.3, 0.9)), 0, rng:NextNumber(0.2, 0.48) * len * (if rng:NextNumber() < 0.5 then -1 else 1))).Position
		mushroom(folder, Vector3.new(p.X, groundY, p.Z), rng:NextNumber(0.8, 1.3), rng)
	end

	folder.Parent = parent
end

-- ── The picnic ─────────────────────────────────────────────────────────────────

local function picnic(parent: Instance, at: Vector3, groundY: number, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Picnic"
	local F = CFrame.new(at.X, groundY, at.Z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)

	-- The blanket: a white sheet with red checks laid on it, 5 x 5.
	local SIZE, N = 7, 5
	local cell = SIZE / N
	K.block(folder, "Blanket", F * CFrame.new(0, 0.025, 0), Vector3.new(SIZE, 0.05, SIZE), BLANKET)
	for i = 0, N - 1 do
		for j = 0, N - 1 do
			if (i + j) % 2 == 0 then
				local cf = F * CFrame.new(-SIZE / 2 + (i + 0.5) * cell, 0.058, -SIZE / 2 + (j + 0.5) * cell)
				K.block(folder, "Check", cf, Vector3.new(cell, 0.02, cell), BLANKET_CHECK)
			end
		end
	end
	local top = 0.07

	-- The basket, lid up.
	local B = F * CFrame.new(2, top, -1.7) * CFrame.Angles(0, math.rad(rng:NextNumber(-20, 20)), 0)
	K.block(folder, "Basket", B * CFrame.new(0, 0.6, 0), Vector3.new(2.2, 1.2, 1.5), WICKER, { studs = true })
	K.block(folder, "BasketRim", B * CFrame.new(0, 1.25, 0), Vector3.new(2.3, 0.18, 1.6), WICKER_DARK)
	K.block(folder, "BasketLid", B * CFrame.new(0, 1.34, 0.8) * CFrame.Angles(math.rad(-55), 0, 0) * CFrame.new(0, 0, -0.4), Vector3.new(2.2, 0.14, 0.8), WICKER, { studs = true })
	local handle = {
		(B * CFrame.new(-0.95, 1.3, 0)).Position,
		(B * CFrame.new(-0.6, 2.25, 0)).Position,
		(B * CFrame.new(0.6, 2.25, 0)).Position,
		(B * CFrame.new(0.95, 1.3, 0)).Position,
	}
	for i = 1, #handle - 1 do
		beam(folder, "BasketHandle", handle[i], handle[i + 1], 0.18, WICKER_DARK)
	end

	-- Plates, a cup knocked over, apples rolled off, a thermos.
	for _, off in { Vector3.new(-1.6, 0, -1.4), Vector3.new(0.4, 0, 1.3) } do
		local p = (F * CFrame.new(off)).Position
		K.disc(folder, "Plate", Vector3.new(p.X, groundY + top + 0.04, p.Z), 1.3, 1.3, 0.08, 0, PLATE)
	end
	local cup = F * CFrame.new(-0.4, top + 0.25, -0.2) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	K.block(folder, "Cup", cup, Vector3.new(0.8, 0.5, 0.5), CUP, { shape = Enum.PartType.Cylinder })
	K.block(folder, "Apple", F * CFrame.new(1.2, top + 0.27, 0.2), Vector3.one * 0.55, APPLE, { shape = Enum.PartType.Ball })
	K.block(folder, "Apple", F * CFrame.new(4.3, 0.27, 2.1), Vector3.one * 0.55, APPLE, { shape = Enum.PartType.Ball })
	K.column(folder, "Thermos", F * CFrame.new(2.6, top + 0.6, 1.2), 1.2, 0.5, THERMOS)
	K.column(folder, "ThermosCap", F * CFrame.new(2.6, top + 1.3, 1.2), 0.2, 0.56, THERMOS_CAP)

	-- The gas mask, dropped face-up on the corner of the blanket.
	local M = F * CFrame.new(-1.8, top, 1.9) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
	K.block(folder, "GasMask", M * CFrame.new(0, 0.22, 0), Vector3.new(1.3, 0.44, 1.5), MASK)
	for _, s in { -1, 1 } do
		roundel(folder, "GasMaskLens", (M * CFrame.new(s * 0.33, 0.46, -0.25)).Position, Vector3.yAxis, 0.5, 0.06, MASK_LENS)
	end
	K.block(folder, "GasMaskFilter", M * CFrame.new(0, 0.3, 0.95) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(0.7, 0.55, 0.55), MASK_FILTER, { shape = Enum.PartType.Cylinder })

	folder.Parent = parent
end

-- ── Sunflowers ─────────────────────────────────────────────────────────────────

--- One sunflower, `w` 0 (fresh, facing `faceYaw`) to 1 (dead, head hung).
local function sunflower(parent: Instance, base: Vector3, faceYaw: number, w: number, groundY: number, rng: Random)
	local h = rng:NextNumber(5.5, 8.5) * lerp(1, 0.85, w)
	local snapped = w > 0.6 and rng:NextNumber() < 0.25
	if snapped then
		h *= 0.5
	end
	local stemDir = tilted(rng:NextNumber(0, 360), lerp(rng:NextNumber(0, 4), rng:NextNumber(6, 16), w))
	local foot = Vector3.new(base.X, groundY - 0.3, base.Z)
	local top = foot + stemDir * h
	local stemColor = STEM:Lerp(STEM_DEAD, w)
	beam(parent, "SunflowerStem", foot, top, 0.45, stemColor, { studs = true })

	-- Two leaves off the stem, drooping as it dies.
	for i = 1, 2 do
		local at = foot:Lerp(top, if i == 1 then 0.35 else 0.6)
		local ya = rng:NextNumber(0, 360)
		local cf = CFrame.new(at) * CFrame.Angles(0, math.rad(ya), 0) * CFrame.Angles(0, 0, math.rad(lerp(-15, -55, w))) * CFrame.new(0.9, 0, 0)
		K.block(parent, "SunflowerLeaf", cf, Vector3.new(1.8, 0.12, 0.9), SUN_LEAF:Lerp(SUN_LEAF_DEAD, w))
	end

	local petal = SUN_PETAL:Lerp(SUN_PETAL_DEAD, w)
	local face = SUN_FACE:Lerp(SUN_FACE_DEAD, w)
	if snapped then
		-- The head came off and lies face-down by the stalk.
		K.wedge(parent, "Snap", CFrame.lookAt(top, top + stemDir) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, 0.3, 0), Vector3.new(0.45, 0.6, 0.45), stemColor)
		local d = rng:NextNumber(1.8, 2.8)
		local ya = math.rad(rng:NextNumber(0, 360))
		local c = Vector3.new(base.X + math.cos(ya) * d, groundY + 0.2, base.Z + math.sin(ya) * d)
		local dir = tilted(rng:NextNumber(0, 360), rng:NextNumber(150, 175))
		roundel(parent, "SunflowerPetals", c, dir, 2.4, 0.16, petal)
		roundel(parent, "SunflowerFace", c - dir * 0.05, dir, 1.7, 0.3, face)
		return
	end

	-- Fresh heads face the sun, a bit up; dead ones hang facing the ground, which
	-- turns their BACK to anyone looking -- the green-brown cup behind the petals is
	-- what a drooped head reads as from across the field.
	local dir = tilted(faceYaw + rng:NextNumber(-15, 15), lerp(rng:NextNumber(50, 70), rng:NextNumber(125, 160), w))
	local c = top + dir * 0.3
	if dir.Y < 0 then
		-- A hung head bends over on its neck and hangs off to the side; centred on the
		-- stalk, the stalk's tip poked up through the middle of it.
		local flat = Vector3.new(dir.X, 0, dir.Z)
		local side = if flat.Magnitude > 0.05 then flat.Unit else Vector3.xAxis
		local bend = top + side * 0.7 + Vector3.new(0, 0.5, 0)
		c = bend + side * 0.6 + Vector3.new(0, -0.5, 0) + dir * 0.25
		beam(parent, "SunflowerNeck", top, bend, 0.4, stemColor)
		beam(parent, "SunflowerNeck", bend, c - dir * 0.2, 0.36, stemColor)
	end
	roundel(parent, "SunflowerPetals", c, dir, lerp(3.2, 2.3, w), 0.18, petal)
	roundel(parent, "SunflowerFace", c + dir * 0.08, dir, lerp(1.9, 1.6, w), 0.3, face)
	roundel(parent, "SunflowerBack", c - dir * 0.14, dir, lerp(1.9, 2, w), 0.26, SUN_BACK:Lerp(SUN_BACK_DEAD, w))
	-- A dead head has shed most of its petals underneath it.
	if w > 0.7 then
		for _ = 1, rng:NextInteger(2, 4) do
			local cf = CFrame.new(base.X + rng:NextNumber(-1.8, 1.8), groundY + rng:NextNumber(0.02, 0.07), base.Z + rng:NextNumber(-1.8, 1.8))
				* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
			K.block(parent, "FallenPetal", cf, Vector3.new(0.9, 0.03, 0.35), petal)
		end
	end
end

local function sunflowerPatch(parent: Instance, name: string, at: Vector3, n: number, w0: number, w1: number, groundY: number, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = name
	-- Sunflowers all face the same way (east, toward the morning), give or take.
	local faceYaw = rng:NextNumber(-30, 30)
	local spots: { Vector3 } = {}
	for _ = 1, n do
		for _ = 1, 30 do
			local a, d = rng:NextNumber(0, math.pi * 2), math.sqrt(rng:NextNumber()) * 6
			local p = Vector3.new(at.X + math.cos(a) * d, 0, at.Z + math.sin(a) * d)
			local ok = true
			for _, q in spots do
				if (p - q).Magnitude < 1.9 then
					ok = false
					break
				end
			end
			if ok then
				table.insert(spots, p)
				sunflower(folder, p, faceYaw, rng:NextNumber(w0, w1), groundY, rng)
				break
			end
		end
	end
	folder.Parent = parent
end

-- ── Wildflowers ────────────────────────────────────────────────────────────────

local function flower(parent: Instance, x: number, z: number, petal: Color3, w: number, groundY: number, rng: Random)
	local h = rng:NextNumber(1.4, 2.2) * (1 - 0.3 * w)
	local yaw = rng:NextNumber(0, 360)
	local foot = Vector3.new(x, groundY - 0.1, z)
	local top = foot + tilted(yaw, rng:NextNumber(3, 12) + 38 * w) * h
	beam(parent, "Stem", foot, top, 0.2, STEM:Lerp(STEM_DEAD, w))

	local dead = PETAL_DEAD
	if w > 0.9 and rng:NextNumber() < 0.5 then
		-- Head gone: a couple of petals on the ground by the stalk.
		for _ = 1, 2 do
			local cf = CFrame.new(x + rng:NextNumber(-0.9, 0.9), groundY + rng:NextNumber(0.02, 0.07), z + rng:NextNumber(-0.9, 0.9))
				* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
			K.block(parent, "Petal", cf, Vector3.new(0.45, 0.03, 0.3), petal:Lerp(dead, 0.7))
		end
		return
	end
	local dir = tilted(rng:NextNumber(0, 360), lerp(rng:NextNumber(10, 35), rng:NextNumber(110, 160), w))
	local c = top + dir * 0.1
	roundel(parent, "Petals", c, dir, lerp(1.15, 0.8, w), 0.14, petal:Lerp(dead, w * 0.85))
	roundel(parent, "Eye", c + dir * 0.06, dir, 0.4, 0.2, FLOWER_EYE:Lerp(FLOWER_EYE_DEAD, w))
end

local function wildflowers(parent: Instance, f: K.Field, taken: Taken, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Wildflowers"
	local clumps = 0
	K.grid(f, CELL, rng, function(x, z)
		local t = along(x)
		local roll = rng:NextNumber()
		if not clearOf(taken, x, z, 1.6) then
			return
		end
		if roll >= lerp(FLOWER_WEST, FLOWER_EAST, t) then
			return
		end
		local petal = K.pick(rng, PETALS)
		local w = math.clamp((t - WILT_START) / WILT_SPAN + rng:NextNumber(-0.15, 0.15), 0, 1)
		local n = math.max(1, rng:NextInteger(1, 3) - math.floor(w))
		clumps += 1
		if (clumps - 1) % KEEP_EVERY ~= 0 then
			return
		end
		for _ = 1, n do
			local a, d = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, 1.6)
			flower(folder, x + math.cos(a) * d, z + math.sin(a) * d, petal, math.clamp(w + rng:NextNumber(-0.08, 0.08), 0, 1), f.groundY, rng)
		end
	end)
	folder.Parent = parent
end

-- ── Build ──────────────────────────────────────────────────────────────────────

function WiltingMeadow.build(parent: Instance, stageId: number, groundY: number)
	local rng = Random.new(SEED)
	local f = K.field(stageId, groundY)
	local taken = existing(parent)

	local folder = Instance.new("Folder")
	folder.Name = "Meadow"

	-- THE CREEK first: it is the one piece with a fixed route, so everything else fits
	-- round it. Its spring and its depth along the north side are picked from a few
	-- candidates, whichever runs over the fewest of the field's own bushes -- a bush
	-- standing in the water was the first thing the live shots caught.
	local best: { Vector3 }? = nil
	local bestHits = math.huge
	for _, sx in { 0.076, 0.1, 0.125 } do
		-- Depths off the field's own north edge (was a flat 46-58 against a maxZ of 70;
		-- the 124-wide map-shrink pass put that meander inside the wall).
		for _, back in { 24, 20, 16, 12 } do
			local zb = f.maxZ - back
			local path = creekPath(zb, f.maxZ, sx)
			local hits = 0
			local list = sampleCreek(path)
			for i, s in list do
				local reach = creekWidth((i - 1) / math.max(1, #list - 1)) / 2 + 1.5
				for _, t in taken do
					local dx, dz = s.at.X - t[1], s.at.Z - t[2]
					if dx * dx + dz * dz < (reach + t[3]) ^ 2 then
						hits += 1
					end
				end
			end
			if hits < bestHits then
				best, bestHits = path, hits
			end
		end
	end
	local samples = sampleCreek(best :: { Vector3 })
	creek(folder, samples, groundY, rng)
	waterFx(folder, samples, groundY)
	-- A bush the route still runs over is moved off it, and the taken list re-read so
	-- nothing else lands where it went.
	clearBushesOffCreek(parent, samples)
	taken = existing(parent)
	for i, s in samples do
		table.insert(taken, { s.at.X, s.at.Z, creekWidth((i - 1) / math.max(1, #samples - 1)) / 2 + 1.5 })
	end

	-- The landmarks, most particular about their spot first. South of the lane: the
	-- picnic near camp, the tree at the middle where the green gives out, the dead
	-- sunflowers near the far seam. North of it, between the lane and the creek: the
	-- live sunflowers near camp and the log by the drying stretch.
	local lane = K.LANE_HALF + 6
	local treeAt = place(taken, 8, rng, fx(0.44), fx(0.56), f.minZ + 10, -lane - 4)
	if treeAt then
		tree(folder, treeAt, groundY, rng)
	end
	local deadAt = place(taken, 7, rng, fx(0.69), fx(0.92), f.minZ + 6, -lane)
	if deadAt then
		sunflowerPatch(folder, "DeadSunflowers", deadAt, 3, 0.75, 1, groundY, rng) -- 5 -> 3, minimal-decor pass
	end
	local picnicAt = place(taken, 6, rng, fx(0.076), fx(0.31), f.minZ + 6, -lane)
	if picnicAt then
		picnic(folder, picnicAt, groundY, rng)
	end
	local logAt = place(taken, 8.5, rng, fx(0.33), fx(0.59), lane, f.maxZ - 6)
	if logAt then
		fallenLog(folder, logAt, groundY, rng)
	end
	local liveAt = place(taken, 7, rng, fx(0.07), fx(0.33), lane, f.maxZ - 6)
	if liveAt then
		sunflowerPatch(folder, "Sunflowers", liveAt, 2, 0, 0.12, groundY, rng) -- 4 -> 2, minimal-decor pass
	end

	-- THE FLOWERS last, into whatever ground the rest left -- off their OWN seed, so
	-- trimming a bush or snag (which shifts this rng through `place`) cannot empty or
	-- refill the meadow by accident; their count is tuned by FLOWER_*/KEEP_EVERY only.
	wildflowers(folder, f, taken, Random.new(SEED + 1))

	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end

	folder.Parent = parent
end

return WiltingMeadow
