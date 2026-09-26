--[[
	Thirteenth Studio command-bar migration, same shape as batch 11 (read
	import-nuke-models.luau's header first). 26 scenes:

	  * 24 REDESIGNS. Each one overwrites an existing item's template in
	    Assets.ImportedNukeTemplates -- same id, new art.
	  * 2 NEW ROCKETS for the stages the first three skipped: Cruise Nuke (Stage 5,
	    the winged missile) and Booster Nuke (Stage 6, the big rocket with strap-on
	    boosters). New ids added to Items.luau in the same change.

	Mapped by part names (the staged scenes carry them). The less certain picks:
	the laurel signet bomb is Golden (Gilded kept batch 11's crowned egg), the
	coolant cask is Core (not Reactor), the arming-panel bomb is Atomic Bomb, the
	hovering monolith is The Big One, the aurora bomb is Sky-Glow, the flattened-fin
	bomb is Dented (not Rusty), the harness-and-pouch bomb is Strapped.

	KEPT IN GIT ON PURPOSE, same reason as every prior migration.

	REGION-SCOPED like batches 2-12. This batch staged in five small vertical
	stacks, all inside one box: X=-426..-327, Z=-54..18, Y=-1..14.

	MARKERS MATCH ON THE BASE NAME (trailing digits and underscores stripped), and
	each must pick out exactly ONE scene -- the script refuses an ambiguous marker
	instead of guessing.

	Set DRY_RUN = true to build every template orphaned (never parented), report,
	and destroy -- nothing in the place changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DRY_RUN = false

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

local REGIONS = {
	{ min = Vector3.new(-432, -5, -60), max = Vector3.new(-320, 18, 24) },
}

local ITEMS = {
	-- Stage 1
	{ itemId = "house_key", label = "Keychain Nuke", marker = "KeyABow", rootPart = "Shell" },
	{ itemId = "radiation_scanner", label = "Clicking Nuke", marker = "ClickLamp", rootPart = "Shell" },
	{ itemId = "gold_ring", label = "Golden Nuke", marker = "Laurel", rootPart = "Shell" },
	{ itemId = "tin_can", label = "Dented Nuke", marker = "FlattenedFin", rootPart = "Shell" },
	{ itemId = "sample_case", label = "Strapped Nuke", marker = "CinchStrap", rootPart = "Shell" },
	-- Stage 5
	{ itemId = "blackbox_recorder", label = "Black-Box Nuke", marker = "RecorderCase", rootPart = "Shell" },
	{ itemId = "sealed_data_drive", label = "Encrypted Nuke", marker = "KeyCard", rootPart = "Shell" },
	{ itemId = "reactor_logbook", label = "Marked Nuke", marker = "ChalkX", rootPart = "Shell" },
	{ itemId = "cooling_valve_wheel", label = "Seized Nuke", marker = "EvidenceTape", rootPart = "Shell" },
	{ itemId = "old_headphones", label = "Static Nuke", marker = "LadderArc", rootPart = "Shell" },
	{ itemId = "pressure_gauge", label = "Pressurized Nuke", marker = "Accumulator", rootPart = "Accumulator" },
	{ itemId = "rad_warning_placard", label = "Labelled Nuke", marker = "ManifestLabel", rootPart = "Shell" },
	{ itemId = "reactor_core_sample", label = "Core Nuke", marker = "CoolantRiser", rootPart = "Cask" },
	{ itemId = "live_fuel_rod", label = "Atomic Bomb", marker = "ArmingPanel", rootPart = "Casing" },
	{ itemId = "sealed_fuel_casing", label = "Drained Nuke", marker = "EmptyCavity", rootPart = "OpenShell" },
	{ itemId = "cruise_missile", label = "Cruise Nuke", marker = "Wing", rootPart = "Shell" },
	-- Stage 6
	{ itemId = "cracked_glow_badge", label = "Fading Nuke", marker = "DissolveEdge", rootPart = "SolidBase" },
	{ itemId = "unlabeled_cylinder", label = "The Big One", marker = "Monolith", rootPart = "Monolith" },
	{ itemId = "stopped_second_hand", label = "Cosmic Nuke", marker = "StarCore", rootPart = "StarCore" },
	{ itemId = "mini_nuke", label = "Mini Nuke", marker = "GiantFuze", rootPart = "StubbyShell" },
	{ itemId = "ufo_fragment", label = "Alien Nuke", marker = "Carapace", rootPart = "Hull" },
	{ itemId = "bent_door_wheel", label = "Warped Nuke", marker = "TwistedShell", rootPart = "TwistedShell" },
	{ itemId = "skyglow_core_fragment", label = "Sky-Glow Nuke", marker = "AuroraCore", rootPart = "LowerShell" },
	{ itemId = "glassy_ground_chip", label = "Glassy Nuke", marker = "FusedShell", rootPart = "FusedShell" },
	{ itemId = "scorched_metal_plate", label = "Scorched Nuke", marker = "EmberCrack", rootPart = "Shell" },
	{ itemId = "booster_rocket", label = "Booster Nuke", marker = "BoosterBell", rootPart = "Shell" },
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
