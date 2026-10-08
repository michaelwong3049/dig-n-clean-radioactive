--[[
	SettingsController.lua — the player Settings panel: a wide panel with a tab rail
	down the left (General / Graphics / Audio / Stats) and the chosen page on the right.

	  GENERAL   base colour, rare drop alerts, confirm rare drops
	  GRAPHICS  graphics level (also the radiation effects), screen shake, reduce flashing, show auras, fast mode
	  AUDIO     sound effects (the mute) and the master / effects / UI / Geiger / music sliders
	  STATS     your lifetime numbers, read only: playtime, nukes dug, cash earned, kills...

	THE LOOK (on request, mockup "2 Sidebar"): House slate, ink outlines, rows split by
	thin lines rather than boxed, pill switches for flags, a segmented picker for
	choices. Landscape (720x470) so it fits short phone screens; each page scrolls if
	it outgrows the panel. No green on the chrome (#651 still holds) — "on" is steel.

	EVERYTHING BUT THE COLOUR, AURA AND MUTE IS A PREF (Config/Prefs, client/Prefs). The
	rows here only show and set them; each one is applied by the file that owns the
	effect (ItemFxController, RadFx, DetonationController, Sfx...), off Prefs.observe, so
	it holds even if this panel never builds. Prefs apply the same frame and save behind;
	the colour, aura and mute keep their older wait-for-the-echo shape.

	SOUND EFFECTS is the same shape as the colour: a profile setting
	(data.sfxMuted) the server owns and echoes on Net.SfxMuted. The mute itself is
	SfxController's (it zeroes Sfx.luau's master group); this panel only shows and
	flips it.

	WHY A COLOUR PICKER LIVES HERE. Every plot is built in one neutral grey
	(build/Plots' `C.plotNeutral`), and the accent — the two side Trim strips, the
	four bars framing the nameplate, the cleansing-station lamp, the CLEANSING
	STATION / WASH PAD sign subtitles, and the gallery's arch, plinth bands, fence caps
	and slot brackets — is RUNTIME state now. The server owns it:
	`ExhibitService.setPlotColor` validates a hex, stores it on the profile
	(`data.plotColor`) and repaints via `Plots.setPlotAccent`. Until a player picks, a
	claimed plot wears its own default hue (build/Plots' `DEFAULT_ACCENTS`), which the
	server sends alongside every echo so the swatch shows it. This file is the other
	end of that remote: a row of preset swatches, and behind the rainbow one a full
	SV square + hue strip for anything else.

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
	Instance names tests drive: Panel.Tabs.<GENERAL|GRAPHICS|AUDIO|STATS> (the rail's
	buttons) and Panel.<GENERAL|GRAPHICS|AUDIO|STATS> (the pages).

	STATS IS THE SERVER'S (Services/StatsService, Net.PlayerStats). The page asks when it
	opens and every STATS_REFRESH seconds while it stays open, and each answer repaints
	the values; nothing is asked while the page is shut.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local HudTile = require(script.Parent.Parent.HudTile)
local Artwork = require(script.Parent.Parent.HudArtwork)
local Prefs = require(script.Parent.Parent.Prefs)
local Rarity = require(Shared.Config.Rarity)
local Stages = require(Shared.Config.Stages)
local Mastery = require(Shared.Mastery)

local Settings = {}

-- Mirrors build/Kit.luau `C.plotNeutral` — the grey an unclaimed plot (and a claimed
-- one whose owner has never picked) wears. Duplicated rather than shared because Kit
-- lives in ServerScriptService; same small, documented dup as CashController's
-- formatCash. Keep in step if the server value changes.
local NEUTRAL = Color3.fromHex("7F8388")

-- THE PANEL'S PALETTE: UIKit.House's slate and ink, plus a steel blue for whatever is
-- on (the chosen tab, an On switch, the chosen option, a slider's fill). No green.
local House = UIKit.House
local C = {
	panel = House.panel,
	rail = Color3.fromHex("15181C"), -- the tab rail, and the wells behind switches/sliders
	card = House.card, -- the chosen tab
	chip = Color3.fromHex("2B3036"), -- an off switch, a tab's icon chip at rest
	divider = Color3.fromHex("2A2F35"),
	ink = House.ink,
	on = Color3.fromHex("7E93AE"),
	knobOff = Color3.fromHex("7A838D"),
	text = House.white,
	dim = House.dim,
}

local PANEL_SIZE = Vector2.new(720, 470)
local RAIL_W = 190
-- The page column: inset from the rail's divider and the panel's right edge.
local PAGE_X = RAIL_W + 3 + 24
local PAGE_RIGHT = 24
local PAGE_TOP = 20
local HEADER_H = 62 -- the page's title + subtitle, above its scrolling rows
local ROW_H = 62
local SLIDER_H = 56
local STAT_H = 48 -- a Stats row with no hint
local GROUP_H = 40 -- a Stats group heading ("Digging", "Combat"...)
local STATS_REFRESH = 2 -- seconds between asks while the Stats page is open

-- THE PANEL'S TYPE: Gotham Black throughout, in sentence case (#650).
local FONT = House.font
local SIZE = {
	title = 28, -- "Settings" on the rail
	page = 26, -- a page's own heading
	tab = 18,
	row = 20, -- a row's name
	button = 16, -- values, the reset button
	option = 15, -- a segmented picker's options
	hint = 14, -- the line under a row's name
}
-- A flag's pill switch, and one option of a segmented picker.
local PILL_W, PILL_H, KNOB = 64, 34, 24
local OPTION_W, OPTION_H = 64, 30
-- Settings' REDUCE FLASHING slows the Anomaly colour cycle by this much (every reader
-- takes Rarity.ANOMALY_CYCLE fresh each frame).
local ANOMALY_SLOW = 4

-- Base colour: the preset swatches (a lime among them — it is the player's base, not
-- the panel's chrome), then the rainbow one that opens the full picker.
local PRESETS = { "E5484D", "F5A524", "F2D543", "7CF25A", "3FB3E0", "4C6FFF", "9B5CF6", "F06FC4", "E8ECF0" }
local SWATCH, SWATCH_GAP = 30, 7
local COLOUR_H = 106 -- the colour row with the picker closed
local SV_SIZE = Vector2.new(300, 130)
local HUE_W = 28
local GAP = 14
local PICKER_H = SV_SIZE.Y + 16

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

-- SOUND EFFECTS, as the server last confirmed it. `known` stays false until the load
-- echo, and the switch ignores clicks until then rather than guessing.
local sound = {
	muted = false,
	known = false,
	pending = false,
}

local ui = {
	-- Every page's ScrollingFrame: a drag on a slider or the picker locks them so a
	-- touch drag moves the handle, not the page.
	scrollers = {} :: { ScrollingFrame },
	-- Preset hex -> its swatch's UIStroke, plus the rainbow swatch's, lit to match the
	-- committed colour.
	presetStrokes = {} :: { [string]: UIStroke },
	-- Stats key -> its row's value label, and hint label where it has one.
	statValues = {} :: { [string]: TextLabel },
	statHints = {} :: { [string]: TextLabel },
}

-- ── Colour helpers ──────────────────────────────────────────────────

local function currentColor(): Color3
	return Color3.fromHSV(state.h, state.s, state.v)
end

local function hexOf(color: Color3): string
	return string.upper(color:ToHex())
end

local function lockScroll(locked: boolean)
	for _, scroller in ui.scrollers do
		scroller.ScrollingEnabled = not locked
	end
end

-- ── Render ──────────────────────────────────────────────────────────

local function setStatus(text: string)
	if ui.status then
		ui.status.Text = text
	end
end

--- Light the swatch that matches the committed colour: a preset, else the rainbow
--- one for a custom hue, else none (the base is on its default).
local function paintPresets()
	local committed = if state.committed then hexOf(currentColor()) else nil
	local matched = false
	for hex, stroke in ui.presetStrokes do
		if hex ~= "CUSTOM" then
			local on = committed ~= nil and hexOf(Color3.fromHex(hex)) == committed
			matched = matched or on
			stroke.Color = if on then C.text else C.ink
		end
	end
	local custom = ui.presetStrokes.CUSTOM
	if custom then
		custom.Color = if committed ~= nil and not matched then C.text else C.ink
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
	if not state.dragging then
		paintPresets()
	end
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

-- ── Controls ────────────────────────────────────────────────────────

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

--- An ink edge round a frame or button (Border mode, so a button's text keeps its own).
local function inkEdge(parent: Instance, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = C.ink
	stroke.Thickness = thickness or 3
	stroke.Parent = parent
	return stroke
end

--- A sliding pill switch, right-aligned and vertically centred in `row`. Returns the
--- button and its painter: paint(on, busy) — busy greys the knob while the server has
--- not answered yet.
local function pillSwitch(row: Instance, name: string): (TextButton, (boolean, boolean?) -> ())
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -4, 0.5, 0)
	button.Size = UDim2.fromOffset(PILL_W, PILL_H)
	button.BackgroundColor3 = C.chip
	button.BorderSizePixel = 0
	button.ZIndex = 12
	button.Parent = row
	corner(button, UDim.new(1, 0))
	inkEdge(button)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.Position = UDim2.new(0, 5, 0.5, 0)
	knob.BackgroundColor3 = C.knobOff
	knob.BorderSizePixel = 0
	knob.ZIndex = 13
	knob.Parent = button
	corner(knob, UDim.new(1, 0))

	local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function paint(on: boolean, busy: boolean?)
		button.BackgroundColor3 = if on then C.on else C.chip
		knob.BackgroundColor3 = if on then C.text else C.knobOff
		knob.BackgroundTransparency = if busy then 0.55 else 0
		local x = if on then PILL_W - 5 - KNOB else 5
		TweenService:Create(knob, info, { Position = UDim2.new(0, x, 0.5, 0) }):Play()
	end
	return button, paint
end

--- A row's title and hint, on the left, leaving `rightW` for its control.
local function rowText(row: Instance, title: string, hint: string, rightW: number)
	UIKit.label(row, {
		name = "SectionTitle",
		position = UDim2.fromOffset(0, 7),
		size = UDim2.new(1, -rightW - 14, 0, 24),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = title,
		zIndex = 12,
	})
	UIKit.label(row, {
		name = "SectionHint",
		position = UDim2.fromOffset(0, 32),
		-- Tall enough for two lines: a long hint wraps instead of running under the control.
		size = UDim2.new(1, -rightW - 14, 0, 30),
		font = FONT,
		textSize = SIZE.hint,
		color = C.dim,
		text = hint,
		yAlign = Enum.TextYAlignment.Top,
		wrapped = true,
		zIndex = 12,
	})
end

-- ── Sound effects ───────────────────────────────────────────────────

local function applySound()
	if ui.paintSound then
		ui.paintSound(not sound.muted, sound.pending or not sound.known)
	end
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

local function buildSoundRow(row: Instance)
	rowText(row, "Sound effects", "Every sound in the game, for you only", PILL_W)
	local switch, paint = pillSwitch(row, "SoundSwitch")
	switch.MouseButton1Click:Connect(toggleSound)
	ui.paintSound = paint
	applySound()
end

-- ── Pref rows ───────────────────────────────────────────────────────

--- A pill switch for a flag pref.
local function flagRow(row: Instance, key: string, title: string, hint: string)
	rowText(row, title, hint, PILL_W)
	local button, paint = pillSwitch(row, "Switch")
	button.MouseButton1Click:Connect(function()
		Prefs.set(key, not Prefs.get(key))
	end)
	Prefs.observe(key, function(on)
		paint(on == true)
	end)
end

--- A segmented picker: one well, one button per option, the chosen one lit.
local function choiceRow(row: Instance, key: string, title: string, hint: string, options: { { string } })
	local pad = 3
	local width = #options * OPTION_W + (#options - 1) * pad + pad * 2
	rowText(row, title, hint, width)

	local well = Instance.new("Frame")
	well.Name = "Options"
	well.AnchorPoint = Vector2.new(1, 0.5)
	well.Position = UDim2.new(1, -4, 0.5, 0)
	well.Size = UDim2.fromOffset(width, OPTION_H + pad * 2)
	well.BackgroundColor3 = C.rail
	well.BorderSizePixel = 0
	well.ZIndex = 12
	well.Parent = row
	corner(well, UDim.new(0, 12))
	inkEdge(well)

	local buttons = {}
	for i, option in options do
		local value, label = option[1], option[2]
		local button = UIKit.button(well, {
			name = "Option_" .. value,
			position = UDim2.fromOffset(pad + (i - 1) * (OPTION_W + pad), pad),
			size = UDim2.fromOffset(OPTION_W, OPTION_H),
			text = label,
			font = FONT,
			textSize = SIZE.option,
			color = C.dim,
			fillColor = C.on,
			fillTransparency = 1,
			cornerRadius = UDim.new(0, 9),
			zIndex = 13,
		})
		button.MouseButton1Click:Connect(function()
			Prefs.set(key, value)
		end)
		buttons[value] = button
	end
	Prefs.observe(key, function(current)
		for value, button in buttons do
			local on = value == current
			button.BackgroundTransparency = if on then 0 else 1
			button.TextColor3 = if on then C.text else C.dim
		end
	end)
end

--- A 0..100% slider for a volume pref. Drags apply live (the sound moves under your
--- finger) and save once, on release.
local function volumeRow(row: Instance, key: string, title: string)
	local labelW, valueW = 130, 56

	UIKit.label(row, {
		name = "SectionTitle",
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.fromScale(0, 0.5),
		size = UDim2.fromOffset(labelW, 28),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = title,
		zIndex = 12,
	})
	local value = UIKit.label(row, {
		name = "Value",
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -4, 0.5, 0),
		size = UDim2.fromOffset(valueW, 28),
		font = FONT,
		textSize = SIZE.button,
		color = C.text,
		xAlign = Enum.TextXAlignment.Right,
		text = "",
		zIndex = 12,
	})

	-- The hit box is the full row height so a thumb can grab it; the track is thin.
	local hit = Instance.new("Frame")
	hit.Name = "Slider"
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(labelW + 8, 0)
	hit.Size = UDim2.new(1, -(labelW + 8 + valueW + 18), 1, 0)
	hit.ZIndex = 12
	hit.Active = true
	hit.Parent = row

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(0, 0.5)
	track.Size = UDim2.new(1, 0, 0, 14)
	track.BackgroundColor3 = C.rail
	track.BorderSizePixel = 0
	track.ZIndex = 12
	track.Parent = hit
	corner(track, UDim.new(1, 0))
	inkEdge(track)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = C.on
	fill.BorderSizePixel = 0
	fill.ZIndex = 13
	fill.Parent = track
	corner(fill, UDim.new(1, 0))

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB, KNOB)
	knob.BackgroundColor3 = C.text
	knob.BorderSizePixel = 0
	knob.ZIndex = 14
	knob.Parent = track
	corner(knob, UDim.new(1, 0))
	inkEdge(knob)

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
		lockScroll(true)
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
		lockScroll(false)
		Prefs.set(key, at(input.Position))
	end)

	Prefs.observe(key, function(alpha)
		if not dragging then
			paint(alpha)
		end
	end)
end

-- ── Stats ───────────────────────────────────────────────────────────

--- 1,284,000.
local function commas(n: number): string
	local out = tostring(math.floor(n))
	repeat
		local changed
		out, changed = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
	until changed == 0
	return out
end

--- 45s, 12m, 3h 05m, 2d 4h.
local function duration(seconds: number): string
	seconds = math.floor(seconds)
	if seconds < 60 then
		return `{seconds}s`
	end
	local minutes = seconds // 60
	if minutes < 60 then
		return `{minutes}m`
	end
	local hours = minutes // 60
	if hours < 24 then
		return string.format("%dh %02dm", hours, minutes % 60)
	end
	return `{hours // 24}d {hours % 24}h`
end

-- The Stats page top to bottom: a `group` entry is a heading, the rest are stats keyed
-- by Net.PlayerStats' fields. `hint` adds a dim line under the title; `format` says how
-- the number reads (plain numbers get commas).
type StatDef = { key: string?, group: string?, title: string?, hint: string?, format: ((number) -> string)? }
local STATS: { StatDef } = {
	{ group = "Overall" },
	{ key = "playtime", title = "Playtime", hint = "Time spent in game", format = duration },
	{
		key = "cashEarned",
		title = "Cash earned",
		hint = "Every dollar you have ever made",
		format = function(n)
			return "$" .. Mastery.short(n)
		end,
	},
	{ key = "index", title = "Index found", hint = "Different nukes you have discovered" },
	{ key = "deepestStage", title = "Deepest stage", hint = "" }, -- the hint is the stage's name
	{ group = "Digging" },
	{ key = "dug", title = "Nukes dug up" },
	{ key = "rareFinds", title = "Rare finds", hint = "Legendary, Mythic and Anomaly nukes dug up" },
	{ key = "itemsCleaned", title = "Nukes cleaned" },
	{ key = "cratesOpened", title = "Crates opened" },
	{ group = "Combat" },
	{ key = "bombsDropped", title = "Nukes bombed", hint = "Clean nukes dropped as bombs" },
	{ key = "kills", title = "Players knocked out", hint = "Players downed by your bombs" },
	{ key = "bagsStolen", title = "Bags stolen", hint = "Dropped bags you took from other players" },
	{ key = "deaths", title = "Deaths" },
	{ group = "Crafting" },
	{ key = "merges", title = "Merges", hint = "At the Merge Reactor" },
	{ key = "rolls", title = "Fluids brewed" },
}

--- One stat: title (and hint) on the left, the number on the right.
local function statRow(row: Instance, def: StatDef)
	local key = def.key :: string
	local valueW = 200
	local hinted = def.hint ~= nil
	UIKit.label(row, {
		name = "SectionTitle",
		anchorPoint = if hinted then Vector2.zero else Vector2.new(0, 0.5),
		position = if hinted then UDim2.fromOffset(0, 5) else UDim2.fromScale(0, 0.5),
		size = UDim2.new(1, -valueW - 14, 0, 24),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = def.title or "",
		zIndex = 12,
	})
	if hinted then
		ui.statHints[key] = UIKit.label(row, {
			name = "SectionHint",
			position = UDim2.fromOffset(0, 30),
			size = UDim2.new(1, -valueW - 14, 0, 18),
			font = FONT,
			textSize = SIZE.hint,
			color = C.dim,
			text = def.hint or "",
			zIndex = 12,
		})
	end
	ui.statValues[key] = UIKit.label(row, {
		name = "Value",
		anchorPoint = Vector2.new(1, 0.5),
		position = UDim2.new(1, -4, 0.5, 0),
		size = UDim2.fromOffset(valueW, 28),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		xAlign = Enum.TextXAlignment.Right,
		text = "\u{2013}",
		zIndex = 12,
	})
end

--- A group heading over a run of stats, in the steel "on" blue.
local function groupRow(row: Instance, title: string)
	UIKit.label(row, {
		name = "Group",
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, 0, 1, -8),
		size = UDim2.new(1, 0, 0, 20),
		font = FONT,
		textSize = SIZE.hint,
		color = C.on,
		text = string.upper(title),
		zIndex = 12,
	})
end

--- The server's numbers (Net.PlayerStats) onto the rows.
local function onServerStats(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local function num(key: string): number
		return tonumber(payload[key]) or 0
	end
	for _, def in STATS do
		local key = def.key
		local label = if key then ui.statValues[key] else nil
		if key == nil or label == nil then
			continue
		end
		if key == "index" then
			label.Text = `{commas(num("indexFound"))} / {commas(num("indexTotal"))}`
		elseif key == "deepestStage" then
			local id = math.max(1, num("deepestStage"))
			label.Text = `Stage {id}`
			local ok, stage = pcall(Stages.get, id)
			ui.statHints.deepestStage.Text = if ok and stage then stage.name else ""
		elseif def.format then
			label.Text = def.format(num(key))
		else
			label.Text = commas(num(key))
		end
	end
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
		lockScroll(true)
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
		lockScroll(false)
		onRelease()
	end)
end

-- ── Base colour ─────────────────────────────────────────────────────

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
	corner(dot, UDim.new(1, 0))

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = dot
	return dot
end

--- The full picker (SV square + hue strip), shown behind the rainbow swatch.
local function buildColorPicker(section: Instance)
	-- Saturation / value square. Hue-coloured base, a white gradient across for
	-- saturation and a black gradient down for value; a transparent catcher on top
	-- takes the drag.
	local svArea = Instance.new("Frame")
	svArea.Name = "SVArea"
	svArea.Size = UDim2.fromOffset(SV_SIZE.X, SV_SIZE.Y)
	svArea.BackgroundColor3 = Color3.fromHSV(state.h, 1, 1)
	svArea.BorderSizePixel = 0
	svArea.ZIndex = 11
	svArea.ClipsDescendants = true
	svArea.Parent = section
	corner(svArea, UDim.new(0, 8))
	ui.svArea = svArea

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
	corner(hue, UDim.new(0, 6))

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
end

--- The base colour row: title + the live swatch and hex, the preset swatches with
--- Reset, and the full picker folded under them until the rainbow swatch opens it.
local function buildColourRow(row: Frame)
	rowText(row, "Base colour", "Trim, nameplate, station signs", 170)

	ui.hexLabel = UIKit.label(row, {
		name = "Hex",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -48, 0, 7),
		size = UDim2.fromOffset(120, 24),
		font = FONT,
		textSize = SIZE.button,
		color = C.text,
		xAlign = Enum.TextXAlignment.Right,
		text = "Not set",
		zIndex = 12,
	})
	ui.status = UIKit.label(row, {
		name = "Status",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -48, 0, 32),
		size = UDim2.fromOffset(120, 18),
		font = FONT,
		textSize = SIZE.hint,
		color = C.dim,
		xAlign = Enum.TextXAlignment.Right,
		text = "",
		zIndex = 12,
	})

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.AnchorPoint = Vector2.new(1, 0)
	swatch.Position = UDim2.new(1, -4, 0, 7)
	swatch.Size = UDim2.fromOffset(36, 36)
	swatch.BackgroundColor3 = NEUTRAL
	swatch.BorderSizePixel = 0
	swatch.ZIndex = 12
	swatch.Parent = row
	corner(swatch, UDim.new(0, 10))
	inkEdge(swatch)
	ui.swatch = swatch

	-- The swatch strip.
	local strip = Instance.new("Frame")
	strip.Name = "Presets"
	strip.Position = UDim2.fromOffset(3, 60)
	strip.Size = UDim2.new(1, -6, 0, SWATCH)
	strip.BackgroundTransparency = 1
	strip.ZIndex = 12
	strip.Parent = row

	local function swatchButton(name: string, x: number): (TextButton, UIStroke)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Text = ""
		button.AutoButtonColor = false
		button.Position = UDim2.fromOffset(x, 0)
		button.Size = UDim2.fromOffset(SWATCH, SWATCH)
		button.BorderSizePixel = 0
		button.ZIndex = 12
		button.Parent = strip
		corner(button, UDim.new(0, 9))
		return button, inkEdge(button)
	end

	for i, hex in PRESETS do
		local button, stroke = swatchButton("Preset_" .. hex, (i - 1) * (SWATCH + SWATCH_GAP))
		button.BackgroundColor3 = Color3.fromHex(hex)
		button.MouseButton1Click:Connect(function()
			state.h, state.s, state.v = Color3.fromHex(hex):ToHSV()
			commit(hexOf(Color3.fromHex(hex)))
		end)
		ui.presetStrokes[hex] = stroke
	end

	-- The rainbow swatch opens (and closes) the full picker under the strip.
	local customX = #PRESETS * (SWATCH + SWATCH_GAP)
	local custom, customStroke = swatchButton("Custom", customX)
	custom.BackgroundColor3 = Color3.new(1, 1, 1)
	local rainbow = Instance.new("UIGradient")
	rainbow.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromHSV(0.00, 1, 1)),
		ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
		ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
		ColorSequenceKeypoint.new(1.0, Color3.fromHSV(0.95, 1, 1)),
	})
	rainbow.Rotation = 45
	rainbow.Parent = custom
	ui.presetStrokes.CUSTOM = customStroke

	local reset = UIKit.button(strip, {
		name = "Reset",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.new(1, -(customX + SWATCH + 12), 0, SWATCH),
		text = "Reset",
		font = FONT,
		textSize = SIZE.option,
		color = C.dim,
		fillColor = C.chip,
		fillTransparency = 0,
		cornerRadius = UDim.new(0, 9),
		zIndex = 12,
	})
	reset.MouseButton1Click:Connect(function()
		commit("")
	end)

	local pickerHost = Instance.new("Frame")
	pickerHost.Name = "Picker"
	pickerHost.Position = UDim2.fromOffset(3, COLOUR_H)
	pickerHost.Size = UDim2.new(1, -6, 0, SV_SIZE.Y)
	pickerHost.BackgroundTransparency = 1
	pickerHost.ZIndex = 11
	pickerHost.Visible = false
	pickerHost.Parent = row
	buildColorPicker(pickerHost)

	custom.MouseButton1Click:Connect(function()
		pickerHost.Visible = not pickerHost.Visible
		row.Size = UDim2.new(1, 0, 0, if pickerHost.Visible then COLOUR_H + PICKER_H else COLOUR_H)
	end)
