--!strict
--[[
	LockerTutorial.luau — the Quarantine Locker's first-visit walkthrough.

	ON REQUEST: "a slight tutorial when you enter the quarantine... make everything
	else black transparent besides the screen and explain it". So it is a spotlight: the
	whole screen goes a see-through black EXCEPT a cut-out over the part of the locker
	panel being explained, ringed in amber, with a small card beside it saying what that
	part is. Three quick steps (the locker, the tubes, the button), NEXT / SKIP,
	and a click anywhere also moves on.

	THE CUT-OUT IS FOUR BLACK FRAMES, not a frame with a hole (Roblox has no masking):
	one above the target, one below, and one either side between them. They follow the
	target's screen rect every frame, eased, so the hole glides from one step to the
	next and keeps up if the panel refits to a resized window.

	A STEP CAN RING A THING IN THE WORLD, not only a panel: `world` (a Model or a part)
	is projected to the screen every frame, so the treadmill's walkthrough
	(TreadmillController) can ring the machine itself and follow the camera.

	ONCE PER PLAYER. The server says whether it is still owed (`lockerTutorial` on the
	locker's StationState, from `data.tutorialsSeen`); finishing or skipping reports it
	seen. Walking away mid-way just closes it, unmarked, so it comes back next visit.

	The layer sits over every HUD (DisplayOrder 115, above the Index/Shop panels at 110)
	so nothing outside the spotlight is clickable while it is up, and under the wash
	view (200), which cannot be open at the same time anyway.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local UIKit = require(script.Parent.UIKit)

local LockerTutorial = {}

local SKIN = {
	card = Color3.fromHex("22272C"),
	edge = Color3.fromHex("343B42"),
	amber = Color3.fromHex("F2A93B"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("C4C9CE"),
	muted = Color3.fromHex("8A9197"),
	button = Color3.fromHex("2A3036"),
	next = Color3.fromHex("3FBF5A"),
	ink = Color3.fromHex("1A1A1A"),
	headline = Enum.Font.LuckiestGuy,
	label = Enum.Font.FredokaOne,
}

--- How dark the rest of the screen goes: 0 is solid black.
local DIM = 0.3
--- Air between the target and the edge of the cut-out, in screen px.
local HOLE_PAD = 8
--- Gap between the cut-out and the card, and the card's margin from the screen edge.
local CARD_GAP = 14
local CARD_W = 340
local CARD_PAD = 14
local BODY_SIZE = 16
--- How fast the hole eases onto its target (per second, exponential).
local EASE = 14

export type Step = {
	-- One of the two: a GuiObject to ring, or a Model/BasePart in the world.
	target: GuiObject?,
	world: Instance?,
	title: string,
	body: string,
}

--- The card's buttons: NEXT (or GOT IT on the last step) and SKIP.
local function button(parent: Instance, name: string, text: string, color: Color3, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.LayoutOrder = order
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.fromOffset(0, 34)
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Font = SKIN.headline
	b.TextSize = 18
	b.TextColor3 = SKIN.text
	b.Text = text
	b.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = b
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = SKIN.ink
	stroke.Thickness = 2
	stroke.Parent = b
	return b
end

--- Run the walkthrough over `steps`. `onDone(finished)` fires once: true when the player
--- reached the end or pressed SKIP (either way, they have seen it), false when it was
--- cut short by `stop` (the panel closed under it).
function LockerTutorial.run(steps: { Step }, onDone: (finished: boolean) -> ()): { stop: () -> () }
	local gui = Instance.new("ScreenGui")
	gui.Name = "LockerTutorial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- A full-screen layer: no safe-area inset, or the dim stops short of the notch.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 115
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Everything that is not the hole. A full-screen catcher under the dim swallows
	-- clicks meant for the HUD (and moves the tutorial on).
	local catcher = Instance.new("TextButton")
	catcher.Name = "Catcher"
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.Parent = gui

	local shades: { Frame } = {}
	for index = 1, 4 do
		local shade = Instance.new("Frame")
		shade.Name = `Shade{index}`
		shade.BorderSizePixel = 0
		shade.BackgroundColor3 = Color3.new(0, 0, 0)
		shade.BackgroundTransparency = 1
		shade.Parent = gui
		shades[index] = shade
		TweenService:Create(shade, TweenInfo.new(0.35), { BackgroundTransparency = DIM }):Play()
	end

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Parent = gui
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0, 16)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = SKIN.amber
	ringStroke.Thickness = 3
	ringStroke.Parent = ring
	TweenService:Create(
		ringStroke,
		TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.6 }
	):Play()

	-- The card lives on a canvas so it scales with the rest of the HUD.
	local canvas = UIKit.canvas(gui)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromOffset(CARD_W, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = SKIN.card
	card.BorderSizePixel = 0
	card.Parent = canvas
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 14)
	cardCorner.Parent = card
	local cardStroke = Instance.new("UIStroke")
	cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cardStroke.Color = SKIN.amber
	cardStroke.Thickness = 2
	cardStroke.Parent = card
	local cardPad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(cardPad :: any)[side] = UDim.new(0, CARD_PAD)
	end
	cardPad.Parent = card
	local cardList = Instance.new("UIListLayout")
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.Padding = UDim.new(0, 6)
	cardList.Parent = card

	local counter = UIKit.label(card, {
		name = "Counter",
		size = UDim2.new(1, 0, 0, 14),
		font = SKIN.label,
		textSize = 13,
		color = SKIN.amber,
		outline = false,
		shadow = false,
	})
	counter.LayoutOrder = 1
	local title = UIKit.label(card, {
		name = "Title",
		size = UDim2.new(1, 0, 0, 28),
		font = SKIN.headline,
		textSize = 26,
		color = SKIN.text,
	})
	title.LayoutOrder = 2
	local body = UIKit.label(card, {
		name = "Body",
		size = UDim2.fromScale(1, 0),
		font = SKIN.label,
		textSize = BODY_SIZE,
		color = SKIN.dim,
		wrapped = true,
		outline = false,
		shadow = false,
	})
	body.LayoutOrder = 3

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.LayoutOrder = 4
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundTransparency = 1
	row.Parent = card
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rowList.VerticalAlignment = Enum.VerticalAlignment.Bottom
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Padding = UDim.new(0, 8)
	rowList.Parent = row
	local skip = button(row, "Skip", "SKIP", SKIN.button, 1)
	skip.TextColor3 = SKIN.muted
	local nextButton = button(row, "Next", "NEXT", SKIN.next, 2)

	-- ── Stepping ────────────────────────────────────────────────────────
	local index = 0
	local done = false
	local hole: Rect? = nil
	local connection: RBXScriptConnection? = nil

	local function finish(finished: boolean)
		if done then
			return
		end
		done = true
		if connection then
			connection:Disconnect()
		end
		gui:Destroy()
		onDone(finished)
	end

	local function show(nextIndex: number)
		if nextIndex > #steps then
			finish(true)
			return
		end
		index = nextIndex
		local step = steps[index]
		counter.Text = `TUTORIAL  ·  {index}/{#steps}`
		title.Text = step.title
		body.Text = step.body
		-- Measured, not AutomaticSize: a wrapped label's automatic height does not grow
		-- when its text gets longer, and the last step's line was being cut off.
		local bounds = TextService:GetTextSize(step.body, BODY_SIZE, SKIN.label, Vector2.new(CARD_W - 2 * CARD_PAD, 1000))
		body.Size = UDim2.new(1, 0, 0, bounds.Y + 4)
		nextButton.Text = if index == #steps then "GOT IT" else "NEXT"
		skip.Visible = index < #steps
	end

	--- Where the target is right now, relative to this gui, padded. AbsolutePosition is
	--- in one space for every ScreenGui (below the topbar), so subtracting this layer's
	--- own origin puts it in this layer's pixels whatever the target's gui insets are.
	--- A world thing's screen rect: its bounding box's eight corners through the camera,
	--- clipped to the screen. Viewport pixels ARE this layer's pixels (IgnoreGuiInset).
	--- nil while any corner is behind the camera, which keeps the last good hole.
	local function worldRect(world: Instance): Rect?
		local camera = workspace.CurrentCamera
		local cf: CFrame, size: Vector3
		if world:IsA("Model") then
			cf, size = world:GetBoundingBox()
		elseif world:IsA("BasePart") then
			cf, size = world.CFrame, world.Size
		else
			return nil
		end
		if camera == nil or world.Parent == nil then
			return nil
		end
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local corner = (cf * CFrame.new(size.X * sx, size.Y * sy, size.Z * sz)).Position
					local point = camera:WorldToViewportPoint(corner)
					if point.Z <= 0 then
						return nil
					end
					x0, y0 = math.min(x0, point.X), math.min(y0, point.Y)
					x1, y1 = math.max(x1, point.X), math.max(y1, point.Y)
				end
			end
		end
		local screen = catcher.AbsoluteSize
		x0, y0 = math.max(x0, HOLE_PAD), math.max(y0, HOLE_PAD)
		x1, y1 = math.min(x1, screen.X - HOLE_PAD), math.min(y1, screen.Y - HOLE_PAD)
		if x1 - x0 < 4 or y1 - y0 < 4 then
			return nil
		end
		return Rect.new(Vector2.new(x0 - HOLE_PAD, y0 - HOLE_PAD), Vector2.new(x1 + HOLE_PAD, y1 + HOLE_PAD))
	end

	local function targetRect(): Rect?
		local step = steps[index]
		if step and step.world then
			return worldRect(step.world)
		end
		local target = step and step.target
		if target == nil or not target.Visible or target.AbsoluteSize.X <= 0 then
			return nil
		end
		local origin = catcher.AbsolutePosition
		local lo = target.AbsolutePosition - origin - Vector2.one * HOLE_PAD
		local hi = lo + target.AbsoluteSize + Vector2.one * 2 * HOLE_PAD
		return Rect.new(lo, hi)
	end

	local function layout(dt: number)
		local want = targetRect()
		if want == nil then
			return
		end
		local current = hole
		if current == nil then
			current = want
		else
			local t = 1 - math.exp(-EASE * dt)
			current = Rect.new(current.Min:Lerp(want.Min, t), current.Max:Lerp(want.Max, t))
		end
		hole = current
		local rect = current :: Rect
		local screen = catcher.AbsoluteSize
		-- Whole pixels, or the shades' shared edges render a hairline seam of daylight.
		local x0, y0 = math.floor(rect.Min.X), math.floor(rect.Min.Y)
		local x1, y1 = math.ceil(rect.Max.X), math.ceil(rect.Max.Y)

		-- Above, below, then left and right of the hole between those two.
		shades[1].Position = UDim2.fromOffset(0, 0)
		shades[1].Size = UDim2.fromOffset(screen.X, math.max(0, y0))
		shades[2].Position = UDim2.fromOffset(0, y1)
		shades[2].Size = UDim2.fromOffset(screen.X, math.max(0, screen.Y - y1))
		shades[3].Position = UDim2.fromOffset(0, y0)
		shades[3].Size = UDim2.fromOffset(math.max(0, x0), y1 - y0)
		shades[4].Position = UDim2.fromOffset(x1, y0)
		shades[4].Size = UDim2.fromOffset(math.max(0, screen.X - x1), y1 - y0)
		ring.Position = UDim2.fromOffset(x0, y0)
		ring.Size = UDim2.fromOffset(x1 - x0, y1 - y0)

		-- The card: below the hole if it fits, else above, else overlapping its foot.
		-- Worked in screen px, written in the canvas's design px.
		local scale = UIKit.canvasScale(canvas)
		local size = card.AbsoluteSize
		local top: number
		if y1 + CARD_GAP + size.Y <= screen.Y - CARD_GAP then
			top = y1 + CARD_GAP
		elseif y0 - CARD_GAP - size.Y >= CARD_GAP then
			top = y0 - CARD_GAP - size.Y
		else
			top = y1 - size.Y - CARD_GAP
		end
		local left = math.clamp((x0 + x1) / 2 - size.X / 2, CARD_GAP, math.max(CARD_GAP, screen.X - size.X - CARD_GAP))
		card.Position = UDim2.fromOffset(left / scale, top / scale)
	end

	nextButton.MouseButton1Click:Connect(function()
		show(index + 1)
	end)
	skip.MouseButton1Click:Connect(function()
		finish(true)
	end)
	catcher.MouseButton1Click:Connect(function()
		show(index + 1)
	end)

	show(1)
	layout(0)
	connection = RunService.RenderStepped:Connect(layout)

	return {
		stop = function()
			finish(false)
		end,
	}
end

return LockerTutorial
