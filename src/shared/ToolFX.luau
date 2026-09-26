--!strict
--[[
	ToolFX.luau — ambient light/particle accents for the top tiers of a gear
	track, keyed off the same `glow` colour ToolTiers already carries but
	nothing renders.

	Attached at equip time (ToolService.equip), not baked into the Studio
	models -- Detector and Magnet are still hand-authored in the place
	(ToolTiers.luau's header), so this is the way to give their top tiers a
	tell without touching that art, and it keeps the whole feature in git.
	build/Shops puts the same FX on the shop rack's display models, and
	Plots.setHoseTier on the hose parked on a player's wash-station mast (a hose
	is never held, so that and the rack are the only places the Cleaner's show).

	No Neon or bloom (the world has neither since the de-neon pass): the glow is
	particles and a low coloured PointLight. Particles are alpha-blended
	(LightEmission 0) with LightInfluence 0 -- additive blending (LightEmission 1)
	washed every colour out to white against the bright daylight ground.

	ONE IDEA PER DETECTOR, AND QUIET. The second pass gave all four detectors the
	same bright sparkle cloud at different colours, and it read as loud and
	repetitive. Each detector now does one small thing its own model suggests: a
	cell that breathes, a pulse running along a grid bar, embers off a core, glints
	running round a ring. The first quiet cut of these (half the size, half the
	rate, dim lights) could not be seen at all from the gameplay camera; the
	numbers below are the middle the user signed off on, live in Studio.

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

--- A coloured PointLight tinting the coil and a small pool of ground under it.
--- From the usual high, pulled-back camera that pool is the most readable cue,
--- so the detectors keep a moderate one (range 8, brightness 1.8).
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
	e.Rate = 0.6
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
	e.Size = seq(0, 0.25, 0.15, 0.95, 0.85, 0.95, 1, 0.25)
	e.Transparency = seq(0, 1, 0.15, 0.1, 0.85, 0.1, 1, 1)
	e.Parent = a
end

--- DEEP CORE ARRAY: embers. A few small sparks lift off the core, cooling from
--- the tier colour towards a deeper orange as they rise and slow. Sparse on
--- purpose -- six a second reads as heat, thirty read as a fire.
local function embers(part: BasePart, color: Color3): ParticleEmitter
	local e = baseEmitter(ColorSequence.new(color, color:Lerp(Color3.fromRGB(255, 90, 20), 0.6)))
	e.Brightness = 2.5
	e.Size = seq(0, 0.37, 1, 0)
	e.Transparency = seq(0, 0, 0.7, 0.2, 1, 1)
	e.Lifetime = NumberRange.new(1.2, 2)
	e.Rate = 6
	e.Speed = NumberRange.new(0.8, 1.6)
	e.Drag = 1.5
	e.Acceleration = Vector3.new(0, 0.6, 0)
	e.SpreadAngle = Vector2.new(20, 20)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = part
	return e
end

--- THE ORACLE: glints running round the rim. A Disc-shaped emitter with its
--- inner radius pushed almost to the edge (ShapePartial) only ever places a
--- particle on the ring itself, so small star glints wink on and off at random
--- points round the search ring, each in a different colour of the spectrum.
local function rimGlints(part: BasePart, colors: ColorSequence): ParticleEmitter
	local e = baseEmitter(colors)
	e.Shape = Enum.ParticleEmitterShape.Disc
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapePartial = 0.9
	e.LockedToPart = true
	e.Brightness = 3
	e.Size = seq(0, 0, 0.3, 0.9, 1, 0)
	e.Transparency = seq(0, 0, 1, 0.4)
	e.Lifetime = NumberRange.new(0.35, 0.55)
	e.Rate = 10
	e.Speed = NumberRange.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Parent = part
	return e
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

-- ── Toxic Twilight presets ────────────────────────────────────────────────────
--
-- The sixteen imported rungs Twilight's shops sell (Detector 10-15, Magnet 7-11,
-- Cleaner 8-12). Same rules as above -- one idea per tool, taken from what its
-- model is (a molten core puffs heat, a void swallows light) -- but a step
-- LOUDER than the Base Camp rungs, by request: these are the endgame tools, so
-- sizes run ~1.3x and rates higher. Each preset is a property table on top of
-- baseEmitter rather than a function per effect: sixteen near-identical bodies
-- of assignments would bury what makes each one different.

local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SQUARE_TEXTURE = "rbxasset://textures/particles/SquareParticle.png"

local function emit(parent: Instance, color: Color3 | ColorSequence, props: { [string]: any }): ParticleEmitter
	local e = baseEmitter(color)
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function gradient(...: Color3): ColorSequence
	local colors = { ... }
	local points = {}
	for i, c in colors do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(points)
end

local WHITE = Color3.new(1, 1, 1)

-- BRIGHTNESS STAYS LOW (1.2-2) WHEREVER THE HUE IS THE POINT. An unlit particle's
-- colour is multiplied by Brightness, so the 3-4 the Base Camp glints use clips a
-- pastel tint straight to white: the first cut of these made a green seep, a teal
-- aurora and a pink nebula that all read as the same white haze. The glints and
-- stars below keep a high value because white-hot is what they should be.

--- Soft motes seeping up out of a small part and fading as they rise.
local function seep(part: BasePart, color: Color3, rate: number)
	emit(part, color, {
		Brightness = 1.6,
		Size = seq(0, 0, 0.25, 0.65, 1, 0),
		Transparency = seq(0, 0.3, 1, 1),
		Lifetime = NumberRange.new(1.2, 1.8),
		Rate = rate,
		Speed = NumberRange.new(0.4, 0.8),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(15, 15),
		Acceleration = Vector3.new(0, 0.5, 0),
		Drag = 0.5,
	})
end

--- One star that swells and winks out on a part, spinning as it goes.
local function wink(part: BasePart, color: Color3, size: number, rate: number)
	emit(part, color:Lerp(WHITE, 0.25), {
		LockedToPart = true,
		Brightness = 3.5,
		Size = seq(0, 0, 0.35, size, 1, 0),
		Transparency = seq(0, 0.1, 1, 0.5),
		Lifetime = NumberRange.new(0.6, 0.9),
		Rate = rate,
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	})
end

--- Something collapsing INTO a point: a big dim ring shrinking to nothing on the
--- part, darkening as it goes. The Singularity Coil's motes shrink too, but they
--- glow; these go dark, which is what sells "null" and "void".
local function collapse(part: BasePart, color: Color3, size: number, rate: number)
	emit(part, gradient(color:Lerp(WHITE, 0.3), color, Color3.fromHex("140A24")), {
		LockedToPart = true,
		Brightness = 2,
		Size = seq(0, size, 1, 0),
		Transparency = seq(0, 1, 0.3, 0.2, 1, 0),
		Lifetime = NumberRange.new(1.1, 1.4),
		Rate = rate,
		Speed = NumberRange.new(0),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(120, 180),
	})
end

--- Every BasePart in `model` whose name matches `pattern`, in a stable order.
local function partsMatching(model: Model, pattern: string): { BasePart }
	local found = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and string.match(d.Name, pattern) then
			table.insert(found, d)
		end
	end
	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)
	return found
end

--- The hoses are two or three textured meshes plus a hidden `Nozzle` core whose
--- `Muzzle` attachment sits on the business end, facing out down -Z (Front). The
--- barrel is always the `*_part2` mesh.
local function muzzleOf(model: Model): Attachment?
	local core = model.PrimaryPart
	local muzzle = if core then core:FindFirstChild("Muzzle") else nil
	return if muzzle and muzzle:IsA("Attachment") then muzzle else nil
end

local function barrelOf(model: Model): BasePart?
	return partsMatching(model, "_part2$")[1]
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
				light(part, color, 8, 1.8)
				breathe(part, color, 1.9)
			end
		end,
		["Resonance Mapper"] = function(model: Model, color: Color3)
			-- The straight bar runs front-to-back down the middle of the hex; the
			-- frame's own width carries a second, slower pulse across it, so the
			-- two cross the node out of step.
			local bar = partNamed(model, "grid_bar2")
			if bar then
				travelPulse(bar, color, Vector3.zAxis, Enum.NormalId.Back, 1.1, 1.1)
			end
			local frame = partNamed(model, "hex_frame")
			if frame then
				travelPulse(frame, color, Vector3.xAxis, Enum.NormalId.Right, 1.4, 0.8)
			end
			local node = partNamed(model, "resonance_node")
			if node then
				light(node, color, 8, 1.8)
			end
		end,
		["Deep Core Array"] = function(model: Model, color: Color3)
			local part = partNamed(model, "lit_core")
			if part then
				light(part, color, 8, 1.8)
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
				light(lens, color, 8, 1.8)
			end
		end,

		-- Toxic Twilight. Every coil head is axis-aligned with its model and the model
		-- is carried (and racked, via HoldCFrame) upright, so each part's Top is up.
		["Vein Whisperer"] = function(model: Model, color: Color3)
			-- Sap seeping up out of the twelve emitter nodes round the twin coils.
			for _, node in partsMatching(model, "^emitter_%d_%d$") do
				seep(node, color, 1.3)
			end
			local hub = partNamed(model, "phase_hub")
			if hub then
				light(hub, color, 9, 2.2)
			end
		end,
		["Aurora Rake"] = function(model: Model, color: Color3)
			-- A curtain of aurora rising off the ribbon strung between the tines: tall
			-- (negative Squash) soft wisps born all along the bar, teal into violet.
			local ribbon = partNamed(model, "aurora_ribbon")
			if ribbon then
				emit(ribbon, gradient(color, Color3.fromHex("7CFFB2"), Color3.fromHex("B58CFF")), {
					Texture = SMOKE_TEXTURE,
					Brightness = 1.3,
					Size = seq(0, 0.5, 0.4, 1, 1, 0.7),
					Squash = seq(0, -1.4, 1, -1.4),
					Transparency = seq(0, 1, 0.25, 0.15, 0.7, 0.3, 1, 1),
					Lifetime = NumberRange.new(1.6, 2.2),
					Rate = 9,
					Speed = NumberRange.new(0.6, 1),
					EmissionDirection = Enum.NormalId.Top,
					SpreadAngle = Vector2.new(4, 4),
				})
			end
			local eye = partNamed(model, "aurora_eye")
			if eye then
				light(eye, color, 9, 2.2)
			end
		end,
		["Strata Lance"] = function(model: Model, color: Color3)
			-- Hot smoke puffing out of the three exhaust stacks, glowing where it
			-- leaves the stack and cooling to soot as it climbs.
			for _, stack in partsMatching(model, "^stack_glow") do
				emit(stack, gradient(color, Color3.fromHex("8A5A3A"), Color3.fromHex("4A423C")), {
					Texture = SMOKE_TEXTURE,
					Brightness = 2,
					Size = seq(0, 0.3, 1, 1.1),
					Transparency = seq(0, 0.2, 1, 1),
					Lifetime = NumberRange.new(1.1, 1.5),
					Rate = 3.5,
					Speed = NumberRange.new(1.2, 1.8),
					Drag = 1,
					EmissionDirection = Enum.NormalId.Top,
					SpreadAngle = Vector2.new(8, 8),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-40, 40),
				})
			end
			local core = partNamed(model, "molten_core")
			if core then
				light(core, color, 9, 2.4)
			end
		end,
		["Leyline Tap"] = function(model: Model, color: Color3)
			-- A thin column of light tapped straight up out of the ley core, and the
			-- eight rune nodes round the halo winking in turn.
			local core = partNamed(model, "ley_core")
			if core then
				emit(core, color, {
					Brightness = 2,
					Size = seq(0, 0.55, 1, 0),
					Transparency = seq(0, 0.1, 1, 0.6),
					Lifetime = NumberRange.new(0.8, 1.1),
					Rate = 16,
					Speed = NumberRange.new(2.6, 3.2),
					EmissionDirection = Enum.NormalId.Top,
					SpreadAngle = Vector2.new(2, 2),
				})
				light(core, color, 9, 2.2)
			end
			for _, rune in partsMatching(model, "^rune_node") do
				wink(rune, color, 0.8, 0.5)
			end
		end,
		["Null Compass"] = function(model: Model, color: Color3)
			-- Light falling into the void sphere, and the orbiting shards catching it.
			local sphere = partNamed(model, "void_sphere")
			if sphere then
				collapse(sphere, color, 3, 1.6)
				light(sphere, color, 9, 2.2)
			end
			for _, shard in partsMatching(model, "^orbit_shard") do
				wink(shard, color, 0.7, 0.5)
			end
		end,
		["Prime Meridian"] = function(model: Model, color: Color3)
			-- The top rung: gold glints racing round the halo, the crown gems flaring.
			local halo = partNamed(model, "gold_halo")
			if halo then
				local glints = rimGlints(halo, gradient(color, WHITE, color))
				glints.Rate = 18
				glints.Size = seq(0, 0, 0.3, 1.2, 1, 0)
			end
			for _, gem in partsMatching(model, "^crown_gem") do
				wink(gem, color, 1.1, 0.7)
			end
			local core = partNamed(model, "meridian_core")
			if core then
				light(core, color, 10, 2.4)
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

		-- Toxic Twilight. The magnets' parts are turned 90 degrees off their model and
		-- the haul pose swings them about, so nothing here trusts a face to be "up":
		-- effects spray every way, or rise under a world-space Acceleration.
		["Lattice Magnet"] = function(model: Model, color: Color3)
			-- Square crystal flecks (turned 45 degrees: diamonds) flaking off the cage.
			local halo = partNamed(model, "lattice_halo")
			if halo then
				emit(halo, color, {
					Texture = SQUARE_TEXTURE,
					Brightness = 2,
					Size = seq(0, 0, 0.2, 0.4, 1, 0),
					Transparency = seq(0, 0, 1, 0.5),
					Lifetime = NumberRange.new(0.8, 1.4),
					Rate = 16,
					Speed = NumberRange.new(0.8, 1.6),
					Drag = 1.5,
					SpreadAngle = Vector2.new(180, 180),
					Rotation = NumberRange.new(45),
				})
			end
			local core = partNamed(model, "lattice_core")
			if core then
				light(core, color, 10, 2.5)
			end
		end,
		["Solar Magnet"] = function(model: Model, color: Color3)
			-- Flames licking off both pole tips and curling upward.
			for _, flame in partsMatching(model, "^pole_flame") do
				-- The sparkle texture stretched tall, not fire_main: that one has soot baked
				-- into it and, alpha-blended, every flame read as a puff of black smoke.
				emit(flame, gradient(Color3.fromHex("FFD23A"), Color3.fromHex("FF8A1E"), Color3.fromHex("E0401E")), {
					Brightness = 1.6,
					Size = seq(0, 0.9, 1, 0.25),
					Squash = seq(0, -0.8, 1, -0.8),
					Transparency = seq(0, 0, 1, 1),
					Lifetime = NumberRange.new(0.3, 0.5),
					Rate = 18,
					Speed = NumberRange.new(1.5, 2.5),
					EmissionDirection = Enum.NormalId.Top,
					SpreadAngle = Vector2.new(20, 20),
					Acceleration = Vector3.new(0, 4, 0),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-90, 90),
				})
			end
			local core = partNamed(model, "sun_core")
			if core then
				light(core, color, 12, 3)
			end
		end,
		["Void Magnet"] = function(model: Model, color: Color3)
			-- An event horizon: light falling into the core, the twin pole cores
			-- swallowing their own.
			local core = partNamed(model, "void_core")
			if core then
				collapse(core, color, 3.4, 2)
				light(core, color, 12, 3)
			end
			for _, twin in partsMatching(model, "^twin_core") do
				collapse(twin, color, 1.6, 1.2)
			end
		end,
		["Nebula Magnet"] = function(model: Model, color: Color3)
			-- A slow pink-into-blue gas cloud round the core, with stars in it. Thinned
			-- after the user's first look ("a little too loud"): half the puffs, smaller
			-- and fainter, half the stars.
			local halo = partNamed(model, "nebula_halo")
			if halo then
				emit(halo, gradient(Color3.fromHex("FF5FD2"), Color3.fromHex("9A5CFF"), Color3.fromHex("4F7BFF")), {
					Texture = SMOKE_TEXTURE,
					Brightness = 1.2,
					Size = seq(0, 0.9, 1, 2),
					Transparency = seq(0, 1, 0.3, 0.45, 1, 1),
					Lifetime = NumberRange.new(2, 3),
					Rate = 4,
					Speed = NumberRange.new(0.6, 1),
					SpreadAngle = Vector2.new(180, 180),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-30, 30),
				})
				wink(halo, WHITE, 0.5, 3)
			end
			local core = partNamed(model, "nebula_core")
			if core then
				light(core, color, 10, 2.2)
			end
		end,
		["Omega Magnet"] = function(model: Model, color: Color3)
			-- Gold discharge crackling off all eight spires, and the apex star flaring.
			-- Eight spires at 10 sparks a second was 80 a second and "a little too
			-- loud": now 3 each, smaller and shorter, and a smaller, slower star.
			for _, spire in partsMatching(model, "^arc%d_spire") do
				emit(spire, color, {
					Brightness = 4,
					Size = seq(0, 0.5, 1, 0),
					Transparency = seq(0, 0, 1, 1),
					Lifetime = NumberRange.new(0.12, 0.25),
					Rate = 3,
					Speed = NumberRange.new(3, 5),
					EmissionDirection = Enum.NormalId.Top,
					SpreadAngle = Vector2.new(45, 45),
				})
			end
			local star = partNamed(model, "apex_star")
			if star then
				wink(star, color, 1.6, 0.8)
			end
			local core = partNamed(model, "omega_core")
			if core then
				light(core, color, 10, 2.2)
			end
		end,
	},
	-- Only Twilight's five hoses: the Base Camp rungs' `glow` paints their drawn
	-- fallback nozzles and nothing more. Built on the mast of your own wash station
	-- (Plots.setHoseTier) and on the shop rack; a hose is never held.
	Cleaner = {
		["Singularity Nozzle"] = function(model: Model, color: Color3)
			-- Motes pulled into the muzzle, shrinking to nothing as they reach it.
			local barrel = barrelOf(model)
			if barrel then
				shrinkMotes(barrel, color)
				light(barrel, color, 8, 2)
			end
		end,
		["Cryo Nova"] = function(model: Model, color: Color3)
			-- Frost vapour rolling off the muzzle and sinking, as off anything that cold.
			local muzzle = muzzleOf(model)
			if muzzle then
				emit(muzzle, gradient(WHITE, color), {
					Texture = SMOKE_TEXTURE,
					Brightness = 1.4,
					Size = seq(0, 0.4, 1, 1.4),
					Transparency = seq(0, 0.35, 1, 1),
					Lifetime = NumberRange.new(1.2, 1.8),
					Rate = 8,
					Speed = NumberRange.new(0.4, 0.8),
					EmissionDirection = Enum.NormalId.Front,
					SpreadAngle = Vector2.new(25, 25),
					Acceleration = Vector3.new(0, -1.2, 0),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-30, 30),
				})
			end
			local barrel = barrelOf(model)
			if barrel then
				wink(barrel, color, 0.6, 3)
				light(barrel, color, 8, 2)
			end
		end,
		["Solar Forge"] = function(model: Model, color: Color3)
			-- A forge-hot barrel throwing embers.
			local barrel = barrelOf(model)
			if barrel then
				local e = embers(barrel, color)
				e.Rate = 10
				e.Size = seq(0, 0.45, 1, 0)
				light(barrel, color, 8, 2)
			end
		end,
		["Quantum Rift"] = function(model: Model, color: Color3)
			-- The barrel glitching: square pixels popping in and out, teal flicking to
			-- the model's pink.
			local barrel = barrelOf(model)
			if barrel then
				emit(barrel, gradient(color, Color3.fromHex("FF5FA8")), {
					Texture = SQUARE_TEXTURE,
					Brightness = 1.6,
					-- One flat size with a wide envelope: every pixel a different size.
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28, 0.14), NumberSequenceKeypoint.new(1, 0.28, 0.14) }),
					Transparency = seq(0, 0, 0.8, 0, 1, 1),
					Lifetime = NumberRange.new(0.15, 0.3),
					Rate = 22,
					Speed = NumberRange.new(0),
				})
				light(barrel, color, 8, 2)
			end
		end,
		["Celestial Deluge"] = function(model: Model, color: Color3)
			-- Stardust spilling out of the muzzle and drifting down.
			local muzzle = muzzleOf(model)
			if muzzle then
				emit(muzzle, gradient(color, WHITE), {
					Brightness = 3.5,
					Size = seq(0, 0.6, 1, 0),
					Transparency = seq(0, 0, 1, 0.5),
					Lifetime = NumberRange.new(0.8, 1.3),
					Rate = 12,
					Speed = NumberRange.new(1, 2),
					Drag = 2,
					EmissionDirection = Enum.NormalId.Front,
					SpreadAngle = Vector2.new(25, 25),
					Acceleration = Vector3.new(0, -0.6, 0),
					Rotation = NumberRange.new(0, 360),
					RotSpeed = NumberRange.new(-60, 60),
				})
			end
			local barrel = barrelOf(model)
			if barrel then
				light(barrel, color, 8, 2)
			end
		end,
	},
}

