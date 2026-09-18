--[[
	One-time Studio command-bar migration: swap the Detector track's 8 tier
	models (previously one reused base mesh, "Metal Detector Ctx 3030",
	recoloured per tier in ToolTiers.Detector) for 8 individually hand-authored
	models the user imported via Studio's 3D import.

	KEPT IN GIT ON PURPOSE. `Shared/ToolModels/init.luau`'s header laments
	that the ORIGINAL Detector/Magnet generator "ran from the command bar once
	and was then lost" -- this file is the same kind of one-off, so it isn't
	getting lost the same way twice. It already ran successfully in Studio;
	keeping it here is documentation of what the migration did and a
	reference if the same shape of problem comes up again (e.g. for Magnet).
	Re-running it against a place that has already been migrated will fail
	loudly (old T<n> won't be found once renamed into _Legacy) rather than
	silently double-applying.

	Source geometry lives ONLY in the place file (ReplicatedStorage.Assets is
	not Rojo-synced -- see ToolModels/init.luau), so this can't be replayed
	from git alone; it assumes the 8 imports already sit in Workspace as
	AuxScene-wrapped models named after each tier (Studio's Import 3D result).

	What it does per tier:
	  1. Finds the imported model in Workspace.AuxScene by tier name (for a
	     name with duplicate imports, picks the one with more descendants).
	  2. Works on a CLONE, never the source import directly -- if anything
	     below fails or under-counts, the original import is untouched.
	  3. Flattens the FBX import's "<part>_Node" wrapper Models down to bare
	     MeshParts. IMPORTANT: some wrappers (e.g. "control_box",
	     "detector_head") hold SEVERAL parts each, not one -- flatten must
	     rescue every BasePart descendant of a wrapper, not just the first it
	     finds, or it silently deletes detail geometry (coil, screen, LEDs)
	     along with the wrapper. This is exactly the bug the first pass of
	     this migration hit.
	  4. Rescales it (Model:ScaleTo) so its height matches the OLD T<n>'s
	     height -- the raw import came in ~2-3x undersized (an FBX unit
	     mismatch), so this restores the game's existing per-tier size
	     progression instead of inventing a new one.
	  5. Rigidly welds every part to one reference part ("upper_shaft") --
	     the import has zero internal Weld/Motor6D, it's a loose bag of parts.
	  6. Sets CanCollide/CanQuery/CanTouch = false on EVERY part (see NOT
	     PHYSICAL below) -- the raw import defaults these true.
	  7. Adds an invisible 0.14-stud "Grip" anchor part (mirrors the OLD
	     model's contract exactly: Transparency 1, CanCollide/CanQuery false,
	     Massless, BrickColor "Medium stone grey") and sets it PrimaryPart --
	     this is what ToolService welds to the character and positions via
	     the model's HoldCFrame/HoldPart attributes.
	  8. Verifies the clone's final part count (parts + Grip) against the
	     source's actual part count before touching anything live.
	  9. Only after that verification: moves the old T<n> aside into
	     Detector._Legacy (kept, not deleted) and places the new model at
	     Detector.T<n>.

	NOT PHYSICAL. The raw import's MeshParts default to CanCollide = true.
	Because the model is RIGIDLY WELDED to the character (see step 5/7), a
	large enough colliding part embedded in the terrain doesn't just look
	wrong -- physics resolves the overlap by shoving the WHOLE WELDED
	ASSEMBLY, character included, upward. This is what "the Oracle makes the
	player float" was: its big search-coil clips into the ground, and with
	CanCollide left true that pushed the player's HumanoidRootPart up with
	it. Confirmed by reading root.Position.Y before/after: it moved off its
	resting height (1.5) exactly as much as the coil's ground penetration,
	and pinning CanCollide/CanQuery/CanTouch false on every part made it
	flat at 1.5 regardless of tier. A held/display prop should never carry
	real collision -- set this once here rather than trusting every future
	import to come in already flagged correctly.

	HOLD POSE: a FIXED, RETUNED HoldCFrame per tier -- position only,
	identity rotation, NOT the old model's carried-over rotation, and NOT
	one shared Y offset either. Two rounds of playtesting, both against a
	live Play session:

	Round 1 found the OLD model's HoldCFrame ROTATION doesn't transfer at
	all -- it was tuned for the OLD base mesh's own arbitrary import
	orientation and, applied to this geometry, held the detector almost
	horizontal against the chest. The NEW import's local geometry already
	hangs the coil straight down from the grip (how it was authored), so an
	identity rotation is correct -- confirmed by comparing a farthest-part
	position in Grip-local space (`grip.CFrame:PointToObjectSpace(
	farPart.Position)`) before assuming any rotation is needed.

	Round 1 ALSO used one shared HoldCFrame.Y for all 8 tiers, which looked
	fine on T1-T5 but was invisibly wrong for T6-T8: those measurements were
	taken while the CanCollide bug above was still active, and the
	collision push was propping the character's feet up by almost exactly
	the amount the coil clipped into the ground, so the on-screen "clearance"
	read as small when the true (physics-honest) clearance was large and
	negative. Lesson: RETUNE POSITION ONLY AFTER FIXING COLLISION, and treat
	any pose measurement taken with collidable held-geometry as suspect --
	compare `root.Position.Y` against its known resting value (here, 1.5) to
	catch this before trusting a "looks close enough" clearance number.
	Round 2, with collision off, gave every tier a clean, independent
	Y offset landing its lowest point ~0.05 studs above the floor:

	  T1 -0.70   T2 -0.60   T3 -0.46   T4 -0.31
	  T5 -0.27   T6 -0.06   T7 -0.03   T8 +0.39

	If a future re-import changes any tier's proportions, re-tune that
	tier's Y alone (X/Z and the identity rotation are shape-independent)
	with collision already disabled, not before.

	The original AuxScene imports in Workspace are left alone by this script.
	Delete them from Workspace once the new tiers have been playtested.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- holdY: per-tier HoldCFrame.Y, retuned live (round 2, collision already
-- disabled -- see NOT PHYSICAL / HOLD POSE above). X/Z and the identity
-- rotation are shared across all 8; only the vertical offset is per-tier.
local TIERS = {
	{ n = 1, ident = "Bent_Coil", name = "Bent Coil", holdY = -0.70 },
	{ n = 2, ident = "Scavenger_MkI", name = "Scavenger MkI", holdY = -0.60 },
	{ n = 3, ident = "Surplus_Geiger", name = "Surplus Geiger", holdY = -0.46 },
	{ n = 4, ident = "Pulse_Array", name = "Pulse Array", holdY = -0.31 },
	{ n = 5, ident = "Isotope_Scanner", name = "Isotope Scanner", holdY = -0.27 },
	{ n = 6, ident = "Resonance_Mapper", name = "Resonance Mapper", holdY = -0.06 },
	{ n = 7, ident = "Deep_Core_Array", name = "Deep Core Array", holdY = -0.03 },
	{ n = 8, ident = "The_Oracle", name = "The Oracle", holdY = 0.39 },
}

local detectorFolder = ReplicatedStorage.Assets.Tools.Detector

local legacy = detectorFolder:FindFirstChild("_Legacy")
if not legacy then
	legacy = Instance.new("Folder")
	legacy.Name = "_Legacy"
	legacy.Parent = detectorFolder
end

local reviewRoot = workspace:FindFirstChild("_DetectorReview")
if not reviewRoot then
	reviewRoot = Instance.new("Folder")
	reviewRoot.Name = "_DetectorReview"
	reviewRoot.Parent = workspace
end

-- Shared X/Z, identity rotation -- retuned live (see this file's header).
-- Y is per-tier, from TIERS[n].holdY.
local function holdCFrame(holdY: number): CFrame
	return CFrame.new(0.02, holdY, -1.1)
end

--- Every imported tier model sits directly under an AuxScene wrapper. Picks
--- the largest match by descendant count so a duplicate/corrected re-import
--- wins over an earlier attempt.
local function findSource(ident)
	local best = nil
	local bestCount = -1
	for _, aux in ipairs(workspace:GetChildren()) do
		if aux.Name == "AuxScene" then
			local candidate = aux:FindFirstChild(ident)
			if candidate and candidate:IsA("Model") then
				local count = #candidate:GetDescendants()
				if count > bestCount then
					best = candidate
					bestCount = count
				end
			end
		end
	end
	return best
end

local function flatten(model)
	local rescued = 0
	for _, node in ipairs(model:GetChildren()) do
		if node:IsA("Model") then
			local parts = {}
			for _, d in ipairs(node:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			for _, p in ipairs(parts) do
				p.Parent = model
				rescued = rescued + 1
			end
			node:Destroy()
		end
	end
	return rescued
end

local function countSourceParts(model)
	local total = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			total = total + 1
		end
	end
	return total
end

local function weldAll(model, rootName)
	local root = model:FindFirstChild(rootName)
	assert(root, `missing reference part "{rootName}"`)
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end
	return root
end

--- The raw import defaults every MeshPart to collidable. Rigidly welded to
--- the character, a colliding part embedded in the terrain shoves the WHOLE
--- assembly (character included) upward instead of just clipping visually
--- -- see NOT PHYSICAL in this file's header. A held/display prop must never
--- carry real collision.
local function stripPhysicality(model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
end

local function makeGrip(model, root)
	local gripMesh = model:FindFirstChild("grip")
	local anchorCFrame = gripMesh and gripMesh.CFrame or root.CFrame

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.14, 0.14, 0.14)
	grip.Transparency = 1
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = true
	grip.Massless = true
	grip.Anchored = false
	grip.Material = Enum.Material.Plastic
	grip.BrickColor = BrickColor.new("Medium stone grey")
	grip.CFrame = anchorCFrame
	grip.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = grip
	weld.Parent = grip

	return grip
end

local report = {}

for _, tier in ipairs(TIERS) do
	local ok, err = pcall(function()
		local source = findSource(tier.ident)
		assert(source, `no imported model found for "{tier.ident}"`)
		local expectedParts = countSourceParts(source)

		local oldModel = detectorFolder:FindFirstChild("T" .. tier.n)
		assert(oldModel, `old T{tier.n} missing`)
		local _, oldSize = oldModel:GetBoundingBox()
		local oldHeight = oldSize.Y
		local oldHoldPart = oldModel:GetAttribute("HoldPart")

		-- Work on a CLONE. The original import in Workspace is never touched.
		local work = source:Clone()
		work.Parent = reviewRoot

		local rescued = flatten(work)
		assert(rescued == expectedParts, `flatten rescued {rescued} parts, expected {expectedParts}`)

		local _, curSize = work:GetBoundingBox()
		local factor = oldHeight / curSize.Y
		work:ScaleTo(factor)

		local root = weldAll(work, "upper_shaft")
		local grip = makeGrip(work, root)
		stripPhysicality(work)

		-- Verify nothing is missing before this clone becomes the real thing.
		local finalParts = 0
		for _, d in ipairs(work:GetDescendants()) do
			if d:IsA("BasePart") then
				finalParts = finalParts + 1
			end
		end
		assert(finalParts == expectedParts + 1, `final part count {finalParts}, expected {expectedParts + 1} (parts + Grip)`)

		work.Name = "T" .. tier.n
		work:SetAttribute("TierName", tier.name)
		work:SetAttribute("HoldPart", oldHoldPart)
		work:SetAttribute("HoldCFrame", holdCFrame(tier.holdY))
		work.PrimaryPart = grip

		-- Only now touch anything live: move the old model aside (kept, not
		-- deleted) and place the verified new one in its spot.
		oldModel.Name = "T" .. tier.n .. "_Legacy"
		oldModel.Parent = legacy
		work.Parent = detectorFolder

		table.insert(report, string.format(
			"T%d %s: OK, %d parts (source had %d), scale x%.2f (h %.2f -> %.2f)",
			tier.n, tier.name, finalParts, expectedParts, factor, curSize.Y, oldHeight
		))
	end)
	if not ok then
		table.insert(report, string.format("T%d %s: FAILED - %s", tier.n, tier.name, tostring(err)))
	end
end

print(table.concat(report, "\n"))
