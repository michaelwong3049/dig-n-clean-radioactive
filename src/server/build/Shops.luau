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
	Gear.TRACKS has six entries. Three stalls covers Detector, Magnet and Cleaner and
	leaves Suit, Boots and Satchel priced but unbuyable — and the SUIT is the gate on
	every stage in the game. Without a way to buy one, Stage 2 stops being "you can go
	there and here is what it costs" and becomes exactly the locked door PLAN §3.5
	promises never to build. It costs nothing to add because the shop system
	is track-generic: it is three more counters with three more StationIds.

	THE LOOK — the supplied classic-Roblox Gear Store reference. Each tool stall
	has studded wooden posts, a slatted rear wall, an open counter with a steel cap,
	a shallow hot-pink-and-white striped canopy and matching valance, a tiny rubber
	duck on the roof, and the floating "Gear Store / Buy Helpful Items!" sign. The
	Outfitter remains the larger peaked-roof building across the aisle.

	IDENTITY STILL COMES FROM THE PROP, NOT THE STALL SHAPE. Every stall is the
	same shape, so the differentiator is still the same big, silhouette-clear
	prop of the actual thing sold (a detector, a horseshoe magnet, a
	bucket-and-brush) standing beside the counter, paired with a crate of
	clutter for a "goods stacked outside the stall" read.

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

	X BRIEFLY MOVED TO RING_CENTER, THEN CAME BACK. For a while every X here
	carried a further +14.5 on top of the +17.5 above, to sit centred under
	Plots.RING_CENTER (x=32) rather than the plaza's own midpoint (x=17.5) — one
	uniform offset from a world coordinate the plaza no longer straddled. That
	correction is REVERTED. Hub's grey central spine is a north-south strip
	centred on the plaza midpoint (x=17.5, which is also the camp spawn datum),
	and the cluster has to sit square on the spine, not hang off its east edge
	with a wide empty grey margin to the west. So the stalls are back to
	`17.5 + {-42, 0, +42}` and the Outfitter to x=17.5 — centred on the plaza
	exactly as para 1 already describes, with the RING_CENTER detour undone.
	Every pad still looks essentially straight at the cluster: 14.5 studs of
	offset from RING_CENTER is nothing at the ring's 180-stud radius. Plots.luau's
	SHOP_CLUSTER_EAST_REACH (53) is deliberately LEFT ALONE — the pad ring is not
	moving — so it is now a conservative bound on how far east the ring could sit,
	not a tight measurement of the Cleaner stall's east edge (which pulled ~14.5
	studs back west with the rest of the row). This file still reads nothing from
	Plots.luau: Plots requires Hub, Hub requires only Kit, and Shops stays a pure
	statement of positions rather than a new Shops<->Plots dependency.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)
local ItemModels = require(Shared.ItemModels)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local Shops = {}
local BUILDER_SOURCE = "src/server/build/Shops.luau"
local BUILDER_VERSION = 13

local C, R = Kit.C, Kit.R
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

--- The three plaza stalls. `at` is world XZ; they face south (−Z), across the
--- shop cluster's own centre aisle at z=0 toward the Outfitter. The row is
--- centred on x=17.5 — the plaza midpoint, the grey central spine's centreline
--- and the camp spawn datum, all the same coordinate — at a 42-stud pitch.
local STALLS = {
	{ track = "Detector", at = { -24.5, 22 }, color = C.shopDetector, tagline = "find it deeper" },
	{ track = "Magnet", at = { 17.5, 22 }, color = C.shopMagnet, tagline = "pull it harder" },
	{ track = "Cleaner", at = { 59.5, 22 }, color = C.shopCleaner, tagline = "scrub it cleaner" },
}

--- The outfitter's three counters, on one bench facing the stalls across the
--- shop cluster's own centre aisle. Radius 6 at a 13-stud pitch, so no two
--- counters' circles overlap and standing at one is unambiguous.
local OUTFITTER = {
	at = { 17.5, -22 },
	pitch = 13,
	counters = {
		{ track = "Suit", label = "SUITS", tagline = "survive it longer" },
		{ track = "Boots", label = "BOOTS", tagline = "get home faster" },
		{ track = "Satchel", label = "SATCHELS", tagline = "buy the clock time" },
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
			size = { bar.w, 0.15, bar.d },
			color = color,
			material = "Neon",
			canCollide = false,
		})
	end
