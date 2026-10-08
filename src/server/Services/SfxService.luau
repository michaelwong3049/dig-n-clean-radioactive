--[[
	SfxService.luau — the server's half of sound effects, which is very little.

	Sound is the client's job (client/Sfx.luau). Nearly every cue is played off
	something the client already sees: a cash change, a panel, a remote payload. This
	service covers the one thing only the server knows:

	  * `SfxService.play(player, name)` — a one-shot cue for ONE player, for moments
	    the client cannot see coming: a purchase refused for want of cash (every shop
	    refuses through EconomyService.spend), a Robux product granted.

	Settings' volumes are client prefs (Config/Prefs volSfx, musicLevel).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local SfxService = {}

--- One cue for one player. Safe to call from any service at any time: the remote is
--- fetched on use, so nothing depends on this service's place in the boot ORDER.
function SfxService.play(player: Player, name: string)
	Net.get("Sfx"):FireClient(player, name)
end

function SfxService.init()
	Net.get("Sfx")
end

function SfxService.start() end

return SfxService
