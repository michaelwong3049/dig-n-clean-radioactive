--!strict
--[[
	CodeService.luau — the Shop's CODES section (Config/Codes, client ShopController).
	A player types a code; if they are in the group and have not used it, it pays out.

	THE FLOW. The client fires the typed text at "RedeemCode". Back comes one answer:
	  "invalid"  no such code (or it is switched off / expired)
	  "used"     this save already redeemed it
	  "join"     not in GroupReward.GROUP_ID: the client opens Roblox's join prompt and,
	             if they join, sends the same code again (membership is checked AGAIN)
	  "ok"       paid; `text` says what
	  "busy"     slow down (cooldown, or a redeem already in flight)

	THE CLIENT IS TRUSTED FOR NOTHING. Membership is read fresh on the server
	(GroupRewardService.isMember), the code is looked up here, and the redeemed flag is
	written BEFORE the reward is paid and after the last yield, so two fast presses
	cannot both pay.

	The grant is the same pieces the group chest and the daily calendar use.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Codes = require(Shared.Config.Codes)
local GroupReward = require(Shared.Config.GroupReward)

local CashBoostService = require(script.Parent.CashBoostService)
local CrateService = require(script.Parent.CrateService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local GroupRewardService = require(script.Parent.GroupRewardService)
local LuckBoostService = require(script.Parent.LuckBoostService)
local PotionService = require(script.Parent.PotionService)
local SpeedService = require(script.Parent.SpeedService)

local CodeService = {}

local COOLDOWN = 1.5

local remote: any = nil
local lastTry: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}

local function grant(player: Player, data: any, entry: Codes.Code)
	if entry.cash and entry.cash > 0 then
		EconomyService.award(player, entry.cash, "code")
	end
	if entry.speed and entry.speed > 0 then
		SpeedService.grantWalk(data, entry.speed)
		SpeedService.refresh(player)
	end
	if entry.luckSeconds and entry.luckSeconds > 0 then
		LuckBoostService.grant(player, data, entry.luckSeconds)
	end
	if entry.cashBoostSeconds and entry.cashBoostSeconds > 0 then
		CashBoostService.grant(player, data, entry.cashBoostSeconds)
	end
	for _, potion in entry.potions or {} do
		PotionService.give(player, data, potion.id, potion.count)
	end
	if entry.crates and #entry.crates > 0 then
		for _, crateId in entry.crates do
			CrateService.give(data, crateId)
		end
		CrateService.notify(
			player,
			`Code reward: {#entry.crates} crate{if #entry.crates == 1 then "" else "s"} added to your bag`
		)
	end
end

--- Try to redeem what `text` says for this player. Yields (the membership web call).
function CodeService.redeem(player: Player, text: any)
	if type(text) ~= "string" or #text > Codes.MAX_LENGTH then
		remote:FireClient(player, { result = "invalid" })
		return
	end
	local t = os.clock()
	if busy[player] or t - (lastTry[player] or -math.huge) < COOLDOWN then
		remote:FireClient(player, { result = "busy" })
		return
	end
	lastTry[player] = t

	local key = Codes.normalize(text)
	local entry = Codes.find(text)
	if key == "" or entry == nil then
		remote:FireClient(player, { result = "invalid" })
		return
	end
	local data = DataService.data(player)
	if data == nil then
		return
	end
	data.redeemedCodes = data.redeemedCodes or {}
	if data.redeemedCodes[key] then
		remote:FireClient(player, { result = "used" })
		return
	end

	busy[player] = true
	local member = GroupRewardService.isMember(player)
	busy[player] = nil

	-- Re-read after the yield: they may have left, or a second press may have landed.
	data = DataService.data(player)
	if data == nil or player.Parent == nil then
		return
	end
	data.redeemedCodes = data.redeemedCodes or {}
	if data.redeemedCodes[key] then
		remote:FireClient(player, { result = "used" })
		return
	end
	if not member then
		remote:FireClient(player, { result = "join", groupId = GroupReward.GROUP_ID })
		return
	end

	data.redeemedCodes[key] = true
	grant(player, data, entry)
	print(`[code] {player.Name} redeemed {key}`)
	remote:FireClient(player, { result = "ok", text = Codes.describe(entry) })
end

--- /resetcodes (DebugService, if wired): forget this player's redeemed codes.
function CodeService.debugReset(player: Player)
	local data = DataService.data(player)
	if data then
		data.redeemedCodes = {}
	end
end

function CodeService.init()
	remote = Net.get("RedeemCode")
end

function CodeService.start()
	remote.OnServerEvent:Connect(function(player: Player, text: any)
		CodeService.redeem(player, text)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
		busy[player] = nil
	end)
end

return CodeService
