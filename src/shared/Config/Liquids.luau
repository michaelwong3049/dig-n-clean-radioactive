--!strict
--[[
	Liquids.lua — what comes out of the hose, and how the roll pad picks it.

	THE THIRD GATE THAT ISN'T A GATE. Config/Rarity's `hardness` column and
	Config/Gear's Cleaner `potency` column are the second gate (PLAN §2 step 4): a
	patch harder than your cleaner never comes off, ever, and the Quarantine Locker
	is where those items sit as a labelled advertisement for the next tier. That
	gate is the whole reason the Cleaner track sells, so a rolled liquid is NOT
	allowed to replace it.

	What a liquid does instead, in order of how much it matters:

	  rateMult   — how FAST you scrub. Every liquid moves this. Always safe.
	  xpMult     — what a cleared patch PAYS. Every liquid moves this. Always safe.
	  potency    — a BONUS on top of your cleaner, capped at +2 and only on the top
	               six of the table. This is the one that touches the gate, and the
	               cap is the entire reason it is allowed to.

	WHY +2 IS THE CAP, and why Util/Spec asserts it. A Wire Brush is potency 1 and
	Anomaly hardness is 7. If a rolled liquid could reach +6, a lucky first-hour
	player would clean the top of the catalogue with the starting tool and the
	Cleaner track would have nothing left to sell. At +2, the starting brush reaches
	hardness 3 (Rare) and stops — Epic and up still need real tools, the Locker still
	fills, and what the jackpot buys you is ONE tier of reach for a handful of
	patches. That is a treat, not a bypass.

	PLAIN WATER IS THE FLOOR AND IT NEVER RUNS OUT. Every other liquid arrives with
	`charges` (one per patch cleared) and reverts to Water at zero. Water is
	deliberately absent from the roll table and absent from the profile — an empty
	`data.liquids` IS "you are on water". A player must never be unable to clean
	anything at all, because "I cannot progress and cannot fix it" is the one state
	this design has no answer for. Water is that answer, permanently.

	`charges` IS THE REAL SCARCITY, NOT THE ODDS. Stardust Rinse clears four patches
	and a Legendary carries five, so even the jackpot does not finish a top-end item
	on its own. That is deliberate: it keeps the pad worth stepping on after you have
	already rolled well once, which a permanent liquid would not.

	THE ROLL ODDS, as `oddsAt` computes them, across the whole Gear.Luck ladder.
	Regenerate this table from Util/TuningReport after touching any weight or bias:

	                   1.0     1.5     2.2     3.1     4.3     6.0     8.0
	  Soapy Suds      40.97%  36.17%  31.48%  27.23%  23.22%  19.27%  16.06%
	  Fizzy Pop       25.40%  24.32%  22.85%  21.17%  19.27%  17.10%  15.09%
	  Bubblegum Gel   15.57%  16.50%  17.06%  17.22%  17.01%  16.40%  15.56%
	  Glacier Melt     8.60%  10.09%  11.48%  12.63%  13.54%  14.19%  14.46%
	  Honey Wax        4.92%   6.25%   7.68%   9.05%  10.36%  11.60%  12.52%
	  Ghost Mist       2.70%   3.73%   4.95%   6.24%   7.62%   9.13%  10.44%
	  Molten Lava      1.23%   1.88%   2.74%   3.76%   4.99%   6.50%   7.98%
	  Nano-Foam        0.49%   0.83%   1.33%   2.00%   2.87%   4.07%   5.37%
	  Stardust Rinse   0.12%   0.23%   0.42%   0.70%   1.11%   1.74%   2.50%

	  any +1 potency  16.22%  20.07%  24.11%  27.91%  31.52%  34.92%  37.43%
	  any +2 potency   1.84%   2.94%   4.49%   6.46%   8.98%  12.30%  15.86%

	Three properties of that table are the design, and Util/Spec pins all three:

	  * THE FLOOR NEVER DISAPPEARS. Soapy Suds is still 16% at maxed luck. A roll you
	    can predict is not a roll, and a pad that always pays is a vending machine.
	  * THE JACKPOT MOVES 20x END TO END (1-in-814 to 1-in-40). That is what the Luck
	    track is actually buying, and it has to be visible in one sitting or the
	    ladder feels like a tax.
	  * LUCK MOVES MASS UP THE TABLE, WHICH IS NOT THE SAME AS "EVERYTHING GETS
	    LIKELIER", and reading the table above carelessly will tell you otherwise.
	    Fizzy Pop has a positive bias and its share still FALLS, 25.40% -> 15.09%: it
	    gains on Soapy Suds and loses to all six entries above it, which is exactly
	    what a luck curve should do. The property that actually has to hold is that
	    no adjacent pair ever INVERTS — a rarer liquid must never become relatively
	    rarer as luck rises — and `luckBias` ascending with `order` is what
	    guarantees it. Util/Spec pins both halves.

	HOW LUCK BENDS IT: `effectiveWeight = weight * luck ^ luckBias`. Soapy Suds has
	bias 0, so its weight is luck-proof and every other entry gains on it — that is
	why the whole table can be described by one exponent per row instead of by a
	second set of weights per luck tier. Raising a bias steepens that entry alone.
]]

