--!strict
--[[
	Scenery.luau — barrels, spills and rubble. Everything on the zones that is not
	the zone.

	    require(game.ServerScriptService.Server.build.Scenery).rebuild()

	WHY THIS IS A SEPARATE MODULE FROM ZoneFields.
	Workspace.Zones must contain the one radioactive plate and NOTHING else. ZoneService walks
	that folder's children ten times a second per player, and — much worse — a prop
	that accidentally carried a ZoneId attribute would register as a zone. Overlapping
	zones resolve as "smallest XZ area wins", so one stray barrel would silently
	become the zone every nearby player is standing in. Keeping decor in a different
	folder makes that class of bug impossible rather than merely unlikely.

	THE OOZE IS THE SURFACE, NOT A HAZARD.
	Per the design call: the plate itself is the sludge you wade through, and the
	pools and spills here are visual variation with NO gameplay rules attached.
	ZoneService.hotPocketFor stays a stub returning 1. This matters for a young
	audience — one rule ("the green ground is dangerous, the paths are not") beats
	two rules ("...but the BRIGHT green is extra dangerous") when the second one is
	only telegraphed by shade.

	"WADE THROUGH" IS NOW LITERAL, NOT JUST WORDING. `OozeSurface` is one
	translucent Neon plate per zone, sized to the whole plate, floating
	`WADE_HEIGHT` above the real floor — about half a leg on a default character.
	Walking into the field sinks your legs into visible ooze instead of just
	standing on tinted ground. It is a SEPARATE part from the actual walking
	surface, not a raised version of it: `Zones.SURFACE_Y` (what DigService buries
	against and what a player's feet actually rest on) never moves. CanCollide is
	false, same as everything else in this file, so it changes nothing about
	movement, burial, or exposure — purely a second, higher, see-through layer.

	NOTHING HERE MAY RISE THROUGH THE DIG SURFACE IN A WAY THAT HIDES IT.
	DigService buries items on the plate's top face and the haul part rises to
	exactly that plane, so anything opaque and tall enough to block the view would
	hide an item surfacing underneath. Props are thin and sit just above;
	anything tall is CanCollide=false so a player can walk out of it.
	`OozeSurface` is the one exception that legitimately sits well above the
	plane — but it stays translucent for exactly this reason, so a surfacing item
	is dimmed, never hidden.

	Placement is a jittered grid, not pure random. Pure random clumps and leaves bald
	patches; a jittered grid reads as scattered while still covering the field, and
	it is deterministic per zone so a rebuild does not reshuffle the whole world.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Zones = require(Shared.Config.Zones)

local Kit = require(script.Parent.Kit)

local Scenery = {}
local BUILDER_SOURCE = "src/server/build/Scenery.luau"
local BUILDER_VERSION = 2

local C, R = Kit.C, Kit.R
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

--- Just above the plate's top face — close enough to read as lying on the ground,
--- high enough not to z-fight with it.
local SKIM = 0.26

--- Roughly half a leg's height on a default character, so walking into the field
--- reads as WADING into the ooze rather than standing on tinted ground. Purely
--- visual: this is a separate, CanCollide=false plate floating above the real
--- floor, never the floor itself. DigService buries against and a player's actual
--- footing rests on Zones.SURFACE_Y exactly as before -- moving that plane is
--- exactly what ZoneFields.luau's header warns never to do ("tilt or bump a
--- plate and items surface underground"). This gets the same visual without
--- touching it.
local WADE_HEIGHT = 1.1

--- Per-zone character. `props` is roughly how many set pieces to scatter; the pool
--- count scales with area so a big zone does not look empty.
--- Pool counts climb with the zone: Ash Flats is barely contaminated, the Belt is
--- more ooze than ground. That gradient is the map teaching you what "deeper" means
--- before any number on the HUD does.
local THEME = {
	[1] = { props = 26, pools = 26, kind = "trees" },
	[2] = { props = 34, pools = 40, kind = "houses" },
	[3] = { props = 40, pools = 58, kind = "sirens" },
	[4] = { props = 18, pools = 46, kind = "barriers" },
}

--- A leaking barrel: the story prop. Tipped or standing, always dripping.
local function barrel(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	local tipped = rng:NextNumber() < 0.35
	local color = if rng:NextNumber() < 0.5 then C.barrelYellow else C.barrelRust

	build(parent, origin, {
		name = "Barrel",
		pos = { x, if tipped then 1.1 else 2.1, z },
		size = { 4.2, 2.4, 2.4 },
		color = color,
		material = "Metal",
		shape = "Cylinder",
		rot = if tipped then R.cylAlongZ else R.cylUpFlipped,
	})

	-- The spill coming out of it. This is the bit that sells "oozing".
	local spillW = rng:NextNumber(8, 14)
	local spill = build(parent, origin, {
		name = "Spill",
		pos = { x + rng:NextNumber(-3, 3), SKIM, z + rng:NextNumber(-3, 3) },
		size = { 0.44, spillW, spillW },
		color = C.oozeBright,
		material = "Neon",
		shape = "Cylinder",
		rot = R.cylUp,
		transparency = 0.04,
		canCollide = false,
	})
	light(spill, C.oozeBright, 18, 2)
end

--- Zone-specific silhouette, so the four fields do not read as one field.
local function prop(parent: Instance, origin: CFrame, kind: string, x: number, z: number, rng: Random)
	if kind == "trees" then
		build(parent, origin, {
			name = "DeadTree",
			pos = { x, 4, z },
			size = { 1.1, 8, 1.1 },
			color = C.wood,
			material = "Wood",
			canCollide = false,
		})
		for _ = 1, 3 do
			build(parent, origin, {
				name = "Branch",
				pos = { x + rng:NextNumber(-1.8, 1.8), rng:NextNumber(5, 7.5), z + rng:NextNumber(-1.8, 1.8) },
				size = { 3.2, 0.35, 0.35 },
				color = C.wood,
				material = "Wood",
				rot = Kit.ang(0, rng:NextNumber(0, 180), rng:NextNumber(-25, 25)),
				canCollide = false,
			})
		end
	elseif kind == "houses" then
		-- A collapsed shell: two standing walls and a leaning roof slab.
		local w = rng:NextNumber(9, 15)
		build(parent, origin, { name = "Wall", pos = { x, 3, z }, size = { w, 6, 0.8 }, color = C.plazaWarm, material = "Brick" })
		build(parent, origin, { name = "Wall", pos = { x - w / 2, 2.4, z + 5 }, size = { 0.8, 5, 10 }, color = C.plazaEdge, material = "Brick" })
		build(parent, origin, {
			name = "RoofSlab",
			pos = { x + 2, 4.4, z + 6 },
			size = { w, 0.6, 9 },
			color = C.barrelRust,
			material = "Slate",
			rot = Kit.ang(0, 0, rng:NextNumber(14, 26)),
			canCollide = false,
		})
	elseif kind == "sirens" then
		build(parent, origin, { name = "SirenPost", pos = { x, 6, z }, size = { 0.8, 12, 0.8 }, color = C.steelDark, material = "Metal" })
		local head = build(parent, origin, {
			name = "SirenHead",
			pos = { x, 12.4, z },
			size = { 2.6, 1.8, 2.6 },
			color = C.barrelRust,
			material = "Neon",
			canCollide = false,
		})
		light(head, C.barrelRust, 22, 2)
	else -- "barriers" — Zone 4. Sparse on purpose: PLAN §15 wants it content-free.
		build(parent, origin, {
			name = "Barrier",
			pos = { x, 1.6, z },
			size = { 9, 3.2, 1.4 },
			color = C.plazaEdge,
			material = "Concrete",
			rot = Kit.ang(0, rng:NextNumber(-40, 40), 0),
		})
		build(parent, origin, {
			name = "HazardStripe",
			pos = { x, 3.3, z },
			size = { 9, 0.4, 1.5 },
			color = C.barrelYellow,
			material = "Neon",
			canCollide = false,
		})
	end
end

local function buildZoneScenery(parent: Instance, id: number)
	local theme = THEME[id]
	if theme == nil then
		return
	end

	local def = Zones.get(id)
	local folder = Instance.new("Folder")
	folder.Name = `Zone{id}`

	-- Deterministic per zone: a rebuild reproduces the same field, so "it looked
	-- better before" is never something you have to chase.
	local rng = Random.new(1000 + id)

	-- Everything is placed relative to the zone's own surface plane.
	local origin = CFrame.new(def.center[1], Zones.SURFACE_Y, def.center[2])
	local hx, hz = def.size[1] / 2 - 14, def.size[2] / 2 - 14

	-- The wading surface: one translucent plate over the WHOLE zone, raised to
	-- WADE_HEIGHT, so the field reads as something you sink into rather than
	-- ground that happens to be green. Sized to the actual plate (not inset like
	-- the pools/props below), so its edge lines up with the zone boundary.
	build(folder, origin, {
		name = "OozeSurface",
		pos = { 0, WADE_HEIGHT, 0 },
		size = { def.size[1], 0.3, def.size[2] },
		color = C.oozeBright,
		material = "Neon",
		-- High transparency on purpose. Neon's brightness is emissive rather than
		-- a true translucent tint, and bloom pushes an opaque-looking plate this
		-- size to a wall of solid colour well before Transparency looks like it
		-- "should" (0.55 first pass still read as solid ground, not a layer over
		-- it). 0.82 is the point props and the sand below actually show through.
		transparency = 0.82,
		canCollide = false,
	})

	-- Ooze pools first, so props sit on top of them.
	for _ = 1, theme.pools do
		local x, z = rng:NextNumber(-hx, hx), rng:NextNumber(-hz, hz)
		local d = rng:NextNumber(18, 46)
		local pool = build(folder, origin, {
			name = "OozePool",
			pos = { x, SKIM, z },
			-- A Cylinder's axis is its X size, so this is {thickness, diameter,
			-- diameter}. Writing it {d, 0.5, d} makes a thin ellipse standing on
			-- edge instead of a puddle -- which is exactly what the first pass did,
			-- and why the fields looked like bare lawn.
			size = { 0.5, d, d },
			color = C.oozeBright,
			material = "Neon",
			shape = "Cylinder",
			rot = R.cylUp,
			-- Near-opaque on purpose. Transparent Neon over a green plate is
			-- invisible in daylight -- the first pass looked like a lawn.
			transparency = 0.06,
			canCollide = false,
		})
		-- A darker rim, so a pool reads as a hole full of something rather than as
		-- a decal painted on the floor.
		build(folder, origin, {
			name = "OozeRim",
			pos = { x, SKIM - 0.12, z },
			size = { 0.4, d + 5, d + 5 },
			color = C.oozeDeep,
			material = "SmoothPlastic",
			shape = "Cylinder",
			rot = R.cylUp,
			canCollide = false,
		})
		light(pool, C.ooze, 26, 2)
	end

	-- Then barrels and set pieces on a jittered grid.
	local cols = math.ceil(math.sqrt(theme.props))
	local placed = 0
	for row = 0, cols - 1 do
		for col = 0, cols - 1 do
			if placed >= theme.props then
				break
			end
			placed += 1

			local x = -hx + (col + 0.5) * (2 * hx / cols) + rng:NextNumber(-12, 12)
			local z = -hz + (row + 0.5) * (2 * hz / cols) + rng:NextNumber(-12, 12)
			x = math.clamp(x, -hx, hx)
			z = math.clamp(z, -hz, hz)

			if placed % 2 == 0 then
				barrel(folder, origin, x, z, rng)
			else
				prop(folder, origin, theme.kind, x, z, rng)
			end
		end
	end

	folder.Parent = parent
end

--- Three readable progression gates inside the one radioactive field. They are
--- deliberately open in the centre for now: the visual contract and unlock tier
--- are present, while the future progression service can own opening the gate
--- without turning Workspace.Zones into three separate radiation zones.
local function buildStageGates(parent: Instance, zoneId: number)
	local def = Zones.get(zoneId)
	local folder = Instance.new("Folder")
	folder.Name = "RadiationStageGates"
	local origin = CFrame.new(def.center[1], Zones.SURFACE_Y, def.center[2])
	local halfDepth = def.size[2] / 2
	local opening = 18

	for _, stage in Zones.STAGES do
		local gate = Instance.new("Model")
		gate.Name = `Stage{stage.id}Gate`
		local x = stage.minX
		local segmentDepth = halfDepth - opening / 2

		for _, side in { -1, 1 } do
			build(gate, origin, {
				name = `Wall_{side}`,
				pos = { x, 5, side * (opening / 2 + segmentDepth / 2) },
				size = { 2, 10, segmentDepth },
				color = stage.color,
				material = "Concrete",
				attributes = { StageId = stage.id, UnlockTier = stage.unlockTier },
			})
		end

		local leftPost = build(gate, origin, {
			name = "GatePostLeft",
			pos = { x, 5, -opening / 2 },
			size = { 3, 10, 2 },
			color = stage.color,
			material = "Metal",
			attributes = { StageId = stage.id, UnlockTier = stage.unlockTier },
		})
		local rightPost = build(gate, origin, {
			name = "GatePostRight",
			pos = { x, 5, opening / 2 },
			size = { 3, 10, 2 },
			color = stage.color,
			material = "Metal",
			attributes = { StageId = stage.id, UnlockTier = stage.unlockTier },
		})

		local sign = build(gate, origin, {
			name = "StageSign",
			pos = { x, 11, 0 },
			size = { 12, 3, 0.5 },
			color = stage.color,
			material = "Neon",
			canCollide = false,
			attributes = { StageId = stage.id, UnlockTier = stage.unlockTier },
		})
		billboard(sign, 180, 3.6, `STAGE {stage.id}`, stage.name, stage.color)
		light(leftPost, stage.color, 16, 1.2)
		light(rightPost, stage.color, 16, 1.2)

		gate.Parent = folder
	end

	folder.Parent = parent
end

local function createScenery(): Model
	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	Kit.stamp(scenery, BUILDER_SOURCE, BUILDER_VERSION)

	for _, id in Zones.builtIds() do
		buildZoneScenery(scenery, id)
	end
	buildStageGates(scenery, 1)

	-- Nothing in here may claim to be a zone. This is the invariant the whole
	-- module/folder split exists to protect, so it is asserted, not trusted.
	for _, d in scenery:GetDescendants() do
		assert(d:GetAttribute("ZoneId") == nil, `scenery part {d:GetFullName()} carries a ZoneId — it would register as a zone`)
	end

	return scenery
end

function Scenery.build(parent: Instance?): Model
	local scenery = createScenery()
	scenery.Parent = parent or Workspace
	return scenery
end

function Scenery.rebuild(parent: Instance?): Model
	local scenery = Kit.swap("Scenery", createScenery, parent) :: Model
	print(`[build] Scenery rebuilt — {#scenery:GetDescendants()} parts`)
	return scenery
end

return Scenery