--[[
	MOVING PARTS. The top magnets' outer balls, rings and crystals turn, orbit
	and float instead of sitting welded solid. The bands wrapped round the poles
	stay put (user rule: only the outer pieces move).

	Every part of a magnet is WeldConstraint-joined to its `bend`, which cannot be
	animated. rig() swaps a chosen part's constraint for a `Weld` of the same pose,
	stamps the motion on it as attributes and tags it MOTION_TAG. That is all the
	server does; ToolMotionController moves them on each client -- the weld's C0 in
	a hand, the part's CFrame on an anchored shop rack -- recomputed from the rest
	pose every frame so nothing drifts.

	All in the BEND'S frame, where every magnet stands the same way: poles up +Y,
	cores centred on its X=0, Z=0 line. Distances are in bend heights so a motion
	reads the same on a 0.75x held magnet and a 3x one on the rack.
]]
local MOTION_TAG = "ToolMotion"

type Motion = {
	pivot: Vector3?, -- bend-space point the part turns about (default: its own centre)
	axis: Vector3?, -- bend-space axis it turns about (default: +Y)
	spin: number?, -- radians a second
	bob: number?, -- up-and-down travel along +Y, in bend heights
	hz: number?, -- bob cycles a second
	phase: number?, -- bob phase, radians
}

