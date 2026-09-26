--[[
	Eleventh Studio command-bar migration, same shape as the first ten (read
	import-nuke-models.luau's header first). 27 scenes:

	  * 24 REDESIGNS. Each one overwrites an existing item's template in
	    Assets.ImportedNukeTemplates -- same id, new art. Items.luau is unchanged for
	    these; only the mesh behind the id moves.
	  * 3 NEW ROCKETS, one per Stage 1/2/3 (Rocket / Seeker / Two-Stage Nuke), new
	    ids added to Items.luau in the same change.

	Five items were close calls, settled by the user: the steampunk gear bomb is
	Clockwork (not Wind-Up), the teal bomb with the snapped fin is Dud (not Rusty),
	the crowned gold egg is Gilded (not Golden), the shovel in the dirt mound is
	Buried (not Abandoned), and the taped, cracked bomb is Cracked.

	KEPT IN GIT ON PURPOSE, same reason as every prior migration.

	REGION-SCOPED like batches 2-10. This batch staged in two clusters: a vertical
	stack of 23 at X=54.6/Z=-109.3 (Y -38..4) and a stack of 4 at X=788/Z=-85
	(Y 47..51).

	MARKERS MATCH ON THE BASE NAME (trailing digits and underscores stripped), so
	`Ruby` finds `Ruby1`..`Ruby6`, and each must pick out exactly ONE scene -- the
	script refuses an ambiguous marker instead of guessing. The small rocket has no
	part name of its own (Shell/NoseCone/NoseTip/Band/Fin/Nozzle are all in the
	two-stage rocket too), so it is found by `NoseCone` and told apart by NOT having
	an `UpperStage`.

	Set DRY_RUN = true to build every template orphaned (never parented), report,
	and destroy -- nothing in the place changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DRY_RUN = false

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

local REGIONS = {
	{ min = Vector3.new(50, -42, -114), max = Vector3.new(60, 8, -104) },
	{ min = Vector3.new(783, 44, -90), max = Vector3.new(793, 55, -80) },
}

local ITEMS = {
	-- Stage 1
	{ itemId = "bottle_cap", label = "Dud Nuke", marker = "SnappedFin", rootPart = "Shell" },
	{ itemId = "glass_pebble", label = "Marble Nuke", marker = "SwirlOrange", rootPart = "GlassShell" },
	{ itemId = "stopped_watch", label = "Stopped Nuke", marker = "BellStem", rootPart = "Shell" },
	{ itemId = "tin_soldier", label = "Tin Nuke", marker = "LithoStripe", rootPart = "Shell" },
	{ itemId = "model_rocket", label = "Rocket Nuke", marker = "NoseCone", without = "UpperStage", rootPart = "Shell" },
	-- Stage 2
	{ itemId = "cracked_tile", label = "Cracked Nuke", marker = "TapeStrip", rootPart = "Shell" },
	{ itemId = "cutlery_set", label = "Tarnished Nuke", marker = "FinialBall", rootPart = "Shell" },
	{ itemId = "doll_head", label = "Toy Nuke", marker = "StarSticker", rootPart = "Shell" },
	{ itemId = "socket_set", label = "Socketed Nuke", marker = "RatchetHandle", rootPart = "Shell" },
	{ itemId = "mutant_carrot", label = "Mutant Nuke", marker = "OozeCap", rootPart = "Shell" },
	{ itemId = "pearl_necklace", label = "Pearl Nuke", marker = "ClamHinge", rootPart = "Shell" },
	{ itemId = "clock_movement", label = "Clockwork Nuke", marker = "GovernorBall", rootPart = "Shell" },
	{ itemId = "deposit_box", label = "Vault Nuke", marker = "ThrowBolt", rootPart = "ArmourShell" },
	{ itemId = "seeker_missile", label = "Seeker Nuke", marker = "SeekerDome", rootPart = "Airframe" },
	-- Stage 3 (some also stock Stage 4)
	{ itemId = "rusty_horseshoe", label = "Lucky Nuke", marker = "Horseshoe", rootPart = "Shell" },
	{ itemId = "gate_latch", label = "Split Nuke", marker = "BridgeWire", rootPart = "UpperShell" },
	{ itemId = "old_food_tin", label = "Canned Nuke", marker = "PeeledLid", rootPart = "CanBody" },
	{ itemId = "unlit_signal_flare", label = "Flare Nuke", marker = "FlareTube", rootPart = "FlareTube" },
	{ itemId = "broken_lantern", label = "Glowless Nuke", marker = "BulbGlass", rootPart = "Shell" },
	{ itemId = "gold_signet", label = "Gilded Nuke", marker = "Ruby", rootPart = "Shell" },
	{ itemId = "radiation_badge", label = "Telltale Nuke", marker = "TelltaleFlag", rootPart = "Shell" },
	{ itemId = "buried_coin_jar", label = "Bottled Nuke", marker = "WaxSeal", rootPart = "Bottle" },
	{ itemId = "bullion_bar", label = "Bullion Nuke", marker = "GoldNugget", rootPart = "FacetedShell" },
	{ itemId = "diamond_brooch", label = "Diamond Nuke", marker = "BrilliantBody", rootPart = "BrilliantBody" },
	{ itemId = "rusted_farm_safe", label = "Buried Nuke", marker = "ShovelBlade", rootPart = "Shell" },
	{ itemId = "two_stage_rocket", label = "Two-Stage Nuke", marker = "UpperStage", rootPart = "Shell" },
	-- Stage 5
	{ itemId = "pressure_gauge", label = "Pressurized Nuke", marker = "GaugeNeedle", rootPart = "Vessel" },
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

--- Every AuxScene Node0 in this batch's regions carrying `marker` (and not
--- `without`). The caller asserts there is exactly one.
local function findSourceNodes(marker: string, without: string?): { Model }
	local found = {}
	for _, aux in ipairs(workspace:GetChildren()) do
		if aux.Name == "AuxScene" then
			local node = aux:FindFirstChild("Node0")
			if node then
				local ok, center = pcall(function()
					return (node :: Model):GetBoundingBox()
				end)
				if ok and inRegion(center.Position) and hasPart(node, marker)
					and (without == nil or not hasPart(node, without))
				then
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
		local sources = findSourceNodes(item.marker, item.without)
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

		-- Pivot on the bounding-box centre, not the root part's own centre (batch 10's
		-- lesson: once PrimaryPart is set, WorldPivot is ignored and the pivot is
		-- PrimaryPart.CFrame * PivotOffset, which leaves a lopsided model off its stand).
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
			"%-20s %-12s meshes=%-3d rescued=%-3d ext=%.2f,%.2f,%.2f  marker=%s",
			item.itemId, verb, meshCount, parts, ext.X, ext.Y, ext.Z, item.marker
		))
	end)
	if not ok then
		table.insert(report, string.format("%-20s FAILED: %s", item.itemId, tostring(err)))
	end
end

-- Any scene in the regions nobody claimed is a model this table forgot.
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