local Liquids = {}

export type LiquidDef = {
	order: number,
	name: string,
	color: string, -- hex; the canister, the stream, and the roll card all read it
	flavor: string,
	weight: number, -- base roll weight at luck 1.0. 0 = never rolled.
	luckBias: number, -- the exponent luck is raised to for THIS entry. 0 = luck-proof.
	potency: number, -- BONUS on top of Cleaner potency. Capped at 2, see the header.
	rateMult: number, -- multiplies scrubRate
	xpMult: number, -- multiplies XP per cleared patch
	charges: number, -- patches this liquid can clear per roll. Ignored for water.
}

--- Deterministic iteration order. `pairs()` order is not stable and a weighted roll
--- that walks an unstable order is a weighted roll with unstable odds — the same
--- reason DigService.rollRarity walks Rarity.ORDER instead of the DEFS table.
Liquids.ORDER = {
	"water",
	"suds",
	"pop",
	"gel",
	"glacier",
	"honey",
	"ghost",
	"lava",
	"nano",
	"stardust",
}

--- The floor. Absent from the profile, absent from the roll table, always available.
Liquids.WATER = "water"

--- The cap the header argues for. Util/Spec asserts no entry exceeds it.
Liquids.MAX_POTENCY_BONUS = 2

Liquids.DEFS = {
	water = {
		order = 1,
		name = "Plain Water",
		color = "6FD5E8",
		flavor = "It's water. It always works, and it never runs out.",
		weight = 0,
		luckBias = 0,
		potency = 0,
		rateMult = 1.00,
		xpMult = 1.00,
		charges = 0,
	},
	suds = {
		order = 2,
		name = "Soapy Suds",
		color = "F2F5F7",
		flavor = "A whole bucket of bubbles. Cheerful, and faster than nothing.",
		weight = 1000,
		luckBias = 0.00,
		potency = 0,
		rateMult = 1.35,
		xpMult = 1.00,
		charges = 40,
	},
	pop = {
		order = 3,
		name = "Fizzy Pop",
		color = "F59E0B",
		flavor = "Shaken, warm, and weirdly good at lifting grime.",
		weight = 620,
		luckBias = 0.20,
		potency = 0,
		rateMult = 1.60,
		xpMult = 1.10,
		charges = 30,
	},
	gel = {
		order = 4,
		name = "Bubblegum Gel",
		color = "F472B6",
		flavor = "Pink, stretchy, and it takes the dirt with it when it peels.",
		weight = 380,
		luckBias = 0.45,
		potency = 0,
		rateMult = 1.90,
		xpMult = 1.25,
		charges = 24,
	},
	glacier = {
		order = 5,
		name = "Glacier Melt",
		color = "A5E9FF",
		flavor = "Meltwater off something very old and very cold. Cracks the crust.",
		weight = 210,
		luckBias = 0.70,
		potency = 1,
		rateMult = 2.10,
		xpMult = 1.20,
		charges = 18,
	},
	honey = {
		order = 6,
		name = "Honey Wax",
		color = "FFC94A",
		flavor = "Slow, golden, and it leaves a shine the buyers notice.",
		weight = 120,
		luckBias = 0.90,
		potency = 1,
		rateMult = 1.80,
		xpMult = 1.90,
		charges = 14,
	},
	ghost = {
		order = 7,
		name = "Ghost Mist",
		color = "C4B5FD",
		flavor = "You can barely see it leave the nozzle. The dirt can.",
		weight = 66,
		luckBias = 1.10,
		potency = 1,
		rateMult = 2.60,
		xpMult = 1.40,
		charges = 12,
	},
	lava = {
		order = 8,
		name = "Molten Lava",
		color = "FF6B35",
		flavor = "Absolutely not approved for this. Absolutely does work.",
		weight = 30,
		luckBias = 1.35,
		potency = 2,
		rateMult = 3.20,
		xpMult = 1.50,
		charges = 8,
	},
	nano = {
		order = 9,
		name = "Nano-Foam",
		color = "5EEAD4",
		flavor = "Billions of tiny scrubbers, each one having the day of its life.",
		weight = 12,
		luckBias = 1.60,
		potency = 2,
		rateMult = 3.80,
		xpMult = 1.90,
		charges = 6,
	},
	stardust = {
		order = 10,
		name = "Stardust Rinse",
		color = "FFF3B0",
		flavor = "Four squirts in the whole canister. Spend them on something good.",
		weight = 3,
		luckBias = 1.90,
		potency = 2,
		rateMult = 5.00,
		xpMult = 2.60,
		charges = 4,
	},
} :: { [string]: LiquidDef }

