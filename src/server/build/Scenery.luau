--!strict
--[[
	Scenery.luau — barrels, spills and rubble. Everything on the stages that is not
	the stage.

	    require(game.ServerScriptService.Server.build.Scenery).rebuild()

	WHY THIS IS A SEPARATE MODULE FROM StageFields.
	Workspace.Stages must contain the one radioactive plate and NOTHING else. StageService walks
	that folder's children ten times a second per player, and — much worse — a prop
	that accidentally carried a StageId attribute would register as a stage. Overlapping
	stages resolve as "smallest XZ area wins", so one stray barrel would silently
	become the stage every nearby player is standing in. Keeping decor in a different
	folder makes that class of bug impossible rather than merely unlikely.

	THE OOZE IS THE SURFACE, NOT A HAZARD.
	Per the design call: the ground itself is the sludge you walk through, and the
	pools and spills here are visual variation with NO gameplay rules attached.
	StageService.hotPocketFor stays a stub returning 1. This matters for a young
	audience — one rule ("the green ground is dangerous, the paths are not") beats
	two rules ("...but the BRIGHT green is extra dangerous") when the second one is
	only telegraphed by shade.

	WHAT USED TO BE HERE: `OozeSurface`, a translucent Neon plate per stage, sized
	to the whole plate and floating WADE_HEIGHT (1.1 studs, "about half a leg" on a
	default character) above the real floor, so walking into a field sank your
	legs into visible ooze instead of just standing on tinted ground.

	REMOVED ON REQUEST — THE WADING EFFECT WAS NEVER APPROVED. The tint it left on
	the ground WAS liked, so that part is kept, just moved: it is baked directly
	into the plate colour now (Stages.GROUND_OOZE_TINT, applied in StageFields.luau)
	instead of arriving via a second, higher, see-through plate. Zero gap between
	a player's feet and the coloured ground now, same as before this plate existed
	at all — `Stages.SURFACE_Y` (what DigService buries against and what a player's
	feet actually rest on) was never touched by this either way. NB the checkerboard
	cap that now covers every plate (buildStageCheckerboard) is UNtinted on request,
	so the tint on the plate under it is only ever seen if that cap fails to build.

	NOTHING HERE MAY RISE THROUGH THE DIG SURFACE IN A WAY THAT HIDES IT.
	DigService buries items on the plate's top face and the haul part rises to
	exactly that plane, so anything opaque and tall enough to block the view would
	hide an item surfacing underneath. Props are thin and sit just above;
	anything tall is CanCollide=false so a player can walk out of it. Nothing left
	in this file sits above the plane the way `OozeSurface` used to — the ground
	colour itself carries no such risk, it's the plate's own top face.

	EVERY STAGE'S GROUND IS A STUDDED TWO-TONE CHECKERBOARD. buildStageCheckerboard
	caps each plate with a studded checkerboard (same board as the plaza and base
	pads, Hub.tileRect), two near-identical shades of that stage's own colour. Stage 1
	is the one exception: its board is a continuous per-tile blend from the plaza's
	tile colours at the west edge to Stage 1's colour at the east edge — a softer
	hand-off into the field than a flat colour reads as. See buildStageCheckerboard
	for why the colour is a layer on top rather than the plate itself, and for why a
	tiled gradient sidesteps the banded-seam problem two earlier, now-removed systems
	here both hit (see the removal notes still kept below for
	`buildStageBlend`/`buildGradientOozeSurface`).

	Placement is a jittered grid, not pure random. Pure random clumps and leaves bald
	patches; a jittered grid reads as scattered while still covering the field, and
	it is deterministic per stage so a rebuild does not reshuffle the whole world.

	THE BOUNDARY WALLS ARE THE ONE EXCEPTION TO "CanCollide IS FALSE, SAME AS
	EVERYTHING ELSE IN THIS FILE" ABOVE. Confirmed with the user before building it
	that way: there is no terrain past the built plates, and without a real
	boundary a player can just walk off the chain's north or south edge into void.
	`buildBoundaryWalls` is a genuine collidable barrier, not a decoration wearing
	one — everything else's CanCollide=false reasoning (haul visibility, walking
	through props) does not apply to it and should not be assumed to.

	THE CAMP HAD NO WALL OF ITS OWN UNTIL `buildBaseWalls`, ON REQUEST -- the same
	void-fall risk `buildBoundaryWalls` exists to close for the stage chain was
	sitting open on the camp side the whole time, just less obviously: Plots.luau's
	circular apron around the base plots (radius Plots.RING_OUTER) is not a neat
	semicircle tucked inside the corridor's own width, it bulges out to roughly
	+-227 in Z right at the x = Hub.PLAZA.maxX seam, well past the corridor's own
	+-120. Confirmed live via raycast, not assumed: a player standing on real apron
	ground at (100, 200) could walk two steps east into the stage chain's own
	airspace and find nothing under them -- Stage 1's plate does not reach that far
	off-centre, and the corridor's own wall only guards its OWN z line, not the open
	shoulder beside it. `buildBaseWalls` closes it with one curved wall following
	the apron's true circular edge plus two short straight pieces bridging each
	shoulder down to where the corridor wall already starts -- see that function's
	own comment for why it is three pieces and not one.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)
local Plots = require(script.Parent.Plots)

local Scenery = {}
local BUILDER_SOURCE = "src/server/build/Scenery.luau"
local BUILDER_VERSION = 23

local C, R = Kit.C, Kit.R
local build = Kit.build

--- Just above the plate's top face — close enough to read as lying on the ground,
--- high enough not to z-fight with it.
local SKIM = 0.26

--- The stage colour layer sits BELOW the pools, so a pool still reads as spilled on
--- the ground rather than buried under it. Low enough to be invisible as a step.
local GROUND_SKIM = 0.06

-- Stage 1 keeps a clear lane down its centreline (z = 0), the walk-through path
-- into the field -- scatterBushes pushes foliage at least this far off it so a
-- bush never sprouts in the middle of the route.
local BUSH_CENTRE_CLEARANCE = 28

-- Stage 2 keeps the same clear lane down z = 0 for its carcasses -- the one Stage 2
-- prop big enough to block a sightline -- pushed at least this far off it. Smaller
-- than the bush clearance on purpose: a rib cage standing just off the path is the
-- point, and you should be walking past one, not hunting for it at the field's edge.
-- (The dead trees themselves are no longer kept off this lane -- scatterFieldTrees
-- covers the whole field now -- but a carcass laid across the walk-through route
-- still reads as a mistake, so its own clearance stays.)
local SKELETON_CENTRE_CLEARANCE = 20

-- Stage 3 keeps the same open lane down z = 0 the first two fields do, so a dump of
-- drums is pushed at least this far off it (scatterBarrels). Smaller again than the
-- carcass clearance: a drum is chest-high where a rib cage is a wall, and a dump you
-- walk past close enough to read the trefoil on is worth more than one at the edge
-- of the field.
local BARREL_CENTRE_CLEARANCE = 16

--- How far the second and third drums of a load stand off the first. THE FLOOR IS A
--- HARD CONSTRAINT, not a look: a drum is 2.84 studs across over its chimes and a
--- fallen one is 4.0 long, so two drums closer than about 4 studs are one drum
--- growing out of another. Measured live at the first pass, which jittered x and z
--- independently and put two of them 2.02 studs apart.
local BARREL_CROWD_MIN = 4.2
local BARREL_CROWD_MAX = 6.0

--- How far a dump SITE has to sit off the walk lane. Not the same number as the
--- clearance above, which is owed by each drum: a load reaches BARREL_CROWD_MAX out
--- from its site before the pose-aware slide in scatterBarrels pushes it further, and
--- a fallen drum then puts half its own length past that again. This is that sum with
--- room over it, and the built field is measured against BARREL_CENTRE_CLEARANCE
--- rather than this, because the slide has no closed-form bound worth deriving.
local BARREL_LANE_KEEPOUT = BARREL_CENTRE_CLEARANCE + BARREL_CROWD_MAX + 4

--- The mix of poses in a dump, as a share of the drums in it: a quarter of them over
--- on their side, one in ten propped at an angle, the rest standing. A yard of drums
--- all plumb reads as a warehouse, and a field of them all down reads as a wreck --
--- this is a place things were dumped and left. These are shares, not odds; see the
--- bag in scatterBarrels for why that distinction is the whole point.
local BARREL_FALLEN = 0.25
local BARREL_LEANING = 0.10

--- Dead wood, for `deadTree`. Lighter than Kit.C.wood (5A4630, the warm living-wood
--- brown the camp and the liveTree use) but still greyer/less saturated -- bark that
--- has had the colour weathered out of it, just not as far weathered as the original
--- near-charcoal tone. Builder-local, same as WALL_BROWN_DARK/LIGHT: nothing outside
--- this file's trees needs them. Roughly one segment in four takes the darker tone so
--- the flat facets read against each other (the trick foliageBlob uses).
local DEAD_WOOD = "6E5A42"
local DEAD_WOOD_DARK = "504230"

--- Living leaf green, for `bush` in Stage 1's alive west half. Brighter and more
--- saturated than the old muted "brush"/"liveTree" scrub greens -- these are meant to
--- pop against the grass like the reference. Plastic (studded), never Neon, so bloom
--- never touches them: the "green = danger" rule is a NEON-in-a-stage rule, and a
--- matte shrub in Stage 1's own green end reads as life, not hazard.
local BUSH_GREEN = "63B83A"
local BUSH_GREEN_DARK = "4C9029"

--- Bone, for the Stage 2 and 3 remains (`boneShaft`, `skull`, `animalSkeleton`). A
--- sun-bleached base with a dirt-stained second tone, mixed per part the way
--- DEAD_WOOD/_DARK is on the trees so a rib cage's facets read against each other
--- instead of flat-shading into one white mass. Builder-local, same as the wood and
--- bush greens: nothing outside the bone fields needs them.
---
--- ONE PALETTE FOR BOTH FIELDS, deliberately -- see the section header. Stage 3's
--- floor (A67C4E) is a darker, browner khaki than Stage 2's dun tan (B8935F), so if
--- anything the same bone separates from it harder, not less.
---
--- PALE, NOT WHITE, AND WARM. Pure white on a studded Plastic part in this world's
--- flat lighting reads as painted polystyrene; holding a little of the ground's own
--- yellow keeps it reading as bone lying in the dirt while still separating clearly
--- from the board at a distance.
---
--- THE WARMTH IS NOT DECORATIVE, AND IT HAS TO BE THIS MUCH OF IT. Everything not
--- facing the sun here is lit by the sky and the ambient, and both are green-mint
--- (build/Daylight: Ambient 6E7A72, OutdoorAmbient 7E9488, ColorShift_Bottom BFE0C8,
--- EnvironmentDiffuseScale 0.6). A pale neutral bone therefore renders visibly BLUE
--- down every shaded face -- shot live at two values before this one: an off-white
--- (DFD6BC) read as ice, and a mildly warmed ivory (E6D9B4) barely moved it, because
--- the cast is coming from the light, not from the paint. It takes a genuinely warm
--- base -- roughly one step short of the ground's own tan -- for the shaded side to
--- come back to bone and the sunlit side to cream. Do not "clean these up" toward
--- white; that is the change that puts the blue back.
local BONE = "F2C98E"
local BONE_DARK = "CEAB79"

--- The hollows -- eye sockets, the nasal notch, the gap between the jaws. Near-black
--- rather than black so it reads as shadow inside a skull rather than as a dot painted
--- on the front of it. Flush with the face it sits in (a hair proud, to not z-fight),
--- which is how every other cartoon detail in this world is done -- there is no
--- boolean-subtract to carve a real socket with.
local BONE_HOLLOW = "2B251D"

--- The chain's north/south boundary walls. Doubled to 56 tall and dropped to a
--- 4-stud tile (from 28/8) after a live look -- ~8,400 parts per side at this size
--- (2,390/4 x 56/4), noticeably more than the first pass's ~1,050 but still well
--- inside what this file's own plaza-adjacent builders already tolerate (the plaza
--- itself is 4,096 tiles alone).
---
--- WALL_THICKNESS 4 -> 8, ON REQUEST -- every wall in this file reads twice as
--- solid. The corridor walls' part count is unchanged (their tiles are counted off
--- the X/Z span and height, never the depth), so the ~8,400/side figure above still
--- holds; the base-camp arc gains ~30 columns because ITS column count comes off
--- wallRadius (= Plots.RING_OUTER + WALL_THICKNESS/2), which grew 2 studs.
--- The corridor walls and the arc pin their INNER face to the edge they guard and
--- grow outward into void from there -- buildBoundaryWalls offsets its centreline
--- by WALL_THICKNESS/2, and the shoulder junctions track that same half-offset. The
--- two shoulder pieces themselves straddle x = clipX, which is shoulder void-fill
--- either side, not walkable ground -- so doubling the depth never eats into a
--- walking surface (verified live: north-wall inner face still exactly on z = minZ).
local WALL_HEIGHT = 56
local WALL_THICKNESS = 8
local WALL_TILE = 4
-- A studded sheet laid flat over each wall's crown -- "the stage floor, stacked on top
-- of the wall", ON REQUEST. Painted in the stage's own FLOOR two-tone (not the paler
-- wallPair), so the crown reads as ground carried up and over the barrier -- EXCEPT
-- Stage 1, which takes the camp apron green like the base-camp arc (see capStagePair).
-- TWO STUDS high, on request (0.75 -> 1 -> 2). Bites 0.1 stud down into the wall top
-- so there is no z-fighting seam.
local WALL_CAP_THICKNESS = 2
-- The camp / Stage 1 pair. A warm terracotta brown; the two sit ~8% apart per
-- channel on purpose -- close enough that the checker reads as one brown material
-- with a faint grid, not a two-tone pattern (the original rust pair, B5573A/9C4A2F,
-- read as too bold up close).
local WALL_BROWN_DARK = "8D4B2B"
local WALL_BROWN_LIGHT = "9B5331"

-- PER-STAGE WALL COLOUR. The chain used to wear ONE uniform rust its whole length,
-- on the principle that an engineered containment barrier reads as one consistent
-- material rather than sharing each stage's theme. OVERRIDDEN ON REQUEST: the wall
-- now shifts colour with the stage behind it, so walking deeper reads on the
-- boundary too. The camp wall (buildBaseWalls) and Stage 1 keep the brown above.
--
-- A stage's wall is either HAND-PICKED (WALL_STAGE_PIN below) or DERIVED as a
-- lighter tint of that stage's own floor colour (Stages def.color): same hue,
-- lifted this fraction of the way to full brightness and slightly desaturated, so
-- the wall reads as "the floor, but paler" standing over it. Either way twoTone()
-- splits the result into the close two-shade checker. See wallPair / lighterFloor.
local WALL_FLOOR_LIFT = 0.5 -- fraction of the value headroom (1 - v) to add
local WALL_FLOOR_DESAT = 0.8 -- saturation multiplier

-- Hand-picked stage walls, keyed by stage id. A pinned stage ignores the
-- lighter-floor derivation entirely; the hex here is the checker's MIDPOINT, same
-- as twoTone treats every other input. Anything not listed is derived.
local WALL_STAGE_PIN: { [number]: string } = {
	[2] = "CD8C44", -- warm amber-gold, on request
	[5] = "EF9DB2", -- rose pink -- the floor's already near-white, so this holds chroma instead of lightening
	[6] = "946DC6", -- light amethyst -- the floor tinted toward white, staying violet rather than the derived blurple
}

--- The boundary lines. A flat hazard-checker strip laid across the full width of the
--- camp -> Stage 1 entrance AND every internal stage-to-stage seam (Stage 1/2
--- through 5/6), so a player reads "new ground" off the floor the instant they cross
--- it, before any HUD number moves. Only Stage 6's east edge (the void wall) has no
--- line. The camp->Stage 1 line was added on request -- it is the walk in from
--- camp, so it reads as "you are leaving the safe ground" rather than "new stage",
--- but it is the same strip either way.
---
--- 3 studs wide in the walk direction, on request. Two rows across that width so
--- the checker alternates both ways rather than reading as a dashed line. Thin,
--- CanCollide/CanQuery false and only SKIM above the surface, same as every other
--- ground layer in this file -- footing and burial stay on Stages.SURFACE_Y.
local BORDER_WIDTH = 3 -- studs along X (the walk direction)
local BORDER_ROWS = 2 -- cells across BORDER_WIDTH; row width is BORDER_WIDTH / BORDER_ROWS
local BORDER_CELL_Z = 3 -- checker cell length along the seam
local BORDER_YELLOW = C.barrelYellow
local BORDER_BLACK = C.hazardBlack

