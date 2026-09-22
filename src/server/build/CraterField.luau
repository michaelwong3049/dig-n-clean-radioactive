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
	the plain.

	TRIANGLES, NOT A RING OF BLOCKS. A berm of boxes, one per step round the circle,
	steps wherever two neighbours' heights differ and gaps on the outside of the curve.
	Every facet here is a true triangle between shared vertices, built from two
	WedgeParts (`triangle`), so the surface is continuous: no steps, no gaps, and the
	crest can rise and fall smoothly all the way round. The facets are the low-poly look.

	SOLID RIM, WALK-THROUGH EVERYTHING ELSE. The facets collide: you climb up and over, so
	a crater is ground you cross, not a sticker on it. Rubble and rays are CanCollide
	false like the rest of build/Scenery, and all of them sit where
	StageCraters.blocksDig already keeps signals out, so nothing here can hide an aura.
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
}

local function paletteFor(stageId: number): Palette
	local base = Color3.fromHex(Stages.get(stageId).color)
	return {
		outer = base:Lerp(ASH, 0.3),
		inner = base:Lerp(SCORCH, 0.5),
		rubble = { base:Lerp(ASH, 0.42), base:Lerp(ASH, 0.25), base:Lerp(SCORCH, 0.35) },
		ray = base:Lerp(SCORCH, 0.5),
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

local function wedge(parent: Instance, cf: CFrame, size: Vector3, color: Color3)
	local w = Instance.new("WedgePart")
	w.Name = "Rim"
	w.Anchored = true
	w.CanTouch = false
	w.Material = Enum.Material.SmoothPlastic
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
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, color: Color3)
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
	local sink = normal * (-RIM_THICKNESS / 2)

	wedge(parent, CFrame.fromMatrix((a + b) / 2 + sink, right, up, back), Vector3.new(RIM_THICKNESS, height, math.abs(ab:Dot(back))), color)
	wedge(parent, CFrame.fromMatrix((a + c) / 2 + sink, -right, up, -back), Vector3.new(RIM_THICKNESS, height, math.abs(ac:Dot(back))), color)
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
local function buildRim(parent: Instance, c: Crater, profile: { { number } }, groundY: number, rng: Random, palette: Palette)
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
				triangle(parent, a, b, cc, color)
				triangle(parent, a, cc, d, color)
			else
				triangle(parent, a, b, d, color)
				triangle(parent, b, cc, d, color)
			end
		end
	end
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
		buildRim(model, c, profile, groundY, rng, palette)
		buildRubble(model, c, profile, groundY, rng, palette)
		if c.radius >= DETAILED_RADIUS then
			buildRays(model, c, groundY, rng, palette)
		end
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
