--!strict
--[[
	RareDropController.luau — the announced drop on every screen (Config/RareDrop).

	PURE PRESENTATION. The server (RareDropService) decides what, where and who got it;
	this reads the ReplicatedStorage attributes it publishes and draws ONE line of text,
	no box (the user's pick off the font mockup: Gotham Black, whole line in the
	rarity's colour, dark outline):

	  WHEN A DROP GOES IN  "A Legendary has appeared in Ooze Marsh!" for ANNOUNCE_HOLD
	                       (10s), then gone: nothing stays on screen while the drop is
	                       live, and a late joiner sees nothing.
	  WHEN IT ENDS         who claimed it, or that it blew up, or that it sank back.

	An Anomaly has no single colour: its line runs Rarity.ANOMALY_SPECTRUM across a
	UIGradient that scrolls while it is up.

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

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)
local FONT = UIKit.Font.hero -- Gotham Black
local TEXT_SIZE = 38
local STROKE = 3

-- The line sits high, above the Violet Aurora's (0.24) so the two never land on top
-- of each other. Design px on the 1280x720 canvas.
local LINE_Y = 0.14
local LINE_W = 1200
local LINE_H = 52

-- The drop's buffs (Config/RareDrop), one row of words over the line, each in the
-- colour the wash stamp and stand sticker give it.
local BUFF_SIZE = 28
local BUFF_H = 36
local BUFF_GAP = "  +  "
local BUFF_COLOR: { [string]: Color3 } = {
	GIGA = Color3.fromHex("FACC15"),
	OVERSIZED = Color3.fromHex("F59E0B"),
	PRISTINE = Color3.fromHex("7DF9FF"),
	IRRADIATED = Color3.fromHex("A3FF3C"),
	FUSED = Color3.fromHex("FF8A3D"),
}

-- How much of the Anomaly spectrum spans the line at once, and how many gradient
-- keypoints carry it.
local RAINBOW_SPAN = 0.6
local RAINBOW_KEYS = 8

local IN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OUT = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local ANNOUNCE_HOLD = 10
local OUTCOME_HOLD = 3.6

local ui: {
	card: CanvasGroup,
	cardScale: UIScale,
	line: TextLabel,
	buffs: TextLabel,
	rainbow: UIGradient,
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

--- "A Legendary", "An Epic", "An Anomaly".
local function withArticle(rarity: string): string
	return (if string.find(rarity, "^[AEIOU]") then "An " else "A ") .. rarity
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RareDrop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 96 -- just over the stage title (95), under the death screen (120)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	-- A CanvasGroup so the outline fades with the words.
	local card = Instance.new("CanvasGroup")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, LINE_Y)
	card.Size = UDim2.fromOffset(LINE_W, BUFF_H + LINE_H + 16)
	card.BackgroundTransparency = 1
	card.GroupTransparency = 1
	card.Visible = false
	card.Parent = canvas
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.BackgroundTransparency = 1
	line.AnchorPoint = Vector2.new(0.5, 1)
	line.Position = UDim2.new(0.5, 0, 1, -8)
	line.Size = UDim2.fromOffset(LINE_W, LINE_H)
	line.Font = FONT
	line.TextSize = TEXT_SIZE
	line.TextColor3 = WHITE
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = STROKE
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = line

	local buffs = Instance.new("TextLabel")
	buffs.Name = "Buffs"
	buffs.BackgroundTransparency = 1
	buffs.AnchorPoint = Vector2.new(0.5, 0)
	buffs.Position = UDim2.new(0.5, 0, 0, 8)
	buffs.Size = UDim2.fromOffset(LINE_W, BUFF_H)
	buffs.Font = FONT
	buffs.TextSize = BUFF_SIZE
	buffs.TextColor3 = WHITE
	buffs.RichText = true
	buffs.TextXAlignment = Enum.TextXAlignment.Center
	buffs.Visible = false
	buffs.Parent = card
	local buffStroke = Instance.new("UIStroke")
	buffStroke.Color = INK
	buffStroke.Thickness = STROKE
	buffStroke.LineJoinMode = Enum.LineJoinMode.Round
	buffStroke.Parent = buffs

	-- Off unless the line is an Anomaly's; the text is white under it so the
	-- gradient's colours come through as they are.
	local rainbow = Instance.new("UIGradient")
	rainbow.Enabled = false
	rainbow.Parent = line

	ui = {
		card = card,
		cardScale = cardScale,
		line = line,
		buffs = buffs,
		rainbow = rainbow,
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

--- "GIGA PRISTINE" -> the buff row's rich text, each word in its own colour.
local function buffRow(words: string): string
	local parts = {}
	for _, word in string.split(words, " ") do
		if word ~= "" then
			local color = BUFF_COLOR[word] or WHITE
			table.insert(parts, `<font color="#{color:ToHex()}">{word}</font>`)
		end
	end
	return table.concat(parts, BUFF_GAP)
end

--- `rainbow` = an Anomaly's line: white text under the scrolling spectrum. `buffs` =
--- the drop's buff words for the row above it (announcements only).
local function showLine(text: string, color: Color3, rainbow: boolean, hold: number, buffs: string?)
	local u = ui
	if u == nil then
		return
	end
	cardToken += 1
	local mine = cardToken
	u.line.Text = text
	u.buffs.Visible = buffs ~= nil and buffs ~= ""
	u.buffs.Text = if buffs then buffRow(buffs) else ""
	u.line.TextColor3 = if rainbow then WHITE else color
	u.rainbow.Enabled = rainbow
	if rainbow then
		startRainbow(u.rainbow)
	else
		stopRainbow()
	end
	u.card.Visible = true
	u.card.GroupTransparency = 1
	u.cardScale.Scale = 1.12
	TweenService:Create(u.card, IN, { GroupTransparency = 0 }):Play()
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
	showLine(
		`{withArticle(tier)} has appeared in {stageName(if type(stage) == "number" then stage else nil)}!`,
		colorOf(tier),
		tier == "Anomaly",
		ANNOUNCE_HOLD,
		if type(buffs) == "string" then buffs else nil
	)
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
		showLine(`{if you then "You" else who} got the {tier}!`, colorOf(tier), tier == "Anomaly", OUTCOME_HOLD)
	elseif outcome == "blown" then
		showLine(`The {tier} blew up in the ground!`, Color3.fromHex("FF6B3D"), false, OUTCOME_HOLD)
	else
		showLine(`The {tier} sank back unclaimed`, Color3.fromHex("9AA3AE"), false, OUTCOME_HOLD)
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
