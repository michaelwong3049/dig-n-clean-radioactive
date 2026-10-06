--[[
	Studio migration, step 1 of 2: merge each imported nuke's static pieces into a
	few meshes and write them out as .obj files for the 3D importer.

	WHY. A nuke averages 76 MeshParts (Dragon Egg 363), and a base streams in a
	dozen of them at once. Most of those pieces are plain painted metal that never
	moves on its own, so every piece of one colour can be one mesh: same geometry,
	same Metal, same colour, a fraction of the parts.

	WHAT STAYS SEPARATE. Every part Config/ItemFx names (ItemFx.referencedNames,
	the same list Spec checks: glows, pulses, spins, particle hosts, lights,
	bolts), the PrimaryPart, any part with a TextureID, and any colour that only
	one part uses. Everything else is grouped by Color + Material + Transparency +
	Reflectance and merged, chunked under the importer's 20k-triangle cap.

	HOW IT GETS OUT. AssetService:CreateAssetAsync can't upload meshes yet, so
	this POSTs each batch to a localhost sink (tools/studio-migrations/
	mesh_sink.py) that writes merged-nukes/batch_NN.obj (+ .mtl, + .json
	manifest). Every OBJ object is `o`/`g`/`usemtl` tagged, or the importer fuses
	the whole file into one mesh and decimates it to 19,999 triangles.

	THEN. Import each batch_NN.obj with the button whose tooltip is "Import content
	from a file" (uploading to the group that owns the game), and run
	apply-merged-nuke-meshes.luau. The importer turns every model 180 degrees
	about Y; the manifest's centres and the apply step undo that.

	Needs HttpService.HttpEnabled. Resume a broken run with START_BATCH.
]]

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ItemFx = require(ReplicatedStorage.Shared.ItemFx)

local URL = "http://localhost:59999/write"
local NUKES_PER_FILE = 14
local MAX_TRIS = 19000
local START_BATCH = 1

--- Re-export just these nukes into one file named REDO_FILE (empty = all).
local ONLY: { string } = {}
local REDO_FILE = "batch_11"
local PROGRESS = "MergedExportProgress"

local fmt = string.format

local function setProgress(text: string)
	Workspace:SetAttribute(PROGRESS, text)
	print("[merge-export] " .. text)
end

--- The merge groups of one template: key -> parts, in first-seen order.
local function groupsOf(template: Model): ({ string }, { [string]: { MeshPart } })
	local def = ItemFx.get(template.Name)
	local kept: { [BasePart]: boolean } = {}
	if def then
		for _, part in ItemFx.partsNamed(template, ItemFx.referencedNames(def)) do
			kept[part] = true
		end
	end
	if template.PrimaryPart then
		kept[template.PrimaryPart] = true
	end
	local order, groups = {}, {}
	for _, d in template:GetDescendants() do
		if d:IsA("MeshPart") and not kept[d] and d.TextureID == "" and #d:GetChildren() == 0 then
			local key = d.Color:ToHex() .. "|" .. d.Material.Name .. "|" .. d.Transparency .. "|" .. d.Reflectance
			if groups[key] == nil then
				groups[key] = {}
				table.insert(order, key)
			end
			table.insert(groups[key], d)
		end
	end
	-- A colour only one part uses gains nothing from a merge.
	local merged = {}
	for _, key in order do
		if #groups[key] >= 2 then
			table.insert(merged, key)
		end
	end
	return merged, groups
end

local function fetchAll(parts: { MeshPart }): { [string]: EditableMesh }
	local cache, pending = {}, 0
	for _, part in parts do
		local id = part.MeshId
		if cache[id] == nil then
			cache[id] = false
			pending += 1
			task.spawn(function()
				-- Fetches fail now and then under load; a part whose mesh never loads
				-- just stays a part of its own (run skips it).
				for attempt = 1, 3 do
					local ok, mesh = pcall(function()
						return AssetService:CreateEditableMeshAsync(Content.fromUri(id))
					end)
					if ok then
						cache[id] = mesh
						break
					end
					cache[id] = nil
					task.wait(attempt)
				end
				pending -= 1
			end)
		end
	end
	while pending > 0 do
		task.wait(0.05)
	end
	return cache
end

