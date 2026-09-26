--[[
	Twelfth Studio command-bar migration, same shape as batch 11 (read
	import-nuke-models.luau's header first). One scene: Airtight Nuke
	(first_aid_tin), a pressure vessel with a handwheel valve, a gauge and a charge
	hose. It overwrites Airtight's existing template.

	It is (near enough) the same model batch 11 installed for Pressurized Nuke
	(pressure_gauge): 37 of its 38 meshes match. Batches 6/7 also gave these two
	items a shared ValveWheel/PressureGauge design.

	KEPT IN GIT ON PURPOSE, same reason as every prior migration.

	REGION-SCOPED: staged alone at X=54.6/Z=-109.3, Y=-38.1.

	Set DRY_RUN = true to build the template orphaned, report, and destroy.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DRY_RUN = false

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

local REGION_MIN = Vector3.new(50, -42, -114)
local REGION_MAX = Vector3.new(60, -34, -104)

local ITEMS = {
	{ itemId = "first_aid_tin", label = "Airtight Nuke", marker = "GaugeNeedle", rootPart = "Vessel" },
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
				if ok then
					local pos = center.Position
					local inRegion = pos.X >= REGION_MIN.X and pos.X <= REGION_MAX.X
						and pos.Y >= REGION_MIN.Y and pos.Y <= REGION_MAX.Y
						and pos.Z >= REGION_MIN.Z and pos.Z <= REGION_MAX.Z
					if inRegion and hasPart(node, marker) then
						table.insert(found, node :: Model)
					end
				end
			end
		end
	end
	return found
end

--- Identical to every prior migration's flatten -- see the first one's comment.
local function flatten(model: Model)
	local function collect(container: Instance)
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("MeshPart") then
				if child.Parent ~= model then
					child.Parent = model
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
end

local folder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("ImportedNukeTemplates")
local report = {}

for _, item in ipairs(ITEMS) do
	local ok, err = pcall(function()
		local sources = findSourceNodes(item.marker)
		assert(#sources == 1, `marker "{item.marker}" matched {#sources} scenes, want exactly 1`)

		local model = sources[1]:Clone()
		model.Name = item.itemId
		flatten(model)

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
		if DRY_RUN then
			model:Destroy()
			verb = "dry-" .. verb
		else
			if existing then
				existing:Destroy()
			end
			model.Parent = folder
		end

		table.insert(report, string.format("%-16s %-12s meshes=%d", item.itemId, verb, meshCount))
	end)
	if not ok then
		table.insert(report, string.format("%-16s FAILED: %s", item.itemId, tostring(err)))
	end
end

table.insert(report, `{#folder:GetChildren()} templates`)
print(table.concat(report, "\n"))
return table.concat(report, "\n")
