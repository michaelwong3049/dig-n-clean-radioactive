--[[
	Studio migration, step 2 of 2: swap each imported nuke's static pieces for the
	merged meshes that export-merged-nuke-meshes.luau wrote out and the 3D importer
	uploaded.

	NEEDS. Workspace.batch_NN models from importing merged-nukes/batch_NN.obj, and
	mesh_sink.py running so the matching batch_NN.json manifests can be read back
	(HttpService.HttpEnabled on). Manifest entries flagged `superseded` were
	re-exported into a later batch and are skipped.

	WHAT IT DOES, per nuke, only when every one of its merged meshes is present:
	  1. copies the untouched template into ServerStorage.ImportedNukeTemplatesPreMerge
	     (once; a second run never overwrites the backup)
	  2. deletes the parts each manifest entry lists (name + colour must match)
	  3. drops in a copy of each imported mesh: manifest colour/material/
	     transparency/reflectance, collision/shadow flags copied from the parts it
	     replaces, placed at the manifest centre. The importer turns everything
	     180 degrees about Y, so each mesh is turned back.
	A mesh whose size is off by more than SIZE_TOLERANCE stops that nuke.

	The merged parts are named `Merged<NN>`: no Config/ItemFx entry names that, so
	no effect latches onto them. Set DRY_RUN = true for a report only. Delete the
	Workspace.batch_NN models afterwards; the templates keep their MeshIds.

	ROLLBACK. Move the backed-up models from ServerStorage.ImportedNukeTemplatesPreMerge
	back into Assets.ImportedNukeTemplates (replacing the merged ones).
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local DRY_RUN = false
local URL = "http://localhost:59999/read?file="
local BACKUP = "ImportedNukeTemplatesPreMerge"
local SIZE_TOLERANCE = 0.02

local FLIP = CFrame.Angles(0, math.pi, 0)
local COPIED = { "Anchored", "CanCollide", "CanQuery", "CanTouch", "CastShadow", "Massless", "CollisionGroup" }

local fmt = string.format

type Entry = {
	name: string,
	item: string,
	color: string,
	material: string,
	transparency: number,
	reflectance: number,
	centre: { number },
	size: { number },
	parts: { string },
	superseded: boolean?,
}

local function sizeOk(got: Vector3, want: { number }): boolean
	local w = Vector3.new(want[1], want[2], want[3])
	local worst = math.max(math.abs(got.X - w.X), math.abs(got.Y - w.Y), math.abs(got.Z - w.Z))
	return worst <= math.max(w.Magnitude * SIZE_TOLERANCE, 0.01)
end

local function run(): string
	local folder = ReplicatedStorage:FindFirstChild("ImportedNukeTemplates", true)
	assert(folder, "no ImportedNukeTemplates")

	-- Every imported mesh by name, and every live manifest entry by nuke.
	local meshes: { [string]: MeshPart } = {}
	local byItem: { [string]: { Entry } } = {}
	local batches = 0
	for _, model in Workspace:GetChildren() do
		local batch = string.match(model.Name, "^batch_%d%d$")
		if batch then
			batches += 1
			for _, d in model:GetDescendants() do
				if d:IsA("MeshPart") then
					meshes[d.Name] = d
				end
			end
			local manifest = HttpService:JSONDecode(HttpService:GetAsync(URL .. model.Name .. ".json"))
			for _, entry in manifest do
				if not entry.superseded then
					byItem[entry.item] = byItem[entry.item] or {}
					table.insert(byItem[entry.item], entry)
				end
			end
		end
	end
	assert(batches > 0, "no Workspace.batch_NN models: import the .obj files first")

	local backup = ServerStorage:FindFirstChild(BACKUP)
	if backup == nil and not DRY_RUN then
		backup = Instance.new("Folder")
		backup.Name = BACKUP
		backup.Parent = ServerStorage
	end

	local done, skipped, before, after = 0, {}, 0, 0
	for item, entries in byItem do
		local template = folder:FindFirstChild(item)
		local problem = nil
		if template == nil then
			problem = "no template"
		elseif template:FindFirstChild("Merged01") then
			problem = "already merged"
		end
		-- Resolve every entry before touching anything.
		local plan = {}
		if problem == nil then
			local claimed: { [BasePart]: boolean } = {}
			for _, entry in entries do
				local mesh = meshes[entry.name]
				if mesh == nil then
					problem = "missing mesh " .. entry.name
					break
				end
				if not sizeOk(mesh.Size, entry.size) then
					problem = fmt("%s size %s, expected %.2f,%.2f,%.2f", entry.name, tostring(mesh.Size), entry.size[1], entry.size[2], entry.size[3])
					break
				end
				local parts = {}
				for _, name in entry.parts do
					local found = nil
					for _, d in template:GetDescendants() do
						if d.Name == name and d:IsA("MeshPart") and not claimed[d] and d.Color:ToHex() == entry.color then
							found = d
							break
						end
					end
					if found == nil then
						problem = fmt("%s: part %s not found", entry.name, name)
						break
					end
					claimed[found] = true
					table.insert(parts, found)
				end
				if problem then
					break
				end
				table.insert(plan, { entry = entry, mesh = mesh, parts = parts })
			end
		end
		if problem then
			table.insert(skipped, item .. " (" .. problem .. ")")
			continue
		end

		local count = 0
		for _, d in template:GetDescendants() do
			if d:IsA("BasePart") then
				count += 1
			end
		end
		before += count
		local removed = 0
		for _, step in plan do
			removed += #step.parts
		end
		after += count - removed + #plan
		done += 1
		if DRY_RUN then
			continue
		end

		if backup:FindFirstChild(item) == nil then
			template:Clone().Parent = backup
		end
		local pivot = template:GetPivot()
		for index, step in plan do
			local entry = step.entry
			local head = step.parts[1]
			local part = step.mesh:Clone()
			for _, property in COPIED do
				(part :: any)[property] = (head :: any)[property]
			end
			pcall(function()
				part.CollisionFidelity = Enum.CollisionFidelity.Box
			end)
			part.Color = Color3.fromHex(entry.color)
			part.Material = (Enum.Material :: any)[entry.material]
			part.Transparency = entry.transparency
			part.Reflectance = entry.reflectance
			part.Name = fmt("Merged%02d", index)
			part.CFrame = pivot * CFrame.new(entry.centre[1], entry.centre[2], entry.centre[3]) * FLIP
			part.Parent = template
			for _, old in step.parts do
				old:Destroy()
			end
		end
	end

	table.sort(skipped)
	return fmt(
		"%s%d nukes merged, %d -> %d parts | skipped %d:\n  %s",
		if DRY_RUN then "DRY RUN: " else "",
		done,
		before,
		after,
		#skipped,
		table.concat(skipped, "\n  ")
	)
end

print("[merge-apply] " .. run())
