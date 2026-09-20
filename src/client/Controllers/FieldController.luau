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
	important number a player owns and, without this, an invisible one.

	IT IS A SONAR SWEEP: an arm turns around you once every six seconds dragging a
	wedge of lit ground behind it, and the rim is a dashed hairline whose dashes light
	as the arm passes and cool off behind it. The radius is still the whole point — it
	is where the wedge stops and where the dashes sit — but the sweep is what makes the
	thing read as an instrument taking a reading rather than a circle painted on the
	floor. It replaced a second dashed ring that expanded out to the radius once a
	second (Config/Tuning, RANGE_SWEEP_*, has why that went).

	It is built from parts rather than a textured decal on purpose. A ring texture is
	an asset id that can rot, needs a decent resolution to survive being scaled to a
	34-stud circle, and gets washed out by the stage fog; a few dozen thin matte parts
	cost less than that and look the same at every radius. The wedge is the same bet
	twice over — a fan of flat triangles rather than an image of a radar sweep.

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

-- How the rim reads between sweeps and under the arm. The dim end is a hairline on
-- purpose now that the wedge carries the "this is live" job: a rim at the old 0.72
-- fought the wedge for the same attention, and the point of the comet is that the
-- boundary is brightest exactly where the sweep is looking.
local RIM_DIM = 0.84
local RIM_HOT = 0.18

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

-- Everything the sweep lays down sits at that same RING_HEIGHT, so the three
-- thicknesses below are what keep them off each other. The rim crosses the wedge's
-- outer edge and the arm's tip on every single frame, and two parts whose faces land
-- on the same plane z-fight — not sometimes, always. All three are centred on
-- RING_HEIGHT and no two share a face: rim 0.06..0.14, arm 0.07..0.13, wedge
-- 0.075..0.125. Change one and check it against the other two, and against the 0.06
-- floor in the comment above.
--
-- 0.05 IS THE FLOOR, NOT A CHOICE. Roblox clamps every part axis to 0.05 studs, so
-- the wedge asked for 0.04 and measured 0.05 on a raycast — which quietly moved its
-- faces off where these numbers said they were. Anything thinner than this is the
-- same number with a misleading comment on it.
local RIM_THICK = 0.08
local ARM_THICK = 0.06
local WEDGE_THICK = 0.05

local DetectorController = nil

type Ring = { parts: { BasePart } }

--- The turning half: one Model holding the wedge triangles and the arm, built once
--- per radius and then rigidly re-pivoted every frame. `shown` is each part's baked
--- transparency (the fade is a property of WHERE a part sits in the wedge, not of
--- time), kept so hiding and showing does not have to recompute the ladder.
type Sweep = {
	model: Model,
	radius: number,
	parts: { { part: BasePart, shown: number } },
	hidden: boolean,
}

local steady: Ring? = nil
local sweep: Sweep? = nil
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

-- ── The rim ─────────────────────────────────────────────────────────

--- Every flat cosmetic part this file makes is the same part with a different size,
--- so they are all born here: anchored, un-queryable, matte, and in the instrument
--- cyan. CanQuery false is the second lock on a door groundY already bolts by
--- excluding this folder by name — the field is full of parts a player stands on and
--- other systems cast rays across, and a cosmetic that can stop a ray is a bug
--- waiting for whichever one forgets to filter it.
local function makePart(class: string, name: string, parent: Instance?): BasePart
	local part = Instance.new(class) :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = GLOW
	part.Parent = parent
	return part
end

local function makeRing(name: string): Ring
	local parts: { BasePart } = {}

	for index = 1, SEGMENTS do
		local part = makePart("Part", `{name}{index}`, ringFolder)
		part.Size = Vector3.new(1, RIM_THICK, 0.22)
		parts[index] = part
	end

	return { parts = parts }
end

