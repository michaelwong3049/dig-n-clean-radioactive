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

	IT IS A STARBURST OF GLOWING CRACKS NOW (changed on request), and most of it is not
	built here. The cracks carry rarity — more of them, forking, pulsing faster, the
	rarer the find (Tuning.AURA_CRACKS) — and rarity is per-player, so the cracks are
	per-player too: client/SpotCracks builds them locally, seeded off this aura's
	position so players with the same reading see identical cracks. What is left here
	is the shared anchor: the hot spot where the cracks meet (Core), the
	low PointLight in it, and the motes rising out of it. Still low and flat, still
	nothing like PLAN §10.9's tall rarity-coloured "somebody pulled a Legendary" beacon.
	The one thing that rises is the client's fan of blinking rays (~6-9 studs, on
	request; see Tuning.AURA_CRACKS for why that is allowed and how the beacon must stay
	different). Do not grow anything ELSE on the spot upward.

	The client OWNS how it looks (the cracks, their pulse, the rarity tint) but never
	where it is or whether it exists — see FieldController's header.
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

-- Instrument cyan, deliberately NOT the green of the sludge and the pools. An aura is
-- the detector talking to you, not the ground being dangerous, and the two readings
-- have to stay separable at a glance. In practice nobody sees it: the aura ships DARK
-- (below) and the client re-tints the core to its own rarity as it fades it in.
local GLOW = Color3.fromHex("2E9FD8")

-- The hot spot sits a hair proud of the surface and higher than anything
-- client/SpotCracks lays down (its tallest glow strip tops out ~0.26), so the crack
-- roots tuck under it instead of poking through where they all meet.
local CORE_LIFT = 0.24
local CORE_THICKNESS = 0.1

--- Build one aura, unparented. `surface` is the world point on the ground the signal
--- is buried under — the spot the player has to stand on.
---
--- `scale` comes off the buried item's weight (DigService, off Config/Weight.auraScale)
--- — a heavier thing gets a bigger hot spot here and longer, wider cracks on the
--- client. Both the scale and the surface point are stamped on the model (`WellScale`,
--- `Surface`) so client/SpotCracks can lay the cracks without guessing either.
function SignalAura.create(surface: Vector3, scale: number): Model
	local model = Instance.new("Model")
	model.Name = "Aura"
	model:SetAttribute("WellScale", scale)
	model:SetAttribute("Surface", surface)
	-- "Nobody's detector reaches this any more; it is on its way out." Stamped false at
	-- birth rather than left nil so the flag exists on the model from the first frame
	-- the client sees it — see Tuning.AURA_LINGER for what the client does with it.
	model:SetAttribute(Tuning.AURA_FADE_ATTR, false)

	-- The hot spot: a small flat disc where the cracks meet — the bullseye, the spot to
	-- stand on. A cylinder whose length (its local X) is tiny, stood so that short axis
	-- points at world up; getting the rotation wrong yields a coin on its edge.
	local diameter = Tuning.AURA_CORE * scale
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(CORE_THICKNESS, diameter, diameter)
	core.CFrame = CFrame.new(surface + Vector3.new(0, CORE_LIFT, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Locked = true
	core.Material = Enum.Material.SmoothPlastic
	core.Color = GLOW
	-- SHIPS DARK: core hidden, light off, no motes. FieldController fades all three in
	-- once this client has a rarity for the spot. Shipped lit, the raw cyan core showed
	-- for the frame between the aura replicating and the client first hiding it -- a
	-- one-frame pop, exactly the kind of snap the reveal is built to avoid.
	core.Transparency = 1
	core.Parent = model

	-- A slow curl of motes rising out of the core, so an idle spot still has life.
	-- FieldController sets the rate by rarity.
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
	motes.Rate = 0 -- ships dark; see the core
	motes.Speed = NumberRange.new(1, 2.2)
	motes.SpreadAngle = Vector2.new(14, 14)
	-- The core is a cylinder stood flat, so its LOCAL +X is world up. Emit along it
	-- or the motes fire sideways out of the rim.
	motes.EmissionDirection = Enum.NormalId.Right
	motes.Parent = core

	-- Nothing in the world is Neon since the de-neon pass, so this is what makes the
	-- spot read as light rather than as paint on the ground. Kept (a locator light is
	-- not a "glowing surface"), but low — it marks the spot without lighting up the
	-- field around it. Its brightness is FieldController's (by rarity); if spots ever
	-- get hard to find at camera distance, that is the knob. Do NOT make the cracks Neon.
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = 10
	light.Brightness = 0 -- ships dark; see the core
	light.Shadows = false
	light.Parent = core

	model.PrimaryPart = core
	CollectionService:AddTag(model, SignalAura.TAG)

	return model
end

return SignalAura
