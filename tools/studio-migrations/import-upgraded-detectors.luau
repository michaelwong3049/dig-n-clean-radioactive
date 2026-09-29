--[[
	One-time Studio command-bar migration (2026-09-29): swaps all fifteen Detector
	templates (`Assets/Tools/Detector/T1`-`T15`) for the user's upgraded imports.

	KEPT IN GIT ON PURPOSE, like import-detector-models.luau and
	import-twilight-detectors.luau: Assets is not Rojo-synced, so this script is the
	only record of what was done to the place file. Run it in EDIT mode, then Save and
	Publish.

	The upgrades are the same heads on a new body: a pistol grip + trigger, forearm
	cuff, battery pack, speaker, skids and an under-sensor. Every part the old model had
	is still there by the same name except `grip`/`armrest` (replaced by `pistol_grip`/
	`cuff_*`) and Deep Core Array's `focuser`. So ToolFX's SPECS and DETECTOR_MOTION,
	which find parts by name, keep working unchanged.

	SIZE: each import is scaled so its `upper_shaft` matches the OLD template's. That
	keeps every head exactly the size the old one was, so the particle sizes and motion
	amplitudes tuned against the old heads still fit.

	HOLD: the new Grip sits on `pistol_grip` (was `grip`). HoldCFrame keeps identity
	rotation and X/Z; Y is solved so the model's lowest point lands where the old
	template's lowest point did (the old values were floor-tuned, see
	import-detector-models.luau).

	The old templates go to `Detector._Legacy` as `T<n>_pre_upgrade`; the AuxScene
	sources are deleted once every tier has been swapped.

	RACKS: the Base Camp (T2-T9) and Twilight (T10-T15) Detector Shop racks were
	swapped in place rather than rebuilt: each new clone takes the old one's pose, is
	fitted with hangTierModel's rules (4.3 tall, 3.0 wide, 3.6 deep, 1.85x cap in the
	stall's frame), gets ToolFX.apply at 1.5x particle scale, and sits on the old one's
	base centre. A later Shops/CampSite rebuild produces the same result.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage.Assets.Tools.Detector
local legacy = folder:FindFirstChild("_Legacy") or Instance.new("Folder")
legacy.Name = "_Legacy"
legacy.Parent = folder

local function parts(model: Instance): { BasePart }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function named(model: Instance, name: string): BasePart?
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == name then
			return d
		end
	end
	return nil
end

--- Lowest point of the model, relative to its PrimaryPart, along world Y.
local function lowRel(model: Model): number
	local box, size = model:GetBoundingBox()
	return (box.Position.Y - size.Y / 2) - (model.PrimaryPart :: BasePart).Position.Y
end

local built = {}
for tier = 1, 15 do
	local old = folder:FindFirstChild("T" .. tier) :: Model
	assert(old, `no T{tier}`)
	local name = old:GetAttribute("TierName") :: string
	local sourceName = string.gsub(name, " ", "_")
	local source = workspace:FindFirstChild(sourceName, true)
	assert(source and source:IsA("Model") and source.Parent and source.Parent.Name == "AuxScene", `no AuxScene import for {name}`)

	local expected = #parts(source)
	local work = source:Clone()
	work.Name = "_work_T" .. tier
	work.Parent = workspace

	-- Flatten the `<part>_Node` wrappers.
	for _, node in work:GetChildren() do
		if node:IsA("Model") then
			for _, p in parts(node) do
				p.Parent = work
			end
			node:Destroy()
		end
	end
	assert(#parts(work) == expected, `{name}: flatten lost parts`)

	local shaft = named(work, "upper_shaft") :: BasePart
	local oldShaft = named(old, "upper_shaft") :: BasePart
	assert(shaft and oldShaft, `{name}: missing upper_shaft`)
	work:ScaleTo(oldShaft.Size.Y / shaft.Size.Y)

	for _, p in parts(work) do
		if p ~= shaft then
			local w = Instance.new("WeldConstraint")
			w.Part0 = shaft
			w.Part1 = p
			w.Parent = shaft
		end
	end

	local handle = named(work, "pistol_grip") :: BasePart
	assert(handle, `{name}: missing pistol_grip`)
	local grip = Instance.new("Part")
	grip.Name = "Grip"
	grip.Size = Vector3.new(0.14, 0.14, 0.14)
	grip.Transparency = 1
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = true
	grip.Massless = true
	grip.CFrame = CFrame.new(handle.Position) * shaft.CFrame.Rotation
	grip.Parent = work
	local gw = Instance.new("WeldConstraint")
	gw.Part0 = shaft
	gw.Part1 = grip
	gw.Parent = grip

	-- A held prop is never collidable (a buried part lifts the whole character).
	for _, p in parts(work) do
		p.Anchored = false
		if p ~= grip then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	work.PrimaryPart = grip
	assert(grip.CFrame.UpVector:Dot(Vector3.yAxis) > 0.999, `{name}: not upright`)

	for key, value in old:GetAttributes() do
		work:SetAttribute(key, value)
	end
	local hold = old:GetAttribute("HoldCFrame") :: CFrame
	local holdY = math.round((hold.Y + lowRel(old) - lowRel(work)) * 1000) / 1000
	work:SetAttribute("HoldCFrame", CFrame.new(hold.X, holdY, hold.Z))

	table.insert(built, { tier = tier, old = old, new = work, source = source, holdY = holdY })
end

-- Only now touch the live folder.
local report = {}
for _, b in built do
	b.old.Name = `T{b.tier}_pre_upgrade`
	b.old.Parent = legacy
	b.new.Name = "T" .. b.tier
	b.new.Parent = folder
	table.insert(report, `T{b.tier} {b.new:GetAttribute("TierName")}: {#parts(b.new)} parts, holdY {b.holdY}`)
end
for _, b in built do
	local aux = b.source.Parent
	b.source:Destroy()
	if aux and aux.Name == "AuxScene" and #aux:GetChildren() == 0 then
		aux:Destroy()
	end
end
return table.concat(report, "\n")
