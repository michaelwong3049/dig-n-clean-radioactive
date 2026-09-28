--!strict
--[[
	CoolantField.luau — the reactor's coolant drainage on Stage 5, and the crust it
	left behind when it dried.

	    called from build/Scenery's buildStageScenery (Stage 5, the only pass that field has)

	WHY THIS FIELD GETS CHANNELS AND NOT PUDDLES. What you dig out of Reactor Grounds
	is fuel rods, cooling valve wheels, core samples, sealed casings and a black-box
	recorder (Config/Items) — so this ground is the plant site itself, inside the fence
	line, and not somewhere the fallout happened to land. That is a vocabulary no other
	field in the chain owns: engineered things, straight lines, concrete. Stage 4 next
	door already owns round ooze puddles (build/Scenery scatterOozePools) and re-using
	them here would make two neighbouring fields rhyme when the whole point of Stage 5
	is that it reads as a different KIND of place — the same argument the stage's own
	colour note in Config/Stages makes about its pink floor.

	So the magenta out here is LEAKED COOLANT: it comes out of something, it runs in a
	direction, and where it stopped running it dried into crust. That also makes it the
	one colour on this field that survives the sky — Stage 5's air is yellow-green
	(Config/Sky, C8E85A fog over 8A9152 ambient), which pushes both the pale pink floor
	and any grey concrete sallow. `ooze.bright` is the only thing out here that holds
	its hue.

	TWO PASSES, ONE SUBSTANCE.

	  * THE NETWORK — a trunk running the field's length just off the walk lane, four
	    spurs branching south off it, and a shorter collector across the field's south
	    half that one of those spurs crosses the walk lane (under a culvert deck) to
	    reach. All of it in concrete beds between low kerbs. Wet stretches carry
	    coolant; dry ones carry only the stain it left. Where a run is BROKEN the kerbs
	    are gone or toppled and the coolant floods out across the ground in a tongue.
	  * THE CRUST — pale mineral rings scattered over the rest of the plate where a
	    spill stood and evaporated, plus fringes hugging the kerbs and collars round
	    every tongue, so the two passes read as one substance rather than as two
	    unrelated decorations.

	THE LAYOUT IS AUTHORED, NOT ROLLED, and that is the same call Config/StageCraters
	makes for Stage 6: a network you can follow end to end is the one thing this field
	has to give a player to navigate by (Stage 3 has its drums, Stage 2 its tree line,
	Stage 5 has had nothing at all), and a landmark that can land anywhere is not a
	landmark. TRUNK/SPURS below are fixed numbers in plate-local studs. Everything
	ROLLED off the seed is detail on top of that skeleton: which stretches are wet,
	which kerb sections have gone, the shape of every tongue and every crust ring.

	ITS OWN SEED, TWICE OVER. Never the stage rng — build/Scenery's other fields draw
	on one shared rng per stage, where adding a pass moves everything placed after it.
	This file takes two Randoms of its own, one for the network and one for the crust,
	so retuning the crust cannot move a single kerb.

	LOW, FLAT AND WALK-THROUGH, BECAUSE THIS IS DUG GROUND. Signals spawn anywhere out
	here, so this file keeps build/Scenery's two standing rules for anything over a dig
	plate: CanCollide false, and low enough that a haul rising underneath still shows.
	The crust and the liquid live in the same thin ground band every other layer in this
	world lives in (see the Y table below). THE KERBS ARE THE ONLY THING THAT STANDS UP,
	at KERB_H — between the broken concrete build/FieldLitter already drops on Stage 3
	(1.23) and the rebar stubs it leans out of them (1.91), both of which stand over a
	dig plate with no special handling. That is WHY the kerbs are this height and not
	waist-high: a taller channel would have to register a no-spawn footprint with
	DigService the way Config/StageCraters does for the crater rims, and none of that
	machinery is worth a drain.

	THE Y BAND, measured over the checkerboard cap (`groundY`, which is already
	Stages.SURFACE_Y + GROUND_SKIM by the time it reaches this file):

	    crust rings / fringes   +0.012 .. +0.024   (under everything)
	    concrete bed            +0.02              (the channel bottom)
	    dry stretch's stain     +0.05
	    spilt coolant on ground +0.09 .. +0.105    = build/Scenery's POOL_TOP over the plate,
	                                                 a tongue's ovals stacking over it the
	                                                 same hundredths its pools do
	    coolant IN a channel    +0.82              = CHANNEL_FILL_TOP, see its note --
	                                                 the drains are backed up, and a
	                                                 surface at ground level is invisible
	                                                 over the kerb from standing height
	    border strip            +0.20              = build/Scenery's SKIM over the plate
	    fallen kerb             +1.10              = KERB_W, lying on its side
	    kerb crown              +1.20              = KERB_H
	    culvert deck            +1.26              (sits ON the kerbs, one crossing only)

	Those are MEASURED off the built field, not intended values.

	THE WALK LANE. Nothing that stands up crosses z = 0 except the one culvert, whose
	deck is the crossing — the same clear corridor the carcasses, the drums and the
	Stage 3 litter all keep off (build/Scenery's SKELETON_CENTRE_CLEARANCE /
	BARREL_CENTRE_CLEARANCE, both 16). The crust rings ignore the lane on purpose, for
	the reason scatterOozePools gives for its puddles: a flat layer you walk straight
	over, and holding it off the route would only make the route the one clean stripe in
	a contaminated field.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)

local Kit = require(script.Parent.Kit)

local CoolantField = {}

--- 8400 is build/FieldLitter's. The network and the crust take SEED and SEED + 1 —
--- see the header on why they are two and not one.
local SEED = 8600

-- ── The skeleton ───────────────────────────────────────────────────────────────
-- Plate-local studs, x along the field's length and z across it, so the layout is
-- readable against Config/Stages' own `size` (290 x 170 -> x +-145, z +-85) and does
-- not have to be re-derived if a stage's centre ever moves.

--- The trunk, west to east, as a polyline. Four points and so three legs: it BENDS,
--- because a drain follows the grade it was cut into and a perfectly straight 270-stud
--- line across a field reads as a ruler, not as something that was built to carry
--- water. The bends are only a few degrees each — enough to see down the length of it,
--- never enough to look like a mistake.
---
--- HELD NORTH OF THE WALK LANE the whole way, parallel to it rather than across it:
--- this is the thing a player walks ALONGSIDE from one end of the field to the other,
--- which is what makes it a spine. Only the spurs reach south toward the route.
local TRUNK: { { number } } = {
	{ -135, 40 },
	{ -60, 34 },
	{ 35, 38 },
	{ 135, 31 },
}

--- The spurs, each attached to a point ON the trunk (`leg` + `t` along it, so a spur
--- can never drift off the run it branches from) and reaching south to an outfall.
---
--- THE OUTFALL IS THE POINT OF A SPUR. Every one of them ends in a break — that is
--- where the coolant leaves the system and floods the ground, and it is the only
--- reason a short dead-end pipe is interesting to walk to.
---
--- ALL BUT ONE STOP SHORT OF THE LANE (|z| >= LANE_HALF). `crosses` marks the one that
--- does not: it runs the full width of the field, over the route, on a culvert deck,
--- and carries on to meet the south collector. One crossing and not four — a crossing
--- is a landmark when there is one of them and a cattle grid when there are four.
---
--- `joins` is that spur's other difference: it ENDS IN A JOINT, not in an outfall, so
--- it gets no break at its tip. Everything else here is a dead end that failed.
local SPURS: { { leg: number, t: number, to: { number }, crosses: boolean?, joins: boolean? } } = {
	{ leg = 1, t = 0.26, to = { -136, 16.5 } },
	{ leg = 2, t = 0.42, to = { -8, 18 } },
	{ leg = 2, t = 0.8, to = { 20, -41 }, crosses = true, joins = true },
	{ leg = 3, t = 0.58, to = { 112, 17 } },
}

--- THE SOUTH COLLECTOR, the run the crossing spur drains INTO. Shorter than the trunk
--- and lower down the field.
---
--- FOUND ON A PLAN VIEW OF THE BUILT FIELD, not designed in from the start: with the
--- trunk held north of the lane and every spur hanging off it, the southern 40% of the
--- plate had nothing on it but scattered crust. A second run down there does two things
--- at once -- it fills that half, and it turns the crossing spur from a stub that
--- happens to cross the route into the LINK between two halves of one system, which is
--- what makes the network read as a network when you are standing in it.
--- ITS WEST END RUNS OFF THE PLATE like the trunk's does, rather than stopping in open
--- ground. A run that simply ceases mid-field with no outfall and no joint reads as
--- unfinished geometry; one that leaves the field reads as carrying on under the next
--- one. (The east end does stop in the field, but it stops at a BREAK, which is a
--- reason.)
local SOUTH: { { number } } = {
	{ -134, -50 },
	{ -62, -46 },
	{ 20, -41 },
	{ 104, -52 },
}

--- Breaks in the SOUTH collector. One, near its east end -- the bottom of the system is
--- where a drain fails first.
local SOUTH_BREAKS: { { leg: number, t: number } } = {
	{ leg = 3, t = 0.82 },
}

--- Breaks in the TRUNK, as points along it. Two, and they are deliberately not near
--- the ends: a run that fails in the middle of its own length reads as failure, where
--- one that stops at the edge of the field reads as the field ending.
local TRUNK_BREAKS: { { leg: number, t: number } } = {
	{ leg = 1, t = 0.7 },
	{ leg = 3, t = 0.3 },
}

--- Half-width of the open walk lane down z = 0, matching build/Scenery's
--- BARREL_CENTRE_CLEARANCE and build/FieldLitter's LANE_HALF. Three different lane
--- widths across one world would read as none.
local LANE_HALF = 16

--- Kept this far inside the plate's own edges, so nothing here touches a stage seam's
--- border strip or a side wall. Wider than build/FieldLitter's 6 because a kerb STANDS
--- and its litter does not.
local EDGE_MARGIN = 8

--- The same for the flat spills, which are placed relative to a break rather than on
--- the grid and so need a live clamp of their own -- see spillTongue. Smaller than
--- EDGE_MARGIN: a tongue lying flat may run right up to the border strip, it just may
--- not run under it.
local SPILL_MARGIN = 4

-- ── The channel section ────────────────────────────────────────────────────────

--- Inside width, kerb thickness, kerb height. The bed is the two kerbs plus the gap
--- between them; see the header on why the crown is 1.2 and not waist-high.
local CHANNEL_W = 4.0
local KERB_W = 1.1
local KERB_H = 1.2

--- Nominal length of one built segment. Each leg is divided into a whole number of
--- equal segments so a run tiles exactly, and each part is grown by SEG_OVERLAP so
--- there is never a hairline of floor showing at a joint.
local SEG_LEN = 12
local SEG_OVERLAP = 0.06

--- Heights over `groundY` — see the Y table in the header. COOLANT_TOP is
--- build/Scenery's POOL_TOP (0.15 over the plate) less its GROUND_SKIM (0.06), so the
--- liquid in a channel sits in exactly the plane the puddles on Stage 4 sit in.
local BED_TOP = 0.02
local BED_THICK = 0.1
local COOLANT_TOP = 0.09
local COOLANT_THICK = 0.12
local STAIN_TOP = 0.05

--- THE CHANNELS RUN NEAR-BRIMMING, and this number is the whole reason the field has a
--- colour at eye level. Shot live standing beside the south collector: with the liquid
--- lying at COOLANT_TOP, the near kerb (KERB_H, 1.2) hides it completely from standing
--- height, so walking the field you see two grey rails and no coolant at all -- the
--- exact opposite of this stage's premise. A drain that has BACKED UP sits high in its
--- channel, which puts the magenta just under the lip where a grazing angle catches it,
--- and it also explains the breaks: a blocked system under head is why the thing is
--- bursting its kerbs in six places rather than quietly draining.
---
--- 0.38 OF FREEBOARD LEFT. Brim-full to the crown would read as a painted stripe rather
--- than as liquid in a trench -- the shadow line of the inner kerb face above the
--- surface is what says "there is a channel here" at all.
---
--- SPILLS DO NOT USE THIS. A tongue is liquid lying on open GROUND and stays at
--- COOLANT_TOP with the rest of the ground layer.
local CHANNEL_FILL_TOP = 0.82

--- Share of segments whose kerb has gone on one side — not a break in the run (the
--- liquid stays in), just a stretch that has lost its edge. Low: this is decay under
--- the eye, and past about one in ten the channel stops reading as built.
local KERB_GONE_CHANCE = 0.08

--- Wet/dry as a two-state walk down each run rather than a per-segment roll, so wet
--- stretches come out CONTIGUOUS. A per-segment coin flip gives a dashed line, which
--- reads as a rendering fault rather than as a drain that is half empty. The pair is
--- asymmetric on purpose: roughly two thirds of the network ends up wet, and the dry
--- thirds are what make the wet ones read as wet at all.
local DRY_START_CHANCE = 0.1
local WET_RESUME_CHANCE = 0.24

--- The culvert. The deck sits ON the kerbs, and the kerbs stop either side of it for
--- the WHOLE width of the walk lane — not just for the deck's own footprint. That is
--- the point of decking this crossing at all: a player walking the route meets flat
--- concrete across the full corridor, never a kerb standing in it. DECK_SPAN is the
--- other axis, across the channel, and carries enough overhang for the run's tilt.
---
--- THE ABUTMENTS ARE WHAT MAKE IT A CULVERT. Shot live standing on the lane, the deck
--- alone read as a grey concrete PAD lying on the ground: the channel came in from one
--- side, stopped, and picked up again on the other, with nothing to say the liquid went
--- anywhere. A real crossing has a headwall at each end with the bore opening through
--- it, and that opening is the whole tell -- you can see the coolant run into the dark
--- under the deck. Two blocks per end, flanking the channel, carrying the deck.
---
--- AND THE DECK NEEDS A THICKNESS TO READ AS A STRUCTURE. At 0.18 it had no visible
--- edge from standing height and looked painted on; 0.45 gives it a slab edge that
--- catches light without lifting the walking surface, since DECK_TOP is unchanged.
local DECK_HALF = LANE_HALF
local DECK_SPAN = 14
local DECK_TOP = KERB_H + 0.06
local DECK_THICK = 0.45
local ABUT_W = 2.2

-- ── Crust ──────────────────────────────────────────────────────────────────────

--- The field-wide scatter: one roll per CELL-stud cell, the same jittered grid
--- build/FieldLitter deals its litter off.
---
--- THE CHANCE IS THE RATE BEFORE THE CHANNEL-CLEAR REJECTION, not the number of rings
--- you get. Roughly a third to a half of the cells that win their roll are then thrown
--- away for sitting on a run (CRUST_CHANNEL_CLEAR), and that share moved once already:
--- adding the south collector took the field from ~29 rings to 10 on the same 0.16,
--- because two more runs' worth of cells left the deal. Raised to 0.26 against the
--- network as it now stands, for about thirty rings over the 290 x 170 plate. Any
--- future change to the SKELETON has to be re-counted here, not assumed.
local CRUST_CELL = 16
local CRUST_CHANCE = 0.26

--- A ring closer than this to any channel centreline is skipped — the fringes along
--- the kerbs already cover that ground, and a scattered ring lying half across a bed
--- reads as a mistake rather than as a second dried pool.
local CRUST_CHANNEL_CLEAR = 9

--- Ring heights. Four stacked ovals at CRUST_STEP apart tops out at +0.048 over the
--- cap: under the liquid, under the border strip, and under a detector spot's cracks
--- (client/SpotCracks, 0.15 over the plate) so a signal under one still shows.
local CRUST_BASE = 0.012
local CRUST_STEP = 0.004
local CRUST_THICK = 0.04

--- Share of rings that still have liquid in the middle. A ring is what a spill leaves
--- when it evaporates, so most of them are finished doing it; the few that are not are
--- the ones that say the rest USED to be wet.
local CRUST_EYE_SHARE = 0.3

--- Per-side chance a wet segment grows a crust fringe outside its kerb, and how far
--- past the kerb it reaches.
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

type Run = {
	points: { Vector3 }, -- world XZ, y unused
	breaks: { number }, -- indices into the segment list of this run
	crosses: boolean,
}

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
--- -- build/Scenery's oozePool has the full measured argument for this, and it cost that
--- file two passes to find. Same rule here, same reason.
local function crustRing(parent: Instance, x: number, z: number, groundY: number, rng: Random, palette: Palette)
	local a = rng:NextNumber(5, 13)
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
--- DROPLETS PAST THE HEAD, the same trick scatterOozePools throws off its puddles: a
--- couple of detached specks past where the body stops break the outline, so the spill
--- ends in a spatter instead of a clean curve.
---
--- HELD INSIDE THE FIELD, ON A LIVE CHECK -- the same clamp scatterOozePools puts on
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
)
	local reach = rng:NextNumber(11, 19)
	local count = rng:NextInteger(4, 6)
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

		local step = a * rng:NextNumber(0.55, 0.85)
		local drift = a * rng:NextNumber(-0.3, 0.3)
		cx = math.clamp(cx + math.cos(math.rad(bearing)) * step + px * drift, bounds.minX, bounds.maxX)
		cz = math.clamp(cz + math.sin(math.rad(bearing)) * step + pz * drift, bounds.minZ, bounds.maxZ)
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
end

