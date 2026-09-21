--[[
	Seventh Studio command-bar migration, same shape as the first six (read
	import-nuke-models.luau's header first). Twelve new Stage 6 scenes, staged as
	two vertical stacks at X=-461.5: seven at Z=30.7 and five at Z=3.7.

	Identified by part names; Alien, Mini, Cosmic, The Big One and Warped were
	checked on screen, and the user picked Warped for the rift scene:
	  sealed_air_filter       Unopened Nuke  TamperWire/BarcodePlate/SealBlob -- still sealed
	  scorched_metal_plate    Scorched Nuke  CharredHoop/Soot/AshFlake/Ember
	  untouched_ground_sample Pristine Nuke  PresentationCollar/Plaque/Engraving
	  bent_door_wheel         Warped Nuke    RiftEye/RiftFrame/Tendril -- dark egg
	  explorers_helmet        Pioneer Nuke   HelmetDome/Flag/MissionPatch
	  skyglow_core_fragment   Sky-Glow Nuke  AuroraCore/AuroraRibbon/Canopy
	  ufo_fragment            Alien Nuke     IrisCore/ChitinRib/Claw/Feeler -- green
	  glassy_ground_chip      Glassy Nuke    TrappedCore/Bubble/GlassDrip
	  fused_tool_roll         Welded Nuke    WeldClamp/WeldBead/PatchPlate
	  mini_nuke               Mini Nuke      FuzeDial/GripHandle -- small green bomb
	  stopped_second_hand     Cosmic Nuke    StarCore in a gimbal on a Plinth (no Shell)
	  unlabeled_cylinder      The Big One    a single plain "Cylinder" capsule part

	Still unmodelled in Stage 6: Fading.

	KEPT IN GIT ON PURPOSE, same reason as every prior migration.

	REGION-SCOPED like batches 2-6. The box stops short of batch 5's stack at
	X=-463/Z=38.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

local REGION_MIN = Vector3.new(-470, -5, -2)
local REGION_MAX = Vector3.new(-454, 15, 35)

local ITEMS = {
	{ itemId = "sealed_air_filter", label = "Unopened Nuke", marker = "TamperWire1", rootPart = "Shell" },
	{ itemId = "scorched_metal_plate", label = "Scorched Nuke", marker = "CharredHoop", rootPart = "Shell" },
	{ itemId = "untouched_ground_sample", label = "Pristine Nuke", marker = "PresentationCollar", rootPart = "Shell" },
	{ itemId = "bent_door_wheel", label = "Warped Nuke", marker = "RiftEye", rootPart = "Shell" },
	{ itemId = "explorers_helmet", label = "Pioneer Nuke", marker = "MissionPatch", rootPart = "Shell" },
	{ itemId = "skyglow_core_fragment", label = "Sky-Glow Nuke", marker = "AuroraCore", rootPart = "Shell" },
	{ itemId = "ufo_fragment", label = "Alien Nuke", marker = "IrisCore", rootPart = "Shell" },
	{ itemId = "glassy_ground_chip", label = "Glassy Nuke", marker = "TrappedCore", rootPart = "Shell" },
	{ itemId = "fused_tool_roll", label = "Welded Nuke", marker = "WeldClamp", rootPart = "Shell" },
	{ itemId = "mini_nuke", label = "Mini Nuke", marker = "FuzeDial", rootPart = "Shell" },
	{ itemId = "stopped_second_hand", label = "Cosmic Nuke", marker = "StarCore", rootPart = "Plinth" },
	{ itemId = "unlabeled_cylinder", label = "The Big One", marker = "Cylinder", rootPart = "Cylinder" },
}

--- Same idea as batch 2-6's findSourceNode, scoped to this batch's own region.
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
		assert(source, `no source AuxScene found in the batch 7 region for marker "{item.marker}"`)

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
