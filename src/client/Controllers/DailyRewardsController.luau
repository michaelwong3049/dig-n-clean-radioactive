--[[
	DailyRewardsController — the Daily tile (right column, under Warp), the 7-day
	calendar it opens, and the CLAIM button. Reads DailyRewards (Services/
	DailyRewardService). Opens ONLY from the tile, on request: nothing pops up on join;
	the tile wears a red "!" while a reward is waiting.

	THE SERVER WORKS OUT EVERY NUMBER. Cash is minutes of your stand income and the
	crates follow your deepest stage (Config/DailyRewards), so the panel asks for a
	fresh calendar each time it opens and only draws what comes back.

	SIX SMALL CARDS AND ONE BIG ONE: Days 1-6 in a 3x2 grid, Day 7 a tall gold card on
	the right. A card is CLAIMED (dimmed, a tick), TODAY (gold edge, claimable now),
	NEXT (the one the countdown is for) or LATER.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Crates = require(Shared.Config.Crates)
local DailyRewards = require(Shared.Config.DailyRewards)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)
local Sfx = require(script.Parent.Parent.Sfx)

local DailyRewardsController = {}

-- Fourth in the right column: Gear, Nukes, Warp, Daily.
local TILE_SLOT = 4
local TILE_COLOR = Color3.fromRGB(240, 80, 127)
local TILE_LIGHT = Color3.fromRGB(255, 190, 210)

local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	card = Color3.fromHex("252A30"),
	cardDone = Color3.fromHex("1F2328"),
	off = Color3.fromHex("3A4047"),
	dim = Color3.fromHex("9AA3AD"),
	close = Color3.fromHex("E5484D"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	gold = Color3.fromRGB(255, 200, 51),
	green = Color3.fromRGB(88, 214, 104),
	cash = Color3.fromRGB(120, 230, 120),
	luck = Color3.fromRGB(110, 220, 120),
	boost = Color3.fromRGB(255, 214, 92),
	claim = Color3.fromRGB(62, 190, 90),
	font = Enum.Font.GothamBlack,
}

local PAD = 20
local HEADER_H = 74
local CARD_W = 180
local CARD_H = 158
local CARD_GAP = 12
local BIG_W = 230
local FOOTER_H = 66
local PANEL_W = PAD * 2 + CARD_W * 3 + CARD_GAP * 3 + BIG_W
local PANEL_H = PAD * 2 + HEADER_H + CARD_H * 2 + CARD_GAP + FOOTER_H
local PANEL_LIFT = 20
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

type Card = {
	frame: Frame,
	edge: UIStroke,
	title: TextLabel,
	gift: ImageLabel,
	lines: Frame,
	tick: TextLabel,
	claimedLabel: TextLabel,
	scale: UIScale,
}

type State = {
	day: number,
	ready: boolean,
	readyAt: number,
	resetAt: number,
	days: { any },
}

local cards: { Card } = {}
local panelFrame: Frame? = nil
local panelScale: UIScale? = nil
local claimButton: TextButton? = nil
local claimEdge: UIStroke? = nil
local statusLabel: TextLabel? = nil
local badge: Frame? = nil
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

local function frame(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	return f
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

local function minutes(seconds: number): string
	return `{math.floor(seconds / 60 + 0.5)}m`
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
end

-- ── The calendar ────────────────────────────────────────────────────

local function buildCard(parent: Instance, index: number, size: Vector2, position: Vector2, big: boolean): Card
	local f = frame(parent, `Day{index}`, UDim2.fromOffset(size.X, size.Y), UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y / 2), PANEL.card, 12)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	round(f, 8)
	local stroke = edge(f, PANEL.ink, 3)
	local scale = Instance.new("UIScale")
	scale.Parent = f

	local title = inked(f, {
		Name = "Title",
		Text = `DAY {index}`,
		TextSize = if big then 30 else 22,
		Size = UDim2.new(1, 0, 0, if big then 36 else 26),
		Position = UDim2.fromOffset(0, 6),
		ZIndex = 14,
	})

	local giftSize = if big then 96 else 52
	local gift = Artwork.picture(f, "Gift", Artwork.IMAGE.gift, giftSize, PANEL.white)
	gift.AnchorPoint = Vector2.new(0.5, 0)
	gift.Position = UDim2.new(0.5, 0, 0, if big then 46 else 32)
	gift.ZIndex = 13

	local linesTop = (if big then 46 else 32) + giftSize + 4
	local lines = frame(f, "Lines", UDim2.new(1, -12, 1, -linesTop - 6), UDim2.fromOffset(6, linesTop), PANEL.card, 13)
	lines.BackgroundTransparency = 1
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, if big then 4 else 1)
	layout.Parent = lines

	-- A claimed card swaps its reward lines for a big tick over the faded gift.
	local tick = inked(f, {
		Name = "Tick",
		Text = "\u{2713}",
		TextSize = if big then 80 else 50,
		TextColor3 = PANEL.green,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(giftSize, giftSize),
		Position = UDim2.new(0.5, 0, 0, (if big then 46 else 32) + giftSize / 2),
		Visible = false,
		ZIndex = 16,
	})
	local claimedLabel = inked(f, {
		Name = "Claimed",
		Text = "CLAIMED",
		TextSize = if big then 22 else 16,
		TextColor3 = PANEL.green,
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, linesTop + 2),
		Visible = false,
		ZIndex = 14,
	})

	return {
		frame = f,
		edge = stroke,
		title = title,
		gift = gift,
		lines = lines,
		tick = tick,
		claimedLabel = claimedLabel,
		scale = scale,
	}
