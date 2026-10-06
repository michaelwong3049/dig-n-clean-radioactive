--[[
	Prefs.luau — this player's Settings prefs (Config/Prefs), for any client file to read.

	    Prefs.get("graphics")            -> "high"
	    Prefs.observe("shake", fn)       -> fn(value) now, and again on every change
	    Prefs.set("volSfx", 0.4)         -> applies at once, then saves
	    Prefs.preview("volSfx", 0.4)     -> applies at once, does not save (mid-drag)
	    Prefs.setMany({ a = 1, b = 2 })  -> several at once, saved as one change
	    Prefs.onLoaded(fn)               -> fn() once the saved values have landed

	The server owns the saved values (PrefsService). Until its first echo lands every
	pref reads its default, which is the game as built, so a reader never has to wait.

	OPTIMISTIC, THEN RECONCILED. `set` applies locally the same frame (a volume slider
	has to move the sound while you drag) and sends the change. Each send gets exactly
	one echo of the whole table back; echoes are only applied once every outstanding
	send has been answered, so an earlier echo never flicks a later change back. A
	change the server refused shows up in that final echo and snaps back.

	Requiring this connects Net.Prefs, so whichever controller requires it first takes
	the queued load echo — and it also asks, in case that echo went before anyone was
	listening.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local PrefsConfig = require(Shared.Config.Prefs)

local Prefs = {}

local values: { [string]: any } = PrefsConfig.defaults()
local listeners: { [string]: { (any) -> () } } = {}
local outstanding = 0
local loaded = false
local loadedWaiters: { () -> () } = {}

local function notify(key: string, value: any)
	local list = listeners[key]
	if list == nil then
		return
	end
	for _, fn in list do
		task.spawn(fn, value)
	end
end

local function put(key: string, value: any)
	if values[key] == value then
		return
	end
	values[key] = value
	notify(key, value)
end

function Prefs.get(key: string): any
	return values[key]
end

--- `fn(value)` straight away with the current value, then on every change.
function Prefs.observe(key: string, fn: (any) -> ())
	local list = listeners[key]
	if list == nil then
		list = {}
		listeners[key] = list
	end
	table.insert(list, fn)
	fn(values[key])
end

--- Apply `value` locally WITHOUT saving: a slider mid-drag, so the sound follows your
--- finger. The drag's release calls `set`, which saves.
function Prefs.preview(key: string, value: any)
	local clean = PrefsConfig.sanitize(key, value)
	if clean ~= nil then
		put(key, clean)
	end
end

function Prefs.set(key: string, value: any)
	local clean = PrefsConfig.sanitize(key, value)
	if clean == nil then
		return
	end
	put(key, clean)
	outstanding += 1
	Net.get("Prefs"):FireServer({ key = key, value = clean })
end

--- Several prefs at once, saved as ONE change: PrefsService's per-player cooldown would
--- refuse the second of two `set`s sent back to back.
function Prefs.setMany(changes: { [string]: any })
	local clean = {}
	for key, value in changes do
		local v = PrefsConfig.sanitize(key, value)
		if v ~= nil then
			clean[key] = v
			put(key, v)
		end
	end
	if next(clean) == nil then
		return
	end
	outstanding += 1
	Net.get("Prefs"):FireServer({ batch = clean })
end

--- `fn()` once the saved values have landed (now, if they already have). Before that
--- every pref reads its default, so "still the default" and "not loaded" look the same.
function Prefs.onLoaded(fn: () -> ())
	if loaded then
		task.spawn(fn)
	else
		table.insert(loadedWaiters, fn)
	end
end

Net.get("Prefs").OnClientEvent:Connect(function(table_: any)
	outstanding = math.max(0, outstanding - 1)
	if outstanding > 0 or type(table_) ~= "table" then
		return
	end
	for key, def in PrefsConfig.DEFS do
		local value = PrefsConfig.sanitize(key, table_[key])
		put(key, if value == nil then def.default else value)
	end
	if not loaded then
		loaded = true
		for _, fn in loadedWaiters do
			task.spawn(fn)
		end
		table.clear(loadedWaiters)
	end
end)
-- The ask counts as a send: its echo is the one that lands the saved values.
outstanding += 1
Net.get("Prefs"):FireServer(nil)

return Prefs
