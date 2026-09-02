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

	Plot INTERNALS still face south (spawn near the front) —
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
	    Stand       StationKind = "pedestal", StationId = "<n>:<slot>", Radius = 7
	                PlotIndex = n, SlotIndex = s
	                — the base course of the display plinth (StandTop / StandRim /
	                Display are the rest of it); see buildDisplayStand.
	    PlotSpawn   SpawnLocation, Enabled = false until the plot is claimed
	    Basin       StationKind = "decon", Shower = true, Radius = 9 — the cleansing
	                station (see buildCleansingStation below). One per base, replacing
	                the single shared station + shower that used to live at camp.
	                Carries a "Wash" ProximityPrompt; WashService wires it at boot.
	    WashStand   IsWashStand = true — invisible; where the item sits during a wash.
	    WashSpot    invisible; where the player is planted during a wash, facing the tub.
	    WashCam     invisible; the side-on camera anchor WashController frames from.
	    Hose        a Model beside the basin, PrimaryPart "Nozzle" — the fire hose
	                (see buildHoseRig). The nozzle carries Muzzle / HoseEnd
	                attachments and stays ANCHORED on the pump; WashService clones it
	                into the player's hand for a session. The green line itself is a
	                Beam ("HoseLine") on HoseReel, from HoseAnchor to whichever
	                nozzle — parked or held — is currently the live one.
	    Plate       StationKind = "roller", Radius = 6 — the wash pad (see
	                buildWashPad below). One per base, three steps from the basin.
	    Button      SellsTrack = "Luck" + a ProximityPrompt — the luck button
	                (see buildLuckButton). ShopService wires the prompt at boot.
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
local Liquids = require(Shared.Config.Liquids)
local Gear = require(Shared.Config.Gear)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local Plots = {}
local BUILDER_SOURCE = "src/server/build/Plots.luau"
local BUILDER_VERSION = 21

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
--- spawn at -Z, so 0 faces south, 180 faces north, -90 faces east — and
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

