--[[
	SuitWarningController.lua — the "!! UPGRADE SUIT" warning for a player out of their depth.

	The rad meter already says SUIT FAILING and counts down, and RadFx whitens the
	screen, but none of that says WHAT TO DO about it. A new player who walks one stage
	too far just watches their health melt. This names the fix: a better suit — or,
	past the top of the ladder, to turn back. Just red words and "!!" floating near the
	top of the screen with an ink outline, no card behind them, and a small IGNORE
	button beside them.

	IT ONLY SHOWS FOR HEAVY DAMAGE. A toe over the suit's rating burns slowly and the
	meter's own countdown is enough for that. It waits until the burn would put
	you down inside HEAVY_SECONDS, or has already taken you under HEAVY_HEALTH, and has
	held for SHOW_DELAY — so brushing a stage line does not flash it.

	IGNORE LASTS ONE TRIP. It hides the warning until the suit is holding again (you
	walked back out) or you go down; the next time you push too deep it warns again.

	IT SITS AS HIGH AS THE TOP OF THE SCREEN ALLOWS. The warp bar is hidden in a stage,
	which is the only place this shows, so it hugs the top edge — but the stage title
	card and the tutorial banner share that strip, and while either is up the warning
	slides down under it (clearTop).

	NO NEW FIELD ON THE WIRE. ExposureState carries `ambient`, `excess` and `failing`,
	and Radiation.resolve defines excess as ambient minus suit tolerance. Whether any
	suit could hold this air is a Gear.Suit rung whose tolerance reaches `ambient`. The
	burn is recomputed from `excess` rather than read off `healthBurn`, because
	`healthBurn` also carries a detonated crater's burn, which no suit helps with.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local SuitWarningController = {}

-- Heavy damage: the suit's burn alone would down you within this many seconds...
local HEAVY_SECONDS = 45
-- ...or it has already taken you under this fraction of max health.
local HEAVY_HEALTH = 0.6
-- Heavy has to hold this long before the warning shows, and the suit has to be holding
-- again for HIDE_DELAY before it goes, so walking the stage line does not strobe it.
local SHOW_DELAY = 0.75
local HIDE_DELAY = 1.5

-- Design px on the 1280x720 canvas.
local TOP_Y = 16 -- with nothing else up there
local CLEARANCE = 8 -- under whatever top banner is showing
local WARNING_W = 520
local WARNING_H = 40
local TITLE_SIZE = 28
local BANG_SIZE = 34
local GAP = 10
local IGNORE_W = 62
local IGNORE_H = 22
local IGNORE_GAP = 14
local FONT = Enum.Font.LuckiestGuy

-- The top-of-screen pieces the warning must not sit on: ScreenGui name -> the frame in
-- it that is drawn only while showing (StageBannerController, TutorialController,
-- WarpController).
local TOP_BANNERS = {
	{ gui = "StageBanner", frame = "Panel" },
	{ gui = "TutorialHud", frame = "Banner" },
	{ gui = "WarpBar", frame = "Panel" },
}

local RED = UIKit.C.red
local INK = Color3.fromHex("1A1A1A")

local POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local ui: any = {}

local reading = {
	failing = false,
	downed = false,
	ambient = 0,
	excess = 0,
	health = 100,
	maxHealth = 100,
}

local shown = false
local ignored = false
local heavyFor = 0
local calmFor = 0
local throb = 0

--- HP/sec from the SUIT alone — Radiation.resolve's burn term, without the crater.
local function suitBurn(): number
	if not reading.failing or reading.excess <= 0 then
		return 0
	end
	return Tuning.BURN_COEF * (reading.excess ^ Tuning.BURN_EXPONENT)
end

local function isHeavy(): boolean
	if reading.downed then
		return false
	end
	local burn = suitBurn()
	if burn <= 0 then
		return false
	end
	local healthFrac = reading.health / math.max(reading.maxHealth, 1)
	return reading.health / burn <= HEAVY_SECONDS or healthFrac <= HEAVY_HEALTH
end

--- Whether any rung of Gear.Suit would hold this air. Past the top of the ladder
--- there is nothing to upgrade to, so the warning says to turn back instead.
local function anySuitHolds(ambient: number): boolean
	for _, tier in Gear.Suit do
		if tier.tolerance >= ambient then
			return true
		end
	end
	return false
end

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 200)).X
end

