--[[
	One-time Studio migration: give the Cleaner track's seven hoses real art.

	Shared/ToolModels/Hose builds every hose from primitives. This turns the seven
	hand-imported, TEXTURED models the user brought in via Studio's Import 3D (Garden,
	Fire, Lance, Chem, Ultrasonic, Ion, Plasma) into ready-to-clone templates under
	ReplicatedStorage.Assets.HoseModels.T1..T7, which Hose.create now clones in place
	of the primitive build. The primitive build stays as the fallback for a place with
	no templates.

	KEPT IN GIT ON PURPOSE, same reason as import-detector-models.luau: the templates
	live ONLY in the place file (ReplicatedStorage.Assets is not Rojo-synced), so this
	is the record of how they were made. It cannot be replayed from git alone: it
	assumes the imports already sit in Workspace.AuxScene. Run it from the Command Bar
	(or an Edit-mode execute_luau). Re-running is safe: a T<n> that already exists is
	moved to HoseModels._Legacy, never overwritten.

	WHY A MIGRATION AND NOT CODE: MeshPart.MeshId cannot be written from a script in
	this place (see the studio-live-validation notes), so mesh art can only ever be
	CLONED from an existing MeshPart. Every template here is a clone of the import.

	WHICH IMPORT. The user imported the hoses three times. Two sets are the uncoloured
	`<name>_tool` models (about a hundred untextured mesh parts each) and one is the
	COLOURED set with plain names (`garden`, `firehose`, ...: two to four MeshParts
	each, one shared TextureID per model). Only the coloured set is used, and the
	script insists every mesh part carries a TextureID so it cannot quietly pick up an
	uncoloured one.

	THE FRAME, which is the whole job (Hose.luau's header has the long version):
	  * authored at the origin; -Z is the business end; +Y is up.
	  * the PrimaryPart is `Nozzle`, an INVISIBLE axis-aligned 0.3 block, Anchored, with
	    `Muzzle` and `HoseEnd` Attachments on it. World.verify() fails the whole rebuild
	    over a hose missing either.
	  * every visible part is welded to it (`ShellWeld`), unanchored and massless, with
	    all collision off, exactly as the primitive build leaves it.

	WHAT THE IMPORT NEEDS TO GET THERE:
	  1. Flatten the FBX `<part>_Node` wrapper Models down to bare MeshParts.
	  2. Turn it. The imports lie along X with the barrel toward -X and the grip hanging
	     down; a yaw of -90 degrees sends -X to -Z and leaves the grip down.
	  3. Scale it by SCALE. The imports came in ~3.5x undersized (FBX unit mismatch).
	     ONE factor for all seven, not a per-tier fit: the artist drew the ladder's
	     proportions (a Lance longer than a Garden Hose) and a per-tier fit would flatten
	     them. 3.6 was picked by matching the old primitive ladder, whose lengths ran
	     2.0-4.2 studs, so the wash bay's tub clearance is not disturbed.
	  4. Re-origin. The barrel axis runs through the origin (its height is the Y of the
	     front-most part, which is the barrel or emitter) and the origin sits at the
	     middle of the length, which is where the primitive hoses kept theirs.
	  5. Muzzle just past the front tip, HoseEnd just past the rear, both on the axis.

	The originals in Workspace.AuxScene are never touched: every step works on a clone,
	and the clone is only moved into Assets after its part count is verified.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- One factor for every tier. See WHAT THE IMPORT NEEDS, step 3.
local SCALE = 3.6

local NOZZLE_SIZE = 0.3
-- The same overshoots the primitive build uses: the muzzle a hair past the tip so the
-- spray starts in open air, the hose end a hair past the rear so the line meets metal.
local MUZZLE_PAST_TIP = 0.05
local HOSEEND_PAST_REAR = 0.08

-- Hose.HOLD, restated because this runs outside the game and cannot require it.
local HOLD = CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(-90), 0, 0)

-- `ident` is the coloured import's model name; `n` is the Gear.Cleaner rung.
local TIERS = {
	{ n = 1, ident = "garden", name = "Garden Hose" },
	{ n = 2, ident = "firehose", name = "Patched Fire Hose" },
	{ n = 3, ident = "lance", name = "Pressure Lance" },
	{ n = 4, ident = "chem", name = "Chem Injector" },
	{ n = 5, ident = "ultrasonic", name = "Ultrasonic Jet" },
	{ n = 6, ident = "ion", name = "Ion Cannon" },
	{ n = 7, ident = "plasma", name = "Plasma Lance" },
}

local assets = ReplicatedStorage:FindFirstChild("Assets")
assert(assets, "ReplicatedStorage.Assets is missing")

-- NOT Assets/Tools/Cleaner: that folder still holds the retired brushes and sponges,
-- and every lookup that reaches it must keep losing to the hose factory.
local folder = assets:FindFirstChild("HoseModels")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "HoseModels"
	folder.Parent = assets
end

local legacy = folder:FindFirstChild("_Legacy")
if not legacy then
	legacy = Instance.new("Folder")
	legacy.Name = "_Legacy"
	legacy.Parent = folder
end

-- Welds only take their offset once both parts are in a live DataModel, so the work
-- is done in Workspace and moved into Assets at the end.
local review = workspace:FindFirstChild("_HoseReview")
if review then
	review:Destroy()
end
review = Instance.new("Folder")
review.Name = "_HoseReview"
review.Parent = workspace

--- The coloured import of `ident`. Most descendants wins if it was imported twice.
local function findSource(ident: string): Model?
	local best: Model? = nil
	local bestCount = -1
	for _, aux in workspace:GetChildren() do
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

local function partsOf(model: Instance): { BasePart }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

--- FBX wraps each part in a `<part>_Node` Model. Lift every BasePart out and drop the
--- wrappers. A wrapper can hold several parts, so rescue ALL of them: taking only the
--- first is what deleted detail geometry in the detector migration.
local function flatten(model: Model): number
	local rescued = 0
	for _, node in model:GetChildren() do
		if node:IsA("Model") then
			for _, p in partsOf(node) do
				p.Parent = model
				rescued += 1
			end
			node:Destroy()
		end
	end
	return rescued
end

--- Min and max corner of every part in `model` except the core, in world space.
local function extents(model: Model): (Vector3, Vector3)
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, p in partsOf(model) do
		if p.Name ~= "Nozzle" then
			local half = p.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local v = p.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						lo = lo:Min(v)
						hi = hi:Max(v)
					end
				end
			end
		end
	end
	return lo, hi
end

--- The part whose nose reaches furthest toward -Z: the barrel or the emitter.
local function frontmost(model: Model): BasePart
	local best: BasePart? = nil
	local bestZ = math.huge
	for _, p in partsOf(model) do
		-- Half the part's reach along Z: after the turn a part's X and Z sizes swap, so
		-- read it off the part's own axes rather than assuming which size is which.
		local halfZ = (
			math.abs(p.CFrame.RightVector.Z) * p.Size.X
			+ math.abs(p.CFrame.UpVector.Z) * p.Size.Y
			+ math.abs(p.CFrame.LookVector.Z) * p.Size.Z
		) / 2
		local z = p.Position.Z - halfZ
		if z < bestZ then
			bestZ = z
			best = p
		end
	end
	return best :: BasePart
end

local report = {}

for _, tier in TIERS do
	local ok, err = pcall(function()
		local source = findSource(tier.ident)
		assert(source, `no imported model named "{tier.ident}" under Workspace.AuxScene`)

		local expectedParts = #partsOf(source)
		for _, p in partsOf(source) do
			assert(p:IsA("MeshPart") and p.TextureID ~= "", `"{tier.ident}" has an untextured part "{p.Name}": wrong (uncoloured) set?`)
		end

		-- Work on a CLONE. The import is never touched.
		local work = source:Clone()
		work.Name = `T{tier.n}`
		work.Parent = review

		local rescued = flatten(work)
		assert(rescued == expectedParts, `flatten rescued {rescued} parts, expected {expectedParts}`)

		-- Step 2: turn -X onto -Z. `PivotTo` also moves the pivot to the origin.
		local lo0, hi0 = extents(work)
		local importLength = hi0.X - lo0.X
		work:PivotTo(CFrame.Angles(0, math.rad(-90), 0))
		local lo1, hi1 = extents(work)
		assert(math.abs((hi1.Z - lo1.Z) - importLength) < 0.001, "turn did not lay the import along Z")

		-- Step 3: scale, about the origin the turn just set.
		work:ScaleTo(work:GetScale() * SCALE)

		-- Step 4: re-origin on the barrel axis, at the middle of the length.
		local nose = frontmost(work)
		local lo, hi = extents(work)
		local axisY = nose.Position.Y
		local shift = -Vector3.new((lo.X + hi.X) / 2, axisY, (lo.Z + hi.Z) / 2)
		work:PivotTo(work:GetPivot() + shift)
		lo, hi = extents(work)

		local core = Instance.new("Part")
		core.Name = "Nozzle"
		core.Size = Vector3.one * NOZZLE_SIZE
		core.CFrame = CFrame.new()
		core.Transparency = 1
		core.Anchored = true
		core.Massless = true
		core.CanCollide = false
		core.CanQuery = false
		core.CanTouch = false
		core.Parent = work

		-- Welded, unanchored, massless and inert: a prop, not physics.
		for _, part in partsOf(work) do
			if part ~= core then
				part.Anchored = false
				part.Massless = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false

				local weld = Instance.new("WeldConstraint")
				weld.Name = "ShellWeld"
				weld.Part0 = core
				weld.Part1 = part
				weld.Parent = part
			end
		end

		-- Step 5. Identity rotation, like the primitive build, so the reel's Beam
		-- leaves HoseEnd the same way it always has.
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "Muzzle"
		muzzle.CFrame = CFrame.new(0, 0, lo.Z - MUZZLE_PAST_TIP)
		muzzle.Parent = core

		local hoseEnd = Instance.new("Attachment")
		hoseEnd.Name = "HoseEnd"
		hoseEnd.CFrame = CFrame.new(0, 0, hi.Z + HOSEEND_PAST_REAR)
		hoseEnd.Parent = core

		work.PrimaryPart = core
		work:SetAttribute("HoldCFrame", HOLD)
		work:SetAttribute("Tier", tier.n)
		work:SetAttribute("TierName", tier.name)

		-- Verify before anything live is touched.
		local finalParts = #partsOf(work)
		assert(finalParts == expectedParts + 1, `final part count {finalParts}, expected {expectedParts + 1} (parts + Nozzle)`)
		assert(lo.Z < 0 and hi.Z > 0, "the origin is not inside the length")

		local existing = folder:FindFirstChild(`T{tier.n}`)
		if existing then
			existing.Name = `T{tier.n}_Prev`
			existing.Parent = legacy
		end
		work.Parent = folder

		table.insert(
			report,
			string.format(
				"T%d %s: OK, %d parts + Nozzle, length %.2f, height %.2f, muzzle z %.2f, hoseEnd z %.2f",
				tier.n,
				tier.name,
				expectedParts,
				hi.Z - lo.Z,
				hi.Y - lo.Y,
				muzzle.CFrame.Z,
				hoseEnd.CFrame.Z
			)
		)
	end)
	if not ok then
		table.insert(report, string.format("T%d %s: FAILED - %s", tier.n, tier.name, tostring(err)))
	end
end

review:Destroy()
print(table.concat(report, "\n"))
return table.concat(report, "\n")
