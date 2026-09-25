--!strict
--[[
	TutorialController.luau — the new-player walkthrough's banner and ground trail.

	ON REQUEST, from browser mockups: card 1 (a banner at the top centre) with trail C
	(a glowing ribbon on the ground with arrows running along it, a pulsing ring where
	it ends, and a bobbing arrow over the target showing the distance). Also on request:
	the banner says ONLY what to do now. There is no "step 3 of 6", no progress
	dots, nothing that counts.

	THE SERVER DECIDES THE STEP (Services/TutorialService) and sends it on
	TutorialState whenever it changes; this file only draws it. What it draws per step:

	    stage    banner + trail to the nearest point of Stage 1's edge
	    dig      banner only. Finding the glow is the lesson, so nothing points at one.
	    haul     banner + an amber ring pulsing round the haul panel's button
	    clean    banner + trail to YOUR cleansing station
	    place    banner + trail to your nearest EMPTY stand
	    upgrade  banner + trail to the Detector Shop
	    finish   the "YOU'RE SET!" card, once

	THE TRAIL IS CLIENT-ONLY PARTS in a local Workspace folder, so nobody else sees
	anyone's trail. The route is PathfindingService's, recomputed a little under once a
	second while you move, and it falls back to a straight line when there is no path
	(the target inside a tub, say). Every ribbon point is raycast onto whatever floor is
	really there. It is built from plain parts and a SurfaceGui, with no uploaded
	textures, and no Neon: it is guidance, not an effect.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Stages = require(Shared.Config.Stages)
local Tutorial = require(Shared.Config.Tutorial)

local UIKit = require(script.Parent.Parent.UIKit)

local TutorialController = {}

local player = Players.LocalPlayer

-- The same field-kit card as client/LockerTutorial, so every walkthrough in the
-- game reads as one voice.
local SKIN = {
	card = Color3.fromHex("22272C"),
	cardLow = Color3.fromHex("1D2226"),
	edge = Color3.fromHex("343B42"),
	amber = Color3.fromHex("F2A93B"),
	text = Color3.new(1, 1, 1),
	dim = Color3.fromHex("C4C9CE"),
	button = Color3.fromHex("2A3036"),
	go = Color3.fromHex("3FBF5A"),
	ink = Color3.fromHex("1A1A1A"),
	cream = Color3.fromHex("FFF1D6"),
	headline = Enum.Font.LuckiestGuy,
	label = Enum.Font.FredokaOne,
}

-- ── Banner layout (design px on the 1280x720 canvas) ─────────────────────────────
-- TEXT ONLY, ON REQUEST: no card behind it, no hint line under it, bigger, and lower
-- down the screen, clear of WarpController's HOME / SHOPS portals (y 10..74). The frame
-- named "Banner" is still there, invisible and sized to the words, because
-- StageBannerController and AuraWarningController read its rect to stack themselves
-- underneath it.
local BANNER_Y = 118
local BANNER_H = 60
local TITLE_SIZE = 46
local SKIP_GAP = 14
local SKIP_CONFIRM_SECONDS = 3
local FINISH_AUTO_CLOSE = 10

-- ── Trail ───────────────────────────────────────────────────────────────────────
local RIBBON_WIDTH = 2.6
local RIBBON_LIFT = 0.12 -- over the floor, clear of z-fighting
local RIBBON_TRANSPARENCY = 0.45
local TRAIL_START = 3.5 -- studs ahead of your feet, so it never draws under you
local ARRIVED = 9 -- inside this, the ribbon and the marker step aside; the ring stays
-- How far the target may drift before the route is thrown away and redrawn. Stage 1's
-- target slides along its edge with you, and the nearest empty stand can change as you
-- walk; neither is worth a fresh ribbon every frame.
local RETARGET = 6
-- How far you may walk along Stage 1's edge before the "head to the first stage" goal
-- slides to follow you.
local STAGE_DRIFT = 30
-- A fresh route every REPATH_SECONDS while you move, sooner (but not more than every
-- OFF_ROUTE_SECONDS) once you have strayed OFF_ROUTE studs from the one on screen.
-- Pathfinding snaps to a 4-stud grid, so every new route lies a little differently from
-- the last one. Asking less often is most of what keeps the trail still under you, and
-- the rest is ROUTE_BLEND.
local REPATH_SECONDS = 2.5
local REPATH_MOVE = 3 -- studs moved before a repath is worth it
local OFF_ROUTE = 4
local OFF_ROUTE_SECONDS = 0.5
-- A new route does not replace the old one in a frame: every point glides from where
-- the old route had it (matched by distance from the target) to its new place.
local ROUTE_BLEND = 0.35
-- How fast the ribbon's start catches up with where you are on the route (per second,
-- exponential). High enough to feel attached, low enough to swallow a step's wobble.
local HEAD_EASE = 10
-- The last arrow stops this far short of the route's end, clear of the ring.
local CHEVRON_END_PAD = 1.5
local CHEVRON_GAP = 4
local CHEVRON_SPEED = 7 -- studs/sec along the ribbon
local CHEVRON_MAX = 24
local CHEVRON_ARM = 1.3
local CHEVRON_ANGLE = math.rad(40)
local RING_SIZE = 9
local MARKER_HEIGHT = 7 -- over the target's floor
local GUIDE_FOLDER = "TutorialGuide"

type State = { step: Tutorial.StepId, holding: boolean, plot: number? }

local state: State? = nil

-- ── UI ──────────────────────────────────────────────────────────────────────────
local ui: any = {}

local function textWidth(text: string, size: number, font: Enum.Font): number
	return TextService:GetTextSize(text, size, font, Vector2.new(4000, 200)).X
end

local function buildBanner(canvas: Frame)
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, BANNER_Y)
	banner.Size = UDim2.fromOffset(400, BANNER_H)
	banner.BackgroundTransparency = 1
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = canvas

	local scale = Instance.new("UIScale")
	scale.Parent = banner

	-- UIKit's default outline and drop shadow carry it over sky, grass and pavers alike.
	local title = UIKit.label(banner, {
		name = "Title",
		size = UDim2.fromScale(1, 1),
		font = SKIN.headline,
		textSize = TITLE_SIZE,
		color = SKIN.text,
		xAlign = Enum.TextXAlignment.Center,
		text = "",
	})

	-- SKIP sits just off the end of the words. It needs a second press: one stray
	-- click should not throw away a new player's only walkthrough.
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(0, 0.5)
	skip.Position = UDim2.new(1, SKIP_GAP, 0.5, 0)
	skip.Size = UDim2.fromOffset(64, 26)
	skip.AutoButtonColor = true
	skip.BackgroundColor3 = SKIN.button
	skip.BorderSizePixel = 0
	skip.Font = SKIN.label
	skip.TextSize = 14
	skip.TextColor3 = SKIN.dim
	skip.Text = "SKIP"
	skip.ZIndex = 3
	skip.Parent = banner
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 8)
	skipCorner.Parent = skip
	local skipStroke = Instance.new("UIStroke")
	skipStroke.Color = SKIN.edge
	skipStroke.Thickness = 2
	skipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	skipStroke.Parent = skip

	local armedAt = 0
	skip.Activated:Connect(function()
		local now = os.clock()
		if now - armedAt <= SKIP_CONFIRM_SECONDS then
			Net.get("TutorialAction"):FireServer("skip")
			skip.Text = "SKIP"
			return
		end
		armedAt = now
		skip.Text = "SURE?"
		skip.TextColor3 = SKIN.amber
		task.delay(SKIP_CONFIRM_SECONDS, function()
			if os.clock() - armedAt >= SKIP_CONFIRM_SECONDS then
				skip.Text = "SKIP"
				skip.TextColor3 = SKIN.dim
			end
		end)
	end)

	ui.banner = banner
	ui.bannerScale = scale
	ui.title = title
