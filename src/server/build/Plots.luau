--!strict
--[[
	Plots.luau — the Rows. Six exhibition plots, one per player.

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

	FOUR PADS ON THE FAR WALL, ONE ON EACH SIDE, EVERY WALL'S PADS CENTRED
	ON ITS OWN SPAN, THE SHOP CLUSTER IN THE MIDDLE — the requested layout:

	    ┌───────────────────────────────────┐
	    │           [PLOT]                   │   north wall (1, centred)
	    │                                    │
	    │[PLOT]     SHOPS + STANDS           │
	    │[PLOT]    (Hub.PLAZA)               ├──▶ [RADIOACTIVE AREA]
	    │[PLOT]                              │
	    │[PLOT]                              │
	    │           [PLOT]                   │   south wall (1, centred)
	    └───────────────────────────────────┘
	     west wall (4, farthest from the stages)

	Four pads along the west wall (the one farthest from Stage 1), one along
	the north wall, one along the south wall — every one of them rotated to
	face back toward the shop cluster in the middle, the same "every pad
	looks at the centre" idea the old semicircular ring had. The plaza
	(`Hub.PLAZA`, untouched by this file) is still what actually touches
	Stage 1's own west edge; the north and south WALLS still anchor flush
	against that edge on their own east end (so the plaza's open east face
	stays the only way out to the field), but the PADS on them sit centred
	on the wall's own span, not pushed flush against either end of it.
	Every pad also sits PLOT_WALL_GAP studs clear of the perimeter wall
	behind it. See PLOT_ROW_PITCH/PLOT_ROW_MARGIN/PLOT_WALL_GAP/WALL_MID_X/
	rowCenters/columnCenters below for the actual layout.

	FIVE ROUNDS OF FEEDBACK SHAPED THIS, THE THREE WALLS THEMSELVES NEVER
	MOVED: 2 rows of 4-and-2 (flush against the perimeter wall, no gap
	behind them) -> 2-and-2-and-2 across three walls, PLOT_WALL_GAP added ->
	3-and-2-and-1 -> 4-and-1-and-1 -> this, same 4-and-1-and-1 split but
	every wall's pads re-centred on its own span instead of sitting flush
	against one end. Every step kept the same three walls and the same
	PLOT_ROW_PITCH/PLOT_ROW_MARGIN/PLOT_WALL_GAP, and Plots.COUNT pinned at
	6 (MaxPlayers, one plot per player, no "sorry, full" case). `rowCenters`/
	`columnCenters` take both a count AND a centre point as plain parameters
	for exactly this reason: neither the split nor the anchoring was ever
	expected to be the last word.

	IT WAS A SEMICIRCLE BEFORE ANY OF THESE RECTANGLES — six pads on the exterior of
	one circle, evenly spaced across its western 180 degrees, each rotated to
	face the shop cluster at the centre, the eastern half left open for the
	plaza to connect straight through to Stage 1. `Kit.orientedRect*` (added
	for the semicircle, since none of its six facings were multiples of 90)
	is kept rather than rolled back — every facing this layout actually uses
	now (0, 180, -90) is a multiple of 90, but the generality costs nothing
	and needs no special-casing back out.

	IT WAS A RECTANGULAR RING BEFORE THE SEMICIRCLE — two pads on each of the plaza's north,
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

	A BASE WEARS THE PLAZA'S STUDDED BOARD IN ONE FLAT COLOUR. The pad is not a slab
	of concrete: it is the same studded tile board the courtyard is paved in, on the
	same grid, one step up from the apron — but a single flat near-black charcoal
	(`Kit.C.baseFloor`), not the courtyard's green checker. The board has been every
	shape by now (navy/grey checker → flat grey → flat near-black → a smooth no-stud
	plate that glinted in the sun); back to the studded board, one flat tone, on
	request. That still makes the six bases the only thing in the world that is not
	some shade of green, and still makes walking onto one a change of colour rather
	than a change of surface.

	A PAD'S OWN TILES ARE BUILT IN ITS YAWED LOCAL SPACE, NOT WORLD SPACE — the
	semicircular ring's facings are no longer multiples of 90, so a pad's true
	footprint is a rotated rectangle, not the axis-aligned one this grid math would
	otherwise assume; `Hub.TileOpts.origin` carries that. The tile cap tops out at
	`pad.topY` and is what a player stands on; the structural `Hub.groundSlab`
	(which carries `PlotIndex`) is recessed one cap-thickness below it.

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

	THE BASE LAYOUT — two flanking columns of stands with the back row filled in
	across (one stand short in the middle, on request, so the centre reads open),
	while a 17-stud entrance-side extension carries the active washing equipment
	and an 18-stud back extension gives the columns room to spread:

	    ┌─────────────────────────────────────┐
	    │  [stand] [stand] [stand] [stand] [stand] │
	    │  [stand]                   [stand]   │
	    │                                     │
	    │  [stand]                   [stand]   │
	    │                                     │
	    │  [stand]         spawn      [stand]  │
	    │                                     │
	    │  [stand]                   [stand]   │
	    ├──────── original front edge ─────────┤
	    │  WASHER + HOSE  [locker]  WASH PAD   │
	    └─────────────────────────────────────┘

	The Quarantine Locker (PLAN §10.2) — the physical rack of items you hauled home
	but can't clean yet — now sits in the +X corner right beside the cleansing
	station, moved off the far back-left wall on request so it is next to the tub
	you fill it at. Built here, filled by ExhibitService.renderLocker; see
	buildQuarantineLocker.

	11 stands: the two flanking columns of 4 (slots 1-8, `slotOffset` pairs them off
	row by row — slot 1 = left row 1, slot 2 = right row 1, ...) plus a 3-stand
	infill (slots 9-11) along the back row, between the two top stands, so that row
	reads as one 5-wide run centred on x = 0 (it was a 4-stand infill / 6-wide row
	until the middle stand was pulled, on request, to open the centre). The
	cleansing station and its hose rig occupy the +X side of the entrance
	extension, the wash pad the -X side, with a deliberate safe gap between their
	station radii.

	SLOTS: 11 BUILT, ALL FREE.
	Tuning.EXHIBIT_MAX_SLOTS is 11 and VISIBLE_SLOTS is the 11 the sketch shows —
	they're the same number. Every stand is usable from the moment a plot is
	claimed; there is no slot to buy or unlock.

	slotOffset only makes sense for these 11 (slots 1-8 flanking, 9-11 the back-row
	infill). Slots past 11 fall through to the flanking-column formula and would
	stack a 5th row deeper toward the entrance — raising VISIBLE_SLOTS past 11 needs
	a real rule for where the extra pedestals go.

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
local ToolModels = require(Shared.ToolModels)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local Plots = {}
local BUILDER_SOURCE = "src/server/build/Plots.luau"
local BUILDER_VERSION = 36

local C = Kit.C
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

--- A Kit.billboard whose subtitle is painted in the plot's accent colour. Tags that
--- Subtitle label `Accent` so Plots.setPlotAccent finds and repaints it alongside the
--- Trim and the nameplate frame. Same args as `billboard`; drop-in for the two plot
--- signs (cleansing station, wash pad) that pass `accent` as their subtitle colour.
local function accentBillboard(part: BasePart, width: number, height: number, title: string, subtitle: string, accent: string)
	local gui = billboard(part, width, height, title, subtitle, accent)
	local sub = gui and gui:FindFirstChild("Subtitle")
	if sub then
		sub:SetAttribute("Accent", true)
	end
end

Plots.COUNT = 6
Plots.VISIBLE_SLOTS = 11
-- Interior bays in the Quarantine Locker cabinet (buildQuarantineLocker). Kept in
-- step with the cleansing-station panel's own LOCKER_ROWS; ExhibitService.renderLocker
-- reads the same number. A locker with more than this many racked items just doesn't
-- show the overflow, exactly like a plot past VISIBLE_SLOTS pedestals.
Plots.LOCKER_SLOTS = 3
-- topY is a deliberate step UP from the plaza (the mirror of Stages.SURFACE_Y's own
-- step down), expressed relative to Hub.PLAZA.topY rather than as a bare literal so
-- it keeps meaning "+1.5 above the plaza" if that ever moves again, instead of
-- silently becoming a different absolute step.
-- The original pad ran from local Z -26 to +26. Both edges have since moved,
-- independently: minZ went to -43 for a 17-stud entrance-side service strip (the
-- washing equipment and the luck button), and maxZ went from +26 to +44 on
-- request — an 18-stud extension straight out the back, behind the old wall, so
-- the two flanking stand columns can be spread over a deeper interior (ROW_PITCH
-- below). The back wall, nameplate and accent trim all read maxZ, so they follow
-- the edge out on their own. Keeping explicit bounds avoids pretending an
-- asymmetric pad is centred on the plot origin.
local PAD_MIN_Z = -43
local PAD_MAX_Z = 44
Plots.PAD = {
	width = 66,
	depth = PAD_MAX_Z - PAD_MIN_Z,
	minZ = PAD_MIN_Z,
	maxZ = PAD_MAX_Z,
	topY = Hub.PLAZA.topY + 1.5,
	thickness = 3,
}

--- FOUR PADS ON THE FAR WALL, ONE ON EACH SIDE. Four along the west wall
--- (the one farthest from Stage 1), one along the north wall, one along the
--- south wall — every pad rotated to face back toward the shop cluster in
--- the middle, the same "every pad looks at the centre" idea the old
--- semicircular ring had. Asymmetric on request, arrived at over three
--- rounds of feedback (see this file's own header for the sequence);
--- Plots.COUNT is pinned to MaxPlayers (6, see this file's own header) — one
--- plot per player, no "sorry, full" case — so NORTH_COUNT/SOUTH_COUNT/
--- WEST_COUNT below always have to add up to 6, whatever the split. North
--- and south are otherwise interchangeable here — nothing structural pins
--- either count to its own wall.
---
--- DERIVED FROM Hub.PLAZA, NOT HAND-SYNCED TO IT — same property the ring
--- before this had: the plaza is the source, this reads it, and moving the
--- plaza moves every wall's pads with it. Hub requires only Kit, so
--- requiring it here is not circular.
---
--- EVERY WALL'S OWN SPAN IS ANCHORED OFF Hub.PLAZA, NOT CENTRED ON THE
--- PLAZA'S OWN MIDPOINT (Hub.CAMP_ORIGIN, x = 17.5). The north/south walls'
--- east end sits flush against Hub.PLAZA.maxX — the same shared-edge
--- convention the plaza's own east side already uses against Stage 1, so
--- that edge stays untouched — and their west end sits flush against the
--- west wall's own back edge (WEST_WALL_X). THE WEST WALL is anchored the
--- mirror way, flush against Hub.PLAZA.minX; it is the wall farthest from
--- the stages, so there is no shared-edge concern on that side to keep
--- clear of.
---
--- A WALL'S PADS ARE CENTRED ON ITS OWN SPAN (WALL_MID_X for north/south,
--- Z = 0 for west), NOT FLUSH AGAINST EITHER END, on request — a single pad
--- sitting flush east read as pushed into the plaza's own corner rather than
--- centred on the wall it was supposed to be sitting on. `rowCenters`/
--- `columnCenters` both centre a `count`-pad group the same way, so this
--- reads correctly whether a wall holds one pad or several.
---
--- `facing` is a yaw in degrees, same convention the ring used: a pad is
--- built with its back wall at local +Z and its spawn at local -Z, so
--- `facing = 0` opens the entrance toward world -Z, `facing = 180` toward
--- world +Z, and `facing = -90` toward world +X (see buildPlot's `origin`,
--- and the old ring's own comment on why -90 is "faces east"). The north
--- wall sits at high Z wanting its entrance to open back south toward the
--- plaza, so it takes `facing = 0`; the south wall mirrors that at
--- `facing = 180`; the west wall sits at low X wanting its entrance to open
--- back east toward the plaza, so it takes `facing = -90`. `padRect`/
--- `Kit.orientedRectsOverlap` below don't need to know there are three
--- facings instead of two now — they already handle an arbitrary yaw, kept
--- from the semicircle rather than rolled back, since the generality costs
--- nothing now that it exists.
---
--- EVERY PAD SITS PLOT_WALL_GAP STUDS CLEAR OF THE PERIMETER WALL BEHIND
--- IT, ON REQUEST — the first cut at this layout ran every pad flush
--- against the wall (Plots.OUTER was exactly the pad footprint, no
--- cushion), which read as too tight. Plots.OUTER now adds PLOT_WALL_GAP
--- beyond every pad's own back edge on all three closed sides (not the
--- open east side, which has no wall to clear).
local PLOT_ROW_PITCH = 82 -- pad width (66) + a 16-stud gap, matching the old ring's own ~17-stud pad-to-pad clearance at its tightest
local PLOT_ROW_MARGIN = 24 -- plaza edge to a wall's own near/entrance edge; clears the old ring's tightest pad-to-plaza gap (~21.6 studs) with room to spare
local PLOT_WALL_GAP = 15 -- a pad's own back edge to the perimeter wall behind it -- real walking space, not flush
local NORTH_COUNT = 1
local SOUTH_COUNT = 1
local WEST_COUNT = 4
assert(NORTH_COUNT + SOUTH_COUNT + WEST_COUNT == Plots.COUNT, "wall counts must add up to Plots.COUNT")

local PLAZA = Hub.PLAZA
local HALF_W = Plots.PAD.width / 2
local HALF_D = Plots.PAD.depth / 2
local PAD_CENTER_Z = (Plots.PAD.minZ + Plots.PAD.maxZ) / 2

-- A north/south wall's own centre Z: PLOT_ROW_MARGIN studs beyond the
-- plaza's near edge, reached from the pad's own entrance-side extent
-- (PAD_MIN_Z, already negative) rather than the pad's local origin, so it's
-- the pad's true entrance edge that lands on the margin line, not some
-- arbitrary interior point. Mirrored south.
local NORTH_Z = PLAZA.maxZ + PLOT_ROW_MARGIN - PAD_MIN_Z
local SOUTH_Z = PLAZA.minZ - PLOT_ROW_MARGIN + PAD_MIN_Z

-- The west wall's own centre X: the same PLOT_ROW_MARGIN idea, mirrored onto
-- the plaza's own west edge instead of its east one.
local WEST_X = PLAZA.minX - PLOT_ROW_MARGIN + PAD_MIN_Z

-- The west wall's own back edge in X (same value Plots.OUTER.minX below
-- reuses, computed here first so it isn't duplicated) and the north/south
-- walls' shared midpoint X, so rowCenters can centre a wall's pads between
-- that back edge and the plaza's own east edge. On request: pads used to sit
-- flush against the plaza's own east edge instead, which read as pushed into
-- the corner once a wall's group shrank to a single pad.
local WEST_WALL_X = WEST_X - PAD_MAX_Z - PLOT_WALL_GAP
local WALL_MID_X = (WEST_WALL_X + PLAZA.maxX) / 2

--- Lay `count` pads evenly along X at a fixed Z, CENTRED on `centerX` —
--- mirrors `columnCenters` below exactly (swap which axis varies). Returns
--- `{x, z, facing}` entries — the same shape the old bearing loop produced,
--- so every downstream reader (`padRect`, `buildPlot`, `World.verify()`) is
--- untouched by what actually populates it.
local function rowCenters(count: number, z: number, facing: number, centerX: number): { { x: number, z: number, facing: number } }
	local list = {}
	local span = (count - 1) * PLOT_ROW_PITCH
	for i = 1, count do
		list[i] = { x = centerX + span / 2 - (i - 1) * PLOT_ROW_PITCH, z = z, facing = facing }
	end
	return list
end

--- The west wall's mirror of `rowCenters`: `count` pads evenly along Z at a
--- fixed X, centred on Z = 0 (the plaza's own Z midpoint) so the group reads
--- symmetric about the plaza's own centreline rather than leaning toward the
--- north or south wall.
local function columnCenters(count: number, x: number, facing: number): { { x: number, z: number, facing: number } }
	local list = {}
	local span = (count - 1) * PLOT_ROW_PITCH
	for i = 1, count do
		list[i] = { x = x, z = span / 2 - (i - 1) * PLOT_ROW_PITCH, facing = facing }
	end
	return list
end

Plots.CENTERS = {}
for _, c in rowCenters(NORTH_COUNT, NORTH_Z, 0, WALL_MID_X) do
	table.insert(Plots.CENTERS, c)
end
for _, c in rowCenters(SOUTH_COUNT, SOUTH_Z, 180, WALL_MID_X) do
	table.insert(Plots.CENTERS, c)
end
for _, c in columnCenters(WEST_COUNT, WEST_X, -90) do
	table.insert(Plots.CENTERS, c)
end

--- The full pad-footprint-plus-clearance bounding rectangle — every wall's
--- own back edge, pushed out by PLOT_WALL_GAP for real walking space behind
--- every pad. Derived from the same wall constants above rather than
--- hand-typed, so it cannot drift from what's actually built. NORTH_Z/
--- SOUTH_Z/WEST_X already place each wall's entrance edge on the margin
--- line; the BACK edge is PAD_MAX_Z further out from a wall's own centre
--- (north: +PAD_MAX_Z in Z, facing 0 doesn't flip; south: -PAD_MAX_Z,
--- facing 180 does; west: -PAD_MAX_Z in X, facing -90 subtracts the same
--- way south's does). maxX stays exactly the plaza's own edge — the open
--- east side has no wall to clear, so no gap is added there.
Plots.OUTER = {
	minX = WEST_WALL_X,
	maxX = PLAZA.maxX,
	minZ = SOUTH_Z - PAD_MAX_Z - PLOT_WALL_GAP,
	maxZ = NORTH_Z + PAD_MAX_Z + PLOT_WALL_GAP,
}

--- A pad's true, ROTATED footprint — an `Kit.OrientedRect`, not an axis-aligned
--- bounding box. Three distinct facings (0, 180, -90) sit across three walls
--- now, so a single "swap width/depth" axis-aligned shortcut can no longer
--- cover every pad the way the old single-row layout could; the real oriented
--- rectangle handles all three the same way it handled the old semicircle's
--- arbitrary bearings. `Kit.pointInOrientedRect` and
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

--- THE APRON — the ground between the shop cluster and the two pad rows,
--- minus the plaza (which already has its own floor) and minus every pad's
--- own footprint.
---
--- ONE TILED RECTANGLE, NOT SIX SPOKES. Tile the bounding rectangle around
--- both rows and drop whatever falls inside the plaza or inside a pad, via a
--- skip predicate — the same "tile the whole area, punch the exceptions
--- back out" approach this file has used since the very first rectangular
--- ring, now back to its simplest form: `Hub.tileRect` already clips every
--- tile to the rect it's handed, so there is no separate "outside the
--- footprint" case to skip any more — the footprint IS the rect.
---
--- THE OPEN MOUTH COMES FREE FROM THE BOUNDING RECT ITSELF: capping it at
--- `maxX = PLAZA.maxX` (see `buildApron`'s own comment on why that, and not
--- the rows' own east anchor — they're the same number, but the reason is
--- the plaza's, not the rows') means this never tiles anything east of the
--- field's own west edge — the same clipping mechanism that already keeps
--- the plaza's own east edge from overhanging into Stage 1 (`Hub.tileRect`
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

--- Same idea as PLAZA_SKIP_MARGIN, one edge in: how far inside a PAD's own footprint
--- a cap tile's centre has to land before this pass drops it. NOT zero. `Hub.tileRect`
--- calls `skip` with each tile's centre and a tile is 3 studs; a pad's footprint
--- generally does not land on the apron's own 3-stud tile grid (a pad is pinned to
--- WALL_MID_X/NORTH_Z/SOUTH_Z/WEST_X, none of which are tile boundaries), so
--- tiles along a pad edge can still cross it. At zero inset a tile whose centre lands just inside the pad
--- is dropped here even though a corner of it pokes back out over open apron — and
--- the pad's own tile grid (a separate, pad-clipped grid) does not reach that far,
--- so the recessed structural slab shows through as a ragged line of dark square
--- dents just outside each base. `Hub.tileRect`'s own header already promises the
--- opposite ("a tile straddling a pad edge is KEPT, and ends up buried inside the
--- pad"); one full tile of inset makes `apronSkip` honour that — a straddling tile
--- is kept, its outward corner is flush apron, and its inward bulk is swallowed by
--- the pad slab sitting 1.5 studs higher over the same ground.
local PAD_SKIP_INSET = 3

--- HOW FAR PAST THE ROWS THE GROUND IS ACTUALLY LAID. Plots.OUTER is the apron's
--- true edge -- every margin / pad-corner-reach figure above is measured to it and
--- stays that way -- but the Scenery perimeter wall (`Scenery.buildBaseWalls`)
--- sits just OUTSIDE that edge on three of its four sides (north, south, west; the
--- fourth, east, is the plaza's own open connector to Stage 1 and carries no wall
--- to tuck under). The tiled cap and its backing slab both used to stop dead at
--- the true edge, which left a thin strip of open void between the cap's own edge
--- and the wall's inner face.
---
--- Laying the ground a full wall-depth past the true edge on those three sides
--- runs it continuously UNDER the wall instead, so there is no seam where the
--- floor gives out before the wall does. The extra rim is hidden beneath a
--- 56-stud wall from every camera inside the camp, so overshooting is free;
--- undershooting is the bug. +10 is the 8 the wall needs plus a 2-stud cushion --
--- Plots cannot require Scenery to read WALL_THICKNESS directly (that would be a
--- cycle: Scenery already requires Plots), so the cushion covers the coupling.
local APRON_BOUNDS: Hub.Rect = {
	minX = Plots.OUTER.minX - 10,
	maxX = Plots.OUTER.maxX, -- flush against the plaza's own open east edge -- no wall there to tuck under
	minZ = Plots.OUTER.minZ - 10,
	maxZ = Plots.OUTER.maxZ + 10,
}

local function apronSkip(x: number, z: number): boolean
	if
		x > PLAZA.minX + PLAZA_SKIP_MARGIN
		and x < PLAZA.maxX - PLAZA_SKIP_MARGIN
		and z > PLAZA.minZ + PLAZA_SKIP_MARGIN
		and z < PLAZA.maxZ - PLAZA_SKIP_MARGIN
	then
		return true -- safely inside the plaza's own floor, well past its edge tiles
	end
	for _, c in Plots.CENTERS do
		if Kit.pointInOrientedRect(x, z, padRect(c, PAD_SKIP_INSET)) then
			return true
		end
	end
	return false
end

--- STAND LAYOUT — two flanking columns of 4, plus a 3-stand infill that turns the
--- back row into one continuous 5-wide run along the back wall. 11 stands total.
---
--- Slots 1-8 are the two flanking columns, paired off row by row — odd slots go
--- left, even slots go right, each pair sharing a Z. ROW_TOP_Z is the FIRST row,
--- closest to the back wall; rows count DOWN from there toward the entrance.
--- ROW_PITCH is 12.5 (was 10): the +18 back extension (PAD_MAX_Z) gave the
--- interior the depth to spread the four rows out, and 12.5 makes the row-to-row
--- gap match the back row's own stand-to-stand gap (5 stands across x -25..25),
--- so the whole grid reads at one even spacing. ROW_TOP_Z moved back to 33 to
--- sit the run against the wall's new position rather than leave empty studs
--- behind it.
---
--- Slots 9-11 fill the gap along ROW_TOP_Z BETWEEN the two top stands (slots 1 and
--- 2 at ±COL_X) — three pedestals at x = ∓12.5, 0 so the back row reads as
--- -25 -12.5 0 12.5 25, one unbroken 5-wide run centred on x = 0. This was a
--- 4-stand infill (a 6-wide back row) until the middle stand was pulled on
--- request to open the centre up; dropping the highest infill slot keeps slots
--- 1-8 (and any saved item in them) exactly where they were.
local COL_X = 25
local ROW_TOP_Z = 33
local ROW_PITCH = 12.5
local BACK_ROW_INFILL_X = { -12.5, 0, 12.5 } -- slots 9-11, along ROW_TOP_Z

local function slotOffset(slot: number): (number, number)
	if BACK_ROW_INFILL_X[slot - 8] ~= nil then
		return BACK_ROW_INFILL_X[slot - 8], ROW_TOP_Z
	end
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
local RISER_BASE = { w = 7.4, h = 0.9 }
local RISER_TOP = { w = 6.3, h = 0.7 }
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

	-- Studded plastic to match the enlarged bay (buildCleansingStation). `BODY` is the
	-- base-course grey, `FACE` the lighter cap grey -- the same pair the display
	-- plinths and the tub wear -- and `FIT` the smooth metal of the pipes and bolts.
	local BODY, FACE, FIT = C.standGreyDark, C.standGrey, C.steelDark

	-- Tucked into the front-left corner of the deck, well clear of the straight walk-up
	-- to WashSpot and out of the tub's own sightline from the aisle. The whole rig
	-- follows (px, pz) so the bay moves as one.
	local px, pz = cx + 7, cz - 9

	-- A skid under the housing, so the pump reads as a unit set down and bolted rather
	-- than a crate left on the tiles.
	build(parent, origin, { name = "PumpSkid", pos = { px, T + 0.35, pz }, size = { 3.2, 0.7, 2.8 }, color = BODY, material = "Plastic", studs = true })

	-- Studded like the tub, a touch bigger than the old squat crate but kept below the
	-- rim of the tub so it does not compete with it.
	build(parent, origin, {
		name = "HosePump",
		pos = { px, T + 1.9, pz },
		size = { 2.6, 3.0, 2.2 },
		color = BODY,
		material = "Plastic",
		studs = true,
	})
	build(parent, origin, { name = "PumpCap", pos = { px, T + 3.55, pz }, size = { 3.0, 0.35, 2.6 }, color = FACE, material = "Plastic", studs = true })
	build(parent, origin, {
		name = "PumpGauge",
		pos = { px + 1.55, T + 2.3, pz },
		size = { 0.2, 0.9, 0.9 },
		color = C.glass,
		material = "SmoothPlastic",
		shape = "Cylinder",
		-- Axis along authored X (plot -Z) so the dial faces the player walking up.
		rot = Kit.R.cylAlongX,
		canCollide = false,
	})

	-- THE DRUM IS THE ONLY THING THAT SAYS THE HOSE IS LONG. The Beam below draws exactly
	-- one span -- reel to nozzle -- and a hose that is only ever a few studs long is a
	-- shower attachment; a visibly wound drum is where the rest of it lives.
	--
	-- WIDEST PART FIRST, NOT FLANGES. A real reel's flanges are wider than the drum, but
	-- a Cylinder part cannot be a ring, so a wide flange is a SOLID disc that occludes
	-- the whole drum from the one angle the reel is legible from. So: the green drum is
	-- the widest thing, a darker band over it reads as wound coils, and a small steel
	-- hub caps each end -- what a spool of hose actually looks like face-on.
	local rx = px - 1.7
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
		pos = { px - 0.9, ry, pz },
		size = { 1.5, 0.3, 0.3 },
		color = FIT,
		material = "Metal",
		shape = "Cylinder",
		canCollide = false,
	})

	-- Where the hose leaves the drum. Its FACING is load-bearing: a Beam's curve
	-- control point runs along the attachment's LookVector, so this aims down-and-
	-- toward-the-tub to throw the slack loop that way, not back behind the pump.
	local anchor = Instance.new("Attachment")
	anchor.Name = "HoseAnchor"
	anchor.CFrame = CFrame.lookAt(Vector3.new(0, -1.1, 0.9), Vector3.new(0, -1.75, 4.9))
	anchor.Parent = reel

	-- A square-section conduit from the skid into the tub base, so the pump reads as
	-- plumbed in. A thin box is a clean pipe at this scale with none of a rotated
	-- cylinder's axis ambiguity.
	build(parent, origin, { name = "Conduit", pos = { px, T + 0.7, (pz + cz) * 0.5 - 1.5 }, size = { 0.5, 0.5, math.abs(cz - pz) - 3 }, color = FIT, material = "Metal", canCollide = false })
	build(parent, origin, { name = "ConduitElbow", pos = { px, T + 0.7, cz - 3 }, size = { 0.7, 0.7, 0.7 }, color = FIT, material = "Metal", canCollide = false })
	build(parent, origin, { name = "Conduit", pos = { (px + cx) * 0.5, T + 0.7, cz - 3 }, size = { math.abs(px - cx) + 0.5, 0.5, 0.5 }, color = FIT, material = "Metal", canCollide = false })

	-- ── The mast, and the monitor bolted to it ────────────────
	-- The nozzle is not something you pick up: it stands on its own mast and the player
	-- aims it from the mark, hands empty. Three constraints fence the mast into the
	-- tub's near-left corner -- OUT OF THE BATH (a mast inside the rims stands in the
	-- water), OFF THE WALK-UP (the player comes straight down the aisle to WashSpot),
	-- and LEFT of the tub because the pump is already there, so the hose runs down one
	-- side of the deck past nothing rather than across the walk-up at ankle height.
	--
	-- The arc it was tuned for (WashController.jetPath) does NOT depend on this mast any
	-- more: WashController re-homes a per-viewer copy of the model to a point near the
	-- washing player's own camera for the session and parks this one back on
	-- `ParkedPivot` on exit. So the mast's whole job now is the at-rest look -- a
	-- bystander, or the same player before/after their wash, finding the machine parked
	-- here wearing whichever Cleaner rung its owner bought.
	local mx, mz = cx + 5, cz - 6
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
--- the four `SignFrame` bars round the nameplate, the cleansing-station `Lamp` (and
--- its `PointLight`), and the `CLEANSING STATION` / `WASH PAD` sign subtitles.
---
--- A NIL COLOUR MEANS "UNCLAIMED": it puts back `C.plotNeutral`, the grey a freshly
--- built plot wears — what ExhibitService hands it when a player leaves. Spelled as a
--- default rather than a separate `clearAccent()`, same reasoning as setHoseTier above.
---
--- TAG-DRIVEN, NOT NAME-DRIVEN. buildPlot stamps `Accent` on the parts and
--- accentBillboard stamps it on the subtitle labels, so this is the same
--- "geometry is build-time, skin is runtime" split setHoseTier uses: a service that
--- needs to recolour plot geometry asks this module rather than learning part names.
--- The lamp's `PointLight` has no attribute of its own — it is matched by its parent
--- carrying `Accent`.
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
--- forward of the final stand row (z = -4.5 once ROW_PITCH widened), well clear
--- of it, while its pump reaches almost to the front edge. That keeps the display
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
	-- built out of the same studded blocks as the display plinths and the back wall so
	-- it belongs to the base. `BODY` is the base-course grey, `FACE` the lighter cap
	-- grey (the display-plinth pair), `LINER` the dark recess inside the tub, `FIT` the
	-- smooth metal of the pipework. Hose stays jade, water stays cyan.
	--
	-- THE WASH MINIGAME GEOMETRY DID NOT MOVE. WashStand (the item point), WashSpot
	-- (where WashService plants the player) and WashCam (WashController's fallback) keep
	-- the exact offsets the previous bay had, and the tub grew around them, not through
	-- them -- so nothing about the first-person shot, the aim, or the placement changed.
	local BODY, FACE, LINER, FIT = C.standGreyDark, C.standGrey, C.drain, C.steelDark

	-- ── The deck ──────────────────────────────────────────────
	-- One studded plate the whole installation stands on, kerbed round the edge, so the
	-- bay is a unit set into the strip and not parts scattered on the tiles. Top a
	-- hair proud of the floor -- a threshold, not a step: WashService plants the player
	-- just off its front edge, so nothing here changes the height they stand at.
	build(m, origin, { name = "Deck", pos = { 21, T - 0.35, -32 }, size = { 12.5, 1.0, 10 }, color = BODY, material = "Plastic", studs = true })
	for _, e in {
		{ x = 21, z = -37, sx = 13.1, sz = 0.6 },
		{ x = 21, z = -27, sx = 13.1, sz = 0.6 },
		{ x = 27.25, z = -32, sx = 0.6, sz = 10.6 },
		{ x = 14.75, z = -32, sx = 0.6, sz = 10.6 },
	} do
		build(m, origin, { name = "DeckKerb", pos = { e.x, T + 0.25, e.z }, size = { e.sx, 0.35, e.sz }, color = FACE, material = "Plastic", studs = true, canCollide = false })
	end

	-- ── The tub ───────────────────────────────────────────────
	-- THE DOCK + THE FLUSH, one part: StationKind="decon" is what DeconService matches
	-- on, Shower=true what ExposureService scans for, and the "Wash" prompt hangs off
	-- it. It is the solid lower body of the trough now -- a heavy studded block, not the
	-- old thin steel slab -- with its centre kept exactly where it was so the item
	-- point and the prompt do not move.
	local basin = build(m, origin, {
		name = "Basin",
		pos = { cx, T + 0.55, cz },
		size = { 7.4, 3.0, 7 },
		color = BODY,
		material = "Plastic",
		studs = true,
		attributes = { StationKind = "decon", Shower = true, Radius = 9 },
	})

	-- A dark liner sunk WELL below the body's top, so looking in you see a real recess
	-- -- a grey lip, a step down, then the dark well and the water at the bottom -- not
	-- a flat plate. This is what turns the block into a basin you wash a thing IN.
	build(m, origin, { name = "TubLiner", pos = { cx, T + 0.15, cz }, size = { 5.9, 2.9, 5.4 }, color = LINER, material = "SmoothPlastic" })

	-- A wide flat rim lip capping the body -- four studded bars, tops at T+2.3, a shade
	-- under the old rims' T+2.6 so the stream still clears them from the player's side
	-- and the item still sits proud of them.
	for _, side in { -1, 1 } do
		build(m, origin, { name = "TubRim", pos = { cx, T + 2.05, cz + side * 3.7 }, size = { 7.9, 0.5, 0.95 }, color = FACE, material = "Plastic", studs = true, canCollide = false })
		build(m, origin, { name = "TubRim", pos = { cx + side * 3.9, T + 2.05, cz }, size = { 0.95, 0.5, 7.4 }, color = FACE, material = "Plastic", studs = true, canCollide = false })
	end

	-- The water: a translucent body low in the well, with a fainter sheen plane on top
	-- -- one flat glass slab reads as a lid, two layers reads as depth.
	build(m, origin, { name = "Water", pos = { cx, T + 1.1, cz }, size = { 5.4, 0.5, 4.9 }, color = C.cyan, material = "Glass", transparency = 0.3 })
	local sheen = build(m, origin, { name = "WaterSheen", pos = { cx, T + 1.38, cz }, size = { 5.2, 0.06, 4.7 }, color = C.glass, material = "SmoothPlastic", transparency = 0.55, canCollide = false })
	sheen.Reflectance = 0.05

	-- A grated drain in the floor of the basin, just visible under the water, so the
	-- trough has an outfall and is not a sealed tank.
	build(m, origin, { name = "Drain", pos = { cx, T + 0.7, cz }, size = { 0.3, 1.3, 1.3 }, color = LINER, material = "Metal", shape = "Cylinder", rot = Kit.R.cylUp, canCollide = false })
	for _, r in { Kit.R.cylAlongX, Kit.R.cylAlongZ } do
		build(m, origin, { name = "DrainBar", pos = { cx, T + 0.85, cz }, size = { 1.3, 0.12, 0.12 }, color = FIT, material = "Metal", shape = "Cylinder", rot = r, canCollide = false })
	end

	-- ── The item rack and the three shot anchors ──────────────
	-- WashRack lifts the item clear of the rim so water from the side reaches it. The
	-- three anchors are UNCHANGED from the previous bay -- WashService pivots the item
	-- to WashStand's centre, plants the player a step forward of WashSpot, and
	-- WashController falls back to WashCam for the frame a respawn leaves the head
	-- missing. Framing is judged by looking, so these stay anchors, not numbers.
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
	local churnHost = build(m, origin, {
		name = "TubChurn",
		pos = { cx, T + 1.45, cz },
		size = { 3.8, 0.1, 3.2 },
		color = "E9F4FF",
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
	})
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
	local signHost = build(m, origin, { name = "SignHost", pos = { 18, GANTRY_TOP + 0.7, POST_Z }, size = { 9.0, 0.4, 1.0 }, color = FACE, material = "Plastic", studs = true, canCollide = false })
	accentBillboard(signHost, 240, 2.6, "CLEANSING STATION", "clean it, flush it, rack it", accent)

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
	light(lamp, accent, 14, 0.9)

	buildHoseRig(m, origin, cx, cz)

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
--- So: basin at local (18, -32) with radius 9, pad at (-22, -31) with radius 6.
--- Centres are ~40 studs apart against a 15-stud combined reach, leaving a broad
--- central aisle and making an accidental paid roll impossible. Keep that gap if
--- either number moves.
---
--- THE PLINTH DOWN ITS -X EDGE IS THE ODDS TABLE, RENDERED. Five glass jars filled
--- with the top five liquids, biggest prize at the far end. It teaches "there are
--- better ones than what you just got" without a tooltip, and it costs a handful of
--- parts.
---
--- REDETAILED TO MATCH THE CLEANSING STATION (on request, the branch after that
--- rebuild). The pad was a bare metal disc, a wood bench and five loose canisters --
--- the thin-steel-and-timber look the bay across the aisle had just moved away from.
--- It is the same studded-block kit now: `BODY` the base-course grey, `FACE` the
--- lighter cap grey (the display-plinth / cleansing-station pair), `LINER` the dark
--- recess, `FIT` the plate's own metal. NOTHING THE SERVICES READ MOVED: the plate
--- keeps its exact plot centre and Radius (so the ~47-stud gap to the basin that
--- World.verify() enforces is untouched), `Glow` is still a BasePart sibling of the
--- plate that LiquidService flashes, and the `Sign` billboard is still on the plate.
local function buildWashPad(parent: Instance, origin: CFrame, accent: string)
	local m = Instance.new("Model")
	m.Name = "WashPad"
	local pad = Plots.PAD
	local T = pad.topY
	-- Negative local X is the player's RIGHT when approaching from the entrance.
	local cx, cz = -22, -31

	-- TURNED A QUARTER-TURN THE OTHER WAY so the odds plinth BACKS ONTO THE -X SIDE
	-- BORDER: the plate faces the central aisle and the canister plinth lines the pad's
	-- own left edge instead of standing in the strip. Applied to `origin` about the
	-- pad's centre so every part below stays in local space; the plate and its Radius
	-- sit on the pivot. The turn puts the deck's -X kerb a stud inside the accent trim
	-- (x ~= -31 against the trim at -32) and the small +X nudge (plot-local, before the
	-- pivot) keeps the plinth clear of it. The roll costs cash off StationService's
	-- entry edge, so the centre-to-centre gap to the basin that World.verify() enforces
	-- has to survive this: the plate lands near x = -21 against the basin's x ~= 26 --
	-- ~47 studs, well past the 15 reach.
	origin = origin
		* CFrame.new(1, 0, 0)
		* CFrame.new(cx, 0, cz)
		* CFrame.Angles(0, math.rad(-90), 0)
		* CFrame.new(-cx, 0, -cz)

	-- Authoring runs in the pad's own pre-pivot frame: +x here ends up +Z on the plot
	-- (toward the interior), +z ends up -X (toward the side border). The plate sits on
	-- the pivot at (cx, cz); everything else is an offset from it.
	local BODY, FACE, LINER, FIT = C.standGreyDark, C.standGrey, C.drain, C.steelDark

	-- ── The deck ──────────────────────────────────────────────
	-- One studded plate the pad stands on, kerbed round the edge, top a hair proud of
	-- the floor (T + 0.15) -- the same threshold-not-a-step the cleansing station deck
	-- across the aisle uses, so the two read as one installation. It runs from a stud
	-- inside the -X trim to flush with the plate's aisle edge; the luck button still
	-- stands a couple of studs off that edge on the bare floor, as it did before.
	build(m, origin, { name = "Deck", pos = { cx + 0.5, T - 0.35, cz + 2.5 }, size = { 13, 1.0, 15 }, color = BODY, material = "Plastic", studs = true })
	for _, e in {
		{ x = cx + 0.5, z = cz - 5, sx = 13.6, sz = 0.6 },
		{ x = cx + 0.5, z = cz + 10, sx = 13.6, sz = 0.6 },
		{ x = cx + 7, z = cz + 2.5, sx = 0.6, sz = 15.6 },
		{ x = cx - 6, z = cz + 2.5, sx = 0.6, sz = 15.6 },
	} do
		build(m, origin, { name = "DeckKerb", pos = { e.x, T + 0.25, e.z }, size = { e.sx, 0.35, e.sz }, color = FACE, material = "Plastic", studs = true, canCollide = false })
	end

	-- ── The well: the step-plate, recessed ────────────────────
	-- The disc drops into a shallow dark tray and a studded kerb rises round it on the
	-- far three sides -- front, back and the -X border side -- open toward the aisle so
	-- you walk straight in over a flush threshold. A proud FACE lip caps the kerb, and
	-- you look over it and DOWN at the lit disc: the tub liner across the aisle, at pad
	-- scale. All of it CanCollide off -- framing, not a barrier, like the tub rim.
	local WELL_H = 1.5
	build(m, origin, { name = "WellLiner", pos = { cx, T + 0.15, cz }, size = { 9.6, 0.9, 9.6 }, color = LINER, material = "SmoothPlastic", canCollide = false })
	for _, bar in {
		{ x = cx, z = cz + 5.4, sx = 12, sz = 1.2 }, -- -X border side
		{ x = cx - 5.4, z = cz + 1.5, sx = 1.2, sz = 10.2 }, -- front (toward the apron)
		{ x = cx + 5.4, z = cz + 1.5, sx = 1.2, sz = 10.2 }, -- back (toward the interior)
	} do
		build(m, origin, { name = "WellKerb", pos = { bar.x, T + 0.55, bar.z }, size = { bar.sx, WELL_H, bar.sz }, color = BODY, material = "Plastic", studs = true, canCollide = false })
		build(m, origin, { name = "WellLip", pos = { bar.x, T + 1.45, bar.z }, size = { bar.sx + 0.4, 0.3, bar.sz + 0.4 }, color = FACE, material = "Plastic", studs = true, canCollide = false })
	end

	-- ── The plate and its lit disc ────────────────────────────
	-- The plate keeps its exact plot position and Radius (see the pivot note above);
	-- only its height changed, up onto the tray floor. Still a bare metal disc -- the
	-- one thing here that is not a studded block -- so it still reads as a surface you
	-- step onto, now cupped in the well. Cylinder on its end (Kit.R.cylUp), so `size`
	-- reads {thickness, diameter, diameter}.
	local plate = build(m, origin, {
		name = "Plate",
		pos = { cx, T + 0.7, cz },
		size = { 0.3, 9, 9 },
		color = FIT,
		material = "Metal",
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		attributes = { StationKind = "roller", Radius = 6 },
	})
	accentBillboard(plate, 250, 5.0, "WASH PAD", `first roll free, then ${Tuning.LIQUID_ROLL_COST}`, accent)

	-- The inner disc is coloured water and deliberately matte -- LiquidService flashes
	-- its Color on a roll and eases it back, and a Neon centre made it compete with
	-- the field and lit the canisters. Sits just above the plate, down in the well.
	local disc = build(m, origin, {
		name = "Glow",
		pos = { cx, T + 0.9, cz },
		size = { 0.22, 7.8, 7.8 },
		color = Liquids.get(Liquids.WATER).color,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = Kit.R.cylUp,
		transparency = 0.12,
		canCollide = false,
	})
	light(disc, Liquids.get(Liquids.WATER).color, 10, 0.35)

	-- ── The odds shelf: a studded plinth down the -X edge ─────
	-- The same two-course studded riser as a display stand, run long against the
	-- border, with the prize jars seated in a shallow dark channel in the top course
	-- and a low FACE back-board behind them. Still "there are better ones than this"
	-- told in five filled jars and no tooltip -- just built like the base now.
	local shelfZ = cz + 7.4
	build(m, origin, { name = "PadShelf", pos = { cx, T + 0.6, shelfZ }, size = { 12, 0.9, 2.4 }, color = BODY, material = "Plastic", studs = true })
	build(m, origin, { name = "PadShelfTop", pos = { cx, T + 1.35, shelfZ }, size = { 11, 0.6, 2.0 }, color = FACE, material = "Plastic", studs = true })
	build(m, origin, { name = "PadShelfChannel", pos = { cx, T + 1.5, shelfZ }, size = { 9.6, 0.35, 1.1 }, color = LINER, material = "SmoothPlastic", canCollide = false })
	build(m, origin, { name = "PadShelfBoard", pos = { cx, T + 2.55, cz + 8.45 }, size = { 12, 2.2, 0.3 }, color = FACE, material = "Plastic", studs = true, canCollide = false })

	-- One prize = one specimen jar: a near-clear glass body with the liquid itself
	-- sitting inside it and a dark metal lid, rather than a solid slug in the liquid's
	-- colour. The glass is a neutral off-white and mostly transparent -- NOT C.glass,
	-- whose blue tint shifted the colour you actually came to read -- so the fill reads
	-- true; the fill is near-opaque and fills most of the jar so it still carries from
	-- across the pad. Base sits in the channel (T + 1.55).
	local jarGlass = "F1F1F2"
	local function jar(x: number, id: string)
		local def = Liquids.get(id)
		local baseY = T + 1.55
		build(m, origin, {
			name = "JarFill",
			pos = { x, baseY + 0.55, shelfZ },
			size = { 1.0, 1.05, 1.05 },
			color = def.color,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = Kit.R.cylUp,
			transparency = 0.05,
			canCollide = false,
		})
		local body = build(m, origin, {
			name = "Jar",
			pos = { x, baseY + 0.8, shelfZ },
			size = { 1.5, 1.35, 1.35 },
			color = jarGlass,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = Kit.R.cylUp,
			transparency = 0.58,
			canCollide = false,
		})
		body.Reflectance = 0.06
		build(m, origin, {
			name = "JarLid",
			pos = { x, baseY + 1.55, shelfZ },
			size = { 0.35, 1.45, 1.45 },
			color = FIT,
			material = "Metal",
			shape = "Cylinder",
			rot = Kit.R.cylUp,
			canCollide = false,
		})
	end

	-- WALKED BACKWARDS FROM THE TOP OF Liquids.ORDER, so the plinth re-sorts itself
	-- the moment the catalogue does. Hard-coding five ids here is how it ends up
	-- advertising a liquid that was renamed two commits ago.
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
		jar(cx - 4 + (index - 1) * 2, id)
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
--- not a stop. MOVED next to the cleansing station on request — it used to stand
--- against the back wall on the far LEFT of the base, a long walk from the tub you
--- fill it at. Now it sits in the +X corner just behind the cleansing bay (plot
--- x ~= 30, z ~= -24), still opening toward the plot entrance (-Z), tucked
--- between the gantry (its posts reach plot x ~= 27.5, z ~= -29) and the right
--- stand column's last row (z = -4.5 after ROW_PITCH widened) with clear studs to
--- each. `ExhibitService` finds every part of it by name, so the move needs
--- nothing on its side.
---
--- THE DOOR IS ITS OWN MODEL, built CLOSED in a frame anchored at the hinge (the
--- -X edge of the opening), so a yaw about that frame's own vertical axis swings
--- it. The two pivots are stamped as CFrame attributes, so ExhibitService never
--- has to know which way this plot faces.
local function buildQuarantineLocker(parent: Instance, origin: CFrame, accent: string)
	local m = Instance.new("Model")
	m.Name = "QuarantineLocker"
	local pad = Plots.PAD

	-- S scales the whole cabinet up; YAW turns it left (CCW seen from above) about
	-- its own centre so the open front angles back toward the plot interior instead
	-- of squarely down -Z. Everything below is authored axis-aligned around (lx,lz)
	-- and then rotated as a block through `face`; the door uses the same frame so
	-- its stamped pivots inherit the turn.
	local S = 1.4
	local lx, lz = 30, -24
	local face = origin * CFrame.new(lx, 0, lz) * CFrame.Angles(0, math.rad(40), 0) * CFrame.new(-lx, 0, -lz)
	local baseY = pad.topY + 0.4 -- top of the plinth; the cabinet's own floor sits here
	local bodyH = 5.4 * S
	local midY = baseY + bodyH / 2 -- centre of the body

	build(m, face, { name = "Plinth", pos = { lx, pad.topY + 0.2, lz }, size = { 3.2 * S, 0.4, 2.4 * S }, color = C.baseTileDark, material = "Metal" })

	-- The open-front box.
	build(m, face, { name = "Back", pos = { lx, midY, lz + 0.85 * S }, size = { 2.6 * S, bodyH, 0.2 }, color = C.steelDark, material = "Metal" })
	for _, sx in { -1, 1 } do
		build(m, face, { name = "Side", pos = { lx + sx * 1.3 * S, midY, lz }, size = { 0.2, bodyH, 1.9 * S }, color = C.steelDark, material = "Metal" })
	end
	build(m, face, { name = "Floor", pos = { lx, baseY + 0.1, lz }, size = { 2.6 * S, 0.2, 1.9 * S }, color = C.steelDark, material = "Metal" })
	build(m, face, { name = "Ceiling", pos = { lx, baseY + bodyH - 0.1, lz }, size = { 2.6 * S, 0.2, 1.9 * S }, color = C.steelDark, material = "Metal" })

	-- Red interior lining — the one saturated colour in the base.
	build(m, face, { name = "Lining", pos = { lx, midY, lz + 0.7 * S }, size = { 2.4 * S, bodyH - 0.4, 0.1 }, color = C.quarantineRed, material = "SmoothPlastic" })
	build(m, face, { name = "LiningFloor", pos = { lx, baseY + 0.25, lz }, size = { 2.4 * S, 0.12, 1.6 * S }, color = C.quarantineRed, material = "SmoothPlastic" })

	-- Two shelves split the interior into LOCKER_SLOTS bays; a hidden anchor sits on
	-- the floor of each. renderLocker seats a scaled item model on the anchor's
	-- bottom face (anchor.Position.Y - anchor.Size.Y/2), so the anchor cube marks
	-- the bay floor and needs no shared magic offset with ExhibitService.
	local bayFloorY = { baseY + 0.31 }
	local bayGap = (bodyH - 0.62) / Plots.LOCKER_SLOTS
	for i = 1, Plots.LOCKER_SLOTS - 1 do
		local shelfY = baseY + 0.31 + i * bayGap
		build(m, face, { name = `Shelf{i}`, pos = { lx, shelfY, lz }, size = { 2.4 * S, 0.1, 1.6 * S }, color = C.steel, material = "Metal" })
		table.insert(bayFloorY, shelfY + 0.05)
	end
	for i, floorY in bayFloorY do
		build(m, face, {
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
	local sign = build(m, face, { name = "Sign", pos = { lx, baseY + bodyH + 0.3, lz - 0.95 * S }, size = { 2.6 * S, 0.55, 0.1 }, color = C.steelDark, material = "Metal" })
	Kit.surfaceText(sign, Enum.NormalId.Front, "QUARANTINE", C.quarantineRed)

	-- THE DOOR. Hinge = the -X edge of the opening; build parts extending +X from it
	-- (closed, across the opening). Slab is a hair wider than the gap so a shut
	-- locker reads solid.
	local hinge = face * CFrame.new(lx - 1.3 * S, midY, lz - 0.9 * S)
	local door = Instance.new("Model")
	door.Name = "LockerDoor"

	build(door, hinge, { name = "Slab", pos = { 1.25 * S, 0, 0 }, size = { 2.5 * S, bodyH - 0.2, 0.14 }, color = C.steel, material = "Metal" })
	for _, bankY in { 1.5 * S, -1.4 * S } do
		for s = 0, 3 do
			build(door, hinge, {
				name = "Louver",
				pos = { 1.25 * S, bankY - s * 0.34 * S, -0.16 },
				size = { 2.0 * S, 0.12, 0.18 },
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

--- The luck button — a free-standing stake beside the wash pad, where you press E to
--- buy the next +0.1x.
---
--- LUCK IS THE ONE TRACK YOU DO NOT WEAR, so it was the one track that did not belong
--- on a shop counter. It used to be a fourth desk at the Outfitter, visually identical
--- to Suits and Boots and Satchels, selling something with no physical form at all —
--- then a free-standing sign staked next to the pad, painting a whole seven-tier
--- ladder on a board; then a button on the plot's back wall under the name. Luck
--- itself changed shape too (Config/Gear.luau's header): there is no ladder left to
--- paint, only a flat +0.1x at a price that climbs every time, so the button just
--- says the two numbers that are true right now.
---
--- BACK BESIDE THE WASH PAD, on request. Luck weights the wash roll, so the control
--- belongs where you do the rolling — a short stake on the aisle side of the pad
--- plate, out on the floor like the pad and the tub because it is a thing you walk up
--- to and DO, not a line on the back-wall console.
---
--- NO PANEL, NO STATION KIND, NO REMOTE. A ProximityPrompt's Triggered fires on the
--- server and Roblox enforces MaxActivationDistance itself, so proximity is a
--- precondition the engine established rather than a claim to be re-checked — see
--- ShopService.buyLuck's header for why that lets this skip StationService entirely.
---
--- GREEN, DELIBERATELY REUSING C.grass RATHER THAN THE PLOT'S OWN ACCENT COLOUR.
--- It wears the same "safe" green the plaza and base camp already do, not one of the
--- hazard greens the stages use. Matte, like
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
	-- Beside the wash pad plate. buildWashPad seats that plate at plot-local
	-- (-21, _, -31) (its own cx/cz of -22/-31, nudged +1 X, then spun about itself);
	-- the plate is 9 across, so a stake at x = -13 stands ~2.5 studs off its aisle
	-- edge, on the +X (plot-centre) side a player walks in from. Same service strip,
	-- clear of the canister shelf backed onto the -X border at x ~= -27.
	local bx, bz = -13, -31
	local buttonY = pad.topY + 3

	-- The stake: a short steel post the button sits on, so it reads as planted
	-- furniture out on the floor rather than a control that needs a wall.
	build(m, origin, {
		name = "Post",
		pos = { bx, pad.topY + 1.3, bz },
		size = { 0.5, 2.6, 0.5 },
		color = C.steelDark,
		material = "Metal",
	})
	build(m, origin, {
		name = "Base",
		pos = { bx, pad.topY + 0.15, bz },
		size = { 1.8, 0.3, 1.8 },
		color = C.steelDark,
		material = "Metal",
		canCollide = false,
	})

	-- The button — a Ball rather than an oriented Cylinder, because a sphere reads as
	-- "press me" from every angle a player can walk up from and needs no rotation to
	-- face the right way.
	local button = build(m, origin, {
		name = "Button",
		pos = { bx, buttonY, bz },
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
--- ONE flat colour — was the pale `C.plazaWarm`, dropped to the dark warm `C.baseWall`
--- on request so the wall sits back behind the nameplate instead of glowing pale.
--- Front face at local z =
--- `pad.maxZ - 0.5` (local z = 43.5 since the +18 back extension moved maxZ out
--- from 26 to 44), so the wall and the NameSign standing proud of it on standoff
--- arms follow the edge on their own; taller than the old 10-stud slab, on request.
local BACKWALL_TILE = 3.3 -- ~20 columns across the 66-wide pad, ~5 rows up the 16 tall
local BACKWALL_HEIGHT = 16
local function buildBackWall(parent: Instance, origin: CFrame)
	local pad = Plots.PAD
	local folder = Instance.new("Folder")
	folder.Name = "BackWall"

	local wallW, wallThick = pad.width, 1
	local frontZ = pad.maxZ - 0.5
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
				color = C.baseWall,
				material = "Plastic",
				studs = true,
			})
		end
	end

	folder.Parent = parent
end

--- A plain grey guard rail down the LEFT and RIGHT long edges of the base, on
--- request — posts and two horizontal rails bolted just inside the accent `Trim`.
--- Its whole job is to read as an enclosure: the base already has a wall across the
--- back and an open service strip across the front, and the two long sides were the
--- one place the pad just fell away to the apron. The entrance (local -Z) and the
--- back-wall edge (local +Z) are deliberately left open — you still walk on from the
--- front and respawn onto the pad.
---
--- Posts collide (a real barrier at intervals); the rails themselves do not, so
--- nothing catches a jumping player at head height. Runs the full pad depth in the
--- pad's own yawed local space through `origin`, like everything else in buildPlot.
local RAIL_H = 3.4
local RAIL_POST_SPACING = 8
local function buildSideRailings(parent: Instance, origin: CFrame)
	local pad = Plots.PAD
	local folder = Instance.new("Folder")
	folder.Name = "SideRailings"

	local railX = pad.width / 2 - 0.7 -- just inside the Trim at width/2 - 0.5
	local z0, z1 = pad.minZ + 0.5, pad.maxZ - 0.5
	local span = z1 - z0
	local midZ = (z0 + z1) / 2
	local postCount = math.max(2, math.floor(span / RAIL_POST_SPACING) + 1)

	for _, side in { -1, 1 } do
		local x = side * railX

		for _, rail in { { y = RAIL_H, t = 0.4 }, { y = RAIL_H * 0.55, t = 0.3 } } do
			build(folder, origin, {
				name = "Rail",
				pos = { x, pad.topY + rail.y, midZ },
				size = { rail.t, rail.t, span },
				color = C.railGrey,
				material = "Metal",
				canCollide = false,
			})
		end

		for i = 0, postCount - 1 do
			local z = z0 + span * (i / (postCount - 1))
			build(folder, origin, {
				name = "RailPost",
				pos = { x, pad.topY + RAIL_H / 2, z },
				size = { 0.5, RAIL_H, 0.5 },
				color = C.railGrey,
				material = "Metal",
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
	-- Every accent piece (Trim, SignFrame, the cleansing-station Lamp, the two station
	-- sign subtitles) is built in this ONE neutral grey and carries an `Accent`
	-- attribute. A plot is colourless until an owner picks a hue in the Settings GUI:
	-- ExhibitService.renderAccent -> Plots.setPlotAccent walks those tagged pieces and
	-- repaints them from `data.plotColor` on claim, and back to grey on release. Plots
	-- used to pick a fixed hue by index here (Kit.PLOT_ACCENT, now gone).
	local accent = C.plotNeutral
	local pad = Plots.PAD

	-- THE STAGE, WEARING THE PLAZA'S STUDDED BOARD IN ONE FLAT COLOUR. One step up
	-- from the apron — a plot should feel like somewhere you walk onto, not part of
	-- the pavement — and one flat near-black charcoal (`C.baseFloor`): a shade below
	-- the base floor's own dark checker and flat where that alternates, so the six
	-- bases still read as their own thing against it. The board has been every shape
	-- by now (navy/grey checker → flat grey → flat near-black → a smooth no-stud
	-- plate); back to the studded board on request, one flat tone, so the studs catch
	-- the light like every other floor in the world without the pad alternating or
	-- turning to a mirror.
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

	-- The visible floor: the plaza's studded tile board (Hub.tileRect) on the plaza's
	-- own grid, `dark == light == C.baseFloor` so it reads as one flat studded tone
	-- rather than the plaza's green checker. Solid and queryable, same as the plaza's
	-- own tiles — the tile cap tops out at pad.topY and IS what a player stands on
	-- (the structural slab is recessed CAP below it).
	local tiles = Instance.new("Folder")
	tiles.Name = "PadTiles"
	Hub.tileRect(tiles, rect, tint)
	tiles.Parent = m

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

	-- Back wall (studded checkerboard, see buildBackWall) and the nameplate that
	-- carries the owner's display name. Dark neutral placard (`C.signText`) with light
	-- text in a thin accent frame — the frame lifts it clear of the equally-dark wall
	-- and carries the plot's hue the same way the side `Trim` does. Floated ~2 studs
	-- proud of the wall on two standoff arms (a wider gap threw a big soft shadow on
	-- the wall) and raised to `pad.topY + 11.5` so it clears the back row of stands.
	buildBackWall(m, origin)
	buildSideRailings(m, origin)
	local SIGN_Y = pad.topY + 11.5
	local SIGN_W, SIGN_H = 34, 4
	local SIGN_Z = pad.maxZ - 2.7 -- the wall's own front face is at pad.maxZ - 0.5
	local sign = build(m, origin, {
		name = "NameSign",
		pos = { 0, SIGN_Y, SIGN_Z },
		size = { SIGN_W, SIGN_H, 0.4 },
		color = C.signText,
		material = "SmoothPlastic",
	})
	-- Thin accent frame, flush with the sign's front face — four bars, corners lapped.
	local FRAME = 0.6
	for _, bar in {
		{ w = SIGN_W + FRAME * 2, h = FRAME, x = 0, y = (SIGN_H + FRAME) / 2 },
		{ w = SIGN_W + FRAME * 2, h = FRAME, x = 0, y = -(SIGN_H + FRAME) / 2 },
		{ w = FRAME, h = SIGN_H, x = (SIGN_W + FRAME) / 2, y = 0 },
		{ w = FRAME, h = SIGN_H, x = -(SIGN_W + FRAME) / 2, y = 0 },
	} do
		build(m, origin, {
			name = "SignFrame",
			pos = { bar.x, SIGN_Y + bar.y, SIGN_Z - 0.2 },
			size = { bar.w, bar.h, 0.6 },
			color = accent,
			material = "SmoothPlastic",
			canCollide = false,
			attributes = { Accent = true },
		})
	end
	-- Standoff arms back to the wall, in the wall's own colour so they read as the
	-- mounting rather than as part of the sign — the floated panel needs something
	-- visibly holding it.
	local armBackZ = pad.maxZ - 0.5
	local armFrontZ = SIGN_Z + 0.2
	for _, sx in { -14, 14 } do
		build(m, origin, {
			name = "SignArm",
			pos = { sx, SIGN_Y, (armFrontZ + armBackZ) / 2 },
			size = { 0.5, 0.5, armBackZ - armFrontZ },
			color = C.baseWall,
			material = "Metal",
		})
	end
	Kit.surfaceText(sign, Enum.NormalId.Front, "UNCLAIMED", C.labelText)

	-- No claim board any more: exhibit income is auto-deposited into the owner's
	-- wallet (ExhibitService.deposit), so there is nothing here to walk up to and
	-- collect. The nameplate on the back wall is the only thing that marks whose
	-- plot this is.

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

--- Lay the apron. Lives in this file rather than in Hub.luau because the shape is
--- derived from the pad rows, and Hub cannot see the rows: Plots requires Hub, so a
--- require back the other way would be a cycle. Hub owns the PATTERN and exports it;
--- this file owns the SHAPE and asks for it to be tiled.
---
--- ONE `Hub.tileRect` CALL, ONE `Hub.groundSlab` CALL. The visible cap tiles
--- `APRON_BOUNDS` (Plots.OUTER plus a wall-depth on three sides, so the tiles run
--- UNDER the Scenery perimeter wall rather than stopping at its inner face — see
--- that constant's own comment above `apronSkip`), punched by `apronSkip` (plaza +
--- every pad's own oriented footprint). The backing underneath is a SINGLE slab
--- over that exact same rect — safe because the rect IS the cap's own true outer
--- silhouette now (no circle to round off into a square and leave corners
--- floating over open air, the way the old circular apron's 12 backing bands
--- existed to avoid). The slab happily runs underneath the plaza's own separate
--- slab and every pad's own separate slab too, buried at the same recessed height
--- theirs already overlapped at today — one more coincident, invisible part is
--- cheaper than carving the plaza and six pads out of this one's own footprint
--- for no visible difference.
---
--- `darkFloor = true` on the tile call is the other half of Hub's dark base floor:
--- buildPlaza paints the plaza slab, this paints the rest of the ground — same
--- grid, same `Hub.inDarkFloor` test — so the base reads as one dark surface. The
--- only green it leaves is the Camp -> Stage 1 border strip, and `inDarkFloor`
--- produces that here too wherever this rect runs up against the `maxX =
--- PLAZA.maxX` clip. The dark flows around every plot footprint since
--- `apronSkip` punches those out before the colour is chosen.
local function buildApron(row: Model)
	local apron = Instance.new("Folder")
	apron.Name = "Apron"

	Hub.tileRect(apron, APRON_BOUNDS, { skip = apronSkip, darkFloor = true })
	Hub.groundSlab(apron, APRON_BOUNDS, "ApronSlab", PLAZA.thickness)

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
