--!strict
--[[
	GroupRewardController.luau — the client half of the group chest just outside
	Stage 1 (Config/GroupReward, Services/GroupRewardService).

	STEP IN THE RING, SEE THE CARD. Standing inside the gold ring round the chest
	(GroupReward.inRing, checked a few times a second) opens the rewards card: the
	three gifts and a CLAIM button. Walking out closes it. Closing it with X while still
	inside keeps it shut until you step out and back in.

	The server answers a claim on Net GroupReward:
	  "join"     not in the group yet: open Roblox's own join-group prompt
	             (GroupService:PromptJoinAsync) and, if they join, claim again. The
	             server re-checks membership itself.
	  "claimed"  paid: the card flips to CLAIMED and a toast says what they got.
	  "already"  the card flips to CLAIMED.

	Once claimed (the GroupRewardClaimed Player attribute), the card's button reads
	CLAIMED and the chest's sign thanks them.
]]

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local GroupReward = require(ReplicatedStorage.Shared.Config.GroupReward)
local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local CloverArt = require(script.Parent.Parent.CloverArt)
local Sfx = require(script.Parent.Parent.Sfx)

local GroupRewardController = {}

local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	card = Color3.fromHex("252A30"),
	off = Color3.fromHex("3A4047"),
	dim = Color3.fromHex("9AA3AD"),
	close = Color3.fromHex("E5484D"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	gold = Color3.fromRGB(255, 200, 51),
	cash = Color3.fromRGB(120, 230, 120),
	speed = Color3.fromRGB(110, 190, 255),
	luck = Color3.fromRGB(110, 220, 120),
	claim = Color3.fromRGB(62, 190, 90),
	font = Enum.Font.GothamBlack,
}

local PAD = 20
local TILE_W = 150
local TILE_H = 150
local TILE_GAP = 12
local PANEL_W = PAD * 2 + TILE_W * 3 + TILE_GAP * 2
local PANEL_H = PAD + 86 + TILE_H + 18 + 54 + PAD
local CHECK_EVERY = 0.15
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local player = Players.LocalPlayer
local remote: any = nil

local ui: {
	panel: Frame?,
	scale: UIScale?,
	button: TextButton?,
	buttonEdge: UIStroke?,
	toast: TextLabel?,
} = {}

local inside = false
local dismissed = false -- closed with X while still standing in the ring
local waiting = false -- a claim is out with the server
local prompting = false
local toastToken = 0

-- ── Little builders ──────────────────────────────────────────────────────────

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

