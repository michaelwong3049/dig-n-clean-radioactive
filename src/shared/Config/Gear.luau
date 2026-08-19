--!strict
--[[
	Gear.lua — the six upgrade tracks (PLAN §6) plus exhibit slots.

	SUIT NUMBERS ARE FITTED, NOT GUESSED.
	`reduction` and `tolerance` were solved so the model in Shared/Radiation.lua
	reproduces the design's stated intent:

	                     Z1      Z2      Z3      Z4      Z5      Z6
	  Cloth Wrap         inf     50s     15s      7s      3s   instant
	  Rubber Suit        inf     inf     35s      9s      3s   instant
	  Lead-Lined         inf     inf     inf     35s      4s   instant
	  Reinforced Hazmat  inf     inf     inf     inf     35s      2s
	  Sealed Exo-Suit    inf     inf     inf     inf     inf     35s
	  Containment Rig    inf     inf     inf   10:00    3:45    1:30

	Three properties that matter fall out of that table:
	  * ONE TIER UNDER is ~35s in every zone. That is one dig. That is the Dive (§3.5).
	  * TWO TIERS UNDER is 2-9s. A suicide sprint, exactly as intended.
	  * Even a full Containment Rig gets 1:30 in the Crater — §4's "timed heist",
	    preserved by giving the Rig a deliberately imperfect reduction rather than
	    a special-case rule.

	Regenerate this table with Shared/Util/TuningReport after ANY change here.
]]

export type GearTier = {
	name: string,
	price: number,
	[string]: any,
}

local Gear = {}

-- PLAN §5 wording note: the design calls this a "sensitivity floor", but the behaviour
-- described (a Bent Coil physically cannot see a Reactor Core) is a CEILING on rarity.
-- Named for the behaviour, not the doc.
Gear.Detector = {
	{ name = "Bent Coil", price = 0, radius = 12, maxRarity = 3, depth = 6, clarity = 0 },
	{ name = "Scavenger MkI", price = 120, radius = 16, maxRarity = 4, depth = 9, clarity = 0 },
	{ name = "Surplus Geiger", price = 290, radius = 21, maxRarity = 5, depth = 12, clarity = 1 },
	{ name = "Pulse Array", price = 700, radius = 27, maxRarity = 5, depth = 16, clarity = 1 },
	{ name = "Isotope Scanner", price = 1680, radius = 34, maxRarity = 6, depth = 21, clarity = 2 },
	{ name = "Resonance Mapper", price = 4030, radius = 42, maxRarity = 7, depth = 27, clarity = 2 },
	{ name = "Deep Core Array", price = 9670, radius = 52, maxRarity = 8, depth = 34, clarity = 3 },
	{ name = "The Oracle", price = 23200, radius = 65, maxRarity = 8, depth = 44, clarity = 3 },
}

-- The extraction track. You do not dig — you drop a magnet and haul the thing up
-- through the soil, because what survives out here is metal and anything the fallout
-- soaked. Same slot in the six tracks the shovel used to hold, same price curve.
--
-- pullSpeed: how fast it hauls (was digSpeed)
-- maxGrip  : the toughest ground it can rip something out of, vs Zones.soilHardness.
--            Under-rated magnets do not fail with a message — they lift the item a
--            little way and stall, in view, which sells the upgrade by itself.
Gear.Magnet = {
	{ name = "Horseshoe Magnet", price = 0, pullSpeed = 1.0, maxGrip = 1 },
	{ name = "Salvage Magnet", price = 100, pullSpeed = 1.3, maxGrip = 2 },
	{ name = "Electromagnet", price = 240, pullSpeed = 1.7, maxGrip = 3 },
	{ name = "Winch Coil", price = 580, pullSpeed = 2.2, maxGrip = 4 },
	{ name = "Rail Coil", price = 1390, pullSpeed = 2.9, maxGrip = 5 },
	{ name = "Singularity Coil", price = 3340, pullSpeed = 3.8, maxGrip = 6 },
}

Gear.Cleaner = {
	{ name = "Wire Brush", price = 0, potency = 1, scrubRate = 1.0 },
	{ name = "Acid Sponge", price = 150, potency = 2, scrubRate = 1.2 },
	{ name = "Pressure Washer", price = 360, potency = 3, scrubRate = 1.5 },
	{ name = "Chem Bath", price = 865, potency = 4, scrubRate = 1.9 },
	{ name = "Ultrasonic Rig", price = 2075, potency = 5, scrubRate = 2.4 },
	{ name = "Ion Shower", price = 4980, potency = 6, scrubRate = 3.0 },
	{ name = "Plasma Scour", price = 11950, potency = 7, scrubRate = 3.8 },
}

-- reduction: fraction of AMBIENT rads/sec removed  (exposure track, green screen)
-- tolerance: ambient rads/sec the suit handles before it fails (burn track, white screen)
-- capacity : hot items carried before it gets unmanageable (PLAN §3.4)
Gear.Suit = {
	{ name = "Cloth Wrap", price = 0, reduction = 0.9000, tolerance = 1.0, capacity = 4 },
	{ name = "Rubber Suit", price = 450, reduction = 0.9750, tolerance = 4.4, capacity = 6 },
	{ name = "Lead-Lined", price = 1080, reduction = 0.9920, tolerance = 13.4, capacity = 8 },
	{ name = "Reinforced Hazmat", price = 2600, reduction = 0.9970, tolerance = 38.4, capacity = 11 },
	{ name = "Sealed Exo-Suit", price = 6240, reduction = 0.9988, tolerance = 98.4, capacity = 15 },
	{ name = "Containment Rig", price = 14980, reduction = 0.9889, tolerance = 105.0, capacity = 20 },
}

-- PLAN §5.2: boots are the most economically dangerous track in the game.
-- Priced on a steeper ~2.8x curve than everything else, deliberately.
Gear.Boots = {
	{ name = "Taped Boots", price = 0, walkSpeed = 16, haulPenalty = 1.20, stamina = 4, canVault = false, canDash = false },
	{ name = "Tread Boots", price = 350, walkSpeed = 18, haulPenalty = 1.00, stamina = 5, canVault = false, canDash = false },
	{ name = "Field Runners", price = 980, walkSpeed = 20, haulPenalty = 0.80, stamina = 6, canVault = true, canDash = false },
	{ name = "Servo Braces", price = 2740, walkSpeed = 22, haulPenalty = 0.55, stamina = 7, canVault = true, canDash = false },
	{ name = "Powered Frame", price = 7670, walkSpeed = 24, haulPenalty = 0.30, stamina = 8, canVault = true, canDash = true },
	{ name = "Strider Rig", price = 21480, walkSpeed = 26, haulPenalty = 0.10, stamina = 10, canVault = true, canDash = true },
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
	{ name = "Lined Pack", price = 600, fuseMult = 1.25, shielding = 0.25 },
	{ name = "Lead Satchel", price = 1440, fuseMult = 1.61, shielding = 0.45 },
	{ name = "Shielded Case", price = 3460, fuseMult = 2.17, shielding = 0.62 },
	{ name = "Containment Pack", price = 8300, fuseMult = 3.12, shielding = 0.78 },
}

Gear.SPRINT_MULTIPLIER = 1.35

-- The endgame money sink (PLAN §8.5). Index = slot number being bought.
function Gear.pedestalPrice(nextSlot: number): number
	return math.floor(900 * (1.28 ^ (nextSlot - 3)))
end

Gear.TRACKS = { "Detector", "Magnet", "Cleaner", "Suit", "Boots", "Satchel" }

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
