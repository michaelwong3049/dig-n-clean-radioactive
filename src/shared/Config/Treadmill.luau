--!strict
--[[
	Treadmill.lua — the Speed unit, the speed levels it unlocks, and the belts that
	earn it. The ONLY thing in the game that sets how fast you walk.

	THE LOOP, in one paragraph: stand on a treadmill and it pays you SPEED — a visible
	number, like cash, that only ever goes up. Every walk-speed level has a Speed
	requirement; the instant your lifetime Speed reaches the next one you level up
	and walk one stud/sec faster. Nothing is spent. The thing you BUY is a better belt,
	which pays more Speed per second. That is the whole feature.

	WHY SPEED IS EARNED AND NOT BOUGHT (unchanged since the Boots ladder was retired).
	The stages chain east and the walk is long (PLAN §5), so speed is the quality-of-
	life lever players ask for first — and as a purchase it is the most economically
	dangerous track in the game (PLAN §5.2): it multiplies sweep rate, round trips and
	value retained against the decay clock all at once. Cash buys a belt that earns
	faster; it never buys a single level. Gear.Boots is still in its file, marked
	RETIRED, because DataService refunds it.

	75 LEVELS, ONE WALK-SPEED POINT EACH. Level 1 walks at 26 (the old Taped Boots
	number, so day one feels exactly like it always did), level 75 at 100.

	NO "RATED SPEED" ANY MORE. Belts used to train at full rate only up to a rating and
	then fall off geometrically. That is gone on request: a belt is now just its
	Speed/sec. The push to upgrade comes from the requirements climbing `LEVEL_GROWTH`
	per level against belts that each pay ~1.8x the last — the ladder is the gate.

	WHAT THAT LANDS ON, upgrading roughly on schedule (one belt per 12 levels; checked
	in Util/Spec, which pins all three). Deliberately easier than the old curve
	(1.0 h / 4.1 h / 15.3 h), on request:

	      walk 45  ~0.7 h   — intermediate. One session.
	      walk 70  ~2.9 h   — advanced.
	      walk 100 ~11 h    — endgame.

	And the cost of never upgrading: walk 64 is ~2.2 h on schedule, ~5.6 h on the free
	belt. Slow enough to make the belts worth buying, finite enough to wall nobody out.

	TUNING. `FIRST_LEVEL_COST` moves the whole curve up and down; `LEVEL_GROWTH` alone
	decides how much steeper the top is than the bottom. REQUIREMENTS is built from the
	two at load and rounded to three significant figures, so the numbers a player reads
	on the card are the numbers the server compares against.
]]

local Treadmill = {}

--- Walk speed at level 1 and at the top level. One level = one stud/sec.
Treadmill.START_WALK = 26
Treadmill.MAX_WALK = 100
Treadmill.MAX_LEVEL = Treadmill.MAX_WALK - Treadmill.START_WALK + 1

--- Speed it takes to go from level 1 to level 2, and how much dearer each level after
--- that is than the one before it.
Treadmill.FIRST_LEVEL_COST = 700
Treadmill.LEVEL_GROWTH = 1.091

--- Three significant figures: 1,530 rather than 1,527.7. Fine enough that no two
--- levels ever round onto the same requirement (the smallest step is ~8% of the
--- running total, three figures resolve 1%), coarse enough to read on a card.
local function roundNice(n: number): number
	if n < 1000 then
		return math.floor(n / 10 + 0.5) * 10
	end
	local magnitude = 10 ^ (math.floor(math.log10(n)) - 2)
	return math.floor(n / magnitude + 0.5) * magnitude
end

--- REQUIREMENTS[level] = lifetime Speed needed to BE at that level. [1] is 0.
Treadmill.REQUIREMENTS = {} :: { number }
do
	local total = 0
	Treadmill.REQUIREMENTS[1] = 0
	for level = 2, Treadmill.MAX_LEVEL do
		total += Treadmill.FIRST_LEVEL_COST * Treadmill.LEVEL_GROWTH ^ (level - 2)
		Treadmill.REQUIREMENTS[level] = roundNice(total)
	end
end

export type TreadmillTier = {
	name: string,
	price: number,
	rate: number, -- Speed per second while standing on it
	blurb: string,
}

