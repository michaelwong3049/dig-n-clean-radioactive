--[[
	Studio command-bar migration: reshapes two batch 16 templates in
	ReplicatedStorage.Assets.ImportedNukeTemplates. Idempotent.

	- ashen_nuke: drops the AshHeap pile under the fins.
	- inferno_nuke: shrinks the ground discs (ScorchedPlain, Shockwave*) so the
	  base no longer sets the model's longest edge, then scales the whole model
	  back up to NATURAL_SIZE -- the nuke itself ends up bigger.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NATURAL_SIZE = 7.02
-- Target width of each Inferno ground disc, in the template's current studs.
local INFERNO_DISCS = { ScorchedPlain = 5.2, Shockwave2 = 4.9, Shockwave = 4.5 }

local templates = ReplicatedStorage.Assets.ImportedNukeTemplates

local ashen = templates.ashen_nuke
local removed = 0
for _, d in ashen:GetDescendants() do
	if d:IsA("BasePart") and d.Name:match("^AshHeap%d+$") then
		d:Destroy()
		removed += 1
	end
end

local inferno = templates.inferno_nuke
if not inferno:GetAttribute("BaseShrunk") then
	for name, width in INFERNO_DISCS do
		local part = inferno:FindFirstChild(name, true) :: BasePart
		part.Size = Vector3.new(width, part.Size.Y, width)
	end
	inferno:SetAttribute("BaseShrunk", true)
end

local function renormalise(model: Model)
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	model:ScaleTo(model:GetScale() * (NATURAL_SIZE / longest))
end
-- The Big One (unlabeled_cylinder): GroundPlate and its cracks pulled in 15%
-- toward the centre, so the nuke above them scales up a touch.
local bigOne = templates.unlabeled_cylinder
if not bigOne:GetAttribute("BaseShrunk") then
	local BIG_ONE_BASE = 0.85
	local centre = bigOne:GetBoundingBox()
	for _, p in bigOne:GetDescendants() do
		if p:IsA("BasePart") and (p.Name == "GroundPlate" or p.Name:match("^GroundCrack%d+$")) then
			local rel = centre:ToObjectSpace(p.CFrame)
			local pos = rel.Position
			p.Size = Vector3.new(p.Size.X * BIG_ONE_BASE, p.Size.Y, p.Size.Z * BIG_ONE_BASE)
			p.CFrame = centre * CFrame.new(pos.X * BIG_ONE_BASE, pos.Y, pos.Z * BIG_ONE_BASE) * (rel - pos)
		end
	end
	bigOne:SetAttribute("BaseShrunk", true)
end

renormalise(ashen)
renormalise(inferno)
renormalise(bigOne)

local _, infernoSize = inferno:GetBoundingBox()
print(`[tweak-stage7-nukes] ashen: removed {removed} heaps; inferno scale {inferno:GetScale()} size {infernoSize}`)
