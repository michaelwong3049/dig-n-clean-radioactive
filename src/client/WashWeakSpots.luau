--!strict
--[[
	WashWeakSpots.luau — the glowing green blisters on a crusted item in the wash bay.

	EVERY CHUNK OF CRUST HAS ONE WEAK POINT (WashService.rollWeak): a seam of fallout
	showing through the slag. Water on it soaks that chunk several times faster and
	shrugs off a tier of the hose's potency shortfall (Contamination.weakGain), so an
	under-tier hose can still take a rare find apart -- if the player can hit it. After a
	second and a half of water it bursts and a new one grows elsewhere on the same chunk.

	THE SERVER OWNS WHICH BLISTER IS LIVE AND HOW MUCH IT IS WORTH; THIS FILE ONLY DRAWS
	IT AND SAYS WHETHER THE WATER IS ON IT. Each patch in the WashState payload carries
	`weak = { id, dir }` while a blister is grown: `dir` is a world direction off the
	chunk's anchor at the pose the item was placed in. The turntable spins client-side,
	so the spot is spun with it here (`spinPoint`, handed in by WashController) and laid
	onto whatever is left of the chunk's surface by a ray cast inward at it -- the crust
	shrinks as it soaks, and a blister floating in the air off a shrunken chunk would be
	the kind of thing nobody aims at twice.

	CLIENT-LOCAL PARTS, NEVER QUERYABLE. The jet's own impact ray must not stop on a
	blister: it has to land on the crust underneath it, which is how `hit` measures.
]]

local Workspace = game:GetService("Workspace")

local Sfx = require(script.Parent.Sfx)

local WashWeakSpots = {}

--- The fallout green the reticle already locks in, at full glow.
local GREEN = Color3.fromHex("6BEE2E")
--- What the reticle turns while the water is ON a blister: hotter, nearly white.
WashWeakSpots.CRIT = Color3.fromHex("E4FF8A")

--- Blister radius as a share of the lump's mean extent, clamped so a bottle cap's lump
--- still gets a target and a boulder's is not a beach ball.
local SIZE_SHARE = 0.045
local SIZE_MIN = 0.16
local SIZE_MAX = 0.32
--- How far round the blister the water still counts, as a multiple of its radius. The
--- jet has width; a hit on the rim is a hit.
local HIT_REACH = 2.2
--- Seconds to grow in, and how hard it throbs once it has.
local GROW = 0.25
local PULSE_RATE = 7
local PULSE_DEPTH = 0.12
--- How fast the drawn spot chases its target as the chunk under it shrinks.
local FOLLOW = 18

type Spot = {
	id: number,
	zone: number,
	core: BasePart,
	halo: BasePart,
	born: number,
	pos: Vector3?,
}

local spots: { [number]: Spot } = {}
local folder: Folder? = nil
local radius = SIZE_MIN
--- Crust parts per zone, rebuilt whenever a new payload lands (ten hertz, not sixty).
local zoneParts: { [number]: { Instance } } = {}
local lastState: any = nil

--- The weak point the water is on right now, for WashController to report.
WashWeakSpots.aimed = nil :: number?

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "WashWeakSpots"
	made.Parent = Workspace
	folder = made
	return made
end

