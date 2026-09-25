--[[
	Client bootstrap — the mirror of ServerScriptService.Server.

	Same two-phase init/start, same explicit ORDER, same loud warning if a controller
	exists but was never listed. Controllers render and predict; they never decide.
	Anything that touches cash, radiation or item state is the server's call
	(ARCHITECTURE.md, "Server/client boundary").
]]

local CONTROLLERS = script.Controllers

local ORDER = {
	"PromptController", -- the glass-card face for every default-style ProximityPrompt; first so it restyles them before any shows
	"DetectorController", -- Phase 1: hold-to-pull lock prompt, haul panel, unearth banner
	"FieldController", -- Phase 1: the range ring and the aura pulse; reads DetectorController, and it reads back
	"StationController", -- Phase 1: base camp — scrub, sell, rack
	"InventoryController", -- Phase 1: the hotbar and its detail card; reads CarryState + StationController
	"HudController", -- Phase 2: rad meter, the RadFx damage overlay, distortion, blackout
	"GeigerController", -- Phase 2: the click bed (reads HudController)
	"AuraWarningController", -- Phase 2: the "UPGRADE AURA" card when an over-tier stage is burning you down; reads ExposureState
	"AtmosphereController", -- per-stage fog; reads stageId off ExposureState
	"StageBannerController", -- the stage-name title card; also reads stageId off ExposureState
	"IndexController", -- the item index GUI; Index tile on the right edge, reads IndexState + Unearthed
	"ShopController", -- the Shop tile, stacked below the Index tile, and the Robux shop panel it opens
	"NukesController", -- the Nukes tile under Shop: every owned nuke + $/s, and Equip Best; reads NukeList
	"CampWarpController", -- the Warp tile under Nukes and its camp list: warp to any camp reached on foot; reads CampState
	"LuckBoostController", -- the 2x-luck clover (bottom right), the Violet Aurora banner + lights; opens the Shop
	"CashController", -- the persistent cash badge; top-left, reads CashState
	"AwayEarningsController", -- the "While you were away" card on login: COLLECT flies coins into the cash badge, DOUBLE IT is Robux
	"SpeedController", -- the persistent Speed badge under the cash badge; the one reader of SpeedState
	"LiquidController", -- the fluid spin popup; reads FluidSpin
	"CrateController", -- supply crates: the Open prompt on a held crate + the nuke-crate reveal; reads CrateOpened
	"WashController", -- the wash bay: camera, patch blobs, the hose stream; reads WashState
	"TreadmillController", -- the speed-training card and the belt's own motion; reads SpeedController
	"StationMotionController", -- base machines moving on their own: fans, dial, gauge needle, tub ripples, screen pulse
	"ItemFxController", -- nuke glow/glass/motion on any `ItemFx`-tagged model, once its crust is off
	"DetonationController", -- nukes going off: the blast, the crater orb, the lit-fuse warnings; reads Detonation
	"NameTagController", -- subdued overhead player names; replaces Roblox's bright default tag
	"AuraController", -- the atom-ring aura round every character (AuraTier attribute) and the Outfitter mannequin
	"StandCardController", -- the trophy-ribbon card over each displayed nuke; reads the StandCard attributes ExhibitService writes
	"WarpController", -- the top-of-screen HOME / SHOPS portals; reads stageId off ExposureState
	"BaseMarkerController", -- the "YOUR BASE" avatar beacon over your own plot; reads PlotState
	"SettingsController", -- the Settings panel (top-right gear); base-colour picker + HIDE MY AURA, reads/writes PlotColor and HideAura
	"TutorialController", -- the new-player walkthrough: top banner + ground trail; reads TutorialState
	"FlyController", -- dev-only free-fly; toggled by DebugService's /fly command via LocalPlayer's FlyMode attribute
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
