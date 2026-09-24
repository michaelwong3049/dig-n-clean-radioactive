--[[
	One-time Studio command-bar migration: the Rust Bucket goes in as the Detector
	track's new free tier 1 (Config/Gear.Detector), and every existing tier moves up
	one: T1 (Bent Coil) -> T2, ..., T8 (The Oracle) -> T9.

	KEPT IN GIT ON PURPOSE, same as import-detector-models.luau beside it:
	ReplicatedStorage.Assets is not Rojo-synced, so the only record of what was done
	to the place file is this script. Run it in EDIT mode (a Play-mode edit is thrown
	away on Stop). Then Save and Publish, and rebuild the shop rack
	(`require(game.ServerScriptService.Server.build.Shops).rebuild()`) so the Detector
	stall hangs nine tiers.

	The source is the user's Import 3D result, `Workspace.AuxScene.Rust_Bucket`. It is
	the same kit of parts as the other eight: `<part>_Node` wrapper models with no welds
	inside, and `upper_shaft` / `grip` present. So the recipe is the one
	import-detector-models.luau worked out over five rounds, applied to one model:

	  1. Work on a CLONE; the import in Workspace is never touched.
	  2. Flatten every wrapper, keeping EVERY BasePart inside it (some hold several).
	  3. Scale to the Bent Coil's height, so the free rung reads the same size in the hand
	     as the rung above it. Import 3D brings models in at the wrong scale.
	  4. Weld everything to `upper_shaft`, add the invisible `Grip` PrimaryPart, and turn
	     off CanCollide/CanQuery/CanTouch on every part. A collidable held prop lifts the
	     whole character off the ground ("the Oracle makes the player float").
	  5. Count the parts again before touching anything live.
	  6. Shift T8..T1 up to T9..T2 (highest first, so no two share a name), then drop
	     the clone in as T1.

	HOLD POSE: identity rotation, shared X/Z, and a Y (`HOLD_Y`) tuned live in a Play
	session, with collision already off, until the coil's lowest point sits ~0.05 studs
	over the floor with `root.Position.Y` unmoved. See import-detector-models.luau's
	header for why the measurement is only trustworthy with collision off.

	Refuses to run twice: if T9 already exists the ladder has been shifted, and it
	stops before changing anything.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SOURCE = "Rust_Bucket"
local NAME = "Rust Bucket"
local HOLD_Y = -0.063 -- tuned live: lowest point 0.05 over the floor, root.Y flat at 1.5
local OLD_TIERS = 8

local detectorFolder = ReplicatedStorage.Assets.Tools.Detector
assert(detectorFolder:FindFirstChild("T" .. (OLD_TIERS + 1)) == nil, "T9 already exists: this migration has already run")

local aux = workspace:FindFirstChild("AuxScene")
local source = aux and aux:FindFirstChild(SOURCE)
assert(source and source:IsA("Model"), `no Workspace.AuxScene.{SOURCE} to import`)

local bentCoil = detectorFolder:FindFirstChild("T1")
assert(bentCoil and bentCoil:GetAttribute("TierName") == "Bent Coil", "T1 is not the Bent Coil; the ladder is not where this expects it")

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

local expected = countParts(source)
local work = source:Clone()
work.Parent = workspace

local rescued = flatten(work)
assert(rescued == expected, `flatten rescued {rescued} parts, expected {expected}`)

local _, bentSize = bentCoil:GetBoundingBox()
local _, curSize = work:GetBoundingBox()
work:ScaleTo(bentSize.Y / curSize.Y)

local root = work:FindFirstChild("upper_shaft") :: BasePart
assert(root, 'missing reference part "upper_shaft"')
for _, part in work:GetChildren() do
	if part:IsA("BasePart") and part ~= root then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = root
	end
end

local gripMesh = work:FindFirstChild("grip") :: BasePart?
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
grip.CFrame = if gripMesh then gripMesh.CFrame else root.CFrame
grip.Parent = work
local gripWeld = Instance.new("WeldConstraint")
gripWeld.Part0 = root
gripWeld.Part1 = grip
gripWeld.Parent = grip

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
assert(final == expected + 1, `final part count {final}, expected {expected + 1} (parts + Grip)`)

work.PrimaryPart = grip
work:SetAttribute("TierName", NAME)
work:SetAttribute("HoldPart", bentCoil:GetAttribute("HoldPart"))
work:SetAttribute("HoldCFrame", CFrame.new(0.02, HOLD_Y, -1.1))

-- Only now touch the live ladder: highest first, so T8 -> T9 clears the name T8 for
-- T7, and so on down.
for n = OLD_TIERS, 1, -1 do
	local model = detectorFolder:FindFirstChild("T" .. n)
	assert(model, `T{n} missing mid-shift`)
	model.Name = "T" .. (n + 1)
end
work.Name = "T1"
work.Parent = detectorFolder

print(`[migration] Rust Bucket is Detector.T1 ({final} parts, x{string.format("%.2f", bentSize.Y / curSize.Y)}); T1-T8 moved up to T2-T9`)
