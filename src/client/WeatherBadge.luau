--!strict
--[[
	WeatherBadge.luau — while a weather is up (Config/Weather), a badge sits right
	above the Boosts widget's "CURRENT BOOSTS": the weather's picture, its name and how
	long is left. On request (2026-10-09): "when a weather event happens,
	put it somewhere, like a luck icon or cash icon for the event with the timer".

	  VIOLET AURORA   the purple clover (luck past x2's green)
	  GOLDEN HOUR     the cash picture the Cash line uses
	  METEOR SHOWER   a drawn fireball

	It decides nothing: the clock is each weather's endsAttr on ReplicatedStorage,
	re-read four times a second (WeatherController.start starts it). Same floating outlined
	text as the Boosts lines, no box. Hidden during the tutorial like the Boosts widget.

	POSITION: right edge flush with the Boosts widget, one GAP above its top
	(Dock.boostsTop), at the widget's scale -- and smaller still if the right column
	(Nukes / Potions) leaves less room than that on a short canvas.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Weather = require(Shared.Config.Weather)
local GamePasses = require(Shared.Config.GamePasses)

local UIKit = require(script.Parent.UIKit)
local CloverArt = require(script.Parent.CloverArt)
local TutorialGate = require(script.Parent.TutorialGate)
local Dock = UIKit.Dock
local House = UIKit.House

local WeatherBadge = {}

local W = Dock.BOOSTS_WIDTH + 40
local H = 58
local ICON = 50
local MIN_FIT = 0.5

local cashPass = GamePasses.byKey("cash")

-- Each weather's name colour (the banner's, WeatherController / LuckBoostController).
local LOOK: { [string]: Color3 } = {
	aurora = CloverArt.PURPLE.leaf,
	golden = Color3.fromHex("FFC94A"),
	meteor = Color3.fromHex("FF9A4A"),
}

local gui: ScreenGui
local canvas: Frame
local badge: Frame
local fit: UIScale
local nameLabel: TextLabel
local timeLabel: TextLabel
local icons: { [string]: GuiObject } = {}
local pulse: UIScale
local shown: string? = nil

local function stroke(parent: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = House.ink
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

local function label(name: string, size: number, thick: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = House.font
	l.TextSize = size
	l.TextColor3 = House.white
	l.TextStrokeTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Right
	l.ZIndex = 22
	l.Parent = badge
	stroke(l, thick)
	return l
end

--- A cartoon fireball: a hot round head with a tapering tail up and to the right.
local function fireball(parent: Instance): Frame
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = parent

	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.fromScale(0.62, 0.38)
	tail.Size = UDim2.fromScale(1, 0.42)
	tail.Rotation = -45
	tail.BorderSizePixel = 0
	tail.BackgroundColor3 = House.white
	tail.ZIndex = 22
	tail.Parent = root
	local tailRound = Instance.new("UICorner")
	tailRound.CornerRadius = UDim.new(0.5, 0)
	tailRound.Parent = tail
	local tailFade = Instance.new("UIGradient")
	-- Hot at the head (the frame's left end, down-left after the turn), gone at the tip.
	tailFade.Color = ColorSequence.new(Color3.fromHex("FFD34A"), Color3.fromHex("FF5A1F"))
	tailFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.35, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	tailFade.Parent = tail

	local head = Instance.new("Frame")
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.36, 0.64)
	head.Size = UDim2.fromScale(0.6, 0.6)
	head.BorderSizePixel = 0
	head.BackgroundColor3 = House.white
	head.ZIndex = 23
	head.Parent = root
	local headRound = Instance.new("UICorner")
	headRound.CornerRadius = UDim.new(0.5, 0)
	headRound.Parent = head
	local glow = Instance.new("UIGradient")
	glow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("FFF3A0")),
		ColorSequenceKeypoint.new(0.5, Color3.fromHex("FFA02E")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("E8401C")),
	})
	glow.Rotation = 45
	glow.Parent = head
	local edge = Instance.new("UIStroke")
	edge.Color = House.ink
	edge.Thickness = 2.5
	edge.Parent = head
	return root
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "WeatherBadge"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 56 -- the Boosts widget's layer
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	TutorialGate.bind(gui)
	canvas = UIKit.canvas(gui)

	badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 1)
	badge.Size = UDim2.fromOffset(W, H)
	badge.BackgroundTransparency = 1
	badge.Visible = false
	badge.Parent = canvas
	fit = Instance.new("UIScale")
	fit.Parent = badge

	-- The picture hard against the right edge, under the Boosts lines' pictures.
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.fromScale(1, 0.5)
	holder.Size = UDim2.fromOffset(ICON, ICON)
	holder.BackgroundTransparency = 1
	holder.Parent = badge
	pulse = Instance.new("UIScale")
	pulse.Parent = holder

	local clover = CloverArt.build(holder, ICON, 23, CloverArt.PURPLE)
	icons.aurora = clover
	local cash = Instance.new("ImageLabel")
	cash.BackgroundTransparency = 1
	cash.ScaleType = Enum.ScaleType.Fit
	cash.Size = UDim2.fromScale(1, 1)
	cash.Image = if cashPass then cashPass.image else ""
	cash.ZIndex = 23
	cash.Parent = holder
	icons.golden = cash
	icons.meteor = fireball(holder)

	nameLabel = label("Name", 17, 2)
	nameLabel.Size = UDim2.new(1, -(ICON + 8), 0, 20)
	nameLabel.Position = UDim2.fromOffset(0, 4)

	timeLabel = label("Time", 28, 3)
	timeLabel.Size = UDim2.new(1, -(ICON + 8), 0, 30)
	timeLabel.Position = UDim2.fromOffset(0, 24)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- A slow heartbeat on the picture so the eye finds it.
	local beat = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(pulse, beat, { Scale = 1.1 }):Play()
end

local function place()
	local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
	local _, scale = Dock.boostsLayout(height)
	local bottom = Dock.boostsTop(height) + Dock.GAP
	-- Room up to the right column's bottom; shrink to fit it.
	local room = height - Dock.rightColumnBottom(height) - Dock.GAP - bottom
	scale = math.clamp(math.min(scale, room / H), MIN_FIT, 1)
	fit.Scale = scale
	badge.Position = UDim2.new(1, -Dock.ROW_SIDE_MARGIN, 1, -bottom)
end

--- "4:32", or "1:04:10" past an hour.
local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h, m, r = s // 3600, (s % 3600) // 60, s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

--- Show the weather running now with its time left, or hide.
function WeatherBadge.refresh()
	if badge == nil then
		return
	end
	local id = Weather.current()
	if id == nil or LOOK[id] == nil then
		badge.Visible = false
		shown = nil
		return
	end
	if shown ~= id then
		shown = id
		for key, icon in icons do
			icon.Visible = key == id
		end
		nameLabel.Text = string.upper(Weather.get(id).name)
		nameLabel.TextColor3 = LOOK[id]
	end
	local left = Weather.endsAt(id) - Workspace:GetServerTimeNow()
	timeLabel.Text = clock(left)
	badge.Visible = true
end

function WeatherBadge.start()
	build()
	place()
	UIKit.onScaleChanged(place)
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	-- The countdown ticks; a few times a second so it never skips a number.
	task.spawn(function()
		while true do
			WeatherBadge.refresh()
			task.wait(0.25)
		end
	end)
end

return WeatherBadge
