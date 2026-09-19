--[[
	FieldController.lua — the detector's world-space half.

	DetectorController owns the screen. This owns the ground: the range ring the
	detector throws around you, and the glowing cracks of the auras that sit over
	buried signals (client/SpotCracks). Splitting them is not tidiness — the two have
	completely different sources. Everything on the HUD is drawn from a payload only
	this client receives, whereas the auras are SERVER parts that every player in the
	server can see, and this controller may only ever change how they LOOK. Never
	where they are, never whether they exist. If it ever decides that, the reveal has
	moved to the client and the field is a free ESP. (The cracks are client parts, but
	they only ever dress an aura the server already put there, and go when it goes.)

	THE RANGE RING EXISTS BECAUSE THE NEEDLE DIED.
	The old detector answered "which way" continuously, so its range never had to be
	legible — you just followed the arrow until it got loud. A reveal detector answers
	nothing at all outside its radius, which makes that radius the single most
	important number a player owns and, without this, an invisible one. So the ring is
	drawn twice: a faint steady outline sitting exactly on the radius, and a pulse
	that runs out to it once a second so the boundary reads while you are moving.

	It is built from segments rather than a textured decal on purpose. A ring texture
	is an asset id that can rot, needs a decent resolution to survive being scaled to
	a 34-stud circle, and gets washed out by the stage fog; forty-eight thin neon parts
	cost less than that and look the same at every radius.

	CLIENT-SIDE, so it is yours alone. Contrast the auras, which are deliberately
	public — see Config/Tuning, "the reveal".
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local SpotCracks = require(script.Parent.Parent.SpotCracks)

local Field = {}

-- The instrument cyan, kept in step with build/SignalAura's GLOW. A mid blue-cyan,
-- not a pale one: the range ring is matte SmoothPlastic since the de-neon pass, so a
-- pale cyan just reads as washed grey against the ground — this holds its colour
-- flat-lit.
--
-- It is the RANGE RING's colour, and only that now. It used to double as the well's
-- neutral state — what a well showed before this client had resolved a rarity for it
-- — but a well with no rarity is now hidden outright (stepAuras) instead of shown in
-- a stand-in colour, so nothing about the wells reads GLOW any more. Rarity itself is
-- not clarity-gated (DigService.hintFor): every detector, in every stage, colours the
-- wells it can register. The old in-range green (a flat colour swap when you stood on
-- a well) is gone too: an in-range well keeps its rarity hue and spikes in brightness
-- instead, so proximity and rarity stop fighting over the same channel.
local GLOW = Color3.fromHex("2E9FD8")

-- "How loud is this well", 0..1, from the resolved rarity. Common sits at 0 and
-- Anomaly at 1, so a Common well reads as calm while a jackpot roars — the rarity
-- colour tells you which wells are worth the walk. Only ever called with a rarity
-- that resolved: a well without one is hidden before stepAuras gets this far.
local function loudness(rarity: string): number
	return math.clamp((Rarity.get(rarity).order - 2) / 6, 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local RING_FOLDER = "DetectorRange"
-- Client-only, like the ring: every burst of cracks this client has built. Kept out
-- of the server's aura folder so nothing the server owns ever has client children.
local CRACK_FOLDER = "SpotCracks"
local SEGMENTS = Tuning.RANGE_RING_SEGMENTS
local SEGMENT_GAP = 0.72 -- fraction of the arc a segment fills; the rest reads as dashes
-- Lifted off the plate so it does not z-fight the ground — except it did: this used
-- to be 0.06, which exactly matches build/Scenery.luau's GROUND_SKIM (the height of
-- Stage 1's opaque stage-colour ground layer, paintBands). Two independently-set
-- constants in different files landing on the same number is invisible everywhere
-- but Stage 1, the one place that layer exists — there, the opaque band sat exactly
-- on top of the ring every frame and hid it completely, not a flicker, since the
-- z-fight was an exact tie rather than a near-miss. 0.1 clears both that (0.06) and
-- OozePool's OozeRim (SKIM - 0.12 = 0.14) by a real margin either side.
local RING_HEIGHT = 0.1

local DetectorController = nil

type Ring = { parts: { BasePart } }

local steady: Ring? = nil
local pulse: Ring? = nil
local ringFolder: Folder? = nil
local crackFolder: Folder? = nil

-- Tracked rather than re-queried: CollectionService:GetTagged allocates a fresh table
-- on every call, and this runs every frame.
--
-- `light` / `motes` are the two children of Core that carry the "this is a light
-- source" work (build/SignalAura); optional because they can lag the rest of the
-- model across a bad connection. `rarity` is this client's resolved reading for the
-- aura: nil until the first position match to a contact lands, then sticky for the
-- aura's life (stepAuras) since the per-player roll never changes once pinned. It
-- gates building the cracks (`burst`) and the ParticleEmitter ColorSequence rebuild to
-- when the reading changes.
type Tracked = {
	core: BasePart,
	light: PointLight?,
	motes: ParticleEmitter?,
	phase: number,
	rarity: string?,
	scale: number,
	surface: Vector3,
	burst: SpotCracks.Burst?,
}
local tracked: { [Model]: Tracked } = {}

-- Auras whose tag arrived before their children did. Usually empty — the server
-- builds each one unparented and parents it complete, so the subtree replicates in
-- one go — but "usually" is not "always" across a bad connection, and an aura that
-- lost its race would otherwise sit in the field permanently un-animated.
local pending: { [Model]: boolean } = {}

-- ── The range ring ──────────────────────────────────────────────────

local function makeRing(name: string): Ring
	local parts: { BasePart } = {}

	for index = 1, SEGMENTS do
		local part = Instance.new("Part")
		part.Name = `{name}{index}`
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Locked = true
		part.Material = Enum.Material.SmoothPlastic
		part.Color = GLOW
		part.Size = Vector3.new(1, 0.08, 0.22)
		part.Parent = ringFolder
		parts[index] = part
	end

	return { parts = parts }
end

--- Lay a ring of segments flat on the ground, centred on `centre`.
---
--- The rotation is the fiddly half. A part's long axis is its local X, and the
--- tangent at angle t is (-sin t, 0, cos t); the yaw that maps one onto the other is
--- -(t + pi/2). Getting it wrong yields segments pointing at the player like spokes,
--- which looks like a deliberate and much worse design rather than a bug.
local function layRing(ring: Ring, centre: Vector3, radius: number, transparency: number, colour: Color3)
	local arc = 2 * math.pi * radius / SEGMENTS

	for index, part in ring.parts do
		local t = (index - 1) / SEGMENTS * 2 * math.pi
		part.Size = Vector3.new(math.max(arc * SEGMENT_GAP, 0.05), 0.08, 0.22)
		part.CFrame = CFrame.new(centre + Vector3.new(math.cos(t) * radius, 0, math.sin(t) * radius))
			* CFrame.Angles(0, -(t + math.pi / 2), 0)
		part.Transparency = transparency
		part.Color = colour
	end
end

local function hideRing(ring: Ring)
	for _, part in ring.parts do
		part.Transparency = 1
	end
end

--- Where the ring should sit. One ray, straight down from the player.
---
--- The stage plates are flat, so a single sample is honest here — sampling per segment
--- would let the ring drape over scenery, which is prettier and also means the ring
--- can be occluded by the very clutter it is supposed to be measured against.
local function groundY(root: BasePart): number
	-- Everything the detector itself put in the world has to be excluded, or the ring
	-- lands on top of an aura the moment the player stands next to one.
	local ignore: { Instance } = { root.Parent :: Instance }
	if ringFolder then
		table.insert(ignore, ringFolder)
	end
	if crackFolder then
		table.insert(ignore, crackFolder)
	end
	local auraFolder = Workspace:FindFirstChild(Tuning.AURA_FOLDER)
	if auraFolder then
		table.insert(ignore, auraFolder)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	if hit then
		return hit.Position.Y + RING_HEIGHT
	end

	-- A HumanoidRootPart floats about three studs over whatever it is standing on.
	-- Not exact, but the ring only has to be on the floor, not welded to it.
	return root.Position.Y - 3 + RING_HEIGHT
end

local function stepRings()
	if steady == nil or pulse == nil then
		return
	end

	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local radius = if DetectorController then DetectorController.radius() else 0

	if root == nil or not root:IsA("BasePart") or radius <= 0 then
		hideRing(steady)
		hideRing(pulse)
		return
	end

	local centre = Vector3.new(root.Position.X, groundY(root), root.Position.Z)

	layRing(steady, centre, radius, 0.72, GLOW)

	-- Off os.clock and Tuning.RANGE_RING_PERIOD so every pulse in the game beats
	-- together — the pick-up card's stroke shimmer rides the same period.
	local phase = (os.clock() % Tuning.RANGE_RING_PERIOD) / Tuning.RANGE_RING_PERIOD
	layRing(pulse, centre, radius * phase, 0.15 + phase * 0.8, GLOW)
end

-- ── The auras ───────────────────────────────────────────────────────

--- Tear down this client's cracks for an aura and forget it. Every exit path goes
--- through here — the tag removed, or the core found orphaned mid-frame — because the
--- cracks are client parts the server's Destroy never reaches.
local function forget(model: Model)
	local entry = tracked[model]
	if entry and entry.burst then
		entry.burst.model:Destroy()
	end
	tracked[model] = nil
	pending[model] = nil
end

local function track(instance: Instance)
	if not instance:IsA("Model") then
		return
	end

	local core = instance:FindFirstChild("Core")
	if core == nil or not core:IsA("BasePart") then
		pending[instance] = true -- children have not replicated yet; retried each frame
		return
	end

	pending[instance] = nil
	local surface = instance:GetAttribute("Surface")
	tracked[instance] = {
		core = core,
		-- Not gated in the check above: these are cosmetic sweeteners, and an aura that
		-- surfaces for a frame without its light is far better than one that never
		-- animates because its light lost the replication race.
		light = core:FindFirstChildWhichIsA("PointLight"),
		motes = core:FindFirstChildWhichIsA("ParticleEmitter"),
		-- Derived from the position so it is stable across frames and DIFFERENT per
		-- aura. Pulsing a field of them in lockstep looks like a screen refresh
		-- artefact rather than like several separate things breathing.
		phase = (core.Position.X * 0.7 + core.Position.Z * 1.3) % (2 * math.pi),
		rarity = nil,
		-- How much bigger this aura is than a default one — a heavier buried thing gets
		-- longer, wider cracks (DigService off Config/Weight.auraScale, stamped by
		-- build/SignalAura). The rarity is per-player (above); this is shared, off the
		-- signal's default item.
		scale = (instance :: any):GetAttribute("WellScale") or 1,
		-- The ground point the cracks lie on, stamped by build/SignalAura. The core's
		-- own position is a fallback that only puts them a hair high.
		surface = if typeof(surface) == "Vector3" then surface else core.Position,
		burst = nil,
	}
end

--- Animate every tracked aura for THIS frame and THIS client: the crack pulse, the
--- standing-on-it flare — and the rarity, which is per-player. The aura is shared
--- server geometry, so the tint and the cracks have to come from here, off
--- DetectorController's per-player contacts read; an aura this client has no reading
--- for is hidden outright until (if ever) a rarity lands.
local function stepAuras()
	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local here = if root and root:IsA("BasePart") then root.Position else nil

	local now = os.clock()

	for model, entry in tracked do
		if entry.core.Parent == nil then
			forget(model)
			continue
		end

		local close = false
		if here then
			local dx = entry.core.Position.X - here.X
			local dz = entry.core.Position.Z - here.Z
			close = dx * dx + dz * dz <= Tuning.DIG_RADIUS * Tuning.DIG_RADIUS
		end

		-- This client's rarity for the signal under this aura -- its OWN per-player roll
		-- (DigService.rollFor), off the per-player contacts payload, never off this
		-- shared part.
		--
		-- STICKY. A signal's per-player roll is pinned server-side the first time it
		-- lands in this client's radar, so an aura's rarity never changes over its life
		-- -- which means a nil read is always "not matched yet" or "never will be",
		-- never "it changed". So once we have a reading, keep it: a transient miss on
		-- the position match (the player walked between ticks, a SweepState was dropped)
		-- must not blink the cracks back out.
		local read = if DetectorController then DetectorController.contactRarityAt(entry.core.Position) else nil
		if read ~= nil and read ~= entry.rarity and crackFolder then
			entry.rarity = read
			local hue = Rarity.get(read).color
			-- The crack count and forks ARE the rarity, so a new reading is a new burst.
			-- Built once per reading, not per frame -- this is also the only place the
			-- ColorSequence churns a fresh object.
			if entry.burst then
				entry.burst.model:Destroy()
			end
			entry.burst = SpotCracks.build(crackFolder, entry.surface, entry.scale, read, hue)
			if entry.motes then
				entry.motes.Color = ColorSequence.new(hue)
			end
		end
		local rarity = entry.rarity

		-- No reading yet (the position match still settling) or ever (a signal someone
		-- else revealed that sits past this player's depth gate): nothing to say about
		-- the aura, so draw nothing -- no cracks are built, and the shared core stays
		-- dark until a rarity lands. The server still owns that the part exists; this
		-- only ever drives how it looks.
		if rarity == nil then
			entry.core.Transparency = 1
			if entry.light then
				entry.light.Brightness = 0
			end
			if entry.motes then
				entry.motes.Rate = 0
			end
			continue
		end

		local hue = Rarity.get(rarity).color
		local t = loudness(rarity)

		-- Standing on it is the moment the player has been walking towards: every crack
		-- burns near-full and the fan of rays lights up (SpotCracks.step). Stepped FIRST
		-- so the fade-in (`shown`) and the eased standing-on-it blend (`onIt`) it keeps
		-- are this frame's, and the core and light below ride the same curves instead of
		-- snapping on while the cracks fade in.
		local shown, onIt = 1, if close then 1 else 0
		local burst = entry.burst
		if burst then
			SpotCracks.step(burst, now, t, entry.phase, close)
			shown, onIt = SpotCracks.shown(burst, now), burst.onIt
		end

		-- The hot spot where the cracks meet: the rarity hue lifted toward white so it
		-- reads as the brightest point, and fully white-hot when you are standing on it.
		entry.core.Color = hue:Lerp(Color3.new(1, 1, 1), lerp(0.45, 0.7, onIt))
		local idle = 0.1 + 0.1 * (0.5 + 0.5 * math.sin(now * 3 + entry.phase))
		entry.core.Transparency = 1 - (1 - lerp(idle, 0, onIt)) * shown

		-- Nothing is Neon, so this light is what makes the spot read as a light source
		-- rather than paint, and it is where "louder" shows most: a Legendary spot
		-- throws four times the Common one's brightness and reaches half again as far,
		-- so you can pick it out across the field.
		if entry.light then
			local brightness = lerp(0.7, 2.4, t)
			entry.light.Brightness = brightness * lerp(1, 1.6, onIt) * shown
			entry.light.Range = lerp(10, 18, t)
		end
		if entry.motes then
			entry.motes.Rate = (lerp(5, 19, t) + 12 * onIt) * shown
		end
	end
end

-- ── Lifecycle ───────────────────────────────────────────────────────

function Field.start()
	-- Sibling controller, required lazily so load order between the two never matters.
	DetectorController = require(script.Parent.DetectorController)

	local folder = Instance.new("Folder")
	folder.Name = RING_FOLDER
	folder.Parent = Workspace
	ringFolder = folder

	local steadyRing = makeRing("Steady")
	local pulseRing = makeRing("Pulse")
	hideRing(steadyRing)
	hideRing(pulseRing)
	steady = steadyRing
	pulse = pulseRing

	local cracks = Instance.new("Folder")
	cracks.Name = CRACK_FOLDER
	cracks.Parent = Workspace
	crackFolder = cracks

	for _, instance in CollectionService:GetTagged(Tuning.AURA_TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Tuning.AURA_TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tuning.AURA_TAG):Connect(function(instance)
		if instance:IsA("Model") then
			forget(instance)
		end
	end)

	-- RenderStepped, unlike its siblings: this is purely cosmetic geometry and there
	-- is no reason to move it on a frame the client is not drawing. The audio cues
	-- that must not stall live on Heartbeat over in DetectorController.
	RunService.RenderStepped:Connect(function()
		-- Retry only the ones that actually lost the race. Re-querying GetTagged here
		-- would allocate a table per frame to answer a question that is almost always
		-- "nothing changed".
		for model in pending do
			track(model)
		end

		stepRings()
		stepAuras()
	end)
end

return Field
