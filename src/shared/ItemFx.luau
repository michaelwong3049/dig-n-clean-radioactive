--!strict
--[[
	ItemFx.luau — the server side of item effects, which only labels the model.

	`ItemModels.create` calls `tag` on every clone it hands out, so every place an item
	is shown gets it for free: the wash stand, the off hand, an exhibit stand, a locker
	bay, the model yard. The client's ItemFxController picks tagged models up and does
	everything visible (Config/ItemFx's header says what, and why it waits for the
	crust to come off).

	WHY THE SERVER ONLY TAGS. Effects applied on the server would replicate every
	part write of every pulse to every player, would have to be undone again the
	moment a crust went on, and could not be culled by distance per player. A tag
	and one attribute cost nothing, and they survive a save, so a model yard built in
	Studio carries them into the published place.

	ATOMIC STREAMING. The place runs StreamingEnabled, and a half-streamed model is a
	light hung on a part that is not there yet. `Atomic` makes a tagged model arrive
	whole or not at all.

	The part-name helpers live here, not in the controller, because Spec uses the same
	matching rule to check every Config/ItemFx name against the live templates.
]]

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config.ItemFx)

local ItemFx = {}

ItemFx.TAG = "ItemFx"
ItemFx.ATTRIBUTE = "FxId"
-- Set on a Pristine-rolled item: the client lays its own shine over the whole model,
-- on top of (or instead of) any Config/ItemFx entry.
ItemFx.PRISTINE_ATTRIBUTE = "Pristine"
-- The same for the other two good qualities: a Fused nuke is bleached toward bone
-- white, an Irradiated one leaks a breathing green glow (Config/ItemFx).
ItemFx.FUSED_ATTRIBUTE = "Fused"
ItemFx.IRRADIATED_ATTRIBUTE = "Irradiated"

-- The qualities with a look of their own, and the attribute each one sets.
local QUALITY_ATTRIBUTES: { [string]: string } = {
	Pristine = ItemFx.PRISTINE_ATTRIBUTE,
	Fused = ItemFx.FUSED_ATTRIBUTE,
	Irradiated = ItemFx.IRRADIATED_ATTRIBUTE,
}

function ItemFx.get(itemId: string?): Config.ItemFxDef?
	return if itemId then Config.DEFS[itemId] or Config.CRATE_DEFS[itemId] else nil
end

--- "GlowSeam3_2" -> "GlowSeam", "Lens1" -> "Lens", "Shell" -> "Shell".
function ItemFx.baseName(name: string): string
	return (string.gsub(name, "[%d_]+$", ""))
end

--- A part answers to a Config name if it IS that name, or if that name is its
--- base name. So `GlowSeam` picks up every numbered seam and `GimbalRing3` only one.
--- A trailing `*` is a prefix match, for sets the base-name rule folds together:
--- `Glyph1*` is rotor 1's ten glyphs (`Glyph11`..`Glyph110`), not all thirty.
function ItemFx.matches(partName: string, wanted: string): boolean
	if string.sub(wanted, -1) == "*" then
		local prefix = string.sub(wanted, 1, -2)
		return string.sub(partName, 1, #prefix) == prefix
	end
	return partName == wanted or ItemFx.baseName(partName) == wanted
end

function ItemFx.partsNamed(root: Instance, names: { string }): { BasePart }
	local found: { BasePart } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			for _, wanted in names do
				if ItemFx.matches(descendant.Name, wanted) then
					table.insert(found, descendant)
					break
				end
			end
		end
	end
	return found
end

function ItemFx.firstPart(root: Instance, name: string): BasePart?
	local exact = root:FindFirstChild(name, true)
	if exact and exact:IsA("BasePart") then
		return exact
	end
	return ItemFx.partsNamed(root, { name })[1]
end

--- Every part name one Config entry refers to, for Spec's live-template check.
function ItemFx.referencedNames(def: Config.ItemFxDef): { string }
	local names: { string } = {}
	local function add(list: { string }?)
		for _, name in list or {} do
			table.insert(names, name)
		end
	end
	for _, finish in def.finish or {} do
		add(finish.parts)
	end
	if def.light then
		add({ def.light.part })
	end
	for _, particles in def.particles or {} do
		add({ particles.part })
	end
	for _, anim in def.anims or {} do
		add(anim.parts)
	end
	for _, spin in def.spins or {} do
		add(spin.parts)
		add({ spin.pivot })
		add(spin.axisParts)
	end
	if def.ping then
		add({ def.ping.part })
	end
	if def.seam then
		add({ def.seam.part })
	end
	if def.glint then
		add(def.glint.parts)
		add(def.glint.starParts)
	end
	for _, bolt in def.bolts or {} do
		add({ bolt.from, bolt.to })
	end
	return names
end

--- Label a freshly cloned item model for the client. A no-op for any item without an
--- entry in Config/ItemFx, so the nukes without effects are untouched -- unless the
--- dig rolled Pristine, Fused or Irradiated, which show whatever the item.
function ItemFx.tag(model: Model, itemId: string?, modifier: string?)
	local hasDef = itemId ~= nil and Config.DEFS[itemId] ~= nil
	local quality = if modifier then QUALITY_ATTRIBUTES[modifier] else nil
	if not hasDef and quality == nil then
		return
	end
	if hasDef then
		model:SetAttribute(ItemFx.ATTRIBUTE, itemId)
	end
	if quality then
		model:SetAttribute(quality, true)
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, ItemFx.TAG)
end

