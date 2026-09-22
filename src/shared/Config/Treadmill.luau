--!strict
--[[
	Treadmill.lua — the speed track, and the ONLY thing in the game that sets how
	fast you walk.

	THIS REPLACED THE BOOTS LADDER. Speed used to be a six-rung purchase like every
	other track (Config/Gear.Boots, 26 -> 36 studs/sec): you saved up, you bought a
	rung, you were permanently faster. That is gone. Speed is now TRAINED — you park
	on a belt on your own plot and the number climbs, slowly, forever, and the thing
	you buy is a better belt rather than the speed itself. Gear.Boots is still in the
	file, marked RETIRED, because DataService refunds it; nothing reads its stats.

	WHY A GRIND AND NOT A PURCHASE. The stages chain east and the walk is long (PLAN
	§5), so speed is the quality-of-life lever players ask for first. As a purchase it
	is also the most economically dangerous track in the game (PLAN §5.2) — it
	multiplies sweep rate, round trips, and value retained against the decay clock all
	at once. Selling it for cash means a player who gets rich once is permanently fast.
	Charging TIME for it instead means the ceiling is gated by something nobody can
	shortcut with a lucky Legendary, and it gives an idle player a reason to leave the
	game open, which is the whole point of the feature.

	THE SHAPE, in one paragraph: every point of speed costs `XP_GROWTH` times more
	training than the point before it. Every belt tier trains you meaningfully faster
	than the last, but NOT as much faster as the cost grew — so the upgrade buys back
	most of the climb, never all of it, and the ladder stays a grind at every height.
	Past a belt's `rated` speed the rate falls off geometrically instead of stopping,
	which is the same soft-gate shape Gear.Magnet's `maxGrip` uses for over-tier soil
	(see Tuning.OVER_GRIP_*): you can always keep going, it just gets brutal. No rung
	of this ladder ever tells a player "no".

	WHAT THAT LANDS ON, upgrading roughly on schedule (checked in Util/Spec, which
	pins all three of these):

	      speed 45  ~1.0 h    — intermediate. Inside a couple of sessions.
	      speed 70  ~4.1 h    — advanced. A real commitment.
	      speed 100 ~15.3 h   — endgame. A multi-week badge.

	And what it costs to skip the upgrades, which is the soft gate doing its job:
	speed 64 is 3.2 h on the belt rated for it, 6.4 h one rung under, and 30 h on the
	free starting belt. Slow enough that nobody grinds through it by choice, finite
	enough that nobody is walled out.

	TUNING. `XP_FIRST_POINT` moves the whole curve up and down; `XP_GROWTH` alone
	decides how much steeper the top is than the bottom. The two are not independent
	of the TIERS table's `rate` column — cost growth per 12-point band is
	XP_GROWTH^12 (~2.2x) against a rate ladder that climbs 1.4x per rung, and the
	ratio between those two numbers IS the difficulty ramp. Raising the rates without
	touching XP_GROWTH flattens the endgame; Spec's milestone checks will say so.
]]

local Treadmill = {}

--- Where an untrained player starts. This is deliberately the OLD Taped Boots
--- number, not zero and not 16: day one has to feel exactly like it did before the
--- Boots track was retired, or this change is a stealth nerf to every new player.
Treadmill.START_SPEED = 26

--- The ceiling, and the reason the curve is geometric rather than open-ended. A
--- trained player tops out here and the belt stops accruing (see `speedFor`), so
--- `speedXp` is bounded in the save file and Humanoid.WalkSpeed is bounded in the
--- world. Nothing above this is reachable by any combination of tier and time.
Treadmill.MAX_SPEED = 100

--- Training units. One unit is one second on the free starting belt, which is what
--- makes every number in this file legible as a time — `costFor(26)` really is
--- "110 seconds for your first point of speed".
Treadmill.XP_FIRST_POINT = 110
Treadmill.XP_GROWTH = 1.068

--- Speed points past a belt's `rated` figure that HALVE its training rate. Six, so
--- a full band over-rated (12 points) is a quarter rate and two bands is a
--- sixteenth. Same 0.5^deficit curve as the magnet's over-tier soil penalty, for the
--- same reason: a multiplicative falloff is a gradient, and a hard cap is a wall.
Treadmill.FALLOFF_STEP = 6

export type TreadmillTier = {
	name: string,
	price: number,
	rate: number, -- training units per second, at or under `rated`
	rated: number, -- the speed this belt is built for; past it, the falloff bites
	blurb: string,
}

