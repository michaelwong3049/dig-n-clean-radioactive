--[[
	LiquidController.lua — the fluid panel at your bottle, and the spin it plays.

	Press ROLL on the fluid panel beside your tub (build/Plots.buildFluidBottle) and the
	server rolls a fluid, then fires FluidSpin with the answer already decided. This
	file only ANIMATES that answer: a reel of fluids scrolls through a window, slows,
	and stops on the one you got. It never asks the server for anything and has
	nothing it could send back to steer a result -- the request is a bare "roll".

	A POPUP, ON REQUEST. The user picked a screen spin over a wheel in the world. It
	opens on the spin, closes itself a moment after landing, and never takes input:
	you can walk away while it plays. The bottle behind it recolours when the reel
	lands (LiquidService holds the repaint until then), so the world does not give the
	result away first.

	THE REEL IS MADE OF REAL ROLLS at your luck (LiquidService.reelFor), so the fluids
	that flash past most are the ones that come up most -- the same job the wash pad's
	shelf of jars used to do, done by the spin itself.

	THE FLUID PANEL, on request. Walk up to your own bottle and a small panel slides in
	to the right of centre: the loaded fluid (a bottle in its colour, its name, washes
	left), a ROLL button that counts down the cooldown, and the Luck upgrade -- the
	multiplier you have and the price of the next +0.1x -- which used to be a lever
	staked out on the floor. It replaced a floating name sign over the bottle and an E
	prompt. Both buttons send FluidAction; the server checks you are at your bottle.
	The panel steps aside while a spin is playing and comes back once it closes.

	All sizes are 1280x720 design pixels on UIKit.canvas (hud-scale-canvas).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Liquids = require(Shared.Config.Liquids)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local Liquid = {}

-- ── Layout (design px) ───────────────────────────────────────────────────
local CARD_W, CARD_H = 640, 300
local WINDOW_W, WINDOW_H = 580, 132
local TILE_W, TILE_GAP = 104, 10
local PITCH = TILE_W + TILE_GAP
--- How long the reel rests on the result before the popup closes.
local HOLD_SECONDS = 1.8
local FADE_SECONDS = 0.25

--- Built-in sounds already used elsewhere in the client (DetonationController's fuse
--- tick, GeigerController's ping), so both are known to load.
local TICK_SOUND = "rbxasset://sounds/volume_slider.ogg"
local LAND_SOUND = "rbxasset://sounds/electronicpingshort.wav"

local ui: any = {}
--- Bumped on every spin, so a spin that starts while the last one is still closing
--- owns the popup and the older one's close timer does nothing.
local spinToken = 0

--- A little bottle drawn from Frames -- cap, neck, and a glass body with the fluid
--- filling most of it -- `s` times its reel-tile size, hung from its top-centre at
--- `position`. Returns the fluid frame, so the fluid panel can recolour it in place.
--- Frames rather than an image, so every fluid Config/Liquids ever adds gets a bottle
--- with no art to upload.
local function bottleIcon(parent: Instance, position: UDim2, s: number, colour: Color3): Frame
	local holder = Instance.new("Frame")
	holder.Name = "BottleIcon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(38 * s, 62 * s)
	holder.Position = position
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Parent = parent

	UIKit.panel(holder, {
		name = "Cap",
		size = UDim2.fromOffset(20 * s, 8 * s),
		position = UDim2.fromScale(0.5, 0),
		anchorPoint = Vector2.new(0.5, 0),
		color = Color3.fromHex("3A454E"),
		transparency = 0,
		cornerRadius = UDim.new(0, 3),
		strokeThickness = 0,
	})
	UIKit.panel(holder, {
		name = "Neck",
		size = UDim2.fromOffset(14 * s, 10 * s),
		position = UDim2.new(0.5, 0, 0, 7 * s),
		anchorPoint = Vector2.new(0.5, 0),
		color = Color3.fromHex("DDE4E8"),
		transparency = 0.75,
		cornerRadius = UDim.new(0, 3),
		strokeThickness = 2,
	})
	local glass = UIKit.panel(holder, {
		name = "Glass",
		size = UDim2.fromOffset(38 * s, 46 * s),
		position = UDim2.new(0.5, 0, 0, 16 * s),
		anchorPoint = Vector2.new(0.5, 0),
		color = Color3.fromHex("DDE4E8"),
		transparency = 0.75,
		cornerRadius = UDim.new(0, 10 * s),
		strokeThickness = 2,
	})
	local fluid = UIKit.panel(glass, {
		name = "Fluid",
		size = UDim2.new(1, -8 * s, 0.78, 0),
		position = UDim2.new(0.5, 0, 1, -4 * s),
		anchorPoint = Vector2.new(0.5, 1),
		color = colour,
		transparency = 0,
		cornerRadius = UDim.new(0, 7 * s),
		strokeThickness = 0,
	})
	return fluid
end

--- One tile in the reel: a little bottle filled with the fluid's colour over its name.
local function tile(parent: Instance, index: number, id: string): Frame
	local def = Liquids.get(id)
	local colour = Color3.fromHex(def.color)

	local frame, stroke = UIKit.panel(parent, {
		name = `Tile{index}`,
		size = UDim2.fromOffset(TILE_W, WINDOW_H - 16),
		position = UDim2.fromOffset((index - 1) * PITCH, 8),
		color = UIKit.C.empty,
		transparency = 0,
		cornerRadius = UIKit.Radius.slot,
		strokeThickness = UIKit.Stroke.thin,
	})
	stroke.Color = colour:Lerp(UIKit.C.panel, 0.45)

	bottleIcon(frame, UDim2.new(0.5, 0, 0, 10), 1, colour)

	UIKit.label(frame, {
		name = "Name",
		size = UDim2.new(1, -8, 0, 30),
		position = UDim2.new(0.5, 0, 1, -4),
		anchorPoint = Vector2.new(0.5, 1),
		text = def.name,
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		xAlign = Enum.TextXAlignment.Center,
		wrapped = true,
	})

	return frame
end

local function sound(id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = ui.gui
	return s
end

--- Build the popup once. Hidden until a spin arrives.
local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "FluidSpin"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Over the HUD and the station/warp bars, under the Index and Shop panels (110)
	-- and WashController's session layer (200).
	gui.DisplayOrder = 105
	gui.Enabled = false
	gui.Parent = playerGui
	ui.gui = gui

	local canvas = UIKit.canvas(gui)

	local card, cardStroke = UIKit.panel(canvas, {
		name = "Card",
		size = UDim2.fromOffset(CARD_W, CARD_H),
		position = UDim2.fromScale(0.5, 0.42),
		anchorPoint = Vector2.new(0.5, 0.5),
		color = UIKit.C.panel,
		transparency = 0.08,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
	})
	ui.card = card
	ui.cardStroke = cardStroke
	local scale = Instance.new("UIScale")
	scale.Parent = card
	ui.cardScale = scale

	UIKit.label(card, {
		name = "Title",
		size = UDim2.new(1, 0, 0, 44),
		position = UDim2.fromOffset(0, 14),
		text = "FLUID SPIN",
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.title,
		xAlign = Enum.TextXAlignment.Center,
	})

	-- The window the reel scrolls through. ClipsDescendants hides the tiles outside it.
	local window = UIKit.panel(card, {
		name = "Window",
		size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
		position = UDim2.new(0.5, 0, 0, 64),
		anchorPoint = Vector2.new(0.5, 0),
		color = Color3.fromHex("05070A"),
		transparency = 0,
		cornerRadius = UIKit.Radius.card,
		strokeThickness = UIKit.Stroke.normal,
	})
	window.ClipsDescendants = true
	ui.window = window

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.fromOffset(0, WINDOW_H)
	strip.Parent = window
	ui.strip = strip

	-- The pointer: an amber frame round the centre slot, and a notch above and below,
	-- so "this one" reads without a label.
	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.BackgroundTransparency = 1
	marker.Size = UDim2.fromOffset(TILE_W + 8, WINDOW_H - 6)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.ZIndex = 5
	marker.Parent = window
	local markerCorner = Instance.new("UICorner")
	markerCorner.CornerRadius = UIKit.Radius.slot
	markerCorner.Parent = marker
	local markerStroke = Instance.new("UIStroke")
	markerStroke.Color = UIKit.C.amber
	markerStroke.Thickness = 4
	markerStroke.Parent = marker
	ui.markerStroke = markerStroke
	for _, y in { 0, 1 } do
		local notch = Instance.new("Frame")
		notch.Name = "Notch"
		notch.BackgroundColor3 = UIKit.C.amber
		notch.BorderSizePixel = 0
		notch.Size = UDim2.fromOffset(16, 16)
		notch.Position = UDim2.fromScale(0.5, y)
		notch.AnchorPoint = Vector2.new(0.5, 0.5)
		notch.Rotation = 45
		notch.ZIndex = 6
		notch.Parent = window
	end

	ui.result = UIKit.label(card, {
		name = "Result",
		size = UDim2.new(1, -40, 0, 34),
		position = UDim2.new(0.5, 0, 0, 212),
		anchorPoint = Vector2.new(0.5, 0),
		text = "",
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.title,
		xAlign = Enum.TextXAlignment.Center,
	})
	ui.detail = UIKit.label(card, {
		name = "Detail",
		size = UDim2.new(1, -40, 0, 22),
		position = UDim2.new(0.5, 0, 0, 250),
		anchorPoint = Vector2.new(0.5, 0),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Center,
	})

	ui.tick = sound(TICK_SOUND, 0.25)
	ui.land = sound(LAND_SOUND, 0.5)
end

--- The strip's X offset that centres tile `position` (fractional, 1-based) in the window.
local function offsetFor(position: number): number
	return WINDOW_W / 2 - (position - 1) * PITCH - TILE_W / 2
end

local function close(token: number)
	if token ~= spinToken or ui.gui == nil then
		return
	end
	TweenService:Create(ui.cardScale, TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }):Play()
	task.delay(FADE_SECONDS, function()
		if token == spinToken then
			ui.gui.Enabled = false
		end
	end)
end

--- The line under the reel once it lands: what you got, and what it did to the hose.
local function describe(payload: any): (string, string)
	local def = Liquids.get(payload.result)
	local loaded = Liquids.get(payload.loaded)
	local washes = if payload.held == 1 then "1 wash" else `{payload.held} washes`
	if payload.loaded == payload.result then
		return `{def.name}!`, `loaded in the hose — {washes} in the bottle`
	end
	return `{def.name}`, `{washes} stored — kept {loaded.name} loaded`
end

local function play(payload: any)
	if type(payload) ~= "table" or type(payload.reel) ~= "table" then
		return
	end
	if ui.gui == nil then
		build()
	end
	spinToken += 1
	local token = spinToken

	for _, child in ui.strip:GetChildren() do
		child:Destroy()
	end
	for index, id in payload.reel do
		tile(ui.strip, index, id)
	end
	ui.strip.Size = UDim2.fromOffset(#payload.reel * PITCH, WINDOW_H)

	local land = tonumber(payload.land) or #payload.reel
	local seconds = math.max(tonumber(payload.seconds) or 4, 0.5)
	local from = 3
	ui.strip.Position = UDim2.fromOffset(offsetFor(from), 0)
	ui.result.Text = ""
	ui.result.TextColor3 = UIKit.C.text
	ui.detail.Text = "spinning\u{2026}"
	ui.markerStroke.Color = UIKit.C.amber
	ui.cardStroke.Color = UIKit.C.stroke
	ui.cardScale.Scale = 0.9
	ui.gui.Enabled = true
	TweenService:Create(ui.cardScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	-- Driven per frame rather than tweened so each tile crossing the pointer can tick.
	-- Quartic ease-out: fast through the common end, crawling as it reaches the result.
	local started = os.clock()
	local lastTile = from
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if token ~= spinToken then
			connection:Disconnect()
			return
		end
		local t = math.clamp((os.clock() - started) / seconds, 0, 1)
		local eased = 1 - (1 - t) ^ 4
		local position = from + (land - from) * eased
		ui.strip.Position = UDim2.fromOffset(offsetFor(position), 0)

		local centred = math.floor(position + 0.5)
		if centred ~= lastTile then
			lastTile = centred
			ui.tick:Play()
		end

		if t >= 1 then
			connection:Disconnect()
			local def = Liquids.get(payload.result)
			local colour = Color3.fromHex(def.color)
			local headline, detail = describe(payload)
			ui.result.Text = headline
			ui.result.TextColor3 = colour
			ui.detail.Text = detail
			ui.markerStroke.Color = colour
			ui.cardStroke.Color = colour
			ui.land:Play()
			local landed = ui.strip:FindFirstChild(`Tile{land}`)
			if landed then
				local pop = Instance.new("UIScale")
				pop.Scale = 1.12
				pop.Parent = landed
				TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			task.delay(HOLD_SECONDS, close, token)
		end
	end)
end

-- ── The fluid panel ──────────────────────────────────────────────────────

--- How close to your own bottle the panel opens, in studs from the bottle's body. Short
--- enough that the wash spot on the far side of the tub (~8 studs away) never opens it.
local PANEL_REACH = 6.5
local PANEL_W, PANEL_H = 300, 240
--- build/Kit.FLUID_TAG — the client cannot require build/, so the string is repeated.
local FLUID_TAG = "FluidSpin"

local panel: any = {}
--- The last FluidState, and when it arrived, so the ROLL countdown runs locally.
local state: any = nil
local stateAt = 0
local plotIndex: number? = nil
local noticeUntil = 0
local lastPress = 0

--- The bottle on the local player's own plot, found by tag.
local function ownBottle(): BasePart?
	if plotIndex == nil then
		return nil
	end
	for _, part in CollectionService:GetTagged(FLUID_TAG) do
		if part:IsA("BasePart") then
			local node: Instance? = part
			while node and node ~= Workspace do
				if node.Name == `Plot{plotIndex}` then
					return part
				end
				node = node.Parent
			end
		end
	end
	return nil
end

local function send(verb: string)
	-- A double-click is one press. The server has its own cooldown and prices; this
	-- only stops one click from arriving twice.
	if os.clock() - lastPress < 0.4 then
		return
	end
	lastPress = os.clock()
	Net.get("FluidAction"):FireServer(verb)
end

local function buildPanel()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "FluidPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Over the HUD, under the spin popup (105) and the Index/Shop panels (110).
	gui.DisplayOrder = 70
	gui.Parent = playerGui
	panel.gui = gui

	local canvas = UIKit.canvas(gui)

	-- Right of centre, so the character and the bottle stay in view in the middle of
	-- the screen, and clear of the Index/Shop tiles on the right edge.
	local card, cardStroke = UIKit.panel(canvas, {
		name = "Card",
		size = UDim2.fromOffset(PANEL_W, PANEL_H),
		position = UDim2.new(0.5, 150, 0.5, 0),
		anchorPoint = Vector2.new(0, 0.5),
		color = UIKit.C.panel,
		transparency = 0.08,
		cornerRadius = UIKit.Radius.panel,
		strokeThickness = UIKit.Stroke.thick,
		visible = false,
	})
	panel.card = card
	panel.cardStroke = cardStroke
	local scale = Instance.new("UIScale")
	scale.Parent = card
	panel.scale = scale

	UIKit.label(card, {
		name = "Header",
		size = UDim2.new(1, -32, 0, 20),
		position = UDim2.fromOffset(16, 12),
		text = "YOUR FLUID",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
	})

	panel.fluid = bottleIcon(card, UDim2.fromOffset(40, 38), 0.95, UIKit.C.text)
	panel.name = UIKit.label(card, {
		name = "FluidName",
		size = UDim2.new(1, -90, 0, 30),
		position = UDim2.fromOffset(76, 40),
		text = "Plain Water",
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.header + 3,
	})
	panel.left = UIKit.label(card, {
		name = "Washes",
		size = UDim2.new(1, -90, 0, 20),
		position = UDim2.fromOffset(76, 70),
		text = "never runs out",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
	})

	local roll, rollStroke = UIKit.button(card, {
		name = "Roll",
		size = UDim2.new(1, -32, 0, 46),
		position = UDim2.fromOffset(16, 104),
		text = "ROLL",
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.header + 3,
		fillColor = UIKit.C.green,
		fillTransparency = 0,
	})
	panel.roll = roll
	panel.rollStroke = rollStroke
	roll.Activated:Connect(function()
		if state and (state.cooldown or 0) - (os.clock() - stateAt) <= 0 then
			send("roll")
		end
	end)

	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = UIKit.C.stroke
	rule.BorderSizePixel = 0
	rule.Size = UDim2.new(1, -32, 0, 2)
	rule.Position = UDim2.fromOffset(16, 162)
	rule.Parent = card

	panel.luck = UIKit.label(card, {
		name = "Luck",
		size = UDim2.fromOffset(130, 24),
		position = UDim2.fromOffset(16, 172),
		text = "LUCK 1.0x",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
	})
	panel.boost = UIKit.label(card, {
		name = "Boost",
		size = UDim2.fromOffset(130, 18),
		position = UDim2.fromOffset(16, 196),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.amber,
	})
	local upgrade = UIKit.button(card, {
		name = "Upgrade",
		size = UDim2.fromOffset(134, 40),
		position = UDim2.new(1, -16, 0, 174),
		anchorPoint = Vector2.new(1, 0),
		text = "+0.1x $0",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		fillColor = Color3.fromHex("2F6FB0"),
		fillTransparency = 0,
	})
	panel.upgrade = upgrade
	upgrade.Activated:Connect(function()
		send("luck")
	end)

	panel.notice = UIKit.label(card, {
		name = "Notice",
		size = UDim2.new(1, -32, 0, 18),
		position = UDim2.fromOffset(16, 216),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.amber,
		xAlign = Enum.TextXAlignment.Center,
	})
end

--- Paint everything except the countdown from the last FluidState.
local function paintState()
	if panel.card == nil or state == nil then
		return
	end
	local def = Liquids.get(state.liquid)
	local colour = Color3.fromHex(def.color)
	panel.fluid.BackgroundColor3 = colour
	panel.name.Text = def.name
	panel.name.TextColor3 = colour
	panel.cardStroke.Color = colour:Lerp(UIKit.C.stroke, 0.35)
	local held = tonumber(state.held) or 0
	panel.left.Text = if state.liquid == Liquids.WATER
		then "never runs out \u{2014} roll for better"
		elseif held == 1 then "1 wash left"
		else `{held} washes left`
	panel.luck.Text = string.format("LUCK %.1fx", tonumber(state.luck) or 1)
	local boost = tonumber(state.boost) or 1
	panel.boost.Text = if boost > 1 then string.format("x%g boost active", boost) else "better roll odds"
	panel.boost.TextColor3 = if boost > 1 then UIKit.C.amber else UIKit.C.dim
	panel.upgrade.Text = `+0.1x  ${tonumber(state.luckPrice) or 0}`
end

--- The ROLL button's face: green and "ROLL" when ready, grey with the seconds left
--- while the cooldown runs.
local function paintRoll()
	if panel.roll == nil or state == nil then
		return
	end
	local left = math.ceil((tonumber(state.cooldown) or 0) - (os.clock() - stateAt))
	if left > 0 then
		panel.roll.Text = `ROLL IN {left}s`
		panel.roll.BackgroundColor3 = UIKit.C.empty
		panel.roll.TextColor3 = UIKit.C.dim
	else
		panel.roll.Text = "ROLL"
		panel.roll.BackgroundColor3 = UIKit.C.green
		panel.roll.TextColor3 = UIKit.C.text
	end
	if os.clock() > noticeUntil then
		panel.notice.Text = ""
	end
end

local function setOpen(open: boolean)
	if panel.card == nil or panel.card.Visible == open then
		return
	end
	panel.card.Visible = open
	if open then
		panel.scale.Scale = 0.9
		TweenService:Create(panel.scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

--- Open the panel while the local player stands at their own bottle, and not while a
--- spin is on screen. Polled at 10 Hz rather than per frame: it is a distance check,
--- and a tenth of a second is below what anyone notices walking up to a table.
local function watch()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		local bottle = ownBottle()
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local near = bottle ~= nil
			and root ~= nil
			and root:IsA("BasePart")
			and (root.Position - bottle.Position).Magnitude <= PANEL_REACH
		local spinning = ui.gui ~= nil and ui.gui.Enabled
		setOpen(near and state ~= nil and not spinning)
		paintRoll()
	end)
end

function Liquid.start()
	buildPanel()
	Net.get("FluidSpin").OnClientEvent:Connect(play)
	Net.get("FluidState").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		state = payload
		stateAt = os.clock()
		if type(payload.notice) == "string" then
			panel.notice.Text = payload.notice
			noticeUntil = os.clock() + 3
		end
		paintState()
		paintRoll()
	end)
	Net.get("PlotState").OnClientEvent:Connect(function(index)
		plotIndex = tonumber(index)
	end)
	watch()
end


return Liquid
