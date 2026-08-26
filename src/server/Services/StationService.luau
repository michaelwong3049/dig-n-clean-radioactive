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
	    StationKind = "trader" | "decon" | "shop" | "plot" | "pedestal"
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

local StationService = {}

local STATION_TAG = "Station"
local DEFAULT_RADIUS = 12

--- Rebuilt on a timer rather than per query. Two seconds is the same number
--- ExposureService uses for its shower cache, and for the same reason: the world's
--- station layout only changes when a builder runs.
local CACHE_REFRESH = 2

type Entry = {
	part: BasePart,
	position: Vector3,
	radius: number,
	kind: string,
	id: string?,
}

local cache: { Entry } = {}
local cacheAge = math.huge

type Current = { kind: string?, id: string? }

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
				})
			end
		end
	end
end

--- Nearest station containing `position`, or nil.
function StationService.at(position: Vector3): (string?, string?, BasePart?)
	local bestKind: string? = nil
	local bestId: string? = nil
	local bestPart: BasePart? = nil
	local bestDistance = math.huge

	for _, entry in cache do
		-- Squared distance: this runs stations x players x 10 per second, and the
		-- square root is the only expensive part of it.
		local delta = entry.position - position
		local squared = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
		if squared <= entry.radius * entry.radius and squared < bestDistance then
			bestKind, bestId, bestPart, bestDistance = entry.kind, entry.id, entry.part, squared
		end
	end

	return bestKind, bestId, bestPart
end

function StationService.kindOf(player: Player): string?
	local entry = current[player]
	return if entry then entry.kind else nil
end

function StationService.idOf(player: Player): string?
	local entry = current[player]
	return if entry then entry.id else nil
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

		local kind, id = StationService.at(root.Position)
		local entry = current[player]
		if entry == nil then
			entry = { kind = nil, id = nil }
			current[player] = entry
		end

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
