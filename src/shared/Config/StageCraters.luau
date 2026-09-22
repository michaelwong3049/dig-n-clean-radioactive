--!strict
--[[
	StageCraters.luau — the impact craters pocking Stage 6, The Crater.

	One big crater a little west and north of the stage's middle, and a scatter of small
	ones round it. Built by build/CraterField; DigService and Shared/Util/Spec read the
	same outlines from here, so the ground a rim covers and the ground no signal spawns
	on can never disagree.

	NOT THE DETONATION CRATERS. A nuke that goes off (Config/Detonation) leaves a
	runtime burn under Workspace.Craters that fades away. These are permanent world
	geometry, and they carry no rads of their own -- StageService only reads X/Z, so
	standing on a rim is standing in Stage 6 like anywhere else.

	A RAISED RIM ON LEVEL GROUND, NOT A PIT. There is no terrain here: every stage is one
	flat plate, and DigService buries against that plate's top face. So the floor of a
	crater IS the stage floor, at Stages.SURFACE_Y, and what makes it a crater is the
	berm thrown up round it -- a steep inner wall, a gentler outer flank, both walkable.
	Stood on the floor of the big one, the rim is well over head height all round, which
	is what a bowl feels like from the inside. (A real sunken pit was the alternative,
	turned down: the plate is only 16 studs thick, and every aura, haul and fuse would
	have had to learn a second floor height.)

	NOT A PERFECT RING. Each crater is an ellipse (`aspect`, turned by `yaw`), bent by a
	few low harmonics (`wobble`) so the outline swells and pinches, with its crest height
	bent the same way (`lift`) and one stretch of rim slumped low (`slump`). All of it is
	fixed numbers, not an rng, because DigService has to be able to ask "is this point
	under a rim" and get the same answer the builder built. The builder adds its own
	small per-vertex jitter on top; the dig margins below cover it.

	THE RIM IS SOLID, SO NOTHING SPAWNS UNDER IT. A nuke that surfaced inside the berm
	would be hidden by it, glow and all. `blocksDig` is the rule DigService checks: the
	whole footprint of a small crater, and the big crater's rim band. The big crater's
	floor stays open (`digFloor`), held off its own inner wall by DIG_FLOOR_MARGIN so
	even a GIGA roll (Config/Payload) has room to come up.

	UNITS. `center` is world {x, z}. `radius` is the crest's distance from the centre
	along the long axis, before any wobble; everything radial is then a fraction of the
	crest distance on that bearing (`rho`): `floorFrac` is where the inner wall meets the
	floor, `outerFrac` where the outer flank meets the plain. Bearings are degrees in the
	XZ plane, atan2(dz, dx).
]]

export type Harmonic = { number } -- { k, amplitude, phase in degrees }

export type Crater = {
	name: string,
	stageId: number,
	center: { number },
	radius: number,
	aspect: number, -- long axis / short axis
	yaw: number, -- bearing of the long axis
	height: number, -- mean crest height above the floor, before `lift` and `slump`
	wobble: { Harmonic }, -- on the crest distance, bearing measured from `yaw`
	lift: { Harmonic }, -- on the crest height, bearing measured from `yaw`
	slump: { bearing: number, width: number, depth: number }?, -- width in degrees; depth 0..1 of the height lost
	floorFrac: number,
	outerFrac: number,
	digFloor: boolean,
	segments: number, -- facets round the rim
	seed: number, -- the builder's jitter
	vents: number?, -- smoking cracks in the rim (build/CraterField); none if nil
}

local StageCraters = {}

--- How far inside the floor's edge (in rho) a signal must sit on a `digFloor` crater. On
--- the big crater that is 3-4 studs of floor between the nearest dig and the foot of the
--- inner wall, and the wall climbs gently for its first few studs -- room for the haul
--- to rise without clipping the slope.
StageCraters.DIG_FLOOR_MARGIN = 0.1

--- How far past the outer foot (in rho) the no-dig ring reaches. Covers the builder's
--- vertex jitter and the rubble thrown down the flank.
StageCraters.DIG_OUTER_MARGIN = 0.04

