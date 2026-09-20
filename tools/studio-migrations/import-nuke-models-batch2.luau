--[[
	Second one-time Studio command-bar migration, same shape as
	import-nuke-models.luau (read that file's header first — this one only
	documents what's DIFFERENT). Builds the 12 remaining Stage 1 templates
	(every Stage 1 item except Rubber Nuke, which was retired instead of
	modelled — see Config/Items.luau's "RETIRED ITEMS" note) from a second,
	later batch of raw Workspace.AuxScene imports, and parks them alongside
	the first 15 under ReplicatedStorage.Assets.ImportedNukeTemplates.

	KEPT IN GIT ON PURPOSE, same reason as the first migration.

	WHY THIS IS A SEPARATE FILE INSTEAD OF APPENDING TO ITEMS IN THE FIRST
	SCRIPT: that file's header describes itself as a record of a specific,
	already-run batch (16 scenes, scene 3 skipped) -- appending a second
	batch's items to that ITEMS table would misrepresent which scenes that
	run actually touched. Second batch, second file.

	WHY THIS SCRIPT SCOPES ITS SOURCE SEARCH TO A WORLD REGION, UNLIKE THE
	FIRST: the first batch's `findSourceNode` finds the one AuxScene whose
	Node0 contains a marker part name unique ACROSS ALL SCENES. That
	assumption breaks here -- this batch's Gold Nuke (`gold_ring`) source
	scene has the exact same part-name set (Shell, TailTaper, ChasedBand1/2,
	RingCollar, SignetBezel, SignetStone, Fin1-4) as the FIRST batch's
	Gilded Nuke (`gold_signet`) source scene, because both were generated
	from the same "ring" rig/prompt. A marker search for "SignetStone" alone
	is ambiguous between the two. The first batch's 16 scenes and this
	batch's 12 all happen to sit in visually distinct staging clusters in
	Workspace though (confirmed live: the first batch sits at two clusters
	around X=-82/Z=82 and X=77/Z=-31; this batch sits stacked in a column
	around X=0/Z=-100), so restricting the search to a bounding region
	around THIS batch's column sidesteps the collision entirely without
	needing the source art re-tagged. If a future batch reuses a marker name
	AND lands in the same region as an earlier one, this trick stops working
	and the source models need distinguishing some other way (e.g. a marker
	unique to just that design, or moving one batch's staging column).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Same value as import-nuke-models.luau's NATURAL_SIZE -- every imported nuke
-- normalises to this so Stage 1's roster doesn't visibly vary in scale
-- depending on which batch modelled it.
local NATURAL_SIZE = 7.02

-- This batch's staging column, read live off the connected place
-- (Workspace.AuxScene Node0 bounding-box centers ranged X in [-0.1, 0.1],
-- Y in [-80.0, -63.6], Z exactly -100.0). Padded generously on every axis --
-- this only needs to exclude the OTHER batch's two clusters (~157 and ~113
-- studs away respectively), not pin an exact box.
local REGION_MIN = Vector3.new(-15, -95, -115)
local REGION_MAX = Vector3.new(15, -50, -85)

local ITEMS = {
	{ itemId = "bottle_cap", label = "Dud Nuke", marker = "NoseDome", rootPart = "Shell" },
	{ itemId = "steel_rod", label = "Rusty Nuke", marker = "Corrosion1", rootPart = "Shell" },
	{ itemId = "glass_pebble", label = "Marble Nuke", marker = "SwirlBandA", rootPart = "Shell" },
	{ itemId = "tin_can", label = "Dented Nuke", marker = "LithoStripe", rootPart = "Shell" },
	{ itemId = "house_key", label = "Keychain Nuke", marker = "SplitRing", rootPart = "Shell" },
	{ itemId = "stopped_watch", label = "Stopped Nuke", marker = "WindKnob", rootPart = "Shell" },
	{ itemId = "tin_soldier", label = "Tin Nuke", marker = "WarningPlacard", rootPart = "CoreCanister" },
	{ itemId = "wind_up_flashlight", label = "Wind-Up Nuke", marker = "GovernorCoil", rootPart = "Shell" },
	{ itemId = "gold_ring", label = "Golden Nuke", marker = "SignetStone", rootPart = "Shell" },
	{ itemId = "radiation_scanner", label = "Clicking Nuke", marker = "ScannerHead", rootPart = "Shell" },
	{ itemId = "film_canister", label = "Exposed Nuke", marker = "ShellCavity", rootPart = "Shell" },
	{ itemId = "sample_case", label = "Strapped Nuke", marker = "VialPouch", rootPart = "Shell" },
}

--- Same idea as the first migration's findSourceNode, but only considers an
--- AuxScene whose Node0 center falls inside this batch's staging region --
--- see the header note on why (the gold_ring/gold_signet marker collision).
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

		table.insert(report, string.format("%-20s OK  parts=%d  marker=%s", item.itemId, rescued, item.marker))
	end)
	if not ok then
		table.insert(report, string.format("%-20s FAILED: %s", item.itemId, tostring(err)))
	end
end

print(table.concat(report, "\n"))
