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

	SEATED BY ITS PARTS, NOT ITS PIVOT. The imported templates' pivots sit anywhere (often
	mid-body), and Model:GetBoundingBox is measured in the pivot's own orientation, so a
	"pivot on the floor" model sank half its height into the floor. `seat` instead reads
	the world-axis box of every part after the model is turned and moved, and lifts it by
	exactly what pokes below the floor.
]]

local Items = require(script.Parent.Config.Items)
local Payload = require(script.Parent.Config.Payload)
local ItemModels = require(script.Parent.ItemModels)
local Placement = require(script.Parent.Placement)

local NukeDisplay = {}

--- The world-axis box of every BasePart in `model`: its min and max corners.
function NukeDisplay.worldBounds(model: Model): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local cf, h = part.CFrame, part.Size / 2
			-- The half-extents of a turned box along the world axes.
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ex = math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z
			local ey = math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z
			local ez = math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
			local p = cf.Position
			lo = Vector3.new(math.min(lo.X, p.X - ex), math.min(lo.Y, p.Y - ey), math.min(lo.Z, p.Z - ez))
			hi = Vector3.new(math.max(hi.X, p.X + ex), math.max(hi.Y, p.Y + ey), math.max(hi.Z, p.Z + ez))
		end
	end
	if lo.X == math.huge then
		return Vector3.zero, Vector3.zero
	end
	return lo, hi
end

--- Stand `model` on the floor at `at` (a point on the floor, plot yaw included): turned
--- to its display rotation, its box centred over the spot and its lowest part `lift`
--- studs above the floor. Returns the model's height.
function NukeDisplay.seat(model: Model, at: CFrame, lift: number?): number
	-- The display rotation goes on once: after the first seat the pivot is upright at
	-- the box's foot (below), so a re-seat (the ghost, every frame) just moves it.
	if model:GetAttribute("DisplaySeated") then
		model:PivotTo(at)
	else
		model:PivotTo(at * ItemModels.rotation(model, "Display"))
		model:SetAttribute("DisplaySeated", true)
	end
	local lo, hi = NukeDisplay.worldBounds(model)
	local centre = (lo + hi) / 2
	local shift = Vector3.new(at.Position.X - centre.X, at.Position.Y + (lift or 0) - lo.Y, at.Position.Z - centre.Z)
	model:PivotTo(model:GetPivot() + shift)
	-- The pivot at the bottom-centre of the box, upright with the plot: the display's
	-- slow turn (StationMotion "hover") spins about the pivot, so this turns the nuke on
	-- the spot instead of swinging it round wherever the template's pivot was.
	model.WorldPivot = CFrame.new(at.Position + Vector3.new(0, lift or 0, 0)) * at.Rotation
	return hi.Y - lo.Y
end

--- The model for `itemId` (dig `uid`, roll `modifier`) at display size, standing on the
--- floor at the world origin. nil while the catalogue model has not arrived
--- (ItemModels.create asks for it). Returns the model, the placement circle's radius and
--- the model's height.
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
	local height = NukeDisplay.seat(model, CFrame.identity)
	local lo, hi = NukeDisplay.worldBounds(model)
	return model, Placement.radiusOf(hi.X - lo.X, hi.Z - lo.Z), height
end

return NukeDisplay
