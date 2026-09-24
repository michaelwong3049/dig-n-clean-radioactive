--[[
	CrateController.lua — opening supply crates (Config/Crates): the Open prompt on the
	crate in your hands, and the nuke-crate reveal.

	THE PROMPT. Pick a crate from the hotbar and ToolService puts its model in your
	hands (`HeldItem`, stamped `CrateId` + `Uid`). This file hangs a plain native
	ProximityPrompt on it -- "Open", on F so it never fights the E prompts on the tub,
	the stands and the dig -- created HERE, on the client, so only the holder ever sees
	it. Triggering it sends CrateOpen with the uid; the server checks it really is the
	crate in your hands and rolls the prize.

	TWO POPUPS, ONE LOOK. A LIQUID crate plays the fluid bottle's own brew
	(LiquidController, FluidSpin) -- the server just sends that popup a reel drawn from
	the crate's table. A NUKE crate plays this file's popup, built as that brew's
	sibling: the same dimmed screen, light rays, burst, name slam, tier pill and chips.
	Where the brew has its flask, this has the NUKES THEMSELVES: every name on the reel
	flicks its own 3D model into the middle, fast at first and slowing down, each tick
	popping in with a faint glow in its rarity's colour, until it lands on your prize
	and bursts. (It used to be the crate rattling here; the user asked for the nukes.)
	The reel is made of real rolls off the crate's own table, so the nukes that flash
	past most are the ones that come up most.

	EVERY REEL MODEL IS BUILT ONCE, when the popup opens, and cached by item id: the
	reel ticks up to ~20 times a second and rebuilding a nuke per tick would hitch.
	They all live IN the ViewportFrame the whole time and the idle ones are parked far
	below the camera: a model freshly parented into a ViewportFrame can miss a frame
	before it draws, which at this tick rate read as a flicker, and a move never does.

	THE MESHES ARE PRELOADED BEFORE YOU OPEN ANYTHING. A nuke whose mesh this client has
	never downloaded draws as nothing the first time it flicks past (the Clockwork and
	Reactor nukes showed as an empty glow in testing). So the imported nuke templates
	are warmed with ContentProvider once in the background after you join, and again
	the moment you pick a crate up -- see preloadNukes.

	All sizes are 1280x720 design pixels on UIKit.canvas (hud-scale-canvas).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage.Shared
local Crates = require(Shared.Config.Crates)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local ItemModels = require(Shared.ItemModels)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local CrateController = {}

-- ── Shared look (LiquidController's brew) ─────────────────────────────

local INK = Color3.fromHex("0B0E09")
local CHIP_FILL = Color3.fromHex("1B2217")
local CHIP_STROKE = Color3.fromHex("2D3827")
local HOT_STROKE = Color3.fromHex("FF8A4C")
local HOT_TEXT = Color3.fromHex("FFB38A")

local TICK_SOUND = "rbxasset://sounds/volume_slider.ogg"
local LAND_SOUND = "rbxasset://sounds/electronicpingshort.wav"

--- The crate's view: its size and centre on the design canvas (the flask's spot).
local VIEW_X = 640
local VIEW_Y = 272
local VIEW = 300
local RAY_COUNT = 9
local HOLD_SECONDS = 3.2
local FADE_SECONDS = 0.25
local REEL_FROM = 3
local OVERSHOOT = 0.35

local HELD_ITEM_NAME = "HeldItem" -- ToolService's name for whatever is in your hands
local OPEN_KEY = Enum.KeyCode.F

local ui: any = {}
local spinToken = 0

local function round(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function outline(parent: Instance, colour: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = colour
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function plainFrame(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor
	frame.Parent = parent
	return frame
end

local function tween(instance: Instance, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(seconds, style, direction), goal):Play()
end

--- CashController.formatCash's ladder: $340, $5.2K, $1.4M, $2.1B.
local function formatCash(amount: number): string
	if amount >= 1_000_000_000 then
		return string.format("$%.1fB", amount / 1_000_000_000)
	elseif amount >= 1_000_000 then
		return string.format("$%.1fM", amount / 1_000_000)
	elseif amount >= 1_000 then
		return string.format("$%.1fK", amount / 1_000)
	end
	return string.format("$%d", math.floor(amount))
end

local function rarityColour(name: string?): (Color3, number)
	local def = if name then Rarity.DEFS[name] else nil
	if def == nil then
		return UIKit.C.dim, 0
	end
	return def.color, def.order
end

--- A rounded pill that grows sideways to fit its text (the brew's `pill`).
local function pill(parent: Instance, name: string, text: string, textSize: number, height: number, fill: Color3, textColour: Color3): (Frame, TextLabel)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromOffset(0, height)
	frame.BackgroundColor3 = fill
	frame.BorderSizePixel = 0
	frame.Parent = parent
	round(frame, UDim.new(1, 0))
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = frame
	local label = UIKit.label(frame, {
		name = "Text",
		size = UDim2.fromOffset(0, height),
		text = text,
		font = UIKit.Font.title,
		textSize = textSize,
		color = textColour,
		xAlign = Enum.TextXAlignment.Center,
		outline = textColour ~= INK,
		strokeTransparency = 1,
		shadow = false,
	})
	label.AutomaticSize = Enum.AutomaticSize.X
	return frame, label
end

-- ── The 3D view ───────────────────────────────────────────────────────

--- Strip every CollectionService tag (ItemFx and friends) from a model headed for the
--- viewport: the world controllers must not try to drive a copy that is not in it.
local function untag(model: Instance)
	for _, instance in { model, table.unpack(model:GetDescendants()) } do
		for _, tag in CollectionService:GetTags(instance) do
			CollectionService:RemoveTag(instance, tag)
		end
	end
end

--- One model ready for the viewport: centred on the origin (`home`), with the camera
--- that frames it.
type Framed = { model: Model, home: CFrame, camera: CFrame }

--- Where idle cached models wait, well out of the camera's view.
local PARKED = CFrame.new(0, -1000, 0)

--- Centre `model` on the origin, work out the camera that fits it, and park it in the
--- viewport. `display` brings it into view.
local function frame(model: Model): Framed
	untag(model)
	model:PivotTo(CFrame.new())
	local box, extents = model:GetBoundingBox()
	model:PivotTo(CFrame.new(-box.Position))

	local radius = extents.Magnitude / 2
	local distance = radius / math.tan(math.rad(ui.camera.FieldOfView / 2)) * 1.08
	local home = model:GetPivot()
	model:PivotTo(PARKED * home)
	model.Parent = ui.viewport
	return {
		model = model,
		home = home,
		camera = CFrame.lookAt(Vector3.new(0, radius * 0.45, -distance), Vector3.zero),
	}
end

--- Swap the view onto `framed` (nil shows nothing): park the last one, bring this one
--- home. Only one model is ever in front of the camera.
local function display(framed: Framed?)
	if ui.current and ui.current ~= framed then
		ui.current.model:PivotTo(PARKED * ui.current.home)
	end
	ui.current = framed
	if framed then
		framed.model:PivotTo(framed.home)
		ui.camera.CFrame = framed.camera
	end
end

--- Destroy every model cached for the last opening.
local function clearCache()
	display(nil)
	for _, framed in ui.cache or {} do
		framed.model:Destroy()
	end
	ui.cache = {}
end

--- The prize's model: the nuke's own art, or the rarity-coloured block every other
--- surface falls back to for an unmodelled item.
local function prizeModel(itemId: string, rarity: string): Model
	local ok, model = pcall(function()
		local def = Items.get(itemId)
		return ItemModels.create(def.model, itemId)
	end)
	if ok and model then
		return model
	end
	local block = Instance.new("Part")
	block.Size = Vector3.new(1.2, 1.2, 1.2)
	block.Color = (rarityColour(rarity))
	block.Material = Enum.Material.SmoothPlastic
	block.Anchored = true
	local wrapper = Instance.new("Model")
	block.Parent = wrapper
	wrapper.PrimaryPart = block
	return wrapper
end

--- The cached, framed model for one reel entry, built on first ask.
local function cached(itemId: string, rarity: string?): Framed
	ui.cache = ui.cache or {}
	local framed = ui.cache[itemId]
	if framed == nil then
		framed = frame(prizeModel(itemId, rarity or "Common"))
		ui.cache[itemId] = framed
	end
	return framed
end

-- ── Build ─────────────────────────────────────────────────────────────

local function sound(id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = ui.gui
	return s
end

local function buildRays(root: Frame)
	local rays = plainFrame(root, "Rays", UDim2.fromOffset(1000, 1000), UDim2.fromOffset(VIEW_X, VIEW_Y), Vector2.new(0.5, 0.5))
	rays.ZIndex = 1
	ui.rays = rays
	ui.rayBars = {}
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	for index = 1, RAY_COUNT do
		local bar = Instance.new("Frame")
		bar.Name = `Ray{index}`
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BackgroundTransparency = 1
		bar.Size = UDim2.new(0, 36, 1, 0)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Rotation = (index - 1) * 180 / RAY_COUNT
		bar.Parent = rays
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = fade
		gradient.Parent = bar
		table.insert(ui.rayBars, bar)
	end
end

local function buildView(root: Frame)
	local holder = plainFrame(root, "View", UDim2.fromOffset(VIEW, VIEW), UDim2.fromOffset(VIEW_X, VIEW_Y), Vector2.new(0.5, 0.5))
	holder.ZIndex = 3
	ui.viewHolder = holder
	ui.viewHome = holder.Position
	ui.viewScale = Instance.new("UIScale")
	ui.viewScale.Parent = holder

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(170, 170, 170)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.6, -1, 0.5)
	viewport.ZIndex = 3
	viewport.Parent = holder
	ui.viewport = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 36
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	ui.camera = camera

	-- A soft shadow on the "floor" under the crate, so it does not float in the dark.
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BorderSizePixel = 0
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.Size = UDim2.fromOffset(200, 34)
	shadow.Position = UDim2.new(0.5, 0, 1, -18)
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.ZIndex = 2
	shadow.Parent = holder
	round(shadow, UDim.new(0.5, 0))
end

local function buildResult(root: Frame)
	local top = VIEW_Y + VIEW / 2 + 22
	ui.header = UIKit.label(root, {
		name = "Header",
		size = UDim2.fromOffset(600, 26),
		position = UDim2.fromOffset(VIEW_X, VIEW_Y - VIEW / 2 - 34),
		anchorPoint = Vector2.new(0.5, 0),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
		zIndex = 5,
	})
	ui.cycle = UIKit.label(root, {
		name = "Cycle",
		size = UDim2.fromOffset(600, 36),
		position = UDim2.fromOffset(VIEW_X, top + 4),
		anchorPoint = Vector2.new(0.5, 0),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.title,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
		zIndex = 5,
	})

	-- The rarity of whatever is flicking past right now, under its name, on request, so
	-- a Legendary going by reads as one before it lands.
	local cycleTier = plainFrame(root, "CycleTierBox", UDim2.fromOffset(240, 22), UDim2.fromOffset(VIEW_X, top + 44), Vector2.new(0.5, 0))
	cycleTier.ZIndex = 5
	cycleTier.Visible = false
	ui.cycleTier = cycleTier
	ui.cycleTierPill, ui.cycleTierText = pill(cycleTier, "Tier", "", UIKit.TextSize.caption, 22, UIKit.C.dim, INK)
	ui.cycleTierPill.AnchorPoint = Vector2.new(0.5, 0)
	ui.cycleTierPill.Position = UDim2.fromScale(0.5, 0)

	local result = plainFrame(root, "Result", UDim2.fromOffset(760, 180), UDim2.fromOffset(VIEW_X, top - 6), Vector2.new(0.5, 0))
	result.ZIndex = 5
	result.Visible = false
	ui.result = result

	local nameBox = plainFrame(result, "NameBox", UDim2.fromOffset(760, 56), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
	ui.nameScale = Instance.new("UIScale")
	ui.nameScale.Parent = nameBox
	ui.name = UIKit.label(nameBox, {
		name = "NukeName",
		size = UDim2.fromScale(1, 1),
		text = "",
		font = UIKit.Font.hero,
		textSize = 48,
		xAlign = Enum.TextXAlignment.Center,
	})

	local tierBox = plainFrame(result, "TierBox", UDim2.fromOffset(240, 26), UDim2.new(0.5, 0, 0, 60), Vector2.new(0.5, 0))
	ui.tierScale = Instance.new("UIScale")
	ui.tierScale.Parent = tierBox
	ui.tierPill, ui.tierText = pill(tierBox, "Tier", "", UIKit.TextSize.caption, 26, UIKit.C.dim, INK)
	ui.tierPill.AnchorPoint = Vector2.new(0.5, 0)
	ui.tierPill.Position = UDim2.fromScale(0.5, 0)

	ui.flavour = UIKit.label(result, {
		name = "Flavour",
		size = UDim2.fromOffset(720, 20),
		position = UDim2.new(0.5, 0, 0, 94),
		anchorPoint = Vector2.new(0.5, 0),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body,
		color = Color3.fromHex("C9D3C2"),
		xAlign = Enum.TextXAlignment.Center,
	})

	local chips = plainFrame(result, "Chips", UDim2.fromOffset(760, 30), UDim2.new(0.5, 0, 0, 122), Vector2.new(0.5, 0))
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = chips
	ui.chips = chips

	ui.detail = UIKit.label(result, {
		name = "Detail",
		size = UDim2.fromOffset(720, 20),
		position = UDim2.new(0.5, 0, 0, 160),
		anchorPoint = Vector2.new(0.5, 0),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Center,
	})
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "CrateOpen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 105 -- the brew's layer: over the HUD, under Index/Shop and the wash
	gui.Enabled = false
	gui.Parent = playerGui
	ui.gui = gui

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 1
	dim.Parent = gui
	ui.dim = dim

	local canvas = UIKit.canvas(gui, 2)
	local root = plainFrame(canvas, "Crate", UDim2.fromOffset(UIKit.DESIGN_SCREEN.X, UIKit.DESIGN_SCREEN.Y), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	ui.root = root
	ui.scale = Instance.new("UIScale")
	ui.scale.Parent = root

	buildRays(root)
	buildView(root)
	buildResult(root)

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 3
	flash.Parent = gui
	ui.flash = flash

	ui.tick = sound(TICK_SOUND, 0.25)
	ui.land = sound(LAND_SOUND, 0.5)

	-- A one-line refusal ("already opening one"), on its own always-on layer.
	local noticeGui = Instance.new("ScreenGui")
	noticeGui.Name = "CrateNotice"
	noticeGui.ResetOnSpawn = false
	noticeGui.IgnoreGuiInset = true
	noticeGui.DisplayOrder = 104
	noticeGui.Parent = playerGui
	local noticeCanvas = UIKit.canvas(noticeGui)
	ui.notice = UIKit.label(noticeCanvas, {
		name = "Notice",
		size = UDim2.fromOffset(700, 28),
		position = UDim2.new(0.5, 0, 1, -170),
		anchorPoint = Vector2.new(0.5, 1),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		color = UIKit.C.amber or UIKit.C.text,
		xAlign = Enum.TextXAlignment.Center,
		visible = false,
	})
end

-- ── Play ──────────────────────────────────────────────────────────────

local noticeToken = 0
local function notice(text: string)
	if ui.gui == nil then
		build()
	end
	noticeToken += 1
	local token = noticeToken
	ui.notice.Text = text
	ui.notice.Visible = true
	task.delay(2.2, function()
		if token == noticeToken then
			ui.notice.Visible = false
		end
	end)
end

local function animateAmbient(dt: number)
	ui.rays.Rotation = (ui.rays.Rotation + dt * 8) % 360
end

--- Sparks flying out of the crate in the rarity's colour and the crate's.
local function burst(primary: Color3, secondary: Color3, count: number, spread: number)
	local palette = { primary, primary, secondary, Color3.new(1, 1, 1) }
	for index = 1, count do
		local size = math.random(6, 16)
		local spark = Instance.new("Frame")
		spark.Name = "Spark"
		spark.BorderSizePixel = 0
		spark.BackgroundColor3 = palette[(index % #palette) + 1]
		spark.Size = UDim2.fromOffset(size, size)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = UDim2.fromOffset(VIEW_X, VIEW_Y)
		spark.Rotation = math.random(0, 90)
		spark.ZIndex = 6
		spark.Parent = ui.root
		-- Square splinters, not droplets: this is a box bursting, not a flask.
		local angle = math.random() * math.pi * 2
		local reach = spread * (0.35 + 0.65 * math.random())
		local seconds = 0.8 + math.random() * 0.6
		tween(spark, seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
			Position = UDim2.fromOffset(VIEW_X + math.cos(angle) * reach, VIEW_Y + math.sin(angle) * reach + 50),
			Size = UDim2.fromOffset(size * 0.3, size * 0.3),
			Rotation = spark.Rotation + math.random(-240, 240),
			BackgroundTransparency = 1,
		})
		task.delay(seconds, spark.Destroy, spark)
	end
end

local function close(token: number)
	if token ~= spinToken or ui.gui == nil then
		return
	end
	tween(ui.scale, FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Scale = 0.92 })
	tween(ui.dim, FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { BackgroundTransparency = 1 })
	task.delay(FADE_SECONDS, function()
		if token == spinToken then
			ui.gui.Enabled = false
			if ui.connection then
				ui.connection:Disconnect()
				ui.connection = nil
			end
			clearCache()
		end
	end)
end

local function fillChips(payload: any): { Frame }
	for _, child in ui.chips:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local specs = {}
	if payload.modifier and payload.modifier ~= "None" then
		local label = if payload.modifier == "PrewarSealed" then "PREWAR SEALED" else string.upper(payload.modifier)
		table.insert(specs, { text = label, hot = true })
	end
	if type(payload.value) == "number" then
		table.insert(specs, { text = `WORTH {formatCash(payload.value)}`, hot = false })
	end
	if payload.firstFind then
		table.insert(specs, { text = "NEW FIND", hot = true })
	end
	local made = {}
	for index, spec in specs do
		local chip = pill(ui.chips, `Chip{index}`, spec.text, UIKit.TextSize.body, 30, CHIP_FILL, if spec.hot then HOT_TEXT else UIKit.C.text)
		chip.LayoutOrder = index
		outline(chip, if spec.hot then HOT_STROKE else CHIP_STROKE, 2)
		table.insert(made, chip)
	end
	return made
end

local function reveal(payload: any, token: number)
	local colour, rank = rarityColour(payload.rarity)
	local crateColour = Color3.fromHex(Crates.get(payload.crate).color)

	display(cached(payload.result, payload.rarity))
	ui.cycle.Visible = false
	ui.cycleTier.Visible = false

	ui.viewScale.Scale = 1.2
	tween(ui.viewScale, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	ui.flash.BackgroundTransparency = 0.35
	tween(ui.flash, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 1 })
	for _, bar in ui.rayBars do
		bar.BackgroundColor3 = colour
		tween(bar, 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 0.35 })
	end
	burst(colour, crateColour, 24 + rank * 6, 230 + rank * 30)
	ui.land.PlaybackSpeed = 0.85 + 0.07 * rank
	ui.land:Play()

	ui.tierPill.BackgroundColor3 = colour
	ui.tierText.Text = string.upper(payload.rarity or "")
	ui.name.Text = payload.name or ""
	ui.name.TextColor3 = colour
	ui.flavour.Text = payload.flavor or ""
	ui.detail.Text = "sealed and clean \u{2014} in your bag, ready to sell or display"
	local chips = fillChips(payload)
	ui.result.Visible = true

	ui.tierScale.Scale = 1.8
	tween(ui.tierScale, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	ui.nameScale.Scale = 1.9
	tween(ui.nameScale, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	for index, chip in chips do
		local grow = Instance.new("UIScale")
		grow.Scale = 0
		grow.Parent = chip
		task.delay(0.15 + index * 0.09, function()
			tween(grow, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
		end)
	end

	task.delay(HOLD_SECONDS, close, token)
end

local function play(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if type(payload.notice) == "string" then
		notice(payload.notice)
		return
	end
	if type(payload.reel) ~= "table" or #payload.reel == 0 or not Crates.has(payload.crate) then
		return
	end
	if ui.gui == nil then
		build()
	end
	spinToken += 1
	local token = spinToken
	if ui.connection then
		ui.connection:Disconnect()
		ui.connection = nil
	end

	local crate = Crates.get(payload.crate)
	local reel = payload.reel
	local land = math.clamp(tonumber(payload.land) or #reel, 1, #reel)
	local seconds = math.max(tonumber(payload.seconds) or 4.5, 0.5)
	local from = math.min(REEL_FROM, land)

	-- Every nuke the reel can show, built now (behind the popup's own scale-in) so the
	-- flicker below never builds anything mid-spin.
	clearCache()
	for _, entry in reel do
		if type(entry) == "table" and type(entry.itemId) == "string" then
			cached(entry.itemId, entry.rarity)
		end
	end
	local first = reel[from]
	display(if first then cached(first.itemId, first.rarity) else nil)
	ui.header.Text = string.upper(crate.name)
	ui.header.TextColor3 = Color3.fromHex(crate.color)
	ui.result.Visible = false
	ui.cycle.Visible = true
	ui.cycle.Text = ""
	ui.cycleTier.Visible = false
	ui.viewHolder.Position = ui.viewHome
	ui.viewScale.Scale = 1
	for _, bar in ui.rayBars do
		bar.BackgroundTransparency = 1
	end
	ui.scale.Scale = 0.92
	ui.dim.BackgroundTransparency = 1
	ui.gui.Enabled = true
	tween(ui.scale, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	tween(ui.dim, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 0.45 })

	-- The brew's own easing: quartic ease-out to just past (or short of) the result,
	-- then a smoothstep back onto it.
	local overshoot = (math.random() * 2 - 1) * OVERSHOOT
	local mainSeconds = seconds * 0.88
	local started = os.clock()
	local lastTile = from
	local tickedAt = 0
	local landed = false
	ui.connection = RunService.RenderStepped:Connect(function(dt)
		if token ~= spinToken then
			return
		end
		local elapsed = os.clock() - started
		if not landed then
			local position
			if elapsed < mainSeconds then
				position = from + (land + overshoot - from) * (1 - (1 - elapsed / mainSeconds) ^ 4)
			else
				local t = math.clamp((elapsed - mainSeconds) / (seconds - mainSeconds), 0, 1)
				position = land + overshoot * (1 - t * t * (3 - 2 * t))
			end

			local centred = math.clamp(math.floor(position + 0.5), 1, #reel)
			if centred ~= lastTile then
				lastTile = centred
				tickedAt = elapsed
				local entry = reel[centred]
				local colour = rarityColour(entry.rarity)
				display(cached(entry.itemId, entry.rarity))
				ui.cycle.Text = entry.name or "???"
				ui.cycle.TextColor3 = colour
				ui.cycleTierText.Text = string.upper(entry.rarity or "")
				ui.cycleTierPill.BackgroundColor3 = colour
				ui.cycleTier.Visible = entry.rarity ~= nil
				-- A faint glow in this nuke's rarity behind it, so a Legendary flicking
				-- past is felt before it is read. The real rays wait for the landing.
				for _, bar in ui.rayBars do
					bar.BackgroundColor3 = colour
					bar.BackgroundTransparency = 0.82
				end
				ui.tick:Play()
			end

			-- Each nuke pops in a touch large and settles, and the current one turns.
			local pop = math.max(0, 1 - (elapsed - tickedAt) / 0.12)
			ui.viewScale.Scale = 1 + 0.12 * pop
			if ui.current then
				-- Rotation on the LEFT: about the model's centre (the origin), not its pivot.
				ui.current.model:PivotTo(CFrame.Angles(0, elapsed * 1.6, 0) * ui.current.home)
			end

			if elapsed >= seconds then
				landed = true
				reveal(payload, token)
			end
		elseif ui.current then
			-- The prize turns slowly on its plinth while the result is up.
			ui.current.model:PivotTo(CFrame.Angles(0, elapsed * 0.8, 0) * ui.current.home)
		end
		animateAmbient(dt)
	end)
end

-- ── Preloading ────────────────────────────────────────────────────────

--- Seconds after joining before the background warm-up, so it never competes with
--- the first things a player loads.
local PRELOAD_DELAY = 20
local preloaded = false

--- Download every imported nuke mesh once, so no reel shows a blank. Idempotent and
--- non-blocking; the templates live in ReplicatedStorage.Assets (Shared/ItemModels).
local function preloadNukes()
	if preloaded then
		return
	end
	preloaded = true
	task.spawn(function()
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local templates = assets and assets:FindFirstChild("ImportedNukeTemplates")
		if templates then
			pcall(function()
				ContentProvider:PreloadAsync({ templates })
			end)
		end
	end)
end

-- ── The Open prompt ───────────────────────────────────────────────────

local openRemote: any = nil
local prompt: ProximityPrompt? = nil

local function clearPrompt()
	if prompt then
		prompt:Destroy()
		prompt = nil
	end
end

--- Hang (or take down) the Open prompt for whatever is in the local player's hands.
local function refreshPrompt(character: Model?)
	local held = if character then character:FindFirstChild(HELD_ITEM_NAME) else nil
	local crateId = if held then held:GetAttribute("CrateId") else nil
	local uid = if held then held:GetAttribute("Uid") else nil
	if held == nil or not Crates.has(crateId) or type(uid) ~= "string" then
		clearPrompt()
		return
	end
	-- A crate in hand is about to be opened: make sure the reel's nukes are loaded.
	preloadNukes()
	if prompt and prompt:GetAttribute("Uid") == uid and prompt.Parent and prompt.Parent:IsDescendantOf(held) then
		return
	end
	clearPrompt()

	local anchor = (held :: Model).PrimaryPart or held:FindFirstChildWhichIsA("BasePart", true)
	if anchor == nil then
		return
	end

	local p = Instance.new("ProximityPrompt")
	p.Name = "CrateOpenPrompt"
	p.ActionText = "Open"
	p.ObjectText = Crates.get(crateId).name
	p.KeyboardKeyCode = OPEN_KEY
	p.GamepadKeyCode = Enum.KeyCode.ButtonY
	p.HoldDuration = 0.35
	p.MaxActivationDistance = 20
	p.RequiresLineOfSight = false
	-- Shown alongside the E prompts on the tub and the stands rather than competing
	-- with them: it is on a different key.
	p.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	p:SetAttribute("Uid", uid)
	p.Triggered:Connect(function()
		openRemote:FireServer(uid)
	end)
	p.Parent = anchor
	prompt = p
end

local function watchCharacter(character: Model)
	refreshPrompt(character)
	character.ChildAdded:Connect(function(child)
		if child.Name == HELD_ITEM_NAME then
			refreshPrompt(character)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child.Name == HELD_ITEM_NAME then
			refreshPrompt(character)
		end
	end)
end

function CrateController.start()
	openRemote = Net.get("CrateOpen")
	Net.get("CrateOpened").OnClientEvent:Connect(play)

	task.delay(PRELOAD_DELAY, preloadNukes)

	local player = Players.LocalPlayer
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

return CrateController
