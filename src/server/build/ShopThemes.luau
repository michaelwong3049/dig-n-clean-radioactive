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
	  * OUTFITTER (the Aura Shop) — a row of faceless mannequins, one per rung, each
	    wearing that rung's live aura, and a giant atom turning on the roof. It was a locker room round a hazmat suit until the Suit
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

-- THE STALLS ARE ISLANDS (2026-09-27): open front and back, the rack on the centre line
-- (Shops' ISLAND_Z), and a short two-sided slat spine on that line over the stand end,
-- with a stand either side of it. The stand-end props were laid out against the old back
-- wall at z = -10, and they still are, in their own frame: SIDE_SHIFT slides that frame
-- forward so WALL_FACE_Z lands on the spine's front face, and dressStall lays the same
-- props a second time, turned round, on its back face. The spine leaves ~3 studs between
-- its face and the stand's back edge (old z -6.65), so floor props stay behind that line.
local ISLAND_Z = -4
local SIDE_SHIFT = 6

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

local function dressDetector(parent: Instance, origin: CFrame, width: number, standX: number, part: string)
	local accent = C.shopDetector

	if part == "side" then
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
	end

	if part == "roof" then
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
	end

	if part == "side" then
		-- A surveyor's tripod behind the stand's outer end: three splayed wooden legs,
		-- a steel head, a yellow instrument body and its lens toward the plaza.
		local tx, tz = standX - 2.6, -8.2
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
	end

	if part == "roof" then
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
end

-- ── Magnet: the scrapyard ─────────────────────────────────────────────────────

local SCRAP_RUST = "B5653A"
local SCRAP_TAN = "A07B4E"
local CRANE_YELLOW = C.barrelYellow

local function dressMagnet(parent: Instance, origin: CFrame, _width: number, standX: number, part: string)
	if part == "roof" then
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
	end

	if part == "side" then
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
		local px, pz = standX - 2.4, -8.1
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
						pz + rng:NextNumber(-spread * 0.6, spread * 0.6),
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
			pos = { px + 1.1, 0.9, pz + 0.5 },
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
end

-- ── Cleaner (the Hose Shop): the decon bay ────────────────────────────────────

local TILE = "D6ECF7"
local GROUT = "8FB8D0"
local TANK_BLUE = "7FB9D6"

local function dressCleaner(parent: Instance, origin: CFrame, _width: number, standX: number, part: string)
	local accent = C.shopCleaner

	if part == "side" then
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
				pos = { rx + 0.3 + t * 0.9, ry - 1.0 - t * 2.9, rz + 0.5 + t * 0.6 },
				size = { 0.35, 0.9, 0.35 },
				color = C.hoseGreenDark,
				material = "SmoothPlastic",
			})
		end
		prop(parent, origin, {
			name = "HoseCoil",
			pos = { rx + 1.6, 0.35, rz + 1.1 },
			size = { 0.35, 1.6, 1.6 },
			color = C.hoseGreenDark,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})

		-- A drain grate in the floor behind the stand, and a mop bucket beside it.
		local dx, dz = standX - 1.5, -8.0
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
			pos = { standX - 3.4, 0.8, -8.2 },
			size = { 1.4, 1.5, 1.5 },
			color = C.barrelYellow,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
		prop(parent, origin, {
			name = "MopHandle",
			pos = { standX - 3.4, 2.6, -8.2 },
			size = { 0.12, 3.6, 0.12 },
			color = C.woodLight,
			material = "Wood",
			rot = Kit.ang(0, 0, 12),
		})
	end

	if part == "roof" then
		-- A banded water tank on the roof over the stand, capped in the accent, with a
		-- pipe running forward and down into the top of the spine the showers hang on.
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
			pos = { standX + 1.9, tankY - 0.4, (ROOF_Z + ISLAND_Z) / 2 },
			size = { 0.3, 0.3, ISLAND_Z - ROOF_Z },
			color = C.steel,
			material = "Metal",
		})
		prop(parent, origin, {
			name = "TankPipeDrop",
			pos = { standX + 1.9, 10.4, ISLAND_Z },
			size = { 0.3, 4.4, 0.3 },
			color = C.steel,
			material = "Metal",
		})
	end
end

-- ── Outfitter: the aura shop ──────────────────────────────────────────────────

local MANNEQUIN = "3A3F47"
local MANNEQUIN_DARK = "2A2E35"

