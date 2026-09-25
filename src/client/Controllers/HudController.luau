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

	THE PANEL IS THE CARTOON ONE (layout 2 of a mockup round), matching the gold-coin
	cash badge above it: one cream card with a thick INK outline and a hard offset
	shadow, holding
	  - a yellow header strip: where you are (Stages' name, "Base Camp" in camp) and how
	    deep ("0 m" in camp — asked for explicitly, so camp shows the same full panel as a
	    stage rather than collapsing);
	  - HEALTH: a heart and a red bar, red at every level. Low health (under
	    LOW_HEALTH) pulses the heart instead of recolouring the bar;
	  - RADS: a radiation badge and a green bar with notches at EXPOSURE_WARN (black) and
	    EXPOSURE_DANGER (red) — the two lines the escalation above actually happens at —
	    plus arrows instead of the old "+0.00 r/s": green ▲ filling, blue ▼ draining in
	    a decon shower, one to three of them for how fast;
	  - the COUNTDOWN strip, only while it means something, which is the one thing that
	    changes the panel's height. White with ink text when the aura is failing, ink with
	    green text for a plain "survivable" clock.

	THE PANEL HANGS FROM ITS TOP EDGE (Dock.METER_TOP_Y), one GAP under the cash badge, so
	the countdown strip grows it downward and never into the badge. Dock.METER_SIZE is its
	tallest shape.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local RadFx = require(script.Parent.Parent.RadFx)
local Dock = UIKit.Dock

local Hud = {}

-- The blackout curtain's palette, unchanged.
local GREEN = UIKit.C.green
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
	font = Enum.Font.FredokaOne,
}

-- Panel-local design px. The card is Dock.METER_SIZE wide; `height` is its resting
-- height and Dock.METER_SIZE.Y its height with the countdown strip showing.
local PANEL = {
	width = Dock.METER_SIZE.X.Offset,
	height = 104,
	radius = 18,
	outline = 4,
	shadowDrop = 5,
	header = { x = 4, y = 4, height = 26, pad = 12, textSize = 14 },
	iconX = 21, -- icon centre
	barX = 42,
	barHeight = 22,
	barStroke = 3,
	barTextSize = 13,
	healthY = 38,
	healthWidth = 226,
	radsY = 70,
	radsWidth = 196, -- shorter than health: the arrows sit at its right end
	arrowX = 255,
	arrowTextSize = { 17, 13, 11 }, -- one, two, three arrows
	countdown = { x = 8, y = 102, height = 28, textSize = 14 },
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

local RESIZE_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local ROUND = UDim.new(0.5, 0)

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
	excess = 0,
	survivable = -1, -- -1 mirrors DebugService's "never" convention
	threat = "",
}

local ui = {}
local shakeSeed = 0
local heartClock = 0
local radsClock = 0
local countdownShown = false

--- HOW FAR PAST YOUR AURA'S RATING THIS AIR IS, 0..1. `failing` only ever answers
--- yes or no, and yes covers both "a stride over the line" and "this stage would
--- have killed three of you already" — one flag cannot tell a player which of those
--- they walked into.
---
--- No new field on the wire: ExposureState already carries `ambient` and `excess`,
--- and Radiation.resolve defines excess as ambient minus aura tolerance, so the
--- tolerance is just their difference and the ratio falls out. Divided by three
--- because three times your own tolerance is comfortably past any argument about
--- whether you meant to be here — a Static Veil reaches it in the Exclusion Belt,
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

--- A square frame centred on (x, y), for shapes built around a centre point.
local function centred(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, zIndex: number, radius: UDim?): Frame
	local frame = blob(parent, name, { x, y, w, h }, color, zIndex, radius or UDim.new(0, 0))
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	return frame
end

--- A heart from primitives: a square turned 45 degrees with a circle on each upper
--- edge. The ink outline is the same heart grown by `edge` (square 2*edge wider,
--- circles `edge` wider, same centres) laid underneath, since a UIStroke per piece
--- would draw the seams between them.
local function buildHeart(parent: Instance, x: number, y: number): UIScale
	local box = Instance.new("Frame")
	box.Name = "Heart"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromOffset(x, y)
	box.Size = UDim2.fromOffset(28, 28)
	box.BackgroundTransparency = 1
	box.ZIndex = 5
	box.Parent = parent

	local side, edge = 14, 2.5
	local lobe = side / math.sqrt(2) / 2 -- centre of each upper edge, from the square's centre
	local cx, cy = 14, 15 -- one px low: the lobes make the shape top-heavy
	for layer, color in { INK, STYLE.health } do
		local grow = if layer == 1 then edge else 0
		local z = 5 + layer
		local square = centred(box, "Square", cx, cy, side + grow * 2, side + grow * 2, color, z)
		square.Rotation = 45
		centred(box, "LobeLeft", cx - lobe, cy - lobe, side + grow * 2, side + grow * 2, color, z, ROUND)
		centred(box, "LobeRight", cx + lobe, cy - lobe, side + grow * 2, side + grow * 2, color, z, ROUND)
	end

	local scale = Instance.new("UIScale")
	scale.Parent = box
	return scale
