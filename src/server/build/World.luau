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

	  * a plate named Zone2 with no ZoneId  -> signals spawn, nobody is ever in the
	                                           zone, and the field quietly fills up
	                                           with items no one can find
	  * a plate whose top face moved        -> items bury below the walk surface and
	                                           the haul is invisible
	  * a decoration carrying a ZoneId      -> smallest-area-wins makes a barrel the
	                                           zone you are standing in
	  * a zone overlapping the plaza        -> base camp irradiates you
	  * a station part without its tag      -> that one shop just does not work
	  * no respawn anchor                   -> blackout drops you at (0, 8, 0)

	None of those throw. All of them ruin the game. So they are checked here, and
	rebuild() runs the check for you.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Zones = require(Shared.Config.Zones)
local Tuning = require(Shared.Config.Tuning)
local Gear = require(Shared.Config.Gear)

local Kit = require(script.Parent.Kit)
local BaseCamp = require(script.Parent.BaseCamp)
local Hub = require(script.Parent.Hub)
local ZoneFields = require(script.Parent.ZoneFields)
local Shops = require(script.Parent.Shops)
local Plots = require(script.Parent.Plots)
local Scenery = require(script.Parent.Scenery)

local World = {}

-- ── Build ─────────────────────────────────────────────────────────────────────

--- Rebuild every generated structure, each one atomically.
---
--- Order is dependency order, not importance order: the zone plates define the
--- frame everything else is measured against, and the scenery is placed relative to
--- them, so plates go down before anything sits on them.
function World.rebuild()
	local started = os.clock()

	ZoneFields.rebuild()
	Hub.rebuild()
	BaseCamp.rebuild(Hub.CAMP_ORIGIN)
	Shops.rebuild()
	Plots.rebuild()
	Scenery.rebuild()

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

	-- ── Zone plates ──────────────────────────────────────────────────────
	local zoneFolder = Workspace:FindFirstChild("Zones")
	check(zoneFolder ~= nil, "Workspace.Zones is missing — DigService will never spawn a signal")

	if zoneFolder then
		local expected: { [string]: boolean } = {}
		for _, id in Zones.builtIds() do
			expected[`Zone{id}`] = true
		end

		for _, child in zoneFolder:GetChildren() do
			check(
				expected[child.Name] == true,
				`Workspace.Zones contains "{child.Name}", which is not a built zone. That folder must hold the plates and nothing else — decor belongs in Workspace.Scenery.`
			)
			check(child:IsA("BasePart"), `Workspace.Zones.{child.Name} is a {child.ClassName}; ZoneService only sees BaseParts`)
		end

		for _, id in Zones.builtIds() do
			local plate = zoneFolder:FindFirstChild(`Zone{id}`)
			if plate == nil or not plate:IsA("BasePart") then
				check(false, `Zone{id} plate missing from Workspace.Zones`)
				continue
			end

			-- The two independent lookups must agree.
			check(plate:GetAttribute("ZoneId") == id, `Zone{id} has ZoneId {tostring(plate:GetAttribute("ZoneId"))} — DigService finds it by name, ZoneService by attribute, and they disagree`)

			-- Flat, or items surface underground / float.
			local rot = plate.CFrame - plate.CFrame.Position
			check(
				rot:FuzzyEq(CFrame.identity, 0.001),
				`Zone{id} is rotated. DigService buries on the flat top face; a tilted plate puts items under the visible ground.`
			)

			local topY = plate.Position.Y + plate.Size.Y / 2
			check(math.abs(topY - Zones.SURFACE_Y) < 0.01, `Zone{id} top face at {topY}, expected {Zones.SURFACE_Y}`)

			local maxDepth = Tuning.DIG_DEPTH_BASE + 7 * Tuning.DIG_DEPTH_PER_RARITY + Tuning.DIG_DEPTH_JITTER
			check(plate.Size.Y >= maxDepth, `Zone{id} is {plate.Size.Y} thick but items bury {maxDepth} deep — a haul would show through the underside`)

			check(plate.Anchored, `Zone{id} is not anchored`)
		end

		-- No two zones may overlap, and none may touch the plaza.
		local built = Zones.builtIds()
		for i = 1, #built do
			for j = i + 1, #built do
				local ax, az, bx, bz = Zones.bounds(built[i])
				local cx, cz, dx, dz = Zones.bounds(built[j])
				check(
					not rectsOverlap({ ax, az, bx, bz }, { cx, cz, dx, dz }),
					`Zone{built[i]} overlaps Zone{built[j]} — smallest-area-wins makes which one you are in non-obvious`
				)
			end

			local half = Hub.PLAZA.size / 2
			local ax, az, bx, bz = Zones.bounds(built[i])
			check(
				not rectsOverlap({ ax, az, bx, bz }, { -half, -half, half, half }),
				`Zone{built[i]} overlaps the hub plaza — base camp would irradiate the people standing in it`
			)
		end
	end

	-- ── Scenery may not pretend to be a zone ─────────────────────────────
	local scenery = Workspace:FindFirstChild("Scenery")
	if scenery then
		for _, d in scenery:GetDescendants() do
			check(d:GetAttribute("ZoneId") == nil, `scenery part {d.Name} carries a ZoneId and would register as a zone`)
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

	check((census.trader or 0) == 1, `expected exactly 1 trader, found {census.trader or 0}`)
	check((census.decon or 0) == 1, `expected exactly 1 decon station, found {census.decon or 0}`)
	check((census.shop or 0) >= #Gear.TRACKS, `expected at least {#Gear.TRACKS} shop counters, found {census.shop or 0}`)
	check((census.plot or 0) == Plots.COUNT, `expected {Plots.COUNT} plot boards, found {census.plot or 0}`)

	-- Every priced track must be buyable somewhere.
	local sells: { [string]: boolean } = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("StationKind") == "shop" then
			sells[d:GetAttribute("StationId") :: string] = true
		end
	end
	for _, track in Gear.TRACKS do
		check(sells[track] == true, `no shop sells "{track}" — it has prices in Gear.luau and nowhere to spend them`)
	end

	-- ── Spawning ─────────────────────────────────────────────────────────
	check(
		Workspace:FindFirstChild("RespawnAnchor", true) ~= nil,
		"no RespawnAnchor in Workspace — blackout falls back to a hardcoded (0, 8, 0)"
	)

	local enabled = 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("SpawnLocation") and d.Enabled then
			enabled += 1
		end
	end
	check(enabled >= 1, "no enabled SpawnLocation in the world — players have nowhere to spawn")

	check(Workspace.Terrain:GetAttribute("ZoneId") == nil, "Terrain carries a ZoneId")

	return #fail == 0, fail
end

--- Coverage report — how searchable each zone actually is at a given detector tier.
--- Prints rather than asserts: this is a tuning aid, and Spec owns the assertion.
function World.coverageReport()
	print("[build] zone search coverage (target c ~= 0.26 at the zone's rated tier)")
	for _, id in Zones.builtIds() do
		local def = Zones.get(id)
		local radius = Gear.tier("Detector", def.ratedSuitTier).radius
		local c = Zones.coverage(id, radius, Tuning.SIGNALS_PER_ZONE)
		local gap = Zones.meanSignalGap(id, Tuning.SIGNALS_PER_ZONE)
		print(string.format("  %-20s area %-8d r=%-3d c=%.3f  mean gap %.0f studs", def.name, Zones.area(id), radius, c, gap))
	end
end

return World
