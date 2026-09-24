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
	requires `Hub` again now — but to READ `Hub.PLAZA` and compute the ring from it, so
	the two cannot drift. Hub requires only Kit, so the direction is safe.

	Plot INTERNALS still face south (spawn near the front) —
	nothing about station detection cares which way a plot faces, it's all
	radius-based, so re-stacking the six plots into this column cost zero
	gameplay risk. The internal arrangement itself (stands + cleansing station)
	changed since; see "THE BASE LAYOUT" below.

	THE BASE LAYOUT — a plain 3-column x 4-row grid of stands (on request,
	replacing the old two-flanking-columns-plus-infill scheme so the middle no
	longer reads as a deliberate gap), while a 17-stud entrance-side extension
	carries the active washing equipment and an 18-stud back extension gives the
	grid room to spread:

	    ┌─────────────────────────────────────┐
	    │ ══════════ back landing ══════════   │
	    │   [stand] ║ [stand] ║ [stand]        │
	    │           ║         ║                │
	    │   [stand] ║ [stand] ║ [stand]        │   ║ = cream aisles
	    │           ║         ║                │
	    │   [stand] ║ [stand] ║ [stand]        │
	    │           ║         ║                │
	    │   [stand] ║ [stand] ║ [stand]        │
	    │   ═══════ cross band ═══════         │
	    ├──────── original front edge ─────────┤
	    │  [locker]                            │
	    │  WASHER [bottle]          TREADMILL  │
	    │           ║ entry (spawn) ║          │
	    └──────────[post]══arch══[post]───────┘

	THE GALLERY PASS (on request, picked from three live previews) dressed that grid
	up: the stands stand on waist-high plinths with an accent band, an empty one shows
	accent corner brackets and a full one a line in its item's rarity colour
	(Plots.setStandState); cream walkways (buildGalleryLanes) run in from an entrance
	arch naming the owner (buildEntranceArch); every fence post wears an accent cap.
	A claimed plot whose owner never picked a colour wears Plots.DEFAULT_ACCENTS.

	The Quarantine Locker (PLAN §10.2) — the physical rack of items you hauled home
	but can't clean yet — now sits in the +X corner right beside the cleansing
	station, moved off the far back-left wall on request so it is next to the tub
	you fill it at. Built here, filled by ExhibitService.renderLocker; see
	buildQuarantineLocker.

	12 stands: 3 columns (`GRID_COLS`, evenly spaced across x) by 4 rows
	(`GRID_ROWS`, evenly spaced from the back wall forward), numbered left to
	right then back row to front row — slot 1 is back-left, slot 3 is back-right,
	slot 12 is front-right (`slotOffset`). Also slightly bigger than the old
	plinths (RISER_BASE/RISER_TOP/RISER_RIM all up ~20%), on request. The
	cleansing station, its hose rig and the fluid bottle occupy the +X side of
	the entrance extension, the treadmill the -X side (where the wash pad stood
	until the pad was removed on request), with a deliberate safe gap between
	their station radii.

	FLOORS: THE GROUND 12 ARE FREE, AND UP TO TWO MORE STOREYS ARE BOUGHT.
	A base can be built up to Config/Floors.MAX = 3 floors. The ground floor's 12
	stands are usable from the moment a plot is claimed; each floor bought on top
	(Floors.PRICES, at the sign at the foot of the next flight of stairs) adds a
	4 x 2 gallery of Floors.UPPER_SLOTS more. Slot numbers run on across floors:
	1..12 are the ground grid above, 13..20 floor 2, 21..28 floor 3
	(slotPlacement). Every plot is BUILT with all of its floors; ExhibitService
	hides the ones its owner has not bought (Plots.setFloors) — see buildFloor.

	THE WORLD CONTRACT:
	    Pad         PlotIndex = n
	    Stand       StationKind = "pedestal", StationId = "<n>:<slot>", Radius = 7
	                PlotIndex = n, SlotIndex = s
	                — the base course of the display plinth (StandTop / StandRim /
	                Display are the rest of it); see buildDisplayStand. StandTop
	                carries the `SlotMarker` SurfaceGui and RarityLine<slot> wraps it;
	                both are switched by Plots.setStandState, never by name elsewhere.
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
	    Belt        StationKind = "treadmill", Radius = 5 — the treadmill's running
	                surface (see buildTreadmill). Standing on it IS training; no
	                prompt, no session. Services/TreadmillService owns the clock.
	    Console     UpgradesTreadmill = true + a ProximityPrompt — buys the next belt
	                rung. TreadmillService wires it at boot, by tag, the same way
	                ShopService wires the luck button.
	    Drive       the motor housing, repainted per rung by Plots.setTreadmillTier;
	                the Console's `Sign` billboard carries the speed and the bar.
	                Both are written by ExhibitService.renderTreadmill, never by name
	                from anywhere else.
	    Floor<f>    Model, one per floor above the ground (f = 2..Floors.MAX): deck,
	                pillars, the flight of stairs up to it, its railings and its
	                Stand/StandTop/Display parts for slots Floors.firstSlot(f)... Moved
	                in and out of ServerStorage by Plots.setFloors, never by name
	                elsewhere.
	    FloorSign<f>  Model; its SignBoard carries BuysFloor = f, PlotIndex = n and
	                a ProximityPrompt — builds floor f. ExhibitService wires it by
	                Kit.FLOOR_TAG and writes its billboard's Subtitle. Shown only on a
	                claimed plot whose owner has exactly f - 1 floors.
	    QuarantineLocker   no station attributes — a display cabinet. LockerSlot1..
	                Plots.LOCKER_SLOTS are hidden item anchors; LockerDoor is a Model
	                carrying ClosedPivot / OpenPivot CFrame attributes. Both are
	                filled/animated by ExhibitService.renderLocker from data.locker.

	The stand's StationId is "plot:slot" so the server can resolve exactly which
	pedestal a player is standing at without a spatial search of its own.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Floors = require(Shared.Config.Floors)
local Liquids = require(Shared.Config.Liquids)
local Treadmill = require(Shared.Config.Treadmill)
local ToolModels = require(Shared.ToolModels)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local Plots = {}
local BUILDER_SOURCE = "src/server/build/Plots.luau"
local BUILDER_VERSION = 62

local C = Kit.C
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

--- A Kit.billboard whose subtitle is painted in the plot's accent colour. Tags that
--- Subtitle label `Accent` so Plots.setPlotAccent finds and repaints it alongside the
--- Trim and the avatar plate's Ring. Same args as `billboard`; drop-in for the two
--- plot signs (cleansing station, fluid bottle) that pass `accent` as their subtitle
--- colour.
local function accentBillboard(part: BasePart, width: number, height: number, title: string, subtitle: string, accent: string)
	local gui = billboard(part, width, height, title, subtitle, accent)
	local sub = gui and gui:FindFirstChild("Subtitle")
	if sub then
		sub:SetAttribute("Accent", true)
	end
end

Plots.COUNT = 6
-- Every stand built per base, across all of its floors (Config/Floors): the ground
-- floor's 12 plus UPPER_SLOTS on each floor above. Floors a plot's owner has not
-- bought are built too, and hidden at runtime (Plots.setFloors).
Plots.VISIBLE_SLOTS = Floors.MAX_SLOTS

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
-- the stand grid can be spread over a deeper interior (GRID_ROWS below). The
-- back fence and accent trim both read maxZ, so they follow the edge out on
-- their own; the avatar plate floats over PAD_CENTER_Z instead, high above the
-- whole pad rather than tucked against either edge. Keeping explicit bounds
-- avoids pretending an asymmetric pad is centred on the plot origin.
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
--- not by the pads: `SHOP_CLUSTER_EAST_REACH = 53` (Hub.luau) was Shops.luau's
--- eastmost stall (the "Cleaner" counter, once at `RING_CENTER.x + 42`) plus its
--- ~11-stud half-width, and `FIELD_CLEARANCE` the margin kept past that. THAT
--- COUPLING IS NOW HISTORICAL: the shop row was re-centred on the plaza midpoint
--- (Hub.CAMP_ORIGIN) rather than on RING_CENTER, so the Cleaner stall
--- pulled ~14.5 studs back west and no longer reaches anywhere near Stage 1.
--- `SHOP_CLUSTER_EAST_REACH` is deliberately left at 53 so RING_CENTER stays put
--- — it is now the established ring position, a conservative bound rather than a
--- live measurement of anything in Shops.luau. (The pads have far more room to
--- spare here — see World.verify()'s own overlap checks, which are the real
--- authority on safety, not this comment.)
--- `facing` is a yaw in degrees. A pad is built with its back fence at +Z and its
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
local HALF_W = Plots.PAD.width / 2
local HALF_D = Plots.PAD.depth / 2
local PAD_CENTER_Z = (Plots.PAD.minZ + Plots.PAD.maxZ) / 2

--- The value lives in Hub.luau now (same formula, same point): the plaza floor paints a
--- octagon centred on this ring, and Hub cannot require this file to read it here.
--- Everything above is still the reasoning behind the number.
Plots.RING_CENTER = Hub.RING_CENTER

--- Pad-CENTRE orbit radius. WAS 180 (gave a uniform ~16-stud gap between every
--- one of the 6 pads' oriented rectangles at the original 30-degree spacing,
--- widened further once spacing grew to 34 degrees — see RING_ANGLES below).
--- SHRUNK TO 165 ON REQUEST, to pull the whole ring — and the walk from it to
--- the shop cluster — noticeably closer in.
---
--- 165 IS A CHECKED FLOOR, NOT A ROUND NUMBER PICKED THEN VERIFIED ONCE. 150 was
--- tried first (2 plots overlapping each other, 4 overlapping the plaza — see
--- World.verify()'s plot-overlap asserts), then 158 (the plot-plot overlaps
--- cleared, but 2 plots still sat in the plaza — RING_CENTER is close enough to
--- the plaza that plaza clearance, not pad spacing, is what actually bounds
--- this number at this radius). 165 is the first of those probes that came back
--- with zero failures, so it's what shipped rather than splitting the
--- difference toward 158 for a few more studs at real risk of the next rebuild
--- (a plaza resize, a pad depth change) tipping it back into failure.
--- `assertNoShopOverlap`'s sibling here — World.verify()'s plot-overlap check —
--- is the actual authority on whether any of this holds, every rebuild, not
--- this comment.
Plots.RING_RADIUS = 165

--- The walkway's outer disc radius — has to clear the farthest PAD CORNER from
--- RING_CENTER, not just the farthest pad centre. The entrance extension grows
--- inward toward the ring centre, so the farthest outward corner is the back
--- edge at local Z +44 (the +18 back extension, PAD_MAX_Z above):
--- `sqrt((RING_RADIUS+44)^2 + HALF_W^2)`.
---
--- RE-DERIVED FOR RING_RADIUS=165: sqrt(209^2 + 33^2) = ~211.6 studs, down from
--- ~226.4 at the old radius 180. 230 keeps the same real ~18-stud margin past
--- that reach 245 kept past 226.4 — this constant has to move by hand whenever
--- RING_RADIUS does, there is no live formula wiring the two together at
--- runtime. `apronSkip`, the backing bands, the Scenery perimeter wall and
--- World.verify()'s landmass square all already read this constant rather than
--- a hardcoded reach, so shrinking it here pulls the outer wall in with the
--- ring rather than leaving a wide empty belt around a now-smaller ring.
Plots.RING_OUTER = 230

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
---
--- The value lives in Hub.luau (`Hub.PLOT_BEARINGS`) for the same reason RING_CENTER
--- does: the plaza floor draws a gate path out along each of these bearings.
local RING_ANGLES = Hub.PLOT_BEARINGS

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

