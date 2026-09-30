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

	TreadmillController reads `Speed.view()` / `Speed.shownPoints()` / `Speed.onChanged`
	rather than listening to the remote itself, so the bar and the badge can never
	disagree about the number.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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

-- Design px inside the Dock.SPEED_SIZE footprint (280 x 60).
local LAYOUT = {
	shoe = 70, -- centred in the icon slot the cash bundle fills (Dock.SIDE_ICON)
	shoeDrop = Vector2.new(3, 4),
	valueLeft = Dock.SIDE_ICON + 10, -- the same column as the cash balance below
	captionTop = 6,
	captionTextSize = 15,
	valueTop = 22,
	valueTextSize = 36,
	valueStroke = 4.5,
	textDrop = Vector2.new(2, 3),
}

local PUNCH_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local ui: any = {}
local view: any = nil
local receivedAt = 0
local listeners: { (view: any, previous: any) -> () } = {}

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
		badge.Position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 1, -(Dock.SPEED_BOTTOM + Dock.sideLift()))
	end)

	local L = LAYOUT
	local shoe = Artwork.droppedPicture(badge, "Shoe", Artwork.IMAGE.speedShoe, L.shoe, L.shoeDrop, 3)
	shoe.Position = UDim2.fromOffset((Dock.SIDE_ICON - L.shoe) / 2, (Dock.SPEED_SIZE.Y.Offset - L.shoe) / 2)

	UIKit.label(badge, {
		name = "Caption",
		position = UDim2.fromOffset(L.valueLeft + 2, L.captionTop),
		size = UDim2.fromOffset(150, 19),
		font = STYLE.captionFont,
		textSize = L.captionTextSize,
		color = STYLE.caption,
		xAlign = Enum.TextXAlignment.Left,
		shadow = false,
		text = "WALK SPEED",
		zIndex = 11,
	})
	ui.value = UIKit.hudNumber(badge, {
		name = "Value",
		position = UDim2.fromOffset(L.valueLeft, L.valueTop),
		size = UDim2.fromOffset(BADGE_W - L.valueLeft - 12, 44),
		font = STYLE.valueFont,
		textSize = L.valueTextSize,
		color = STYLE.value,
		xAlign = Enum.TextXAlignment.Left,
		text = "0",
		zIndex = 11,
	}, L.valueStroke, L.textDrop)

	return gui
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
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	Net.get("SpeedState").OnClientEvent:Connect(onState)

	-- The badge shows walk speed, not the Speed total (that lives on the training bar).
	-- Checked every frame, but only written when it changes.
	local lastText = ""
	RunService.RenderStepped:Connect(function()
		local text = if view then tostring(view.walk) else "0"
		if text ~= lastText then
			lastText = text
			ui.value.Text = text
		end
	end)
end

return Speed