--- Derive a (dark, light) checkerboard pair from one existing colour, at roughly the
--- same brightness ratio the plaza's own hand-picked pair already sits at (measured:
--- light is ~1.14x dark, per channel, on C.plazaTileDark/plazaTileLight). Treats the
--- given colour as that pair's MIDPOINT, splitting the ratio symmetrically in
--- log-space (0.937x / 1.068x) so the input colour is recoverable as roughly the
--- average of what comes out -- used so every waypoint below stays anchored to an
--- ALREADY-SHIPPED colour (a stage's own single `color`) rather than a new palette.
local function twoToneOf(c: Color3): (Color3, Color3)
	-- clamp: the 1.068x lightening can push a near-white input (Stage 5's pink) past
	-- 1.0, which :ToHex() would otherwise clamp with a console warning on every build.
	local function ch(v: number): number
		return math.clamp(v, 0, 1)
	end
	return Color3.new(ch(c.R * 0.937), ch(c.G * 0.937), ch(c.B * 0.937)),
		Color3.new(ch(c.R * 1.068), ch(c.G * 1.068), ch(c.B * 1.068))
end
local function twoTone(hex: string): (Color3, Color3)
	return twoToneOf(Color3.fromHex(hex))
end

--- A lighter tint of a stage's floor colour: same hue, value lifted toward 1 and
--- saturation eased off, so the wall reads as the floor gone pale rather than as a
--- new colour. Stage 4's floor (near-black brown) lifts to a mid clay; Stage 5's
--- (already near-white pink) barely moves, which is correct -- there is little
--- "lighter" left to go.
local function lighterFloor(hex: string): Color3
	local h, s, v = Color3.fromHex(hex):ToHSV()
	return Color3.fromHSV(h, s * WALL_FLOOR_DESAT, v + (1 - v) * WALL_FLOOR_LIFT)
end

--- The (dark, light) hex pair for one stage's stretch of boundary wall. Stage 1 and
--- anything not a stage (id 1 is the fallback) stay the camp brown; a pinned stage
--- uses its hand-picked colour; every other stage is a lighterFloor() tint of its
--- own floor. All three paths end in the same close two-tone split every
--- checkerboard in this file uses.
local function wallPair(id: number): (string, string)
	if id == 1 then
		return WALL_BROWN_DARK, WALL_BROWN_LIGHT
	end

	local pin = WALL_STAGE_PIN[id]
	local mid = if pin then Color3.fromHex(pin) else lighterFloor(Stages.get(id).color)

	local darkC, lightC = twoToneOf(mid)
	return darkC:ToHex(), lightC:ToHex()
end

--- The (dark, light) hex pair for one stage's FLOOR checker -- twoTone(def.color), the
--- same pair buildStageCheckerboard paints the ground with. The crown caps use this
--- (via capStagePair, rather than wallPair) so a wall's crown matches the floor it is
--- "stacking", not the paler wall face under it. Stage 1's floor gradient is not
--- reproduced up here -- and Stage 1's cap is the camp green anyway (capStagePair).
local function floorPair(id: number): (string, string)
	local darkC, lightC = twoTone(Stages.get(id).color)
	return darkC:ToHex(), lightC:ToHex()
end

--- The camp apron's own ground two-tone -- the tinted plaza board colours, the same
--- pair Hub paints the apron with (and buildStageCheckerboard's Stage-1 west endpoint
--- reuses just above). buildBaseWalls' crown caps take this so the camp wall tops read
--- as the apron carried up and over, exactly as the stage caps do for their floors.
local function campCapPair(): (string, string)
	local bright = Stages.get(1).ooze.bright
	return Kit.blendHex(C.plazaTileDark, bright, Stages.GROUND_OOZE_TINT),
		Kit.blendHex(C.plazaTileLight, bright, Stages.GROUND_OOZE_TINT)
end

--- The (dark, light) crown-cap pair for the stage behind a boundary-wall column.
--- Stage 1 takes the camp apron green (campCapPair), the same as the base-camp arc --
--- ON REQUEST, so the walk out of camp reads as one continuous green rim rather than
--- flipping to sand at the x = Hub.PLAZA.maxX seam. Every other stage takes its own
--- floor two-tone, exactly as buildStageCheckerboard paints the ground.
local function capStagePair(id: number): (string, string)
	if id == 1 then
		return campCapPair()
	end
	return floorPair(id)
end

--- WHAT USED TO BE HERE: `buildStageBlend`, `oozeInset`, `STAGE_BLEND(S)`. The
--- boundaries between Stages 1-4 (the "dead-sand family") each had a 90-stud,
--- 14-step blend — a ground-colour band UNDER an ooze-colour band, both stepping
--- from one stage's hex to the next's, so "Stage 1's pale sand into Stage 2's dun tan"
--- read as one thing becoming another instead of two fields parked against each
--- other. 4/5 and 5/6 never got one on purpose: plum into pink into violet was
--- judged to read as continuous without help.
---
--- REMOVED FOR THE SAME REASON `buildGradientOozeSurface` WAS: BANDING A
--- TRANSLUCENT LAYER MAKES A SEAM, NOT A GRADIENT, REGARDLESS OF STEP COUNT. This
--- is the second time that exact bet did not pay off — the ooze half of this blend
--- was structurally identical to Stage 1's own since-removed fade (many thin Neon
--- parts at WADE_HEIGHT, abutting), and reported live at all three boundaries (1/2,
--- 2/3, 3/4) as the same floating lines. The GROUND half was not exempt either:
--- 14 abutting SmoothPlastic bands at GROUND_SKIM, even opaque-ish and barely off
--- the floor, still showed a visible seam at each boundary in the same screenshots.
---
--- Every stage boundary is a hard cut now, the same technique 4/5 and 5/6 already
--- proved clean (see the header's own "two fields parked against each other" line —
--- that description is simply accurate everywhere now, not just past Stage 4). The
--- "one thing becoming another" storytelling for 1-2-3-4 is a real loss, recorded
--- rather than hidden: if it needs to come back, it needs an actual gradient
--- (a texture/decal with a baked alpha or colour ramp), not more bands — no count
--- of abutting parts has produced a seamless result here twice running.

--- WHAT USED TO BE HERE: `buildGradientOozeSurface`. Stage 1's ooze surface was 24
--- thin Neon bands (LIFE_FADE_STEPS) stepping transparency from near-invisible at
--- the west edge up to every other stage's flat 0.82, so "life fading into a
--- wasteland" read in the ooze itself, not just the ground colour under it.
---
--- REMOVED: THE BANDS WERE VISIBLE AS FLOATING LINES, ON REPORT FROM A LIVE PLAY
--- SESSION. The comment that used to sit here argued a transparency fade's small
--- per-step delta "never creates a visible seam the way a hue change would" — the
--- premise this whole technique rode on, and the one buildStageScenery's own
--- OozeSurface comment already warns against for a HUE fade ("splitting it per
--- stage... produces hard stripes"). In practice a fade does not need a hue jump to
--- show a seam: 24 separate Neon parts sitting edge-to-edge at WADE_HEIGHT (1.1
--- studs up — "about half a leg", exactly where a seam reads as "floating" rather
--- than "in the ground") each carry their own face normals, so the boundary between
--- two nearly-identical transparencies still renders as a thin line, worst at the
--- shallow viewing angle a standing player actually has. Stage 1 now uses
--- buildStageScenery's ordinary single-part OozeSurface, same as every other stage —
--- one part has no internal boundary to show a seam at.
---
--- The "west edge feels alive, east edge doesn't" storytelling is not entirely
--- gone: the POOLS still thin out and shrink toward the west (see the `id == 1`
--- branch a little further down, and THEME's own comment above it) — that is
--- individual props being placed, not one surface split into many, so it was never
--- the source of this bug and did not need to change.

--- NO PROP LIGHTS ANY MORE, AND STAGE 4's POOLS ARE A NAMED EXCEPTION. Props and the
--- pools both used to be Neon with a PointLight every few of them, spilling that glow
--- onto the ground; the whole world went matte and unlit (see Kit.C's header). The
--- drums (`radBarrel`) and every dormant `prop()` kind are still matte under that rule
--- -- this paragraph's "no prop lights" half still holds everywhere but one place.
---
--- THE POOL LIGHTS CAME BACK, ON REQUEST, AFTER THIS PARAGRAPH SAID THEY WOULD BE THE
--- THING TO READ FIRST IF THEY EVER DID. Stage 4's ooze went Neon for the surface look
--- first (POOL_MATERIAL), which was explicitly NOT a light source on its own -- then
--- a real PointLight per pool followed, one per `oozePool` call, radius-scaled and
--- shadowless (see the light itself, in `oozePool`). It is still true nowhere else in
--- this file emits light: this is one field's puddles, not a rule change for props,
--- the drums, or any other stage.

--- Per-stage character. `props` is roughly how many set pieces to scatter; the pool
--- count scales with area so a big stage does not look empty.
--- Pool counts climb with the stage: Ash Flats is barely contaminated, the Belt is
--- more ooze than ground. That gradient is the map teaching you what "deeper" means
--- before any number on the HUD does.
---
--- REBALANCED, BACK-LOADED. The old counts (26/40/58/46/74/92) were not actually the
--- climb the comment above describes — 58 to 46 is a DIP at Stage 4, and Stage 1 was
--- already the sparsest field by a wide margin while 2 and 3 were denser than the
--- pink stages that are supposed to read as more contaminated. The new counts are a
--- clean monotonic climb, lighter everywhere (208 pools total, down from 336) and
--- specifically lighter at the front: Stages 1-3 lost roughly two thirds of their
--- pools each and now hold 21% of the field's total (was 37%), while Stages 5-6 lost
--- only a sixth to a fifth and now hold 66% of it (was 49%). Early stages should read
--- clean enough that a pool is a landmark; the Crater should still read as more ooze
--- than ground.
--- Stage 1 and 2's pool counts dropped again (10->8, 14->10) for LIFE FADING INTO A
--- DEAD WASTELAND — on top of the per-pool west-to-east thinning inside Stage 1's own
--- placement loop (buildStageScenery's `id == 1` branch, below), the stage should
--- already read sparser at a glance than the rebalance above assumed. The
--- percentages in the paragraph above are now stale by a few points, not worth
--- re-deriving for a six-pool difference.
--- `scatter = true` is what turns a field's props on -- the scatter pass in
--- buildStageScenery is gated on it (and dispatches per stage), so a field stays bare
--- until its own rework flips the flag. `props` is the item count for that field's
--- scatter:
---   Stage 1 -- chunky green bushes across the alive west half (scatterBushes),
---            then `deadProps` knee-high dead snags across the dead-tan east half
---            (scatterDeadBushes).
---   Stage 2 -- big dead trees across the whole field (scatterFieldTrees), then the
---            remains scattered over the whole field (scatterBones): `skeletons` whole
---            carcasses as landmarks, `bones` handfuls of loose bone underfoot and
---            `skulls` human skulls.
---   Stage 3 -- the same three bone counts, denser (scatterBones), and then
---            `barrels` radioactive drums dumped over the field in loads of one to
---            three (scatterBarrels). Its `kind = "sirens"` set piece is still on
---            the shelf and `props` with it -- the drums are what this field got
---            instead, and they are the only thing standing in it.
--- `skeletons`/`bones`/`skulls` belong to the two bone fields and `barrels` to Stage 3;
--- unset, and so skipped, everywhere else.
type StageTheme = {
	props: number,
	pools: number,
	kind: string,
	scatter: boolean?,
	deadProps: number?,
	skeletons: number?,
	bones: number?,
	skulls: number?,
	barrels: number?,
	signs: number?,
}
local THEME: { [number]: StageTheme } = {
	[1] = { props = 9, deadProps = 14, pools = 8, kind = "trees", scatter = true },
	-- Stage 2's bone counts. Two carcasses is the whole point of the number: one either
	-- side of the lane (scatterBones alternates), so the field always has one in view
	-- and never a pile. The loose clusters are the dense one -- 16 of them at 3-6 bones
	-- each is roughly a bone every 25 studs of walking, which reads as "this ground is
	-- littered" without ever being what you are looking at. Skulls stay rare: they are
	-- the detail that lands hardest, and lose all of it the moment there are enough of
	-- them to be scenery.
	[2] = { props = 9, pools = 10, kind = "trees", scatter = true, skeletons = 2, bones = 16, skulls = 7 },
	-- Stage 3 gets the SAME three bone passes, denser, and NOTHING ELSE -- its sirens
	-- are still on the shelf (`props`/`kind` below are untouched and unused), so this
	-- is a partial pass, not Stage 3's rework. That is most of why the two fields do
	-- not read as one: Stage 2 is a tree line with remains under it, Stage 3 is bare
	-- khaki ground with nothing standing on it at all but the remains -- which is
	-- exactly the "nothing left standing" the note under Stage 5 already claims starts
	-- here. The counts are the other half: half again the carcasses, half again the
	-- loose bone, and nearly double the human skulls. THE SKULLS ARE THE ESCALATION
	-- THAT LANDS. One field further in and the ratio of people to animals has moved --
	-- more of them got this far, fewer of them walked back out.
	-- FOURTEEN DRUMS, and the count is low because they are the field's LANDMARKS --
	-- scatterBarrels groups them into loads of one to three, so fourteen is six or
	-- seven dumps over 262 x 142 studs of ground and you cross most of the field
	-- between them. This is the one prop out here tall enough and saturated enough to
	-- navigate by, which is worth more than cover: enough of them to steer by, never
	-- so many that the ground stops reading as empty.
	[3] = { props = 40, pools = 20, kind = "sirens", scatter = true, skeletons = 3, bones = 24, skulls = 12, barrels = 14 },
	-- The rest of THIS pass (`props`/`pools`/`kind = "barriers"`) is still on the
	-- shelf -- `scatter` only turns on the sign rank below. FIVE signs, spread over
	-- the entrance's 142-stud width (2 * hz, hz = 170/2 - 14): one roughly every 28
	-- studs, enough that one is always in view crossing in from Stage 3 without the
	-- rank reading as a fence.
	-- 26 -> 12 POOLS ON REPORT ("way too many"), and the count is only half of that
	-- fix: the 26 were all rolled out of one 9-24 stud range, so the field read as
	-- spotty -- many puddles, all the same size, all the same roughly-round shape.
	-- The 12 are dealt off a size ladder in scatterOozePools (one mini lake, a few
	-- broad, some mid, the rest spills), so this number is now "how many pools" and
	-- NOT "how much ooze" -- the lake alone covers more ground than a third of the
	-- old 26 did. Retune the ladder there, not just this number.
	[4] = { props = 18, pools = 12, kind = "barriers", scatter = true, signs = 5 },
	-- The two pink stages. Pool counts climb with the rads because the pools ARE the
	-- colour — the plate underneath is deliberately muted, so a field with few pools
	-- reads as dark ground rather than as hot ground. Prop counts do not climb with
	-- them: past Stage 3 the story is that there is nothing left standing.
	[5] = { props = 22, pools = 60, kind = "reactor" },
	[6] = { props = 26, pools = 78, kind = "shards" },
}

--- ── The radioactive drum ─────────────────────────────────────────────────────
--- The 55-gallon steel drum: hazard yellow, a chime hoop at each end, two rolling
--- ribs round the belly, a black-and-yellow hazard band under each chime, and the
--- trefoil painted on the side. Stage 3's set piece (`scatterBarrels`).
---
--- WHAT USED TO BE HERE: `barrel()`, a DORMANT two-part stand-in — one plain cylinder
--- plus a translucent spill disc — kept as the reference implementation while the
--- fields waited for their rework. Stage 3's pass is that rework, and the stand-in is
--- not what it wanted: the old drum carried no markings at all, so nothing about it
--- said radioactive, which is the entire reason one is standing in a fallout field.
--- Git history has it if the spill is ever wanted back.
---
--- EVERY PIECE IS BUILT IN THE DRUM'S OWN FRAME, standing on local y = 0 with its axis
--- up local Y. `base` carries the pose — upright, leaning, on its side — so one set of
--- geometry covers all three and no angle in here has to know which it got.
--- `scatterBarrels` is what tips them.
---
--- THE HAZARD BAND IS A BLACK RING WITH THE DRUM'S OWN YELLOW LAID BACK OVER IT in
--- diagonal slats, not black slats on a yellow drum, and that is the whole trick to a
--- clean band: a diagonal stripe necessarily overhangs the top and bottom of the band
--- it sits in, and yellow overhanging onto a yellow drum is invisible where black
--- would fringe. DRUM_SLATS is a hard constraint, not a taste call — a tilted stripe
--- reaches further round the drum than its own width (0.59 studs of envelope at
--- DRUM_STRIPE_TILT against a 0.67-stud gap between slats), so twelve slats clear each
--- other and fourteen would cross.
---
--- THE TREFOIL IS WRAPPED ONTO THE SHELL PIECE BY PIECE rather than laid out on one
--- flat plate tangent at its centre. The symbol is nearly a stud across on a 2.5-stud
--- drum, and a single plate that wide floats its far corners a tenth of a stud off the
--- curve, which reads as a sticker peeling off. `decal` gives every block its own
--- tangent point instead: measured on the built drums, a blade's far corner lifts
--- 0.014 studs further off the curve than the middle of that same blade does.
local DRUM_H = 4.0
local DRUM_R = 1.25
--- How far proud of the shell the rolled ends stand, and the two belly ribs. The chime
--- is a named constant rather than a number inside the builder because a FALLEN drum
--- rests on its chimes, not on its shell — `scatterBarrels` needs the same figure to
--- set one down on the ground correctly.
local DRUM_CHIME = 0.17
local DRUM_RIB = 0.09
local DRUM_BAND_H = 0.62
local DRUM_SLATS = 12
local DRUM_STRIPE_TILT = 30 -- degrees off the drum's axis
--- Painted markings float this far off the shell — enough never to z-fight the curve
--- under them, small enough to read as paint rather than as a plate bolted on.
local DRUM_PAINT = 0.04

local function radBarrel(parent: Instance, base: CFrame, rng: Random)
	local drum = Instance.new("Model")
	drum.Name = "Barrel"

	-- Roughly a quarter of them have been lying out here long enough to lose their
	-- paint. Blended toward the rust rather than given a second hex of their own, so a
	-- weathered drum stays recognisably the SAME drum — the markings still read, they
	-- are just sitting on a dirtier yellow.
	local body = if rng:NextNumber() < 0.26 then Kit.blendHex(C.barrelYellow, C.barrelRust, 0.4) else C.barrelYellow
	local trim = Kit.blendHex(body, "FFFFFF", 0.13)

	--- One flat piece lying on the shell, placed in the drum's UNROLLED surface: `deg`
	--- is where round the drum, `du` a further distance along the circumference from
	--- there, `dv` a distance up the axis, and `roll` a spin about the outward normal.
	--- The frame handed to `build` has +X across the surface, +Y up it and +Z out of
	--- it, so `size` reads as {width, height, thickness} for every caller — including a
	--- `disc`, which is re-ordered here rather than at the call site (a Roblox
	--- cylinder's axis being its X size is a fact about the engine, and has no business
	--- leaking into the code that says what the trefoil looks like).
	local function decal(
		name: string,
		deg: number,
		y: number,
		du: number,
		dv: number,
		roll: number,
		size: { number },
		color: string,
		disc: boolean?
	)
		local at = deg + math.deg(du / DRUM_R)
		local th = math.rad(at)
		local on = base
			* CFrame.new((DRUM_R + DRUM_PAINT) * math.sin(th), y + dv, (DRUM_R + DRUM_PAINT) * math.cos(th))
			* Kit.ang(0, at, 0)
			* Kit.ang(0, 0, roll)

		build(drum, on * (if disc then Kit.ang(0, 90, 0) else R.flat), {
			name = name,
			pos = { 0, 0, 0 },
			size = if disc then { size[3], size[1], size[2] } else size,
			color = color,
			material = "Metal",
			shape = if disc then "Cylinder" else "Block",
			canCollide = false,
		})
	end

	build(drum, base, {
		name = "Shell",
		pos = { 0, DRUM_H / 2, 0 },
		size = { DRUM_H, DRUM_R * 2, DRUM_R * 2 },
		color = body,
		material = "Metal",
		shape = "Cylinder",
		rot = R.cylUp,
		canCollide = false,
	})

	-- The four raised rings: a chime at each end, two rolling ribs round the belly.
	-- They are what keeps a drum from reading as a plain tube at the distance its
	-- markings have already stopped resolving at.
	for _, ring in { { 0.18, DRUM_CHIME }, { DRUM_H - 0.18, DRUM_CHIME }, { DRUM_H * 0.32, DRUM_RIB }, { DRUM_H * 0.68, DRUM_RIB } } do
		build(drum, base, {
			name = "Rib",
			pos = { 0, ring[1], 0 },
			size = { 0.34, (DRUM_R + ring[2]) * 2, (DRUM_R + ring[2]) * 2 },
			color = trim,
			material = "Metal",
			shape = "Cylinder",
			rot = R.cylUp,
			canCollide = false,
		})
	end

	-- The lid, sitting down inside the top chime the way a rolled seam does, and the
	-- bung cap off to one side of it — the one piece of bare metal on the whole drum,
	-- and the detail that says "this opens" rather than "this is a cylinder".
	build(drum, base, {
		name = "Lid",
		pos = { 0, DRUM_H - 0.02, 0 },
		size = { 0.10, DRUM_R * 2 - 0.12, DRUM_R * 2 - 0.12 },
		color = trim,
		material = "Metal",
		shape = "Cylinder",
		rot = R.cylUp,
		canCollide = false,
	})
	build(drum, base, {
		name = "Bung",
		pos = { DRUM_R * 0.46, DRUM_H + 0.08, DRUM_R * 0.24 },
		size = { 0.14, 0.40, 0.40 },
		color = C.steelDark,
		material = "Metal",
		shape = "Cylinder",
		rot = R.cylUp,
		canCollide = false,
	})

	-- The two hazard bands. Both clear every ring above and below them: the lower one
	-- sits between the bottom chime and the lower rib, the upper one between the upper
	-- rib and the top chime, which is the only place on a four-ringed drum a 0.62-stud
	-- band fits without a rib cutting through it.
	for _, y in { 0.70, DRUM_H - 0.74 } do
		build(drum, base, {
			name = "HazardBand",
			pos = { 0, y, 0 },
			size = { DRUM_BAND_H, (DRUM_R + 0.01) * 2, (DRUM_R + 0.01) * 2 },
			color = C.hazardBlack,
			material = "Metal",
			shape = "Cylinder",
			rot = R.cylUp,
			canCollide = false,
		})
		-- A stripe is exactly as long as it takes to cross the band at the tilt, so its
		-- ends land on the band's own edges and the black ring is what defines them.
		local slat = DRUM_BAND_H / math.cos(math.rad(DRUM_STRIPE_TILT))
		for i = 0, DRUM_SLATS - 1 do
			decal("HazardStripe", i * (360 / DRUM_SLATS), y, 0, 0, DRUM_STRIPE_TILT, { 0.27, slat, 0.05 }, body)
		end
	end

	-- The trefoil, on the belly between the two rolling ribs: a centre disc and three
	-- blades 120 degrees apart, each blade a narrow inner block and a wider outer one.
	-- A stepped taper is as close to a 60-degree pie sector as a world built out of
	-- blocks gets, and at the range the symbol actually reads from, the step is not
	-- what you see — the three-bladed rosette is. The proportions are the real
	-- symbol's: blades running from one and a half to five times the hub's radius.
	local face = rng:NextNumber(0, 360)
	local waist = DRUM_H / 2
	decal("TrefoilHub", face, waist, 0, 0, 0, { 0.20, 0.20, 0.05 }, C.hazardBlack, true)
	for i = 0, 2 do
		local phi = math.rad(i * 120)
		for _, blade in { { 0.220, 0.22 }, { 0.385, 0.38 } } do
			decal(
				"TrefoilBlade",
				face,
				waist,
				blade[1] * math.sin(phi),
				blade[1] * math.cos(phi),
				-i * 120,
				{ blade[2], 0.17, 0.05 },
				C.hazardBlack
			)
		end
	end

	drum.Parent = parent
end
--- Stage-specific silhouette, so the four fields do not read as one field.
--- `ooze` is the STAGE's Neon triple (Config/Stages StageDef.ooze), not a global. Only
--- the two pink kinds read it today — the older kinds are lit in their own prop
--- colours, which is correct: a rusted siren head is rust everywhere. Anything a prop
--- glows with because the FIELD is hot has to come from here, or Reactor Grounds gets
--- acid-green vents standing in a hot pink field.
--- A rounded, FACETED clump of foliage — the "low-poly toy tree" look (reference:
--- a chunky rounded canopy built from visible flat cube facets, not a smooth
--- sphere or one flat box) has to come from many small cube blocks jittered
--- inside a sphere, since this generator only has Block/Cylinder/Ball/Wedge to
--- work with. Distance is weighted toward the sphere's surface so the clump
--- reads as a full round mass rather than clumping in the middle, and every
--- cube gets its own small random tilt so the facets actually show — a grid of
--- axis-aligned cubes reads as a cube pile, not a rounded blob.
local function foliageBlob(parent: Instance, origin: CFrame, center: { number }, radius: number, color: string, darkColor: string, rng: Random)
	for _ = 1, rng:NextInteger(7, 10) do
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 1), rng:NextNumber(-1, 1))
		if dir.Magnitude < 0.05 then
			dir = Vector3.new(0, 1, 0)
		end
		dir = dir.Unit
		local dist = radius * rng:NextNumber(0.35, 1)
		local size = rng:NextNumber(radius * 0.55, radius * 0.85)
		build(parent, origin, {
			name = "Foliage",
			pos = { center[1] + dir.X * dist, center[2] + dir.Y * dist, center[3] + dir.Z * dist },
			size = { size, size, size },
			color = if rng:NextNumber() < 0.25 then darkColor else color,
			material = "SmoothPlastic",
			rot = Kit.ang(rng:NextNumber(0, 45), rng:NextNumber(0, 90), rng:NextNumber(0, 45)),
			canCollide = false,
		})
	end
	-- A couple of little berries, half-sunk into the surface so they read as
	-- growing out of the foliage rather than floating on top of it.
	for _ = 1, rng:NextInteger(1, 2) do
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.2, 1), rng:NextNumber(-1, 1)).Unit
		local dist = radius * rng:NextNumber(0.75, 1)
		build(parent, origin, {
			name = "Berry",
			pos = { center[1] + dir.X * dist, center[2] + dir.Y * dist, center[3] + dir.Z * dist },
			size = { 0.6, 0.6, 0.6 },
			color = "C23B3B",
			material = "SmoothPlastic",
			shape = "Ball",
			canCollide = false,
		})
	end
end

--- A bare, forked dead tree (reference: a low-poly wasteland snag -- a tapered angular
--- trunk that carries up through the crown while two or three limbs fork off it, each
--- forking again into branches that lean outward and taper to sharp points).
---
--- Built the only way this generator can: square-section Block segments for the wood,
--- a Wedge cap on every tip, studded on every face like the floor and walls. SQUARE
--- section, not Cylinder, on purpose -- the hard edges and studded facets ARE the
--- look, a round trunk reads as a telephone pole. Each segment carries a small roll so
--- an edge faces out rather than a flat face.
---
--- Recurses down a length/thickness ramp. Everything CanCollide=false (walk through
--- it) and thin -- the same rules the file header sets for anything tall over a dig
--- field, and the same the old one-box DeadTree followed.
local function deadTree(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	local base = origin * CFrame.new(x, 0, z) * Kit.ang(0, rng:NextNumber(0, 360), 0)

	-- depth 4..3 = trunk: two thick, near-vertical segments. The split happens at the
	-- TOP of depth 3, so a clear tall trunk stands before anything forks -- the
	-- reference's proportions, not a shrub branching from the ground.
	-- depth 2 = main limbs, depth 1 = branches, depth 0 = twig + point.
	local function branch(cf: CFrame, length: number, thick: number, depth: number)
		local isTrunk = depth >= 3
		build(parent, cf, {
			name = if isTrunk then "Trunk" else "Limb",
			pos = { 0, length / 2, 0 },
			size = { thick, length, thick },
			color = if rng:NextNumber() < 0.28 then DEAD_WOOD_DARK else DEAD_WOOD,
			material = "Plastic",
			studs = true, -- studded like everything else in this world (floor, walls, bushes)
			-- Barely any roll on the trunk (a visible kink there reads as broken, not
			-- weathered); the crown can twist more freely.
			rot = Kit.ang(0, 0, if isTrunk then rng:NextNumber(-2, 2) else rng:NextNumber(-6, 6)),
			canCollide = false,
		})

		local tip = cf * CFrame.new(0, length, 0)

		if depth == 0 then
			-- The point. One Wedge tapers in a single plane -- from the angles a player
			-- sees a field prop that reads as a flattened spike, which is the
			-- reference's branch tips. Kept roughly in line with the twig, not yawed
			-- randomly, so it does not stick out sideways.
			build(parent, tip * Kit.ang(0, rng:NextNumber(-20, 20), 0), {
				name = "Tip",
				pos = { 0, thick * 0.9, 0 },
				size = { thick * 0.7, thick * 1.9, thick * 0.7 },
				color = DEAD_WOOD_DARK,
				material = "Plastic",
				studs = true,
				shape = "Wedge",
				canCollide = false,
			})
			return
		end

		-- The stem carries straight on past every fork -- almost dead vertical through
		-- the trunk, leaning more up in the crown -- so the trunk reads as running all
		-- the way up through it. Trunk segments keep their bearing (no yaw before the
		-- lean) so the two-piece trunk stays a clean line.
		if isTrunk then
			branch(
				tip * Kit.ang(rng:NextNumber(0, 3), 0, rng:NextNumber(-3, 3)),
				length * rng:NextNumber(0.82, 0.92),
				thick * rng:NextNumber(0.85, 0.93),
				depth - 1
			)
		else
			branch(
				tip * Kit.ang(0, rng:NextNumber(0, 360), 0) * Kit.ang(rng:NextNumber(6, 16), 0, 0),
				length * rng:NextNumber(0.76, 0.9),
				thick * rng:NextNumber(0.64, 0.8),
				depth - 1
			)
		end

		-- Side limbs fork off at the trunk top (2-3) and the primary limbs (1-2); past
		-- that a limb just runs to its point. Each takes its own bearing and leans out
		-- from vertical -- further the higher it is, so the tree reaches up then spreads.
		-- Kept long (little length drop) so the crown is a few reaching branches, not a
		-- tight ball of stubs.
		local forks = if depth == 3 then rng:NextInteger(2, 3) elseif depth == 2 then rng:NextInteger(1, 2) else 0
		local yaw0 = rng:NextNumber(0, 360)
		for i = 1, forks do
			local yaw = yaw0 + (i - 1) * (360 / forks) + rng:NextNumber(-24, 24)
			local lean = if depth == 3 then rng:NextNumber(18, 32) else rng:NextNumber(26, 42)
			branch(
				tip * Kit.ang(0, yaw, 0) * Kit.ang(lean, 0, 0),
				length * rng:NextNumber(0.66, 0.82),
				thick * rng:NextNumber(0.55, 0.7),
				depth - 1
			)
		end
	end

	-- Per-tree size. `scale` is rolled wide so the stand still has clearly smaller and
	-- clearly bigger trees, but the whole band sits high -- these are looming dead
	-- giants over the field, not scrub. Length and thickness scale together so a
	-- smaller tree is a proportionally smaller tree, never a thin tall one. Everything
	-- downstream is a ratio of this trunk-base pair; the roll spans ~30 studs tall to
	-- ~45 (the tallest is ~9 characters).
	local scale = rng:NextNumber(1.2, 1.8)
	branch(base, rng:NextNumber(5.2, 6.2) * scale, rng:NextNumber(2.5, 3.1) * scale, 4)
end

--- A knee-high dead shrub -- `deadTree` shrunk to scrub height and made to fork at the
--- ground rather than carry a clear trunk first, and to SPLAY low and wide rather than
--- reach up: a dead bush sprawls, it does not stand. Same square-section studded
--- segments, same Wedge tips, same DEAD_WOOD palette as the trees, so the east end of
--- Stage 1 reads as one dying stand at two scales. CanCollide=false and low, like every
--- field prop over a dig plate.
local function deadBush(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	local base = origin * CFrame.new(x, 0, z) * Kit.ang(0, rng:NextNumber(0, 360), 0)

	-- depth 2 = the stub, depth 1 = splayed limbs, depth 0 = twig + point. Mirrors
	-- deadTree.branch but every lean angle is wider and every length drop steeper.
	local function twig(cf: CFrame, length: number, thick: number, depth: number)
		build(parent, cf, {
			name = "DeadBush",
			pos = { 0, length / 2, 0 },
			size = { thick, length, thick },
			color = if rng:NextNumber() < 0.3 then DEAD_WOOD_DARK else DEAD_WOOD,
			material = "Plastic",
			studs = true,
			rot = Kit.ang(0, 0, rng:NextNumber(-5, 5)),
			canCollide = false,
		})

		local tip = cf * CFrame.new(0, length, 0)

		if depth == 0 then
			build(parent, tip * Kit.ang(0, rng:NextNumber(-20, 20), 0), {
				name = "Tip",
				pos = { 0, thick * 0.8, 0 },
				size = { thick * 0.7, thick * 1.7, thick * 0.7 },
				color = DEAD_WOOD_DARK,
				material = "Plastic",
				studs = true,
				shape = "Wedge",
				canCollide = false,
			})
			return
		end

		-- The stem carries on, leaning outward; 2-3 limbs fork off the stub, 0-1 off a
		-- limb. Wide leans (up to ~58 degrees) are what make it sprawl.
		twig(
			tip * Kit.ang(0, rng:NextNumber(0, 360), 0) * Kit.ang(rng:NextNumber(10, 24), 0, 0),
			length * rng:NextNumber(0.62, 0.8),
			thick * rng:NextNumber(0.6, 0.78),
			depth - 1
		)
		local forks = if depth == 2 then rng:NextInteger(2, 3) else rng:NextInteger(0, 1)
		local yaw0 = rng:NextNumber(0, 360)
		for i = 1, forks do
			local yaw = yaw0 + (i - 1) * (360 / forks) + rng:NextNumber(-28, 28)
			twig(
				tip * Kit.ang(0, yaw, 0) * Kit.ang(rng:NextNumber(34, 58), 0, 0),
				length * rng:NextNumber(0.5, 0.7),
				thick * rng:NextNumber(0.5, 0.66),
				depth - 1
			)
		end
	end

	-- Short and stout. Everything downstream is a ratio of this pair; the roll spans
	-- roughly a 2.5-stud snag to a 4.5-stud one -- knee to thigh, never tree height.
	local scale = rng:NextNumber(0.85, 1.35)
	twig(base, rng:NextNumber(1.5, 2.0) * scale, rng:NextNumber(0.7, 0.95) * scale, 2)
end

--- A chunky low-poly bush: three or four fat cube-ish blocks packed tightly together
--- and tilted, some stacked, so they overlap into one rounded green mass (reference: a
--- cluster of big rounded blocks, not the many-small-cube blob foliageBlob makes, and
--- not a few spread-out crates). The first block sits on the ground; the rest are
--- offset only a little and can ride up on top of it. Each block picks its own green
--- from the two-tone so the facets read against each other and the bush pops off the
--- grass. CanCollide=false and low enough to see over, like the old "brush" kind.
local function bush(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	local base = origin * CFrame.new(x, 0, z) * Kit.ang(0, rng:NextNumber(0, 360), 0)
	local n = rng:NextInteger(3, 4)
	local s = rng:NextNumber(4.2, 5.3) -- the base block's size; the whole bush scales off it

	for i = 1, n do
		-- Each block above the base is a step smaller and rides higher, so the cluster
		-- builds into a rounded MOUND rather than sprawling flat.
		local k = 1 - (i - 1) * 0.17
		local w = s * k * rng:NextNumber(0.86, 1.08)
		local h = s * k * rng:NextNumber(0.8, 1.0)
		local d = s * k * rng:NextNumber(0.86, 1.08)
		local ox = if i == 1 then 0 else rng:NextNumber(-1.6, 1.6)
		local oz = if i == 1 then 0 else rng:NextNumber(-1.6, 1.6)
		local oy = if i == 1 then 0 else (i - 1) * s * 0.3 + rng:NextNumber(-0.5, 0.5)
		-- Base block sunk ~0.4 stud so the bush grows out of the grass, not off it.
		-- Studded on every face like the floor, the walls and the trees -- a tilted,
		-- stacked block shows more than its top, so all six.
		build(parent, base, {
			name = "Bush",
			pos = { ox, h / 2 - 0.4 + oy, oz },
			size = { w, h, d },
			color = if rng:NextNumber() < 0.55 then BUSH_GREEN else BUSH_GREEN_DARK,
			material = "Plastic",
			studs = true,
			rot = Kit.ang(rng:NextNumber(-12, 12), rng:NextNumber(0, 90), rng:NextNumber(-12, 12)),
			canCollide = false,
		})
	end
end

--- ── THE REMAINS ──────────────────────────────────────────────────────────────
--- Stage 1 is life dying back (green scrub in the west, dead snags in the east);
--- Stages 2 and 3 are what the die-off left behind. The bones are the whole
--- storytelling job of both fields -- a suburb the animals did not walk out of, then
--- open ground where more of them and more of US did not either -- and they come at
--- three scales on request: loose bones scattered underfoot, whole articulated
--- carcasses as landmarks, and human skulls.
---
--- NOTHING HERE IS PER-STAGE. Every builder below takes its size and its pose from its
--- caller, so the two fields differ only in how many of each they scatter, how far off
--- the lane the carcasses may sit, and what else is standing in the field with them
--- (Stage 2, a tree line; Stage 3, nothing). Keep it that way -- one weathered-bone
--- palette and one set of proportions is what makes the two fields read as the same
--- disaster rather than as two art passes.
---
--- All of them obey this file's two standing rules for anything sitting over a dig
--- plate: CanCollide=false (walk through it, never get wedged inside a rib cage) and
--- open or low enough that a haul rising to the surface underneath is still visible --
--- a rib cage is a hoop of thin bars with daylight through it, not a dome.

--- One bone, grown along +Y from `cf`: a square-section shaft with a knuckle swelling
--- at each end. THE KNUCKLES ARE THE WHOLE TRICK. A bare shaft reads as a stick --
--- it is exactly what `deadTree` already builds -- and this generator has no capsule
--- or sphere cap to round an end with, so the joint has to be modelled as its own
--- slightly fatter box. Square section and studded, same as the trees and the bushes.
local function boneShaft(parent: Instance, cf: CFrame, length: number, thick: number, rng: Random)
	build(parent, cf, {
		name = "Bone",
		pos = { 0, length / 2, 0 },
		size = { thick, length, thick },
		color = if rng:NextNumber() < 0.25 then BONE_DARK else BONE,
		material = "Plastic",
		studs = true,
		rot = Kit.ang(0, 0, rng:NextNumber(-4, 4)),
		canCollide = false,
	})

	for _, at in { 0, length } do
		build(parent, cf, {
			name = "Knuckle",
			pos = { 0, at, 0 },
			size = { thick * 1.5, thick * 1.2, thick * 1.5 },
			color = BONE,
			material = "Plastic",
			studs = true,
			rot = Kit.ang(0, rng:NextNumber(-14, 14), 0),
			canCollide = false,
		})
	end
end

--- A curving run of bone -- a rib, a horn, a neck, a tail -- as `segs` shafts each
--- pitched a further `curve` degrees off the last and tapering as it goes. Returns the
--- CFrame at the far tip so a caller can hang the next thing off the end of it.
---
--- Pitch is about the frame's local X, so a caller aims the whole bow by yawing `cf`
--- BEFORE calling: the ribs below yaw nothing and bend out across Z, the horns yaw 90
--- so the same bend runs across X instead.
---
--- NO KNUCKLES, unlike boneShaft: a rib is one continuous bow, and a swelling at every
--- segment join reads as a caterpillar rather than as a curve.
local function boneArc(
	parent: Instance,
	cf: CFrame,
	name: string,
	segs: number,
	length: number,
	thick: number,
	curve: number,
	rng: Random
): CFrame
	local at = cf
	for _ = 1, segs do
		build(parent, at, {
			name = name,
			pos = { 0, length / 2, 0 },
			size = { thick, length, thick },
			color = if rng:NextNumber() < 0.25 then BONE_DARK else BONE,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
		at = at * CFrame.new(0, length, 0) * Kit.ang(curve + rng:NextNumber(-2.5, 2.5), 0, 0)
		length *= 0.93
		thick *= 0.95
	end
	return at
end

--- A skull resting on the ground, facing its frame's local +Z. `s` scales the whole
--- thing off a ~1.6-stud-wide human braincase -- s = 1 is a little larger than a
--- character's own head, which is what a skull has to be to read as one at all from
--- standing height.
---
--- `animal` swaps the short human jaw for a long muzzle, moves the eyes from the FRONT
--- of the face to the SIDES of it, and adds a pair of upswept horns. That eye move is
--- the whole difference between "a person died here" and "a beast died here" at a
--- glance, and it is why both come out of one function: the two have to read as the
--- same material and the same hand, only different animals.
---
--- Boxes only, studded, same as every other prop in this file. The sockets and the
--- mouth line are flat near-black faces sitting a hair proud of the bone around them:
--- there is no boolean subtract here to carve a real hollow with, and a dark face
--- reads as one at every distance a player actually sees this from.
local function skull(parent: Instance, base: CFrame, s: number, animal: boolean, rng: Random)
	--- One box in skull-local units, `s` applied on the way out: x across the face,
	--- y up from the ground it sits on, z toward the snout.
	local function box(name: string, size: { number }, pos: { number }, color: string)
		build(parent, base, {
			name = name,
			pos = { pos[1] * s, pos[2] * s, pos[3] * s },
			size = { size[1] * s, size[2] * s, size[3] * s },
			color = color,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end

	if animal then
		-- Long-muzzled and horned: cattle, deliberately -- a short-muzzled skull at
		-- this scale reads as somebody's dog, which is a different and much less
		-- welcome thing to leave lying in a field.
		box("Cranium", { 1.5, 1.2, 1.4 }, { 0, 1.1, -0.4 }, BONE)
		box("Muzzle", { 0.95, 0.85, 1.9 }, { 0, 0.85, 1.15 }, BONE)
		box("Jaw", { 0.85, 0.42, 1.8 }, { 0, 0.3, 1.05 }, BONE_DARK)
		box("MouthGap", { 0.8, 0.14, 1.76 }, { 0, 0.53, 1.05 }, BONE_HOLLOW)
		for _, side in { 1, -1 } do
			box("EyeSocket", { 0.2, 0.44, 0.46 }, { side * 0.66, 1.18, -0.15 }, BONE_HOLLOW)
			box("Nostril", { 0.18, 0.22, 0.16 }, { side * 0.22, 0.98, 2.04 }, BONE_HOLLOW)
			-- Out from the top corner, then curving back toward upright: the arc opens
			-- wide and RECOVERS (negative curve), which is what makes a horn a horn
			-- rather than a drooping tusk.
			--
			-- LOW AND LONG, not tall. The first pass left at 54 degrees off vertical and
			-- recovered 17 a segment, which lands almost upright by the tip -- read live
			-- as a pair of ears, not horns. Leaving wider (62) and recovering less (14)
			-- keeps the sweep mostly HORIZONTAL, so the silhouette is a longhorn's span
			-- rather than a crown. Thin, too: a horn as thick as a leg bone reads as one.
			boneArc(
				parent,
				base * CFrame.new(side * 0.55 * s, 1.5 * s, -0.45 * s) * Kit.ang(0, side * 90, 0) * Kit.ang(62, 0, 0),
				"Horn",
				3,
				0.9 * s,
				0.3 * s,
				-14,
				rng
			)
		end
		return
	end

	-- Human. Four things carry the read, in this order of importance: the two sockets,
	-- the TEETH, the nasal notch, and the taper from braincase down to jaw. The first
	-- pass had no teeth and sat low enough in the ground that the mouth was under the
	-- floor -- a cube with two dark squares in it, which reads as a ghost, not a skull.
	-- Everything below the eyes is why it now reads as the second one.
	--
	-- The crown block is what keeps the braincase itself from reading as a plain cube:
	-- one step in at the top is the cheapest dome this generator can build.
	box("Cranium", { 1.5, 1.35, 1.55 }, { 0, 1.25, -0.05 }, BONE)
	box("Crown", { 1.25, 0.36, 1.3 }, { 0, 2, -0.1 }, BONE)
	-- A slim ledge, in bone rather than shadow: full-width and dark, the first pass's
	-- brow read as a headband strapped across the forehead.
	box("Brow", { 1.34, 0.15, 0.11 }, { 0, 1.6, 0.74 }, BONE)
	box("Nose", { 0.24, 0.32, 0.2 }, { 0, 0.94, 0.635 }, BONE_HOLLOW)
	for _, side in { 1, -1 } do
		box("EyeSocket", { 0.42, 0.4, 0.2 }, { side * 0.34, 1.36, 0.635 }, BONE_HOLLOW)
	end

	-- The face below the eyes: a narrower block than the braincase (the taper is what
	-- makes it a head rather than a box), a dark mouth band across it, and four teeth
	-- straddling that band. Four is enough -- the eye reads "row of teeth" off any
	-- interruption of a dark line, and one tooth per stud of face is a portcullis.
	box("Maxilla", { 1.1, 0.55, 1.15 }, { 0, 0.44, 0.12 }, BONE)
	box("MouthGap", { 0.96, 0.26, 0.96 }, { 0, 0.3, 0.16 }, BONE_HOLLOW)
	for _, at in { -0.39, -0.13, 0.13, 0.39 } do
		box("Tooth", { 0.13, 0.26, 0.12 }, { at, 0.3, 0.64 }, BONE)
	end
	box("Jaw", { 1, 0.3, 1 }, { 0, 0.12, 0.2 }, BONE_DARK)
end

--- A whole animal where it dropped: a backbone carrying a hooped rib cage, a neck
--- arcing down to a skull resting on the ground, a flared pelvis, four splayed legs
--- and a tail trailing off behind. STAGE 2'S LANDMARK PROP -- one of these is a thing
--- you point at from across the field, which is what a stage whose only other prop is
--- "another dead tree" was short of.
---
--- Laid out along the frame's local +X, nose end forward: thirteen vertebrae with the
--- ribs on the middle six and the pelvis back near the tail. THE RIB BOWS ARE THE
--- LOAD-BEARING DETAIL. Each is a `boneArc` that leaves the spine almost horizontal
--- and keeps bending until it comes back down to the ground and starts to turn under,
--- so the cage reads as a closed barrel in silhouette while staying a see-through cage
--- of thin bars from every angle -- which is the rule this section's header sets for
--- anything standing over a dig plate.
---
--- Everything is a ratio of `s` (the carcass scale) and `seg` (the vertebra pitch), so
--- the roll at the top resizes the whole animal proportionally rather than producing a
--- long thin one.
local function animalSkeleton(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	local base = origin * CFrame.new(x, 0, z) * Kit.ang(0, rng:NextNumber(0, 360), 0)
	local s = rng:NextNumber(0.8, 1.05) -- whole-carcass scale
	local seg = 1.7 * s -- vertebra pitch along the spine
	local spineY = 4.0 * s -- the backbone's height off the ground
	local VERTEBRAE = 13
	local mid = (VERTEBRAE - 1) / 2

	-- The backbone. Blocks spaced a clear gap apart (each box is well under `seg`
	-- wide) so the chain reads as beads rather than as one bar, each with a dorsal fin
	-- on top. The fins peak over the shoulders and fall away to nothing at both ends --
	-- that tent, not the spine itself, is what gives the silhouette a withers.
	for i = 0, VERTEBRAE - 1 do
		local t = i / (VERTEBRAE - 1)
		local vx = (i - mid) * seg
		local fin = s * (0.35 + 0.9 * math.max(0, 1 - math.abs(t - 0.66) / 0.42))

		build(parent, base, {
			name = "Vertebra",
			pos = { vx, spineY, 0 },
			size = { seg * 0.62, 0.95 * s, 1.15 * s },
			color = if rng:NextNumber() < 0.22 then BONE_DARK else BONE,
			material = "Plastic",
			studs = true,
			rot = Kit.ang(0, rng:NextNumber(-5, 5), rng:NextNumber(-4, 4)),
			canCollide = false,
		})
		build(parent, base, {
			name = "SpineFin",
			pos = { vx, spineY + 0.45 * s + fin / 2, 0 },
			size = { seg * 0.32, fin, 0.5 * s },
			color = BONE,
			material = "Plastic",
			studs = true,
			rot = Kit.ang(rng:NextNumber(-6, 6), 0, rng:NextNumber(-7, 7)),
			canCollide = false,
		})
	end

	-- The cage. Six pairs, the middle pairs reaching furthest so the barrel tapers at
	-- both ends instead of reading as a culvert. Each side takes the SAME bow mirrored
	-- (`side` flips both the start pitch and the bend), which is the only way a pair
	-- meets underneath rather than crossing.
	for i = 4, 9 do
		local vx = (i - mid) * seg
		local t = (i - 4) / 5
		local reach = 1.62 * s * (0.84 + 0.16 * math.sin(t * math.pi))
		for _, side in { 1, -1 } do
			boneArc(parent, base * CFrame.new(vx, spineY, 0) * Kit.ang(side * 72, 0, 0), "Rib", 6, reach, 0.34 * s, side * 30, rng)
		end
	end

	-- The neck leaves the shoulders near level and keeps curving until it reaches the
	-- ground: the head went down first and stayed there. The skull sits just past the
	-- end of it, upright and facing forward -- a head lying ON the ground at the end of
	-- a dropped neck is the pose that reads as "died here", where a head held up on a
	-- straight neck reads as a museum mount.
	local neckX = (mid + 0.4) * seg
	boneArc(parent, base * CFrame.new(neckX, spineY, 0) * Kit.ang(0, 90, 0) * Kit.ang(72, 0, 0), "Neck", 6, 1.5 * s, 0.55 * s, 26, rng)
	skull(
		parent,
		base * CFrame.new(neckX + 5.1 * s, -0.1 * s, 0) * Kit.ang(0, 90 + rng:NextNumber(-12, 12), 0) * Kit.ang(0, 0, rng:NextNumber(-8, 8)),
		1.7 * s,
		true,
		rng
	)

	-- The hips: a flared plate either side, tipped down and out. Rotating about X tips
	-- the plate's own depth, which is what turns a flat slab into a hip you can read
	-- the angle of from the side.
	local hipX = -(mid - 1.4) * seg
	for _, side in { 1, -1 } do
		build(parent, base, {
			name = "Pelvis",
			pos = { hipX, spineY - 0.75 * s, side * 1.35 * s },
			size = { 2.4 * s, 0.5 * s, 1.9 * s },
			color = BONE,
			material = "Plastic",
			studs = true,
			rot = Kit.ang(side * 38, 0, 0),
			canCollide = false,
		})
	end

	--- One leg, splayed out from under the body and folded at the knee: a femur, a
	--- shin and a hoof block. Aimed outward across Z by yawing the frame (0 or 180) and
	--- then pitching PAST horizontal, so the leg runs out and DOWN rather than out and
	--- up; the knee adds a second, sharper fold. Every angle is rolled per leg, so the
	--- four never match -- a carcass with four identical legs reads as a toy.
	local function leg(atX: number, side: number)
		local hip = base
			* CFrame.new(atX, 2.5 * s, side * 2.2 * s)
			* Kit.ang(0, if side > 0 then 0 else 180, 0)
			* Kit.ang(rng:NextNumber(96, 112), 0, 0)
		boneShaft(parent, hip, 2.9 * s, 0.5 * s, rng)

		local knee = hip * CFrame.new(0, 2.9 * s, 0) * Kit.ang(rng:NextNumber(22, 44), 0, 0) * Kit.ang(0, rng:NextNumber(-22, 22), 0)
		boneShaft(parent, knee, 2.2 * s, 0.38 * s, rng)
		build(parent, knee * CFrame.new(0, 2.2 * s, 0), {
			name = "Hoof",
			pos = { 0, 0.3 * s, 0 },
			size = { 0.6 * s, 0.62 * s, 0.6 * s },
			color = BONE_DARK,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end

	for _, side in { 1, -1 } do
		leg((mid - 3.5) * seg, side) -- shoulder
		leg(hipX, side) -- hip
	end

	-- The tail, shrinking fast as it trails off behind and settles onto the ground.
	boneArc(
		parent,
		base * CFrame.new(-(mid + 0.3) * seg, spineY - 0.2 * s, 0) * Kit.ang(0, -90, 0) * Kit.ang(84, 0, 0),
		"Tail",
		7,
		1.25 * s,
		0.34 * s,
		15,
		rng
	)
end

--- A handful of loose bones lying where they scattered -- long bones, a curved rib
--- shard or two, the odd vertebra. This is the field's TEXTURE between the carcasses:
--- the thing you notice underfoot on your way somewhere else, not the thing you walk
--- over to look at.
---
--- EVERYTHING HERE LIES FLAT, and the frame is what does it: `Kit.ang(0, 0, -90)` after
--- the yaw puts the growth axis along the ground and the bend axis VERTICAL, so a
--- `boneArc` bows across the floor like a C rather than arcing up out of it. (Pitching
--- 90 degrees instead is the obvious version of this that does not work: it lays the
--- shaft down but leaves the bend running straight into the ground.)
---
--- A third of a stud up: clear of the checkerboard cap at GROUND_SKIM, under the
--- border strip at SKIM, and low enough that a haul surfacing beneath one still shows.
local function boneCluster(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	for _ = 1, rng:NextInteger(3, 6) do
		local px = x + rng:NextNumber(-3.5, 3.5)
		local pz = z + rng:NextNumber(-3.5, 3.5)
		local lie = origin * CFrame.new(px, 0.32, pz) * Kit.ang(0, rng:NextNumber(0, 360), 0) * Kit.ang(0, 0, -90)
		local roll = rng:NextNumber()

		if roll < 0.5 then
			boneShaft(parent, lie, rng:NextNumber(2.4, 4.6), rng:NextNumber(0.42, 0.62), rng)
		elseif roll < 0.82 then
			boneArc(parent, lie, "RibShard", rng:NextInteger(3, 4), rng:NextNumber(1.1, 1.6), rng:NextNumber(0.3, 0.42), rng:NextNumber(14, 26), rng)
		else
			build(parent, origin, {
				name = "Vertebra",
				pos = { px, 0.42, pz },
				size = { 0.95, 0.8, 1.05 },
				color = if rng:NextNumber() < 0.3 then BONE_DARK else BONE,
				material = "Plastic",
				studs = true,
				rot = Kit.ang(rng:NextNumber(-28, 28), rng:NextNumber(0, 360), rng:NextNumber(-28, 28)),
				canCollide = false,
			})
		end
	end
end

local function prop(
	parent: Instance,
	origin: CFrame,
	kind: string,
	x: number,
	z: number,
	rng: Random,
	ooze: { bright: string, deep: string, glow: string }
)
	if kind == "trees" then
		deadTree(parent, origin, x, z, rng)
	elseif kind == "brush" then
		-- Stage 1's Outer Ash stage only (see propKindFor): live scrub, not the dead
		-- "trees" kind the rest of the stage uses — one or two small foliage blobs
		-- low to the ground, deliberately reading as smaller than both DeadTree and
		-- liveTree so none of the three get mistaken for one another at a glance.
		for _ = 1, rng:NextInteger(1, 2) do
			local center = { x + rng:NextNumber(-2, 2), rng:NextNumber(0.9, 1.3), z + rng:NextNumber(-2, 2) }
			foliageBlob(parent, origin, center, rng:NextNumber(1.1, 1.5), "6B8F3E", "547231", rng)
		end
	elseif kind == "liveTree" then
		-- Stage 1's Outer Ash stage only — a branching trunk carrying several
		-- rounded foliage clusters, matching the reference the user gave (a
		-- chunky, low-poly toy tree, not one flat canopy block or DeadTree's bare
		-- branches). Canopy colour matches Stage 1's own ground green so
		-- trunk-and-leaves reads as one plant family with the grass it stands on.
		local h = rng:NextNumber(5, 6.5)
		build(parent, origin, {
			name = "TreeTrunk",
			pos = { x, h / 2, z },
			size = { 1.3, h, 1.3 },
			color = C.wood,
			material = "Wood",
			canCollide = false,
		})

		local clusterCount = rng:NextInteger(3, 4)
		for i = 1, clusterCount do
			local angle = (i - 1) * (360 / clusterCount) + rng:NextNumber(-20, 20)
			local reach = rng:NextNumber(2.4, 3.6)
			local clusterX = x + math.cos(math.rad(angle)) * reach
			local clusterZ = z + math.sin(math.rad(angle)) * reach
			local clusterY = h + rng:NextNumber(1.2, 2.8)

			-- A short angled branch reaching roughly toward the cluster — same
			-- jittered-angle technique DeadTree's own branches already use, not a
			-- precise line to the cluster's exact position; it does not need to be,
			-- the foliage covers the join.
			build(parent, origin, {
				name = "Branch",
				pos = { x + math.cos(math.rad(angle)) * reach * 0.55, h + rng:NextNumber(0.6, 1.6), z + math.sin(math.rad(angle)) * reach * 0.55 },
				size = { reach, 0.55, 0.55 },
				color = C.wood,
				material = "Wood",
				rot = Kit.ang(0, -angle, rng:NextNumber(20, 35)),
				canCollide = false,
			})

			foliageBlob(parent, origin, { clusterX, clusterY, clusterZ }, rng:NextNumber(2, 2.7), "5C9A34", "4A7D29", rng)
		end
	elseif kind == "houses" then
		-- A collapsed shell: two standing walls and a leaning roof slab.
		local w = rng:NextNumber(9, 15)
		build(parent, origin, { name = "Wall", pos = { x, 3, z }, size = { w, 6, 0.8 }, color = C.plazaWarm, material = "Brick" })
		build(parent, origin, { name = "Wall", pos = { x - w / 2, 2.4, z + 5 }, size = { 0.8, 5, 10 }, color = C.plazaEdge, material = "Brick" })
		build(parent, origin, {
			name = "RoofSlab",
			pos = { x + 2, 4.4, z + 6 },
			size = { w, 0.6, 9 },
			color = C.barrelRust,
			material = "Slate",
			rot = Kit.ang(0, 0, rng:NextNumber(14, 26)),
			canCollide = false,
		})
	elseif kind == "sirens" then
		build(parent, origin, { name = "SirenPost", pos = { x, 6, z }, size = { 0.8, 12, 0.8 }, color = C.steelDark, material = "Metal" })
		build(parent, origin, {
			name = "SirenHead",
			pos = { x, 12.4, z },
			size = { 2.6, 1.8, 2.6 },
			color = C.barrelRust,
			material = "SmoothPlastic",
			canCollide = false,
		})
	elseif kind == "reactor" then
		-- Reactor Grounds: cooling stacks, cracked and still lit from inside. Tapered
		-- by stacking two cylinders rather than using a cone, which the Kit has no
		-- shape for — and a straight pipe reads as scaffolding, not as a reactor.
		local h = rng:NextNumber(16, 26)
		build(parent, origin, {
			name = "Stack",
			pos = { x, h / 2, z },
			size = { h, 9, 9 },
			color = C.steelDark,
			material = "Concrete",
			shape = "Cylinder",
			rot = R.cylUp,
		})
		build(parent, origin, {
			name = "StackNeck",
			pos = { x, h + 2, z },
			size = { 4, 6.4, 6.4 },
			color = C.rubble,
			material = "Concrete",
			shape = "Cylinder",
			rot = R.cylUp,
		})
		-- The crack, in the STAGE's own colour — matte, like every surface in the world.
		build(parent, origin, {
			name = "StackVent",
			pos = { x, h + 5.4, z },
			size = { 1.2, 6.8, 6.8 },
			color = ooze.bright,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R.cylUp,
			canCollide = false,
		})
	elseif kind == "shards" then
		-- The Crater: whatever the blast fused, standing up out of the ground. Three
		-- leaning spikes per cluster, each tilted off vertical by a different amount,
		-- because three identical uprights read as a fence.
		for _ = 1, 3 do
			local h = rng:NextNumber(7, 19)
			build(parent, origin, {
				name = "Shard",
				pos = { x + rng:NextNumber(-5, 5), h / 2, z + rng:NextNumber(-5, 5) },
				size = { rng:NextNumber(1.4, 3.2), h, rng:NextNumber(1.4, 3.2) },
				color = ooze.bright,
				material = "SmoothPlastic",
				rot = Kit.ang(rng:NextNumber(-22, 22), rng:NextNumber(0, 180), rng:NextNumber(-22, 22)),
				transparency = 0.15,
				canCollide = false,
			})
		end
		-- A dark base so a cluster reads as something that grew out of the ground
		-- rather than as three lights hovering over it.
		build(parent, origin, {
			name = "ShardBase",
			pos = { x, 0.6, z },
			size = { 1.2, 15, 15 },
			color = ooze.deep,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R.cylUp,
			canCollide = false,
		})
	else -- "barriers" — Stage 4. Sparse on purpose: PLAN §15 wants it content-free.
		build(parent, origin, {
			name = "Barrier",
			pos = { x, 1.6, z },
			size = { 9, 3.2, 1.4 },
			color = C.plazaEdge,
			material = "Concrete",
			rot = Kit.ang(0, rng:NextNumber(-40, 40), 0),
		})
		build(parent, origin, {
			name = "HazardStripe",
			pos = { x, 3.3, z },
			size = { 9, 0.4, 1.5 },
			color = C.barrelYellow,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end
end

--- SCATTER IS BESPOKE PER STAGE during this incremental rework -- each field wants its
--- props somewhere different, so `buildStageScenery` dispatches on `id` rather than
--- running one shared loop. All of these:
---   * only run for stages whose THEME entry sets `scatter`,
---   * are deterministic off the stage rng (a rebuild reproduces the field),
---   * leave barrels, ooze pools and every un-reworked `prop()` kind on the shelf.

--- Stage 2 -- big dead trees over the WHOLE field, biased toward the two long edges
--- rather than spread flat: the depth splits into three equal-width bands (north edge,
--- middle, south edge) and BAND_WEIGHTS hands the edge bands more of the count than
--- the middle gets, so it still reads as a tree LINE with a few strays further in,
--- not a lawn. Whichever band comes up short on the rounding is picked by shuffled
--- tie-break, not always the same one, so a rebuild doesn't always favour north.
--- Within a band, trees sit in even cells across the width, each jittered up to half
--- a cell in both axes, so a band never clumps or grids. Every candidate point is also
--- checked against MIN_GAP from every tree already placed, in any band -- the per-cell
--- jitter alone can still land two trees close enough that their canopies overlap
--- (especially across a band boundary), and the trees are big enough that reads as a
--- bug, not a cluster.
local function scatterFieldTrees(folder: Instance, origin: CFrame, count: number, rng: Random, hx: number, hz: number)
	local BAND_WEIGHTS = { 2, 1, 2 } -- north edge, middle, south edge
	local MIN_GAP = 32 -- studs between trunks -- a same-band gap this size reads fine,
	-- but it's also what a cross-band pair needs: two adjacent cells' jitter can still
	-- land a north-band and a middle-band tree ~25 studs apart, close enough to read as
	-- one clump straddling the boundary. 32 forces both cases apart.
	local MAX_ATTEMPTS_PER_TREE = 50

	local bandCount, remainder = {}, {}
	local totalWeight = BAND_WEIGHTS[1] + BAND_WEIGHTS[2] + BAND_WEIGHTS[3]
	local assigned = 0
	for i, w in BAND_WEIGHTS do
		local raw = count * w / totalWeight
		bandCount[i] = math.floor(raw)
		remainder[i] = raw - bandCount[i]
		assigned += bandCount[i]
	end

	local tieOrder = { 1, 2, 3 }
	for i = 3, 2, -1 do
		local j = rng:NextInteger(1, i)
		tieOrder[i], tieOrder[j] = tieOrder[j], tieOrder[i]
	end
	for _ = 1, count - assigned do
		local bestI, bestFrac = tieOrder[1], -1
		for _, i in tieOrder do
			if remainder[i] > bestFrac then
				bestI, bestFrac = i, remainder[i]
			end
		end
		bandCount[bestI] += 1
		remainder[bestI] = -1
	end

	local bandH = 2 * hz / 3
	local placed = {}
	local function tooClose(x: number, z: number): boolean
		for _, p in placed do
			if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 < MIN_GAP ^ 2 then
				return true
			end
		end
		return false
	end

	for band = 1, 3 do
		local n = bandCount[band]
		if n > 0 then
			local zLo = -hz + (band - 1) * bandH
			local cell = 2 * hx / n
			for i = 0, n - 1 do
				local x, z
				local attempts = 0
				repeat
					x = math.clamp(-hx + (i + 0.5 + rng:NextNumber(-0.5, 0.5)) * cell, -hx, hx)
					z = math.clamp(zLo + (0.5 + rng:NextNumber(-0.5, 0.5)) * bandH, -hz, hz)
					attempts += 1
				until not tooClose(x, z) or attempts >= MAX_ATTEMPTS_PER_TREE
				table.insert(placed, { x, z })
				deadTree(folder, origin, x, z, rng)
			end
		end
	end
end

--- Stages 2 AND 3 -- THE REMAINS, three passes over one field (see the "THE REMAINS"
--- section above for what each piece is and why it is built the way it is):
---   * `skeletons` whole carcasses, the landmarks. Held off the centre lane by
---     SKELETON_CENTRE_CLEARANCE and inside `carcassOuterZ`, so each sits in the open
---     ground beside the walk-through route -- seen broadside from the path, which is
---     the only angle a rib cage reads as a rib cage from.
---   * `clusters` handfuls of loose bone, on an even jittered grid over the WHOLE
---     field, lane included: these are ankle-height ground texture, and the walk in is
---     exactly where they should be underfoot.
---   * `skulls` human skulls, same grid treatment, each with its own yaw and a small
---     tilt so a scatter of them never lines up into a row of bollards.
---
--- Alternating sides for the carcasses is deliberate at these counts: two or three on
--- the same side of the lane reads as one pile, alternating reads as a field with
--- remains all over it.
---
--- `carcassOuterZ` IS PER FIELD BECAUSE THE FIELDS DIFFER, and it is the only
--- placement number that does. Stage 2's carcasses stay off the outer wall band (a
--- 30-stud carcass laid across the corridor would read as a bug); Stage 3 has nothing
--- standing in it, so its band runs almost to the wall and its three spread over the
--- full depth instead of crowding one mid-field strip. Everything else -- the grids,
--- the clearance, the alternation -- is shared.
---
--- Deterministic off the stage rng. On Stage 2 it is consumed AFTER scatterFieldTrees
--- so the trees keep the exact placement they already had; on Stage 3 it is the only
--- pass there is. Same discipline as Stage 1's three passes.
---
--- ALL OF IT GOES IN ONE `Bones` FOLDER SO IT CAN BE MADE UNQUERYABLE IN ONE PASS.
--- FieldController.groundY fires a ray straight down from the player to sit the
--- detector's range ring on the floor, and these are the first props in this file that
--- a player routinely stands ON TOP OF -- a bone lying flat is a third of a stud of
--- lip spread over the ground, where a tree trunk is something you walk around. Left
--- queryable, the ring would step up whenever you crossed one. CanTouch goes with it:
--- nothing here is ever meant to fire a touch event. Same reasoning and the same fix
--- as scatterStage1Cracks, just applied to a folder rather than part by part.
local function scatterBones(
	folder: Instance,
	origin: CFrame,
	rng: Random,
	hx: number,
	hz: number,
	carcassOuterZ: number,
	skeletons: number,
	clusters: number,
	skulls: number
)
	local bones = Instance.new("Folder")
	bones.Name = "Bones"

	--- An even jittered grid over the whole field: `count` cells laid out to roughly
	--- square proportions, each item nudged up to a third of a cell so the cover stays
	--- even without reading as a lattice. Same idiom as scatterBushes/scatterDeadBushes.
	local function grid(count: number, place: (number, number) -> ())
		if count <= 0 then
			return
		end
		local cols = math.max(1, math.round(math.sqrt(count * (hx / hz))))
		local rows = math.ceil(count / cols)
		local placed = 0
		for row = 0, rows - 1 do
			for col = 0, cols - 1 do
				if placed >= count then
					break
				end
				placed += 1
				local x = -hx + (col + 0.5 + rng:NextNumber(-0.34, 0.34)) * (2 * hx / cols)
				local z = -hz + (row + 0.5 + rng:NextNumber(-0.34, 0.34)) * (2 * hz / rows)
				place(math.clamp(x, -hx, hx), math.clamp(z, -hz, hz))
			end
		end
	end

	for i = 1, skeletons do
		local side = if i % 2 == 1 then -1 else 1
		local x = -hx + (i - 0.5) * (2 * hx / math.max(1, skeletons)) + rng:NextNumber(-14, 14)
		-- Out of the walk, inside whatever this field's outer bound is (see above).
		local z = side
			* rng:NextNumber(SKELETON_CENTRE_CLEARANCE, math.max(SKELETON_CENTRE_CLEARANCE + 1, carcassOuterZ))
		animalSkeleton(bones, origin, math.clamp(x, -hx + 26, hx - 26), z, rng)
	end

	grid(clusters, function(x: number, z: number)
		boneCluster(bones, origin, x, z, rng)
	end)

	-- Bedded a HAIR into the ground -- the same trick `bush` uses on its base block, but
	-- a fraction of the depth. A skull is nearly all read below the eyeline (teeth,
	-- notch, the taper to the jaw, see `skull`), so a sink deep enough to look settled
	-- is a sink deep enough to bury everything that makes it a skull.
	grid(skulls, function(x: number, z: number)
		local base = origin
			* CFrame.new(x, -0.05, z)
			* Kit.ang(0, rng:NextNumber(0, 360), 0)
			* Kit.ang(rng:NextNumber(-9, 9), 0, rng:NextNumber(-9, 9))
		skull(bones, base, rng:NextNumber(1.05, 1.35), false, rng)
	end)

	for _, d in bones:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	bones.Parent = folder
end

--- Stage 1 -- chunky green bushes across the ALIVE WEST HALF only. Stage 1's ground
--- fades green (west, where you walk in from camp) to dead tan (east); the scrub
--- belongs on the living side. Bushes fill a grid over the western half of the field,
--- each nudged only a third of a cell so the scatter stays even, and any that land
--- within BUSH_CENTRE_CLEARANCE of z = 0 are pushed out to it so the walk-through
--- lane down the middle of the field stays open.
---
--- All candidate bushes are built before the farthest ones are discarded. `bush`
--- consumes the same deterministic RNG used by placement, so skipping a build in the
--- loop would reshuffle every bush after it. Temporary folders let the surviving six
--- retain their exact positions, sizes and colours while removing only the three with
--- the greatest X coordinate (farthest east from the plaza entrance).
local function scatterBushes(folder: Instance, origin: CFrame, count: number, removeFarthest: number, rng: Random, hx: number, hz: number)
	local westEdge = -hx
	local bandDepth = 2 * hx * 0.5 -- the western half of the field
	local cols = math.ceil(math.sqrt(count * (bandDepth / (2 * hz))))
	local rows = math.ceil(count / cols)
	local candidates: { { folder: Folder, x: number } } = {}

	local placed = 0
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			if placed >= count then
				break
			end
			placed += 1
			local x = westEdge + (col + 0.5 + rng:NextNumber(-0.34, 0.34)) * (bandDepth / cols)
			local z = -hz + (row + 0.5 + rng:NextNumber(-0.34, 0.34)) * (2 * hz / rows)
			local candidate = Instance.new("Folder")
			local clampedX = math.clamp(x, westEdge, westEdge + bandDepth)
			local clampedZ = math.clamp(z, -hz, hz)
			if math.abs(clampedZ) < BUSH_CENTRE_CLEARANCE then
				clampedZ = (if clampedZ < 0 then -1 else 1) * BUSH_CENTRE_CLEARANCE
			end
			bush(candidate, origin, clampedX, clampedZ, rng)
			table.insert(candidates, { folder = candidate, x = clampedX })
		end
	end

	table.sort(candidates, function(a, b)
		return a.x > b.x
	end)
	local removeCount = math.clamp(removeFarthest, 0, #candidates)
	for index, candidate in candidates do
		if index > removeCount then
			for _, part in candidate.folder:GetChildren() do
				part.Parent = folder
			end
		end
		candidate.folder:Destroy()
	end
end

--- Stage 1 -- pixelated shatter cracks in the dead tan ground near the Stage 2 seam.
--- Half a dozen radial bursts in the last ~35 studs before the border: the field's
--- ground starting to give out at the edge. Grid-snapped near-black pixels laid flat on the
--- surface, non-colliding and non-queryable like every other ground layer in this
--- file, so footing, burial and the detector raycast all stay on the real plate
--- underneath. Physical breakage only -- no glow, no green (PLAN §14).
---
--- `halfX` / `halfZ` are Stage 1's true half-extents (not the -14 inset the scatter
--- helpers take) so the bursts can sit right up against the border. Deterministic off
--- the stage rng, consumed after scatterBushes.
local function scatterStage1Cracks(folder: Instance, origin: CFrame, halfX: number, halfZ: number, rng: Random)
	local PIXEL = 0.55
	-- Local offset above the stage surface plane -- `origin` already sits at
	-- Stages.SURFACE_Y. Clears the floor cap (at +GROUND_SKIM 0.06), below the
	-- border line (at +SKIM 0.26).
	local y = 0.14
	local seamX = halfX -- stage-local x of the Stage 1/2 border
	local occupied: { [string]: boolean } = {}

	--- Drop one crack pixel, snapped to the shared PIXEL grid. Clipped at the seam
	--- (nothing spills into Stage 2), held a stud clear of the walls, and deduped so
	--- overlapping arms never stack two parts in one cell.
	local function pixelAt(lx: number, lz: number, shade: string)
		local gx = math.round(lx / PIXEL) * PIXEL
		local gz = math.round(lz / PIXEL) * PIXEL
		if gx > seamX - PIXEL or gx < seamX - 54 or math.abs(gz) > halfZ - PIXEL then
			return
		end
		local key = `{gx},{gz}`
		if occupied[key] then
			return
		end
		occupied[key] = true

		local part = build(folder, origin, {
			name = "GroundCrack",
			pos = { gx, y, gz },
			size = { PIXEL, 0.1, PIXEL },
			color = shade,
			material = "SmoothPlastic",
			canCollide = false,
		})
		part.CanQuery = false
		part.CanTouch = false
	end

	--- One crack arm: a single-pixel-wide random-walk drifting along `heading`. Stays
	--- one pixel wide (only a rare chip beside it), and until `gen` hits 2 splits off
	--- the occasional divergent child branch carrying ~60% of the length still left.
	local function arm(lx: number, lz: number, heading: number, steps: number, gen: number)
		for step = 1, steps do
			heading += rng:NextNumber(-14, 14)
			lx += math.cos(math.rad(heading)) * PIXEL
			lz += math.sin(math.rad(heading)) * PIXEL
			pixelAt(lx, lz, if rng:NextNumber() < 0.18 then "2A2A2D" else C.hazardBlack)
			if rng:NextNumber() < 0.04 then
				pixelAt(lx + (if rng:NextNumber() < 0.5 then PIXEL else -PIXEL), lz, C.hazardBlack)
			end
			if gen < 2 and step > 3 and rng:NextNumber() < 0.14 then
				local turn = (if rng:NextNumber() < 0.5 then 1 else -1) * rng:NextNumber(30, 65)
				arm(lx, lz, heading + turn, math.max(3, math.floor((steps - step) * 0.6)), gen + 1)
			end
		end
	end

	local bursts = 6
	for i = 1, bursts do
		local cx = seamX - rng:NextNumber(6, 34)
		local cz = math.clamp(
			-halfZ + (i - 0.5 + rng:NextNumber(-0.28, 0.28)) * (2 * halfZ / bursts),
			-halfZ + 10,
			halfZ - 10
		)
		pixelAt(cx, cz, C.hazardBlack)
		-- Enough arms to read as a full radial shatter rather than a Y. Evenly spaced
		-- around the circle with a wide jitter so no two clusters look alike.
		local armCount = rng:NextInteger(5, 8)
		local base = rng:NextNumber(0, 360)
		for a = 1, armCount do
			local heading = base + (a - 1) * (360 / armCount) + rng:NextNumber(-24, 24)
			arm(cx, cz, heading, rng:NextInteger(9, 16), 0)
		end
	end
end

--- Stage 1 -- `count` knee-high dead snags across the EASTERN half, the dead-tan side
--- where the green scrub (scatterBushes, west half) has died back and the ground is
--- starting to crack. Same even grid + third-of-a-cell jitter as scatterBushes, and the
--- same BUSH_CENTRE_CLEARANCE lane down z = 0. Sparser than the green side by count
--- alone -- nothing thrives here. The band stops a few studs short of the Stage 1/2
--- seam so a snag never straddles the border line.
---
--- Deterministic off the stage rng, and consumed AFTER scatterStage1Cracks in
--- buildStageScenery so neither pass shifts the other's placement.
local function scatterDeadBushes(folder: Instance, origin: CFrame, count: number, rng: Random, hx: number, hz: number)
	local bandStart = 6 -- a small gap east of dead centre, clear of the green scrub
	local bandDepth = hx - 8 - bandStart -- ...to a few studs short of the seam at +hx
	local cols = math.max(1, math.ceil(math.sqrt(count * (bandDepth / (2 * hz)))))
	local rows = math.ceil(count / cols)

	local placed = 0
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			if placed >= count then
				break
			end
			placed += 1
			local x = bandStart + (col + 0.5 + rng:NextNumber(-0.34, 0.34)) * (bandDepth / cols)
			local z = -hz + (row + 0.5 + rng:NextNumber(-0.34, 0.34)) * (2 * hz / rows)
			local clampedX = math.clamp(x, bandStart, bandStart + bandDepth)
			local clampedZ = math.clamp(z, -hz, hz)
			if math.abs(clampedZ) < BUSH_CENTRE_CLEARANCE then
				clampedZ = (if clampedZ < 0 then -1 else 1) * BUSH_CENTRE_CLEARANCE
			end
			deadBush(folder, origin, clampedX, clampedZ, rng)
		end
	end
end

--- Stage 3 — radioactive drums, dumped across the field in ones and twos.
---
--- DUMPED, NOT PLACED. The grid picks DUMP SITES, not drums: the count is split into
--- loads of one to three FIRST and the grid is then sized to however many loads that
--- came to, so every cell gets a load and no drum is left over at the end. A load of
--- three standing within a few studs of each other reads as something tipped off the
--- back of a truck; `count` drums spread evenly over the same field reads as a car
--- park. It is also what makes them landmarks rather than texture, which is the job
--- this field needed doing — Stage 3's own note in THEME calls it bare khaki ground
--- with nothing standing on it at all, and a drum is the first thing that does.
---
--- A quarter of them have gone over (BARREL_FALLEN) and a fallen drum rests on its
--- CHIMES, not on its shell (DRUM_CHIME) -- and it is placed by its MIDDLE, which the
--- pose has to walk back for, since `radBarrel` builds every drum standing on the base
--- it is handed.
---
--- NOTHING LEAKS, AND THAT IS DELIBERATE. The obvious next thing here is an ooze
--- puddle under the fallen ones, and this field does not have one: Stage 3's pass is
--- bare ground with the remains on it and no pools anywhere (see THEME), so a spill is
--- that decision reversed rather than a detail added. `barrel()`'s old spill disc is in
--- git history for whenever it is actually wanted.
---
--- Out of the centre lane like the carcasses (BARREL_CENTRE_CLEARANCE), and
--- deterministic off the stage rng, consumed AFTER scatterBones so every bone in the
--- field stays exactly where it already was.
local function scatterBarrels(folder: Instance, origin: CFrame, count: number, rng: Random, hx: number, hz: number)
	if count <= 0 then
		return
	end

	local loads = {}
	local left = count
	while left > 0 do
		local take = math.min(left, rng:NextInteger(1, 3))
		table.insert(loads, take)
		left -= take
	end

	-- POSES COME OUT OF A SHUFFLED BAG, NOT OFF A DIE PER DRUM, and that is worth the
	-- extra dozen lines. A field is fourteen drums, and fourteen rolls against a
	-- probability is a small enough sample to miss badly: at a one-in-five chance of
	-- going over, this field's stream rolled SEVEN of its fourteen under 0.145 and put
	-- half the drums on the ground. The stage seed is FIXED (buildStageScenery's
	-- `Random.new(1000 + id)`), so that is not bad luck that averages out over a
	-- session — it is what the field looks like, every time, for everyone. A bag
	-- holding the right number of each pose gives the mix that was actually asked for
	-- at any count, and the shuffle is what keeps it from arriving in blocks.
	local bag = table.create(count, "upright")
	local fallen = math.round(count * BARREL_FALLEN)
	for i = 1, fallen do
		bag[i] = "fallen"
	end
	for i = fallen + 1, math.min(count, fallen + math.round(count * BARREL_LEANING)) do
		bag[i] = "leaning"
	end
	for i = count, 2, -1 do
		local j = rng:NextInteger(1, i)
		bag[i], bag[j] = bag[j], bag[i]
	end
	local drawn = 0

	local barrels = Instance.new("Folder")
	barrels.Name = "Barrels"

	-- The same jittered grid the bones use, over the dump sites rather than the drums.
	local cols = math.max(1, math.round(math.sqrt(#loads * (hx / hz))))
	local rows = math.ceil(#loads / cols)
	local site = 0
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			site += 1
			if site > #loads then
				break
			end

			local cx = math.clamp(-hx + (col + 0.5 + rng:NextNumber(-0.32, 0.32)) * (2 * hx / cols), -hx, hx)
			local cz = -hz + (row + 0.5 + rng:NextNumber(-0.32, 0.32)) * (2 * hz / rows)
			-- Pushed off the walk, never onto it: a site that landed inside the lane goes
			-- out to the edge of it on the side it was already on. The clearance is owed
			-- by the DRUM, not by the site, so the site has to clear the lane by the
			-- whole reach of a load as well -- one parked exactly on the clearance line
			-- puts its second and third drums straight back inside it (measured at 14
			-- studs, not 16). BARREL_LANE_KEEPOUT is checked live rather than proved:
			-- the slide below can push a crowding drum out past BARREL_CROWD_MAX.
			if math.abs(cz) < BARREL_LANE_KEEPOUT then
				cz = (if cz < 0 then -1 else 1) * BARREL_LANE_KEEPOUT
			end
			cz = math.clamp(cz, -hz, hz)

			-- Which way the load fell off the truck. Rolled per site so a field of them
			-- does not settle into the same triangle over and over.
			local spread = rng:NextNumber(0, 360)
			-- The drums already standing at this site: where they are relative to it, and
			-- how much ground each of them claims.
			local here = {}

			for n = 1, loads[site] do
				-- The first drum of a load lands on the site; the rest stand off it on a
				-- rough triangle. A BEARING AND A DISTANCE, never two independent jitters:
				-- the distance is the axis with a floor under it, and jittering x and z
				-- separately has no way to hold one. Bearings a third of a turn apart
				-- with less than half that in wobble keep the crowding drums off EACH
				-- OTHER as well as off the first one.
				local bearing = math.rad(spread + (n - 1) * 120 + rng:NextNumber(-28, 28))
				local ux, uz = math.sin(bearing), math.cos(bearing)
				local reach = if n == 1 then 0 else rng:NextNumber(BARREL_CROWD_MIN, BARREL_CROWD_MAX)
				-- Which way the drum points, how far round its own axis it is turned,
				-- and how far off plumb. All three are rolled for every drum whichever
				-- pose it drew, so the rng runs the same number of times per drum and
				-- retuning the mix above cannot reshuffle the whole field.
				local aim = Kit.ang(0, rng:NextNumber(0, 360), 0)
				local spin = Kit.ang(0, rng:NextNumber(0, 360), 0)
				drawn += 1
				local pose = bag[drawn]
				local lean = if pose == "leaning" then rng:NextNumber(9, 16) else rng:NextNumber(-2.5, 2.5)

				-- How much ground this drum claims. A FALLEN one is four studs long and
				-- may be aimed any way, so it claims half its length on top of its chime
				-- radius — which is why one distance floor cannot serve both poses: nose
				-- to nose, two fallen drums need nearly seven studs between centres where
				-- two standing ones need under three. A flat 4.2 left two of them
				-- intersecting on the first build.
				local foot = (DRUM_R + DRUM_CHIME) + (if pose == "fallen" then DRUM_H / 2 else 0)
				-- Slide out along the bearing to the first point clear of every drum
				-- already here. Solved rather than stepped: the points on the ray at
				-- exactly `need` from a placed drum are the roots of a quadratic, and the
				-- larger one is where the ray leaves that drum's ground for good.
				for _, placed in here do
					local need = foot + placed.foot
					local along = ux * placed.x + uz * placed.z
					local disc = along * along - (placed.x * placed.x + placed.z * placed.z) + need * need
					if disc > 0 then
						reach = math.max(reach, along + math.sqrt(disc))
					end
				end
				local jx, jz = reach * ux, reach * uz
				table.insert(here, { x = jx, z = jz, foot = foot })

				if pose == "fallen" then
					-- On its side: `aim` is the direction it lies in, the 90 tips it
					-- over, and `spin` then turns it about its own axis so the trefoil
					-- is not always pointing at the sky.
					--
					-- THE LAST STEP IS NOT OPTIONAL. `radBarrel` builds a drum standing on
					-- the base it is handed, so the base is the drum's BOTTOM -- which,
					-- once the drum is on its side, is one end of it, two studs from the
					-- middle. Without walking that back along the drum's own axis a fallen
					-- drum lands two studs from where it was placed, which quietly voids
					-- every distance this function just worked out (measured live: two
					-- drums 3.5 studs apart out of a 4.2 floor).
					radBarrel(
						barrels,
						origin
							* CFrame.new(cx + jx, GROUND_SKIM + DRUM_R + DRUM_CHIME - 0.03, cz + jz)
							* aim
							* Kit.ang(0, 0, 90)
							* spin
							* CFrame.new(0, -DRUM_H / 2, 0),
						rng
					)
				else
					-- Standing: plumb to within a couple of degrees, or propped over at
					-- a real angle if it drew "leaning". Either way the tilt is about the
					-- base, so the drum has to be lifted by exactly what that tilt would
					-- otherwise sink the low edge of the bottom chime into the ground.
					local sink = (DRUM_R + DRUM_CHIME) * math.abs(math.sin(math.rad(lean)))
					radBarrel(barrels, origin * CFrame.new(cx + jx, GROUND_SKIM - 0.03 + sink, cz + jz) * aim * Kit.ang(0, 0, lean), rng)
				end
			end
		end
	end

	for _, d in barrels:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	barrels.Parent = folder
end

--- ── Stage 4's caution sign ───────────────────────────────────────────────────
--- REPLACED THE BLACK-BORDERED HAZARD PLACARD, ON REQUEST -- it read as "horrible"
--- live. Much simpler now: a studded brown leg and a studded brown board, one
--- colour, one material, no separate face/border/mark layers and no proud-decal
--- offset math to get wrong (the first version's whole bug was exactly that math).
--- `studs = true` also brings the sign in line with every OTHER prop in this file --
--- deadTree, deadBush and bush are all studded Plastic already; the old sign's
--- Metal/SmoothPlastic faces were the one thing in the field that was not, which is
--- most of why it read as an odd sore thumb next to everything around it.
local SIGN_THICK = 1 -- shared depth (X, the axis a player walks through) -- "1 stud thick"
local SIGN_LEG_W, SIGN_LEG_H = 1, 2 -- "the leg of the stick 2x1 long" -- 1x1 cross-section, 2 tall
local SIGN_W, SIGN_H = 4, 3 -- "the actual sign 4x3 rectangle" -- wider than tall
local SIGN_BROWN = C.wood

--- THE CAUTION BADGE, ON REQUEST -- reference was a yellow radiation-warning sign:
--- a black "CAUTION" band across the top, a black trefoil on yellow below it.
--- Nailed onto the board's west (entrance) face as its own proud plate rather than
--- painted straight onto the wood, the same "placard bolted to a post" read the
--- reference image itself has. SmoothPlastic, not studded -- the wood board is the
--- carpentry, the badge is a printed metal sign fixed to it, and that material
--- contrast is what sells "something was bolted on here" rather than carved in.
local SIGN_BADGE_W, SIGN_BADGE_H = 3.5, 2.6 -- leaves an even wood margin inside the 4x3 board
local SIGN_BAND_H = 0.7 -- the black CAUTION strip, flush with the badge's own top edge

--- Every proud layer in this sign is measured off the WEST FACE of the layer
--- behind it, never off that layer's centre -- see the git history on this file
--- (the first hazard-placard version) for exactly what goes wrong otherwise: a
--- thicker layer's own half-thickness can reach further west than a thinner one
--- centred only `paint` in front of it, so the thicker layer ends up hiding the
--- thinner one instead of backing it. Returns the new layer's own centre X and its
--- west face X, so the next layer out can chain off the second value.
local function proudOf(prevWestFaceX: number, paint: number, thickness: number): (number, number)
	local centerX = prevWestFaceX - paint + thickness / 2
	return centerX, centerX - thickness / 2
end

local BADGE_PAINT = 0.05
local BOARD_WEST_FACE = -SIGN_THICK / 2
local BADGE_X, BADGE_WEST_FACE = proudOf(BOARD_WEST_FACE, BADGE_PAINT, 0.06)
local BAND_X = (proudOf(BADGE_WEST_FACE, BADGE_PAINT, 0.05))
local MARK_X = (proudOf(BADGE_WEST_FACE, BADGE_PAINT, 0.05))

--- The radiation trefoil, flat against the badge -- the same three-bladed rosette
--- radBarrel paints on the drums (see that function's own header for the real
--- symbol's proportions this follows), just laid straight in the sign's Y-Z plane
--- instead of wrapped around a cylinder: there is no curvature to unwrap on a flat
--- badge, so this is the simpler of the two versions.
---
--- EACH ARM'S ORIGIN CARRIES ITS OWN ROTATION, RATHER THAN A SEPARATELY COMPUTED
--- POSITION ROLLED BY HAND -- `build`'s pos/rot split can't express "rotate about
--- the hub, then push outward," so position and facing would otherwise have to
--- agree on Roblox's own rotation handedness by hand (get the sign wrong and a
--- blade points off at the mirror of where it sits). Composing the arm's CFrame
--- once and pushing straight out along ITS OWN rotated Y axis makes the two agree
--- by construction instead of by luck.
local function flatTrefoil(parent: Instance, hubOrigin: CFrame, scale: number, color: string)
	build(parent, hubOrigin, {
		name = "TrefoilHub",
		pos = { 0, 0, 0 },
		size = { 0.05, 0.5 * scale, 0.5 * scale },
		color = color,
		material = "SmoothPlastic",
		shape = "Cylinder",
		canCollide = false,
	})
	for i = 0, 2 do
		local armOrigin = hubOrigin * Kit.ang(i * 120, 0, 0)
		for _, blade in { { 0.55, 0.55 }, { 0.95, 0.95 } } do
			local reach, width = blade[1] * scale, blade[2] * scale
			build(parent, armOrigin * CFrame.new(0, reach, 0), {
				name = "TrefoilBlade",
				pos = { 0, 0, 0 },
				size = { 0.05, width, width * 0.42 },
				color = color,
				material = "SmoothPlastic",
				canCollide = false,
			})
		end
	end
end

local function warningSign(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	-- A few degrees of yaw jitter, not the full 0-360 deadTree/bush get: the badge is
	-- one-sided (west face only), so a full random spin would leave some signs in the
	-- rank showing their blank back to a player walking in from Stage 3.
	local base = origin * CFrame.new(x, 0, z) * Kit.ang(0, rng:NextNumber(-8, 8), 0)

	build(parent, base, {
		name = "SignLeg",
		pos = { 0, SIGN_LEG_H / 2, 0 },
		size = { SIGN_THICK, SIGN_LEG_H, SIGN_LEG_W },
		color = SIGN_BROWN,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})
	local boardY = SIGN_LEG_H + SIGN_H / 2
	build(parent, base, {
		name = "SignBoard",
		pos = { 0, boardY, 0 },
		size = { SIGN_THICK, SIGN_H, SIGN_W },
		color = SIGN_BROWN,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})

	build(parent, base, {
		name = "SignBadge",
		pos = { BADGE_X, boardY, 0 },
		size = { 0.06, SIGN_BADGE_H, SIGN_BADGE_W },
		color = C.barrelYellow,
		material = "SmoothPlastic",
		canCollide = false,
	})

	-- Flush with the badge's own top edge, full badge width -- the reference has no
	-- yellow margin around the band, only below it.
	local band = build(parent, base, {
		name = "SignBand",
		pos = { BAND_X, boardY + SIGN_BADGE_H / 2 - SIGN_BAND_H / 2, 0 },
		size = { 0.05, SIGN_BAND_H, SIGN_BADGE_W },
		color = C.hazardBlack,
		material = "SmoothPlastic",
		canCollide = false,
	})
	Kit.surfaceText(band, Enum.NormalId.Left, "CAUTION", C.labelText)

	-- Centred in whatever yellow is left below the band.
	local trefoilY = boardY - SIGN_BAND_H / 2
	flatTrefoil(parent, base * CFrame.new(MARK_X, trefoilY, 0), 0.75, C.hazardBlack)
end

--- Stage 4 -- a rank of signs along the entrance edge. Evenly spread across z with
--- the usual per-cell jitter -- the same one-axis jittered-grid technique Stage 2's
--- trees used to use along a long side, just run along the SHORT edge here since
--- these guard the entrance, not a side.
local function scatterWarningSigns(folder: Instance, origin: CFrame, count: number, rng: Random, hx: number, hz: number)
	for i = 0, count - 1 do
		local cell = 2 * hz / count
		local z = -hz + (i + 0.5 + rng:NextNumber(-0.35, 0.35)) * cell
		local x = -hx + rng:NextNumber(5, 11)
		warningSign(folder, origin, x, z, rng)
	end
end

--- ── Stage 4's ooze puddles ───────────────────────────────────────────────────
--- THE FIRST POOLS TO COME OFF THE SHELF since the strip-for-rework pass (`1b6ff88`)
--- took the old whole-field loop out. That loop's pool was ONE Neon cylinder plus one
--- bigger cylinder under it for a rim -- a perfect circle, and its own comment already
--- admitted the failure mode ("a decal painted on the floor"). This is a rebuild, not
--- a revival: nothing here is a single disc.
---
--- FEW AND DIFFERENT, NOT MANY AND ALIKE. The first pass built 26 puddles all rolled
--- out of one 9-24 stud range and read as spotty -- too many, and every one the same
--- size and the same roughly-round shape. There are 12 now, dealt off a SIZE LADDER
--- (scatterOozePools): one mini lake that is a landmark you walk around, a few broad
--- pools, some mid ones, and small spills. A field of identical blobs is wallpaper;
--- a field with one big thing in it has somewhere to walk TO.
---
--- ONE FLAT GREEN, NO DARK BORDER, NO INTERIOR DETAIL, VISIBLY OVAL, MORE CURVE THAN
--- BUMPS. On request, several times over -- flatten the inside to one shade, remove
--- the dark rim, elongate the body so it never reads as a circle, and shrink/swallow
--- the lobes so the outline reads as one sweeping curve rather than a cluster of
--- similar-sized bumps. A puddle here is now just its OWN outline, laid down as:
---   * an OVAL body, aspect 1.6-2.6 off its own yaw -- the floor is well clear of a
---     disc on purpose, so every puddle in the field is visibly elongated, not just
---     the ones that happened to roll long;
---   * two to four smaller ovals overlapping it near its two ENDS (the body's own
---     long axis, within +-20 degrees of each pole -- a lobe on the SIDE, or even
---     55 degrees off a pole on a body this elongated, bulges the waist back out
---     toward the minor axis's own width and cancels the ellipse's length back
---     toward a circle; both found live, on two separate shots), most
---     of them rolled SHORT of tangent so they swell one stretch of the outline into
---     a gentle sweep rather than poking out as a separate rounded lump, plus one
---     (arbitrarily, the last placed) allowed a wider size and reach so roughly one
---     puddle feature reads as a real protruding foot -- see the reference this shape
---     is built on, which has exactly one such foot off an otherwise smooth outline,
---     not a symmetric ring of equal bumps;
---   * droplets thrown clear, in the same one green as the body;
---   * one PointLight per pool, in `ooze.glow`, so the field looks lit rather than
---     merely coloured -- see the note at the light itself, below the lobe loop.
--- Every SOLID part of a puddle -- the body, every lobe, every droplet -- is
--- `ooze.bright` exactly. No blend, no second shade, no gradient, nothing dark
--- touching any of it. `ooze.deep`, the stage triple's third slot, goes unused now --
--- it used to be the rim, and there is nothing dark left anywhere in this field.
---
--- WHAT USED TO BE HERE, in the order it came off:
---   1. Interior detail -- a brighter off-centre CORE ("the middle is deeper than the
---      edge"), surface FROTH bubbles, a per-lobe MOTTLE blending each lobe a little
---      way toward `deep`, and the lake's mud ISLANDS. Flattened to one green first.
---   2. The RIM -- a `deep`-colour ring of even width following the whole outline, one
---      layer under the liquid, meant to read as the edge where liquid soaks into
---      ground. Removed next, as "that dark green outline".
---   3. The NOTCH that made the outline concave -- a `deep`-coloured oval straddling
---      the rim, there so a bite out of the pool would merge into the rim already
---      sitting on that edge rather than reading as a separate dark shape. It could
---      not survive step 2: shot live with the rim gone, a notch with nothing left to
---      blend into was a small dark blob stuck to a puddle's edge, not a dent. Removed
---      in the same pass as the rim, for that reason -- it was never wanted for its
---      own sake, only as camouflage for something that is no longer there. The
---      outline is purely convex now, which is the one trade this removal made: no
---      concave bite is possible without either a rim to hide the seam in or a real
---      boolean subtract, and this file has neither.
--- Every one of these had been tuned against live shots and was working by the time it
--- went. Do not reintroduce any of them as a "fix" for the pools looking flat or plain
--- -- flat and plain (and now unbordered) is the brief. The tuned numbers are in git
--- history on this file if interior detail or a rim is ever wanted back.
---
--- NO Z-FIGHTING BY CONSTRUCTION. Overlapping discs at one Y are exactly coplanar and
--- flicker; every part of a puddle is lifted POOL_LOBE_LIFT above the last in draw
--- order, so the stack rises a few hundredths of a stud over a whole puddle -- under
--- the border strip at SKIM even for the lake, invisible as a step, and there is never
--- a tie for the renderer to break.
---
--- STILL PURELY VISUAL. This file's header rule holds -- the ground is the hazard and
--- a pool is not a second one. Nothing here is queryable, collidable or touchable, and
--- StageService.hotPocketFor stays the stub it is.

--- Top of the liquid. Clears the checkerboard cap at GROUND_SKIM (0.06) and stays
--- under the border strip at SKIM (0.26) -- the same thin band every other ground
--- layer in this file lives in, so a haul surfacing under a puddle still comes up
--- through it.
local POOL_TOP = 0.15
local POOL_THICK = 0.12

--- Per-part Y step within one puddle. See the section header -- this both breaks
--- coplanar ties and IS the layering. 0.0025 rather than a rounder number because the
--- lake is the constraint: it is the one puddle big enough to carry ~30 parts, and
--- 30 * 0.0025 on top of POOL_TOP still lands under SKIM.
local POOL_LOBE_LIFT = 0.0025

--- THE OOZE IS THE ONE THING IN THIS WORLD THAT IS STILL NEON, ON REQUEST. Kit.C's
--- header sets the de-neon rule for everything else and it stands -- no shop accent,
--- no prop, no sign goes back to emitting. This is a deliberate, named exception for
--- one substance in one stage: the ask was for the green to have "a bright effect",
--- and matte green on brown mud cannot do it. Neon renders unshaded at full value, so
--- the liquid reads as lit from inside rather than painted on -- that is the surface
--- doing the work, separate from the PointLight below actually casting light onto the
--- ground around it. Together they are "glowing"; either alone is only "bright" or
--- only "lit from one side".
local POOL_MATERIAL = "Neon"

--- WHAT USED TO BE HERE: POOL_MOTTLE / POOL_CORE_PALE / POOL_FROTH_PALE, the three
--- blend strengths that shaded a pool's interior. There is no interior shading any
--- more -- see the section header. The liquid is `ooze.bright`; `glow` now lights the
--- pool from a PointLight instead of shading it, and `deep` -- the old rim's colour --
--- goes unused, full stop.
---
--- One thing worth keeping out of that removal, because it will come up again the next
--- time anything in this world is asked to glow: INTERIOR SHADING ON AN UNSHADED
--- SURFACE NEEDS A FRACTION OF THE CONTRAST A MATTE ONE WOULD. Neon renders at full
--- value with no lighting on it, so blends that look subtle in a palette read as hard
--- edges on the part -- 0.34 toward white made every puddle a fried egg, and 0.1 was
--- as far as it could go before the core started to separate from the body.

--- One flat oval lying on the ground. Every part of a puddle is one of these.
---
--- NOT A Cylinder, ON PAIN OF SILENTLY GETTING A CIRCLE BACK. This is the second time
--- this exact bug has cost a shape pass: `Enum.PartType.Cylinder`'s cross-section
--- (its Size.Y/Size.Z face) is CIRCULAR NO MATTER WHAT YOU PUT IN THOSE TWO FIELDS --
--- confirmed live by raycasting a test Cylinder sized {0.5, 80, 35} from twelve
--- bearings and getting exactly 17.5 studs (= Size.Z / 2) back every single time,
--- Size.Y's 80 completely ignored. `Enum.PartType.Ball` was tried next and is NO
--- BETTER (same raycast technique, same result: a constant radius off the smallest
--- axis) -- neither of Roblox's two round primitive Shapes takes an unequal
--- cross-section, however unequal the Size you give one. Every "oval" pool built by
--- either of those two Shapes, across every earlier pass of this file, was a plain
--- circle wearing an oval-shaped comment.
---
--- SpecialMesh (MeshType.Sphere, independent non-uniform Scale) is what actually
--- renders as an ellipsoid -- confirmed the same way, by screenshot: a flattened
--- sphere mesh scaled {80, 4, 35} rendered as a visibly elongated oval, not a circle.
--- So a puddle disc here is a near-invisible 1x1x1 Part (Transparency 0, but its own
--- Size never reads as anything -- the child mesh fully replaces what gets drawn)
--- carrying that mesh, scaled to {a, POOL_THICK, b} directly -- no R.cylUp reorienting
--- dance needed either, since a sphere has no axis to stand upright in the first
--- place: local X and Z already sit in the ground plane, `yaw` just turns them there.
--- Color/Material still live on the PART (the mesh has neither of its own), exactly
--- as before.
local function oozeDisc(
	parent: Instance,
	origin: CFrame,
	name: string,
	x: number,
	y: number,
	z: number,
	a: number,
	b: number,
	yaw: number,
	color: string,
	material: string
)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = Vector3.new(1, 1, 1) -- irrelevant once the mesh below is parented; kept
	-- small so this part's own (invisible, never-rendered) box can't be mistaken for
	-- real geometry by anything that walks Workspace looking at BasePart.Size directly.
	part.Color = Color3.fromHex(color)
	part.Material = Enum.Material[material]
	part.CFrame = origin * CFrame.new(x, y - POOL_THICK / 2, z) * Kit.ang(0, yaw, 0)

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(a, POOL_THICK, b)
	mesh.Parent = part

	part.Parent = parent
	return part
end

--- One puddle, `radius` studs from centre to outline at its widest, centred on the
--- stage-local point (x, z). `hx`/`hz` are the field's own half-extents, so a droplet
--- thrown off a puddle near the boundary can be held inside the field -- see the note
--- at the droplet loop below, this was found overhanging the edge by up to 3.3 studs
--- on a live check.
local function oozePool(
	parent: Instance,
	origin: CFrame,
	x: number,
	z: number,
	radius: number,
	rng: Random,
	ooze: { bright: string, deep: string, glow: string },
	hx: number,
	hz: number
)
	local yaw = rng:NextNumber(0, 360)
	-- The body oval. `aspect` is how much longer it is than it is wide. RAISED OFF THE
	-- FLOOR TWICE, on request ("turn the circles to more oval shapes") -- 1.0 used to
	-- be a legal roll and a puddle that landed near it read as a plain circle with a
	-- few bumps on it. The first raise (1.35-2.1) was not enough on its own: shot live
	-- from directly overhead, a lobe sized close to the body's own width and sitting
	-- AT the tip rounded that tip off into its own little circle, so the whole puddle
	-- still read as "circle plus a bump" rather than as one long oval -- see the note
	-- on lobe SIZE below, which is the other half of this fix. The ceiling is still
	-- about as far as a puddle can stretch before it reads as a painted stripe rather
	-- than as standing liquid.
	local bodyA = radius * 2
	local bodyB = bodyA / rng:NextNumber(1.6, 2.6)

	--- How far the body's own outline is from its centre along a compass bearing --
	--- the polar radius of an ellipse, so the lobes below can be placed against the
	--- real outline instead of against the circle it is NOT.
	local function bodyEdge(bearingDeg: number): number
		local t = math.rad(bearingDeg - yaw)
		local ea, eb = bodyA / 2, bodyB / 2
		local ct, st = math.cos(t), math.sin(t)
		return (ea * eb) / math.sqrt((eb * ct) ^ 2 + (ea * st) ^ 2)
	end

	-- The outline, solved before anything is built: the body plus its ring of lobes.
	--
	-- SMALLER LOBES, SWALLOWED DEEPER, ON REQUEST ("give the pools more curve"). The
	-- first pass's lobes were up to 1.15x the body's own size at up to 1.3x reach --
	-- close enough to the body's own scale that a puddle read as a cluster of
	-- similar-sized circles (a flower, or a bunch of grapes) rather than as one shape
	-- with a curved edge. Lobes are now well under the body's scale and mostly land
	-- SHORT of tangent, so most of them only swell one stretch of the outline into a
	-- gentle sweep instead of poking out as a separate rounded lump.
	--
	-- ONE LOBE PER PUDDLE IS ALLOWED TO BREAK THAT RULE -- the reference this shape is
	-- built on has exactly one small foot-like protrusion off an otherwise smooth
	-- outline, not a symmetric ring of equal bumps. `i == count` (the last lobe placed,
	-- itself an arbitrary pick off the evenly-spaced ring) gets a wider size and reach
	-- range so roughly one puddle feature reads as a real protruding foot while the
	-- rest of the outline stays a single sweeping curve.
	local lobes: { { ox: number, oz: number, a: number, b: number, yaw: number } } =
		{ { ox = 0, oz = 0, a = bodyA, b = bodyB, yaw = yaw } }
	local count = rng:NextInteger(2, 4)
	for i = 1, count do
		-- BEARING NEAR ONE OF THE BODY'S TWO POLES (yaw or yaw + 180), NOT ANYWHERE
		-- ROUND THE RING -- found live, and this is the fix for it, not a taste call.
		-- The body is already an elongated ellipse, but a lobe dropped at a bearing
		-- near +-90 off that axis bulges the WAIST outward, and widening the middle is
		-- exactly what cancels an oval's own length back toward a circle -- shot live,
		-- a pool measuring 1.8:1 on its own body still read as round because its
		-- lobes had landed on the sides.
		--
		-- +-55 WAS STILL TOO WIDE -- the first attempt at this same fix, caught on a
		-- SECOND live shot. An ellipse's own polar radius does not fall off linearly
		-- with angle: at 2.2:1 aspect, the edge distance 55 degrees off the pole is
		-- already most of the way down to the MINOR axis's own value (measured:
		-- 16.5 studs at 55 degrees vs 31.7 at the pole itself, on a body whose short
		-- axis is only 14.1) -- so a "+-55 off the pole" lobe was still landing
		-- somewhere close to the waist in practice, not the tip, and the fix did not
		-- fix it. +-20 is what actually keeps a lobe's centre near the pole's own
		-- radius (28.1 of 31.7 at 20 degrees off) rather than sliding toward the side.
		-- Alternating ends (i odd -> the yaw end, i even -> the opposite end) still
		-- allows a lobe to land off-centre for asymmetry -- this is not "only ever
		-- exactly at the tip" -- it just can no longer drift far enough to fight the
		-- ellipse it is sitting on.
		local pole = if i % 2 == 1 then yaw else yaw + 180
		local bearing = pole + rng:NextNumber(-20, 20)
		local isFoot = i == count
		-- SMALL, ON PURPOSE -- the other half of the "still reads round" fix above. A
		-- lobe anywhere near the body's own minor-axis width (bodyB, ~17-25% of
		-- `radius` at these aspects) caps the tapered tip with a rounder, wider hump
		-- instead of extending it, which is what rounded the whole puddle off live.
		-- Regular lobes are now well under that width; only the one foot lobe is
		-- allowed up near it, and even it stays short of the body's own scale.
		local la = radius * rng:NextNumber(if isFoot then 0.28 else 0.14, if isFoot then 0.5 else 0.26)
		-- ALIGNED WITH THE BEARING, NOT FREE -- a lobe elongated ALONG the axis it
		-- sits on extends the body's own taper; one elongated across it (the old fully
		-- random yaw) is a wide cap on the tip, the exact failure this whole pass is
		-- fixing. The +-20 jitter is enough to keep every lobe from looking like a
		-- ruler-straight extension of the body without ever pointing far enough off
		-- axis to read as a cross-bar.
		local lb = la / rng:NextNumber(1.2, 2.2)
		local lyaw = bearing + rng:NextNumber(-20, 20)
		-- (edge - la / 2) is exactly tangent inside the body. Rolling either side of
		-- that is what makes the outline irregular: under it the lobe is swallowed and
		-- only softens the curve, over it the lobe bulges out past it. The ceiling is
		-- well short of (edge + la / 2), so a lobe can never detach from the body. Most
		-- lobes stay under 1.0 (swallowed, a soft sweep); the one foot lobe is allowed
		-- past it for a real protrusion.
		local reach = (bodyEdge(bearing) - la / 2) * rng:NextNumber(0.45, if isFoot then 1.2 else 0.95)
		table.insert(lobes, {
			ox = math.cos(math.rad(bearing)) * reach,
			oz = math.sin(math.rad(bearing)) * reach,
			a = la,
			b = lb,
			yaw = lyaw,
		})
	end

	-- Every part of this puddle steps up by one lift in draw order. See the section
	-- header: this is the layering, not just a z-fight guard.
	local lift = 0
	local function nextY(baseY: number): number
		lift += POOL_LOBE_LIFT
		return baseY + lift
	end

	-- ONE GREEN, NOT A SHADE PER LOBE. The body and every lobe are the same
	-- `ooze.bright`, so the union reads as one pool of one liquid rather than as the
	-- overlapping discs it is actually built from -- which is the whole point of the
	-- lobes: they are there to shape the OUTLINE, and any colour difference between
	-- them draws each disc's boundary back on top of the shape they were hiding.
	local bodyPart: BasePart? = nil
	for index, lobe in lobes do
		local part = oozeDisc(parent, origin, "OozePool", x + lobe.ox, nextY(POOL_TOP), z + lobe.oz, lobe.a, lobe.b, lobe.yaw, ooze.bright, POOL_MATERIAL)
		if index == 1 then
			bodyPart = part
		end
	end

	-- THE GLOW, ON REQUEST -- Neon alone reads as "bright", not as "lighting the
	-- ground around it". One PointLight per pool, on the body part only (never a
	-- lobe or a droplet -- a light on every one of those would be a light for every
	-- few studs across the whole field, and the ground under a small spill does not
	-- need its own halo). `ooze.glow`, the triple's third slot, finally has a caller
	-- again -- it sat unused from the moment the rim (which used to occupy `deep`)
	-- and the interior detail came off. `deep` itself stays unused; there is nothing
	-- dark left anywhere in this field for it to paint.
	--
	-- SCALED OFF RADIUS, NOT ONE FLAT NUMBER, same reasoning as the rim width used to
	-- be before it was removed: a 3-stud spill and a 30-stud lake cannot share a
	-- light without one of them looking wrong -- a flat light bright enough to read
	-- on the lake floods a small spill into a blown-out white disc, and one dim
	-- enough to suit a spill barely tints the lake at all. Both ends are still
	-- clamped, not left to the formula: too dim reads as no light at all, and too
	-- bright starts washing out the checkerboard floor past the pool's own edge.
	--
	-- SHADOWS OFF, same call SignalAura's own locator light already made and for the
	-- same reason -- this is marking a glowing surface, not casting geometry-accurate
	-- shadows off scattered props, and shadow casting is the expensive part of a
	-- PointLight. With 12 of these alight in the field at once, that is not optional.
	if bodyPart then
		Kit.light(bodyPart, ooze.glow, math.clamp(radius * 1.3, 10, 46), math.clamp(radius * 0.07, 0.7, 2.4), false)
	end

	-- Thrown clear of the blob, each on its own bearing -- droplets, not a second pool.
	--
	-- HELD INSIDE THE FIELD, ON A LIVE CHECK. A puddle's own centre is clamped to the
	-- field by its caller (scatterOozePools), but a droplet is placed relative to THAT
	-- centre at up to 1.7x the body's edge reach with no clamp of its own -- a puddle
	-- sitting near the north or south boundary can throw one past it. Measured live:
	-- two drops off puddles near z = +-85 stuck out by 3.3 and 1.25 studs. Clamped to
	-- the field's own half-extents rather than shrinking the reach range, so the
	-- puddles that are NOT near an edge keep throwing drops exactly as before.
	for _ = 1, rng:NextInteger(3, 6) do
		local bearing = rng:NextNumber(0, 360)
		local reach = bodyEdge(bearing) * rng:NextNumber(1.08, 1.7)
		local da = math.clamp(radius * rng:NextNumber(0.05, 0.16), 0.6, 3.4)
		local dx = math.clamp(x + math.cos(math.rad(bearing)) * reach, -hx, hx)
		local dz = math.clamp(z + math.sin(math.rad(bearing)) * reach, -hz, hz)
		oozeDisc(parent, origin, "OozeDrop", dx, nextY(POOL_TOP), dz, da, da / rng:NextNumber(1.0, 1.5), rng:NextNumber(0, 360), ooze.bright, POOL_MATERIAL)
	end
end

--- Stage 4 -- `count` ooze puddles over the whole field, dealt off a size ladder so no
--- two are the same scale, on the same jittered grid scatterBushes uses. The cell
--- aspect comes off the field's own, so a 290 x 170 stage gets wider-than-tall cells
--- rather than a square grid stretched over it.
---
--- THE MINI LAKE IS PLACED BY HAND, NOT DEALT. It is the one thing in this field big
--- enough to be a landmark, and a landmark that can land anywhere is not one -- so it
--- goes down first, in the middle of the walk rather than tucked against the entrance
--- where the sign rank already is, and the grid pools are pushed OUT of it afterwards
--- (a pool inside the lake is not a second pool, it is more lake). It is a landmark on
--- SIZE alone now -- it used to carry islands the other pools did not, and those went
--- with the rest of the interior detail.
---
--- NO CENTRE LANE HERE, unlike the bushes, carcasses and drum dumps -- those three all
--- keep a clear corridor down z = 0 because each is a thing you would have to walk
--- AROUND. A puddle is a flat layer you walk straight over (nothing here collides), so
--- holding it off the route would only make the route the one clean stripe in a
--- contaminated field, which is the opposite of the read.
---
--- RUNS AFTER scatterWarningSigns, always: both passes draw on the one stage rng, so
--- putting the puddles first would move every sign in the entrance rank.
local function scatterOozePools(
	folder: Instance,
	origin: CFrame,
	count: number,
	rng: Random,
	hx: number,
	hz: number,
	ooze: { bright: string, deep: string, glow: string }
)
	-- The lake: one per field.
	local lakeR = rng:NextNumber(26, 33)
	local lakeX = rng:NextNumber(-hx * 0.3, hx * 0.45)
	local lakeZ = rng:NextNumber(-hz + lakeR, hz - lakeR)
	oozePool(folder, origin, lakeX, lakeZ, lakeR, rng, ooze, hx, hz)

	-- The rest, as a size ladder: broad pools, mid ones, then spills. Dealt from a
	-- shuffled bag so the sizes are spread over the field instead of the big ones all
	-- landing in the first rows the loop happens to reach.
	local rest = count - 1
	local broad = math.max(1, math.round(rest * 0.3))
	local mid = math.max(1, math.round(rest * 0.36))
	local sizes: { number } = {}
	for i = 1, rest do
		if i <= broad then
			table.insert(sizes, rng:NextNumber(11, 17))
		elseif i <= broad + mid then
			table.insert(sizes, rng:NextNumber(6, 10))
		else
			table.insert(sizes, rng:NextNumber(2.6, 5))
		end
	end
	for i = #sizes, 2, -1 do
		local swap = rng:NextInteger(1, i)
		sizes[i], sizes[swap] = sizes[swap], sizes[i]
	end

	local cols = math.ceil(math.sqrt(rest * (hx / hz)))
	local rows = math.ceil(rest / cols)

	-- COLUMN COUNTS ARE ASSIGNED, NOT ROLLED -- found live, on report ("space them out
	-- more evenly"). The previous build shuffled one flat bag over all `cols * rows`
	-- cells and took the first `rest` -- and for THIS stage's fixed seed, that shuffle
	-- happened to land most of its cells in two or three neighbouring x-bins, leaving
	-- most of the field's own length (the walk axis, the dimension that actually
	-- matters for "spread out") close to bald. A shuffle averages out even over the
	-- long run, but this field is not drawn over and over -- it is ONE fixed seed,
	-- rebuilt identically every time, so an unlucky roll here is not a one-in-many
	-- fluke that washes out, it is the permanent shape of the field.
	--
	-- BOTH AXES BALANCED TOGETHER, NOT ONE AT A TIME -- found live. Column totals
	-- alone (guaranteeing every x-bin its fair share) fixed the bald half of the
	-- field's own length, but then every pool still landed within one narrow strip
	-- across the field's WIDTH, because nothing constrained which rows those column
	-- shares fell on -- fixing one axis on its own just moved the same clustering bug
	-- onto the other one. `colCount`/`rowRemaining` fix each axis's OWN totals the
	-- same way (floor share guaranteed, the small remainder dealt to a shuffled
	-- subset); the greedy assignment below is what makes both hold AT ONCE, by always
	-- handing a column's pools to whichever rows still want the most.
	--
	-- THIRD REPORT ("a lot in the middle... should be scattered more"): the balance
	-- above was doing its job, but the lake's own displacement was undoing it -- see
	-- the note at the block just below, which takes the lake's cells out of the deal
	-- BEFORE the balance runs rather than shoving pools off the lake afterwards.
	local function evenShare(total: number, bins: number): { number }
		local baseShare = math.floor(total / bins)
		local leftover = total - baseShare * bins
		local share = table.create(bins, baseShare)
		if leftover > 0 then
			local order = table.create(bins)
			for i = 1, bins do
				order[i] = i
			end
			for i = bins, 2, -1 do
				local swap = rng:NextInteger(1, i)
				order[i], order[swap] = order[swap], order[i]
			end
			for i = 1, leftover do
				share[order[i]] += 1
			end
		end
		return share
	end

	-- THE LAKE'S CELLS ARE TAKEN OUT OF THE DEAL, NOT PATCHED AFTER IT -- found live
	-- ("a lot in the middle... should be scattered more"). The lake sits near the
	-- field's centre, and the old code let the grid deal pools into the cells it
	-- covers and THEN shoved each of those pools radially out to just past the
	-- lake's rim -- which swept a whole handful of them onto one tight ring hugging
	-- the lake, reading as a single clump in the middle of an otherwise sparse
	-- field. Marking the covered cells unavailable BEFORE the deal spreads the same
	-- eleven pools over the cells that are actually open, out toward the edges.
	local cellW, cellH = 2 * hx / cols, 2 * hz / rows
	local function cellCenter(col: number, row: number): (number, number)
		return -hx + (col - 0.5) * cellW, -hz + (row - 0.5) * cellH
	end
	local blocked: { [number]: { [number]: boolean } } = {}
	local blockRadiusSq = (lakeR + math.max(cellW, cellH) * 0.5) ^ 2
	local freeCells = cols * rows
	for col = 1, cols do
		blocked[col] = {}
		for row = 1, rows do
			local ccx, ccz = cellCenter(col, row)
			if (ccx - lakeX) ^ 2 + (ccz - lakeZ) ^ 2 < blockRadiusSq then
				blocked[col][row] = true
				freeCells -= 1
			end
		end
	end
	-- If the lake ate so many cells that the rest no longer fit, hand back the
	-- blocked ones whose centres are farthest from it first -- a pool there still
	-- clears the lake by the widest margin available.
	if freeCells < rest then
		local reclaim: { { col: number, row: number, d: number } } = {}
		for col = 1, cols do
			for row = 1, rows do
				if blocked[col][row] then
					local ccx, ccz = cellCenter(col, row)
					table.insert(reclaim, { col = col, row = row, d = (ccx - lakeX) ^ 2 + (ccz - lakeZ) ^ 2 })
				end
			end
		end
		table.sort(reclaim, function(a, b)
			return a.d > b.d
		end)
		for i = 1, math.min(#reclaim, rest - freeCells) do
			blocked[reclaim[i].col][reclaim[i].row] = nil
		end
	end

	local colFree: { { number } } = {}
	for col = 1, cols do
		colFree[col] = {}
		for row = 1, rows do
			if not blocked[col][row] then
				table.insert(colFree[col], row)
			end
		end
	end

	-- Even column totals, each CAPPED at that column's open-cell count; whatever
	-- doesn't fit is dealt on to the columns that still have room (shuffled, so it
	-- is not always the low-index ones that absorb it).
	local colCount = table.create(cols, 0)
	local remainder = rest
	for col = 1, cols do
		local give = math.min(math.floor(rest / cols), #colFree[col])
		colCount[col] = give
		remainder -= give
	end
	local spare = table.create(cols)
	for c = 1, cols do
		spare[c] = c
	end
	for c = cols, 2, -1 do
		local swap = rng:NextInteger(1, c)
		spare[c], spare[swap] = spare[swap], spare[c]
	end
	while remainder > 0 do
		local moved = false
		for _, col in spare do
			if remainder > 0 and colCount[col] < #colFree[col] then
				colCount[col] += 1
				remainder -= 1
				moved = true
			end
		end
		if not moved then
			break
		end
	end

	local rowRemaining = evenShare(rest, rows)

	local colOrder = table.create(cols)
	for c = 1, cols do
		colOrder[c] = c
	end
	for c = cols, 2, -1 do
		local swap = rng:NextInteger(1, c)
		colOrder[c], colOrder[swap] = colOrder[swap], colOrder[c]
	end

	local cellFilled: { [number]: { [number]: boolean } } = {}
	for _, col in colOrder do
		cellFilled[col] = {}
		-- Rank this column's OPEN row-slots by how much each row still wants
		-- (descending), shuffled first so ties -- and there are usually several,
		-- most rows sit at the same remaining count most of the time -- do not
		-- always resolve toward the same row.
		local ranked = table.clone(colFree[col])
		for r = #ranked, 2, -1 do
			local swap = rng:NextInteger(1, r)
			ranked[r], ranked[swap] = ranked[swap], ranked[r]
		end
		table.sort(ranked, function(a, b)
			return rowRemaining[a] > rowRemaining[b]
		end)
		for i = 1, math.min(colCount[col], #ranked) do
			local row = ranked[i]
			cellFilled[col][row] = true
			rowRemaining[row] -= 1
		end
	end

	local dealt = 0
	for col = 1, cols do
		for row = 1, rows do
			if not cellFilled[col][row] then
				continue
			end
			dealt += 1
			local r = sizes[dealt]
			local px = -hx + (col - 0.5 + rng:NextNumber(-0.34, 0.34)) * cellW
			local pz = -hz + (row - 0.5 + rng:NextNumber(-0.34, 0.34)) * cellH

			-- BACKSTOP ONLY -- the lake's cells are already out of the deal, so this
			-- almost never fires; it just catches a pool whose cell-jitter nudged it
			-- into the rim. Slide it straight back out along the bearing from the
			-- lake's centre (no +6 spacing buffer this time -- a hair's clearance is
			-- all a jitter-sized overlap needs).
			local dx, dz = px - lakeX, pz - lakeZ
			local dist = math.sqrt(dx * dx + dz * dz)
			local need = lakeR + r
			if dist < need then
				local ux = if dist > 0.01 then dx / dist else 1
				local uz = if dist > 0.01 then dz / dist else 0
				px, pz = lakeX + ux * need, lakeZ + uz * need
			end

			oozePool(folder, origin, math.clamp(px, -hx, hx), math.clamp(pz, -hz, hz), r, rng, ooze, hx, hz)
		end
	end
end

local function buildStageScenery(parent: Instance, id: number)
	local theme = THEME[id]
	if theme == nil then
		return
	end

	local def = Stages.get(id)
	local folder = Instance.new("Folder")
	folder.Name = `Stage{id}`

	-- Deterministic per stage: a rebuild reproduces the same field, so "it looked
	-- better before" is never something you have to chase.
	local rng = Random.new(1000 + id)

	-- Everything is placed relative to the stage's own surface plane.
	local origin = CFrame.new(def.center[1], Stages.SURFACE_Y, def.center[2])
	local hx, hz = def.size[1] / 2 - 14, def.size[2] / 2 - 14

	-- WHAT USED TO BE HERE: the OozeSurface build call -- one translucent Neon
	-- plate over the whole stage, raised WADE_HEIGHT above the floor. REMOVED, see
	-- this file's own header. The stage's colour identity (PLAN's "the coral one
	-- is the detector shop" rule extended to stages) is no longer this plate's
	-- job -- it now lives in the floor, from buildStageCheckerboard's two-tone board
	-- (and StageFields.luau's plate paint underneath as a fallback).

	-- THE REWORK, ONE STAGE AT A TIME. The strip-for-rework pass (`1b6ff88`) took out
	-- two loops here -- ooze pools and a jittered-grid prop scatter. They come back per
	-- stage, gated on `theme.scatter`, each with its own bespoke placement (see the
	-- scatter* functions): Stage 2's dead trees flank the corridor, Stage 1's bushes
	-- fill its living west half.
	--
	-- STILL ON THE SHELF: every `prop()` set-piece kind for the fields that have not
	-- had their pass yet. `THEME` and `prop()` are still defined above -- the full
	-- previous implementation, with its per-stage tuning rationale, is in git history
	-- on this file rather than dead code here. The de-neon pass swapped their materials
	-- to matte and dropped their PointLights; revived, they render flat like everything
	-- else. (The barrels came OFF the shelf with Stage 3's drums -- `radBarrel`, which
	-- replaced the dormant `barrel()`. The POOLS came off it with Stage 4's puddles --
	-- `oozePool`, a rebuild rather than a revival; the fields still waiting on their own
	-- pass read `theme.pools` for nothing until they call scatterOozePools too.)
	if theme.scatter then
		if id == 1 then
			scatterBushes(folder, origin, theme.props, 3, rng, hx, hz)
			scatterStage1Cracks(folder, origin, def.size[1] / 2, def.size[2] / 2, rng)
			scatterDeadBushes(folder, origin, theme.deadProps or 0, rng, hx, hz)
		elseif id == 2 then
			scatterFieldTrees(folder, origin, theme.props, rng, hx, hz)
			-- hz - 30 keeps a carcass off the outer wall band, same margin as before.
			scatterBones(folder, origin, rng, hx, hz, hz - 30, theme.skeletons or 0, theme.bones or 0, theme.skulls or 0)
		elseif id == 3 then
			-- Nothing GREW in this field, so the carcasses get almost the full depth to
			-- spread over rather than Stage 2's mid strip -- there is no tree line here
			-- to keep them inside of.
			scatterBones(folder, origin, rng, hx, hz, hz - 12, theme.skeletons or 0, theme.bones or 0, theme.skulls or 0)
			-- AFTER the bones, always: both passes run off the one stage rng, so putting
			-- the drums first would move every bone in the field.
			scatterBarrels(folder, origin, theme.barrels or 0, rng, hx, hz)
		elseif id == 4 then
			-- The `barriers` set piece (`theme.props`) is still on the shelf; the signs
			-- and the puddles are what this field has had its pass on so far.
			scatterWarningSigns(folder, origin, theme.signs or 0, rng, hx, hz)
			-- AFTER the signs, always: both passes run off the one stage rng, so putting
			-- the puddles first would move every sign in the entrance rank.
			scatterOozePools(folder, origin, theme.pools, rng, hx, hz, def.ooze)
		end
	end

	folder.Parent = parent
end

--- Every stage's ground: a studded two-tone checkerboard cap, the same 3-stud board
--- as the plaza and the base pads (`Hub.tileRect`, one shared grid so the tiles stay
--- in register across every edge), painted in each stage's own colour.
---
--- WAS STAGE 1 ONLY (`buildStage1Checkerboard`). Extended to all six on request —
--- "the same floor texture on every stage". Stages 2-6 used to show their raw plate:
--- Sand dots, Slate, Glass. Those materials are gone from view now (the plate keeps
--- them as a fallback under the cap; nothing sees it).
---
--- WHY A CAP LAYER AND NOT THE PLATE ITSELF.
--- The obvious implementation is to cut Workspace.Stages.Stage{id} into coloured
--- plates, and it is the one thing this file's header forbids. StageService walks that
--- folder at 10 Hz and resolves overlaps as "smallest XZ area wins", so extra plates
--- would quietly decide which stage you are standing in; and DigService.stagePart
--- looks each stage up BY NAME and would find nothing. One plate per stage, always.
--- The colour goes on top, here, where it is free to be as many parts as it likes.
---
--- Thin, CanCollide and CanQuery false, at GROUND_SKIM: a player still stands on
--- Stages.SURFACE_Y, DigService still buries against it, and FieldController's
--- range-ring raycast passes through to the real plate. `Hub.tileRect` has no option
--- for that (the plaza and pads want solid, queryable tiles), so it is a deliberate
--- after-the-fact override of these folders' own tiles only.
---
--- THE TWO SHADES ARE twoTone(def.color) — the stage's one configured colour split
--- into a near-identical dark/light pair (see twoTone). UNTINTED, on request: the
--- ooze tint StageFields bakes into the plate is NOT carried up here, so the board
--- reads as the stage's base colour (tan, plum, violet) rather than as glowing
--- sludge.
---
--- STAGE 1 KEEPS ITS GRADIENT, the one exception. A flat colour reads as a harder
--- edge against the plaza than a soft hand-off does, so Stage 1's board fades across
--- its width: the plaza's actual tile colours at the west edge (where a player
--- arrives from camp — that one endpoint stays plaza-tinted, or the x=100 seam
--- snaps), blending to Stage 1's own untinted twoTone at the east edge. Each tile
--- computes its colour from a continuous lerp on its world X, so there is no band
--- count to tune and no seam — the board is already thousands of small tiles. Z
--- never affects colour.
local function buildStageCheckerboard(parent: Instance, id: number)
	local def = Stages.get(id)
	local minX = def.center[1] - def.size[1] / 2
	local maxX = def.center[1] + def.size[1] / 2
	local minZ = def.center[2] - def.size[2] / 2
	local maxZ = def.center[2] + def.size[2] / 2

	local stageDark, stageLight = twoTone(def.color) -- Color3 pair, untinted

	local colorAt: ((x: number, z: number) -> (string, string))? = nil
	local flatDark: string? = nil
	local flatLight: string? = nil

	if id == 1 then
		-- West endpoint = the plaza's real tile colours (C.plazaTile* blended toward
		-- Stage 1's ooze, exactly as Hub's own PLAZA_DARK/LIGHT are), so the board is
		-- continuous across x = Hub.PLAZA.maxX. East endpoint, and the whole of every
		-- other stage, is the raw untinted twoTone.
		local wD = Color3.fromHex(Kit.blendHex(C.plazaTileDark, def.ooze.bright, Stages.GROUND_OOZE_TINT))
		local wL = Color3.fromHex(Kit.blendHex(C.plazaTileLight, def.ooze.bright, Stages.GROUND_OOZE_TINT))
		colorAt = function(x: number, _z: number): (string, string)
			local t = math.clamp((x - minX) / (maxX - minX), 0, 1)
			return wD:Lerp(stageDark, t):ToHex(), wL:Lerp(stageLight, t):ToHex()
		end
	else
		flatDark, flatLight = stageDark:ToHex(), stageLight:ToHex()
	end

	local folder = Instance.new("Folder")
	folder.Name = `Stage{id}`

	Hub.tileRect(folder, { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }, {
		topY = Stages.SURFACE_Y + GROUND_SKIM,
		colorAt = colorAt,
		dark = flatDark,
		light = flatLight,
	})

	-- See this function's header: footing / burial / the range-ring raycast all stay
	-- on the real plate under this cap, so every tile drops out of physics and
	-- queries. Hub.tileRect can't do this itself — the plaza and pads want the
	-- opposite — so it's an override of these folders' tiles only.
	for _, tile in folder:GetChildren() do
		if tile:IsA("BasePart") then
			tile.CanCollide = false
			tile.CanQuery = false
		end
	end

	folder.Parent = parent
end

--- The camp->Stage 1 entrance line plus one strip per INTERNAL stage seam -- see
--- BORDER_WIDTH's comment for what these are and why only Stage 6's east edge has none.
---
--- SEAMS ARE READ, NOT HARDCODED. Every stage's east edge is the next stage's west
--- edge exactly (Config/Stages centres them that way and World.verify() rejects any
--- overlap), so the seam X is the shared edge between consecutive stages once they
--- are sorted west-to-east; the camp line sits on the first stage's west edge, which
--- is Hub.PLAZA.maxX. This chain has been reordered and resized more than once
--- already -- same reasoning as buildBoundaryWalls reading its own bounds.
local function buildStageBorderLines(parent: Instance)
	local ids = table.clone(Stages.builtIds())
	table.sort(ids, function(a, b)
		return Stages.get(a).center[1] < Stages.get(b).center[1]
	end)

	local folder = Instance.new("Folder")
	folder.Name = "StageBorders"

	local y = Stages.SURFACE_Y + SKIM
	local rowWidth = BORDER_WIDTH / BORDER_ROWS

	-- One strip centred on `seamX`, spanning minZ..maxZ.
	local function strip(seamX: number, minZ: number, maxZ: number, name: string)
		local x0 = seamX - BORDER_WIDTH / 2
		local cols = math.ceil((maxZ - minZ) / BORDER_CELL_Z)
		for ix = 0, BORDER_ROWS - 1 do
			local cx0 = x0 + ix * rowWidth
			for iz = 0, cols - 1 do
				local z0 = minZ + iz * BORDER_CELL_Z
				local z1 = math.min(z0 + BORDER_CELL_Z, maxZ)
				local d = z1 - z0
				if d <= 1e-3 then
					continue
				end

				local yellow = (ix + iz) % 2 == 0
				build(folder, CFrame.new(0, 0, 0), {
					name = name,
					pos = { cx0 + rowWidth / 2, y, (z0 + z1) / 2 },
					size = { rowWidth, 0.4, d },
					color = if yellow then BORDER_YELLOW else BORDER_BLACK,
					material = "SmoothPlastic", -- matte hazard tape; nothing in the world is Neon any more
					canCollide = false,
				})
			end
		end
	end

	-- Camp -> Stage 1. Stage 1's west edge is exactly Hub.PLAZA.maxX; the strip spans
	-- Stage 1's own Z extent so it reads as one line with the rest of the chain (the
	-- plaza is narrower, but the field is what you are crossing into).
	do
		local wMinX, wMinZ, _, wMaxZ = Stages.bounds(ids[1])
		strip(wMinX, wMinZ, wMaxZ, `Camp-Stage{ids[1]}`)
	end

	-- Every internal stage-to-stage seam. seamX is averaged rather than assumed
	-- equal: if a future edit ever leaves a hair of gap or overlap between two
	-- plates, the line still lands in the middle of it. Z span is the union of both
	-- plates' depth (identical since the uniform passes, taken as a union so this
	-- keeps covering the seam if that stops being true).
	for i = 1, #ids - 1 do
		local _, aMinZ, aMaxX, aMaxZ = Stages.bounds(ids[i])
		local bMinX, bMinZ, _, bMaxZ = Stages.bounds(ids[i + 1])
		strip((aMaxX + bMinX) / 2, math.min(aMinZ, bMinZ), math.max(aMaxZ, bMaxZ), `Seam{ids[i]}-{ids[i + 1]}`)
	end

	-- Same override buildStageCheckerboard's cap tiles take: a thin marker on the
	-- floor must not intercept the detector's range-ring raycast or a dig probe.
	for _, tile in folder:GetChildren() do
		if tile:IsA("BasePart") then
			tile.CanQuery = false
		end
	end

	folder.Parent = parent
end

--- One checkerboard wall, the full length of the chain, at a fixed Z. `faceProperty`
--- is whichever side face actually points back toward the chain on an unrotated
--- part -- "BackSurface" (+Z) for the north wall, "FrontSurface" (-Z) for the south
--- wall -- so the studs render on the side a player can actually see.
---
--- `pairAt(x)` returns the (dark, light) hex pair for a column centred at world X --
--- this is what carries the per-stage colour along the wall. Columns are 4 studs and
--- every stage seam lands on a multiple of that, so no column straddles two stages.
local function buildWall(parent: Instance, name: string, minX: number, maxX: number, atZ: number, faceProperty: string, pairAt: (number) -> (string, string))
	local baseY = Stages.SURFACE_Y
	local cols = math.ceil((maxX - minX) / WALL_TILE)
	local rows = math.ceil(WALL_HEIGHT / WALL_TILE)

	for ix = 0, cols - 1 do
		local x0 = minX + ix * WALL_TILE
		local x1 = math.min(x0 + WALL_TILE, maxX)
		local w = x1 - x0
		if w <= 1e-3 then
			continue
		end

		local darkHex, lightHex = pairAt((x0 + x1) / 2)

		for iy = 0, rows - 1 do
			local y0 = baseY + iy * WALL_TILE
			local y1 = math.min(y0 + WALL_TILE, baseY + WALL_HEIGHT)
			local h = y1 - y0
			if h <= 1e-3 then
				continue
			end

			local tile = build(parent, CFrame.new(0, 0, 0), {
				name = name,
				pos = { (x0 + x1) / 2, (y0 + y1) / 2, atZ },
				size = { w, h, WALL_THICKNESS },
				color = if (ix + iy) % 2 == 0 then darkHex else lightHex,
				material = "Plastic", -- studs only render on Plastic, per Hub.tileRect's note
				canCollide = true, -- see the header: the one deliberate exception in this file
			});
			(tile :: any)[faceProperty] = Enum.SurfaceType.Studs
		end
	end
end

--- A thin studded sheet laid FLAT over a wall's crown -- the stage floor, stacked on
--- top of the wall (requested against a live look: the walls read as raw slabs with a
--- bare top edge). Runs along X at a fixed Z, `WALL_THICKNESS` deep, the full length
--- of the chain, on the same `WALL_TILE` grid as the wall face below it so the checker
--- stays in register looking up the wall.
---
--- `pairAt(x)` is the FLOOR two-tone for the stage behind the column (floorPair via
--- buildBoundaryWalls' resolver), so the crown matches the ground rather than the
--- paler wall. Decorative: `CanCollide`/`CanQuery` false -- nothing stands 55 studs up,
--- and DigService / the range-ring raycast must never see it.
local function buildWallCap(parent: Instance, name: string, minX: number, maxX: number, atZ: number, pairAt: (number) -> (string, string))
	local capY = Stages.SURFACE_Y + WALL_HEIGHT + WALL_CAP_THICKNESS / 2 - 0.1
	local cols = math.ceil((maxX - minX) / WALL_TILE)
	local depthCells = math.ceil(WALL_THICKNESS / WALL_TILE)

	for ix = 0, cols - 1 do
		local x0 = minX + ix * WALL_TILE
		local x1 = math.min(x0 + WALL_TILE, maxX)
		local w = x1 - x0
		if w <= 1e-3 then
			continue
		end

		local darkHex, lightHex = pairAt((x0 + x1) / 2)

		for iz = 0, depthCells - 1 do
			local z0 = -WALL_THICKNESS / 2 + iz * WALL_TILE
			local z1 = math.min(z0 + WALL_TILE, WALL_THICKNESS / 2)
			local d = z1 - z0
			if d <= 1e-3 then
				continue
			end

			local tile = build(parent, CFrame.new(0, 0, 0), {
				name = name,
				pos = { (x0 + x1) / 2, capY, atZ + (z0 + z1) / 2 },
				size = { w, WALL_CAP_THICKNESS, d },
				color = if (ix + iz) % 2 == 0 then darkHex else lightHex,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
			tile.CanQuery = false
		end
	end
end

--- The chain's north and south edges. ONE WALL PER SIDE, NOT SIX -- every stage
--- shares the same Z footprint since the uniform-depth pass, so this is one long
--- straight boundary the full length of the chain rather than a per-stage piece.
---
--- BOUNDS ARE READ, NOT ASSUMED. This chain has moved, resized and had stages
--- reordered more than once already -- hardcoding today's numbers would just be
--- tomorrow's silent bug the next time it changes.
local function buildBoundaryWalls(parent: Instance)
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, id in Stages.builtIds() do
		local ax, az, bx, bz = Stages.bounds(id)
		minX, minZ = math.min(minX, ax), math.min(minZ, az)
		maxX, maxZ = math.max(maxX, bx), math.max(maxZ, bz)
	end

	local folder = Instance.new("Folder")
	folder.Name = "BoundaryWalls"

	-- West-to-east stage list, so a column's X resolves to the stage behind it.
	local ids = table.clone(Stages.builtIds())
	table.sort(ids, function(a, b)
		return Stages.get(a).center[1] < Stages.get(b).center[1]
	end)
	-- The same west-to-east "which stage is behind this column" lookup, wrapped so the
	-- wall face (wallPair) and its crown cap (floorPair) can share one resolver.
	local function pairAtWith(fn: (number) -> (string, string)): (number) -> (string, string)
		return function(x: number): (string, string)
			for _, id in ids do
				local _, _, bx = Stages.bounds(id)
				if x < bx then
					return fn(id)
				end
			end
			return fn(ids[#ids])
		end
	end

	buildWall(folder, "NorthWall", minX, maxX, minZ - WALL_THICKNESS / 2, "BackSurface", pairAtWith(wallPair))
	buildWall(folder, "SouthWall", minX, maxX, maxZ + WALL_THICKNESS / 2, "FrontSurface", pairAtWith(wallPair))

	local capPairAt = pairAtWith(capStagePair)
	buildWallCap(folder, "NorthWallCap", minX, maxX, minZ - WALL_THICKNESS / 2, capPairAt)
	buildWallCap(folder, "SouthWallCap", minX, maxX, maxZ + WALL_THICKNESS / 2, capPairAt)

	folder.Parent = parent
end

--- A short straight run along Z at a fixed X -- the mirror image of `buildWall`
--- (which runs along X at a fixed Z), swapped axes, for the two shoulder pieces
--- below that bridge the base's curved wall to the corridor's straight one.
--- Same tiling, same checkerboard, same stud treatment; the only real difference
--- is which local face ends up pointing at the walkable interior. `buildWall`'s
--- segments are unrotated and expose the field on their +-Z face (hence
--- Front/BackSurface); these are unrotated too but expose it on their +-X face
--- instead, so they take Left/RightSurface.
local function buildShoulderWall(parent: Instance, name: string, atX: number, minZ: number, maxZ: number, faceProperty: string)
	local baseY = Stages.SURFACE_Y
	local cols = math.ceil((maxZ - minZ) / WALL_TILE)
	local rows = math.ceil(WALL_HEIGHT / WALL_TILE)

	for iz = 0, cols - 1 do
		local z0 = minZ + iz * WALL_TILE
		local z1 = math.min(z0 + WALL_TILE, maxZ)
		local d = z1 - z0
		if d <= 1e-3 then
			continue
		end

		for iy = 0, rows - 1 do
			local y0 = baseY + iy * WALL_TILE
			local y1 = math.min(y0 + WALL_TILE, baseY + WALL_HEIGHT)
			local h = y1 - y0
			if h <= 1e-3 then
				continue
			end

			local tile = build(parent, CFrame.new(0, 0, 0), {
				name = name,
				pos = { atX, (y0 + y1) / 2, (z0 + z1) / 2 },
				size = { WALL_THICKNESS, h, d },
				color = if (iz + iy) % 2 == 0 then WALL_BROWN_DARK else WALL_BROWN_LIGHT,
				material = "Plastic", -- studs only render on Plastic, per Hub.tileRect's note
				canCollide = true,
			});
			(tile :: any)[faceProperty] = Enum.SurfaceType.Studs
		end
	end
end

--- `buildWallCap` with the axes swapped -- a thin studded crown sheet running along Z
--- at a fixed X, for the two shoulder pieces, exactly as `buildShoulderWall` is
--- `buildWall` swapped. Flat (dark, light) rather than a per-column resolver: a
--- shoulder is a few studs of one stage's edge, not a colour transition.
local function buildShoulderCap(parent: Instance, name: string, atX: number, minZ: number, maxZ: number, dark: string, light: string)
	local capY = Stages.SURFACE_Y + WALL_HEIGHT + WALL_CAP_THICKNESS / 2 - 0.1
	local cols = math.ceil((maxZ - minZ) / WALL_TILE)
	local depthCells = math.ceil(WALL_THICKNESS / WALL_TILE)

	for iz = 0, cols - 1 do
		local z0 = minZ + iz * WALL_TILE
		local z1 = math.min(z0 + WALL_TILE, maxZ)
		local d = z1 - z0
		if d <= 1e-3 then
			continue
		end

		for ix = 0, depthCells - 1 do
			local x0 = -WALL_THICKNESS / 2 + ix * WALL_TILE
			local x1 = math.min(x0 + WALL_TILE, WALL_THICKNESS / 2)
			local w = x1 - x0
			if w <= 1e-3 then
				continue
			end

			local tile = build(parent, CFrame.new(0, 0, 0), {
				name = name,
				pos = { atX + (x0 + x1) / 2, capY, (z0 + z1) / 2 },
				size = { w, WALL_CAP_THICKNESS, d },
				color = if (iz + ix) % 2 == 0 then dark else light,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
			tile.CanQuery = false
		end
	end
end

--- The base camp's own perimeter -- see this file's header for WHY (there was no
--- wall here at all, and there is a real, raycast-confirmed void-fall gap in the
--- shoulders flanking the corridor's own wall). THREE PIECES, each closing one
--- part of the true footprint's actual edge:
---
---   1. a curved wall following Plots.RING_OUTER's own circle, for every bearing
---      the apron is actually built at -- i.e. everywhere EXCEPT the slice
---      buildApron's own `x <= Hub.PLAZA.maxX` clip already cuts away. There is no
---      ground on the far side of that clip for a wall to guard, so the arc stops
---      exactly where the clip does, not a bearing further.
---   2 & 3. two short straight "shoulder" pieces at x = Hub.PLAZA.maxX, one per
---      side, bridging the arc's own clip-line endpoint down to wherever
---      `buildBoundaryWalls`'s corridor wall already starts on that same side.
---
--- GET ANY ONE OF THE THREE PIECES' OWN JUNCTION COORDINATES WRONG AND IT IS NOT A
--- GRAPHICAL GLITCH, IT IS A HOLE. All three are computed from the same live
--- inputs (Plots.RING_CENTER/RING_OUTER, Hub.PLAZA.maxX, Stages.bounds) rather
--- than measured once and hardcoded, for the same reason `buildBoundaryWalls`
--- reads its own bounds instead of assuming them.
---
--- THE ARC DELIBERATELY SKIPS THE STUD-FACE TREATMENT'S USUAL PRECISION. Every
--- straight wall segment in this file picks ONE fixed local face for its studs
--- because it never rotates; the arc's columns each carry a different world-space
--- yaw, and Roblox resolves a local face (`FrontSurface`) the same way regardless
--- of that yaw, so one fixed face works for the whole curve too -- confirmed live,
--- not just assumed from the geometry. What the arc does NOT attempt is
--- phase-locking that texture's stud grid across columns the way a flat tiled
--- surface would; at this radius the seam between columns is not worth the
--- bookkeeping for a peripheral wall almost nobody stands next to.
local function buildBaseWalls(parent: Instance)
	local cx, cz = Plots.RING_CENTER.x, Plots.RING_CENTER.z
	local wallRadius = Plots.RING_OUTER + WALL_THICKNESS / 2
	local clipX = Hub.PLAZA.maxX

	local stageMinZ, stageMaxZ = math.huge, -math.huge
	for _, id in Stages.builtIds() do
		local _, az, _, bz = Stages.bounds(id)
		stageMinZ, stageMaxZ = math.min(stageMinZ, az), math.max(stageMaxZ, bz)
	end
	local corridorMinZ = stageMinZ - WALL_THICKNESS / 2
	local corridorMaxZ = stageMaxZ + WALL_THICKNESS / 2

	-- Where the wall's own circle (radius wallRadius, not RING_OUTER -- the wall
	-- sits just outside the apron's real edge, same convention buildWall's own
	-- minZ-thickness/2 / maxZ+thickness/2 already uses) crosses x = clipX. Using
	-- Plots' own bearing convention (x = cx + r*sin, z = cz + r*cos): the +Z-side
	-- crossing is bearing `crossing`, the -Z-side crossing is bearing
	-- `180 - crossing`, and the arc that stays on the buildable side of the clip
	-- (x <= clipX) is the LONG way round between them, through bearing 270 (the
	-- far side of the circle from the stage chain), not the short way through 90.
	local halfSpanZ = math.sqrt(wallRadius ^ 2 - (clipX - cx) ^ 2)
	local crossing = math.deg(math.asin((clipX - cx) / wallRadius))
	local startBearing = 180 - crossing
	local endBearing = 360 + crossing

	local folder = Instance.new("Folder")
	folder.Name = "BaseWalls"

	-- THE ARC. Columns sized to roughly WALL_TILE studs of CHORD, not of angle --
	-- the two are only equal in the small-angle limit, and this radius is large
	-- enough that the difference does not matter, but the chord is the one that
	-- actually controls how faceted the curve looks.
	local totalDeg = endBearing - startBearing
	local stepDeg = math.deg(WALL_TILE / wallRadius)
	local cols = math.max(1, math.ceil(totalDeg / stepDeg))
	local rows = math.ceil(WALL_HEIGHT / WALL_TILE)
	local baseY = Stages.SURFACE_Y

	-- Crown cap: the apron colour carried up and over, same as the stage walls now get
	-- (buildWallCap). capY / the ±0.1 bite and the two-radial-cell checker match it.
	local capY = baseY + WALL_HEIGHT + WALL_CAP_THICKNESS / 2 - 0.1
	local capDark, capLight = campCapPair()

	for ix = 0, cols - 1 do
		local a0 = startBearing + ix * (totalDeg / cols)
		local a1 = startBearing + (ix + 1) * (totalDeg / cols)
		local aMid = math.rad((a0 + a1) / 2)
		local halfStepRad = math.rad(a1 - a0) / 2
		local chord = 2 * wallRadius * math.sin(halfStepRad)
		-- The part's centre is the TRUE CHORD MIDPOINT connecting the circle points
		-- at a0 and a1 -- which sits at radius wallRadius*cos(halfStepRad), a hair
		-- inside the circle itself, not ON it. Centring on the circle (radius
		-- wallRadius outright) would still get the chord LENGTH and YAW exactly
		-- right, but every column's own corner would land slightly outside the
		-- true circle point shared with its neighbour -- consecutive columns would
		-- no longer share an exact corner, just a near one. At this step size the
		-- miss is a fraction of a stud, but "a fraction of a stud" is still not
		-- zero, and zero is free here: this is the one line that makes it exact.
		local rMid = wallRadius * math.cos(halfStepRad)
		local px = cx + rMid * math.sin(aMid)
		local pz = cz + rMid * math.cos(aMid)
		local origin = CFrame.new(px, 0, pz) * CFrame.Angles(0, aMid, 0)

		for iy = 0, rows - 1 do
			local y0 = baseY + iy * WALL_TILE
			local y1 = math.min(y0 + WALL_TILE, baseY + WALL_HEIGHT)
			local h = y1 - y0
			if h <= 1e-3 then
				continue
			end

			local tile = build(folder, origin, {
				name = "ArcWall",
				pos = { 0, (y0 + y1) / 2, 0 },
				size = { chord, h, WALL_THICKNESS },
				color = if (ix + iy) % 2 == 0 then WALL_BROWN_DARK else WALL_BROWN_LIGHT,
				material = "Plastic",
				canCollide = true,
			});
			(tile :: any).FrontSurface = Enum.SurfaceType.Studs
		end

		-- Two radial cells of thin studded sheet over this column, checkered on
		-- (ix + cell) like buildWallCap. Each cell keeps this column's chord width and
		-- yaw; only the radius shifts, so the strip follows the curve with the wall.
		for cell = 0, 1 do
			local rCell = rMid + (if cell == 0 then -WALL_TILE / 2 else WALL_TILE / 2)
			local cap = build(folder, CFrame.new(cx + rCell * math.sin(aMid), 0, cz + rCell * math.cos(aMid)) * CFrame.Angles(0, aMid, 0), {
				name = "ArcWallCap",
				pos = { 0, capY, 0 },
				size = { chord, WALL_CAP_THICKNESS, WALL_TILE },
				color = if (ix + cell) % 2 == 0 then capDark else capLight,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
			cap.CanQuery = false
		end
	end

	-- THE TWO SHOULDERS. -halfSpanZ/+halfSpanZ are the arc's own clip-line
	-- endpoints; corridorMinZ/corridorMaxZ are where buildBoundaryWalls' corridor
	-- wall already starts. A 1-stud overlap on the corridor side (not an exact
	-- touch) is deliberate -- see Plots.luau's own PLAZA_SKIP_MARGIN comment for
	-- why an exact-touching seam between two independently-computed edges is the
	-- one that grows a gap first the next time either number moves.
	local OVERLAP = 1
	buildShoulderWall(folder, "ShoulderWallNeg", clipX, -halfSpanZ, corridorMinZ + OVERLAP, "LeftSurface")
	buildShoulderWall(folder, "ShoulderWallPos", clipX, corridorMaxZ - OVERLAP, halfSpanZ, "LeftSurface")
	buildShoulderCap(folder, "ShoulderWallNegCap", clipX, -halfSpanZ, corridorMinZ + OVERLAP, capDark, capLight)
	buildShoulderCap(folder, "ShoulderWallPosCap", clipX, corridorMaxZ - OVERLAP, halfSpanZ, capDark, capLight)

	folder.Parent = parent
end

local function createScenery(): Model
	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	Kit.stamp(scenery, BUILDER_SOURCE, BUILDER_VERSION)

	for _, id in Stages.builtIds() do
		buildStageScenery(scenery, id)
	end

	-- Every stage's floor board, foldered together. Was Stage 1 only.
	local floors = Instance.new("Folder")
	floors.Name = "StageFloors"
	for _, id in Stages.builtIds() do
		buildStageCheckerboard(floors, id)
	end
	floors.Parent = scenery

	-- No stage-to-stage blend any more anywhere in the chain -- see the removal note
	-- above STAGE_BLEND's old spot, just above buildStageScenery. Every boundary --
	-- camp/1 and 1/2 through 5/6 -- is a hard cut now, marked by a hazard-checker
	-- line on the ground (buildStageBorderLines) rather than smoothed with a fade.
	buildStageBorderLines(scenery)
	buildBoundaryWalls(scenery)
	buildBaseWalls(scenery)

	-- Nothing in here may claim to be a stage. This is the invariant the whole
	-- module/folder split exists to protect, so it is asserted, not trusted.
	for _, d in scenery:GetDescendants() do
		assert(d:GetAttribute("StageId") == nil, `scenery part {d:GetFullName()} carries a StageId — it would register as a stage`)
	end

	return scenery
end

function Scenery.build(parent: Instance?): Model
	local scenery = createScenery()
	scenery.Parent = parent or Workspace
	return scenery
end

function Scenery.rebuild(parent: Instance?): Model
	local scenery = Kit.swap("Scenery", createScenery, parent) :: Model
	print(`[build] Scenery rebuilt — {#scenery:GetDescendants()} parts`)
	return scenery
end

return Scenery