local function rig(bend: BasePart, part: BasePart, motion: Motion)
	-- Already rigged (a rack built before a motion was retuned): restamp the same
	-- weld. Its C0 is still the rest pose -- only clients ever move it.
	local weld = part:FindFirstChild(MOTION_TAG)
	local old: WeldConstraint? = nil
	if not (weld and weld:IsA("Weld") and weld.Part0 == bend) then
		weld = nil
		for _, j in bend:GetChildren() do
			if j:IsA("WeldConstraint") and (j.Part1 == part or j.Part0 == part) then
				old = j
				break
			end
		end
		if old == nil then
			return
		end
		local fresh = Instance.new("Weld")
		fresh.Name = MOTION_TAG
		fresh.Part0 = bend
		fresh.Part1 = part
		fresh.C0 = bend.CFrame:ToObjectSpace(part.CFrame)
		weld = fresh
	end
	assert(weld and weld:IsA("Weld"), "ToolFX.rig: no weld")
	weld:SetAttribute("Pivot", motion.pivot or weld.C0.Position)
	weld:SetAttribute("Axis", (motion.axis or Vector3.yAxis).Unit)
	weld:SetAttribute("Spin", motion.spin or 0)
	weld:SetAttribute("Bob", (motion.bob or 0) * bend.Size.Y)
	weld:SetAttribute("Hz", motion.hz or 0.5)
	weld:SetAttribute("Phase", motion.phase or 0)
	weld:AddTag(MOTION_TAG)
	weld.Parent = part
	if old then
		old:Destroy()
	end
