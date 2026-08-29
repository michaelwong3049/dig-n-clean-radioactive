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
local BUILDER_VERSION = 10

local C, R = Kit.C, Kit.R
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

--- Just above the plate's top face — close enough to read as lying on the ground,
--- high enough not to z-fight with it.
local SKIM = 0.26

--- The stage colour layer sits BELOW the pools, so a pool still reads as spilled on
--- the ground rather than buried under it. Low enough to be invisible as a step.
local GROUND_SKIM = 0.06

--- Dead wood, for `deadTree`. Darker and greyer than Kit.C.wood (5A4630, which is the
--- warm living-wood brown the camp and the liveTree use) -- these are bark that has
--- had the colour weathered out of it. Builder-local, same as WALL_DARK/WALL_LIGHT:
--- nothing outside this file's trees needs them. Roughly one segment in four takes the
--- darker tone so the flat facets read against each other (the trick foliageBlob uses).
local DEAD_WOOD = "4A3A29"
local DEAD_WOOD_DARK = "372A1D"

--- Living leaf green, for `bush` in Stage 1's alive west end. Brighter and more
--- saturated than the old muted "brush"/"liveTree" scrub greens -- these are meant to
--- pop against the grass like the reference. SmoothPlastic, not Neon, so bloom never
--- touches them: the "green = danger" rule is a NEON-in-a-stage rule, and a matte
--- shrub in Stage 1's own green end reads as life, not hazard.
local BUSH_GREEN = "63B83A"
local BUSH_GREEN_DARK = "4C9029"

--- The chain's north/south boundary walls. Doubled to 56 tall and dropped to a
--- 4-stud tile (from 28/8) after a live look -- ~8,400 parts per side at this size
--- (2,390/4 x 56/4), noticeably more than the first pass's ~1,050 but still well
--- inside what this file's own plaza-adjacent builders already tolerate (the plaza
--- itself is 4,096 tiles alone).
local WALL_HEIGHT = 56
local WALL_THICKNESS = 4
local WALL_TILE = 4
local WALL_DARK = "B5573A" -- rust
local WALL_LIGHT = "9C4A2F" -- a close, subtly darker rust variant -- NOT the first
-- pass's salmon-tan, which read as too bold a two-tone checker up close. One
-- uniform palette for the whole chain either way, deliberately not tinted per
-- stage -- an engineered containment barrier reads as one consistent material, not
-- something that shares each stage's own theme.

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
local function twoTone(hex: string): (Color3, Color3)
	local c = Color3.fromHex(hex)
	return Color3.new(c.R * 0.937, c.G * 0.937, c.B * 0.937), Color3.new(c.R * 1.068, c.G * 1.068, c.B * 1.068)
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

--- HOW MANY POOL LIGHTS A FIELD MAY HAVE, however many pools it has.
---
--- Every pool used to get its own PointLight. That was 39 lights when Stage 1 was the
--- only field in the world and nobody had to think about it; at six fields, with the
--- pink stages carrying 74 and 92 pools each because the pools ARE their colour, it
--- came to 532 and the renderer fell over — screen capture timed out before this was
--- even a gameplay question.
---
--- The cap is safe because a light is not what makes a pool glow. The pool is Neon:
--- it is emissive on its own, at full brightness, whether or not anything is lit
--- beside it. The PointLight only spills that colour onto the props and the ground
--- AROUND it, and eight per field does that job — you cannot tell which pools have
--- one without counting, and a field lit by eight looks the same as one lit by
--- ninety-two.
local STAGE_LIGHT_BUDGET = 8

--- Same argument, applied to the barrels: the spill is Neon and glows regardless, so
--- only every fifth one also throws light.
local BARREL_LIGHT_EVERY = 5

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
---   Stage 1 -- chunky green bushes in the alive west end (scatterBushes).
---   Stage 2 -- big dead trees flanking the corridor (scatterEdgeTrees).
type StageTheme = { props: number, pools: number, kind: string, scatter: boolean? }
local THEME: { [number]: StageTheme } = {
	[1] = { props = 7, pools = 8, kind = "trees", scatter = true },
	[2] = { props = 6, pools = 10, kind = "trees", scatter = true },
	[3] = { props = 40, pools = 20, kind = "sirens" },
	[4] = { props = 18, pools = 26, kind = "barriers" },
	-- The two pink stages. Pool counts climb with the rads because the pools ARE the
	-- colour — the plate underneath is deliberately muted, so a field with few pools
	-- reads as dark ground rather than as hot ground. Prop counts do not climb with
	-- them: past Stage 3 the story is that there is nothing left standing.
	[5] = { props = 22, pools = 60, kind = "reactor" },
	[6] = { props = 26, pools = 78, kind = "shards" },
}

