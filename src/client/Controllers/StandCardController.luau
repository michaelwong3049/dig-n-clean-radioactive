--!strict
--[[
	StandCardController.luau — the trophy-ribbon card over every nuke on a display stand.

	WHAT IT SHOWS, top to bottom: the rarity (shimmering from Legendary up), one star
	per tier, the name across a rarity-coloured prize ribbon with notched tails, a coin
	pill with what the piece pays per second beside a pill with what it weighs, and --
	only when they apply -- stickers for the modifier and a big size roll, how far a
	duplicate's share is cut, and (to the plot's owner only) how long until a nuke that
	just went up can come back off.

	THE SERVER PUBLISHES, THIS DRAWS. ExhibitService writes a handful of attributes on
	each stand's Display part (Shared/StandCard names them, and says why) and every
	client builds its own BillboardGui on that part. The shimmer, the pop when a nuke
	goes up and the crating countdown all run here, so none of it costs a replicated
	write.

	A STUD-SIZED BILLBOARD, on request. A pixel-sized one holds its size on screen while
	the world shrinks around it, so zooming out made every card look huge next to its
	stand. This one is CARD_STUDS wide in the world: it still turns to face the camera,
	but it shrinks and grows with the plinth under it. The card is still laid out in
	design px (L below) and one UIScale fits that layout to whatever the gui measures on
	screen this frame, so every TextSize stays fixed relative to the card (the old card's
	TextScaled name resized itself card to card); only the ribbon's width follows its name.

	HUNG FROM THE NUKE'S OWN TOP. The gui's bottom edge sits LIFT studs above CardTop, the
	top of whatever model is on the plinth, so a GIGA roll carries its card up with it
	instead of swallowing a card pinned at one height.

	PRIMITIVES ONLY, NO UPLOADED ART. The tails' notches are horizontal strips (a
	triangle without masking the world behind it), the coin is
	CashController's coin in miniature, and the lock is three rounded frames.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Weight = require(Shared.Config.Weight)
local Rarity = require(Shared.Config.Rarity)
local Tuning = require(Shared.Config.Tuning)
local Payload = require(Shared.Config.Payload)
local StandCard = require(Shared.StandCard)

local UIKit = require(script.Parent.Parent.UIKit)

local StandCards = {}

local A = StandCard.ATTR

-- The cartoon black every chunky card in the game is outlined in (CashController's
-- INK, Kit.C.hazardBlack), a touch softer than UIKit.C.outline's pure black.
local INK = Color3.fromHex("1A1A1A")
local WHITE = Color3.new(1, 1, 1)

local STYLE = {
	nameFont = Enum.Font.LuckiestGuy,
	font = Enum.Font.FredokaOne,
	-- The cash badge's rate pill and coin, so a stand's $/s reads as the same money.
	pill = Color3.fromHex("FF7A1A"),
	coin = Color3.fromHex("FFB81C"),
	coinFace = Color3.fromHex("FFD34D"),
	coinRim = Color3.fromHex("D98A00"),
	coinMark = Color3.fromHex("B36A00"),
	kg = Color3.fromHex("5E6773"), -- steel, for a weight
	star = Color3.fromHex("FFCF3A"),
	foot = Color3.fromHex("D7DCE0"),
	chip = Color3.fromHex("3A3F45"),
}

-- Sticker colours. Nothing else in the game names a modifier yet, so this is where
-- they get one; an unlisted modifier still gets a sticker, in grey.
local MODIFIER_COLOR: { [string]: Color3 } = {
	Pristine = Color3.fromHex("7DF9FF"),
	Irradiated = Color3.fromHex("A3FF3C"),
	Fused = Color3.fromHex("FF8A3D"),
	PrewarSealed = Color3.fromHex("E3C27A"),
	Cracked = Color3.fromHex("A7ADB4"),
}
-- DetectorController's callout colours, so the sticker matches the dig's own shout.
local CALLOUT_COLOR: { [string]: Color3 } = {
	GIGA = Color3.fromHex("FACC15"),
	OVERSIZED = Color3.fromHex("F59E0B"),
}

