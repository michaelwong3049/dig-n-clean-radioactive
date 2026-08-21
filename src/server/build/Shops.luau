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

	THE LOOK — cartoony toxic-waste-barrel stalls, not market stalls.
	Every stall used to be a wood-plank-and-canvas farmers' market booth. Reskinned
	around one clear idea instead: each shop IS a big friendly radioactive drum —
	bright glossy SmoothPlastic body, chunky black hazard-stripe bands, a rounded
	dome roof, and a hand-built trefoil badge (three blocks radiating from a hub —
	see `buildTrefoil`) rather than a photo or decal, because there is no image
	asset to reference and low-poly chunky blocks are this game's whole art
	language anyway (PLAN §14). Bold black OUTLINE plates sit behind the coloured
	signs — the cheapest way to get a "toy packaging" pop out of flat Roblox parts.

	ONE DELIBERATE GLOW, AND IT IS NOT GREEN. PLAN §14's whole rule is "radiation is
	the only thing that glows [acid green]" — a shop glowing the same colour as the
	danger fields would dilute the one signal the whole map is built to teach. Each
	counter gets a single small glass vial that DOES glow (it is, thematically, the
	radioactive product on the shelf) but in cyan, not ooze green, so "glowing
	green" still means exactly one thing anywhere you stand.

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
local BUILDER_VERSION = 3

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

-- ── The trefoil ───────────────────────────────────────────────────────────────

--- The radiation symbol, built from parts: a yellow backing disc, a black hub, and
--- three black blades at 120°.
---
--- Kit.build composes `origin * CFrame.new(pos) * rot`, which rotates a part IN
--- PLACE around its own centre AFTER it has already been moved to `pos` — it does
--- NOT sweep the part around some other shared centre. That is exactly what is
--- wanted here, but only because `pos` for each blade is already the pre-rotated
--- orbit point (`radius * cos/sin(angle)`), not a fixed offset relied on `rot` to
--- also relocate. Rotating a symmetric block around its own centre after it is
--- correctly positioned looks identical to true orbital rotation; relying on `rot`
--- alone to both move and turn it would not.
---
--- `pos` is the badge centre in the caller's local space; the blades' plane is
--- local X/Y, thickness along local Z, so mount this on anything whose face
--- normal points along Z (every sign board in this file already does).
local function buildTrefoil(parent: Instance, origin: CFrame, pos: { number }, radius: number)
	-- Cylinder size is {axisLength, diameter, diameter} in local space, and the
	-- axis is ALWAYS the first number — cylAlongZ then points that axis along
	-- world Z. So the THIN dimension goes first, or this bulges into a stubby
	-- tube facing the viewer instead of a flat coin.
	build(parent, origin, {
		name = "TrefoilBacking",
		pos = pos,
		size = { 0.15, radius * 2.3, radius * 2.3 },
		color = C.hazard,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R.cylAlongZ,
		canCollide = false,
	})

	build(parent, origin, {
		name = "TrefoilHub",
		pos = { pos[1], pos[2], pos[3] + 0.12 },
		size = { 0.2, radius * 0.7, radius * 0.7 },
		color = C.hazardBlack,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R.cylAlongZ,
		canCollide = false,
	})

	for i = 0, 2 do
		local angle = i * 120
		local dx = radius * 0.62 * math.cos(math.rad(angle))
		local dy = radius * 0.62 * math.sin(math.rad(angle))
		build(parent, origin, {
			name = "TrefoilBlade",
			pos = { pos[1] + dx, pos[2] + dy, pos[3] + 0.12 },
			size = { radius * 0.85, radius * 0.42, 0.2 },
			color = C.hazardBlack,
			material = "SmoothPlastic",
			rot = Kit.ang(0, 0, angle),
			canCollide = false,
		})
	end
end

-- ── The barrel ────────────────────────────────────────────────────────────────

export type BarrelSpec = {
	color: string,
	diameter: number,
	height: number,
	baseY: number,
	z: number,
	stationKind: string?,
	stationId: string?,
	radius: number?,
}

