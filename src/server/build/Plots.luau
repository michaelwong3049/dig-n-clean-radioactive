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

	A RING AROUND THE PLAZA, DIRECTLY AGAINST IT — the requested layout:

	          [PLOT] [PLOT]
	    [PLOT] ┌───────────┐
	           │ SHOP AREA │ === [RADIOACTIVE AREA]
	    [PLOT] └───────────┘
	          [PLOT] [PLOT]

	Two north, two south, two west, each pad butted flush against the plaza edge and
	rotated to face inward. The east side is the radiation field, so the ring is open
	there and always will be — you leave the courtyard by walking into the sludge.

	IT WAS A SINGLE COLUMN DOWN THE WEST SIDE UNTIL NOW, and that had a cost nobody
	had priced: the plaza had been stretched to 382 studs deep purely so it could span
	the column and let all six plots border it. Ringing them freed the plaza to be
	sized by what actually stands on it, and it came back to 180x200 — a little over
	half the area. The plots did not get smaller; the car park between them did.

	A BASE WEARS THE PLAZA'S BOARD IN ITS OWN COLOURS. The pad is not a slab of
	concrete any more: it is the same studded checkerboard the courtyard is paved in,
	on the same grid, in navy and grey instead of green, one step up. That makes the
	six bases the only thing in the world that is not some shade of green, and it
	makes walking onto one a change of colour rather than a change of surface. See
	`buildPlot` — the tiles are placed in WORLD space, not this model's yawed local
	space, which is the one detail that is easy to get wrong.

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
local BUILDER_VERSION = 8

local C = Kit.C
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

Plots.COUNT = 6
Plots.VISIBLE_SLOTS = 8
Plots.PAD = { width = 66, depth = 52, topY = 1.5, thickness = 3 }

--- THE RING. Six pads butted against the plaza edge, each rotated to face inward.
---
--- DERIVED FROM Hub.PLAZA, NOT HAND-SYNCED TO IT. This used to be a single column at
--- a literal `Plots.PLOT_X = -170`, with Hub.luau carrying a four-number comment about
--- how its plaza had been stretched to match — two files, one shared geometry, and
--- nothing to catch them drifting apart. The dependency now runs one way: the plaza is
--- the source, this reads it, and moving the plaza moves the pads with it. Hub requires
--- only Kit, so requiring it here is not circular.
---
--- `facing` is a yaw in degrees. A pad is built with its back wall at +Z and its claim
--- board at -Z, so 0 faces south and each side of the ring turns to look at the plaza:
---
---              [ 2 ]   [ 3 ]          north pads face south  (0)
---        [ 1 ]  ┌───────────┐
---               │   PLAZA   │  ==>  RADIATION      east is the field; the
---        [ 6 ]  └───────────┘                      ring is open there
---              [ 5 ]   [ 4 ]          south pads face north  (180)
---                                     west pads face east    (-90)
---
--- Numbered clockwise from the west side's north half. The jump from 3 to 4 crosses
--- the open east side, which is the one place the ring cannot close.
local PLAZA = Hub.PLAZA
local HALF_W, HALF_D = Plots.PAD.width / 2, Plots.PAD.depth / 2
local MID_X, MID_Z = (PLAZA.minX + PLAZA.maxX) / 2, (PLAZA.minZ + PLAZA.maxZ) / 2

--- Half the centre-to-centre spacing of the two pads on a side. HALF_W plus a gap, so
--- the pair sits either side of the midpoint with a walkable slot between them rather
--- than as one 132-stud slab.
local SPREAD = HALF_W + 8

Plots.CENTERS = {
	{ x = PLAZA.minX - HALF_D, z = MID_Z + SPREAD, facing = -90 },
	{ x = MID_X - SPREAD, z = PLAZA.maxZ + HALF_D, facing = 0 },
	{ x = MID_X + SPREAD, z = PLAZA.maxZ + HALF_D, facing = 0 },
	{ x = MID_X + SPREAD, z = PLAZA.minZ - HALF_D, facing = 180 },
	{ x = MID_X - SPREAD, z = PLAZA.minZ - HALF_D, facing = 180 },
	{ x = PLAZA.minX - HALF_D, z = MID_Z - SPREAD, facing = -90 },
}

