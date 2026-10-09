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

--- Seconds between applied changes per player, so a spammed switch cannot hammer the
--- profile. A change inside it WAITS, it is not dropped: dropping one meant a volume
--- you had just lowered could snap back and never save. Every send still gets exactly
--- one echo (client/Prefs counts them), sent once its change is in.
local CHANGE_COOLDOWN = 0.15

local lastChange: { [Player]: number } = {}
--- Changes waiting out the cooldown, oldest first, flushed together.
local queued: { [Player]: { { [string]: any } } } = {}

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

local function apply(player: Player, changes: { [string]: any })
	local data = DataService.data(player)
	if data == nil or next(changes) == nil then
		return
	end
	if type(data.prefs) ~= "table" then
		data.prefs = Prefs.defaults()
	end
	for key, value in changes do
		data.prefs[key] = value
	end
end

local function onChange(player: Player, payload: any)
	-- Anything but a { key, value } is "what are they set to?".
	if type(payload) ~= "table" then
		echo(player)
		return
	end
	if DataService.data(player) == nil then
		return
	end
	-- One change ({ key, value }) or several at once ({ batch = { [key] = value } }),
	-- which counts as ONE change against the cooldown: the loading screen's device pick
	-- sets three prefs together.
	local changes: { [string]: any } = {}
	if type(payload.batch) == "table" then
		for key, raw in payload.batch do
			local value = Prefs.sanitize(key, raw)
			if value ~= nil then
				changes[key] = value
			end
		end
	else
		local value = Prefs.sanitize(payload.key, payload.value)
		if value ~= nil then
			changes[payload.key] = value
		end
	end

	local list = queued[player]
	if list then
		-- A flush is already scheduled; ride along with it.
		table.insert(list, changes)
		return
	end
	local wait = (lastChange[player] or -math.huge) + CHANGE_COOLDOWN - os.clock()
	if wait <= 0 then
		lastChange[player] = os.clock()
		apply(player, changes)
		echo(player)
		return
	end
	list = { changes }
	queued[player] = list
	task.delay(wait, function()
		if queued[player] ~= list then
			return -- left meanwhile
		end
		queued[player] = nil
		lastChange[player] = os.clock()
		for _, each in list do
			apply(player, each)
		end
		for _ in list do
			echo(player)
		end
	end)
end

function PrefsService.init()
	Net.get("Prefs")
end

function PrefsService.start()
	Net.get("Prefs").OnServerEvent:Connect(onChange)
	DataService.onLoaded(function(player, data)
		if not data.fastModeSwitchedOn then
			data.fastModeSwitchedOn = true
			if type(data.prefs) ~= "table" then
				data.prefs = Prefs.defaults()
			end
			data.prefs.fastMode = true
		end
		echo(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- Anything still waiting out the cooldown goes in before the profile saves.
		for _, each in queued[player] or {} do
			apply(player, each)
		end
		lastChange[player] = nil
		queued[player] = nil
	end)
end

return PrefsService