function Liquids.get(id: string?): LiquidDef
	local def = Liquids.DEFS[id or Liquids.WATER]
	return def or Liquids.DEFS[Liquids.WATER]
end

--- True for anything the pad can actually hand you. Water is the one exception and
--- it is the reason this is a function rather than a `weight > 0` check scattered
--- across three call sites.
function Liquids.isRollable(id: string): boolean
	local def = Liquids.DEFS[id]
	return def ~= nil and def.weight > 0
end

--- `weight * luck ^ luckBias`. Shared so the odds the roll pad DISPLAYS and the
--- odds LiquidService actually rolls come out of one function — the same rule
--- Radiation, Decay and Contamination follow (ARCHITECTURE.md, "Server/client
--- boundary"). A pad that advertises 1-in-40 and rolls 1-in-800 is the single
--- worst bug this feature could ship.
function Liquids.effectiveWeight(def: LiquidDef, luck: number): number
	if def.weight <= 0 then
		return 0
	end
	return def.weight * math.max(luck, 0.01) ^ def.luckBias
end

--- Normalised probability per liquid at this luck, keyed by id. Sums to 1.
--- Unrollable entries (water) are absent rather than zero, so a caller iterating
--- this never has to special-case the floor.
function Liquids.oddsAt(luck: number): { [string]: number }
	local total = 0
	for _, id in Liquids.ORDER do
		total += Liquids.effectiveWeight(Liquids.DEFS[id], luck)
	end

	local odds: { [string]: number } = {}
	if total <= 0 then
		return odds
	end
	for _, id in Liquids.ORDER do
		local weight = Liquids.effectiveWeight(Liquids.DEFS[id], luck)
		if weight > 0 then
			odds[id] = weight / total
		end
	end
	return odds
end

--- The cheapest liquid that would add this much potency, for "Molten Lava cracks
--- this" style labels. nil when no liquid reaches that far — which is the honest
--- answer whenever the shortfall is more than MAX_POTENCY_BONUS.
function Liquids.cheapestWithPotency(bonus: number): LiquidDef?
	if bonus <= 0 then
		return nil
	end
	for _, id in Liquids.ORDER do
		local def = Liquids.DEFS[id]
		if def.weight > 0 and def.potency >= bonus then
			return def
		end
	end
	return nil
end

return Liquids
