--!strict
--[[
	AtmosphereController.luau — the air changes colour as you walk deeper.

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
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Net = require(Shared.Net)

local AtmosphereController = {}

-- Base camp air. Matches build/Daylight's BASE_FOG_*, which is the server-side
-- half of this look; if you change one, change the other.
local BASE = {
	fogColor = Color3.fromHex("CFF3FF"),
	fogEnd = 900,
	fogStart = 120,
}

local TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local currentStage: number? = -1 -- -1 so the first update always applies
local activeTween: Tween? = nil

local function applyFor(stageId: number?)
	if stageId == currentStage then
		return
	end
	currentStage = stageId

	local target = BASE
	if stageId ~= nil then
		local ok, def = pcall(Stages.get, stageId)
		if ok and def then
			target = {
				fogColor = def.fogColor,
				fogEnd = def.fogEnd,
				-- Deep stages close in: start the fog proportionally nearer so the
				-- band between "clear" and "gone" stays readable at every depth.
				fogStart = math.max(40, def.fogEnd * 0.13),
			}
		end
	end

	if activeTween then
		activeTween:Cancel()
	end
	activeTween = TweenService:Create(Lighting, TWEEN, {
		FogColor = target.fogColor,
		FogEnd = target.fogEnd,
		FogStart = target.fogStart,
	})
	;(activeTween :: Tween):Play()
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
