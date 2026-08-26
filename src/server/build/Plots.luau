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
	the shop cluster and Zone 1) is the connector, so the ring is open there and
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
	    │              CLEANSING               │
	    │  [stand]                   [stand]   │
	    │  [stand]                   [stand]   │
	    │  [stand]         .                   │
	    │  [stand]                   [stand]   │
	    │                                       │
	    └─────────────────────────────────────┘

	Eight stands, four per side, in two flanking columns — `slotOffset` pairs
	them off row by row (slot 1 = left row 1, slot 2 = right row 1, slot 3 = left
	row 2, ...) rather than filling a centred grid, and the cleansing station
	moved from the pad's back-third to right up near the back wall so it reads
	as the "top" of the base the sketch asks for.

	SLOTS: 3 UNLOCKED, 8 BUILT, 40 ADDRESSABLE.
	Tuning.EXHIBIT_STARTING_SLOTS is 3 and EXHIBIT_MAX_SLOTS is 40; VISIBLE_SLOTS
	is the 8 the sketch actually shows. Locked stands are the visible form of
	Gear.pedestalPrice() (PLAN §8.5's endgame money sink) — a wish list you can
	walk around beats a number in a menu, but you only need to SEE the next few
	to feel that, not all thirty-seven.

	slotOffset is defined for every slot up to EXHIBIT_MAX_SLOTS (rows 5+ extend
	the same two columns further out), so raising VISIBLE_SLOTS past 8 is still
	the only change needed to show more — it just won't match the sketch's exact
	8-stand picture once you do.

	THE WORLD CONTRACT:
	    Pad         PlotIndex = n
	    ClaimBoard  StationKind = "plot",     StationId = "<n>",        Radius = 10
	    Stand       StationKind = "pedestal", StationId = "<n>:<slot>", Radius = 7
	                PlotIndex = n, SlotIndex = s, Locked = true|false
	    PlotSpawn   SpawnLocation, Enabled = false until the plot is claimed
	    Basin       StationKind = "decon", Shower = true, Radius = 9 — the cleansing
	                station (see buildCleansingStation below). One per base, replacing
	                the single shared station + shower that used to live at camp.

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
local BUILDER_VERSION = 12

local C = Kit.C
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

Plots.COUNT = 6
Plots.VISIBLE_SLOTS = 8
-- topY is a deliberate step UP from the plaza (the mirror of Zones.SURFACE_Y's own
-- step down), expressed relative to Hub.PLAZA.topY rather than as a bare literal so
-- it keeps meaning "+1.5 above the plaza" if that ever moves again, instead of
-- silently becoming a different absolute step.
Plots.PAD = { width = 66, depth = 52, topY = Hub.PLAZA.topY + 1.5, thickness = 3 }

--- THE RING. Six pads on the exterior of a circle pulled toward Zone 1, each
--- rotated to face the centre.
---
--- DERIVED FROM Hub.PLAZA, NOT HAND-SYNCED TO IT — same property the rectangular
--- ring before this had: the plaza is the source, this reads it, and moving the
--- plaza moves the ring with it. Hub requires only Kit, so requiring it here is
--- not circular.
---
--- RING_CENTER USED TO BE THE PLAZA'S OWN MIDPOINT (MID_X, MID_Z) — moved
--- toward Zone 1 on request, to shorten the walk from the shop cluster to the
--- field. How far it could move is bounded by the shop cluster's OWN footprint,
--- not by the pads: `SHOP_CLUSTER_EAST_REACH` below is Shops.luau's own
--- eastmost stall (the "Cleaner" counter, `at.x` = centre + 42) plus its own
--- ~11-stud half-width — the shop cluster, not any pad, is the first thing that
--- would cross into Zone 1 if this moved further east than it does.
--- `FIELD_CLEARANCE` is the margin kept past that. (The pads have far more room
--- to spare here — see World.verify()'s own overlap checks, which are the real
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
--- RING_ANGLES is 6 bearings at 30-degree SECTOR MIDPOINTS across the western
--- 180 (195, 225, ... 345), not the sector edges (180, 210, ... 360) — so no pad
--- sits exactly on the north/south line where the ring's open mouth begins.
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

--- Pad-CENTRE orbit radius. 180 gives a uniform ~16-stud gap between every one
--- of the 6 pads' oriented rectangles at 30-degree spacing (checked with real
--- oriented-rectangle distance, not a small-angle approximation) — matching the
--- old rectangular ring's own 16-stud SPREAD gap between paired pads. Comfortably
--- more spread out than the old ring's west-side reach (~134.5 studs from
--- centre): this radius alone is already 180, before a pad's own half-depth is
--- added on top.
Plots.RING_RADIUS = 180

