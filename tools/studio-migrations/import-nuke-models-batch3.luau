--[[
	Third one-time Studio command-bar migration, same shape as
	import-nuke-models.luau / import-nuke-models-batch2.luau (read the first
	file's header first). Builds 16 templates from a third batch of raw
	Workspace.AuxScene imports -- ten of them finish out Stage 2's roster
	(every remaining unmodelled Stage 2 item except none; Stage 2 is now
	fully modelled), plus one Stage 5 piece and three Stage 3/6 pieces,
	parked alongside the first 27 under ReplicatedStorage.Assets.ImportedNukeTemplates.

	Also carries the feat/wire-stage2-nuke-imports rename: `gate_latch` displays
	as "Split Nuke" now, not "Snapped Nuke" (Config/Items.luau) -- unrelated to
	this script's job, noted here only because gate_latch is one of the 16
	items this batch models.

	KEPT IN GIT ON PURPOSE, same reason as the first two migrations.

	WHY THIS SCRIPT SCOPES ITS SOURCE SEARCH TO A WORLD REGION, SAME AS BATCH 2:
	this batch's raw scenes are staged as a vertical stack (not a horizontal
	cluster like the first two batches) at a distinct column around
	X=-145.2/Z=170.6, Y climbing from ~71 to ~93 one scene at a time. Region
	scoping isn't strictly required for marker-collision avoidance here (this
	batch's chosen markers don't collide with the first two batches' marker
	sets), but it's kept anyway as the established defensive pattern -- several
	part names in this batch (Shell, TailTaper, HoopBand1/2, Fin1-4) are
	extremely common across ALL THREE batches' scenes, so an unscoped search
	keyed on any one of those alone would be ambiguous.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Same value as the first two migrations' NATURAL_SIZE.
local NATURAL_SIZE = 7.02

-- This batch's staging column (Workspace.AuxScene Node0 bounding-box centers
-- ranged X in [-145.25, -145.15], Y in [71.2, 92.8], Z in [170.5, 170.7]).
-- Padded generously -- this only needs to exclude the other two batches'
-- clusters (~X=-82/Z=82, ~X=77/Z=-31, ~X=0/Z=-100), not pin an exact box.
local REGION_MIN = Vector3.new(-155, 65, 160)
local REGION_MAX = Vector3.new(-135, 98, 180)

local ITEMS = {
	{ itemId = "door_hinge", label = "Creaky Nuke", marker = "SwingSeam", rootPart = "Shell" },
	{ itemId = "deposit_box", label = "Vault Nuke", marker = "CombinationDial", rootPart = "Shell" },
	{ itemId = "photo_locket", label = "Keepsake Nuke", marker = "LocketHinge", rootPart = "LocketHalf1" },
	{ itemId = "ignition_coil", label = "Ignition Nuke", marker = "SparkPin", rootPart = "Shell" },
	{ itemId = "doll_head", label = "Toy Nuke", marker = "TopKnob", rootPart = "Shell" },
	{ itemId = "cutlery_set", label = "Tarnished Nuke", marker = "Finial", rootPart = "Shell" },
	{ itemId = "clock_movement", label = "Clockwork Nuke", marker = "WindCrown", rootPart = "Shell" },
	{ itemId = "charm_bracelet", label = "Trinket Nuke", marker = "Bail", rootPart = "Shell" },
	{ itemId = "socket_set", label = "Socketed Nuke", marker = "DriveSquare", rootPart = "Shell" },
	{ itemId = "cracked_tile", label = "Cracked Nuke", marker = "Fissure1", rootPart = "Shell" },
	{ itemId = "pressure_gauge", label = "Pressurized Nuke", marker = "PressureGauge", rootPart = "Shell" },
	{ itemId = "rusted_farm_safe", label = "Buried Nuke", marker = "ShoringTimber1", rootPart = "Shell" },
	{ itemId = "diamond_brooch", label = "Diamond Nuke", marker = "GemPavilion", rootPart = "GemPavilion" },
	{ itemId = "gate_latch", label = "Split Nuke", marker = "SnapCollar", rootPart = "LowerShell" },
	{ itemId = "skyglow_core_fragment", label = "Sky-Glow Nuke", marker = "CoreHalo", rootPart = "Shell" },
	{ itemId = "unlabeled_cylinder", label = "The Big One", marker = "ForkBase", rootPart = "Shell" },
}

--- Same idea as the first migration's findSourceNode, but only considers an
--- AuxScene whose Node0 center falls inside this batch's staging region.
local function findSourceNode(markerPart: string): Model?
	for _, aux in ipairs(workspace:GetChildren()) do
		if aux.Name == "AuxScene" then
			local node = aux:FindFirstChild("Node0")
			if node then
				local ok, center = pcall(function()
					return (node :: Model):GetBoundingBox()
				end)
				if ok and center.Position.X >= REGION_MIN.X and center.Position.X <= REGION_MAX.X
					and center.Position.Y >= REGION_MIN.Y and center.Position.Y <= REGION_MAX.Y
					and center.Position.Z >= REGION_MIN.Z and center.Position.Z <= REGION_MAX.Z
					and node:FindFirstChild(markerPart, true)
				then
					return node :: Model
				end
			end
		end
	end
	return nil
end

--- Identical to the first migration's flatten -- see its comment.
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
		assert(source, `no source AuxScene found in this batch's region for marker "{item.marker}"`)

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
