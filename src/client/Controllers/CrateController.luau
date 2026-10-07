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
	sibling: the same dimmed screen, glow, light rays, burst, tier pill and chips.

	THE CARD REEL (2026-10-06, on request, the Slag Furnace's option 1): a strip of
	nuke cards slides across the screen past a marker, slows down and stops on your
	prize (client/PrizeReel). Every card is its rarity's colour under the L-stud
	pattern, with the nuke's model on the cards near the prize, and the glow behind
	eases to the rarity of the card under the marker. It replaced a reel that slid one
	3D nuke at a time through a single viewport. The reel is made of real rolls off
	the crate's own table, so the nukes that flash past most are the ones that come
	up most.

	THE PRIZE IS BUILT ONCE, when the crate opens, and cached; the single 3D view
	shows it only after the reel lands, turning on its plinth beside the stat sheet.

	THE MODEL NEVER MOVES PER FRAME. The turn and the reel slide are the CAMERA orbiting
	the model (with the light turned the same way, so the shading matches a turning
	model exactly). Moving a 150-part model is 150 part writes a frame; moving the
	camera is one.

	NO NUKE IS EVER SHOWN HALF-LOADED. Each nuke is 20-250 MeshParts that download one
	by one (a lone nuke measured 4.5 s in Studio), and a mesh that has not arrived draws
	as nothing -- the "incomplete nukes" bug. So:
	  * the view stays hidden while the nuke in it is still downloading and fades in
	    when it is whole (the name and glow carry on regardless);
	  * the reel's FILLER (every tile but the prize; it is cosmetic) is swapped, tile
	    by tile, for an already-downloaded nuke of the SAME rarity when the rolled one
	    is not ready, so the rarities flashing past are still the crate's real odds;
	  * the prize's meshes are fetched first when the crate opens (the background
	    preload pauses while a crate is open), and the landing waits up to PRIZE_WAIT
	    for them.

	THE RESULT IS A STAT SHEET (mockup option 2). On landing the nuke glides left and a
	sheet slides in on the right: the name with its kg beside it (big, on request), the
	tier / modifier / NEW FIND chips, a 10-star row that fills in, EARNS and WORTH, and
	bars for damage, radius and fuse -- each against the best a nuke from that nuke's
	home stage can roll -- then cooldown and the flavour line. The numbers come from the
	same `CarryService.describe` record the hotbar gets (CrateOpen's `item`) run
	through the same Shared/Bombing.statsFor the hotbar card uses, so the sheet and the
	card can never disagree.

	THE MESHES ARE PRELOADED BEFORE YOU OPEN ANYTHING. A nuke whose mesh this client has
	never downloaded draws as nothing the first time it flicks past (the Clockwork and
	Reactor nukes showed as an empty glow in testing). So the imported nuke templates
	are fetched from the server (they no longer replicate at join, Shared/ItemModels)
	and warmed with ContentProvider the moment you pick a crate up -- see
	preloadNukes. A reel entry drawn before its model lands is swapped for the real
	one on the next tick it shows (`cached`).

	All sizes are 1280x720 design pixels on UIKit.canvas (hud-scale-canvas).
]]

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
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
local Bombing = require(Shared.Bombing)
local BombConfig = require(Shared.Config.Bombing)
local Detonation = require(Shared.Detonation)
local Net = require(Shared.Net)

local UIKit = require(script.Parent.Parent.UIKit)
local Sfx = require(script.Parent.Parent.Sfx)
local Prefs = require(script.Parent.Parent.Prefs)
local RadFxArt = require(script.Parent.Parent.RadFxArt)
local PrizeReel = require(script.Parent.Parent.PrizeReel)

local CrateController = {}

-- ── Shared look (LiquidController's brew) ─────────────────────────────

local INK = Color3.fromHex("0B0E09")
local CHIP_FILL = Color3.fromHex("1B2217")
local HOT_STROKE = Color3.fromHex("FF8A4C")
local HOT_TEXT = Color3.fromHex("FFB38A")

local TICK_SOUND = "rbxasset://sounds/volume_slider.ogg"
local LAND_SOUND = "rbxasset://sounds/electronicpingshort.wav"

--- The crate's view: its size and centre on the design canvas (the flask's spot).
local VIEW_X = 640
local VIEW_Y = 272
local VIEW = 300
local RAY_COUNT = 9
local HOLD_SECONDS = 5
--- Where the nuke glides to when the sheet comes in, and the sheet itself (design px).
local SHEET_VIEW_X = 400
local SHEET_VIEW_Y = 330
local SHEET_X = 640
local SHEET_W = 560
local SHEET_H = 484
local SHEET_PAD = 24
local STAR_SIZE = 30
local GOLD = Color3.fromHex("FFD34D")
local MONEY = UIKit.House.cash
local FADE_SECONDS = 0.25
--- The reel's band across the screen, and its cards (design px).
local REEL_BAND_H = 196
local REEL_CARD = Vector2.new(124, 156)
--- How long the landed card holds before the prize's own view takes over.
local LAND_HOLD = 0.8
--- The same hold after a SKIP: just long enough to see which card it stopped on.
local SKIP_HOLD = 0.3
--- The soft glow behind the view: RadFx's white "soft dot with a bright core", tinted.
local GLOW_IMAGE = RadFxArt.mote
--- Sparks fall under this (design px/s^2) and lose speed to this drag per second.
local SPARK_GRAVITY = 520
local SPARK_DRAG = 0.35
--- The viewport's light, before the camera's orbit turns it.
local LIGHT = Vector3.new(-0.6, -1, 0.5)
--- The longest the landing waits for the prize's meshes before revealing anyway.
local PRIZE_WAIT = 2.5
--- While a nuke in view is still downloading, how often to look at it again (s).
local RECHECK_SECONDS = 0.2

