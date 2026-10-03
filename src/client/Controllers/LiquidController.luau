--[[
	LiquidController.lua — the fluid panel at your bottle, and the brew it plays.

	Press BREW on the fluid panel beside your tub (build/Plots.buildFluidBottle) and the
	server rolls a fluid, then fires FluidSpin with the answer already decided. This
	file only ANIMATES that answer. It never asks the server for anything and has
	nothing it could send back to steer a result -- the request is a bare "roll".

	THE FLASK BREW, picked from six mockups (option 5). There is no card: a big
	round-bottomed flask sits on a burner in the middle of the screen. Its liquid blends
	through the fluids of the reel, fast at first, then slower, the flask swaying gently
	and settling just before it stops (the "Smooth Flask" pass, mockup option 1). When it
	stops, the flask pulses, a soft glow blooms and light rays fade in behind it in the
	TIER colour (Config/Liquids `tier`, painted from Config/Rarity), a shockwave ring
	goes out, droplets arc out under gravity, and the name eases up over its stats. It closes itself a moment later and never takes input, so you can walk away
	while it plays. The bottle in the world recolours when it lands (LiquidService holds
	the repaint until then), so the world does not give the result away first.

	THE REEL IS MADE OF REAL ROLLS at your luck (LiquidService.reelFor), so the colours
	that flash through the flask most are the fluids that come up most.

	THE FLASK IS FRAMES. The bulb is a round CanvasGroup, because a CanvasGroup clips its
	children to its UICorner and a plain Frame's ClipsDescendants only clips to the
	rectangle; the liquid inside is a frame hung from a pivot at its surface, so tilting
	the pivot sloshes the surface while the glass shakes. A metal collar sits over the
	place the neck meets the bulb, which hides where the two outlines cross.

	THE FLUID PANEL. Walk up to your own bottle and press E ("View") and it slides in to
	the right of centre:
	a tabbed terminal (mockup option 5). BREW: the loaded fluid (bottle, tier, name,
	stats, each with a hover explanation) and a BREW button that counts down the
	cooldown. FLUIDS: every rollable fluid as a collection grid, unrolled ones dark
	(FluidState `seen`). LUCK: the UPGRADE with its price and the rarest fluids' odds
	now and after the purchase (worked out from FluidState's `rollLuck` and
	`nextRollLuck`, the numbers the server rolls with). Both buttons send FluidAction;
	the server checks you are at your bottle. The panel steps aside while a brew is
	playing.

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
local Tuning = require(Shared.Config.Tuning)
local Crates = require(Shared.Config.Crates)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)
local Prefs = require(script.Parent.Parent.Prefs)
local RadFxArt = require(script.Parent.Parent.RadFxArt)
local RobuxButton = require(script.Parent.Parent.RobuxButton)

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

--- Refill a chip row with a fluid's stats: how fast it scrubs, and the potency bonus
--- when it has one. Returns the chips in order, for the reveal's pop-in. `hover`, when
--- given, is called with a chip and its one-line explanation as the mouse enters it,
--- and with nil as it leaves -- the panel's tooltip.
---
--- NO PAY CHIP. `xpMult` only ever fed data.xp, which nothing spends; a chip selling
--- a bonus that does nothing was removed on request.
local function fillChips(row: Frame, def: any, textSize: number, height: number, hover: ((Frame, string?) -> ())?): { Frame }
	for _, child in row:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local specs = {
		{
			text = string.format("SCRUB x%.2f", def.rateMult),
			tip = string.format("Scrub: crust soaks off x%.2f as fast in your tub.", def.rateMult),
			hot = false,
		},
	}
	if def.potency > 0 then
		table.insert(specs, {
			text = `+{def.potency} CRACK`,
			tip = `Crack: +{def.potency} hose power. Crust tougher than your hose comes off far faster.`,
			hot = true,
		})
	end
	local made = {}
	for index, spec in specs do
		local chip = pill(row, `Chip{index}`, spec.text, textSize, height, CHIP_FILL, if spec.hot then HOT_TEXT else UIKit.C.text)
		chip.LayoutOrder = index
		outline(chip, if spec.hot then HOT_STROKE else CHIP_STROKE, 2)
		if hover then
			chip.Active = true
			chip.MouseEnter:Connect(function()
				hover(chip, spec.tip)
			end)
			chip.MouseLeave:Connect(function()
				hover(chip, nil)
			end)
			-- Touch has no hover: a tap (or click) shows the same line.
			chip.InputBegan:Connect(function(input)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
					hover(chip, spec.tip)
				end
				if kind == Enum.UserInputType.Touch then
					-- No MouseLeave on a finger, so a tapped line goes away by itself.
					task.delay(3, hover, chip, nil)
				end
			end)
		end
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
--- The landing's soft glow: RadFx's white "soft dot with a bright core", tinted.
local GLOW_IMAGE = RadFxArt.mote
--- Droplets fall under this (design px/s^2) and lose speed to this drag per second.
local DROP_GRAVITY = 520
local DROP_DRAG = 0.35

local ui: any = {}
--- Bumped on every brew, so a brew that starts while the last one is still closing
--- owns the popup and the older one's close timer does nothing.
local spinToken = 0

local function sound(id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	Sfx.adopt(s, "ui") -- under Settings' SOUND EFFECTS switch
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
		NumberSequenceKeypoint.new(0.25, 0.92),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(0.75, 0.92),
		NumberSequenceKeypoint.new(1, 1),
	})
	for index = 1, RAY_COUNT do
		local bar = Instance.new("Frame")
		bar.Name = `Ray{index}`
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BackgroundTransparency = 1
		bar.Size = UDim2.new(0, 26, 1, 0)
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

	-- A soft glow behind the flask: the current fluid's colour, faint, while it brews;
	-- it blooms out in the tier colour on landing.
	local bloom = Instance.new("ImageLabel")
	bloom.Name = "Bloom"
	bloom.BackgroundTransparency = 1
	bloom.Image = GLOW_IMAGE
	bloom.ImageTransparency = 1
	bloom.Size = UDim2.fromOffset(420, 420)
	bloom.Position = UDim2.fromOffset(FLASK_X, BULB_Y)
	bloom.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Under the rays: there is no additive blending, so a glow drawn over them would
	-- just wash them out.
	bloom.ZIndex = 0
	bloom.Parent = root
	ui.bloom = bloom

	-- The landing's shockwave: an empty circle that grows and thins out.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromOffset(80, 80)
	ring.Position = UDim2.fromOffset(FLASK_X, BULB_Y)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.ZIndex = 2
	ring.Visible = false
	ring.Parent = root
	round(ring, UDim.new(1, 0))
	ui.ring = outline(ring, Color3.new(1, 1, 1), 10)
	ui.ringFrame = ring
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
--- replaces it: tier chip, name, stat chips, and what it did to the hose.
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
	ui.cycleHome = ui.cycle.Position

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
	ui.drops = {}

	local nameBox = plainFrame(result, "NameBox", UDim2.fromOffset(760, 56), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0))
	ui.nameBox = nameBox
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

	ui.chips = chipRow(result, "Chips", UDim2.fromOffset(760, 42), UDim2.new(0.5, 0, 0, 100), Vector2.new(0.5, 0), true)
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

	-- REPLACE / KEEP, on request: a roll never auto-loads, the player picks. Shown
	-- only when the server asks (payload.choose); the answer goes back as FluidAction.
	local choice = plainFrame(result, "Choice", UDim2.fromOffset(420, 56), UDim2.new(0.5, 0, 0, 196), Vector2.new(0.5, 0))
	choice.Visible = false
	ui.choice = choice
	local function choiceButton(name: string, x: number, fill: Color3): TextButton
		local button = UIKit.button(choice, {
			name = name,
			size = UDim2.fromOffset(200, 56),
			position = UDim2.fromOffset(x, 0),
			text = "",
			font = UIKit.Font.hero,
			textSize = 26,
			fillColor = fill,
			fillTransparency = 0,
			cornerRadius = UDim.new(0, 14),
			zIndex = 6,
			shadow = false,
		})
		-- Frees the mouse from shift-lock / first person while the question is up.
		button.Modal = true
		return button
	end
	ui.replace = choiceButton("Take", 0, UIKit.C.green)
	ui.keep = choiceButton("Leave", 220, Color3.fromHex("D13B3B"))

	-- The fluid in the hose right now, on request: a side card beside the roll while
	-- TAKE / LEAVE is up, so the player can weigh the two before swapping.
	local current = UIKit.panel(root, {
		name = "Current",
		size = UDim2.fromOffset(210, 230),
		position = UDim2.fromOffset(FLASK_X + 410, BULB_Y),
		anchorPoint = Vector2.new(0, 0.5),
		color = Color3.fromHex("1B1F24"),
		transparency = 0.1,
		cornerRadius = UDim.new(0, 0),
		strokeColor = UIKit.C.outline,
		strokeThickness = 2,
		zIndex = 5,
	})
	current.Visible = false
	ui.current = current
	UIKit.label(current, {
		name = "Header",
		size = UDim2.new(1, 0, 0, 22),
		position = UDim2.fromOffset(0, 10),
		text = "YOUR FLUID",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 6,
	})
	ui.currentName = UIKit.label(current, {
		name = "FluidName",
		size = UDim2.new(1, -16, 0, 30),
		position = UDim2.fromOffset(8, 34),
		text = "",
		font = UIKit.Font.hero,
		textSize = 24,
		xAlign = Enum.TextXAlignment.Center,
		zIndex = 6,
	})
	local currentTier = plainFrame(current, "TierBox", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 70), Vector2.zero)
	currentTier.ZIndex = 6
	ui.currentTierPill, ui.currentTierText = pill(currentTier, "Tier", "", UIKit.TextSize.caption, 22, UIKit.C.dim, INK)
	ui.currentTierPill.AnchorPoint = Vector2.new(0.5, 0)
	ui.currentTierPill.Position = UDim2.fromScale(0.5, 0)
	local currentChips = plainFrame(current, "Chips", UDim2.new(1, 0, 0, 120), UDim2.fromOffset(0, 104), Vector2.zero)
	currentChips.ZIndex = 6
	local stack = Instance.new("UIListLayout")
	stack.FillDirection = Enum.FillDirection.Vertical
	stack.HorizontalAlignment = Enum.HorizontalAlignment.Center
	stack.SortOrder = Enum.SortOrder.LayoutOrder
	stack.Padding = UDim.new(0, 6)
	stack.Parent = currentChips
	ui.currentChips = currentChips
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
	-- Two slow sines per blob instead of a fresh random size every frame: the flame
	-- breathes rather than strobes.
	local now = os.clock()
	for index, flame in ui.flames do
		local flicker = 1 + 0.12 * (math.sin(now * 9 + index * 1.7) * 0.5 + math.sin(now * 13.3 + index) * 0.5)
		flame.frame.Size = UDim2.fromOffset(flame.w * (2 - flicker) ^ 0.5, flame.h * flicker)
	end
	ui.rays.Rotation = (ui.rays.Rotation + dt * 8) % 360

	-- Droplets from the landing: arcs under gravity, shrinking and fading out.
	local drops = ui.drops
	for index = #drops, 1, -1 do
		local drop = drops[index]
		drop.life -= drop.decay * dt
		if drop.life <= 0 then
			drop.frame:Destroy()
			table.remove(drops, index)
			continue
		end
		drop.vy += DROP_GRAVITY * dt
		drop.vx *= DROP_DRAG ^ dt
		drop.x += drop.vx * dt
		drop.y += drop.vy * dt
		local size = drop.size * drop.life + 1
		drop.frame.Position = UDim2.fromOffset(drop.x, drop.y)
		drop.frame.Size = UDim2.fromOffset(size, size)
		drop.frame.BackgroundTransparency = 1 - math.clamp(drop.life, 0, 1)
	end
