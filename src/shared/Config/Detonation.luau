--!strict
--[[
	Detonation.luau — the pull fuse, and what a nuke leaves behind when it runs out.

	Config/ RULE (Tuning.luau's header): data only, no game logic, no requires of
	anything outside Config/. This file requires nothing. The maths that reads it is
	Shared/Detonation, required by the server (DigService, HazardService) AND the
	client (the haul panel, DetonationController) for the same reason Radiation and
	Decay are shared: the fuse the player watches and the fuse the server blows up on
	have to be one piece of arithmetic.

	THE RULE, AS THE PLAYER MEETS IT. Locking the magnet onto a buried nuke lights its
	fuse. Let go before ARM_AT of the window and you walk away free. Hang on past it
	and the nuke is ARMED: the release stops working, and it either comes out of the
	ground in the time that is left or it goes off where it lies. What it leaves is a
	scorched crater with a glowing orb of hot air over it that burns the health off
	anyone standing inside -- bigger, hotter and longer-lived the rarer and bigger the
	nuke was.

	THE FUSE LIVES ON THE NUKE, NOT ON THE HAUL. Letting go does not reset it; it cools
	back down at COOL_RATE times the speed it heated up. Without that, "let go at 79%
	and grab it again" hands out a fresh window every time and the rule is decoration.
	It also means a nuke somebody else has been working on is still warm when you get
	there -- and its spot says so (DetonationController).
]]

local Detonation = {}

-- ── The fuse ───────────────────────────────────────────────────────────

-- The window in seconds for an average nuke at Uncommon, before rarity and weight
-- bend it. "About thirty seconds" is the brief; everything below is a nudge off it.
Detonation.BASE_WINDOW = 30

-- RARER NUKES ARE LESS STABLE. Multiplies BASE_WINDOW. Monotonic non-increasing down
-- Rarity.ORDER (Spec pins it): the find worth the most is the one with the shortest
-- fuse, which is the same inversion the decay clock makes (PLAN §3.6) on purpose.
Detonation.RARITY_WINDOW = {
	Scrap = 1.10,
	Common = 1.10,
	Uncommon = 1.00,
	Rare = 0.94,
	Epic = 0.90,
	Legendary = 0.84,
	Mythic = 0.80,
	Anomaly = 0.74,
}

-- BIGGER NUKES TAKE LONGER TO PULL, SO THEY GET LONGER. The window is multiplied by
-- (Weight.pullFactor(kg) / Weight.pullFactor(WEIGHT_REF_KG)) ^ WEIGHT_WINDOW_EXP -- the
-- same factor that lengthens the mash itself (DigService `required`), taken RELATIVE
-- to a typical nuke so a typical nuke gets BASE_WINDOW exactly, and softened so a
-- buried safe is not handed the whole of its extra rope back as free time. 0 would
-- ignore weight entirely; 1 would scale the window exactly as hard as the pull.
-- WEIGHT_REF_KG is the catalogue's median weight (1 kg); a feather-light nuke comes in
-- ~25% under BASE_WINDOW, the heaviest ~35% over.
Detonation.WEIGHT_WINDOW_EXP = 0.5
Detonation.WEIGHT_REF_KG = 1

-- The point of no return, as a fraction of the window. Before it the release is free;
-- at it the nuke arms and the release stops working (DigService's lock handler).
Detonation.ARM_AT = 0.8

-- Where the fuse starts TELLING you -- the haul panel's bar warms, the "let go" hint
-- lights up and the nuke's spot starts ticking. Well before ARM_AT so there is time to
-- read it and still decide.
Detonation.WARN_AT = 0.5

-- ── The fairness floor ──────────────────────────────────────────────────
--
-- A flat thirty seconds blows up honest pulls. The starting magnet has no draw, and a
-- Rare dug out of Stage 1 is a 25-40s mash with it -- longer than its whole window --
-- so a new player's first good find would go off in their hands for no fault of
-- their own. The window therefore has a FLOOR: long enough that the magnet RATED for
-- this soil, clicked at a relaxed REF_CPS, has the nuke out of the ground by SAFE_AT
-- of the window. Most pulls never touch the floor (the rarity/weight window is longer
-- already); it only lifts the slow deep ones.
--
-- The floor is sized off the STAGE's rated magnet, never the player's own. A better
-- magnet is simply safer; an under-rated one pulling over its tier is slower than the
-- floor assumed and can run the fuse down -- over-tier pulls were already a grind
-- (Tuning.PULL_GRIP_FALLOFF) and are now a gamble as well, which is the intent.
Detonation.REF_CPS = 4 -- clicks/sec: relaxed desktop, a busy thumb on a phone
Detonation.SAFE_AT = 0.6 -- the rated pull has to land by this fraction of the window

-- How fast an unheld fuse cools, as a multiple of the rate it heated. 1 = it takes as
-- long to settle as you spent on it. Above 1 starts to reopen the let-go-and-regrab
-- reset described in the header; Spec holds it at <= 1.
Detonation.COOL_RATE = 1.0

-- ── The blast and the crater ─────────────────────────────────────────────
--
-- Per rarity, for an AVERAGE-sized nuke (see SIZE_* for how size bends the radii):
--   hit        health taken off anyone at ground zero, once, the moment it goes off.
--              Falls to BLAST_EDGE of that at the rim of the blast.
--   orbRadius  studs. The glowing orb of hot air left over the crater.
--   orbBurn    health/sec at the orb's centre. Falls to ORB_EDGE of that at its rim.
--   orbLife    seconds the orb hangs there before it has fully dissipated.
--
-- MAX_HEALTH is 100 (Config/Tuning), so these are percentages of a body. A Common's
-- crater is a bruise you walk out of; a Mythic's or an Anomaly's at point blank is a
-- blackout even running straight out (Spec pins the Common end).
Detonation.BLAST = {
	Scrap = { hit = 25, orbRadius = 8, orbBurn = 10, orbLife = 30 },
	Common = { hit = 25, orbRadius = 8, orbBurn = 10, orbLife = 30 },
	Uncommon = { hit = 30, orbRadius = 10, orbBurn = 14, orbLife = 40 },
	Rare = { hit = 40, orbRadius = 13, orbBurn = 20, orbLife = 45 },
	Epic = { hit = 50, orbRadius = 16, orbBurn = 28, orbLife = 50 },
	Legendary = { hit = 60, orbRadius = 20, orbBurn = 38, orbLife = 60 },
	Mythic = { hit = 75, orbRadius = 25, orbBurn = 50, orbLife = 75 },
	Anomaly = { hit = 90, orbRadius = 32, orbBurn = 65, orbLife = 90 },
}

-- The blast reaches a little past the orb it leaves: blastRadius = orbRadius * this.
-- Standing just outside the orb still gets you knocked flat.
Detonation.BLAST_REACH = 1.3
Detonation.BLAST_EDGE = 0.4 -- fraction of `hit` taken at the blast's rim
Detonation.ORB_EDGE = 0.35 -- fraction of `orbBurn` at the orb's rim

-- The orb holds its full size and heat for this fraction of its life, then shrinks
-- and cools linearly to nothing. The radius shrinks WITH the heat, so the edge the
-- player can see is the edge that burns.
Detonation.ORB_FADE_FROM = 0.8

-- HOW BIG IT LOOKED. A nuke's visual scale is Weight.sizeScale * the item's sizeMult *
-- this dig's Payload roll -- the same product the haul lump is :ScaleTo'd by. The blast
-- and orb radii are multiplied by (scale / SIZE_REF) ^ SIZE_EXP, clamped. SIZE_REF is
-- about where an ordinary dig lands, so the BLAST table above reads as "a normal one".
-- Clamped hard because Payload's 2.5x jackpot on a 3x-weight item is a 7.5x model,
-- and a crater that swallows a third of a stage is not a hazard, it is a closure.
Detonation.SIZE_REF = 1.5
Detonation.SIZE_EXP = 0.5
Detonation.SIZE_MIN = 0.75
Detonation.SIZE_MAX = 1.5

-- Knockback at ground zero, in studs/sec, falling off linearly to nothing at the
-- blast's rim. Applied by each client to its OWN character (it owns the physics).
Detonation.KNOCKBACK_SPEED = 70
Detonation.KNOCKBACK_LIFT = 45
Detonation.KNOCKBACK_SECONDS = 0.8 -- how long you are off your feet

-- ── Instances ─────────────────────────────────────────────────────────
--
-- Here rather than in the services because the client has to find them too and cannot
-- require anything out of ServerScriptService (same reason Tuning.AURA_TAG lives in
-- Config).

-- Workspace folder holding one marker part per live crater. The marker carries the
-- crater's attributes; every visual on it is built client-side (DetonationController).
Detonation.FOLDER = "Craters"

-- Tag on anything whose nuke has a lit fuse: the aura spot ("spot") and the haul lump
-- climbing out of the ground ("lump"). Attributes ride on the tagged instance.
Detonation.HOT_TAG = "FuseHot"
Detonation.ATTR_HEAT = "FuseHeat" -- 0..1, quantised
Detonation.ATTR_ARMED = "FuseArmed"
Detonation.ATTR_BLOWS_AT = "FuseBlowsAt" -- Workspace:GetServerTimeNow() it goes off, once armed
Detonation.ATTR_ROLE = "FuseRole" -- "spot" | "lump"

return Detonation
