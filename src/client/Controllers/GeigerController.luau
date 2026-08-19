--[[
	GeigerController.lua — the click bed.

	PLAN §10.7 asks for sound to be the PRIMARY feedback channel, not decoration: a
	skilled player should be able to sweep with their eyes half shut. This is the layer
	that makes that possible for exposure specifically — a background tick whose rate
	climbs with the meter, so you know you are getting hot without ever looking at it.

	It reads HudController's copy of the exposure fraction rather than subscribing to
	ExposureState separately, so the picture and the sound can never drift apart. One
	subscriber, one truth.

	PLACEHOLDER AUDIO: this reuses Roblox's built-in ping at low volume and varying
	pitch. It is the right BEHAVIOUR with the wrong sample — PLAN §14 wants six distinct
	layers of clicking, and that needs authored audio.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local Geiger = {}

-- Below the warn threshold the world is quiet. Silence is the reward for clean play.
local SILENT_BELOW = Tuning.EXPOSURE_WARN * 0.5

local INTERVAL_CALM = 1.6
local INTERVAL_HOT = 0.055
local PITCH_CALM = 0.65
local PITCH_HOT = 1.45
local VOLUME_CALM = 0.10
local VOLUME_HOT = 0.34

local HudController = nil
local sound: Sound? = nil
local clock = 0

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Geiger.start()
	local player = Players.LocalPlayer
	local parent = player:WaitForChild("PlayerGui")

	-- Sibling controller, required lazily so load order between the two never matters.
	HudController = require(script.Parent.HudController)

	sound = Instance.new("Sound")
	sound.Name = "GeigerBed"
	sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	sound.Volume = VOLUME_CALM
	sound.Parent = parent

	RunService.Heartbeat:Connect(function(dt)
		if sound == nil then
			return
		end

		local frac = HudController.exposureFraction()
		if frac < SILENT_BELOW then
			clock = 0
			return
		end

		-- Normalise the audible band so the ramp spans the whole range the player
		-- can hear, rather than crushing everything into the top 20%.
		local t = math.clamp((frac - SILENT_BELOW) / (1 - SILENT_BELOW), 0, 1)

		clock -= dt
		if clock > 0 then
			return
		end

		-- Slight jitter: a perfectly metronomic tick reads as a UI beep, not a
		-- geiger counter. Real ones are stochastic.
		clock = lerp(INTERVAL_CALM, INTERVAL_HOT, t) * (0.85 + math.random() * 0.3)
		sound.PlaybackSpeed = lerp(PITCH_CALM, PITCH_HOT, t)
		sound.Volume = lerp(VOLUME_CALM, VOLUME_HOT, t)
		sound:Play()
	end)
end

return Geiger
