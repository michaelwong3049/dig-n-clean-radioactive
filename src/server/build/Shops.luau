--!strict
--[[
	Shops.luau — where cash turns back into capability.

	    require(game.ServerScriptService.Server.build.Shops).rebuild()

	THREE STALLS ON THE PLAZA, one per tool you hold: the detector that finds it, the
	magnet that pulls it, and the cleaner that scrubs it. Each is a different colour
	and keeps that colour forever. A young player learns "the coral one is the
	detector shop" once and then navigates by colour rather than by reading signs,
	which is the cheapest legibility win available anywhere in this map.

	PLUS AN OUTFITTER BENCH, and this one is not decoration.
	Gear.TRACKS has six entries. Three stalls covers Detector, Magnet and Cleaner and
	leaves Suit, Boots and Satchel priced but unbuyable — and the SUIT is the gate on
	every zone in the game. Without a way to buy one, Zone 2 stops being "you can go
	there and here is what it costs" and becomes exactly the locked door PLAN §3.5
	promises never to build. The bench costs nothing to add because the shop system
	is track-generic: it is three more counters with three more StationIds.

	THE LOOK — a classic toy-store kiosk, not a toxic drum, not a booth.
	The nuclear-drum reskin (round barrel counter, dome roof, trefoil badge) is
	long gone, replaced with a wood counter on four wood posts under a bowed,
	candy-striped, rolled-edge canopy (`buildArchAwning`), a little blocky
	shopkeeper standing behind the counter, and a glowing bubble sign floating
	over the roof peak. Open on all sides — no booth walls anywhere — matching
	the reference photo this shape came from. All three plaza stalls and the
	Outfitter's backboard trim share the one awning builder, just at different
	scales: a deep 35° bow for a stall roof you stand under, a wide, shallow 12°
	bow for a trim strip capping a shared bench. Per-shop colour-coding survives
	fully intact — the awning stripes, the sign, and the floor marker all use
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
	else. World positions (STALLS.at, OUTFITTER.at/pitch) and both Radius values are
	untouched — this file only changed what things look like, not where they are or
	how close you need to stand.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)

local Kit = require(script.Parent.Kit)

local Shops = {}
local BUILDER_SOURCE = "src/server/build/Shops.luau"
local BUILDER_VERSION = 4

local C, R = Kit.C, Kit.R
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

--- The three plaza stalls. `at` is world XZ; they face south, toward the fountainless
--- middle of the plaza where a player walks in from the south gate.
local STALLS = {
	{ track = "Detector", at = { -42, 45 }, color = C.shopDetector, tagline = "find it deeper" },
	{ track = "Magnet", at = { 0, 45 }, color = C.shopMagnet, tagline = "pull it harder" },
	{ track = "Cleaner", at = { 42, 45 }, color = C.shopCleaner, tagline = "scrub it cleaner" },
}

--- The outfitter's three counters, on one bench between the stalls and the camp gate.
--- Radius 6 at a 13-stud pitch, so no two counters' circles overlap and standing at
--- one is unambiguous.
local OUTFITTER = {
	at = { 0, -48 },
	pitch = 13,
	counters = {
		{ track = "Suit", label = "SUITS", tagline = "survive it longer" },
		{ track = "Boots", label = "BOOTS", tagline = "get home faster" },
		{ track = "Satchel", label = "SATCHELS", tagline = "buy the clock time" },
	},
}

-- ── The bowed awning ─────────────────────────────────────────────────────────

--- A bowed, rolled-edge canopy — every stall and the Outfitter's backboard trim
--- share this now. Built as SEGMENTS flat panels walked around a shallow arc (a
--- cheap fake-curve trick this project's chunky low-poly language already leans
--- on elsewhere) instead of a real curved surface, which Roblox parts can't do at
--- all. Each segment is a Block, so ITS SIZE STAYS {length, thickness, depth}
--- REGARDLESS OF ROTATION — a Block's local axes rotate WITH it, unlike a
--- Cylinder's fixed local axis, so there is no "which number is the axis" trap
--- here to get backwards.
---
--- `width` is the arc's total span end-to-end and `halfAngle` how deep the bow is
--- (degrees either side of the peak) — kept separate rather than a fixed radius
--- because this same shape has to cover both a ~14-wide stall canopy (a deep,
--- dramatic bow) and the Outfitter's ~40-wide backboard trim (a wide, shallow
--- one); one hardcoded radius could not do both.
---
--- Returns the arc's peak Y so the caller can float the sign above it without
--- re-deriving the same trig.
local function buildArchAwning(parent: Instance, origin: CFrame, centerZ: number, baseY: number, depth: number, width: number, halfAngle: number, color: string): number
	local segments = 7
	local radius = width / (2 * math.sin(math.rad(halfAngle)))
	local pivotY = baseY + radius * (1 - math.cos(math.rad(halfAngle)))
	local angleStep = (2 * halfAngle) / (segments - 1)
	-- A little longer than the pure chord length so consecutive segments
	-- overlap slightly instead of leaving hairline gaps at the seams.
	local segmentLen = 2 * radius * math.sin(math.rad(angleStep / 2)) * 1.2

	for i = 0, segments - 1 do
		local angle = -halfAngle + i * angleStep
		local rad = math.rad(angle)
		local x = radius * math.sin(rad)
		local y = pivotY - radius * (1 - math.cos(rad))
		local stripeColor = if i % 2 == 0 then color else C.labelText
		-- Only Z rotates (Kit.ang(0,0,angle)), so local Y and Z stay world Y and
		-- Z: Y has to be the thin dimension and Z the stall's depth, or this
		-- renders as a wall of vertical spikes instead of a flat roof panel.
		build(parent, origin, {
			name = "ArchSegment",
			pos = { x, y, centerZ },
			size = { segmentLen, 0.6, depth },
			color = stripeColor,
			material = "Plastic",
			rot = Kit.ang(0, 0, angle),
			canCollide = false,
		})
	end

	-- The rolled scroll ends -- the chunky wood "log" the fabric wraps around at
	-- each edge, the detail that reads as "bowed canopy" rather than just "two
	-- ramps." A Cylinder's axis is ALWAYS size[1] regardless of rot, so length
	-- goes first here even though it reads oddly next to the two diameters.
	for _, side in { -1, 1 } do
		local rad = math.rad(side * halfAngle)
		local x = radius * math.sin(rad)
		local y = pivotY - radius * (1 - math.cos(rad))
		build(parent, origin, {
			name = "AwningScroll",
			pos = { x, y, centerZ },
			size = { depth + 1, 1.6, 1.6 },
			color = C.wood,
			material = "Wood",
			shape = "Cylinder",
			rot = R.cylAlongZ,
			canCollide = false,
		})
	end

	return pivotY