--- `slots` is one entry per rung the shop sells: `x` along the stall and the `tier` that
--- mannequin wears. `scale` is the mannequins' size (Shops' AURA_DISPLAY_SCALE).
---
--- THE SUIT SHOP BECAME THE AURA SHOP. The hazmat Suit track is the Aura now (see
--- Shared/AuraLook), and the locker room went with the suits. Since 2026-09-27 the shop
--- shows every rung it sells on its own faceless mannequin, in a row on the centre line
--- under the rail the rungs' mounts hang from (the tool stalls' rack, for auras), with a
--- giant atom turning on the roof. That replaced one mannequin walking the ladder and a
--- sample tube per tier.
---
--- THE MANNEQUINS' AURAS ARE THE ONE THING IN THE PLAZA THAT GLOWS, AND THEY ARE NOT
--- BUILT HERE. Each torso carries AuraLook.DISPLAY_TAG and its rung as `AuraTier`, and
--- client/Controllers/AuraController draws the same rings a player wears round it. The
--- shop therefore cannot drift from the product. Everything this file builds still keeps
--- the header's rule: no Neon, no lights.
function ShopThemes.dressOutfitter(parent: Instance, origin: CFrame, slots: { { x: number, tier: number } }, scale: number): Model
	local theme = Instance.new("Model")
	theme.Name = "Theme"
	local accent = C.shopOutfitter

	-- One mannequin per rung, on the island's centre line under that rung's mount
	-- (Shops' buildOutfitterAt): the old suit stand with an accent band, two legs, a
	-- torso, arms hanging a little out, a neck and a plain ball head, all at `scale`.
	-- Dark slate, so the aura is the brightest thing in the stall.
	for _, slot in slots do
		local base = origin * CFrame.new(slot.x, 0, ISLAND_Z)
		local function part(spec: Kit.Spec): BasePart
			local p = spec.pos :: { number }
			spec.pos = { p[1] * scale, p[2] * scale, p[3] * scale }
			local size = spec.size :: { number }
			spec.size = { size[1] * scale, size[2] * scale, size[3] * scale }
			return prop(theme, base, spec)
		end
		part({
			name = "MannequinStand",
			pos = { 0, 0.25, 0 },
			size = { 0.4, 2.4, 2.4 },
			color = C.hazardBlack,
			material = "Metal",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
		part({
			name = "MannequinBand",
			pos = { 0, 0.25, 0 },
			size = { 0.14, 2.52, 2.52 },
			color = accent,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
		for _, dx in { -0.45, 0.45 } do
			part({
				name = "MannequinLeg",
				pos = { dx, 1.5, 0 },
				size = { 0.8, 2.2, 0.9 },
				color = MANNEQUIN_DARK,
				material = "SmoothPlastic",
			})
		end
		local torso = part({
			name = "MannequinTorso",
			pos = { 0, 3.6, 0 },
			size = { 2.0, 2.0, 1.0 },
			color = MANNEQUIN,
			material = "SmoothPlastic",
			-- This rung's aura, centred on the torso (no lift), at the mannequin's scale.
			attributes = { AuraTier = slot.tier, AuraLift = 0, AuraScale = scale },
			-- Facing the front customers, the way a wearer's LookVector (-Z) points.
			rot = Kit.ang(0, 180, 0),
		})
		CollectionService:AddTag(torso, AuraLook.DISPLAY_TAG)
		for _, dx in { -1.35, 1.35 } do
			part({
				name = "MannequinArm",
				pos = { dx, 3.5, 0 },
				size = { 0.7, 2.2, 0.8 },
				color = MANNEQUIN,
				material = "SmoothPlastic",
				rot = Kit.ang(0, 0, if dx > 0 then 8 else -8),
			})
		end
		part({
			name = "MannequinNeck",
			pos = { 0, 4.75, 0 },
			size = { 0.3, 0.6, 0.6 },
			color = MANNEQUIN_DARK,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R_CYL_UP,
		})
		part({
			name = "MannequinHead",
			pos = { 0, 5.45, 0 },
			size = { 1.3, 1.3, 1.3 },
			color = MANNEQUIN,
			material = "SmoothPlastic",
			shape = "Ball",
		})
	end

	-- A giant atom over the roof, centred over the stall: an accent nucleus, three steel
	-- rings at the aura's own tilts and an accent electron on each, one Model that
	-- StationMotionController turns slowly about its nucleus. It floats with no post
	-- (2026-09-27, on request: the mast read as a stray pole). ATOM_Y still clears the
	-- tall shopfront's sign board (top ~16 studs up, Shops' buildShopfront).
	local ATOM_Y = ROOF_Y + 8.7
	local centre = origin * CFrame.new(0, ATOM_Y, ROOF_Z)
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

local DRESSERS: { [string]: (Instance, CFrame, number, number, string) -> () } = {
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
	dresser(theme, origin, width, standX, "roof")
	-- The stand-end props on both faces of the spine: once facing the front, once
	-- turned 180 degrees about the stand's centre on the centre line (see SIDE_SHIFT).
	local front = origin * CFrame.new(0, 0, SIDE_SHIFT)
	local back = origin * CFrame.new(standX, 0, ISLAND_Z) * CFrame.Angles(0, math.pi, 0) * CFrame.new(-standX, 0, -ISLAND_Z)
	dresser(theme, front, width, standX, "side")
	dresser(theme, back * CFrame.new(0, 0, SIDE_SHIFT), width, standX, "side")
	theme.Parent = parent
	return theme
end

return ShopThemes
