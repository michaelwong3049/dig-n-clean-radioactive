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
	"ModelCacheService", -- FIRST: moves the nuke templates out of ReplicatedStorage before anyone joins
	"PromptStyleService", -- every world ProximityPrompt replicates as Custom, so Roblox's grey prompt never draws under the glass card
	"DataService", -- everything downstream needs a profile
	"PlayerCollisionService", -- players phase through each other; standalone
	"SfxService", -- one-shot sound cues for one player + the SOUND EFFECTS setting; needs Data
	"PrefsService", -- the Settings panel's prefs (graphics, shake, rad effects, flashing, volumes, rare drops); needs Data
	"IdentifyService", -- "???" -> a name; the index write lives here and nowhere else
	"StageService", -- who is standing where; exposure and digging both read it
	"CampService", -- which camp you are in and which you have reached; Exposure + Warp read it
	"HazardService", -- detonations and their craters; Dig sets them off, Exposure takes the damage
	"ExposureService", -- Phase 2: the rad meter, burn and blackout
	"DigService", -- Phase 1: the signal field, sweep and haul
	"EconomyService", -- prices and the till; DeconService calls into it
	"CarryService", -- describes the backpack for every surface that renders it; needs Economy
	"StationService", -- what you are standing at; DeconService, ShopService and ExhibitService read it
	"ShopService", -- turning cash back into capability; needs Station + Economy
	"ProductService", -- Robux developer products; the ONE owner of ProcessReceipt; needs Data
	"GamePassService", -- the seven permanent passes: ownership into data.passes for StatResolver; needs Data
	"LuckBoostService", -- 2x luck: the Violet Aurora event + the bought Lucky Clover; needs Product
	"CashBoostService", -- 2x cash for a while, bought inside a pack; needs Data
	"PotionService", -- the potion stash + ten-minute potion clocks; needs Data
	"BoostsService", -- the bottom-right Boosts widget: every multiplier and its sources, sent on change; needs Data
	"WeatherService", -- the random weather every 15-20 min: Violet Aurora / Golden Hour / Meteor Shower; needs Dig + LuckBoost
	"RareDropService", -- the announced drop every 8-12 min: a guaranteed Epic+ in a random stage; needs Dig + LuckBoost
	"AwayEarningsService", -- the "While you were away" card: holds offline income for COLLECT / Robux DOUBLE IT; needs Economy + Product
	"ExhibitService", -- plot assignment, display/undisplay, yield accrual; needs Station + Economy
	"TreadmillService", -- the speed grind on your plot's belt; needs Station + Economy + Exhibit
	"WarpService", -- the top-of-screen bar's teleport; needs Stage + Camp + Dig + Exhibit + Exposure
	"LiquidService", -- the fluid bottle + panel: rolling liquids, charges, Luck; needs Exhibit + Shop
	"WashService", -- the hose bay: the E-to-wash session; needs Carry + Liquid + Economy
	"CrateService", -- opening dug-up supply crates; needs Dig + Wash + Liquid + Identify
	"PackService", -- the Starter / Pro Packs: cash, crates, luck + cash time in one receipt; needs Product + Economy + Crate + LuckBoost + CashBoost
	"DailyRewardService", -- the 7-day login calendar; needs Economy + Crate + LuckBoost + CashBoost + Exhibit
	"GroupRewardService", -- the group chest on Stage 1: join the group for cash + Speed + 2x luck, once; needs Economy + LuckBoost + Exhibit + Treadmill
	"CrateShopService", -- the two crate pads either side of the group chest: Scrap + Coolant for cash, Fusion + Plasma for Robux; needs Economy + Product + Crate
	"PlaytimeGiftService", -- the Free Gifts ladder: gifts open at 1-120 min of play, reset on leaving; needs Economy + Crate + LuckBoost + CashBoost + Exhibit + Treadmill + Potion
	"CodeService", -- the Shop's CODES section: group members redeem a code once for its reward; needs Economy + Crate + LuckBoost + CashBoost + Potion + Exhibit + Treadmill + GroupReward
	"DeconService", -- base camp: docking, racking, and the shop/plot/pedestal panel
	"MergeService", -- the Merge Reactor at Toxic Twilight: 3 copies in, 1 out; needs Station + Economy + Carry + Exhibit + Wash
	"ReforgeService", -- the Reforge Station at Toxic Twilight: pay to reroll a nuke's bomb damage/radius, rare quality; same needs as Merge
	"FurnaceService", -- the Slag Furnace at Magma Hollow: burn nukes to fill a meter, roll potions/crates/cash/boosts/nukes; needs Station + Economy + Carry + Exhibit + Wash + Identify + Potion + Crate + LuckBoost + CashBoost
	"GiftService", -- gifting the held nuke to another player, both past Toxic Twilight; needs Carry + Dig + Wash
	"ToolService", -- held models; reads DigService + DeconService + WashService state
	"BombService", -- dropping a held clean nuke as a bomb; copies ToolService's held model, needs Stage + Hazard + Dig
	"LeaderboardService", -- mirrors data.cash into leaderstats for the player list; needs Data
	"StatsService", -- Settings > Stats: ticks playtime into data.stats and answers the page's asks; needs Data
	"MasteryService", -- the Masteries panel + "Mastery reached" toast; watches counters other services bump; needs Data + Stage
	"AuraService", -- the worn aura: stamps each character's AuraTier for the clients to draw; reads Data
	"TutorialService", -- the new-player walkthrough; reads Stage + Dig + Carry, nudges Carry
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