local HELD_ITEM_NAME = "HeldItem" -- ToolService's name for whatever is in your hands
local OPEN_KEY = Enum.KeyCode.F

local ui: any = {}
--- CrateSkip (client -> server): the reel's SKIP button. Set in start().
local skipRemote: any = nil
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
type Framed = {
	model: Model,
	home: CFrame,
	camera: CFrame,
	radius: number,
	atHome: boolean,
	itemId: string,
	placeholder: boolean?,
	loaded: boolean?,
	checkedAt: number?,
}

--- Where idle cached models wait, well out of the camera's view.
local PARKED = CFrame.new(0, -1000, 0)

--- Centre `model` on the origin and work out the camera that fits it. It stays out of
--- the viewport until `stage` puts it there.
local function frame(model: Model): Framed
	untag(model)
	model:PivotTo(CFrame.new())
	local box, extents = model:GetBoundingBox()
	model:PivotTo(CFrame.new(-box.Position))

	local radius = extents.Magnitude / 2
	local distance = radius / math.tan(math.rad(ui.camera.FieldOfView / 2)) * 1.08
	return {
		model = model,
		home = model:GetPivot(),
		camera = CFrame.lookAt(Vector3.new(0, radius * 0.45, -distance), Vector3.zero),
		radius = radius,
		atHome = true,
		itemId = "",
	}
end

--- Put exactly `wanted` in the viewport, `current` at home in front of the camera and
--- the rest parked below it; take everything else out. Each model moves at most once
--- per call, and only when its place changes.
local function stage(wanted: { Framed }, current: Framed?)
	local keep: { [Framed]: boolean } = {}
	for _, framed in wanted do
		keep[framed] = true
	end
	if current then
		keep[current] = true
	end
	for framed in ui.staged do
		if not keep[framed] then
			framed.model.Parent = nil
			ui.staged[framed] = nil
		end
	end
	for framed in keep do
		local show = framed == current
		if not ui.staged[framed] then
			framed.model:PivotTo(if show then framed.home else PARKED * framed.home)
			framed.atHome = show
			framed.model.Parent = ui.viewport
			ui.staged[framed] = true
		elseif framed.atHome ~= show then
			framed.model:PivotTo(if show then framed.home else PARKED * framed.home)
			framed.atHome = show
		end
	end
	-- The camera is left alone: `aim` places it every frame, and resetting it here
	-- showed one un-turned frame at every swap.
	ui.current = current
end

--- Show just `framed` (nil shows nothing).
local function display(framed: Framed?)
	stage(if framed then { framed } else {}, framed)
end

--- Turn the view `angle` radians and slide it `slide` studs to the right by moving the
--- CAMERA (and the light with it) around the model, which never moves. Same picture
--- as turning and sliding the model, without writing every part every frame.
local function aim(angle: number, slide: number)
	local framed = ui.current
	if framed == nil then
		return
	end
	local turn = CFrame.Angles(0, -angle, 0)
	ui.camera.CFrame = turn * CFrame.new(framed.camera.RightVector * -slide) * framed.camera
	ui.viewport.LightDirection = turn:VectorToWorldSpace(LIGHT)
end

--- This player's copies of the nuke templates (Shared/ItemModels' client cache).
local function templateFolder(): Instance?
	return Players.LocalPlayer.PlayerGui:FindFirstChild(ItemModels.CLIENT_CACHE)
end

--- Item ids whose every mesh and texture has downloaded. Only ever grows.
local loadedIds: { [string]: boolean } = {}

--- True once every mesh and texture of `itemId`'s template has downloaded (a missing
--- one draws as nothing). False while the template itself has not arrived.
local function templateLoaded(itemId: string): boolean
	if loadedIds[itemId] then
		return true
	end
	local folder = templateFolder()
	local template = folder and folder:FindFirstChild(itemId)
	if template == nil then
		return false
	end
	for _, part in template:GetDescendants() do
		if part:IsA("MeshPart") then
			for _, content in { part.MeshId, part.TextureID } do
				if content ~= "" and ContentProvider:GetAssetFetchStatus(content) ~= Enum.AssetFetchStatus.Success then
					return false
				end
			end
		end
	end
	loadedIds[itemId] = true
	return true
end

--- Whether `framed` can be drawn whole. The rarity block an unarrived template falls
--- back to always can; a real nuke can once its meshes are in, re-checked at most
--- every RECHECK_SECONDS.
local function drawable(framed: Framed): boolean
	if framed.placeholder or framed.loaded then
		return true
	end
	local now = os.clock()
	if now - (framed.checkedAt or 0) < RECHECK_SECONDS then
		return false
	end
	framed.checkedAt = now
	framed.loaded = templateLoaded(framed.itemId)
	return framed.loaded == true
end

--- Destroy every model cached for the last opening.
local function clearCache()
	ui.staged = ui.staged or {}
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
	if framed and framed.placeholder and ItemModels.ready(itemId) then
		framed.model:Destroy()
		framed = nil
	end
	if framed == nil then
		local placeholder = not ItemModels.ready(itemId)
		framed = frame(prizeModel(itemId, rarity or "Common"))
		framed.placeholder = placeholder
		framed.itemId = itemId
		ui.cache[itemId] = framed
	end
	return framed
end

-- ── Build ─────────────────────────────────────────────────────────────

