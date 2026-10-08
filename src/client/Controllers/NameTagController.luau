--!strict
--[[
	NameTagController.luau — the quiet world-space player name tag.

	Roblox's default Humanoid name display is bright white and is not exposed as a
	styling surface. Hide that display locally and give every client a small, muted
	version instead. Each client builds tags for every character, so names remain
	visible to everyone without replicating UI instances from the server.

	THE HP BAR sits over the name: a chunky outlined red pill of that player's health
	with "72 / 100" printed across it (the Health / MaxHealth attributes ExposureService
	publishes on the Player). Other players only -- your own health is already on the
	vitals HUD.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.Parent.UIKit)

local NameTags = {}

local TAG_NAME = "QuietNameTag"
local TAG_COLOR = Color3.fromHex("B7C0B8")
local BAR_NAME = "HealthBar"
-- The vitals HUD's health red and track (HudController STYLE), so the bar reads as
-- the same health everywhere.
local BAR_FILL = Color3.fromHex("FF4D5E")
local BAR_TRACK = Color3.fromHex("3B3340")
local BAR_INK = Color3.fromHex("1A1A1A")
-- The lighter band across the top of the fill: the cartoon shine on the pill.
local BAR_SHINE = Color3.fromHex("FF8A96")
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ONE ANCHOR, STACKED IN PIXELS. The billboards are pixel-sized, so spacing
-- them by stud offsets only works at one distance: further out the studs shrink on
-- screen while the pixels don't, and the pill ends up on top of the name. Both
-- sit on the same anchor and lift themselves with SizeOffset instead -- measured in
-- their own size, so the stack holds its gaps at any range.
local TAG_ANCHOR = Vector3.new(0, 2.9, 0)
local TAG_SIZE = Vector2.new(180, 26)
local BAR_SIZE = Vector2.new(116, 24)
-- Centre-to-centre lifts over the name, in pixels.
local BAR_LIFT = TAG_SIZE.Y / 2 + BAR_SIZE.Y / 2

local function removeTag(character: Model)
	for _, name in { TAG_NAME, BAR_NAME } do
		local existing = character:FindFirstChild(name, true)
		if existing then
			existing:Destroy()
		end
	end
end

--- The HP bar over the name, kept current off the player's
--- Health/MaxHealth attributes.
local function addBar(player: Player, character: Model, head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = BAR_NAME
	gui.Adornee = head
	gui.StudsOffsetWorldSpace = TAG_ANCHOR
	gui.SizeOffset = Vector2.new(0, BAR_LIFT / BAR_SIZE.Y)
	gui.MaxDistance = 55 -- the name tag's reach: a bar with no name under it is a stranger
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0 -- same reason as the name tag's, below
	gui.Parent = character
	local canvas = UIKit.billboardCanvas(gui, BAR_SIZE)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.5)
	track.Size = UDim2.new(1, -6, 1, -6)
	track.BackgroundColor3 = BAR_TRACK
	track.BorderSizePixel = 0
	track.Parent = canvas
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = track
	local stroke = Instance.new("UIStroke")
	stroke.Color = BAR_INK
	stroke.Thickness = 3
	stroke.Parent = track

	-- ClipsDescendants clips to the square box, not the UICorner, so the fill rounds
	-- its own ends instead of relying on the track to trim them.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = BAR_FILL
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner:Clone().Parent = fill

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.new(0.5, 0, 0, 2)
	shine.Size = UDim2.new(1, -8, 0.25, 0)
	shine.BackgroundColor3 = BAR_SHINE
	shine.BorderSizePixel = 0
	shine.Parent = fill
	corner:Clone().Parent = shine

	local readout = UIKit.label(track, {
		name = "Readout",
		size = UDim2.fromScale(1, 1),
		font = UIKit.Font.hero,
		textSize = 12,
		color = Color3.new(1, 1, 1),
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 2,
	})

	local function refresh()
		local health = player:GetAttribute("Health")
		local maxHealth = player:GetAttribute("MaxHealth")
		if typeof(health) ~= "number" or typeof(maxHealth) ~= "number" or maxHealth <= 0 then
			gui.Enabled = false
			return
		end
		gui.Enabled = true
		local frac = math.clamp(health / maxHealth, 0, 1)
		-- Hidden at 0 rather than squashed: a rounded frame narrower than its own
		-- height turns into a red dot stuck at the left end.
		fill.Visible = frac > 0
		TweenService:Create(fill, BAR_TWEEN, { Size = UDim2.fromScale(frac, 1) }):Play()
		readout.Text = `{math.max(math.ceil(health), 0)} / {math.ceil(maxHealth)}`
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
	gui.StudsOffsetWorldSpace = TAG_ANCHOR
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
	local canvas = UIKit.billboardCanvas(gui, TAG_SIZE)

	UIKit.label(canvas, {
		name = "PlayerName",
		size = UDim2.fromScale(1, 1),
		font = Enum.Font.GothamMedium,
		textSize = 14,
		color = TAG_COLOR,
		xAlign = Enum.TextXAlignment.Center,
		text = player.DisplayName,
	})

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
