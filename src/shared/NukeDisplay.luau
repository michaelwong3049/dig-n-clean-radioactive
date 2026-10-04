--!strict
--[[
	NukeDisplay.luau — one placed nuke's model, at the size it stands on a base.

	SHARED SO THE GHOST IS THE TRUTH. ExhibitService builds a placed nuke with this and
	the client's PlacementController builds its see-through preview with the same call,
	so the circle the ghost is checked against (Shared/Placement) is the circle the
	server checks — off the same model, at the same scale.

	THE SIZE is the catalogue model at its own scale, times the item's Config/Items
	`sizeMult` and this dig's Config/Payload roll — what the stands used to show. There
	is no ceiling over an open floor any more, so the old stand height cap is gone too:
	a GIGA roll stands as tall as it rolled.
]]

local Items = require(script.Parent.Config.Items)
local Payload = require(script.Parent.Config.Payload)
local ItemModels = require(script.Parent.ItemModels)
local Placement = require(script.Parent.Placement)

local NukeDisplay = {}

--- The model for `itemId` (dig `uid`, roll `modifier`) at display size and display
--- rotation, pivoted at the origin with its base on y = 0. nil while the catalogue
--- model has not arrived (ItemModels.create asks for it). Returns the model, the
--- placement circle's radius and the model's height.
function NukeDisplay.create(itemId: string, uid: string?, modifier: string?): (Model?, number, number)
	local def = Items.get(itemId)
	local model = ItemModels.create(def.model, itemId, modifier)
	if model == nil then
		return nil, Placement.MIN_RADIUS, 0
	end
	local mult = (def.sizeMult or 1) * (if uid then Payload.forUid(uid) else 1)
	if mult ~= 1 then
		model:ScaleTo(model:GetScale() * mult)
	end
	model:PivotTo(ItemModels.rotation(model, "Display"))
	local bounds, extent = model:GetBoundingBox()
	-- Seat it: the bottom of its box on y = 0, its box centred on x/z 0, so a pivot
	-- of CFrame.new(x, floorY, z) stands it on the floor right where it was placed.
	local shift = Vector3.new(-bounds.Position.X, extent.Y / 2 - bounds.Position.Y, -bounds.Position.Z)
	model:PivotTo(model:GetPivot() + shift)
	model.WorldPivot = CFrame.identity
	return model, Placement.radiusOf(extent.X, extent.Z), extent.Y
end

return NukeDisplay