end

local function fillLines(card: Card, reward: any, big: boolean)
	for _, child in card.lines:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local size = if big then 18 else 16
	local order = 0
	local function line(text: string, color: Color3)
		order += 1
		inked(card.lines, {
			Name = `Line{order}`,
			Text = text,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, size + 3),
			LayoutOrder = order,
			ZIndex = 14,
		})
	end

	if (tonumber(reward.cash) or 0) > 0 then
		line(shortMoney(reward.cash), PANEL.cash)
	end
	-- Fold repeats: { "nuke3", "nuke3" } -> "2x Void Crate".
	local counts, seen = {}, {}
	for _, crateId in reward.crates or {} do
		if Crates.has(crateId) then
			if counts[crateId] == nil then
				table.insert(seen, crateId)
			end
			counts[crateId] = (counts[crateId] or 0) + 1
		end
	end
	for _, crateId in seen do
		local def = Crates.get(crateId)
		line(`{counts[crateId]}x {def.short}`, Color3.fromHex(def.color):Lerp(PANEL.white, 0.25))
	end
	if (tonumber(reward.luckSeconds) or 0) > 0 then
		line(`{minutes(reward.luckSeconds)} 2x Luck`, PANEL.luck)
	end
	if (tonumber(reward.cashBoostSeconds) or 0) > 0 then
		line(`{minutes(reward.cashBoostSeconds)} 2x Cash`, PANEL.boost)
	end
end

--- Which days of this cycle are already claimed: the ones before `day`, or all seven
--- just after a Day 7 claim (the save has looped to Day 1 but it is not ready yet).
local function claimedThrough(s: State): number
	if not s.ready and s.day == 1 and s.readyAt > 0 then
		return DailyRewards.DAYS_IN_CYCLE
	end
	return s.day - 1
end

