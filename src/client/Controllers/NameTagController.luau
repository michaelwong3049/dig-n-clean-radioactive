--!strict
--[[
	NameTagController.luau — the world-space player name tag, in the studded look.

	Roblox's default Humanoid name display is not exposed as a styling surface. Hide
	that display locally and give every client its own: the name on a purple striped
	plate (2026-10-04, the shop panel's studded style; see client/Studded). Each client
	builds tags for every character, so names remain
	visible to everyone without replicating UI instances from the server.

	THE STAR BADGE sits over the name: "★ 4.2", the average star rating of
	the best three nukes that player is carrying (the BagStars / BagNukes attributes CarryService
	publishes on the Player). A bomb death drops the whole bag for anyone to grab
	(ExposureService), so this is how a bomber sizes up a target (Services/BombService).
	Its own billboard, reaching further than the name, so you can pick a target from
	across a field. Hidden while the bag holds no nukes.

	THE HP BAR sits between the two: a lime bar in a dark studded track (red when low)
	with "72 / 100" printed across it (the Health / MaxHealth attributes ExposureService
	publishes on the Player). Other players only -- your own health is already on the
	vitals HUD.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.Parent.UIKit)
local Studded = require(script.Parent.Parent.Studded)

local NameTags = {}

local TAG_NAME = "QuietNameTag"
local BADGE_NAME = "BagStarBadge"
local BAR_NAME = "HealthBar"
-- THE STUDDED LOOK (2026-10-04, on request: "do the name tag in the same studded style"
-- as the shop panel). The name sits on a purple striped plate like the shop's title
-- bar, the stars on a gold studded chip, and health is a lime bar in a dark studded
-- track that turns red when low. All three are inked. See client/Studded.
local BAR_TRACK = Color3.fromHex("2B2F36")
local BAR_LOW = 0.3 -- at or under this share of max health the fill turns red
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ONE ANCHOR, STACKED IN PIXELS. The three billboards are pixel-sized, so spacing
-- them by stud offsets only works at one distance: further out the studs shrink on
-- screen while the pixels don't, and the pill ends up on top of the name. All three
-- sit on the same anchor and lift themselves with SizeOffset instead -- measured in
-- their own size, so the stack holds its gaps at any range.
local TAG_ANCHOR = Vector3.new(0, 2.9, 0)
local TAG_SIZE = Vector2.new(220, 30)
local BAR_SIZE = Vector2.new(124, 24)
local BADGE_SIZE = Vector2.new(200, 28)
-- Centre-to-centre lifts over the name, in pixels.
local BAR_LIFT = TAG_SIZE.Y / 2 + BAR_SIZE.Y / 2
local BADGE_LIFT = BAR_LIFT + BAR_SIZE.Y / 2 + BADGE_SIZE.Y / 2

local function removeTag(character: Model)
	for _, name in { TAG_NAME, BADGE_NAME, BAR_NAME } do
		local existing = character:FindFirstChild(name, true)
		if existing then
			existing:Destroy()
		end
	end
end

--- A studded plate centred in `canvas` that grows to fit its one line of text: the
--- plate's colour (a Studded gradient), its tile overlay, and the inked label.
local function plate(canvas: Instance, colors: ColorSequence, tile: string, tileSize: number, tileFade: number, textSize: number): TextLabel
	local frame = Instance.new("Frame")
	frame.Name = "Plate"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(0, 0, 1, -6)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.BorderSizePixel = 0
	frame.Parent = canvas
	Studded.fill(frame, colors)
	Studded.edge(frame, 8, 2.5)
	Studded.tile(frame, tile, tileSize, tileFade, 8)

	local label = Studded.text(frame, "Text", textSize, 2)
	label.Size = UDim2.fromScale(0, 1)
	label.AutomaticSize = Enum.AutomaticSize.X
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 9)
	pad.PaddingRight = UDim.new(0, 9)
	pad.Parent = label
	return label
end

--- The star badge over the name, kept current off the player's BagStars/BagNukes.
local function addBadge(player: Player, character: Model, head: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = BADGE_NAME
	gui.Adornee = head
	gui.StudsOffsetWorldSpace = TAG_ANCHOR
	gui.SizeOffset = Vector2.new(0, BADGE_LIFT / BADGE_SIZE.Y)
	gui.MaxDistance = 120
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0 -- same reason as the name tag's, below
	gui.Parent = character
	local canvas = UIKit.billboardCanvas(gui, BADGE_SIZE)

	local label = plate(canvas, Studded.GOLD, Studded.STUDS, 14, 0.3, 15)
	label.Name = "Stars"

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
	Studded.edge(track, 8, 2.5)
	Studded.tile(track, Studded.STUDS, 12, 0.45, 8)

	-- ClipsDescendants clips to the square box, not the UICorner, so the fill rounds
	-- its own ends instead of relying on the track to trim them.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = fill
	local fillColor = Studded.fill(fill, Studded.LIME)

	local readout = Studded.text(track, "Readout", 12, 1.5)
	readout.Size = UDim2.fromScale(1, 1)

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
		fillColor.Color = if frac <= BAR_LOW then Studded.RED else Studded.LIME
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
	-- tag read as its own colours regardless of what is lit nearby.
	gui.LightInfluence = 0
	gui.Parent = character
	-- 220x30 design pixels, scaled with the rest of the HUD (UIKit.billboardCanvas) so a
	-- name keeps its size relative to everything else on a big screen.
	local canvas = UIKit.billboardCanvas(gui, TAG_SIZE)

	local name = plate(canvas, Studded.PURPLE, Studded.STRIPES, 32, 0, 16)
	name.Name = "PlayerName"
	name.Text = player.DisplayName

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