StageCraters.DEFS = {
	-- THE crater. Stage 6's middle is (1695, 0); this sits 22 west and 17 north of it, so
	-- it reads as the stage's centrepiece without being dead centre. The entrance path
	-- (z = 0, from the Stage 5 seam) runs into its west flank, and the slump faces that
	-- way: coming in from Stage 5, the low stretch of rim is the first thing you see, and
	-- the floor shows through it before you have climbed anything.
	{
		name = "GreatCrater",
		stageId = 6,
		center = { 1673, 17 },
		radius = 38,
		aspect = 1.24,
		yaw = 22,
		height = 7.5,
		wobble = { { 2, 0.05, 40 }, { 3, 0.07, 170 }, { 5, 0.035, 300 }, { 7, 0.02, 80 } },
		lift = { { 2, 0.12, 10 }, { 3, 0.1, 250 }, { 4, 0.08, 130 } },
		slump = { bearing = 205, width = 70, depth = 0.55 },
		floorFrac = 0.66,
		outerFrac = 1.36,
		digFloor = true,
		segments = 48,
		seed = 6001,
		vents = 5,
	},
	-- The small ones. Placed by hand, not dealt: spread down the whole walk (west edge to
	-- the camp gate) and across both halves of the corridor, clear of the big crater's
	-- flank, clear of the Stage 5 seam and the Toxic Twilight gate, and never two
	-- the same size or shape. Spec pins the clearances.
	{
		name = "Pock1",
		stageId = 6,
		center = { 1583, -50 },
		radius = 6.5,
		aspect = 1.15,
		yaw = 60,
		height = 1.8,
		wobble = { { 2, 0.06, 90 }, { 3, 0.08, 200 } },
		lift = { { 2, 0.2, 30 }, { 3, 0.15, 160 } },
		slump = nil,
		floorFrac = 0.6,
		outerFrac = 1.42,
		digFloor = false,
		segments = 12,
		seed = 6101,
	},
	{
		name = "Pock2",
		stageId = 6,
		center = { 1597, 55 },
		radius = 5,
		aspect = 1.1,
		yaw = 140,
		height = 1.4,
		wobble = { { 2, 0.05, 10 }, { 3, 0.09, 120 } },
		lift = { { 2, 0.18, 200 }, { 3, 0.2, 60 } },
		slump = nil,
		floorFrac = 0.6,
		outerFrac = 1.42,
		digFloor = false,
		segments = 12,
		seed = 6102,
	},
	{
		name = "Pock3",
		stageId = 6,
		center = { 1650, -62 },
		radius = 10,
		aspect = 1.2,
		yaw = 10,
		height = 2.6,
		wobble = { { 2, 0.05, 250 }, { 3, 0.07, 20 }, { 5, 0.03, 140 } },
		lift = { { 2, 0.15, 90 }, { 3, 0.12, 300 } },
		slump = { bearing = 40, width = 60, depth = 0.5 },
		floorFrac = 0.62,
		outerFrac = 1.4,
		digFloor = false,
		segments = 16,
		seed = 6103,
		vents = 1,
	},
	{
		name = "Pock4",
		stageId = 6,
		center = { 1743, -36 },
		radius = 11.5,
		aspect = 1.3,
		yaw = 115,
		height = 3,
		wobble = { { 2, 0.04, 70 }, { 3, 0.08, 310 }, { 4, 0.04, 180 } },
		lift = { { 2, 0.14, 260 }, { 3, 0.12, 40 } },
		slump = { bearing = 300, width = 55, depth = 0.45 },
		floorFrac = 0.62,
		outerFrac = 1.4,
		digFloor = false,
		segments = 18,
		seed = 6104,
		vents = 1,
	},
	{
		name = "Pock5",
		stageId = 6,
		center = { 1765, 52 },
		radius = 8.5,
		aspect = 1.18,
		yaw = 35,
		height = 2.2,
		wobble = { { 2, 0.06, 160 }, { 3, 0.07, 80 } },
		lift = { { 2, 0.16, 120 }, { 3, 0.14, 350 } },
		slump = nil,
		floorFrac = 0.6,
		outerFrac = 1.42,
		digFloor = false,
		segments = 14,
		seed = 6105,
	},
	{
		name = "Pock6",
		stageId = 6,
		center = { 1803, -60 },
		radius = 6,
		aspect = 1.12,
		yaw = 160,
		height = 1.6,
		wobble = { { 2, 0.05, 300 }, { 3, 0.08, 45 } },
		lift = { { 2, 0.2, 75 }, { 3, 0.15, 210 } },
		slump = nil,
		floorFrac = 0.6,
		outerFrac = 1.42,
		digFloor = false,
		segments = 12,
		seed = 6106,
	},
	{
		name = "Pock7",
		stageId = 6,
		center = { 1791, 14 },
		radius = 7,
		aspect = 1.2,
		yaw = 80,
		height = 1.9,
		wobble = { { 2, 0.05, 130 }, { 3, 0.08, 270 } },
		lift = { { 2, 0.18, 330 }, { 3, 0.14, 100 } },
		slump = nil,
		floorFrac = 0.6,
		outerFrac = 1.42,
		digFloor = false,
		segments = 12,
		seed = 6107,
	},
	{
		name = "Pock8",
		stageId = 6,
		center = { 1735, 66 },
		radius = 5.5,
		aspect = 1.1,
		yaw = 5,
		height = 1.5,
		wobble = { { 2, 0.06, 220 }, { 3, 0.07, 15 } },
		lift = { { 2, 0.16, 280 }, { 3, 0.18, 150 } },
		slump = nil,
		floorFrac = 0.6,
		outerFrac = 1.42,
		digFloor = false,
		segments = 12,
		seed = 6108,
	},
} :: { Crater }