-- ── Part looks ────────────────────────────────────────────────────────────
-- Client-side paint, shared by ItemFxController (at activation) and
-- StandNukeController (before a full model replaces a stand's still copy). Each one
-- can run any number of times on the same model without compounding.

--- Config/ItemFx `finish` on the matched parts: material, colour, transparency,
--- reflectance, tint, ramp.
function ItemFx.applyFinish(model: Model, def: Config.ItemFxDef)
	for _, finish in def.finish or {} do
		for _, part in ItemFx.partsNamed(model, finish.parts) do
			if finish.material or finish.color then
				-- The SurfaceAppearance overrides both material and colour; it has to go
				-- for either to show.
				for _, child in part:GetChildren() do
					if child:IsA("SurfaceAppearance") then
						child:Destroy()
					end
				end
			end
			if finish.material then
				part.Material = (Enum.Material :: any)[finish.material]
			end
			if finish.color then
				part.Color = finish.color
			end
			if finish.transparency then
				part.Transparency = finish.transparency
			end
			if finish.reflectance then
				part.Reflectance = finish.reflectance
			end
			if finish.tint then
				-- Multiplies the painted colour map; the texture's detail stays.
				local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
				if appearance then
					appearance.Color = finish.tint
				else
					-- Baked parts (tools/studio-migrations/bake-nuke-texture-colours)
					-- carry the paint in Part.Color. The untinted colour is kept in an
					-- attribute so a second pass over the same model can't compound it.
					local base = part:GetAttribute("FxBaseColor")
					if typeof(base) ~= "Color3" then
						base = part.Color
						part:SetAttribute("FxBaseColor", base)
					end
					local tint = finish.tint
					part.Color = Color3.new(base.R * tint.R, base.G * tint.G, base.B * tint.B)
				end
			end
			local ramp = finish.ramp
			if ramp then
				local level = tonumber(string.match(part.Name, "%d+")) or 1
				local t = if ramp.levels > 1 then (level - 1) / (ramp.levels - 1) else 0
				part.Transparency = ramp.from + (ramp.to - ramp.from) * math.clamp(t, 0, 1)
			end
		end
	end
end

--- Every part of the model that can be seen, largest first, so [1] is the body
--- rather than some small fitting.
function ItemFx.visibleParts(model: Model): { BasePart }
	local visible: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 0.9 then
			table.insert(visible, descendant)
		end
	end
	table.sort(visible, function(a, b)
		return a.Size.Magnitude > b.Size.Magnitude
	end)
	return visible
end

--- Pull each painted part's colour `amount` of the way to `color` (the Fused bleach,
--- the Irradiated cast). Glowing (Neon) and see-through parts keep their own. The
--- colour before the first pull is kept in an attribute, so a second pass over the
--- same model starts from it again instead of compounding.
function ItemFx.pullColour(parts: { BasePart }, color: Color3, amount: number, reflectance: number?)
	for _, part in parts do
		if part.Material ~= Enum.Material.Neon and part.Transparency < 0.5 then
			local appearance = part:FindFirstChildOfClass("SurfaceAppearance")
			if appearance then
				-- A colour map can only be multiplied, never lightened; it has to go.
				-- Every imported map is one flat colour already baked into Part.Color
				-- (tools/studio-migrations/bake-nuke-texture-colours), so little is lost.
				appearance:Destroy()
			end
			local base = part:GetAttribute("FxQualityBaseColor")
			if typeof(base) ~= "Color3" then
				base = part.Color
				part:SetAttribute("FxQualityBaseColor", base)
			end
			part.Color = (base :: Color3):Lerp(color, amount)
			if reflectance then
				part.Reflectance = math.max(part.Reflectance, reflectance)
			end
		end
	end
end

--- Everything about a tagged model's resting look, read off its own attributes: its
--- Config/ItemFx finish, then the Fused or Irradiated colour pull. No lights,
--- particles or motion (those are ItemFxController's).
function ItemFx.applyLook(model: Model)
	local def = ItemFx.get(model:GetAttribute(ItemFx.ATTRIBUTE) :: string?)
	if def then
		ItemFx.applyFinish(model, def)
	end
	if model:GetAttribute(ItemFx.FUSED_ATTRIBUTE) == true then
		local fused = Config.FUSED
		ItemFx.pullColour(ItemFx.visibleParts(model), fused.color, fused.whiten, fused.reflectance)
	end
	if model:GetAttribute(ItemFx.IRRADIATED_ATTRIBUTE) == true then
		local hot = Config.IRRADIATED
		ItemFx.pullColour(ItemFx.visibleParts(model), hot.color, hot.tint)
	end
end

return ItemFx
