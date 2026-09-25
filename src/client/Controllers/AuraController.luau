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

type Electron = { part: Part, trail: Trail, ring: number, index: number }

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

local function build(anchor: BasePart, tier: number, scale: number, lift: number, character: Model?): Rig
	local look = AuraLook.get(tier)
	local model = Instance.new("Model")
	model.Name = if character then `Aura_{character.Name}` else "Aura_Display"

	local hub = fxPart("Hub", model)
	hub.Transparency = 1

	local radius = AuraLook.RADIUS * scale
	local bend = HALF_CIRCLE * radius
	local ends: { { Attachment } } = {}
	local beams: { Beam } = {}
	for ring = 1, look.rings do
		local a = Instance.new("Attachment")
		a.Name = `Ring{ring}A`
		a.Parent = hub
		local b = Instance.new("Attachment")
		b.Name = `Ring{ring}B`
		b.Parent = hub
		table.insert(ends, { a, b })
		for _, side in { 1, -1 } do
			local beam = Instance.new("Beam")
			beam.Name = `Ring{ring}`
			beam.Attachment0 = a
			beam.Attachment1 = b
			beam.CurveSize0 = side * bend
			beam.CurveSize1 = -side * bend
			beam.Segments = 24
			beam.FaceCamera = true
			beam.Width0 = look.width * scale
			beam.Width1 = look.width * scale
			beam.Color = ColorSequence.new(look.color)
			beam.Transparency = NumberSequence.new(look.transparency)
			beam.LightEmission = GLOW
			beam.LightInfluence = 0
			beam.Brightness = 1
			beam.Parent = hub
			table.insert(beams, beam)
		end
	end

	local electrons: { Electron } = {}
	local ballSize = (0.3 + look.width) * scale
	local trailHalf = look.width * 0.8 * scale
	for ring = 1, look.rings do
		for index = 1, look.electrons do
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
			table.insert(electrons, { part = ball, trail = trail, ring = ring, index = index })
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

	model.Parent = fx
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
		shown = true,
	}
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
		if rig.light then
			rig.light.Brightness = CORE_BRIGHTNESS * (0.8 + 0.2 * math.sin(t * 2.4))
		end
	end

	if #movedParts > 0 then
		Workspace:BulkMoveTo(movedParts, movedFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
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
