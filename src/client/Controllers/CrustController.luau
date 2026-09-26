--!strict
--[[
	CrustController — the crust on an item being washed, drawn smooth on each client.

	THE SERVER DECIDES, THIS DRAWS. WashService runs the soak clock and stamps each piece
	of slag with how eroded it is (ItemCrust.erode: the `CrustLevel` and `CrustTough`
	attributes), but that only arrives at the wash tick's ten hertz. Drawn straight off
	it, a chunk shrank in visible steps. So each client eases every piece toward its
	latest level, every frame, and paints the look itself (ItemCrust.paint): size,
	wetness and colour glide down under the stream instead of ticking.

	PIECES COMING OFF. When a flake's moment in the soak comes, or a chunk's patch pops,
	the server hides the part and flips its `CrustShed` attribute (Shared/ItemCrust). It
	cannot throw the falling piece itself: the wash bay's turntable spins on the washing
	player's client (WashController), so the server's copy of the part is not where that
	player sees it. Each client throws its own falling copy instead, from wherever the
	part stands on ITS screen -- spun for the washer, still for anyone watching from the
	plot. Local, unanchored and non-colliding: it drops away from the item, tumbling,
	and fades out before it has fallen far.

	Nothing here is gameplay. Every crust part is tagged, so this finds the lump in a
	hand and the haul's lump too; those never get a level, so they are only watched.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ItemCrust = require(ReplicatedStorage.Shared.ItemCrust)

local CrustController = {}

--- How quickly a drawn level catches the server's, in seconds (exponential ease). About
--- one wash tick: long enough to bridge the gap to the next level so a steady stream
--- reads as one continuous shrink, short enough that the rock never visibly lags the
--- water.
local EASE = 0.12

--- Close enough to stop easing and land exactly on the server's level.
local SETTLE = 0.002

--- How long a falling piece lives, and the fade it takes to get out of the way.
local LIFETIME = 0.9
local FADE = TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--- Off the item's side (studs/s, horizontal) and up, before gravity takes it. Small:
--- this is rock sloughing off under a hose, not a blast.
local PUSH_MIN, PUSH_MAX = 3, 6
local LIFT_MIN, LIFT_MAX = 2, 4.5
local SPIN = 8

type Watch = { connections: { RBXScriptConnection } }

local watched: { [BasePart]: Watch } = {}
--- The level each part is drawn at right now, kept after it settles so the next level
--- from the server eases on from here rather than from dry rock.
local shown: { [BasePart]: number } = {}
--- Only parts still catching up are stepped, so a bay of settled rock costs nothing.
local moving: { [BasePart]: true } = {}
local rng = Random.new()

local function targetOf(part: BasePart): number?
	local level = part:GetAttribute(ItemCrust.LEVEL_ATTR)
	return if type(level) == "number" then level else nil
end

local function toughOf(part: BasePart): boolean
	return part:GetAttribute(ItemCrust.TOUGH_ATTR) == true
end

local function throw(part: BasePart)
	if not part:IsDescendantOf(Workspace) then
		return
	end

	-- Away from the middle of whatever it was stuck to, flattened so a piece on top
	-- still slides off sideways rather than straight up.
	local model = part:FindFirstAncestorWhichIsA("Model")
	local centre = if model then model:GetBoundingBox().Position else part.Position
	local away = part.Position - centre
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 1e-3 then
		local angle = rng:NextNumber(0, 2 * math.pi)
		away = Vector3.new(math.cos(angle), 0, math.sin(angle))
	end

	-- A fresh part rather than a Clone: a clone carries the tag and the shed flag, and
	-- would be picked straight back up by this controller.
	local piece = Instance.new(part.ClassName) :: BasePart
	piece.Name = "CrustDebris"
	piece.Size = part.Size
	piece.CFrame = part.CFrame
	piece.Color = part.Color
	piece.Material = part.Material
	piece.Transparency = 0.1
	piece.CastShadow = false
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.Anchored = false
	piece.Parent = Workspace
	piece.AssemblyLinearVelocity = away.Unit * rng:NextNumber(PUSH_MIN, PUSH_MAX)
		+ Vector3.new(0, rng:NextNumber(LIFT_MIN, LIFT_MAX), 0)
	piece.AssemblyAngularVelocity = Vector3.new(
		rng:NextNumber(-SPIN, SPIN),
		rng:NextNumber(-SPIN, SPIN),
		rng:NextNumber(-SPIN, SPIN)
	)

	TweenService:Create(piece, FADE, { Transparency = 1 }):Play()
	Debris:AddItem(piece, LIFETIME)
end

--- A new level (or toughness) landed from the server: start easing toward it. The very
--- first one starts from dry, whole rock, which is what the part still looks like.
local function onLevel(part: BasePart)
	if part:GetAttribute(ItemCrust.SHED_ATTR) or targetOf(part) == nil then
		return
	end
	if shown[part] == nil then
		shown[part] = 1
	end
	moving[part] = true
end

local function onShed(part: BasePart)
	if part:GetAttribute(ItemCrust.SHED_ATTR) then
		shown[part] = nil
		moving[part] = nil
		throw(part)
	end
end

local function watch(instance: Instance)
	if not instance:IsA("BasePart") or watched[instance :: BasePart] then
		return
	end
	local part = instance :: BasePart
	watched[part] = {
		connections = {
			part:GetAttributeChangedSignal(ItemCrust.SHED_ATTR):Connect(function()
				onShed(part)
			end),
			part:GetAttributeChangedSignal(ItemCrust.LEVEL_ATTR):Connect(function()
				onLevel(part)
			end),
			part:GetAttributeChangedSignal(ItemCrust.TOUGH_ATTR):Connect(function()
				onLevel(part)
			end),
		},
	}

	-- JOINING PART-WAY THROUGH SOMEONE ELSE'S WASH: the level is already down, so draw
	-- it there at once rather than easing a stranger's half-washed rock down from full.
	local target = targetOf(part)
	if target and not part:GetAttribute(ItemCrust.SHED_ATTR) then
		ItemCrust.paint(part, target, toughOf(part))
		shown[part] = target
	end
end

local function unwatch(instance: Instance)
	local part = instance :: BasePart
	local entry = watched[part]
	if entry then
		for _, connection in entry.connections do
			connection:Disconnect()
		end
		watched[part] = nil
	end
	shown[part] = nil
	moving[part] = nil
end

local function step(dt: number)
	local blend = 1 - math.exp(-dt / EASE)
	for part in moving do
		local target = targetOf(part)
		if target == nil or part.Parent == nil or part:GetAttribute(ItemCrust.SHED_ATTR) then
			moving[part] = nil
			continue
		end
		local level = shown[part] or 1
		local nextLevel = level + (target - level) * blend
		if math.abs(target - nextLevel) < SETTLE then
			nextLevel = target
			moving[part] = nil
		end
		shown[part] = nextLevel
		ItemCrust.paint(part, nextLevel, toughOf(part))
	end
end

function CrustController.start()
	CollectionService:GetInstanceAddedSignal(ItemCrust.TAG):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(ItemCrust.TAG):Connect(unwatch)
	for _, instance in CollectionService:GetTagged(ItemCrust.TAG) do
		watch(instance)
	end
	RunService.RenderStepped:Connect(step)
end

return CrustController