--- Put a label (and the shadow UIKit hung beside it) at `x`, `width` wide.
local function place(label: TextLabel, shadow: TextLabel?, x: number, width: number)
	label.Size = UDim2.fromOffset(width, WARNING_H)
	label.Position = UDim2.fromOffset(x, 0)
	if shadow then
		shadow.Size = label.Size
		shadow.Position = label.Position + UDim2.fromOffset(UIKit.TextShadow.offset.X, UIKit.TextShadow.offset.Y)
	end
end

--- "!!" and the words side by side, centred as a pair whatever the words' width, with
--- IGNORE hung off to the right so the warning itself stays centred.
local function layoutRow()
	local bangW = textWidth(ui.badge.Text, BANG_SIZE)
	local titleW = textWidth(ui.title.Text, TITLE_SIZE)
	local x = (WARNING_W - (bangW + GAP + titleW)) / 2
	place(ui.badge, ui.badgeShadow, x, bangW)
	place(ui.title, ui.titleShadow, x + bangW + GAP, titleW)
	ui.ignore.Position = UDim2.new(0, x + bangW + GAP + titleW + IGNORE_GAP, 0.5, 0)
end

local function refreshText()
	local text = if anySuitHolds(reading.ambient) then "UPGRADE SUIT" else "TURN BACK"
	if ui.title.Text ~= text then
		ui.title.Text = text
		layoutRow()
	end
end

--- The highest design-px Y the warning can take without covering a top banner. Only a
--- banner in the warning's way moves it: the stage title and the tutorial banner both
--- sit below y 16, and dropping under them anyway just parked the warning over the field.
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
	-- Top-down, so a banner the warning was pushed onto pushes it on in turn.
	table.sort(spans, function(a, b)
		return a.top < b.top
	end)
	for _, span in spans do
		if span.top < y + WARNING_H + CLEARANCE and span.bottom + CLEARANCE > y then
			y = span.bottom + CLEARANCE
		end
	end
	return y
end

