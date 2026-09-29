--[[
	Studio command-bar migration: drops the InkCloud lumps ("rocks") from under the
	kraken_nuke template in ReplicatedStorage.Assets.ImportedNukeTemplates, then
	scales the model back up to NATURAL_SIZE -- without the pile setting its height,
	the kraken itself ends up bigger. Idempotent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NATURAL_SIZE = 7.02

local kraken = ReplicatedStorage.Assets.ImportedNukeTemplates.kraken_nuke

local removed = 0
for _, d in kraken:GetDescendants() do
	if d:IsA("BasePart") and d.Name:match("^InkCloud%d+$") then
		d:Destroy()
		removed += 1
	end
end

local _, size = kraken:GetBoundingBox()
local longest = math.max(size.X, size.Y, size.Z)
kraken:ScaleTo(kraken:GetScale() * (NATURAL_SIZE / longest))

local _, after = kraken:GetBoundingBox()
print(`[tweak-stage8-kraken] removed {removed} ink clouds; scale {kraken:GetScale()} size {after}`)
