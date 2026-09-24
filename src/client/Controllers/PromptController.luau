--!strict
--[[
	PromptController.luau — the game's own face for every "press E" ProximityPrompt.

	Roblox's default prompt is a flat grey box that looks like nothing else in the game.
	This swaps it, for every prompt, for a dark glass card: an amber accent pill, a
	keycap that fills amber while you hold, the object's name small and dim, the verb
	big and white. Chosen from a mockup round ("option 3").

	HOW: every ProximityPrompt that shows up in the world at `Style = Default` is flipped
	to `Custom` ON THIS CLIENT ONLY, and ProximityPromptService's events drive a card we
	build ourselves. The prompt object still owns all the input -- key, gamepad button,
	hold timing, Exclusivity, the Triggered fire -- so no server code, no world rebuild
	and no prompt's behaviour changes; only the face does. A prompt that already arrives
	as `Custom` (the dig pick-up keycap, DetectorController) has its own face and is left
	alone.

	ONE SCREENGUI HOLDS EVERY CARD, the way Roblox's own "ProximityPrompts" gui does, so
	WashController's hideHud (which disables each direct child LayerCollector of
	PlayerGui) puts every prompt away in one go for the wash view -- including any that
	appear while it is up.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UIKit = require(script.Parent.Parent.UIKit)

local PromptController = {}

-- ── Look ─────────────────────────────────────────────────────────────
-- Design px (UIKit.billboardCanvas scales them with the HUD). The palette is the shop
-- panel's slate and amber, so a stall's prompt and the panel it opens read as one.
local STYLE = {
	card = Color3.fromRGB(18, 20, 24),
	cardAlpha = 0.18,
	cardEdge = Color3.fromRGB(255, 255, 255),
	cardEdgeAlpha = 0.86,
	accent = Color3.fromHex("F2A93B"),
	key = Color3.fromRGB(42, 47, 55),
	keyLip = Color3.fromRGB(24, 27, 32),
	keyEdge = Color3.fromRGB(74, 82, 94),
	keyText = Color3.fromRGB(255, 255, 255),
	object = Color3.fromRGB(154, 164, 174),
	verb = Color3.fromRGB(255, 255, 255),
}

local CANVAS = Vector2.new(420, 72) -- room for the longest verb; the card sizes itself inside it
local CARD_HEIGHT = 56
local KEY_SIZE = 40
local KEY_LIP = 4 -- the darker slab under the cap that makes it read as a key
local KEY_RADIUS = UDim.new(0, 9)
local KEY_TEXT = 18
local KEY_TEXT_WORD = 11 -- "TAP" / "HOLD" on touch
local OBJECT_TEXT = 11
local VERB_TEXT = 20

local SHOW = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local QUICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local GAMEPAD_GLYPH: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
	[Enum.KeyCode.ButtonL1] = "LB",
	[Enum.KeyCode.ButtonR1] = "RB",
}

-- ── State ────────────────────────────────────────────────────────────

