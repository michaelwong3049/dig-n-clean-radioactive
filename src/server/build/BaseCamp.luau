--!strict
--[[
	BaseCamp.luau — THE SOURCE OF TRUTH for the base camp geometry.

	This is a build tool, not a service. Nothing requires it at boot; you run it by
	hand when the camp changes:

	    require(game.ServerScriptService.Server.build.BaseCamp).rebuild()

	WHY THIS FILE EXISTS
	The camp used to exist only as 101 instances inside the place file, which meant it
	was versioned nowhere and two people could not edit it without clobbering each
	other. The generator that originally produced it was run from the command bar and
	then lost — the same way the tool-tier generator was lost, leaving Config/ToolTiers
	as a recipe with no cook. Geometry that was born from code should stay as code.

	HOW TO EDIT
	Change a number here and re-run rebuild(). Do NOT drag parts in Studio: this file
	is authoritative, so the next rebuild silently reverts anything you moved by hand.
	That is the trade — you lose freehand dragging, you gain a camp that merges.

	The layout is deliberately expressed as loops and offsets rather than 101 literal
	positions, because that is what it actually is: 7 evenly spaced awning slats, 5
	jets on a 2.1-stud pitch, 4 posts at the corners. Editing "step" beats editing
	seven positions and hoping you got them all.

	NO DECON STATION AND NO SHOWER HERE ANY MORE. Both moved to `build/Plots.luau`
	— one combined "cleansing station" per base instead of one shared pair at
	camp, so a player docks and flushes exposure right where they're about to
	rack the item, not on a round trip back here. See Plots.luau's
	`buildCleansingStation` for the replacement and the reasoning.

	THE TRADER IS BACK, but not the old walled camp version. It is an open market
	stall now standing IN THE PLAZA STALLS' OWN SOUTH ROW, between MagnetShop and
	CleanerShop (build/Shops), rather than tucked just south of the respawn anchor
	— a player selling a haul is already walking the shop row to spend it, so the
	sell counter reads as the fourth stop on that row instead of a separate detour
	back toward spawn. It is open on every side, so it restores the sell loop
	without reintroducing a second enclosure inside the plaza. `build/Shops.luau`'s
	STALLS west column moved from x=-30 to x=-42 specifically to open this gap —
	see that file's header for the clearance numbers.

	THE STALL READS AS A BUILT FRAME, not four poles under a sheet: four slim posts
	in the pale storefront grey, deep-brown rail beams wrapping the frame in two
	rings (ground and counter height), a low grey counter across the front, and a
	striped gold-and-white awning that leans forward from tall back posts to short
	front ones, is cantilevered past the frame at both ends, and drops a short
	striped valance off its front edge — the same read as the plaza stalls
	(build/Shops' buildStripedCanopy), scaled up for one kiosk. The frame is studded
	plastic throughout (no wood texture); the awning is flat-coloured SmoothPlastic.

	NO ENTRANCE GATE EITHER. The two posts, their lamps, and the "BASE CAMP" sign
	spanning between them read as an archway framing the approach, which wasn't
	wanted — removed rather than reworked into something smaller. The camp is
	identified by what's standing on it (the shops, the plots), not a sign over
	the door.
]]

local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Kit)
local ModelGallery = require(script.Parent.ModelGallery)

local BaseCamp = {}
local BUILDER_SOURCE = "src/server/build/BaseCamp.luau"
local BUILDER_VERSION = 12

-- Where the camp sits. Everything else is relative to it, so moving the whole camp
-- is a one-line change (or an argument to build()). This used to be described as the
-- Floor's centre; the floor is gone (see buildShell) and the origin is now just the
-- camp's own datum, which is what it always actually was.
local DEFAULT_ORIGIN = CFrame.new(0, 0.9, 136)

-- ── Primitives ────────────────────────────────────────────────────────────────
-- `build`/`C` used to be aliased here from Kit, for the floor pad and the spawn.
-- Both are gone now (see buildShell); ModelGallery owns the yard's primitives, while
-- Kit remains responsible for this model's stamp and atomic rebuild plumbing.

export type Spec = Kit.Spec

local C = Kit.C
local build, billboard = Kit.build, Kit.billboard

-- ── The trader awning ─────────────────────────────────────────────────────────

