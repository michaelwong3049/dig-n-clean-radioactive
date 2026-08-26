--!strict
--[[
	Daylight.luau — the Lighting setup, as code.

	    require(game.ServerScriptService.Server.build.Daylight).apply()

	WHY THIS IS A FILE AND NOT A STUDIO SETTING.
	Lighting properties live in the place file, which is gitignored — exactly the
	problem this whole build/ folder exists to solve. A world that only looks right
	because somebody once dragged sliders in Studio is a world that looks wrong the
	next time anyone opens a fresh clone. So the look is written down and applied.

	THE ART DIRECTION THIS IMPLEMENTS (PLAN §14, as rewritten):

	    Saturated everywhere. Radiation is the only thing that GLOWS.

	The original §14 asked for desaturated ash-grey with radiation as the only
	saturated colour. That is a good rule for a survival horror game and the wrong
	one for this audience. But the INSIGHT under it is worth keeping — one visual
	channel means danger, so the eye trains itself without being taught. This moves
	the channel from saturation to emission: the world is bright and colourful, and
	the only things that glow acid green are the things that will hurt you.

	Concretely that means: a high sun, warm ambient, thin atmosphere so the map reads
	as open rather than foggy, and just enough bloom that Neon ooze blooms while
	painted timber does not. Depth of field is pushed out to nothing — blurring the
	horizon in a game whose whole tension is "how far away is home" actively fights
	the design.
]]

local Lighting = game:GetService("Lighting")

local Daylight = {}
local BUILDER_SOURCE = "src/server/build/Daylight.luau"
local BUILDER_VERSION = 1

--- Base fog. Per-stage fog is a CLIENT concern (Lighting is global, but each player
--- should see their own stage's air), so AtmosphereController tweens from here.
--- These values are the base camp look.
Daylight.BASE_FOG_COLOR = Color3.fromHex("CFF3FF")
Daylight.BASE_FOG_END = 900
Daylight.BASE_FOG_START = 120

local function child<T>(className: string, name: string): T
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	if existing then
		existing:Destroy()
	end
	local created = Instance.new(className) :: any
	created.Name = name
	created.Parent = Lighting
	return created
end

function Daylight.apply()
	-- A high, bright, slightly-past-noon sun. Long enough shadows to give the
	-- geometry shape, short enough that nothing important sits in the dark.
	Lighting.ClockTime = 13.6
	Lighting.GeographicLatitude = 12
	-- Brightness past ~2.5 blows the ground out to near-white and takes the colour
	-- with it, which is the opposite of the goal. Sunny, not overexposed.
	Lighting.Brightness = 2.4
	Lighting.ExposureCompensation = -0.05

	-- Ambient is where "colourful" is actually won or lost. Default grey ambient
	-- desaturates every surface in the world; a warm-mint ambient lets the plaza
	-- read as sunny and the grass as green rather than as grey-green.
	Lighting.Ambient = Color3.fromHex("6E7A72")
	Lighting.OutdoorAmbient = Color3.fromHex("7E9488")
	Lighting.ColorShift_Top = Color3.fromHex("FFF3D6")
	Lighting.ColorShift_Bottom = Color3.fromHex("BFE0C8")

	Lighting.FogColor = Daylight.BASE_FOG_COLOR
	Lighting.FogStart = Daylight.BASE_FOG_START
	Lighting.FogEnd = Daylight.BASE_FOG_END

	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.35

	-- Thin air. The default Atmosphere is what was making the map read as a grey
	-- haze — density down, and the glare/haze kept low so distance stays legible.
	local atmosphere = child("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromHex("E6F7E0")
	atmosphere.Decay = Color3.fromHex("9FD8B0")
	atmosphere.Glare = 0.15
	atmosphere.Haze = 0.6

	-- Bloom tuned so Neon blooms and paint does not. Threshold is the important
	-- number: drop it and the whole bright plaza starts glowing, which destroys
	-- the "only radiation glows" rule this palette is built on.
	local bloom = child("BloomEffect", "Bloom") :: BloomEffect
	bloom.Enabled = true
	bloom.Intensity = 0.55
	bloom.Size = 20
	bloom.Threshold = 1.15

	-- Gentle saturation lift. Does the "colourful" work globally without needing
	-- every part's colour retuned by hand.
	local grade = child("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	grade.Enabled = true
	grade.Saturation = 0.26
	grade.Contrast = 0.06
	grade.Brightness = 0.01
	grade.TintColor = Color3.fromHex("FFFDF6")

	-- Depth of field OFF. This game's tension is "how far away is base camp"; a
	-- blurred horizon fights that directly.
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		dof.Enabled = false
	end

	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays.Enabled = true
		rays.Intensity = 0.08
		rays.Spread = 0.9
	end

	local sky = child("Sky", "Sky") :: Sky
	sky.SunAngularSize = 12
	sky.MoonAngularSize = 8
	sky.StarCount = 0

	Lighting:SetAttribute("GeneratedBy", BUILDER_SOURCE)
	Lighting:SetAttribute("BuilderVersion", BUILDER_VERSION)

	print("[build] Daylight applied — bright outdoor, thin atmosphere, bloom gated to Neon")
end

return Daylight
