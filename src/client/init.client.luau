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
	"StationController", -- Phase 1: base camp — scrub, sell, rack
	"InventoryController", -- Phase 1: the hotbar and its detail card; reads CarryState + StationController
	"HudController", -- Phase 2: rad meter, the RadFx damage overlay, distortion, blackout
	"GeigerController", -- Phase 2: the click bed (reads HudController)
	"AtmosphereController", -- per-stage fog; reads stageId off ExposureState
	"StageBannerController", -- the stage-name title card; also reads stageId off ExposureState
	"IndexController", -- the item index GUI; bottom-right button, reads IndexState + Unearthed
	"CashController", -- the persistent cash badge; top-left, reads CashState
	"LiquidController", -- the loaded-liquid badge; reads LiquidState
	"WashController", -- the wash bay: camera, patch blobs, the hose stream; reads WashState
	"NameTagController", -- subdued overhead player names; replaces Roblox's bright default tag
	"WarpController", -- the top-of-screen BASE / SHOPS bar; reads stageId off ExposureState
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