end

-- ── Reference gear-store details ─────────────────────────────────────────────

local GEAR_STORE_PINK = "FF00E5"

--- The reference roof is one shallow rectangular awning, striped front-to-back,
--- with a short matching valance at the front. Separate studded Plastic parts
--- keep every stripe crisp and give it the chunky classic-Roblox texture.
local function buildStripedCanopy(parent: Instance, origin: CFrame): number
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
		local color = if index % 2 == 1 then GEAR_STORE_PINK else C.labelText
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
			color = C.wood,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end

	return centerY + 0.25
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
			color = C.woodLight,
			material = "Plastic",
			studs = true,
		})
	end
end

--- Large floating title copied from the reference's hierarchy: hot-pink store
--- name with a black outline, then a smaller white call-to-action below it.
local function buildGearStoreBillboard(adornee: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "GearStoreSign"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(360, 90)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 12.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 40
	gui.Parent = adornee

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 54)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.Text = "Gear Store"
	title.TextColor3 = Color3.fromHex(GEAR_STORE_PINK)
	title.TextSize = 42
	title.TextStrokeColor3 = Color3.fromHex(C.hazardBlack)
	title.TextStrokeTransparency = 0
	title.Parent = gui

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromOffset(0, 50)
	subtitle.Size = UDim2.new(1, 0, 0, 34)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamBold
	subtitle.Text = "Buy Helpful Items!"
	subtitle.TextColor3 = Color3.fromHex(C.labelText)
	subtitle.TextSize = 25
	subtitle.TextStrokeColor3 = Color3.fromHex(C.hazardBlack)
	subtitle.TextStrokeTransparency = 0
	subtitle.Parent = gui
end

local function buildRoofDuck(parent: Instance, origin: CFrame, roofY: number)
	local duck = ItemModels.create("RubberDuck")
	if duck == nil then
		return
	end
	duck.Name = "RoofDuck"
	duck:ScaleTo(0.55)
	duck:PivotTo(origin * CFrame.new(0, roofY, -3.5) * CFrame.Angles(0, math.rad(15), 0))
	duck.Parent = parent
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
	studded: boolean?,
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
		size = { w, 2.2, d },
		color = C.wood,
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
		color = C.wood,
		material = mat,
		shape = "Cylinder",
		rot = R.cylAlongX,
		canCollide = false,
	})

	return ridgeY
end

-- ── The plaza stalls ────────────────────────────────────────────────────────────

--- One classic-Roblox gear store: studded wood posts and rear slats, an open
--- counter, a pink-and-white striped roof, a tiny display duck, and the reference
--- image's floating two-line sign. The shop-specific prop and floor marker retain
--- the gameplay colour-coding beneath the shared pink storefront.
local function buildStall(parent: Instance, spec: { track: string, at: { number }, color: string, tagline: string })
	local m = Instance.new("Model")
	m.Name = `{spec.track}Shop`

	-- Y comes from Hub.PLAZA.topY, not a bare 0 -- the stall has to sit on whatever
	-- plane the plaza itself is actually on, and that stopped being world Y=0 once
	-- the plaza moved down to match Stages.SURFACE_Y (see Hub.luau's own comment on
	-- Hub.PLAZA). Every part below is a LOCAL offset from this origin, so this one
	-- line is the only thing that needed to change for the whole stall to move.
	local origin = CFrame.new(spec.at[1], Hub.PLAZA.topY, spec.at[2])

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
	local POST_SIZE = 1.5
	local POST_DX = 7.1
	for _, dx in { -POST_DX, POST_DX } do
		for _, dz in { -10, 2 } do
			local postHeight = if dz < 0 then 10 else 9.2
			build(m, origin, {
				name = "Post",
				pos = { dx, postHeight / 2, dz },
				size = { POST_SIZE, postHeight, POST_SIZE },
				color = C.wood,
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
	buildGearStoreBillboard(counter)

	buildShopkeeper(m, origin, 0, -1.1, spec.color)

	local roofTop = buildStripedCanopy(m, origin)
	buildRoofDuck(m, origin, roofTop)

	-- The floor marker: a glowing outline of the buy radius, in the shop's own
	-- colour — never green, see the header.
	buildFloorMarker(m, origin, 0, 3.4, 10, 5, spec.color)

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