end

--- The radiation trefoil from primitives, on a green badge. Each 60-degree blade is a
--- fan of thin rotated bars from the inner to the outer radius, close enough together
--- to read as a solid wedge at icon size. No picture needed: the Unicode trefoil renders
--- as a colour emoji in Roblox and ignores TextColor3.
local function buildRadsBadge(parent: Instance, x: number, y: number): UIScale
	local size = 24
	local badge = centred(parent, "RadsBadge", x, y, size, size, STYLE.rads, 5, ROUND)
	local stroke = badge:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 3
	end

	local centre = size / 2
	local inner, outer = 2.6, 9.4
	local mid, length = (inner + outer) / 2, outer - inner
	for _, blade in { 90, 210, 330 } do -- one blade pointing down, like the sign
		for spread = -24, 24, 8 do
			local angle = blade + spread
			local rad = math.rad(angle)
			local ray = centred(badge, "Blade", centre + mid * math.cos(rad), centre + mid * math.sin(rad), length, 2.2, INK, 6)
			ray.Rotation = angle
		end
	end
	centred(badge, "Hub", centre, centre, 3.4, 3.4, INK, 6, ROUND)

	local scale = Instance.new("UIScale")
	scale.Parent = badge
	return scale
end

--- One dark track with a coloured fill (and a flat lighter shine along its top) and a
--- centred value label. setBar drives it.
local function buildBar(parent: Instance, name: string, y: number, width: number, fillColor: Color3, shineColor: Color3)
	local P = PANEL
	local track = blob(parent, name .. "Track", { P.barX, y, width, P.barHeight }, STYLE.track, 5, ROUND, P.barStroke)
	local fill = blob(track, "Fill", { 0, 0, width, P.barHeight }, fillColor, 6, ROUND, P.barStroke)
	local shine = blob(fill, "Shine", { 6, 3, width - 12, 6 }, shineColor, 7, ROUND)
	local value = UIKit.label(track, {
		name = "Value",
		size = UDim2.fromScale(1, 1),
		font = STYLE.font,
		textSize = P.barTextSize,
		color = STYLE.text,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
		zIndex = 9,
	})
	return { track = track, fill = fill, shine = shine, value = value, width = width }
end

--- A notch that pokes out of both edges of a bar at `frac` of its length.
local function notch(bar: any, frac: number, color: Color3)
	local x = bar.width * frac
	for _, y in { -4, PANEL.barHeight - 3 } do
		blob(bar.track, "Notch", { x - 1.5, y, 3, 7 }, color, 8, UDim.new(0, 1.5))
	end
end

