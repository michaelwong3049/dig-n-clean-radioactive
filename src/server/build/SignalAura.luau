--!strict
--[[
	SignalAura.luau — the glow that marks a revealed signal.

	WHY THIS IS IN build/ AND NOT IN Services/
	It is an instance recipe, which is what this folder is for, and dropping it in
	Services/ would trip the bootstrap's "exists but is not in ORDER" warning — that
	check is right, and working around it by giving a part-builder an empty start()
	would be worse than putting it here.

	It is NOT a world generator like its siblings, though, and the difference matters:
	generators run once in edit mode and their output is saved with the place. These
	are built and destroyed constantly at runtime as players walk around, so nothing
	here goes through Kit.build/Kit.swap — that machinery exists to make a rebuild
	safe to interrupt, and it buys nothing for an object with a two-second lifespan.

	WHAT IT MAY AND MAY NOT SAY
	"Something is here." That is all. No rarity, no colour coding, no name. Every
	player in the server sees every aura (Tuning, "the reveal"), so anything encoded
	in one is public — and rarity is gated per-player by detectorClarity, which a
	shared instance physically cannot express. The rarity read lives on the client's
	radar blips instead, where the gate still works.

	KEEP IT VISUALLY DISTINCT FROM THE BEACON. PLAN §10.9 spends a light pillar on
	"somebody just pulled a Legendary, server-wide". If a routine reveal looks like a
	short version of that, §10.9 stops landing the moment it ships. This one is small,
	cold and cyan; the beacon is tall and rarity-coloured. Do not converge them.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local SignalAura = {}

--- The client finds auras by this tag to animate them (FieldController). The tag is
--- an index, not state: everything the client needs it derives from the transform.
--- Both constants come from Config/Tuning because the client needs them too and
--- cannot require anything out of ServerScriptService.
SignalAura.TAG = Tuning.AURA_TAG

--- Folder every aura lives under, so nothing has to walk Workspace to find them.
SignalAura.FOLDER = Tuning.AURA_FOLDER

-- Instrument cyan, deliberately NOT the acid green of the sludge and the pools. Kit's
-- palette note reserves neon acid green for "this is radioactive"; an aura is the
-- detector talking to you, not the ground being dangerous, and the two readings have
-- to stay separable at a glance.
local GLOW = Color3.fromHex("8FD8FF")

local function cylinder(name: string, diameter: number, length: number): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	-- A cylinder's axis runs along X, so size is (length, diameter, diameter) and the
	-- caller stands it up with a rotation. Getting this backwards yields a flat disc
	-- lying in the wrong plane, which looks like a bug in the position, not the size.
	part.Size = Vector3.new(length, diameter, diameter)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.Neon
	part.Color = GLOW
	return part
end

--- Build one aura, unparented. `surface` is the world point on the ground the signal
--- is buried under — the spot the player has to stand on.
function SignalAura.create(surface: Vector3, height: number, width: number, ringSize: number): Model
	local model = Instance.new("Model")
	model.Name = "Aura"

	local upright = CFrame.Angles(0, 0, math.pi / 2)

	local pillar = cylinder("Pillar", width, height)
	pillar.Transparency = 0.35
	pillar.CFrame = CFrame.new(surface + Vector3.new(0, height / 2, 0)) * upright
	pillar.Parent = model

	-- Thin, and lifted a hair off the surface. Flush with the plate it z-fights with
	-- the ground on half the hardware that will ever run this.
	local ring = cylinder("Ring", ringSize, 0.15)
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(surface + Vector3.new(0, 0.08, 0)) * upright
	ring.Parent = model

	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = 12
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = ring

	-- Self-animating, so an idle aura costs no script time on either side. The client
	-- only ever touches the pulse; the drift runs itself.
	local drift = Instance.new("ParticleEmitter")
	drift.Color = ColorSequence.new(GLOW)
	drift.LightEmission = 1
	drift.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	drift.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	drift.Lifetime = NumberRange.new(0.8, 1.4)
	drift.Rate = 7
	drift.Speed = NumberRange.new(1.5, 3)
	drift.SpreadAngle = Vector2.new(8, 8)
	-- The pillar is a cylinder stood upright, so its LOCAL +X is world up. The default
	-- emission direction (Top, local +Y) fires the particles sideways out of the side
	-- of the pillar, which reads as a leak rather than a plume.
	drift.EmissionDirection = Enum.NormalId.Right
	drift.Parent = pillar

	model.PrimaryPart = pillar
	CollectionService:AddTag(model, SignalAura.TAG)

	return model
end

return SignalAura
