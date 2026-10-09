--[[
	PotionController — the Potions tile (bottom left of the left-edge grid), the panel
	it opens, the running-potion chips beside it, and the card that pops up when a
	Potion Crate is opened (Config/Potions, Services/PotionService).

	IT DECIDES NOTHING. The stash comes from the server on the Potions remote; the
	clocks are the Player attributes PotionService publishes (Potions.attrFor). DRINK
	just asks.

	THE CHIPS run leftward along the corner row, one per running potion, soonest to
	run out nearest the tile: the potion's picture with its time left under it. The
	last 30 seconds pulse. Clicking one opens the panel.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Potions = require(Shared.Config.Potions)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Studded = require(script.Parent.Parent.Studded)
local HudTile = require(script.Parent.Parent.HudTile)
local TutorialGate = require(script.Parent.Parent.TutorialGate)
local Sfx = require(script.Parent.Parent.Sfx)

local PotionController = {}

-- The Potions tile: under Nukes in the right-edge column (HudTile, Dock.rightTileCentre),
-- picture only (2026-10-07, on request; it was in the left grid). Its running-potion chips
-- stay in the top-right corner row, after Daily (1), Masteries (2) and Info (3): from 4 on.
local TILE_RIGHT = 2
local CHIP_AFTER = 3
local TILE_COLOR = Color3.fromRGB(168, 75, 240)
local TILE_LIGHT = Color3.fromRGB(227, 166, 255)

local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	card = Color3.fromHex("252A30"),
	off = Color3.fromHex("3A4047"),
	dim = Color3.fromHex("9AA3AD"),
	close = Color3.fromHex("E5484D"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	drink = Color3.fromRGB(62, 190, 90),
	warn = Color3.fromHex("C23B9A"),
	font = Enum.Font.GothamBlack,
}

local PAD = 20
local HEADER_H = 74
local ROW_H = 78
local ROW_GAP = 10
local ICON = 66
local BUTTON_W = 120
local PANEL_W = 560
local PANEL_H = PAD * 2 + HEADER_H + #Potions.ORDER * ROW_H + (#Potions.ORDER - 1) * ROW_GAP
local PANEL_LIFT = 20
local CHIP = 38 -- one corner tile wide (Dock.CORNER_TILE_SIZE), so the chips step along the row
local WARN_SECONDS = 30

local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local REVEAL_HOLD = 3.5

type Row = {
	count: TextLabel,
	time: TextLabel,
	button: TextButton,
	scale: UIScale,
}

type Chip = {
	frame: TextButton,
	time: TextLabel,
	pill: Frame,
}

local remote: any = nil
local stash: { [string]: number } = {}
local rows: { [string]: Row } = {}
local chips: { [string]: Chip } = {}
local panelFrame: Frame? = nil
local panelScale: UIScale? = nil
local statusLabel: TextLabel? = nil
local tileBadge: Frame? = nil
local tileMark: TextLabel? = nil
-- Potions gained since the panel was last opened; the tile badge shows this, not the stash.
local unseen = 0
local lastTotal: number? = nil
local reveal: { frame: Frame, scale: UIScale, image: ImageLabel, name: TextLabel, blurb: TextLabel }? = nil
local revealToken = 0

-- ── Little builders ─────────────────────────────────────────────────

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

--- A label in the panels' voice: GothamBlack, white, ink-outlined. `props` set as-is.
local function inked(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = PANEL.font
	label.TextColor3 = PANEL.white
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(label :: any)[key] = value
	end
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = PANEL.ink
	stroke.Thickness = math.max(1.5, label.TextSize * 0.09)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function picture(parent: Instance, image: string, size: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Image = image
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = UDim2.fromOffset(size, size)
	img.Parent = parent
	return img
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

--- Seconds this potion has left, from the attribute PotionService publishes.
local function leftOf(id: string): number
	local value = Players.LocalPlayer:GetAttribute(Potions.attrFor(id))
	return if type(value) == "number" then math.max(0, value - now()) else 0
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

-- ── The panel ───────────────────────────────────────────────────────

local function paint()
	for _, id in Potions.ORDER do
		local have = stash[id] or 0
		local row = rows[id]
		if row then
			row.count.Text = `x{have}`
			row.count.TextColor3 = if have > 0 then PANEL.white else PANEL.dim
			local left = leftOf(id)
			row.time.Text = if left > 0 then `ACTIVE  {clock(left)}` else ""
			local can = have > 0
			row.button.Active = can
			row.button.AutoButtonColor = can
			row.button.BackgroundColor3 = if can then PANEL.drink else PANEL.off
			row.button.Text = if left > 0 and can then "+10 MIN" else "DRINK"
		end
	end
	-- Looking at the panel counts as seeing everything in it.
	if panelFrame and panelFrame.Visible then
		unseen = 0
	end
	if tileBadge and tileMark then
		tileBadge.Visible = unseen > 0
		tileMark.Text = tostring(unseen)
	end
end

function PotionController.open()
	local panel = panelFrame
	if panel == nil or panel.Visible or HudTile.blocked("Potions") then
		return
	end
	panel.Visible = true
	if statusLabel then
		statusLabel.Text = ""
	end
	paint()
	if panelScale then
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, OPEN, { Scale = 1 }):Play()
	end
end

function PotionController.close()
	if panelFrame then
		panelFrame.Visible = false
	end
end

function PotionController.toggle()
	if panelFrame and panelFrame.Visible then
		PotionController.close()
	else
		PotionController.open()
	end
end

local function buildRow(panel: Frame, index: number, id: string)
	local def = Potions.get(id)
	local colour = Color3.fromHex(def.color)
	local top = PAD + HEADER_H + (index - 1) * (ROW_H + ROW_GAP)

	local card = Instance.new("Frame")
	card.Name = `Row_{id}`
	card.Size = UDim2.new(1, -PAD * 2, 0, ROW_H)
	card.Position = UDim2.fromOffset(PAD, top)
	card.BackgroundColor3 = PANEL.card
	card.BorderSizePixel = 0
	card.ZIndex = 11
	card.Parent = panel
	round(card, 8)
	edge(card, colour, 2.5)
	local scale = Instance.new("UIScale")
	scale.Parent = card

	local img = picture(card, def.image, ICON)
	img.AnchorPoint = Vector2.new(0, 0.5)
	img.Position = UDim2.new(0, 8, 0.5, 0)
	img.ZIndex = 12

	inked(card, {
		Name = "Name",
		Text = def.name,
		TextSize = 22,
		TextColor3 = colour,
		Size = UDim2.new(1, -(ICON + 24 + BUTTON_W + 70), 0, 28),
		Position = UDim2.fromOffset(ICON + 18, 10),
		ZIndex = 12,
	})
	inked(card, {
		Name = "Blurb",
		Text = def.blurb,
		TextSize = 14,
		TextColor3 = PANEL.dim,
		TextWrapped = true,
		Size = UDim2.new(1, -(ICON + 24 + BUTTON_W + 70), 0, 18),
		Position = UDim2.fromOffset(ICON + 18, 38),
		ZIndex = 12,
	})
	local time = inked(card, {
		Name = "Time",
		Text = "",
		Font = UIKit.House.font,
		TextSize = 15,
		TextColor3 = colour,
		Size = UDim2.new(1, -(ICON + 24 + BUTTON_W + 70), 0, 16),
		Position = UDim2.fromOffset(ICON + 18, 56),
		ZIndex = 12,
	})
	time.UIStroke.Thickness = 1 -- as on the chips: keeps Gotham Black's colon readable
	local count = inked(card, {
		Name = "Count",
		Text = "x0",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Size = UDim2.fromOffset(60, 30),
		Position = UDim2.new(1, -(BUTTON_W + 20), 0.5, 0),
		ZIndex = 12,
	})

	local button = Instance.new("TextButton")
	button.Name = "Drink"
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(BUTTON_W, 46)
	button.BackgroundColor3 = PANEL.off
	button.Font = PANEL.font
	button.TextSize = 18
	button.TextColor3 = PANEL.white
	button.Text = "DRINK"
	button.ZIndex = 12
	button.Parent = card
	round(button, 6)
	edge(button, PANEL.ink, 3)
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = PANEL.ink
	textStroke.Thickness = 2
	textStroke.Parent = button
	button.Activated:Connect(function()
		if button.Active and (stash[id] or 0) > 0 then
			Sfx.play("pour")
			remote:FireServer("drink", id)
		end
	end)

	rows[id] = { count = count, time = time, button = button, scale = scale }
end

local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "PotionsPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.Position = UDim2.new(0.5, 0, 0.5, -PANEL_LIFT)
	panel.BackgroundColor3 = PANEL.panel
	panel.BorderSizePixel = 0
	panel.ZIndex = 10
	panel.Visible = false
	panel.Parent = canvas
	round(panel, 8)
	edge(panel, PANEL.ink, 4)
	Studded.darkPanel(panel, 8) -- the Shop's dark grey studded backdrop
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	inked(panel, {
		Name = "Title",
		Text = "Potions",
		TextSize = 38,
		Size = UDim2.fromOffset(300, 46),
		Position = UDim2.fromOffset(PAD, PAD - 6),
		ZIndex = 11,
	})
	statusLabel = inked(panel, {
		Name = "Subtitle",
		Text = "",
		TextSize = 14,
		TextColor3 = PANEL.dim,
		Size = UDim2.new(1, -PAD * 2 - 50, 0, 18),
		Position = UDim2.fromOffset(PAD + 2, PAD + 40),
		ZIndex = 11,
	})
	local hint = inked(panel, {
		Name = "Hint",
		Text = "Find Potion Crates on any stage. Each potion lasts 10 minutes.",
		TextSize = 14,
		TextColor3 = PANEL.dim,
		Size = UDim2.new(1, -PAD * 2 - 50, 0, 18),
		Position = UDim2.fromOffset(PAD + 2, PAD + 40),
		ZIndex = 11,
	})
	-- The refusal line shares the hint's spot and hides it while it shows.
	statusLabel:GetPropertyChangedSignal("Text"):Connect(function()
		hint.Visible = (statusLabel :: TextLabel).Text == ""
	end)

	local close = UIKit.closeButton(panel, {
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -PAD, 0, PAD - 4),
		size = 40,
		zIndex = 11,
	})
	close.Activated:Connect(PotionController.close)

	for index, id in Potions.ORDER do
		buildRow(panel, index, id)
	end

	panelFrame = panel
	panelScale = scale
	return gui
end

-- ── The running chips ───────────────────────────────────────────────

local function buildChip(canvas: Frame, id: string): Chip
	local def = Potions.get(id)
	local colour = Color3.fromHex(def.color)

	local frame = Instance.new("TextButton")
	frame.Name = `Potion_{id}`
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(CHIP, CHIP)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.ZIndex = 4
	frame.Parent = canvas
	frame.Activated:Connect(PotionController.open)

	local img = picture(frame, def.image, CHIP)
	img.ZIndex = 5

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 1, -6)
	pill.Size = UDim2.fromOffset(CHIP + 8, 18)
	pill.BackgroundColor3 = colour:Lerp(Color3.new(0, 0, 0), 0.35)
	pill.BorderSizePixel = 0
	pill.ZIndex = 6
	pill.Parent = frame
	round(pill, 9)
	edge(pill, PANEL.ink, 2)

	local time = inked(pill, {
		Name = "Time",
		Text = "",
		Font = UIKit.House.font,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
	})
	-- A 1px edge: at 1.5 Gotham Black's colon vanishes under the outline at this size.
	time.UIStroke.Thickness = 1
	return { frame = frame, time = time, pill = pill }
end

local function paintChips()
	local running = {}
	for _, id in Potions.ORDER do
		local left = leftOf(id)
		if left > 0 then
			table.insert(running, { id = id, left = left })
		end
	end
	table.sort(running, function(a, b)
		return a.left < b.left
	end)
	local shown: { [string]: boolean } = {}
	for index, entry in running do
		local chip = chips[entry.id]
		if chip then
			shown[entry.id] = true
			chip.frame.Visible = true
			chip.frame.Position = UIKit.Dock.cornerButtonCentre(CHIP_AFTER + index) + UDim2.fromOffset(0, -4)
			chip.time.Text = clock(entry.left)
			local warn = entry.left <= WARN_SECONDS
			chip.pill.BackgroundColor3 = if warn
				then PANEL.warn
				else Color3.fromHex(Potions.get(entry.id).color):Lerp(Color3.new(0, 0, 0), 0.35)
			chip.frame.Rotation = if warn then math.sin(os.clock() * 10) * 6 else 0
		end
	end
	for id, chip in chips do
		if not shown[id] then
			chip.frame.Visible = false
		end
	end
end

local function buildChips(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "PotionChips"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 55
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Hidden until the tutorial is over, with the corner row they sit in.
	TutorialGate.bind(gui)
	local canvas = UIKit.canvas(gui)
	for _, id in Potions.ORDER do
		chips[id] = buildChip(canvas, id)
	end
	return gui
end

-- ── The crate reveal ────────────────────────────────────────────────

local function buildReveal(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "PotionReveal"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 120
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local frame = Instance.new("Frame")
	frame.Name = "Card"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.42)
	frame.Size = UDim2.fromOffset(340, 300)
	frame.BackgroundColor3 = PANEL.panel
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 20
	frame.Parent = canvas
	round(frame, 10)
	local stroke = edge(frame, PANEL.ink, 4)
	stroke.Name = "Edge"
	local scale = Instance.new("UIScale")
	scale.Parent = frame

	inked(frame, {
		Name = "Title",
		Text = "POTION CRATE",
		TextSize = 18,
		TextColor3 = PANEL.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 12),
		ZIndex = 21,
	})
	local image = picture(frame, "", 150)
	image.AnchorPoint = Vector2.new(0.5, 0)
	image.Position = UDim2.new(0.5, 0, 0, 38)
	image.ZIndex = 21
	local name = inked(frame, {
		Name = "Name",
		Text = "",
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 192),
		ZIndex = 21,
	})
	local blurb = inked(frame, {
		Name = "Blurb",
		Text = "",
		TextSize = 15,
		TextColor3 = PANEL.white,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 228),
		ZIndex = 21,
	})
	inked(frame, {
		Name = "Hint",
		Text = "Added to your Potions. Drink it from the potion tile.",
		TextSize = 12,
		TextColor3 = PANEL.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Size = UDim2.new(1, -24, 0, 32),
		Position = UDim2.fromOffset(12, 254),
		ZIndex = 21,
	})

	reveal = { frame = frame, scale = scale, image = image, name = name, blurb = blurb }
	return gui
