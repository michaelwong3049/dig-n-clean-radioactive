--!strict
--[[
	StatsService.luau — the numbers on Settings > Stats, and the playtime clock.

	PLAYTIME IS TICKED, NOT STAMPED. Every TICK seconds each loaded player's
	`data.stats.playtime` grows by the time since their last tick, so the save already
	holds it when the profile is released on leave; a leave handler adding the session
	at the end could run after the release and lose it.

	EVERYTHING ELSE IS ALREADY COUNTED where it happens (DataService's `stats` block
	names each writer). This file only reads: when the page asks, it answers with one
	flat table of whole numbers (Net.PlayerStats). The client asks once when the page
	opens and every couple of seconds while it stays open; ASK_COOLDOWN keeps a spammed
	ask from costing anything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Stages = require(Shared.Config.Stages)
local IndexProgress = require(Shared.IndexProgress)

local DataService = require(script.Parent.DataService)

local StatsService = {}

local TICK = 5
local ASK_COOLDOWN = 0.5

local lastTick: { [Player]: number } = {}
local askedAt: { [Player]: number } = {}
local remote: any = nil

local function count(stats: any, key: string): number
	return math.floor(tonumber(stats[key]) or 0)
end

--- Bank the seconds since `player`'s last tick into their playtime.
local function tick(player: Player, data: any)
	local now = os.clock()
	local last = lastTick[player]
	lastTick[player] = now
	if last then
		data.stats.playtime = (tonumber(data.stats.playtime) or 0) + (now - last)
	end
end

local function snapshot(data: any): { [string]: number }
	local stats = data.stats
	local found, total = 0, 0
	local discovered = if type(data.discovered) == "table" then data.discovered else {}
	for _, stage in Stages.DEFS do
		local have, of = IndexProgress.stageCount(discovered, stage.id)
		found += have
		total += of
	end
	return {
		playtime = count(stats, "playtime"),
		dug = count(stats, "dug"),
		itemsCleaned = count(stats, "itemsCleaned"),
		cashEarned = math.floor(tonumber(data.cashEarned) or 0),
		indexFound = found,
		indexTotal = total,
		deepestStage = math.max(1, count(stats, "deepestStage")),
		kills = count(stats, "kills"),
		bagsStolen = count(stats, "bagsStolen"),
		deaths = count(stats, "deaths"),
		bombsDropped = count(stats, "bombsDropped"),
		rareFinds = count(stats, "rareFinds"),
		merges = count(stats, "merges"),
		rolls = count(stats, "rolls"),
		cratesOpened = count(stats, "cratesOpened"),
	}
end

function StatsService.init()
	remote = Net.get("PlayerStats")
end

function StatsService.start()
	DataService.onLoaded(function(player)
		lastTick[player] = os.clock()
	end)

	remote.OnServerEvent:Connect(function(player: Player)
		local t = os.clock()
		if t - (askedAt[player] or -math.huge) < ASK_COOLDOWN then
			return
		end
		askedAt[player] = t
		local data = DataService.data(player)
		if data then
			tick(player, data)
			remote:FireClient(player, snapshot(data))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastTick[player] = nil
		askedAt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			for player in lastTick do
				local data = DataService.data(player)
				if data then
					tick(player, data)
				end
			end
		end
	end)
end

return StatsService
