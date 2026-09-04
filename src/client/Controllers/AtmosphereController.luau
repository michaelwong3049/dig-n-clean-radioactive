--!strict
--[[
	AtmosphereController.luau — the air, and now the SKY, change as you walk deeper.

	Lighting is global, but which stage a player is standing in is personal, so this
	has to be a client concern. ExposureState already carries `stageId` every tick
	(ExposureService), so this costs no new remote and no new server work — it is
	pure presentation reading a field that was already on the wire.

	WHY THIS EARNS ITS PLACE: Config/Stages has carried fogColor and fogEnd since the
	first commit and NOTHING has ever read them. Six stages' worth of art direction
	was sitting in the config doing nothing. Wiring it is about forty lines and it is
	the difference between four green rectangles and four places.

	The gradient runs bright-and-open at base camp to close-and-toxic at the Belt:
	fogEnd 900 -> 600 as you go deeper, so the deep stages literally close in around
	you. That is the cheapest possible way to make distance feel dangerous, and it
	reinforces the one rule the whole map teaches — the paths are safe, the green is
	not.

	Tweened, never snapped. A hard cut on a stage boundary reads as a bug; a
	half-second fade reads as walking into different air.

	── THE SKY (Config/Sky) ──────────────────────────────────────────────────────
	Fog only ever told you about the middle distance. Look UP in any stage and until
	now you got the same stock blue day everywhere, which quietly undid the work the
	fog was doing — a poisoned field under a holiday sky reads as a bug, not as a
	wasteland. build/Daylight cleared the skybox faces so the sky is procedural, and
	procedural means the sky is just Atmosphere plus the sun, which is to say: five
	properties, a cloud deck, and four lighting values, all of them tweenable.

	So this controller now drives FIVE instances instead of one, and there is nothing
	clever about it — same trigger, same tween, more targets:

	    Lighting          fog, brightness, ambient tint, clock time
	    Atmosphere        the sky's own colour, its density and haze
	    Terrain.Clouds    the deck overhead: colour, cover, thickness
	    SunRaysEffect     shafts through the muck, stronger the worse it gets
	    Sky               the sun swelling as you go east

	THE SKY FADES SLOWER THAN THE FOG, deliberately. Fog is a middle-distance cue and
	wants to keep up with you (0.6s, unchanged). The sky is a backdrop; at the same
	speed a whole hemisphere changing colour in half a second reads as a light switch
	rather than as weather, so it takes SKY_TWEEN's 1.8s. Crossing a boundary and
	stepping straight back cancels both, so the slower fade costs nothing but a
	prettier transition.

	EVERY LOOKUP IS DEFENSIVE. Atmosphere, Clouds, SunRays and Sky are all created by
	build/Daylight on the server and replicated down, so on a cold join this can
	genuinely run before they exist. A missing instance is skipped, not waited on —
	the next stage change (or the next respawn) picks it up, and a player who never
	changes stage was already looking at the right base look anyway.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local SkyConfig = require(Shared.Config.Sky)
local Net = require(Shared.Net)

local AtmosphereController = {}

-- Base camp air. Matches build/Daylight's BASE_FOG_*, which is the server-side
-- half of this look; if you change one, change the other. (The sky half of base
-- camp does NOT need copying out like this — Config/Sky.BASE is shared code that
-- both this file and build/Daylight read, which is what the fog should eventually
-- become too.)
local BASE = {
	fogColor = Color3.fromHex("CFF3FF"),
	fogEnd = 900,
	fogStart = 120,
}

local AIR_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SKY_TWEEN = TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local currentStage: number? = -1 -- -1 so the first update always applies
local activeTweens: { Tween } = {}

--- Fog for a stage. Unchanged behaviour — pulled out of applyFor only because that
--- function now has a second, larger job.
local function fogFor(stageId: number?)
	if stageId == nil then
		return BASE
	end
	local ok, def = pcall(Stages.get, stageId)
	if not ok or not def then
		return BASE
	end
	return {
		fogColor = def.fogColor,
		fogEnd = def.fogEnd,
		-- Deep stages close in: start the fog proportionally nearer so the band
		-- between "clear" and "gone" stays readable at every depth.
		fogStart = math.max(40, def.fogEnd * 0.13),
	}
end

local function tween(instance: Instance?, info: TweenInfo, goal: { [string]: any })
	if instance == nil then
		return
	end
	local created = TweenService:Create(instance, info, goal)
	table.insert(activeTweens, created)
	created:Play()
end

local function applyFor(stageId: number?)
	if stageId == currentStage then
		return
	end
	currentStage = stageId

	local fog = fogFor(stageId)
	local sky = SkyConfig.get(stageId)

	for _, active in activeTweens do
		active:Cancel()
	end
	table.clear(activeTweens)

	-- Fog keeps its own faster curve; everything above the horizon takes the slow
	-- one. Brightness/ambient/clock ride with the SKY rather than the fog because
	-- they are what the sky is lighting, and splitting them looks like a flicker.
	tween(Lighting, AIR_TWEEN, {
		FogColor = fog.fogColor,
		FogEnd = fog.fogEnd,
		FogStart = fog.fogStart,
	})
	tween(Lighting, SKY_TWEEN, {
		Brightness = sky.brightness,
		OutdoorAmbient = sky.outdoorAmbient,
		ColorShift_Top = sky.colorShiftTop,
		ClockTime = sky.clockTime,
	})
	tween(Lighting:FindFirstChildOfClass("Atmosphere"), SKY_TWEEN, {
		Color = sky.atmoColor,
		Decay = sky.atmoDecay,
		Density = sky.atmoDensity,
		Glare = sky.atmoGlare,
		Haze = sky.atmoHaze,
	})
	tween(Workspace.Terrain:FindFirstChildOfClass("Clouds"), SKY_TWEEN, {
		Color = sky.cloudColor,
		Cover = sky.cloudCover,
		Density = sky.cloudDensity,
	})
	tween(Lighting:FindFirstChildOfClass("SunRaysEffect"), SKY_TWEEN, {
		Intensity = sky.sunRays,
	})
	tween(Lighting:FindFirstChildOfClass("Sky"), SKY_TWEEN, {
		SunAngularSize = sky.sunSize,
	})
end

function AtmosphereController.init()
	Lighting.FogColor = BASE.fogColor
	Lighting.FogEnd = BASE.fogEnd
	Lighting.FogStart = BASE.fogStart
end

function AtmosphereController.start()
	Net.get("ExposureState").OnClientEvent:Connect(function(state)
		applyFor(state.stageId)
	end)

	-- Respawning does not re-fire ExposureState immediately, and waking up at base
	-- camp still tinted like the Exclusion Belt looks broken.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		currentStage = -1
		applyFor(nil)
	end)
end

return AtmosphereController
