--[[
	SettingsController.lua — the player Settings panel. One setting today: the colour
	of your base.

	WHY A COLOUR PICKER LIVES HERE. Every plot is built in one neutral grey
	(build/Plots' `C.plotNeutral`), and the accent — the two side Trim strips, the
	four bars framing the nameplate, the cleansing-station lamp, and the CLEANSING
	STATION / WASH PAD sign subtitles — is RUNTIME state now, not a fixed hue baked in
	by plot index. The server owns it: `ExhibitService.setPlotColor` validates a hex,
	stores it on the profile (`data.plotColor`) and repaints via `Plots.setPlotAccent`.
	This file is the other end of that remote — a full RGB picker, and nothing else.

	THE CLIENT NEVER PAINTS THE WORLD. Picking a colour fires `Net.PlotColor` and waits;
	the plot repaints when the server's own render runs. The only thing this file
	colours is the preview swatch inside the panel. The server echoes the
	SERVER-CONFIRMED value straight back, so a rejected or rate-limited change reverts
	the picker to what actually stuck.

	CONFIRMATION IS IN-PANEL, NOT A STATION TOAST. `StationResult` is invisible away
	from a station panel (see ExhibitService / the wash pad's own note), and this is a
	screen GUI, not a station — so the status line here says "saved", and the real
	feedback is your base changing colour behind the panel.

	SHAPE MIRRORS IndexController: a ScreenGui with a corner button and a centred
	`UIKit.panel` that toggles. `start()` only — nothing to build in `init()`.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local Settings = {}

-- Mirrors build/Kit.luau `C.plotNeutral` — the grey an unclaimed plot (and a claimed
-- one whose owner has never picked) wears. Duplicated rather than shared because Kit
-- lives in ServerScriptService; same small, documented dup as CashController's
-- formatCash. Keep in step if the server value changes.
local NEUTRAL = Color3.fromHex("7F8388")

local PANEL_SIZE = Vector2.new(430, 428)
local SV_SIZE = Vector2.new(232, 158)
local HUE_W = 26
local GAP = 14

-- The picker's live HSV, plus whether the COMMITTED base colour is a real hue or the
-- neutral (never-picked / reset) state. `dragging` (any track) makes the preview show
-- the hue under the handles even before it is committed.
local state = {
	h = 0,
	s = 0.72,
	v = 0.92,
	committed = false,
	dragging = false,
}

local ui = {}

-- ── Colour helpers ──────────────────────────────────────────────────

local function currentColor(): Color3
	return Color3.fromHSV(state.h, state.s, state.v)
end

local function hexOf(color: Color3): string
	return string.upper(color:ToHex())
end

-- ── Render ──────────────────────────────────────────────────────────

local function setStatus(text: string)
	if ui.status then
		ui.status.Text = text
	end
end

--- Push `state` onto every piece of the picker. Cheap; called on every input frame
--- while dragging and once per server echo.
local function applyPreview()
	local picked = currentColor()

	ui.hueHandle.Position = UDim2.fromScale(0.5, state.h)
	ui.svArea.BackgroundColor3 = Color3.fromHSV(state.h, 1, 1)
	ui.svHandle.Position = UDim2.fromScale(state.s, 1 - state.v)

	local live = state.committed or state.dragging
	ui.swatch.BackgroundColor3 = if live then picked else NEUTRAL
	ui.hexLabel.Text = if live then "#" .. hexOf(picked) else "not set"
end

-- ── Commit ──────────────────────────────────────────────────────────

--- Send the pick to the server. "" resets the base to neutral. The server echoes the
--- confirmed value back on Net.PlotColor, which `onServerColor` reconciles — so this
--- does NOT optimistically set `state.committed`; it waits for the echo.
local function commit(hex: string)
	setStatus(if hex == "" then "resetting\u{2026}" else "saving\u{2026}")
	Net.get("PlotColor"):FireServer(hex)
end

--- The server's authoritative value (fired once on load, and after every change).
local function onServerColor(hex: any)
	if type(hex) ~= "string" or hex == "" then
		state.committed = false
		setStatus("")
	else
		local ok, parsed = pcall(Color3.fromHex, hex)
		if ok then
			state.h, state.s, state.v = parsed:ToHSV()
			state.committed = true
			setStatus("saved \u{2713}")
		end
	end
	applyPreview()
end

-- ── Draggable tracks ────────────────────────────────────────────────

--- Wire a full-bleed transparent `catcher` frame so a press anywhere on it — and any
--- drag that then wanders off it — reports a clamped (fx, fy) in [0, 1] against the
--- catcher's own rect. `onMove` fires every frame of the drag; `onRelease` once at the
--- end. The catcher is topmost and transparent so the gradient layers and the handle
--- underneath it stay purely visual.
---
--- `dragging` is LOCAL to each call — the SV square and the hue strip must not both
--- react to one drag (they did while this flag was shared, and every drag moved both
--- handles). `state.dragging` is still set so applyPreview shows the live colour, but
--- the move/release gating is per-track.
local function makeDraggable(catcher: GuiObject, onMove: (number, number) -> (), onRelease: () -> ())
	local dragging = false

	local function fractionFrom(inputPos: Vector3): (number, number)
		local rel = Vector2.new(inputPos.X, inputPos.Y) - catcher.AbsolutePosition
		local fx = math.clamp(rel.X / math.max(catcher.AbsoluteSize.X, 1), 0, 1)
		local fy = math.clamp(rel.Y / math.max(catcher.AbsoluteSize.Y, 1), 0, 1)
		return fx, fy
	end

	catcher.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		state.dragging = true
		onMove(fractionFrom(input.Position))
	end)

	UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		onMove(fractionFrom(input.Position))
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = false
		state.dragging = false
		onRelease()
	end)
end

-- ── Build ───────────────────────────────────────────────────────────

local function gradientFrame(parent: Instance, name: string, color: Color3, transparency: NumberSequence, rotation: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = 12
	frame.Parent = parent

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(color)
	grad.Transparency = transparency
	grad.Rotation = rotation
	grad.Parent = frame
	return frame
end

local function handleDot(parent: Instance): Frame
	local dot = Instance.new("Frame")
	dot.Name = "Handle"
	dot.Size = UDim2.fromOffset(14, 14)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.ZIndex = 13
	dot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = dot
	return dot
end

local function buildColorPicker(section: Instance)
	-- Saturation / value square. Hue-coloured base, a white gradient across for
	-- saturation and a black gradient down for value; a transparent catcher on top
	-- takes the drag.
	local svArea = Instance.new("Frame")
	svArea.Name = "SVArea"
	svArea.Size = UDim2.fromOffset(SV_SIZE.X, SV_SIZE.Y)
	svArea.Position = UDim2.fromOffset(0, 0)
	svArea.BackgroundColor3 = Color3.fromHSV(state.h, 1, 1)
	svArea.BorderSizePixel = 0
	svArea.ZIndex = 11
	svArea.Parent = section
	ui.svArea = svArea

	local svCorner = Instance.new("UICorner")
	svCorner.CornerRadius = UDim.new(0, 8)
	svCorner.Parent = svArea
	local svClip = Instance.new("UICorner") -- clip the gradient children to the rounded box
	svClip.CornerRadius = UDim.new(0, 8)
	svClip.Parent = svArea
	svArea.ClipsDescendants = true

	gradientFrame(
		svArea,
		"Saturation",
		Color3.new(1, 1, 1),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		0
	)
	gradientFrame(
		svArea,
		"Value",
		Color3.new(0, 0, 0),
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		90
	)

	ui.svHandle = handleDot(svArea)

	local svCatcher = Instance.new("Frame")
	svCatcher.Name = "Catcher"
	svCatcher.Size = UDim2.fromScale(1, 1)
	svCatcher.BackgroundTransparency = 1
	svCatcher.ZIndex = 14
	svCatcher.Active = true
	svCatcher.Parent = svArea

	makeDraggable(svCatcher, function(fx, fy)
		state.s = fx
		state.v = 1 - fy
		applyPreview()
	end, function()
		commit(hexOf(currentColor()))
	end)

	-- Hue strip, to the right of the square. A vertical rainbow; drag picks hue.
	local hue = Instance.new("Frame")
	hue.Name = "Hue"
	hue.Size = UDim2.fromOffset(HUE_W, SV_SIZE.Y)
	hue.Position = UDim2.fromOffset(SV_SIZE.X + GAP, 0)
	hue.BackgroundColor3 = Color3.new(1, 1, 1)
	hue.BorderSizePixel = 0
	hue.ZIndex = 11
	hue.ClipsDescendants = true
	hue.Parent = section

	local hueCorner = Instance.new("UICorner")
	hueCorner.CornerRadius = UDim.new(0, 6)
	hueCorner.Parent = hue

	local hueGrad = Instance.new("UIGradient")
	hueGrad.Rotation = 90
	hueGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromHSV(0.00, 1, 1)),
		ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17, 1, 1)),
		ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
		ColorSequenceKeypoint.new(0.50, Color3.fromHSV(0.50, 1, 1)),
		ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
		ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
		ColorSequenceKeypoint.new(1.0, Color3.fromHSV(1.00, 1, 1)),
	})
	hueGrad.Parent = hue

	local hueHandle = Instance.new("Frame")
	hueHandle.Name = "HueHandle"
	hueHandle.Size = UDim2.new(1, 6, 0, 6)
	hueHandle.AnchorPoint = Vector2.new(0.5, 0.5)
	hueHandle.BackgroundColor3 = Color3.new(1, 1, 1)
	hueHandle.BorderSizePixel = 0
	hueHandle.ZIndex = 13
	hueHandle.Parent = hue
	local hhStroke = Instance.new("UIStroke")
	hhStroke.Color = Color3.new(0, 0, 0)
	hhStroke.Thickness = 2
	hhStroke.Transparency = 0.3
	hhStroke.Parent = hueHandle
	ui.hueHandle = hueHandle

	local hueCatcher = Instance.new("Frame")
	hueCatcher.Name = "Catcher"
	hueCatcher.Size = UDim2.fromScale(1, 1)
	hueCatcher.BackgroundTransparency = 1
	hueCatcher.ZIndex = 14
	hueCatcher.Active = true
	hueCatcher.Parent = hue

	makeDraggable(hueCatcher, function(_, fy)
		state.h = fy
		applyPreview()
	end, function()
		commit(hexOf(currentColor()))
	end)

	-- Preview swatch + hex, and the two commit buttons, in the strip under the square.
	local footerY = SV_SIZE.Y + 18

	local swatch = Instance.new("Frame")
	swatch.Name = "Swatch"
	swatch.Size = UDim2.fromOffset(46, 46)
	swatch.Position = UDim2.fromOffset(0, footerY)
	swatch.BackgroundColor3 = NEUTRAL
	swatch.BorderSizePixel = 0
	swatch.ZIndex = 12
	swatch.Parent = section
	local swCorner = Instance.new("UICorner")
	swCorner.CornerRadius = UDim.new(0, 8)
	swCorner.Parent = swatch
	local swStroke = Instance.new("UIStroke")
	swStroke.Color = UIKit.C.stroke
	swStroke.Thickness = 2
	swStroke.Parent = swatch
	ui.swatch = swatch

	ui.hexLabel = UIKit.label(section, {
		name = "Hex",
		position = UDim2.fromOffset(58, footerY),
		size = UDim2.fromOffset(120, 22),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.text,
		text = "not set",
		zIndex = 12,
	})

	ui.status = UIKit.label(section, {
		name = "Status",
		position = UDim2.fromOffset(58, footerY + 24),
		size = UDim2.fromOffset(200, 18),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		text = "",
		zIndex = 12,
	})

	local apply = UIKit.button(section, {
		name = "Apply",
		position = UDim2.fromOffset(SV_SIZE.X + GAP + HUE_W - 132, footerY),
		size = UDim2.fromOffset(132, 34),
		text = "APPLY",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.text,
		fillColor = UIKit.C.selected,
		fillTransparency = 0,
		cornerRadius = UIKit.Radius.button,
		zIndex = 12,
	})
	apply.MouseButton1Click:Connect(function()
		commit(hexOf(currentColor()))
	end)

	local reset = UIKit.button(section, {
		name = "Reset",
		position = UDim2.fromOffset(SV_SIZE.X + GAP + HUE_W - 132, footerY + 42),
		size = UDim2.fromOffset(132, 28),
		text = "RESET TO NEUTRAL",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		fillColor = UIKit.C.empty,
		fillTransparency = 0.2,
		cornerRadius = UIKit.Radius.slot,
		zIndex = 12,
	})
	reset.MouseButton1Click:Connect(function()
		commit("")
	end)
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 90
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- The button: a small gear, top-RIGHT corner — clear of the top-centre warp bar
	-- (WarpController) and the full bottom-left dock column.
	local button = UIKit.button(gui, {
		name = "SettingsButton",
		size = UDim2.fromOffset(44, 44),
		position = UDim2.new(1, -12, 0, 12),
		anchorPoint = Vector2.new(1, 0),
		text = "\u{2699}",
		font = Enum.Font.SourceSansBold, -- Gotham has no gear glyph; SourceSans does
		textSize = 26,
		color = UIKit.C.text,
		fillColor = UIKit.C.panel,
		fillTransparency = 0.1,
		cornerRadius = UIKit.Radius.card,
		zIndex = 4,
	})

	local panel = UIKit.panel(gui, {
		name = "Panel",
		size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = UIKit.C.panel,
		transparency = 0.05,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		zIndex = 10,
		visible = false,
	})
	ui.panel = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.Parent = panel

	UIKit.label(panel, {
		name = "Title",
		size = UDim2.new(1, -40, 0, 40),
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.hero,
		color = UIKit.C.text,
		text = "SETTINGS",
		zIndex = 11,
	})

	local close = UIKit.button(panel, {
		name = "Close",
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.fromScale(1, 0),
		size = UDim2.fromOffset(32, 32),
		text = "X",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.text,
		fillColor = UIKit.C.empty,
		cornerRadius = UIKit.Radius.slot,
		zIndex = 12,
	})

	-- One section for now, laid out so more can stack under it later.
	local section = Instance.new("Frame")
	section.Name = "BaseColour"
	section.Position = UDim2.fromOffset(0, 64)
	section.Size = UDim2.new(1, 0, 1, -64)
	section.BackgroundTransparency = 1
	section.ZIndex = 11
	section.Parent = panel

	UIKit.label(section, {
		name = "SectionTitle",
		size = UDim2.new(1, 0, 0, 24),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.text,
		text = "BASE COLOUR",
		zIndex = 12,
	})

	UIKit.label(section, {
		name = "SectionHint",
		position = UDim2.fromOffset(0, 24),
		size = UDim2.new(1, 0, 0, 18),
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		text = "the accent on your base — trim, nameplate, station signs",
		zIndex = 12,
	})

	local pickerHost = Instance.new("Frame")
	pickerHost.Name = "Picker"
	pickerHost.Position = UDim2.fromOffset(0, 52)
	pickerHost.Size = UDim2.new(1, 0, 1, -52)
	pickerHost.BackgroundTransparency = 1
	pickerHost.ZIndex = 11
	pickerHost.Parent = section

	buildColorPicker(pickerHost)

	local function toggle()
		panel.Visible = not panel.Visible
	end
	button.MouseButton1Click:Connect(toggle)
	close.MouseButton1Click:Connect(toggle)

	return gui
end

-- ── Lifecycle ───────────────────────────────────────────────────────

function Settings.start()
	local player = Players.LocalPlayer
	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	applyPreview()

	-- Fired once on load with the saved value, and again after every change as the
	-- server-confirmed echo — same channel both ways (Shared/Net.PlotColor).
	Net.get("PlotColor").OnClientEvent:Connect(onServerColor)
end

return Settings
