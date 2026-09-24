--[[
	SuitWarningController.lua — the "UPGRADE SUIT" card for a player out of their depth.

	The rad meter already says SUIT FAILING and counts down, and RadFx whitens the
	screen, but none of that says WHAT TO DO about it. A new player who walks one stage
	too far just watches their health melt. This card names the fix: the suit that
	would hold this air, and what it costs — or, past the top of the ladder, to turn
	back.

	IT ONLY SHOWS FOR HEAVY DAMAGE. A toe over the suit's rating burns slowly and the
	meter's own countdown is enough for that. The card waits until the burn would put
	you down inside HEAVY_SECONDS, or has already taken you under HEAVY_HEALTH, and has
	held for SHOW_DELAY — so brushing a stage line does not flash it.

	NO NEW FIELD ON THE WIRE. ExposureState carries `ambient`, `excess` and `failing`,
	and Radiation.resolve defines excess as ambient minus suit tolerance, so the
	equipped suit's tolerance is their difference and the suit that would hold this air
	is the first Gear.Suit rung whose tolerance reaches `ambient`. The burn is
	recomputed from `excess` rather than read off `healthBurn`, because `healthBurn`
	also carries a detonated crater's burn, which no suit helps with.

	WHITE AND INK, because white is suit failure's colour and nothing else's
	(HudController's ONE COLOUR RULE) — this card is about exactly that.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
-- Heavy has to hold this long before the card shows, and the suit has to be holding
-- again for HIDE_DELAY before it goes, so walking the stage line does not strobe it.
local SHOW_DELAY = 0.75
local HIDE_DELAY = 1.5

-- Design px on the 1280x720 canvas. Under WarpController's bar (to 68), the stage
-- title card (34..~100) and TutorialController's banner (84..~170).
local CARD_Y = 196
local CARD_W = 440
local CARD_H = 82
local SHADOW_DROP = 5
local BADGE = 46

local INK = Color3.fromHex("1A1A1A")
local WHITE = UIKit.C.burn
local SUB = Color3.fromHex("4A4A4A")

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
local heavyFor = 0
local calmFor = 0
local throb = 0

--- CashController.formatCash's ladder ($340, $5.2K, $1.4M), minus a trailing ".0":
--- every suit price is a round number, and "$15.0K" reads as a typo on a warning.
local function formatCash(amount: number): string
	local text
	if amount >= 1_000_000_000 then
		text = string.format("$%.1fB", amount / 1_000_000_000)
	elseif amount >= 1_000_000 then
		text = string.format("$%.1fM", amount / 1_000_000)
	elseif amount >= 1_000 then
		text = string.format("$%.1fK", amount / 1_000)
	else
		return string.format("$%d", math.floor(amount))
	end
	return (string.gsub(text, "%.0([KMB])$", "%1"))
end

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

--- The rung you are wearing (by tolerance, the one number the wire gives us) and the
--- first rung that would hold this air, or nil past the top of the ladder.
local function suitsFor(ambient: number, excess: number)
	local tolerance = ambient - excess
	local current = Gear.Suit[1]
	for _, tier in Gear.Suit do
		if tier.tolerance <= tolerance + 1e-3 then
			current = tier
		end
	end
	for _, tier in Gear.Suit do
		if tier.tolerance >= ambient then
			return current, tier
		end
	end
	return current, nil
end

local function refreshText()
	local current, needed = suitsFor(reading.ambient, reading.excess)
	if needed then
		ui.title.Text = "UPGRADE SUIT"
		ui.sub.Text = `{current.name} can't hold this air. {needed.name} can ({formatCash(needed.price)})`
	else
		ui.title.Text = "TURN BACK"
		ui.sub.Text = "No suit holds this air. Get out before it drops you"
	end
end

local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	if on then
		refreshText()
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
	-- under the blackout curtain's moment, which hides this card anyway (downed).
	gui.DisplayOrder = 101
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local canvas = UIKit.canvas(gui)

	-- A CanvasGroup so the whole card (outline, shadow, text) fades as one.
	local root = Instance.new("Frame")
	root.Name = "Warning"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, CARD_Y)
	root.Size = UDim2.fromOffset(CARD_W, CARD_H + SHADOW_DROP)
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

	UIKit.panel(group, {
		name = "Shadow",
		position = UDim2.fromOffset(0, SHADOW_DROP),
		size = UDim2.fromOffset(CARD_W, CARD_H),
		color = INK,
		transparency = 0,
		cornerRadius = UDim.new(0, 18),
		strokeThickness = 0,
		zIndex = 1,
	})
	local card = UIKit.panel(group, {
		name = "Card",
		size = UDim2.fromOffset(CARD_W, CARD_H),
		color = WHITE,
		transparency = 0,
		cornerRadius = UDim.new(0, 18),
		strokeColor = INK,
		strokeThickness = 4,
		zIndex = 2,
	})

	-- The hazard badge: an ink disc with a white "!". Plain ASCII on purpose — the
	-- warning-sign glyphs render as colour emoji or boxes in Roblox.
	local badge = UIKit.panel(card, {
		name = "Badge",
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.new(0, 16, 0.5, 0),
		size = UDim2.fromOffset(BADGE, BADGE),
		color = INK,
		transparency = 0,
		cornerRadius = UDim.new(0.5, 0),
		strokeThickness = 0,
		zIndex = 3,
	})
	UIKit.label(badge, {
		name = "Bang",
		size = UDim2.fromScale(1, 1),
		text = "!",
		font = Enum.Font.LuckiestGuy,
		textSize = 34,
		color = WHITE,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		zIndex = 4,
	})

	local textX = 16 + BADGE + 14
	local title = UIKit.label(card, {
		name = "Title",
		position = UDim2.fromOffset(textX, 10),
		size = UDim2.new(1, -textX - 16, 0, 36),
		font = Enum.Font.LuckiestGuy,
		textSize = 32,
		color = INK,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		zIndex = 3,
	})
	local sub = UIKit.label(card, {
		name = "Sub",
		position = UDim2.fromOffset(textX, 46),
		size = UDim2.new(1, -textX - 16, 0, 24),
		font = Enum.Font.FredokaOne,
		textSize = 15,
		color = SUB,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
		zIndex = 3,
	})
	sub.TextScaled = true
	local subSize = Instance.new("UITextSizeConstraint")
	subSize.MaxTextSize = 15
	subSize.Parent = sub

	ui = { root = root, group = group, scale = scale, throbScale = throbScale, title = title, sub = sub, badge = badge }
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

	-- Stays up while the suit is still failing, even if the damage eases off, and only
	-- goes once it has actually been holding for HIDE_DELAY.
	if not shown and heavyFor >= SHOW_DELAY then
		setShown(true)
	elseif shown and (reading.downed or (not reading.failing and calmFor >= HIDE_DELAY)) then
		setShown(false)
	end

	if shown then
		-- The air changes as you walk deeper (or back), and the advice with it.
		refreshText()
		throb += dt * 6
		ui.throbScale.Scale = 1 + 0.035 * math.abs(math.sin(throb))
		ui.badge.Rotation = math.sin(throb * 1.3) * 8
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