--- The drum, its hazard stripes, its lid (the interactive part) and its one
--- deliberate cyan glow. Returns the lid so the caller can billboard it.
---
--- `stationKind`/`stationId`/`radius` are optional so this doubles as pure set
--- dressing for the clutter barrels — pass none of them and it is just a drum.
local function buildBarrel(parent: Instance, origin: CFrame, spec: BarrelSpec): BasePart
	local dia, h, baseY, z = spec.diameter, spec.height, spec.baseY, spec.z

	build(parent, origin, {
		name = "Barrel",
		pos = { 0, baseY + h / 2, z },
		size = { h, dia, dia },
		color = spec.color,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R.cylUp,
	})

	for _, frac in { 0.32, 0.68 } do
		build(parent, origin, {
			name = "HazardStripe",
			pos = { 0, baseY + h * frac, z },
			size = { h * 0.16, dia + 0.3, dia + 0.3 },
			color = C.hazardBlack,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R.cylUp,
		})
	end

	local attrs = nil
	if spec.stationKind then
		attrs = { StationKind = spec.stationKind, StationId = spec.stationId, Radius = spec.radius }
	end

	local lid = build(parent, origin, {
		name = "Lid",
		pos = { 0, baseY + h + 0.5, z },
		size = { 1.0, dia + 2, dia + 2 },
		color = spec.color,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R.cylUp,
		attributes = attrs,
	})

	-- THE GLOW. Cyan, never green — see the file header for why.
	--
	-- Cylinder size is {axisLength, diameter, diameter} in the part's OWN local
	-- space, and cylUp then reorients that axis onto world Y — so the FIRST
	-- number has to be the tall one or this renders as a squat oval, not a vial.
	local vialHeight = dia * 0.5
	local vialY = baseY + h + 1.6
	local vial = build(parent, origin, {
		name = "Vial",
		pos = { 0, vialY, z },
		size = { vialHeight, dia * 0.28, dia * 0.28 },
		color = C.cyan,
		material = "Neon",
		shape = "Cylinder",
		rot = R.cylUp,
		transparency = 0.15,
		canCollide = false,
	})
	build(parent, origin, {
		name = "VialCap",
		pos = { 0, vialY + vialHeight / 2, z },
		size = { dia * 0.1, dia * 0.34, dia * 0.34 },
		color = C.hazardBlack,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R.cylUp,
		canCollide = false,
	})
	light(vial, C.cyan, 12, 1.4)

	return lid
end

-- ── Shop-specific props ─────────────────────────────────────────────────────────
--
-- The barrel + dome + trefoil kit above is identical for every shop except colour,
-- which was the actual complaint: nothing about the SHAPE said "this is the magnet
-- one" versus "this is the cleaner one." Each shop gets one big, silhouette-clear
-- prop of the actual thing it sells, standing next to the counter, on top of the
-- colour-coding rather than instead of it. All canCollide=false — display pieces,
-- not obstacles to path around.

