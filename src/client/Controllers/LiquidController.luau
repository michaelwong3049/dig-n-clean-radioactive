--[[
	LiquidController.lua — the fluid panel at your bottle, and the brew it plays.

	Press BREW on the fluid panel beside your tub (build/Plots.buildFluidBottle) and the
	server rolls a fluid, then fires FluidSpin with the answer already decided. This
	file only ANIMATES that answer. It never asks the server for anything and has
	nothing it could send back to steer a result -- the request is a bare "roll".

	THE FLASK BREW, picked from six mockups (option 5). There is no card: a big
	round-bottomed flask sits on a burner in the middle of the screen. Its liquid flashes
	through the fluids of the reel, fast at first, then slower, shaking harder the closer
	it gets to stopping. When it stops, the flask pops, a flash and a burst of droplets
	go off in the fluid's colour, light rays turn behind it in the TIER colour
	(Config/Liquids `tier`, painted from Config/Rarity), and the name slams in over its
	stats. It closes itself a moment later and never takes input, so you can walk away
	while it plays. The bottle in the world recolours when it lands (LiquidService holds
	the repaint until then), so the world does not give the result away first.

	THE REEL IS MADE OF REAL ROLLS at your luck (LiquidService.reelFor), so the colours
	that flash through the flask most are the fluids that come up most.

	THE FLASK IS FRAMES. The bulb is a round CanvasGroup, because a CanvasGroup clips its
	children to its UICorner and a plain Frame's ClipsDescendants only clips to the
	rectangle; the liquid inside is a frame hung from a pivot at its surface, so tilting
	the pivot sloshes the surface while the glass shakes. A metal collar sits over the
	place the neck meets the bulb, which hides where the two outlines cross.

	THE FLUID PANEL. Walk up to your own bottle and it slides in to the right of centre:
	the loaded fluid (a bottle filled to what is left, its tier, name, washes and
	stats), a BREW button that counts down the cooldown, and the Luck upgrade with what
	the next +0.1x does to the jackpot's odds (worked out from FluidState's `rollLuck`,
	the same number the server rolls with). Both buttons send FluidAction; the server
	checks you are at your bottle. The panel steps aside while a brew is playing.

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
local Rarity = require(Shared.Config.Rarity)
local Gear = require(Shared.Config.Gear)
local Tuning = require(Shared.Config.Tuning)
local Crates = require(Shared.Config.Crates)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)

local Liquid = {}

-- ── Shared look ──────────────────────────────────────────────────────────

local GLASS = Color3.fromHex("DDE4E8")
local METAL = Color3.fromHex("3A454E")
--- Dark text on a bright pill (the tier chip).
local INK = Color3.fromHex("0B0E09")
local CHIP_FILL = Color3.fromHex("1B2217")
local CHIP_STROKE = Color3.fromHex("2D3827")
--- The "+N CRACK" chip: potency is the stat that reaches past your hose, so it glows.
local HOT_STROKE = Color3.fromHex("FF8A4C")
local HOT_TEXT = Color3.fromHex("FFB38A")

--- Built-in sounds already used elsewhere in the client (DetonationController's fuse
--- tick, GeigerController's ping), so both are known to load.
local TICK_SOUND = "rbxasset://sounds/volume_slider.ogg"
local LAND_SOUND = "rbxasset://sounds/electronicpingshort.wav"

--- A fluid's tier name and colour. Water has no tier (it is never rolled) and reads
--- as BASIC in the panel's dim grey.
local function tierOf(def: any): (string, Color3, number)
	local rarity = def.tier and Rarity.DEFS[def.tier]
	if rarity == nil then
		return "BASIC", UIKit.C.dim, 0
	end
	return string.upper(def.tier), rarity.color, rarity.order
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

--- "41%" for the common end, "1 in 814" once a chance is small enough that a
--- percentage stops meaning anything to a player.
local function oneIn(chance: number): string
	if chance <= 0 then
		return "never"
	elseif chance >= 0.1 then
		return string.format("%d%%", math.floor(chance * 100 + 0.5))
	end
	return `1 in {math.floor(1 / chance + 0.5)}`
end

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

--- A rounded pill that grows sideways to fit its text. Returns the pill and its label.
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
		-- Dark ink on the bright tier chip; a black outline would just smear it.
		outline = textColour ~= INK,
		strokeTransparency = 1,
		shadow = false,
	})
	label.AutomaticSize = Enum.AutomaticSize.X
	return frame, label
end

--- A horizontal row that lays out its children left to right (or centred).
local function chipRow(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2, centred: boolean): Frame
	local row = plainFrame(parent, name, size, position, anchor)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = if centred then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row
	return row
end

--- Refill a chip row with a fluid's stats: how fast it scrubs, what it pays, and the
--- potency bonus when it has one. Returns the chips in order, for the reveal's pop-in.
local function fillChips(row: Frame, def: any, textSize: number, height: number): { Frame }
	for _, child in row:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local specs = {
		{ text = string.format("SCRUB x%.2f", def.rateMult), hot = false },
		{ text = string.format("PAY x%.2f", def.xpMult), hot = false },
	}
	if def.potency > 0 then
		table.insert(specs, { text = `+{def.potency} CRACK`, hot = true })
	end
	local made = {}
	for index, spec in specs do
		local chip = pill(row, `Chip{index}`, spec.text, textSize, height, CHIP_FILL, if spec.hot then HOT_TEXT else UIKit.C.text)
		chip.LayoutOrder = index
		outline(chip, if spec.hot then HOT_STROKE else CHIP_STROKE, 2)
		table.insert(made, chip)
	end
	return made