--- The walkway's outer disc radius — has to clear the farthest PAD CORNER from
--- RING_CENTER, not just the farthest pad centre: `sqrt((RING_RADIUS+HALF_D)^2 +
--- HALF_W^2)` = ~208.6 studs.
---
--- 290, NOT A TIGHT FIT OVER THAT REACH, ON REQUEST — the disc used to stop
--- barely 6 studs past the pads' own farthest corner, which read as the
--- walkway ending right where the pads do rather than as land the camp sits
--- on. The extra ~80 studs is a real buffer of tiled ground beyond every pad
--- in every direction, not a tighter safety margin on the same number: nothing
--- else in this file needed to change for it, since `apronSkip`, the backing
--- bands and World.verify()'s landmass square all already read this constant
--- rather than a hardcoded reach.
Plots.RING_OUTER = 290

--- 30-degree spacing, sector MIDPOINTS (see this section's own comment above for
--- why not the sector edges). Order matches the numbering diagram above.
local RING_ANGLES = { 195, 225, 255, 285, 315, 345 }

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
--- the sliver flanking the plaza on its way out to Zone 1 — never anything
--- east of the field's own west edge, the same clipping mechanism that already
--- keeps the plaza's own east edge from overhanging into Zone 1 (`Hub.tileRect`
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
--- rows count DOWN from there toward the entrance. Defined for every slot up to
--- EXHIBIT_MAX_SLOTS (not just the 8 that are actually built — see the header),
--- so raising VISIBLE_SLOTS just adds more rows further toward the front.
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
	light(sign, accent, 22, 1.6)
	light(wall, accent, 18, 0.8)

	-- The claim board: collect banked income, buy the next pedestal slot.
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
	billboard(board, 240, 4.4, `PLOT {index}`, "collect and expand", accent)

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

	-- Only the first EXHIBIT_STARTING_SLOTS are unlocked; the rest of the visible run
	-- is capped and dim, which is the point — you can see what you are saving for.
	for slot = 1, math.min(Plots.VISIBLE_SLOTS, Tuning.EXHIBIT_MAX_SLOTS) do
		local ox, oz = slotOffset(slot)
		local locked = slot > Tuning.EXHIBIT_STARTING_SLOTS

		local stand = build(m, origin, {
			name = `Stand{slot}`,
			pos = { ox, pad.topY + 2, oz },
			size = { 2.6, 4, 2.6 },
			color = if locked then C.plazaEdge else C.plazaWarm,
			material = if locked then "Slate" else "Marble",
			transparency = if locked then 0.45 else 0,
			attributes = {
				StationKind = "pedestal",
				StationId = `{index}:{slot}`,
				PlotIndex = index,
				SlotIndex = slot,
				Locked = locked,
				Radius = 7,
			},
		})

		-- The item sits here. Transparent while the slot is empty; ExhibitService
		-- colours it by rarity when something is displayed, matching the colour the
		-- haul part used when it came out of the ground.
		build(m, origin, {
			name = `Display{slot}`,
			pos = { ox, pad.topY + 5, oz },
			size = { 1.4, 1.4, 1.4 },
			color = accent,
			material = "SmoothPlastic",
			transparency = 1,
			canCollide = false,
			attributes = { PlotIndex = index, SlotIndex = slot },
		})

		if not locked then
			light(stand, accent, 8, 0.6)
		end
	end

	buildCleansingStation(m, origin, accent)

	m.Parent = parent
	return m
end

--- Lay the apron. Lives in this file rather than in Hub.luau because the disc is
--- derived from the pad ring, and Hub cannot see the ring: Plots requires Hub, so a
--- require back the other way would be a cycle. Hub owns the PATTERN and exports it;
--- this file owns the SHAPE and asks for it to be tiled.
---
--- THE VISIBLE CAP is one `Hub.tileRect` call over a square bounding RING_OUTER,
--- clipped at `maxX = PLAZA.maxX` (Zone 1's own west edge, touching not
--- crossing it — the same shared-edge convention the plaza's own east side
--- already uses) and punched by `apronSkip` (plaza + every pad's own oriented
--- footprint) — see that function's own comment above.
---
--- CLIPPED AT THE FIELD, NOT AT RING_CENTER, ON REQUEST. The disc used to stop
--- dead at `RING_CENTER.x`, which is west of the plaza's own east edge — the
--- plaza itself (165x140, its own fixed rectangle) was the only thing carrying
--- the ground from there out to Zone 1, and it is narrower in Z (+/-70) than
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
	Hub.tileRect(apron, discBounds, { skip = apronSkip })

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
			.. `({Tuning.EXHIBIT_STARTING_SLOTS} unlocked, {Tuning.EXHIBIT_MAX_SLOTS} addressable), `
			.. `{#row.Apron:GetChildren()} apron parts`
	)
	return row
end

return Plots
