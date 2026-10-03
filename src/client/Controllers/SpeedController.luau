--[[
	SpeedController.lua — the persistent SPEED row, and the one reader of SpeedState.

	SPEED IS A UNIT NOW (Config/Treadmill): a lifetime total a treadmill pays per
	second, with one more point of walk speed unlocked at each requirement. This row is
	where a player sees it at all times — the bottom-left corner, directly over the cash
	row (Dock.SPEED_BOTTOM), so the two numbers you earn read as one cluster.

	NO BOX, THE SAME AS THE CASH ROW (CashController's header): the glossy sneaker
	standing on its own with a hard drop shadow, and the number beside it in light blue
	in Gotham Black with a heavy INK outline and drop shadow (UIKit.hudNumber). Light blue where cash is
	green, and a sneaker where cash has a bundle of notes, so the two never read as the
	same counter at a glance. The small WALK SPEED caption stays, so the number reads as
	your speed. No level is shown: the requirements are levels internally
	(SpeedState still carries `level`), but on screen the player only ever hears about
	walk speed.

	THE NUMBER COUNTS SMOOTHLY WHILE YOU RUN. The server only re-sends the readout once a
	second (TreadmillService.PUSH_INTERVAL), so between pushes this counts up locally
	from the belt's `rate`. It never leads the last push by more than LEAD_CAP seconds,
	so a stalled server shows a paused counter, not a runaway one. A walk-speed point
	punches the badge. The "+10" and "WALK SPEED 35!" popups float off the training bar
	instead (TreadmillController), where the player is looking while they earn.

	THE PENCIL PICKS YOUR WALK SPEED. Beside the number, a white edit pencil opens a
	small picker above the row: a slider from Treadmill.MIN_PICKED_WALK up to what you
	have trained, and MAX. Letting go sends Net.WalkCap; the server saves it on the
	profile (`walkCap`, 0 = full speed) and ExposureService walks you at it. The badge
	shows the speed you WALK at (Treadmill.chosenWalk), not the one you have trained.

	TreadmillController reads `Speed.view()` / `Speed.shownPoints()` / `Speed.onChanged`
	rather than listening to the remote itself, so the bar and the badge can never
	disagree about the number.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Treadmill = require(Shared.Config.Treadmill)

local Artwork = require(script.Parent.Parent.HudArtwork)
local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Speed = {}

local BADGE_W = Dock.SPEED_SIZE.X.Offset

--- How far past the last push the local count may run, in seconds of belt time.
local LEAD_CAP = 1.5

local STYLE = {
	value = Color3.fromHex("9FE3FF"),
	caption = Color3.fromHex("DDF3FF"),
	valueFont = Enum.Font.GothamBlack,
	captionFont = Enum.Font.GothamBlack,
}

-- Design px inside the Dock.SPEED_SIZE footprint (320 x 66).
local LAYOUT = {
	shoe = 66, -- centred in the icon slot the cash bundle fills (Dock.SIDE_ICON)
	shoeDrop = Vector2.new(3, 4),
	valueLeft = Dock.SIDE_ICON + 10, -- the same column as the cash balance below
	-- The number is centred on the sneaker's VISIBLE middle (Dock.SIDE_ICON_MIDDLE), the
	-- same rule as the cash balance; the caption sits in the space above it.
	valueTop = math.floor(Dock.SPEED_SIZE.Y.Offset * Dock.SIDE_ICON_MIDDLE + 0.5) - 27, -- the sneaker fills the row
	valueHeight = 54,
	captionTop = 0,
	captionTextSize = 15,
	valueTextSize = 42, -- 52 -> 42, "slightly smaller"
	valueStroke = 3.5, -- matches the cash balance's
	textDrop = Vector2.new(2, 3),
}

-- The pencil, and the picker it opens (design px).
local PICKER = {
	pencil = 22, -- the edit icon, small: a superscript on the number, not a second number
	pencilGap = 14, -- between the end of the number and the pencil
	pencilRise = 18, -- its top sits this far above the number's middle: up by the digits' top
	width = 300,
	height = 128,
	gap = 6, -- between the top of the row and the picker
	trackHeight = 14,
	knob = 30,
	fill = Color3.fromHex("9FE3FF"), -- the walk number's light blue
	track = Color3.fromHex("1E2630"),
	slab = Color3.fromRGB(18, 20, 24),
	edge = Color3.fromRGB(49, 53, 61),
}

local PUNCH_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local ui: any = {}
local view: any = nil
local receivedAt = 0
local listeners: { (view: any, previous: any) -> () } = {}
--- The walk being dragged to, shown on the badge before the server confirms it; nil
--- when the server's `walkCap` is what to show.
local pending: number? = nil

-- ── Formatting ────────────────────────────────────────────────────────────

--- Treadmill.DISPLAY_SCALE: every on-screen Speed number goes through format(), so
--- they all agree.
local DISPLAY_SCALE = Treadmill.DISPLAY_SCALE

--- 91,500 in full under a million (so the ticking number keeps visibly moving), then
--- 1.30M / 2.1B.
function Speed.format(points: number): string
	local n = math.floor(points * DISPLAY_SCALE + 0.5)
	if n >= 1_000_000_000 then
		return string.format("%.2fB", n / 1_000_000_000)
	elseif n >= 1_000_000 then
		return string.format("%.2fM", n / 1_000_000)
	end
	local text = tostring(n)
	while true do
		local swapped, count = string.gsub(text, "^(-?%d+)(%d%d%d)", "%1,%2")
		text = swapped
		if count == 0 then
			break
		end
	end
	return text
end

-- ── State ─────────────────────────────────────────────────────────────────

--- The last SpeedState readout, or nil before the load snapshot lands.
function Speed.view(): any
	return view
end

--- Lifetime Speed as it should be SHOWN right now: the last push, plus what the belt
--- has paid since if the player is still on it.
--- The client-side count between pushes climbs this many DISPLAYED points at a time.
local COUNT_STEP = 11 / DISPLAY_SCALE

function Speed.shownPoints(): number
	if view == nil then
		return 0
	end
	if not view.training then
		return view.points
	end
	-- The counted lead ticks up in whole steps of COUNT_STEP rather than 1 at a time.
	local lead = Speed.smoothPoints() - view.points
	return view.points + lead // COUNT_STEP * COUNT_STEP
end

--- The same count unstepped, for things that should glide (the training bar's fill).
function Speed.smoothPoints(): number
	if view == nil then
		return 0
	end
	if not view.training then
		return view.points
	end
	return view.points + view.rate * math.min(os.clock() - receivedAt, LEAD_CAP)
end

--- Called with (view, previous) on every SpeedState push.
function Speed.onChanged(fn: (view: any, previous: any) -> ())
	table.insert(listeners, fn)
end

-- ── The badge ─────────────────────────────────────────────────────────────

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpeedHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 80
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local canvas = UIKit.canvas(gui)

	local badge = Instance.new("Frame")
	badge.Name = "SpeedBadge"
	badge.Size = Dock.SPEED_SIZE
	badge.AnchorPoint = Vector2.new(0, 1)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 2
	badge.Parent = canvas
	ui.badge = badge

	ui.punch = Instance.new("UIScale")
	ui.punch.Parent = badge

	-- Stacked on the cash row, and lifted with it clear of a phone's thumbstick.
	UIKit.onScaleChanged(function()
		badge.Position = UDim2.new(0, Dock.SIDE_CORNER_X, 1, -(Dock.SPEED_BOTTOM + Dock.sideLift()))
	end)

	local L = LAYOUT
	local shoe = Artwork.droppedPicture(badge, "Shoe", Artwork.IMAGE.speedShoe, L.shoe, L.shoeDrop, 3)
	shoe.Position = UDim2.fromOffset((Dock.SIDE_ICON - L.shoe) / 2, (Dock.SPEED_SIZE.Y.Offset - L.shoe) / 2)

	UIKit.label(badge, {
		name = "Caption",
		position = UDim2.fromOffset(L.valueLeft + 2, L.captionTop),
		size = UDim2.fromOffset(160, 18),
		font = STYLE.captionFont,
		textSize = L.captionTextSize,
		color = STYLE.caption,
		xAlign = Enum.TextXAlignment.Left,
		shadow = false,
		text = "Walk Speed",
		zIndex = 11,
	})
	ui.value = UIKit.hudNumber(badge, {
		name = "Value",
		position = UDim2.fromOffset(L.valueLeft, L.valueTop),
		size = UDim2.fromOffset(BADGE_W - L.valueLeft - 12, L.valueHeight),
		font = STYLE.valueFont,
		textSize = L.valueTextSize,
		color = STYLE.value,
		xAlign = Enum.TextXAlignment.Left,
		text = "0",
		zIndex = 11,
	}, L.valueStroke, L.textDrop)

	-- The pencil rides at the number's top-right corner, wherever the number ends.
	local pencil = Instance.new("ImageButton")
	pencil.Name = "EditWalk"
	pencil.Size = UDim2.fromOffset(PICKER.pencil, PICKER.pencil)
	pencil.AnchorPoint = Vector2.new(0, 0)
	pencil.BackgroundTransparency = 1
	pencil.Image = Artwork.IMAGE.editPencil
	pencil.ScaleType = Enum.ScaleType.Fit
	pencil.ZIndex = 12
	pencil.Parent = badge
	ui.pencil = pencil
	local pencilScale = Instance.new("UIScale")
	pencilScale.Parent = pencil
	pencil.MouseEnter:Connect(function()
		pencilScale.Scale = 1.12
	end)
	pencil.MouseLeave:Connect(function()
		pencilScale.Scale = 1
	end)
	local function placePencil()
		local width = TextService:GetTextSize(ui.value.Text, L.valueTextSize, STYLE.valueFont, Vector2.new(1000, 200)).X
		pencil.Position = UDim2.fromOffset(L.valueLeft + width + PICKER.pencilGap, L.valueTop + L.valueHeight / 2 - PICKER.pencilRise)
	end
	ui.value:GetPropertyChangedSignal("Text"):Connect(placePencil)
	placePencil()

	return gui
end

-- ── The walk-speed picker ─────────────────────────────────────────────────

--- The range the slider covers right now: the floor, and what they have trained.
local function pickRange(): (number, number)
	local trained = if view then view.walk else Treadmill.START_WALK
	return Treadmill.MIN_PICKED_WALK, math.max(trained, Treadmill.MIN_PICKED_WALK)
end

--- The walk the badge and the slider show: a drag in progress, else the server's
--- confirmed pick.
local function shownWalk(): number
	if view == nil then
		return 0
	end
	return Treadmill.chosenWalk(view.walk, pending or view.walkCap)
end

--- What the badge prints: the walk you chose, scaled by the worn aura's bonus -- the
--- speed you actually move at. The slider stays in trained units (what you can pick).
local function badgeWalk(): number
	local walk = shownWalk()
	if view == nil then
		return walk
	end
	return math.floor((view.override or walk) * (1 + (view.auraSpeed or 0)) + 0.5)
end

local function drawPicker()
	if ui.picker == nil then
		return
	end
	local low, high = pickRange()
	local walk = shownWalk()
	local alpha = if high > low then math.clamp((walk - low) / (high - low), 0, 1) else 1
	if view and view.override then
		alpha = 1 -- a pinned speed IS the top of the slider
	end
	ui.pickFill.Size = UDim2.fromScale(alpha, 1)
	ui.pickKnob.Position = UDim2.fromScale(alpha, 0.5)
	-- The numbers are printed in the units the badge uses -- the aura's bonus included,
	-- and the debug /speed pin standing in for the trained top -- so the slider and the
	-- badge never disagree. The slider itself still works in trained units underneath.
	local scale = 1 + ((view and view.auraSpeed) or 0)
	local override = view and view.override
	ui.pickValue.Text = tostring(if override then math.floor(override * scale + 0.5) else math.floor(walk * scale + 0.5))
	ui.pickLow.Text = tostring(math.floor(low * scale + 0.5))
	ui.pickHigh.Text = tostring(if override then math.floor(override * scale + 0.5) else math.floor(high * scale + 0.5))
	local atMax = walk >= high
	ui.pickMax.BackgroundColor3 = if atMax then PICKER.track else PICKER.fill
	ui.pickMax.TextColor3 = if atMax then UIKit.C.dim else UIKit.C.outline
end

--- 0 = "full speed", so a pick at the top keeps following the next level up.
local function send(walk: number)
	local _, high = pickRange()
	Net.get("WalkCap"):FireServer(if walk >= high then 0 else walk)
end

local function caption(parent: Instance, name: string, x: number, xAlign: Enum.TextXAlignment): TextLabel
	return UIKit.label(parent, {
		name = name,
		position = UDim2.fromOffset(x, 90),
		anchorPoint = Vector2.new(if xAlign == Enum.TextXAlignment.Right then 1 else 0, 0),
		size = UDim2.fromOffset(60, 18),
		font = Enum.Font.GothamBlack,
		textSize = 14,
		color = UIKit.C.dim,
		xAlign = xAlign,
		zIndex = 21,
	})
end

local function buildPicker(canvas: Frame)
	local picker, stroke = UIKit.panel(canvas, {
		name = "WalkPicker",
		size = UDim2.fromOffset(PICKER.width, PICKER.height),
		anchorPoint = Vector2.new(0, 1),
		color = PICKER.slab,
		transparency = 0.05,
		strokeColor = PICKER.edge,
		strokeThickness = 2,
		cornerRadius = UDim.new(0, 4),
		zIndex = 20,
		visible = false,
	})
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	picker.Active = true -- a click on the slab is not a click on the world behind it
	ui.picker = picker

	UIKit.onScaleChanged(function()
		local bottom = Dock.SPEED_BOTTOM + Dock.sideLift() + Dock.SPEED_SIZE.Y.Offset + PICKER.gap
		picker.Position = UDim2.new(0, Dock.SIDE_CORNER_X, 1, -bottom)
	end)

	UIKit.label(picker, {
		name = "Title",
		position = UDim2.fromOffset(16, 14),
		size = UDim2.fromOffset(180, 20),
		font = Enum.Font.GothamBlack,
		textSize = 16,
		color = STYLE.caption,
		text = "Walk Speed",
		zIndex = 21,
	})
	ui.pickValue = UIKit.label(picker, {
		name = "Value",
		position = UDim2.fromOffset(PICKER.width - 16, 8),
		anchorPoint = Vector2.new(1, 0),
		size = UDim2.fromOffset(120, 32),
		font = Enum.Font.GothamBlack,
		textSize = 30,
		color = STYLE.value,
		xAlign = Enum.TextXAlignment.Right,
		zIndex = 21,
	})

	-- The slider. The hit box is taller than the track so a thumb can grab it, and
	-- inset by half a knob so the knob never hangs off either end.
	local hit = Instance.new("TextButton")
	hit.Name = "Slider"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(16 + PICKER.knob / 2, 46)
	hit.Size = UDim2.fromOffset(PICKER.width - 32 - PICKER.knob, 40)
	hit.ZIndex = 21
	hit.Parent = picker

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.new(1, 0, 0, PICKER.trackHeight)
	track.BackgroundColor3 = PICKER.track
	track.BorderSizePixel = 0
	track.ZIndex = 21
	track.Parent = hit
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = UIKit.C.outline
	trackStroke.Thickness = 2
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = PICKER.fill
	fill.BorderSizePixel = 0
	fill.ZIndex = 22
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	ui.pickFill = fill

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(PICKER.knob, PICKER.knob)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.ZIndex = 23
	knob.Parent = hit
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	local knobStroke = Instance.new("UIStroke")
	knobStroke.Color = UIKit.C.outline
	knobStroke.Thickness = 3
	knobStroke.Parent = knob
	ui.pickKnob = knob

	-- The two ends of the track, under it: the floor and what they have trained.
	ui.pickLow = caption(picker, "Low", 16, Enum.TextXAlignment.Left)
	ui.pickHigh = caption(picker, "High", PICKER.width - 16 - 86 - 12, Enum.TextXAlignment.Right)

	local max, maxStroke = UIKit.button(picker, {
		name = "Max",
		position = UDim2.fromOffset(PICKER.width - 16, PICKER.height - 10),
		anchorPoint = Vector2.new(1, 1),
		size = UDim2.fromOffset(86, 30),
		font = Enum.Font.GothamBlack,
		textSize = 16,
		text = "MAX",
		fillColor = PICKER.fill,
		fillTransparency = 0,
		strokeThickness = 2,
		cornerRadius = UDim.new(0, 4),
		zIndex = 21,
	})
	-- The ink edge goes round the button, not round its dark text.
	maxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ui.pickMax = max
	max.Activated:Connect(function()
		local _, high = pickRange()
		pending = high
		send(high)
		drawPicker()
	end)

	-- Dragging: the knob follows the pointer in whole studs/sec, and the pick is sent
	-- once, on release.
	local dragging: InputObject? = nil
	local function follow(x: number)
		local low, high = pickRange()
		local alpha = math.clamp((x - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
		pending = math.floor(low + alpha * (high - low) + 0.5)
		drawPicker()
	end
	hit.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = input
			follow(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging ~= nil and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragging) then
			follow(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging ~= nil and (input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = nil
			if pending ~= nil then
				send(pending)
			end
		end
	end)

	ui.pencil.Activated:Connect(function()
		picker.Visible = not picker.Visible
		drawPicker()
	end)
	-- A click out in the world puts it away. A click on any GUI (the slab is Active, so
	-- that includes it) arrives game-processed and leaves it open; the pencil toggles.
	UserInputService.InputBegan:Connect(function(input, processed)
		local kind = input.UserInputType
		if processed or not picker.Visible then
			return
		end
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			picker.Visible = false
		end
	end)
end

local function punch()
	ui.punch.Scale = 1.08
	TweenService:Create(ui.punch, PUNCH_TWEEN, { Scale = 1 }):Play()
end

local function onState(next: any)
	if type(next) ~= "table" or type(next.points) ~= "number" then
		return
	end
	local previous = view
	view = next
	receivedAt = os.clock()
	-- Once the server agrees with a sent pick, its word is what shows.
	if pending ~= nil and Treadmill.chosenWalk(next.walk, next.walkCap) == Treadmill.chosenWalk(next.walk, pending) then
		pending = nil
	end
	drawPicker()

	-- One more point of walk speed. Its popup is the training bar's.
	if previous ~= nil and next.level > previous.level then
		punch()
	end

	for _, fn in listeners do
		task.spawn(fn, next, previous)
	end
end

function Speed.start()
	local gui = build()
	buildPicker(ui.badge.Parent :: Frame)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	Net.get("SpeedState").OnClientEvent:Connect(onState)

	-- The badge shows the walk you WALK at (your pick, under what you have trained), not
	-- the Speed total (that lives on the training bar). Checked every frame, but only
	-- written when it changes.
	local lastText = ""
	RunService.RenderStepped:Connect(function()
		local text = tostring(badgeWalk())
		if text ~= lastText then
			lastText = text
			ui.value.Text = text
		end
	end)
end

return Speed