local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	if on then
		refreshText()
		ui.root.Position = UDim2.new(0.5, 0, 0, clearTop())
		ui.root.Visible = true
		ui.group.GroupTransparency = 0
		ui.scale.Scale = 0.6
		TweenService:Create(ui.scale, POP, { Scale = 1 }):Play()
	else
		local tween = TweenService:Create(ui.group, FADE, { GroupTransparency = 1 })
		tween.Completed:Connect(function()
			if not shown then
				ui.root.Visible = false
			end
		end)
		tween:Play()
	end
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "SuitWarning"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Over the RadFx overlay (RadHud is 100) so a whitening screen cannot bury it, and
	-- under the blackout curtain's moment, which hides this warning anyway (downed).
	gui.DisplayOrder = 101
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local canvas = UIKit.canvas(gui)

	-- A CanvasGroup so the "!!", the words and the button (and their outlines) fade as one.
	local root = Instance.new("Frame")
	root.Name = "Warning"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, TOP_Y)
	root.Size = UDim2.fromOffset(WARNING_W, WARNING_H)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = canvas

	local scale = Instance.new("UIScale")
	scale.Parent = root

	local group = Instance.new("CanvasGroup")
	group.Name = "Group"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Parent = root

	-- The throb, on its own UIScale: the pop-in tweens the root's, and one UIScale
	-- driven by both a tween and the heartbeat would fight for a few frames.
	local throbScale = Instance.new("UIScale")
	throbScale.Parent = group

	-- Red with UIKit's heavy ink outline and drop shadow, so it reads over bright sky
	-- and the RadFx whiteout alike. Plain ASCII "!" on purpose — the warning-sign glyphs
	-- render as colour emoji or boxes in Roblox. Laid out by hand (layoutRow), not by a
	-- UIListLayout: UIKit's shadow is a SIBLING label, and a list layout would line it
	-- up as another word.
	local function word(name: string, text: string, size: number): TextLabel
		return UIKit.label(group, {
			name = name,
			size = UDim2.fromOffset(0, WARNING_H),
			text = text,
			font = FONT,
			textSize = size,
			color = RED,
			xAlign = Enum.TextXAlignment.Center,
			shadow = true,
		})
	end
	local badge = word("Bang", "!!", BANG_SIZE)
	local title = word("Title", "UPGRADE SUIT", TITLE_SIZE)

	local ignore = UIKit.button(group, {
		name = "Ignore",
		anchorPoint = Vector2.new(0, 0.5),
		size = UDim2.fromOffset(IGNORE_W, IGNORE_H),
		text = "IGNORE",
		font = Enum.Font.FredokaOne,
		textSize = 12,
		color = Color3.new(1, 1, 1),
		fillColor = INK,
		fillTransparency = 0.25,
		strokeThickness = 1.5,
		cornerRadius = UDim.new(0.5, 0),
		shadow = false,
		zIndex = 3,
	})
	ignore.MouseEnter:Connect(function()
		ignore.BackgroundTransparency = 0.05
	end)
	ignore.MouseLeave:Connect(function()
		ignore.BackgroundTransparency = 0.25
	end)
	ignore.Activated:Connect(function()
		ignored = true
		setShown(false)
	end)

	ui = {
		canvas = canvas,
		root = root,
		group = group,
		scale = scale,
		throbScale = throbScale,
		title = title,
		titleShadow = group:FindFirstChild("TitleShadow"),
		badge = badge,
		badgeShadow = group:FindFirstChild("BangShadow"),
		ignore = ignore,
	}
	layoutRow()
	return gui
end

local function step(dt: number)
	if isHeavy() then
		heavyFor += dt
		calmFor = 0
	else
		heavyFor = 0
		-- Downed hides at once: the curtain is already the loudest thing on screen.
		calmFor = if reading.downed then HIDE_DELAY else calmFor + dt
	end

	-- An ignore holds until this trip is over: back under the suit's rating, or down.
	if ignored and (reading.downed or (not reading.failing and calmFor >= HIDE_DELAY)) then
		ignored = false
	end

	-- Stays up while the suit is still failing, even if the damage eases off, and only
	-- goes once it has actually been holding for HIDE_DELAY.
	if not shown and not ignored and heavyFor >= SHOW_DELAY then
		setShown(true)
	elseif shown and (reading.downed or (not reading.failing and calmFor >= HIDE_DELAY)) then
		setShown(false)
	end

	if shown then
		-- The air changes as you walk deeper (or back), and the advice with it.
		refreshText()
		-- Glide under a top banner that slides in, and back up once it goes.
		local y = ui.root.Position.Y.Offset
		y += (clearTop() - y) * math.min(1, dt * 12)
		ui.root.Position = UDim2.new(0.5, 0, 0, y)
		throb += dt * 6
		ui.throbScale.Scale = 1 + 0.035 * math.abs(math.sin(throb))
		local wobble = math.sin(throb * 1.3) * 8
		ui.badge.Rotation = wobble
		if ui.badgeShadow then
			ui.badgeShadow.Rotation = wobble
		end
	else
		throb = 0
	end
end

function SuitWarningController.start()
	local gui = build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	Net.get("ExposureState").OnClientEvent:Connect(function(payload)
		reading.failing = payload.failing == true
		reading.downed = payload.downed == true
		reading.ambient = payload.ambient or 0
		reading.excess = payload.excess or 0
		reading.maxHealth = payload.maxHealth or reading.maxHealth
		reading.health = payload.health or reading.health
	end)

	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn(`[suitwarning] step failed: {err}`)
		end
	end)
end

return SuitWarningController
