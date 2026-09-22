--!strict
--[[
	CraterField.luau — the craters Config/StageCraters describes, built into a stage.

	    called from build/Scenery: `build` from buildStageScenery, `groundColorAt` from
	    buildStageCheckerboard

	WHAT A CRATER IS HERE. A raised rim on the level stage floor (Config/StageCraters has
	why it is not a pit): a berm of flat triangular facets round an uneven ellipse, a
	bowl-shaped inner wall and a gentler outer flank, both solid and walkable. The floor
	inside is the stage's own checkerboard, darkened toward the middle (`groundColorAt`),
	and the scorch carries a little way out past the outer foot. Every crater has blast
	rubble kicked up round its lip; the big one also throws dark ejecta rays out across
	the plain and has a pool of fused glass at ground zero. A few rims still smoke
	(`vents` in Config/StageCraters). The dirt and wreckage across the rest of the
	stage is build/BlastDebris.

	TRIANGLES, NOT A RING OF BLOCKS. A berm of boxes, one per step round the circle,
	steps wherever two neighbours' heights differ and gaps on the outside of the curve.
	Every facet here is a true triangle between shared vertices, built from two
	WedgeParts (`triangle`), so the surface is continuous: no steps, no gaps, and the
	crest can rise and fall smoothly all the way round. The facets are the low-poly look.

	SOLID RIM, WALK-THROUGH EVERYTHING ELSE. The facets collide: you climb up and over, so
	a crater is ground you cross, not a sticker on it. Rubble, rays, glass and vents are
	CanCollide false like the rest of build/Scenery. Everything that stands up sits where
	StageCraters.blocksDig already keeps signals out; the glass is on dug ground and is
	flat for exactly that reason (see Ground zero below).
	The facets' thickness hangs BELOW the surface, so the ridge and the feet show clean
	edges and the slab bodies meet out of sight underneath.

	NO GLOWING CRACKS ON THE FLOOR, ON PURPOSE. A detector spot already draws glowing
	cracks in the ground (Tuning.AURA_CRACKS). The big crater's floor is diggable, and
	violet fissures on it would read as signals that are not there.

	DETERMINISTIC. Jitter comes off each crater's own `seed`, never the stage rng, so
	moving or adding a crater cannot shuffle any other prop in the field, and a rebuild
	reproduces the same rims.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local StageCraters = require(Shared.Config.StageCraters)

local CraterField = {}

type Crater = StageCraters.Crater

--- A crater at least this big (crest radius, studs) gets the detailed five-ring rim,
--- the ejecta rays and the boulders. Anything smaller is a pock: a three-ring lip.
local DETAILED_RADIUS = 20

--- Facet slab thickness. Thick enough that a character walking the flank never falls
--- through a seam between two facets; it hangs under the surface, so it never shows.
local RIM_THICKNESS = 0.6

--- The rim's cross-section, inner foot to outer foot: { rho, height as a fraction of the
--- crest }. The inner wall is a bowl -- the first half of its run climbs under a third
--- of the height, then it steepens into the crest. The outer flank is the reverse: a
--- shoulder off the crest, then a long low apron of thrown-out ground.
local function profileOf(c: Crater): { { number } }
	if c.radius >= DETAILED_RADIUS then
		return {
			{ c.floorFrac, 0 },
			{ c.floorFrac + (1 - c.floorFrac) * 0.5, 0.3 },
			{ 1, 1 },
			{ 1 + (c.outerFrac - 1) * 0.4, 0.52 },
			{ c.outerFrac, 0 },
		}
	end
	return { { c.floorFrac, 0 }, { 1, 1 }, { c.outerFrac, 0 } }
end

--- The analytic surface height above the floor at (bearing, rho) -- the profile with no
--- jitter. What rubble is set down on; the real facets wander a few percent off it,
--- which a half-sunk boulder swallows.
local function surfaceAt(c: Crater, profile: { { number } }, bearing: number, rho: number): number
	local h = StageCraters.crestHeight(c, bearing)
	for i = 1, #profile - 1 do
		local p, q = profile[i], profile[i + 1]
		if rho >= p[1] and rho <= q[1] then
			local t = (rho - p[1]) / (q[1] - p[1])
			return (p[2] + (q[2] - p[2]) * t) * h
		end
	end
	return 0
end

-- ── Colour ─────────────────────────────────────────────────────────────────────
-- Everything is the stage's own colour pushed two ways: toward ASH for ground that was
-- thrown up (the outer flank, the rubble), toward SCORCH for ground that was burnt
-- where it lay (the inner wall, the floor, the rays). Nothing here is a new hue, so a
-- crater reads as the stage's ground, blasted -- not as something laid on top of it.
local ASH = Color3.fromHex("3A3342")
local SCORCH = Color3.fromHex("1C0E2E")
local WHITE = Color3.new(1, 1, 1)

--- The floor tint. FLOOR_* is how far the checkerboard inside a crater is pushed toward
--- SCORCH, from the foot of the inner wall to the middle. APRON_SCORCH is the outer
--- foot's tint, fading by SCORCH_FALLOFF per unit rho out onto the plain, mottled by
--- SCORCH_MOTTLE of low-frequency noise so it does not end in a clean ring. A pock
--- burns SMALL_SCORCH as hard as the big crater.
local FLOOR_SCORCH_EDGE = 0.42
local FLOOR_SCORCH_CENTRE = 0.6
local APRON_SCORCH = 0.38
local SCORCH_FALLOFF = 2.4
local SCORCH_MOTTLE = 0.4
local SMALL_SCORCH = 0.8

type Palette = {
	outer: Color3,
	inner: Color3,
	rubble: { Color3 },
	ray: Color3,
	glass: Color3,
	melt: Color3,
	crack: Color3,
}

local function paletteFor(stageId: number): Palette
	local base = Color3.fromHex(Stages.get(stageId).color)
	return {
		outer = base:Lerp(ASH, 0.3),
		inner = base:Lerp(SCORCH, 0.5),
		rubble = { base:Lerp(ASH, 0.42), base:Lerp(ASH, 0.25), base:Lerp(SCORCH, 0.35) },
		ray = base:Lerp(SCORCH, 0.5),
		-- The ground at ground zero melted and set as glass (the real thing, trinitite, is
		-- bottle green; this is the Crater's violet taken nearly to black). A sheen, never
		-- a light, so the no-glow rule holds -- see GLASS_REFLECTANCE.
		glass = base:Lerp(SCORCH, 0.74),
		melt = base:Lerp(SCORCH, 0.62):Lerp(ASH, 0.18),
		crack = SCORCH:Lerp(Color3.new(0, 0, 0), 0.4),
	}
end

--- One facet's shade: its face colour, nudged a few percent lighter or darker at random.
--- NOT a strict light/dark alternation round the rim -- that was the first version, and
--- shot live it striped the outer flank into a circus tent. Uneven nudges read as
--- broken ground instead.
local function facetTone(face: Color3, rng: Random): Color3
	if rng:NextNumber() < 0.5 then
		return face:Lerp(WHITE, rng:NextNumber(0, 0.05))
	end
	return face:Lerp(SCORCH, rng:NextNumber(0, 0.08))
end

-- ── Geometry ───────────────────────────────────────────────────────────────────

--- What a run of triangles is made of. The rim is solid ground you climb; everything
--- flat laid on the floor (the glass) is a skin like the checker cap under it --
--- CanCollide and CanQuery off, so footing, burial and the range-ring raycast all stay
--- on the real plate.
type Style = { name: string, material: Enum.Material, thickness: number, solid: boolean, reflectance: number }

--- GLASS IS NOT Enum.Material.Glass. Shot live, that material mirrored the Crater's
--- bright hazy sky off a flat, upward-facing pool and turned a near-black violet into a
--- pale grey puddle. Smooth plastic with a little reflectance keeps the colour dark and
--- still catches a sheen at a low angle.
local GLASS_REFLECTANCE = 0.06

local RIM_STYLE: Style = { name = "Rim", material = Enum.Material.SmoothPlastic, thickness = RIM_THICKNESS, solid = true, reflectance = 0 }
local GLASS_STYLE: Style = {
	name = "FusedGlass",
	material = Enum.Material.SmoothPlastic,
	thickness = 0.05,
	solid = false,
	reflectance = GLASS_REFLECTANCE,
}
local MELT_STYLE: Style = { name = "Melt", material = Enum.Material.SmoothPlastic, thickness = 0.05, solid = false, reflectance = 0 }

local function wedge(parent: Instance, cf: CFrame, size: Vector3, color: Color3, style: Style)
	local w = Instance.new("WedgePart")
	w.Name = style.name
	w.Anchored = true
	w.CanTouch = false
	w.CanCollide = style.solid
	if not style.solid then
		w.CanQuery = false -- only settable once CanCollide is off
	end
	w.Material = style.material
	w.Reflectance = style.reflectance
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Color = color
	w.Size = size
	w.CFrame = cf
	w.Parent = parent
end

--- One flat triangle (a, b, c) out of two WedgeParts: split along the altitude from the
--- vertex opposite the longest edge, each half a right triangle, which is exactly a
--- wedge's cross-section. The slabs are sunk half their thickness along the UPWARD
--- normal, so their top faces lie on the triangle and their bodies hang below it.
--- (Checked numerically: over random triangles both top faces land on the three
--- vertices and one shared foot, and their areas sum to the triangle's.)
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, color: Color3, style: Style)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b

	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-4 then
		return -- degenerate: three points in a line
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local normal = if right.Y >= 0 then right else -right
	local t = style.thickness
	local sink = normal * (-t / 2)

	wedge(parent, CFrame.fromMatrix((a + b) / 2 + sink, right, up, back), Vector3.new(t, height, math.abs(ab:Dot(back))), color, style)
	wedge(parent, CFrame.fromMatrix((a + c) / 2 + sink, -right, up, -back), Vector3.new(t, height, math.abs(ac:Dot(back))), color, style)
end

local function flat(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

local function direction(bearing: number): (number, number)
	local r = math.rad(bearing)
	return math.cos(r), math.sin(r)
end

--- The berm. One column of vertices per segment bearing, one vertex per profile ring;
--- each pair of neighbouring columns is a strip of quads, two triangles each. The
--- diagonal alternates so no one direction of the split reads across the whole rim.
---
--- THE JITTER IS WHAT STOPS IT BEING A CONE. With the analytic profile alone (and the
--- first pass's +-3% / +-8%), the outer flank shot live as one smooth frustum however
--- lopsided the outline was. Every raised vertex now wanders RIM_WANDER_R off its
--- radius and RIM_WANDER_Y off its height, so the crest is jagged and the flank lumpy.
--- The feet wander far less: the dig margins in Config/StageCraters are measured off
--- them, and 2.5% of the outer foot stays inside DIG_OUTER_MARGIN.
local RIM_WANDER_R = 0.045
local RIM_WANDER_Y = 0.14
local FOOT_WANDER_R = 0.025
--- Returns the vertex columns and which ring is the crest, so the smoke vents can be set
--- on the rim's real surface rather than on the analytic profile it wanders off.
local function buildRim(parent: Instance, c: Crater, profile: { { number } }, groundY: number, rng: Random, palette: Palette): ({ { Vector3 } }, number)
	local n = c.segments
	local crestRing = 1
	for j, ring in profile do
		if ring[2] == 1 then
			crestRing = j
		end
	end

	local columns: { { Vector3 } } = {}
	for i = 0, n - 1 do
		-- Each spoke wanders up to a quarter-step off even spacing, so the facets are not
		-- all the same width. Never half a step: the spokes must stay in order.
		local bearing = (i + rng:NextNumber(-0.25, 0.25)) * 360 / n
		local dx, dz = direction(bearing)
		local crestR = StageCraters.crestRadius(c, bearing)
		local crestH = StageCraters.crestHeight(c, bearing)
		local column = {}
		for j, ring in profile do
			local rho, lift = ring[1], ring[2]
			local r, y
			if lift > 0 then
				r = crestR * rho * (1 + rng:NextNumber(-RIM_WANDER_R, RIM_WANDER_R))
				y = groundY + lift * crestH * (1 + rng:NextNumber(-RIM_WANDER_Y, RIM_WANDER_Y))
			else
				-- A foot sits a hair under the checker cap so the facet rises out of the
				-- tiles.
				r = crestR * rho * (1 + rng:NextNumber(-FOOT_WANDER_R, FOOT_WANDER_R))
				y = groundY - 0.04
			end
			column[j] = Vector3.new(c.center[1] + dx * r, y, c.center[2] + dz * r)
		end
		columns[i + 1] = column
	end

	for i = 1, n do
		local here, there = columns[i], columns[i % n + 1]
		for j = 1, #profile - 1 do
			local color = facetTone(if j < crestRing then palette.inner else palette.outer, rng)
			local a, b, cc, d = here[j], here[j + 1], there[j + 1], there[j]
			if (i + j) % 2 == 0 then
				triangle(parent, a, b, cc, color, RIM_STYLE)
				triangle(parent, a, cc, d, color, RIM_STYLE)
			else
				triangle(parent, a, b, d, color, RIM_STYLE)
				triangle(parent, b, cc, d, color, RIM_STYLE)
			end
		end
	end

	return columns, crestRing
end

--- Slabs of ground kicked up round the lip, each lying roughly along its own spoke and
--- tipped off the flank at a different angle, sunk into the slope they landed on. FLAT
--- AND BURIED, on a live look: the first pass's chunkier slabs sat proud of the flank
--- and read as cubes dropped on it, not as ground that broke.
local function buildRubble(parent: Instance, c: Crater, profile: { { number } }, groundY: number, rng: Random, palette: Palette)
	local detailed = c.radius >= DETAILED_RADIUS
	local count = if detailed then 18 else math.max(3, math.round(c.radius * 0.45))
	local scale = if detailed then 2.4 else c.radius / 10 * 1.2
	for _ = 1, count do
		local bearing = rng:NextNumber(0, 360)
		local rho = rng:NextNumber(0.9, math.min(1.2, c.outerFrac - 0.1))
		local dx, dz = direction(bearing)
		local r = StageCraters.crestRadius(c, bearing) * rho
		local w = rng:NextNumber(0.9, 1.9) * scale
		local size = Vector3.new(w, w * rng:NextNumber(0.2, 0.36), w * rng:NextNumber(1.0, 1.7))
		local at = Vector3.new(c.center[1] + dx * r, groundY + surfaceAt(c, profile, bearing, rho) - size.Y * 0.1, c.center[2] + dz * r)
		local cf = CFrame.lookAt(at, at + Vector3.new(dx, 0, dz))
			* CFrame.Angles(math.rad(rng:NextNumber(-35, 35)), math.rad(rng:NextNumber(-30, 30)), math.rad(rng:NextNumber(-20, 20)))
		flat(parent, "Rubble", cf, size, palette.rubble[rng:NextInteger(1, #palette.rubble)], Enum.Material.SmoothPlastic)
	end

	if not detailed then
		return
	end
	-- Boulders down the big crater's outer apron: chunky, tumbled any way up, sunk to
	-- about a third of their height. Held inside the no-dig ring (rho < outerFrac).
	for _ = 1, 10 do
		local bearing = rng:NextNumber(0, 360)
		local rho = rng:NextNumber(1.08, c.outerFrac - 0.06)
		local dx, dz = direction(bearing)
		local r = StageCraters.crestRadius(c, bearing) * rho
		local s = rng:NextNumber(1.8, 3.6)
		local size = Vector3.new(s * rng:NextNumber(0.8, 1.2), s * rng:NextNumber(0.6, 0.9), s * rng:NextNumber(0.8, 1.3))
		local at = Vector3.new(c.center[1] + dx * r, groundY + surfaceAt(c, profile, bearing, rho) + size.Y * 0.2, c.center[2] + dz * r)
		local cf = CFrame.new(at) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-25, 25)))
		flat(parent, "Boulder", cf, size, palette.rubble[rng:NextInteger(1, #palette.rubble)], Enum.Material.SmoothPlastic)
	end
end

--- Dark streaks of thrown-out ground running out from the big crater across the
--- plain, each three flat strips narrowing as they go. Flat, a hair over the checker
--- cap, and held inside the plate.
---
--- UNEVEN BEARINGS, NOT A STAR. The first pass spaced nine evenly round the rim (with a
--- little jitter), and from above that is a child's drawing of the sun. Now RAY_COUNT
--- bearings are rolled freely, only held RAY_MIN_GAP apart so two never fuse into one
--- fat streak, and their lengths spread wide.
local RAY_COUNT = 7
local RAY_MIN_GAP = 26

local function buildRays(parent: Instance, c: Crater, groundY: number, rng: Random, palette: Palette)
	local minX, minZ, maxX, maxZ = Stages.bounds(c.stageId)
	local bearings: { number } = {}
	for _ = 1, 200 do
		if #bearings >= RAY_COUNT then
			break
		end
		local candidate = rng:NextNumber(0, 360)
		local clear = true
		for _, other in bearings do
			if math.abs((candidate - other + 180) % 360 - 180) < RAY_MIN_GAP then
				clear = false
				break
			end
		end
		if clear then
			table.insert(bearings, candidate)
		end
	end

	for _, bearing in bearings do
		local dx, dz = direction(bearing)
		local crestR = StageCraters.crestRadius(c, bearing)
		local start = crestR * (c.outerFrac - 0.08)
		local length = crestR * rng:NextNumber(0.35, 1.15)
		local width = rng:NextNumber(2.5, 4.5)

		-- Shorten any ray that would run off the plate (6 studs of margin, clear of the
		-- border strips and the walls).
		local function inside(dist: number): boolean
			local x, z = c.center[1] + dx * dist, c.center[2] + dz * dist
			return x > minX + 6 and x < maxX - 6 and z > minZ + 6 and z < maxZ - 6
		end
		while length > 4 and not inside(start + length) do
			length -= 2
		end
		if length <= 4 then
			continue
		end

		local pieces = 3
		local seg = length / pieces
		for p = 1, pieces do
			local mid = start + (p - 0.5) * seg
			local pos = Vector3.new(c.center[1] + dx * mid, groundY + 0.015 + p * 0.004, c.center[2] + dz * mid)
			local w = width * (1 - 0.3 * (p - 1))
			flat(parent, "Ray", CFrame.lookAt(pos, pos + Vector3.new(dx, 0, dz)), Vector3.new(w, 0.04, seg + 0.8), palette.ray, Enum.Material.SmoothPlastic)
		end
	end
end

--- A flattened ellipsoid lying on the ground: a plain Part carrying a Sphere SpecialMesh,
--- because a Cylinder or Ball Shape silently forces a circle (build/Scenery's oozeDisc
--- has the whole story). `a` x `b` across, `h` thick.
local function disc(parent: Instance, name: string, at: Vector3, a: number, b: number, h: number, yaw: number, color: Color3, material: Enum.Material)
	local p = flat(parent, name, CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0), Vector3.one, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(a, h, b)
	mesh.Parent = p
	return p
end

-- ── Ground zero ────────────────────────────────────────────────────────────────
-- Where the fireball touched down the ground melted and set as glass: a glossy pool
-- off the dead middle of the big crater's floor, a dull ring of half-melted ground round
-- it, dark crazing across it where it cracked as it cooled, and beads of it splashed out
-- over the floor.
--
-- ALL OF IT IS FLAT AND WALK-THROUGH, BECAUSE THIS FLOOR IS DUG. Signals spawn here
-- (Config/StageCraters `digFloor`), so everything sits under a detector spot's cracks
-- (client/SpotCracks, 0.15 over the plate and up) and under the range ring's rim. The
-- heights below are over the checker cap (itself 0.06 over the plate): the glass tops
-- out at 0.09 over the plate, the crazing at 0.105, a bead at 0.12.
-- The crazing is dark, never lit -- a lit crack in this floor would read as a signal.
local GLASS_SIZE = 0.36 -- the pool's mean radius, as a fraction of the floor's short radius
local GLASS_POINTS = 28
local GLASS_CRAZE = 7
local GLASS_BEADS = 14
local MELT_TOP = 0.02
local GLASS_TOP = 0.03
local CRAZE_TOP = 0.045
--- How far inside the floor's edge (rho) the glass keeps -- clear of the inner wall.
local GLASS_FLOOR_INSET = 0.08

local function buildGlass(parent: Instance, c: Crater, groundY: number, rng: Random, palette: Palette)
	local gx = c.center[1] + rng:NextNumber(-3, 3)
	local gz = c.center[2] + rng:NextNumber(-3, 3)
	local base = (c.radius / c.aspect) * c.floorFrac * GLASS_SIZE
	local limit = c.floorFrac - GLASS_FLOOR_INSET

	--- The farthest the glass may reach from its own centre along an angle before it
	--- would climb the inner wall. Bisected against the crater's real outline.
	local function room(t: number): number
		local lo, hi = 0, c.radius
		for _ = 1, 18 do
			local mid = (lo + hi) / 2
			if StageCraters.rho(c, gx + math.cos(t) * mid, gz + math.sin(t) * mid) <= limit then
				lo = mid
			else
				hi = mid
			end
		end
		return lo
	end

	local p1, p2, p3 = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, math.pi * 2)
	local centre = Vector3.new(gx, groundY + GLASS_TOP, gz)
	local inner: { Vector3 } = {}
	local outer: { Vector3 } = {}
	local reach: { number } = {}
	for i = 0, GLASS_POINTS - 1 do
		local t = i / GLASS_POINTS * math.pi * 2
		local shape = 1 + 0.16 * math.cos(2 * t + p1) + 0.1 * math.cos(3 * t + p2) + 0.06 * math.cos(5 * t + p3)
		local max = room(t)
		local r = math.min(base * shape * (1 + rng:NextNumber(-0.12, 0.12)), max * 0.7)
		local ro = math.min(r * rng:NextNumber(1.2, 1.45), max)
		inner[i + 1] = Vector3.new(gx + math.cos(t) * r, groundY + GLASS_TOP, gz + math.sin(t) * r)
		outer[i + 1] = Vector3.new(gx + math.cos(t) * ro, groundY + MELT_TOP, gz + math.sin(t) * ro)
		reach[i + 1] = r
	end

	-- The pool is one fan off its centre, the melt ring one strip round it sharing the
	-- pool's edge -- so nothing overlaps anything and nothing flat can z-fight.
	for i = 1, GLASS_POINTS do
		local j = i % GLASS_POINTS + 1
		triangle(parent, centre, inner[i], inner[j], palette.glass, GLASS_STYLE)
		local melt = facetTone(palette.melt, rng)
		triangle(parent, inner[i], outer[i], outer[j], melt, MELT_STYLE)
		triangle(parent, inner[i], outer[j], inner[j], melt, MELT_STYLE)
	end

	local function reachAt(t: number): number
		local index = math.floor((t % (math.pi * 2)) / (math.pi * 2) * GLASS_POINTS) + 1
		return reach[math.clamp(index, 1, GLASS_POINTS)]
	end

	-- Crazing: short kinked runs of dark crack, held inside the pool. Each starts
	-- somewhere of its own across the pool and heads off on its own bearing -- a
	-- network, the way cooling glass breaks. Started from the middle, the first pass
	-- read as a splat drawn on the floor.
	for _ = 1, GLASS_CRAZE do
		local t = rng:NextNumber(0, math.pi * 2)
		local from = centre + Vector3.new(math.cos(t), 0, math.sin(t)) * reachAt(t) * rng:NextNumber(0.1, 0.65)
		local heading = rng:NextNumber(0, math.pi * 2)
		local width = rng:NextNumber(0.14, 0.26)
		for _ = 1, 3 do
			heading += math.rad(rng:NextNumber(-32, 32))
			local dir = Vector3.new(math.cos(heading), 0, math.sin(heading))
			local to = from + dir * base * rng:NextNumber(0.16, 0.3)
			local offset = to - centre
			if offset.Magnitude > reachAt(math.atan2(offset.Z, offset.X)) * 0.85 then
				break
			end
			local mid = (from + to) / 2
			mid = Vector3.new(mid.X, groundY + CRAZE_TOP - 0.01, mid.Z)
			flat(parent, "Craze", CFrame.lookAt(mid, mid + dir), Vector3.new(width, 0.02, (to - from).Magnitude + width), palette.crack, Enum.Material.SmoothPlastic)
			from = to
		end
	end

	-- Beads: splashes of melt thrown out over the floor, domed, never onto the wall.
	for _ = 1, GLASS_BEADS do
		local t = rng:NextNumber(0, math.pi * 2)
		local dist = reachAt(t) * rng:NextNumber(1.05, 1.9)
		local x, z = gx + math.cos(t) * dist, gz + math.sin(t) * dist
		if StageCraters.rho(c, x, z) <= limit then
			local a = rng:NextNumber(0.35, 1.2)
			local bead = disc(parent, "GlassBead", Vector3.new(x, groundY + 0.01, z), a, a / rng:NextNumber(1, 1.6), 0.1, rng:NextNumber(0, 360), palette.glass, Enum.Material.SmoothPlastic)
			bead.Reflectance = GLASS_REFLECTANCE
		end
	end
end

-- ── Smoke ──────────────────────────────────────────────────────────────────────
-- A few cracks in the rim still smoking. Each vent is a clutch of dark slivers lying in
-- the rim's own surface, set on a real rim vertex (not the analytic profile, which the
-- facets wander 14% off), and an invisible anchor carrying one slow emitter.
--
-- REAL SMOKE, NOT A GLOW: LightEmission 0 and LightInfluence 1, so the plume is lit by
-- the Crater's amber sky like any other thing in it and nothing emits. Every vent leans
-- on the one WIND, so the plumes drift together the way real ones would. A vent is a
-- landmark you see from across the stage, never a wall of fog in front of a detector
-- spot -- but the first pass (peak opacity 0.3, 5.5 studs wide) was so thin it did not
-- show at all against the pale walls, so these are the numbers tuned live after it.
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- the same one the detonations use
local SMOKE_DARK = Color3.fromHex("2E2934")
local SMOKE_PALE = Color3.fromHex("6A6472")
local WIND = Vector3.new(0.55, 0, 0.3)

local function smoke(anchor: BasePart, big: boolean)
	local s = if big then 1 else 0.65
	local e = Instance.new("ParticleEmitter")
	e.Name = "Smoke"
	e.Texture = SMOKE_TEXTURE
	e.Color = ColorSequence.new(SMOKE_DARK, SMOKE_PALE)
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2 * s),
		NumberSequenceKeypoint.new(0.3, 3.6 * s),
		NumberSequenceKeypoint.new(1, 8 * s),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.08, 0.45),
		NumberSequenceKeypoint.new(0.5, 0.62),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(7, 10)
	e.Rate = if big then 4 else 2.5
	e.Speed = NumberRange.new(2.2 * s + 0.6, 3.4 * s + 0.6)
	e.SpreadAngle = Vector2.new(10, 10)
	e.Acceleration = WIND + Vector3.new(0, 0.1, 0)
	e.Drag = 0.2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-18, 18)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = anchor
end

local function buildVents(parent: Instance, c: Crater, columns: { { Vector3 } }, crestRing: number, rng: Random, palette: Palette)
	local count = c.vents or 0
	if count <= 0 then
		return
	end
	local big = c.radius >= DETAILED_RADIUS
	local scale = if big then 1 else 0.6
	local n = #columns
	local offset = rng:NextInteger(0, n - 1)
	for k = 1, count do
		-- Spread round the rim, not bunched: one per 1/count of the way round, jittered.
		local col = (offset + math.floor((k - 1 + rng:NextNumber(-0.3, 0.3)) * n / count)) % n + 1
		-- On the detailed rim half of them sit on the inner wall's shoulder, a step
		-- down from the crest, so not every plume stands on the skyline.
		local ring = crestRing
		if crestRing > 2 and rng:NextNumber() < 0.5 then
			ring = crestRing - 1
		end
		local column = columns[col]
		local at = column[ring]
		local along = columns[col % n + 1][ring] - columns[(col - 2) % n + 1][ring]
		local across = column[math.min(ring + 1, #column)] - column[ring - 1]
		local normal = along:Cross(across).Unit
		if normal.Y < 0 then
			normal = -normal
		end
		local tangent = along.Unit

		for s = 1, 3 do
			local dir = CFrame.fromAxisAngle(normal, math.rad((s - 2) * 28 + rng:NextNumber(-25, 25))):VectorToWorldSpace(tangent)
			local side = normal:Cross(dir).Unit
			local mid = at + dir * rng:NextNumber(-0.6, 0.6) * scale + side * rng:NextNumber(-0.4, 0.4) * scale
			flat(
				parent,
				"VentCrack",
				CFrame.fromMatrix(mid, side, normal, side:Cross(normal)),
				Vector3.new(rng:NextNumber(0.18, 0.35) * scale + 0.08, 0.2, rng:NextNumber(1.2, 2.6) * scale),
				palette.crack,
				Enum.Material.SmoothPlastic
			)
		end

		local anchor = flat(parent, "Vent", CFrame.new(at + normal * 0.25), Vector3.new(0.4, 0.4, 0.4), palette.crack, Enum.Material.SmoothPlastic)
		anchor.Transparency = 1
		anchor.CastShadow = false
		smoke(anchor, big)
	end
end

-- ── Public ─────────────────────────────────────────────────────────────────────

--- Build every crater on `stageId` into `parent` (buildStageScenery's stage folder).
--- `groundY` is the top of the checkerboard cap -- the height the floor reads at.
function CraterField.build(parent: Instance, stageId: number, groundY: number)
	local craters = StageCraters.forStage(stageId)
	if #craters == 0 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "ImpactCraters"
	local palette = paletteFor(stageId)

	for _, c in craters do
		local model = Instance.new("Model")
		model.Name = c.name
		local rng = Random.new(c.seed)
		local profile = profileOf(c)
		-- Order matters: every pass draws on this one rng, so a new pass goes on the END
		-- or it moves everything built after it.
		local columns, crestRing = buildRim(model, c, profile, groundY, rng, palette)
		buildRubble(model, c, profile, groundY, rng, palette)
		if c.radius >= DETAILED_RADIUS then
			buildRays(model, c, groundY, rng, palette)
			buildGlass(model, c, groundY, rng, palette)
		end
		buildVents(model, c, columns, crestRing, rng, palette)
		model.Parent = folder
	end

	folder.Parent = parent
end

--- How far a floor tile at (x, z) is pushed toward SCORCH, 0..1: the strongest pull of
--- any crater on the stage. See the FLOOR_* constants.
local function scorchAt(craters: { Crater }, x: number, z: number): number
	local best = 0
	for _, c in craters do
		local rho = StageCraters.rho(c, x, z)
		local t
		if rho <= c.floorFrac then
			t = FLOOR_SCORCH_EDGE + (FLOOR_SCORCH_CENTRE - FLOOR_SCORCH_EDGE) * (1 - rho / c.floorFrac)
		elseif rho <= c.outerFrac then
			t = FLOOR_SCORCH_EDGE -- under the rim; only the tiles at its feet ever show
		else
			local mottle = 1 + SCORCH_MOTTLE * math.noise(x / 17, z / 17, (c.seed % 97) + 0.5)
			t = APRON_SCORCH * math.exp(-(rho - c.outerFrac) * SCORCH_FALLOFF) * mottle
		end
		if c.radius < DETAILED_RADIUS then
			t *= SMALL_SCORCH
		end
		best = math.max(best, t)
	end
	return math.clamp(best, 0, 1)
end

--- The checkerboard's per-tile colour for a stage with craters on it (Hub.tileRect's
--- `colorAt`), or nil for a stage with none -- which then keeps its flat pair. `dark` and
--- `light` are the stage's own untinted two-tone.
function CraterField.groundColorAt(stageId: number, dark: Color3, light: Color3): ((number, number) -> (string, string))?
	local craters = StageCraters.forStage(stageId)
	if #craters == 0 then
		return nil
	end
	local darkHex, lightHex = dark:ToHex(), light:ToHex()
	return function(x: number, z: number): (string, string)
		local t = scorchAt(craters, x, z)
		if t < 0.01 then
			return darkHex, lightHex
		end
		return dark:Lerp(SCORCH, t):ToHex(), light:Lerp(SCORCH, t):ToHex()
	end
end

return CraterField