end

--- Where `part` sits in the bend's frame.
local function at(bend: BasePart, part: BasePart?): Vector3?
	return if part then bend.CFrame:PointToObjectSpace(part.Position) else nil
end

--- Parts carried round `centre` as one rigid wheel.
local function orbit(bend: BasePart, parts: { BasePart }, centre: BasePart?, spin: number, axis: Vector3?)
	local pivot = at(bend, centre)
	if pivot == nil then
		return
	end
	for _, part in parts do
		rig(bend, part, { pivot = pivot, axis = axis, spin = spin })
	end
end

local function spinAll(bend: BasePart, parts: { BasePart }, motion: Motion)
	for _, part in parts do
		rig(bend, part, motion)
	end
end

local function one(model: Model, name: string): { BasePart }
	local part = partNamed(model, name)
	return if part then { part } else {}
end

--- Every part matching any of `patterns`, as one list.
local function gather(model: Model, patterns: { string }): { BasePart }
	local found = {}
	for _, pattern in patterns do
		for _, part in partsMatching(model, pattern) do
			table.insert(found, part)
		end
	end
	return found
end

local TILT = Vector3.new(1, 1, 0)
local TILT_BACK = Vector3.new(-1, 1, 1)

-- Magnet tier NAME -> rig(model, bend). Same keying as SPECS.
local MOTION: { [string]: (Model, BasePart) -> () } = {
	["Singularity Coil"] = function(model: Model, bend: BasePart)
		local core = partNamed(model, "singularity_core")
		local c = at(bend, core)
		-- A gyroscope: three rings round the core, each tumbling on its own axis.
		spinAll(bend, one(model, "gyro_ring_a"), { pivot = c, axis = Vector3.xAxis, spin = 1.6 })
		spinAll(bend, one(model, "gyro_ring_b"), { pivot = c, axis = Vector3.zAxis, spin = -1.2 })
		spinAll(bend, one(model, "gyro_ring_c"), { pivot = c, axis = Vector3.yAxis, spin = 0.9 })
		spinAll(bend, one(model, "core_halo"), { axis = TILT, spin = 0.8 })
		spinAll(bend, one(model, "singularity_core"), { spin = -0.6 })
		-- The big ring and its six balls wheel round the waist.
		local halo = partNamed(model, "halo_ring")
		local wheel = partsMatching(model, "^halo_node_")
		if halo then
			table.insert(wheel, halo)
		end
		orbit(bend, wheel, halo, 0.7)
	end,
	["Lattice Magnet"] = function(model: Model, bend: BasePart)
		local core = partNamed(model, "lattice_core")
		-- The big crystal ball and its cage float as one (a spin alone is invisible on
		-- a sphere), and the six diamonds circling it ride along.
		local float = { bob = 0.25, hz = 0.35 }
		local c = at(bend, core)
		for _, shard in partsMatching(model, "^lattice_shard_") do
			rig(bend, shard, { pivot = c, spin = 1.1, bob = float.bob, hz = float.hz })
		end
		spinAll(bend, one(model, "lattice_halo"), { axis = TILT, spin = 0.6, bob = float.bob, hz = float.hz })
		spinAll(bend, one(model, "lattice_core"), { spin = -0.8, bob = float.bob, hz = float.hz })
		for i, side in { "l", "r" } do
			local lift = { bob = 0.04, hz = 0.45, phase = i * math.pi }
			spinAll(bend, one(model, `float_pole_{side}`), lift)
			spinAll(bend, one(model, `pole_gem_{side}`), { spin = 1.5, bob = lift.bob, hz = lift.hz, phase = lift.phase })
		end
	end,
	["Solar Magnet"] = function(model: Model, bend: BasePart)
		local sun = partNamed(model, "sun_core")
		orbit(bend, partsMatching(model, "^corona_"), sun, 0.8)
		spinAll(bend, one(model, "flare_ring_a"), { pivot = at(bend, sun), spin = 1.2 })
		spinAll(bend, one(model, "flare_ring_b"), { pivot = at(bend, sun), spin = -1.2 })
		spinAll(bend, one(model, "sun_halo"), { axis = TILT, spin = 0.5 })
	end,
	["Void Magnet"] = function(model: Model, bend: BasePart)
		-- The big ball floats, carrying its halo and event rings with it.
		local float = { bob = 0.25, hz = 0.35 }
		spinAll(bend, one(model, "void_core"), float)
		spinAll(bend, one(model, "event_ring"), { spin = 1.4, bob = float.bob, hz = float.hz })
		spinAll(bend, one(model, "event_rim"), { spin = -0.9, bob = float.bob, hz = float.hz })
		spinAll(bend, one(model, "void_halo"), { axis = TILT_BACK, spin = 0.7, bob = float.bob, hz = float.hz })
		for i, side in { "l", "r" } do
			spinAll(bend, one(model, `twin_core_{side}`), { axis = TILT, spin = 1.2, bob = 0.08, hz = 0.5, phase = i * math.pi })
		end
	end,
	["Nebula Magnet"] = function(model: Model, bend: BasePart)
		-- The crown and its six diamond stars turn slowly overhead.
		local crown = partNamed(model, "crown_halo")
		local wheel = partsMatching(model, "^halo_star_")
		if crown then
			table.insert(wheel, crown)
		end
		orbit(bend, wheel, crown, 0.6)
		local c = at(bend, partNamed(model, "nebula_core"))
		spinAll(bend, one(model, "field_line_1"), { pivot = c, spin = 0.9 })
		spinAll(bend, one(model, "field_line_2"), { pivot = c, spin = -0.7 })
		spinAll(bend, one(model, "field_line_3"), { pivot = c, spin = 0.5 })
		spinAll(bend, one(model, "nebula_halo"), { axis = TILT, spin = 0.5 })
		for arm = 1, 3 do
			for i, side in { "l", "r" } do
				spinAll(bend, one(model, `arm{arm}_tip_{side}`), { spin = 1.3, bob = 0.04, hz = 0.5, phase = arm * 2.1 + i * math.pi })
			end
		end
	end,
	["Omega Magnet"] = function(model: Model, bend: BasePart)
		local c = at(bend, partNamed(model, "omega_core"))
		spinAll(bend, one(model, "gyro_1"), { pivot = c, axis = Vector3.xAxis, spin = 1.5 })
		spinAll(bend, one(model, "gyro_2"), { pivot = c, axis = Vector3.yAxis, spin = -1.2 })
		spinAll(bend, one(model, "gyro_3"), { pivot = c, axis = Vector3.zAxis, spin = 1.0 })
		spinAll(bend, one(model, "gyro_4"), { pivot = c, axis = TILT, spin = -0.8 })
		spinAll(bend, one(model, "omega_halo"), { axis = TILT_BACK, spin = 0.6 })
		-- Three stacked halos and their shards, counter-rotating.
		for n, spin in { 0.6, -0.8, 1.0 } do
			local halo = partNamed(model, `halo_{n}`)
			local wheel = partsMatching(model, `^halo{n}_shard_`)
			if halo then
				table.insert(wheel, halo)
			end
			orbit(bend, wheel, halo, spin)
		end
		spinAll(bend, one(model, "apex_star"), { spin = 1.5, bob = 0.05, hz = 0.5 })
	end,
}

