--!strict
--[[
	ItemModels — the catalogue's versioned visual-asset registry.

	Config.Items stores only a small string key. This module owns the factories, so
	gameplay services never need a growing chain of item-specific requires. Missing
	keys return nil and deliberately fall back to the old rarity-coloured block while
	the rest of the catalogue is modelled.

	feat/nuke-arsenal-retheme: every item is now a nuke, reskinned by rarity, so the
	whole catalogue resolves through exactly 7 factories (one per rarity tier) instead
	of a bespoke sculpt per item. The old real-world-object factories (BottleCap,
	GoldBar, etc.) are retired -- nothing in Config/Items references them any more.

	feat/imported-nuke-showcase-yard: retired the procedural per-item signature
	system (NukeSignatures.luau, 7/68 items) in favour of real hand-imported
	meshes for 16 items (Shared.Config.ImportedNukeMeshes). `create` still takes
	an optional itemId (Items.DEFS' `id`, NOT the model key) -- it now checks
	ImportedNukeMeshes.byItemId FIRST and, on a hit, clones that mesh assembly
	instead of the tier factory entirely.

	THE CLONE CAN COME BACK NIL even when there IS an entry: ImportedNukeMeshes
	only has templates to clone from after installTemplates() has run (a
	command-bar World.rebuild(), since it writes MeshPart.MeshId, which needs a
	capability no gameplay Script has -- see that module's header). Falling
	through to the plain tier archetype in that case, rather than returning nil
	outright, is what keeps a fresh merge (rebuild not yet run) equipping the
	rarity capsule instead of the empty-hand Placeholder block ToolService
	reserves for a truly unmodelled item.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NukeCommon = require(script.NukeCommon)
local NukeUncommon = require(script.NukeUncommon)
local NukeRare = require(script.NukeRare)
local NukeEpic = require(script.NukeEpic)
local NukeLegendary = require(script.NukeLegendary)
local NukeMythic = require(script.NukeMythic)
local NukeAnomaly = require(script.NukeAnomaly)
local ImportedNukeMeshes = require(ReplicatedStorage.Shared.Config.ImportedNukeMeshes)

local ItemModels = {}

local factories: { [string]: () -> Model } = {
	NukeCommon = NukeCommon.create,
	NukeUncommon = NukeUncommon.create,
	NukeRare = NukeRare.create,
	NukeEpic = NukeEpic.create,
	NukeLegendary = NukeLegendary.create,
	NukeMythic = NukeMythic.create,
	NukeAnomaly = NukeAnomaly.create,
}

function ItemModels.has(modelKey: string): boolean
	return factories[modelKey] ~= nil
end

function ItemModels.create(modelKey: string?, itemId: string?): Model?
	local imported = if itemId then ImportedNukeMeshes.byItemId[itemId] else nil
	if imported then
		local model = ImportedNukeMeshes.build(imported)
		if model then
			return model
		end
	end

	if modelKey == nil then
		return nil
	end

	local factory = factories[modelKey]
	if factory == nil then
		warn(`[items] unknown model key "{modelKey}"`)
		return nil
	end

	return factory()
end

--- Item factories author placement rotations as attributes so a flat object such
--- as the cap can be tilted toward the player without forcing the same tilt onto a
--- future upright object. Unknown contexts and missing attributes mean identity.
function ItemModels.rotation(model: Model, context: string): CFrame
	local value = model:GetAttribute(`{context}Rotation`)
	return if typeof(value) == "CFrame" then value else CFrame.identity
end

return ItemModels
