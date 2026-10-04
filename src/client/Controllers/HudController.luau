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

	ONE COLOUR RULE (PLAN §14): exposure is GREEN, aura failure is WHITE, and they never
	share a shade. Green means "the meter is filling". White means "your aura is coming
	apart" — a different category of dying, not a worse degree of the same one. White is
	used exactly once in this entire game, which is why it will read instantly forever.

	THE VITALS BARS (option 2 "Cartoon" of a mockup round) replaced the cream card that
	used to sit under the cash badge. Two slim ink-outlined bars centred over the hotbar
	(Dock.VITALS_*), rads on top and health under it, 1px apart, with a label row above:
	  - top left, the COUNTDOWN, only while it means something: SURVIVABLE (green),
	    RAD SICKNESS (red), AURA FAILING (white), CRATER BURN (crater yellow-green);
	  - top right, where you are and how deep ("BASE CAMP · 0 m" in camp: camp shows
	    the full readout rather than collapsing, asked for explicitly);
	  - top centre, "Clean at base" while the thing in your hands still has crust on it
	    (ToolService's `Crust` attribute on the held model), the nudge back to the wash;
	  - RADS: a radiation badge (hover or tap it: what 50/80/100% do) and a green bar with notches at EXPOSURE_WARN (black) and
	    EXPOSURE_DANGER (red), the two lines the escalation above actually happens at,
	    and the % inside it with arrows instead of "+0.00 r/s": green ▲ filling, blue ▼
	    draining in a decon shower, one to three of them for how fast;
	  - HEALTH: a heart and a red bar, red at every level, "74 / 100" inside it. Low
	    health (under LOW_HEALTH) pulses the heart instead of recolouring the bar.

	FIXED HEIGHT: nothing grows or shrinks; an empty countdown is just a hidden label.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local RadFx = require(script.Parent.Parent.RadFx)
local DeathScreen = require(script.Parent.Parent.DeathScreen)
local Prefs = require(script.Parent.Parent.Prefs)
local Dock = UIKit.Dock

local Hud = {}

-- The aura-failing countdown strip's white (the colour rule above).
local WHITE = UIKit.C.burn

-- The same cartoon black every sign and outline in the game uses (Kit.C.hazardBlack).
local INK = Color3.fromHex("1A1A1A")

-- Rads stay green and the countdown's failing state stays white (the colour rule above);
-- health is red, which neither of those rules owns.
local STYLE = {
	panel = Color3.fromHex("FFF3D6"),
	header = Color3.fromHex("FFD34D"),
	track = Color3.fromHex("3B3340"),
	health = Color3.fromHex("FF4D5E"),
	healthShine = Color3.fromHex("FF8C97"),
	rads = Color3.fromHex("3FD35A"),
	radsShine = Color3.fromHex("9BF29A"),
	warnMark = INK,
	dangerMark = Color3.fromHex("E23B4A"),
	drain = Color3.fromHex("4FC3F7"),
	-- Standing in a detonated nuke's crater: its own acid yellow-green (the orb's glow,
	-- DetonationController), because white belongs to aura failure alone.
	crater = Color3.fromHex("A6FF3E"),
	text = Color3.new(1, 1, 1),
	font = UIKit.House.font,
}

-- Vitals-local design px. The frame is Dock.VITALS_WIDTH wide (less on a narrow
-- screen) and Dock.VITALS_HEIGHT tall; every x below is from its left edge.
local VITALS = {
	labelHeight = 18,
	labelTextSize = 15,
	icon = 26, -- badge diameter
	barX = 32, -- icon + 6
	barHeight = 17,
	barStroke = 2,
	barTextSize = 13,
	valuePad = 6,
	shadowDrop = 2,
	radsY = 21, -- row tops; each row is `icon` tall with the bar centred in it
	healthY = 48,
}

-- Under this fraction of max health the heart starts to pulse, faster as it drops.
local LOW_HEALTH = 0.3

