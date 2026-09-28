--!strict
--[[
	OozeMarsh.luau — Stage 4 as a dead marsh: green ooze standing in curved pools on dead
	mud, the wood that died in it, and the cordons somebody put up and gave up on.

	    called from build/Scenery's buildStageScenery (Stage 4, the whole pass)

	WHAT IS OUT HERE:

	  * THE POOLS — thirteen, dealt off a size ladder (one landmark lake, a few broad, some
	    mid, the rest small spills) and spaced EVENLY by best-candidate sampling, so no
	    corner of the field is bald and no two pools crowd.
	  * THE WOOD — four big withered trees (build/Scenery's `deadTree`, handed in, so they
	    are the same wood as Stage 2's stand), two of them standing at a pool's edge; then
	    broken-off snags, stumps, fallen logs (some lying into the ooze) and loose branches.
	  * THE CAUTION — build/Scenery's caution signs scattered over the field at every lean,
	    one knocked flat, and broken tape cordons round the lake and one broad pool with a
	    trefoil placard on each.

	THE POOL SHAPE, which is what this rework was for. A pool used to be one oval with a
	couple of small lobes at its tips: every puddle on the field was an egg. Now it is a
	chain of overlapping ovals laid along a SPINE that bends as it goes, each oval as wide
	as a width profile says at that point along it — so a pool swells and pinches, and
	the inside of the bend is concave. The big ones grow a side arm, and a spill leaves a
	satellite puddle or two and a few droplets past its end.

	THE POOL BRIEF STILL HOLDS, and it was arrived at over several rounds with the user:
	ONE flat green (`ooze.bright`, Neon), NO rim or dark outline, NO interior shading —
	the shape is the outline alone. One PointLight per pool (shadowless, on its widest
	oval) and one bubble carrier. Every oval in a pool steps up POOL_LIFT over the last,
	so overlapping discs never tie for the renderer.

	STANDING THINGS KEEP OFF THE WALK LANE down z = 0 (build/BiomeKit's LANE_HALF); the
	pools do not, because a flat layer you walk over does not block a route.

	EVERY PART IS CanCollide/CanQuery/CanTouch false: this is dug ground, so a player walks
	through all of it and the range-ring raycast and the burial pass reach the plate.

	ITS OWN SEED, never the stage rng.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local K = require(script.Parent.BiomeKit)
local Kit = require(script.Parent.Kit)

local OozeMarsh = {}

local SEED = 8500

--- What build/Scenery hands in, so the trees and signs out here are the same ones the
--- rest of the world uses. `tree` stands one of its withered trees on world (x, z);
--- `sign` stands a caution sign on `base` (foot at local y = 0, badge facing local -X).
export type Deps = {
	tree: (parent: Instance, x: number, z: number, rng: Random) -> (),
	sign: (parent: Instance, base: CFrame) -> (),
	trefoil: (parent: Instance, hub: CFrame, scale: number, color: string) -> (),
	wood: string,
	woodDark: string,
}

-- ── Pools ──────────────────────────────────────────────────────────────────────

--- The size ladder, biggest first (they are placed in this order, so the lake gets the
--- pick of the field and the spills fill the gaps). `length`/`width` are nominal
--- extents in studs; `arm` is the chance a pool grows a side arm.
---
--- THE LAKE IS SMALLER THAN IT WAS (the old one ran 52-66 long and swallowed the
--- centre-right of the field). A landmark you walk round, not the field itself.
local POOL_LADDER: { { n: number, length: { number }, width: { number }, arm: number } } = {
	{ n = 1, length = { 54, 62 }, width = { 21, 25 }, arm = 1 },
	{ n = 3, length = { 28, 36 }, width = { 12, 15 }, arm = 0.67 },
	{ n = 4, length = { 15, 21 }, width = { 7, 10 }, arm = 0.25 },
	{ n = 5, length = { 7, 11 }, width = { 3.8, 5.5 }, arm = 0 },
}

--- The lake is held to the middle of the walk: a landmark tucked against a wall is not
--- one. Offsets from the field's centre X.
local LAKE_X = { -60, 70 }

--- Candidates tried per pool. Each is scored by its clearance to every pool already
--- down (and to the walls, at half weight) and the best one wins.
local POOL_CANDIDATES = 36

--- Top of the liquid over `groundY` (the checkerboard cap): build/Scenery's old
--- POOL_TOP of 0.15 over the plate, less the cap's own 0.06. Under the border strip.
local POOL_TOP = 0.09
local POOL_THICK = 0.12
local POOL_LIFT = 0.002

--- THE OOZE IS THE ONE THING ON A DIG FIELD THAT IS STILL NEON, ON REQUEST (Kit.C's
--- header has the de-neon rule it is the named exception to). Neon renders unshaded,
--- so the liquid reads lit from inside; the PointLight is what lights the mud round it.
local POOL_MATERIAL: K.PartOpts = { neon = true }

-- ── Wood ───────────────────────────────────────────────────────────────────────

local TREES = 4
local SNAGS = 6
local STUMPS = 7
local LOGS = 5
local BRANCHES = 12

--- Studs between big trees. On a field carrying four, a pair that reads as one clump
--- costs a quarter of everything standing.
local TREE_GAP = 45
--- Nothing big stands this close to the entrance edge: that strip is where the signs
--- are read against open ground walking in from Stage 3.
local ENTRANCE_KEEP = 28

-- ── Cordons ────────────────────────────────────────────────────────────────────

local POST_H = 5
local POST_W = 0.36
local POST_SPACING = 6.5
local WIRE_HEIGHTS = { 1.5, 4.3 }
local TAPE_H = 3.1
local TAPE_SAG = 0.4
local TAPE_W = 0.34

-- ── Colour ─────────────────────────────────────────────────────────────────────

local C = Kit.C
-- WasteDump's weathered warm grey, matte (a cool grey reads blue off the sky).
local POST = K.hex("7F7B74")
local POST_CAP = K.hex("5E5A54")
local WIRE = K.hex("4E4A44")
local TAPE_YELLOW = K.hex(C.barrelYellow)
local TAPE_BLACK = K.hex(C.hazardBlack)

type Palette = {
	ooze: Color3,
	oozeHex: string,
	glowHex: string,
	wood: Color3,
	woodDark: Color3,
	cut: Color3,
	soil: Color3,
}

-- ── Helpers ────────────────────────────────────────────────────────────────────

local STUDS: K.PartOpts = { studs = true }
local NO_SHADOW: K.PartOpts = { shadow = false }

--- A square bar between two points.
local function strut(parent: Instance, name: string, a: Vector3, b: Vector3, t: number, color: Color3, opts: K.PartOpts?): Part?
	local d = (b - a).Magnitude
	if d < 0.05 then
		return nil
	end
	local up = if math.abs((b - a).Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return K.block(parent, name, CFrame.lookAt((a + b) / 2, b, up), Vector3.new(t, t, d), color, opts)
end

local function woodOf(rng: Random, p: Palette, darkShare: number?): Color3
	return if rng:NextNumber() < (darkShare or 0.4) then p.woodDark else p.wood
end

--- A jagged break on the face whose centre is `face`, with `face`'s local +Y pointing
--- OUT of the wood: two wedges back to back at different heights, so the top reads as
--- splintered rather than as a neat chisel point.
local function jagged(parent: Instance, face: CFrame, w: number, rng: Random, p: Palette)
	local hA = w * rng:NextNumber(0.45, 0.9)
	local hB = w * rng:NextNumber(0.15, 0.4)
	for i, yaw in { 0, 180 } do
		local h = if i == 1 then hA else hB
		K.wedge(
			parent,
			"Splinter",
			face * CFrame.Angles(0, math.rad(yaw + rng:NextNumber(-8, 8)), 0) * CFrame.new(0, h / 2, -w / 4),
			Vector3.new(w * rng:NextNumber(0.8, 0.95), h, w / 2),
			if i == 1 then p.wood else p.woodDark,
			STUDS
		)
	end
end

-- ── Pool shape ─────────────────────────────────────────────────────────────────

--- One oval of a pool, in the pool's own XZ (offsets from its centre). `yaw` is
--- K.disc's: degrees about Y, with the oval's `a` along the turned local X.
type Oval = { x: number, z: number, a: number, b: number, yaw: number, t: number? }

type Pool = {
	x: number,
	z: number,
	reach: number,
	ovals: { Oval },
	spine: { Oval },
	heading: number, -- math degrees, direction (cos, sin) in XZ
	span: number,
	width: number,
}

--- K.disc's yaw for an oval whose long axis runs along math heading `h` (degrees):
--- CFrame.Angles(0, t, 0) sends local X to (cos t, 0, -sin t), hence the minus.
local function yawFor(h: number): number
	return -h
end

local function dirOf(h: number): (number, number)
	return math.cos(math.rad(h)), math.sin(math.rad(h))
end

--- Shapes one pool at the origin: a bending spine of overlapping ovals, a side arm on
--- the bigger ones, a toe or two, satellites and droplets.
---
--- THE SPINE IS THE SHAPE. Nodes step ~0.3 of the pool's width apart and each oval runs
--- about two and a half times that along the spine, so neighbours overlap well past each
--- other's centres and the waist between two barely dips -- one smooth edge, not a string
--- of beads. (First shot at 0.42 apart read lumpy, like a cloud.) The heading turns a little at every node (24-70 degrees
--- over the whole pool), and the turn is what gives the inside of the bend a real
--- concave curve: the one thing the old single-oval pools could not do.
---
--- THE WIDTH PROFILE is a sine hump (narrow ends, full middle) with a slow wobble laid
--- over it, so a pool swells and pinches along its length instead of being a sausage.
local function shapePool(length: number, width: number, armChance: number, rng: Random): Pool
	local span = length * 0.7
	local n = math.clamp(math.round(span / (width * 0.3)) + 1, 3, 14)
	local step = span / (n - 1)
	local bend = rng:NextNumber(24, 70) * (if rng:NextNumber() < 0.5 then -1 else 1)
	local turn = bend / (n - 1)
	local phase = rng:NextNumber(0, 1)
	local waves = rng:NextNumber(0.8, 1.5)
	local function widthAt(t: number): number
		local body = 0.52 + 0.48 * math.sin(math.pi * t) ^ 0.65
		local wobble = 1 + 0.12 * math.sin((t * waves + phase) * math.pi * 2)
		return width * body * wobble
	end

	-- Walk the spine.
	local h = rng:NextNumber(0, 360)
	local startH = h
	local pts: { { x: number, z: number } } = {}
	local px, pz = 0, 0
	for i = 1, n do
		pts[i] = { x = px, z = pz }
		if i < n then
			h += turn + rng:NextNumber(-6, 6)
			local dx, dz = dirOf(h)
			px += dx * step
			pz += dz * step
		end
	end
	-- Recentre on the spine's middle, so (x, z) of the placed pool is its visual centre.
	local mx, mz = 0, 0
	for _, p in pts do
		mx += p.x
		mz += p.z
	end
	mx /= n
	mz /= n

	local spine: { Oval } = {}
	for i = 1, n do
		local prev, nxt = pts[math.max(1, i - 1)], pts[math.min(n, i + 1)]
		local th = math.deg(math.atan2(nxt.z - prev.z, nxt.x - prev.x))
		local t = (i - 1) / (n - 1)
		local w = widthAt(t)
		table.insert(spine, {
			x = pts[i].x - mx,
			z = pts[i].z - mz,
			a = math.max(step * 2.6, w * 0.7),
			b = w,
			yaw = yawFor(th),
			t = t,
		})
	end

	local ovals: { Oval } = table.clone(spine)

	--- The spine tangent at node `i`, as a math heading.
	local function tangentAt(i: number): number
		return -spine[i].yaw
	end

	-- The side arm: a shorter, narrower spine forking off near the middle, tapering out.
	if rng:NextNumber() < armChance and n >= 4 then
		local k = rng:NextInteger(math.max(2, math.floor(n * 0.3)), math.min(n - 1, math.ceil(n * 0.7)))
		local base = spine[k]
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local ah = tangentAt(k) + side * rng:NextNumber(50, 80)
		local alen = span * rng:NextNumber(0.3, 0.45)
		local aw = base.b * rng:NextNumber(0.5, 0.62)
		local an = math.clamp(math.round(alen / (aw * 0.3)) + 1, 3, 8)
		local astep = alen / (an - 1)
		local ax, az = base.x, base.z
		local armTurn = rng:NextNumber(-14, 14)
		for j = 2, an do
			ah += armTurn / (an - 1)
			local dx, dz = dirOf(ah)
			ax += dx * astep
			az += dz * astep
			local w = aw * (1 - 0.45 * (j - 1) / (an - 1))
			table.insert(ovals, { x = ax, z = az, a = math.max(astep * 2.6, w * 0.7), b = w, yaw = yawFor(ah) })
		end
	end

	-- A toe: one small swallowed oval pushed out past one side of a node, so a long edge
	-- is not perfectly smooth either. At most one, on the bigger pools, and mostly inside
	-- -- "more curve than bumps" was an explicit ask on the old pools and it still stands.
	for _ = 1, if width > 8 then rng:NextInteger(0, 1) else 0 do
		local i = rng:NextInteger(2, math.max(2, n - 1))
		local node = spine[i]
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local oh = tangentAt(i) + side * 90 + rng:NextNumber(-25, 25)
		local dx, dz = dirOf(oh)
		local s = node.b * rng:NextNumber(0.28, 0.4)
		local reach = node.b / 2 - s * rng:NextNumber(0.35, 0.6)
		table.insert(ovals, { x = node.x + dx * reach, z = node.z + dz * reach, a = s * 1.35, b = s, yaw = yawFor(oh) })
	end

	-- A satellite: a small separate puddle past one end, where the spill ran on. Set well
	-- clear -- one stuck to the edge reads as another lump on the outline.
	if width >= 6 and rng:NextNumber() < 0.65 then
		for _ = 1, 1 do
			local atEnd = if rng:NextNumber() < 0.5 then 1 else n
			local node = spine[atEnd]
			local out = tangentAt(atEnd) + (if atEnd == 1 then 180 else 0) + rng:NextNumber(-45, 45)
			local dx, dz = dirOf(out)
			local s = width * rng:NextNumber(0.18, 0.3)
			local gap = node.a / 2 + s / 2 + rng:NextNumber(3, 6)
			local sx, sz = node.x + dx * gap, node.z + dz * gap
			table.insert(ovals, { x = sx, z = sz, a = s * rng:NextNumber(1.3, 1.9), b = s, yaw = yawFor(out) })
			local ex, ez = dirOf(out + rng:NextNumber(-40, 40))
			table.insert(ovals, { x = sx + ex * s * 0.45, z = sz + ez * s * 0.45, a = s * 0.8, b = s * 0.55, yaw = yawFor(out + 30) })
		end
	end

	-- Droplets, thrown just clear of the edge.
	for _ = 1, rng:NextInteger(1, if width > 8 then 4 else 2) do
		local i = rng:NextInteger(1, n)
		local node = spine[i]
		local oh = rng:NextNumber(0, 360)
		local dx, dz = dirOf(oh)
		local reach = math.max(node.a, node.b) / 2 + rng:NextNumber(1.5, 4)
		local d = math.clamp(width * rng:NextNumber(0.05, 0.1), 0.5, 1.6)
		table.insert(ovals, { x = node.x + dx * reach, z = node.z + dz * reach, a = d * rng:NextNumber(1, 1.5), b = d, yaw = rng:NextNumber(0, 360) })
	end

	local reach = 0
	for _, o in ovals do
		reach = math.max(reach, math.sqrt(o.x * o.x + o.z * o.z) + math.max(o.a, o.b) / 2)
	end

	return {
		x = 0,
		z = 0,
		reach = reach,
		ovals = ovals,
		spine = spine,
		heading = startH + bend / 2,
		span = span,
		width = width,
	}
end

--- Is world (x, z) inside any oval of `pool`, grown by `pad`?
local function inPool(pool: Pool, x: number, z: number, pad: number): boolean
	local lx, lz = x - pool.x, z - pool.z
	if lx * lx + lz * lz > (pool.reach + pad) ^ 2 then
		return false
	end
	for _, o in pool.ovals do
		local dx, dz = lx - o.x, lz - o.z
		local t = math.rad(-o.yaw)
		local c, s = math.cos(t), math.sin(t)
		local u, v = dx * c + dz * s, -dx * s + dz * c
		local ra, rb = o.a / 2 + pad, o.b / 2 + pad
		if (u / ra) ^ 2 + (v / rb) ^ 2 <= 1 then
			return true
		end
	end
	return false
end

--- Builds a shaped pool at its placed (x, z): every oval in the one green, stepping up
--- POOL_LIFT each, a light on the widest spine oval and bubbles along the body.
local function buildPool(parent: Instance, pool: Pool, groundY: number, p: Palette, f: K.Field)
	local model = Instance.new("Model")
	model.Name = "OozePool"
	local lift = 0
	local widest: Part? = nil
	local widestB = 0
	for i, o in pool.ovals do
		lift += POOL_LIFT
		-- Droplets and satellites are held on the plate (a pool near a wall throws them).
		local x, z = K.clamp(f, pool.x + o.x, pool.z + o.z, -4)
		local part = K.disc(
			model,
			if i <= #pool.spine then "Ooze" else "OozeDrop",
			Vector3.new(x, groundY + POOL_TOP - POOL_THICK / 2 + lift, z),
			o.a,
			o.b,
			POOL_THICK,
			o.yaw,
			p.ooze,
			POOL_MATERIAL
		)
		if i <= #pool.spine and o.b > widestB then
			widest, widestB = part, o.b
		end
	end
	if widest then
		-- Scaled off the pool, clamped both ends: a spill and the lake cannot share one
		-- light without one of them looking wrong. Shadows off (one per pool, 13 lit).
		local size = (pool.span + pool.width) / 2
		Kit.light(widest, p.glowHex, math.clamp(size * 1.25, 10, 42), math.clamp(size * 0.065, 0.7, 2.2), false)
		Kit.liquidFx(
			model,
			CFrame.new(pool.x, groundY + POOL_TOP + lift, pool.z) * CFrame.Angles(0, math.rad(yawFor(pool.heading)), 0),
			pool.span * 0.8,
			pool.width * 0.5,
			p.oozeHex
		)
	end
	model.Parent = parent
end

--- Deals the ladder over the field. Best-candidate: each pool tries POOL_CANDIDATES
--- spots and keeps the one with the most clearance to every pool already down, the walls
--- counting at half weight so the field fills to its edges without pools hugging them.
local function dealPools(f: K.Field, rng: Random): { Pool }
	local pools: { Pool } = {}
	for tier, rung in POOL_LADDER do
		for _ = 1, rung.n do
			local pool = shapePool(
				rng:NextNumber(rung.length[1], rung.length[2]),
				rng:NextNumber(rung.width[1], rung.width[2]),
				rung.arm,
				rng
			)
			local inset = pool.reach * 0.8
			local x0, x1 = f.minX + inset, f.maxX - inset
			if tier == 1 then
				x0, x1 = f.cx + LAKE_X[1], f.cx + LAKE_X[2]
			end
			local bestX, bestZ, bestScore = (x0 + x1) / 2, 0, -math.huge
			for _ = 1, POOL_CANDIDATES do
				local x = rng:NextNumber(x0, x1)
				local z = rng:NextNumber(f.minZ + inset, f.maxZ - inset)
				local score = math.huge
				for _, other in pools do
					local d = math.sqrt((x - other.x) ^ 2 + (z - other.z) ^ 2) - other.reach - pool.reach
					score = math.min(score, d)
				end
				local wall = math.min(x - f.minX, f.maxX - x, z - f.minZ, f.maxZ - z) - pool.reach
				score = math.min(score, wall * 2 + 6)
				if score > bestScore then
					bestX, bestZ, bestScore = x, z, score
				end
			end
			pool.x, pool.z = bestX, bestZ
			table.insert(pools, pool)
		end
	end
	return pools
end

-- ── Wood ───────────────────────────────────────────────────────────────────────

--- A broken-off trunk: two studded sections, the upper thinner and turned off the
--- lower, a splintered top, and a stub limb or two. Leans a few degrees and is sunk by
--- what the lean lifts, so the foot never shows daylight.
local function snag(parent: Instance, x: number, z: number, groundY: number, rng: Random, p: Palette)
	local model = Instance.new("Model")
	model.Name = "Snag"
	local h = rng:NextNumber(6, 12)
	local t = rng:NextNumber(1.7, 2.7)
	local tilt = rng:NextNumber(1, 9)
	local sink = t * 0.72 * math.sin(math.rad(tilt)) + 0.1
	local base = CFrame.new(x, groundY - sink, z)
		* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		* CFrame.Angles(math.rad(tilt), 0, 0)
	local h1 = h * rng:NextNumber(0.5, 0.62)
	K.block(model, "Trunk", base * CFrame.new(0, h1 / 2, 0), Vector3.new(t, h1, t), woodOf(rng, p), STUDS)
	local t2 = t * rng:NextNumber(0.72, 0.84)
	local upper = base * CFrame.new(0, h1, 0) * CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), math.rad(rng:NextNumber(-20, 20)), math.rad(rng:NextNumber(-4, 4)))
	local h2 = h - h1
	K.block(model, "Trunk", upper * CFrame.new(0, h2 / 2, 0), Vector3.new(t2, h2, t2), woodOf(rng, p), STUDS)
	jagged(model, upper * CFrame.new(0, h2, 0), t2, rng, p)
	-- A root flare, so the foot spreads into the mud instead of standing on it like a post.
	for i = 1, rng:NextInteger(2, 3) do
		local len = t * rng:NextNumber(0.5, 0.8)
		K.wedge(
			model,
			"Root",
			base * CFrame.Angles(0, math.rad(i * 120 + rng:NextNumber(-25, 25)), 0) * CFrame.new(0, len * 0.35, -(t / 2 + len / 2) + 0.1),
			Vector3.new(t * 0.45, len * 0.7, len),
			p.woodDark,
			STUDS
		)
	end
	for _ = 1, rng:NextInteger(0, 2) do
		local at = h1 + h2 * rng:NextNumber(0.1, 0.6)
		local len = rng:NextNumber(1.6, 3.4)
		local lt = t2 * rng:NextNumber(0.3, 0.45)
		local limb = base
			* CFrame.new(0, at, 0)
			* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
			* CFrame.Angles(math.rad(rng:NextNumber(55, 95)), 0, 0)
		K.block(model, "Limb", limb * CFrame.new(0, len / 2, 0), Vector3.new(lt, len, lt), woodOf(rng, p), STUDS)
	end
	model.Parent = parent
end

--- A stump: short and thick, a root flare all round, and either a splintered top (it
--- snapped) or a flat cut face in the paler cut-wood colour (somebody felled it).
local function stump(parent: Instance, x: number, z: number, groundY: number, rng: Random, p: Palette)
	local model = Instance.new("Model")
	model.Name = "Stump"
	local h = rng:NextNumber(1.2, 2.8)
	local t = rng:NextNumber(2.2, 3.6)
	local base = CFrame.new(x, groundY - 0.1, z)
		* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		* CFrame.Angles(math.rad(rng:NextNumber(-3, 3)), 0, math.rad(rng:NextNumber(-3, 3)))
	K.block(model, "Stump", base * CFrame.new(0, h / 2, 0), Vector3.new(t, h, t), woodOf(rng, p), STUDS)
	if rng:NextNumber() < 0.55 then
		jagged(model, base * CFrame.new(0, h, 0), t, rng, p)
	else
		K.block(model, "CutFace", base * CFrame.new(0, h + 0.04, 0), Vector3.new(t - 0.3, 0.1, t - 0.3), p.cut, nil)
	end
	for i = 1, rng:NextInteger(3, 4) do
		local len = t * rng:NextNumber(0.45, 0.75)
		K.wedge(
			model,
			"Root",
			base * CFrame.Angles(0, math.rad(i * 90 + rng:NextNumber(-20, 20)), 0) * CFrame.new(0, h * 0.28, -(t / 2 + len / 2) + 0.1),
			Vector3.new(t * 0.42, h * 0.56, len),
			p.woodDark,
			STUDS
		)
	end
	model.Parent = parent
end

--- A fallen trunk lying along its own local X, sunk into the mud by a third of its
--- thickness. Tapers toward the snapped end, which is splintered; the other end is
--- either the torn-up root plate with its soil still on it, or a flat sawn face. A stub
--- limb or two stands off the top.
local function log(parent: Instance, x: number, z: number, groundY: number, rng: Random, p: Palette)
	local model = Instance.new("Model")
	model.Name = "Log"
	local len = rng:NextNumber(11, 19)
	local t = rng:NextNumber(1.8, 2.6)
	local sink = t * rng:NextNumber(0.25, 0.38)
	local cf = CFrame.new(x, groundY + t / 2 - sink, z)
		* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-2.5, 2.5)))
	local sections = 3
	local sl = len / sections
	local endT = t
	for i = 1, sections do
		local st = t * (1 - 0.1 * (i - 1))
		endT = st
		K.block(
			model,
			"Log",
			cf * CFrame.new(-len / 2 + sl * (i - 0.5), -(t - st) / 2, 0) * CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, 0),
			Vector3.new(sl + 0.05, st, st),
			woodOf(rng, p),
			STUDS
		)
	end
	-- The snapped end (+X): a splintered face pointing along the log.
	jagged(model, cf * CFrame.new(len / 2, -(t - endT) / 2, 0) * CFrame.Angles(0, 0, math.rad(-90)), endT, rng, p)
	if rng:NextNumber() < 0.5 then
		-- Torn up by the roots: a slab of soil and root standing on end, a few roots out of it.
		local plate = cf * CFrame.new(-len / 2 - 0.45, t * 0.25, 0)
		K.block(model, "RootPlate", plate, Vector3.new(0.9, t * 2.1, t * 1.9), p.soil, STUDS)
		for _ = 1, rng:NextInteger(3, 5) do
			local ry, rz = rng:NextNumber(-t, t * 1.05), rng:NextNumber(-t * 0.95, t * 0.95)
			local rl = rng:NextNumber(0.9, 2.2)
			K.block(
				model,
				"Root",
				plate * CFrame.new(-0.45, ry, rz) * CFrame.Angles(math.rad(rng:NextNumber(-40, 40)), math.rad(rng:NextNumber(-30, 30)), 0) * CFrame.new(-rl / 2, 0, 0),
				Vector3.new(rl, 0.32, 0.32),
				p.woodDark,
				STUDS
			)
		end
	else
		K.block(model, "CutFace", cf * CFrame.new(-len / 2 - 0.04, 0, 0), Vector3.new(0.1, t - 0.3, t - 0.3), p.cut, nil)
	end
	for _ = 1, rng:NextInteger(1, 3) do
		local along = rng:NextNumber(-len * 0.35, len * 0.4)
		local bl = rng:NextNumber(1.4, 3.6)
		local bt = rng:NextNumber(0.45, 0.7)
		local limb = cf
			* CFrame.new(along, 0, 0)
			* CFrame.Angles(math.rad(rng:NextNumber(-65, 65)), 0, math.rad(rng:NextNumber(-35, 10)))
		K.block(model, "Limb", limb * CFrame.new(0, t * 0.35 + bl / 2, 0), Vector3.new(bt, bl, bt), woodOf(rng, p), STUDS)
	end
	model.Parent = parent