end

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
	build(parent, origin, { name = "CrateBox", pos = { x, 1.1, z }, size = { 2.2, 2.2, 2.2 }, color = C.wood, material = "Wood", canCollide = false })
	for _, angle in { 35, -35 } do
		build(parent, origin, {
			name = "CrateBrace",
			pos = { x, 1.1, z },
			size = { 0.25, 2.9, 0.25 },
			color = C.woodLight,
			material = "Wood",
			rot = Kit.ang(0, 0, angle),
			canCollide = false,
		})
	end
	build(parent, origin, { name = "CrateGoods", pos = { x, 2.55, z }, size = { 0.9, 0.9, 0.9 }, color = color, material = "Plastic", shape = "Ball", canCollide = false })
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
}

--- The wood counter desk — the interactive part — with a coloured trim cap on
--- top. Returns the desk so the caller can billboard it.
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
		material = "Wood",
		attributes = attrs,
	})

	build(parent, origin, { name = "CounterTrim", pos = { 0, 2.25, z }, size = { 0.3, w + 0.4, d + 0.4 }, color = spec.color, material = "Plastic", canCollide = false })

	return desk
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

	local origin = CFrame.new(spec.at[1], 0, spec.at[2])

	build(m, origin, {
		name = "Deck",
		pos = { 0, -0.3, 0 },
		size = { 0.6, 20, 20 },
		color = C.plazaWarm,
		material = "Plastic",
		shape = "Cylinder",
		rot = R.cylUp,
	})

	-- Four chunky wood posts holding the awning up, positioned under the arch's
	-- own edge x (±6.9, see buildArchAwning) so post-top and roof-edge line up.
	local POST_HEIGHT = 6
	local POST_DX = 6.9
	for _, dx in { -POST_DX, POST_DX } do
		for _, dz in { -10, 2 } do
			build(m, origin, {
				name = "Post",
				pos = { dx, POST_HEIGHT / 2, dz },
				size = { POST_HEIGHT, 1.1, 1.1 },
				color = C.wood,
				material = "Wood",
				shape = "Cylinder",
				rot = R.cylUp,
			})
		end
	end

	-- THE COUNTER. This is the part the whole file exists to place correctly.
	local counter = buildCounter(m, origin, {
		color = spec.color,
		width = 12,
		depth = 3,
		z = -6,
		stationKind = "shop",
		stationId = spec.track,
		radius = 12,
	})
	billboard(counter, 260, 5.6, `{string.upper(spec.track)} SHOP`, spec.tagline, spec.color)

	buildShopkeeper(m, origin, 0, -7.2, spec.color)

	-- The awning, and the Y the sign should float above -- a function of the
	-- radius and half-angle buildArchAwning uses, not a number worth
	-- re-deriving at the call site.
	local roofTop = buildArchAwning(m, origin, -4, POST_HEIGHT, 12, 2 * POST_DX, 35, spec.color)

	-- The glowing bubble sign, floating over the roof peak. Block size is always
	-- {X, Y, Z} in local space with no rotation applied here, so width has to be
	-- FIRST and height SECOND or this renders as a tall obelisk instead of a
	-- wide sign board.
	local signY = roofTop + 2.6
	build(m, origin, { name = "SignOutline", pos = { 0, signY, -4.2 }, size = { 9.6, 2.6, 0.3 }, color = C.hazardBlack, material = "Plastic", canCollide = false })
	local sign = build(m, origin, { name = "Sign", pos = { 0, signY, -3.8 }, size = { 9, 2.2, 0.4 }, color = spec.color, material = "Neon", canCollide = false })
	-- Back (local +Z), not Front (-Z): players approach this booth from +Z,
	-- coming down from the higher local-z porch toward the counter at z=-6, so
	-- the face pointing back AT them is Back, not Front. Got this backwards on
	-- the first pass and shipped a sign whose text only ever faced away from
	-- the approach -- caught by checking from the actual approach camera angle,
	-- not just confirming the parts existed.
	Kit.surfaceText(sign, Enum.NormalId.Back, string.upper(spec.track), C.signText)
	light(sign, spec.color, 26, 2.2)

	-- The floor marker: a glowing outline of the buy radius, in the shop's own
	-- colour — never green, see the header.
	buildFloorMarker(m, origin, 0, -2, 10, 8, spec.color)

	-- THE ACTUAL POINT OF THIS PASS: a big, shape-clear prop of the thing this shop
	-- sells, standing beside the counter, plus a crate of clutter next to it.
	buildIdentityProp(m, origin, spec.track, 7.5, -5, spec.color)
	buildCrateProp(m, origin, 8.2, -1, spec.color)

	m.Parent = parent
	return m