-- Prompts this controller restyled, and so owns the face of. Keyed strongly and
-- pruned on removal: a weak-keyed Instance table drops entries while the Instance is
-- still alive (see UIKit's canvas registry).
local owned: { [ProximityPrompt]: boolean } = {}

type Fader = { inst: Instance, prop: string, shown: number }

type Card = {
	gui: BillboardGui,
	scale: UIScale,
	keyScale: UIScale,
	fill: Frame,
	key: TextLabel,
	object: TextLabel,
	verb: TextLabel,
	faders: { Fader },
	conns: { RBXScriptConnection },
}

local cards: { [ProximityPrompt]: Card } = {}
local host: ScreenGui? = nil

local function getHost(): ScreenGui
	if host and host.Parent then
		return host
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PromptCards"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	host = gui
	return gui
end

-- ── Restyling ────────────────────────────────────────────────────────

local function adopt(inst: Instance)
	if not inst:IsA("ProximityPrompt") or owned[inst] then
		return
	end
	-- Custom already means someone draws its face on purpose.
	if inst.Style ~= Enum.ProximityPromptStyle.Default then
		return
	end
	inst.Style = Enum.ProximityPromptStyle.Custom
	owned[inst] = true
	inst.Destroying:Connect(function()
		owned[inst] = nil
	end)
end

-- ── The card ─────────────────────────────────────────────────────────

local function adorneeFor(prompt: ProximityPrompt): Instance?
	local parent = prompt.Parent
	if parent == nil then
		return nil
	end
	if parent:IsA("BasePart") or parent:IsA("Attachment") then
		return parent
	end
	if parent:IsA("Model") then
		return parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function glyphFor(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): (string, number)
	if inputType == Enum.ProximityPromptInputType.Touch then
		return if prompt.HoldDuration > 0 then "HOLD" else "TAP", KEY_TEXT_WORD
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		local code = prompt.GamepadKeyCode
		return GAMEPAD_GLYPH[code] or code.Name, KEY_TEXT
	end
	local code = prompt.KeyboardKeyCode
	local text = UserInputService:GetStringForKeyCode(code)
	if text == nil or text == "" then
		text = code.Name
	end
	return string.upper(text), if #text > 2 then KEY_TEXT_WORD else KEY_TEXT
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function textLabel(parent: Instance, name: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, size + 2)
	label.Parent = parent
	return label
end

local function refreshText(card: Card, prompt: ProximityPrompt)
	card.verb.Text = prompt.ActionText
	local object = prompt.ObjectText
	card.object.Text = string.upper(object)
	card.object.Visible = object ~= ""
end

local function setShown(card: Card, shown: boolean, info: TweenInfo)
	for _, f in card.faders do
		TweenService:Create(f.inst, info, { [f.prop] = if shown then f.shown else 1 }):Play()
	end
	TweenService:Create(card.scale, info, { Scale = if shown then 1 else 0.7 }):Play()
end

local function buildCard(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): Card?
	local adornee = adorneeFor(prompt)
	if adornee == nil then
		return nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "Prompt"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Active = true
	gui.ResetOnSpawn = false
	gui.Parent = getHost()
	local canvas = UIKit.billboardCanvas(gui, CANVAS)

	local faders: { Fader } = {}
	local function fade(inst: Instance, prop: string, shown: number)
		table.insert(faders, { inst = inst, prop = prop, shown = shown });
		(inst :: any)[prop] = 1
	end

	-- The whole card, centred in the canvas and as wide as its text.
	local panel = Instance.new("Frame")
	panel.Name = "Card"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(0, CARD_HEIGHT)
	panel.AutomaticSize = Enum.AutomaticSize.X
	panel.BackgroundColor3 = STYLE.card
	panel.BorderSizePixel = 0
	panel.Parent = canvas
	corner(panel, UDim.new(0, 14))
	fade(panel, "BackgroundTransparency", STYLE.cardAlpha)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = panel

	local edge = Instance.new("UIStroke")
	edge.Color = STYLE.cardEdge
	edge.Thickness = 1.5
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = panel
	fade(edge, "Transparency", STYLE.cardEdgeAlpha)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = panel

	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 10)
	row.Parent = panel

	-- Amber pill down the left edge: an inset pill rather than a flush bar, because a
	-- flush bar would square off the card's rounded corners (Roblox clips to rects).
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.LayoutOrder = 1
	accent.Size = UDim2.fromOffset(4, CARD_HEIGHT - 20)
	accent.BackgroundColor3 = STYLE.accent
	accent.BorderSizePixel = 0
	accent.Parent = panel
	corner(accent, UDim.new(1, 0))
	fade(accent, "BackgroundTransparency", 0)

	-- The keycap: a darker lip under a raised cap, so it reads as a key and not a tile.
	local keyHolder = Instance.new("Frame")
	keyHolder.Name = "KeyHolder"
	keyHolder.LayoutOrder = 2
	keyHolder.Size = UDim2.fromOffset(KEY_SIZE, KEY_SIZE)
	keyHolder.BackgroundTransparency = 1
	keyHolder.Parent = panel

	local keyScale = Instance.new("UIScale")
	keyScale.Parent = keyHolder

	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.Size = UDim2.fromScale(1, 1)
	lip.BackgroundColor3 = STYLE.keyLip
	lip.BorderSizePixel = 0
	lip.Parent = keyHolder
	corner(lip, KEY_RADIUS)
	fade(lip, "BackgroundTransparency", 0)

	local cap = Instance.new("Frame")
	cap.Name = "Cap"
	cap.Size = UDim2.new(1, 0, 1, -KEY_LIP)
	cap.BackgroundColor3 = STYLE.key
	cap.BorderSizePixel = 0
	cap.ClipsDescendants = true
	cap.Parent = keyHolder
	corner(cap, KEY_RADIUS)
	fade(cap, "BackgroundTransparency", 0)

	local capEdge = Instance.new("UIStroke")
	capEdge.Color = STYLE.keyEdge
	capEdge.Thickness = 1.5
	capEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	capEdge.Parent = cap
	fade(capEdge, "Transparency", 0)

	-- The hold timer: fills the cap bottom-up in amber across HoldDuration. Its own
	-- corner, because ClipsDescendants clips to the cap's rect, not its rounding.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = STYLE.accent
	fill.BorderSizePixel = 0
	fill.Parent = cap
	corner(fill, KEY_RADIUS)
	fade(fill, "BackgroundTransparency", 0)

	local glyph, glyphSize = glyphFor(prompt, inputType)
	local key = Instance.new("TextLabel")
	key.Name = "Key"
	key.Size = UDim2.fromScale(1, 1)
	key.BackgroundTransparency = 1
	key.Font = UIKit.Font.hero
	key.Text = glyph
	key.TextSize = glyphSize
	key.TextColor3 = STYLE.keyText
	key.ZIndex = 2
	key.Parent = cap
	fade(key, "TextTransparency", 0)

	-- The words: the object small, dim and in caps over the verb.
	local words = Instance.new("Frame")
	words.Name = "Words"
	words.LayoutOrder = 3
	words.Size = UDim2.fromOffset(0, CARD_HEIGHT)
	words.AutomaticSize = Enum.AutomaticSize.X
	words.BackgroundTransparency = 1
	words.Parent = panel

	local column = Instance.new("UIListLayout")
	column.FillDirection = Enum.FillDirection.Vertical
	column.VerticalAlignment = Enum.VerticalAlignment.Center
	column.SortOrder = Enum.SortOrder.LayoutOrder
	column.Padding = UDim.new(0, 1)
	column.Parent = words

	local object = textLabel(words, "Object", UIKit.Font.title, OBJECT_TEXT, STYLE.object)
	object.LayoutOrder = 1
	fade(object, "TextTransparency", 0)

	local verb = textLabel(words, "Verb", UIKit.Font.title, VERB_TEXT, STYLE.verb)
	verb.LayoutOrder = 2
	fade(verb, "TextTransparency", 0)

	-- Tap / click target over the whole card, so touch players (who have no E) and
	-- mouse users can press it -- Custom style drops Roblox's own tappable button.
	-- A SIBLING of the card, not a child: inside the card the row layout would place it
	-- as a fourth item, and a scale-sized item in an auto-sized row feeds its own width
	-- back into the card's. It tracks the card's size instead.
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = canvas
	local function fitHit()
		local s = UIKit.canvasScale(canvas) * math.max(scale.Scale, 0.01)
		hit.Size = UDim2.fromOffset(panel.AbsoluteSize.X / s, panel.AbsoluteSize.Y / s)
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHit)
	fitHit()

	local card: Card = {
		gui = gui,
		scale = scale,
		keyScale = keyScale,
		fill = fill,
		key = key,
		object = object,
		verb = verb,
		faders = faders,
		conns = {},
	}
	refreshText(card, prompt)

	local pressing = false
	table.insert(
		card.conns,
		hit.InputBegan:Connect(function(input)
			local t = input.UserInputType
			if
				prompt.ClickablePrompt
				and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch)
			then
				pressing = true
				prompt:InputHoldBegin()
			end
		end)
	)
	table.insert(
		card.conns,
		hit.InputEnded:Connect(function(input)
			local t = input.UserInputType
			if pressing and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
				pressing = false
				prompt:InputHoldEnd()
			end
		end)
	)
	table.insert(
		card.conns,
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			refreshText(card, prompt)
		end)
	)
	table.insert(
		card.conns,
		prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
			refreshText(card, prompt)
		end)
	)

	return card
