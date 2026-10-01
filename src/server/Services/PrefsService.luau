--[[
	PrefsService.luau — stores the Settings panel's prefs (Config/Prefs) and echoes them.

	That is all it does. Every pref is client-side in effect (graphics, shake, flashing,
	volumes, which rare drop lines show), so nothing on the server reads them. The shape
	is SfxService's SOUND EFFECTS switch, widened to a table: the whole table goes to the
	client once on load and again after every change, so a refused or dropped change
	snaps the panel back to what actually stuck.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Prefs = require(Shared.Config.Prefs)

local DataService = require(script.Parent.DataService)

local PrefsService = {}

--- Seconds between accepted changes per player, so a spammed switch cannot hammer the
--- profile. A change inside it is dropped and the echo snaps the panel back.
local CHANGE_COOLDOWN = 0.15

local lastChange: { [Player]: number } = {}

--- The player's prefs with every key present and legal, whatever the save holds.
local function resolved(data: any): { [string]: any }
	local stored = if type(data.prefs) == "table" then data.prefs else {}
	local out = {}
	for key, def in Prefs.DEFS do
		local value = Prefs.sanitize(key, stored[key])
		out[key] = if value == nil then def.default else value
	end
	return out
end

local function echo(player: Player)
	local data = DataService.data(player)
	if data then
		Net.get("Prefs"):FireClient(player, resolved(data))
	end
end

local function onChange(player: Player, payload: any)
	-- Anything but a { key, value } is "what are they set to?".
	if type(payload) ~= "table" then
		echo(player)
		return
	end
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local value = Prefs.sanitize(payload.key, payload.value)
	local now = os.clock()
	if value ~= nil and now - (lastChange[player] or 0) >= CHANGE_COOLDOWN then
		lastChange[player] = now
		if type(data.prefs) ~= "table" then
			data.prefs = Prefs.defaults()
		end
		data.prefs[payload.key] = value
	end
	echo(player)
end

function PrefsService.init()
	Net.get("Prefs")
end

function PrefsService.start()
	Net.get("Prefs").OnServerEvent:Connect(onChange)
	DataService.onLoaded(function(player, _data)
		echo(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastChange[player] = nil
	end)
end

return PrefsService
