--!strict
--[[
	CampWarpController.luau — the camp list the WARP portal opens.

	THE BUTTON is the WARP portal in the top bar, right of SELL (WarpController builds
	it and calls CampWarp.toggle); it used to be a tile in the left-edge grid, whose
	slot is the Potions tile's now. Like the bar, it is only up outside a stage.
	A red "!" sits on its corner (CampWarp.attachBadge) from the moment a camp is reached on foot (CampState's
	`unlocked`) until the panel is next opened, so a new warp does not go unnoticed.

	THE PANEL IS A TRAIL MAP (2026-10-05, mockup 3 of 4, on request): every camp
	(Config/Camps, in order), then one "???" for the camps still to come, as round
	badges along a dotted trail on a dark studded board. Each badge is the camp's
	little postcard (Config/Camps `card`) in a circle; a YOU ARE HERE pin marks the camp
	you stand in, a padlock one you have not walked to yet, and a green ring the one
	picked. Clicking a badge picks it. The bar under the board shows the picked camp --
	postcard, name, one line (`blurb`) on a patterned plate in its accent colour -- and
	the one button:
	  WARP    — go there (the Warp remote with the camp's key; WarpService decides the
	            CFrame, and Base Camp's key lands you on your plot, like HOME);
	  HERE    — you are standing in it;
	  LOCKED  — a site camp you have not reached on foot yet (CampState `reached`);
	  SOON    — the "???".
	Inside a stage, or downed, the button is off and a notice says to walk back:
	WarpService refuses a warp out of a field whatever the client shows, so this only
	says so up front. A camp that is not in this world at all (CampState `available`;
	a place saved before it was built) gets no badge, since there is nothing to land on.

	"HERE" is worked out on the client, from ExposureState's stageId and Camps.at on the
	character's position: no stage and no site camp means Base Camp, the same rule the
	server's CampService.campOf uses.

	Its look is the glossy L-stud family's (client/Studded): the shop's dark studded panel
	under the Nukes panel's navy patterned title bar, and the shop's big red X.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Camps = require(Shared.Config.Camps)

local UIKit = require(script.Parent.Parent.UIKit)
local HudTile = require(script.Parent.Parent.HudTile)
local Studded = require(script.Parent.Parent.Studded)

local CampWarp = {}

local PANEL = {
	-- The glossy L-stud look (2026-10-05, mockup 3 "trail map", on request): the shop's
	-- dark studded panel under the Nukes panel's navy patterned title bar.
	panel = Color3.fromHex("2B2F36"),
	board = Color3.fromHex("22262C"),
	header = ColorSequence.new(Color3.fromHex("2C3E6B"), Color3.fromHex("1C2848")),
	subtitle = Color3.fromHex("C9D3EA"),
	dim = Color3.fromHex("9AA3AD"),
	dot = Color3.fromHex("C9CDD2"),
	-- The info bar under the board, for the "???" camp (a real camp wears its accent).
	soonBar = Color3.fromHex("3D4452"),
	go = ColorSequence.new(Color3.fromHex("85FF01"), Color3.fromHex("3FFE01")),
	goHover = ColorSequence.new(Color3.fromHex("A4FF4A"), Color3.fromHex("66FF3A")),
	here = ColorSequence.new(Color3.fromHex("43474F"), Color3.fromHex("33363C")),
	hereText = Color3.fromHex("86F27A"),
	off = ColorSequence.new(Color3.fromHex("9AA3B0"), Color3.fromHex("7C8594")),
	soon = ColorSequence.new(Color3.fromHex("5A6272"), Color3.fromHex("454C5A")),
	offText = Color3.fromHex("E6EAF0"),
	selected = Color3.fromHex("85FF01"),
	pin = Color3.fromHex("FFD24A"),
	lock = Color3.fromHex("FFC24B"),
	close = Color3.fromHex("E5281F"),
	noticeFill = Color3.fromHex("3A2A10"),
	noticeEdge = Color3.fromHex("F59E0B"),
	noticeText = Color3.fromHex("FFD58A"),
	soonPicture = Color3.fromHex("3A404A"),
	soonMark = Color3.fromHex("8A93A0"),
	stall = Color3.fromHex("EEE4CF"),
	badge = Color3.fromHex("EF4444"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	headline = Enum.Font.GothamBlack,
	label = Enum.Font.GothamBlack,
}
local PANEL_W = 760
-- Sits this far above dead centre: a little higher than the true middle, on request.
local PANEL_LIFT = 30
local PAD = 18
local HEADER_H = 64
local GAP = 12
local NOTICE_H = 34
local BOARD_H = 270
-- The board's badges: discs this wide, this far in from the board's ends.
local DISC = 96
local DISC_MARGIN = 90
-- Down the board, badge by badge: the trail zigzags through these heights.
local DISC_Y = { 0.6, 0.42, 0.55, 0.38, 0.58, 0.44 }
-- The dotted trail: one dot every DOT_STEP px, bowing BOW px off the straight line.
local DOT = 9
local DOT_STEP = 22
local BOW = 46
local INFO_H = 92
local INFO_PICTURE_W, INFO_PICTURE_H = 120, 68
local BUTTON_W, BUTTON_H = 170, 54
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLICK_DEBOUNCE = 0.4
-- A locked camp's picture, greyed down.
local DIMMED = Color3.fromRGB(120, 120, 130)

local SUBTITLE = "Tap a camp on the trail, then warp. A camp unlocks once you've walked there."
local STAGE_NOTICE = "You can't warp out of a stage. Walk back to a camp first."

-- The "???" badge's key in `selected`.
local SOON_KEY = "?"

type Status = "go" | "here" | "locked" | "blocked" | "soon"
type Stop = { key: string, def: Camps.CampDef?, id: number, status: Status }

local warpRemote: RemoteEvent? = nil
local ui: any = {}
local reached: { [string]: boolean } = {}
local available: { [string]: boolean } = {}
local stageId: any = nil
local downed = false
local unseen = false
local drawn = "" -- the signature of the board on screen
local selected: string? = nil -- the picked badge: a camp key, or SOON_KEY
local lastClick = 0

-- ── Helpers ─────────────────────────────────────────────────────────

--- A label in the panel's cartoon voice: white, INK-outlined. `props` are set as-is.
local function inked(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = PANEL.white
	label.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(label :: any)[key] = value
	end
	label.TextStrokeTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = PANEL.ink
	stroke.Thickness = math.max(2, label.TextSize * 0.1)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = parent
	return label
end

local function round(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

--- An empty, see-through frame.
local function box(parent: Instance, name: string, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 1
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

local CIRCLE = UDim.new(0.5, 0)

--- A plain rectangle at picture coordinates: x/y/w/h in a 120 x 68 box, whatever size
--- the picture is drawn at.
local function patch(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Position = UDim2.fromScale(x / 120, y / 68)
	frame.Size = UDim2.fromScale(w / 120, h / 68)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

-- ── Where you are ───────────────────────────────────────────────────

--- The camp you are standing in, or nil out in a stage: no stage and no site camp is
--- Base Camp (CampService.campOf's rule).
local function currentCamp(): string?
	if stageId ~= nil then
		return nil
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil
	end
	local site = Camps.at(root.Position.X, root.Position.Z)
	return if site then site.key else Camps.BASE
end

--- Every camp that gets a badge: Base Camp always, a site camp once it is in this world.
local function listed(): { Camps.CampDef }
	local out = {}
	for _, def in Camps.DEFS do
		if def.key == Camps.BASE or available[def.key] then
			table.insert(out, def)
		end
	end
	return out
end

local function statusOf(def: Camps.CampDef, here: string?): Status
	if stageId ~= nil or downed then
		return "blocked"
	end
	if def.key == here then
		return "here"
	end
	if def.key ~= Camps.BASE and reached[def.key] ~= true then
		return "locked"
	end
	return "go"
end

-- ── The postcard ────────────────────────────────────────────────────

--- The camp's postcard: sky, wall, two stalls, lawn and a path, in `def.card`'s
--- colours, inside a CanvasGroup so its rounded corners (or a badge's circle) clip
--- everything drawn in it. The scene keeps its 120:68 shape and is cropped to fit, so
--- a round badge shows its middle rather than a squashed picture. nil draws the "???".
--- Its INK frame is a sibling laid over it: a stroke inside a CanvasGroup would be
--- clipped to half its width.
local function picture(parent: Instance, def: Camps.CampDef?, dim: boolean, size: Vector2, position: UDim2, anchor: Vector2, radius: UDim, inkWidth: number, zIndex: number)
	local group = Instance.new("CanvasGroup")
	group.Name = "Picture"
	group.AnchorPoint = anchor
	group.Position = position
	group.Size = UDim2.fromOffset(size.X, size.Y)
	group.BackgroundColor3 = PANEL.soonPicture
	group.BorderSizePixel = 0
	group.ZIndex = zIndex
	group.GroupColor3 = if dim then DIMMED else PANEL.white
	group.Parent = parent
	round(group, radius)

	local frame = box(parent, "PictureEdge", zIndex + 1)
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = group.Size
	round(frame, radius)
	edge(frame, PANEL.ink, inkWidth)

	if def == nil then
		local mark = Instance.new("TextLabel")
		mark.Name = "Unknown"
		mark.Size = UDim2.fromScale(1, 1)
		mark.BackgroundTransparency = 1
		mark.Font = PANEL.headline
		mark.TextSize = math.floor(size.Y * 0.5)
		mark.TextColor3 = PANEL.soonMark
		mark.Text = "?"
		mark.ZIndex = zIndex
		mark.Parent = group
		return
	end

	-- The scene covers the group at its own 120:68, centred.
	local scene = box(group, "Scene", zIndex)
	scene.AnchorPoint = Vector2.new(0.5, 0.5)
	scene.Position = UDim2.fromScale(0.5, 0.5)
	local aspect = 120 / 68
	if size.X / size.Y >= aspect then
		scene.Size = UDim2.fromScale(1, (size.X / aspect) / size.Y)
	else
		scene.Size = UDim2.fromScale((size.Y * aspect) / size.X, 1)
	end

	local card = def.card
	local sky = patch(scene, 0, 0, 120, 68, PANEL.white, zIndex)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromHex(card.skyTop), Color3.fromHex(card.skyBottom))
	gradient.Rotation = 90
	gradient.Parent = sky
	patch(scene, 0, 30, 120, 12, Color3.fromHex(card.wall), zIndex + 1)
	patch(scene, 0, 28, 120, 3, Color3.fromHex(card.wallCap), zIndex + 1)
	-- Each stall: a roof (a square turned 45 degrees -- only its top half shows, as the
	-- gable; the stall and the lawn cover the rest) over a pale body.
	for index, stall in { { x = 30, half = 12 }, { x = 90, half = 14 } } do
		-- Square in pixels whatever the picture's aspect: sized off its height alone.
		local side = stall.half * math.sqrt(2) / 68
		local roof = Instance.new("Frame")
		roof.AnchorPoint = Vector2.new(0.5, 0.5)
		roof.Position = UDim2.fromScale(stall.x / 120, 34 / 68)
		roof.SizeConstraint = Enum.SizeConstraint.RelativeYY
		roof.Size = UDim2.fromScale(side, side)
		roof.Rotation = 45
		roof.BackgroundColor3 = Color3.fromHex(card.roofs[index])
		roof.BorderSizePixel = 0
		roof.ZIndex = zIndex + 2
		roof.Parent = scene
		patch(scene, stall.x - stall.half + 3, 34, (stall.half - 3) * 2, 8, PANEL.stall, zIndex + 3)
	end
	patch(scene, 0, 41, 120, 27, Color3.fromHex(card.lawn), zIndex + 4)
	-- The path: a trapezoid from the wall's foot to the bottom edge, one strip per unit.
	local path = Color3.fromHex(card.path)
	for y = 41, 67 do
		local half = 3 + (y - 41) * (9 / 26)
		patch(scene, 60 - half, y, half * 2, 1.05, path, zIndex + 5)
	end
end

-- ── Warping ─────────────────────────────────────────────────────────

local function warpTo(key: string)
	local now = os.clock()
	if now - lastClick < CLICK_DEBOUNCE or warpRemote == nil then
		return
	end
	lastClick = now
	warpRemote:FireServer({ dest = key })
	CampWarp.close()
end

local BUTTON_LOOK: { [Status]: { text: string, fill: ColorSequence, color: Color3 } } = {
	go = { text = "WARP", fill = PANEL.go, color = PANEL.white },
	here = { text = "HERE", fill = PANEL.here, color = PANEL.hereText },
	locked = { text = "LOCKED", fill = PANEL.off, color = PANEL.offText },
	blocked = { text = "WARP", fill = PANEL.off, color = PANEL.offText },
	soon = { text = "SOON", fill = PANEL.soon, color = PANEL.offText },
}

--- The info bar's chunky button. Only "go" does anything.
local function warpButton(parent: Instance, status: Status, key: string?)
	local look = BUTTON_LOOK[status]
	local button = Instance.new("TextButton")
	button.Name = "Warp"
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -16, 0.5, 0)
	button.Size = UDim2.fromOffset(BUTTON_W, BUTTON_H)
	button.Text = ""
	button.ZIndex = 4
	button.Parent = parent
	round(button, UDim.new(0, 12))
	edge(button, PANEL.ink, 3)
	local fill = Studded.fill(button, look.fill)
	inked(button, {
		Name = "Label",
		Text = look.text,
		Font = PANEL.headline,
		TextSize = 26,
		TextColor3 = look.color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	})

	if status ~= "go" or key == nil then
		button.Active = false
		return
	end
	local dest: string = key
	button.MouseEnter:Connect(function()
		fill.Color = PANEL.goHover
	end)
	button.MouseLeave:Connect(function()
		fill.Color = PANEL.go
	end)
	button.Activated:Connect(function()
		warpTo(dest)
	end)
end

-- ── The board ───────────────────────────────────────────────────────

--- A padlock drawn in frames (no game font has the glyph): an inked gold ring for the
--- shackle, behind an inked gold body.
local function padlock(parent: Instance, zIndex: number)
	local shackle = box(parent, "Shackle", zIndex)
	shackle.AnchorPoint = Vector2.new(0.5, 0.5)
	shackle.Position = UDim2.new(0.5, 0, 0.5, -10)
	shackle.Size = UDim2.fromOffset(22, 24)
	round(shackle, CIRCLE)
	edge(shackle, PANEL.ink, 7)
	local inner = box(shackle, "Inner", zIndex)
	inner.Size = UDim2.fromScale(1, 1)
	round(inner, CIRCLE)
	edge(inner, PANEL.lock, 3)
	local body = box(parent, "Body", zIndex + 1)
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.new(0.5, 0, 0.5, 6)
	body.Size = UDim2.fromOffset(34, 26)
	body.BackgroundTransparency = 0
	body.BackgroundColor3 = PANEL.lock
	round(body, UDim.new(0, 6))
	edge(body, PANEL.ink, 3)
end

--- Where badge `index` of `count` sits on a board `width` x BOARD_H.
local function discAt(index: number, count: number, width: number): Vector2
	local x = if count <= 1 then width / 2 else DISC_MARGIN + (index - 1) * (width - 2 * DISC_MARGIN) / (count - 1)
	local y = DISC_Y[(index - 1) % #DISC_Y + 1] * BOARD_H
	return Vector2.new(x, y)
end

--- The dotted trail from badge to badge: each leg bows off the straight line (up, then
--- down, alternately), with no dot under a disc.
local function trail(board: Frame, points: { Vector2 })
	local clear = DISC / 2 + 8
	for leg = 1, #points - 1 do
		local a, b = points[leg], points[leg + 1]
		local along = b - a
		local normal = Vector2.new(-along.Y, along.X).Unit * (if leg % 2 == 1 then -BOW else BOW)
		local steps = math.max(2, math.floor(along.Magnitude / DOT_STEP))
		for step = 0, steps do
			local t = step / steps
			local p = a + along * t + normal * math.sin(math.pi * t)
			if (p - a).Magnitude > clear and (p - b).Magnitude > clear then
				local dot = box(board, "Dot", 2)
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.Position = UDim2.fromOffset(p.X, p.Y)
				dot.Size = UDim2.fromOffset(DOT, DOT)
				dot.BackgroundTransparency = 0.15
				dot.BackgroundColor3 = PANEL.dot
				round(dot, CIRCLE)
			end
		end
	end
end

--- One badge: the camp's postcard in a circle, its name under it, a green ring while
--- it is the one picked, a YOU ARE HERE pin over the camp you stand in, and a padlock
--- over a camp you have not walked to yet. Clicking it picks it.
local function campBadge(board: Frame, stop: Stop, at: Vector2, here: boolean)
	local holder = box(board, `Stop_{stop.key}`, 3)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromOffset(at.X, at.Y)
	holder.Size = UDim2.fromOffset(DISC, DISC)

	if stop.key == selected then
		local ring = box(holder, "Ring", 3)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromOffset(DISC + 16, DISC + 16)
		ring.BackgroundTransparency = 0
		ring.BackgroundColor3 = PANEL.selected
		round(ring, CIRCLE)
		edge(ring, PANEL.ink, 3)
	end

	local locked = stop.status == "locked"
	picture(holder, stop.def, locked, Vector2.new(DISC, DISC), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), CIRCLE, 4, 4)

	if locked then
		local lock = box(holder, "Lock", 12)
		lock.Size = UDim2.fromScale(1, 1)
		padlock(lock, 12)
	end

	inked(holder, {
		Name = "CampName",
		Text = if stop.def then stop.def.name else "???",
		Font = PANEL.label,
		TextSize = 16,
		TextColor3 = if stop.def then PANEL.white else PANEL.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 10),
		Size = UDim2.fromOffset(DISC + 70, 20),
		ZIndex = 14,
	})

	if here then
		local pin = Instance.new("TextLabel")
		pin.Name = "YouAreHere"
		pin.AnchorPoint = Vector2.new(0.5, 1)
		pin.Position = UDim2.new(0.5, 0, 0, -4)
		pin.Size = UDim2.fromOffset(122, 24)
		pin.BackgroundColor3 = PANEL.pin
		pin.BorderSizePixel = 0
		pin.Font = PANEL.label
		pin.TextSize = 12
		pin.TextColor3 = PANEL.ink
		pin.Text = "YOU ARE HERE"
		pin.ZIndex = 15
		pin.Parent = holder
		round(pin, UDim.new(0, 6))
		edge(pin, PANEL.ink, 2)
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Pick"
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 16
	hit.Parent = holder
	round(hit, CIRCLE)
	local key = stop.key
	hit.Activated:Connect(function()
		if selected ~= key then
			selected = key
			CampWarp.refresh()
		end
	end)
end

--- The bar under the board: the picked camp's postcard, name and line, and its button,
--- on a patterned plate in the camp's own accent colour.
local function infoBar(bar: Frame, stop: Stop)
	for _, child in bar:GetChildren() do
		if not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	bar.BackgroundColor3 = if stop.def then Color3.fromHex(stop.def.card.accent):Lerp(PANEL.ink, 0.25) else PANEL.soonBar
	Studded.pattern(bar, { radius = 14, zIndex = 1, bands = { 0.3, 0.52, 0.6, 0.66 }, glow = false })

	picture(bar, stop.def, stop.status == "locked", Vector2.new(INFO_PICTURE_W, INFO_PICTURE_H), UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5), UDim.new(0, 10), 2.5, 2)

	local textLeft = 12 + INFO_PICTURE_W + 16
	local textWidth = UDim2.new(1, -textLeft - BUTTON_W - 32, 0, 0)
	inked(bar, {
		Name = "CampName",
		Text = if stop.def then stop.def.name else "???",
		Font = PANEL.headline,
		TextSize = 26,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textLeft, 16),
		Size = textWidth + UDim2.fromOffset(0, 30),
		ZIndex = 4,
	})
	local blurb = "More camps are coming"
	if stop.def and stop.status == "locked" then
		blurb = "Walk there once to unlock"
	elseif stop.def then
		blurb = stop.def.blurb
	end
	inked(bar, {
		Name = "Blurb",
		Text = `Camp {stop.id} · {blurb}`,
		Font = PANEL.label,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textLeft, 50),
		Size = textWidth + UDim2.fromOffset(0, 20),
		ZIndex = 4,
	})

	warpButton(bar, stop.status, if stop.def then stop.def.key else nil)
end

-- ── Render ──────────────────────────────────────────────────────────

--- Every badge on the trail, in order: each listed camp, then the "???" one.
local function stops(here: string?): { Stop }
	local out: { Stop } = {}
	for _, def in listed() do
		table.insert(out, { key = def.key, def = def, id = def.id, status = statusOf(def, here) })
	end
	-- Numbered after every camp in the config, listed here or not -- except a COMING
	-- SOON one, which IS that "???" badge (Rift Outpost is seen past Stage 12, never warped to).
	local lastId = 0
	for _, def in Camps.DEFS do
		if not def.comingSoon then
			lastId = math.max(lastId, def.id)
		end
	end
	table.insert(out, { key = SOON_KEY, def = nil, id = lastId + 1, status = "soon" })
	return out
end

--- The badge picked when the panel opens: the first camp you can warp to, else the one
--- you stand in, else the first.
local function defaultPick(list: { Stop }): string
	for _, stop in list do
		if stop.status == "go" then
			return stop.key
		end
	end
	for _, stop in list do
		if stop.status == "here" then
			return stop.key
		end
	end
	return list[1].key
end

--- Redraw the board and the bar if anything they show has changed (or `force`), and
--- size the panel to them.
local function render(force: boolean?)
	local panel = ui.panel
	if panel == nil then
		return
	end
	local here = currentCamp()
	local list = stops(here)
	local picked: Stop? = nil
	for _, stop in list do
		if stop.key == selected then
			picked = stop
		end
	end
	if picked == nil then
		selected = defaultPick(list)
	end

	local blocked = stageId ~= nil or downed
	local parts = { if blocked then "blocked" else "open", `pick={selected}`, `here={here}` }
	for _, stop in list do
		table.insert(parts, `{stop.key}={stop.status}`)
	end
	local signature = table.concat(parts, ",")
	if signature == drawn and not force then
		return
	end
	drawn = signature

	local board: Frame = ui.board
	for _, child in board:GetChildren() do
		if child.Name == "Dot" or string.sub(child.Name, 1, 5) == "Stop_" then
			child:Destroy()
		end
	end
	local width = PANEL_W - 2 * PAD
	local points = {}
	for index in list do
		points[index] = discAt(index, #list, width)
	end
	trail(board, points)
	for index, stop in list do
		campBadge(board, stop, points[index], stop.key == here)
		if stop.key == selected then
			picked = stop
		end
	end
	infoBar(ui.info, picked or list[1])

	ui.notice.Visible = blocked
	local boardTop = HEADER_H + GAP + (if blocked then NOTICE_H + GAP else 0)
	board.Position = UDim2.fromOffset(0, boardTop)
	ui.info.Position = UDim2.fromOffset(0, boardTop + BOARD_H + GAP)
	panel.Size = UDim2.fromOffset(PANEL_W, boardTop + BOARD_H + GAP + INFO_H + 2 * PAD)
end

--- Redraw now (a badge was just picked).
function CampWarp.refresh()
	render()
end

local function setBadge()
	if ui.badge then
		ui.badge.Visible = unseen
	end
end

-- ── Open / close ────────────────────────────────────────────────────

function CampWarp.open()
	local panel = ui.panel
	if panel == nil or panel.Visible or HudTile.blocked("Warp") then
		return
	end
	unseen = false
	setBadge()
	selected = nil -- re-picked on every opening
	render(true)
	panel.Visible = true
	if ui.scale then
		ui.scale.Scale = 0.85
		TweenService:Create(ui.scale, OPEN, { Scale = 1 }):Play()
	end
end

function CampWarp.close()
	if ui.panel then
		ui.panel.Visible = false
	end
end

function CampWarp.toggle()
	if ui.panel and ui.panel.Visible then
		CampWarp.close()
	else
		CampWarp.open()
	end
end

local function buildPanel(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarpPanel"
	gui.ResetOnSpawn = false
	-- Same call as the Nukes, Shop and Index panels: a centred modal that respects the
	-- topbar inset and sits over the whole HUD (RadHud is 100).
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 110
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local canvas = UIKit.canvas(gui)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, -PANEL_LIFT)
	panel.Size = UDim2.fromOffset(PANEL_W, 480)
	panel.BackgroundColor3 = PANEL.panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 1
	panel.Parent = canvas
	round(panel, UDim.new(0, 20))
	edge(panel, PANEL.ink, 4)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	-- The dark studded panel. UIPadding insets every child, this one too, so it is
	-- pushed back out to the panel's edges.
	local pattern = Studded.pattern(panel, { radius = 20, bands = { 0.15, 0.42, 0.52, 0.58 }, bandTransparency = 0.93, studTransparency = 0.1, glow = false })
	pattern.Position = UDim2.fromOffset(-PAD, -PAD)
	pattern.Size = UDim2.new(1, 2 * PAD, 1, 2 * PAD)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PAD)
	padding.PaddingBottom = UDim.new(0, PAD)
	padding.PaddingLeft = UDim.new(0, PAD)
	padding.PaddingRight = UDim.new(0, PAD)
	padding.Parent = panel

	-- The navy patterned title bar, like the Nukes panel's.
	local header = box(panel, "Header", 2)
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	Studded.fill(header, PANEL.header)
	round(header, UDim.new(0, 12))
	edge(header, PANEL.ink, 3)
	Studded.pattern(header, { radius = 12, tile = 22, bands = { 0.28, 0.5, 0.58, 0.64 } })
	inked(header, {
		Name = "Title",
		Text = "Warp",
		Font = PANEL.headline,
		TextSize = 34,
		Position = UDim2.fromOffset(18, 4),
		Size = UDim2.fromOffset(200, 36),
		ZIndex = 3,
	})
	inked(header, {
		Name = "Subtitle",
		Text = SUBTITLE,
		Font = PANEL.label,
		TextSize = 13,
		TextColor3 = PANEL.subtitle,
		Position = UDim2.fromOffset(18, 40),
		Size = UDim2.new(1, -80, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})

	-- The big red X, hung over the panel's top-right corner like the shop's.
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, PAD - 6, 0, -PAD + 6)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundColor3 = PANEL.close
	close.Font = PANEL.headline
	close.TextSize = 26
	close.TextColor3 = PANEL.white
	close.Text = "X"
	close.ZIndex = 20
	close.Parent = panel
	round(close, UDim.new(0, 10))
	edge(close, PANEL.ink, 3)
	close.Activated:Connect(CampWarp.close)

	-- Up only while the player is in a stage (or downed): the reason the button is off.
	local notice = box(panel, "StageNotice", 2)
	notice.Position = UDim2.fromOffset(0, HEADER_H + GAP)
	notice.Size = UDim2.new(1, 0, 0, NOTICE_H)
	notice.BackgroundTransparency = 0
	notice.BackgroundColor3 = PANEL.noticeFill
	notice.Visible = false
	round(notice, UDim.new(0, 10))
	edge(notice, PANEL.noticeEdge, 2.5)
	local noticeText = Instance.new("TextLabel")
	noticeText.Name = "Text"
	noticeText.BackgroundTransparency = 1
	noticeText.Position = UDim2.fromOffset(12, 0)
	noticeText.Size = UDim2.new(1, -24, 1, 0)
	noticeText.Font = PANEL.label
	noticeText.TextSize = 15
	noticeText.TextColor3 = PANEL.noticeText
	noticeText.TextXAlignment = Enum.TextXAlignment.Left
	noticeText.Text = STAGE_NOTICE
	noticeText.ZIndex = 3
	noticeText.Parent = notice

	-- The board the trail is drawn on: a darker studded well.
	local board = box(panel, "Board", 2)
	board.Size = UDim2.new(1, 0, 0, BOARD_H)
	board.BackgroundTransparency = 0
	board.BackgroundColor3 = PANEL.board
	round(board, UDim.new(0, 12))
	edge(board, PANEL.ink, 3)
	Studded.pattern(board, { radius = 12, zIndex = 1, bands = { 0.1, 0.38, 0.5, 0.56 }, bandTransparency = 0.95, studTransparency = 0.15, glow = false })

	-- The picked camp's bar (infoBar fills it).
	local info = box(panel, "Info", 2)
	info.Size = UDim2.new(1, 0, 0, INFO_H)
	info.BackgroundTransparency = 0
	round(info, UDim.new(0, 14))
	edge(info, PANEL.ink, 4)

	ui.panel = panel
	ui.scale = scale
	ui.notice = notice
	ui.board = board
	ui.info = info
	return gui
end

--- Hang the "camp reached" red "!" on the WARP portal (WarpController's bar).
function CampWarp.attachBadge(host: GuiObject)
	local badge, mark = HudTile.badge(host, PANEL.badge, PANEL.ink)
	badge.ZIndex = 10
	mark.Text = "!"
	mark.TextSize = 13
	ui.badge = badge
	setBadge()
end

function CampWarp.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	buildPanel().Parent = playerGui
	HudTile.registerPanel("Warp", ui.panel)

	warpRemote = Net.get("Warp")

	-- ~10Hz. Cheap while the panel is shut: render() is only reached while it shows,
	-- and it redraws only when a badge's status (or the pick) actually changed.
	Net.get("ExposureState").OnClientEvent:Connect(function(state)
		stageId = state.stageId
		downed = state.downed == true
		if ui.panel and ui.panel.Visible then
			render()
		end
	end)

	local campState = Net.get("CampState")
	campState.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then
			return
		end
		reached = if type(state.reached) == "table" then state.reached else {}
		available = if type(state.available) == "table" then state.available else {}
		if type(state.unlocked) == "string" and not (ui.panel and ui.panel.Visible) then
			unseen = true
			setBadge()
		end
		if ui.panel and ui.panel.Visible then
			render()
		end
	end)
	-- The load-time push may already have gone to StageBannerController, which listens
	-- first (a queued remote event goes to the first listener only): ask for our own.
	campState:FireServer()
end

return CampWarp
