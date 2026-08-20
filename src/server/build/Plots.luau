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

	SLOTS: 3 UNLOCKED, 12 BUILT, 40 ADDRESSABLE.
	Tuning.EXHIBIT_STARTING_SLOTS is 3 and EXHIBIT_MAX_SLOTS is 40. Building all 40
	plinths on all 6 plots would put 480 parts and 240 station entries into the world
	before anyone has displayed anything, so only VISIBLE_SLOTS are materialised: the
	3 you own plus the next 9, capped and dim. Locked plinths are the visible form of
	Gear.pedestalPrice() (PLAN §8.5's endgame money sink) and a wish list you can walk
	around inside beats a number in a menu — but you only need to SEE the next few to
	feel that, not all thirty-seven.

	The grid geometry addresses all 40 regardless (slotOffset is defined for every
	slot), so raising VISIBLE_SLOTS is the only change needed to show more.

	THE WORLD CONTRACT:
	    Pad         PlotIndex = n
	    ClaimBoard  StationKind = "plot",     StationId = "<n>",       Radius = 10
	    Plinth      StationKind = "pedestal", StationId = "<n>:<slot>", Radius = 7
	                PlotIndex = n, SlotIndex = s, Locked = true|false
	    PlotSpawn   SpawnLocation, Enabled = false until the plot is claimed

	The plinth's StationId is "plot:slot" so the server can resolve exactly which
	pedestal a player is standing at without a spatial search of its own.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)

local Kit = require(script.Parent.Kit)

local Plots = {}
local BUILDER_SOURCE = "src/server/build/Plots.luau"
local BUILDER_VERSION = 1

local C = Kit.C
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

Plots.COUNT = 6
Plots.VISIBLE_SLOTS = 12
Plots.PAD = { width = 66, depth = 52, topY = 1.5, thickness = 3 }

--- Plot centres, in world XZ. Three down each side of the plaza.
---
--- These are threaded BETWEEN the gates on purpose. With plots at these Z bands the
--- east and west edges still have a clear run at Z 6..49 for their roads, and the
--- south edge has a clear run at X -57..57. Move a plot and check Hub.GATES again —
--- the two files share this arithmetic and nothing enforces it but this comment.
Plots.CENTERS = {
	{ -90, -95 },
	{ 90, -95 },
	{ -90, -20 },
	{ 90, -20 },
	{ -90, 75 },
	{ 90, 75 },
}

--- 5 columns x 8 rows addresses 40 positions, matching Tuning.EXHIBIT_MAX_SLOTS.
--- Only the first Plots.VISIBLE_SLOTS of them are actually built — see the header.
local GRID_COLS = 5
local GRID_PITCH_X = 11
local GRID_PITCH_Z = 5.6

local function slotOffset(slot: number): (number, number)
	local index = slot - 1
	local col = index % GRID_COLS
	local row = math.floor(index / GRID_COLS)
	local x = (col - (GRID_COLS - 1) / 2) * GRID_PITCH_X
	local z = -14 + row * GRID_PITCH_Z
	return x, z
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

		local plinth = build(m, origin, {
			name = `Plinth{slot}`,
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
			light(plinth, accent, 8, 0.6)
		end
	end

	m.Parent = parent
	return m
end

local function createPlots(): Model
	local row = Instance.new("Model")
	row.Name = "Plots"
	Kit.stamp(row, BUILDER_SOURCE, BUILDER_VERSION)

	assert(#Plots.CENTERS == Plots.COUNT, "plot centre list does not match Plots.COUNT")

	for index = 1, Plots.COUNT do
		buildPlot(row, index)
	end

	return row
end

function Plots.build(parent: Instance?): Model
	local row = createPlots()
	row.Parent = parent or Workspace
	return row
end

function Plots.rebuild(parent: Instance?): Model
	local row = Kit.swap("Plots", createPlots, parent) :: Model
	print(`[build] Plots rebuilt — {Plots.COUNT} plots, {Plots.VISIBLE_SLOTS} plinths each ({Tuning.EXHIBIT_STARTING_SLOTS} unlocked, {Tuning.EXHIBIT_MAX_SLOTS} addressable)`)
	return row
end

return Plots