-- ── The run ────────────────────────────────────────────────────────────────────

--- One channel run — the trunk or a spur — built leg by leg.
---
--- EACH LEG TILES EXACTLY. Its own length is divided into a whole number of equal
--- segments rather than chopped into SEG_LEN pieces with a remainder on the end, so a
--- leg never finishes with a stub, and every part is grown by SEG_OVERLAP so a joint
--- never shows a hairline of floor between two segments.
---
--- THE MITRE AT A BEND IS COVERED BY A COLLAR, not solved. Two box segments meeting at
--- an angle leave a wedge open on the outside of the turn whatever you do to their
--- lengths; a junction box over the corner is what a real drain has there anyway, and
--- it is one part instead of a trigonometry problem.
local function buildRun(
	parent: Instance,
	run: Run,
	groundY: number,
	rng: Random,
	palette: Palette,
	crustParent: Instance,
	bounds: Bounds
)
	local points = run.points
	local halfKerb = (CHANNEL_W + KERB_W) / 2
	local bedW = CHANNEL_W + 2 * KERB_W

	-- Which segment is the last one, so a break there can be recognised as the run's
	-- OUTFALL: the liquid leaves the end of the pipe still travelling the way the pipe
	-- pointed, where a failure mid-run dumps it out sideways over open ground.
	local totalSegs = 0
	for leg = 1, #points - 1 do
		local a, b = points[leg], points[leg + 1]
		totalSegs += math.max(1, math.round(math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2) / SEG_LEN))
	end

	local segIndex = 0
	local wet = true

	for leg = 1, #points - 1 do
		local a, b = points[leg], points[leg + 1]
		local legLen = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
		local count = math.max(1, math.round(legLen / SEG_LEN))
		local segLen = legLen / count
		local yaw = yawAlong(a.X, a.Z, b.X, b.Z)
		local rot = CFrame.Angles(0, yaw, 0)
		-- Unit vectors along the run and across it, so every offset below is written in
		-- the run's own frame rather than as a fresh sin/cos each time.
		local ux, uz = (b.X - a.X) / legLen, (b.Z - a.Z) / legLen
		local nx, nz = -uz, ux

		for s = 1, count do
			segIndex += 1
			local mid = (s - 0.5) * segLen
			local cx, cz = a.X + ux * mid, a.Z + uz * mid

			-- The culvert's mouth: the kerbs stop either side of the crossing and the deck
			-- bridges them, so the walk lane crosses flat concrete rather than a wall.
			local underDeck = run.crosses and math.abs(cz) < DECK_HALF

			local broken = table.find(run.breaks, segIndex) ~= nil

			if broken then
				-- Everything upstream of a failure is still carrying liquid -- a break that
				-- opens onto a dry stretch is just a gap in a wall.
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
				Vector3.new(segLen + SEG_OVERLAP, BED_THICK, bedW),
				palette.concrete[1 + (segIndex % 2)],
				true
			)

			if not underDeck then
				for side = -1, 1, 2 do
					-- A break loses BOTH kerbs; the rest of the run loses one here and there,
					-- which is decay rather than failure — see KERB_GONE_CHANCE.
					if not broken and rng:NextNumber() >= KERB_GONE_CHANCE then
						local kx, kz = cx + nx * halfKerb * side, cz + nz * halfKerb * side
						block(
							parent,
							"CoolantKerb",
							CFrame.new(kx, groundY + KERB_H / 2, kz) * rot,
							Vector3.new(segLen + SEG_OVERLAP, KERB_H, KERB_W),
							palette.concrete[2],
							true
						)
						if wet and rng:NextNumber() < FRINGE_CHANCE then
							kerbFringe(
								crustParent,
								kx + nx * FRINGE_REACH * 0.8 * side,
								kz + nz * FRINGE_REACH * 0.8 * side,
								groundY,
								yaw,
								segLen,
								rng,
								palette
							)
						end
					end
				end
			end

			if broken then
				-- The kerb did not vanish, it went over: one length of it lying flat beside
				-- the gap, turned off the run's own line so it reads as fallen rather than
				-- as placed.
				--
				-- TIPPED ABOUT ITS OWN LONG AXIS, WHICH IS THE ONLY ROLL THAT LAYS IT DOWN.
				-- CFrame.Angles is XYZ order, so folding the roll into the yaw call as a Z
				-- term (`Angles(0, yaw, pi/2)`) applies Ry * Rz and stands the kerb's LENGTH
				-- straight up instead -- a seven-stud concrete post in the middle of a dig
				-- field, well over everything this file's header promises. Post-multiplying
				-- a separate Rx by 90 degrees rotates it in its own frame, swapping height
				-- for thickness: 1.2 tall standing becomes KERB_W lying down.
				local side = if rng:NextNumber() < 0.5 then -1 else 1
				block(
					parent,
					"KerbFallen",
					CFrame.new(cx + nx * (halfKerb + 1.6) * side, groundY + KERB_W / 2, cz + nz * (halfKerb + 1.6) * side)
						* CFrame.Angles(0, yaw + math.rad(rng:NextNumber(-22, 22)), 0)
						* CFrame.Angles(math.rad(90), 0, 0),
					Vector3.new(segLen * rng:NextNumber(0.5, 0.85), KERB_H, KERB_W),
					palette.concrete[2],
					true
				)
				-- An outfall carries on down the run's own line; a mid-run failure dumps
				-- out to the SOUTH side (-n, the trunk running west to east), which is
				-- where the player walks -- a spill tucked in behind the channel against
				-- the boundary wall is one nobody ever stands next to.
				local bearing = if segIndex == totalSegs
					then math.deg(math.atan2(uz, ux))
					else math.deg(math.atan2(-nz, -nx))
				spillTongue(parent, cx, cz, groundY, bearing, rng, palette, bounds)
			elseif wet then
				local liquid = block(
					parent,
					"Coolant",
					CFrame.new(cx, groundY + CHANNEL_FILL_TOP - COOLANT_THICK / 2, cz) * rot,
					Vector3.new(segLen + SEG_OVERLAP, COOLANT_THICK, CHANNEL_W - 0.2),
					palette.coolant
				)
				liquid.Material = Enum.Material.Neon
			else
				-- A dry stretch is not empty concrete: it is the mark the liquid left on the
				-- way through, which is what tells you the wet stretches upstream are the
				-- same run and not a separate thing.
				block(
					parent,
					"CoolantStain",
					CFrame.new(cx, groundY + STAIN_TOP - COOLANT_THICK / 2, cz) * rot,
					Vector3.new(segLen + SEG_OVERLAP, COOLANT_THICK, CHANNEL_W - 0.9),
					palette.stainDeep
				)
			end
		end

		-- The collar over every interior bend — see this function's note on the mitre.
		if leg < #points - 1 then
			local nxt = points[leg + 2]
			local outYaw = yawAlong(b.X, b.Z, nxt.X, nxt.Z)
			block(
				parent,
				"CoolantCollar",
				CFrame.new(b.X, groundY + KERB_H / 2 - 0.02, b.Z) * CFrame.Angles(0, (yaw + outYaw) / 2, 0),
				Vector3.new(bedW + 1.2, KERB_H - 0.04, bedW + 1.2),
				palette.concrete[1],
				true
			)
		end
	end

	if run.crosses then
		-- The culvert deck: the road over the drain, spanning the mouth the kerbs left
		-- open. Axis-aligned with the WALK LANE, not with the channel — it is the route
		-- that crosses here, and it is the route the deck belongs to.
		local at = points[1]
		local b = points[#points]
		local dx, dz = b.X - at.X, b.Z - at.Z
		local runLen = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / runLen, dz / runLen
		local nx, nz = -uz, ux
		local function xAtZ(atZ: number): number
			return at.X + dx * (if dz ~= 0 then (atZ - at.Z) / dz else 0)
		end

		block(
			parent,
			"CulvertDeck",
			CFrame.new(xAtZ(0), groundY + DECK_TOP - DECK_THICK / 2, 0),
			Vector3.new(DECK_SPAN, DECK_THICK, DECK_HALF * 2),
			palette.concrete[1],
			true
		)

		-- A headwall either side of the bore, at each end of the deck. The gap they
		-- leave between them IS the opening, and the coolant runs into it.
		for _, endZ in { -DECK_HALF, DECK_HALF } do
			local ex = xAtZ(endZ)
			for side = -1, 1, 2 do
				local ax = ex + nx * (halfKerb + ABUT_W / 2 - KERB_W / 2) * side
				local az = endZ + nz * (halfKerb + ABUT_W / 2 - KERB_W / 2) * side
				block(
					parent,
					"CulvertAbutment",
					CFrame.new(ax, groundY + DECK_TOP / 2, az) * CFrame.Angles(0, yawAlong(at.X, at.Z, b.X, b.Z), 0),
					Vector3.new(2.6, DECK_TOP, ABUT_W),
					palette.concrete[2],
					true
				)
			end
		end
	end
end

-- ── Build ──────────────────────────────────────────────────────────────────────

--- Resolves TRUNK/SPURS into world-space runs, builds them, then scatters the crust
--- over whatever ground the network left open.
function CoolantField.build(parent: Instance, stageId: number, groundY: number)
	local palette = paletteFor(stageId)
	local def = Stages.get(stageId)
	local cx, cz = def.center[1], def.center[2]

	local folder = Instance.new("Folder")
	folder.Name = "CoolantField"
	-- The crust lives in its own folder purely so the field is legible in the Explorer:
	-- ~200 discs interleaved with the channel parts makes finding a kerb a chore.
	local crustFolder = Instance.new("Folder")
	crustFolder.Name = "Crust"

	local function toWorld(p: { number }): Vector3
		return Vector3.new(cx + p[1], 0, cz + p[2])
	end

	local trunkPoints: { Vector3 } = {}

	-- Segment indices are what a run's `breaks` list holds, so a break has to be
	-- converted from its (leg, t) authoring form the same way the builder walks the
	-- legs: whole segments per leg, counted from the start of the run.
	local function segmentIndexAt(points: { Vector3 }, leg: number, t: number): number
		local before = 0
		for i = 1, leg - 1 do
			local a, b = points[i], points[i + 1]
			before += math.max(1, math.round(math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2) / SEG_LEN))
		end
		local a, b = points[leg], points[leg + 1]
		local count = math.max(1, math.round(math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2) / SEG_LEN))
		return before + math.clamp(math.ceil(t * count), 1, count)
	end

	local runs: { Run } = {}

	--- One of the two authored runs: its plate-local points lifted into world space, and
	--- its breaks resolved from the (leg, t) they are authored as into the segment index
	--- the builder will be counting when it reaches them. The crossing spur joins the
	--- collector at one of its own vertices, so that joint gets the same collar every
	--- other bend does, for free.
	local function addAuthoredRun(authoredPoints: { { number } }, authoredBreaks: { { leg: number, t: number } })
		local points: { Vector3 } = {}
		for i, p in authoredPoints do
			points[i] = toWorld(p)
		end
		local breaks: { number } = {}
		for _, brk in authoredBreaks do
			table.insert(breaks, segmentIndexAt(points, brk.leg, brk.t))
		end
		table.insert(runs, { points = points, breaks = breaks, crosses = false })
		return points
	end

	trunkPoints = addAuthoredRun(TRUNK, TRUNK_BREAKS)
	addAuthoredRun(SOUTH, SOUTH_BREAKS)

	for _, spur in SPURS do
		local start = pointOn(trunkPoints, spur.leg, spur.t)
		local points = { start, toWorld(spur.to) }
		-- A spur ends in a break — the outfall — unless it runs on into another run,
		-- which only the crossing one does. See SPURS.
		local breaks = if spur.joins then {} else { segmentIndexAt(points, 1, 1) }
		table.insert(runs, { points = points, breaks = breaks, crosses = spur.crosses == true })
	end

	local minX, minZ, maxX, maxZ = Stages.bounds(stageId)
	local bounds: Bounds = {
		minX = minX + SPILL_MARGIN,
		minZ = minZ + SPILL_MARGIN,
		maxX = maxX - SPILL_MARGIN,
		maxZ = maxZ - SPILL_MARGIN,
	}

	local netRng = Random.new(SEED)
	for _, run in runs do
		buildRun(folder, run, groundY, netRng, palette, crustFolder, bounds)
	end

	-- ── The scattered crust ──
	-- Its own rng, and it runs last: nothing above can be moved by anything below it.
	local crustRng = Random.new(SEED + 1)
	local x0, x1 = minX + EDGE_MARGIN, maxX - EDGE_MARGIN
	local z0, z1 = minZ + EDGE_MARGIN, maxZ - EDGE_MARGIN
	local cols = math.max(1, math.floor((x1 - x0) / CRUST_CELL))
	local rows = math.max(1, math.floor((z1 - z0) / CRUST_CELL))
	local cellW, cellH = (x1 - x0) / cols, (z1 - z0) / rows

	for col = 0, cols - 1 do
		for row = 0, rows - 1 do
			local x = x0 + (col + 0.5 + crustRng:NextNumber(-0.42, 0.42)) * cellW
			local z = z0 + (row + 0.5 + crustRng:NextNumber(-0.42, 0.42)) * cellH
			if crustRng:NextNumber() < CRUST_CHANCE then
				local clear = true
				for _, run in runs do
					if distToPolyline(run.points, x, z) < CRUST_CHANNEL_CLEAR then
						clear = false
						break
					end
				end
				if clear then
					crustRing(crustFolder, x, z, groundY, crustRng, palette)
				end
			end
		end
	end

	crustFolder.Parent = folder
	folder.Parent = parent
end

return CoolantField