-- Rads per second below which the rads meter counts as still: no arrows at all.
local STILL_RATE = 0.01
-- Arrow count by how fast the meter moves, as a fraction of the whole meter per
-- second: one arrow for any movement, two once it would fill (or empty) in about a
-- minute, three in about fifteen seconds.
local ARROW_TWO = 1 / 60
local ARROW_THREE = 1 / 15

local ROUND = UDim.new(0.5, 0)

local HELD_ITEM_NAME = "HeldItem" -- ToolService's name for whatever is in your hands

local state = {
	exposureFrac = 0,
	net = 0,
	failing = false,
	inShower = false,
	inCrater = false,
	stageName = "Base Camp",
	downed = false,

	health = 100,
	maxHealth = 100,
	healthBurn = 0,
	ambient = 0,
	depth = 0, -- metres below base camp's edge; 0 in camp
	over = 0, -- 0..1, how far out of its depth the aura is (Radiation.resolve)
	survivable = -1, -- -1 mirrors DebugService's "never" convention
	sickness = 0, -- HP/sec of radiation sickness (meter 80%+, out in a stage)
	threat = "",
}

local ui = {}
local shakeSeed = 0
local heartClock = 0
local radsClock = 0
-- The bars' live track width in design px (the vitals frame minus the icon column).
local barWidth = Dock.VITALS_WIDTH - VITALS.barX

--- HOW FAR PAST YOUR AURA'S RATING THIS AIR IS, 0..1. `failing` only ever answers
--- yes or no, and yes covers both "a stride over the line" and "this stage would
--- have killed three of you already" — one flag cannot tell a player which of those
--- they walked into.
---
--- ExposureState carries it as `over`, graded off the zone survival curve
--- (Radiation.resolve): 0 at a one-tier-under entrance, 1 at a one-second death.
local function overTier(): number
	return math.clamp(state.over, 0, 1)
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

--- One flat, outlined cartoon shape. `stroke` 0 (the default) is no outline.
local function blob(
	parent: Instance,
	name: string,
	rect: { number },
	color: Color3,
	zIndex: number,
	radius: UDim,
	stroke: number?
): Frame
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

--- A vitals icon: a full-colour picture (Artwork.IMAGE, drawn with its own ink
--- outline) centred on (x, y). Pictures, not primitives: the heart and trefoil used to
--- be rotated Frames, and at ~20 screen px the rotated pieces snapped to different
--- pixels, which stepped the heart's outline and turned the trefoil's blades ragged.
--- Returns the UIScale the render loop pulses.
local function buildIcon(parent: Instance, name: string, image: string, x: number, y: number): UIScale
	local icon = Artwork.picture(parent, name, image, VITALS.icon, Color3.new(1, 1, 1))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromOffset(x, y)
	icon.ZIndex = 5

	local scale = Instance.new("UIScale")
	scale.Parent = icon
	return scale
end

--- What each notch on the rads bar does, one row per threshold. Read straight off
--- Tuning so the tooltip can never disagree with ExposureService.
local function radsTipRows(): { { string } }
	return {
		{ string.format("%d%%", math.round(Tuning.SICKNESS_NO_REGEN * 100)), "Health stops regenerating" },
		{ string.format("%d%%", math.round(Tuning.SICKNESS_DRAIN_AT * 100)), "You start taking damage" },
		{ "100%", "Heavy damage" },
	}
end