end

-- ── The outfitter ─────────────────────────────────────────────────────────────

--- A simple peaked roof: two flat panels sloping up from the wall tops to a ridge
--- along the building's centreline, plus a capping ridge beam. `halfDepth` is the
--- distance from centre to each wall, `rise` how far the ridge climbs above the
--- wall tops. Positions are derived from the two literal points each panel spans
--- (wall-top eave, centre-line ridge) rather than reasoned out in the abstract --
--- this project has gotten CFrame rotation signs backwards from pure reasoning
--- more than once this session, and deriving from known points is the version
--- that's checkable by eye against the numbers.
---
--- Returns the ridge Y so the caller can float a sign above it.
local function buildGableRoof(parent: Instance, origin: CFrame, centerZ: number, wallHeight: number, halfDepth: number, rise: number, width: number, color: string): number
	local slopeLen = math.sqrt(halfDepth ^ 2 + rise ^ 2)
	local ridgeY = wallHeight + rise
	local tiltDeg = math.deg(math.atan2(rise, halfDepth))

	for _, side in { -1, 1 } do
		-- Eave point: (side*halfDepth, wallHeight). Ridge point: (0, ridgeY).
		-- The panel's own centre sits halfway between them.
		build(parent, origin, {
			name = "RoofPanel",
			pos = { 0, wallHeight + rise / 2, centerZ + side * halfDepth / 2 },
			size = { width, 0.6, slopeLen },
			color = color,
			material = "Wood",
			rot = Kit.ang(side * tiltDeg, 0, 0),
			canCollide = false,
		})
	end

	build(parent, origin, {
		name = "RoofRidge",
		pos = { 0, ridgeY, centerZ },
		size = { width, 1.1, 1.1 },
		color = C.wood,
		material = "Wood",
		shape = "Cylinder",
		rot = R.cylAlongX,
		canCollide = false,
	})

	return ridgeY
end

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

	local origin = CFrame.new(OUTFITTER.at[1], 0, OUTFITTER.at[2])
	local span = OUTFITTER.pitch * (#OUTFITTER.counters - 1)
	local width = span + 20
	local halfDepth = 8
	local wallHeight = 7

	build(m, origin, { name = "Floor", pos = { 0, -0.2, 0 }, size = { width, 0.4, halfDepth * 2 }, color = C.plazaWarm, material = "Plastic" })

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
	local signY = ridgeY + 2.2
	build(m, origin, { name = "SignOutline", pos = { 0, signY, halfDepth - 0.2 }, size = { width - 8, 2.6, 0.3 }, color = C.hazardBlack, material = "Plastic", canCollide = false })
	local sign = build(m, origin, { name = "Sign", pos = { 0, signY, halfDepth + 0.2 }, size = { width - 8.6, 2.2, 0.4 }, color = C.shopOutfitter, material = "Neon", canCollide = false })
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