--- A pad's XZ footprint in world space. A pad is built width-along-X, depth-along-Z
--- and then YAWED into place, so the two pads on the west side — the ones facing east
--- — have those two numbers the other way round. Only right angles occur in the ring,
--- so this is a swap rather than a rotation.
local function padBounds(c: { x: number, z: number, facing: number }): (number, number, number, number)
	local sideways = c.facing == 90 or c.facing == -90
	local halfX = if sideways then HALF_D else HALF_W
	local halfZ = if sideways then HALF_W else HALF_D
	return c.x - halfX, c.z - halfZ, c.x + halfX, c.z + halfZ
end

--- THE APRON — the ground in the gaps BETWEEN the bases.
---
--- The six pads sit in a corridor one pad-depth wide wrapped around three sides of
--- the plaza, but they do not fill it. SPREAD leaves a 16-stud slot between each
--- pair, and where the west side meets the north and south sides there is a much
--- bigger L-shaped hole. All of it was open sky: you could see the void under the map
--- from the middle of the camp, and there was no way to walk from one base to the one
--- beside it without cutting all the way back across the plaza.
---
--- FILLING IT IS THREE RECTANGLES, NOT NINE. Tile the whole corridor and punch the
--- pads back out with a skip predicate, rather than enumerating the gaps by hand.
--- Same result, and it cannot fall out of step with the ring — nine hand-written
--- rectangles would be wrong the moment SPREAD, PAD or the plaza changes, and wrong
--- silently, as a hole somebody notices weeks later.
---
--- THE EAST EDGE STOPS DEAD ON PLAZA.maxX, which is also Zone 1's west edge. The
--- corridor may touch the field and must never cross into it: apron is zero-rad
--- ground, and a strip of it inside the zone would be a safe pocket in the middle of
--- the radiation — the one property the whole "paths are safe, the green is not" rule
--- rests on. `Hub.tileRect` clips edge tiles to the rectangle for this reason.
local RING = Plots.PAD.depth

local APRON: { Hub.Rect } = {
	{ minX = PLAZA.minX - RING, maxX = PLAZA.maxX, minZ = PLAZA.maxZ, maxZ = PLAZA.maxZ + RING },
	{ minX = PLAZA.minX - RING, maxX = PLAZA.maxX, minZ = PLAZA.minZ - RING, maxZ = PLAZA.minZ },
	{ minX = PLAZA.minX - RING, maxX = PLAZA.minX, minZ = PLAZA.minZ, maxZ = PLAZA.maxZ },
}

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
	-- BUILT IN WORLD SPACE, NOT THIS MODEL'S LOCAL SPACE, which is the one thing to be
	-- careful about here. Everything else in this function is placed against `origin`,
	-- which is YAWED to face the plaza; the tiles are not, because they have to land on
	-- the plaza's own grid to stay in register with the apron the pad sits on. Yawing
	-- them 90 degrees on the west pads would rotate the board out of alignment with
	-- itself. A pad's footprint is axis-aligned in world space at every facing the ring
	-- uses, so tiling the footprint directly is exact, not an approximation.
	local x0, z0, x1, z1 = padBounds(Plots.CENTERS[index])
	local rect: Hub.Rect = { minX = x0, maxX = x1, minZ = z0, maxZ = z1 }
	local tint: Hub.TileOpts = { topY = pad.topY, dark = C.baseTileDark, light = C.baseTileLight }

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

--- Lay the apron. Lives in this file rather than in Hub.luau because the corridor is
--- derived from the pad ring, and Hub cannot see the ring: Plots requires Hub, so a
--- require back the other way would be a cycle. Hub owns the PATTERN and exports it;
--- this file owns the SHAPE and asks for it to be tiled.
local function buildApron(row: Model)
	local apron = Instance.new("Folder")
	apron.Name = "Apron"

	local function insidePad(x: number, z: number): boolean
		for _, c in Plots.CENTERS do
			local x0, z0, x1, z1 = padBounds(c)
			if x > x0 and x < x1 and z > z0 and z < z1 then
				return true
			end
		end
		return false
	end

	for index, rect in APRON do
		Hub.groundSlab(apron, rect, `ApronSlab{index}`)
		Hub.tileRect(apron, rect, { skip = insidePad })
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
