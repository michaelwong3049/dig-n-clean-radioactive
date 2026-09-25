--!strict
--[[
	CampWarpController.luau — the Warp tile, and the camp list it opens.

	THE TILE is the bottom-right square of the right-edge 2x2 grid, built by HudTile
	like Index, Shop and Nukes, with a portal swirl on it.
	A red "!" sits on its corner from the moment a camp is reached on foot (CampState's
	`unlocked`) until the panel is next opened, so a new warp does not go unnoticed.

	THE PANEL LISTS EVERY CAMP (Config/Camps, in order), then one "???" row for the
	camps still to come. Each row is a little postcard of the camp in its own colours
	(Config/Camps `card`), its name and one line (`blurb`), and a button:
	  WARP    — go there (the Warp remote with the camp's key; WarpService decides the
	            CFrame, and Base Camp's key lands you on your plot, like HOME);
	  HERE    — you are standing in it;
	  LOCKED  — a site camp you have not reached on foot yet (CampState `reached`);
	  SOON    — the "???" row.
	Inside a stage, or downed, every button is off and a notice says to walk back:
	WarpService refuses a warp out of a field whatever the client shows, so this only
	says so up front. A camp that is not in this world at all (CampState `available`;
	a place saved before it was built) gets no row, since there is nothing to land on.

	"HERE" is worked out on the client, from ExposureState's stageId and Camps.at on the
	character's position: no stage and no site camp means Base Camp, the same rule the
	server's CampService.campOf uses.

	Its look is the Nukes panel's (NukesController PANEL: slate, LuckiestGuy / FredokaOne
	in INK outlines, red X), so the two read as one family.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Camps = require(Shared.Config.Camps)

local UIKit = require(script.Parent.Parent.UIKit)
local Artwork = require(script.Parent.Parent.HudArtwork)
local HudTile = require(script.Parent.Parent.HudTile)

local CampWarp = {}

-- THE WARP TILE: bottom right of the right-edge 2x2 grid (HudTile), a cyan glow
-- behind the portal swirl.
local TILE_SLOT = 4
local TILE_COLOR = Color3.fromRGB(60, 195, 255)
local TILE_LIGHT = Color3.fromRGB(183, 236, 255)
local HOVER = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local PANEL = {
	panel = Color3.fromHex("1B1F23"),
	row = Color3.fromHex("252A30"),
	rowSoon = Color3.fromHex("1F2328"),
	edgeSoon = Color3.fromHex("4A4F55"),
	light = Color3.fromHex("E6EAF0"),
	dim = Color3.fromHex("9AA3AD"),
	faint = Color3.fromHex("6B737C"),
	go = Color3.fromHex("3FB35A"),
	goHover = Color3.fromHex("52C96C"),
	off = Color3.fromHex("4A4F55"),
	offText = Color3.fromHex("C9CDD2"),
	here = Color3.fromHex("2B3A2F"),
	hereText = Color3.fromHex("86F27A"),
	close = Color3.fromHex("E5484D"),
	noticeFill = Color3.fromHex("3A2A10"),
	noticeEdge = Color3.fromHex("F59E0B"),
	noticeText = Color3.fromHex("FFD58A"),
	soonPicture = Color3.fromHex("2A2E33"),
	soonMark = Color3.fromHex("555C64"),
	stall = Color3.fromHex("EEE4CF"),
	badge = Color3.fromHex("EF4444"),
	ink = Color3.fromHex("1A1A1A"),
	white = Color3.new(1, 1, 1),
	headline = Enum.Font.LuckiestGuy,
	label = Enum.Font.FredokaOne,
}
local PANEL_W = 620
local PAD = 20
local HEADER_H = 50
local SUB_H = 24
local NOTICE_H = 34
local ROW_H = 86
local ROW_GAP = 10
local MAX_ROWS = 4 -- any more than this and the list scrolls
local PICTURE_W, PICTURE_H = 110, 62
local BUTTON_W, BUTTON_H = 118, 46
local OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLICK_DEBOUNCE = 0.4
-- A locked camp's (and the "???" row's) picture, greyed down.
local DIMMED = Color3.fromRGB(120, 120, 130)

local SUBTITLE = "Jump between camps. A camp unlocks once you've walked there."
local STAGE_NOTICE = "You can't warp out of a stage. Walk back to a camp first."

type Status = "go" | "here" | "locked" | "blocked" | "soon"

local warpRemote: RemoteEvent? = nil
local ui: any = {}
local reached: { [string]: boolean } = {}
local available: { [string]: boolean } = {}
local stageId: any = nil
local downed = false
local unseen = false
local drawn = "" -- the signature of the rows on screen
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

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function edge(parent: Instance, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

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

--- Every camp that gets a row: Base Camp always, a site camp once it is in this world.
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

-- ── A row ───────────────────────────────────────────────────────────

--- The camp's postcard: sky, wall, two stalls, lawn and a path, in `def.card`'s
--- colours. A CanvasGroup, so its rounded corners clip everything drawn inside it.
--- nil draws the "???" card.
local function picture(parent: Instance, def: Camps.CampDef?, dim: boolean)
	local group = Instance.new("CanvasGroup")
	group.Name = "Picture"
	group.AnchorPoint = Vector2.new(0, 0.5)
	group.Position = UDim2.new(0, 12, 0.5, 0)
	group.Size = UDim2.fromOffset(PICTURE_W, PICTURE_H)
	group.BackgroundColor3 = PANEL.soonPicture
	group.BorderSizePixel = 0
	group.ZIndex = 14
	group.GroupColor3 = if dim then DIMMED else PANEL.white
	group.Parent = parent
	round(group, 10)

	-- The INK frame goes on a sibling laid over it: a stroke inside the CanvasGroup
	-- would be clipped to half its width.
	local frame = Instance.new("Frame")
	frame.Name = "PictureEdge"
	frame.AnchorPoint = group.AnchorPoint
	frame.Position = group.Position
	frame.Size = group.Size
	frame.BackgroundTransparency = 1
	frame.ZIndex = 16
	frame.Parent = parent
	round(frame, 10)
	edge(frame, PANEL.ink, 2.5)

	if def == nil then
		local mark = Instance.new("TextLabel")
		mark.Name = "Unknown"
		mark.Size = UDim2.fromScale(1, 1)
		mark.BackgroundTransparency = 1
		mark.Font = PANEL.headline
		mark.TextSize = 34
		mark.TextColor3 = PANEL.soonMark
		mark.Text = "?"
		mark.ZIndex = 15
		mark.Parent = group
		return
	end

	local card = def.card
	local sky = patch(group, 0, 0, 120, 68, PANEL.white, 15)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromHex(card.skyTop), Color3.fromHex(card.skyBottom))
	gradient.Rotation = 90
	gradient.Parent = sky
	patch(group, 0, 30, 120, 12, Color3.fromHex(card.wall), 16)
	patch(group, 0, 28, 120, 3, Color3.fromHex(card.wallCap), 16)
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
		roof.ZIndex = 17
		roof.Parent = group
		patch(group, stall.x - stall.half + 3, 34, (stall.half - 3) * 2, 8, PANEL.stall, 18)
	end
	patch(group, 0, 41, 120, 27, Color3.fromHex(card.lawn), 19)
	-- The path: a trapezoid from the wall's foot to the bottom edge, one strip per unit.
	local path = Color3.fromHex(card.path)
	for y = 41, 67 do
		local half = 3 + (y - 41) * (9 / 26)
		patch(group, 60 - half, y, half * 2, 1.05, path, 20)
	end
end

local function warpTo(key: string)
	local now = os.clock()
	if now - lastClick < CLICK_DEBOUNCE or warpRemote == nil then
		return
	end
	lastClick = now
	warpRemote:FireServer({ dest = key })
	CampWarp.close()
end

local BUTTON_LOOK: { [Status]: { text: string, fill: Color3, color: Color3 } } = {
	go = { text = "WARP", fill = PANEL.go, color = PANEL.white },
	here = { text = "HERE", fill = PANEL.here, color = PANEL.hereText },
	locked = { text = "LOCKED", fill = PANEL.off, color = PANEL.offText },
	blocked = { text = "WARP", fill = PANEL.off, color = PANEL.offText },
	soon = { text = "SOON", fill = PANEL.off, color = PANEL.offText },
}

--- The row's button, and its hard INK shadow. Only "go" does anything.
local function rowButton(parent: Instance, status: Status, key: string?)
	local look = BUTTON_LOOK[status]
	local shadow = Instance.new("Frame")
	shadow.Name = "ButtonShadow"
	shadow.AnchorPoint = Vector2.new(1, 0.5)
	shadow.Position = UDim2.new(1, -14, 0.5, 2)
	shadow.Size = UDim2.fromOffset(BUTTON_W, BUTTON_H)
	shadow.BackgroundColor3 = PANEL.ink
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 14
	shadow.Parent = parent
	round(shadow, 12)

	local button = Instance.new("TextButton")
	button.Name = "Warp"
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -14, 0.5, -2)
	button.Size = UDim2.fromOffset(BUTTON_W, BUTTON_H)
	button.BackgroundColor3 = look.fill
	button.Font = PANEL.headline
	button.TextSize = 22
	button.TextColor3 = look.color
	button.Text = look.text
	button.ZIndex = 15
	button.Parent = parent
	round(button, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = PANEL.ink
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	-- LuckiestGuy sits high in its line box (see CashController); nudge it down.
	local inset = Instance.new("UIPadding")
	inset.PaddingTop = UDim.new(0, 4)
	inset.Parent = button

	if status ~= "go" or key == nil then
		button.Active = false
		return
	end
	local dest: string = key
	button.MouseEnter:Connect(function()
		TweenService:Create(button, HOVER, { BackgroundColor3 = PANEL.goHover }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, HOVER, { BackgroundColor3 = PANEL.go }):Play()
	end)
	button.Activated:Connect(function()
		warpTo(dest)
	end)
end

--- One camp's row (or, with `def` nil, the "???" row numbered `id`).
local function row(parent: Instance, order: number, def: Camps.CampDef?, id: number, status: Status)
	local soon = def == nil
	local frame = Instance.new("Frame")
	frame.Name = if def then def.key else "ComingSoon"
	frame.Size = UDim2.new(1, -8, 0, ROW_H)
	frame.BackgroundColor3 = if soon then PANEL.rowSoon else PANEL.row
	frame.BorderSizePixel = 0
	frame.LayoutOrder = order
	frame.ZIndex = 13
	frame.Parent = parent
	round(frame, 14)
	edge(frame, if soon then PANEL.edgeSoon else PANEL.ink, if soon then 2 else 3)

	picture(frame, def, status == "locked" or soon)

	local textLeft = 12 + PICTURE_W + 14
	local textWidth = UDim2.new(1, -textLeft - BUTTON_W - 30, 0, 0)
	local caption = Instance.new("TextLabel")
	caption.Name = "Number"
	caption.BackgroundTransparency = 1
	caption.Position = UDim2.fromOffset(textLeft, 12)
	caption.Size = textWidth + UDim2.fromOffset(0, 14)
	caption.Font = PANEL.label
	caption.TextSize = 13
	caption.TextColor3 = if def then Color3.fromHex(def.card.accent) else PANEL.faint
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Text = `CAMP {id}`
	caption.ZIndex = 14
	caption.Parent = frame
	inked(frame, {
		Name = "CampName",
		Text = if def then def.name else "???",
		Font = PANEL.label,
		TextSize = 23,
		TextColor3 = if soon then PANEL.faint else PANEL.light,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textLeft, 27),
		Size = textWidth + UDim2.fromOffset(0, 28),
		ZIndex = 14,
	})
	local blurb = "More camps are coming"
	if def and status == "locked" then
		blurb = "Walk there once to unlock"
	elseif def then
		blurb = def.blurb
	end
	inked(frame, {
		Name = "Blurb",
		Text = blurb,
		Font = PANEL.label,
		TextSize = 14,
		TextColor3 = PANEL.dim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(textLeft, 56),
		Size = textWidth + UDim2.fromOffset(0, 18),
		ZIndex = 14,
	})

	rowButton(frame, status, if def then def.key else nil)
