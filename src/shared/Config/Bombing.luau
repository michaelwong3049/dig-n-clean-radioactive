--!strict
--[[
	Config/Bombing.luau — every number for dropping a clean nuke as a bomb.

	Hold a CLEANED nuke and press G: it leaves your bag, sits on the ground with a lit
	fuse, and goes off (Services/BombService -> HazardService.detonate). The point is
	to put another player down with it: a bomb death drops their WHOLE bag for anyone
	to grab (ExposureService). Maths in Shared/Bombing, so the hotbar's hover card and
	the server read the same stats.

	STATS COME FROM THE STAR RATING (Rarity.stars: rarity tier nudged by modifier and
	size), then the nuke's own size roll, then a small per-uid variance so two copies
	of one nuke are not quite the same bomb. DAMAGE/RADIUS are read by that rating
	WITHOUT its stage nudge and capped at 8 (Shared/Bombing powerOf): the stage already
	scales the blast, and the rating going to 10 stars left bombs as they were.
]]

local Bombing = {}

-- Health taken at ground zero, falling to Config/Detonation.BLAST_EDGE of it at the
-- rim. Base health is 100 and every aura tier adds 50 (Tuning.maxHealthFor), so a
-- 1-star bomb chips a fresh player while an 8-star one flattens anyone short of the
-- top auras.
Bombing.DAMAGE = { 30, 45, 65, 90, 120, 160, 210, 280 }
-- Blast radius in studs. Buffed ~1.8x (was 10..34): small blasts needed a near-direct hit,
-- now a dropped bomb clears an area. The crater orb (ORB_RADIUS) grows with it.
Bombing.RADIUS = { 18, 22, 26, 31, 37, 44, 52, 62 }

-- The nuke's size roll (Config/Payload, 0.6-2.5) nudges damage and radius. A
-- Payload of 1 is neutral. Kept narrow because size already bumps the STAR rating (so
-- the DAMAGE/RADIUS row it reads from); clamped so a GIGA roll is a bigger bomb, not an
-- automatic kill.
Bombing.SIZE_EXP = 0.35
Bombing.SIZE_MIN = 0.9
Bombing.SIZE_MAX = 1.15

-- Per-uid variance, a multiplier in [1 - VARIANCE, 1 + VARIANCE], rolled separately
-- for damage and radius.
Bombing.VARIANCE = 0.12

-- Seconds from the drop to the bang: an average per rarity (indexed by Rarity order,
-- Scrap..Anomaly), so the rarer the nuke the less time to run. Each copy rolls within
-- FUSE_SPREAD of its rarity's average (per uid), then an OVERSIZED or GIGA size roll
-- (Payload.calloutFor) burns a little longer.
Bombing.FUSE_BY_RARITY = { 3.0, 3.0, 2.8, 2.6, 2.4, 2.2, 2.0, 1.8 }
Bombing.FUSE_SPREAD = 0.2
Bombing.FUSE_SIZE_BONUS = { OVERSIZED = 0.2, GIGA = 0.4 }

-- Seconds before you can drop another bomb, flat for every nuke.
Bombing.COOLDOWN = 3

-- The crater a bomb leaves is a short flash-burn, not a dig nuke's minute-long orb.
Bombing.ORB_RADIUS = 0.5 -- x the blast radius
Bombing.ORB_BURN = 0.12 -- health/sec, x DAMAGE
Bombing.ORB_LIFE = 6

-- Where the bomb lands: this far in front of the player, dropped onto the ground.
Bombing.DROP_AHEAD = 3
-- Most bombs a player can have lit at once, in case the cooldown is ever tuned down.
Bombing.MAX_LIVE = 2

return Bombing
