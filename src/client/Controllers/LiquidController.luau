--[[
	LiquidController.lua — the fluid spin, on your screen.

	Press E on the fluid bottle beside your tub (build/Plots.buildFluidBottle) and the
	server rolls a fluid, then fires FluidSpin with the answer already decided. This
	file only ANIMATES that answer: a reel of fluids scrolls through a window, slows,
	and stops on the one you got. It never asks the server for anything and has
	nothing it could send back to steer a result -- the request half is the bottle's
	ProximityPrompt, which fires on the server on its own.

	A POPUP, ON REQUEST. The user picked a screen spin over a wheel in the world. It
	opens on the spin, closes itself a moment after landing, and never takes input:
	you can walk away while it plays. The bottle behind it recolours when the reel
	lands (LiquidService holds the repaint until then), so the world does not give the
	result away first.

	THE REEL IS MADE OF REAL ROLLS at your luck (LiquidService.reelFor), so the fluids
	that flash past most are the ones that come up most -- the same job the wash pad's
	shelf of jars used to do, done by the spin itself.

	THIS USED TO BE the loaded-fluid billboard over the wash pad. The pad is gone; the
	bottle's own colour and sign now say what is loaded, and WashController's
	WashFluidBar says it during a wash.

	All sizes are 1280x720 design pixels on UIKit.canvas (hud-scale-canvas).
]]

local Players = game:GetService("Players")
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

--- One tile in the reel: a little bottle filled with the fluid's colour over its name.
--- Drawn from Frames (glass body, fluid, neck, cap) rather than an image, so every
--- fluid Config/Liquids ever adds gets a tile with no art to upload.
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

	-- The bottle: glass body with the fluid filling most of it, a neck and a cap.
	local glass = UIKit.panel(frame, {
		name = "Glass",
		size = UDim2.fromOffset(38, 46),
		position = UDim2.new(0.5, 0, 0, 26),
		anchorPoint = Vector2.new(0.5, 0),
		color = Color3.fromHex("DDE4E8"),
		transparency = 0.75,
		cornerRadius = UDim.new(0, 10),
		strokeThickness = 2,
	})
	UIKit.panel(glass, {
		name = "Fluid",
		size = UDim2.new(1, -8, 0.78, 0),
		position = UDim2.new(0.5, 0, 1, -4),
		anchorPoint = Vector2.new(0.5, 1),
		color = colour,
		transparency = 0,
		cornerRadius = UDim.new(0, 7),
		strokeThickness = 0,
	})
	UIKit.panel(frame, {
		name = "Neck",
		size = UDim2.fromOffset(14, 10),
		position = UDim2.new(0.5, 0, 0, 17),
		anchorPoint = Vector2.new(0.5, 0),
		color = Color3.fromHex("DDE4E8"),
		transparency = 0.75,
		cornerRadius = UDim.new(0, 3),
		strokeThickness = 2,
	})
	UIKit.panel(frame, {
		name = "Cap",
		size = UDim2.fromOffset(20, 8),
		position = UDim2.new(0.5, 0, 0, 10),
		anchorPoint = Vector2.new(0.5, 0),
		color = Color3.fromHex("3A454E"),
		transparency = 0,
		cornerRadius = UDim.new(0, 3),
		strokeThickness = 0,
	})

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

function Liquid.start()
	Net.get("FluidSpin").OnClientEvent:Connect(play)
end

return Liquid
