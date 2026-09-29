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
	of one nuke are not quite the same bomb. Everything is indexed 1..Rarity.MAX_STARS.
]]

local Bombing = {}

-- Health taken at ground zero, falling to Config/Detonation.BLAST_EDGE of it at the
-- rim. Base health is 100 and every aura tier adds 50 (Tuning.maxHealthFor), so a
-- 1-star bomb chips a fresh player while an 8-star one flattens anyone short of the
-- top auras.
Bombing.DAMAGE = { 30, 45, 65, 90, 120, 160, 210, 280 }
-- Blast radius in studs.
Bombing.RADIUS = { 10, 12, 14, 17, 20, 24, 28, 34 }

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

-- Seconds from the drop to the bang: a per-uid roll between these. Bigger stars burn
-- a little longer (FUSE_PER_STAR), so the nastiest bombs are the easiest to run from.
Bombing.FUSE_MIN = 2.5
Bombing.FUSE_MAX = 4.5
Bombing.FUSE_PER_STAR = 0.15

-- Seconds before you can drop another bomb, 8-10 on request: 1 star = COOLDOWN_MIN,
-- 8 stars = COOLDOWN_MAX, plus a little per-uid jitter, then clamped back into range.
Bombing.COOLDOWN_MIN = 8
Bombing.COOLDOWN_MAX = 10
Bombing.COOLDOWN_JITTER = 0.4

-- The crater a bomb leaves is a short flash-burn, not a dig nuke's minute-long orb.
Bombing.ORB_RADIUS = 0.5 -- x the blast radius
Bombing.ORB_BURN = 0.12 -- health/sec, x DAMAGE
Bombing.ORB_LIFE = 6

-- Where the bomb lands: this far in front of the player, dropped onto the ground.
Bombing.DROP_AHEAD = 3
-- Most bombs a player can have lit at once, in case the cooldown is ever tuned down.
Bombing.MAX_LIVE = 2

return Bombing
