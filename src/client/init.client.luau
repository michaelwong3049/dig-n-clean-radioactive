--[[
	Client bootstrap — the mirror of ServerScriptService.Server.

	Same two-phase init/start, same explicit ORDER, same loud warning if a controller
	exists but was never listed. Controllers render and predict; they never decide.
	Anything that touches cash, radiation or item state is the server's call
	(ARCHITECTURE.md, "Server/client boundary").
]]

local CONTROLLERS = script.Controllers

local ORDER = {
	"DetectorController", -- Phase 1: radar scope, ping audio, hold-to-pull
	"FieldController", -- Phase 1: the range ring and the aura pulse; reads DetectorController
	"InventoryController", -- Phase 1: the hotbar and its detail card; reads CarryState
	"StationController", -- Phase 1: base camp — scrub, sell, rack
	"HudController", -- Phase 2: rad meter, vignette, distortion, blackout
	"GeigerController", -- Phase 2: the click bed (reads HudController)
	"AtmosphereController", -- per-zone fog; reads zoneId off ExposureState
	"DebugHudController",
}

local loaded: { [string]: any } = {}
local ordered: { { name: string, controller: any } } = {}

-- Listed-in-ORDER and successfully-loaded are different things. Keying the orphan
-- check below off `loaded` conflates them, so a controller that errored while
-- loading also got reported as unlisted — two warnings, one of them false, for one
-- problem.
local listed: { [string]: boolean } = {}
for _, name in ORDER do
	listed[name] = true
end

for _, name in ORDER do
	local module = CONTROLLERS:FindFirstChild(name)
	if module == nil then
		warn(`[client] listed in ORDER but not present: {name}`)
		continue
	end

	local ok, result = pcall(require, module)
	if not ok then
		warn(`[client] FAILED to require {name}: {result}`)
		continue
	end

	loaded[name] = result
	table.insert(ordered, { name = name, controller = result })
end

for _, module in CONTROLLERS:GetChildren() do
	if module:IsA("ModuleScript") and not listed[module.Name] then
		warn(`[client] {module.Name} exists but is not in ORDER — it will never start`)
	end
end

for _, entry in ordered do
	if type(entry.controller.init) == "function" then
		local ok, err = pcall(entry.controller.init)
		if not ok then
			warn(`[client] {entry.name}.init() errored: {err}`)
		end
	end
end

for _, entry in ordered do
	if type(entry.controller.start) == "function" then
		local ok, err = pcall(entry.controller.start)
		if not ok then
			warn(`[client] {entry.name}.start() errored: {err}`)
		end
	end
end

print(`[client] {#ordered} controller(s) up: {table.concat(ORDER, ", ")}`)
