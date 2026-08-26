--!strict
--[[
	ItemModels — the catalogue's versioned visual-asset registry.

	Config.Items stores only a small string key. This module owns the factories, so
	gameplay services never need a growing chain of item-specific requires. Missing
	keys return nil and deliberately fall back to the old rarity-coloured block while
	the rest of the catalogue is modelled.
]]

local BottleCap = require(script.BottleCap)
local HouseKey = require(script.HouseKey)

local ItemModels = {}

local factories: { [string]: () -> Model } = {
	BottleCap = BottleCap.create,
	HouseKey = HouseKey.create,
}

function ItemModels.has(modelKey: string): boolean
	return factories[modelKey] ~= nil
end

function ItemModels.create(modelKey: string?): Model?
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