--- Hovering the rads badge (or tapping it on a phone) shows what the meter's
--- thresholds do: a small ink card above the icon, hidden otherwise.
local function buildRadsTip(parent: Instance, badge: GuiObject)
	local V = VITALS
	local rowHeight, width = 18, 236
	local rows = radsTipRows()
	local tip = UIKit.panel(parent, {
		name = "RadsTip",
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.fromOffset(0, V.radsY - 6),
		size = UDim2.fromOffset(width, 34 + #rows * rowHeight),
		color = INK,
		transparency = 0.08,
		cornerRadius = UDim.new(0, 8),
		strokeColor = STYLE.rads,
		strokeThickness = 2,
		zIndex = 20,
		visible = false,
	})
	UIKit.label(tip, {
		name = "Title",
		position = UDim2.fromOffset(10, 6),
		size = UDim2.new(1, -20, 0, 20),
		font = STYLE.font,
		textSize = 15,
		color = STYLE.rads,
		text = "RADIATION",
		shadow = false,
		zIndex = 21,
	})
	local tint = { STYLE.radsShine, STYLE.healthShine, STYLE.dangerMark }
	for i, row in rows do
		local y = 28 + (i - 1) * rowHeight
		UIKit.label(tip, {
			name = "Mark" .. i,
			position = UDim2.fromOffset(10, y),
			size = UDim2.fromOffset(44, rowHeight),
			font = STYLE.font,
			textSize = 14,
			color = tint[i],
			text = row[1],
			shadow = false,
			zIndex = 21,
		})
		UIKit.label(tip, {
			name = "Effect" .. i,
			position = UDim2.fromOffset(54, y),
			size = UDim2.new(1, -64, 0, rowHeight),
			font = STYLE.font,
			textSize = 14,
			color = STYLE.text,
			text = row[2],
			shadow = false,
			zIndex = 21,
		})
	end

	badge.MouseEnter:Connect(function()
		tip.Visible = true
	end)
	badge.MouseLeave:Connect(function()
		tip.Visible = false
	end)
	badge.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			tip.Visible = not tip.Visible
		end
	end)
end

--- One dark track with a coloured fill (and a flat lighter shine along its top), a hard
--- ink drop-shadow, and a right-aligned value label. The track is as wide as the vitals
--- frame minus the icon column (Scale), so a narrow screen just shortens it; setBar
--- sizes the fill.
local function buildBar(parent: Instance, name: string, rowY: number, fillColor: Color3, shineColor: Color3)
	local V = VITALS
	local y = rowY + (V.icon - V.barHeight) / 2
	local shadow = blob(parent, name .. "Shadow", { V.barX, y + V.shadowDrop, 0, V.barHeight }, INK, 4, ROUND, V.barStroke)
	shadow.Size = UDim2.new(1, -V.barX, 0, V.barHeight)
	local track = blob(parent, name .. "Track", { V.barX, y, 0, V.barHeight }, STYLE.track, 5, ROUND, V.barStroke)
	track.Size = UDim2.new(1, -V.barX, 0, V.barHeight)
	local fill = blob(track, "Fill", { 0, 0, 0, V.barHeight }, fillColor, 6, ROUND)
	local shine = blob(fill, "Shine", { 4, 2, 0, 3 }, shineColor, 7, ROUND)
	shine.Size = UDim2.new(1, -8, 0, 3)
	local value = UIKit.label(track, {
		name = "Value",
		size = UDim2.new(1, -V.valuePad, 1, 0),
		font = STYLE.font,
		textSize = V.barTextSize,
		color = STYLE.text,
		xAlign = Enum.TextXAlignment.Right,
		shadow = false,
		zIndex = 9,
	})
	value.RichText = true
	return { track = track, fill = fill, shine = shine, value = value }
end

--- A thin line across a bar at `frac` of its length.
local function notch(bar: any, frac: number, color: Color3)
	local mark = blob(bar.track, "Notch", { 0, 0, 2, VITALS.barHeight }, color, 8, UDim.new(0, 1))
	mark.Position = UDim2.new(frac, -1, 0, 0)
end

