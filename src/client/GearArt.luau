--[[
	GearArt — a live 3D picture of one gear tier in a ViewportFrame.

	Lifted out of StationController when the Gear panel needed the same picture: the
	shop card's art well and the Gear panel's rows both draw the real model, from one
	shared hero angle, framed to fill its box. A LIVE RENDER, NOT AN UPLOADED
	PICTURE: every tier's model is already on the client (Assets/Tools for Detector and
	Magnet, Shared/ToolModels for the hose, AuraLook for the aura), so it cannot drift
	from the rack or the hand when a model is re-imported.

	The aura's atom moves on its own: it is tagged AuraLook.ICON_TAG, and AuraController
	circles the camera of whatever ViewportFrame it sits in. Gear pictures asked for
	`effects` (the shop card) also get their tier's ToolFX — sparks, glow, moving parts
	— redrawn by client/GearArtFx, since a ViewportFrame renders none of them.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AuraLook = require(Shared.AuraLook)
local MagnetHang = require(Shared.MagnetHang)
local ToolModels = require(Shared.ToolModels)
local ToolTiers = require(Shared.Config.ToolTiers)

local GearArtFx = require(script.Parent.GearArtFx)

local GearArt = {}

-- ONE HERO SHOT FOR EVERY TRACK (2026-10-04, on request: "a better and consistent
-- angle"). Each track used to be seen from its own direction — the detector side-on and
-- standing, the hose flat along the well, the magnet from above — so a row of cards read
-- as three different photographers, and the long thin tools filled a sliver of the
-- landscape well. Now every model is first turned into one shared DISPLAY POSE (`pose`,
-- applied about the model's pivot) and then shot from the same `from`: a three-quarter
-- view from the front-right, a little above. The pose lays each tool's long side on the
-- same rising diagonal (muzzle up-right for the hose, poles up and leaning right for the
-- magnet), the classic item-icon angle, so it fills the well and every card in the row
-- matches. The detector alone stands upright (see its row). `from` and `up` are in the
-- posed model's frame (its pivot at the origin).
type ArtView = { from: Vector3, up: Vector3, pose: CFrame }
local HERO_FROM = Vector3.new(0.5, 0.45, 1)
local ART_VIEW: { [string]: ArtView } = {
	-- Stands along Y with its display box on +X, coil at the bottom the way it is
	-- carried, seen nearly side-on from a little above (the user's pick of six mock-ups,
	-- "F"): the box to camera, and the coil lying flat on the ground under it. Leaning
	-- it onto the diagonal like the others read as fallen over.
	Detector = {
		from = Vector3.new(0, 0.25, 1),
		up = Vector3.yAxis,
		pose = CFrame.Angles(0, math.rad(-90), 0),
	},
	-- Lies flat with its arms along Z: stood up so the U opens upward, poles leaning right.
	Magnet = {
		from = HERO_FROM,
		up = Vector3.yAxis,
		pose = CFrame.Angles(0, 0, math.rad(-30)) * CFrame.Angles(math.rad(-90), 0, 0),
	},
	-- Barrel along Z, grip down: side to camera, muzzle raised 25deg to the right.
	Cleaner = {
		from = HERO_FROM,
		up = Vector3.yAxis,
		pose = CFrame.Angles(0, 0, math.rad(25)) * CFrame.Angles(0, math.rad(-90), 0),
	},
	-- Worn, not held, and AuraController circles this camera itself: nearly head on and
	-- a little above, so the flat ring reads as a ring and the tilted pair cross in front
	-- of the nucleus the way they do round a chest.
	Aura = { from = Vector3.new(0.25, 0.4, 1), up = Vector3.yAxis, pose = CFrame.identity },
}
-- A turn about the vertical, on top of the track's pose, for the odd tier whose head the
-- shared pose shows edge-on. The Aurora Rake (Detector 11) is a straight comb, not a
-- round coil, and the detector pose points its length straight at the camera, so it
-- read as a bare stick (2026-10-08, "fix the aurora rake positioning"). Turned 60deg it
-- shows the whole comb and keeps the row's lean.
local TIER_TURN: { [string]: { [number]: number } } = {
	Detector = { [11] = 60 },
}
-- Narrow, so a long detector does not bulge at the near end the way a wide lens makes
-- it; the camera just stands further back.
local ART_FOV = 25
-- How much bigger than the model the framed view is — the breathing room at the edges.
local ART_MARGIN = 1.12
-- The ViewportFrame's defaults (a 200 grey ambient under a 140 key) wash every tier out
-- to the same pale grey. A low ambient and a warm key over the camera's left shoulder
-- give the models back the colour that tells one tier from the next.
local ART_LIGHT = {
	ambient = Color3.fromRGB(90, 92, 98),
	color = Color3.fromRGB(255, 248, 235),
	direction = Vector3.new(-1, -1, -1),
}
-- Parts that only make sense in the hand: the same gag build/Shops' rack strips
-- (RACK_HIDE_ON_DISPLAY), hardcoded again because build/ cannot be required from here.
local ART_HIDE = { "Realistically Sized Magnet" }

--- A fresh copy of one tier's model, or nil for a track with no art. Code-authored
--- first, the place's Assets/Tools second — the order build/Shops' `tierTemplate` uses
--- and for its reason: Assets/Tools/Cleaner still holds the retired brushes and sponges,
--- and they must not win over the hoses ToolModels builds.
local function artModel(track: string, tier: number): Model?
	-- Worn, not held: there is no tool model, and a ViewportFrame cannot draw the Beams
	-- the real aura is made of, so AuraLook builds a still one out of parts.
	if track == "Aura" then
		return AuraLook.icon(tier)
	end
	if ToolModels.has(track) then
		return ToolModels.create(track, tier)
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local library = if assets then assets:FindFirstChild("Tools") else nil
	local folder = if library then library:FindFirstChild(track) else nil
	local template = if folder then folder:FindFirstChild(`T{tier}`) else nil
	if template and template:IsA("Model") then
		return template:Clone()
	end
	return nil
end

local BOX_CORNERS = {}
for _, x in { -1, 1 } do
	for _, y in { -1, 1 } do
		for _, z in { -1, 1 } do
			table.insert(BOX_CORNERS, Vector3.new(x, y, z))
		end
	end
end

--- Aim `camera` so `model` fills a well `aspect` wide per unit tall, seen from `view`.
---
--- THE BOX IS MEASURED IN THE CAMERA'S OWN AXES: every visible part's eight corners are
--- turned into the view's frame, then min/max. `GetBoundingBox` would hand back a box
--- aligned to the model, whose corners overstate a three-quarter view and leave the
--- model floating small in the middle of the well. Invisible parts (every tool's Grip)
--- are skipped, or a hidden handle nub would decide the framing.
---
--- The fit is taken at the box's NEAR face, where perspective makes things largest, so
--- nothing can poke past the edge.
local function frameArt(camera: Camera, model: Model, view: ArtView, aspect: number)
	local look = CFrame.lookAt(Vector3.zero, -view.from.Unit, view.up)
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local half = part.Size / 2
			for _, corner in BOX_CORNERS do
				local point = look:PointToObjectSpace(part.CFrame * (half * corner))
				lo = lo:Min(point)
				hi = hi:Max(point)
			end
		end
	end
	if lo.X > hi.X then
		return
	end

	local mid = (lo + hi) / 2
	local extent = (hi - lo) / 2
	local tanHalf = math.tan(math.rad(ART_FOV) / 2)
	local reach = math.max(extent.Y / tanHalf, extent.X / (tanHalf * aspect)) * ART_MARGIN
	camera.CFrame = look * CFrame.new(mid.X, mid.Y, hi.Z + reach)
end

--- Download every gear model's meshes and textures in the background, once per session.
---
--- WHY (on request, 2026-10-08: scrolling the shop showed empty wells). The templates
--- are on the client but their MeshParts' content is not fetched until something first
--- draws them, so a card scrolled into view rendered blank until its meshes arrived.
--- Asking for all of it at join means the wells are drawn by the time anyone opens a
--- stall. Only the folders `artModel` clones from: Assets/Tools/Cleaner still holds the
--- retired brushes and sponges. The aura's still atom is plain parts and needs nothing.
local preloaded = false
function GearArt.preload()
	if preloaded then
		return
	end
	preloaded = true
	task.spawn(function()
		local assets = ReplicatedStorage:WaitForChild("Assets", 30)
		if assets == nil then
			return
		end
		local wanted = {}
		local tools = assets:FindFirstChild("Tools")
		for track in ART_VIEW do
			local folder = if tools and not ToolModels.has(track) then tools:FindFirstChild(track) else nil
			if folder then
				table.insert(wanted, folder)
			end
		end
		local hoses = assets:FindFirstChild("HoseModels")
		if hoses then
			table.insert(wanted, hoses)
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, wanted)
	end)
end

--- A clear ViewportFrame filling `parent`, lit for gear, with its own camera. The
--- camera is made once and only ever moved; `show` swaps the model in front of it.
function GearArt.viewport(parent: Instance): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "GearModel"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = ART_LIGHT.ambient
	viewport.LightColor = ART_LIGHT.color
	viewport.LightDirection = ART_LIGHT.direction
	viewport.Parent = parent

	local camera = Instance.new("Camera")
	camera.FieldOfView = ART_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

--- Put `track`'s tier `tier` in `viewport` (one made by `GearArt.viewport`), framed for
--- a box `aspect` wide per unit tall. Clears whatever model was there. The aspect is a
--- caller's design size, not AbsoluteSize, which reads 0 until the first layout.
--- `effects` also draws the tier's ToolFX over the picture (see GearArtFx).
function GearArt.show(viewport: ViewportFrame, track: string, tier: number, aspect: number, effects: boolean?)
	GearArtFx.clear(viewport)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end

	local view = ART_VIEW[track]
	local model = if view then artModel(track, tier) else nil
	if model == nil or view == nil then
		return
	end

	for _, name in ART_HIDE do
		local extra = model:FindFirstChild(name)
		if extra then
			extra:Destroy()
		end
	end
	-- The views are written in the posed model's frame, so its pivot goes to the origin,
	-- turned into the track's display pose.
	local turns = TIER_TURN[track]
	local turn = if turns then turns[tier] else nil
	model:PivotTo(if turn then view.pose * CFrame.Angles(0, math.rad(turn), 0) else view.pose)
	model.Parent = viewport
	-- Jumps this model's meshes to the front of the queue if the join-time preload
	-- has not reached them yet.
	task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { model })
	frameArt(viewport.CurrentCamera :: Camera, model, view, aspect)
	if effects then
		GearArtFx.attach(viewport, model, track, tier, aspect)
	end
end

-- How vivid a colour reads: saturation times brightness. A white, grey or near-black
-- body scores low and hands the tint to the tier's glow.
local function vividness(color: Color3): number
	local _, s, v = color:ToHSV()
	return s * v
end
local DULL = 0.2
-- The card shade every tint is pushed to: bright, and never so saturated or so pale
-- that the white Gotham Black on it stops reading.
local TINT_VALUE = 0.9
local TINT_SATURATION = NumberRange.new(0.3, 0.68)
local GREY = 0.12
local STEEL = Color3.fromHex("A9B8CC")

--- A bright card colour in the gear's own colour, for the shop card behind its model
--- (2026-10-04, on request: "make the background relevant to the color and aesthetic of
--- the gear"). Read off ToolTiers rather than the model, because the imported tiers are
--- textured and their parts' Color is plain white: each row's `body` is the dominant
--- colour of that rung's model (its `glow` when the body is white, cream or black —
--- The Oracle, Void Magnet). The aura is its own rings' colour.
function GearArt.tint(track: string, tier: number): Color3?
	local base: Color3
	if track == "Aura" then
		base = AuraLook.get(tier).color
	elseif (ToolTiers :: any)[track] ~= nil then
		local look = ToolTiers.get(track, tier)
		base = look.body
		if vividness(base) < DULL then
			for _, other in { look.glow, look.accent } do
				if other and vividness(other) > vividness(base) then
					base = other
				end
			end
		end
	else
		return nil
	end
	local h, s = base:ToHSV()
	-- Grey to the bone (Scrap Sweeper): a pale steel, where pushing a hue that is not
	-- there up to the floor saturation would paint it a muddy yellow.
	if s < GREY then
		return STEEL
	end
	return Color3.fromHSV(h, math.clamp(s * 0.9, TINT_SATURATION.Min, TINT_SATURATION.Max), TINT_VALUE)
end

--- Put magnet tier `tier` in `viewport` HUNG the way the hand and the rack hold it
--- (Shared/MagnetHang: poles down, face to camera), seen nearly head on from a hair
--- above. For the haul shaft, where the magnet hangs over the nuke on its cable.
local HUNG_VIEW: ArtView = { from = Vector3.new(0.3, 0.2, 1), up = Vector3.yAxis, pose = CFrame.identity }
function GearArt.showHung(viewport: ViewportFrame, tier: number, aspect: number)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	local model = artModel("Magnet", tier)
	if model == nil then
		return
	end
	for _, name in ART_HIDE do
		local extra = model:FindFirstChild(name)
		if extra then
			extra:Destroy()
		end
	end
	model:PivotTo(MagnetHang.basis(tier))
	model.Parent = viewport
	frameArt(viewport.CurrentCamera :: Camera, model, HUNG_VIEW, aspect)
end

return GearArt
