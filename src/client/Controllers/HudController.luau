--[[
	HudController.lua — the rad meter the player actually plays against.

	The debug HUD shows every number at once because it is an instrument panel. This
	one shows almost none of them, because PLAN §3.1 escalates by FEEL, not by readout:

	  0-50%   nothing. Clean play, no UI shouting at you.
	  50-80%  sight starts going green at its edges, and the click bed comes up.
	  80-99%  vision distorts, the picture tears, the meter stops being ignorable.
	  100%    blackout.

	THE DAMAGE OVERLAY ITSELF LIVES IN RadFx. It used to be four gradient rectangles
	right here, which is why it read as UI rather than as dying; that file explains
	what replaced them and this one just hands it the escalation number.

	ONE COLOUR RULE (PLAN §14): exposure is GREEN, suit failure is WHITE, and they never
	share a shade. Green means "the meter is filling". White means "your suit is coming
	apart" — a different category of dying, not a worse degree of the same one. White is
	used exactly once in this entire game, which is why it will read instantly forever.

	THE METER NOW LIVES IN THE DOCK, not alone in the corner. See UIKit.Dock for the
	whole bottom-center layout — this file only needs to know its own offset within it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local RadFx = require(script.Parent.Parent.RadFx)
local Dock = UIKit.Dock

local Hud = {}

local GREEN = UIKit.C.green
local WHITE = UIKit.C.burn
local DIM = UIKit.C.dim

local state = {
	exposureFrac = 0,
	net = 0,
	failing = false,
	inShower = false,
	stageName = "Base Camp",
	downed = false,

	health = 100,
	maxHealth = 100,
	healthBurn = 0,
	ambient = 0,
	excess = 0,
	survivable = -1, -- -1 mirrors DebugService's "never" convention
	threat = "",
}

local ui = {}
local shakeSeed = 0

--- HOW FAR PAST YOUR SUIT'S RATING THIS AIR IS, 0..1. `failing` only ever answers
--- yes or no, and yes covers both "a stride over the line" and "this stage would
--- have killed three of you already" — one flag cannot tell a player which of those
--- they walked into.
---
--- No new field on the wire: ExposureState already carries `ambient` and `excess`,
--- and Radiation.resolve defines excess as ambient minus suit tolerance, so the
--- tolerance is just their difference and the ratio falls out. Divided by three
--- because three times your own tolerance is comfortably past any argument about
--- whether you meant to be here — a Rubber Suit reaches it in the Exclusion Belt,
--- which is exactly the walk this is meant to punish.
local function overTier(): number
	if state.excess <= 0 then
		return 0
	end
	local tolerance = math.max(state.ambient - state.excess, 0.5)
	return math.clamp(state.excess / tolerance / 3, 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- Mirrors DebugHudController's formatting exactly, so the countdown a player sees here
--- and the one a dev sees on F3 never disagree. -1 is "never" (indefinite), not a real
--- duration — see ExposureService's `finite()`.
local function clock(seconds: number): string
	if seconds < 0 then
		return "never"
	end
	if seconds >= 3600 then
		return "1h+"
	end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%d:%02d", m, s)
end

-- ── Build ───────────────────────────────────────────────────────────

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RadHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- The damage overlay. Not part of the dock — it is the whole screen, under every
	-- panel (ZIndex 2) and under the blackout curtain, which has to cover it.
	RadFx.build(gui)

	-- The meter. Bottom-left screen edge, clear of the dig button/dial cluster — it
	-- shares the dig button's baseline (Dock.INSTRUMENT_BOTTOM) so it still sits in
	-- the same reserved instrument row and never encroaches on the status line above
	-- or the bag count/hotbar below, just anchored to the left edge instead of the
	-- button's side. HEALTH and RADS stack as two instrument rows in one panel rather
	-- than two panels, so the dock's shared layout math (Dock.INSTRUMENT_HEIGHT and
	-- everything derived from it) never has to know a second panel exists — see
	-- UIKit.Dock.METER_SIZE's comment for why growing this panel taller is safe.
	local panel, meterStroke = UIKit.panel(gui, {
		name = "Meter",
		size = Dock.METER_SIZE,
		position = UDim2.new(0, Dock.ROW_SIDE_MARGIN, 1, -Dock.INSTRUMENT_BOTTOM),
		anchorPoint = Vector2.new(0, 1),
		color = UIKit.C.panel,
		transparency = 0.25,
		cornerRadius = UIKit.Radius.card,
		strokeThickness = UIKit.Stroke.thick,
		zIndex = 4,
	})
	ui.meterStroke = meterStroke

	--- One "CAPTION ... VALUE" row plus a rounded track/fill bar underneath, the
	--- shape both HEALTH and RADS share. Returns the pieces render() needs to drive.
	local function instrumentRow(prefix: string, y: number, captionText: string, barHeight: number)
		local caption = UIKit.label(panel, {
			name = prefix .. "Caption",
			position = UDim2.fromOffset(16, y),
			size = UDim2.new(1, -32, 0, 18),
			font = UIKit.Font.body,
			textSize = 16,
			color = DIM,
			text = captionText,
			zIndex = 4,
		})

		local value = UIKit.label(panel, {
			name = prefix .. "Value",
			position = UDim2.fromOffset(16, y),
			size = UDim2.new(1, -32, 0, 18),
			font = UIKit.Font.body,
			textSize = 16,
			color = DIM,
			xAlign = Enum.TextXAlignment.Right,
			zIndex = 4,
		})

		local track = Instance.new("Frame")
		track.Name = prefix .. "Track"
		track.Position = UDim2.fromOffset(16, y + 22)
		track.Size = UDim2.new(1, -32, 0, barHeight)
		track.BackgroundColor3 = UIKit.C.empty
		track.BackgroundTransparency = 0.25
		track.BorderSizePixel = 0
		track.ZIndex = 4
		track.Parent = panel

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0, barHeight / 2)
		trackCorner.Parent = track

		local fill = Instance.new("Frame")
		fill.Name = prefix .. "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = GREEN
		fill.BorderSizePixel = 0
		fill.ZIndex = 5
		fill.Parent = track

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, barHeight / 2)
		fillCorner.Parent = fill

		return caption, value, fill
	end

	-- Row 1: HEALTH — the taller, primary bar. Suit-failure countdown lives in the
	-- quiet row right underneath it, reserved but invisible until there's something
	-- to say (PLAN §3.1: escalate by feel, not by readout the player has to hunt for).
	ui.healthCaption, ui.healthValue, ui.healthFill = instrumentRow("Health", 8, "HEALTH", 16)

	ui.countdown = UIKit.label(panel, {
		name = "Countdown",
		position = UDim2.fromOffset(16, 50),
		size = UDim2.new(1, -32, 0, 16),
		font = UIKit.Font.body,
		textSize = 14,
		color = UIKit.C.burn,
		xAlign = Enum.TextXAlignment.Center,
		text = "",
		visible = false,
		zIndex = 4,
	})

	-- Row 2: RADS — the exposure meter, unchanged in spirit, just given the same
	-- caption+value shape as HEALTH above.
	ui.caption, ui.percentValue, ui.fill = instrumentRow("Rads", 72, "RADS", 14)

	ui.readout = UIKit.label(panel, {
		name = "Readout",
		position = UDim2.fromOffset(16, 112),
		size = UDim2.new(1, -32, 0, 16),
		font = UIKit.Font.body,
		textSize = 15,
		color = DIM,
		text = "",
		zIndex = 4,
	})

	ui.stageLabel = UIKit.label(panel, {
		name = "StageLabel",
		position = UDim2.fromOffset(16, 112),
		size = UDim2.new(1, -32, 0, 16),
		font = UIKit.Font.body,
		textSize = 13,
		color = DIM,
		xAlign = Enum.TextXAlignment.Right,
		text = "",
		zIndex = 4,
	})

	-- Blackout curtain. Full-screen background, unchanged; the text on it is bigger
	-- and centred exactly as before — it already lived at true screen-centre.
	ui.curtain = Instance.new("Frame")
	ui.curtain.Name = "Curtain"
	ui.curtain.Size = UDim2.fromScale(1, 1)
	ui.curtain.BackgroundColor3 = Color3.new(0, 0, 0)
	ui.curtain.BackgroundTransparency = 1
	ui.curtain.BorderSizePixel = 0
	ui.curtain.ZIndex = 20
	ui.curtain.Visible = false
	ui.curtain.Parent = gui

	-- SPLIT FROM ONE LABEL INTO TWO. LuckiestGuy is a heavy display face — it reads
	-- as a punch of a headline and badly as a full sentence, and the drop-items line
	-- is a full sentence. The headline's TEXT never changes (it is always "YOU WENT
	-- DOWN" — only the cause, the body line, and both labels' colour/fade vary per
	-- call), so it is set once here and playBlackout() never touches its Text again.
	ui.curtainHeadline = UIKit.label(ui.curtain, {
		name = "Headline",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, -50),
		size = UDim2.fromOffset(900, 70),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.hero,
		color = GREEN,
		xAlign = Enum.TextXAlignment.Center,
		text = "YOU WENT DOWN",
		zIndex = 21,
	})

	ui.curtainBody = UIKit.label(ui.curtain, {
		name = "Body",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, 45),
		size = UDim2.fromOffset(860, 90),
		font = UIKit.Font.body,
		textSize = 20,
		color = GREEN,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = "",
		zIndex = 21,
	})

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

