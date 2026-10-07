--!strict
--[[
	StationService.lua — what are you standing at, and who cares.

	Shaped exactly like StageService (a cached spatial lookup plus an onChanged
	edge), because it is the same problem: a cheap per-tick "where is this player"
	that several services need and none of them should each be computing.

	WHY THIS WAS EXTRACTED FROM DeconService
	DeconService.stationAt walked EVERY descendant of Workspace.BaseCamp, per player,
	per tick, at 10 Hz. Two problems, and the second is the fatal one:

	  1. It was O(#camp). The camp is 121 parts; the hub, six plots and seven shop
	     counters take the world past a thousand. That is a full-tree walk ten times
	     a second per player for a question whose answer barely changes.

	  2. It only ever looked inside Workspace.BaseCamp. A shop on the plaza, or a
	     pedestal on a plot, was structurally invisible to the game — not broken,
	     not erroring, just permanently not there.

	So the scan is now O(#stations) via CollectionService, and it covers the whole
	world. THE ATTRIBUTE IS STILL THE SOURCE OF TRUTH — Kit.build adds the tag at the
	moment it sets the attribute, and World.verify() asserts the two agree in both
	directions, so the tag can never silently drift out of sync with the world.

	THE WORLD CONTRACT (see ARCHITECTURE.md):
	    StationKind = "trader" | "decon" | "shop" | "pedestal" | "treadmill" | "locker" | "merge" | "reforge" | "furnace"
	    StationId   = optional discriminator within a kind ("Detector", "3:2", ...)
	    Radius      = studs, default 12

	Nearest-wins, which matters where counters sit close together: the Outfitter's
	three counters are 13 studs apart with a radius of 6 precisely so that standing
	at one of them is unambiguous.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Ticker = require(Shared.Util.Ticker)
local Tutorial = require(Shared.Config.Tutorial)

local ExhibitService = require(script.Parent.ExhibitService)

local StationService = {}

local STATION_TAG = "Station"
local DEFAULT_RADIUS = 12

--- Rebuilt on a timer rather than per query. Two seconds is the same number
--- ExposureService uses for its shower cache, and for the same reason: the world's
--- station layout only changes when a builder runs.
local CACHE_REFRESH = 2

--- Kinds tested against the part's own footprint instead of a sphere. A treadmill belt
--- is ~4 studs wide, so its old 6.6-stud sphere kept a player "on the belt" after they
--- stepped off the side: the training bar stayed up and the run animation kept playing
--- over their walk. Inside the box = feet over the belt (plus FOOTPRINT_MARGIN), with
--- the root anywhere from just under the belt to a jump above it.
local FOOTPRINT_KINDS: { [string]: boolean } = { treadmill = true }
local FOOTPRINT_MARGIN = 0.75
local FOOTPRINT_BELOW = 1
local FOOTPRINT_ABOVE = 7

--- Kinds that belong to the base they are built on. A plot's cleansing station and
--- treadmill are its owner's alone: for anyone else they are nowhere, so nothing that
--- asks kindOf (docking, the hose, belt training) works there. The camps' public
--- cleansing stations are on no plot and stay open to all (ExhibitService.ownsPlotStation).
local OWNER_ONLY_KINDS: { [string]: boolean } = { decon = true, treadmill = true }

type Entry = {
	part: BasePart,
	position: Vector3,
	radius: number,
	kind: string,
	id: string?,
	footprint: { cframe: CFrame, half: Vector3 }?,
	plot: number?,
}

local cache: { Entry } = {}
local cacheAge = math.huge

type Current = { kind: string?, id: string?, part: BasePart? }

local current: { [Player]: Current } = {}
local listeners: { (Player, string?, string?, string?, string?) -> () } = {}
local handle: any = nil

local function refresh()
	table.clear(cache)
	for _, part in CollectionService:GetTagged(STATION_TAG) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			local kind = part:GetAttribute("StationKind") :: string?
			if kind then
				table.insert(cache, {
					part = part,
					position = part.Position,
					radius = (part:GetAttribute("Radius") :: number?) or DEFAULT_RADIUS,
					kind = kind,
					id = part:GetAttribute("StationId") :: string?,
					footprint = if FOOTPRINT_KINDS[kind]
						then { cframe = part.CFrame, half = part.Size / 2 }
						else nil,
					plot = if OWNER_ONLY_KINDS[kind] then ExhibitService.plotIndexOf(part) else nil,
				})
			end
		end
	end
end

--- Nearest station containing `position`, or nil. The fourth value is the plot an
--- owner-only station sits on (OWNER_ONLY_KINDS), nil for anything anyone may use.
function StationService.at(position: Vector3): (string?, string?, BasePart?, number?)
	local bestKind: string? = nil
	local bestId: string? = nil
	local bestPart: BasePart? = nil
	local bestPlot: number? = nil
	local bestDistance = math.huge

	for _, entry in cache do
		-- Squared distance: this runs stations x players x 10 per second, and the
		-- square root is the only expensive part of it.
		local delta = entry.position - position
		local squared = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
		local inside = squared <= entry.radius * entry.radius
		local footprint = entry.footprint
		if inside and footprint then
			local localPos = footprint.cframe:PointToObjectSpace(position)
			local half = footprint.half
			inside = math.abs(localPos.X) <= half.X + FOOTPRINT_MARGIN
				and math.abs(localPos.Z) <= half.Z + FOOTPRINT_MARGIN
				and localPos.Y >= -half.Y - FOOTPRINT_BELOW
				and localPos.Y <= half.Y + FOOTPRINT_ABOVE
		end
		if inside and squared < bestDistance then
			bestKind, bestId, bestPart, bestPlot, bestDistance = entry.kind, entry.id, entry.part, entry.plot, squared
		end
	end

	return bestKind, bestId, bestPart, bestPlot
end

function StationService.kindOf(player: Player): string?
	local entry = current[player]
	return if entry then entry.kind else nil
end

function StationService.idOf(player: Player): string?
	local entry = current[player]
	return if entry then entry.id else nil
end

--- The station PART the player is standing at, for whatever else it carries.
---
--- kind and id are not enough to tell two stations apart when a track is sold in more than
--- one place: Base Camp's Detector stall and Toxic Twilight's are both ("shop", "Detector"),
--- and only the part says which camp's rungs are for sale (`ShopCamp`, see
--- ShopService.campAt). Kept current every tick rather than on an edge, because walking
--- from one stall to another of the same kind fires no edge.
function StationService.partOf(player: Player): BasePart?
	local entry = current[player]
	return if entry then entry.part else nil
end

--- fn(player, kind, id, previousKind, previousId). Fires only on a real change.
function StationService.onChanged(fn: (Player, string?, string?, string?, string?) -> ())
	table.insert(listeners, fn)
end

local function step(dt: number)
	cacheAge += dt
	if cacheAge >= CACHE_REFRESH then
		cacheAge = 0
		refresh()
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			continue
		end

		local kind, id, part, plot = StationService.at(root.Position)
		-- Someone else's cleansing station or treadmill is nowhere, the same way.
		if not ExhibitService.ownsPlotStation(player, plot) then
			kind, id, part = nil, nil, nil
		end
		-- A station the walkthrough keeps shut (Config/Tutorial) is nowhere: no panel
		-- opens, and nothing that asks kindOf (buying, selling, the locker, the belt) works.
		if not Tutorial.stationOpen(player, kind, id) then
			kind, id, part = nil, nil, nil
		end
		local entry = current[player]
		if entry == nil then
			entry = { kind = nil, id = nil, part = nil }
			current[player] = entry
		end
		entry.part = part

		if entry.kind ~= kind or entry.id ~= id then
			local previousKind, previousId = entry.kind, entry.id
			entry.kind, entry.id = kind, id
			for _, fn in listeners do
				-- One listener throwing must not stop the others being told.
				local ok, err = pcall(fn, player, kind, id, previousKind, previousId)
				if not ok then
					warn(`[station] onChanged listener errored: {err}`)
				end
			end
		end
	end
end

function StationService.init()
	refresh()
	cacheAge = 0
end

function StationService.start()
	handle = Ticker.every(Tuning.TICK_RATE, step, "StationService")

	Players.PlayerRemoving:Connect(function(player)
		current[player] = nil
	end)
end

function StationService.stop()
	if handle then
		handle:stop()
		handle = nil
	end
end

return StationService
