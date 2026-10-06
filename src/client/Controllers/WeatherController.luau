--!strict
--[[
	WeatherController.luau — Golden Hour and the Meteor Shower on this client
	(Config/Weather): the banner when one arrives, its effects in the air (WeatherFx),
	the stars for the shower's night, and the meteors themselves (Net MeteorFall).

	IT DECIDES NOTHING, like LuckBoostController (which still draws the Violet Aurora).
	Which weather is up is two ReplicatedStorage attributes per weather, written by
	WeatherService; the sky itself is AtmosphereController's; the countdown and the
	2x cash are the Cash pill of the Boosts widget (StatResolver.boosts).
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Weather = require(Shared.Config.Weather)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)
local WeatherFx = require(script.Parent.Parent.WeatherFx)

local WeatherController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

-- Each weather's banner: the title colour and the line under it.
local BANNERS = {
	golden = {
		color = Color3.fromHex("FFC94A"),
		line = `{Weather.GOLDEN_MULT}x CASH for {math.floor(Weather.DEFS.golden.seconds / 60)} min!`,
	},
	meteor = {
		color = Color3.fromHex("FF9A4A"),
		line = `Meteors are landing - dig them up for {Weather.METEOR_LUCK}x luck!`,
	},
}

-- build/Daylight ships StarCount 0 (a day sky); the shower's night needs stars.
local SHOWER_STARS = 3000

local BANNER_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BANNER_OUT = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BANNER_HOLD = 3.6

local banner: CanvasGroup
local bannerScale: UIScale
local bannerTitle: TextLabel
local bannerSub: TextLabel
local bannerToken = 0

local function ink(label: TextLabel, thickness: number)
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
end

local function text(parent: Instance, name: string, font: Enum.Font, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = WHITE
	label.ZIndex = 42
	label.Parent = parent
	return label
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Weather"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- The same layer as the aurora's banner (LuckBoostController); only one weather
	-- is ever up, so the two never show at once.
	gui.DisplayOrder = 56
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	-- A CanvasGroup so the whole card fades as one, UIStroke outlines included.
	banner = Instance.new("CanvasGroup")
	banner.Name = "WeatherBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.24)
	banner.Size = UDim2.fromOffset(720, 130)
	banner.BackgroundTransparency = 1
	banner.GroupTransparency = 1
	banner.Visible = false
	banner.ZIndex = 40
	banner.Parent = canvas

	bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	bannerTitle = text(banner, "Title", Enum.Font.LuckiestGuy, 50)
	bannerTitle.Size = UDim2.new(1, 0, 0, 62)
	bannerTitle.Position = UDim2.fromOffset(0, 6)
	ink(bannerTitle, 4.5)

	bannerSub = text(banner, "Subtitle", Enum.Font.FredokaOne, 26)
	bannerSub.Size = UDim2.new(1, 0, 0, 34)
	bannerSub.Position = UDim2.fromOffset(0, 70)
	ink(bannerSub, 3)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function showBanner(title: string, subtitle: string, color: Color3)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color
	bannerSub.Text = subtitle
	banner.Visible = true
	banner.GroupTransparency = 1
	bannerScale.Scale = 0.6
	TweenService:Create(banner, BANNER_IN, { GroupTransparency = 0 }):Play()
	TweenService:Create(bannerScale, BANNER_IN, { Scale = 1 }):Play()
	task.delay(BANNER_HOLD, function()
		if token ~= bannerToken then
			return
		end
		TweenService:Create(banner, BANNER_OUT, { GroupTransparency = 1 }):Play()
		TweenService:Create(bannerScale, BANNER_OUT, { Scale = 1.08 }):Play()
		task.delay(BANNER_OUT.Time, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end)
end

local function refresh()
	local golden = Weather.active("golden")
	local meteor = Weather.active("meteor")
	WeatherFx.setGolden(golden)
	WeatherFx.setMeteors(meteor)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.StarCount = if meteor then SHOWER_STARS else 0
	end
end

local function onChanged(id: string)
	refresh()
	local def = Weather.get(id)
	local started = ReplicatedStorage:GetAttribute(def.startAttr)
	-- Only a weather that has JUST begun gets the banner, not one you joined into.
	if Weather.active(id) and type(started) == "number" and Workspace:GetServerTimeNow() - started < 5 then
		local style = BANNERS[id]
		Sfx.play("aurora")
		showBanner(string.upper(def.name), style.line, style.color)
	end
end

function WeatherController.start()
	build()

	for id in BANNERS do
		ReplicatedStorage:GetAttributeChangedSignal(Weather.get(id).endsAttr):Connect(function()
			onChanged(id)
		end)
	end

	Net.get("MeteorFall").OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and typeof(payload.position) == "Vector3" and type(payload.landsAt) == "number" then
			WeatherFx.fall(payload.position, payload.landsAt)
		end
	end)

	-- The belt to the attributes' brace: a clock that runs out with nothing changing.
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
end

return WeatherController
