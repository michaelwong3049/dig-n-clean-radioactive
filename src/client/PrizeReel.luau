--!strict
--[[
	PrizeReel.luau — a horizontal strip of prize cards that slides past a marker, slows
	down and stops on the prize (option 1 of the Slag Furnace roll mockups, 2026-10-06).
	The Slag Furnace's panel (client/FurnacePanel) and the nuke-crate opening
	(Controllers/CrateController) both roll on it.

	EVERY CARD IS ITS RARITY'S COLOUR UNDER THE L-STUD PATTERN (Studded.pattern), on
	request, so a Legendary flashing past reads as gold before its name can be read.
	An Anomaly card walks Rarity's spectrum instead of sitting white.

	ART IS A PICTURE (`image`) OR A MODEL (`item`, drawn by ItemArt). A model costs a
	ViewportFrame and a clone of a nuke that can be hundreds of parts, so only the cards
	that will be on screen while the reel is SLOW get one: the stretch around the
	prize, and the first few at rest. The rest whizz past as colour and a name, which
	is all anyone can read at that speed anyway. The models are built one a frame,
	the prize first, so opening never builds them all in one hitch.

	A NUKE'S MODEL WAITS FOR ITS MESHES. A ViewportFrame does not redraw when a mesh
	finishes downloading after it was drawn, so a nuke painted early stays blank for
	good. Each spin asks for its nukes' templates and preloads their meshes, and a
	card only gets its model once every mesh is in (it shows its colour and name
	until then, and the queue keeps going after the reel lands).

	The motion is the crate brew's quartic ease-out, from a few cards in to the prize,
	landing a little off-centre on it like a real case reel.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rarity = require(ReplicatedStorage.Shared.Config.Rarity)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local ItemModels = require(ReplicatedStorage.Shared.ItemModels)

local Studded = require(script.Parent.Studded)
local ItemArt = require(script.Parent.ItemArt)

local PrizeReel = {}

export type Entry = {
	name: string,
	-- A Rarity name; the card's colour.
	tier: string?,
	-- Picture art, or a model (an ItemArt description: a washed nuke, or a crate).
	image: string?,
	item: any?,
	-- A short line over the name ("x3", "$1.2M").
	caption: string?,
}

export type Props = {
	size: UDim2, -- the window
	-- Roughly how wide the window is, px, for how many cards show at rest.
	widthHint: number?,
	cardSize: Vector2,
	gap: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	zIndex: number?,
	-- The backdrop colour the window's edges fade into; nil = no fade.
	fade: Color3?,
	-- The marker's colour.
	marker: Color3?,
	-- Model art on the cards showing at rest too (default true). The crate reel says
	-- no: those whizz off at once, and every model is a nuke's worth of parts.
	artAtStart: boolean?,
}

export type Callbacks = {
	onTick: ((entry: Entry, index: number) -> ())?,
	onLand: (() -> ())?,
}

export type Reel = {
	frame: Frame,
	spin: (entries: { Entry }, land: number, seconds: number, callbacks: Callbacks?) -> (),
	clear: () -> (),
	-- Jump a running spin straight to its landing; false when nothing is spinning.
	skip: () -> boolean,
	winner: () -> Frame?,
}

local INK = Studded.INK
local NAME_BAND = Color3.new(0, 0, 0)
local WIN_STROKE = Color3.fromHex("FFE45A")
--- Cards started this far in, so the strip opens already full.
local START_AT = 3
--- How far off centre the prize may stop, in cards.
local JITTER = 0.3
--- How much the prize card grows when it lands.
local WIN_SCALE = 1.08
--- Model art for this many cards either side of the prize (the slow part of the reel).
local ART_BEFORE = 6
local ART_AFTER = 3

--- How often a waiting card looks at its meshes again (s).
local RECHECK = 0.25
--- The longest a spin's mesh preload waits for a template to arrive (s).
local TEMPLATE_WAIT = 5

--- Item ids whose every mesh and texture has downloaded. Only ever grows.
local loadedIds: { [string]: boolean } = {}

local function templateOf(itemId: string): Instance?
	local folder = Players.LocalPlayer.PlayerGui:FindFirstChild(ItemModels.CLIENT_CACHE)
	return if folder then folder:FindFirstChild(itemId) else nil
end

--- The nuke an entry draws, or nil for a picture or a crate (those need no wait).
local function nukeOf(entry: Entry): string?
	local item = entry.item
	if type(item) ~= "table" or not item.identified or type(item.itemId) ~= "string" or not Items.has(item.itemId) then
		return nil
	end
	return item.itemId
end

--- Whether a nuke's template is here and every mesh in it has downloaded.
local function meshesIn(itemId: string): boolean
	if loadedIds[itemId] then
		return true
	end
	local template = templateOf(itemId)
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

--- Ask for these nukes' templates and pull their meshes down.
local function warm(ids: { string })
	if #ids == 0 then
		return
	end
	ItemModels.request(ids)
	for _, itemId in ids do
		task.spawn(function()
			if ItemModels.await(itemId, TEMPLATE_WAIT) then
				local template = templateOf(itemId)
				if template then
					pcall(ContentProvider.PreloadAsync, ContentProvider, { template })
				end
			end
		end)
	end
end

local function tierColour(tier: string?): Color3
	local def = if tier then Rarity.DEFS[tier] else nil
	return if def then def.color else Color3.fromHex("9AA0A6")
end

local function spectrum(): ColorSequence
	local stops = Rarity.ANOMALY_SPECTRUM
	local keys = {}
	for index, colour in stops do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / #stops, colour))
	end
	table.insert(keys, ColorSequenceKeypoint.new(1, stops[1]))
	return ColorSequence.new(keys)
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, name: string, size: number, stroke: number, z: number): TextLabel
	local text = Studded.text(parent, name, size, stroke)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextWrapped = true
	text.ZIndex = z
	return text
end

type Card = {
	frame: Frame,
	art: Frame,
	stroke: UIStroke,
	scale: UIScale,
	gradient: UIGradient?,
	entry: Entry,
	viewport: ViewportFrame?,
}

function PrizeReel.new(parent: Instance, props: Props): Reel
	local z = props.zIndex or 1
	local cardW, cardH = props.cardSize.X, props.cardSize.Y
	local gap = props.gap or 8
	local step = cardW + gap
	local width = props.widthHint or 600

	local root = Instance.new("Frame")
	root.Name = "PrizeReel"
	root.BackgroundTransparency = 1
	root.Size = props.size
	root.Position = props.position or UDim2.new()
	root.AnchorPoint = props.anchorPoint or Vector2.zero
	root.ClipsDescendants = true
	root.ZIndex = z
	root.Parent = parent

	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.AnchorPoint = Vector2.new(0, 0.5)
	strip.Position = UDim2.fromScale(0, 0.5)
	strip.Size = UDim2.fromOffset(0, cardH)
	strip.ZIndex = z
	strip.Parent = root

	-- The edges fade into the backdrop, so cards slide in and out of nothing.
	if props.fade then
		for _, side in { 0, 1 } do
			local fade = Instance.new("Frame")
			fade.Name = if side == 0 then "FadeLeft" else "FadeRight"
			fade.BorderSizePixel = 0
			fade.BackgroundColor3 = props.fade
			fade.AnchorPoint = Vector2.new(side, 0)
			fade.Position = UDim2.fromScale(side, 0)
			fade.Size = UDim2.fromScale(0.16, 1)
			fade.ZIndex = z + 6
			fade.Parent = root
			local gradient = Instance.new("UIGradient")
			gradient.Transparency = NumberSequence.new(if side == 0 then 0 else 1, if side == 0 then 1 else 0)
			gradient.Parent = fade
		end
	end

	-- The marker: a bar down the middle with a point at each end (a square turned 45
	-- degrees and half clipped by the window).
	local markerColour = props.marker or Color3.fromHex("FFC24A")
	local bar = Instance.new("Frame")
	bar.Name = "Marker"
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = markerColour
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0)
	bar.Size = UDim2.new(0, 4, 1, 0)
	bar.ZIndex = z + 8
	bar.Parent = root
	local barInk = Instance.new("UIStroke")
	barInk.Color = INK
	barInk.Thickness = 1.5
	barInk.Parent = bar
	for _, y in { 0, 1 } do
		local point = Instance.new("Frame")
		point.Name = "Point"
		point.BorderSizePixel = 0
		point.BackgroundColor3 = markerColour
		point.AnchorPoint = Vector2.new(0.5, 0.5)
		point.Position = UDim2.fromScale(0.5, y)
		point.Size = UDim2.fromOffset(20, 20)
		point.Rotation = 45
		point.ZIndex = z + 8
		point.Parent = root
		local ink = Instance.new("UIStroke")
		ink.Color = INK
		ink.Thickness = 2
		ink.Parent = point
	end

	--- The bar is hidden while a prize sits under it, so the card's name reads whole;
	--- the two points stay.
	local function showBar(on: boolean)
		bar.BackgroundTransparency = if on then 0 else 1
		barInk.Transparency = if on then 0 else 1
	end

	local cards: { Card } = {}
	local connection: RBXScriptConnection? = nil
	local artConnection: RBXScriptConnection? = nil
	local token = 0
	local landedIndex: number? = nil
	--- Set by skip(): the running spin lands on its next frame.
	local rushed = false

	local function makeCard(entry: Entry, index: number): Card
		local cz = z + 1
		local frame = Instance.new("Frame")
		frame.Name = `Card{index}`
		frame.BorderSizePixel = 0
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset((index - 1) * step + cardW / 2, cardH / 2)
		frame.Size = UDim2.fromOffset(cardW, cardH)
		frame.ZIndex = cz
		frame.Parent = strip
		corner(frame, 10)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = INK
		stroke.Thickness = 3
		stroke.Parent = frame
		local scale = Instance.new("UIScale")
		scale.Parent = frame

		local gradient: UIGradient? = nil
		if entry.tier == "Anomaly" then
			frame.BackgroundColor3 = Color3.new(1, 1, 1)
			local made = Instance.new("UIGradient")
			made.Color = spectrum()
			made.Rotation = 20
			made.Parent = frame
			gradient = made
		else
			frame.BackgroundColor3 = tierColour(entry.tier)
		end
		Studded.pattern(frame, {
			tile = 18,
			radius = 10,
			glow = false,
			studTransparency = 0.3,
			bandTransparency = 0.72,
			zIndex = cz,
		})

		local art = Instance.new("Frame")
		art.Name = "Art"
		art.BackgroundTransparency = 1
		art.Position = UDim2.fromOffset(6, 6)
		art.Size = UDim2.new(1, -12, 1, -44)
		art.ZIndex = cz + 1
		art.Parent = frame
		if entry.image then
			local picture = Instance.new("ImageLabel")
			picture.Name = "Picture"
			picture.BackgroundTransparency = 1
			picture.Size = UDim2.fromScale(1, 1)
			picture.Image = entry.image
			picture.ScaleType = Enum.ScaleType.Fit
			picture.ZIndex = cz + 1
			picture.Parent = art
		end

		-- A dark band under the name, so white text holds on the palest rarity.
		local band = Instance.new("Frame")
		band.Name = "NameBand"
		band.BorderSizePixel = 0
		band.BackgroundColor3 = NAME_BAND
		band.BackgroundTransparency = 0.45
		band.AnchorPoint = Vector2.new(0, 1)
		band.Position = UDim2.fromScale(0, 1)
		band.Size = UDim2.new(1, 0, 0, 36)
		band.ZIndex = cz + 1
		band.Parent = frame
		corner(band, 10)

		local name = label(band, "ItemName", 12, 1.5, cz + 2)
		name.Size = UDim2.new(1, -8, 1, -4)
		name.Position = UDim2.fromOffset(4, 2)
		name.TextScaled = true
		name.Text = entry.name
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = 14
		cap.MinTextSize = 8
		cap.Parent = name

		if entry.caption then
			local caption = label(frame, "Caption", 14, 2, cz + 2)
			caption.AnchorPoint = Vector2.new(0.5, 1)
			caption.Position = UDim2.new(0.5, 0, 1, -38)
			caption.Size = UDim2.new(1, -8, 0, 16)
			caption.Text = entry.caption
		end

		return { frame = frame, art = art, stroke = stroke, scale = scale, gradient = gradient, entry = entry }
	end

	local function giveArt(card: Card)
		if card.viewport or card.entry.item == nil then
			return
		end
		local viewport = ItemArt.newViewport(card.art)
		viewport.ZIndex = card.art.ZIndex
		card.viewport = viewport
		ItemArt.paint(viewport, card.entry.item, (cardW - 12) / (cardH - 44))
	end

	local function clear()
		token += 1
		if connection then
			connection:Disconnect()
			connection = nil
		end
		if artConnection then
			artConnection:Disconnect()
			artConnection = nil
		end
		for _, card in cards do
			card.frame:Destroy()
		end
		table.clear(cards)
		landedIndex = nil
		rushed = false
	end

	local function place(position: number)
		strip.Position = UDim2.new(0.5, -((position - 1) * step + cardW / 2), 0.5, 0)
	end

	local function spin(given: { Entry }, land: number, seconds: number, callbacks: Callbacks?)
		clear()
		showBar(true)
		local my = token
		land = math.clamp(land, 1, #given)
		-- Enough cards past the prize to fill the window's far side at rest: copies of
		-- the reel's own filler, so it is cosmetic and honest to the odds alike.
		local entries = table.clone(given)
		local tail = math.ceil(width / step / 2) + 1
		while #entries < land + tail and land > 1 do
			table.insert(entries, given[math.random(1, land - 1)])
		end
		strip.Size = UDim2.fromOffset(#entries * step, cardH)
		for index, entry in entries do
			cards[index] = makeCard(entry, index)
		end
		-- Model art where the reel will be slow (prize first, then outward), and on the
		-- cards showing at rest, queued and built one a frame.
		local visible = math.ceil(width / step / 2) + 1
		local from = math.min(START_AT, land)
		local queue: { Card } = { cards[land] }
		for offset = 1, ART_BEFORE do
			if cards[land - offset] then
				table.insert(queue, cards[land - offset])
			end
			if offset <= ART_AFTER and cards[land + offset] then
				table.insert(queue, cards[land + offset])
			end
		end
		if props.artAtStart ~= false then
			for index = 1, math.min(#cards, from + visible) do
				table.insert(queue, 1, cards[index])
			end
		end
		local wanted: { string } = {}
		local asked: { [string]: boolean } = {}
		for _, card in queue do
			local itemId = nukeOf(card.entry)
			if itemId and not asked[itemId] then
				asked[itemId] = true
				table.insert(wanted, itemId)
			end
		end
		warm(wanted)

		-- One model a frame, the first card in the queue whose meshes are in. Runs on
		-- past the landing until the queue is empty or the next spin starts.
		local checkedAt = 0
		artConnection = RunService.Heartbeat:Connect(function()
			if token ~= my or #queue == 0 then
				if artConnection and token == my then
					artConnection:Disconnect()
					artConnection = nil
				end
				return
			end
			local now = os.clock()
			local recheck = now - checkedAt >= RECHECK
			for index, card in queue do
				local itemId = nukeOf(card.entry)
				if itemId == nil or loadedIds[itemId] or (recheck and meshesIn(itemId)) then
					table.remove(queue, index)
					giveArt(card)
					break
				end
			end
			if recheck then
				checkedAt = now
			end
		end)

		local target = land + (math.random() * 2 - 1) * JITTER
		local started = os.clock()
		local lastIndex = from
		local onTick = callbacks and callbacks.onTick
		local onLand = callbacks and callbacks.onLand
		place(from)
		connection = RunService.RenderStepped:Connect(function()
			if token ~= my then
				return
			end
			local t = if rushed then 1 else math.clamp((os.clock() - started) / math.max(seconds, 0.1), 0, 1)
			local position = from + (target - from) * (1 - (1 - t) ^ 4)
			place(position)

			local centred = math.clamp(math.floor(position + 0.5), 1, #cards)
			if centred ~= lastIndex then
				lastIndex = centred
				if onTick then
					onTick(entries[centred], centred)
				end
			end

			-- The Anomaly cards' spectrum keeps sliding.
			local shift = (os.clock() * 0.35) % 1
			for _, card in cards do
				if card.gradient then
					card.gradient.Offset = Vector2.new(shift * 2 - 1, 0)
				end
			end

			if t >= 1 then
				if connection then
					connection:Disconnect()
					connection = nil
				end
				landedIndex = land
				local winner = cards[land]
				winner.stroke.Color = WIN_STROKE
				winner.stroke.Thickness = 4
				winner.scale.Scale = 1
				showBar(false)
				local pop = TweenService:Create(
					winner.scale,
					TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = WIN_SCALE }
				)
				pop:Play()
				if onLand then
					onLand()
				end
			end
		end)
	end

	return {
		frame = root,
		spin = spin,
		clear = clear,
		skip = function(): boolean
			if connection == nil then
				return false
			end
			rushed = true
			return true
		end,
		winner = function(): Frame?
			return if landedIndex and cards[landedIndex] then cards[landedIndex].frame else nil
		end,
	}
end

return PrizeReel
