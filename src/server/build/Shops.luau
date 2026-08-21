--!strict
--[[
	Shops.luau — where cash turns back into capability.

	    require(game.ServerScriptService.Server.build.Shops).rebuild()

	THREE STALLS ON THE PLAZA, one per tool you hold: the detector that finds it, the
	magnet that pulls it, and the cleaner that scrubs it. Each is a different colour
	and keeps that colour forever. A young player learns "the coral one is the
	detector shop" once and then navigates by colour rather than by reading signs,
	which is the cheapest legibility win available anywhere in this map.

	PLUS AN OUTFITTER BENCH, and this one is not decoration.
	Gear.TRACKS has six entries. Three stalls covers Detector, Magnet and Cleaner and
	leaves Suit, Boots and Satchel priced but unbuyable — and the SUIT is the gate on
	every zone in the game. Without a way to buy one, Zone 2 stops being "you can go
	there and here is what it costs" and becomes exactly the locked door PLAN §3.5
	promises never to build. The bench costs nothing to add because the shop system
	is track-generic: it is three more counters with three more StationIds.

	THE WORLD CONTRACT:
	    StationKind = "shop"      -- what kind of thing you are standing at
	    StationId   = "Detector"  -- which track, EXACTLY as spelled in Gear.TRACKS
	    Radius      = <studs>

	StationId rather than a StationKind of "shop_detector" keeps the kind enum small
	and lets one client panel be parameterised by track. It is deliberately the
	capitalised Gear.TRACKS spelling, so no case conversion happens at the world
	boundary — the single lowercase translation lives in Gear.profileKey and nowhere
	else.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)

local Kit = require(script.Parent.Kit)

local Shops = {}
local BUILDER_SOURCE = "src/server/build/Shops.luau"
local BUILDER_VERSION = 1

local C, R = Kit.C, Kit.R
local build, light, billboard = Kit.build, Kit.light, Kit.billboard

--- The three plaza stalls. `at` is world XZ; they face south, toward the fountainless
--- middle of the plaza where a player walks in from the south gate.
local STALLS = {
	{ track = "Detector", at = { -42, 45 }, color = C.shopDetector, tagline = "find it deeper" },
	{ track = "Magnet", at = { 0, 45 }, color = C.shopMagnet, tagline = "pull it harder" },
	{ track = "Cleaner", at = { 42, 45 }, color = C.shopCleaner, tagline = "scrub it cleaner" },
}

--- The outfitter's three counters, on one bench between the stalls and the camp gate.
--- Radius 6 at a 13-stud pitch, so no two counters' circles overlap and standing at
--- one is unambiguous.
local OUTFITTER = {
	at = { 0, -48 },
	pitch = 13,
	counters = {
		{ track = "Suit", label = "SUITS", tagline = "survive it longer" },
		{ track = "Boots", label = "BOOTS", tagline = "get home faster" },
		{ track = "Satchel", label = "SATCHELS", tagline = "buy the clock time" },
	},
}

--- One market stall, in the same idiom as BaseCamp's Trader so the plaza reads as
--- one place: a deck, four posts, striped canvas, a counter you stand at.
local function buildStall(parent: Instance, spec: { track: string, at: { number }, color: string, tagline: string })
	local m = Instance.new("Model")
	m.Name = `{spec.track}Shop`

	local origin = CFrame.new(spec.at[1], 0, spec.at[2])

	build(m, origin, { name = "Deck", pos = { 0, -0.2, 0 }, size = { 26, 0.4, 18 }, color = C.wood, material = "WoodPlanks" })

	for _, dx in { -12, 12 } do
		for _, dz in { -8, 8 } do
			build(m, origin, {
				name = "Post",
				pos = { dx, 2.5, dz },
				size = { 0.5, 5, 0.5 },
				color = C.wood,
				material = "Wood",
			})
		end
	end

	-- Striped canvas, alternating the shop's identity colour with a pale cream.
	for i = 0, 9 do
		build(m, origin, {
			name = "Awning",
			pos = { -11.7 + i * 2.6, 5.4, 0 },
			size = { 2.6, 0.3, 19 },
			color = if i % 2 == 0 then spec.color else C.canvasPale,
			material = "Fabric",
			canCollide = false,
		})
	end

	-- THE COUNTER. This is the part the whole file exists to place correctly.
	local counter = build(m, origin, {
		name = "Counter",
		pos = { 0, 1.4, -6 },
		size = { 20, 2.8, 3 },
		color = spec.color,
		material = "WoodPlanks",
		attributes = {
			StationKind = "shop",
			StationId = spec.track,
			Radius = 12,
		},
	})
	billboard(counter, 260, 5.2, `{string.upper(spec.track)} SHOP`, spec.tagline, spec.color)

	build(m, origin, { name = "CounterTop", pos = { 0, 2.95, -6 }, size = { 21, 0.3, 3.8 }, color = C.canvasPale, material = "WoodPlanks" })

	-- A lit sign board at the back, so the stall is identifiable from behind too.
	local board = build(m, origin, {
		name = "Board",
		pos = { 0, 3.6, 8.2 },
		size = { 18, 3.2, 0.4 },
		color = spec.color,
		material = "Neon",
	})
	Kit.surfaceText(board, Enum.NormalId.Front, string.upper(spec.track), C.signText)
	light(board, spec.color, 26, 2.2)

	-- Stock crates, irregular on purpose — a tidy stack reads as programmer art.
	build(m, origin, { name = "Crate", pos = { -9.4, 0.9, 5.6 }, size = { 2, 2, 2 }, color = C.woodLight, material = "WoodPlanks" })
	build(m, origin, { name = "Crate", pos = { -7.6, 0.8, 6.4 }, size = { 1.7, 1.7, 1.7 }, color = C.wood, material = "WoodPlanks" })
	build(m, origin, { name = "Crate", pos = { -9.2, 2.6, 5.5 }, size = { 1.6, 1.6, 1.6 }, color = C.wood, material = "WoodPlanks" })
	build(m, origin, { name = "Barrel", pos = { 9.6, 1.1, 5.9 }, size = { 2.4, 1.6, 1.6 }, color = spec.color, material = "Metal", shape = "Cylinder", rot = R.cylUpFlipped })

	m.Parent = parent
	return m
end

--- The outfitter: one long bench, three counters on it.
local function buildOutfitter(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Outfitter"

	local origin = CFrame.new(OUTFITTER.at[1], 0, OUTFITTER.at[2])
	local span = OUTFITTER.pitch * (#OUTFITTER.counters - 1)

	build(m, origin, { name = "Bench", pos = { 0, -0.2, 0 }, size = { span + 18, 0.4, 12 }, color = C.steelDark, material = "DiamondPlate" })
	build(m, origin, { name = "Backboard", pos = { 0, 3.2, 5 }, size = { span + 18, 6, 0.5 }, color = C.shopOutfitter, material = "Metal" })

	local backboard = m:FindFirstChild("Backboard") :: BasePart
	Kit.surfaceText(backboard, Enum.NormalId.Front, "OUTFITTER", C.signText)
	light(backboard, C.shopOutfitter, 24, 1.8)

	for index, counter in OUTFITTER.counters do
		local x = -span / 2 + (index - 1) * OUTFITTER.pitch

		local part = build(m, origin, {
			name = `{counter.track}Counter`,
			pos = { x, 1.3, -2 },
			size = { 10, 2.6, 2.6 },
			color = C.shopOutfitter,
			material = "Metal",
			attributes = {
				StationKind = "shop",
				StationId = counter.track,
				-- Tighter than the plaza stalls: three counters on one bench, and
				-- standing at one of them has to be unambiguous.
				Radius = 6,
			},
		})
		billboard(part, 200, 4.2, counter.label, counter.tagline, C.shopOutfitter)
	end

	m.Parent = parent
	return m
end

local function createShops(): Model
	local shops = Instance.new("Model")
	shops.Name = "Shops"
	Kit.stamp(shops, BUILDER_SOURCE, BUILDER_VERSION)

	for _, spec in STALLS do
		buildStall(shops, spec)
	end
	buildOutfitter(shops)

	-- Every track in Gear must be buyable somewhere, or it is a priced dead end.
	-- Checked here, at build time, because the failure is otherwise invisible until
	-- a player saves up for something they can never spend it on.
	local covered: { [string]: boolean } = {}
	for _, part in shops:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("StationKind") == "shop" then
			covered[part:GetAttribute("StationId") :: string] = true
		end
	end
	for _, track in Gear.TRACKS do
		assert(covered[track], `no shop sells the {track} track — it is priced but unbuyable`)
	end

	return shops
end

function Shops.build(parent: Instance?): Model
	local shops = createShops()
	shops.Parent = parent or Workspace
	return shops
end

function Shops.rebuild(parent: Instance?): Model
	local shops = Kit.swap("Shops", createShops, parent) :: Model
	print(`[build] Shops rebuilt — {#shops:GetChildren()} storefronts, all {#Gear.TRACKS} tracks covered`)
	return shops
end

return Shops