end

--- A branch lying in the mud, sometimes with a fork still on it.
local function branch(parent: Instance, x: number, z: number, groundY: number, rng: Random, p: Palette)
	local len = rng:NextNumber(2.5, 6)
	local t = rng:NextNumber(0.35, 0.7)
	local cf = CFrame.new(x, groundY + t * 0.4, z) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-3, 3)))
	K.block(parent, "Branch", cf, Vector3.new(len, t, t), woodOf(rng, p, 0.5), STUDS)
	if rng:NextNumber() < 0.55 then
		local fl = len * rng:NextNumber(0.3, 0.5)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		K.block(
			parent,
			"Branch",
			cf * CFrame.new(len * rng:NextNumber(0, 0.3), 0, 0) * CFrame.Angles(0, math.rad(side * rng:NextNumber(25, 45)), 0) * CFrame.new(fl / 2, 0, 0),
			Vector3.new(fl, t * 0.7, t * 0.7),
			woodOf(rng, p, 0.5),
			STUDS
		)
	end
end

-- ── Cordons ────────────────────────────────────────────────────────────────────

--- A trefoil placard wired to a post, facing `face` (flat unit vector).
local function placard(parent: Instance, deps: Deps, at: Vector3, face: Vector3, rng: Random)
	local board = CFrame.fromMatrix(at + face * (POST_W / 2 + 0.07), face, Vector3.yAxis)
		* CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, 0)
	K.block(parent, "Placard", board, Vector3.new(0.12, 2.2, 2.6), TAPE_YELLOW, nil)
	K.block(parent, "PlacardBand", board * CFrame.new(0.07, 0.82, 0), Vector3.new(0.05, 0.5, 2.6), TAPE_BLACK, nil)
	deps.trefoil(parent, board * CFrame.new(0.08, -0.22, 0), 0.62, C.hazardBlack)
