--!strict
--[[
	Weight.luau — every item has a mass, and mass has five physical consequences.

	Config/ RULE (Tuning.luau's header): data only, no game logic, no requires of
	anything outside Config/. This file requires nothing; Config/Items requires it.

	An item's `weight` is in KILOGRAMS and authored per entry in Config/Items. It is
	INTRINSIC — a Dud Nuke is always ~5 kg, a buried nuke always ~470 — not a
	per-dig roll. Rarity and weight are ORTHOGONAL: a Diamond Chain is light and
	precious, a Steel Rod is heavy and worthless. Five things read the mass:

	  sizeScale   the hauled / displayed model is :ScaleTo'd by this
	  auraScale   the buried signal's glowing cracks run this much longer and wider
	  pullFactor  the mash takes this much longer (depth * this), never a hard gate
	  valueMult   sale value and $/sec are multiplied by this, layered like a modifier
	  rollBias    the dig-roll weight is multiplied by this (<= 1): a U-shape that
	              leaves the feather end a touch rarer and buries the heavy end deep

	`shownOdds` turns an item's authored `odds` headline into the number a sharp
	detector ping / the Index actually PRINT: `odds / rollBias`, so the display and
	the roll move together off ONE function and cannot drift (the same rule
	Config/Items' "The dig roll" and Config/Liquids.oddsAt follow).

	All the anchor constants and curve endpoints are top-level so Shared/Util/Spec
	can pin them.
]]

local Weight = {}

-- The catalogue's real span. MIN is the floor no nuke may show under (a Dud Nuke);
-- MAX is the Containment Cylinder. `norm` is LOG between them because mass is
-- perceived multiplicatively — 10 vs 100 kg reads like 100 vs 1000.
--
-- SIZE CLASSES (an authoring guide, not a mechanic — the curves below do the work):
--   Small 5-15 kg, Normal 16-50, Large 51-250, Extra Large 250+.
-- Every authored `weight` was rebased from the old 0.05..250 span onto 5..500 along
-- the same log curve (kg = 5 * 100^oldNorm), so every curve below reads each item at
-- the same `norm` as before and balance is unchanged; only the printed kg moved.
Weight.MIN = 5
Weight.MAX = 500

-- `rollBias` knobs. The curve is `min(light, heavy)` over `norm`:
--   * feather items (norm <= LIGHT_END) are lifted from LIGHT_FLOOR back up to 1
--   * heavy items (norm >= HEAVY_START) sink from 1 down to HEAVY_FLOOR
--   * the broad middle sits at exactly 1 — weight there does nothing to the roll
-- Kept gentle at the light end so it nudges "small isn't overly common" without
-- swinging a stage's rarity mix (Spec §7); the heavy end is where the real
-- suppression lives. HEAVY_START pulled in 0.60 -> 0.52 (penalty now bites from
-- ~4kg, was ~8kg) and HEAVY_FLOOR down 0.35 -> 0.24, on request -- the first pass
-- read too gentle.
Weight.LIGHT_FLOOR = 0.85
Weight.LIGHT_END = 0.12
Weight.HEAVY_START = 0.52
Weight.HEAVY_FLOOR = 0.24

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

--- 0..1 log position of a mass between MIN and MAX. Clamped, so an out-of-range
--- authored weight saturates rather than throwing.
function Weight.norm(kg: number): number
	return clamp01(math.log(math.max(kg, Weight.MIN) / Weight.MIN) / math.log(Weight.MAX / Weight.MIN))
end

-- Heavy-end endpoints raised across the board on request (the first pass read too
-- gentle): sizeScale 2.40 -> 3.00, auraScale 1.90 -> 2.40, pullFactor 2.20 -> 2.80,
-- valueMult 1.60 -> 1.75. The light end and the linear-in-`norm` shape are unchanged.

--- Model :ScaleTo multiplier — a feather is a bit over half size, the heaviest
--- things ~3x. Multiplies the authored model / placeholder size.
function Weight.sizeScale(kg: number): number
	return lerp(0.55, 3.00, Weight.norm(kg))
end

--- How much bigger the buried signal's aura reads (the hot spot, and the cracks'
--- length and width). NOT the pickup radius — that stays Tuning.DIG_RADIUS. Purely
--- "big thing, big glow".
function Weight.auraScale(kg: number): number
	return lerp(0.75, 2.40, Weight.norm(kg))
end

--- Multiplies the pull's `required` seconds (DigService: PULL_SECONDS_PER_STUD *
--- depth * this). Only ever lengthens the mash; it does not touch clicks-to-hold
--- (that is weight-independent), so the mobile promise in Config/Gear is intact.
function Weight.pullFactor(kg: number): number
	return lerp(0.85, 2.80, Weight.norm(kg))
end

--- Multiplies sale value and pedestal $/sec. Rides ON TOP of baseValue exactly
--- like Rarity.MODIFIERS' valueMult (and stays under Pristine's 2.0), so the
--- "baseValue sits in its rarity band" rule still describes the AUTHORED number.
function Weight.valueMult(kg: number): number
	return lerp(0.90, 1.75, Weight.norm(kg))
end

--- Dig-roll weight multiplier, <= 1 always. U-shaped — see the knobs above.
function Weight.rollBias(kg: number): number
	local n = Weight.norm(kg)
	local light = lerp(Weight.LIGHT_FLOOR, 1, clamp01(n / Weight.LIGHT_END))
	local heavy = lerp(1, Weight.HEAVY_FLOOR, clamp01((n - Weight.HEAVY_START) / (1 - Weight.HEAVY_START)))
	return math.min(light, heavy)
end

--- The kg a surface PRINTS for one specific find: the item's authored weight times
--- its per-dig Payload roll, floored at MIN so a small item on a low roll still
--- reads as the 5 kg minimum rather than dipping under it.
function Weight.shownKg(kg: number, roll: number): number
	return math.max(kg * roll, Weight.MIN)
end

--- The "1 in N" a surface should PRINT for an item: its authored headline inflated
--- by whatever the roll bias took away. The feather and heavy ends read rarer; the
--- middle is unchanged. Pair with Items.oddsText for formatting.
function Weight.shownOdds(odds: number, kg: number): number
	return odds / Weight.rollBias(kg)
end

return Weight
