-- Small HUD illustrations. Most are built from GUI shapes; the right-edge tiles and
-- the warp bar use real pictures (see Artwork.IMAGE).
local Artwork = {}
local INK = Color3.fromRGB(8, 14, 5)

function Artwork.outline(parent: Instance, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

local function shape(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, z: number, radius: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 3)
	corner.Parent = frame
	return frame
end

function Artwork.cash(parent: Instance)
	local icon = shape(parent, "MoneyStack", 7, 12, 68, 40, Color3.new(), 5)
	icon.BackgroundTransparency = 1
	icon.Rotation = -12
	for layer = 3, 0, -1 do
		local bill = shape(icon, "Bill", 0, layer * 5, 65, 30, Color3.fromRGB(67, 186 + (3 - layer) * 18, 18), 5)
		Artwork.outline(bill, 2)
	end
	local inset = shape(icon, "PrintedBorder", 5, 4, 55, 21, Color3.fromRGB(132, 244, 39), 6)
	Artwork.outline(inset, 1.5)
	local dollar = Instance.new("TextLabel")
	dollar.Size = UDim2.fromOffset(30, 25)
	dollar.Position = UDim2.fromOffset(3, 0)
	dollar.BackgroundTransparency = 1
	dollar.Font = Enum.Font.GothamBlack
	dollar.Text = "$"
	dollar.TextSize = 24
	dollar.TextColor3 = Color3.fromRGB(24, 83, 8)
	dollar.TextStrokeTransparency = 1
	dollar.ZIndex = 7
	dollar.Parent = icon
	Artwork.outline(dollar, 2) -- every other shape in this icon already has one
	local band = shape(icon, "GoldBand", 36, -2, 15, 48, Color3.fromRGB(255, 199, 37), 8)
	Artwork.outline(band, 2)
	shape(band, "Highlight", 2, 2, 4, 43, Color3.fromRGB(255, 237, 95), 9)
end

-- THE PICTURES. These are IMAGE ids, which is what an ImageLabel needs, NOT a store
-- listing's decal id (the number in its URL). To swap in a store picture, load the
-- listing's decal on the server (`InsertService:LoadAsset(decalId)`) and copy its
-- Decal.Texture here.
Artwork.IMAGE = {
	-- The left-edge button grid (HudTile): glossy 3D cartoon pictures the user made with an
	-- AI image tool (2026-10-03), cut out of their white backgrounds and uploaded as 256px
	-- PNGs. Sources in tools/hud-icons/ai. Full colour, so a caller leaves ImageColor3 white.
	cards = "rbxassetid://116610662603362", -- Index: fanned cards, a white star on the gold one
	chest = "rbxassetid://84040096771363", -- Shop: pink shopping basket, blue handle
	nuke = "rbxassetid://111508823006778", -- Nukes: green finned bomb with a trefoil
	portal = "rbxassetid://75514448109874", -- Warp: stone ring round a blue-violet vortex
	detector = "rbxassetid://110438827801253", -- Gear: metal detector, red coil
	giftBox = "rbxassetid://107608600195476", -- Gifts: gold gift box, red ribbon and bow
	gift = "rbxassetid://131150228950941", -- Free Gifts fallback + Daily panel: pink gift box, gold bow (daily_gift.svg)
	-- The top-right corner row, same AI pipeline as the grid (2026-10-03, on request):
	-- the Daily tile's red-topped "31" calendar and the Settings button's glossy blue cog.
	-- tools/hud-icons/ai/daily_calendar.png, settings_gear.png.
	calendar = "rbxassetid://125293311526646",
	settingsGear = "rbxassetid://86077006685520",
	-- The Masteries bar (MasteriesController), above Shop: a gold star medal on a red and
	-- blue ribbon. tools/hud-icons/mastery_medal.svg.
	medal = "rbxassetid://139869106879830",
	-- The SPEED badge's disc (SpeedController): a glossy blue sneaker, same family and
	-- pipeline. tools/hud-icons/speed_shoe.svg.
	speedShoe = "rbxassetid://97884293509666",
	-- The pencil beside it that opens the walk-speed picker: a white edit mark (box +
	-- pencil) with an ink outline. tools/hud-icons/edit_pencil.svg.
	editPencil = "rbxassetid://78973083811767",
	-- The cash row's icon (CashController): a banded bundle of green notes in 3/4 view.
	-- tools/hud-icons/cash_bundle.svg.
	cashBundle = "rbxassetid://128764628759725",
	-- The Shop's CASH cards (ShopController), cheapest to dearest: one bundle, a stack,
	-- a stuffed money bag, an open vault. tools/hud-icons/shop_cash_1..4.svg, 512px.
	shopCash = {
		"rbxassetid://71413718562997",
		"rbxassetid://77284563341858",
		"rbxassetid://128765520321660",
		"rbxassetid://136943347154341",
	},
	-- White rays fading out from the centre, behind each cash card's art; a caller sets
	-- ImageTransparency. tools/hud-icons/shop_sunburst.svg.
	sunburst = "rbxassetid://113625396052479",
	-- The vitals bars' icons (HudController): a glossy red heart for health and a
	-- trefoil on a green disc for rads. tools/hud-icons/health_heart.svg, rads_trefoil.svg.
	healthHeart = "rbxassetid://80065249224141",
	radsTrefoil = "rbxassetid://99314438299822",
	-- The glow behind each tile's symbol: a WHITE disc whose alpha eases from solid to
	-- nothing at the rim (smoothstep), so a caller tints it with ImageColor3.
	-- tools/hud-icons/glow.svg.
	glow = "rbxassetid://76655055685501",
	-- One tile of the drifting pattern on the Shop and Index bars (HudTile): two WHITE
	-- trefoils, staggered, on clear, so a caller tints and fades it.
	-- tools/hud-icons/trefoil_tile.svg, 128px.
	trefoilTile = "rbxassetid://123229088705923",
	-- The warp bar's HOME and SHOPS portals (WarpController).
	-- "House Icon" by uR1St3nLe4hH4lt0n, store decal 124662272665879.
	house = "rbxassetid://82460327730975",
	-- "shop icon" by kqvest, store decal 18517062241.
	storefront = "rbxassetid://18517062196",
}

--- A picture icon: a square, transparent ImageLabel `size` design px on a side, with
--- `image` fitted inside and tinted `color`. The caller positions it.
function Artwork.picture(parent: Instance, name: string, image: string, size: number, color: Color3): ImageLabel
	local icon = Instance.new("ImageLabel")
	icon.Name = name
	icon.Size = UDim2.fromOffset(size, size)
	icon.BackgroundTransparency = 1
	icon.BorderSizePixel = 0
	icon.Image = image
	icon.ImageColor3 = color
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 6
	icon.Parent = parent
	return icon
end

--- A full-colour picture standing straight on the world, with a hard drop shadow: an
--- INK copy of the same image nudged `drop` design px down-right, under it. Both sit in
--- a transparent `size` box the caller positions. Returns the box and the picture.
function Artwork.droppedPicture(parent: Instance, name: string, image: string, size: number, drop: Vector2, zIndex: number): (Frame, ImageLabel)
	local box = Instance.new("Frame")
	box.Name = name
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.ZIndex = zIndex
	box.Parent = parent

	local shadow = Artwork.picture(box, "Shadow", image, size, Color3.new(0, 0, 0))
	shadow.Position = UDim2.fromOffset(drop.X, drop.Y)
	shadow.ImageTransparency = 0.45
	shadow.ZIndex = zIndex

	local picture = Artwork.picture(box, "Picture", image, size, Color3.new(1, 1, 1))
	picture.ZIndex = zIndex + 1
	return box, picture
end

--- A picture with a hard INK outline, for sitting on a busy coloured fill: eight INK
--- copies nudged `outline` design px out around a centred box `size` px square, and the
--- picture itself on top, tinted `color`. An ImageLabel has no stroke of its own; the
--- copies are that stroke. Returns the box (position it) and the top picture (tint it).
function Artwork.inkedPicture(
	parent: Instance,
	name: string,
	image: string,
	size: number,
	color: Color3,
	outline: number,
	zIndex: number
): (Frame, ImageLabel)
	local box = Instance.new("Frame")
	box.Name = name
	box.Size = UDim2.fromOffset(size, size)
	box.BackgroundTransparency = 1
	box.ZIndex = zIndex
	box.Parent = parent
	for step = 0, 7 do
		local angle = step * math.pi / 4
		local copy = Artwork.picture(box, "Outline", image, size, INK)
		copy.Position = UDim2.fromOffset(math.cos(angle) * outline, math.sin(angle) * outline)
		copy.ZIndex = zIndex
	end
	local face = Artwork.picture(box, "Face", image, size, color)
	face.ZIndex = zIndex + 1
	return box, face
end

function Artwork.studs(parent: GuiObject)
	local texture = shape(parent, "StudTexture", 5, 5, 1, 1, Color3.new(), 5)
	texture.Size = UDim2.new(1, -10, 1, -10)
	texture.BackgroundTransparency = 1
	texture.ClipsDescendants = true
	for row = 0, 3 do
		for column = 0, 11 do
			local stud = shape(texture, "Stud", column * 20 + 2, row * 20 + 2, 9, 9, Color3.fromRGB(92, 245, 255), 5)
			stud.BackgroundTransparency = 0.8
			local stroke = Artwork.outline(stud, 1)
			stroke.Color = Color3.fromRGB(0, 153, 193)
			stroke.Transparency = 0.75
		end
	end
end

return Artwork
