--!strict
--[[
	WarpController.luau — the "getting around" bar at the top of the screen.

	Two portals, HOME and SHOPS, centred against the top edge. They are a convenience
	for moving around Base Camp — from your plot out to the shop cluster and back — and
	they are ONLY on screen while you are standing in no stage. The moment you cross
	into a field the bar slides away: warping is not an escape hatch (WarpService
	refuses it server-side from inside a stage as well), and the top-centre strip is
	the stage-name banner's while you are in one.

	CAMPS ARE NOT UP HERE. Every other camp (Config/Camps) is on the Warp tile's panel
	on the right edge (CampWarpController), which lists them all, locked or not, so the
	bar stays two buttons however many camps the chain grows.

	THE LOOK is a portal ring per destination: a disc of the destination's colour whose
	bands turn slowly (a UIGradient's Rotation, stepped every frame while the bar is
	up — Roblox has no conic gradient, so two counter-turning banded discs stand in for
	the swirl), an INK rim, a soft halo, the destination's picture on top, and a dark
	name pill tucked under its right side. Hover spins it fast and grows it a little.

	READS stageId OFF ExposureState, the same field StageBannerController and
	AtmosphereController already read — it ticks ~10Hz and costs nothing new on the
	wire. Pure presentation: the click sends a destination NAME, WarpService decides
	the CFrame.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)

local WarpController = {}

local SHOWN = UDim2.new(0.5, 0, 0, 10)
local HIDDEN = UDim2.new(0.5, 0, 0, -100) -- fully off the top edge
local SLIDE = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLICK_DEBOUNCE = 0.4

-- Design px. The disc sits on the left; the name pill starts OVERLAP under its right
-- side, so the pill's left end is always hidden and only its rounded right end shows.
-- The bar's bottom (with the disc's drop shadow) stays above TutorialController's
-- banner at y 84.
local DISC = 60
local RIM = 3
local PILL_W = 112
local PILL_H = 42
local OVERLAP = 22
local BTN_W = DISC - OVERLAP + PILL_W
local BTN_H = DISC + 4
local GAP = 18
local ICON = 34
local ICON_OUTLINE = 2
local NAME_SIZE = 21
local HOVER_GROW = 1.08
local PRESS_SHRINK = 0.9

-- Degrees per second the bands turn, at rest and under the pointer.
local SPIN_REST = 90
local SPIN_HOVER = 540
-- The inner disc turns the other way, a little faster, so the two read as a swirl.
local INNER_SPIN = -1.4

local INK = Color3.fromHex("1A1A1A")
local PILL = Color3.fromHex("161A22")
local PILL_HOVER = Color3.fromHex("232936")
local EYE = Color3.fromHex("0F0F19")

type Spec = {
	dest: string,
	text: string,
	image: string,
	light: Color3,
	mid: Color3,
	dark: Color3,
}

local BUTTONS: { Spec } = {
	{
		dest = "base",
		text = "HOME",
		image = Artwork.IMAGE.house,
		light = Color3.fromHex("86F27A"),
		mid = Color3.fromHex("34C446"),
		dark = Color3.fromHex("1D8A2A"),
	},
	{
		dest = "shops",
		text = "SHOPS",
		image = Artwork.IMAGE.storefront,
		light = Color3.fromHex("FFE36B"),
		mid = Color3.fromHex("FFB61C"),
		dark = Color3.fromHex("C47A00"),
	},
}

type Entry = {
	outer: UIGradient,
	inner: UIGradient,
	angle: number,
	speed: number,
}

local panel: Frame? = nil
local entries: { Entry } = {}
local shown = false
local hideToken = 0
local lastClick = 0
local warpRemote: any = nil

local function circle(parent: Instance, name: string, size: number, color: Color3, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	return frame
end

--- Alternating bands of two colours across a white fill: turned by Rotation, they are
--- the portal's swirl.
local function bands(parent: Instance, a: Color3, b: Color3): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, a),
		ColorSequenceKeypoint.new(0.25, b),
		ColorSequenceKeypoint.new(0.5, a),
		ColorSequenceKeypoint.new(0.75, b),
		ColorSequenceKeypoint.new(1, a),
	})
	gradient.Parent = parent
	return gradient
end

