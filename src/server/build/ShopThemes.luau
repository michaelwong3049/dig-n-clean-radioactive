--!strict
--[[
	ShopThemes.luau — the props that make each plaza stall look like its trade.

	    called from build/Shops (buildStall for the three track stalls, buildOutfitter)

	WHY THIS EXISTS. Every stall was the same grey frame with a different canopy
	colour, so the only thing telling the Detector Shop from the Hose Shop was the
	colour and the floating label. The trader's hazmat booth (build/BaseCamp) showed
	the fix: a stall reads best when it looks like the thing it does. These themes
	were picked on request from mockups built in Play:

	  * DETECTOR — a survey outpost: a radar dish on the roof over the stand, a survey
	    map with a red route and pins on the back wall, a surveyor's tripod, and a whip
	    antenna on the back corner post.
	  * MAGNET — a scrapyard: a giant horseshoe magnet on the roof, a wall crane
	    holding an electromagnet with a rusty plate stuck to it, and a scrap pile.
	  * CLEANER (the Hose Shop) — a decon bay: a tiled wall with a shower bar, a hose
	    reel, a drain grate, a mop bucket, and a water tank on the roof.
	  * OUTFITTER (the Aura Shop) — a faceless mannequin wearing a live aura that walks
	    the tier ladder, a sample tube per tier either side of it, and a giant atom
	    turning on the roof. It was a locker room round a hazmat suit until the Suit
	    track became the Aura.

	THIS OVERRIDES THE OLD "NO PROPS IN THE SHOPS" CALL, ON REQUEST. The stalls were
	stripped to bare structure once (grey lumber, no identity props, no vendors). The
	themes bring props back, deliberately, and they stay inside these rules:

	  * EVERYTHING SITS BEHIND THE SHOPFRONT OR ON THE ROOF. Props stand in the back
	    strip of the stall (between the slat wall at z = -10 and the rack/stand line)
	    or on the canopy. Nothing crosses the shopfront, so the rack, its prompts and
	    the forecourt floor markers are untouched, and nothing leaves the stall's own
	    footprint (Shops.assertNoShopOverlap still holds — the neighbours are close).
	  * PROPS CLUSTER BEHIND THE STAND, NOT THE RACK. The hanging tiers fill the rack
	    wing from the floor to the rail, so anything low behind them is hidden. The
	    stand is only waist high, which leaves the whole back wall above it visible.
	  * NOTHING GLOWS. No Neon, no lights (Kit.C's header): the radar is painted and
	    the tank is steel. The one exception is the Outfitter mannequin's aura, which
	    this file does not build (see dressOutfitter). Motion goes through Kit.motion
	    and StationMotionController, like the roof atom's spin.
	  * WALK-THROUGH. Every prop is CanCollide false, like the rest of the plaza
	    dressing, so none of them can trap a player who wanders behind a counter.

	All coordinates are in the stall's own frame (Shops' facingOrigin): +Z toward the
	customer, Y from the plaza top, X across the shopfront. `standX` is the stand's
	centre along that line.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AuraLook = require(ReplicatedStorage.Shared.AuraLook)
local Gear = require(ReplicatedStorage.Shared.Config.Gear)
local Kit = require(script.Parent.Kit)

local ShopThemes = {}

local C = Kit.C

-- ── Shared geometry ───────────────────────────────────────────────────────────

-- The inner face of the slat wall (Shops' buildSlatWall stands at z = -10, 0.55 deep).
local WALL_FACE_Z = -9.725
-- The underside of a roof prop's plinth: the roof plates (Shops' buildPlateRoof,
-- centreY 9.8 at z = -4, 4 degree tilt, 0.45 thick) top out at ~10.2 around z = -5
-- to -6, where every roof prop stands. The seam straps and rivets stand up to ~0.4
-- proud of that, which the 0.7-tall plinth swallows.
local ROOF_Y = 10.2
local ROOF_Z = -5.5

local R_CYL_UP = Kit.R.cylUp -- cylinder standing upright
local R_CYL_Z = Kit.R.yaw90 -- cylinder lying front-to-back (its flat face to the customer)

--- One prop part. Every prop is walk-through (see the header), so this only
--- forwards to Kit.build with canCollide pinned off.
local function prop(parent: Instance, origin: CFrame, spec: Kit.Spec): BasePart
	spec.canCollide = false
	return Kit.build(parent, origin, spec)
end

--- A dark steel plinth on the roof for a roof prop to stand on.
local function roofPlinth(parent: Instance, origin: CFrame, x: number, sx: number, sz: number)
	prop(parent, origin, {
		name = "RoofPlinth",
		pos = { x, ROOF_Y + 0.35, ROOF_Z },
		size = { sx, 0.7, sz },
		color = C.steelDark,
		material = "Plastic",
	})
end

-- ── Detector: the survey outpost ──────────────────────────────────────────────

local MAP_PAPER = "EFE3C8"
local MAP_LAND = "8FC7A0"
local MAP_WATER = "9DC4DE"
local MAP_SAND = "C9B48C"
local TRIPOD_WOOD = "C9A46A"

local function dressDetector(parent: Instance, origin: CFrame, width: number, standX: number)
	local accent = C.shopDetector

	-- The survey map on the back wall over the stand: a paper board in an accent
	-- frame, painted land/water/sand patches, a dashed red route and three pins.
	local mapY = 5.6
	local mapZ = WALL_FACE_Z + 0.1
	prop(parent, origin, {
		name = "MapFrame",
		pos = { standX, mapY, mapZ },
		size = { 7.6, 4.6, 0.2 },
		color = accent,
		material = "SmoothPlastic",
	})
	prop(parent, origin, {
		name = "MapPaper",
		pos = { standX, mapY, mapZ + 0.12 },
		size = { 7, 4, 0.1 },
		color = MAP_PAPER,
		material = "SmoothPlastic",
	})
	for _, patch in {
		{ -2, 1, 2.2, 1.2, MAP_LAND },
		{ 1.6, 0.9, 2.4, 1.6, MAP_WATER },
		{ -1.2, -1.1, 2.8, 1.2, MAP_SAND },
		{ 2, -1.2, 1.8, 1, MAP_LAND },
	} do
		prop(parent, origin, {
			name = "MapPatch",
			pos = { standX + patch[1], mapY + patch[2], mapZ + 0.19 },
			size = { patch[3], patch[4], 0.05 },
			color = patch[5],
			material = "SmoothPlastic",
		})
	end
	local route = { { -3, -1.5 }, { -1.8, -0.6 }, { -0.6, 0.2 }, { 0.6, 0.4 }, { 1.8, 1.2 }, { 2.8, 1.5 } }
	for i = 1, #route - 1 do
		local a, b = route[i], route[i + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		prop(parent, origin, {
			name = "MapRoute",
			pos = { standX + (a[1] + b[1]) / 2, mapY + (a[2] + b[2]) / 2, mapZ + 0.23 },
			-- 60% of the leg's length, so the route reads as a dashed line.
			size = { math.sqrt(dx * dx + dy * dy) * 0.6, 0.12, 0.04 },
			color = C.quarantineRed,
			material = "SmoothPlastic",
			rot = Kit.ang(0, 0, math.deg(math.atan2(dy, dx))),
		})
	end
	for _, pin in { route[1], route[4], route[6] } do
		prop(parent, origin, {
			name = "MapPin",
			pos = { standX + pin[1], mapY + pin[2], mapZ + 0.32 },
			size = { 0.35, 0.35, 0.35 },
			color = C.quarantineRed,
			material = "SmoothPlastic",
			shape = "Ball",
		})
	end

	-- The radar dish on the roof over the stand: a mast on a plinth, and a white dish
	-- in an accent rim tilted 25 degrees up toward the plaza, with its feed arm and
	-- horn and a gearbox behind it. Static (see the header).
	roofPlinth(parent, origin, standX, 1.6, 1.6)
	prop(parent, origin, {
		name = "RadarMast",
		pos = { standX, ROOF_Y + 1.95, ROOF_Z },
		size = { 2.6, 0.45, 0.45 },
		color = C.steelDark,
		material = "Metal",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	local hub = origin * CFrame.new(standX, ROOF_Y + 3.45, ROOF_Z)
	local dish = hub * Kit.ang(-25, 0, 0)
	prop(parent, dish, {
		name = "RadarDish",
		pos = { 0, 0, 0 },
		size = { 0.3, 5.2, 5.2 },
		color = C.labelText,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R_CYL_Z,
	})
	prop(parent, dish, {
		name = "RadarRim",
		pos = { 0, 0, -0.18 },
		size = { 0.2, 5.6, 5.6 },
		color = accent,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R_CYL_Z,
	})
	prop(parent, dish, {
		name = "RadarFeedArm",
		pos = { 0, 0, 1.2 },
		size = { 2.2, 0.18, 0.18 },
		color = C.steelDark,
		material = "Metal",
		shape = "Cylinder",
		rot = R_CYL_Z,
	})
	prop(parent, dish, {
		name = "RadarFeedHorn",
		pos = { 0, 0, 2.35 },
		size = { 0.5, 0.5, 0.5 },
		color = accent,
		material = "SmoothPlastic",
	})
	prop(parent, hub, {
		name = "RadarGearbox",
		pos = { 0, -0.6, -0.5 },
		size = { 1, 1, 1.2 },
		color = C.steelDark,
		material = "Metal",
	})

	-- A surveyor's tripod behind the stand's outer end: three splayed wooden legs,
	-- a steel head, a yellow instrument body and its lens toward the plaza.
	local tx, tz = standX - 2.6, -6.5
	for i = 0, 2 do
		local a = math.rad(i * 120 + 30)
		prop(parent, origin, {
			name = "TripodLeg",
			pos = { tx + math.cos(a) * 0.9, 2.0, tz + math.sin(a) * 0.9 },
			size = { 0.18, 4.1, 0.18 },
			color = TRIPOD_WOOD,
			material = "Wood",
			-- Lean each leg's foot outward, away from the head.
			rot = CFrame.Angles(math.sin(a) * math.rad(-12), 0, math.cos(a) * math.rad(12)),
		})
	end
	prop(parent, origin, {
		name = "TripodHead",
		pos = { tx, 4.15, tz },
		size = { 0.9, 0.25, 0.9 },
		color = C.steelDark,
		material = "Metal",
	})
	prop(parent, origin, {
		name = "TripodInstrument",
		pos = { tx, 4.65, tz },
		size = { 0.7, 0.75, 0.9 },
		color = C.barrelYellow,
		material = "SmoothPlastic",
	})
	prop(parent, origin, {
		name = "TripodLens",
		pos = { tx, 4.75, tz + 0.7 },
		size = { 0.6, 0.35, 0.35 },
		color = C.steelDark,
		material = "Metal",
		shape = "Cylinder",
		rot = R_CYL_Z,
	})

	-- A whip antenna off the top of the back corner post at the rack's far end, with
	-- three shrinking crossbars and an accent ball on the tip.
	local ax = width / 2 - 0.75
	prop(parent, origin, {
		name = "AntennaWhip",
		pos = { ax, 12.6, -10 },
		size = { 0.14, 5, 0.14 },
		color = C.steelDark,
		material = "Metal",
	})
	for i, y in { 11.2, 12.4, 13.6 } do
		prop(parent, origin, {
			name = "AntennaBar",
			pos = { ax, y, -10 },
			size = { 1.6 - i * 0.35, 0.1, 0.1 },
			color = C.steelDark,
			material = "Metal",
		})
	end
	prop(parent, origin, {
		name = "AntennaTip",
		pos = { ax, 15.15, -10 },
		size = { 0.3, 0.3, 0.3 },
		color = accent,
		material = "SmoothPlastic",
		shape = "Ball",
	})
end

-- ── Magnet: the scrapyard ─────────────────────────────────────────────────────

local SCRAP_RUST = "B5653A"
local SCRAP_TAN = "A07B4E"
local CRANE_YELLOW = C.barrelYellow

local function dressMagnet(parent: Instance, origin: CFrame, _width: number, standX: number)
	-- A giant horseshoe magnet on the roof over the stand, opening upward with steel
	-- pole tips: nine blocks around the bend, each rotated to follow the curve, and
	-- two straight legs.
	roofPlinth(parent, origin, standX, 5.6, 1.8)
	local magnet = origin * CFrame.new(standX, ROOF_Y + 3.0, ROOF_Z)
	local BEND_R, THICK = 2.1, 1.1
	for i = 0, 8 do
		local a = math.rad(180 + i * 22.5)
		prop(parent, magnet * CFrame.new(math.cos(a) * BEND_R, math.sin(a) * BEND_R, 0), {
			name = "MagnetBend",
			pos = { 0, 0, 0 },
			size = { THICK, 0.95, 1.2 },
			color = C.quarantineRed,
			material = "SmoothPlastic",
			rot = Kit.ang(0, 0, math.deg(a) + 90),
		})
	end
	for _, x in { -BEND_R, BEND_R } do
		prop(parent, magnet, {
			name = "MagnetLeg",
			pos = { x, 1.0, 0 },
			size = { THICK, 2.0, 1.2 },
			color = C.quarantineRed,
			material = "SmoothPlastic",
		})
		prop(parent, magnet, {
			name = "MagnetPole",
			pos = { x, 2.45, 0 },
			size = { THICK, 0.9, 1.2 },
			color = C.steel,
			material = "Metal",
		})
	end

	-- A wall crane behind the stand: a yellow jib off the back wall with a diagonal
	-- brace, a cable, and an electromagnet in the stall's accent lifting a rusty plate.
	local jx = standX + 2
	local hookZ = -6.2
	prop(parent, origin, {
		name = "CraneMount",
		pos = { jx, 8.2, WALL_FACE_Z + 0.03 },
		size = { 0.9, 1.4, 0.3 },
		color = C.steelDark,
		material = "Metal",
	})
	prop(parent, origin, {
		name = "CraneJib",
		pos = { jx, 8.2, -7.9 },
		size = { 0.5, 0.5, 3.8 },
		color = CRANE_YELLOW,
		material = "Metal",
	})
	prop(parent, origin, {
		name = "CraneBrace",
		pos = { jx, 7.2, -8.9 },
		size = { 0.3, 0.3, 2.6 },
		color = CRANE_YELLOW,
		material = "Metal",
		rot = Kit.ang(-45, 0, 0),
	})
	prop(parent, origin, {
		name = "CraneCable",
		pos = { jx, 7.25, hookZ },
		size = { 0.1, 1.7, 0.1 },
		color = C.hazardBlack,
		material = "SmoothPlastic",
	})
	prop(parent, origin, {
		name = "Electromagnet",
		pos = { jx, 6.25, hookZ },
		size = { 0.6, 2.2, 2.2 },
		color = C.shopMagnet,
		material = "Metal",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	prop(parent, origin, {
		name = "ElectromagnetBand",
		pos = { jx, 6.25, hookZ },
		size = { 0.3, 2.35, 2.35 },
		color = C.steelDark,
		material = "Metal",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	prop(parent, origin, {
		name = "LiftedPlate",
		pos = { jx + 0.2, 5.75, hookZ },
		size = { 2.6, 0.3, 1.6 },
		color = SCRAP_RUST,
		material = "CorrodedMetal",
		rot = Kit.ang(0, 12, -6),
	})

	-- A scrap pile in the back corner behind the stand's outer end, stacked about
	-- three studs high so it shows over the waist-high stand. Its own fixed seed, so
	-- the pile is the same on every rebuild.
	local px, pz = standX - 2.4, -7.3
	local rng = Random.new(7)
	local scrapColors = { SCRAP_RUST, C.railGrey, C.shopWood, SCRAP_RUST, SCRAP_TAN }
	for layer = 0, 2 do
		local count = 5 - layer
		local spread = 1.5 - layer * 0.4
		for i = 1, count do
			prop(parent, origin, {
				name = "Scrap",
				pos = {
					px + rng:NextNumber(-spread, spread),
					0.4 + layer * 0.95 + rng:NextNumber(0, 0.2),
					pz + rng:NextNumber(-spread * 0.8, spread * 0.8),
				},
				size = { rng:NextNumber(0.7, 1.9), rng:NextNumber(0.35, 0.8), rng:NextNumber(0.6, 1.6) },
				color = scrapColors[rng:NextInteger(1, #scrapColors)],
				material = if i % 2 == 0 then "CorrodedMetal" else "Metal",
				rot = Kit.ang(rng:NextNumber(-25, 25), rng:NextNumber(0, 180), rng:NextNumber(-25, 25)),
			})
		end
	end
	prop(parent, origin, {
		name = "ScrapTyre",
		pos = { px + 1.1, 0.9, pz + 1.1 },
		size = { 0.7, 1.8, 1.8 },
		color = C.hazardBlack,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = Kit.ang(0, 20, 70),
	})
	prop(parent, origin, {
		name = "ScrapDrum",
		pos = { px - 0.4, 3.2, pz - 0.2 },
		size = { 1.8, 1.2, 1.2 },
		color = C.barrelRust,
		material = "Metal",
		shape = "Cylinder",
		rot = Kit.ang(0, 35, 0),
	})
end

-- ── Cleaner (the Hose Shop): the decon bay ────────────────────────────────────

local TILE = "D6ECF7"
local GROUT = "8FB8D0"
local TANK_BLUE = "7FB9D6"

local function dressCleaner(parent: Instance, origin: CFrame, _width: number, standX: number)
	local accent = C.shopCleaner

	-- A tiled panel on the back wall behind the stand: pale blue tiles in a grout
	-- grid, with an accent band along the bottom.
	local PW, PH, PY = 9.2, 7.2, 4.5
	local panelZ = WALL_FACE_Z + 0.12
	prop(parent, origin, {
		name = "TilePanel",
		pos = { standX, PY, panelZ },
		size = { PW, PH, 0.2 },
		color = TILE,
		material = "SmoothPlastic",
	})
	for i = 1, 7 do
		prop(parent, origin, {
			name = "Grout",
			pos = { standX - PW / 2 + i * PW / 8, PY, panelZ + 0.12 },
			size = { 0.08, PH, 0.04 },
			color = GROUT,
			material = "SmoothPlastic",
		})
	end
	for j = 1, 5 do
		prop(parent, origin, {
			name = "Grout",
			pos = { standX, PY - PH / 2 + j * PH / 6, panelZ + 0.12 },
			size = { PW, 0.08, 0.04 },
			color = GROUT,
			material = "SmoothPlastic",
		})
	end
	prop(parent, origin, {
		name = "TileBand",
		pos = { standX, PY - PH / 2 + 0.6, panelZ + 0.14 },
		size = { PW, 1.2, 0.06 },
		color = accent,
		material = "SmoothPlastic",
	})

	-- A shower bar across the top of the tiles with three nozzles hanging off it.
	prop(parent, origin, {
		name = "ShowerBar",
		pos = { standX, 8.4, -9.1 },
		size = { PW - 0.6, 0.3, 0.3 },
		color = C.steel,
		material = "Metal",
		shape = "Cylinder",
	})
	for _, dx in { -3, 0, 3 } do
		prop(parent, origin, {
			name = "ShowerStem",
			pos = { standX + dx, 8.1, -8.85 },
			size = { 0.18, 0.5, 0.18 },
			color = C.steel,
			material = "Metal",
		})
		prop(parent, origin, {
			name = "ShowerHead",
			pos = { standX + dx, 7.8, -8.85 },
			size = { 0.25, 0.8, 0.8 },
			color = C.steelDark,
			material = "Metal",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
	end

	-- A hose reel on a wall bracket. Its axle runs along the wall, so the plaza sees
	-- the wound green hose between two brass flanges rather than a flange face-on.
	-- The hose drops from the drum in a slanted run to a coil on the floor.
	local rx, ry, rz = standX + 2.6, 4.2, -8.3
	prop(parent, origin, {
		name = "ReelBracket",
		pos = { rx, ry, (WALL_FACE_Z + rz) / 2 + 0.1 },
		size = { 0.3, 0.3, rz - WALL_FACE_Z },
		color = C.steelDark,
		material = "Metal",
	})
	prop(parent, origin, {
		name = "ReelDrum",
		pos = { rx, ry, rz },
		size = { 1.4, 2.0, 2.0 },
		color = C.hoseGreen,
		material = "SmoothPlastic",
		shape = "Cylinder",
	})
	for _, dx in { -0.76, 0.76 } do
		prop(parent, origin, {
			name = "ReelFlange",
			pos = { rx + dx, ry, rz },
			size = { 0.12, 2.6, 2.6 },
			color = C.hoseBrass,
			material = "Metal",
			shape = "Cylinder",
		})
	end
	for i = 0, 5 do
		local t = i / 5
		prop(parent, origin, {
			name = "HoseRun",
			pos = { rx + 0.3 + t * 0.9, ry - 1.0 - t * 2.9, rz + 0.9 + t * 0.9 },
			size = { 0.35, 0.9, 0.35 },
			color = C.hoseGreenDark,
			material = "SmoothPlastic",
		})
	end
	prop(parent, origin, {
		name = "HoseCoil",
		pos = { rx + 1.6, 0.35, rz + 2.0 },
		size = { 0.35, 1.6, 1.6 },
		color = C.hoseGreenDark,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})

	-- A drain grate in the floor behind the stand, and a mop bucket beside it.
	local dx, dz = standX - 1.5, -6.4
	prop(parent, origin, {
		name = "DrainGrate",
		pos = { dx, 0.12, dz },
		size = { 2.2, 0.06, 2.2 },
		color = C.steelDark,
		material = "DiamondPlate",
	})
	for i = -2, 2 do
		prop(parent, origin, {
			name = "DrainSlot",
			pos = { dx + i * 0.4, 0.16, dz },
			size = { 0.12, 0.04, 2.0 },
			color = C.hazardBlack,
			material = "SmoothPlastic",
		})
	end
	prop(parent, origin, {
		name = "MopBucket",
		pos = { standX - 3.4, 0.8, -6.8 },
		size = { 1.4, 1.5, 1.5 },
		color = C.barrelYellow,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	prop(parent, origin, {
		name = "MopHandle",
		pos = { standX - 3.4, 2.6, -6.8 },
		size = { 0.12, 3.6, 0.12 },
		color = C.woodLight,
		material = "Wood",
		rot = Kit.ang(0, 0, 12),
	})

	-- A banded water tank on the roof over the stand, capped in the accent, with a
	-- pipe running back and down the rear of the stall toward the shower bar.
	roofPlinth(parent, origin, standX, 3.4, 3.4)
	for _, sx in { -1.2, 1.2 } do
		prop(parent, origin, {
			name = "TankSaddle",
			pos = { standX + sx, ROOF_Y + 0.9, ROOF_Z },
			size = { 0.3, 0.8, 3.0 },
			color = C.steelDark,
			material = "Metal",
		})
	end
	local tankY = ROOF_Y + 2.6
	prop(parent, origin, {
		name = "WaterTank",
		pos = { standX, tankY, ROOF_Z },
		size = { 3.4, 3.6, 3.6 },
		color = TANK_BLUE,
		material = "Metal",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	for _, dy in { -1.1, 0, 1.1 } do
		prop(parent, origin, {
			name = "TankBand",
			pos = { standX, tankY + dy, ROOF_Z },
			size = { 0.18, 3.75, 3.75 },
			color = C.steelDark,
			material = "Metal",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
	end
	prop(parent, origin, {
		name = "TankLid",
		pos = { standX, tankY + 1.9, ROOF_Z },
		size = { 0.3, 3.2, 3.2 },
		color = accent,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	prop(parent, origin, {
		name = "TankPipe",
		pos = { standX + 1.9, tankY - 0.4, ROOF_Z - 1.75 },
		size = { 0.3, 0.3, 3.5 },
		color = C.steel,
		material = "Metal",
	})
	prop(parent, origin, {
		name = "TankPipeDrop",
		pos = { standX + 1.9, 10.4, -8.9 },
		size = { 0.3, 4.4, 0.3 },
		color = C.steel,
		material = "Metal",
	})
end

-- ── Outfitter: the aura shop ──────────────────────────────────────────────────

local MANNEQUIN = "3A3F47"
local MANNEQUIN_DARK = "2A2E35"
local TUBE_GLASS = "CFE8F2"

--- `auraX` is the Aura counter's centre along the shopfront.
---
--- THE SUIT SHOP BECAME THE AURA SHOP. The hazmat Suit track is the Aura now (see
--- Shared/AuraLook), and the locker room went with the suits: a faceless mannequin
--- stands on the old suit stand behind the desk, three sample tubes either side hold
--- each tier's colour in ladder order (low to high, left to right as the customer
--- sees it), and a giant atom turns on the roof.
---
--- THE MANNEQUIN'S AURA IS THE ONE THING IN THE PLAZA THAT GLOWS, AND IT IS NOT BUILT
--- HERE. Its torso carries AuraLook.DISPLAY_TAG, and client/Controllers/AuraController
--- draws the same rings a player wears round it, walking the whole ladder
--- (`AuraCycle`). The shop therefore cannot drift from the product. Everything this
--- file builds still keeps the header's rule: no Neon, no lights.
---
--- The aura's rings reach RADIUS (2.5) round the torso, so the tubes start 3.4 out and
--- the torso stands 3.2 off the slat wall: the precessing rings clear both.
---
--- `camp` (a Config/Camps key) is the camp whose shop this is; nil is Base Camp. The
--- mannequin walks and the tubes show only the rungs that camp sells (Gear.tiersAt), so
--- a stall never models an aura it cannot sell. A camp's tubes start further out:
--- Toxic Twilight's corona and wings reach wider than any ring.
function ShopThemes.dressOutfitter(parent: Instance, origin: CFrame, auraX: number, camp: string?): Model
	local theme = Instance.new("Model")
	theme.Name = "Theme"
	local accent = C.shopOutfitter
	local tiers = Gear.tiersAt("Aura", camp or "base")
	local tubeStart = if camp then 4.8 else 3.4

	-- The mannequin: the old suit stand with an accent band, two legs, a torso, arms
	-- hanging a little out, a neck and a plain ball head. Dark slate, so the aura is
	-- the brightest thing in the stall.
	local mz = -6.5
	prop(theme, origin, {
		name = "MannequinStand",
		pos = { auraX, 0.2, mz },
		size = { 0.4, 2.4, 2.4 },
		color = C.hazardBlack,
		material = "Metal",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	prop(theme, origin, {
		name = "MannequinBand",
		pos = { auraX, 0.2, mz },
		size = { 0.14, 2.52, 2.52 },
		color = accent,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	for _, dx in { -0.45, 0.45 } do
		prop(theme, origin, {
			name = "MannequinLeg",
			pos = { auraX + dx, 1.5, mz },
			size = { 0.8, 2.2, 0.9 },
			color = MANNEQUIN_DARK,
			material = "SmoothPlastic",
		})
	end
	local torso = prop(theme, origin, {
		name = "MannequinTorso",
		pos = { auraX, 3.6, mz },
		size = { 2.0, 2.0, 1.0 },
		color = MANNEQUIN,
		material = "SmoothPlastic",
		-- Centred on the torso itself (no lift), at stock size, walking the ladder.
		attributes = { AuraCycle = true, AuraLift = 0, AuraScale = 1, AuraCamp = camp },
		-- Facing the customer, the way a wearer's LookVector (-Z) points. The atom and
		-- the helix look the same either way round; the corona and the wings have a back.
		rot = Kit.ang(0, 180, 0),
	})
	CollectionService:AddTag(torso, AuraLook.DISPLAY_TAG)
	for _, dx in { -1.35, 1.35 } do
		prop(theme, origin, {
			name = "MannequinArm",
			pos = { auraX + dx, 3.5, mz },
			size = { 0.7, 2.2, 0.8 },
			color = MANNEQUIN,
			material = "SmoothPlastic",
			rot = Kit.ang(0, 0, if dx > 0 then 8 else -8),
		})
	end
	prop(theme, origin, {
		name = "MannequinNeck",
		pos = { auraX, 4.75, mz },
		size = { 0.3, 0.6, 0.6 },
		color = MANNEQUIN_DARK,
		material = "SmoothPlastic",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	prop(theme, origin, {
		name = "MannequinHead",
		pos = { auraX, 5.45, mz },
		size = { 1.3, 1.3, 1.3 },
		color = MANNEQUIN,
		material = "SmoothPlastic",
		shape = "Ball",
	})

	-- A sample tube against the back wall per tier this stall sells, in the aura's own
	-- colour: the lower half left of the mannequin, the upper half right (Base Camp:
	-- tiers 1-3 left, 4-6 right), each a steel base and cap with an accent band, a
	-- glass tube and a coloured orb floating in it.
	local tubeZ = -8.2
	local leftCount = math.ceil(#tiers / 2)
	for index, tier in tiers do
		local look = AuraLook.get(tier)
		local side = if index <= leftCount then -1 else 1
		local slot = if index <= leftCount then leftCount - index + 1 else index - leftCount
		local x = auraX + side * (tubeStart + (slot - 1) * 1.5)
		prop(theme, origin, {
			name = "TubeBase",
			pos = { x, 0.25, tubeZ },
			size = { 0.5, 1.3, 1.3 },
			color = C.steelDark,
			material = "Metal",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
		prop(theme, origin, {
			name = "TubeGlass",
			pos = { x, 2.0, tubeZ },
			size = { 3.0, 1.0, 1.0 },
			color = TUBE_GLASS,
			material = "Glass",
			transparency = 0.55,
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
		prop(theme, origin, {
			name = "TubeOrb",
			pos = { x, 2.0, tubeZ },
			size = { 0.7, 0.7, 0.7 },
			color = look.color:ToHex(),
			material = "SmoothPlastic",
			shape = "Ball",
		})
		prop(theme, origin, {
			name = "TubeCap",
			pos = { x, 3.65, tubeZ },
			size = { 0.3, 1.3, 1.3 },
			color = C.steelDark,
			material = "Metal",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
		prop(theme, origin, {
			name = "TubeBand",
			pos = { x, 3.65, tubeZ },
			size = { 0.12, 1.36, 1.36 },
			color = accent,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
	end

	-- A giant atom on the roof, centred over the stall: a steel post off the plinth, an
	-- accent nucleus, three steel rings at the aura's own tilts and an accent electron
	-- on each. Everything but the post is one Model that StationMotionController turns
	-- slowly about its nucleus.
	roofPlinth(theme, origin, 0, 3, 2)
	local centre = origin * CFrame.new(0, ROOF_Y + 3, ROOF_Z)
	prop(theme, origin, {
		name = "AtomPost",
		pos = { 0, ROOF_Y + 1.6, ROOF_Z },
		size = { 1.8, 0.4, 0.4 },
		color = C.steelDark,
		material = "Metal",
		shape = "Cylinder",
		rot = R_CYL_UP,
	})
	local atom = Instance.new("Model")
	atom.Name = "RoofAtom"
	local nucleus = prop(atom, centre, {
		name = "AtomNucleus",
		pos = { 0, 0, 0 },
		size = { 1.4, 1.4, 1.4 },
		color = accent,
		material = "SmoothPlastic",
		shape = "Ball",
	})
	local ROOF_RING = 2
	local segments, length = AuraLook.segments(ROOF_RING, 20)
	for ring, tilt in AuraLook.TILTS do
		local frame = centre * CFrame.Angles(0, 0, tilt)
		for _, segment in segments do
			prop(atom, frame * segment, {
				name = "AtomRing",
				pos = { 0, 0, 0 },
				size = { length, 0.22, 0.22 },
				color = C.steel,
				material = "Metal",
				rot = CFrame.identity,
			})
		end
		local u = 0.6 + ring * 2.1
		prop(atom, frame, {
			name = "AtomElectron",
			pos = { math.cos(u) * ROOF_RING, 0, math.sin(u) * ROOF_RING },
			size = { 0.5, 0.5, 0.5 },
			color = accent,
			material = "SmoothPlastic",
			shape = "Ball",
		})
	end
	atom.PrimaryPart = nucleus
	atom.Parent = theme
	Kit.motion(atom, { kind = "spin", axis = "Y", rate = 0.5 })

	theme.Parent = parent
	return theme
end

-- ── Entry point for the track stalls ──────────────────────────────────────────

local DRESSERS: { [string]: (Instance, CFrame, number, number) -> () } = {
	Detector = dressDetector,
	Magnet = dressMagnet,
	Cleaner = dressCleaner,
}

--- Dress one track stall in its theme, under a "Theme" model inside `parent`.
--- `width` is the stall's full width and `standX` the stand's centre, both in the
--- stall's own frame. A track with no theme builds nothing and returns nil, so a
--- new track gets a plain stall until someone designs its theme.
function ShopThemes.dressStall(parent: Instance, origin: CFrame, track: string, width: number, standX: number): Model?
	local dresser = DRESSERS[track]
	if dresser == nil then
		return nil
	end
	local theme = Instance.new("Model")
	theme.Name = "Theme"
	dresser(theme, origin, width, standX)
	theme.Parent = parent
	return theme
end

return ShopThemes
