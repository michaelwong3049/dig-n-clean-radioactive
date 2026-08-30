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

	A SEMICIRCLE AROUND THE SHOP CLUSTER — the requested layout:

	              [PLOT] [PLOT]
	         [PLOT]   .-'''-.
	                 (  SHOPS ) === [RADIOACTIVE AREA]
	         [PLOT]   `-...-'
	              [PLOT] [PLOT]

	Six pads on the exterior of one circle, evenly spaced across its western 180
	degrees, each rotated to face the shop cluster at the centre. The eastern half
	is open — the plaza (`Hub.PLAZA`, untouched by this file, still sitting between
	the shop cluster and Stage 1) is the connector, so the ring is open there and
	always will be — you leave the courtyard by walking into the sludge. See
	RING_CENTER/RING_RADIUS/RING_ANGLES below for the actual circle.

	IT WAS A RECTANGULAR RING BEFORE THIS — two pads on each of the plaza's north,
	south and west edges, butted flush against it. That shape hard-assumed every
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

	A BASE WEARS THE PLAZA'S BOARD IN ITS OWN COLOURS. The pad is not a slab of
	concrete any more: it is the same studded checkerboard the courtyard is paved in,
	on the same grid, in navy and grey instead of green, one step up. That makes the
	six bases the only thing in the world that is not some shade of green, and it
	makes walking onto one a change of colour rather than a change of surface.

	A PAD'S OWN TILES ARE BUILT IN ITS YAWED LOCAL SPACE, NOT WORLD SPACE — the
	opposite of how this used to work, and the semicircle is exactly why: a pad's
	footprint was axis-aligned in world space at every facing the old rectangular
	ring used (only multiples of 90), so tiling that world-space bounding box was
	exact. None of the six facings on the semicircular ring are multiples of 90 any
	more, so the old approach would tile a diamond of excess area outside the
	pad's real, rotated footprint. See `buildPlot` and `Hub.TileOpts.origin`. The
	one cost: a pad's board can no longer phase-lock with the apron's grid across
	their shared edge (only possible at 90-degree multiples) — still an exact 3x3
	checkerboard, just an incidental phase instead of a matched one.

	THE DEPENDENCY FLIPPED, AGAIN, AND THIS TIME IT IS DERIVED RATHER THAN COMMENTED.
	This file used to require `Hub`, then stopped, and `Hub.luau` carried a comment
	listing four of this file's constants that its plaza had to be hand-matched to. It
	requires `Hub` again now — but to READ `Hub.PLAZA` and compute the ring from it, so
	the two cannot drift. Hub requires only Kit, so the direction is safe.

	Plot INTERNALS still face south (claim board and spawn near the front) —
	nothing about station detection cares which way a plot faces, it's all
	radius-based, so re-stacking the six plots into this column cost zero
	gameplay risk. The internal arrangement itself (stands + cleansing station)
	changed since; see "THE BASE LAYOUT" below.

	THE BASE LAYOUT — cleansing station at the top, stands flanking left and
	right, per the requested sketch:

	    ┌─────────────────────────────────────┐
	    │      [locker]   CLEANSING            │
	    │  [stand]                   [stand]   │
	    │  [stand]                   [stand]   │
	    │  [stand]         .                   │
	    │  [stand]                   [stand]   │
	    │                                       │
	    └─────────────────────────────────────┘

	The Quarantine Locker (PLAN §10.2) sits against the back wall left of the
	cleansing station — the physical rack of items you hauled home but can't clean
	yet. Built here, filled by ExhibitService.renderLocker; see buildQuarantineLocker.

	Eight stands, four per side, in two flanking columns — `slotOffset` pairs
	them off row by row (slot 1 = left row 1, slot 2 = right row 1, slot 3 = left
	row 2, ...) rather than filling a centred grid, and the cleansing station
	moved from the pad's back-third to right up near the back wall so it reads
	as the "top" of the base the sketch asks for.

	SLOTS: 8 BUILT, ALL FREE.
	Tuning.EXHIBIT_MAX_SLOTS is 8 and VISIBLE_SLOTS is the 8 the sketch shows —
	they're the same number now. Every stand is usable from the moment a plot is
	claimed; there is no slot to buy or unlock.

	slotOffset is defined for slots past 8 too (rows 5+ extend the same two columns
	further out), so raising both VISIBLE_SLOTS and EXHIBIT_MAX_SLOTS is all it
	takes to show more — it just won't match the sketch's exact 8-stand picture
	once you do.

	THE WORLD CONTRACT:
	    Pad         PlotIndex = n
	    ClaimBoard  StationKind = "plot",     StationId = "<n>",        Radius = 10
	    Stand       StationKind = "pedestal", StationId = "<n>:<slot>", Radius = 7
	                PlotIndex = n, SlotIndex = s
	                — the base course of the display plinth (StandTop / StandRim /
	                Display are the rest of it); see buildDisplayStand.
	    PlotSpawn   SpawnLocation, Enabled = false until the plot is claimed
	    Basin       StationKind = "decon", Shower = true, Radius = 9 — the cleansing
	                station (see buildCleansingStation below). One per base, replacing
	                the single shared station + shower that used to live at camp.
	    QuarantineLocker   no station attributes — a display cabinet. LockerSlot1..
	                Plots.LOCKER_SLOTS are hidden item anchors; LockerDoor is a Model
	                carrying ClosedPivot / OpenPivot CFrame attributes. Both are
	                filled/animated by ExhibitService.renderLocker from data.locker.

	The stand's StationId is "plot:slot" so the server can resolve exactly which
	pedestal a player is standing at without a spatial search of its own.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local Plots = {}
local BUILDER_SOURCE = "src/server/build/Plots.luau"
local BUILDER_VERSION = 17

local C = Kit.C
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

Plots.COUNT = 6
Plots.VISIBLE_SLOTS = 8
-- Interior bays in the Quarantine Locker cabinet (buildQuarantineLocker). Kept in
-- step with the cleansing-station panel's own LOCKER_ROWS; ExhibitService.renderLocker
-- reads the same number. A locker with more than this many racked items just doesn't
-- show the overflow, exactly like a plot past VISIBLE_SLOTS pedestals.
Plots.LOCKER_SLOTS = 3
-- topY is a deliberate step UP from the plaza (the mirror of Stages.SURFACE_Y's own
-- step down), expressed relative to Hub.PLAZA.topY rather than as a bare literal so
-- it keeps meaning "+1.5 above the plaza" if that ever moves again, instead of
-- silently becoming a different absolute step.
Plots.PAD = { width = 66, depth = 52, topY = Hub.PLAZA.topY + 1.5, thickness = 3 }

--- THE RING. Six pads on the exterior of a circle pulled toward Stage 1, each
--- rotated to face the centre.
---
--- DERIVED FROM Hub.PLAZA, NOT HAND-SYNCED TO IT — same property the rectangular
--- ring before this had: the plaza is the source, this reads it, and moving the
--- plaza moves the ring with it. Hub requires only Kit, so requiring it here is
--- not circular.
---
--- RING_CENTER USED TO BE THE PLAZA'S OWN MIDPOINT (MID_X, MID_Z) — moved
--- toward Stage 1 on request, to shorten the walk from the shop cluster to the
--- field. How far it could move WAS bounded by the shop cluster's OWN footprint,
--- not by the pads: `SHOP_CLUSTER_EAST_REACH = 53` below was Shops.luau's
--- eastmost stall (the "Cleaner" counter, once at `RING_CENTER.x + 42`) plus its
--- ~11-stud half-width, and `FIELD_CLEARANCE` the margin kept past that. THAT
--- COUPLING IS NOW HISTORICAL: the shop row was re-centred on the plaza midpoint
--- (Hub's grey central spine) rather than on RING_CENTER, so the Cleaner stall
--- pulled ~14.5 studs back west and no longer reaches anywhere near Stage 1.
--- `SHOP_CLUSTER_EAST_REACH` is deliberately left at 53 so RING_CENTER stays put
--- — it is now the established ring position, a conservative bound rather than a
--- live measurement of anything in Shops.luau. (The pads have far more room to
--- spare here — see World.verify()'s own overlap checks, which are the real
--- authority on safety, not this comment.)
--- `facing` is a yaw in degrees. A pad is built with its back wall at +Z and its
--- claim board at -Z, so 0 faces south, 180 faces north, -90 faces east — and
--- because every pad's position below is constructed as
--- `RING_CENTER + RING_RADIUS * (sin(bearing), cos(bearing))`, its `facing`
--- equals that same bearing (normalised into the -180..180 range this file
--- already used for the old west-side pads' -90): a pad built this way always
--- looks straight back at RING_CENTER by construction, no separate aim step
--- needed. Checked against the three cases the old rectangular ring had: bearing
--- 0 (due north of centre) faces south (0) toward it, bearing 180 (due south)
--- faces north (180), bearing 270 (due west) faces east (-90) — all three match.
---
--- RING_ANGLES is 6 bearings at 34-degree SECTOR MIDPOINTS symmetric about due
--- west (185, 219, ... 355), not the sector edges — so no pad sits exactly on
--- the north/south line where the ring's open mouth begins. See RING_ANGLES'
--- own comment for why 34 and not wider.
---
---                    (north, bearing 0)
---                [ 6 ]           [ 1 ]
---           [ 5 ]     .-'''-.        <open mouth>
---                    ( SHOPS  )  ==>  RADIATION
---           [ 4 ]     `-...-'
---                [ 3 ]           [ 2 ]
---                    (south, bearing 180)
---
--- Numbered clockwise starting just west of due south. Unlike the old ring
--- (whose single "jump" crossed the entire east side in one step, 3 to 4), the
--- open mouth here is symmetric: it's the gap on BOTH sides of the 6-to-1 seam,
--- between the last pad short of due-north and the first pad short of due-south.
local PLAZA = Hub.PLAZA
local HALF_W, HALF_D = Plots.PAD.width / 2, Plots.PAD.depth / 2
local MID_Z = (PLAZA.minZ + PLAZA.maxZ) / 2

local SHOP_CLUSTER_EAST_REACH = 53
local FIELD_CLEARANCE = 15
Plots.RING_CENTER = { x = PLAZA.maxX - SHOP_CLUSTER_EAST_REACH - FIELD_CLEARANCE, z = MID_Z }

--- Pad-CENTRE orbit radius. 180 gave a uniform ~16-stud gap between every one of
--- the 6 pads' oriented rectangles at the original 30-degree spacing (checked
--- with real oriented-rectangle distance, not a small-angle approximation) —
--- matching the old rectangular ring's own 16-stud SPREAD gap between paired
--- pads. Widening the spacing to 34 degrees (see RING_ANGLES below) only grows
--- that gap further at this same radius, so 180 was left untouched rather than
--- re-derived — the number that mattered (minimum gap, at whatever the current
--- spacing is) is checked live by World.verify() every rebuild, not pinned to a
--- comment that would need re-deriving each time either constant moves.
--- Comfortably more spread out than the old ring's west-side reach (~134.5
--- studs from centre): this radius alone is already 180, before a pad's own
--- half-depth is added on top.
Plots.RING_RADIUS = 180

--- The walkway's outer disc radius — has to clear the farthest PAD CORNER from
--- RING_CENTER, not just the farthest pad centre: `sqrt((RING_RADIUS+HALF_D)^2 +
--- HALF_W^2)` = ~208.6 studs.
---
--- 235, TRIMMED BACK DOWN FROM 290, ON REQUEST — 290's ~80-stud buffer past
--- every pad's farthest corner read as a wide belt of empty tiled ground
--- ringing the whole camp (most visible on the west cap, farthest from the
--- plaza, where nothing but the walkway itself ever stood). 235 keeps a real
--- ~26-stud margin past the 208.6 reach — still comfortably more than the
--- previous 215's ~6-stud margin, just nowhere near 290's — without any other
--- change: `apronSkip`, the backing bands and World.verify()'s landmass
--- square all already read this constant rather than a hardcoded reach.
Plots.RING_OUTER = 235

--- 34-degree spacing (was 30, widened on request for more breathing room
--- between pads at the same radius), sector MIDPOINTS (see this section's own
--- comment above for why not the sector edges).
---
--- 34, NOT WIDER, IS CLOSE TO THE ACTUAL CEILING HERE, NOT A ROUND NUMBER. Six
--- pads symmetric about bearing 270 (due west) at spacing S sit at
--- 270 +/- 0.5S, +/- 1.5S, +/- 2.5S — the two extremes are 2.5S off 270, and
--- once either one reaches 90 degrees off 270 (bearing 180 or 360, due south
--- or due north exactly) its centre's world X stops being west of RING_CENTER
--- at all (sin of the bearing crosses zero there) and starts swinging back
--- toward the field on the OTHER side of that cardinal point. That puts a hard
--- ceiling at S = 90/2.5 = 36; 34 leaves each extreme 5 degrees short of it —
--- enough that the pad's own half-width doesn't need a separate check on top
--- of the centre-point one, confirmed by World.verify()'s actual oriented-rect
--- overlap math rather than trusted on this angle alone. Order matches the
--- numbering diagram above.
local RING_ANGLES = { 185, 219, 253, 287, 321, 355 }

Plots.CENTERS = {}
for i, bearing in RING_ANGLES do
	local rad = math.rad(bearing)
	Plots.CENTERS[i] = {
		x = Plots.RING_CENTER.x + Plots.RING_RADIUS * math.sin(rad),
		z = Plots.RING_CENTER.z + Plots.RING_RADIUS * math.cos(rad),
		facing = if bearing > 180 then bearing - 360 else bearing,
	}
end

--- A pad's true, ROTATED footprint — an `Kit.OrientedRect`, not an axis-aligned
--- bounding box. Only right angles occurred in the old rectangular ring, which is
--- what let that ring get away with a "swap width/depth" axis-aligned shortcut;
--- none of the six facings here are multiples of 90, so overlap/containment
--- tests need the real oriented rectangle. `Kit.pointInOrientedRect` and
--- `Kit.orientedRectsOverlap` (used by this file's apron and by
--- World.verify()'s pad checks) both take this same shape.
local function padRect(c: { x: number, z: number, facing: number }): Kit.OrientedRect
	return { cx = c.x, cz = c.z, halfWidth = HALF_W, halfDepth = HALF_D, yawDeg = c.facing }
end

--- THE APRON — the disc of ground between the shop cluster and the pads, minus
--- the plaza (which already has its own floor) and minus every pad's own
--- footprint.
---
--- ONE TILED DISC, NOT SIX SPOKES. Tile a square bounding RING_OUTER and drop
--- whatever falls outside the disc, inside the plaza, or inside a pad, via a
--- skip predicate — the same "tile the whole area, punch the exceptions back
--- out" approach the old rectangular apron used, generalised from three
--- rectangles to a circle. It cannot fall out of step with the ring for the same
--- reason the old version couldn't: everything here reads RING_CENTER,
--- RING_OUTER and CENTERS directly rather than duplicating a shape.
---
--- THE OPEN MOUTH COMES FREE FROM THE BOUNDING RECT ITSELF: capping it at
--- `maxX = PLAZA.maxX` (see `buildApron`'s own comment on why that, and not
--- RING_CENTER.x) still only ever tiles at most the disc's western half plus
--- the sliver flanking the plaza on its way out to Stage 1 — never anything
--- east of the field's own west edge, the same clipping mechanism that already
--- keeps the plaza's own east edge from overhanging into Stage 1 (`Hub.tileRect`
--- clips every tile to the rect it's given).
--- How far inside the plaza's own literal edge a tile's CENTRE has to land
--- before this treats it as safely covered by the plaza's own floor and skips
--- it here. NOT zero, and here is why: Hub.PLAZA is 140 studs in Z (70*2) and
--- the tile grid is 3 studs (Hub.TILES) — 140 isn't a multiple of 3, so the
--- plaza's own northmost/southmost tile ROW is a partial-height tile clipped
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
local PLAZA_SKIP_MARGIN = 3

local function apronSkip(x: number, z: number): boolean
	local dx, dz = x - Plots.RING_CENTER.x, z - Plots.RING_CENTER.z
	if dx * dx + dz * dz > Plots.RING_OUTER * Plots.RING_OUTER then
		return true -- outside the disc
	end
	if
		x > PLAZA.minX + PLAZA_SKIP_MARGIN
		and x < PLAZA.maxX - PLAZA_SKIP_MARGIN
		and z > PLAZA.minZ + PLAZA_SKIP_MARGIN
		and z < PLAZA.maxZ - PLAZA_SKIP_MARGIN
	then
		return true -- safely inside the plaza's own floor, well past its edge tiles
	end
	for _, c in Plots.CENTERS do
		if Kit.pointInOrientedRect(x, z, padRect(c)) then
			return true
		end
	end
	return false
end

--- Two flanking columns, paired off row by row — odd slots go left, even slots
--- go right, and each pair shares a Z so the sketch's row-by-row symmetry holds.
--- ROW_TOP_Z is the FIRST row, closest to the cleansing station at the back;
--- rows count DOWN from there toward the entrance. The maths works for any slot
--- number, not just the 8 that are built — so raising VISIBLE_SLOTS (and
--- EXHIBIT_MAX_SLOTS with it) just adds more rows further toward the front.
local COL_X = 25
local ROW_TOP_Z = 15
local ROW_PITCH = 10

local function slotOffset(slot: number): (number, number)
	local row = math.floor((slot - 1) / 2)
	local isLeft = slot % 2 == 1
	local x = if isLeft then -COL_X else COL_X
	local z = ROW_TOP_Z - row * ROW_PITCH
	return x, z
end

--- THE DISPLAY STAND — a low two-course studded riser, on request, replacing the
--- tall marble-and-slate column this used to be. The reference is a wide shallow
--- plinth: a broad base course, a slightly inset top course stacked on it, and a
--- raised lip framing a recessed panel the item rests in. Grey studded plastic —
--- `studs = true` forces Material.Plastic and stud-textures every face (see
--- Kit.build), and the greys are Kit.C.standGrey* (mid neutral grey, the one
--- built-not-poured grey object on an otherwise navy-tiled base).
---
--- THE BASE COURSE IS THE STATION PART. It keeps the `Stand{slot}` name and every
--- attribute the world contract (this file's header) publishes. Detection is
--- radius-based off the part CENTRE (StationService, Radius = 7), so dropping that
--- centre from pad.topY + 2 to pad.topY + ~0.5 costs nothing — a player at the
--- plinth sits ~2.5 studs away in Y against a 7-stud reach.
---
--- RISER_SURFACE is the pad-local height of the top course's top face — where the
--- item sits and where ExhibitService pivots a displayed model to. `Display{slot}`
--- rides 1 stud above it, keeping the same item-to-surface gap the old column had
--- (its top was pad.topY + 4, the item pivoted 0.28 above that).
local RISER_BASE = { w = 4.8, h = 0.9 }
local RISER_TOP = { w = 3.9, h = 0.7 }
local RISER_RIM = { h = 0.22, thickness = 0.5 } -- the raised frame around the recessed panel
local RISER_SURFACE = RISER_BASE.h + RISER_TOP.h

local function buildDisplayStand(parent: Instance, origin: CFrame, index: number, slot: number, accent: string)
	local pad = Plots.PAD
	local ox, oz = slotOffset(slot)
	-- Every stand is usable from the start — there is no locked/dim state any more.
	-- Base course darker than the top course and its frame, so the two courses read
	-- as lit from above.
	local topGrey = C.standGrey

	local base = build(parent, origin, {
		name = `Stand{slot}`,
		pos = { ox, pad.topY + RISER_BASE.h / 2, oz },
		size = { RISER_BASE.w, RISER_BASE.h, RISER_BASE.w },
		color = C.standGreyDark,
		material = "Plastic",
		studs = true,
		attributes = {
			StationKind = "pedestal",
			StationId = `{index}:{slot}`,
			PlotIndex = index,
			SlotIndex = slot,
			Radius = 7,
		},
	})

	build(parent, origin, {
		name = `StandTop{slot}`,
		pos = { ox, pad.topY + RISER_BASE.h + RISER_TOP.h / 2, oz },
		size = { RISER_TOP.w, RISER_TOP.h, RISER_TOP.w },
		color = topGrey,
		material = "Plastic",
		studs = true,
	})

	-- Four bars proud of the top course, framing the recessed panel — the routed
	-- border the reference plinth has. CanCollide off so nothing catches on them.
	local frameHalf = RISER_TOP.w / 2 - RISER_RIM.thickness / 2
	local sideLen = RISER_TOP.w - 2 * RISER_RIM.thickness
	for _, bar in {
		{ dx = 0, dz = -frameHalf, sx = RISER_TOP.w, sz = RISER_RIM.thickness },
		{ dx = 0, dz = frameHalf, sx = RISER_TOP.w, sz = RISER_RIM.thickness },
		{ dx = -frameHalf, dz = 0, sx = RISER_RIM.thickness, sz = sideLen },
		{ dx = frameHalf, dz = 0, sx = RISER_RIM.thickness, sz = sideLen },
	} do
		build(parent, origin, {
			name = `StandRim{slot}`,
			pos = { ox + bar.dx, pad.topY + RISER_SURFACE + RISER_RIM.h / 2, oz + bar.dz },
			size = { bar.sx, RISER_RIM.h, bar.sz },
			color = topGrey,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end

	-- The item sits on the panel. Transparent while the slot is empty; ExhibitService
	-- colours it by rarity, or swaps in the real model, when something is displayed —
	-- matching the colour the haul part used when it came out of the ground.
	build(parent, origin, {
		name = `Display{slot}`,
		pos = { ox, pad.topY + RISER_SURFACE + 1, oz },
		size = { 1.4, 1.4, 1.4 },
		color = accent,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		attributes = { PlotIndex = index, SlotIndex = slot },
	})

	-- A dim WARM lift on the plinth (the old column carried an accent-coloured
	-- PointLight here — that stained a grey plinth the plot's accent and fought the
	-- "keep it grey" brief). Warm and low so it reads as a gallery spot on the
	-- panel, not a coloured object.
	light(base, C.lampWarm, 6, 0.35)
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
--- Walk home from the field, dock here, rack the clean item on a pedestal three
--- steps away — no trip back to base camp required, and every player's loop is
--- entirely local to their own plot.
---
--- AT THE TOP, per the sketch: pushed up near the back wall (local z = 25)
--- rather than the pad's middle third, so it's the first thing that reads when
--- you look at the base from the front. Clear of both stand columns (COL_X, at
--- x = ±25) by construction — the station is centred on x = 0 and never
--- overlaps them regardless of how close their rows get to the back wall.
local function buildCleansingStation(parent: Instance, origin: CFrame, accent: string)
	local m = Instance.new("Model")
	m.Name = "CleansingStation"
	local pad = Plots.PAD
	local cz = 20

	-- THE DOCK + THE FLUSH, one part. StationKind="decon" is what DeconService
	-- matches on; Shower=true is what ExposureService scans for.
	local basin = build(m, origin, {
		name = "Basin",
		pos = { 0, pad.topY + 0.9, cz },
		size = { 7, 1.8, 5 },
		color = C.steel,
		material = "Metal",
		attributes = { StationKind = "decon", Shower = true, Radius = 9 },
	})
	billboard(basin, 240, 4.6, "CLEANSING STATION", "clean it, flush it, rack it", accent)

	build(m, origin, { name = "Water", pos = { 0, pad.topY + 1.85, cz }, size = { 6.2, 0.25, 4.2 }, color = C.cyan, material = "Neon", transparency = 0.35 })

	for _, x in { -3.2, 3.2 } do
		build(m, origin, { name = "Post", pos = { x, pad.topY + 3.5, cz + 1.5 }, size = { 0.4, 4, 0.4 }, color = C.steelDark, material = "Metal" })
	end
	build(m, origin, { name = "GantryBeam", pos = { 0, pad.topY + 5.4, cz + 1.5 }, size = { 7.2, 0.4, 0.4 }, color = C.steelDark, material = "Metal" })
	build(m, origin, { name = "NozzleArm", pos = { 0, pad.topY + 5.4, cz + 0.7 }, size = { 0.35, 0.35, 1.6 }, color = C.steelDark, material = "Metal" })
	build(m, origin, {
		name = "ShowerHead",
		pos = { 0, pad.topY + 5.1, cz },
		size = { 0.5, 1.6, 1.6 },
		color = C.steel,
		material = "Metal",
		shape = "Cylinder",
		rot = Kit.R.cylUpFlipped,
		canCollide = false,
	})
	build(m, origin, {
		name = "Jet",
		pos = { 0, pad.topY + 3.3, cz },
		size = { 0.16, 2.8, 0.16 },
		color = C.cyan,
		material = "Neon",
		transparency = 0.5,
		canCollide = false,
	})

	-- Lamp in the plot's own accent colour, so the station reads as part of
	-- THIS base rather than a generic fixture repeated six times.
	local lamp = build(m, origin, {
		name = "Lamp",
		pos = { 0, pad.topY + 5.9, cz + 1.5 },
		size = { 0.5, 0.5, 0.5 },
		color = accent,
		material = "Neon",
		shape = "Ball",
		canCollide = false,
	})
	light(lamp, accent, 14, 1.6)

	m.Parent = parent
end

--- THE QUARANTINE LOCKER (PLAN §10.2) — a steel cabinet beside the cleansing
--- station holding what you hauled home but can't clean yet. THIS FILE BUILDS THE
--- SHELL; the data (`data.locker`), the `rack` action and the dirty-sell already
--- exist. ExhibitService.renderLocker fills `LockerSlot1..LOCKER_SLOTS` from the
--- owner's `data.locker` and swings `LockerDoor` to `OpenPivot` whenever the
--- locker holds anything, `ClosedPivot` when it's empty — a full locker reads as a
--- red-lined taunt from across the base, an empty one is just a shut cabinet.
---
--- NO STATION ATTRIBUTES. Racking still happens at the cleansing station
--- (DeconService gates it on `StationKind == "decon"`); this cabinet is a display,
--- not a stop. Placed against the back wall LEFT of the cleansing station, opening
--- toward the plot entrance (-Z), clear of the gantry posts (x = ±3.2) and the
--- left stand column (x = -25) by ~8 studs each — World.verify() re-checks nothing
--- overlaps on every rebuild.
---
--- THE DOOR IS ITS OWN MODEL, built CLOSED in a frame anchored at the hinge (the
--- -X edge of the opening), so a yaw about that frame's own vertical axis swings
--- it. The two pivots are stamped as CFrame attributes, so ExhibitService never
--- has to know which way this plot faces.
local function buildQuarantineLocker(parent: Instance, origin: CFrame, accent: string)
	local m = Instance.new("Model")
	m.Name = "QuarantineLocker"
	local pad = Plots.PAD

	local lx, lz = -13, 22.5
	local baseY = pad.topY + 0.4 -- top of the plinth; the cabinet's own floor sits here
	local midY = baseY + 2.7 -- centre of the 5.4-tall body

	build(m, origin, { name = "Plinth", pos = { lx, pad.topY + 0.2, lz }, size = { 3.2, 0.4, 2.4 }, color = C.baseTileDark, material = "Metal" })

	-- The open-front box.
	build(m, origin, { name = "Back", pos = { lx, midY, lz + 0.85 }, size = { 2.6, 5.4, 0.2 }, color = C.steelDark, material = "Metal" })
	for _, sx in { -1, 1 } do
		build(m, origin, { name = "Side", pos = { lx + sx * 1.3, midY, lz }, size = { 0.2, 5.4, 1.9 }, color = C.steelDark, material = "Metal" })
	end
	build(m, origin, { name = "Floor", pos = { lx, baseY + 0.1, lz }, size = { 2.6, 0.2, 1.9 }, color = C.steelDark, material = "Metal" })
	build(m, origin, { name = "Ceiling", pos = { lx, baseY + 5.3, lz }, size = { 2.6, 0.2, 1.9 }, color = C.steelDark, material = "Metal" })

	-- Red interior lining — the one saturated colour in the base.
	build(m, origin, { name = "Lining", pos = { lx, midY, lz + 0.7 }, size = { 2.4, 5.0, 0.1 }, color = C.quarantineRed, material = "SmoothPlastic" })
	build(m, origin, { name = "LiningFloor", pos = { lx, baseY + 0.25, lz }, size = { 2.4, 0.12, 1.6 }, color = C.quarantineRed, material = "SmoothPlastic" })

	-- Two shelves split the interior into LOCKER_SLOTS bays; a hidden anchor sits on
	-- the floor of each. renderLocker seats a scaled item model on the anchor's
	-- bottom face (anchor.Position.Y - anchor.Size.Y/2), so the anchor cube marks
	-- the bay floor and needs no shared magic offset with ExhibitService.
	local bayFloorY = { baseY + 0.31 }
	for i = 1, Plots.LOCKER_SLOTS - 1 do
		local shelfY = baseY + 0.31 + i * 1.6
		build(m, origin, { name = `Shelf{i}`, pos = { lx, shelfY, lz }, size = { 2.4, 0.1, 1.6 }, color = C.steel, material = "Metal" })
		table.insert(bayFloorY, shelfY + 0.05)
	end
	for i, floorY in bayFloorY do
		build(m, origin, {
			name = `LockerSlot{i}`,
			pos = { lx, floorY + 0.45, lz },
			size = { 0.9, 0.9, 0.9 },
			color = accent,
			material = "SmoothPlastic",
			transparency = 1,
			canCollide = false,
		})
	end

	-- Header plate over the opening.
	local sign = build(m, origin, { name = "Sign", pos = { lx, baseY + 5.7, lz - 0.95 }, size = { 2.6, 0.55, 0.1 }, color = C.steelDark, material = "Metal" })
	Kit.surfaceText(sign, Enum.NormalId.Front, "QUARANTINE", C.quarantineRed)

	-- THE DOOR. Hinge = the -X edge of the opening; build parts extending +X from it
	-- (closed, across the opening). Slab is a hair wider than the gap so a shut
	-- locker reads solid.
	local hinge = origin * CFrame.new(lx - 1.3, midY, lz - 0.9)
	local door = Instance.new("Model")
	door.Name = "LockerDoor"

	build(door, hinge, { name = "Slab", pos = { 1.25, 0, 0 }, size = { 2.5, 5.2, 0.14 }, color = C.steel, material = "Metal" })
	for _, bankY in { 1.5, -1.4 } do
		for s = 0, 3 do
			build(door, hinge, {
				name = "Louver",
				pos = { 1.25, bankY - s * 0.34, -0.16 },
				size = { 2.0, 0.12, 0.18 },
				color = C.steelDark,
				material = "Metal",
				rot = Kit.ang(-22, 0, 0),
				canCollide = false,
			})
		end
	end

	door.WorldPivot = hinge
	door:SetAttribute("ClosedPivot", hinge)
	door:SetAttribute("OpenPivot", hinge * CFrame.Angles(0, math.rad(110), 0))
	door.Parent = m

	m.Parent = parent
end

local function buildPlot(parent: Instance, index: number)
	local m = Instance.new("Model")
	m.Name = `Plot{index}`

	local center = Plots.CENTERS[index]
	-- The yaw is applied to the ORIGIN, so every part in this function stays written
	-- in the pad's own space and the whole plot turns as one. Rotating the parts
	-- individually would leave the claim board, the spawn and the stands facing
	-- whichever way each was authored.
	local origin = CFrame.new(center.x, 0, center.z) * CFrame.Angles(0, math.rad(center.facing), 0)
	local accent = Kit.PLOT_ACCENT[((index - 1) % #Kit.PLOT_ACCENT) + 1]
	local pad = Plots.PAD

	-- THE STAGE, WEARING THE SAME BOARD AS THE PLAZA IN ITS OWN COLOURS. One step up
	-- from the apron — a plot should feel like somewhere you walk onto, not part of
	-- the pavement — and navy-and-grey against the courtyard's green, so the six bases
	-- are the one thing in the world that is not some shade of it.
	--
	-- BUILT IN THIS MODEL'S YAWED LOCAL SPACE, THROUGH `origin`, LIKE EVERYTHING ELSE
	-- IN THIS FUNCTION — the opposite of how this used to work (see this file's own
	-- header on why: a pad's footprint stopped being axis-aligned in world space the
	-- moment the ring stopped using only 90-degree facings). `rect` is a LOCAL
	-- rectangle centred on the pad's own origin, not a world-space one.
	local rect: Hub.Rect = { minX = -HALF_W, maxX = HALF_W, minZ = -HALF_D, maxZ = HALF_D }
	local tint: Hub.TileOpts = { topY = pad.topY, dark = C.baseTileDark, light = C.baseTileLight, origin = origin }

	-- The slab underneath carries PlotIndex, because that is the world contract this
	-- file's header publishes and a folder of 350 tiles cannot carry it.
	local slab = Hub.groundSlab(m, rect, "Pad", pad.thickness, tint)
	slab:SetAttribute("PlotIndex", index)

	local tiles = Instance.new("Folder")
	tiles.Name = "PadTiles"
	Hub.tileRect(tiles, rect, tint)
	tiles.Parent = m

	-- Accent trim, so whose plot is whose is readable from across the plaza.
	for _, side in { -1, 1 } do
		build(m, origin, {
			name = "Trim",
			pos = { side * (pad.width / 2 - 0.5), pad.topY + 0.1, 0 },
			size = { 1, 0.5, pad.depth },
			color = accent,
			material = "Neon",
			canCollide = false,
		})
	end

	-- Back wall and the nameplate the owner's display name goes on.
	local wall = build(m, origin, {
		name = "BackWall",
		pos = { 0, pad.topY + 5, pad.depth / 2 - 0.5 },
		size = { pad.width, 10, 1 },
		color = C.plazaWarm,
		material = "Concrete",
	})
	local sign = build(m, origin, {
		name = "NameSign",
		pos = { 0, pad.topY + 8, pad.depth / 2 - 1.4 },
		size = { 34, 4, 0.4 },
		color = accent,
		material = "Neon",
	})
	Kit.surfaceText(sign, Enum.NormalId.Front, "UNCLAIMED", C.signText)
	-- Dialled back from 22/1.6 and 18/0.8: the back-third accent wash was bright
	-- enough to bounce the plot's colour onto the grey display plinths in front of
	-- it (the Neon sign and Trim carry the "whose plot is this" cue on their own;
	-- these lights only need to lift the nameplate and give the wall a gentle
	-- tint, not floodlight the whole back of the pad).
	light(sign, accent, 20, 1.0)
	light(wall, accent, 14, 0.4)

	-- The claim board: collect the exhibit's banked income.
	local board = build(m, origin, {
		name = "ClaimBoard",
		pos = { 0, pad.topY + 2, -pad.depth / 2 + 3 },
		size = { 8, 4, 1 },
		color = accent,
		material = "Metal",
		attributes = {
			StationKind = "plot",
			StationId = tostring(index),
			PlotIndex = index,
			Radius = 10,
		},
	})
	billboard(board, 240, 4.4, `PLOT {index}`, "collect banked income", accent)

	-- Where this plot's owner respawns. Disabled until somebody owns it, so nobody
	-- ever lands on a stranger's stage. ExhibitService flips this on assignment.
	local spawn = build(m, origin, {
		name = "PlotSpawn",
		class = "SpawnLocation",
		pos = { 0, pad.topY + 0.5, -pad.depth / 2 + 8 },
		size = { 6, 1, 6 },
		color = accent,
		material = "Neon",
		transparency = 0.4,
		canCollide = false,
		attributes = { PlotIndex = index },
	}) :: SpawnLocation
	spawn.Enabled = false
	spawn.Neutral = true

	-- Every stand is usable from the start. See buildDisplayStand for the plinth's form.
	for slot = 1, math.min(Plots.VISIBLE_SLOTS, Tuning.EXHIBIT_MAX_SLOTS) do
		buildDisplayStand(m, origin, index, slot, accent)
	end

	buildCleansingStation(m, origin, accent)
	buildQuarantineLocker(m, origin, accent)

	m.Parent = parent
	return m
end

--- Lay the apron. Lives in this file rather than in Hub.luau because the disc is
--- derived from the pad ring, and Hub cannot see the ring: Plots requires Hub, so a
--- require back the other way would be a cycle. Hub owns the PATTERN and exports it;
--- this file owns the SHAPE and asks for it to be tiled.
---
--- THE VISIBLE CAP is one `Hub.tileRect` call over a square bounding RING_OUTER,
--- clipped at `maxX = PLAZA.maxX` (Stage 1's own west edge, touching not
--- crossing it — the same shared-edge convention the plaza's own east side
--- already uses) and punched by `apronSkip` (plaza + every pad's own oriented
--- footprint) — see that function's own comment above.
---
--- `pad = true` on that call is the other half of Hub's grey central spine: the
--- plaza paints the band down its own stretch, this carries it a little further north
--- and south onto the apron — same grid, same `Hub.inPad` test (which caps the length
--- at the Camp -> Stage 1 hazard border, well short of the bases) — so the strip runs
--- unbroken across the plaza/apron seam and stops clean. Where it does reach, the band
--- flows around any plot footprint exactly like the green does, since `apronSkip`
--- punches those out before the colour is ever chosen.
---
--- CLIPPED AT THE FIELD, NOT AT RING_CENTER, ON REQUEST. The disc used to stop
--- dead at `RING_CENTER.x`, which is west of the plaza's own east edge — the
--- plaza itself (165x140, its own fixed rectangle) was the only thing carrying
--- the ground from there out to Stage 1, and it is narrower in Z (+/-70) than
--- either the disc beside it or the field beyond it, so it read as a bridge
--- with void visible on both sides. Moving the clip out to PLAZA.maxX lets the
--- SAME circle (still centred on RING_CENTER, still radius RING_OUTER) keep
--- tapering outward past the plaza's own edges instead of stopping there —
--- `apronSkip`'s existing `insidePlaza` check already excludes the plaza's own
--- footprint from this pass, so this only ever fills genuinely empty ground
--- flanking it, never doubles up on the plaza's own floor.
---
--- THE STRUCTURAL BACKING underneath is N horizontal bands rather than one big
--- rectangle, each inscribed so its own farthest corner lands exactly on the
--- RING_OUTER circle — a single bounding rectangle would round the disc's curve
--- out to a square and leave the tiled cap's corners floating over open air.
--- Purely cosmetic backing (World.verify() never inspects apron shape): if it
--- ever needs to look tidier from underneath, BANDS is the one knob to turn.
local function buildApron(row: Model)
	local apron = Instance.new("Folder")
	apron.Name = "Apron"

	local discBounds: Hub.Rect = {
		minX = Plots.RING_CENTER.x - Plots.RING_OUTER,
		maxX = PLAZA.maxX,
		minZ = Plots.RING_CENTER.z - Plots.RING_OUTER,
		maxZ = Plots.RING_CENTER.z + Plots.RING_OUTER,
	}
	Hub.tileRect(apron, discBounds, { skip = apronSkip, pad = true })

	local BANDS = 12
	local bandHeight = (2 * Plots.RING_OUTER) / BANDS
	for i = 0, BANDS - 1 do
		local zLo = Plots.RING_CENTER.z - Plots.RING_OUTER + i * bandHeight
		local zHi = zLo + bandHeight
		local reach = math.max(math.abs(zLo - Plots.RING_CENTER.z), math.abs(zHi - Plots.RING_CENTER.z))
		if reach < Plots.RING_OUTER then
			local safeHalfX = math.sqrt(Plots.RING_OUTER ^ 2 - reach ^ 2)
			Hub.groundSlab(apron, {
				minX = Plots.RING_CENTER.x - safeHalfX,
				maxX = PLAZA.maxX,
				minZ = zLo,
				maxZ = zHi,
			}, `ApronSlab{i + 1}`)
		end
	end

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
		`[build] Plots rebuilt — {Plots.COUNT} plots, {Plots.VISIBLE_SLOTS} stands each `
			.. `(all free), `
			.. `{Plots.LOCKER_SLOTS}-bay quarantine locker each, `
			.. `{#row.Apron:GetChildren()} apron parts`
	)
	return row
end

return Plots
