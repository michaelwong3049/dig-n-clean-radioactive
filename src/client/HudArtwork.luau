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
	-- The four right-edge tiles (HudTile). Drawn for this game as full-colour cartoon
	-- symbols with a dark outline, the left column's coin/heart family, and uploaded as
	-- 256px PNGs. Picked from a mockup round (I6, S7, N4, W2). The SVG sources are in
	-- tools/hud-icons: edit one, re-render it transparent at 256px, upload, and paste
	-- the new id here. Full colour, so a caller leaves ImageColor3 white.
	cards = "rbxassetid://79446288774542", -- Index: fanned rarity cards with a star
	chest = "rbxassetid://137692103278879", -- Shop: open treasure chest of coins
	mushroomCloud = "rbxassetid://107094805710382", -- Nukes: mushroom cloud
	portal = "rbxassetid://107949254570705", -- Warp: violet-to-cyan portal swirl
	-- The SPEED badge's disc (SpeedController): a glossy blue sneaker, same family and
	-- pipeline. tools/hud-icons/speed_shoe.svg.
	speedShoe = "rbxassetid://74013499057089",
	-- The glow behind each tile's symbol: a WHITE disc whose alpha eases from solid to
	-- nothing at the rim (smoothstep), so a caller tints it with ImageColor3.
	-- tools/hud-icons/glow.svg.
	glow = "rbxassetid://76655055685501",
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
