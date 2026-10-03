--!strict
--[[
	GamePassService.luau — who owns which permanent pass (Config/GamePasses).

	Asks Roblox on every join and listens for a purchase in-session, then mirrors the
	answer two ways: into `data.passes` (key -> true) for StatResolver, which is where
	every pass actually takes effect, and onto a Player attribute (GamePasses.attr) so
	the Shop card can say OWNED without a remote.

	A FAILED CHECK CHANGES NOTHING. UserOwnsGamePassAsync is a web call and can throw;
	when it does, the saved mirror from last time stands, so a hiccup never strips a
	pass someone paid for. A successful "no" does clear it -- that is a refund, or a
	`/pass` test grant wearing off.

	COMPED ROLES. A player in GamePasses.COMP_ROLES in the game's group (or its owner)
	owns every pass, checked on join only -- a role change takes a rejoin.
]]

local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePasses = require(ReplicatedStorage.Shared.Config.GamePasses)
local GroupReward = require(ReplicatedStorage.Shared.Config.GroupReward)

local DataService = require(script.Parent.DataService)
local SfxService = require(script.Parent.SfxService)

local GamePassService = {}

--- Set (or clear) `key` on this player. Used by the join check, a purchase, and /pass.
function GamePassService.set(player: Player, data: any, key: string, owned: boolean)
	data.passes = data.passes or {}
	data.passes[key] = if owned then true else nil
	player:SetAttribute(GamePasses.attr(key), owned)
end

-- In a comped group role (GamePasses.COMP_ROLES, or the group's owner)? Nil when the
-- web call fails, so a hiccup falls through to the normal per-pass check.
local function comped(player: Player): boolean?
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if not ok or type(groups) ~= "table" then
		warn(`[pass] group role check for {player.Name} failed: {groups}`)
		return nil
	end
	for _, g in groups do
		if g.Id == GroupReward.GROUP_ID then
			return GamePasses.COMP_ROLES[g.Role] == true or (g.Rank or 0) >= GamePasses.COMP_MIN_RANK
		end
	end
	return false
end

local function check(player: Player, data: any)
	local comp = comped(player) == true
	if comp then
		print(`[pass] {player.Name} comped every pass (group role)`)
	end
	for _, pass in GamePasses.PASSES do
		local owned = GamePasses.owns(data, pass.key)
		if comp then
			owned = true
		elseif pass.id ~= 0 then
			local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.id)
			if ok then
				owned = result == true
			else
				warn(`[pass] ownership check for {player.Name} {pass.key} failed: {result}`)
			end
		end
		if player.Parent == nil then
			return
		end
		GamePassService.set(player, data, pass.key, owned)
	end
end

function GamePassService.init() end

function GamePassService.start()
	DataService.onLoaded(check)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased then
			return
		end
		local pass = GamePasses.byId(passId)
		local data = DataService.data(player)
		if pass == nil or data == nil then
			return
		end
		GamePassService.set(player, data, pass.key, true)
		SfxService.play(player, "robux")
		print(`[pass] {player.Name} bought {pass.name}`)
	end)
end

return GamePassService