local function setBar(bar: any, frac: number, text: string)
	local P = PANEL
	local width = bar.width * math.clamp(frac, 0, 1)
	-- A pill narrower than it is tall stops reading as a fill, so anything above zero
	-- shows at least a full round end, and zero shows nothing.
	bar.fill.Visible = width > 0.5
	width = math.max(width, P.barHeight)
	bar.fill.Size = UDim2.fromOffset(width, P.barHeight)
	bar.shine.Visible = width - 12 >= 4
	bar.shine.Size = UDim2.fromOffset(math.max(width - 12, 0), 6)
	bar.value.Text = text
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RadHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Edge to edge, notch and all (UIKit's "The notch"): the damage overlay and the
	-- blackout curtain are both the whole screen, and a curtain that stops at the safe
	-- area leaves a strip of the world showing down one side. The meter, the one thing
	-- here that hugs an edge, adds the inset back itself.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- The damage overlay. Not part of the dock — it is the whole screen, under every
	-- panel (ZIndex 2) and under the blackout curtain, which has to cover it.
	RadFx.build(gui)

	-- Everything else goes on the scaled canvas (UIKit.canvas). RadFx stays beside it,
	-- straight on the gui: it already sizes every crack and ring off the camera's own
	-- viewport, and scaling it a second time would push it past the screen edges. ZIndex
	-- 3 so the canvas — meter and curtain alike — still draws over the overlay's 2.
	local canvas = UIKit.canvas(gui, 3)

	local P = PANEL

	-- The panel's footprint: invisible, hung from its top edge (see the header).
	local meter = Instance.new("Frame")
	meter.Name = "Meter"
	meter.Size = Dock.METER_SIZE
	-- Placed in the safe area's frame, not the screen's, to stay stacked under the cash
	-- badge (CashController), whose gui IS inset: its left edge, and its centre line,
	-- which a home bar at the bottom lifts by half the bar.
	UIKit.onScaleChanged(function()
		local inset = UIKit.safeInsets()
		local centreShift = (inset.top - inset.bottom) / 2
		meter.Position = UDim2.new(0, Dock.ROW_SIDE_MARGIN + inset.left, 0.5, Dock.METER_TOP_Y + centreShift)
	end)
	meter.BackgroundTransparency = 1
	meter.ZIndex = 4
	meter.Parent = canvas

	ui.shadow = blob(meter, "Shadow", { 0, P.shadowDrop, P.width, P.height }, INK, 1, UDim.new(0, P.radius))
	ui.card = blob(meter, "Card", { 0, 0, P.width, P.height }, STYLE.panel, 2, UDim.new(0, P.radius), P.outline)
	local card = ui.card

	-- Header strip: where you are, and how deep.
	local H = P.header
	local header = blob(card, "Header", { H.x, H.y, P.width - H.x * 2, H.height }, STYLE.header, 3, ROUND)
	local function headerLabel(name: string, align: Enum.TextXAlignment): TextLabel
		return UIKit.label(header, {
			name = name,
			position = UDim2.fromOffset(H.pad, 0),
			size = UDim2.new(1, -H.pad * 2, 1, 0),
			font = STYLE.font,
			textSize = H.textSize,
			color = INK,
			xAlign = align,
			outline = false,
			strokeTransparency = 1,
			shadow = false,
			zIndex = 4,
		})
	end
	ui.stageName = headerLabel("StageName", Enum.TextXAlignment.Left)
	ui.depth = headerLabel("Depth", Enum.TextXAlignment.Right)

	-- HEALTH
	ui.heartScale = buildHeart(card, P.iconX, P.healthY + P.barHeight / 2)
	ui.health = buildBar(card, "Health", P.healthY, P.healthWidth, STYLE.health, STYLE.healthShine)

	-- RADS
	ui.radsScale = buildRadsBadge(card, P.iconX, P.radsY + P.barHeight / 2)
	ui.rads = buildBar(card, "Rads", P.radsY, P.radsWidth, STYLE.rads, STYLE.radsShine)
	notch(ui.rads, Tuning.EXPOSURE_WARN, STYLE.warnMark)
	notch(ui.rads, Tuning.EXPOSURE_DANGER, STYLE.dangerMark)

	ui.arrows = UIKit.label(card, {
		name = "Arrows",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.fromOffset(P.arrowX, P.radsY + P.barHeight / 2),
		size = UDim2.fromOffset(38, P.barHeight),
		font = STYLE.font,
		textSize = P.arrowTextSize[1],
		color = STYLE.rads,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
		zIndex = 5,
	})

	-- The countdown strip PLAN §3.5 calls "the single most important UI element" for
	-- aura failure. Hidden until render() says it means something.
	local C = P.countdown
	ui.countdown = blob(card, "Countdown", { C.x, C.y, P.width - C.x * 2, C.height }, WHITE, 3, UDim.new(0, 12), 3)
	ui.countdown.Visible = false
	ui.countdownText = UIKit.label(ui.countdown, {
		name = "Text",
		size = UDim2.fromScale(1, 1),
		font = STYLE.font,
		textSize = C.textSize,
		color = INK,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		strokeTransparency = 1,
		shadow = false,
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
	ui.curtain.Parent = canvas

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

--- Show or hide the countdown strip, growing or shrinking the card to fit it. Only
--- called on a change, so the tween is not restarted every frame.
local function setCountdownShown(shown: boolean)
	if shown == countdownShown then
		return
	end
	countdownShown = shown

	local P = PANEL
	local height = if shown then Dock.METER_SIZE.Y.Offset else P.height
	ui.countdown.Visible = shown
	TweenService:Create(ui.card, RESIZE_TWEEN, { Size = UDim2.fromOffset(P.width, height) }):Play()
	TweenService:Create(ui.shadow, RESIZE_TWEEN, { Size = UDim2.fromOffset(P.width, height) }):Play()
end

--- ▲ filling, ▼ draining, nothing when still; one to three by speed.
---
--- DRAINING IS THE SHOWER, NOT A NEGATIVE `net`. `net` is what the air and your bag
--- ADD (Radiation.resolve: stage + bag, never below zero), and a decon shower flushes
--- on top of that at SHOWER_FLUSH_RATE without touching it — so a player standing
--- in the shower with a half-full meter reads `net == 0`. This takes the flush rate
--- whenever there is something left to flush, which is what the old "RADS — FLUSHING"
--- caption was keyed to.
local function renderArrows()
	local draining = state.inShower and state.exposureFrac > 0
	local rate = if draining then Tuning.SHOWER_FLUSH_RATE else state.net
	if rate < STILL_RATE then
		ui.arrows.Text = ""
		return
	end
	local perSecond = rate / Tuning.EXPOSURE_CAP
	local count = if perSecond >= ARROW_THREE then 3 elseif perSecond >= ARROW_TWO then 2 else 1
	ui.arrows.Text = string.rep(if draining then "\u{25BC}" else "\u{25B2}", count)
	ui.arrows.TextColor3 = if draining then STYLE.drain else STYLE.rads
	ui.arrows.TextSize = PANEL.arrowTextSize[count]
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
	-- the overlay as hard as a nearly-full meter. Lands back on exactly 0.65 at three
	-- times your tolerance. Same reasoning as RadFx's `failTarget`; the two have to
	-- agree or the grade reappears through this floor.
	if state.failing then
		intensity = math.max(intensity, 0.2 + 0.45 * over)
	end

	local healthFrac = state.health / math.max(state.maxHealth, 1)
	RadFx.update(dt, intensity, state.failing, healthFrac, over)

	-- Header. The payload already names base camp "Base Camp", and camp's depth is 0.
	ui.stageName.Text = state.stageName
	ui.depth.Text = string.format("%d m", math.floor(state.depth + 0.5))

	-- HEALTH: red at every level; low health pulses the heart, faster as it drops.
	setBar(ui.health, healthFrac, string.format("%d/%d", math.floor(state.health + 0.5), state.maxHealth))
	if healthFrac < LOW_HEALTH and not state.downed then
		local urgency = 1 - healthFrac / LOW_HEALTH
		heartClock += dt * lerp(5, 11, urgency)
		ui.heartScale.Scale = pulse(heartClock, lerp(0.14, 0.26, urgency))
	else
		heartClock = 0
		ui.heartScale.Scale = lerp(ui.heartScale.Scale, 1, math.min(1, dt * 10))
	end

	-- RADS: the badge pulses once the meter is past the danger notch or the aura fails.
	setBar(ui.rads, frac, string.format("%d%%", math.floor(frac * 100 + 0.5)))
	renderArrows()
	if frac >= Tuning.EXPOSURE_DANGER or state.failing then
		radsClock += dt * 8
		ui.radsScale.Scale = pulse(radsClock, 0.18)
	else
		radsClock = 0
		ui.radsScale.Scale = lerp(ui.radsScale.Scale, 1, math.min(1, dt * 10))
	end

	-- The countdown, only while it means something. Downed and showering both already
	-- have their own loud signals (the curtain, the draining arrows), so it stays
	-- hidden there too rather than repeating the news.
	local showCountdown = not state.downed and not state.inShower and state.survivable >= 0
	setCountdownShown(showCountdown)
	if showCountdown then
		local burning = state.threat == "burn"
		-- Burn with the aura holding means the burn is the crater's, not the aura's.
		local crater = burning and state.inCrater and not state.failing
		local label = if crater then "CRATER BURN" elseif burning then "AURA FAILING" else "SURVIVABLE"
		ui.countdownText.Text = string.format("%s  %s", label, clock(state.survivable))
		ui.countdown.BackgroundColor3 = if crater then STYLE.crater elseif burning then WHITE else INK
		ui.countdownText.TextColor3 = if burning then INK else STYLE.rads
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

-- ── Blackout ─────────────────────────────────────────────────────────

local function playBlackout(info)
	-- A blast death ("blast") flashes white like aura burn -- it is heat either way --
	-- but its bag went off with it rather than dropping (ExposureService).
	local burn = info.cause == "burn" or info.cause == "blast"
	local dropped = info.itemsDropped or 0
	local detonated = info.itemsDetonated or 0

	local textColor = if burn then Color3.new(0.1, 0.1, 0.1) else GREEN

	ui.curtain.BackgroundColor3 = if burn then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
	ui.curtainHeadline.TextColor3 = textColor
	ui.curtainBody.TextColor3 = textColor
	ui.curtainBody.Text = if detonated > 0
		then `your bag went off \u{2014} {detonated} nuke(s) blew where you fell`
		elseif dropped > 0 then `dropped {dropped} item(s) where you fell \u{2014} 90 seconds to get back`
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
		state.depth = payload.depth or 0
		state.excess = payload.excess or 0
		state.survivable = if payload.survivable ~= nil then payload.survivable else -1
		state.threat = payload.threat or ""
		state.inCrater = payload.inCrater == true
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
