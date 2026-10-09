--!strict
--[[
	TutorialService.lua — the new-player walkthrough (Config/Tutorial). It decides which
	step each player is on and tells their client.

	NOTHING HERE ADVANCES A COUNTER. Four times a second each player still on the
	walkthrough has their step re-read off the real game (`stepFor`): the Bent Coil
	owned, a stand filled and the $15 for the Bent Coil in hand, a stand filled, a clean nuke in the bag, a crusted one, locked onto a signal,
	standing in a stage. The first of those that holds, in that order, is the step. That
	is the whole state machine, and it is why a rejoin resumes where you were, and why
	selling or losing the nuke puts you back on "find a spot to dig" rather than
	stranded on a step you can no longer do. The client is sent the step only when it
	changes.

	The save holds one flag, `onboarding` ("active" / "done", DataService). It goes
	"done" on the last step ("navigate": the HOME / SHOPS buttons) when you use one of
	them (WarpService calls TutorialService.complete) or after Tutorial.NAVIGATE_SECONDS,
	or on SKIP, and after that this service ignores you for good.

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
--- os.clock() each player reached the "navigate" step, for its timeout.
local navigateSince: { [Player]: number } = {}

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
		return "navigate", true
	end
	if #data.exhibit.pedestals > 0 then
		-- "Earn $15" until the stand has paid for the Bent Coil. Nothing else can be
		-- bought on the walkthrough, so cash is the count.
		return if data.cash >= Tutorial.EARN_TARGET then "upgrade" else "earn", true
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
	local signature = if payload == nil then "" else `{payload.step}:{payload.holding}:{payload.plot}:{payload.earned}`
	if lastSent[player] == signature then
		return
	end
	lastSent[player] = signature
	stateRemote:FireClient(player, payload)
end

local function stepPlayer(player: Player)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	-- WarpController keeps HOME / SHOPS off screen while this is true (WarpService
	-- refuses them too). Read off the save every tick so skip / finish flip it.
	player:SetAttribute("TutorialActive", data.onboarding == "active")
	if data.onboarding ~= "active" then
		player:SetAttribute("TutorialStep", nil)
		navigateSince[player] = nil
		-- Ended outside this tick (a warp on the last step, /tutorial off): clear the
		-- client's banner. `send` drops it if the client was already cleared.
		if lastSent[player] ~= nil then
			send(player, nil)
		end
		return
	end

	local previous = lastSent[player]
	local step, holding = TutorialService.stepFor(player, data)
	-- Tutorial.stationOpen / promptOpen read this to open the Detector shop on "upgrade".
	player:SetAttribute("TutorialStep", step)

	-- The nudge from the header: the dig just finished, so the new nuke goes into your hands.
	if step == "clean" and not holding and previous ~= nil and string.sub(previous, 1, 5) == "haul:" and data.heldUid == "" then
		local crusted = carried(data)
		if crusted and CarryService.hold(player, crusted.uid) then
			holding = true
		end
	end

	-- The last step ends itself if neither HOME nor SHOPS gets pressed.
	if step == "navigate" then
		local since = navigateSince[player]
		if since == nil then
			navigateSince[player] = os.clock()
		elseif os.clock() - since >= Tutorial.NAVIGATE_SECONDS then
			TutorialService.complete(player)
			return
		end
	else
		navigateSince[player] = nil
	end
	-- `plot` rides along because the trail points at YOUR cleansing station and YOUR
	-- stands, and PlotState fires once on assignment, before this controller may be
	-- listening.
	-- `earned` is the "earn" step's live "$N/$15" count, so it re-sends as cash comes in.
	local earned = if step == "earn" then math.clamp(math.floor(data.cash), 0, Tutorial.EARN_TARGET) else nil
	send(player, { step = step, holding = holding, plot = ExhibitService.plotOf(player), earned = earned })
end

--- End the walkthrough from its last step ("navigate"). WarpService calls this when a
--- HOME / SHOPS warp lands; the step's own timeout calls it too. Does nothing on any
--- earlier step, so a stray call cannot cut a walkthrough short.
function TutorialService.complete(player: Player)
	local data = DataService.data(player)
	if data == nil or data.onboarding ~= "active" or player:GetAttribute("TutorialStep") ~= "navigate" then
		return
	end
	data.onboarding = "done"
	navigateSince[player] = nil
	player:SetAttribute("TutorialActive", false)
	player:SetAttribute("TutorialStep", nil)
	print(`[tutorial] {player.Name} finished the walkthrough`)
	send(player, nil)
end

--- End the walkthrough from any step. No button does this any more (ON REQUEST, new
--- players always walk it through); DebugService's /skip calls it. True when there
--- was a walkthrough to end.
function TutorialService.skip(player: Player): boolean
	local data = DataService.data(player)
	if data == nil or data.onboarding ~= "active" then
		return false
	end
	data.onboarding = "done"
	navigateSince[player] = nil
	player:SetAttribute("TutorialActive", false)
	player:SetAttribute("TutorialStep", nil)
	print(`[tutorial] {player.Name} skipped the walkthrough`)
	send(player, nil)
	return true
end

function TutorialService.init()
	stateRemote = Net.get("TutorialState")
end

function TutorialService.start()
	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
		navigateSince[player] = nil
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