--- Lay the rim flat on the ground, centred on `centre`, and run the comet round it:
--- a dash is brightest as the arm crosses it and cools over the next
--- RANGE_SWEEP_COMET radians. That decay is what makes the rim read as the sweep's
--- echo rather than as a circle that happens to share its colour.
---
--- The rotation is the fiddly half. A part's long axis is its local X, and the
--- tangent at angle t is (-sin t, 0, cos t); the yaw that maps one onto the other is
--- -(t + pi/2). Getting it wrong yields segments pointing at the player like spokes,
--- which looks like a deliberate and much worse design rather than a bug.
local function layRing(ring: Ring, centre: Vector3, radius: number, lead: number)
	local arc = 2 * math.pi * radius / SEGMENTS
	local comet = Tuning.RANGE_SWEEP_COMET

	for index, part in ring.parts do
		local t = (index - 1) / SEGMENTS * 2 * math.pi
		part.Size = Vector3.new(math.max(arc * SEGMENT_GAP, 0.05), RIM_THICK, 0.22)
		part.CFrame = CFrame.new(centre + Vector3.new(math.cos(t) * radius, 0, math.sin(t) * radius))
			* CFrame.Angles(0, -(t + math.pi / 2), 0)

		-- How far the arm has travelled since it was over this dash. The modulo is
		-- what makes the dash behind the arm read as 0.05 rad old rather than 6.23.
		local behind = (lead - t) % (2 * math.pi)
		local heat = if behind < comet then (1 - behind / comet) ^ 2 else 0
		part.Transparency = lerp(RIM_DIM, RIM_HOT, heat)
	end
end

-- ── The sweep ───────────────────────────────────────────────────────

