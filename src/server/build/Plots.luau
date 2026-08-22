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

	ONE COLUMN, ONE SPINE — the requested layout:

	    [PLOT] --|
	             |
	    [PLOT] --|
	             | ----- [SHOP AREA]  --- [RADIOACTIVE AREA]
	    [PLOT] --|
	             |
	    [PLOT] --|

	Six plots stack along Z at a single X (`Plots.PLOT_X`), each connected to the
	hub by its own short east-west stub. The stubs all feed one north-south spine
	(`Plots.SPINE_X`), and the spine's east edge lands EXACTLY on the plaza's west
	edge — no trunk road between them any more (there used to be one; per the
	requested layout, plots — shop area — radiation should be directly touching,
	not three places joined by roads, and `Hub.luau`'s plaza grew to meet the
	radiation field's edge the same way on the other side). `buildWestNetwork`
	owns all of this; it requires `Hub` only to read `Hub.PLAZA`
	(halfX/halfZ/topY/thickness), never any Hub *instance* — the two modules
	build independently and Hub has no idea Plots exists, which keeps
	`World.rebuild()`'s ordering irrelevant here.

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
local BUILDER_VERSION = 6

local C = Kit.C
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

Plots.COUNT = 6
Plots.VISIBLE_SLOTS = 8
Plots.PAD = { width = 66, depth = 52, topY = 1.5, thickness = 3 }

--- One column, one X. Stacked along Z so the whole block reads as a single line
--- of plots, per the requested layout — see the header diagram.
Plots.PLOT_X = -170

--- Spacing = pad.depth (52) + a 14-stud gap, so plots pack tight without
--- touching. Six values, symmetric about z=0.
Plots.CENTERS = {
	{ Plots.PLOT_X, -165 },
	{ Plots.PLOT_X, -99 },
	{ Plots.PLOT_X, -33 },
	{ Plots.PLOT_X, 33 },
	{ Plots.PLOT_X, 99 },
	{ Plots.PLOT_X, 165 },
}

--- Where the north-south spine sits. The spine is a lane 20 studs wide (see
--- `buildWestNetwork`), so its own east edge is `SPINE_X + 10` — and that edge
--- has to land EXACTLY on `Hub.PLAZA`'s west edge (`-Hub.PLAZA.halfX` = -100)
--- for the plaza and the plot block to touch directly, with no trunk road
--- filling the gap between them any more. Hence -110, not -100.
Plots.SPINE_X = -110

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
	local origin = CFrame.new(center[1], 0, center[2])
	local accent = Kit.PLOT_ACCENT[((index - 1) % #Kit.PLOT_ACCENT) + 1]
	local pad = Plots.PAD

	-- The stage. One step up from the plaza — a plot should feel like somewhere you
	-- walk onto, not part of the pavement.
	build(m, origin, {
		name = "Pad",
		pos = { 0, pad.topY - pad.thickness / 2, 0 },
		size = { pad.width, pad.thickness, pad.depth },
		color = C.plazaEdge,
		material = "Concrete",
		attributes = { PlotIndex = index },
	})

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

-- ── The west network: stubs, spine, trunk ────────────────────────────────────
-- Same shape as Hub.luau's buildRoad (flat pavement strip + grass verges either
-- side), kept as its own local copy rather than shared through Kit: each
-- generator's road-shape logic has stayed self-contained by convention so far,
-- and this is the only other file that needs it.
local function buildLane(parent: Instance, name: string, from: Vector3, to: Vector3, width: number)
	local origin = CFrame.new(0, 0, 0)
	local mid = (from + to) / 2
	local span = (to - from).Magnitude
	local alongX = math.abs(to.X - from.X) > math.abs(to.Z - from.Z)
	local topY, thickness = Hub.PLAZA.topY, Hub.PLAZA.thickness

	build(parent, origin, {
		name = name,
		pos = { mid.X, topY - thickness / 2, mid.Z },
		size = {
			if alongX then span else width,
			thickness,
			if alongX then width else span,
		},
		color = C.road,
		material = "Pavement",
	})

	for _, side in { -1, 1 } do
		build(parent, origin, {
			name = `{name}Verge`,
			pos = {
				mid.X + (if alongX then 0 else side * (width / 2 + 2)),
				topY - 0.3,
				mid.Z + (if alongX then side * (width / 2 + 2) else 0),
			},
			size = {
				if alongX then span else 4,
				0.8,
				if alongX then 4 else span,
			},
			color = C.grass,
			material = "Grass",
			canCollide = false,
		})
	end
end

--- The connective tissue for the diagram in the header: a stub per plot, one
--- spine collecting them. No trunk any more — the spine's east edge lands
--- exactly on the plaza's west edge (see `Plots.SPINE_X`'s own comment), so the
--- plot block and the shop area butt directly against each other. All safe
--- ground (no ZoneId), same as every other road in the map.
local function buildWestNetwork(parent: Instance)
	local pad = Plots.PAD

	-- Spine: one north-south lane every stub feeds into. Spans the full plot
	-- column with a 20-stud margin at each end so the top and bottom stubs don't
	-- join it right at a corner.
	local topZ, bottomZ = Plots.CENTERS[1][2], Plots.CENTERS[1][2]
	for _, center in Plots.CENTERS do
		topZ = math.max(topZ, center[2])
		bottomZ = math.min(bottomZ, center[2])
	end
	buildLane(parent, "PlotSpine", Vector3.new(Plots.SPINE_X, 0, bottomZ - 20), Vector3.new(Plots.SPINE_X, 0, topZ + 20), 20)

	-- One stub per plot: its own east edge straight into the spine. Narrower than
	-- the spine and trunk (16 vs 20/34) so the hierarchy — private lane feeds
	-- neighbourhood spine feeds main road — is readable at a glance.
	for index, center in Plots.CENTERS do
		local from = Vector3.new(center[1] + pad.width / 2, 0, center[2])
		local to = Vector3.new(Plots.SPINE_X, 0, center[2])
		buildLane(parent, `PlotStub{index}`, from, to, 16)
	end
end

local function createPlots(): Model
	local row = Instance.new("Model")
	row.Name = "Plots"
	Kit.stamp(row, BUILDER_SOURCE, BUILDER_VERSION)

	assert(#Plots.CENTERS == Plots.COUNT, "plot centre list does not match Plots.COUNT")

	for index = 1, Plots.COUNT do
		buildPlot(row, index)
	end
	buildWestNetwork(row)

	return row
end

function Plots.build(parent: Instance?): Model
	local row = createPlots()
	row.Parent = parent or Workspace
	return row
end

function Plots.rebuild(parent: Instance?): Model
	local row = Kit.swap("Plots", createPlots, parent) :: Model
	print(`[build] Plots rebuilt — {Plots.COUNT} plots, {Plots.VISIBLE_SLOTS} stands each ({Tuning.EXHIBIT_STARTING_SLOTS} unlocked, {Tuning.EXHIBIT_MAX_SLOTS} addressable)`)
	return row
end

return Plots
