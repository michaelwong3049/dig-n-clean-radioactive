--!strict
--[[
	ImportedStation.luau — fits a station model the user imported in Studio onto the
	footprint a builder (build/ReforgeStation, build/SlagFurnace) would otherwise fill
	with parts.

	The templates live in the PLACE, not in git: ServerStorage.StationTemplates/<name>,
	each the import's AuxScene model renamed (it keeps its RBX_ReimportId, so a re-import
	still finds it). Their colours are vertex colours, so the meshes are left as they
	came: no Color, Material or TextureID is touched.

	The imports are authored FACING -Z (the rune plate / furnace mouth is on their -Z
	side) and a builder authors facing +Z, so `place` turns them half a turn.

	A place without the folder (or without one template) gets nil from `template`, and
	the builder falls back to its own parts, one station at a time.
]]

local ServerStorage = game:GetService("ServerStorage")

local ImportedStation = {}

ImportedStation.FOLDER = "StationTemplates"

--- Below this (largest side, studs, after scaling) a mesh is trim: it does not collide.
local TRIM = 1.5

function ImportedStation.template(name: string): Model?
	local folder = ServerStorage:FindFirstChild(ImportedStation.FOLDER)
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

--- The first descendant called `name`, as a world bounding box (CFrame, size).
function ImportedStation.bounds(look: Model, name: string): (CFrame?, Vector3?)
	local found = look:FindFirstChild(name, true)
	if found == nil then
		return nil, nil
	end
	if found:IsA("Model") then
		return found:GetBoundingBox()
	elseif found:IsA("BasePart") then
		return found.CFrame, found.Size
	end
	return nil, nil
end

--- Clone `template` under `parent` as a Model named "Look", `scale` times its imported
--- size, turned to face +Z, its foot on `origin`'s plane. It is centred over `origin` by
--- the descendant `centreOn` (the plinth, so a spout off one side does not shift the
--- body), or by its whole box when that is missing.
function ImportedStation.place(template: Model, parent: Instance, origin: CFrame, scale: number, centreOn: string?): Model
	local look = template:Clone()
	look.Name = "Look"
	for _, d in look:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
		end
	end
	look:ScaleTo(look:GetScale() * scale)

	local box, size = look:GetBoundingBox()
	local centre = box.Position
	if centreOn then
		local anchor = ImportedStation.bounds(look, centreOn)
		if anchor then
			centre = Vector3.new(anchor.X, centre.Y, anchor.Z)
		end
	end
	-- Where the pivot sits relative to the foot's centre, then re-seat that on origin.
	local foot = CFrame.new(centre - Vector3.new(0, size.Y / 2, 0)) * box.Rotation
	local offset = foot:ToObjectSpace(look:GetPivot())
	look:PivotTo(origin * CFrame.Angles(0, math.pi, 0) * offset)

	for _, d in look:GetDescendants() do
		if d:IsA("BasePart") then
			local s = d.Size
			d.CanCollide = math.max(s.X, s.Y, s.Z) >= TRIM
			d.CanQuery = d.CanCollide
		end
	end
	look.Parent = parent
	return look
end

return ImportedStation