--- A metal detector: flat coil on the ground, a shaft rising from it, a control
--- box and a crossbar grip near the top. The coil-and-shaft silhouette is the one
--- unmistakable "detector" shape, so it carries the whole prop.
local function buildDetectorProp(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	build(parent, origin, { name = "DetectorCoil", pos = { x, 0.3, z }, size = { 0.4, 4.2, 4.2 }, color = C.steelDark, material = "SmoothPlastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "DetectorCoilTrim", pos = { x, 0.55, z }, size = { 0.15, 3.4, 3.4 }, color = color, material = "SmoothPlastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "DetectorShaft", pos = { x, 3.6, z }, size = { 6.5, 0.35, 0.35 }, color = C.steel, material = "SmoothPlastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "DetectorBox", pos = { x, 5.6, z }, size = { 1.1, 1.3, 0.8 }, color = color, material = "SmoothPlastic", canCollide = false })
	build(parent, origin, { name = "DetectorGrip", pos = { x, 6.9, z }, size = { 1.8, 0.3, 0.3 }, color = C.steel, material = "SmoothPlastic", canCollide = false })
end

--- A horseshoe magnet: two vertical prongs, a connecting bar at the bottom, white
--- tip caps at the top. Classic red-body-white-tips colouring rather than the
--- shop's own colour — the shape only reads as "magnet" instantly if the colours
--- match the cliché everyone already knows.
local function buildMagnetProp(parent: Instance, origin: CFrame, x: number, z: number)
	for _, dx in { -0.9, 0.9 } do
		build(parent, origin, { name = "MagnetProng", pos = { x + dx, 2.5, z }, size = { 5, 0.9, 0.9 }, color = C.barrelRust, material = "SmoothPlastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
		build(parent, origin, { name = "MagnetTip", pos = { x + dx, 5.1, z }, size = { 0.3, 1.0, 1.0 }, color = C.labelText, material = "SmoothPlastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	end
	-- Unrotated: a Cylinder's axis is local X by default, which is exactly the
	-- direction that needs to span between the two prongs — no rot needed.
	build(parent, origin, { name = "MagnetBase", pos = { x, 0.45, z }, size = { 2.7, 0.9, 0.9 }, color = C.barrelRust, material = "SmoothPlastic", shape = "Cylinder", canCollide = false })
end

--- A bucket, suds and a scrub brush leaning against it.
local function buildCleanerProp(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	build(parent, origin, { name = "Bucket", pos = { x, 1.1, z }, size = { 2.2, 2.6, 2.6 }, color = color, material = "SmoothPlastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "BucketRim", pos = { x, 2.25, z }, size = { 0.2, 2.8, 2.8 }, color = C.labelText, material = "SmoothPlastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })

	for _, offset in { { -0.5, 0 }, { 0.4, 0.3 }, { 0, -0.4 } } do
		build(parent, origin, {
			name = "Suds",
			pos = { x + offset[1], 2.7, z + offset[2] },
			size = { 0.7, 0.7, 0.7 },
			color = C.labelText,
			material = "SmoothPlastic",
			shape = "Ball",
			transparency = 0.15,
			canCollide = false,
		})
	end

	build(parent, origin, { name = "BrushHandle", pos = { x + 2.0, 2.0, z }, size = { 4.0, 0.3, 0.3 }, color = C.canvas, material = "SmoothPlastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
	build(parent, origin, { name = "BrushHead", pos = { x + 2.0, 4.2, z }, size = { 0.6, 1.6, 1.6 }, color = C.labelText, material = "SmoothPlastic", shape = "Cylinder", rot = R.cylUp, canCollide = false })
end

--- A standing hazmat suit: torso, helmet with a visor, boots, arms.
local function buildSuitProp(parent: Instance, origin: CFrame, x: number, z: number, color: string)
	build(parent, origin, { name = "SuitTorso", pos = { x, 2.6, z }, size = { 2.2, 1.8, 1.2 }, color = color, material = "SmoothPlastic", canCollide = false })
	build(parent, origin, { name = "SuitHelmet", pos = { x, 4.1, z }, size = { 1.6, 1.6, 1.6 }, color = C.labelText, material = "SmoothPlastic", shape = "Ball", canCollide = false })
	build(parent, origin, { name = "SuitVisor", pos = { x, 4.1, z - 0.75 }, size = { 0.9, 0.7, 0.15 }, color = C.cyan, material = "SmoothPlastic", canCollide = false })
	for _, dx in { -1.4, 1.4 } do
		build(parent, origin, { name = "SuitArm", pos = { x + dx, 2.7, z }, size = { 1.5, 0.5, 0.5 }, color = color, material = "SmoothPlastic", canCollide = false })
	end
	for _, dx in { -0.5, 0.5 } do
		build(parent, origin, { name = "SuitBoot", pos = { x + dx, 0.6, z }, size = { 0.7, 0.7, 1.0 }, color = C.hazardBlack, material = "SmoothPlastic", canCollide = false })
	end
end

--- A pair of boots side by side: foot, ankle shaft, sole.
--- Colour note: this and the satchel below use C.wood (dark brown), not
--- C.canvas — canvas is close enough to the outfitter's own yellow that a
--- first pass all but disappeared against the bench and backboard. Dark
--- brown is also just what boots and satchels actually look like.
local function buildBootsProp(parent: Instance, origin: CFrame, x: number, z: number)
	for _, dx in { -1.1, 1.1 } do
		build(parent, origin, { name = "BootFoot", pos = { x + dx, 0.55, z + 0.3 }, size = { 1.5, 0.7, 1.5 }, color = C.wood, material = "SmoothPlastic", canCollide = false })
		build(parent, origin, { name = "BootSole", pos = { x + dx, 0.18, z + 0.3 }, size = { 1.6, 0.15, 1.6 }, color = C.hazardBlack, material = "SmoothPlastic", canCollide = false })
		build(parent, origin, { name = "BootShaft", pos = { x + dx, 1.5, z - 0.4 }, size = { 0.9, 1.4, 0.9 }, color = C.wood, material = "SmoothPlastic", canCollide = false })
		build(parent, origin, { name = "BootLace", pos = { x + dx, 1.5, z - 0.85 }, size = { 0.3, 1.3, 0.15 }, color = C.shopOutfitter, material = "SmoothPlastic", canCollide = false })
	end
end

--- A satchel: a rounded bag body, a flap, a buckle, and a strap made from two
--- angled struts meeting above the bag rather than a true arc — Roblox parts
--- don't bend, and two straight struts read as a handle loop close enough at
--- this chunky, low-poly scale.
local function buildSatchelProp(parent: Instance, origin: CFrame, x: number, z: number)
	build(parent, origin, { name = "SatchelBody", pos = { x, 1.6, z }, size = { 1.8, 1.6, 1.1 }, color = C.wood, material = "SmoothPlastic", shape = "Ball", canCollide = false })
	build(parent, origin, { name = "SatchelFlap", pos = { x, 2.0, z - 0.55 }, size = { 1.6, 0.9, 0.3 }, color = C.woodLight, material = "SmoothPlastic", canCollide = false })
	build(parent, origin, { name = "SatchelBuckle", pos = { x, 1.9, z - 0.72 }, size = { 0.35, 0.35, 0.15 }, color = C.hazard, material = "SmoothPlastic", canCollide = false })
	for _, side in { -1, 1 } do
		build(parent, origin, {
			name = "SatchelStrap",
			pos = { x + side * 0.5, 2.7, z },
			size = { 1.3, 0.22, 0.22 },
			color = C.woodLight,
			material = "SmoothPlastic",
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

-- ── The plaza stalls ────────────────────────────────────────────────────────────

--- One toxic-drum stall: a round deck, the barrel (the counter you buy from), a
--- rounded canopy on four posts, a sign with a trefoil badge above it, and a
--- couple of mini barrels for clutter.
local function buildStall(parent: Instance, spec: { track: string, at: { number }, color: string, tagline: string })
	local m = Instance.new("Model")
	m.Name = `{spec.track}Shop`

	local origin = CFrame.new(spec.at[1], 0, spec.at[2])

	build(m, origin, {
		name = "Deck",
		pos = { 0, -0.3, 0 },
		size = { 0.6, 20, 20 },
		color = C.plazaWarm,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R.cylUp,
	})

	-- THE COUNTER. This is the part the whole file exists to place correctly.
	local lid = buildBarrel(m, origin, {
		color = spec.color,
		diameter = 6,
		height = 4.4,
		baseY = 0,
		z = -6,
		stationKind = "shop",
		stationId = spec.track,
		radius = 12,
	})
	billboard(lid, 260, 5.6, `{string.upper(spec.track)} SHOP`, spec.tagline, spec.color)

	-- Four chunky posts holding the canopy up. Height is sized to the dome
	-- below, not guessed independently — see the note there.
	local POST_HEIGHT = 6.5
	for _, dx in { -6.5, 6.5 } do
		for _, dz in { -10, 2 } do
			build(m, origin, {
				name = "Post",
				pos = { dx, POST_HEIGHT / 2, dz },
				size = { POST_HEIGHT, 1.0, 1.0 },
				color = C.hazardBlack,
				material = "SmoothPlastic",
				shape = "Cylinder",
				rot = R.cylUp,
			})
		end
	end

	-- The dome. A squashed Ball reads as a rounded canopy without needing an
	-- actual mesh — chunky and toy-like, which is the point. Sized to the
	-- BARREL, not to fill space: the first pass used a 22-wide dome over a
	-- 6-wide barrel and it read as a giant balloon on a stick, floating above
	-- a tiny stall rather than a roof over it.
	--
	-- An ellipsoid tapers to a POINT at its bottom pole, so sitting it flush on
	-- the posts (bounding boxes just touching) still reads as floating — the
	-- actual dome surface right above the post tops is razor-thin near that
	-- point. Pushed down further instead, so the posts visibly disappear a
	-- couple of studs into the dome's lower curve rather than stopping short
	-- of it.
	local DOME_W, DOME_H, DOME_D = 14, 4, 12
	local domeY = POST_HEIGHT - 1.5 + DOME_H / 2
	build(m, origin, {
		name = "Dome",
		pos = { 0, domeY, -4 },
		size = { DOME_W, DOME_H, DOME_D },
		color = spec.color,
		material = "SmoothPlastic",
		shape = "Ball",
		canCollide = false,
	})
	build(m, origin, {
		name = "DomeTrim",
		pos = { 0, POST_HEIGHT - 0.5, -4 },
		size = { 0.7, DOME_W - 1, DOME_D - 1 },
		color = C.hazard,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R.cylUp,
		canCollide = false,
	})

	-- The sign: a black outline plate behind a bright board, plus the trefoil
	-- badge floating above it. The outline is the whole "toy packaging" trick —
	-- a flat colour on a slightly bigger black backing reads as a bold cartoon
	-- outline without any actual line-drawing tool available in Roblox parts.
	-- Sized to the BARREL below it, not to the old 20-wide wooden deck — an
	-- 18-wide board dwarfed the new 6-wide barrel the same way the first-pass
	-- dome did.
	build(m, origin, { name = "BoardOutline", pos = { 0, 3.1, 8.3 }, size = { 11.6, 3.0, 0.3 }, color = C.hazardBlack, material = "SmoothPlastic" })
	local board = build(m, origin, { name = "Board", pos = { 0, 3.1, 8.1 }, size = { 11, 2.6, 0.4 }, color = spec.color, material = "Neon" })
	Kit.surfaceText(board, Enum.NormalId.Front, string.upper(spec.track), C.signText)
	light(board, spec.color, 26, 2.2)

	buildTrefoil(m, origin, { 0, 5.5, 8.1 }, 1.1)

	-- THE ACTUAL POINT OF THIS PASS: a big, shape-clear prop of the thing this
	-- shop sells, standing beside the counter. The barrel told you "a shop"; this
	-- tells you WHICH one, without reading a sign. Position checked against the
	-- 10-stud deck radius (sqrt(7.5^2 + 5^2) ~= 9.0), so it stays on the deck.
	buildIdentityProp(m, origin, spec.track, 7.5, -5, spec.color)

	m.Parent = parent
	return m
end

-- ── The outfitter ─────────────────────────────────────────────────────────────

--- The outfitter: one long bench, three mini-barrel counters on it, one shared
--- trefoil on the backboard instead of three crowded together.
local function buildOutfitter(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Outfitter"

	local origin = CFrame.new(OUTFITTER.at[1], 0, OUTFITTER.at[2])
	local span = OUTFITTER.pitch * (#OUTFITTER.counters - 1)

	build(m, origin, { name = "Bench", pos = { 0, -0.2, 0 }, size = { span + 18, 0.4, 12 }, color = C.steelDark, material = "DiamondPlate" })

	build(m, origin, { name = "BackboardOutline", pos = { 0, 3.3, 5.2 }, size = { span + 19, 6.4, 0.4 }, color = C.hazardBlack, material = "SmoothPlastic" })
	local backboard = build(m, origin, { name = "Backboard", pos = { 0, 3.3, 5 }, size = { span + 18, 6, 0.5 }, color = C.shopOutfitter, material = "Metal" })
	Kit.surfaceText(backboard, Enum.NormalId.Front, "OUTFITTER", C.signText)
	light(backboard, C.shopOutfitter, 24, 1.8)

	buildTrefoil(m, origin, { 0, 7.5, 5 }, 1.6)

	for index, counter in OUTFITTER.counters do
		local x = -span / 2 + (index - 1) * OUTFITTER.pitch
		local counterOrigin = origin * CFrame.new(x, 0, 0)

		local lid = buildBarrel(m, counterOrigin, {
			color = C.shopOutfitter,
			diameter = 3.6,
			height = 2.6,
			baseY = 0,
			z = -1.5,
			stationKind = "shop",
			stationId = counter.track,
			-- Tighter than the plaza stalls: three counters on one bench, and
			-- standing at one of them has to be unambiguous.
			radius = 6,
		})
		billboard(lid, 200, 4.4, counter.label, counter.tagline, C.shopOutfitter)

		-- Same idea as the plaza stalls, scaled to the bench: the actual gear,
		-- not just a coloured barrel. Offset to the SIDE, not straight in front
		-- — a first pass put it directly behind the barrel on the approach
		-- axis, where the barrel's own silhouette occluded almost the whole
		-- prop. 2.2 studs of sideways clearance is nothing next to the 13-stud
		-- counter pitch, so it can't drift into a neighbour's space.
		buildIdentityProp(m, counterOrigin, counter.track, 2.3, 1.0, C.shopOutfitter)
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
