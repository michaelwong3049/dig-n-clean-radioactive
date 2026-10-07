--!strict
--[[
	FriendBoostService.luau — +10% cash while a Roblox friend is in your server
	(Config/FriendBoost). Gone the moment the last friend leaves.

	IT ONLY RAISES A FLAG. `data.friendBoost` is what StatResolver reads, so the bonus
	lands on every sale and every stand's income with nothing else learning about it,
	and the Boosts widget lists it as a Cash source. The Player attribute
	(FriendBoost.ATTR) is for the client.

	NEVER SAVED. The flag rides on the profile only because StatResolver is pure over
	the profile. It is cleared when its owner leaves, and DataService clears any copy a
	crashed server saved on the next load, so it can never pay out offline.

	FRIENDSHIP IS ASKED ONCE PER PAIR. Player:IsFriendsWith is a web call, so each
	pair's answer is cached for as long as both are here. Two players who befriend
	each other mid-session get the boost the next time either rejoins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local FriendBoost = require(Shared.Config.FriendBoost)

local DataService = require(script.Parent.DataService)
local ExhibitService = require(script.Parent.ExhibitService)

local FriendBoostService = {}

local noticeRemote: RemoteEvent
-- Player -> Player -> are they friends. Filled both ways at once.
local friends: { [Player]: { [Player]: boolean } } = {}
-- Who has had their pairs checked (IsFriendsWith yields, so a player only counts once
-- this is set).
local ready: { [Player]: boolean } = {}

local function hasFriendHere(player: Player): boolean
	local mine = friends[player]
	if mine == nil then
		return false
	end
	for other, isFriend in mine do
		if isFriend and ready[other] and other.Parent == Players then
			return true
		end
	end
	return false
end

--- Re-derive one player's flag; toast and repaint the $/s only when it flips.
local function refresh(player: Player, quiet: boolean?)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local active = ready[player] == true and hasFriendHere(player)
	if (data.friendBoost == true) == active then
		return
	end
	data.friendBoost = if active then true else nil
	player:SetAttribute(FriendBoost.ATTR, active)
	ExhibitService.refreshStandCards(player)
	if not quiet then
		local percent = FriendBoost.cashPercent()
		if active then
			noticeRemote:FireClient(player, `Friend Boost! +{percent}% cash while your friend is here`, "success")
		else
			noticeRemote:FireClient(player, `Friend Boost ended (-{percent}% cash)`, "info")
		end
	end
end

local function refreshAll()
	for _, player in Players:GetPlayers() do
		refresh(player)
	end
end

local function onLoaded(player: Player, data: any)
	-- A copy left on the save by a server that died before PlayerRemoving.
	data.friendBoost = nil
	player:SetAttribute(FriendBoost.ATTR, false)

	friends[player] = friends[player] or {}
	for _, other in Players:GetPlayers() do
		if other ~= player and friends[player][other] == nil then
			local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
			local result = ok and isFriend == true
			if player.Parent ~= Players then
				return
			end
			friends[player][other] = result
			friends[other] = friends[other] or {}
			friends[other][player] = result
		end
	end
	ready[player] = true
	refreshAll()
end

local function onRemoving(player: Player)
	local data = DataService.data(player)
	if data then
		data.friendBoost = nil
	end
	ready[player] = nil
	friends[player] = nil
	for _, mine in friends do
		mine[player] = nil
	end
	refreshAll()
end

function FriendBoostService.start()
	noticeRemote = Net.get("Notice") :: RemoteEvent
	DataService.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(onRemoving)
end

return FriendBoostService
