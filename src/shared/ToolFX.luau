--!strict
--[[
	ToolFX.luau — ambient light/particle accents for the top tiers of a gear
	track, keyed off the same `glow` colour ToolTiers already carries but
	nothing renders.

	Attached at equip time (ToolService.equip), not baked into the Studio
	models -- Detector and Magnet are still hand-authored in the place
	(ToolTiers.luau's header), so this is the way to give their top tiers a
	tell without touching that art, and it keeps the whole feature in git.

	Matte parts + ParticleEmitter with LightEmission = 1 + a low PointLight is
	the same idiom SignalAura.luau uses to read as "light" without Neon or
	bloom (the world has neither any more since the de-neon pass).

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

--- One small PointLight -- low enough to read as an accent on something held
--- a few studs from the camera, not a beacon (compare SignalAura's ground
--- well light, Range 10 / Brightness 0.55, sized for a much bigger prop).
local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

--- Shared knobs every preset below builds on. LightEmission = 1 is what lets
--- a matte-coloured particle still read as glowing without Neon.
local function baseEmitter(color: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	return e
end

--- Slow upward drift, fading out -- a cell/core quietly giving off light.
--- Isotope Scanner runs this faint and idle; Deep Core Array runs it denser
--- and quicker for a warmer, more active feel.
local function drift(part: BasePart, color: Color3, rate: number, speed: NumberRange, lifetime: NumberRange)
	local e = baseEmitter(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = lifetime
	e.Rate = rate
	e.Speed = speed
	e.SpreadAngle = Vector2.new(18, 18)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = part
end

--- Tight, quick twinkling in place -- reads as an active signal rather than
--- a glow. Resonance Mapper and The Oracle's lens both want this over drift.
local function sparkle(part: BasePart, color: Color3, rate: number)
	local e = baseEmitter(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.14),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.35, 0.7)
	e.Rate = rate
	e.Speed = NumberRange.new(0.1, 0.3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = part
end

--- Short, punchy bursts -- an electrical discharge rather than a glow.
--- Rail Coil's two emitter tips.
local function arcSpark(part: BasePart, color: Color3)
	local e = baseEmitter(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.16),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.08, 0.18)
	e.Rate = 14
	e.Speed = NumberRange.new(2, 4)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Parent = part
end

--- Motes that hold near the part and shrink to nothing instead of drifting
--- away -- matter being crushed into the Singularity Coil's core, the one
--- effect here that reads as pulling IN rather than glowing OUT.
local function shrinkMotes(part: BasePart, color: Color3)
	local e = baseEmitter(color)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Rate = 10
	e.Speed = NumberRange.new(0.15, 0.35)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = part
end

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
				light(part, color, 5, 0.9)
				drift(part, color, 3, NumberRange.new(0.3, 0.6), NumberRange.new(1.0, 1.8))
			end
		end,
		["Resonance Mapper"] = function(model: Model, color: Color3)
			local part = partNamed(model, "resonance_node")
			if part then
				light(part, color, 5, 1.0)
				sparkle(part, color, 9)
			end
		end,
		["Deep Core Array"] = function(model: Model, color: Color3)
			local part = partNamed(model, "lit_core")
			if part then
				light(part, color, 6, 1.1)
				drift(part, color, 6, NumberRange.new(0.6, 1.0), NumberRange.new(0.7, 1.3))
			end
		end,
		["The Oracle"] = function(model: Model, color: Color3)
			local lens = partNamed(model, "oracle_lens")
			if lens then
				light(lens, color, 6, 1.1)
				sparkle(lens, color, 6)
			end
			local ring = partNamed(model, "aux_ring")
			if ring then
				sparkle(ring, color, 3)
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
		end,
		["Singularity Coil"] = function(model: Model, color: Color3)
			local part = partNamed(model, "core_halo")
			if part then
				light(part, color, 6, 1.1)
				shrinkMotes(part, color)
			end
		end,
	},
}

--- Attaches this tier's ambient FX to an already-cloned tool model. A no-op
--- for any tier without a `glow` or an entry above -- the common rungs of both
--- tracks are untouched by design.
function ToolFX.apply(model: Model, track: string, tier: number)
	local byName = SPECS[track]
	if byName == nil then
		return
	end
	local look = ToolTiers.get(track, tier)
	local build = byName[look.name]
	if build and look.glow then
		build(model, look.glow)
	end
end

return ToolFX
