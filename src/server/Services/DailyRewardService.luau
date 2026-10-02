--!strict
--[[
	DailyRewardService.luau — the 7-day login calendar (Config/DailyRewards, client
	DailyRewardsController).

	THE SAVE HOLDS TWO NUMBERS: `dailyDay`, the day the next claim pays (1-7), and
	`dailyLastAt`, the os.time() of the last claim (0 = never). Everything else is read
	off them and the server clock: a claim is ready CLAIM_GAP after the last one, and a
	streak left longer than RESET_AFTER reads as Day 1 again (the save is only rewritten
	when that claim lands).

	The grant is the Packs' pieces (PackService): EconomyService.award, CrateService.give
	(into the bag even past capacity), LuckBoostService.grant, CashBoostService.grant.
	Cash and crate tier scale with the player -- see Config/DailyRewards' header -- so
	the panel's numbers are worked out here and pushed, never guessed on the client.

	ONE REMOTE, DailyRewards. Client -> server: "ask" (send me the calendar; the panel
	asks every time it opens, so the cash it shows follows your income) or "claim".
	Server -> client: the state below, plus `claimed` on the push that answers a claim.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local DailyRewards = require(Shared.Config.DailyRewards)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local CrateService = require(script.Parent.CrateService)
local LuckBoostService = require(script.Parent.LuckBoostService)
local CashBoostService = require(script.Parent.CashBoostService)
local ExhibitService = require(script.Parent.ExhibitService)
local ProductService = require(script.Parent.ProductService)

local DailyRewardService = {}

local ASK_COOLDOWN = 0.5

local remote: any = nil
local askedAt: { [Player]: number } = {}

local function stageOf(data: any): number
	return tonumber(data.stats and data.stats.deepestStage) or 1
end

--- The day the next claim pays, after a broken streak has been read as Day 1.
local function currentDay(data: any, now: number): number
	local last = tonumber(data.dailyLastAt) or 0
	if last > 0 and now - last > DailyRewards.RESET_AFTER then
		return 1
	end
	return math.clamp(tonumber(data.dailyDay) or 1, 1, DailyRewards.DAYS_IN_CYCLE)
end

--- When the next claim opens (server os.time()); at or before `now` means ready.
local function readyAt(data: any): number
	local last = tonumber(data.dailyLastAt) or 0
	return if last > 0 then last + DailyRewards.CLAIM_GAP else 0
end

--- Every day's reward for this player as it stands right now.
local function resolveDays(data: any): { any }
	local stage = stageOf(data)
	local rate = ExhibitService.ratePerSecond(data)
	local out = {}
	for index, day in DailyRewards.DAYS do
		out[index] = {
			cash = DailyRewards.cashFor(day, stage, rate),
			crates = DailyRewards.crateIds(day, stage),
			luckSeconds = day.luckSeconds,
			cashBoostSeconds = day.cashBoostSeconds,
			big = day.big == true,
		}
	end
	return out
end

--- A streak past RESET_AFTER that has not been restarted yet, and the day it reached.
local function brokenDay(data: any, now: number): number?
	local last = tonumber(data.dailyLastAt) or 0
	local day = math.clamp(tonumber(data.dailyDay) or 1, 1, DailyRewards.DAYS_IN_CYCLE)
	if last > 0 and now - last > DailyRewards.RESET_AFTER and day > 1 then
		return day
	end
	return nil
end

local function push(player: Player, data: any, claimed: number?)
	local now = os.time()
	local opens = readyAt(data)
	local last = tonumber(data.dailyLastAt) or 0
	remote:FireClient(player, {
		day = currentDay(data, now),
		ready = now >= opens,
		readyAt = opens,
		-- When an unclaimed streak would break (0 before the first claim).
		resetAt = if last > 0 then last + DailyRewards.RESET_AFTER else 0,
		days = resolveDays(data),
		claimed = claimed,
		-- The day a Restore Streak purchase would bring back (nil = nothing to restore).
		restoreDay = brokenDay(data, now),
	})
end

--- Pay `dayIndex` onto this player. Mutates `data` and never yields.
local function grant(player: Player, data: any, dayIndex: number): number
	local day = DailyRewards.DAYS[dayIndex]
	local stage = stageOf(data)
	local cash = DailyRewards.cashFor(day, stage, ExhibitService.ratePerSecond(data))
	if cash > 0 then
		EconomyService.award(player, cash, "daily")
	end
	local crates = DailyRewards.crateIds(day, stage)
	for _, crateId in crates do
		CrateService.give(data, crateId)
	end
	if day.luckSeconds > 0 then
		LuckBoostService.grant(player, data, day.luckSeconds)
	end
	if day.cashBoostSeconds > 0 then
		CashBoostService.grant(player, data, day.cashBoostSeconds)
	end
	return #crates
end

--- Claim today's reward if it is ready. Returns whether anything was paid.
function DailyRewardService.claim(player: Player): boolean
	local data = DataService.data(player)
	if data == nil then
		return false
	end
	local now = os.time()
	if now < readyAt(data) then
		push(player, data)
		return false
	end
	local dayIndex = currentDay(data, now)
	local crateCount = grant(player, data, dayIndex)
	data.dailyDay = dayIndex % DailyRewards.DAYS_IN_CYCLE + 1
	data.dailyLastAt = now
	print(`[daily] {player.Name} claimed Day {dayIndex}`)
	push(player, data, dayIndex)
	if crateCount > 0 then
		CrateService.notify(player, `Day {dayIndex} reward: {crateCount} crate{if crateCount == 1 then "" else "s"} added to your bag`)
	end
	return true
end

--- Rewind the calendar (DebugService's /daily): make the next claim ready now, on `day`
--- if given. `broken` backdates the last claim past RESET_AFTER instead.
function DailyRewardService.debugSet(player: Player, day: number?, broken: boolean?)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	if day then
		data.dailyDay = math.clamp(day, 1, DailyRewards.DAYS_IN_CYCLE)
	end
	local now = os.time()
	if broken then
		data.dailyLastAt = now - DailyRewards.RESET_AFTER - 60
	elseif (tonumber(data.dailyLastAt) or 0) > 0 then
		data.dailyLastAt = now - DailyRewards.CLAIM_GAP
	end
	push(player, data)
end

function DailyRewardService.init()
	remote = Net.get("DailyRewards")
	-- Restore Streak: backdate the last claim to exactly CLAIM_GAP ago, so the streak
	-- is unbroken and the day it reached is ready now. Mutates `data`, never yields.
	ProductService.register(DailyRewards.RESTORE_PRODUCT_ID, function(player, data)
		local now = os.time()
		if brokenDay(data, now) then
			data.dailyLastAt = now - DailyRewards.CLAIM_GAP
		end
		task.defer(function()
			local live = DataService.data(player)
			if live then
				push(player, live)
			end
		end)
	end)
end

function DailyRewardService.start()
	DataService.onLoaded(function(player, data)
		push(player, data)
	end)

	remote.OnServerEvent:Connect(function(player: Player, action: any)
		local now = os.clock()
		if now - (askedAt[player] or -math.huge) < ASK_COOLDOWN then
			return
		end
		askedAt[player] = now
		if action == "claim" then
			DailyRewardService.claim(player)
		elseif action == "ask" then
			local data = DataService.data(player)
			if data then
				push(player, data)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		askedAt[player] = nil
	end)
end

return DailyRewardService