--- The fire hose and the pump that feeds it (see buildCleansingStation, which calls
--- this). A pump unit standing behind the player's wash mark, a reel of green hose
--- coiled on it, and a brass-tipped nozzle that lives parked on the pump's cap until
--- somebody picks it up.
---
--- IT IS A REAL OBJECT IN THE WORLD, NOT AN EFFECT DRAWN FOR THE DURATION OF A WASH,
--- and that is the whole reason it is built here rather than spawned by WashService.
--- Three things fall out of it that a per-session client effect cannot give:
---
---   * The station reads as a wash bay when nobody is using it. A tub with a hose
---     coiled beside it explains itself; a bare tub does not.
---   * A visitor standing on your plot sees you holding a fire hose, which is
---     ToolService's "what you hold is public storytelling" rule applied to the one
---     object in this feature that the player is actually holding.
---   * Nothing has to define the hose's colours twice. Kit.C is here; a service is
---     not (see ShopService's own note on why it hardcodes UPGRADE_TAG).
---
--- WashService borrows the nozzle for a session: it CLONES the parked one into the
--- player's hand, stashes the original, and re-points the beam's far end at the copy
--- so the line follows the hand. That is all it does; the geometry, the colours and
--- the beam are this file's business.
---
--- A COPY RATHER THAN THE PARKED NOZZLE ITSELF, and the reason is a genuinely nasty
--- failure rather than tidiness. The station's nozzle is Anchored, and an anchored
--- part anchors its whole assembly — so the moment anything joints it to a character
--- (WashController adds a local Motor6D to aim it), that character is bolted to the
--- world until the joint goes away. Handing out an unanchored copy parented into the
--- character makes it exactly the same kind of object as ToolService's HeldTool, with
--- the same lifetime: it dies with the character, and nothing can strand a player.
---
--- THE HOSE ITSELF IS A Beam, NOT A CHAIN OF PARTS, and it costs nothing per frame
--- because of it. A Beam spans two Attachments and re-renders itself whenever either
--- one moves — one of them is bolted to the reel and the other rides the nozzle in
--- the player's hand, so the hose follows the hand for free, on every client, with no
--- script running anywhere. `CurveSize0/1` give it the slack a hose has when it is
--- not under tension; a chain of parts would need a per-frame catenary solve to fake
--- the same thing and would still be jointed.
local function buildHoseRig(parent: Instance, origin: CFrame, cz: number)
	local pad = Plots.PAD

	-- EIGHT STUDS BEHIND THE PLAYER'S MARK, AND JUST PAST IT IN DEPTH. WashSpot is at
	-- (0, cz - 6) and the wash camera sits out at local x = -13 looking across, so the
	-- shot's depth axis is x and its horizontal axis is z. That makes the placement
	-- almost entirely a framing decision:
	--
	--   z    how far back along the hose's run, which is screen-LEFT of the player.
	--        Eight studs, because three (the first attempt) plus a little slack is a
	--        shower attachment, and the brief was a long green line trailing away.
	--   x    depth. The first attempt put the pump at x = -5, on the CAMERA's side --
	--        which dropped it to about 8 studs from the lens against the player's 13,
	--        and at that depth "eight studs back" is far enough sideways to fall off
	--        the edge of the frame entirely. Slightly POSITIVE keeps it at roughly the
	--        player's own depth, where the same eight studs is a comfortable distance
	--        into open frame, and puts the hose's run on the far side of the player
	--        rather than between them and the camera.
	--
	-- +3.5 rather than 0 also keeps the pump off the straight walk-up line from the
	-- front of the pad to the tub. Clear of everything else by a wide margin: the wash
	-- pad is at (18, 18), the display columns at x = +/-25, the stand rows at
	-- z = 15/5/-5/-15, and the plot spawn at z = -18.
	local px, pz = 3.5, cz - 14

	-- TALL AND NARROW, so the reel bolted to its side reads as a smaller wheel on a
	-- bigger box. The first version was a squat 2.6-high crate with a 3.2-wide reel
	-- across it, and the reel simply swallowed it: what rendered was one pale steel
	-- disc lying on the tiles with a sliver of green behind, which reads as a barrel.
	build(parent, origin, {
		name = "HosePump",
		pos = { px, pad.topY + 1.6, pz },
		size = { 2.4, 3.2, 2.0 },
		color = C.steelDark,
		material = "Metal",
	})
	build(parent, origin, { name = "PumpCap", pos = { px, pad.topY + 3.35, pz }, size = { 2.6, 0.3, 2.2 }, color = C.steel, material = "Metal" })
	build(parent, origin, {
		name = "PumpGauge",
		pos = { px, pad.topY + 2.6, pz - 1.05 },
		size = { 0.16, 0.8, 0.8 },
		color = C.hazard,
		material = "SmoothPlastic",
		shape = "Cylinder",
		-- yaw90, for the same reason the nozzle uses it -- see the note there.
		rot = Kit.R.yaw90,
		canCollide = false,
	})

	-- THE DRUM IS THE ONLY THING THAT SAYS THE HOSE IS LONG. The Beam below draws
	-- exactly one span — reel to nozzle — and a hose that is only ever a few studs
	-- long is a shower attachment. A visibly wound drum is where the rest of it is.
	--
	-- HUNG OFF THE PUMP'S -X FACE, WHICH IS THE ONE THE WASH CAMERA IS ON (WashCam
	-- sits out at x = -13). A reel is only legible face-on: side-on it is just a green
	-- cylinder. Mounting it on top would also have put it through the parked nozzle.
	--
	-- SMALL STEEL HUBS, NOT FLANGES, and this is the second thing that went wrong
	-- here. A real reel's flanges are wider than the drum — but a Cylinder part cannot
	-- be a ring, so a wide flange is a SOLID disc that occludes the entire drum from
	-- exactly the one angle the reel is legible from. Two passes of shrinking the
	-- margin (3.2 against 2.6, then 2.3 against 2.0) both produced the same picture:
	-- a pale steel plate with a rim of green behind it. So the geometry gives up on
	-- being correct and goes for being READABLE: the green drum is the widest thing,
	-- with a small steel hub capping each end, which is what a spool of wound hose
	-- actually looks like from the front.
	local rx = px - 1.55
	local ry = pad.topY + 1.9
	local reel = build(parent, origin, {
		name = "HoseReel",
		pos = { rx, ry, pz },
		size = { 1.0, 2.4, 2.4 },
		color = C.hoseGreen,
		material = "SmoothPlastic",
		shape = "Cylinder",
		canCollide = false,
	})
	-- A narrower dark band on the same axis: face-on that is a dark green disc inside
	-- a lighter green ring, which reads as coils wound over each other. One flat
	-- colour reads as a painted spool.
	build(parent, origin, {
		name = "HoseCoil",
		pos = { rx, ry, pz },
		size = { 1.06, 1.7, 1.7 },
		color = C.hoseGreenDark,
		material = "SmoothPlastic",
		shape = "Cylinder",
		canCollide = false,
	})
	for _, side in { -0.56, 0.56 } do
		build(parent, origin, {
			name = "ReelHub",
			pos = { rx + side, ry, pz },
			size = { 0.14, 0.9, 0.9 },
			color = C.steel,
			material = "Metal",
			shape = "Cylinder",
			canCollide = false,
		})
	end
	build(parent, origin, {
		name = "ReelAxle",
		pos = { px - 0.9, ry, pz },
		size = { 1.5, 0.3, 0.3 },
		color = C.steelDark,
		material = "Metal",
		shape = "Cylinder",
		canCollide = false,
	})

	-- Where the hose leaves the drum: off the bottom of the rim, on the tub side.
	--
	-- ITS ROTATION IS LOAD-BEARING, not decoration. A Beam's curve control point is
	-- `WorldPosition + WorldCFrame.LookVector * CurveSize`, so the attachment's FACING
	-- decides which way the slack bulges. Left at the default it would look straight
	-- back off the drum and throw the loop away from the tub, behind the pump. Aimed
	-- down and forward, the line leaves the reel, dips toward the floor, and comes up
	-- into the hand — which is where a hose lying slack actually goes. Local axes are
	-- the plot's here: the drum is a Cylinder in its native, unrotated orientation.
	local anchor = Instance.new("Attachment")
	anchor.Name = "HoseAnchor"
	-- Shallow: mostly toward the tub, only a little downward. The attachment sits at
	-- y = 0.95 above the pad and the held CurveSize is 5, so anything steeper than
	-- about 10 degrees throws the control point through the floor the pump is standing
	-- on and the slack loop dips underground.
	anchor.CFrame = CFrame.lookAt(Vector3.new(0, -0.95, 0.8), Vector3.new(0, -1.55, 4.8))
	anchor.Parent = reel

	-- ── The nozzle ────────────────────────────────────────────────────
	-- Parked on the pump cap, lying along the plot's -Z (toward the front of the
	-- base), which is also the axis WashController aims it down: CFrame.lookAt puts
	-- its target on -Z, so "the nozzle's -Z is the business end" has to hold both
	-- parked and held, or the spray comes out of the grip.
	local hose = Instance.new("Model")
	hose.Name = "Hose"

	-- Resting on the pump cap (its top face is at pad.topY + 3.5), nudged forward so
	-- the brass end overhangs the front edge rather than burying itself in the cap.
	local nx, ny, nz = px, pad.topY + 3.78, pz - 0.2

	-- THE PRIMARY PART IS AN INVISIBLE, UNROTATED BLOCK, and that is deliberate. The
	-- visible tube is a Cylinder, whose native axis is X and which therefore has to be
	-- rotated to lie along Z — and once it is rotated, every attachment offset on it
	-- would have to be written in a twisted local frame. An axis-aligned anchor block
	-- keeps `Muzzle` at a plain (0, 0, -1.4) that anyone can read, and gives the
	-- hand-weld and the aim Motor6D one unambiguous frame to work in.
	local core = build(hose, origin, {
		name = "Nozzle",
		pos = { nx, ny, nz },
		size = { 0.3, 0.3, 0.3 },
		color = C.hoseGreenDark,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
	})

	-- ROTATION: yaw90, NOT Kit.R.cylAlongZ, WHOSE NAME IS A LIE. A Part's Cylinder
	-- shape runs along its own local X, and `cylAlongZ` is ang(90, 90, 0) -- which
	-- composes (XYZ order) to send that X axis to +Y, i.e. it stands the cylinder UP.
	-- The nozzle built with it hung vertically off the fist while the muzzle attachment
	-- pointed correctly at the target, so the water came out sideways from a tube that
	-- was not aimed at anything. `yaw90` is ang(0, 90, 0), which sends X to -Z, which
	-- is genuinely front-to-back. Left the preset alone rather than corrected: it is
	-- also used by build/Scenery's tipped barrels, and whatever those look like today
	-- is not this feature's to change.
	local shell = {
		{ name = "NozzleBody", pos = { nx, ny, nz + 0.15 }, size = { 1.7, 0.68, 0.68 }, color = C.hoseGreenDark, material = "SmoothPlastic", shape = "Cylinder", rot = Kit.R.yaw90 },
		{ name = "NozzleGrip", pos = { nx, ny - 0.55, nz + 0.55 }, size = { 0.4, 0.9, 0.5 }, color = C.hoseGreenDark, material = "SmoothPlastic", shape = "Block", rot = Kit.R.flat },
		{ name = "NozzleCollar", pos = { nx, ny, nz + 1.05 }, size = { 0.4, 0.86, 0.86 }, color = C.hoseBrass, material = "Metal", shape = "Cylinder", rot = Kit.R.yaw90 },
		{ name = "NozzleTaper", pos = { nx, ny, nz - 0.95 }, size = { 0.95, 0.52, 0.52 }, color = C.hoseBrass, material = "Metal", shape = "Cylinder", rot = Kit.R.yaw90 },
		{ name = "NozzleTip", pos = { nx, ny, nz - 1.45 }, size = { 0.2, 0.66, 0.66 }, color = C.hoseBrass, material = "Metal", shape = "Cylinder", rot = Kit.R.yaw90 },
	}
	for _, spec in shell do
		local part = build(hose, origin, {
			name = spec.name,
			pos = spec.pos,
			size = spec.size,
			color = spec.color,
			material = spec.material,
			shape = spec.shape,
			rot = spec.rot,
			canCollide = false,
		})
		-- Welded to the core, never anchored themselves. Anchoring ONE part of a welded
		-- assembly pins the whole assembly, so parking the nozzle is `core.Anchored =
		-- true` and picking it up is `false` plus a weld to the hand — one property on
		-- one part either way, with no risk of half the nozzle being left behind.
		part.Anchored = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Name = "ShellWeld"
		weld.Part0 = core
		weld.Part1 = part
		weld.Parent = part
	end
	core.Massless = true

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = CFrame.new(0, 0, -1.6)
	muzzle.Parent = core

	local hoseEnd = Instance.new("Attachment")
	hoseEnd.Name = "HoseEnd"
	hoseEnd.CFrame = CFrame.new(0, 0, 1.3)
	hoseEnd.Parent = core

	-- Darker at both ends than in the middle. It is not real cylinder shading — a Beam
	-- is a camera-facing ribbon and cannot have any — but a ribbon with a lighter band
	-- down its centre reads as a round tube catching the sky, and a flat one reads as a
	-- painted strip. Cheapest possible fix for the one weakness of drawing a hose this
	-- way, and the only reason `hoseGreen` and `hoseGreenDark` are both in the palette.
	local beam = Instance.new("Beam")
	beam.Name = "HoseLine"
	beam.Attachment0 = anchor
	beam.Attachment1 = hoseEnd
	-- Fat. A fire hose is a thick, heavy thing and a thin ribbon reads as cable; this
	-- is roughly the diameter of the nozzle it feeds into, which is what stops the two
	-- looking like different objects joined by a wire.
	beam.Width0 = 0.62
	beam.Width1 = 0.5
	-- Slack, not tension. Positive out of the reel throws the loop the way HoseAnchor
	-- is aimed (down and toward the tub); NEGATIVE into the nozzle throws the other
	-- control point BACKWARD from HoseEnd, whose LookVector is the direction the
	-- nozzle is pointing — so the line arrives from behind the player's hand rather
	-- than curling around in front of it. That pair is the whole shape of the hose.
	--
	-- TWO SETS OF NUMBERS, BECAUSE THE TWO STATES ARE NOT THE SAME SHAPE. A Bezier's
	-- control points are absolute distances, not fractions of the span, so one pair
	-- cannot serve both: the held run is eight-plus studs and wants a long lazy sag,
	-- while the parked run is barely three studs from the drum up to the cap, and the
	-- held numbers on THAT threw the line out sideways into the tiles — the parked
	-- hose looked broken. The properties carry the parked pair; WashService reads the
	-- attributes when it hands the nozzle over and puts the parked pair back after.
	-- Both live here, in the builder, next to the geometry they are measured against,
	-- exactly like the HoldCFrame and ClosedPivot/OpenPivot attributes elsewhere.
	beam.CurveSize0 = 1.4
	beam.CurveSize1 = -1.4
	beam:SetAttribute("HeldCurve0", 5)
	beam:SetAttribute("HeldCurve1", -6)
	beam.Segments = 24
	beam.FaceCamera = true
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex(C.hoseGreenDark)),
		ColorSequenceKeypoint.new(0.5, Color3.fromHex(C.hoseGreen)),
		ColorSequenceKeypoint.new(1, Color3.fromHex(C.hoseGreenDark)),
	})
	beam.Transparency = NumberSequence.new(0)
	-- Lit like every other surface out here. The world went matte on purpose (Kit's
	-- palette header) and a self-lit hose would be the one glowing object on a base
	-- whose only glowing thing is meant to be the fallout.
	beam.LightInfluence = 1
	beam.Parent = reel

	hose.PrimaryPart = core
	hose.Parent = parent
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

	-- TUB WALLS. The basin used to be a bare slab with a blue plate on top, which read
	-- as a table, not as something you wash a thing IN. Four low rims turn the same
	-- footprint into a bath — and now that pressing E here starts a hosing animation
	-- with the object sitting in it, "is this a container" stopped being cosmetic.
	for _, side in { -1, 1 } do
		build(m, origin, { name = "TubRim", pos = { side * 3.3, pad.topY + 2.1, cz }, size = { 0.5, 1.0, 5.2 }, color = C.steel, material = "Metal" })
		build(m, origin, { name = "TubRim", pos = { 0, pad.topY + 2.1, cz + side * 2.35 }, size = { 7.0, 1.0, 0.5 }, color = C.steel, material = "Metal" })
	end

	build(m, origin, { name = "Water", pos = { 0, pad.topY + 1.85, cz }, size = { 6.2, 0.25, 4.2 }, color = C.cyan, material = "Glass", transparency = 0.35 })

	-- THREE ANCHORS, AND THE SHOT IS COMPOSED OUT OF THEM RATHER THAN OUT OF NUMBERS
	-- IN THE CONTROLLER. Framing is a thing you judge by looking at it, so it has to
	-- be nudgeable in Studio against live geometry — the same reasoning ARCHITECTURE.md
	-- gives for the tool models' HoldCFrame attribute.
	--
	--   WashStand  where the item sits
	--   WashSpot   where the PLAYER stands, facing the tub
	--   WashCam    a SIDE-ON camera that frames both of them
	--
	-- WHY THE PLAYER GETS PINNED TO A SPOT. The first version let you trigger the
	-- prompt from anywhere inside 11 studs and then framed the shot from in front of
	-- the tub — which put the camera roughly where the player was standing, so you saw
	-- a tub, no character, and no hose. A fixed mark is what makes the shot reliable:
	-- the camera knows where both subjects are because the geometry decided, not the
	-- player's approach angle.

	-- A RACK TO STAND THE ITEM ON, and it is not decoration. The stand used to sit at
	-- pad.topY + 2.6, which is exactly the height of the tub rims built above -- so an
	-- item on it was half sunk behind the near rim, and water arriving from the side
	-- hit that rim about a stud out of the nozzle instead of reaching the item at all.
	-- The plate lifts the whole thing clear and gives the float a reason.
	build(m, origin, {
		name = "WashRack",
		pos = { 0, pad.topY + 2.7, cz },
		size = { 2.6, 0.2, 2.6 },
		color = C.steelDark,
		material = "Metal",
		canCollide = false,
	})

	local stand = build(m, origin, {
		name = "WashStand",
		pos = { 0, pad.topY + 3.5, cz },
		size = { 1, 1, 1 },
		color = C.steel,
		material = "Metal",
		transparency = 1,
		canCollide = false,
	})
	stand:SetAttribute("IsWashStand", true)

	local spot = build(m, origin, {
		name = "WashSpot",
		pos = { 0, pad.topY + 3, cz - 6 },
		size = { 1, 1, 1 },
		color = C.steel,
		material = "Metal",
		transparency = 1,
		canCollide = false,
	})
	-- Faces the stand, so WashService can drop the character straight onto this CFrame
	-- and have them looking at what they are about to hose.
	spot.CFrame = origin * CFrame.lookAt(Vector3.new(0, pad.topY + 3, cz - 6), Vector3.new(0, pad.topY + 3, cz))

	local cam = build(m, origin, {
		name = "WashCam",
		pos = { -13, pad.topY + 5, cz - 3 },
		size = { 1, 1, 1 },
		color = C.steel,
		material = "Metal",
		transparency = 1,
		canCollide = false,
	})
	-- SIDE-ON, off to the left, aimed at the midpoint between the player's mark and
	-- the item. That is the shot the design asked for: you see your own character
	-- holding the hose in profile and the object across from them, with the stream
	-- crossing the frame between the two. A camera in front of the tub cannot show
	-- that, because the player is behind it.
	--
	-- Composed here with CFrame.lookAt rather than given to Kit.build as a `rot`,
	-- because Kit.build's rot takes fixed angles and "point at that" stops being a
	-- fixed angle once the plot's own yaw is applied. `origin` carries it to world
	-- space like everything else in this function.
	cam.CFrame = origin * CFrame.lookAt(Vector3.new(-13, pad.topY + 5, cz - 3), Vector3.new(0, pad.topY + 3.6, cz - 3))

	-- PRESS E TO WASH, AND PRESS IT AGAIN TO STOP. Always enabled, because a
	-- ProximityPrompt is one shared instance and cannot be shown to one player and
	-- hidden from another — so the "are you actually holding something dirty" test is
	-- the SERVER's, on trigger, and it answers with a toast. That is also what makes
	-- "nothing happens if you hold nothing" honest rather than a silent no-op.
	--
	-- The re-press is not a nicety. The player is pinned in place during a wash, so
	-- walking out of the leash — the only other way to end a session — is exactly the
	-- thing they cannot do. Without this, entering the bay was a one-way door.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Wash"
	prompt.ActionText = "Wash"
	prompt.ObjectText = "Cleansing Station"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = basin

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
		material = "Glass",
		transparency = 0.5,
		canCollide = false,
	})

	-- Lamp in the plot's own accent colour, so the station reads as part of
	-- THIS base rather than a generic fixture repeated six times. Matte now, with a
	-- soft accent-tinted light -- the one coloured light left on a plot, kept low so
	-- it warms the station without washing the grey plinths in front of it.
	local lamp = build(m, origin, {
		name = "Lamp",
		pos = { 0, pad.topY + 5.9, cz + 1.5 },
		size = { 0.5, 0.5, 0.5 },
		color = accent,
		material = "SmoothPlastic",
		shape = "Ball",
		canCollide = false,
	})
	light(lamp, accent, 12, 0.9)

	buildHoseRig(m, origin, cz)

	m.Parent = parent
