--!strict
--[[
	MusicController.luau — the background playlist.

	One 2D Sound in SoundService, heard only by you, that walks a shuffled list of
	tracks and reshuffles when it runs out. It joins Sfx's "music" group, so the
	Settings mute and master volume quieten it with everything else.

	TRACKS are Roblox-licensed APM library music: bouncy, cartoony picks chosen by ear.
	Swapping one is one line here; the place file is not involved.
]]

local SoundService = game:GetService("SoundService")

local Sfx = require(script.Parent.Parent.Sfx)

local MusicController = {}

-- Very quiet on purpose: a bed under the game, never over it. The Music slider scales
-- this down further, so even 100% there stays low.
local VOLUME = 0.08
-- Silence between two tracks, so one ending does not crash into the next.
local GAP = 2

local TRACKS: { number } = {
	1837589421, -- Cheekie Chappy
	1846531424, -- The Happy Parrot
	1836295968, -- Doris Duck
	1842262519, -- Baby Bouncer
	1842214009, -- Plenty Funny
	1839153331, -- Fun Kidz
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

	task.spawn(function()
		local queue = shuffled(nil)
		local index = 0
		local last: number? = nil
		while true do
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
