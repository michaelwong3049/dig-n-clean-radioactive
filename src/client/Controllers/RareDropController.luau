--!strict
--[[
	RareDropController.luau — the announced drop on every screen (Config/RareDrop).

	PURE PRESENTATION. The server (RareDropService) decides what, where and who got it;
	this reads the ReplicatedStorage attributes it publishes and draws ONE line of text
	on a dark band that fades out at both ends, dressed exactly like the "You can afford
	a new Detector" hints (PurchaseHintController) and sitting in the same slot under the
	warp bar, so it reads as one more line of that stack. While it is up the hint stack
	steps down a row to make room (PurchaseHintController watches this Card).

	  WHEN A DROP GOES IN  "A Giga Pristine Legendary has spawned in Ooze Marsh!" for
	                       ANNOUNCE_HOLD (10s), then gone: nothing stays on screen while
	                       the drop is live, and a late joiner sees nothing. Its qualities
	                       come BEFORE the rarity, each word in its own colour
	                       (QUALITY_COLOR), the rarity in the rarity's colour.
	  WHEN IT ENDS         who claimed it, or that it blew up, or that it sank back.

	The line is a row of word labels, not one rich-text label, so an Anomaly's rarity
	word can run Rarity.ANOMALY_SPECTRUM across its own scrolling UIGradient without
	tinting the quality words beside it.

	Settings' RARE DROP ANNOUNCEMENTS (Config/Prefs rareDrops) filters what is drawn:
	"all", "mine" (only the line when YOU claim one) or "off". The drop's glow in the
	field is DigService's and shows either way.

	It never says WHERE in the stage. The drop's aura is lit for everyone
	(DigService), so the stage name plus the glow is the whole hint.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local RareDrop = require(Shared.Config.RareDrop)
local Rarity = require(Shared.Config.Rarity)
local Stages = require(Shared.Config.Stages)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)
local Prefs = require(script.Parent.Parent.Prefs)

local RareDropController = {}

local INK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local FONT = UIKit.Font.hero -- Gotham Black
-- Text and band match PurchaseHintController's rows (H, TextSize, BAND_*), so the
-- two read as one stack. Design px on the 1280x720 canvas.
local TEXT_SIZE = 22
local STROKE = 3
local LINE_Y = 84 -- the hint stack's top, just under the warp bar
local LINE_H = 30
local BAND_W = 520 -- narrowest band; a longer line widens it
local BAND_H = 36
local BAND_SHADE = 0.35
local BAND_FADE = 0.25
-- Room the band keeps past the words on each side, in its fading ends.
local BAND_PAD = 85
-- Widest the band gets; a longer line shrinks to fit inside it.
local MAX_W = 1000

-- Space between the line's words: a space's width at TEXT_SIZE, so the row of word
-- labels reads like the hints' single sentence.
local WORD_GAP = 6

-- The drop's buffs (Config/RareDrop.buffWords), each its own colour in the line, and
-- none of them a rarity's colour (Legendary is amber, Mythic red, Epic violet) so a
-- quality never reads as a second rarity. GIGA and HUGE never appear together.
local QUALITY_COLOR: { [string]: Color3 } = {
	GIGA = Color3.fromHex("FACC15"), -- gold
	HUGE = Color3.fromHex("FDE68A"), -- pale gold
	PRISTINE = Color3.fromHex("7DF9FF"), -- ice cyan
	IRRADIATED = Color3.fromHex("A3FF3C"), -- toxic lime
	FUSED = Color3.fromHex("FF6FB5"), -- hot pink
}

-- How much of the Anomaly spectrum spans a word at once, and how many gradient
-- keypoints carry it.
local RAINBOW_SPAN = 0.6
local RAINBOW_KEYS = 8

-- Springs in like a hint row (PurchaseHintController POP).
local IN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHOW = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OUT = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local ANNOUNCE_HOLD = 10
local OUTCOME_HOLD = 3.6

type Word = { text: string, color: Color3, rainbow: boolean? }

local ui: {
	card: CanvasGroup,
	cardScale: UIScale,
	row: Frame,
	fit: UIScale,
	layout: UIListLayout,
}? = nil

local cardToken = 0
local rainbowConn: RBXScriptConnection? = nil

local function colorOf(rarity: string?): Color3
	local ok, def = pcall(Rarity.get, rarity or "")
	return if ok and def then def.color else WHITE
end

local function stageName(stageId: number?): string
	local ok, def = pcall(Stages.get, stageId or 0)
	return if ok and def then def.name else "the field"
end

--- "A" or "An" for the word that follows it.
local function articleFor(word: string): string
	return if string.find(word, "^[AEIOUaeiou]") then "An" else "A"
end

--- "GIGA" -> "Giga".
local function titleCase(word: string): string
	return string.upper(string.sub(word, 1, 1)) .. string.lower(string.sub(word, 2))
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RareDrop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 96 -- just over the stage title (95), under the death screen (120)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	-- A CanvasGroup so the band and the outline fade with the words.
	local card = Instance.new("CanvasGroup")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, LINE_Y)
	card.Size = UDim2.fromOffset(MAX_W, BAND_H)
	card.BackgroundTransparency = 1
	card.GroupTransparency = 1
	card.Visible = false
	card.Parent = canvas
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	-- The band: dark in the middle, see-through at both ends, sized to the words.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.fromOffset(BAND_W, BAND_H)
	band.BackgroundColor3 = INK
	band.BackgroundTransparency = BAND_SHADE
	band.BorderSizePixel = 0
	band.Parent = card
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(BAND_FADE, 0),
		NumberSequenceKeypoint.new(1 - BAND_FADE, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = band

	-- The words, side by side and centred. `fit` shrinks the row when a long line
	-- (four buffs and a long stage name) would run past the widest band.
	local roomW = MAX_W - 2 * BAND_PAD
	local row = Instance.new("Frame")
	row.Name = "Line"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.5)
	row.Size = UDim2.fromOffset(roomW, LINE_H)
	row.Parent = card
	local fit = Instance.new("UIScale")
	fit.Parent = row
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, WORD_GAP)
	layout.Parent = row
	-- `fit` scales the row and its words alike, so this ratio does not move when it
	-- is applied: no feedback loop. Re-run whenever the words (or the screen) change.
	local function refit()
		local width = layout.AbsoluteContentSize.X
		local room = row.AbsoluteSize.X
		if width > 0 and room > 0 then
			fit.Scale = math.min(1, room / width)
			-- The words' width in design px once fitted; the band hugs it.
			local wordsW = math.min(roomW, width / room * roomW)
			band.Size = UDim2.fromOffset(math.max(BAND_W, wordsW + 2 * BAND_PAD), BAND_H)
		end
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refit)
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)

	ui = {
		card = card,
		cardScale = cardScale,
		row = row,
		fit = fit,
		layout = layout,
	}
	return gui
