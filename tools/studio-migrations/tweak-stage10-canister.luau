--[[
	Studio command-bar migration: drops the ooze puddle (Puddle1-3) and the bubbles
	sitting in it (Bubble1-3) from beside the canister_nuke template in
	ReplicatedStorage.Assets.ImportedNukeTemplates, then scales the model back up to
	NATURAL_SIZE so the drum alone fills the display size. Idempotent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NATURAL_SIZE = 7.02

local canister = ReplicatedStorage.Assets.ImportedNukeTemplates.canister_nuke

local removed = 0
for _, d in canister:GetDescendants() do
	if d:IsA("BasePart") and (d.Name:match("^Puddle%d+$") or d.Name:match("^Bubble%d+$")) then
		d:Destroy()
		removed += 1
	end
end

local _, size = canister:GetBoundingBox()
local longest = math.max(size.X, size.Y, size.Z)
canister:ScaleTo(canister:GetScale() * (NATURAL_SIZE / longest))

local _, after = canister:GetBoundingBox()
print(`[tweak-stage10-canister] removed {removed} puddle/bubble parts; scale {canister:GetScale()} size {after}`)
