--!strict
--[[
	ItemModels — the catalogue's versioned visual-asset registry.

	Config.Items stores only a small string key. This module owns the model
	resolution, so gameplay services never need a growing chain of item-specific
	requires. Missing keys return nil and deliberately fall back to the rarity-
	coloured placeholder block (see WashService/ToolService/ExhibitService's own
	`model == nil` branches) while the rest of the catalogue is modelled.

	feat/imported-nuke-gameplay RETIRES THE PROCEDURAL CAPSULE SYSTEM. It used to
	be that every item resolved through one of 7 rarity-tier factories
	(NukeCommon..NukeAnomaly, NukeBase.luau), optionally bolting on a per-item
	`signature` prop from NukeSignatures.luau (7/68 items ever got one). Both are
	gone now, on request: an item either has real hand-imported mesh art or it
	has no model at all and falls back to the placeholder cube everywhere --
	there is no procedural middle tier any more. `modelKey` is now just a flag
	(only "ImportedNuke" is meaningful); which mesh to build is resolved by
	`itemId`.

	IMPORTED MESH TEMPLATES LIVE IN ReplicatedStorage.Assets.ImportedNukeTemplates,
	NOT Shared -- same convention Assets.Tools.Detector already uses, and for
	the same reason (see Shared/ToolModels/init.luau's header): that geometry
	is built once, elevated-only (tools/studio-migrations/import-nuke-models.luau,
	run from Studio's Command Bar, since MeshPart.MeshId cannot be written by an
	ordinary Instance.new in this place), and Assets is NOT Rojo-managed the way
	Shared is, so a runtime-installed folder there survives every sync instead
	of being deleted as an "unknown instance." `create` just Clones whatever
	template is already parked there; a place that predates the migration (or
	whose migration hasn't been re-run since a fresh Studio session) has no
	template yet, and this returns nil -- the same graceful degrade as any
	other unmodelled item.

	EVERY CLONE IS TAGGED FOR ITS EFFECTS HERE (Shared/ItemFx), because this is the
	one door every display context comes through. The glow, light and motion itself
	is client-side (ItemFxController) and waits for the crust to come off.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFx = require(script.Parent.ItemFx)

local IMPORTED_NUKE_KEY = "ImportedNuke"
local TEMPLATE_PATH = { "Assets", "ImportedNukeTemplates" }

local ItemModels = {}

function ItemModels.has(modelKey: string): boolean
	return modelKey == IMPORTED_NUKE_KEY
end

local function importedNukeTemplate(itemId: string): Model?
	local folder: Instance = ReplicatedStorage
	for _, name in TEMPLATE_PATH do
		local next_ = folder:FindFirstChild(name)
		if next_ == nil then
			return nil
		end
		folder = next_
	end
	local template = folder:FindFirstChild(itemId)
	return if template and template:IsA("Model") then template else nil
end

function ItemModels.create(modelKey: string?, itemId: string?): Model?
	if modelKey == nil then
		return nil
	end

	if modelKey == IMPORTED_NUKE_KEY then
		local template = if itemId then importedNukeTemplate(itemId) else nil
		if template == nil then
			return nil
		end
		local clone = template:Clone()
		ItemFx.tag(clone, itemId)
		return clone
	end

	warn(`[items] unknown model key "{modelKey}"`)
	return nil
end

--- Item factories author placement rotations as attributes so a flat object such
--- as the cap can be tilted toward the player without forcing the same tilt onto a
--- future upright object. Unknown contexts and missing attributes mean identity.
function ItemModels.rotation(model: Model, context: string): CFrame
	local value = model:GetAttribute(`{context}Rotation`)
	return if typeof(value) == "CFrame" then value else CFrame.identity
end

return ItemModels
