--[[
	Ninth Studio command-bar migration, same shape as the first eight (read
	import-nuke-models.luau's header first). Two scenes:
	  pressure_gauge      Pressurized Nuke  GaugeCan/GaugeNeedle, Handwheel,
	                                        ManifoldHead, ReliefStack, BurstDisc
	  cracked_glow_badge  Fading Nuke       FadingCore, FadePlate1-10, GhostShell,
	                                        Wisps

	Still unmodelled after this: Core Nuke (reactor_core_sample) only.

	KEPT IN GIT ON PURPOSE, same reason as every prior migration.

	REGION-SCOPED like batches 2-8: staged as a two-scene stack at
	X=-443.5/Z=-33, Y from -0.5 to 1.0.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

local REGION_MIN = Vector3.new(-450, -6, -40)
local REGION_MAX = Vector3.new(-437, 7, -26)

local ITEMS = {
	{ itemId = "pressure_gauge", label = "Pressurized Nuke", marker = "ManifoldHead", rootPart = "Shell" },
	{ itemId = "cracked_glow_badge", label = "Fading Nuke", marker = "FadingCore", rootPart = "Shell" },
}

--- Same idea as batch 2-8's findSourceNode, scoped to this batch's own region.
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
		assert(source, `no source AuxScene found in the batch 9 region for marker "{item.marker}"`)

		local model = source:Clone()
		model.Name = item.itemId

		local rescued = flatten(model)

		local root = model:FindFirstChild(item.rootPart)
		assert(root and root:IsA("BasePart"), `rootPart "{item.rootPart}" not found after flatten`)
		model.PrimaryPart = root :: BasePart

		local center, extents = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(center.Position)

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

		-- None of these ids had a template before; overwrite anyway so a re-run
		-- is idempotent.
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
