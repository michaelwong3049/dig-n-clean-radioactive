--[[
	One-time Studio migration: Rift Outpost's imported gear (2026-10-11), five templates.

	  Detector T16 Fault Splitter   <- Workspace.AuxScene.Fault_Splitter
	  Detector T17 Rift Sovereign   <- Workspace.AuxScene.Rift_Sovereign
	  Magnet   T13 Fault Magnet     <- Workspace.AuxScene.tier_12_rift       (pack numbering one below ours)
	  Magnet   T14 Tectonic Magnet  <- Workspace.AuxScene.tier_13_riftvalley
	  Hose     T14 Riftwalker       <- Workspace.AuxScene.riftwalker_tool    (Cleaner rung 13, Hose.ART_SLOTS)

	KEPT IN GIT ON PURPOSE, like every script beside it: ReplicatedStorage.Assets is not
	Rojo-synced, so this is the only record of what was done to the place file. Run in EDIT
	mode, then rebuild Camps and Save + Publish.

	THREE RECIPES, EACH ITS TRACK'S OWN:

	  * DETECTORS are import-twilight-detectors.luau's: flatten the `_Node` wrappers, scale to
	    one height, weld to `upper_shaft`, a Grip on the handle, HoldCFrame.Y solved so the
	    coil's lowest point sits at FLOOR_IN_ROOT. The handle is `pistol_grip` here (the same
	    kit as the Magma five, whose Grip sits exactly on it); there is no `grip` part.
	    TARGET_HEIGHT 4.8 sits just over the Prime Meridian (4.72).

	  * MAGNETS are import-magma-magnet.luau's contract (sub-Model named after the tier, Grip
	    at the bend turned -90 degrees about X so the poles run along its +Z, one shared
	    TARGET_LENGTH, T6's HoldPart/HoldCFrame) with ONE CHANGE: these imports have no
	    `bend` mesh -- the U is two halves (`*_l_arc` / `*_r_arc`) meeting at the bottom. So
	    an invisible `bend` part is ADDED at the arcs' lowest centre, made the sub-Model's
	    PrimaryPart and the weld root (ToolFX's MOTION_ANCHOR for magnets, if a rig is ever
	    written for them). The poles' tops (`fault_block_l` / `pole_cap_l`; the `horst` parts are feet UNDER the U) must rise from it.

	  * THE HOSE is import-magma-hose.luau's, unchanged: x3.6, turn -X onto -Z, Nozzle core,
	    Muzzle/HoseEnd. Every part must be textured.

	Refuses to run twice (asserts none of the five slots exist), builds and checks every
	template on clones first, and only then parents them into Assets. The AuxScene sources
	are cloned, never moved.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local assets = ReplicatedStorage.Assets
local detectorFolder = assets.Tools.Detector
local magnetFolder = assets.Tools.Magnet
local hoseFolder = assets.HoseModels

assert(detectorFolder:FindFirstChild("T16") == nil and detectorFolder:FindFirstChild("T17") == nil, "Detector T16/T17 already exist: this migration has already run")
assert(magnetFolder:FindFirstChild("T13") == nil and magnetFolder:FindFirstChild("T14") == nil, "Magnet T13/T14 already exist: this migration has already run")
assert(hoseFolder:FindFirstChild("T14") == nil, "HoseModels.T14 already exists: this migration has already run")
assert(detectorFolder:FindFirstChild("T15") and detectorFolder.T15:GetAttribute("TierName") == "Prime Meridian", "Detector T15 is not the Prime Meridian")
assert(magnetFolder:FindFirstChild("T12") and magnetFolder.T12:GetAttribute("TierName") == "Magma Magnet", "Magnet T12 is not the Magma Magnet")
assert(hoseFolder:FindFirstChild("T13") and hoseFolder.T13:GetAttribute("TierName") == "Magma Cannon", "HoseModels.T13 is not the Magma Cannon")

local function partsOf(model: Instance): { BasePart }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function findAuxSource(name: string): Model
	for _, aux in workspace:GetChildren() do
		if aux.Name == "AuxScene" then
			local m = aux:FindFirstChild(name)
			if m and m:IsA("Model") then
				return m
			end
		end
	end
	error(`no {name} under a Workspace.AuxScene to import`)
end

--- Lift every BasePart out of the import's wrapper Models into `into`, then drop them.
local function flattenInto(model: Model, into: Model): number
	local rescued = 0
	for _, p in partsOf(model) do
		p.Parent = into
		rescued += 1
	end
	for _, c in model:GetChildren() do
		if c:IsA("Model") then
			c:Destroy()
		end
	end
	return rescued
end

-- Welds only take their offset in a live DataModel, so everything is built here.
local review = workspace:FindFirstChild("_RiftGearReview")
if review then
	review:Destroy()
end
review = Instance.new("Folder")
review.Name = "_RiftGearReview"
review.Parent = workspace

local built: { { folder: Instance, name: string, model: Model, line: string } } = {}

-- ── Detectors ────────────────────────────────────────────────────────────────

local TARGET_HEIGHT = 4.8
local FLOOR_IN_ROOT = -2.95
local HOLD_X, HOLD_Z = 0.02, -1.1
local oracle = detectorFolder:FindFirstChild("T9")
assert(oracle and oracle:GetAttribute("TierName") == "The Oracle", "Detector T9 is not The Oracle")

for _, spec in { { tier = 16, source = "Fault_Splitter", name = "Fault Splitter" }, { tier = 17, source = "Rift_Sovereign", name = "Rift Sovereign" } } do
	local source = findAuxSource(spec.source)
	local expected = #partsOf(source)
	local work = source:Clone()
	work.Name = "_work_DT" .. spec.tier
	work.Parent = review
	local rescued = 0
	for _, node in work:GetChildren() do
		if node:IsA("Model") then
			for _, p in partsOf(node) do
				p.Parent = work
				rescued += 1
			end
			node:Destroy()
		end
	end
	assert(rescued == expected, `{spec.name}: flatten rescued {rescued} parts, expected {expected}`)

	local _, curSize = work:GetBoundingBox()
	work:ScaleTo(work:GetScale() * TARGET_HEIGHT / curSize.Y)

	local root = work:FindFirstChild("upper_shaft") :: BasePart
	assert(root, `{spec.name}: missing "upper_shaft"`)
	for _, part in partsOf(work) do
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = root
		end
	end

	local gripMesh = work:FindFirstChild("pistol_grip") :: BasePart
	assert(gripMesh, `{spec.name}: missing "pistol_grip"`)
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.14, 0.14, 0.14)
	grip.Transparency = 1
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = true
	grip.Massless = true
	grip.Material = Enum.Material.Plastic
	grip.CFrame = gripMesh.CFrame
	grip.Parent = work
	local gripWeld = Instance.new("WeldConstraint")
	gripWeld.Part0 = root
	gripWeld.Part1 = grip
	gripWeld.Parent = grip

	for _, part in partsOf(work) do
		part.Anchored = false
		if part ~= grip then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	assert(#partsOf(work) == expected + 1, `{spec.name}: final part count {#partsOf(work)}, expected {expected + 1}`)
	work.PrimaryPart = grip
	assert(grip.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999, `{spec.name}: grip is not upright`)
	assert(grip.CFrame.LookVector:Dot(-Vector3.zAxis) > 0.999, `{spec.name}: grip does not look down -Z like the other rungs`)

	local boxCFrame, boxSize = work:GetBoundingBox()
	local lowRel = (boxCFrame.Position.Y - boxSize.Y / 2) - grip.Position.Y
	assert(lowRel < -1, `{spec.name}: the coil is not below the grip (lowRel {lowRel})`)
	local holdY = math.round((FLOOR_IN_ROOT - lowRel) * 1000) / 1000

	work:SetAttribute("TierName", spec.name)
	work:SetAttribute("HoldPart", oracle:GetAttribute("HoldPart"))
	work:SetAttribute("HoldCFrame", CFrame.new(HOLD_X, holdY, HOLD_Z))
	table.insert(built, {
		folder = detectorFolder,
		name = "T" .. spec.tier,
		model = work,
		line = string.format("Detector.T%d %s: %d parts, %.2fx, holdY %.3f", spec.tier, spec.name, expected + 1, work:GetScale(), holdY),
	})
end

-- ── Magnets ──────────────────────────────────────────────────────────────────

local TARGET_LENGTH = 8
local GRIP_SIZE = 0.56
local BEND_SIZE = 0.2
local singularity = magnetFolder:FindFirstChild("T6")
assert(singularity and singularity:GetAttribute("TierName") == "Singularity Coil", "Magnet T6 is not the Singularity Coil")
local holdPart = singularity:GetAttribute("HoldPart")
local holdCFrame = singularity:GetAttribute("HoldCFrame")
assert(typeof(holdCFrame) == "CFrame", "Magnet T6 has no HoldCFrame to share")

for _, spec in {
	{ tier = 13, source = "tier_12_rift", name = "Fault Magnet", arcs = { "plate_l_arc", "plate_r_arc" }, top = "fault_block_l" },
	{ tier = 14, source = "tier_13_riftvalley", name = "Tectonic Magnet", arcs = { "tectonic_l_arc", "tectonic_r_arc" }, top = "pole_cap_l" },
} do
	local source = findAuxSource(spec.source)
	local expected = #partsOf(source)
	local clone = source:Clone()
	local work = Instance.new("Model")
	work.Name = "_work_MT" .. spec.tier
	work.Parent = review
	local body = Instance.new("Model")
	body.Name = spec.name
	body.Parent = work
	assert(flattenInto(clone, body) == expected, `{spec.name}: flatten lost parts`)
	clone:Destroy()

	-- The bend: the U's lowest centre, between the two arc halves' bottoms.
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, n in spec.arcs do
		local arc = body:FindFirstChild(n) :: BasePart
		assert(arc, `{spec.name}: missing "{n}"`)
		local half = arc.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local v = arc.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
					lo, hi = lo:Min(v), hi:Max(v)
				end
			end
		end
	end
	local bendAt = Vector3.new((lo.X + hi.X) / 2, lo.Y + (hi.Y - lo.Y) * 0.25, (lo.Z + hi.Z) / 2)
	local bend = Instance.new("Part")
	bend.Name = "bend"
	bend.Size = Vector3.one * BEND_SIZE
	bend.Transparency = 1
	bend.Material = Enum.Material.Plastic
	bend.CFrame = CFrame.new(bendAt)
	bend.Parent = body
	body.PrimaryPart = bend

	local top = body:FindFirstChild(spec.top) :: BasePart
	assert(top, `{spec.name}: missing "{spec.top}"`)
	local rise = top.Position - bend.Position
	assert(rise.Y > 0.5 * (hi.Y - lo.Y) and math.abs(rise.Z) < 0.05, `{spec.name}: poles do not stand up from the bend (rise {rise})`)

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.one * GRIP_SIZE
	grip.Transparency = 1
	grip.Material = Enum.Material.Plastic
	grip.CFrame = CFrame.new(bendAt) * CFrame.Angles(-math.pi / 2, 0, 0)
	grip.Parent = work
	work.PrimaryPart = grip
	work:PivotTo(CFrame.new(grip.Position))

	local _, boxSize = work:GetBoundingBox()
	work:ScaleTo(work:GetScale() * TARGET_LENGTH / boxSize.Z)
	local topAt = grip.CFrame:PointToObjectSpace(top.Position)
	assert(topAt.Z > 1 and math.abs(topAt.Y) < 0.05, `{spec.name}: poles are not along the Grip's +Z (at {topAt})`)

	for _, part in partsOf(work) do
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = part ~= grip
		part.CanTouch = true
		if part ~= bend then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bend
			weld.Part1 = part
			weld.Parent = if part == grip then grip else bend
		end
	end
	assert(#partsOf(work) == expected + 2, `{spec.name}: final part count {#partsOf(work)}, expected {expected + 2} (parts + bend + Grip)`)

	work:SetAttribute("TierName", spec.name)
	work:SetAttribute("HoldPart", holdPart)
	work:SetAttribute("HoldCFrame", holdCFrame)
	table.insert(built, {
		folder = magnetFolder,
		name = "T" .. spec.tier,
		model = work,
		line = string.format("Magnet.T%d %s: %d parts, %.2fx", spec.tier, spec.name, expected + 2, work:GetScale()),
	})
end

-- ── The hose ─────────────────────────────────────────────────────────────────

local SCALE = 3.6
local NOZZLE_SIZE = 0.3
local MUZZLE_PAST_TIP = 0.05
local HOSEEND_PAST_REAR = 0.08
local HOLD = CFrame.new(0, -0.2, 0) * CFrame.Angles(math.rad(-90), 0, 0)

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
						lo, hi = lo:Min(v), hi:Max(v)
					end
				end
			end
		end
	end
	return lo, hi
end

local function frontmost(model: Model): BasePart
	local best: BasePart? = nil
	local bestZ = math.huge
	for _, p in partsOf(model) do
		local halfZ = (math.abs(p.CFrame.RightVector.Z) * p.Size.X + math.abs(p.CFrame.UpVector.Z) * p.Size.Y + math.abs(p.CFrame.LookVector.Z) * p.Size.Z) / 2
		if p.Position.Z - halfZ < bestZ then
			bestZ = p.Position.Z - halfZ
			best = p
		end
	end
	return best :: BasePart
end

do
	local spec = { n = 14, ident = "riftwalker_tool", name = "Riftwalker" }
	local source = findAuxSource(spec.ident)
	local expected = #partsOf(source)
	for _, p in partsOf(source) do
		assert(p:IsA("MeshPart") and p.TextureID ~= "", `"{spec.ident}" has an untextured part "{p.Name}"`)
	end
	local work = source:Clone()
	work.Name = "_work_HT" .. spec.n
	work.Parent = review
	local rescued = 0
	for _, node in work:GetChildren() do
		if node:IsA("Model") then
			for _, p in partsOf(node) do
				p.Parent = work
				rescued += 1
			end
			node:Destroy()
		end
	end
	assert(rescued == expected, `{spec.name}: flatten rescued {rescued}, expected {expected}`)

	local lo0, hi0 = extents(work)
	local importLength = hi0.X - lo0.X
	work:PivotTo(CFrame.Angles(0, math.rad(-90), 0))
	local lo1, hi1 = extents(work)
	assert(math.abs((hi1.Z - lo1.Z) - importLength) < 0.001, "turn did not lay the import along Z")
	work:ScaleTo(work:GetScale() * SCALE)

	local nose = frontmost(work)
	local lo, hi = extents(work)
	work:PivotTo(work:GetPivot() + -Vector3.new((lo.X + hi.X) / 2, nose.Position.Y, (lo.Z + hi.Z) / 2))
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
	work:SetAttribute("Tier", spec.n)
	work:SetAttribute("TierName", spec.name)
	assert(#partsOf(work) == expected + 1, `{spec.name}: final part count {#partsOf(work)}, expected {expected + 1}`)
	assert(lo.Z < 0 and hi.Z > 0, "the origin is not inside the length")
	table.insert(built, {
		folder = hoseFolder,
		name = "T" .. spec.n,
		model = work,
		line = string.format("HoseModels.T%d %s: %d parts, length %.2f, height %.2f", spec.n, spec.name, expected + 1, hi.Z - lo.Z, hi.Y - lo.Y),
	})
end

-- Only now touch the live ladders.
local report = {}
for _, b in built do
	b.model.Name = b.name
	b.model.Parent = b.folder
	table.insert(report, "[migration] " .. b.line)
end
review:Destroy()
print(table.concat(report, "\n"))
return table.concat(report, "\n")
