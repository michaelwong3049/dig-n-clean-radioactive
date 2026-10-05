--!strict
--[[
	LuckBoostController.luau — the banner when the Violet Aurora arrives (or a Lucky
	Clover is bought), and the aurora's lights (Config/LuckBoost).

	IT DECIDES NOTHING. Whether you are lucky is the server's answer (StatResolver,
	LuckBoostService); this reads the two clocks the server publishes as attributes --
	the event's end on ReplicatedStorage, the bought clover's end on the Player -- and
	draws them. Attributes rather than a remote because both are state a late joiner
	needs the instant they arrive (Config/LuckBoost's replication note).

	THE CLOVER BADGE THAT USED TO SIT IN THE BOTTOM-RIGHT CORNER IS GONE: the luck total
	and its countdown are now the Luck pill of the Boosts widget (BoostsController),
	beside every other multiplier, so players see one luck number instead of two.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local LuckBoost = require(Shared.Config.LuckBoost)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)
local CloverArt = require(script.Parent.Parent.CloverArt)
local AuroraFx = require(script.Parent.Parent.AuroraFx)

local LuckBoostController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

local STYLE = {
	numberFont = Enum.Font.LuckiestGuy,
	textFont = Enum.Font.FredokaOne,
}

local BANNER_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BANNER_OUT = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BANNER_HOLD = 3.6

type Ui = {
	gui: ScreenGui,
	canvas: Frame,
	banner: CanvasGroup,
	bannerScale: UIScale,
	bannerTitle: TextLabel,
	bannerSub: TextLabel,
}

local ui: Ui
local bannerToken = 0
-- The clover's last end time, and whether the first value has arrived yet: the one the
-- server publishes on load is a baseline, not a purchase.
local lastPersonal = 0
local seenPersonal = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function eventEndsAt(): number
	local value = ReplicatedStorage:GetAttribute(LuckBoost.EVENT_ATTR)
	return if type(value) == "number" then value else 0
end

local function personalEndsAt(): number
	local value = Players.LocalPlayer:GetAttribute(LuckBoost.PERSONAL_ATTR)
	return if type(value) == "number" then value else 0
end

--- "9:42", or "1:04:10" past an hour.
local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local r = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

local function ink(label: TextLabel, thickness: number)
	label.TextStrokeTransparency = 1
	local stroke = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
end

local function text(parent: Instance, name: string, font: Enum.Font, size: number, z: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = WHITE
	label.ZIndex = z
	label.Parent = parent
	ink(label, math.max(2, size * 0.1))
	return label
end

-- ── Build ─────────────────────────────────────────────────────────────

local function buildBanner(canvas: Frame): (CanvasGroup, UIScale, TextLabel, TextLabel)
	-- A CanvasGroup so the whole card fades as one: UIKit-style UIStroke outlines do
	-- not fade with TextTransparency, GroupTransparency takes them too.
	local banner = Instance.new("CanvasGroup")
	banner.Name = "LuckBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.24)
	banner.Size = UDim2.fromOffset(620, 130)
	banner.BackgroundTransparency = 1
	banner.GroupTransparency = 1
	banner.Visible = false
	banner.ZIndex = 40
	banner.Parent = canvas

	local scale = Instance.new("UIScale")
	scale.Parent = banner

	local title = text(banner, "Title", STYLE.numberFont, 50, 42)
	title.Size = UDim2.new(1, 0, 0, 62)
	title.Position = UDim2.fromOffset(0, 6)
	ink(title, 4.5)

	local sub = text(banner, "Subtitle", STYLE.textFont, 26, 42)
	sub.Size = UDim2.new(1, 0, 0, 34)
	sub.Position = UDim2.fromOffset(0, 70)
	ink(sub, 3)

	-- A clover either side of the title.
	for i, side in { -1, 1 } do
		local c = CloverArt.build(banner, 54, 41)
		c.Name = `Clover{i}`
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.new(0.5, side * 262, 0, 38)
		c.Rotation = side * 14
	end

	return banner, scale, title, sub
end

local function build(): Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = "LuckBoost"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Beside the Index/Shop tiles (55); the banner is a one-off over the field.
	gui.DisplayOrder = 56
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local banner, bannerScale, bannerTitle, bannerSub = buildBanner(canvas)

	return {
		gui = gui,
		canvas = canvas,
		banner = banner,
		bannerScale = bannerScale,
		bannerTitle = bannerTitle,
		bannerSub = bannerSub,
	}
end

-- ── Behaviour ─────────────────────────────────────────────────────────

local function currentMultiplier(): number
	local t = now()
	return LuckBoost.multiplier(eventEndsAt() > t, personalEndsAt() > t)
end

--- The banner's clovers and title in the colour of the multiplier it leaves you on.
local function showBanner(title: string, subtitle: string)
	bannerToken += 1
	local token = bannerToken
	local banner = ui.banner
	local palette = CloverArt.paletteFor(currentMultiplier())
	for _, child in banner:GetChildren() do
		if string.sub(child.Name, 1, 6) == "Clover" then
			CloverArt.paint(child, palette)
		end
	end
	ui.bannerTitle.TextColor3 = palette.shine
	ui.bannerTitle.Text = title
	ui.bannerSub.Text = subtitle
	banner.Visible = true
	banner.GroupTransparency = 1
	ui.bannerScale.Scale = 0.6
	TweenService:Create(banner, BANNER_IN, { GroupTransparency = 0 }):Play()
	TweenService:Create(ui.bannerScale, BANNER_IN, { Scale = 1 }):Play()
	task.delay(BANNER_HOLD, function()
		if token ~= bannerToken then
			return
		end
		TweenService:Create(banner, BANNER_OUT, { GroupTransparency = 1 }):Play()
		TweenService:Create(ui.bannerScale, BANNER_OUT, { Scale = 1.08 }):Play()
		task.delay(BANNER_OUT.Time, function()
			if token == bannerToken then
				banner.Visible = false
			end
		end)
	end)
end

local function refresh(t: number)
	AuroraFx.setActive(eventEndsAt() > t)
end

local function onEventChanged()
	local t = now()
	local started = ReplicatedStorage:GetAttribute(LuckBoost.EVENT_START_ATTR)
	local ends = eventEndsAt()
	-- Only an aurora that has JUST begun gets the banner. Joining mid-event you see the
	-- sky and the clover; being told it "arrived" ten minutes late would be wrong.
	if ends > t and type(started) == "number" and t - started < 5 then
		Sfx.play("aurora")
		showBanner(string.upper(LuckBoost.EVENT_NAME), `{LuckBoost.MULT}x LUCK for {clock(ends - started)}!`)
	end
end

local function onPersonalChanged()
	local value = Players.LocalPlayer:GetAttribute(LuckBoost.PERSONAL_ATTR)
	if type(value) ~= "number" then
		return
	end
	-- More time than before, by more than rounding: a purchase (or a debug grant).
	if seenPersonal then
		local before = math.max(lastPersonal, now())
		if value > before + 5 then
			showBanner("LUCKY CLOVER", `{LuckBoost.MULT}x LUCK  +{clock(value - before)}`)
		end
	end
	seenPersonal = true
	lastPersonal = value
end

function LuckBoostController.start()
	local player = Players.LocalPlayer
	ui = build()
	ui.gui.Parent = player:WaitForChild("PlayerGui")

	ReplicatedStorage:GetAttributeChangedSignal(LuckBoost.EVENT_ATTR):Connect(onEventChanged)
	player:GetAttributeChangedSignal(LuckBoost.PERSONAL_ATTR):Connect(onPersonalChanged)
	onPersonalChanged()

	-- The aurora's lights follow the event clock. One attribute read a frame.
	RunService.Heartbeat:Connect(function()
		refresh(now())
	end)
end

return LuckBoostController
