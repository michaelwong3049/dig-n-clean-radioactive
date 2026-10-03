--!strict
--[[
	MusicController.luau — the background playlist.

	One 2D Sound in SoundService, heard only by you, that walks a shuffled list of
	tracks and reshuffles when it runs out. It joins Sfx's "music" group, so the
	Settings mute and master volume quieten it with everything else.

	Only plays at Base Camp and in Stage 1. Past that (Stage 2+, or a site camp like
	Toxic Twilight, both off ExposureState) it fades out and pauses, and picks the
	same track back up when you return.

	TRACKS are Roblox-licensed APM library music: bouncy, cartoony picks chosen by ear.
	Swapping one is one line here; the place file is not involved.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sfx = require(script.Parent.Parent.Sfx)
local Net = require(game:GetService("ReplicatedStorage").Shared.Net)

local MusicController = {}

-- Very quiet on purpose: a bed under the game, never over it. The Music slider
-- defaults to 0% (off, opt-in); 50% there halves this to the intended 0.12.
local VOLUME = 0.24
-- Seconds to fade out leaving Stage 1, and back in on return.
local FADE = 2
-- Silence between two tracks, so one ending does not crash into the next.
local GAP = 2

local TRACKS: { number } = {
	1837589421, -- Cheekie Chappy
	1846531424, -- The Happy Parrot
	1836295968, -- Doris Duck
	1842262519, -- Baby Bouncer
	1842214009, -- Plenty Funny
}

local function shuffled(last: number?): { number }
	local list = table.clone(TRACKS)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	-- Never play the same track twice in a row across a reshuffle.
	if last and #list > 1 and list[1] == last then
		list[1], list[#list] = list[#list], list[1]
	end
	return list
end

function MusicController.init() end

function MusicController.start()
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.Volume = VOLUME
	Sfx.adopt(sound, "music")
	sound.Parent = SoundService

	-- Base Camp (no stage, no camp) and Stage 1 only.
	local allowed = true
	local fade: Tween? = nil
	local function setAllowed(on: boolean)
		if on == allowed then
			return
		end
		allowed = on
		if fade then
			fade:Cancel()
		end
		local tween = TweenService:Create(sound, TweenInfo.new(FADE), { Volume = if on then VOLUME else 0 })
		fade = tween
		if on and sound.IsPaused and sound.TimePosition > 0 then
			sound:Resume()
		end
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed and not allowed then
				sound:Pause()
			end
		end)
		tween:Play()
	end
	Net.get("ExposureState").OnClientEvent:Connect(function(state)
		setAllowed((state.stageId == nil and state.campId == nil) or state.stageId == 1)
	end)

	task.spawn(function()
		local queue = shuffled(nil)
		local index = 0
		local last: number? = nil
		while true do
			-- Do not start a fresh track while faded out past Stage 1.
			while not allowed do
				task.wait(1)
			end
			index += 1
			if index > #queue then
				queue = shuffled(last)
				index = 1
			end
			last = queue[index]
			sound.SoundId = "rbxassetid://" .. tostring(last)
			sound.TimePosition = 0
			sound:Play()
			-- A track that fails to load never fires Ended; the timeout moves on.
			local done = false
			local conn = sound.Ended:Connect(function()
				done = true
			end)
			local started = os.clock()
			while not done do
				task.wait(1)
				if sound.TimeLength == 0 and os.clock() - started > 15 then
					break
				end
			end
			conn:Disconnect()
			task.wait(GAP)
		end
	end)
end

return MusicController
