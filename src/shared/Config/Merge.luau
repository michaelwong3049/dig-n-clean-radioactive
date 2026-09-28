--!strict
--[[
	Merge.luau — the Merge Reactor at Toxic Twilight: three copies of one nuke go in,
	one comes out, maybe with MERGE STARS on it.

	Config/ RULE (Tuning.luau's header): data only, no requires of anything outside
	Config/. The helpers below are pure maths over these numbers, the same way
	Rarity.stars and Payload.fromRoll are, so the panel's odds bar and the server's
	roll are one function and cannot disagree.

	A MERGE STAR IS NOT A RATING STAR. The rating (Rarity.stars) is the tier, nudged by
	quality and size, and stops at 8. A merge star is a stored upgrade on ONE copy --
	`item.merge`, 0..MAX_LEVEL, carried through the bag, the locker and the stands --
	drawn after the rating in its own colour, so an Anomaly already at 8 can still be
	merged up. Each one multiplies what the copy sells for AND what it pays on a stand
	by VALUE_STEP (EconomyService.valueOf, CarryService.describe,
	ExhibitService.entryYieldPerSecond all call `valueMult`).

	THE ROLL (picked by the user, 2026-09-28: "gamble, keep best"):
	  * The target is one level above the HIGHEST level among the three inputs, so a +2
	    fed two plain copies tries for +3. Feeders never have to match levels.
	  * SUCCESS[target] is the chance of +1, plus PITY_STEP for every failed merge of this
	    nuke since its last success (`data.mergePity[itemId]`), capped at SUCCESS_MAX.
	  * CRIT is the share of rolls that land +2 instead, grown by the player's luck
	    multiplier (the Luck button and 2x luck), capped at CRIT_MAX. It is part of the
	    success chance, never on top of it, and it only exists while +2 still fits
	    under MAX_LEVEL.
	  * A FAIL keeps the best of the three untouched and uses up the other two.
	  * The fee is paid either way.

	WHAT COMES OUT ON A SUCCESS is not just the best copy bumped: it wears the best
	quality modifier among the three (MODIFIER_RANK) and the biggest payload roll
	among the three (its uid, since Config/Payload derives size from uid). Merging a
	Pristine with an OVERSIZED copy is how you get a Pristine OVERSIZED.
]]

local Items = require(script.Parent.Items)
local Weight = require(script.Parent.Weight)

local Merge = {}

--- How many copies go in.
Merge.INPUTS = 3

--- The most merge stars one copy can carry.
Merge.MAX_LEVEL = 3

--- Chance of success when trying FOR this level (index = the level you would reach).
Merge.SUCCESS = { 0.75, 0.55, 0.35 }

--- Added to the success chance for every failed merge of that nuke since its last
--- success, and the ceiling the two together may reach.
Merge.PITY_STEP = 0.10
Merge.SUCCESS_MAX = 0.95

--- Share of rolls that crit to +2, before luck; how much each whole 1.0 of luck
--- multiplier above 1 adds; and the ceiling.
Merge.CRIT = 0.10
Merge.CRIT_PER_LUCK = 0.10
Merge.CRIT_MAX = 0.30

--- Each merge star multiplies sale value and stand income by this.
Merge.VALUE_STEP = 1.5

--- The fee, as a share of what one PLAIN copy of the nuke is worth (base value times
--- its weight multiplier) at the inputs' current merge level. Never under FEE_MIN.
Merge.FEE_SHARE = 0.15
Merge.FEE_MIN = 10

--- Merge stars are drawn as the same star glyph as the rating (the game fonts carry
--- U+2605; they do not all carry fancier stars), in this colour.
Merge.GLYPH = "\u{2605}"
Merge.COLOR = Color3.fromHex("FF7AC6")

--- Quality modifiers from best to worst, for picking what a merge result wears.
--- Anything not listed ranks below all of these. Slagged can never be merged.
Merge.MODIFIER_RANK = { "PrewarSealed", "Pristine", "Irradiated", "Fused", "None", "Cracked" }

--- A copy's merge level, 0 for anything that has never been merged (the field is
--- absent on every record written before the reactor existed).
function Merge.levelOf(item: any): number
	local level = if type(item) == "table" then item.merge else nil
	if type(level) ~= "number" then
		return 0
	end
	return math.clamp(math.floor(level), 0, Merge.MAX_LEVEL)
end

--- What `level` merge stars multiply value and income by.
function Merge.valueMult(level: number?): number
	return Merge.VALUE_STEP ^ math.clamp(level or 0, 0, Merge.MAX_LEVEL)
end

--- The merge stars as text ("★★"), empty for 0.
function Merge.text(level: number?): string
	return string.rep(Merge.GLYPH, math.clamp(level or 0, 0, Merge.MAX_LEVEL))
end

--- Position of `modifier` in MODIFIER_RANK (1 = best); unknown ones sort last.
function Merge.modifierRank(modifier: string?): number
	for index, name in Merge.MODIFIER_RANK do
		if name == (modifier or "None") then
			return index
		end
	end
	return #Merge.MODIFIER_RANK + 1
end

export type Odds = {
	target: number, -- the level a success reaches (from + 1)
	success: number, -- 0..1, every success including crits
	crit: number, -- 0..1, the part of `success` that lands +2 (0 when +2 does not fit)
}

--- The odds of one merge whose best input sits at `from`, after `pity` failed merges
--- of this nuke, at luck multiplier `luck` (StatResolver's luckMultiplier; 1 = none).
--- nil when `from` is already MAX_LEVEL -- nothing left to merge up to.
function Merge.odds(from: number, pity: number?, luck: number?): Odds?
	local target = from + 1
	local base = Merge.SUCCESS[target]
	if base == nil then
		return nil
	end
	local success = math.min(base + Merge.PITY_STEP * math.max(pity or 0, 0), Merge.SUCCESS_MAX)
	local crit = 0
	if target + 1 <= Merge.MAX_LEVEL then
		crit = math.min(Merge.CRIT + Merge.CRIT_PER_LUCK * math.max((luck or 1) - 1, 0), Merge.CRIT_MAX, success)
	end
	return { target = target, success = success, crit = crit }
end

--- How many levels a roll gains under `odds`: 2 (crit), 1 (success) or 0 (fail).
--- `roll` is a uniform [0, 1) draw.
function Merge.gain(odds: Odds, roll: number): number
	if roll < odds.crit then
		return 2
	elseif roll < odds.success then
		return 1
	end
	return 0
end

--- What merging three copies of `itemId` whose best sits at `from` costs.
function Merge.fee(itemId: string, from: number): number
	if not Items.has(itemId) then
		return Merge.FEE_MIN
	end
	local def = Items.get(itemId)
	local plain = def.baseValue * Weight.valueMult(def.weight) * Merge.valueMult(from)
	return math.max(Merge.FEE_MIN, math.floor(plain * Merge.FEE_SHARE + 0.5))
end

return Merge