end

local function showReveal(id: string)
	local r = reveal
	if r == nil or not Potions.has(id) then
		return
	end
	local def = Potions.get(id)
	local colour = Color3.fromHex(def.color)
	r.image.Image = def.image
	r.name.Text = def.name
	r.name.TextColor3 = colour
	r.blurb.Text = def.blurb
	local stroke = r.frame:FindFirstChild("Edge") :: UIStroke?
	if stroke then
		stroke.Color = colour
	end
	r.frame.Visible = true
	r.scale.Scale = 0.4
	TweenService:Create(r.scale, POP, { Scale = 1 }):Play()
	Sfx.play("mastery")

	revealToken += 1
	local token = revealToken
	task.delay(REVEAL_HOLD, function()
		if token ~= revealToken then
			return
		end
		local out = TweenService:Create(r.scale, FADE, { Scale = 0 })
		out:Play()
		out.Completed:Wait()
		if token == revealToken then
			r.frame.Visible = false
		end
	end)
end

-- ── Wiring ──────────────────────────────────────────────────────────

local function onState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.stash) == "table" then
		for _, id in Potions.ORDER do
			stash[id] = tonumber(payload.stash[id]) or 0
		end
		-- Only new potions light the badge; drinking one never does. The first state
		-- (on join) counts the whole stash so it's flagged once until opened.
		local total = 0
		for _, id in Potions.ORDER do
			total += stash[id] or 0
		end
		local gained = total - (lastTotal or 0)
		if gained > 0 then
			unseen += gained
		end
		lastTotal = total
	end
	if statusLabel then
		statusLabel.Text = if type(payload.notice) == "string" then payload.notice else ""
	end
	if type(payload.got) == "string" then
		showReveal(payload.got)
	end
	if type(payload.drank) == "string" then
		local row = rows[payload.drank]
		if row then
			row.scale.Scale = 1.06
			TweenService:Create(row.scale, OPEN, { Scale = 1 }):Play()
		end
	end
	paint()
	paintChips()
end

function PotionController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local tileGui, button = HudTile.build({
		name = "PotionsButton",
		caption = "Potions",
		slot = 0,
		right = TILE_RIGHT,
		color = TILE_COLOR,
		light = TILE_LIGHT,
		image = Potions.TILE_IMAGE,
		onActivated = PotionController.toggle,
	})
	tileBadge, tileMark = HudTile.badge(button, PANEL.close, PANEL.ink)
	tileGui.Parent = playerGui
	buildPanel().Parent = playerGui
	buildChips().Parent = playerGui
	buildReveal().Parent = playerGui
	HudTile.registerPanel("Potions", panelFrame :: Frame)

	remote = Net.get("Potions")
	remote.OnClientEvent:Connect(onState)
	remote:FireServer("ask")

	for _, id in Potions.ORDER do
		Players.LocalPlayer:GetAttributeChangedSignal(Potions.attrFor(id)):Connect(function()
			paint()
			paintChips()
		end)
	end

	-- The countdowns, four times a second (the last 30 seconds wobble).
	task.spawn(function()
		while true do
			task.wait(0.25)
			paintChips()
			if panelFrame and panelFrame.Visible then
				paint()
			end
		end
	end)
end

return PotionController
