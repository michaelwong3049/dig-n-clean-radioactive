--!strict
--[[
	CrustDebrisController — pieces of crust tumbling off an item as it is washed.

	The server decides WHEN a piece of slag comes off (Shared/ItemCrust: a flake at its
	own point in the soak, the whole chunk when its patch pops) and says so by hiding the
	part and flipping its `CrustShed` attribute. It cannot throw the falling piece itself:
	the wash bay's turntable spins on the washing player's client (WashController), so the
	server's copy of the part is not where that player sees it. Each client throws its own
	falling copy instead, from wherever the part stands on ITS screen -- spun for the
	washer, still for anyone watching from the plot.

	Local, unanchored and non-colliding: the copy drops away from the item, tumbling, and
	fades out before it has fallen far. Nothing here is gameplay; a client that never runs
	it just sees pieces disappear instead of fall.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ItemCrust = require(ReplicatedStorage.Shared.ItemCrust)

local CrustDebrisController = {}

--- How long a falling piece lives, and the fade it takes to get out of the way.
local LIFETIME = 0.9
local FADE = TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

--- Off the item's side (studs/s, horizontal) and up, before gravity takes it. Small:
--- this is rock sloughing off under a hose, not a blast.
local PUSH_MIN, PUSH_MAX = 3, 6
local LIFT_MIN, LIFT_MAX = 2, 4.5
local SPIN = 8

local watched: { [Instance]: RBXScriptConnection } = {}
local rng = Random.new()

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

local function watch(instance: Instance)
	if watched[instance] or not instance:IsA("BasePart") then
		return
	end
	local part = instance :: BasePart
	watched[part] = part:GetAttributeChangedSignal(ItemCrust.SHED_ATTR):Connect(function()
		if part:GetAttribute(ItemCrust.SHED_ATTR) then
			throw(part)
		end
	end)
end

local function unwatch(instance: Instance)
	local connection = watched[instance]
	if connection then
		connection:Disconnect()
		watched[instance] = nil
	end
end

function CrustDebrisController.start()
	CollectionService:GetInstanceAddedSignal(ItemCrust.TAG):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(ItemCrust.TAG):Connect(unwatch)
	for _, instance in CollectionService:GetTagged(ItemCrust.TAG) do
		watch(instance)
	end
end

return CrustDebrisController
