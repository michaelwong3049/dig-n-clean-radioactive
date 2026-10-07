--[[
	PlaytimeGiftController — the Free Gifts tile (left edge, stacked right above Masteries:
	the clock, with "Free Gifts" under it), the 12-gift
	panel it opens, and the CLAIM buttons. Reads PlaytimeGifts (Services/
	PlaytimeGiftService, Config/PlaytimeGifts).

	THE SERVER WORKS OUT EVERY NUMBER AND CHECKS EVERY CLAIM. It sends the session's
	`startedAt` and each gift as it stands for this player; the panel counts down against
	the server clock on its own and only asks to claim when a gift looks open. A card is
	CLAIMED (dimmed), READY (green CLAIM, gold edge) or a countdown to its minute.

	Leaving resets everything -- the clock is the session -- and the footer says so. The
	tile wears a number while gifts are waiting. Nothing pops up on its own.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Potions = require(Shared.Config.Potions)
local PlaytimeGifts = require(Shared.Config.PlaytimeGifts)

local UIKit = require(script.Parent.Parent.UIKit)
local Studded = require(script.Parent.Parent.Studded)
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)
local Sfx = require(script.Parent.Parent.Sfx)
local ShinyCard = require(script.Parent.Parent.ShinyCard)

local PlaytimeGiftController = {}

-- THE GIFTS TILE: bottom right of the left-edge grid (HudTile), beside Index.
local TILE_SLOT = 4
local TILE_COLOR = Color3.fromRGB(255, 150, 40)
local TILE_LIGHT = Color3.fromRGB(255, 214, 150)

local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	-- One colour per row of the panel, so the ladder reads as three tiers: a warm orange,
	-- a light blue for the second, a gold for the last (which holds the shiny plate).
	-- Each is a top-lit gradient (top -> bottom) and a pale rim of the same hue.
	tier = {
		{ top = Color3.fromHex("FFB75E"), bottom = Color3.fromHex("F27A1A"), rim = Color3.fromHex("FFE1B4") },
		{ top = Color3.fromHex("A4DEFF"), bottom = Color3.fromHex("4DA6EE"), rim = Color3.fromHex("E8F7FF") },
		{ top = Color3.fromHex("FFE680"), bottom = Color3.fromHex("F4B21E"), rim = Color3.fromHex("FFF5C8") },
	},
	doneTop = Color3.fromHex("5A6068"),
	doneBottom = Color3.fromHex("383D43"),
	doneRim = Color3.fromHex("7A828B"),
	-- The timer pill: a pale track with a deeper fill that grows toward the gift opening.
	track = Color3.fromHex("8CC2FF"),
	fill = Color3.fromHex("2F7DEB"),
	cardDone = Color3.fromHex("3A3F45"),
	pillDone = Color3.fromHex("2A2E33"),
	claim = UIKit.House.buy,
	dim = Color3.fromHex("9AA3AD"),
	close = Color3.fromHex("E5484D"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	gold = Color3.fromRGB(255, 214, 80),
	cash = UIKit.House.cash,
	speed = Color3.fromRGB(150, 210, 255),
	boost = Color3.fromRGB(255, 240, 150),
	potion = Color3.fromRGB(255, 190, 255),
	crate = Color3.fromRGB(255, 220, 170),
	font = Enum.Font.GothamBlack,
}

local PAD = 16
local HEADER_H = 54
local FOOTER_H = 50
local CARD_W = 184
local CARD_H = 136
local CARD_GAP = 10
-- Inside a card: the picture on top, the timer pill on the bottom, and the gift's lines
-- centred in the strip between them (so a one-line gift has no hole under it).
local ICON = 46
local ICON_Y = 4
local PILL_H = 30
local PILL_INSET = 6
local LINE_ROWS = 3
local LINE_H = 16
local COLS = 4
local ROWS = 3
local PANEL_W = PAD * 2 + CARD_W * COLS + CARD_GAP * (COLS - 1)
local PANEL_H = PAD * 2 + HEADER_H + CARD_H * ROWS + CARD_GAP * (ROWS - 1) + FOOTER_H
local PANEL_LIFT = 20
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

type Card = {
	button: TextButton,
	icon: ImageLabel,
	sheen: UIGradient?,
	fill: Frame,
	pulse: Tween?,
	bob: Tween?,
	edge: UIStroke,
	lines: { TextLabel },
	pill: TextButton,
	pillLabel: TextLabel,
	scale: UIScale,
}

type State = {
	startedAt: number,
	gifts: { any },
	claimed: { [number]: boolean },
}

local cards: { Card } = {}
-- The stop functions of the ShinyCard effect on the big gift, by card index.
local shiny: { [number]: () -> () } = {}
local panelFrame: Frame? = nil
local panelScale: UIScale? = nil
local claimAllButton: TextButton? = nil
local badge: Frame? = nil
local badgeMark: TextLabel? = nil
local remote: any = nil
local state: State? = nil

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
	label.TextXAlignment = Enum.TextXAlignment.Center
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

--- Cash as a short tag: $50K, $3M, $1.2B.
local function shortMoney(amount: number): string
	for _, unit in { { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if amount >= unit[1] then
			local s = string.format("%.1f", amount / unit[1])
			s = (string.gsub(s, "%.0$", ""))
			return `${s}{unit[2]}`
		end
	end
	return `${math.floor(amount)}`
end

local function shortCount(amount: number): string
	return (string.gsub(shortMoney(amount), "%$", ""))
end

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
	end
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

local function elapsed(): number
	local s = state
	return if s then Workspace:GetServerTimeNow() - s.startedAt else 0
end

local function isReady(index: number): boolean
	local s = state
	if s == nil or s.claimed[index] then
		return false
	end
	local gift = s.gifts[index]
	return gift ~= nil and elapsed() >= gift.minutes * 60
end

local function readyCount(): number
	local s = state
	if s == nil then
		return 0
	end
	local count = 0
	for index in s.gifts do
		if isReady(index) then
			count += 1
		end
	end
	return count
end

--- What a gift holds, as up to four short coloured lines.
local function linesFor(gift: any): { { text: string, color: Color3 } }
	local out = {}
	local top = {}
	if gift.cash > 0 then
		table.insert(top, `${shortCount(gift.cash)}`)
	end
	if gift.speed > 0 then
		table.insert(top, `+{shortCount(gift.speed)} Speed`)
	end
	if #top > 0 then
		table.insert(out, { text = table.concat(top, "  "), color = if gift.cash > 0 then PANEL.cash else PANEL.speed })
	end
	-- Boosts: "2x Luck 5m", or "2x Luck & Cash 10m" when both run the same time.
	local luckMin = math.floor(gift.luckSeconds / 60)
	local cashMin = math.floor(gift.cashBoostSeconds / 60)
	if luckMin > 0 and luckMin == cashMin then
		table.insert(out, { text = `2x Luck & Cash {luckMin}m`, color = PANEL.boost })
	else
		local boosts = {}
		if luckMin > 0 then
			table.insert(boosts, `2x Luck {luckMin}m`)
		end
		if cashMin > 0 then
			table.insert(boosts, `2x Cash {cashMin}m`)
		end
		if #boosts > 0 then
			table.insert(out, { text = table.concat(boosts, " + "), color = PANEL.boost })
		end
	end
	-- Potions and crates share a line, so the biggest gift still fits in three.
	local items = {}
	local potionTotal, lastId = 0, nil
	local kinds = 0
	for _, potion in gift.potions do
		potionTotal += potion.count
		kinds += 1
		lastId = potion.id
	end
	if potionTotal > 0 then
		table.insert(
			items,
			if kinds == 1 and lastId and Potions.has(lastId)
				then (if potionTotal == 1
					then `{Potions.get(lastId).short} Potion`
					else `{potionTotal} {Potions.get(lastId).short} Potions`)
				else `{potionTotal} Potions`
		)
	end
	if gift.crates > 0 then
		table.insert(items, `{gift.crates} Crate{if gift.crates == 1 then "" else "s"}`)
	end
	if #items > 0 then
		table.insert(out, { text = table.concat(items, " + "), color = if potionTotal > 0 then PANEL.potion else PANEL.crate })
	end
	return out
end

-- ── The panel ───────────────────────────────────────────────────────

--- The colours of the row gift `index` sits in.
local function tierOf(index: number): { top: Color3, bottom: Color3, rim: Color3 }
	return PANEL.tier[math.clamp((index - 1) // COLS + 1, 1, #PANEL.tier)]
end

local function gradientOf(top: Color3, bottom: Color3): ColorSequence
	return ColorSequence.new(top, bottom)
end

local function buildCard(parent: Instance, index: number, position: Vector2): Card
	local button = Instance.new("TextButton")
	button.Name = `Gift{index}`
	button.AutoButtonColor = false
	button.Text = ""
	button.Size = UDim2.fromOffset(CARD_W, CARD_H)
	button.Position = UDim2.fromOffset(position.X, position.Y)
	button.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient below carries the colour
	button.BorderSizePixel = 0
	button.ZIndex = 11
	button.Parent = parent
	round(button, 14)
	local tier = tierOf(index)
	local cardEdge = edge(button, tier.rim, 3)
	-- The plate's colour is a top-lit gradient. Not on the big last plate: ShinyCard
	-- clears a card's gradients when it takes over (and has its own look).
	local giftDef = PlaytimeGifts.GIFTS[index]
	local sheen: UIGradient? = nil
	if not (giftDef and giftDef.big) then
		sheen = Instance.new("UIGradient")
		sheen.Rotation = 90
		sheen.Color = gradientOf(tier.top, tier.bottom)
		sheen.Parent = button
	else
		button.BackgroundColor3 = tier.bottom
	end
	-- The glossy L-stud pattern the pass cards wear, over the plate's colour.
	Studded.pattern(button, { radius = 14, tile = 20, zIndex = 11, bands = { 0.28, 0.5, 0.58, 0.64 }, glow = false })
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local icon = Instance.new("ImageLabel")
	icon.Name = "Gift"
	icon.BackgroundTransparency = 1
	icon.Image = Artwork.IMAGE.gift
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, ICON_Y)
	icon.Size = UDim2.fromOffset(ICON, ICON)
	icon.ZIndex = 12
	icon.Parent = button

	local textTop = ICON_Y + ICON
	local textBox = Instance.new("Frame")
	textBox.Name = "Lines"
	textBox.BackgroundTransparency = 1
	textBox.Position = UDim2.fromOffset(6, textTop)
	textBox.Size = UDim2.new(1, -12, 0, CARD_H - PILL_INSET - PILL_H - textTop)
	textBox.ZIndex = 12
	textBox.Parent = button
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = textBox

	local lines = {}
	for row = 1, LINE_ROWS do
		local label = inked(textBox, {
			Name = `Line{row}`,
			Text = "",
			TextSize = 15,
			TextScaled = true,
			LayoutOrder = row,
			Size = UDim2.new(1, 0, 0, LINE_H),
			ZIndex = 12,
		})
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 15
		cap.Parent = label
		lines[row] = label
	end

	local pill = Instance.new("TextButton")
	pill.Name = "Pill"
	pill.AutoButtonColor = false
	pill.Text = ""
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -PILL_INSET)
	pill.Size = UDim2.new(1, -2 * PILL_INSET, 0, PILL_H)
	pill.BackgroundColor3 = PANEL.track
	pill.BorderSizePixel = 0
	pill.ClipsDescendants = true
	pill.ZIndex = 12
	pill.Parent = button
	round(pill, 12)
	edge(pill, PANEL.ink, 2)
	-- The progress fill: how far the session clock has come toward this gift.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = PANEL.fill
	fill.BorderSizePixel = 0
	fill.ZIndex = 12
	fill.Parent = pill
	round(fill, 12)
	local pillLabel = inked(pill, {
		Name = "Time",
		Text = "",
		TextSize = 20,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 13,
	})

	local function press()
		if isReady(index) then
			Sfx.play("click")
			remote:FireServer("claim", index)
		end
	end
	button.Activated:Connect(press)
	pill.Activated:Connect(press)

	return {
		button = button,
		icon = icon,
		sheen = sheen,
		fill = fill,
		pulse = nil,
		bob = nil,
		edge = cardEdge,
		lines = lines,
		pill = pill,
		pillLabel = pillLabel,
		scale = scale,
	}
end

--- Repaint every card's face from the gifts the server sent.
local function paintGifts()
	local s = state
	if s == nil then
		return
	end
	for index, card in cards do
		local gift = s.gifts[index]
		if gift then
			card.icon.Image = PlaytimeGifts.iconFor(PlaytimeGifts.GIFTS[index]) or Artwork.IMAGE.gift
			local lines = linesFor(gift)
			for row, label in card.lines do
				local line = lines[row]
				label.Text = if line then line.text else ""
				label.Visible = line ~= nil
				label.TextColor3 = if line then line.color else PANEL.white
			end
		end
	end
end

--- Repaint the countdowns and states. Cheap; runs four times a second.
local function paintTimes()
	local s = state
	if s == nil then
		return
	end
	local now = elapsed()
	for index, card in cards do
		local gift = s.gifts[index]
		if gift then
			local done = s.claimed[index] == true
			local ready = not done and now >= gift.minutes * 60
			-- THE BIG LAST GIFT SHINES while it is unclaimed and the panel is up (ShinyCard):
			-- rainbow border, rays, sweep. Claimed or hidden, the effect goes and the card
			-- gets its own colours back. The fill is the effect's while it runs.
			local panelUp = panelFrame ~= nil and panelFrame.Visible
			local shine = gift.big == true and not done and panelUp
			if shine and shiny[index] == nil then
				shiny[index] = ShinyCard.apply(card.button, { icon = card.icon, timer = card.pill, badgeText = "BEST!" })
			elseif not shine and shiny[index] ~= nil then
				shiny[index]()
				shiny[index] = nil
			end
			local tier = tierOf(index)
			if card.sheen then
				card.sheen.Color = if done then gradientOf(PANEL.doneTop, PANEL.doneBottom) else gradientOf(tier.top, tier.bottom)
			elseif shiny[index] == nil then
				-- The big plate with no effect running (claimed, or the panel is hidden).
				card.button.BackgroundColor3 = if done then PANEL.doneBottom else tier.bottom
			end
			card.edge.Color = if ready then PANEL.gold elseif done then PANEL.doneRim else tier.rim
			card.edge.Thickness = if ready then 5 else 3
			-- A ready gift breathes: its gold rim pulses, and its picture bobs (the big plate's
			-- picture is ShinyCard's to bob).
			if ready and card.pulse == nil then
				card.edge.Transparency = 0
				local pulse = TweenService:Create(
					card.edge,
					TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = 0.6 }
				)
				pulse:Play()
				card.pulse = pulse
				if not gift.big then
					local bob = TweenService:Create(
						card.icon,
						TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ Position = UDim2.fromScale(0.5, 0) }
					)
					bob:Play()
					card.bob = bob
				end
			elseif not ready and card.pulse ~= nil then
				card.pulse:Cancel()
				card.pulse = nil
				card.edge.Transparency = 0
				if card.bob then
					card.bob:Cancel()
					card.bob = nil
					card.icon.Position = UDim2.new(0.5, 0, 0, ICON_Y)
				end
			end
			local total = gift.minutes * 60
			card.fill.Size = UDim2.fromScale(math.clamp(now / total, 0, 1), 1)
			card.fill.Visible = not ready and not done
			card.pill.BackgroundColor3 = if done then PANEL.pillDone elseif ready then PANEL.claim else PANEL.track
			card.pillLabel.Text = if done then "CLAIMED" elseif ready then "CLAIM" else clock(gift.minutes * 60 - now)
			card.pillLabel.TextSize = if done or ready then 18 else 20
			for _, label in card.lines do
				label.TextTransparency = if done then 0.5 else 0
			end
		end
	end
	local count = readyCount()
	if badge and badgeMark then
		badge.Visible = count > 0
		badgeMark.Text = tostring(count)
	end
	if claimAllButton then
		claimAllButton.BackgroundColor3 = if count > 0 then PANEL.claim else PANEL.cardDone
		claimAllButton.Active = count > 0
		claimAllButton.Text = if count > 0 then `CLAIM ALL ({count})` else "CLAIM ALL"
	end
end

function PlaytimeGiftController.open()
	local panel = panelFrame
	if panel == nil or panel.Visible or HudTile.blocked("PlaytimeGifts") then
		return
	end
	panel.Visible = true
	remote:FireServer("ask")
	paintTimes()
	if panelScale then
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, OPEN, { Scale = 1 }):Play()
	end
end

function PlaytimeGiftController.close()
	if panelFrame then
		panelFrame.Visible = false
	end
end

function PlaytimeGiftController.toggle()
	if panelFrame and panelFrame.Visible then
		PlaytimeGiftController.close()
	else
		PlaytimeGiftController.open()
	end
end

local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlaytimeGiftsPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, -PANEL_LIFT)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = PANEL.panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 10
	panel.Parent = canvas
	round(panel, 8)
	edge(panel, PANEL.ink, 4)
	Studded.darkPanel(panel, 8) -- the Shop's dark grey studded backdrop
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	inked(panel, {
		Name = "Title",
		Text = "Free Gifts",
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(400, 40),
		Position = UDim2.fromOffset(PAD, PAD - 6),
		ZIndex = 11,
	})
	inked(panel, {
		Name = "Subtitle",
		Text = "Keep playing to unlock better gifts!",
		TextSize = 14,
		TextColor3 = PANEL.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -PAD * 2 - 50, 0, 18),
		Position = UDim2.fromOffset(PAD + 2, PAD + 33),
		ZIndex = 11,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -PAD, 0, PAD - 4)
	close.Size = UDim2.fromOffset(36, 36)
	close.BackgroundColor3 = PANEL.close
	close.Font = PANEL.font
	close.TextSize = 24
	close.TextColor3 = PANEL.white
	close.Text = "X"
	close.ZIndex = 11
	close.Parent = panel
	round(close, 6)
	edge(close, PANEL.ink, 3)
	close.Activated:Connect(PlaytimeGiftController.close)

	local top = PAD + HEADER_H
	for index = 1, COLS * ROWS do
		local col = (index - 1) % COLS
		local row = (index - 1) // COLS
		cards[index] = buildCard(
			panel,
			index,
			Vector2.new(PAD + col * (CARD_W + CARD_GAP), top + row * (CARD_H + CARD_GAP))
		)
	end

	inked(panel, {
		Name = "Footer",
		Text = "Leaving resets gifts!",
		TextSize = 22,
		TextColor3 = PANEL.gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(420, 36),
		Position = UDim2.new(0, PAD, 1, -PAD + 4),
		ZIndex = 11,
	})

	local all = Instance.new("TextButton")
	all.Name = "ClaimAll"
	all.AutoButtonColor = false
	all.AnchorPoint = Vector2.new(1, 1)
	all.Position = UDim2.new(1, -PAD, 1, -PAD + 6)
	all.Size = UDim2.fromOffset(220, 38)
	all.BackgroundColor3 = PANEL.cardDone
	all.Font = PANEL.font
	all.TextSize = 20
	all.TextColor3 = PANEL.white
	all.Text = "CLAIM ALL"
	all.ZIndex = 11
	all.Parent = panel
	round(all, 8)
	edge(all, PANEL.ink, 3)
	all.Activated:Connect(function()
		if readyCount() > 0 then
			Sfx.play("click")
			remote:FireServer("claimAll")
		end
	end)
	claimAllButton = all

	panelFrame = panel
	panelScale = scale
	return gui
