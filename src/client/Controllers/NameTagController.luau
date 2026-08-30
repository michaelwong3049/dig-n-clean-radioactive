--!strict
--[[
	NameTagController.luau — the quiet world-space player name tag.

	Roblox's default Humanoid name display is bright white and is not exposed as a
	styling surface. Hide that display locally and give every client a small, muted
	version instead. Each client builds tags for every character, so names remain
	visible to everyone without replicating UI instances from the server.
]]

local Players = game:GetService("Players")

local NameTags = {}

local TAG_NAME = "QuietNameTag"
local TAG_COLOR = Color3.fromHex("B7C0B8")
local STROKE_COLOR = Color3.fromHex("172018")

local function removeTag(character: Model)
	local existing = character:FindFirstChild(TAG_NAME, true)
	if existing then
		existing:Destroy()
	end
end

local function addTag(player: Player, character: Model)
	removeTag(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 5)
	if humanoid == nil or head == nil or not head:IsA("BasePart") then
		return
	end

	-- This is local-only presentation state; the server still owns the Humanoid.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local gui = Instance.new("BillboardGui")
	gui.Name = TAG_NAME
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(180, 26)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.9, 0)
	gui.MaxDistance = 55
	gui.AlwaysOnTop = false
	-- LightInfluence = 0, NOT 1. Every base carries a PointLight or two right next to
	-- where players stand (the wash pad's disc light, the cleansing station's accent
	-- Lamp), and BillboardGui.LightInfluence = 1 means "render as if lit by the
	-- scene" -- so a muted grey name tag standing near either one washes back toward
	-- white the moment a player walks up to their own base. That is the exact bug
	-- Kit.surfaceText's own header already documents and works around; 0 makes the
	-- tag read as constant, muted text regardless of what is lit nearby.
	gui.LightInfluence = 0
	gui.Parent = character

	local label = Instance.new("TextLabel")
	label.Name = "PlayerName"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = TAG_COLOR
	label.TextStrokeColor3 = STROKE_COLOR
	label.TextStrokeTransparency = 0.72
	label.Text = player.DisplayName
	label.Parent = gui
end

local function watch(player: Player)
	local function onCharacter(character: Model)
		addTag(player, character)
	end

	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function NameTags.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return NameTags