-- How each tier's rarity word is filled. "glint" sweeps a pale band across the base
-- colour; "rainbow" rocks a spectrum back and forth. Tiers not listed are flat, Epic
-- gets a still top-to-bottom fade.
local SHIMMER: { [string]: { kind: string, glint: Color3? } } = {
	Epic = { kind = "fade" },
	Legendary = { kind = "glint", glint = Color3.fromHex("FFF1B8") },
	Mythic = { kind = "glint", glint = Color3.fromHex("FFD6D6") },
	Anomaly = { kind = "rainbow" },
}
local RAINBOW = { "FF5D5D", "FFCF3A", "5CD65C", "3DB8F5", "A855F7", "FF5D9E" }
local RIBBON_RAINBOW = { "FF8F8F", "FFD97A", "8FE68F", "7FCAF7", "C89BFA" }

-- Design px on the card's own footprint, fitted to CARD_STUDS. Top to bottom: rarity,
-- stars, ribbon, pill row, footer. With no footer everything drops FOOTLESS_DROP so
-- the pill row sits on the card's bottom edge either way.
local L = {
	width = 300,
	height = 152,
	rarityY = 0,
	rarityH = 18,
	raritySize = 15,
	starsY = 20,
	starW = 14,
	starH = 16,
	starOn = 15,
	starOff = 11,
	bannerY = 40,
	bannerH = 40,
	bannerMin = 150,
	bannerMax = 236,
	bannerPad = 40, -- name width -> ribbon width
	nameSize = 21,
	nameMin = 15,
	nameDrop = 3, -- LuckiestGuy draws high in its line box (CashController measured the same)
	tailW = 46,
	tailH = 34,
	tailDrop = 10, -- tails hang this far below the ribbon's top edge
	tailTuck = 22, -- and stick out this far past each end of it
	notch = 11,
	strip = 2, -- row height the notched tails are drawn in
	pillY = 92,
	pillH = 28,
	pillGap = 6,
	coin = 22,
	rateSize = 18,
	kgSize = 16,
	stickerH = 18,
	stickerSize = 12,
	stickerTilt = 10,
	footY = 130,
	footH = 20,
	footSize = 13,
	footGap = 6,
	shadow = 4,
	stroke = 3,
}
local FOOTLESS_DROP = 24

-- The card's footprint in studs, L.width wide. 11 puts the ribbon itself at ~7-10
-- studs, about the width of the plinth under it (8.9), and inside the 20-stud column
-- pitch so neighbours never touch side to side. Picked by eye in a Play session: 8
-- left the rate and kg unreadable from where you normally stand on the pad.
local CARD_STUDS = 11
local LIFT = 0.6 -- studs between the nuke's top and the card's bottom edge
-- CAMERA-to-adornee, as the old card had it: every stand on your own pad from anywhere
-- on it, and short of the next plot on the ring.
local MAX_DISTANCE = 120

local POP = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local GLINT_SWEEP = TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false, 0.9)
local RAINBOW_ROCK = TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

type Card = {
	display: BasePart,
	gui: BillboardGui,
	canvas: Frame, -- L.width x L.height design px, fitted to the gui by its own UIScale
	root: Frame?,
	shimmer: Tween?,
	key: string?, -- what is drawn (item + when it went up); a change pops the card
	primed: boolean, -- false until the first draw, so a stand already full on join never pops
	queued: boolean,
	crateEnds: number?, -- server time the crating lock lifts; nil = no lock drawn
	lockLabel: TextLabel?,
	conn: RBXScriptConnection?,
}

local cards: { [BasePart]: Card } = {}

-- ── Formatting ────────────────────────────────────────────────────────────────

