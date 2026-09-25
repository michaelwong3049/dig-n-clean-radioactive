--!strict
--[[
	ToolFX.luau — ambient light/particle accents for the top tiers of a gear
	track, keyed off the same `glow` colour ToolTiers already carries but
	nothing renders.

	Attached at equip time (ToolService.equip), not baked into the Studio
	models -- Detector and Magnet are still hand-authored in the place
	(ToolTiers.luau's header), so this is the way to give their top tiers a
	tell without touching that art, and it keeps the whole feature in git.
	build/Shops puts the same FX on the shop rack's display models.

	No Neon or bloom (the world has neither since the de-neon pass): the glow is
	particles and a low coloured PointLight. Particles are alpha-blended
	(LightEmission 0) with LightInfluence 0 -- additive blending (LightEmission 1)
	washed every colour out to white against the bright daylight ground.

	ONE IDEA PER DETECTOR, AND QUIET. The second pass gave all four detectors the
	same bright sparkle cloud at different colours, and it read as loud and
	repetitive. Each detector now does one small thing its own model suggests: a
	cell that breathes, a pulse running along a grid bar, embers off a core, glints
	running round a ring. Low rates and low brightness -- they should reward a
	look at the coil, not shout across the field.

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

--- Every emitter and attachment this module makes carries this name, so
--- apply() can find its own work again to size it for a display model without
--- touching anything authored.
local FX_NAME = "ToolFX"

local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

--- A coloured PointLight, kept low: enough to tint the coil and the ground
--- just under it, not a pool that announces the tool from across the field.
local function light(part: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = part
end

--- Shared knobs every particle preset builds on. Unlit (LightInfluence 0) but
--- NOT additive, so each tier keeps its colour in daylight.
local function baseEmitter(color: Color3 | ColorSequence): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = FX_NAME
	e.Texture = SPARKLE_TEXTURE
	e.Color = if typeof(color) == "ColorSequence" then color else ColorSequence.new(color)
	e.LightEmission = 0
	e.LightInfluence = 0
	e.Brightness = 2
	return e
end

local function seq(...: number): NumberSequence
	local values = { ... }
	local points = {}
	for i = 1, #values, 2 do
		table.insert(points, NumberSequenceKeypoint.new(values[i], values[i + 1]))
	end
	return NumberSequence.new(points)
end

-- ── Detector presets ──────────────────────────────────────────────────────────

--- ISOTOPE SCANNER: the cell breathes. One soft glow at a time swells over the
--- cell window and fades, about once every two seconds, pinned to the part so it
--- rides the sweep. The slowest, calmest effect -- it is the first rare rung.
local function breathe(part: BasePart, color: Color3, size: number)
	local e = baseEmitter(color)
	e.LockedToPart = true
	e.Brightness = 2.5
	e.Size = seq(0, 0, 0.5, size, 1, 0)
	e.Transparency = seq(0, 1, 0.5, 0.25, 1, 1)
	e.Lifetime = NumberRange.new(2.2)
	e.Rate = 0.45
	e.Speed = NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-12, 12)
	e.Parent = part
end

--- RESONANCE MAPPER: a pulse runs along the grid. One soft dot of light is born
--- at one end of the part and travels its length in `lifetime` seconds, pinned
--- to the part so it rides the sweep. Lightened towards white: a purple glow
--- over the purple frame had no contrast and could not be seen at all. (A Beam
--- scrolling ItemFxController's glint streak was tried first -- the streak all
--- but vanished at this width and the beam read as a flat white line.)
local function travelPulse(part: BasePart, color: Color3, axis: Vector3, direction: Enum.NormalId, lifetime: number, rate: number)
	local a = Instance.new("Attachment")
	a.Name = FX_NAME
	a.Position = -part.Size * axis / 2
	a.Parent = part

	local e = baseEmitter(color:Lerp(Color3.new(1, 1, 1), 0.45))
	e.LockedToPart = true
	e.Brightness = 3
	e.EmissionDirection = direction
	e.SpreadAngle = Vector2.zero
	e.Speed = NumberRange.new((part.Size * axis).Magnitude / lifetime)
	e.Lifetime = NumberRange.new(lifetime)
	e.Rate = rate
	e.Size = seq(0, 0.15, 0.15, 0.55, 0.85, 0.55, 1, 0.15)
	e.Transparency = seq(0, 1, 0.15, 0.1, 0.85, 0.1, 1, 1)
	e.Parent = a
end

--- DEEP CORE ARRAY: embers. A few small sparks lift off the core, cooling from
--- the tier colour towards a deeper orange as they rise and slow. Sparse on
--- purpose -- three a second reads as heat, thirty read as a fire.
local function embers(part: BasePart, color: Color3)
	local e = baseEmitter(ColorSequence.new(color, color:Lerp(Color3.fromRGB(255, 90, 20), 0.6)))
	e.Brightness = 2.5
	e.Size = seq(0, 0.22, 1, 0)
	e.Transparency = seq(0, 0, 0.7, 0.2, 1, 1)
	e.Lifetime = NumberRange.new(1.2, 2)
	e.Rate = 3
	e.Speed = NumberRange.new(0.8, 1.6)
	e.Drag = 1.5
	e.Acceleration = Vector3.new(0, 0.6, 0)
	e.SpreadAngle = Vector2.new(20, 20)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = part
end

--- THE ORACLE: glints running round the rim. A Disc-shaped emitter with its
--- inner radius pushed almost to the edge (ShapePartial) only ever places a
--- particle on the ring itself, so small star glints wink on and off at random
--- points round the search ring, each in a different colour of the spectrum.
local function rimGlints(part: BasePart, colors: ColorSequence)
	local e = baseEmitter(colors)
	e.Shape = Enum.ParticleEmitterShape.Disc
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapePartial = 0.9
	e.LockedToPart = true
	e.Brightness = 3
	e.Size = seq(0, 0, 0.3, 0.55, 1, 0)
	e.Transparency = seq(0, 0, 1, 0.4)
	e.Lifetime = NumberRange.new(0.35, 0.55)
	e.Rate = 6
	e.Speed = NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Parent = part
end

--- The Oracle's `glow` is nearly white, and white glints looked exactly like
--- the white signal rays over a find. Each glint takes one colour of the
--- spectrum instead (a short lifetime barely moves along the gradient).
local PRISM = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("FF7AD9")),
	ColorSequenceKeypoint.new(0.25, Color3.fromHex("FFD36E")),
	ColorSequenceKeypoint.new(0.5, Color3.fromHex("7CFFB2")),
	ColorSequenceKeypoint.new(0.75, Color3.fromHex("6EC8FF")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("B58CFF")),
})

