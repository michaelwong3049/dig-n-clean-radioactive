--!strict
--[[
	GroupRewardChest.luau — the group chest's looks (Config/GroupReward,
	Services/GroupRewardService). World.rebuild() bakes it into the place, so it shows
	in Studio's Edit mode like the rest of the map.

	The user's imported model (ServerStorage.GroupRewardChestModel, in the place file)
	is cloned, scaled and stood at GroupReward.CHEST_POSITION, with sparkles, a light,
	the sign and the gold ring on the ground round it. Without the template it falls
	back to a part chest.

	THIS BUILDS LOOKS ONLY. The ring check is the client's (GroupReward.inRing, off the
	config, not the parts) and the claim is GroupRewardService's. If the chest is
	missing from Workspace (a place saved before this module existed), the service calls
	GroupRewardChest.build itself, so the chest never vanishes.

	NAMES THE CLIENT READS (keep these): Workspace.GroupRewardChest.Body.Sign.Reward,
	the line it swaps to CLAIMED.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GroupReward = require(ReplicatedStorage.Shared.Config.GroupReward)

local Kit = require(script.Parent.Kit)

local GroupRewardChest = {}

local WOOD = Color3.fromHex("8B5A2B")
local WOOD_DARK = Color3.fromHex("6B4220")
local GOLD = Color3.fromHex("F5C542")

local TEMPLATE_NAME = "GroupRewardChestModel"
GroupRewardChest.MODEL_NAME = "GroupRewardChest"
local CHEST_LENGTH = 10.5 -- studs along its long side
local SIGN_DISTANCE = 22
-- The big FREE over it, top to bottom, like the crate pads' gradient titles.
local FREE_TITLE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FFF6C8")),
	ColorSequenceKeypoint.new(0.5, Color3.fromHex("FFE066")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("F5A623")),
})

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

--- A heavier outline than TextStroke: a UIStroke, which a UIGradient on the label leaves
--- black (a gradient tints the legacy TextStroke along with the text).
local function outline(l: TextLabel, thickness: number)
	l.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = l
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

--- The chest, fully formed and UNPARENTED (Kit.swap's contract).
function GroupRewardChest.build(): Model
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
	sign.Size = UDim2.fromOffset(230, 56)
	sign.StudsOffsetWorldSpace = Vector3.new(0, H / 2 + 3, 0)
	-- Only up close: measured from the camera, which trails the player by ~10 studs,
	-- so this shows from about the ring's edge in.
	sign.MaxDistance = SIGN_DISTANCE
	sign.LightInfluence = 0
	sign.Adornee = body
	label(sign, "FREE REWARD", 0, 0.56, GOLD, Enum.Font.GothamBlack)
	-- The client swaps this line to CLAIMED once the gift is paid.
	local reward = label(sign, "Join the group + like the game!", 0.6, 0.4, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	reward.Name = "Reward"
	sign.Parent = body

	-- A big FREE over the sign, sized in studs and seen from across the square, so the
	-- chest reads as free before you're close enough for the sign.
	local free = Instance.new("BillboardGui")
	free.Name = "FreeTitle"
	free.Size = UDim2.fromScale(9, 3.2)
	free.StudsOffsetWorldSpace = Vector3.new(0, H / 2 + 6.5, 0)
	free.MaxDistance = 70
	free.LightInfluence = 0
	free.Adornee = body
	-- A black copy a notch lower is the drop shadow.
	local shadow = label(free, "FREE", 0.06, 0.94, Color3.new(0, 0, 0), Enum.Font.GothamBlack)
	shadow.Name = "TitleShadow"
	outline(shadow, 3)
	local title = label(free, "FREE", 0, 0.94, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	title.Name = "Title"
	outline(title, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = FREE_TITLE
	gradient.Rotation = 90
	gradient.Parent = title
	free.Parent = body

	return model
end

--- Bake the chest into Workspace (World.rebuild).
function GroupRewardChest.rebuild(parent: Instance?): Model
	local model = Kit.swap(GroupRewardChest.MODEL_NAME, GroupRewardChest.build, parent) :: Model
	print(`[build] Group reward chest rebuilt — {#model:GetDescendants()} descendants`)
	return model
end

return GroupRewardChest
