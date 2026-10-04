--[[
	MasteriesController — the Masteries bar (left column, above Shop), the panel it
	opens, and the "Mastery reached" toast. Reads MasteryState (Services/MasteryService).

	Every word and number on it comes out of Shared/Mastery over Config/Masteries, the
	same functions StatResolver pays the rewards through, so a row cannot promise a
	reward the game does not apply.

	ONE ROW PER MASTERY: a medal well in the mastery's own colour (dimmed until Bronze),
	the name and the tier reached, what it counts, a bar toward the next goal, three
	pips for Bronze / Silver / Gold with their goals under them, and the reward now and
	at the next tier on the right.

	THE BADGE on the bar counts tiers reached since the panel was last opened this
	session; opening it clears the count.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Masteries = require(Shared.Config.Masteries)
local Mastery = require(Shared.Mastery)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)
local Sfx = require(script.Parent.Parent.Sfx)

local MasteriesController = {}

-- The button: alone on the middle of the RIGHT edge, level with the left-hand button
-- grid's middle (it swapped sides with the grid) -- no box, on request, just the medal
-- with its name under it.
local BAR_COLOR = Color3.fromRGB(255, 196, 46)
local BAR_LIGHT = Color3.fromRGB(255, 236, 170)
-- "Masteries" is twice "Shop"; at the bars' 28 it dwarfs the medal; a little smaller still, on request.
local CAPTION_SIZE = 17

local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	row = Color3.fromHex("252A30"),
	track = Color3.fromHex("14171A"),
	off = Color3.fromHex("3A4047"),
	dim = Color3.fromHex("9AA3AD"),
	close = Color3.fromHex("E5484D"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	font = Enum.Font.GothamBlack,
}
local PANEL_W = 820
local PANEL_H = 600
local PANEL_LIFT = 20
local PAD = 20
local HEADER_H = 70
local ROW_H = 80
local ROW_GAP = 8
local WELL = 60
local PIP = 22
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- The toast.
local TOAST_W = 460
local TOAST_H = 96
-- Below the tutorial's top banner and the warp bar, which it used to sit on.
local TOAST_TOP = 200
local TOAST_HOLD = 3
local TOAST_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TOAST_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

type Row = {
	well: Frame,
	medal: ImageLabel,
	tierLabel: TextLabel,
	fill: Frame,
	progress: TextLabel,
	pips: { Frame },
	now: TextLabel,
	nextLabel: TextLabel,
}

local rows: { [string]: Row } = {}
local panelFrame: Frame? = nil
local panelScale: UIScale? = nil
local badge: Frame? = nil
local badgeText: TextLabel? = nil
local unseen = 0

local toastHost: Frame? = nil
local toastQueue: { { id: string, tier: number } } = {}
local toasting = false

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

-- ── The panel ───────────────────────────────────────────────────────

local function buildRow(list: Instance, def: Masteries.Def, order: number): Row
	local row = frame(list, def.id, UDim2.new(1, -8, 0, ROW_H), UDim2.new(), PANEL.row, 12)
	row.LayoutOrder = order
	round(row, 6)
	edge(row, PANEL.ink, 2)

	local well = frame(row, "Well", UDim2.fromOffset(WELL, WELL), UDim2.new(0, 10, 0.5, -WELL / 2), def.color, 13)
	round(well, 6)
	edge(well, PANEL.ink, 2.5)
	local medal = Artwork.picture(well, "Medal", Artwork.IMAGE.medal, WELL - 8, PANEL.white)
	medal.AnchorPoint = Vector2.new(0.5, 0.5)
	medal.Position = UDim2.fromScale(0.5, 0.5)
	medal.ZIndex = 14

	local textLeft = 10 + WELL + 14
	inked(row, {
		Name = "Name",
		Text = def.name,
		TextSize = 24,
		Size = UDim2.fromOffset(200, 28),
		Position = UDim2.fromOffset(textLeft, 8),
		ZIndex = 14,
	})
	local tierLabel = inked(row, {
		Name = "Tier",
		Text = "",
		TextSize = 15,
		Size = UDim2.fromOffset(120, 20),
		Position = UDim2.fromOffset(textLeft + 168, 13),
		ZIndex = 14,
	})
	inked(row, {
		Name = "Counts",
		Text = def.counts,
		TextSize = 14,
		TextColor3 = PANEL.dim,
		Size = UDim2.fromOffset(200, 18),
		Position = UDim2.fromOffset(textLeft, 36),
		ZIndex = 14,
	})

	-- The bar toward the next goal, with "412 / 1K" over it.
	local barW = 220
	local track = frame(row, "Track", UDim2.fromOffset(barW, 14), UDim2.fromOffset(textLeft, 57), PANEL.track, 13)
	round(track, 4)
	edge(track, PANEL.ink, 2)
	local fill = frame(track, "Fill", UDim2.fromScale(0, 1), UDim2.new(), def.color, 14)
	round(fill, 4)
	local progress = inked(row, {
		Name = "Progress",
		Text = "",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(barW, 18),
		Position = UDim2.fromOffset(textLeft, 36),
		ZIndex = 15,
	})

	-- Three pips, each with its goal under it.
	local pipsLeft = textLeft + barW + 24
	local pips = {}
	for tier = 1, #def.goals do
		local x = pipsLeft + (tier - 1) * 58
		local pip = frame(row, `Pip{tier}`, UDim2.fromOffset(PIP, PIP), UDim2.fromOffset(x + 18, 14), PANEL.off, 14)
		round(pip, PIP)
		edge(pip, PANEL.ink, 2.5)
		inked(row, {
			Name = `Goal{tier}`,
			Text = Mastery.goalText(def, def.goals[tier]),
			TextSize = 13,
			TextColor3 = Masteries.TIER_COLORS[tier],
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(58, 18),
			Position = UDim2.fromOffset(x, 44),
			ZIndex = 14,
		})
		pips[tier] = pip
	end

	-- The reward: what it pays now, and at the next tier.
	local rewardLeft = pipsLeft + 3 * 58 + 14
	local now = inked(row, {
		Name = "Now",
		Text = "",
		TextSize = 17,
		TextWrapped = true,
		Size = UDim2.new(1, -rewardLeft - 10, 0, 22),
		Position = UDim2.fromOffset(rewardLeft, 14),
		ZIndex = 14,
	})
	local nextLabel = inked(row, {
		Name = "Next",
		Text = "",
		TextSize = 13,
		TextColor3 = PANEL.dim,
		Size = UDim2.new(1, -rewardLeft - 10, 0, 18),
		Position = UDim2.fromOffset(rewardLeft, 44),
		ZIndex = 14,
	})

	return {
		well = well,
		medal = medal,
		tierLabel = tierLabel,
		fill = fill,
		progress = progress,
		pips = pips,
		now = now,
		nextLabel = nextLabel,
	}
end

local function paintRow(def: Masteries.Def, count: number, tier: number)
	local row = rows[def.id]
	if row == nil then
		return
	end
	local reached = tier > 0
	row.well.BackgroundColor3 = if reached then def.color else def.color:Lerp(Color3.new(0, 0, 0), 0.6)
	row.medal.ImageTransparency = if reached then 0 else 0.55
	row.medal.ImageColor3 = if reached then Masteries.TIER_COLORS[tier]:Lerp(PANEL.white, 0.5) else PANEL.dim

	if reached then
		row.tierLabel.Text = Masteries.TIER_NAMES[tier]
		row.tierLabel.TextColor3 = Masteries.TIER_COLORS[tier]
	else
		row.tierLabel.Text = ""
	end

	for index, pip in row.pips do
		pip.BackgroundColor3 = if index <= tier then Masteries.TIER_COLORS[index] else PANEL.off
	end

	local maxed = tier >= #def.goals
	local goal = def.goals[math.min(tier + 1, #def.goals)]
	local floor = if tier > 0 then def.goals[tier] else 0
	local share = if maxed then 1 else math.clamp((count - floor) / math.max(goal - floor, 1), 0, 1)
	TweenService:Create(row.fill, FILL_TWEEN, { Size = UDim2.fromScale(share, 1) }):Play()
	row.fill.BackgroundColor3 = if maxed then Masteries.TIER_COLORS[#def.goals] else def.color
	row.progress.Text = if maxed
		then `{Mastery.goalText(def, count)}  Mastered`
		else `{Mastery.goalText(def, count)} / {Mastery.goalText(def, goal)}`

	if reached then
		row.now.Text = Mastery.rewardText(def, tier)
		row.now.TextColor3 = PANEL.white
	else
		row.now.Text = "No reward yet"
		row.now.TextColor3 = PANEL.dim
	end
	row.nextLabel.Text = if maxed then "Max tier" else `Next: {Mastery.rewardText(def, tier + 1)}`
end

function MasteriesController.open()
	local panel = panelFrame
	if panel == nil or panel.Visible or HudTile.blocked("Masteries") then
		return
	end
	panel.Visible = true
	unseen = 0
	if badge then
		badge.Visible = false
	end
	if panelScale then
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, OPEN, { Scale = 1 }):Play()
	end
end

function MasteriesController.close()
	if panelFrame then
		panelFrame.Visible = false
	end
end

function MasteriesController.toggle()
	if panelFrame and panelFrame.Visible then
		MasteriesController.close()
	else
		MasteriesController.open()
	end
end

local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "MasteriesPanel"
	gui.ResetOnSpawn = false
	-- Same as the Shop's: a centred modal, over the whole HUD.
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
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PAD - 6)
	padding.PaddingBottom = UDim.new(0, PAD)
	padding.PaddingLeft = UDim.new(0, PAD)
	padding.PaddingRight = UDim.new(0, PAD)
	padding.Parent = panel

	inked(panel, {
		Name = "Title",
		Text = "Masteries",
		TextSize = 38,
		Size = UDim2.fromOffset(300, 46),
		ZIndex = 11,
	})
	inked(panel, {
		Name = "Subtitle",
		Text = "Permanent rewards for all-time goals. A higher tier replaces the one below it.",
		TextSize = 14,
		TextColor3 = PANEL.dim,
		Size = UDim2.new(1, -60, 0, 18),
		Position = UDim2.fromOffset(2, 46),
		ZIndex = 11,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 2)
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
	close.Activated:Connect(MasteriesController.close)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(0, HEADER_H + 6)
	list.Size = UDim2.new(1, 0, 1, -HEADER_H - 6)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = PANEL.dim
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ZIndex = 11
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 2)
	listPad.PaddingLeft = UDim.new(0, 2)
	listPad.PaddingBottom = UDim.new(0, 4)
	listPad.Parent = list

	for index, def in Masteries.LIST do
		rows[def.id] = buildRow(list, def, index)
		paintRow(def, 0, 0)
	end

	panelFrame = panel
	panelScale = scale
	return gui
end

-- ── The toast ───────────────────────────────────────────────────────

local function buildToast(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "MasteryToast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)
	canvas.ClipsDescendants = false

	local host = frame(canvas, "Toast", UDim2.fromOffset(TOAST_W, TOAST_H), UDim2.new(0.5, 0, 0, -TOAST_H - 20), PANEL.panel, 20)
	host.AnchorPoint = Vector2.new(0.5, 0)
	host.Visible = false
	round(host, 8)
	edge(host, PANEL.ink, 4)
	toastHost = host
	return gui
end

local function showToast(id: string, tier: number)
	local host = toastHost
	local def = Mastery.get(id)
	if host == nil or def == nil then
		return
	end
	for _, child in host:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local color = Masteries.TIER_COLORS[tier]
	local stroke = host:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = PANEL.ink
	end
	local strip = frame(host, "Strip", UDim2.new(0, 10, 1, -8), UDim2.fromOffset(4, 4), color, 21)
	round(strip, 4)

	local well = frame(host, "Well", UDim2.fromOffset(72, 72), UDim2.new(0, 24, 0.5, -36), def.color, 21)
	round(well, 6)
	edge(well, PANEL.ink, 2.5)
	local medal = Artwork.picture(well, "Medal", Artwork.IMAGE.medal, 64, color:Lerp(PANEL.white, 0.5))
	medal.AnchorPoint = Vector2.new(0.5, 0.5)
	medal.Position = UDim2.fromScale(0.5, 0.5)
	medal.ZIndex = 22

	local left = 112
	inked(host, {
		Text = "Mastery reached!",
		TextSize = 16,
		TextColor3 = color,
		Size = UDim2.new(1, -left - 10, 0, 20),
		Position = UDim2.fromOffset(left, 10),
		ZIndex = 22,
	})
	inked(host, {
		Text = `{def.name} {Masteries.TIER_NAMES[tier]}`,
		TextSize = 30,
		Size = UDim2.new(1, -left - 10, 0, 34),
		Position = UDim2.fromOffset(left, 30),
		ZIndex = 22,
	})
	inked(host, {
		Text = `{Mastery.rewardText(def, tier)}, forever`,
		TextSize = 16,
		TextColor3 = def.color:Lerp(PANEL.white, 0.35),
		Size = UDim2.new(1, -left - 10, 0, 20),
		Position = UDim2.fromOffset(left, 66),
		ZIndex = 22,
	})

	host.Visible = true
	host.Position = UDim2.new(0.5, 0, 0, -TOAST_H - 20)
	TweenService:Create(host, TOAST_IN, { Position = UDim2.new(0.5, 0, 0, TOAST_TOP) }):Play()
	Sfx.play("mastery")
	task.wait(TOAST_HOLD)
	local out = TweenService:Create(host, TOAST_OUT, { Position = UDim2.new(0.5, 0, 0, -TOAST_H - 20) })
	out:Play()
	out.Completed:Wait()
	host.Visible = false
end

local function drainToasts()
	if toasting then
		return
	end
	toasting = true
	task.spawn(function()
		while #toastQueue > 0 do
			local queued = table.remove(toastQueue, 1)
			if queued then
				showToast(queued.id, queued.tier)
			end
		end
		toasting = false
	end)
end

-- ── State ───────────────────────────────────────────────────────────

local function onState(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.masteries) == "table" then
		for _, entry in payload.masteries do
			local def = if type(entry) == "table" and type(entry.id) == "string" then Mastery.get(entry.id) else nil
			if def then
				paintRow(def, tonumber(entry.count) or 0, tonumber(entry.tier) or 0)
			end
		end
	end
	if type(payload.unlocked) == "table" then
		for _, entry in payload.unlocked do
			if type(entry) == "table" and type(entry.id) == "string" and type(entry.tier) == "number" then
				table.insert(toastQueue, { id = entry.id, tier = entry.tier })
				if not (panelFrame and panelFrame.Visible) then
					unseen += 1
				end
			end
		end
		if badge and badgeText then
			badge.Visible = unseen > 0
			badgeText.Text = tostring(unseen)
		end
		drainToasts()
	end
end

function MasteriesController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local barGui, button = HudTile.build({
		name = "MasteriesButton",
		caption = "Masteries",
		slot = 0,
		color = BAR_COLOR,
		light = BAR_LIGHT,
		image = Artwork.IMAGE.medal,
		onActivated = MasteriesController.toggle,
		captionSize = CAPTION_SIZE,
		bare = true,
	})
	badge, badgeText = HudTile.badge(button, Color3.fromRGB(229, 72, 77), PANEL.ink)
	-- On the medal's shoulder, not the (invisible) button's far corner.
	badge.AnchorPoint = Vector2.new(0, 0)
	badge.Position = UDim2.new(0.5, 22, 0, -2)
	barGui.Parent = playerGui
	buildPanel().Parent = playerGui
	buildToast().Parent = playerGui
	HudTile.registerPanel("Masteries", panelFrame :: Frame)

	local remote = Net.get("MasteryState")
	remote.OnClientEvent:Connect(onState)
	-- In case the load push landed before this listener did.
	remote:FireServer()
end

return MasteriesController
