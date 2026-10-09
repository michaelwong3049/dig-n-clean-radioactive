--[[
	HideNukesToggleController — the "Hide others' nukes" bar over the Shop tile
	(2026-10-08, on request: "put the hide other nukes thing above the shop"). One tap
	flips the `fastMode` pref, the same one Settings' "Hide others' nukes" switch sets
	(FastModeController does the hiding); either one follows the other through
	Prefs.observe. Green plate when on, the dark plate when off.

	Placement is Dock's (Dock.sideToggleCentre): as wide as the left grid, just over its
	top row, re-placed on every canvas resize like the tiles.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.Parent.UIKit)
local Dock = UIKit.Dock
local Studded = require(script.Parent.Parent.Studded)
local Prefs = require(script.Parent.Parent.Prefs)

local HideNukesToggleController = {}

local ON = ColorSequence.new(Color3.fromHex("4FA23A"), Color3.fromHex("1F5A1E"))
local OFF = ColorSequence.new(Studded.DARK)
local CORNER = math.round(8 * Dock.SIDE_GRID_SCALE)
local TEXT_SIZE = math.round(12 * Dock.SIDE_GRID_SCALE)
local HOVER_SCALE = 1.05
local PRESS_SCALE = 0.94
local TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function HideNukesToggleController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HideNukesToggle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- With the grid tiles (HudTile).
	gui.DisplayOrder = 55
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local button = Instance.new("TextButton")
	button.Name = "Toggle"
	button.Text = ""
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(Dock.SIDE_GRID_WIDTH, Dock.SIDE_TOGGLE_HEIGHT)
	button.BorderSizePixel = 0
	button.ZIndex = 4
	button.Parent = canvas
	Studded.edge(button, CORNER, 2)
	local fill = Studded.fill(button, OFF)
	Studded.pattern(button, {
		tile = math.round(14 * Dock.SIDE_GRID_SCALE),
		radius = CORNER,
		studTransparency = 0.3,
		bandTransparency = 0.8,
		glow = false,
	})

	local label = Studded.text(button, "Caption", TEXT_SIZE, 2)
	label.Size = UDim2.new(1, -8, 1, 0)
	label.Position = UDim2.fromOffset(4, 0)
	label.TextScaled = true
	label.ZIndex = 8
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = TEXT_SIZE
	fit.Parent = label

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local function place()
		local height = canvas.AbsoluteSize.Y / UIKit.canvasScale(canvas)
		button.Position = Dock.sideToggleCentre(height)
	end
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()

	Prefs.observe("fastMode", function(on)
		on = on == true
		fill.Color = if on then ON else OFF
		label.Text = if on then "Hide nukes: ON" else "Hide nukes: OFF"
	end)
	button.Activated:Connect(function()
		Prefs.set("fastMode", not Prefs.get("fastMode"))
	end)

	local hovered, pressed = false, false
	local function refresh()
		local target = if pressed then PRESS_SCALE elseif hovered then HOVER_SCALE else 1
		TweenService:Create(scale, TWEEN, { Scale = target }):Play()
	end
	button.MouseEnter:Connect(function()
		hovered = true
		refresh()
	end)
	button.MouseLeave:Connect(function()
		hovered, pressed = false, false
		refresh()
	end)
	button.MouseButton1Down:Connect(function()
		pressed = true
		refresh()
	end)
	button.MouseButton1Up:Connect(function()
		pressed = false
		refresh()
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return HideNukesToggleController