end

local function buildFinish(canvas: Frame)
	-- A full-screen shade that also eats clicks, so the card has to be answered.
	local shade = Instance.new("TextButton")
	shade.Name = "FinishShade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.BorderSizePixel = 0
	shade.AutoButtonColor = false
	shade.Text = ""
	shade.Visible = false
	shade.ZIndex = 5
	shade.Parent = canvas

	local card = Instance.new("Frame")
	card.Name = "FinishCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(470, 210)
	card.BackgroundColor3 = SKIN.card
	card.BorderSizePixel = 0
	card.ZIndex = 6
	card.Parent = shade
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = SKIN.amber
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	local scale = Instance.new("UIScale")
	scale.Parent = card

	local finish = Tutorial.STEPS.finish
	UIKit.label(card, {
		name = "Title",
		size = UDim2.new(1, 0, 0, 56),
		position = UDim2.fromOffset(0, 22),
		font = SKIN.headline,
		textSize = 50,
		color = SKIN.amber,
		xAlign = Enum.TextXAlignment.Center,
		text = finish.title,
		zIndex = 7,
	})
	UIKit.label(card, {
		name = "Hint",
		size = UDim2.new(1, -40, 0, 24),
		position = UDim2.fromOffset(20, 86),
		font = SKIN.label,
		textSize = 18,
		color = SKIN.dim,
		xAlign = Enum.TextXAlignment.Center,
		outline = false,
		shadow = false,
		text = finish.hint,
		zIndex = 7,
	})

	local go = Instance.new("TextButton")
	go.Name = "Go"
	go.AnchorPoint = Vector2.new(0.5, 0)
	go.Position = UDim2.new(0.5, 0, 0, 128)
	go.Size = UDim2.fromOffset(190, 52)
	go.BackgroundColor3 = SKIN.go
	go.BorderSizePixel = 0
	go.Font = SKIN.headline
	go.TextSize = 26
	go.TextColor3 = SKIN.text
	go.Text = "LET'S GO"
	go.ZIndex = 7
	go.Parent = card
	local goCorner = Instance.new("UICorner")
	goCorner.CornerRadius = UDim.new(0, 12)
	goCorner.Parent = go
	local goStroke = Instance.new("UIStroke")
	goStroke.Color = SKIN.ink
	goStroke.Thickness = 3
	goStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	goStroke.Parent = go

	local function close()
		shade.Visible = false
	end
	go.Activated:Connect(close)

	ui.finishShade = shade
	ui.finishScale = scale
	ui.closeFinish = close
