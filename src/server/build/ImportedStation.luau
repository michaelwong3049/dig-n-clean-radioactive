--!strict
--[[
	ImportedStation.luau — fits a station model the user imported in Studio onto the
	footprint a builder (build/ReforgeStation, build/SlagFurnace) would otherwise fill
	with parts.

	The templates live in the PLACE, not in git: ServerStorage.StationTemplates/<name>,
	each the import's AuxScene model renamed (it keeps its RBX_ReimportId, so a re-import
	still finds it). Their colours are vertex colours, and a MeshPart's Color only
	multiplies them, so a near-black import cannot be lifted by Color. `paint` swaps the
	named meshes for a Part + SpecialMesh instead (a FileMesh ignores vertex colours and
	takes the Part's Color); anything a palette does not name keeps the import's colours.

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

--- One palette entry: a hex colour, whether the piece glows (Neon), and how see-through
--- it is (glass; the imports come in opaque). `studs` makes the piece a plain studded
--- Plastic Block or upright Cylinder of the mesh's box instead: studs never draw on a
--- mesh, so only pieces that really are a box or a round post can take them.
export type Paint = { color: string, neon: boolean?, transparency: number?, studs: ("Block" | "Cylinder")? }

local FACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }

--- Turn `p` (a painted piece, its mesh removed) into a studded Plastic `shape` filling
--- the same box. A Cylinder's axis is its X, so it is rolled a quarter turn to stand up.
function ImportedStation.stud(p: Part, shape: "Block" | "Cylinder")
	local mesh = p:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh:Destroy()
	end
	local size, cf = p.Size, p.CFrame
	p.Shape = Enum.PartType[shape]
	if shape == "Cylinder" then
		p.Size = Vector3.new(size.Y, size.X, size.Z)
		p.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	end
	p.Material = Enum.Material.Plastic
	for _, face in FACES do
		(p :: any)[face] = Enum.SurfaceType.Studs
	end
end

--- Repaint the placed `look`: every MeshPart whose name, less any trailing digits
--- ("coal12" → "coal"), is a key of `palette` becomes a Part of the same name, box and
--- collision carrying a SpecialMesh of its mesh, in that colour. Children (none today)
--- move across. Returns how many were swapped.
function ImportedStation.paint(look: Model, palette: { [string]: Paint }): number
	local swapped = 0
	for _, d in look:GetDescendants() do
		if not d:IsA("MeshPart") then
			continue
		end
		local entry = palette[d.Name] or palette[(string.gsub(d.Name, "%d+$", ""))]
		if entry == nil then
			continue
		end
		-- MeshSize is the mesh's native size; the templates come in at it, so the look's
		-- scale stands in if it cannot be read.
		local ok, native = pcall(function()
			return (d :: any).MeshSize :: Vector3
		end)
		local scale = if ok and native and native.Magnitude > 0 then d.Size / native else Vector3.one * look:GetScale()

		local p = Instance.new("Part")
		p.Name = d.Name
		p.Size = d.Size
		p.CFrame = d.CFrame
		p.Color = Color3.fromHex(entry.color)
		p.Material = if entry.neon then Enum.Material.Neon else Enum.Material.Plastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Anchored = true
		p.CanCollide = d.CanCollide
		p.CanQuery = d.CanQuery
		p.CanTouch = false
		p.Transparency = entry.transparency or d.Transparency
		p.CastShadow = d.CastShadow and not entry.neon and entry.transparency == nil

		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = d.MeshId
		mesh.Scale = scale
		mesh.Parent = p

		for _, child in d:GetChildren() do
			child.Parent = p
		end
		if entry.studs then
			ImportedStation.stud(p, entry.studs)
		end
		p.Parent = d.Parent
		d:Destroy()
		swapped += 1
	end
	return swapped
end

return ImportedStation