--- Lay one flat triangle a-b-c with a pair of WedgeParts.
---
--- A WedgePart is the only primitive Roblox has with a triangular silhouette, and it
--- takes two of them to make an arbitrary triangle: the altitude from the longest
--- side splits it into two right triangles, which is exactly the shape a wedge is.
--- The swaps at the top put the longest side on b-c so that altitude actually falls
--- inside the triangle; without them an obtuse slice comes out inside-out. This is
--- the long-standing community routine for the job, kept in its usual form (with a
--- real thickness rather than the usual zero) so it stays recognisable.
---
--- `right` comes out vertical for a triangle lying flat, which is why the wedges'
--- thickness is their X and the triangle itself lives in their Y-Z plane.
local function layTriangle(w1: BasePart, w2: BasePart, a: Vector3, b: Vector3, c: Vector3)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)

	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end

	ab, ac, bc = b - a, c - a, c - b

	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	w1.Size = Vector3.new(WEDGE_THICK, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w2.Size = Vector3.new(WEDGE_THICK, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
end

--- Build the turning half at this radius, in LOCAL space: the arm points down +X and
--- the wedge trails behind it into negative angles, so the whole model is placed and
--- aimed with one pivot per frame (stepRings) and nothing in here is recomputed while
--- the player walks. Rebuilt only when the radius changes, which means on a tier
--- change and at nothing else.
---
--- The wedge is a fan of triangles rather than a stack of rectangles because
--- rectangles cannot do it: a slice is a shape that WIDENS with radius, so
--- constant-width parts either leave gaps at the rim or pile up near the player, and
--- piled-up translucent parts do not stay at their own transparency — they composite
--- into a bright blob under your feet.
local function buildSweep(radius: number): Sweep
	local model = Instance.new("Model")
	model.Name = "Sweep"

	-- The pivot. A Model with no PrimaryPart pivots about its bounding-box centre,
	-- which for a fan is somewhere out in the wedge, so the sweep would orbit the
	-- player instead of turning under them.
	local hub = makePart("Part", "Hub", model)
	hub.Size = Vector3.new(0.05, 0.05, 0.05)
	hub.Transparency = 1
	hub.CFrame = CFrame.new()
	model.PrimaryPart = hub

	local parts: { { part: BasePart, shown: number } } = {}
	local slices = Tuning.RANGE_SWEEP_SLICES
	local span = Tuning.RANGE_SWEEP_SPAN

	for index = 1, slices do
		-- Slice 1 is the one against the arm and the brightest; the falloff is the
		-- square of the distance behind it, so the wedge has a hot leading edge and a
		-- long thin tail rather than a uniform smear.
		local outer = -span * (index - 1) / slices
		local inner = -span * index / slices
		local shown = 1 - Tuning.RANGE_SWEEP_ALPHA * (1 - (index - 1) / slices) ^ 2

		local w1 = makePart("WedgePart", `Slice{index}a`, model)
		local w2 = makePart("WedgePart", `Slice{index}b`, model)
		layTriangle(
			w1,
			w2,
			Vector3.zero,
			Vector3.new(math.cos(inner) * radius, 0, math.sin(inner) * radius),
			Vector3.new(math.cos(outer) * radius, 0, math.sin(outer) * radius)
		)
		w1.Transparency = shown
		w2.Transparency = shown
		table.insert(parts, { part = w1, shown = shown })
		table.insert(parts, { part = w2, shown = shown })
	end

	-- The arm, in four pieces so it can brighten along its length. One part with a
	-- flat transparency reads as a spoke; the gradient is what makes it look like the
	-- reading is being taken out at the edge.
	local ARM = 4
	for index = 1, ARM do
		local shown = 1 - lerp(0.08, 0.85, (index - 0.5) / ARM)
		local part = makePart("Part", `Arm{index}`, model)
		part.Size = Vector3.new(radius / ARM, ARM_THICK, 0.26)
		part.CFrame = CFrame.new((index - 0.5) / ARM * radius, 0, 0)
		part.Transparency = shown
		table.insert(parts, { part = part, shown = shown })
	end

	model.Parent = ringFolder
	return { model = model, radius = radius, parts = parts, hidden = false }
end

local function showSweep(entry: Sweep, hidden: boolean)
	if entry.hidden == hidden then
		return
	end
	entry.hidden = hidden
	for _, item in entry.parts do
		item.part.Transparency = if hidden then 1 else item.shown
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
	if steady == nil then
		return
	end

	local player = Players.LocalPlayer
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local radius = if DetectorController then DetectorController.radius() else 0

	if root == nil or not root:IsA("BasePart") or radius <= 0 then
		hideRing(steady)
		if sweep then
			showSweep(sweep, true)
		end
		return
	end

	local centre = Vector3.new(root.Position.X, groundY(root), root.Position.Z)

	-- Where the arm is pointing this frame, as a bearing in the same convention the
	-- rim uses: local +X at 0, turning toward +Z. Off os.clock rather than a
	-- delta-time accumulator so two players standing together sweep in step, and so
	-- the arm does not lurch after a frame the client spent loading.
	local lead = (os.clock() % Tuning.RANGE_SWEEP_PERIOD) / Tuning.RANGE_SWEEP_PERIOD * 2 * math.pi

	layRing(steady, centre, radius, lead)

	-- A tier change is the only thing that moves the radius, so this rebuild costs
	-- nothing on a normal frame. Everything else about the sweep is a single pivot:
	-- the fan is rigid, and its fade is baked into the parts.
	if sweep == nil or math.abs(sweep.radius - radius) > 0.01 then
		if sweep then
			sweep.model:Destroy()
		end
		sweep = buildSweep(radius)
	end
	local turning = sweep :: Sweep
	showSweep(turning, false)
	turning.model:PivotTo(CFrame.new(centre) * CFrame.Angles(0, -lead, 0))
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

	-- Only the rim is built up front. The sweep needs a radius to have a shape at all,
	-- and there is no radius until the first payload lands, so stepRings builds it on
	-- the frame the detector turns on.
	local steadyRing = makeRing("Rim")
	hideRing(steadyRing)
	steady = steadyRing

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