end

local function showFinish()
	ui.banner.Visible = false
	ui.finishShade.Visible = true
	ui.finishScale.Scale = 0.6
	TweenService:Create(ui.finishScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(FINISH_AUTO_CLOSE, ui.closeFinish)
end

local function setBanner(step: Tutorial.StepId)
	local def = Tutorial.STEPS[step]
	local changed = ui.title.Text ~= def.title
	ui.title.Text = def.title
	-- Sized to the words, so SKIP sits right after them and the banners that stack
	-- under this one (see BANNER_Y) measure the text, not an empty box.
	ui.banner.Size = UDim2.fromOffset(math.ceil(textWidth(def.title, TITLE_SIZE, SKIN.headline)) + 8, BANNER_H)

	local wasHidden = not ui.banner.Visible
	ui.banner.Visible = true
	if changed or wasHidden then
		ui.bannerScale.Scale = 0.8
		TweenService:Create(ui.bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- ── The haul button ring ────────────────────────────────────────────────────────
-- A child of the haul panel's own button (DetectorController, "HaulButton"), so it
-- follows the panel wherever it is laid out and hides with it, with no rect math.
local haulRing: Frame? = nil

local function setHaulRing(on: boolean)
	if not on then
		if haulRing then
			haulRing:Destroy()
			haulRing = nil
		end
		return
	end
	if haulRing and haulRing.Parent then
		return
	end
	local hud = player:FindFirstChildOfClass("PlayerGui") and player.PlayerGui:FindFirstChild("DetectorHud")
	local button = hud and hud:FindFirstChild("HaulButton", true)
	if button == nil or not button:IsA("GuiObject") then
		return
	end
	local ring = Instance.new("Frame")
	ring.Name = "TutorialRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, 18, 1, 18)
	ring.BackgroundTransparency = 1
	ring.ZIndex = button.ZIndex + 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = SKIN.amber
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	ring.Parent = button
	haulRing = ring
end

-- ── World guide ─────────────────────────────────────────────────────────────────
local guide: Folder? = nil
local ribbonPool: { BasePart } = {}
local jointPool: { BasePart } = {}
-- How many of each pool the current route uses. The rest of the pool stays hidden,
-- which setGuideVisible has to respect or a stale leg of the last route reappears.
local liveLegs = 0
local liveJoints = 0
local chevrons: { { BasePart } } = {}
local ring: BasePart? = nil
local ringPulses: { Frame } = {}
local marker: Model? = nil
local markerLabel: TextLabel? = nil

--- The route, as world points on the floor from just ahead of you to the target,
--- with the cumulative length at each point.
local route: { Vector3 } = {}
local routeLen: { number } = {}
-- `route` is what is DRAWN. While a new route blends in it is rebuilt every frame from
-- `baseRoute` (the new one) and `fromRoute` (the one it is replacing); afterwards it
-- simply equals `baseRoute`.
local baseRoute: { Vector3 } = {}
local baseLen: { number } = {}
local fromRoute: { Vector3 } = {}
local fromLen: { number } = {}
local blendAt = -math.huge
local target: Vector3? = nil
local lastPathAt = -math.huge
local lastPathFrom: Vector3? = nil
local pathBusy = false
--- How far along `route` you are, eased, in studs. The ribbon starts TRAIL_START ahead
--- of this every frame. -1 means "not measured on this route yet", so a new route is
--- picked up straight away rather than eased in from the old one's numbers.
local head = -1

local function localPart(name: string, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ensureGuide(): Folder
	if guide and guide.Parent then
		return guide
	end
	local folder = Instance.new("Folder")
	folder.Name = GUIDE_FOLDER
	folder.Parent = Workspace
	guide = folder
	table.clear(ribbonPool)
	table.clear(jointPool)
	table.clear(chevrons)
	table.clear(ringPulses)
	ring = nil
	marker = nil
	markerLabel = nil
	return folder
end

local function buildRing(folder: Folder): BasePart
	local part = localPart("TargetRing", folder)
	part.Size = Vector3.new(RING_SIZE, 0.05, RING_SIZE)
	part.Transparency = 1

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.CanvasSize = Vector2.new(300, 300)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = part

	local function circle(name: string, size: number, thickness: number, fill: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(size, size)
		f.BackgroundColor3 = SKIN.amber
		f.BackgroundTransparency = fill
		f.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		local s = Instance.new("UIStroke")
		s.Name = "Stroke"
		s.Color = SKIN.amber
		s.Thickness = thickness
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
		f.Parent = gui
		return f
	end

	circle("Core", 0.5, 10, 0.72)
	table.clear(ringPulses)
	table.insert(ringPulses, circle("PulseA", 0.5, 8, 1))
	table.insert(ringPulses, circle("PulseB", 0.5, 8, 1))
	return part
end

--- The bobbing arrow over the target: a shaft and a head made of two wedges back to
--- back, point down, outlined by a Highlight so it reads against any sky.
local function buildMarker(folder: Folder): (Model, TextLabel)
	local model = Instance.new("Model")
	model.Name = "Marker"

	local depth, headH, headHalfW = 0.9, 2.0, 1.5
	local shaft = localPart("Shaft", model)
	shaft.Size = Vector3.new(depth, 1.8, 1.2)
	shaft.Color = SKIN.amber
	local wedgeA = Instance.new("WedgePart")
	local wedgeB = Instance.new("WedgePart")
	for _, w in { wedgeA, wedgeB } do
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.CastShadow = false
		w.Material = Enum.Material.SmoothPlastic
		w.Color = SKIN.amber
		w.Size = Vector3.new(depth, headH, headHalfW)
		w.Parent = model
	end
	wedgeA.Name = "HeadA"
	wedgeB.Name = "HeadB"
	model.PrimaryPart = shaft
	shaft:SetAttribute("HeadH", headH)
	shaft:SetAttribute("HeadHalfW", headHalfW)

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = SKIN.ink
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	local board = Instance.new("BillboardGui")
	board.Name = "Distance"
	board.Adornee = shaft
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.StudsOffset = Vector3.new(0, 2.6, 0)
	board.MaxDistance = 2000
	board.Parent = model
	local boardCanvas = UIKit.billboardCanvas(board, Vector2.new(140, 40))
	local label = UIKit.label(boardCanvas, {
		name = "Metres",
		size = UDim2.fromScale(1, 1),
		font = SKIN.headline,
		textSize = 28,
		color = SKIN.text,
		xAlign = Enum.TextXAlignment.Center,
		text = "",
	})

	model.Parent = folder
	return model, label
end

local function placeMarker(model: Model, at: Vector3, t: number)
	local shaft = model.PrimaryPart :: BasePart
	local headH = shaft:GetAttribute("HeadH") :: number
	local halfW = shaft:GetAttribute("HeadHalfW") :: number
	local bob = math.sin(t * 3.2) * 0.45
	local base = CFrame.new(at + Vector3.new(0, MARKER_HEIGHT + bob, 0)) * CFrame.Angles(0, t * 1.4, 0)
	-- `base` is the head's centre; the tip is headH/2 below it.
	local wedgeA = model:FindFirstChild("HeadA") :: BasePart
	local wedgeB = model:FindFirstChild("HeadB") :: BasePart
	-- A wedge flipped upside down (Z roll 180) has its full faces up and at +Z and
	-- its point at the bottom of the +Z edge. One sits either side of the centre line,
	-- the second turned round, so the two points meet under the middle.
	wedgeA.CFrame = base * CFrame.new(0, 0, -halfW / 2) * CFrame.Angles(0, 0, math.pi)
	wedgeB.CFrame = base * CFrame.new(0, 0, halfW / 2) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(0, 0, math.pi)
	shaft.CFrame = base * CFrame.new(0, headH / 2 + shaft.Size.Y / 2, 0)
end

local function setGuideVisible(showRibbon: boolean, showRing: boolean, showMarker: boolean)
	for i, p in ribbonPool do
		p.Transparency = if showRibbon and i <= liveLegs then RIBBON_TRANSPARENCY else 1
	end
	for i, p in jointPool do
		p.Transparency = if showRibbon and i <= liveJoints then RIBBON_TRANSPARENCY else 1
	end
	for _, arms in chevrons do
		for _, arm in arms do
			arm.Transparency = if showRibbon then arm.Transparency else 1
		end
	end
	if ring then
		local gui = ring:FindFirstChildOfClass("SurfaceGui")
		if gui then
			gui.Enabled = showRing
		end
	end
	if marker then
		for _, d in marker:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = if showMarker then 0 else 1
			elseif d:IsA("BillboardGui") or d:IsA("Highlight") then
				d.Enabled = showMarker
			end
		end
	end
end

local function clearGuide()
	if guide then
		guide:Destroy()
		guide = nil
	end
	table.clear(ribbonPool)
	table.clear(jointPool)
	table.clear(chevrons)
	table.clear(ringPulses)
	table.clear(route)
	table.clear(routeLen)
	table.clear(baseRoute)
	table.clear(baseLen)
	table.clear(fromRoute)
	table.clear(fromLen)
	blendAt = -math.huge
	liveLegs, liveJoints = 0, 0
	head = -1
	ring = nil
	marker = nil
	markerLabel = nil
	target = nil
	lastPathFrom = nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

--- The floor under `p`: the first thing a ray straight down from a little above it
--- hits that is not a character, the guide itself, or an invisible part. The last
--- matters: every stand has a see-through `Display` cube floating over its plinth, and
--- the ring landed on that. Falls back to `p` as given.
local function floorAt(p: Vector3): Vector3
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	if guide then
		table.insert(ignore, guide)
	end
	rayParams.FilterDescendantsInstances = ignore
	local from = p + Vector3.new(0, 5, 0)
	for _ = 1, 6 do
		local hit = Workspace:Raycast(from, Vector3.new(0, -14, 0), rayParams)
		if hit == nil then
			return p
		end
		if hit.Instance.Transparency < 1 then
			return hit.Position
		end
		table.insert(ignore, hit.Instance)
		rayParams.FilterDescendantsInstances = ignore
	end
	return p
end

-- ── Targets ─────────────────────────────────────────────────────────────────────
local function plotModel(): Instance?
	local s = state
	if s == nil or s.plot == nil then
		return nil
	end
	local plots = Workspace:FindFirstChild("Plots")
	return plots and plots:FindFirstChild(`Plot{s.plot}`)
end

local function targetFor(step: Tutorial.StepId, from: Vector3): Vector3?
	if step == "stage" then
		-- The nearest point of Stage 1's west edge, a few studs in: the stage is a
		-- long edge, so walking straight at it is the shortest way in.
		-- STICKY: it only follows you along the edge once you are STAGE_DRIFT studs off
		-- it, so walking at an angle does not keep moving the goal (and the route) under you.
		local minX, minZ, _, maxZ = Stages.bounds(1)
		local z = math.clamp(from.Z, minZ + 12, maxZ - 12)
		if target and math.abs(target.X - (minX + 8)) < 1 and math.abs(target.Z - z) < STAGE_DRIFT then
			z = target.Z
		end
		return Vector3.new(minX + 8, Stages.SURFACE_Y, z)
	elseif step == "clean" then
		local plot = plotModel()
		local spot = plot and (plot:FindFirstChild("WashSpot", true) or plot:FindFirstChild("WashStand", true))
		return if spot and spot:IsA("BasePart") then spot.Position else nil
	elseif step == "place" then
		local plot = plotModel()
		if plot == nil then
			return nil
		end
		local best: Vector3? = nil
		local bestDist = math.huge
		for _, d in plot:GetDescendants() do
			if d:IsA("BasePart") and string.match(d.Name, "^Stand%d+$") then
				local prompt = d:FindFirstChildWhichIsA("ProximityPrompt")
				if prompt and prompt:GetAttribute("Occupied") ~= true then
					local dist = (d.Position - from).Magnitude
					if dist < bestDist then
						best, bestDist = d.Position, dist
					end
				end
			end
		end
		return best
	elseif step == "upgrade" then
		local shops = Workspace:FindFirstChild("Shops")
		if shops == nil then
			return nil
		end
		for _, d in shops:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("StationKind") == "shop" and d:GetAttribute("StationId") == "Detector" then
				return d.Position
			end
		end
		return nil
	end
	return nil
end

-- ── Route ───────────────────────────────────────────────────────────────────────
--- Copy `points` into `into`, with the running length at each point in `lens`.
local function fill(into: { Vector3 }, lens: { number }, points: { Vector3 })
	table.clear(into)
	table.clear(lens)
	local total = 0
	for i, p in points do
		if i > 1 then
			total += (p - points[i - 1]).Magnitude
		end
		table.insert(into, p)
		table.insert(lens, total)
	end
end

--- The point `d` studs along a polyline, and the direction it is heading there.
local function alongIn(pts: { Vector3 }, lens: { number }, d: number): (Vector3, Vector3)
	for i = 2, #pts do
		if lens[i] >= d or i == #pts then
			local a, b = pts[i - 1], pts[i]
			local seg = lens[i] - lens[i - 1]
			local t = if seg > 0 then math.clamp((d - lens[i - 1]) / seg, 0, 1) else 0
			local dir = b - a
			dir = Vector3.new(dir.X, 0, dir.Z)
			return a:Lerp(b, t), if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1)
		end
	end
	return pts[1] or Vector3.zero, Vector3.new(0, 0, -1)
end

--- The point `d` studs along the DRAWN route.
local function along(d: number): (Vector3, Vector3)
	return alongIn(route, routeLen, d)
end

--- Rebuild the drawn route for this frame. Mid-blend, each of the new route's points
--- sits part-way between its own place and the point the OLD route had at the same
--- distance from the target, so the whole trail slides into its new shape; the ends
--- (the target, and near you) barely move because both routes share them.
local function blendRoute(now: number)
	local alpha = math.clamp((now - blendAt) / ROUTE_BLEND, 0, 1)
	if alpha >= 1 or #fromRoute < 2 then
		if #route ~= #baseRoute or route[#route] ~= baseRoute[#baseRoute] or route[1] ~= baseRoute[1] then
			fill(route, routeLen, baseRoute)
		end
		return
	end
	local eased = 1 - (1 - alpha) * (1 - alpha)
	local baseTotal = baseLen[#baseLen] or 0
	local fromTotal = fromLen[#fromLen] or 0
	local mixed: { Vector3 } = {}
	for i, p in baseRoute do
		local fromEnd = baseTotal - baseLen[i]
		local old = alongIn(fromRoute, fromLen, math.max(0, fromTotal - fromEnd))
		table.insert(mixed, old:Lerp(p, eased))
	end
	fill(route, routeLen, mixed)
end

--- How far along the route the point nearest `p` is, in studs, measured flat. Only the
--- first PROJECT_REACH studs are searched: a route that doubles back past you must not
--- let your nearest point jump to its far end.
local PROJECT_REACH = 60

local function project(p: Vector3): (number, number)
	local best, bestDist = 0, math.huge
	for i = 2, #route do
		if routeLen[i - 1] > PROJECT_REACH then
			break
		end
		local a, b = route[i - 1], route[i]
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
		local len2 = ab:Dot(ab)
		local t = if len2 > 1e-6 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
		local dist = (ap - ab * t).Magnitude
		if dist < bestDist then
			best, bestDist = routeLen[i - 1] + t * (routeLen[i] - routeLen[i - 1]), dist
		end
	end
	return best, bestDist
end

--- Lay the ribbon along `route`: one flat slab per leg, and a flat disc at each real
--- bend so the corner reads as one strip. Pathfinding hands back a waypoint every 4
--- studs even on a straight run, and every seam between two see-through slabs shows
--- as a darker blot where they overlap, so straight runs are merged into one leg
--- first (simplify).
local BEND_DOT = math.cos(math.rad(10))

local function simplify(points: { Vector3 }): { Vector3 }
	if #points <= 2 then
		return points
	end
	local out = { points[1] }
	for i = 2, #points - 1 do
		local a, b, c = out[#out], points[i], points[i + 1]
		local ab, bc = b - a, c - b
		local straight = ab.Magnitude > 1e-3
			and bc.Magnitude > 1e-3
			and ab.Unit:Dot(bc.Unit) >= BEND_DOT
		if not straight then
			table.insert(out, b)
		end
	end
	table.insert(out, points[#points])
	return out
end

--- Drawn from `start` studs along the route to its end, every frame: the near end
--- follows you as you walk instead of snapping forward each time a new route lands. A
--- simplified route is a handful of legs, so resizing them per frame costs nothing.
local function drawRibbon(start: number)
	local folder = ensureGuide()
	local view: { Vector3 } = {}
	if #route > 1 and start < (routeLen[#routeLen] or 0) then
		table.insert(view, (along(start)))
		for i = 2, #route do
			if routeLen[i] > start + 0.05 then
				table.insert(view, route[i])
			end
		end
	end
	local legs = math.max(0, #view - 1)
	liveLegs, liveJoints = legs, math.max(0, legs - 1)
	for i = 1, legs do
		local a, b = view[i], view[i + 1]
		local slab = ribbonPool[i]
		if slab == nil then
			slab = localPart("Ribbon", folder)
			slab.Color = SKIN.amber
			ribbonPool[i] = slab
		end
		local length = (b - a).Magnitude
		local mid = (a + b) / 2 + Vector3.new(0, RIBBON_LIFT, 0)
		slab.Size = Vector3.new(RIBBON_WIDTH, 0.06, math.max(length, 0.05))
		slab.CFrame = CFrame.lookAt(mid, b + Vector3.new(0, RIBBON_LIFT, 0))
		slab.Transparency = RIBBON_TRANSPARENCY

		if i > 1 then
			local joint = jointPool[i - 1]
			if joint == nil then
				joint = localPart("Joint", folder)
				joint.Shape = Enum.PartType.Cylinder
				joint.Color = SKIN.amber
				jointPool[i - 1] = joint
			end
			joint.Size = Vector3.new(0.06, RIBBON_WIDTH, RIBBON_WIDTH)
			joint.CFrame = CFrame.new(a + Vector3.new(0, RIBBON_LIFT - 0.005, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			joint.Transparency = RIBBON_TRANSPARENCY
		end
	end
	for i = legs + 1, #ribbonPool do
		ribbonPool[i].Transparency = 1
	end
	for i = liveJoints + 1, #jointPool do
		jointPool[i].Transparency = 1
	end
end

local function repath(from: Vector3, goal: Vector3)
	if pathBusy then
		return
	end
	pathBusy = true
	lastPathAt = os.clock()
	lastPathFrom = from
	task.spawn(function()
		local points: { Vector3 } = {}
		local ok = pcall(function()
			local path = PathfindingService:CreatePath({
				AgentRadius = 2,
				AgentHeight = 5,
				AgentCanJump = true,
				WaypointSpacing = 4,
			})
			path:ComputeAsync(from, goal)
			if path.Status == Enum.PathStatus.Success then
				for _, wp in path:GetWaypoints() do
					table.insert(points, wp.Position)
				end
			end
		end)
		if not ok or #points < 2 then
			-- No route (or a target inside something): a straight line, in 4-stud steps
			-- so it still hugs the floor on the way.
			table.clear(points)
			local flat = Vector3.new(goal.X - from.X, 0, goal.Z - from.Z)
			local steps = math.max(1, math.ceil(flat.Magnitude / 4))
			for i = 0, steps do
				table.insert(points, from + flat * (i / steps))
			end
		end

		-- The whole route, from your feet. The ribbon's start is cut off per frame
		-- (drawRibbon), measured from where you are NOW rather than where you were when
		-- this was asked for.
		for i, p in points do
			points[i] = floorAt(p)
		end

		pathBusy = false
		if target == nil or (target - goal).Magnitude > 0.5 then
			return -- the step moved on while this was computing
		end
		-- Blend from whatever is on screen right now (itself possibly mid-blend).
		if #route > 1 then
			fill(fromRoute, fromLen, route)
			blendAt = os.clock()
		else
			table.clear(fromRoute)
			table.clear(fromLen)
		end
		fill(baseRoute, baseLen, simplify(points))
		head = -1
	end)
end

--- Once a frame while a step with a target is up: move the chevrons along the
--- ribbon, pulse the ring, bob the marker, and ask for a new route when it is due.
local function stepGuide(dt: number)
	local s = state
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if s == nil or root == nil then
		return
	end

	local goal = targetFor(s.step, root.Position)
	if goal == nil then
		if guide then
			clearGuide()
		end
		return
	end

	local folder = ensureGuide()
	local fresh = floorAt(goal)
	if target == nil or (target - fresh).Magnitude > RETARGET then
		-- The old route stays drawn until the new one lands (repath), so a moved goal
		-- bends the trail rather than blinking it out and back.
		target = fresh
		lastPathAt = -math.huge
		lastPathFrom = nil
	end
	local ground = target :: Vector3

	local now = os.clock()
	blendRoute(now)

	local from = root.Position - Vector3.new(0, 2.5, 0)
	local onRoute, offBy = project(root.Position)
	local since = now - lastPathAt
	local moved = lastPathFrom == nil or (from - lastPathFrom).Magnitude >= REPATH_MOVE
	local strayed = #route < 2 or offBy > OFF_ROUTE
	if moved and (since >= REPATH_SECONDS or (strayed and since >= OFF_ROUTE_SECONDS)) then
		repath(from, ground)
	end
	local flatDist = Vector3.new(ground.X - root.Position.X, 0, ground.Z - root.Position.Z).Magnitude
	local arrived = flatDist <= ARRIVED

	-- The ring on the floor at the target.
	if ring == nil then
		ring = buildRing(folder)
	end
	local ringPart = ring :: BasePart
	ringPart.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0))
	for i, pulse in ringPulses do
		local t = (now * 0.9 + (i - 1) * 0.5) % 1
		pulse.Size = UDim2.fromScale(0.45 + 0.55 * t, 0.45 + 0.55 * t)
		local stroke = pulse:FindFirstChild("Stroke") :: UIStroke
		stroke.Transparency = t
	end

	-- The marker, with the distance in the HUD's own metres.
	if marker == nil then
		local m, label = buildMarker(folder)
		marker, markerLabel = m, label
	end
	placeMarker(marker :: Model, ground, now)
	if markerLabel then
		markerLabel.Text = `{math.floor(flatDist / Stages.STUDS_PER_METRE + 0.5)}m`
	end

	-- Where you are on the route, eased so a step or a wobble does not jitter the
	-- ribbon's start; snapped straight on for a route that has just arrived.
	local total = routeLen[#routeLen] or 0
	if head < 0 then
		head = onRoute
	else
		head += (onRoute - head) * (1 - math.exp(-HEAD_EASE * dt))
	end
	local start = math.min(head + TRAIL_START, total)
	drawRibbon(start)

	-- Chevrons running along the ribbon toward the target, COUNTED BACK FROM THE END
	-- rather than out from the start. The target end is the part of the route that
	-- stays put when a fresh route replaces the old one, or when the start slides
	-- with you, so the arrows keep flowing instead of all jumping at once.
	local visibleLen = total - CHEVRON_END_PAD - start
	local wanted = if arrived or visibleLen < 1 then 0 else math.min(CHEVRON_MAX, math.floor(visibleLen / CHEVRON_GAP) + 1)
	while #chevrons < wanted do
		local arms = {}
		for _ = 1, 2 do
			local arm = localPart("Chevron", folder)
			arm.Color = SKIN.cream
			arm.Size = Vector3.new(0.34, 0.07, CHEVRON_ARM)
			arm.Transparency = 1
			table.insert(arms, arm)
		end
		table.insert(chevrons, arms)
	end
	local phase = (now * CHEVRON_SPEED) % CHEVRON_GAP
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local sa, ca = math.sin(CHEVRON_ANGLE), math.cos(CHEVRON_ANGLE)
	local back = CHEVRON_ARM / 2
	local tip = CFrame.new(0, 0, -0.5)
	for i, arms in chevrons do
		local d = total - CHEVRON_END_PAD - (i - 1) * CHEVRON_GAP - (CHEVRON_GAP - phase)
		if i > wanted or d < start then
			arms[1].Transparency = 1
			arms[2].Transparency = 1
			continue
		end
		local p, dir = along(d)
		-- Fade in over the first two studs of ribbon and out over the last arrow gap.
		local fade = math.clamp(math.min((d - start) / 2, (total - CHEVRON_END_PAD - d) / CHEVRON_GAP * 3), 0, 1)
		local lifted = p + Vector3.new(0, RIBBON_LIFT + 0.05, 0)
		local base = CFrame.lookAt(lifted, lifted + dir)
		table.insert(parts, arms[1])
		table.insert(cframes, base * tip * CFrame.new(-sa * back, 0, ca * back) * CFrame.Angles(0, -CHEVRON_ANGLE, 0))
		table.insert(parts, arms[2])
		table.insert(cframes, base * tip * CFrame.new(sa * back, 0, ca * back) * CFrame.Angles(0, CHEVRON_ANGLE, 0))
		arms[1].Transparency = 1 - 0.95 * fade
		arms[2].Transparency = 1 - 0.95 * fade
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end

	setGuideVisible(not arrived and liveLegs > 0, true, not arrived)
end

-- ── State ───────────────────────────────────────────────────────────────────────
local function apply(payload: any)
	if type(payload) ~= "table" or Tutorial.STEPS[payload.step] == nil then
		state = nil
		ui.banner.Visible = false
		setHaulRing(false)
		clearGuide()
		return
	end

	local previous = state
	state = { step = payload.step, holding = payload.holding ~= false, plot = payload.plot }
	if previous == nil or previous.step ~= payload.step then
		clearGuide()
	end

	if payload.step == "finish" then
		state = nil
		setHaulRing(false)
		clearGuide()
		showFinish()
		return
	end

	setBanner(payload.step)
	setHaulRing(payload.step == "haul")
end

function TutorialController.init() end

function TutorialController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Over the warp bar (90) and under the stage-name card (95): the two share the
	-- top of the screen only in passing, and the stage name should win that moment.
	gui.DisplayOrder = 92
	gui.Parent = player:WaitForChild("PlayerGui")

	local canvas = UIKit.canvas(gui)
	buildBanner(canvas)
	buildFinish(canvas)

	Net.get("TutorialState").OnClientEvent:Connect(apply)

	RunService.RenderStepped:Connect(function(dt)
		if state == nil then
			return
		end
		-- The haul panel is built lazily; keep trying until the ring finds its button.
		if state.step == "haul" and haulRing == nil then
			setHaulRing(true)
		end
		if haulRing then
			local stroke = haulRing:FindFirstChild("Stroke") :: UIStroke?
			if stroke then
				local t = (math.sin(os.clock() * 5) + 1) / 2
				stroke.Thickness = 3 + 3 * t
				stroke.Transparency = 0.35 * (1 - t)
			end
		end
		local ok, err = pcall(stepGuide, dt)
		if not ok then
			warn(`[tutorial] guide step failed: {err}`)
		end
	end)
end

return TutorialController
