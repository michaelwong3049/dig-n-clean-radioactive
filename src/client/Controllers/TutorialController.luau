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
	    haul     banner + an amber ring pulsing round REEL IN, and arrows bouncing at it
	    clean    banner + trail to YOUR cleansing station
	    place    banner + trail to the middle of your base's open floor
	    upgrade  banner + trail to the Detector Shop
	    navigate banner + rings and arrows on the HOME and SHOPS buttons (WarpController);
	             using one ends the walkthrough (no "You're set!" card, removed on request)

	THE TRAIL IS CLIENT-ONLY PARTS in a local Workspace folder, so nobody else sees
	anyone's trail. The route is PathfindingService's, recomputed every couple of seconds
	while you move (sooner once you stray), and it falls back to a straight line when
	there is no path (the target inside a tub, say). The ribbon's near end is joined to
	your feet every frame, straight to the furthest corner you have a clear line to
(SIGHT_*), so it moves with you, never with the repaths.
	Every ribbon point is raycast onto whatever floor is really there. It is built from plain parts and a SurfaceGui, with no uploaded
	textures, and no Neon: it is guidance, not an effect.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local ProximityPromptService = game:GetService("ProximityPromptService")
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
	headline = Enum.Font.FredokaOne, -- on request, over LuckiestGuy
	label = Enum.Font.FredokaOne,
}

-- ── Banner layout (design px on the 1280x720 canvas) ─────────────────────────────
-- The words sit on a see-through black pill (ON REQUEST, over the earlier text-only
-- banner, then made roomier) in Fredoka One and sentence case (both on request, over
-- all-caps LuckiestGuy), with no hint line under them, and low enough to clear
-- WarpController's HOME / SHOPS portals (y 10..74). The pill is the frame named
-- "Banner", sized to the words plus SKIP, because StageBannerController and
-- AuraWarningController read its rect to stack themselves underneath it.
-- ON REQUEST (from a reference shot): the pill became a FULL-WIDTH dark band that
-- fades out to both screen edges, with big white words in a heavy black outline.
local BANNER_Y = 114 -- ON REQUEST: nudged down from 98
local BANNER_H = 96
local BANNER_SHADE = 0.35 -- the band's BackgroundTransparency at its middle
local BANNER_FADE = 0.28 -- fraction of the width each side spends fading out
local TITLE_SIZE = 56
local SKIP_W = 64
local SKIP_GAP = 18
local SKIP_CONFIRM_SECONDS = 3

-- ── Pointing arrows (design px) ────────────────────────────────────────────────────
-- ON REQUEST: fat amber arrows with a black outline, bouncing at what to press: REEL IN
-- on the haul step, HOME and SHOPS on the last one. Built from rounded bars (a shaft and
-- two arms), the outline being the same bars a size up in black underneath, so the
-- joins read as one shape. No uploaded art.
local ARROW_LEN = 58 -- tail to tip
local ARROW_THICK = 11
local ARROW_ARM = 28
local ARROW_OUTLINE = 3
local ARROW_GAP = 8 -- tip to the thing it points at, at rest
local ARROW_BOB = 9 -- how far it bounces toward it
local ARROW_BOB_SPEED = 6 -- radians per second

