--!strict
--[[
	WarpService.luau — the one server verb behind every warp button.

	The client's WarpController shows two portals whenever the player is standing in
	no stage — HOME and SHOPS — and CampWarpController's Warp tile opens a list of every
	camp; this is what all of them call. The client sends
	a destination NAME and nothing else (`{ dest = "base" | "shops" }`); this file
	re-derives the actual CFrame server-side, the same way DigService decides which
	buried signal a yank meant from where the player is standing rather than trusting
	the client to name it (ARCHITECTURE.md, "the client never names what it wants").

	IT IS NOT AN ESCAPE HATCH. The wasteland is open and the only thing that stops a
	player is the arithmetic in Shared/Radiation (PLAN §3.5) — a button that lifts you
	out of a lethal field for free would gut that. So a Warp from inside a stage is
	REFUSED here, not merely hidden by the bar: `StageService.stageOf` must be nil.
	The bar hides itself in stages and the camp list greys out, so a legitimate client
	never reaches the refusal; it is here for the one that lies.

	DESTINATIONS, AND WHY THEY ARE NOT THIS FILE'S TO DEFINE:
	  base   -> ExhibitService.plotSpawn(player), the same PlotSpawn assign() already
	            routes this player's respawns to. nil (no plot this session, all six
	            taken) falls through to the shop anchor, so the button is never dead.
	  shops  -> the SELL button: in front of Base Camp's Trader kiosk (traderCFrame),
	            falling back to ExposureService.baseCampCFrame() if it is missing.

	  <camp key> -> CampService.arrivalCFrame(key), the CampAnchor build/CampSite stands
	            in that camp's plaza (Config/Camps; "twilight" is Toxic Twilight). A
	            third rule on top of "not from inside a stage": the player must have
	            REACHED that camp on foot once (CampService.reached). The Warp panel shows
	            the row locked until then; this is the refusal for a client that lies.
	            nil (the saved place predates the camp) refuses too, rather than
	            dropping anyone into open water.

	Neither is looked up from Workspace here: this service owns the RULE (are you
	allowed to, and where does the name point), not the geometry.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Camps = require(ReplicatedStorage.Shared.Config.Camps)

local DataService = require(script.Parent.DataService)
local StageService = require(script.Parent.StageService)
local DigService = require(script.Parent.DigService)
local ExhibitService = require(script.Parent.ExhibitService)
local ExposureService = require(script.Parent.ExposureService)
local CampService = require(script.Parent.CampService)
local TutorialService = require(script.Parent.TutorialService)

local WarpService = {}

--- Spam guard. The move itself is idempotent, but firing it repeatedly while the
--- character is still settling reads as a rubber-band; one hop per this many seconds
--- is plenty for a navigation button.
local COOLDOWN = 0.5
local lastWarp: { [Player]: number } = {}

--- Lift so the character drops onto the pad rather than spawning inside it — the
--- same +4 ExhibitService.teleportToSpawn and DebugService's /stage both use.
local DROP_IN = Vector3.new(0, 4, 0)

--- StreamingEnabled: ask the client to stream the landing in BEFORE the move, so the
--- player arrives on a loaded area instead of watching the map pop in block by block
--- around them. Capped, so a slow device still warps -- just with some pop-in.
local PRELOAD_TIMEOUT = 1.5
local preloading: { [Player]: boolean } = {}

--- The SELL button lands you at Base Camp's Trader (2026-10-04, on request: "change
--- shop tp name to sell and make it go to the trader"). The Trader is the four-sided
--- kiosk on PLAZA_MID (BaseCamp.buildHubTrader): land this far out from its centre on a
--- random side, facing a counter. That is past the deck (half 7.5) but inside the sell
--- radius (16), so the panel opens on arrival -- unlike the respawn ring, which sits just
--- outside it on purpose. Looked up only on a press, scoped to BaseCamp (Toxic Twilight
--- has a Trader too). Falls back to the plaza anchor if the kiosk is not there.
local TRADER_LANDING = 10
local function traderCFrame(): CFrame
	local camp = Workspace:FindFirstChild("BaseCamp", true)
	local trader = camp and camp:FindFirstChild("Trader")
	local station = trader and trader:FindFirstChild("TraderStation")
	if station and station:IsA("BasePart") then
		local centre = station.Position + Vector3.new(0, 2, 0)
		local angle = math.random(0, 3) * (math.pi / 2)
		local at = centre + Vector3.new(math.sin(angle), 0, math.cos(angle)) * TRADER_LANDING
		return CFrame.lookAt(at, centre)
	end
	return ExposureService.baseCampCFrame()
end

local function destinationFor(player: Player, dest: string): CFrame?
	if dest == "shops" then
		return traderCFrame()
	elseif dest == "base" then
		local spawn = ExhibitService.plotSpawn(player)
		if spawn then
			return spawn.CFrame + DROP_IN
		end
		-- No plot this session. The shop anchor is a safe, sensible landing rather
		-- than leaving the button do nothing.
		return ExposureService.baseCampCFrame()
	end
	-- A site camp. Reached on foot first, and actually in this world -- see the header.
	local camp = Camps.get(dest)
	if camp and camp.key ~= Camps.BASE and CampService.reached(player, camp.key) then
		local anchor = CampService.arrivalCFrame(camp.key)
		if anchor then
			return anchor + DROP_IN
		end
	end
	return nil
end

--- Every rule a warp has to pass right now. Checked before the preload and again
--- after it, since the player can walk into a stage or start a haul while it yields.
local function allowed(player: Player, dest: string): boolean
	-- Never out of a live field. See the header.
	if StageService.stageOf(player) ~= nil then
		return false
	end
	-- HOME / SHOPS unlock with the walkthrough: the tutorial walks you there on foot.
	-- Its last step ("navigate") is the one that shows you these two buttons, so they
	-- work from then on.
	if dest == "base" or dest == "shops" then
		local data = DataService.data(player)
		if data == nil or (data.onboarding == "active" and player:GetAttribute("TutorialStep") ~= "navigate") then
			return false
		end
	end
	-- Rooted mid-haul: DigService releases the lock on every path that can
	-- invalidate it and a teleport is not one of those paths, so refuse rather than
	-- strand a rooted player somewhere new.
	return not DigService.isLocked(player)
end

local function onWarp(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local dest = payload.dest
	if type(dest) ~= "string" or (dest ~= "base" and dest ~= "shops" and Camps.get(dest) == nil) then
		return
	end

	if preloading[player] or not allowed(player, dest) then
		return
	end

	local now = os.clock()
	local previous = lastWarp[player]
	-- HOME / SHOPS are instant: no cooldown, only site-camp hops are rate limited.
	local instant = dest == "base" or dest == "shops"
	if not instant and previous ~= nil and now - previous < COOLDOWN then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local target = destinationFor(player, dest)
	if target == nil then
		return
	end

	lastWarp[player] = now
	preloading[player] = true
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, PRELOAD_TIMEOUT)
	end)
	preloading[player] = nil

	-- The world moved on while that yielded: same character, same rules, or no warp.
	if player.Parent == nil or player.Character ~= character or root.Parent ~= character or not allowed(player, dest) then
		return
	end
	root.CFrame = target
	root.AssemblyLinearVelocity = Vector3.zero
	-- Using HOME / SHOPS is the walkthrough's last task.
	if instant then
		TutorialService.complete(player)
	end
end

function WarpService.init() end

function WarpService.start()
	Net.get("Warp").OnServerEvent:Connect(function(player: Player, payload: any)
		local ok, err = pcall(onWarp, player, payload)
		if not ok then
			warn(`[warp] {player.Name}: {err}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastWarp[player] = nil
		preloading[player] = nil
	end)
end

return WarpService