-- ── Magnet presets ────────────────────────────────────────────────────────────

--- Short, fast spark spray -- an electrical discharge rather than a glow.
--- Rail Coil's two emitter tips.
local function arcSpark(part: BasePart, color: Color3)
	local e = baseEmitter(color)
	e.Brightness = 4
	e.Size = seq(0, 0.8, 1, 0)
	e.Transparency = seq(0, 0, 1, 1)
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
	e.Brightness = 3.5
	e.Size = seq(0, 1.3, 1, 0)
	e.Transparency = seq(0, 0.1, 0.8, 0.3, 1, 1)
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Rate = 22
	e.Speed = NumberRange.new(0.3, 0.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = part
end

-- Track -> tier NAME -> build(model, glow). Keyed by the ToolTiers name, not
-- the tier number, because the ladder moves: the Rust Bucket slid every detector
-- up one rung, and a number-keyed table would have lit the wrong tools. Only
-- tiers that carry a `glow` in ToolTiers show up here -- the rarest rungs of
-- each track. Part names are verified against the live Studio models
-- (Detector's sit directly under the tier model; Magnet's are nested one level
-- under a named sub-model), so every lookup below is recursive. Every detector
-- coil head lies flat in its part's XZ plane.
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
				light(part, color, 5, 0.8)
				breathe(part, color, 1.1)
			end
		end,
		["Resonance Mapper"] = function(model: Model, color: Color3)
			-- The straight bar runs front-to-back down the middle of the hex; the
			-- frame's own width carries a second, slower pulse across it, so the
			-- two cross the node out of step.
			local bar = partNamed(model, "grid_bar2")
			if bar then
				travelPulse(bar, color, Vector3.zAxis, Enum.NormalId.Back, 1.1, 0.7)
			end
			local frame = partNamed(model, "hex_frame")
			if frame then
				travelPulse(frame, color, Vector3.xAxis, Enum.NormalId.Right, 1.4, 0.5)
			end
			local node = partNamed(model, "resonance_node")
			if node then
				light(node, color, 5, 0.8)
			end
		end,
		["Deep Core Array"] = function(model: Model, color: Color3)
			local part = partNamed(model, "lit_core")
			if part then
				light(part, color, 6, 1)
				embers(part, color)
			end
		end,
		["The Oracle"] = function(model: Model, color: Color3)
			local ring = partNamed(model, "search_ring1")
			if ring then
				rimGlints(ring, PRISM)
			end
			local lens = partNamed(model, "oracle_lens")
			if lens then
				light(lens, color, 6, 1)
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

local function scaleSequence(s: NumberSequence, k: number): NumberSequence
	local points = {}
	for _, p in s.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k))
	end
	return NumberSequence.new(points)
end

--- Attaches this tier's ambient FX to an already-cloned tool model. A no-op
--- for any tier without a `glow` or an entry above -- the common rungs of both
--- tracks are untouched by design.
---
--- `particleScale` is for DISPLAY models (build/Shops' rack), applied after the
--- model is scaled: particles grow with it, but lights never do
--- -- a 3x Oracle light floods the whole stall deck white.
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
			if d.Name ~= FX_NAME then
				continue
			end
			if d:IsA("ParticleEmitter") then
				d.Size = scaleSequence(d.Size, k)
				-- A part-locked emitter's speed is already measured off the scaled
				-- part (travelPulse runs exactly its length); scaling it again
				-- would fire the pulse off the end of the bar.
				if not d.LockedToPart then
					d.Speed = NumberRange.new(d.Speed.Min * k, d.Speed.Max * k)
				end
			end
		end
	end
end

return ToolFX