local function buildButton(parent: Frame, spec: Spec, x: number): Entry
	local button = Instance.new("TextButton")
	button.Name = spec.text
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Size = UDim2.fromOffset(BTN_W, BTN_H)
	button.Position = UDim2.fromOffset(x, 0)
	button.ZIndex = 2
	button.Parent = parent

	-- The name pill, and its hard drop shadow.
	local pillTop = (DISC - PILL_H) / 2
	local pillShadow = Instance.new("Frame")
	pillShadow.Name = "PillShadow"
	pillShadow.Position = UDim2.fromOffset(DISC - OVERLAP, pillTop + 4)
	pillShadow.Size = UDim2.fromOffset(PILL_W, PILL_H)
	pillShadow.BackgroundColor3 = INK
	pillShadow.BorderSizePixel = 0
	pillShadow.ZIndex = 3
	pillShadow.Parent = button
	local pill = pillShadow:Clone()
	pill.Name = "Pill"
	pill.Position = UDim2.fromOffset(DISC - OVERLAP, pillTop)
	pill.BackgroundColor3 = PILL
	pill.ZIndex = 4
	pill.Parent = button
	for _, frame in { pillShadow, pill } do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
	end
	local pillEdge = Instance.new("UIStroke")
	pillEdge.Color = INK
	pillEdge.Thickness = RIM
	pillEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pillEdge.Parent = pill
	UIKit.label(pill, {
		name = "Name",
		size = UDim2.new(1, -(OVERLAP + 12), 1, 0),
		position = UDim2.fromOffset(OVERLAP + 4, 0),
		text = spec.text,
		font = Enum.Font.FredokaOne,
		textSize = NAME_SIZE,
		color = Color3.new(1, 1, 1),
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 6,
	})

	-- The portal: halo, drop shadow, banded disc, counter-turning inner disc, dark eye.
	local seat = Instance.new("Frame")
	seat.Name = "Portal"
	seat.Size = UDim2.fromOffset(DISC, DISC)
	seat.BackgroundTransparency = 1
	seat.ZIndex = 5
	seat.Parent = button
	local halo = circle(seat, "Halo", DISC + 22, spec.mid, 2)
	halo.BackgroundTransparency = 0.85
	local glow = circle(seat, "Glow", DISC + 10, spec.mid, 2)
	glow.BackgroundTransparency = 0.65
	local shadow = circle(seat, "Shadow", DISC, INK, 5)
	shadow.Position = UDim2.new(0.5, 0, 0.5, 4)

	local disc = circle(seat, "Disc", DISC, Color3.new(1, 1, 1), 6)
	local rim = Instance.new("UIStroke")
	rim.Color = INK
	rim.Thickness = RIM
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = disc
	local grow = Instance.new("UIScale")
	grow.Parent = disc
	local outer = bands(disc, spec.light, spec.dark)
	local innerDisc = circle(disc, "Inner", math.floor(DISC * 0.64), Color3.new(1, 1, 1), 7)
	local inner = bands(innerDisc, spec.mid, spec.dark)
	local eye = circle(disc, "Eye", math.floor(DISC * 0.36), EYE, 8)
	eye.BackgroundTransparency = 0.45

	local icon = Artwork.inkedPicture(disc, "Icon", spec.image, ICON, Color3.new(1, 1, 1), ICON_OUTLINE, 9)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)

	local entry: Entry = { outer = outer, inner = inner, angle = x, speed = SPIN_REST }

	local function setHighlighted(active: boolean)
		entry.speed = if active then SPIN_HOVER else SPIN_REST
		TweenService:Create(grow, HOVER, { Scale = if active then HOVER_GROW else 1 }):Play()
		TweenService:Create(pill, HOVER, { BackgroundColor3 = if active then PILL_HOVER else PILL }):Play()
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
	button.Activated:Connect(function()
		local now = os.clock()
		if now - lastClick < CLICK_DEBOUNCE then
			return
		end
		lastClick = now
		-- A quick press, then back to whatever the pointer says.
		grow.Scale = PRESS_SHRINK
		TweenService:Create(grow, POP, { Scale = if entry.speed == SPIN_HOVER then HOVER_GROW else 1 }):Play()
		warpRemote:FireServer({ dest = spec.dest })
	end)

	return entry
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarpBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90 -- under StageBanner (95) so the banner wins the brief stage-exit overlap
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local canvas = UIKit.canvas(gui)
	-- Named Panel: AuraWarningController finds the bar by WarpBar.Panel to stay clear of it.
	local frame = UIKit.panel(canvas, {
		name = "Panel",
		size = UDim2.fromOffset(#BUTTONS * BTN_W + (#BUTTONS - 1) * GAP, BTN_H),
		position = HIDDEN,
		anchorPoint = Vector2.new(0.5, 0),
		color = UIKit.C.panel,
		transparency = 1,
		strokeThickness = 0,
		visible = false,
	})

	for index, spec in BUTTONS do
		table.insert(entries, buildButton(frame, spec, (index - 1) * (BTN_W + GAP)))
	end

	panel = frame
	return gui
end

--- Slide the bar in (`next` true) or out. Out finishes with a token-guarded
--- Visible = false so a rapid out/in does not leave it hidden mid-slide — the same
--- pattern StageBannerController uses for its card.
local function setShown(next: boolean)
	local frame = panel
	if next == shown or frame == nil then
		return
	end
	shown = next

	if next then
		frame.Visible = true
		TweenService:Create(frame, SLIDE, { Position = SHOWN }):Play()
	else
		hideToken += 1
		local mine = hideToken
		TweenService:Create(frame, SLIDE, { Position = HIDDEN }):Play()
		task.delay(SLIDE.Time, function()
			if not shown and mine == hideToken and panel then
				panel.Visible = false
			end
		end)
	end
end

--- Turn every portal's bands. Only while the bar is on screen.
local function spin(dt: number)
	if panel == nil or not panel.Visible then
		return
	end
	for _, entry in entries do
		entry.angle = (entry.angle + entry.speed * dt) % 360
		entry.outer.Rotation = entry.angle
		entry.inner.Rotation = (entry.angle * INNER_SPIN) % 360
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
	RunService.Heartbeat:Connect(spin)
end

return WarpController