end

-- ── Render ──────────────────────────────────────────────────────────

--- Redraw the rows if anything they show has changed (or `force`), and size the panel
--- to them.
local function render(force: boolean?)
	local panel = ui.panel
	if panel == nil then
		return
	end
	local here = currentCamp()
	local defs = listed()
	local blocked = stageId ~= nil or downed
	local parts = { if blocked then "blocked" else "open" }
	local statuses: { Status } = {}
	for index, def in defs do
		statuses[index] = statusOf(def, here)
		table.insert(parts, `{def.key}={statuses[index]}`)
	end
	local signature = table.concat(parts, ",")
	if signature == drawn and not force then
		return
	end
	drawn = signature

	local scroll: ScrollingFrame = ui.scroll
	for _, child in scroll:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	for index, def in defs do
		row(scroll, index, def, def.id, statuses[index])
	end
	-- Numbered after every camp in the config, listed here or not.
	local lastId = 0
	for _, def in Camps.DEFS do
		lastId = math.max(lastId, def.id)
	end
	row(scroll, #defs + 1, nil, lastId + 1, "soon")

	ui.notice.Visible = blocked
	local listTop = HEADER_H + SUB_H + 8 + (if blocked then NOTICE_H + 8 else 0)
	local shownRows = math.min(#defs + 1, MAX_ROWS)
	local listHeight = shownRows * ROW_H + (shownRows - 1) * ROW_GAP + 8
	scroll.Position = UDim2.fromOffset(0, listTop)
	scroll.Size = UDim2.new(1, 0, 0, listHeight)
	panel.Size = UDim2.fromOffset(PANEL_W, listTop + listHeight + PAD + (PAD - 6))
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
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, 400)
	panel.BackgroundColor3 = PANEL.panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 10
	panel.Parent = canvas
	round(panel, 20)
	edge(panel, PANEL.ink, 4)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, PAD - 6)
	padding.PaddingBottom = UDim.new(0, PAD)
	padding.PaddingLeft = UDim.new(0, PAD)
	padding.PaddingRight = UDim.new(0, PAD)
	padding.Parent = panel

	inked(panel, {
		Name = "Title",
		Text = "WARP",
		Font = PANEL.headline,
		TextSize = 38,
		Size = UDim2.fromOffset(200, 46),
		ZIndex = 11,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AutoButtonColor = false
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 2)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = PANEL.close
	close.Font = PANEL.headline
	close.TextSize = 24
	close.TextColor3 = PANEL.white
	close.Text = "X"
	close.ZIndex = 11
	close.Parent = panel
	round(close, 12)
	local closeEdge = Instance.new("UIStroke")
	closeEdge.Color = PANEL.ink
	closeEdge.Thickness = 3
	closeEdge.Parent = close
	close.Activated:Connect(CampWarp.close)

	inked(panel, {
		Name = "Subtitle",
		Text = SUBTITLE,
		Font = PANEL.label,
		TextSize = 15,
		TextColor3 = PANEL.dim,
		Position = UDim2.fromOffset(0, HEADER_H),
		Size = UDim2.new(1, 0, 0, SUB_H),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 11,
	})

	-- Up only while the player is in a stage (or downed): the reason every button is off.
	local notice = Instance.new("Frame")
	notice.Name = "StageNotice"
	notice.Position = UDim2.fromOffset(0, HEADER_H + SUB_H + 8)
	notice.Size = UDim2.new(1, -8, 0, NOTICE_H)
	notice.BackgroundColor3 = PANEL.noticeFill
	notice.BorderSizePixel = 0
	notice.Visible = false
	notice.ZIndex = 11
	notice.Parent = panel
	round(notice, 10)
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
	noticeText.ZIndex = 12
	noticeText.Parent = notice

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = PANEL.dim
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ZIndex = 12
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, ROW_GAP)
	layout.Parent = scroll
	local inset = Instance.new("UIPadding")
	inset.PaddingLeft = UDim.new(0, 2)
	inset.PaddingTop = UDim.new(0, 3)
	inset.PaddingBottom = UDim.new(0, 4)
	inset.Parent = scroll

	ui.panel = panel
	ui.scale = scale
	ui.notice = notice
	ui.scroll = scroll
	return gui
end

-- ── The tile ────────────────────────────────────────────────────────

local function build(): ScreenGui
	local gui, button = HudTile.build({
		name = "WarpButton",
		caption = "Warp",
		slot = TILE_SLOT,
		color = TILE_COLOR,
		light = TILE_LIGHT,
		image = Artwork.IMAGE.portal,
		onActivated = CampWarp.toggle,
	})
	-- A camp reached since the panel was last opened: a red "!" on the corner, the
	-- same badge the Index tile wears for new entries.
	local badge, mark = HudTile.badge(button, PANEL.badge, PANEL.ink)
	mark.Text = "!"
	mark.TextSize = 13
	ui.badge = badge
	return gui
end

function CampWarp.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	build().Parent = playerGui
	buildPanel().Parent = playerGui
	HudTile.registerPanel("Warp", ui.panel)

	warpRemote = Net.get("Warp")

	-- ~10Hz. Cheap while the panel is shut: render() is only reached while it shows,
	-- and it redraws only when a row's status actually changed.
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
