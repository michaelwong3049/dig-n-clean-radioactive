--!strict
--[[
	NameTagController.luau — the quiet world-space player name tag.

	Roblox's default Humanoid name display is bright white and is not exposed as a
	styling surface. Hide that display locally and give every client a small, muted
	version instead. Each client builds tags for every character, so names remain
	visible to everyone without replicating UI instances from the server.

	THE STAR BADGE sits over the name: "★ 4.2 · 6 nukes", the average star rating of
	what that player is carrying (the BagStars / BagNukes attributes CarryService
	publishes on the Player). A bomb death drops the whole bag for anyone to grab
	(ExposureService), so this is how a bomber sizes up a target (Services/BombService).
	Its own billboard, reaching further than the name, so you can pick a target from
	across a field. Hidden while the bag holds no nukes.
]]

local Players = game:GetService("Players")

local UIKit = require(script.Parent.Parent.UIKit)

local NameTags = {}

local TAG_NAME = "QuietNameTag"
local TAG_COLOR = Color3.fromHex("B7C0B8")
local BADGE_NAME = "BagStarBadge"
local BADGE_COLOR = Color3.fromHex("FFD34D")

local function removeTag(character: Model)
	for _, name in { TAG_NAME, BADGE_NAME } do
		local existing = character:FindFirstChild(name, true)
		if existing then
			existing:Destroy()
		end
	end
end

--- The star badge over the name, kept current off the player's BagStars/BagNukes.
local function addBadge(player: Player, character: Model, head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = BADGE_NAME
	gui.Adornee = head
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.1, 0)
	gui.MaxDistance = 120
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0 -- same reason as the name tag's, below
	gui.Parent = character
	local canvas = UIKit.billboardCanvas(gui, Vector2.new(200, 26))

	local label = UIKit.label(canvas, {
		name = "Stars",
		size = UDim2.fromScale(1, 1),
		font = Enum.Font.GothamBold,
		textSize = 17,
		color = BADGE_COLOR,
		xAlign = Enum.TextXAlignment.Center,
		-- Plain text, no shadow copy: UIKit's shadow is a sibling that never hears a
		-- Text change (the same reason the hotbar's names turn it off).
		shadow = false,
	})

	local function refresh()
		local stars = player:GetAttribute("BagStars")
		local count = player:GetAttribute("BagNukes")
		local nukes = if typeof(count) == "number" then count else 0
		gui.Enabled = nukes > 0
		if nukes > 0 then
			local average = if typeof(stars) == "number" then stars else 0
			label.Text = `\u{2605} {string.format("%.1f", average)}  \u{00B7}  {nukes} {if nukes == 1 then "nuke" else "nukes"}`
		end
	end

	local connections = {
		player:GetAttributeChangedSignal("BagStars"):Connect(refresh),
		player:GetAttributeChangedSignal("BagNukes"):Connect(refresh),
	}
	gui.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	refresh()
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
	-- 180x26 design pixels, scaled with the rest of the HUD (UIKit.billboardCanvas) so a
	-- name keeps its size relative to everything else on a big screen.
	local canvas = UIKit.billboardCanvas(gui, Vector2.new(180, 26))

	UIKit.label(canvas, {
		name = "PlayerName",
		size = UDim2.fromScale(1, 1),
		font = Enum.Font.GothamMedium,
		textSize = 14,
		color = TAG_COLOR,
		xAlign = Enum.TextXAlignment.Center,
		text = player.DisplayName,
	})

	addBadge(player, character, head :: BasePart)
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
