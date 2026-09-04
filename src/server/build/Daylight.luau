--!strict
--[[
	Daylight.luau — the Lighting setup, as code.

	    require(game.ServerScriptService.Server.build.Daylight).apply()

	WHY THIS IS A FILE AND NOT A STUDIO SETTING.
	Lighting properties live in the place file, which is gitignored — exactly the
	problem this whole build/ folder exists to solve. A world that only looks right
	because somebody once dragged sliders in Studio is a world that looks wrong the
	next time anyone opens a fresh clone. So the look is written down and applied.

	THE ART DIRECTION THIS IMPLEMENTS (PLAN §14, as rewritten twice):

	    Bright and colourful. Everything is matte. Colour alone carries meaning.

	The original §14 asked for desaturated ash-grey with radiation as the only
	saturated colour — right for survival horror, wrong for this audience. The second
	pass kept the "one channel means danger" insight and moved it to emission: the
	world glowed acid green where it was dangerous and nowhere else. That was undone
	on request — every Neon surface in the game is matte now, and bloom is off. The
	danger cue is back to colour and shape: the ooze is still green, the hazard tape
	is still yellow-and-black, they just don't light up.

	Concretely that means: a high sun, warm ambient, thin atmosphere so the map reads
	as open rather than foggy, no bloom. Depth of field is pushed out to nothing —
	blurring the horizon in a game whose whole tension is "how far away is home"
	actively fights the design.

	THE SKY ITSELF IS NOW WRITTEN DOWN TOO (v3). This file used to create a `Sky` and
	set three properties on it while leaving the six SKYBOX FACES alone — so the
	actual sky was whatever the gitignored place file happened to carry, which turned
	out to be `rbxassetid://6444884337`, Roblox's stock blue day. Precisely the thing
	the header above objects to, hiding inside the file that objects to it. apply()
	now clears all six faces, which drops the renderer onto its procedural sky: a sky
	made of Atmosphere and sun properties, all of which live in Config/Sky.luau and
	all of which the client can tween per stage (Client/AtmosphereController). It
	also creates the Terrain.Clouds deck that the per-stage look needs and the place
	did not have at all.

	Everything this function writes into Lighting is Config/Sky's BASE row — base
	camp, a normal bright day. The stages are the client's business.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local SkyConfig = require(Shared.Config.Sky)

local Daylight = {}
local BUILDER_SOURCE = "src/server/build/Daylight.luau"
local BUILDER_VERSION = 3

--- Base fog. Per-stage fog is a CLIENT concern (Lighting is global, but each player
--- should see their own stage's air), so AtmosphereController tweens from here.
--- These values are the base camp look.
Daylight.BASE_FOG_COLOR = Color3.fromHex("CFF3FF")
Daylight.BASE_FOG_END = 900
Daylight.BASE_FOG_START = 120

local function childOf<T>(parent: Instance, className: string, name: string): T
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing :: any
	end
	if existing then
		existing:Destroy()
	end
	local created = Instance.new(className) :: any
	created.Name = name
	created.Parent = parent
	return created
end

local function child<T>(className: string, name: string): T
	return childOf(Lighting, className, name)
end

function Daylight.apply()
	local base = SkyConfig.BASE

	-- A high, bright, slightly-past-noon sun. Long enough shadows to give the
	-- geometry shape, short enough that nothing important sits in the dark. The
	-- per-stage looks walk this later and lower as you go east (Config/Sky).
	Lighting.ClockTime = base.clockTime
	Lighting.GeographicLatitude = 12
	-- Brightness past ~2.5 blows the ground out to near-white and takes the colour
	-- with it, which is the opposite of the goal. Sunny, not overexposed.
	Lighting.Brightness = base.brightness
	Lighting.ExposureCompensation = -0.05

	-- Ambient is where "colourful" is actually won or lost. Default grey ambient
	-- desaturates every surface in the world; a warm-mint ambient lets the plaza
	-- read as sunny and the grass as green rather than as grey-green.
	Lighting.Ambient = Color3.fromHex("6E7A72")
	Lighting.OutdoorAmbient = base.outdoorAmbient
	Lighting.ColorShift_Top = base.colorShiftTop
	Lighting.ColorShift_Bottom = Color3.fromHex("BFE0C8")

	Lighting.FogColor = Daylight.BASE_FOG_COLOR
	Lighting.FogStart = Daylight.BASE_FOG_START
	Lighting.FogEnd = Daylight.BASE_FOG_END

	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.35

	-- Thin air. The default Atmosphere is what was making the map read as a grey
	-- haze — density down, and the glare/haze kept low so distance stays legible.
	-- With no skybox texture (below) these four are also the SKY, which is why they
	-- come from Config/Sky rather than being spelled out here: the client tweens the
	-- same four per stage and the two halves must not drift.
	local atmosphere = child("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = base.atmoDensity
	atmosphere.Offset = 0.1
	atmosphere.Color = base.atmoColor
	atmosphere.Decay = base.atmoDecay
	atmosphere.Glare = base.atmoGlare
	atmosphere.Haze = base.atmoHaze

	-- Bloom OFF. It existed to make Neon ooze glow while painted timber did not;
	-- nothing in the world is Neon or emissive any more (de-neon pass), so there is
	-- nothing left for it to bloom. Kept as a disabled child rather than deleted so a
	-- fresh apply() still clears any bloom a place file was saved with.
	local bloom = child("BloomEffect", "Bloom") :: BloomEffect
	bloom.Enabled = false
	bloom.Intensity = 0
	bloom.Size = 20
	bloom.Threshold = 2

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

	-- God rays. Nearly off at camp; the per-stage looks push this up as the haze
	-- thickens, so the deep stages get visible shafts through the muck.
	local rays = child("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Enabled = true
	rays.Intensity = base.sunRays
	rays.Spread = 0.9

	local sky = child("Sky", "Sky") :: Sky
	sky.SunAngularSize = base.sunSize
	sky.MoonAngularSize = 8
	sky.StarCount = 0
	-- THE SIX FACES ARE CLEARED ON PURPOSE — see this file's header. An empty face
	-- set makes Roblox render its own procedural sky, which is the only kind of sky
	-- Atmosphere can actually recolour and the only kind that can cross-fade between
	-- stages. Written every apply() so a place file saved with a skybox loses it.
	sky.SkyboxBk = ""
	sky.SkyboxDn = ""
	sky.SkyboxFt = ""
	sky.SkyboxLf = ""
	sky.SkyboxRt = ""
	sky.SkyboxUp = ""
	sky.CelestialBodiesShown = true

	-- The cloud deck. Terrain.Clouds is the only sky SCENERY the engine gives you
	-- for free — real geometry that moves, not a gradient — and the place had none.
	-- Camp gets a thin scatter of white; Config/Sky thickens and poisons it stage by
	-- stage until the Crater is under an amber lid.
	local clouds = childOf(Workspace.Terrain, "Clouds", "Clouds") :: Clouds
	clouds.Enabled = true
	clouds.Color = base.cloudColor
	clouds.Cover = base.cloudCover
	clouds.Density = base.cloudDensity

	Lighting:SetAttribute("GeneratedBy", BUILDER_SOURCE)
	Lighting:SetAttribute("BuilderVersion", BUILDER_VERSION)

	print("[build] Daylight applied — procedural sky, cloud deck, thin atmosphere, no bloom (matte world)")
end

return Daylight
