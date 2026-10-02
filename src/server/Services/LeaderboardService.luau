--!strict
--[[
	LeaderboardService.luau — puts each player's cash and trained walk speed on the
	Roblox player list (top-right leaderboard) via the standard `leaderstats` folder.

	data.cash is mutated from many places (EconomyService, refunds on load, debug
	commands), not all of which go through EconomyService.pushCash, so instead of
	hooking every writer this mirrors the wallet on a short poll. Only writes the
	IntValue when the number actually changed, so replication stays quiet.
]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local Treadmill = require(ReplicatedStorage.Shared.Config.Treadmill)

local LeaderboardService = {}

local POLL = 0.5

local cashValues: { [Player]: IntValue } = {}
local speedValues: { [Player]: IntValue } = {}

local function setup(player: Player)
	if cashValues[player] then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = folder
	-- Trained walk speed (not the picker's cap), so the board shows what they've earned.
	local speed = Instance.new("IntValue")
	speed.Name = "Speed"
	speed.Value = Treadmill.START_WALK
	speed.Parent = folder
	folder.Parent = player
	cashValues[player] = cash
	speedValues[player] = speed
end

function LeaderboardService.init() end

function LeaderboardService.start()
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		cashValues[player] = nil
		speedValues[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		setup(player)
	end

	task.spawn(function()
		while true do
			for player, value in cashValues do
				local data = DataService.data(player)
				if data ~= nil then
					local cash = math.floor(tonumber(data.cash) or 0)
					if value.Value ~= cash then
						value.Value = cash
					end
					local speedValue = speedValues[player]
					if speedValue ~= nil then
						local walk = Treadmill.walkSpeedFor((Treadmill.levelFor(data.speedPoints or 0)))
						if speedValue.Value ~= walk then
							speedValue.Value = walk
						end
					end
				end
			end
			task.wait(POLL)
		end
	end)
end

return LeaderboardService
