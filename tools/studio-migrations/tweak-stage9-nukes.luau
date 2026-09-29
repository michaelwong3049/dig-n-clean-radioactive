--[[
	Studio command-bar migration: drops the floating Steam puffs from the
	thermos_nuke template and the LightSpot floor splotches from lava_lamp_nuke
	in ReplicatedStorage.Assets.ImportedNukeTemplates, then scales each back up
	to NATURAL_SIZE (the spots and steam were setting the bounds). Idempotent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NATURAL_SIZE = 7.02

local DROPS = {
	thermos_nuke = "^Steam%d+$",
	lava_lamp_nuke = "^LightSpot%d+$",
}

local templates = ReplicatedStorage.Assets.ImportedNukeTemplates

for itemId, pattern in DROPS do
	local model = templates[itemId]
	local removed = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name:match(pattern) then
			d:Destroy()
			removed += 1
		end
	end

	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	model:ScaleTo(model:GetScale() * (NATURAL_SIZE / longest))

	local _, after = model:GetBoundingBox()
	print(`[tweak-stage9-nukes] {itemId}: removed {removed}; size {after}`)
end