local byStage: { [number]: { Crater } } = {}
for _, def in StageCraters.DEFS do
	local list = byStage[def.stageId]
	if list == nil then
		list = {}
		byStage[def.stageId] = list
	end
	table.insert(list, def)
end

local NONE: { Crater } = {}

--- Every crater on a stage (empty for a stage with none).
function StageCraters.forStage(stageId: number): { Crater }
	return byStage[stageId] or NONE
end

local function harmonics(list: { Harmonic }, t: number): number
	local sum = 0
	for _, h in list do
		sum += h[2] * math.cos(h[1] * t + math.rad(h[3]))
	end
	return sum
end

--- The signed difference between two bearings, in (-180, 180].
local function angleDiff(a: number, b: number): number
	return (a - b + 180) % 360 - 180
end

--- Crest distance from the centre along a world bearing (degrees): the ellipse, bent by
--- `wobble`.
function StageCraters.crestRadius(c: Crater, bearing: number): number
	local t = math.rad(bearing - c.yaw)
	local a = c.radius
	local b = c.radius / c.aspect
	local ellipse = (a * b) / math.sqrt((b * math.cos(t)) ^ 2 + (a * math.sin(t)) ^ 2)
	return ellipse * (1 + harmonics(c.wobble, t))
end

--- Crest height above the floor along a world bearing: `height`, bent by `lift`, with
--- the slumped stretch eased down on a cosine so it has no hard ends.
function StageCraters.crestHeight(c: Crater, bearing: number): number
	local t = math.rad(bearing - c.yaw)
	local h = c.height * (1 + harmonics(c.lift, t))
	local slump = c.slump
	if slump then
		local u = math.abs(angleDiff(bearing, slump.bearing)) / (slump.width / 2)
		if u < 1 then
			h *= 1 - slump.depth * (0.5 + 0.5 * math.cos(math.pi * u))
		end
	end
	return h
end

--- Where a world point sits relative to one crater: its distance from the centre as a
--- fraction of the crest distance on that bearing (0 = centre, 1 = crest), and that
--- bearing.
function StageCraters.rho(c: Crater, x: number, z: number): (number, number)
	local dx, dz = x - c.center[1], z - c.center[2]
	local bearing = math.deg(math.atan2(dz, dx))
	return math.sqrt(dx * dx + dz * dz) / StageCraters.crestRadius(c, bearing), bearing
end

--- The farthest the crater reaches from its centre on any bearing: the outer foot at
--- its widest. What clearance checks (Spec) measure against.
function StageCraters.reach(c: Crater): number
	local best = 0
	for step = 0, 359 do
		best = math.max(best, StageCraters.crestRadius(c, step) * c.outerFrac)
	end
	return best
end

--- True where no signal may spawn: under any rim on this stage, or anywhere inside a
--- crater whose floor is closed to digging. DigService's spawn loop re-rolls on true.
function StageCraters.blocksDig(stageId: number, x: number, z: number): boolean
	for _, c in StageCraters.forStage(stageId) do
		local rho = StageCraters.rho(c, x, z)
		if rho < c.outerFrac + StageCraters.DIG_OUTER_MARGIN then
			if not c.digFloor or rho > c.floorFrac - StageCraters.DIG_FLOOR_MARGIN then
				return true
			end
		end
	end
	return false
end

return StageCraters
