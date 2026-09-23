--!strict
--[[
	CloverArt.luau — a four-leaf clover drawn out of Frames, for the 2x-luck badge
	(LuckBoostController) and the Lucky Clover card in the Shop panel (ShopController).

	FRAMES, NOT AN IMAGE, for the same reason the rad panel's trefoil is Frames
	(HealthPanel): an uploaded icon is an asset the account has to own and moderation
	can take away, and a Frame drawing takes any colour the palette asks for.

	DRAWN IN THE HUD'S CARTOON VOICE (CashController's header): thick INK outlines and a
	hard black shadow dropped a few px, never a blur. A per-shape UIStroke would outline
	every overlap too -- a line through the middle of each leaf where its two lobes
	meet -- so each outline is a LAYER instead: the same shapes grown by the outline
	width in INK, with the fill laid on top. The shadow is the whole silhouette again,
	offset, under everything.

	ONE OUTLINE PER LEAF, STACKED LIKE STICKERS. The first draft outlined the four
	leaves as one silhouette, and at badge size the eight touching lobes merged into a
	purple flower; nobody would have called it a clover. Drawing each leaf's outline
	and fill in turn, one on top of the last, puts an ink seam between every pair of
	leaves -- the X down the middle is what makes it read as four hearts. (Picked from a
	four-way comparison in Studio; the leaves were narrowed at the same time.)

	GREEN AT x2, PURPLE AT x4 -- the user's call (2026-09-23). The first cut was violet
	everywhere, on PLAN §14's "green on the HUD means exposure" rule, and the user asked
	for a clover that looks like a clover, keeping purple for the stacked x4: purple is
	the Violet Aurora's colour, so x4 reads as "aurora plus clover". GREEN is a leafy
	mid-green, well clear of radiation's acid #4FD11A. `paint` recolours a clover that
	is already built, which is how the corner badge swaps between the two.

	Each leaf is a heart: two round lobes outboard and a square turned 45 degrees whose
	corner is the leaf's point, meeting the other three at the clover's centre.
]]

local CloverArt = {}

local INK = Color3.fromHex("1A1A1A")

export type Palette = {
	leaf: Color3,
	shade: Color3,
	shine: Color3,
	stem: Color3,
}

-- 2x: one boost running.
CloverArt.GREEN = {
	leaf = Color3.fromHex("5ED15A"),
	shade = Color3.fromHex("3A9E3F"),
	shine = Color3.fromHex("DDF8D2"),
	stem = Color3.fromHex("2E7D32"),
} :: Palette

-- 4x: the aurora and a clover stacked.
CloverArt.PURPLE = {
	leaf = Color3.fromHex("A46BFF"),
	shade = Color3.fromHex("7E45E6"),
	shine = Color3.fromHex("E6D6FF"),
	stem = Color3.fromHex("6A34C9"),
} :: Palette

CloverArt.PALETTE = CloverArt.GREEN

--- The palette for a luck multiplier: purple once it is past 2x, green otherwise.
function CloverArt.paletteFor(multiplier: number): Palette
	return if multiplier > 2 then CloverArt.PURPLE else CloverArt.GREEN
end

-- Fill shapes carry their palette key here so `paint` can find them; the INK outline
-- and shadow layers carry none and are never touched.
local ROLE = "CloverRole"

local ROUND = UDim.new(0.5, 0)

