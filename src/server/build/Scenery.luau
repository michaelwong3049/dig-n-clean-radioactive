--!strict
--[[
	Scenery.luau — barrels, spills and rubble. Everything on the zones that is not
	the zone.

	    require(game.ServerScriptService.Server.build.Scenery).rebuild()

	WHY THIS IS A SEPARATE MODULE FROM ZoneFields.
	Workspace.Zones must contain the one radioactive plate and NOTHING else. ZoneService walks
	that folder's children ten times a second per player, and — much worse — a prop
	that accidentally carried a ZoneId attribute would register as a zone. Overlapping
	zones resolve as "smallest XZ area wins", so one stray barrel would silently
	become the zone every nearby player is standing in. Keeping decor in a different
	folder makes that class of bug impossible rather than merely unlikely.

	THE OOZE IS THE SURFACE, NOT A HAZARD.
	Per the design call: the plate itself is the sludge you wade through, and the
	pools and spills here are visual variation with NO gameplay rules attached.
	ZoneService.hotPocketFor stays a stub returning 1. This matters for a young
	audience — one rule ("the green ground is dangerous, the paths are not") beats
	two rules ("...but the BRIGHT green is extra dangerous") when the second one is
	only telegraphed by shade.

	"WADE THROUGH" IS NOW LITERAL, NOT JUST WORDING. `OozeSurface` is one translucent
	Neon plate per zone, sized to the whole plate, floating
	`WADE_HEIGHT` above the real floor — about half a leg on a default character.
	Walking into the field sinks your legs into visible ooze instead of just
	standing on tinted ground. It is a SEPARATE part from the actual walking
	surface, not a raised version of it: `Zones.SURFACE_Y` (what DigService buries
	against and what a player's feet actually rest on) never moves. CanCollide is
	false, same as everything else in this file, so it changes nothing about
	movement, burial, or exposure — purely a second, higher, see-through layer.

	NOTHING HERE MAY RISE THROUGH THE DIG SURFACE IN A WAY THAT HIDES IT.
	DigService buries items on the plate's top face and the haul part rises to
	exactly that plane, so anything opaque and tall enough to block the view would
	hide an item surfacing underneath. Props are thin and sit just above;
	anything tall is CanCollide=false so a player can walk out of it.
	`OozeSurface` is the one exception that legitimately sits well above the
	plane — but it stays translucent for exactly this reason, so a surfacing item
	is dimmed, never hidden.

	THE STAGES ARE TOLD APART BY GROUND COLOUR, NOT BY WALLS. buildStageGround paints
	the plate's three stages in their own colours with a short blended seam between
	them; buildStageMarkers puts a signed post and some debris at each boundary so the
	stage still has a name. The concrete barrier that used to stand there is gone — it
	gated nothing and read as unnatural. See buildStageGround for why the colour is a
	layer on top rather than the plate itself.

	Placement is a jittered grid, not pure random. Pure random clumps and leaves bald
	patches; a jittered grid reads as scattered while still covering the field, and
	it is deterministic per zone so a rebuild does not reshuffle the whole world.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Zones = require(Shared.Config.Zones)

local Kit = require(script.Parent.Kit)

local Scenery = {}
local BUILDER_SOURCE = "src/server/build/Scenery.luau"
local BUILDER_VERSION = 4

local C, R = Kit.C, Kit.R
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

--- Just above the plate's top face — close enough to read as lying on the ground,
--- high enough not to z-fight with it.
local SKIM = 0.26

--- The stage colour layer sits BELOW the pools, so a pool still reads as spilled on
--- the ground rather than buried under it. Low enough to be invisible as a step.
local GROUND_SKIM = 0.06

--- Roughly half a leg's height on a default character, so walking into the field
--- reads as WADING into the ooze rather than standing on tinted ground. Purely
--- visual: this is a separate, CanCollide=false plate floating above the real
--- floor, never the floor itself. DigService buries against and a player's actual
--- footing rests on Zones.SURFACE_Y exactly as before -- moving that plane is
--- exactly what ZoneFields.luau's header warns never to do ("tilt or bump a
--- plate and items surface underground"). This gets the same visual without
--- touching it.
local WADE_HEIGHT = 1.1

--- How wide the seam between two stage colours is, in studs. The colour interpolates
--- across this band instead of changing on a line — a dead-straight edge across open
--- ground is its own kind of unnatural, which is the thing being fixed here. Narrow
--- enough that the boundary is still locatable: the loot table changes there, so the
--- player has to be able to tell.
local SEAM_BLEND = 25
local SEAM_STEPS = 8

--- Paint the field in bands across X, one colour per stage, blended at the seams.
---
--- ONLY THE GROUND LAYER IS BANDED, AND THAT WAS NOT THE FIRST ANSWER. The ooze sheet
--- above it was banded too at one point, on the theory that a bright Neon layer would
--- otherwise wash the ground out. It does not — the stage colours carry through it
--- fine once they are actually far apart (see Config/Zones) — and banding it looked
--- much worse: the slabs abut exactly, so at every internal seam two TRANSPARENT
--- faces land on the same plane, the alpha stacks, and the field renders as a set of
--- hard stripes at exactly the grazing angle a player sees it from. One sheet, no
--- coincident faces, no stripes. Do not band a transparent layer.
local function paintBands(folder: Instance, origin: CFrame, def: any, spec: any)
	local stages = Zones.STAGES
	local depth = def.size[2]
	local half = SEAM_BLEND / 2

	local function band(suffix: string, fromX: number, toX: number, colour: Color3)
		local width = toX - fromX
		if width <= 0 then
			return
		end
		local part = build(folder, origin, {
			name = `{spec.name}{suffix}`,
			pos = { (fromX + toX) / 2, spec.y, 0 },
			size = { width, spec.thickness, depth },
			-- Kit.build takes a hex STRING and these are interpolated Color3s, so the
			-- real colour is assigned straight after.
			color = stages[1].color,
			material = spec.material,
			transparency = spec.transparency,
			canCollide = false,
		})
		part.Color = colour
		-- Out of raycasts, so FieldController's range ring still lands on the plate
		-- exactly as it did before either of these layers existed.
		part.CanQuery = false
	end

	for index, stage in stages do
		local colour = Color3.fromHex(stage.color)

		-- The stage's own solid colour, pulled back from each INTERNAL seam. The
		-- outer edges are the field boundary, not a seam, so those run to the end.
		local fromX = if index == 1 then stage.minX else stage.minX + half
		local toX = if index == #stages then stage.maxX else stage.maxX - half
		band(`_Stage{stage.id}`, fromX, toX, colour)

		-- The seam itself, stepped across so one ground gives way to the next rather
		-- than meeting it on a drawn line. Eight steps over 25 studs is already past
		-- where the eye reads banding at head height.
		if index < #stages then
			local nextColour = Color3.fromHex(stages[index + 1].color)
			local step = SEAM_BLEND / SEAM_STEPS
			for s = 0, SEAM_STEPS - 1 do
				local x0 = stage.maxX - half + s * step
				band(`_Seam{stage.id}_{s}`, x0, x0 + step, colour:Lerp(nextColour, (s + 0.5) / SEAM_STEPS))
			end
		end
	end
end

--- THE PLACE WHERE THE WORLD TURNS PINK.
---
--- Zones 1-3 are green and Zone 5 is hot pink, and they meet on a straight line at
--- x = 1240 with nothing in between: two fields parked against each other rather than
--- one becoming the other. This lays the same stepped blend `paintBands` uses between
--- Zone 1's stages across that boundary, half on each side.
---
--- IT IS DRAWN ON BOTH PLATES, WHICH IS THE WHOLE DIFFICULTY. A stage seam lives
--- inside one zone and can be positioned in that zone's local space; this one spans
--- two, so every band is placed in WORLD space and each is clipped to the plate it
--- actually lies on. A band hanging over the edge of both plates would be a strip of
--- floating colour over the void.
---
--- Wider than a stage seam — 25 studs reads as a seam between two shades of the same
--- family, and this is a change of family. 90 reads as ground that is going wrong.
local ZONE_BLEND = 90
local ZONE_BLEND_STEPS = 14

--- Which boundaries get one. Read by `buildZoneScenery` as well as by the builder
--- below, because a blend is not something you can add on top: the zone's own ooze
--- sheet has to get out of the way first. See `oozeInset`.
---
--- 1/2 and 2/3 joined 3/4 when the Zone 1-3 gradient (LIFE FADING INTO A DEAD
--- WASTELAND, see Config/Zones) gave every zone in the chain a genuinely different
--- ground/ooze colour instead of three shades of one green — Zone 1's own pale-sand
--- endpoint into Zone 2's dun tan, and Zone 2's tan into Zone 3's deeper khaki-brown,
--- are real family changes now, same as 3/4 already was.
local ZONE_BLENDS = { { from = 1, to = 2 }, { from = 2, to = 3 }, { from = 3, to = 4 } }

--- How far this zone's ooze sheet must stop short of its west and east edges.
---
--- THE FIRST VERSION OF THE BLEND DID NOT DO THIS AND WAS INVISIBLE. It painted a
--- lovely fourteen-step gradient on the GROUND, and then each zone's ooze sheet — one
--- Neon plate covering the whole field, with a dead-straight edge exactly on the zone
--- boundary — was drawn over the top of it. The bright layer is what you actually
--- see; blending only what is underneath it changes nothing. Both layers have to
--- break at the same place, which is what this is for.
local function oozeInset(zoneId: number): (number, number)
	local west, east = 0, 0
	for _, blend in ZONE_BLENDS do
		if blend.to == zoneId then
			west = ZONE_BLEND / 2
		elseif blend.from == zoneId then
			east = ZONE_BLEND / 2
		end
	end
	return west, east
end

--- Lay the blend. Two bands per step: the ground colour underneath and the ooze
--- colour above it, so the field changes at the same rate at both heights.
local function buildZoneBlend(parent: Instance, fromId: number, toId: number)
	local from, to = Zones.get(fromId), Zones.get(toId)
	local atX = to.center[1] - to.size[1] / 2
	assert(
		math.abs(atX - (from.center[1] + from.size[1] / 2)) < 0.001,
		`zones {fromId} and {toId} do not share an edge — there is nothing to blend across`
	)

	local folder = Instance.new("Folder")
	folder.Name = `Blend{fromId}to{toId}`

	local fromGround, toGround = Color3.fromHex(from.color), Color3.fromHex(to.color)
	local fromOoze, toOoze = Color3.fromHex(from.ooze.bright), Color3.fromHex(to.ooze.bright)
	local step = ZONE_BLEND / ZONE_BLEND_STEPS

	for i = 0, ZONE_BLEND_STEPS - 1 do
		local x0 = atX - ZONE_BLEND / 2 + i * step
		local x1 = x0 + step
		-- Which plate is this band on, and how deep is that plate? The two zones are
		-- rarely the same depth, so a band takes the depth of whichever side it fell
		-- on — otherwise the wider zone's half hangs over the void.
		local side = if x1 <= atX then from else to
		local origin = CFrame.new(0, Zones.SURFACE_Y, side.center[2])
		local t = (i + 0.5) / ZONE_BLEND_STEPS

		local ground = build(folder, origin, {
			name = `BlendGround{i}`,
			pos = { (x0 + x1) / 2, GROUND_SKIM, 0 },
			size = { step, 0.12, side.size[2] },
			color = from.color, -- overwritten below; Kit.build takes a hex STRING
			material = "SmoothPlastic",
			transparency = 0.12,
			canCollide = false,
		})
		ground.Color = fromGround:Lerp(toGround, t)
		ground.CanQuery = false

		-- The same 0.3-thick Neon sheet at the same height and the same transparency
		-- the zones use, so this reads as their sheet continuing rather than as a
		-- separate object laid across the seam.
		local sheet = build(folder, origin, {
			name = `BlendOoze{i}`,
			pos = { (x0 + x1) / 2, WADE_HEIGHT, 0 },
			size = { step, 0.3, side.size[2] },
			color = from.ooze.bright,
			material = "Neon",
			transparency = 0.82,
			canCollide = false,
		})
		sheet.Color = fromOoze:Lerp(toOoze, t)
		sheet.CanQuery = false
	end

	folder.Parent = parent
end

--- How many thin bands Zone 1's own ooze fade uses. Same technique buildZoneBlend
--- already proves safe (many thin steps, small delta each) rather than the FEW WIDE
--- bands buildZoneScenery's OozeSurface comment warns produces hard stripes — 24
--- steps across a 660-stud plate is finer-grained than buildZoneBlend's 14 steps
--- across 90.
local LIFE_FADE_STEPS = 24

--- Presence, not hue, carries "life fading into a wasteland": Zone 1's ooze colour
--- never changes across this fade, only how transparent it is. Near-invisible at
--- the untouched west edge, climbing to every other zone's normal 0.82 by the start
--- of Deep Fallout (STAGES[3]) — flat thereafter, so nothing distinguishes Zone 1's
--- own east third from Zone 2 onward except the ground colour underneath it.
local LIFE_FADE_START_TRANSPARENCY = 0.985

--- Zone 1 only: the OozeSurface as many thin transparency-graded bands instead of
--- buildZoneScenery's usual one flat part. A transparency fade with a small
--- per-step delta never creates a visible seam the way a hue change would — that is
--- what keeps this from becoming the "few wide bands" mistake, not the band count
--- alone.
local function buildGradientOozeSurface(folder: Instance, origin: CFrame, def: any, westInset: number, eastInset: number)
	local startX = -def.size[1] / 2 + westInset
	local endX = def.size[1] / 2 - eastInset
	local fadeEndX = math.clamp(Zones.STAGES[#Zones.STAGES].minX, startX, endX)
	local fadeSpan = fadeEndX - startX

	local step = (endX - startX) / LIFE_FADE_STEPS
	for i = 0, LIFE_FADE_STEPS - 1 do
		local x0 = startX + i * step
		local x1 = x0 + step
		local mid = (x0 + x1) / 2

		local transparency = if fadeSpan <= 0
			then 0.82
			else LIFE_FADE_START_TRANSPARENCY
				+ (0.82 - LIFE_FADE_START_TRANSPARENCY) * math.clamp((mid - startX) / fadeSpan, 0, 1)

		local sheet = build(folder, origin, {
			name = `OozeSurfaceFade{i}`,
			pos = { mid, WADE_HEIGHT, 0 },
			size = { step, 0.3, def.size[2] },
			color = def.ooze.bright,
			material = "Neon",
			transparency = transparency,
			canCollide = false,
		})
		sheet.CanQuery = false
	end
end

--- HOW MANY POOL LIGHTS A FIELD MAY HAVE, however many pools it has.
---
--- Every pool used to get its own PointLight. That was 39 lights when Zone 1 was the
--- only field in the world and nobody had to think about it; at six fields, with the
--- pink zones carrying 74 and 92 pools each because the pools ARE their colour, it
--- came to 532 and the renderer fell over — screen capture timed out before this was
--- even a gameplay question.
---
--- The cap is safe because a light is not what makes a pool glow. The pool is Neon:
--- it is emissive on its own, at full brightness, whether or not anything is lit
--- beside it. The PointLight only spills that colour onto the props and the ground
--- AROUND it, and eight per field does that job — you cannot tell which pools have
--- one without counting, and a field lit by eight looks the same as one lit by
--- ninety-two.
local ZONE_LIGHT_BUDGET = 8

--- Same argument, applied to the barrels: the spill is Neon and glows regardless, so
--- only every fifth one also throws light.
local BARREL_LIGHT_EVERY = 5

--- Per-zone character. `props` is roughly how many set pieces to scatter; the pool
--- count scales with area so a big zone does not look empty.
--- Pool counts climb with the zone: Ash Flats is barely contaminated, the Belt is
--- more ooze than ground. That gradient is the map teaching you what "deeper" means
--- before any number on the HUD does.
---
--- REBALANCED, BACK-LOADED. The old counts (26/40/58/46/74/92) were not actually the
--- climb the comment above describes — 58 to 46 is a DIP at Zone 4, and Zone 1 was
--- already the sparsest field by a wide margin while 2 and 3 were denser than the
--- pink zones that are supposed to read as more contaminated. The new counts are a
--- clean monotonic climb, lighter everywhere (208 pools total, down from 336) and
--- specifically lighter at the front: Zones 1-3 lost roughly two thirds of their
--- pools each and now hold 21% of the field's total (was 37%), while Zones 5-6 lost
--- only a sixth to a fifth and now hold 66% of it (was 49%). Early zones should read
--- clean enough that a pool is a landmark; the Crater should still read as more ooze
--- than ground.
--- Zone 1 and 2's pool counts dropped again (10->8, 14->10) for LIFE FADING INTO A
--- DEAD WASTELAND — on top of buildGradientOozeSurface's own west-to-east thinning
--- within Zone 1 itself, the zone should already read sparser at a glance than the
--- rebalance above assumed. The percentages in the paragraph above are now stale by
--- a few points, not worth re-deriving for a six-pool difference.
local THEME = {
	[1] = { props = 26, pools = 8, kind = "trees" },
	[2] = { props = 34, pools = 10, kind = "houses" },
	[3] = { props = 40, pools = 20, kind = "sirens" },
	[4] = { props = 18, pools = 26, kind = "barriers" },
	-- The two pink zones. Pool counts climb with the rads because the pools ARE the
	-- colour — the plate underneath is deliberately muted, so a field with few pools
	-- reads as dark ground rather than as hot ground. Prop counts do not climb with
	-- them: past Zone 3 the story is that there is nothing left standing.
	[5] = { props = 22, pools = 60, kind = "reactor" },
	[6] = { props = 26, pools = 78, kind = "shards" },
}

--- A leaking barrel: the story prop. Tipped or standing, always dripping.
---
--- The DRUM is yellow or rust in every field — it is the same drum wherever it was
--- dumped. The SPILL is the zone's own Neon, because the spill is what the field is
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

--- Zone-specific silhouette, so the four fields do not read as one field.
--- `ooze` is the ZONE's Neon triple (Config/Zones ZoneDef.ooze), not a global. Only
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
		build(parent, origin, {
			name = "DeadTree",
			pos = { x, 4, z },
			size = { 1.1, 8, 1.1 },
			color = C.wood,
			material = "Wood",
			canCollide = false,
		})
		for _ = 1, 3 do
			build(parent, origin, {
				name = "Branch",
				pos = { x + rng:NextNumber(-1.8, 1.8), rng:NextNumber(5, 7.5), z + rng:NextNumber(-1.8, 1.8) },
				size = { 3.2, 0.35, 0.35 },
				color = C.wood,
				material = "Wood",
				rot = Kit.ang(0, rng:NextNumber(0, 180), rng:NextNumber(-25, 25)),
				canCollide = false,
			})
		end
	elseif kind == "brush" then
		-- Zone 1's Outer Ash stage only (see propKindFor): live scrub, not the dead
		-- "trees" kind the rest of the zone uses — one or two small foliage blobs
		-- low to the ground, deliberately reading as smaller than both DeadTree and
		-- liveTree so none of the three get mistaken for one another at a glance.
		for _ = 1, rng:NextInteger(1, 2) do
			local center = { x + rng:NextNumber(-2, 2), rng:NextNumber(0.9, 1.3), z + rng:NextNumber(-2, 2) }
			foliageBlob(parent, origin, center, rng:NextNumber(1.1, 1.5), "6B8F3E", "547231", rng)
		end
	elseif kind == "liveTree" then
		-- Zone 1's Outer Ash stage only — a branching trunk carrying several
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
		-- The crack. Neon in the ZONE's own colour, so this glows pink here and would
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
			-- three times as much — see ZONE_LIGHT_BUDGET.
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
	else -- "barriers" — Zone 4. Sparse on purpose: PLAN §15 wants it content-free.
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

local function buildZoneScenery(parent: Instance, id: number)
	local theme = THEME[id]
	if theme == nil then
		return
	end

	local def = Zones.get(id)
	local folder = Instance.new("Folder")
	folder.Name = `Zone{id}`

	-- Deterministic per zone: a rebuild reproduces the same field, so "it looked
	-- better before" is never something you have to chase.
	local rng = Random.new(1000 + id)

	-- Everything is placed relative to the zone's own surface plane.
	local origin = CFrame.new(def.center[1], Zones.SURFACE_Y, def.center[2])
	local hx, hz = def.size[1] / 2 - 14, def.size[2] / 2 - 14

	-- The wading surface: ONE translucent plate over the whole zone, raised to
	-- WADE_HEIGHT, so the field reads as something you sink into rather than ground
	-- that happens to be green. Sized to the actual plate (not inset like the
	-- pools/props below), so its edge lines up with the zone boundary.
	--
	-- IT STAYS ONE PART. Splitting it per stage to reinforce the ground colour is the
	-- obvious next idea and it produces hard stripes across the field — see paintBands
	-- for why. The stage colours read through this perfectly well on their own.
	--
	-- High transparency on purpose. Neon's brightness is emissive rather than a true
	-- translucent tint, and bloom pushes an opaque-looking plate this size to a wall
	-- of solid colour well before Transparency looks like it "should" (0.55 first pass
	-- still read as solid ground, not a layer over it). 0.82 is the point props and
	-- the sand below actually show through — including, now, the stage colour.
	local westInset, eastInset = oozeInset(id)
	if id == 1 then
		-- Zone 1 only: LIFE FADING INTO A DEAD WASTELAND (see Config/Zones) means
		-- this zone's own ooze is not uniform west-to-east the way every other
		-- zone's is — see buildGradientOozeSurface for why that is still one
		-- technique, not the banned "few wide bands" one.
		buildGradientOozeSurface(folder, origin, def, westInset, eastInset)
	else
		build(folder, origin, {
			name = "OozeSurface",
			-- Centred on the plate unless one edge is blended, in which case the sheet
			-- stops short of it and buildZoneBlend fills the gap with the stepped
			-- version. `(west - east) / 2` recentres what is left of the sheet.
			pos = { (westInset - eastInset) / 2, WADE_HEIGHT, 0 },
			size = { def.size[1] - westInset - eastInset, 0.3, def.size[2] },
			color = def.ooze.bright,
			material = "Neon",
			transparency = 0.82,
			canCollide = false,
		})
	end

	-- Ooze pools first, so props sit on top of them.
	local lightEvery = math.max(1, math.ceil(theme.pools / ZONE_LIGHT_BUDGET))
	for index = 1, theme.pools do
		local x, z = rng:NextNumber(-hx, hx), rng:NextNumber(-hz, hz)
		local d = rng:NextNumber(18, 46)

		-- Zone 1 only: pools thin out and shrink heading toward the west/life edge,
		-- matching the OozeSurface fade above. t=0 at the untouched west edge, t=1
		-- at the east edge bordering Zone 2.
		if id == 1 then
			local t = (x + hx) / (2 * hx)
			if rng:NextNumber() < 0.75 * (1 - t) then
				continue
			end
			d *= 0.35 + 0.65 * t
		end

		local pool = build(folder, origin, {
			name = "OozePool",
			pos = { x, SKIM, z },
			-- A Cylinder's axis is its X size, so this is {thickness, diameter,
			-- diameter}. Writing it {d, 0.5, d} makes a thin ellipse standing on
			-- edge instead of a puddle -- which is exactly what the first pass did,
			-- and why the fields looked like bare lawn.
			size = { 0.5, d, d },
			color = def.ooze.bright,
			material = "Neon",
			shape = "Cylinder",
			rot = R.cylUp,
			-- Near-opaque on purpose. Transparent Neon over a green plate is
			-- invisible in daylight -- the first pass looked like a lawn.
			transparency = 0.06,
			canCollide = false,
		})
		-- A darker rim, so a pool reads as a hole full of something rather than as
		-- a decal painted on the floor.
		build(folder, origin, {
			name = "OozeRim",
			pos = { x, SKIM - 0.12, z },
			size = { 0.4, d + 5, d + 5 },
			color = def.ooze.deep,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R.cylUp,
			canCollide = false,
		})
		if index % lightEvery == 0 then
			light(pool, def.ooze.glow, 26, 2)
		end
	end

	-- Then barrels and set pieces on a jittered grid.
	local cols = math.ceil(math.sqrt(theme.props))
	local placed = 0
	for row = 0, cols - 1 do
		for col = 0, cols - 1 do
			if placed >= theme.props then
				break
			end
			placed += 1

			local x = -hx + (col + 0.5) * (2 * hx / cols) + rng:NextNumber(-12, 12)
			local z = -hz + (row + 0.5) * (2 * hz / cols) + rng:NextNumber(-12, 12)
			x = math.clamp(x, -hx, hx)
			z = math.clamp(z, -hz, hz)

			if placed % 2 == 0 then
				barrel(folder, origin, x, z, rng, def.ooze, placed % BARREL_LIGHT_EVERY == 0)
			else
				-- Zone 1's Outer Ash stage (the untouched west third, see LIFE FADING
				-- INTO A DEAD WASTELAND) gets a mix of live "brush" and "liveTree"
				-- instead of its zone's normal "trees" kind, which is already dead
				-- wood everywhere else. Trees sparser than bushes -- a tree is a
				-- landmark, not ground cover.
				local kind = theme.kind
				if id == 1 and x <= Zones.STAGES[1].maxX then
					kind = if rng:NextNumber() < 0.3 then "liveTree" else "brush"
				end
				prop(folder, origin, kind, x, z, rng, def.ooze)
			end
		end
	end

	folder.Parent = parent
end

--- The three stages, told apart by the GROUND rather than by a wall.
---
--- WHAT USED TO BE HERE, AND WHY IT WENT.
--- A 10-stud concrete barrier across the field at each boundary, with an 18-stud
--- hole in the middle. It read as unnatural because it was: a wall standing in open
--- ground, gating nothing. Nothing ever read its UnlockTier attribute — it was a
--- visual placeholder for a progression service that still does not exist. The
--- colour change carries the boundary now, and buildStageMarkers puts the label back
--- without the barrier.
---
--- WHY THIS IS A SEPARATE LAYER AND NOT SIMPLY THE PLATE'S COLOUR.
--- The obvious implementation is to cut Workspace.Zones.Zone1 into three coloured
--- plates, and it is the one thing this file's header forbids. ZoneService walks that
--- folder at 10 Hz and resolves overlaps as "smallest XZ area wins", so three plates
--- would quietly make the stage you stand in the ZONE you are in; and
--- DigService.zonePart looks "Zone1" up BY NAME and would find nothing at all, so the
--- field would stop spawning signals. One plate, always. The colour goes on top,
--- here, where it is free to be as many parts as it likes.
---
--- Thin, CanCollide and CanQuery false, and below SKIM so the ooze pools still read
--- as lying on this rather than under it. Footing and burial are untouched: a player
--- still stands on Zones.SURFACE_Y and DigService still buries against it.
local function buildStageGround(parent: Instance, zoneId: number)
	local def = Zones.get(zoneId)
	local folder = Instance.new("Folder")
	folder.Name = "StageGround"

	paintBands(folder, CFrame.new(def.center[1], Zones.SURFACE_Y, def.center[2]), def, {
		name = "Ground",
		y = GROUND_SKIM,
		thickness = 0.12,
		material = def.material,
	})

	folder.Parent = parent
end

--- What is left of the gates: a signed post and some weathered debris at each
--- boundary, instead of a barrier across it.
---
--- SCATTERED, NOT LINED UP. Three posts in a row is a fence, which is the thing being
--- removed. The label post sits near the middle where a player walking the field will
--- pass it; the other two are thrown out across the depth so the sign reads as part of
--- the landscape rather than as a planted marker.
local function buildStageMarkers(parent: Instance, zoneId: number)
	local def = Zones.get(zoneId)
	local folder = Instance.new("Folder")
	folder.Name = "StageMarkers"

	local origin = CFrame.new(def.center[1], Zones.SURFACE_Y, def.center[2])
	local hx, hz = def.size[1] / 2 - 4, def.size[2] / 2 - 20

	for _, stage in Zones.STAGES do
		-- Deterministic per stage, same reason as the rest of this file: a rebuild
		-- reproduces the same field rather than reshuffling it.
		local rng = Random.new(4000 + stage.id)
		local model = Instance.new("Model")
		model.Name = `Stage{stage.id}Marker`

		for i = 1, 3 do
			local signPost = i == 1
			local height = if signPost then 3.8 else rng:NextNumber(1.5, 2.6)
			-- Stage 1's boundary IS the western edge of the plate, so the jitter has
			-- to be clamped or its markers hang off the side of the world.
			local x = math.clamp(stage.minX + rng:NextNumber(-7, 7), -hx, hx)
			local z = if signPost then rng:NextNumber(-16, 16) else rng:NextNumber(-hz, hz)

			-- The sign post stays near-upright so its plate does not float away from
			-- it; the debris leans properly.
			local lean = if signPost then 5 else 14
			local post = build(model, origin, {
				name = if signPost then "MarkerPost" else `Debris{i}`,
				pos = { x, height / 2, z },
				size = { 0.55, height, 0.55 },
				color = if i % 2 == 0 then C.steelDark else C.wood,
				material = if i % 2 == 0 then "Metal" else "Wood",
				rot = Kit.ang(rng:NextNumber(-lean, lean), rng:NextNumber(0, 360), rng:NextNumber(-lean, lean)),
				canCollide = false,
				attributes = { StageId = stage.id, UnlockTier = stage.unlockTier },
			})
			post.CanQuery = false

			if signPost then
				local plate = build(model, origin, {
					name = "StagePlate",
					pos = { x, height - 0.6, z },
					size = { 2.6, 1.4, 0.18 },
					color = stage.color,
					material = "Metal",
					canCollide = false,
					attributes = { StageId = stage.id, UnlockTier = stage.unlockTier },
				})
				plate.CanQuery = false
				-- Further than the gate sign's default 40 studs: a low marker has to be
				-- legible from further out than a ten-stud wall did.
				billboard(plate, 180, 2.4, `STAGE {stage.id}`, stage.name, stage.color, 150)
				light(plate, stage.color, 10, 0.7)
			end
		end

		model.Parent = folder
	end

	folder.Parent = parent
end

local function createScenery(): Model
	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	Kit.stamp(scenery, BUILDER_SOURCE, BUILDER_VERSION)

	for _, id in Zones.builtIds() do
		buildZoneScenery(scenery, id)
	end
	buildStageGround(scenery, 1)
	buildStageMarkers(scenery, 1)

	-- Zone 1's pale-sand endpoint into Zone 2's dun tan, and Zone 2's tan into Zone
	-- 3's deeper khaki-brown, are real family changes now that Zones 1-3 are a life-
	-- to-wasteland gradient rather than three shades of one green — see ZONE_BLENDS.
	buildZoneBlend(scenery, 1, 2)
	buildZoneBlend(scenery, 2, 3)

	-- Zones 1-3 are the (now muted) dead-sand family, 4-6 are plum/pink/violet, so
	-- this is drawn once more, at the 3/4 boundary — moved here from 3/5 when Zone 4
	-- was pulled out of its old spot by camp and slotted into the chain ahead of
	-- Zone 5. 4 to 5 and 5 to 6 get none: plum into pink into violet is a step along
	-- one scale, and the plates read as continuous without help.
	buildZoneBlend(scenery, 3, 4)

	-- Nothing in here may claim to be a zone. This is the invariant the whole
	-- module/folder split exists to protect, so it is asserted, not trusted.
	for _, d in scenery:GetDescendants() do
		assert(d:GetAttribute("ZoneId") == nil, `scenery part {d:GetFullName()} carries a ZoneId — it would register as a zone`)
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
