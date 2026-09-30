--[[
	Studio command-bar migration: drops the floating splash blobs (Splash1-10)
	hovering round the sludge_nuke template in
	ReplicatedStorage.Assets.ImportedNukeTemplates, then scales the model back up to
	NATURAL_SIZE so the body alone fills the display size. Idempotent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NATURAL_SIZE = 7.02

local sludge = ReplicatedStorage.Assets.ImportedNukeTemplates.sludge_nuke

local removed = 0
for _, d in sludge:GetDescendants() do
	if d:IsA("BasePart") and d.Name:match("^Splash%d+$") then
		d:Destroy()
		removed += 1
	end
end

local _, size = sludge:GetBoundingBox()
local longest = math.max(size.X, size.Y, size.Z)
sludge:ScaleTo(sludge:GetScale() * (NATURAL_SIZE / longest))

local _, after = sludge:GetBoundingBox()
print(`[tweak-stage10-sludge] removed {removed} splash blobs; scale {sludge:GetScale()} size {after}`)
