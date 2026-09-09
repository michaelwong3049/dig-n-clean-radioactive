--!strict
-- Asset-free destination logos. Transparent cutouts retain the card's background.
local WarpIcons = {}

function WarpIcons.build(parent: GuiObject, destination: string): { Frame }
	local root = Instance.new("Frame")
	root.Name = "DestinationIcon"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(40, 40)
	root.BackgroundTransparency = 1
	root.ZIndex = 7
	root.Parent = parent

	local pieces: { Frame } = {}
	local function rectangle(x: number, y: number, width: number, height: number, rounded: boolean?): Frame
		local part = Instance.new("Frame")
		part.Position = UDim2.fromScale(x / 100, y / 100)
		part.Size = UDim2.fromScale(width / 100, height / 100)
		part.BackgroundColor3 = Color3.fromRGB(232, 242, 255)
		part.BorderSizePixel = 0
		part.ZIndex = 7
		part.Parent = root
		if rounded then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = part
		end
		table.insert(pieces, part)
		return part
	end

	local function line(x1: number, y1: number, x2: number, y2: number, thickness: number)
		local dx, dy = x2 - x1, y2 - y1
		local part = rectangle((x1 + x2) / 2, (y1 + y2) / 2, math.sqrt(dx * dx + dy * dy), thickness, true)
		part.AnchorPoint = Vector2.new(0.5, 0.5)
		part.Rotation = math.deg(math.atan2(dy, dx))
	end

	if destination == "base" then
		-- Circular border, pitched roof, chimney and a solid house with an open door.
		for step = 0, 47 do
			local a, b = step * math.pi / 24, (step + 1) * math.pi / 24
			line(50 + 47 * math.cos(a), 50 + 47 * math.sin(a), 50 + 47 * math.cos(b), 50 + 47 * math.sin(b), 5)
		end
		rectangle(29, 30, 7, 14)
		line(22, 50, 50, 26, 3)
		line(50, 26, 78, 50, 3)
		-- Horizontal strips fill the triangular gable without masking the background.
		for y = 33, 50 do
			local halfWidth = (y - 32) * 1.12
			rectangle(50 - halfWidth, y, halfWidth * 2, 1.05)
		end
		rectangle(28, 51, 44, 11)
		rectangle(28, 62, 18, 14)
		rectangle(55, 62, 17, 14)
	else
		-- Shop outline, open doorway/window and a striped, scalloped awning.
		line(16, 44, 16, 94, 6)
		line(84, 44, 84, 94, 6)
		line(16, 94, 84, 94, 6)
		line(30, 94, 30, 61, 6)
		line(30, 61, 47, 61, 6)
		line(47, 61, 47, 94, 6)
		line(60, 62, 73, 62, 5)
		line(73, 62, 73, 77, 5)
		line(73, 77, 60, 77, 5)
		line(60, 77, 60, 62, 5)
		line(19, 8, 81, 8, 6)
		line(19, 8, 9, 36, 6)
		line(81, 8, 91, 36, 6)
		line(9, 36, 91, 36, 6)
		line(37, 8, 30, 36, 5)
		line(56, 8, 56, 36, 5)
		line(70, 8, 75, 36, 5)
		local edges = { 9, 30, 56, 75, 91 }
		for index = 1, #edges - 1 do
			local left, right = edges[index], edges[index + 1]
			local center, radius = (left + right) / 2, (right - left) / 2
			for step = 0, 7 do
				local a, b = step * math.pi / 8, (step + 1) * math.pi / 8
				line(center + radius * math.cos(a), 36 + 10 * math.sin(a), center + radius * math.cos(b), 36 + 10 * math.sin(b), 5)
			end
		end
	end
	return pieces
end

return WarpIcons