--- A label in the panels' voice: GothamBlack, white, ink-outlined (DailyRewardsController's).
local function inked(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = PANEL.font
	label.TextColor3 = PANEL.white
	label.TextXAlignment = Enum.TextXAlignment.Center
	for key, value in props do
		(label :: any)[key] = value
	end
	local stroke = Instance.new("UIStroke")
	stroke.Color = PANEL.ink
	stroke.Thickness = math.max(1.5, label.TextSize * 0.09)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function claimed(): boolean
	return player:GetAttribute(GroupReward.CLAIMED_ATTR) == true
end

-- ── The toast ────────────────────────────────────────────────────────────────

local function showToast(text: string, color: Color3)
	if ui.toast == nil then
		local gui = Instance.new("ScreenGui")
		gui.Name = "GroupRewardToast"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 111
		gui.Parent = player:WaitForChild("PlayerGui")
		ui.toast = UIKit.label(UIKit.canvas(gui), {
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
	local label = ui.toast :: TextLabel
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

-- ── The card ─────────────────────────────────────────────────────────────────

local function paint()
	local button, stroke = ui.button, ui.buttonEdge
	if button == nil or stroke == nil then
		return
	end
	local done = claimed()
	button.Text = if done then "CLAIMED" elseif waiting then "..." else "CLAIM"
	button.BackgroundColor3 = if done or waiting then PANEL.off else PANEL.claim
	button.Active = not done and not waiting
	button.AutoButtonColor = button.Active
end

local function rewardTile(parent: Instance, index: number, title: string, sub: string, color: Color3): Frame
	local tile = Instance.new("Frame")
	tile.Name = `Reward{index}`
	tile.Size = UDim2.fromOffset(TILE_W, TILE_H)
	tile.Position = UDim2.fromOffset(PAD + (index - 1) * (TILE_W + TILE_GAP), PAD + 86)
	tile.BackgroundColor3 = PANEL.card
	tile.BorderSizePixel = 0
	tile.ZIndex = 12
	tile.Parent = parent
	round(tile, 8)
	edge(tile, PANEL.ink, 3)
	inked(tile, {
		Name = "Title",
		Text = title,
		TextSize = 24,
		TextColor3 = color,
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 1, -50),
		ZIndex = 14,
	})
	inked(tile, {
		Name = "Sub",
		Text = sub,
		TextSize = 14,
		TextColor3 = PANEL.dim,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -24),
		ZIndex = 14,
	})
	return tile
end

local function icon(tile: Frame, image: string)
	local pic = Artwork.picture(tile, "Icon", image, 76, PANEL.white)
	pic.AnchorPoint = Vector2.new(0.5, 0)
	pic.Position = UDim2.new(0.5, 0, 0, 12)
	pic.ZIndex = 13
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GroupRewardPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.Position = UDim2.new(0.5, 0, 0.5, -20)
	panel.BackgroundColor3 = PANEL.panel
	panel.BorderSizePixel = 0
	panel.ZIndex = 10
	panel.Visible = false
	panel.Parent = canvas
	round(panel, 8)
	edge(panel, PANEL.ink, 4)
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	inked(panel, {
		Name = "Title",
		Text = "Free Group Reward",
		TextSize = 36,
		TextColor3 = PANEL.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(PANEL_W - PAD * 2 - 50, 44),
		Position = UDim2.fromOffset(PAD, PAD - 6),
		ZIndex = 11,
	})
	inked(panel, {
		Name = "Subtitle",
		Text = "Join the group and like the game to claim. One time only!",
		TextSize = 16,
		TextColor3 = PANEL.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -PAD * 2, 0, 20),
		Position = UDim2.fromOffset(PAD + 2, PAD + 42),
		ZIndex = 11,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -PAD, 0, PAD - 4)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = PANEL.close
	close.Font = PANEL.font
	close.TextSize = 24
	close.TextColor3 = PANEL.white
	close.Text = "X"
	close.ZIndex = 11
	close.Parent = panel
	round(close, 6)
	edge(close, PANEL.ink, 3)
	close.Activated:Connect(function()
		dismissed = true
		panel.Visible = false
	end)

	icon(rewardTile(panel, 1, "$25K", "Cash", PANEL.cash), Artwork.IMAGE.cashBundle)
	icon(rewardTile(panel, 2, "25K", "Speed", PANEL.speed), Artwork.IMAGE.speedShoe)
	local luckTile = rewardTile(panel, 3, "2x Luck", `{math.floor(GroupReward.LUCK_SECONDS / 60)} minutes`, PANEL.luck)
	local clover = CloverArt.build(luckTile, 76, 13)
	clover.AnchorPoint = Vector2.new(0.5, 0)
	clover.Position = UDim2.new(0.5, 0, 0, 12)

	local button = Instance.new("TextButton")
	button.Name = "Claim"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -PAD)
	button.Size = UDim2.new(1, -PAD * 2, 0, 54)
	button.BackgroundColor3 = PANEL.claim
	button.Font = PANEL.font
	button.TextSize = 26
	button.TextColor3 = PANEL.white
	button.Text = "CLAIM"
	button.ZIndex = 11
	button.Parent = panel
	round(button, 6)
	ui.buttonEdge = edge(button, PANEL.ink, 3)
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = PANEL.ink
	textStroke.Thickness = 2
	textStroke.Parent = button
	button.Activated:Connect(function()
		if not button.Active or claimed() then
			return
		end
		Sfx.play("click")
		waiting = true
		paint()
		remote:FireServer("claim")
		-- Never leave the button stuck on "..." if the answer goes missing.
		task.delay(6, function()
			if waiting then
				waiting = false
				paint()
			end
		end)
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	ui.panel = panel
	ui.scale = scale
	ui.button = button
	paint()
end

local function setOpen(open: boolean)
	local panel = ui.panel
	if panel == nil or panel.Visible == open then
		return
	end
	panel.Visible = open
	if open then
		paint()
		local scale = ui.scale :: UIScale
		scale.Scale = 0.85
		TweenService:Create(scale, OPEN, { Scale = 1 }):Play()
	end
end

-- ── The chest's sign ─────────────────────────────────────────────────────────

local function paintSign()
	local chest = Workspace:FindFirstChild("GroupRewardChest")
	local body = chest and chest:FindFirstChild("Body")
	local sign = body and body:FindFirstChild("Sign")
	local reward = sign and sign:FindFirstChild("Reward") :: TextLabel?
	if reward then
		reward.Text = if claimed() then "CLAIMED - thanks for the support!" else "Join the group + like the game!"
	end
end

-- ── Joining ──────────────────────────────────────────────────────────────────

local function askToJoin(groupId: number)
	if prompting then
		return
	end
	prompting = true
	local ok, status = pcall(GroupService.PromptJoinAsync, GroupService, groupId)
	prompting = false
	if ok and (status == Enum.GroupMembershipStatus.Joined or status == Enum.GroupMembershipStatus.AlreadyMember) then
		waiting = true
		paint()
		remote:FireServer("claim")
	elseif ok and status == Enum.GroupMembershipStatus.JoinRequestPending then
		showToast("Join request sent - claim again once you're in!", UIKit.C.amber)
	elseif ok then
		showToast("Join the group to claim your free reward!", UIKit.C.amber)
	else
		showToast("Join our group from the game page, then claim again!", UIKit.C.amber)
	end
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────

function GroupRewardController.start()
	remote = Net.get("GroupReward")
	build()

	remote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		waiting = false
		if payload.result == "join" then
			task.spawn(askToJoin, tonumber(payload.groupId) or GroupReward.GROUP_ID)
		elseif payload.result == "claimed" then
			Sfx.play("click")
			showToast(`Reward claimed! +{payload.text or GroupReward.rewardText()}`, UIKit.C.green)
		elseif payload.result == "already" then
			showToast("You've already claimed this reward!", UIKit.C.amber)
		end
		paint()
	end)

	player:GetAttributeChangedSignal(GroupReward.CLAIMED_ATTR):Connect(function()
		paint()
		paintSign()
	end)

	-- StreamingEnabled: the chest's parts stream in (and back in) on their own
	-- schedule, each time with the server's sign text, so repaint when the sign lands.
	local function watch(chest: Instance)
		chest.DescendantAdded:Connect(function(d)
			if d.Name == "Reward" then
				task.defer(paintSign)
			end
		end)
		paintSign()
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

	-- The ring. A flat distance check off the config, not Touched, so it works however
	-- the ring's parts have streamed and never fires on a stray limb.
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local now = root ~= nil and GroupReward.inRing(root.Position)
			if now ~= inside then
				inside = now
				if not now then
					dismissed = false
				end
				setOpen(now and not dismissed)
			end
		end
	end)
end

return GroupRewardController
