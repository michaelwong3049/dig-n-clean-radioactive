--!strict
--[[
	Shops.luau — where cash turns back into capability.

	    require(game.ServerScriptService.Server.build.Shops).rebuild()

	THREE STALLS ON THE PLAZA, one per tool you hold: the detector that finds it, the
	magnet that pulls it, and the cleaner that scrubs it. Each is a different colour
	and keeps that colour forever. A young player learns "the coral one is the
	detector shop" once and then navigates by colour rather than by reading signs,
	which is the cheapest legibility win available anywhere in this map.

	PLUS AN OUTFITTER, a real building, and this one is not decoration.
	Gear.TRACKS has seven entries. Three stalls covers Detector, Magnet and Cleaner and
	leaves Suit, Boots and Satchel priced but unbuyable — and the SUIT is the gate
	on every stage in the game. Without a way to buy one, Stage 2 stops being "you can go
	there and here is what it costs" and becomes exactly the locked door PLAN §3.5
	promises never to build. It costs nothing to add because the shop system
	is track-generic: it is four more counters with four more StationIds.

	THE SPLIT BETWEEN THE STALLS AND THIS BENCH IS "DO YOU HOLD IT". The three stalls
	sell the three things ToolService can put in your hands; the Outfitter sells the
	three you wear. Luck briefly sat here too, as a fourth desk selling something you
	do not physically have at all — since moved out to its own button (see the LUCK
	IS NOT HERE note below).

	THE LOOK — the supplied classic-Roblox Gear Store reference, stripped to the
	structure. Each tool stall has studded posts, a slatted rear wall, an open
	counter with a steel cap, a shallow striped canopy and matching valance IN THE
	STALL'S OWN COLOUR (coral / teal / purple against white, no longer the one
	shared awning red), and a floating two-line sign that NAMES WHAT THE STALL
	SELLS (DETECTORS / MAGNETS / CLEANERS) in that same accent, with the tagline
	under it. The Outfitter remains the larger peaked-roof building — now tucked in
	behind the Detector and Cleaner stalls on the west, and open front and back as
	a walk-through — its three counters each billboarded the same way (SUITS /
	BOOTS / SATCHELS).

	THE DECORATION IS GONE, AND THAT WAS A DELIBERATE STRIP. Earlier passes stood a
	blocky shopkeeper behind each counter, a big silhouette prop of the thing sold
	(a detector, a horseshoe magnet, a bucket-and-brush, a hazmat suit…) beside it,
	a crate and an open chest of clutter on the deck, and a rubber duck on the roof.
	All removed. What identifies a stall now is the sign naming its wares plus its
	accent colour — the sign text, the counter trim cap and the floor-marker
	outline all in the shop's own hue.

	THE LUMBER IS GREY, NOT BROWN. Posts, counters, the Outfitter's walls, roof
	beams and rear slats all paint from C.shopWood / C.shopWoodLight — a cool
	neutral grey, so the built structure reads as painted timber and the shop's own
	accent colour (trim cap, canopy, floor marker) is the only warm thing on the
	stall.

	THE GLOW STAYS OUT OF GREEN. The floor outline marking the buy radius uses the
	shop's own accent colour, never green, so "glowing green" still means exactly
	one thing anywhere in the world: the ooze (PLAN §14).

	THE WORLD CONTRACT (unchanged by the reskin):
	    StationKind = "shop"      -- what kind of thing you are standing at
	    StationId   = "Detector"  -- which track, EXACTLY as spelled in Gear.TRACKS
	    Radius      = <studs>

	StationId rather than a StationKind of "shop_detector" keeps the kind enum small
	and lets one client panel be parameterised by track. It is deliberately the
	capitalised Gear.TRACKS spelling, so no case conversion happens at the world
	boundary — the single lowercase translation lives in Gear.profileKey and nowhere
	else. Both Radius values are untouched by the reskin — this file only changed what
	things look like, not how close you need to stand.

	THE THREE STALLS SIT IN A TRIANGLE FACING THE MIDDLE. `PLAZA_MID` (x=17.5, z=0)
	is that middle — the plaza midpoint, Hub's grey central spine centreline, the
	camp datum (Hub.CAMP_ORIGIN) and the blackout-respawn anchor, all the same
	point. Each stall stands `STALL_RING_RADIUS` studs out from it at a 120-degree
	spacing and is turned so its own front — the counter side, local +Z — points
	back at PLAZA_MID (`facingOrigin` does the turn). A player standing on the
	respawn anchor is inside the triangle with all three counters facing them; the
	gap between the two western stalls is the way in, aimed at the pad ring the
	players arrive from.

	THE OUTFITTER TUCKS IN BEHIND THE DETECTOR AND CLEANER STALLS, ON THE WEST. It
	used to sit across a centre aisle from a straight row of stalls (row at z=22,
	Outfitter at z=-22), then went through a run of holding spots — z=-55, the
	south edge, the south-east arc. Now it sits at (-20, 0) on the grey central
	pad, due west of PLAZA_MID and directly BEHIND the two stalls on that side
	(Detector NW, Cleaner SW) — out on the ground the west pad widening opened up
	(Hub.PAD_WEST_EXTEND), off the way in rather than straddling it. On the z=0
	centreline it faces due east, so `facingOrigin` leaves it square, no turn.

	AND IT IS OPEN FRONT AND BACK — A WALK-THROUGH, NOT A DEAD END. Only the two
	side walls are solid now; both gable ends (the +Z centre-facing side and the -Z
	outer side) are open. The three counters sit clear of the ~9-stud gaps between
	them, so the building can be walked straight through rather than being a room
	with a back wall — the +Z end is the counter approach from the plaza, the -Z
	end opens onto the west apron behind.

	`facingOrigin` IS THE ONLY PLACEMENT PRIMITIVE. Both builders lay every part as
	a local offset from the CFrame it returns, so that one CFrame carries a shop's
	whole position AND facing. It reads Hub.PLAZA.topY for the ground plane (the
	plaza is at Stages.SURFACE_Y, not Y=0). This file still reads nothing from
	Plots.luau: Plots requires Hub, Hub requires only Kit, and Shops stays a pure
	statement of positions. Plots.luau's SHOP_CLUSTER_EAST_REACH is already marked
	historical there and stays a conservative bound, not a live measurement of
	anything here — and this move is westward anyway (the Outfitter's east face
	pulls BACK to ~x=-12), so it only ever relieves that bound, never strains it.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local Shops = {}
local BUILDER_SOURCE = "src/server/build/Shops.luau"
local BUILDER_VERSION = 21

local C, R = Kit.C, Kit.R
local build, billboard = Kit.build, Kit.billboard

--- The middle everything else here faces: the plaza midpoint, Hub's central-spine
--- centreline, the camp datum and the blackout-respawn anchor, all this one point.
local PLAZA_MID = { x = 17.5, z = 0 }

--- The three plaza stalls, one at each vertex of an equilateral triangle centred
--- on PLAZA_MID at radius 20, each turned by `facingOrigin` so its counter side
--- (local +Z) points back at PLAZA_MID. `at` is world XZ. Magnet takes the east
--- vertex; Detector (NW) and Cleaner (SW) the two western ones, so the gap a
--- player walks in through faces the pad ring they arrive from.
local STALLS = {
	{ track = "Detector", at = { 7.5, 17.3 }, color = C.shopDetector, label = "DETECTORS", tagline = "find it deeper" },
	{ track = "Magnet", at = { 37.5, 0 }, color = C.shopMagnet, label = "MAGNETS", tagline = "pull it harder" },
	{ track = "Cleaner", at = { 7.5, -17.3 }, color = C.shopCleaner, label = "CLEANERS", tagline = "scrub it cleaner" },
}

--- The outfitter's three counters on one bench. Radius 6 at a 13-stud pitch, so
--- no two counters' circles overlap and standing at one is unambiguous. `at` is
--- on the central square at (-20, 0), due west of PLAZA_MID and tucked in behind
--- the Detector and Cleaner stalls (see the header) — its +Z front faces due
--- east at the centre, so `facingOrigin` leaves it square.
local OUTFITTER = {
	at = { -20, 0 },
	pitch = 13,
	counters = {
		{ track = "Suit", label = "SUITS", tagline = "survive it longer" },
		{ track = "Boots", label = "BOOTS", tagline = "get home faster" },
		{ track = "Satchel", label = "SATCHELS", tagline = "buy the clock time" },
		-- LUCK IS NOT HERE, and it briefly was. It is the one track you neither hold
		-- nor wear, and a fourth desk here sold it as though it were a satchel. It
		-- moved to a glowing button staked next to the wash pad it actually affects
		-- (build/Plots.buildLuckButton) -- press E, no panel. World.verify() still
		-- asserts every priced track is buyable somewhere; it accepts a `SellsTrack`
		-- attribute as well as a shop counter, which is what keeps that check honest
		-- after this move.
	},
}

--- A build origin on the plaza plane at world (x, z), turned so its local +Z —
--- every shop's counter-facing front — points at (towardX, towardZ). Both
--- builders lay every part as a local offset from what this returns, so this one
--- CFrame is the whole of a shop's position AND its facing.
local function facingOrigin(x: number, z: number, towardX: number, towardZ: number): CFrame
	local topY = Hub.PLAZA.topY
	-- CFrame.lookAt aims local -Z (its LookVector) at the target; the shop fronts
	-- are +Z, so aim -Z at the target's mirror through (x, z) and +Z lands on the
	-- target. Degenerate only if (x, z) == the target, which no caller passes.
	local mirror = Vector3.new(2 * x - towardX, topY, 2 * z - towardZ)
	return CFrame.lookAt(Vector3.new(x, topY, z), mirror)
end

-- ── The floor marker ─────────────────────────────────────────────────────────

--- A rectangular outline on the ground marking the buy radius — the reference
--- photo's floor square, recoloured per shop instead of always blue so it keeps
--- doing the colour-navigation job instead of flattening it. Four thin matte bars
--- rather than a filled plate, matching the "outline, not fill" read the photo has.
local function buildFloorMarker(parent: Instance, origin: CFrame, x: number, z: number, width: number, depth: number, color: string)
	local thickness = 0.4
	for _, bar in {
		{ w = width, d = thickness, dx = 0, dz = -depth / 2 },
		{ w = width, d = thickness, dx = 0, dz = depth / 2 },
		{ w = thickness, d = depth, dx = -width / 2, dz = 0 },
		{ w = thickness, d = depth, dx = width / 2, dz = 0 },
	} do
		build(parent, origin, {
			name = "FloorMarker",
			pos = { x + bar.dx, 0.08, z + bar.dz },
			size = { bar.w, 0.15, bar.d },
			color = color,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end
end

-- ── Reference gear-store details ─────────────────────────────────────────────

--- The reference roof is one shallow rectangular awning, striped front-to-back,
--- with a short matching valance at the front. Separate studded Plastic parts
--- keep every stripe crisp and give it the chunky classic-Roblox texture.
---
--- `accent` is the stall's own hex — the canopy stripes and valance alternate it
--- with white, so each stall's cloth is its own colour (coral / teal / purple)
--- instead of the shared awning red every stall used to wear. It is the biggest
--- painted surface on the stall, so this is now the loudest of the per-shop
--- colour cues (with the trim cap, floor marker and sign text).
local function buildStripedCanopy(parent: Instance, origin: CFrame, accent: string)
	local stripeCount = 7
	local stripeWidth = 2.5
	local totalWidth = stripeCount * stripeWidth
	local centerZ = -4
	local centerY = 9.8
	local depth = 14.5
	local tiltDegrees = 4
	local frontZ = centerZ + depth / 2
	local frontY = centerY - math.sin(math.rad(tiltDegrees)) * (depth / 2)

	for index = 1, stripeCount do
		local color = if index % 2 == 1 then accent else C.labelText
		local x = -totalWidth / 2 + (index - 0.5) * stripeWidth
		build(parent, origin, {
			name = `CanopyStripe{index}`,
			pos = { x, centerY, centerZ },
			size = { stripeWidth + 0.06, 0.45, depth },
			color = color,
			material = "Plastic",
			rot = Kit.ang(tiltDegrees, 0, 0),
			studs = true,
			canCollide = false,
		})
		build(parent, origin, {
			name = `CanopyValance{index}`,
			pos = { x, frontY - 0.45, frontZ },
			size = { stripeWidth + 0.06, 1.15, 0.45 },
			color = color,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end

	for _, z in { centerZ - depth / 2 + 0.35, frontZ - 0.35 } do
		local y = centerY - math.sin(math.rad(tiltDegrees)) * (z - centerZ) - 0.38
		build(parent, origin, {
			name = "CanopySupport",
			pos = { 0, y, z },
			size = { totalWidth, 0.4, 0.5 },
			color = C.shopWood,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end
end

--- Seven separated boards form the open slatted back seen most clearly in the
--- third reference image. The gaps keep the booth airy instead of turning it
--- into a solid shed.
local function buildSlatWall(parent: Instance, origin: CFrame)
	for index = 1, 7 do
		build(parent, origin, {
			name = `BackSlat{index}`,
			pos = { 0, 0.8 + (index - 1) * 1.2, -10 },
			size = { 14.8, 0.88, 0.55 },
			color = C.shopWoodLight,
			material = "Plastic",
			studs = true,
		})
	end
end

--- The floating stall sign, in the reference's two-line hierarchy: the big line
--- names WHAT THE STALL SELLS (DETECTORS / MAGNETS / CLEANERS) in that shop's own
--- accent colour so the sign itself does the colour-navigation, and a smaller
--- white line under it carries the tagline. `accent` is the shop's hex string.
--- The big line is TextScaled so any label length fits its band without
--- re-tuning TextSize.
local function buildStoreBillboard(adornee: BasePart, label: string, tagline: string, accent: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "StoreSign"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(400, 96)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 12.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 40
	gui.Parent = adornee

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 56)
	title.BackgroundTransparency = 1
	title.Font = Kit.FONT
	title.Text = label
	title.TextScaled = true
	title.TextColor3 = Color3.fromHex(accent)
	title.TextStrokeColor3 = Color3.fromHex(C.hazardBlack)
	title.TextStrokeTransparency = 0
	title.Parent = gui

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromOffset(0, 56)
	subtitle.Size = UDim2.new(1, 0, 0, 34)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Kit.FONT
	subtitle.Text = tagline
	subtitle.TextColor3 = Color3.fromHex(C.labelText)
	subtitle.TextSize = 25
	subtitle.TextStrokeColor3 = Color3.fromHex(C.hazardBlack)
	subtitle.TextStrokeTransparency = 0
	subtitle.Parent = gui
end

-- ── The counter ───────────────────────────────────────────────────────────────

export type CounterSpec = {
	color: string,
	width: number,
	depth: number,
	z: number,
	stationKind: string?,
	stationId: string?,
	radius: number?,
	material: string?,
	studded: boolean?,
}

--- The counter desk — the interactive part — in grey storefront lumber
--- (C.shopWood) with a coloured trim cap on top in the shop's own accent.
--- Returns the desk so the caller can billboard it. `material` defaults to
--- "Wood" (the Outfitter's own look); the plaza stalls pass "Plastic" instead,
--- since Roblox's stud-bump texture only renders on Plastic, and that studded
--- look is the whole point of the reskin.
local function buildCounter(parent: Instance, origin: CFrame, spec: CounterSpec): BasePart
	local w, d, z = spec.width, spec.depth, spec.z

	local attrs = nil
	if spec.stationKind then
		attrs = { StationKind = spec.stationKind, StationId = spec.stationId, Radius = spec.radius }
	end

	local desk = build(parent, origin, {
		name = "Counter",
		pos = { 0, 1.1, z },
		size = { w, 2.2, d },
		color = C.shopWood,
		material = spec.material or "Wood",
		studs = spec.studded,
		attributes = attrs,
	})

	build(parent, origin, { name = "CounterTrim", pos = { 0, 2.25, z }, size = { w + 0.4, 0.3, d + 0.4 }, color = spec.color, material = "Plastic", studs = spec.studded, canCollide = false })

	return desk
end

-- ── The gable roof ───────────────────────────────────────────────────────────

--- A simple peaked roof: two flat panels sloping up from the wall tops to a ridge
--- along the building's centreline, plus a capping ridge beam. `halfDepth` is the
--- distance from centre to each wall, `rise` how far the ridge climbs above the
--- wall tops. Positions are derived from the two literal points each panel spans
--- (wall-top eave, centre-line ridge) rather than reasoned out in the abstract --
--- this project has gotten CFrame rotation signs backwards from pure reasoning
--- more than once this session, and deriving from known points is the version
--- that's checkable by eye against the numbers.
---
--- Returns the ridge Y so the caller can float a sign above it. Shared by the
--- plaza stalls (a small roof on posts) and the Outfitter (a much bigger one
--- over real walls) -- the same shape at two different scales. `material`
--- defaults to "Wood" (the Outfitter's own look, unchanged); the plaza stalls
--- pass "Plastic" so the roof shows Roblox's stud-bump texture, matching the
--- reference market stall's studded-block look.
---
--- CLEARANCE, NOT JUST THE CENTRELINE. The eave/ridge points above describe
--- where the panel's own zero-thickness centreline sits -- but a real board has
--- thickness on both sides of that line, so the panel's PHYSICAL underside sits
--- `(thickness/2)*cos(tilt)` below it. Left uncorrected, a flat-topped post
--- built to exactly `wallHeight` pokes up into that underside by that same
--- amount -- invisible on the original round, shallow-pitched posts, and very
--- visible once the posts went square and the roof steeper. `clearance` raises
--- the whole roof (both panels AND the ridge beam, so they stay flush with each
--- other) by that offset, so it's the underside that touches the wall top.
local function buildGableRoof(parent: Instance, origin: CFrame, centerZ: number, wallHeight: number, halfDepth: number, rise: number, width: number, color: string, material: string?): number
	local thickness = 0.6
	local slopeLen = math.sqrt(halfDepth ^ 2 + rise ^ 2)
	local tiltDeg = math.deg(math.atan2(rise, halfDepth))
	local clearance = (thickness / 2) * math.cos(math.rad(tiltDeg))
	local ridgeY = wallHeight + rise + clearance
	local mat = material or "Wood"

	for _, side in { -1, 1 } do
		-- Eave point: (side*halfDepth, wallHeight). Ridge point: (0, wallHeight + rise).
		-- The panel's own centre sits halfway between them, then the whole
		-- panel is lifted by `clearance` (see above).
		build(parent, origin, {
			name = "RoofPanel",
			pos = { 0, wallHeight + rise / 2 + clearance, centerZ + side * halfDepth / 2 },
			size = { width, thickness, slopeLen },
			color = color,
			material = mat,
			rot = Kit.ang(side * tiltDeg, 0, 0),
			canCollide = false,
		})
	end

	build(parent, origin, {
		name = "RoofRidge",
		pos = { 0, ridgeY, centerZ },
		size = { width, 1.1, 1.1 },
		color = C.shopWood,
		material = mat,
		shape = "Cylinder",
		rot = R.cylAlongX,
		canCollide = false,
	})

	return ridgeY
end

-- ── The plaza stalls ────────────────────────────────────────────────────────────

--- One classic-Roblox gear store, stripped to the structure: studded grey posts
--- and rear slats, an open counter, and a striped canopy + two-line sign both in
--- the stall's own accent colour. The canopy, the sign text, the floor marker
--- and the counter's trim cap — all `spec.color` — are the per-shop identity now
--- that the shopkeeper and the identity prop are gone.
local function buildStall(parent: Instance, spec: { track: string, at: { number }, color: string, label: string, tagline: string })
	local m = Instance.new("Model")
	m.Name = `{spec.track}Shop`

	-- Position AND facing in one CFrame: at the triangle vertex spec.at, turned so
	-- the counter side (+Z) looks back at PLAZA_MID. Y comes from Hub.PLAZA.topY
	-- (the plaza is at Stages.SURFACE_Y, not Y=0). Every part below is a LOCAL
	-- offset from this, so this one line carries the whole stall's placement.
	local origin = facingOrigin(spec.at[1], spec.at[2], PLAZA_MID.x, PLAZA_MID.z)

	-- A thin blue-grey floor is visible through the open sides in the reference.
	-- It is non-colliding and lifted just enough to avoid z-fighting with the plaza.
	build(m, origin, {
		name = "StallFloor",
		pos = { 0, 0.05, -4 },
		size = { 15, 0.1, 12 },
		color = C.steelDark,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})

	-- Four chunky posts holding the roof up, in grey storefront lumber
	-- (C.shopWood). Square-cut, not round logs — the reference photo's posts read
	-- as sawn beams, and Block needs no
	-- rot (unlike Cylinder, whose long axis is local X and needs R.cylUp to
	-- stand it upright) since a Block's size is already literal {X,Y,Z}.
	-- Plastic, not Wood: Roblox's stud-bump texture only renders on Plastic
	-- (the same reason the plaza's own checkerboard tiles are Plastic), and
	-- that studded look is what makes this read as the chunky reference stall
	-- instead of a plain wood kiosk. Taller than the original kiosk, too — the
	-- reference stall reads as a proper standing structure, not a picnic table.
	--
	-- 2x2, not 1.1x1.1: the stud pattern needs a couple of repeats across a
	-- face to actually read as studded rather than a flat colour -- the same
	-- reason the checkerboard tiles were tuned to exactly 3x3 studs. A 1.1-wide
	-- post face was too narrow for the pattern to be legible even though the
	-- material was already correct.
	local POST_SIZE = 1.5
	local POST_DX = 7.1
	for _, dx in { -POST_DX, POST_DX } do
		for _, dz in { -10, 2 } do
			local postHeight = if dz < 0 then 10 else 9.2
			build(m, origin, {
				name = "Post",
				pos = { dx, postHeight / 2, dz },
				size = { POST_SIZE, postHeight, POST_SIZE },
				color = C.shopWood,
				material = "Plastic",
				shape = "Block",
				studs = true,
			})
		end
	end
	buildSlatWall(m, origin)

	-- THE COUNTER. This is the part the whole file exists to place correctly.
	-- material = "Plastic" here (not buildCounter's own "Wood" default) so the
	-- studded look stays consistent across the whole stall -- the Outfitter's
	-- call to the same function passes no material and keeps its original Wood.
	local counter = buildCounter(m, origin, {
		color = C.steel,
		width = 14,
		depth = 2.5,
		z = 0.6,
		stationKind = "shop",
		stationId = spec.track,
		radius = 12,
		material = "Plastic",
		studded = true,
	})
	buildStoreBillboard(counter, spec.label, spec.tagline, spec.color)

	buildStripedCanopy(m, origin, spec.color)

	-- The floor marker: a glowing outline of the buy radius, in the shop's own
	-- colour — never green, see the header. With the shopkeeper and the identity
	-- prop stripped out, this, the counter trim cap and the sign text are the
	-- whole of a stall's per-shop identity.
	buildFloorMarker(m, origin, 0, 3.4, 10, 5, spec.color)

	m.Parent = parent
	return m
end

-- ── The outfitter ─────────────────────────────────────────────────────────────

--- The outfitter: a proper building, not a bench under a trim strip. Three
--- shops left Suit, Boots and Satchel priced but unbuyable, and hazard gear that
--- actually reduces incoming damage earns more than a picnic table — two side
--- walls, a peaked roof, and BOTH gable ends open so it reads as a walk-through
--- rather than a room with a back wall. Tucked in behind the Detector and Cleaner
--- stalls on the west of the square; the +Z front (sign, forecourt marker, and
--- the counters just inside) faces due east at PLAZA_MID, the -Z end opens onto
--- the west apron behind. Each counter carries its own billboard naming the track
--- (SUITS / BOOTS / SATCHELS).
local function buildOutfitter(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Outfitter"

	-- Same primitive as the stalls: placed at OUTFITTER.at behind the Detector and
	-- Cleaner stalls, on the z=0 centreline so facingOrigin's aim at PLAZA_MID is
	-- a straight due-east facing with no turn.
	local origin = facingOrigin(OUTFITTER.at[1], OUTFITTER.at[2], PLAZA_MID.x, PLAZA_MID.z)
	local span = OUTFITTER.pitch * (#OUTFITTER.counters - 1)
	local width = span + 20
	local halfDepth = 8
	local wallHeight = 7

	-- Same 0.1 lift as the stall decks, for the same reason: 0.4 thick at y = -0.2 put
	-- this floor's top face on the plaza's own plane and the two z-fought.
	build(m, origin, { name = "Floor", pos = { 0, -0.1, 0 }, size = { width, 0.4, halfDepth * 2 }, color = C.plazaWarm, material = "Plastic" })

	-- Two side walls only. BOTH gable ends are left open: the +Z end faces
	-- PLAZA_MID (east) and is the counter approach, the -Z end opens onto the west
	-- apron behind. That open pair is what makes this a walk-through and not a
	-- room with a back wall.
	for _, dx in { -width / 2, width / 2 } do
		build(m, origin, { name = "SideWall", pos = { dx, wallHeight / 2, 0 }, size = { 0.6, wallHeight, halfDepth * 2 }, color = C.shopWood, material = "Wood" })
	end

	local ridgeY = buildGableRoof(m, origin, 0, wallHeight, halfDepth, 4, width + 2, C.shopOutfitter)

	-- The sign, floating over the open +Z end, facing PLAZA_MID -- the same
	-- Back-face convention the plaza stalls use, for the same reason: whoever is
	-- walking toward this building from the centre is standing on the +Z side.
	-- Matte, in the shop's accent colour -- colour still does the navigation, it
	-- just doesn't glow.
	-- Fixed size, not derived from the building's width — a sign that spans the
	-- whole 46-wide storefront came out as a comically long, thin plank with
	-- "OUTFITTER" lost in the middle of it, which read as stretched-out text even
	-- though TextScaled itself never distorts a glyph. The board's own proportions
	-- were the actual problem.
	local signY = ridgeY + 2.2
	build(m, origin, { name = "SignOutline", pos = { 0, signY, halfDepth - 0.2 }, size = { 15, 3.0, 0.3 }, color = C.hazardBlack, material = "Plastic", canCollide = false })
	local sign = build(m, origin, { name = "Sign", pos = { 0, signY, halfDepth + 0.2 }, size = { 14.4, 2.6, 0.4 }, color = C.shopOutfitter, material = "SmoothPlastic", canCollide = false })
	Kit.surfaceText(sign, Enum.NormalId.Back, "OUTFITTER", C.signText)

	-- The forecourt outline at the +Z end, the approach from the centre, with the
	-- counters just inside it.
	buildFloorMarker(m, origin, 0, halfDepth - 3, width - 6, 8, C.shopOutfitter)

	for index, counter in OUTFITTER.counters do
		local x = -span / 2 + (index - 1) * OUTFITTER.pitch
		local counterOrigin = origin * CFrame.new(x, 0, 0)

		local desk = buildCounter(m, counterOrigin, {
			color = C.shopOutfitter,
			width = 4,
			depth = 2.4,
			z = halfDepth - 3.5,
			stationKind = "shop",
			stationId = counter.track,
			-- Tighter than the plaza stalls: three counters share one building,
			-- and standing at one of them has to be unambiguous.
			radius = 6,
		})
		billboard(desk, 200, 4.4, counter.label, counter.tagline, C.shopOutfitter)
	end

	m.Parent = parent
	return m
end

local function createShops(): Model
	local shops = Instance.new("Model")
	shops.Name = "Shops"
	Kit.stamp(shops, BUILDER_SOURCE, BUILDER_VERSION)

	for _, spec in STALLS do
		buildStall(shops, spec)
	end
	buildOutfitter(shops)

	-- SELF-CONSISTENCY, NOT GLOBAL COVERAGE, and that distinction is new. This used to
	-- assert every entry in Gear.TRACKS had a counter here — correct while this file
	-- was the only thing in the world that sold anything, and wrong the moment Luck
	-- moved to a button at each base (build/Plots.buildLuckButton). It failed the
	-- next rebuild, which is exactly what a good assert does; it was just asking a
	-- question this file can no longer answer.
	--
	-- So it now checks only what this file DECLARES: every track named in STALLS or
	-- OUTFITTER.counters actually got a counter built with that StationId. That
	-- catches the real local failure (a typo'd track name, a counter that silently
	-- did not build) without claiming to know about selling points it did not make.
	--
	-- "Every priced track is buyable SOMEWHERE" is still checked, once, in
	-- World.verify() — which sees the whole world and knows about both a `shop`
	-- counter and a `SellsTrack` prompt.
	local covered: { [string]: boolean } = {}
	for _, part in shops:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("StationKind") == "shop" then
			covered[part:GetAttribute("StationId") :: string] = true
		end
	end

	local declared: { string } = {}
	for _, spec in STALLS do
		table.insert(declared, spec.track)
	end
	for _, counter in OUTFITTER.counters do
		table.insert(declared, counter.track)
	end
	for _, track in declared do
		assert(covered[track], `{track} is listed in this file but no counter was built for it`)
	end

	return shops
end

function Shops.build(parent: Instance?): Model
	local shops = createShops()
	shops.Parent = parent or Workspace
	return shops
end

function Shops.rebuild(parent: Instance?): Model
	local shops = Kit.swap("Shops", createShops, parent) :: Model
	print(`[build] Shops rebuilt — {#shops:GetChildren()} storefronts, {#STALLS} stalls + {#OUTFITTER.counters} outfitter counters`)
	return shops
end

return Shops