local function paint()
	local s = state
	if s == nil then
		return
	end
	local done = claimedThrough(s)
	for index, card in cards do
		local reward = s.days[index]
		local big = index == DailyRewards.DAYS_IN_CYCLE
		if reward then
			fillLines(card, reward, big)
		end
		local claimed = index <= done
		local current = index == s.day and done < index
		card.tick.Visible = claimed
		card.claimedLabel.Visible = claimed
		card.lines.Visible = not claimed
		card.frame.BackgroundColor3 = if claimed then PANEL.cardDone elseif big then Color3.fromHex("3A2F14") else PANEL.card
		card.gift.ImageTransparency = if claimed then 0.75 else 0
		card.title.TextColor3 = if current then PANEL.gold elseif claimed then PANEL.dim else PANEL.white
		card.edge.Color = if current then PANEL.gold elseif big then Color3.fromHex("8A6A14") else PANEL.ink
		card.edge.Thickness = if current then 4 else 3
	end
	if badge then
		badge.Visible = s.ready
	end
end

--- The footer: CLAIM while ready, otherwise the countdown. Runs every second the
--- panel is open.
local function paintFooter()
	local s = state
	local button, label = claimButton, statusLabel
	if s == nil or button == nil or label == nil then
		return
	end
	local now = workspace:GetServerTimeNow()
	local ready = s.ready or (s.readyAt > 0 and now >= s.readyAt)
	if ready and not s.ready then
		-- The countdown ran out with the panel open: fetch the calendar it opens on.
		s.ready = true
		remote:FireServer("ask")
	end
	button.Active = ready
	button.AutoButtonColor = ready
	button.BackgroundColor3 = if ready then PANEL.claim else PANEL.off
	button.Text = if ready then `CLAIM DAY {s.day}` else `NEXT IN {clock(s.readyAt - now)}`
	if claimEdge then
		claimEdge.Color = PANEL.ink
	end
	if ready then
		label.Text = if s.day == 1 and s.resetAt > 0 and now > s.resetAt
			then "You missed a day, so the streak starts again at Day 1."
			else "Come back every day. Miss a day and it starts over at Day 1."
	else
		label.Text = `Claim within 24 h of it opening or the streak resets to Day 1.`
	end
end

function DailyRewardsController.open()
	local panel = panelFrame
	if panel == nil or panel.Visible or HudTile.blocked("DailyRewards") then
		return
	end
	panel.Visible = true
	remote:FireServer("ask")
	paintFooter()
	if panelScale then
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, OPEN, { Scale = 1 }):Play()
	end
end

function DailyRewardsController.close()
	if panelFrame then
		panelFrame.Visible = false
	end
end

function DailyRewardsController.toggle()
	if panelFrame and panelFrame.Visible then
		DailyRewardsController.close()
	else
		DailyRewardsController.open()
	end
end

