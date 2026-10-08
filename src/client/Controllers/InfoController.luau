--[[
	InfoController — the "i" button in the top left (right of the Settings gear) and the
	short "How to play" panel it opens, on request (2026-10-06: "add an information
	button to explain the game briefly").

	ONE ROW PER STEP of the loop, in the order a new player meets them: a numbered chip
	in the step's colour, a heading, one line under it. Plain copy, nothing read from
	the server, so it opens instantly and never goes stale on a number. Keep it short:
	the tutorial teaches the moves, this is the one-page "what is this game" reminder.

	Not gated by the tutorial (TutorialGate): a brand-new player is the one who needs it.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.Parent.UIKit)
local Studded = require(script.Parent.Parent.Studded)
local HudTile = require(script.Parent.Parent.HudTile)

local InfoController = {}

local PANEL = {
	row = Color3.fromHex("252A30"),
	dim = Color3.fromHex("9AA3AD"),
	close = Color3.fromHex("E5484D"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	font = Enum.Font.GothamBlack,
	body = Enum.Font.GothamBold,
}
local PANEL_W = 600
local PANEL_H = 580
local PANEL_LIFT = 20
local PAD = 20
local HEADER_H = 70
local ROW_H = 70
local ROW_GAP = 8
local CHIP = 40
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- The loop, in order. Wording follows Config/Tutorial's step titles.
local STEPS = {
	{
		title = "Dig",
		text = "Head out to a stage, walk onto a glowing spot and hold E to dig.",
		color = Color3.fromHex("FFC42E"),
	},
	{
		title = "Haul",
		text = "Click fast to pull the nuke to the top before its fuse runs out.",
		color = Color3.fromHex("FF7A6B"),
	},
	{
		title = "Clean",
		text = "Take it home to your cleansing station and wash the crust off.",
		color = Color3.fromHex("5AC8FA"),
	},
	{
		title = "Earn",
		text = "Put clean nukes on your stands. They make cash every second.",
		color = Color3.fromHex("33D23F"),
	},
	{
		title = "Upgrade",
		text = "Buy better gear to find rarer nukes, and more floors for more stands.",
		color = Color3.fromHex("C77BFF"),
	},
	{
		title = "Stay safe",
		text = "Radiation builds up in the field. An aura keeps you alive deeper in.",
		color = Color3.fromHex("D9F51C"),
	},
}

local panelFrame: Frame? = nil
local panelScale: UIScale? = nil

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

function InfoController.open()
	local panel = panelFrame
	if panel == nil or panel.Visible or HudTile.blocked("Info") then
		return
	end
	panel.Visible = true
	if panelScale then
		panelScale.Scale = 0.85
		TweenService:Create(panelScale, OPEN, { Scale = 1 }):Play()
	end
end

function InfoController.close()
	if panelFrame then
		panelFrame.Visible = false
	end
end

function InfoController.toggle()
	if panelFrame and panelFrame.Visible then
		InfoController.close()
	else
		InfoController.open()
	end
end

local function buildRow(parent: Instance, index: number, step: { title: string, text: string, color: Color3 })
	local row = Instance.new("Frame")
	row.Name = `Step{index}`
	row.LayoutOrder = index
	row.Size = UDim2.new(1, -4, 0, ROW_H)
	row.BackgroundColor3 = PANEL.row
	row.BorderSizePixel = 0
	row.ZIndex = 11
	row.Parent = parent
	round(row, 6)
	edge(row, PANEL.ink, 3)

	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, 12, 0.5, 0)
	chip.Size = UDim2.fromOffset(CHIP, CHIP)
	chip.BackgroundColor3 = step.color
	chip.BorderSizePixel = 0
	chip.ZIndex = 12
	chip.Parent = row
	round(chip, 6)
	edge(chip, PANEL.ink, 3)
	inked(chip, {
		Name = "Number",
		Text = tostring(index),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 13,
	})

	local left = 12 + CHIP + 14
	inked(row, {
		Name = "Title",
		Text = step.title,
		TextSize = 22,
		TextColor3 = step.color,
		Position = UDim2.fromOffset(left, 8),
		Size = UDim2.new(1, -left - 12, 0, 24),
		ZIndex = 12,
	})
	inked(row, {
		Name = "Text",
		Text = step.text,
		Font = PANEL.body,
		TextSize = 15,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(left, 34),
		Size = UDim2.new(1, -left - 12, 0, ROW_H - 38),
		ZIndex = 12,
	})
end

local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "InfoPanel"
	gui.ResetOnSpawn = false
	-- Same as the Shop's and Masteries': a centred modal, over the whole HUD.
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, -PANEL_LIFT)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BorderSizePixel = 0
	panel.ZIndex = 10
	panel.Visible = false
	panel.Parent = canvas
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
	-- The Shop's dark grey studded backdrop, pushed back out past the padding.
	local pattern = Studded.darkPanel(panel, 8)
	pattern.Position = UDim2.fromOffset(-PAD, -(PAD - 6))
	pattern.Size = UDim2.new(1, 2 * PAD, 1, 2 * PAD - 6)

	inked(panel, {
		Name = "Title",
		Text = "How to play",
		TextSize = 38,
		Size = UDim2.fromOffset(340, 46),
		ZIndex = 11,
	})
	inked(panel, {
		Name = "Subtitle",
		Text = "Dig up radioactive nukes, clean them, and show them off for cash.",
		TextSize = 14,
		TextColor3 = PANEL.dim,
		Size = UDim2.new(1, -60, 0, 18),
		Position = UDim2.fromOffset(2, 46),
		ZIndex = 11,
	})

	local close = UIKit.closeButton(panel, {
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, 0, 0, 2),
		size = 40,
		zIndex = 11,
	})
	close.Activated:Connect(InfoController.close)

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

	for index, step in STEPS do
		buildRow(list, index, step)
	end

	panelFrame = panel
	panelScale = scale
	return gui
end

function InfoController.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local tileGui = HudTile.build({
		name = "InfoButton",
		caption = "Info",
		slot = 1,
		-- Right of the Settings gear, in the top-left topbar band.
		topbarLeft = 2,
		color = Color3.fromHex("5AC8FA"),
		light = Color3.fromHex("CDEEFF"),
		image = "",
		glyph = "i",
		onActivated = InfoController.toggle,
	})
	tileGui.Parent = playerGui
	buildPanel().Parent = playerGui
	HudTile.registerPanel("Info", panelFrame :: Frame)
end

return InfoController
