--!strict
--[[
	Studded.luau — the chunky studded-plastic UI look (2026-10-04, after a reference the
	user sent): solid colour plates with soft moulded studs, inked outlines, vertical
	gloss gradients, and a purple striped title bar. The shop panel (StationController)
	and the overhead name tag (NameTagController) both wear it.

	The studs and stripes are two uploaded tiles; their sources are art/ui/stud-tile.png
	and art/ui/stripe-tile.png. Both are soft white/black over transparency, so they
	tint whatever colour sits under them.
]]

local Studded = {}

Studded.STUDS = "rbxassetid://89675992974575"
Studded.STRIPES = "rbxassetid://120310774406938"
Studded.INK = Color3.fromHex("1A1A1A")

Studded.PURPLE = ColorSequence.new(Color3.fromHex("C77BFF"), Color3.fromHex("8C3FE6"))
Studded.LIME = ColorSequence.new(Color3.fromHex("D9F51C"), Color3.fromHex("33D23F"))
Studded.GOLD = ColorSequence.new(Color3.fromHex("FFE45A"), Color3.fromHex("FFAA14"))
Studded.RED = ColorSequence.new(Color3.fromHex("FF7A6B"), Color3.fromHex("E5281F"))

--- A tiled overlay (studs or stripes) filling `parent`, under its other children.
function Studded.tile(parent: GuiObject, image: string, tile: number, transparency: number?, radius: number?): ImageLabel
	local overlay = Instance.new("ImageLabel")
	overlay.Name = if image == Studded.STRIPES then "Stripes" else "Studs"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Image = image
	overlay.ImageTransparency = transparency or 0
	overlay.ScaleType = Enum.ScaleType.Tile
	overlay.TileSize = UDim2.fromOffset(tile, tile)
	overlay.ZIndex = parent.ZIndex
	overlay.Parent = parent
	if radius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, radius)
		corner.Parent = overlay
	end
	return overlay
end

--- Paint `frame` white under a vertical gradient, so the gradient IS its colour.
function Studded.fill(frame: GuiObject, colors: ColorSequence): UIGradient
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	local gradient = frame:FindFirstChild("Fill") :: UIGradient?
	if gradient == nil then
		local made = Instance.new("UIGradient")
		made.Name = "Fill"
		made.Rotation = 90
		made.Parent = frame
		gradient = made
	end
	(gradient :: UIGradient).Color = colors
	return gradient :: UIGradient
end

--- A rounded inked edge round `frame`'s box.
function Studded.edge(frame: GuiObject, radius: number, thickness: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
	local ink = Instance.new("UIStroke")
	ink.Color = Studded.INK
	ink.Thickness = thickness
	ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ink.Parent = frame
end

--- White Gotham Black text with the rounded ink outline every HUD label wears.
function Studded.text(parent: Instance, name: string, size: number, stroke: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	label.ZIndex = 3
	label.Parent = parent
	local ink = Instance.new("UIStroke")
	ink.Color = Studded.INK
	ink.Thickness = stroke
	ink.LineJoinMode = Enum.LineJoinMode.Round
	ink.Parent = label
	return label
end

-- ── The glossy L-stud pattern (2026-10-05, after a ChatGPT shop background the user
-- sent): moulded L-studs, two pale diagonal gloss bands and a soft glow, over a solid
-- colour. Built from layers rather than the picture itself, so it fits a wide panel,
-- a tall card or a thin title bar without stretching, in any colour. Sources:
-- art/ui/l-stud-tile.png and art/ui/soft-glow.png.
Studded.L_STUDS = "rbxassetid://115279443125797"
Studded.GLOW = "rbxassetid://84270973459774"

export type PatternProps = {
	tile: number?, -- L-stud tile size, px
	studTransparency: number?,
	-- Gloss bands, as fractions along the top-left -> bottom-right diagonal: a wide band
	-- from a to b, a thin one from c to d.
	bands: { number }?,
	bandTransparency: number?,
	glow: boolean?,
	glowTransparency: number?,
	radius: number?,
	zIndex: number?,
}

local EDGE = 0.002

--- The two gloss bands as one white overlay faded by a hard-stopped gradient.
local function bandSequence(b: { number }, alpha: number): NumberSequence
	local a1, a2, c1, c2 = b[1], b[2], b[3], b[4]
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(a1, 1),
		NumberSequenceKeypoint.new(a1 + EDGE, alpha),
		NumberSequenceKeypoint.new(a2, alpha),
		NumberSequenceKeypoint.new(a2 + EDGE, 1),
		NumberSequenceKeypoint.new(c1, 1),
		NumberSequenceKeypoint.new(c1 + EDGE, alpha + (1 - alpha) * 0.25),
		NumberSequenceKeypoint.new(c2, alpha + (1 - alpha) * 0.25),
		NumberSequenceKeypoint.new(c2 + EDGE, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

--- Lay the pattern over `parent`'s own background colour, under its other children.
--- Returns the holder, so a caller can hide it.
function Studded.pattern(parent: GuiObject, props: PatternProps?): Frame
	local p: PatternProps = props or {}
	local z = p.zIndex or parent.ZIndex
	local holder = Instance.new("Frame")
	holder.Name = "Pattern"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent

	local function rounded(gui: GuiObject)
		if p.radius then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, p.radius)
			corner.Parent = gui
		end
	end

	if p.glow ~= false then
		local glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.42, 0.36)
		glow.Size = UDim2.fromScale(1.1, 1.2)
		glow.BackgroundTransparency = 1
		glow.Image = Studded.GLOW
		glow.ImageTransparency = p.glowTransparency or 0.55
		glow.ZIndex = z
		glow.Parent = holder
	end

	local bands = Instance.new("Frame")
	bands.Name = "Bands"
	bands.Size = UDim2.fromScale(1, 1)
	bands.BackgroundColor3 = Color3.new(1, 1, 1)
	bands.BorderSizePixel = 0
	bands.ZIndex = z
	bands.Parent = holder
	rounded(bands)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 45
	fade.Transparency = bandSequence(p.bands or { 0.18, 0.45, 0.55, 0.62 }, p.bandTransparency or 0.6)
	fade.Parent = bands

	local studs = Instance.new("ImageLabel")
	studs.Name = "LStuds"
	studs.Size = UDim2.fromScale(1, 1)
	studs.BackgroundTransparency = 1
	studs.Image = Studded.L_STUDS
	studs.ImageTransparency = p.studTransparency or 0.45
	studs.ScaleType = Enum.ScaleType.Tile
	studs.TileSize = UDim2.fromOffset(p.tile or 28, p.tile or 28)
	studs.ZIndex = z
	studs.Parent = holder
	rounded(studs)

	return holder
end

return Studded
