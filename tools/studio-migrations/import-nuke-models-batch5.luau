--[[
	Fifth Studio command-bar migration, same shape as the first four (read
	import-nuke-models.luau's header first). Three coloured re-imports that
	replace wrong or missing templates:

	  bottle_cap  (Dud Nuke)    <- ShellCavity scene: a plain egg-shaped shell with
	                              a crack (BentFin/PeeledPlate/SplitSeam).
	  tin_can     (Dented Nuke) <- NoseDome/BaseRim scene: the dome-topped canister.
	  tin_soldier (Tin Nuke)    <- LithoStripe scene: blue with an orange band
	                              (PressedCap/RolledSeam).

	CHECKED ON SCREEN, NOT JUST BY PART NAMES: the first pass guessed from names
	alone (NoseDome -> Dud, since batch 2 used it for Dud) and the user caught it --
	NoseDome is the Dented one. Batch 4 had Dented and Tin mixed up too; its table
	no longer lists either id, so re-running it will not undo this.

	KEPT IN GIT ON PURPOSE, same reason as every prior migration.

	REGION SCOPING IS LOAD-BEARING (same as batch 4): all three markers also exist
	on older scenes still sitting in Workspace (batch 2's column near X=0/Z=-100 and
	batch 4's near X=0/Z=-108.5). This batch was staged as a small vertical stack
	at X=-463/Z=38, Y from -0.7 to 1.9 -- nowhere near any other batch.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

local REGION_MIN = Vector3.new(-470, -6, 30)
local REGION_MAX = Vector3.new(-456, 8, 46)

local ITEMS = {
	{ itemId = "bottle_cap", label = "Dud Nuke", marker = "ShellCavity", rootPart = "Shell" },
	{ itemId = "tin_can", label = "Dented Nuke", marker = "NoseDome", rootPart = "Shell" },
	{ itemId = "tin_soldier", label = "Tin Nuke", marker = "LithoStripe", rootPart = "Shell" },
}

--- Same idea as batch 2-4's findSourceNode, scoped to this batch's own region.
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
		assert(source, `no source AuxScene found in the batch 5 region for marker "{item.marker}"`)

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

		-- OVERWRITES any existing template for the id (tin_can/tin_soldier had the
		-- swapped batch 4 designs).
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
