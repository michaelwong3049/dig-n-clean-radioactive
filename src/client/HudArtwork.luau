-- Small HUD illustrations built from GUI shapes, so no uploaded assets are needed.
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
	dollar.ZIndex = 7
	dollar.Parent = icon
	local band = shape(icon, "GoldBand", 36, -2, 15, 48, Color3.fromRGB(255, 199, 37), 8)
	Artwork.outline(band, 2)
	shape(band, "Highlight", 2, 2, 4, 43, Color3.fromRGB(255, 237, 95), 9)
end

-- The index book's box, in design pixels. IndexController centres it in the top
-- of its tile.
Artwork.BOOK_SIZE = Vector2.new(42, 48)

export type Book = { icon: Frame, paper: { Frame }, cut: UIStroke, plate: Frame }

--- The index book: a flat, upright cover with a dark title plate on it, and the
--- page block standing proud of it to the right and below. Drawn into a BOOK_SIZE box
--- at the icon's own origin; the caller positions `icon`.
---
--- `paper` is the white of both faces. `gap` is the colour of the cover's outline —
--- the cut that separates it from the pages — and of the title plate: pass the
--- button's own fill so the cut reads as a gap rather than a drawn line, then tween
--- `cut` / `plate` with that fill (and `paper` with the icon colour) on hover.
function Artwork.book(parent: Instance, paper: Color3, gap: Color3): Book
	local icon = shape(parent, "BookIcon", 0, 0, Artwork.BOOK_SIZE.X, Artwork.BOOK_SIZE.Y, Color3.new(), 5)
	icon.BackgroundTransparency = 1
	local pages = shape(icon, "Pages", 11, 5, 31, 43, paper, 6, 5)
	local cover = shape(icon, "Cover", 0, 0, 31, 43, paper, 7, 5)
	local cut = Artwork.outline(cover, 3)
	cut.Color = gap
	local plate = shape(cover, "TitlePlate", 7, 9, 17, 10, gap, 8, 2)
	return { icon = icon, paper = { pages, cover }, cut = cut, plate = plate }
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
