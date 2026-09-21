--[[
	Fourth Studio command-bar migration, same shape as the first three (read
	import-nuke-models.luau's header first). This one is a RE-IMPORT, not a new
	batch: the very first import pass (batch 1/2) landed with every MeshPart's
	SurfaceAppearance.ColorMap pointing at a texture asset that rendered flat
	grey in Studio -- not a wiring bug, the source art itself had no colour.
	The user re-generated 14 of those designs with real colour and re-imported
	them; this script re-runs the exact same clone/flatten/scale/anchor pipeline
	against the NEW raw scenes and OVERWRITES the existing (grey) templates for
	those same 14 item ids. `sample_case` (Strapped Nuke) was flagged as
	colourless too but is not part of this re-import -- a future batch 5 covers
	it, and its existing grey template is left untouched here.

	KEPT IN GIT ON PURPOSE, same reason as the first three migrations.

	TWO SEARCH REGIONS, NOT ONE: 13 of these 14 restaged as a vertical column
	next to (but not overlapping) batch 2's own column -- around X=0, Y in
	[-68, -50], Z=-108.5, versus batch 2's Z=-99.95 -- but `radiation_scanner`
	landed alone, far away, around (-389, 0, 0). REGION SCOPING IS LOAD-BEARING
	HERE, NOT JUST DEFENSIVE (contrast batch 2/3's headers): every marker this
	script searches for is the SAME name batch 1/2's ORIGINAL migration used
	for the same item (BullionStrapCross, Horseshoe, BurnPort, GovernorCoil,
	ShellCavity, PullTabRing, Corrosion1, ScannerHead, SignetStone, PlanRoll,
	WarningPlacard, TelltaleFlag) -- because the OLD, colourless scenes with
	those exact same marker names are STILL SITTING IN WORKSPACE at their
	original batch 1/2 positions (never deleted -- see this repo's own
	precedent of leaving prior batches' source scenes in place). An unscoped
	search would silently re-clone the grey original instead of the new
	coloured one, whichever happens to sort first in
	`workspace:GetChildren()`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Same value as every prior migration's NATURAL_SIZE.
local NATURAL_SIZE = 7.02

-- The main re-import column (13 of the 14): Node0 bounding-box centers ranged
-- X in [-0.1, 0.1], Y in [-68, -50], Z in [-108.6, -108.5]. Padded generously --
-- this only needs to clear batch 2's own column at Z=-99.95, ~9 studs away.
local MAIN_MIN = Vector3.new(-15, -75, -115)
local MAIN_MAX = Vector3.new(15, -45, -100)

-- radiation_scanner landed alone, far from every other batch's staging area.
local SCANNER_MIN = Vector3.new(-395, -6, -6)
local SCANNER_MAX = Vector3.new(-383, 6, 6)

local ITEMS = {
	{ itemId = "glass_pebble", label = "Marble Nuke", marker = "SwirlBandA", rootPart = "Shell" },
	{ itemId = "bullion_bar", label = "Bullion Nuke", marker = "BullionStrapCross", rootPart = "BullionStrapCross" },
	{ itemId = "rusty_horseshoe", label = "Lucky Nuke", marker = "Horseshoe", rootPart = "Shell" },
	{ itemId = "treasure_map", label = "Blueprint Nuke", marker = "PlanRoll", rootPart = "Shell" },
	{ itemId = "bottle_cap", label = "Dud Nuke", marker = "LithoStripe", rootPart = "Shell" },
	{ itemId = "unlit_signal_flare", label = "Flare Nuke", marker = "BurnPort", rootPart = "Shell" },
	{ itemId = "wind_up_flashlight", label = "Wind-Up Nuke", marker = "GovernorCoil", rootPart = "Shell" },
	{ itemId = "gold_ring", label = "Golden Nuke", marker = "SignetStone", rootPart = "Shell" },
	{ itemId = "film_canister", label = "Exposed Nuke", marker = "ShellCavity", rootPart = "Shell" },
	{ itemId = "old_food_tin", label = "Canned Nuke", marker = "PullTabRing", rootPart = "Shell" },
	{ itemId = "steel_rod", label = "Rusty Nuke", marker = "Corrosion1", rootPart = "Shell" },
	{ itemId = "tin_soldier", label = "Tin Nuke", marker = "WarningPlacard", rootPart = "CoreCanister" },
	{ itemId = "radiation_badge", label = "Telltale Nuke", marker = "TelltaleFlag", rootPart = "Shell" },
	{ itemId = "radiation_scanner", label = "Clicking Nuke", marker = "ScannerHead", rootPart = "Shell" },
}

--- Same idea as batch 2/3's findSourceNode, but checks membership in EITHER of
--- two disjoint regions (see header on why region scoping is load-bearing here).
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
					local inMain = pos.X >= MAIN_MIN.X and pos.X <= MAIN_MAX.X
						and pos.Y >= MAIN_MIN.Y and pos.Y <= MAIN_MAX.Y
						and pos.Z >= MAIN_MIN.Z and pos.Z <= MAIN_MAX.Z
					local inScanner = pos.X >= SCANNER_MIN.X and pos.X <= SCANNER_MAX.X
						and pos.Y >= SCANNER_MIN.Y and pos.Y <= SCANNER_MAX.Y
						and pos.Z >= SCANNER_MIN.Z and pos.Z <= SCANNER_MAX.Z
					if (inMain or inScanner) and node:FindFirstChild(markerPart, true) then
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
		assert(source, `no source AuxScene found in either region for marker "{item.marker}"`)

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

		-- OVERWRITES the existing (grey) template -- that is the entire point of
		-- this migration, unlike batch 1-3 where every id was previously unmapped.
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
