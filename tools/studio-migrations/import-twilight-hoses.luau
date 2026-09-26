--[[
	One-time Studio migration: Toxic Twilight's five hoses, Cleaner tiers 8-12.

	The same recipe as import-hose-models.luau (read its header for the frame, the
	Nozzle core, Muzzle/HoseEnd and why this is a migration and not code), run on the
	second art pack the user imported for the Twilight Hose Shop: `singularity`, `cryo`,
	`solar`, `quantum`, `celestial`, each two or three textured MeshParts in FBX
	`<part>_Node` wrappers, lying along X with the nozzle toward -X, like the first pack.

	SAME SCALE AS T1-T7 (3.6), so the new rungs land at 3.0-3.4 studs long against the
	Plasma Lance's 3.5 and the wash bay's tub clearance is unchanged.

	Writes ReplicatedStorage.Assets.HoseModels.T8..T12. Re-running is safe (an existing
	T<n> moves to HoseModels._Legacy), but the AuxScene sources were deleted at the
	user's request once the templates checked out, so this is now a record, not a tool.
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

-- `ident` is the import's model name; `n` is the Gear.Cleaner rung. The user's order,
-- not the order they sit in AuxScene (solar, cryo, celestial, singularity, quantum).
local TIERS = {
	{ n = 8, ident = "singularity", name = "Singularity Nozzle" },
	{ n = 9, ident = "cryo", name = "Cryo Nova" },
	{ n = 10, ident = "solar", name = "Solar Forge" },
	{ n = 11, ident = "quantum", name = "Quantum Rift" },
	{ n = 12, ident = "celestial", name = "Celestial Deluge" },
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
