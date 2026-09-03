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

	NO WALLS AND NO TRADER HERE EITHER, as of this pass. The camp used to be a
	walled enclosure sitting inside the open plaza, boxing the trader off from the
	shops around it; both the walls and the trader are gone now, so the plaza reads
	as one open shop area instead of a plaza with a smaller walled camp inside it.
	The item-model yard in the southwest corner is now the only permanent structure
	owned by this module. THIS MEANS THERE IS
	CURRENTLY NO `StationKind = "trader"` ANYWHERE IN THE WORLD — `EconomyService.sell`
	and the "sell" verb in `DeconService`'s action router are still there and still
	work, but nothing in the world can trigger them until a trader (or some other
	sell point) is placed again somewhere. Flagged, not silently dropped — see TODO.md.

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
local BUILDER_VERSION = 8

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