--- PRICED ON THE RETIRED BOOTS LADDER, RUNG FOR RUNG, so DataService's one-time Boots
--- refund hands a returning player back the exact cash for the equivalent belt (Spec
--- §5.1 pins the match). Rates climb ~1.8x a rung: with no rated-speed falloff left,
--- this ratio is the whole reason to upgrade.
Treadmill.TIERS = {
	{ name = "Scrap Belt", price = 0, rate = 10, blurb = "A conveyor off a dead factory line. It turns. Mostly." },
	{ name = "Chain Runner", price = 11500, rate = 18, blurb = "Bicycle chain and a flywheel. Keeps its own pace." },
	{ name = "Geared Treadplate", price = 32500, rate = 32, blurb = "Geared plate deck. Pushes back when you push it." },
	{ name = "Servo Track", price = 90000, rate = 58, blurb = "Servo-driven. Reads your stride and outruns it." },
	{ name = "Reactor Mill", price = 255000, rate = 105, blurb = "Runs off a slug of core. Warm underfoot." },
	{ name = "Isotope Strider", price = 700000, rate = 190, blurb = "The last belt. Nothing on this map runs faster." },
} :: { TreadmillTier }

--- Lifetime Speed needed to be at `level`, or nil past the top. nil rather than
--- math.huge so every surface that prints "next level at" has to decide what the top
--- looks like instead of printing inf.
function Treadmill.requirementFor(level: number): number?
	return Treadmill.REQUIREMENTS[level]
end

--- The level `points` of lifetime Speed buys, and how far into the NEXT level the
--- remainder sits (0..1, exactly 1 at the top). A plain table walk against the same
--- rounded numbers the card prints, so there is no floating-point boundary where a
--- player who has exactly the requirement reads as the level below.
function Treadmill.levelFor(points: number): (number, number)
	local banked = math.max(0, points)
	local reqs = Treadmill.REQUIREMENTS
	local lo, hi = 1, Treadmill.MAX_LEVEL
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if banked >= reqs[mid] then
			lo = mid
		else
			hi = mid - 1
		end
	end
	if lo >= Treadmill.MAX_LEVEL then
		return Treadmill.MAX_LEVEL, 1
	end
	local from, to = reqs[lo], reqs[lo + 1]
	return lo, math.clamp((banked - from) / (to - from), 0, 1)
end

function Treadmill.walkSpeedFor(level: number): number
	return Treadmill.START_WALK + math.clamp(level, 1, Treadmill.MAX_LEVEL) - 1
end

--- Walk speed straight from lifetime Speed, plus the progress bar. What StatResolver
--- reads.
function Treadmill.walkFor(points: number): (number, number)
	local level, progress = Treadmill.levelFor(points)
	return Treadmill.walkSpeedFor(level), progress
end

--- A belt rung, clamped. Mirrors Gear.tier's contract (out-of-range clamps rather
--- than errors) because `treadmill` is a plain number in a save file.
function Treadmill.tier(index: number): TreadmillTier
	return Treadmill.TIERS[math.clamp(index, 1, #Treadmill.TIERS)]
end

function Treadmill.maxTier(): number
	return #Treadmill.TIERS
end

--- Speed per second on belt `index`. Flat: no rating, no falloff.
function Treadmill.rateFor(index: number): number
	return Treadmill.tier(index).rate
end

--- The next rung's price, or nil at the top of the ladder.
function Treadmill.priceFor(index: number): number?
	local next = Treadmill.TIERS[index + 1]
	return if next then next.price else nil
end

-- ── Save conversion ───────────────────────────────────────────────────────

--- The curve saves were banked against before Speed existed: hidden `speedXp`, one
--- unit per second on the free belt, each walk-speed point 1.068x dearer than the
--- last from 110. Kept ONLY to read an old save — nothing earns in these units.
local LEGACY_FIRST = 110
local LEGACY_GROWTH = 1.068

local function legacyXpFor(walk: number): number
	local n = math.clamp(walk, Treadmill.START_WALK, Treadmill.MAX_WALK) - Treadmill.START_WALK
	return LEGACY_FIRST * (LEGACY_GROWTH ^ n - 1) / (LEGACY_GROWTH - 1)
end

--- Old `speedXp` -> lifetime Speed, landing the player on the SAME walk speed with the
--- same fraction of the bar filled. Nobody loses a level to the rework; the bar just
--- starts reading in the new unit.
function Treadmill.fromLegacyXp(xp: number): number
	local banked = math.max(0, xp)
	local walk = Treadmill.START_WALK
	while walk < Treadmill.MAX_WALK and banked >= legacyXpFor(walk + 1) do
		walk += 1
	end
	local level = walk - Treadmill.START_WALK + 1
	if level >= Treadmill.MAX_LEVEL then
		return Treadmill.REQUIREMENTS[Treadmill.MAX_LEVEL]
	end
	local into = (banked - legacyXpFor(walk)) / (legacyXpFor(walk + 1) - legacyXpFor(walk))
	local from, to = Treadmill.REQUIREMENTS[level], Treadmill.REQUIREMENTS[level + 1]
	return from + math.clamp(into, 0, 1) * (to - from)
end

return Treadmill
