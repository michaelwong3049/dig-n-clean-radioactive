--!strict
--[[
	PlacementController.luau — put the nuke in your hands down anywhere on your base.

	A BASE IS ONE OPEN FLOOR (Config/BaseUpgrades). While you hold a clean nuke and your
	cursor is over your OWN base's floor, a see-through copy of it follows the cursor,
	standing on a ring the size of the room it needs: green where it fits, red where it
	does not (off the floor, too close to another nuke, or the base already full). Click
	(or tap, on a phone) and PlaceNuke asks the server to put it there.

	THE GHOST IS BUILT THE WAY THE SERVER BUILDS THE REAL THING (Shared/NukeDisplay), and
	is checked with the same Shared/Placement rules, so green here means the server will
	say yes. The other nukes on the floor are read off the plot's PlacedNukes anchors
	(their `PlaceRadius` attribute is the circle the server saved), the floor's depth off
	the plot's `BaseLevel` attribute (build/Plots.setLevel).

	WHICH PLOT IS OURS comes from RespawnLocation (its PlotSpawn carries PlotIndex), with
	Net PlotState as well (same reason OwnStationPromptController gives). The plot's
	frame comes from the same PlotSpawn: build/Plots stands it at plot-local (0, -24)
	with no turn of its own, so its CFrame is the pad's frame shifted 24 studs forward.

	WHAT THE HELD MODEL IS comes from ToolService's "HeldItem" attributes (ItemId, Uid,
	Modifier, Crust). A crusted nuke (Crust > 0) or a crate shows no ghost: neither can
	be displayed, and the server would only refuse it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local BaseUpgrades = require(Shared.Config.BaseUpgrades)
local Placement = require(Shared.Placement)
local NukeDisplay = require(Shared.NukeDisplay)
local ItemModels = require(Shared.ItemModels)

local PlacementController = {}

local HELD_ITEM_NAME = "HeldItem" -- ToolService's name for whatever is in your hands
local SPAWN_Z = -24 -- PlotSpawn's plot-local z (build/Plots)
local GHOST_ALPHA = 0.55
local RING_ALPHA = 0.35
local OK_COLOR = Color3.fromHex("5BE36B")
local BAD_COLOR = Color3.fromHex("FF5A5A")
local RAY_LENGTH = 400
-- Parts a ray may land on to count as "your floor".
local FLOOR_PARTS = { PadFloor = true, ExtensionFloor = true }

local myPlot: number? = nil
local placeRemote: RemoteEvent = nil

type Ghost = {
	key: string, -- what it was built for, so a new held item rebuilds it
	folder: Model,
	model: Model?,
	ring: Part,
	label: TextLabel,
	r: number,
}
local ghost: Ghost? = nil
-- The spot the ghost is on right now, and whether it fits there; nil when hidden.
local current: { x: number, z: number, ok: boolean }? = nil

local function plotModel(): Instance?
	local row = Workspace:FindFirstChild("Plots")
	return if row and myPlot then row:FindFirstChild(`Plot{myPlot}`) else nil
end

--- The pad-local frame of our plot, from its PlotSpawn.
local function plotFrame(plot: Instance): CFrame?
	local spawn = plot:FindFirstChild("PlotSpawn", true)
	if spawn == nil or not spawn:IsA("BasePart") then
		return nil
	end
	local pad = plot:FindFirstChild("PadFloor", true)
	local topY = if pad and pad:IsA("BasePart") then pad.Position.Y + pad.Size.Y / 2 else spawn.Position.Y - 0.5
	local flat = spawn.CFrame - spawn.CFrame.Position
	return CFrame.new(spawn.Position.X, topY, spawn.Position.Z) * flat * CFrame.new(0, 0, -SPAWN_Z)
end

local function held(): Model?
	local character = Players.LocalPlayer.Character
	local model = character and character:FindFirstChild(HELD_ITEM_NAME)
	return if model and model:IsA("Model") then model else nil
end

local function clearGhost()
	if ghost then
		ghost.folder:Destroy()
		ghost = nil
	end
	current = nil
end

local function buildGhost(itemId: string, uid: string?, modifier: string?): Ghost
	local folder = Instance.new("Model")
	folder.Name = "PlacementGhost"

	local model, r = NukeDisplay.create(itemId, uid, modifier)
	if model then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				d.Transparency = 1 - (1 - d.Transparency) * (1 - GHOST_ALPHA)
			elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Beam") or d:IsA("Trail") then
				d:Destroy()
			end
		end
		model.Parent = folder
	else
		ItemModels.request({ itemId })
	end

	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.12, r * 2, r * 2)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Transparency = RING_ALPHA
	ring.Parent = folder

	local gui = Instance.new("BillboardGui")
	gui.Name = "Hint"
	gui.Size = UDim2.fromOffset(240, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = ring
	gui.Parent = folder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui

	folder.Parent = Workspace
	return {
		key = `{itemId}|{uid or ""}|{modifier or ""}|{model ~= nil}`,
		folder = folder,
		model = model,
		ring = ring,
		label = label,
		r = r,
	}
end

--- Every placed nuke on our plot, in plot-local space.
local function spotsOn(plot: Instance, frame: CFrame): { Placement.Spot }
	local spots = {}
	local folder = plot:FindFirstChild("PlacedNukes")
	if folder == nil then
		return spots
	end
	for _, anchor in folder:GetChildren() do
		if anchor:IsA("BasePart") then
			local p = frame:PointToObjectSpace(anchor.Position)
			local r = anchor:GetAttribute("PlaceRadius")
			table.insert(spots, { x = p.X, z = p.Z, r = if type(r) == "number" then r else Placement.MIN_RADIUS })
		end
	end
	return spots
end

--- The point on our own floor under a screen position, or nil.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function floorUnder(screen: Vector2, plot: Instance): Vector3?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	if ghost then
		table.insert(ignore, ghost.folder)
	end
	local placed = plot:FindFirstChild("PlacedNukes")
	if placed then
		table.insert(ignore, placed)
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, rayParams)
	if hit and FLOOR_PARTS[hit.Instance.Name] and hit.Instance:IsDescendantOf(plot) then
		return hit.Position
	end
	return nil