--- "$2.00/s", "$48.6/s", "$236/s", "$6.1K/s", "$118K/s", "$1.2M/s" -- the cash
--- badge's ladder, carried on so a six-figure rate stops printing "$118.0K/s".
local function formatRate(perSecond: number): string
	if perSecond >= 1_000_000_000 then
		return string.format("$%.1fB/s", perSecond / 1_000_000_000)
	elseif perSecond >= 1_000_000 then
		return string.format("$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 100_000 then
		return string.format("$%.0fK/s", perSecond / 1000)
	elseif perSecond >= 1000 then
		return string.format("$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("$%.1f/s", perSecond)
	end
	return string.format("$%.2f/s", perSecond)
end

--- Same ladder as IndexController and the wash reveal: two sig figs under a kilo.
local function formatWeight(kg: number): string
	if kg < 1 then
		return string.format("%.2g kg", kg)
	end
	return string.format("%d kg", math.floor(kg + 0.5))
end

local function formatClock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local ORDINAL = { "1st", "2nd", "3rd" }

--- "2nd copy · 40% pay" for a duplicate, nil for the first of its kind.
local function copyLine(copy: number): string?
	if copy <= 1 then
		return nil
	end
	local ladder = Tuning.EXHIBIT_DUPLICATE_YIELD
	local share = ladder[math.min(copy, #ladder)]
	return `{ORDINAL[copy] or `{copy}th`} copy \u{00B7} {math.floor(share * 100 + 0.5)}% pay`
end

--- "PREWAR SEALED" from "PrewarSealed", nil for "None".
local function modifierLabel(modifier: string?): string?
	if modifier == nil or modifier == "" or modifier == "None" then
		return nil
	end
	return string.upper((string.gsub(modifier, "(%l)(%u)", "%1 %2")))
end

local function textWidth(text: string, size: number, font: Enum.Font): number
	return TextService:GetTextSize(text, size, font, Vector2.new(2000, 200)).X
end

local function lighten(color: Color3, t: number): Color3
	return color:Lerp(WHITE, t)
end

local function darken(color: Color3, t: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), t)
end

local function sequence(hexes: { string }): ColorSequence
	local points = {}
	for i, hex in hexes do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#hexes - 1), Color3.fromHex(hex)))
	end
	return ColorSequence.new(points)
end

-- ── Building blocks ───────────────────────────────────────────────────────────

type ShapeOpts = {
	radius: UDim?,
	stroke: number?,
	z: number?,
	shadow: number?, -- drop of a hard INK copy behind it; nil = none
	centre: boolean?, -- x/y are the centre, and Rotation turns it about that centre
	rotation: number?,
}

--- One flat, INK-outlined cartoon shape, optionally with its hard shadow. The shadow
--- carries the same stroke so its outline matches the shape it sits under, whatever
--- side of the edge Roblox draws a stroke on.
local function shape(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, opts: ShapeOpts?): Frame
	local o: ShapeOpts = opts or {}
	local z = o.z or 3
	local stroke = o.stroke or 0
	local anchor = if o.centre then Vector2.new(0.5, 0.5) else Vector2.zero
	local function make(frameName: string, pos: Vector2, fill: Color3, zIndex: number): Frame
		local frame = UIKit.panel(parent, {
			name = frameName,
			position = UDim2.fromOffset(pos.X, pos.Y),
			size = UDim2.fromOffset(w, h),
			anchorPoint = anchor,
			color = fill,
			transparency = 0,
			cornerRadius = o.radius or UDim.new(0, 0),
			strokeColor = INK,
			strokeThickness = stroke,
			zIndex = zIndex,
		})
		frame.Rotation = o.rotation or 0
		return frame
	end
	if o.shadow then
		make(name .. "Shadow", Vector2.new(x, y + o.shadow), INK, z - 1)
	end
	return make(name, Vector2.new(x, y), color, z)
end

--- A line of text in the card's voice: FredokaOne (unless told otherwise) with a
--- rounded INK outline. `stroke = 0` for none.
local function text(
	parent: Instance,
	name: string,
	value: string,
	size: number,
	color: Color3,
	stroke: number,
	props: { position: UDim2?, size: UDim2?, font: Enum.Font?, xAlign: Enum.TextXAlignment?, z: number? }?
): TextLabel
	local p = props or {}
	local label = UIKit.label(parent, {
		name = name,
		text = value,
		font = p.font or STYLE.font,
		textSize = size,
		color = color,
		position = p.position,
		size = p.size or UDim2.fromScale(1, 1),
		xAlign = p.xAlign or Enum.TextXAlignment.Center,
		outline = stroke > 0,
		strokeTransparency = 1,
		shadow = false,
		zIndex = p.z or 4,
	})
	local outline = label:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = INK
		outline.Thickness = stroke
	end
	return label
end

--- One notched ribbon tail, drawn in horizontal strips so the V cut is real
--- transparency, not a patch painted over the world. `mirror` puts the notch on the
--- right; the end tucked under the ribbon carries no outline, nothing can see it.
local function tail(parent: Instance, name: string, x: number, y: number, fill: Color3, mirror: boolean)
	local root = Instance.new("Frame")
	root.Name = name
	root.Position = UDim2.fromOffset(x, y)
	root.Size = UDim2.fromOffset(L.tailW, L.tailH)
	root.BackgroundTransparency = 1
	root.ZIndex = 1
	root.Parent = parent

	local half = L.tailH / 2
	-- The outline's width measured along a row, so the diagonal edge reads as thick as
	-- the straight ones.
	local slant = L.stroke * math.sqrt(1 + (L.notch / half) ^ 2)
	local function notchAt(rowMid: number): number
		return L.notch * (1 - math.abs(rowMid - half) / half)
	end
	local function strip(top: number, height: number, inset: number, color: Color3, z: number)
		local row = Instance.new("Frame")
		row.BorderSizePixel = 0
		row.BackgroundColor3 = color
		row.Position = UDim2.fromOffset(if mirror then 0 else inset, top)
		row.Size = UDim2.fromOffset(L.tailW - inset, height)
		row.ZIndex = z
		row.Parent = root
	end

	local top = 0
	while top < L.tailH do
		local height = math.min(L.strip, L.tailH - top)
		strip(top, height, notchAt(top + height / 2), INK, 1)
		top += height
	end
	top = L.stroke
	while top < L.tailH - L.stroke do
		local height = math.min(L.strip, L.tailH - L.stroke - top)
		strip(top, height, notchAt(top + height / 2) + slant, fill, 2)
		top += height
	end
end

--- CashController's coin, shrunk to sit inside a 28px pill.
local function coin(parent: Instance, x: number, y: number)
	local body = shape(parent, "Coin", x, y, L.coin, L.coin, STYLE.coin, { radius = UDim.new(0.5, 0), stroke = 2, z = 5 })
	local inset = 3
	local face = shape(body, "Face", inset, inset, L.coin - inset * 2, L.coin - inset * 2, STYLE.coinFace, {
		radius = UDim.new(0.5, 0),
		stroke = 1.5,
		z = 6,
	})
	local rim = face:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = STYLE.coinRim
	end
	text(body, "Mark", "$", 15, STYLE.coinMark, 0, {
		font = STYLE.nameFont,
		position = UDim2.fromOffset(0, 2),
		z = 7,
	})
end

--- A little padlock: a rounded shackle with a hole punched in the chip's colour, and a
--- body over its feet.
local function padlock(parent: Instance, x: number, y: number, holeColor: Color3)
	local shackle = shape(parent, "Shackle", x + 1.5, y, 8, 9, WHITE, { radius = UDim.new(0.5, 0), z = 5 })
	shape(shackle, "Hole", 2.4, 2.4, 3.2, 6, holeColor, { radius = UDim.new(0.5, 0), z = 6 })
	shape(parent, "Body", x, y + 5, 11, 8, WHITE, { radius = UDim.new(0, 2), z = 7 })
end

local function sticker(parent: Instance, name: string, label: string, color: Color3, cx: number, cy: number, tilt: number)
	local w = textWidth(label, L.stickerSize, STYLE.font) + 14
	-- Keep a long one ("PREWAR SEALED") on the card rather than hanging off its edge.
	cx = math.clamp(cx, w / 2 + 2, L.width - w / 2 - 2)
	local chip = shape(parent, name, cx, cy, w, L.stickerH, color, {
		radius = UDim.new(0, 6),
		stroke = 2.5,
		z = 7,
		shadow = 3,
		centre = true,
		rotation = tilt,
	})
	text(chip, "Label", label, L.stickerSize, INK, 0, { z = 8 })
end

--- Fill the rarity word, and start its shimmer if the tier has one.
local function paintRarity(label: TextLabel, rarityId: string, color: Color3): Tween?
	local style = SHIMMER[rarityId]
	if style == nil then
		label.TextColor3 = color
		return nil
	end

	label.TextColor3 = WHITE
	local gradient = Instance.new("UIGradient")
	gradient.Parent = label
	if style.kind == "fade" then
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(lighten(color, 0.45), color)
		return nil
	elseif style.kind == "rainbow" then
		gradient.Color = sequence(RAINBOW)
		gradient.Offset = Vector2.new(-0.35, 0)
		local tween = TweenService:Create(gradient, RAINBOW_ROCK, { Offset = Vector2.new(0.35, 0) })
		tween:Play()
		return tween
	end

	local glint = style.glint or WHITE
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color),
		ColorSequenceKeypoint.new(0.4, color),
		ColorSequenceKeypoint.new(0.5, glint),
		ColorSequenceKeypoint.new(0.6, color),
		ColorSequenceKeypoint.new(1, color),
	})
	gradient.Offset = Vector2.new(-1, 0)
	local tween = TweenService:Create(gradient, GLINT_SWEEP, { Offset = Vector2.new(1, 0) })
	tween:Play()
	return tween
