-- Small HUD illustrations. Most are built from GUI shapes; the Index and Shop tile
-- icons are real pictures (see Artwork.IMAGE).
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

-- THE TILE PICTURES. Free white silhouettes from the Creator Store, not GUI shapes.
-- White on purpose: ImageColor3 multiplies, so the caller tints the picture to the
-- icon colour and tweens it to white on hover, the same change the shape-built icons
-- made. The see-through cuts in a picture (the book's title plate and page edge) show
-- the tile's own fill, so they follow the hover fill with no tween of their own.
--
-- These are IMAGE ids, which is what an ImageLabel needs, NOT the store listing's
-- decal id (the number in its URL). To swap a picture, load the listing's decal on
-- the server (`InsertService:LoadAsset(decalId)`) and copy its Decal.Texture here.
Artwork.IMAGE = {
	-- "Book Icon" by AtomicSlumber, store decal 6867518950.
	book = "rbxassetid://6867518941",
	-- "Shopping Cart Icon" by EgizianoEG, store decal 11385395257.
	cart = "rbxassetid://11385395241",
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