--- A leaking barrel: the story prop. Tipped or standing, always dripping.
---
--- The DRUM is yellow or rust in every field — it is the same drum wherever it was
--- dumped. The SPILL is the stage's own Neon, because the spill is what the field is
--- made of: a barrel leaking acid green into a hot pink Reactor Grounds says the
--- ground got its colour from somewhere else, which is the one thing it did not.
local function barrel(
	parent: Instance,
	origin: CFrame,
	x: number,
	z: number,
	rng: Random,
	ooze: { bright: string, deep: string, glow: string },
	lit: boolean
)
	local tipped = rng:NextNumber() < 0.35
	local color = if rng:NextNumber() < 0.5 then C.barrelYellow else C.barrelRust

	build(parent, origin, {
		name = "Barrel",
		pos = { x, if tipped then 1.1 else 2.1, z },
		size = { 4.2, 2.4, 2.4 },
		color = color,
		material = "Metal",
		shape = "Cylinder",
		rot = if tipped then R.cylAlongZ else R.cylUpFlipped,
	})

	-- The spill coming out of it. This is the bit that sells "oozing".
	local spillW = rng:NextNumber(8, 14)
	local spill = build(parent, origin, {
		name = "Spill",
		pos = { x + rng:NextNumber(-3, 3), SKIM, z + rng:NextNumber(-3, 3) },
		size = { 0.44, spillW, spillW },
		color = ooze.bright,
		material = "Neon",
		shape = "Cylinder",
		rot = R.cylUp,
		transparency = 0.04,
		canCollide = false,
	})
	if lit then
		light(spill, ooze.glow, 18, 2)
	end
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
--- a Wedge cap on every tip. SQUARE section, not Cylinder, on purpose -- the flat
--- facets and hard edges ARE the look, a round trunk reads as a telephone pole. Each
--- segment carries a small roll so an edge faces out rather than a flat face.
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
			material = "SmoothPlastic",
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
				material = "SmoothPlastic",
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
		local block = build(parent, base, {
			name = "Bush",
			pos = { ox, h / 2 - 0.4 + oy, oz },
			size = { w, h, d },
			color = if rng:NextNumber() < 0.55 then BUSH_GREEN else BUSH_GREEN_DARK,
			-- Plastic, not SmoothPlastic: studs only render on Plastic (Hub.tileRect's
			-- note), and studded blocks sit in this world -- which is studded floor to
			-- studded wall -- far better than smooth blobs would. Every face, since a
			-- tilted, stacked block shows more than its top.
			material = "Plastic",
			rot = Kit.ang(rng:NextNumber(-12, 12), rng:NextNumber(0, 90), rng:NextNumber(-12, 12)),
			canCollide = false,
		})
		for _, face in { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" } do
			(block :: any)[face] = Enum.SurfaceType.Studs
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
		local head = build(parent, origin, {
			name = "SirenHead",
			pos = { x, 12.4, z },
			size = { 2.6, 1.8, 2.6 },
			color = C.barrelRust,
			material = "Neon",
			canCollide = false,
		})
		light(head, C.barrelRust, 22, 2)
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
		-- The crack. Neon in the STAGE's own colour, so this glows pink here and would
		-- glow whatever the field glows if the theme is ever reused.
		local vent = build(parent, origin, {
			name = "StackVent",
			pos = { x, h + 5.4, z },
			size = { 1.2, 6.8, 6.8 },
			color = ooze.bright,
			material = "Neon",
			shape = "Cylinder",
			rot = R.cylUp,
			canCollide = false,
		})
		light(vent, ooze.glow, 30, 2.5)
	elseif kind == "shards" then
		-- The Crater: whatever the blast fused, standing up out of the ground. Three
		-- leaning spikes per cluster, each tilted off vertical by a different amount,
		-- because three identical uprights read as a fence.
		for spike = 1, 3 do
			local h = rng:NextNumber(7, 19)
			local shard = build(parent, origin, {
				name = "Shard",
				pos = { x + rng:NextNumber(-5, 5), h / 2, z + rng:NextNumber(-5, 5) },
				size = { rng:NextNumber(1.4, 3.2), h, rng:NextNumber(1.4, 3.2) },
				color = ooze.bright,
				material = "Neon",
				rot = Kit.ang(rng:NextNumber(-22, 22), rng:NextNumber(0, 180), rng:NextNumber(-22, 22)),
				transparency = 0.15,
				canCollide = false,
			})
			-- One light for the cluster, not one per spike. Three overlapping lights
			-- on three touching Neon spikes is indistinguishable from one and costs
			-- three times as much — see STAGE_LIGHT_BUDGET.
			if spike == 1 then
				light(shard, ooze.glow, 22, 2)
			end
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
			material = "Neon",
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

--- Stage 2 -- big dead trees along the two LONG sides, so the travel corridor down the
--- middle stays clear. Count splits as evenly as it can between the north and south
--- edges; within a side the trees sit in even cells across the width, each jittered up
--- to half a cell and pushed a random amount IN off the wall, so the line reads as
--- scattered, never a fence.
local function scatterEdgeTrees(folder: Instance, origin: CFrame, count: number, rng: Random, hx: number, hz: number)
	local perSide = math.ceil(count / 2)
	local placed = 0

	for _, side in { -1, 1 } do -- -1 = north edge (z < 0), +1 = south edge (z > 0)
		local n = math.min(perSide, count - placed)
		for i = 0, n - 1 do
			placed += 1
			local cell = 2 * hx / n
			local x = -hx + (i + 0.5 + rng:NextNumber(-0.5, 0.5)) * cell
			local z = side * (hz - rng:NextNumber(4, 30))
			deadTree(folder, origin, math.clamp(x, -hx, hx), z, rng)
		end
	end
end

--- Stage 1 -- chunky green bushes in the ALIVE WEST END only. Stage 1's ground fades
--- green (west, where you walk in from camp) to dead tan (east); the scrub belongs on
--- the living side. Bushes are placed in the western ~35% of the field, on a jittered
--- grid, and they are allowed near the centreline -- they are low ground cover you see
--- over and walk through, not a wall.
local function scatterBushes(folder: Instance, origin: CFrame, count: number, rng: Random, hx: number, hz: number)
	local westEdge = -hx
	local bandDepth = 2 * hx * 0.35 -- how far east the scrub reaches
	local cols = math.ceil(math.sqrt(count * (bandDepth / (2 * hz))))
	local rows = math.ceil(count / cols)

	local placed = 0
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			if placed >= count then
				break
			end
			placed += 1
			local x = westEdge + (col + 0.5 + rng:NextNumber(-0.6, 0.6)) * (bandDepth / cols)
			local z = -hz + (row + 0.5 + rng:NextNumber(-0.6, 0.6)) * (2 * hz / rows)
			bush(folder, origin, math.clamp(x, westEdge, westEdge + bandDepth), math.clamp(z, -hz, hz), rng)
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
	-- cluster in its living west end.
	--
	-- STILL ON THE SHELF: ooze pools (`theme.pools`), barrels (`barrel()`), and every
	-- `prop()` set-piece kind for the fields that have not had their pass yet. `THEME`,
	-- `prop()`, `barrel()` and the light-budget constants are all still defined above
	-- and untouched -- the full previous implementation, with its per-stage tuning
	-- rationale, is in git history on this file rather than dead code here.
	if theme.scatter then
		if id == 1 then
			scatterBushes(folder, origin, theme.props, rng, hx, hz)
		elseif id == 2 then
			scatterEdgeTrees(folder, origin, theme.props, rng, hx, hz)
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
					material = if yellow then "Neon" else "SmoothPlastic",
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
local function buildWall(parent: Instance, name: string, minX: number, maxX: number, atZ: number, faceProperty: string)
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
				color = if (ix + iy) % 2 == 0 then WALL_DARK else WALL_LIGHT,
				material = "Plastic", -- studs only render on Plastic, per Hub.tileRect's note
				canCollide = true, -- see the header: the one deliberate exception in this file
			});
			(tile :: any)[faceProperty] = Enum.SurfaceType.Studs
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

	buildWall(folder, "NorthWall", minX, maxX, minZ - WALL_THICKNESS / 2, "BackSurface")
	buildWall(folder, "SouthWall", minX, maxX, maxZ + WALL_THICKNESS / 2, "FrontSurface")

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
				color = if (iz + iy) % 2 == 0 then WALL_DARK else WALL_LIGHT,
				material = "Plastic", -- studs only render on Plastic, per Hub.tileRect's note
				canCollide = true,
			});
			(tile :: any)[faceProperty] = Enum.SurfaceType.Studs
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
				color = if (ix + iy) % 2 == 0 then WALL_DARK else WALL_LIGHT,
				material = "Plastic",
				canCollide = true,
			});
			(tile :: any).FrontSurface = Enum.SurfaceType.Studs
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