end

local function celebrate(indexes: { any })
	local panel = panelFrame
	if panel == nil or not panel.Visible then
		return
	end
	Sfx.play("mastery")
	for _, index in indexes do
		local card = cards[tonumber(index) or 0]
		if card then
			card.scale.Scale = 1.12
			TweenService:Create(card.scale, POP, { Scale = 1 }):Play()
		end
	end
end

local function onState(payload: any)
	if type(payload) ~= "table" or type(payload.gifts) ~= "table" then
		return
	end
	local claimed = {}
	for _, index in payload.claimed or {} do
		claimed[tonumber(index) or 0] = true
	end
	state = {
		startedAt = tonumber(payload.startedAt) or Workspace:GetServerTimeNow(),
		gifts = payload.gifts,
		claimed = claimed,
	}
	paintGifts()
	paintTimes()
	if type(payload.justClaimed) == "table" then
		celebrate(payload.justClaimed)
	end
end

function PlaytimeGiftController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local tileGui, button = HudTile.build({
		name = "FreeGiftsButton",
		caption = "Gifts",
		slot = TILE_SLOT,
		color = TILE_COLOR,
		light = TILE_LIGHT,
		image = Artwork.IMAGE.giftBox,
		onActivated = PlaytimeGiftController.toggle,
	})
	badge, badgeMark = HudTile.badge(button, PANEL.close, PANEL.ink)
	tileGui.Parent = playerGui
	buildPanel().Parent = playerGui
	HudTile.registerPanel("PlaytimeGifts", panelFrame :: Frame)

	remote = Net.get("PlaytimeGifts")
	remote.OnClientEvent:Connect(onState)
	-- In case the load push landed before this listener did.
	remote:FireServer("ask")

	-- The countdowns, and the badge lighting up when a gift opens mid-session.
	task.spawn(function()
		while true do
			task.wait(0.25)
			paintTimes()
		end
	end)
end

return PlaytimeGiftController
