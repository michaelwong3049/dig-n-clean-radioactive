--[[
	DeathScreen.luau — "Flatline", what you see when you go down (option 1 of a mockup
	round; HudController plays it off Net.Blackout).

	A black monitor screen. A heartbeat trace runs across it, spikes three times and goes
	flat; YOU WENT DOWN flickers on under it; then what put you down and where, what it
	cost you, and a WAKING UP AT CAMP bar that fills while you stand at the respawn
	anchor behind it (the server has already moved you by the time this starts). About
	four seconds, and a click or tap after SKIP_AT jumps straight to the fade.

	ONE COLOUR PER DEATH, the same split the HUD keeps (HudController's header):
	radiation is GREEN, aura burn is WHITE (warm, so the text is not a hole in the
	screen), and a blast is ORANGE. Burn and blast open on a white flash first -- heat,
	either way -- which is what the old white curtain was saying.

	EVERYTHING IS A FUNCTION OF ONE CLOCK. render(t) sets every piece from how long the
	screen has been up, so skipping is just moving the clock to FADE_AT, and a second
	blackout landing mid-play simply restarts it.

	THE TRACE IS BUILT PER PLAY, to the canvas's width at that moment: the beats sit
	round the centre and the flat runs reach both screen edges, however wide the screen.
	Each segment is a rotated Frame placed by its CENTRE (a GuiObject rotates about its
	centre, not its AnchorPoint), grown along its own line as the pen reaches it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UIKit = require(script.Parent.UIKit)

local DeathScreen = {}

-- ── Timeline (seconds since the screen went up) ─────────────────────────────
local FLASH_TIME = 0.3 -- burn/blast only
local TRACE_AT, TRACE_TIME = 0.1, 1.2
local TITLE_AT, TITLE_TIME = 1.1, 0.5
local CAUSE_AT = 1.4
local BAG_AT = 1.6
local LINE_TIME = 0.35 -- the cause and bag lines' fade-and-rise
local WAKE_AT = 1.8
local BAR_AT, BAR_END = 1.9, 3.6
local SKIP_AT = 1.5
local FADE_AT, FADE_TIME = 3.6, 0.6

-- ── Layout (design px, offsets from screen centre) ──────────────────────────
local TRACE_Y = -150 -- the flat line
local TITLE_Y = 10
local CAUSE_Y = 82
local BAG_Y = 122
local WAKE_Y = 200
local BAR_Y = 226
local BAR_W, BAR_H = 440, 10
local RISE = 14 -- the cause and bag lines come up this far as they fade in

-- The heartbeat, relative to the centre of the screen: three beats, each smaller than
-- the last, then flat. The first and last points are replaced by the screen edges.
local BEATS = {
	{ -460, 0 },
	{ -430, -50 },
	{ -408, 60 },
	{ -386, 0 },
	{ -240, 0 },
	{ -210, -80 },
	{ -185, 85 },
	{ -162, 0 },
	{ -40, 0 },
	{ -22, -32 },
	{ -10, 40 },
	{ 2, -14 },
	{ 16, 15 },
	{ 32, 0 },
}
local LINE = 5
local GLOW = 15
local GLOW_TRANSPARENCY = 0.8

local BACKGROUND = Color3.fromHex("050805")
local BODY = Color3.fromHex("D8E4D0")
local DIM = Color3.fromHex("A9B4A4")

local CAUSES = {
	exposure = { accent = Color3.fromHex("8CFF3A"), title = "RADIATION POISONING", flash = false },
	burn = { accent = Color3.fromHex("FFF6D8"), title = "AURA BURNOUT", flash = true },
	blast = { accent = Color3.fromHex("FF9A3C"), title = "CAUGHT IN THE BLAST", flash = true },
}

local ui: any = nil
local playing: any = nil -- { started, cause, conn }

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function ramp(t: number, at: number, length: number): number
	return clamp01((t - at) / length)
end

--- The headline's flicker, 0..1 over TITLE_TIME: on, nearly off, on, half, on.
local FLICKER = { { 0, 0 }, { 0.2, 1 }, { 0.3, 0.2 }, { 0.45, 1 }, { 0.6, 0.5 }, { 1, 1 } }
local function flicker(x: number): number
	for i = 2, #FLICKER do
		local a, b = FLICKER[i - 1], FLICKER[i]
		if x <= b[1] then
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return 1
end

local function plural(n: number, one: string, many: string): string
	return if n == 1 then `{n} {one}` else `{n} {many}`
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function frame(parent: Instance, name: string, color: Color3, zIndex: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = zIndex
	f.Parent = parent
	return f
end

local function text(parent: Instance, name: string, font: Enum.Font, size: number, color: Color3, y: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, y)
	label.Size = UDim2.fromOffset(1200, height)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = 5
	label.Parent = parent
	return label
end

--- An edge of the vignette: black at the screen edge fading to nothing inward.
local function vignetteEdge(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2, rotation: number)
	local edge = frame(parent, name, Color3.new(0, 0, 0), 8)
	edge.Size = size
	edge.Position = position
	edge.AnchorPoint = anchor
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- The whole screen, notch and all (UIKit's "The notch"): a curtain that stops at the
	-- safe area leaves a strip of the world showing down one side.
	gui.ScreenInsets = Enum.ScreenInsets.None
	-- Over every HUD and panel (the Index/Shop panels are 110, the locker tutorial 115),
	-- under the wash bay's transition (200).
	gui.DisplayOrder = 120
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local canvas = UIKit.canvas(gui)

	local background = frame(canvas, "Background", BACKGROUND, 1)
	background.Size = UDim2.fromScale(1, 1)
	-- Swallows clicks meant for the world or the HUD under it while you are down.
	background.Active = true

	local trace = frame(canvas, "Trace", BACKGROUND, 3)
	trace.BackgroundTransparency = 1
	trace.Position = UDim2.new(0.5, 0, 0.5, TRACE_Y)
	trace.Size = UDim2.fromOffset(0, 0)

	local title = text(canvas, "Title", Enum.Font.LuckiestGuy, 100, Color3.new(1, 1, 1), TITLE_Y, 110)
	-- A wide, faint stroke in the accent reads as the phosphor glow round the letters.
	local glow = Instance.new("UIStroke")
	glow.Thickness = 7
	glow.LineJoinMode = Enum.LineJoinMode.Round
	glow.Parent = title
	title.Text = "YOU WENT DOWN"

	local cause = text(canvas, "Cause", Enum.Font.FredokaOne, 28, BODY, CAUSE_Y, 36)
	cause.RichText = true
	local bag = text(canvas, "Bag", Enum.Font.FredokaOne, 23, DIM, BAG_Y, 32)

	local wake = text(canvas, "Wake", Enum.Font.RobotoMono, 16, Color3.new(1, 1, 1), WAKE_Y, 22)
	wake.Text = "W A K I N G   U P   A T   C A M P"

	local track = frame(canvas, "BarTrack", Color3.fromHex("1C2A1C"), 5)
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.new(0.5, 0, 0.5, BAR_Y)
	track.Size = UDim2.fromOffset(BAR_W, BAR_H)
	local trackRound = Instance.new("UICorner")
	trackRound.CornerRadius = UDim.new(0.5, 0)
	trackRound.Parent = track
	local fill = frame(track, "Fill", Color3.new(1, 1, 1), 6)
	fill.Size = UDim2.fromScale(0, 1)
	local fillRound = trackRound:Clone()
	fillRound.Parent = fill

	local skip = text(canvas, "Skip", Enum.Font.FredokaOne, 15, DIM, 0, 20)
	skip.AnchorPoint = Vector2.new(0.5, 1)
	skip.Position = UDim2.new(0.5, 0, 1, -26)

	-- CRT scanlines: a faint light line every 5 px, enough rows for any design height.
	local scan = frame(canvas, "Scanlines", BACKGROUND, 7)
	scan.BackgroundTransparency = 1
	scan.Size = UDim2.fromScale(1, 1)
	scan.ClipsDescendants = true
	for row = 0, 300 do
		local line = frame(scan, "Line", Color3.new(1, 1, 1), 7)
		line.BackgroundTransparency = 0.955
		line.Position = UDim2.fromOffset(0, row * 5)
		line.Size = UDim2.new(1, 0, 0, 2)
	end

	local vignette = frame(canvas, "Vignette", BACKGROUND, 8)
	vignette.BackgroundTransparency = 1
	vignette.Size = UDim2.fromScale(1, 1)
	vignetteEdge(vignette, "Top", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0), Vector2.zero, 90)
	vignetteEdge(vignette, "Bottom", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 1), Vector2.new(0, 1), -90)
	vignetteEdge(vignette, "Left", UDim2.fromScale(0.25, 1), UDim2.fromScale(0, 0), Vector2.zero, 0)
	vignetteEdge(vignette, "Right", UDim2.fromScale(0.25, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180)

	local flash = frame(canvas, "Flash", Color3.new(1, 1, 1), 10)
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1

	ui = {
		gui = gui,
		canvas = canvas,
		background = background,
		trace = trace,
		title = title,
		glow = glow,
		cause = cause,
		bag = bag,
		wake = wake,
		track = track,
		fill = fill,
		skip = skip,
		scan = scan,
		vignette = vignette,
		flash = flash,
		segments = {},
		traceLength = 0,
	}
	return gui
end

--- Lay the trace out for this screen's width: the beats round the centre, flat runs
--- out to both edges. Segments start at zero length; render() grows them.
local function buildTrace(accent: Color3)
	ui.trace:ClearAllChildren()
	table.clear(ui.segments)

	-- The camera's viewport, not the canvas's AbsoluteSize: the gui was only just
	-- enabled and has not been laid out yet. It is the whole screen either way
	-- (ScreenInsets None), in design px once divided by the canvas scale.
	local camera = workspace.CurrentCamera
	local scale = UIKit.scale()
	local halfWidth = if camera and scale > 0 then camera.ViewportSize.X / scale / 2 + 20 else 700

	local points = { Vector2.new(-halfWidth, 0) }
	for _, point in BEATS do
		table.insert(points, Vector2.new(point[1], point[2]))
	end
	table.insert(points, Vector2.new(halfWidth, 0))

	local walked = 0
	for i = 2, #points do
		local from, to = points[i - 1], points[i]
		local length = (to - from).Magnitude
		local angle = math.deg(math.atan2(to.Y - from.Y, to.X - from.X))
		local pieces = {}
		for _, spec in { { GLOW, GLOW_TRANSPARENCY, 3 }, { LINE, 0, 4 } } do
			local piece = frame(ui.trace, "Segment", accent, spec[3])
			piece.AnchorPoint = Vector2.new(0.5, 0.5)
			piece.BackgroundTransparency = spec[2]
			piece.Rotation = angle
			piece.Size = UDim2.fromOffset(0, spec[1])
			piece.Visible = false
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0.5, 0)
			round.Parent = piece
			table.insert(pieces, { frame = piece, thickness = spec[1], transparency = spec[2] })
		end
		table.insert(ui.segments, {
			from = from,
			direction = (to - from).Unit,
			length = length,
			start = walked,
			pieces = pieces,
		})
		walked += length
	end
	ui.traceLength = walked

	-- The pen: a bright dot riding the front of the line while it draws.
	ui.pen = {}
	for _, spec in { { 30, 0.7, 5 }, { 11, 0, 6 } } do
		local dot = frame(ui.trace, "Pen", Color3.new(1, 1, 1), spec[3])
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(spec[1], spec[1])
		dot.BackgroundColor3 = if spec[1] > 20 then accent else Color3.new(1, 1, 1)
		dot.BackgroundTransparency = spec[2]
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = dot
		table.insert(ui.pen, { frame = dot, transparency = spec[2] })
	end
end

-- ── Render ──────────────────────────────────────────────────────────────────

--- `alpha` 0..1 of a piece whose fully-shown transparency is `base`.
local function fade(base: number, alpha: number): number
	return 1 - (1 - base) * clamp01(alpha)
end

local function render(t: number)
	local out = 1 - ramp(t, FADE_AT, FADE_TIME)

	ui.background.BackgroundTransparency = fade(0, out)
	ui.flash.BackgroundTransparency = if playing.cause.flash then fade(0, 1 - ramp(t, 0, FLASH_TIME)) else 1

	-- The trace, drawn up to `pen` studs along its whole length.
	local pen = ui.traceLength * ramp(t, TRACE_AT, TRACE_TIME)
	local head = nil
	for _, segment in ui.segments do
		local shown = math.clamp(pen - segment.start, 0, segment.length)
		local centre = segment.from + segment.direction * (shown / 2)
		for _, piece in segment.pieces do
			piece.frame.Visible = shown > 0
			piece.frame.Position = UDim2.fromOffset(centre.X, centre.Y)
			-- A round-capped piece is never shorter than it is thick.
			piece.frame.Size = UDim2.fromOffset(math.max(shown, piece.thickness), piece.thickness)
			piece.frame.BackgroundTransparency = fade(piece.transparency, out)
		end
		if shown > 0 and shown < segment.length then
			head = segment.from + segment.direction * shown
		end
	end
	local drawing = head ~= nil and t < TRACE_AT + TRACE_TIME
	for _, dot in ui.pen do
		dot.frame.Visible = drawing
		if head then
			dot.frame.Position = UDim2.fromOffset(head.X, head.Y)
		end
		dot.frame.BackgroundTransparency = dot.transparency
	end

	local title = flicker(ramp(t, TITLE_AT, TITLE_TIME)) * out
	ui.title.TextTransparency = fade(0, title)
	ui.glow.Transparency = fade(0.55, title)

	for _, line in { { ui.cause, CAUSE_AT, CAUSE_Y }, { ui.bag, BAG_AT, BAG_Y } } do
		local shown = ramp(t, line[2], LINE_TIME)
		line[1].TextTransparency = fade(0, shown * out)
		line[1].Position = UDim2.new(0.5, 0, 0.5, line[3] + RISE * (1 - shown))
	end

	local wake = ramp(t, WAKE_AT, 0.3) * out
	ui.wake.TextTransparency = fade(0, wake)
	ui.track.BackgroundTransparency = fade(0, wake)
	ui.fill.BackgroundTransparency = fade(0, wake)
	ui.fill.Size = UDim2.fromScale(ramp(t, BAR_AT, BAR_END - BAR_AT), 1)

	ui.skip.TextTransparency = if t < FADE_AT then fade(0.3, ramp(t, SKIP_AT, 0.3)) else 1

	ui.scan.Visible = out > 0.5
	ui.vignette.Visible = out > 0.5
end

local function stop()
	if playing and playing.conn then
		playing.conn:Disconnect()
	end
	playing = nil
	if ui then
		ui.gui.Enabled = false
	end
end

-- ── API ─────────────────────────────────────────────────────────────────────

--- Play the screen for one blackout payload (ExposureService): { cause, itemsDropped,
--- itemsDetonated, stageName, depth }. A second call mid-play starts it over.
function DeathScreen.play(info: any)
	if ui == nil then
		return
	end
	stop()

	local cause = CAUSES[info.cause] or CAUSES.exposure
	local accent = cause.accent
	local dropped = info.itemsDropped or 0
	local detonated = info.itemsDetonated or 0

	local where = { `<font color="#{accent:ToHex()}">{cause.title}</font>` }
	if info.stageName and info.stageName ~= "" then
		table.insert(where, info.stageName)
	end
	local depth = math.floor((info.depth or 0) + 0.5)
	if depth > 0 then
		table.insert(where, `{depth} m`)
	end
	ui.cause.Text = table.concat(where, "  \u{00B7}  ")

	ui.bag.Text = if detonated > 0
		then `Your bag went off where you fell  \u{00B7}  {plural(detonated, "item", "items")} lost`
		elseif dropped > 0 then `Dropped {plural(dropped, "item", "items")} where you fell  \u{00B7}  1:30 to get {if dropped == 1 then "it" else "them"} back`
		else "Nothing lost"

	ui.title.TextColor3 = accent
	ui.glow.Color = accent
	ui.wake.TextColor3 = accent
	ui.fill.BackgroundColor3 = accent
	ui.skip.Text = if UIKit.isTouch() then "tap to skip" else "click to skip"

	ui.gui.Enabled = true
	buildTrace(accent)

	local run = { started = os.clock(), cause = cause, conn = nil }
	playing = run
	render(0)
	run.conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - run.started
		local ok, err = pcall(render, t)
		if not ok then
			warn(`[deathscreen] render failed: {err}`)
			stop()
		elseif t >= FADE_AT + FADE_TIME then
			stop()
		end
	end)
end

--- Whether the death screen is covering the screen right now.
function DeathScreen.isPlaying(): boolean
	return playing ~= nil
end

function DeathScreen.start()
	local gui = build()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Skip: once the headline is up, any click, tap or gamepad A/B jumps to the fade.
	UserInputService.InputBegan:Connect(function(input)
		if playing == nil then
			return
		end
		local kind = input.UserInputType
		local pressed = kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
			or input.KeyCode == Enum.KeyCode.ButtonB
		local t = os.clock() - playing.started
		if pressed and t >= SKIP_AT and t < FADE_AT then
			playing.started = os.clock() - FADE_AT
		end
	end)
end

return DeathScreen
