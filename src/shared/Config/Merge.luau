--!strict
--[[
	Merge.luau — the Merge Reactor at Toxic Twilight: three copies of one nuke go in,
	one comes out with MERGE STARS on it.

	Config/ RULE (Tuning.luau's header): data only, no requires of anything outside
	Config/. The helpers below are pure maths over these numbers, the same way
	Rarity.stars and Payload.fromRoll are, so the panel's odds bar and the server's
	roll are one function and cannot disagree.

	A MERGE STAR IS NOT A RATING STAR. The rating (Rarity.stars) is the tier, nudged by
	quality, size and stage, and stops at 10. A merge star is a stored upgrade on ONE copy --
	`item.merge`, 0..MAX_LEVEL, carried through the bag, the locker and the stands --
	drawn after the rating in its own colour, so an Anomaly already at 8 can still be
	merged up. Each one multiplies what the copy sells for AND what it pays on a stand
	by VALUE_STEP (EconomyService.valueOf, CarryService.describe,
	ExhibitService.entryYieldPerSecond all call `valueMult`).

	THE ROLL (reworked 2026-10-06, on request: "no fail chance at all, keep 3"):
	  * The target is one level above the HIGHEST level among the three inputs, so a +2
	    fed two plain copies goes to +3. Feeders never have to match levels.
	  * Every merge SUCCEEDS. CRIT is the share of merges that land +2 instead of +1,
	    grown by the player's luck multiplier (the Luck button and 2x luck), capped at
	    CRIT_MAX, and only while +2 still fits under MAX_LEVEL.
	  * With no risk left, the fee is the brake: FEE_SHARE of a plain copy, cut by the
	    Reactor mastery (StatResolver's mergeFee).
	  (Until then it was "gamble, keep best": SUCCESS 75/55/35% with pity, a fail
	  keeping the best copy. `data.mergePity` on old saves is now unread.)

	WHAT COMES OUT is not just the best copy bumped: it wears the best quality modifier
	among the three (MODIFIER_RANK) and the biggest payload roll among the three (its
	uid, since Config/Payload derives size from uid). Merging a Pristine with an
	HUGE copy is how you get a Pristine HUGE. Merge.result is that rule, and
	both MergeService (the write) and the panel (the preview) call it.
]]

local Items = require(script.Parent.Items)
local Weight = require(script.Parent.Weight)
local Rarity = require(script.Parent.Rarity)
local Payload = require(script.Parent.Payload)

local Merge = {}

--- How many copies go in.
Merge.INPUTS = 3

--- The most merge stars one copy can carry.
Merge.MAX_LEVEL = 3

--- Share of merges that crit to +2, before luck; how much each whole 1.0 of luck
--- multiplier above 1 adds; and the ceiling.
Merge.CRIT = 0.10
Merge.CRIT_PER_LUCK = 0.10
Merge.CRIT_MAX = 0.30

--- Each merge star multiplies sale value and stand income by this.
Merge.VALUE_STEP = 1.5

--- The fee, as a share of what one PLAIN copy of the nuke is worth (base value times
--- its weight multiplier) at the inputs' current merge level. Never under FEE_MIN.
Merge.FEE_SHARE = 0.30
Merge.FEE_MIN = 10

--- Merge stars are drawn as the same star glyph as the rating (the game fonts carry
--- U+2605; they do not all carry fancier stars), in this colour.
Merge.GLYPH = "\u{2605}"
Merge.COLOR = Color3.fromHex("FF7AC6")

--- Quality modifiers from best to worst, for picking what a merge result wears.
--- Anything not listed ranks below all of these. Slagged can never be merged.
Merge.MODIFIER_RANK = { "Pristine", "Irradiated", "Fused", "None", "Cracked" }

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
	target: number, -- the level a plain merge reaches (from + 1)
	crit: number, -- 0..1, the chance it lands +2 instead (0 when +2 does not fit)
}

--- The odds of one merge whose best input sits at `from`, at luck multiplier `luck`
--- (StatResolver's luckMultiplier; 1 = none). nil when `from` is already MAX_LEVEL --
--- nothing left to merge up to.
function Merge.odds(from: number, luck: number?): Odds?
	local target = from + 1
	if target > Merge.MAX_LEVEL then
		return nil
	end
	local crit = 0
	if target + 1 <= Merge.MAX_LEVEL then
		crit = math.min(Merge.CRIT + Merge.CRIT_PER_LUCK * math.max((luck or 1) - 1, 0), Merge.CRIT_MAX)
	end
	return { target = target, crit = crit }
end

--- How many levels a merge gains under `odds`: 2 (crit) or 1. `roll` is a uniform
--- [0, 1) draw.
function Merge.gain(odds: Odds, roll: number): number
	return if roll < odds.crit then 2 else 1
end

--- What merging three copies of `itemId` whose best sits at `from` costs, times
--- `discount` (the Reactor mastery's fee multiplier; 1 = none).
function Merge.fee(itemId: string, from: number, discount: number?): number
	if not Items.has(itemId) then
		return Merge.FEE_MIN
	end
	local def = Items.get(itemId)
	local plain = def.baseValue * Weight.valueMult(def.weight) * Merge.valueMult(from)
	return math.max(Merge.FEE_MIN, math.floor(plain * Merge.FEE_SHARE * (discount or 1) + 0.5))
end

export type Result = {
	uid: string, -- the biggest payload roll's uid
	modifier: string, -- the best quality among the three
	bonus: { string }?, -- every other quality any announced input stacked, best first
	level: number, -- the merge stars it comes out with
}

--- What three copies (records with uid / modifier / bonus / merge) come out as after
--- gaining `gain` levels.
function Merge.result(inputs: { any }, gain: number): Result
	local from = 0
	local bigUid, bigPayload = inputs[1].uid, -math.huge
	local modifier = inputs[1].modifier or "None"
	for _, item in inputs do
		from = math.max(from, Merge.levelOf(item))
		local payload = Payload.forUid(item.uid)
		if payload > bigPayload then
			bigUid, bigPayload = item.uid, payload
		end
		if Merge.modifierRank(item.modifier) < Merge.modifierRank(modifier) then
			modifier = item.modifier or "None"
		end
	end
	-- An announced drop's stacked qualities survive the merge: every quality of any
	-- input that carried a `bonus`, best first, minus the one worn as `modifier`.
	local stacked: { string } = {}
	for _, item in inputs do
		if item.bonus then
			for _, quality in Rarity.qualities(item.modifier, item.bonus) do
				if quality ~= modifier and not table.find(stacked, quality) then
					table.insert(stacked, quality)
				end
			end
		end
	end
	table.sort(stacked, function(a, b)
		return Merge.modifierRank(a) < Merge.modifierRank(b)
	end)
	return {
		uid = bigUid,
		modifier = modifier,
		bonus = if #stacked > 0 then stacked else nil,
		level = math.min(from + gain, Merge.MAX_LEVEL),
	}
end

--- How much a copy's value (and stand income) scales when it becomes `result`: the
--- quality, size and merge-star factors swapped, everything else (decay, sell
--- multipliers) unchanged.
function Merge.valueRatio(item: any, result: Result): number
	local before = Rarity.valueMult(item.modifier, item.bonus) * Payload.forUid(item.uid) * Merge.valueMult(Merge.levelOf(item))
	local after = Rarity.valueMult(result.modifier, result.bonus) * Payload.forUid(result.uid) * Merge.valueMult(result.level)
	return after / math.max(before, 1e-6)
end

return Merge