local function render(dt: number)
	local frac = state.exposureFrac
	local colour = if state.failing then WHITE else GREEN

	-- Nothing at all below the warn threshold. Silence is a UI state.
	local intensity = 0
	if frac >= Tuning.EXPOSURE_WARN then
		intensity = (frac - Tuning.EXPOSURE_WARN) / (1 - Tuning.EXPOSURE_WARN)
	end
	if state.failing then
		intensity = math.max(intensity, 0.65)
	end

	local healthFrac = state.health / math.max(state.maxHealth, 1)
	RadFx.update(dt, intensity, state.failing, healthFrac, overTier())

	ui.fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	ui.fill.BackgroundColor3 = colour
	ui.meterStroke.Color = colour

	local label = if state.inShower then "RADS  \u{2014}  FLUSHING" else "RADS"
	ui.caption.Text = label
	ui.caption.TextColor3 = if frac >= Tuning.EXPOSURE_DANGER then colour else DIM
	ui.percentValue.Text = string.format("%d%%", math.floor(frac * 100 + 0.5))
	ui.percentValue.TextColor3 = if frac >= Tuning.EXPOSURE_DANGER then colour else DIM
	ui.readout.Text = string.format("%+.2f r/s", state.net)
	ui.stageLabel.Text = state.stageName

	-- HEALTH. Green is exposure's colour and exposure's alone (PLAN §14's one-colour
	-- rule), so a hurting suit reads amber -> red the same way any other game's HP bar
	-- would, and only turns white — the ONE white in the game — once failing is real.
	local healthColour = if state.failing then WHITE elseif healthFrac < 0.3 then UIKit.C.red else UIKit.C.amber
	ui.healthFill.Size = UDim2.fromScale(math.clamp(healthFrac, 0, 1), 1)
	ui.healthFill.BackgroundColor3 = healthColour
	ui.healthValue.Text = string.format("%d/%d", math.floor(state.health + 0.5), state.maxHealth)
	ui.healthValue.TextColor3 = healthColour
	ui.healthCaption.TextColor3 = if state.failing then healthColour else DIM

	-- The countdown PLAN §3.5 calls "the single most important UI element" for suit
	-- failure — but only while it means something. Downed and showering both already
	-- have their own loud signals (the curtain, "FLUSHING"), so this stays hidden
	-- there too rather than repeating the news.
	local showCountdown = not state.downed and not state.inShower and state.survivable >= 0
	ui.countdown.Visible = showCountdown
	if showCountdown then
		local burning = state.threat == "burn"
		ui.countdown.Text = string.format("%s  %s", if burning then "SUIT FAILING \u{2014}" else "SURVIVABLE \u{2014}", clock(state.survivable))
		ui.countdown.TextColor3 = if burning then WHITE else GREEN
	end

	-- Above the danger threshold the world starts moving. PLAN §3.1 wants vision
	-- distorted here, not merely tinted — the player should be uncomfortable.
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Over-tier always sets `failing` (Radiation.resolve: failing = excess > 0), so
		-- the blind state is never waiting on the rad meter to catch up to it.
		if frac >= Tuning.EXPOSURE_DANGER or state.failing then
			shakeSeed += dt * 22
			local amount = lerp(0, 0.55, math.clamp((frac - Tuning.EXPOSURE_DANGER) / (1 - Tuning.EXPOSURE_DANGER), 0, 1))
			if state.failing then
				amount = math.max(amount, 0.3)
			end
			-- Out of your depth the camera stops being nudged and starts being shoved.
			amount = math.max(amount, overTier() * 1.1)
			humanoid.CameraOffset = Vector3.new(
				math.sin(shakeSeed * 1.7) * amount,
				math.sin(shakeSeed * 2.3) * amount * 0.6,
				0
			)
		elseif humanoid.CameraOffset.Magnitude > 0.01 then
			humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.zero, math.min(1, dt * 8))
		end
	end
