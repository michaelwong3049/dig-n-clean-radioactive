--!strict
--[[
	Plots.luau — the Row. Five exhibition plots, one per player.

	    require(game.ServerScriptService.Server.build.Plots).rebuild()

	AN ITEM YOU SELL IS GONE. AN ITEM YOU DISPLAY KEEPS PAYING (PLAN §8).
	These are not sell pads — the Trader at the camp already does that. A plot is
	where a cleaned item goes to earn forever, in public, with your name under it.
	PLAN §8.1 is right that this is what makes a shared server worth having: without
	it the other four people are scenery.

	FIVE PLOTS, FIVE PLAYERS. MaxPlayers is set to 5 on the place so plots and players
	are 1:1 and there is no "sorry, full" case to design around. That is a place
	setting, not repo state — Rojo does not capture it — so it is written down in
	ARCHITECTURE.md as one of the things a fresh clone cannot reconstruct.

	FIVE BASES IN ONE ROW ALONG THE BACK (WEST) WALL, ALL FACING STAGE 1 (2026-10-09, on
	request, from the user's sketch: "5 stages along each other facing towards the stage"):

	     ┌────────────────────────────────────────────┐
	     │ [P1]                                       │
	     │          (booth)                           │
	     │ [P2]                                       │
	     │          (booth)                           │
	     │ [P3]                [chest + crates]       ===> STAGE 1   (east, open)
	     │          (Trader)                          │
	     │ [P4]                                       │
	     │          (booth)                           │
	     │ [P5]                                       │
	     └────────────────────────────────────────────┘

	Numbered left to right as you face Stage 1 (-Z to +Z). The shops stand in one row in
	front of the bases, a booth opposite each gap (build/Shops BOOTHS), and the group chest
	with its two crate pads sits in front of the middle base, by Stage 1's mouth
	(build/PrizeSquare). The perimeter wall (Scenery.buildBaseWalls) is the plain rectangle
	in Plots.CAMP.

	IT WAS THREE TO A SIDE BEFORE THIS (2026-10-04 to -09): three bases on the north edge
	and three on the south, facing a shop square between them, the south row's front
	strips mirrored (`stripFlip`, still in buildPlot for any pad facing north).

	IT WAS TWO TO A SIDE BEFORE THIS (2026-10-03 to -04): two pads each on the north,
	south and west edges, the wall a stepped outline (a back block for the west pair, two
	wider wings).

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
	carries the active washing equipment and an 18-stud back extension gives the
	grid room to spread:

	    ┌─────────────────────────────────────┐
	    │ ══════════ back landing ══════════   │
	    │   [stand] ║ [stand] ║ [stand]        │
	    │   [stand] ║ [stand] ║ [stand]        │   ║ = black aisles
	    │   [stand] ║ [stand] ║ [stand]        │
	    │   [stand] ║ [stand] ║ [stand]        │
	    │   ═══════ cross band ═══════         │
	    │  [locker]       ║                    │
	    └──────── hazard line, deck edge ──────┘
	       WASHER [bottle]                        ← deck-coloured strip, ground level, open
	                  entry (spawn)

	THE GALLERY PASS (on request, picked from three live previews) dressed that grid
	up: the stands stand on waist-high plinths with an accent band, an empty one shows
	accent corner brackets and a full one a line in its item's rarity colour
	(Plots.setStandState); walkways (buildGalleryLanes) run in from the hazard line.
	They were cream; black now (2026-10-04, on request). The front strip in front of the
	deck wears the deck's own colour (buildFrontPath). The entrance arch and the front
	fence are gone (on request): the raised deck stops at the hazard line. Every fence post wears an accent cap.
	A claimed plot whose owner never picked a colour wears Plots.DEFAULT_ACCENTS.

	THE STANDS CAME BACK (2026-10-04, on request). For a day the base was one open floor
	nukes were placed anywhere on, with an Upgrade Base sign (#873-#876); that was
	taken out again and the 12-stand grid and its bought storeys restored, inside the
	square layout and grey camp floor that came after it.

	The Quarantine Locker (PLAN §10.2) — a rack of eight specimen tubes where you park
	finds instead of carrying them — backs onto the +X fence beside the cleansing
	station. Built here, filled by ExhibitService.renderLocker, opened by its own E
	prompt into the locker panel (client/LockerPanel); see buildQuarantineLocker.

	12 stands: a full 3-column (`GRID_COLS`) by 4-row (`GRID_ROWS`) grid,
	numbered left to right then back row to front row. Slot 1 is back-left,
	slot 3 back-right, slot 12 front-right (`GRID_SLOTS`, `slotOffset`). The cleansing station, its hose rig and the fluid bottle occupy the +X side of
	the entrance extension, the Quarantine Locker the -X side (the treadmill stood
	beside it until 2026-10-09), with a deliberate safe gap between their station radii.

	FLOORS: THE GROUND 12 ARE FREE, AND UP TO TWO MORE STOREYS ARE BOUGHT.
	A base can be built up to Config/Floors.MAX = 3 floors. The ground floor's 12
	stands are usable from the moment a plot is claimed; each floor bought on top
	(Floors.PRICES, at the sign at the foot of the next flight of stairs) adds the
	same 12-stand gallery, Floors.UPPER_SLOTS more. Slot numbers run on across floors:
	1..12 are the ground grid above, 13..24 floor 2, 25..36 floor 3
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
	    NamePlate   invisible anchor; BaseMarkerController hangs the owner's floating
	                plate off it, reading the model's OwnerUserId / OwnerName /
	                OwnerRate attributes (ExhibitService).
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
	    Floor<f>    Model, one per floor above the ground (f = 2..Floors.MAX): deck,
	                pillars, the flight of stairs up to it, its railings and its
	                Stand/StandTop/Display parts for slots Floors.firstSlot(f)... Moved
	                in and out of ServerStorage by Plots.setFloors, never by name
	                elsewhere.
	    FloorSign<f>  Model; its SignBoard carries BuysFloor = f, PlotIndex = n and
	                a ProximityPrompt — builds floor f. ExhibitService wires it by
	                Kit.FLOOR_TAG and writes its Sign's Subtitle. Shown only on a
	                claimed plot whose owner has exactly f - 1 floors.
	    QuarantineLocker   the specimen-tube rack. LockerSlot1..Plots.LOCKER_SLOTS are
	                hidden item anchors, LockerGlow<i> the pool ExhibitService.renderLocker
	                tints per stored find (from data.locker). LockerStation carries
	                StationKind = "locker", StationId = "<n>", PlotIndex = n,
	                Radius = 6 and the "OpenLocker" prompt that opens the locker panel.

	The stand's StationId is "plot:slot" so the server can resolve exactly which
	pedestal a player is standing at without a spatial search of its own.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Floors = require(Shared.Config.Floors)
local Liquids = require(Shared.Config.Liquids)
local Mastery = require(Shared.Mastery)
local Tuning = require(Shared.Config.Tuning)
local ToolModels = require(Shared.ToolModels)
local ToolFX = require(Shared.ToolFX)

local Kit = require(script.Parent.Kit)
local Hub = require(script.Parent.Hub)

local Plots = {}
local BUILDER_SOURCE = "src/server/build/Plots.luau"
local BUILDER_VERSION = 125 -- side bases 22 nearer the east wall (2026-10-10)

local C = Kit.C
local build, light = Kit.build, Kit.light

Plots.COUNT = 5
-- Every stand built per base, across all of its floors (Config/Floors): the ground
-- floor's 12 plus UPPER_SLOTS on each floor above. Floors a plot's owner has not
-- bought are built too, and hidden at runtime (Plots.setFloors).
Plots.VISIBLE_SLOTS = Floors.MAX_SLOTS

--- The accent a CLAIMED plot wears until its owner picks one in Settings, by plot
--- index. Most players never open Settings, and the gallery (arch caps, plinth bands,
--- fence caps, slot brackets) is mostly accent — in `C.plotNeutral` it reads as more
--- grey fence. One hue per plot, so the five bases in a server never match. Never saved
--- to the profile (ExhibitService.renderAccent picks it at paint time), so a player who
--- has never chosen simply wears whichever plot they land on. Kept clear of the
--- quarantine red and the stages' hazard greens.
Plots.DEFAULT_ACCENTS = {
	"FF9F43", -- orange
	"2EC4B6", -- teal
	"9B5DE5", -- purple
	"FF5D8F", -- pink
	"3FA7F5", -- blue
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
-- 2026-10-04, on request ("push the length of the base more to the back so there's more
-- space with treadmill and cleaning station"): -43 -> -51. The fronts stay on the same
-- world line (the origin sits PAD_FRONT_REACH behind them), so the deck, the stands and
-- the back fence all moved 8 back, into BACK_SPARE; the front strip is 8 deeper, and its
-- machines moved 4 forward (STRIP_FORWARD) to split the room before and behind them.
local PAD_MIN_Z = -51
local PAD_MAX_Z = 56
--- THE DECK STOPS AT THE HAZARD LINE (2026-10-03, on request). Everything in front of
--- it — the washer, the bottle, the treadmill, the spawn — stands on the plaza's grey
--- path at ground level instead of on the raised brown deck, and the fence starts at
--- the line. `minZ` is still the plot's whole footprint (the pads are placed by it, and
--- World.verify and the foliage scatter keep clear of it); `deckMinZ` is where the
--- raised deck itself begins, just in front of the hazard line (HAZARD_Z, -20) so it
--- line still lies on the deck, and behind the cleansing station's back (z -21.3).
local DECK_MIN_Z = -21
--- 66 -> 57 wide, fence to fence (2026-10-04, on request: "shrink each player base width by
--- 9 studs"). The centres stayed put, so the gaps between bases grew by 9 and the camp
--- walls (Plots.CAMP, read off CAMP_HALF_W) did not move.
Plots.PAD = {
	width = 57,
	depth = PAD_MAX_Z - PAD_MIN_Z,
	minZ = PAD_MIN_Z,
	maxZ = PAD_MAX_Z,
	deckMinZ = DECK_MIN_Z,
	topY = Hub.PLAZA.topY + 1.5,
	thickness = 3,
}
--- How far the front strip's machines sit below the deck: the deck's top down to the
--- grey path's (Hub.PLAZA_LIFT above the plaza).
local STRIP_DROP = Plots.PAD.topY - (Hub.PLAZA.topY + Hub.PLAZA_LIFT)

--- NO BASE BORDER (2026-10-10, on request: "remove the grey border still on the base").
--- A 2-stud dark grey band lay on the ground round each pad from 2026-10-04; the camp
--- floor is lawn again and the band read as leftover grey.

--- THE FRONT PATH: one flat plate over the front strip, the whole width of the pad from
--- its front edge to the deck, where the washer, the bottle and the treadmill stand. In
--- the deck's own colour and finish (PadFloor), on request (2026-10-04: "same color as
--- the one the stands are on"); it was the walkways' black for a moment before that. The apron still paves the strip grey underneath (Hub.setPadFronts);
--- this lies a hair above it and a hair under the border, so neither z-fights.
--- A VERY FAINT CHECKER on top (2026-10-08, on request): Kit's CHECKER detail texture in
--- a darker grey at FRONT_CHECKER_ALPHA, 4-stud cells (the plaza's tile), centred on the
--- pad's middle line. A Texture, not tiles, so the strip stays one part and keeps its studs.
local FRONT_PATH_TOP = Hub.PLAZA.topY + Hub.PLAZA_LIFT + 0.03
local FRONT_CHECKER_CELL = 4
local FRONT_CHECKER_COLOR = "6E7378"
local FRONT_CHECKER_ALPHA = 0.8
local function buildFrontPath(parent: Instance, origin: CFrame)
	local part = build(parent, origin, {
		name = "FrontPath",
		pos = { 0, FRONT_PATH_TOP - Hub.TILE_CAP / 2, (PAD_MIN_Z + DECK_MIN_Z) / 2 },
		size = { Plots.PAD.width, Hub.TILE_CAP, DECK_MIN_Z - PAD_MIN_Z },
		color = C.baseFloor,
		material = "Plastic",
		canCollide = false,
	})
	part.CanQuery = false
	part.CanTouch = false
	local tile = 2 * FRONT_CHECKER_CELL
	local checker = Kit.detailTexture(
		part,
		Enum.NormalId.Top,
		Kit.DETAIL_TEXTURE.CHECKER,
		FRONT_CHECKER_COLOR,
		tile,
		tile,
		(tile - (Plots.PAD.width / 2) % tile) % tile,
		0
	)
	checker.Name = "FaintChecker"
	checker.Transparency = FRONT_CHECKER_ALPHA
	return part
end

--- THE ROW. Three pads in one line along the west wall, each facing east at Stage 1
--- (five from 2026-10-09; the end two became the U's side bases on 2026-10-10). Hand-placed, like Hub's SHOP_ZONE and GATE_RECTS (which are
--- cut to these numbers -- move those with these).
---
--- `facing` is a yaw in degrees. A pad is built with its back fence at +Z and its
--- spawn/front at -Z, so 0 faces south (a north pad), 180 faces north (a south pad) and
--- -90 faces east (a west pad).
---
--- A pad's FRONT edge is its local Z = PAD_MIN_Z (-51), so the origin sits 51 studs
--- behind the front: fronts on x = ROW_FRONT_X (a tile line of Hub's grid), centres 76
--- apart along Z (a 19-stud gap between neighbours, wide enough to walk through to the
--- back wall). World.verify() checks that no pad overlaps the plaza, a stage, or another
--- pad.
local PAD_FRONT_REACH = -PAD_MIN_Z -- origin to front edge
-- -1 -> 15 (2026-10-10, on request: "move the bases closer" to Stage 1, asked 18; 16 is
-- the nearest move that keeps the fronts on Hub's grid with the same checker parity).
local ROW_FRONT_X = 15
-- 2026-10-10, the U (from the user's sketch): the row is the middle three only; the two
-- end bases became SIDE pads (below).
local ROW_Z = { -76, 0, 76 }

local PLAZA = Hub.PLAZA
local HALF_W = Plots.PAD.width / 2
--- The half-width the camp walls were laid round (the 66-wide pads). Kept when the pads
--- narrowed, so the walls, the apron and the foliage did not move.
local CAMP_HALF_W = 33
--- How far each side's front-strip machines (cleansing station, bottle, locker, treadmill)
--- moved in with the side fences when the pad narrowed: they are written for a 66-wide
--- pad and built through frames shifted by this toward the middle.
local STRIP_INSET = CAMP_HALF_W - HALF_W
--- How far toward the front the strip's machines and spawn are built (see PAD_MIN_Z).
local STRIP_FORWARD = 4
local HALF_D = Plots.PAD.depth / 2
local PAD_CENTER_Z = (Plots.PAD.minZ + Plots.PAD.maxZ) / 2
local DECK_CENTER_Z = (DECK_MIN_Z + Plots.PAD.maxZ) / 2
local DECK_HALF_D = (Plots.PAD.maxZ - DECK_MIN_Z) / 2

local ROW_X = ROW_FRONT_X - PAD_FRONT_REACH

--- THE U (2026-10-10, from the user's sketch): three bases on the west wall (the row
--- above) and one more each side, out in front of the row's ends toward Stage 1, turned
--- to face each other across the middle -- the -Z one faces +Z (180), the +Z one -Z (0).
--- Their fronts sit SIDE_FRONT_Z out, just past the row's outer edges (|z| 104.5), so a
--- side base never stands in front of an end row base. SIDE_X 36 -> 58 (later 2026-10-10,
--- on request: "move the side bases closer to the wall"): their east flank is WALL_CLEARANCE
--- off the east wall's face, where the chest square stood -- the chest and crates went to
--- the middle square, the leaderboards to the shoulders by Stage 1's mouth.
local SIDE_X = 58
local SIDE_FRONT_Z = 106
local SIDE_Z = SIDE_FRONT_Z + PAD_FRONT_REACH

--- Numbered left to right as you stand at the row's fronts facing Stage 1: 1 is the -Z
--- side base, 2-4 the row (-Z to +Z), 5 the +Z side base. ExhibitService fills them from
--- the middle out (FILL_ORDER).
Plots.CENTERS = {}
table.insert(Plots.CENTERS, { x = SIDE_X, z = -SIDE_Z, facing = 180 })
for _, z in ROW_Z do
	table.insert(Plots.CENTERS, { x = ROW_X, z = z, facing = -90 })
end
table.insert(Plots.CENTERS, { x = SIDE_X, z = SIDE_Z, facing = 0 })

--- THE CAMP OUTLINE -- the inner faces of the perimeter wall (Scenery.buildBaseWalls),
--- derived from the pads so a base (plus BACK_SPARE behind it) clears the wall by
--- WALL_CLEARANCE. One rectangle, x westX..eastX, |z| <= halfZ (it was stepped -- a back
--- block for the old west pair plus two wings -- until the rows went three to a side).
---
--- eastX is the east wall's inner face, the shoulders either side of Stage 1's mouth
--- (Scenery builds that wall on x = PLAZA.maxX, 8 thick). Everything that has to agree
--- on the camp's shape -- the apron, its rim lights, the wall, the base foliage,
--- World.verify()'s landmass -- reads this table or Plots.campRects.
local WALL_CLEARANCE = 10
-- The camp's walls stand where they stood for the open-floor bases (whose back fence
-- could slide 32 studs out), kept when the stands and floors came back.
-- 32 -> 24 when the pads grew 8 deeper at the front (PAD_MIN_Z), so the walls stay put.
-- 24 -> 6 on request (2026-10-08, "not so much extra space behind the bases"): the north
-- and south walls come 18 in, leaving ~13 studs between a back fence and the wall face.
local BACK_SPARE = 6
local BACK_REACH = Plots.PAD.maxZ + BACK_SPARE -- origin to the wall's reference line
Plots.CAMP = {
	-- The paved ground in front of the row (Hub.GATE_RECTS): from the fronts east, and
	-- out to the end pads' outer edges along Z. Scenery keeps it bare of foliage.
	pavedMinX = ROW_FRONT_X,
	pavedHalfZ = SIDE_Z + BACK_REACH,
	eastX = PLAZA.maxX - 4,
	westX = ROW_X - BACK_REACH - WALL_CLEARANCE,
	-- The side bases' backs set the north and south walls now (the U, 2026-10-10).
	halfZ = SIDE_Z + BACK_REACH + WALL_CLEARANCE,
}

--- The camp's floor as axis rectangles (one, now the outline is a plain rectangle),
--- grown by `grow` studs on every walled side (the east side stays at PLAZA.maxX, Stage
--- 1's edge). A positive `grow` reaches under the wall, which is what the apron wants
--- (see APRON_GROW).
function Plots.campRects(grow: number?): { Hub.Rect }
	local g = grow or 0
	local c = Plots.CAMP
	return {
		{ minX = c.westX - g, maxX = PLAZA.maxX, minZ = -c.halfZ - g, maxZ = c.halfZ + g },
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

--- The raised deck alone (padRect minus the front strip), for apronSkip: the strip in
--- front of it is laid by the apron, as grey path (see Hub.setPadFronts below).
local function deckRect(c: { x: number, z: number, facing: number }, inset: number): Kit.OrientedRect
	local yaw = math.rad(c.facing)
	return {
		cx = c.x + DECK_CENTER_Z * math.sin(yaw),
		cz = c.z + DECK_CENTER_Z * math.cos(yaw),
		halfWidth = HALF_W - inset,
		halfDepth = DECK_HALF_D - inset,
		yawDeg = c.facing,
	}
end

--- Each pad's front strip (plot-local z PAD_MIN_Z..DECK_MIN_Z, full width) as a world
--- rectangle snapped OUT to the plaza's tile grid, so the apron paints it as whole grey
--- path cells that run on seamlessly from the gate path in front. Pads face a multiple
--- of 90 degrees, so the strip is axis-aligned; the snap reaches at most one tile under
--- the deck (hidden) and 2 studs past a fence line (path either way).
local function frontStripRect(c: { x: number, z: number, facing: number }): { minX: number, maxX: number, minZ: number, maxZ: number }
	local origin = CFrame.new(c.x, 0, c.z) * CFrame.Angles(0, math.rad(c.facing), 0)
	local a = origin:PointToWorldSpace(Vector3.new(-HALF_W, 0, PAD_MIN_Z))
	local b = origin:PointToWorldSpace(Vector3.new(HALF_W, 0, DECK_MIN_Z))
	local t = Hub.TILE_SIZE
	local function down(v: number, o: number): number
		return o + math.floor((v - o) / t + 1e-6) * t
	end
	local function up(v: number, o: number): number
		return o + math.ceil((v - o) / t - 1e-6) * t
	end
	return {
		minX = down(math.min(a.X, b.X), PLAZA.minX),
		maxX = up(math.max(a.X, b.X), PLAZA.minX),
		minZ = down(math.min(a.Z, b.Z), PLAZA.minZ),
		maxZ = up(math.max(a.Z, b.Z), PLAZA.minZ),
	}
end
do
	local strips = {}
	for i, c in Plots.CENTERS do
		strips[i] = frontStripRect(c)
	end
	Hub.setPadFronts(strips)
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
		if Kit.pointInOrientedRect(x, z, deckRect(c, PAD_SKIP_INSET)) then
			return true
		end
	end
	return false
end

--- STAND LAYOUT — a full 3-column x 4-row grid, 12 stands a floor. It was cut to 9
--- (the centre column's front three left out) and then put back to 12 on request;
--- buildGalleryLanes' two aisles run either side of the centre column either way.
---
--- GRID_COLS are 3 evenly spaced x's, symmetric about x = 0. ±16.5 since the pad went
--- 57 wide (was ±20 on 66): with 8.9-wide plinths, the four gaps fence -> plinth ->
--- plinth -> plinth -> fence are all ~7.6 studs ("make them even", on request).
---
--- GRID_ROWS are 4 evenly spaced z's (pitch 17, widened from 13 with the +12 pad), ROW_TOP first — closest to the
--- back wall — counting DOWN from there toward the entrance. The front row
--- (z = -6) stays clear of PlotSpawn (z = -24).
---
--- GRID_SLOTS numbers the stands left to right, back row to front row: slot 1 is
--- back-left, slot 2 back-centre, slot 3 back-right, slot 12 front-right. Each entry
--- is a { column, row } index pair.
local GRID_COLS = { -16.5, 0, 16.5 }
local GRID_ROWS = { 45, 28, 11, -6 }
local GRID_SLOTS = {
	{ 1, 1 }, { 2, 1 }, { 3, 1 },
	{ 1, 2 }, { 2, 2 }, { 3, 2 },
	{ 1, 3 }, { 2, 3 }, { 3, 3 },
	{ 1, 4 }, { 2, 4 }, { 3, 4 },
}

local function slotOffset(slot: number): (number, number)
	local cell = GRID_SLOTS[slot]
	return GRID_COLS[cell[1]], GRID_ROWS[cell[2]]
end
assert(#GRID_SLOTS == Floors.GROUND_SLOTS, "the ground grid must hold exactly Floors.GROUND_SLOTS stands")

--- THE UPPER FLOORS' GALLERY — the ground's own 12-stand layout (Floors.UPPER_SLOTS
--- = 12), on every floor above the ground (see buildFloor). The outer columns' plinths
--- (edge at +/-20.95) leave the side corridors clear, and the front
--- row (plinth front at z -10.45) sits behind the deck's front rail at FLOOR.front.
--- The walkway corridor past them (out to the stair gates) starts at |x| 22.7.
---
--- Numbered the same way as the ground.
assert(#GRID_SLOTS == Floors.UPPER_SLOTS, "the upper grid must hold exactly Floors.UPPER_SLOTS stands")

--- The top of `floor`'s deck — what a player on it stands on. Floor 1 is the pad.
local function floorTopY(floor: number): number
	return Plots.PAD.topY + (floor - 1) * Floors.HEIGHT
end

--- Where a slot's stand goes: plot-local x and z, and the top of the floor it stands
--- on. Slots run on across floors (Config/Floors), so 1..12 are the ground grid above
--- and every floor past that repeats the same layout one storey up.
local function slotPlacement(slot: number): (number, number, number)
	local floor, i = Floors.floorOf(slot)
	assert(floor ~= nil and i ~= nil, `slot {slot} is on no floor`)
	local x, z = slotOffset(i)
	return x, z, floorTopY(floor)
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
local RISER_BASE = { w = 7.8, h = 0.95 }
local RISER_TOP = { w = 6.7, h = 0.75 }
local RISER_RIM = { h = 0.26, thickness = 0.6 } -- the raised frame around the recessed panel
local RISER_SURFACE = RISER_BASE.h + RISER_TOP.h
local PLINTH = {
	h = 1.3, -- how far the riser stack is lifted
	footW = 7.4,
	footH = 0.3,
	columnW = 6.3,
	bandW = 6.5,
	bandH = 0.4,
}
local DISPLAY_RIDE = 1.2 -- the Display part's centre above the top course
--- How far a `Display{slot}` part's centre sits above the deck its stand is on
--- (buildDisplayStand). ExhibitService works back from it to the deck overhead, to
--- size a displayed nuke against the floor above.
Plots.DISPLAY_LIFT = PLINTH.h + RISER_SURFACE + DISPLAY_RIDE
-- The slot marker, in studs on the top course's face: a dark inset square, and
-- L-shaped corner brackets (arm length x thickness) just inside the rim.
local SLOT_MARK = { inset = 4.9, arm = 1.15, thick = 0.3, reach = 2.4, color = "3A3F47" }

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
		pos = { ox, lift + RISER_SURFACE + DISPLAY_RIDE, oz },
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
--- `WASH PAD` sign subtitles, and the
--- gallery's pieces: the arch caps and stripe, every plinth band, every fence-post cap
--- and the empty-slot bracket Frames.
---
--- A NIL COLOUR MEANS "UNCLAIMED": it puts back `C.plotNeutral`, the grey a freshly
--- built plot wears — what ExhibitService hands it when a player leaves. Spelled as a
--- default rather than a separate `clearAccent()`, same reasoning as setHoseTier above.
---
--- TAG-DRIVEN, NOT NAME-DRIVEN. buildPlot stamps `Accent` on the parts and
--- accentBillboard stamps it on its labels and stroke, so this is the
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
---
--- A LITTLE FURTHER BACK, on request: x 26 -> 27.5, away from the wash spot. The table
--- still stands off the tub's -Z face; past the flat's end the tub's corner falls away.
local BOTTLE = {
	x = 27.5,
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
--- is ExhibitService.renderBottle, the same split setHoseTier has: the service
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
--- WHERE: backed onto the treadmill's fence (-X before buildPlot's `stripFlip`), facing
--- +X into the aisle beside the front row of stands (moved back over from the cleansing
--- station's fence on request, 2026-10-04): the cleansing-station spot mirrored. Then
--- slid down the fence to stand level with the treadmill, between its belt and the
--- fence (on request, 2026-10-08: "on the right of treadmill", as you walk in); the
--- treadmill moved toward the middle to make room (TREADMILL.cx). World.verify asserts
--- its station's gap to the treadmill's.
local LOCKER_TUBES_PER_TIER = 4
local LOCKER = {
	x = -29.6, -- the rack's centre; its back reaches x ~= -31.1
	z = -35, -- level with the treadmill's belt (was -15.5, up by the stair foot gate)
	yaw = -90, -- turns the authored -Z front to face +X, its back against the -X fence
	pitch = 1.65, -- tube centre to tube centre, along the rack
	tubeD = 1.45, -- glass diameter
	tubeH = 3.8, -- glass height, cap to cap (taller on request; the rack grows with it)
	capH = 0.24,
	deckH = 0.3,
	kerbH = 0.55,
	depth = 2.6,
	-- Was 6, cut to 4.5 when the treadmill came 2 closer; 5.5 once World.verify measured
	-- to the belt's footprint (what StationService tests) instead of its sphere.
	radius = 5.5,
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
	-- to face +X and puts the back against the -X fence.
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

-- ── The treadmill (removed) ─────────────────────────────────────────────────
--
-- Speed was trained on a treadmill on the -X side of the entrance strip, beside the
-- Quarantine Locker, until 2026-10-09: walk speed is bought at the Upgrades booth now
-- (Config/WalkSpeed). Nothing builds one any more, and a place saved with one loses it
-- at boot (ExhibitService -> removeTreadmill), so the base is right before a rebuild.

--- Take a saved place's treadmill (and its upgrade sign) off plot model `plot`.
function Plots.removeTreadmill(plot: Instance)
	local treadmill = plot:FindFirstChild("Treadmill", true)
	if treadmill then
		treadmill:Destroy()
	end
end

-- ── The Hoses pad ────────────────────────────────────────────────────────────
--
-- WHERE HOSES ARE BOUGHT (2026-10-09, on request: "remove hose shop booth, instead make
-- a pad to the right of the cleaning station"). Every hose shop (Base Camp's booth, the
-- Twilight and Magma stalls) is gone; this studded pad off the end of the base's
-- own tub is the only place left, and it sells every hose with no camp lock
-- (Gear.CAMP_FREE). It is a shop station (StationKind "shop", StationId "Cleaner") with
-- the stands' "ViewShop" prompt, so StationController opens the usual card row on its E,
-- titled "Hoses" (Config/Booths). `OwnerOnly` makes it its base owner's alone, like the
-- tub (StationService, client OwnStationPromptController).
--
-- PLACED OFF THE TUB'S DECK, NOT AT A PLOT COORDINATE: off its ENTRANCE end, the side
-- closest to the stages (2026-10-10, on request: "put the hose upgrade on the left of the
-- cleansing station (the side closest to the stages)"; it sat on the fence side before).
-- Which end of the deck's long axis that is flips between mirrored strips, so it is read
-- off where the stands are (the entrance is the other way). The same rule moves the pad
-- on a place saved with it elsewhere (ExhibitService calls this at boot).
local HOSE_PAD = {
	width = 3.6, -- out from the deck's end, toward the entrance
	length = 6, -- across the deck's end
	gap = 0.5, -- between the tub's deck and the pad
	radius = 4, -- the station circle: well inside the pad's own reach, off the tub's spot
	rim = 0.3,
}

--- Build (or rebuild) plot model `plot`'s Hoses pad beside its cleansing station's deck.
--- Returns the pad part, or nil if the plot has no station to stand it by.
function Plots.ensureHosePad(plot: Instance): BasePart?
	local station = plot:FindFirstChild("CleansingStation", true)
	local deck = station and station:FindFirstChild("Deck")
	if deck == nil or not deck:IsA("BasePart") then
		return nil
	end
	local old = plot:FindFirstChild("HosePad", true)
	if old then
		old:Destroy()
	end
	local P = HOSE_PAD
	local m = Instance.new("Model")
	m.Name = "HosePad"
	-- Deck-local: X is the long axis, Y up. The deck's top stands 0.15 over the strip's
	-- floor (buildCleansingStation), so the floor is that far under it.
	local floorY = deck.Position.Y + deck.Size.Y / 2 - 0.15
	local toEntrance = 1
	local stand = plot:FindFirstChild("Stand1", true)
	if stand and stand:IsA("BasePart") and deck.CFrame.RightVector:Dot(stand.Position - deck.Position) > 0 then
		toEntrance = -1
	end
	local center = deck.CFrame * CFrame.new(toEntrance * (deck.Size.X / 2 + P.gap + P.width / 2), 0, 0)
	-- A quarter-turn, so the pad's length runs across the deck's end (its local Z).
	local frame = CFrame.new(center.Position.X, floorY, center.Position.Z)
		* (deck.CFrame - deck.CFrame.Position)
		* CFrame.Angles(0, math.pi / 2, 0)
	local color = C.shopCleaner
	local padPart = build(m, frame, {
		name = "Pad",
		pos = { 0, 0.1, 0 },
		size = { P.length, 0.2, P.width },
		color = color,
		material = "Plastic",
		studs = true,
		canCollide = false,
		attributes = { StationKind = "shop", StationId = "Cleaner", Radius = P.radius, OwnerOnly = true },
	})
	for _, bar in {
		{ 0, -P.width / 2, P.length + P.rim, P.rim },
		{ 0, P.width / 2, P.length + P.rim, P.rim },
		{ -P.length / 2, 0, P.rim, P.width },
		{ P.length / 2, 0, P.rim, P.width },
	} do
		build(m, frame, {
			name = "PadRim",
			pos = { bar[1], 0.13, bar[2] },
			size = { bar[3], 0.26, bar[4] },
			color = color,
			material = "Neon",
			canCollide = false,
		})
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ViewShop" -- StationController's BROWSE_PROMPT: E opens the card row
	prompt.ActionText = "Browse"
	prompt.ObjectText = "Hoses"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = padPart
	m.Parent = station.Parent
	return padPart
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
local STAIR_RAIL_T = 0.4 -- a flight's handrails and their posts: half the old 0.8
--- A gate in a fence line: the gap from `z0` to `z1` (plot-local) that a flight of
--- stairs outside the base is reached through, and the floor whose purchase opens it
--- (nil = always open). Until then GateFill rails span the gap (Plots.setFloors).
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
	local z0, z1 = pad.deckMinZ + 0.5 + RAIL_POST_W / 2, pad.maxZ - 0.5 - RAIL_POST_W / 2
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

-- The avatar-plate anchor: an invisible point high over the CENTRE of the pad. The
-- plate itself (circular headshot, owner's name, $/s) is drawn client-side by
-- client/Controllers/BaseMarkerController.luau off this part, so it can scale with
-- each player's screen; ExhibitService stamps the owner and rate on the plot model
-- as attributes for it to read.
local function buildNamePlate(parent: Instance, origin: CFrame)
	local pad = Plots.PAD
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
	return anchor
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

--- THE GALLERY WALKWAYS — a black path (cream until 2026-10-04) laid through the base, so the deck
--- reads as a floor plan instead of one brown field (on request, the Gallery pass).
--- Kept as-is through the nine-stand cut and back to twelve (on request).
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
--- Thinned ~0.6x on request (2026-10-05): aisle 6, entry 8, band 5, landing ~4.8.
local LANE = { aisle = 3.6, entry = 4.8, kerb = 0.5, band = 3, landing = 3, lift = 0.06, thick = 0.12 }
--- `topY` is the floor the lanes lie on and `entryZ` where the entry lane starts:
--- the pad's front edge on the ground, the deck's front rail on an upper floor
--- (buildFloor), which has the same grid and so the same walkways.
---
--- `stairs` (optional) runs the walkways out to the flights: `depart` is the side
--- (-1/+1) whose flight climbs up from this floor — the cross band reaches out to its
--- foot at `footZ` — and `arrive` the side whose flight lands here, where the back
--- landing reaches over to its head. `inX`/`outX` are a flight's |x| edges.
--- `next` is the floor the departing flight leads to: its walkway spur is tagged
--- `PathFloor` = next and only shows once that floor is bought (Plots.setFloors); the
--- plain kerb it replaces is tagged `PathFloorUntil` = next and shows until then.
type LaneStairs = { depart: number?, arrive: number?, next: number?, footZ: number, inX: number, outX: number }
local function buildGalleryLanes(parent: Instance, origin: CFrame, topY: number?, entryZ: number?, stairs: LaneStairs?)
	local pad = Plots.PAD
	local floorY = topY or pad.topY
	local entryFrom = entryZ or pad.minZ
	local folder = Instance.new("Folder")
	folder.Name = "GalleryLanes"

	local tag: { [string]: any }? = nil -- attributes for the plates being laid right now
	local function plate(name: string, x0: number, x1: number, z0: number, z1: number, color: string)
		build(folder, origin, {
			attributes = tag,
			-- Built as a plot with nothing bought: the spur hidden until setFloors.
			transparency = if tag and tag.PathFloor then 1 else nil,
			name = name,
			pos = { (x0 + x1) / 2, floorY + LANE.lift - LANE.thick / 2, (z0 + z1) / 2 },
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
	-- back row and runs to the back fence's inner face, at most LANE.landing deep.
	local bandBack = GRID_ROWS[#GRID_ROWS] - standHalf - 1.55
	local bandFront = bandBack - LANE.band
	local landingBack = pad.maxZ - 0.5 - RAIL_POST_W
	local landingFront = math.max(GRID_ROWS[1] + standHalf + 1.05, landingBack - LANE.landing)

	local LANE_BLACK, KERB = C.baseLane, C.baseLaneKerb

	-- Entry: from the pad's front edge (under the arch) to the cross band.
	plate("Lane", -entryHalf, entryHalf, entryFrom, bandFront, LANE_BLACK)
	mirrored("Kerb", entryHalf, entryHalf + K, entryFrom, bandFront, KERB)

	-- Cross band, joining the entry to both aisles.
	-- On the departing flight's side it runs on out to the flight's outer edge, then a
	-- spur turns back along the flight's width to its first step.
	plate("Lane", -outer, outer, bandFront, bandBack, LANE_BLACK)
	plate("Kerb", -(inner - K), inner - K, bandBack, bandBack + K, KERB)
	for _, sd in { -1, 1 } do
		local function side(name: string, a: number, b: number, z0: number, z1: number, color: string)
			plate(name, math.min(sd * a, sd * b), math.max(sd * a, sd * b), z0, z1, color)
		end
		local departs = stairs and stairs.depart == sd
		if departs and stairs then
			local sIn, sOut, foot = stairs.inX, stairs.outX, stairs.footZ
			tag = if stairs.next then { PathFloor = stairs.next } else nil
			side("Lane", outer, sOut, bandFront, bandBack, LANE_BLACK)
			side("Lane", sIn, sOut, bandBack, foot, LANE_BLACK)
			side("Kerb", entryHalf + K, sOut + K, bandFront - K, bandFront, KERB)
			side("Kerb", sOut, sOut + K, bandFront, foot, KERB)
			side("Kerb", outer + K, sIn - K, bandBack, bandBack + K, KERB)
			side("Kerb", sIn - K, sIn, bandBack, foot, KERB)
			tag = if stairs.next then { PathFloorUntil = stairs.next } else nil
		end
		if not departs or tag then
			side("Kerb", entryHalf + K, outer + K, bandFront - K, bandFront, KERB)
			side("Kerb", outer, outer + K, bandFront, bandBack, KERB)
		end
		tag = nil
	end

	-- The two aisles between the stand columns.
	mirrored("Lane", inner, outer, bandBack, landingFront, LANE_BLACK)
	mirrored("Kerb", inner - K, inner, bandBack, landingFront, KERB)
	mirrored("Kerb", outer, outer + K, bandBack, landingFront, KERB)

	-- Back landing along the fence, joining the aisles' far ends.
	-- On the arriving flight's side it reaches over to the flight's head, open where
	-- the steps meet it.
	plate("Lane", -outer, outer, landingFront, landingBack, LANE_BLACK)
	plate("Kerb", -(inner - K), inner - K, landingFront - K, landingFront, KERB)
	for _, sd in { -1, 1 } do
		local function side(name: string, a: number, b: number, z0: number, z1: number, color: string)
			plate(name, math.min(sd * a, sd * b), math.max(sd * a, sd * b), z0, z1, color)
		end
		if stairs and stairs.arrive == sd then
			local sIn, sOut = stairs.inX, stairs.outX
			side("Lane", outer, sOut, landingFront, landingBack, LANE_BLACK)
			side("Kerb", outer + K, sIn, landingFront - K, landingFront, KERB)
			side("Kerb", sOut, sOut + K, landingFront - K, landingBack, KERB)
		else
			side("Kerb", outer, outer + K, landingFront, landingBack, KERB)
		end
	end

	folder.Parent = parent
end
--- The dark board fill the floor signs are painted on (it was the entrance arch's
--- sign colour; the arch is gone, on request).
local ARCH_SIGN_FILL = "2B2F36"

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
--- THE FLIGHTS RUN OUTSIDE THE BASE, AND ALTERNATE SIDES (on request: the stairs
--- used to climb the side corridors inside the fence, through a stairwell hole in each
--- deck). The flight up from the ground climbs the -X side, the one up from floor 2
--- the +X side, each hugging the OUTSIDE of the side fence, front to back, in the apron
--- gap between neighbouring bases. You step out through a gate in the fence onto the
--- foot landing, climb, and step back in through an opening in the next deck's rail
--- from the head landing at the back. The decks are solid: nothing is cut out of them.
--- A foot gate is filled with GateFill rails until the floor it leads to is bought.
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
	front = -19, -- the decks' front edge (plot-local z): 8 studs out over the entrance strip, still clear of the tub
	thick = 1.2,
	fascia = 0.6, -- the accent band round a deck's edge
	-- 4.4 wide, 0.2 off the fence (were 4.8 and 0.4): the square layout puts paired pads
	-- 10 studs apart, and two flights back to back in that lane need 0.8 between them.
	stairW = 4.4,
	stairOff = 0.2, -- gap between the pad/deck side edge and a flight's inner edge
	stairZ = -7.6, -- where a flight's first step starts; its foot gate is the `foot` in front
	foot = 5, -- depth of the landing (and the fence gate) in front of a flight's first step
	landing = 6, -- depth of the head landing (and the deck-rail opening) behind a flight's top
	rise = 1, -- Floors.HEIGHT steps of this, so a flight lands exactly on the next deck
	-- Pillars stand ON the fence line, one per deck corner, outer faces flush with the
	-- pad's side and the deck's front/back edge, so the rails run straight through
	-- them. A pillar takes over the fence there: the posts it swallows are hidden
	-- while its floor is up (hidePillarPosts / Plots.setFloors) instead of poking
	-- out of it.
	pillarW = 1.2,
	handrails = { 2.0, 3.5 }, -- heights of a flight's two sloped rails over the step line
	handPostH = 3.2,
}
local FLIGHT_STEPS = math.round(Floors.HEIGHT / FLOOR.rise)
-- Each flight runs the whole depth of the deck, front to a landing at the back, so
-- the tread is whatever spreads FLIGHT_STEPS over that run.
FLOOR.tread = (Plots.PAD.maxZ - FLOOR.landing - FLOOR.stairZ) / FLIGHT_STEPS
local FLIGHT_TOP_Z = FLOOR.stairZ + FLIGHT_STEPS * FLOOR.tread
--- |x| of a flight's inner edge / centre line / outer edge, all past the side fence.
local STAIR_IN = HALF_W + FLOOR.stairOff
local STAIR_X = STAIR_IN + FLOOR.stairW / 2
local STAIR_OUT = STAIR_IN + FLOOR.stairW
--- The fence gates: where you step out to a flight's foot, and back in off its head.
--- The head opening stops short of the back corner so the corner post and pillar stay.
local FOOT_GATE = { z0 = FLOOR.stairZ - FLOOR.foot, z1 = FLOOR.stairZ }
local HEAD_GATE = { z0 = FLIGHT_TOP_Z, z1 = Plots.PAD.maxZ - FLOOR.pillarW - 0.2 }

--- Which side (-1 = -X, +1 = +X) the flight climbing UP FROM `floor` runs up.
local function flightSide(floor: number): number
	return if floor % 2 == 1 then -1 else 1
end

--- Where `floor`'s walkways meet the stairs (buildGalleryLanes): the flight up from
--- it, if there is a floor above, and the flight that lands on it, if it is not the
--- ground.
local function laneStairs(floor: number): LaneStairs
	return {
		depart = if floor < Floors.MAX then flightSide(floor) else nil,
		next = if floor < Floors.MAX then floor + 1 else nil,
		arrive = if floor > 1 then flightSide(floor - 1) else nil,
		footZ = FLOOR.stairZ,
		-- The walkway corridor along the inside of the fence, out to the gate.
		inX = HALF_W - 1 - FLOOR.stairW,
		outX = HALF_W - 1,
	}
end

--- THE CEILING LIGHT — no fixture, just light (on request: the lamp panels read as
--- clutter). One invisible, non-colliding sheet under the whole deck carries a wide,
--- bright SurfaceLight facing down, washing out the stair and rail shadows on the floor
--- below. A SurfaceLight spreads over its face, so one sheet covers the gallery. NO
--- SHADOWS of its own: shadow casting is the expensive part of a light.
--- Brightness 2.5 -> 1.0 (2026-09-30, "the floor very bright").
local CEILING_LIGHT = { range = 24, brightness = 1.0, color = "FFF6E8" }
local function buildCeilingLights(parent: Instance, origin: CFrame, deckTop: number)
	local pad = Plots.PAD
	local halfW = pad.width / 2 - 1
	local z0, z1 = FLOOR.front + 1, pad.maxZ - 1
	local sheet = build(parent, origin, {
		name = "CeilingLight",
		pos = { 0, deckTop - FLOOR.thick - 0.1, (z0 + z1) / 2 },
		size = { halfW * 2, 0.05, z1 - z0 },
		color = CEILING_LIGHT.color,
		material = "SmoothPlastic",
		canCollide = false,
	})
	sheet.Transparency = 1
	sheet.CastShadow = false
	sheet.CanQuery = false
	sheet.CanTouch = false
	local l = Instance.new("SurfaceLight")
	l.Face = Enum.NormalId.Bottom
	l.Color = Color3.fromHex(CEILING_LIGHT.color)
	l.Range = CEILING_LIGHT.range
	l.Brightness = CEILING_LIGHT.brightness
	l.Angle = 180
	l.Shadows = false
	l.Parent = sheet
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

--- The flight of stairs from `fromFloor` up to the floor above it: open studded
--- treads, one stud thick with nothing under them, in alternating greys so
--- the steps read from across the plaza, and a pair of sloped handrails down each
--- side. The rails are rotated straight parts, not a staircase of little bars
--- (memory: straight-edges-over-pixel-stairs). Outside the fence: a landing at the
--- foot (in front of the fence gate) and one at the head (beside the deck's opening),
--- railed on their open sides. No support posts under them (removed on request).
local function buildFlight(parent: Instance, origin: CFrame, fromFloor: number)
	local m = Instance.new("Model")
	m.Name = "Stairs"
	local baseY = floorTopY(fromFloor)
	local sd = flightSide(fromFloor)
	local x = sd * STAIR_X
	local topY = baseY + Floors.HEIGHT
	local groundY = Plots.PAD.topY - 1.5 -- the apron the ground flight's foot block stands on

	-- The landings. The foot of the ground flight is a solid block down to the apron.
	local slab = FLOOR.thick
	local function landing(name: string, y: number, z0: number, z1: number, solid: boolean)
		local h = if solid then y - groundY else slab
		build(m, origin, {
			name = name,
			pos = { sd * (HALF_W + STAIR_OUT) / 2, y - h / 2, (z0 + z1) / 2 },
			size = { STAIR_OUT - HALF_W, h, z1 - z0 },
			color = C.standGrey,
			material = "Plastic",
			studs = true,
		})
	end
	landing("FootLanding", baseY, FOOT_GATE.z0, FOOT_GATE.z1, fromFloor == 1)
	landing("HeadLanding", topY, FLIGHT_TOP_Z, Plots.PAD.maxZ, false)

	-- Rails round the landings' open sides: the outer edge, and the end away from
	-- the flight. The side against the base is the fence gate / deck opening.
	local rails = Instance.new("Folder")
	rails.Name = "LandingRails"
	local ox = sd * (STAIR_OUT - RAIL_POST_W / 2)
	local ix = sd * (HALF_W + RAIL_POST_W / 2)
	local fz = FOOT_GATE.z0 + RAIL_POST_W / 2
	railRun(rails, origin, baseY, ix, fz, ox, fz)
	railRun(rails, origin, baseY, ox, fz, ox, FLOOR.stairZ, true)
	local bz = Plots.PAD.maxZ - RAIL_POST_W / 2
	railRun(rails, origin, topY, ox, FLIGHT_TOP_Z, ox, bz)
	railRun(rails, origin, topY, ox, bz, ix, bz, true)
	rails.Parent = m

	for i = 1, FLIGHT_STEPS do
		-- One stud-thick tread per step, nothing under it: an open stair.
		build(m, origin, {
			name = "Step",
			pos = { x, baseY + (i - 0.5) * FLOOR.rise, FLOOR.stairZ + (i - 0.5) * FLOOR.tread },
			size = { FLOOR.stairW, FLOOR.rise, FLOOR.tread },
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
		local hx = x + edge * (FLOOR.stairW / 2 - STAIR_RAIL_T / 2)
		for _, lift in FLOOR.handrails do
			build(m, origin, {
				name = "Handrail",
				pos = { hx, baseY + climb / 2 + lift, FLOOR.stairZ + run / 2 },
				size = { STAIR_RAIL_T, STAIR_RAIL_T, length },
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
				size = { STAIR_RAIL_T, FLOOR.handPostH, STAIR_RAIL_T },
				color = C.railPost,
				material = "Plastic",
				studs = true,
			})
		end
	end

	m.Parent = parent
end

--- One whole storey: its solid deck, the accent band round the deck's edge, the
--- pillars holding it up, the flight of stairs outside the fence that arrives at it,
--- the railings round the deck (open where that flight lands, gated where the next
--- one leaves) and its gallery of stands.
local function buildFloor(parent: Instance, origin: CFrame, index: number, floor: number, accent: string)
	local pad = Plots.PAD
	local m = Instance.new("Model")
	m.Name = `Floor{floor}`
	m:SetAttribute("FloorIndex", floor)

	local top = floorTopY(floor)
	local below = floorTopY(floor - 1)
	local front, back = FLOOR.front, pad.maxZ

	-- ── The deck: one solid studded board, like the pad's own floor ─
	local plate = build(m, origin, {
		name = "Deck",
		pos = { 0, top - FLOOR.thick / 2, (front + back) / 2 },
		size = { pad.width, FLOOR.thick, back - front },
		color = C.baseFloor,
		material = "Plastic",
	})
	plate.CastShadow = false

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
	-- Off the ground they start on the Trim's top, not inside it.
	if floor == 2 then
		below += 0.35
	end
	local pillarH = top - FLOOR.thick - below
	local pw = FLOOR.pillarW / 2
	for _, sx in { -1, 1 } do
		for _, pz in { front + pw, back - pw } do
			build(m, origin, {
				name = "Pillar",
				pos = { sx * (HALF_W - pw), below + pillarH / 2, pz },
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

	-- ── Railings: the deck's four edges ─────────────────────────
	-- The side the flight arrives on is open over its head landing; the side the next
	-- flight leaves from has a foot gate, filled until that floor is bought.
	local rails = Instance.new("Folder")
	rails.Name = "Railings"
	local rx = HALF_W - RAIL_POST_W / 2
	local rzFront, rzBack = front + RAIL_POST_W / 2, back - RAIL_POST_W / 2
	-- The front edge is one skinny bar at rail height, no posts (on request), so the
	-- gallery below stays open to the plaza. It still collides: past it is a drop.
	build(rails, origin, {
		name = "FrontBar",
		pos = { 0, top + RAIL_H, rzFront },
		size = { rx * 2 + RAIL_POST_W, STAIR_RAIL_T, STAIR_RAIL_T },
		color = C.railGrey,
		material = "Plastic",
		studs = true,
	})
	railRun(rails, origin, top, -rx, rzBack, rx, rzBack)
	for _, sd in { -1, 1 } do
		local gates: { FenceGate } = {}
		if floor < Floors.MAX and flightSide(floor) == sd then
			table.insert(gates, { z0 = FOOT_GATE.z0, z1 = FOOT_GATE.z1, floor = floor + 1 })
		end
		if flightSide(floor - 1) == sd then
			table.insert(gates, HEAD_GATE)
		end
		-- The front corner post is the side's own (the front bar has none); the back
		-- corner belongs to the back run.
		fenceLineZ(rails, origin, top, sd * rx, rzFront, rzBack, gates, true, false, true)
	end
	rails.Parent = m
	capFencePosts(rails, accent)

	-- The ground's walkways, laid on this deck from its front rail back.
	buildGalleryLanes(m, origin, top, front + RAIL_POST_W, laneStairs(floor))
	buildCeilingLights(m, origin, top)

	-- ── The gallery ─────────────────────────────────────────────
	local first = Floors.firstSlot(floor)
	for slot = first, first + Floors.UPPER_SLOTS - 1 do
		buildDisplayStand(m, origin, index, slot, accent)
	end

	m.Parent = parent
end

--- "$40M" rather than "$40,000,000" (on request): K / M / B / T, Mastery.short's ladder.
local function floorPrice(floor: number): string
	return "$" .. Mastery.short(Floors.PRICES[floor] or 0)
end

--- What a floor sign's board reads, painted ON the board (a SurfaceGui named "Sign"
--- with Title / Subtitle children, so ExhibitService.flashSign still finds its
--- Subtitle): "Floor 2" over "Purchase floor for $40,000,000", in Gotham Black. It
--- replaced the floating "BUILD FLOOR 2 / +9 stands for $X" billboard and the
--- capitalised "FLOOR 2" painted text (on request). Idempotent; a board saved with
--- the old pieces has them taken down, so ExhibitService calls this as it wires each
--- sign and no world rebuild is needed.
local FLOOR_SIGN_LOOK = 3
local FLOOR_SIGN_PRICE_COLOR = "8FE36B"
function Plots.dressFloorSign(board: BasePart)
	local floor = board:GetAttribute("BuysFloor")
	if type(floor) ~= "number" then
		return
	end
	-- A saved board's prompt still carries the old comma'd price.
	local prompt = board:FindFirstChild("BuyFloor")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ObjectText = floorPrice(floor)
	end
	local current = board:FindFirstChild("Sign")
	if current and current:IsA("SurfaceGui") and current:GetAttribute("Look") == FLOOR_SIGN_LOOK then
		return
	end
	for _, child in board:GetChildren() do
		if child:IsA("BillboardGui") or child:IsA("SurfaceGui") then
			child:Destroy()
		end
	end
	local subtitle = `Purchase floor for {floorPrice(floor)}`
	board:SetAttribute("SignText", subtitle)

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui:SetAttribute("Look", FLOOR_SIGN_LOOK)

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
	line("Title", `Floor {floor}`, C.labelText, 0.1, 0.48, 2.5)
	line("Subtitle", subtitle, FLOOR_SIGN_PRICE_COLOR, 0.62, 0.24, 1.5)
	gui.Parent = board
end

--- The sign that sells floor `floor`: a post and a board standing just inside
--- the fence gate out to that floor's flight of stairs, on the floor below it. Holding
--- E on the board buys the floor (ExhibitService wires it by Kit.FLOOR_TAG); the sign
--- then disappears, the gate opens and the stairs are outside it. Plots.setFloors shows exactly one of these on a
--- claimed plot — the next floor up — and none on a full or unclaimed one.
---
--- ANSWERS IN THE WORLD. A refused purchase is written into this sign's painted
--- subtitle for a moment (ExhibitService), not sent as a StationResult toast, which
--- nobody sees away from a panel (memory: station-result-toast-needs-panel).
--- `SignText` on the board is the subtitle to put back afterwards.
local function buildFloorSign(parent: Instance, origin: CFrame, index: number, floor: number, accent: string)
	local m = Instance.new("Model")
	m.Name = `FloorSign{floor}`
	local base = floorTopY(floor - 1)
	-- Hung on the inside of the fence, across the gate out to that floor's flight
	-- (on request: it used to stand on a post). Turned so its face looks into the base.
	local sd = flightSide(floor - 1)
	local railX = HALF_W - RAIL_POST_W / 2
	local x = sd * (railX - RAIL_BAR_T / 2 - 0.27)
	local z = (FOOT_GATE.z0 + FOOT_GATE.z1) / 2
	local face = Kit.ang(0, sd * 90, 0)

	-- The accent stripe along the board's top edge doubles as the bar it hangs from,
	-- resting on the fence's top rail.
	build(m, origin, {
		name = "SignStripe",
		pos = { x, base + RAIL_H + RAIL_BAR_T / 2 + 0.15, z },
		size = { 5.2, 0.3, 0.7 },
		rot = face,
		color = accent,
		material = "SmoothPlastic",
		canCollide = false,
		attributes = { Accent = true },
	})
	local board = build(m, origin, {
		name = "SignBoard",
		pos = { x, base + RAIL_H + RAIL_BAR_T / 2 - 1.2, z },
		size = { 5, 2.4, 0.5 },
		rot = face,
		color = ARCH_SIGN_FILL,
		material = "SmoothPlastic",
		attributes = { BuysFloor = floor, PlotIndex = index },
	})
	-- Front is the face turned into the base.
	Plots.dressFloorSign(board)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyFloor"
	prompt.ActionText = `Build Floor {floor}`
	prompt.ObjectText = floorPrice(floor)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = board

	m.Parent = parent
end

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

--- THE BASE GLOW — a little light inside each base, on request (2026-10-04). The old
--- per-plot ring (buildBaseLights, ~20 EdgeLights at brightness 1.4) was taken out for
--- making the floors too bright (#595), so this is deliberately small: eight warm,
--- dim, shadowless points, no fixtures. Six hang over the two aisles of the ground
--- gallery (a 2 x 3 grid between the stand columns), two over the front strip by the
--- washer and the treadmill. Low enough to sit under floor 2's deck.
local BASE_GLOW = { range = 16, brightness = 0.55, color = "FFE9C8", height = 8 }
local BASE_GLOW_SPOTS = {
	{ -10, 37 }, { 10, 37 },
	{ -10, 19 }, { 10, 19 },
	{ -10, 1 }, { 10, 1 },
	{ -16, -32 }, { 16, -32 },
}
local function buildBaseGlow(parent: Instance, origin: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "BaseGlow"
	for _, spot in BASE_GLOW_SPOTS do
		local p = Instance.new("Part")
		p.Name = "GlowLight"
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.CFrame = origin * CFrame.new(spot[1], Plots.PAD.topY + BASE_GLOW.height, spot[2])
		p.Anchored = true
		p.Transparency = 1
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		local l = Instance.new("PointLight")
		l.Color = Color3.fromHex(BASE_GLOW.color)
		l.Range = BASE_GLOW.range
		l.Brightness = BASE_GLOW.brightness
		l.Shadows = false
		l.Parent = p
		p.Parent = folder
	end
	folder.Parent = parent
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
--- THE PILLARS TAKE OVER THE FENCE. Every fence post (and its cap) a floor's pillar
--- swallows — the ground railing's under floor 2's, floor 2's deck railing under
--- floor 3's — is tagged `PillarFloor` = that floor and hidden, so nothing pokes out
--- of a pillar. The pillar only exists while its floor is bought, though, so
--- showPillarPosts (Plots.setFloors) brings a post back when its floor is not.
local PILLAR_FLOOR_ATTR = "PillarFloor"
local function setPostHidden(part: BasePart, hidden: boolean)
	part.Transparency = if hidden then 1 else 0
	part.CanCollide = (not hidden) and part:GetAttribute("PillarCollide") == true
end

local function hidePillarPosts(m: Model)
	for floor = 2, Floors.MAX do
		local f = m:FindFirstChild(`Floor{floor}`)
		if f == nil then
			continue
		end
		for _, pillar in f:GetChildren() do
			if pillar.Name ~= "Pillar" or not pillar:IsA("BasePart") then
				continue
			end
			local pc, half = pillar.CFrame, pillar.Size / 2
			for _, d in m:GetDescendants() do
				if (d.Name == "RailPost" or d.Name == "PostCap") and d:IsA("BasePart") and not d:IsDescendantOf(f) then
					local l = pc:PointToObjectSpace(d.Position)
					local dh = d.Size / 2
					if math.abs(l.X) < half.X + dh.X and math.abs(l.Z) < half.Z + dh.Z and math.abs(l.Y) < half.Y + dh.Y then
						d:SetAttribute(PILLAR_FLOOR_ATTR, floor)
						d:SetAttribute("PillarCollide", d.CanCollide)
						setPostHidden(d, true)
					end
				end
			end
		end
	end
end

local function showPillarPosts(model: Instance, count: number)
	for _, d in model:GetDescendants() do
		local floor = d:GetAttribute(PILLAR_FLOOR_ATTR)
		if typeof(floor) == "number" and d:IsA("BasePart") then
			setPostHidden(d, floor <= count)
		end
	end
end

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
	showPillarPosts(model, count)
	-- Open the gates to the flights that are built, fill the rest.
	for _, d in model:GetDescendants() do
		local gate = d:GetAttribute(GATE_FLOOR_ATTR)
		if typeof(gate) == "number" and d:IsA("BasePart") then
			local open = gate <= count
			d.Transparency = if open then 1 else 0
			d.CanCollide = (not open) and d:GetAttribute("GateCollide") == true
		end
		-- The walkway out to a flight shows once its floor is bought; the kerb it
		-- replaces shows until then.
		local path, pathUntil = d:GetAttribute("PathFloor"), d:GetAttribute("PathFloorUntil")
		if d:IsA("BasePart") then
			if typeof(path) == "number" then
				d.Transparency = if path <= count then 0 else 1
			elseif typeof(pathUntil) == "number" then
				d.Transparency = if pathUntil <= count then 1 else 0
			end
		end
	end

	local plate = model:FindFirstChild("NamePlate")
	local rest = plate and plate:GetAttribute("BaseCFrame")
	if plate and plate:IsA("BasePart") and typeof(rest) == "CFrame" then
		plate.CFrame = rest + Vector3.new(0, (count - 1) * Floors.HEIGHT, 0)
	end
	model:SetAttribute("Floors", count)
end
--- THE HAZARD LINE — yellow and black studded bricks laid flat across the front of the
--- raised deck. They marked where the open floor's nukes could go, and stayed as the
--- deck's edge when the stands came back. Flat, so you walk over it; not collidable.
local PLACE_LINE = { depth = 0.8, height = 0.16, stripe = 2.4 }
--- The hazard line's back edge (plot-local z), just behind the deck's front.
local HAZARD_Z = -20
local function buildPlaceLine(parent: Instance, origin: CFrame)
	local folder = Instance.new("Folder")
	folder.Name = "PlaceLine"
	local x0, x1 = -HALF_W + 1, HALF_W - 1
	local stripes = math.max(2, math.round((x1 - x0) / PLACE_LINE.stripe))
	local w = (x1 - x0) / stripes
	local z = HAZARD_Z - PLACE_LINE.depth / 2
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

--- Where the cleansing station's tub stands, plot-local before STRIP_INSET (the +8 shift
--- and the `cx, cz` in buildCleansingStation): the centre a mirrored strip turns it about.
local STATION_CENTER = { x = 26, z = -32 }
--- The station and its bottle slid this far toward the middle of the pad (2026-10-09,
--- on request: "shift the cleaning station 4 studs to the left, closer to the nuke
--- displays"). The Hoses pad stands off its entrance end (Plots.ensureHosePad).
--- Applied in the strip's written space, before a mirrored strip's flip, so it is always
--- toward the middle.
local STATION_SHIFT = -4

--- A frame that turns whatever is built through it 180 degrees about plot-local
--- (x0, z0) and sets it down at (-x0, z0): the same machine on the opposite fence, still
--- backed onto it (buildPlot's `stripFlip`).
local function flipAbout(x0: number, z0: number): CFrame
	return CFrame.new(-x0, 0, z0) * CFrame.Angles(0, math.pi, 0) * CFrame.new(-x0, 0, -z0)
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
	local rect: Hub.Rect = { minX = -HALF_W, maxX = HALF_W, minZ = pad.deckMinZ, maxZ = pad.maxZ }
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
		pos = { 0, pad.topY - cap / 2, DECK_CENTER_Z },
		size = { rect.maxX - rect.minX, cap, rect.maxZ - rect.minZ },
		color = C.baseFloor,
		material = "Plastic",
	})

	buildPlaceLine(m, origin)
	-- The walkways laid over it (the Gallery pass), from just behind the hazard line,
	-- and the deck-coloured plate over the front strip in front of the deck.
	buildGalleryLanes(m, origin, nil, HAZARD_Z, laneStairs(1))
	buildFrontPath(m, origin)

	-- Accent trim, so whose plot is whose is readable from across the plaza. Matte —
	-- the colour alone carries the "whose plot" cue now, no glow. `Accent` tags it for
	-- Plots.setPlotAccent; grey until the owner picks a hue.
	for _, side in { -1, 1 } do
		build(m, origin, {
			name = "Trim",
			pos = { side * (pad.width / 2 - 0.5), pad.topY + 0.1, DECK_CENTER_Z },
			size = { 1, 0.5, pad.maxZ - pad.deckMinZ },
			color = accent,
			material = "SmoothPlastic",
			canCollide = false,
			attributes = { Accent = true },
		})
	end

	-- No solid back wall any more, on request — just the fence (buildBackFence, the
	-- same rail/post language buildSideRailings already runs down the long edges,
	-- closing the back edge instead of a wall) and the anchor for the floating avatar
	-- plate high over the pad's centre (buildNamePlate; the plate is client-drawn).
	buildSideRailings(m, origin, { [flightSide(1)] = { { z0 = FOOT_GATE.z0, z1 = FOOT_GATE.z1, floor = 2 } } })
	buildBackFence(m, origin)
	capFencePosts(m:FindFirstChild("SideRailings"), accent)
	capFencePosts(m:FindFirstChild("BackFence"), accent)
	buildNamePlate(m, origin)

	-- No claim board and no entrance arch any more (the arch removed on request): whose
	-- plot this is reads from the avatar plate floating over the pad.

	-- Where this plot's owner respawns. Disabled until somebody owns it, so nobody
	-- ever lands on a stranger's stage. ExhibitService flips this on assignment.
	-- Fully invisible: there is no physical checkpoint pad any more, just the spawn
	-- point itself at the same spot the pad used to mark.
	-- The front strip (spawn, washer, bottle, treadmill) is built through `ground`, the
	-- same frame dropped to the grey path's height; the locker stands behind the hazard
	-- line, on the deck, so it keeps `origin`.
	-- STRIP_FORWARD: the strip's machines and spawn are written for the old -43 front and
	-- built 4 further out, the middle of the 8 the strip gained.
	local ground = origin * CFrame.new(0, -STRIP_DROP, -STRIP_FORWARD)
	local spawn = build(m, ground, {
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

	-- The +X machines and the -X locker moved in with the fences (STRIP_INSET).
	local plusIn = CFrame.new(-STRIP_INSET, 0, 0)
	local minusIn = CFrame.new(STRIP_INSET, 0, 0)
	-- THE CLEANSING STATION GOES AT THE STAGE END (on request, 2026-10-04). Written on the
	-- +X side, which is east on a north pad but west on a south one (turned 180), so a
	-- pad whose +X points away from the stage swaps the strip: the station and bottle
	-- turned 180 about their own centre onto the -X fence and the locker onto the +X one
	-- (each still backed onto its fence, still facing the aisle).
	-- THE BOTTLE TURNS WITH THE STATION, about the tub's centre, not its own: the pump
	-- tank stands off the tub's +Z face and the bottle off its -Z face, so turning only
	-- the station swung the tank straight onto the bottle's table. Turned as one, the
	-- bottle lands on the tub's other face and keeps the same reach to the wash spot.
	local stripFlip = math.cos(math.rad(center.facing)) < 0
	local shift = CFrame.new(STATION_SHIFT, 0, 0)
	local stationAt, lockerAt, bottleAt = plusIn * shift, minusIn, plusIn * shift
	if stripFlip then
		stationAt = flipAbout(STATION_CENTER.x - STRIP_INSET, STATION_CENTER.z) * plusIn * shift
		lockerAt = flipAbout(LOCKER.x + STRIP_INSET, LOCKER.z) * minusIn
		bottleAt = stationAt
	end
	buildCleansingStation(m, ground * stationAt, accent)
	buildQuarantineLocker(m, origin * lockerAt, index)
	buildFluidBottle(m, ground * bottleAt)
	Plots.ensureHosePad(m)

	buildBaseGlow(m, origin)

	-- Every floor above, and the sign that sells each one. All built; the ones this
	-- plot's owner has not bought are hidden at runtime (Plots.setFloors).
	for floor = 2, Floors.MAX do
		buildFloor(m, origin, index, floor, accent)
		buildFloorSign(m, origin, index, floor, accent)
	end
	hidePillarPosts(m)

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
	-- from the south wall round the back to the north one. The east walls are left
	-- dark.
	local rim = Instance.new("Folder")
	rim.Name = "RimLights"
	local c = Plots.CAMP
	local inset = 4
	local ex, wx, hz = c.eastX - inset, c.westX + inset, c.halfZ - inset
	local path = { { ex, -hz }, { wx, -hz }, { wx, hz }, { ex, hz } }
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
		`[build] Plots rebuilt — {Plots.COUNT} plots, {Floors.MAX} floors and `
			.. `{Plots.VISIBLE_SLOTS} stands each ({Floors.GROUND_SLOTS} free on the ground), `
			.. `{Plots.LOCKER_SLOTS}-tube quarantine locker each, `
			.. `{#row.Apron:GetChildren()} apron parts`
	)
	return row
end

return Plots
