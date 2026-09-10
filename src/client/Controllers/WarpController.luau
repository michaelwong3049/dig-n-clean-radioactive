--!strict
--[[
	WarpController.luau — the "getting around" bar at the top of the screen.

	Two buttons, BASE and SHOPS, centred against the top edge. They are a convenience
	for moving around the safe zone — from your plot out to the shop cluster and back
	— and they are ONLY on screen while you are standing in no stage. The moment you
	cross into a field the bar slides away: warping is not an escape hatch (WarpService
	refuses it server-side from inside a stage as well), and the top-centre strip is
	the stage-name banner's while you are in one.

	READS stageId OFF ExposureState, the same field StageBannerController and
	AtmosphereController already read — it ticks ~10Hz and costs nothing new on the
	wire. Pure presentation: the click sends a destination NAME, WarpService decides
	the CFrame.

	Neutral dark cards keep the destination logos clear.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local WarpIcons = require(script.Parent.Parent.WarpIcons)

local WarpController = {}

local SHOWN = UDim2.new(0.5, 0, 0, 12)
local HIDDEN = UDim2.new(0.5, 0, 0, -100) -- fully off the top edge
local SLIDE = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLICK_DEBOUNCE = 0.4
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Shared with IndexController's Index tile (UIKit.C.nav*), so the two read as one
-- family of buttons.
local BACKGROUND = UIKit.C.navFill
local HOVER_BACKGROUND = UIKit.C.navFillHover
local EDGE = UIKit.C.navEdge
local HOVER_EDGE = UIKit.C.navEdgeHover

local BUTTONS = {
	{ dest = "base", text = "BASE" },
	{ dest = "shops", text = "SHOPS" },
}

local ui: {
	panel: Frame,
}? = nil

local shown = false
local hideToken = 0
local lastClick = 0
local warpRemote: any = nil

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarpBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90 -- under StageBanner (95) so the banner wins the brief stage-exit overlap
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Dark cards with a centered destination logo.
	local BTN_W, BTN_H, GAP = 120, 56, 10
	local width = #BUTTONS * BTN_W + (#BUTTONS - 1) * GAP
	local height = BTN_H

	local canvas = UIKit.canvas(gui)
	local panel = UIKit.panel(canvas, {
		name = "Panel",
		size = UDim2.fromOffset(width, height),
		position = HIDDEN,
		anchorPoint = Vector2.new(0.5, 0),
		color = UIKit.C.panel,
		transparency = 1,
		strokeThickness = 0,
		visible = false,
	})

	for index, spec in BUTTONS do
		UIKit.panel(panel, {
			name = spec.text .. "Shadow",
			size = UDim2.fromOffset(BTN_W, BTN_H),
			position = UDim2.fromOffset((index - 1) * (BTN_W + GAP), 4),
			color = UIKit.C.navShadow,
			transparency = 0.2,
			cornerRadius = UDim.new(0, 9),
			strokeThickness = 0,
			zIndex = 3,
		})
		local button, stroke = UIKit.button(panel, {
			name = spec.text,
			size = UDim2.fromOffset(BTN_W, BTN_H),
			position = UDim2.fromOffset((index - 1) * (BTN_W + GAP), 0),
			font = Enum.Font.GothamBlack,
			textSize = 29,
			color = Color3.new(1, 1, 1),
			fillColor = BACKGROUND,
			fillTransparency = 0,
			strokeColor = EDGE,
			cornerRadius = UDim.new(0, 9),
			strokeThickness = 2,
			text = "",
			zIndex = 4,
		})
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

		local iconPieces = WarpIcons.build(button, spec.dest)

		local function setHighlighted(active: boolean)
			TweenService:Create(button, HOVER, {
				BackgroundColor3 = if active then HOVER_BACKGROUND else BACKGROUND,
			}):Play()
			TweenService:Create(stroke, HOVER, { Color = if active then HOVER_EDGE else EDGE }):Play()
			for _, piece in iconPieces do
				TweenService:Create(piece, HOVER, {
					BackgroundColor3 = if active then Color3.new(1, 1, 1) else UIKit.C.navIcon,
				}):Play()
			end
		end
		button.MouseEnter:Connect(function()
			setHighlighted(true)
		end)
		button.MouseLeave:Connect(function()
			setHighlighted(false)
		end)
		button.SelectionGained:Connect(function()
			setHighlighted(true)
		end)
		button.SelectionLost:Connect(function()
			setHighlighted(false)
		end)
		button.MouseButton1Click:Connect(function()
			local now = os.clock()
			if now - lastClick < CLICK_DEBOUNCE then
				return
			end
			lastClick = now
			warpRemote:FireServer({ dest = spec.dest })
		end)
	end

	ui = { panel = panel }
	return gui
end

--- Slide the bar in (`next` true) or out. Out finishes with a token-guarded
--- Visible = false so a rapid out/in does not leave it hidden mid-slide — the same
--- pattern StageBannerController uses for its card.
local function setShown(next: boolean)
	if next == shown or ui == nil then
		return
	end
	shown = next
	local panel = ui.panel

	if next then
		panel.Visible = true
		TweenService:Create(panel, SLIDE, { Position = SHOWN }):Play()
	else
		hideToken += 1
		local mine = hideToken
		TweenService:Create(panel, SLIDE, { Position = HIDDEN }):Play()
		task.delay(SLIDE.Time, function()
			if not shown and mine == hideToken and ui then
				ui.panel.Visible = false
			end
		end)
	end
end

function WarpController.start()
	local player = Players.LocalPlayer
	warpRemote = Net.get("Warp")

	local gui = build()
	gui.Parent = player:WaitForChild("PlayerGui")

	Net.get("ExposureState").OnClientEvent:Connect(function(state)
		setShown(state.stageId == nil and state.downed ~= true)
	end)
end

return WarpController