local function run()
	local folder = ReplicatedStorage:FindFirstChild("ImportedNukeTemplates", true)
	assert(folder, "no ImportedNukeTemplates")

	local nukes = {}
	for _, template in folder:GetChildren() do
		if template:IsA("Model") and #(groupsOf(template)) > 0 and (#ONLY == 0 or table.find(ONLY, template.Name)) then
			table.insert(nukes, template)
		end
	end
	table.sort(nukes, function(a, b)
		return a.Name < b.Name
	end)
	local perFile = if #ONLY > 0 then #nukes else NUKES_PER_FILE
	local batches = math.ceil(#nukes / perFile)
	setProgress(fmt("%d nukes with something to merge, %d batches", #nukes, batches))

	for batch = (if #ONLY > 0 then 1 else START_BATCH), batches do
		local file = if #ONLY > 0 then REDO_FILE else fmt("batch_%02d", batch)
		local buf, bytes, first = {}, 0, true
		local function flush()
			HttpService:PostAsync(
				URL .. "?file=" .. file .. ".obj&mode=" .. (if first then "w" else "a"),
				table.concat(buf, "\n") .. "\n",
				Enum.HttpContentType.TextPlain
			)
			first, buf, bytes = false, {}, 0
		end
		local function push(line: string)
			buf[#buf + 1] = line
			bytes += #line + 1
			if bytes > 800000 then
				flush()
			end
		end
		push("mtllib " .. file .. ".mtl")
		local mtl, manifest = {}, {}
		local vOff, tOff, nOff = 0, 0, 0

		for index = (batch - 1) * perFile + 1, math.min(batch * perFile, #nukes) do
			local template = nukes[index]
			local pivot = template:GetPivot()
			local order, groups = groupsOf(template)
			local all = {}
			for _, key in order do
				for _, part in groups[key] do
					table.insert(all, part)
				end
			end
			setProgress(fmt("batch %d/%d: %s (%d parts)", batch, batches, template.Name, #all))
			local cache = fetchAll(all)
			local objects = 0

			for _, key in order do
				local parts = groups[key]
				local head = parts[1]
				local entry, mn, mx
				local tris = math.huge
				local function close()
					if entry then
						entry.centre = { (mn.X + mx.X) / 2, (mn.Y + mx.Y) / 2, (mn.Z + mx.Z) / 2 }
						entry.size = { mx.X - mn.X, mx.Y - mn.Y, mx.Z - mn.Z }
					end
				end
				for _, part in parts do
					local source = cache[part.MeshId]
					if not source then
						warn(fmt("[merge-export] %s.%s: mesh would not load, left as its own part", template.Name, part.Name))
						continue
					end
					local faces = source:GetFaces()
					if tris + #faces > MAX_TRIS then
						close()
						objects += 1
						local name = fmt("%s__G%02d", template.Name, objects)
						entry = {
							name = name,
							item = template.Name,
							color = head.Color:ToHex(),
							material = head.Material.Name,
							transparency = head.Transparency,
							reflectance = head.Reflectance,
							tris = 0,
							parts = {},
						}
						table.insert(manifest, entry)
						mn, mx = Vector3.one * 1e9, -Vector3.one * 1e9
						local c = head.Color
						table.insert(mtl, fmt("newmtl mat_%s\nKd %.4f %.4f %.4f\nKa 0 0 0\nKs 0 0 0\nd 1\nillum 1\n", name, c.R, c.G, c.B))
						push("o " .. name)
						push("g " .. name)
						push("usemtl mat_" .. name)
						tris = 0
					end
					local scale = part.Size / part.MeshSize
					local rel = pivot:ToObjectSpace(part.CFrame)
					local rot = rel.Rotation
					local vIdx, tIdx, nIdx = {}, {}, {}
					local nv, nt, nn = 0, 0, 0
					for _, v in source:GetVertices() do
						nv += 1
						vIdx[v] = nv
						local q = rel * (source:GetPosition(v) * scale)
						mn, mx = mn:Min(q), mx:Max(q)
						push(fmt("v %.5f %.5f %.5f", q.X, q.Y, q.Z))
					end
					for _, u in source:GetUVs() do
						nt += 1
						tIdx[u] = nt
						local uv = source:GetUV(u)
						push(fmt("vt %.5f %.5f", uv.X, 1 - uv.Y))
					end
					for _, n in source:GetNormals() do
						nn += 1
						nIdx[n] = nn
						local q = (rot * (source:GetNormal(n) / scale)).Unit
						push(fmt("vn %.5f %.5f %.5f", q.X, q.Y, q.Z))
					end
					for _, f in faces do
						local fv, fu, fn = source:GetFaceVertices(f), source:GetFaceUVs(f), source:GetFaceNormals(f)
						local corner = {}
						for k = 1, 3 do
							local t = if fu[k] then tostring(tIdx[fu[k]] + tOff) else ""
							local n = if fn[k] then tostring(nIdx[fn[k]] + nOff) else ""
							corner[k] = tostring(vIdx[fv[k]] + vOff) .. "/" .. t .. "/" .. n
						end
						push("f " .. table.concat(corner, " "))
					end
					vOff += nv
					tOff += nt
					nOff += nn
					tris += #faces
					entry.tris += #faces
					table.insert(entry.parts, part.Name)
				end
				close()
			end
			-- EditableMeshes count against a memory budget until destroyed; without
			-- this every load past the first ~90 nukes failed.
			for _, mesh in cache do
				if mesh then
					mesh:Destroy()
				end
			end
			table.clear(cache)
			task.wait()
		end

		flush()
		HttpService:PostAsync(URL .. "?file=" .. file .. ".mtl&mode=w", table.concat(mtl, "\n"), Enum.HttpContentType.TextPlain)
		HttpService:PostAsync(URL .. "?file=" .. file .. ".json&mode=w", HttpService:JSONEncode(manifest), Enum.HttpContentType.TextPlain)
		setProgress(fmt("batch %d/%d written (%d objects)", batch, batches, #manifest))
	end
	setProgress("DONE")
end

task.spawn(function()
	local ok, err = pcall(run)
	if not ok then
		setProgress("ERROR " .. tostring(err))
	end
end)