-- ── Trail ───────────────────────────────────────────────────────────────────────
local RIBBON_WIDTH = 2.6
local RIBBON_LIFT = 0.12 -- over the floor, clear of z-fighting
local RIBBON_TRANSPARENCY = 1 -- ON REQUEST: no amber ribbon, the chevrons alone are the trail
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
local REPATH_SECONDS = 1.2
local REPATH_MOVE = 3 -- studs moved before a repath is worth it
local OFF_ROUTE = 4
local OFF_ROUTE_SECONDS = 0.5
-- A new route does not replace the old one in a frame: every point glides from where
-- the old route had it (matched by distance from the target) to its new place.
local ROUTE_BLEND = 0.35
-- How fast the point where the ribbon joins the route catches up with where you are
-- on it (per second, exponential). High enough to feel attached, low enough to
-- swallow a step's wobble or a fresh route's different length.
local HEAD_EASE = 10
-- THE RIBBON IS JOINED TO YOUR FEET EVERY FRAME (ON REQUEST: it used to sit on the last
-- computed route and catch up only when the next one landed, which read as a trail
-- that jumped every half second). It runs from your feet to the route JOIN_AHEAD studs
-- past the point you are level with, then follows the route. Pathfinding only shapes
-- the far part, so a slow or late route never holds the near end still.
local JOIN_AHEAD = 6
-- LINE OF SIGHT (ON REQUEST: the arrows have to point where you really need to go and
-- follow you live). Pathfinding's 4-stud grid left the arrows wandering a couple of
-- studs off the true line and a few degrees off the goal. So every route is pulled
-- tight (pullTight) to straight runs wherever nothing solid is in the way, and EVERY
-- FRAME the trail runs from your feet straight to the furthest corner of the route you
-- have a clear line to, which is usually the target itself. The test is a sphere swept
-- at waist height that only collidable parts can stop, so kerbs and see-through props
-- don't count but walls and fences do.
local SIGHT_LIFT = 2.4
local SIGHT_RADIUS = 1.2
local SIGHT_CHECKS = 6 -- corners tested per frame, furthest first
local PULL_WINDOW = 16 -- waypoints looked ahead per corner when pulling a route tight
local SIGHT_EASE = 16 -- how fast the trail swings to a newly seen corner (per second)
-- The last arrow stops this far short of the route's end, clear of the ring.
local CHEVRON_END_PAD = 1.5
local CHEVRON_GAP = 4
local CHEVRON_SPEED = 7 -- studs/sec along the ribbon
local CHEVRON_MAX = 28
-- ON REQUEST (from a reference shot): fat, flat, glowing white chevrons, like arrow
-- decals lit from below. Neon is the exception to "guidance, not an effect" here.
-- ON REQUEST (stronger): bigger and fully opaque, with a dark outline (one Highlight
-- over all of them) so they read on pale floors too.
local CHEVRON_ARM = 2.6
local CHEVRON_THICK = 1
local CHEVRON_ANGLE = math.rad(45)
local CHEVRON_PARK = CFrame.new(0, -5000, 0) -- where unused arrows wait, out of the outline
local RING_SIZE = 9
local MARKER_HEIGHT = 8 -- over the target's floor
local GUIDE_FOLDER = "TutorialGuide"

type State = { step: Tutorial.StepId, holding: boolean, plot: number? }

local state: State? = nil

-- ── UI ──────────────────────────────────────────────────────────────────────────
local ui: any = {}

local function buildBanner(canvas: Frame)
	-- The pill sizes ITSELF to the words and SKIP (AutomaticSize + a row layout).
	-- Measuring with TextService does not work here: it answers with the fallback
	-- font's width until Fredoka One has loaded, and the words overran the pill.
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, BANNER_Y)
	banner.Size = UDim2.new(1, 0, 0, BANNER_H)
	banner.BackgroundColor3 = Color3.new(0, 0, 0)
	banner.BackgroundTransparency = BANNER_SHADE
	banner.BorderSizePixel = 0
	banner.Visible = false
	banner.Parent = canvas
	-- Solid in the middle, see-through at both edges.
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(BANNER_FADE, 0),
		NumberSequenceKeypoint.new(1 - BANNER_FADE, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = banner
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, SKIP_GAP)
	row.Parent = banner

	local scale = Instance.new("UIScale")
	scale.Parent = banner

	-- UIKit's default outline and drop shadow keep the words crisp on the pill.
	local title = UIKit.label(banner, {
		name = "Title",
		size = UDim2.fromScale(0, 1),
		font = SKIN.headline,
		textSize = TITLE_SIZE,
		color = SKIN.text,
		xAlign = Enum.TextXAlignment.Center,
		text = "",
	})
	title.AutomaticSize = Enum.AutomaticSize.X
	title.LayoutOrder = 1
	-- A heavier outline than UIKit's default, as in the reference.
	for _, d in title:GetDescendants() do
		if d:IsA("UIStroke") then
			d.Thickness = math.max(d.Thickness, 4)
		end
	end
	local own = title:FindFirstChildOfClass("UIStroke")
	if own then
		own.Thickness = math.max(own.Thickness, 4)
	end

	-- SKIP sits at the pill's right end, after the words. It needs a second press: one
	-- stray click should not throw away a new player's only walkthrough.
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.LayoutOrder = 2
	skip.Size = UDim2.fromOffset(SKIP_W, 26)
	skip.AutoButtonColor = true
	skip.BackgroundColor3 = SKIN.button
	skip.BorderSizePixel = 0
	skip.Font = SKIN.label
	skip.TextSize = 14
	skip.TextColor3 = SKIN.dim
	skip.Text = "Skip"
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
			skip.Text = "Skip"
			return
		end
		armedAt = now
		skip.Text = "Sure?"
		skip.TextColor3 = SKIN.amber
		task.delay(SKIP_CONFIRM_SECONDS, function()
			if os.clock() - armedAt >= SKIP_CONFIRM_SECONDS then
				skip.Text = "Skip"
				skip.TextColor3 = SKIN.dim
			end
		end)
	end)

	ui.banner = banner
	ui.bannerScale = scale
	ui.title = title