end

-- ── Build ───────────────────────────────────────────────────────────

-- A tab's icon, drawn from frames so it needs no upload: the gear art for General, a
-- little screen on a stand for Graphics, equaliser bars for Audio.
local function tabIcon(chip: Frame, tab: string)
	if tab == "GENERAL" then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromOffset(22, 22)
		image.Image = Artwork.IMAGE.settingsGear
		image.ZIndex = 15
		image.Parent = chip
		return
	end
	local function bar(x: number, y: number, w: number, h: number, hollow: boolean?)
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(w, h)
		f.BackgroundColor3 = C.text
		f.BackgroundTransparency = if hollow then 1 else 0
		f.BorderSizePixel = 0
		f.ZIndex = 15
		f.Parent = chip
		if hollow then
			local s = Instance.new("UIStroke")
			s.Color = C.text
			s.Thickness = 2
			s.Parent = f
			corner(f, UDim.new(0, 2))
		end
	end
	if tab == "GRAPHICS" then
		bar(6, 7, 18, 12, true)
		bar(13, 20, 4, 3)
		bar(10, 23, 10, 2)
	elseif tab == "STATS" then
		-- A rising bar chart on a baseline.
		bar(7, 17, 4, 6)
		bar(13, 12, 4, 11)
		bar(19, 7, 4, 16)
		bar(5, 23, 20, 2)
	else
		bar(6, 14, 4, 10)
		bar(13, 7, 4, 17)
		bar(20, 11, 4, 13)
	end
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
		topbarLeft = 1,
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
		strokeColor = C.ink,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		zIndex = 10,
		visible = false,
	})
	ui.panel = panel

	-- THE RAIL: rounded on the panel's left corners, squared where it meets the page,
	-- with an ink line between the two.
	local rail = Instance.new("Frame")
	rail.Name = "Tabs"
	rail.Size = UDim2.new(0, RAIL_W, 1, 0)
	rail.BackgroundColor3 = C.rail
	rail.BorderSizePixel = 0
	rail.ZIndex = 11
	rail.Parent = panel
	corner(rail, UIKit.Radius.panel)
	local square = Instance.new("Frame")
	square.Name = "Square"
	square.AnchorPoint = Vector2.new(1, 0)
	square.Position = UDim2.fromScale(1, 0)
	square.Size = UDim2.new(0, 24, 1, 0)
	square.BackgroundColor3 = C.rail
	square.BorderSizePixel = 0
	square.ZIndex = 11
	square.Parent = rail
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Position = UDim2.fromOffset(RAIL_W, 0)
	divider.Size = UDim2.new(0, 3, 1, 0)
	divider.BackgroundColor3 = C.ink
	divider.BorderSizePixel = 0
	divider.ZIndex = 11
	divider.Parent = panel

	UIKit.label(rail, {
		name = "Title",
		position = UDim2.fromOffset(18, 18),
		size = UDim2.new(1, -36, 0, 36),
		font = FONT,
		textSize = SIZE.title,
		color = C.text,
		text = "Settings",
		zIndex = 12,
	})

	local close = UIKit.button(panel, {
		name = "Close",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -16, 0, 16),
		size = UDim2.fromOffset(40, 40),
		text = "X",
		font = FONT,
		textSize = SIZE.row,
		color = House.white,
		fillColor = House.close,
		fillTransparency = 0,
		strokeColor = House.ink,
		strokeThickness = 3,
		cornerRadius = UIKit.Radius.slot,
		zIndex = 14,
	})

	local TABS = { "GENERAL", "GRAPHICS", "AUDIO", "STATS" }
	local TAB_LABEL = { GENERAL = "General", GRAPHICS = "Graphics", AUDIO = "Audio", STATS = "Stats" }
	local TAB_SUB = {
		GENERAL = "Your base and alerts",
		GRAPHICS = "Lower is smoother on slow devices",
		AUDIO = "Only changes what you hear",
		STATS = "Your lifetime numbers",
	}
	local pages: { [string]: Frame } = {}
	local scrollers: { [string]: ScrollingFrame } = {}
	local tabs: { [string]: { button: TextButton, back: Frame, chip: Frame } } = {}
	local function choose(name: string)
		for tab, page in pages do
			local on = tab == name
			page.Visible = on
			local t = tabs[tab]
			t.back.Visible = on
			t.button.TextColor3 = if on then C.text else C.dim
			t.chip.BackgroundColor3 = if on then C.on else C.chip
		end
		ui.tab = name
		if name == "STATS" and ui.askStats then
			ui.askStats()
		end
	end
	for i, name in TABS do
		-- The chosen tab's card sits behind its button: a button's own UIStroke is its
		-- text outline, so the ink edge lives on this frame instead.
		local back = Instance.new("Frame")
		back.Name = name .. "Back"
		back.Position = UDim2.fromOffset(12, 70 + (i - 1) * 56)
		back.Size = UDim2.new(1, -24, 0, 48)
		back.BackgroundColor3 = C.card
		back.BorderSizePixel = 0
		back.ZIndex = 12
		back.Visible = false
		back.Parent = rail
		corner(back, UDim.new(0, 12))
		inkEdge(back)

		local tabButton = UIKit.button(rail, {
			name = name,
			position = UDim2.fromOffset(12, 70 + (i - 1) * 56),
			size = UDim2.new(1, -24, 0, 48),
			text = TAB_LABEL[name],
			font = FONT,
			textSize = SIZE.tab,
			color = C.dim,
			fillTransparency = 1,
			cornerRadius = UDim.new(0, 12),
			zIndex = 13,
		})
		tabButton.TextXAlignment = Enum.TextXAlignment.Left
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 48)
		pad.Parent = tabButton

		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.AnchorPoint = Vector2.new(0, 0.5)
		chip.Position = UDim2.new(0, -38, 0.5, 0) -- back out of the padding
		chip.Size = UDim2.fromOffset(30, 30)
		chip.BackgroundColor3 = C.chip
		chip.BorderSizePixel = 0
		chip.ZIndex = 14
		chip.Parent = tabButton
		corner(chip, UDim.new(0, 8))
		tabIcon(chip, name)

		tabButton.MouseButton1Click:Connect(function()
			choose(name)
		end)
		tabs[name] = { button = tabButton, back = back, chip = chip }

		-- The page: its heading, then its rows in a scroller.
		local page = Instance.new("Frame")
		page.Name = name
		page.Position = UDim2.fromOffset(PAGE_X, PAGE_TOP)
		page.Size = UDim2.new(1, -(PAGE_X + PAGE_RIGHT), 1, -(PAGE_TOP + 12))
		page.BackgroundTransparency = 1
		page.ZIndex = 11
		page.Visible = false
		page.Parent = panel
		pages[name] = page

		UIKit.label(page, {
			name = "Heading",
			size = UDim2.new(1, -56, 0, 32),
			font = FONT,
			textSize = SIZE.page,
			color = C.text,
			text = TAB_LABEL[name],
			zIndex = 12,
		})
		UIKit.label(page, {
			name = "Subtitle",
			position = UDim2.fromOffset(0, 34),
			size = UDim2.new(1, -56, 0, 18),
			font = FONT,
			textSize = SIZE.hint,
			color = C.dim,
			text = TAB_SUB[name],
			zIndex = 12,
		})

		local scroller = Instance.new("ScrollingFrame")
		scroller.Name = "Rows"
		scroller.Position = UDim2.fromOffset(0, HEADER_H)
		scroller.Size = UDim2.new(1, 0, 1, -HEADER_H)
		scroller.BackgroundTransparency = 1
		scroller.BorderSizePixel = 0
		scroller.CanvasSize = UDim2.new()
		scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroller.ScrollingDirection = Enum.ScrollingDirection.Y
		scroller.ScrollBarThickness = 6
		scroller.ScrollBarImageColor3 = C.on
		scroller.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
		scroller.ZIndex = 11
		scroller.Parent = page
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = scroller
		scrollers[name] = scroller
		table.insert(ui.scrollers, scroller)
	end

	-- Rows stack down a page's scroller in build order, a thin line under each but the
	-- last; returns the row frame.
	local lastRow: { [string]: Frame } = {}
	local function row(tab: string, name: string, height: number?): Frame
		local scroller = scrollers[tab]
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.new(1, 0, 0, height or ROW_H)
		frame.BackgroundTransparency = 1
		frame.LayoutOrder = #scroller:GetChildren()
		frame.ZIndex = 11
		frame.Parent = scroller

		local line = Instance.new("Frame")
		line.Name = "Line"
		line.AnchorPoint = Vector2.new(0, 1)
		line.Position = UDim2.fromScale(0, 1)
		line.Size = UDim2.new(1, 0, 0, 2)
		line.BackgroundColor3 = C.divider
		line.BorderSizePixel = 0
		line.ZIndex = 11
		line.Parent = frame

		lastRow[tab] = frame
		return frame
	end

	-- GENERAL
	buildColourRow(row("GENERAL", "BaseColour", COLOUR_H))
	choiceRow(row("GENERAL", "RareDrops"), "rareDrops", "Rare drops", "Which drop alerts you see", {
		{ "all", "All" },
		{ "mine", "Mine" },
		{ "off", "Off" },
	})
	flagRow(row("GENERAL", "ConfirmDrop"), "confirmDrop", "Confirm rare drops", "Ask before bombing a Rare+ nuke")

	-- GRAPHICS
	choiceRow(row("GRAPHICS", "Graphics"), "graphics", "Graphics", "Low helps slower devices. Also sets radiation effects: less on Low and Med, full on High", {
		{ "low", "Low" },
		{ "med", "Med" },
		{ "high", "High" },
	})
	flagRow(row("GRAPHICS", "Shake"), "shake", "Screen shake", "Blasts and radiation wobble")
	flagRow(row("GRAPHICS", "Flashing"), "reduceFlashing", "Reduce flashing", "Dims screen flashes, slows rainbows")
	flagRow(row("GRAPHICS", "Auras"), "auras", "Show auras", "The auras around you and other players")
	flagRow(row("GRAPHICS", "FastMode"), "fastMode", "Fast mode", "Hides other bases' nukes and stops their effects")
	flagRow(row("GRAPHICS", "SuperFast"), "superFast", "Super fast mode", "Also hides your own nukes (names stay). Needs Fast mode on")

	-- AUDIO: the mute first (it predates the sliders), then the sliders.
	buildSoundRow(row("AUDIO", "Sound"))
	volumeRow(row("AUDIO", "Master", SLIDER_H), "volMaster", "Master")
	volumeRow(row("AUDIO", "Effects", SLIDER_H), "volSfx", "Effects")
	volumeRow(row("AUDIO", "Interface", SLIDER_H), "volUi", "Interface")
	volumeRow(row("AUDIO", "Geiger", SLIDER_H), "volGeiger", "Geiger")
	volumeRow(row("AUDIO", "Music", SLIDER_H), "musicLevel", "Music")

	-- STATS: read only. A heading has no line of its own; the one under the row before
	-- it marks the break.
	for _, def in STATS do
		if def.group then
			local heading = row("STATS", "Group_" .. def.group, GROUP_H)
			heading.Line.Visible = false
			groupRow(heading, def.group)
		else
			statRow(row("STATS", "Stat_" .. (def.key :: string), if def.hint then ROW_H - 4 else STAT_H), def)
		end
	end

	for _, frame in lastRow do
		frame.Line.Visible = false
	end

	choose("GENERAL")

	local function toggle()
		panel.Visible = not panel.Visible
		if panel.Visible and ui.tab == "STATS" and ui.askStats then
			ui.askStats()
		end
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
	-- And for SOUND EFFECTS (SfxService). SfxController applies the mute off the same echo.
	Net.get("SfxMuted").OnClientEvent:Connect(onServerSfxMuted)
	-- Ask rather than wait: SfxController connected first and took the queued load echo.
	Net.get("SfxMuted"):FireServer(nil)

	-- STATS: asked on open (choose / toggle call askStats), then kept fresh while it shows.
	local statsRemote = Net.get("PlayerStats")
	statsRemote.OnClientEvent:Connect(onServerStats)
	ui.askStats = function()
		statsRemote:FireServer()
	end
	task.spawn(function()
		while true do
			task.wait(STATS_REFRESH)
			if ui.panel.Visible and ui.tab == "STATS" then
				ui.askStats()
			end
		end
	end)
end

return Settings
