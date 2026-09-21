--[[
	One-time Studio command-bar migration: build the 15 mapped imported-nuke
	templates from the raw Workspace.AuxScene imports and park them under
	ReplicatedStorage.Assets.ImportedNukeTemplates.

	KEPT IN GIT ON PURPOSE, same reason import-detector-models.luau is: this
	already ran successfully against the connected place, and this file is a
	record of what it did / how to redo it if a future re-import needs the
	same treatment.

	Source geometry lives ONLY in the place file (the raw AuxScene imports are
	not Rojo-synced), so this can't be replayed from git alone -- it assumes
	16 AuxScene-wrapped Node0 models sit in Workspace (Studio's Import 3D
	result), one per nuke design. Scene 3 (an ornate crown/filigree design) is
	deliberately skipped -- not yet mapped to an item.

	WHY THIS CLONES INSTEAD OF AUTHORING GEOMETRY AS DATA (the first version
	of this script, and the original 2026-09-17 batch's ImportedNukeMeshes.luau,
	both did the latter): `MeshPart.MeshId` cannot be WRITTEN by a fresh
	`Instance.new("MeshPart")` in this place -- confirmed directly, "The
	current thread cannot write 'MeshId' (lacking capability NotAccessible)",
	and this held even from the real Studio Command Bar, not just a reduced-
	capability bridge. Cloning a MeshPart that already has MeshId legitimately
	set (i.e. by Studio's own Import 3D flow) sidesteps this entirely --
	Clone() preserves the property without ever "writing" it. So every
	template here is built by finding its source Node0, cloning it, and
	reshaping the clone -- never by authoring a MeshId string and assigning
	it. This is also why the built templates live in ReplicatedStorage.Assets
	(NOT ReplicatedStorage.Shared, which is Rojo-managed and would have this
	folder deleted on the next sync) -- same convention
	ReplicatedStorage.Assets.Tools.Detector already uses for exactly this
	reason (see Shared/ToolModels/init.luau's header).

	Each item is identified by a MARKER part name unique to its scene (chosen
	by eye from the captured part list -- e.g. only the bullion bar has a
	"BullionStrapCross"), not by position in workspace:GetChildren(), which is
	not guaranteed stable across a Studio reload.

	What it does per item:
	  1. Finds the AuxScene whose Node0 contains a MeshPart named `marker`.
	  2. Clones Node0 (the source in Workspace is never touched).
	  3. Flattens the FBX import's nested wrapper Models down to bare
	     MeshParts, recursively (some wrappers nest more than one level).
	  4. Sets PrimaryPart to `rootPart`, centres WorldPivot on the model's own
	     bounding box (does not move geometry -- just defines the pivot every
	     later ScaleTo/PivotTo call uses).
	  5. ScaleTo's the model so its longest bounding-box dimension is
	     NATURAL_SIZE studs -- the one caller that doesn't itself re-normalise
	     to a target size is the plain exhibit pedestal (ExhibitService.
	     renderStand); every other caller (WashService, ToolService, the
	     exhibit locker) re-ScaleTo's its own target on top of this
	     regardless, and ScaleTo is absolute, so stacking just overwrites.
	  6. Strips CanCollide/CanQuery/CanTouch (display props, never physical).
	  7. Recolours/rematerialises to a uniform gunmetal look (the raw import
	     is flat Plastic grey) and sets DisplayName/GallerySize attributes.
	  8. Parents the result into ReplicatedStorage.Assets.ImportedNukeTemplates,
	     replacing any existing template with the same name.

	Re-running this is safe (idempotent) as long as the source AuxScene
	imports are still in Workspace.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Longest bounding-box dimension every built template is normalised to. This
-- is the STANDARD base size for every imported nuke going forward -- any
-- future item added to this migration's ITEMS table gets the same value, no
-- per-item tuning. See point 5 above for how it interacts with each display
-- context's own further normalisation (WashService.WASH_DISPLAY_SIZE,
-- ToolService.HELD_ITEM_SIZE, this file's own GallerySize attribute below).
-- ExhibitService's LOCKER_ITEM_SIZE is the one exception, kept smaller for its
-- physically cramped cabinet bay.
local NATURAL_SIZE = 7.02

-- Remapped on user review (feat/wire-stage2-nuke-imports): the `ValveWheel` scene
-- is the Airtight Nuke (first_aid_tin), not Reactor; the `BrokenCore` scene is the
-- Split Nuke (gate_latch), not Fading. Reactor and Fading have no art yet.
local ITEMS = {
	{ itemId = "old_compass", label = "Guided Nuke", marker = "SeekerWindow", rootPart = "Shell" },
	{ itemId = "mutant_carrot", label = "Mutant Nuke", marker = "Tendril1", rootPart = "Shell" },
	{ itemId = "first_aid_tin", label = "Airtight Nuke", marker = "ValveWheel", rootPart = "Shell" },
	{ itemId = "broken_lantern", label = "Glowless Nuke", marker = "DeadLens1", rootPart = "Shell" },
	{ itemId = "treasure_map", label = "Blueprint Nuke", marker = "PlanRoll", rootPart = "Shell" },
	{ itemId = "pearl_necklace", label = "Pearl Nuke", marker = "CrownPearl", rootPart = "Shell" },
	{ itemId = "old_food_tin", label = "Canned Nuke", marker = "PullTabRing", rootPart = "Shell" },
	{ itemId = "rusty_horseshoe", label = "Lucky Nuke", marker = "Horseshoe", rootPart = "Shell" },
	{ itemId = "garden_trowel", label = "Abandoned Nuke", marker = "EarthMound", rootPart = "Shell" },
	{ itemId = "unlit_signal_flare", label = "Flare Nuke", marker = "BurnPort", rootPart = "Shell" },
	{ itemId = "bullion_bar", label = "Bullion Nuke", marker = "BullionStrapCross", rootPart = "BullionStrapCross" },
	{ itemId = "radiation_badge", label = "Telltale Nuke", marker = "TelltaleFlag", rootPart = "Shell" },
	{ itemId = "gate_latch", label = "Split Nuke", marker = "BrokenCore", rootPart = "UpperShell" },
	{ itemId = "gold_signet", label = "Gilded Nuke", marker = "SignetStone", rootPart = "Shell" },
	{ itemId = "buried_coin_jar", label = "Bottled Nuke", marker = "WaxSeal", rootPart = "BottleBody" },
}

--- Finds the Workspace.AuxScene model whose Node0 contains a MeshPart named
--- `markerPart`, unique to one scene. Robust to AuxScene reordering across a
--- Studio reload, unlike matching by position in workspace:GetChildren().
local function findSourceNode(markerPart: string): Model?
	for _, aux in ipairs(workspace:GetChildren()) do
		if aux.Name == "AuxScene" then
			local node = aux:FindFirstChild("Node0")
			if node and node:FindFirstChild(markerPart, true) then
				return node :: Model
			end
		end
	end
	return nil
end

--- Recursively rescues every MeshPart out of nested FBX wrapper Models,
--- reparenting it directly under `model`, then destroys the now-empty
--- wrappers. Depth-agnostic (some wrappers nest more than one level).
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
		assert(source, `no source AuxScene found for marker "{item.marker}"`)

		local model = source:Clone()
		model.Name = item.itemId

		local rescued = flatten(model)

		local root = model:FindFirstChild(item.rootPart)
		assert(root and root:IsA("BasePart"), `rootPart "{item.rootPart}" not found after flatten`)
		model.PrimaryPart = root :: BasePart

		-- Centres the pivot on the model's own geometry WITHOUT moving any
		-- part -- WorldPivot is purely a reference point for later
		-- ScaleTo/PivotTo calls, not a transform.
		local center, extents = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(center.Position)

		local longest = math.max(extents.X, extents.Y, extents.Z)
		if longest > 0 then
			model:ScaleTo(NATURAL_SIZE / longest)
		end

		-- ANCHORED IS LOAD-BEARING, NOT COSMETIC. The raw import comes in with
		-- every part Anchored = false (confirmed live) -- fine for a static
		-- Studio 3D import sitting untouched in Workspace, but the moment a
		-- clone is parented into the world during a live Play session,
		-- un-anchored MeshParts with no weld between them are individually
		-- affected by gravity: the model doesn't just look wrong, it visibly
		-- falls apart into its ~20-40 loose pieces and scatters/falls through
		-- the floor within a second or two. NukeBase (the old procedural
		-- system) always anchored every part it built, so nothing downstream
		-- ever had to defend against this; WashService happens to force
		-- Anchored = true defensively before display, which is why wash
		-- wasn't affected, but the exhibit pedestal (ExhibitService.
		-- renderStand) isn't defensive and broke exactly this way.
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
