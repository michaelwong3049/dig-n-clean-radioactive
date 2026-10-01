--!strict
--[[
	FloorSignController.luau — hides the "Build Floor N" prompt on a base that
	is not your own.

	THE SERVER ALREADY REFUSES THIS (ExhibitService.buyFloor: "that isn't your
	base"), and by design every other world prompt is left open to everyone and
	lets the service refuse cleanly (see ExhibitService.renderStand's note on
	why a stand's prompt does not gate by ownership either). A floor sign is
	the one exception: "Press E — Build Floor N — $X" sitting in full view on
	someone else's base reads as a live offer, not a decoration, so this hides
	it from anyone it is not for. LOCAL ONLY — the server's prompt, and its own
	refusal, are both untouched; this just stops the ones that were always
	going to fail from ever showing.

	FLOOR_TAG matches build/Kit.FLOOR_TAG's value ("BuyFloor"), repeated rather
	than required — same call ExhibitService makes: Services (and now this
	controller) never depend on build/.

	Each board carries PlotIndex (build/Plots.buildFloorSign). Net PlotState
	tells this client its OWN plot index once, on assign — the same signal
	BaseMarkerController reads for the "YOUR BASE" beacon.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local FloorSignController = {}

local FLOOR_TAG = "BuyFloor"

local myPlot: number? = nil
local boards: { [Instance]: ProximityPrompt } = {}

local function apply(board: Instance, prompt: ProximityPrompt)
	local plot = board:GetAttribute("PlotIndex")
	prompt.Enabled = type(plot) == "number" and plot == myPlot
end

local function onBoard(board: Instance)
	local prompt = board:FindFirstChildOfClass("ProximityPrompt")
	if prompt == nil then
		return
	end
	boards[board] = prompt
	apply(board, prompt)
	board.Destroying:Connect(function()
		boards[board] = nil
	end)
end

local function onPlot(index: number?)
	myPlot = index
	for board, prompt in boards do
		apply(board, prompt)
	end
end

function FloorSignController.start()
	for _, board in CollectionService:GetTagged(FLOOR_TAG) do
		onBoard(board)
	end
	CollectionService:GetInstanceAddedSignal(FLOOR_TAG):Connect(onBoard)
	Net.get("PlotState").OnClientEvent:Connect(onPlot)
end

return FloorSignController
