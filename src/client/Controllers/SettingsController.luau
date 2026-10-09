--[[
	SettingsController.lua — the player Settings panel: a wide panel with a tab rail
	down the left (Settings / Stats) and the chosen page on the right.

	  SETTINGS  every setting on one page (on request, 2026-10-08): rare drop alerts,
	            graphics level (also the radiation effects), screen shake, reduce
	            flashing, show auras, hide others' nukes, hide your nukes, then the
	            music and sound effects sliders
	  STATS     your lifetime numbers, read only: playtime, nukes dug, cash earned, kills...

	Base colour and Confirm rare drops are gone from here (on request, 2026-10-08).
	A plot just wears its default accent; the server's Net.PlotColor path is untouched.
	confirmDrop is still a pref, set by the drop popup's own "Don't show again".

	THE LOOK (on request, mockup "2 Sidebar"): House slate, ink outlines, rows split by
	thin lines rather than boxed, pill switches for flags, a segmented picker for
	choices. Landscape (720x470) so it fits short phone screens; each page scrolls if
	it outgrows the panel. No green on the chrome (#651 still holds) — "on" is steel.

	EVERY ROW IS A PREF (Config/Prefs, client/Prefs). The rows here only show and set
	them; each one is applied by the file that owns the effect (ItemFxController,
	RadFx, DetonationController, Sfx...), off Prefs.observe, so it holds even if this
	panel never builds. Prefs apply the same frame and save behind.

	SHAPE MIRRORS IndexController: a ScreenGui with a corner button and a centred
	`UIKit.panel` that toggles. `start()` only — nothing to build in `init()`.
	Instance names tests drive: Panel.Tabs.<SETTINGS|STATS> (the rail's buttons) and
	Panel.<SETTINGS|STATS> (the pages).

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
local Studded = require(script.Parent.Parent.Studded)
local Prefs = require(script.Parent.Parent.Prefs)
local Rarity = require(Shared.Config.Rarity)
local Mastery = require(Shared.Mastery)

local Settings = {}

-- THE PANEL'S PALETTE: UIKit.House's slate and ink, plus a steel blue for whatever is
-- on (the chosen tab, an On switch, the chosen option, a slider's fill). No green.
local House = UIKit.House
local C = {
	-- The Shop's studded grey (2026-10-08): the darker House.panel hid the studs.
	panel = Studded.DARK,
	tabs = Color3.fromHex("1E2126"), -- the tab rail
	rail = Color3.fromHex("15181C"), -- the wells behind switches/sliders
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
-- The studded backdrop (on request, 2026-10-08): the Shop's dark-panel studs, smaller.
local STUD_TILE = 16
local RAIL_W = 190
-- The page column: inset from the rail's divider and the panel's right edge.
local PAGE_X = RAIL_W + 3 + 24
local PAGE_RIGHT = 24
local PAGE_TOP = 20
local HEADER_H = 44 -- the page's title, above its scrolling rows
local ROW_H = 52
local SLIDER_H = 56
local STAT_H = 48
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
	hint = 14, -- small dim text: the colour row's status, Stats group headings
}
-- A flag's pill switch, and one option of a segmented picker.
local PILL_W, PILL_H, KNOB = 64, 34, 24
local OPTION_W, OPTION_H = 64, 30
-- Settings' REDUCE FLASHING slows the Anomaly colour cycle by this much (every reader
-- takes Rarity.ANOMALY_CYCLE fresh each frame).
local ANOMALY_SLOW = 4

local ui = {
	-- Every page's ScrollingFrame: a drag on a slider locks them so a
	-- touch drag moves the handle, not the page.
	scrollers = {} :: { ScrollingFrame },
	-- Stats key -> its row's value label.
	statValues = {} :: { [string]: TextLabel },
}

-- ── Scroll lock ─────────────────────────────────────────────────────

local function lockScroll(locked: boolean)
	for _, scroller in ui.scrollers do
		scroller.ScrollingEnabled = not locked
	end
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

--- A row's title on the left, leaving `rightW` for its control. Centred in the row
--- unless `top` pins it that far down (the colour row, whose swatches sit under it).
local function rowText(row: Instance, title: string, rightW: number, top: number?)
	UIKit.label(row, {
		name = "SectionTitle",
		anchorPoint = if top then Vector2.zero else Vector2.new(0, 0.5),
		position = if top then UDim2.fromOffset(0, top) else UDim2.fromScale(0, 0.5),
		size = UDim2.new(1, -rightW - 14, 0, 24),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = title,
		zIndex = 12,
	})
end

-- ── Pref rows ───────────────────────────────────────────────────────

--- A pill switch for a flag pref.
local function flagRow(row: Instance, key: string, title: string)
	rowText(row, title, PILL_W)
	local button, paint = pillSwitch(row, "Switch")
	button.MouseButton1Click:Connect(function()
		Prefs.set(key, not Prefs.get(key))
	end)
	Prefs.observe(key, function(on)
		paint(on == true)
	end)
end

--- A segmented picker: one well, one button per option, the chosen one lit.
local function choiceRow(row: Instance, key: string, title: string, options: { { string } })
	local pad = 3
	local width = #options * OPTION_W + (#options - 1) * pad + pad * 2
	rowText(row, title, width)

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
	local labelW, valueW = 160, 56

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
-- by Net.PlayerStats' fields. `format` says how the number reads (plain numbers get commas).
type StatDef = { key: string?, group: string?, title: string?, format: ((number) -> string)? }
local STATS: { StatDef } = {
	{ group = "Overall" },
	{ key = "playtime", title = "Playtime", format = duration },
	{
		key = "cashEarned",
		title = "Cash earned",
		format = function(n)
			return "$" .. Mastery.short(n)
		end,
	},
	{ key = "index", title = "Index found" },
	{ key = "deepestStage", title = "Deepest stage" },
	{ group = "Digging" },
	{ key = "dug", title = "Nukes dug up" },
	{ key = "rareFinds", title = "Rare finds" },
	{ key = "itemsCleaned", title = "Nukes cleaned" },
	{ key = "cratesOpened", title = "Crates opened" },
	{ group = "Combat" },
	{ key = "bombsDropped", title = "Nukes bombed" },
	{ key = "kills", title = "Players knocked out" },
	{ key = "bagsStolen", title = "Bags stolen" },
	{ key = "deaths", title = "Deaths" },
	{ group = "Crafting" },
	{ key = "merges", title = "Merges" },
	{ key = "rolls", title = "Fluids brewed" },
}

--- One stat: title on the left, the number on the right.
local function statRow(row: Instance, def: StatDef)
	local key = def.key :: string
	local valueW = 200
	UIKit.label(row, {
		name = "SectionTitle",
		anchorPoint = Vector2.new(0, 0.5),
		position = UDim2.fromScale(0, 0.5),
		size = UDim2.new(1, -valueW - 14, 0, 24),
		font = FONT,
		textSize = SIZE.row,
		color = C.text,
		text = def.title or "",
		zIndex = 12,
	})
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
		elseif def.format then
			label.Text = def.format(num(key))
		else
			label.Text = commas(num(key))
		end
	end
end

-- ── Build ───────────────────────────────────────────────────────────

-- A tab's icon, drawn from frames so it needs no upload: the gear art for Settings, a
-- bar chart for Stats.
local function tabIcon(chip: Frame, tab: string)
	if tab == "SETTINGS" then
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
	local function bar(x: number, y: number, w: number, h: number)
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(w, h)
		f.BackgroundColor3 = C.text
		f.BorderSizePixel = 0
		f.ZIndex = 15
		f.Parent = chip
	end
	-- STATS: a rising bar chart on a baseline.
	bar(7, 17, 4, 6)
	bar(13, 12, 4, 11)
	bar(19, 7, 4, 16)
	bar(5, 23, 20, 2)
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

	local function studs(frame: GuiObject, z: number)
		Studded.pattern(frame, {
			radius = UIKit.Radius.panel.Offset,
			tile = STUD_TILE,
			bands = { 0.15, 0.42, 0.52, 0.58 },
			bandTransparency = 0.93,
			studTransparency = 0.1,
			glow = false,
			zIndex = z,
		})
	end
	studs(panel, 10)

	-- THE RAIL: rounded on the panel's left corners, squared where it meets the page,
	-- with an ink line between the two.
	local rail = Instance.new("Frame")
	rail.Name = "Tabs"
	rail.Size = UDim2.new(0, RAIL_W, 1, 0)
	rail.BackgroundColor3 = C.tabs
	rail.BorderSizePixel = 0
	rail.ZIndex = 11
	rail.Parent = panel
	corner(rail, UIKit.Radius.panel)
	local square = Instance.new("Frame")
	square.Name = "Square"
	square.AnchorPoint = Vector2.new(1, 0)
	square.Position = UDim2.fromScale(1, 0)
	square.Size = UDim2.new(0, 24, 1, 0)
	square.BackgroundColor3 = C.tabs
	square.BorderSizePixel = 0
	square.ZIndex = 10 -- under the rail's studs
	square.Parent = rail
	studs(rail, 11)
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

	local close = UIKit.closeButton(panel, {
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -16, 0, 16),
		size = 40,
		zIndex = 14,
	})

	local TABS = { "SETTINGS", "STATS" }
	local TAB_LABEL = { SETTINGS = "Settings", STATS = "Stats" }
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

	-- SETTINGS: every setting on one page (on request, 2026-10-08).
	choiceRow(row("SETTINGS", "RareDrops"), "rareDrops", "Rare drops", {
		{ "all", "All" },
		{ "mine", "Mine" },
		{ "off", "Off" },
	})
	choiceRow(row("SETTINGS", "Graphics"), "graphics", "Graphics", {
		{ "low", "Low" },
		{ "med", "Med" },
		{ "high", "High" },
	})
	flagRow(row("SETTINGS", "Shake"), "shake", "Screen shake")
	flagRow(row("SETTINGS", "Flashing"), "reduceFlashing", "Reduce flashing")
	flagRow(row("SETTINGS", "Auras"), "auras", "Show auras")
	flagRow(row("SETTINGS", "FastMode"), "fastMode", "Hide others' nukes")
	flagRow(row("SETTINGS", "SuperFast"), "superFast", "Hide your nukes")
	volumeRow(row("SETTINGS", "Music", SLIDER_H), "musicLevel", "Music")
	volumeRow(row("SETTINGS", "Effects", SLIDER_H), "volSfx", "Sound effects")

	-- STATS: read only. A heading has no line of its own; the one under the row before
	-- it marks the break.
	for _, def in STATS do
		if def.group then
			local heading = row("STATS", "Group_" .. def.group, GROUP_H)
			heading.Line.Visible = false
			groupRow(heading, def.group)
		else
			statRow(row("STATS", "Stat_" .. (def.key :: string), STAT_H), def)
		end
	end

	for _, frame in lastRow do
		frame.Line.Visible = false
	end

	choose("SETTINGS")

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

	-- REDUCE FLASHING's slower Anomaly cycle. Here, not in Prefs, because it is a
	-- shared Config value every Anomaly reader picks up on its own next frame.
	local anomalyCycle = Rarity.ANOMALY_CYCLE
	Prefs.observe("reduceFlashing", function(on)
		Rarity.ANOMALY_CYCLE = if on then anomalyCycle * ANOMALY_SLOW else anomalyCycle
	end)

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