end

local function stopRainbow()
	if rainbowConn then
		rainbowConn:Disconnect()
		rainbowConn = nil
	end
end

local function startRainbow(gradient: UIGradient)
	stopRainbow()
	rainbowConn = RunService.Heartbeat:Connect(function()
		local phase = os.clock() / Rarity.ANOMALY_CYCLE
		local keys = table.create(RAINBOW_KEYS)
		for i = 0, RAINBOW_KEYS - 1 do
			local x = i / (RAINBOW_KEYS - 1)
			keys[i + 1] = ColorSequenceKeypoint.new(x, Rarity.anomalyHue(phase + x * RAINBOW_SPAN))
		end
		gradient.Color = ColorSequence.new(keys)
	end)
end

--- One word of the line, outlined like the rest of the HUD's hero text.
local function wordLabel(word: Word, order: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "Word"
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, LINE_H)
	label.Font = FONT
	label.TextSize = TEXT_SIZE
	label.Text = word.text
	-- White under the spectrum so its colours come through as they are.
	label.TextColor3 = if word.rainbow then WHITE else word.color
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = STROKE
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	if word.rainbow then
		local gradient = Instance.new("UIGradient")
		gradient.Parent = label
		startRainbow(gradient)
	end
	return label
end

--- Lay `words` out as the line and bring it up for `hold` seconds.
local function showLine(words: { Word }, hold: number)
	local u = ui
	if u == nil then
		return
	end
	cardToken += 1
	local mine = cardToken
	stopRainbow()
	for _, child in u.row:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for order, word in words do
		wordLabel(word, order).Parent = u.row
	end
	u.card.Visible = true
	u.card.GroupTransparency = 1
	u.cardScale.Scale = 0.6
	TweenService:Create(u.card, SHOW, { GroupTransparency = 0 }):Play()
	TweenService:Create(u.cardScale, IN, { Scale = 1 }):Play()
	task.delay(hold, function()
		if mine ~= cardToken then
			return
		end
		TweenService:Create(u.card, OUT, { GroupTransparency = 1 }):Play()
		task.delay(OUT.Time, function()
			if mine == cardToken then
				u.card.Visible = false
				stopRainbow()
			end
		end)
	end)