end

--- The wash pad — step on it, roll a liquid (Config/Liquids, Services/LiquidService).
---
--- A PRESSURE PLATE, NOT A KIOSK, and the shape is the instruction. There is no
--- button to press and no panel to open first: `StationKind = "roller"` plus
--- StationService's entry edge means arriving IS the input. A five-year-old walks
--- onto a lit circle to see what happens, which is the entire onboarding this
--- mechanic gets, so the circle has to look like something you step on.
---
--- BESIDE THE BASIN, BUT THE TWO RADII MUST NOT TOUCH, and that is a correctness
--- constraint rather than a layout preference. Rolling fires off StationService's
--- ENTRY EDGE and costs cash, so a player scrubbing at the basin who drifts into an
--- overlapping roller radius gets charged for a roll they never asked for. Nearest
--- station wins, which resolves an overlap for *rendering* but not for that edge.
---
--- So: basin at local (0, 20) with radius 9, pad at (18, 18) with radius 6. Centres
--- 18.1 studs apart against a 15-stud combined reach, leaving a ~3-stud dead band
--- between them that a player has to cross deliberately. Keep that gap if either
--- number moves.
---
--- THE SHELF BEHIND IT IS THE ODDS TABLE, RENDERED. Five canisters in the colours of
--- the top five liquids, biggest prize at the far end. It teaches "there are better
--- ones than what you just got" without a tooltip, and it costs five parts.
local function buildWashPad(parent: Instance, origin: CFrame, accent: string)
	local m = Instance.new("Model")
	m.Name = "WashPad"
	local pad = Plots.PAD
	local cx, cz = 18, 18

	-- The plate. Cylinder on its end (Kit.R.cylUp), so `size` reads
	-- {thickness, diameter, diameter} -- see the ShowerHead above for the same idiom.
	local plate = build(m, origin, {
		name = "Plate",
		pos = { cx, pad.topY + 0.25, cz },
		size = { 0.5, 9, 9 },
		color = C.steelDark,
		material = "Metal",
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		attributes = { StationKind = "roller", Radius = 6 },
	})
	billboard(plate, 250, 4.8, "WASH PAD", "step on it, roll a liquid", accent)

	-- The inner disc is coloured water, but it is deliberately matte. The pad is a
	-- physical interaction surface; making its whole centre Neon made it compete
	-- with the radioactive field and made the canisters read as light sources.
	local disc = build(m, origin, {
		name = "Glow",
		pos = { cx, pad.topY + 0.55, cz },
		size = { 0.2, 7.4, 7.4 },
		color = Liquids.get(Liquids.WATER).color,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		transparency = 0.12,
		canCollide = false,
	})
	light(disc, Liquids.get(Liquids.WATER).color, 10, 0.35)

	-- The shelf: a low bench behind the plate carrying one canister per prize.
	build(m, origin, {
		name = "Shelf",
		pos = { cx, pad.topY + 1.4, cz + 5.6 },
		size = { 10, 0.4, 1.6 },
		color = C.wood,
		material = "Wood",
	})
	for _, post in { -4.6, 4.6 } do
		build(m, origin, { name = "ShelfLeg", pos = { cx + post, pad.topY + 0.7, cz + 5.6 }, size = { 0.4, 1.4, 1.4 }, color = C.steelDark, material = "Metal" })
	end

	-- WALKED BACKWARDS FROM THE TOP OF Liquids.ORDER, so the shelf re-sorts itself
	-- the moment the catalogue does. Hard-coding five ids here is how the shelf ends
	-- up advertising a liquid that was renamed two commits ago.
	local shown = {}
	for index = #Liquids.ORDER, 1, -1 do
		local id = Liquids.ORDER[index]
		if Liquids.isRollable(id) then
			table.insert(shown, 1, id)
		end
		if #shown >= 5 then
			break
		end
	end

	for index, id in shown do
		local def = Liquids.get(id)
		local x = cx - 4 + (index - 1) * 2
		build(m, origin, {
			name = `Canister{index}`,
			pos = { x, pad.topY + 2.4, cz + 5.6 },
			size = { 1.6, 1.6, 1.6 },
			color = def.color,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = Kit.R.cylUp,
			transparency = 0.05,
			canCollide = false,
		})
	end

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

