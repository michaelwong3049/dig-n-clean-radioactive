--!strict
--[[
	StageBannerController.luau — the name of the place drops in when you enter it.

	Config/Stages has carried a `name` for all six stages since the first commit and
	nothing has ever shown it. Crossing a stage seam gave you a fog tween
	(AtmosphereController) and a floor colour and no words. This is the words: an
	area title over the world near the top of the screen — "STAGE 3" with a thin
	rule either side, "FALLOUT FIELDS" under it — that fades in from slightly large,
	holds a beat, and fades out drifting up.

	NO CARD BEHIND IT (the user picked this over the old dark pill from a round of
	mockups: option 2, "area title", in the HUD's own Gotham Black, smaller). The
	name is UIKit.C.text with the usual heavy outline; only the eyebrow and its rules
	carry the stage colour, with a thicker outline than UIKit gives text that size so
	the tan stages still read against a tan sky. Everything sits in one CanvasGroup
	so the outlines and shadows fade with the words.

	IT KEEPS A FRAME NAMED "Panel". AuraWarningController finds the banner by that
	name to stay clear of it; here it is just the invisible box around the title.
	While the tutorial's banner is up (same spot, TutorialController) the title drops
	below it instead of landing on top of it.

	COSTS NOTHING NEW ON THE WIRE. ExposureState already carries `stageId` every
	tick (ExposureService) and AtmosphereController already reads it; this is a
	second reader of the same field. Pure presentation — it decides nothing.

	NOT GREEN, EVER. The obvious tint is each stage's `ooze` accent, but that is
	acid green for stages 1-3, and green in the HUD means exactly one thing (PLAN
	§14, and see CashController's header for the last file that hit this wall and
	chose amber). The tint is `def.color` — the stage's earthy ground colour,
	punched up for legibility — which also happens to trace the map's own "the
	colour turns at Stage 4" progression: warm earth 1-4, rose at 5, violet at 6.

	Base camp is not a stage and gets no card — crossing back into it just dismisses
	whatever is showing.

	A SITE CAMP DOES GET ONE (Config/Camps — Toxic Twilight): "CAMP / Toxic Twilight",
	tinted to the camp's first awning colour, off ExposureState's `campId`. The first
	time you reach a camp the eyebrow reads CAMP UNLOCKED instead — CampState's
	`unlocked` says so, and whichever of the two remotes lands first, the card ends up
	saying it (see `unlockedAt`).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Camps = require(Shared.Config.Camps)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local StageBannerController = {}

-- Design px on the 1280x720 canvas. The eyebrow's text starts at y 104, well clear of
-- the Roblox topbar (IgnoreGuiInset is on) and of the aura warning at y 16.
local TOP = 98
local PAD = 6 -- inside the CanvasGroup, so the outlines and shadow are not clipped
local WIDTH = 820 -- wider than the longest name, "THE EXCLUSION BELT"
local EYEBROW_H = 22
local NAME_Y = PAD + EYEBROW_H + 1
local NAME_H = 46
local HEIGHT = NAME_Y + NAME_H + PAD

local EYEBROW_FONT = UIKit.Font.title
local EYEBROW_SIZE = 17
local EYEBROW_STROKE = 2 -- UIKit's 1.5 for this size lets tan-on-tan wash out
local NAME_SIZE = UIKit.TextSize.hero

local RULE_W = 110
local RULE_H = 3
local RULE_GAP = 12 -- between the eyebrow's text and each rule

local GROW = 1.12 -- the scale it fades in from
local DRIFT = 12 -- how far it rises as it fades out
local TUTORIAL_GAP = 10

local IN = TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local RULE_IN = TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.2)
local OUT = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOLD = 2.6

--- Where the card last settled: "stage:<id>", "camp:<id>", or nil for Base Camp (no
--- card). "?" so the first ExposureState always applies.
local currentWhere: string? = "?"
local token = 0

--- Camp key -> os.clock() of its CampState `unlocked`, so a camp card shown just after
--- (or just before) the unlock reads CAMP UNLOCKED rather than plain CAMP.
local unlockedAt: { [string]: number } = {}
local UNLOCK_FRESH = 4

local ui: {
	canvas: Frame,
	panel: Frame,
	grow: UIScale,
	group: CanvasGroup,
	eyebrow: TextLabel,
	ruleL: Frame,
	ruleR: Frame,
	name: TextLabel,
}? = nil

--- The fade-out's rise. A new card sets Position outright, which a tween still running
--- would keep overwriting, so it is cancelled by hand.
local drift: Tween? = nil

--- The stage's ground colour, pulled to a consistent brightness so the near-black
--- Exclusion Belt and the near-white Reactor Grounds both read as an accent.
local function accentFor(hex: string): Color3
	local h, s, v = Color3.fromHex(hex):ToHSV()
	return Color3.fromHSV(h, math.clamp(s * 1.4, 0.35, 0.85), math.clamp(v, 0.5, 0.9))
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "StageBanner"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95 -- under the death screen (DeathScreen, 120), over the rest
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local canvas = UIKit.canvas(gui)

	-- Invisible: the box AuraWarningController measures. Anchored at its centre so the
	-- fade-in shrinks toward the middle of the title rather than toward its top edge.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0, TOP + HEIGHT / 2)
	panel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = canvas

	local grow = Instance.new("UIScale")
	grow.Name = "Grow"
	grow.Parent = panel

	-- A CanvasGroup so the words, their outlines and shadows, and the rules fade as one:
	-- a UIStroke does not fade with TextTransparency.
	local group = Instance.new("CanvasGroup")
	group.Name = "Group"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Parent = panel

	local eyebrow = UIKit.label(group, {
		name = "Eyebrow",
		position = UDim2.fromOffset(0, PAD),
		size = UDim2.new(1, 0, 0, EYEBROW_H),
		font = EYEBROW_FONT,
		textSize = EYEBROW_SIZE,
		xAlign = Enum.TextXAlignment.Center,
	})
	local eyebrowStroke = eyebrow:FindFirstChildOfClass("UIStroke")
	if eyebrowStroke then
		eyebrowStroke.Thickness = EYEBROW_STROKE
	end

	-- The rules either side of the eyebrow, placed per card against its text width
	-- (showCard) and grown outward from zero.
	local function rule(name: string, anchorX: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(anchorX, 0.5)
		frame.Size = UDim2.fromOffset(0, RULE_H)
		frame.BorderSizePixel = 0
		frame.Parent = group
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = UIKit.C.outline
		stroke.Thickness = 1.5
		stroke.Parent = frame
		return frame
	end
	local ruleL = rule("RuleL", 1)
	local ruleR = rule("RuleR", 0)

	local name = UIKit.label(group, {
		name = "NameLabel", -- NOT "Name": a child called "Name" is shadowed by the
		-- Instance property, unreachable by path. Every reader here uses the captured
		-- reference, but naming it safely is free.
		position = UDim2.fromOffset(0, NAME_Y),
		size = UDim2.new(1, 0, 0, NAME_H),
		font = UIKit.Font.hero,
		textSize = NAME_SIZE,
		color = UIKit.C.text,
		xAlign = Enum.TextXAlignment.Center,
	})

	ui = {
		canvas = canvas,
		panel = panel,
		grow = grow,
		group = group,
		eyebrow = eyebrow,
		ruleL = ruleL,
		ruleR = ruleR,
		name = name,
	}
	return gui
end

--- Where the title's top edge goes: TOP, or just under the tutorial's banner while that
--- is up, since it sits in the same spot.
local function topY(): number
	if ui == nil then
		return TOP
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local scale = UIKit.canvasScale(ui.canvas)
	local tutorial = playerGui and playerGui:FindFirstChild("TutorialHud")
	local banner = tutorial and tutorial:FindFirstChild("Banner", true)
	if scale > 0 and banner and banner:IsA("GuiObject") and banner.Visible and (tutorial :: ScreenGui).Enabled then
		local bottom = (banner.AbsolutePosition.Y + banner.AbsoluteSize.Y - ui.canvas.AbsolutePosition.Y) / scale
		return math.max(TOP, bottom + TUTORIAL_GAP)
	end
	return TOP
end

local function stopDrift()
	if drift then
		drift:Cancel()
		drift = nil
	end
end

--- Fade out rising DRIFT px, then hide — unless a newer card has started by then.
local function fadeOut(mine: number)
	if ui == nil then
		return
	end
	local u = ui
	stopDrift()
	TweenService:Create(u.group, OUT, { GroupTransparency = 1 }):Play()
	drift = TweenService:Create(u.panel, OUT, { Position = u.panel.Position - UDim2.fromOffset(0, DRIFT) })
	drift:Play()
	task.delay(OUT.Time, function()
		if ui and mine == token then
			ui.panel.Visible = false
		end
	end)
end

local function hide()
	token += 1
	if ui and ui.panel.Visible then
		fadeOut(token)
	end
end

local function showCard(eyebrow: string, title: string, accent: Color3)
	if ui == nil then
		return
	end
	local u = ui

	u.eyebrow.Text = eyebrow
	u.eyebrow.TextColor3 = accent
	u.name.Text = string.upper(title)
	u.ruleL.BackgroundColor3 = accent
	u.ruleR.BackgroundColor3 = accent

	-- Each rule starts RULE_GAP out from the eyebrow's text, on the centre line of its row.
	local half = TextService:GetTextSize(eyebrow, EYEBROW_SIZE, EYEBROW_FONT, Vector2.new(4000, 200)).X / 2
	local ruleY = PAD + EYEBROW_H / 2
	u.ruleL.Position = UDim2.new(0.5, -(half + RULE_GAP), 0, ruleY)
	u.ruleR.Position = UDim2.new(0.5, half + RULE_GAP, 0, ruleY)

	token += 1
	local mine = token

	stopDrift()
	u.panel.Position = UDim2.new(0.5, 0, 0, topY() + HEIGHT / 2)
	u.grow.Scale = GROW
	u.group.GroupTransparency = 1
	u.ruleL.Size = UDim2.fromOffset(0, RULE_H)
	u.ruleR.Size = UDim2.fromOffset(0, RULE_H)
	u.panel.Visible = true

	TweenService:Create(u.group, IN, { GroupTransparency = 0 }):Play()
	TweenService:Create(u.grow, IN, { Scale = 1 }):Play()
	TweenService:Create(u.ruleL, RULE_IN, { Size = UDim2.fromOffset(RULE_W, RULE_H) }):Play()
	TweenService:Create(u.ruleR, RULE_IN, { Size = UDim2.fromOffset(RULE_W, RULE_H) }):Play()

	task.delay(IN.Time + HOLD, function()
		if mine == token then
			fadeOut(mine)
		end
	end)
end

local function showStage(stageId: number)
	local ok, def = pcall(Stages.get, stageId)
	if ok and def then
		showCard(`STAGE {stageId}`, def.name, accentFor(def.color))
	end
end

local function showCamp(campId: number)
	local def = Camps.byId(campId)
	if def == nil then
		return
	end
	local fresh = os.clock() - (unlockedAt[def.key] or -math.huge) < UNLOCK_FRESH
	local tint = if def.palette then def.palette.awnings[1] else "A855FF"
	showCard(if fresh then "CAMP UNLOCKED" else "CAMP", def.name, accentFor(tint))
end

--- SETTLE BEFORE ACTING. `StageService.stageOf` can read nil for a tick or two while a
--- player is crossing a seam or dropping onto a plate after a teleport, so a raw
--- edge-trigger produces a stage->nil->stage flicker that slides the card in, out and in
--- again. Every change starts a short timer instead; only the value still current when it
--- fires gets a show()/hide(). 0.22s is below notice for the card's own appearance and
--- long enough to swallow the blip.
local pendingToken = 0

local function applyFor(stageId: number?, campId: number?)
	local where = if stageId then `stage:{stageId}` elseif campId then `camp:{campId}` else nil
	if where == currentWhere then
		return
	end
	currentWhere = where

	pendingToken += 1
	local mine = pendingToken
	task.delay(0.22, function()
		if mine ~= pendingToken then
			return -- a newer transition superseded this one
		end
		if stageId then
			showStage(stageId)
		elseif campId then
			showCamp(campId)
		else
			hide()
		end
	end)
end

function StageBannerController.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("ExposureState").OnClientEvent:Connect(function(state)
		applyFor(state.stageId, state.campId)
	end)

	-- A camp reached for the first time. If the camp's card is already up (or settling)
	-- this re-announces it as unlocked; if it has not arrived yet, showCamp reads
	-- `unlockedAt` when it does.
	Net.get("CampState").OnClientEvent:Connect(function(state)
		if type(state) ~= "table" or type(state.unlocked) ~= "string" then
			return
		end
		local def = Camps.get(state.unlocked)
		if def == nil then
			return
		end
		unlockedAt[def.key] = os.clock()
		if currentWhere == `camp:{def.id}` then
			pendingToken += 1 -- supersede a settle timer that would show plain CAMP
			showCamp(def.id)
		end
	end)

	-- Respawn: ExposureState does not re-fire immediately, and a card left up from
	-- before the blackout would hang there. Wipe it and let the next tick re-announce
	-- wherever the player actually wakes up (nothing, if that is camp).
	player.CharacterAdded:Connect(function()
		currentWhere = "?"
		token += 1
		pendingToken += 1 -- cancel any settle timer mid-flight
		stopDrift()
		if ui then
			ui.panel.Visible = false
			ui.group.GroupTransparency = 1
		end
	end)
end

return StageBannerController
