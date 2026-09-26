--!strict
--[[
	GearTierShowcase.luau — a display-only showcase for the three gear tracks that
	have real 3D art (Detector, Magnet, Cleaner), lined up in Stage 1 next to
	NukeRarityShowcase: one row per track, tier 1 lowest through the top tier.

	    require(game.ServerScriptService.Server.build.GearTierShowcase).rebuild()
	    require(game.ServerScriptService.Server.build.GearTierShowcase).remove()

	Suit, Boots, and Satchel are deliberately excluded — they are stat-only gear
	with no held/worn model anywhere in this codebase or the place (see Gear.luau
	and Shops.luau's STALLS, which only lists Detector/Magnet/Cleaner as having a
	`present` rack). There is nothing to stand on a pedestal for them.

	Model resolution mirrors Shops.luau's own `tierTemplate`: Cleaner is built from
	code (Shared.ToolModels), Detector and Magnet come from the place file
	(ReplicatedStorage.Assets.Tools.<Track>.T<n>) since their tier-model generator
	is long gone (see ToolModels' header). A place missing that folder degrades to
	a painted fallback block per slot instead of leaving a gap or erroring the
	whole rebuild — same convention the shop rack already uses.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)
local Stages = require(Shared.Config.Stages)
local ToolModels = require(Shared.ToolModels)

local Kit = require(script.Parent.Kit)

local GearTierShowcase = {}

local NAME = "GearTierShowcase"
local BUILDER_SOURCE = "src/server/build/GearTierShowcase.luau"
local BUILDER_VERSION = 1

-- Gag parts that only make sense held in a hand — see Shops.luau's own
-- RACK_HIDE_ON_DISPLAY, same idea reused here for the same reason.
local HIDE_ON_DISPLAY = { "Realistically Sized Magnet" }

local SPACING = 9
local MODEL_SIZE = 5 -- longest edge once scaled and standing on its pedestal
local PEDESTAL_TOP = 2.5
local PEDESTAL_SIZE = 4.5
local ROW_SPACING = 14

-- Continues the same north-edge line NukeRarityShowcase occupies (also maxZ -
-- 25), starting far enough east of that showcase's own footprint (16 items *
-- SPACING 9, from minX + 30) to clear it with room to spare.
local ROW_MARGIN_X = 190
local ROW_MARGIN_Z = 25

local TRACKS = {
	{ track = "Detector", color = Kit.C.shopDetector },
	{ track = "Magnet", color = Kit.C.shopMagnet },
	{ track = "Cleaner", color = Kit.C.shopCleaner },
}

--- Mirrors Shops.luau's private `tierTemplate`: code-authored art first, then the
--- place-file library, nil (not an error) when this place has neither.
local function gearTemplate(track: string, tier: number): Model?
	if ToolModels.has(track) then
		return ToolModels.create(track, tier)
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local library = assets and assets:FindFirstChild("Tools")
	local folder = library and library:FindFirstChild(track)
	local model = folder and folder:FindFirstChild(`T{tier}`)
	if model and model:IsA("Model") and model.PrimaryPart ~= nil then
		return model :: Model
	end
	return nil
end

--- Normalise an arbitrary gear model onto a fixed footprint and rest it on the
--- pedestal at `target`. Starts from the model's own `HoldCFrame` attribute (the
--- one per-model orientation correction this project already maintains — see
--- Shops.luau's `hangTierModel`) rather than identity, since none of these three
--- tracks share an authored axis (a detector's shaft runs local X, a magnet's
--- local Z) and only HoldCFrame knows which way is "up" for a given model.
local function placeOnPedestal(model: Model, target: CFrame)
	local hold = model:GetAttribute("HoldCFrame")
	model:PivotTo(if typeof(hold) == "CFrame" then hold else CFrame.new())

	local size = model:GetExtentsSize()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		model:ScaleTo(MODEL_SIZE / longest)
	end

	model:PivotTo(target)
	local bounds, extent = model:GetBoundingBox()
	local bottom = bounds.Position.Y - extent.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, PEDESTAL_TOP - bottom + 0.08, 0))