end

-- ── Blackout ─────────────────────────────────────────────────────────

local function playBlackout(info)
	local burn = info.cause == "burn"
	local dropped = info.itemsDropped or 0

	local textColor = if burn then Color3.new(0.1, 0.1, 0.1) else GREEN

	ui.curtain.BackgroundColor3 = if burn then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
	ui.curtainHeadline.TextColor3 = textColor
	ui.curtainBody.TextColor3 = textColor
	ui.curtainBody.Text = if dropped > 0
		then `dropped {dropped} item(s) where you fell \u{2014} 90 seconds to get back`
		else "nothing to lose \u{2014} your bag was empty"
	ui.curtain.Visible = true
	ui.curtain.BackgroundTransparency = 0

	task.spawn(function()
		task.wait(1.6)
		for i = 1, 30 do
			ui.curtain.BackgroundTransparency = i / 30
			ui.curtainHeadline.TextTransparency = i / 30
			ui.curtainBody.TextTransparency = i / 30
			task.wait(0.03)
		end
		ui.curtain.Visible = false
		ui.curtainHeadline.TextTransparency = 0
		ui.curtainBody.TextTransparency = 0
	end)
end

-- ── Lifecycle ────────────────────────────────────────────────────────

--- Read by GeigerController so the audio bed and the picture cannot disagree.
function Hud.exposureFraction(): number
	return state.exposureFrac
end

function Hud.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("ExposureState").OnClientEvent:Connect(function(payload)
		state.exposureFrac = payload.exposureFrac or 0
		state.net = payload.net or 0
		state.failing = payload.failing == true
		state.inShower = payload.inShower == true
		state.stageName = payload.stageName or ""
		state.downed = payload.downed == true

		-- maxHealth before health: health / maxHealth is divided every render frame,
		-- so a stale maxHealth from an old payload must never outlive its own health.
		state.maxHealth = payload.maxHealth or state.maxHealth
		state.health = payload.health or state.health
		state.healthBurn = payload.healthBurn or 0
		state.ambient = payload.ambient or 0
		state.excess = payload.excess or 0
		state.survivable = if payload.survivable ~= nil then payload.survivable else -1
		state.threat = payload.threat or ""
	end)

	Net.get("Blackout").OnClientEvent:Connect(function(info)
		local ok, err = pcall(playBlackout, info)
		if not ok then
			warn(`[hud] blackout render failed: {err}`)
		end
	end)

	-- Heartbeat, not RenderStepped: this drives audio-adjacent feedback and must not
	-- stop because the viewport is not being drawn.
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(render, dt)
		if not ok then
			warn(`[hud] render failed: {err}`)
		end
	end)
end

return Hud
