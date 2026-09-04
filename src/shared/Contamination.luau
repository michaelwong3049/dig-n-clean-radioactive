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

--- How dirty the thing still is, 0 (clean) to 1 (exactly as it came out of the
--- ground). Shared/ItemGrime paints with this, and it is the only reason the fraction
--- is expressed here rather than in the renderer: a display grade computed from the
--- same function that rolled the patches cannot drift away from them.
function Contamination.grimeLevel(patches: { number }, rarityName: string, modifier: string): number
	local remaining = #patches
	if remaining == 0 then
		return 0
	end

	-- An item carrying patches its own rarity/modifier would no longer produce (a save
	-- from before a retune) is simply "dirty" rather than a divide by zero.
	local initial = Contamination.initialCount(rarityName, modifier)
	if initial <= 0 then
		return 1
	end
	return math.clamp(remaining / initial, 0, 1)
end

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

--- Remove one patch this tool can actually clear, easiest first, and return its
--- hardness. nil means nothing left within reach — either done, or walled.
function Contamination.clearOne(patches: { number }, potency: number): number?
	local bestIndex: number? = nil
	local bestHardness: number? = nil

	for index, hardness in patches do
		if hardness <= potency and (bestHardness == nil or hardness < bestHardness) then
			bestIndex, bestHardness = index, hardness
		end
	end

	if bestIndex == nil then
		return nil
	end
	table.remove(patches, bestIndex)
	return bestHardness
end

--- Seconds of scrubbing one patch costs. Harder patches take longer even when
--- they are within reach, so a better cleaner is felt as speed as well as access.
function Contamination.secondsFor(hardness: number, scrubRate: number): number
	return (0.9 + hardness * 0.5) / math.max(scrubRate, 0.1)
end

return Contamination