end

local function setBanner(step: Tutorial.StepId)
	local def = Tutorial.STEPS[step]
	local changed = ui.title.Text ~= def.title
	-- The pill resizes itself round the new words (buildBanner).
	ui.title.Text = def.title

	local wasHidden = not ui.banner.Visible
	ui.banner.Visible = true
	if changed or wasHidden then
		ui.bannerScale.Scale = 0.8
		TweenService:Create(ui.bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- ── Pointers on screen buttons ───────────────────────────────────────────────────
-- A pulsing amber ring round a button plus arrows bouncing at it, all CHILDREN of that
-- button (REEL IN in DetectorHud, HOME / SHOPS in WarpBar), so they follow it wherever
-- it is laid out and hide with it, with no rect math.

--- Which way an arrow points, as the screen direction from its tail to its tip.
type Facing = "down" | "left" | "right"

--- A rounded bar, `len` long along its local Y, centred on `at` (px in the arrow's box).
local function bar(parent: Instance, at: Vector2, len: number, thick: number, rotation: number, color: Color3, z: number)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(at.X, at.Y)
	f.Size = UDim2.fromOffset(thick, len)
	f.Rotation = rotation
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	f.Parent = parent
end

--- An arrow pointing DOWN in its own box (tip at the bottom middle), turned to `facing`.
--- The box is square so a turn keeps it where it was put.
local function buildArrow(parent: GuiObject, facing: Facing): Frame
	local box = Instance.new("Frame")
	box.Name = "TutorialArrow"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(ARROW_LEN, ARROW_LEN)
	box.Rotation = if facing == "left" then 90 elseif facing == "right" then -90 else 0
	local tip = Vector2.new(ARROW_LEN / 2, ARROW_LEN - ARROW_THICK / 2)
	local s45 = math.sin(math.rad(45))
	local z = parent.ZIndex + 3
	for layer = 1, 2 do
		local grow = if layer == 1 then ARROW_OUTLINE * 2 else 0
		local color = if layer == 1 then SKIN.ink else SKIN.amber
		local thick = ARROW_THICK + grow
		local zLayer = z + layer - 1
		-- The shaft, from the top of the box down to the tip.
		local shaftLen = ARROW_LEN - ARROW_THICK / 2 + grow
		bar(box, Vector2.new(tip.X, tip.Y - (ARROW_LEN - ARROW_THICK) / 2), shaftLen, thick, 0, color, zLayer)
		-- Two arms rising back from the tip at 45 degrees.
		local half = (ARROW_ARM - ARROW_THICK) / 2
		bar(box, tip + Vector2.new(-half * s45, -half * s45), ARROW_ARM + grow, thick, -45, color, zLayer)
		bar(box, tip + Vector2.new(half * s45, -half * s45), ARROW_ARM + grow, thick, 45, color, zLayer)
	end
	box.Parent = parent
	return box
end

type Pointer = {
	ring: Frame,
	arrows: { { box: Frame, facing: Facing } },
}

local function buildPointer(button: GuiObject, facings: { Facing }, round: boolean): Pointer
	local ring = Instance.new("Frame")
	ring.Name = "TutorialRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, 18, 1, 18)
	ring.BackgroundTransparency = 1
	ring.ZIndex = button.ZIndex + 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0, 16)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = SKIN.amber
	stroke.Thickness = 4
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	ring.Parent = button
	local arrows = {}
	for _, facing in facings do
		table.insert(arrows, { box = buildArrow(button, facing), facing = facing })
	end
	return { ring = ring, arrows = arrows }
end

local function destroyPointer(pointer: Pointer)
	pointer.ring:Destroy()
	for _, arrow in pointer.arrows do
		arrow.box:Destroy()
	end
end

--- One frame of a pointer: the ring breathes, the arrows bounce in at the button.
local function stepPointer(pointer: Pointer, t: number)
	local pulse = (math.sin(t * 5) + 1) / 2
	local stroke = pointer.ring:FindFirstChild("Stroke") :: UIStroke?
	if stroke then
		stroke.Thickness = 3 + 3 * pulse
		stroke.Transparency = 0.35 * (1 - pulse)
	end
	-- Out at ARROW_GAP + ARROW_BOB, a quick tap in to ARROW_GAP, and back out.
	local bob = ARROW_GAP + ARROW_BOB * (1 - math.abs(math.sin(t * ARROW_BOB_SPEED / 2)))
	for _, arrow in pointer.arrows do
		local box = arrow.box
		if arrow.facing == "down" then
			-- Above the button, pointing down at it.
			box.AnchorPoint = Vector2.new(0.5, 1)
			box.Position = UDim2.new(0.5, 0, 0, -bob)
		elseif arrow.facing == "right" then
			-- Left of the button, pointing right at it.
			box.AnchorPoint = Vector2.new(1, 0.5)
			box.Position = UDim2.new(0, -bob, 0.5, 0)
		else
			-- Right of the button, pointing left at it.
			box.AnchorPoint = Vector2.new(0, 0.5)
			box.Position = UDim2.new(1, bob, 0.5, 0)
		end
	end
end

-- REEL IN, on the haul step: the ring, an arrow from above and one from the right.
local haulPointer: Pointer? = nil

local function setHaulRing(on: boolean)
	if not on then
		if haulPointer then
			destroyPointer(haulPointer)
			haulPointer = nil
		end
		return
	end
	if haulPointer and haulPointer.ring.Parent then
		return
	end
	local hud = player:FindFirstChildOfClass("PlayerGui") and player.PlayerGui:FindFirstChild("DetectorHud")
	local button = hud and hud:FindFirstChild("HaulButton", true)
	if button == nil or not button:IsA("GuiObject") then
		return
	end
	haulPointer = buildPointer(button, { "down", "left" }, false)
end

-- HOME and SHOPS, on the last step: each ringed, with an arrow coming in from the
-- outside of the pair (HOME's from the left, SHOPS' from the right).
local navPointers: { Pointer }? = nil

local function setNavPointers(on: boolean)
	if not on then
		if navPointers then
			for _, pointer in navPointers do
				destroyPointer(pointer)
			end
			navPointers = nil
		end
		return
	end
	if navPointers and navPointers[1].ring.Parent then
		return
	end
	local warpBar = player:FindFirstChildOfClass("PlayerGui") and player.PlayerGui:FindFirstChild("WarpBar")
	local home = warpBar and warpBar:FindFirstChild("HOME", true)
	local shops = warpBar and warpBar:FindFirstChild("SHOPS", true)
	if home == nil or shops == nil or not home:IsA("GuiObject") or not shops:IsA("GuiObject") then
		return
	end
	navPointers = { buildPointer(home, { "right" }, true), buildPointer(shops, { "left" }, true) }
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
-- The chevrons live in one Model so a single Highlight outlines all of them.
local arrows: Model? = nil
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
--- How much of `route` is left from the point you are level with, eased, in studs.
--- Measured from the END because that is what a new route shares with the old one
--- (blendRoute matches points by distance from the target), so it stays continuous
--- when a route is replaced. -1 means "not measured yet".
local headLeft = -1
--- Where the ribbon meets the route, in the world, eased (HEAD_EASE). A fresh route can
--- lie a few studs to one side of the old one near you; this glides across instead.
local joinPoint: Vector3? = nil
--- What is drawn this frame: from TRAIL_START ahead of your feet to the target, with
--- the running length at each point. Rebuilt every frame by buildView.
local view: { Vector3 } = {}
local viewLen: { number } = {}

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
	local model = Instance.new("Model")
	model.Name = "Arrows"
	local outline = Instance.new("Highlight")
	outline.FillTransparency = 1
	outline.OutlineColor = SKIN.ink
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model
	model.Parent = folder
	arrows = model
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

	local depth, headH, headHalfW = 1.2, 2.8, 2.1
	local shaft = localPart("Shaft", model)
	shaft.Size = Vector3.new(depth, 2.4, 1.6)
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
	local outline = arrows and arrows:FindFirstChildOfClass("Highlight")
	if outline then
		outline.Enabled = showRibbon
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
	arrows = nil
	table.clear(route)
	table.clear(routeLen)
	table.clear(baseRoute)
	table.clear(baseLen)
	table.clear(fromRoute)
	table.clear(fromLen)
	table.clear(view)
	table.clear(viewLen)
	blendAt = -math.huge
	liveLegs, liveJoints = 0, 0
	headLeft = -1
	joinPoint = nil
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

-- Line of sight: only collidable parts block it (RespectCanCollide), so the guide's
-- own parts, see-through Display cubes and decor that players walk through never do.
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.RespectCanCollide = true

--- Keep every character out of the sight tests. Called before each batch of them.
local function refreshSight()
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	sightParams.FilterDescendantsInstances = ignore
end

--- Could you walk straight from floor point `a` to floor point `b`? A sphere swept at
--- waist height: walls and fences stop it, kerbs and steps below it do not.
local function clearLine(a: Vector3, b: Vector3): boolean
	local lift = Vector3.new(0, SIGHT_LIFT, 0)
	local delta = b - a
	if delta.Magnitude < 0.5 then
		return true
	end
	return Workspace:Spherecast(a + lift, SIGHT_RADIUS, delta, sightParams) == nil
end

--- The floor right under an arrow, one ray, so arrows on a straight run over a bump
--- or a step sit on it instead of sinking in or floating.
local function snapFloor(p: Vector3): Vector3
	local hit = Workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -7, 0), sightParams)
	return if hit then hit.Position else p
