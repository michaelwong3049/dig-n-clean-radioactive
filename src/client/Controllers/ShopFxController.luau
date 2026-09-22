--!strict
--[[
	ShopFxController.luau — the little motion on the plaza stalls' theme props.

	WHAT IT READS. Anything tagged `ShopFx` (Shared/ShopFx, stamped by
	build/ShopThemes), with a `ShopFx` attribute naming what it does:

	  * SPIN — the Detector's radar head turns slowly about the top of its mast.
	  * SWAY — the Magnet's crane load swings a few degrees on its cable, like it was
	    just set down.
	  * DRIP — water drops fall from the Hose Shop's shower heads to the floor, one
	    every second or so per head, each head on its own random beat.

	A moving group is a Model whose WorldPivot is the joint it turns about, so this
	file moves it with PivotTo off the pose it arrived in and never needs to know the
	geometry.

	ALL OF IT IS LOCAL, the same as ItemFxController: the server's parts are moved on
	this client only, so nothing replicates per frame. Drops are client-only parts in
	a local folder.

	CULLED BY DISTANCE. Past ANIMATE_RANGE from the camera a prop holds whatever pose
	it had and a head stops dripping — nobody reads a radar turning from across the
	map, and the plaza is where players spend the least time.

	NOTHING GLOWS. The drops are pale, half-clear plastic: water, not light (Kit.C's
	no-Neon rule covers shop props).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ShopFx = require(ReplicatedStorage.Shared.ShopFx)

local Controller = {}

local ANIMATE_RANGE = 140 -- studs from the camera

local SPIN_SPEED = 0.6 -- radians per second: one turn every ~10s

local SWAY_ANGLE = math.rad(5) -- front-to-back swing, each way
local SWAY_SIDE = 0.35 -- the side-to-side swing, as a share of the front-to-back one
local SWAY_PERIOD = 3.4 -- seconds per full swing

local DRIP_GAP_MIN, DRIP_GAP_MAX = 0.7, 1.6 -- seconds between drops from one head
local DRIP_GRAVITY = 45 -- studs/s², a touch under the game's, so a drop is visible
local DRIP_SIZE = 0.16
local DRIP_COLOR = Color3.fromHex("BFE6FF")
local DRIP_TRANSPARENCY = 0.3

type Entry = {
	instance: Instance,
	kind: string,
	base: CFrame,
	phase: number, -- a random offset so two props never move in step
	angle: number, -- SPIN: the head's current turn
	nextDrip: number, -- DRIP: os.clock() of the next drop
}

type Drop = {
	part: BasePart,
	start: Vector3,
	age: number,
	fall: number,
}

local entries: { [Instance]: Entry } = {}
local drops: { Drop } = {}
local rng = Random.new()
local dropFolder: Folder? = nil

local function pivotOf(instance: Instance): CFrame?
	if instance:IsA("Model") then
		return instance:GetPivot()
	elseif instance:IsA("BasePart") then
		return instance.CFrame
	end
	return nil
end

local function track(instance: Instance)
	local kind = instance:GetAttribute(ShopFx.ATTRIBUTE)
	if kind ~= ShopFx.SPIN and kind ~= ShopFx.SWAY and kind ~= ShopFx.DRIP then
		return
	end
	local base = pivotOf(instance)
	if base == nil then
		return
	end
	entries[instance] = {
		instance = instance,
		kind = kind :: string,
		base = base,
		phase = rng:NextNumber(0, SWAY_PERIOD),
		angle = rng:NextNumber(0, math.pi * 2),
		nextDrip = os.clock() + rng:NextNumber(0, DRIP_GAP_MAX),
	}
end

local function untrack(instance: Instance)
	entries[instance] = nil
end

local function spawnDrop(head: BasePart, fall: number)
	local folder = dropFolder
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "ShopFxDrops"
		folder.Parent = Workspace
		dropFolder = folder
	end

	-- The head is an upright cylinder, so its underside is half its length (Size.X,
	-- the cylinder's axis) below its centre.
	local start = head.Position - Vector3.new(0, head.Size.X / 2, 0)
	local part = Instance.new("Part")
	part.Name = "Drop"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * DRIP_SIZE
	part.Color = DRIP_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = DRIP_TRANSPARENCY
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Position = start
	part.Parent = folder
	table.insert(drops, { part = part, start = start, age = 0, fall = fall })
end

local function stepEntry(entry: Entry, now: number, dt: number, camera: Vector3)
	if (entry.base.Position - camera).Magnitude > ANIMATE_RANGE then
		return
	end
	local instance = entry.instance

	if entry.kind == ShopFx.SPIN then
		entry.angle = (entry.angle + SPIN_SPEED * dt) % (math.pi * 2)
		local model = instance :: Model
		model:PivotTo(entry.base * CFrame.Angles(0, entry.angle, 0))
	elseif entry.kind == ShopFx.SWAY then
		local a = SWAY_ANGLE * math.sin((now + entry.phase) * 2 * math.pi / SWAY_PERIOD)
		local model = instance :: Model
		model:PivotTo(entry.base * CFrame.Angles(a, 0, a * SWAY_SIDE))
	elseif entry.kind == ShopFx.DRIP then
		if now >= entry.nextDrip then
			entry.nextDrip = now + rng:NextNumber(DRIP_GAP_MIN, DRIP_GAP_MAX)
			local fall = instance:GetAttribute(ShopFx.DRIP_FALL)
			if type(fall) == "number" and fall > 0 then
				spawnDrop(instance :: BasePart, fall)
			end
		end
	end
end

--- Advance every falling drop; a drop that has reached the floor is gone.
local function stepDrops(dt: number)
	for i = #drops, 1, -1 do
		local drop = drops[i]
		drop.age += dt
		local fallen = 0.5 * DRIP_GRAVITY * drop.age * drop.age
		if fallen >= drop.fall then
			drop.part:Destroy()
			table.remove(drops, i)
		else
			drop.part.Position = drop.start - Vector3.new(0, fallen, 0)
		end
	end
end

function Controller.start()
	for _, instance in CollectionService:GetTagged(ShopFx.TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(ShopFx.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(ShopFx.TAG):Connect(untrack)

	RunService.Heartbeat:Connect(function(dt: number)
		if next(entries) == nil and #drops == 0 then
			return
		end
		local camera = Workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		local now = os.clock()
		for _, entry in entries do
			stepEntry(entry, now, dt, cameraPosition)
		end
		stepDrops(dt)
	end)
end

return Controller
