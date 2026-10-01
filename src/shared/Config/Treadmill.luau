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

	NO TOP LEVEL, ONE WALK-SPEED POINT EACH. Level 1 walks at 30 (raised from the old
	Taped Boots 26 on request), level 71 at 100, and it keeps
	going: the cap was removed on request. Nothing has to hold the line instead, because
	each level costs `LEVEL_GROWTH` more than the last forever. Even on the top belt a
	level past 120 costs well over half an hour, so the number keeps climbing but never
	runs away (walk 110 is ~5 h on schedule, 120 ~8.4 h).
	`ENDGAME_WALK` (100) is where the old cap was. It is what the Spec milestones and the
	dig-reveal check measure against.

	NO "RATED SPEED" ANY MORE. Belts used to train at full rate only up to a rating and
	then fall off geometrically. That is gone on request: a belt is now just its
	Speed/sec. The push to upgrade comes from the requirements climbing `LEVEL_GROWTH`
	per level against belts that each pay ~2.5x the last — the ladder is the gate.

	FIVE BELTS, ONE IMPORTED MODEL EACH. There used to be six rungs sharing one
	procedural machine that only changed colour; the user imported four treadmill
	models (basic, green, blue, gold) and asked that every upgrade turn the machine
	into the next one, so the ladder was cut to four. Saves on the old six-rung ladder
	are collapsed by `fromSixRungLadder` (below), which refunds the difference in cash.
	The fifth, Diamond (`t5_diamond`), came with the cap removal: a Twilight-era buy
	that carries the climb past 100.

	WHAT THAT LANDS ON, upgrading roughly on schedule (one belt per 18 levels; checked
	in Util/Spec, which pins all three):

	      walk 45  ~0.25 h  — intermediate. One session.
	      walk 70  ~1.0 h   — advanced.
	      walk 100 ~3.7 h   — endgame. The old cap.

	Every belt's rate was doubled on request (the treadmill trains 2x faster than the
	first tuning), which is what roughly halves those times.

	And the cost of never upgrading: walk 64 is ~0.8 h on schedule, ~1.75 h on the free
	belt. Slow enough to make the belts worth buying, finite enough to wall nobody out.

	TUNING. `FIRST_LEVEL_COST` moves the whole curve up and down; `LEVEL_GROWTH` alone
	decides how much steeper the top is than the bottom. REQUIREMENTS is built from the
	two and rounded to three significant figures, so the numbers a player reads on the
	card are the numbers the server compares against. It is grown on demand
	(`requirementFor`), since there is no last level to build up to at load.
]]

local Treadmill = {}

--- Walk speed at level 1. One level = one stud/sec, with no top level.
Treadmill.START_WALK = 30

--- The slowest a player can turn themselves down to with the walk-speed picker (the
--- pencil by the WALK SPEED row). Roblox's own default walk, so "slow" still moves.
Treadmill.MIN_PICKED_WALK = 16

--- The walk a player has PICKED, clamped to what they have trained. `picked` is the
--- profile's `walkCap`: 0 (or nil) means "always my full trained speed", which is what
--- a new save starts on and what MAX sets, so a new level is felt at once.
function Treadmill.chosenWalk(trained: number, picked: number?): number
	if type(picked) ~= "number" or picked <= 0 then
		return trained
	end
	return math.clamp(picked, Treadmill.MIN_PICKED_WALK, trained)
end

--- Where the cap used to be (level 75). Nothing clamps to it any more; it is the
--- reference point the Spec milestones and the dig-reveal check are measured at.
Treadmill.ENDGAME_WALK = 100

--- Speed it takes to go from level 1 to level 2 on the normal curve, and how much
--- dearer each level after that is than the one before it. 630 is the old 700 made 10%
--- easier, on request; every level past the early ramp is 10% cheaper with it.
Treadmill.FIRST_LEVEL_COST = 630
Treadmill.LEVEL_GROWTH = 1.091

--- The first five levels, priced by hand and far cheaper than the curve, so a new
--- player feels the belt work within a minute or two (shown x10: 3,000 / 4,000 /
--- 5,000 / 6,000 / 7,500). From the sixth level on the normal curve resumes at the
--- step it would have been on anyway, so the ramp joins it without a jump.
Treadmill.EARLY_COSTS = { 300, 400, 500, 600, 750 }

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

