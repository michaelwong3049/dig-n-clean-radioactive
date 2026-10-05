--[[
	FastModeController — FAST MODE (Settings > Graphics, the `fastMode` pref): while it
	is on, the nukes standing on OTHER players' bases are hidden from you, along with
	their effects, so a busy server has far less to draw. Your own base is untouched.
	SUPER FAST MODE (the `superFast` pref) adds YOUR nukes to the hidden ones, while FAST MODE
	is on; the name cards over them stay, because they are not part of the model.
	(Their name cards are StandCardController's and every nuke's effects ItemFxController's;
	both read the same pref. Auras have their own SHOW AURAS setting, AuraController's.)

	WHAT COUNTS AS A NUKE ON A BASE is any Model named "ItemModel" under Workspace.Plots
	(ExhibitService puts one on each Display stand and each locker slot). Which base it
	is on comes from its Plot<n> ancestor; which base is ours from our RespawnLocation
	(the plot's PlotSpawn, which carries PlotIndex) and Net PlotState, as
	OwnStationPromptController reads it. Until we know which is ours everything is
	treated as someone else's, and our own comes back the moment we do.

	HIDING IS LOCAL AND REVERSIBLE. Nothing is destroyed or reparented (the server owns
	these models): parts get LocalTransparencyModifier 1, decals go transparent, and
	emitters, beams, trails, lights, billboards and highlights are turned off -- the
	effects ItemFxController adds on this client included, which is why a model's
	DescendantAdded is watched for as long as it is hidden. Every value is saved first and
	put back when FAST MODE is turned off or the model turns out to be ours.

	THE BASES' OWN LIGHTS GO TOO. Every plot carries a set of lights of its own (and the
	Apron beside the plots a bigger set), none of them inside an ItemModel. Each lit light
	is paid for every frame, and a warp loads dozens at once, so while FAST MODE is on
	every light under Workspace.Plots that is not on YOUR plot is switched off (the Apron
	belongs to no plot, so its lights go off too), and put back exactly as they were
	when it is turned off or the plot turns out to be ours.

	StreamingEnabled: bases stream in and out, so models are picked up as they arrive and
	forgotten as they leave.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)

local Prefs = require(script.Parent.Parent.Prefs)

local FastModeController = {}

type Saved = { prop: string, value: any }

type Hidden = {
	saved: { [Instance]: Saved },
	conns: { RBXScriptConnection },
}

local enabled = false
-- SUPER FAST MODE: an add-on to FAST MODE that hides your own nukes as well.
local superFast = false
local myPlot: number? = nil
-- ItemModel -> the plot it stands on, for every one we are tracking.
local models: { [Model]: number } = {}
local hidden: { [Model]: Hidden } = {}

type PlotLight = { plot: number?, wasOn: boolean, guard: RBXScriptConnection? }
-- Every base/Apron light that is not inside an ItemModel (those are hidden with it).
local lights: { [Light]: PlotLight } = {}

--- Classes whose `Enabled` is the whole effect.
local SWITCHED = {
	"ParticleEmitter",
	"Beam",
	"Trail",
	"Light",
	"Fire",
	"Smoke",
	"Sparkles",
	"BillboardGui",
	"SurfaceGui",
	"Highlight",
}

local function plotIndexOf(row: Instance, inst: Instance): number?
	local node: Instance? = inst
	while node and node.Parent ~= row do
		node = node.Parent
	end
	return if node then tonumber(string.match(node.Name, "^Plot(%d+)$")) else nil
end

local function isSwitched(inst: Instance): boolean
	for _, class in SWITCHED do
		if inst:IsA(class) then
			return true
		end
	end
	return false
end

--- Hides one instance of a hidden model, remembering what it was.
local function hideInstance(record: Hidden, inst: Instance)
	if record.saved[inst] ~= nil then
		return
	end
	if inst:IsA("BasePart") then
		record.saved[inst] = { prop = "LocalTransparencyModifier", value = inst.LocalTransparencyModifier }
		inst.LocalTransparencyModifier = 1
	elseif inst:IsA("Decal") then
		record.saved[inst] = { prop = "Transparency", value = inst.Transparency }
		inst.Transparency = 1
	elseif isSwitched(inst) then
		local effect = inst :: any
		record.saved[inst] = { prop = "Enabled", value = effect.Enabled }
		effect.Enabled = false
		-- An effect something else turns back on (ItemFxController) is turned off again.
		table.insert(
			record.conns,
			inst:GetPropertyChangedSignal("Enabled"):Connect(function()
				if effect.Enabled then
					effect.Enabled = false
				end
			end)
		)
	end
end

local function hideModel(model: Model)
	if hidden[model] then
		return
	end
	local record: Hidden = { saved = {}, conns = {} }
	hidden[model] = record
	for _, inst in model:GetDescendants() do
		hideInstance(record, inst)
	end
	table.insert(
		record.conns,
		model.DescendantAdded:Connect(function(inst)
			hideInstance(record, inst)
		end)
	)
end

local function showModel(model: Model)
	local record = hidden[model]
	if record == nil then
		return
	end
	hidden[model] = nil
	for _, conn in record.conns do
		conn:Disconnect()
	end
	for inst, saved in record.saved do
		if inst.Parent then
			(inst :: any)[saved.prop] = saved.value
		end
	end
end

--- Hide the model if FAST MODE is on and it is someone else's, else show it.
local function refresh(model: Model)
	local plot = models[model]
	if plot ~= nil and enabled and (plot ~= myPlot or superFast) then
		hideModel(model)
	else
		showModel(model)
	end
end

local function track(row: Instance, model: Model)
	if models[model] ~= nil then
		return
	end
	local plot = plotIndexOf(row, model)
	if plot == nil then
		return
	end
	models[model] = plot
	model.Destroying:Connect(function()
		showModel(model)
		models[model] = nil
	end)
	refresh(model)
end

--- Switch one base light off (FAST MODE, not ours) or put it back.
local function refreshLight(light: Light)
	local record = lights[light]
	if record == nil then
		return
	end
	if enabled and record.plot ~= myPlot then
		if record.guard == nil then
			record.wasOn = light.Enabled
			light.Enabled = false
			-- Something else turning it back on is turned off again.
			record.guard = light:GetPropertyChangedSignal("Enabled"):Connect(function()
				if light.Enabled then
					light.Enabled = false
				end
			end)
		end
	elseif record.guard then
		record.guard:Disconnect()
		record.guard = nil
		light.Enabled = record.wasOn
	end
end

local function trackLight(row: Instance, light: Light)
	if lights[light] ~= nil or light:FindFirstAncestor("ItemModel") then
		return
	end
	lights[light] = { plot = plotIndexOf(row, light), wasOn = light.Enabled, guard = nil }
	light.Destroying:Connect(function()
		local record = lights[light]
		if record and record.guard then
			record.guard:Disconnect()
		end
		lights[light] = nil
	end)
	refreshLight(light)
end

local function onDescendant(row: Instance, inst: Instance)
	if inst:IsA("Model") and inst.Name == "ItemModel" then
		track(row, inst)
	elseif inst:IsA("Light") then
		trackLight(row, inst)
	end
end

local function refreshAll()
	for model in models do
		refresh(model)
	end
	for light in lights do
		refreshLight(light)
	end
end

local function onPlot(index: number?)
	if index == myPlot then
		return
	end
	myPlot = index
	refreshAll()
end

--- Our plot from RespawnLocation (assign points it at the plot's PlotSpawn, which
--- carries PlotIndex). PlotState alone is not enough: it is fired once on load and a
--- queued remote event only reaches the first listener to connect, which may not be us.
local function fromSpawn()
	local spawn = Players.LocalPlayer.RespawnLocation
	local index = spawn and spawn:GetAttribute("PlotIndex")
	if type(index) == "number" then
		onPlot(index)
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

function FastModeController.start()
	Net.get("PlotState").OnClientEvent:Connect(onPlot)
	fromSpawn()
	Players.LocalPlayer:GetPropertyChangedSignal("RespawnLocation"):Connect(fromSpawn)

	Prefs.observe("fastMode", function(on)
		enabled = on == true
		refreshAll()
	end)
	Prefs.observe("superFast", function(on)
		superFast = on == true
		refreshAll()
	end)

	local row = Workspace:FindFirstChild("Plots")
	if row then
		watch(row)
	else
		task.spawn(function()
			watch(Workspace:WaitForChild("Plots"))
		end)
	end
end

return FastModeController