--- The luck button — mounted on the plot's own back wall, below the name, where you
--- press E to buy the next +0.1x.
---
--- LUCK IS THE ONE TRACK YOU DO NOT WEAR, so it was the one track that did not belong
--- on a shop counter. It used to be a fourth desk at the Outfitter, visually identical
--- to Suits and Boots and Satchels, selling something with no physical form at all —
--- then a free-standing sign staked next to the pad, painting a whole seven-tier
--- ladder on a board. Luck itself changed shape too (Config/Gear.luau's header): there
--- is no ladder left to paint, only a flat +0.1x at a price that climbs every time, so
--- the button just says the two numbers that are true right now.
---
--- ON THE BACK WALL, UNDER THE NAME, because both are "what is true about this base
--- right now" and belong on the same console — unlike the pad and the tub, which sit
--- out on the floor because they are things you walk up and DO.
---
--- NO PANEL, NO STATION KIND, NO REMOTE. A ProximityPrompt's Triggered fires on the
--- server and Roblox enforces MaxActivationDistance itself, so proximity is a
--- precondition the engine established rather than a claim to be re-checked — see
--- ShopService.buyLuck's header for why that lets this skip StationService entirely.
---
--- GREEN, DELIBERATELY REUSING C.grass RATHER THAN THE PLOT'S OWN ACCENT COLOUR.
--- It sits two steps from a wash pad, so it wears the same "safe" green the plaza and
--- base camp already do, not one of the hazard greens the stages use. Matte, like
--- every surface in the world now (see Kit.C's header) — a button reads as "press me"
--- from its shape and its billboard, it never needed to glow.
---
--- THE BILLBOARD SHOWS YOUR MULTIPLIER AND THE NEXT PRICE, not a ladder — ShopService
--- rewrites both the moment a purchase lands, and ExhibitService rewrites them again
--- on plot assignment, the exact Sign/Title/Subtitle convention LiquidService.announce
--- already uses to name a roll on the wash pad.
local function buildLuckButton(parent: Instance, origin: CFrame)
	local m = Instance.new("Model")
	m.Name = "LuckButton"
	local pad = Plots.PAD
	local wallZ = pad.depth / 2 - 0.5 -- BackWall's own face, see buildPlot
	local panelY = pad.topY + 4.6

	-- A small backing plate on the back wall, below the name -- the same wall the
	-- NameSign is bolted to, so the two read as one console.
	build(m, origin, {
		name = "Panel",
		pos = { 0, panelY, wallZ - 0.55 },
		size = { 3.6, 3.2, 0.3 },
		color = C.steelDark,
		material = "Metal",
	})

	-- The button — a Ball rather than an oriented Cylinder, because a sphere reads as
	-- "press me" from every angle a player can walk up from and needs no rotation to
	-- face the right way.
	local button = build(m, origin, {
		name = "Button",
		pos = { 0, panelY, wallZ - 0.15 },
		size = { 1.4, 1.4, 1.4 },
		color = C.grass,
		material = "SmoothPlastic",
		shape = "Ball",
		canCollide = false,
		attributes = { SellsTrack = "Luck" },
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Upgrade"
	prompt.ActionText = "Upgrade Luck"
	prompt.ObjectText = "Luck"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = button

	-- Level 1 -- the only value that exists before any player has ever claimed this
	-- plot. ShopService and ExhibitService both overwrite it the moment real
	-- per-player state does.
	billboard(
		button,
		220,
		2.6,
		string.format("LUCK %.1fx", Gear.luckMultiplier(1)),
		string.format("+0.1x for $%d", Gear.luckPrice(1)),
		C.grass
	)

	m.Parent = parent
end

--- The plot's back wall. WAS a flat Concrete slab in warm peach; now a studded wall,
--- the same stud treatment the boundary walls and every floor in the world already
--- wear, so the base reads as built out of the same blocks as everything around it.
--- ONE flat colour (the brighter of the old plaza pair, `C.plazaWarm`), on request —
--- the two-tone checker read as busy behind the nameplate. Front face at local z =
--- `pad.depth / 2 - 0.5` (unchanged), so the NameSign and the luck-button panel still
--- bolt straight to it; taller than the old 10-stud slab, on request.
local BACKWALL_TILE = 3.3 -- ~20 columns across the 66-wide pad, ~5 rows up the 16 tall
local BACKWALL_HEIGHT = 16
local function buildBackWall(parent: Instance, origin: CFrame)
	local pad = Plots.PAD
	local folder = Instance.new("Folder")
	folder.Name = "BackWall"

	local wallW, wallThick = pad.width, 1
	local frontZ = pad.depth / 2 - 0.5
	local cols = math.ceil(wallW / BACKWALL_TILE)
	local rows = math.ceil(BACKWALL_HEIGHT / BACKWALL_TILE)

	for ix = 0, cols - 1 do
		local x0 = -wallW / 2 + ix * BACKWALL_TILE
		local x1 = math.min(x0 + BACKWALL_TILE, wallW / 2)
		local w = x1 - x0
		if w <= 1e-3 then
			continue
		end
		for iy = 0, rows - 1 do
			local y0 = iy * BACKWALL_TILE
			local y1 = math.min(y0 + BACKWALL_TILE, BACKWALL_HEIGHT)
			local h = y1 - y0
			if h <= 1e-3 then
				continue
			end
			build(folder, origin, {
				name = "WallTile",
				pos = { (x0 + x1) / 2, pad.topY + (y0 + y1) / 2, frontZ },
				size = { w, h, wallThick },
				color = C.plazaWarm,
				material = "Plastic",
				studs = true,
			})
		end
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

	-- Accent trim, so whose plot is whose is readable from across the plaza. Matte —
	-- the colour alone carries the "whose plot" cue now, no glow.
	for _, side in { -1, 1 } do
		build(m, origin, {
			name = "Trim",
			pos = { side * (pad.width / 2 - 0.5), pad.topY + 0.1, 0 },
			size = { 1, 0.5, pad.depth },
			color = accent,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end

	-- Back wall (studded checkerboard, see buildBackWall) and the nameplate the owner's
	-- display name goes on. The sign is matte in the plot's accent colour — the Trim
	-- and the sign carry "whose plot is this" on hue alone; no accent light any more,
	-- which used to bounce the plot's colour onto the grey plinths in front of it.
	buildBackWall(m, origin)
	local sign = build(m, origin, {
		name = "NameSign",
		pos = { 0, pad.topY + 8, pad.depth / 2 - 1.4 },
		size = { 34, 4, 0.4 },
		color = accent,
		material = "SmoothPlastic",
	})
	Kit.surfaceText(sign, Enum.NormalId.Front, "UNCLAIMED", C.signText)

	-- No claim board any more: exhibit income is auto-deposited into the owner's
	-- wallet (ExhibitService.deposit), so there is nothing here to walk up to and
	-- collect. The nameplate on the back wall is the only thing that marks whose
	-- plot this is.

	-- Where this plot's owner respawns. Disabled until somebody owns it, so nobody
	-- ever lands on a stranger's stage. ExhibitService flips this on assignment.
	local spawn = build(m, origin, {
		name = "PlotSpawn",
		class = "SpawnLocation",
		pos = { 0, pad.topY + 0.5, -pad.depth / 2 + 8 },
		size = { 6, 1, 6 },
		color = accent,
		material = "SmoothPlastic",
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
	buildWashPad(m, origin, accent)
	buildLuckButton(m, origin)

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
