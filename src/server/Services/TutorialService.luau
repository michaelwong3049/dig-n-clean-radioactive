--!strict
--[[
	TutorialService.lua — the new-player walkthrough (Config/Tutorial). It decides which
	step each player is on and tells their client.

	NOTHING HERE ADVANCES A COUNTER. Four times a second each player still on the
	walkthrough has their step re-read off the real game (`stepFor`): the Bent Coil
	owned, a stand filled, a clean nuke in the bag, a crusted one, locked onto a signal,
	standing in a stage. The first of those that holds, in that order, is the step. That
	is the whole state machine, and it is why a rejoin resumes where you were, and why
	selling or losing the nuke puts you back on "find a spot to dig" rather than
	stranded on a step you can no longer do. The client is sent the step only when it
	changes.

	The save holds one flag, `onboarding` ("active" / "done", DataService). It goes
	"done" when you reach the finish, or on SKIP, and after that this service ignores
	you for good.

	ONE NUDGE, NOT A RAIL: when your first nuke comes out of the ground it is put in
	your hands if they are empty, so "clean the nuke" does not start with a hunt through
	the hotbar. The client is told when the step needs the nuke held and it is not, and
	the banner says so.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tutorial = require(Shared.Config.Tutorial)
local Net = require(Shared.Net)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)
local StageService = require(script.Parent.StageService)
local DigService = require(script.Parent.DigService)
local CarryService = require(script.Parent.CarryService)
local ExhibitService = require(script.Parent.ExhibitService)

local TutorialService = {}

local TICK_HZ = 4

local stateRemote: any = nil
--- The last payload signature each player was sent, so an unchanged step costs a
--- string compare and not a remote.
local lastSent: { [Player]: string } = {}

local function ownsTier(data: any, tier: number): boolean
	local owned = data.gearOwned and data.gearOwned.detector
	if owned == nil then
		return (data.gear.detector or 1) >= tier
	end
	for _, t in owned do
		if t >= tier then
			return true
		end
	end
	return false
end

--- The first carried nuke that is still crusted, and the first that is clean.
local function carried(data: any): (any?, any?)
	local crusted, clean = nil, nil
	for _, item in data.carry do
		if #(item.patches or {}) > 0 then
			crusted = crusted or item
		else
			clean = clean or item
		end
	end
	return crusted, clean
end

--- Which step this player is on right now, and whether the nuke that step needs is
--- in their hands. Checked from the END of the walk backwards: whatever they have
--- already achieved wins over anything earlier.
function TutorialService.stepFor(player: Player, data: any): (Tutorial.StepId, boolean)
	if ownsTier(data, Tutorial.UPGRADE_TIER) then
		return "finish", true
	end
	if #data.exhibit.pedestals > 0 then
		return "upgrade", true
	end
	local crusted, clean = carried(data)
	if clean then
		return "place", data.heldUid ~= "" and data.heldUid == clean.uid
	end
	if crusted then
		return "clean", data.heldUid ~= "" and data.heldUid == crusted.uid
	end
	if DigService.isLocked(player) then
		return "haul", true
	end
	if StageService.stageOf(player) ~= nil then
		return "dig", true
	end
	return "stage", true
end

local function send(player: Player, payload: any)
	local signature = if payload == nil then "" else `{payload.step}:{payload.holding}:{payload.plot}`
	if lastSent[player] == signature then
		return
	end
	lastSent[player] = signature
	stateRemote:FireClient(player, payload)
end

local function stepPlayer(player: Player)
	local data = DataService.data(player)
	if data == nil or data.onboarding ~= "active" then
		return
	end

	local previous = lastSent[player]
	local step, holding = TutorialService.stepFor(player, data)

	-- The nudge from the header: the dig just finished, so the new nuke goes into your hands.
	if step == "clean" and not holding and previous ~= nil and string.sub(previous, 1, 5) == "haul:" and data.heldUid == "" then
		local crusted = carried(data)
		if crusted and CarryService.hold(player, crusted.uid) then
			holding = true
		end
	end

	if step == "finish" then
		data.onboarding = "done"
		print(`[tutorial] {player.Name} finished the walkthrough`)
	end
	-- `plot` rides along because the trail points at YOUR cleansing station and YOUR
	-- stands, and PlotState fires once on assignment, before this controller may be
	-- listening.
	send(player, { step = step, holding = holding, plot = ExhibitService.plotOf(player) })
end

function TutorialService.init()
	stateRemote = Net.get("TutorialState")
end

function TutorialService.start()
	Net.get("TutorialAction").OnServerEvent:Connect(function(player: Player, verb: any)
		if verb ~= "skip" then
			return
		end
		local data = DataService.data(player)
		if data == nil or data.onboarding ~= "active" then
			return
		end
		data.onboarding = "done"
		print(`[tutorial] {player.Name} skipped the walkthrough`)
		send(player, nil)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
	end)

	Ticker.every(TICK_HZ, function()
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player)
			if not ok then
				warn(`[tutorial] tick failed for {player.Name}: {err}`)
			end
		end
	end, "Tutorial")
end

return TutorialService