end

--- Droplets flying out of the flask in the fluid's colour (and a few in the tier's).
local function burst(fluidColour: Color3, tierColour: Color3, count: number, spread: number)
	-- Stepped in animateAmbient (gravity and drag), so they arc and fall instead of
	-- sliding out in straight lines.
	local palette = { fluidColour, fluidColour, tierColour, Color3.new(1, 1, 1) }
	local originY = BULB_Y - BULB * 0.15
	for index = 1, count do
		local size = math.random(6, 16)
		local drop = Instance.new("Frame")
		drop.Name = "Drop"
		drop.BorderSizePixel = 0
		drop.BackgroundColor3 = palette[(index % #palette) + 1]
		drop.Size = UDim2.fromOffset(size, size)
		drop.AnchorPoint = Vector2.new(0.5, 0.5)
		drop.Position = UDim2.fromOffset(FLASK_X, originY)
		drop.ZIndex = 6
		drop.Parent = ui.root
		round(drop, UDim.new(1, 0))
		local angle = math.random() * math.pi * 2
		local speed = spread * (0.4 + 0.6 * math.random())
		table.insert(ui.drops, {
			frame = drop,
			x = FLASK_X,
			y = originY,
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed - spread * 0.35,
			size = size,
			life = 1,
			decay = 0.55 + math.random() * 0.5,
		})
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
	if payload.choose then
		return ""
	end
	if payload.infinite then
		return `{source}already loaded`
	end
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

	-- A soft landing: a gentle pulse of the flask, a faint tint instead of a white
	-- flash, the glow blooming out in the tier colour, the rays fading in, a
	-- shockwave ring, and droplets. Rarer lands glow brighter and throw more.
	ui.flaskScale.Scale = 1.07
	tween(ui.flaskScale, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Scale = 1 })
	ui.flash.BackgroundColor3 = tierColour
	ui.flash.BackgroundTransparency = if Prefs.get("reduceFlashing") then 0.95 else 0.82
	tween(ui.flash, 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 1 })
	ui.bloom.ImageColor3 = tierColour
	tween(ui.bloom, 0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
		ImageTransparency = math.max(0.15, 0.5 - tierRank * 0.05),
		Size = UDim2.fromOffset(560 + tierRank * 40, 560 + tierRank * 40),
	})
	for _, bar in ui.rayBars do
		bar.BackgroundColor3 = tierColour
		tween(bar, 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = math.max(0.2, 0.55 - tierRank * 0.05) })
	end
	ui.ringFrame.Size = UDim2.fromOffset(BULB * 0.6, BULB * 0.6)
	ui.ringFrame.Visible = true
	ui.ring.Color = tierColour
	ui.ring.Thickness = 10
	ui.ring.Transparency = 0.15
	tween(ui.ringFrame, 0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(BULB * 2.6, BULB * 2.6) })
	tween(ui.ring, 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Thickness = 1, Transparency = 1 })
	burst(colour, tierColour, 20 + tierRank * 7, 240 + tierRank * 25)
	-- Rarer lands ring higher.
	ui.land.PlaybackSpeed = 0.85 + 0.07 * tierRank
	ui.land:Play()

	ui.tierPill.BackgroundColor3 = tierColour
	ui.tierText.Text = tierName
	ui.name.Text = def.name
	ui.name.TextColor3 = colour
	ui.detail.Text = describe(payload)
	local chips = fillChips(ui.chips, def, UIKit.TextSize.title, 42)
	ui.result.Visible = true

	-- The name eases up and fades in rather than slamming down from twice its size;
	-- the tier chip pops in just after it.
	ui.nameScale.Scale = 1.15
	tween(ui.nameScale, 0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Scale = 1 })
	ui.nameBox.Position = UDim2.new(0.5, 0, 0, 18)
	tween(ui.nameBox, 0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Position = UDim2.fromScale(0.5, 0) })
	ui.name.TextTransparency = 1
	tween(ui.name, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { TextTransparency = 0 })
	local nameStroke = ui.name:FindFirstChildOfClass("UIStroke")
	if nameStroke then
		nameStroke.Transparency = 1
		tween(nameStroke, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Transparency = 0 })
	end
	ui.tierScale.Scale = 0.01
	task.delay(0.12, function()
		tween(ui.tierScale, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	end)
	for index, chip in chips do
		local grow = Instance.new("UIScale")
		grow.Scale = 0
		grow.Parent = chip
		task.delay(0.15 + index * 0.09, function()
			tween(grow, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
		end)
	end

	if payload.choose then
		-- Held open until the player answers; close() runs off the button press.
		ui.replace.Text = "TAKE"
		ui.keep.Text = "LEAVE"
		ui.choice.Visible = true
		local held = Liquids.get(payload.loaded)
		local heldTier, heldColour = tierOf(held)
		ui.currentName.Text = held.name
		ui.currentName.TextColor3 = Color3.fromHex(held.color)
		ui.currentTierPill.BackgroundColor3 = heldColour
		ui.currentTierText.Text = heldTier
		fillChips(ui.currentChips, held, UIKit.TextSize.caption, 30)
		ui.current.Visible = true
		local answered = false
		local function answer(verb: string)
			if answered or token ~= spinToken then
				return
			end
			answered = true
			ui.choice.Visible = false
			ui.current.Visible = false
			if verb == "replace" then
				Sfx.play("pour") -- the new fluid going into the hose tank
			end
			Net.get("FluidAction"):FireServer(verb)
			close(token)
		end
		ui.choiceConnections = {
			ui.replace.Activated:Connect(function()
				answer("replace")
			end),
			ui.keep.Activated:Connect(function()
				answer("keep")
			end),
		}
		return
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

	-- The flask bubbling on the burner for the spin.
	Sfx.play("brew")

	local reel = payload.reel
	local land = math.clamp(tonumber(payload.land) or #reel, 1, #reel)
	local seconds = math.max(tonumber(payload.seconds) or 4, 0.5)
	local from = math.min(REEL_FROM, land)
	local function reelAt(position: number): string
		return reel[math.clamp(math.floor(position + 0.5), 1, #reel)]
	end

	ui.result.Visible = false
	ui.choice.Visible = false
	ui.current.Visible = false
	for _, connection in ui.choiceConnections or {} do
		connection:Disconnect()
	end
	ui.choiceConnections = nil
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
	ui.ringFrame.Visible = false
	ui.flash.BackgroundTransparency = 1
	ui.bloom.Size = UDim2.fromOffset(420, 420)
	ui.bloom.ImageTransparency = 0.8
	paintLiquid(reelAt(from))
	ui.bloom.ImageColor3 = ui.liquid.BackgroundColor3
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

			-- The liquid BLENDS from one fluid into the next as the reel moves instead of
			-- snapping on every tile.
			local below = math.clamp(math.floor(position), 1, #reel)
			local above = math.clamp(below + 1, 1, #reel)
			local frac = math.clamp(position - math.floor(position), 0, 1)
			local blend = Color3.fromHex(Liquids.get(reel[below]).color)
				:Lerp(Color3.fromHex(Liquids.get(reel[above]).color), frac * frac * (3 - 2 * frac))
			ui.liquid.BackgroundColor3 = blend
			ui.bloom.ImageColor3 = blend

			local centred = math.clamp(math.floor(position + 0.5), 1, #reel)
			if centred ~= lastTile then
				lastTile = centred
				local def = Liquids.get(reel[centred])
				-- The name drops in from just above rather than swapping in place.
				ui.cycle.Position = ui.cycleHome - UDim2.fromOffset(0, 8)
				tween(ui.cycle, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Position = ui.cycleHome })
				ui.cycle.Text = def.name
				ui.cycle.TextColor3 = Color3.fromHex(def.color)
				local tierName, tierColour = tierOf(def)
				ui.cycleTierText.Text = tierName
				ui.cycleTierPill.BackgroundColor3 = tierColour
				ui.cycleTier.Visible = true
				ui.tick:Play()
			end

			-- A slow sway that grows as the reel slows, then eases to rest just before it
			-- lands (no jitter); the liquid tilts the other way so its surface lags the
			-- glass.
			local progress = math.clamp(elapsed / seconds, 0, 1)
			local rest = math.clamp((progress - 0.85) / 0.15, 0, 1)
			local amp = (2.5 + progress * 4) * (1 - rest * rest * (3 - 2 * rest))
			ui.flask.Rotation = math.sin(elapsed * 5.5) * amp
			ui.surface.Rotation = -ui.flask.Rotation * 1.4

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
local PANEL_W, PANEL_H = 340, 350
--- The whole card drawn this much bigger than its design size, on request.
local PANEL_SCALE = 1.15
--- The BREW key's flame: the image id behind Creator Store decal 10656056859.
local FLAME_IMAGE = "rbxassetid://10656056841"
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

--- THE TABBED TERMINAL (mockup option 5). A tab strip across the top of the card and
--- three pages under it:
---   BREW   — the loaded fluid (bottle, name, tier, stat chips) and the BREW key.
---   FLUIDS — all fifteen rollable fluids as a collection grid; ones you have never
---            rolled are dark ??? bottles (FluidState `seen`).
---   LUCK   — the Upgrade key, with the top fluids' odds now and after the purchase
---            (FluidState `rollLuck` and `nextRollLuck`).
--- The card opens on BREW every time.
local TAB_TOP, TAB_H = 14, 34
local PAGE_TOP = TAB_TOP + TAB_H + 12
local TAB_ORDER = { "brew", "fluids", "luck" }
local TAB_IDLE = Color3.fromHex("070906")
--- How many of the rarest fluids the LUCK tab lists, from the top of Liquids.ORDER.
local LUCK_ROWS = 6

local function page(card: Frame, name: string): Frame
	return plainFrame(card, name, UDim2.new(1, 0, 1, -PAGE_TOP), UDim2.fromOffset(0, PAGE_TOP), Vector2.zero)
end

--- BREW page, top: the bottle, name, tier chip and stat chips. No washes line --
--- fluids never run out (Tuning.LIQUID_INFINITE), so it was removed on request.
local function buildPanelFluid(pg: Frame)
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.BorderSizePixel = 0
	glow.BackgroundTransparency = 0.8
	glow.Size = UDim2.fromOffset(78, 78)
	glow.Position = UDim2.fromOffset(52, 58)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Parent = pg
	round(glow, UDim.new(1, 0))
	panel.glow = glow
	panel.fluid = bottleIcon(pg, UDim2.fromOffset(52, 14), ICON_SCALE, UIKit.C.text)

	local name = UIKit.label(pg, {
		name = "FluidName",
		size = UDim2.fromOffset(PANEL_W - 116, 32),
		position = UDim2.fromOffset(100, 22),
		text = "Plain Water",
		font = UIKit.Font.hero,
		textSize = 25,
		shadow = false,
	})
	-- "Antimatter Tonic" is near the edge in GothamBlack; shrink rather than clip.
	name.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 25
	fit.Parent = name
	panel.name = name
	-- The rarity sits right under the name, on request.
	panel.tierPill, panel.tierText = pill(pg, "Tier", "BASIC", UIKit.TextSize.caption - 1, 20, UIKit.C.dim, INK)
	panel.tierPill.Position = UDim2.fromOffset(100, 60)

	panel.chips = chipRow(pg, "Stats", UDim2.new(1, -32, 0, 28), UDim2.fromOffset(16, 112), Vector2.zero, false)
end

--- The BREW button: a chunky green key on a darker lip, a flame beside the word, a
--- sheen that sweeps across it while it is ready, and a bar that fills as the
--- cooldown runs down.
local SKIP_W = 104

--- Brews banked right now (LiquidService.accrue). Counts the next one in as soon as the
--- local countdown runs out, so the key turns green without waiting on the push.
local function brewsReady(): number
	if state == nil then
		return 0
	end
	local stored = tonumber(state.stored) or 0
	local cooldown = tonumber(state.cooldown) or 0
	if cooldown > 0 and cooldown - (os.clock() - stateAt) <= 0 then
		stored += 1
	end
	return stored
end

local function buildPanelBrew(pg: Frame)
	local lip = UIKit.panel(pg, {
		name = "BrewLip",
		size = UDim2.new(1, -32, 0, 60),
		position = UDim2.fromOffset(16, 162),
		color = BREW_LIP,
		transparency = 0,
		cornerRadius = UDim.new(0, 16),
		strokeColor = UIKit.C.outline,
		strokeThickness = UIKit.Stroke.normal,
	})
	panel.lip = lip

	local brew = UIKit.button(pg, {
		name = "Brew",
		size = UDim2.new(1, -32, 0, 60),
		position = UDim2.fromOffset(16, 156),
		text = "BREW",
		font = UIKit.Font.hero,
		textSize = 28,
		fillColor = BREW_READY,
		fillTransparency = 0,
		cornerRadius = UDim.new(0, 16),
		zIndex = 3,
		-- No drop-shadow copy: it keeps its first TextSize, so "BREW IN 29:59" drew twice.
		shadow = false,
	})
	panel.brew = brew
	brew.Activated:Connect(function()
		if brewsReady() > 0 then
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

	-- A real cartoon flame picture (Creator Store "Cartoon fire icon", decal 10656056859)
	-- in place of the two stacked blobs, on request; it flickers while BREW is ready.
	local flame = Instance.new("ImageLabel")
	flame.Name = "Flame"
	flame.BackgroundTransparency = 1
	flame.Image = FLAME_IMAGE
	flame.ScaleType = Enum.ScaleType.Fit
	flame.Size = UDim2.fromOffset(34, 34)
	flame.Position = UDim2.new(0.5, -62, 0.5, -1)
	flame.AnchorPoint = Vector2.new(0.5, 0.5)
	flame.ZIndex = 4
	flame.Parent = brew
	panel.flame = flame
	RunService.RenderStepped:Connect(function()
		if flame.Visible and panel.card and panel.card.Visible then
			local t = os.clock()
			flame.Rotation = math.sin(t * 7) * 6
			local s = 34 + math.sin(t * 11) * 2
			flame.Size = UDim2.fromOffset(s, s)
		end
	end)

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

	-- SKIP: a Robux button beside the key while the cooldown runs (Tuning.
	-- BREW_SKIP_PRODUCT_ID); the key narrows to make room for it.
	local skip = RobuxButton.product(pg, function()
		return Tuning.BREW_SKIP_PRODUCT_ID
	end, "SKIP")
	skip.button.Size = UDim2.fromOffset(SKIP_W, 60)
	skip.button.AnchorPoint = Vector2.new(1, 0)
	skip.button.Position = UDim2.new(1, -16, 0, 156)
	skip.button.ZIndex = 5
	skip.button.Visible = false
	panel.skip = skip.button

	-- One line under the key: your luck and the jackpot's odds at it, so the BREW
	-- page still says what a roll can reach without opening LUCK.
	panel.brewOdds = UIKit.label(pg, {
		name = "Odds",
		size = UDim2.new(1, -32, 0, 18),
		position = UDim2.fromOffset(16, 236),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = Color3.fromHex("FFF3B0"),
		xAlign = Enum.TextXAlignment.Center,
	})
end

--- FLUIDS page: a 5x3 grid of every rollable fluid, and a discovered count under it.
local FLUID_TILE = Vector2.new(56, 66)
local function buildPanelFluids(pg: Frame)
	local grid = plainFrame(pg, "Grid", UDim2.new(1, -32, 0, 214), UDim2.fromOffset(16, 0), Vector2.zero)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(FLUID_TILE.X, FLUID_TILE.Y)
	layout.CellPadding = UDim2.fromOffset(6, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	panel.tiles = {}
	for index, id in Liquids.ORDER do
		if id == Liquids.WATER then
			continue
		end
		local tile, stroke = UIKit.panel(grid, {
			name = id,
			size = UDim2.fromOffset(FLUID_TILE.X, FLUID_TILE.Y),
			color = Color3.fromHex("151A12"),
			transparency = 0,
			cornerRadius = UDim.new(0, 10),
			strokeColor = CHIP_STROKE,
			strokeThickness = 2,
		})
		tile.LayoutOrder = index
		local fluid = bottleIcon(tile, UDim2.new(0.5, 0, 0, 5), 0.62, UIKit.C.text)
		local label = UIKit.label(tile, {
			name = "FluidName",
			size = UDim2.new(1, -6, 0, 20),
			position = UDim2.new(0.5, 0, 0, 43),
			anchorPoint = Vector2.new(0.5, 0),
			text = "???",
			font = UIKit.Font.title,
			textSize = 11,
			xAlign = Enum.TextXAlignment.Center,
			shadow = false,
		})
		label.TextWrapped = true
		label.TextScaled = true
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = 11
		fit.Parent = label
		panel.tiles[id] = { stroke = stroke, fluid = fluid, label = label }
	end

	panel.seenCount = UIKit.label(pg, {
		name = "Count",
		size = UDim2.new(1, -32, 0, 20),
		position = UDim2.fromOffset(16, 224),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		color = UIKit.C.dim,
		xAlign = Enum.TextXAlignment.Center,
	})
end

--- LUCK page: luck now -> after the upgrade, the rarest fluids' odds in two columns,
--- and the Upgrade key with its price.
local function buildPanelLuck(pg: Frame)
	panel.luck = UIKit.label(pg, {
		name = "Luck",
		size = UDim2.fromOffset(150, 30),
		position = UDim2.fromOffset(16, 0),
		text = "LUCK 1x",
		font = UIKit.Font.hero,
		textSize = 26,
	})
	panel.nextLuck = UIKit.label(pg, {
		name = "NextLuck",
		size = UDim2.fromOffset(150, 30),
		position = UDim2.new(1, -16, 0, 0),
		anchorPoint = Vector2.new(1, 0),
		text = "",
		font = UIKit.Font.hero,
		textSize = 26,
		color = UIKit.C.green,
		xAlign = Enum.TextXAlignment.Right,
	})
	panel.boost = UIKit.label(pg, {
		name = "Boost",
		size = UDim2.fromOffset(150, 16),
		position = UDim2.fromOffset(16, 32),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.amber,
	})
	for _, spec in { { "NOW", 196, UIKit.C.dim }, { "NEXT", 264, UIKit.C.green } } do
		UIKit.label(pg, {
			name = `{spec[1]}Head`,
			size = UDim2.fromOffset(64, 16),
			position = UDim2.fromOffset(spec[2], 34),
			text = spec[1],
			font = UIKit.Font.title,
			textSize = UIKit.TextSize.caption - 2,
			color = spec[3],
			xAlign = Enum.TextXAlignment.Right,
		})
	end

	panel.luckRows = {}
	local first = #Liquids.ORDER - LUCK_ROWS + 1
	for row = 1, LUCK_ROWS do
		local id = Liquids.ORDER[first + row - 1]
		local def = Liquids.get(id)
		local _, tierColour = tierOf(def)
		local y = 54 + (row - 1) * 24
		local dot = UIKit.panel(pg, {
			name = `Dot{row}`,
			size = UDim2.fromOffset(12, 12),
			position = UDim2.fromOffset(16, y + 4),
			color = Color3.fromHex(def.color),
			transparency = 0,
			cornerRadius = UDim.new(1, 0),
			strokeColor = UIKit.C.outline,
			strokeThickness = 2,
		})
		dot.ZIndex = 2
		UIKit.label(pg, {
			name = `Name{row}`,
			size = UDim2.fromOffset(160, 20),
			position = UDim2.fromOffset(34, y),
			text = def.name,
			font = UIKit.Font.title,
			textSize = UIKit.TextSize.caption,
			color = tierColour,
		})
		local now = UIKit.label(pg, {
			name = `Now{row}`,
			size = UDim2.fromOffset(76, 20),
			position = UDim2.fromOffset(184, y),
			text = "",
			font = UIKit.Font.title,
			textSize = UIKit.TextSize.caption,
			color = UIKit.C.dim,
			xAlign = Enum.TextXAlignment.Right,
		})
		local after = UIKit.label(pg, {
			name = `Next{row}`,
			size = UDim2.fromOffset(76, 20),
			position = UDim2.fromOffset(252, y),
			text = "",
			font = UIKit.Font.title,
			textSize = UIKit.TextSize.caption,
			color = Color3.fromHex("8BE59F"),
			xAlign = Enum.TextXAlignment.Right,
		})
		panel.luckRows[row] = { id = id, now = now, after = after }
	end

	local upgrade = UIKit.button(pg, {
		name = "Upgrade",
		size = UDim2.new(1, -32, 0, 56),
		position = UDim2.fromOffset(16, 202),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		fillColor = Color3.fromHex("2F6FB0"),
		fillTransparency = 0,
		cornerRadius = UDim.new(0, 14),
	})
	upgrade.Activated:Connect(function()
		send("luck")
	end)
	UIKit.label(upgrade, {
		name = "Step",
		size = UDim2.new(1, 0, 0, 26),
		position = UDim2.fromOffset(0, 5),
		text = "Upgrade Luck",
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.header + 3,
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
	panel.upPrice = UIKit.label(upgrade, {
		name = "Price",
		size = UDim2.new(1, 0, 0, 18),
		position = UDim2.fromOffset(0, 31),
		text = "$0",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		color = Color3.fromHex("CFE3FF"),
		xAlign = Enum.TextXAlignment.Center,
		shadow = false,
	})
end

--- The stat chips' hover explanation: a dark slip just under the chip row, over the
--- top of the BREW key, shown while the mouse is on a chip (fillChips' `hover`).
local function buildPanelTip(pg: Frame)
	local tip = UIKit.panel(pg, {
		name = "Tip",
		size = UDim2.new(1, -32, 0, 40),
		position = UDim2.fromOffset(16, 144),
		color = Color3.fromHex("0B0E09"),
		transparency = 0.05,
		cornerRadius = UDim.new(0, 10),
		strokeColor = CHIP_STROKE,
		strokeThickness = 2,
		visible = false,
	})
	tip.ZIndex = 20
	local text = UIKit.label(tip, {
		name = "Text",
		size = UDim2.new(1, -16, 1, -6),
		position = UDim2.fromOffset(8, 3),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		shadow = false,
	})
	text.TextWrapped = true
	text.ZIndex = 21
	panel.tip = tip
	panel.tipText = text
end

--- fillChips' hover for the panel's row: show the chip's line, or hide on leave.
local function chipHover(_chip: Frame, line: string?)
	if panel.tip == nil then
		return
	end
	panel.tip.Visible = line ~= nil
	if line then
		panel.tipText.Text = line
	end
end

local function selectTab(which: string)
	panel.tab = which
	for _, key in TAB_ORDER do
		local on = key == which
		panel.pages[key].Visible = on
		local button = panel.tabs[key]
		button.BackgroundColor3 = if on then UIKit.C.selected else TAB_IDLE
		button.BackgroundTransparency = if on then 0 else 1
		button.TextColor3 = if on then UIKit.C.text else UIKit.C.dim
	end
	if panel.tip then
		panel.tip.Visible = false
	end
end

--- The tab strip and the close key across the top of the card.
local function buildPanelTabs(card: Frame)
	local strip = UIKit.panel(card, {
		name = "Tabs",
		size = UDim2.new(1, -32 - 42, 0, TAB_H),
		position = UDim2.fromOffset(16, TAB_TOP),
		color = TAB_IDLE,
		transparency = 0,
		cornerRadius = UDim.new(0, 12),
		strokeColor = UIKit.C.outline,
		strokeThickness = 2,
	})
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 3)
	padding.PaddingRight = UDim.new(0, 3)
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = strip
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = strip

	panel.tabs = {}
	for index, key in TAB_ORDER do
		local button = Instance.new("TextButton")
		button.Name = key
		button.LayoutOrder = index
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.Size = UDim2.fromScale(1 / #TAB_ORDER, 1)
		button.Font = UIKit.Font.hero
		button.TextSize = UIKit.TextSize.body
		button.Text = string.upper(key)
		button.Parent = strip
		round(button, UDim.new(0, 9))
		button.Activated:Connect(function()
			selectTab(key)
		end)
		panel.tabs[key] = button
	end

	local closeKey = UIKit.button(card, {
		name = "Close",
		size = UDim2.fromOffset(TAB_H, TAB_H),
		position = UDim2.new(1, -16, 0, TAB_TOP),
		anchorPoint = Vector2.new(1, 0),
		text = "X",
		font = UIKit.Font.hero,
		textSize = UIKit.TextSize.header,
		fillColor = UIKit.C.red,
		fillTransparency = 0,
		cornerRadius = UDim.new(0, 10),
		shadow = false,
	})
	closeKey.Activated:Connect(function()
		if panel.onClose then
			panel.onClose()
		end
	end)
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

	panel.pages = {
		brew = page(card, "BrewPage"),
		fluids = page(card, "FluidsPage"),
		luck = page(card, "LuckPage"),
	}
	buildPanelTabs(card)
	buildPanelFluid(panel.pages.brew)
	buildPanelBrew(panel.pages.brew)
	buildPanelTip(panel.pages.brew)
	buildPanelFluids(panel.pages.fluids)
	buildPanelLuck(panel.pages.luck)

	-- The server's notices (too poor, not at your bottle) belong to every tab.
	panel.notice = UIKit.label(card, {
		name = "Notice",
		size = UDim2.new(1, -32, 0, 18),
		position = UDim2.new(0, 16, 1, -26),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.amber,
		xAlign = Enum.TextXAlignment.Center,
	})
	selectTab("brew")
end

--- FLUIDS tab: light up every fluid in FluidState `seen`; the rest stay dark ???.
local function paintFluids()
	local seen = {}
	if type(state.seen) == "table" then
		for _, id in state.seen do
			seen[id] = true
		end
	end
	local count, total = 0, 0
	for id, tile in panel.tiles do
		local def = Liquids.get(id)
		local known = seen[id] == true
		local _, tierColour = tierOf(def)
		total += 1
		if known then
			count += 1
		end
		tile.fluid.BackgroundColor3 = if known then Color3.fromHex(def.color) else INK
		tile.stroke.Color = if known then tierColour else CHIP_STROKE
		tile.label.Text = if known then def.name else "???"
		tile.label.TextColor3 = if known then UIKit.C.text else UIKit.C.dim
	end
	panel.seenCount.Text = `{count} / {total} discovered`
end

--- LUCK tab: the header, and each row's odds at the luck rolled with now and after
--- one more Upgrade.
local function paintLuck()
	local luck = tonumber(state.luck) or 1
	local nextLuck = tonumber(state.nextLuck) or (luck + 1)
	panel.luck.Text = string.format("LUCK %gx", luck)
	panel.nextLuck.Text = string.format("NEXT %gx", nextLuck)
	local boost = tonumber(state.boost) or 1
	panel.boost.Text = if boost > 1 then string.format("x%g BOOST ACTIVE", boost) else ""

	local rollLuck = tonumber(state.rollLuck) or luck
	local nextRoll = tonumber(state.nextRollLuck) or rollLuck * nextLuck / luck
	local now = Liquids.oddsAt(rollLuck)
	local after = Liquids.oddsAt(nextRoll)
	for _, row in panel.luckRows do
		row.now.Text = oneIn(now[row.id] or 0)
		row.after.Text = oneIn(after[row.id] or 0)
	end
	panel.upPrice.Text = formatCash(tonumber(state.luckPrice) or 0)

	local jackpot = Liquids.ORDER[#Liquids.ORDER]
	panel.brewOdds.Text = string.format("LUCK %gx  ·  %s %s", luck, Liquids.get(jackpot).name, oneIn(now[jackpot] or 0))
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

	-- A roll can stack past one canister (Tuning.LIQUID_MAX_STACK); the bottle reads
	-- full from one canister up rather than showing a stack as a sliver.
	local full = if water or Tuning.LIQUID_INFINITE then 1 else math.clamp(held / math.max(def.charges, 1), 0, 1)
	panel.fluid.BackgroundColor3 = colour
	panel.fluid.Size = UDim2.new(1, -8 * ICON_SCALE, FILL_EMPTY + (FILL_FULL - FILL_EMPTY) * full, 0)
	panel.tip.Visible = false
	fillChips(panel.chips, def, UIKit.TextSize.body, 28, chipHover)

	paintFluids()
	paintLuck()
end

--- The BREW key's face: green with the flame and sheen while any brew is banked
--- ("BREW x3" past one); grey, counting down, when the bank is empty. The bar fills
--- toward the next banked brew either way, and hides once the bank is full.
local function paintBrew()
	if panel.brew == nil or state == nil then
		return
	end
	local left = (tonumber(state.cooldown) or 0) - (os.clock() - stateAt)
	local ready = brewsReady()
	local waiting = ready <= 0
	local total = tonumber(state.cooldownTotal) or Tuning.LIQUID_SPIN_COOLDOWN
	local done = 1 - math.clamp(left / total, 0, 1)
	panel.cooldown.Size = UDim2.new(done, -12 * done, 0, 6)
	if waiting then
		local secs = math.ceil(left)
		panel.brew.Text = string.format("BREW IN %d:%02d", secs // 60, secs % 60)
		panel.brew.TextSize = UIKit.TextSize.title - 4
		panel.brew.BackgroundColor3 = UIKit.C.empty
		panel.brew.TextColor3 = UIKit.C.dim
		panel.lip.BackgroundColor3 = IDLE_LIP
	else
		panel.brew.Text = if ready > 1 then `BREW x{ready}` else "BREW"
		-- The flame sits left of the word; "BREW x12" is wider, so it steps out further.
		panel.flame.Position = UDim2.new(0.5, if ready > 1 then -92 else -62, 0.5, -1)
		panel.brew.TextSize = 28
		panel.brew.BackgroundColor3 = BREW_READY
		panel.brew.TextColor3 = UIKit.C.text
		panel.lip.BackgroundColor3 = BREW_LIP
	end
	panel.cooldown.Visible = left > 0
	-- Green on the grey key; white over the green one so the next-brew bar still reads.
	panel.cooldown.BackgroundColor3 = if waiting then UIKit.C.green else Color3.new(1, 1, 1)
	local room = if waiting then SKIP_W + 10 else 0
	panel.skip.Visible = waiting
	panel.brew.Size = UDim2.new(1, -32 - room, 0, 60)
	panel.lip.Size = UDim2.new(1, -32 - room, 0, 60)
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
		selectTab("brew")
		panel.scale.Scale = 0.9 * PANEL_SCALE
		tween(panel.scale, 0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = PANEL_SCALE })
	else
		panel.tip.Visible = false
	end
end

--- E TO VIEW. The panel no longer pops up on its own: a "View" prompt hangs on your
--- own bottle and E opens it (E again closes it). It is made here, locally, so only
--- the owner ever sees it and the world needs no rebuild.
local viewPrompt: ProximityPrompt? = nil
local wantOpen = false
--- The tub's Wash prompt while the bottle has borrowed E from it (see watch).
local washStepped: ProximityPrompt? = nil
--- The card's X does what a second E does.
panel.onClose = function()
	wantOpen = false
end

local function ensurePrompt(bottle: BasePart?)
	if bottle == nil then
		if viewPrompt then
			viewPrompt:Destroy()
			viewPrompt = nil
		end
		return
	end
	if viewPrompt and viewPrompt.Parent == bottle then
		return
	end
	if viewPrompt then
		viewPrompt:Destroy()
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "FluidViewPrompt"
	p.ActionText = "View"
	p.ObjectText = "Brew Station"
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = PANEL_REACH
	p.RequiresLineOfSight = false
	p.Triggered:Connect(function()
		wantOpen = not wantOpen
	end)
	p.Parent = bottle
	viewPrompt = p
end

--- THE BREW HINT. After your third clean wash (FluidState `brewHint`) a little yellow
--- arrow bobs and turns over your bottle, pointing down at it, until the panel first
--- opens. Local parts, so only the owner sees it and the world needs no rebuild.
local HINT_YELLOW = Color3.fromHex("FFD21F")
--- Studs above the bottle's top, and how far it bobs either side of that.
local HINT_LIFT, HINT_BOB = 2.6, 0.35
local hintModel: Model? = nil
local hintSent = false
local hintParts: { { part: BasePart, offset: CFrame } } = {}

local function hintPart(model: Model, class: string, size: Vector3, offset: CFrame, colour: Color3)
	local p = Instance.new(class) :: BasePart
	p.Size = size
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = model
	table.insert(hintParts, { part = p, offset = offset })
end

--- A down-pointing arrow: a short shaft over a head of four wedges, crossed so the
--- point reads the same from every side while it turns.
local function buildHint(): Model
	local model = Instance.new("Model")
	model.Name = "BrewHintArrow"
	hintParts = {}
	local headW, headH, thick = 1.5, 1.1, 0.32
	local half = headW / 2
	hintPart(model, "Part", Vector3.new(0.5, 0.9, 0.5), CFrame.new(0, headH / 2 + 0.45, 0), HINT_YELLOW)
	for _, turn in { 0, math.pi / 2 } do
		local spin = CFrame.Angles(0, turn, 0)
		-- A WedgePart's right angle sits at its bottom back; flipped about Z it sits top
		-- back, so each one is half the triangle with its upright edge on the centre line.
		hintPart(model, "WedgePart", Vector3.new(thick, headH, half),
			spin * CFrame.new(0, 0, -half / 2) * CFrame.Angles(0, 0, math.pi), HINT_YELLOW)
		hintPart(model, "WedgePart", Vector3.new(thick, headH, half),
			spin * CFrame.new(0, 0, half / 2) * CFrame.Angles(0, math.pi, math.pi), HINT_YELLOW)
	end
	local light = Instance.new("PointLight")
	light.Color = HINT_YELLOW
	light.Range = 6
	light.Brightness = 0.6
	light.Parent = hintParts[1].part
	model.Parent = Workspace
	return model
end

--- Place (or clear) the arrow for this frame.
local function paintHint(bottle: BasePart?)
	local want = bottle ~= nil and state ~= nil and state.brewHint == true and not (panel.card and panel.card.Visible)
	if not want then
		if hintModel then
			hintModel:Destroy()
			hintModel = nil
		end
		return
	end
	if hintModel == nil or hintModel.Parent == nil then
		hintModel = buildHint()
	end
	local t = os.clock()
	local base = CFrame.new(bottle.Position + Vector3.new(0, bottle.Size.Y / 2 + HINT_LIFT + math.sin(t * 3) * HINT_BOB, 0))
		* CFrame.Angles(0, t * 1.6, 0)
	for _, entry in hintParts do
		entry.part.CFrame = base * entry.offset
	end
end

--- Show the panel once E has asked for it, while the local player is still at their
--- own bottle and no brew is on screen; walking away closes it. Polled at 10 Hz
--- rather than per frame: it is a distance check, and a tenth of a second is below
--- what anyone notices walking away from a table.
local function watch()
	local elapsed = 0
	local hintBottle: BasePart? = nil
	RunService.RenderStepped:Connect(function()
		paintHint(hintBottle)
	end)
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		elapsed = 0
		local bottle = ownBottle()
		hintBottle = bottle
		ensurePrompt(bottle)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local near = bottle ~= nil
			and root ~= nil
			and root:IsA("BasePart")
			and (root.Position - bottle.Position).Magnitude <= PANEL_REACH
		if not near then
			wantOpen = false
		end
		-- The tub's "Wash" prompt reaches 14 studs, over the bottle's table, and only
		-- one E prompt shows at a time -- it won. At the bottle the bottle gets E: the
		-- Wash prompt steps aside, locally, until you walk out of reach (the wash spot
		-- is outside PANEL_REACH, so nobody washing is ever in here).
		local wash = bottle and plotIndex and Workspace:FindFirstChild("Plots")
		wash = wash and wash:FindFirstChild(`Plot{plotIndex}`)
		wash = wash and wash:FindFirstChild("CleansingStation")
		wash = wash and wash:FindFirstChild("Wash", true)
		if wash and wash:IsA("ProximityPrompt") then
			if near and wash.Enabled then
				wash.Enabled = false
				washStepped = wash
			elseif not near and washStepped == wash then
				wash.Enabled = true
				washStepped = nil
			end
		end
		local brewing = ui.gui ~= nil and ui.gui.Enabled
		setOpen(wantOpen and near and state ~= nil and not brewing)
		if panel.card and panel.card.Visible and state and state.brewHint and not hintSent then
			-- Opened it: tell the server once so the arrow never comes back.
			hintSent = true
			Net.get("FluidAction"):FireServer("viewed")
		end
		if viewPrompt then
			viewPrompt.ActionText = if wantOpen then "Close" else "View"
		end
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
	-- PlotState is fired once on load and a queued remote event only reaches the first
	-- listener to connect, which may not be us: read our plot off RespawnLocation (the
	-- plot's PlotSpawn carries PlotIndex) too, as OwnStationPromptController does.
	local function fromSpawn()
		local spawn = Players.LocalPlayer.RespawnLocation
		local index = spawn and spawn:GetAttribute("PlotIndex")
		if type(index) == "number" then
			plotIndex = index
		end
	end
	fromSpawn()
	Players.LocalPlayer:GetPropertyChangedSignal("RespawnLocation"):Connect(fromSpawn)
	watch()
end

return Liquid