local function ball(name: string, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = GREEN
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.one * 0.05
	part.Parent = parent
	return part
end

local function makeSpot(id: number, zone: number): Spot
	local root = ensureFolder()
	local core = ball(`Weak{zone}`, root)
	local halo = ball(`Weak{zone}Halo`, root)
	halo.Transparency = 0.82
	local light = Instance.new("PointLight")
	light.Color = GREEN
	light.Brightness = 0.8
	light.Range = 2.5
	light.Shadows = false
	light.Parent = core
	return { id = id, zone = zone, core = core, halo = halo, born = os.clock(), pos = nil }
end

local function dropSpot(spot: Spot)
	spot.core:Destroy()
	spot.halo:Destroy()
end

--- The blister bursts: a flash that swells and fades, a spray of green droplets, and a
--- wet crack. Self-cleaning; nothing here outlives a second and a half.
local function burst(at: Vector3)
	local root = ensureFolder()
	local flash = ball("WeakBurst", root)
	flash.Position = at
	flash.Color = WashWeakSpots.CRIT
	local start = os.clock()
	task.spawn(function()
		while flash.Parent do
			local t = (os.clock() - start) / 0.28
			if t >= 1 then
				break
			end
			flash.Size = Vector3.one * radius * (1.4 + t * 3)
			flash.Transparency = 0.15 + t * 0.85
			task.wait()
		end
		flash:Destroy()
	end)

	local carrier = Instance.new("Attachment")
	carrier.WorldPosition = at
	carrier.Parent = Workspace.Terrain
	local drops = Instance.new("ParticleEmitter")
	drops.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drops.Color = ColorSequence.new(GREEN, WashWeakSpots.CRIT)
	drops.LightEmission = 0.8
	drops.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, radius * 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	drops.Transparency = NumberSequence.new(0, 1)
	drops.Lifetime = NumberRange.new(0.35, 0.7)
	drops.Speed = NumberRange.new(4, 9)
	drops.SpreadAngle = Vector2.new(180, 180)
	drops.Acceleration = Vector3.new(0, -Workspace.Gravity * 0.25, 0)
	drops.Rate = 0
	drops.Parent = carrier
	drops:Emit(16)
	task.delay(1.2, function()
		carrier:Destroy()
	end)

	Sfx.playAt("weakPop", at)
end

local function rebuildParts(item: Instance?)
	table.clear(zoneParts)
	if item == nil then
		return
	end
	for _, part in item:GetDescendants() do
		if part:IsA("BasePart") and not part:GetAttribute("CrustShed") then
			local zone = part:GetAttribute("WashZone")
			if type(zone) == "number" then
				local list = zoneParts[zone]
				if list == nil then
					list = {}
					zoneParts[zone] = list
				end
				table.insert(list, part)
			end
		end
	end
end

--- Where the blister sits this frame: on the surface of what is left of its chunk, along
--- its spun direction. Nil if the ray found no rock (the chunk is mid-shed).
local function surfaceAt(anchor: Vector3, dir: Vector3, zone: number, reach: number): Vector3?
	local parts = zoneParts[zone]
	if parts == nil or #parts == 0 then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	-- Include-lists still respect CanQuery; the crust is queryable, the blisters not.
	local origin = anchor + dir * reach
	local result = Workspace:Raycast(origin, -dir * reach, params)
	if result then
		return result.Position
	end
	return nil
end

--- Draw every live blister. Called every render frame by WashController after it has
--- turned the turntable, with the same `spinPoint` it carries the anchors round with.
function WashWeakSpots.update(state: any, item: Instance?, spinPoint: (Vector3) -> Vector3, dt: number)
	if state ~= lastState then
		lastState = state
		rebuildParts(item)
	end

	local reach = 4
	if item and item:IsA("Model") then
		local _, size = item:GetBoundingBox()
		local mean = (size.X + size.Y + size.Z) / 3
		radius = math.clamp(mean * SIZE_SHARE, SIZE_MIN, SIZE_MAX)
		reach = math.max(size.X, size.Y, size.Z) + 1
	end

	local live: { [number]: boolean } = {}
	for _, patch in (state and state.patches) or {} do
		local weak = patch.weak
		local zone = patch.zone
		if type(weak) ~= "table" or type(zone) ~= "number" or patch.anchor == nil then
			continue
		end
		live[zone] = true

		local spot = spots[zone]
		if spot and spot.id ~= weak.id then
			-- The server rolled a new one while the old was still drawn: it popped.
			if spot.pos then
				burst(spot.pos)
			end
			dropSpot(spot)
			spot = nil
		end
		if spot == nil then
			spot = makeSpot(weak.id, zone)
			spots[zone] = spot
		end
		local current = spot :: Spot

		local anchor = spinPoint(patch.anchor)
		local dir = (spinPoint(patch.anchor + weak.dir) - anchor).Unit
		local target = surfaceAt(anchor, dir, zone, reach)
		if target == nil then
			current.core.Transparency = 1
			current.halo.Transparency = 1
			current.pos = nil
			continue
		end
		local pos = current.pos
		pos = if pos then pos:Lerp(target, math.min(dt * FOLLOW, 1)) else target
		current.pos = pos

		local age = os.clock() - current.born
		local grow = math.clamp(age / GROW, 0, 1)
		local throb = 1 + math.sin(age * PULSE_RATE) * PULSE_DEPTH
		local onIt = WashWeakSpots.aimed == current.id
		local size = radius * 2 * grow * throb
		current.core.Transparency = 0
		current.core.Color = if onIt then WashWeakSpots.CRIT else GREEN
		current.core.Size = Vector3.one * size
		current.core.Position = pos
		current.halo.Transparency = if onIt then 0.65 else 0.82
		current.halo.Size = Vector3.one * size * 1.6
		current.halo.Position = pos
	end

	-- Gone from the payload: either respawning after a pop the server rolled between two
	-- frames of ours (burst it), or its chunk came off (the crust's own shed is the FX).
	for zone, spot in spots do
		if not live[zone] then
			local chunkStanding = false
			for _, patch in (state and state.patches) or {} do
				if patch.zone == zone then
					chunkStanding = true
					break
				end
			end
			if chunkStanding and spot.pos then
				burst(spot.pos)
			end
			dropSpot(spot)
			spots[zone] = nil
		end
	end
end

--- Is this landing point on a blister? Returns its zone and id, or nil.
function WashWeakSpots.hit(point: Vector3): (number?, number?)
	local reach = radius * HIT_REACH
	local bestZone: number?, bestId: number? = nil, nil
	for zone, spot in spots do
		local pos = spot.pos
		if pos and spot.core.Transparency < 1 then
			local distance = (pos - point).Magnitude
			if distance < reach then
				reach = distance
				bestZone, bestId = zone, spot.id
			end
		end
	end
	return bestZone, bestId
end

--- Session over: every blister goes, quietly.
function WashWeakSpots.clear()
	for _, spot in spots do
		dropSpot(spot)
	end
	table.clear(spots)
	table.clear(zoneParts)
	lastState = nil
	WashWeakSpots.aimed = nil
	if folder then
		folder:Destroy()
		folder = nil
	end
end

return WashWeakSpots
