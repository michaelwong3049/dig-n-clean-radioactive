--[[
	BagTrackerController.luau — "get your bag back": where your dropped bag is and how
	long it has left (option 7 of the death-screen mockup round, paired with Flatline).

	Going down drops your whole bag where you fell, for ninety seconds, for anyone to
	steal (ExposureService). The death screen says so once; this keeps saying it after
	you wake up at camp:
	  - a pill at the top of the screen: YOUR BAG, how many items are left in it, the
	    countdown (red under LOW_SECONDS), and how far away it is with an arrow that
	    points at it from where the camera is looking;
	  - a tall light column over the bag and a BagCard on it, drawn on YOUR client
	    only and from any distance -- everyone else gets theirs close up only
	    (DroppedBagController);
	  - a red toast when someone steals from it, naming them ("Sam stole 3 items from
	    your bag"), and the thief's name on the pill (Net.DroppedBag stolenBy).
	  - a purple RECOVER button at the end of the pill (BagRecover): Robux puts the whole
	    bag back in your pack from wherever you are.
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
local BagCard = require(script.Parent.Parent.BagCard)
local BagRecover = require(script.Parent.Parent.BagRecover)
local Sfx = require(script.Parent.Parent.Sfx)

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

local TOAST_H = 58
local TOAST_SECONDS = 4.5

local POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

type Bag = {
	id: string,
	position: Vector3,
	expiresAt: number,
	items: number,
	column: BasePart,
	billboard: BillboardGui,
	card: BagCard.Card,
	thief: string?,
}

local bags: { [string]: Bag } = {}
local ui: any = {}
local shown = false

local clock = BagCard.clock
local plural = BagCard.items

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
	local canvas = UIKit.billboardCanvas(billboard, BagCard.SIZE)
	local card = BagCard.build(canvas, BAG_GREEN)
	card.title.Text = "Your bag"
	card.title.TextColor3 = BAG_GREEN

	bag.column = column
	bag.billboard = billboard
	bag.card = card
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

	local title = label(root, "Title", Enum.Font.GothamBlack, 20, BAG_GREEN, 0, 1)
	title.Text = "Your bag"
	local items = label(root, "Items", Enum.Font.GothamBlack, 16, GREY, 0, 2)
	-- Fixed width, so the pill does not twitch as 1:10 turns into 1:09.
	local timer = label(root, "Timer", Enum.Font.GothamBlack, 28, Color3.new(1, 1, 1), 72, 3)
	local arrow = label(root, "Arrow", Enum.Font.GothamBlack, 20, Color3.new(1, 1, 1), 24, 4)
	arrow.Text = "\u{25B2}"
	local distance = label(root, "Distance", Enum.Font.GothamBlack, 17, GREY, 0, 5)
	-- "Stolen by Sam" once someone has had a go at it; hidden until then.
	local thief = label(root, "Thief", Enum.Font.GothamBlack, 16, RED, 0, 6)
	thief.Visible = false
	local recover = BagRecover.button(root, "RECOVER")
	recover.button.Size = UDim2.fromOffset(104, 42)
	recover.button.LayoutOrder = 7
	BagRecover.onChanged(function()
		recover.refresh()
	end)

	-- The theft toast, under the pill: a dark slab with a red edge and strip.
	local toast = UIKit.panel(canvas, {
		name = "StolenToast",
		size = UDim2.fromOffset(0, TOAST_H),
		anchorPoint = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, TOP_Y + PILL_H + 10),
		color = SLATE,
		transparency = 0,
		strokeColor = RED,
		strokeThickness = 3,
		cornerRadius = UDim.new(0, 12),
		visible = false,
	})
	toast.AutomaticSize = Enum.AutomaticSize.X
	local toastPad = Instance.new("UIPadding")
	toastPad.PaddingLeft = UDim.new(0, 26)
	toastPad.PaddingRight = UDim.new(0, 20)
	toastPad.Parent = toast
	local toastStrip = Instance.new("Frame")
	toastStrip.Name = "Strip"
	toastStrip.AnchorPoint = Vector2.new(0, 0.5)
	toastStrip.Position = UDim2.new(0, -17, 0.5, 0)
	toastStrip.Size = UDim2.new(0, 5, 1, -18)
	toastStrip.BackgroundColor3 = RED
	toastStrip.BorderSizePixel = 0
	toastStrip.Parent = toast
	local stripRound = Instance.new("UICorner")
	stripRound.CornerRadius = UDim.new(1, 0)
	stripRound.Parent = toastStrip
	local toastTitle = UIKit.label(toast, {
		name = "Title",
		size = UDim2.fromOffset(0, 24),
		position = UDim2.fromOffset(0, 7),
		font = Enum.Font.GothamBlack,
		textSize = 19,
		color = RED,
		text = "Bag stolen!",
	})
	toastTitle.AutomaticSize = Enum.AutomaticSize.X
	local toastBody = UIKit.label(toast, {
		name = "Body",
		size = UDim2.fromOffset(0, 20),
		position = UDim2.fromOffset(0, 31),
		font = Enum.Font.GothamBlack,
		textSize = 15,
		color = Color3.new(1, 1, 1),
	})
	toastBody.AutomaticSize = Enum.AutomaticSize.X
	toastBody.RichText = true
	local toastScale = Instance.new("UIScale")
	toastScale.Parent = toast

	ui = {
		canvas = canvas,
		root = root,
		scale = scale,
		items = items,
		timer = timer,
		arrow = arrow,
		distance = distance,
		thief = thief,
		toast = toast,
		toastBody = toastBody,
		toastScale = toastScale,
	}
	return gui
end

-- ── The theft toast ─────────────────────────────────────────────────────────

local toastSerial = 0

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function showStolen(thief: string, count: number, left: number)
	toastSerial += 1
	local serial = toastSerial
	local rest = if left > 0 then `  \u{00B7}  {plural(left)} left` else ""
	ui.toastBody.Text = `<font color="#{BAG_GREEN:ToHex()}">{escape(thief)}</font> stole {plural(count)} from your bag{rest}`
	-- Under the pill when it is up, else where the pill would sit.
	local top = if shown then ui.root.Position.Y.Offset + PILL_H + 10 else clearTop()
	ui.toast.Position = UDim2.new(0.5, 0, 0, top)
	ui.toast.Visible = true
	ui.toastScale.Scale = 0.6
	TweenService:Create(ui.toastScale, POP, { Scale = 1 }):Play()
	Sfx.play("denied")

	task.delay(TOAST_SECONDS, function()
		if serial == toastSerial then
			ui.toast.Visible = false
		end
	end)
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
		bag.card.detail.Text = BagCard.detailText(bag.items, bag.expiresAt - now, LOW_SECONDS)
		-- A slow breath on the column, so it reads as a signal rather than scenery.
		bag.column.Transparency = 0.6 + 0.12 * math.sin(now * 4)
	end

	local bag = newest()
	BagRecover.setNewest(bag and bag.id)
	setShown(bag ~= nil)
	if bag == nil then
		return
	end

	local left = bag.expiresAt - now
	ui.timer.Text = clock(left)
	ui.timer.TextColor3 = if left <= LOW_SECONDS then RED else Color3.new(1, 1, 1)
	ui.items.Text = plural(bag.items)
	ui.thief.Visible = bag.thief ~= nil
	ui.thief.Text = if bag.thief then `Stolen by {bag.thief}` else ""

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
		-- Told before any "gone", even for the take that empties the bag.
		if type(payload.stolenBy) == "string" then
			showStolen(payload.stolenBy, payload.stolenCount or 0, payload.items or 0)
			if bags[id] then
				bags[id].thief = payload.stolenBy
			end
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
			-- Now, not on the next tick: the death screen's Recover reads it at once.
			local latest = newest()
			BagRecover.setNewest(latest and latest.id)
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
