--[[
	Studio migration, still copies, step 1 of 2: merge EVERY piece of each imported
	nuke into one mesh per final look and write them out as .obj files.

	WHY. A nuke on a stand is 20-190 MeshParts, and almost every one is a different
	mesh, so nothing batches: a full three-floor base is ~1,950 draw calls. Most of
	those parts stay separate only so Config/ItemFx can spin, pulse or glow them,
	and only the nearest few nukes (ItemFxController's full tier) ever do. Every
	other nuke, and every nuke under Fast Mode, stands still. A still copy of each
	nuke, ~7 meshes, stands in for those.

	WHAT A STILL COPY LOOKS LIKE. The nuke at rest with its Config/ItemFx `finish`
	baked in: the same material / colour / transparency / reflectance / tint /
	ramp the controller's applyFinish gives the full copy, so the glowing (Neon) and
	see-through parts look the same. No spins, anims, particles, lights or glint:
	the still tier shows none of those anyway. Parts invisible after the finish
	(transparency >= STILL_HIDDEN, pivots and particle hosts) are left out.

	GROUPS. Every remaining MeshPart, including the first pass's `MergedNN` meshes,
	is grouped by Color + Material + Transparency + Reflectance + TextureID and
	merged, chunked under the importer's 20k-triangle cap. A group of one part is
	still exported, so the still copy is made only of imported meshes.

	MANIFEST. stillbatch_NN.json carries one entry per mesh (look, centre, size,
	tris, source parts) plus one `nuke` entry per template: its PrimaryPart's
	name/size/pose and the model's bounding box, both relative to the pivot, which
	apply-still-nuke-meshes.luau uses to rebuild the model and check it lines up.

	HOW IT GETS OUT. Same route as export-merged-nuke-meshes.luau: POSTs to
	tools/studio-migrations/mesh_sink.py on :59999, which writes
	merged-nukes/stillbatch_NN.obj/.mtl/.json. Every OBJ object is `o`/`g`/`usemtl`
	tagged, or the importer fuses the file into one mesh and decimates it.

	RUN IT IN EDIT, with HttpService.HttpEnabled on and the sink running:
	  python tools/studio-migrations/mesh_sink.py merged-nukes
	DRY_RUN = true only reports the projected mesh counts (no mesh loads, no sink).
	Progress is on Workspace's StillExportProgress attribute. Resume a broken run
	with START_BATCH; re-export a few nukes into REDO_FILE with ONLY, then flag
	their old entries `superseded` in the earlier manifests (the apply step skips
	those). Meshes owned by another account ("not allowed to be forked":
	garden_trowel, old_compass) never load, so those nukes get no still copy.

	THEN. Import each stillbatch_NN.obj with the button whose tooltip is "Import
	content from a file" and run apply-still-nuke-meshes.luau.
]]

local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ItemFx = require(ReplicatedStorage.Shared.ItemFx)

local DRY_RUN = true
local URL = "http://localhost:59999/write"
local FILE_PREFIX = "stillbatch_"
local NUKES_PER_FILE = 10
local MAX_TRIS = 19000
local START_BATCH = 1
--- Re-export just these nukes into one file named REDO_FILE (empty = all).
local ONLY: { string } = {}
local REDO_FILE = "stillbatch_redo"
--- At or above this transparency (after the finish) a part is not drawn and is
--- left out of the still copy.
local STILL_HIDDEN = 0.98
local PROGRESS = "StillExportProgress"

local fmt = string.format

local function setProgress(text: string)
	Workspace:SetAttribute(PROGRESS, text)
	print("[still-export] " .. text)
end

type Look = {
	color: Color3,
	material: string,
	transparency: number,
	reflectance: number,
	texture: string,
}

--- A part's look once ItemFxController.applyFinish has run: the same rules, read
--- without touching the template.
local function finishedLooks(template: Model): { [MeshPart]: Look }
	local looks: { [MeshPart]: Look } = {}
	for _, d in template:GetDescendants() do
		if d:IsA("MeshPart") then
			looks[d] = {
				color = d.Color,
				material = d.Material.Name,
				transparency = d.Transparency,
				reflectance = d.Reflectance,
				texture = d.TextureID,
			}
		end
	end
	local def = ItemFx.get(template.Name)
	for _, finish in (if def then def.finish else nil) or {} do
		for _, part in ItemFx.partsNamed(template, finish.parts) do
			local look = looks[part :: any]
			if look == nil then
				continue
			end
			if finish.material then
				look.material = finish.material
			end
			if finish.color then
				look.color = finish.color
			end
			if finish.transparency then
				look.transparency = finish.transparency
			end
			if finish.reflectance then
				look.reflectance = finish.reflectance
			end
			if finish.tint then
				local base = part:GetAttribute("FxBaseColor")
				local c = if typeof(base) == "Color3" then base else look.color
				local t = finish.tint
				look.color = Color3.new(c.R * t.R, c.G * t.G, c.B * t.B)
			end
			local ramp = finish.ramp
			if ramp then
				local level = tonumber(string.match(part.Name, "%d+")) or 1
				local t = if ramp.levels > 1 then (level - 1) / (ramp.levels - 1) else 0
				look.transparency = ramp.from + (ramp.to - ramp.from) * math.clamp(t, 0, 1)
			end
		end
	end
	return looks
end

local function keyOf(look: Look): string
	return fmt("%s|%s|%.3f|%.3f|%s", look.color:ToHex(), look.material, look.transparency, look.reflectance, look.texture)
end

--- The merge groups of one template: key -> parts, in first-seen order.
local function groupsOf(template: Model): ({ string }, { [string]: { MeshPart } }, { [string]: Look })
	local looks = finishedLooks(template)
	local order, groups, groupLook = {}, {}, {}
	for _, d in template:GetDescendants() do
		local look = if d:IsA("MeshPart") then looks[d] else nil
		if look and look.transparency < STILL_HIDDEN then
			local key = keyOf(look)
			if groups[key] == nil then
				groups[key] = {}
				groupLook[key] = look
				table.insert(order, key)
			end
			table.insert(groups[key], d :: MeshPart)
		end
	end
	return order, groups, groupLook
end

--- One at a time, five tries each. Loading a nuke's meshes all at once (the first
--- pass's way) dropped whole colour groups from 7 of 138 nukes on 2026-10-07; every
--- one of those loaded fine on its own afterwards.
local function fetchAll(parts: { MeshPart }): { [string]: EditableMesh }
	local cache = {}
	for _, part in parts do
		local id = part.MeshId
		if cache[id] == nil then
			for attempt = 1, 5 do
				local ok, mesh = pcall(function()
					return AssetService:CreateEditableMeshAsync(Content.fromUri(id))
				end)
				if ok then
					cache[id] = mesh
					break
				end
				task.wait(attempt)
			end
		end
	end
	return cache
end

local function v3(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

--- What the apply step needs to rebuild the model around the merged meshes.
local function nukeEntry(template: Model): any
	local pivot = template:GetPivot()
	local bounds, extent = template:GetBoundingBox()
	local primary = template.PrimaryPart
	local entry: any = {
		nuke = template.Name,
		bboxCentre = v3(pivot:PointToObjectSpace(bounds.Position)),
		bboxSize = v3(extent),
	}
	if primary then
		local rel = pivot:ToObjectSpace(primary.CFrame)
		entry.primary = {
			name = primary.Name,
			size = v3(primary.Size),
			cframe = { rel:GetComponents() },
		}
	end
	return entry
end

local function run()
	local folder = ReplicatedStorage:FindFirstChild("ImportedNukeTemplates", true)
	assert(folder, "no ImportedNukeTemplates (run this in Edit, not in a play test)")

	local nukes = {}
	for _, template in folder:GetChildren() do
		if template:IsA("Model") and (#ONLY == 0 or table.find(ONLY, template.Name)) then
			table.insert(nukes, template)
		end
	end
	table.sort(nukes, function(a, b)
		return a.Name < b.Name
	end)

	if DRY_RUN then
		local parts, meshes, worst, worstName = 0, 0, 0, ""
		for _, template in nukes do
			local order, groups = groupsOf(template)
			for _, key in order do
				parts += #groups[key]
			end
			meshes += #order
			if #order > worst then
				worst, worstName = #order, template.Name
			end
		end
		setProgress(
			fmt(
				"DRY RUN: %d nukes, %d visible parts -> %d meshes before tri chunking (avg %.1f, max %d %s), %d batch files",
				#nukes,
				parts,
				meshes,
				meshes / math.max(#nukes, 1),
				worst,
				worstName,
				math.ceil(#nukes / NUKES_PER_FILE)
			)
		)
		return
	end

	local perFile = if #ONLY > 0 then #nukes else NUKES_PER_FILE
	local batches = math.ceil(#nukes / perFile)
	setProgress(fmt("%d nukes, %d batches", #nukes, batches))

	for batch = (if #ONLY > 0 then 1 else START_BATCH), batches do
		local file = if #ONLY > 0 then REDO_FILE else fmt("%s%02d", FILE_PREFIX, batch)
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
			local order, groups, groupLook = groupsOf(template)
			local all = {}
			for _, key in order do
				for _, part in groups[key] do
					table.insert(all, part)
				end
			end
			setProgress(fmt("batch %d/%d: %s (%d parts, %d looks)", batch, batches, template.Name, #all, #order))
			table.insert(manifest, nukeEntry(template))
			local cache = fetchAll(all)
			local objects = 0

			for _, key in order do
				local parts = groups[key]
				local look = groupLook[key]
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
						warn(fmt("[still-export] %s.%s: mesh would not load, left out", template.Name, part.Name))
						continue
					end
					local faces = source:GetFaces()
					if tris + #faces > MAX_TRIS then
						close()
						objects += 1
						local name = fmt("%s__S%02d", template.Name, objects)
						entry = {
							name = name,
							item = template.Name,
							color = look.color:ToHex(),
							material = look.material,
							transparency = look.transparency,
							reflectance = look.reflectance,
							texture = look.texture,
							tris = 0,
							parts = {},
						}
						table.insert(manifest, entry)
						mn, mx = Vector3.one * 1e9, -Vector3.one * 1e9
						local c = look.color
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
			-- this every load past the first ~90 nukes fails.
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
		setProgress(fmt("batch %d/%d written (%d entries)", batch, batches, #manifest))
	end
	setProgress("DONE")
end

task.spawn(function()
	local ok, err = pcall(run)
	if not ok then
		setProgress("ERROR " .. tostring(err))
	end
end)
