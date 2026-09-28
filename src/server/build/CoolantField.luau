--!strict
--[[
	CoolantField.luau — the reactor's coolant drainage on Stage 5, and the crust it
	left behind when it dried.

	    called from build/Scenery's buildStageScenery (Stage 5, the only pass that field has)

	WHY THIS FIELD GETS CHANNELS AND NOT PUDDLES. What you dig out of Reactor Grounds
	is fuel rods, cooling valve wheels, core samples, sealed casings and a black-box
	recorder (Config/Items) — so this ground is the plant site itself, and the magenta
	is LEAKED COOLANT: it runs in a direction, and where it stopped running it dried into
	crust. Stage 4 next door owns round ooze pools (build/OozeMarsh); re-using them here
	would make two neighbouring fields rhyme. It is also the one colour out here that
	survives the sky — Stage 5's air is yellow-green (Config/Sky), which pushes the pale
	pink floor and any grey concrete sallow.

	THE NETWORK, built like a drain is built:

	  * A TRUNK down the north side of the walk and a COLLECTOR down the south side, each
	    in precast units: a concrete bed, two kerbs, a paler coping along each kerb's
	    crown, and a hairline joint between units.
	  * SPURS off both, reaching out to the north and south edges and in toward the walk
	    lane. Every spur ends in an OUTFALL — an apron slab between splayed wingwalls —
	    where the backed-up coolant pours over and runs out across the ground.
	  * An INSPECTION CHAMBER at every bend, every junction and where a run leaves the
	    plate: a square concrete box with a steel grate, coolant standing under it. The
	    chambers are also what make the network precise: a run's kerbs stop at a chamber
	    wall, so no two runs ever meet as overlapping boxes or an open mitre.
	  * ONE CROSSING of the walk lane, under a culvert: a deck on filled sides with ramps,
	    headwalls with a parapet at each end and the dark of the bore under them. A shut-off
	    valve stands on the chamber where that crossing leaves the trunk.
	  * Where a run has FAILED, its kerb on the walk side has cracked and tipped out, the
	    coping lies in the mud, and the coolant pours through the gap.

	THE CRUST — pale mineral rings where a spill stood and evaporated, spread EVENLY over
	the open plate (best-candidate, off a size ladder), plus fringes along the kerbs and
	collars round every spill, so the two passes read as one substance.

	THE LAYOUT IS AUTHORED, NOT ROLLED (the call Config/StageCraters makes for Stage 6): a
	network you can follow end to end is what this field gives a player to navigate by.
	TRUNK/SOUTH/SPURS are fixed plate-local studs; the seed only rolls detail on top.

	ITS OWN SEED, TWICE OVER: one Random for the network, one for the crust, so retuning
	the crust cannot move a kerb. Never the stage rng.

	LOW AND WALK-THROUGH, BECAUSE THIS IS DUG GROUND. Every part is CanCollide, CanQuery
	and CanTouch false, and nothing out here is tall enough to hide a haul surfacing
	beside it: the kerb crown is 1.2 (between Stage 3's rubble at 1.23 and its rebar at
	1.91, both over a dig plate unhandled), a chamber 1.5, the culvert deck 1.5. The
	valve is the one thin thing that stands higher.

	THE Y BAND, over the checkerboard cap (`groundY`, already Stages.SURFACE_Y +
	GROUND_SKIM when it arrives here):

	    crust rings / fringes   +0.012 .. +0.024   (under everything)
	    concrete bed            +0.02
	    dry stretch's stain     +0.05
	    spilt coolant on ground +0.09 .. +0.105    = build/OozeMarsh's POOL_TOP
	    coolant IN a channel    +0.82              = CHANNEL_FILL_TOP (backed up; a
	                                                 surface lower is hidden by the kerb
	                                                 from standing height)
	    kerb crown              +1.20              = KERB_H + COPING_H
	    chamber / culvert deck  +1.50

	THE WALK LANE. Nothing that stands crosses z = 0 except the culvert, which is the
	crossing. The crust ignores the lane: a flat layer you walk over does not block it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)

local Kit = require(script.Parent.Kit)

local CoolantField = {}

--- 8400 is build/FieldLitter's. The network and the crust take SEED and SEED + 1.
local SEED = 8600

-- ── The skeleton ───────────────────────────────────────────────────────────────
-- Plate-local studs, x along the field's length and z across it (290 x 170 -> x +-145,
-- z +-85).

--- The trunk, west to east. It BENDS a few degrees at each vertex, because a drain
--- follows the grade it was cut into and a ruler-straight 270-stud line reads as a
--- ruler. Held north of the walk lane the whole way: the spine you walk alongside.
--- Both ends stop at a chamber against the wall -- the drain carries on under it.
local TRUNK: { { number } } = {
	{ -137, 44 },
	{ -72, 38 },
	{ 0, 43 },
	{ 74, 36 },
	{ 137, 41 },
}

--- The collector down the south side. Its west end leaves the plate at a chamber like
--- the trunk's; its east end is an OUTFALL -- the bottom of the system, where it fails.
local SOUTH: { { number } } = {
	{ -137, -42 },
	{ -58, -49 },
	{ 16, -44 },
	{ 92, -51 },
	{ 126, -47 },
}

--- The spurs, each attached to a point ON a run (`from`, `leg` + `t` along it, so a
--- spur can never drift off the run it branches from) and ending in an outfall at `to`.
--- They alternate out to the plate's north and south strips and in toward the walk, so
--- the whole width of the field has the network in it, not just two bands.
---
--- `crosses` is the one that does not end in an outfall: it runs over the walk lane
--- under the culvert and JOINS the collector at one of its vertices (16, -44). One
--- crossing, not four -- a crossing is a landmark when there is one of them.
local SPURS: { { from: string, leg: number, t: number, to: { number }, crosses: boolean? } } = {
	{ from = "trunk", leg = 1, t = 0.45, to = { -118, 70 } },
	{ from = "trunk", leg = 2, t = 0.45, to = { -46, 22 } },
	{ from = "trunk", leg = 3, t = 0.2, to = { 16, -44 }, crosses = true },
	{ from = "trunk", leg = 3, t = 0.7, to = { 60, 71 } },
	{ from = "trunk", leg = 4, t = 0.4, to = { 110, 22 } },
	{ from = "south", leg = 1, t = 0.55, to = { -100, -72 } },
	{ from = "south", leg = 2, t = 0.4, to = { -24, -22 } },
	{ from = "south", leg = 3, t = 0.6, to = { 54, -73 } },
}

--- Failures mid-run, as (leg, t) on the AUTHORED polyline. Deliberately not near the
--- ends: a run that fails in the middle of its length reads as failure.
local TRUNK_BREAKS: { { leg: number, t: number } } = {
	{ leg = 2, t = 0.8 },
}
local SOUTH_BREAKS: { { leg: number, t: number } } = {}

