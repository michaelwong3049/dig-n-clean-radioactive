--!strict
--[[
	ToolFX.luau — ambient light/particle accents for the top tiers of a gear
	track, keyed off the same `glow` colour ToolTiers already carries but
	nothing renders.

	Attached at equip time (ToolService.equip), not baked into the Studio
	models -- Detector and Magnet are still hand-authored in the place
	(ToolTiers.luau's header), so this is the way to give their top tiers a
	tell without touching that art, and it keeps the whole feature in git.

	No Neon or bloom (the world has neither since the de-neon pass): the glow is
	particles plus a coloured PointLight. The particles are alpha-blended
	(LightEmission 0) with LightInfluence 0 and a high Brightness -- additive
	blending (LightEmission 1) washed every colour out to white against the
	bright daylight ground, which is why the first pass could not be seen.

	NO NEW GAMEPLAY SIGNAL. DetectorController's header says the needle and
	audio ping were removed on request -- everything here is passive cosmetic
	flavour for the tier, not a new "something is here" readout.

	Every colour below comes from ToolTiers.get(track, tier).glow, never
	re-hardcoded, so a palette tweak there carries through automatically. A
	track/tier with no entry in SPECS is untouched -- apply() just returns.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local ToolTiers = require(Shared.Config.ToolTiers)

local ToolFX = {}

-- SIZED FOR THE GAMEPLAY CAMERA. The first pass was tuned close-up in a test rig
-- (0.14-0.3 stud particles, brightness-1 lights) and was invisible from where a
-- player actually stands: the default third-person camera sits ~15 studs back in
-- full daylight. Everything below is sized so it reads from there -- particles
-- about a stud across, and a light strong enough to tint the ground under the
-- tool.
--- Every emitter this module makes carries this name, so apply() can find its own
--- work again to size it for a display model without touching anything authored.
local EMITTER_NAME = "ToolFX"

local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

--- A coloured PointLight -- mostly shows as a tinted pool on the ground under the
--- tool, which is what makes a rare detector read as "lit" in daylight.
local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

--- Shared knobs every preset below builds on. Unlit (LightInfluence 0) and
--- over-bright, but NOT additive: LightEmission 1 turned every tier white
--- against the lime ground, so the colour -- the whole point -- was lost.
local function baseEmitter(color: Color3 | ColorSequence): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = EMITTER_NAME
	e.Texture = SPARKLE_TEXTURE
	e.Color = if typeof(color) == "ColorSequence" then color else ColorSequence.new(color)
	e.LightEmission = 0
	e.LightInfluence = 0
	e.Brightness = 3.5
	return e
end

--- Rising motes, fading out -- a cell/core quietly giving off light.
--- Isotope Scanner runs this slow and sparse; Deep Core Array runs it denser
--- and quicker for a warmer, more active feel.
local function drift(part: BasePart, color: Color3, rate: number, speed: NumberRange, lifetime: NumberRange)
	local e = baseEmitter(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = lifetime
	e.Rate = rate
	e.Speed = speed
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = part
end

--- Star-shaped twinkling that hangs around the part -- reads as an active
--- signal rather than a glow. Resonance Mapper and The Oracle want this.
local function sparkle(part: BasePart, color: Color3 | ColorSequence, rate: number, size: number)
	local e = baseEmitter(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.6),
		NumberSequenceKeypoint.new(0.4, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Rate = rate
	e.Speed = NumberRange.new(0.6, 1.4)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = part
end

--- Short, fast spark spray -- an electrical discharge rather than a glow.
--- Rail Coil's two emitter tips.
local function arcSpark(part: BasePart, color: Color3)
	local e = baseEmitter(color)
	e.Brightness = 4
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.12, 0.25)
	e.Rate = 40
	e.Speed = NumberRange.new(4, 8)
	e.SpreadAngle = Vector2.new(45, 45)
	e.Parent = part
end

--- Motes that hold near the part and shrink to nothing instead of drifting
--- away -- matter being crushed into the Singularity Coil's core, the one
--- effect here that reads as pulling IN rather than glowing OUT.
local function shrinkMotes(part: BasePart, color: Color3)
	local e = baseEmitter(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Rate = 22
	e.Speed = NumberRange.new(0.3, 0.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = part
end

--- The Oracle is the top of the ladder, and its `glow` is nearly white -- in
--- plain sparkles it looked exactly like the white signal rays over a find. Its
--- sparkles run the spectrum instead, so the best detector is unmistakable.
local PRISM = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FF7AD9")),
	ColorSequenceKeypoint.new(0.25, Color3.fromHex("FFD36E")),
	ColorSequenceKeypoint.new(0.5, Color3.fromHex("7CFFB2")),
	ColorSequenceKeypoint.new(0.75, Color3.fromHex("6EC8FF")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("B58CFF")),
})

-- Track -> tier NAME -> build(model, glow). Keyed by the ToolTiers name, not
-- the tier number, because the ladder moves: the Rust Bucket slid every detector
-- up one rung, and a number-keyed table would have lit the wrong tools. Only
-- tiers that carry a `glow` in ToolTiers show up here -- the rarest rungs of
-- each track. Part names are verified against the live Studio models
-- (Detector's sit directly under the tier model; Magnet's are nested one level
-- under a named sub-model), so every lookup below is recursive.
local function partNamed(model: Model, ...: string): BasePart?
	for _, name in { ... } do
		local part = model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local SPECS: { [string]: { [string]: (Model, Color3) -> () } } = {
	Detector = {
		["Isotope Scanner"] = function(model: Model, color: Color3)
			local part = partNamed(model, "cell_window", "isotope_cell")
			if part then
				light(part, color, 9, 2.5)
				drift(part, color, 8, NumberRange.new(0.8, 1.4), NumberRange.new(1.0, 1.6))
			end
		end,
		["Resonance Mapper"] = function(model: Model, color: Color3)
			local part = partNamed(model, "resonance_node")
			if part then
				light(part, color, 9, 2.5)
				sparkle(part, color, 18, 1.1)
			end
		end,
		["Deep Core Array"] = function(model: Model, color: Color3)
			local part = partNamed(model, "lit_core")
			if part then
				light(part, color, 10, 3)
				drift(part, color, 18, NumberRange.new(1.5, 2.5), NumberRange.new(0.7, 1.2))
			end
		end,
		["The Oracle"] = function(model: Model, color: Color3)
			local lens = partNamed(model, "oracle_lens")
			if lens then
				light(lens, color, 11, 3)
				sparkle(lens, PRISM, 26, 1.3)
			end
			local ring = partNamed(model, "aux_ring")
			if ring then
				sparkle(ring, PRISM, 10, 0.9)
			end
		end,
	},
	Magnet = {
		["Rail Coil"] = function(model: Model, color: Color3)
			for _, name in { "emitter_r", "emitter_l" } do
				local part = partNamed(model, name)
				if part then
					arcSpark(part, color)
				end
			end
			local tip = partNamed(model, "emitter_r")
			if tip then
				light(tip, color, 10, 2.5)
			end
		end,
		["Singularity Coil"] = function(model: Model, color: Color3)
			local part = partNamed(model, "core_halo")
			if part then
				light(part, color, 12, 3)
				shrinkMotes(part, color)
			end
		end,
	},
}

local function scaleSequence(seq: NumberSequence, k: number): NumberSequence
	local points = {}
	for _, p in seq.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k))
	end
	return NumberSequence.new(points)
end

--- Attaches this tier's ambient FX to an already-cloned tool model. A no-op
--- for any tier without a `glow` or an entry above -- the common rungs of both
--- tracks are untouched by design.
---
--- `particleScale` is for DISPLAY models (build/Shops' rack), applied after the
--- model is scaled: particles grow with an enlarged model so they stay in
--- proportion, but lights never do -- a 3x Oracle light floods the whole stall
--- deck white. The rack passes max(scale, 1), so a magnet shrunk to fit its slot
--- keeps full-size effects instead of shrinking them to specks.
function ToolFX.apply(model: Model, track: string, tier: number, particleScale: number?)
	local byName = SPECS[track]
	if byName == nil then
		return
	end
	local look = ToolTiers.get(track, tier)
	local build = byName[look.name]
	if build and look.glow then
		build(model, look.glow)
	end
	local k = particleScale or 1
	if k ~= 1 then
		for _, d in model:GetDescendants() do
			if d:IsA("ParticleEmitter") and d.Name == EMITTER_NAME then
				d.Size = scaleSequence(d.Size, k)
				d.Speed = NumberRange.new(d.Speed.Min * k, d.Speed.Max * k)
			end
		end
	end
end

return ToolFX
