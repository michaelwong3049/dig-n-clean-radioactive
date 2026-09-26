--!strict
--[[
	AuraController.lua — draws the Aura every character is wearing: atom rings round
	the chest, electrons riding them, and a core light in the top tiers.

	WHAT IT READS. AuraService stamps each character with its equipped tier
	(AuraLook.ATTRIBUTE); this draws it. Anything tagged AuraLook.DISPLAY_TAG gets one
	too — the Outfitter's mannequin, which walks the whole ladder (`AuraCycle`). The
	look itself — colours, ring counts, sizes — is Shared/AuraLook's.

	CLIENT-SIDE BY DESIGN. The rings precess and the electrons orbit every frame; doing
	that on the server would replicate a CFrame per part per frame to every player for
	a picture. Here every client draws every aura locally: nothing crosses the wire but
	the tier, and each client can skip the ones it cannot see.

	HOW A RING IS DRAWN. Two Beams per ring, each a half circle: both run between the
	same two Attachments on opposite sides of the ring, and their CurveSizes bend one
	to either side (4/3 r is the cubic Bezier that traces a half circle to within 2%).
	FaceCamera makes each a glowing line from any angle. The Attachments sit on one
	invisible anchored hub per aura, moved to the chest every frame, so the rings
	follow the body; the precession is the Attachments turning on the hub. Electrons
	are small Neon balls with a Trail, moved in the same pass (one BulkMoveTo).

	THE TOP RUNG IS A HELIX, NOT AN ATOM (AuraLook's `form`). Its two strands are chains
	of Beams through Attachments laid along the spiral with their Axes on its tangent,
	its halo and foot ring are half-circle pairs like the atom's, and all of it is fixed
	in the hub: the hub turning is the helix turning. The electrons climb the strands.

	THE SPARKLE STORM (tiers 3-6, AuraLook's `sparkle`) is ParticleEmitters with the
	engine's sparkle texture: star dust off an invisible shell round the aura, sparkles
	shed by each electron, embers off a pad at the feet, and a glitter burst out of the
	core that `step` fires on a clock and flares the core light with. They switch with
	the rest of the aura (setShown), so a hidden or far one emits nothing.

	NOTHING IS PUT IN THE CHARACTER. The rig lives in its own `AuraFx` folder, anchored
	and CanQuery false, so no raycast (the detector's, the wash bay's aim) can land on
	it and nothing that walks a character's parts ever meets it.

	THE SHOP CARDS MOVE TOO, on request. A shop card's atom (AuraLook.icon, tagged
	AuraLook.ICON_TAG) is parts in a ViewportFrame, which redraws whenever anything in
	it moves. So this moves as little as possible: the card's camera circles the atom
	at the aura's own precession (which reads exactly as the rings turning) and the
	electrons ride their rings. The hundred-odd ring segments never move. Only a card
	actually on screen is touched; the carousel's off-panel slots stand still.

	YOUR OWN AURA HIDES WHEN THE CAMERA IS INSIDE IT. The wash bay is first person
	from your own head, and first-person zoom is the same: a ring round your chest is
	then a streak across the whole view. Past FAR from the camera an aura is too small
	to read and is skipped entirely, and a downed character's aura goes out.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AuraLook = require(ReplicatedStorage.Shared.AuraLook)

local AuraController = {}

--- Studs from the camera past which an aura is not drawn.
local FAR = 250
--- Seconds between re-checking who wears what (and which displays exist).
local RESCAN = 0.5
--- The half-circle Bezier's control distance, as a fraction of the radius.
local HALF_CIRCLE = 4 / 3
--- Turns an Attachment so its Axis (its X) points along the ring's Z, the direction
--- the half circles bulge toward.
local AXIS_TO_Z = CFrame.Angles(0, -math.pi / 2, 0)
--- The top-tier core light: range at tier 4, extra range per tier above it, and how
--- bright it breathes.
local CORE_RANGE = 8
local CORE_RANGE_STEP = 2
local CORE_BRIGHTNESS = 1.3
--- How additive the rings and trails are. Full LightEmission (and Brightness 2) washed
--- every tier out to near-white in daylight, and white is aura failure's colour; at
--- this much the gold still reads as gold on a sunny plaza.
local GLOW = 0.4

--- The sparkle storm's texture: the engine's own sparkle, as the aurora and crates use.
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
--- Sparkles glow a little more than the rings (they are small, and a twinkle has to
--- pop), but not fully: at 1 the gold ones read white in daylight, like the rings did.
local SPARKLE_GLOW = 0.7
--- Beams per helix strand. Each is a cubic Bezier through the strand's tangents, so a
--- quarter turn or less apiece keeps the spiral round.
local STRAND_BEAMS = 6
--- How hard the core light flares on a glitter burst, on top of its breathing.
local BURST_FLARE = 2.5

type Electron = { part: Part, trail: Trail, ring: number, index: number, progress: number }

type Rig = {
	anchor: BasePart,
	humanoid: Humanoid?,
	isLocal: boolean,
	tier: number,
	look: AuraLook.Look,
	scale: number,
	lift: number,
	seed: number,
	model: Model,
	hub: Part,
	ends: { { Attachment } },
	beams: { Beam },
	electrons: { Electron },
	light: PointLight?,
	-- The sparkle storm: every emitter (switched with the aura), the parts they emit
	-- from, and the core's burst.
	emitters: { ParticleEmitter },
	dust: Part?,
	dustOffset: CFrame,
	embers: Part?,
	burst: ParticleEmitter?,
	sinceBurst: number,
	flare: number,
	shown: boolean,
}

local localPlayer = Players.LocalPlayer
local rigs: { [BasePart]: Rig } = {}
local fx: Folder
local rng = Random.new()
local sinceScan = math.huge
-- A failing step would otherwise warn sixty times a second.
local warned = false

local function fxPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Size = Vector3.one * 0.2
	part.Parent = parent
	return part
end

local function destroyRig(rig: Rig)
	rig.model:Destroy()
	rigs[rig.anchor] = nil
end

local function ringBeam(name: string, a: Attachment, b: Attachment, curve0: number, curve1: number, segments: number, look: AuraLook.Look, scale: number, parent: Instance): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = a
	beam.Attachment1 = b
	beam.CurveSize0 = curve0
	beam.CurveSize1 = curve1
	beam.Segments = segments
	beam.FaceCamera = true
	beam.Width0 = look.width * scale
	beam.Width1 = look.width * scale
	beam.Color = ColorSequence.new(look.color)
	beam.Transparency = NumberSequence.new(look.transparency)
	beam.LightEmission = GLOW
	beam.LightInfluence = 0
	beam.Brightness = 1
	beam.Parent = parent
	return beam
end

--- A ring as two half-circle Beams between an A and a B Attachment on `hub`, set at
--- `frame` (the ring's own frame, relative to the hub) when it is given. The atom's rings
--- pass none and are posed every frame; the helix's halo and foot ring never move.
local function halfCircles(hub: Part, name: string, radius: number, frame: CFrame?, look: AuraLook.Look, scale: number, beams: { Beam }): { Attachment }
	local a = Instance.new("Attachment")
	a.Name = `{name}A`
	a.Parent = hub
	local b = Instance.new("Attachment")
	b.Name = `{name}B`
	b.Parent = hub
	if frame then
		a.CFrame = frame * CFrame.new(radius, 0, 0) * AXIS_TO_Z
		b.CFrame = frame * CFrame.new(-radius, 0, 0) * AXIS_TO_Z
	end
	local bend = HALF_CIRCLE * radius
	for _, side in { 1, -1 } do
		table.insert(beams, ringBeam(name, a, b, side * bend, -side * bend, 24, look, scale, hub))
	end
	return { a, b }
end

--- The top rung's strands: each a chain of Beams through Attachments on the hub, every
--- Attachment's Axis along the strand's tangent there, so each Beam's CurveSizes (a
--- third of the tangent over its span, the cubic Bezier that matches a curve's ends
--- and slopes) bend it along the spiral. Fixed in the hub; the hub turns.
local function strands(hub: Part, look: AuraLook.Look, scale: number, beams: { Beam })
	local span = 1 / STRAND_BEAMS
	for strand = 1, AuraLook.HELIX.strands do
		local previous: Attachment? = nil
		local previousPull = 0
		for step = 0, STRAND_BEAMS do
			local point, tangent = AuraLook.helixPoint(strand, step * span)
			point *= scale
			tangent *= scale
			local along = tangent.Unit
			local out = Vector3.new(point.X, 0, point.Z).Unit
			local side = along:Cross(out).Unit
			local attachment = Instance.new("Attachment")
			attachment.Name = `Strand{strand}_{step}`
			attachment.CFrame = CFrame.fromMatrix(point, along, side:Cross(along), side)
			attachment.Parent = hub
			local pull = tangent.Magnitude * span / 3
			if previous then
				table.insert(beams, ringBeam(`Strand{strand}`, previous, attachment, previousPull, pull, 10, look, scale, hub))
			end
			previous = attachment
			previousPull = pull
		end
	end
end

local function sparkleEmitter(look: AuraLook.Look, size: number, parent: Instance): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Color = ColorSequence.new(AuraLook.electronColor(look))
	emitter.LightEmission = SPARKLE_GLOW
	emitter.LightInfluence = 0
	-- Grows in, twinkles once, and goes out.
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, size),
		NumberSequenceKeypoint.new(0.5, size * 0.45),
		NumberSequenceKeypoint.new(0.75, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0.1)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Parent = parent
	return emitter
end

--- The sparkle storm's layers for this rung (AuraLook's `sparkle`), each only if on.
local function buildSparkle(rig: Rig)
	local look, scale, model = rig.look, rig.scale, rig.model
	local sparkle = look.sparkle

	if sparkle.dust > 0 then
		-- Star dust drifts off a shell just outside the rings (a ball round the atom, a
		-- cylinder round the helix), carried along with the body.
		local dust = fxPart("Dust", model)
		dust.Transparency = 1
		local emitter = sparkleEmitter(look, 0.35 * scale, dust)
		if look.form == "helix" then
			local h = AuraLook.HELIX
			dust.Size = Vector3.new(2 * h.radius + 0.6, h.top - h.bottom, 2 * h.radius + 0.6) * scale
			rig.dustOffset = CFrame.new(0, (h.top + h.bottom) / 2 * scale, 0)
			emitter.Shape = Enum.ParticleEmitterShape.Cylinder
		else
			dust.Shape = Enum.PartType.Ball
			dust.Size = Vector3.one * 2 * (AuraLook.RADIUS + 0.4) * scale
			emitter.Shape = Enum.ParticleEmitterShape.Sphere
		end
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		emitter.Rate = sparkle.dust
		emitter.Lifetime = NumberRange.new(1.2, 2)
		emitter.Speed = NumberRange.new(0.1 * scale, 0.4 * scale)
		emitter.Acceleration = Vector3.new(0, 0.5 * scale, 0)
		emitter.LockedToPart = true
		rig.dust = dust
		table.insert(rig.emitters, emitter)
	end

	if sparkle.shed > 0 then
		-- Each electron sheds sparkles that hang where it was and fall away.
		for _, electron in rig.electrons do
			local emitter = sparkleEmitter(look, 0.28 * scale, electron.part)
			emitter.Rate = sparkle.shed
			emitter.Lifetime = NumberRange.new(0.4, 0.8)
			emitter.Speed = NumberRange.new(0.3 * scale, 1.2 * scale)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Drag = 2
			emitter.Acceleration = Vector3.new(0, -1 * scale, 0)
			table.insert(rig.emitters, emitter)
		end
	end

	if sparkle.embers > 0 then
		-- Embers rise off a flat pad at the feet and stay in the world as you walk on.
		local embers = fxPart("Embers", model)
		embers.Transparency = 1
		embers.Size = Vector3.new(3.6, 0.1, 3.6) * scale
		local emitter = sparkleEmitter(look, 0.3 * scale, embers)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Rate = sparkle.embers
		emitter.Lifetime = NumberRange.new(1, 1.8)
		emitter.Speed = NumberRange.new(2.5 * scale, 5 * scale)
		emitter.SpreadAngle = Vector2.new(12, 12)
		emitter.Acceleration = Vector3.new(0, 1 * scale, 0)
		rig.embers = embers
		table.insert(rig.emitters, emitter)
	end

	if sparkle.burst > 0 then
		-- The core's glitter burst: nothing flows, `step` fires it every BURST_SECONDS.
		local core = Instance.new("Attachment")
		core.Name = "Core"
		core.Parent = rig.hub
		local emitter = sparkleEmitter(look, 0.45 * scale, core)
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Speed = NumberRange.new(5 * scale, 11 * scale)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 4
		emitter.Acceleration = Vector3.new(0, -2 * scale, 0)
		rig.burst = emitter
	end
end

local function build(anchor: BasePart, tier: number, scale: number, lift: number, character: Model?): Rig
	local look = AuraLook.get(tier)
	local model = Instance.new("Model")
	model.Name = if character then `Aura_{character.Name}` else "Aura_Display"

	local hub = fxPart("Hub", model)
	hub.Transparency = 1

	local ends: { { Attachment } } = {}
	local beams: { Beam } = {}
	local electrons: { Electron } = {}
	local ballSize = (0.3 + look.width) * scale
	local trailHalf = look.width * 0.8 * scale
	local function electron(ring: number, index: number)
		local ball = fxPart("Electron", model)
		ball.Shape = Enum.PartType.Ball
		ball.Material = Enum.Material.Neon
		ball.Color = AuraLook.electronColor(look)
		ball.Size = Vector3.one * ballSize
		-- The ball's Y is kept on the ring's axis (see step), so these two sit
		-- across the direction of travel and the trail has width.
		local t0 = Instance.new("Attachment")
		t0.Position = Vector3.new(0, trailHalf, 0)
		t0.Parent = ball
		local t1 = Instance.new("Attachment")
		t1.Position = Vector3.new(0, -trailHalf, 0)
		t1.Parent = ball
		local trail = Instance.new("Trail")
		trail.Attachment0 = t0
		trail.Attachment1 = t1
		trail.Lifetime = 0.3
		trail.MinLength = 0.05
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(look.color)
		trail.Transparency = NumberSequence.new(0.15, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.LightEmission = GLOW
		trail.LightInfluence = 0
		trail.Brightness = 1
		trail.Parent = ball
		table.insert(electrons, { part = ball, trail = trail, ring = ring, index = index, progress = 0 })
	end

	if look.form == "helix" then
		local h = AuraLook.HELIX
		strands(hub, look, scale, beams)
		halfCircles(hub, "Halo", h.haloRadius * scale, CFrame.new(0, h.haloY * scale, 0), look, scale, beams)
		halfCircles(hub, "Foot", h.footRadius * scale, CFrame.new(0, h.footY * scale, 0), look, scale, beams)
		-- `ring` is the strand here.
		for strand = 1, h.strands do
			for index = 1, look.electrons do
				electron(strand, index)
			end
		end
	else
		for ring = 1, look.rings do
			table.insert(ends, halfCircles(hub, `Ring{ring}`, AuraLook.RADIUS * scale, nil, look, scale, beams))
		end
		for ring = 1, look.rings do
			for index = 1, look.electrons do
				electron(ring, index)
			end
		end
	end

	local light: PointLight? = nil
	if look.core then
		local core = Instance.new("PointLight")
		core.Color = look.color
		core.Range = (CORE_RANGE + CORE_RANGE_STEP * (tier - 4)) * scale
		core.Brightness = CORE_BRIGHTNESS
		core.Shadows = false
		core.Parent = hub
		light = core
	end

	local rig: Rig = {
		anchor = anchor,
		humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil,
		isLocal = character ~= nil and character == localPlayer.Character,
		tier = tier,
		look = look,
		scale = scale,
		lift = lift,
		-- Out of step with every other aura, so a crowd does not spin in unison.
		seed = rng:NextNumber(0, 100),
		model = model,
		hub = hub,
		ends = ends,
		beams = beams,
		electrons = electrons,
		light = light,
		emitters = {},
		dust = nil,
		dustOffset = CFrame.identity,
		embers = nil,
		burst = nil,
		sinceBurst = rng:NextNumber(0, AuraLook.BURST_SECONDS),
		flare = 0,
		shown = true,
	}
	buildSparkle(rig)
	model.Parent = fx
	rigs[anchor] = rig
	return rig
end

local function setShown(rig: Rig, shown: boolean)
	if rig.shown == shown then
		return
	end
	rig.shown = shown
	for _, beam in rig.beams do
		beam.Enabled = shown
	end
	for _, electron in rig.electrons do
		electron.part.Transparency = if shown then 0 else 1
		electron.trail.Enabled = shown
		if shown then
			-- Otherwise the first frame back draws a streak from wherever the ball was
			-- when it went out.
			electron.trail:Clear()
		end
	end
	if rig.light then
		rig.light.Enabled = shown
	end
	for _, emitter in rig.emitters do
		emitter.Enabled = shown
	end
end

--- Make sure `anchor` has an aura of `tier` (rebuilding it on a change of tier), and
--- note that it is still wanted this scan.
local function want(anchor: BasePart, tier: number, scale: number, lift: number, character: Model?, seen: { [BasePart]: boolean })
	seen[anchor] = true
	local rig = rigs[anchor]
	if rig and rig.tier == tier then
		return
	end
	if rig then
		destroyRig(rig)
	end
	build(anchor, tier, scale, lift, character)
end

local function scan()
	local seen: { [BasePart]: boolean } = {}

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local tier = if character then character:GetAttribute(AuraLook.ATTRIBUTE) else nil
		if character and root and root:IsA("BasePart") and type(tier) == "number" then
			-- A stock HumanoidRootPart is 2 tall; a scaled avatar's aura scales with it.
			want(root, tier, root.Size.Y / 2, AuraLook.LIFT, character, seen)
		end
	end

	local cycle = math.floor(os.clock() / AuraLook.CYCLE_SECONDS) % AuraLook.count() + 1
	for _, display in CollectionService:GetTagged(AuraLook.DISPLAY_TAG) do
		if display:IsA("BasePart") and display:IsDescendantOf(Workspace) then
			local fixed = display:GetAttribute("AuraTier")
			local tier = if display:GetAttribute("AuraCycle") == true
				then cycle
				else (if type(fixed) == "number" then fixed else AuraLook.count())
			local scale = display:GetAttribute("AuraScale")
			local lift = display:GetAttribute("AuraLift")
			want(display, tier, if type(scale) == "number" then scale else 1, if type(lift) == "number" then lift else 0, nil, seen)
		end
	end

	for anchor, rig in rigs do
		if not seen[anchor] or anchor.Parent == nil then
			destroyRig(rig)
		end
	end
end

local movedParts: { BasePart } = {}
local movedFrames: { CFrame } = {}
local wrapped: { Trail } = {}

--- Shop card atoms (AuraLook.ICON_TAG) -> the pose their card's camera was framed at,
--- captured the first frame the card is on screen (StationController frames the
--- camera as it parents the model, so by then the framing is final).
local icons: { [Model]: { base: CFrame? } } = {}

--- True while `gui` is drawn and at least partly inside the screen: every ancestor
--- Visible, its ScreenGui Enabled, and its rect not wholly off either side. The shop
--- carousel keeps every tier's card alive side by side and clips the ones off the
--- panel, so Visible alone would animate all six.
local function onScreen(gui: GuiObject, screenWidth: number): boolean
	local left = gui.AbsolutePosition.X
	if left + gui.AbsoluteSize.X <= 0 or left >= screenWidth then
		return false
	end
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function stepIcons(now: number, screenWidth: number)
	for model, entry in icons do
		local viewport = model.Parent
		if viewport == nil or not viewport:IsA("ViewportFrame") or not onScreen(viewport, screenWidth) then
			continue
		end
		local camera = viewport.CurrentCamera
		if camera == nil then
			continue
		end
		if entry.base == nil then
			entry.base = camera.CFrame
		end
		-- The atom's pivot is the origin (StationController pivots it there), so turning
		-- the camera about the world Y circles it. Backwards, so the atom turns forwards.
		camera.CFrame = CFrame.fromAxisAngle(Vector3.yAxis, -now * AuraLook.PRECESS) * (entry.base :: CFrame)
		AuraLook.poseIcon(model, now)
	end
end

local function step(dt: number)
	sinceScan += dt
	if sinceScan >= RESCAN then
		sinceScan = 0
		scan()
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local now = os.clock()
	stepIcons(now, camera.ViewportSize.X)
	table.clear(movedParts)
	table.clear(movedFrames)

	for _, rig in rigs do
		local chest = rig.anchor.CFrame * CFrame.new(0, rig.lift * rig.scale, 0)
		local radius = AuraLook.RADIUS * rig.scale
		local distance = (chest.Position - eye).Magnitude
		local downed = rig.humanoid ~= nil and rig.humanoid.Health <= 0
		local inside = rig.isLocal and distance < radius + 1.5
		setShown(rig, distance <= FAR and not downed and not inside)
		if not rig.shown then
			continue
		end

		local t = now + rig.seed
		if rig.look.form == "helix" then
			-- The whole helix is fixed in the hub, so turning the hub turns it; only the
			-- electrons climb. One that wraps from the top back to the bottom has its
			-- trail cleared once it has moved, or it would streak down through the body.
			local hub = chest * AuraLook.helixFrame(t)
			table.insert(movedParts, rig.hub)
			table.insert(movedFrames, hub)
			for _, electron in rig.electrons do
				local s = AuraLook.helixProgress(rig.look, electron.ring, electron.index, t)
				local point, tangent = AuraLook.helixPoint(electron.ring, s)
				point *= rig.scale
				if s < electron.progress then
					table.insert(wrapped, electron.trail)
				end
				electron.progress = s
				table.insert(movedParts, electron.part)
				table.insert(movedFrames, hub * CFrame.lookAt(point, point + tangent))
			end
		else
			table.insert(movedParts, rig.hub)
			table.insert(movedFrames, chest)
			for ring, pair in rig.ends do
				local frame = AuraLook.ringFrame(ring, t)
				pair[1].CFrame = frame * CFrame.new(radius, 0, 0) * AXIS_TO_Z
				pair[2].CFrame = frame * CFrame.new(-radius, 0, 0) * AXIS_TO_Z
			end
			for _, electron in rig.electrons do
				local u = AuraLook.electronAngle(rig.look, electron.ring, electron.index, t)
				local frame = AuraLook.ringFrame(electron.ring, t)
				table.insert(movedParts, electron.part)
				table.insert(movedFrames, chest * frame * CFrame.new(math.cos(u) * radius, 0, math.sin(u) * radius))
			end
		end

		-- The sparkle storm's emitting parts follow the body upright (not the hub's turn).
		if rig.dust then
			table.insert(movedParts, rig.dust)
			table.insert(movedFrames, chest * rig.dustOffset)
		end
		if rig.embers then
			table.insert(movedParts, rig.embers)
			table.insert(movedFrames, chest * CFrame.new(0, AuraLook.FEET * rig.scale, 0))
		end
		if rig.burst then
			rig.sinceBurst += dt
			if rig.sinceBurst >= AuraLook.BURST_SECONDS then
				rig.sinceBurst = 0
				rig.flare = 1
				rig.burst:Emit(rig.look.sparkle.burst)
			end
		end
		rig.flare = math.max(0, rig.flare - dt * 2.5)
		if rig.light then
			rig.light.Brightness = CORE_BRIGHTNESS * (0.8 + 0.2 * math.sin(t * 2.4)) + BURST_FLARE * rig.flare
		end
	end

	if #movedParts > 0 then
		Workspace:BulkMoveTo(movedParts, movedFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	for _, trail in wrapped do
		trail:Clear()
	end
	table.clear(wrapped)
end

function AuraController.start()
	fx = Instance.new("Folder")
	fx.Name = "AuraFx"
	fx.Parent = Workspace
	for _, model in CollectionService:GetTagged(AuraLook.ICON_TAG) do
		if model:IsA("Model") then
			icons[model] = {}
		end
	end
	CollectionService:GetInstanceAddedSignal(AuraLook.ICON_TAG):Connect(function(model)
		if model:IsA("Model") then
			icons[model] = {}
		end
	end)
	CollectionService:GetInstanceRemovedSignal(AuraLook.ICON_TAG):Connect(function(model)
		icons[model :: Model] = nil
	end)
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and not warned then
			warned = true
			warn(`[aura] step failed: {err}`)
		end
	end)
end

return AuraController