--- A striped market awning centred on `origin` at height `y`: flat-coloured stripes
--- running front-to-back alternating gold and off-white, forced to an odd count so
--- the cloth opens and closes on gold, pitched `tilt` degrees down toward the
--- customer (+Z), with a short valance of the same stripes hanging straight down off
--- the front edge — the same read as the plaza stalls' canopies (build/Shops'
--- buildStripedCanopy), scaled for one open kiosk. SmoothPlastic, pure colour, no
--- texture.
local function buildTraderAwning(parent: Instance, origin: CFrame, y: number, centerZ: number, tilt: number, width: number, depth: number)
	local stripeCount = math.floor(width / 1.9)
	if stripeCount % 2 == 0 then
		stripeCount += 1
	end
	local stripeWidth = width / stripeCount
	local sinT = math.sin(math.rad(tilt))
	local frontZ = centerZ + depth / 2
	local frontY = y - sinT * (depth / 2)

	for i = 1, stripeCount do
		local color = if i % 2 == 1 then C.gold else C.canvasPale
		local x = -width / 2 + (i - 0.5) * stripeWidth
		build(parent, origin, {
			name = `AwningStripe{i}`,
			pos = { x, y, centerZ },
			size = { stripeWidth + 0.05, 0.5, depth },
			color = color,
			material = "SmoothPlastic",
			rot = Kit.ang(tilt, 0, 0),
			canCollide = false,
		})
		build(parent, origin, {
			name = `AwningValance{i}`,
			pos = { x, frontY - 0.9, frontZ },
			size = { stripeWidth + 0.05, 1.7, 0.4 },
			color = color,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end
end

-- ── The camp ──────────────────────────────────────────────────────────────────

local function buildShell(camp: Model, origin: CFrame)
	-- NO FLOOR PAD. There used to be a 64x46 slab of cream Pavement here whose top
	-- face landed on exactly Y = 0 — the same plane as the plaza it sits inside. That
	-- was invisible while the plaza was cream too: two coplanar faces in the same
	-- colour z-fight against each other every frame and nobody can tell. The plaza is
	-- a navy-and-grey checkerboard now, so the fight became a 64x46 patch of cream
	-- squares flickering through the pattern in the dead centre of the map.
	--
	-- Deleted rather than nudged up a hair, because the pad had no job left. It was
	-- the camp's ground back when the camp was a walled enclosure standing on open
	-- plaza; the walls went, the trader went, the gate went, and what remained was a
	-- rectangle of floor drawn on top of identical floor. The plaza IS the camp's
	-- ground. Nothing stood on the pad — the spawn below is positioned off the camp
	-- ORIGIN, not off the pad's top face — so removing it moves nothing.

	-- No enclosing walls, no entrance gate. Both used to box the camp off from
	-- the plaza it sits in; the camp now reads as one open shop area, identified
	-- by what's standing on it rather than a walled box with a sign over the door.

	-- NO SPAWN HERE ANY MORE EITHER. This used to be the join spawn AND the sole
	-- fallback while a player's data (and their assigned base) was still loading —
	-- "the middle checkpoint", central in the plaza while the 6 PlotSpawns ring it.
	-- Removed on purpose: every player belongs at their own personal base, not a
	-- shared camp pad, so the game now teleports each player to their assigned
	-- PlotSpawn directly (ExhibitService.assign()) instead of relying on a spawn
	-- point ever existing here. The cost is a brief undefined moment on a
	-- player's very first join, between the automatic character spawn and their
	-- data finishing loading — accepted, not fixed, since fixing it for real means
	-- delaying character creation until after data loads, a bigger change than
	-- was asked for.
	--
	-- The public model yard now gives BaseCamp a permanent authored structure again.
	-- It stays out of the central aisle and automatically includes every catalog item
	-- backed by ItemModels whenever this camp is rebuilt.
	ModelGallery.build(ModelGallery.originForBase(origin), camp)

	-- A small open trader kiosk, deliberately placed in the inner plaza rather than
	-- behind a wall or at a player's private plot. The counter has an 8-stud
	-- station radius.
	local trader = Instance.new("Model")
	trader.Name = "Trader"

	-- The plaza surface sits 0.9 below the camp datum here; every part builds up
	-- from this one local-Y so nothing floats over the tiles.
	local G = -0.9

	-- WORLD (-13, -38.5), IN THE GAP BETWEEN MAGNETSHOP AND CLEANERSHOP, not the
	-- old 12-stud-south-of-spawn spot. `origin` here is Hub.CAMP_ORIGIN, (17.5,
	-- -0.6, 0) with no rotation, so a local offset maps straight onto world XZ:
	-- (-30.5, 0, -38.5) local lands on world (-13, ~, -38.5). Z tracks Magnet and
	-- Cleaner's own `at` (build/Shops.luau's STALLS) whenever they move — the
	-- three were dragged together in Studio, so this file's Z has to move with
	-- theirs by hand each time; there is no live link between the two files. The
	-- kiosk keeps its original unrotated facing (local +Z = world +Z, i.e. north)
	-- unchanged, which already matches Magnet's and Cleaner's own `faceYaw = 0` —
	-- the row reads as one line of storefronts, not three different facings.
	local kiosk = origin * CFrame.new(-30.5, 0, -38.5)

	-- A low grey studded deck, just proud of the plaza tiles — the stall is studded
	-- throughout, like the plaza shops.
	build(trader, kiosk, {
		name = "Deck",
		pos = { 0, G + 0.2, 0 },
		size = { 17, 0.8, 13 },
		color = C.standGrey,
		material = "Plastic",
		studs = true,
	})

	-- Four slim studded posts in the pale storefront grey — the stall's frame, not
	-- four poles under a sheet. The back pair stands taller than the front pair so
	-- the awning leans forward on a real slope (a lean-to stall), which also keeps
	-- every post tucked under the cloth instead of poking through it.
	local POST = 0.95
	local POST_DX, POST_DZ = 6.8, 4.9
	local FRONT_H, BACK_H = 10.6, 11.8
	local SPAN_X = POST_DX * 2 - POST
	local SPAN_Z = POST_DZ * 2 - POST
	local BEAM = 0.55
	for _, x in { -POST_DX, POST_DX } do
		for _, z in { -POST_DZ, POST_DZ } do
			local h = if z > 0 then FRONT_H else BACK_H
			build(trader, kiosk, {
				name = "Post",
				pos = { x, G + h / 2, z },
				size = { POST, h, POST },
				color = C.shopWoodLight,
				material = "Plastic",
				studs = true,
			})
		end
	end

	-- Rail beams wrapping the frame — the market-stall read: a ground-height
	-- stretcher ring and a second at counter height, on the back and the two sides.
	-- The front is left open (that side is the counter). Deep-brown and studded, not
	-- a wood texture — the whole stall is studded plastic.
	local function railBeam(px: number, py: number, pz: number, sx: number, sz: number)
		build(trader, kiosk, {
			name = "RailBeam",
			pos = { px, py, pz },
			size = { sx, BEAM, sz },
			color = C.wood,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end
	for _, ringY in { G + 1.0, G + 5.4 } do
		for _, x in { -POST_DX, POST_DX } do
			railBeam(x, ringY, 0, BEAM, SPAN_Z)
		end
		railBeam(0, ringY, -POST_DZ, SPAN_X, BEAM)
	end

	-- The counter across the front — a low studded stall wall in storefront grey
	-- with a steel cap, carrying the sell station. It stands on the deck (top face
	-- G + 0.6) so it reads as furniture on the stall rather than a slab through it.
	local DECK_TOP = G + 0.6
	local COUNTER_H = 2.1
	local counter = build(trader, kiosk, {
		name = "TraderCounter",
		pos = { 0, DECK_TOP + COUNTER_H / 2, POST_DZ - 0.3 },
		size = { SPAN_X, COUNTER_H, 2.0 },
		color = C.shopWood,
		material = "Plastic",
		studs = true,
		attributes = { StationKind = "trader", Radius = 8 },
	})
	build(trader, kiosk, {
		name = "CounterTop",
		pos = { 0, DECK_TOP + COUNTER_H + 0.16, POST_DZ - 0.3 },
		size = { SPAN_X + 0.9, 0.32, 2.7 },
		color = C.steel,
		material = "Metal",
		canCollide = false,
	})
	billboard(counter, 210, 4.3, "TRADER", "turn finds into cash", C.gold)

	-- The striped awning: a gently forward-sloping roof with a modest, roughly even
	-- oversail front and back. The `y`/`centerZ`/tilt trio is tuned so the slab
	-- underside meets every post top flush (none poke through). A striped valance
	-- drops off the front edge.
	buildTraderAwning(trader, kiosk, G + 11.45, 0, 7, 14.6, 12.0)

	trader.Parent = camp
end

-- ── Entry points ──────────────────────────────────────────────────────────────

--- Construct a complete, unparented camp. Keeping it out of the DataModel while it
--- is assembled makes rebuild atomic: an error here cannot destroy the working camp.
local function createCamp(origin: CFrame): Model
	local camp = Instance.new("Model")
	camp.Name = "BaseCamp"
	Kit.stamp(camp, BUILDER_SOURCE, BUILDER_VERSION)

	buildShell(camp, origin)

	return camp
end

--- Construct the camp under `parent` (default Workspace) without removing anything.
function BaseCamp.build(origin: CFrame?, parent: Instance?): Model
	local camp = createCamp(origin or DEFAULT_ORIGIN)
	camp.Parent = parent or Workspace
	return camp
end

--- Replace the camp in the world. This is the one you run after editing this file.
--- Kit.swap builds first and only then destroys, so a bad edit that throws leaves
--- the camp currently in the world untouched.
function BaseCamp.rebuild(origin: CFrame?, parent: Instance?): Model
	local camp = Kit.swap("BaseCamp", function()
		return createCamp(origin or DEFAULT_ORIGIN)
	end, parent) :: Model
	print(`[build] BaseCamp rebuilt — {#camp:GetDescendants()} descendants`)
	return camp
end

return BaseCamp
