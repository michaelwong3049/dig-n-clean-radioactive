--!strict
--[[
	GroupRewardController.luau — the client half of the group chest on Stage 1
	(Config/GroupReward, Services/GroupRewardService).

	The server answers every press of the chest's prompt on Net GroupReward:
	  "join"     not in the group yet: open Roblox's own join-group prompt
	             (GroupService:PromptJoinAsync) and, if they join, ask the server to
	             claim again. The server re-checks membership itself.
	  "claimed"  paid: a one-line toast with what they got.
	  "already"  a reminder that it was a one-time gift.

	Once claimed (the GroupRewardClaimed Player attribute), the chest's prompt is
	switched off locally and its sign reads CLAIMED.
]]

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local GroupReward = require(ReplicatedStorage.Shared.Config.GroupReward)
local UIKit = require(script.Parent.Parent.UIKit)

local GroupRewardController = {}

local player = Players.LocalPlayer
local remote: any = nil
local toast: TextLabel? = nil
local toastToken = 0
local prompting = false

local function showToast(text: string, color: Color3)
	if toast == nil then
		local gui = Instance.new("ScreenGui")
		gui.Name = "GroupRewardToast"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 104
		gui.Parent = player:WaitForChild("PlayerGui")
		toast = UIKit.label(UIKit.canvas(gui), {
			name = "Toast",
			size = UDim2.fromOffset(760, 30),
			position = UDim2.new(0.5, 0, 1, -UIKit.Dock.VITALS_CLEAR),
			anchorPoint = Vector2.new(0.5, 1),
			text = "",
			font = UIKit.Font.title,
			textSize = UIKit.TextSize.header,
			color = color,
			xAlign = Enum.TextXAlignment.Center,
			visible = false,
		})
	end
	local label = toast :: TextLabel
	toastToken += 1
	local token = toastToken
	label.Text = text
	label.TextColor3 = color
	label.Visible = true
	task.delay(3, function()
		if token == toastToken then
			label.Visible = false
		end
	end)
end

local function applyClaimed()
	local claimed = player:GetAttribute(GroupReward.CLAIMED_ATTR) == true
	local chest = Workspace:FindFirstChild("GroupRewardChest")
	local body = chest and chest:FindFirstChild("Body")
	if body == nil then
		return
	end
	local prompt = body:FindFirstChild("ClaimPrompt") :: ProximityPrompt?
	if prompt then
		prompt.Enabled = not claimed
	end
	local reward = body:FindFirstChild("Sign") and (body :: any).Sign:FindFirstChild("Reward") :: TextLabel?
	if reward then
		reward.Text = if claimed then "CLAIMED - thanks for the support!" else GroupReward.rewardText()
	end
end

local function askToJoin(groupId: number)
	if prompting then
		return
	end
	prompting = true
	showToast("Join the group to claim your free reward!", UIKit.C.amber)
	local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, groupId)
	prompting = false
	if ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember) then
		remote:FireServer("claim")
	elseif ok and status == Enum.GroupMembershipStatus.JoinRequestPending then
		showToast("Join request sent - press E again once you're in!", UIKit.C.amber)
	elseif not ok then
		showToast("Join our group from the game page, then press E again!", UIKit.C.amber)
	end
end

function GroupRewardController.start()
	remote = Net.get("GroupReward")
	remote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.result == "join" then
			task.spawn(askToJoin, tonumber(payload.groupId) or GroupReward.GROUP_ID)
		elseif payload.result == "claimed" then
			showToast(`Reward claimed! +{payload.text or GroupReward.rewardText()}`, UIKit.C.green)
		elseif payload.result == "already" then
			showToast("You've already claimed this reward!", UIKit.C.amber)
		end
	end)

	player:GetAttributeChangedSignal(GroupReward.CLAIMED_ATTR):Connect(applyClaimed)
	-- StreamingEnabled: the chest's parts stream in (and back in after streaming out)
	-- on their own schedule, each time carrying the server's enabled prompt and sign
	-- text, so re-apply whenever one of them lands.
	local function watch(chest: Instance)
		chest.DescendantAdded:Connect(function(d)
			if d.Name == "ClaimPrompt" or d.Name == "Reward" then
				task.defer(applyClaimed)
			end
		end)
		applyClaimed()
	end
	local chest = Workspace:FindFirstChild("GroupRewardChest")
	if chest then
		watch(chest)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "GroupRewardChest" then
			watch(child)
		end
	end)
end

return GroupRewardController