--[[
	The Twilight detectors (Aurora Rake..Prime Meridian). Every part is welded to
	`upper_shaft`, which stands axis-aligned with the model: +Y is up and each
	head lies flat in the XZ plane. So the same rig() applies with `upper_shaft`
	as the anchor, and distances are in shaft heights instead. The shaft, box,
	arm and grip never move -- only the head's outer pieces.
]]
local DETECTOR_MOTION: { [string]: (Model, BasePart) -> () } = {
	["Aurora Rake"] = function(model: Model, shaft: BasePart)
		-- The comb pumps: tines, their tips and the ribbon strung between the tips
		-- plunge together through the still collars, raking the ground.
		spinAll(shaft, gather(model, { "^tine%d+$", "^tine_tip%d+$", "^aurora_ribbon$" }), { bob = 0.06, hz = 0.6 })
		-- The eye turns and rides up and down the neck.
		spinAll(shaft, one(model, "aurora_eye"), { spin = 1.2, bob = 0.03, hz = 0.35 })
		-- The five fins over the bar spin like radar vanes, out of step.
		for i, fin in partsMatching(model, "^bar_fin%d+$") do
			rig(shaft, fin, { spin = if i % 2 == 0 then -3 else 3 })
		end
	end,
	["Strata Lance"] = function(model: Model, shaft: BasePart)
		local core = partNamed(model, "molten_core")
		-- The outer drill wheel -- rim, spokes and the six heat claws -- grinds round,
		-- the inner ring and its cooling fins counter-turning inside it.
		orbit(shaft, gather(model, { "^coil_rim$", "^coil_spoke%d+$", "^rim_glow$", "^heat_claw%d+$", "^claw_glow%d+$" }), core, 0.9)
		orbit(shaft, gather(model, { "^inner_ring$", "^core_lip$", "^cool_fin%d+$" }), core, -1.4)
		spinAll(shaft, one(model, "molten_core"), { spin = 2 })
		-- The three exhaust stacks pump like pistons, one after another.
		for i = 1, 3 do
			spinAll(shaft, gather(model, { `^exhaust_stack{i}$`, `^stack_glow{i}$`, `^stack_band{i}$` }), { bob = 0.05, hz = 1.2, phase = i * 2.1 })
		end
	end,
	["Leyline Tap"] = function(model: Model, shaft: BasePart)
		local core = partNamed(model, "ley_core")
		local c = at(shaft, core)
		-- The outer halo wheels round with its rune nodes, carrying the four crystals
		-- on its rim; each crystal also rises and settles in its socket in turn.
		orbit(shaft, gather(model, { "^halo_outer$", "^halo_spoke%d+$", "^rune_node%d+$", "^crystal_socket%d+$" }), core, 0.6)
		for i = 1, 4 do
			spinAll(shaft, one(model, `ley_crystal{i}`), { pivot = c, spin = 0.6, bob = 0.04, hz = 0.5, phase = i * math.pi / 2 })
		end
		-- The inner halo counter-turns; the core floats and turns inside it.
		orbit(shaft, gather(model, { "^halo_inner$", "^inner_spoke%d+$" }), core, -1)
		spinAll(shaft, one(model, "ley_core"), { spin = 1.2, bob = 0.04, hz = 0.4 })
		spinAll(shaft, one(model, "keystone_ring"), { spin = 1.5 })
	end,
	["Null Compass"] = function(model: Model, shaft: BasePart)
		local sphere = partNamed(model, "void_sphere")
		local c = at(shaft, sphere)
		-- A compass gyro: the big ring and its spokes tumble end over end round the
		-- void, the meridian disc swings round it, the band rolls the other way.
		orbit(shaft, gather(model, { "^null_ring$", "^null_spoke%d+$" }), sphere, 0.8, Vector3.xAxis)
		spinAll(shaft, one(model, "void_meridian"), { pivot = c, spin = 1.2 })
		spinAll(shaft, one(model, "void_band"), { pivot = c, axis = Vector3.zAxis, spin = -1 })
		-- The five shards circle on their tethers.
		orbit(shaft, gather(model, { "^orbit_shard%d+$", "^shard_tether%d+$" }), sphere, 0.9)
		spinAll(shaft, one(model, "singularity"), { axis = TILT, spin = 2.5 })
	end,
	["Prime Meridian"] = function(model: Model, shaft: BasePart)
		local core = partNamed(model, "meridian_core")
		local c = at(shaft, core)
		-- The crown -- gold halo, spokes, nine points, three gems on their posts --
		-- turns slowly, the gems bobbing on their posts as it goes.
		orbit(shaft, gather(model, { "^gold_halo$", "^crown_spoke%d+$", "^crown_point%d+$", "^gem_post%d+$", "^gem_setting%d+$" }), core, 0.5)
		for i = 1, 3 do
			spinAll(shaft, one(model, `crown_gem{i}`), { pivot = c, spin = 0.5, bob = 0.03, hz = 0.6, phase = i * 2.1 })
		end
		-- The filigree ring and its inlays drift the other way underneath.
		orbit(shaft, gather(model, { "^filigree_ring$", "^filigree_post%d+$", "^inlay%d+$" }), core, -0.4)
		-- Inside: an armillary. The orbit ring tumbles, the meridian ring rolls
		-- across it, and the twelve sun rays wheel fast round the core.
		orbit(shaft, gather(model, { "^orbit_ring$", "^orbit_spoke%d+$" }), core, 1, Vector3.xAxis)
		spinAll(shaft, one(model, "meridian_ring"), { pivot = c, axis = Vector3.zAxis, spin = -1.4 })
		orbit(shaft, partsMatching(model, "^sun_ray%d+$"), core, 1.6)
		spinAll(shaft, one(model, "meridian_core"), { spin = 0.8 })
	end,
}

