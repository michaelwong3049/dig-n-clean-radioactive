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

	THE METER NOW LIVES IN THE DOCK, not alone in the corner. See UIKit.Dock for the
	whole bottom-center layout — this file only needs to know its own offset within it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock

local Hud = {}

local GREEN = UIKit.C.green
local WHITE = UIKit.C.burn
local DIM = UIKit.C.dim

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

	-- Unchanged. Not part of the dock — this is a full-screen tint, not a panel.
	ui.edges = {
		edge(gui, "EdgeTop", UDim2.new(1, 0, 0, 190), UDim2.fromScale(0, 0), 270),
		edge(gui, "EdgeBottom", UDim2.new(1, 0, 0, 190), UDim2.new(0, 0, 1, -190), 90),
		edge(gui, "EdgeLeft", UDim2.new(0, 260, 1, 0), UDim2.fromScale(0, 0), 180),
		edge(gui, "EdgeRight", UDim2.new(0, 260, 1, 0), UDim2.new(1, -260, 0, 0), 0),
	}

	-- The meter. Left half of the instrument band, mirrored across the dig button
	-- from the detector dial — see UIKit.Dock for the whole band's layout. It used to
	-- stand alone in the bottom-left corner with no background of its own; now that
	-- it is packed into a dense cluster with the button and the dial either side of
	-- it, it needs a real panel to read as one instrument rather than bleeding into
	-- its neighbours.
	local panel, meterStroke = UIKit.panel(gui, {
		name = "Meter",
		size = Dock.METER_SIZE,
		position = UDim2.new(0.5, -Dock.METER_RIGHT_OFFSET, 1, -Dock.INSTRUMENT_BOTTOM),
		anchorPoint = Vector2.new(1, 1),
		color = UIKit.C.panel,
		transparency = 0.25,
		cornerRadius = UIKit.Radius.card,
		zIndex = 4,
	})
	ui.meterStroke = meterStroke

	ui.caption = UIKit.label(panel, {
		name = "Caption",
		position = UDim2.fromOffset(16, 8),
		size = UDim2.new(1, -32, 0, 20),
		font = UIKit.Font.body,
		textSize = 16,
		color = DIM,
		text = "RADS",
		zIndex = 4,
	})

	local track = Instance.new("Frame")
	track.Position = UDim2.fromOffset(16, 30)
	track.Size = UDim2.new(1, -32, 0, 14)
	track.BackgroundColor3 = Color3.fromHex("14180F")
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.ZIndex = 4
	track.Parent = panel

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 7)
	trackCorner.Parent = track

	ui.fill = Instance.new("Frame")
	ui.fill.Size = UDim2.fromScale(0, 1)
	ui.fill.BackgroundColor3 = GREEN
	ui.fill.BorderSizePixel = 0
	ui.fill.ZIndex = 5
	ui.fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 7)
	fillCorner.Parent = ui.fill

	ui.readout = UIKit.label(panel, {
		name = "Readout",
		position = UDim2.fromOffset(16, 46),
		size = UDim2.new(1, -32, 0, 13),
		font = UIKit.Font.body,
		textSize = 15,
		color = DIM,
		text = "",
		zIndex = 4,
	})

	-- Blackout curtain. Full-screen background, unchanged; the text on it is bigger
	-- and centred exactly as before — it already lived at true screen-centre.
	ui.curtain = Instance.new("Frame")
	ui.curtain.Name = "Curtain"
	ui.curtain.Size = UDim2.fromScale(1, 1)
	ui.curtain.BackgroundColor3 = Color3.new(0, 0, 0)
	ui.curtain.BackgroundTransparency = 1
	ui.curtain.BorderSizePixel = 0
	ui.curtain.ZIndex = 20
	ui.curtain.Visible = false
	ui.curtain.Parent = gui

	-- SPLIT FROM ONE LABEL INTO TWO. LuckiestGuy is a heavy display face — it reads
	-- as a punch of a headline and badly as a full sentence, and the drop-items line
	-- is a full sentence. The headline's TEXT never changes (it is always "YOU WENT
	-- DOWN" — only the cause, the body line, and both labels' colour/fade vary per
	-- call), so it is set once here and playBlackout() never touches its Text again.
	ui.curtainHeadline = UIKit.label(ui.curtain, {
		name = "Headline",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, -50),
		size = UDim2.fromOffset(900, 70),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.hero,
		color = GREEN,
		xAlign = Enum.TextXAlignment.Center,
		text = "YOU WENT DOWN",
		zIndex = 21,
	})

	ui.curtainBody = UIKit.label(ui.curtain, {
		name = "Body",
		anchorPoint = Vector2.new(0.5, 0.5),
		position = UDim2.new(0.5, 0, 0.5, 45),
		size = UDim2.fromOffset(860, 90),
		font = UIKit.Font.body,
		textSize = 20,
		color = GREEN,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
		text = "",
		zIndex = 21,
	})

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
	ui.meterStroke.Color = colour

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

	local textColor = if burn then Color3.new(0.1, 0.1, 0.1) else GREEN

	ui.curtain.BackgroundColor3 = if burn then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
	ui.curtainHeadline.TextColor3 = textColor
	ui.curtainBody.TextColor3 = textColor
	ui.curtainBody.Text = if dropped > 0
		then `dropped {dropped} item(s) where you fell \u{2014} 90 seconds to get back`
		else "nothing to lose \u{2014} your bag was empty"
	ui.curtain.Visible = true
	ui.curtain.BackgroundTransparency = 0

	task.spawn(function()
		task.wait(1.6)
		for i = 1, 30 do
			ui.curtain.BackgroundTransparency = i / 30
			ui.curtainHeadline.TextTransparency = i / 30
			ui.curtainBody.TextTransparency = i / 30
			task.wait(0.03)
		end
		ui.curtain.Visible = false
		ui.curtainHeadline.TextTransparency = 0
		ui.curtainBody.TextTransparency = 0
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
