--!strict
--[[
	Config/Reforge.luau — every number for the Reforge Station at Toxic Twilight
	(build/ReforgeStation, Services/ReforgeService, client/ReforgePanel).

	PAY CASH, REROLL A WASHED NUKE'S BOMB STATS. Every copy's damage and radius carry a
	small per-copy wobble (Shared/Bombing, Config/Bombing.VARIANCE, +-12%) that used to be
	seeded off the uid and never stored. A reforge rolls a fresh pair and STORES it on
	the record as `forge = { dmg, rad }`, which Shared/Bombing reads in place of the
	seeded wobble from then on. The forge band is wider than the natural one, so a lucky
	reforge makes a better bomb than any copy could be dug as -- that is the point.

	KEEP OR REVERT, ON REQUEST. The new pair is shown next to the old one and the player
	picks; the cash is spent either way. Walking away (or reforging again) without
	picking keeps the OLD pair.

	A RARE QUALITY ON TOP, ON REQUEST. Each paid reforge has QUALITY_CHANCE to add one
	good quality the copy does not already carry (Pristine / Irradiated / Fused, by
	Rarity.MODIFIERS weight). It is a real quality: value, income and stars all move. It
	is applied at once and is NOT undone by REVERT -- it is the jackpot, not a stat roll.

	COST, ON REQUEST: a share of the copy's current sell value that climbs with every
	reforge that copy has had, so rerolling one nuke forever gets expensive.
]]

local Reforge = {}

--- The panel's accent: forge orange, against the reactor's pink.
Reforge.COLOR = Color3.fromHex("FF8A3D")

--- The band a reforged stat lands in, as a multiplier on the base damage/radius. The
--- natural wobble is 0.88..1.12 (Config/Bombing.VARIANCE); a reforge reaches past both
--- ends. SKEW > 1 leans rolls low, so the top of the band stays rare.
Reforge.ROLL_MIN = 0.85
Reforge.ROLL_MAX = 1.35
Reforge.SKEW = 1.6

--- The chance each paid reforge adds a quality, and the ones it can add (best first,
--- Merge.MODIFIER_RANK's order). Odds between them follow Rarity.MODIFIERS weights.
Reforge.QUALITY_CHANCE = 0.03
Reforge.QUALITIES = { "Pristine", "Irradiated", "Fused" }

--- Price: COST_SHARE of the copy's sell value, +COST_STEP of that per reforge it has
--- already had, never under COST_MIN.
Reforge.COST_SHARE = 1.0
Reforge.COST_STEP = 0.25
Reforge.COST_MIN = 1000

--- One reforge per player per this many seconds: the anvil's strike plays that long.
Reforge.COOLDOWN = 1.2

--- What one reforge of a copy costs. `value` is its current sell value
--- (EconomyService.valueOf / the described copy's `value`), `count` how many times it
--- has been reforged already.
function Reforge.cost(value: number, count: number?): number
	local share = Reforge.COST_SHARE * (1 + Reforge.COST_STEP * math.max(0, count or 0))
	return math.max(Reforge.COST_MIN, math.floor(math.max(0, value) * share + 0.5))
end

--- One stat's multiplier from a 0..1 draw, rounded to 3 places so it saves small.
function Reforge.rollStat(u: number): number
	local t = math.clamp(u, 0, 1) ^ Reforge.SKEW
	local value = Reforge.ROLL_MIN + (Reforge.ROLL_MAX - Reforge.ROLL_MIN) * t
	return math.floor(value * 1000 + 0.5) / 1000
end

--- A stat multiplier as the panel's signed percent: 1.18 -> "+18%", 0.9 -> "-10%".
function Reforge.percentText(mult: number): string
	local pct = math.floor((mult - 1) * 100 + 0.5)
	return if pct >= 0 then `+{pct}%` else `{pct}%`
end

--- How good a forge roll is, 0..1 across the band, for the panel's meter.
function Reforge.grade(mult: number): number
	return math.clamp((mult - Reforge.ROLL_MIN) / (Reforge.ROLL_MAX - Reforge.ROLL_MIN), 0, 1)
end

return Reforge
