--!strict
--[[
	World.luau — build the whole map, then prove it.

	    require(game.ServerScriptService.Server.build.World).rebuild()
	    require(game.ServerScriptService.Server.build.World).verify()

	verify() is this map's answer to Shared/Util/Spec. Spec checks that the tuning
	numbers still describe the game the design document describes; verify() checks
	that the WORLD still satisfies the contracts the eight services read out of it.

	That distinction is the whole reason this function exists. Every one of these
	assertions corresponds to a real failure that is silent at build time and awful
	at play time:

	  * a plate named Stage2 with no StageId  -> signals spawn, nobody is ever in the
	                                           stage, and the field quietly fills up
	                                           with items no one can find
	  * a plate whose top face moved        -> items bury below the walk surface and
	                                           the haul is invisible
	  * a decoration carrying a StageId      -> smallest-area-wins makes a barrel the
	                                           stage you are standing in
	  * a stage overlapping the plaza        -> base camp irradiates you
	  * a station part without its tag      -> that one shop just does not work
	  * no respawn anchor                   -> blackout drops you at (0, 8, 0)

	None of those throw. All of them ruin the game. So they are checked here, and
	rebuild() runs the check for you.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Tuning = require(Shared.Config.Tuning)
local Gear = require(Shared.Config.Gear)

local Kit = require(script.Parent.Kit)
local BaseCamp = require(script.Parent.BaseCamp)
local Hub = require(script.Parent.Hub)
local StageFields = require(script.Parent.StageFields)
local Shops = require(script.Parent.Shops)
local Plots = require(script.Parent.Plots)
local Scenery = require(script.Parent.Scenery)
local Daylight = require(script.Parent.Daylight)

local World = {}

-- ── Build ─────────────────────────────────────────────────────────────────────

--- Rebuild every generated structure, each one atomically.
---
--- Order is dependency order, not importance order: the stage plates define the
--- frame everything else is measured against, and the scenery is placed relative to
--- them, so plates go down before anything sits on them.
function World.rebuild()
	local started = os.clock()

	StageFields.rebuild()
	Hub.rebuild()
	BaseCamp.rebuild(Hub.CAMP_ORIGIN)
	Shops.rebuild()
	Plots.rebuild()
	Scenery.rebuild()
	Daylight.apply()

	local elapsed = (os.clock() - started) * 1000
	print(`[build] world rebuilt in {string.format("%.0f", elapsed)}ms`)

	local ok, failures = World.verify()
	if ok then
		print("[build] verify: all world contracts hold")
	else
		warn(`[build] verify: {#failures} FAILURE(S)`)
		for _, f in failures do
			warn(`  - {f}`)
		end
	end
	return ok
end

-- ── Verify ────────────────────────────────────────────────────────────────────

local function rectsOverlap(a: { number }, b: { number }): boolean
	return not (a[3] <= b[1] or b[3] <= a[1] or a[4] <= b[2] or b[4] <= a[2])
end

--- Returns (ok, failures). Never throws — a verification pass that dies on its
--- first problem tells you about one thing when there might be six.
function World.verify(): (boolean, { string })
	local fail: { string } = {}
	local function check(condition: boolean, message: string)
		if not condition then
			table.insert(fail, message)
		end
	end

	-- ── Stage plates ──────────────────────────────────────────────────────
	local stageFolder = Workspace:FindFirstChild("Stages")
	check(stageFolder ~= nil, "Workspace.Stages is missing — DigService will never spawn a signal")

	if stageFolder then
		local expected: { [string]: boolean } = {}
		for _, id in Stages.builtIds() do
			expected[`Stage{id}`] = true
		end

		for _, child in stageFolder:GetChildren() do
			check(
				expected[child.Name] == true,
				`Workspace.Stages contains "{child.Name}", which is not a built stage. That folder must hold the plates and nothing else — decor belongs in Workspace.Scenery.`
			)
			check(child:IsA("BasePart"), `Workspace.Stages.{child.Name} is a {child.ClassName}; StageService only sees BaseParts`)
		end

		for _, id in Stages.builtIds() do
			local plate = stageFolder:FindFirstChild(`Stage{id}`)
			if plate == nil or not plate:IsA("BasePart") then
				check(false, `Stage{id} plate missing from Workspace.Stages`)
				continue
			end

			-- The two independent lookups must agree.
			check(plate:GetAttribute("StageId") == id, `Stage{id} has StageId {tostring(plate:GetAttribute("StageId"))} — DigService finds it by name, StageService by attribute, and they disagree`)

			-- Flat, or items surface underground / float.
			local rot = plate.CFrame - plate.CFrame.Position
			check(
				rot:FuzzyEq(CFrame.identity, 0.001),
				`Stage{id} is rotated. DigService buries on the flat top face; a tilted plate puts items under the visible ground.`
			)

			local topY = plate.Position.Y + plate.Size.Y / 2
			check(math.abs(topY - Stages.SURFACE_Y) < 0.01, `Stage{id} top face at {topY}, expected {Stages.SURFACE_Y}`)

			local maxDepth = Tuning.DIG_DEPTH_BASE + 7 * Tuning.DIG_DEPTH_PER_RARITY + Tuning.DIG_DEPTH_JITTER
			check(plate.Size.Y >= maxDepth, `Stage{id} is {plate.Size.Y} thick but items bury {maxDepth} deep — a haul would show through the underside`)

			check(plate.Anchored, `Stage{id} is not anchored`)
		end

		-- No two stages may overlap, and none may touch the plaza.
		local built = Stages.builtIds()
		for i = 1, #built do
			for j = i + 1, #built do
				local ax, az, bx, bz = Stages.bounds(built[i])
				local cx, cz, dx, dz = Stages.bounds(built[j])
				check(
					not rectsOverlap({ ax, az, bx, bz }, { cx, cz, dx, dz }),
					`Stage{built[i]} overlaps Stage{built[j]} — smallest-area-wins makes which one you are in non-obvious`
				)
			end

			-- Not a symmetric square any more (see Hub.PLAZA's own comment) — the
			-- plaza's east edge is DELIBERATELY exactly on Stage 1's west edge, so
			-- this has to accept touching, not just reject overlap. rectsOverlap
			-- already does (an exactly-shared edge fails `<`, not `<=`), which is
			-- the whole reason the connected layout is safe against this check.
			local ax, az, bx, bz = Stages.bounds(built[i])
			local p = Hub.PLAZA
			check(
				not rectsOverlap({ ax, az, bx, bz }, { p.minX, p.minZ, p.maxX, p.maxZ }),
				`Stage{built[i]} overlaps the hub plaza — base camp would irradiate the people standing in it`
			)
		end

		-- ── Every stage has to be REACHABLE ON FOOT ───────────────────────
		-- There is no terrain in this world: off the built parts is void. A stage with
		-- a gap between it and the nearest floor is a stage nobody can get to, and
		-- nothing else in this function would notice — it would have a correct plate,
		-- a correct attribute, correct thickness, and be unplayable.
		--
		-- This is a REACHABILITY check, not a contact check, so it is a flood fill
		-- rather than six independent tests. A stage counts as reached if it shares an
		-- edge with the camp landmass or with a stage already reached, which is what
		-- lets the east chain work: only Stage 1 touches camp, and 2, 3, 5 and 6 are
		-- reached through each other.
		local function touches(a: { number }, b: { number }): boolean
			-- Overlapping in one axis and sharing (or crossing) the boundary in the
			-- other. Tolerance because these come from centre/size arithmetic, not
			-- from integers: an edge that lands 0.0001 short is still an edge.
			local e = 0.01
			local xOverlap = a[3] >= b[1] - e and b[3] >= a[1] - e
			local zOverlap = a[4] >= b[2] - e and b[4] >= a[2] - e
			return xOverlap and zOverlap
		end

		-- The camp landmass: the plaza, plus one bounding square over the
		-- semicircular pad ring (Plots.RING_CENTER/RING_OUTER). (`p` above is
		-- scoped to the per-stage loop; this block runs after it.)
		--
		-- ONE SQUARE, NOT A TRACED CURVE. Every stage in this codebase chains
		-- reachability off the plaza rectangle alone -- Stages.DEFS is one
		-- straight chain starting at Stage 1, whose west edge is exactly
		-- Hub.PLAZA.maxX -- so the ring's own landmass has never actually been
		-- load-bearing for a stage's reachability, only for keeping this
		-- description honest. A single generous square still does that job:
		-- this check only ever produces a boolean "touches", never a rendered
		-- shape, so over-covering the ring's true circular footprint is
		-- harmless.
		local p = Hub.PLAZA
		local reached: { { number } } = {
			{ p.minX, p.minZ, p.maxX, p.maxZ },
			{
				Plots.RING_CENTER.x - Plots.RING_OUTER,
				Plots.RING_CENTER.z - Plots.RING_OUTER,
				Plots.RING_CENTER.x,
				Plots.RING_CENTER.z + Plots.RING_OUTER,
			},
		}

		local pending: { number } = table.clone(built)
		local grew = true
		while grew do
			grew = false
			for index = #pending, 1, -1 do
				local ax, az, bx, bz = Stages.bounds(pending[index])
				local rect = { ax, az, bx, bz }
				for _, land in reached do
					if touches(rect, land) then
						table.insert(reached, rect)
						table.remove(pending, index)
						grew = true
						break
					end
				end
			end
		end

		for _, id in pending do
			check(
				false,
				`Stage{id} does not touch the camp or any stage connected to it — there is no terrain in this world, so it is a plate across open void that no player can walk to`
			)
		end
	end

	-- ── Plot pads: on the ring, not in it ────────────────────────────────
	-- Six pads on the semicircular ring can absolutely land on the plaza, on a
	-- stage, or on each other, and every one of those is invisible until someone
	-- walks into a wall.
	--
	-- ORIENTED, NOT AXIS-ALIGNED. The old rectangular ring only ever used
	-- facings that were multiples of 90, so an axis-aligned bounding box (this
	-- function used to just swap width/depth at +/-90) was exact. None of the
	-- six facings on the semicircular ring are multiples of 90 any more, so
	-- this needs the pad's real, rotated footprint -- Kit.orientedRectsOverlap,
	-- the same separating-axis test Plots.luau's own apron uses to punch pads
	-- out of the walkway.
	local function padRect(centre: { x: number, z: number, facing: number }): Kit.OrientedRect
		return { cx = centre.x, cz = centre.z, halfWidth = Plots.PAD.width / 2, halfDepth = Plots.PAD.depth / 2, yawDeg = centre.facing }
	end

	-- An axis-aligned rectangle expressed the same way, so the plaza and a stage
	-- plate (both yaw 0) can be tested against a pad with the same function.
	local function axisRect(minX: number, minZ: number, maxX: number, maxZ: number): Kit.OrientedRect
		return { cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2, halfWidth = (maxX - minX) / 2, halfDepth = (maxZ - minZ) / 2, yawDeg = 0 }
	end

	local plaza = Hub.PLAZA
	local plazaRect = axisRect(plaza.minX, plaza.minZ, plaza.maxX, plaza.maxZ)
	for i, centre in Plots.CENTERS do
		local a = padRect(centre)

		check(
			not Kit.orientedRectsOverlap(a, plazaRect),
			`plot {i} overlaps the plaza — the pad is a step up, so it would sit in the middle of the pavement`
		)

		for _, id in Stages.builtIds() do
			local ax, az, bx, bz = Stages.bounds(id)
			check(
				not Kit.orientedRectsOverlap(a, axisRect(ax, az, bx, bz)),
				`plot {i} overlaps Stage{id} — a plot inside a stage irradiates whoever is standing on it`
			)
		end

		for j = i + 1, #Plots.CENTERS do
			check(
				not Kit.orientedRectsOverlap(a, padRect(Plots.CENTERS[j])),
				`plot {i} overlaps plot {j}`
			)
		end
	end

	-- ── Scenery may not pretend to be a stage ─────────────────────────────
	local scenery = Workspace:FindFirstChild("Scenery")
	if scenery then
		for _, d in scenery:GetDescendants() do
			check(d:GetAttribute("StageId") == nil, `scenery part {d.Name} carries a StageId and would register as a stage`)
		end
	end

	-- ── Stations: attribute and tag must agree, both directions ──────────
	local census: { [string]: number } = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			local kind = d:GetAttribute("StationKind") :: string?
			if kind then
				census[kind] = (census[kind] or 0) + 1
				check(
					CollectionService:HasTag(d, Kit.STATION_TAG),
					`{d:GetFullName()} has StationKind="{kind}" but no "{Kit.STATION_TAG}" tag — StationService scans by tag and will never see it`
				)
			end
		end
	end
	for _, tagged in CollectionService:GetTagged(Kit.STATION_TAG) do
		if tagged:IsDescendantOf(Workspace) then
			check(
				tagged:GetAttribute("StationKind") ~= nil,
				`{tagged:GetFullName()} is tagged as a station but has no StationKind`
			)
		end
	end

	-- No trader in the world by design as of this pass — BaseCamp.luau dropped it
	-- along with the camp's walls, and nothing has replaced it yet. Not asserting
	-- a count here at all: EconomyService.sell still exists and still works, it
	-- just currently has nothing in the world that can trigger it. If a trader
	-- (or any other sell point) comes back, give this an == check again.
	-- One cleansing station per base now, not one shared station at camp.
	check(
		(census.decon or 0) == Plots.COUNT,
		`expected {Plots.COUNT} decon stations (one per base), found {census.decon or 0}`
	)
	-- NOT `>= #Gear.TRACKS` any more. That equated "a track" with "a shop counter",
	-- which stopped being true when Luck moved to a wooden sign with a prompt — and it
	-- was always the weaker statement anyway: a COUNT cannot tell you *which* track is
	-- missing, and the per-track coverage loop below can, across both selling
	-- mechanisms. This is left as a floor so that "the shops model failed to build at
	-- all" still trips something loud and specific.
	check((census.shop or 0) > 0, `no shop counters in the world at all, found {census.shop or 0}`)
	check((census.plot or 0) == Plots.COUNT, `expected {Plots.COUNT} plot boards, found {census.plot or 0}`)
	-- One wash pad per base, beside that base's cleansing station (Plots.buildWashPad).
	check(
		(census.roller or 0) == Plots.COUNT,
		`expected {Plots.COUNT} wash pads (one per base), found {census.roller or 0}`
	)

	-- ...and one luck sign per base, beside the pad it bends the odds for.
	local luckSigns = 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("SellsTrack") == "Luck" then
			luckSigns += 1
		end
	end
	check(luckSigns == Plots.COUNT, `expected {Plots.COUNT} luck signs (one per base), found {luckSigns}`)

	-- Every priced track must be buyable somewhere. TWO WAYS TO SELL ONE now, and the
	-- check has to know both or moving a track between them looks like a clean
	-- refactor and is actually a priced dead end:
	--
	--   StationKind = "shop"   a counter with a panel  (Detector, Magnet, Cleaner,
	--                          Suit, Boots, Satchel)
	--   SellsTrack = "<track>" a world object with a ProximityPrompt, no panel
	--                          (Luck, on the wooden sign at every base)
	local sells: { [string]: boolean } = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("StationKind") == "shop" then
				sells[d:GetAttribute("StationId") :: string] = true
			end
			local direct = d:GetAttribute("SellsTrack")
			if type(direct) == "string" then
				sells[direct] = true
				-- A sign with no prompt is invisible to ShopService and sells nothing.
				check(
					d:FindFirstChildOfClass("ProximityPrompt") ~= nil,
					`{d:GetFullName()} sells "{direct}" but has no ProximityPrompt — nobody can buy from it`
				)
				check(
					CollectionService:HasTag(d, Kit.UPGRADE_TAG),
					`{d:GetFullName()} has SellsTrack but no "{Kit.UPGRADE_TAG}" tag — ShopService scans by tag and will never wire it`
				)
			end
		end
	end
	for _, track in Gear.TRACKS do
		check(sells[track] == true, `no shop sells "{track}" — it has prices in Gear.luau and nowhere to spend them`)
	end

	-- THE WASH PAD AND THE CLEANSING STATION MUST NOT OVERLAP, and this is a real
	-- correctness check rather than a layout preference. Rolling fires off
	-- StationService's ENTRY EDGE and charges cash, so a player scrubbing at the
	-- basin who drifts into an overlapping roller radius is billed for a roll they
	-- never asked for. Nearest-wins settles which panel opens; it does not settle
	-- which edges fire. See Plots.buildWashPad for the numbers this protects.
	local rollers: { BasePart } = {}
	local decons: { BasePart } = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") then
			local kind = d:GetAttribute("StationKind")
			if kind == "roller" then
				table.insert(rollers, d)
			elseif kind == "decon" then
				table.insert(decons, d)
			end
		end
	end
	for _, roller in rollers do
		for _, decon in decons do
			local reach = ((roller:GetAttribute("Radius") :: number?) or 12) + ((decon:GetAttribute("Radius") :: number?) or 12)
			local gap = (roller.Position - decon.Position).Magnitude
			check(
				gap > reach,
				`{roller:GetFullName()} and {decon:GetFullName()} are {gap // 1} studs apart but reach {reach} — walking between them would bill an unasked-for roll`
			)
		end
	end

	-- ── Spawning ─────────────────────────────────────────────────────────
	check(
		Workspace:FindFirstChild("RespawnAnchor", true) ~= nil,
		"no RespawnAnchor in Workspace — blackout falls back to a hardcoded (0, 8, 0)"
	)

	-- No SpawnLocation is Enabled at build time by design, not oversight — there is
	-- no camp-wide fallback spawn any more. Every one of the 6 PlotSpawns starts
	-- disabled and is switched on (plus the player teleported to it directly) by
	-- ExhibitService.assign() the moment that player's plot is decided, so "zero
	-- enabled right after a fresh build, before anyone has joined" is the correct
	-- state, not a bug. What this checks instead: the CAPACITY to spawn someone
	-- exists at all — one SpawnLocation per plot, ready for assign() to claim.
	local spawnCount = 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("SpawnLocation") then
			spawnCount += 1
		end
	end
	check(spawnCount == Plots.COUNT, `expected {Plots.COUNT} SpawnLocations (one per plot), found {spawnCount} — a player assigned a plot with none would have nowhere to spawn`)

	check(Workspace.Terrain:GetAttribute("StageId") == nil, "Terrain carries a StageId")

	return #fail == 0, fail
end

--- Coverage report — how searchable each stage actually is at a given detector tier.
--- Prints rather than asserts: this is a tuning aid, and Spec owns the assertion.
function World.coverageReport()
	print("[build] stage search coverage (target c ~= 0.26 at the stage's rated tier)")
	for _, id in Stages.builtIds() do
		local def = Stages.get(id)
		local radius = Gear.tier("Detector", def.ratedSuitTier).radius
		local c = Stages.coverage(id, radius, Tuning.SIGNALS_PER_STAGE)
		local gap = Stages.meanSignalGap(id, Tuning.SIGNALS_PER_STAGE)
		print(string.format("  %-20s area %-8d r=%-3d c=%.3f  mean gap %.0f studs", def.name, Stages.area(id), radius, c, gap))
	end
end

return World
