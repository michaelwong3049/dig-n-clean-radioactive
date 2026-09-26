--!strict
--[[
	Gear.lua — the seven upgrade tracks (PLAN §6) plus exhibit slots.

	ECONOMY RESCALE (feat/economy-rescale-display-income): every `price` below and
	`LUCK_START_PRICE` were multiplied by 20/3 (~6.667x) and rounded to two significant
	figures -- the same factor applied to item baseValues in Config/Items and the rarity
	bands in Config/Rarity, so "sell N finds to afford this tier" is unchanged. Only the
	stat columns (radius, tolerance, pullSpeed, price ratios in comments) are untouched.
	See Config/Rarity.luau's header for why displayYield alone moved differently.

	AURA NUMBERS ARE FITTED, NOT GUESSED.
	`reduction` and `tolerance` were solved so the model in Shared/Radiation.lua
	reproduces the design's stated intent. Table below regenerated via
	Shared/Util/TuningReport after four radiation-harshening passes today
	(Tuning.BURN_COEF 2.0 -> 3.0 -> 6.0, Stage 1's deepRads 1.25 -> 1.8 -> 1.97,
	Faint Glow's `reduction` 0.9000 -> 0.6296) — all figures below are at each
	stage's ENTRANCE (depthFrac=0); the deep edge of every stage is meaningfully
	worse, see Stages.radsAt/Stages.DEFS. Stage 1's deepRads specifically governs
	its OWN far edge (NOT the separate, distant Stage 3 "Fallout Fields" its old
	sub-band naming used to resemble) — see Stages.luau's Stage 1 comment for that
	story:

	                     Z1      Z2      Z3      Z4      Z5      Z6
	  Faint Glow        9:00   ~28s      5s       2s  instant  instant   (Z2 was 17s before tolerance 1.0 -> 1.5)
	  Static Veil        inf     inf     12s      3s  instant  instant
	  Lead Halo         inf     inf     inf     12s  instant  instant
	  Ion Shroud  inf     inf     inf     inf     12s  instant
	  Isotope Mantle    inf     inf     inf     inf     inf     12s
	  Containment Nimbus    inf     inf     inf   10:00    3:45    1:30

	STAGE 1's FAINT GLOW CELL IS NOT "inf" ANY MORE, AND IT DID NOT MOVE VIA BURN.
	Stage 1's ENTRANCE ambient (0.5) is still below Faint Glow's tolerance (1.5) -- the
	entrance never enters the burn/white-screen track at all, by design (Stage 1's rated aura tier IS
	the starting tier, and Spec still requires SOME stage to be a true no-pressure
	tutorial space). The 9:00 instead comes entirely from lowering Faint Glow's own
	`reduction` (0.9000 -> 0.6296), which only touches the EXPOSURE/green-screen track
	-- raising Stage 1's ambient far enough to trigger burn at exactly 9 minutes would
	have required an ambient value within about 0.02 rads/sec of Faint Glow's exact
	tolerance, a razor-thin, un-maintainable number given how steeply burn responds to
	`excess`. Lowering `reduction` instead needed no such precision and is provably
	isolated to Stage 1: every other stage already burns Faint Glow long before its
	exposure meter would matter, so `reduction` is inert everywhere else for this tier.

	Three properties that matter fall out of that table:
	  * ONE TIER UNDER is ~12s in every stage (was ~35s originally, ~23s after the
	    second pass). That is the Dive (§3.5), now considerably tighter -- a kept
	    side effect of the BURN_COEF raise, not something asked for on its own --
	    see Tuning.luau's BURN_COEF comment.
	  * TWO TIERS UNDER is instant almost everywhere now. A suicide sprint, more
	    punishing than ever.
	  * Even a full Containment Nimbus gets 1:30 in the Crater — §4's "timed heist",
	    preserved by giving the Nimbus a deliberately imperfect reduction rather than
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
-- 1 is exactly 1.0 (no bias -- a Rust Bucket rolls the raw per-stage distribution). This
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
-- to feel earned again, move the value into luck/depth -- they do not flatten.
-- Do NOT fix it by widening `radius`.
--
-- `clarity` IS NOW INERT (on request): the ping shows rarity, modifier and the "1 in N"
-- odds on every detector regardless (DigService.hintFor). The column is left here at
-- its old values so a repurpose -- or a re-gate -- does not start from a blank field.
-- PRICE x5 (feat/shop-price-increase): every `price` in this file was multiplied by
-- 5 and rounded to a clean figure -- deliberately NOT paired with an income-side
-- rescale like the 20/3 economy pass (see this file's header). Digging/washing/exhibit
-- payouts are untouched, so the ladder simply takes longer to climb -- the point of
-- the change (game loop was ending too quickly).
--
-- THE RUST BUCKET IS THE FREE RUNG, AND THE BENT COIL IS NOW A $15 ONE (on request,
-- with the new-player tutorial). The tutorial ends on "upgrade your detector", and a
-- first stand pays for a $15 upgrade in seconds (it was $50 until a later request),
-- so the Bent Coil is the first thing a new player buys. Everything above it kept its stats and price and only
-- moved one index up. DataService.shiftDetectorLadder moved old saves up with it,
-- so nobody's paid-for tier became the one below it.
--
-- The Rust Bucket is a little worse than the old starter in every column except luck.
-- The Spec pins luck at exactly 1.0 on tier 1 and requires it to go strictly up after that. The
-- Bent Coil's 1.06 is the smallest step that still reads as a real upgrade. Its radius and
-- depth are the old starter's, so a $15 upgrade restores the old starter exactly and then
-- adds a little luck.
Gear.Detector = {
	{ name = "Rust Bucket", price = 0, radius = 11, luck = 1.00, depth = 5, clarity = 0, blurb = "Found in a ditch. Mostly works." },
	{ name = "Bent Coil", price = 15, radius = 13, luck = 1.06, depth = 6, clarity = 0, blurb = "A coat hanger with ambition." },
	{ name = "Scavenger MkI", price = 4000, radius = 16, luck = 1.12, depth = 9, clarity = 0, blurb = "Wider sweep. Still deaf to anything deep." },
	{ name = "Surplus Geiger", price = 9500, radius = 19, luck = 1.25, depth = 12, clarity = 1, blurb = "Army surplus, and it still clicks true." },
	{ name = "Pulse Array", price = 23500, radius = 22, luck = 1.40, depth = 16, clarity = 1, blurb = "Pulses instead of sweeps. Reaches past rubble." },
	{ name = "Isotope Scanner", price = 55000, radius = 25, luck = 1.60, depth = 21, clarity = 2, blurb = "Sorts isotopes from scrap before you dig." },
	{ name = "Resonance Mapper", price = 135000, radius = 28, luck = 1.85, depth = 27, clarity = 2, blurb = "Maps a whole plot in one slow pass." },
	{ name = "Deep Core Array", price = 320000, radius = 31, luck = 2.15, depth = 34, clarity = 3, blurb = "Hears the core. Ignores everything above it." },
	{ name = "The Oracle", price = 750000, radius = 34, luck = 2.50, depth = 44, clarity = 3, blurb = "Sees the bottom of the map and is bored by it." },
	-- TOXIC TWILIGHT'S SIX. Sold at the Detector stall in that camp and nowhere else
	-- (`camp` below, and Gear.campOf), so a player has to reach the end of Stage 6 to
	-- spend on them. The order is the order they were drawn in, which is the order they
	-- cost.
	--
	-- THE CLIMB IS IN LUCK AND DEPTH, AND `radius` BARELY MOVES, ON PURPOSE. The note above
	-- says why the reveal curve is flat, and the Spec pins a ratio guard on it (top radius
	-- over the Rust Bucket's, <= 4). The Oracle already sits at 3.1x; +1 a rung to 40 is
	-- 3.6x, which is the most this ladder can take before that guard trips. Spec still
	-- needs every rung to reveal further than the last, so it is a whole stud, no more.
	-- Prices keep the ladder's x2.4 stride. Luck steps 0.30 a rung, a touch under the
	-- Oracle's last 0.35. It buys less than it looks like: Items.luckBias caps a weight at
	-- DIG_LUCK_BIAS_CAP (20), and luck^3 (Legendary) reaches that at 2.71 and luck^2 (Epic)
	-- at 4.47, so from the second rung up the extra luck is mostly Rare and Epic weight.
	{ name = "Vein Whisperer", price = 1800000, radius = 35, luck = 2.80, depth = 48, clarity = 3, blurb = "Hums along a vein and tells you where it thickens.", camp = "twilight" },
	{ name = "Aurora Rake", price = 4300000, radius = 36, luck = 3.10, depth = 53, clarity = 3, blurb = "Combs the ground with light. The rare things snag first.", camp = "twilight" },
	{ name = "Strata Lance", price = 10000000, radius = 37, luck = 3.40, depth = 58, clarity = 3, blurb = "One beam through every layer at once.", camp = "twilight" },
	{ name = "Leyline Tap", price = 24000000, radius = 38, luck = 3.70, depth = 64, clarity = 3, blurb = "Drinks from the fault lines. Warm to hold.", camp = "twilight" },
	{ name = "Null Compass", price = 58000000, radius = 39, luck = 4.00, depth = 70, clarity = 3, blurb = "Points at whatever the ground is hiding from you.", camp = "twilight" },
	{ name = "Prime Meridian", price = 140000000, radius = 40, luck = 4.30, depth = 76, clarity = 3, blurb = "Every direction agrees on where the good stuff is.", camp = "twilight" },
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
-- maxGrip  : the soil hardness (Stages.soilHardness) this magnet is RATED for. Past
--            that it is not blocked and not messaged — the pull just scales down by
--            Tuning.PULL_GRIP_FALLOFF per stage of deficit (yank and draw both), which
--            is a brutal grind one stage over, a lurch-then-sink two over, and an
--            unwinnable mash three over. Spec §Step2 pins that curve.
--
-- The trailing column is what falls out of pullSpeed and draw together: the clicks per
-- second needed just to HOLD an item still. It is the number that decides whether a
-- tier is playable, so it is worth keeping written down next to the inputs -- and
-- MOBILE LIVES ON IT. PLAN §Step 2 is explicit that the pull must never be balanced
-- around desktop mash rate, and `draw` is the lever that keeps that promise: by the
-- Winch Coil the answer is about one click every two seconds, which is comfortable on
-- a phone. Spec pins that tier specifically. If you retune draw, re-run it.
Gear.Magnet = {
	{ name = "Horseshoe Magnet", price = 0, pullSpeed = 1.0, draw = 0.00, maxGrip = 1, blurb = "A fridge magnet on a rope. Pull like you mean it." }, -- 2.50 clicks/sec to hold
	{ name = "Salvage Magnet", price = 3350, pullSpeed = 1.3, draw = 0.12, maxGrip = 2, blurb = "Holds its grip between yanks. Barely." }, -- 1.62
	{ name = "Electromagnet", price = 8000, pullSpeed = 1.7, draw = 0.25, maxGrip = 3, blurb = "Wired to a car battery. Lifts while you rest." }, -- 0.98
	{ name = "Winch Coil", price = 19500, pullSpeed = 2.2, draw = 0.40, maxGrip = 4, blurb = "One click every two seconds is enough." }, -- 0.53  <- the mobile target
	{ name = "Rail Coil", price = 46500, pullSpeed = 2.9, draw = 0.55, maxGrip = 5, blurb = "Rails the load up. Your wrist stops arguing." }, -- 0.23
	{ name = "Singularity Coil", price = 110000, pullSpeed = 3.8, draw = 0.70, maxGrip = 6, blurb = "Point it down. It does the rest." }, -- 0.04, effectively hands-free
	-- TOXIC TWILIGHT'S FIVE. Sold at the Magnet stall in that camp and nowhere else
	-- (`camp`, Gear.campOf), like the camp's six detectors. The order is the art pack's
	-- own (its tier_6_lattice .. tier_10_omega), which is the order they cost.
	--
	-- `draw` HAS NOWHERE LEFT TO GO, so the climb is in pullSpeed. The Singularity Coil
	-- already draws 0.70 against a 0.75 drag, and Spec wants every rung to ask for fewer
	-- clicks to hold than the last without draw ever reaching the drag (that would lift
	-- on its own, and the pull stops being a beat), so draw only creeps toward it.
	-- pullSpeed rises ~x1.25 a rung; Spec's "heaviest deep item takes >= 2s at 4 clicks/sec
	-- with the best magnet" is what caps it, and the Omega sits near 3s.
	--
	-- `maxGrip` runs 7-11 AHEAD OF THE MAP: soil hardness stops at 6 today, so it buys
	-- nothing until Stage 7 is built, and it is written down now so those stages have a
	-- ladder to be rated against. Prices keep the Detector ladder's x2.4 stride.
	{ name = "Lattice Magnet", price = 1200000, pullSpeed = 4.8, draw = 0.72, maxGrip = 7, blurb = "A cage of field lines. Nothing slips through it.", camp = "twilight" }, -- 0.021
	{ name = "Solar Magnet", price = 2900000, pullSpeed = 6.0, draw = 0.73, maxGrip = 8, blurb = "Runs hot enough to pull the soil off the soil.", camp = "twilight" }, -- 0.011
	{ name = "Void Magnet", price = 7000000, pullSpeed = 7.4, draw = 0.74, maxGrip = 9, blurb = "Pulls from somewhere past the bottom of the hole.", camp = "twilight" }, -- 0.0045
	{ name = "Nebula Magnet", price = 17000000, pullSpeed = 9.0, draw = 0.745, maxGrip = 10, blurb = "Three fields at once. The ground stops arguing.", camp = "twilight" }, -- 0.0019
	{ name = "Omega Magnet", price = 40000000, pullSpeed = 11.0, draw = 0.748, maxGrip = 11, blurb = "The last magnet. The earth just hands things over.", camp = "twilight" }, -- 0.0006
}

-- THE CLEANING TRACK IS A MACHINE ON YOUR BASE, NOT A THING IN YOUR HAND, and that
-- is the second correction this track has had. First it was seven different nouns
-- (Wire Brush, Acid Sponge, Pressure Washer, Chem Bath, Ultrasonic Rig, Ion Shower,
-- Plasma Scour) while the wash bay welded a fire hose into your fist, so the thing
-- you bought was never the thing you cleaned with. That got fixed by making all
-- seven rungs hoses. This is the other half of the same mistake: a hose is plumbing.
-- It runs from a pump, through a reel, to a nozzle bolted to a mast beside the tub —
-- it is not a sponge you carry into the ash and back. So the tier you own is the
-- MONITOR MOUNTED AT YOUR OWN CLEANSING STATION (build/Plots.buildHoseRig), it swaps
-- the moment you buy a rung (ExhibitService.refreshHose), and nothing is ever put in
-- the player's hands: they stand at the mark and aim the machine.
--
-- YOU STILL BUY IT AT THE PLAZA'S HOSES STALL. The machine is where the purchase
-- LANDS, not where it is made — walking home to find a Chem Injector on your mast is
-- the point, and a shop that sells nothing you can see is the failure this whole
-- change is about, not one it introduces.
--
-- NOT ONE NUMBER MOVED, TWICE OVER. `price` and both stat columns are exactly what
-- they were as the seven nouns and as the seven held hoses; only the column NAMES
-- changed, and they changed to say what the machine does rather than what a sponge
-- did. Config/Liquids' entire +2-cap argument is written against "a Garden Hose is
-- a 1 and Anomaly hardness is 7", and Util/Spec pins tier 1 plus the best possible
-- liquid roll landing short of Epic. This is a re-fit, not a rebalance.
--
-- power : HOW HARD IT CLEANS — the hard gate (PLAN §2 step 4). A patch harder than
--         this never comes off with this machine, ever, and the Quarantine Locker is
--         where those items sit as a labelled advertisement for the next rung. Liquids
--         lend at most +2 on top (Config/Liquids.MAX_POTENCY_BONUS) and are
--         deliberately not allowed to replace it. Resolved into `cleanPotency` by
--         StatResolver, which is still the name the cleaning MATH uses — the gate is
--         one number whether it comes from the machine or from what is in the tank.
-- volume: HOW MUCH WATER IT THROWS. Twice a stat: it is the divisor on
--         Contamination.secondsFor, so a patch you CAN shift comes off faster, and it
--         is what the stream visibly looks like at the bay (WashController scales the
--         jet's girth and its splash by it). A Garden Hose dribbles; a Plasma Lance
--         is a firehose you can hear. Always safe to move — nothing gates on it.
--
-- What each rung looks like is Shared/ToolModels/Hose — real geometry, in git, seven
-- authored silhouettes rather than one base model recoloured. That file is also why
-- ToolTiers.Cleaner's `scale` column is 1.00 all the way down.
Gear.Cleaner = {
	{ name = "Garden Hose", price = 0, power = 1, volume = 1.0, blurb = "A dribble and a prayer." },
	{ name = "Patched Fire Hose", price = 5000, power = 2, volume = 1.2, blurb = "Leaks at every wrap, and still outguns the hose." },
	{ name = "Pressure Lance", price = 12000, power = 3, volume = 1.5, blurb = "Narrow jet. Strips crust, not your patience." },
	{ name = "Chem Injector", price = 29000, power = 4, volume = 1.9, blurb = "Doses the stream. Eats what water cannot." },
	{ name = "Ultrasonic Jet", price = 70000, power = 5, volume = 2.4, blurb = "Shakes the grime loose before it is wet." },
	{ name = "Ion Cannon", price = 165000, power = 6, volume = 3.0, blurb = "Charges the water. The dirt lets go first." },
	{ name = "Plasma Lance", price = 400000, power = 7, volume = 3.8, blurb = "Overkill, mounted on a mast, aimed by you." },
	-- TOXIC TWILIGHT'S FIVE. Sold at that camp's Hose Shop and nowhere else (`camp`,
	-- Gear.campOf), like its detectors and magnets. The order is the user's.
	--
	-- `power` runs 8-12 AHEAD OF THE MAP, the way the camp's magnets' maxGrip does:
	-- crust hardness stops at 7 (Anomaly) today, so the gate buys nothing until harder
	-- crust exists. What these rungs sell NOW is `volume`, the divisor on
	-- Contamination.secondsFor, climbing ~x1.25 a rung so every one still washes
	-- faster than the last. The stream's girth is already capped (WashController's
	-- JET_GIRTH_MAX), so the extra water is speed, not a wall of spray. Prices keep
	-- the other Twilight ladders' x2.4 stride.
	{ name = "Singularity Nozzle", price = 1000000, power = 8, volume = 4.7, blurb = "Folds the stream down to a point. The crust folds with it.", camp = "twilight" },
	{ name = "Cryo Nova", price = 2400000, power = 9, volume = 5.8, blurb = "Freezes the grime, then shatters it off.", camp = "twilight" },
	{ name = "Solar Forge", price = 5800000, power = 10, volume = 7.2, blurb = "Water hot enough to glow. Dirt does not argue.", camp = "twilight" },
	{ name = "Quantum Rift", price = 14000000, power = 11, volume = 8.9, blurb = "Cleans it here and in every other version of here.", camp = "twilight" },
	{ name = "Celestial Deluge", price = 34000000, power = 12, volume = 11.0, blurb = "The last hose. It rains from somewhere higher.", camp = "twilight" },
}

-- reduction  : fraction of AMBIENT rads/sec removed  (exposure track, green screen)
-- tolerance  : ambient rads/sec the aura handles before it fails (burn track, white screen)
-- capacity   : hot items carried before it gets unmanageable (PLAN §3.4)
-- haulPenalty: studs/sec of walk speed lost PER CARRIED ITEM (StatResolver.effectiveWalkSpeed)
--
-- haulPenalty MOVED HERE WITH THE SATCHEL'S RETIREMENT (see the RETIRED block below),
-- and it is the stat that makes capacity a decision rather than a bigger number (PLAN
-- §5.1). Living on the Aura means one purchase buys the room AND the frame to carry
-- it, so the ladder is fitted to keep a FULL BAG'S drag roughly level while the bag
-- grows: 7.2 / 9.5 / 10.1 / 10.4 / 9.1 / 6.8 studs/sec, tier 1 to 6. A bigger aura
-- never makes a full bag feel lighter than a smaller full one did, and never much
-- heavier either; the treadmill is what makes that drag a smaller slice of your speed.
-- Tier 1 (1.20) and tier 6 (0.20) are the Satchel's old ends, so a new player's first
-- haul feels exactly as it did.
--
-- KEEP THE FLOOR ABOVE ZERO. An aura with no haul penalty turns capacity back into a
-- free number, and Spec pins every rung above zero and none heavier than the one below.
--
-- Capacity ladder raised 4/6/8/11/15/20 -> 6/10/14/20/26/34 on request ("start at 6
-- slots, raise the max for the other upgrades"). Past 10 slots the hotbar stops growing
-- and the rest lives in the bag panel (InventoryController, ` key).
--
-- Faint Glow's reduction dropped 0.9000 -> 0.6296 in the third harshening pass, SOLELY
-- to hit an explicit Stage 1 target (unshielded survival capped at 9 minutes, was ~33
-- minutes) without touching Stage 1's ambient rate itself -- see this file's header.
--
-- Faint Glow's tolerance raised 1.0 -> 1.5 on request ("radiation damage kicks in too
-- early for unshielded players"). Stage 1's ambient climbs 0.5 -> 1.97 across its depth,
-- so burn onset moves from ~34% depth to ~68% depth. Deliberately capped at 1.5, not
-- higher: Spec still requires an unshielded player to die within 30s at Stage 1's own
-- deepest point (radsAt 1.97), and 1.5 lands that at ~28s -- 1.6 would break it. The
-- informational Z2-Z6 cells below shift with this (Z2 entrance 17s -> ~28s) but no
-- Spec check pins those.
Gear.Aura = {
	{ name = "Faint Glow", price = 0, reduction = 0.6296, tolerance = 1.5, capacity = 6, haulPenalty = 1.20, blurb = "A flicker of static. Counts as a glow, not a shield." },
	{ name = "Static Veil", price = 15000, reduction = 0.9750, tolerance = 4.4, capacity = 10, haulPenalty = 0.95, blurb = "Crackles more than it shields. Shields a little." },
	{ name = "Lead Halo", price = 36000, reduction = 0.9920, tolerance = 13.4, capacity = 14, haulPenalty = 0.72, blurb = "Hums like a lead apron. Feels safe. Nearly is." },
	{ name = "Ion Shroud", price = 85000, reduction = 0.9970, tolerance = 38.4, capacity = 20, haulPenalty = 0.52, blurb = "Wound tight around you. The first aura that trusts you." },
	{ name = "Isotope Mantle", price = 210000, reduction = 0.9988, tolerance = 98.4, capacity = 26, haulPenalty = 0.35, blurb = "Burns hotter than the air. Walks into the red and back." },
	{ name = "Containment Nimbus", price = 500000, reduction = 0.9889, tolerance = 105.0, capacity = 34, haulPenalty = 0.20, blurb = "Ninety seconds in the Crater. Leakier than it looks." },
}

-- ── RETIRED ───────────────────────────────────────────────────────────────────
--
-- THE BOOTS TRACK NO LONGER EXISTS. It is not in Gear.TRACKS, it has no STAT_META
-- entry, no shop counter and no stall: nothing sells it and nothing reads a stat off
-- it. Speed is TRAINED now, on the treadmill on your own plot — see
-- Config/Treadmill.luau, which owns `walkSpeed` outright and explains why a purchase
-- became a grind.
--
-- WHY THE TABLE IS STILL HERE, when the rule for a retired ITEM is to empty its
-- stages and leave the entry (see Config/Items): DataService's one-time refund prices
-- against this exact `price` column. A returning player is handed back the cash for
-- every rung they actually bought, and it cannot compute that from a table that has
-- been deleted.
--
-- WHERE THE FOUR STATS WENT:
--   walkSpeed    -> Config/Treadmill. The whole feature.
--   haulPenalty  -> Gear.Aura. It went to the Satchel first, and moved on to the
--                   Aura when the Satchel was retired too (see below).
--   stamina      -> nowhere. Verified inert before removal: StatResolver was the only
--   canVault        writer and NOTHING in the game ever read any of the three. Sprint
--   canDash         (Gear.SPRINT_MULTIPLIER) is in the same state — `effectiveWalkSpeed`
--                   takes a `sprinting` flag that no call site has ever passed true.
--                   PLAN §5.1 specced all four; none was ever built.
--
-- The history of the numbers, kept because the treadmill's START_WALK is one of
-- them: every tier's walkSpeed was raised +4, then +3, then +3 again on request
-- ("base speed is too slow", "bump the base walkspeed a bit more"), moving the floor
-- 16 -> 26 while the ladder and its pairings stayed put. That floor of 26 is exactly
-- Treadmill.START_WALK, so an untrained player today walks at the speed a
-- freshly-booted player walked at before any of this changed.
-- These prices got the same x5 PRICE PASS as the live tracks above. They are what a
-- returning player is refunded, so they must not change.
Gear.Boots = {
	{ name = "Taped Boots", price = 0, walkSpeed = 26, haulPenalty = 1.20, stamina = 4, canVault = false, canDash = false, blurb = "Taped at the toe. They hold, mostly." },
	{ name = "Tread Boots", price = 11500, walkSpeed = 28, haulPenalty = 1.00, stamina = 5, canVault = false, canDash = false, blurb = "Real tread. A full load stops dragging you." },
	{ name = "Field Runners", price = 32500, walkSpeed = 30, haulPenalty = 0.80, stamina = 6, canVault = true, canDash = false, blurb = "Light enough to vault a fence." },
	{ name = "Servo Braces", price = 90000, walkSpeed = 32, haulPenalty = 0.55, stamina = 7, canVault = true, canDash = false, blurb = "Braced knees. Carry more, feel less of it." },
	{ name = "Powered Frame", price = 255000, walkSpeed = 34, haulPenalty = 0.30, stamina = 8, canVault = true, canDash = true, blurb = "Powered stride, and a dash when you need it." },
	{ name = "Strider Rig", price = 700000, walkSpeed = 36, haulPenalty = 0.10, stamina = 10, canVault = true, canDash = true, blurb = "Full load, full speed. The haul stops mattering." },
}

-- THE SATCHEL TRACK IS GONE TOO, and unlike Boots it left no table behind: nobody has
-- a save that bought one, so there is nothing to refund and nothing to price against.
-- It sold three columns, and only one of them was ever something a player felt:
--
--   haulPenalty -> Gear.Aura (see its header). The one that mattered: a full bag
--                  on the free Canvas Bag was a 28% slowdown, and nothing else in the
--                  game touched it.
--   fuseMult    -> nowhere. It stretched the decay clock, whose countdown left the
--                  hotbar long ago (InventoryController's header), so a purchase that
--                  only moved an invisible clock was selling nothing you could see.
--                  The decay clock itself is untouched and still runs at 1x.
--   shielding   -> nowhere. Carried emission is now blocked only by level resist,
--                  which is exactly what the free Canvas Bag always gave you. The
--                  aura still does NOT shield your own backpack (Shared/Radiation's
--                  header) -- that rule was never the Satchel's, and it stays.

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
Gear.LUCK_START_PRICE = 3350 -- x5 price pass (feat/shop-price-increase), same factor as every tiered price
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

-- INERT, and kept only so `effectiveWalkSpeed`'s signature does not have to change
-- with the Boots retirement. Sprint was specced in PLAN §5.1 and never built: no call
-- site has ever passed `sprinting = true`. Building it means finding it a stamina
-- number to drain, which no longer exists on any track — see Gear.Boots' header.
Gear.SPRINT_MULTIPLIER = 1.35

-- LUCK IS NOT HERE. It has no tiers to iterate, no `Gear.tier("Luck", n)` to call,
-- and no per-track shop counter or SellsTrack-generic sell path to require one — see
-- ShopService.buyLuck and the header above Gear.luckMultiplier for the replacement.
--
-- NEITHER IS A PEDESTAL PRICE. The ground floor's exhibit stands are free from the
-- start; the cash-bought slot track and its `pedestalPrice` curve were cut with it.
-- More stands now come a floor at a time (Config/Floors), priced there.
--
-- AND NEITHER IS BOOTS, ANY MORE. Dropping it from this list is the whole mechanism
-- of the retirement: the shop's stall row, the generic sell path, the card panel's
-- stat block and Spec's STAT_META coverage check all walk THIS table, so a track that
-- leaves it stops existing everywhere at once with no per-file surgery. Its data is
-- still in the file for the refund (see Gear.Boots). THE SATCHEL LEFT THE SAME WAY,
-- plus its counter at the Outfitter (build/Shops' OUTFITTER.counters).
Gear.TRACKS = { "Detector", "Magnet", "Cleaner", "Aura" }

--- Track name (capitalised, as used here and in the world's StationId attribute)
--- to profile field (lowercase, as used in DataService's TEMPLATE.gear).
---
--- This mapping used to live as a 3-entry local inside ToolService, covering only
--- the tracks that have held models. The shop needs every live track, and two copies
--- of a translation table is how you end up writing data.gear.Detector alongside
--- data.gear.detector and losing a purchase. One table, here, next to the data.
---
--- BOOTS IS STILL IN HERE AND IS NOT IN Gear.TRACKS. That is deliberate and it is the
--- only entry for which the two disagree: this table answers "what does this track
--- call itself in a profile", which the refund in DataService still has to ask about a
--- track nobody can buy. Membership of TRACKS is what decides whether a track is live.
Gear.PROFILE_KEY = {
	Detector = "detector",
	Magnet = "magnet",
	Cleaner = "cleaner",
	Aura = "aura",
	Boots = "boots",
}

function Gear.profileKey(track: string): string
	local key = Gear.PROFILE_KEY[track]
	assert(key, `unknown gear track "{track}"`)
	return key
end

--- WHICH STAT COLUMNS THE SHOP IS ALLOWED TO SELL, AND WHAT TO CALL THEM.
---
--- ShopService used to build a card's stat block by walking the tier table itself and
--- `table.sort`ing the results, which meant three things nobody chose:
---
---   * EVERY numeric column was advertised, including `clarity` — which is INERT (see
---     its note above Gear.Detector: DigService shows rarity and odds on every
---     detector regardless). The shop was charging for a stat that does nothing.
---   * The order was ALPHABETICAL, so "clarity" led every detector card and the stat
---     a player actually buys the track for (radius) came third.
---   * The label was the field name, so an aura sold "reduction 0.997" — a number whose
---     units only make sense if you have read Shared/Radiation.
---
--- `order` fixes all three: it is the exact list, in the exact sequence, that the shop
--- draws for that track. A column left out of it is not sold. `clarity` is left in the
--- Detector tiers (its own note asks for that, so a repurpose does not start blank)
--- but is absent here, which is the whole mechanism for retiring it from the storefront
--- without deleting the data.
---
--- Per-field entries:
---   label          what the card prints. Short, uppercase — these sit in a 62px gutter.
---   kind           "number" (default, draws a bar) or "flag" (a boolean; draws a chip).
---   lowerIsBetter  the bar fills as the number FALLS. Only Aura's haulPenalty,
---                  which is the one column in the game where 0.20 beats 1.20. (It
---                  was Boots' column, then Satchel's, before both were retired.)
---   complement     the bar measures `1 - value`, not the value. Only Aura's
---                  `reduction`, which is the fraction of dose BLOCKED: it sits at
---                  0.63..0.9988 and what actually varies between rungs is the sliver
---                  that gets THROUGH (0.37 down to 0.0012, a 300x spread). Drawn
---                  straight, the bar says a Static Veil is 98% as good as the best
---                  aura in the game, which would sell four upgrades as rounding error.
---   scale = "log"  place the rung on a logarithmic ladder. Also only `reduction`:
---                  leakage is multiplicative (halving it doubles your time in a
---                  stage) and on a linear axis tier 1 is so bad that every other rung
---                  pins to the top.
---
--- The bar's ENDS are not here on purpose: ShopService derives them from that track's
--- own tiers, so retuning a column cannot leave a stale ceiling behind. They are the
--- ladder's min and max rather than zero and max, which matters for every column whose
--- floor is not zero — `luck` starts at 1.00 (no bonus at all), and a bar drawn from
--- zero showed the do-nothing starting detector as 40% full.
---
--- Util/Spec asserts this table covers every column of every tier, so a new stat
--- cannot silently fail to appear in the shop the way `clarity` silently appeared in it.
export type StatMeta = {
	label: string,
	kind: string?,
	lowerIsBetter: boolean?,
	complement: boolean?,
	scale: string?,
}

Gear.STAT_META = {
	Detector = {
		order = { "radius", "depth", "luck" },
		hidden = { clarity = true },
		radius = { label = "RADIUS" },
		depth = { label = "DEPTH" },
		luck = { label = "LUCK" },
	},
	Magnet = {
		order = { "pullSpeed", "draw", "maxGrip" },
		hidden = {},
		pullSpeed = { label = "PULL" },
		draw = { label = "DRAW" },
		maxGrip = { label = "GRIP" },
	},
	Cleaner = {
		order = { "power", "volume" },
		hidden = {},
		power = { label = "POWER" },
		volume = { label = "VOLUME" },
	},
	Aura = {
		order = { "reduction", "tolerance", "capacity", "haulPenalty" },
		hidden = {},
		reduction = { label = "SHIELD", complement = true, scale = "log" },
		tolerance = { label = "TOLERANCE" },
		capacity = { label = "CARRY" },
		-- Right under CARRY because it is the other half of the same question: how
		-- much you can take, then how much taking it slows you. `lowerIsBetter` is
		-- the only use of that flag in the game: 0.20 beats 1.20, and drawn straight
		-- the bar would empty as the aura got better.
		haulPenalty = { label = "HAUL", lowerIsBetter = true },
	},
	-- NO BOOTS OR SATCHEL ENTRY. Both tracks are retired (see the RETIRED block above)
	-- and are not in Gear.TRACKS, which is the table Spec's coverage check and the shop
	-- both walk — so their columns are neither advertised nor asserted over.
}

--- Every column of `track` that is neither sold nor deliberately retired is a bug, and
--- Spec calls this to say so. `name`, `price` and `blurb` are the card's chrome rather
--- than stats, so they are never expected in `order`.
Gear.STAT_CHROME = { name = true, price = true, blurb = true, camp = true }

function Gear.tier(track: string, index: number): GearTier
	local list = (Gear :: any)[track]
	assert(list, `unknown gear track "{track}"`)
	local t = list[math.clamp(index, 1, #list)]
	return t
end

--- The camp whose stall sells this rung. A row with no `camp` is sold at Base Camp,
--- which is every rung of every track but Toxic Twilight's six detectors, five
--- magnets and five hoses. It is a
--- Config/Camps key, spelled the way that file spells it ("base" is Camps.BASE).
---
--- WHERE A RUNG IS SOLD AND WHERE YOU CAN USE IT ARE NOT THE SAME QUESTION. This gates
--- the purchase only (ShopService.buyTier's caller, the stall's rack and card row). What
--- you own you carry anywhere, and can switch to at any stall of the track.
function Gear.campOf(track: string, index: number): string
	return (Gear.tier(track, index) :: any).camp or "base"
end

--- The rungs `camp`'s stall of `track` sells, ascending. Empty when the camp has no
--- stall for the track, which is the case for most track/camp pairs.
function Gear.tiersAt(track: string, camp: string): { number }
	local tiers = {}
	for index = 1, Gear.maxTier(track) do
		if Gear.campOf(track, index) == camp then
			table.insert(tiers, index)
		end
	end
	return tiers
end

function Gear.maxTier(track: string): number
	return #((Gear :: any)[track])
end

return Gear