--- REQUIREMENTS[level] = lifetime Speed needed to BE at that level. [1] is 0. Grown
--- on demand by `grow`; read it through `requirementFor`, never by index, because a
--- level nobody has asked about yet is not in the table.
Treadmill.REQUIREMENTS = { 0 } :: { number }

--- The unrounded running total behind the last entry, so growing the table never
--- re-sums from level 1 and the rounding never compounds.
local rawTotal = 0

--- Past this many levels the requirement is past any Speed a save can hold (it passes
--- 1e15 around level 295), so stop growing rather than loop on a corrupt total.
local LEVEL_LIMIT = 2000

local function grow(level: number)
	local reqs = Treadmill.REQUIREMENTS
	for next = #reqs + 1, math.min(level, LEVEL_LIMIT) do
		rawTotal += Treadmill.EARLY_COSTS[next - 1] or Treadmill.FIRST_LEVEL_COST * Treadmill.LEVEL_GROWTH ^ (next - 2)
		reqs[next] = roundNice(rawTotal)
	end
end
grow(Treadmill.ENDGAME_WALK - Treadmill.START_WALK + 1)

export type TreadmillTier = {
	name: string,
	price: number,
	rate: number, -- Speed per second while standing on it
	blurb: string,
	-- The imported model this rung wears: a child of
	-- ReplicatedStorage.Assets.TreadmillTemplates (build/Plots.setTreadmillTier).
	model: string,
}

