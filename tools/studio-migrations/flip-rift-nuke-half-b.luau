--[[
	flip-rift-nuke-half-b.luau — turns the Rift Nuke's B half upside down, so the two
	halves read as torn from different sides of the rift.

	Every `HalfB*` part is rotated 180 degrees about the line from RiftCore's centre
	out through HalfBShell's centre: the half stays where it is, only flipped.
	Runs on the template and on every placed copy (the yard stand). Idempotent via
	the `HalfBFlipped` attribute. Paste into the Studio command bar, then Save. A placed copy
	may need re-seating on its pedestal afterwards (its bounding box changes).
]]

local function flip(model: Model)
	if model:GetAttribute("HalfBFlipped") then
		return false
	end
	local core = model:FindFirstChild("RiftCore") :: BasePart
	local shell = model:FindFirstChild("HalfBShell") :: BasePart
	local axis = (shell.Position - core.Position).Unit
	local about = CFrame.new(shell.Position) * CFrame.fromAxisAngle(axis, math.pi) * CFrame.new(-shell.Position)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name:sub(1, 5) == "HalfB" then
			part.CFrame = about * part.CFrame
		end
	end
	model:SetAttribute("HalfBFlipped", true)
	return true
end

-- The flip mirrors B's lean, so it ends up ~30 degrees off. Stand it up exactly
-- opposite A (thruster-to-nose antiparallel), turning about HalfBShell.
local function straighten(model: Model)
	if model:GetAttribute("HalfBStraightened") then
		return
	end
	local function dir(a: string, b: string): Vector3
		return ((model:FindFirstChild(b) :: BasePart).Position - (model:FindFirstChild(a) :: BasePart).Position).Unit
	end
	local want = -dir("HalfAThruster", "HalfANoseSpike")
	local cur = dir("HalfBThruster", "HalfBNoseSpike")
	local axis = cur:Cross(want)
	if axis.Magnitude > 1e-4 then
		local c = (model:FindFirstChild("HalfBShell") :: BasePart).Position
		local about = CFrame.new(c) * CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(cur:Dot(want), -1, 1))) * CFrame.new(-c)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name:sub(1, 5) == "HalfB" then
				part.CFrame = about * part.CFrame
			end
		end
	end
	model:SetAttribute("HalfBStraightened", true)
end

local count = 0
for _, d in game:GetDescendants() do
	if d:IsA("Model") and d:FindFirstChild("HalfBShell") and d:FindFirstChild("RiftCore") then
		if flip(d) then
			count += 1
			print("flipped", d:GetFullName())
		end
		straighten(d)
	end
end
print(`flip-rift-nuke-half-b: {count} model(s)`)
