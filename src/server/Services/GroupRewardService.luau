--!strict
--[[
	GroupRewardService.luau — the group chest just outside Stage 1 (Config/GroupReward,
	client GroupRewardController). Join the group, step in the ring, claim $25K + 25K
	Speed + 15 min of 2x luck, once -- plus +10% cash forever (GroupReward.CASH_MULT,
	read by StatResolver off `groupRewardClaimed`, so it lasts as long as the save).

	THE CHEST IS BAKED INTO THE PLACE by build/GroupRewardChest (World.rebuild), so it
	shows in Studio's Edit mode. A place saved before that has no chest, so a missing
	one is built here at runtime instead. Moving it means a world rebuild + Save +
	Publish (the client's ring check reads GroupReward.CHEST_POSITION, so keep the two
	in step).

	THE FLOW. Standing in the ring opens the client's rewards card; its CLAIM button
	fires "claim" here. Already claimed -> "already". In the group -> pay, "claimed".
	Not in the group -> "join": the client opens Roblox's own join-group prompt
	(GroupService:PromptJoinAsync) and, if they join, fires "claim" again, where
	membership is checked AGAIN. The client is never trusted about membership. No
	distance check: the gift is once-ever and group-gated, so claiming it from
	anywhere gains nothing.

	MEMBERSHIP IS READ FRESH. Player:IsInGroup caches its first answer for the whole
	session on the server, so a player who joins mid-session would stay "not a member"
	until they rejoin. GroupService:GetGroupsAsync is a live web call; IsInGroup is
	only the fallback when that call fails.

	The grant is the same pieces the packs and the daily calendar use:
	EconomyService.award, LuckBoostService.grant, and speedPoints the way /train pokes
	it (then the treadmill refreshes so the walk speed and the Speed badge follow).
]]

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local GroupReward = require(Shared.Config.GroupReward)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local LuckBoostService = require(script.Parent.LuckBoostService)
local ExhibitService = require(script.Parent.ExhibitService)
local TreadmillService = require(script.Parent.TreadmillService)
local GroupRewardChest = require(script.Parent.Parent.build.GroupRewardChest)

local GroupRewardService = {}

local CLAIM_COOLDOWN = 1

local remote: any = nil
local lastTry: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}

-- ── Membership ───────────────────────────────────────────────────────────────

local function isMember(player: Player): boolean
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, player.UserId)
	if ok and type(groups) == "table" then
		for _, g in groups do
			if g.Id == GroupReward.GROUP_ID then
				return true
			end
		end
		return false
	end
	local ok2, member = pcall(player.IsInGroup, player, GroupReward.GROUP_ID)
	return ok2 and member == true
end

--- Shared with CodeService: shop codes are group-only, by the same live check.
GroupRewardService.isMember = isMember

-- ── Claiming ─────────────────────────────────────────────────────────────────

local function publish(player: Player, data: any)
	player:SetAttribute(GroupReward.CLAIMED_ATTR, data.groupRewardClaimed == true)
end

local function grant(player: Player, data: any)
	data.groupRewardClaimed = true
	EconomyService.award(player, GroupReward.CASH, "group")
	data.speedPoints = (data.speedPoints or 0) + GroupReward.SPEED
	ExhibitService.refreshTreadmill(player)
	TreadmillService.refresh(player)
	LuckBoostService.grant(player, data, GroupReward.LUCK_SECONDS)
	-- The permanent cash bonus is live the moment the flag is set; repaint the $/s.
	ExhibitService.refreshStandCards(player)
	publish(player, data)
end

--- Try to pay the chest out to this player. Yields (the membership web call).
function GroupRewardService.claim(player: Player)
	local t = os.clock()
	if busy[player] or t - (lastTry[player] or -math.huge) < CLAIM_COOLDOWN then
		return
	end
	lastTry[player] = t
	local data = DataService.data(player)
	if data == nil then
		return
	end
	if data.groupRewardClaimed then
		remote:FireClient(player, { result = "already" })
		return
	end

	busy[player] = true
	local member = isMember(player)
	busy[player] = nil

	-- Re-read after the yield: they may have left, or a second claim may have landed.
	data = DataService.data(player)
	if data == nil or player.Parent == nil then
		return
	end
	if data.groupRewardClaimed then
		remote:FireClient(player, { result = "already" })
		return
	end
	if not member then
		remote:FireClient(player, { result = "join", groupId = GroupReward.GROUP_ID })
		return
	end
	grant(player, data)
	print(`[groupreward] {player.Name} claimed the group chest`)
	remote:FireClient(player, { result = "claimed", text = GroupReward.rewardText() })
end

--- /groupchest: forget this player's claim so the chest can be tested again.
function GroupRewardService.debugReset(player: Player)
	local data = DataService.data(player)
	if data then
		data.groupRewardClaimed = false
		publish(player, data)
	end
end

-- ── The chest ────────────────────────────────────────────────────────────────

--- The chest as the place has it, or built now when the saved place predates the
--- baked chest (or someone deleted it): it must never just be missing.
local function ensureChest()
	if Workspace:FindFirstChild(GroupRewardChest.MODEL_NAME) then
		return
	end
	warn("[groupreward] Workspace.GroupRewardChest is missing; building it at runtime (rebuild the world + Save to bake it)")
	GroupRewardChest.build().Parent = Workspace
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────

function GroupRewardService.init()
	remote = Net.get("GroupReward")
end

function GroupRewardService.start()
	ensureChest()

	DataService.onLoaded(function(player, data)
		publish(player, data)
	end)

	remote.OnServerEvent:Connect(function(player: Player, action: any)
		if action == "claim" then
			GroupRewardService.claim(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
		busy[player] = nil
	end)
end

return GroupRewardService
