--!strict
--[[
	Spec.lua — assertions that pin the DESIGN INTENT, not the implementation.

	Run in Studio's command bar:
	    require(game.ReplicatedStorage.Shared.Util.Spec).run()

	Every check here corresponds to a sentence in PLAN.md. When you retune Config/,
	these tell you which part of the design you just broke. They are deliberately
	written as ranges, not exact values — the point is to catch "you moved a number
	and the Dive is now 4 seconds", not to freeze the balance.

	Two of these exist because the first draft of the config got them WRONG, and only
	running the numbers caught it:
	  * "hot bag does not trip suit failure" — carried emission was counting toward
	    suit tolerance, so a full backpack triggered the white-screen over-tier state
	    inside your own rated stage.
	  * "satchel shielding is a real upgrade" — the suit's reduction was being applied
	    to your own backpack, which erased 99% of a screaming Legendary and quietly
	    switched off the greed dial (§3.3), the mechanic the whole game is built on.

	Keep both. They guard the two most load-bearing sentences in the design.
]]

local Config = script.Parent.Parent.Config
local Stages = require(Config.Stages)
local Gear = require(Config.Gear)
local Tuning = require(Config.Tuning)
local Rarity = require(Config.Rarity)
local Liquids = require(Config.Liquids)
local Items = require(Config.Items)
local ItemModels = require(script.Parent.Parent.ItemModels)
local Radiation = require(script.Parent.Parent.Radiation)
local Decay = require(script.Parent.Parent.Decay)
local StatResolver = require(script.Parent.Parent.StatResolver)

local Spec = {}

local function statsFor(suitTier: number, satchelTier: number)
	local suit = Gear.tier("Suit", suitTier)
	local satchel = Gear.tier("Satchel", satchelTier)
	return {
		suitReduction = suit.reduction,
		suitTolerance = suit.tolerance,
		satchelShielding = satchel.shielding,
		levelResist = 0,
	}
end

--- `depthFrac` picks WHERE in the stage to test: 0 (entrance) for "can you work
--- here safely", 1 (deepest) for "what happens if you actually push in" -- see
--- Stages.radsAt. Defaults to 0 so existing call sites that don't care about depth
--- keep testing the same "just inside the stage" point they always did.
local function survive(stageId: number, suitTier: number, satchelTier: number, carried: number, depthFrac: number?): number
	local reading = Radiation.resolve(Radiation.ambientAt(Stages.radsAt(stageId, depthFrac or 0)), carried, statsFor(suitTier, satchelTier))
	return Radiation.survivableSeconds(reading, 0, 100)
end

local function bagOf(rarity: string, modifier: string, count: number, elapsed: number)
	local bag = {}
	for i = 1, count do
		table.insert(bag, { uid = "spec" .. i, itemId = "spec", rarity = rarity, modifier = modifier, elapsed = elapsed, frozen = false })
	end
	return bag
end

