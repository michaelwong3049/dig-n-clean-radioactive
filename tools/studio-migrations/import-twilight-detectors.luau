--[[
	One-time Studio command-bar migration: Toxic Twilight's six detectors go in as the
	Detector track's tiers 10-15 (Config/Gear.Detector rows 10-15, `camp = "twilight"`),
	after The Oracle:

	  T10 Vein Whisperer   T11 Aurora Rake   T12 Strata Lance
	  T13 Leyline Tap      T14 Null Compass  T15 Prime Meridian

	KEPT IN GIT ON PURPOSE, same as import-rust-bucket.luau and import-detector-models.luau
	beside it: ReplicatedStorage.Assets is not Rojo-synced, so the only record of what was
	done to the place file is this script. Run it in EDIT mode (a Play-mode edit is thrown
	away on Stop). Then Save and Publish. The shop rack does not change until the Twilight
	camp is rebuilt (`require(game.ServerScriptService.Server.build.CampSite).rebuild()`).

	The sources are the user's Import 3D results, each in its own `Workspace.AuxScene`. They
	are the same kit of parts as the nine before them (`<part>_Node` wrapper models with no
	welds inside, `upper_shaft` and `grip` present), so this is import-rust-bucket.luau's
	recipe run six times, with two differences:

	  * SIZE. Every rung is scaled to one height (`TARGET_HEIGHT`), not to the height of
	    the tier below. The raw imports are not the same size as each other (1.22 to 1.47
	    studs tall) and the earlier "match the old tier's height" rule had a base mesh to
	    match; these have none. 4.0 sits between the Oracle (3.71) and the Resonance
	    Mapper (4.11), the tallest held so far.

	  * HOLD HEIGHT IS COMPUTED, NOT TUNED. import-detector-models.luau needed five rounds
	    of live Play tuning to find each tier's `HoldCFrame.Y`, and the answer had a fixed
	    shape: with identity rotation and collision off, the model hangs straight down from
	    its Grip, so the coil's lowest point sits `lowRel` studs below the grip, and the
	    right Y is the one that puts that point at the floor. T8 and T9 land the lowest point
	    at -2.997 and -3.023 in the character root's frame (holdY 0.390 with lowest -3.387,
	    holdY 0.451 with lowest -3.474), and the root rests 3.0 above the floor. So the target
	    is `FLOOR_IN_ROOT` = -2.95: 0.05 of clearance like every earlier rung, because -3.0
	    puts the coil exactly on the ground and it would clip during the sweep. The script
	    measures `lowRel` and solves for it. Checked in Play on the Strata Lance: root.Y stays
	    flat at 1.500 with a tier equipped (a collidable part would lift the character), and
	    no part is collidable.

	HOLD POSE: identity rotation, X/Z shared with every other rung (0.02, -1.1). Every tier
	is oriented the same way (grip up = +Y, look = -Z), which the script asserts.

	Refuses to run twice: if T10 already exists it stops before changing anything, and it
	asserts every source is present and every part count adds up before it touches the live
	folder. The sources are cloned, never moved, so the imports stay in AuxScene as a safety
	net until someone cleans them out.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TARGET_HEIGHT = 4.0
local FLOOR_IN_ROOT = -2.95 -- where the coil's lowest point belongs, in the character root's frame
local HOLD_X, HOLD_Z = 0.02, -1.1 -- shared by every rung of the track

local TIERS = {
	{ tier = 10, source = "Vein_Whisperer", name = "Vein Whisperer" },
	{ tier = 11, source = "Aurora_Rake", name = "Aurora Rake" },
	{ tier = 12, source = "Strata_Lance", name = "Strata Lance" },
	{ tier = 13, source = "Leyline_Tap", name = "Leyline Tap" },
	{ tier = 14, source = "Null_Compass", name = "Null Compass" },
	{ tier = 15, source = "Prime_Meridian", name = "Prime Meridian" },
}

local detectorFolder = ReplicatedStorage.Assets.Tools.Detector
assert(detectorFolder:FindFirstChild("T10") == nil, "T10 already exists: this migration has already run")

local oracle = detectorFolder:FindFirstChild("T9")
assert(oracle and oracle:GetAttribute("TierName") == "The Oracle", "T9 is not The Oracle; the ladder is not where this expects it")

local function countParts(model: Instance): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function flatten(model: Model): number
	local rescued = 0
	for _, node in model:GetChildren() do
		if node:IsA("Model") then
			local parts = {}
			for _, d in node:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
				end
			end
			for _, p in parts do
				p.Parent = model
				rescued += 1
			end
			node:Destroy()
		end
	end
	return rescued
end

-- Everything is built and checked on clones first; the live folder is touched last.
local built: { { tier: number, model: Model, holdY: number, parts: number } } = {}

for _, spec in TIERS do
	local source = workspace:FindFirstChild(spec.source, true)
	assert(source and source:IsA("Model"), `no {spec.source} model in Workspace to import`)
	assert(source.Parent and source.Parent.Name == "AuxScene", `{spec.source} is not an Import 3D result (its parent is not AuxScene)`)

	local expected = countParts(source)
	local work = source:Clone()
	work.Name = "_work_T" .. spec.tier
	work.Parent = workspace

	local rescued = flatten(work)
	assert(rescued == expected, `{spec.name}: flatten rescued {rescued} parts, expected {expected}`)

	local _, curSize = work:GetBoundingBox()
	work:ScaleTo(TARGET_HEIGHT / curSize.Y)

	local root = work:FindFirstChild("upper_shaft") :: BasePart
	assert(root, `{spec.name}: missing reference part "upper_shaft"`)
	for _, part in work:GetChildren() do
		if part:IsA("BasePart") and part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end

	local gripMesh = work:FindFirstChild("grip") :: BasePart?
	assert(gripMesh, `{spec.name}: missing "grip"`)
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
	grip.CFrame = gripMesh.CFrame
	grip.Parent = work
	local gripWeld = Instance.new("WeldConstraint")
	gripWeld.Part0 = root
	gripWeld.Part1 = grip
	gripWeld.Parent = grip

	-- A held prop is never collidable: welded to the character, a part buried in the
	-- terrain shoves the WHOLE assembly upward ("the Oracle makes the player float").
	for _, part in work:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			if part ~= grip then
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
	end

	local final = countParts(work)
	assert(final == expected + 1, `{spec.name}: final part count {final}, expected {expected + 1} (parts + Grip)`)

	work.PrimaryPart = grip

	-- Identity hold rotation only works if the model already hangs its coil straight
	-- down from the grip, like the nine before it.
	assert(grip.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999, `{spec.name}: grip is not upright`)
	assert(grip.CFrame.LookVector:Dot(-Vector3.zAxis) > 0.999, `{spec.name}: grip does not look down -Z like the other rungs`)

	local boxCFrame, boxSize = work:GetBoundingBox()
	local lowRel = (boxCFrame.Position.Y - boxSize.Y / 2) - grip.Position.Y
	assert(lowRel < -1, `{spec.name}: the coil is not below the grip (lowRel {lowRel})`)
	local holdY = math.round((FLOOR_IN_ROOT - lowRel) * 1000) / 1000

	work:SetAttribute("TierName", spec.name)
	work:SetAttribute("HoldPart", oracle:GetAttribute("HoldPart"))
	work:SetAttribute("HoldCFrame", CFrame.new(HOLD_X, holdY, HOLD_Z))

	table.insert(built, { tier = spec.tier, model = work, holdY = holdY, parts = final })
end

-- Only now touch the live ladder.
for _, b in built do
	b.model.Name = "T" .. b.tier
	b.model.Parent = detectorFolder
	print(`[migration] Detector.T{b.tier} {b.model:GetAttribute("TierName")}: {b.parts} parts, {string.format("%.2f", b.model:GetScale())}x, holdY {b.holdY}`)
end
