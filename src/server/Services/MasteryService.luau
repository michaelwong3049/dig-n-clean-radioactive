--!strict
--[[
	MasteryService.luau — the masteries (Config/Masteries): keeping each player's panel
	current and telling them the moment they reach a tier.

	IT GRANTS NOTHING. A mastery's reward is read off its counter by StatResolver
	(Shared/Mastery.value), so a tier pays the instant the counter crosses its goal,
	in every system at once, whether or not this service has noticed yet. This file only
	watches the counters, which other services bump where the thing happens:

	  itemsCleaned  WashService       a nuke washed clean
	  kills         ExposureService   a player downed by your bomb (HazardService.killerOf)
	  dug           DigService        a nuke out of the ground
	  merges        MergeService      a merge that gained stars
	  bagsStolen    ExposureService   first take from someone else's dropped bag
	  rolls         LiquidService     a fluid brewed
	  speedPoints, cashEarned, discovered — the profile's own lifetime numbers

	and `deepestStage`, which nothing else kept, is written here off StageService.

	ONCE A SECOND it snapshots every player's counters and pushes MasteryState when
	anything moved. A tier higher than the one seen last time rides along as `unlocked`,
	which the client turns into the "Mastery reached" toast. The first snapshot after a
	load is quiet, so rejoining does not re-announce everything you already had.

	THE BOMBER MULTIPLIER IS ALSO A PLAYER ATTRIBUTE (MasteryBombDamage), because the
	hotbar's bomb card computes damage client-side (Shared/Bombing) and needs the same
	number BombService will apply.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Masteries = require(Shared.Config.Masteries)
local Mastery = require(Shared.Mastery)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local StageService = require(script.Parent.StageService)

local MasteryService = {}

local POLL_SECONDS = 1
local BOMB_ATTR = "MasteryBombDamage"
local DEEPEST_ATTR = "DeepestStage"

type Seen = {
	tiers: { [string]: number },
	signature: string,
}

local seen: { [Player]: Seen } = {}
local askedAt: { [Player]: number } = {}
local stateRemote: any = nil

--- Raise `deepestStage` to `stageId` if it is deeper, and publish it as the
--- DeepestStage attribute (the bag-steal gate, Tuning.STEAL_MIN_STAGE, is worded
--- client-side off it).
local function reach(player: Player, data: any, stageId: number?)
	if stageId and stageId > (tonumber(data.stats.deepestStage) or 1) then
		data.stats.deepestStage = stageId
	end
	player:SetAttribute(DEEPEST_ATTR, tonumber(data.stats.deepestStage) or 1)
end

--- Snapshot `player`'s masteries and push them if anything changed. `quiet` records
--- the tiers without announcing any (the first look after a load).
local function check(player: Player, data: any, quiet: boolean)
	reach(player, data, StageService.stageOf(player))

	local snapshot = Mastery.snapshot(data)
	local record = seen[player]
	local unlocked = {}
	local parts = table.create(#snapshot)
	local tiers = {}
	for _, entry in snapshot do
		-- Whole numbers only: Speed banks fractions every tick, and the panel never
		-- shows them, so they would push a payload nobody can see change.
		entry.count = math.floor(entry.count)
		table.insert(parts, `{entry.id}={entry.count}`)
		tiers[entry.id] = entry.tier
		local was = if record then record.tiers[entry.id] else nil
		if not quiet and was ~= nil and entry.tier > was then
			table.insert(unlocked, { id = entry.id, tier = entry.tier })
		end
	end
	local signature = table.concat(parts, ",")

	if record and record.signature == signature then
		return
	end
	seen[player] = { tiers = tiers, signature = signature }

	player:SetAttribute(BOMB_ATTR, Mastery.value(data, "bombDamage"))
	stateRemote:FireClient(player, {
		masteries = snapshot,
		unlocked = if #unlocked > 0 then unlocked else nil,
	})
	for _, entry in unlocked do
		local def = Mastery.get(entry.id)
		if def then
			print(`[mastery] {player.Name} reached {def.name} {Masteries.TIER_NAMES[entry.tier]}: {Mastery.rewardText(def, entry.tier)}`)
		end
	end
end

--- Push `player`'s panel now, whether or not anything changed (the client asked).
function MasteryService.push(player: Player)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local record = seen[player]
	if record then
		record.signature = ""
	end
	check(player, data, record == nil)
end

function MasteryService.init()
	stateRemote = Net.get("MasteryState")
end

function MasteryService.start()
	DataService.onLoaded(function(player, data)
		check(player, data, true)
	end)

	StageService.onChanged(function(player, newStage)
		local data = DataService.data(player)
		if data then
			reach(player, data, newStage)
		end
	end)

	-- The panel asks once when it is built, in case it missed the load push.
	stateRemote.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (askedAt[player] or -math.huge) < POLL_SECONDS then
			return
		end
		askedAt[player] = now
		MasteryService.push(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		seen[player] = nil
		askedAt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			for _, player in Players:GetPlayers() do
				local data = DataService.data(player)
				if data then
					local ok, err = pcall(check, player, data, seen[player] == nil)
					if not ok then
						warn(`[mastery] check failed for {player.Name}: {err}`)
					end
				end
			end
		end
	end)
end

return MasteryService