function Spec.run(): boolean
	local passed, failed = 0, 0
	local lines = { "\n=== DESIGN SPEC ===\n" }

	local function check(label: string, ok: boolean)
		if ok then
			passed += 1
			table.insert(lines, "  PASS  " .. label)
		else
			failed += 1
			table.insert(lines, "  FAIL  " .. label)
		end
	end

	-- Catalogue art is intentionally arriving item by item, but every key that has
	-- been assigned must resolve. A typo here would otherwise degrade silently to a
	-- placeholder and make a finished asset look as though it had never shipped.
	for _, item in Items.DEFS do
		if item.model then
			check(`item model resolves: {item.id} -> {item.model}`, ItemModels.has(item.model))
		end
	end

	-- PLAN §3.5 — the Dive is ~one dig, in every stage. Tested at the ENTRANCE
	-- (depthFrac=0), same as before this file's depth-based radiation pass -- this
	-- check is about "one tier under, at all," and the entrance rate is exactly
	-- the number these targets were originally fitted against, unchanged by the
	-- depth pass on purpose (see Stages.luau's header note). Real depth-driven
	-- danger is checked separately below, directly against Stages.radsAt, rather
	-- than folded into this already-precisely-tuned survival-time math.
	--
	-- BAND TIGHTENED 25-40 -> 18-30 (second pass) -> 8-15 (third pass, BURN_COEF
	-- 3.0->6.0, Tuning.luau): the dive now lands at ~12s, was ~23s, was ~35s
	-- originally. This band moved a second time as a direct, unavoidable side
	-- effect of an explicit Stage 3 unsuited-survival target, NOT an independent
	-- decision to keep tightening the Dive on its own -- see Tuning.luau's
	-- BURN_COEF comment for the full reasoning on why the two couldn't be
	-- decoupled. Still "sprint in, grab one signal, extract, run," just a much
	-- faster sprint than PLAN §3.5 originally imagined.
	for stageId = 3, 6 do
		local s = survive(stageId, Stages.get(stageId).ratedSuitTier - 1, 1, 0)
		check(string.format("§3.5 dive window in stage %d = %.0fs (want 8-15)", stageId, s), s >= 8 and s <= 15)
	end

	-- PLAN §3.4 — a rated suit means you can work, not just survive. Entrance,
	-- same reasoning as the Dive above.
	--
	-- STAGE 1 IS DELIBERATELY EXCLUDED FROM THIS LOOP as of the third harshening
	-- pass. Stage 1's rated suit tier IS Cloth Wrap (the starting/no-gear tier), so
	-- this check used to mean "a fresh player can stand in Stage 1 forever" -- true
	-- before this pass (it was exposure-bound at ~33 minutes), no longer true by
	-- explicit design choice (capped at 9 minutes via Cloth Wrap's own `reduction`,
	-- see Gear.luau). Checked on its own immediately below instead of silently
	-- dropped, so a future change can't quietly regress it back past 15 minutes
	-- without this file complaining.
	for stageId = 2, 5 do
		check(string.format("§3.4 rated suit farmable in stage %d", stageId), survive(stageId, Stages.get(stageId).ratedSuitTier, 1, 0) > 900)
	end
	do
		local s = survive(1, 1, 1, 0)
		check(string.format("§3.4 stage 1 unsuited capped at ~9min = %.0fs (want 480-600)", s), s >= 480 and s <= 600)
	end

	-- The ask was "an unsuited player should die fast near Stage 1's own far end" --
	-- checked at Stage 1's own deepest point (depthFrac=1.0, its worst case for this
	-- bound, since ambient only climbs further in), tuned via Stage 1's deepRads
	-- specifically (see Stages.luau's Stage 1 comment for why 1.97 and not higher --
	-- any higher breaks "Stage 1 is the safest stage" against Stage 2's own entrance).
	do
		local s = survive(1, 1, 1, 0, 1.0)
		check(string.format("§new Stage 1's own deepest point, unsuited dies within 30s = %.0fs", s), s < 30)
	end

	-- PLAN §4 — the Crater never becomes a farm, at any gear level, forever.
	-- Entrance, same reasoning.
	local crater = survive(6, 6, 1, 0)
	check(string.format("§4 Crater with full Rig = %.0fs (want 60-130, a heist)", crater), crater > 60 and crater < 130)

	-- NEW: depth-based radiation itself (PLAN's "make it harsher, and make going
	-- deeper and crossing stages feel like it" request). Checked directly against
	-- Stages.radsAt rather than through survival-time math, which is sensitive
	-- enough to small ambient changes that it's the wrong tool for pinning a
	-- geometry fact.
	for _, id in Stages.builtIds() do
		check(string.format("§new stage %d radiation climbs with depth", id), Stages.radsAt(id, 1) > Stages.radsAt(id, 0))
	end
	for id = 2, #Stages.builtIds() do
		check(
			string.format("§new stage %d entrance beats stage %d's deepest point", id, id - 1),
			Stages.radsAt(id, 0) > Stages.radsAt(id - 1, 1)
		)
	end

	-- PLAN §3.5 — over-tier is the WHITE failure state and it ignores your bag.
	-- Tested at depthFrac=0: if being under-tiered fails you even at the shallow
	-- edge, it fails you everywhere, which is the point being checked.
	local overEmpty = survive(5, 3, 1, 0, 0)
	local overFull = survive(5, 3, 1, Decay.totalEmission(bagOf("Rare", "None", 8, 0), 1), 0)
	check("§3.5 over-tier burn is unaffected by what you carry", math.abs(overEmpty - overFull) < 1)
	local overReading = Radiation.resolve(Radiation.ambientAt(Stages.radsAt(5, 0)), 0, statsFor(3, 1))
	check("§3.5 over-tier flags suit failure", overReading.failing)
	check("§3.5 over-tier dominant threat is burn", Radiation.dominantThreat(overReading, 0, 100) == "burn")

	-- PLAN §3.3 — the greed dial. Carrying loot is the GREEN threat, never the
	-- white one. Tested at depthFrac=0, same "safe at the entrance" reasoning.
	local hotBag = { bagOf("Epic", "None", 1, 0)[1], bagOf("Legendary", "Irradiated", 1, 200)[1] }
	local hotReading = Radiation.resolve(Radiation.ambientAt(Stages.radsAt(3, 0)), Decay.totalEmission(hotBag, 1), statsFor(3, 1))
	check("§3.3 a hot bag does NOT trip suit failure in your rated stage", not hotReading.failing)
	check("§3.3 a hot bag's threat is exposure, not burn", Radiation.dominantThreat(hotReading, 0, 100) == "exposure")
	local hotS = Radiation.survivableSeconds(hotReading, 0, 100)
	check(string.format("§3.3 cooking Legendary creates real pressure: %.0fs (want 20-90)", hotS), hotS > 20 and hotS < 90)
	check("§3.3 the bag, not the world, is what is killing you", Radiation.greedFraction(hotReading, statsFor(3, 1)) > 0.9)

	-- PLAN §3.3 — but a normal full bag is comfortable. Greed should be a choice, not a tax.
	local fullS = survive(3, 3, 1, Decay.totalEmission(bagOf("Rare", "None", 8, 0), 1))
	check(string.format("§3.3 a full bag of rated loot is comfortable: %.0fs (want 150-330)", fullS), fullS > 150 and fullS < 330)
	check("§3.3 an empty bag in your rated stage is safe indefinitely", survive(3, 3, 1, 0) > 900)

	-- PLAN §3.7 — the satchel is a real upgrade, and never a total one
	local shieldedS = survive(3, 3, 5, Decay.totalEmission(hotBag, 1))
	check(string.format("§3.7 top satchel triples the window: %.0fs vs %.0fs", shieldedS, hotS), shieldedS > hotS * 3)
	for tier = 1, Gear.maxTier("Satchel") do
		check(string.format("§3.7 satchel %d shields <100%% (greed survives)", tier), Gear.tier("Satchel", tier).shielding < 1)
		check(string.format("§3.7 satchel %d fuse is finite (slows, never stops)", tier), Gear.tier("Satchel", tier).fuseMult < math.huge)
	end

	-- PLAN §3.6 — the decay clock
	local leg = bagOf("Legendary", "None", 1, 0)[1]
	check("§3.6 Legendary fuse is 2:00", Decay.fuseFor(leg, 1) == 120)
	leg.elapsed = 119
	local s1 = Decay.conditionOf(leg, 1)
	leg.elapsed = 121
	local s2 = Decay.conditionOf(leg, 1)
	leg.elapsed = 361
	local s3 = Decay.conditionOf(leg, 1)
	check("§3.6 Fresh -> Hot at T, Slag past 3T", s1 == 1 and s2 == 2 and s3 == 4)
	check("§3.6 rarer items burn faster", Decay.fuseFor(bagOf("Anomaly", "None", 1, 0)[1], 1) < Decay.fuseFor(bagOf("Common", "None", 1, 0)[1], 1))
	check("§3.6 Slag still retains a token 10%", math.abs(Decay.valueRetained(leg, 1) - 0.10) < 1e-9)

	-- PLAN §7 — Prewar Sealed is the jackpot: no clean, no clock
	local sealed = bagOf("Mythic", "PrewarSealed", 1, 99999)[1]
	check("§7 Prewar Sealed never leaves Fresh", Decay.conditionOf(sealed, 1) == 1)
	check("§7 Prewar Sealed emits nothing", Decay.emissionOf(sealed, 1) == 0)

	-- PLAN §3.6 — freezing is total and one-way
	local frozen = bagOf("Mythic", "None", 1, 10)[1]
	frozen.frozen = true
	Decay.tick(frozen, 5, 1)
	check("§3.6 a docked item stops emitting, ticking, and counting down", Decay.totalEmission({ frozen }, 1) == 0 and frozen.elapsed == 10 and Decay.secondsToNextCondition(frozen, 1) == math.huge)

	-- PLAN §9.2 / §5.1 — one resolver, perks folded in exactly once
	local profile = {
		level = 20,
		gear = { detector = 3, magnet = 2, cleaner = 4, suit = 3, boots = 2, satchel = 3 },
		perks = { steadyHands = true, sureFooting = true },
		multipliers = { sell = 2 },
	}
	local stats = StatResolver.get(profile)
	check("§9.2 Steady Hands adds exactly +1 potency", stats.cleanPotency == Gear.tier("Cleaner", 4).potency + 1)
	check("§9.2 level 20 = 20% resist", math.abs(stats.levelResist - 0.20) < 1e-9)
	check("§9.2 level 20 = +4 carry capacity", stats.capacity == Gear.tier("Suit", 3).capacity + 4)
	check("§9.2 Sure Footing halves the haul penalty", math.abs(stats.haulPenalty - Gear.tier("Boots", 2).haulPenalty * 0.5) < 1e-9)
	check("§5.1 a full bag physically slows you", StatResolver.effectiveWalkSpeed(stats, stats.capacity, false) < stats.walkSpeed)
	check("§5.1 but never immobilises you", StatResolver.effectiveWalkSpeed(stats, 999, false) >= 6)

	-- The liquid folds into effectivePotency and NOWHERE ELSE. `cleanPotency` is the
	-- permanent capability the Locker and the Cleaner shop both read; the day someone
	-- "simplifies" this by adding the bonus into cleanPotency directly, the Locker
	-- starts promising items it cannot keep once the canister empties.
	check("§2.4 no liquid loaded means the two potencies agree", stats.effectivePotency == stats.cleanPotency)

	local hosed = table.clone(profile) :: any
	hosed.liquids = { lava = 3 }
	hosed.equippedLiquid = "lava"
	local hosedStats = StatResolver.get(hosed)
	check("§2.4 a loaded liquid raises effectivePotency", hosedStats.effectivePotency == stats.cleanPotency + Liquids.get("lava").potency)
	check("§2.4 ...and leaves cleanPotency alone", hosedStats.cleanPotency == stats.cleanPotency)

	-- AN EMPTY CANISTER IS THE SAME THING AS NO CANISTER. StatResolver.liquidFor is
	-- the single place that rule is written down, which is the only reason
	-- DeconService, CarryService and the panel cannot each forget it separately.
	local dry = table.clone(profile) :: any
	dry.liquids = { lava = 0 }
	dry.equippedLiquid = "lava"
	local dryStats = StatResolver.get(dry)
	check("§2.4 a spent canister falls back to Plain Water", dryStats.liquidId == Liquids.WATER and dryStats.effectivePotency == stats.cleanPotency)

	-- ── The wash pad (Config/Liquids, Config/Gear.Luck) ──────────────────
	--
	-- THE ONE THAT MATTERS MOST IS THE POTENCY CAP. Liquids lend potency on top of
	-- the Cleaner track, and the Cleaner track is PLAN §2 step 4's second hard gate —
	-- the thing that makes the Quarantine Locker fill and the Cleaner shop sell.
	-- Nudging one liquid's `potency` to 5 because a playtester found the wall
	-- annoying would silently delete that gate, and it would not fail anywhere else.
	local worstBonus = 0
	for _, id in Liquids.ORDER do
		worstBonus = math.max(worstBonus, Liquids.get(id).potency)
	end
	check(
		string.format("§2.4 no liquid lends more than +%d potency (found +%d)", Liquids.MAX_POTENCY_BONUS, worstBonus),
		worstBonus <= Liquids.MAX_POTENCY_BONUS
	)

	-- The starting brush plus the best possible roll must still hit a wall inside the
	-- catalogue, or the Cleaner track is decorative for a lucky player.
	local startingReach = Gear.tier("Cleaner", 1).potency + Liquids.MAX_POTENCY_BONUS
	check(
		string.format("§2.4 Wire Brush + the best liquid reaches hardness %d, short of Epic (%d)", startingReach, Rarity.get("Epic").hardness),
		startingReach < Rarity.get("Epic").hardness
	)

	-- PLAIN WATER IS THE FLOOR, AND IT IS THE ANTI-SOFTLOCK. A player with no cash
	-- and no canisters must still be able to clean something, or "I cannot progress
	-- and cannot fix it" becomes reachable — the one state this design has no answer
	-- for. Three properties make that true and all three are load-bearing.
	local water = Liquids.get(Liquids.WATER)
	check("§2.4 Plain Water is the bottom of the table", water.order == 1)
	check("§2.4 Plain Water lends no potency (it cannot be a gate key)", water.potency == 0)
	check("§2.4 Plain Water is never rolled (it is always simply there)", not Liquids.isRollable(Liquids.WATER))

	-- LUCK MUST NEVER MAKE ANYTHING YOU WANTED RARER. `effectiveWeight` raises luck
	-- to a per-entry exponent, so a negative or accidentally-zero bias on a top-end
	-- entry would make buying the Luck track actively harmful — invisible in play
	-- until someone with a Shooting Star notices they stopped seeing Stardust.
	local luckFloor = Gear.tier("Luck", 1).luck
	local luckCeiling = Gear.tier("Luck", Gear.maxTier("Luck")).luck
	local oddsLo, oddsHi = Liquids.oddsAt(luckFloor), Liquids.oddsAt(luckCeiling)

	-- THE INVARIANT IS "MASS MOVES UP THE TABLE", NOT "EVERY ENTRY GETS LIKELIER",
	-- and the first draft of this check asserted the second one and failed. It failed
	-- CORRECTLY: Fizzy Pop's share drops 25.4% -> 15.1% across the ladder despite a
	-- positive bias, because it gains on Soapy Suds while losing to everything above
	-- it. That is what a luck curve is supposed to do. What must never happen is an
	-- INVERSION -- a rarer liquid becoming relatively rarer than a commoner one --
	-- so the pairwise ratio is the thing to pin.
	local rollable: { string } = {}
	for _, id in Liquids.ORDER do
		if Liquids.isRollable(id) then
			table.insert(rollable, id)
		end
	end

	local monotone = true
	local biasAscending = true
	for index = 2, #rollable do
		local rarer, commoner = rollable[index], rollable[index - 1]
		if oddsHi[rarer] / oddsHi[commoner] <= oddsLo[rarer] / oddsLo[commoner] then
			monotone = false
		end
		if Liquids.get(rarer).luckBias <= Liquids.get(commoner).luckBias then
			biasAscending = false
		end
	end
	check("§6 luck only ever moves mass UP the table (no inversions)", monotone)
	check("§6 luckBias rises with every rung, which is what guarantees that", biasAscending)

	local sumLo, sumHi = 0, 0
	for _, chance in oddsLo do
		sumLo += chance
	end
	for _, chance in oddsHi do
		sumHi += chance
	end
	check("§6 the odds table is a probability distribution at both ends", math.abs(sumLo - 1) < 1e-9 and math.abs(sumHi - 1) < 1e-9)

	-- THE FLOOR NEVER DISAPPEARS. A roll you can predict is not a roll; if maxed luck
	-- ever pushes the commonest liquid under ~10% the pad has become a vending
	-- machine and the reveal animation is lying about there being a moment.
	local commonest = Liquids.ORDER[2]
	check(
		string.format("§6 the common end survives maxed luck: %s at %.1f%% (want >= 10%%)", Liquids.get(commonest).name, oddsHi[commonest] * 100),
		oddsHi[commonest] >= 0.10
	)

	-- ...and the jackpot has to visibly move, or the ladder reads as a tax.
	local jackpot = Liquids.ORDER[#Liquids.ORDER]
	check(
		string.format("§6 maxed luck multiplies the jackpot %.1fx (want >= 5x)", oddsHi[jackpot] / oddsLo[jackpot]),
		oddsHi[jackpot] / oddsLo[jackpot] >= 5
	)

	local luckAscending = true
	for tier = 2, Gear.maxTier("Luck") do
		local better = Gear.tier("Luck", tier)
		local worse = Gear.tier("Luck", tier - 1)
		if better.luck <= worse.luck or better.price <= worse.price then
			luckAscending = false
		end
	end
	check("§6 every Luck tier is both luckier and pricier than the last", luckAscending)

	-- A ROLL MUST BE WORTH LESS THAN WHAT IT CLEANS. The pad charges cash per roll and
	-- pays in charges; if a roll ever costs more than the cheapest item in the game is
	-- worth, the pad is a trap for exactly the players with the least money.
	check(
		string.format("§6 a roll ($%d) costs less than a Common sells for ($%d)", Tuning.LIQUID_ROLL_COST, Rarity.get("Common").maxValue),
		Tuning.LIQUID_ROLL_COST < Rarity.get("Common").maxValue
	)

	-- PLAN §2 step 1 — the reveal. These are the checks that catch someone "fixing"
	-- the Detector track's weak payoff by widening the radius, which is the one lever
	-- the design says must not move (see the header of Config/Gear).
	local ascending = true
	for tier = 2, Gear.maxTier("Detector") do
		if Gear.tier("Detector", tier).radius <= Gear.tier("Detector", tier - 1).radius then
			ascending = false
		end
	end
	check("§2.1 every detector tier reveals further than the last", ascending)

	-- Revealing is not the same as reaching. If the pull radius ever grows into the
	-- reveal radius, the walk to the glow disappears and the loop is one button.
	check(
		string.format("§2.1 the walk to the glow survives (dig %d vs reveal %d)", Tuning.DIG_RADIUS, Gear.tier("Detector", 1).radius),
		Tuning.DIG_RADIUS * 2 < Gear.tier("Detector", 1).radius
	)

	local field = Stages.builtIds()[1]
	if field then
		local walk = Gear.tier("Boots", 1).walkSpeed
		local lo = Gear.tier("Detector", 1).radius
		local hi = Gear.tier("Detector", Gear.maxTier("Detector")).radius
		local slow = Stages.secondsBetweenContacts(field, lo, walk, Tuning.SIGNALS_PER_STAGE)
		local fast = Stages.secondsBetweenContacts(field, hi, walk, Tuning.SIGNALS_PER_STAGE)
		-- BANDS RE-FITTED TO THE UNIFORM-LENGTH PASS (Config/Stages header). Every
		-- stage is now 400 x 240 = 96,000 studs, so at SIGNALS_PER_STAGE = 90 the
		-- starting detector turns up a contact roughly every 2s of walking and a
		-- maxed one almost continuously. Denser than the old targets (3-12s / >=2s),
		-- and that is the accepted cost of uniform stages with no dead walking -- so
		-- the floors came down rather than the geometry being bent to hold them. What
		-- did NOT move: this must still be a WALK, not a stand-still (slow floor > 0),
		-- and the reveal curve must stay FLAT end to end -- that ratio guard is
		-- area-independent and is the real check against "fixing" the Detector
		-- track's payoff by widening radius (see Config/Gear's header). Move this
		-- band only via SIGNALS_PER_STAGE.
		check(string.format("§2.1 starting detector walks %.1fs between contacts (want 1.2-5)", slow), slow >= 1.2 and slow <= 5)
		check(string.format("§2.1 a maxed detector still has a beat between contacts: %.2fs (want >= 0.4)", fast), fast >= 0.4)
		check(string.format("§2.1 the reveal curve stays flat: %.1fx end to end (want <= 4)", slow / fast), slow / fast <= 4)
	end

	-- PLAN §7 — DENSITY AND THE LOOT TABLES ARE ONE DECISION, NOT TWO.
	--
	-- SIGNALS_PER_STAGE was doubled to 90 so the reveal has something to reveal, and
	-- every weight at Rare and above was halved to cancel that multiplier exactly.
	-- This is the check that catches someone doing only the first half: raise the
	-- density on its own and the field quietly starts holding twice the jackpots,
	-- which is invisible in play until the economy is already ruined.
	--
	-- This assertion is about the STARTER field: Stage 1's own single loot table is
	-- what a new player rolls against. Stages 4, 5 and 6 have their own tables and
	-- are deliberately far richer — the Crater is 18% Legendary on purpose — so
	-- folding them in here would not tighten this check, it would destroy it.
	local function shareAtOrAbove(loot: { [string]: number }, minOrder: number): number
		local total, wanted = 0, 0
		for name, weight in loot do
			total += weight
			if Rarity.get(name).order >= minOrder then
				wanted += weight
			end
		end
		return if total > 0 then wanted / total else 0
	end

	local rarePlus = Tuning.SIGNALS_PER_STAGE * shareAtOrAbove(Stages.get(1).loot, 4) -- Rare and up
	check(
		string.format("§7 the field holds %.1f Rare-or-better signals (want 1.8-3.0, Stage 1's own table)", rarePlus),
		rarePlus >= 1.8 and rarePlus <= 3.0
	)

	-- ...and the flip side: the extra signals have to be junk, or "more items" just
	-- means "more of everything" with extra steps.
	local plentiful = 1 - shareAtOrAbove(Stages.get(1).loot, 3) -- Scrap + Common
	check(
		string.format("§2.1 stage 1 is mostly Scrap/Common: %.0f%% (want >= 70)", plentiful * 100),
		plentiful >= 0.70
	)

	-- PLAN §3.5 — no stage is gated by anything except arithmetic
	for _, stage in Stages.DEFS do
		check(string.format("§3.5 stage %d has no unlock field", stage.id), (stage :: any).locked == nil and (stage :: any).requiresGamepass == nil)
	end

	table.insert(lines, string.format("\n%d passed, %d failed", passed, failed))
	print(table.concat(lines, "\n"))
	return failed == 0
end

return Spec
