--[[
	One-time Studio command-bar migration: Magma Hollow's Stage 12 magnet goes in as the
	Magnet track's tier 12 (Config/Gear.Magnet row 12, `camp = "magma"`), after the Omega.

	  T12 Magma Magnet   <- Workspace.AuxScene.tier_11_magma (the pack's numbering is one
	                        below ours, like the Twilight pack's)

	THE RECIPE IS import-twilight-magnets.luau's, unchanged (read its header for the
	template contract, the -90 degree Grip turn and the one shared TARGET_LENGTH): the
	import stands upright like that pack, bend at the bottom and poles along +Y. Run in
	EDIT mode, then rebuild Camps and Save + Publish.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TIERS = {
	{ tier = 12, source = "tier_11_magma", name = "Magma Magnet" },
}

local TARGET_LENGTH = 8 -- studs along the poles (Grip +Z), every rung the same

local GRIP_SIZE = 0.56 -- T2-T6's Grip

local magnetFolder = ReplicatedStorage.Assets.Tools.Magnet
assert(magnetFolder:FindFirstChild("T12") == nil, "T12 already exists: this migration has already run")

local singularity = magnetFolder:FindFirstChild("T6")
assert(singularity and singularity:GetAttribute("TierName") == "Singularity Coil", "T6 is not the Singularity Coil; the ladder is not where this expects it")
local holdPart = singularity:GetAttribute("HoldPart")
local holdCFrame = singularity:GetAttribute("HoldCFrame")
assert(typeof(holdCFrame) == "CFrame", "T6 has no HoldCFrame to share")

local function partsOf(model: Instance): { BasePart }
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function findAuxSource(name: string): Model?
	for _, aux in workspace:GetChildren() do
		if aux.Name == "AuxScene" then
			local m = aux:FindFirstChild(name)
			if m and m:IsA("Model") then
				return m
			end
		end
	end
	return nil
end

-- Everything is built and checked on clones first; the live folder is touched last.
local built: { { tier: number, model: Model, parts: number, scale: number } } = {}

for _, spec in TIERS do
	local source = findAuxSource(spec.source)
	assert(source, `no {spec.source} under a Workspace.AuxScene to import`)
	local expected = #partsOf(source)

	local clone = source:Clone()

	-- Flatten: every mesh straight under one sub-Model named after the tier; the
	-- import's wrapper models (magnet_x, groups, *_Node) go.
	local work = Instance.new("Model")
	work.Name = "_work_T" .. spec.tier
	local body = Instance.new("Model")
	body.Name = spec.name
	body.Parent = work
	for _, part in partsOf(clone) do
		part.Parent = body
	end
	clone:Destroy()
	assert(#body:GetChildren() == expected, `{spec.name}: flatten kept {#body:GetChildren()} parts, expected {expected}`)

	local bend: BasePart? = nil
	local outerPole: BasePart? = nil
	for _, part in body:GetChildren() do
		if part.Name == "bend" then
			assert(bend == nil, `{spec.name}: more than one part named "bend"`)
			bend = part :: BasePart
		elseif part.Name == "pole_left" then
			outerPole = part :: BasePart
		end
	end
	assert(bend and outerPole, `{spec.name}: missing "bend" or "pole_left"`)
	body.PrimaryPart = bend

	-- The poles have to stand straight up from the bend for the -90 degree turn below to
	-- lay them along the Grip's +Z.
	local rise = outerPole.Position - bend.Position
	assert(rise.Y > 0.5 and math.abs(rise.Z) < 0.05, `{spec.name}: poles do not stand up from the bend (rise {rise})`)

	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(GRIP_SIZE, GRIP_SIZE, GRIP_SIZE)
	grip.Transparency = 1
	grip.Material = Enum.Material.Plastic
	grip.CFrame = CFrame.new(bend.Position) * CFrame.Angles(-math.pi / 2, 0, 0)
	grip.Parent = work
	work.PrimaryPart = grip

	-- Grip world-aligned, like every other template (Shops and ToolService only ever
	-- read it relatively, but a template that sits identity is one less thing to doubt).
	work:PivotTo(CFrame.new(grip.Position))

	-- Scale about the Grip to the one shared length. The Grip is world-aligned now, so
	-- the bounding box's Z is the length along the poles.
	local _, boxSize = work:GetBoundingBox()
	work:ScaleTo(work:GetScale() * TARGET_LENGTH / boxSize.Z)

	local polesAt = grip.CFrame:PointToObjectSpace(outerPole.Position)
	assert(polesAt.Z > 1 and math.abs(polesAt.Y) < 0.05, `{spec.name}: poles are not along the Grip's +Z (at {polesAt})`)

	for _, part in partsOf(work) do
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		if part ~= grip then
			part.CanQuery = true
			part.CanTouch = true
		else
			part.CanQuery = false
			part.CanTouch = true
		end
		if part ~= bend then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bend
			weld.Part1 = part
			weld.Parent = if part == grip then grip else bend
		end
	end

	local final = #partsOf(work)
	assert(final == expected + 1, `{spec.name}: final part count {final}, expected {expected + 1} (parts + Grip)`)

	work:SetAttribute("TierName", spec.name)
	work:SetAttribute("HoldPart", holdPart)
	work:SetAttribute("HoldCFrame", holdCFrame)

	table.insert(built, { tier = spec.tier, model = work, parts = final, scale = work:GetScale() })
end

-- Only now touch the live ladder.
for _, b in built do
	b.model.Name = "T" .. b.tier
	b.model.Parent = magnetFolder
	print(`[migration] Magnet.T{b.tier} {b.model:GetAttribute("TierName")}: {b.parts} parts, {string.format("%.2f", b.scale)}x`)
end
