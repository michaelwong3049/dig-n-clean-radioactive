--!strict
--[[
	PlaytimeGiftService.luau — the "Free Gifts" ladder (Config/PlaytimeGifts, client
	PlaytimeGiftController): stay in the game and gifts open at 1, 3, 5 ... 120 minutes.

	THE SESSION CLOCK IS NOT SAVED. `startedAt` and the claimed set live in memory,
	keyed by player, and are made when the profile loads and dropped when the player
	leaves -- "Leaving resets gifts!". Nothing here touches the save except the grants.

	THE SERVER DECIDES EVERYTHING. The client is sent `startedAt` (server time) and the
	gifts as worked out for THIS player (cash follows income and stage); it counts down
	on its own, but a claim is checked here against the real clock, and a gift can only
	be claimed once.

	ONE REMOTE, PlaytimeGifts. Client -> server: "ask" (send me the state), "claim", index
	(one gift) or "claimAll". Server -> client: the state below, plus `claimed` (a list of
	indexes) on the push that answers a claim.

	The grant is the same set of pieces the calendar and the codes use: EconomyService.award,
	CrateService.give, LuckBoostService.grant, CashBoostService.grant, speedPoints the way
	the group chest pays them, and PotionService.give into the potion stash.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local PlaytimeGifts = require(Shared.Config.PlaytimeGifts)

local CashBoostService = require(script.Parent.CashBoostService)
local CrateService = require(script.Parent.CrateService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ExhibitService = require(script.Parent.ExhibitService)
local LuckBoostService = require(script.Parent.LuckBoostService)
local PotionService = require(script.Parent.PotionService)
local TreadmillService = require(script.Parent.TreadmillService)

local PlaytimeGiftService = {}

local ASK_COOLDOWN = 0.3

type Session = {
	startedAt: number,
	claimed: { [number]: boolean },
}

local remote: any = nil
local sessions: { [Player]: Session } = {}
local askedAt: { [Player]: number } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function stageOf(data: any): number
	return tonumber(data.stats and data.stats.deepestStage) or 1
end

--- Every gift as this player would get it right now.
local function resolveGifts(data: any): { any }
	local stage = stageOf(data)
	local rate = ExhibitService.ratePerSecond(data)
	local out = {}
	for index, gift in PlaytimeGifts.GIFTS do
		local potions = {}
		for _, potion in gift.potions or {} do
			table.insert(potions, { id = potion.id, count = potion.count })
		end
		out[index] = {
			minutes = gift.minutes,
			cash = PlaytimeGifts.cashFor(gift, stage, rate),
			speed = gift.speed or 0,
			luckSeconds = gift.luckSeconds or 0,
			cashBoostSeconds = gift.cashBoostSeconds or 0,
			potions = potions,
			crates = #PlaytimeGifts.crateIds(gift, stage),
			-- Which crates, so the card can show the best one's picture.
			crateIds = PlaytimeGifts.crateIds(gift, stage),
			big = gift.big == true,
		}
	end
	return out
end

local function push(player: Player, data: any, claimed: { number }?)
	local session = sessions[player]
	if session == nil then
		return
	end
	local done = {}
	for index in session.claimed do
		table.insert(done, index)
	end
	table.sort(done)
	remote:FireClient(player, {
		startedAt = session.startedAt,
		now = serverNow(),
		gifts = resolveGifts(data),
		claimed = done,
		justClaimed = claimed,
	})
end

--- Pay gift `index` onto this player. Mutates `data` and never yields.
local function grant(player: Player, data: any, index: number)
	local gift = PlaytimeGifts.GIFTS[index]
	local stage = stageOf(data)
	local cash = PlaytimeGifts.cashFor(gift, stage, ExhibitService.ratePerSecond(data))
	if cash > 0 then
		EconomyService.award(player, cash, "playtime")
	end
	if gift.speed and gift.speed > 0 then
		data.speedPoints = (data.speedPoints or 0) + gift.speed
		ExhibitService.refreshTreadmill(player)
		TreadmillService.refresh(player)
	end
	if gift.luckSeconds and gift.luckSeconds > 0 then
		LuckBoostService.grant(player, data, gift.luckSeconds)
	end
	if gift.cashBoostSeconds and gift.cashBoostSeconds > 0 then
		CashBoostService.grant(player, data, gift.cashBoostSeconds)
	end
	for _, potion in gift.potions or {} do
		PotionService.give(player, data, potion.id, potion.count)
	end
	local crates = PlaytimeGifts.crateIds(gift, stage)
	for _, crateId in crates do
		CrateService.give(data, crateId)
	end
	if #crates > 0 then
		CrateService.notify(player, `Free gift: {#crates} crate{if #crates == 1 then "" else "s"} added to your bag`)
	end
end

local function ready(session: Session, index: number): boolean
	local gift = PlaytimeGifts.GIFTS[index]
	return gift ~= nil
		and not session.claimed[index]
		and serverNow() - session.startedAt >= PlaytimeGifts.openAt(gift)
end

--- Claim the listed gifts that are open and unclaimed. Returns how many were paid.
local function claim(player: Player, indexes: { number }): number
	local session = sessions[player]
	local data = DataService.data(player)
	if session == nil or data == nil then
		return 0
	end
	local paid = {}
	for _, index in indexes do
		if ready(session, index) then
			session.claimed[index] = true
			grant(player, data, index)
			table.insert(paid, index)
		end
	end
	if #paid > 0 then
		print(`[playtime] {player.Name} claimed gift(s) {table.concat(paid, ", ")}`)
	end
	push(player, data, if #paid > 0 then paid else nil)
	return #paid
end

--- /gifttime <minutes>: move the session clock forward so gifts open now (testing).
function PlaytimeGiftService.debugAdvance(player: Player, minutes: number)
	local session = sessions[player]
	if session then
		session.startedAt -= minutes * 60
		local data = DataService.data(player)
		if data then
			push(player, data)
		end
	end
end

--- /giftreset: start the session over, as if the player had just joined.
function PlaytimeGiftService.debugReset(player: Player)
	local data = DataService.data(player)
	if data then
		sessions[player] = { startedAt = serverNow(), claimed = {} }
		push(player, data)
	end
end

function PlaytimeGiftService.init()
	remote = Net.get("PlaytimeGifts")
end

function PlaytimeGiftService.start()
	DataService.onLoaded(function(player, data)
		sessions[player] = { startedAt = serverNow(), claimed = {} }
		push(player, data)
	end)

	remote.OnServerEvent:Connect(function(player: Player, action: any, index: any)
		local t = os.clock()
		if t - (askedAt[player] or -math.huge) < ASK_COOLDOWN then
			return
		end
		askedAt[player] = t
		if action == "claim" and type(index) == "number" then
			claim(player, { math.floor(index) })
		elseif action == "claimAll" then
			local all = {}
			for i = 1, #PlaytimeGifts.GIFTS do
				table.insert(all, i)
			end
			claim(player, all)
		elseif action == "ask" then
			local data = DataService.data(player)
			if data then
				push(player, data)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		askedAt[player] = nil
	end)
end

return PlaytimeGiftService