--- PRICED ON THE RETIRED BOOTS LADDER, RUNG FOR RUNG (0 / 2300 / 6500 / 18000 /
--- 51000 / 140000). That is not nostalgia: Boots was the steep ~2.8x curve PLAN §5.2
--- asked for precisely because speed is the dangerous stat, and this track inherits
--- that exact economic role. It also means DataService's one-time Boots refund hands
--- a returning player back the exact cash to buy the belt rung matching whatever
--- boots they had, which is as close to "nothing was taken from you" as a retirement
--- gets.
---
--- `rated` covers a 12-point band each, tiling START_SPEED..MAX_SPEED with the top
--- rung rated for the cap itself — so a maxed player on a maxed belt is never in
--- falloff at all, and the last point of speed is expensive because the CURVE is
--- expensive, not because the belt is fighting them.
Treadmill.TIERS = {
	{ name = "Scrap Belt", price = 0, rate = 1.00, rated = 40, blurb = "A conveyor off a dead factory line. It turns. Mostly." },
	{ name = "Chain Runner", price = 2300, rate = 1.40, rated = 52, blurb = "Bicycle chain and a flywheel. Keeps its own pace." },
	{ name = "Geared Treadplate", price = 6500, rate = 1.96, rated = 64, blurb = "Geared plate deck. Pushes back when you push it." },
	{ name = "Servo Track", price = 18000, rate = 2.74, rated = 76, blurb = "Servo-driven. Reads your stride and outruns it." },
	{ name = "Reactor Mill", price = 51000, rate = 3.84, rated = 88, blurb = "Runs off a slug of core. Warm underfoot." },
	{ name = "Isotope Strider", price = 140000, rate = 5.38, rated = 100, blurb = "The last belt. Nothing here is rated past what it does." },
} :: { TreadmillTier }

--- Training units to buy the point that takes you FROM `speed` to `speed + 1`.
---
--- Returns math.huge at the cap, which is what stops `speedFor` from ever reading a
--- fractional progress bar past MAX_SPEED and what lets the service clamp accrual
--- with a comparison rather than a special case. It is never stored — `speedXp` is
--- clamped to `xpForSpeed(MAX_SPEED)` before it reaches the profile, because a
--- math.huge in a DataStore is a corrupted save.
function Treadmill.costFor(speed: number): number
	if speed >= Treadmill.MAX_SPEED then
		return math.huge
	end
	local n = math.max(0, speed - Treadmill.START_SPEED)
	return Treadmill.XP_FIRST_POINT * Treadmill.XP_GROWTH ^ n
end

--- Total training units banked by a player sitting at exactly `speed`. The closed
--- form of the geometric series `costFor` walks, so nothing has to sum 74 terms to
--- answer "how far in am I".
function Treadmill.xpForSpeed(speed: number): number
	local n = math.clamp(speed, Treadmill.START_SPEED, Treadmill.MAX_SPEED) - Treadmill.START_SPEED
	local g = Treadmill.XP_GROWTH
	return Treadmill.XP_FIRST_POINT * (g ^ n - 1) / (g - 1)
end

--- The whole of `xp`, read as a speed: the integer studs/sec it buys, and how far
--- into the NEXT point the remainder sits (0..1, and exactly 1 at the cap).
---
--- Closed-form inverse of `xpForSpeed`, then corrected. The correction is not
--- defensive padding: `xpForSpeed` and its own inverse disagree by an ulp or two
--- right at a boundary, and without it a player who has banked exactly enough for
--- speed 47 reads as 46 with a 100%-full bar — the single most visible possible bug
--- in this feature, and one that only appears at the instant of a level-up. Both
--- loops are bounded by one or two steps in practice.
function Treadmill.speedFor(xp: number): (number, number)
	local start, max = Treadmill.START_SPEED, Treadmill.MAX_SPEED
	local g = Treadmill.XP_GROWTH
	local banked = math.max(0, xp)

	local n = math.floor(math.log(1 + banked * (g - 1) / Treadmill.XP_FIRST_POINT) / math.log(g))
	n = math.clamp(n, 0, max - start)
	while n < max - start and banked >= Treadmill.xpForSpeed(start + n + 1) do
		n += 1
	end
	while n > 0 and banked < Treadmill.xpForSpeed(start + n) do
		n -= 1
	end

	local speed = start + n
	if speed >= max then
		return max, 1
	end
	local into = banked - Treadmill.xpForSpeed(speed)
	return speed, math.clamp(into / Treadmill.costFor(speed), 0, 1)
end

--- A belt rung, clamped. Mirrors Gear.tier's contract exactly (out-of-range indices
--- clamp rather than error) because DataService's `treadmill` field is a plain number
--- in a save file and a hand-edited or rolled-back profile must not break a boot.
function Treadmill.tier(index: number): TreadmillTier
	return Treadmill.TIERS[math.clamp(index, 1, #Treadmill.TIERS)]
end

function Treadmill.maxTier(): number
	return #Treadmill.TIERS
end

--- What tier `index` earns per second for a player currently at `speed`.
---
--- At or under the belt's rated speed this is just its `rate`. Past it the rate
--- halves every FALLOFF_STEP points, which is the soft gate: it approaches zero and
--- never reaches it, so the answer to "can I train past what my belt is rated for"
--- is always yes and the answer to "should I" is always no.
function Treadmill.rateFor(index: number, speed: number): number
	local tier = Treadmill.tier(index)
	local over = math.max(0, speed - tier.rated)
	return tier.rate * 0.5 ^ (over / Treadmill.FALLOFF_STEP)
end

--- The next rung's price, or nil at the top of the ladder. nil rather than math.huge
--- so every surface that renders a price has to decide what "there is no next one"
--- looks like instead of printing $inf.
function Treadmill.priceFor(index: number): number?
	local next = Treadmill.TIERS[index + 1]
	return if next then next.price else nil
end

return Treadmill
