--!strict
--[[
	BaseMarkerController.luau — the floating avatar plate over every claimed base.

	One plate per plot, high over the pad's centre: a circular headshot "orb" that
	bobs gently, the owner's display name in their own casing (no upper-casing — a
	name like "MattM" stays "MattM"), and what that base earns per second under it.

	DRAWN HERE, NOT ON THE SERVER. It used to be two markers stacked in the same spot
	— a server-built plate everyone saw plus a client-only "YOUR BASE" beacon over
	your own plot. A server-built BillboardGui is a fixed number of pixels on every
	screen (huge on a phone, tiny on a 4K monitor), so the plate is now built per
	client on UIKit.billboardCanvas and scales with the rest of the HUD. The server
	only stamps each Plot model with attributes (ExhibitService.renderName /
	pushIncome):

	    OwnerUserId  number, 0 when unclaimed (no plate)
	    OwnerName    the owner's DisplayName
	    OwnerRate    their stands' cash per second

	The orb's ring follows the plot's accent, read straight off its Trim part, so a
	base colour change in Settings repaints it live.

	HIDDEN INSIDE A STAGE. It is a safe-zone wayfinding aid — once you step into a
	field the AlwaysOnTop plates would just hang over the hazard. Toggled off
	`ExposureState.stageId` (nil = safe zone), the signal WarpController uses too.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local BaseMarker = {}

local PLATE_NAME = "BasePlate"
local FONT = Enum.Font.GothamBlack -- UIKit.House.font
local NAME_COLOR = Color3.fromHex("7CF24A") -- bright cash green, like the HUD's money
local RATE_COLOR = Color3.fromHex("FFF6D6") -- warm cream so the number reads apart from the name
local OUTLINE = Color3.fromHex("14161A")
local FACE_FILL = Color3.fromHex("1E2A22") -- shows for the beat before the thumbnail loads
local ACCENT_FALLBACK = Color3.fromHex("7CF24A") -- if the plot has no Trim to read a colour off

-- How far away a plate stays drawn (camera-to-plate, studs). Your own reads from
-- anywhere on the plaza; other players' from about the far side of the ring.
local OWN_REACH = 600
local OTHER_REACH = 400

-- Design-pixel footprint; UIKit.billboardCanvas multiplies it by the HUD scale.
local CANVAS = Vector2.new(200, 160)
local ORB = 84 -- outer diameter, outline included
local BOB = 4 -- design px the orb floats up and down
local BOB_SECONDS = 1.6

local plates: { [Instance]: BillboardGui } = {}
local inStage = false

--- "$35/s" up to "$1.2T/s" — the same ladder the hotbar card prints.
local function formatRate(perSecond: number): string
	if perSecond >= 1_000_000_000_000 then
		return string.format("$%.1fT/s", perSecond / 1_000_000_000_000)
	elseif perSecond >= 1_000_000_000 then
		return string.format("$%.1fB/s", perSecond / 1_000_000_000)
	elseif perSecond >= 1_000_000 then
		return string.format("$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 1000 then
		return string.format("$%.1fK/s", perSecond / 1000)
	end
	return string.format("$%d/s", math.floor(perSecond))
end

local function accentOf(plot: Instance): Color3
	local trim = plot:FindFirstChild("Trim")
	if trim and trim:IsA("BasePart") then
		return trim.Color
	end
	return ACCENT_FALLBACK
end

local function circle(parent: Instance, name: string, size: number, color: Color3, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Parent = parent
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = frame
	return frame
end

local function text(parent: Instance, name: string, y: number, height: number, maxSize: number, color: Color3, stroke: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, y)
	label.Size = UDim2.new(1, -8, 0, height)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	-- Scaled down to fit, so a long display name shrinks instead of clipping.
	label.TextScaled = true
	label.ZIndex = 5
	label.Parent = parent
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = maxSize
	cap.MinTextSize = 12
	cap.Parent = label
	local outline = Instance.new("UIStroke")
	outline.Color = OUTLINE
	outline.Thickness = stroke
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = label
	return label
end

local function refreshVisibility(plot: Instance, gui: BillboardGui)
	local owner = plot:GetAttribute("OwnerUserId")
	gui.Enabled = not inStage and type(owner) == "number" and owner ~= 0
end

local function build(plot: Instance, anchor: BasePart): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = PLATE_NAME
	gui.AlwaysOnTop = true -- visible even with another base between you and it
	-- LightInfluence 0: every base sits next to a PointLight or two, and the default
	-- washes the plate toward white the moment you walk up to it.
	gui.LightInfluence = 0
	gui.MaxDistance = OTHER_REACH
	gui.Adornee = anchor
	local canvas = UIKit.billboardCanvas(gui, CANVAS)

	-- THE ORB: a dark outline disc, the accent ring, then the headshot on a soft
	-- gradient — layered frames so the ring reads as a chunky cartoon bezel.
	local holder = Instance.new("Frame")
	holder.Name = "Orb"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, BOB)
	holder.Size = UDim2.fromOffset(ORB, ORB)
	holder.BackgroundTransparency = 1
	holder.Parent = canvas

	circle(holder, "Outline", ORB, OUTLINE, 1)
	local ring = circle(holder, "Ring", ORB - 6, accentOf(plot), 2)
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	shine.Parent = ring
	local well = circle(holder, "Well", ORB - 18, OUTLINE, 3)
	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.new(1, -4, 1, -4)
	face.BackgroundColor3 = FACE_FILL
	face.BorderSizePixel = 0
	face.ZIndex = 4
	face.Parent = well
	local faceRound = Instance.new("UICorner")
	faceRound.CornerRadius = UDim.new(0.5, 0)
	faceRound.Parent = face
	local backdrop = Instance.new("UIGradient")
	backdrop.Rotation = 90
	backdrop.Color = ColorSequence.new(Color3.fromRGB(90, 120, 100), Color3.fromRGB(30, 42, 34))
	backdrop.Parent = face

	-- Floating: the orb drifts up and down on a slow sine; the text stays put.
	TweenService:Create(
		holder,
		TweenInfo.new(BOB_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromScale(0.5, 0) }
	):Play()

	local name = text(canvas, "OwnerName", ORB + BOB + 4, 32, 28, NAME_COLOR, 3)
	local rate = text(canvas, "Rate", ORB + BOB + 36, 24, 21, RATE_COLOR, 2.5)

	local function paint()
		local userId = plot:GetAttribute("OwnerUserId")
		local display = plot:GetAttribute("OwnerName")
		local perSecond = plot:GetAttribute("OwnerRate")
		local id = if type(userId) == "number" then userId else 0
		face.Image = if id ~= 0 then `rbxthumb://type=AvatarHeadShot&id={id}&w=150&h=150` else ""
		name.Text = if type(display) == "string" then display else ""
		rate.Text = formatRate(if type(perSecond) == "number" then perSecond else 0)
		ring.BackgroundColor3 = accentOf(plot)
		gui.MaxDistance = if id == Players.LocalPlayer.UserId then OWN_REACH else OTHER_REACH
		refreshVisibility(plot, gui)
	end
	plot:GetAttributeChangedSignal("OwnerUserId"):Connect(paint)
	plot:GetAttributeChangedSignal("OwnerName"):Connect(paint)
	plot:GetAttributeChangedSignal("OwnerRate"):Connect(paint)

	local trim = plot:FindFirstChild("Trim")
	if trim and trim:IsA("BasePart") then
		trim:GetPropertyChangedSignal("Color"):Connect(function()
			ring.BackgroundColor3 = trim.Color
		end)
	end

	paint()
	-- Kept in PlayerGui with an Adornee rather than parented to the anchor, so the
	-- anchor (server-owned, streamable) never carries client instances.
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

--- Hang a plate on `anchor`, and take it down again if the anchor leaves (streamed
--- out, or a Studio Plots rebuild); watchPlot's ChildAdded puts a fresh one up when
--- an anchor comes back.
local function hang(plot: Instance, anchor: BasePart)
	if plates[plot] then
		return
	end
	local gui = build(plot, anchor)
	plates[plot] = gui
	local conn: RBXScriptConnection
	conn = anchor.AncestryChanged:Connect(function()
		if anchor:IsDescendantOf(plot) then
			return
		end
		conn:Disconnect()
		gui:Destroy()
		if plates[plot] == gui then
			plates[plot] = nil
		end
	end)
end

local function watchPlot(plot: Instance)
	if not plot.Name:match("^Plot%d+$") then
		return
	end
	local function consider(child: Instance)
		if child.Name == "NamePlate" and child:IsA("BasePart") then
			hang(plot, child)
		end
	end
	plot.ChildAdded:Connect(consider)
	local anchor = plot:FindFirstChild("NamePlate")
	if anchor then
		consider(anchor)
	end
end

function BaseMarker.start()
	task.spawn(function()
		local folder = Workspace:WaitForChild("Plots", 30)
		if folder == nil then
			warn("[basemarker] no Plots folder to hang plates on")
			return
		end
		for _, plot in folder:GetChildren() do
			watchPlot(plot)
		end
		folder.ChildAdded:Connect(watchPlot)
	end)

	-- ExposureState ticks ~10Hz; stageId is nil in the safe zone and the field id
	-- once you cross in.
	Net.get("ExposureState").OnClientEvent:Connect(function(state)
		local now = state.stageId ~= nil
		if now == inStage then
			return
		end
		inStage = now
		for plot, gui in plates do
			refreshVisibility(plot, gui)
		end
	end)
end

return BaseMarker