end

local function dropCard(prompt: ProximityPrompt)
	local card = cards[prompt]
	if card == nil then
		return
	end
	cards[prompt] = nil
	for _, c in card.conns do
		c:Disconnect()
	end
	setShown(card, false, HIDE)
	task.delay(HIDE.Time, function()
		card.gui:Destroy()
	end)
end

local function showCard(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if cards[prompt] then
		dropCard(prompt)
	end
	local card = buildCard(prompt, inputType)
	if card == nil then
		return
	end
	cards[prompt] = card
	setShown(card, true, SHOW)
end

local function holdBegan(prompt: ProximityPrompt)
	local card = cards[prompt]
	if card == nil then
		return
	end
	TweenService:Create(card.keyScale, QUICK, { Scale = 0.92 }):Play()
	local info = TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear)
	TweenService:Create(card.fill, info, { Size = UDim2.fromScale(1, 1) }):Play()
end

local function holdEnded(prompt: ProximityPrompt)
	local card = cards[prompt]
	if card == nil then
		return
	end
	TweenService:Create(card.keyScale, QUICK, { Scale = 1 }):Play()
	TweenService:Create(card.fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(1, 0) }):Play()
end

--- A press lands: flash the key full and pop it, whether the prompt was held or not.
local function triggered(prompt: ProximityPrompt)
	local card = cards[prompt]
	if card == nil then
		return
	end
	card.fill.Size = UDim2.fromScale(1, 1)
	card.keyScale.Scale = 0.86
	TweenService:Create(card.keyScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	task.delay(0.12, function()
		if cards[prompt] == card then
			TweenService:Create(card.fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 0) }):Play()
		end
	end)
end

function PromptController.start()
	for _, d in Workspace:GetDescendants() do
		adopt(d)
	end
	Workspace.DescendantAdded:Connect(adopt)

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if owned[prompt] then
			showCard(prompt, inputType)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		dropCard(prompt)
	end)
	ProximityPromptService.PromptButtonHoldBegan:Connect(holdBegan)
	ProximityPromptService.PromptButtonHoldEnded:Connect(holdEnded)
	ProximityPromptService.PromptTriggered:Connect(triggered)
end

return PromptController