--- HOW FAR PAST THE RING THE GROUND IS ACTUALLY LAID. RING_OUTER is the apron's
--- true edge -- every margin / pad-corner-reach figure above is measured to it and
--- stays that way -- but the Scenery perimeter wall (`Scenery.buildBaseWalls`)
--- sits just OUTSIDE that edge: its arc is centred on RING_OUTER + WALL_THICKNESS/2
--- and the wall is WALL_THICKNESS (8) deep, so its INNER face lands right on
--- r = RING_OUTER and its outer face ~8 studs past. The tiled cap and its backing
--- bands both used to stop dead at RING_OUTER, which left a thin scalloped strip of
--- open void between the cap's staircase edge (a 4-stud tile grid clipped to a
--- circle wobbles +/- a tile) and that wall face -- it reads as bright slivers
--- along the curve at the shallow angle a standing player sees it from.
---
--- Laying the ground a full wall-depth past the ring runs it continuously UNDER the
--- wall instead, so there is no bearing where the floor gives out before the wall
--- does. The extra rim is hidden beneath a 56-stud wall from every camera inside
--- the camp, so overshooting is free; undershooting is the bug. +10 is the 8 the
--- wall needs plus a 2-stud cushion -- Plots cannot require Scenery to read
--- WALL_THICKNESS directly (that is the cycle the apron comment below and
--- Scenery's own header both describe), so the cushion covers the coupling.
local APRON_CAP_RADIUS = Plots.RING_OUTER + 10

local function apronSkip(x: number, z: number): boolean
	local dx, dz = x - Plots.RING_CENTER.x, z - Plots.RING_CENTER.z
	if dx * dx + dz * dz > APRON_CAP_RADIUS * APRON_CAP_RADIUS then
		return true -- outside the disc (laid past RING_OUTER to tuck under the perimeter wall)
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
		if Kit.pointInOrientedRect(x, z, padRect(c, PAD_SKIP_INSET)) then
			return true
		end
	end
	return false
end

--- STAND LAYOUT — a plain 3-column x 4-row grid, 12 stands total, replacing the
--- old two-flanking-columns-plus-infill scheme (on request: a uniform grid reads
--- better than a deliberate gap down the middle).
---
--- GRID_COLS are 3 evenly spaced x's (pitch 20, symmetric about x = 0): ±20
--- leaves a wide margin to the side Trim (well past the old flanking columns'
--- ±25), and the open floor either side of the centre column (20 studs) clears
--- the bigger stand footprint below with room to spare.
---
--- GRID_ROWS are 4 evenly spaced z's (pitch 13), ROW_TOP first — closest to the
--- back wall — counting DOWN from there toward the entrance, the same 4-deep
--- count the old flanking columns used. Pitch 13 (down slightly from the old
--- 12.5, to hold the front row back from PlotSpawn now that RISER_BASE below is
--- ~20% bigger) still clears the stand footprint row to row, and leaves the
--- front row (z = -6) clear of PlotSpawn (z = -24).
---
--- slotOffset numbers left to right, back row to front row: slot 1 is
--- (GRID_COLS[1], GRID_ROWS[1]) i.e. back-left, slot 3 is back-right, slot 12 is
--- front-right.
local GRID_COLS = { -20, 0, 20 }
local GRID_ROWS = { 33, 20, 7, -6 }

local function slotOffset(slot: number): (number, number)
	local col = (slot - 1) % #GRID_COLS
	local row = math.floor((slot - 1) / #GRID_COLS)
	return GRID_COLS[col + 1], GRID_ROWS[row + 1]
end
assert(#GRID_COLS * #GRID_ROWS == Floors.GROUND_SLOTS, "the ground grid must hold exactly Floors.GROUND_SLOTS stands")

--- THE UPPER FLOORS' GALLERY — 4 columns x 2 rows (Floors.UPPER_SLOTS = 8), on every
--- floor above the ground (see buildFloor). Pitch 13 across keeps the outer columns'
--- plinths (edge at +/-23.95) clear of the stairwell guard rail at +/-25.5 on one side
--- and the next flight's handrail at +/-26.4 on the other. The rows sit either side of
--- the deck's middle, the front one well behind the deck's front rail.
---
--- Numbered the same way as the ground: left to right, back row first.
local UPPER_COLS = { -19.5, -6.5, 6.5, 19.5 }
local UPPER_ROWS = { 28, 6 }
assert(#UPPER_COLS * #UPPER_ROWS == Floors.UPPER_SLOTS, "the upper grid must hold exactly Floors.UPPER_SLOTS stands")

--- The top of `floor`'s deck — what a player on it stands on. Floor 1 is the pad.
local function floorTopY(floor: number): number
	return Plots.PAD.topY + (floor - 1) * Floors.HEIGHT
end

--- Where a slot's stand goes: plot-local x and z, and the top of the floor it stands
--- on. Slots run on across floors (Config/Floors), so 1..12 are the ground grid above
--- exactly as they always were, and everything past that is an upper floor's grid.
local function slotPlacement(slot: number): (number, number, number)
	local floor, i = Floors.floorOf(slot)
	assert(floor ~= nil and i ~= nil, `slot {slot} is on no floor`)
	if floor == 1 then
		local x, z = slotOffset(i)
		return x, z, floorTopY(1)
	end
	local col = (i - 1) % #UPPER_COLS
	local row = math.floor((i - 1) / #UPPER_COLS)
	return UPPER_COLS[col + 1], UPPER_ROWS[row + 1], floorTopY(floor)
end

--- THE DISPLAY STAND — a two-course studded riser on a waist-high plinth. The riser
--- replaced the tall marble-and-slate column this used to be: a broad base course, a
--- slightly inset top course stacked on it, and a raised lip framing a recessed panel
--- the item rests in. Grey studded plastic — `studs = true` forces Material.Plastic
--- and stud-textures every face (see Kit.build), and the greys are Kit.C.standGrey*.
---
--- THE PLINTH UNDER IT IS THE GALLERY PASS (on request, picked from three live
--- previews). Knee-high risers read as paving slabs from the entrance — an empty one
--- did not say "a nuke goes here". `PLINTH` lifts the whole riser stack onto a studded
--- foot and column with an accent band round the top, so a stand is a pedestal you
--- walk up to. Nothing about the stack itself changed shape; it just starts PLINTH.h
--- higher, and every part keeps its name.
---
--- THE BASE COURSE IS THE STATION PART. It keeps the `Stand{slot}` name and every
--- attribute the world contract (this file's header) publishes. Detection is
--- radius-based off the part CENTRE (StationService, Radius = 7), and the lift brings
--- that centre (pad.topY + ~2.35) CLOSER to a standing player's root than the old
--- knee-high one was, so the reach only gets easier.
---
--- RISER_SURFACE is the height of the top course's top face above the riser's own
--- foot — where the item sits. `Display{slot}` rides 1.2 studs above it, and
--- ExhibitService seats the model and its StandCard from Display's live position, so
--- both follow the lift with no change on that side.
---
--- EMPTY AND FULL LOOK DIFFERENT, and Plots.setStandState is the switch. An empty
--- stand shows `SlotMarker` — a dark inset with accent corner brackets drawn by a
--- SurfaceGui on the top course (GUI, not parts, so twelve of them cost no geometry).
--- A full one hides it and lights `RarityLine`, a thin band wrapped round the top
--- course in the displayed item's rarity colour. Neon, deliberately: it belongs to
--- the item on show, under the same exception the nuke FX use.
local RISER_BASE = { w = 8.9, h = 1.1 }
local RISER_TOP = { w = 7.6, h = 0.85 }
local RISER_RIM = { h = 0.26, thickness = 0.6 } -- the raised frame around the recessed panel
local RISER_SURFACE = RISER_BASE.h + RISER_TOP.h
local PLINTH = {
	h = 1.8, -- how far the riser stack is lifted
	footW = 8.4,
	footH = 0.3,
	columnW = 7.2,
	bandW = 7.4,
	bandH = 0.4,
}
-- The slot marker, in studs on the top course's face: a dark inset square, and
-- L-shaped corner brackets (arm length x thickness) just inside the rim.
local SLOT_MARK = { inset = 5.6, arm = 1.3, thick = 0.3, reach = 2.75, color = "3A3F47" }

--- The empty-slot marker: a SurfaceGui on the top course's top face. Built enabled
--- (every stand starts empty); Plots.setStandState hides it once something is shown.
--- The brackets carry `Accent`, so Plots.setPlotAccent repaints them with the Trim.
local function buildSlotMarker(top: BasePart, accent: string)
	local width = RISER_TOP.w
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SlotMarker"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = top

	local function box(name: string, cx: number, cz: number, sx: number, sz: number, color: string): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5 + cx / width, 0.5 + cz / width)
		f.Size = UDim2.fromScale(sx / width, sz / width)
		f.BackgroundColor3 = Color3.fromHex(color)
		f.BorderSizePixel = 0
		f.Parent = gui
		return f
	end

	box("Inset", 0, 0, SLOT_MARK.inset, SLOT_MARK.inset, SLOT_MARK.color)
	-- Symmetric under every flip and axis swap, so whichever way the canvas happens to
	-- be oriented on the top face does not matter.
	local along = SLOT_MARK.reach - SLOT_MARK.arm / 2 + SLOT_MARK.thick / 2
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box("Bracket", sx * along, sz * SLOT_MARK.reach, SLOT_MARK.arm, SLOT_MARK.thick, accent):SetAttribute("Accent", true)
			box("Bracket", sx * SLOT_MARK.reach, sz * along, SLOT_MARK.thick, SLOT_MARK.arm, accent):SetAttribute("Accent", true)
		end
	end
end

local function buildDisplayStand(parent: Instance, origin: CFrame, index: number, slot: number, accent: string)
	-- `floorY` is the top of whichever floor this slot stands on (slotPlacement).
	local ox, oz, floorY = slotPlacement(slot)
	-- The riser stack's own foot: the plinth's top.
	local lift = floorY + PLINTH.h
	-- Every stand is usable from the start — there is no locked/dim state any more.
	-- Base course darker than the top course and its frame, so the two courses read
	-- as lit from above.
	local topGrey = C.standGrey

	-- ── The plinth ────────────────────────────────────────────
	-- A light foot, a dark column, and an accent band wrapping the column's top just
	-- under the base course's overhang — the band is the plot colour at every stand.
	build(parent, origin, {
		name = "PlinthFoot",
		pos = { ox, floorY + PLINTH.footH / 2, oz },
		size = { PLINTH.footW, PLINTH.footH, PLINTH.footW },
		color = C.standGrey,
		material = "Plastic",
		studs = true,
	})
	build(parent, origin, {
		name = "PlinthColumn",
		pos = { ox, floorY + PLINTH.footH + (PLINTH.h - PLINTH.footH) / 2, oz },
		size = { PLINTH.columnW, PLINTH.h - PLINTH.footH, PLINTH.columnW },
		color = C.standGreyDark,
		material = "Plastic",
		studs = true,
	})
	build(parent, origin, {
		name = "PlinthBand",
		pos = { ox, lift - PLINTH.bandH / 2, oz },
		size = { PLINTH.bandW, PLINTH.bandH, PLINTH.bandW },
		color = accent,
		material = "SmoothPlastic",
		canCollide = false,
		attributes = { Accent = true },
	})

	-- ── The riser stack, on the plinth ────────────────────────
	build(parent, origin, {
		name = `Stand{slot}`,
		pos = { ox, lift + RISER_BASE.h / 2, oz },
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

	local top = build(parent, origin, {
		name = `StandTop{slot}`,
		pos = { ox, lift + RISER_BASE.h + RISER_TOP.h / 2, oz },
		size = { RISER_TOP.w, RISER_TOP.h, RISER_TOP.w },
		color = topGrey,
		material = "Plastic",
		studs = true,
	})
	buildSlotMarker(top, accent)

	-- The rarity line: a hair proud of the top course on every side, hidden until
	-- Plots.setStandState colours it for whatever is on display.
	local line = build(parent, origin, {
		name = `RarityLine{slot}`,
		pos = { ox, lift + RISER_BASE.h + RISER_TOP.h / 2, oz },
		size = { RISER_TOP.w + 0.06, 0.2, RISER_TOP.w + 0.06 },
		color = accent,
		material = "Neon",
		transparency = 1,
		canCollide = false,
	})
	line.CastShadow = false

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
			pos = { ox + bar.dx, lift + RISER_SURFACE + RISER_RIM.h / 2, oz + bar.dz },
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
		pos = { ox, lift + RISER_SURFACE + 1.2, oz },
		size = { 1.7, 1.7, 1.7 },
		color = accent,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
		attributes = { PlotIndex = index, SlotIndex = slot },
	})

	-- NO LIGHT ON THE PLINTH. Each stand used to carry a dim warm PointLight (range 6,
	-- brightness 0.35) as a "gallery spot" — 72 across the ring, every one casting
	-- shadows (Kit.light's default), under a sky that never gets past mid-afternoon
	-- (Config/Sky clockTime 13.6-16.0). Invisible in daylight, and still paying for a
	-- shadow pass each.
end

--- Show one stand as empty (`color == nil`: slot brackets on, rarity line off) or
--- full (`color` = the displayed item's rarity colour: brackets off, line on in that
--- colour). ExhibitService.renderStand calls it every time a stand changes; a plot
--- built before the gallery pass has neither piece and this quietly does nothing.
function Plots.setStandState(plot: Instance?, slot: number, color: Color3?)
	if plot == nil then
		return
	end
	local top = plot:FindFirstChild(`StandTop{slot}`, true)
	local marker = top and top:FindFirstChild("SlotMarker")
	if marker and marker:IsA("SurfaceGui") then
		marker.Enabled = color == nil
	end
	local line = plot:FindFirstChild(`RarityLine{slot}`, true)
	if line and line:IsA("BasePart") then
		line.Transparency = if color then 0 else 1
		if color then
			line.Color = color
		end
	end
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

--- The radiation trefoil painted on one square face of `part`, `studs` across, in a
--- black border: three 60-degree blades round a hub, one pointing down like the sign.
--- Each blade is a fan of thin rotated bars close enough together to read as a solid
--- wedge -- HudController's rads badge draws it the same way, because the Unicode
--- trefoil renders as a colour emoji and ignores TextColor3. A GUI rather than parts:
--- blocks cannot make a wedge, and a trefoil of stacked blocks at placard size read as
--- a fan.
local function paintTrefoil(part: BasePart, face: Enum.NormalId, studs: number, ink: string)
	local pps = 100
	local px = studs * pps
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Trefoil"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.MaxDistance = 80
	gui.Parent = part

	local color = Color3.fromHex(ink)
	local function box(name: string, x: number, y: number, w: number, h: number, rotation: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(x, y)
		frame.Size = UDim2.fromOffset(w, h)
		frame.Rotation = rotation
		frame.BackgroundColor3 = color
		frame.BorderSizePixel = 0
		frame.Parent = gui
		return frame
	end

	local border = box("Border", px / 2, px / 2, px, px, 0)
	border.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = px * 0.05
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = border

	local centre = px / 2
	local inner, outer = px * 0.13, px * 0.42
	local mid, length = (inner + outer) / 2, outer - inner
	for _, blade in { 90, 210, 330 } do
		for spread = -26, 26, 4 do
			local angle = blade + spread
			local rad = math.rad(angle)
			box("Blade", centre + mid * math.cos(rad), centre + mid * math.sin(rad), length, px * 0.035, angle)
		end
	end
	local hub = box("Hub", centre, centre, px * 0.16, px * 0.16, 0)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = hub
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
	-- bolts; the tank itself is hazard yellow.
	local BODY, FIT = C.standGreyDark, C.steelDark

	-- Tucked into the front-left corner of the deck, well clear of the straight walk-up
	-- to WashSpot and out of the tub's own sightline from the aisle. The whole rig
	-- follows (px, pz) so the bay moves as one.
	local px, pz = cx + 7, cz - 9

	-- A skid under the housing, so the pump reads as a unit set down and bolted rather
	-- than a crate left on the tiles.
	build(parent, origin, { name = "PumpSkid", pos = { px, T + 0.35, pz }, size = { 3.2, 0.7, 2.8 }, color = BODY, material = "Plastic", studs = true })

	-- ── The pump: tank + motor on the skid ────────────────────
	-- PICKED BY THE USER from a round of AI-generated pump models ("D", built from
	-- primitives), then rebuilt here out of studded parts so it lives in code, survives a
	-- rebuild and wears the base's stud texture. A banded yellow pressure tank with a
	-- gauge and a valve handwheel, and beside it a finned grey motor driving a spoked
	-- flywheel. The gauge and the flywheel face the aisle (authored -Z), the side you
	-- walk past; the motor's end cap and a warning placard face the plot entrance (+X).
	-- The reel still hangs off the tank's -X side on its axle, and the pipe to the tub
	-- still leaves from the tank's +Z side.
	local TANK_YELLOW, MOTOR_GREY, METAL_LIGHT = "FAD214", "82878C", "B4B9BE"
	local tx = px - 0.35
	local tankR, tankBottom, tankTop = 0.8, T + 0.7, T + 3.7
	build(parent, origin, {
		name = "HosePump",
		pos = { tx, (tankBottom + tankTop) / 2, pz },
		size = { tankTop - tankBottom, tankR * 2, tankR * 2 },
		color = TANK_YELLOW,
		material = "Plastic",
		studs = true,
		shape = "Cylinder",
		rot = Kit.R.cylUp,
	})
	for _, bandY in { T + 1.3, T + 3.1 } do
		build(parent, origin, {
			name = "PumpHoop",
			pos = { tx, bandY, pz },
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
		pos = { tx, tankTop, pz },
		size = { tankR * 2, tankR * 2, tankR * 2 },
		color = TANK_YELLOW,
		material = "Plastic",
		studs = true,
		shape = "Ball",
		canCollide = false,
	})

	-- The valve on the crown: a base, a stem, and a spoked handwheel whose rim is a
	-- ring of studded segments rather than a solid disc, so it reads as a wheel.
	local domeTop = tankTop + tankR
	build(parent, origin, { name = "PumpValve", pos = { tx, domeTop + 0.07, pz }, size = { 0.15, 0.48, 0.48 }, color = MOTOR_GREY, material = "Plastic", studs = true, shape = "Cylinder", rot = Kit.R.cylUp, canCollide = false })
	build(parent, origin, { name = "PumpValveStem", pos = { tx, domeTop + 0.3, pz }, size = { 0.32, 0.24, 0.24 }, color = C.hazardBlack, material = "Metal", shape = "Cylinder", rot = Kit.R.cylUp, canCollide = false })
	local wheelY = domeTop + 0.5
	polygonRing(parent, origin, {
		name = "PumpValveWheel",
		sides = 10,
		cx = tx,
		cz = pz,
		apothem = 0.55,
		thickness = 0.12,
		y = wheelY,
		height = 0.12,
		color = C.hazardBlack,
		studs = true,
		canCollide = false,
	})
	build(parent, origin, { name = "PumpValveHub", pos = { tx, wheelY, pz }, size = { 0.2, 0.36, 0.36 }, color = C.hazardBlack, material = "Plastic", studs = true, shape = "Cylinder", rot = Kit.R.cylUp, canCollide = false })
	for k = 0, 1 do
		build(parent, origin, { name = "PumpValveSpoke", pos = { tx, wheelY, pz }, size = { 1.1, 0.08, 0.1 }, color = C.hazardBlack, material = "Metal", rot = Kit.ang(0, 45 + k * 90, 0), canCollide = false })
	end

	-- THE GAUGE, on the aisle face of the tank: a grey case on a stub mount, a white
	-- face with eight ticks, and a red needle that wanders about the dial
	-- (StationMotionController), because a pressure gauge that never twitches reads as
	-- a sticker.
	local gy = T + 2.35
	local gaugeZ = pz - tankR - 0.02
	build(parent, origin, { name = "GaugeMount", pos = { tx, gy, pz - tankR + 0.2 }, size = { 0.7, 0.6, 0.6 }, color = MOTOR_GREY, material = "Plastic", studs = true, shape = "Cylinder", rot = CYL_ALONG_Z, canCollide = false })
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
	local motorX, motorY, motorZ = tx + 1.2, T + 1.25, pz + 0.2
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
			color = if k == 0 then TANK_YELLOW else C.hazardBlack,
			material = "Plastic",
			studs = true,
			canCollide = false,
		})
	end
	flywheel.WorldPivot = shaft
	flywheel.Parent = parent
	Kit.motion(flywheel, { kind = "spin", axis = "Z", rate = 4 })

	-- The trefoil, on a warning placard on the tank's entrance face above the motor:
	-- yellow, black-bordered, the real sign. A flat placard on a standoff rather than
	-- paint, because the mark is flat and the tank is not.
	local PLACARD = 0.9
	local plateY = T + 2.5
	build(parent, origin, { name = "PumpPlacardMount", pos = { tx + tankR - 0.1, plateY, pz }, size = { 0.3, 0.45, 0.45 }, color = MOTOR_GREY, material = "Metal", canCollide = false })
	local placard = build(parent, origin, {
		name = "PumpPlacard",
		pos = { tx + tankR + 0.06, plateY, pz },
		size = { PLACARD, PLACARD, 0.08 },
		color = C.hazard,
		material = "SmoothPlastic",
		rot = Kit.ang(0, -90, 0),
		canCollide = false,
	})
	paintTrefoil(placard, Enum.NormalId.Front, PLACARD, C.hazardBlack)

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

	-- ── The plumbing ──────────────────────────────────────────
	-- A round pipe from the foot of the tank to the tub's front diagonal wall, on
	-- studded clamps, with a ball elbow at the turn and a flange where it goes in. It
	-- used to be a square conduit that ran on INTO the tub, to its centre line -- harmless
	-- while the tub was solid, a bar across the water now that it is not -- so it stops at
	-- the wall. `wallX` is where that wall's outer face crosses the pipe's line, and it
	-- follows TUB_SHELL rather than being a second copy of it.
	local pipeY, pipeZ = T + 0.95, cz - 3
	local wallX = cx + (TUB_SHELL.apothem + TUB_SHELL.wall / 2) * math.sqrt(2) - (cz - pipeZ) - 0.1
	local tankFront = pz + tankR
	build(parent, origin, {
		name = "Conduit",
		pos = { tx, pipeY, (tankFront + pipeZ) / 2 },
		size = { pipeZ - tankFront, 0.45, 0.45 },
		color = FIT,
		material = "Metal",
		shape = "Cylinder",
		rot = CYL_ALONG_Z,
		canCollide = false,
	})
	build(parent, origin, { name = "ConduitElbow", pos = { tx, pipeY, pipeZ }, size = { 0.62, 0.62, 0.62 }, color = FIT, material = "Metal", shape = "Ball", canCollide = false })
	build(parent, origin, {
		name = "Conduit",
		pos = { (tx + wallX) / 2, pipeY, pipeZ },
		size = { tx - wallX, 0.45, 0.45 },
		color = FIT,
		material = "Metal",
		shape = "Cylinder",
		canCollide = false,
	})
	build(parent, origin, { name = "ConduitFlange", pos = { wallX + 0.2, pipeY, pipeZ }, size = { 0.16, 0.8, 0.8 }, color = FIT, material = "Metal", shape = "Cylinder", canCollide = false })
	-- Clamps: one on the bare floor under the first run, one on the deck under the
	-- second. Each stands from whatever it is on up to the pipe's underside.
	local pipeUnder = pipeY - 0.225
	build(parent, origin, { name = "ConduitClamp", pos = { tx, (T + pipeUnder) / 2, pz + tankR + 1.1 }, size = { 0.7, pipeUnder - T, 0.4 }, color = BODY, material = "Plastic", studs = true, canCollide = false })
	build(parent, origin, { name = "ConduitClamp", pos = { (tx + wallX) / 2, (T + 0.15 + pipeUnder) / 2, pipeZ }, size = { 0.4, pipeUnder - (T + 0.15), 0.7 }, color = BODY, material = "Plastic", studs = true, canCollide = false })

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
	build(m, origin, { name = "Deck", pos = { 21, T - 0.35, -32 }, size = { 12.5, 1.0, 10 }, color = BODY, material = "Plastic", studs = true })
	for _, e in {
		{ x = 21, z = -27, sx = 13.1, sz = 0.6 },
		{ x = 27.25, z = -32, sx = 0.6, sz = 10.6 },
		{ x = 14.75, z = -32, sx = 0.6, sz = 10.6 },
	} do
		build(m, origin, { name = "DeckKerb", pos = { e.x, T + 0.25, e.z }, size = { e.sx, 0.35, e.sz }, color = FACE, material = "Plastic", studs = true, canCollide = false })
	end
	-- The front kerb -- the edge you walk over to reach the wash mark -- is hazard-striped:
	-- studded yellow and black bricks, the toy-brick version of the tape round a real
	-- decontamination bay, and the first thing on the plot that says what this bay is for.
	local STRIPES = 10
	local stripeW = 13.1 / STRIPES
	for s = 0, STRIPES - 1 do
		build(m, origin, {
			name = "DeckKerb",
			pos = { 21 - 13.1 / 2 + (s + 0.5) * stripeW, T + 0.25, -37 },
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
--- RIGHT NEXT TO THE TUB, on request. The table stands against the tub's +Z face
--- (the rim's flat side at z ~= -27.8), a few tenths of a stud off it, so tub and
--- bottle read as one station. That side is free: the gantry posts are at x ~= 30,
--- the hose rig and pump are off the -Z end, and the player washes from the -X side
--- (WashSpot, plot (20, -32)). Nothing reaches over the tub (crust-fills-the-wash-bay).
--- Round, so it needs no pivot: every part below is written straight in plot space.
---
--- NO PROMPT OF ITS OWN. Walking within reach of your own bottle opens the fluid
--- panel on your screen (LiquidController): the loaded fluid, ROLL, and the Luck
--- upgrade. So the tub's "Wash" E prompt is the only prompt in this corner. The reach
--- is kept short (LiquidController's PANEL_REACH) so the wash spot, plot (20, -32),
--- is well outside it.
local BOTTLE = {
	x = 26,
	z = -26.1,
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
	stationModel:SetAttribute("Liquid", liquidId or Liquids.WATER)
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
--- fill it at. Now it sits in the +X corner behind the cleansing bay (plot
--- x ~= 30, z ~= -15.5), still opening toward the plot entrance (-Z). It stood at
--- z ~= -24, right against the gantry, until the fluid bottle needed that spot
--- (buildFluidBottle); it moved BACK, toward the grid's front row, on request, and
--- stays clear of that row's plinths. `ExhibitService` finds every part of it by
--- name, so neither move needed anything on its side.
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
	local lx, lz = 30, -15.5
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

-- ── The treadmill ─────────────────────────────────────────────────────────
--
-- Where speed comes from, now that the Boots track is retired (Config/Treadmill).
-- Step on the belt and the number climbs; press E on the console to buy a faster
-- belt. Services/TreadmillService owns both halves.
--
-- IT SHARES THE ENTRANCE SERVICE STRIP with the cleansing station (+X), and the
-- clearances here are a CORRECTNESS constraint, not a layout
-- preference. Training is an edge, so overlapping station radii would mean a player at
-- one machine being registered at another. MOVED TO THE -X SIDE, into the wash pad's
-- old spot, when the pad was removed on request -- it used to stand in the middle of
-- the strip, on the entrance path. Belt centre sits at plot-local (-21, -35), Radius 5:
--
--   to the Basin  (26, -32), Radius 9 ...... 47.1 studs against a 14-stud combined reach
--   to PlotSpawn  (0, -24), 6x6 ............ 23.7 studs against 8
--
-- Keep those gaps if either moves. World.verify() is the actual authority and asserts
-- the first every rebuild, not this comment. The gears reach plot x ~= -25.5 against
-- the -X accent trim at -32.
--
-- THE RUNNER FACES -Z, out through the entrance arch at the wasteland, with the
-- console at that end, clear of the spawn pad.
local TREADMILL = {
	cx = -21,
	cz = -35,
	beltW = 5.2, -- the running surface, across the runner
	-- 9 along the run. The motor block at the head reaches plot-local z -42.6 against a
	-- pad that stops at -43, and the hazard ramp at the tail -28.4 against PlotSpawn at
	-- -27; lengthen the belt and one of those two gives.
	beltL = 9,
	beltTop = 0.2, -- what you stand on, relative to the pad top
	-- FOUR CHEVRONS AT A PITCH THAT DIVIDES `beltL` EXACTLY (4 x 2.25 = 9). That is
	-- what makes the scroll seamless: TreadmillController wraps each one modulo the
	-- belt's own length, so after a full belt-length of travel the pattern is back
	-- where it started. Break the division and the wrap becomes visible.
	chevrons = 4,
	chevronPitch = 2.25, -- 4 x 2.25 = beltL exactly
	wallX = 3.1, -- centre of each hazard wall, out from the belt's centreline
	headZ = -6.6, -- the motor block's centre, relative to the belt's
}

--- THE HAZARD CONVEYOR PALETTE, picked from three live mock-ups (option 2 of Arcade
--- Runner / Hazard Conveyor / Reactor Wheel). Hazard yellow and a near-black for the
--- stripes, dark steel for the machine, a bare steel for the rollers and gears.
local HAZ_YELLOW, HAZ_BLACK = "FFC21A", "22252A"
local HAZ_STEEL, HAZ_STEEL_DARK = "6B7682", "2E3338"
local HAZ_RUST, HAZ_BEACON = "8A4B2A", "FF6A00"
--- The belt's own surface and the chevrons on it. The tread is only a couple of steps
--- off the belt -- readable as motion, not as stripes painted on a road.
local BELT_DARK = "1A1F24"
local BELT_TREAD = "4A5561"
--- The CRT leans back 15 degrees so its screen looks up at whoever is on the belt.
local CONSOLE_TILT = Kit.ang(-15, 0, 0)
--- The screen: dark glass, hazard-yellow readout, a dim track for the progress bar.
local SCREEN_DARK, SCREEN_INK, SCREEN_DIM = "14262B", "FFC21A", "3A3A2A"
local SCREEN_BARS = 7

--- The drive housing's colour per rung. Bare steel at the bottom, reactor orange at
--- the top; deliberately clear of the quarantine red and the stages' hazard greens,
--- the same rule Plots.DEFAULT_ACCENTS follows.
local TREADMILL_DRIVE = {
	"6E7683", -- Scrap Belt: bare steel
	"7A8796", -- Chain Runner
	"5E8CA8", -- Geared Treadplate: cold blue
	"4F9E86", -- Servo Track: servo teal
	"C98A2E", -- Reactor Mill: warm
	"E8631F", -- Isotope Strider: hot
}
assert(#TREADMILL_DRIVE == #Treadmill.TIERS, "one drive colour per treadmill rung")

--- Dress one plot's treadmill in a belt rung. Returns the tier actually applied, or
--- nil if this plot has no treadmill to dress (a place file saved before the machine
--- existed — degrade quietly, exactly as setHoseTier does).
---
--- A REPAINT AND A RELABEL, NOT SIX MODELS. The hose track earns its seven authored
--- silhouettes because you hold it up to your own face at a tub; a treadmill is a box
--- you stand on and look away from, and six variants of it would be six times the
--- parts on every plot in the world for a difference nobody is positioned to see. So
--- the rung reads off the drive housing's colour and off the sign — which is also
--- where the numbers that actually matter live.
---
--- `points` (the owner's lifetime Speed) is optional and only feeds the sign. nil
--- means "unclaimed plot", which prints level 1 and no progress, because a bar that
--- always reads empty on six plots is worse than no bar at all.
function Plots.setTreadmillTier(treadmill: Instance?, tier: number?, points: number?): number?
	if treadmill == nil then
		return nil
	end

	local wanted = math.clamp(math.floor(tier or 1), 1, Treadmill.maxTier())
	local def = Treadmill.tier(wanted)

	-- The housing is the rung you can see from across the plot: it walks a ladder from
	-- bare steel up to the hot end, so a maxed belt reads as machinery rather than as
	-- scrap without anyone having to read the sign.
	-- Every part tagged `TierPaint` (the cowl, its hood, the rail grips) wears it; `Drive`
	-- by name as well, for a world built before the tag existed.
	local paint = Color3.fromHex(TREADMILL_DRIVE[wanted])
	local drive = treadmill:FindFirstChild("Drive", true)
	if drive and drive:IsA("BasePart") then
		drive.Color = paint
	end
	for _, d in treadmill:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("TierPaint") then
			d.Color = paint
		end
	end

	local sign = treadmill:FindFirstChild("Sign", true)
	local title = sign and sign:FindFirstChild("Title")
	local subtitle = sign and sign:FindFirstChild("Subtitle")
	local level, progress = Treadmill.levelFor(points or 0)
	local maxed = level >= Treadmill.MAX_LEVEL
	if title then
		(title :: TextLabel).Text = string.format("SPEED LV %d", level)
	end

	-- The console's own screen says the same number to the runner, with the bar to the
	-- next level. Absent on a world built before the screen faced the belt.
	local readout = treadmill:FindFirstChild("Readout", true)
	local screenSpeed = readout and readout:FindFirstChild("Speed")
	if screenSpeed and screenSpeed:IsA("TextLabel") then
		screenSpeed.Text = string.format("LV %d", level)
	end
	local fill = readout and readout:FindFirstChild("Fill", true)
	if fill and fill:IsA("Frame") then
		local shown = if points == nil then 0 elseif maxed then 1 else progress
		fill.Size = UDim2.fromScale(math.clamp(shown, 0, 1), 1)
	end
	if subtitle then
		(subtitle :: TextLabel).Text = if points == nil or maxed
			then `{def.name} — +{def.rate} Speed/s`
			else string.format("%s — %d%% to LV %d", def.name, math.floor(progress * 100), level + 1)
	end

	treadmill:SetAttribute("Tier", wanted)
	return wanted
end

--- THE HAZARD CONVEYOR, picked by the user from three live mock-ups built on empty
--- plots in a Play session ("something like 2, don't have to do too much"). An
--- industrial belt rather than a gym machine, which is what this world is:
---
---   * yellow/black studded hazard walls down both sides of a dark, recessed belt,
---     with chevrons that scroll ALL THE TIME (TreadmillController) so the machine
---     reads as running from across the plot, not only while somebody is on it;
---   * a dark steel motor block at the head, hazard-striped on top, with a gear
---     turning on each flank (StationMotionController), two exhaust stacks and an
---     orange beacon;
---   * a chunky CRT on an arm, leaning back at the runner, carrying the readout;
---   * a striped ramp at the tail, which is where you step on.
---
--- THE STATION CONTRACT IS UNCHANGED. `Belt` carries StationKind/Radius at the same
--- plot-local centre (World.verify's clearances are measured from it), `Console`
--- carries UpgradesTreadmill + the prompt + the billboard, `Drive` (the motor block)
--- (tagged `TierPaint`) is what setTreadmillTier repaints per belt rung, the
--- chevron arms are `Slat` and the end drums `Roller` because TreadmillController
--- scrolls and turns those, and the screen's SurfaceGui is still `Readout` with
--- `Speed` / `Pulse` / `Progress.Fill`.
---
--- THE WALLS COLLIDE, and that is deliberate: they are the machine's sides, the ramp
--- at the tail is the way on, and both are low enough to jump. Everything above them
--- -- rails, gears, stacks, the monitor -- does not, so nothing catches a player's
--- head on the way on or off a machine they will stand on for hours.
local function buildTreadmill(parent: Instance, origin: CFrame, accent: string)
	local m = Instance.new("Model")
	m.Name = "Treadmill"
	local t = TREADMILL
	local cx, cz = t.cx, t.cz
	local halfL, halfW = t.beltL / 2, t.beltW / 2
	-- Everything below is laid out from the belt's top centre: x across, y up from the
	-- running surface, z along the run (the runner faces -z, the head).
	local B = Plots.PAD.topY + t.beltTop
	local function at(x: number, y: number, z: number): { number }
		return { cx + x, B + y, cz + z }
	end
	local CYL_UP = Kit.R.cylUp

	-- ── The belt ──────────────────────────────────────────────
	-- The running surface, and the ONLY part of this machine a service reads.
	build(m, origin, {
		name = "Belt",
		pos = at(0, -0.3, 0),
		size = { t.beltW, 0.6, t.beltL },
		color = BELT_DARK,
		material = "Rubber",
		attributes = { StationKind = "treadmill", Radius = 5 },
	})
	-- The bed under it, running out past both ends beneath the drums.
	build(m, origin, {
		name = "Deck",
		pos = at(0, -0.35, 0),
		size = { t.beltW + 0.2, 0.5, t.beltL + 2 },
		color = HAZ_STEEL_DARK,
		material = "Plastic",
		studs = true,
	})

	-- Chevrons pointing the way the runner faces (-Z), scrolling the other way under
	-- them. Two rotated arms each, meeting at an apex.
	local ARM_SPREAD, ARM_DEPTH = halfW - 0.5, 1.6
	local armLength = math.sqrt(ARM_SPREAD * ARM_SPREAD + ARM_DEPTH * ARM_DEPTH)
	local armYaw = math.deg(math.atan2(ARM_SPREAD, ARM_DEPTH))
	for i = 1, t.chevrons do
		local apexZ = -halfL + (i - 1) * t.chevronPitch
		for _, side in { -1, 1 } do
			build(m, origin, {
				name = "Slat",
				pos = at(side * ARM_SPREAD / 2, 0.03, apexZ + ARM_DEPTH / 2),
				size = { 0.45, 0.08, armLength },
				color = BELT_TREAD,
				material = "SmoothPlastic",
				rot = Kit.ang(0, side * armYaw, 0),
				canCollide = false,
			})
		end
	end

	-- Exposed steel drums at both ends, half sunk in the bed; they turn with the tread.
	for _, endZ in { -halfL - 0.5, halfL + 0.5 } do
		build(m, origin, {
			name = "Roller",
			pos = at(0, -0.05, endZ),
			size = { t.beltW + 0.2, 1.0, 1.0 },
			color = HAZ_STEEL,
			material = "Metal",
			shape = "Cylinder",
			rot = Kit.R.cylAlongX,
			canCollide = false,
		})
	end

	-- ── The walls ─────────────────────────────────────────────
	-- Alternating yellow and black studded blocks, eight a side, capped in dark steel.
	-- The blocks ARE the hazard stripe: no decal, no texture, just bricks.
	local wallRun = t.beltL + 1.8
	local blocks = 8
	local blockL = wallRun / blocks
	for _, side in { -1, 1 } do
		for i = 0, blocks - 1 do
			build(m, origin, {
				name = "Wall",
				pos = at(side * t.wallX, 0.45, -wallRun / 2 + blockL / 2 + i * blockL),
				size = { 1.0, 1.3, blockL },
				color = if i % 2 == 0 then HAZ_YELLOW else HAZ_BLACK,
				material = "Plastic",
				studs = true,
			})
		end
		build(m, origin, {
			name = "WallCap",
			pos = at(side * t.wallX, 1.2, 0),
			size = { 1.2, 0.2, wallRun },
			color = HAZ_STEEL_DARK,
			material = "Plastic",
			studs = true,
		})

		-- Handrails at eyeline on two black posts, a lower bar between them.
		for _, postZ in { -halfL + 0.1, halfL - 1.9 } do
			build(m, origin, {
				name = "RailPost",
				pos = at(side * t.wallX, 2.25, postZ),
				size = { 0.55, 2.1, 0.55 },
				color = HAZ_BLACK,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
		end
		build(m, origin, {
			name = "Rail",
			pos = at(side * t.wallX, 3.3, -1.1),
			size = { 0.5, 0.5, t.beltL - 0.4 },
			color = HAZ_YELLOW,
			material = "SmoothPlastic",
			canCollide = false,
		})
		build(m, origin, {
			name = "RailBar",
			pos = at(side * t.wallX, 2.3, -0.9),
			size = { 0.3, 0.3, t.beltL - 2 },
			color = HAZ_BLACK,
			material = "SmoothPlastic",
			canCollide = false,
		})
	end

	-- The step-on end: a striped ramp across the tail, sloping down away from the belt.
	local rampBlocks = 6
	local rampW = (t.wallX * 2 - 0.6) / rampBlocks
	for i = 0, rampBlocks - 1 do
		build(m, origin, {
			name = "Ramp",
			class = "WedgePart",
			pos = at(-(t.wallX - 0.3) + rampW / 2 + i * rampW, 0, halfL + 1.6),
			size = { rampW, 0.45, 1.0 },
			color = if i % 2 == 0 then HAZ_YELLOW else HAZ_BLACK,
			material = "Plastic",
			studs = true,
			rot = Kit.ang(0, 180, 0),
		})
	end

	-- ── The head ──────────────────────────────────────────────
	-- The motor block. THE PART setTreadmillTier REPAINTS: bare steel on the free belt,
	-- reactor orange on the last, and the widest solid mass on the machine, so the rung
	-- reads from across the plot.
	local hz = t.headZ
	build(m, origin, {
		name = "Drive",
		pos = at(0, 1.2, hz),
		size = { t.wallX * 2 + 1, 2.8, 2.0 },
		color = TREADMILL_DRIVE[1],
		material = "Plastic",
		studs = true,
		attributes = { TierPaint = true },
	})
	local stripes = 8
	local stripeW = (t.wallX * 2 + 1) / stripes
	for i = 0, stripes - 1 do
		build(m, origin, {
			name = "Stripe",
			pos = at(-(t.wallX + 0.5) + stripeW / 2 + i * stripeW, 2.75, hz),
			size = { stripeW, 0.3, 2.05 },
			color = if i % 2 == 0 then HAZ_YELLOW else HAZ_BLACK,
			material = "Plastic",
			studs = true,
		})
	end

	-- "RAD MILL" on a yellow plate on the runner's side of the block.
	local placard = build(m, origin, {
		name = "Placard",
		pos = at(0, 1.2, hz + 1.05),
		size = { 3.0, 1.2, 0.12 },
		color = HAZ_YELLOW,
		material = "SmoothPlastic",
		canCollide = false,
	})
	local placardGui = Instance.new("SurfaceGui")
	placardGui.Name = "PlacardText"
	placardGui.Face = Enum.NormalId.Back
	placardGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	placardGui.PixelsPerStud = 50
	placardGui.Parent = placard
	local placardText = Instance.new("TextLabel")
	placardText.BackgroundTransparency = 1
	placardText.Size = UDim2.fromScale(0.9, 0.8)
	placardText.Position = UDim2.fromScale(0.05, 0.1)
	placardText.Font = Kit.FONT
	placardText.TextScaled = true
	placardText.TextColor3 = Color3.fromHex(HAZ_BLACK)
	placardText.Text = "RAD MILL"
	placardText.Parent = placardGui

	-- A gear on each flank, turning (StationMotionController). Each is its own Model so
	-- it turns as one about its hub, streamed as a unit. Set 0.4 back from the block's
	-- centre: on it, the teeth swept out to z -43.35 past a pad that ends at -43.
	for _, side in { -1, 1 } do
		local hub = origin * CFrame.new(cx + side * (t.wallX + 0.85), B + 1.4, cz + hz + 0.4)
		local gear = Instance.new("Model")
		gear.Name = "Gear"
		gear.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		build(gear, hub, {
			name = "GearBody",
			pos = { 0, 0, 0 },
			size = { 0.5, 2.8, 2.8 },
			color = HAZ_STEEL,
			material = "Plastic",
			studs = true,
			shape = "Cylinder",
			canCollide = false,
		})
		build(gear, hub, {
			name = "GearHub",
			pos = { side * 0.2, 0, 0 },
			size = { 0.5, 0.9, 0.9 },
			color = HAZ_YELLOW,
			material = "Plastic",
			studs = true,
			shape = "Cylinder",
			canCollide = false,
		})
		for k = 0, 9 do
			build(gear, hub * Kit.ang(k * 36, 0, 0), {
				name = "Tooth",
				pos = { 0, 1.5, 0 },
				size = { 0.5, 0.5, 0.55 },
				color = HAZ_STEEL,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
		end
		gear.WorldPivot = hub
		gear.Parent = m
		Kit.motion(gear, { kind = "spin", axis = "X", rate = side * 1.5 })
	end

	-- Two exhaust stacks and a beacon on the block's back edge.
	for _, side in { -1, 1 } do
		build(m, origin, {
			name = "Stack",
			pos = at(side * 2.6, 3.7, hz - 0.5),
			size = { 2.2, 0.6, 0.6 },
			color = HAZ_BLACK,
			material = "Plastic",
			studs = true,
			shape = "Cylinder",
			rot = CYL_UP,
			canCollide = false,
		})
		build(m, origin, {
			name = "StackCap",
			pos = at(side * 2.6, 4.85, hz - 0.5),
			size = { 0.3, 0.8, 0.8 },
			color = HAZ_RUST,
			material = "Plastic",
			studs = true,
			shape = "Cylinder",
			rot = CYL_UP,
			canCollide = false,
		})
	end
	build(m, origin, {
		name = "BeaconBase",
		pos = at(0, 3.05, hz - 0.5),
		size = { 0.3, 1.2, 1.2 },
		color = HAZ_BLACK,
		material = "Plastic",
		studs = true,
		shape = "Cylinder",
		rot = CYL_UP,
		canCollide = false,
	})
	build(m, origin, {
		name = "Beacon",
		pos = at(0, 3.45, hz - 0.5),
		size = { 1.0, 1.0, 1.0 },
		color = HAZ_BEACON,
		material = "SmoothPlastic",
		shape = "Ball",
		canCollide = false,
	})

	-- ── The console ───────────────────────────────────────────
	-- A chunky CRT on an arm off the front of the block, leaning back at the runner.
	-- The bezel carries the prompt, the attributes and the billboard; the screen is a
	-- lit inset on its runner-side face.
	local monitorZ = hz + 0.7
	build(m, origin, {
		name = "ConsoleStem",
		pos = at(0, 3.4, monitorZ),
		size = { 0.6, 1.4, 0.6 },
		color = HAZ_BLACK,
		material = "Plastic",
		studs = true,
		canCollide = false,
	})
	local console = build(m, origin, {
		name = "Console",
		pos = at(0, 4.6, monitorZ),
		size = { 3.2, 2.1, 1.3 },
		color = HAZ_STEEL_DARK,
		material = "Plastic",
		studs = true,
		rot = CONSOLE_TILT,
		canCollide = false,
		attributes = { UpgradesTreadmill = true },
	})
	local screen = build(m, origin, {
		name = "Screen",
		pos = at(0, 4.6, monitorZ),
		size = { 2.6, 1.6, 0.1 },
		color = SCREEN_DARK,
		material = "SmoothPlastic",
		rot = CONSOLE_TILT * CFrame.new(0, 0, 0.66),
		canCollide = false,
	})

	-- The readout: the owner's speed level, a bar to the next one (both written by
	-- setTreadmillTier alongside the billboard), and a stride pulse that bounces
	-- (StationMotionController). Lit text on dark glass, LightInfluence 0 so the sun
	-- does not wash it out -- a screen, not paint.
	local readout = Instance.new("SurfaceGui")
	readout.Name = "Readout"
	readout.Face = Enum.NormalId.Back
	readout.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	readout.PixelsPerStud = 60
	readout.LightInfluence = 0
	readout.MaxDistance = 60
	readout.Parent = screen

	local speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "Speed"
	speedLabel.BackgroundTransparency = 1
	speedLabel.Position = UDim2.fromScale(0.04, 0.08)
	speedLabel.Size = UDim2.fromScale(0.6, 0.58)
	speedLabel.Font = Kit.FONT
	speedLabel.TextScaled = true
	speedLabel.TextXAlignment = Enum.TextXAlignment.Left
	speedLabel.TextColor3 = Color3.fromHex(SCREEN_INK)
	speedLabel.Text = "LV 1"
	speedLabel.Parent = readout

	local pulse = Instance.new("Frame")
	pulse.Name = "Pulse"
	pulse.BackgroundTransparency = 1
	pulse.Position = UDim2.fromScale(0.68, 0.12)
	pulse.Size = UDim2.fromScale(0.28, 0.52)
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
	track.Size = UDim2.fromScale(0.92, 0.12)
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

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Upgrade"
	prompt.ActionText = "Upgrade Treadmill"
	prompt.ObjectText = "Treadmill"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = console

	-- Tier 1, untrained -- the only state that exists before a player has ever claimed
	-- this plot. ExhibitService.renderTreadmill overwrites both lines the moment real
	-- per-player state does, exactly as it does for the luck button.
	accentBillboard(console, 230, 3.0, "SPEED LV 1", `{Treadmill.tier(1).name} — +{Treadmill.tier(1).rate} Speed/s`, accent)

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
local RAIL_POST_W = 1.2
local RAIL_BAR_T = 0.8
local function buildSideRailings(parent: Instance, origin: CFrame)
	local pad = Plots.PAD
	local folder = Instance.new("Folder")
	folder.Name = "SideRailings"

	-- Stands on the Trim (width/2 - 1 .. width/2), outer face flush with the pad edge,
	-- so the thicker posts still clear the wash pad / cleansing station deck edges.
	local railX = pad.width / 2 - RAIL_POST_W / 2
	local z0, z1 = pad.minZ + 0.5 + RAIL_POST_W / 2, pad.maxZ - 0.5 - RAIL_POST_W / 2
	local span = z1 - z0
	local midZ = (z0 + z1) / 2
	local postCount = math.max(2, math.floor(span / RAIL_POST_SPACING) + 1)
	local postH = RAIL_H + RAIL_BAR_T / 2 + 0.4 -- stands proud of the top rail

	for _, side in { -1, 1 } do
		local x = side * railX

		for _, railY in { RAIL_H, RAIL_H * 0.5 } do
			build(folder, origin, {
				name = "Rail",
				pos = { x, pad.topY + railY, midZ },
				size = { RAIL_BAR_T, RAIL_BAR_T, span + RAIL_POST_W },
				color = C.railGrey,
				material = "Plastic",
				studs = true,
				canCollide = false,
			})
		end

		for i = 0, postCount - 1 do
			local z = z0 + span * (i / (postCount - 1))
			build(folder, origin, {
				name = "RailPost",
				pos = { x, pad.topY + postH / 2, z },
				size = { RAIL_POST_W, postH, RAIL_POST_W },
				color = C.railPost,
				material = "Plastic",
				studs = true,
			})
		end
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
	local folder = Instance.new("Folder")
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
	-- Where it floats over a one-floor base. Plots.setFloors lifts it a floor's height
	-- per floor bought, so it keeps floating over the top deck instead of inside it.
	anchor:SetAttribute("BaseCFrame", anchor.CFrame)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Plate"
	gui.Size = UDim2.fromOffset(128, 156)
	gui.AlwaysOnTop = true
	-- SHORT on purpose, on request — this identifies one specific base to someone
	-- standing near it, not a wayfinding beacon like BaseMarkerController's own
	-- plaza-wide "YOUR BASE" (600). At 600 every plot's plate was readable from
	-- clear across the ring and even from inside a stage. `MaxDistance` is
	-- CAMERA-to-adornee (not player-to-adornee — see the BillboardGui note in
	-- Studio verification history), and the plate sits 38 studs up. 100 (up
	-- slightly from 70, on request) gives more slack for the camera's own
	-- trailing distance without reaching a neighbouring plot (~100+ studs apart
	-- centre to centre) or a stage.
	gui.MaxDistance = 100
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

--- THE GALLERY WALKWAYS — the plaza's cream path carried on into the base, so the deck
--- reads as a floor plan instead of one brown field (on request, the Gallery pass).
---
---        ┌───────────── back landing ─────────────┐
---        │  [S]  ║     [S]      ║  [S]              │
---        │  [S]  ║ aisle [S] aisle║  [S]             │   ║ = aisle between
---        │  [S]  ║     [S]      ║  [S]              │       stand columns
---        │  [S]  ║     [S]      ║  [S]              │
---        │  ════════ cross band ═══════             │
---        │  tub        ║entry║        pad           │
---        └─────────────╨─arch╨──────────────────────┘
---
--- Every rectangle is derived from the stand grid (GRID_COLS / GRID_ROWS / RISER_BASE),
--- so moving a column or a row moves its walkway with it. Lanes and kerbs only ever
--- share EDGES, never area, and all share one top height — coplanar overlap is the
--- z-fighting shimmer, and an edge is not an overlap.
---
--- Thin plates a hair proud of the floor (LANE_LIFT), not cut into it: PadFloor stays
--- one part. CanCollide off — the floor under them is what a player stands on, so a
--- 0.06 lip never catches a foot.
local LANE = { aisle = 6, entry = 8, kerb = 0.5, band = 5, lift = 0.06, thick = 0.12 }
local function buildGalleryLanes(parent: Instance, origin: CFrame)
	local pad = Plots.PAD
	local folder = Instance.new("Folder")
	folder.Name = "GalleryLanes"

	local function plate(name: string, x0: number, x1: number, z0: number, z1: number, color: string)
		build(folder, origin, {
			name = name,
			pos = { (x0 + x1) / 2, pad.topY + LANE.lift - LANE.thick / 2, (z0 + z1) / 2 },
			size = { x1 - x0, LANE.thick, z1 - z0 },
			color = color,
			material = "Plastic",
			canCollide = false,
		})
	end
	local function mirrored(name: string, x0: number, x1: number, z0: number, z1: number, color: string)
		plate(name, x0, x1, z0, z1, color)
		plate(name, -x1, -x0, z0, z1, color)
	end

	local K = LANE.kerb
	local standHalf = RISER_BASE.w / 2
	-- The aisle runs down the middle of the gap between the centre column and each
	-- outer one; `inner`/`outer` are its two edges.
	local aisleX = (GRID_COLS[2] + GRID_COLS[3]) / 2
	local inner, outer = aisleX - LANE.aisle / 2, aisleX + LANE.aisle / 2
	local entryHalf = LANE.entry / 2
	-- The cross band stops ~1.5 short of the front row; the landing starts ~1 past the
	-- back row and runs to the back fence's inner face.
	local bandBack = GRID_ROWS[#GRID_ROWS] - standHalf - 1.55
	local bandFront = bandBack - LANE.band
	local landingFront = GRID_ROWS[1] + standHalf + 1.05
	local landingBack = pad.maxZ - 0.5 - RAIL_POST_W

	local CREAM, KERB = C.baseLane, C.baseLaneKerb

	-- Entry: from the pad's front edge (under the arch) to the cross band.
	plate("Lane", -entryHalf, entryHalf, pad.minZ, bandFront, CREAM)
	mirrored("Kerb", entryHalf, entryHalf + K, pad.minZ, bandFront, KERB)

	-- Cross band, joining the entry to both aisles.
	plate("Lane", -outer, outer, bandFront, bandBack, CREAM)
	mirrored("Kerb", entryHalf + K, outer + K, bandFront - K, bandFront, KERB)
	mirrored("Kerb", outer, outer + K, bandFront, bandBack, KERB)
	plate("Kerb", -(inner - K), inner - K, bandBack, bandBack + K, KERB)

	-- The two aisles between the stand columns.
	mirrored("Lane", inner, outer, bandBack, landingFront, CREAM)
	mirrored("Kerb", inner - K, inner, bandBack, landingFront, KERB)
	mirrored("Kerb", outer, outer + K, bandBack, landingFront, KERB)

	-- Back landing along the fence, joining the aisles' far ends.
	plate("Lane", -outer, outer, landingFront, landingBack, CREAM)
	plate("Kerb", -(inner - K), inner - K, landingFront - K, landingFront, KERB)
	mirrored("Kerb", outer, outer + K, landingFront, landingBack, KERB)

	folder.Parent = parent
end

--- THE ENTRANCE ARCH — two studded posts either side of the entry lane, a lintel
--- across them, and a sign naming the owner, so whose base this is reads at eye level
--- from the plaza and not only from the avatar plate floating 38 studs up.
---
--- The sign's label is named `OwnerName`; ExhibitService.renderName writes
--- "<DisplayName>'s Base" into it on claim (the player's own casing, like the plate)
--- and puts "UNCLAIMED" back on release. The post caps and the stripe under the
--- lintel carry `Accent`.
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
	local label = Kit.surfaceText(sign, Enum.NormalId.Front, "UNCLAIMED", C.labelText)
	label.Name = "OwnerName"

	m.Parent = parent
end

-- ── Upper floors (Config/Floors) ─────────────────────────────────────────────

--- THE UPPER FLOORS — up to two more storeys stacked over the gallery, on request.
---
---   side view, looking along +X, all three floors bought:
---
---              ┌───────────── deck 3 ──────────────┐  T + 32
---              │  [stand]  [stand]  [stand]  [stand]
---              ├───────────── deck 2 ──────────────┤  T + 16
---              │  [stand]  [stand]  [stand]  [stand]
---   ═══════════╧═══════════════ pad ═══════════════╧  T
---   entrance strip       (the ground gallery)
---   (open to the sky)
---
--- A DECK COVERS THE GALLERY, NOT THE WHOLE PAD. It runs from FLOOR.front (just in
--- front of the ground grid's front row) to the back edge, full width. The entrance
--- strip in front of it — the tub, the bottle, the treadmill, the locker — stays open
--- to the sky: the wash camera and the crust reach both assume nothing hangs over the
--- tub (memory: crust-fills-the-wash-bay).
---
--- THE FLIGHTS ALTERNATE SIDES. The flight up from the ground climbs the -X side
--- corridor (between the outer stand column and the fence), front to back; the flight
--- up from floor 2 climbs the +X side the same way. Each deck has a stairwell hole
--- over the flight that arrives at it, fenced on its inner edge (the guard rail) and
--- open at the back, where you step off. You walk off the top of one flight, across
--- the deck, and the next flight's foot is on the far side at the front.
---
--- EVERY FLOOR IS BUILT, AND HIDDEN AT RUNTIME. buildPlot builds Floor2..Floor<MAX>
--- and a FloorSign per floor on every plot, so Studio shows the whole three-storey
--- building. Plots.setFloors (called by ExhibitService) moves the ones a plot's owner
--- has not bought out to ServerStorage and back; nothing here knows who owns what.
---
--- DECKS CAST NO SHADOW. A 66 x 55 deck over the gallery would put every stand under
--- it in shade the moment a floor is bought, and a gallery is for looking at. The
--- pillars and stairs still cast one, so the building does not read as floating.
local FLOOR = {
	front = -11, -- the decks' front edge (plot-local z); the ground grid's front plinths end at -10.45
	thick = 1.2,
	fascia = 0.6, -- the accent band round a deck's edge
	stairX = 28.6, -- |x| of a flight's centre line: the side corridor past the outer stand column
	stairW = 4.8,
	stairZ = -9.6, -- where a flight's first step starts, just behind the deck's front rail
	tread = 1.75,
	rise = 1, -- Floors.HEIGHT steps of this, so a flight lands exactly on the next deck
	openIn = 25.8, -- |x| of a stairwell's inner edge
	openOut = 31.4, -- |x| of its outer edge; the ledge past it carries the side rail
	-- Pillars stand on the fence line, at z's picked between BOTH rows of fence posts
	-- (the ground's side railing and every deck's own), so a pillar never swallows a
	-- post or shares a face with one.
	pillarX = 32,
	pillarW = 1.4,
	pillarZ = { -5.3, 15, 39 },
	handrails = { 2.0, 3.5 }, -- heights of a flight's two sloped rails over the step line
	handPostH = 3.2,
}
local FLIGHT_STEPS = math.round(Floors.HEIGHT / FLOOR.rise)
local FLIGHT_TOP_Z = FLOOR.stairZ + FLIGHT_STEPS * FLOOR.tread

--- Which side (-1 = -X, +1 = +X) the flight climbing UP FROM `floor` runs up.
local function flightSide(floor: number): number
	return if floor % 2 == 1 then -1 else 1
end

--- One straight run of fence (posts + two rails) along x or along z, at deck height
--- `y`. Unlike the ground's railings every piece COLLIDES: past the ground floor the
--- other side of a rail is a drop. `skipStart`/`skipEnd` leave off an end post that
--- another run already puts in the same spot (two identical posts z-fight).
local function railRun(folder: Instance, origin: CFrame, y: number, x0: number, z0: number, x1: number, z1: number, skipStart: boolean?, skipEnd: boolean?)
	local alongX = math.abs(x1 - x0) >= math.abs(z1 - z0)
	local span = math.max(math.abs(x1 - x0), math.abs(z1 - z0))
	local posts = math.max(2, math.ceil(span / RAIL_POST_SPACING) + 1)
	local postH = RAIL_H + RAIL_BAR_T / 2 + 0.4
	for _, railY in { RAIL_H, RAIL_H * 0.5 } do
		build(folder, origin, {
			name = "Rail",
			pos = { (x0 + x1) / 2, y + railY, (z0 + z1) / 2 },
			size = if alongX then { span + RAIL_POST_W, RAIL_BAR_T, RAIL_BAR_T } else { RAIL_BAR_T, RAIL_BAR_T, span + RAIL_POST_W },
			color = C.railGrey,
			material = "Plastic",
			studs = true,
		})
	end
	for i = 0, posts - 1 do
		if (i == 0 and skipStart) or (i == posts - 1 and skipEnd) then
			continue
		end
		local t = i / (posts - 1)
		build(folder, origin, {
			name = "RailPost",
			pos = { x0 + (x1 - x0) * t, y + postH / 2, z0 + (z1 - z0) * t },
			size = { RAIL_POST_W, postH, RAIL_POST_W },
			color = C.railPost,
			material = "Plastic",
			studs = true,
		})
	end
end

--- The flight of stairs from `fromFloor` up to the floor above it: solid studded
--- blocks, each one from the floor below to its own tread, in alternating greys so
--- the steps read from across the plaza, and a pair of sloped handrails down each
--- side. The rails are rotated straight parts, not a staircase of little bars
--- (memory: straight-edges-over-pixel-stairs).
local function buildFlight(parent: Instance, origin: CFrame, fromFloor: number)
	local m = Instance.new("Model")
	m.Name = "Stairs"
	local baseY = floorTopY(fromFloor)
	local x = flightSide(fromFloor) * FLOOR.stairX

	for i = 1, FLIGHT_STEPS do
		local h = i * FLOOR.rise
		build(m, origin, {
			name = "Step",
			pos = { x, baseY + h / 2, FLOOR.stairZ + (i - 0.5) * FLOOR.tread },
			size = { FLOOR.stairW, h, FLOOR.tread },
			color = if i % 2 == 1 then C.standGrey else C.standGreyDark,
			material = "Plastic",
			studs = true,
		})
	end

	-- The step line runs from the flight's foot (z = stairZ, the floor below) to its
	-- head (FLIGHT_TOP_Z, the deck above); a handrail is that line lifted `lift`, so
	-- over the middle of step i it sits at i - 0.5 + lift.
	local run = FLIGHT_STEPS * FLOOR.tread
	local climb = FLIGHT_STEPS * FLOOR.rise
	local length = math.sqrt(run * run + climb * climb)
	local pitch = CFrame.Angles(-math.atan2(climb, run), 0, 0)
	for _, edge in { -1, 1 } do
		local hx = x + edge * (FLOOR.stairW / 2 - RAIL_BAR_T / 2)
		for _, lift in FLOOR.handrails do
			build(m, origin, {
				name = "Handrail",
				pos = { hx, baseY + climb / 2 + lift, FLOOR.stairZ + run / 2 },
				size = { RAIL_BAR_T, RAIL_BAR_T, length },
				color = C.railGrey,
				material = "Plastic",
				studs = true,
				rot = pitch,
			})
		end
		-- Posts at the foot, the middle and the head, each from its tread up into the
		-- top rail (which is 3.0 over the tread there — see above).
		for _, i in { 1, math.ceil(FLIGHT_STEPS / 2), FLIGHT_STEPS } do
			build(m, origin, {
				name = "HandrailPost",
				pos = { hx, baseY + i * FLOOR.rise + FLOOR.handPostH / 2, FLOOR.stairZ + (i - 0.5) * FLOOR.tread },
				size = { RAIL_BAR_T, FLOOR.handPostH, RAIL_BAR_T },
				color = C.railPost,
				material = "Plastic",
				studs = true,
			})
		end
	end

	m.Parent = parent
end

--- One whole storey: its deck (with a stairwell hole over the flight arriving at it),
--- the accent band round the deck's edge, the pillars holding it up, that flight of
--- stairs, the railings round the deck and the stairwell, and its gallery of stands.
local function buildFloor(parent: Instance, origin: CFrame, index: number, floor: number, accent: string)
	local pad = Plots.PAD
	local m = Instance.new("Model")
	m.Name = `Floor{floor}`
	m:SetAttribute("FloorIndex", floor)

	local top = floorTopY(floor)
	local below = floorTopY(floor - 1)
	local side = flightSide(floor - 1) -- the side this floor's stairwell is on
	local front, back = FLOOR.front, pad.maxZ

	-- ── The deck: three plates round the stairwell ─────────────
	-- The plates only ever share edges; one studded board, like the pad's own floor.
	local function deck(xa: number, xb: number, z0: number, z1: number)
		local x0, x1 = math.min(xa, xb), math.max(xa, xb)
		local plate = build(m, origin, {
			name = "Deck",
			pos = { (x0 + x1) / 2, top - FLOOR.thick / 2, (z0 + z1) / 2 },
			size = { x1 - x0, FLOOR.thick, z1 - z0 },
			color = C.baseFloor,
			material = "Plastic",
		})
		plate.CastShadow = false
	end
	deck(-side * HALF_W, side * FLOOR.openIn, front, back) -- everything inside the stairwell's inner edge
	deck(side * FLOOR.openIn, side * HALF_W, FLIGHT_TOP_Z, back) -- behind it, where the flight lands
	deck(side * FLOOR.openOut, side * HALF_W, front, FLIGHT_TOP_Z) -- the ledge outside it, under the side rail

	-- The accent band round the deck's outer edge, so a bought floor wears the plot's
	-- colour from across the plaza the way the ground's Trim does.
	local bandY = top - 0.1 - FLOOR.fascia / 2
	for _, band in {
		{ x = 0, z = front - 0.15, sx = pad.width + 0.6, sz = 0.3 },
		{ x = 0, z = back + 0.15, sx = pad.width + 0.6, sz = 0.3 },
		{ x = -HALF_W - 0.15, z = (front + back) / 2, sx = 0.3, sz = back - front },
		{ x = HALF_W + 0.15, z = (front + back) / 2, sx = 0.3, sz = back - front },
	} do
		build(m, origin, {
			name = "Fascia",
			pos = { band.x, bandY, band.z },
			size = { band.sx, FLOOR.fascia, band.sz },
			color = accent,
			material = "SmoothPlastic",
			canCollide = false,
			attributes = { Accent = true },
		})
	end

	-- ── Pillars, from the floor below to this deck's underside ─
	local pillarH = top - FLOOR.thick - below
	for _, sx in { -1, 1 } do
		for _, pz in FLOOR.pillarZ do
			build(m, origin, {
				name = "Pillar",
				pos = { sx * FLOOR.pillarX, below + pillarH / 2, pz },
				size = { FLOOR.pillarW, pillarH, FLOOR.pillarW },
				color = C.standGreyDark,
				material = "Plastic",
				studs = true,
			})
		end
	end

	-- The flight that arrives here. It belongs to THIS floor, not the one it stands
	-- on, so it appears when this floor is bought.
	buildFlight(m, origin, floor - 1)

	-- ── Railings: the deck's four edges and the stairwell ──────
	local rails = Instance.new("Folder")
	rails.Name = "Railings"
	local rx = HALF_W - RAIL_POST_W / 2
	local rzFront, rzBack = front + RAIL_POST_W / 2, back - RAIL_POST_W / 2
	railRun(rails, origin, top, -rx, rzFront, rx, rzFront)
	railRun(rails, origin, top, -rx, rzFront, -rx, rzBack, true)
	railRun(rails, origin, top, rx, rzFront, rx, rzBack, true)
	railRun(rails, origin, top, -rx, rzBack, rx, rzBack, true, true)
	-- The stairwell's inner edge, from the front rail back to where the flight lands.
	-- Its front post would sit exactly on one of the front run's.
	local gx = side * (FLOOR.openIn - RAIL_POST_W / 2)
	railRun(rails, origin, top, gx, rzFront, gx, FLIGHT_TOP_Z, true)
	rails.Parent = m
	capFencePosts(rails, accent)

	-- ── The gallery ─────────────────────────────────────────────
	local first = Floors.firstSlot(floor)
	for slot = first, first + Floors.UPPER_SLOTS - 1 do
		buildDisplayStand(m, origin, index, slot, accent)
	end

	m.Parent = parent
end

--- "$75,000" rather than "$75000".
local function withCommas(n: number): string
	local digits = tostring(math.floor(n))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return (string.gsub(grouped, "^,", ""))
end

--- The sign that sells floor `floor`: a post and a board standing where that floor's
--- flight of stairs will go, on the floor below it. Holding E on the board buys the
--- floor (ExhibitService wires it by Kit.FLOOR_TAG); the sign then disappears and the
--- stairs are there in its place. Plots.setFloors shows exactly one of these on a
--- claimed plot — the next floor up — and none on a full or unclaimed one.
---
--- ANSWERS IN THE WORLD. A refused purchase is written into this sign's billboard
--- subtitle for a moment (ExhibitService), not sent as a StationResult toast, which
--- nobody sees away from a panel (memory: station-result-toast-needs-panel).
--- `SignText` on the board is the subtitle to put back afterwards.
local function buildFloorSign(parent: Instance, origin: CFrame, index: number, floor: number, accent: string)
	local m = Instance.new("Model")
	m.Name = `FloorSign{floor}`
	local base = floorTopY(floor - 1)
	local x = flightSide(floor - 1) * FLOOR.stairX
	local z = FLOOR.stairZ + 3
	local price = withCommas(Floors.PRICES[floor] or 0)
	local subtitle = `+{Floors.UPPER_SLOTS} stands for ${price}`

	build(m, origin, { name = "SignFoot", pos = { x, base + 0.2, z }, size = { 2, 0.4, 2 }, color = C.standGrey, material = "Plastic", studs = true })
	build(m, origin, { name = "SignPost", pos = { x, base + 2.3, z }, size = { 0.8, 3.8, 0.8 }, color = C.standGreyDark, material = "Plastic", studs = true })
	build(m, origin, {
		name = "SignStripe",
		pos = { x, base + 3.85, z },
		size = { 5.2, 0.3, 0.7 },
		color = accent,
		material = "SmoothPlastic",
		canCollide = false,
		attributes = { Accent = true },
	})
	local board = build(m, origin, {
		name = "SignBoard",
		pos = { x, base + 5.2, z },
		size = { 5, 2.4, 0.5 },
		color = ARCH_SIGN_FILL,
		material = "SmoothPlastic",
		attributes = { BuysFloor = floor, PlotIndex = index, SignText = subtitle },
	})
	-- Front is -Z: the face you see walking in from the entrance.
	Kit.surfaceText(board, Enum.NormalId.Front, `FLOOR {floor}`, C.labelText)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyFloor"
	prompt.ActionText = `Build Floor {floor}`
	prompt.ObjectText = `${price}`
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = board

	accentBillboard(board, 230, 2.8, `BUILD FLOOR {floor}`, subtitle, accent)

	m.Parent = parent
end

--- Where ExhibitService parks the floors a plot's owner has not bought. Out of
--- Workspace entirely (not just transparent), so a hidden floor costs the clients
--- nothing, its stands' prompts cannot be reached and nobody walks into invisible
--- pillars. One folder per plot, created on first use — only ever at runtime.
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

--- Show the floors a plot's owner has built and hide the rest: Floor2..Floor`owned`
--- in the plot, everything above that parked in ServerStorage, and — only on a
--- `claimed` plot — the one FloorSign that sells the next floor up. Also lifts the
--- avatar plate over the top deck, and publishes the count as the plot's `Floors`
--- attribute (the client's "YOUR BASE" beacon rides at the same height).
---
--- Idempotent, and quiet on a world built before floors existed (nothing to move).
--- The stands on a floor coming back keep whatever they showed when they were parked:
--- ExhibitService re-renders them straight after calling this.
function Plots.setFloors(plot: Instance?, owned: number?, claimed: boolean)
	if plot == nil then
		return
	end
	local model: Instance = plot
	local count = Floors.clamp(owned)
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
	for floor = 2, Floors.MAX do
		place(`Floor{floor}`, floor <= count)
		place(`FloorSign{floor}`, claimed and floor == count + 1)
	end

	local plate = model:FindFirstChild("NamePlate")
	local rest = plate and plate:GetAttribute("BaseCFrame")
	if plate and plate:IsA("BasePart") and typeof(rest) == "CFrame" then
		plate.CFrame = rest + Vector3.new(0, (count - 1) * Floors.HEIGHT, 0)
	end
	model:SetAttribute("Floors", count)
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
	-- The cream walkways laid over it (the Gallery pass).
	buildGalleryLanes(m, origin)

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

	-- The ground floor's stands are usable from the start. See buildDisplayStand for
	-- the plinth's form.
	for slot = 1, Floors.GROUND_SLOTS do
		buildDisplayStand(m, origin, index, slot, accent)
	end

	buildCleansingStation(m, origin, accent)
	buildQuarantineLocker(m, origin, accent)
	buildFluidBottle(m, origin)
	buildTreadmill(m, origin, accent)

	-- Every floor above, and the sign that sells each one. All built; the ones this
	-- plot's owner has not bought are hidden at runtime (Plots.setFloors).
	for floor = 2, Floors.MAX do
		buildFloor(m, origin, index, floor, accent)
		buildFloorSign(m, origin, index, floor, accent)
	end

	m.Parent = parent
	return m
end

--- Lay the apron. Lives in this file rather than in Hub.luau because the disc is
--- derived from the pad ring, and Hub cannot see the ring: Plots requires Hub, so a
--- require back the other way would be a cycle. Hub owns the PATTERN and exports it;
--- this file owns the SHAPE and asks for it to be tiled.
---
--- THE VISIBLE CAP is one `Hub.tileRect` call over a square bounding
--- APRON_CAP_RADIUS (RING_OUTER plus a wall-depth, so the tiles run UNDER the
--- Scenery perimeter wall rather than stopping at its inner face — see that
--- constant's own comment above `apronSkip`), clipped at `maxX = PLAZA.maxX`
--- (Stage 1's own west edge, touching not
--- crossing it — the same shared-edge convention the plaza's own east side
--- already uses) and punched by `apronSkip` (plaza + every pad's own oriented
--- footprint) — see that function's own comment above.
---
--- `ground = true` on that call is the other half of Hub's base floor: buildPlaza
--- paints the plaza slab, this paints the rest of the disc — same grid, same
--- `Hub.groundPairAt` resolver — so the disc comes out grass (the Stage-1-matched green)
--- flowing around every plot footprint, picks up the plaza octagon's rim where it spills
--- past the plaza rectangle and the gate paths out to each pad (all one raised floor), and
--- every tile it doubles over the plaza's own
--- edge (PLAZA_SKIP_MARGIN) takes the plaza's colour instead of z-fighting a different
--- one over it. See `Hub.groundPairAt` on why that must stay one shared resolver.
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
--- APRON_CAP_RADIUS circle — a single bounding rectangle would round the disc's
--- curve out to a square and leave the tiled cap's corners floating over open air.
--- (Same radius as the cap, so the backing also reaches under the perimeter wall
--- and nothing shows through the cap's edge tiles from a low angle at the wall
--- base.) Purely cosmetic backing (World.verify() never inspects apron shape): if
--- it ever needs to look tidier from underneath, BANDS is the one knob to turn.
local function buildApron(row: Model)
	local apron = Instance.new("Folder")
	apron.Name = "Apron"

	-- APRON_CAP_RADIUS, not RING_OUTER: the cap and its backing bands both run a
	-- wall-depth past the ring so they pass under the Scenery perimeter wall instead
	-- of stopping at its inner face — see that constant's own comment above.
	local discBounds: Hub.Rect = {
		minX = Plots.RING_CENTER.x - APRON_CAP_RADIUS,
		maxX = PLAZA.maxX,
		minZ = Plots.RING_CENTER.z - APRON_CAP_RADIUS,
		maxZ = Plots.RING_CENTER.z + APRON_CAP_RADIUS,
	}
	Hub.tileRect(apron, discBounds, { skip = apronSkip, ground = true })

	local BANDS = 12
	local bandHeight = (2 * APRON_CAP_RADIUS) / BANDS
	for i = 0, BANDS - 1 do
		local zLo = Plots.RING_CENTER.z - APRON_CAP_RADIUS + i * bandHeight
		local zHi = zLo + bandHeight
		local reach = math.max(math.abs(zLo - Plots.RING_CENTER.z), math.abs(zHi - Plots.RING_CENTER.z))
		if reach < APRON_CAP_RADIUS then
			local safeHalfX = math.sqrt(APRON_CAP_RADIUS ^ 2 - reach ^ 2)
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
		`[build] Plots rebuilt — {Plots.COUNT} plots, {Floors.MAX} floors and `
			.. `{Plots.VISIBLE_SLOTS} stands each ({Floors.GROUND_SLOTS} free on the ground), `
			.. `{Plots.LOCKER_SLOTS}-bay quarantine locker each, `
			.. `{#row.Apron:GetChildren()} apron parts`
	)
	return row
end

return Plots