local function sound(id: string, volume: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	Sfx.adopt(s, "ui") -- under Settings' SOUND EFFECTS switch
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

	-- A soft glow behind the nuke, easing between rarity colours while the reel runs
	-- and blooming out on the landing. Under the rays: there is no additive blending,
	-- so a glow drawn over them would just wash them out.
	local bloom = Instance.new("ImageLabel")
	bloom.Name = "Bloom"
	bloom.BackgroundTransparency = 1
	bloom.Image = GLOW_IMAGE
	bloom.ImageTransparency = 1
	bloom.Size = UDim2.fromOffset(460, 460)
	bloom.Position = UDim2.fromOffset(VIEW_X, VIEW_Y)
	bloom.AnchorPoint = Vector2.new(0.5, 0.5)
	bloom.ZIndex = 0
	bloom.Parent = root
	ui.bloom = bloom

	-- The landing's shockwave: an empty circle that grows and thins out.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromOffset(80, 80)
	ring.Position = UDim2.fromOffset(VIEW_X, VIEW_Y)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.ZIndex = 2
	ring.Visible = false
	ring.Parent = root
	round(ring, UDim.new(1, 0))
	ui.ring = outline(ring, Color3.new(1, 1, 1), 10)
	ui.ringFrame = ring
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
	viewport.LightDirection = LIGHT
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

--- A left-to-right row of pills.
local function chipRow(parent: Instance, name: string, size: UDim2, position: UDim2): Frame
	local row = plainFrame(parent, name, size, position, Vector2.zero)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row
	return row
end

--- A caption over a value, in a tinted box (EARNS, WORTH).
local function moneyBox(parent: Instance, name: string, x: number, caption: string, fill: Color3, captionColour: Color3, valueColour: Color3): TextLabel
	local box = UIKit.panel(parent, {
		name = name,
		size = UDim2.fromOffset((SHEET_W - 2 * SHEET_PAD - 16) / 2, 84),
		position = UDim2.fromOffset(x, 164),
		color = fill,
		transparency = 0,
		cornerRadius = UDim.new(0, 14),
		strokeColor = UIKit.C.outline,
		strokeThickness = 2,
	})
	UIKit.label(box, {
		name = "Caption",
		size = UDim2.new(1, -24, 0, 20),
		position = UDim2.fromOffset(14, 10),
		text = caption,
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = captionColour,
		outline = false,
		strokeTransparency = 1,
	})
	return UIKit.label(box, {
		name = "Value",
		size = UDim2.new(1, -24, 0, 40),
		position = UDim2.fromOffset(14, 32),
		text = "",
		font = UIKit.Font.hero,
		textSize = 30,
		color = valueColour,
	})
end

--- One stat with a bar under it. Returns the value label and the bar's fill.
local function statBar(parent: Instance, name: string, y: number): (TextLabel, Frame)
	UIKit.label(parent, {
		name = `{name}Caption`,
		size = UDim2.fromOffset(200, 20),
		position = UDim2.fromOffset(SHEET_PAD, y),
		text = string.upper(name),
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		outline = false,
		strokeTransparency = 1,
	})
	local value = UIKit.label(parent, {
		name = `{name}Value`,
		size = UDim2.fromOffset(200, 20),
		position = UDim2.new(1, -SHEET_PAD, 0, y),
		anchorPoint = Vector2.new(1, 0),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		xAlign = Enum.TextXAlignment.Right,
	})
	local track = UIKit.panel(parent, {
		name = `{name}Track`,
		size = UDim2.new(1, -2 * SHEET_PAD, 0, 10),
		position = UDim2.fromOffset(SHEET_PAD, y + 24),
		color = UIKit.C.empty,
		transparency = 0,
		cornerRadius = UDim.new(1, 0),
		strokeThickness = 0,
	})
	local fill = UIKit.panel(track, {
		name = "Fill",
		size = UDim2.fromScale(0, 1),
		color = Color3.new(1, 1, 1),
		transparency = 0,
		cornerRadius = UDim.new(1, 0),
		strokeThickness = 0,
	})
	return value, fill
end

--- The result sheet (mockup option 2), hidden until a landing. A CanvasGroup so the
--- whole sheet fades in as one.
local function buildSheet(root: Frame)
	local sheet = Instance.new("CanvasGroup")
	sheet.Name = "Sheet"
	sheet.BackgroundColor3 = UIKit.C.panel
	sheet.BackgroundTransparency = 0.06
	sheet.BorderSizePixel = 0
	sheet.Size = UDim2.fromOffset(SHEET_W, SHEET_H)
	sheet.Position = UDim2.fromOffset(SHEET_X, SHEET_VIEW_Y)
	sheet.AnchorPoint = Vector2.new(0, 0.5)
	sheet.ZIndex = 5
	sheet.Visible = false
	sheet.Parent = root
	round(sheet, UDim.new(0, 22))
	ui.sheetStroke = outline(sheet, UIKit.C.outline, 3)
	ui.sheet = sheet

	-- The name with its kg right beside it, bigger than the old corner readout, on
	-- request. Both size to their text; `paintSheet` shrinks the name to make room.
	local titleRow = plainFrame(sheet, "Title", UDim2.new(1, -2 * SHEET_PAD, 0, 52), UDim2.fromOffset(SHEET_PAD, 18), Vector2.zero)
	local titleLayout = Instance.new("UIListLayout")
	titleLayout.FillDirection = Enum.FillDirection.Horizontal
	titleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	titleLayout.SortOrder = Enum.SortOrder.LayoutOrder
	titleLayout.Padding = UDim.new(0, 14)
	titleLayout.Parent = titleRow
	ui.sheetName = UIKit.label(titleRow, {
		name = "NukeName",
		size = UDim2.fromOffset(0, 52),
		text = "",
		font = UIKit.Font.hero,
		textSize = 40,
		-- No drop-shadow copy: it keeps its first TextSize, and the name shrinks to fit.
		shadow = false,
	})
	ui.sheetName.AutomaticSize = Enum.AutomaticSize.X
	ui.sheetName.LayoutOrder = 1
	ui.sheetKg = UIKit.label(titleRow, {
		name = "Kg",
		size = UDim2.fromOffset(0, 52),
		text = "",
		font = UIKit.Font.hero,
		textSize = 30,
		color = GOLD,
	})
	ui.sheetKg.AutomaticSize = Enum.AutomaticSize.X
	ui.sheetKg.LayoutOrder = 2

	ui.sheetChips = chipRow(sheet, "Chips", UDim2.new(1, -2 * SHEET_PAD, 0, 28), UDim2.fromOffset(SHEET_PAD, 76))

	-- Ten star slots: a dim star, and a lit one clipped to how much of it is earned
	-- (Rarity.stars comes in half steps), each popping in when the sheet lands.
	local starRow = plainFrame(sheet, "Stars", UDim2.new(1, -2 * SHEET_PAD, 0, STAR_SIZE), UDim2.fromOffset(SHEET_PAD, 118), Vector2.zero)
	ui.stars = {}
	for index = 1, 10 do
		local slot = plainFrame(starRow, `Star{index}`, UDim2.fromOffset(STAR_SIZE, STAR_SIZE), UDim2.fromOffset((index - 1) * (STAR_SIZE + 4), 0), Vector2.zero)
		local pop = Instance.new("UIScale")
		pop.Parent = slot
		local function glyph(parent: Instance, colour: Color3, transparency: number): TextLabel
			local label = UIKit.label(parent, {
				name = "Glyph",
				size = UDim2.fromOffset(STAR_SIZE, STAR_SIZE),
				text = "\u{2605}",
				font = UIKit.Font.hero,
				textSize = STAR_SIZE,
				color = colour,
				xAlign = Enum.TextXAlignment.Center,
				shadow = false,
			})
			label.TextTransparency = transparency
			return label
		end
		glyph(slot, Color3.new(1, 1, 1), 0.82)
		local clip = plainFrame(slot, "Lit", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), Vector2.zero)
		clip.ClipsDescendants = true
		glyph(clip, GOLD, 0)
		ui.stars[index] = { lit = clip, pop = pop }
	end

	local boxWidth = (SHEET_W - 2 * SHEET_PAD - 16) / 2
	ui.sheetEarns = moneyBox(sheet, "Earns", SHEET_PAD, "EARNS", Color3.fromHex("14301C"), Color3.fromHex("86EFAC"), MONEY)
	ui.sheetWorth = moneyBox(sheet, "Worth", SHEET_PAD + boxWidth + 16, "WORTH", Color3.fromHex("2A2410"), Color3.fromHex("FDE68A"), GOLD)

	ui.bars = {}
	for index, name in { "Damage", "Radius", "Fuse" } do
		local value, fill = statBar(sheet, name, 268 + (index - 1) * 46)
		ui.bars[index] = { value = value, fill = fill }
	end
	UIKit.label(sheet, {
		name = "CooldownCaption",
		size = UDim2.fromOffset(200, 20),
		position = UDim2.fromOffset(SHEET_PAD, 406),
		text = "COOLDOWN",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.caption,
		color = UIKit.C.dim,
		outline = false,
		strokeTransparency = 1,
	})
	ui.sheetCooldown = UIKit.label(sheet, {
		name = "CooldownValue",
		size = UDim2.fromOffset(200, 20),
		position = UDim2.new(1, -SHEET_PAD, 0, 406),
		anchorPoint = Vector2.new(1, 0),
		text = "",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.body,
		xAlign = Enum.TextXAlignment.Right,
	})
	ui.sheetFlavour = UIKit.label(sheet, {
		name = "Flavour",
		size = UDim2.new(1, -2 * SHEET_PAD, 0, 40),
		position = UDim2.fromOffset(SHEET_PAD, 434),
		text = "",
		font = UIKit.Font.body,
		textSize = UIKit.TextSize.body - 1,
		color = Color3.fromHex("C9D3C2"),
	})
	ui.sheetFlavour.TextWrapped = true
	ui.sheetFlavour.TextYAlignment = Enum.TextYAlignment.Top
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
	ui.cycleHome = ui.cycle.Position

	-- The rarity of whatever is flicking past right now, under its name, on request, so
	-- a Legendary going by reads as one before it lands.
	local cycleTier = plainFrame(root, "CycleTierBox", UDim2.fromOffset(240, 22), UDim2.fromOffset(VIEW_X, top + 44), Vector2.new(0.5, 0))
	cycleTier.ZIndex = 5
	cycleTier.Visible = false
	ui.cycleTier = cycleTier
	ui.cycleTierPill, ui.cycleTierText = pill(cycleTier, "Tier", "", UIKit.TextSize.caption, 22, UIKit.C.dim, INK)
	ui.cycleTierPill.AnchorPoint = Vector2.new(0.5, 0)
	ui.cycleTierPill.Position = UDim2.fromScale(0.5, 0)

	ui.sparks = {}
	buildSheet(root)
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

	-- The card reel, a dark band right across the screen through the view's middle.
	local band = plainFrame(root, "ReelBand", UDim2.fromOffset(UIKit.DESIGN_SCREEN.X * 3, REEL_BAND_H), UDim2.fromOffset(VIEW_X, VIEW_Y), Vector2.new(0.5, 0.5))
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BackgroundTransparency = 0.4
	band.ZIndex = 4
	band.Visible = false
	ui.reelBand = band
	ui.reel = PrizeReel.new(band, {
		size = UDim2.fromScale(1, 1),
		widthHint = UIKit.DESIGN_SCREEN.X * 1.5,
		cardSize = REEL_CARD,
		gap = 10,
		zIndex = 4,
		marker = HOT_STROKE,
		artAtStart = false,
	})

	-- SKIP, under the reel while it runs: snaps it onto the prize and has the server
	-- settle the open now, so the nuke is in your hands with the result sheet.
	local skip, skipStroke = UIKit.button(root, {
		name = "Skip",
		size = UDim2.fromOffset(150, 44),
		position = UDim2.fromOffset(VIEW_X, VIEW_Y + REEL_BAND_H / 2 + 18),
		anchorPoint = Vector2.new(0.5, 0),
		text = "SKIP",
		font = UIKit.Font.title,
		textSize = UIKit.TextSize.header,
		fillColor = Color3.new(0, 0, 0),
		fillTransparency = 0.35,
		strokeColor = HOT_STROKE,
		strokeThickness = 2.5,
		zIndex = 6,
		visible = false,
	})
	-- The orange ring on the box only; the word gets the usual dark outline.
	skipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	skip.TextStrokeColor3 = INK
	skip.TextStrokeTransparency = 0
	skip.MouseEnter:Connect(function()
		skip.BackgroundTransparency = 0.15
	end)
	skip.MouseLeave:Connect(function()
		skip.BackgroundTransparency = 0.35
	end)
	ui.skip = skip

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
		position = UDim2.new(0.5, 0, 1, -UIKit.Dock.VITALS_CLEAR),
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

	-- While the reel runs the glow and the faint rays EASE toward the rarity of the
	-- nuke in view instead of snapping to it on every tick.
	if ui.glowTarget then
		local k = 1 - 0.002 ^ dt
		local colour = ui.bloom.ImageColor3:Lerp(ui.glowTarget, k)
		ui.bloom.ImageColor3 = colour
		for _, bar in ui.rayBars do
			bar.BackgroundColor3 = colour
		end
	end

	-- Sparks from the landing: arcs under gravity, tumbling, shrinking and fading.
	local sparks = ui.sparks
	for index = #sparks, 1, -1 do
		local spark = sparks[index]
		spark.life -= spark.decay * dt
		if spark.life <= 0 then
			spark.frame:Destroy()
			table.remove(sparks, index)
			continue
		end
		spark.vy += SPARK_GRAVITY * dt
		spark.vx *= SPARK_DRAG ^ dt
		spark.x += spark.vx * dt
		spark.y += spark.vy * dt
		local size = spark.size * spark.life + 1
		spark.frame.Position = UDim2.fromOffset(spark.x, spark.y)
		spark.frame.Size = UDim2.fromOffset(size, size)
		spark.frame.Rotation += spark.spin * dt
		spark.frame.BackgroundTransparency = 1 - math.clamp(spark.life, 0, 1)
	end