end

--- A little bottle drawn from Frames -- cap, neck, and a glass body with the fluid
--- in it -- `s` times its base size, hung from its top-centre at `position`. Returns
--- the fluid frame, so the panel can recolour and refill it in place. Frames rather
--- than an image, so every fluid Config/Liquids ever adds gets a bottle with no art.
local function bottleIcon(parent: Instance, position: UDim2, s: number, colour: Color3): Frame
	local holder = plainFrame(parent, "BottleIcon", UDim2.fromOffset(38 * s, 62 * s), position, Vector2.new(0.5, 0))

	UIKit.panel(holder, {
		name = "Cap",
		size = UDim2.fromOffset(20 * s, 8 * s),
		position = UDim2.fromScale(0.5, 0),
		anchorPoint = Vector2.new(0.5, 0),
		color = METAL,
		transparency = 0,
		cornerRadius = UDim.new(0, 3),
		strokeThickness = 0,
	})
	UIKit.panel(holder, {
		name = "Neck",
		size = UDim2.fromOffset(14 * s, 10 * s),
		position = UDim2.new(0.5, 0, 0, 7 * s),
		anchorPoint = Vector2.new(0.5, 0),
		color = GLASS,
		transparency = 0.75,
		cornerRadius = UDim.new(0, 3),
		strokeThickness = 2,
	})
	local glass = UIKit.panel(holder, {
		name = "Glass",
		size = UDim2.fromOffset(38 * s, 46 * s),
		position = UDim2.new(0.5, 0, 0, 16 * s),
		anchorPoint = Vector2.new(0.5, 0),
		color = GLASS,
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

-- ── The brew ─────────────────────────────────────────────────────────────

--- The flask's bulb: its diameter, and its centre on the design canvas.
local FLASK_X = 640
local BULB = 190
local BULB_Y = 272
--- Where the liquid's surface sits, as a fraction of the bulb from its top.
local LIQUID_LEVEL = 0.38
local BUBBLE_COUNT = 12
--- Beams through the centre, so twice this many rays.
local RAY_COUNT = 9
--- How long the result stays up before the brew closes.
local HOLD_SECONDS = 2.4
local FADE_SECONDS = 0.25
--- Where the reel starts, and how far past the result (in tiles, either way) the
--- flask may drift before settling back onto it -- the "almost stopped on the next
--- one" beat.
local REEL_FROM = 3
local OVERSHOOT = 0.35

local ui: any = {}
--- Bumped on every brew, so a brew that starts while the last one is still closing
--- owns the popup and the older one's close timer does nothing.
local spinToken = 0

local function sound(id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = ui.gui
	return s
end

--- Light rays behind the flask: beams across the centre, fading out toward both ends,
--- tinted the tier colour on landing. Invisible until then.
local function buildRays(root: Frame)
	local rays = plainFrame(root, "Rays", UDim2.fromOffset(1000, 1000), UDim2.fromOffset(FLASK_X, BULB_Y), Vector2.new(0.5, 0.5))
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

--- The burner the flask sits on, and its flame (three nested blobs that flicker).
local function buildBurner(root: Frame)
	local bottom = BULB_Y + BULB / 2
	local flame = plainFrame(root, "Flame", UDim2.fromOffset(70, 48), UDim2.fromOffset(FLASK_X, bottom + 18), Vector2.new(0.5, 1))
	flame.ZIndex = 2
	ui.flames = {}
	for index, spec in { { 48, 46, "FF7A1A" }, { 30, 32, "FFD24A" }, { 14, 18, "FFF6C9" } } do
		local blob = Instance.new("Frame")
		blob.Name = `Blob{index}`
		blob.BorderSizePixel = 0
		blob.BackgroundColor3 = Color3.fromHex(spec[3])
		blob.Size = UDim2.fromOffset(spec[1], spec[2])
		blob.Position = UDim2.fromScale(0.5, 1)
		blob.AnchorPoint = Vector2.new(0.5, 1)
		blob.ZIndex = index
		blob.Parent = flame
		round(blob, UDim.new(0.5, 0))
		table.insert(ui.flames, { frame = blob, w = spec[1], h = spec[2] })
	end

	local burner = UIKit.panel(root, {
		name = "Burner",
		size = UDim2.fromOffset(150, 30),
		position = UDim2.fromOffset(FLASK_X, bottom + 16),
		anchorPoint = Vector2.new(0.5, 0),
		color = Color3.fromHex("5A6167"),
		transparency = 0,
		cornerRadius = UDim.new(0, 8),
		strokeColor = UIKit.C.outline,
		strokeThickness = 3,
		zIndex = 4,
	})
	burner.ZIndex = 4
end

--- The flask: bulb (a round CanvasGroup holding the liquid, bubbles and a glare),
--- its outline, the neck, the collar hiding the join, and a stopper.
local function buildFlask(root: Frame)
	-- Holder coordinates: 200 wide, 300 tall, the bulb filling the bottom 190.
	local flask = plainFrame(root, "Flask", UDim2.fromOffset(200, 300), UDim2.fromOffset(FLASK_X, BULB_Y + BULB / 2), Vector2.new(0.5, 1))
	flask.ZIndex = 3
	ui.flask = flask
	ui.flaskHome = flask.Position
	local pop = Instance.new("UIScale")
	pop.Parent = flask
	ui.flaskScale = pop

	local bulb = Instance.new("CanvasGroup")
	bulb.Name = "Bulb"
	bulb.BorderSizePixel = 0
	bulb.BackgroundColor3 = GLASS
	bulb.BackgroundTransparency = 0.86
	bulb.Size = UDim2.fromOffset(BULB, BULB)
	bulb.Position = UDim2.fromScale(0.5, 1)
	bulb.AnchorPoint = Vector2.new(0.5, 1)
	bulb.ZIndex = 1
	bulb.Parent = flask
	round(bulb, UDim.new(1, 0))

	-- The liquid hangs from a pivot at its surface, twice the bulb's size so the body
	-- still fills the glass when the pivot tilts. Rotating the pivot tilts the surface.
	local surface = plainFrame(bulb, "Surface", UDim2.fromScale(2, 2), UDim2.fromScale(0.5, LIQUID_LEVEL), Vector2.new(0.5, 0.5))
	ui.surface = surface
	local body = Instance.new("Frame")
	body.Name = "Liquid"
	body.BorderSizePixel = 0
	body.Size = UDim2.fromScale(1, 0.5)
	body.Position = UDim2.fromScale(0, 0.5)
	body.Parent = surface
	ui.liquid = body
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.BorderSizePixel = 0
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.BackgroundTransparency = 0.55
	sheen.Size = UDim2.new(1, 0, 0, 6)
	sheen.Position = UDim2.fromScale(0, 0.5)
	sheen.Parent = surface

	ui.bubbles = {}
	for index = 1, BUBBLE_COUNT do
		local radius = math.random(2, 6)
		local bubble = Instance.new("Frame")
		bubble.Name = `Bubble{index}`
		bubble.BorderSizePixel = 0
		bubble.BackgroundColor3 = Color3.new(1, 1, 1)
		bubble.BackgroundTransparency = 0.45
		bubble.Size = UDim2.fromOffset(radius * 2, radius * 2)
		bubble.AnchorPoint = Vector2.new(0.5, 0.5)
		bubble.ZIndex = 2
		bubble.Parent = bulb
		round(bubble, UDim.new(1, 0))
		table.insert(ui.bubbles, {
			frame = bubble,
			x = BULB * (0.22 + 0.56 * math.random()),
			y = BULB * (LIQUID_LEVEL + (1 - LIQUID_LEVEL) * math.random()),
			rate = 0.5 + math.random(),
		})
	end

	local glare = Instance.new("Frame")
	glare.Name = "Glare"
	glare.BorderSizePixel = 0
	glare.BackgroundColor3 = Color3.new(1, 1, 1)
	glare.BackgroundTransparency = 0.5
	glare.Size = UDim2.fromOffset(16, 62)
	glare.Position = UDim2.fromOffset(38, 104)
	glare.AnchorPoint = Vector2.new(0.5, 0.5)
	glare.Rotation = 22
	glare.ZIndex = 3
	glare.Parent = bulb
	round(glare, UDim.new(1, 0))

	local rim = plainFrame(flask, "Rim", UDim2.fromOffset(BULB, BULB), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1))
	rim.ZIndex = 2
	round(rim, UDim.new(1, 0))
	outline(rim, GLASS, 5)

	-- The rim crosses the neck ~3 studs below the bulb's top (y 110 + 3); the collar
	-- is centred there and the neck's own bottom edge ends under it.
	UIKit.panel(flask, {
		name = "Neck",
		size = UDim2.fromOffset(52, 78),
		position = UDim2.fromOffset(100, 118),
		anchorPoint = Vector2.new(0.5, 1),
		color = GLASS,
		transparency = 0.86,
		cornerRadius = UDim.new(0, 6),
		strokeColor = GLASS,
		strokeThickness = 5,
		zIndex = 3,
	})
	for _, spec in { { "Collar", 72, 18, 113 }, { "Stopper", 64, 20, 40 } } do
		UIKit.panel(flask, {
			name = spec[1],
			size = UDim2.fromOffset(spec[2], spec[3]),
			position = UDim2.fromOffset(100, spec[4]),
			anchorPoint = Vector2.new(0.5, 0.5),
			color = METAL,
			transparency = 0,
			cornerRadius = UDim.new(0, 6),
			strokeColor = UIKit.C.outline,
			strokeThickness = 2,
			zIndex = 4,
		})
	end
end

--- The name that flickers under the flask while it brews, and the result block that
--- replaces it: tier chip, name, flavour line, stat chips, and what it did to the hose.
local function buildResult(root: Frame)
	local top = BULB_Y + BULB / 2 + 58
	ui.cycle = UIKit.label(root, {
		name = "Cycle",
		size = UDim2.fromOffset(600, 36),
		position = UDim2.fromOffset(FLASK_X, top + 4),
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
	local cycleTier = plainFrame(root, "CycleTierBox", UDim2.fromOffset(240, 22), UDim2.fromOffset(FLASK_X, top + 44), Vector2.new(0.5, 0))
	cycleTier.ZIndex = 5
	cycleTier.Visible = false
	ui.cycleTier = cycleTier
	ui.cycleTierPill, ui.cycleTierText = pill(cycleTier, "Tier", "", UIKit.TextSize.caption, 22, UIKit.C.dim, INK)
	ui.cycleTierPill.AnchorPoint = Vector2.new(0.5, 0)
	ui.cycleTierPill.Position = UDim2.fromScale(0.5, 0)

	local result = plainFrame(root, "Result", UDim2.fromOffset(760, 180), UDim2.fromOffset(FLASK_X, top - 6), Vector2.new(0.5, 0))
	result.ZIndex = 5
	result.Visible = false
	ui.result = result

	local nameBox = plainFrame(result, "NameBox", UDim2.fromOffset(760, 56), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
	ui.nameScale = Instance.new("UIScale")
	ui.nameScale.Parent = nameBox
	ui.name = UIKit.label(nameBox, {
		name = "FluidName",
		size = UDim2.fromScale(1, 1),
		text = "",
		font = UIKit.Font.hero,
		textSize = 48,
		xAlign = Enum.TextXAlignment.Center,
	})

	-- The rarity sits right under the name, on request.
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
	ui.chips = chipRow(result, "Chips", UDim2.fromOffset(760, 30), UDim2.new(0.5, 0, 0, 122), Vector2.new(0.5, 0), true)
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

--- Build the brew once. Hidden until a spin arrives.
local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "FluidSpin"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Over the HUD and the station/warp bars, under the Index and Shop panels (110)
	-- and WashController's session layer (200).
	gui.DisplayOrder = 105
	gui.Enabled = false
	gui.Parent = playerGui
	ui.gui = gui

	-- The world dims behind the flask so the burst reads. Full screen, not canvas: the
	-- canvas is letterboxed to 16:9 and the dim should reach every edge.
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 1
	dim.Parent = gui
	ui.dim = dim

	-- A fixed 1280x720 box centred on the canvas. The canvas itself is the whole screen
	-- in design px, so it is wider than 1280 on anything but 16:9, and every Offset
	-- below (FLASK_X = 640 and friends) is measured inside this box, not the screen.
	local canvas = UIKit.canvas(gui, 2)
	local root = plainFrame(canvas, "Brew", UDim2.fromOffset(UIKit.DESIGN_SCREEN.X, UIKit.DESIGN_SCREEN.Y), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	ui.root = root
	ui.scale = Instance.new("UIScale")
	ui.scale.Parent = root

	buildRays(root)
	buildBurner(root)
	buildFlask(root)
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
end

local function tween(instance: Instance, seconds: number, style: Enum.EasingStyle, direction: Enum.EasingDirection, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(seconds, style, direction), goal):Play()
end

--- The flask's liquid, recoloured.
local function paintLiquid(id: string)
	ui.liquid.BackgroundColor3 = Color3.fromHex(Liquids.get(id).color)
end

--- Bubbles, flame and rays: the parts that keep moving the whole time the brew is up.
--- `speed` is how fast the reel is running, in fluids per second -- the brew boils
--- harder the faster it spins.
local function animateAmbient(dt: number, speed: number)
	for _, bubble in ui.bubbles do
		bubble.y -= bubble.rate * (28 + speed * 9) * dt
		if bubble.y < BULB * LIQUID_LEVEL then
			bubble.y = BULB - 12
			bubble.x = BULB * (0.22 + 0.56 * math.random())
		end
		bubble.frame.Position = UDim2.fromOffset(bubble.x + math.sin(bubble.y / 9) * 3, bubble.y)
	end
	for _, flame in ui.flames do
		local flicker = 0.88 + math.random() * 0.28
		flame.frame.Size = UDim2.fromOffset(flame.w * (2 - flicker) ^ 0.5, flame.h * flicker)
	end
	ui.rays.Rotation = (ui.rays.Rotation + dt * 8) % 360
end

--- Droplets flying out of the flask in the fluid's colour (and a few in the tier's).
local function burst(fluidColour: Color3, tierColour: Color3, count: number, spread: number)
	local palette = { fluidColour, fluidColour, tierColour, Color3.new(1, 1, 1) }
	for index = 1, count do
		local size = math.random(6, 18)
		local drop = Instance.new("Frame")
		drop.Name = "Drop"
		drop.BorderSizePixel = 0
		drop.BackgroundColor3 = palette[(index % #palette) + 1]
		drop.Size = UDim2.fromOffset(size, size)
		drop.AnchorPoint = Vector2.new(0.5, 0.5)
		drop.Position = UDim2.fromOffset(FLASK_X, BULB_Y)
		drop.ZIndex = 6
		drop.Parent = ui.root
		round(drop, UDim.new(1, 0))
		local angle = math.random() * math.pi * 2
		local reach = spread * (0.35 + 0.65 * math.random())
		local seconds = 0.8 + math.random() * 0.6
		tween(drop, seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
			Position = UDim2.fromOffset(FLASK_X + math.cos(angle) * reach, BULB_Y + math.sin(angle) * reach + 50),
			Size = UDim2.fromOffset(size * 0.3, size * 0.3),
			BackgroundTransparency = 1,
		})
		task.delay(seconds, drop.Destroy, drop)
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
		end
	end)
end

--- What the brew did to the hose: loaded straight in, or stored behind something better.
local function describe(payload: any): string
	local loaded = Liquids.get(payload.loaded)
	local washes = if payload.held == 1 then "1 wash" else `{payload.held} washes`
	-- A liquid crate (Config/Crates) plays this same brew; say where it came from.
	local source = if Crates.has(payload.crate) then `from a {Crates.get(payload.crate).name} \u{2014} ` else ""
	if payload.loaded == payload.result then
		return `{source}loaded in the hose \u{2014} {washes} in the bottle`
	end
	return `{source}{washes} stored \u{2014} kept {loaded.name} loaded`
end

--- The landing: pop, flash, burst, rays, and the result slamming in.
local function reveal(payload: any, token: number)
	local def = Liquids.get(payload.result)
	local colour = Color3.fromHex(def.color)
	local tierName, tierColour, tierRank = tierOf(def)

	paintLiquid(payload.result)
	ui.flask.Rotation = 0
	ui.flask.Position = ui.flaskHome
	ui.surface.Rotation = 0
	ui.cycle.Visible = false
	ui.cycleTier.Visible = false

	ui.flaskScale.Scale = 1.1
	tween(ui.flaskScale, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	ui.flash.BackgroundTransparency = 0.45
	tween(ui.flash, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 1 })
	for _, bar in ui.rayBars do
		bar.BackgroundColor3 = tierColour
		tween(bar, 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 0.35 })
	end
	burst(colour, tierColour, 22 + tierRank * 6, 220 + tierRank * 30)
	-- Rarer lands ring higher.
	ui.land.PlaybackSpeed = 0.85 + 0.07 * tierRank
	ui.land:Play()

	ui.tierPill.BackgroundColor3 = tierColour
	ui.tierText.Text = tierName
	ui.name.Text = def.name
	ui.name.TextColor3 = colour
	ui.flavour.Text = def.flavor
	ui.detail.Text = describe(payload)
	local chips = fillChips(ui.chips, def, UIKit.TextSize.body, 30)
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
	if type(payload) ~= "table" or type(payload.reel) ~= "table" or #payload.reel == 0 then
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

	local reel = payload.reel
	local land = math.clamp(tonumber(payload.land) or #reel, 1, #reel)
	local seconds = math.max(tonumber(payload.seconds) or 4, 0.5)
	local from = math.min(REEL_FROM, land)
	local function reelAt(position: number): string
		return reel[math.clamp(math.floor(position + 0.5), 1, #reel)]
	end

	ui.result.Visible = false
	ui.cycle.Visible = true
	ui.cycle.Text = ""
	ui.cycleTier.Visible = false
	ui.flask.Rotation = 0
	ui.flask.Position = ui.flaskHome
	ui.surface.Rotation = 0
	ui.flaskScale.Scale = 1
	for _, bar in ui.rayBars do
		bar.BackgroundTransparency = 1
	end
	paintLiquid(reelAt(from))
	ui.scale.Scale = 0.92
	ui.dim.BackgroundTransparency = 1
	ui.gui.Enabled = true
	tween(ui.scale, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	tween(ui.dim, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 0.45 })

	-- Driven per frame rather than tweened so each fluid crossing into the flask can
	-- tick. Quartic ease-out to just past (or short of) the result, then a smoothstep
	-- back onto it: fast through the common end, crawling, then a last-moment settle.
	local overshoot = (math.random() * 2 - 1) * OVERSHOOT
	local mainSeconds = seconds * 0.88
	local started = os.clock()
	local lastTile = from
	local lastPosition = from
	local landed = false
	ui.connection = RunService.RenderStepped:Connect(function(dt)
		if token ~= spinToken then
			return
		end
		local elapsed = os.clock() - started
		local speed = 0
		if not landed then
			local position
			if elapsed < mainSeconds then
				position = from + (land + overshoot - from) * (1 - (1 - elapsed / mainSeconds) ^ 4)
			else
				local t = math.clamp((elapsed - mainSeconds) / (seconds - mainSeconds), 0, 1)
				position = land + overshoot * (1 - t * t * (3 - 2 * t))
			end
			speed = math.abs(position - lastPosition) / math.max(dt, 1 / 240)
			lastPosition = position

			local centred = math.clamp(math.floor(position + 0.5), 1, #reel)
			if centred ~= lastTile then
				lastTile = centred
				local def = Liquids.get(reel[centred])
				paintLiquid(reel[centred])
				ui.cycle.Text = def.name
				ui.cycle.TextColor3 = Color3.fromHex(def.color)
				local tierName, tierColour = tierOf(def)
				ui.cycleTierText.Text = tierName
				ui.cycleTierPill.BackgroundColor3 = tierColour
				ui.cycleTier.Visible = true
				ui.tick:Play()
			end

			-- Shakes harder the closer it gets to stopping, and the liquid sloshes the
			-- other way so its surface lags the glass.
			local progress = elapsed / seconds
			local amp = if progress > 0.55 then (progress - 0.55) * 14 else 0
			ui.flask.Rotation = math.sin(elapsed * 36) * amp
			ui.flask.Position = ui.flaskHome + UDim2.fromOffset(math.sin(elapsed * 52) * amp * 0.6, 0)
			ui.surface.Rotation = -ui.flask.Rotation * 1.6

			if elapsed >= seconds then
				landed = true
				reveal(payload, token)
			end
		end
		animateAmbient(dt, speed)
	end)
end

-- ── The fluid panel ──────────────────────────────────────────────────────

--- How close to your own bottle the panel opens, in studs from the bottle's body. Short
--- enough that the wash spot on the far side of the tub (~8 studs away) never opens it.
local PANEL_REACH = 6.5
local PANEL_W, PANEL_H = 330, 362
--- The panel's bottle icon: its scale and the fluid's height at empty and full.
local ICON_SCALE = 1.4
local FILL_EMPTY, FILL_FULL = 0.12, 0.78
--- build/Kit.FLUID_TAG — the client cannot require build/, so the string is repeated.
local FLUID_TAG = "FluidSpin"
local BREW_READY = UIKit.C.green
local BREW_LIP = Color3.fromHex("13733A")
local IDLE_LIP = Color3.fromHex("0A0C08")

local panel: any = {}
--- The last FluidState, and when it arrived, so the BREW countdown runs locally.
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

--- Top of the card: header and tier chip, the bottle, name, washes, bar and stats.
local function buildPanelFluid(card: Frame)
	UIKit.label(card, {
		name = "Header",
		size = UDim2.fromOffset(160, 22),
		position = UDim2.fromOffset(16, 14),
		text = "YOUR FLUID",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
	})
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.BorderSizePixel = 0
	glow.BackgroundTransparency = 0.8
	glow.Size = UDim2.fromOffset(78, 78)
	glow.Position = UDim2.fromOffset(52, 100)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Parent = card
	round(glow, UDim.new(1, 0))
	panel.glow = glow
	panel.fluid = bottleIcon(card, UDim2.fromOffset(52, 56), ICON_SCALE, UIKit.C.text)

	local name = UIKit.label(card, {
		name = "FluidName",
		size = UDim2.fromOffset(214, 32),
		position = UDim2.fromOffset(100, 42),
		text = "Plain Water",
		font = UIKit.Font.hero,
		textSize = 25,
		shadow = false,
	})
	-- "Stardust Rinse" is right at the edge of 214px in GothamBlack; shrink rather
	-- than clip.
	name.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 25
	fit.Parent = name
	panel.name = name
	-- The rarity sits right under the name, on request.
	panel.tierPill, panel.tierText = pill(card, "Tier", "BASIC", UIKit.TextSize.caption - 1, 20, UIKit.C.dim, INK)
	panel.tierPill.Position = UDim2.fromOffset(100, 77)
	panel.left = UIKit.label(card, {
		name = "Washes",
		size = UDim2.fromOffset(214, 20),
		position = UDim2.fromOffset(100, 100),
		text = "never runs out",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body - 1,
		color = UIKit.C.dim,
	})
	local track = UIKit.panel(card, {
		name = "WashBar",
		size = UDim2.fromOffset(214, 10),
		position = UDim2.fromOffset(100, 124),
		color = UIKit.C.empty,
		transparency = 0,
		cornerRadius = UDim.new(1, 0),
		strokeThickness = 0,
	})
	panel.washFill = UIKit.panel(track, {
		name = "Fill",
		size = UDim2.fromScale(1, 1),
		color = UIKit.C.text,
		transparency = 0,
		cornerRadius = UDim.new(1, 0),
		strokeThickness = 0,
	})

	panel.chips = chipRow(card, "Stats", UDim2.new(1, -32, 0, 26), UDim2.fromOffset(16, 150), Vector2.zero, false)
end

--- The BREW button: a chunky green key on a darker lip, a flame beside the word, a
--- sheen that sweeps across it while it is ready, and a bar that fills as the
--- cooldown runs down.
local function buildPanelBrew(card: Frame)
	local lip = UIKit.panel(card, {
		name = "BrewLip",
		size = UDim2.new(1, -32, 0, 60),
		position = UDim2.fromOffset(16, 192),
		color = BREW_LIP,
		transparency = 0,
		cornerRadius = UDim.new(0, 16),
		strokeColor = UIKit.C.outline,
		strokeThickness = UIKit.Stroke.normal,
	})
	panel.lip = lip

	local brew = UIKit.button(card, {
		name = "Brew",
		size = UDim2.new(1, -32, 0, 60),
		position = UDim2.fromOffset(16, 186),
		text = "BREW",
		font = UIKit.Font.hero,
		textSize = 28,
		fillColor = BREW_READY,
		fillTransparency = 0,
		cornerRadius = UDim.new(0, 16),
		zIndex = 3,
	})
	panel.brew = brew
	brew.Activated:Connect(function()
		if state and (state.cooldown or 0) - (os.clock() - stateAt) <= 0 then
			send("roll")
		end
	end)

	-- Children with a lower ZIndex than the button draw over its fill but behind its
	-- own text (UIKit.button's shadow relies on the same rule).
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.BorderSizePixel = 0
	sheen.BackgroundColor3 = Color3.new(1, 1, 1)
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.ZIndex = 1
	sheen.Parent = brew
	round(sheen, UDim.new(0, 16))
	local band = Instance.new("UIGradient")
	band.Rotation = 20
	band.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.4, 1),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	band.Offset = Vector2.new(-1, 0)
	band.Parent = sheen
	TweenService:Create(
		band,
		TweenInfo.new(1.3, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false, 1.4),
		{ Offset = Vector2.new(1, 0) }
	):Play()
	panel.sheen = sheen

	local flame = plainFrame(brew, "Flame", UDim2.fromOffset(20, 28), UDim2.new(0.5, -64, 0.5, 0), Vector2.new(0.5, 0.5))
	flame.ZIndex = 4
	for index, spec in { { 18, 26, "FF7A1A" }, { 9, 13, "FFE08A" } } do
		local blob = Instance.new("Frame")
		blob.Name = `Blob{index}`
		blob.BorderSizePixel = 0
		blob.BackgroundColor3 = Color3.fromHex(spec[3])
		blob.Size = UDim2.fromOffset(spec[1], spec[2])
		blob.Position = UDim2.fromScale(0.5, 1)
		blob.AnchorPoint = Vector2.new(0.5, 1)
		blob.ZIndex = index
		blob.Parent = flame
		round(blob, UDim.new(0.5, 0))
		outline(blob, UIKit.C.outline, if index == 1 then 2 else 0)
	end
	panel.flame = flame

	local fill = Instance.new("Frame")
	fill.Name = "Cooldown"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = UIKit.C.green
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.new(0, 6, 1, -5)
	fill.Size = UDim2.fromOffset(0, 6)
	fill.ZIndex = 1
	fill.Visible = false
	fill.Parent = brew
	round(fill, UDim.new(1, 0))
	panel.cooldown = fill
end

--- Bottom of the card: Luck, the jackpot's odds now and after the next purchase, the
--- upgrade key, and a line for the server's notices.
local function buildPanelLuck(card: Frame)
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = UIKit.C.stroke
	rule.BorderSizePixel = 0
	rule.Size = UDim2.new(1, -32, 0, 2)
	rule.Position = UDim2.fromOffset(16, 264)
	rule.Parent = card

	panel.luck = UIKit.label(card, {
		name = "Luck",
		size = UDim2.fromOffset(110, 24),
		position = UDim2.fromOffset(16, 274),
		text = "LUCK 1.0x",
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.header + 1,
	})
	panel.boost = UIKit.label(card, {
		name = "Boost",
		size = UDim2.fromOffset(70, 24),
		position = UDim2.fromOffset(126, 274),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.amber,
	})
	panel.jackpot = UIKit.label(card, {
		name = "Jackpot",
		size = UDim2.fromOffset(180, 16),
		position = UDim2.fromOffset(16, 300),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption - 1,
		color = Color3.fromHex("FFF3B0"),
	})
	-- "Antimatter Tonic 1 in 2308" is right at the edge of 180px; shrink rather
	-- than clip.
	panel.jackpot.TextScaled = true
	local jackpotFit = Instance.new("UITextSizeConstraint")
	jackpotFit.MaxTextSize = UIKit.TextSize.caption - 1
	jackpotFit.Parent = panel.jackpot
	panel.jackpotNext = UIKit.label(card, {
		name = "JackpotNext",
		size = UDim2.fromOffset(180, 16),
		position = UDim2.fromOffset(16, 316),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption - 1,
		color = UIKit.C.dim,
	})

	local upgrade = UIKit.button(card, {
		name = "Upgrade",
		size = UDim2.fromOffset(116, 52),
		position = UDim2.new(1, -16, 0, 274),
		anchorPoint = Vector2.new(1, 0),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		fillColor = Color3.fromHex("2F6FB0"),
		fillTransparency = 0,
	})
	upgrade.Activated:Connect(function()
		send("luck")
	end)
	panel.upStep = UIKit.label(upgrade, {
		name = "Step",
		size = UDim2.new(1, 0, 0, 24),
		position = UDim2.fromOffset(0, 5),
		text = "+0.1x",
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.header,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
	panel.upPrice = UIKit.label(upgrade, {
		name = "Price",
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 28),
		text = "$0",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = Color3.fromHex("CFE3FF"),
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})

	panel.notice = UIKit.label(card, {
		name = "Notice",
		size = UDim2.new(1, -32, 0, 18),
		position = UDim2.fromOffset(16, 336),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.amber,
		xAlign = Enum.TextXAlignment.Center,
	})
end

local function buildPanel()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "FluidPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Over the HUD, under the brew (105) and the Index/Shop panels (110).
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
		transparency = 0.05,
		cornerRadius = UDim.new(0, 22),
		strokeThickness = UIKit.Stroke.thick,
		visible = false,
	})
	panel.card = card
	panel.cardStroke = cardStroke
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.fromHex("FFFFFF"), Color3.fromHex("B8BDB4"))
	shade.Parent = card
	local scale = Instance.new("UIScale")
	scale.Parent = card
	panel.scale = scale

	buildPanelFluid(card)
	buildPanelBrew(card)
	buildPanelLuck(card)
end

--- Paint everything except the countdown from the last FluidState.
local function paintState()
	if panel.card == nil or state == nil then
		return
	end
	local def = Liquids.get(state.liquid)
	local colour = Color3.fromHex(def.color)
	local water = state.liquid == Liquids.WATER
	local held = tonumber(state.held) or 0
	local tierName, tierColour = tierOf(def)

	panel.tierPill.BackgroundColor3 = tierColour
	panel.tierText.Text = tierName
	panel.name.Text = def.name
	panel.name.TextColor3 = colour
	panel.cardStroke.Color = colour:Lerp(UIKit.C.stroke, 0.35)
	panel.glow.BackgroundColor3 = colour

	-- A roll can stack past one canister (Tuning.LIQUID_MAX_STACK); the bottle and bar
	-- read full from one canister up rather than showing a stack as a sliver.
	local full = if water then 1 else math.clamp(held / math.max(def.charges, 1), 0, 1)
	panel.fluid.BackgroundColor3 = colour
	panel.fluid.Size = UDim2.new(1, -8 * ICON_SCALE, FILL_EMPTY + (FILL_FULL - FILL_EMPTY) * full, 0)
	panel.washFill.BackgroundColor3 = colour
	panel.washFill.Size = UDim2.fromScale(math.max(full, 0.04), 1)
	panel.left.Text = if water
		then "never runs out \u{2014} brew for better"
		elseif held == 1 then "1 wash left"
		else `{held} washes left`
	fillChips(panel.chips, def, UIKit.TextSize.caption - 1, 24)

	local luck = tonumber(state.luck) or 1
	local level = tonumber(state.luckLevel) or 1
	local nextLuck = Gear.luckMultiplier(level + 1)
	panel.luck.Text = string.format("LUCK %.1fx", luck)
	local boost = tonumber(state.boost) or 1
	panel.boost.Text = if boost > 1 then string.format("x%g BOOST", boost) else ""

	-- The jackpot's odds at the luck the server actually rolls with, and after one
	-- more purchase (bought luck scales, any boost rides along unchanged).
	local rollLuck = tonumber(state.rollLuck) or luck
	local jackpot = Liquids.ORDER[#Liquids.ORDER]
	local now = Liquids.oddsAt(rollLuck)[jackpot] or 0
	local after = Liquids.oddsAt(rollLuck * nextLuck / luck)[jackpot] or 0
	panel.jackpot.Text = `{Liquids.get(jackpot).name} {oneIn(now)}`
	panel.jackpotNext.Text = `next +{string.format("%.1f", nextLuck - luck)}x: {oneIn(after)}`
	panel.upStep.Text = string.format("+%.1fx", nextLuck - luck)
	panel.upPrice.Text = formatCash(tonumber(state.luckPrice) or 0)
end

--- The BREW key's face: green with the flame and sheen when ready; grey, counting
--- down, with the bar filling, while the cooldown runs.
local function paintBrew()
	if panel.brew == nil or state == nil then
		return
	end
	local left = (tonumber(state.cooldown) or 0) - (os.clock() - stateAt)
	local waiting = left > 0
	if waiting then
		panel.brew.Text = `BREW IN {math.ceil(left)}s`
		panel.brew.TextSize = UIKit.TextSize.title - 4
		panel.brew.BackgroundColor3 = UIKit.C.empty
		panel.brew.TextColor3 = UIKit.C.dim
		panel.lip.BackgroundColor3 = IDLE_LIP
		local done = 1 - math.clamp(left / Tuning.LIQUID_SPIN_COOLDOWN, 0, 1)
		panel.cooldown.Size = UDim2.new(done, -12 * done, 0, 6)
	else
		panel.brew.Text = "BREW"
		panel.brew.TextSize = 28
		panel.brew.BackgroundColor3 = BREW_READY
		panel.brew.TextColor3 = UIKit.C.text
		panel.lip.BackgroundColor3 = BREW_LIP
	end
	panel.cooldown.Visible = waiting
	panel.sheen.Visible = not waiting
	panel.flame.Visible = not waiting
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
		tween(panel.scale, 0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	end
end

--- Open the panel while the local player stands at their own bottle, and not while a
--- brew is on screen. Polled at 10 Hz rather than per frame: it is a distance check,
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
		local brewing = ui.gui ~= nil and ui.gui.Enabled
		setOpen(near and state ~= nil and not brewing)
		paintBrew()
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
		paintBrew()
	end)
	Net.get("PlotState").OnClientEvent:Connect(function(index)
		plotIndex = tonumber(index)
	end)
	watch()
end

return Liquid
