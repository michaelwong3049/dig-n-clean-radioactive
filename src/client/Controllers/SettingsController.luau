--[[
	SettingsController.lua — the player Settings panel, in three tabs:

	  GENERAL   base colour, HIDE MY AURA, rare drop announcements
	  GRAPHICS  graphics level, radiation effects, screen shake, reduce flashing, FAST MODE
	  AUDIO     SOUND EFFECTS (the mute) and the master / effects / UI / Geiger sliders

	EVERYTHING BUT THE FIRST THREE IS A PREF (Config/Prefs, client/Prefs). The rows here
	only show and set them; each one is applied by the file that owns the effect
	(ItemFxController, RadFx, DetonationController, Sfx...), off Prefs.observe, so it
	holds even if this panel never builds. Prefs apply the same frame and save behind;
	the colour, aura and mute keep their older wait-for-the-echo shape.

	SOUND EFFECTS is the same shape as HIDE MY AURA below: a profile setting
	(data.sfxMuted) the server owns and echoes on Net.SfxMuted. The mute itself is
	SfxController's (it zeroes Sfx.luau's master group); this panel only shows and
	flips it.

	HIDE MY AURA turns your aura off for everyone (on request, over hiding auras only
	on your own screen). It is a profile setting the server owns, exactly like the
	colour: the switch fires Net.HideAura with the new boolean and waits for
	AuraService's confirmed echo before it changes, and the server sends the saved
	value once on load. The aura keeps protecting you while hidden.

	WHY A COLOUR PICKER LIVES HERE. Every plot is built in one neutral grey
	(build/Plots' `C.plotNeutral`), and the accent — the two side Trim strips, the
	four bars framing the nameplate, the cleansing-station lamp, the CLEANSING
	STATION / WASH PAD sign subtitles, and the gallery's arch, plinth bands, fence caps
	and slot brackets — is RUNTIME state now. The server owns it:
	`ExhibitService.setPlotColor` validates a hex, stores it on the profile
	(`data.plotColor`) and repaints via `Plots.setPlotAccent`. Until a player picks, a
	claimed plot wears its own default hue (build/Plots' `DEFAULT_ACCENTS`), which the
	server sends alongside every echo so the swatch shows it. This file is the other
	end of that remote — a full RGB picker, and nothing else.

	THE CLIENT NEVER PAINTS THE WORLD. Picking a colour fires `Net.PlotColor` and waits;
	the plot repaints when the server's own render runs. The only thing this file
	colours is the preview swatch inside the panel. The server echoes the
	SERVER-CONFIRMED value straight back, so a rejected or rate-limited change reverts
	the picker to what actually stuck.

	CONFIRMATION IS IN-PANEL, NOT A STATION TOAST. `StationResult` is invisible away
	from a station panel (see ExhibitService / the wash pad's own note), and this is a
	screen GUI, not a station — so the status line here says "saved", and the real
	feedback is your base changing colour behind the panel.

	SHAPE MIRRORS IndexController: a ScreenGui with a corner button and a centred
	`UIKit.panel` that toggles. `start()` only — nothing to build in `init()`.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local HudTile = require(script.Parent.Parent.HudTile)
local Artwork = require(script.Parent.Parent.HudArtwork)
local Prefs = require(script.Parent.Parent.Prefs)
local Rarity = require(Shared.Config.Rarity)

local Settings = {}

-- Mirrors build/Kit.luau `C.plotNeutral` — the grey an unclaimed plot (and a claimed
-- one whose owner has never picked) wears. Duplicated rather than shared because Kit
-- lives in ServerScriptService; same small, documented dup as CashController's
-- formatCash. Keep in step if the server value changes.
local NEUTRAL = Color3.fromHex("7F8388")

-- THE PANEL'S OWN PALETTE: neutral greys, no green, on request — the near-black and
-- edge of the right-edge tiles (UIKit.C.nav*), with a light steel for whatever is on
-- (the chosen tab, an On switch, the chosen option, a slider's fill). UIKit.C's
-- olive panel/selected greens stay for the rest of the HUD.
local C = {
	panel = UIKit.C.navFill,
	stroke = UIKit.C.navEdge,
	empty = Color3.fromRGB(32, 35, 41),
	selected = Color3.fromRGB(74, 82, 96),
	fill = Color3.fromRGB(205, 214, 226), -- a slider's filled part
	text = UIKit.C.navIcon,
	dim = Color3.fromRGB(138, 146, 158),
}

local PANEL_SIZE = Vector2.new(560, 668)
-- Where a tab's rows start (under the title and the tab strip), and a row's height.
local TABS_Y = 60
local TABS_H = 42
local CONTENT_Y = TABS_Y + TABS_H + 18
local ROW_H = 54
local ROW_GAP = 12

-- THE PANEL'S TYPE: Gotham Black throughout, in normal (sentence) case, on request —
-- one weight at four sizes rather than UIKit's three-weight scale.
local FONT = Enum.Font.GothamBlack
local SIZE = {
	title = 36, -- "Settings"
	row = 22, -- a row's name
	button = 18, -- switches, tabs, values
	option = 16, -- the narrower option buttons
	hint = 15, -- the line under a row's name
}
-- A row's switch, and each button of an option row.
local SWITCH_W, SWITCH_H = 120, 40
local OPTION_W, OPTION_GAP = 76, 6
-- Settings' REDUCE FLASHING slows the Anomaly colour cycle by this much (every reader
-- takes Rarity.ANOMALY_CYCLE fresh each frame).
local ANOMALY_SLOW = 4
-- The base colour section's height; the aura row sits under it.
local COLOUR_SECTION_H = 340
local SV_SIZE = Vector2.new(300, 190)
local HUE_W = 32
local GAP = 16

-- The picker's live HSV, plus whether the COMMITTED base colour is a real hue or the
-- neutral (never-picked / reset) state. `dragging` (any track) makes the preview show
-- the hue under the handles even before it is committed.
local state = {
	h = 0,
	s = 0.72,
	v = 0.92,
	committed = false,
	dragging = false,
	-- The plot's default hue, which the base wears while nothing is committed. nil
	-- until the server says (and if the player holds no plot).
	fallback = nil :: Color3?,
}

-- HIDE MY AURA, as the server last confirmed it. `known` stays false until the load
-- echo, and the switch ignores clicks until then rather than guessing.
local aura = {
	hidden = false,
	known = false,
	pending = false,
}

-- SOUND EFFECTS, as the server last confirmed it. Same known/pending gate as `aura`.
local sound = {
	muted = false,
	known = false,
	pending = false,
}

local ui = {}

-- ── Colour helpers ──────────────────────────────────────────────────

local function currentColor(): Color3
	return Color3.fromHSV(state.h, state.s, state.v)
end

local function hexOf(color: Color3): string
	return string.upper(color:ToHex())
end

-- ── Render ──────────────────────────────────────────────────────────

local function setStatus(text: string)
	if ui.status then
		ui.status.Text = text
	end
end

--- Push `state` onto every piece of the picker. Cheap; called on every input frame
--- while dragging and once per server echo.
local function applyPreview()
	local picked = currentColor()

	ui.hueHandle.Position = UDim2.fromScale(0.5, state.h)
	ui.svArea.BackgroundColor3 = Color3.fromHSV(state.h, 1, 1)
	ui.svHandle.Position = UDim2.fromScale(state.s, 1 - state.v)

	local live = state.committed or state.dragging
	ui.swatch.BackgroundColor3 = if live then picked else (state.fallback or NEUTRAL)
	ui.hexLabel.Text = if live then "#" .. hexOf(picked) elseif state.fallback then "Auto" else "Not set"
end

-- ── Commit ──────────────────────────────────────────────────────────

--- Send the pick to the server. "" resets the base to its default hue. The server echoes the
--- confirmed value back on Net.PlotColor, which `onServerColor` reconciles — so this
--- does NOT optimistically set `state.committed`; it waits for the echo.
local function commit(hex: string)
	setStatus(if hex == "" then "Resetting\u{2026}" else "Saving\u{2026}")
	Net.get("PlotColor"):FireServer(hex)
end

--- The server's authoritative value (fired once on load, and after every change),
--- plus the plot's default hue — what the base wears while `hex` is "".
local function onServerColor(hex: any, fallback: any)
	state.fallback = nil
	if type(fallback) == "string" and fallback ~= "" then
		local ok, parsed = pcall(Color3.fromHex, fallback)
		if ok then
			state.fallback = parsed
		end
	end
	if type(hex) ~= "string" or hex == "" then
		state.committed = false
		setStatus("")
	else
		local ok, parsed = pcall(Color3.fromHex, hex)
		if ok then
			state.h, state.s, state.v = parsed:ToHSV()
			state.committed = true
			setStatus("Saved \u{2713}")
		end
	end
	applyPreview()
end

-- ── Hide my aura ────────────────────────────────────────────────────

local function applyAura()
	local switch = ui.auraSwitch
	if switch == nil then
		return
	end
	switch.Text = if aura.pending or not aura.known then "\u{2026}" elseif aura.hidden then "On" else "Off"
	switch.BackgroundColor3 = if aura.hidden then C.selected else C.empty
	switch.TextColor3 = if aura.hidden then C.text else C.dim
end

--- The server's confirmed value: once on load, then after every toggle.
local function onServerHideAura(hidden: any)
	aura.hidden = hidden == true
	aura.known = true
	aura.pending = false
	applyAura()
end

local function toggleAura()
	if not aura.known or aura.pending then
		return
	end
	aura.pending = true
	applyAura()
	Net.get("HideAura"):FireServer(not aura.hidden)
end

local function buildAuraRow(section: Instance)
	UIKit.label(section, {
		name = "SectionTitle",
		size = UDim2.new(1, -SWITCH_W - 12, 0, 28),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = "Hide my aura",
		zIndex = 12,
	})

	UIKit.label(section, {
		name = "SectionHint",
		position = UDim2.fromOffset(0, 28),
		size = UDim2.new(1, -SWITCH_W - 12, 0, 20),
		font = FONT,
		textSize = SIZE.hint,
		color = C.dim,
		text = "Off for everyone \u{2014} it still protects you",
		zIndex = 12,
	})

	local switch = UIKit.button(section, {
		name = "AuraSwitch",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 6),
		size = UDim2.fromOffset(SWITCH_W, SWITCH_H),
		text = "\u{2026}",
		font = FONT,
		textSize = SIZE.button,
		color = C.dim,
		fillColor = C.empty,
		fillTransparency = 0,
		cornerRadius = UIKit.Radius.button,
		zIndex = 12,
	})
	switch.MouseButton1Click:Connect(toggleAura)
	ui.auraSwitch = switch
	applyAura()
end

-- ── Sound effects ───────────────────────────────────────────────────

local function applySound()
	local switch = ui.soundSwitch
	if switch == nil then
		return
	end
	local on = not sound.muted
	switch.Text = if sound.pending or not sound.known then "\u{2026}" elseif on then "On" else "Off"
	switch.BackgroundColor3 = if on then C.selected else C.empty
	switch.TextColor3 = if on then C.text else C.dim
end

--- The server's confirmed value: once on load, then after every toggle.
local function onServerSfxMuted(muted: any)
	sound.muted = muted == true
	sound.known = true
	sound.pending = false
	applySound()
end

local function toggleSound()
	if not sound.known or sound.pending then
		return
	end
	sound.pending = true
	applySound()
	Net.get("SfxMuted"):FireServer(not sound.muted)
end

local function buildSoundRow(section: Instance)
	UIKit.label(section, {
		name = "SectionTitle",
		size = UDim2.new(1, -SWITCH_W - 12, 0, 28),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = "Sound effects",
		zIndex = 12,
	})

	UIKit.label(section, {
		name = "SectionHint",
		position = UDim2.fromOffset(0, 28),
		size = UDim2.new(1, -SWITCH_W - 12, 0, 20),
		font = FONT,
		textSize = SIZE.hint,
		color = C.dim,
		text = "Every sound in the game, for you only",
		zIndex = 12,
	})

	local switch = UIKit.button(section, {
		name = "SoundSwitch",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 6),
		size = UDim2.fromOffset(SWITCH_W, SWITCH_H),
		text = "\u{2026}",
		font = FONT,
		textSize = SIZE.button,
		color = C.dim,
		fillColor = C.empty,
		fillTransparency = 0,
		cornerRadius = UIKit.Radius.button,
		zIndex = 12,
	})
	switch.MouseButton1Click:Connect(toggleSound)
	ui.soundSwitch = switch
	applySound()
end

-- ── Pref rows ───────────────────────────────────────────────────────

--- A row's title and hint, on the left, leaving `rightW` for its control.
local function rowText(row: Instance, title: string, hint: string, rightW: number)
	UIKit.label(row, {
		name = "SectionTitle",
		size = UDim2.new(1, -rightW - 12, 0, 28),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = title,
		zIndex = 12,
	})
	UIKit.label(row, {
		name = "SectionHint",
		position = UDim2.fromOffset(0, 30),
		-- Tall enough for two lines: a long hint wraps instead of running under the control.
		size = UDim2.new(1, -rightW - 12, 0, 36),
		font = FONT,
		textSize = SIZE.hint,
		color = C.dim,
		text = hint,
		yAlign = Enum.TextYAlignment.Top,
		wrapped = true,
		zIndex = 12,
	})
end

local function paintSwitch(button: TextButton, on: boolean, text: string)
	button.Text = text
	button.BackgroundColor3 = if on then C.selected else C.empty
	button.TextColor3 = if on then C.text else C.dim
end

local function switchButton(row: Instance, name: string, width: number, x: UDim): TextButton
	local button = UIKit.button(row, {
		name = name,
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(x, UDim.new(0, 6)),
		size = UDim2.fromOffset(width, SWITCH_H),
		text = "",
		font = FONT,
		textSize = SIZE.button,
		color = C.dim,
		fillColor = C.empty,
		fillTransparency = 0,
		cornerRadius = UIKit.Radius.button,
		zIndex = 12,
	})
	return button
end

--- ON / OFF for a flag pref.
local function flagRow(row: Instance, key: string, title: string, hint: string)
	rowText(row, title, hint, SWITCH_W)
	local button = switchButton(row, "Switch", SWITCH_W, UDim.new(1, 0))
	button.MouseButton1Click:Connect(function()
		Prefs.set(key, not Prefs.get(key))
	end)
	Prefs.observe(key, function(on)
		paintSwitch(button, on == true, if on then "On" else "Off")
	end)
end

--- One button per option, side by side; the chosen one lit.
local function choiceRow(row: Instance, key: string, title: string, hint: string, options: { { string } })
	local each, gap = OPTION_W, OPTION_GAP
	local width = #options * each + (#options - 1) * gap
	rowText(row, title, hint, width)
	local buttons = {}
	for i, option in options do
		local value, label = option[1], option[2]
		local right = (#options - i) * (each + gap)
		local button = switchButton(row, "Option_" .. value, each, UDim.new(1, -right))
		button.TextSize = SIZE.option
		button.MouseButton1Click:Connect(function()
			Prefs.set(key, value)
		end)
		buttons[value] = { button = button, label = label }
	end
	Prefs.observe(key, function(current)
		for value, entry in buttons do
			paintSwitch(entry.button, value == current, entry.label)
		end
	end)
end

--- A 0..100% slider for a volume pref. Drags apply live (the sound moves under your
--- finger) and save once, on release.
local function volumeRow(row: Instance, key: string, title: string)
	local labelW, valueW = 150, 64

	UIKit.label(row, {
		name = "SectionTitle",
		position = UDim2.fromOffset(0, 13),
		size = UDim2.fromOffset(labelW, 28),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = title,
		zIndex = 12,
	})
	local value = UIKit.label(row, {
		name = "Value",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 13),
		size = UDim2.fromOffset(valueW, 28),
		font = FONT,
		textSize = SIZE.button,
		color = C.dim,
		text = "",
		zIndex = 12,
	})
	value.TextXAlignment = Enum.TextXAlignment.Right

	-- The hit box is the full row height so a thumb can grab it; the track is thin.
	local hit = Instance.new("Frame")
	hit.Name = "Slider"
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(labelW + 8, 0)
	hit.Size = UDim2.new(1, -(labelW + 8 + valueW + 10), 1, 0)
	hit.ZIndex = 12
	hit.Parent = row

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.new(1, 0, 0, 12)
	track.BackgroundColor3 = C.empty
	track.BorderSizePixel = 0
	track.ZIndex = 12
	track.Parent = hit
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = UIKit.C.outline
	trackStroke.Thickness = 1.5
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = C.fill
	fill.BorderSizePixel = 0
	fill.ZIndex = 13
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(24, 24)
	knob.BackgroundColor3 = C.text
	knob.BorderSizePixel = 0
	knob.ZIndex = 14
	knob.Parent = track
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
	local knobStroke = Instance.new("UIStroke")
	knobStroke.Color = UIKit.C.outline
	knobStroke.Thickness = 2
	knobStroke.Parent = knob

	local function paint(alpha: number)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		value.Text = `{math.round(alpha * 100)}%`
	end

	local dragging = false
	local function at(position: Vector3): number
		local x = (position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
		return math.clamp(x, 0, 1)
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		local alpha = at(input.Position)
		paint(alpha)
		Prefs.preview(key, alpha)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local alpha = at(input.Position)
		paint(alpha)
		Prefs.preview(key, alpha)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = false
		Prefs.set(key, at(input.Position))
	end)

	Prefs.observe(key, function(alpha)
		if not dragging then
			paint(alpha)
		end
	end)
end

-- ── Draggable tracks ────────────────────────────────────────────────

--- Wire a full-bleed transparent `catcher` frame so a press anywhere on it — and any
--- drag that then wanders off it — reports a clamped (fx, fy) in [0, 1] against the
--- catcher's own rect. `onMove` fires every frame of the drag; `onRelease` once at the
--- end. The catcher is topmost and transparent so the gradient layers and the handle
--- underneath it stay purely visual.
---
--- `dragging` is LOCAL to each call — the SV square and the hue strip must not both
--- react to one drag (they did while this flag was shared, and every drag moved both
--- handles). `state.dragging` is still set so applyPreview shows the live colour, but
--- the move/release gating is per-track.
local function makeDraggable(catcher: GuiObject, onMove: (number, number) -> (), onRelease: () -> ())
	local dragging = false

	local function fractionFrom(inputPos: Vector3): (number, number)
		local rel = Vector2.new(inputPos.X, inputPos.Y) - catcher.AbsolutePosition
		local fx = math.clamp(rel.X / math.max(catcher.AbsoluteSize.X, 1), 0, 1)
		local fy = math.clamp(rel.Y / math.max(catcher.AbsoluteSize.Y, 1), 0, 1)
		return fx, fy
	end

	catcher.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		state.dragging = true
		onMove(fractionFrom(input.Position))
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		onMove(fractionFrom(input.Position))
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = false
		state.dragging = false
		onRelease()
	end)
end

-- ── Build ───────────────────────────────────────────────────────────

local function gradientFrame(parent: Instance, name: string, color: Color3, transparency: NumberSequence, rotation: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = 12
	frame.Parent = parent

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(color)
	grad.Transparency = transparency
	grad.Rotation = rotation
	grad.Parent = frame
	return frame
end

local function handleDot(parent: Instance): Frame
	local dot = Instance.new("Frame")
	dot.Name = "Handle"
	dot.Size = UDim2.fromOffset(14, 14)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.ZIndex = 13
	dot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = dot
	return dot
end

local function buildColorPicker(section: Instance)
	-- Saturation / value square. Hue-coloured base, a white gradient across for
	-- saturation and a black gradient down for value; a transparent catcher on top
	-- takes the drag.
	local svArea = Instance.new("Frame")
	svArea.Name = "SVArea"
	svArea.Size = UDim2.fromOffset(SV_SIZE.X, SV_SIZE.Y)
	svArea.Position = UDim2.fromOffset(0, 0)
	svArea.BackgroundColor3 = Color3.fromHSV(state.h, 1, 1)
	svArea.BorderSizePixel = 0
	svArea.ZIndex = 11
	svArea.Parent = section
	ui.svArea = svArea

	local svCorner = Instance.new("UICorner")
	svCorner.CornerRadius = UDim.new(0, 8)
	svCorner.Parent = svArea
	local svClip = Instance.new("UICorner") -- clip the gradient children to the rounded box
	svClip.CornerRadius = UDim.new(0, 8)
	svClip.Parent = svArea
	svArea.ClipsDescendants = true

	gradientFrame(
		svArea,
		"Saturation",
		Color3.new(1, 1, 1),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		0
	)
	gradientFrame(
		svArea,
		"Value",
		Color3.new(0, 0, 0),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		90
	)

	ui.svHandle = handleDot(svArea)

	local svCatcher = Instance.new("Frame")
	svCatcher.Name = "Catcher"
	svCatcher.Size = UDim2.fromScale(1, 1)
	svCatcher.BackgroundTransparency = 1
	svCatcher.ZIndex = 14
	svCatcher.Active = true
	svCatcher.Parent = svArea

	makeDraggable(svCatcher, function(fx, fy)
		state.s = fx
		state.v = 1 - fy
		applyPreview()
	end, function()
		commit(hexOf(currentColor()))
	end)

	-- Hue strip, to the right of the square. A vertical rainbow; drag picks hue.
	local hue = Instance.new("Frame")
	hue.Name = "Hue"
	hue.Size = UDim2.fromOffset(HUE_W, SV_SIZE.Y)
	hue.Position = UDim2.fromOffset(SV_SIZE.X + GAP, 0)
	hue.BackgroundColor3 = Color3.new(1, 1, 1)
	hue.BorderSizePixel = 0
	hue.ZIndex = 11
	hue.ClipsDescendants = true
	hue.Parent = section

	local hueCorner = Instance.new("UICorner")
	hueCorner.CornerRadius = UDim.new(0, 6)
	hueCorner.Parent = hue

	local hueGrad = Instance.new("UIGradient")
	hueGrad.Rotation = 90
	hueGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromHSV(0.00, 1, 1)),
		ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17, 1, 1)),
		ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
		ColorSequenceKeypoint.new(0.50, Color3.fromHSV(0.50, 1, 1)),
		ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
		ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
		ColorSequenceKeypoint.new(1.0, Color3.fromHSV(1.00, 1, 1)),
	})
	hueGrad.Parent = hue

	local hueHandle = Instance.new("Frame")
	hueHandle.Name = "HueHandle"
	hueHandle.Size = UDim2.new(1, 6, 0, 6)
	hueHandle.AnchorPoint = Vector2.new(0.5, 0.5)
	hueHandle.BackgroundColor3 = Color3.new(1, 1, 1)
	hueHandle.BorderSizePixel = 0
	hueHandle.ZIndex = 13
	hueHandle.Parent = hue
	local hhStroke = Instance.new("UIStroke")
	hhStroke.Color = Color3.new(0, 0, 0)
	hhStroke.Thickness = 2
	hhStroke.Transparency = 0.3
	hhStroke.Parent = hueHandle
	ui.hueHandle = hueHandle

	local hueCatcher = Instance.new("Frame")
	hueCatcher.Name = "Catcher"
	hueCatcher.Size = UDim2.fromScale(1, 1)
	hueCatcher.BackgroundTransparency = 1
	hueCatcher.ZIndex = 14
	hueCatcher.Active = true
	hueCatcher.Parent = hue

	makeDraggable(hueCatcher, function(_, fy)
		state.h = fy
		applyPreview()
	end, function()
		commit(hexOf(currentColor()))
	end)

	-- Preview swatch + hex, and the two commit buttons, in the strip under the square.
	local footerY = SV_SIZE.Y + 20

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Size = UDim2.fromOffset(54, 54)
	swatch.Position = UDim2.fromOffset(0, footerY)
	swatch.BackgroundColor3 = NEUTRAL
	swatch.BorderSizePixel = 0
	swatch.ZIndex = 12
	swatch.Parent = section
	local swCorner = Instance.new("UICorner")
	swCorner.CornerRadius = UDim.new(0, 8)
	swCorner.Parent = swatch
	local swStroke = Instance.new("UIStroke")
	swStroke.Color = C.stroke
	swStroke.Thickness = 2
	swStroke.Parent = swatch
	ui.swatch = swatch

	ui.hexLabel = UIKit.label(section, {
		name = "Hex",
		position = UDim2.fromOffset(66, footerY + 2),
		size = UDim2.fromOffset(140, 24),
		font = FONT,
		textSize = SIZE.button,
		color = C.text,
		text = "Not set",
		zIndex = 12,
	})

	ui.status = UIKit.label(section, {
		name = "Status",
		position = UDim2.fromOffset(66, footerY + 30),
		size = UDim2.fromOffset(200, 20),
		font = FONT,
		textSize = SIZE.hint,
		color = C.dim,
		text = "",
		zIndex = 12,
	})

	local apply = UIKit.button(section, {
		name = "Apply",
		position = UDim2.fromOffset(SV_SIZE.X + GAP + HUE_W - 170, footerY),
		size = UDim2.fromOffset(170, SWITCH_H),
		text = "Apply",
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		fillColor = C.selected,
		fillTransparency = 0,
		cornerRadius = UIKit.Radius.button,
		zIndex = 12,
	})
	apply.MouseButton1Click:Connect(function()
		commit(hexOf(currentColor()))
	end)

	local reset = UIKit.button(section, {
		name = "Reset",
		position = UDim2.fromOffset(SV_SIZE.X + GAP + HUE_W - 170, footerY + SWITCH_H + 8),
		size = UDim2.fromOffset(170, 32),
		text = "Reset to default",
		font = FONT,
		textSize = SIZE.hint,
		color = C.dim,
		fillColor = C.empty,
		fillTransparency = 0.2,
		cornerRadius = UIKit.Radius.slot,
		zIndex = 12,
	})
	reset.MouseButton1Click:Connect(function()
		commit("")
	end)
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110 -- with the other full panels (Index, Shop, Nukes): over the vitals and the tutorial banner
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- The button: a small gear tile up in the topbar band on the LEFT, right after
	-- Roblox's own buttons (the microphone), on request (Dock.topbarLeftCentre). HudTile's glow-orb tile, kept in HudTile's own gui, which
	-- ignores the topbar inset. The grid keeps below it on short screens
	-- (Dock.CORNER_BUTTON_BOTTOM).
	local canvas = UIKit.canvas(gui)

	local tileGui, button = HudTile.build({
		name = "SettingsButton",
		caption = "Settings",
		slot = 1,
		topbarLeft = true,
		color = Color3.fromHex("9FB4C8"),
		light = Color3.fromHex("DCE6F0"),
		image = Artwork.IMAGE.settingsGear,
	})
	-- Parented beside the panel's gui in start(): a ScreenGui inside another draws nothing.
	ui.tileGui = tileGui

	local panel = UIKit.panel(canvas, {
		name = "Panel",
		size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = C.panel,
		transparency = 0,
		strokeColor = C.stroke,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		zIndex = 10,
		visible = false,
	})
	ui.panel = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 24)
	padding.PaddingBottom = UDim.new(0, 24)
	padding.PaddingLeft = UDim.new(0, 28)
	padding.PaddingRight = UDim.new(0, 28)
	padding.Parent = panel

	UIKit.label(panel, {
		name = "Title",
		size = UDim2.new(1, -50, 0, 46),
		font = FONT,
		textSize = SIZE.title,
		color = C.text,
		text = "Settings",
		zIndex = 11,
	})

	local close = UIKit.button(panel, {
		name = "Close",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.fromOffset(40, 40),
		text = "X",
		font = FONT,
		textSize = SIZE.row,
		color = UIKit.House.white,
		fillColor = UIKit.House.close,
		fillTransparency = 0,
		strokeColor = UIKit.House.ink,
		strokeThickness = 3,
		cornerRadius = UIKit.Radius.slot,
		zIndex = 12,
	})

	-- The tab strip, then one page per tab; only the chosen page is visible.
	local strip = Instance.new("Frame")
	strip.Name = "Tabs"
	strip.Position = UDim2.fromOffset(0, TABS_Y)
	strip.Size = UDim2.new(1, 0, 0, TABS_H)
	strip.BackgroundTransparency = 1
	strip.ZIndex = 11
	strip.Parent = panel

	local TABS = { "GENERAL", "GRAPHICS", "AUDIO" }
	local TAB_LABEL = { GENERAL = "General", GRAPHICS = "Graphics", AUDIO = "Audio" }
	local pages: { [string]: Frame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local function choose(name: string)
		for tab, page in pages do
			page.Visible = tab == name
			paintSwitch(tabButtons[tab], tab == name, TAB_LABEL[tab])
		end
	end
	for i, name in TABS do
		local tabButton = UIKit.button(strip, {
			name = name,
			-- Three equal tabs with a 6px gap between them, flush to both edges.
			position = UDim2.new((i - 1) / #TABS, (i - 1) * 2, 0, 0),
			size = UDim2.new(1 / #TABS, -4, 1, 0),
			text = TAB_LABEL[name],
			font = FONT,
			textSize = SIZE.button,
			color = C.dim,
			fillColor = C.empty,
			fillTransparency = 0,
			cornerRadius = UIKit.Radius.button,
			zIndex = 12,
		})
		tabButton.MouseButton1Click:Connect(function()
			choose(name)
		end)
		tabButtons[name] = tabButton

		local page = Instance.new("Frame")
		page.Name = name
		page.Position = UDim2.fromOffset(0, CONTENT_Y)
		page.Size = UDim2.new(1, 0, 1, -CONTENT_Y)
		page.BackgroundTransparency = 1
		page.ZIndex = 11
		page.Visible = false
		page.Parent = panel
		pages[name] = page
	end

	-- Rows stack down a page from `y`; returns the row frame.
	local function row(page: Frame, name: string, y: number, height: number?): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Position = UDim2.fromOffset(0, y)
		frame.Size = UDim2.new(1, 0, 0, height or ROW_H)
		frame.BackgroundTransparency = 1
		frame.ZIndex = 11
		frame.Parent = page
		return frame
	end
	local step = ROW_H + ROW_GAP

	-- GENERAL: the base colour, then the aura and rare drop rows under it.
	local general = pages.GENERAL
	local section = row(general, "BaseColour", 0, COLOUR_SECTION_H)

	UIKit.label(section, {
		name = "SectionTitle",
		size = UDim2.new(1, 0, 0, 28),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = "Base colour",
		zIndex = 12,
	})

	UIKit.label(section, {
		name = "SectionHint",
		position = UDim2.fromOffset(0, 28),
		size = UDim2.new(1, 0, 0, 20),
		font = FONT,
		textSize = SIZE.hint,
		color = C.dim,
		text = "The accent on your base: trim, nameplate, station signs",
		zIndex = 12,
	})

	local pickerHost = Instance.new("Frame")
	pickerHost.Name = "Picker"
	pickerHost.Position = UDim2.fromOffset(0, 60)
	pickerHost.Size = UDim2.new(1, 0, 1, -60)
	pickerHost.BackgroundTransparency = 1
	pickerHost.ZIndex = 11
	pickerHost.Parent = section

	buildColorPicker(pickerHost)

	local y = COLOUR_SECTION_H + 8
	buildAuraRow(row(general, "Aura", y))
	y += step
	choiceRow(row(general, "RareDrops", y), "rareDrops", "Rare drops", "Which drop alerts you see", {
		{ "all", "All" },
		{ "mine", "Mine" },
		{ "off", "Off" },
	})

	-- GRAPHICS
	local graphics = pages.GRAPHICS
	y = 0
	choiceRow(row(graphics, "Graphics", y), "graphics", "Graphics", "Low helps slower devices", {
		{ "low", "Low" },
		{ "med", "Med" },
		{ "high", "High" },
	})
	y += step
	choiceRow(row(graphics, "RadFx", y), "radFx", "Radiation effects", "On-screen only; damage is unchanged", {
		{ "reduced", "Less" },
		{ "full", "Full" },
	})
	y += step
	flagRow(row(graphics, "Shake", y), "shake", "Screen shake", "Blasts and radiation wobble")
	y += step
	flagRow(row(graphics, "Flashing", y), "reduceFlashing", "Reduce flashing", "Dims screen flashes, slows rainbows")
	y += step
	flagRow(row(graphics, "ConfirmDrop", y), "confirmDrop", "Confirm rare drops", "Ask before bombing a Rare+ nuke")
	y += step
	flagRow(row(graphics, "FastMode", y), "fastMode", "FAST MODE", "Hides other players' nukes and names; stops auras and nuke effects")

	-- AUDIO: the mute first (it predates the sliders), then the sliders.
	local audio = pages.AUDIO
	y = 0
	buildSoundRow(row(audio, "Sound", y))
	y += step
	volumeRow(row(audio, "Master", y), "volMaster", "Master")
	y += step
	volumeRow(row(audio, "Effects", y), "volSfx", "Effects")
	y += step
	volumeRow(row(audio, "Interface", y), "volUi", "Interface")
	y += step
	volumeRow(row(audio, "Geiger", y), "volGeiger", "Geiger")
	y += step
	volumeRow(row(audio, "Music", y), "musicLevel", "Music")

	choose("GENERAL")

	local function toggle()
		panel.Visible = not panel.Visible
	end
	button.MouseButton1Click:Connect(toggle)
	close.MouseButton1Click:Connect(toggle)

	return gui
end

-- ── Lifecycle ───────────────────────────────────────────────────────

function Settings.start()
	local player = Players.LocalPlayer
	local gui = build()
	local playerGui = player:WaitForChild("PlayerGui")
	ui.tileGui.Parent = playerGui
	gui.Parent = playerGui

	applyPreview()

	-- REDUCE FLASHING's slower Anomaly cycle. Here, not in Prefs, because it is a
	-- shared Config value every Anomaly reader picks up on its own next frame.
	local anomalyCycle = Rarity.ANOMALY_CYCLE
	Prefs.observe("reduceFlashing", function(on)
		Rarity.ANOMALY_CYCLE = if on then anomalyCycle * ANOMALY_SLOW else anomalyCycle
	end)

	-- Fired once on load with the saved value, and again after every change as the
	-- server-confirmed echo — same channel both ways (Shared/Net.PlotColor).
	Net.get("PlotColor").OnClientEvent:Connect(onServerColor)
	-- The same once-on-load-then-echo channel for HIDE MY AURA (AuraService).
	Net.get("HideAura").OnClientEvent:Connect(onServerHideAura)
	-- And for SOUND EFFECTS (SfxService). SfxController applies the mute off the same echo.
	Net.get("SfxMuted").OnClientEvent:Connect(onServerSfxMuted)
	-- Ask rather than wait: SfxController connected first and took the queued load echo.
	Net.get("SfxMuted"):FireServer(nil)
end

return Settings
