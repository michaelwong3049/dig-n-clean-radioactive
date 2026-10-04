--!strict
--[[
	Plots.luau — the Row. Six exhibition plots, one per player.

	    require(game.ServerScriptService.Server.build.Plots).rebuild()

	AN ITEM YOU SELL IS GONE. AN ITEM YOU DISPLAY KEEPS PAYING (PLAN §8).
	These are not sell pads — the Trader at the camp already does that. A plot is
	where a cleaned item goes to earn forever, in public, with your name under it.
	PLAN §8.1 is right that this is what makes a shared server worth having: without
	it the other five people are scenery.

	SIX PLOTS, SIX PLAYERS. MaxPlayers is set to 6 on the place so plots and players
	are 1:1 and there is no "sorry, full" case to design around. That is a place
	setting, not repo state — Rojo does not capture it — so it is written down in
	ARCHITECTURE.md as one of the things a fresh clone cannot reconstruct.

	TWO BASES TO A SIDE, SQUARED ROUND THE SHOPS — the requested layout (2026-10-03,
	from the user's sketch: "more square like ... more closer and compact"):

	                  ┌───────────────────┐
	                  │ [P5]    [P6]      │        (north wing)
	     ┌────────────┘                   │
	     │ [P4]                           │
	     │              ( SHOPS )          ===> STAGE 1   (east, open)
	     │ [P3]                           │
	     └────────────┐                   │
	                  │ [P2]    [P1]      │        (south wing)
	                  └───────────────────┘

	Two pads on each of the plaza's north, south and west edges, every one facing the
	shops, a ~20-stud walkway between the shop paving and each pad's front. The east side
	is open onto Stage 1. The perimeter wall (Scenery.buildBaseWalls) follows the stepped
	outline in Plots.CAMP: a "back" block holding the west pair and two wider wings
	holding the north and south pairs.

	IT WAS A SEMICIRCLE BEFORE THIS (six pads on a circle of radius 165 round a ring
	centre, each yawed to face it, a round perimeter wall at radius 274). Facings are
	multiples of 90 again now, but the pad maths stays on `Kit.orientedRect*`, which
	handles any yaw.

	IT WAS A RECTANGULAR RING BEFORE THE SEMICIRCLE — two pads on each of the plaza's
	north, south and west edges, butted flush against it. That shape hard-assumed every
	pad sat at a multiple of 90 degrees (both in the old `padBounds` here and in
	World.luau's own copy, and in how a pad's own tiles were built — see
	`buildPlot`'s comment on that below); a circle needs a real fix for both, not a
	new set of coordinates plugged into the old assumptions. `Kit.orientedRect*`
	(added alongside this rework) is what makes an arbitrary facing angle safe to
	overlap-test and tile.

	IT WAS A SINGLE COLUMN DOWN THE WEST SIDE BEFORE THAT, and that had a cost
	nobody had priced: the plaza had been stretched to 382 studs deep purely so it
	could span the column and let all six plots border it. Ringing them freed the
	plaza to be sized by what actually stands on it. The plots did not get
	smaller through any of these reshuffles; the car park between them did.

	A BASE WEARS THE PLAZA'S STUDDED BOARD IN ONE FLAT COLOUR. The pad is not a slab
	of concrete: it is the same studded tile board the courtyard is paved in, on the
	same grid, one step up from the apron — but a single flat wooden-deck brown
	(`Kit.C.baseFloor`), not the grass checker around it. The board has been every
	shape by now (navy/grey checker → flat grey → flat near-black → a smooth no-stud
	plate that glinted in the sun → charcoal studs); one flat tone, on request. That
	makes the six bases read as decks set into the lawn, and walking onto one a change
	of colour rather than a change of surface.

	A PAD'S FLOOR IS ONE PART, NOT A TILE GRID. It used to be `Hub.tileRect` laid in the
	pad's yawed local space — 391 cap tiles per pad, every one the same colour, so the
	grid bought nothing a single studded part does not show (studs are a surface type,
	not geometry). One `PadFloor` cap tops out at `pad.topY` and is what a player
	stands on; the structural `Hub.groundSlab` (which carries `PlotIndex`) is recessed
	one cap-thickness below it.

	THE DEPENDENCY FLIPPED, AGAIN, AND THIS TIME IT IS DERIVED RATHER THAN COMMENTED.
	This file used to require `Hub`, then stopped, and `Hub.luau` carried a comment
	listing four of this file's constants that its plaza had to be hand-matched to. It
	requires `Hub` again now — but to READ `Hub.PLAZA` and place the pads against it, so
	the two cannot drift. Hub requires only Kit, so the direction is safe.

	Plot INTERNALS still face south (spawn near the front) —
	nothing about station detection cares which way a plot faces, it's all
	radius-based, so re-stacking the six plots into this column cost zero
	gameplay risk. The internal arrangement itself (stands + cleansing station)
	changed since; see "THE BASE LAYOUT" below.

	THE BASE LAYOUT — a plain 3-column x 4-row grid of stands (on request,
	replacing the old two-flanking-columns-plus-infill scheme so the middle no
	longer reads as a deliberate gap), while a 17-stud entrance-side extension
	carries the active washing equipment and the rest is one open floor:

	    ┌─────────────────────────────────────┐ ← back fence, slides out per upgrade
	    │                                     │   (BaseExtension1..8 strips behind it)
	    │      open floor: nukes are placed    │
	    │      anywhere on it (Shared/         │
	    │      Placement), PlacedNukes folder  │
	    │ [UPGRADE]                            │
	    ├──────── original front edge ─────────┤
	    │  [locker]                            │
	    │  WASHER [bottle]          TREADMILL  │
	    │             entry (spawn)            │
	    └──────────[post]══arch══[post]───────┘

	THE OPEN FLOOR replaced a 12-stand grid and two bought storeys of 12 more (on
	request): a player places each nuke wherever it fits, and the Upgrade Base sign
	sells more of them along with a deeper floor (Config/BaseUpgrades). The entrance
	arch names the owner (buildEntranceArch); every fence post wears an accent cap.
	A claimed plot whose owner never picked a colour wears Plots.DEFAULT_ACCENTS.

	The Quarantine Locker (PLAN §10.2) — a rack of eight specimen tubes where you park
	finds instead of carrying them — backs onto the +X fence beside the cleansing
	station. Built here, filled by ExhibitService.renderLocker, opened by its own E
	prompt into the locker panel (client/LockerPanel); see buildQuarantineLocker.

	The cleansing station, its hose rig and the fluid bottle occupy the +X side of
	the entrance extension, the treadmill the -X side (where the wash pad stood
	until the pad was removed on request), with a deliberate safe gap between
	their station radii.

	THE WORLD CONTRACT:
	    Pad         PlotIndex = n
	    PlacedNukes Folder; ExhibitService puts one anchor part per placed nuke in it
	                (named by uid), carrying the model, the StandCard attributes and
	                the Take prompt. Empty in the saved place.
	    EntranceArch  decor; its ArchSign's SurfaceGui label `OwnerName` is written
	                by ExhibitService.renderName.
	    PlotSpawn   SpawnLocation, Enabled = false until the plot is claimed
	    Basin       StationKind = "decon", Shower = true, Radius = 9 — the cleansing
	                station (see buildCleansingStation below). One per base, replacing
	                the single shared station + shower that used to live at camp.
	                Carries a "Wash" ProximityPrompt; WashService wires it at boot.
	    WashStand   IsWashStand = true — invisible; where the item sits during a wash.
	    WashSpot    invisible; where the player is planted during a wash, facing the tub.
	                WashService steps them a little forward of it — the wash is shot
	                from the player's own head, and first person wants to be AT the tub.
	    WashCam     invisible; a side-on camera anchor. The wash used to be framed from
	                here; it is now first person (WashController), and this survives as
	                the fallback for the frame where the character's head is missing.
	    Hose        a Model on the mast beside the basin, PrimaryPart "Nozzle" — the
	                machine's own monitor (see buildHoseRig), at whatever Cleaner rung
	                this plot's owner has bought. Carries Muzzle / HoseEnd attachments
	                and a `ParkedPivot` CFrame, and stays ANCHORED: nothing ever puts
	                it in a player's hand, and WashController swings it LOCALLY for the
	                duration of a wash, then puts it back on ParkedPivot. Swapped rung
	                for rung by Plots.setHoseTier. The green line itself is a Beam
	                ("HoseLine") on HoseReel, from HoseAnchor to that nozzle's HoseEnd.
	    HoseMast    the post it is bolted to, with HoseMastFoot under it and HoseYoke —
	                the ball joint — at the top. Decor: nothing reads them.
	    Bottle      SpinsFluid = true, tagged Kit.FLUID_TAG — the fluid bottle on
	                its table beside the tub (see buildFluidBottle). Walking up to
	                your own opens the fluid panel (LiquidController): roll for a
	                fluid, upgrade Luck. `Liquid` parts inside FluidBottle wear the
	                owner's loaded fluid (Plots.setFluidBottle, written by
	                ExhibitService.renderBottle, never by name elsewhere), and so
	                does the tub's `Water` / `WaterSheen` (Plots.setTubFluid).
	    Belt        StationKind = "treadmill", Radius sized to the fitted model — the treadmill's running
	                surface (see buildTreadmill). Standing on it IS training; no
	                prompt, no session. Services/TreadmillService owns the clock.
	    Console     UpgradesTreadmill = true + a ProximityPrompt — unlocks the treadmill
	                (Treadmill.UNLOCK_PRICE), then buys the next belt rung. TreadmillService wires it at boot, by tag, the same way
	                ShopService wires the luck button.
	    Look        the imported treadmill model for the owner's belt rung, swapped
	                by Plots.setTreadmillTier; its console `Readout` screen carries
	                the speed and the bar. Both are written by
	                ExhibitService.renderTreadmill, never by name from anywhere else.
	    BaseExtension<k>  Model, one per upgrade level (k = 1..BaseUpgrades.MAX_LEVEL):
	                a strip of floor, trim and side fence behind the level-0 back edge.
	                Moved in and out of ServerStorage by Plots.setLevel, which also
	                slides BackFence (a Model) out behind the last strip shown.
	    UpgradeSign Model; its SignBoard carries UpgradesBase = true, PlotIndex = n and
	                a ProximityPrompt — opens the Upgrade Base popup. ExhibitService
	                wires it by Kit.BASE_UPGRADE_TAG and writes its Subtitle
	                (Plots.dressUpgradeSign). Shown only on a claimed, not-maxed plot.
	    QuarantineLocker   the specimen-tube rack. LockerSlot1..Plots.LOCKER_SLOTS are
	                hidden item anchors, LockerGlow<i> the pool ExhibitService.renderLocker
	                tints per stored find (from data.locker). LockerStation carries
	                StationKind = "locker", StationId = "<n>", PlotIndex = n,
	                Radius = 6 and the "OpenLocker" prompt that opens the locker panel.

]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local BaseUpgrades = require(Shared.Config.BaseUpgrades)
local Placement = require(Shared.Placement)
local Liquids = require(Shared.Config.Liquids)
local Treadmill = require(Shared.Config.Treadmill)
local Tuning = require(Shared.Config.Tuning)
local ToolModels = require(Shared.ToolModels)
local ToolFX = require(Shared.ToolFX)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local Plots = {}
local BUILDER_SOURCE = "src/server/build/Plots.luau"
local BUILDER_VERSION = 100 -- apron re-tiled for Hub's darker greys

local C = Kit.C
local build, light = Kit.build, Kit.light

Plots.COUNT = 6
-- How far past PAD.maxZ a fully upgraded base reaches (Config/BaseUpgrades). The pad
-- itself stays its level-0 size; the extension strips are built behind it.
Plots.MAX_EXTRA_DEPTH = BaseUpgrades.extraDepth(BaseUpgrades.MAX_LEVEL)

--- The accent a CLAIMED plot wears until its owner picks one in Settings, by plot
--- index. Most players never open Settings, and the gallery (arch caps, plinth bands,
--- fence caps, slot brackets) is mostly accent — in `C.plotNeutral` it reads as more
--- grey fence. One hue per plot, so the six bases in a server never match. Never saved
--- to the profile (ExhibitService.renderAccent picks it at paint time), so a player who
--- has never chosen simply wears whichever plot they land on. Kept clear of the
--- quarantine red and the stages' hazard greens.
Plots.DEFAULT_ACCENTS = {
	"FF9F43", -- orange
	"2EC4B6", -- teal
	"9B5DE5", -- purple
	"FF5D8F", -- pink
	"3FA7F5", -- blue
	"F9C74F", -- yellow
}
assert(#Plots.DEFAULT_ACCENTS == Plots.COUNT, "one default accent per plot")
-- Tubes in the Quarantine Locker rack (buildQuarantineLocker), one stored nuke each.
-- Config/Tuning owns the number because the server's store refusal and the client's
-- panel both read it too; ExhibitService.renderLocker fills exactly this many.
Plots.LOCKER_SLOTS = Tuning.LOCKER_SLOTS
-- topY is a deliberate step UP from the plaza (the mirror of Stages.SURFACE_Y's own
-- step down), expressed relative to Hub.PLAZA.topY rather than as a bare literal so
-- it keeps meaning "+1.5 above the plaza" if that ever moves again, instead of
-- silently becoming a different absolute step.
-- The original pad ran from local Z -26 to +26. Both edges have since moved,
-- independently: minZ went to -43 for a 17-stud entrance-side service strip (the
-- washing equipment and the luck button), and maxZ went from +26 to +44 on
-- request — an 18-stud extension straight out the back (then +12 more to 56, to
-- spread the stand rows further apart), behind the old wall, so
-- the stand grid can be spread over a deeper interior (GRID_ROWS below). The
-- back fence and accent trim both read maxZ, so they follow the edge out on
-- their own; the avatar plate floats over PAD_CENTER_Z instead, high above the
-- whole pad rather than tucked against either edge. Keeping explicit bounds
-- avoids pretending an asymmetric pad is centred on the plot origin.
local PAD_MIN_Z = -43
local PAD_MAX_Z = 56
Plots.PAD = {
	width = 66,
	depth = PAD_MAX_Z - PAD_MIN_Z,
	minZ = PAD_MIN_Z,
	maxZ = PAD_MAX_Z,
	topY = Hub.PLAZA.topY + 1.5,
	thickness = 3,
}

--- THE SQUARE. Six pads, two on each of the plaza's north, south and west edges, each
--- facing the shops. Hand-placed, like Hub's SHOP_ZONE and GATE_RECTS (which are cut to
--- these numbers -- move those with these).
---
--- `facing` is a yaw in degrees. A pad is built with its back fence at +Z and its
--- spawn/front at -Z, so 0 faces south (a north pad), 180 faces north (a south pad) and
--- -90 faces east (a west pad).
---
--- A pad's FRONT edge is its local Z = PAD_MIN_Z (-43), so the origin sits 43 studs
--- behind the front:
---   north/south pairs: fronts at z = +/-76 (the plaza edge is +/-70, the shop kerb
---       +/-51, so ~25 studs of walkway), x -42 and 34 -- pulled west of the shops'
---       centre so the leaderboards and the group chest keep the strip by the east wall.
---   west pair: fronts at x = -95, z +/-38 -- a 10-stud gap between the two. Pushed
---       back from -51 on request ("make the top longer, so the side bases aren't looking
---       at the top bases"): the north/south pads reach x = -75, so a front 20 studs past
---       that keeps the west pair out of their view. Gate paths (Hub.GATE_RECTS) run the
---       walk from the plaza's west edge (-49) out to them.
--- World.verify() checks that no pad overlaps the plaza, a stage, or another pad.
local PAD_FRONT_REACH = -PAD_MIN_Z -- origin to front edge
local NS_FRONT_Z = 76
local WEST_FRONT_X = -95
local NS_X = { -42, 34 }
local WEST_Z = 38

local PLAZA = Hub.PLAZA
local HALF_W = Plots.PAD.width / 2
local HALF_D = Plots.PAD.depth / 2
local PAD_CENTER_Z = (Plots.PAD.minZ + Plots.PAD.maxZ) / 2

local NS_Z = NS_FRONT_Z + PAD_FRONT_REACH
local WEST_X = WEST_FRONT_X - PAD_FRONT_REACH

--- Numbered round from the south-east, clockwise seen from above with the field on the
--- right: 1-2 south, 3-4 west, 5-6 north (the diagram in this file's header).
Plots.CENTERS = {
	{ x = NS_X[2], z = -NS_Z, facing = 180 },
	{ x = NS_X[1], z = -NS_Z, facing = 180 },
	{ x = WEST_X, z = -WEST_Z, facing = -90 },
	{ x = WEST_X, z = WEST_Z, facing = -90 },
	{ x = NS_X[1], z = NS_Z, facing = 0 },
	{ x = NS_X[2], z = NS_Z, facing = 0 },
}

--- THE CAMP OUTLINE -- the inner faces of the perimeter wall (Scenery.buildBaseWalls),
--- derived from the pads so a fully upgraded base (Plots.MAX_EXTRA_DEPTH past its back
--- edge) still clears the wall by WALL_CLEARANCE. Stepped, from the user's sketch:
---
---   the back block   x backX..eastX, |z| <= backHalfZ   -- holds the west pair
---   the two wings    x wingX..eastX, |z| <= wingZ       -- hold the north/south pairs
---
--- eastX is the east wall's inner face, the shoulders either side of Stage 1's mouth
--- (Scenery builds that wall on x = PLAZA.maxX, 8 thick). Everything that has to agree
--- on the camp's shape -- the apron, its rim lights, the wall, the base foliage,
--- World.verify()'s landmass -- reads this table or Plots.campRects.
local WALL_CLEARANCE = 10
local BACK_REACH = Plots.PAD.maxZ + Plots.MAX_EXTRA_DEPTH -- origin to a maxed pad's back edge
Plots.CAMP = {
	westFrontX = WEST_FRONT_X, -- the west pair's fronts (Scenery keeps the walk to them bare)
	eastX = PLAZA.maxX - 4,
	backX = WEST_X - BACK_REACH - WALL_CLEARANCE,
	backHalfZ = WEST_Z + HALF_W + WALL_CLEARANCE,
	wingX = math.min(NS_X[1], NS_X[2]) - HALF_W - WALL_CLEARANCE,
	wingZ = NS_Z + BACK_REACH + WALL_CLEARANCE,
}

--- The camp's floor as three axis rectangles -- the back block and the two wings, the
--- wings starting where the block stops so none overlap -- each grown by `grow` studs
--- on every walled side (the east side stays at PLAZA.maxX, Stage 1's edge). A positive
--- `grow` reaches under the wall, which is what the apron wants (see APRON_GROW).
function Plots.campRects(grow: number?): { Hub.Rect }
	local g = grow or 0
	local c = Plots.CAMP
	local block = c.backHalfZ + g
	return {
		{ minX = c.backX - g, maxX = PLAZA.maxX, minZ = -block, maxZ = block },
		{ minX = c.wingX - g, maxX = PLAZA.maxX, minZ = block, maxZ = c.wingZ + g },
		{ minX = c.wingX - g, maxX = PLAZA.maxX, minZ = -c.wingZ - g, maxZ = -block },
	}
end

--- Is (x, z) on the camp's floor (grown by `grow`, see campRects)?
function Plots.inCamp(x: number, z: number, grow: number?): boolean
	for _, r in Plots.campRects(grow) do
		if x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ then
			return true
		end
	end
	return false
end

--- A pad's true, ROTATED footprint — an `Kit.OrientedRect`, not an axis-aligned
--- bounding box. The square layout only uses right angles, but the semicircle before
--- it did not, and the oriented rectangle handles any yaw, so it stays: overlap and
--- containment
--- tests use the real oriented rectangle. `Kit.pointInOrientedRect` and
--- `Kit.orientedRectsOverlap` (used by this file's apron and by
--- World.verify()'s pad checks) both take this same shape.
---
--- `inset` (default 0) shrinks the rectangle by that many studs on every side.
--- `apronSkip` passes a full tile here so a cap tile straddling the pad edge is
--- KEPT rather than dropped — see PAD_SKIP_INSET.
local function padRect(c: { x: number, z: number, facing: number }, inset: number?): Kit.OrientedRect
	local yaw = math.rad(c.facing)
	local d = inset or 0
	return {
		cx = c.x + PAD_CENTER_Z * math.sin(yaw),
		cz = c.z + PAD_CENTER_Z * math.cos(yaw),
		halfWidth = HALF_W - d,
		halfDepth = HALF_D - d,
		yawDeg = c.facing,
	}
end

--- Every pad's own true footprint, exported for callers outside this file that need to
--- avoid a pad the same way `apronSkip` does (Scenery's base-plate foliage scatter, e.g.)
--- -- wraps the same private `padRect` this file's own skip test uses rather than a
--- second, independently-derived shape, so the two can never drift apart. `inset` is the
--- same "shrink every side by this many studs" convention `padRect` already takes;
--- pass a NEGATIVE value to grow the footprint outward instead (extra clearance).
function Plots.padRects(inset: number?): { Kit.OrientedRect }
	local rects = {}
	for i, c in Plots.CENTERS do
		rects[i] = padRect(c, inset)
	end
	return rects
end

--- THE APRON — the ground between the shop cluster, the pads and the perimeter wall,
--- minus the plaza (which already has its own floor) and minus every pad's own
--- footprint. Tile the camp's bounding box and drop whatever falls outside the camp
--- outline (Plots.campRects), inside the plaza, or inside a pad, via a skip predicate.
--- How far inside the plaza's own literal edge a tile's CENTRE has to land
--- before this treats it as safely covered by the plaza's own floor and skips
--- it here. NOT zero, and here is why: Hub.PLAZA is 165 studs in X (maxX - minX)
--- and the tile grid is 4 studs (Hub.TILE_SIZE) — 165 isn't a multiple of 4, so the
--- plaza's own westmost tile COLUMN is a partial-width tile clipped
--- to the plaza's real edge (exactly what Hub.tileRect's own header says edge
--- tiles do, correctly, on its own). This apron's tiling is a SEPARATE,
--- independently-clipped grid over a different, bigger rect, so its own tile
--- touching that same edge has a different centre and a different clip. At
--- zero margin a boundary tile whose centre lands JUST inside the plaza (by
--- this apron's own grid) got skipped here on the assumption the plaza already
--- covers it -- but the plaza's own clipped tile does NOT reach as far as this
--- apron tile's far edge, since the two grids clip independently. Net result,
--- confirmed live: a real gap, one stud wide, running the length of the
--- boundary, showing as a dark recessed seam (the structural backing slab
--- underneath, visible through the missing cap). A full tile width of margin
--- guarantees any tile whose true footprint reaches past the plaza's edge gets
--- built here too, even though its centre reads as "inside" — redundant with
--- the plaza's own edge tile there, but a doubled, coincident, same-colour,
--- same-height tile is invisible, unlike the seam it replaces.
local PLAZA_SKIP_MARGIN = 4

--- Same idea as PLAZA_SKIP_MARGIN, one edge in: how far inside a PAD's own footprint
--- a cap tile's centre has to land before this pass drops it. NOT zero. `Hub.tileRect`
--- calls `skip` with each tile's centre and a tile is 4 studs; a pad's footprint is
--- rotated ~5 degrees off the apron's axis-aligned grid, so tiles along a pad edge
--- cross it diagonally. At zero inset a tile whose centre lands just inside the pad
--- is dropped here even though a corner of it pokes back out over open apron — and
--- the pad's own tile grid (a separate, pad-clipped grid) does not reach that far,
--- so the recessed structural slab shows through as a ragged line of dark square
--- dents just outside each base. `Hub.tileRect`'s own header already promises the
--- opposite ("a tile straddling a pad edge is KEPT, and ends up buried inside the
--- pad"); one full tile of inset makes `apronSkip` honour that — a straddling tile
--- is kept, its outward corner is flush apron, and its inward bulk is swallowed by
--- the pad slab sitting 1.5 studs higher over the same ground.
local PAD_SKIP_INSET = 4

--- HOW FAR PAST THE CAMP OUTLINE THE GROUND IS ACTUALLY LAID. The Scenery perimeter
--- wall stands just OUTSIDE the outline (its inner face on it, 8 deep), so the ground
--- runs on under it rather than stopping at its face, where a seam of void would show
--- at the wall's foot. +10 is the 8 the wall needs plus a 2-stud cushion (Plots cannot
--- require Scenery to read WALL_THICKNESS: Scenery requires Plots).
local APRON_GROW = 10

local function apronSkip(x: number, z: number): boolean
	if not Plots.inCamp(x, z, APRON_GROW) then
		return true -- outside the camp (laid APRON_GROW past the outline, under the wall)
	end
	if
		x > PLAZA.minX + PLAZA_SKIP_MARGIN
		and x < PLAZA.maxX - PLAZA_SKIP_MARGIN
		and z > PLAZA.minZ + PLAZA_SKIP_MARGIN
		and z < PLAZA.maxZ - PLAZA_SKIP_MARGIN
	then
		return true -- safely inside the plaza's own floor, well past its edge tiles
	end
	-- The shop square reaches the plaza's west edge (x = -49, a tile line, so no seam):
	-- the plaza lays those cells itself as pavers and half-width kerb, and a doubled
	-- full paver here would poke up through the kerb band.
	if x > PLAZA.minX and x < PLAZA.maxX and z > PLAZA.minZ and z < PLAZA.maxZ then
		local cx, cz = Hub.cellCentre(x, z)
		if Hub.inShopFloor(cx, cz) then
			return true
		end
	end
	for _, c in Plots.CENTERS do
		if Kit.pointInOrientedRect(x, z, padRect(c, PAD_SKIP_INSET)) then
			return true
		end
	end
	return false
end

-- ── Round machines out of studded blocks ─────────────────────────────────────
-- The tub and the wash pad's well used to be four straight bars round a square, and a
-- square of studded bars reads as a crate however it is painted. These two lay the
-- same studded blocks round a regular polygon instead, so the machines keep the
-- base's stud texture and lose the crate.

type RingSpec = {
	name: string,
	sides: number,
	cx: number,
	cz: number,
	apothem: number, -- centre to the middle of each segment's thickness
	thickness: number,
	y: number, -- centre height
	height: number,
	color: string,
	material: string?,
	studs: boolean?,
	canCollide: boolean?,
	skip: ((number) -> boolean)?, -- leave segment i out (an open mouth)
}

--- A regular polygon of wall segments round (cx, cz). Segment `i` faces out along
--- i * 360 / sides degrees, measured from +Z toward +X, so segment 0 is the +Z side.
--- Each is exactly as long as the polygon's OUTER face: neighbouring outer corners meet
--- on the vertices, and the overlap the inner corners need to close up is buried
--- inside the next segment along.
local function polygonRing(parent: Instance, origin: CFrame, spec: RingSpec)
	local step = 360 / spec.sides
	local outer = spec.apothem + spec.thickness / 2
	local length = 2 * outer * math.tan(math.rad(step / 2))
	for i = 0, spec.sides - 1 do
		if spec.skip and spec.skip(i) then
			continue
		end
		local a = math.rad(i * step)
		build(parent, origin, {
			name = spec.name,
			pos = { spec.cx + spec.apothem * math.sin(a), spec.y, spec.cz + spec.apothem * math.cos(a) },
			size = { length, spec.height, spec.thickness },
			color = spec.color,
			material = spec.material or "Plastic",
			studs = spec.studs,
			canCollide = spec.canCollide,
			rot = Kit.ang(0, i * step, 0),
		})
	end
end

--- Where vertex `i` of a `polygonRing` falls -- the corner between segments i and i + 1 --
--- for a polygon whose flats sit `apothem` from the centre.
local function ringVertex(sides: number, cx: number, cz: number, apothem: number, i: number): (number, number)
	local step = math.rad(360 / sides)
	local r = apothem / math.cos(step / 2)
	local a = (i + 0.5) * step
	return cx + r * math.sin(a), cz + r * math.cos(a)
end

--- The cleansing station's tub shell (buildCleansingStation): an octagon of studded
--- walls, `apothem` from the basin centre to the middle of each wall. The hose rig's
--- pipe reads it to stop at the wall's outer face.
local TUB_SHELL = { sides = 8, apothem = 3.55, wall = 0.7 }

--- A cylinder lying along the authored Z axis. NOT Kit.R.cylAlongZ, which composes to
--- standing the cylinder up (Shared/ToolModels/Hose has the long version of that note).
local CYL_ALONG_Z = Kit.R.yaw90

--- An invisible part that only carries something -- a particle emitter, a SurfaceGui.
--- Never a thing a ray should land on: the wash hose traces its stream against the
--- whole bay, and a see-through box over the water would catch the splash in mid-air.
local function carrier(parent: Instance, origin: CFrame, name: string, pos: { number }, size: { number }): BasePart
	local part = build(parent, origin, {
		name = name,
		pos = pos,
		size = size,
		color = "FFFFFF",
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
	})
	part.CanQuery = false
	part.CanTouch = false
	return part
end

--- Repaint the reel drum, its wound-coil band and the Beam that runs to the nozzle so
--- the hose "still on the reel" matches whichever Cleaner rung is on the mast. The rig
--- is built once at STATION_TIER and never rebuilt; without this, buying a new hose swaps
--- the nozzle silhouette (Plots.setHoseTier) but leaves a garden-hose-green drum and a
--- green line arriving at, say, a violet Plasma Lance.
local function paintHoseRig(station: Instance, tier: number)
	local reel = station:FindFirstChild("HoseReel")
	if not (reel and reel:IsA("BasePart")) then
		return
	end
	local look = ToolModels.Hose.rigLook(tier)
	;(reel :: BasePart).Color = look.body

	local coil = station:FindFirstChild("HoseCoil")
	if coil and coil:IsA("BasePart") then
		coil.Color = look.coil
	end

	local line = reel:FindFirstChildOfClass("Beam")
	if line then
		-- Darker at both ends than the middle, exactly as buildHoseRig set it -- the band
		-- reads as a round tube catching the sky, and a Beam cannot shade itself.
		line.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, look.coil),
			ColorSequenceKeypoint.new(0.5, look.body),
			ColorSequenceKeypoint.new(1, look.coil),
		})
	end
end

--- The wash machine: the pump, the drum, the line, and the monitor on its mast (see
--- buildCleansingStation, which calls this). A pump unit standing behind the player's
--- wash mark, a reel of green hose coiled on its face, and a brass-tipped nozzle bolted
--- to a ball joint at the near corner of the tub.
---
--- IT IS A REAL OBJECT IN THE WORLD, NOT AN EFFECT DRAWN FOR THE DURATION OF A WASH,
--- and that is the whole reason it is built here rather than spawned by WashService.
--- Three things fall out of it that a per-session client effect cannot give:
---
---   * The station reads as a wash bay when nobody is using it. A tub with a hose
---     coiled beside it explains itself; a bare tub does not.
---   * THE CLEANER TRACK IS VISIBLE FROM ACROSS THE PLOT. The monitor on the mast is
---     the rung its owner bought (Plots.setHoseTier), so the upgrade is a thing anyone
---     walking onto the base can see — which is ToolService's "what you hold is public
---     storytelling" rule, kept intact after the thing stopped being held.
---   * Nothing has to define the hose's colours twice. Kit.C is here; a service is
---     not (see ShopService's own note on why it hardcodes UPGRADE_TAG).
---
--- NOBODY PICKS IT UP. WashService used to clone the parked nozzle into the player's
--- right hand for the length of a session, stash the original, and swing the beam's
--- far end onto the copy. All of that is gone: the nozzle stays bolted to its mast and
--- WashController merely POINTS it, locally, for whoever is at the mark. The old
--- arrangement needed a copy rather than the parked nozzle itself, because an anchored
--- part anchors its whole assembly and jointing one to a character bolts that character
--- to the world — a hazard that simply stops existing once nothing is jointed to
--- anybody. What is left is one anchored model whose CFrame a client rewrites per
--- frame, which replicates to nobody and can strand no one.
---
--- THE HOSE ITSELF IS A Beam, NOT A CHAIN OF PARTS, and it costs nothing per frame
--- because of it. A Beam spans two Attachments and re-renders itself whenever either
--- one moves — one is bolted to the reel, the other rides the nozzle as it swivels, so
--- the line follows the aim for free with no script running anywhere. `CurveSize0/1`
--- give it the slack a hose has when it is not under tension; a chain of parts would
--- need a per-frame catenary solve to fake the same thing and would still be jointed.
local function buildHoseRig(parent: Instance, origin: CFrame, cx: number, cz: number)
	local pad = Plots.PAD
	local T = pad.topY

	-- Studded plastic to match the bay (buildCleansingStation). `BODY` is the base-course
	-- grey the deck and the display plinths wear, `FIT` the smooth metal of the pipes and
	-- bolts; the tank itself is clear glass with the fluid inside.
	local BODY, FIT = C.standGreyDark, C.steelDark

	-- Tucked into the front-right corner of the deck (the player's right at WashSpot), well clear of the straight walk-up
	-- to WashSpot and out of the tub's own sightline from the aisle. The whole rig
	-- follows (px, pz) so the bay moves as one.
	local px, pz = cx - 7, cz - 9

	-- A skid under the housing, so the pump reads as a unit set down and bolted rather
	-- than a crate left on the tiles.
	build(parent, origin, { name = "ReelSkid", pos = { px + 0.9, T + 0.35, pz }, size = { 2.2, 0.7, 2.6 }, color = BODY, material = "Plastic", studs = true })

	-- ── The pump: tank + motor on the skid ────────────────────
	-- PICKED BY THE USER from a round of AI-generated pump models ("D", built from
	-- primitives), then rebuilt here out of studded parts so it lives in code, survives a
	-- rebuild and wears the base's stud texture. A banded yellow pressure tank with a
	-- gauge and a valve handwheel, and beside it a finned grey motor driving a spoked
	-- flywheel. The gauge and the flywheel face the aisle (authored -Z), the side you
	-- walk past; the motor's end cap and a warning placard face the plot entrance (+X).
	-- The reel still hangs off the tank's -X side on its axle, and the pipe to the tub
	-- still leaves from the tank's +Z side.
	local SPOKE_YELLOW, MOTOR_GREY, METAL_LIGHT = "FAD214", "82878C", "B4B9BE"
	-- THE TANK STANDS APART FROM THE REEL, on request: against the tub's right flat
	-- face, where the brew bottle's table used to be, with the motor behind it. The
	-- reel and the mast stay at the front corner; `tz` is the tank's own Z.
	local tx, tz = cx - 5.9, cz
	local tankR, tankBottom, tankTop = 0.8, T + 0.7, T + 3.7
	build(parent, origin, { name = "PumpSkid", pos = { tx - 0.55, T + 0.35, tz + 0.15 }, size = { 3.0, 0.7, 2.6 }, color = BODY, material = "Plastic", studs = true })
	-- A CLEAR TANK WITH THE OWNER'S FLUID IN IT, on request (it was solid hazard
	-- yellow). The shell is see-through glass; `PumpFluid` inside it is filled most of
	-- the way up and wears the loaded fluid's colour -- Plots.setTubFluid paints it
	-- alongside the tub's Water, so tank and tub always hold the same liquid.
	local TANK_GLASS = "FFFFFF"
	build(parent, origin, {
		name = "HosePump",
		pos = { tx, (tankBottom + tankTop) / 2, tz },
		size = { tankTop - tankBottom, tankR * 2, tankR * 2 },
		color = TANK_GLASS,
		material = "SmoothPlastic",
		transparency = 0.88,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
	})
	local fluidTop = tankBottom + (tankTop - tankBottom) * 0.8
	build(parent, origin, {
		name = "PumpFluid",
		pos = { tx, (tankBottom + 0.05 + fluidTop) / 2, tz },
		size = { fluidTop - tankBottom - 0.05, tankR * 2 - 0.08, tankR * 2 - 0.08 },
		color = Liquids.get(Liquids.WATER).color,
		material = "SmoothPlastic",
		transparency = 0,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		canCollide = false,
	})
	for _, bandY in { T + 1.3, T + 3.1 } do
		build(parent, origin, {
			name = "PumpHoop",
			pos = { tx, bandY, tz },
			size = { 0.2, tankR * 2 + 0.1, tankR * 2 + 0.1 },
			color = C.hazardBlack,
			material = "Plastic",
			studs = true,
			shape = "Cylinder",
			rot = Kit.R.cylUp,
			canCollide = false,
		})
	end
	-- The dome: a ball as wide as the tank, sunk to its equator in the tank's top.
	build(parent, origin, {
		name = "PumpDome",
		pos = { tx, tankTop, tz },
		size = { tankR * 2, tankR * 2, tankR * 2 },
		color = TANK_GLASS,
		material = "SmoothPlastic",
		transparency = 0.88,
		shape = "Ball",
		canCollide = false,
	})

	-- The valve on the crown: a base, a stem, and a spoked handwheel whose rim is a
	-- ring of studded segments rather than a solid disc, so it reads as a wheel.
	local domeTop = tankTop + tankR
	build(parent, origin, { name = "PumpValve", pos = { tx, domeTop + 0.07, tz }, size = { 0.15, 0.48, 0.48 }, color = MOTOR_GREY, material = "Plastic", studs = true, shape = "Cylinder", rot = Kit.R.cylUp, canCollide = false })
	build(parent, origin, { name = "PumpValveStem", pos = { tx, domeTop + 0.3, tz }, size = { 0.32, 0.24, 0.24 }, color = C.hazardBlack, material = "Metal", shape = "Cylinder", rot = Kit.R.cylUp, canCollide = false })
	local wheelY = domeTop + 0.5
	polygonRing(parent, origin, {
		name = "PumpValveWheel",
		sides = 10,
		cx = tx,
		cz = tz,
		apothem = 0.55,
		thickness = 0.12,
		y = wheelY,
		height = 0.12,
		color = C.hazardBlack,
		studs = true,
		canCollide = false,
	})
	build(parent, origin, { name = "PumpValveHub", pos = { tx, wheelY, tz }, size = { 0.2, 0.36, 0.36 }, color = C.hazardBlack, material = "Plastic", studs = true, shape = "Cylinder", rot = Kit.R.cylUp, canCollide = false })
	for k = 0, 1 do
		build(parent, origin, { name = "PumpValveSpoke", pos = { tx, wheelY, tz }, size = { 1.1, 0.08, 0.1 }, color = C.hazardBlack, material = "Metal", rot = Kit.ang(0, 45 + k * 90, 0), canCollide = false })
	end

	-- THE GAUGE, on the aisle face of the tank: a grey case on a stub mount, a white
	-- face with eight ticks, and a red needle that wanders about the dial
	-- (StationMotionController), because a pressure gauge that never twitches reads as
	-- a sticker.
	local gy = T + 2.35
	local gaugeZ = tz - tankR - 0.02
	build(parent, origin, { name = "GaugeMount", pos = { tx, gy, tz - tankR + 0.2 }, size = { 0.7, 0.6, 0.6 }, color = MOTOR_GREY, material = "Plastic", studs = true, shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
	build(parent, origin, { name = "PumpGauge", pos = { tx, gy, gaugeZ }, size = { 0.18, 0.92, 0.92 }, color = METAL_LIGHT, material = "Metal", shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
	local faceZ = gaugeZ - 0.1
	build(parent, origin, { name = "GaugeFace", pos = { tx, gy, faceZ }, size = { 0.04, 0.76, 0.76 }, color = C.labelText, material = "SmoothPlastic", shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
	local dial = origin * CFrame.new(tx, gy, faceZ - 0.03)
	for k = 0, 7 do
		build(parent, dial * Kit.ang(0, 0, k * 45), { name = "GaugeTick", pos = { 0, 0.3, 0 }, size = { 0.04, 0.1, 0.02 }, color = C.hazardBlack, material = "SmoothPlastic", canCollide = false })
	end
	local needle = build(parent, dial, {
		name = "GaugeNeedle",
		pos = { 0, 0.14, -0.01 },
		size = { 0.04, 0.3, 0.02 },
		color = C.quarantineRed,
		material = "SmoothPlastic",
		canCollide = false,
	})
	-- Pivot on the spindle at the dial's centre, not on the needle's own middle.
	needle.PivotOffset = CFrame.new(0, -0.14, 0)
	Kit.motion(needle, { kind = "sway", axis = "Z", rate = 0.9, amp = 0.55 })
	build(parent, dial, { name = "GaugePin", pos = { 0, 0, -0.02 }, size = { 0.04, 0.1, 0.1 }, color = C.hazardBlack, material = "SmoothPlastic", shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })

	-- The motor, lying along Z beside the tank on a studded mount: a grey drum ringed
	-- with cooling fins, an end cap toward the tub, a junction box on top.
	local motorX, motorY, motorZ = tx - 1.2, T + 1.25, tz + 0.2
	build(parent, origin, { name = "MotorMount", pos = { motorX, T + 0.97, motorZ }, size = { 0.72, 0.55, 1.2 }, color = MOTOR_GREY, material = "Plastic", studs = true, canCollide = false })
	build(parent, origin, { name = "MotorCore", pos = { motorX, motorY, motorZ }, size = { 1.6, 0.9, 0.9 }, color = MOTOR_GREY, material = "Plastic", studs = true, shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
	for k = 0, 5 do
		build(parent, origin, { name = "MotorFin", pos = { motorX, motorY, motorZ - 0.56 + k * 0.225 }, size = { 0.1, 1.06, 1.06 }, color = "64696E", material = "Plastic", studs = true, shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
	end
	build(parent, origin, { name = "MotorCap", pos = { motorX, motorY, motorZ + 0.9 }, size = { 0.28, 0.6, 0.6 }, color = "64696E", material = "Plastic", studs = true, shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
	build(parent, origin, { name = "MotorBox", pos = { motorX, motorY + 0.55, motorZ }, size = { 0.4, 0.3, 0.5 }, color = MOTOR_GREY, material = "Plastic", studs = true, canCollide = false })

	-- The flywheel on the motor's aisle end, turning (StationMotionController): a
	-- studded rim of segments round a hub, three spokes, one of them hazard yellow so
	-- the turn is visible. Its own Model so it spins as one about the shaft, streamed
	-- as a unit.
	local shaft = origin * CFrame.new(motorX, motorY, motorZ - 1.0)
	build(parent, shaft, { name = "FlywheelShaft", pos = { 0, 0, 0.1 }, size = { 0.3, 0.16, 0.16 }, color = METAL_LIGHT, material = "Metal", shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
	local flywheel = Instance.new("Model")
	flywheel.Name = "Flywheel"
	flywheel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- polygonRing lays its ring round its origin's Y axis; tip that axis onto the shaft.
	polygonRing(flywheel, shaft * Kit.ang(90, 0, 0), {
		name = "FlywheelRim",
		sides = 12,
		cx = 0,
		cz = 0,
		apothem = 0.48,
		thickness = 0.14,
		y = 0,
		height = 0.2,
		color = C.hazardBlack,
		studs = true,
		canCollide = false,
	})
	build(flywheel, shaft, { name = "FlywheelHub", pos = { 0, 0, 0 }, size = { 0.3, 0.3, 0.3 }, color = C.hazardBlack, material = "Plastic", studs = true, shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
	for k = 0, 2 do
		build(flywheel, shaft * Kit.ang(0, 0, k * 120), {
			name = "FlywheelSpoke",
			pos = { 0, 0.25, 0 },
			size = { 0.12, 0.44, 0.14 },
			color = if k == 0 then SPOKE_YELLOW else C.hazardBlack,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end
	flywheel.WorldPivot = shaft
	flywheel.Parent = parent
	Kit.motion(flywheel, { kind = "spin", axis = "Z", rate = 4 })


	-- THE DRUM IS THE ONLY THING THAT SAYS THE HOSE IS LONG. The Beam below draws exactly
	-- one span -- reel to nozzle -- and a hose that is only ever a few studs long is a
	-- shower attachment; a visibly wound drum is where the rest of it lives.
	--
	-- WIDEST PART FIRST, NOT FLANGES. A real reel's flanges are wider than the drum, but
	-- a Cylinder part cannot be a ring, so a wide flange is a SOLID disc that occludes
	-- the whole drum from the one angle the reel is legible from. So: the green drum is
	-- the widest thing, a darker band over it reads as wound coils, and a small steel
	-- hub caps each end -- what a spool of hose actually looks like face-on.
	local rx = px + 1.7
	local ry = T + 1.9
	local reel = build(parent, origin, {
		name = "HoseReel",
		pos = { rx, ry, pz },
		size = { 1.0, 2.1, 2.1 },
		color = C.hoseGreen,
		material = "SmoothPlastic",
		shape = "Cylinder",
		canCollide = false,
	})
	build(parent, origin, {
		name = "HoseCoil",
		pos = { rx, ry, pz },
		size = { 1.06, 1.6, 1.6 },
		color = C.hoseGreenDark,
		material = "SmoothPlastic",
		shape = "Cylinder",
		canCollide = false,
	})
	for _, side in { -0.55, 0.55 } do
		build(parent, origin, {
			name = "ReelHub",
			pos = { rx + side, ry, pz },
			size = { 0.16, 0.8, 0.8 },
			color = FIT,
			material = "Metal",
			shape = "Cylinder",
			canCollide = false,
		})
	end
	build(parent, origin, {
		name = "ReelAxle",
		pos = { px + 0.55, ry, pz },
		size = { 0.8, 0.3, 0.3 },
		color = FIT,
		material = "Metal",
		shape = "Cylinder",
		canCollide = false,
	})

	build(parent, origin, { name = "ReelPost", pos = { px + 0.15, (T + 0.7 + ry + 0.3) / 2, pz }, size = { 0.5, ry + 0.3 - (T + 0.7), 0.5 }, color = BODY, material = "Plastic", studs = true, canCollide = false })

	-- THE FEED LINE, reel to tank: down the reel post, along the deck past the mast's
	-- outside, a dog-leg round the flywheel, and into the tank's aisle face under the
	-- gauge -- so the hose on the drum visibly draws from the tank.
	do
		local fy, postX, turnZ = T + 0.95, px + 0.15, tz - 2
		local tankFace = tz - tankR
		local function run(name: string, a: Vector3, b: Vector3)
			local mid, len = (a + b) / 2, (b - a).Magnitude
			local along = if math.abs(b.X - a.X) > 0.01 then nil else CYL_ALONG_Z
			build(parent, origin, { name = name, pos = { mid.X, mid.Y, mid.Z }, size = { len, 0.4, 0.4 }, color = FIT, material = "Metal", shape = "Cylinder", rot = along, canCollide = false })
		end
		local p1, p2, p3, p4 = Vector3.new(postX, fy, pz + 0.3), Vector3.new(postX, fy, turnZ), Vector3.new(tx, fy, turnZ), Vector3.new(tx, fy, tankFace + 0.05)
		run("FeedPipe", p1, p2)
		run("FeedPipe", p2, p3)
		run("FeedPipe", p3, p4)
		for _, joint in { p2, p3 } do
			build(parent, origin, { name = "FeedElbow", pos = { joint.X, joint.Y, joint.Z }, size = { 0.55, 0.55, 0.55 }, color = FIT, material = "Metal", shape = "Ball", canCollide = false })
		end
		build(parent, origin, { name = "FeedFlange", pos = { tx, fy, tankFace - 0.05 }, size = { 0.14, 0.7, 0.7 }, color = FIT, material = "Metal", shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
	end

	-- Where the hose leaves the drum. Its FACING is load-bearing: a Beam's curve
	-- control point runs along the attachment's LookVector, so this aims down-and-
	-- toward-the-tub to throw the slack loop that way, not back behind the pump.
	local anchor = Instance.new("Attachment")
	anchor.Name = "HoseAnchor"
	anchor.CFrame = CFrame.lookAt(Vector3.new(0, -1.1, 0.9), Vector3.new(0, -1.75, 4.9))
	anchor.Parent = reel

	-- ── The plumbing ──────────────────────────────────────────
	-- A round pipe from the foot of the tank to the tub's front diagonal wall, on
	-- studded clamps, with a ball elbow at the turn and a flange where it goes in. It
	-- used to be a square conduit that ran on INTO the tub, to its centre line -- harmless
	-- while the tub was solid, a bar across the water now that it is not -- so it stops at
	-- the wall. `wallX` is where that wall's outer face crosses the pipe's line, and it
	-- follows TUB_SHELL rather than being a second copy of it.
	local pipeY = T + 0.95
	local wallX = cx - (TUB_SHELL.apothem + TUB_SHELL.wall / 2) - 0.1
	local tankSide = tx + tankR
	build(parent, origin, {
		name = "Conduit",
		pos = { (tankSide + wallX) / 2, pipeY, tz },
		size = { wallX - tankSide, 0.45, 0.45 },
		color = FIT,
		material = "Metal",
		shape = "Cylinder",
		canCollide = false,
	})
	build(parent, origin, { name = "ConduitFlange", pos = { wallX - 0.2, pipeY, tz }, size = { 0.16, 0.8, 0.8 }, color = FIT, material = "Metal", shape = "Cylinder", canCollide = false })

	-- ── The mast, and the monitor bolted to it ────────────────
	-- The nozzle is not something you pick up: it stands on its own mast and the player
	-- aims it from the mark, hands empty. Three constraints fence the mast into the
	-- tub's near-right corner -- OUT OF THE BATH (a mast inside the rims stands in the
	-- water), OFF THE WALK-UP (the player comes straight down the aisle to WashSpot),
	-- and RIGHT of the tub because the pump is already there, so the hose runs down one
	-- side of the deck past nothing rather than across the walk-up at ankle height.
	--
	-- The arc it was tuned for (WashController.jetPath) does NOT depend on this mast any
	-- more: WashController re-homes a per-viewer copy of the model to a point near the
	-- washing player's own camera for the session and parks this one back on
	-- `ParkedPivot` on exit. So the mast's whole job now is the at-rest look -- a
	-- bystander, or the same player before/after their wash, finding the machine parked
	-- here wearing whichever Cleaner rung its owner bought.
	local mx, mz = cx - 5, cz - 6
	local mountY = T + 5.0

	build(parent, origin, {
		name = "HoseMastFoot",
		pos = { mx, T + 0.5, mz },
		size = { 1.3, 0.7, 1.3 },
		color = BODY,
		material = "Plastic",
		studs = true,
	})
	-- Bottom on the foot, top at the mount, so length and centre both derive from
	-- mountY rather than being two numbers kept in sync by hand.
	local mastLen = mountY - (T + 0.8)
	build(parent, origin, {
		name = "HoseMast",
		pos = { mx, T + 0.8 + mastLen * 0.5, mz },
		size = { mastLen, 0.4, 0.4 },
		color = FIT,
		material = "Metal",
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		canCollide = false,
	})
	-- A ball joint is honest at every angle the nozzle swings through; a forked yoke is
	-- only right about one axis of that swing.
	build(parent, origin, {
		name = "HoseYoke",
		pos = { mx, mountY, mz },
		size = { 0.85, 0.85, 0.85 },
		color = FIT,
		material = "Metal",
		shape = "Ball",
		canCollide = false,
	})

	-- BUILT BY Shared/ToolModels/Hose. STATION_TIER is the unclaimed plot's hose;
	-- ExhibitService.refreshHose swaps it for the rung the owner actually bought.
	-- Parked aimed at WashStand -- `CFrame.lookAt` puts the target down -Z and -Z is
	-- the business end, so this one line is both the rest pose and what the local
	-- swivel returns to. Stamped as `ParkedPivot` because Plots.setHoseTier and
	-- WashController both need it and neither can re-derive it.
	local mount = origin * CFrame.new(mx, mountY, mz)
	local aimAt = origin * CFrame.new(cx, T + 3.5, cz)
	local parked = CFrame.lookAt(mount.Position, aimAt.Position)

	local hose = ToolModels.Hose.create(ToolModels.Hose.STATION_TIER)
	hose:PivotTo(parked)
	hose:SetAttribute("ParkedPivot", parked)

	local core = hose.PrimaryPart :: BasePart
	local hoseEnd = core:FindFirstChild("HoseEnd") :: Attachment

	-- Darker at both ends than the middle: a Beam is a camera-facing ribbon and cannot
	-- shade itself, but a lighter centre band reads as a round tube catching the sky.
	local beam = Instance.new("Beam")
	beam.Name = "HoseLine"
	beam.Attachment0 = anchor
	beam.Attachment1 = hoseEnd
	beam.Width0 = 0.7
	beam.Width1 = 0.55
	-- Slack, not tension: positive out of the reel throws the loop the way HoseAnchor
	-- is aimed; negative into the nozzle throws the far control point BACKWARD from
	-- HoseEnd, so the line arrives from behind the monitor, not curling round its front.
	beam.CurveSize0 = 1.6
	beam.CurveSize1 = -1.0
	beam.Segments = 20
	beam.FaceCamera = true
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex(C.hoseGreenDark)),
		ColorSequenceKeypoint.new(0.5, Color3.fromHex(C.hoseGreen)),
		ColorSequenceKeypoint.new(1, Color3.fromHex(C.hoseGreenDark)),
	})
	beam.Transparency = NumberSequence.new(0)
	beam.LightInfluence = 1
	beam.Parent = reel

	hose.Parent = parent

	-- The drum, coil and line above were painted the jade they were first drawn in.
	-- Repaint them to the station rung's own colours (ToolTiers.Cleaner), which is what
	-- Plots.setHoseTier does on every purchase, so an unclaimed plot's rig already
	-- matches the nozzle on its mast instead of only after somebody buys one.
	paintHoseRig(parent, ToolModels.Hose.STATION_TIER)
end

--- Swap the monitor on one cleansing station's mast to `tier`, in place. Returns the
--- hose now on it, or nil if this station has no rig to swap (a place file saved
--- before the mast existed — degrade quietly, exactly as the wash bay does).
---
--- A NIL TIER MEANS "UNCLAIMED": it puts back the same STATION_TIER a freshly built
--- plot wears, which is what ExhibitService hands it when a player leaves and the base
--- goes back to belonging to nobody. Spelled as a default rather than as a separate
--- `clearHose()`, because the two would be the same six lines and the second one is
--- the one that rots.
---
--- THIS IS WHERE THE PURCHASE LANDS. The Cleaner track is bought at the plaza's HOSES
--- stall like every other track, and this is what makes that purchase a thing you can
--- see: ExhibitService.refreshHose calls it on plot assignment and again on every buy,
--- so walking home from the stall means finding a different machine on your own mast.
---
--- REBUILT RATHER THAN RECOLOURED. The seven rungs are seven authored silhouettes
--- (Shared/ToolModels/Hose), not one model in seven paints, so there is nothing to
--- tint — and the factory is the same one build/Shops hangs on the rack and the same
--- one this file parks at build time. One geometry, three surfaces, no drift.
---
--- ORDER MATTERS AT EXACTLY ONE POINT: the new hose is parented and the reel's Beam is
--- swung onto it BEFORE the old one is destroyed. A Beam whose Attachment1 has just
--- been freed draws nothing, and a hose line that blinks out on every purchase is a
--- bug someone reports.
function Plots.setHoseTier(station: Instance?, tier: number?): Model?
	if station == nil then
		return nil
	end

	local existing = station:FindFirstChild("Hose")
	local parked = if existing then existing:GetAttribute("ParkedPivot") else nil
	if typeof(parked) ~= "CFrame" and existing and existing:IsA("Model") and existing.PrimaryPart ~= nil then
		-- A rig built before ParkedPivot was stamped on. Where it stands right now IS
		-- where it parks, so read it off rather than refusing the swap.
		parked = existing:GetPivot()
	end
	if typeof(parked) ~= "CFrame" then
		return nil
	end

	-- Clamped the way the factory clamps, so the comparison below is against the rung
	-- that would actually be built rather than against the caller's raw number.
	local wanted = math.clamp(math.floor(tier or ToolModels.Hose.STATION_TIER), 1, ToolModels.Hose.count())
	if existing and existing:GetAttribute("Tier") == wanted then
		return existing :: Model
	end

	local hose = ToolModels.Hose.create(wanted)
	hose:PivotTo(parked)
	hose:SetAttribute("ParkedPivot", parked)
	-- The rung's ambient effects (Toxic Twilight's hoses have them), the same ones the
	-- shop rack shows. Runtime, like the rest of this swap, so no rebuild carries it.
	ToolFX.apply(hose, "Cleaner", wanted)
	hose.Parent = station

	local reel = station:FindFirstChild("HoseReel")
	local line = if reel then reel:FindFirstChildOfClass("Beam") else nil
	local core = hose.PrimaryPart
	local hoseEnd = if core then core:FindFirstChild("HoseEnd") else nil
	if line and hoseEnd and hoseEnd:IsA("Attachment") then
		line.Attachment1 = hoseEnd
	end

	-- The reel, the coil wound on it and the Beam are one prop that was built green at
	-- STATION_TIER -- follow the nozzle so the whole hose reads as the rung you bought.
	paintHoseRig(station, wanted)

	if existing then
		existing:Destroy()
	end
	return hose
end

--- Repaint every accent piece on one plot to `color` — the two side `Trim` strips,
--- the cleansing-station `Lamp` (and its `PointLight`), the `CLEANSING STATION` /
--- `WASH PAD` sign subtitles, the avatar plate's `Ring` (buildNamePlate), and the
--- gallery's pieces: the arch caps and stripe, every plinth band, every fence-post cap
--- and the empty-slot bracket Frames.
---
--- A NIL COLOUR MEANS "UNCLAIMED": it puts back `C.plotNeutral`, the grey a freshly
--- built plot wears — what ExhibitService hands it when a player leaves. Spelled as a
--- default rather than a separate `clearAccent()`, same reasoning as setHoseTier above.
---
--- TAG-DRIVEN, NOT NAME-DRIVEN. buildPlot stamps `Accent` on the parts and
--- accentBillboard/buildNamePlate stamp it on their labels and stroke, so this is the
--- same "geometry is build-time, skin is runtime" split setHoseTier uses: a service
--- that needs to recolour plot geometry asks this module rather than learning part
--- names. The lamp's `PointLight` has no attribute of its own — it is matched by its
--- parent carrying `Accent`.
function Plots.setPlotAccent(plot: Instance?, color: Color3?)
	if plot == nil then
		return
	end
	local paint = color or Color3.fromHex(C.plotNeutral)
	for _, d in plot:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("Accent") then
				d.Color = paint
			end
		elseif d:IsA("PointLight") then
			local host = d.Parent
			if host and host:IsA("BasePart") and host:GetAttribute("Accent") then
				d.Color = paint
			end
		elseif d:IsA("TextLabel") then
			if d:GetAttribute("Accent") then
				d.TextColor3 = paint
			end
		elseif d:IsA("Frame") then
			-- The gallery's empty-slot brackets (buildSlotMarker).
			if d:GetAttribute("Accent") then
				d.BackgroundColor3 = paint
			end
		elseif d:IsA("UIStroke") and d:GetAttribute("Accent") then
			d.Color = paint
		end
	end
end

--- The cleansing station — replaces the camp's old central Decon Station and
--- Decon Shower with one combined stop on EVERY base, per the request. A single
--- part carries BOTH `StationKind = "decon"` (freezes carried items' decay
--- clocks and lets you scrub, exactly like the old camp station) AND
--- `Shower = true` (flushes your own exposure, exactly like the old camp
--- shower). The two systems already read their attributes independently —
--- DeconService only cares whether `StationKind` is set, ExposureService only
--- cares whether `Shower` is `true` — so nothing stops one part being both, and
--- putting both on one part means "clean my loot" and "clean myself" happen in
--- the same spot instead of two separate structures at camp. They share one
--- `Radius`, which is fine: it's the same "how close do I need to be" question
--- either way.
---
--- Walk home from the field, dock here, then rack the clean item on a pedestal —
--- no trip back to base camp required, and every player's loop remains local.
---
--- The whole bay now sits on the left side of the entrance extension. Its tub is
--- forward of the final stand row (z = -6, the grid's front row), well clear of
--- it, while its pump reaches almost to the front edge. That keeps the display
--- floor and the entrance strip reading together as one service strip.
local function buildCleansingStation(parent: Instance, origin: CFrame, accent: string)
	local m = Instance.new("Model")
	m.Name = "CleansingStation"
	local pad = Plots.PAD
	local T = pad.topY
	-- Positive local X is the player's LEFT when approaching from local -Z and
	-- facing the back wall, because Roblox's look direction uses -Z.
	local cx, cz = 18, -32

	-- TURNED A QUARTER-TURN so the whole rig backs onto the +X side border rather than
	-- standing across the service strip. Applied to `origin` about the bay's own centre
	-- so every part below stays written in the bay's local space and buildHoseRig,
	-- WashSpot and WashCam all turn with it as one assembly. The leading +X shift
	-- (plot-local, before the pivot) slides it outward to sit inside the +X accent trim.
	origin = origin
		* CFrame.new(8, 0, 0)
		* CFrame.new(cx, 0, cz)
		* CFrame.Angles(0, math.rad(90), 0)
		* CFrame.new(-cx, 0, -cz)

	-- REBUILT BIGGER AND IN STUD MATERIAL, on request. The bay used to be thin steel
	-- rims and a bare slab that read as a table; it is a heavy decontamination bay now,
	-- built out of the same studded blocks as the display plinths and the fence so
	-- it belongs to the base. `BODY` is the base-course grey, `FACE` the lighter cap
	-- grey (the display-plinth pair), `LINER` the dark of the drain, `FIT` the smooth
	-- metal of the pipework. Hose stays jade, water stays cyan.
	--
	-- THE TUB IS WHITE, and that is the point of it. It used to be the same grey as
	-- the deck, the gantry, the fence and every plinth on the plot, so the one object
	-- you come here to use melted into everything round it. `TUB_WALL`/`TUB_TOP` are a
	-- porcelain pair (walls a shade under the lip, so it reads as lit from above),
	-- `TUB_POST` the corner pillars, `TUB_TILE` the pale pool-blue of the inside.
	--
	-- THE WASH MINIGAME GEOMETRY DID NOT MOVE. WashStand (the item point), WashSpot
	-- (where WashService plants the player) and WashCam (WashController's fallback) keep
	-- the exact offsets the previous bay had, and the tub grew around them, not through
	-- them -- so nothing about the first-person shot, the aim, or the placement changed.
	local BODY, FACE, LINER, FIT = C.standGreyDark, C.standGrey, C.drain, C.steelDark
	local TUB_WALL, TUB_TOP, TUB_POST, TUB_TILE = "DCE3E8", "F2F5F7", "AEB8C0", "9ED6E3"

	-- ── The deck ──────────────────────────────────────────────
	-- One studded plate the whole installation stands on, kerbed round the edge, so the
	-- bay is a unit set into the strip and not parts scattered on the tiles. Top a
	-- hair proud of the floor -- a threshold, not a step: WashService plants the player
	-- just off its front edge, so nothing here changes the height they stand at.
	build(m, origin, { name = "Deck", pos = { 17.125, T - 0.35, -32 }, size = { 16.75, 1.0, 10 }, color = BODY, material = "Plastic", studs = true })
	-- The side kerbs stop short of the back kerb and the hazard line (9.4, not 10.6) so no
	-- corner is two bricks fighting over the same spot; the hazard line owns the whole front.
	for _, e in {
		{ x = 17.125, z = -27, sx = 17.35, sz = 0.6 },
		{ x = 25.5, z = -32, sx = 0.6, sz = 9.4 },
		{ x = 8.75, z = -32, sx = 0.6, sz = 9.4 },
	} do
		build(m, origin, { name = "DeckKerb", pos = { e.x, T + 0.25, e.z }, size = { e.sx, 0.35, e.sz }, color = FACE, material = "Plastic", studs = true, canCollide = false })
	end
	-- The front kerb -- the edge you walk over to reach the wash mark -- is hazard-striped:
	-- studded yellow and black bricks, the toy-brick version of the tape round a real
	-- decontamination bay, and the first thing on the plot that says what this bay is for.
	local STRIPES = 14
	local stripeW = 17.35 / STRIPES
	for s = 0, STRIPES - 1 do
		build(m, origin, {
			name = "DeckKerb",
			pos = { 17.125 - 17.35 / 2 + (s + 0.5) * stripeW, T + 0.25, -37 },
			size = { stripeW, 0.35, 0.6 },
			color = if s % 2 == 0 then C.hazard else C.hazardBlack,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end

	-- ── The tub ───────────────────────────────────────────────
	-- AN OCTAGON, AND HOLLOW. It was a solid 7.4 x 3 x 7 studded block with the liner,
	-- the water and the drain all sealed INSIDE it: the block's top sat 0.45 above the
	-- liner's and 0.7 above the water's, so for its whole life this "deep tub" was a flat
	-- studded lid with a rim round it, and a ray straight down anywhere off the rack
	-- landed on Basin. Found by raycasting it, not by reading this code, which described
	-- a recess nobody could ever see. Now eight studded walls stand round a real well,
	-- and the water you wash over is water you can see.
	--
	-- THE DOCK + THE FLUSH IS STILL ONE PART, AT THE SAME CENTRE: StationKind="decon" is
	-- what DeconService matches on, Shower=true what ExposureService scans for, and the
	-- "Wash" prompt hangs off it. Every service reads its Position and Radius and nothing
	-- reads its Size, so it became the tub's FLOOR -- a round studded plate centred
	-- exactly where the solid block was, its top the bottom of the well. Round, not
	-- octagonal, because a Cylinder is one part; its edge tucks under the walls all round.
	local floorTop, wallTop = T + 0.65, T + 1.8
	local wallMid, wallH = (T + 0.15 + wallTop) / 2, wallTop - (T + 0.15)
	local tubInner = TUB_SHELL.apothem - TUB_SHELL.wall / 2
	local basin = build(m, origin, {
		name = "Basin",
		pos = { cx, T + 0.55, cz },
		size = { 0.2, 7.0, 7.0 },
		color = TUB_TILE,
		material = "Plastic",
		studs = true,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		attributes = { StationKind = "decon", Shower = true, Radius = 9 },
	})

	polygonRing(m, origin, {
		name = "TubWall",
		sides = TUB_SHELL.sides,
		cx = cx,
		cz = cz,
		apothem = TUB_SHELL.apothem,
		thickness = TUB_SHELL.wall,
		y = wallMid,
		height = wallH,
		color = TUB_WALL,
		studs = true,
	})
	-- The lining: pale studded panels on every inside face, floor to lip, so what you
	-- look down into is a pool and not the back of the outside wall.
	polygonRing(m, origin, {
		name = "TubLiner",
		sides = TUB_SHELL.sides,
		cx = cx,
		cz = cz,
		apothem = tubInner - 0.05,
		thickness = 0.1,
		y = (floorTop + wallTop) / 2,
		height = wallTop - floorTop,
		color = TUB_TILE,
		studs = true,
		canCollide = false,
	})
	-- A round studded pillar on every outside corner, deck to lip, so the octagon's
	-- corners read as posts the walls are set between rather than as two boxes meeting.
	for i = 0, TUB_SHELL.sides - 1 do
		local vx, vz = ringVertex(TUB_SHELL.sides, cx, cz, TUB_SHELL.apothem + TUB_SHELL.wall / 2, i)
		build(m, origin, {
			name = "TubPillar",
			pos = { vx, wallMid, vz },
			size = { wallH, 0.7, 0.7 },
			color = TUB_POST,
			material = "Plastic",
			studs = true,
			shape = "Cylinder",
			rot = Kit.R.cylUp,
		})
	end

	-- A wide flat rim lip capping the walls -- eight studded bars, tops at T+2.3, a shade
	-- under the old rims' T+2.6 so the stream still clears them from the player's side
	-- and the item still sits proud of them. Flush with the lining inside, a little proud
	-- of the walls outside.
	local RIM_APOTHEM = 3.7
	polygonRing(m, origin, {
		name = "TubRim",
		sides = TUB_SHELL.sides,
		cx = cx,
		cz = cz,
		apothem = RIM_APOTHEM,
		thickness = 1.0,
		y = T + 2.05,
		height = 0.5,
		color = TUB_TOP,
		studs = true,
		canCollide = false,
	})
	-- Flat bolt heads on the lip's corners. FLAT ON PURPOSE: the crusted lump sits on the
	-- rack only half a stud above the lip, and slides up to 1.2 toward the player, so a
	-- rounded cap here would be the first thing a big roll grazed (crust-fills-the-wash-bay).
	for i = 0, TUB_SHELL.sides - 1 do
		local vx, vz = ringVertex(TUB_SHELL.sides, cx, cz, RIM_APOTHEM, i)
		build(m, origin, {
			name = "TubBolt",
			pos = { vx, T + 2.375, vz },
			size = { 0.15, 0.45, 0.45 },
			color = FIT,
			material = "Metal",
			shape = "Cylinder",
			rot = Kit.R.cylUp,
			canCollide = false,
		})
	end

	-- The water: a translucent round body filling the well to two-thirds, with a fainter
	-- sheen disc on top -- one flat glass slab reads as a lid, two layers reads as depth.
	-- Wide enough that its edge is buried in the walls, so no dry corner shows. Not
	-- solid: a player who jumps in stands on the floor, not on the surface.
	local waterTop = T + 1.45
	build(m, origin, {
		name = "Water",
		pos = { cx, (floorTop + waterTop) / 2, cz },
		size = { waterTop - floorTop, 6.9, 6.9 },
		color = C.cyan,
		material = "Glass",
		transparency = 0.3,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		canCollide = false,
	})
	local sheen = build(m, origin, {
		name = "WaterSheen",
		pos = { cx, waterTop + 0.03, cz },
		size = { 0.06, 6.9, 6.9 },
		color = C.glass,
		material = "SmoothPlastic",
		transparency = 0.55,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		canCollide = false,
	})
	sheen.Reflectance = 0.05

	-- Rings spreading across the surface, drawn on a SurfaceGui lying just over the water
	-- (StationMotionController). A GUI rather than parts because a ring is an outline, and
	-- a Cylinder part can only be a solid disc.
	local ripples = carrier(m, origin, "WaterRipples", { cx, waterTop + 0.08, cz }, { 6.2, 0.02, 6.2 })
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Ripples"
	surface.Face = Enum.NormalId.Top
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.MaxDistance = 90
	surface.ClipsDescendants = true
	surface.Parent = ripples
	Kit.motion(ripples, { kind = "ripples" })

	-- A grated drain in the floor, off to one side of the rack's post, just visible under
	-- the water, so the tub has an outfall and is not a sealed tank.
	local drainX, drainZ = cx - 1.8, cz + 1.4
	build(m, origin, { name = "Drain", pos = { drainX, floorTop + 0.03, drainZ }, size = { 0.06, 1.1, 1.1 }, color = LINER, material = "Metal", shape = "Cylinder", rot = Kit.R.cylUp, canCollide = false })
	for _, r in { Kit.R.cylAlongX, CYL_ALONG_Z } do
		build(m, origin, { name = "DrainBar", pos = { drainX, floorTop + 0.08, drainZ }, size = { 1.0, 0.1, 0.1 }, color = FIT, material = "Metal", shape = "Cylinder", rot = r, canCollide = false })
	end

	-- ── The item rack and the three shot anchors ──────────────
	-- WashRack lifts the item clear of the rim so water from the side reaches it. It
	-- used to sit on the solid block's top; with the tub hollow it stands on a studded
	-- post up out of the water, under a metal collar. The three anchors are UNCHANGED
	-- from the previous bay -- WashService seats the item on the rack, plants the player
	-- a step forward of WashSpot, and WashController falls back to WashCam for the frame
	-- a respawn leaves the head missing. Framing is judged by looking, so these stay
	-- anchors, not numbers.
	local collarY = T + 2.525
	build(m, origin, {
		name = "RackPost",
		pos = { cx, (floorTop + collarY - 0.05) / 2, cz },
		size = { collarY - 0.05 - floorTop, 1.0, 1.0 },
		color = TUB_POST,
		material = "Plastic",
		studs = true,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		canCollide = false,
	})
	build(m, origin, { name = "RackCollar", pos = { cx, collarY, cz }, size = { 0.1, 1.9, 1.9 }, color = FIT, material = "Metal", shape = "Cylinder", rot = Kit.R.cylUp, canCollide = false })
	build(m, origin, {
		name = "WashRack",
		pos = { cx, T + 2.7, cz },
		size = { 2.8, 0.25, 2.8 },
		color = FACE,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})

	local stand = build(m, origin, {
		name = "WashStand",
		pos = { cx, T + 3.5, cz },
		size = { 1, 1, 1 },
		color = C.steel,
		material = "Metal",
		transparency = 1,
		canCollide = false,
	})
	stand:SetAttribute("IsWashStand", true)

	local spot = build(m, origin, {
		name = "WashSpot",
		pos = { cx, T + 3, cz - 6 },
		size = { 1, 1, 1 },
		color = C.steel,
		material = "Metal",
		transparency = 1,
		canCollide = false,
	})
	-- Faces the stand, so WashService can drop the character straight onto this CFrame
	-- and have them looking at what they are about to hose.
	spot.CFrame = origin
		* CFrame.lookAt(Vector3.new(cx, T + 3, cz - 6), Vector3.new(cx, T + 3, cz))

	local cam = build(m, origin, {
		name = "WashCam",
		pos = { cx - 13, T + 5, cz - 3 },
		size = { 1, 1, 1 },
		color = C.steel,
		material = "Metal",
		transparency = 1,
		canCollide = false,
	})
	-- Side-on fallback only: the wash is first person from the character's own head
	-- (WashController), and this is read for the one frame a mid-session respawn leaves
	-- the head missing. Composed with CFrame.lookAt rather than a fixed `rot` because
	-- "point at that" stops being a fixed angle once the plot's own yaw is applied.
	cam.CFrame = origin
		* CFrame.lookAt(
			Vector3.new(cx - 13, T + 5, cz - 3),
			Vector3.new(cx, T + 3.6, cz - 3)
		)

	-- PRESS E TO WASH, AND PRESS IT AGAIN TO STOP. Always enabled -- a ProximityPrompt
	-- is one shared instance -- so "are you holding something dirty" is the server's
	-- test on trigger, answered with a toast. The re-press matters: the player is
	-- pinned during a wash, so walking out is exactly what they cannot do.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Wash"
	prompt.ActionText = "Wash"
	prompt.ObjectText = "Cleansing Station"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = basin

	-- ── The gantry + back wall, one structure ─────────────────
	-- Two heavy studded posts on the +X (back) side, a panelled wall filling the gap
	-- between them so the bay backs onto something solid, and a boxed header across the
	-- top. The FRONT of the tub is left open -- nothing between the player and the basin
	-- -- so the frame looms behind the wash rather than caging it.
	--
	-- NOTHING REACHES OVER THE TUB ANY MORE. There used to be an arm cantilevered
	-- forward off this header to the tub centre, braced with a gusset at each post, and
	-- its only job was carrying the shower head. The head is gone (see the tub's water
	-- below) and the arm went with it -- not merely because it was orphaned, but because
	-- it had the head's own defect: its underside sits 2.2 studs over WashStand and the
	-- crust on seven of the fourteen authored items reaches higher than that, the
	-- tallest of them standing 1.2 studs proud of the beam's TOP. Everything overhead is
	-- now behind the tub's back rim, where the widest crust measured still clears it by
	-- most of a stud.
	local GANTRY_TOP = T + 6.2
	local POST_Z = -28.2 -- authored; plot x ~= 29.8, just behind the tub's far rim
	for _, ax in { 14, 22 } do
		build(m, origin, { name = "GantryFoot", pos = { ax, T + 0.35, POST_Z }, size = { 1.4, 0.5, 1.4 }, color = FACE, material = "Plastic", studs = true })
		build(m, origin, {
			name = "GantryPost",
			pos = { ax, (T + 0.15 + GANTRY_TOP) * 0.5, POST_Z },
			size = { 1.1, GANTRY_TOP - (T + 0.15), 1.1 },
			color = BODY,
			material = "Plastic",
			studs = true,
		})
	end
	-- The wall between the posts: a base course and a lighter upper course.
	build(m, origin, { name = "SplashWall", pos = { 18, T + 1.6, POST_Z }, size = { 7.6, 3.0, 0.7 }, color = BODY, material = "Plastic", studs = true })
	build(m, origin, { name = "SplashWall", pos = { 18, T + 4.4, POST_Z }, size = { 7.6, 2.4, 0.5 }, color = FACE, material = "Plastic", studs = true })
	-- A boxed header across the post tops, capping the wall and carrying the sign.
	build(m, origin, { name = "GantryBeam", pos = { 18, GANTRY_TOP, POST_Z }, size = { 9.0, 1.0, 1.2 }, color = FACE, material = "Plastic", studs = true, canCollide = false })

	-- ── The tub's own water ───────────────────────────────────
	-- THERE IS NO SHOWER HEAD ANY MORE, and that is a measurement rather than a taste.
	-- A dug item arrives encased in slag (Shared/ItemCrust) and the crust is SIZED OFF
	-- THE ITEM, so what sits on the rack is a lump two to five studs across: measured
	-- over every authored item, it reaches up to 4.4 studs above WashStand and 2.5
	-- studs back from it. The head hung on a drop pipe with its underside 1.05 studs
	-- over the stand, and ten of the fourteen items pushed straight through it.
	--
	-- RAISING IT DOES NOT FIX IT, which is why this is a deletion and not a nudge. The
	-- gantry arm's own underside is 2.7 studs over the stand, so no height under the arm
	-- clears the tall items; the crust very nearly fills the basin, so no position over
	-- it clears the wide ones. Anything solid hung above the rack is something the next
	-- item will wear.
	--
	-- THE OVERHEAD WATER WENT WITH IT, on the minigame's terms rather than the prop's. A
	-- curtain falling down the middle of the shot is the one thing this wash cannot
	-- afford: the player is aiming a hose at crust a couple of studs across, and a
	-- second stream between the lens and the target competes with their own for the only
	-- thing they are being asked to read. The rinse is theirs alone now.
	--
	-- WHAT IS LEFT IS THE WATER ALREADY IN THE TUB -- a slow churn turning over the
	-- drain, which says the bay is live without putting anything between the player and
	-- the thing they came here to clean. Particles, not geometry, for the reason the
	-- stream always was: a particle animates itself, so a static prop reads as running
	-- with no per-frame script anywhere. Matte like everything out here (Kit's palette
	-- header) -- LightEmission stays a fraction, no PointLight; the fallout is the only
	-- thing on a plot that glows.
	-- Sat on the water's surface. It was at T+1.45 inside the old solid block, where
	-- nothing it threw could ever be seen.
	local churnHost = carrier(m, origin, "TubChurn", { cx, T + 1.5, cz }, { 3.8, 0.1, 3.2 })
	local churn = Instance.new("ParticleEmitter")
	churn.Name = "Churn"
	churn.Texture = "rbxasset://textures/particles/smoke_main.dds"
	churn.Color = ColorSequence.new(Color3.fromHex("F4FAFF"))
	churn.LightEmission = 0.04
	churn.LightInfluence = 1
	churn.EmissionDirection = Enum.NormalId.Top
	-- A SIMMER, NOT A SPLASH. The old numbers were an impact ring under a falling
	-- column: fast, wide, and thrown clear of the rim. With nothing landing on it the
	-- surface is only turning over, so rate, speed and spread all come down and the
	-- drops stay inside the tub instead of arcing out over the deck.
	churn.Rate = 26
	churn.Lifetime = NumberRange.new(0.4, 0.75)
	churn.Speed = NumberRange.new(1.2, 2.6)
	churn.SpreadAngle = Vector2.new(34, 34)
	churn.Acceleration = Vector3.new(0, -12, 0)
	churn.Squash = NumberSequence.new(1.1)
	churn.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.07),
		NumberSequenceKeypoint.new(0.4, 0.16),
		NumberSequenceKeypoint.new(1, 0),
	})
	churn.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.62),
		NumberSequenceKeypoint.new(1, 1),
	})
	churn.Parent = churnHost

	-- The station sign rides the gantry header (the back wall itself is built up in the
	-- gantry section above). The accent lamp is a ball on the header end with a soft
	-- PointLight -- the one coloured light on the plot, kept low; `Accent` tags the ball
	-- and Plots.setPlotAccent repaints it and the light from `data.plotColor`.
	-- No floating title over it: the station's prompt names it up close.
	build(m, origin, { name = "SignHost", pos = { 18, GANTRY_TOP + 0.7, POST_Z }, size = { 9.0, 0.4, 1.0 }, color = FACE, material = "Plastic", studs = true, canCollide = false })

	local lamp = build(m, origin, {
		name = "Lamp",
		pos = { cx + 4.4, GANTRY_TOP, POST_Z },
		size = { 0.7, 0.7, 0.7 },
		color = accent,
		material = "SmoothPlastic",
		shape = "Ball",
		canCollide = false,
		attributes = { Accent = true },
	})
	-- No shadows: a small accent glow on the header has nothing to throw them onto
	-- that the sun has not already shaded, and shadow casting is a PointLight's cost.
	light(lamp, accent, 14, 0.9, false)

	buildHoseRig(m, origin, cx, cz)

	m.Parent = parent
end

--- EXPORTED FOR build/CampSite, which stands one shared cleansing station in each site
--- camp. Nothing in here is tied to a plot: the Basin's decon/shower attributes, the
--- Wash prompt WashService wires by tag, WashStand/WashSpot/WashCam and the hose's
--- ParkedPivot are all found by what they carry, not by which plot holds them. Only
--- ExhibitService.refreshHose is plot-bound (it swaps the rung on an OWNED plot), so a
--- camp station keeps the ToolModels.Hose.STATION_TIER rung it was built with -- and
--- washing there still uses the washer's own Cleaner stats (WashService's header).
---
--- `origin` is a PLOT origin (Y = 0, the pad's own top is Plots.PAD.topY): the bay's
--- centre lands at origin * (26, 0, -32), turned a quarter-turn -- see the top of the
--- function for that pivot.
Plots.buildCleansingStation = buildCleansingStation

--- The fluid bottle — a glass bottle on a table beside the tub, full of whatever
--- fluid its owner has loaded in the hose (Config/Liquids, Services/LiquidService).
---
--- IT REPLACED THE WASH PAD, on request. The pad was a step-on pressure plate across
--- the aisle that charged a fee per roll and flashed its result on its own sign; the
--- user wanted the mechanic simpler and next to the tub it feeds. So the liquid now
--- lives in one object you can read from across the base -- the colour in the bottle
--- IS the loaded fluid -- and pressing E on it opens a spin on your screen
--- (LiquidController) that lands on a fluid. When the spin lands, the bottle
--- recolours (LiquidService delays the repaint until then).
---
--- FREE, ON A COOLDOWN. Tuning.LIQUID_SPIN_COOLDOWN is the only limiter now; there
--- is no fee and no first-roll-free special case. While it runs, the prompt's own
--- ActionText counts down, so the answer to "why won't it spin" is on the bottle.
---
--- RIGHT NEXT TO THE TUB, on the player's LEFT (moved on request; the pump tank
--- took its old spot on the right). The table stands off the tub's -Z flat face, a few tenths of a stud off it, so tub and
--- bottle read as one station. That side is free: the gantry posts are at x ~= 30,
--- the hose rig and pump are off the -Z end, and the player washes from the -X side
--- (WashSpot, plot (20, -32)). Nothing reaches over the tub (crust-fills-the-wash-bay).
--- Round, so it needs no pivot: every part below is written straight in plot space.
---
--- NO PROMPT BUILT HERE. LiquidController hangs a local "View" E prompt on your own
--- bottle, which opens the fluid panel on your screen: the loaded fluid, BREW, and
--- the Luck upgrade. The tub's "Wash" E prompt is the only built prompt here. The reach
--- is kept short (LiquidController's PANEL_REACH) so the wash spot, plot (20, -32),
--- is well outside it.
local BOTTLE = {
	x = 26,
	z = -37.9,
}

local function buildFluidBottle(parent: Instance, origin: CFrame)
	local m = Instance.new("Model")
	m.Name = "FluidBottle"
	local T = Plots.PAD.topY
	local bx, bz = BOTTLE.x, BOTTLE.z
	local BODY, FACE, FIT = C.standGreyDark, C.standGrey, C.steelDark
	local water = Liquids.get(Liquids.WATER).color

	-- ON A TABLE AT THE TUB'S OWN HEIGHT, on request. The tabletop's surface is level
	-- with the tub's rim (T + 2.3, see TubRim in buildCleansingStation), so the bottle
	-- and the wash read as one bench-height station rather than a bottle on the floor
	-- beside a raised machine. Studded, in the display plinths' pair of greys: a thick
	-- top on four square legs.
	local TOP_Y = T + 2.3
	local TOP_W, TOP_H, LEG_W = 2.8, 0.4, 0.45
	build(m, origin, { name = "TableTop", pos = { bx, TOP_Y - TOP_H / 2, bz }, size = { TOP_W, TOP_H, TOP_W }, color = FACE, material = "Plastic", studs = true })
	local legH = TOP_Y - TOP_H - T
	local legOff = TOP_W / 2 - LEG_W / 2 - 0.15
	for _, corner in { { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } } do
		build(m, origin, {
			name = "TableLeg",
			pos = { bx + corner[1] * legOff, T + legH / 2, bz + corner[2] * legOff },
			size = { LEG_W, legH, LEG_W },
			color = BODY,
			material = "Plastic",
			studs = true,
		})
	end
	-- A low stretcher between the legs, so the table stands braced rather than on stilts.
	build(m, origin, { name = "TableShelf", pos = { bx, T + 0.55, bz }, size = { TOP_W - 0.5, 0.2, TOP_W - 0.5 }, color = BODY, material = "Plastic", studs = true, canCollide = false })

	-- SMALLER, on request (twice): the bottle is the original one scaled by S, so every
	-- proportion (fill, shoulder, neck, cap) is kept and only the size changes. `at(v)`
	-- is a height in the original full-size bottle's units above the tabletop.
	local S = 0.4
	local baseY = TOP_Y
	local function at(v: number): number
		return baseY + v * S
	end

	-- The fluid: near-opaque and filling most of the body, so its colour carries from
	-- across the base. Deliberately matte with a faint light -- nuke FX are the only
	-- thing on a base allowed to glow (nuke-fx-neon-exception). Plots.setFluidBottle
	-- repaints every part named `Liquid` and its light.
	local fill = build(m, origin, {
		name = "Liquid",
		pos = { bx, at(0.1 + 1.65), bz },
		size = { 3.3 * S, 2.7 * S, 2.7 * S },
		color = water,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		transparency = 0.05,
		canCollide = false,
	})
	light(fill, water, 5, 0.35, false)

	-- The glass: a near-clear neutral, NOT C.glass, whose blue tint would shift the
	-- colour you came to read (the same call the wash pad's specimen jars made).
	local GLASS = "F1F1F2"
	local function glass(name: string, pos: { number }, size: { number }, shape: string?, attributes: { [string]: any }?): BasePart
		local part = build(m, origin, {
			name = name,
			pos = pos,
			size = size,
			color = GLASS,
			material = "SmoothPlastic",
			shape = shape,
			rot = if shape == "Cylinder" then Kit.R.cylUp else nil,
			transparency = 0.58,
			canCollide = attributes ~= nil,
			attributes = attributes,
		})
		part.Reflectance = 0.06
		return part
	end

	-- The body is the one glass part you bump into, and the one the panel measures to.
	-- `SpinsFluid` is what Kit.build tags it FLUID_TAG by.
	glass("Bottle", { bx, at(1.95), bz }, { 3.9 * S, 3.2 * S, 3.2 * S }, "Cylinder", { SpinsFluid = true })

	-- Shouldered into a neck, so it reads as a bottle and not a tin can: a squashed
	-- sphere mesh, since a Ball part can only be round (roblox-cylinder-ball-no-ellipse).
	local shoulder = glass("BottleShoulder", { bx, at(3.9), bz }, { 1, 1, 1 })
	local dome = Instance.new("SpecialMesh")
	dome.MeshType = Enum.MeshType.Sphere
	dome.Scale = Vector3.new(3.2 * S, 1.3 * S, 3.2 * S)
	dome.Parent = shoulder
	glass("BottleNeck", { bx, at(4.6), bz }, { 1.1 * S, 1.2 * S, 1.2 * S }, "Cylinder")

	-- A studded cap, so the one solid thing up top belongs to the base's brick kit.
	build(m, origin, {
		name = "BottleCap",
		pos = { bx, at(5.35), bz },
		size = { 0.6 * S, 1.5 * S, 1.5 * S },
		color = FIT,
		material = "Plastic",
		studs = true,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		canCollide = false,
	})
	build(m, origin, {
		name = "BottleCapTop",
		pos = { bx, at(5.77), bz },
		size = { 0.25 * S, 1.0 * S, 1.0 * S },
		color = FIT,
		material = "Plastic",
		studs = true,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		canCollide = false,
	})

	-- Bubbles rising through the fill: speed x lifetime tops out under the fill's own
	-- height (~1.3 studs), so none climbs into the empty headspace.
	local source = carrier(m, origin, "BottleBubbles", { bx, at(0.3), bz }, { 2 * S, 0.05, 2 * S })
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bubbles"
	bubbles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromHex("FFFFFF"))
	bubbles.LightInfluence = 1
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.Rate = 3
	bubbles.Lifetime = NumberRange.new(2.0, 2.3)
	bubbles.Speed = NumberRange.new(0.45, 0.5)
	bubbles.SpreadAngle = Vector2.new(8, 8)
	bubbles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 0.09),
	})
	bubbles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.85, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	bubbles.ZOffset = 0.55
	bubbles.Parent = source

	-- NO PROMPT AND NO SIGN, on request. Walking up to your own bottle opens a panel on
	-- your screen instead (the client's LiquidController): the loaded fluid, a ROLL
	-- button, and the Luck upgrade that used to be a lever out on the floor. The panel
	-- finds the bottle by its `SpinsFluid` tag, so the body part is all it needs.

	m.Parent = parent
end

--- Dress one plot's bottle in a fluid: every `Liquid` part and its light take the
--- fluid's colour. `liquidId` nil (an unclaimed plot) is Plain Water. The only writer
--- is ExhibitService.renderBottle, the same split setTreadmillTier has: the service
--- decides WHAT, this file knows WHERE. The fluid's NAME is on the owner's panel, not
--- over the bottle -- the floating sign was removed on request.
function Plots.setFluidBottle(bottleModel: Instance?, liquidId: string?)
	if bottleModel == nil then
		return
	end
	local def = Liquids.get(liquidId or Liquids.WATER)
	local colour = Color3.fromHex(def.color)
	for _, d in bottleModel:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Liquid" then
			d.Color = colour
			local glow = d:FindFirstChildOfClass("PointLight")
			if glow then
				glow.Color = colour
			end
		end
	end
	bottleModel:SetAttribute("Liquid", liquidId or Liquids.WATER)
end

--- Fill one plot's tub with a fluid: the `Water` body takes the fluid's colour and the
--- `WaterSheen` over it a paler wash of the same, so the tub you wash in holds what the
--- bottle beside it does. `liquidId` nil (an unclaimed plot) is Plain Water. Written by
--- ExhibitService.renderBottle alongside setFluidBottle, so the two never disagree.
--- The sheen is NOT left at C.glass: its blue tint over an orange fill read as a
--- second, different liquid floating on top.
function Plots.setTubFluid(stationModel: Instance?, liquidId: string?)
	if stationModel == nil then
		return
	end
	local colour = Color3.fromHex(Liquids.get(liquidId or Liquids.WATER).color)
	local water = stationModel:FindFirstChild("Water", true)
	if water and water:IsA("BasePart") then
		water.Color = colour
	end
	local sheen = stationModel:FindFirstChild("WaterSheen", true)
	if sheen and sheen:IsA("BasePart") then
		sheen.Color = colour:Lerp(Color3.new(1, 1, 1), 0.5)
	end
	local tank = stationModel:FindFirstChild("PumpFluid", true)
	if tank and tank:IsA("BasePart") then
		tank.Color = colour
	end
	stationModel:SetAttribute("Liquid", liquidId or Liquids.WATER)
end

--- THE QUARANTINE LOCKER (PLAN §10.2) — a rack of sealed specimen tubes beside the
--- cleansing station, holding what you parked instead of carrying. REBUILT ON REQUEST
--- from the old one-door steel cabinet ("the old one is bad"), picked from browser
--- mockups: cabinet B, the tube rack, to match the panel's GUI 3, the tubes. It was a
--- display nobody could open; it is now a station with its own E prompt.
---
--- TWO TIERS OF FOUR TUBES = Plots.LOCKER_SLOTS (8), one stored nuke per tube, lower
--- tier first, then left to right as you face the rack. `LockerSlot<i>` is a hidden
--- anchor on the floor of tube i; `LockerGlow<i>` is the pool at the tube's foot that
--- ExhibitService.renderLocker tints in the stored find's rarity colour (the crust's
--- brown while it is still ???) and lights. The glass stays glass.
---
--- IT IS A STATION NOW: `LockerStation`, an invisible part in front of the rack, carries
--- StationKind = "locker" and StationId = the plot index, and the "OpenLocker" prompt
--- lives on it. StationController opens the locker panel on that E; DeconService only
--- reports the station to the plot's OWNER, so walking up to a neighbour's rack opens
--- nothing. Plots.lockerStation is exported so ExhibitService can put the same part on
--- a world built before this rack existed -- a stale world keeps its old cabinet but
--- still gets a locker that opens.
---
--- WHERE: backed onto the +X fence beside the cleansing station (moved back on
--- request, after a spell on the -X fence by the treadmill), facing -X into the aisle
--- beside the front row of stands, between that row's +X plinth and the cleansing
--- station (which ends at z ~= -21.3). This is where it first stood. A locker whose
--- station overlapped the tub would steal the decon station, and your hose with it;
--- World.verify asserts the gap.
local LOCKER_TUBES_PER_TIER = 4
local LOCKER = {
	x = 29.6, -- the rack's centre; its back reaches x ~= 31.1
	z = -15.5,
	yaw = 90, -- turns the authored -Z front to face -X, its back against the +X fence
	pitch = 1.65, -- tube centre to tube centre, along the rack
	tubeD = 1.45, -- glass diameter
	tubeH = 3.8, -- glass height, cap to cap (taller on request; the rack grows with it)
	capH = 0.24,
	deckH = 0.3,
	kerbH = 0.55,
	depth = 2.6,
	radius = 6,
}
assert(LOCKER_TUBES_PER_TIER * 2 == Plots.LOCKER_SLOTS, "the rack's two tiers must hold exactly Plots.LOCKER_SLOTS tubes")

--- The station part + its prompt, in front of a rack whose own frame is `face` (rack
--- faces -Z in that frame). Exported for ExhibitService's stale-world backfill.
function Plots.lockerStation(parent: Instance, face: CFrame, index: number): BasePart
	local station = build(parent, face, {
		name = "LockerStation",
		pos = { 0, 2.5, -LOCKER.depth / 2 - 1.6 },
		size = { 1, 1, 1 },
		color = C.steelDark,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		attributes = {
			StationKind = "locker",
			StationId = tostring(index),
			PlotIndex = index,
			Radius = LOCKER.radius,
		},
	})
	-- A plain default prompt, like the tub's "Wash": the panel is the custom part.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenLocker"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Quarantine Locker"
	prompt.HoldDuration = 0
	-- Inside the station's radius, so the E is never offered from a spot where the server
	-- does not yet count you as at the locker.
	prompt.MaxActivationDistance = LOCKER.radius - 0.5
	prompt.RequiresLineOfSight = false
	prompt.Parent = station
	return station
end

--- THE IMPORTED RACK (the user's own model, Import 3D): ReplicatedStorage.Assets
--- .QuarantineLocker, a cabinet of two tiers of four tubes, `tube_L0..3` (lower) and
--- `tube_U0..3` (upper), each holding a `glass` mesh and a `baseGlow` disc. Authored
--- front -Z like the built rack, tube 0 at +X = the left as you face it. Scaled up from
--- its ~2.5-stud import; a place without it falls back to the built rack below.
local LOCKER_TEMPLATE_SCALE = 3.4

local function lockerTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("QuarantineLocker")
	return if template and template:IsA("Model") then template else nil
end

local function firstPart(root: Instance, prefix: string): BasePart?
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Name:sub(1, #prefix) == prefix then
			return d
		end
	end
	return nil
end

--- Stand the imported rack at `face` and give each tube the same LockerTube / LockerGlow
--- / LockerSlot parts the built rack has, so ExhibitService.renderLocker fills it as is.
local function placeLockerTemplate(m: Model, template: Model, face: CFrame)
	local rack = template:Clone()
	rack.Name = "Rack"
	rack:ScaleTo(rack:GetScale() * LOCKER_TEMPLATE_SCALE)
	local cf, size = rack:GetBoundingBox()
	-- Bounding box centre onto the rack's spot, its feet on the floor.
	rack:PivotTo(face * CFrame.new(0, size.Y / 2, 0) * cf:Inverse() * rack:GetPivot())
	for _, d in rack:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CastShadow = false
		end
	end
	rack.Parent = m

	local slot = 0
	for _, tier in { "L", "U" } do
		for t = 0, LOCKER_TUBES_PER_TIER - 1 do
			slot += 1
			local tube = rack:FindFirstChild(`tube_{tier}{t}`)
			local glass = tube and firstPart(tube, "glass")
			local disc = tube and firstPart(tube, "baseGlow")
			if glass == nil or disc == nil then
				warn(`[plots] imported locker has no tube_{tier}{t} glass/baseGlow; slot {slot} stays empty`)
				continue
			end
			glass.Name = `LockerTube{slot}`
			glass.Material = Enum.Material.Glass
			glass.Transparency = 0.72
			glass.CanCollide = true
			-- A flat pool laid on the disc: renderLocker tints it, and a textured mesh
			-- would hide the tint.
			local floor = disc.CFrame * CFrame.new(0, disc.Size.Y / 2, 0)
			local glow = Instance.new("Part")
			glow.Name = `LockerGlow{slot}`
			glow.Shape = Enum.PartType.Cylinder
			glow.Size = Vector3.new(0.06, disc.Size.X * 0.92, disc.Size.Z * 0.92)
			glow.CFrame = floor * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.rad(90))
			glow.Color = Color3.fromHex(C.steelDark)
			glow.Material = Enum.Material.SmoothPlastic
			glow.Anchored = true
			glow.CanCollide = false
			glow.Parent = m
			local lamp = Instance.new("PointLight")
			lamp.Name = "GlowLight"
			lamp.Range = 5
			lamp.Brightness = 0.9
			lamp.Shadows = false
			lamp.Enabled = false
			lamp.Parent = glow
			-- The anchor's bottom face is the pool's top (renderLocker seats on it).
			local anchor = Instance.new("Part")
			anchor.Name = `LockerSlot{slot}`
			anchor.Size = Vector3.new(0.9, 0.9, 0.9)
			anchor.CFrame = floor * CFrame.new(0, 0.06 + 0.45, 0)
			anchor.Transparency = 1
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.Parent = m
		end
	end
end

local function buildQuarantineLocker(parent: Instance, origin: CFrame, index: number)
	local m = Instance.new("Model")
	m.Name = "QuarantineLocker"
	local L = LOCKER
	local floorY = Plots.PAD.topY

	-- Authored facing -Z, long axis along X, centred on the rack; L.yaw turns the front
	-- to face -X and puts the back against the +X fence.
	local face = origin * CFrame.new(L.x, floorY, L.z) * CFrame.Angles(0, math.rad(L.yaw), 0)
	local template = lockerTemplate()
	if template then
		placeLockerTemplate(m, template, face)
		Plots.lockerStation(m, face, index)
		m.Parent = parent
		return
	end
	local span = LOCKER_TUBES_PER_TIER * L.pitch
	local width = span + 0.5
	local HAZ_YELLOW, HAZ_BLACK = "FFC21A", "22252A"
	local GLASS = "CFE8FF"

	-- ── The kerb: studded, with a hazard-striped front ──
	build(m, face, { name = "Kerb", pos = { 0, L.kerbH / 2, 0 }, size = { width, L.kerbH, L.depth }, color = C.standGreyDark, material = "Plastic", studs = true })
	local stripes = 10
	local stripeW = width / stripes
	for s = 0, stripes - 1 do
		build(m, face, {
			name = "KerbStripe",
			pos = { -width / 2 + (s + 0.5) * stripeW, L.kerbH / 2, -L.depth / 2 - 0.03 },
			size = { stripeW, L.kerbH - 0.12, 0.06 },
			color = if s % 2 == 0 then HAZ_YELLOW else HAZ_BLACK,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end

	-- ── Two tiers ──
	local tierH = L.capH * 2 + L.tubeH
	local tierBase = { L.kerbH, L.kerbH + tierH + L.deckH }
	local topY = tierBase[2] + tierH

	-- The back panel and its two side posts: one studded frame the tubes stand inside.
	build(m, face, { name = "BackPanel", pos = { 0, topY / 2, L.depth / 2 - 0.2 }, size = { width, topY, 0.4 }, color = C.steelDark, material = "Metal" })
	for _, sx in { -1, 1 } do
		build(m, face, {
			name = "Post",
			pos = { sx * (width / 2 + 0.25), (topY + 0.6) / 2, 0.2 },
			size = { 0.5, topY + 0.6, L.depth - 0.4 },
			color = C.standGreyDark,
			material = "Plastic",
			studs = true,
		})
	end
	-- The deck between the tiers, and the lid over the top one.
	build(m, face, { name = "Deck", pos = { 0, tierBase[2] - L.deckH / 2, 0.1 }, size = { width, L.deckH, L.depth - 0.2 }, color = C.steel, material = "Metal" })
	build(m, face, { name = "Lid", pos = { 0, topY + 0.2, 0.1 }, size = { width + 1, 0.4, L.depth - 0.2 }, color = C.standGreyDark, material = "Plastic", studs = true })

	local slot = 0
	for tier = 1, 2 do
		local y0 = tierBase[tier]
		for t = 1, LOCKER_TUBES_PER_TIER do
			slot += 1
			-- Left to right AS YOU FACE THE RACK: facing +Z in this frame, your right is -X.
			local x = span / 2 - (t - 0.5) * L.pitch
			local z = -0.15
			local glassY = y0 + L.capH + L.tubeH / 2

			for _, capY in { y0 + L.capH / 2, y0 + L.capH + L.tubeH + L.capH / 2 } do
				build(m, face, {
					name = "TubeCap",
					pos = { x, capY, z },
					size = { L.capH, L.tubeD + 0.2, L.tubeD + 0.2 },
					color = C.steel,
					material = "Metal",
					shape = "Cylinder",
					rot = Kit.R.cylUp,
				})
			end
			build(m, face, {
				name = `LockerTube{slot}`,
				pos = { x, glassY, z },
				size = { L.tubeH, L.tubeD, L.tubeD },
				color = GLASS,
				material = "Glass",
				transparency = 0.72,
				shape = "Cylinder",
					rot = Kit.R.cylUp,
			})
			-- The pool the stored find sits in. Grey and dark while the tube is empty;
			-- renderLocker colours it and switches its light on.
			local glow = build(m, face, {
				name = `LockerGlow{slot}`,
				pos = { x, y0 + L.capH + 0.12, z },
				size = { 0.24, L.tubeD - 0.12, L.tubeD - 0.12 },
				color = C.steelDark,
				material = "SmoothPlastic",
				canCollide = false,
				shape = "Cylinder",
					rot = Kit.R.cylUp,
			})
			local lamp = Instance.new("PointLight")
			lamp.Name = "GlowLight"
			lamp.Range = 5
			lamp.Brightness = 0.9
			lamp.Shadows = false
			lamp.Enabled = false
			lamp.Parent = glow

			-- The anchor's bottom face is the pool's top: renderLocker seats the model
			-- on (anchor.Position.Y - anchor.Size.Y / 2).
			build(m, face, {
				name = `LockerSlot{slot}`,
				pos = { x, y0 + L.capH + 0.24 + 0.45, z },
				size = { 0.9, 0.9, 0.9 },
				color = C.steel,
				material = "SmoothPlastic",
				transparency = 1,
				canCollide = false,
			})
		end
	end

	-- The manifold: one pipe along the top, a short riser down into each upper cap.
	local pipeY = topY + 0.75
	build(m, face, { name = "Manifold", pos = { 0, pipeY, 0.35 }, size = { width + 0.6, 0.42, 0.42 }, color = C.steel, material = "Metal", shape = "Cylinder", rot = Kit.R.cylAlongX })
	for t = 1, LOCKER_TUBES_PER_TIER do
		build(m, face, {
			name = "Riser",
			pos = { span / 2 - (t - 0.5) * L.pitch, topY + 0.55, 0.35 },
			size = { 0.5, 0.26, 0.26 },
			color = C.steel,
			material = "Metal",
			shape = "Cylinder",
					rot = Kit.R.cylUp,
		})
	end

	Plots.lockerStation(m, face, index)
	m.Parent = parent
end

-- ── The treadmill ─────────────────────────────────────────────────────────
--
-- Where speed comes from, now that the Boots track is retired (Config/Treadmill).
-- Step on the belt and the number climbs; press the red button on the upgrade sign
-- beside it to buy a faster belt. Services/TreadmillService owns both halves.
--
-- IT SHARES THE ENTRANCE SERVICE STRIP with the cleansing station (+X), and the
-- clearances here are a CORRECTNESS constraint, not a layout
-- preference. Training is an edge, so overlapping station radii would mean a player at
-- one machine being registered at another. MOVED TO THE -X SIDE, into the wash pad's
-- old spot, when the pad was removed on request -- it used to stand in the middle of
-- the strip, on the entrance path. Belt centre sits at plot-local (-21, -31), Radius
-- up to ~9 on the diamond rung (installTreadmillLook sizes it to the belt):
--
--   to the Basin  (26, -32), Radius 9 ...... 47.0 studs against an 18-stud combined reach
--   to PlotSpawn  (0, -24), 6x6 ............ 22.1 studs against 12
--   to Stand10    (-20, -6), Radius 7 ...... 25.0 studs against 16
--
-- Keep those gaps if either moves. World.verify() is the actual authority and asserts
-- the first every rebuild, not this comment.
--
-- THE RUNNER FACES -Z, out through the entrance arch at the wasteland, with the
-- console at that end, clear of the spawn pad.
local TREADMILL = {
	cx = -21,
	-- Moved back from -35 as the models grew, so the gold rung's console end stays on
	-- the pad: see `scale`. Then from -33.5 to -31 (2026-10-02), because the diamond
	-- rung's nose ran 1.2 studs through the front fence. A saved place built at the
	-- old spot is moved at runtime (placeTreadmill), so this needs no rebuild.
	cz = -31,
	-- The imported models come in at ~2 studs long; every rung is scaled by the SAME
	-- factor, so the machine visibly grows as it is upgraded (the gold one is half again
	-- the basic one's length, as authored). 4.5, then 5, then 5.6, each on request
	-- ("slightly bigger", "a little bit bigger again"). At 5.6 the diamond one (the
	-- biggest) reaches plot-local z -40.8, clear of the front fence's rail at ~-41.7,
	-- and its back end z -23.7. Behind it the strip is
	-- clear to the upper-floor posts at z -11 (PlotSpawn is off at x 0), so a bigger
	-- scale moves `cz` back by 1.62 studs per unit of scale to keep the console end put.
	scale = 5.6,
	-- The belt surface above the pad top. The models' belts sit ~0.1 model units above
	-- their lowest part, so at `scale` this rests every rung on the pad.
	beltTop = 0.55,
	-- The skeleton belt before a model is fitted to it, and what shows if the templates
	-- are missing (a place without Assets.TreadmillTemplates).
	beltW = 3.2,
	beltL = 8,
}

--- Where the imported rungs live: one Model per `Treadmill.TIERS[i].model`, as the
--- user imported them (Import 3D, coloured). Their parts are named
--- `<model>_belt`, `<model>_belt_stripe_<k>`, `<model>_screen`, `<model>_console_body`,
--- and the runner stands facing the model's +Z, with the console at that end.
local TEMPLATE_FOLDER = "TreadmillTemplates"

--- Imported parts that stay solid: the motor hood at the head, the uprights, and the
--- low side rails, which are the machine's walls. Everything above them does not
--- collide, so nothing catches a player's head on the way on or off.
local SOLID_SUFFIXES = { "_motor_hood", "_upright_L", "_upright_R", "_side_rail_L", "_side_rail_R" }

--- The readout's palette: hazard-yellow on the model's own screen, a dim track for
--- the progress bar.
local SCREEN_INK, SCREEN_DIM = "FFC21A", "3A3A2A"
local SCREEN_BARS = 7

local warnedMissing: { [string]: boolean } = {}

local function treadmillTemplate(name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(TEMPLATE_FOLDER)
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template
	end
	if not warnedMissing[name] then
		warnedMissing[name] = true
		warn(`[plots] no treadmill model ReplicatedStorage.Assets.{TEMPLATE_FOLDER}.{name}; the belt stays bare`)
	end
	return nil
end

--- The console's screen: the owner's speed level, a bar to the next one (both written
--- by setTreadmillTier alongside the billboard), and a stride pulse that bounces
--- (StationMotionController). Lit text, LightInfluence 0 so the sun does not wash it
--- out -- a screen, not paint. It rides a thin clear part laid just proud of the
--- model's screen, because a SurfaceGui drawn on the mesh's own box face can sit behind
--- the bezel around it.
local function buildReadout(look: Model, screenMesh: BasePart)
	local screen = Instance.new("Part")
	screen.Name = "Screen"
	screen.Size = Vector3.new(screenMesh.Size.X, screenMesh.Size.Y, 0.05)
	-- The runner looks at the model's -Z faces (Front); stand the panel off that face.
	screen.CFrame = screenMesh.CFrame * CFrame.new(0, 0, -(screenMesh.Size.Z / 2 + 0.06))
	screen.Transparency = 1
	screen.Anchored = true
	screen.CanCollide = false
	screen.CanQuery = false
	screen.CanTouch = false
	screen.Parent = look

	local readout = Instance.new("SurfaceGui")
	readout.Name = "Readout"
	readout.Face = Enum.NormalId.Front
	readout.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	readout.PixelsPerStud = 60
	readout.LightInfluence = 0
	readout.MaxDistance = 60
	readout.Parent = screen

	local speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "Speed"
	speedLabel.BackgroundTransparency = 1
	speedLabel.Position = UDim2.fromScale(0.04, 0.06)
	speedLabel.Size = UDim2.fromScale(0.6, 0.6)
	speedLabel.Font = Kit.FONT
	speedLabel.TextScaled = true
	speedLabel.TextXAlignment = Enum.TextXAlignment.Left
	speedLabel.TextColor3 = Color3.fromHex(SCREEN_INK)
	speedLabel.Text = `WALK {Treadmill.walkSpeedFor(1)}` -- setTreadmillTier's until it runs
	speedLabel.Parent = readout

	local pulse = Instance.new("Frame")
	pulse.Name = "Pulse"
	pulse.BackgroundTransparency = 1
	pulse.Position = UDim2.fromScale(0.68, 0.1)
	pulse.Size = UDim2.fromScale(0.28, 0.54)
	pulse.Parent = readout
	for i = 1, SCREEN_BARS do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.fromScale((i - 1) / SCREEN_BARS, 1)
		bar.Size = UDim2.fromScale(0.6 / SCREEN_BARS, 0.4)
		bar.BackgroundColor3 = Color3.fromHex(SCREEN_INK)
		bar.BorderSizePixel = 0
		bar.Parent = pulse
	end

	local track = Instance.new("Frame")
	track.Name = "Progress"
	track.Position = UDim2.fromScale(0.04, 0.76)
	track.Size = UDim2.fromScale(0.92, 0.14)
	track.BackgroundColor3 = Color3.fromHex(SCREEN_DIM)
	track.BorderSizePixel = 0
	track.Parent = readout
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromHex(SCREEN_INK)
	fill.BorderSizePixel = 0
	fill.Parent = track
	for _, frame in { track, fill } do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
	Kit.motion(screen, { kind = "screen" })
end

--- Per-rung glow, on request ("add effects to the upgraded treadmills", then "remove
--- sparkles, I was thinking glowed parts"). No particles: each paid rung turns more of
--- its own model's parts Neon in the rung's colour, plus a light under the belt, so
--- the machine reads as more powerful at a glance. The free Scrap Belt stays plain.
---
---   Servo Track      side rails glow green
---   Reactor Mill     side rails + uprights glow blue
---   Isotope Strider  side rails + uprights + motor hood + belt slats glow gold
---   Diamond Drive    its own crystals, neon strips, belt edges + slats glow ice-blue
---
--- Everything is inside `look`, so a swap to the next rung takes the old glow with it.
local TREADMILL_GLOW: { [number]: { color: string, light: number, parts: { string } } } = {
	[2] = { color = "5BE36B", light = 0.25, parts = { "_side_rail_L", "_side_rail_R" } },
	[3] = { color = "3AA8FF", light = 0.35, parts = { "_side_rail_L", "_side_rail_R", "_upright_L", "_upright_R" } },
	[4] = {
		color = "FFC21A",
		light = 0.5,
		parts = { "_side_rail_L", "_side_rail_R", "_upright_L", "_upright_R", "_motor_hood", "Slat" },
	},
	-- The diamond model brings its own crystals and neon strips, so those are what glow;
	-- its uprights and hood keep their texture, which is most of what makes it diamond.
	[5] = {
		color = "8EF4FF",
		light = 0.6,
		parts = {
			"_neon_strip_L",
			"_neon_strip_R",
			"_belt_edge_L",
			"_belt_edge_R",
			"_crystal",
			"_upright_crystal_L",
			"_upright_crystal_R",
			"_halo_arch_glow",
			"Slat",
		},
	},
}

local TREADMILL_NEON_DIM = 0.7

local function addTreadmillFx(look: Model, belt: BasePart, tier: number, model: string)
	local glow = TREADMILL_GLOW[tier]
	if glow == nil then
		return
	end
	local color = Color3.fromHex(glow.color)
	-- Neon blooms by colour, so the parts take a dimmed shade ("too bright"); the lamp keeps the full hue.
	local neonColor = color:Lerp(Color3.new(0, 0, 0), TREADMILL_NEON_DIM)
	local names: { [string]: boolean } = {}
	for _, suffix in glow.parts do
		names[if suffix == "Slat" then suffix else model .. suffix] = true
	end
	for _, d in look:GetDescendants() do
		if d:IsA("BasePart") and names[d.Name] then
			d.Material = Enum.Material.Neon
			d.Color = color
			if d:IsA("MeshPart") then
				d.TextureID = "" -- a baked texture would paint over the glow
			end
		end
	end

	local lamp = Instance.new("PointLight")
	lamp.Color = color
	lamp.Brightness = glow.light
	lamp.Range = math.max(8, belt.Size.Z * 0.7)
	lamp.Shadows = false
	local anchor = Instance.new("Part")
	anchor.Name = "FxGlow"
	anchor.Size = Vector3.new(1, 0.2, 1)
	anchor.CFrame = belt.CFrame * CFrame.new(0, belt.Size.Y / 2 + 0.5, 0)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = look
	lamp.Parent = anchor
end

--- Swap the treadmill's `Look` for the imported model of belt rung `tier`, fitted to
--- the skeleton: the model's belt top lands on the skeleton `Belt`'s top centre, the
--- skeleton belt is resized to the model's (its CENTRE never moves, and that centre is
--- all StationService and World.verify read), and the `Console` anchor -- prompt,
--- billboard and tag -- is moved onto the model's console.
---
--- THE STRIPES ARE REBUILT, NOT KEPT. TreadmillController scrolls every `Slat` down
--- the belt and wraps it modulo the skeleton belt's length, which is only seamless if
--- that length is a whole number of stripe pitches with a stripe in every one. The
--- imported models leave the stretch under the motor hood bare and their belts are not
--- a whole number of pitches long, so the skeleton belt is trimmed to the largest whole
--- number that fits and one stripe is laid per pitch, cloned from the model's own.
local function installTreadmillLook(treadmill: Instance, tier: number): boolean
	local belt = treadmill:FindFirstChild("Belt")
	local console = treadmill:FindFirstChild("Console")
	if belt == nil or not belt:IsA("BasePart") or console == nil or not console:IsA("BasePart") then
		return false
	end
	local def = Treadmill.tier(tier)
	local template = treadmillTemplate(def.model)
	if template == nil then
		return false
	end

	local look = template:Clone()
	look:ScaleTo(TREADMILL.scale)
	local modelBelt = look:FindFirstChild(def.model .. "_belt", true)
	if modelBelt == nil or not modelBelt:IsA("BasePart") then
		look:Destroy()
		warn(`[plots] treadmill model {def.model} has no {def.model}_belt part`)
		return false
	end

	-- Belt top centre to belt top centre, turned half round so the model's +Z runner
	-- faces the skeleton's -Z.
	local skeletonTop = belt.CFrame * CFrame.new(0, belt.Size.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)
	local modelTop = modelBelt.CFrame * CFrame.new(0, modelBelt.Size.Y / 2, 0)
	look:PivotTo(skeletonTop * modelTop:Inverse() * look:GetPivot())

	local stripes: { BasePart } = {}
	local screenMesh: BasePart? = nil
	local consoleBody: BasePart? = nil
	for _, d in look:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		for _, suffix in SOLID_SUFFIXES do
			if d.Name == def.model .. suffix then
				d.CanCollide = true
			end
		end
		if string.find(d.Name, "_belt_stripe_", 1, true) then
			table.insert(stripes, d)
		elseif d.Name == def.model .. "_screen" then
			screenMesh = d
		elseif d.Name == def.model .. "_console_body" then
			consoleBody = d
		end
	end

	-- The model's own belt is the running surface you see; the skeleton belt under it
	-- is the one you stand on, so it goes clear and takes the model's footprint.
	local travel = belt.CFrame.LookVector * -1
	if #stripes >= 2 then
		table.sort(stripes, function(a, b)
			return a.Position:Dot(travel) < b.Position:Dot(travel)
		end)
		local pitch = (stripes[#stripes].Position - stripes[1].Position):Dot(travel) / (#stripes - 1)
		local count = math.max(1, math.floor(modelBelt.Size.Z / pitch + 1e-3))
		local length = count * pitch
		belt.Size = Vector3.new(modelBelt.Size.X, belt.Size.Y, length)
		local proto = stripes[1]
		local lift = proto.Position.Y - belt.Position.Y
		for k = 0, count - 1 do
			local slat = proto:Clone()
			slat.Name = "Slat"
			local at = belt.CFrame * CFrame.new(0, 0, length / 2 - (k + 0.5) * pitch)
			slat.CFrame = proto.CFrame.Rotation + at.Position + Vector3.new(0, lift, 0)
			slat.Parent = proto.Parent
		end
		for _, stripe in stripes do
			stripe:Destroy()
		end
	else
		belt.Size = Vector3.new(modelBelt.Size.X, belt.Size.Y, modelBelt.Size.Z)
	end
	belt.Transparency = 1
	-- The training zone covers the whole belt, whatever its size: StationService
	-- measures from the belt's centre to the runner's HumanoidRootPart (~3.3 studs
	-- above the belt part's centre), and the gold rung's belt runs well past a fixed 5.
	-- Re-read by StationService every CACHE_REFRESH, so a swap lands within 2 s.
	local halfL, halfW = belt.Size.Z / 2, belt.Size.X / 2
	belt:SetAttribute("Radius", math.ceil((math.sqrt(halfL * halfL + halfW * halfW + 3.3 * 3.3) + 0.5) * 10) / 10)

	if screenMesh then
		buildReadout(look, screenMesh)
	end
	addTreadmillFx(look, belt, tier, def.model)
	if consoleBody then
		console.CFrame = consoleBody.CFrame
		console.Size = consoleBody.Size
	end

	local old = treadmill:FindFirstChild("Look")
	if old then
		old:Destroy()
	end
	look.Name = "Look"
	look.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	look.Parent = treadmill
	treadmill:SetAttribute("LookTier", tier)
	return true
end

--- THE UPGRADE SIGN: a studded navy board on a post beside the belt, the way to buy the
--- next rung (on request, in place of the console's E prompt). Only the geometry is
--- built here. What it says, and its red cash and purple Robux buttons, are drawn by
--- the client (TreadmillSignController) from the treadmill's `Tier` / `Locked`
--- attributes: buttons on a world gui only take input from a gui under PlayerGui.
---
--- PLACED OFF THE BELT, never from plot-local numbers: the sign stands at a fixed
--- offset from the skeleton `Belt`, whose centre never moves (installTreadmillLook),
--- on the +X side between the machine and the entrance path, PARALLEL TO THE FRONT
--- FENCE (on request), its face turned back into the base (+Z), a little ahead of the
--- belt's centre so a runner facing out sees it front-on to their right. Its near
--- edge stands `gap` off the INSTALLED rung's +X side (treadmillSideX), so it hugs
--- the small belts too instead of always clearing the diamond (on request: closer).
local UPGRADE_SIGN = {
	gap = 0.5, -- board's near edge to the installed rung's +X side
	fallbackSide = 6.8, -- the diamond rung's side, for a treadmill with no Look
	z = -3, -- toward the entrance (-Z), ahead of the runner
	-- Five sixths of the second cut (on request: slightly smaller again). The client
	-- draws its face at the board's own size, so these can change freely.
	boardW = 5,
	boardH = 2.75,
	boardT = 1,
	boardBottom = 2.2, -- above the pad
	-- The post is exactly as thick as the board and centred under it, so its front
	-- and back run flush into the board's (on request: line up, same width).
	postW = 1,
	color = "1D2B4F",
}

--- Where a treadmill built before `TREADMILL.cz` moved stood (no `BeltZ` attribute).
local LEGACY_TREADMILL_CZ = -33.5

--- Move a treadmill saved in the place at an older `TREADMILL.cz` to the current one:
--- the skeleton belt, console, look and sign all slide along the plot's Z axis by the
--- difference, and `BeltZ` records where it now is. A no-op once it is in place, so
--- setTreadmillTier calls it on every repaint. The belt's rotation IS the plot's.
local function placeTreadmill(treadmill: Instance)
	local belt = treadmill:FindFirstChild("Belt")
	if belt == nil or not belt:IsA("BasePart") then
		return
	end
	local at = treadmill:GetAttribute("BeltZ")
	local shift = TREADMILL.cz - (if type(at) == "number" then at else LEGACY_TREADMILL_CZ)
	if math.abs(shift) < 1e-3 then
		return
	end
	local offset = belt.CFrame.ZVector * shift
	for _, child in treadmill:GetChildren() do
		if child:IsA("BasePart") then
			child.CFrame += offset
		elseif child:IsA("Model") then
			child:PivotTo(child:GetPivot() + offset)
		end
	end
	treadmill:SetAttribute("BeltZ", TREADMILL.cz)
end

--- Put the sign up beside `treadmill` if it isn't there yet. Idempotent and cheap, so
--- setTreadmillTier calls it on every repaint. A sign built to an older UPGRADE_SIGN
--- (its board a different size, or stood at a different offset) is taken down and put up again to the current one.
--- How far the installed rung's `Look` reaches off the belt's centre line on its +X
--- side (the sign's side), measured once per look and kept as its `SideX` attribute:
--- setTreadmillTier asks on every repaint and the look only changes on a swap.
local function treadmillSideX(treadmill: Instance, belt: BasePart): number
	local look = treadmill:FindFirstChild("Look")
	if look == nil then
		return UPGRADE_SIGN.fallbackSide
	end
	local cached = look:GetAttribute("SideX")
	if type(cached) == "number" then
		return cached
	end
	local side = 0
	for _, d in look:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local h = d.Size / 2
			for _, sx in { 1, -1 } do
				for _, sy in { 1, -1 } do
					for _, sz in { 1, -1 } do
						local corner = d.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
						side = math.max(side, belt.CFrame:PointToObjectSpace(corner).X)
					end
				end
			end
		end
	end
	side = math.ceil(side * 10) / 10
	look:SetAttribute("SideX", side)
	return side
end

local function ensureUpgradeSign(treadmill: Instance)
	local belt = treadmill:FindFirstChild("Belt")
	if belt == nil or not belt:IsA("BasePart") then
		return
	end
	local u = UPGRADE_SIGN
	local x = treadmillSideX(treadmill, belt) + u.gap + u.boardW / 2
	local existing = treadmill:FindFirstChild("UpgradeSign")
	if existing then
		local board = existing:FindFirstChild("Board")
		if
			board
			and board:IsA("BasePart")
			and (board.Size - Vector3.new(u.boardW, u.boardH, u.boardT)).Magnitude < 1e-3
			and existing:GetAttribute("OffsetX") == x
			and existing:GetAttribute("OffsetZ") == u.z
		then
			return
		end
		existing:Destroy()
	end
	local padTop = belt.Position.Y + belt.Size.Y / 2 - TREADMILL.beltTop
	local level = belt.CFrame.Rotation + Vector3.new(belt.Position.X, padTop, belt.Position.Z)
	-- The board's front face (-Z) is turned to look along +Z, back into the base.
	local frame = level * CFrame.new(x, 0, u.z) * CFrame.Angles(0, math.pi, 0)

	local sign = Instance.new("Model")
	sign.Name = "UpgradeSign"
	local postH = u.boardBottom + 0.5 -- runs half a stud up into the board
	build(sign, frame, {
		name = "Post",
		pos = { 0, postH / 2, 0 },
		size = { u.postW, postH, u.boardT },
		color = u.color,
		material = "Plastic",
		studs = true,
	})
	build(sign, frame, {
		name = "Board",
		pos = { 0, u.boardBottom + u.boardH / 2, 0 },
		size = { u.boardW, u.boardH, u.boardT },
		color = u.color,
		material = "Plastic",
		studs = true,
	})
	sign:SetAttribute("OffsetX", x)
	sign:SetAttribute("OffsetZ", u.z)
	sign.Parent = treadmill
end

--- Dress one plot's treadmill in a belt rung. Returns the tier actually applied, or
--- nil if this plot has no treadmill to dress (a place file saved before the machine
--- existed — degrade quietly, exactly as setHoseTier does).
---
--- EACH RUNG IS ITS OWN MODEL: the five imported treadmills in
--- ReplicatedStorage.Assets.TreadmillTemplates, one per Treadmill.TIERS entry. Buying a
--- belt swaps the machine for the next one (installTreadmillLook). A treadmill built
--- before the imported models (no `ImportedLook` attribute) keeps its old body and
--- only has its sign rewritten, until the world is rebuilt.
---
--- `points` (the owner's lifetime Speed) is optional and only feeds the sign. nil
--- means "unclaimed plot", which prints level 1 and no progress, because a bar that
--- always reads empty on six plots is worse than no bar at all.
---
--- `locked` means the owner has not bought treadmill access (Treadmill.UNLOCK_PRICE),
--- or there is no owner. The sign and screen say so, the prompt offers the unlock, and
--- the `Locked` attribute tells TreadmillController to leave this belt standing still.
function Plots.setTreadmillTier(treadmill: Instance?, tier: number?, points: number?, locked: boolean?): number?
	if treadmill == nil then
		return nil
	end

	local wanted = math.clamp(math.floor(tier or 1), 1, Treadmill.maxTier())
	placeTreadmill(treadmill)
	if treadmill:GetAttribute("ImportedLook") and treadmill:GetAttribute("LookTier") ~= wanted then
		installTreadmillLook(treadmill, wanted)
	end

	-- Levels are internal: every word a player reads is walk speed.
	local level, progress = Treadmill.levelFor(points or 0)
	local walk = Treadmill.walkSpeedFor(level)
	treadmill:SetAttribute("Locked", locked == true)
	-- The upgrade sign replaced the console's E prompt (on request). A place saved
	-- before it still has the prompt, so it goes here, and the sign is put up here
	-- too: both land on the first repaint, with no world rebuild needed.
	local console = treadmill:FindFirstChild("Console")
	local prompt = console and console:FindFirstChild("Upgrade")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
	end
	-- The floating "WALK SPEED n / belt — n% to walk speed n+1" billboard is gone (on
	-- request): the console screen and the upgrade sign say it. A place saved with it
	-- still has it, so it is taken down here, same as the prompt above.
	local oldSign = console and console:FindFirstChild("Sign")
	if oldSign and oldSign:IsA("BillboardGui") then
		oldSign:Destroy()
	end
	ensureUpgradeSign(treadmill)

	-- The console's own screen says the same number to the runner, with the bar to the
	-- next walk-speed point. Absent when the model has no screen or failed to load.
	local readout = treadmill:FindFirstChild("Readout", true)
	local screenSpeed = readout and readout:FindFirstChild("Speed")
	if screenSpeed and screenSpeed:IsA("TextLabel") then
		screenSpeed.Text = if locked then "LOCKED" else string.format("WALK %d", walk)
	end
	local fill = readout and readout:FindFirstChild("Fill", true)
	if fill and fill:IsA("Frame") then
		local shown = if points == nil or locked then 0 else progress
		fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	end

	treadmill:SetAttribute("Tier", wanted)
	return wanted
end

--- THE TREADMILL: a skeleton the world is built with, dressed at runtime in the
--- imported model of whichever belt the plot's owner has bought.
---
--- THE SKELETON IS THE STATION CONTRACT, and it never moves:
---
---   * `Belt` carries StationKind/Radius at the same plot-local centre (World.verify's
---     clearances are measured from it) and is the solid surface a runner stands on.
---     It goes clear once a model is fitted over it, and it is what TreadmillController
---     scrolls the model's `Slat` stripes down.
---   * `Console` carries UpgradesTreadmill + the prompt + the billboard. It is an
---     invisible anchor, moved onto each model's console as the model changes.
---
--- Everything visible is the `Look` model, which Plots.setTreadmillTier swaps per rung.
--- Tier 1 is fitted here, so an unclaimed plot in the saved place already shows the
--- basic treadmill.
local function buildTreadmill(parent: Instance, origin: CFrame, _accent: string)
	local m = Instance.new("Model")
	m.Name = "Treadmill"
	m:SetAttribute("ImportedLook", true)
	m:SetAttribute("BeltZ", TREADMILL.cz) -- where it was built (placeTreadmill)
	local t = TREADMILL
	local B = Plots.PAD.topY + t.beltTop

	build(m, origin, {
		name = "Belt",
		pos = { t.cx, B - 0.3, t.cz },
		size = { t.beltW, 0.6, t.beltL },
		color = "1A1F24",
		material = "Rubber",
		attributes = { StationKind = "treadmill", Radius = 5 },
	})

	local console = build(m, origin, {
		name = "Console",
		pos = { t.cx, B + 5, t.cz - 3 },
		size = { 1, 1, 1 },
		color = "2E3338",
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		attributes = { UpgradesTreadmill = true },
	})
	console.CanQuery = false
	console.CanTouch = false

	Plots.setTreadmillTier(m, 1, nil, true)
	m.Parent = parent
end

--- A plain grey guard rail down the LEFT and RIGHT long edges of the base, on
--- request — posts and two horizontal rails bolted just inside the accent `Trim`.
--- Its whole job is to read as an enclosure: the base already has a wall across the
--- back and an open service strip across the front, and the two long sides were the
--- one place the pad just fell away to the apron. The entrance (local -Z) is
--- deliberately left open — you still walk on from the front and respawn onto the
--- pad. The back-wall edge (local +Z) used to be left open too, for the NameSign's
--- standoff arms; buildBackFence now closes it with matching rail/post fencing since
--- nothing physical mounts there any more (see buildNamePlate).
---
--- Posts collide (a real barrier at intervals); the rails themselves do not, so
--- nothing catches a jumping player at head height. Runs the full pad depth in the
--- pad's own yawed local space through `origin`, like everything else in buildPlot.
---
--- Built chunky and studded on request (was thin 0.5/0.4 metal): square brick posts
--- in a darker grey, with two thick studded rails running through them, so the
--- fence reads as the same toy-brick plastic as the rest of the base.
local RAIL_H = 3.4
local RAIL_POST_SPACING = 8
local RAIL_POST_W = 0.72 -- 1.2, thinned 0.6x on request
local RAIL_BAR_T = 0.48 -- 0.8, thinned 0.6x
--- A gate in a fence line: the gap from `z0` to `z1` (plot-local) that a flight of
--- stairs outside the base is reached through, and the floor whose purchase opens it
--- (nil = always open). Until then GateFill rails span the gap.
type FenceGate = { z0: number, z1: number, floor: number? }

--- GATE_FLOOR_ATTR marks a GateFill piece with the floor that opens its gate.
local GATE_FLOOR_ATTR = "GateFloor"

--- One fence line along z at `x`, from `z0` to `z1`, broken by `gates`: a run of
--- posts and two rails between each pair of gates, a post on each gate's edges, and
--- GateFill rails across each gate that has a floor to wait for.
local function fenceLineZ(folder: Instance, origin: CFrame, y: number, x: number, z0: number, z1: number, gates: { FenceGate }?, railsCollide: boolean, skipStart: boolean?, skipEnd: boolean?)
	local postH = RAIL_H + RAIL_BAR_T / 2 + 0.4 -- stands proud of the top rail
	local function rails(name: string, a: number, b: number, attrs: { [string]: any }?)
		for _, railY in { RAIL_H, RAIL_H * 0.5 } do
			build(folder, origin, {
				name = name,
				pos = { x, y + railY, (a + b) / 2 },
				size = { RAIL_BAR_T, RAIL_BAR_T, b - a + RAIL_POST_W },
				color = C.railGrey,
				material = "Plastic",
				studs = true,
				canCollide = railsCollide,
				attributes = attrs,
			})
		end
	end
	local runs = {}
	local from = z0
	for _, g in gates or {} do
		table.insert(runs, { from, g.z0 - RAIL_POST_W / 2 })
		from = g.z1 + RAIL_POST_W / 2
		if g.floor then
			rails("GateFill", g.z0 - RAIL_POST_W / 2, g.z1 + RAIL_POST_W / 2, { [GATE_FLOOR_ATTR] = g.floor, GateCollide = railsCollide })
		end
	end
	table.insert(runs, { from, z1 })
	for n, r in runs do
		local a, b = r[1], r[2]
		if b - a < 0.01 then
			continue
		end
		rails("Rail", a, b)
		local posts = math.max(2, math.floor((b - a) / RAIL_POST_SPACING) + 1)
		for i = 0, posts - 1 do
			if (n == 1 and i == 0 and skipStart) or (n == #runs and i == posts - 1 and skipEnd) then
				continue
			end
			build(folder, origin, {
				name = "RailPost",
				pos = { x, y + postH / 2, a + (b - a) * (i / (posts - 1)) },
				size = { RAIL_POST_W, postH, RAIL_POST_W },
				color = C.railPost,
				material = "Plastic",
				studs = true,
			})
		end
	end
end

--- `gates[side]` (side -1/+1) is that side's gate list, for the flight of stairs
--- outside the fence (buildFlight).
local function buildSideRailings(parent: Instance, origin: CFrame, gates: { [number]: { FenceGate } }?)
	local pad = Plots.PAD
	local folder = Instance.new("Folder")
	folder.Name = "SideRailings"

	-- Stands on the Trim (width/2 - 1 .. width/2), outer face flush with the pad edge,
	-- so the thicker posts still clear the wash pad / cleansing station deck edges.
	local railX = pad.width / 2 - RAIL_POST_W / 2
	local z0, z1 = pad.minZ + 0.5 + RAIL_POST_W / 2, pad.maxZ - 0.5 - RAIL_POST_W / 2
	for _, side in { -1, 1 } do
		fenceLineZ(folder, origin, pad.topY, side * railX, z0, z1, gates and gates[side], false)
	end

	folder.Parent = parent
end

--- Closes the back-wall edge with the same rail/post fence buildSideRailings runs
--- down the long edges, standing where the old NameSign's standoff arms used to —
--- on request, in place of a nameplate mounted there. `railZ`/end-post X match
--- buildSideRailings' own `railX`/`z1` exactly, so the back fence's corner posts
--- land flush with the side fence's rather than leaving a gap or doubling up.
local function buildBackFence(parent: Instance, origin: CFrame)
	local pad = Plots.PAD
	-- A Model, not a Folder: Plots.setLevel slides it out behind each extension strip.
	local folder = Instance.new("Model")
	folder.Name = "BackFence"

	local railX = pad.width / 2 - RAIL_POST_W / 2
	local railZ = pad.maxZ - 0.5 - RAIL_POST_W / 2
	local span = railX * 2
	local postCount = math.max(2, math.floor(span / RAIL_POST_SPACING) + 1)
	local postH = RAIL_H + RAIL_BAR_T / 2 + 0.4

	for _, railY in { RAIL_H, RAIL_H * 0.5 } do
		build(folder, origin, {
			name = "Rail",
			pos = { 0, pad.topY + railY, railZ },
			size = { span + RAIL_POST_W, RAIL_BAR_T, RAIL_BAR_T },
			color = C.railGrey,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end

	for i = 0, postCount - 1 do
		local x = -railX + span * (i / (postCount - 1))
		build(folder, origin, {
			name = "RailPost",
			pos = { x, pad.topY + postH / 2, railZ },
			size = { RAIL_POST_W, postH, RAIL_POST_W },
			color = C.railPost,
			material = "Plastic",
			studs = true,
		})
	end

	folder.Parent = parent
	folder:SetAttribute("BasePivot", folder:GetPivot())
	folder:SetAttribute("BackAxis", origin:VectorToWorldSpace(Vector3.zAxis))
end

-- The avatar-plate marker: a circular headshot over a caption, the exact "who is
-- this" language BaseMarkerController's client-only "YOUR BASE" beacon already
-- uses for the owner's own view. This is the SAME visual built server-side instead,
-- so every player in the plaza reads it, not just the owner — replacing the old
-- flat NameSign placard as the one thing that marks whose plot this is.
local NAMEPLATE_FACE_FILL = Color3.fromHex("11150F") -- shows for the beat before the thumbnail loads
local function buildNamePlate(parent: Instance, origin: CFrame, accent: string)
	local pad = Plots.PAD

	-- High over the CENTRE of the pad, not tucked against the back edge — the same
	-- "floats over the whole base" placement BaseMarkerController's own beacon uses
	-- (Vector3.new(0, 38, 0) off the Pad), so this one reads the same way from
	-- anywhere in the plaza instead of only from in front of the plot. An invisible,
	-- uncollidable anchor — nothing to mount a physical sign to any more, this is
	-- purely something to hang the BillboardGui from.
	local anchor = build(parent, origin, {
		name = "NamePlate",
		pos = { 0, pad.topY + 38, PAD_CENTER_Z },
		size = { 1, 1, 1 },
		color = C.baseWall,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
	})
	-- Where it floats. Saved so a world built with storeys (which lifted it) can be put back.
	anchor:SetAttribute("BaseCFrame", anchor.CFrame)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Plate"
	gui.Size = UDim2.fromOffset(128, 156)
	gui.AlwaysOnTop = true
	-- Readable from way out across the plaza (on request) — walked from 600 down to
	-- 70, then 100, and now back out to 400 so a base's owner shows from the far
	-- side of the ring. `MaxDistance` is CAMERA-to-adornee and the plate sits 38
	-- studs up. ExhibitService.renderName stamps the same value on every repaint,
	-- so a live place picks it up without a Plots rebuild — keep the two in step.
	gui.MaxDistance = 400
	-- Every plot sits next to a PointLight or two; LightInfluence defaults to 1 and
	-- washes the plate back toward white up close, the same bug Kit.surfaceText and
	-- BaseMarkerController both already document and fix.
	gui.LightInfluence = 0
	gui.Parent = anchor

	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.fromScale(0.5, 0)
	face.Size = UDim2.fromOffset(80, 80)
	face.BackgroundColor3 = NAMEPLATE_FACE_FILL
	face.BackgroundTransparency = 0
	face.Image = ""
	face.Parent = gui

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = face

	-- Tagged `Accent` so Plots.setPlotAccent's UIStroke pass keeps the ring matching
	-- the plot's Trim colour, exactly like it already does for the old SignFrame bars.
	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Thickness = 2.5
	ring.Color = Color3.fromHex(accent)
	ring.Transparency = 0.1
	ring.Parent = face
	ring:SetAttribute("Accent", true)

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.new(0.5, 0, 0, 88)
	caption.Size = UDim2.new(1, 0, 0, 24)
	caption.BackgroundTransparency = 1
	caption.Font = Kit.FONT
	caption.TextSize = 18
	caption.TextColor3 = Color3.fromHex(C.labelText)
	caption.TextStrokeTransparency = 1
	caption.Text = "UNCLAIMED"
	caption.Parent = gui
	Kit.textOutline(caption, 2)

	return gui
end

--- An accent cap on top of every fence post, so the plot colour runs round the whole
--- enclosure and not just along the Trim at ankle height. A separate pass over the
--- posts buildSideRailings / buildBackFence already laid, sized off each post's own
--- CFrame and height, so it follows those builders wherever they put a post (or skip
--- one — the back fence's corners are the side fence's) without touching their loops.
local function capFencePosts(fence: Instance?, accent: string)
	if fence == nil then
		return
	end
	for _, post in fence:GetChildren() do
		if post.Name == "RailPost" and post:IsA("BasePart") then
			local cap = build(fence, post.CFrame, {
				name = "PostCap",
				pos = { 0, post.Size.Y / 2 + 0.2, 0 },
				size = { RAIL_POST_W + 0.4, 0.4, RAIL_POST_W + 0.4 },
				color = accent,
				material = "Plastic",
				studs = true,
				canCollide = false,
				attributes = { Accent = true },
			})
			cap.CanQuery = false
		end
	end
end

--- THE ENTRANCE ARCH — two studded posts either side of the entry lane, a lintel
--- across them, and a sign naming the owner, so whose base this is reads at eye level
--- from the plaza and not only from the avatar plate floating 38 studs up.
---
--- The sign's label is named `OwnerName`; ExhibitService.renderName writes
--- "<DisplayName>'s Base" into it on claim (the player's own casing, like the plate)
--- and blanks it again on release (an empty base's sign reads nothing, not
--- "UNCLAIMED"). The post caps and the stripe under the lintel carry `Accent`.
---
--- Clear of everything on the service strip: the posts stand at x = ±ARCH.x, well
--- inside the luck button (x = -13) and the cleansing station's deck (x >= 15.6), and
--- in front of both decks in z. The lintel, stripe, caps and sign are CanQuery off:
--- the default camera pops forward when a queryable part comes between it and the
--- character, which every walk under a lintel would do.
local ARCH = {
	x = 10,
	inset = 1.7, -- post centres this far in from the pad's front edge
	postW = 2.2,
	postH = 10.8,
	footW = 3.2,
	footH = 0.6,
	capW = 2.8,
	capH = 0.8,
	lintelW = 22.4,
	lintelH = 2.2,
	lintelD = 1.8,
	signW = 15,
	signH = 2,
}
local ARCH_SIGN_FILL = "2B2F36"
local function buildEntranceArch(parent: Instance, origin: CFrame, accent: string)
	local pad = Plots.PAD
	local m = Instance.new("Model")
	m.Name = "EntranceArch"
	local T = pad.topY
	local z = pad.minZ + ARCH.inset
	local postTop = T + ARCH.footH + ARCH.postH
	local lintelY = postTop + ARCH.lintelH / 2

	local function noQuery(part: BasePart)
		part.CanQuery = false
	end

	for _, side in { -1, 1 } do
		local x = side * ARCH.x
		build(m, origin, { name = "ArchFoot", pos = { x, T + ARCH.footH / 2, z }, size = { ARCH.footW, ARCH.footH, ARCH.footW }, color = C.standGrey, material = "Plastic", studs = true })
		build(m, origin, {
			name = "ArchPost",
			pos = { x, T + ARCH.footH + ARCH.postH / 2, z },
			size = { ARCH.postW, ARCH.postH, ARCH.postW },
			color = C.standGreyDark,
			material = "Plastic",
			studs = true,
		})
		-- The caps sit on the lintel's ends, which rest on the post tops.
		noQuery(build(m, origin, {
			name = "ArchCap",
			pos = { x, postTop + ARCH.lintelH + ARCH.capH / 2, z },
			size = { ARCH.capW, ARCH.capH, ARCH.capW },
			color = accent,
			material = "Plastic",
			studs = true,
			canCollide = false,
			attributes = { Accent = true },
		}))
	end

	noQuery(build(m, origin, {
		name = "ArchLintel",
		pos = { 0, lintelY, z },
		size = { ARCH.lintelW, ARCH.lintelH, ARCH.lintelD },
		color = C.standGrey,
		material = "Plastic",
		studs = true,
		canCollide = false,
	}))
	noQuery(build(m, origin, {
		name = "ArchStripe",
		pos = { 0, postTop - 0.1, z },
		size = { ARCH.lintelW + 0.2, 0.4, ARCH.lintelD + 0.1 },
		color = accent,
		material = "SmoothPlastic",
		canCollide = false,
		attributes = { Accent = true },
	}))

	-- On the lintel's outward (-Z) face, reading to anyone walking in.
	local sign = build(m, origin, {
		name = "ArchSign",
		pos = { 0, lintelY, z - ARCH.lintelD / 2 - 0.1 },
		size = { ARCH.signW, ARCH.signH, 0.25 },
		color = ARCH_SIGN_FILL,
		material = "SmoothPlastic",
		canCollide = false,
	})
	noQuery(sign)
	local label = Kit.surfaceText(sign, Enum.NormalId.Front, "", C.labelText)
	label.Name = "OwnerName"

	m.Parent = parent
end

-- ── Base upgrades (Config/BaseUpgrades) ──────────────────────────────────────

--- THE OPEN FLOOR GROWS OUT THE BACK. A base used to buy storeys of stands; now it is
--- one open floor its owner places nukes on anywhere (Shared/Placement), and each
--- Upgrade Base adds BaseUpgrades.PER_LEVEL to how many may be out AND pushes the back
--- fence DEPTH_PER_LEVEL studs further out, so the extra nukes have room.
---
--- EVERY STRIP IS BUILT, AND HIDDEN AT RUNTIME — the shape the upper floors had.
--- buildPlot builds BaseExtension1..MAX_LEVEL behind the level-0 back edge on every
--- plot: a strip of the pad's own floor with its trim, and the side fence carried out
--- along it. Plots.setLevel (ExhibitService) parks the strips a plot's owner has not
--- bought in ServerStorage and slides the BackFence out to the last one shown. The
--- apron is laid round the LEVEL-0 pad (apronSkip / padRect read Plots.PAD), so the
--- grass runs on under a hidden strip and a shown one sits on top of it.
local EXT_DEPTH = BaseUpgrades.DEPTH_PER_LEVEL
--- The back fence's rail line at level 0 (buildBackFence) and the side railings' last post.
local BACK_RAIL_Z = Plots.PAD.maxZ - 0.5 - RAIL_POST_W / 2

local function withCommas(n: number): string
	local digits = tostring(math.floor(n))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return (string.gsub(grouped, "^,", ""))
end

local function buildExtension(parent: Instance, origin: CFrame, level: number, accent: string)
	local pad = Plots.PAD
	local m = Instance.new("Model")
	m.Name = `BaseExtension{level}`
	local z0 = pad.maxZ + (level - 1) * EXT_DEPTH
	local z1 = z0 + EXT_DEPTH
	local zc = (z0 + z1) / 2

	-- Floor and the structure under it in one part, flush with PadFloor's top and
	-- bottom, so the seam between strips is a line in the studs and nothing more.
	build(m, origin, {
		name = "ExtensionFloor",
		pos = { 0, pad.topY - (pad.thickness + Hub.TILE_CAP) / 2, zc },
		size = { pad.width, pad.thickness + Hub.TILE_CAP, EXT_DEPTH },
		color = C.baseFloor,
		material = "Plastic",
	})
	for _, side in { -1, 1 } do
		build(m, origin, {
			name = "Trim",
			pos = { side * (pad.width / 2 - 0.5), pad.topY + 0.1, zc },
			size = { 1, 0.5, EXT_DEPTH },
			color = accent,
			material = "SmoothPlastic",
			canCollide = false,
			attributes = { Accent = true },
		})
	end

	-- The side fence carried out along the strip: two rails from the last strip's
	-- fence line to this one's, and one post (capped) where they end. The post at the
	-- start is the one the strip before already stands.
	local railX = pad.width / 2 - RAIL_POST_W / 2
	local fromZ = BACK_RAIL_Z + (level - 1) * EXT_DEPTH
	local toZ = fromZ + EXT_DEPTH
	local postH = RAIL_H + RAIL_BAR_T / 2 + 0.4
	local fence = Instance.new("Folder")
	fence.Name = "ExtensionFence"
	for _, side in { -1, 1 } do
		for _, railY in { RAIL_H, RAIL_H * 0.5 } do
			build(fence, origin, {
				name = "Rail",
				pos = { side * railX, pad.topY + railY, (fromZ + toZ) / 2 },
				size = { RAIL_BAR_T, RAIL_BAR_T, EXT_DEPTH + RAIL_POST_W },
				color = C.railGrey,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
		end
		build(fence, origin, {
			name = "RailPost",
			pos = { side * railX, pad.topY + postH / 2, toZ },
			size = { RAIL_POST_W, postH, RAIL_POST_W },
			color = C.railPost,
			material = "Plastic",
			studs = true,
		})
	end
	fence.Parent = m
	capFencePosts(fence, accent)

	m.Parent = parent
end

--- What the Upgrade Base sign's board reads for a base at `level`, painted ON the board
--- (a SurfaceGui named "Sign" with Title / Subtitle, so ExhibitService.flashSign finds
--- its Subtitle): "Upgrade Base" over "+2 nukes for $X". `SignText` keeps the subtitle
--- to put back after a flash. ExhibitService calls this whenever the owner's level
--- changes; the board itself is the same one at every level.
local UPGRADE_SIGN_PRICE_COLOR = "8FE36B"
function Plots.dressUpgradeSign(board: BasePart, level: number?)
	local price = BaseUpgrades.nextPrice(level)
	local subtitle = if price then `+{BaseUpgrades.PER_LEVEL} nukes for ${withCommas(price)}` else "Fully upgraded"
	board:SetAttribute("SignText", subtitle)

	local gui = board:FindFirstChild("Sign")
	if gui == nil or not gui:IsA("SurfaceGui") then
		gui = Instance.new("SurfaceGui")
		gui.Name = "Sign"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0

		local function line(name: string, text: string, color: string, y: number, h: number, stroke: number)
			local label = Instance.new("TextLabel")
			label.Name = name
			label.AnchorPoint = Vector2.new(0.5, 0)
			label.Position = UDim2.fromScale(0.5, y)
			label.Size = UDim2.fromScale(0.9, h)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBlack
			label.TextScaled = true
			label.TextColor3 = Color3.fromHex(color)
			label.TextStrokeTransparency = 1
			label.Text = text
			label.Parent = gui
			Kit.textOutline(label, stroke)
		end
		line("Title", "Upgrade Base", C.labelText, 0.1, 0.48, 2.5)
		line("Subtitle", subtitle, UPGRADE_SIGN_PRICE_COLOR, 0.62, 0.24, 1.5)
		gui.Parent = board
	end
	local label = (gui :: Instance):FindFirstChild("Subtitle")
	if label and label:IsA("TextLabel") then
		label.Text = subtitle
	end
	local prompt = board:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ObjectText = if price then `${withCommas(price)}` else ""
	end
end

--- THE UPGRADE BASE SIGN — a board hung on the inside of the -X side fence, just
--- behind the entrance strip, facing into the base: the first thing on your left as
--- you walk in under the arch. Tapping E on it opens the purchase popup (ExhibitService
--- wires it by Kit.UPGRADE_TAG). Plots.setLevel shows it only on a claimed plot that
--- still has an upgrade to buy.
---
--- ANSWERS IN THE WORLD. A refused purchase is written into the painted subtitle for a
--- moment (ExhibitService.flashSign), not sent as a toast nobody sees away from a panel
--- (memory: station-result-toast-needs-panel).
local UPGRADE_SIGN_Z = -14
local function buildUpgradeSign(parent: Instance, origin: CFrame, index: number, accent: string)
	local pad = Plots.PAD
	local m = Instance.new("Model")
	m.Name = "UpgradeSign"
	local railX = HALF_W - RAIL_POST_W / 2
	local x = -(railX - RAIL_BAR_T / 2 - 0.27)
	local face = Kit.ang(0, -90, 0)

	-- The accent stripe along the board's top edge doubles as the bar it hangs from,
	-- resting on the fence's top rail.
	build(m, origin, {
		name = "SignStripe",
		pos = { x, pad.topY + RAIL_H + RAIL_BAR_T / 2 + 0.15, UPGRADE_SIGN_Z },
		size = { 5.2, 0.3, 0.7 },
		rot = face,
		color = accent,
		material = "SmoothPlastic",
		canCollide = false,
		attributes = { Accent = true },
	})
	local board = build(m, origin, {
		name = "SignBoard",
		pos = { x, pad.topY + RAIL_H + RAIL_BAR_T / 2 - 1.2, UPGRADE_SIGN_Z },
		size = { 5, 2.4, 0.5 },
		rot = face,
		color = ARCH_SIGN_FILL,
		material = "SmoothPlastic",
		attributes = { UpgradesBase = true, PlotIndex = index },
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UpgradeBase"
	prompt.ActionText = "Upgrade Base"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = board
	-- Front is the face turned into the base.
	Plots.dressUpgradeSign(board, 0)

	m.Parent = parent
end

--- Where ExhibitService parks the extension strips a plot's owner has not bought (and
--- the Upgrade Base sign while nobody can use it). Out of Workspace entirely, so a
--- hidden strip costs the clients nothing.

--- EDGE LIGHTS — no fixture, just light (same rule as the ceiling sheet). Tiny
--- invisible anchors carrying a shadowless PointLight each, so the base and the
--- camp's rim stay lit without adding lamp props.
--- Brightness 1.4 -> 1.0 (2026-09-30, "remove a little more lighting in the base camp").
local EDGE_LIGHT = { range = 18, brightness = 1.0, color = "FFF1DC", spacing = 22, height = 7 }
local function edgeLight(parent: Instance, cf: CFrame)
	local p = Instance.new("Part")
	p.Name = "EdgeLight"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = cf
	p.Anchored = true
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	local l = Instance.new("PointLight")
	l.Color = Color3.fromHex(EDGE_LIGHT.color)
	l.Range = EDGE_LIGHT.range
	l.Brightness = EDGE_LIGHT.brightness
	l.Shadows = false
	l.Parent = p
	p.Parent = parent
end


local STASH_NAME = "PlotFloorStash"
local function stashFor(plot: Instance): Instance
	local root = ServerStorage:FindFirstChild(STASH_NAME)
	if root == nil then
		root = Instance.new("Folder")
		root.Name = STASH_NAME
		root.Parent = ServerStorage
	end
	local mine = (root :: Instance):FindFirstChild(plot.Name)
	if mine == nil then
		mine = Instance.new("Folder")
		mine.Name = plot.Name
		mine.Parent = root
	end
	return mine :: Instance
end

--- Show the strips this base's owner has bought and park the rest, slide the back
--- fence out behind the last one, and — only on a `claimed` plot with an upgrade left
--- to buy — show the Upgrade Base sign. Publishes the level as the plot's `BaseLevel`
--- attribute (the client's placement ghost reads the open floor's depth off it).
--- Idempotent, and quiet on a world built before extensions existed (nothing to move).
function Plots.setLevel(plot: Instance?, level: number?, claimed: boolean)
	if plot == nil then
		return
	end
	local model: Instance = plot
	local n = BaseUpgrades.clamp(level)
	local stash = stashFor(model)

	local function place(name: string, visible: boolean)
		local here = model:FindFirstChild(name)
		local away = stash:FindFirstChild(name)
		if visible then
			if here == nil and away ~= nil then
				away.Parent = model
			end
		elseif here ~= nil then
			if away ~= nil then
				away:Destroy() -- a leftover from a plot rebuilt mid-session
			end
			here.Parent = stash
		end
	end
	for k = 1, BaseUpgrades.MAX_LEVEL do
		place(`BaseExtension{k}`, k <= n)
	end
	place("UpgradeSign", claimed and n < BaseUpgrades.MAX_LEVEL)

	local fence = model:FindFirstChild("BackFence")
	local rest = fence and fence:GetAttribute("BasePivot")
	local axis = fence and fence:GetAttribute("BackAxis")
	if fence and fence:IsA("Model") and typeof(rest) == "CFrame" and typeof(axis) == "Vector3" then
		fence:PivotTo(rest + axis * (n * EXT_DEPTH))
	end
	model:SetAttribute("BaseLevel", n)
end

--- THE FRONT FENCE — the side railings' fence carried across the pad's front edge (on
--- request), in two runs from each front corner in to the entrance arch, so the base
--- is fenced all round with the arch as its one way in. Same line as the side
--- railings' first post (`z`), so the corners meet flush; each run skips its corner
--- post (buildSideRailings already stands one there) and its arch end, where the
--- rails run into the arch post, which does that post's job.
local function buildFrontFence(parent: Instance, origin: CFrame)
	local pad = Plots.PAD
	local folder = Instance.new("Folder")
	folder.Name = "FrontFence"

	local railX = pad.width / 2 - RAIL_POST_W / 2
	local z = pad.minZ + 0.5 + RAIL_POST_W / 2
	local postH = RAIL_H + RAIL_BAR_T / 2 + 0.4
	for _, side in { -1, 1 } do
		local x0, x1 = side * ARCH.x, side * railX
		local span = math.abs(x1 - x0)
		for _, railY in { RAIL_H, RAIL_H * 0.5 } do
			build(folder, origin, {
				name = "Rail",
				pos = { (x0 + x1) / 2, pad.topY + railY, z },
				size = { span, RAIL_BAR_T, RAIL_BAR_T },
				color = C.railGrey,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
		end
		local posts = math.max(2, math.floor(span / RAIL_POST_SPACING) + 1)
		for i = 1, posts - 2 do
			build(folder, origin, {
				name = "RailPost",
				pos = { x0 + (x1 - x0) * (i / (posts - 1)), pad.topY + postH / 2, z },
				size = { RAIL_POST_W, postH, RAIL_POST_W },
				color = C.railPost,
				material = "Plastic",
				studs = true,
			})
		end
	end

	folder.Parent = parent
end

--- THE HAZARD LINE — yellow and black studded bricks laid flat across the pad where the
--- open floor starts (Shared/Placement.AREA.minZ), on request: everything behind it is
--- where nukes go, everything in front (the washer, the treadmill, the locker, the
--- spawn) is not. The bricks sit just in FRONT of the edge, so a nuke placed right up to
--- the line never stands on it. Flat, so you walk over it; not collidable either way.
local PLACE_LINE = { depth = 0.8, height = 0.16, stripe = 2.4 }
local function buildPlaceLine(parent: Instance, origin: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "PlaceLine"
	local x0, x1 = -HALF_W + 1, HALF_W - 1
	local stripes = math.max(2, math.round((x1 - x0) / PLACE_LINE.stripe))
	local w = (x1 - x0) / stripes
	local z = Placement.AREA.minZ - PLACE_LINE.depth / 2
	for i = 0, stripes - 1 do
		build(folder, origin, {
			name = "HazardStripe",
			pos = { x0 + (i + 0.5) * w, Plots.PAD.topY + PLACE_LINE.height / 2, z },
			size = { w, PLACE_LINE.height, PLACE_LINE.depth },
			color = if i % 2 == 0 then C.hazard else C.hazardBlack,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end
	folder.Parent = parent
end

local function buildPlot(parent: Instance, index: number)
	local m = Instance.new("Model")
	m.Name = `Plot{index}`

	local center = Plots.CENTERS[index]
	-- The yaw is applied to the ORIGIN, so every part in this function stays written
	-- in the pad's own space and the whole plot turns as one. Rotating the parts
	-- individually would leave the spawn and the stands facing
	-- whichever way each was authored.
	local origin = CFrame.new(center.x, 0, center.z) * CFrame.Angles(0, math.rad(center.facing), 0)
	-- Every accent piece (Trim, the avatar plate's Ring, the cleansing-station Lamp,
	-- the two station sign subtitles, and the gallery's arch caps/stripe, plinth bands,
	-- fence caps and slot brackets) is built in this ONE neutral grey and carries an
	-- `Accent` attribute. ExhibitService.renderAccent -> Plots.setPlotAccent walks those
	-- tagged pieces on claim and repaints them from `data.plotColor` — or, until the
	-- owner picks one in Settings, from this plot's Plots.DEFAULT_ACCENTS entry — and
	-- back to grey on release. The build itself stays neutral: an unclaimed plot is grey.
	local accent = C.plotNeutral
	local pad = Plots.PAD

	-- THE STAGE, WEARING THE PLAZA'S STUDDED BOARD IN ONE FLAT COLOUR. One step up
	-- from the apron — a plot should feel like somewhere you walk onto, not part of
	-- the lawn — and one flat wooden-deck brown (`C.baseFloor`), flat where the grass
	-- around it alternates, so the six bases read as decks set into the apron. The
	-- board has been every shape by now (navy/grey checker → flat grey → flat
	-- near-black → a smooth no-stud plate → charcoal studs); one flat studded tone so
	-- the studs catch the light like every other floor in the world without the pad
	-- alternating or turning to a mirror.
	--
	-- BUILT IN THIS MODEL'S YAWED LOCAL SPACE, THROUGH `origin`, LIKE EVERYTHING ELSE
	-- IN THIS FUNCTION — the opposite of how this used to work (see this file's own
	-- header on why: a pad's footprint stopped being axis-aligned in world space the
	-- moment the ring stopped using only 90-degree facings). `rect` is a LOCAL
	-- rectangle with an asymmetric entrance extension, not a world-space one.
	local rect: Hub.Rect = { minX = -HALF_W, maxX = HALF_W, minZ = pad.minZ, maxZ = pad.maxZ }
	local tint: Hub.TileOpts = { topY = pad.topY, dark = C.baseFloor, light = C.baseFloor, origin = origin }

	-- The slab underneath carries PlotIndex, because that is the world contract this
	-- file's header publishes and a folder of tiles cannot carry it.
	local slab = Hub.groundSlab(m, rect, "Pad", pad.thickness, tint)
	slab:SetAttribute("PlotIndex", index)

	-- The visible floor: ONE studded cap over the whole pad, topping out at pad.topY —
	-- it IS what a player stands on (the structural slab is recessed a cap below it).
	-- This used to be the plaza's tile board (Hub.tileRect) with `dark == light`, i.e.
	-- 391 identical 4x4 tiles per pad, 2,346 across the ring, for a floor with no
	-- pattern to draw. Studs are a surface type, so one part shows the same studded
	-- board; the pad's width and depth are whole studs, so no stud is cut at an edge.
	local cap = Hub.TILE_CAP
	build(m, origin, {
		name = "PadFloor",
		pos = { 0, pad.topY - cap / 2, PAD_CENTER_Z },
		size = { rect.maxX - rect.minX, cap, rect.maxZ - rect.minZ },
		color = C.baseFloor,
		material = "Plastic",
	})

	buildPlaceLine(m, origin)

	-- Accent trim, so whose plot is whose is readable from across the plaza. Matte —
	-- the colour alone carries the "whose plot" cue now, no glow. `Accent` tags it for
	-- Plots.setPlotAccent; grey until the owner picks a hue.
	for _, side in { -1, 1 } do
		build(m, origin, {
			name = "Trim",
			pos = { side * (pad.width / 2 - 0.5), pad.topY + 0.1, PAD_CENTER_Z },
			size = { 1, 0.5, pad.depth },
			color = accent,
			material = "SmoothPlastic",
			canCollide = false,
			attributes = { Accent = true },
		})
	end

	-- No solid back wall any more, on request — just the fence (buildBackFence, the
	-- same rail/post language buildSideRailings already runs down the long edges,
	-- closing the back edge instead of a wall) and a floating avatar+name plate high
	-- over the pad's centre (buildNamePlate) that reads like BaseMarkerController's
	-- own "YOUR BASE" beacon — a circular headshot with the owner's name below it —
	-- except built server-side so it's visible to every player in the plaza, not
	-- just the owner.
	buildSideRailings(m, origin)
	buildBackFence(m, origin)
	capFencePosts(m:FindFirstChild("SideRailings"), accent)
	capFencePosts(m:FindFirstChild("BackFence"), accent)
	buildFrontFence(m, origin)
	capFencePosts(m:FindFirstChild("FrontFence"), accent)
	buildNamePlate(m, origin, accent)

	-- No claim board any more: exhibit income is auto-deposited into the owner's
	-- wallet (ExhibitService.deposit), so there is nothing here to walk up to and
	-- collect. Whose plot this is reads from the avatar plate floating over the pad
	-- and, at eye level, from the entrance arch's sign.
	buildEntranceArch(m, origin, accent)

	-- Where this plot's owner respawns. Disabled until somebody owns it, so nobody
	-- ever lands on a stranger's stage. ExhibitService flips this on assignment.
	-- Fully invisible: there is no physical checkpoint pad any more, just the spawn
	-- point itself at the same spot the pad used to mark.
	local spawn = build(m, origin, {
		name = "PlotSpawn",
		class = "SpawnLocation",
		pos = { 0, pad.topY + 0.5, -24 },
		size = { 6, 1, 6 },
		color = accent,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		attributes = { PlotIndex = index },
	}) :: SpawnLocation
	spawn.Enabled = false
	spawn.Neutral = true

	buildCleansingStation(m, origin, accent)
	buildQuarantineLocker(m, origin, index)
	buildFluidBottle(m, origin)
	buildTreadmill(m, origin, accent)

	-- The open floor's extension strips and the sign that sells them. All built; the
	-- ones this plot's owner has not bought are hidden at runtime (Plots.setLevel).
	for level = 1, BaseUpgrades.MAX_LEVEL do
		buildExtension(m, origin, level, accent)
	end
	buildUpgradeSign(m, origin, index, accent)
	-- Where ExhibitService puts each placed nuke (one anchor part per nuke, by uid).
	local placed = Instance.new("Folder")
	placed.Name = "PlacedNukes"
	placed.Parent = m

	m.Parent = parent
	return m
end

--- Lay the apron. Lives in this file rather than in Hub.luau because its shape is
--- derived from the pads, and Hub cannot see them: Plots requires Hub, so a require back
--- the other way would be a cycle. Hub owns the PATTERN and exports it; this file owns
--- the SHAPE and asks for it to be tiled.
---
--- THE VISIBLE CAP is one `Hub.tileRect` call over the camp's bounding box (grown by
--- APRON_GROW, so the tiles run UNDER the perimeter wall), clipped at `maxX = PLAZA.maxX`
--- (Stage 1's own west edge, touching not crossing it) and punched by `apronSkip`.
---
--- `ground = true` on that call is the other half of Hub's base floor: buildPlaza
--- paints the plaza slab, this paints the rest of the camp -- same grid, same
--- `Hub.groundPairAt` resolver -- so it comes out grass flowing around every plot
--- footprint, picks up the gate paths out to each pad (one raised floor with the plaza),
--- and every tile it doubles over the plaza's own edge (PLAZA_SKIP_MARGIN) takes the
--- plaza's colour instead of z-fighting a different one over it.
---
--- THE STRUCTURAL BACKING underneath is one slab per camp rectangle (Plots.campRects),
--- grown the same APRON_GROW so it also reaches under the wall.
local function buildApron(row: Model)
	local apron = Instance.new("Folder")
	apron.Name = "Apron"

	local rects = Plots.campRects(APRON_GROW)
	local bounds: Hub.Rect = { minX = math.huge, maxX = PLAZA.maxX, minZ = math.huge, maxZ = -math.huge }
	for _, r in rects do
		bounds.minX = math.min(bounds.minX, r.minX)
		bounds.minZ = math.min(bounds.minZ, r.minZ)
		bounds.maxZ = math.max(bounds.maxZ, r.maxZ)
	end
	Hub.tileRect(apron, bounds, { skip = apronSkip, ground = true })

	for i, r in rects do
		Hub.groundSlab(apron, r, `ApronSlab{i}`)
	end

	-- The camp's rim: edge lights 4 studs inside the perimeter wall, along the outline
	-- from the south wing's outer wall round the back to the north wing's. The east
	-- walls are left dark: the leaderboards and the group chest stand against them.
	local rim = Instance.new("Folder")
	rim.Name = "RimLights"
	local c = Plots.CAMP
	local inset = 4
	local ex, wx, bx = c.eastX - inset, c.wingX + inset, c.backX + inset
	local wz, bz = c.wingZ - inset, c.backHalfZ - inset
	local path = { { ex, -wz }, { wx, -wz }, { wx, -bz }, { bx, -bz }, { bx, bz }, { wx, bz }, { wx, wz }, { ex, wz } }
	for i = 1, #path - 1 do
		local ax, az = path[i][1], path[i][2]
		local dx, dz = path[i + 1][1] - ax, path[i + 1][2] - az
		local len = math.sqrt(dx * dx + dz * dz)
		local steps = math.max(1, math.ceil(len / EDGE_LIGHT.spacing))
		-- Each leg owns its start corner; the last leg also lays the final corner.
		for k = 0, if i == #path - 1 then steps else steps - 1 do
			local t = k / steps
			edgeLight(rim, CFrame.new(ax + dx * t, Plots.PAD.topY + EDGE_LIGHT.height, az + dz * t))
		end
	end
	rim.Parent = apron

	apron.Parent = row
end

local function createPlots(): Model
	local row = Instance.new("Model")
	row.Name = "Plots"
	Kit.stamp(row, BUILDER_SOURCE, BUILDER_VERSION)

	assert(#Plots.CENTERS == Plots.COUNT, "plot centre list does not match Plots.COUNT")

	for index = 1, Plots.COUNT do
		buildPlot(row, index)
	end

	buildApron(row)

	return row
end

function Plots.build(parent: Instance?): Model
	local row = createPlots()
	row.Parent = parent or Workspace
	return row
end

function Plots.rebuild(parent: Instance?): Model
	local row = Kit.swap("Plots", createPlots, parent) :: Model
	print(
		`[build] Plots rebuilt — {Plots.COUNT} open-floor plots, {BaseUpgrades.MAX_LEVEL} extension strips `
			.. `each ({BaseUpgrades.START} to {BaseUpgrades.MAX_NUKES} nukes), `
			.. `{Plots.LOCKER_SLOTS}-tube quarantine locker each, `
			.. `{#row.Apron:GetChildren()} apron parts`
	)
	return row
end

return Plots