-- Track -> { tier name -> rig }, and the part every other part is welded to.
local MOTION_BY_TRACK: { [string]: { [string]: (Model, BasePart) -> () } } = {
	Magnet = MOTION,
	Detector = DETECTOR_MOTION,
}
local MOTION_ANCHOR: { [string]: string } = {
	Magnet = "bend",
	Detector = "upper_shaft",
}

local function scaleSequence(s: NumberSequence, k: number): NumberSequence
	local points = {}
	for _, p in s.Keypoints do
		table.insert(points, NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k))
	end
	return NumberSequence.new(points)
end

--- Rigs this tier's moving parts (MOTION above) on an already-cloned tool model.
--- Part of apply(); on its own it re-rigs a model built before MOTION existed
--- without doubling its particles. Re-runnable: a part already rigged keeps its
--- weld and takes the current motion.
function ToolFX.animate(model: Model, track: string, tier: number)
	local byName = MOTION_BY_TRACK[track]
	local moves = if byName then byName[ToolTiers.get(track, tier).name] else nil
	local bend = if moves then partNamed(model, MOTION_ANCHOR[track]) else nil
	if moves == nil or bend == nil then
		return
	end
	-- Still anything rigged by an older MOTION (a rack built before a retune); the
	-- current one restamps what should move.
	for _, d in model:GetDescendants() do
		if d:IsA("Weld") and d.Name == MOTION_TAG then
			d:SetAttribute("Spin", 0)
			d:SetAttribute("Bob", 0)
		end
	end
	moves(model, bend)
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
	ToolFX.animate(model, track, tier)
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
