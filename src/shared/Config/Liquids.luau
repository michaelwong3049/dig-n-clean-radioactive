--!strict
--[[
	Liquids.lua — what comes out of the hose, and how the roll pad picks it.

	THE THIRD GATE THAT ISN'T A GATE. Config/Rarity's `hardness` column and
	Config/Gear's Cleaner `potency` column are the second gate (PLAN §2 step 4): a
	patch harder than your hose never comes off, ever, and the Quarantine Locker
	is where those items sit as a labelled advertisement for the next tier. That
	gate is the whole reason the Cleaner track sells, so a rolled liquid is NOT
	allowed to replace it.

	What a liquid does instead, in order of how much it matters:

	  rateMult   — how FAST you scrub. Every liquid moves this. Always safe.
	  xpMult     — what a cleared patch PAYS. Every liquid moves this. Always safe.
	  potency    — a BONUS on top of your hose, capped at +2 and only on the top
	               six of the table. This is the one that touches the gate, and the
	               cap is the entire reason it is allowed to.

	WHY +2 IS THE CAP, and why Util/Spec asserts it. A Garden Hose is potency 1 and
	Anomaly hardness is 7. If a rolled liquid could reach +6, a lucky first-hour
	player would clean the top of the catalogue with the starting tier and the
	Cleaner track would have nothing left to sell. At +2, the Garden Hose reaches
	hardness 3 (Rare) and stops — Epic and up still need a real hose, the Locker still
	fills, and what the jackpot buys you is ONE tier of reach for a handful of
	patches. That is a treat, not a bypass.

	THE LIQUID AND THE HOSE ARE TWO DIFFERENT PURCHASES AND THE UI MUST KEEP SAYING SO.
	They were easy to tell apart when the Cleaner track sold brushes and sponges; now
	that it sells hoses, "your hose" and "what is in your hose" are one word apart. So
	nothing here calls a liquid "the hose": the liquid is always named (Glacier Melt),
	and the permanent capability is always the rung name (Pressure Lance). See
	WashService's two-clause too-tough message for the same rule applied to a string
	a player actually reads.

	PLAIN WATER IS THE FLOOR AND IT NEVER RUNS OUT. Every other liquid arrives with
	`charges` (one per patch cleared) and reverts to Water at zero. Water is
	deliberately absent from the roll table and absent from the profile — an empty
	`data.liquids` IS "you are on water". A player must never be unable to clean
	anything at all, because "I cannot progress and cannot fix it" is the one state
	this design has no answer for. Water is that answer, permanently.

	`charges` IS THE REAL SCARCITY, NOT THE ODDS. Antimatter Tonic clears three patches
	and a Legendary carries five, so even the jackpot does not finish a top-end item
	on its own. That is deliberate: it keeps the pad worth stepping on after you have
	already rolled well once, which a permanent liquid would not.

	THE ROLL ODDS, as `oddsAt` computes them, across a representative range of luck
	values (Luck has no fixed ladder any more — see Config/Gear.luau's header).
	Regenerate this table from Util/TuningReport after touching any weight or bias:

	                     1.0     1.5     2.2     3.1     4.3     6.0     8.0
	  Soapy Suds        34.67%  30.17%  25.90%  22.12%  18.63%  15.25%  12.54%
	  Fizzy Pop         17.91%  16.91%  15.67%  14.33%  12.88%  11.28%   9.82%
	  Pickle Brine      13.29%  13.06%  12.58%  11.91%  11.06%  10.01%   8.97%
	  Bubblegum Gel     10.98%  11.47%  11.70%  11.66%  11.37%  10.82%  10.12%
	  Blue Razz Slush    7.22%   7.95%   8.53%   8.88%   9.04%   8.98%   8.73%
	  Glacier Melt       6.07%   7.01%   7.87%   8.55%   9.05%   9.35%   9.41%
	  Honey Wax          3.47%   4.35%   5.27%   6.12%   6.92%   7.65%   8.15%
	  Rust Eater         2.37%   3.09%   3.89%   4.69%   5.47%   6.25%   6.86%
	  Ghost Mist         1.91%   2.59%   3.39%   4.22%   5.10%   6.02%   6.79%
	  Molten Lava        0.87%   1.30%   1.88%   2.55%   3.34%   4.28%   5.19%
	  Plasma Jelly       0.58%   0.91%   1.35%   1.90%   2.57%   3.42%   4.26%
	  Nano-Foam          0.35%   0.58%   0.91%   1.35%   1.92%   2.68%   3.49%
	  Atomic Slime       0.20%   0.36%   0.60%   0.93%   1.40%   2.05%   2.78%
	  Stardust Rinse     0.09%   0.16%   0.29%   0.47%   0.74%   1.15%   1.63%
	  Antimatter Tonic   0.04%   0.09%   0.17%   0.30%   0.50%   0.82%   1.24%

	  any +1 potency    15.93%  20.44%  25.63%  31.09%  37.01%  43.67%  49.81%
	  any +2 potency     2.12%   3.40%   5.21%   7.51%  10.47%  14.39%  18.60%

	Three properties of that table are the design, and Util/Spec pins all three:

	  * THE FLOOR NEVER DISAPPEARS. Soapy Suds is still 12.5% at luck 8. A roll you
	    can predict is not a roll, and a pad that always pays is a vending machine.
	  * THE JACKPOT MOVES 28x END TO END (Antimatter Tonic, 1-in-2,300 to 1-in-81).
	    That is what the Luck track is actually buying, and it has to be visible in
	    one sitting or the ladder feels like a tax.
	  * LUCK MOVES MASS UP THE TABLE, WHICH IS NOT THE SAME AS "EVERYTHING GETS
	    LIKELIER", and reading the table above carelessly will tell you otherwise.
	    Fizzy Pop has a positive bias and its share still FALLS, 17.91% -> 9.82%: it
	    gains on Soapy Suds and loses to every entry above it, which is exactly
	    what a luck curve should do. The property that actually has to hold is that
	    no adjacent pair ever INVERTS — a rarer liquid must never become relatively
	    rarer as luck rises — and `luckBias` ascending with `order` is what
	    guarantees it. Util/Spec pins both halves.

	TIERS ARE A LABEL, NOT A MECHANIC. Each rollable liquid carries a Config/Rarity name
	(`tier`) so the brew reveal can say how good a roll was at a glance, in the same
	colours the nukes use. Nothing rolls on it: the odds are `weight` and `luckBias`
	alone. Util/Spec pins that every tier is a real Rarity and never steps DOWN along
	ORDER, so the chip never calls a rarer fluid a lesser tier.

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
	tier: string?, -- a Config/Rarity name, for the brew reveal's chip and colour. nil on water.
	flavor: string,
	weight: number, -- base roll weight at luck 1.0. 0 = never rolled.
	luckBias: number, -- the exponent luck is raised to for THIS entry. 0 = luck-proof.
	potency: number, -- BONUS on top of the hose's potency. Capped at 2, see the header.
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
	"pickle",
	"gel",
	"razz",
	"glacier",
	"honey",
	"rust",
	"ghost",
	"lava",
	"plasma",
	"nano",
	"atomic",
	"stardust",
	"antimatter",
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
		tier = "Common",
		order = 2,
		name = "Soapy Suds",
		color = "F2F5F7",
		flavor = "A whole bucket of bubbles. Cheerful, and faster than nothing.",
		weight = 1200,
		luckBias = 0.00,
		potency = 0,
		rateMult = 1.35,
		xpMult = 1.00,
		charges = 40,
	},
	pop = {
		tier = "Common",
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
	pickle = {
		tier = "Common",
		order = 4,
		name = "Pickle Brine",
		color = "9ACD32",
		flavor = "Sharp, green, and it smells like a deli fridge. The crust hates it more than you do.",
		weight = 460,
		luckBias = 0.30,
		potency = 0,
		rateMult = 1.50,
		xpMult = 1.30,
		charges = 32,
	},
	gel = {
		tier = "Uncommon",
		order = 5,
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
	razz = {
		tier = "Uncommon",
		order = 6,
		name = "Blue Razz Slush",
		color = "3B82F6",
		flavor = "Tastes like a gas-station freezer. Scrubs like one, too.",
		weight = 250,
		luckBias = 0.58,
		potency = 0,
		rateMult = 2.20,
		xpMult = 1.30,
		charges = 20,
	},
	glacier = {
		tier = "Rare",
		order = 7,
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
		tier = "Rare",
		order = 8,
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
	rust = {
		tier = "Rare",
		order = 9,
		name = "Rust Eater",
		color = "C2410C",
		flavor = "Eats rust, eats paint, eats most gloves. Keep it off your hands.",
		weight = 82,
		luckBias = 1.00,
		potency = 1,
		rateMult = 2.40,
		xpMult = 1.50,
		charges = 14,
	},
	ghost = {
		tier = "Epic",
		order = 10,
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
		tier = "Epic",
		order = 11,
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
	plasma = {
		tier = "Epic",
		order = 12,
		name = "Plasma Jelly",
		color = "D946EF",
		flavor = "Wobbles in the canister, crackles on contact. Nobody knows what it's made of.",
		weight = 20,
		luckBias = 1.45,
		potency = 2,
		rateMult = 3.40,
		xpMult = 1.70,
		charges = 8,
	},
	nano = {
		tier = "Legendary",
		order = 13,
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
	atomic = {
		tier = "Legendary",
		order = 14,
		name = "Atomic Slime",
		color = "39FF14",
		flavor = "Glows in the dark, glows in the light. Dissolves anything that isn't you. Probably.",
		weight = 7,
		luckBias = 1.75,
		potency = 2,
		rateMult = 4.40,
		xpMult = 2.20,
		charges = 5,
	},
	stardust = {
		tier = "Mythic",
		order = 15,
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
	antimatter = {
		tier = "Mythic",
		order = 16,
		name = "Antimatter Tonic",
		color = "E11D48",
		flavor = "Three drops in the whole vial. The dirt doesn't come off, it just stops existing.",
		weight = 1.5,
		luckBias = 2.10,
		potency = 2,
		rateMult = 6.00,
		xpMult = 3.20,
		charges = 3,
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
--- answer whenever the shortfall is more than MAX_POTENCY_BONUS, and the point at
--- which the only remaining answer is a better hose (CarryService.hoseNameFor).
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
