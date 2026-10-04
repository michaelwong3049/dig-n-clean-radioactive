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

return Studded
