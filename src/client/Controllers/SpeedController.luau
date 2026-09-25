--[[
	SpeedController.lua — the persistent SPEED badge, and the one reader of SpeedState.

	SPEED IS A UNIT NOW (Config/Treadmill): a lifetime total a treadmill pays per
	second, with one more point of walk speed unlocked at each requirement. This badge is
	where a player sees it at all times — sat in the left column between the cash badge
	and the meter (Dock.SPEED_MID_Y), so the two numbers you earn read as one cluster.

	THE SAME TOY-SHOP VOICE AS THE CASH BADGE (CashController's header): a thick INK
	outline on every shape, hard offset shadows, LuckiestGuy numbers. Blue where cash is
	gold, and a glossy sneaker where cash has a coin, so the two never read as the same
	counter at a glance. No level is shown: the requirements are levels internally
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

local Artwork = require(script.Parent.Parent.HudArtwork)
local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Speed = {}

local BADGE_W = Dock.SPEED_SIZE.X.Offset

--- How far past the last push the local count may run, in seconds of belt time.
local LEAD_CAP = 1.5

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

-- Electric blue, never green: green is exposure's colour and nothing else's (PLAN §14).
local STYLE = {
	card = Color3.fromHex("33AEFF"),
	cardShine = Color3.fromHex("8AD4FF"),
	disc = Color3.fromHex("1C6FE8"),
	discFace = Color3.fromHex("3D93FF"),
	caption = Color3.fromHex("DDF3FF"),
	valueFont = Enum.Font.LuckiestGuy,
	captionFont = Enum.Font.FredokaOne,
}

-- Design px inside the Dock.SPEED_SIZE footprint (280 x 64).
local LAYOUT = {
	disc = 58,
	shoe = 52, -- wider than the face, so the sneaker overlaps the disc's rim
	cardTop = 4,
	cardHeight = 48, -- the 12 px under it in Dock's 64 held the old level pill
	cardRadius = 16,
	shadowDrop = 4,
	outline = 4,
	valueLeft = 72,
	captionTextSize = 13,
	valueTextSize = 26,
	valueStroke = 3,
}
local CARD_LEFT = LAYOUT.disc / 2
local ROUND = UDim.new(0.5, 0)

local PUNCH_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local ui: any = {}
local view: any = nil
local receivedAt = 0
local listeners: { (view: any, previous: any) -> () } = {}

-- ── Formatting ────────────────────────────────────────────────────────────

--- 9,150 in full under ten thousand (every point still moves while the early levels
--- come quickly), then 12.4K / 1.30M / 2.1B.
function Speed.format(points: number): string
	local n = math.floor(points)
	if n >= 1_000_000_000 then
		return string.format("%.2fB", n / 1_000_000_000)
	elseif n >= 1_000_000 then
		return string.format("%.2fM", n / 1_000_000)
	elseif n >= 10_000 then
		return string.format("%.1fK", n / 1_000)
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
function Speed.shownPoints(): number
	if view == nil then
		return 0
	end
	if not view.training then
		return view.points
	end
	local lead = math.min(os.clock() - receivedAt, LEAD_CAP)
	return view.points + view.rate * lead
end

--- Called with (view, previous) on every SpeedState push.
function Speed.onChanged(fn: (view: any, previous: any) -> ())
	table.insert(listeners, fn)
end

-- ── The badge ─────────────────────────────────────────────────────────────

local function blob(parent: Instance, name: string, rect: { number }, color: Color3, zIndex: number, radius: UDim, stroke: number?): Frame
	local frame = UIKit.panel(parent, {
		name = name,
		position = UDim2.fromOffset(rect[1], rect[2]),
		size = UDim2.fromOffset(rect[3], rect[4]),
		color = color,
		transparency = 0,
		cornerRadius = radius,
		strokeColor = INK,
		strokeThickness = stroke or 0,
		zIndex = zIndex,
	})
	return frame
end

local function setStroke(label: TextLabel, thickness: number)
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = thickness
	end
end

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
	badge.Position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 0.5, Dock.SPEED_MID_Y)
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 2
	badge.Parent = canvas
	ui.badge = badge

	ui.punch = Instance.new("UIScale")
	ui.punch.Parent = badge

	local L = LAYOUT
	local cardW = BADGE_W - CARD_LEFT
	local cardRadius = UDim.new(0, L.cardRadius)

	blob(badge, "CardShadow", { CARD_LEFT, L.cardTop + L.shadowDrop, cardW, L.cardHeight }, INK, 1, cardRadius)
	local card = blob(badge, "Card", { CARD_LEFT, L.cardTop, cardW, L.cardHeight }, STYLE.card, 2, cardRadius, L.outline)
	local shineLeft = L.valueLeft - CARD_LEFT - 2
	blob(card, "Shine", { shineLeft, 6, cardW - shineLeft - 8, 12 }, STYLE.cardShine, 3, ROUND)

	-- The disc, breaking out past the card's left end like the cash coin.
	local discTop = L.cardTop + L.cardHeight / 2 - L.disc / 2
	blob(badge, "DiscShadow", { 0, discTop + L.shadowDrop, L.disc, L.disc }, INK, 6, ROUND)
	local disc = blob(badge, "Disc", { 0, discTop, L.disc, L.disc }, STYLE.disc, 7, ROUND, L.outline)
	local inset = 7
	blob(disc, "Face", { inset, inset, L.disc - inset * 2, L.disc - inset * 2 }, STYLE.discFace, 8, ROUND)
	-- Full colour with its own ink outline baked in, so it stays untinted.
	local shoe = Artwork.picture(disc, "Shoe", Artwork.IMAGE.speedShoe, L.shoe, WHITE)
	shoe.Position = UDim2.fromOffset((L.disc - L.shoe) / 2, (L.disc - L.shoe) / 2)
	shoe.ZIndex = 10

	UIKit.label(badge, {
		name = "Caption",
		position = UDim2.fromOffset(L.valueLeft, L.cardTop + 3),
		size = UDim2.fromOffset(120, 16),
		font = STYLE.captionFont,
		textSize = L.captionTextSize,
		color = STYLE.caption,
		xAlign = Enum.TextXAlignment.Left,
		shadow = false,
		text = "SPEED",
		zIndex = 11,
	})
	ui.value = UIKit.label(badge, {
		name = "Value",
		position = UDim2.fromOffset(L.valueLeft, L.cardTop + 16),
		size = UDim2.fromOffset(BADGE_W - L.valueLeft - 12, 32),
		font = STYLE.valueFont,
		textSize = L.valueTextSize,
		color = WHITE,
		xAlign = Enum.TextXAlignment.Left,
		shadow = false,
		text = "0",
		zIndex = 11,
	})
	setStroke(ui.value, L.valueStroke)

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

	-- The counter, every frame. Cheap: one string format, and nothing at all when the
	-- text would not change (an idle player's number is static).
	local lastText = ""
	RunService.RenderStepped:Connect(function()
		local text = Speed.format(Speed.shownPoints())
		if text ~= lastText then
			lastText = text
			ui.value.Text = text
		end
	end)
end

return Speed
