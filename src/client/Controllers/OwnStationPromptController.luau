--!strict
--[[
	OwnStationPromptController.luau — hides a base's "Wash" (cleansing station) and Hoses
	pad prompts from everyone but that base's owner. (The treadmill's "Upgrade" prompt it used to
	gate too is gone, with the treadmill.)

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

	It also hangs a white "CLEANING" label over OUR tub only (and "HOSES" over our pad) — a billboard in our own
	PlayerGui, so nobody else ever sees it and we never see one over theirs. It hides
	while our Wash prompt is off (the server holds it off for the length of a wash), so
	it is not floating in the wash shot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)

local OwnStationPromptController = {}

--- prompt name -> the part it hangs off: the tub's "Wash" (build/Plots.buildCleansingStation)
--- and the Hoses pad's "ViewShop" (build/Plots.ensureHosePad). A booth stand's ViewShop
--- hangs off a "Stand", so it is never caught here.
local GATED: { [string]: string } = { Wash = "Basin", ViewShop = "Pad" }

local myPlot: number? = nil
local prompts: { [ProximityPrompt]: number } = {}

--- The white labels over our own base's machines, one per gated prompt: "CLEANING"
--- over the tub, "HOSES" over the Hoses pad. Studs wide/tall, and how far above the
--- part's centre each floats.
local LABELS: { [string]: { text: string, size: UDim2, height: number } } = {
	Wash = { text = "CLEANING", size = UDim2.fromScale(14, 3), height = 9 },
	ViewShop = { text = "HOSES", size = UDim2.fromScale(10, 2.4), height = 5 },
}

local labels: { [string]: BillboardGui } = {}

local function buildLabel(promptName: string): BillboardGui
	local look = LABELS[promptName]
	local gui = Instance.new("BillboardGui")
	gui.Name = if promptName == "Wash" then "CleaningStationLabel" else `{look.text}Label`
	gui.Size = look.size
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBlack
	text.Text = look.text
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 1
	text.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = text
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

--- Point each label at our own base's part (if it has streamed in), shown only while
--- its prompt is on (the tub's goes off during a wash).
local function refreshLabel()
	for promptName, gui in labels do
		local mine: ProximityPrompt? = nil
		for prompt, plot in prompts do
			if plot == myPlot and prompt.Name == promptName then
				mine = prompt
				break
			end
		end
		local part = mine and mine.Parent
		if part and part:IsA("BasePart") then
			gui.Adornee = part
			-- StudsOffsetWorldSpace is in the ADORNEE's axes, and the Basin is a Cylinder
			-- turned to stand up (Kit.R.cylUp), so its own Y points sideways: take world up
			-- into its space or the label sits beside the tub at floor height.
			gui.StudsOffsetWorldSpace = part.CFrame:VectorToObjectSpace(Vector3.new(0, LABELS[promptName].height, 0))
		else
			gui.Adornee = nil
		end
		gui.Enabled = mine ~= nil and gui.Adornee ~= nil and mine.Enabled
	end
end

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
		refreshLabel()
	end)
	inst.Destroying:Connect(function()
		prompts[inst] = nil
		refreshLabel()
	end)
	refreshLabel()
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
	refreshLabel()
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
	for promptName in LABELS do
		labels[promptName] = buildLabel(promptName)
	end
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
