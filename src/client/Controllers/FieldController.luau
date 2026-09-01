--[[
	FieldController.lua — the detector's world-space half.

	DetectorController owns the screen. This owns the ground: the range ring the
	detector throws around you, and the ripple of the aura wells that sit over buried
	signals. Splitting them is not tidiness — the two have completely different
	sources. Everything on the HUD is drawn from a payload only this client receives,
	whereas the auras are SERVER parts that every player in the server can see, and
	this controller may only ever change how they LOOK. Never where they are, never
	whether they exist. If it ever decides that, the reveal has moved to the client
	and the field is a free ESP.

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

local Field = {}

-- The instrument cyan, kept in step with build/SignalAura's GLOW (the ripple discs
-- this controller drives expand out of that core). A mid blue-cyan, not a pale one:
-- the ring and the aura discs are matte SmoothPlastic since the de-neon pass, so a
-- pale cyan just reads as washed grey against the ground — this holds its colour
-- flat-lit.
--
-- It is also the well's NEUTRAL state: the colour a well shows when this client has
-- no rarity for it — which now only happens for a frame while the position match to a
-- contact settles, or for an aura someone else revealed that is past this player's
-- depth gate. Rarity itself is no longer clarity-gated (DigService.hintFor, on
-- request): every detector, in every stage, colours its wells. The old in-range green
-- (a flat colour swap when you stood on a well) is gone too: an in-range well keeps
-- its rarity hue and spikes in brightness instead, so proximity and rarity stop
-- fighting over the same channel.
local GLOW = Color3.fromHex("2E9FD8")

-- "How loud is this well", 0..1, from the resolved rarity. Common sits at 0 and
-- Anomaly at 1, so a Common well reads as calm while a jackpot roars — the rarity
-- colour tells you which wells are worth the walk. A well whose rarity has not
-- resolved yet is not t = 0: it stays fully neutral (all three ripples, GLOW) so it
-- never looks feebler than the plain blue it replaced.
local function loudness(rarity: string): number
	return math.clamp((Rarity.get(rarity).order - 2) / 6, 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local RING_FOLDER = "DetectorRange"
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

-- Tracked rather than re-queried: CollectionService:GetTagged allocates a fresh table
-- on every call, and this runs every frame.
--
-- `light` / `motes` are the two children of Core that carry the "this is a light
-- source" work (build/SignalAura); optional because they can lag the rest of the
-- model across a bad connection. `rarity` is what this client last resolved for the
-- well — cached so the ParticleEmitter's ColorSequence and Rate are only rewritten
-- when it actually changes, not sixty times a second.
type Tracked = {
	core: BasePart,
	dome: BasePart,
	ripples: { BasePart },
	light: PointLight?,
	motes: ParticleEmitter?,
	phase: number,
	rarity: string?,
	scale: number,
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
	-- lands on top of an aura dome the moment the player stands next to one.
	local ignore: { Instance } = { root.Parent :: Instance }
	if ringFolder then
		table.insert(ignore, ringFolder)
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

	-- Shares os.clock with the sweep arm on the HUD scope, so the arm crossing the top
	-- of the dial and the ring leaving your feet are the same event.
	local phase = (os.clock() % Tuning.RANGE_RING_PERIOD) / Tuning.RANGE_RING_PERIOD
	layRing(pulse, centre, radius * phase, 0.15 + phase * 0.8, GLOW)
end

-- ── The auras ───────────────────────────────────────────────────────

local function track(instance: Instance)
	if not instance:IsA("Model") then
		return
	end

	local core = instance:FindFirstChild("Core")
	local dome = instance:FindFirstChild("Dome")
	local ripples: { BasePart } = {}
	for _, child in instance:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 6) == "Ripple" then
			table.insert(ripples, child)
		end
	end

	if core == nil or not core:IsA("BasePart") or dome == nil or not dome:IsA("BasePart") or #ripples == 0 then
		pending[instance] = true -- children have not replicated yet; retried each frame
		return
	end

	pending[instance] = nil
	tracked[instance] = {
		core = core,
		dome = dome,
		ripples = ripples,
		-- Not gated in the check above: these are cosmetic sweeteners, and a well that
		-- surfaces for a frame without its light is far better than one that never
		-- animates because its light lost the replication race.
		light = core:FindFirstChildWhichIsA("PointLight"),
		motes = core:FindFirstChildWhichIsA("ParticleEmitter"),
		-- Derived from the position so it is stable across frames and DIFFERENT per
		-- aura. Pulsing a field of them in lockstep looks like a screen refresh
		-- artefact rather than like several separate things breathing.
		phase = (core.Position.X * 0.7 + core.Position.Z * 1.3) % (2 * math.pi),
		rarity = nil,
		-- How much wider this well is than a default one — a heavier buried thing gets
		-- a bigger glow (DigService off Config/Weight.auraScale, stamped by
		-- build/SignalAura). 1 for an unscaled well and for an old aura saved into the
		-- place without the attribute. The rarity TINT is per-player (above); this is
		-- shared, off the signal's default item.
		scale = (instance :: any):GetAttribute("WellScale") or 1,
	}
end

--- Animate every tracked well for THIS frame and THIS client: the idle breathe, the
--- outward ripples, the in-range freeze — and the rarity tint, which is per-player.
--- The well part is shared server geometry, so the tint has to be applied here off
--- DetectorController's per-player contacts read; a player whose detector cannot
--- resolve a signal only ever sees the cyan build/SignalAura ships.
local function stepAuras()
	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local here = if root and root:IsA("BasePart") then root.Position else nil

	local now = os.clock()
	local breatheClock = now * 2 * math.pi * Tuning.AURA_PULSE_HZ
	local reach = Tuning.AURA_PULSE_REACH

	for model, entry in tracked do
		if entry.core.Parent == nil then
			tracked[model] = nil
			continue
		end

		local close = false
		if here then
			local dx = entry.core.Position.X - here.X
			local dz = entry.core.Position.Z - here.Z
			close = dx * dx + dz * dz <= Tuning.DIG_RADIUS * Tuning.DIG_RADIUS
		end

		-- This client's rarity for the signal under this well -- its OWN per-player roll
		-- (DigService.rollFor), off the per-player contacts payload, never off this
		-- shared part. Every detector gets it now; nil only while the position match to
		-- a contact is still settling, or for an aura past this player's depth gate.
		local rarity = if DetectorController then DetectorController.contactRarityAt(entry.core.Position) else nil
		if rarity ~= entry.rarity then
			entry.rarity = rarity
			-- ColorSequence churns a fresh object; only rebuild it when the read
			-- actually changed, not every frame.
			if entry.motes then
				entry.motes.Color = ColorSequence.new(if rarity then Rarity.get(rarity).color else GLOW)
			end
		end

		local known = rarity ~= nil
		local hue = if known then Rarity.get(rarity :: string).color else GLOW
		local t = if known then loudness(rarity :: string) else 0

		-- The well wears its rarity hue at every distance now. Being in range spikes its
		-- INTENSITY (brightness, solidity, frozen rings) rather than swapping the colour
		-- for green -- proximity and rarity were fighting over one channel before.
		local coreHue = if close then hue:Lerp(Color3.new(1, 1, 1), 0.25) else hue
		entry.core.Color = coreHue
		entry.dome.Color = coreHue

		-- The de-neon pass left this light as the only thing making the well read as a
		-- light source rather than a painted coin, so it is where "louder" shows most:
		-- a Legendary well throws four times the Common one's brightness and reaches
		-- half again as far, so you can pick it out across the field.
		if entry.light then
			local brightness = if known then lerp(0.7, 2.4, t) else 0.55
			entry.light.Brightness = if close then brightness * 1.6 else brightness
			entry.light.Range = if known then lerp(10, 18, t) else 10
		end
		if entry.motes then
			entry.motes.Rate = if known then lerp(4, 16, t) else 4
		end

		if close then
			-- Standing on it is the moment the player has been walking towards. Core
			-- solid, dome firm, the rings frozen together at the dome's own edge as one
			-- steady outline -- the motion stopping is the "you are on it" tell now that
			-- the colour no longer changes. Same SIZE as idle: it does NOT balloon out
			-- to the pickup radius (removed on request).
			entry.core.Transparency = 0.05
			entry.dome.Transparency = lerp(0.2, 0.1, t)
			-- Freeze the rings on THIS well's dome edge, not the default one — a heavy
			-- well's dome is wider (entry.scale, off Config/Weight.auraScale).
			local frozen = Tuning.AURA_DOME * entry.scale
			for _, ripple in entry.ripples do
				ripple.Size = Vector3.new(ripple.Size.X, frozen, frozen)
				ripple.Color = coreHue
				ripple.Transparency = 0.3
			end
		else
			local breathe = 0.5 + 0.5 * math.sin(breatheClock + entry.phase)
			entry.core.Transparency = 0.22 + breathe * 0.14
			entry.dome.Transparency = lerp(0.42, 0.3, t) + breathe * 0.12

			-- A known-cheap well runs one slow ripple; a known-jackpot runs all three
			-- fast. An UNRESOLVED well keeps all three at base speed -- it must never
			-- look feebler than the plain blue well it used to be.
			local count = #entry.ripples
			local visible = if known then math.clamp(1 + math.round(t * 2), 1, count) else count
			local speed = if known then lerp(1.0, 1.9, t) else 1.0
			local rippleProgress = now * Tuning.AURA_PULSE_HZ * speed
			for i, ripple in entry.ripples do
				if i > visible then
					ripple.Transparency = 1
					continue
				end
				-- Each ring runs its own outward sweep, offset so they chase each
				-- other out of the well. p: 0 at the core, 1 fully expanded. It fades
				-- IN off the core and OUT again as it reaches the rim (sin curve), so
				-- what you see is a ring travelling, not a disc filling.
				local p = (rippleProgress + entry.phase / (2 * math.pi) + (i - 1) / visible) % 1
				local d = 1.0 + (2 * reach - 1.0) * p
				ripple.Size = Vector3.new(ripple.Size.X, d, d)
				ripple.Color = hue
				ripple.Transparency = 1 - math.sin(p * math.pi) * (0.5 + 0.2 * t)
			end
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

	for _, instance in CollectionService:GetTagged(Tuning.AURA_TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Tuning.AURA_TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Tuning.AURA_TAG):Connect(function(instance)
		if instance:IsA("Model") then
			tracked[instance] = nil
			pending[instance] = nil
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
