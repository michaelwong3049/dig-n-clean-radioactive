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
]]

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamePasses = require(ReplicatedStorage.Shared.Config.GamePasses)

local DataService = require(script.Parent.DataService)
local SfxService = require(script.Parent.SfxService)

local GamePassService = {}

--- Set (or clear) `key` on this player. Used by the join check, a purchase, and /pass.
function GamePassService.set(player: Player, data: any, key: string, owned: boolean)
	data.passes = data.passes or {}
	data.passes[key] = if owned then true else nil
	player:SetAttribute(GamePasses.attr(key), owned)
end

local function check(player: Player, data: any)
	for _, pass in GamePasses.PASSES do
		local owned = GamePasses.owns(data, pass.key)
		if pass.id ~= 0 then
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