--- What a player pays at the console before ANY belt will train them. FREE, on
--- request: it used to be $1,000, and every save now starts unlocked on the Scrap Belt
--- (DataService's template; TreadmillService unlocks older saves on load). The lock
--- machinery stays for `/train lock`, which is the only way a player is locked now,
--- and a $0 unlock there is one press of the console.
Treadmill.UNLOCK_PRICE = 0

--- "$25,000": a price as every sign, prompt and notice prints it.
function Treadmill.priceText(amount: number): string
	local digits = tostring(math.floor(amount))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return "$" .. (string.gsub(grouped, "^,", ""))
end

--- Every real Speed point is SHOWN as this many, so on-screen numbers race (a 700
--- requirement reads 7,000, a 10/s belt reads +100/s). Display only: the curve, the
--- rates and the saves are all in real points.
Treadmill.DISPLAY_SCALE = 10

--- A real Speed/sec rate as players see it.
function Treadmill.rateText(rate: number): string
	return tostring(rate * Treadmill.DISPLAY_SCALE)
end

--- "$1,000", or "Free" at $0: the unlock price as every sign, prompt and notice prints it.
function Treadmill.unlockPriceText(): string
	if Treadmill.UNLOCK_PRICE <= 0 then
		return "Free"
	end
	return Treadmill.priceText(Treadmill.UNLOCK_PRICE)
end

--- Rates climb ~2.5x a rung: with no rated-speed falloff left, this ratio is the whole
--- reason to upgrade. Prices were re-fitted in the economy pacing pass (Config/Gear's
--- header): the belts are Stage 3, Stage 6 and Stage 9 purchases.
Treadmill.TIERS = {
	{ name = "Scrap Belt", price = 0, rate = 20, model = "t1_basic", blurb = "A conveyor off a dead factory line. It turns. Mostly." },
	{ name = "Servo Track", price = 950000, rate = 60, model = "t2_green", blurb = "Servo-driven. Reads your stride and outruns it." },
	{ name = "Reactor Mill", price = 5400000, rate = 160, model = "t3_blue", blurb = "Runs off a slug of core. Warm underfoot." },
	{ name = "Isotope Strider", price = 38000000, rate = 380, model = "t4_gold", blurb = "Hums like a reactor. Most runners stop here." },
	-- A Twilight-era buy (priced against the Strata Lance), for the climb past the old
	-- cap: ~4 h from walk 100 to 110 on it, against ~10 h on the Strider.
	{ name = "Diamond Drive", price = 2500000000, rate = 900, model = "t5_diamond", blurb = "The last belt. Cut from one crystal. It never wears down." },
} :: { TreadmillTier }

--- Lifetime Speed needed to be at `level`. There is no top level, so this is always a
--- number for any level from 1 up (nil only for a level below 1, or one past the
--- 2,000-level guard no save can reach).
function Treadmill.requirementFor(level: number): number?
	if level < 1 then
		return nil
	end
	grow(level)
	return Treadmill.REQUIREMENTS[level]
end

--- The level `points` of lifetime Speed buys, and how far into the NEXT level the
--- remainder sits (0..1). A plain table walk against the same rounded numbers the card
--- prints, so there is no floating-point boundary where a player who has exactly the
--- requirement reads as the level below.
function Treadmill.levelFor(points: number): (number, number)
	local banked = if points == points then math.max(0, points) else 0 -- NaN reads as 0
	local reqs = Treadmill.REQUIREMENTS
	-- Grow until the table holds a requirement past `banked`. Each level costs ~9% more
	-- than the last, so even 1e15 is only ~295 levels in.
	while reqs[#reqs] <= banked and #reqs < LEVEL_LIMIT do
		grow(#reqs + 1)
	end
	local lo, hi = 1, #reqs
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if banked >= reqs[mid] then
			lo = mid
		else
			hi = mid - 1
		end
	end
	if lo >= #reqs then
		return lo, 1
	end
	local from, to = reqs[lo], reqs[lo + 1]
	return lo, math.clamp((banked - from) / (to - from), 0, 1)
end

function Treadmill.walkSpeedFor(level: number): number
	return Treadmill.START_WALK + math.max(level, 1) - 1
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
local LEGACY_MAX_WALK = 100 -- that curve's cap; old saves cannot be past it

local function legacyXpFor(walk: number): number
	local n = math.clamp(walk, Treadmill.START_WALK, LEGACY_MAX_WALK) - Treadmill.START_WALK
	return LEGACY_FIRST * (LEGACY_GROWTH ^ n - 1) / (LEGACY_GROWTH - 1)
end

--- Old `speedXp` -> lifetime Speed, landing the player on the SAME walk speed with the
--- same fraction of the bar filled. Nobody loses a level to the rework; the bar just
--- starts reading in the new unit.
function Treadmill.fromLegacyXp(xp: number): number
	local banked = math.max(0, xp)
	local walk = Treadmill.START_WALK
	while walk < LEGACY_MAX_WALK and banked >= legacyXpFor(walk + 1) do
		walk += 1
	end
	local level = walk - Treadmill.START_WALK + 1
	if walk >= LEGACY_MAX_WALK then
		return Treadmill.requirementFor(level) :: number
	end
	local into = (banked - legacyXpFor(walk)) / (legacyXpFor(walk + 1) - legacyXpFor(walk))
	local from, to = Treadmill.requirementFor(level) :: number, Treadmill.requirementFor(level + 1) :: number
	return from + math.clamp(into, 0, 1) * (to - from)
end

--- What each rung of the OLD six-belt ladder cost to buy (Scrap Belt, Chain Runner,
--- Geared Treadplate, Servo Track, Reactor Mill, Isotope Strider). Kept ONLY to read
--- a save made before the ladder was cut to four.
local SIX_RUNG_PRICES = { 0, 11500, 32500, 90000, 255000, 700000 }

--- Cash spent climbing a ladder of per-rung `prices` up to and including `tier`.
local function spentTo(prices: { number }, tier: number): number
	local total = 0
	for index = 2, math.clamp(tier, 1, #prices) do
		total += prices[index]
	end
	return total
end

--- An old six-rung `treadmill` number -> the new rung, and the cash to hand back. The
--- player lands on the best new belt their old spend covers and gets the rest as cash,
--- so nobody loses a dollar to the cut and nobody is handed a belt they did not pay
--- for. Spec §5.1 pins that the two always add back up to the old spend.
function Treadmill.fromSixRungLadder(oldTier: number): (number, number)
	local spent = spentTo(SIX_RUNG_PRICES, math.floor(oldTier))
	local newPrices = {}
	for index, def in Treadmill.TIERS do
		newPrices[index] = def.price
	end
	local tier = 1
	while tier < #Treadmill.TIERS and spentTo(newPrices, tier + 1) <= spent do
		tier += 1
	end
	return tier, spent - spentTo(newPrices, tier)
end

return Treadmill