local function shape(
	parent: Instance,
	name: string,
	size: Vector2,
	center: Vector2,
	color: Color3,
	z: number,
	round: boolean,
	rotation: number?,
	role: string?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.Position = UDim2.new(0.5, center.X, 0.5, center.Y)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Rotation = rotation or 0
	frame.ZIndex = z
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = ROUND
		corner.Parent = frame
	end
	if role then
		frame:SetAttribute(ROLE, role)
	end
	frame.Parent = parent
	return frame
end

--- Rotate a screen-space offset clockwise by `degrees` (screen y points down).
local function turn(v: Vector2, degrees: number): Vector2
	local r = math.rad(degrees)
	local c, s = math.cos(r), math.sin(r)
	return Vector2.new(v.X * c - v.Y * s, v.X * s + v.Y * c)
end

-- The leaf's geometry, in leaf units: lobes at (+-LOBE_X, -LOBE_Y) of LOBE_D across,
-- the diamond POINT_SIDE square centred POINT_Y out from the clover's centre.
local LOBE_X = 0.22
local LOBE_Y = 0.70
local LOBE_D = 0.5
local POINT_SIDE = 0.5
local POINT_Y = 0.37

--- One heart-shaped leaf pointing `angle` degrees clockwise from straight up, in leaf
--- units `u` (the leaf's own box), grown by `grow` px on every edge. `tag` marks it
--- as a fill layer (point = shade, lobes = leaf) for `paint`.
local function leaf(parent: Instance, u: number, angle: number, grow: number, fill: Color3, lobeFill: Color3?, z: number, tag: boolean?)
	-- In the leaf's own frame (point toward +y, the clover's centre), measured from the
	-- point: the lobes outboard, the diamond between them and the centre.
	local lobeD = LOBE_D * u + 2 * grow
	local diamond = POINT_SIDE * u + 2 * grow
	local lobes = {
		Vector2.new(-LOBE_X * u, -LOBE_Y * u),
		Vector2.new(LOBE_X * u, -LOBE_Y * u),
	}
	local body = turn(Vector2.new(0, -POINT_Y * u), angle)
	shape(parent, "Point", Vector2.new(diamond, diamond), body, fill, z, false, 45 + angle, if tag then "shade" else nil)
	for i, lobe in lobes do
		shape(parent, `Lobe{i}`, Vector2.new(lobeD, lobeD), turn(lobe, angle), lobeFill or fill, z, true, nil, if tag then "leaf" else nil)
	end
end

local function stem(parent: Instance, u: number, grow: number, color: Color3, z: number, role: string?)
	-- Long enough to show past the leaves, down the gap between the east and south ones.
	local length = 1.2 * u + 2 * grow
	local width = 0.17 * u + 2 * grow
	shape(parent, "Stem", Vector2.new(width, length), turn(Vector2.new(0, 0.5 * length - grow), -45), color, z, true, -45, role)
end

--- Build a clover `size` px square, centred in a transparent frame of that size.
--- `outline` is the INK width, `shadow` the drop in px (0 = none). Returns the frame.
function CloverArt.build(parent: Instance, size: number, zIndex: number?, palette: Palette?, outline: number?, shadow: number?): Frame
	local colors = palette or CloverArt.PALETTE
	local z = zIndex or 1
	local line = outline or math.max(2, size * 0.045)
	local drop = shadow or math.max(2, size * 0.05)
	-- The whole clover spans ~1.95 leaf units each way from its centre.
	local u = size / 2.05

	local root = Instance.new("Frame")
	root.Name = "Clover"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(size, size)
	root.Parent = parent

	local angles = { 0, 90, 180, 270 }

	-- Shadow, then outline: the same silhouette twice, grown by the line width.
	if drop > 0 then
		local shadowLayer = Instance.new("Frame")
		shadowLayer.Name = "Shadow"
		shadowLayer.BackgroundTransparency = 1
		shadowLayer.Size = UDim2.fromScale(1, 1)
		shadowLayer.Position = UDim2.fromOffset(drop * 0.6, drop)
		shadowLayer.Parent = root
		stem(shadowLayer, u, line, INK, z)
		for _, angle in angles do
			leaf(shadowLayer, u, angle, line, INK, nil, z)
		end
	end
	stem(root, u, line, INK, z + 1)
	stem(root, u, 0, colors.stem, z + 2, "stem")

	-- Each leaf's outline, then its fill, each leaf over the last (the header's
	-- stickers). Lobes a shade lighter than the point, so each leaf reads as a heart.
	for i, angle in angles do
		leaf(root, u, angle, line, INK, nil, z + 1 + 2 * i)
		leaf(root, u, angle, 0, colors.shade, colors.leaf, z + 2 + 2 * i, true)
	end
	local top = z + 3 + 2 * #angles
	-- The knot where the four points meet, and a glint on each leaf's upper lobe.
	shape(root, "Heart", Vector2.new(0.3 * u, 0.3 * u), Vector2.zero, colors.shade, top, true, nil, "shade")
	for _, angle in angles do
		local glint = turn(Vector2.new(-(LOBE_X + 0.05) * u, -(LOBE_Y + 0.1) * u), angle)
		local spot = shape(root, "Glint", Vector2.new(0.2 * u, 0.13 * u), glint, colors.shine, top + 1, true, angle - 35, "shine")
		spot.BackgroundTransparency = 0.15
	end

	return root
end

--- Recolour a clover `build` made, in place. Outline and shadow stay INK.
function CloverArt.paint(clover: Instance, palette: Palette)
	for _, node in clover:GetDescendants() do
		local role = node:GetAttribute(ROLE)
		if node:IsA("Frame") and type(role) == "string" then
			node.BackgroundColor3 = (palette :: any)[role]
		end
	end
end

return CloverArt
