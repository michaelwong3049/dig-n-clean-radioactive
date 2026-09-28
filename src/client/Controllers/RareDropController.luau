--!strict
--[[
	RareDropController.luau — the announced drop on every screen (Config/RareDrop).

	PURE PRESENTATION. The server (RareDropService) decides what, where and who got it;
	this reads the ReplicatedStorage attributes it publishes and draws ONE card:

	  WHEN A DROP GOES IN  "LEGENDARY DROP!" in the rarity's colour, "Surfaced in Ooze
	                       Marsh -- first to dig it keeps it" under it. It pops up for
	                       ANNOUNCE_HOLD (10s, the user's call) and is gone: nothing stays
	                       on screen while the drop is live, and a late joiner sees nothing.
	  WHEN IT ENDS         who claimed it, or that it blew up, or that it sank back.

	It never says WHERE in the stage. The drop's aura is lit for everyone
	(DigService), so the stage name plus the glow is the whole hint.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local RareDrop = require(Shared.Config.RareDrop)
local Rarity = require(Shared.Config.Rarity)
local Stages = require(Shared.Config.Stages)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)

local RareDropController = {}

local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)
local TITLE_FONT = Enum.Font.LuckiestGuy
local TEXT_FONT = Enum.Font.FredokaOne

-- The card sits a little under the Violet Aurora's (0.24) so the two never land on
-- top of each other. Design px on the 1280x720 canvas.
local CARD_Y = 0.34
local CARD_W = 760
local CARD_H = 130

local IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OUT = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local ANNOUNCE_HOLD = 10
local OUTCOME_HOLD = 3.6

local ui: {
	card: CanvasGroup,
	cardScale: UIScale,
	title: TextLabel,
	sub: TextLabel,
}? = nil

local cardToken = 0

local function ink(label: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
end

local function text(parent: Instance, name: string, font: Enum.Font, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = WHITE
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = parent
	return label
end

local function colorOf(rarity: string?): Color3
	local ok, def = pcall(Rarity.get, rarity or "")
	return if ok and def then def.color else WHITE
end

local function stageName(stageId: number?): string
	local ok, def = pcall(Stages.get, stageId or 0)
	return if ok and def then def.name else "the field"
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RareDrop"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 96 -- just over the stage title (95), under the death screen (120)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	-- A CanvasGroup so the outlines fade with the words.
	local card = Instance.new("CanvasGroup")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, CARD_Y)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundTransparency = 1
	card.GroupTransparency = 1
	card.Visible = false
	card.Parent = canvas
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card

	local title = text(card, "Title", TITLE_FONT, 50)
	title.Size = UDim2.new(1, 0, 0, 62)
	title.Position = UDim2.fromOffset(0, 6)
	ink(title, 4.5)

	local sub = text(card, "Subtitle", TEXT_FONT, 26)
	sub.Size = UDim2.new(1, 0, 0, 34)
	sub.Position = UDim2.fromOffset(0, 72)
	ink(sub, 3)


	ui = {
		card = card,
		cardScale = cardScale,
		title = title,
		sub = sub,
	}
	return gui
end

local function showCard(title: string, subtitle: string, color: Color3, hold: number)
	local u = ui
	if u == nil then
		return
	end
	cardToken += 1
	local mine = cardToken
	u.title.Text = title
	u.title.TextColor3 = color
	u.sub.Text = subtitle
	u.card.Visible = true
	u.card.GroupTransparency = 1
	u.cardScale.Scale = 0.6
	TweenService:Create(u.card, IN, { GroupTransparency = 0 }):Play()
	TweenService:Create(u.cardScale, IN, { Scale = 1 }):Play()
	task.delay(hold, function()
		if mine ~= cardToken then
			return
		end
		TweenService:Create(u.card, OUT, { GroupTransparency = 1 }):Play()
		TweenService:Create(u.cardScale, OUT, { Scale = 1.08 }):Play()
		task.delay(OUT.Time, function()
			if mine == cardToken then
				u.card.Visible = false
			end
		end)
	end)
end

--- A fresh drop went in: announce it. Only on a live change, never on join -- the
--- news is old by then.
local function onLive()
	local endsAt = ReplicatedStorage:GetAttribute(RareDrop.ENDS_ATTR)
	if type(endsAt) ~= "number" or endsAt <= 0 then
		return
	end
	local rarity = ReplicatedStorage:GetAttribute(RareDrop.RARITY_ATTR)
	local stage = ReplicatedStorage:GetAttribute(RareDrop.STAGE_ATTR)
	local tier = if type(rarity) == "string" then rarity else "Epic"
	Sfx.play("rareDrop")
	showCard(
		`{string.upper(tier)} DROP!`,
		`Surfaced in {stageName(if type(stage) == "number" then stage else nil)} — first to dig it keeps it!`,
		colorOf(tier),
		ANNOUNCE_HOLD
	)
end

local function onOutcome()
	local outcome = ReplicatedStorage:GetAttribute(RareDrop.OUTCOME_ATTR)
	if type(outcome) ~= "string" then
		return
	end
	local rarity = ReplicatedStorage:GetAttribute(RareDrop.RARITY_ATTR)
	local tier = string.upper(if type(rarity) == "string" then rarity else "rare")
	local color = colorOf(if type(rarity) == "string" then rarity else nil)
	local who = string.match(outcome, "^claimed:(.+)$")
	if who then
		local you = who == Players.LocalPlayer.DisplayName
		showCard(if you then "YOU GOT IT!" else `{string.upper(who)} GOT IT!`, `The {tier} drop has been claimed`, color, OUTCOME_HOLD)
	elseif outcome == "blown" then
		showCard("KABOOM!", `The {tier} drop blew up in the ground`, Color3.fromHex("FF6B3D"), OUTCOME_HOLD)
	else
		showCard("TOO LATE", `The {tier} drop sank back unclaimed`, Color3.fromHex("9AA3AE"), OUTCOME_HOLD)
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
