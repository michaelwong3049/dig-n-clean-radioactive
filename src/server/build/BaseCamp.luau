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

	THE TRADER IS BACK, but not the old walled camp version. It is a compact open
	kiosk just south of the plaza midpoint: close enough to be the natural return
	stop after a run, but offset far enough that a player spawning at the exact
	middle does not immediately open the sell panel. The kiosk is intentionally low
	and open on every side, so it restores the sell loop without reintroducing a
	second enclosure inside the plaza.

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
local BUILDER_VERSION = 9

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
	-- behind a wall or at a player's private plot. The counter is 10 studs south of
	-- the respawn anchor and has an 8-stud station radius: arriving players can see
	-- it immediately but do not have a sale window forced open on spawn.
	local trader = Instance.new("Model")
	trader.Name = "Trader"

	local kiosk = origin * CFrame.new(0, 0, -12)
	build(trader, kiosk, {
		name = "Deck",
		pos = { 0, -0.35, 0 },
		size = { 13, 0.7, 7 },
		color = C.shopWoodLight,
		material = "WoodPlanks",
	})

	-- Four slim posts and a shallow striped roof make it read as a shop from the
	-- plaza without adding a solid wall to the central walking route.
	for _, x in { -5.4, 5.4 } do
		for _, z in { -2.5, 2.5 } do
			build(trader, kiosk, {
				name = "Post",
				pos = { x, 2.4, z },
				size = { 0.55, 5.5, 0.55 },
				color = C.shopWood,
				material = "Wood",
				studs = true,
			})
		end
	end
	build(trader, kiosk, {
		name = "Canopy",
		pos = { 0, 5.25, 0 },
		size = { 12.6, 0.45, 6.4 },
		color = C.canvasPale,
		material = "Fabric",
	})
	for _, x in { -4.2, 0, 4.2 } do
		build(trader, kiosk, {
			name = "CanopyStripe",
			pos = { x, 5.5, 0 },
			size = { 1.05, 0.08, 6.45 },
			color = C.gold,
			material = "Fabric",
		})
	end

	local counter = build(trader, kiosk, {
		name = "TraderCounter",
		pos = { 0, 1.05, 2.0 },
		size = { 10.8, 2.2, 1.25 },
		color = C.shopWood,
		material = "Wood",
		attributes = { StationKind = "trader", Radius = 8 },
	})
	build(trader, kiosk, {
		name = "CounterTop",
		pos = { 0, 2.23, 2.0 },
		size = { 11.2, 0.22, 1.6 },
		color = C.gold,
		material = "Metal",
	})
	billboard(counter, 210, 4.3, "TRADER", "turn finds into cash", C.gold)

	-- A scale and two open crates give the counter a clear purpose without a vendor
	-- NPC that would need animation and ownership code.
	build(trader, kiosk, {
		name = "ScaleBase",
		pos = { 0, 2.46, 1.6 },
		size = { 2.2, 0.18, 1.1 },
		color = C.steelDark,
		material = "Metal",
	})
	build(trader, kiosk, {
		name = "ScalePlate",
		pos = { 0, 2.68, 1.6 },
		size = { 1.45, 0.14, 0.8 },
		color = C.steel,
		material = "Metal",
	})
	for _, x in { -3.8, 3.8 } do
		build(trader, kiosk, {
			name = "TradeCrate",
			pos = { x, 0.65, -1.25 },
			size = { 2.1, 1.65, 1.8 },
			color = C.woodLight,
			material = "WoodPlanks",
		})
	end

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
