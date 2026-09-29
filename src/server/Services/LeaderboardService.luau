--!strict
--[[
	LeaderboardService.luau — puts each player's cash on the Roblox player list
	(top-right leaderboard) via the standard `leaderstats` folder.

	data.cash is mutated from many places (EconomyService, refunds on load, debug
	commands), not all of which go through EconomyService.pushCash, so instead of
	hooking every writer this mirrors the wallet on a short poll. Only writes the
	IntValue when the number actually changed, so replication stays quiet.
]]

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local POLL = 0.5

local cashValues: { [Player]: IntValue } = {}

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
	folder.Parent = player
	cashValues[player] = cash
end

function LeaderboardService.init() end

function LeaderboardService.start()
	Players.PlayerAdded:Connect(setup)
	Players.PlayerRemoving:Connect(function(player)
		cashValues[player] = nil
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
				end
			end
			task.wait(POLL)
		end
	end)
end

return LeaderboardService
