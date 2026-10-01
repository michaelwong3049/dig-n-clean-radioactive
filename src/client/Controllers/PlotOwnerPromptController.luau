--!strict
--[[
	PlotOwnerPromptController.luau — hides world prompts that only ever do
	anything on your OWN base, from anyone it is not for.

	THE SERVER ALREADY REFUSES THESE: ExhibitService.buyFloor ("that isn't
	your base") and DeconService's locker verbs ("that happens at your own
	locker") both let anyone press the prompt and refuse cleanly -- the
	documented pattern for every world prompt in this game (see
	ExhibitService.renderStand's note on why a display stand's own prompt is
	NOT gated this way). A floor sign and a locker's "Open" are the two
	exceptions: both read as a live offer on someone else's base, not a
	decoration, so they are hidden here instead. LOCAL ONLY -- the server's
	prompt, and its refusal, are both untouched.

	NOT THE TREADMILL. TreadmillService's "Upgrade Treadmill" stays visible
	everywhere, on purpose -- "WHOSE BELT DOES NOT MATTER" is the explicit,
	load-bearing rule that lets a player with no plot this session (all six
	taken) still train Speed at someone else's base instead of being locked
	out of a whole progression track. Pressing it there spends YOUR OWN
	money on YOUR OWN tier regardless of whose belt it is -- nothing about
	the plot it stands on is ever touched -- so hiding it would regress a
	feature that is shared on purpose, not a refusal waiting to happen.

	FLOOR_TAG/STATION_TAG match build/Kit's values ("BuyFloor"/"Station"),
	repeated rather than required -- the same call every Service here makes
	(build/ is never a dependency of anything outside itself).

	Each gated instance carries PlotIndex (build/Plots.buildFloorSign,
	Plots.lockerStation). Net PlotState tells this client its OWN plot index
	once, on assign -- the same signal BaseMarkerController reads for the
	"YOUR BASE" beacon.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local PlotOwnerPromptController = {}

local FLOOR_TAG = "BuyFloor"
local STATION_TAG = "Station"

local myPlot: number? = nil
local gated: { [Instance]: ProximityPrompt } = {}

local function apply(instance: Instance, prompt: ProximityPrompt)
	local plot = instance:GetAttribute("PlotIndex")
	prompt.Enabled = type(plot) == "number" and plot == myPlot
end

local function track(instance: Instance, prompt: ProximityPrompt)
	gated[instance] = prompt
	apply(instance, prompt)
	instance.Destroying:Connect(function()
		gated[instance] = nil
	end)
end

local function onFloorSign(board: Instance)
	local prompt = board:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		track(board, prompt)
	end
end

--- Station-tagged covers shop/locker/pedestal/treadmill alike (anything carrying
--- StationKind); only the locker's "Open" is gated here -- see header for why the
--- pedestal's own prompt and the treadmill are both left alone on purpose.
local function onStation(part: Instance)
	if part:GetAttribute("StationKind") ~= "locker" then
		return
	end
	local prompt = part:FindFirstChild("OpenLocker")
	if prompt and prompt:IsA("ProximityPrompt") then
		track(part, prompt)
	end
end

local function onPlot(index: number?)
	myPlot = index
	for instance, prompt in gated do
		apply(instance, prompt)
	end
end

function PlotOwnerPromptController.start()
	for _, board in CollectionService:GetTagged(FLOOR_TAG) do
		onFloorSign(board)
	end
	CollectionService:GetInstanceAddedSignal(FLOOR_TAG):Connect(onFloorSign)

	for _, part in CollectionService:GetTagged(STATION_TAG) do
		onStation(part)
	end
	CollectionService:GetInstanceAddedSignal(STATION_TAG):Connect(onStation)

	Net.get("PlotState").OnClientEvent:Connect(onPlot)
end

return PlotOwnerPromptController
