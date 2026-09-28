--[[
	SfxService.luau — the server's half of sound effects, which is very little.

	Sound is the client's job (client/Sfx.luau). Nearly every cue is played off
	something the client already sees: a cash change, a panel, a remote payload. This
	service covers the two things only the server knows:

	  * `SfxService.play(player, name)` — a one-shot cue for ONE player, for moments
	    the client cannot see coming: a purchase refused for want of cash (every shop
	    refuses through EconomyService.spend), a Robux product granted.
	  * SOUND EFFECTS on/off (Settings). A profile setting, data.sfxMuted, sent once on
	    load and echoed after every toggle -- the same shape as AuraService's HIDE MY
	    AURA, so a dropped toggle snaps the switch back.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local DataService = require(script.Parent.DataService)

local SfxService = {}

--- Seconds between accepted toggles per player, so a spammed click cannot hammer the
--- profile. A toggle inside it is dropped and the echo snaps the switch back.
local TOGGLE_COOLDOWN = 0.3

local lastToggle: { [Player]: number } = {}

--- One cue for one player. Safe to call from any service at any time: the remote is
--- fetched on use, so nothing depends on this service's place in the boot ORDER.
function SfxService.play(player: Player, name: string)
	Net.get("Sfx"):FireClient(player, name)
end

local function echo(player: Player)
	local data = DataService.data(player)
	if data then
		Net.get("SfxMuted"):FireClient(player, data.sfxMuted == true)
	end
end

local function onToggle(player: Player, muted: any)
	-- Anything but a boolean is "what is it set to?": the Settings panel asks on start,
	-- because a RemoteEvent's queued load echo is handed to whichever listener connects
	-- first (SfxController), and a later one never sees it.
	if type(muted) ~= "boolean" then
		echo(player)
		return
	end
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local now = os.clock()
	if now - (lastToggle[player] or 0) >= TOGGLE_COOLDOWN then
		lastToggle[player] = now
		data.sfxMuted = muted
	end
	echo(player)
end

function SfxService.init()
	Net.get("Sfx")
	Net.get("SfxMuted")
end

function SfxService.start()
	Net.get("SfxMuted").OnServerEvent:Connect(onToggle)
	DataService.onLoaded(function(player, _data)
		echo(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastToggle[player] = nil
	end)
end

return SfxService
