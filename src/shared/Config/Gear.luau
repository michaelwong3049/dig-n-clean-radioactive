--!strict
--[[
	Gear.lua — the seven upgrade tracks (PLAN §6) plus exhibit slots.

	ECONOMY RESCALE (feat/economy-rescale-display-income): every `price` below and
	`LUCK_START_PRICE` were multiplied by 20/3 (~6.667x) and rounded to two significant
	figures -- the same factor applied to item baseValues in Config/Items and the rarity
	bands in Config/Rarity, so "sell N finds to afford this tier" is unchanged. Only the
	stat columns (radius, tolerance, pullSpeed, price ratios in comments) are untouched.
	See Config/Rarity.luau's header for why displayYield alone moved differently.

	SUIT NUMBERS ARE FITTED, NOT GUESSED.
	`reduction` and `tolerance` were solved so the model in Shared/Radiation.lua
	reproduces the design's stated intent. Table below regenerated via
	Shared/Util/TuningReport after four radiation-harshening passes today
	(Tuning.BURN_COEF 2.0 -> 3.0 -> 6.0, Stage 1's deepRads 1.25 -> 1.8 -> 1.97,
	Cloth Wrap's `reduction` 0.9000 -> 0.6296) — all figures below are at each
	stage's ENTRANCE (depthFrac=0); the deep edge of every stage is meaningfully
	worse, see Stages.radsAt/Stages.DEFS. Stage 1's deepRads specifically governs
	its OWN far edge (NOT the separate, distant Stage 3 "Fallout Fields" its old
	sub-band naming used to resemble) — see Stages.luau's Stage 1 comment for that
	story:

	                     Z1      Z2      Z3      Z4      Z5      Z6
	  Cloth Wrap        9:00    17s      5s       2s  instant  instant
	  Rubber Suit        inf     inf     12s      3s  instant  instant
	  Lead-Lined         inf     inf     inf     12s  instant  instant
	  Reinforced Hazmat  inf     inf     inf     inf     12s  instant
	  Sealed Exo-Suit    inf     inf     inf     inf     inf     12s
	  Containment Rig    inf     inf     inf   10:00    3:45    1:30

	STAGE 1's CLOTH WRAP CELL IS NOT "inf" ANY MORE, AND IT DID NOT MOVE VIA BURN.
	Stage 1's ambient (0.5) is still below Cloth Wrap's tolerance (1.0) -- it never
	enters the burn/white-screen track at all, by design (Stage 1's rated suit tier IS
	the starting tier, and Spec still requires SOME stage to be a true no-pressure
	tutorial space). The 9:00 instead comes entirely from lowering Cloth Wrap's own
	`reduction` (0.9000 -> 0.6296), which only touches the EXPOSURE/green-screen track
	-- raising Stage 1's ambient far enough to trigger burn at exactly 9 minutes would
	have required an ambient value within about 0.02 rads/sec of Cloth Wrap's exact
	tolerance, a razor-thin, un-maintainable number given how steeply burn responds to
	`excess`. Lowering `reduction` instead needed no such precision and is provably
	isolated to Stage 1: every other stage already burns Cloth Wrap long before its
	exposure meter would matter, so `reduction` is inert everywhere else for this tier.

	Three properties that matter fall out of that table:
	  * ONE TIER UNDER is ~12s in every stage (was ~35s originally, ~23s after the
	    second pass). That is the Dive (§3.5), now considerably tighter -- a kept
	    side effect of the BURN_COEF raise, not something asked for on its own --
	    see Tuning.luau's BURN_COEF comment.
	  * TWO TIERS UNDER is instant almost everywhere now. A suicide sprint, more
	    punishing than ever.
	  * Even a full Containment Rig gets 1:30 in the Crater — §4's "timed heist",
	    preserved by giving the Rig a deliberately imperfect reduction rather than
	    a special-case rule. Unaffected by either COEF change: this scenario is
	    exposure-bound, not burn-bound.

	Regenerate this table with Shared/Util/TuningReport after ANY change here.
]]

export type GearTier = {
	name: string,
	price: number,
	[string]: any,
}

local Gear = {}

-- `luck` REPLACED `maxRarity`. The old field was a hard CEILING -- a signal rarer than
-- the tier's cap was invisible and un-pullable, even from inside its glow. It is gone:
-- rarity is now probabilistic. `luck` feeds Config/Items.luckBias, which multiplies the
-- weight of Rare-and-above items in the dig roll (capped, "rarer-only") -- so a better
-- detector does not unlock the top of the catalogue, it tilts the odds toward it. Tier
-- 1 is exactly 1.0 (no bias -- a Bent Coil rolls the raw per-stage distribution). This
-- is DIG luck only; the wash pad's luck (the Luck button + gamepass, Gear.luckMultiplier)
-- is a separate number and this does not touch it.
--
-- What still gates the deep/rare end for a weak detector: `depth` vs signal burial
-- depth, the magnet's maxGrip vs stage soil hardness, and the radiation itself.
--
-- `radius` IS THE REVEAL RANGE, NOT A SENSING RANGE. Every registerable signal inside
-- it surfaces an aura at its exact spot (DigService, "the reveal"). It used to mean
-- "how far away the needle still points at something", which is why the old curve ran
-- 12 -> 65: a direction hint stays readable at any range, so the top end could be huge
-- for free. A REVEAL at 65 studs lights up most of a stage at once and there is no
-- game left in it, so the curve is now a flat +3 per tier.
--
-- What that costs, stated plainly so nobody re-derives it in six months: max-tier
-- reveal AREA is 6.8x tier 1, where the old curve was 29x. The Detector track is
-- therefore a much weaker purchase than its price ladder implies. If that ladder needs
-- to feel earned again, move the value into luck/depth/clarity -- they do not flatten.
-- Do NOT fix it by widening `radius`.
Gear.Detector = {
	{ name = "Bent Coil", price = 0, radius = 13, luck = 1.00, depth = 6, clarity = 0 },
	{ name = "Scavenger MkI", price = 800, radius = 16, luck = 1.12, depth = 9, clarity = 0 },
	{ name = "Surplus Geiger", price = 1900, radius = 19, luck = 1.25, depth = 12, clarity = 1 },
	{ name = "Pulse Array", price = 4700, radius = 22, luck = 1.40, depth = 16, clarity = 1 },
	{ name = "Isotope Scanner", price = 11000, radius = 25, luck = 1.60, depth = 21, clarity = 2 },
	{ name = "Resonance Mapper", price = 27000, radius = 28, luck = 1.85, depth = 27, clarity = 2 },
	{ name = "Deep Core Array", price = 64000, radius = 31, luck = 2.15, depth = 34, clarity = 3 },
	{ name = "The Oracle", price = 150000, radius = 34, luck = 2.50, depth = 44, clarity = 3 },
}

-- The extraction track. You do not dig — you drop a magnet and haul the thing up
-- through the soil, because what survives out here is metal and anything the fallout
-- soaked. Same slot in the six tracks the shovel used to hold, same price curve.
--
-- THE PULL IS A MASH. Every click is a yank; the soil drags the item back down between
-- them (Tuning.PULL_DRAG_RATE). These two stats are the two halves of that fight, and
-- they are deliberately different KINDS of upgrade:
--
-- pullSpeed: what one yank is worth. The speed stat -- the one a player feels on the
--            first click after buying, because the same item now takes half as many.
-- draw     : passive lift between yanks, in the same units as the drag. This is the
--            COMFORT stat and it is what the top of the track actually sells. At tier 1
--            it is zero, so the ground takes back everything the instant you slow down;
--            near the top it nearly cancels the drag, which turns frantic mashing into
--            steady, unhurried clicking (PLAN §Step 2, "it sells you your hand back").
-- maxGrip  : the toughest ground it can rip something out of, vs Stages.soilHardness.
--            Under-rated magnets do not fail with a message — they lift the item a
--            little way and stall, in view, which sells the upgrade by itself.
--
-- The trailing column is what falls out of pullSpeed and draw together: the clicks per
-- second needed just to HOLD an item still. It is the number that decides whether a
-- tier is playable, so it is worth keeping written down next to the inputs -- and
-- MOBILE LIVES ON IT. PLAN §Step 2 is explicit that the pull must never be balanced
-- around desktop mash rate, and `draw` is the lever that keeps that promise: by the
-- Winch Coil the answer is about one click every two seconds, which is comfortable on
-- a phone. Spec pins that tier specifically. If you retune draw, re-run it.
Gear.Magnet = {
	{ name = "Horseshoe Magnet", price = 0, pullSpeed = 1.0, draw = 0.00, maxGrip = 1 }, -- 2.50 clicks/sec to hold
	{ name = "Salvage Magnet", price = 670, pullSpeed = 1.3, draw = 0.12, maxGrip = 2 }, -- 1.62
	{ name = "Electromagnet", price = 1600, pullSpeed = 1.7, draw = 0.25, maxGrip = 3 }, -- 0.98
	{ name = "Winch Coil", price = 3900, pullSpeed = 2.2, draw = 0.40, maxGrip = 4 }, -- 0.53  <- the mobile target
	{ name = "Rail Coil", price = 9300, pullSpeed = 2.9, draw = 0.55, maxGrip = 5 }, -- 0.23
	{ name = "Singularity Coil", price = 22000, pullSpeed = 3.8, draw = 0.70, maxGrip = 6 }, -- 0.04, effectively hands-free
}

Gear.Cleaner = {
	{ name = "Wire Brush", price = 0, potency = 1, scrubRate = 1.0 },
	{ name = "Acid Sponge", price = 1000, potency = 2, scrubRate = 1.2 },
	{ name = "Pressure Washer", price = 2400, potency = 3, scrubRate = 1.5 },
	{ name = "Chem Bath", price = 5800, potency = 4, scrubRate = 1.9 },
	{ name = "Ultrasonic Rig", price = 14000, potency = 5, scrubRate = 2.4 },
	{ name = "Ion Shower", price = 33000, potency = 6, scrubRate = 3.0 },
	{ name = "Plasma Scour", price = 80000, potency = 7, scrubRate = 3.8 },
}

-- reduction: fraction of AMBIENT rads/sec removed  (exposure track, green screen)
-- tolerance: ambient rads/sec the suit handles before it fails (burn track, white screen)
-- capacity : hot items carried before it gets unmanageable (PLAN §3.4)
--
-- Cloth Wrap's reduction dropped 0.9000 -> 0.6296 in the third harshening pass, SOLELY
-- to hit an explicit Stage 1 target (unsuited survival capped at 9 minutes, was ~33
-- minutes) without touching Stage 1's ambient rate itself -- see this file's header.
Gear.Suit = {
	{ name = "Cloth Wrap", price = 0, reduction = 0.6296, tolerance = 1.0, capacity = 4 },
	{ name = "Rubber Suit", price = 3000, reduction = 0.9750, tolerance = 4.4, capacity = 6 },
	{ name = "Lead-Lined", price = 7200, reduction = 0.9920, tolerance = 13.4, capacity = 8 },
	{ name = "Reinforced Hazmat", price = 17000, reduction = 0.9970, tolerance = 38.4, capacity = 11 },
	{ name = "Sealed Exo-Suit", price = 42000, reduction = 0.9988, tolerance = 98.4, capacity = 15 },
	{ name = "Containment Rig", price = 100000, reduction = 0.9889, tolerance = 105.0, capacity = 20 },
}

-- PLAN §5.2: boots are the most economically dangerous track in the game.
-- Priced on a steeper ~2.8x curve than everything else, deliberately.
--
-- Every tier's walkSpeed +4 on request ("base speed is too slow"): 16->20 for the
-- starting tier, same +4 straight up the ladder so the relative gaps between tiers
-- (and their haulPenalty/stamina pairing) are untouched -- only the floor moved.
-- Then +3 more, same deal: whole ladder shifts up together (20->23 at the floor),
-- gaps and pairings still untouched.
-- This used to be inert data: nothing set Humanoid.WalkSpeed from it at all outside
-- the /speed debug command (see DebugService.luau). ExposureService's per-tick loop
-- now applies StatResolver.effectiveWalkSpeed live, so this table finally means
-- something in actual play, not just in Spec's math.
Gear.Boots = {
	{ name = "Taped Boots", price = 0, walkSpeed = 23, haulPenalty = 1.20, stamina = 4, canVault = false, canDash = false },
	{ name = "Tread Boots", price = 2300, walkSpeed = 25, haulPenalty = 1.00, stamina = 5, canVault = false, canDash = false },
	{ name = "Field Runners", price = 6500, walkSpeed = 27, haulPenalty = 0.80, stamina = 6, canVault = true, canDash = false },
	{ name = "Servo Braces", price = 18000, walkSpeed = 29, haulPenalty = 0.55, stamina = 7, canVault = true, canDash = false },
	{ name = "Powered Frame", price = 51000, walkSpeed = 31, haulPenalty = 0.30, stamina = 8, canVault = true, canDash = true },
	{ name = "Strider Rig", price = 140000, walkSpeed = 33, haulPenalty = 0.10, stamina = 10, canVault = true, canDash = true },
}

-- The satchel does two jobs, and the second one matters more than PLAN §3.7 realised:
--   fuseMult  — multiplies the decay clock's fuse length. 1.25 = 20% slower decay.
--   shielding — fraction of CARRIED emission blocked. The suit shields you from the
--               world; the satchel shields you from your own loot. Without this the
--               greed dial (§3.3) stops working the moment you buy a decent suit,
--               because suit reduction would erase your backpack too.
--
-- PLAN §3.7: this line SLOWS the clock, it never stops it. Keep fuseMult finite, and
-- keep shielding under 1.0 forever — a bag that fully shields is a bag with no greed.
Gear.Satchel = {
	{ name = "Canvas Bag", price = 0, fuseMult = 1.00, shielding = 0.00 },
	{ name = "Lined Pack", price = 4000, fuseMult = 1.25, shielding = 0.25 },
	{ name = "Lead Satchel", price = 9600, fuseMult = 1.61, shielding = 0.45 },
	{ name = "Shielded Case", price = 23000, fuseMult = 2.17, shielding = 0.62 },
	{ name = "Containment Pack", price = 55000, fuseMult = 3.12, shielding = 0.78 },
}

-- THE SEVENTH TRACK, AND THE ONLY ONE THAT BUYS NOTHING YOU HOLD, AND THE ONLY ONE
-- WITH NO TOP RUNG. Luck does exactly one thing: it bends the liquid roll at the wash
-- pad (Config/Liquids) toward the top of the table. It has no radius, no tolerance,
-- no speed — the number IS the odds.
--
-- USED TO BE A SEVEN-RUNG LADDER OF NAMED CHARMS (Rusty Horseshoe -> Shooting Star).
-- It is now a button: every purchase is +LUCK_STEP flat, forever, at a price that
-- climbs LUCK_PRICE_GROWTH per purchase — no names, no ceiling, because the button
-- has nothing to paint a ladder ON. `level` is a 1-based purchase count (1 = never
-- bought, matching every other track's "tier 1 is the free starting rung"
-- convention) so DataService's TEMPLATE.gear.luck default of 1 needed no migration.
--
-- `luckMultiplier` is the base of the exponent in Liquids.effectiveWeight, so its
-- effect on any given liquid's odds is legible from Liquids.luau's own odds table
-- rather than from anything here.
--
-- COMPOUNDING PRICE, FLAT GAIN — the opposite shape from every tiered track, where
-- gain grows AND price grows. Luck is self-limiting already (a good roll only ever
-- hands out `charges`, a fixed handful of patches, never a permanent capability), so
-- there is no need for the gain itself to taper — the compounding price is what
-- keeps one more click from ever being free.
Gear.LUCK_STEP = 0.1
Gear.LUCK_START_PRICE = 670 -- economy rescale: 100 * 20/3, same factor as every tiered price
Gear.LUCK_PRICE_GROWTH = 1.10

--- The multiplier a player sits at after `level - 1` purchases (level 1 = 1.0x,
--- never bought). Matches Liquids.oddsAt's `luck` parameter exactly.
function Gear.luckMultiplier(level: number): number
	return 1.0 + Gear.LUCK_STEP * (math.max(level, 1) - 1)
end

--- What the NEXT purchase costs, given the buyer is currently at `level`.
--- Rounded to the dollar — Liquids.effectiveWeight never sees this number, only
--- luckMultiplier does, so rounding it costs nothing in the roll math.
function Gear.luckPrice(level: number): number
	return math.floor(Gear.LUCK_START_PRICE * Gear.LUCK_PRICE_GROWTH ^ (math.max(level, 1) - 1) + 0.5)
end

Gear.SPRINT_MULTIPLIER = 1.35

-- LUCK IS NOT HERE. It has no tiers to iterate, no `Gear.tier("Luck", n)` to call,
-- and no per-track shop counter or SellsTrack-generic sell path to require one — see
-- ShopService.buyLuck and the header above Gear.luckMultiplier for the replacement.
--
-- NEITHER IS A PEDESTAL PRICE. All 8 exhibit stands are free from the start
-- (Tuning.EXHIBIT_MAX_SLOTS); the cash-bought slot track and its `pedestalPrice`
-- curve were cut with it.
Gear.TRACKS = { "Detector", "Magnet", "Cleaner", "Suit", "Boots", "Satchel" }

--- Track name (capitalised, as used here and in the world's StationId attribute)
--- to profile field (lowercase, as used in DataService's TEMPLATE.gear).
---
--- This mapping used to live as a 3-entry local inside ToolService, covering only
--- the tracks that have held models. The shop needs all six, and two copies of a
--- translation table is how you end up writing data.gear.Detector alongside
--- data.gear.detector and losing a purchase. One table, here, next to the data.
Gear.PROFILE_KEY = {
	Detector = "detector",
	Magnet = "magnet",
	Cleaner = "cleaner",
	Suit = "suit",
	Boots = "boots",
	Satchel = "satchel",
}

function Gear.profileKey(track: string): string
	local key = Gear.PROFILE_KEY[track]
	assert(key, `unknown gear track "{track}"`)
	return key
end

function Gear.tier(track: string, index: number): GearTier
	local list = (Gear :: any)[track]
	assert(list, `unknown gear track "{track}"`)
	local t = list[math.clamp(index, 1, #list)]
	return t
end

function Gear.maxTier(track: string): number
	return #((Gear :: any)[track])
end

return Gear
