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
	player sees every aura (Tuning, "the reveal"), but each player's ROLL for the
	signal under it is their own (DigService.rollFor) — signal X can be Rare for one
	player and Common for the next — so a shared instance physically cannot carry it.
	This part ships instrument cyan and nothing else. FieldController then RE-TINTS its
	own client's copy to that client's own rarity (DetectorController.contactRarityAt,
	off the per-player contacts payload). The rarity read also rides the client's radar
	blips, the same way and for the same reason.

	IT IS A LOW WELL, NOT A PILLAR (changed on request). Low and wide: a matte cyan
	disc set into the ground, a shimmering ForceField dome over it, a low PointLight in
	the core, and a few ripple discs the client (FieldController) drives expanding
	outward from it. The discs used to be Neon; the de-neon pass took them matte along
	with the rest of the world, so the dome, the light and the rising motes are what
	give the well its life now. The old tall thin pillar was too close to PLAN §10.9's
	server-wide "somebody pulled a Legendary" beacon; that one is TALL and
	RARITY-COLOURED, this one hugs the ground and is instrument cyan, and the two
	cannot be confused at any distance. Do not grow this one upward.

	The client OWNS how it looks (the ripple, the breathe, the lock-on, the rarity
	tint) but never where it is or whether it exists — see FieldController's header.
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

--- How many ripple discs each well carries. The client animates `Ripple1`..`RippleN`
--- expanding and fading on staggered phases; it finds them by that name prefix, so
--- this count lives here (the structure) and not in Tuning (the tuning).
SignalAura.RIPPLES = 3

-- Instrument cyan, deliberately NOT the green of the sludge and the pools. An aura is
-- the detector talking to you, not the ground being dangerous, and the two readings
-- have to stay separable at a glance.
--
-- A MID blue-cyan, not a pale one. The discs are matte since the de-neon pass and the
-- world no longer blooms, so a pale cyan would just read as washed-out grey against
-- the ground; this sits far enough down the channel to hold its colour flat-lit, with
-- the core's low PointLight doing the "this is a light source" work.
local GLOW = Color3.fromHex("2E9FD8")

--- A flat cyan disc: a cylinder whose length (its local X axis) is tiny, stood so
--- that short axis points at world up. Getting the rotation wrong yields a coin
--- standing on its edge, which reads as a bug in the position rather than the size.
local function disc(name: string, diameter: number, thickness: number): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(thickness, diameter, diameter)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = GLOW
	return part
end

--- Build one aura, unparented. `surface` is the world point on the ground the signal
--- is buried under — the spot the player has to stand on. `core` / `dome` are
--- diameters; `reach` is how far the ripples travel (the client reads it off the
--- part sizes, nothing is stored).
---
--- `core`/`dome` arrive pre-scaled by the buried item's weight (DigService, off
--- Config/Weight.auraScale) — a heavier thing gets a wider well. The scale relative
--- to the Tuning defaults is stamped on the model as `WellScale` so FieldController's
--- in-range freeze can size the ripple ring to THIS well's dome, not the default one.
function SignalAura.create(surface: Vector3, core: number, dome: number, reach: number): Model
	local model = Instance.new("Model")
	model.Name = "Aura"
	model:SetAttribute("WellScale", dome / Tuning.AURA_DOME)

	local flat = CFrame.Angles(0, 0, math.pi / 2) -- disc lying flat, short axis up

	-- The core: a small bright disc just proud of the ground — the bullseye. A touch
	-- transparent so it reads as a spot of light, not a solid coin, once bloom gets
	-- to it.
	local coreDisc = disc("Core", core * 0.42, 0.25)
	coreDisc.Transparency = 0.2
	coreDisc.CFrame = CFrame.new(surface + Vector3.new(0, 0.12, 0)) * flat
	coreDisc.Parent = model

	-- The dome: a FORCE FIELD ball centred on the ground so its bottom half is buried
	-- and only the cap shows. ForceField, not SmoothPlastic and not Glass — it renders
	-- as a shimmering translucent energy shell that keeps its own colour instead of
	-- taking the ground's, and it is the one bit of the aura that still has any life to
	-- it now the discs are matte. Wide and low: the whole aura stands barely a stud and
	-- a half tall, nothing like PLAN 10.9's pillar.
	local domeBall = Instance.new("Part")
	domeBall.Name = "Dome"
	domeBall.Shape = Enum.PartType.Ball
	domeBall.Size = Vector3.new(dome, dome, dome)
	domeBall.CFrame = CFrame.new(surface)
	domeBall.Anchored = true
	domeBall.CanCollide = false
	domeBall.CanQuery = false
	domeBall.CanTouch = false
	domeBall.CastShadow = false
	domeBall.Locked = true
	domeBall.Material = Enum.Material.ForceField
	domeBall.Color = GLOW
	domeBall.Transparency = 0.35
	domeBall.Parent = model

	-- The ripples. Built at `reach` diameter but invisible; the client scales each
	-- from a point out to here and fades it, staggered, so the well reads as pulsing.
	-- Thin, so what shows is the glowing rim of the disc rather than a filled circle.
	-- Server owns that they exist and where they sit (this file's header) — the
	-- client only ever changes Size and Transparency.
	for i = 1, SignalAura.RIPPLES do
		local ripple = disc(`Ripple{i}`, reach * 2, 0.06)
		ripple.Transparency = 1
		-- Staggered a hair in Y so three coincident discs do not z-fight the instant
		-- the client has them all small at once.
		ripple.CFrame = CFrame.new(surface + Vector3.new(0, 0.05 + i * 0.015, 0)) * flat
		ripple.Parent = model
	end

	-- A slow curl of motes rising out of the core, so an idle well still has life.
	-- Low rate on purpose: this is a well, not a fire.
	local motes = Instance.new("ParticleEmitter")
	motes.Color = ColorSequence.new(GLOW)
	motes.LightEmission = 1
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Lifetime = NumberRange.new(0.9, 1.6)
	motes.Rate = 4
	motes.Speed = NumberRange.new(1, 2.2)
	motes.SpreadAngle = Vector2.new(14, 14)
	-- The core is a cylinder stood flat, so its LOCAL +X is world up. Emit along it
	-- or the motes fire sideways out of the rim.
	motes.EmissionDirection = Enum.NormalId.Right
	motes.Parent = coreDisc

	-- The de-neon pass took the discs matte, so this is now the only thing making the
	-- well read as light rather than as a painted coin on the ground. Kept (a locator
	-- light is not a "glowing surface"), but low — it marks the spot without lighting
	-- up the field around it. If the well ever gets hard to find at camera distance,
	-- this brightness is the knob; do NOT put the discs back to Neon.
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = 10
	light.Brightness = 0.55
	light.Shadows = false
	light.Parent = coreDisc

	model.PrimaryPart = coreDisc
	CollectionService:AddTag(model, SignalAura.TAG)

	return model
end

return SignalAura
