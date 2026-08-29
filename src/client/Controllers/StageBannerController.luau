--!strict
--[[
	StageBannerController.luau — the name of the place drops in when you enter it.

	Config/Stages has carried a `name` for all six stages since the first commit and
	nothing has ever shown it. Crossing a stage seam gave you a fog tween
	(AtmosphereController) and a floor colour and no words. This is the words: a
	title card that slides in at the top of the screen — "STAGE 3 / Fallout Fields"
	— tinted to that stage's own ground colour, holds a beat, slides back out.

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
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local StageBannerController = {}

local SHOWN = UDim2.new(0.5, 0, 0, 34) -- clear of the Roblox topbar (IgnoreGuiInset is on)
local HIDDEN = UDim2.new(0.5, 0, 0, -110) -- fully off the top edge
local PANEL_TRANSPARENCY = 0.12

local IN = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOLD = 2.6

--- -1 so the first ExposureState always applies. nil is base camp (no card).
local currentStage: number? = -1
local token = 0

local ui: {
	panel: Frame,
	stroke: UIStroke,
	eyebrow: TextLabel,
	name: TextLabel,
}? = nil

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
	gui.DisplayOrder = 95 -- under HudController's blackout curtain (100), over the rest
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel, stroke = UIKit.panel(gui, {
		name = "Panel",
		size = UDim2.fromOffset(460, 64),
		position = HIDDEN,
		anchorPoint = Vector2.new(0.5, 0),
		color = UIKit.C.panel,
		transparency = 1,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		visible = false,
	})
	stroke.Transparency = 1

	local eyebrow = UIKit.label(panel, {
		name = "Eyebrow",
		position = UDim2.fromOffset(0, 9),
		size = UDim2.new(1, 0, 0, 14),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		xAlign = Enum.TextXAlignment.Center,
	})
	eyebrow.TextTransparency = 1

	local name = UIKit.label(panel, {
		name = "NameLabel", -- NOT "Name": a child called "Name" is shadowed by the
		-- Instance property, unreachable by path. Every reader here uses the captured
		-- reference, but naming it safely is free.
		position = UDim2.fromOffset(0, 24),
		size = UDim2.new(1, 0, 0, 32),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.title,
		color = UIKit.C.text,
		xAlign = Enum.TextXAlignment.Center,
	})
	name.TextTransparency = 1

	ui = { panel = panel, stroke = stroke, eyebrow = eyebrow, name = name }
	return gui
end

--- Tween the four pieces to `t` (0 shown, 1 gone) and the panel to `pos`.
local function tweenTo(info: TweenInfo, pos: UDim2, t: number)
	if ui == nil then
		return
	end
	local u = ui
	TweenService:Create(u.panel, info, {
		Position = pos,
		BackgroundTransparency = if t >= 1 then 1 else PANEL_TRANSPARENCY,
	}):Play()
	TweenService:Create(u.stroke, info, { Transparency = t }):Play()
	TweenService:Create(u.eyebrow, info, { TextTransparency = t }):Play()
	TweenService:Create(u.name, info, { TextTransparency = t }):Play()
end

local function hide()
	token += 1
	if ui and ui.panel.Visible then
		tweenTo(OUT, HIDDEN, 1)
		local mine = token
		task.delay(OUT.Time, function()
			if ui and mine == token then
				ui.panel.Visible = false
			end
		end)
	end
end

local function show(stageId: number)
	if ui == nil then
		return
	end
	local u = ui

	local ok, def = pcall(Stages.get, stageId)
	if not (ok and def) then
		return
	end

	local accent = accentFor(def.color)
	u.eyebrow.Text = `STAGE {stageId}`
	u.eyebrow.TextColor3 = accent
	u.name.Text = def.name
	u.stroke.Color = accent

	token += 1
	local mine = token

	u.panel.Position = HIDDEN
	u.panel.BackgroundTransparency = 1
	u.stroke.Transparency = 1
	u.eyebrow.TextTransparency = 1
	u.name.TextTransparency = 1
	u.panel.Visible = true

	tweenTo(IN, SHOWN, 0)

	task.delay(HOLD, function()
		if mine ~= token then
			return
		end
		tweenTo(OUT, HIDDEN, 1)
		task.delay(OUT.Time, function()
			if ui and mine == token then
				ui.panel.Visible = false
			end
		end)
	end)
end

--- SETTLE BEFORE ACTING. `StageService.stageOf` can read nil for a tick or two while a
--- player is crossing a seam or dropping onto a plate after a teleport, so a raw
--- edge-trigger produces a stage->nil->stage flicker that slides the card in, out and in
--- again. Every change starts a short timer instead; only the value still current when it
--- fires gets a show()/hide(). 0.22s is below notice for the card's own appearance and
--- long enough to swallow the blip.
local pendingToken = 0

local function applyFor(stageId: number?)
	if stageId == currentStage then
		return
	end
	currentStage = stageId

	pendingToken += 1
	local mine = pendingToken
	task.delay(0.22, function()
		if mine ~= pendingToken then
			return -- a newer transition superseded this one
		end
		if stageId == nil then
			hide()
		else
			show(stageId)
		end
	end)
end

function StageBannerController.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("ExposureState").OnClientEvent:Connect(function(state)
		applyFor(state.stageId)
	end)

	-- Respawn: ExposureState does not re-fire immediately, and a card left up from
	-- before the blackout would hang there. Wipe it and let the next tick re-announce
	-- wherever the player actually wakes up (nothing, if that is camp).
	player.CharacterAdded:Connect(function()
		currentStage = -1
		token += 1
		pendingToken += 1 -- cancel any settle timer mid-flight
		if ui then
			ui.panel.Visible = false
			ui.panel.Position = HIDDEN
		end
	end)
end

return StageBannerController
