--[[
	GearArt — a live 3D picture of one gear tier in a ViewportFrame.

	Lifted out of StationController when the Gear panel needed the same picture: the
	shop card's art well and the Gear panel's rows both draw the real model, from the
	same hero angle per track, framed to fill its box. A LIVE RENDER, NOT AN UPLOADED
	PICTURE: every tier's model is already on the client (Assets/Tools for Detector and
	Magnet, Shared/ToolModels for the hose, AuraLook for the aura), so it cannot drift
	from the rack or the hand when a model is re-imported.

	The aura's atom is the one picture that moves: it is tagged AuraLook.ICON_TAG, and
	AuraController circles the camera of whatever ViewportFrame it sits in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local AuraLook = require(Shared.AuraLook)
local ToolModels = require(Shared.ToolModels)

local GearArt = {}

-- A STILL HERO SHOT per track. Each is a direction to look FROM and an `up`, both in the
-- model's own frame (its pivot put at the origin), and all put the working end on the
-- right: the detector is laid along the well with its coil there, since stood up the
-- way it is carried it would be a thin stripe in a box this wide; the magnet and the
-- hose are three-quarter views from a little above. Every tier is framed to fill its
-- box, so tier is carried by the model itself, not by its size.
type ArtView = { from: Vector3, up: Vector3 }
local ART_VIEW: { [string]: ArtView } = {
	Detector = { from = Vector3.new(1, 0.5, 0.3), up = Vector3.new(0, 0.6, -1) },
	Magnet = { from = Vector3.new(1, 0.6, 0.35), up = Vector3.yAxis },
	Cleaner = { from = Vector3.new(1, 0.55, -0.35), up = Vector3.yAxis },
	-- Nearly head on and a little above, so the flat ring reads as a ring and the
	-- tilted pair cross in front of the nucleus the way they do round a chest.
	Aura = { from = Vector3.new(0.25, 0.4, 1), up = Vector3.yAxis },
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
function GearArt.show(viewport: ViewportFrame, track: string, tier: number, aspect: number)
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
	-- The views are written in the model's own frame, so its pivot goes to the origin.
	model:PivotTo(CFrame.identity)
	model.Parent = viewport
	frameArt(viewport.CurrentCamera :: Camera, model, view, aspect)
end

return GearArt
