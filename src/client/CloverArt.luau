--!strict
--[[
	CloverArt.luau — the four-leaf clover picture for the 2x-luck badge
	(LuckBoostController), its banner, and the Lucky Clover card in the Shop panel
	(ShopController).

	A PICTURE NOW, NOT FRAMES. It used to be drawn out of rotated Frames so it could
	take any colour; the user swapped it (2026-10-02) for the clover drawn for the 2x
	Luck game pass card (tools/hud-icons/pass_luck.svg), so every luck surface in the
	game is the same clover. Two uploads cover the two colours it ever needs.

	GREEN AT x2, PURPLE AT x4 -- the user's call (2026-09-23). Purple is the Violet
	Aurora's colour, so x4 reads as "aurora plus clover". The purple upload is the same
	drawing recoloured (tools/hud-icons/luck_clover_purple.svg). `paint` swaps the
	picture on a clover that is already built, which is how the corner badge changes.

	The palettes keep their colours for the text and pills drawn next to the clover
	(the banner title is `shine`), so callers did not have to change.
]]

local CloverArt = {}

export type Palette = {
	image: string,
	leaf: Color3,
	shade: Color3,
	shine: Color3,
	stem: Color3,
}

-- 2x: one boost running. The 2x Luck pass card's own picture (Config/GamePasses).
CloverArt.GREEN = {
	image = "rbxassetid://75584960857266",
	leaf = Color3.fromHex("5ED15A"),
	shade = Color3.fromHex("3A9E3F"),
	shine = Color3.fromHex("DDF8D2"),
	stem = Color3.fromHex("2E7D32"),
} :: Palette

-- 4x: the aurora and a clover stacked.
CloverArt.PURPLE = {
	image = "rbxassetid://122647766157064",
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

--- Build a clover `size` px square in a transparent frame of that size. Returns the
--- frame. The picture carries its own ink outline, so there is nothing else to draw.
function CloverArt.build(parent: Instance, size: number, zIndex: number?, palette: Palette?): Frame
	local root = Instance.new("Frame")
	root.Name = "Clover"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(size, size)
	root.Parent = parent

	local picture = Instance.new("ImageLabel")
	picture.Name = "Picture"
	picture.BackgroundTransparency = 1
	picture.Size = UDim2.fromScale(1, 1)
	picture.ScaleType = Enum.ScaleType.Fit
	picture.Image = (palette or CloverArt.PALETTE).image
	picture.ZIndex = zIndex or 1
	picture.Parent = root

	return root
end

--- Swap a clover `build` made to `palette`'s picture, in place.
function CloverArt.paint(clover: Instance, palette: Palette)
	local picture = clover:FindFirstChild("Picture")
	if picture and picture:IsA("ImageLabel") then
		picture.Image = palette.image
	end
end

return CloverArt
