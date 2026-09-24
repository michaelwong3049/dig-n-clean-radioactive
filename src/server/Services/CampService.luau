--!strict
--[[
	CampService.luau — which camp you are in, and which camps you have reached.

	Base Camp is everyone's from the start. Every camp after it (Config/Camps, built by
	build/CampSite) is REACHED by standing in it on foot once, and that is saved:
	`data.camps[key] = true`. Reaching it is what unlocks its row on the Warp panel --
	the row is on everybody's list from day one, just locked (CampWarpController), and
	WarpService refuses the warp until this file says the camp is reached.

	WHY ON FOOT, AND NOT A PURCHASE. The camps sit on the stage chain: Toxic Twilight is
	past the Crater, and the only way in is to survive the walk (a Containment Rig, or a
	very brave dive -- Config/Stages' Crater note). Getting there IS the unlock. The warp
	only takes the tedium out of doing it twice. No gate stands in the way of the walk
	itself -- PLAN §3.5, nothing here denies entry.

	"IN A CAMP" IS PURE POSITION, NOT A STATION. `Camps.at` is a disc test off the root's
	XZ, the same shape of answer StageService gives for stages. A camp is safe because it
	is in no stage rectangle (World.verify() holds that), not because of anything here.

	A CAMP THAT ISN'T IN THE WORLD CANNOT BE REACHED OR WARPED TO. Code and geometry
	ship separately (the place file is not in git), so new code routinely runs against a
	place saved before the camp was built. Without the camp's CampAnchor in Workspace a
	warp would drop a player into open water, and a player falling off the end of the
	chain would "reach" a camp that is not there. So both wait on the anchor, per camp,
	and `available` in CampState tells the client which buttons may show at all.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Camps = require(Shared.Config.Camps)
local Stages = require(Shared.Config.Stages)
local Net = require(Shared.Net)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)

local CampService = {}

--- Reaching is not urgent -- a quarter second is well inside the time it takes to
--- notice you have arrived -- and the tick also polls for a rebuilt world.
local TICK = 0.25

--- A root this far below the camp's floor is falling past it, not standing in it.
local STANDING_BAND = 6

--- The least time between two asked-for pushes from one client (see start()).
local ASK_COOLDOWN = 1

local stateRemote: any = nil
local lastAvailable = ""
local lastAsk: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

--- This camp's warp landing, or nil if the world has not been built with it. The
--- anchor is a direct child of its camp's model (build/CampSite buildAnchor), so this
--- never walks the thousands of floor and wall parts around it -- it runs every tick.
function CampService.anchorFor(key: string): BasePart?
	local root = Workspace:FindFirstChild(Camps.MODEL_NAME)
	if root == nil then
		return nil
	end
	for _, camp in root:GetChildren() do
		if camp:GetAttribute("CampKey") == key then
			local anchor = camp:FindFirstChild(Camps.ANCHOR_NAME)
			if anchor and anchor:IsA("BasePart") then
				return anchor
			end
		end
	end
	return nil
end

--- The site camp this player is standing in, or nil (a stage, Base Camp, the void).
function CampService.campOf(player: Player): Camps.CampDef?
	local root = rootOf(player)
	if root == nil then
		return nil
	end
	local pos = root.Position
	return Camps.at(pos.X, pos.Z)
end

--- Has this player unlocked `key`'s warp? Base Camp always; a site once reached.
function CampService.reached(player: Player, key: string): boolean
	if key == Camps.BASE then
		return true
	end
	local data = DataService.data(player)
	return data ~= nil and data.camps ~= nil and data.camps[key] == true
end

--- Where a warp to `key` lands, or nil if that camp is not in this world.
function CampService.arrivalCFrame(key: string): CFrame?
	local anchor = CampService.anchorFor(key)
	return if anchor then anchor.CFrame else nil
end

local function availableSet(): { [string]: boolean }
	local out = {}
	for _, def in Camps.sites() do
		if CampService.anchorFor(def.key) then
			out[def.key] = true
		end
	end
	return out
end

local function signature(set: { [string]: boolean }): string
	local keys = {}
	for key in set do
		table.insert(keys, key)
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function push(player: Player, available: { [string]: boolean }, unlocked: string?)
	local data = DataService.data(player)
	if data == nil or stateRemote == nil then
		return
	end
	local reached = {}
	for key, yes in data.camps or {} do
		if yes == true and Camps.get(key) then
			reached[key] = true
		end
	end
	stateRemote:FireClient(player, { reached = reached, available = available, unlocked = unlocked })
end

--- Forget every camp this player has reached. For the tuning console (/camplock), so
--- the locked button can be tested without a fresh save.
function CampService.clearReached(player: Player)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	data.camps = {}
	push(player, availableSet(), nil)
end

function CampService.init()
	stateRemote = Net.get("CampState")
end

function CampService.start()
	DataService.onLoaded(function(player: Player, data: any)
		if data.camps == nil then
			data.camps = {} -- Reconcile() fills this; belt and braces for a mid-session hot reload
		end
		push(player, availableSet(), nil)
	end)

	-- A client asks for a fresh push with an empty FireServer. More than one client
	-- controller reads CampState, and a push that lands before any of them listens is
	-- queued for the FIRST one to connect only; the others ask once they are listening.
	-- Nothing is taken from the request but the player.
	stateRemote.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastAsk[player] or -math.huge) < ASK_COOLDOWN then
			return
		end
		lastAsk[player] = now
		push(player, availableSet(), nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAsk[player] = nil
	end)

	Ticker.every(TICK, function()
		local available = availableSet()
		local sig = signature(available)
		local worldChanged = sig ~= lastAvailable
		lastAvailable = sig

		for _, player in Players:GetPlayers() do
			local data = DataService.data(player)
			if data == nil then
				continue
			end
			local unlocked: string? = nil
			local camp = CampService.campOf(player)
			local root = rootOf(player)
			if
				camp
				and root
				and available[camp.key]
				and root.Position.Y > Stages.SURFACE_Y - STANDING_BAND
				and not CampService.reached(player, camp.key)
			then
				data.camps = data.camps or {}
				data.camps[camp.key] = true
				unlocked = camp.key
				print(`[camp] {player.Name} reached {camp.name} — its warp is unlocked`)
			end
			if unlocked or worldChanged then
				push(player, available, unlocked)
			end
		end
	end)
end

return CampService
