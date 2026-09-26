--[[
	One-off Edit-mode migration (2026-09-26): gives the Twilight detectors already
	hanging on the Detector Shop rack (Aurora Rake..Prime Meridian, tiers 11-15)
	their moving parts (ToolFX.animate), without a full World.rebuild(). The Camps
	were built at CampSite v11, before detectors had MOTION; rigging them in place
	is exactly what v12 would build, so the stamp is bumped to match.

	Requires a fresh clone of Shared: Studio's require cache can serve the old
	ToolFX (see memory: studio-require-cache-stale-modules). Idempotent.
]]

local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local fresh = RS.Shared:Clone()
fresh.Name = "Shared_Fresh"
fresh.Parent = RS
for _, m in fresh:GetDescendants() do
	if m:IsA("ModuleScript") then
		m.Source = string.gsub(m.Source, "ReplicatedStorage%.Shared", "ReplicatedStorage.Shared_Fresh")
	end
end

-- A part only that tier's head has, so a T11 magnet is never mistaken for one.
local HEAD_TIER = {
	aurora_ribbon = 11,
	molten_core = 12,
	ley_core = 13,
	void_sphere = 14,
	meridian_core = 15,
}

local report = {}
local ok, err = pcall(function()
	local ToolFX = require(fresh.ToolFX)
	for _, model in workspace.Camps:GetDescendants() do
		if not model:IsA("Model") or not string.match(model.Name, "^T%d+$") then
			continue
		end
		for head, tier in HEAD_TIER do
			if model.Name == `T{tier}` and model:FindFirstChild(head, true) and model:FindFirstChild("upper_shaft", true) then
				local before = #CollectionService:GetTagged("ToolMotion")
				ToolFX.animate(model, "Detector", tier)
				table.insert(report, `{model:GetFullName()}: +{#CollectionService:GetTagged("ToolMotion") - before}`)
			end
		end
	end
	workspace.Camps:SetAttribute("BuilderVersion", 12)
end)
fresh:Destroy()
if not ok then
	error(err)
end
return table.concat(report, "\n")
