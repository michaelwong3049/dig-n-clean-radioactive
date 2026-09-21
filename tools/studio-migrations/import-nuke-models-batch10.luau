--[[
	Tenth Studio command-bar migration, same shape as the first nine (read
	import-nuke-models.luau's header first). One scene: Stage 5's Core Nuke
	(reactor_core_sample), a lidded lead cask -- CaskBase, three ShieldBands, a
	Pit on its Pedestal with four Initiators, CaskLid/LidBoss/HoistBail, two
	CoolantRiser rings, TamperTags.

	Nothing is left unmodelled after this: Core Nuke was the last item on the
	placeholder cube.

	KEPT IN GIT ON PURPOSE, same reason as every prior migration.

	REGION-SCOPED like batches 2-9: staged alone at X=-28/Z=-122, Y=-26.3.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

local REGION_MIN = Vector3.new(-34, -32, -128)
local REGION_MAX = Vector3.new(-22, -20, -116)

local ITEMS = {
	{ itemId = "reactor_core_sample", label = "Core Nuke", marker = "PitCollar", rootPart = "Shell" },
}

--- Same idea as batch 2-9's findSourceNode, scoped to this batch's own region.
local function findSourceNode(markerPart: string): Model?
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
					if inRegion and node:FindFirstChild(markerPart, true) then
						return node :: Model
					end
				end
			end
		end
	end
	return nil
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

for _, item in ipairs(ITEMS) do
	local ok, err = pcall(function()
		local source = findSourceNode(item.marker)
		assert(source, `no source AuxScene found in the batch 10 region for marker "{item.marker}"`)

		local model = source:Clone()
		model.Name = item.itemId

		local rescued = flatten(model)

		local root = model:FindFirstChild(item.rootPart)
		assert(root and root:IsA("BasePart"), `rootPart "{item.rootPart}" not found after flatten`)
		model.PrimaryPart = root :: BasePart

		local center, extents = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(center.Position)
		-- WorldPivot is ignored once PrimaryPart is set: the pivot is then
		-- PrimaryPart.CFrame * PrimaryPart.PivotOffset. This scene's Shell sits ~0.2
		-- of its length off the bounding-box centre (HoistBail, placard and tags are
		-- lopsided), which left it ~1.1 studs off its yard stand -- the worst of all
		-- 67. Pivot on the bounding-box centre instead.
		local rootPart = root :: BasePart
		rootPart.PivotOffset = rootPart.CFrame:ToObjectSpace(CFrame.new(center.Position))

		local longest = math.max(extents.X, extents.Y, extents.Z)
		if longest > 0 then
			model:ScaleTo(NATURAL_SIZE / longest)
		end

		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("MeshPart") then
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

		-- No template existed for this id before; overwrite anyway so a re-run is
		-- idempotent.
		local existing = folder:FindFirstChild(item.itemId)
		if existing then
			existing:Destroy()
		end
		model.Parent = folder

		table.insert(report, string.format("%-24s OK  parts=%d  marker=%s", item.itemId, rescued, item.marker))
	end)
	if not ok then
		table.insert(report, string.format("%-24s FAILED: %s", item.itemId, tostring(err)))
	end
end

print(table.concat(report, "\n"))
