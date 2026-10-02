--!strict
--[[
	GroupRewardService.luau — the group chest just outside Stage 1 (Config/GroupReward,
	client GroupRewardController). Join the group, step in the ring, claim $25K + 25K
	Speed + 5 min of 2x luck, once.

	THE CHEST IS PLACED HERE AT RUNTIME, not by build/Scenery: the user's imported
	model (ServerStorage.GroupRewardChestModel, in the place file) is cloned, scaled
	and stood by the wall, with sparkles, a light, the sign and the gold ring on the
	ground round it added here. Without the template it falls back to a part chest.

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
local ServerStorage = game:GetService("ServerStorage")
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

local TEMPLATE_NAME = "GroupRewardChestModel"
local CHEST_LENGTH = 10.5 -- studs along its long side

local function studded(p: BasePart)
	p.Material = Enum.Material.Plastic
	for _, face in { "TopSurface", "BottomSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" } do
		(p :: any)[face] = Enum.SurfaceType.Studs
	end
end

local function part(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, metal: boolean?): Part
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

--- A flat decoration on the floor: no collision, no shadow, not hit by raycasts.
local function decal(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
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

--- Gold glints drifting up off the chest. Emits from the invisible box's volume.
local function sparkles(model: Model, cf: CFrame, size: Vector3)
	local box = part(model, "Sparkles", size, cf, GOLD)
	box.Transparency = 1
	decal(box)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromHex("FFE58A"), GOLD)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0.1)
	e.Lifetime = NumberRange.new(1.2, 2.2)
	e.Rate = 22
	e.Speed = NumberRange.new(1, 2.5)
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Top
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Parent = box
end

--- The gold ring on the floor round the chest: a circle of short gold segments over a
--- faint gold disc. SmoothPlastic, not Neon: on the floor, Neon's bloom smeared the
--- ring into one yellow blob (checked live).
local function ring(model: Model)
	local centre = GroupReward.CHEST_POSITION
	local radius = GroupReward.RING_RADIUS
	local width = GroupReward.RING_WIDTH
	local count = 44
	local length = 2 * math.pi * radius / count + 0.15
	local folder = Instance.new("Model")
	folder.Name = "Ring"
	for i = 0, count - 1 do
		local a = i / count * 2 * math.pi
		local at = centre + Vector3.new(math.cos(a) * radius, 0.06, math.sin(a) * radius)
		-- Each segment's length runs along the tangent.
		local seg = part(folder, "Segment", Vector3.new(width, 0.12, length), CFrame.lookAt(at, at + Vector3.new(-math.sin(a), 0, math.cos(a))), GOLD, true)
		seg.Material = Enum.Material.SmoothPlastic
		decal(seg)
	end
	local disc = part(folder, "Disc", Vector3.new(0.06, radius * 2, radius * 2), CFrame.new(centre + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.pi / 2), GOLD, true)
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.SmoothPlastic
	disc.Transparency = 0.75
	decal(disc)
	folder.Parent = model
end

--- The user's imported chest (Import 3D, kept in the place file at
--- ServerStorage.GroupRewardChestModel -- not in git, like every world mesh), scaled
--- so its long side is CHEST_LENGTH and stood on the floor at `base`. Its long side is
--- model X and its pivot is its bottom centre, so it lines up with chest space as-is.
--- Returns its height and depth, or nil when the template is missing.
local function importedChest(model: Model, base: CFrame): (number?, number?)
	local template = ServerStorage:FindFirstChild(TEMPLATE_NAME)
	if template == nil or not template:IsA("Model") then
		return nil, nil
	end
	local chest = template:Clone()
	chest.Name = "Chest"
	local _, size = chest:GetBoundingBox()
	chest:ScaleTo(chest:GetScale() * CHEST_LENGTH / size.X)
	chest:PivotTo(base)
	for _, d in chest:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	chest.Parent = model
	local _, scaled = chest:GetBoundingBox()
	return scaled.Y, scaled.Z
end