end

--- The whole line as one word in one colour (the outcome lines).
local function plainLine(text: string, color: Color3, rainbow: boolean, hold: number)
	showLine({ { text = text, color = color, rainbow = rainbow } }, hold)
end

--- A fresh drop went in: announce it. Only on a live change, never on join -- the
--- news is old by then.
local function onLive()
	if Prefs.get("rareDrops") ~= "all" then
		return
	end
	local endsAt = ReplicatedStorage:GetAttribute(RareDrop.ENDS_ATTR)
	if type(endsAt) ~= "number" or endsAt <= 0 then
		return
	end
	local rarity = ReplicatedStorage:GetAttribute(RareDrop.RARITY_ATTR)
	local stage = ReplicatedStorage:GetAttribute(RareDrop.STAGE_ATTR)
	local buffs = ReplicatedStorage:GetAttribute(RareDrop.BUFFS_ATTR)
	local tier = if type(rarity) == "string" then rarity else "Epic"
	Sfx.play("rareDrop")

	-- "A Giga Pristine Legendary has spawned in Ooze Marsh!": the qualities first, each
	-- in its own colour, then the rarity in the rarity's.
	local words: { Word } = {}
	if type(buffs) == "string" then
		for _, buff in string.split(buffs, " ") do
			if buff ~= "" then
				table.insert(words, { text = titleCase(buff), color = QUALITY_COLOR[buff] or WHITE })
			end
		end
	end
	table.insert(words, { text = tier, color = colorOf(tier), rainbow = tier == "Anomaly" })
	table.insert(words, 1, { text = articleFor(words[1].text), color = WHITE })
	table.insert(words, {
		text = `has spawned in {stageName(if type(stage) == "number" then stage else nil)}!`,
		color = WHITE,
	})
	showLine(words, ANNOUNCE_HOLD)
end

local function onOutcome()
	local outcome = ReplicatedStorage:GetAttribute(RareDrop.OUTCOME_ATTR)
	if type(outcome) ~= "string" then
		return
	end
	local rarity = ReplicatedStorage:GetAttribute(RareDrop.RARITY_ATTR)
	local tier = if type(rarity) == "string" then rarity else "Rare"
	local who = string.match(outcome, "^claimed:(.+)$")
	local you = who ~= nil and who == Players.LocalPlayer.DisplayName
	local show = Prefs.get("rareDrops")
	if show == "off" or (show == "mine" and not you) then
		return
	end
	if who then
		plainLine(`{if you then "You" else who} got the {tier}!`, colorOf(tier), tier == "Anomaly", OUTCOME_HOLD)
	elseif outcome == "blown" then
		plainLine(`The {tier} blew up in the ground!`, Color3.fromHex("FF6B3D"), false, OUTCOME_HOLD)
	else
		plainLine(`The {tier} sank back unclaimed`, Color3.fromHex("9AA3AE"), false, OUTCOME_HOLD)
	end
end

function RareDropController.start()
	build().Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- The service writes STAGE and RARITY before ENDS, so by the time ENDS changes the
	-- other two already say the new drop.
	ReplicatedStorage:GetAttributeChangedSignal(RareDrop.ENDS_ATTR):Connect(onLive)
	-- ENDED_AT changes on every end, even the same outcome twice running; OUTCOME is
	-- written first.
	ReplicatedStorage:GetAttributeChangedSignal(RareDrop.ENDED_AT_ATTR):Connect(onOutcome)
end

return RareDropController