end

-- ── One card ──────────────────────────────────────────────────────────────────

local function clear(card: Card)
	if card.shimmer then
		card.shimmer:Cancel()
		card.shimmer = nil
	end
	if card.root then
		card.root:Destroy()
		card.root = nil
	end
	card.lockLabel = nil
	card.crateEnds = nil
end

local function draw(card: Card)
	local display = card.display
	local itemId = display:GetAttribute(A.item)
	local wasPrimed = card.primed
	card.primed = true

	local def: any = nil
	if type(itemId) == "string" and itemId ~= "" then
		local ok, found = pcall(Items.get, itemId)
		def = if ok then found else nil
	end
	if def == nil then
		clear(card)
		card.key = nil
		card.gui.Enabled = false
		return
	end

	local rarityId = display:GetAttribute(A.rarity)
	local rarity = Rarity.DEFS[rarityId] or Rarity.DEFS.Common
	rarityId = if Rarity.DEFS[rarityId] then rarityId else "Common"
	local color = rarity.color
	local rate = display:GetAttribute(A.rate)
	local copy = display:GetAttribute(A.copy)
	local payload = display:GetAttribute(A.payload)
	local placedAt = display:GetAttribute(A.placedAt)
	local owner = display:GetAttribute(A.owner)
	local top = display:GetAttribute(A.top)

	local key = `{itemId}@{placedAt}`
	local pop = wasPrimed and key ~= card.key
	card.key = key

	clear(card)

	-- The crating lock only means something to whoever can press Take.
	local crateEnds: number? = nil
	if owner == Players.LocalPlayer.UserId and type(placedAt) == "number" and placedAt > 0 then
		local ends = placedAt + Tuning.EXHIBIT_UNCRATE_SECONDS
		if ends > Workspace:GetServerTimeNow() then
			crateEnds = ends
		end
	end
	local copyText = if type(copy) == "number" then copyLine(copy) else nil
	local hasFooter = copyText ~= nil or crateEnds ~= nil

	local root = Instance.new("Frame")
	root.Name = "Card"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.fromScale(0.5, 1)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Name = "Pop"
	scale.Parent = root

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, if hasFooter then 0 else FOOTLESS_DROP)
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundTransparency = 1
	body.Parent = root

	local mid = L.width / 2

	-- Rarity word and tier stars.
	local rarityLabel = text(body, "Rarity", string.upper(rarityId), L.raritySize, color, 2.3, {
		position = UDim2.fromOffset(0, L.rarityY),
		size = UDim2.new(1, 0, 0, L.rarityH),
	})
	card.shimmer = paintRarity(rarityLabel, rarityId, color)

	local tiers = #Rarity.ORDER
	local starsLeft = mid - tiers * L.starW / 2
	for i = 1, tiers do
		local on = i <= rarity.order
		local slot = {
			position = UDim2.fromOffset(starsLeft + (i - 1) * L.starW, L.starsY),
			size = UDim2.fromOffset(L.starW, L.starH),
		}
		if on then
			text(body, `Star{i}`, "\u{2605}", L.starOn, STYLE.star, 1.8, slot)
		else
			text(body, `Star{i}`, "\u{2605}", L.starOff, WHITE, 0, slot).TextTransparency = 0.55
		end
	end

	-- The ribbon, sized to its name, with its tails tucked behind each end.
	local nameSize = L.nameSize
	local bannerW = math.clamp(textWidth(def.name, nameSize, STYLE.nameFont) + L.bannerPad, L.bannerMin, L.bannerMax)
	while nameSize > L.nameMin and textWidth(def.name, nameSize, STYLE.nameFont) > bannerW - 24 do
		nameSize -= 1
	end
	local bannerX = mid - bannerW / 2
	local isRainbow = rarityId == "Anomaly"
	local tailFill = if isRainbow then Color3.fromHex("C89BFA") else darken(color, 0.3)
	tail(body, "TailLeft", bannerX - L.tailTuck, L.bannerY + L.tailDrop, tailFill, false)
	tail(body, "TailRight", bannerX + bannerW + L.tailTuck - L.tailW, L.bannerY + L.tailDrop, tailFill, true)

	local banner = shape(body, "Ribbon", bannerX, L.bannerY, bannerW, L.bannerH, WHITE, {
		radius = UDim.new(0, 6),
		stroke = 3.5,
		z = 3,
		shadow = L.shadow,
	})
	local fill = Instance.new("UIGradient")
	if isRainbow then
		fill.Color = sequence(RIBBON_RAINBOW)
	else
		fill.Rotation = 90
		fill.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, lighten(color, 0.3)),
			ColorSequenceKeypoint.new(0.6, color),
			ColorSequenceKeypoint.new(1, darken(color, 0.1)),
		})
	end
	fill.Parent = banner
	text(banner, "ItemName", def.name, nameSize, WHITE, 3, {
		font = STYLE.nameFont,
		position = UDim2.fromOffset(0, L.nameDrop),
	})

	-- Stickers ride the tails' outer ends, tilted away from the name.
	local stickerY = L.bannerY + 3
	local callout = if type(payload) == "number" then Payload.calloutFor(payload) else nil
	if callout then
		local label = string.format("%s \u{00D7}%.1f", callout, payload)
		local tint = CALLOUT_COLOR[callout] or STYLE.star
		sticker(body, "SizeSticker", label, tint, bannerX - L.tailTuck + 18, stickerY, -L.stickerTilt)
	end
	local modifier = display:GetAttribute(A.modifier)
	local modText = modifierLabel(if type(modifier) == "string" then modifier else nil)
	if modText then
		local tint = MODIFIER_COLOR[modifier] or STYLE.foot
		sticker(body, "ModifierSticker", modText, tint, bannerX + bannerW + L.tailTuck - 18, stickerY, L.stickerTilt)
	end

	-- The pill row: what it pays, and what it weighs.
	local rateText = formatRate(if type(rate) == "number" then rate else 0)
	local rateW = textWidth(rateText, L.rateSize, STYLE.font)
	local coinLeft = 3
	local rateLeft = coinLeft + L.coin + 6
	local ratePillW = rateLeft + rateW + 12
	-- The rate pill and the SizeSticker above it both already ride Payload.forUid
	-- (ExhibitService.entryYieldPerSecond: "a heavy/big-rolled piece pays more per
	-- second AND sells for more, off the same two factors"). The weight pill used to
	-- read the catalogue's intrinsic def.weight straight, so a card could show a
	-- "GIGA x2.3" sticker over a kg number that never moved -- fold the same roll in
	-- so what the card says it weighs matches what it says it pays and how big the
	-- sticker says it rolled.
	local kgText = formatWeight(Weight.shownKg(def.weight, if type(payload) == "number" then payload else 1))
	local kgW = textWidth(kgText, L.kgSize, STYLE.font) + 22
	local rowLeft = mid - (ratePillW + L.pillGap + kgW) / 2

	local ratePill = shape(body, "RatePill", rowLeft, L.pillY, ratePillW, L.pillH, STYLE.pill, {
		radius = UDim.new(0.5, 0),
		stroke = L.stroke,
		shadow = L.shadow,
	})
	coin(ratePill, coinLeft, (L.pillH - L.coin) / 2)
	text(ratePill, "Rate", rateText, L.rateSize, WHITE, 2.5, {
		position = UDim2.fromOffset(rateLeft, 0),
		size = UDim2.new(0, rateW + 4, 1, 0),
		xAlign = Enum.TextXAlignment.Left,
	})

	local kgPill = shape(body, "WeightPill", rowLeft + ratePillW + L.pillGap, L.pillY, kgW, L.pillH, STYLE.kg, {
		radius = UDim.new(0.5, 0),
		stroke = L.stroke,
		shadow = L.shadow,
	})
	text(kgPill, "Weight", kgText, L.kgSize, WHITE, 2)

	-- The footer: a duplicate's share, and the owner's crating lock.
	if hasFooter then
		local copyW = if copyText then textWidth(copyText, L.footSize, STYLE.font) else 0
		local clockText = if crateEnds then formatClock(crateEnds - Workspace:GetServerTimeNow()) else ""
		-- Measured on a fixed-width stand-in so the chip doesn't twitch as digits change.
		local chipW = if crateEnds then 20 + textWidth("0:00", L.footSize, STYLE.font) + 7 else 0
		local gap = if copyText and crateEnds then L.footGap else 0
		local left = mid - (copyW + gap + chipW) / 2
		if copyText then
			text(body, "CopyShare", copyText, L.footSize, STYLE.foot, 2, {
				position = UDim2.fromOffset(left, L.footY),
				size = UDim2.fromOffset(copyW + 4, L.footH),
				xAlign = Enum.TextXAlignment.Left,
			})
		end
		if crateEnds then
			local chip = shape(body, "CrateLock", left + copyW + gap, L.footY + 1, chipW, 18, STYLE.chip, {
				radius = UDim.new(0, 6),
				stroke = 2.5,
				shadow = 3,
			})
			padlock(chip, 5, 3, STYLE.chip)
			card.lockLabel = text(chip, "Clock", clockText, L.footSize, WHITE, 1.5, {
				position = UDim2.fromOffset(20, 0),
				size = UDim2.new(1, -22, 1, 0),
				xAlign = Enum.TextXAlignment.Left,
			})
			card.crateEnds = crateEnds
		end
	end

	root.Parent = card.canvas
	card.root = root
	card.gui.StudsOffsetWorldSpace = Vector3.new(0, (if type(top) == "number" then top else 1) + LIFT, 0)
	card.gui.Enabled = true

	if pop then
		scale.Scale = 0.25
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
	end
end

--- Redraw once per frame at most: the server writes a stand's attributes one at a
--- time, and they land together.
local function queue(card: Card)
	if card.queued then
		return
	end
	card.queued = true
	task.defer(function()
		card.queued = false
		if cards[card.display] == card then
			draw(card)
		end
	end)
end

local function track(instance: Instance)
	if not instance:IsA("BasePart") or cards[instance] then
		return
	end
	local display = instance :: BasePart

	local gui = Instance.new("BillboardGui")
	gui.Name = "StandCard"
	gui.Adornee = display
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0 -- same wash-to-white bug NameTagController documents
	gui.MaxDistance = MAX_DISTANCE
	gui.ClipsDescendants = false
	-- Lift the gui by half its own height, so its BOTTOM edge sits on the anchor point
	-- above the nuke rather than its centre.
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	-- Scale components of a BillboardGui's Size are studs: a fixed size in the world.
	gui.Size = UDim2.fromScale(CARD_STUDS, CARD_STUDS * L.height / L.width)

	-- The design-px layout, blown up or shrunk to exactly cover the gui. AbsoluteSize
	-- is what the gui measures on screen right now, so this follows every zoom.
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.AnchorPoint = Vector2.new(0.5, 1)
	canvas.Position = UDim2.fromScale(0.5, 1)
	canvas.Size = UDim2.fromOffset(L.width, L.height)
	canvas.BackgroundTransparency = 1
	canvas.Parent = gui
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = canvas
	local function refit()
		fit.Scale = gui.AbsoluteSize.X / L.width
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()
	gui.Parent = display

	local card: Card = {
		display = display,
		gui = gui,
		canvas = canvas,
		root = nil,
		shimmer = nil,
		key = nil,
		primed = false,
		queued = false,
		crateEnds = nil,
		lockLabel = nil,
		conn = nil,
	}
	cards[display] = card
	card.conn = display.AttributeChanged:Connect(function()
		queue(card)
	end)
	draw(card)
end

local function untrack(instance: Instance)
	local card = cards[instance :: BasePart]
	if card == nil then
		return
	end
	cards[instance :: BasePart] = nil
	if card.conn then
		card.conn:Disconnect()
	end
	clear(card)
	card.gui:Destroy()
end

function StandCards.start()
	for _, instance in CollectionService:GetTagged(StandCard.TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(StandCard.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(StandCard.TAG):Connect(untrack)

	-- The crating clocks. A few times a second is plenty for a seconds readout; when
	-- one runs out its card redraws without the footer.
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < 0.2 then
			return
		end
		since = 0
		local now = Workspace:GetServerTimeNow()
		for _, card in cards do
			local ends = card.crateEnds
			if ends then
				if ends <= now then
					card.crateEnds = nil
					queue(card)
				elseif card.lockLabel then
					card.lockLabel.Text = formatClock(ends - now)
				end
			end
		end
	end)
end

return StandCards
