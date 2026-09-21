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

function ItemFx.get(itemId: string?): Config.ItemFxDef?
	return if itemId then Config.DEFS[itemId] else nil
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
	return names
end

--- Label a freshly cloned item model for the client. A no-op for any item without an
--- entry in Config/ItemFx, so the nukes without effects are untouched.
function ItemFx.tag(model: Model, itemId: string?)
	if itemId == nil or Config.DEFS[itemId] == nil then
		return
	end
	model:SetAttribute(ItemFx.ATTRIBUTE, itemId)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, ItemFx.TAG)
end

return ItemFx