local function setBar(bar: any, frac: number, text: string)
	local h = VITALS.barHeight
	local width = barWidth * math.clamp(frac, 0, 1)
	-- A pill narrower than it is tall stops reading as a fill, so anything above zero
	-- shows at least a full round end, and zero shows nothing.
	bar.fill.Visible = width > 0.5
	width = math.max(width, h)
	bar.fill.Size = UDim2.fromOffset(width, h)
	bar.shine.Visible = width - 8 >= 4
	bar.value.Text = text
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RadHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Edge to edge, notch and all (UIKit's "The notch"): the damage overlay is the
	-- whole screen, and an overlay that stops at the safe area leaves a strip of the
	-- world showing down one side. The meter, the one thing here that hugs an edge,
	-- adds the inset back itself.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- The damage overlay. Not part of the dock — it is the whole screen, under every
	-- panel (ZIndex 2). The death screen covers it from its own gui (DeathScreen).
	RadFx.build(gui)
	Prefs.observe("radFx", function(level)
		RadFx.setReduced(level == "reduced")
	end)

	-- Everything else goes on the scaled canvas (UIKit.canvas). RadFx stays beside it,
	-- straight on the gui: it already sizes every crack and ring off the camera's own
	-- viewport, and scaling it a second time would push it past the screen edges. ZIndex
	-- 3 so the canvas and the meter on it still draw over the overlay's 2.
	local canvas = UIKit.canvas(gui, 3)

	local V = VITALS

	-- The vitals frame: invisible, bottom-centred over the hotbar (Dock.VITALS_BOTTOM).
	local vitals = Instance.new("Frame")
	vitals.Name = "Vitals"
	vitals.AnchorPoint = Vector2.new(0.5, 1)
	vitals.BackgroundTransparency = 1
	vitals.ZIndex = 4
	vitals.Parent = canvas
	-- Placed in the safe area's frame, not the screen's, to stay on the hotbar, whose gui
	-- IS inset. Narrower than VITALS_WIDTH only when the screen cannot fit it inside the
	-- same side margins the hotbar keeps (clear of the touch controls on a phone).
	local function place()
		local inset = UIKit.safeInsets()
		local screenWidth = canvas.AbsoluteSize.X / UIKit.canvasScale(canvas)
		local margin = math.max(Dock.ROW_SIDE_MARGIN, UIKit.touchCorner().X + Dock.GAP)
		local width = Dock.VITALS_WIDTH
		if screenWidth > 0 then
			width = math.clamp(screenWidth - inset.left - inset.right - 2 * margin, 240, Dock.VITALS_WIDTH)
		end
		barWidth = width - V.barX
		vitals.Size = UDim2.fromOffset(width, Dock.VITALS_HEIGHT)
		vitals.Position = UDim2.new(0.5, (inset.left - inset.right) / 2, 1, -(Dock.VITALS_BOTTOM + inset.bottom))
	end
	UIKit.onScaleChanged(place)
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()

	-- Label row: the countdown on the left (over the bars, past the icons), where you are
	-- and how deep on the right.
	local function rowLabel(name: string, align: Enum.TextXAlignment): TextLabel
		local label = UIKit.label(vitals, {
			name = name,
			position = UDim2.fromOffset(V.barX, 0),
			size = UDim2.new(1, -V.barX, 0, V.labelHeight),
			font = STYLE.font,
			textSize = V.labelTextSize,
			color = STYLE.text,
			xAlign = align,
			yAlign = Enum.TextYAlignment.Bottom,
			shadow = false,
			zIndex = 5,
		})
		label.RichText = true
		return label
	end
	ui.countdownText = rowLabel("Countdown", Enum.TextXAlignment.Left)
	ui.place = rowLabel("Place", Enum.TextXAlignment.Right)
	ui.cleanHint = rowLabel("CleanHint", Enum.TextXAlignment.Center)
	ui.cleanHint.Text = "Clean at base"
	ui.cleanHint.TextColor3 = STYLE.header
	ui.cleanHint.Visible = false

	-- RADS
	ui.radsScale = buildIcon(vitals, "RadsBadge", Artwork.IMAGE.radsTrefoil, V.icon / 2, V.radsY + V.icon / 2)
	buildRadsTip(vitals, ui.radsScale.Parent :: GuiObject)
	ui.rads = buildBar(vitals, "Rads", V.radsY, STYLE.rads, STYLE.radsShine)
	notch(ui.rads, Tuning.EXPOSURE_WARN, STYLE.warnMark)
	notch(ui.rads, Tuning.EXPOSURE_DANGER, STYLE.dangerMark)

	-- HEALTH
	ui.heartScale = buildIcon(vitals, "Heart", Artwork.IMAGE.healthHeart, V.icon / 2, V.healthY + V.icon / 2)
	ui.health = buildBar(vitals, "Health", V.healthY, STYLE.health, STYLE.healthShine)

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

--- ▲ filling, ▼ draining, nothing when still; one to three by speed.
---
--- DRAINING IS THE SHOWER, NOT A NEGATIVE `net`. `net` is what the air and your bag
--- ADD (Radiation.resolve: stage + bag, never below zero), and a decon shower flushes
--- on top of that at SHOWER_FLUSH_RATE without touching it — so a player standing
--- in the shower with a half-full meter reads `net == 0`. This takes the flush rate
--- whenever there is something left to flush, which is what the old "RADS — FLUSHING"
--- caption was keyed to.
local function arrows(): string
	local draining = state.inShower and state.exposureFrac > 0
	local rate = if draining then Tuning.SHOWER_FLUSH_RATE else state.net
	if rate < STILL_RATE then
		return ""
	end
	local perSecond = rate / Tuning.EXPOSURE_CAP
	local count = if perSecond >= ARROW_THREE then 3 elseif perSecond >= ARROW_TWO then 2 else 1
	local glyphs = string.rep(if draining then "\u{25BC}" else "\u{25B2}", count)
	return string.format(' <font color="#%s">%s</font>', (if draining then STYLE.drain else STYLE.radsShine):ToHex(), glyphs)
end

--- A heartbeat-style bump for a UIScale: 1 at rest, 1 + `amount` at the top of each
--- beat. The caller advances `phase`, which is where the speed comes from.
local function pulse(phase: number, amount: number): number
	return 1 + amount * math.abs(math.sin(phase))
end

local function render(dt: number)
	local frac = state.exposureFrac

	-- Nothing at all below the warn threshold. Silence is a UI state.
	local over = overTier()
	local intensity = 0
	if frac >= Tuning.EXPOSURE_WARN then
		intensity = (frac - Tuning.EXPOSURE_WARN) / (1 - Tuning.EXPOSURE_WARN)
	end
	-- A failing aura always shows something, but HOW MUCH is graded by how far past
	-- your rating you are — a flat 0.65 floor here meant one step over the line lit
	-- the overlay as hard as a nearly-full meter. Lands back on exactly 0.65 at a
	-- one-second death (Radiation.resolve's `over`). Same reasoning as RadFx's `failTarget`; the two have to
	-- agree or the grade reappears through this floor.
	if state.failing then
		intensity = math.max(intensity, 0.2 + 0.45 * over)
	end

	local healthFrac = state.health / math.max(state.maxHealth, 1)
	RadFx.update(dt, intensity, state.failing, healthFrac, over)

	-- Where you are. The payload already names base camp "Base Camp", and camp's depth is 0.
	ui.place.Text = string.format(
		'%s <font color="#%s">\u{00B7} %d m</font>',
		state.stageName,
		STYLE.header:ToHex(),
		math.floor(state.depth + 0.5)
	)

	-- HEALTH: red at every level; low health pulses the heart, faster as it drops.
	setBar(ui.health, healthFrac, string.format("%d / %d", math.floor(state.health + 0.5), state.maxHealth))
	if healthFrac < LOW_HEALTH and not state.downed then
		local urgency = 1 - healthFrac / LOW_HEALTH
		heartClock += dt * lerp(5, 11, urgency)
		ui.heartScale.Scale = pulse(heartClock, lerp(0.14, 0.26, urgency))
	else
		heartClock = 0
		ui.heartScale.Scale = lerp(ui.heartScale.Scale, 1, math.min(1, dt * 10))
	end

	-- RADS: the badge pulses once the meter is past the danger notch or the aura fails.
	setBar(ui.rads, frac, string.format("%d%%", math.floor(frac * 100 + 0.5)) .. arrows())
	if frac >= Tuning.EXPOSURE_DANGER or state.failing then
		radsClock += dt * 8
		ui.radsScale.Scale = pulse(radsClock, 0.18)
	else
		radsClock = 0
		ui.radsScale.Scale = lerp(ui.radsScale.Scale, 1, math.min(1, dt * 10))
	end

	-- The countdown, only while it means something. Downed and showering both already
	-- have their own loud signals (the death screen, the draining arrows), so it stays
	-- hidden there too rather than repeating the news.
	local showCountdown = not state.downed and not state.inShower and state.survivable >= 0
	ui.countdownText.Visible = showCountdown
	if showCountdown then
		local burning = state.threat == "burn"
		-- Burn with the aura holding means the burn is the crater's, not the aura's.
		local crater = burning and state.inCrater and not state.failing
		local label = if crater then "Crater Burn" elseif burning then "Aura Failing" elseif state.sickness > 0 then "Rad Sickness" else "Survivable"
		ui.countdownText.Text = string.format("%s  %s", label, clock(state.survivable))
		ui.countdownText.TextColor3 = if crater
			then STYLE.crater
			elseif burning then WHITE
			elseif state.sickness > 0 then STYLE.dangerMark
			else STYLE.rads
	end

	-- Holding a find that still has crust on it: point the player home to the wash.
	local character = Players.LocalPlayer.Character
	local held = character and character:FindFirstChild(HELD_ITEM_NAME)
	local crust = held and held:GetAttribute("Crust")
	ui.cleanHint.Visible = not state.downed and type(crust) == "number" and crust > 0

	-- Above the danger threshold the world starts moving. PLAN §3.1 wants vision
	-- distorted here, not merely tinted — the player should be uncomfortable.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Over-tier always sets `failing` (Radiation.resolve: failing = excess > 0), so
		-- the blind state is never waiting on the rad meter to catch up to it.
		-- Settings' SCREEN SHAKE off skips the wobble; the overlay still says it all.
		if (frac >= Tuning.EXPOSURE_DANGER or state.failing) and Prefs.get("shake") then
			shakeSeed += dt * 22
			local amount = lerp(0, 0.55, math.clamp((frac - Tuning.EXPOSURE_DANGER) / (1 - Tuning.EXPOSURE_DANGER), 0, 1))
			-- Graded for the same reason as the intensity floor above: a flat 0.3 shove
			-- the instant the flag flipped was a large part of what made crossing a
			-- stage line feel like an explosion. Still 0.3 at three times your rating.
			if state.failing then
				amount = math.max(amount, 0.1 + 0.2 * over)
			end
			-- Out of your depth the camera stops being nudged and starts being shoved.
			amount = math.max(amount, over * 1.1)
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

-- ── Lifecycle ────────────────────────────────────────────────────────

--- Read by GeigerController so the audio bed and the picture cannot disagree.
function Hud.exposureFraction(): number
	return state.exposureFrac
end

--- Read by SfxController for the heartbeat, the sickness stings and the hurt thud,
--- off the same ExposureState copy the bars draw.
function Hud.vitals(): { exposureFrac: number, health: number, maxHealth: number, sickness: number, downed: boolean }
	return {
		exposureFrac = state.exposureFrac,
		health = state.health,
		maxHealth = state.maxHealth,
		sickness = state.sickness,
		downed = state.downed == true,
	}
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
		state.depth = payload.depth or 0
		state.over = payload.over or 0
		state.survivable = if payload.survivable ~= nil then payload.survivable else -1
		state.threat = payload.threat or ""
		state.inCrater = payload.inCrater == true
		state.sickness = payload.sickness or 0
	end)

	-- Going down is DeathScreen's ("Flatline"), on its own gui over every panel.
	DeathScreen.start()
	Net.get("Blackout").OnClientEvent:Connect(function(info)
		local ok, err = pcall(DeathScreen.play, info)
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
