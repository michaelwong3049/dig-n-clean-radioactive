--[[
	Server bootstrap — the ONLY Script in the game (ARCHITECTURE.md, module map).

	Everything else is a ModuleScript required from here. That is what makes service
	startup order explicit and debuggable instead of being whatever order Roblox felt
	like running loose Scripts in.

	Two phases, deliberately:
	  init()  — build your own state. Do NOT touch another service.
	  start() — connect events and talk to other services. Everything exists by now.

	That split is what lets services reference each other without a load-order puzzle.
	A service may omit either function.
]]

local SERVICES = script.Services

-- Explicit order. Dependencies first — read this list as the dependency graph,
-- because it is the only place that graph is written down.
local ORDER = {
	"DataService", -- everything downstream needs a profile
	"StageService", -- who is standing where; exposure and digging both read it
	"ExposureService", -- Phase 2: the rad meter, burn and blackout
	"DigService", -- Phase 1: the signal field, sweep and haul
	"EconomyService", -- prices and the till; DeconService calls into it
	"CarryService", -- describes the backpack for every surface that renders it; needs Economy
	"StationService", -- what you are standing at; DeconService, ShopService and ExhibitService read it
	"ShopService", -- turning cash back into capability; needs Station + Economy
	"ExhibitService", -- plot assignment, display/undisplay, yield accrual; needs Station + Economy
	"WarpService", -- the top-of-screen bar's teleport; needs Stage + Dig + Exhibit + Exposure
	"LiquidService", -- the wash pad: rolling liquids, charges, equip; needs Station + Economy
	"WashService", -- the hose bay: the E-to-wash session; needs Carry + Liquid + Economy
	"DeconService", -- base camp: docking, racking, and the shop/plot/pedestal panel
	"ToolService", -- held models; reads DigService + DeconService + WashService state
	"DebugService", -- the tuning console; reads the services above
}

local function boot()
	local started = os.clock()
	local loaded: { [string]: any } = {}
	local ordered: { { name: string, service: any } } = {}

	-- Listed-in-ORDER and successfully-loaded are different things; keying the orphan
	-- check off `loaded` would report a service that errored while loading as also
	-- being unlisted.
	local listed: { [string]: boolean } = {}
	for _, name in ORDER do
		listed[name] = true
	end

	-- Load
	for _, name in ORDER do
		local module = SERVICES:FindFirstChild(name)
		if module == nil then
			warn(`[boot] listed in ORDER but not present: {name}`)
			continue
		end

		local ok, result = pcall(require, module)
		if not ok then
			warn(`[boot] FAILED to require {name}: {result}`)
			continue
		end

		loaded[name] = result
		table.insert(ordered, { name = name, service = result })
	end

	-- Anything sitting in Services/ that nobody listed. Loud on purpose: a service
	-- that exists but never boots is a genuinely horrible bug to chase later.
	for _, module in SERVICES:GetChildren() do
		if module:IsA("ModuleScript") and not listed[module.Name] then
			warn(`[boot] {module.Name} exists but is not in ORDER — it will never start`)
		end
	end

	-- Phase 1: init
	for _, entry in ordered do
		if type(entry.service.init) == "function" then
			local ok, err = pcall(entry.service.init)
			if not ok then
				warn(`[boot] {entry.name}.init() errored: {err}`)
			end
		end
	end

	-- Phase 2: start
	for _, entry in ordered do
		if type(entry.service.start) == "function" then
			local ok, err = pcall(entry.service.start)
			if not ok then
				warn(`[boot] {entry.name}.start() errored: {err}`)
			end
		end
	end

	local ms = math.floor((os.clock() - started) * 1000)
	print(`[boot] {#ordered} service(s) up in {ms}ms: {table.concat(ORDER, ", ")}`)

	-- "NoAccess" means Studio API services are off and ProfileStore is running against
	-- an in-memory mock — saves will not survive restarting Studio. Worth saying out
	-- loud, because silently-not-persisting is a confusing thing to debug.
	local data = loaded.DataService
	if data then
		task.spawn(function()
			local state = data.dataStoreState()
			local deadline = os.clock() + 10
			while state == "NotReady" and os.clock() < deadline do
				task.wait(0.1)
				state = data.dataStoreState()
			end
			if state == "Access" then
				print("[boot] DataStore access OK — saves are real.")
			else
				warn(`[boot] DataStore state is "{state}" — running on the in-memory mock. Saves will NOT persist across a Studio restart.`)
			end
		end)
	end
end

boot()