--- The part-built chest, for when the imported one is missing (an unsaved place).
local function partChest(model: Model, base: CFrame): (number, number)
	local W, H, D = CHEST_LENGTH, 5.4, 6.6
	local FOOT = 0.45

	-- The box stands on its feet, so it runs from y FOOT up to H.
	part(model, "Box", Vector3.new(W, H - FOOT, D), base * CFrame.new(0, (H + FOOT) / 2, 0), WOOD)
	-- The lid: a cylinder along X (a Part cylinder's axis), its lower half sunk into the box.
	local lid = part(model, "Lid", Vector3.new(W, D, D), base * CFrame.new(0, H, 0), WOOD_DARK)
	lid.Shape = Enum.PartType.Cylinder

	-- Gold bands over box and lid, a rim along the seam, and the lock plate.
	for _, x in { -W / 2 + 1.6, W / 2 - 1.6 } do
		part(model, "Band", Vector3.new(0.75, H - FOOT + 0.1, D + 0.3), base * CFrame.new(x, (H + FOOT) / 2, 0), GOLD, true)
		local bandLid = part(model, "BandLid", Vector3.new(0.75, D + 0.3, D + 0.3), base * CFrame.new(x, H, 0), GOLD, true)
		bandLid.Shape = Enum.PartType.Cylinder
	end
	part(model, "Rim", Vector3.new(W + 0.15, 0.5, D + 0.2), base * CFrame.new(0, H, 0), GOLD, true)
	local lock = part(model, "Lock", Vector3.new(1.6, 1.9, 0.4), base * CFrame.new(0, H - 0.45, D / 2 + 0.2), GOLD, true)
	part(model, "Keyhole", Vector3.new(0.35, 0.65, 0.12), lock.CFrame * CFrame.new(0, -0.15, 0.22), Color3.fromHex("2A1A08"), true)
	-- Feet.
	for _, x in { -W / 2 + 0.6, W / 2 - 0.6 } do
		for _, z in { -D / 2 + 0.6, D / 2 - 0.6 } do
			part(model, "Foot", Vector3.new(1.2, FOOT, 1.2), base * CFrame.new(x, FOOT / 2, z), WOOD_DARK)
		end
	end
	return H, D
end

local function buildChest(): Model
	local model = Instance.new("Model")
	model.Name = "GroupRewardChest"

	-- Chest space: origin on the floor at the chest's centre, front facing +Z.
	local base = CFrame.new(GroupReward.CHEST_POSITION) * CFrame.Angles(0, GroupReward.CHEST_FACING, 0)
	local H, D = importedChest(model, base)
	if H == nil or D == nil then
		warn(`[groupreward] ServerStorage.{TEMPLATE_NAME} is missing; building the part chest instead`)
		-- The part chest's lock is on its +Z side, the imported one's front on -Z.
		H, D = partChest(model, base * CFrame.Angles(0, math.pi, 0))
	end
	local W = CHEST_LENGTH

	-- An invisible box round the chest: what the sign and light hang off, and what
	-- the client finds the sign on (Body.Sign), whichever chest was built.
	local body = part(model, "Body", Vector3.new(W, H, D), base * CFrame.new(0, H / 2, 0), GOLD, true)
	body.Transparency = 1
	decal(body)

	local light = Instance.new("PointLight")
	light.Color = GOLD
	-- Short range: a wide one floods the floor yellow and drowns the ring.
	light.Brightness = 0.8
	light.Range = 7
	light.Parent = body

	sparkles(model, base * CFrame.new(0, H * 0.75, 0), Vector3.new(W + 1, H * 0.8, D + 1))
	ring(model)

	model.PrimaryPart = body

	-- The sign over it. Labels only, no buttons, so a Workspace BillboardGui is fine.
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromOffset(320, 120)
	sign.StudsOffsetWorldSpace = Vector3.new(0, H / 2 + 6, 0)
	sign.MaxDistance = 110
	sign.LightInfluence = 0
	sign.Adornee = body
	label(sign, "FREE REWARD", 0, 0.34, GOLD, Enum.Font.GothamBlack)
	label(sign, "Join the group + like the game!", 0.36, 0.28, Color3.new(1, 1, 1), Enum.Font.GothamBold)
	local reward = label(sign, "Step in the ring to claim", 0.66, 0.28, Color3.fromHex("7CFC8A"), Enum.Font.GothamBold)
	reward.Name = "Reward"
	sign.Parent = body

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
