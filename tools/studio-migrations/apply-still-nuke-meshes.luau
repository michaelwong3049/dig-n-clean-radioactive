--[[
	Studio migration, still copies, step 2 of 2: build Assets.NukeStillTemplates from
	the meshes export-still-nuke-meshes.luau wrote out and the 3D importer uploaded.

	NEEDS. Workspace.stillbatch_NN models from importing merged-nukes/stillbatch_NN.obj
	("Import content from a file"), and mesh_sink.py running so the matching
	stillbatch_NN.json manifests can be read back (HttpService.HttpEnabled on).
	Entries flagged `superseded` were re-exported into a later file (ONLY /
	REDO_FILE in the export) and are skipped.

	WHAT IT DOES, per nuke, only when every one of its meshes is present and the
	right size:
	  1. builds a Model named after the item with the template's attributes and pivot
	  2. drops in a copy of each imported mesh with the manifest look (colour,
	     material, transparency, reflectance, TextureID), anchored and inert
	     (no collide/query/touch/shadow). The importer turns everything 180 degrees
	     about Y, so each mesh is turned back.
	  3. adds an invisible PrimaryPart in the template PrimaryPart's place, so
	     ItemModels.rotation / pivots / ScaleTo behave the same on both copies
	  4. checks the bounding box against the template's (BBOX_TOLERANCE) and drops
	     the copy if it is off
	THE ORIGINAL TEMPLATES ARE NEVER TOUCHED. A nuke already in NukeStillTemplates is
	skipped; delete it there to rebuild it.

	ROLLBACK. Delete Assets.NukeStillTemplates. Delete the Workspace.stillbatch_NN
	models afterwards either way; the still copies keep their MeshIds.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DRY_RUN = false
local URL = "http://localhost:59999/read?file="
local OUT = "NukeStillTemplates"
local SIZE_TOLERANCE = 0.02
local BBOX_TOLERANCE = 0.03

local FLIP = CFrame.Angles(0, math.pi, 0)

local fmt = string.format

local function vec(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function close(got: Vector3, want: Vector3, tolerance: number): boolean
	local worst = math.max(math.abs(got.X - want.X), math.abs(got.Y - want.Y), math.abs(got.Z - want.Z))
	return worst <= math.max(want.Magnitude * tolerance, 0.01)
end

local function inert(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
end

local function run(): string
	local templates = ReplicatedStorage:FindFirstChild("ImportedNukeTemplates", true)
	assert(templates, "no ImportedNukeTemplates (run this in Edit, not in a play test)")

	local meshes: { [string]: MeshPart } = {}
	local nukes: { [string]: any } = {}
	local byItem: { [string]: { any } } = {}
	local batches = 0
	local seen: { [string]: boolean } = {}
	for _, model in Workspace:GetChildren() do
		local name = model.Name
		if string.match(name, "^stillbatch_") then
			for _, d in model:GetDescendants() do
				if d:IsA("MeshPart") then
					meshes[d.Name] = d
				end
			end
			if not seen[name] then
				seen[name] = true
				batches += 1
				for _, entry in HttpService:JSONDecode(HttpService:GetAsync(URL .. name .. ".json")) do
					if entry.superseded then
						continue
					elseif entry.nuke then
						nukes[entry.nuke] = entry
					else
						byItem[entry.item] = byItem[entry.item] or {}
						table.insert(byItem[entry.item], entry)
					end
				end
			end
		end
	end
	assert(batches > 0, "no Workspace.stillbatch_NN models: import the .obj files first")

	local out = templates.Parent:FindFirstChild(OUT)
	if out == nil and not DRY_RUN then
		out = Instance.new("Folder")
		out.Name = OUT
		out.Parent = templates.Parent
	end

	local done, skipped, before, after = 0, {}, 0, 0
	for item, info in nukes do
		local template = templates:FindFirstChild(item)
		local entries = byItem[item] or {}
		local problem = nil
		if template == nil then
			problem = "no template"
		elseif out and out:FindFirstChild(item) then
			problem = "already built"
		elseif #entries == 0 then
			problem = "no meshes in manifest"
		end
		if problem == nil then
			for _, entry in entries do
				local mesh = meshes[entry.name]
				if mesh == nil then
					problem = "missing mesh " .. entry.name
					break
				end
				if not close(mesh.Size, vec(entry.size), SIZE_TOLERANCE) then
					problem = fmt("%s size %s, expected %s", entry.name, tostring(mesh.Size), tostring(vec(entry.size)))
					break
				end
			end
		end
		if problem then
			table.insert(skipped, item .. " (" .. problem .. ")")
			continue
		end

		local pivot = (template :: Model):GetPivot()
		local model = Instance.new("Model")
		model.Name = item
		for key, value in (template :: Model):GetAttributes() do
			-- RBX_ attributes (the importer's RBX_ReimportId) are engine-only.
			if string.sub(key, 1, 4) ~= "RBX_" then
				model:SetAttribute(key, value)
			end
		end
		model:SetAttribute("StillCopy", true)
		for index, entry in entries do
			local part = meshes[entry.name]:Clone()
			for _, child in part:GetChildren() do
				child:Destroy()
			end
			inert(part)
			pcall(function()
				part.CollisionFidelity = Enum.CollisionFidelity.Box
			end)
			part.Color = Color3.fromHex(entry.color)
			part.Material = (Enum.Material :: any)[entry.material]
			part.Transparency = entry.transparency
			part.Reflectance = entry.reflectance
			part.TextureID = entry.texture or ""
			part.Name = fmt("Still%02d", index)
			part.CFrame = pivot * CFrame.new(entry.centre[1], entry.centre[2], entry.centre[3]) * FLIP
			part.Parent = model
		end
		local root = Instance.new("Part")
		local primary = info.primary
		if primary then
			root.Name = primary.name
			root.Size = vec(primary.size)
			root.CFrame = pivot * CFrame.new(table.unpack(primary.cframe))
		else
			root.Name = "StillRoot"
			root.Size = Vector3.one * 0.2
			root.CFrame = pivot
		end
		root.Transparency = 1
		inert(root)
		root.Parent = model
		model.PrimaryPart = root
		model.WorldPivot = pivot

		local bounds, extent = model:GetBoundingBox()
		local wantCentre = pivot:PointToWorldSpace(vec(info.bboxCentre))
		local wantSize = vec(info.bboxSize)
		if not close(extent, wantSize, BBOX_TOLERANCE) or (bounds.Position - wantCentre).Magnitude > wantSize.Magnitude * BBOX_TOLERANCE then
			table.insert(skipped, fmt("%s (bbox %s at %s, expected %s)", item, tostring(extent), tostring(bounds.Position - wantCentre), tostring(wantSize)))
			model:Destroy()
			continue
		end

		local count = 0
		for _, d in (template :: Model):GetDescendants() do
			if d:IsA("BasePart") then
				count += 1
			end
		end
		before += count
		after += #entries + 1
		done += 1
		if DRY_RUN then
			model:Destroy()
		else
			model.Parent = out
		end
	end

	local missing = {}
	for _, template in templates:GetChildren() do
		if template:IsA("Model") and nukes[template.Name] == nil and not (out and out:FindFirstChild(template.Name)) then
			table.insert(missing, template.Name)
		end
	end

	table.sort(skipped)
	return fmt(
		"%s%d still copies built, %d -> %d parts | skipped %d:\n  %s\n| not in any imported batch: %d",
		if DRY_RUN then "DRY RUN: " else "",
		done,
		before,
		after,
		#skipped,
		table.concat(skipped, "\n  "),
		#missing
	)
end

print("[still-apply] " .. run())
