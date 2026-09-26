--[[
	One-off Edit-mode migration (2026-09-26): gives the magnets already hanging on
	the shop racks the moving parts #334 added (ToolFX.animate), without a full
	World.rebuild(). Base Camp's Shops (Singularity Coil) and the Camps' Twilight
	Magnet Shop (Lattice..Omega) were built at Shops v47 / CampSite v10, before
	MOTION existed; rigging their magnets in place is exactly what v48 / v11 would
	build, so the stamps are bumped to match.

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

local CORE_TIER = {
	singularity_core = 6,
	lattice_core = 7,
	sun_core = 8,
	void_core = 9,
	nebula_core = 10,
	omega_core = 11,
}

local report = {}
local ok, err = pcall(function()
	local ToolFX = require(fresh.ToolFX)
	for root, version in { [workspace.Shops] = 48, [workspace.Camps] = 11 } do
		for _, model in root:GetDescendants() do
			if not model:IsA("Model") or not string.match(model.Name, "^T%d+$") then
				continue
			end
			for core, tier in CORE_TIER do
				if model.Name == `T{tier}` and model:FindFirstChild(core, true) and model:FindFirstChild("bend", true) then
					local before = #CollectionService:GetTagged("ToolMotion")
					ToolFX.animate(model, "Magnet", tier)
					table.insert(report, `{model:GetFullName()}: +{#CollectionService:GetTagged("ToolMotion") - before}`)
				end
			end
		end
		root:SetAttribute("BuilderVersion", version)
	end
end)
fresh:Destroy()
if not ok then
	error(err)
end
return table.concat(report, "\n")