end

--- One length of tape from `a` to `b`, with black bands across it.
local function tape(parent: Instance, a: Vector3, b: Vector3)
	local d = (b - a).Magnitude
	if d < 0.1 then
		return
	end
	local frame = CFrame.lookAt((a + b) / 2, b, Vector3.yAxis)
	K.block(parent, "Tape", frame, Vector3.new(0.05, TAPE_W, d), TAPE_YELLOW, NO_SHADOW)
	local bands = math.max(1, math.floor(d / 1.6))
	for i = 1, bands do
		local along = -d / 2 + (i - 0.5) * d / bands
		K.block(parent, "TapeBand", frame * CFrame.new(0, 0, along), Vector3.new(0.07, TAPE_W + 0.02, 0.36), TAPE_BLACK, NO_SHADOW)
	end
end

type Post = { foot: Vector3, top: Vector3, up: boolean }

--- A broken cordon along `path` (post positions, world, on the ground). Each post rolls
--- a state -- standing, leaning off the line, down in the mud or gone -- and the wire and
--- tape follow it: strung taut between two posts that are up, trailing to the ground off
--- one that is up where its neighbour is not. The ends always stand.
local function cordon(parent: Instance, path: { Vector3 }, groundY: number, rng: Random, deps: Deps, placardFace: Vector3?)
	if #path < 2 then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Cordon"
	local posts: { Post } = {}
	for i, at in path do
		local foot = Vector3.new(at.X, groundY, at.Z)
		local nxt = path[math.min(#path, i + 1)]
		local prv = path[math.max(1, i - 1)]
		local run = Vector3.new(nxt.X - prv.X, 0, nxt.Z - prv.Z)
		run = if run.Magnitude > 0.01 then run.Unit else Vector3.xAxis
		local across = Vector3.new(-run.Z, 0, run.X)
		local roll = if i == 1 or i == #path then 0 else rng:NextNumber()
		if roll < 0.64 then
			local lean = rng:NextNumber(-3, 3)
			local top = foot + across * math.sin(math.rad(lean)) * POST_H + Vector3.new(0, math.cos(math.rad(lean)) * POST_H, 0)
			posts[i] = { foot = foot, top = top, up = true }
		elseif roll < 0.84 then
			local lean = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(12, 26)
			local top = foot + across * math.sin(math.rad(lean)) * POST_H + Vector3.new(0, math.cos(math.rad(lean)) * POST_H, 0)
			posts[i] = { foot = foot, top = top, up = true }
		elseif roll < 0.94 then
			-- Down: lying in the mud off its hole, a stub left standing.
			local fall = CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0).LookVector
			local a = foot + Vector3.new(0, POST_W / 2, 0) + fall * 0.4
			strut(model, "PostDown", a, a + fall * (POST_H - 0.6), POST_W, POST, nil)
			K.block(model, "PostStub", CFrame.new(foot + Vector3.new(0, 0.3, 0)), Vector3.new(POST_W, 0.6, POST_W), POST, nil)
			posts[i] = { foot = foot, top = foot, up = false }
		else
			posts[i] = { foot = foot, top = foot, up = false }
		end
	end

	local function at(post: Post, h: number): Vector3
		return post.foot:Lerp(post.top, h / POST_H)
	end

	for i, post in posts do
		if post.up then
			strut(model, "Post", post.foot - Vector3.new(0, 0.2, 0), post.top, POST_W, POST, nil)
			K.block(model, "PostCap", CFrame.lookAt(post.top, post.top + (post.top - post.foot).Unit) * CFrame.new(0, 0, -0.08), Vector3.new(POST_W + 0.1, POST_W + 0.1, 0.16), POST_CAP, nil)
		end
		local nxt = posts[i + 1]
		if not nxt then
			continue
		end
		if post.up and nxt.up then
			for _, h in WIRE_HEIGHTS do
				strut(model, "Wire", at(post, h), at(nxt, h), 0.07, WIRE, NO_SHADOW)
			end
			local a, b = at(post, TAPE_H), at(nxt, TAPE_H)
			local mid = (a + b) / 2 - Vector3.new(0, TAPE_SAG, 0)
			tape(model, a, mid)
			tape(model, mid, b)
		elseif post.up or nxt.up then
			-- Snapped: the tape and the top wire hang off the standing post to the mud.
			local from, to = if post.up then post else nxt, if post.up then nxt else post
			local ground = from.foot:Lerp(to.foot, rng:NextNumber(0.3, 0.55)) + Vector3.new(0, 0.05, 0)
			tape(model, at(from, TAPE_H), ground)
			local tail = ground + (to.foot - from.foot).Unit * rng:NextNumber(0.8, 2)
			tape(model, ground, tail + Vector3.new(0, 0.02, 0))
			strut(model, "Wire", at(from, WIRE_HEIGHTS[2]), ground + Vector3.new(0.3, 0, 0.3), 0.07, WIRE, NO_SHADOW)
		end
	end

	if placardFace then
		-- On a standing post near the middle of the run.
		local mid = math.ceil(#posts / 2)
		for off = 0, #posts do
			local i = mid + (if off % 2 == 0 then off // 2 else -(off + 1) // 2)
			local post = posts[i]
			if post and post.up then
				placard(model, deps, at(post, 2.4), placardFace, rng)
				break
			end
		end
	end

	model.Parent = parent
end

-- ── Build ──────────────────────────────────────────────────────────────────────

local function paletteFor(stageId: number, deps: Deps): Palette
	local def = Stages.get(stageId)
	local floor = K.hex(def.color)
	local wood = K.hex(deps.wood)
	return {
		ooze = K.hex(def.ooze.bright),
		oozeHex = def.ooze.bright,
		glowHex = def.ooze.glow,
		wood = wood,
		woodDark = K.hex(deps.woodDark),
		-- Sawn or snapped-fresh wood is paler than the weathered bark round it, but only
		-- a little: near-white on this dark mud read as poured concrete on the old trees.
		cut = wood:Lerp(K.hex("B8A889"), 0.4),
		soil = K.shade(floor, -0.18),
	}
end

type Spot = { x: number, z: number, r: number }

function OozeMarsh.build(parent: Instance, stageId: number, groundY: number, deps: Deps)
	local rng = Random.new(SEED + stageId)
	local f = K.field(stageId, groundY)
	local p = paletteFor(stageId, deps)

	local folder = Instance.new("Folder")
	folder.Name = "OozeMarsh"
	local poolFolder = Instance.new("Folder")
	poolFolder.Name = "Pools"
	local woodFolder = Instance.new("Folder")
	woodFolder.Name = "Wood"
	local signFolder = Instance.new("Folder")
	signFolder.Name = "Signs"

	local pools = dealPools(f, rng)
	for _, pool in pools do
		buildPool(poolFolder, pool, groundY, p, f)
	end

	local function wet(x: number, z: number, pad: number): boolean
		for _, pool in pools do
			if inPool(pool, x, z, pad) then
				return true
			end
		end
		return false
	end

	-- Everything that stands, so the next thing keeps its distance.
	local standing: { Spot } = {}
	local function clearance(x: number, z: number): number
		local best = math.huge
		for _, s in standing do
			best = math.min(best, math.sqrt((x - s.x) ^ 2 + (z - s.z) ^ 2) - s.r)
		end
		return best
	end
	local function inField(x: number, z: number, inset: number): boolean
		return x > f.minX + inset and x < f.maxX - inset and z > f.minZ + inset and z < f.maxZ - inset
	end

	--- A spot just outside a pool's edge, beside one of its spine ovals.
	local function poolEdge(pool: Pool, out: number): (number, number)
		local node = pool.spine[rng:NextInteger(1, #pool.spine)]
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local dx, dz = dirOf(-node.yaw + 90 * side)
		local off = node.b / 2 + out
		return pool.x + node.x + dx * off, pool.z + node.z + dz * off
	end

	--- Best-candidate placement for one standing thing of radius `r`: candidates are
	--- half free, half at a pool's edge (`edgeShare`), scored by clearance to everything
	--- already standing. Rejects the lane, the entrance strip, the walls and (unless
	--- `inOoze`) the pools themselves.
	local function placeStanding(r: number, minGap: number, edgeShare: number, inOoze: boolean, keepEntrance: number): (number?, number?)
		local bestX, bestZ, bestScore = nil, nil, -math.huge
		for _ = 1, 40 do
			local x, z
			if rng:NextNumber() < edgeShare then
				x, z = poolEdge(pools[rng:NextInteger(1, #pools)], rng:NextNumber(0.8, 3) + r * 0.5)
			else
				x, z = rng:NextNumber(f.minX, f.maxX), rng:NextNumber(f.minZ, f.maxZ)
			end
			if
				inField(x, z, r + 2)
				and x > f.minX + keepEntrance
				and not K.onLane(z, r + 2)
				and (inOoze or not wet(x, z, 0.5))
			then
				local score = clearance(x, z) - r
				if score > bestScore then
					bestX, bestZ, bestScore = x, z, score
				end
			end
		end
		if bestX and bestScore >= minGap then
			return bestX, bestZ
		end
		return nil, nil
	end

	-- The big trees: the first two at a pool's edge (the lake, then the biggest broad
	-- pool -- a dead tree standing over the ooze is what this field is), the other two
	-- in open mud, all of them TREE_GAP apart.
	for i = 1, TREES do
		local x, z
		if i <= 2 then
			for _ = 1, 40 do
				local tx, tz = poolEdge(pools[i], rng:NextNumber(2, 4))
				if
					inField(tx, tz, 12)
					and tx > f.minX + ENTRANCE_KEEP
					and not K.onLane(tz, 6)
					and not wet(tx, tz, 1)
					and clearance(tx, tz) > TREE_GAP
				then
					x, z = tx, tz
					break
				end
			end
		end
		if not x then
			x, z = placeStanding(10, TREE_GAP - 10, 0, false, ENTRANCE_KEEP)
		end
		if x and z then
			deps.tree(woodFolder, x, z, rng)
			table.insert(standing, { x = x, z = z, r = 10 })
		end
	end

	-- The cordons go down before the small wood so a log never lands across a tape line.
	-- Round the lake and round the broad pool with no tree at it, each an arc of a bit
	-- over half a circle facing a random way, broken wherever it would cross the lane or
	-- leave the plate.
	local cordonFolder = Instance.new("Folder")
	cordonFolder.Name = "Cordons"
	for _, pool in { pools[1], pools[3] } do
		local radius = pool.reach + rng:NextNumber(4, 7)
		local a0 = rng:NextNumber(0, 360)
		local sweep = rng:NextNumber(160, 220)
		local steps = math.max(2, math.floor(math.rad(sweep) * radius / POST_SPACING))
		local run: { Vector3 } = {}
		local function flush()
			if #run >= 3 then
				-- The placard faces out, away from the pool, from the run's middle.
				local mid = run[math.ceil(#run / 2)]
				local face = Vector3.new(mid.X - pool.x, 0, mid.Z - pool.z)
				cordon(cordonFolder, run, groundY, rng, deps, if face.Magnitude > 0 then face.Unit else nil)
				for _, post in run do
					table.insert(standing, { x = post.X, z = post.Z, r = 2 })
				end
			end
			run = {}
		end
		for s = 0, steps do
			local ang = math.rad(a0 + sweep * s / steps)
			local x, z = pool.x + math.cos(ang) * radius, pool.z + math.sin(ang) * radius
			if inField(x, z, 3) and not K.onLane(z, 1) and clearance(x, z) > 2 then
				table.insert(run, Vector3.new(x, groundY, z))
			else
				flush()
			end
		end
		flush()
	end
	cordonFolder.Parent = folder

	for _ = 1, SNAGS do
		local x, z = placeStanding(3, 12, 0.5, false, ENTRANCE_KEEP)
		if x and z then
			snag(woodFolder, x, z, groundY, rng, p)
			table.insert(standing, { x = x, z = z, r = 4 })
		end
	end
	for _ = 1, LOGS do
		-- Logs may lie into the ooze: a trunk that fell into the pool it died beside.
		local x, z = placeStanding(7, 8, 0.6, true, 12)
		if x and z then
			log(woodFolder, x, z, groundY, rng, p)
			table.insert(standing, { x = x, z = z, r = 9 })
		end
	end
	for _ = 1, STUMPS do
		local x, z = placeStanding(2, 10, 0.45, false, 12)
		if x and z then
			stump(woodFolder, x, z, groundY, rng, p)
			table.insert(standing, { x = x, z = z, r = 3 })
		end
	end
	-- Loose branches are flat: they ignore the lane and the standing list, and sit mostly
	-- under the trees and snags they came off.
	local wood: { Spot } = {}
	for _, s in standing do
		if s.r >= 3 then
			table.insert(wood, s)
		end
	end
	for i = 1, BRANCHES do
		local s = wood[((i - 1) % math.max(1, #wood)) + 1]
		local x, z
		if s and rng:NextNumber() < 0.7 then
			local ang = rng:NextNumber(0, math.pi * 2)
			local d = s.r * rng:NextNumber(0.4, 0.9) + rng:NextNumber(1, 4)
			x, z = s.x + math.cos(ang) * d, s.z + math.sin(ang) * d
		else
			x, z = rng:NextNumber(f.minX, f.maxX), rng:NextNumber(f.minZ, f.maxZ)
		end
		if inField(x, z, 3) then
			branch(woodFolder, x, z, groundY, rng, p)
		end
	end

	-- The signs. Badges face local -X, which is WEST, toward a player walking in: a yaw
	-- of 180 +- 30 would show the blank back, so they stay within +-30 of it.
	--   two by the entrance, one either side of the lane, standing near straight;
	--   two out in the field, leant well over;
	--   one knocked flat on its back beside a cordon.
	local signSpots: { { x: number, z: number, lean: number, flat: boolean } } = {}
	for _, side in { -1, 1 } do
		table.insert(signSpots, {
			x = f.minX + rng:NextNumber(6, 18),
			z = side * rng:NextNumber(K.LANE_HALF + 8, f.maxZ - 14),
			lean = rng:NextNumber(0, 5),
			flat = false,
		})
	end
	for _ = 1, 2 do
		local x, z = placeStanding(3, 8, 0.7, false, ENTRANCE_KEEP)
		if x and z then
			table.insert(signSpots, { x = x, z = z, lean = rng:NextNumber(12, 22), flat = false })
			table.insert(standing, { x = x, z = z, r = 3 })
		end
	end
	do
		local x, z = placeStanding(3, 6, 0.3, false, 20)
		if x and z then
			table.insert(signSpots, { x = x, z = z, lean = 0, flat = true })
		end
	end
	for _, s in signSpots do
		local yaw = rng:NextNumber(-30, 30)
		local base
		if s.flat then
			-- Tipped onto its back (top toward +X), face up, lying on its 1-stud thickness.
			base = CFrame.new(s.x, groundY + 0.5, s.z) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(0, 0, math.rad(-86))
		else
			local sideways = rng:NextNumber(-1, 1) * s.lean
			local back = rng:NextNumber(-0.6, 0.6) * s.lean
			local sink = 0.5 * math.sin(math.rad(math.max(math.abs(sideways), math.abs(back)))) + 0.05
			base = CFrame.new(s.x, groundY - sink, s.z)
				* CFrame.Angles(0, math.rad(yaw), 0)
				* CFrame.Angles(math.rad(sideways), 0, math.rad(back))
		end
		deps.sign(signFolder, base)
	end

	poolFolder.Parent = folder
	woodFolder.Parent = folder
	signFolder.Parent = folder

	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end

	folder.Parent = parent
end

return OozeMarsh