local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DailyRewardsPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local panel = frame(canvas, "Panel", UDim2.fromOffset(PANEL_W, PANEL_H), UDim2.new(0.5, 0, 0.5, -PANEL_LIFT), PANEL.panel, 10)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Visible = false
	round(panel, 8)
	edge(panel, PANEL.ink, 4)
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	inked(panel, {
		Name = "Title",
		Text = "Daily Rewards",
		TextSize = 38,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromOffset(400, 46),
		Position = UDim2.fromOffset(PAD, PAD - 6),
		ZIndex = 11,
	})
	inked(panel, {
		Name = "Subtitle",
		Text = "A new reward every 24 hours. Cash and crates grow with how far you've dug.",
		TextSize = 14,
		TextColor3 = PANEL.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -PAD * 2 - 50, 0, 18),
		Position = UDim2.fromOffset(PAD + 2, PAD + 40),
		ZIndex = 11,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -PAD, 0, PAD - 4)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = PANEL.close
	close.Font = PANEL.font
	close.TextSize = 24
	close.TextColor3 = PANEL.white
	close.Text = "X"
	close.ZIndex = 11
	close.Parent = panel
	round(close, 6)
	edge(close, PANEL.ink, 3)
	close.Activated:Connect(DailyRewardsController.close)

	local top = PAD + HEADER_H
	for index = 1, DailyRewards.DAYS_IN_CYCLE - 1 do
		local col = (index - 1) % 3
		local row = (index - 1) // 3
		cards[index] = buildCard(
			panel,
			index,
			Vector2.new(CARD_W, CARD_H),
			Vector2.new(PAD + col * (CARD_W + CARD_GAP), top + row * (CARD_H + CARD_GAP)),
			false
		)
	end
	cards[DailyRewards.DAYS_IN_CYCLE] = buildCard(
		panel,
		DailyRewards.DAYS_IN_CYCLE,
		Vector2.new(BIG_W, CARD_H * 2 + CARD_GAP),
		Vector2.new(PAD + 3 * (CARD_W + CARD_GAP), top),
		true
	)

	local footTop = top + CARD_H * 2 + CARD_GAP + 14
	local button = Instance.new("TextButton")
	button.Name = "Claim"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -PAD, 0, footTop)
	button.Size = UDim2.fromOffset(BIG_W, 50)
	button.BackgroundColor3 = PANEL.off
	button.Font = PANEL.font
	button.TextSize = 22
	button.TextColor3 = PANEL.white
	button.Text = ""
	button.ZIndex = 11
	button.Parent = panel
	round(button, 6)
	claimEdge = edge(button, PANEL.ink, 3)
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = PANEL.ink
	textStroke.Thickness = 2
	textStroke.Parent = button
	button.Activated:Connect(function()
		if state and button.Active then
			Sfx.play("click")
			button.Active = false
			remote:FireServer("claim")
		end
	end)

	statusLabel = inked(panel, {
		Name = "Status",
		Text = "",
		TextSize = 16,
		TextColor3 = PANEL.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Size = UDim2.new(1, -PAD * 2 - BIG_W - 16, 0, 50),
		Position = UDim2.fromOffset(PAD + 2, footTop),
		ZIndex = 11,
	})

	panelFrame = panel
	panelScale = scale
	claimButton = button
	return gui
end

--- The claimed card's little celebration: a pop and the tick.
local function celebrate(index: number)
	local card = cards[index]
	if card == nil then
		return
	end
	Sfx.play("mastery")
	card.scale.Scale = 1.15
	TweenService:Create(card.scale, POP, { Scale = 1 }):Play()
end

local function onState(payload: any)
	if type(payload) ~= "table" or type(payload.days) ~= "table" then
		return
	end
	state = {
		day = tonumber(payload.day) or 1,
		ready = payload.ready == true,
		readyAt = tonumber(payload.readyAt) or 0,
		resetAt = tonumber(payload.resetAt) or 0,
		days = payload.days,
	}
	paint()
	paintFooter()
	local claimed = tonumber(payload.claimed)
	if claimed then
		celebrate(claimed)
	end
end

function DailyRewardsController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local tileGui, button = HudTile.build({
		name = "DailyButton",
		caption = "Daily",
		slot = TILE_SLOT,
		color = TILE_COLOR,
		light = TILE_LIGHT,
		image = Artwork.IMAGE.gift,
		onActivated = DailyRewardsController.toggle,
	})
	local mark
	badge, mark = HudTile.badge(button, PANEL.close, PANEL.ink)
	mark.Text = "!"
	mark.TextSize = 13
	tileGui.Parent = playerGui
	buildPanel().Parent = playerGui
	HudTile.registerPanel("DailyRewards", panelFrame :: Frame)

	remote = Net.get("DailyRewards")
	remote.OnClientEvent:Connect(onState)
	-- In case the load push landed before this listener did.
	remote:FireServer("ask")

	-- The countdown, and the badge lighting up when a reward opens mid-session.
	task.spawn(function()
		while true do
			task.wait(1)
			local s = state
			if s and not s.ready and s.readyAt > 0 and workspace:GetServerTimeNow() >= s.readyAt then
				remote:FireServer("ask")
			end
			if panelFrame and panelFrame.Visible then
				paintFooter()
			end
		end
	end)
end

return DailyRewardsController
