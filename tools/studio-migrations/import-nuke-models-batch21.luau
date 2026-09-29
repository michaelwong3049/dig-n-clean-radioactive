--[[
	Twenty-first Studio command-bar migration, same shape as batch 20 (read
	import-nuke-models.luau's header first). 9 NEW models stocking Stage 12
	(Ground Zero). Mapped by part names.

	REGION-SCOPED: all nine staged at X~-94, Z~78, Y -37..-18 (batch 20's spot).

	Set DRY_RUN = true to build every template orphaned (never parented), report,
	and destroy -- nothing in the place changes.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DRY_RUN = false

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

local REGIONS = {
	{ min = Vector3.new(-110, -45, 60), max = Vector3.new(-78, -10, 96) },
}

local ITEMS = {
	{ itemId = "fallout_nuke", label = "Fallout Nuke", marker = "TrefoilDisc", rootPart = "Body" },
	{ itemId = "warhead_nuke", label = "Warhead Nuke", marker = "Stencil", rootPart = "Body" },
	{ itemId = "shockwave_nuke", label = "Shockwave Nuke", marker = "PressureRing", rootPart = "Body" },
	{ itemId = "mushroom_cloud_nuke", label = "Mushroom Cloud Nuke", marker = "StemCore", rootPart = "Body" },
	{ itemId = "reactor_core_nuke", label = "Reactor Nuke", marker = "ControlRod", rootPart = "ShellNose" },
	{ itemId = "solar_flare_nuke", label = "Solar Flare Nuke", marker = "Corona", rootPart = "ShellNose" },
	{ itemId = "ground_zero_nuke", label = "Ground Zero Nuke", marker = "CraterRim", rootPart = "Body" },
	{ itemId = "atom_nuke", label = "Atom Nuke", marker = "Electron", rootPart = "ShellNose" },
	{ itemId = "game_over_nuke", label = "Game Over Nuke", marker = "Hatch", rootPart = "Body" },
}

local function baseName(name: string): string
	return (name:gsub("[%d_]+$", ""))
end

local function hasPart(root: Instance, name: string): boolean
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and baseName(d.Name) == name then
			return true
		end
	end
	return false
end

local function inRegion(pos: Vector3): boolean
	for _, r in ipairs(REGIONS) do
		if pos.X >= r.min.X and pos.X <= r.max.X
			and pos.Y >= r.min.Y and pos.Y <= r.max.Y
			and pos.Z >= r.min.Z and pos.Z <= r.max.Z
		then
			return true
		end
	end
	return false
end

--- Every AuxScene Node0 in this batch's region carrying `marker`. The caller
--- asserts there is exactly one.
local function findSourceNodes(marker: string): { Model }
	local found = {}
	for _, aux in ipairs(workspace:GetChildren()) do
		if aux.Name == "AuxScene" then
			local node = aux:FindFirstChild("Node0")
			if node then
				local ok, center = pcall(function()
					return (node :: Model):GetBoundingBox()
				end)
				if ok and inRegion(center.Position) and hasPart(node, marker) then
					table.insert(found, node :: Model)
				end
			end
		end
	end
	return found
end

--- Identical to every prior migration's flatten -- see the first one's comment.
local function flatten(model: Model): number
	local rescued = 0
	local function collect(container: Instance)
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("MeshPart") then
				if child.Parent ~= model then
					child.Parent = model
					rescued += 1
				end
			else
				collect(child)
			end
		end
	end
	collect(model)
	for _, child in ipairs(model:GetChildren()) do
		if not child:IsA("MeshPart") then
			child:Destroy()
		end
	end
	return rescued
end

local averageCache: { [string]: Color3 } = {}

--- The mean colour of a (flat) texture. Sampled every 5th pixel.
local function averageColor(uri: string): Color3
	local cached = averageCache[uri]
	if cached then
		return cached
	end
	local image = AssetService:CreateEditableImageAsync(Content.fromUri(uri))
	local size = image.Size
	local pixels = image:ReadPixelsBuffer(Vector2.zero, size)
	local r, g, b, count = 0, 0, 0, 0
	for i = 0, size.X * size.Y - 1, 5 do
		r += buffer.readu8(pixels, i * 4)
		g += buffer.readu8(pixels, i * 4 + 1)
		b += buffer.readu8(pixels, i * 4 + 2)
		count += 1
	end
	image:Destroy()
	local color = Color3.fromRGB(r / count, g / count, b / count)
	averageCache[uri] = color
	return color
end

--- Moves each SurfaceAppearance's colour onto the part and drops it (see header).
local function bakeColors(model: Model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("MeshPart") then
			local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
			if appearance then
				if appearance.ColorMap ~= "" then
					part.Color = averageColor(appearance.ColorMap)
				end
				appearance:Destroy()
			end
		end
	end
end

local function templateFolder(): Folder
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local folder = assets:FindFirstChild("ImportedNukeTemplates")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "ImportedNukeTemplates"
		folder.Parent = assets
	end
	return folder :: Folder
end

local folder = templateFolder()
local report = {}
local claimed: { [Model]: string } = {}

for _, item in ipairs(ITEMS) do
	local ok, err = pcall(function()
		local sources = findSourceNodes(item.marker)
		assert(#sources == 1, `marker "{item.marker}" matched {#sources} scenes, want exactly 1`)
		local source = sources[1]
		assert(claimed[source] == nil, `scene already claimed by {claimed[source]}`)
		claimed[source] = item.itemId

		local model = source:Clone()
		model.Name = item.itemId

		local parts = flatten(model)

		local root = model:FindFirstChild(item.rootPart)
		assert(root and root:IsA("BasePart"), `rootPart "{item.rootPart}" not found after flatten`)
		model.PrimaryPart = root :: BasePart

		-- Pivot on the bounding-box centre (batch 10's lesson).
		local center, extents = model:GetBoundingBox()
		local rootPart = root :: BasePart
		rootPart.PivotOffset = rootPart.CFrame:ToObjectSpace(CFrame.new(center.Position))

		local longest = math.max(extents.X, extents.Y, extents.Z)
		if longest > 0 then
			model:ScaleTo(NATURAL_SIZE / longest)
		end

		bakeColors(model)

		local meshCount = 0
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("MeshPart") then
				meshCount += 1
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Material = Enum.Material.Metal
			end
		end

		model:SetAttribute("ItemModel", "ImportedNuke")
		model:SetAttribute("DisplayName", item.label)
		model:SetAttribute("GallerySize", 9.18)

		local existing = folder:FindFirstChild(item.itemId)
		local verb = if existing then "REPLACED" else "NEW"
		local ext = model:GetExtentsSize()
		if DRY_RUN then
			model:Destroy()
			verb = "dry-" .. verb
		else
			if existing then
				existing:Destroy()
			end
			model.Parent = folder
		end

		table.insert(report, string.format(
			"%-22s %-12s meshes=%-3d rescued=%-3d ext=%.2f,%.2f,%.2f  marker=%s",
			item.itemId, verb, meshCount, parts, ext.X, ext.Y, ext.Z, item.marker
		))
	end)
	if not ok then
		table.insert(report, string.format("%-22s FAILED: %s", item.itemId, tostring(err)))
	end
end

-- Any scene in the region nobody claimed is a model this table forgot.
local unclaimed = 0
for _, aux in ipairs(workspace:GetChildren()) do
	local node = aux.Name == "AuxScene" and aux:FindFirstChild("Node0")
	if node and claimed[node :: Model] == nil then
		local ok, center = pcall(function()
			return (node :: Model):GetBoundingBox()
		end)
		if ok and inRegion(center.Position) then
			unclaimed += 1
		end
	end
end
table.insert(report, `{#ITEMS} items, {unclaimed} unclaimed scene(s) in region, {#folder:GetChildren()} templates`)

print(table.concat(report, "\n"))
return table.concat(report, "\n")
