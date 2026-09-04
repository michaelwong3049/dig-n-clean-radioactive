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
local Weight = require(Config.Weight)
local ItemModels = require(script.Parent.Parent.ItemModels)
local ToolModels = require(script.Parent.Parent.ToolModels)
local ToolTiers = require(Config.ToolTiers)
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
		-- `odds` DRIVES THE ROLL now (weight = 1/odds), so a zero or missing one is a
		-- divide-by-zero in Items.effectiveWeight, not just a bad "1 in 0" on the HUD.
		check(`item has a positive odds: {item.id}`, type(item.odds) == "number" and item.odds >= 1)
		-- `weight` (kg) feeds five curves in Config/Weight; a nil or out-of-band value
		-- degrades as silently as a bad model key. Weight.norm clamps, so out-of-band
		-- would not throw -- it would just quietly saturate a curve.
		check(
			`item weight is in Weight.MIN..MAX: {item.id}`,
			type(item.weight) == "number" and item.weight >= Weight.MIN and item.weight <= Weight.MAX
		)
	end

	-- Config/Weight — the five curves and the one U-shaped bias. These pin the shape,
	-- not the exact endpoints: "heavier is bigger / harder / worth more", and "weight
	-- never makes an item COMMONER" (rollBias <= 1), and the middle of the range is
	-- untouched (rollBias == 1) so a mid-weight catalogue is exactly as #61 tuned it.
	do
		local mono = true
		local prev = { s = -1, a = -1, p = -1, v = -1 }
		for i = 0, 40 do
			local kg = Weight.MIN * (Weight.MAX / Weight.MIN) ^ (i / 40)
			local s, a, p, v = Weight.sizeScale(kg), Weight.auraScale(kg), Weight.pullFactor(kg), Weight.valueMult(kg)
			if s < prev.s - 1e-9 or a < prev.a - 1e-9 or p < prev.p - 1e-9 or v < prev.v - 1e-9 then
				mono = false
			end
			prev = { s = s, a = a, p = p, v = v }
			if Weight.rollBias(kg) > 1 + 1e-9 then
				mono = false
			end
		end
		check("§weight sizeScale/auraScale/pullFactor/valueMult all rise with mass; rollBias never exceeds 1", mono)

		local mid = math.sqrt(Weight.MIN * Weight.MAX) -- geometric middle == norm 0.5
		check("§weight the mid of the range is roll-unbiased (rollBias == 1)", math.abs(Weight.rollBias(mid) - 1) < 1e-6)
		check("§weight the feather end is a touch rarer, not commoner", Weight.rollBias(Weight.MIN) < 1 and Weight.rollBias(Weight.MIN) >= 0.75)
		check("§weight the heavy end is buried deep but still rolls", Weight.rollBias(Weight.MAX) < 0.5 and Weight.rollBias(Weight.MAX) > 0.15)
		check("§weight heaviest item's valueMult stays sane (<= 2.0, like a modifier)", Weight.valueMult(Weight.MAX) <= 2.0)

		-- Weight and rarity are orthogonal by design, but a genuinely HEAVY find should
		-- also be scarce, or the physical slog and the payoff come apart. Pin the
		-- heaviest catalogue item to Rare or better.
		local heaviest = Items.DEFS[1]
		for _, item in Items.DEFS do
			if item.weight > heaviest.weight then
				heaviest = item
			end
		end
		check(
			string.format("§weight the heaviest item (%s, %gkg) is Rare or better", heaviest.id, heaviest.weight),
			Rarity.get(heaviest.rarity).order >= Rarity.get("Rare").order
		)
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
	check("§9.2 Steady Hands adds exactly +1 potency", stats.cleanPotency == Gear.tier("Cleaner", 4).power + 1)
	check("§9.2 level 20 = 20% resist", math.abs(stats.levelResist - 0.20) < 1e-9)
	check("§9.2 level 20 = +4 carry capacity", stats.capacity == Gear.tier("Suit", 3).capacity + 4)
	check("§9.2 Sure Footing halves the haul penalty", math.abs(stats.haulPenalty - Gear.tier("Boots", 2).haulPenalty * 0.5) < 1e-9)
	check("§5.1 a full bag physically slows you", StatResolver.effectiveWalkSpeed(stats, stats.capacity, false) < stats.walkSpeed)
	check("§5.1 but never immobilises you", StatResolver.effectiveWalkSpeed(stats, 999, false) >= 6)

	-- The liquid folds into effectivePotency and NOWHERE ELSE. `cleanPotency` is the
	-- permanent capability the Locker and the hose shop both read; the day someone
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

	-- ── The wash pad (Config/Liquids, Config/Gear's luckMultiplier/luckPrice) ──────
	--
	-- THE ONE THAT MATTERS MOST IS THE POTENCY CAP. Liquids lend potency on top of
	-- the Cleaner track, and the Cleaner track is PLAN §2 step 4's second hard gate —
	-- the thing that makes the Quarantine Locker fill and the hose shop sell.
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

	-- ── The hose ladder (Config/Gear.Cleaner, Config/ToolTiers, ToolModels/Hose) ──
	--
	-- THREE TABLES DESCRIBE ONE LADDER and nothing but these checks stops them
	-- diverging. Gear.Cleaner is the rungs (price, power, volume), ToolTiers is
	-- their palette, ToolModels/Hose is their geometry. Every one of the three clamps
	-- an out-of-range tier rather than erroring — which is right for a live server and
	-- exactly why a mismatch is invisible in play: add an eighth rung to Gear and the
	-- shop sells it, takes the money, and hands you the seventh hose forever.
	local cleanerRungs = Gear.maxTier("Cleaner")
	check(
		string.format("the hose ladder has one look per rung (%d rungs, %d looks)", cleanerRungs, ToolTiers.count("Cleaner")),
		ToolTiers.count("Cleaner") == cleanerRungs
	)
	check(
		string.format("the hose ladder has one model per rung (%d rungs, %d forms)", cleanerRungs, ToolModels.Hose.count()),
		ToolModels.Hose.count() == cleanerRungs
	)

	-- ToolTiers' own header says "names mirror Gear.lua exactly; if they ever disagree,
	-- Gear.lua wins". That was a comment for six years and a rule for none of them.
	for tier = 1, cleanerRungs do
		local rung, look = Gear.tier("Cleaner", tier), ToolTiers.get("Cleaner", tier)
		check(`hose {tier} agrees on its name: "{rung.name}" / "{look.name}"`, rung.name == look.name)
	end

	-- CarryService.hoseNameFor WALKS THIS TABLE IN ORDER and returns the first rung
	-- that reaches a hardness, so ascending `power` is not a nicety — a table sorted
	-- any other way makes "needs the Chem Injector" name the wrong hose, and it names
	-- it confidently. Ascending price is the same promise made to the shop rack.
	--
	-- ASCENDING VOLUME IS THE NEWER HALF, and it is checked for a reason that only
	-- exists now that the hose is a machine you look at: WashController scales the
	-- stream's girth off `volume` (WashService.push sends it), so a rung whose volume
	-- went DOWN would visibly dribble harder than the rung below it while costing more.
	-- Volume gates nothing, which is exactly why nothing else would catch it.
	for tier = 2, cleanerRungs do
		local prev, this = Gear.tier("Cleaner", tier - 1), Gear.tier("Cleaner", tier)
		check(`hose {tier} costs more than {tier - 1}`, this.price > prev.price)
		check(`hose {tier} reaches further than {tier - 1}`, this.power > prev.power)
		check(`hose {tier} throws more water than {tier - 1}`, this.volume > prev.volume)
	end

	-- THE HOSE ON THE MAST IS THE ONE THE LADDER SELLS. build/Plots parks the station's
	-- monitor at STATION_TIER for a plot nobody owns yet, and ExhibitService swaps it to
	-- the owner's rung from the same factory — so a STATION_TIER off the end of the
	-- ladder would silently clamp and an unclaimed plot would show a hose that is not
	-- for sale anywhere.
	check(
		`the station's parked hose is a real rung (tier {ToolModels.Hose.STATION_TIER})`,
		ToolModels.Hose.STATION_TIER >= 1 and ToolModels.Hose.STATION_TIER <= cleanerRungs
	)

	-- The starting hose plus the best possible roll must still hit a wall inside the
	-- catalogue, or the Cleaner track is decorative for a lucky player. Named off the
	-- table rather than hardcoded to "Garden Hose": the ladder has been renamed once
	-- already (it was Wire Brush -> Plasma Scour before the seven hoses), and a check
	-- whose MESSAGE goes stale while its assertion still passes is a check nobody
	-- trusts the second time they read it.
	local startingHose = Gear.tier("Cleaner", 1)
	local startingReach = startingHose.power + Liquids.MAX_POTENCY_BONUS
	check(
		string.format("§2.4 %s + the best liquid reaches hardness %d, short of Epic (%d)", startingHose.name, startingReach, Rarity.get("Epic").hardness),
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
	-- entry would make buying Luck actively harmful — invisible in play until someone
	-- well into the button notices they stopped seeing Stardust.
	--
	-- LUCK HAS NO CEILING ANY MORE (Config/Gear.luau's header) — every purchase is a
	-- flat +0.1x forever, at a compounding price. 8.0x is not a real cap; it is the
	-- old seven-tier ladder's top rung, kept here as a fixed, well-understood
	-- reference point so the invariants below (and the numbers in their own
	-- descriptions, like "16.1%" and "20.4x") keep meaning the same thing across a
	-- refactor of how a player actually GETS there.
	local luckFloor = Gear.luckMultiplier(1)
	local luckCeiling = 8.0
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

	-- THE FLOOR NEVER DISAPPEARS. A roll you can predict is not a roll; if pushing
	-- luck this far ever drops the commonest liquid under ~10% the pad has become a
	-- vending machine and the reveal animation is lying about there being a moment.
	local commonest = Liquids.ORDER[2]
	check(
		string.format("§6 the common end survives luck %.1fx: %s at %.1f%% (want >= 10%%)", luckCeiling, Liquids.get(commonest).name, oddsHi[commonest] * 100),
		oddsHi[commonest] >= 0.10
	)

	-- ...and the jackpot has to visibly move, or the button reads as a tax.
	local jackpot = Liquids.ORDER[#Liquids.ORDER]
	check(
		string.format("§6 luck %.1fx multiplies the jackpot %.1fx (want >= 5x)", luckCeiling, oddsHi[jackpot] / oddsLo[jackpot]),
		oddsHi[jackpot] / oddsLo[jackpot] >= 5
	)

	-- EVERY PURCHASE MUST BE BOTH LUCKIER AND PRICIER THAN THE LAST, forever — the
	-- one invariant a fixed ladder used to guarantee by construction and a formula
	-- has to be checked instead. 200 purchases is arbitrary and large: a formula that
	-- breaks monotonicity does so either immediately or via a slow float-precision
	-- drift, and 200 steps is enough runway to catch either.
	local luckAscending = true
	for level = 2, 200 do
		if Gear.luckMultiplier(level) <= Gear.luckMultiplier(level - 1) or Gear.luckPrice(level) <= Gear.luckPrice(level - 1) then
			luckAscending = false
		end
	end
	check("§6 every luck purchase is both luckier and pricier than the last", luckAscending)

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

	-- `luck` replaced `maxRarity`. Tier 1 must be exactly 1.0 -- Config/Items.luckBias
	-- treats <=1 as "no bias", so a Bent Coil rolls the raw per-stage distribution --
	-- and every tier above must buy strictly more of it.
	check("§2.1 the starting detector has luck 1.0 (no dig bias)", Gear.tier("Detector", 1).luck == 1.0)
	local luckAsc = true
	for tier = 2, Gear.maxTier("Detector") do
		if Gear.tier("Detector", tier).luck <= Gear.tier("Detector", tier - 1).luck then
			luckAsc = false
		end
	end
	check("§2.1 every detector tier is luckier than the last", luckAsc)

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
		-- BANDS RE-FITTED TO THE UNIFORM-LENGTH PASS (Config/Stages header), then left
		-- alone through three footprint moves because the numbers stayed inside them.
		-- Every stage is 290 x 170 = 49,300 studs; SIGNALS_PER_STAGE is 75, so
		-- `area / N` = 657.33 -- the starting detector turns up a contact about every
		-- 1.3s of walking (slow) and a maxed one about every 0.48s (fast). Denser than
		-- the old targets (3-12s / >=2s) and denser again with each footprint shrink
		-- that held N; that is the accepted cost of small stages with the signal count
		-- left alone. The 240 -> 200 width pass held `area / N` so slow and fast did
		-- not move; the 15% pass dropped it to 0.7225x and the length pass to 0.853x
		-- again, so both came down by those factors. `slow` is now ~1.26 against the
		-- 1.2 floor -- the length pass was the last free one; a fourth shrink needs N
		-- to drop with it (and see §7 -- below ~69 the per-stage rarityTilt moves too).
		-- What must NEVER move: this stays a WALK not a stand-still (slow floor > 0), and the
		-- reveal curve stays FLAT end to end -- that ratio guard is area-independent
		-- and is the real check against "fixing" the Detector track's payoff by
		-- widening radius (see Config/Gear's header). Retarget via SIGNALS_PER_STAGE.
		check(string.format("§2.1 starting detector walks %.1fs between contacts (want 1.2-5)", slow), slow >= 1.2 and slow <= 5)
		check(string.format("§2.1 a maxed detector still has a beat between contacts: %.2fs (want >= 0.4)", fast), fast >= 0.4)
		check(string.format("§2.1 the reveal curve stays flat: %.1fx end to end (want <= 4)", slow / fast), slow / fast <= 4)
	end

	-- PLAN §Step 2 — THE PULL IS A MASH, AND `draw` IS WHAT KEEPS IT PLAYABLE.
	--
	-- Every check below is a restatement of one number: the clicks per second a tier
	-- needs just to HOLD an item where it is,
	--     (PULL_DRAG_RATE - draw) / (PULL_YANK_PER_CLICK * pullSpeed)
	-- which is the thing a player actually experiences when they buy a magnet. It is
	-- worth pinning rather than eyeballing because it falls out of FOUR numbers spread
	-- across two files, and moving any one of them silently moves it.
	local function clicksToHold(tier: number): number
		local magnet = Gear.tier("Magnet", tier)
		return (Tuning.PULL_DRAG_RATE - magnet.draw) / (Tuning.PULL_YANK_PER_CLICK * magnet.pullSpeed)
	end

	-- Same number, but with the soil OUTCLASSING the magnet by `deficit` stages:
	-- DigService bends both magnet terms (yank + draw) by Tuning.PULL_GRIP_FALLOFF ^
	-- deficit and leaves the drag alone, so clicks-to-hold climbs steeply.
	local function holdAtDeficit(tier: number, deficit: number): number
		local magnet = Gear.tier("Magnet", tier)
		local e = Tuning.PULL_GRIP_FALLOFF ^ deficit
		return (Tuning.PULL_DRAG_RATE - magnet.draw * e) / (Tuning.PULL_YANK_PER_CLICK * magnet.pullSpeed * e)
	end

	do
		local starting = clicksToHold(1)
		check(
			string.format("§Step2 the starting magnet is a real mash but a mashable one: %.2f clicks/sec (want 2-3.5)", starting),
			starting >= 2 and starting <= 3.5
		)

		-- THE MOBILE CHECK, and the most load-bearing line in this block. PLAN §Step 2
		-- is explicit that the pull must never be balanced around desktop mash rate,
		-- because doing so quietly locks half the Roblox audience out of deep stages —
		-- and a mash is exactly the mechanic most likely to drift that way under
		-- "make tier 1 feel weightier" pressure. `draw` is the promise that it will
		-- not, and this is where the promise is kept: by the mid magnet the answer has
		-- to be about one click every two seconds, which is comfortable on a phone.
		local mid = math.ceil(Gear.maxTier("Magnet") / 2) + 1
		check(
			string.format("§Step2 a mid magnet (%s) is comfortable on a phone: %.2f clicks/sec (want <= 1)", Gear.tier("Magnet", mid).name, clicksToHold(mid)),
			clicksToHold(mid) <= 1
		)

		local easing = true
		for tier = 2, Gear.maxTier("Magnet") do
			if clicksToHold(tier) >= clicksToHold(tier - 1) then
				easing = false
			end
		end
		check("§Step2 every magnet tier asks for fewer clicks than the last", easing)

		-- The pull must stay a BEAT, not a tap, AND never a chore. The worst case is the
		-- deepest rarity carried by the HEAVIEST catalogue item (Config/Weight.pullFactor
		-- multiplies `required` in DigService) against the best magnet. If even that is
		-- instant the mash has stopped mattering; if it runs past ~15s the weight curve
		-- has turned a haul into homework.
		local heaviestKg = Items.DEFS[1].weight
		for _, item in Items.DEFS do
			heaviestKg = math.max(heaviestKg, item.weight)
		end
		local deepest = (Tuning.DIG_DEPTH_BASE + (#Rarity.ORDER - 1) * Tuning.DIG_DEPTH_PER_RARITY)
			* Weight.pullFactor(heaviestKg)
		local best = Gear.tier("Magnet", Gear.maxTier("Magnet"))
		local netPerSecond = 4 * Tuning.PULL_YANK_PER_CLICK * best.pullSpeed - (Tuning.PULL_DRAG_RATE - best.draw)
		local fastest = (Tuning.PULL_SECONDS_PER_STUD * deepest) / netPerSecond
		check(
			string.format("§Step2 the heaviest deep item takes %.1fs at 4 clicks/sec with the best magnet (want 2-15)", fastest),
			fastest >= 2 and fastest <= 15
		)

		-- The home-turf Common ease (Config/Tuning.PULL_HOME_COMMON_EASE) shortens
		-- `required` for Common items pulled on soil the magnet is rated for. Its two
		-- conditions -- Common-only, gripDeficit == 0 -- are code properties in
		-- DigService (Config sees neither the roll nor the soil), so what this pins is
		-- the one thing Config owns: the size of the cut. A real break, but not so deep
		-- the floor of the catalogue stops being a mash.
		check(
			string.format("§Step2 the home-turf Common ease is a real cut, not a giveaway: %.2fx (want 0.55-0.8)", Tuning.PULL_HOME_COMMON_EASE),
			Tuning.PULL_HOME_COMMON_EASE >= 0.55 and Tuning.PULL_HOME_COMMON_EASE < 0.8
		)
	end

	-- PLAN §Step 2 continued — maxGrip IS NOT A WALL ANY MORE, IT IS A STEEP GRIND.
	--
	-- Soil past a magnet's maxGrip used to clamp the haul at a quarter and paint
	-- "MAGNET TOO WEAK". Now it scales the pull down by Tuning.PULL_GRIP_FALLOFF per
	-- stage of deficit, with no clamp. These pin the shape the user asked for: one
	-- stage over is a grind you can still win, two lurches then sinks, three is
	-- unwinnable -- and a better magnet always rescues what the tier below cannot.
	do
		local cap = Tuning.PULL_YANK_SUSTAINED_CPS -- the click rate a strong human sustains
		local start = Gear.tier("Magnet", 1)

		-- Deficit 0 has to be the untouched pull, or every check above stops describing
		-- the game: gripEff is exactly 1 when the magnet is rated for its soil.
		check(
			"§Step2 a magnet rated for its soil pulls exactly as before (no penalty at deficit 0)",
			holdAtDeficit(1, 0) == clicksToHold(1)
		)

		-- Every stage the soil gains on the magnet costs strictly more mash.
		check(
			"§Step2 each stage over tier is strictly harder to hold than the last",
			holdAtDeficit(1, 0) < holdAtDeficit(1, 1)
				and holdAtDeficit(1, 1) < holdAtDeficit(1, 2)
				and holdAtDeficit(1, 2) < holdAtDeficit(1, 3)
		)

		-- +1: past the starting magnet's own mash band (Spec pins that at <= 3.5 above),
		-- but a strong masher still out-pulls the drag, so the item does come free.
		local overByOne = holdAtDeficit(1, 1)
		check(
			string.format("§Step2 one stage over tier is a grind you can still win: %.2f clicks/sec (want 3.5-%.0f)", overByOne, cap),
			overByOne > 3.5 and overByOne <= cap
		)

		-- +2: past what a human sustains. The opening token-bucket burst still lurches it
		-- upward, then it sinks -- "almost impossible", deliberately not "impossible".
		check(
			string.format("§Step2 two stages over tier cannot be sustained: %.2f clicks/sec (want > %.0f)", holdAtDeficit(1, 2), cap),
			holdAtDeficit(1, 2) > cap
		)

		-- +3: the wall enforces itself. Flat out at the sustained cap, the starting
		-- magnet's net progress is still negative -- it can only sink.
		local e3 = Tuning.PULL_GRIP_FALLOFF ^ 3
		local netAtCap = cap * Tuning.PULL_YANK_PER_CLICK * start.pullSpeed * e3
			- (Tuning.PULL_DRAG_RATE - start.draw * e3)
		check(
			string.format("§Step2 three stages over tier is unwinnable: %.3f net pull-sec/sec at the mash cap (want < 0)", netAtCap),
			netAtCap < 0
		)

		-- The whole point of the redesign: one tier up the magnet track rescues an
		-- over-tier soil the tier below cannot hold at all.
		check(
			"§Step2 a better magnet claws out an over-tier soil the tier below cannot",
			holdAtDeficit(2, 2) < holdAtDeficit(1, 2)
		)
	end

	-- PLAN §7 — DENSITY AND RARITY ARE ONE DECISION, NOT TWO.
	--
	-- The old per-rarity `loot` weight tables are gone: the dig roll walks a stage's
	-- stocked items weighted by 1/odds (Config/Items), and one scalar per stage --
	-- Stages.rarityTilt -- shapes the rarity curve on top. SIGNALS_PER_STAGE (75) times
	-- the Rare+ share is the count of jackpots buried in the starter field, and that
	-- product is the number this pins: raise the density on its own, or nudge the tilt,
	-- and the field quietly starts holding more jackpots -- invisible in play until the
	-- economy is already ruined. Band is ~1.9 at the solved Stage 1 tilt (see
	-- Config/Stages' header); a fourth footprint shrink that drops N below ~69 needs the
	-- tilt to move with it to hold this.
	--
	-- STARTER FIELD ONLY. This is what a new player, tier-1 detector, rolls against.
	-- Stages 4-6 are deliberately far richer (Config/Stages) -- folding them in would
	-- destroy the check, not tighten it.
	local function shareAtOrAbove(stageId: number, minOrder: number): number
		local wanted = 0
		for name, share in Items.rarityWeights(stageId, Stages.get(stageId).rarityTilt) do
			if Rarity.get(name).order >= minOrder then
				wanted += share -- rarityWeights already sums to 1
			end
		end
		return wanted
	end

	local rarePlus = Tuning.SIGNALS_PER_STAGE * shareAtOrAbove(1, 4) -- Rare and up
	check(
		string.format("§7 the starter field holds %.1f Rare-or-better signals at a tier-1 detector (want 1.7-3.0)", rarePlus),
		rarePlus >= 1.7 and rarePlus <= 3.0
	)

	-- ...and the flip side: the rest have to be junk, or "more items" just means "more
	-- of everything".
	local plentiful = 1 - shareAtOrAbove(1, 3) -- Scrap + Common
	check(
		string.format("§2.1 stage 1 is mostly Scrap/Common: %.0f%% (want >= 70)", plentiful * 100),
		plentiful >= 0.70
	)

	-- Every built, stocked stage must actually hand out an item -- rollItem returns nil
	-- only for a stage Config/Items forgot entirely, which should spawn no signals and
	-- warn, never crash. Rarer-only luck must also never invert the ladder: pushing
	-- detector luck up can only raise a stage's Rare+ share, never drop it, and no
	-- rarity may overtake a rarer one (the property Config/Liquids pins for the pad).
	local topLuck = Gear.tier("Detector", Gear.maxTier("Detector")).luck
	for _, id in Stages.builtIds() do
		local tilt = Stages.get(id).rarityTilt
		check(string.format("§7 stage %d rolls a stocked item", id), Items.rollItem(id, tilt, 1) ~= nil)

		local base = Items.rarityWeights(id, tilt)
		local lucky: { [string]: number } = {}
		for itemId, p in Items.rollWeights(id, tilt, topLuck) do
			local r = Items.get(itemId).rarity
			lucky[r] = (lucky[r] or 0) + p
		end

		local baseRarePlus, luckyRarePlus = 0, 0
		local noInversion = true
		local prevBase, prevLucky = 0, 0
		for _, name in Rarity.ORDER do
			local b, l = base[name] or 0, lucky[name] or 0
			if Rarity.get(name).order >= 4 then
				baseRarePlus += b
				luckyRarePlus += l
			end
			-- ratio to the previous rung must not fall as luck rises (only meaningful
			-- where both rungs are actually stocked)
			if b > 0 and l > 0 and prevBase > 0 and prevLucky > 0 then
				if (l / prevLucky) < (b / prevBase) - 1e-9 then
					noInversion = false
				end
			end
			if b > 0 then
				prevBase, prevLucky = b, l
			end
		end
		check(string.format("§7 stage %d: detector luck only raises Rare+ share", id), luckyRarePlus >= baseRarePlus - 1e-9)
		check(string.format("§7 stage %d: detector luck never inverts the rarity ladder", id), noInversion)
	end

	-- PLAN §3.5 — no stage is gated by anything except arithmetic
	for _, stage in Stages.DEFS do
		check(string.format("§3.5 stage %d has no unlock field", stage.id), (stage :: any).locked == nil and (stage :: any).requiresGamepass == nil)
	end

	table.insert(lines, string.format("\n%d passed, %d failed", passed, failed))
	print(table.concat(lines, "\n"))
	return failed == 0
end

return Spec
