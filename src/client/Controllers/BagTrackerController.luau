--[[
	BagTrackerController.luau — "get your bag back": where your dropped bag is and how
	long it has left (option 7 of the death-screen mockup round, paired with Flatline).

	Going down to radiation drops your unwashed haul where you fell, for ninety seconds,
	for anyone to grab (ExposureService). The death screen says so once; this keeps
	saying it after you wake up at camp:
	  - a pill at the top of the screen: YOUR BAG, how many items are left in it, the
	    countdown (red under LOW_SECONDS), and how far away it is with an arrow that
	    points at it from where the camera is looking;
	  - a tall light column over the bag and a countdown label on it, drawn on YOUR
	    client only -- everyone else already sees the bag and its own label.
	It goes the moment the bag is emptied (by you or anyone) or times out.

	FED BY Net.DroppedBag, NOT BY FINDING THE PART. The bag lies where you fell and you
	have just been moved to camp, so it may not be streamed in here at all; the server
	sends its position and a server-clock deadline instead, and says when it is gone.

	SEVERAL BAGS AT ONCE ARE POSSIBLE (go down twice inside ninety seconds). Each gets
	its own column; the pill follows the newest one.

	THE PILL SITS AS HIGH AS THE TOP OF THE SCREEN ALLOWS, under whichever top banner is
	showing (the warp bar in camp, the stage title card in a field, the tutorial banner,
	the UPGRADE AURA warning) -- AuraWarningController's clearTop, with that warning
	added to the list.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Stages = require(Shared.Config.Stages)

local UIKit = require(script.Parent.Parent.UIKit)

local BagTrackerController = {}

-- Under this many seconds left the countdown turns red.
local LOW_SECONDS = 20

-- Design px on the 1280x720 canvas.
local TOP_Y = 16 -- with nothing else up there
local CLEARANCE = 8 -- under whatever top banner is showing
local PILL_H = 54

-- The top-of-screen pieces the pill must not sit on: ScreenGui name -> the frame in it
-- that is drawn only while showing.
local TOP_BANNERS = {
	{ gui = "StageBanner", frame = "Panel" },
	{ gui = "TutorialHud", frame = "Banner" },
	{ gui = "WarpBar", frame = "Panel" },
	{ gui = "AuraWarning", frame = "Warning" },
}

-- The dropped bag's own green (ExposureService.dropBag), so the pill, the column and
-- the bag lying in the field are plainly the same thing.
local BAG_GREEN = Color3.fromHex("8FE04A")
local INK = Color3.fromHex("1A1A1A")
local SLATE = Color3.fromHex("1D2326")
local GREY = Color3.fromHex("9AA6AD")
local RED = UIKit.C.red

local COLUMN_HEIGHT = 60
local COLUMN_WIDTH = 2.6
local LABEL_SIZE = Vector2.new(170, 40) -- the column's billboard, design px

local POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

type Bag = {
	id: string,
	position: Vector3,
	expiresAt: number,
	items: number,
	column: BasePart,
	billboard: BillboardGui,
	timer: TextLabel,
}

local bags: { [string]: Bag } = {}
local ui: any = {}
local shown = false

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function plural(n: number): string
	return if n == 1 then "1 item" else `{n} items`
end

local function newest(): Bag?
	local best: Bag? = nil
	for _, bag in bags do
		if best == nil or bag.expiresAt > best.expiresAt then
			best = bag
		end
	end
	return best
end

-- ── The column over the bag (your client only) ──────────────────────────────

local markerFolder: Folder? = nil

local function folder(): Folder
	if markerFolder == nil or markerFolder.Parent == nil then
		local f = Instance.new("Folder")
		f.Name = "BagMarkers"
		f.Parent = Workspace
		markerFolder = f
	end
	return markerFolder :: Folder
end

local function addColumn(bag: any)
	local column = Instance.new("Part")
	column.Name = "BagColumn"
	column.Shape = Enum.PartType.Cylinder
	-- A Cylinder's length runs along its X axis; turned onto Z so it stands up.
	column.Size = Vector3.new(COLUMN_HEIGHT, COLUMN_WIDTH, COLUMN_WIDTH)
	column.CFrame = CFrame.new(bag.position + Vector3.new(0, COLUMN_HEIGHT / 2 - 1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	column.CastShadow = false
	column.Material = Enum.Material.SmoothPlastic
	column.Color = BAG_GREEN
	column.Transparency = 0.6
	column.Parent = folder()

	-- Under PlayerGui with an Adornee rather than inside the part, so the wash bay's
	-- hideHud (which stows every LayerCollector under PlayerGui) takes it too.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BagMarkerLabel"
	billboard.Adornee = column
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = math.huge
	billboard.ResetOnSpawn = false
	-- Low down the column, just over the bag: the column's middle is its origin.
	billboard.StudsOffsetWorldSpace = Vector3.new(0, -COLUMN_HEIGHT / 2 + 7, 0)
	billboard.LightInfluence = 0
	billboard.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local canvas = UIKit.billboardCanvas(billboard, LABEL_SIZE)

	local card = UIKit.panel(canvas, {
		name = "Card",
		size = UDim2.fromScale(1, 1),
		color = SLATE,
		transparency = 0,
		strokeColor = INK,
		strokeThickness = 3,
		cornerRadius = UDim.new(0, 12),
	})
	local timer = UIKit.label(card, {
		name = "Text",
		size = UDim2.fromScale(1, 1),
		font = Enum.Font.LuckiestGuy,
		textSize = 22,
		color = Color3.new(1, 1, 1),
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
	timer.RichText = true

	bag.column = column
	bag.billboard = billboard
	bag.timer = timer
end

local function removeBag(id: string)
	local bag = bags[id]
	if bag == nil then
		return
	end
	bags[id] = nil
	bag.column:Destroy()
	bag.billboard:Destroy()
end

-- ── The pill ────────────────────────────────────────────────────────────────

--- The highest design-px Y the pill can take without covering a top banner (the same
--- walk as AuraWarningController.clearTop).
local function clearTop(): number
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local scale = UIKit.canvasScale(ui.canvas)
	local canvasTop = ui.canvas.AbsolutePosition.Y
	local y = TOP_Y
	if playerGui == nil or scale <= 0 then
		return y
	end
	local spans = {}
	for _, spec in TOP_BANNERS do
		local gui = playerGui:FindFirstChild(spec.gui)
		local frame = gui and gui:FindFirstChild(spec.frame, true)
		if frame and frame:IsA("GuiObject") and frame.Visible and (gui :: ScreenGui).Enabled then
			local top = (frame.AbsolutePosition.Y - canvasTop) / scale
			table.insert(spans, { top = top, bottom = top + frame.AbsoluteSize.Y / scale })
		end
	end
	table.sort(spans, function(a, b)
		return a.top < b.top
	end)
	for _, span in spans do
		if span.top < y + PILL_H + CLEARANCE and span.bottom + CLEARANCE > y then
			y = span.bottom + CLEARANCE
		end
	end
	return y
end

local function label(parent: Instance, name: string, font: Enum.Font, size: number, color: Color3, width: number, order: number): TextLabel
	local l = UIKit.label(parent, {
		name = name,
		size = UDim2.fromOffset(width, PILL_H),
		font = font,
		textSize = size,
		color = color,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
	l.LayoutOrder = order
	if width == 0 then
		l.AutomaticSize = Enum.AutomaticSize.X
	end
	return l
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "BagTracker"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Under the stage title card (95) it ducks beneath anyway, and under the death
	-- screen (120), which covers the moment the bag is dropped.
	gui.DisplayOrder = 94
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local canvas = UIKit.canvas(gui)

	local root = Instance.new("Frame")
	root.Name = "Pill"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, TOP_Y)
	root.Size = UDim2.fromOffset(0, PILL_H)
	root.AutomaticSize = Enum.AutomaticSize.X
	root.BackgroundColor3 = SLATE
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = canvas
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = root
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 4
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = root
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 22)
	pad.PaddingRight = UDim.new(0, 22)
	pad.Parent = root
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 12)
	list.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local title = label(root, "Title", Enum.Font.LuckiestGuy, 22, BAG_GREEN, 0, 1)
	title.Text = "YOUR BAG"
	local items = label(root, "Items", Enum.Font.FredokaOne, 17, GREY, 0, 2)
	-- Fixed width, so the pill does not twitch as 1:10 turns into 1:09.
	local timer = label(root, "Timer", Enum.Font.LuckiestGuy, 32, Color3.new(1, 1, 1), 76, 3)
	local arrow = label(root, "Arrow", Enum.Font.FredokaOne, 22, Color3.new(1, 1, 1), 24, 4)
	arrow.Text = "\u{25B2}"
	local distance = label(root, "Distance", Enum.Font.FredokaOne, 19, GREY, 0, 5)

	ui = {
		canvas = canvas,
		root = root,
		scale = scale,
		items = items,
		timer = timer,
		arrow = arrow,
		distance = distance,
	}
	return gui
end

local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	ui.root.Visible = on
	if on then
		ui.root.Position = UDim2.new(0.5, 0, 0, clearTop())
		ui.scale.Scale = 0.6
		TweenService:Create(ui.scale, POP, { Scale = 1 }):Play()
	end
end

-- ── Tick ────────────────────────────────────────────────────────────────────

local function step(dt: number)
	local now = Workspace:GetServerTimeNow()

	-- Timed out here even if the server's "gone" is still on its way.
	for id, bag in bags do
		if bag.expiresAt - now <= 0 then
			removeBag(id)
		end
	end

	for _, bag in bags do
		local left = bag.expiresAt - now
		local colour = if left <= LOW_SECONDS then RED else Color3.new(1, 1, 1)
		bag.timer.Text = `YOUR BAG <font color="#{colour:ToHex()}">{clock(left)}</font>`
		-- A slow breath on the column, so it reads as a signal rather than scenery.
		bag.column.Transparency = 0.6 + 0.12 * math.sin(now * 4)
	end

	local bag = newest()
	setShown(bag ~= nil)
	if bag == nil then
		return
	end

	local left = bag.expiresAt - now
	ui.timer.Text = clock(left)
	ui.timer.TextColor3 = if left <= LOW_SECONDS then RED else Color3.new(1, 1, 1)
	ui.items.Text = plural(bag.items)

	-- Distance and heading from wherever you are, relative to where the camera looks,
	-- flat on the ground: straight up the screen means straight ahead.
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if root and root:IsA("BasePart") and camera then
		local offset = bag.position - root.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		ui.distance.Text = `{math.floor(flat.Magnitude / Stages.STUDS_PER_METRE + 0.5)} m`
		local look = camera.CFrame.LookVector
		local forward = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.1 and forward.Magnitude > 0.01 then
			local a = math.atan2(forward.X, forward.Z)
			local b = math.atan2(flat.X, flat.Z)
			ui.arrow.Rotation = math.deg(a - b)
		end
	end

	-- Glide under a top banner that slides in, and back up once it goes.
	local y = ui.root.Position.Y.Offset
	y += (clearTop() - y) * math.min(1, dt * 12)
	ui.root.Position = UDim2.new(0.5, 0, 0, y)
end

function BagTrackerController.start()
	local gui = build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	Net.get("DroppedBag").OnClientEvent:Connect(function(payload)
		local id = payload.id
		if type(id) ~= "string" then
			return
		end
		if payload.gone then
			removeBag(id)
		elseif payload.position then
			removeBag(id)
			local bag = {
				id = id,
				position = payload.position,
				expiresAt = payload.expiresAt or (Workspace:GetServerTimeNow() + 90),
				items = payload.items or 0,
			}
			addColumn(bag)
			bags[id] = bag :: any
		elseif bags[id] and payload.items then
			bags[id].items = payload.items
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn(`[bagtracker] step failed: {err}`)
		end
	end)
end

return BagTrackerController
