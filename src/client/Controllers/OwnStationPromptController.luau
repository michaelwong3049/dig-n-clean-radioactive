--!strict
--[[
	OwnStationPromptController.luau — hides a base's "Wash" (cleansing station) prompt
	from everyone but that base's owner. (The treadmill's "Upgrade" prompt it used to
	gate too is gone: TreadmillSignController shows the upgrade sign's buttons to the
	owner only.)

	THE SERVER ALREADY REFUSES IT: StationService treats someone else's tub as no
	station at all, and WashService.begin says "that's someone else's ...". This only
	stops the prompts that were always going to fail
	from showing. LOCAL ONLY — the server's prompts are untouched, and the camps' public
	cleansing stations are not under Workspace.Plots, so they are never touched here.

	The server toggles a tub's prompt itself (off for the length of a wash), and that
	replicates to every client — so a prompt on someone else's base is held off on
	every Enabled change, not just set once. Our own base's prompts are left to the
	server entirely.

	Which plot a prompt is on comes from its Plot<n> ancestor; which plot is ours from
	our RespawnLocation (the plot's PlotSpawn) and Net PlotState. StreamingEnabled: the
	plots stream in and out, so prompts are picked up as they arrive.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)

local OwnStationPromptController = {}

--- prompt name -> the part it hangs off (build/Plots.buildCleansingStation). The
--- treadmill's Upgrade prompt is gone: its sign sells to the owner only (TreadmillSignController).
local GATED: { [string]: string } = { Wash = "Basin" }

local myPlot: number? = nil
local prompts: { [ProximityPrompt]: number } = {}

local function plotIndexOf(row: Instance, inst: Instance): number?
	local node: Instance? = inst
	while node and node.Parent ~= row do
		node = node.Parent
	end
	return if node then tonumber(string.match(node.Name, "^Plot(%d+)$")) else nil
end

local function apply(prompt: ProximityPrompt, index: number)
	if index ~= myPlot and prompt.Enabled then
		prompt.Enabled = false
	end
end

local function onDescendant(row: Instance, inst: Instance)
	if not inst:IsA("ProximityPrompt") then
		return
	end
	local parentName = GATED[inst.Name]
	if parentName == nil or inst.Parent == nil or inst.Parent.Name ~= parentName then
		return
	end
	local index = plotIndexOf(row, inst)
	if index == nil or prompts[inst] then
		return
	end
	prompts[inst] = index
	apply(inst, index)
	inst:GetPropertyChangedSignal("Enabled"):Connect(function()
		apply(inst, index)
	end)
	inst.Destroying:Connect(function()
		prompts[inst] = nil
	end)
end

local function onPlot(index: number?)
	myPlot = index
	for prompt, plot in prompts do
		-- Our own base's prompts go back to whatever the server last said. A prompt we
		-- held off locally never saw the server's value, so it is re-enabled here; the
		-- server's next write (a wash starting) still wins as normal.
		if plot == myPlot then
			prompt.Enabled = true
		else
			apply(prompt, plot)
		end
	end
end

local function watch(row: Instance)
	for _, inst in row:GetDescendants() do
		onDescendant(row, inst)
	end
	row.DescendantAdded:Connect(function(inst)
		onDescendant(row, inst)
	end)
end

--- Our plot from RespawnLocation (assign points it at the plot's PlotSpawn, which
--- carries PlotIndex). PlotState alone is not enough: it is fired once on load and a
--- queued remote event only reaches the first listener to connect, which may not be us.
local function fromSpawn()
	local spawn = Players.LocalPlayer.RespawnLocation
	local index = spawn and spawn:GetAttribute("PlotIndex")
	if type(index) == "number" and index ~= myPlot then
		onPlot(index)
	end
end

function OwnStationPromptController.start()
	Net.get("PlotState").OnClientEvent:Connect(onPlot)
	fromSpawn()
	Players.LocalPlayer:GetPropertyChangedSignal("RespawnLocation"):Connect(fromSpawn)
	local row = Workspace:FindFirstChild("Plots")
	if row then
		watch(row)
	else
		task.spawn(function()
			watch(Workspace:WaitForChild("Plots"))
		end)
	end
end

return OwnStationPromptController
