--!strict
--[[
	StarLine — draws a star rating (Rarity.stars, 1..10 in half steps) inside an
	existing TextLabel, with a REAL half star: no game font has a half-star glyph, so a
	half is a dim full star with a lit one clipped to its left half.

	The label keeps its place, size, font, outline and alignment. StarLine empties its
	Text and lays out clones of it in a row inside: an optional rich-text part before,
	the stars, an optional trail of extra stars in their own colour (Merge Reactor
	stars), then an optional rich-text part after. Calling `set` again redraws the row
	only when something changed.
]]

local TextService = game:GetService("TextService")

local StarLine = {}

local GLYPH = "\u{2605}"
-- The dim star a half sits on, and how see-through it is.
local DIM = Color3.new(1, 1, 1)
local DIM_TRANSPARENCY = 0.6

export type Opts = {
	color: Color3?, -- the lit stars; the label's own TextColor3 when left out
	before: string?, -- rich text drawn before the stars
	after: string?, -- rich text drawn after the stars (and the trail)
	trail: number?, -- whole extra stars after the rating, in `trailColor`
	trailColor: Color3?,
}

type State = { template: TextLabel, key: string }

-- Strong table cleaned on Destroying: a weak table would lose Instance keys.
local states: { [TextLabel]: State } = {}

local function stateOf(label: TextLabel): State
	local state = states[label]
	if state then
		return state
	end
	local template = label:Clone()
	for _, child in template:GetChildren() do
		if not child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	template.Name = "Part"
	template.Text = ""
	template.Position = UDim2.new()
	template.AnchorPoint = Vector2.zero
	template.Size = UDim2.fromScale(0, 1)
	template.AutomaticSize = Enum.AutomaticSize.X
	template.TextTruncate = Enum.TextTruncate.None
	template.TextWrapped = false
	template.TextScaled = false
	template.BackgroundTransparency = 1
	template.Visible = true
	state = { template = template, key = "" }
	states[label] = state
	label.Destroying:Connect(function()
		states[label] = nil
	end)
	return state
end

local function part(state: State, parent: Instance, order: number, text: string, rich: boolean): TextLabel
	local label = state.template:Clone()
	label.RichText = rich
	label.Text = text
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function star(state: State, parent: Instance, order: number, color: Color3, width: number): TextLabel
	local label = part(state, parent, order, GLYPH, false)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.new(0, width, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextColor3 = color
	return label
end

--- Draw `rating` stars into `label`. 0 or less draws no stars (the parts still show).
function StarLine.set(label: TextLabel, rating: number, opts: Opts?)
	local o = opts or {}
	local color = o.color or label.TextColor3
	local trail = math.max(0, math.floor(o.trail or 0))
	local trailColor = o.trailColor or color
	local key = table.concat({
		tostring(rating),
		color:ToHex(),
		o.before or "",
		o.after or "",
		tostring(trail),
		trailColor:ToHex(),
	}, "|")
	local state = stateOf(label)
	local row = label:FindFirstChild("StarLine")
	if state.key == key and row then
		return
	end
	state.key = key
	label.Text = ""

	if row then
		row:Destroy()
	end
	local frame = Instance.new("Frame")
	frame.Name = "StarLine"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.ClipsDescendants = true
	frame.ZIndex = label.ZIndex
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = if label.TextXAlignment == Enum.TextXAlignment.Center
		then Enum.HorizontalAlignment.Center
		elseif label.TextXAlignment == Enum.TextXAlignment.Right then Enum.HorizontalAlignment.Right
		else Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, math.floor(label.TextSize * 0.4))
	layout.Parent = frame

	local width = TextService:GetTextSize(GLYPH, label.TextSize, label.Font, Vector2.new(1000, 1000)).X
	local order = 0
	local function group(): Frame
		order += 1
		local g = Instance.new("Frame")
		g.Name = "Stars"
		g.BackgroundTransparency = 1
		g.Size = UDim2.fromScale(0, 1)
		g.AutomaticSize = Enum.AutomaticSize.X
		g.LayoutOrder = order
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Parent = g
		g.Parent = frame
		return g
	end

	if o.before and o.before ~= "" then
		order += 1
		part(state, frame, order, o.before, true)
	end
	if rating > 0 then
		local stars = group()
		local whole = math.floor(rating)
		for i = 1, whole do
			star(state, stars, i, color, width)
		end
		if rating - whole >= 0.5 then
			local slot = Instance.new("Frame")
			slot.Name = "HalfStar"
			slot.BackgroundTransparency = 1
			slot.Size = UDim2.new(0, width, 1, 0)
			slot.LayoutOrder = whole + 1
			slot.Parent = stars
			local back = star(state, slot, 0, DIM, width)
			back.TextTransparency = DIM_TRANSPARENCY
			local stroke = back:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = math.max(stroke.Transparency, DIM_TRANSPARENCY)
			end
			local clip = Instance.new("Frame")
			clip.Name = "Clip"
			clip.BackgroundTransparency = 1
			clip.ClipsDescendants = true
			clip.Size = UDim2.new(0.5, 0, 1, 0)
			clip.Parent = slot
			star(state, clip, 0, color, width)
		end
	end
	if trail > 0 then
		local stars = group()
		for i = 1, trail do
			star(state, stars, i, trailColor, width)
		end
	end
	if o.after and o.after ~= "" then
		order += 1
		part(state, frame, order, o.after, true)
	end
	frame.Parent = label
end

return StarLine