end

local function buildFallback(showcase: Model, origin: CFrame, x: number, rowZ: number, colorHex: string)
	Kit.build(showcase, origin, {
		name = "FallbackArt",
		pos = { x, PEDESTAL_TOP + MODEL_SIZE / 2, rowZ },
		size = { MODEL_SIZE * 0.5, MODEL_SIZE, MODEL_SIZE * 0.5 },
		color = colorHex,
		material = "SmoothPlastic",
		canCollide = false,
	})
end

local function buildStand(showcase: Model, origin: CFrame, rowZ: number, track: string, colorHex: string, tier: number)
	local x = (tier - 1) * SPACING
	local label = Gear.tier(track, tier).name

	local pedestal = Kit.build(showcase, origin, {
		name = `Stand_{track}_T{tier}`,
		pos = { x, PEDESTAL_TOP / 2, rowZ },
		size = { PEDESTAL_SIZE, PEDESTAL_TOP, PEDESTAL_SIZE },
		color = colorHex,
		material = "SmoothPlastic",
		attributes = { GearTrack = track, GearTier = tier },
	})

	Kit.billboard(pedestal, 150, 5, string.upper(label), `{string.upper(track)} T{tier}`, colorHex, 60)

	local template = gearTemplate(track, tier)
	if template == nil then
		buildFallback(showcase, origin, x, rowZ, colorHex)
		return
	end

	local clone = template:Clone()
	clone.Name = `T{tier}`
	for _, hideName in HIDE_ON_DISPLAY do
		local extra = clone:FindFirstChild(hideName)
		if extra then
			extra:Destroy()
		end
	end
	clone.Parent = showcase
	placeOnPedestal(clone, origin * CFrame.new(x, 0, rowZ))

	-- A code-authored template has no parent and is this call's alone to clean up;
	-- a library template lives in Assets.Tools and must survive for the next slot
	-- (and the next rebuild) to clone from.
	if template.Parent == nil then
		template:Destroy()
	end
end

local function buildHeader(showcase: Model, origin: CFrame)
	local sign = Kit.build(showcase, origin, {
		name = "ShowcaseSign",
		pos = { -SPACING, 4.5, 0 },
		size = { 0.6, 4.5, 6 },
		color = Kit.C.hazard,
		material = "Metal",
		canCollide = false,
	})
	Kit.billboard(sign, 220, 6, "GEAR SHOWCASE", "DETECTOR / MAGNET / CLEANER — LOW TO HIGH", Kit.C.hazardBlack, 80)
end

local function createShowcase(): Model
	local showcase = Instance.new("Model")
	showcase.Name = NAME
	Kit.stamp(showcase, BUILDER_SOURCE, BUILDER_VERSION)
	showcase:SetAttribute("StageShowcase", 1)

	local minX, _minZ, _maxX, maxZ = Stages.bounds(1)
	local originX = minX + ROW_MARGIN_X
	local originZ = maxZ - ROW_MARGIN_Z
	local origin = CFrame.new(originX, Stages.SURFACE_Y, originZ)

	buildHeader(showcase, origin)
	for rowIndex, entry in TRACKS do
		local rowZ = -(rowIndex - 1) * ROW_SPACING
		for tier = 1, Gear.maxTier(entry.track) do
			buildStand(showcase, origin, rowZ, entry.track, entry.color, tier)
		end
	end

	return showcase
end

function GearTierShowcase.rebuild(parent: Instance?): Model
	local target = parent or Workspace
	local showcase = Kit.swap(NAME, function()
		return createShowcase()
	end, target) :: Model
	print("[build] gear tier showcase rebuilt — Detector/Magnet/Cleaner in Stage 1")
	return showcase
end

function GearTierShowcase.remove(parent: Instance?): boolean
	local target = parent or Workspace
	local showcase = target:FindFirstChild(NAME)
	if showcase == nil then
		return false
	end
	showcase:Destroy()
	print("[build] gear tier showcase removed")
	return true
end

return GearTierShowcase