end

--- Move the ghost to the floor under `screen` and work out whether it fits there.
--- Hides it (and returns false) when there is nothing to place or no floor there.
local function update(screen: Vector2): boolean
	local plot = plotModel()
	local model = held()
	local itemId = model and model:GetAttribute("ItemId")
	local crust = model and model:GetAttribute("Crust")
	if plot == nil or model == nil or type(itemId) ~= "string" or (type(crust) == "number" and crust > 0) then
		clearGhost()
		return false
	end
	local frame = plotFrame(plot)
	local at = frame and floorUnder(screen, plot)
	if frame == nil or at == nil then
		clearGhost()
		return false
	end

	local uid = model:GetAttribute("Uid")
	local modifier = model:GetAttribute("Modifier")
	local u = if type(uid) == "string" then uid else nil
	local m = if type(modifier) == "string" then modifier else nil
	local wantModel = ItemModels.ready(itemId)
	local key = `{itemId}|{u or ""}|{m or ""}|{wantModel}`
	if ghost == nil or ghost.key ~= key then
		clearGhost()
		ghost = buildGhost(itemId, u, m)
	end
	local g = ghost :: Ghost

	local p = frame:PointToObjectSpace(at)
	local level = plot:GetAttribute("BaseLevel")
	local area = Placement.area(if type(level) == "number" then level else 0)
	local spots = spotsOn(plot, frame)
	local cap = BaseUpgrades.capFor(if type(level) == "number" then level else 0)
	local why: string? = nil
	if #spots >= cap then
		why = "Base full - upgrade it"
	else
		why = Placement.why(area, spots, p.X, p.Z, g.r)
	end
	local ok = why == nil

	local spot = frame * CFrame.new(p.X, 0, p.Z)
	if g.model then
		g.model:PivotTo(spot + Vector3.new(0, 0.03, 0))
	end
	g.ring.CFrame = spot * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90))
	g.ring.Color = if ok then OK_COLOR else BAD_COLOR
	g.label.Text = if ok
		then (if UserInputService.TouchEnabled then "Tap to place" else "Click to place")
		else (why :: string):sub(1, 1):upper() .. (why :: string):sub(2)
	g.label.TextColor3 = if ok then Color3.new(1, 1, 1) else BAD_COLOR
	current = { x = p.X, z = p.Z, ok = ok }
	return true
end

local function tryPlace(screen: Vector2)
	if not update(screen) then
		return
	end
	local c = current
	if c and c.ok then
		placeRemote:FireServer(c.x, c.z)
	end
end

local function onPlot(index: number?)
	myPlot = index
end

local function fromSpawn()
	local spawn = Players.LocalPlayer.RespawnLocation
	local index = spawn and spawn:GetAttribute("PlotIndex")
	if type(index) == "number" and index ~= myPlot then
		onPlot(index)
	end
end

function PlacementController.start()
	placeRemote = Net.get("PlaceNuke")
	Net.get("PlotState").OnClientEvent:Connect(onPlot)
	fromSpawn()
	Players.LocalPlayer:GetPropertyChangedSignal("RespawnLocation"):Connect(fromSpawn)

	-- The ghost follows the mouse on a desktop. On touch there is no hover: the ghost
	-- appears where you tap, and a tap on a free spot places straight away.
	RunService.RenderStepped:Connect(function()
		if UserInputService.MouseEnabled then
			update(UserInputService:GetMouseLocation())
		elseif ghost and held() == nil then
			clearGhost()
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		tryPlace(UserInputService:GetMouseLocation())
	end)
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
		if processed then
			return
		end
		-- TouchTapInWorld is in screen space without the top-bar inset; the ray maths
		-- (ViewportPointToRay) wants it with, the same as GetMouseLocation.
		tryPlace(position + Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y))
	end)
end

return PlacementController
