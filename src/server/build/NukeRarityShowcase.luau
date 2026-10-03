--!strict
--[[
	NukeRarityShowcase.luau — a display-only showcase for the 16 hand-imported
	reference nuke meshes (Shared.Config.ImportedNukeMeshes), lined up in a single
	row inside Stage 1, ordered lowest to highest rarity.

	    require(game.ServerScriptService.Server.build.NukeRarityShowcase).rebuild()
	    require(game.ServerScriptService.Server.build.NukeRarityShowcase).remove()

	This is deliberately NARROWER than feat/imported-nuke-showcase-yard (PR #190),
	which was reverted whole (commit 8ef54ab, at the user's request): that branch
	also wired these same meshes into ItemModels.create so every dig/wash/hold/
	exhibit interaction rendered them instead of the procedural rarity capsule.
	This module only builds the showcase — it never touches Items, ItemModels,
	WashService, ToolService, or ExhibitService, so the dig loop still renders
	through NukeSignatures/NukeBase exactly as it does on main today.

	It still needs ImportedNukeMeshes.installTemplates (elevated-context only —
	MeshPart.MeshId cannot be set from a gameplay Script) to stand up the meshes,
	so `rebuild` must run from World.rebuild() in a build-time / command-bar
	context, same as every other builder here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local ImportedNukeMeshes = require(Shared.Config.ImportedNukeMeshes)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Stages = require(Shared.Config.Stages)

local Kit = require(script.Parent.Kit)

local NukeRarityShowcase = {}

local NAME = "NukeRarityShowcase"
local BUILDER_SOURCE = "src/server/build/NukeRarityShowcase.luau"
local BUILDER_VERSION = 1

local SPACING = 9
local MODEL_SIZE = 6 -- longest edge once scaled and standing on its pedestal
local PEDESTAL_TOP = 2.5
local PEDESTAL_SIZE = 4.5

-- Row runs along Stage 1's walk axis (X), ROW_MARGIN_X in from the west entrance
-- (Stages.bounds' minX) so it reads as "the first thing you see" without sitting
-- on top of the boundary itself. ROW_MARGIN_Z pulls it off the centreline toward
-- the +Z edge, clear of the corridor a player walks down and clear of that edge's
-- boundary wall.
local ROW_MARGIN_X = 30
local ROW_MARGIN_Z = 25

--- Ascending rarity order, tie-broken by the item's original catalogue position
--- (table.sort is not stable, so the tie-break is explicit rather than assumed).
local function orderedModels(): { ImportedNukeMeshes.ModelDef }
	local indexed = {}
	for index, def in ImportedNukeMeshes.MODELS do
		table.insert(indexed, { def = def, index = index, order = Rarity.get(Items.get(def.itemId).rarity).order })
	end
	table.sort(indexed, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.index < b.index
	end)

	local result = {}
	for _, entry in indexed do
		table.insert(result, entry.def)
	end
	return result
end

--- Normalise an arbitrary imported assembly onto a fixed footprint and rest it
--- on the pedestal at `target` — the same normalise-to-a-target-dimension trick
--- ExhibitService's locker uses for arbitrary item art.
local function placeOnPedestal(model: Model, target: CFrame)
	model:PivotTo(CFrame.identity)

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

local function buildStand(
	showcase: Model,
	templates: Folder,
	origin: CFrame,
	def: ImportedNukeMeshes.ModelDef,
	index: number
)
	local item = Items.get(def.itemId)
	local rarityDef = Rarity.get(item.rarity)

	local x = (index - 1) * SPACING
	local pedestal = Kit.build(showcase, origin, {
		name = `Stand_{def.itemId}`,
		pos = { x, PEDESTAL_TOP / 2, 0 },
		size = { PEDESTAL_SIZE, PEDESTAL_TOP, PEDESTAL_SIZE },
		color = rarityDef.color:ToHex(),
		material = "SmoothPlastic",
		attributes = { ImportedNukeId = def.itemId, Rarity = item.rarity },
	})

	Kit.billboard(pedestal, 150, 5, string.upper(def.label), string.upper(item.rarity), rarityDef.color:ToHex(), 60)

	local template = templates:FindFirstChild(def.itemId)
	if template == nil then
		return
	end
	local assembly = (template :: Model):Clone()
	assembly.Parent = showcase
	placeOnPedestal(assembly, origin * CFrame.new(x, 0, 0))
end

local function buildHeader(showcase: Model, origin: CFrame, models: { ImportedNukeMeshes.ModelDef })
	local sign = Kit.build(showcase, origin, {
		name = "ShowcaseSign",
		pos = { -SPACING, 4.5, 0 },
		size = { 0.6, 4.5, 6 },
		color = Kit.C.hazard,
		material = "Metal",
		canCollide = false,
	})

	local lowest = string.upper(Items.get(models[1].itemId).rarity)
	local highest = string.upper(Items.get(models[#models].itemId).rarity)
	Kit.billboard(
		sign,
		220,
		6,
		"NUKE RARITY SHOWCASE",
		`{#models} MODELS — {lowest} → {highest}`,
		Kit.C.hazardBlack,
		80
	)
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

	local models = orderedModels()

	-- The staging folder is a scratch pad: installTemplates is the only place
	-- MeshId is ever written (elevated-context only), everything placed in the
	-- world is an ordinary Clone of what lands here. Destroyed once every stand
	-- has cloned what it needs, so nothing but the finished display remains.
	local templates = ImportedNukeMeshes.installTemplates(showcase)

	buildHeader(showcase, origin, models)
	for index, def in models do
		buildStand(showcase, templates, origin, def, index)
	end

	templates:Destroy()

	return showcase
end

function NukeRarityShowcase.rebuild(parent: Instance?): Model
	local target = parent or Workspace
	local showcase = Kit.swap(NAME, function()
		return createShowcase()
	end, target) :: Model
	print(`[build] nuke rarity showcase rebuilt — {#ImportedNukeMeshes.MODELS} model(s) in Stage 1`)
	return showcase
end

function NukeRarityShowcase.remove(parent: Instance?): boolean
	local target = parent or Workspace
	local showcase = target:FindFirstChild(NAME)
	if showcase == nil then
		return false
	end
	showcase:Destroy()
	print("[build] nuke rarity showcase removed")
	return true
end

return NukeRarityShowcase
