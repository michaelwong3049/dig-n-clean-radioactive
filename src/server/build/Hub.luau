--!strict
--[[
	Hub.luau — the plaza at the middle of the world.

	    require(game.ServerScriptService.Server.build.Hub).rebuild()

	THE HUB IS A REST POCKET, AND THAT IS A CODE FACT, NOT A DECORATION.
	A player standing in no stage gets zero rads and 6x health regen
	(ExposureService). The plaza and every road leading off it are deliberately
	OUTSIDE all four stage rectangles, so "the paths are safe, the green is not" is
	true by construction and costs nothing to enforce. For a young audience that is
	the single most legible rule in the game, and it is free.

	THE PLOTS RING IT AS A SEMICIRCLE. Six pads on the exterior of a circle pulled
	toward Stage 1 (not centred on the plaza's own midpoint any more — see
	Plots.luau's own comment on RING_CENTER for why), each rotated to face the
	shop cluster at the centre. The eastern half is open — the plaza connects
	straight through to Stage 1 there, same as always — so the ring only occupies
	the western 180 degrees; you still walk out of the courtyard directly into
	the sludge. See Plots.luau for the actual circle math
	(Plots.RING_CENTER/RING_RADIUS/RING_ANGLES).

	NO CONNECTOR ROADS. The plaza used to be a fixed 160x160 square with paved strips
	running out to a plot spine and to the field. Per the requested layout (plots —
	shop area — radiation, directly touching, not places joined by roads), the plaza's
	footprint reaches its neighbours directly: its east edge lands exactly on Stage 1's
	west edge, and the pads sit flush against its other three. Zero gap, not a short
	one — `rectsOverlap` treats an exactly-shared edge as touching, not overlapping,
	so this is safe against the "no stage may overlap the plaza" check in
	`World.verify()`.

	IT USED TO BE 237x382, AND THAT WAS NOT A DESIGN DECISION. It was that deep for
	one reason: all six plots were a single column down the west side, and the plaza
	had been stretched in Z until it spanned the whole column so they could all border
	it. Ringing the plots removed that constraint, and the plaza went back to being
	sized by what is actually standing on it — the camp and the stalls occupy roughly
	110x120 — rather than by the length of something parked beside it. Went to 200x200
	next (a little under half the 237x382 area), then to the current 165x140 (see
	Hub.PLAZA below) once 200x200 turned out to still be carrying 40+ studs of dead
	space beyond the westmost stall's own footprint — walking distance for nothing.

	THE FLOOR IS A CHECKERBOARD, and it is not only this floor. `Hub.TILE_SIZE` below is
	the grid; `tileRect` and `groundSlab` are exported so the plot ring and the six
	player bases can lay the same board. The plaza and its apron wear it in zones
	resolved by one function, `Hub.groundPairAt`: grass on the apron and along the
	Camp -> Stage 1 border (GREEN_STRIP_DEPTH), an OCTAGONAL cream plaza centred on the
	plot ring (PLAZA_OCT_*, its diagonals laid true by split tiles) with a cream path out
	to each pad as part of the same floor (GATE_RECTS / GATE_DIAGONALS), and warm tan pavers
	edged with a darker kerb under the shop cluster (SHOP_ZONE); the bases wear it
	as a flat wooden deck a step above — one pattern, one grid, staying in register
	across the apron's own edges because the grid belongs to the plaza rather than to
	whoever is asking for tiles. All zones come out of the one tileRect pass, so it is
	one tile per square rather than boards laid on top of each other.

	IT HAS BEEN GREEN, GREY-SPINED, AND ALL CHARCOAL. A grey band started as a small
	inlaid pad (`eaffbc7`), was widened (`39df0b0`), run north/south onto the apron as
	a "spine" (`819ff28`), pushed west (`f27e670`), then flooded across the whole base
	as a near-flat charcoal (PR #143) that read as a car park from any height. The
	cartoon pass put the grass back around the plots and paved only the plaza, in
	light colours (PR #166); the paving was then made round (a staircase at every edge),
	then an octagon, centred on the plots, with a gate path out to each pad and warm
	pavers under the shops. The
	grass is Stage 1's own tinted green, so Stage 1's west edge
	(Scenery.buildStageCheckerboard) meets it with no seam at the x = 100 line.

	A PAD'S OWN BOARD IS THE ONE EXCEPTION, AND ONLY SINCE THE SEMICIRCLE. Both
	builders below take an optional `opts.origin` CFrame so a caller can tile a
	rectangle defined in ITS OWN local frame instead of always in world space —
	added because a pad's facing is no longer a multiple of 90 degrees, so its
	footprint is no longer axis-aligned in world space the way the grid math here
	assumes. A pad's tiles stay an exact 4x4 checkerboard, they just no longer
	phase-lock with the apron's grid across the shared edge the way a 90-degree pad
	could. See Plots.buildPlot.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Kit = require(script.Parent.Kit)
-- Hub otherwise requires only Kit (see Hub.PLAZA's own comment on why: Plots.luau
-- requires Hub, so Hub requiring Plots would be circular). Stages is safe -- it is
-- pure config, requires nothing under build/, and Scenery.luau already requires
-- both Hub and Stages together with no cycle. Needed for PLAZA_DARK/PLAZA_LIGHT
-- below.
local Stages = require(ReplicatedStorage.Shared.Config.Stages)

local Hub = {}
local BUILDER_SOURCE = "src/server/build/Hub.luau"
local BUILDER_VERSION = 24

local C = Kit.C
local build = Kit.build

--- The plaza/apron's own checkerboard, tinted to match Stage 1's ground exactly the
--- way it already visually promises to. Scenery.luau's buildStage1Checkerboard
--- starts ITS gradient at these two colours (Hub.PLAZA's own comment: "Stage 1's
--- checkerboard gradient now starting at the plaza's own tile colours") and then
--- bakes Stages.GROUND_OOZE_TINT into every tile uniformly, camp included in that
--- promise or not -- so leaving these two constants untinted would draw a colour
--- jump right at Stage 1's edge, exactly the seam the checkerboard rewrite was
--- built to avoid. Same formula, same weight, applied once here instead of at
--- every tile: Kit.blendHex(rawColour, Stage 1's own ooze.bright, the shared
--- tint weight).
local PLAZA_DARK = Kit.blendHex(C.plazaTileDark, Stages.get(1).ooze.bright, Stages.GROUND_OOZE_TINT)
local PLAZA_LIGHT = Kit.blendHex(C.plazaTileLight, Stages.get(1).ooze.bright, Stages.GROUND_OOZE_TINT)

--- The base floor, in zones on the one shared grid -- see `Hub.groundPairAt`.
---
--- CARTOON PASS, ON REQUEST. The whole base used to be a near-flat dark charcoal
--- (3D3F42/404246, ~5% apart) with a black/grey patch under the shops, and from any
--- height it read as a car park. It is now:
---
---   GRASS  -- the apron around and between the plots, the lawn outside the plaza octagon,
---             and the Camp -> Stage 1 border strip. This IS PLAZA_DARK/PLAZA_LIGHT (the
---             Stage-1-tinted green), so the ground meets Stage 1's own west edge with no
---             seam at all.
---   PATH   -- the plaza octagon (PLAZA_OCT_*) and the gate paths out to each pad: a warm
---             cream, ~6% apart so the checker reads.
---   PAVERS -- the shop cluster (SHOP_ZONE): warm tan pavers, edged by a one-tile darker
---             KERB so the square reads as paved rather than painted. Pale cool stone
---             (AEB6BD/BFC6CC) came first and read near-white from ground level: glare,
---             and the stalls' grey lumber (Kit.C.shopWood) melted into it. The fix is
---             hue, not just value -- cool grey stalls on a warm floor. A darker slate
---             was previewed alongside and still washed out; a terracotta patch before
---             that swallowed the orange awning.
---
--- Same studded board, same grid, same height everywhere -- only the palette changes
--- zone to zone, so footing is unchanged.
local PATH_DARK = "DCCBA3"
local PATH_LIGHT = "EADCBA"
local PAVER_DARK = "C9A37A"
local PAVER_LIGHT = "D4B088"
local KERB_DARK = "9C7A52"
local KERB_LIGHT = "A6835B"

--- How far WEST of Stage 1's edge (x = PLAZA.maxX = 100) the green strip reaches, on
--- request. Quantises to the 4-stud tile grid: `inGreenStrip` tests each tile's snapped
--- centre, so the green/cream boundary lands on a tile edge (x = 75 for 23), a ~25-stud
--- band in practice.
---
--- FULL HEIGHT, NOT +/-85 ANY MORE. The strip used to stop at Stage 1's own half-width
--- (the length of the Camp -> Stage 1 hazard line), which only ever mattered inside the
--- plaza's +/-70 rectangle. The plaza octagon reaches z = +/-98 along this line, so a
--- z-limited strip would let a cream notch poke out past the line's ends, beside the
--- corridor walls.
local GREEN_STRIP_DEPTH = 23

-- ── Layout ────────────────────────────────────────────────────────────────────
-- Everything here is world space. The plaza's walking surface is at Y = 0, and
-- the stage plate sits 1.5 studs lower so you step DOWN into the sludge. See
-- Config/Stages.SURFACE_Y.
--
-- THIS RECTANGLE IS NOW THE SOURCE, NOT THE FOLLOWER. It used to be hand-synced to
-- Plots.luau's constants through a comment, with four numbers that had to be edited
-- together and nothing to catch it if they were not. That is backwards: the plaza is
-- the thing the map is arranged around. Plots.luau requires this file and derives its
-- pad ring from these four numbers, so moving the plaza moves the plots with it and
-- there is no pair to keep in step. (Hub requires only Kit, so that direction is not
-- circular — do not add a require of Plots here or it becomes one.)
--
--   maxX = 100  is the one number NOT free to move: it is Stage 1's west edge
--               (Stages.get(1).center[1] - size[1]/2), and the plaza touching the
--               field directly is the whole point of the layout.
--
-- NO LONGER SYMMETRIC ABOUT WORLD X=0, AND THAT IS FINE. It used to be, and the old
-- guidance here ("shrink by moving maxX, never minX") assumed that could stay true —
-- it cannot, once maxX is pinned to Stage 1 (above) and the west side is the only one
-- left to compact. COMPACTED, PLAN: "a lot of walking to the stages" — the old 200x200
-- square left 40+ studs of dead space beyond the westmost stall's own footprint doing
-- nothing but padding the walk. minX moved -100 -> -65 (35 studs off the west edge);
-- minZ/maxZ moved -100/100 -> -70/70 for the same reason on the other two open sides.
--
-- What actually matters is not world-X=0, it's the RECTANGLE'S OWN midpoint — camp
-- floor, the three stalls, the outfitter bench and the plot ring (derived from this
-- rectangle) all still have to agree on where "centre" is, or the ring reads out of
-- line with the shops it faces, same failure the old comment described (at minX=-80,
-- centre landed on x=10 and the pads sat ten studs off). The fix that generalises: the
-- midpoint moved from x=0 to x=17.5 (`(minX+maxX)/2`), and everything hardcoded
-- against the old centre — Hub.CAMP_ORIGIN below, Shops.luau's STALLS/OUTFITTER — moved
-- the same +17.5, so they are exactly as centred on the new, smaller rectangle as they
-- were on the old one.
-- topY MATCHES Stages.SURFACE_Y (-1.5), ON REQUEST. The plaza used to sit at Y=0, a
-- full 1.5 studs above the stage plates -- a deliberate "step down into the sludge"
-- cue, per Stages.SURFACE_Y's own comment. That cue is gone now, in favour of camp
-- flowing into Stage 1 at one level -- reinforced by Stage 1's checkerboard gradient
-- now starting at the plaza's own tile colours (Scenery.luau's
-- buildStage1Checkerboard). Both cues (colour AND height) were pointing the same
-- direction anyway; this just stops fighting the other one.
Hub.PLAZA = { minX = -65, maxX = 100, minZ = -70, maxZ = 70, thickness = 8, topY = -1.5 }
Hub.CAMP_ORIGIN = CFrame.new(17.5, -0.6, 0) -- the camp's datum; its spawn lands on Y = 0

--- THE PLOT RING'S CENTRE AND BEARINGS ARE DEFINED HERE, not in Plots.luau, because the
--- floor below draws on both (the plaza octagon and its gate paths) and Hub cannot require
--- Plots -- Plots requires Hub. Plots re-exports them unchanged (`Plots.RING_CENTER`, its
--- local RING_ANGLES) and keeps the notes on why they are these numbers.
---
--- SHOP_CLUSTER_EAST_REACH / FIELD_CLEARANCE are historical: they placed the centre off an
--- old eastmost stall and are left as they were so the ring stays put -- see Plots.luau.
local SHOP_CLUSTER_EAST_REACH = 53
local FIELD_CLEARANCE = 15
Hub.RING_CENTER = {
	x = Hub.PLAZA.maxX - SHOP_CLUSTER_EAST_REACH - FIELD_CLEARANCE,
	z = (Hub.PLAZA.minZ + Hub.PLAZA.maxZ) / 2,
}
Hub.PLOT_BEARINGS = { 185, 219, 253, 287, 321, 355 }

--- THE PLAZA IS AN OCTAGON, centred on the plot ring so the pads stand around it at an
--- even distance. It has been a rectangle (a rug in a round room: near-touching the west
--- pads, a lawn away from the rest), then a circle, r 112 and then 98 -- but a circle on a
--- 4-stud grid is a ragged staircase all the way round. An octagon's four axis sides fall
--- straight on tile lines, and its four diagonals are laid true by splitting every cell
--- they cross into two flat triangles (`Hub.groundSplitAt`, `buildSplitTile`).
---
--- CENTRED ON (33, 0), NOT RING_CENTER's (32, 0): the nearest cell centre (cell centres
--- sit at PLAZA.minX + 2 + 4k in x, PLAZA.minZ + 2 + 4k in z). Only from a cell centre do
--- the axis sides land on tile lines AND the diagonals run exactly corner to corner
--- through the cells they cross. A stud off the ring's true centre does not show.
---
--- HALF (the axis apothem) is 4k + 2 so 33 +/- HALF is a tile line -- the west side IS the
--- plaza rectangle's own west edge, x = -65. DIAG (|dx| + |dz| on a diagonal) is a
--- multiple of 4, so the diagonal passes through cell corners. 98 / 140 is the smallest
--- near-regular pair (98 * sqrt 2 = 138.6) that still rings the shop square with a tile
--- of cream: its south-west corner, 136 out on the diagonal, is the one that binds. The
--- east end needs no diagonals: the north and south sides run to dx = 42 (x = 75), exactly
--- where the green strip starts, so that strip's edge closes the shape.
---
--- FLOOR ONLY. Hub.PLAZA stays the rectangle for the slab, World.verify()'s stage-overlap
--- check and everything else that reads it; the octagon only decides which tiles are
--- cream. It reaches past that rectangle north and south onto apron tiles, which is fine:
--- the apron lays its tiles through the same resolver.
local PLAZA_OCT_X = 33
local PLAZA_OCT_Z = 0
local PLAZA_OCT_HALF = 98
local PLAZA_OCT_DIAG = 140

--- THE PLAZA FLOOR STANDS PROUD OF THE LAWN, on request -- the user liked the old raised
--- gate strips' look and asked for the middle floor to match it. Every floor tile (cream,
--- pavers, kerb, the gate paths, and the floor half of a split cell) is laid this much
--- above PLAZA.topY; the grass stays on it. So does everything built ON the plaza: Shops'
--- `facingOrigin` and BaseCamp's Trader read this constant, and the respawn anchor adds
--- it, so nothing sinks into the raised floor.
Hub.PLAZA_LIFT = 0.15

--- THE GATE PATHS ARE PART OF THIS FLOOR, on request. They were separate strips laid
--- along each pad's own bearing, a hair below the plaza so the two would not z-fight where
--- a strip started inside the octagon -- and that step showed. Now each path runs square
--- off the octagon side that faces its pad, straight out to the pad's front and on under
--- it, so it meets the plaza with no seam: same tiles, same checker, same height. Running
--- square is what keeps every edge on the grid -- the north, south and west paths' edges
--- sit on tile lines, the two diagonal paths' on 45-degree lines through tile corners,
--- laid true by the same split cells as the octagon's own diagonals (floorCover).
---
--- Each is centred on its pad's front (RING_CENTER + 122 along the pad's bearing),
--- snapped to that grid -- within ~2 studs -- and runs on under the pad, whose slab hides
--- the end, far enough to meet the pad's front across its whole width. 16 wide (the
--- diagonal pair ~17, the nearest width their corner lines allow). Hand-placed, like
--- SHOP_ZONE: move them by hand with Plots.RING_RADIUS / PLOT_BEARINGS.
local GATE_RECTS = {
	{ minX = 15, maxX = 31, minZ = -130, maxZ = -98 }, -- Plot1 (bearing 185): due south off the south side
	{ minX = 15, maxX = 31, minZ = 98, maxZ = 130 }, -- Plot6 (355): due north off the north side
	{ minX = -97, maxX = -65, minZ = -42, maxZ = -26 }, -- Plot3 (253): due west off the west side
	{ minX = -97, maxX = -65, minZ = 26, maxZ = 42 }, -- Plot4 (287): due west
}

--- The two diagonal paths, in 45-degree coordinates: `across` = x + zSign * z runs across
--- the path, `along` = x - zSign * z runs along it (more negative is further out).
---
--- THE ACROSS EDGES ARE 1 MOD 8, not merely 1 mod 4 like every corner line. With the
--- along lines at 5 mod 8 (the octagon's diagonal at -107, the end at -155), that puts
--- every place a side meets an end exactly on a tile corner. Meeting at a cell centre
--- instead would leave a cell three quarters floor, which two triangles cannot lay.
local GATE_DIAGONALS = {
	{ zSign = -1, across = { 41, 65 }, along = { -155, -107 } }, -- Plot2 (219): south-west, off the SW diagonal
	{ zSign = 1, across = { 41, 65 }, along = { -155, -107 } }, -- Plot5 (321): north-west, off the NW diagonal
}

--- Is the tile at (x, z) in the green Camp -> Stage 1 border strip? GREEN_STRIP_DEPTH
--- studs west from Stage 1's edge (x = PLAZA.maxX), at any z. It keeps the plaza octagon
--- back from the field, so the walk out of camp still crosses grass before the yellow
--- hazard line Scenery.buildStageBorderLines draws on that seam.
---
--- A plain half-plane test: the strip's edge follows the tile grid straight, no easing.
local function inGreenStrip(x: number): boolean
	return x >= Hub.PLAZA.maxX - GREEN_STRIP_DEPTH
end

--- A rectangle over the plaza covering the shop cluster — the three tool stalls,
--- the Outfitter and the Trader kiosk (build/Shops.luau, build/BaseCamp.luau) —
--- with a few studs of margin on every side. Hand-measured off their current
--- positions (Shops.luau's `at` values are themselves hand-placed now, not
--- derived — see that file's header) rather than computed live: there is no
--- single formula covering four freely-placed stalls plus a kiosk in a
--- different file, so this rectangle has to move by hand whenever the shop
--- cluster does, the same way BaseCamp.luau's Trader offset already does.
---
--- Moved 20 east (exactly 5 tiles, so the kerb lands on the same grid phase) with the
--- whole cluster, to centre it in the plaza's visible cream: the plaza's own
--- centre (RING_CENTER.x = 32) is out of reach, since centring there would run the
--- cluster's east end onto the green strip at x = 75. maxX 65 leaves two cream tiles
--- before that strip.
local SHOP_ZONE = { minX = -45, maxX = 65, minZ = -55, maxZ = 47 }

--- Is the tile at (x, z) under the shop cluster, and so painted pavers rather than the
--- cream path? A plain rectangle test. `Hub.groundPairAt` asks it inside the plaza
--- octagon, for plaza and apron tiles alike.
function Hub.inShopFloor(x: number, z: number): boolean
	return x >= SHOP_ZONE.minX and x <= SHOP_ZONE.maxX and z >= SHOP_ZONE.minZ and z <= SHOP_ZONE.maxZ
end

--- Is the shop-floor tile at (x, z) on the square's outermost ring of tiles, and so
--- painted the kerb pair rather than the pavers? True when one tile's step in any
--- direction leaves SHOP_ZONE.
local function inShopKerb(x: number, z: number): boolean
	local t = Hub.TILE_SIZE
	return not (
		Hub.inShopFloor(x - t, z)
		and Hub.inShopFloor(x + t, z)
		and Hub.inShopFloor(x, z - t)
		and Hub.inShopFloor(x, z + t)
	)
end

--- The centre of the grid cell holding (x, z). Every zone test reads a cell's centre --
--- see groundPairAt's note on snapping.
local function cellCentre(x: number, z: number): (number, number)
	local p, t = Hub.PLAZA, Hub.TILE_SIZE
	return p.minX + (math.floor((x - p.minX) / t) + 0.5) * t, p.minZ + (math.floor((z - p.minZ) / t) + 0.5) * t
end

--- Is the point (x, z) on the plaza floor -- the octagon, or one of its gate paths? A pure
--- shape test with no grid in it; floorCover turns it into whole and split cells.
local function insideFloor(x: number, z: number): boolean
	local ax, az = math.abs(x - PLAZA_OCT_X), math.abs(z - PLAZA_OCT_Z)
	if ax <= PLAZA_OCT_HALF and az <= PLAZA_OCT_HALF and ax + az <= PLAZA_OCT_DIAG then
		return true
	end
	for _, r in GATE_RECTS do
		if x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ then
			return true
		end
	end
	for _, d in GATE_DIAGONALS do
		local across, along = x + d.zSign * z, x - d.zSign * z
		if across >= d.across[1] and across <= d.across[2] and along >= d.along[1] and along <= d.along[2] then
			return true
		end
	end
	return false
end

--- How the plaza floor covers the cell centred at (cx, cz): "full", "none", or "split"
--- plus the corner (sx, sz) its LAWN half holds (the floor half holds the opposite one).
---
--- Every floor edge is a tile line or a 45-degree line through tile corners, so a cell is
--- only ever whole or cut corner to corner -- and the four triangles its two diagonals
--- make say which. One sample sits at each triangle's centroid, a third of a tile off the
--- centre, where no edge can pass; two neighbouring triangles on the floor mean that half
--- is floor.
local function floorCover(cx: number, cz: number): (string, number, number)
	local q = Hub.TILE_SIZE / 3
	local up, right = insideFloor(cx, cz + q), insideFloor(cx + q, cz)
	local down, left = insideFloor(cx, cz - q), insideFloor(cx - q, cz)
	if up and right and down and left then
		return "full", 0, 0
	elseif not (up or right or down or left) then
		return "none", 0, 0
	elseif up and right and not (down or left) then
		return "split", -1, -1 -- the floor holds the (+x, +z) corner, so the lawn (-x, -z)
	elseif down and left and not (up or right) then
		return "split", 1, 1
	elseif up and left and not (down or right) then
		return "split", 1, -1
	elseif down and right and not (up or left) then
		return "split", -1, 1
	end
	-- Three quarters floor, or cut both ways: two triangles cannot lay it, and the shapes
	-- above are placed so no such cell occurs (see GATE_DIAGONALS). Round to the majority.
	local n = (if up then 1 else 0) + (if right then 1 else 0) + (if down then 1 else 0) + (if left then 1 else 0)
	return if n > 2 then "full" else "none", 0, 0
end

--- The (dark, light) pair for the base-floor tile centred at (x, z): grass in the
--- Camp -> Stage 1 strip; on the plaza floor (the octagon and its gate paths --
--- insideFloor), kerb-edged pavers under the shops and cream everywhere else; grass
--- everywhere else, including the cells a floor edge cuts in half -- a builder asks
--- groundSplitAt about those first. See PATH_DARK's comment for the palette.
---
--- ONE RESOLVER FOR EVERY BASE-FLOOR TILE, WHICHEVER BUILDER LAYS IT, AND THAT IS
--- LOAD-BEARING. The apron deliberately lays a ring of tiles coincident with the
--- plaza's own edge tiles (Plots' PLAZA_SKIP_MARGIN -- it closes a one-stud seam),
--- same grid, same height. While both floors were one charcoal that doubling was
--- invisible; with grass on one and cream on the other it z-fought into a stair-step
--- along every plaza edge (seen live: 183 doubled tiles). Resolving by position means
--- a doubled tile always takes the plaza's own colour, so it is invisible again.
---
--- IT SNAPS TO THE GRID CELL FIRST, for the same reason. `tileRect` passes each tile's
--- own centre, and an edge tile clipped to its rectangle has an off-grid one; two
--- builders clipping differently could then resolve one cell two ways at a zone edge.
--- Every test below reads the cell's centre instead, so a cell has exactly one colour.
---
--- THE THIRD RETURN IS THE TILE'S LIFT above PLAZA.topY: Hub.PLAZA_LIFT for every plaza
--- tile (cream, pavers, kerb), 0 for the lawn. tileRect lays the tile's top there.
function Hub.groundPairAt(x: number, z: number): (string, string, number)
	local cx, cz = cellCentre(x, z)
	if inGreenStrip(cx) or floorCover(cx, cz) ~= "full" then
		return PLAZA_DARK, PLAZA_LIGHT, 0
	end
	if not Hub.inShopFloor(cx, cz) then
		return PATH_DARK, PATH_LIGHT, Hub.PLAZA_LIFT
	elseif inShopKerb(cx, cz) then
		return KERB_DARK, KERB_LIGHT, Hub.PLAZA_LIFT
	end
	return PAVER_DARK, PAVER_LIGHT, Hub.PLAZA_LIFT
end

export type GroundSplit = {
	inner: { string }, -- (dark, light) of the floor half
	outer: { string }, -- (dark, light) of the lawn half
	innerLift: number, -- the floor half stands Hub.PLAZA_LIFT proud; the lawn half does not
	sx: number, -- the corner the lawn half holds, as signs (the floor half holds the opposite)
	sz: number,
}

--- For a cell a 45-degree floor edge -- an octagon diagonal, or a diagonal gate path's
--- side -- cuts in half, corner to corner: the two halves' pairs and which way the cut
--- faces (see GroundSplit). nil for every whole cell. Resolved from the same snapped cell
--- centre as groundPairAt, so the plaza and the apron -- which both lay the cells along
--- the plaza rectangle's edge -- split a doubled cell identically. The shop square sits
--- well inside the octagon, so a floor half is always cream and a lawn half always grass.
function Hub.groundSplitAt(x: number, z: number): GroundSplit?
	local cx, cz = cellCentre(x, z)
	if inGreenStrip(cx) then
		return nil
	end
	local cover, sx, sz = floorCover(cx, cz)
	if cover ~= "split" then
		return nil
	end
	return {
		inner = { PATH_DARK, PATH_LIGHT },
		outer = { PLAZA_DARK, PLAZA_LIGHT },
		innerLift = Hub.PLAZA_LIFT,
		sx = sx,
		sz = sz,
	}
end

-- ── The floor ─────────────────────────────────────────────────────────────────
-- THE PLAZA IS A CHECKERBOARD OF STUDDED TILES, not one flat slab. A single colour
-- reads as a void with things parked on it: nothing tells you how big the courtyard
-- is or how far you have walked across it. A regular grid does both for free, and
-- classic Roblox studs are the cheapest way to get a surface that catches the light
-- instead of sitting there as a matte rectangle.
--
-- TILE_SIZE IS A STUD SIZE, NOT A COUNT PER AXIS, and it is the one number to turn
-- when the pattern reads wrong. 4 was chosen (up from 3) on request, kept as a
-- direct size rather than a divisor-of-the-plaza count: the plaza is 165 studs wide
-- (PLAZA.maxX - PLAZA.minX), and 165 isn't a multiple of 4, so the west edge column
-- is a partial-width tile clipped to the plaza's real edge — the same clipping
-- `tileRect` already does at any rectangle boundary that doesn't land on a tile
-- line (see PLAZA_SKIP_MARGIN / PAD_SKIP_INSET in Plots.luau, which scale with
-- this constant for the same reason).
--
-- Studs are laid out on a one-per-stud pitch centred on each face, so a tile whose
-- side is a whole number of studs comes out exactly like the classic brick.
--
-- THE TILES ARE A CAP LAYER OVER A STRUCTURAL SLAB, rather than thousands of
-- full-thickness blocks. Two reasons: the plaza's exposed side stays one clean dark
-- face instead of a many-toothed checkered stripe, and the slab is what everything
-- actually stands on. The slab's top is recessed by exactly CAP, so the walking
-- surface is still PLAZA.topY on the lawn. The plaza octagon's tiles stand
-- Hub.PLAZA_LIFT above it (see that constant), and everything on the plaza stands on that.
--
-- THE BASE FLOOR'S ZONES ARE PAINT, NOT GEOMETRY -- see PATH_DARK, Hub.groundPairAt and
-- the `ground` flag on TileOpts. Grass, cream path and shop stone are the same cap tiles
-- in different pairs; footing and height are the plaza's everywhere. The plaza paints
-- its own slab (buildPlaza); the apron paints the rest of the disc (Plots.buildApron) on
-- the one shared grid, through the one shared resolver.
Hub.TILE_SIZE = 4
local CAP = 0.4

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

--- What to lay, and where to lay its top face.
---
--- ALL FOUR ARE OPTIONAL AND ALL FOUR DEFAULT TO THE PLAZA. That is the point: a
--- caller that wants the plaza's board asks for nothing, and a caller that wants the
--- same board in a different palette at a different height overrides only what
--- differs. The tile SIZE and the colour PARITY are deliberately not in here —
--- they come from the plaza's grid for every caller, which is what keeps six plot
--- pads, the apron and the plaza reading as one board rather than eight.
export type TileOpts = {
	topY: number?, -- default PLAZA.topY
	dark: string?, -- default PLAZA_DARK (C.plazaTileDark, tinted to match Stage 1)
	light: string?, -- default PLAZA_LIGHT (C.plazaTileLight, tinted to match Stage 1)
	skip: ((x: number, z: number) -> boolean)?,
	-- Per-tile colour override, for a board whose colour is itself a gradient (Stage
	-- 1's checkerboard) rather than one fixed pair. Called with each tile's own
	-- centre, same as `skip`; returns that ONE tile's (dark, light), which the
	-- existing parity below still picks between exactly as it does for the fixed
	-- case. `dark`/`light` above are simply never read when this is set. Kept
	-- optional and additive so every existing caller (the plaza itself, Plots'
	-- pads/apron) is untouched -- none of them pass this.
	colorAt: ((x: number, z: number) -> (string, string))?,
	-- Paint the base floor's zones (grass / cream path / stone under the shops) from each
	-- tile's own centre via `Hub.groundPairAt`. Applied AFTER `colorAt`, so a gradient
	-- board (Stage 1's, which never sets this) is untouched. The plaza and the apron both
	-- set this, and they must keep sharing the one resolver -- see `groundPairAt` on the
	-- doubled edge tiles.
	ground: boolean?,
	origin: CFrame?, -- default identity -- see this type's own comment above
}

--- The structural slab a tiled rectangle rides on: same footprint, recessed by
--- exactly the cap thickness so the tiles laid on it top out at PLAZA.topY.
---
--- Exported for the same reason `tileRect` is. Plots.luau needs one under the ring
--- it fills, and an apron that is only the 0.4 of the tile layer reads as a wafer
--- bridging two 3-thick pads rather than as ground you are standing on.
--- `thickness` is the slab's own, not the plaza's, because a plot pad is 3 studs
--- thick and the plaza is 8. Everything else comes from `opts` exactly as it does
--- for `tileRect`, so a slab and the tiles laid on it cannot disagree about where
--- the surface is.
function Hub.groundSlab(parent: Instance, rect: Rect, name: string, thickness: number?, opts: TileOpts?): BasePart
	local o = opts or {}
	local topY = o.topY or Hub.PLAZA.topY
	local deep = thickness or Hub.PLAZA.thickness
	return build(parent, o.origin or CFrame.new(0, 0, 0), {
		name = name,
		pos = {
			(rect.minX + rect.maxX) / 2,
			topY - CAP - deep / 2,
			(rect.minZ + rect.maxZ) / 2,
		},
		size = { rect.maxX - rect.minX, deep, rect.maxZ - rect.minZ },
		color = o.dark or PLAZA_DARK,
		material = "SmoothPlastic",
	})
end

--- A split cell (Hub.groundSplitAt) is laid as two flat triangles instead of one square
--- tile: the floor half and the lawn half, meeting exactly on a 45-degree floor edge (an
--- octagon diagonal or a diagonal gate path's side).
--- Each is a WedgePart on its side -- rolled 90 degrees about local Z so its triangular
--- face (local +X) is the top, CAP thick like every other cap tile. Unturned, that
--- triangle holds the cell's (+x, +z) corner; SPLIT_YAW turns it onto whichever corner
--- a half needs. The plaza half stands `innerLift` proud, like every plaza tile.
---
--- STUDS ON THE TOP FACE ONLY, set after the build rather than via Kit's `studs` (which
--- studs every face). The raised plaza half's cut face is a visible sliver along the
--- diagonal, and studs on a sliver that thin read as a dotted line.
local SPLIT_ROLL = CFrame.Angles(0, 0, math.pi / 2)
local SPLIT_YAW = {
	["1,1"] = 0,
	["1,-1"] = math.pi / 2,
	["-1,-1"] = math.pi,
	["-1,1"] = -math.pi / 2,
}
local SPLIT_SMOOTH_FACES = { "TopSurface", "BottomSurface", "LeftSurface", "FrontSurface", "BackSurface" }

local function buildSplitTile(parent: Instance, origin: CFrame, cx: number, topY: number, cz: number, split: GroundSplit, isDark: boolean)
	local pick = if isDark then 1 else 2
	for _, half in {
		{ sx = -split.sx, sz = -split.sz, pair = split.inner, lift = split.innerLift },
		{ sx = split.sx, sz = split.sz, pair = split.outer, lift = 0 },
	} do
		local part = build(parent, origin, {
			name = "Tile",
			class = "WedgePart",
			pos = { cx, topY + half.lift - CAP / 2, cz },
			size = { CAP, Hub.TILE_SIZE, Hub.TILE_SIZE },
			rot = CFrame.Angles(0, SPLIT_YAW[`{half.sx},{half.sz}`], 0) * SPLIT_ROLL,
			color = half.pair[pick],
			material = "Plastic",
		})
		for _, face in SPLIT_SMOOTH_FACES do
			(part :: any)[face] = Enum.SurfaceType.Smooth
		end
		part.RightSurface = Enum.SurfaceType.Studs -- local +X, rolled up to be the top
	end
end

--- Tile one rectangle of ground with the plaza's checkerboard. Returns the count.
---
--- THE GRID IS GLOBAL, NOT PER-RECTANGLE. Both the tile size and the colour parity
--- are derived from PLAZA's own corner, so a rectangle tiled anywhere in the world
--- lands on the same board as the plaza: the pattern runs straight across the seam
--- between them instead of restarting and doubling a row of one colour. That is the
--- whole reason this is exported rather than private — Plots.luau fills the gaps
--- between the six bases with it, and those gaps have to look like the same floor
--- continuing, not a patch laid over a hole.
---
--- RECTANGLES DO NOT HAVE TO FALL ON TILE BOUNDARIES, and the ring around the plaza
--- does not: its edges come from pad sizes that have nothing to do with the tile's 3
--- studs. Edge
--- tiles are CLIPPED to the rectangle rather than allowed to overhang it. That is not
--- fussiness — the ring's east edge is Stage 1's west edge, and one tile of overhang
--- there would put walkable, zero-rad floor inside the radioactive field.
---
--- `opts.skip` is called with each tile's centre; returning true drops that tile.
--- Plots uses it to punch its six pads out of the ring. A tile straddling a pad edge
--- is KEPT, and ends up buried inside the pad — the pad is 3 studs thick with its top
--- 1.5 above this layer, so it swallows the overlap completely.
---
--- `opts.topY`, `opts.dark` and `opts.light` are how the plot pads wear this board in
--- their own colours a step above the plaza's. For a `rect` given in world space
--- (every caller except a pad's own tiles, see `opts.origin` below) the GRID is
--- still the plaza's, so walking off e.g. the apron onto ground built the same way
--- keeps the tiles in register, one step down and in a different palette.
---
--- `opts.origin` (default identity) lets a caller give `rect` in ITS OWN local
--- frame instead of world space — every part `build` places still goes through
--- `origin`, same as everywhere else in this file. Added for pads on the
--- semicircular ring, whose facing is no longer a multiple of 90 degrees: at an
--- arbitrary yaw a pad's true footprint is a rotated rectangle, not the
--- axis-aligned one this grid math otherwise assumes, so tiling it in world space
--- would tile a diamond of excess area outside the pad. The one cost: a pad tiled
--- this way is still an exact 3x3 checkerboard, it just no longer phase-locks
--- with the apron's grid across their shared edge — only possible at 90-degree
--- multiples. See Plots.buildPlot.
---
--- Studs are the look, and they only render on Plastic — the plaza's old Pavement
--- swallowed them completely, which is why every other surface in this world is
--- smooth. TopSurface is already Studs on a fresh Part, so there is nothing to set.
function Hub.tileRect(parent: Instance, rect: Rect, opts: TileOpts?): number
	local p = Hub.PLAZA
	local o = opts or {}
	local topY = o.topY or p.topY
	local dark = o.dark or PLAZA_DARK
	local light = o.light or PLAZA_LIGHT
	local skip = o.skip
	local colorAt = o.colorAt
	local groundOverlay = o.ground

	local origin = o.origin or CFrame.new(0, 0, 0)
	local size = Hub.TILE_SIZE

	local built = 0
	local ix0 = math.floor((rect.minX - p.minX) / size)
	local iz0 = math.floor((rect.minZ - p.minZ) / size)

	for ix = ix0, math.ceil((rect.maxX - p.minX) / size) - 1 do
		local x0 = math.max(p.minX + ix * size, rect.minX)
		local x1 = math.min(p.minX + (ix + 1) * size, rect.maxX)
		if x1 - x0 < 1e-3 then
			continue -- the rectangle's edge landed on this tile's own edge
		end

		for iz = iz0, math.ceil((rect.maxZ - p.minZ) / size) - 1 do
			local z0 = math.max(p.minZ + iz * size, rect.minZ)
			local z1 = math.min(p.minZ + (iz + 1) * size, rect.maxZ)
			if z1 - z0 < 1e-3 then
				continue
			end

			local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
			if skip and skip(cx, cz) then
				continue
			end

			local tileDark, tileLight = dark, light
			local tileTop = topY
			if colorAt then
				tileDark, tileLight = colorAt(cx, cz)
			end
			if groundOverlay then
				-- A whole cell a 45-degree floor edge cuts in half goes down as two
				-- triangles (buildSplitTile). A clipped one could not be halved on the
				-- diagonal, so it keeps groundPairAt's lawn colour -- none exist at the
				-- current numbers, since every diagonal cell is a whole one.
				local split = Hub.groundSplitAt(cx, cz)
				if split and x1 - x0 == size and z1 - z0 == size then
					buildSplitTile(parent, origin, cx, topY, cz, split, (ix + iz) % 2 == 0)
					built += 2
					continue
				end
				local lift
				tileDark, tileLight, lift = Hub.groundPairAt(cx, cz)
				tileTop = topY + lift
			end

			build(parent, origin, {
				name = "Tile",
				pos = { cx, tileTop - CAP / 2, cz },
				size = { x1 - x0, CAP, z1 - z0 },
				-- Parity off the GLOBAL index, never the loop counter: ix already
				-- counts from the plaza's corner, so a rectangle out at the plot ring
				-- inherits the phase instead of starting its own.
				color = if (ix + iz) % 2 == 0 then tileDark else tileLight,
				material = "Plastic",
			})
			built += 1
		end
	end

	return built
end

local function buildPlaza(hub: Model)
	local p = Hub.PLAZA

	Hub.groundSlab(hub, p, "Plaza", p.thickness)

	-- Foldered because thousands of siblings (one per tile) makes the Hub model
	-- unopenable in the explorer, and every one of them is the same decorative cap.
	-- The handful of parts that actually matter stay visible next to the folder
	-- instead of buried in it.
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"

	-- The board is one call: `ground = true` paints every tile from `Hub.groundPairAt`
	-- by its own centre -- stone under the shops, cream on the rest, grass in the
	-- Camp -> Stage 1 strip -- on the same grid in one pass (not tileRects laid on top of
	-- each other), so there is one tile per square and the checker parity carries
	-- straight through every zone edge. Plots.buildApron makes the identical call over
	-- the apron disc, so the grass runs unbroken across the plaza/apron seam.
	Hub.tileRect(tiles, p, { ground = true })
	tiles.Parent = hub

	-- NO RIM ON ANY SIDE ANY MORE. Three cream strips used to run along the north,
	-- south and west edges, there for one reason: so the plaza edge read as an edge
	-- from ground level rather than as a floor that stopped. That reason expired when
	-- Plots.luau started tiling the ring around it — the floor no longer stops at
	-- those three edges, it continues into the apron on the same board, and the rim
	-- had turned into a bright seam drawn across the middle of a continuous surface.
	--
	-- The east edge never had one, for a version of the same argument: it butts into
	-- the stage plate, and a rim there would draw a false seam across the boundary that
	-- is supposed to read as continuous ground. All four edges agree now.
end

--- THE BLACKOUT ANCHOR — see ExposureService.baseCampCFrame.
---
--- This is a named part, not a SpawnLocation, and the distinction matters. The old
--- lookup was Workspace:FindFirstChildWhichIsA("SpawnLocation"), which searches
--- DIRECT CHILDREN ONLY — and BaseCamp parents its spawn inside the camp model, so
--- the search failed and fell through to a hardcoded CFrame.new(0, 8, 0). With the
--- old layout that point was inside Stage 1: blacking out teleported you into the
--- radioactive field. Making it a search over a class that now has seven instances
--- in the world would have replaced one arbitrary answer with another.
---
--- It used to sit ON the camp's shower grate, so you woke up mid-flush — a
--- relief beat instead of a punishment one. The shower moved to a per-base
--- cleansing station on every plot (see Plots.buildCleansingStation) and isn't
--- at camp any more, so that instant flush is gone: a blacked-out player now
--- lands here with whatever exposure they had, same as anyone else who's just
--- standing in a zero-rad stage. Base camp is still "no stage" (zero rads, 6x
--- health regen per ExposureService), so exposure still drains here — just on
--- the normal passive curve, not an instant reset.
local function buildSpawns(hub: Model)
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"

	-- (17.5, 0) — the plaza midpoint (Shops.luau's PLAZA_MID). The shop cluster's
	-- two rows (Shops.luau's STALLS + OUTFITTER, plus BaseCamp's Trader) run
	-- east-west either side of it, so a player waking up here stands in the open
	-- aisle between the storefronts. Nothing is built on this point.
	local grate = Hub.CAMP_ORIGIN * CFrame.new(0, 0.75, 0)
	build(spawns, CFrame.new(0, 0, 0), {
		name = "RespawnAnchor",
		pos = { grate.X, Hub.PLAZA.topY + Hub.PLAZA_LIFT + 0.5, grate.Z }, -- on the raised plaza floor
		size = { 4, 1, 4 },
		color = C.cyan,
		material = "SmoothPlastic",
		transparency = 1,
		canCollide = false,
	})

	spawns.Parent = hub
end

local function createHub(): Model
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	Kit.stamp(hub, BUILDER_SOURCE, BUILDER_VERSION)

	buildPlaza(hub)
	buildSpawns(hub)

	return hub
end

function Hub.build(parent: Instance?): Model
	local hub = createHub()
	hub.Parent = parent or Workspace
	return hub
end

function Hub.rebuild(parent: Instance?): Model
	local hub = Kit.swap("Hub", createHub, parent) :: Model
	print(`[build] Hub rebuilt — {#hub:GetDescendants()} descendants`)
	return hub
end

return Hub
