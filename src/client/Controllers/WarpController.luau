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

	NOT GREEN. The buttons use the neutral blue accent; green in the HUD means
	exposure and nothing else (PLAN §14, and every other HUD header).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local WarpController = {}

local SHOWN = UDim2.new(0.5, 0, 0, 10)
local HIDDEN = UDim2.new(0.5, 0, 0, -90) -- fully off the top edge
local SLIDE = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLICK_DEBOUNCE = 0.4

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

	local BTN_W, BTN_H, GAP, PAD = 118, 34, 8, 8
	local width = #BUTTONS * BTN_W + (#BUTTONS - 1) * GAP + 2 * PAD
	local height = BTN_H + 2 * PAD

	local panel = UIKit.panel(gui, {
		name = "Panel",
		size = UDim2.fromOffset(width, height),
		position = HIDDEN,
		anchorPoint = Vector2.new(0.5, 0),
		color = UIKit.C.panel,
		transparency = 0.12,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.normal,
		visible = false,
	})

	for index, spec in BUTTONS do
		local button, stroke = UIKit.button(panel, {
			name = spec.text,
			size = UDim2.fromOffset(BTN_W, BTN_H),
			position = UDim2.fromOffset(PAD + (index - 1) * (BTN_W + GAP), PAD),
			font = UIKit.Font.title,
			textSize = UIKit.TextSize.header,
			color = UIKit.C.text,
			fillColor = UIKit.C.empty,
			fillTransparency = 0.2,
			cornerRadius = UIKit.Radius.button,
			strokeThickness = UIKit.Stroke.thin,
			text = spec.text,
		})

		-- UIKit.button turns AutoButtonColor off, so hover/press is ours to drive.
		button.MouseEnter:Connect(function()
			stroke.Color = UIKit.C.blue
			button.BackgroundTransparency = 0.05
		end)
		button.MouseLeave:Connect(function()
			stroke.Color = UIKit.C.stroke
			button.BackgroundTransparency = 0.2
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
