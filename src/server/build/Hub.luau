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

	THE FLOOR IS A CHECKERBOARD, and it is not only this floor. `Hub.TILES` below is
	the grid; `tileRect` and `groundSlab` are exported so the plot ring and the six
	player bases can lay the same board. The plaza and its apron wear it in two shades
	of green, the bases wear it in navy and grey a step above — one pattern, one grid,
	two palettes, staying in register across the apron's own edges because the grid
	belongs to the plaza rather than to whoever is asking for tiles.

	A PAD'S OWN BOARD IS THE ONE EXCEPTION, AND ONLY SINCE THE SEMICIRCLE. Both
	builders below take an optional `opts.origin` CFrame so a caller can tile a
	rectangle defined in ITS OWN local frame instead of always in world space —
	added because a pad's facing is no longer a multiple of 90 degrees, so its
	footprint is no longer axis-aligned in world space the way the grid math here
	assumes. A pad's tiles stay an exact 3x3 checkerboard, they just no longer
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
local BUILDER_VERSION = 10

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

--- The central pad. A neutral-grey square inlaid dead-centre of the plaza -- the same
--- studded board on the same grid at the same height as the rest of the courtyard,
--- only a different palette, so it reads as a marked-out gathering pad rather than a
--- raised platform (no step, footing is unchanged). ~44 studs, sitting in the open
--- ground the three shop fronts face onto. The two greys keep the plaza pair's own
--- ~1.14x light/dark ratio so the checker reads the same, just decoloured.
local PAD_HALF = 22
local PAD_DARK = "63656B"
local PAD_LIGHT = "767981"

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

-- ── The floor ─────────────────────────────────────────────────────────────────
-- THE PLAZA IS A CHECKERBOARD OF STUDDED TILES, not one flat slab. A single colour
-- reads as a void with things parked on it: nothing tells you how big the courtyard
-- is or how far you have walked across it. A regular grid does both for free, and
-- classic Roblox studs are the cheapest way to get a surface that catches the light
-- instead of sitting there as a matte rectangle.
--
-- TILES IS A COUNT PER AXIS, NOT A STUD SIZE, and it is the one number to turn when
-- the pattern reads wrong. The plaza is 165 studs wide (PLAZA.maxX - PLAZA.minX,
-- post "compact the plaza" pass — was 200 when this file's numbers were first
-- picked), so 55 gives an exact 165/55 = 3-stud tile with no rounding, 55^2 = 3025
-- of them.
--
-- Studs are laid out on a one-per-stud pitch centred on each face, so a tile whose
-- side is a whole number of studs is the one that comes out exactly like the classic
-- brick — which is why 55 was chosen over an arbitrary nearby count: it lands on
-- exactly 3, not a rounding that happens to look close to 3.
--
-- THE TILES ARE A CAP LAYER OVER A STRUCTURAL SLAB, rather than thousands of
-- full-thickness blocks. Two reasons: the plaza's exposed side stays one clean dark
-- face instead of a many-toothed checkered stripe, and the slab is what everything
-- actually stands on. The slab's top is recessed by exactly CAP, so the walking
-- surface is still PLAZA.topY and nothing standing on the plaza has to move.
--
-- THE CENTRE OF THE BOARD IS A GREY PAD -- see PAD_DARK/PAD_LIGHT and buildPlaza. It
-- is not separate geometry, just those same cap tiles painted a different pair over a
-- ~44-stud square in the middle; footing and height are the plaza's everywhere.
Hub.TILES = 55
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

	local origin = o.origin or CFrame.new(0, 0, 0)
	local size = (p.maxX - p.minX) / Hub.TILES

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
			if colorAt then
				tileDark, tileLight = colorAt(cx, cz)
			end

			build(parent, origin, {
				name = "Tile",
				pos = { cx, topY - CAP / 2, cz },
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

	-- Foldered because thousands of siblings (Hub.TILES^2) makes the Hub model
	-- unopenable in the explorer, and every one of them is the same decorative cap.
	-- The handful of parts that actually matter stay visible next to the folder
	-- instead of buried in it.
	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"

	-- The board is one call: the whole plaza in its green pair, EXCEPT the central pad,
	-- which the same grid paints grey. A per-tile colourAt (not a second tileRect laid
	-- on top) so there is one tile per square, no z-fight, and the checker parity
	-- carries straight through the pad edge.
	local cx, cz = (p.minX + p.maxX) / 2, (p.minZ + p.maxZ) / 2
	Hub.tileRect(tiles, p, {
		colorAt = function(x: number, z: number): (string, string)
			if math.abs(x - cx) < PAD_HALF and math.abs(z - cz) < PAD_HALF then
				return PAD_DARK, PAD_LIGHT
			end
			return PLAZA_DARK, PLAZA_LIGHT
		end,
	})
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

	-- z moved 0 <- -14: that offset used to read as "just inside the gate," but
	-- the gate is gone and -14 now lands inside the Outfitter's new footprint
	-- (Shops.luau's OUTFITTER moved to z=-22, reaching to about z=-13). 0 sits in
	-- the open aisle between the two shop rows (STALLS at z=22, OUTFITTER at
	-- z=-22) — still an arbitrary point, just no longer one that lands inside a
	-- building.
	local grate = Hub.CAMP_ORIGIN * CFrame.new(0, 0.75, 0)
	build(spawns, CFrame.new(0, 0, 0), {
		name = "RespawnAnchor",
		pos = { grate.X, Hub.PLAZA.topY + 0.5, grate.Z },
		size = { 4, 1, 4 },
		color = C.cyan,
		material = "Neon",
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