--- Half-width of the open walk lane down z = 0 (build/BiomeKit's LANE_HALF).
local LANE_HALF = 16

--- Kept this far inside the plate's own edges.
local EDGE_MARGIN = 8

--- The flat spills may run closer to the edge than anything standing.
local SPILL_MARGIN = 4

-- ── The channel section ────────────────────────────────────────────────────────

--- Inside width, kerb thickness, kerb body height and the coping on top of it. The
--- crown (KERB_H + COPING_H) is 1.2, the height the header argues for.
local CHANNEL_W = 4.0
local KERB_W = 1.1
local KERB_H = 1.06
local COPING_H = 0.14
--- The coping overhangs the kerb by this each side: the lip that makes it read precast.
local COPING_LIP = 0.1
--- The bed's footing shows this far outside each kerb.
local APRON = 0.45

--- Nominal length of one precast unit. Each leg is divided into a whole number of
--- equal units. Beds are grown by SEG_OVERLAP (no floor showing between them); kerbs
--- and coping are SHORTENED by JOINT, which is the hairline between units.
local SEG_LEN = 10
local SEG_OVERLAP = 0.06
local JOINT = 0.16

local BED_TOP = 0.02
local BED_THICK = 0.1
local COOLANT_TOP = 0.09
local COOLANT_THICK = 0.12
local STAIN_TOP = 0.05

--- THE CHANNELS RUN NEAR-BRIMMING. Shot live on the first version: with the liquid down
--- at COOLANT_TOP, the kerb hid it completely from standing height and the field lost
--- its colour. A backed-up drain sits high, just under the lip where a grazing angle
--- catches it -- and a blocked system under head is why it bursts.
local CHANNEL_FILL_TOP = 0.82

--- Share of kerb units that have lost their coping (lying beside them). Low: decay
--- under the eye, not failure.
local KERB_DAMAGE_CHANCE = 0.1

--- Wet/dry as a two-state walk down each run, so wet stretches are CONTIGUOUS (a
--- per-unit coin flip gives a dashed line, which reads as a rendering fault).
local DRY_START_CHANCE = 0.1
local WET_RESUME_CHANCE = 0.24

-- ── Chambers, outfalls, culvert ────────────────────────────────────────────────

--- The inspection chamber: outside size, wall thickness, height, grate bar count. Wide
--- enough that a run arriving at up to ~25 degrees off square still enters through a
--- wall, and the kerbs stop CHAMBER_TRIM short of its centre so they end inside it.
local CHAMBER = CHANNEL_W + 2 * KERB_W + 2.4
local CHAMBER_WALL = 0.9
local CHAMBER_H = 1.5
local CHAMBER_TRIM = CHAMBER / 2 - 0.3
local GRATE_BARS = 9

--- The outfall: apron slab length, and the wingwalls' length and splay.
local OUTFALL_APRON = 5
local WING_LEN = 3.2
local WING_SPLAY = 35

--- The culvert. The deck covers the full width of the walk lane (DECK_HALF each side of
--- z = 0) so a player walking the route meets one crossing, never a kerb. DECK_SPAN is
--- its width across the lane. Headwalls stand HEAD_T thick at each end with a parapet
--- PARAPET over the deck, and the filled sides slope down to the ground over RAMP_RUN.
local DECK_HALF = LANE_HALF
local DECK_SPAN = 14
local DECK_TOP = 1.5
local DECK_THICK = 0.35
local HEAD_T = 0.9
local PARAPET = 0.3
local RAMP_RUN = 3

-- ── Crust ──────────────────────────────────────────────────────────────────────

--- The field-wide rings, as a size ladder (full length of a ring's rim oval), dealt
--- best-candidate so they spread evenly instead of clumping where a grid cell happened
--- to win its roll.
local CRUST_LADDER: { { n: number, a: { number } } } = {
	{ n = 6, a = { 10, 13 } },
	{ n = 10, a = { 7, 10 } },
	{ n = 14, a = { 4, 7 } },
}
local CRUST_CANDIDATES = 24

--- A ring closer than this (plus a share of its own size) to a channel centreline is
--- not placed -- the kerb fringes already cover that ground.
local CRUST_CHANNEL_CLEAR = 9

--- Ring heights. Four stacked ovals at CRUST_STEP apart top out at +0.048 over the cap:
--- under the liquid, the border strip and a detector spot's cracks.
local CRUST_BASE = 0.012
local CRUST_STEP = 0.004
local CRUST_THICK = 0.04

--- Share of rings that still have liquid in the middle.
local CRUST_EYE_SHARE = 0.3

--- Per-side chance a wet unit grows a crust fringe outside its kerb, and its reach.
local FRINGE_CHANCE = 0.55
local FRINGE_REACH = 2.6

-- ── Colour ─────────────────────────────────────────────────────────────────────

--- The chalk a dried coolant rim leaves, and the pan inside it.
---
--- A LOW LERP, AND THE FLOOR IS WHY. build/FieldLitter learned this on Stage 3 the
--- expensive way: its dust started at 0.4 toward cream and read as spilled paint from
--- across the field, because that stage's ground was light khaki already. Stage 5's
--- floor is LIGHTER still (FFB6C1), so the margin here is thinner again — the crust
--- has to be a shade the ground could plausibly have turned, not a new colour laid on
--- top of it. Anything approaching white stops being mineral and starts being spill.
local CHALK = Color3.fromHex("EAE2EC")
local CHALK_MIX = 0.25

--- The pan floor inside a ring: the stage's own colour pushed slightly darker and
--- greyer, the ground as it looks after something stood on it for a long time.
local PAN = Color3.fromHex("6E5A63")
local PAN_MIX = 0.22

--- Concrete, lifted straight from build/FieldLitter's rubble so the bed out here and
--- the broken slabs on Stage 3 are the same material. Cool rather than warm, which
--- matters more on this field than on that one: Stage 5's light is yellow-green, and a
--- warm grey under it goes straight to mud.
local CONCRETE = { Color3.fromHex("8E8894"), Color3.fromHex("77727E") }
--- The precast coping along a kerb's crown and the apron slabs: a shade paler than the
--- kerb body, so the lip catches the light as its own edge.
local COPING = Color3.fromHex("A39EAA")
--- Grates, frames and the valve: dark steel, matte-ish Metal.
local STEEL = Color3.fromHex("4C525A")
local STEEL_DARK = Color3.fromHex("30343A")
local VALVE_RED = Color3.fromHex("A8392C")
--- The dark inside a culvert's bore.
local BORE = Color3.fromHex("1E1B22")

type Palette = {
	coolant: Color3,
	coolantHex: string,
	glowHex: string,
	stain: Color3,
	stainDeep: Color3,
	chalk: Color3,
	pan: Color3,
	concrete: { Color3 },
}

--- Everything derives from the stage's own `color` / `ooze` triple, so this file is not
--- hardcoded to Stage 5 even though only Stage 5 calls it.
---
--- `ooze.deep` FINALLY HAS A CALLER. build/Scenery's pool section notes that the triple's
--- third-from-bright slot went unused the moment the old pool rims came off — "there is
--- nothing dark left anywhere in this field for it to paint". A dried tide line is
--- exactly the thing it was mixed for. It is lerped toward the floor rather than used
--- neat, because neat 7A0F45 on light pink is a black ring, and a stain is a stain, not
--- an outline.
local function paletteFor(stageId: number): Palette
	local def = Stages.get(stageId)
	local base = Color3.fromHex(def.color)
	local deep = Color3.fromHex(def.ooze.deep)
	return {
		coolant = Color3.fromHex(def.ooze.bright),
		coolantHex = def.ooze.bright,
		glowHex = def.ooze.glow,
		-- 0.68, NOT 0.58: at the lower mix the tide line read as a drawn pink band rather
		-- than as a mark on the ground, which is half of what made the first rings look
		-- like targets. The other half was their shape -- see crustRing.
		stain = deep:Lerp(base, 0.68),
		stainDeep = deep:Lerp(base, 0.3),
		chalk = base:Lerp(CHALK, CHALK_MIX),
		pan = base:Lerp(PAN, PAN_MIX),
		concrete = CONCRETE,
	}
end

-- ── Parts ──────────────────────────────────────────────────────────────────────

--- Same part contract as build/FieldLitter's `block`, and for the same reasons: nothing
--- on a dig plate collides, answers a raycast or casts a shadow. Studs only render on
--- Plastic, which is why the concrete asks for the material it does.
local function block(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, studded: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if studded then
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

--- A flat oval lying on the ground.
---
--- SpecialMesh + MeshType.Sphere, NOT a Cylinder or a Ball part — build/Scenery's
--- `oozeDisc` documents at length why those two silently render a circle whatever
--- unequal Size you hand them, and every oval in this file would be a plain circle if
--- it went that way. Colour and material live on the part; the mesh has neither.
local function disc(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	z: number,
	a: number,
	b: number,
	yaw: number,
	color: Color3,
	thick: number,
	neon: boolean?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = Vector3.one
	p.CFrame = CFrame.new(x, y - thick / 2, z) * CFrame.Angles(0, math.rad(yaw), 0)
	p.Color = color
	-- The one named Neon exception in this world is the ooze, and this is the same
	-- substance — see build/Scenery's POOL_MATERIAL note. Everything else here is matte.
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(a, thick, b)
	mesh.Parent = p

	p.Parent = parent
	return p
end

-- ── The skeleton, resolved ─────────────────────────────────────────────────────

--- The box every loose piece is held inside: the plate less SPILL_MARGIN, so a tongue
--- can reach the edge of the field without any of it hanging over a border strip.
type Bounds = { minX: number, minZ: number, maxX: number, maxZ: number }

--- A part's Y rotation such that its LOCAL X runs from `ax, az` toward `bx, bz`.
--- CFrame.Angles(0, t, 0) sends local X to (cos t, 0, -sin t), hence the negated dz.
local function yawAlong(ax: number, az: number, bx: number, bz: number): number
	return math.atan2(-(bz - az), bx - ax)
end

--- The point `t` of the way along leg `leg` of a polyline (1-based, `t` in 0..1).
local function pointOn(points: { Vector3 }, leg: number, t: number): Vector3
	local a, b = points[leg], points[leg + 1]
	return a:Lerp(b, t)
end

--- Shortest distance from a point to a polyline, used to hold the scattered crust rings
--- off the channels.
local function distToPolyline(points: { Vector3 }, x: number, z: number): number
	local best = math.huge
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local dx, dz = b.X - a.X, b.Z - a.Z
		local len2 = dx * dx + dz * dz
		local t = if len2 > 0 then math.clamp(((x - a.X) * dx + (z - a.Z) * dz) / len2, 0, 1) else 0
		local px, pz = a.X + dx * t, a.Z + dz * t
		best = math.min(best, math.sqrt((x - px) ^ 2 + (z - pz) ^ 2))
	end
	return best
end

-- ── Crust ──────────────────────────────────────────────────────────────────────

--- The distance from an ellipse's centre to its edge on a world bearing, for an
--- ellipse of full width `a` by `b` turned by `yaw`. Lobes hang off this.
local function ellipseEdge(a: number, b: number, yaw: number, bearing: number): number
	local t = math.rad(bearing - yaw)
	local ca, sa = math.cos(t) / (a / 2), math.sin(t) / (b / 2)
	return 1 / math.sqrt(ca * ca + sa * sa)
end

--- One dried pool: a pale chalk rim, the tide line inside it, the pan it left, and --
--- for the few that have not finished drying -- a shrunken eye of coolant in it.
---
--- BUILT OUTSIDE IN, each band smaller and a hundredth of a stud higher than the last.
--- That stack IS the ring: there is no annulus primitive here, and the ascending Y is
--- what stops the renderer having to break a coplanar tie four ways, which it does
--- badly and differently every frame.
---
--- NOT CONCENTRIC, AND THAT IS THE WHOLE SHAPE. Shot live on the built field, the first
--- version of this read as a BULLSEYE -- four ellipses on one centre with one aspect
--- and one yaw, which the eye resolves as a painted target long before it resolves as
--- crud on the ground. The fix is not contrast, it is eccentricity: a real pan drains
--- toward its own low corner, so every band inside the rim is shifted that way (`low`),
--- carries its own yaw and its own aspect, and the rim itself is broken by a lobe or two
--- near its poles so the outline is not an ellipse at all. The rim ends up thick on the
--- high side and thin on the low one, which is exactly what a tide mark looks like.
---
--- THE LOBES GO NEAR THE POLES, SHORT OF TANGENT. Dropped at a bearing near the waist
--- they widen the middle, which cancels the body's own elongation back toward a circle
--- -- Stage 4's old single-oval pools had the full measured argument for this, and it cost that
--- file two passes to find. Same rule here, same reason.
local function crustRing(parent: Instance, x: number, z: number, groundY: number, size: number, rng: Random, palette: Palette)
	local a = size
	local b = a / rng:NextNumber(1.05, 1.6)
	local yaw = rng:NextNumber(0, 360)
	local y = groundY + CRUST_BASE

	-- The side the pan drained to. Every band inside the rim walks this way, and the
	-- eye ends up sitting in it.
	local low = yaw + rng:NextNumber(-70, 70)
	local lx, lz = math.cos(math.rad(low)), math.sin(math.rad(low))

	disc(parent, "CrustRim", x, y, z, a, b, yaw, palette.chalk, CRUST_THICK)
	for i = 1, rng:NextInteger(1, 2) do
		local pole = if i % 2 == 1 then yaw else yaw + 180
		local bearing = pole + rng:NextNumber(-22, 22)
		local la = a * rng:NextNumber(0.3, 0.52)
		local lb = la / rng:NextNumber(1.2, 2.0)
		local reach = (ellipseEdge(a, b, yaw, bearing) - la / 2) * rng:NextNumber(0.5, 0.95)
		disc(
			parent,
			"CrustRim",
			x + math.cos(math.rad(bearing)) * reach,
			y,
			z + math.sin(math.rad(bearing)) * reach,
			la,
			lb,
			bearing + rng:NextNumber(-20, 20),
			palette.chalk,
			CRUST_THICK
		)
	end

	local tideShift = a * rng:NextNumber(0.07, 0.15)
	local tideA = a * rng:NextNumber(0.72, 0.84)
	disc(
		parent,
		"CrustTide",
		x + lx * tideShift,
		y + CRUST_STEP,
		z + lz * tideShift,
		tideA,
		tideA / rng:NextNumber(1.0, 1.7),
		yaw + rng:NextNumber(-25, 25),
		palette.stain,
		CRUST_THICK
	)

	-- THE PAN COVERS MOST OF THE TIDE, AND SITS WELL OFF ITS CENTRE. Second live shot:
	-- making the bands eccentric killed the bullseye but left a DONUT -- the tide still
	-- showed as a closed, even band all the way round, because the pan inside it was
	-- small and nearly on its centre. A real pan does not keep an even rim: it holds its
	-- heaviest mineral on the side the water sat longest and thins to nothing opposite.
	-- Pushing the pan out to 0.58-0.74 of the body and shifting it a further tenth of the
	-- width down the low side leaves the tide showing as a CRESCENT on the high side and
	-- closed nowhere.
	local panShift = tideShift + a * rng:NextNumber(0.1, 0.22)
	local panA = a * rng:NextNumber(0.58, 0.74)
	disc(
		parent,
		"CrustPan",
		x + lx * panShift,
		y + CRUST_STEP * 2,
		z + lz * panShift,
		panA,
		panA / rng:NextNumber(1.0, 1.8),
		yaw + rng:NextNumber(-40, 40),
		palette.pan,
		CRUST_THICK
	)

	if rng:NextNumber() < CRUST_EYE_SHARE then
		-- The remnant sits in the low corner, not in the middle -- a centred dot was half
		-- of what made the old version a target -- and it is elongated along the drain
		-- rather than round.
		local eyeShift = panShift + a * rng:NextNumber(0.04, 0.12)
		local eyeA = a * rng:NextNumber(0.1, 0.19)
		-- No light on an eye. One PointLight per dried puddle, thirty of them over the
		-- field, is the mistake build/Scenery's pool section already talks itself out of
		-- for the small spills: the ground under a two-stud remnant does not need its own
		-- halo, and thirty of them would light the whole plate flat.
		disc(
			parent,
			"CrustEye",
			x + lx * eyeShift,
			y + CRUST_STEP * 3,
			z + lz * eyeShift,
			eyeA,
			eyeA / rng:NextNumber(1.3, 2.4),
			low + rng:NextNumber(-30, 30),
			palette.coolant,
			CRUST_THICK,
			true
		)
	end
end

--- The crust hugging a kerb: a thin smear outside the channel where the liquid has been
--- over the edge and dried. Elongated ALONG the run, never across it, so it reads as
--- the channel's own tide mark and not as a puddle that happens to be next to one.
local function kerbFringe(
	parent: Instance,
	x: number,
	z: number,
	groundY: number,
	yaw: number,
	length: number,
	rng: Random,
	palette: Palette
)
	local a = length * rng:NextNumber(0.5, 0.9)
	local b = FRINGE_REACH * rng:NextNumber(0.6, 1.15)
	local deg = math.deg(yaw)
	disc(parent, "CrustFringe", x, groundY + CRUST_BASE, z, a, b, deg, palette.chalk, CRUST_THICK)
	disc(parent, "CrustFringeTide", x, groundY + CRUST_BASE + CRUST_STEP, z, a * 0.7, b * 0.62, deg, palette.stain, CRUST_THICK)
end

-- ── The break, and what comes out of it ────────────────────────────────────────

--- Where a run has failed: the liquid leaves the channel and spreads over open ground.
---
--- A TONGUE, NOT A PUDDLE. The ovals march AWAY from the break on one bearing, so the
--- spill has a direction and a head -- which is the whole difference between "it leaked
--- here" and "there is a pool here". Stage 4's puddles are the other read, on purpose
--- (see this file's header).
---
--- IT WIDENS AS IT GOES, IT DOES NOT TAPER. Shot live on the built field, the first
--- version put its biggest oval AT the break and shrank from there, which built a
--- keyhole: a fat round head with a tail hanging off it, reading as a paint splat
--- rather than as liquid. Liquid coming out of a broken kerb does the opposite -- it
--- leaves the gap narrow, spreads as it runs and POOLS at the far end where it stops.
--- `swell` is that curve, peaking around three quarters along and easing off at the
--- very end, and it is what makes the shape read as flow.
---
--- EVERY OVAL WANDERS OFF THE LINE, sideways as well as along it, and carries its own
--- aspect. Ovals that share a centreline and an aspect merge into one sausage however
--- many of them there are.
---
--- DROPLETS PAST THE HEAD, the same trick build/OozeMarsh throws off its pools: a
--- couple of detached specks past where the body stops break the outline, so the spill
--- ends in a spatter instead of a clean curve.
---
--- HELD INSIDE THE FIELD, ON A LIVE CHECK -- the same clamp build/OozeMarsh puts on
--- its thrown droplets, and needed here for the same reason: a tongue is placed
--- relative to the break it came out of and walks up to eighteen studs further on its
--- own bearing with nothing stopping it. The west spur's outfall is the one that
--- actually runs off the plate without this (it sits 9 studs from the west edge aiming
--- south-west, measured at ~1257 against a boundary of 1260). Clamped rather than
--- shortened, so every OTHER tongue keeps its full reach.
---
--- ONE LIGHT, ON THE HEAD. build/Scenery's pools carry a PointLight each because Neon
--- alone reads as bright rather than as lighting the ground around it, and the same
--- holds here -- but there are six breaks on this field against Stage 4's twelve pools,
--- and the light goes on the widest oval only, never on every piece of the tongue.
--- Shadows off, the same call every other light on a field makes.
local function spillTongue(
	parent: Instance,
	x: number,
	z: number,
	groundY: number,
	bearing: number,
	rng: Random,
	palette: Palette,
	bounds: Bounds
): (number, number, number)
	local reach = rng:NextNumber(11, 19)
	local count = rng:NextInteger(5, 7)
	local head: Part? = nil
	local headA = 0
	local cx, cz = x, z
	-- Across the flow, for the sideways wander.
	local px, pz = math.cos(math.rad(bearing + 90)), math.sin(math.rad(bearing + 90))

	for i = 1, count do
		-- Narrow at the break, widest about three quarters down, easing off at the end.
		local t = (i - 1) / math.max(1, count - 1)
		local swell = 0.32 + 0.68 * math.sin(math.min(t / 0.78, 1) * math.pi * 0.5)
		if t > 0.78 then
			swell *= 1 - (t - 0.78) * 1.1
		end
		local a = math.max(1.8, reach * 0.42 * swell * rng:NextNumber(0.86, 1.14))
		local b = a / rng:NextNumber(1.15, 2.6)
		local axis = bearing + rng:NextNumber(-34, 34)
		-- Held in by the collar's own reach, not just its centre: a tongue running at the
		-- wall had its collar poking up to four studs past the plate edge.
		local collar = a * 1.35 / 2
		cx = math.clamp(cx, bounds.minX + collar, bounds.maxX - collar)
		cz = math.clamp(cz, bounds.minZ + collar, bounds.maxZ - collar)

		-- The crust collar goes down FIRST and a touch wider, so every tongue is ringed
		-- by the same dried edge the scattered rings out in the field wear -- that shared
		-- fringe is what makes the two passes read as one substance.
		disc(parent, "SpillCrust", cx, groundY + CRUST_BASE, cz, a * 1.35, b * 1.45, axis, palette.chalk, CRUST_THICK)
		disc(parent, "SpillTide", cx, groundY + CRUST_BASE + CRUST_STEP, cz, a * 1.16, b * 1.24, axis, palette.stain, CRUST_THICK)

		local part = disc(
			parent,
			"Spill",
			cx,
			groundY + COOLANT_TOP + i * 0.0025,
			cz,
			a,
			b,
			axis,
			palette.coolant,
			COOLANT_THICK,
			true
		)
		if a > headA then
			head, headA = part, a
		end

		-- Well under half an oval per step, so the tongue is one body and not a string of
		-- beads (shot live at 0.55-0.85: every oval read as its own blob).
		local step = a * rng:NextNumber(0.34, 0.5)
		local drift = a * rng:NextNumber(-0.16, 0.16)
		cx = math.clamp(cx + math.cos(math.rad(bearing)) * step + px * drift, bounds.minX, bounds.maxX)
		cz = math.clamp(cz + math.sin(math.rad(bearing)) * step + pz * drift, bounds.minZ, bounds.maxZ)
	end

	if head then
		Kit.liquidFx(parent, head.CFrame + Vector3.new(0, COOLANT_THICK / 2, 0), headA * 0.5, headA * 0.4, palette.coolantHex)
	end

	-- The spatter past the head.
	for _ = 1, rng:NextInteger(2, 4) do
		local throw = reach * rng:NextNumber(0.1, 0.42)
		local off = bearing + rng:NextNumber(-48, 48)
		local da = rng:NextNumber(0.7, 2.2)
		disc(
			parent,
			"SpillDrop",
			math.clamp(cx + math.cos(math.rad(off)) * throw, bounds.minX, bounds.maxX),
			groundY + COOLANT_TOP,
			math.clamp(cz + math.sin(math.rad(off)) * throw, bounds.minZ, bounds.maxZ),
			da,
			da / rng:NextNumber(1.0, 1.8),
			off,
			palette.coolant,
			COOLANT_THICK,
			true
		)
	end

	if head then
		Kit.light(head, palette.glowHex, math.clamp(reach * 1.4, 12, 30), math.clamp(reach * 0.08, 0.7, 1.6), false)
	end
	-- Where it ended up, and how far it ran: the crust scatter keeps clear of it.
	return (x + cx) / 2, (z + cz) / 2, reach * 0.75
end

-- ── Structures ─────────────────────────────────────────────────────────────────

local function metal(p: Part): Part
	p.Material = Enum.Material.Metal
	return p
end

--- A flat unit vector's yaw, in the same convention as yawAlong.
local function yawOf(ux: number, uz: number): number
	return math.atan2(-uz, ux)
end

--- An inspection chamber centred on `at`, turned by `yaw` (radians): a footing, four
--- studded concrete walls, a steel frame round the opening and a grate across it, and
--- the backed-up coolant standing under the bars.
local function chamber(parent: Instance, at: Vector3, yaw: number, groundY: number, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "Chamber"
	local F = CFrame.new(at.X, groundY, at.Z) * CFrame.Angles(0, yaw, 0)
	local half = CHAMBER / 2
	local inner = CHAMBER - 2 * CHAMBER_WALL

	block(model, "ChamberFooting", F * CFrame.new(0, BED_TOP - BED_THICK / 2, 0), Vector3.new(CHAMBER + 0.8, BED_THICK, CHAMBER + 0.8), palette.concrete[1], true)
	for side = -1, 1, 2 do
		block(model, "ChamberWall", F * CFrame.new(0, CHAMBER_H / 2, side * (half - CHAMBER_WALL / 2)), Vector3.new(CHAMBER, CHAMBER_H, CHAMBER_WALL), palette.concrete[2], true)
		block(model, "ChamberWall", F * CFrame.new(side * (half - CHAMBER_WALL / 2), CHAMBER_H / 2, 0), Vector3.new(CHAMBER_WALL, CHAMBER_H, inner), palette.concrete[2], true)
	end

	-- The frame sits on the walls' inner edge, the bars span it.
	local frameY = CHAMBER_H + 0.06
	for side = -1, 1, 2 do
		metal(block(model, "GrateFrame", F * CFrame.new(0, frameY, side * (inner / 2 + 0.05)), Vector3.new(inner + 0.5, 0.12, 0.4), STEEL))
		metal(block(model, "GrateFrame", F * CFrame.new(side * (inner / 2 + 0.05), frameY, 0), Vector3.new(0.4, 0.12, inner + 0.5), STEEL))
	end
	for i = 1, GRATE_BARS do
		local x = -inner / 2 + inner * i / (GRATE_BARS + 1)
		metal(block(model, "GrateBar", F * CFrame.new(x, CHAMBER_H - 0.04, 0), Vector3.new(0.16, 0.22, inner + 0.1), STEEL_DARK))
	end

	local liquid = block(model, "Coolant", F * CFrame.new(0, CHANNEL_FILL_TOP - COOLANT_THICK / 2, 0), Vector3.new(inner + 0.1, COOLANT_THICK, inner + 0.1), palette.coolant)
	liquid.Material = Enum.Material.Neon
	model.Parent = parent
	return F
end

--- The shut-off valve on a chamber's corner: a stem, a gearbox and a red hand wheel.
--- The dig table out here has cooling valve wheels in it; this is where they came off.
local function valve(parent: Instance, F: CFrame)
	local model = Instance.new("Model")
	model.Name = "Valve"
	local corner = F * CFrame.new(CHAMBER / 2 - CHAMBER_WALL / 2, CHAMBER_H, CHAMBER / 2 - CHAMBER_WALL / 2)
	metal(block(model, "ValveFlange", corner * CFrame.new(0, 0.06, 0), Vector3.new(0.8, 0.12, 0.8), STEEL_DARK))
	local stem = block(model, "ValveStem", corner * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(1.3, 0.3, 0.3), STEEL)
	stem.Shape = Enum.PartType.Cylinder
	metal(stem)
	metal(block(model, "ValveBox", corner * CFrame.new(0, 1.55, 0), Vector3.new(0.7, 0.5, 0.7), STEEL))
	local hub = corner * CFrame.new(0, 1.95, 0)
	local r = 0.85
	for k = 0, 7 do
		local th = math.rad(k * 45)
		local c = hub.Position + Vector3.new(math.cos(th) * r, 0, math.sin(th) * r)
		local tangent = Vector3.new(-math.sin(th), 0, math.cos(th))
		block(model, "WheelRim", CFrame.lookAt(c, c + tangent), Vector3.new(0.18, 0.18, 2 * math.pi * r / 8 + 0.08), VALVE_RED)
	end
	for _, a in { 0, 90 } do
		block(model, "WheelSpoke", hub * CFrame.Angles(0, math.rad(a), 0), Vector3.new(2 * r, 0.12, 0.12), VALVE_RED)
	end
	metal(block(model, "WheelHub", hub, Vector3.new(0.34, 0.26, 0.34), STEEL_DARK))
	model.Parent = parent
end

--- The end of a spur: an apron slab between wingwalls splayed off the kerbs, and the
--- coolant pouring over the lip of the channel onto it. Returns where the spill starts.
local function outfall(parent: Instance, E: Vector3, ux: number, uz: number, groundY: number, palette: Palette): Vector3
	local model = Instance.new("Model")
	model.Name = "Outfall"
	local nx, nz = -uz, ux
	local rot = CFrame.Angles(0, yawOf(ux, uz), 0)
	local halfKerb = (CHANNEL_W + KERB_W) / 2
	local bedW = CHANNEL_W + 2 * KERB_W

	local apronC = E + Vector3.new(ux, 0, uz) * (OUTFALL_APRON / 2)
	block(model, "Apron", CFrame.new(apronC.X, groundY + BED_TOP + 0.02 - BED_THICK / 2, apronC.Z) * rot, Vector3.new(OUTFALL_APRON, BED_THICK, bedW + 3.2), COPING, true)

	for side = -1, 1, 2 do
		local k = E + Vector3.new(nx, 0, nz) * (halfKerb * side)
		local splay = math.rad(WING_SPLAY)
		local w = Vector3.new(ux * math.cos(splay) + nx * side * math.sin(splay), 0, uz * math.cos(splay) + nz * side * math.sin(splay))
		local c = k + w * (WING_LEN / 2) + Vector3.new(0, groundY + (KERB_H + COPING_H) / 2, 0)
		-- A WedgePart is full height at its +Z face: lookAt points -Z outward, so the
		-- wing is full height against the kerb end and slopes down away from it.
		local wing = Instance.new("WedgePart")
		wing.Name = "Wingwall"
		wing.Anchored = true
		wing.CanCollide = false
		wing.CanQuery = false
		wing.CanTouch = false
		wing.CastShadow = false
		wing.Size = Vector3.new(KERB_W, KERB_H + COPING_H, WING_LEN)
		wing.CFrame = CFrame.lookAt(c, c + w)
		wing.Color = palette.concrete[2]
		wing.Material = Enum.Material.Plastic
		for _, face in { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" } do
			(wing :: any)[face] = Enum.SurfaceType.Studs
		end
		wing.Parent = model
	end

	-- The pour: a sheet from the channel's brim down to the apron's far end.
	local top = Vector3.new(E.X, groundY + CHANNEL_FILL_TOP - 0.06, E.Z)
	local bottom = Vector3.new(E.X + ux * (OUTFALL_APRON - 0.4), groundY + COOLANT_TOP + 0.03, E.Z + uz * (OUTFALL_APRON - 0.4))
	local pour = block(model, "Pour", CFrame.lookAt((top + bottom) / 2, bottom), Vector3.new(CHANNEL_W - 0.3, COOLANT_THICK, (bottom - top).Magnitude), palette.coolant)
	pour.Material = Enum.Material.Neon
	model.Parent = parent
	return Vector3.new(bottom.X, 0, bottom.Z)
end

--- The culvert where the crossing spur runs under the walk lane, built in the run's
--- own frame `C` (local X down the channel, centred on z = 0). `L` is the deck's length
--- along the channel. The channel's bed and coolant run straight through underneath
--- (buildRun lays them); this is the box, deck, fill, ramps and headwalls round them.
local function culvert(parent: Instance, C: CFrame, L: number, groundY: number, palette: Palette)
	local model = Instance.new("Model")
	model.Name = "Culvert"
	local F = C + Vector3.new(0, groundY, 0)
	local H0 = DECK_TOP - DECK_THICK
	local fillW = DECK_SPAN / 2 - CHANNEL_W / 2

	block(model, "CulvertDeck", F * CFrame.new(0, DECK_TOP - DECK_THICK / 2, 0), Vector3.new(L, DECK_THICK, DECK_SPAN), palette.concrete[1], true)
	for side = -1, 1, 2 do
		-- Filled sides under the deck, from the bore out to the deck's edge.
		block(model, "CulvertFill", F * CFrame.new(0, H0 / 2, side * (CHANNEL_W / 2 + fillW / 2)), Vector3.new(L, H0, fillW), palette.concrete[2], true)
		-- Ramps down to the ground off both long edges.
		local ramp = Instance.new("WedgePart")
		ramp.Name = "CulvertRamp"
		ramp.Anchored = true
		ramp.CanCollide = false
		ramp.CanQuery = false
		ramp.CanTouch = false
		ramp.CastShadow = false
		ramp.Size = Vector3.new(L + 2 * HEAD_T, DECK_TOP, RAMP_RUN)
		-- Full height at +Z, which has to face the deck.
		ramp.CFrame = F * CFrame.new(0, DECK_TOP / 2, side * (DECK_SPAN / 2 + RAMP_RUN / 2)) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0)
		ramp.Color = palette.concrete[1]
		ramp.Material = Enum.Material.Plastic
		ramp.TopSurface = Enum.SurfaceType.Studs
		ramp.Parent = model
		-- A hazard edge along the top of each long side.
		block(model, "DeckEdge", F * CFrame.new(0, DECK_TOP + 0.03, side * (DECK_SPAN / 2 - 0.3)), Vector3.new(L, 0.06, 0.5), Color3.fromHex(Kit.C.barrelYellow))
		local bands = math.floor(L / 3)
		for i = 1, bands do
			block(model, "DeckEdgeBand", F * CFrame.new(-L / 2 + (i - 0.5) * L / bands, DECK_TOP + 0.04, side * (DECK_SPAN / 2 - 0.3)), Vector3.new(0.6, 0.07, 0.52), Color3.fromHex(Kit.C.hazardBlack))
		end
	end

	-- The headwalls: a block either side of the bore and a lintel over it, standing a
	-- parapet above the deck. The bore itself reads dark behind the coolant.
	for e = -1, 1, 2 do
		local x = e * (L / 2 + HEAD_T / 2)
		for side = -1, 1, 2 do
			block(model, "Headwall", F * CFrame.new(x, (DECK_TOP + PARAPET) / 2, side * (CHANNEL_W / 2 + fillW / 2)), Vector3.new(HEAD_T, DECK_TOP + PARAPET, fillW), palette.concrete[2], true)
		end
		local lintelH = DECK_TOP + PARAPET - H0
		block(model, "Lintel", F * CFrame.new(x, H0 + lintelH / 2, 0), Vector3.new(HEAD_T, lintelH, CHANNEL_W + 0.02), palette.concrete[2], true)
		block(model, "HeadwallCap", F * CFrame.new(x, DECK_TOP + PARAPET + COPING_H / 2, 0), Vector3.new(HEAD_T + 2 * COPING_LIP, COPING_H, DECK_SPAN + 2 * COPING_LIP), COPING, true)
		local boreH = H0 - CHANNEL_FILL_TOP
		block(model, "Bore", F * CFrame.new(e * (L / 2 - 0.8), CHANNEL_FILL_TOP + boreH / 2, 0), Vector3.new(0.2, boreH, CHANNEL_W), BORE)
	end
	model.Parent = parent
end

-- ── The run ────────────────────────────────────────────────────────────────────

type Run = {
	points: { Vector3 }, -- world XZ, y unused
	chambers: { [number]: boolean }, -- vertices this run builds a chamber at
	trims: { [number]: boolean }, -- vertices whose chamber the kerbs stop short of
	breaks: { { leg: number, t: number } }, -- on THIS polyline
	culvertLeg: number?,
	outfall: boolean,
	valveAt: number?, -- vertex whose chamber carries the valve
}

--- Every run's legs with their chambers, units, breaks and outfall. Returns the spill
--- sites it made ({x, z, r}), for the crust to keep clear of.
local function buildRun(
	parent: Instance,
	run: Run,
	groundY: number,
	rng: Random,
	palette: Palette,
	crustParent: Instance,
	bounds: Bounds,
	spills: { { number } }
)
	local points = run.points
	local halfKerb = (CHANNEL_W + KERB_W) / 2
	local bedW = CHANNEL_W + 2 * KERB_W
	local wet = true

	local function spill(x: number, z: number, bearing: number)
		local sx, sz, sr = spillTongue(parent, x, z, groundY, bearing, rng, palette, bounds)
		table.insert(spills, { sx, sz, sr })
	end

	for leg = 1, #points - 1 do
		local a, b = points[leg], points[leg + 1]
		local legLen = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
		local ux, uz = (b.X - a.X) / legLen, (b.Z - a.Z) / legLen
		local nx, nz = -uz, ux
		local yaw = yawAlong(a.X, a.Z, b.X, b.Z)
		local rot = CFrame.Angles(0, yaw, 0)

		-- Kerbs run between the chamber walls, not centre to centre.
		local s0 = if run.trims[leg] then CHAMBER_TRIM else 0
		local s1 = legLen - (if run.trims[leg + 1] then CHAMBER_TRIM else 0)
		local span = s1 - s0
		if span <= 0.5 then
			continue
		end
		local count = math.max(1, math.round(span / SEG_LEN))
		local segLen = span / count
		local inCulvert = run.culvertLeg == leg

		local breakSeg: { [number]: boolean } = {}
		for _, brk in run.breaks do
			if brk.leg == leg then
				breakSeg[math.clamp(math.ceil(((brk.t * legLen) - s0) / segLen), 1, count)] = true
			end
		end

		-- The spill side of a break is the one facing the walk lane.
		local toLane = if (a.Z + b.Z) / 2 * nz > 0 then -1 else 1

		for s = 1, count do
			local mid = s0 + (s - 0.5) * segLen
			local cx, cz = a.X + ux * mid, a.Z + uz * mid
			local broken = breakSeg[s] == true and not inCulvert

			if broken or inCulvert then
				wet = true
			elseif wet then
				wet = rng:NextNumber() >= DRY_START_CHANCE
			else
				wet = rng:NextNumber() < WET_RESUME_CHANCE
			end

			block(
				parent,
				"CoolantBed",
				CFrame.new(cx, groundY + BED_TOP - BED_THICK / 2, cz) * rot,
				Vector3.new(segLen + SEG_OVERLAP, BED_THICK, bedW + 2 * APRON),
				palette.concrete[1 + (s % 2)],
				true
			)

			if not inCulvert then
				for side = -1, 1, 2 do
					local kx, kz = cx + nx * halfKerb * side, cz + nz * halfKerb * side
					if broken and side == toLane then
						-- CRACKED AND TIPPED OUT: two stubs either side of a gap, each rolled
						-- outward about its own foot, the coping off them lying in the mud.
						local piece = segLen * 0.36
						for _, e in { -1, 1 } do
							local along = e * (segLen / 2 - piece / 2)
							local foot = Vector3.new(kx + ux * along, groundY, kz + uz * along)
							local tilt = side * rng:NextNumber(18, 34)
							local F = CFrame.new(foot) * rot * CFrame.Angles(math.rad(tilt), math.rad(rng:NextNumber(-6, 6)), 0)
							block(parent, "KerbCracked", F * CFrame.new(0, KERB_H / 2 - 0.12, 0), Vector3.new(piece, KERB_H, KERB_W), palette.concrete[2], true)
							local out = Vector3.new(nx, 0, nz) * side * rng:NextNumber(2, 3.4)
							block(
								parent,
								"CopingFallen",
								CFrame.new(foot + out + Vector3.new(0, COPING_H / 2 + 0.02, 0)) * rot * CFrame.Angles(0, math.rad(rng:NextNumber(-30, 30)), 0),
								Vector3.new(piece * rng:NextNumber(0.6, 0.95), COPING_H, KERB_W + 2 * COPING_LIP),
								COPING,
								true
							)
						end
						for _ = 1, rng:NextInteger(3, 5) do
							local r = rng:NextNumber(0.35, 0.8)
							local d = rng:NextNumber(0.4, 2.6)
							local along = rng:NextNumber(-segLen * 0.2, segLen * 0.2)
							block(
								parent,
								"Rubble",
								CFrame.new(kx + nx * side * d + ux * along, groundY + r * 0.35, kz + nz * side * d + uz * along)
									* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-25, 25))),
								Vector3.new(r, r * 0.8, r * 1.1),
								palette.concrete[rng:NextInteger(1, 2)],
								true
							)
						end
						-- The coolant pours through the gap onto the ground.
						local lip = Vector3.new(cx + nx * side * (CHANNEL_W / 2), groundY + CHANNEL_FILL_TOP - 0.05, cz + nz * side * (CHANNEL_W / 2))
						local land = Vector3.new(cx + nx * side * (halfKerb + KERB_W / 2 + 1.6), groundY + COOLANT_TOP + 0.02, cz + nz * side * (halfKerb + KERB_W / 2 + 1.6))
						local pour = block(parent, "Pour", CFrame.lookAt((lip + land) / 2, land), Vector3.new(segLen * 0.22, COOLANT_THICK, (land - lip).Magnitude), palette.coolant)
						pour.Material = Enum.Material.Neon
						spill(land.X, land.Z, math.deg(math.atan2(nz * side, nx * side)))
						continue
					end

					local damaged = rng:NextNumber() < KERB_DAMAGE_CHANCE
					block(parent, "CoolantKerb", CFrame.new(kx, groundY + KERB_H / 2, kz) * rot, Vector3.new(segLen - JOINT, KERB_H, KERB_W), palette.concrete[2], true)
					if damaged then
						-- The coping came off and lies beside the kerb it fell from.
						local out = Vector3.new(nx, 0, nz) * side * rng:NextNumber(1.6, 2.6)
						block(
							parent,
							"CopingFallen",
							CFrame.new(kx + out.X, groundY + COPING_H / 2 + 0.02, kz + out.Z) * rot * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), math.rad(rng:NextNumber(-4, 4))),
							Vector3.new(segLen * rng:NextNumber(0.35, 0.6), COPING_H, KERB_W + 2 * COPING_LIP),
							COPING,
							true
						)
					else
						block(
							parent,
							"KerbCoping",
							CFrame.new(kx, groundY + KERB_H + COPING_H / 2, kz) * rot,
							Vector3.new(segLen - JOINT, COPING_H, KERB_W + 2 * COPING_LIP),
							COPING,
							true
						)
					end
					if wet and rng:NextNumber() < FRINGE_CHANCE then
						kerbFringe(crustParent, kx + nx * FRINGE_REACH * 0.8 * side, kz + nz * FRINGE_REACH * 0.8 * side, groundY, yaw, segLen, rng, palette)
					end
				end
			end

			if wet then
				local liquid = block(
					parent,
					"Coolant",
					CFrame.new(cx, groundY + CHANNEL_FILL_TOP - COOLANT_THICK / 2, cz) * rot,
					-- A hair wider than the channel, so its sides bury in the kerbs.
					Vector3.new(segLen + SEG_OVERLAP, COOLANT_THICK, CHANNEL_W + 0.1),
					palette.coolant
				)
				liquid.Material = Enum.Material.Neon
				-- Flow: flecks ride downstream (a -> b) with a few bubbles.
				Kit.liquidFx(
					parent,
					CFrame.fromMatrix(liquid.Position + Vector3.new(0, COOLANT_THICK / 2, 0), Vector3.new(ux, 0, uz), Vector3.yAxis),
					segLen,
					CHANNEL_W - 0.6,
					palette.coolantHex,
					2.2
				)
			else
				-- A dry stretch still carries the mark the liquid left on the way through.
				block(
					parent,
					"CoolantStain",
					CFrame.new(cx, groundY + STAIN_TOP - COOLANT_THICK / 2, cz) * rot,
					Vector3.new(segLen + SEG_OVERLAP, COOLANT_THICK, CHANNEL_W - 0.9),
					palette.stainDeep
				)
			end
		end
	end

	-- Chambers, turned to the bisector of the legs either side of them.
	for i in run.chambers do
		local p = points[i]
		local dx, dz = 0, 0
		if i > 1 then
			local q = points[i - 1]
			local l = math.sqrt((p.X - q.X) ^ 2 + (p.Z - q.Z) ^ 2)
			dx += (p.X - q.X) / l
			dz += (p.Z - q.Z) / l
		end
		if i < #points then
			local q = points[i + 1]
			local l = math.sqrt((q.X - p.X) ^ 2 + (q.Z - p.Z) ^ 2)
			dx += (q.X - p.X) / l
			dz += (q.Z - p.Z) / l
		end
		local F = chamber(parent, p, yawOf(dx, dz), groundY, palette)
		if run.valveAt == i then
			valve(parent, F)
		end
	end

	if run.outfall then
		local a, b = points[#points - 1], points[#points]
		local l = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
		local ux, uz = (b.X - a.X) / l, (b.Z - a.Z) / l
		local start = outfall(parent, b, ux, uz, groundY, palette)
		spill(start.X, start.Z, math.deg(math.atan2(uz, ux)))
	end
end

-- ── Build ──────────────────────────────────────────────────────────────────────

--- `points` with extra vertices spliced in at each (leg, t) in `at`, in order along the
--- line. Returns the new polyline and, for each entry of `at`, its vertex index.
local function splice(points: { Vector3 }, at: { { leg: number, t: number } }): ({ Vector3 }, { number })
	local out: { Vector3 } = {}
	local index: { number } = table.create(#at, 0)
	for leg = 1, #points - 1 do
		table.insert(out, points[leg])
		local here: { number } = {}
		for j, jn in at do
			if jn.leg == leg then
				table.insert(here, j)
			end
		end
		table.sort(here, function(x, y)
			return at[x].t < at[y].t
		end)
		for _, j in here do
			table.insert(out, points[leg]:Lerp(points[leg + 1], at[j].t))
			index[j] = #out
		end
	end
	table.insert(out, points[#points])
	return out, index
end

--- A break authored as (leg, t) on the original polyline, moved onto the spliced one.
local function relocate(original: { Vector3 }, spliced: { Vector3 }, brk: { leg: number, t: number }): { leg: number, t: number }
	local p = pointOn(original, brk.leg, brk.t)
	local best, bestLeg, bestT = math.huge, 1, 0
	for i = 1, #spliced - 1 do
		local a, b = spliced[i], spliced[i + 1]
		local dx, dz = b.X - a.X, b.Z - a.Z
		local len2 = dx * dx + dz * dz
		local t = if len2 > 0 then math.clamp(((p.X - a.X) * dx + (p.Z - a.Z) * dz) / len2, 0, 1) else 0
		local d = (p.X - a.X - dx * t) ^ 2 + (p.Z - a.Z - dz * t) ^ 2
		if d < best then
			best, bestLeg, bestT = d, i, t
		end
	end
	return { leg = bestLeg, t = bestT }
end

function CoolantField.build(parent: Instance, stageId: number, groundY: number)
	local palette = paletteFor(stageId)
	local def = Stages.get(stageId)
	local cx, cz = def.center[1], def.center[2]

	local folder = Instance.new("Folder")
	folder.Name = "CoolantField"
	local crustFolder = Instance.new("Folder")
	crustFolder.Name = "Crust"

	local function toWorld(p: { number }): Vector3
		return Vector3.new(cx + p[1], 0, cz + p[2])
	end
	local function lift(list: { { number } }): { Vector3 }
		local out = {}
		for i, p in list do
			out[i] = toWorld(p)
		end
		return out
	end

	local trunk0, south0 = lift(TRUNK), lift(SOUTH)

	-- Every spur's junction becomes a vertex (and a chamber) on the run it leaves.
	local trunkJ, southJ = {}, {}
	local spurFrom: { { list: string, j: number } } = {}
	for i, spur in SPURS do
		local list = if spur.from == "trunk" then trunkJ else southJ
		table.insert(list, { leg = spur.leg, t = spur.t })
		spurFrom[i] = { list = spur.from, j = #list }
	end
	local trunk, trunkIdx = splice(trunk0, trunkJ)
	local south, southIdx = splice(south0, southJ)

	local function allChambers(n: number, lastToo: boolean): { [number]: boolean }
		local set = {}
		for i = 1, n do
			if i < n or lastToo then
				set[i] = true
			end
		end
		return set
	end

	local runs: { Run } = {}
	local trunkBreaks = {}
	for _, brk in TRUNK_BREAKS do
		table.insert(trunkBreaks, relocate(trunk0, trunk, brk))
	end
	local southBreaks = {}
	for _, brk in SOUTH_BREAKS do
		table.insert(southBreaks, relocate(south0, south, brk))
	end
	local trunkRun: Run = {
		points = trunk,
		chambers = allChambers(#trunk, true),
		trims = allChambers(#trunk, true),
		breaks = trunkBreaks,
		outfall = false,
	}
	local southRun: Run = {
		points = south,
		chambers = allChambers(#south, false),
		trims = allChambers(#south, false),
		breaks = southBreaks,
		outfall = true,
	}
	table.insert(runs, trunkRun)
	table.insert(runs, southRun)

	local culvertFrame: CFrame? = nil
	local culvertLen = 0
	for i, spur in SPURS do
		local from = spurFrom[i]
		local startIdx = if from.list == "trunk" then trunkIdx[from.j] else southIdx[from.j]
		local start = if from.list == "trunk" then trunk[startIdx] else south[startIdx]
		local finish = toWorld(spur.to)
		if spur.crosses then
			-- Cut the run at the culvert's headwalls, so its kerbs end exactly on them.
			local dz = finish.Z - start.Z
			local function atZ(z: number): Vector3
				return start:Lerp(finish, (z - start.Z) / dz)
			end
			local zIn = if dz < 0 then DECK_HALF + HEAD_T else -(DECK_HALF + HEAD_T)
			local points = { start, atZ(zIn), atZ(-zIn), finish }
			trunkRun.valveAt = if from.list == "trunk" then startIdx else nil
			table.insert(runs, {
				points = points,
				chambers = {},
				trims = { [1] = true, [4] = true },
				breaks = {},
				culvertLeg = 2,
				outfall = false,
			})
			local u = (finish - start).Unit
			local mid = atZ(0)
			culvertFrame = CFrame.fromMatrix(mid, u, Vector3.yAxis)
			culvertLen = 2 * DECK_HALF / math.abs(u.Z)
		else
			table.insert(runs, {
				points = { start, finish },
				chambers = {},
				trims = { [1] = true },
				breaks = {},
				outfall = true,
			})
		end
	end

	local minX, minZ, maxX, maxZ = Stages.bounds(stageId)
	local bounds: Bounds = {
		minX = minX + SPILL_MARGIN,
		minZ = minZ + SPILL_MARGIN,
		maxX = maxX - SPILL_MARGIN,
		maxZ = maxZ - SPILL_MARGIN,
	}

	local netRng = Random.new(SEED)
	local spills: { { number } } = {}
	for _, run in runs do
		buildRun(folder, run, groundY, netRng, palette, crustFolder, bounds, spills)
	end
	if culvertFrame then
		culvert(folder, culvertFrame, culvertLen, groundY, palette)
	end

	-- ── The scattered crust ──
	-- Its own rng, and it runs last: nothing above can be moved by anything below it.
	local crustRng = Random.new(SEED + 1)
	local x0, x1 = minX + EDGE_MARGIN, maxX - EDGE_MARGIN
	local z0, z1 = minZ + EDGE_MARGIN, maxZ - EDGE_MARGIN
	local rings: { { number } } = {}
	for _, rung in CRUST_LADDER do
		for _ = 1, rung.n do
			local size = crustRng:NextNumber(rung.a[1], rung.a[2])
			local r = size / 2
			local bestX, bestZ, bestScore = 0, 0, -math.huge
			for _ = 1, CRUST_CANDIDATES do
				local x = crustRng:NextNumber(x0 + r, x1 - r)
				local z = crustRng:NextNumber(z0 + r, z1 - r)
				local clear = true
				for _, run in runs do
					if distToPolyline(run.points, x, z) < CRUST_CHANNEL_CLEAR + r * 0.6 then
						clear = false
						break
					end
				end
				if clear then
					local score = math.huge
					for _, o in rings do
						score = math.min(score, math.sqrt((x - o[1]) ^ 2 + (z - o[2]) ^ 2) - o[3] - r)
					end
					for _, o in spills do
						score = math.min(score, math.sqrt((x - o[1]) ^ 2 + (z - o[2]) ^ 2) - o[3] - r)
					end
					if score > bestScore then
						bestX, bestZ, bestScore = x, z, score
					end
				end
			end
			if bestScore > 1 then
				crustRing(crustFolder, bestX, bestZ, groundY, size, crustRng, palette)
				table.insert(rings, { bestX, bestZ, r })
			end
		end
	end

	crustFolder.Parent = folder
	folder.Parent = parent
end

return CoolantField
