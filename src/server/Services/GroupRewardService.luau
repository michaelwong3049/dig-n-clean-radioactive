--!strict
--[[
	GroupRewardService.luau — the group chest on Stage 1 (Config/GroupReward, client
	GroupRewardController). Join the group, press E, get $25K + 25K Speed + 5 min of
	2x luck, once.

	THE CHEST IS BUILT HERE AT RUNTIME, not by build/Scenery, so it ships with the
	scripts and needs no place rebuild + Publish. It is a dozen parts.

	THE FLOW. The prompt fires on the server (MaxActivationDistance is the engine's
	proximity check). Already claimed -> "already". In the group -> pay, "claimed".
	Not in the group -> "join": the client opens Roblox's own join-group prompt
	(GroupService:PromptJoinAsync) and, if they join, fires "claim" back here, where
	membership is checked AGAIN. The client is never trusted about membership.

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

local WOOD = Color3.fromHex("8B5A2B")
local WOOD_DARK = Color3.fromHex("6B4220")
local GOLD = Color3.fromHex("F5C542")

local function studded(p: BasePart)
	p.Material = Enum.Material.Plastic
	for _, face in { "TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" } do
		(p :: any)[face] = Enum.SurfaceType.Studs
	end
end

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, metal: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if metal then
		p.Material = Enum.Material.Metal
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
	else
		studded(p)
	end
	p.Parent = model
	return p
end

local function label(parent: Instance, text: string, y: number, h: number, color: Color3, font: Enum.Font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, h, 0)
	l.Position = UDim2.fromScale(0, y)
	l.Text = text
	l.TextScaled = true
	l.Font = font
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.Parent = parent
	return l
end

local function buildChest(): Model
	local model = Instance.new("Model")
	model.Name = "GroupRewardChest"

	-- Chest space: origin on the floor at the chest's centre, front facing +Z.
	local base = CFrame.new(GroupReward.CHEST_POSITION)
	local W, H, D = 7, 3.6, 4.4

	-- The body stands on 0.3-stud feet, so it runs from y 0.3 up to H.
	local body = part(model, "Body", Vector3.new(W, H - 0.3, D), base * CFrame.new(0, (H + 0.3) / 2, 0), WOOD)
	-- The lid: a cylinder along X (a Part cylinder's axis), its lower half sunk into the body.
	local lid = part(model, "Lid", Vector3.new(W, D, D), base * CFrame.new(0, H, 0), WOOD_DARK)
	lid.Shape = Enum.PartType.Cylinder

	-- Gold bands over body and lid, a rim along the seam, and the lock plate.
	for _, x in { -W / 2 + 1.1, W / 2 - 1.1 } do
		part(model, "Band", Vector3.new(0.5, H - 0.2, D + 0.2), base * CFrame.new(x, (H + 0.3) / 2, 0), GOLD, true)
		local bandLid = part(model, "BandLid", Vector3.new(0.5, D + 0.2, D + 0.2), base * CFrame.new(x, H, 0), GOLD, true)
		bandLid.Shape = Enum.PartType.Cylinder
	end
	part(model, "Rim", Vector3.new(W + 0.1, 0.35, D + 0.15), base * CFrame.new(0, H, 0), GOLD, true)
	local lock = part(model, "Lock", Vector3.new(1.1, 1.3, 0.3), base * CFrame.new(0, H - 0.3, D / 2 + 0.15), GOLD, true)
	part(model, "Keyhole", Vector3.new(0.25, 0.45, 0.1), lock.CFrame * CFrame.new(0, -0.1, 0.17), Color3.fromHex("2A1A08"), true)
	-- Feet.
	for _, x in { -W / 2 + 0.4, W / 2 - 0.4 } do
		for _, z in { -D / 2 + 0.4, D / 2 - 0.4 } do
			part(model, "Foot", Vector3.new(0.8, 0.3, 0.8), base * CFrame.new(x, 0.15, z), WOOD_DARK)
		end
	end
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Brightness = 1.2
	light.Range = 12
	light.Parent = lock

	model.PrimaryPart = body

	-- The sign over it. Labels only, no buttons, so a Workspace BillboardGui is fine.
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromOffset(300, 110)
	sign.StudsOffsetWorldSpace = Vector3.new(0, H + 4.5, 0)
	sign.MaxDistance = 90
	sign.LightInfluence = 0
	sign.Adornee = body
	label(sign, "FREE REWARD", 0, 0.34, GOLD, Enum.Font.GothamBlack)
	label(sign, "Join the group + like the game!", 0.36, 0.28, Color3.new(1, 1, 1), Enum.Font.GothamBold)
	local reward = label(sign, GroupReward.rewardText(), 0.66, 0.28, Color3.fromHex("7CFC8A"), Enum.Font.GothamBold)
	reward.Name = "Reward"
	sign.Parent = body

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimPrompt"
	prompt.ActionText = "Claim Reward"
	prompt.ObjectText = "Group Chest"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player)
		GroupRewardService.claim(player)
	end)

	model.Parent = Workspace
	return model
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────

function GroupRewardService.init()
	remote = Net.get("GroupReward")
end

function GroupRewardService.start()
	buildChest()

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
