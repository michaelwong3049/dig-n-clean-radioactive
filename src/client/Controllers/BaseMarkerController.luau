--!strict
--[[
	BaseMarkerController.luau — the "YOUR BASE" beacon.

	The six plots are near-identical from across the plaza — one charcoal board each,
	told apart only by an accent Trim strip and a back-wall name sign. After a warp or
	a respawn it is not obvious which one is yours. This floats a small marker high
	above the centre of your OWN plot: a circular headshot of your avatar and the
	words YOUR BASE.

	LOCAL ONLY. Each client builds one beacon, over its own plot, and never sees
	anyone else's — the server tells only the owning client its plot index (Net
	PlotState, fired once from ExhibitService.assign). Whose plot is whose for
	everyone else is already carried by the Trim colour and the back-wall sign.

	HIDDEN INSIDE A STAGE. It is a safe-zone wayfinding aid, not a HUD element — once
	you step into a field there is nothing to navigate to and the sky-high AlwaysOnTop
	marker would just hang in view over the hazard. Toggled off `ExposureState.stageId`
	(nil = safe zone), the exact signal WarpController uses to hide its BASE/SHOPS bar.

	A WORLD-SPACE BillboardGui PARENTED TO THE PAD, not a ScreenGui — same choice
	NameTagController makes for the overhead name. It rides the plot slab, so a
	respawn never touches it and a Studio `Plots` rebuild takes it away cleanly with
	the slab it hung on (the next PlotState on rejoin builds a fresh one).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Floors = require(Shared.Config.Floors)

local UIKit = require(script.Parent.Parent.UIKit)

local BaseMarker = {}

local MARKER_NAME = "BaseMarker"
-- Bumped up from the original muted grey (B7C0B8) on request — the beacon needs to
-- actually stand out while you're looking for your own base, not just read as a
-- calm marker. Still gets the game-wide outline (UIKit.label's default) for crisp
-- edges on top of the brighter fill.
local TEXT_COLOR = Color3.fromHex("EAF0E4")
local FACE_FILL = Color3.fromHex("11150F") -- shows for the beat before the thumbnail loads
local ACCENT_FALLBACK = Color3.fromHex("B7C0B8") -- if the plot has no Trim to read a colour off

local marker: BillboardGui? = nil
local floorsWatch: RBXScriptConnection? = nil
-- Set from ExposureState every tick. The beacon shows only in the safe zone.
local inStage = false

-- Over a one-floor base. Each floor built on top (the plot's `Floors` attribute,
-- written by build/Plots.setFloors) lifts it by Floors.HEIGHT, so it keeps floating
-- over the top deck rather than sitting in it.
local BASE_HEIGHT = 38

local function clear()
	if marker then
		marker:Destroy()
		marker = nil
	end
	if floorsWatch then
		floorsWatch:Disconnect()
		floorsWatch = nil
	end
end

local function heightOver(plot: Instance): number
	return BASE_HEIGHT + (Floors.clamp(plot:GetAttribute("Floors") :: number?) - 1) * Floors.HEIGHT
end

--- Beacon is visible only outside a stage. Re-applied both on every ExposureState
--- tick and right after a (re)build, so a beacon that gets rebuilt while you are in
--- a field comes back already hidden.
local function applyVisibility()
	if marker then
		marker.Enabled = not inStage
	end
end

--- The plot's own accent, read straight off its Trim part so the beacon's ring
--- matches the strip you already navigate by. Falls back to the muted grey if a
--- place saved before Trim existed is loaded.
local function accentOf(plot: Instance): Color3
	local trim = plot:FindFirstChild("Trim")
	if trim and trim:IsA("BasePart") then
		return trim.Color
	end
	return ACCENT_FALLBACK
end

local function build(plot: Instance, pad: BasePart, accent: Color3)
	local player = Players.LocalPlayer

	local gui = Instance.new("BillboardGui")
	gui.Name = MARKER_NAME
	-- Well above the 16-stud back wall, so it floats free of the plot's own geometry
	-- and reads as a beacon rather than a sign bolted to something.
	gui.StudsOffsetWorldSpace = Vector3.new(0, heightOver(plot), 0)
	gui.MaxDistance = 600 -- plaza-wide; it fades out once you are deep in a field
	gui.AlwaysOnTop = true -- a beacon: visible even with another plot between you and it
	-- LightInfluence = 0, NOT 1 — every base sits next to a PointLight or two, and the
	-- default washes a muted marker back toward white the moment you walk up to it.
	-- The same bug Kit.surfaceText and NameTagController already document.
	gui.LightInfluence = 0
	-- 144x172 design pixels (up from 128x156, to fit the bigger face+caption below
	-- without clipping), scaled with the rest of the HUD (UIKit.billboardCanvas).
	local canvas = UIKit.billboardCanvas(gui, Vector2.new(144, 172))

	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.fromScale(0.5, 0)
	-- Up from 80x80 on request, so the beacon carries more weight from a distance.
	face.Size = UDim2.fromOffset(92, 92)
	face.BackgroundColor3 = FACE_FILL
	face.BackgroundTransparency = 0
	face.Image = `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=150&h=150`
	face.Parent = canvas

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = face

	local ring = Instance.new("UIStroke")
	ring.Thickness = 3.2 -- up from 2.5, to match the bigger face
	ring.Color = accent
	ring.Transparency = 0.1
	ring.Parent = face

	UIKit.label(canvas, {
		name = "Caption",
		anchorPoint = Vector2.new(0.5, 0),
		position = UDim2.new(0.5, 0, 0, 100), -- clears the taller 92px face
		size = UDim2.new(1, 0, 0, 26),
		font = Enum.Font.GothamMedium,
		textSize = 17, -- up from 15
		color = TEXT_COLOR,
		xAlign = Enum.TextXAlignment.Center,
		text = "YOUR BASE",
	})

	gui.Parent = pad
	marker = gui
	applyVisibility()
end

--- `index` nil means "no plot this session" (all six taken); otherwise it is the
--- physical plot this client owns.
local function onPlot(index: number?)
	clear()
	if index == nil then
		return
	end

	local plots = Workspace:WaitForChild("Plots", 10)
	local plot = plots and plots:WaitForChild(`Plot{index}`, 10)
	local pad = plot and plot:WaitForChild("Pad", 10)
	if not (plot and pad and pad:IsA("BasePart")) then
		warn(`[basemarker] plot {index} has no Pad to hang the beacon on`)
		return
	end

	build(plot :: Instance, pad :: BasePart, accentOf(plot :: Instance))
	-- A floor built while the beacon is up moves it too, whichever of the attribute and
	-- the server's PlotState re-fire lands first.
	floorsWatch = (plot :: Instance):GetAttributeChangedSignal("Floors"):Connect(function()
		if marker then
			marker.StudsOffsetWorldSpace = Vector3.new(0, heightOver(plot :: Instance), 0)
		end
	end)
end

function BaseMarker.start()
	Net.get("PlotState").OnClientEvent:Connect(onPlot)

	-- ExposureState ticks ~10Hz; stageId is nil in the safe zone and the field id
	-- once you cross in. Same read WarpController does to slide its bar away.
	Net.get("ExposureState").OnClientEvent:Connect(function(state)
		inStage = state.stageId ~= nil
		applyVisibility()
	end)
end

return BaseMarker
