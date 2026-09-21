--[[
	Sixth Studio command-bar migration, same shape as the first five (read
	import-nuke-models.luau's header first). Ten new scenes: nine Stage 5 items
	plus Stage 4's Reactor Nuke.

	Identified by part names, with the two least obvious (Reactor, Polished)
	checked on screen:
	  old_pipe_scrap      Pipe Nuke       FuzeElbow/Wick/HoseClamp -- cobbled together
	  shiny_metal_blade   Polished Nuke   plain egg: Finial/TrimRing/SeamBand
	  rad_warning_placard Labelled Nuke   ManifestTag/ShippingPlate/TapeStrip
	  old_headphones      Static Nuke     ElectrodeHorn/Arc/SparkNode
	  reactor_logbook     Marked Nuke     Bullseye/ChalkMark/Reticle
	  cooling_valve_wheel Seized Nuke     Padlock/Chain/EvidenceSeal
	  sealed_data_drive   Encrypted Nuke  CipherRotor/Keypad/Glyph
	  sealed_fuel_casing  Drained Nuke    EmptyCavity/DrainValve/Residue
	  blackbox_recorder   Black-Box Nuke  BeaconPinger/DataPort/HiVisBand
	  reactor_rod         Reactor Nuke    CorePit/RingCoil/Magnet in a cage, on a
	                                      Plinth (no Shell part -- root is Plinth)

	Still unmodelled in Stage 5: Pressurized, Core, Atomic Bomb.

	KEPT IN GIT ON PURPOSE, same reason as every prior migration.

	REGION-SCOPED like batches 2-5: Finial is also cutlery_set's batch 3 marker,
	and Shell is on nearly every scene. This batch was staged as a vertical stack
	at X=-402.3/Z=-5.75, Y from 1.9 to 15.3 -- clear of batch 4's lone
	radiation_scanner at X=-389.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

local REGION_MIN = Vector3.new(-410, -5, -14)
local REGION_MAX = Vector3.new(-396, 22, 2)

local ITEMS = {
	{ itemId = "old_pipe_scrap", label = "Pipe Nuke", marker = "FuzeElbow", rootPart = "Shell" },
	{ itemId = "shiny_metal_blade", label = "Polished Nuke", marker = "Finial", rootPart = "Shell" },
	{ itemId = "rad_warning_placard", label = "Labelled Nuke", marker = "ManifestTag", rootPart = "Shell" },
	{ itemId = "old_headphones", label = "Static Nuke", marker = "ElectrodeHorn1", rootPart = "Shell" },
	{ itemId = "reactor_logbook", label = "Marked Nuke", marker = "Bullseye", rootPart = "Shell" },
	{ itemId = "cooling_valve_wheel", label = "Seized Nuke", marker = "Padlock", rootPart = "Shell" },
	{ itemId = "sealed_data_drive", label = "Encrypted Nuke", marker = "CipherRotor1", rootPart = "Shell" },
	{ itemId = "sealed_fuel_casing", label = "Drained Nuke", marker = "EmptyCavity", rootPart = "Shell" },
	{ itemId = "blackbox_recorder", label = "Black-Box Nuke", marker = "BeaconPinger", rootPart = "Shell" },
	{ itemId = "reactor_rod", label = "Reactor Nuke", marker = "CorePit", rootPart = "Plinth" },
}

--- Same idea as batch 2-5's findSourceNode, scoped to this batch's own region.
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
		assert(source, `no source AuxScene found in the batch 6 region for marker "{item.marker}"`)

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