end

--- Pull a pathfinding route tight: from each corner, jump to the furthest later
--- waypoint (up to PULL_WINDOW ahead) with a clear straight line to it. What is left
--- is the real corners, joined by true straight runs.
local function pullTight(points: { Vector3 }): { Vector3 }
	if #points <= 2 then
		return points
	end
	refreshSight()
	local out = { points[1] }
	local i = 1
	while i < #points do
		local k = i + 1
		for j = math.min(#points, i + PULL_WINDOW), i + 2, -1 do
			if clearLine(points[i], points[j]) then
				k = j
				break
			end
		end
		table.insert(out, points[k])
		i = k
	end
	return out
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
	elseif step == "dig" then
		-- The tutorial's one spot (DigService, Tutorial.DIG_SPOT_IN): it is the only
		-- signal your detector reads until it is dug, so the arrows lead straight to it.
		local spot = player:GetAttribute("TutorialDigSpot")
		return if typeof(spot) == "Vector3" then spot else nil
	elseif step == "clean" then
		local plot = plotModel()
		local spot = plot and (plot:FindFirstChild("WashSpot", true) or plot:FindFirstChild("WashStand", true))
		return if spot and spot:IsA("BasePart") then spot.Position else nil
	elseif step == "place" then
		-- The middle of your base's open floor: the nuke goes down wherever you click.
		local plot = plotModel()
		local pad = plot and plot:FindFirstChild("Pad")
		return if pad and pad:IsA("BasePart") then pad.Position + Vector3.new(0, pad.Size.Y / 2, 0) else nil
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

--- Build this frame's `view`: your feet, straight to `join` (on the route `joinAt` studs
--- along it, give or take its easing), then the rest of the route, with the first
--- TRAIL_START studs cut off so it never draws under you.
local function buildView(feet: Vector3, join: Vector3, joinAt: number)
	local total = routeLen[#routeLen] or 0
	local raw: { Vector3 } = { feet }
	if #route > 1 then
		table.insert(raw, join)
		for i = 2, #route do
			if routeLen[i] > joinAt + 0.05 then
				table.insert(raw, route[i])
			end
		end
	elseif total <= 0 and target then
		table.insert(raw, target)
	end
	local lens: { number } = { 0 }
	for i = 2, #raw do
		lens[i] = lens[i - 1] + (raw[i] - raw[i - 1]).Magnitude
	end

	table.clear(view)
	table.clear(viewLen)
	local rawTotal = lens[#lens] or 0
	if #raw < 2 or rawTotal <= TRAIL_START then
		return
	end
	local cut = {}
	table.insert(cut, (alongIn(raw, lens, TRAIL_START)))
	for i = 2, #raw do
		if lens[i] > TRAIL_START + 0.05 then
			table.insert(cut, raw[i])
		end
	end
	fill(view, viewLen, cut)
end

--- Lay the ribbon along `view`, every frame: the near end follows you as you walk
--- instead of waiting for a new route. A simplified route is a handful of legs, so
--- resizing them per frame costs nothing.
local function drawRibbon()
	local folder = ensureGuide()
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
		-- headLeft is NOT reset: it is measured from the target, which both routes share.
		fill(baseRoute, baseLen, simplify(pullTight(points)))
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

	-- Where you are on the route (as route LEFT, see headLeft), eased so a step, a
	-- wobble or a fresh route of a different length slides the join rather than
	-- snapping it. The ribbon itself starts at your feet this frame regardless.
	local routeTotal = routeLen[#routeLen] or 0
	local left = math.max(0, routeTotal - onRoute)
	if headLeft < 0 then
		headLeft = left
	else
		headLeft += (left - headLeft) * (1 - math.exp(-HEAD_EASE * dt))
	end
	local joinAt = math.clamp(routeTotal - (headLeft - JOIN_AHEAD), 0, routeTotal)
	local joinWanted = along(joinAt)
	local ease = HEAD_EASE
	-- Your feet's height from the character itself, not a raycast: a ray here lands on
	-- every pebble and fence rail you pass and pops the ribbon's end up and down.
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 2
	local feet = root.Position - Vector3.new(0, root.Size.Y / 2 + hip, 0)
	-- LIVE LINE OF SIGHT: the furthest of the next few corners ahead of you that you
	-- could walk straight to. The trail runs dead straight at it from wherever you are
	-- this frame, so it swings with you as you walk, and on an open run that corner
	-- is the target itself.
	refreshSight()
	local checked = 0
	for i = 2, #route do
		if routeLen[i] > onRoute + 0.5 then
			if checked >= SIGHT_CHECKS then
				break
			end
			checked += 1
			if clearLine(feet, route[i]) then
				joinWanted, joinAt, ease = route[i], routeLen[i], SIGHT_EASE
			end
		end
	end
	local joinNow = joinPoint
	if joinNow == nil then
		joinNow = joinWanted
	else
		joinNow = joinNow:Lerp(joinWanted, 1 - math.exp(-ease * dt))
	end
	joinPoint = joinNow
	buildView(feet, joinNow, joinAt)
	drawRibbon()

	-- Chevrons running along the ribbon toward the target, COUNTED BACK FROM THE END
	-- rather than out from the start. The target end is the part of the route that
	-- stays put when a fresh route replaces the old one, or when the start slides
	-- with you, so the arrows keep flowing instead of all jumping at once.
	local total = viewLen[#viewLen] or 0
	local start = 0
	local visibleLen = total - CHEVRON_END_PAD - start
	local wanted = if arrived or visibleLen < 1 then 0 else math.min(CHEVRON_MAX, math.floor(visibleLen / CHEVRON_GAP) + 1)
	while #chevrons < wanted do
		local arms = {}
		for _ = 1, 2 do
			local arm = localPart("Chevron", arrows or folder)
			arm.Color = Color3.fromHex("F4FFE8")
			arm.Material = Enum.Material.Neon
			arm.Size = Vector3.new(CHEVRON_THICK, 0.07, CHEVRON_ARM)
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
			-- Parked out of sight too: the outline would still trace an invisible arm.
			for _, arm in arms do
				arm.Transparency = 1
				table.insert(parts, arm)
				table.insert(cframes, CHEVRON_PARK)
			end
			continue
		end
		local p, dir = alongIn(view, viewLen, d)
		p = snapFloor(p)
		-- Fade in over the first two studs of ribbon and out over the last arrow gap.
		local fade = math.clamp(math.min((d - start) / 2, (total - CHEVRON_END_PAD - d) / CHEVRON_GAP * 3), 0, 1)
		local lifted = p + Vector3.new(0, RIBBON_LIFT + 0.05, 0)
		local base = CFrame.lookAt(lifted, lifted + dir)
		table.insert(parts, arms[1])
		table.insert(cframes, base * tip * CFrame.new(-sa * back, 0, ca * back) * CFrame.Angles(0, -CHEVRON_ANGLE, 0))
		table.insert(parts, arms[2])
		table.insert(cframes, base * tip * CFrame.new(sa * back, 0, ca * back) * CFrame.Angles(0, CHEVRON_ANGLE, 0))
		arms[1].Transparency = 1 - fade
		arms[2].Transparency = 1 - fade
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
		setNavPointers(false)
		clearGuide()
		return
	end

	local previous = state
	state = { step = payload.step, holding = payload.holding ~= false, plot = payload.plot }
	if previous == nil or previous.step ~= payload.step then
		clearGuide()
	end

	setBanner(payload.step)
	setHaulRing(payload.step == "haul")
	setNavPointers(payload.step == "navigate")
end

-- ── Shut prompts ──────────────────────────────────────────────────────────────────
-- ON REQUEST: the shops, Trader, locker and the rest are shut while the walkthrough
-- runs (Config/Tutorial.promptOpen). The server already refuses them. This hides
-- their prompts too, so nobody sees an E that does nothing. A prompt is caught the
-- moment it would show and disabled LOCALLY. Each one is remembered, so the step
-- that opens it (the Detector shop on "upgrade") or the end of the walkthrough can
-- switch it back on.
local shutPrompts: { [ProximityPrompt]: true } = {}

local function reopenPrompts()
	for prompt in shutPrompts do
		if prompt.Parent == nil then
			shutPrompts[prompt] = nil
		elseif Tutorial.promptOpen(player, prompt) then
			shutPrompts[prompt] = nil
			prompt.Enabled = true
		end
	end
end

local function watchPrompts()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if not Tutorial.promptOpen(player, prompt) then
			shutPrompts[prompt] = true
			prompt.Enabled = false
		end
	end)
	player:GetAttributeChangedSignal("TutorialActive"):Connect(reopenPrompts)
	player:GetAttributeChangedSignal("TutorialStep"):Connect(reopenPrompts)
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

	Net.get("TutorialState").OnClientEvent:Connect(apply)
	watchPrompts()

	RunService.RenderStepped:Connect(function(dt)
		if state == nil then
			return
		end
		-- The haul panel and the warp bar are built lazily; keep trying until the
		-- pointers find their buttons.
		if state.step == "haul" and haulPointer == nil then
			setHaulRing(true)
		elseif state.step == "navigate" and navPointers == nil then
			setNavPointers(true)
		end
		local t = os.clock()
		if haulPointer then
			stepPointer(haulPointer, t)
		end
		if navPointers then
			for _, pointer in navPointers do
				stepPointer(pointer, t)
			end
		end
		local ok, err = pcall(stepGuide, dt)
		if not ok then
			warn(`[tutorial] guide step failed: {err}`)
		end
	end)
end

return TutorialController
