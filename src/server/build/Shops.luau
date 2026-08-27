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
	leaves Suit, Boots, Satchel and Luck priced but unbuyable — and the SUIT is the gate
	on every stage in the game. Without a way to buy one, Stage 2 stops being "you can go
	there and here is what it costs" and becomes exactly the locked door PLAN §3.5
	promises never to build. It costs nothing to add because the shop system
	is track-generic: it is four more counters with four more StationIds.

	THE SPLIT BETWEEN THE STALLS AND THIS BENCH IS "DO YOU HOLD IT". The three stalls
	sell the three things ToolService can put in your hands; the Outfitter sells the
	three you wear and, since the wash pad landed, the one you do not physically have
	at all — Luck is a charm on a workbench, not a machine, and the counter names in
	Config/Gear.Luck say so on purpose.

	THE LOOK — a classic toy-store kiosk, not a toxic drum, not an archway.
	The nuclear-drum reskin (round barrel counter, dome roof, trefoil badge) and,
	later, a bowed rolled-edge canopy are both long gone, replaced with a wood
	counter on four wood posts under a real peaked roof (`buildGableRoof` — two
	flat panels tilted up to a centre ridge, this project's usual way of faking a
	slope out of flat blocks), a little blocky shopkeeper standing behind the
	counter, and a glowing bubble sign floating over the roof peak. Open on all
	sides — no booth walls on the stalls themselves. The Outfitter shares the same
	roof builder at building scale, over real walls. Per-shop colour-coding
	survives fully intact — the roof colour, the sign, and the floor marker all use
	`spec.color`, so "the coral one is the detector shop" still holds.

	IDENTITY STILL COMES FROM THE PROP, NOT THE STALL SHAPE. Every stall is the
	same shape, so the differentiator is still the same big, silhouette-clear
	prop of the actual thing sold (a detector, a horseshoe magnet, a
	bucket-and-brush) standing beside the counter, paired with a crate of
	clutter for a "goods stacked outside the stall" read.

	THE GLOW STAYS OUT OF GREEN. Two glowing elements per stall — the bubble sign
	and a floor outline marking the buy radius — both use the shop's own accent
	colour, never green, so "glowing green" still means exactly one thing anywhere
	in the world: the ooze (PLAN §14).

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

	STALLS.at / OUTFITTER.at ARE NOT UNTOUCHED ANY MORE. Both were written when
	Hub.PLAZA was symmetric about world X=0, so "centred at x=0" and "centred on the
	plaza" were the same statement. They stopped being the same statement when the
	plaza's compaction pass pinned its east edge to Stage 1 and pulled its west edge in
	instead (see Hub.PLAZA's own comment) — the rectangle's midpoint moved to x=17.5,
	so every X here carries that same +17.5 to stay centred on the plaza rather than on
	a world coordinate the plaza no longer straddles.

	Z MOVED TOO, WHEN THE BASE RING BECAME A SEMICIRCLE. The two rows used to sit at
	the edges of a plaza the pad ring surrounded on three sides (stalls z=45,
	Outfitter z=-48); now that all six pads face one central shop cluster
	(Plots.luau's RING_CENTER), the two rows pulled in tight around it instead:
	stalls z=45 -> 22, Outfitter z=-48 -> -22, symmetric about z=0. That leaves a
	clean 20-stud aisle between them (a stall deck's southmost point at z=7, the
	Outfitter's northmost wall at z=-13) and puts the whole cluster's farthest
	reach from centre at only ~60 studs — well short of the ring's 154-stud inner
	pad edge, so every pad has a clear, unobstructed line of sight to the cluster
	it's built to face. Each shop's own internal facing (stalls south, Outfitter
	north) is untouched — only the row positions moved, not which way anything
	points.

	X MOVED AGAIN, WHEN RING_CENTER PULLED TOWARD STAGE 1. RING_CENTER is no
	longer the plaza's own midpoint (see Plots.luau's own comment on why) — it
	moved from x=17.5 to x=32, so every X here carries that same +14.5 to stay
	centred under it, same reasoning as the +17.5 correction above. THIS ROW'S
	OWN FOOTPRINT IS WHAT CAPPED HOW FAR RING_CENTER COULD MOVE, not the pads —
	the eastmost stall (Cleaner, at.x = centre + 42) plus its own ~11-stud
	half-width is the first thing that would cross into Stage 1 (world x=100) if
	pushed further; Plots.luau's SHOP_CLUSTER_EAST_REACH constant is that exact
	number, kept in sync with these three x values by hand since this file has no
	way to read Plots.luau's own layout (Plots requires Hub, and Hub requires
	only Kit — a Shops<->Plots require would be fine on its own, but this file
	stays a pure reskin of positions Plots.luau already computed, not a new
	dependency, for the same reason the Z move above didn't add one either).
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local Shops = {}
local BUILDER_SOURCE = "src/server/build/Shops.luau"
local BUILDER_VERSION = 12

local C, R = Kit.C, Kit.R
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

--- The three plaza stalls. `at` is world XZ; they face south, toward the shop
--- cluster's own centre (Plots.RING_CENTER) that every base on the semicircle
--- faces in turn.
local STALLS = {
	{ track = "Detector", at = { -10, 22 }, color = C.shopDetector, tagline = "find it deeper" },
	{ track = "Magnet", at = { 32, 22 }, color = C.shopMagnet, tagline = "pull it harder" },
	{ track = "Cleaner", at = { 74, 22 }, color = C.shopCleaner, tagline = "scrub it cleaner" },
}

--- The outfitter's three counters, on one bench facing the stalls across the
--- shop cluster's own centre aisle. Radius 6 at a 13-stud pitch, so no two
--- counters' circles overlap and standing at one is unambiguous.
local OUTFITTER = {
	at = { 32, -22 },
	pitch = 13,
	counters = {
		{ track = "Suit", label = "SUITS", tagline = "survive it longer" },
		{ track = "Boots", label = "BOOTS", tagline = "get home faster" },
		{ track = "Satchel", label = "SATCHELS", tagline = "buy the clock time" },
		-- Luck is the seventh track (Config/Gear) and the only one that is not
		-- equipment. It belongs on this bench rather than in a fourth plaza stall for
		-- exactly the reason the other three are here: the stalls are for the thing
		-- you HOLD -- detector, magnet, cleaner -- and everything else outfits you.
		-- The bench's width is derived from #counters, so this cost one line.
		{ track = "Luck", label = "LUCK", tagline = "bend the odds" },
	},
}

-- ── The shopkeeper ────────────────────────────────────────────────────────────

--- A little blocky vendor standing behind the counter — head, torso, two arms.
--- Friendlier than the Outfitter's hazmat mannequin prop: bare peach head, no
--- helmet, torso in the shop's own colour like a shirt.
local function buildShopkeeper(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	build(parent, origin, { name = "KeeperTorso", pos = { x, 3.6, z }, size = { 2.0, 1.8, 1.0 }, color = color, material = "Plastic", canCollide = false })
	build(parent, origin, { name = "KeeperHead", pos = { x, 5.1, z }, size = { 1.3, 1.3, 1.3 }, color = C.lampWarm, material = "Plastic", shape = "Ball", canCollide = false })
	for _, dx in { -1.25, 1.25 } do
		build(parent, origin, { name = "KeeperArm", pos = { x + dx, 3.6, z }, size = { 1.6, 0.5, 0.5 }, color = color, material = "Plastic", shape = "Cylinder", canCollide = false })
	end
end

-- ── The floor marker ─────────────────────────────────────────────────────────

--- A glowing rectangular outline on the ground marking the buy radius — the
--- reference photo's neon floor square, recoloured per shop instead of always
--- blue so it keeps doing the colour-navigation job instead of flattening it.
--- Four thin Neon bars rather than a filled plate, matching the "outline, not
--- fill" read the photo actually has.
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
			size = { 0.15, bar.w, bar.d },
			color = color,
			material = "Neon",
			canCollide = false,
		})
	end
end

-- ── The pennant awning ───────────────────────────────────────────────────────

--- A row of alternating-colour triangular flags hung from a thin rail along the
--- stall's front eave — the reference photo's candy-striped bunting canopy.
--- Each flag is a single WedgePart rather than a mirrored pair, which renders as
--- a right-triangle "shark tooth" pennant instead of a symmetric one: a
--- legitimate bunting style, and one part per flag instead of two.
---
--- WedgePart's uncut face sits in local Y-Z with the taper running along Z, so
--- `rot = Kit.ang(180, 90, 0)` is what turns that into a flat top edge, a
--- vertical left edge and a hypotenuse reaching down to the bottom-right when
--- viewed from the +Z approach — verified once against the actual approach
--- camera, the same way the sign's Back-face convention above was, rather than
--- trusted from rotation math alone.
---
--- Alternates `color` with a pale canvas rather than plain white — every other
--- colour already used in this file is a warm off-white (`C.canvasPale`,
--- `C.labelText`), and true white would be the one stark exception.
local function buildPennantAwning(parent: Instance, origin: CFrame, centerX: number, z: number, y: number, count: number, flagWidth: number, color: string)
	local flagHeight = 1.6
	local thickness = 0.2
	local totalWidth = count * flagWidth
	local startX = centerX - totalWidth / 2

	build(parent, origin, { name = "AwningRail", pos = { centerX, y, z }, size = { totalWidth + 0.4, 0.25, 0.25 }, color = C.hazardBlack, material = "Metal", shape = "Cylinder", rot = R.cylAlongX, canCollide = false })

	for i = 1, count do
		local flagColor = (i % 2 == 1) and color or C.canvasPale
		local flagX = startX + (i - 0.5) * flagWidth
		build(parent, origin, {
			name = `PennantFlag{i}`,
			pos = { flagX, y - flagHeight / 2, z },
			size = { thickness, flagHeight, flagWidth - 0.15 },
			color = flagColor,
			material = "Fabric",
			class = "WedgePart",
			rot = Kit.ang(180, 90, 0),
			canCollide = false,
		})
	end
end

-- ── Shop-specific props ─────────────────────────────────────────────────────────
--
-- One big, silhouette-clear prop of the actual thing each shop sells, standing
-- beside the counter — the differentiator now that every booth is the same shape.
-- All canCollide=false — display pieces, not obstacles to path around.

--- A metal detector: flat coil on the ground, a shaft rising from it, a control
--- box and a crossbar grip near the top. The coil-and-shaft silhouette is the one
--- unmistakable "detector" shape, so it carries the whole prop.
local function buildDetectorProp(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	build(parent, origin, { name = "DetectorCoil", pos = { x, 0.3, z }, size = { 0.4, 4.2, 4.2 }, color = C.steelDark, material = "Plastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "DetectorCoilTrim", pos = { x, 0.55, z }, size = { 0.15, 3.4, 3.4 }, color = color, material = "Plastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "DetectorShaft", pos = { x, 3.6, z }, size = { 6.5, 0.35, 0.35 }, color = C.steel, material = "Plastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "DetectorBox", pos = { x, 5.6, z }, size = { 1.1, 1.3, 0.8 }, color = color, material = "Plastic", canCollide = false })
	build(parent, origin, { name = "DetectorGrip", pos = { x, 6.9, z }, size = { 1.8, 0.3, 0.3 }, color = C.steel, material = "Plastic", canCollide = false })
end

--- A horseshoe magnet: two vertical prongs, a connecting bar at the bottom, white
--- tip caps at the top. Classic red-body-white-tips colouring rather than the
--- shop's own colour — the shape only reads as "magnet" instantly if the colours
--- match the cliché everyone already knows.
local function buildMagnetProp(parent: Instance, origin: CFrame, x: number, z: number)
	for _, dx in { -0.9, 0.9 } do
		build(parent, origin, { name = "MagnetProng", pos = { x + dx, 2.5, z }, size = { 5, 0.9, 0.9 }, color = C.barrelRust, material = "Plastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
		build(parent, origin, { name = "MagnetTip", pos = { x + dx, 5.1, z }, size = { 0.3, 1.0, 1.0 }, color = C.labelText, material = "Plastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	end
	-- Unrotated: a Cylinder's axis is local X by default, which is exactly the
	-- direction that needs to span between the two prongs — no rot needed.
	build(parent, origin, { name = "MagnetBase", pos = { x, 0.45, z }, size = { 2.7, 0.9, 0.9 }, color = C.barrelRust, material = "Plastic", shape = "Cylinder", canCollide = false })
end

--- A bucket, suds and a scrub brush leaning against it.
local function buildCleanerProp(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	build(parent, origin, { name = "Bucket", pos = { x, 1.1, z }, size = { 2.2, 2.6, 2.6 }, color = color, material = "Plastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "BucketRim", pos = { x, 2.25, z }, size = { 0.2, 2.8, 2.8 }, color = C.labelText, material = "Plastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })

	for _, offset in { { -0.5, 0 }, { 0.4, 0.3 }, { 0, -0.4 } } do
		build(parent, origin, {
			name = "Suds",
			pos = { x + offset[1], 2.7, z + offset[2] },
			size = { 0.7, 0.7, 0.7 },
			color = C.labelText,
			material = "Plastic",
			shape = "Ball",
			transparency = 0.15,
			canCollide = false,
		})
	end

	build(parent, origin, { name = "BrushHandle", pos = { x + 2.0, 2.0, z }, size = { 4.0, 0.3, 0.3 }, color = C.canvas, material = "Plastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "BrushHead", pos = { x + 2.0, 4.2, z }, size = { 0.6, 1.6, 1.6 }, color = C.labelText, material = "Plastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
end

--- A standing hazmat suit: torso, helmet with a visor, boots, arms.
local function buildSuitProp(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	build(parent, origin, { name = "SuitTorso", pos = { x, 2.6, z }, size = { 2.2, 1.8, 1.2 }, color = color, material = "Plastic", canCollide = false })
	build(parent, origin, { name = "SuitHelmet", pos = { x, 4.1, z }, size = { 1.6, 1.6, 1.6 }, color = C.labelText, material = "Plastic", shape = "Ball", canCollide = false })
	build(parent, origin, { name = "SuitVisor", pos = { x, 4.1, z - 0.75 }, size = { 0.9, 0.7, 0.15 }, color = C.cyan, material = "Plastic", canCollide = false })
	for _, dx in { -1.4, 1.4 } do
		build(parent, origin, { name = "SuitArm", pos = { x + dx, 2.7, z }, size = { 1.5, 0.5, 0.5 }, color = color, material = "Plastic", canCollide = false })
	end
	for _, dx in { -0.5, 0.5 } do
		build(parent, origin, { name = "SuitBoot", pos = { x + dx, 0.6, z }, size = { 0.7, 0.7, 1.0 }, color = C.hazardBlack, material = "Plastic", canCollide = false })
	end
end

--- A pair of boots side by side: foot, ankle shaft, sole.
--- Colour note: this and the satchel below use C.wood (dark brown), not
--- C.canvas — canvas is close enough to the outfitter's own yellow that a
--- first pass all but disappeared against the bench and backboard. Dark
--- brown is also just what boots and satchels actually look like.
local function buildBootsProp(parent: Instance, origin: CFrame, x: number, z: number)
	for _, dx in { -1.1, 1.1 } do
		build(parent, origin, { name = "BootFoot", pos = { x + dx, 0.55, z + 0.3 }, size = { 1.5, 0.7, 1.5 }, color = C.wood, material = "Plastic", canCollide = false })
		build(parent, origin, { name = "BootSole", pos = { x + dx, 0.18, z + 0.3 }, size = { 1.6, 0.15, 1.6 }, color = C.hazardBlack, material = "Plastic", canCollide = false })
		build(parent, origin, { name = "BootShaft", pos = { x + dx, 1.5, z - 0.4 }, size = { 0.9, 1.4, 0.9 }, color = C.wood, material = "Plastic", canCollide = false })
		build(parent, origin, { name = "BootLace", pos = { x + dx, 1.5, z - 0.85 }, size = { 0.3, 1.3, 0.15 }, color = C.shopOutfitter, material = "Plastic", canCollide = false })
	end
end

--- A satchel: a rounded bag body, a flap, a buckle, and a strap made from two
--- angled struts meeting above the bag rather than a true arc — Roblox parts
--- don't bend, and two straight struts read as a handle loop close enough at
--- this chunky, low-poly scale.
local function buildSatchelProp(parent: Instance, origin: CFrame, x: number, z: number)
	build(parent, origin, { name = "SatchelBody", pos = { x, 1.6, z }, size = { 1.8, 1.6, 1.1 }, color = C.wood, material = "Plastic", shape = "Ball", canCollide = false })
	build(parent, origin, { name = "SatchelFlap", pos = { x, 2.0, z - 0.55 }, size = { 1.6, 0.9, 0.3 }, color = C.woodLight, material = "Plastic", canCollide = false })
	build(parent, origin, { name = "SatchelBuckle", pos = { x, 1.9, z - 0.72 }, size = { 0.35, 0.35, 0.15 }, color = C.hazard, material = "Plastic", canCollide = false })
	for _, side in { -1, 1 } do
		build(parent, origin, {
			name = "SatchelStrap",
			pos = { x + side * 0.5, 2.7, z },
			size = { 1.3, 0.22, 0.22 },
			color = C.woodLight,
			material = "Plastic",
			rot = Kit.ang(0, 0, side * -35),
			canCollide = false,
		})
	end
end

--- A four-leaf clover on a stem. The Luck counter is the one shop selling something
--- with no physical form at all — you cannot draw "a 4.3x weight exponent" — so the
--- prop carries the entire identity here rather than merely reinforcing it, which is
--- why it is the largest and the only one that glows. Four ball leaves on a cross,
--- each rotated to sit on the diagonal, so it reads as a clover from any approach
--- angle instead of only from the front.
local function buildLuckProp(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	build(parent, origin, { name = "CloverStem", pos = { x, 1.4, z }, size = { 0.28, 2.8, 0.28 }, color = C.grassDark, material = "Plastic", canCollide = false })
	for _, corner in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		build(parent, origin, {
			name = "CloverLeaf",
			pos = { x + corner[1] * 0.72, 3.5, z + corner[2] * 0.72 },
			size = { 1.5, 0.5, 1.5 },
			color = C.grass,
			material = "Plastic",
			shape = "Ball",
			canCollide = false,
		})
	end
	-- The one glowing bead at the centre, in the shop's own accent rather than in
	-- green: green means the ooze everywhere else in this world (PLAN §14), and a
	-- glowing green clover on the plaza would be the one exception that breaks it.
	local heart = build(parent, origin, { name = "CloverHeart", pos = { x, 3.7, z }, size = { 0.55, 0.55, 0.55 }, color = color, material = "Neon", shape = "Ball", canCollide = false })
	light(heart, color, 10, 1.2)
end

--- Dispatches on track so buildStall/buildOutfitter can call one function without
--- caring which shop they're building.
local function buildIdentityProp(parent: Instance, origin: CFrame, track: string, x: number, z: number, color: string)
	if track == "Detector" then
		buildDetectorProp(parent, origin, x, z, color)
	elseif track == "Magnet" then
		buildMagnetProp(parent, origin, x, z)
	elseif track == "Cleaner" then
		buildCleanerProp(parent, origin, x, z, color)
	elseif track == "Suit" then
		buildSuitProp(parent, origin, x, z, color)
	elseif track == "Boots" then
		buildBootsProp(parent, origin, x, z)
	elseif track == "Satchel" then
		buildSatchelProp(parent, origin, x, z)
	elseif track == "Luck" then
		buildLuckProp(parent, origin, x, z, color)
	end
end

--- A wood shipping crate: a box with an X of cross-braces on the front face and one
--- small coloured item peeking over the rim — the "goods stacked outside the
--- stall" clutter the reference photo has (crates, a barrel, a boombox) that the
--- old single-prop stalls didn't.
local function buildCrateProp(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	build(parent, origin, { name = "CrateBox", pos = { x, 1.1, z }, size = { 2.2, 2.2, 2.2 }, color = C.wood, material = "Plastic", canCollide = false })
	for _, angle in { 35, -35 } do
		build(parent, origin, {
			name = "CrateBrace",
			pos = { x, 1.1, z },
			size = { 0.25, 2.9, 0.25 },
			color = C.woodLight,
			material = "Plastic",
			rot = Kit.ang(0, 0, angle),
			canCollide = false,
		})
	end
	build(parent, origin, { name = "CrateGoods", pos = { x, 2.55, z }, size = { 0.9, 0.9, 0.9 }, color = color, material = "Plastic", shape = "Ball", canCollide = false })
end

--- A small open chest: a wood base, a dark metal band, and a lid tilted back on
--- a single X-axis rotation so it reads as propped open, plus a glowing
--- spec.color peek of "contents" — the reference photo's open trunk, and one
--- more piece of "goods stacked outside the stall" clutter alongside the crate.
---
--- The lid's `pos` is solved rather than eyeballed: for `rot = Kit.ang(-70, 0, 0)`
--- and lid thickness/depth `t`/`d`, keeping the lid's local back-bottom edge
--- pinned to the chest's own back-top edge (so the lid reads as hinged there,
--- not floating) requires pos.y = chestTop - (-t/2*cos(-70°) - d/2*sin(-70°)) and
--- pos.z = (z - d/2) - (t/2*sin(-70°) - d/2*cos(-70°)).
local function buildOpenChestProp(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	local chestHeight = 1.0
	build(parent, origin, { name = "ChestBase", pos = { x, chestHeight / 2, z }, size = { 1.6, chestHeight, 1.2 }, color = C.wood, material = "Plastic", canCollide = false })
	build(parent, origin, { name = "ChestBand", pos = { x, chestHeight / 2, z }, size = { 1.7, 0.2, 1.3 }, color = C.hazardBlack, material = "Metal", canCollide = false })
	build(parent, origin, { name = "ChestLid", pos = { x, 1.59, z - 0.465 }, size = { 1.5, 0.15, 1.1 }, color = C.woodLight, material = "Plastic", rot = Kit.ang(-70, 0, 0), canCollide = false })
	build(parent, origin, { name = "ChestGlow", pos = { x, 1.1, z - 0.15 }, size = { 0.7, 0.35, 0.5 }, color = color, material = "Neon", shape = "Ball", canCollide = false })
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
}

--- The wood counter desk — the interactive part — with a coloured trim cap on
--- top. Returns the desk so the caller can billboard it. `material` defaults to
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
		size = { 2.2, w, d },
		color = C.wood,
		material = spec.material or "Wood",
		attributes = attrs,
	})

	build(parent, origin, { name = "CounterTrim", pos = { 0, 2.25, z }, size = { 0.3, w + 0.4, d + 0.4 }, color = spec.color, material = "Plastic", canCollide = false })

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
		color = C.wood,
		material = mat,
		shape = "Cylinder",
		rot = R.cylAlongX,
		canCollide = false,
	})

	return ridgeY
end

-- ── The plaza stalls ────────────────────────────────────────────────────────────

--- One toy-store kiosk: a wood counter on four posts under a bowed, candy-striped
--- awning, a shopkeeper behind the counter, a glowing sign over the roof, a floor
--- marker for the buy radius, and the shop's signature prop plus a crate of
--- clutter beside it. Open on all sides — no booth walls — matching the arch
--- awning's own reference photo, which all three stalls now share.
local function buildStall(parent: Instance, spec: { track: string, at: { number }, color: string, tagline: string })
	local m = Instance.new("Model")
	m.Name = `{spec.track}Shop`

	-- Y comes from Hub.PLAZA.topY, not a bare 0 -- the stall has to sit on whatever
	-- plane the plaza itself is actually on, and that stopped being world Y=0 once
	-- the plaza moved down to match Stages.SURFACE_Y (see Hub.luau's own comment on
	-- Hub.PLAZA). Every part below is a LOCAL offset from this origin, so this one
	-- line is the only thing that needed to change for the whole stall to move.
	local origin = CFrame.new(spec.at[1], Hub.PLAZA.topY, spec.at[2])

	-- LIFTED 0.1 CLEAR OF THE PLAZA, and that tenth of a stud is load-bearing. The
	-- deck is 0.6 thick, so at local y = -0.3 its top face lands exactly on origin's
	-- own Y — the same plane as the plaza's own surface, whatever that plane
	-- currently is. Two coplanar faces z-fight, which was invisible while both were
	-- cream and is not now that the floor underneath is a checkerboard. A pad lying
	-- ON the floor should sit on it, not in it.
	--
	-- CENTRED ON THE STALL, NOT ON THE ORIGIN. The posts/roof/counter cluster
	-- sits between dz=-10 (back posts) and dz=+2 (front posts) -- centred on
	-- z=-4, not z=0 -- because the origin is the OLD bowed-canopy stall's
	-- centre, not this one's. A disc centred at z=0 put half its own radius
	-- hanging out in front of the stall with nothing on it. Radius bumped
	-- 10->11 too, since the widened posts' outer corners (see POST_DX/size
	-- below) sit about 10.3 studs out from that centre.
	build(m, origin, {
		name = "Deck",
		pos = { 0, -0.2, -4 },
		size = { 0.6, 22, 22 },
		color = C.plazaWarm,
		material = "Plastic",
		shape = "Cylinder",
		rot = R.cylUp,
	})

	-- Four chunky wood posts holding the roof up. Square-cut lumber, not round
	-- logs — the reference photo's posts read as sawn beams, and Block needs no
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
	local POST_HEIGHT = 9
	local POST_SIZE = 2
	local POST_DX = 6.5
	for _, dx in { -POST_DX, POST_DX } do
		for _, dz in { -10, 2 } do
			build(m, origin, {
				name = "Post",
				pos = { dx, POST_HEIGHT / 2, dz },
				size = { POST_SIZE, POST_HEIGHT, POST_SIZE },
				color = C.wood,
				material = "Plastic",
				shape = "Block",
			})
		end
	end

	-- THE COUNTER. This is the part the whole file exists to place correctly.
	-- material = "Plastic" here (not buildCounter's own "Wood" default) so the
	-- studded look stays consistent across the whole stall -- the Outfitter's
	-- call to the same function passes no material and keeps its original Wood.
	local counter = buildCounter(m, origin, {
		color = spec.color,
		width = 12,
		depth = 3,
		z = -6,
		stationKind = "shop",
		stationId = spec.track,
		radius = 12,
		material = "Plastic",
	})
	billboard(counter, 260, 5.6, `{string.upper(spec.track)} SHOP`, spec.tagline, spec.color)

	buildShopkeeper(m, origin, 0, -7.2, spec.color)

	-- A real peaked roof -- same builder and the same reasoning as the
	-- Outfitter building, not the bowed/rolled-edge canopy this stall used to
	-- have. `halfDepth = 6` matches the post span exactly (dz -10 to +2, centred
	-- on -4), so the eaves land right at the post tops (buildGableRoof's own
	-- `clearance` now accounts for the panel's physical thickness on top of
	-- that). `rise = 4` (was 3) to keep the peak's proportions with the taller
	-- posts. `width = 15.4` (was 14) so the roof still overhangs the now-2-wide
	-- posts (outer edge at x=±7.5) by a bit, instead of the posts poking out
	-- past a roof sized for the old 1.1-wide ones. Plastic, same reason as the
	-- posts and counter -- the Outfitter's own call is untouched.
	local roofTop = buildGableRoof(m, origin, -4, POST_HEIGHT, 6, 4, 15.4, spec.color, "Plastic")

	-- The candy-striped bunting awning, hung along the front eave. z=3.5 (was
	-- 2.6) and flagWidth=1.1 (was 1.2) both shift to clear the now-2-wide front
	-- posts: post face sits at z=3 (dz=2 + POST_SIZE/2), so the rail needs to
	-- hang past that, and the flag row's half-width (5.5) now matches the
	-- posts' new inner edge (6.5-1) instead of overlapping it.
	buildPennantAwning(m, origin, 0, 3.5, POST_HEIGHT, 10, 1.1, spec.color)

	-- The big tilted signboard -- the reference photo's storefront board, angled
	-- back so it reads from ground level, floating clear above the roof ridge
	-- rather than nested into the gable (nothing there to clip into at any tilt).
	-- Block size is always {X, Y, Z} in local space with no rotation applied
	-- here, so width has to be FIRST and height SECOND or this renders as a tall
	-- obelisk instead of a wide sign board.
	-- SignFrame is thinner than Sign, not thicker: the two share the same centre,
	-- so whichever one is thicker pokes through and is what's actually visible
	-- head-on. The old small sign relied on exactly this (SignOutline 0.3 thick
	-- behind a 0.4-thick Sign) -- making the frame the thicker box here was
	-- backwards and hid the glowing coloured panel and its text entirely behind
	-- a solid wood face. Same ratio as before, just scaled up with the board.
	local SIGN_TILT = Kit.ang(18, 0, 0)
	local signY = roofTop + 2.9
	local signZ = -3.6
	build(m, origin, { name = "SignFrame", pos = { 0, signY, signZ }, size = { 10.6, 4.6, 0.32 }, color = C.wood, material = "Plastic", rot = SIGN_TILT, canCollide = false })
	local sign = build(m, origin, { name = "Sign", pos = { 0, signY, signZ }, size = { 9.8, 3.8, 0.44 }, color = spec.color, material = "Neon", rot = SIGN_TILT, canCollide = false })
	-- Back (local +Z), not Front (-Z): players approach this booth from +Z,
	-- coming down from the higher local-z porch toward the counter at z=-6, so
	-- the face pointing back AT them is Back, not Front. Got this backwards on
	-- the first pass and shipped a sign whose text only ever faced away from
	-- the approach -- caught by checking from the actual approach camera angle,
	-- not just confirming the parts existed. A pure X-axis tilt doesn't relabel
	-- local faces, so Back still means the same thing on the tilted board.
	Kit.surfaceText(sign, Enum.NormalId.Back, string.upper(spec.track), C.signText)
	light(sign, spec.color, 30, 2.4)

	-- The floor marker: a glowing outline of the buy radius, in the shop's own
	-- colour — never green, see the header.
	buildFloorMarker(m, origin, 0, -2, 10, 8, spec.color)

	-- THE ACTUAL POINT OF THIS PASS: a big, shape-clear prop of the thing this shop
	-- sells, standing beside the counter, plus a crate of clutter next to it.
	-- x offsets nudged out by 0.5 on both sides from the original 7.5/8.2/-8 --
	-- the post's outer edge moved from x=7.05 to x=7.5 when it went from
	-- 1.1-wide to 2-wide, and these need to keep clearing it.
	buildIdentityProp(m, origin, spec.track, 8.0, -5, spec.color)
	buildCrateProp(m, origin, 8.7, -1, spec.color)
	buildOpenChestProp(m, origin, -8.5, -2, spec.color)

	m.Parent = parent
	return m
end

-- ── The outfitter ─────────────────────────────────────────────────────────────

--- The outfitter: a proper building, not a bench under a trim strip. Three
--- shops left Suit, Boots and Satchel priced but unbuyable, and hazard gear that
--- actually reduces incoming damage earns more than a picnic table — four walls,
--- a peaked roof, and a real doorway facing the camp gate, with the three
--- counters inside. No room for three shopkeepers under one roof, so the
--- identity props keep doing the "which counter is which" job, exactly as they
--- already did before this pass.
local function buildOutfitter(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Outfitter"

	-- Same reasoning as buildStall's own origin: Y comes from Hub.PLAZA.topY, not a
	-- bare 0, so the building sits on the plaza's actual current plane.
	local origin = CFrame.new(OUTFITTER.at[1], Hub.PLAZA.topY, OUTFITTER.at[2])
	local span = OUTFITTER.pitch * (#OUTFITTER.counters - 1)
	local width = span + 20
	local halfDepth = 8
	local wallHeight = 7

	-- Same 0.1 lift as the stall decks, for the same reason: 0.4 thick at y = -0.2 put
	-- this floor's top face on the plaza's own plane and the two z-fought.
	build(m, origin, { name = "Floor", pos = { 0, -0.1, 0 }, size = { width, 0.4, halfDepth * 2 }, color = C.plazaWarm, material = "Plastic" })

	-- Back wall and two side walls. Open at the front (+Z, facing the camp
	-- gate) -- that's the doorway, not a fourth wall.
	build(m, origin, { name = "BackWall", pos = { 0, wallHeight / 2, -halfDepth }, size = { width, wallHeight, 0.6 }, color = C.wood, material = "Wood" })
	for _, dx in { -width / 2, width / 2 } do
		build(m, origin, { name = "SideWall", pos = { dx, wallHeight / 2, 0 }, size = { 0.6, wallHeight, halfDepth * 2 }, color = C.wood, material = "Wood" })
	end

	local ridgeY = buildGableRoof(m, origin, 0, wallHeight, halfDepth, 4, width + 2, C.shopOutfitter)

	-- The glowing sign, floating over the doorway, facing the approach from the
	-- camp gate -- same Back-face convention the plaza stalls use, for the same
	-- reason: whoever is walking toward this building is standing on the +Z side.
	-- Fixed size, not derived from the building's width — a sign that spans the
	-- whole 46-wide storefront came out as a comically long, thin plank with
	-- "OUTFITTER" lost in the middle of it, which read as stretched-out text even
	-- though TextScaled itself never distorts a glyph. The board's own proportions
	-- were the actual problem.
	local signY = ridgeY + 2.2
	build(m, origin, { name = "SignOutline", pos = { 0, signY, halfDepth - 0.2 }, size = { 15, 3.0, 0.3 }, color = C.hazardBlack, material = "Plastic", canCollide = false })
	local sign = build(m, origin, { name = "Sign", pos = { 0, signY, halfDepth + 0.2 }, size = { 14.4, 2.6, 0.4 }, color = C.shopOutfitter, material = "Neon", canCollide = false })
	Kit.surfaceText(sign, Enum.NormalId.Back, "OUTFITTER", C.signText)
	light(sign, C.shopOutfitter, 26, 2.2)

	buildFloorMarker(m, origin, 0, halfDepth - 3, width - 6, 8, C.shopOutfitter)

	for index, counter in OUTFITTER.counters do
		local x = -span / 2 + (index - 1) * OUTFITTER.pitch
		local counterOrigin = origin * CFrame.new(x, 0, 0)

		local desk = buildCounter(m, counterOrigin, {
			color = C.shopOutfitter,
			width = 4,
			depth = 2.4,
			z = -halfDepth + 3.5,
			stationKind = "shop",
			stationId = counter.track,
			-- Tighter than the plaza stalls: three counters share one building,
			-- and standing at one of them has to be unambiguous.
			radius = 6,
		})
		billboard(desk, 200, 4.4, counter.label, counter.tagline, C.shopOutfitter)

		-- Same idea as the plaza stalls: the actual gear, not just the counter.
		-- Offset to the SIDE, not straight in front — a first pass put it
		-- directly behind the counter on the approach axis, where the counter's
		-- own silhouette occluded almost the whole prop.
		buildIdentityProp(m, counterOrigin, counter.track, 2.3, -halfDepth + 5.5, C.shopOutfitter)
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

	-- Every track in Gear must be buyable somewhere, or it is a priced dead end.
	-- Checked here, at build time, because the failure is otherwise invisible until
	-- a player saves up for something they can never spend it on.
	local covered: { [string]: boolean } = {}
	for _, part in shops:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("StationKind") == "shop" then
			covered[part:GetAttribute("StationId") :: string] = true
		end
	end
	for _, track in Gear.TRACKS do
		assert(covered[track], `no shop sells the {track} track — it is priced but unbuyable`)
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
	print(`[build] Shops rebuilt — {#shops:GetChildren()} storefronts, all {#Gear.TRACKS} tracks covered`)
	return shops
end

return Shops
