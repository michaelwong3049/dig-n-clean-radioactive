--[[
	HudController.lua — the rad meter the player actually plays against.

	The debug HUD shows every number at once because it is an instrument panel. This
	one shows almost none of them, because PLAN §3.1 escalates by FEEL, not by readout:

	  0-50%   nothing. Clean play, no UI shouting at you.
	  50-80%  the screen greens at the edges, and the click bed comes up.
	  80-99%  vision distorts, the world tilts, the meter stops being ignorable.
	  100%    blackout.

	ONE COLOUR RULE (PLAN §14): exposure is GREEN, suit failure is WHITE, and they never
	share a shade. Green means "the meter is filling". White means "your suit is coming
	apart" — a different category of dying, not a worse degree of the same one. White is
	used exactly once in this entire game, which is why it will read instantly forever.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

local Hud = {}

local GREEN = Color3.fromHex("8FE04A")
local WHITE = Color3.fromHex("FFFFFF")
local DIM = Color3.fromHex("7C8874")

local state = {
	exposureFrac = 0,
	net = 0,
	failing = false,
	inShower = false,
	zoneName = "Base Camp",
	downed = false,
}

local ui = {}
local shakeSeed = 0

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ── Build ───────────────────────────────────────────────────────────

--- Four gradient edges standing in for a vignette. No image asset needed, and it
--- tints per state, which a baked PNG could not.
local function edge(parent: Instance, name: string, size: UDim2, position: UDim2, rotation: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = GREEN
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = 2
	frame.Parent = parent

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame

	return frame
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "RadHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	ui.edges = {
		edge(gui, "EdgeTop", UDim2.new(1, 0, 0, 190), UDim2.fromScale(0, 0), 270),
		edge(gui, "EdgeBottom", UDim2.new(1, 0, 0, 190), UDim2.new(0, 0, 1, -190), 90),
		edge(gui, "EdgeLeft", UDim2.new(0, 260, 1, 0), UDim2.fromScale(0, 0), 180),
		edge(gui, "EdgeRight", UDim2.new(0, 260, 1, 0), UDim2.new(1, -260, 0, 0), 0),
	}

	-- The meter. Bottom-left, out of the way of the sweep dial.
	local panel = Instance.new("Frame")
	panel.Name = "Meter"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 18, 1, -18)
	panel.Size = UDim2.fromOffset(240, 46)
	panel.BackgroundTransparency = 1
	panel.ZIndex = 4
	panel.Parent = gui

	ui.caption = Instance.new("TextLabel")
	ui.caption.Size = UDim2.new(1, 0, 0, 16)
	ui.caption.BackgroundTransparency = 1
	ui.caption.Font = Enum.Font.GothamBold
	ui.caption.TextSize = 13
	ui.caption.TextXAlignment = Enum.TextXAlignment.Left
	ui.caption.TextColor3 = DIM
	ui.caption.TextStrokeTransparency = 0.6
	ui.caption.Text = "RADS"
	ui.caption.ZIndex = 4
	ui.caption.Parent = panel

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(0, 20)
	track.Size = UDim2.new(1, 0, 0, 12)
	track.BackgroundColor3 = Color3.fromHex("14180F")
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.ZIndex = 4
	track.Parent = panel

	ui.fill = Instance.new("Frame")
	ui.fill.Size = UDim2.fromScale(0, 1)
	ui.fill.BackgroundColor3 = GREEN
	ui.fill.BorderSizePixel = 0
	ui.fill.ZIndex = 5
	ui.fill.Parent = track

	ui.readout = Instance.new("TextLabel")
	ui.readout.Position = UDim2.fromOffset(0, 33)
	ui.readout.Size = UDim2.new(1, 0, 0, 14)
	ui.readout.BackgroundTransparency = 1
	ui.readout.Font = Enum.Font.Code
	ui.readout.TextSize = 12
	ui.readout.TextXAlignment = Enum.TextXAlignment.Left
	ui.readout.TextColor3 = DIM
	ui.readout.TextStrokeTransparency = 0.6
	ui.readout.Text = ""
	ui.readout.ZIndex = 4
	ui.readout.Parent = panel

	-- Blackout curtain.
	ui.curtain = Instance.new("Frame")
	ui.curtain.Name = "Curtain"
	ui.curtain.Size = UDim2.fromScale(1, 1)
	ui.curtain.BackgroundColor3 = Color3.new(0, 0, 0)
	ui.curtain.BackgroundTransparency = 1
	ui.curtain.BorderSizePixel = 0
	ui.curtain.ZIndex = 20
	ui.curtain.Visible = false
	ui.curtain.Parent = gui

	ui.curtainText = Instance.new("TextLabel")
	ui.curtainText.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.curtainText.Position = UDim2.fromScale(0.5, 0.5)
	ui.curtainText.Size = UDim2.fromOffset(700, 90)
	ui.curtainText.BackgroundTransparency = 1
	ui.curtainText.Font = Enum.Font.GothamBold
	ui.curtainText.TextSize = 26
	ui.curtainText.TextColor3 = GREEN
	ui.curtainText.Text = ""
	ui.curtainText.ZIndex = 21
	ui.curtainText.Parent = ui.curtain

	return gui
end

-- ── Render ──────────────────────────────────────────────────────────

local function render(dt: number)
	local frac = state.exposureFrac
	local colour = if state.failing then WHITE else GREEN

	-- Nothing at all below the warn threshold. Silence is a UI state.
	local intensity = 0
	if frac >= Tuning.EXPOSURE_WARN then
		intensity = (frac - Tuning.EXPOSURE_WARN) / (1 - Tuning.EXPOSURE_WARN)
	end
	if state.failing then
		intensity = math.max(intensity, 0.65)
	end

	for _, frame in ui.edges do
		frame.BackgroundColor3 = colour
		frame.BackgroundTransparency = 1 - (intensity * 0.62)
	end

	ui.fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	ui.fill.BackgroundColor3 = colour

	local label = if state.inShower then "RADS  \u{2014}  FLUSHING" else "RADS"
	ui.caption.Text = label
	ui.caption.TextColor3 = if frac >= Tuning.EXPOSURE_DANGER then colour else DIM
	ui.readout.Text = string.format("%d%%   %+.2f r/s   %s", math.floor(frac * 100 + 0.5), state.net, state.zoneName)

	-- Above the danger threshold the world starts moving. PLAN §3.1 wants vision
	-- distorted here, not merely tinted — the player should be uncomfortable.
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if frac >= Tuning.EXPOSURE_DANGER or state.failing then
			shakeSeed += dt * 22
			local amount = lerp(0, 0.55, math.clamp((frac - Tuning.EXPOSURE_DANGER) / (1 - Tuning.EXPOSURE_DANGER), 0, 1))
			if state.failing then
				amount = math.max(amount, 0.3)
			end
			humanoid.CameraOffset = Vector3.new(
				math.sin(shakeSeed * 1.7) * amount,
				math.sin(shakeSeed * 2.3) * amount * 0.6,
				0
			)
		elseif humanoid.CameraOffset.Magnitude > 0.01 then
			humanoid.CameraOffset = humanoid.CameraOffset:Lerp(Vector3.zero, math.min(1, dt * 8))
		end
	end
end

-- ── Blackout ─────────────────────────────────────────────────────────

local function playBlackout(info)
	local burn = info.cause == "burn"
	local dropped = info.itemsDropped or 0

	ui.curtain.BackgroundColor3 = if burn then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
	ui.curtainText.TextColor3 = if burn then Color3.new(0.1, 0.1, 0.1) else GREEN
	ui.curtainText.Text = if dropped > 0
		then `YOU WENT DOWN\n\ndropped {dropped} item(s) where you fell \u{2014} 90 seconds to get back`
		else "YOU WENT DOWN\n\nnothing to lose \u{2014} your bag was empty"
	ui.curtain.Visible = true
	ui.curtain.BackgroundTransparency = 0

	task.spawn(function()
		task.wait(1.6)
		for i = 1, 30 do
			ui.curtain.BackgroundTransparency = i / 30
			ui.curtainText.TextTransparency = i / 30
			task.wait(0.03)
		end
		ui.curtain.Visible = false
		ui.curtainText.TextTransparency = 0
	end)
end

-- ── Lifecycle ────────────────────────────────────────────────────────

--- Read by GeigerController so the audio bed and the picture cannot disagree.
function Hud.exposureFraction(): number
	return state.exposureFrac
end

function Hud.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("ExposureState").OnClientEvent:Connect(function(payload)
		state.exposureFrac = payload.exposureFrac or 0
		state.net = payload.net or 0
		state.failing = payload.failing == true
		state.inShower = payload.inShower == true
		state.zoneName = payload.zoneName or ""
		state.downed = payload.downed == true
	end)

	Net.get("Blackout").OnClientEvent:Connect(function(info)
		local ok, err = pcall(playBlackout, info)
		if not ok then
			warn(`[hud] blackout render failed: {err}`)
		end
	end)

	-- Heartbeat, not RenderStepped: this drives audio-adjacent feedback and must not
	-- stop because the viewport is not being drawn.
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(render, dt)
		if not ok then
			warn(`[hud] render failed: {err}`)
		end
	end)
end

return Hud
