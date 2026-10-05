--!strict
--[[
	BoostsService.luau — sends each player their boosts breakdown for the bottom-right
	Boosts widget (BoostsController): every multiplier on luck, cash, walk speed and the
	rest, and which potion, pass, event or reward each one comes from.

	IT DECIDES NOTHING. StatResolver.boosts builds the list from the same helpers that
	StatResolver.get folds in, so the widget and the dig roll cannot disagree.

	SENT ON CHANGE, checked once a second. A source starting or stopping (a potion
	drunk or run out, the aurora, a pass bought, a mastery reached) changes the
	signature and the list goes out again. Countdowns are not sent at all: each timed
	source names the attribute its owner service already publishes, and the client
	counts down off that.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)

local BoostsService = {}

local remote: RemoteEvent
-- Player -> the signature of the last list sent.
local sent: { [Player]: string } = {}

local function signature(list: { StatResolver.Boost }): string
	local parts = {}
	for _, boost in list do
		table.insert(parts, `{boost.key}={boost.total}`)
		for _, source in boost.sources do
			table.insert(parts, `{source.name}:{source.mult}`)
		end
	end
	return table.concat(parts, ";")
end

local function push(player: Player, data: any)
	local list = StatResolver.boosts(data)
	local sig = signature(list)
	if sent[player] == sig then
		return
	end
	sent[player] = sig
	remote:FireClient(player, list)
end

local function step()
	for _, player in Players:GetPlayers() do
		local data = DataService.data(player)
		if data then
			push(player, data)
		end
	end
end

function BoostsService.start()
	remote = Net.get("Boosts") :: RemoteEvent
	DataService.onLoaded(push)
	Players.PlayerRemoving:Connect(function(player)
		sent[player] = nil
	end)
	Ticker.every(1, step, "BoostsService")
end

return BoostsService
