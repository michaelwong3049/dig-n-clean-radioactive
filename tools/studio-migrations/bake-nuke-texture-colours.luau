--[[
	Studio command-bar migration: bake every remaining imported-nuke texture into
	Part.Color, the same fix batch 13 got in import-nuke-models-batch13.luau.

	WHY. The imported nukes carry a SurfaceAppearance on every MeshPart, and the
	renderer never loads their ColorMaps (ContentProvider reports Failure for all
	176 of them, although AssetService reads each one fine). A part whose
	appearance fails draws unpredictably: grey, or not at all. In the model yard
	that showed up as whole Stage 1-3 nukes missing and others reduced to a few
	floating fins. The meshes themselves load; only the appearance is broken.

	WHAT. Every one of those textures is a single flat colour (checked: no
	sampled channel strays more than 6%), so each MeshPart takes its ColorMap's
	average colour, times the appearance's own Color, and the SurfaceAppearance
	is removed. Metalness/roughness maps go with it; Material = Metal already
	covers them. A `tint` finish in Config/ItemFx then multiplies Part.Color
	instead (see ItemFxController.applyFinish).

	WHERE. Assets.ImportedNukeTemplates (what every later clone copies) and the
	yard's already-placed models, so the yard needs no rebuild. Anything else
	cloned from a template at runtime picks the baked colours up on its own.

	KEPT IN GIT ON PURPOSE, same reason as every prior migration.

	Set DRY_RUN = true to report what would change without touching anything.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DRY_RUN = false

local averageCache: { [string]: Color3 } = {}

--- The mean colour of a (flat) texture. Sampled every 5th pixel.
local function averageColor(uri: string): Color3
	local cached = averageCache[uri]
	if cached then
		return cached
	end
	local image = AssetService:CreateEditableImageAsync(Content.fromUri(uri))
	local size = image.Size
	local pixels = image:ReadPixelsBuffer(Vector2.zero, size)
	local r, g, b, count = 0, 0, 0, 0
	for i = 0, size.X * size.Y - 1, 5 do
		r += buffer.readu8(pixels, i * 4)
		g += buffer.readu8(pixels, i * 4 + 1)
		b += buffer.readu8(pixels, i * 4 + 2)
		count += 1
	end
	image:Destroy()
	local color = Color3.fromRGB(r / count, g / count, b / count)
	averageCache[uri] = color
	return color
end

--- Moves each SurfaceAppearance's colour onto its part and drops it. Returns how
--- many appearances it baked.
local function bakeColors(root: Instance): number
	local baked = 0
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("MeshPart") then
			local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
			if appearance then
				baked += 1
				if not DRY_RUN then
					if appearance.ColorMap ~= "" then
						local base = averageColor(appearance.ColorMap)
						local tint = appearance.Color
						part.Color = Color3.new(base.R * tint.R, base.G * tint.G, base.B * tint.B)
					end
					appearance:Destroy()
				end
			end
		end
	end
	return baked
end

local roots = {}
for _, template in ipairs(ReplicatedStorage.Assets.ImportedNukeTemplates:GetChildren()) do
	table.insert(roots, template)
end
local camp = Workspace:FindFirstChild("BaseCamp")
local yard = camp and camp:FindFirstChild("ModelYard")
if yard then
	for _, child in ipairs(yard:GetChildren()) do
		if child:IsA("Model") and string.sub(child.Name, 1, 5) == "Item_" then
			table.insert(roots, child)
		end
	end
else
	warn("[bake] no BaseCamp.ModelYard; baking templates only")
end

local models, total = 0, 0
for _, root in ipairs(roots) do
	local baked = bakeColors(root)
	if baked > 0 then
		models += 1
		total += baked
	end
end

print(`[bake] {if DRY_RUN then "would bake" else "baked"} {total} appearance(s) on {models} model(s)`)