end

--- Sparks flying out of the crate in the rarity's colour and the crate's.
local function burst(primary: Color3, secondary: Color3, count: number, spread: number, origin: Vector2)
	local palette = { primary, primary, secondary, Color3.new(1, 1, 1) }
	for index = 1, count do
		local size = math.random(6, 16)
		local spark = Instance.new("Frame")
		spark.Name = "Spark"
		spark.BorderSizePixel = 0
		spark.BackgroundColor3 = palette[(index % #palette) + 1]
		spark.Size = UDim2.fromOffset(size, size)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = UDim2.fromOffset(origin.X, origin.Y)
		spark.Rotation = math.random(0, 90)
		spark.ZIndex = 6
		spark.Parent = ui.root
		-- Square splinters, not droplets: this is a box bursting, not a flask. Stepped
		-- in animateAmbient so they arc and fall instead of sliding out in lines.
		local angle = math.random() * math.pi * 2
		local speed = spread * (0.4 + 0.6 * math.random())
		table.insert(ui.sparks, {
			frame = spark,
			x = origin.X,
			y = origin.Y,
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed - spread * 0.35,
			size = size,
			spin = math.random(-300, 300),
			life = 1,
			decay = 0.55 + math.random() * 0.5,
		})
	end
end

local function close(token: number)
	if token ~= spinToken or ui.gui == nil then
		return
	end
	ui.opening = false
	tween(ui.scale, FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { Scale = 0.92 })
	tween(ui.dim, FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { BackgroundTransparency = 1 })
	task.delay(FADE_SECONDS, function()
		if token == spinToken then
			ui.gui.Enabled = false
			if ui.connection then
				ui.connection:Disconnect()
				ui.connection = nil
			end
			ui.reel.clear()
			clearCache()
		end
	end)
end

--- The sheet's chips: the tier, then the modifier and NEW FIND when there are any.
local function fillChips(payload: any, colour: Color3): { Frame }
	for _, child in ui.sheetChips:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local made = {}
	local tier = pill(ui.sheetChips, "Tier", string.upper(payload.rarity or ""), UIKit.TextSize.caption, 26, colour, INK)
	tier.LayoutOrder = 1
	table.insert(made, tier)
	local specs = {}
	if payload.modifier and payload.modifier ~= "None" then
		table.insert(specs, string.upper(payload.modifier))
	end
	if payload.firstFind then
		table.insert(specs, "NEW FIND")
	end
	for index, text in specs do
		local chip = pill(ui.sheetChips, `Chip{index}`, text, UIKit.TextSize.caption, 26, CHIP_FILL, HOT_TEXT)
		chip.LayoutOrder = index + 1
		outline(chip, HOT_STROKE, 2)
		table.insert(made, chip)
	end
	return made
end

--- "$2.00/s" up to "$1.2T/s", the hotbar card's ladder (InventoryController.formatRate).
local function formatRate(perSecond: number): string
	if perSecond >= 1_000_000_000_000 then
		return string.format("$%.1fT/s", perSecond / 1_000_000_000_000)
	elseif perSecond >= 1_000_000_000 then
		return string.format("$%.1fB/s", perSecond / 1_000_000_000)
	elseif perSecond >= 1_000_000 then
		return string.format("$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 1000 then
		return string.format("$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("$%.1f/s", perSecond)
	end
	return string.format("$%.2f/s", perSecond)
end

--- How far along each bar runs: the stat against the best a nuke from this one's home
--- stage can roll (top-power row x the stage's multiplier x the biggest size roll x the
--- top of the variance). Fuse is the other way round: shorter is better.
local function barFractions(itemId: string?, stats: any): (number, number, number)
	local homeStage = 1
	if itemId and Items.has(itemId) then
		homeStage = Items.homeStage(Items.get(itemId))
	end
	local hitMult, radiusMult = Detonation.stageMults(homeStage)
	local top = BombConfig.SIZE_MAX * (1 + BombConfig.VARIANCE)
	local damage = stats.damage / (BombConfig.DAMAGE[#BombConfig.DAMAGE] * hitMult * top)
	local radius = stats.radius / (BombConfig.RADIUS[#BombConfig.RADIUS] * radiusMult * top)
	local slowest = BombConfig.FUSE_BY_RARITY[1] + BombConfig.FUSE_SPREAD + (BombConfig.FUSE_SIZE_BONUS.GIGA or 0)
	local fastest = BombConfig.FUSE_BY_RARITY[#BombConfig.FUSE_BY_RARITY] - BombConfig.FUSE_SPREAD
	local fuse = (slowest - stats.fuse) / (slowest - fastest)
	return math.clamp(damage, 0.06, 1), math.clamp(radius, 0.06, 1), math.clamp(fuse, 0.06, 1)
end

--- Fill the sheet from a CrateOpen payload and play it in: slide + fade, the stars
--- popping in one by one, the bars growing.
local function paintSheet(payload: any, colour: Color3)
	local item = if type(payload.item) == "table" then payload.item else { rarity = payload.rarity, itemId = payload.result }
	local bomberMult = Players.LocalPlayer:GetAttribute("MasteryBombDamage")
	local stats = Bombing.statsFor(item, if type(bomberMult) == "number" then bomberMult else nil)

	-- Name and kg on one line: the kg keeps its size and the name shrinks to fit.
	local kgText = if type(item.weight) == "number" then UIKit.formatKg(item.weight) else ""
	ui.sheetKg.Text = kgText
	local room = SHEET_W - 2 * SHEET_PAD - 14
		- TextService:GetTextSize(kgText, 30, UIKit.Font.hero, Vector2.new(10000, 100)).X - 6
	local name = payload.name or ""
	local size = 40
	while size > 22 and TextService:GetTextSize(name, size, UIKit.Font.hero, Vector2.new(10000, 100)).X > room do
		size -= 2
	end
	ui.sheetName.TextSize = size
	ui.sheetName.Text = name
	ui.sheetName.TextColor3 = colour
	ui.sheetStroke.Color = colour:Lerp(UIKit.C.outline, 0.45)

	local chips = fillChips(payload, colour)
	for index, chip in chips do
		local grow = Instance.new("UIScale")
		grow.Scale = 0
		grow.Parent = chip
		task.delay(0.3 + index * 0.08, function()
			tween(grow, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
		end)
	end

	local stars = tonumber(stats.stars) or 1
	for index, star in ui.stars do
		local earned = math.clamp(stars - (index - 1), 0, 1)
		earned = if earned >= 1 then 1 elseif earned >= 0.5 then 0.5 else 0
		star.lit.Size = UDim2.fromScale(earned, 1)
		if earned > 0 then
			star.pop.Scale = 0.01
			task.delay(0.45 + index * 0.07, function()
				tween(star.pop, 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
			end)
		else
			star.pop.Scale = 1
		end
	end

	if type(item.perSecond) == "number" then
		ui.sheetEarns.Text = formatRate(item.perSecond)
		ui.sheetEarns.TextColor3 = MONEY
	else
		ui.sheetEarns.Text = "NOTHING"
		ui.sheetEarns.TextColor3 = UIKit.C.dim
	end
	ui.sheetWorth.Text = if type(payload.value) == "number" then formatCash(payload.value) else "?"

	local damage, radius, fuse = barFractions(item.itemId, stats)
	local rows = {
		{ text = tostring(stats.damage), fraction = damage },
		{ text = `{stats.radius} studs`, fraction = radius },
		{ text = `{stats.fuse}s`, fraction = fuse },
	}
	for index, row in rows do
		local bar = ui.bars[index]
		bar.value.Text = row.text
		bar.fill.BackgroundColor3 = colour
		bar.fill.Size = UDim2.fromScale(0, 1)
		task.delay(0.5 + index * 0.1, function()
			tween(bar.fill, 0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Size = UDim2.fromScale(row.fraction, 1) })
		end)
	end
	ui.sheetCooldown.Text = `{stats.cooldown}s`
	ui.sheetFlavour.Text = payload.flavor or ""

	local sheet = ui.sheet
	sheet.Position = UDim2.fromOffset(SHEET_X + 50, SHEET_VIEW_Y)
	sheet.GroupTransparency = 1
	sheet.Visible = true
	tween(sheet, 0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
		Position = UDim2.fromOffset(SHEET_X, SHEET_VIEW_Y),
		GroupTransparency = 0,
	})
end

local function reveal(payload: any, token: number)
	local colour, rank = rarityColour(payload.rarity)
	local crateColour = Color3.fromHex(Crates.get(payload.crate).color)

	display(cached(payload.result, payload.rarity))
	ui.cycle.Visible = false
	ui.cycleTier.Visible = false

	-- A soft landing, the brew's: a gentle pulse, a faint rarity tint instead of a
	-- white flash, the glow blooming out, the rays fading in, a shockwave ring, and
	-- sparks. Rarer lands glow brighter and throw more.
	ui.glowTarget = nil
	ui.viewScale.Scale = 1.07
	tween(ui.viewScale, 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Scale = 1 })
	ui.flash.BackgroundColor3 = colour
	ui.flash.BackgroundTransparency = if Prefs.get("reduceFlashing") then 0.95 else 0.82
	tween(ui.flash, 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 1 })
	ui.bloom.ImageColor3 = colour
	tween(ui.bloom, 0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
		ImageTransparency = math.max(0.15, 0.5 - rank * 0.05),
		Size = UDim2.fromOffset(600 + rank * 40, 600 + rank * 40),
	})
	for _, bar in ui.rayBars do
		bar.BackgroundColor3 = colour
		tween(bar, 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = math.max(0.2, 0.55 - rank * 0.05) })
	end
	ui.ringFrame.Size = UDim2.fromOffset(VIEW * 0.4, VIEW * 0.4)
	ui.ringFrame.Visible = true
	ui.ring.Color = colour
	ui.ring.Thickness = 10
	ui.ring.Transparency = 0.15
	tween(ui.ringFrame, 0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(VIEW * 1.7, VIEW * 1.7) })
	tween(ui.ring, 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Thickness = 1, Transparency = 1 })
	-- The nuke glides left to make room for the sheet, and everything that hangs off
	-- its centre (glow, rays, ring) goes with it; the sparks burst from where it lands.
	local glide = UDim2.fromOffset(SHEET_VIEW_X, SHEET_VIEW_Y)
	for _, thing in { ui.viewHolder, ui.rays, ui.bloom, ui.ringFrame } do
		tween(thing, 0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, { Position = glide })
	end
	burst(colour, crateColour, 22 + rank * 7, 240 + rank * 25, Vector2.new(SHEET_VIEW_X, SHEET_VIEW_Y))
	ui.land.PlaybackSpeed = 0.85 + 0.07 * rank
	ui.land:Play()

	paintSheet(payload, colour)

	task.delay(HOLD_SECONDS, close, token)
end

--- The reel as it is drawn: the server's reel with every FILLER tile (all but `land`,
--- the prize) whose nuke has not downloaded yet swapped for a downloaded nuke of the
--- same rarity from this crate's pool, when there is one. The filler is cosmetic, and
--- keeping each tile's rarity keeps what flashes past honest to the crate's odds.
local function fillReel(reel: { any }, land: number, crateId: string): { any }
	local pool: { [string]: { string } } = {}
	local ok, odds = pcall(Crates.nukeOdds, crateId)
	if ok and type(odds) == "table" then
		for itemId in odds do
			if templateLoaded(itemId) then
				local def = Items.get(itemId)
				local list = pool[def.rarity]
				if list == nil then
					list = {}
					pool[def.rarity] = list
				end
				table.insert(list, itemId)
			end
		end
	end
	local shown = table.clone(reel)
	for index, entry in reel do
		if index ~= land and type(entry) == "table" and type(entry.itemId) == "string" and not templateLoaded(entry.itemId) then
			local options = pool[entry.rarity]
			if options and #options > 0 then
				local itemId = options[math.random(#options)]
				local def = Items.get(itemId)
				shown[index] = { itemId = itemId, name = def.name, rarity = def.rarity }
			end
		end
	end
	return shown
end

--- When a crate opens: fetch the PRIZE's meshes first (the landing waits on them),
--- then the rest of the reel's. Ids whose template has not arrived are asked for.
local function preloadReel(reel: { any }, prizeId: string?)
	local ids = {}
	local seen = {}
	if type(prizeId) == "string" then
		table.insert(ids, prizeId)
		seen[prizeId] = true
	end
	for _, entry in reel do
		if type(entry) == "table" and type(entry.itemId) == "string" and not seen[entry.itemId] then
			seen[entry.itemId] = true
			table.insert(ids, entry.itemId)
		end
	end
	ItemModels.request(ids)
	task.spawn(function()
		local folder = Players.LocalPlayer.PlayerGui:FindFirstChild(ItemModels.CLIENT_CACHE)
		if folder == nil then
			return
		end
		local prize = if type(prizeId) == "string" then folder:FindFirstChild(prizeId) else nil
		if prize then
			pcall(ContentProvider.PreloadAsync, ContentProvider, { prize })
		end
		local rest = {}
		for _, itemId in ids do
			local template = folder:FindFirstChild(itemId)
			if template and template ~= prize then
				table.insert(rest, template)
			end
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, rest)
	end)
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
	local reel = fillReel(payload.reel, math.clamp(tonumber(payload.land) or #payload.reel, 1, #payload.reel), payload.crate)
	local land = math.clamp(tonumber(payload.land) or #reel, 1, #reel)
	local seconds = math.max(tonumber(payload.seconds) or 4.5, 0.5)

	clearCache()
	preloadReel(reel, payload.result)
	-- The prize, built now and staged in the (hidden) view, so the reveal never waits on
	-- a clone.
	display(cached(payload.result, payload.rarity))
	ui.opening = true
	ui.hide = 1
	local first = reel[1]
	ui.header.Text = string.upper(crate.name)
	ui.header.TextColor3 = Color3.fromHex(crate.color)
	ui.sheet.Visible = false
	ui.cycle.Visible = false
	ui.cycleTier.Visible = false
	ui.viewHolder.Position = ui.viewHome
	ui.viewHolder.Visible = false
	local centre = UDim2.fromOffset(VIEW_X, VIEW_Y)
	ui.rays.Position = centre
	ui.bloom.Position = centre
	ui.ringFrame.Position = centre
	ui.viewScale.Scale = 1
	for _, bar in ui.rayBars do
		bar.BackgroundTransparency = 0.82
	end
	ui.ringFrame.Visible = false
	ui.flash.BackgroundTransparency = 1
	ui.viewport.ImageTransparency = 1
	ui.bloom.Size = UDim2.fromOffset(460, 460)
	ui.bloom.ImageTransparency = 0.75
	local firstColour = rarityColour(if type(first) == "table" then first.rarity else nil)
	ui.bloom.ImageColor3 = firstColour
	ui.glowTarget = firstColour
	ui.scale.Scale = 0.92
	ui.dim.BackgroundTransparency = 1
	ui.reelBand.Visible = true
	ui.gui.Enabled = true
	tween(ui.scale, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })
	tween(ui.dim, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { BackgroundTransparency = 0.45 })

	local entries: { PrizeReel.Entry } = {}
	for index, entry in reel do
		local known = type(entry) == "table"
		local itemId = if known and type(entry.itemId) == "string" then entry.itemId else payload.result
		local rarity = if known then entry.rarity else nil
		entries[index] = {
			name = if known and entry.name then entry.name else "???",
			tier = rarity,
			item = { uid = `crate-reel-{index}`, itemId = itemId, identified = true, rarity = rarity },
		}
	end
	local landedAt: number? = nil
	local skipped = false
	ui.reel.spin(entries, land, seconds, {
		onTick = function(entry)
			-- The glow behind eases toward the rarity under the marker (animateAmbient),
			-- so a Legendary going by is felt before it is read.
			ui.glowTarget = rarityColour(entry.tier)
			ui.tick:Play()
		end,
		onLand = function()
			landedAt = os.clock()
			ui.skip.Visible = false
		end,
	})

	if ui.skipConnection then
		ui.skipConnection:Disconnect()
	end
	ui.skip.Visible = true
	ui.skipConnection = ui.skip.Activated:Connect(function()
		if token ~= spinToken or skipped then
			return
		end
		skipped = true
		ui.skip.Visible = false
		ui.reel.skip()
		skipRemote:FireServer()
	end)

	local revealed = false
	local turn = 0

	--- The view's transparency: hidden while the prize is still downloading, eased in
	--- once it is whole.
	local function showView(dt: number)
		if ui.current and drawable(ui.current) then
			ui.hide -= ui.hide * (1 - 0.0005 ^ dt)
		else
			ui.hide = 1
		end
		ui.viewport.ImageTransparency = ui.hide
	end
	ui.connection = RunService.RenderStepped:Connect(function(dt)
		if token ~= spinToken then
			return
		end
		if not revealed then
			-- Reveal once the landed card has held a moment and the prize can draw whole:
			-- its template has arrived and its meshes are in, or PRIZE_WAIT has run out.
			if landedAt then
				local since = os.clock() - landedAt
				local prize = cached(payload.result, payload.rarity)
				if since >= (if skipped then SKIP_HOLD else LAND_HOLD) and ((not prize.placeholder and drawable(prize)) or since >= PRIZE_WAIT) then
					revealed = true
					ui.opening = false
					ui.reelBand.Visible = false
					ui.viewHolder.Visible = true
					reveal(payload, token)
					aim(turn, 0)
				end
			end
		elseif ui.current then
			-- The prize turns slowly on its plinth while the result is up (and fades in
			-- late if PRIZE_WAIT ran out before its meshes did).
			turn += dt * 0.8
			aim(turn, 0)
			showView(dt)
		end
		animateAmbient(dt)
	end)
end

-- ── Preloading ────────────────────────────────────────────────────────

--- Seconds after joining before the background warm-up, so it never competes with
--- the first things a player loads.
local warmed: { [string]: boolean } = {}

--- Fetch every nuke `crateId` can roll from the server (Shared/ItemModels) and
--- download their meshes, so no reel shows a blank. Once per crate type, non-blocking.
local function preloadNukes(crateId: string)
	if warmed[crateId] then
		return
	end
	warmed[crateId] = true
	local odds = Crates.nukeOdds(crateId)
	local ids = {}
	for itemId in odds do
		table.insert(ids, itemId)
	end
	if #ids == 0 then
		return
	end
	-- Likeliest first, one nuke at a time: the ones the reel shows most are ready
	-- soonest, instead of every mesh of every nuke landing together at the end.
	table.sort(ids, function(a, b)
		return (tonumber(odds[a]) or 0) > (tonumber(odds[b]) or 0)
	end)
	ItemModels.request(ids)
	task.spawn(function()
		for _, itemId in ids do
			-- Give the queue to an opening crate's prize: wait while one is open.
			while ui.opening do
				task.wait(0.25)
			end
			local folder = templateFolder()
			local template = folder and folder:FindFirstChild(itemId)
			if template == nil and ItemModels.await(itemId, 10) then
				folder = templateFolder()
				template = folder and folder:FindFirstChild(itemId)
			end
			if template then
				pcall(ContentProvider.PreloadAsync, ContentProvider, { template })
			end
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
	preloadNukes(crateId)
	if prompt and prompt:GetAttribute("Uid") == uid and prompt.Parent and prompt.Parent:IsDescendantOf(held) then
		return
	end
	clearPrompt()

	local anchor = (held :: Model).PrimaryPart or held:FindFirstChildWhichIsA("BasePart", true)
	if anchor == nil then
		-- StreamingEnabled: the model can land before its parts (or its attributes do).
		-- Try again as soon as a part shows up instead of giving up for good.
		local waiter
		waiter = held.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				waiter:Disconnect()
				task.defer(refreshPrompt, character)
			end
		end)
		held.AncestryChanged:Once(function()
			waiter:Disconnect()
		end)
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
	skipRemote = Net.get("CrateSkip")
	Net.get("CrateOpened").OnClientEvent:Connect(play)

	local player = Players.LocalPlayer
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

return CrateController
