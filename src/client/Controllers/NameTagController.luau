--!strict
--[[
	NameTagController.luau — the quiet world-space player name tag.

	Roblox's default Humanoid name display is bright white and is not exposed as a
	styling surface. Hide that display locally and give every client a small, muted
	version instead. Each client builds tags for every character, so names remain
	visible to everyone without replicating UI instances from the server.

	THE STAR BADGE sits over the name: "★ 4.2", the average star rating of
	the best three nukes that player is carrying (the BagStars / BagNukes attributes CarryService
	publishes on the Player). A bomb death drops the whole bag for anyone to grab
	(ExposureService), so this is how a bomber sizes up a target (Services/BombService).
	Its own billboard, reaching further than the name, so you can pick a target from
	across a field. Hidden while the bag holds no nukes.

	THE HP BAR sits between the two: a slim red bar of that player's health (the
	Health / MaxHealth attributes ExposureService publishes on the Player). Other
	players only -- your own health is already on the vitals HUD.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.Parent.UIKit)

local NameTags = {}

local TAG_NAME = "QuietNameTag"
local TAG_COLOR = Color3.fromHex("B7C0B8")
local BADGE_NAME = "BagStarBadge"
local BADGE_COLOR = Color3.fromHex("FFD34D")
local BAR_NAME = "HealthBar"
-- The vitals HUD's health red and track (HudController STYLE), so the bar reads as
-- the same health everywhere.
local BAR_FILL = Color3.fromHex("FF4D5E")
local BAR_TRACK = Color3.fromHex("3B3340")
local BAR_INK = Color3.fromHex("1A1A1A")
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function removeTag(character: Model)
	for _, name in { TAG_NAME, BADGE_NAME, BAR_NAME } do
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
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
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
			label.Text = `\u{2605} {string.format("%.1f", average)}`
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

--- The HP bar between the name and the star badge, kept current off the player's
--- Health/MaxHealth attributes.
local function addBar(player: Player, character: Model, head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = BAR_NAME
	gui.Adornee = head
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.55, 0)
	gui.MaxDistance = 55 -- the name tag's reach: a bar with no name over it is a stranger
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0 -- same reason as the name tag's, below
	gui.Parent = character
	local canvas = UIKit.billboardCanvas(gui, Vector2.new(90, 12))

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.5)
	track.Size = UDim2.new(1, -4, 1, -4)
	track.BackgroundColor3 = BAR_TRACK
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Parent = canvas
	local stroke = Instance.new("UIStroke")
	stroke.Color = BAR_INK
	stroke.Thickness = 1.5
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BAR_FILL
	fill.BorderSizePixel = 0
	fill.Parent = track

	local function refresh()
		local health = player:GetAttribute("Health")
		local maxHealth = player:GetAttribute("MaxHealth")
		if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
			gui.Enabled = false
			return
		end
		gui.Enabled = true
		local frac = math.clamp(health / maxHealth, 0, 1)
		TweenService:Create(fill, BAR_TWEEN, { Size = UDim2.fromScale(frac, 1) }):Play()
	end

	local connections = {
		player:GetAttributeChangedSignal("Health"):Connect(refresh),
		player:GetAttributeChangedSignal("MaxHealth"):Connect(refresh),
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
	if player ~= Players.LocalPlayer then
		addBar(player, character, head :: BasePart)
	end
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
