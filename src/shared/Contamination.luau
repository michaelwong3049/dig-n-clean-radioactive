--!strict
--[[
	Contamination.lua — PURE MATH for the second gate (PLAN §2 step 4).

	Shared for the same reason as Radiation and Decay: the patches the player scrubs on
	screen and the patches the server says are gone must come out of one function.

	THE GATE: every patch has a hardness. Your hose has a potency. A patch harder
	than your potency will NOT clear, ever, with that hose. So you can find something
	with a good detector and still be unable to sell it — two different upgrade tracks
	gating two different halves of the same item.

	Every item gets at least one patch AT its rarity's hardness, which is what makes
	rarity the gate rather than luck. The rest are rolled softer, so a cleaner that is
	one tier short still makes visible progress before hitting the wall — and PLAN §2
	says partial progress still pays XP. A failed clean is never a wasted one.
]]

local Config = script.Parent.Config
local Rarity = require(Config.Rarity)

local Contamination = {}

local function patchCount(order: number): number
	return 2 + math.floor(order / 2)
end

--- HOW MANY patches a fresh roll puts on this item. Deterministic -- only the
--- HARDNESSES are rolled -- which is the whole reason this is worth pulling out of
--- rollPatches: it lets anything downstream ask "how dirty was this to begin with"
--- without a second number being stored on every carried item and migrated into every
--- existing save. Zero means the pair never needed cleaning at all.
function Contamination.initialCount(rarityName: string, modifier: string): number
	local def = Rarity.get(rarityName)
	local mod = Rarity.MODIFIERS[modifier] or Rarity.MODIFIERS.None

	-- Prewar Sealed is still in its packaging: it sells as-is (PLAN §7).
	if not mod.needsCleaning then
		return 0
	end

	local count = patchCount(def.order)
	if modifier == "Fused" then
		count += 1 -- melted into something else; one extra pass
	elseif modifier == "Pristine" then
		count -= 1 -- no rust, cleans faster
	end
	return math.max(1, count)
end

--- Roll the contamination for a freshly unearthed item.
function Contamination.rollPatches(rarityName: string, modifier: string): { number }
	local count = Contamination.initialCount(rarityName, modifier)
	if count == 0 then
		return {}
	end

	-- One patch always sits at the item's full hardness. That is the gate.
	local def = Rarity.get(rarityName)
	local patches = { def.hardness }
	for _ = 2, count do
		table.insert(patches, math.random(1, def.hardness))
	end
	return patches
end

-- `grimeLevel` LIVED HERE AND IS GONE. It graded an item's dirt as one fraction --
-- patches left over patches rolled -- for Shared/ItemGrime to tint the whole model
-- with. Contamination is a crust of real chunks now (Shared/ItemCrust), one per patch,
-- and a chunk is either on the item or off it: there is no aggregate for anything to
-- render, and `#patches` is the only count a caller needs. `initialCount` stays,
-- because rollPatches is what it was really for.

function Contamination.isClean(patches: { number }): boolean
	return #patches == 0
end

--- The hardest patch this potency cannot touch, or nil if the hose can finish.
--- This is what the Quarantine Locker labels itself with.
function Contamination.blockedBy(patches: { number }, potency: number): number?
	local worst: number? = nil
	for _, hardness in patches do
		if hardness > potency and (worst == nil or hardness > worst) then
			worst = hardness
		end
	end
	return worst
end

--- Remove ONE NAMED PATCH, if this tool can actually shift it. Returns its hardness
--- and the array index it came out of; nil means the index named nothing, or named
--- something out of reach.
---
--- IT USED TO BE `clearOne`, WHICH PICKED THE EASIEST PATCH ITSELF, and that choice
--- was invisible for as long as the caller was a hold-to-clean bar with no notion of
--- WHERE on the item it was working. The wash bay has one: you point a hose at a
--- specific dirty area. Letting this function pick meant finishing a timer on the
--- crusted patch you had deliberately worked for eight seconds and watching a
--- different, easier patch on the far side of the object pop instead. The caller
--- knows which patch the water is on, so the caller names it.
---
--- The index is handed back so a caller tracking a parallel array (WashService's
--- per-session zone ids, keeping a real part in sync with a patch that has no
--- identity of its own) can remove at the same spot and stay in lockstep with the
--- shift `table.remove` causes.
function Contamination.clearAt(patches: { number }, index: number, potency: number): (number?, number?)
	local hardness = patches[index]
	if hardness == nil or hardness > potency then
		return nil, nil
	end
	table.remove(patches, index)
	return hardness, index
end

--- Is there anything left here this potency can shift? The wall check, split out from
--- the old `clearOne` returning nil: "nothing reachable" is now a question asked on
--- its own rather than a side effect of trying to clear something.
function Contamination.anyReachable(patches: { number }, potency: number): boolean
	for _, hardness in patches do
		if hardness <= potency then
			return true
		end
	end
	return false
end

--- Seconds of scrubbing one patch costs. Harder patches take longer even when
--- they are within reach, so a better cleaner is felt as speed as well as access.
function Contamination.secondsFor(hardness: number, scrubRate: number): number
	return (0.9 + hardness * 0.5) / math.max(scrubRate, 0.1)
end

return Contamination
