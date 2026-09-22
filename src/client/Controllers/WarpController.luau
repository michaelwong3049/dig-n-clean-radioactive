--!strict
--[[
	WarpController.luau — the "getting around" bar at the top of the screen.

	BASE and SHOPS, centred against the top edge, plus one button per site camp
	(Config/Camps — Toxic Twilight first). They are a convenience for moving around
	the safe zones — from your plot out to the shop cluster, out to a far camp and back
	— and they are ONLY on screen while you are standing in no stage. The moment you
	cross into a field the bar slides away: warping is not an escape hatch (WarpService
	refuses it server-side from inside a stage as well), and the top-centre strip is
	the stage-name banner's while you are in one.

	A CAMP BUTTON IS ON EVERYONE'S BAR, LOCKED, until that camp has been reached on
	foot once (CampService). Locked, it wears a padlock and a dimmed logo, and a click
	says how to open it instead of warping. That is presentation only — WarpService
	makes the same refusal for a client that ignores the lock. A camp that is not in
	this world at all (a place saved before it was built) gets no button: there is
	nothing to land on, so `available` in CampState hides it rather than locking it.

	READS stageId OFF ExposureState, the same field StageBannerController and
	AtmosphereController already read — it ticks ~10Hz and costs nothing new on the
	wire. The camp buttons read CampState, which only fires on change. Pure
	presentation: the click sends a destination NAME, WarpService decides the CFrame.

	Neutral dark cards keep the destination logos clear.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Camps = require(Shared.Config.Camps)

local UIKit = require(script.Parent.Parent.UIKit)
local WarpIcons = require(script.Parent.Parent.WarpIcons)

local WarpController = {}

local SHOWN = UDim2.new(0.5, 0, 0, 12)
local HIDDEN = UDim2.new(0.5, 0, 0, -100) -- fully off the top edge
local SLIDE = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLICK_DEBOUNCE = 0.4
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HINT_HOLD = 2.4
-- Shared with IndexController's Index tile (UIKit.C.nav*), so the two read as one
-- family of buttons.
local BACKGROUND = UIKit.C.navFill
local HOVER_BACKGROUND = UIKit.C.navFillHover
local EDGE = UIKit.C.navEdge
local HOVER_EDGE = UIKit.C.navEdgeHover
-- A locked logo stays legible but plainly off.
local LOCKED_ICON_TRANSPARENCY = 0.6

local BTN_W, BTN_H, GAP = 120, 56, 10

type ButtonSpec = { dest: string, text: string, camp: Camps.CampDef? }

local BUTTONS: { ButtonSpec } = {
	{ dest = "base", text = "BASE" },
	{ dest = "shops", text = "SHOPS" },
}
for _, def in Camps.sites() do
	table.insert(BUTTONS, { dest = def.key, text = def.name:upper(), camp = def })
end

type Entry = {
	spec: ButtonSpec,
	shadow: Frame,
	button: TextButton,
	stroke: UIStroke,
	icon: { Frame },
	lock: Frame?,
}

local ui: {
	panel: Frame,
	hint: TextLabel,
	entries: { Entry },
}? = nil

local shown = false
local hideToken = 0
local hintToken = 0
local lastClick = 0
local warpRemote: any = nil

local reached: { [string]: boolean } = {}
local available: { [string]: boolean } = {}

local function isLocked(spec: ButtonSpec): boolean
	return spec.camp ~= nil and reached[spec.dest] ~= true
end

local function isShown(spec: ButtonSpec): boolean
	return spec.camp == nil or available[spec.dest] == true
end

--- Lay out whichever buttons this world has, left to right, and size the panel to them.
local function layout()
	if ui == nil then
		return
	end
	local index = 0
	for _, entry in ui.entries do
		local visible = isShown(entry.spec)
		entry.shadow.Visible = visible
		entry.button.Visible = visible
		if visible then
			local x = index * (BTN_W + GAP)
			entry.shadow.Position = UDim2.fromOffset(x, 4)
			entry.button.Position = UDim2.fromOffset(x, 0)
			index += 1
		end
		if entry.lock then
			entry.lock.Visible = isLocked(entry.spec)
		end
		for _, piece in entry.icon do
			piece.BackgroundTransparency = if isLocked(entry.spec) then LOCKED_ICON_TRANSPARENCY else 0
		end
	end
	ui.panel.Size = UDim2.fromOffset(math.max(1, index * BTN_W + math.max(0, index - 1) * GAP), BTN_H)
end

--- Shown and hidden outright rather than faded: UIKit.label's outline is a UIStroke
--- (and its shadow a second label), neither of which follows TextTransparency, so a
--- fade would leave the outline hanging on screen after the letters had gone.
local function showHint(text: string)
	if ui == nil then
		return
	end
	hintToken += 1
	local mine = hintToken
	ui.hint.Text = text
	ui.hint.Visible = true
	task.delay(HINT_HOLD, function()
		if mine == hintToken and ui then
			ui.hint.Visible = false
		end
	end)
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarpBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90 -- under StageBanner (95) so the banner wins the brief stage-exit overlap
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Dark cards with a centered destination logo.
	local canvas = UIKit.canvas(gui)
	local panel = UIKit.panel(canvas, {
		name = "Panel",
		size = UDim2.fromOffset(BTN_W, BTN_H),
		position = HIDDEN,
		anchorPoint = Vector2.new(0.5, 0),
		color = UIKit.C.panel,
		transparency = 1,
		strokeThickness = 0,
		visible = false,
	})

	-- Under the bar: "how do I open this", shown briefly when a locked camp is clicked.
	-- A child of the panel so it slides with it.
	local hint = UIKit.label(panel, {
		name = "LockHint",
		size = UDim2.fromOffset(460, 24),
		position = UDim2.new(0.5, 0, 1, 12),
		anchorPoint = Vector2.new(0.5, 0),
		text = "",
		font = Enum.Font.GothamBold,
		textSize = 18,
		color = Color3.new(1, 1, 1),
		zIndex = 6,
		visible = false,
	})

	local entries: { Entry } = {}
	for _, spec in BUTTONS do
		local shadow = UIKit.panel(panel, {
			name = spec.text .. "Shadow",
			size = UDim2.fromOffset(BTN_W, BTN_H),
			position = UDim2.fromOffset(0, 4),
			color = UIKit.C.navShadow,
			transparency = 0.2,
			cornerRadius = UDim.new(0, 9),
			strokeThickness = 0,
			zIndex = 3,
		})
		local button, stroke = UIKit.button(panel, {
			name = spec.text,
			size = UDim2.fromOffset(BTN_W, BTN_H),
			position = UDim2.fromOffset(0, 0),
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
		local lock = if spec.camp then WarpIcons.lock(button) else nil
		table.insert(entries, { spec = spec, shadow = shadow, button = button, stroke = stroke, icon = iconPieces, lock = lock })

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
			if isLocked(spec) then
				local name = if spec.camp then spec.camp.name else spec.text
				showHint(`Reach {name} on foot to unlock its warp`)
				return
			end
			warpRemote:FireServer({ dest = spec.dest })
		end)
	end

	ui = { panel = panel, hint = hint, entries = entries }
	layout()
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

	Net.get("CampState").OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		reached = if type(state.reached) == "table" then state.reached else {}
		available = if type(state.available) == "table" then state.available else {}
		layout()
	end)
end

return WarpController
