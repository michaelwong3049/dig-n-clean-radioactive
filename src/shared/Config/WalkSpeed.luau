--!strict
--[[
	WalkSpeed.luau — how fast you walk, and what it costs to walk faster. The ONLY thing
	in the game that sets your base walk speed.

	SPEED IS BOUGHT NOW, AT THE UPGRADES BOOTH (on request, 2026-10-09: "removing the
	treadmill, and making an upgrade stand to buy speed instead"). The booth that used to
	be the Magnet Shop (Base Camp, Toxic Twilight, Magma Hollow) opens the speed panel
	(client/SpeedPanel); each press of BUY adds `stepFor(deepest stage)` walk speed for
	one price. The treadmill, its belts, the Speed unit and the 2x Speed pass are gone.

	THE STEP GROWS WITH HOW DEEP YOU HAVE BEEN (on request: "make the speed incrementally
	higher depending on the level of where the player is at"). `data.stats.deepestStage`
	(MasteryService) picks the row of STAGE_STEPS: +1 a purchase in Stages 1-2, up to +6
	in Stages 11-12. The PRICE is set by the walk you are buying FROM, not by the step, so
	one purchase deep in the map buys more speed for the same money -- the reward for
	getting there.

	THE PRICE CLIMBS PRICE_GROWTH PER POINT OF WALK, forever (no cap, like the treadmill
	had none). That is what keeps a lucky Legendary from making anyone permanently fast:
	every point costs ~18% more than the last, so the walk a player can afford tracks the
	cash their stage pays rather than running away from it. Roughly, from walk 30:

	      walk  45  ~$6K      (Stage 1-2 money)
	      walk  70  ~$380K    (Stage 3-4, a Winch Coil)
	      walk 100  ~$55M     (Twilight)
	      walk 130  ~$7.6B    (Magma Hollow)

	BULK BUYS (on request, 2026-10-10: "options where you can buy +3, +10 speed"): the
	panel's +3 and +10 cash buttons buy exactly that much walk, whatever the step. Each
	point costs its share of the purchase it would have been part of, priceFor(walk) /
	step, summed point by point (`bulkPriceFor`), so +N costs about what N points of
	BUY presses would. The Robux button (PRODUCT_ID) is a flat +10 too.

	The Runner mastery that took a share off every price is gone (2026-10-10, on request).

	SAVES: `data.walkBought` is walk speed bought on top of START_WALK. A save from the
	treadmill days carries lifetime `speedPoints` instead; DataService converts it once
	through `fromLegacyPoints`, which keeps the walk speed they had trained.
]]

local WalkSpeed = {}

--- Walk speed with nothing bought. One purchase step = that many studs/sec on top.
WalkSpeed.START_WALK = 30

--- The slowest a player can turn themselves down to with the walk-speed picker (the
--- pencil by the WALK SPEED row). Roblox's own default walk, so "slow" still moves.
WalkSpeed.MIN_PICKED_WALK = 16

--- The walk a player has PICKED, clamped to what they own. `picked` is the profile's
--- `walkCap`: 0 (or nil) means "always my full speed", which is what a new save starts
--- on and what MAX sets, so a new purchase is felt at once.
function WalkSpeed.chosenWalk(owned: number, picked: number?): number
	if type(picked) ~= "number" or picked <= 0 then
		return owned
	end
	return math.clamp(picked, WalkSpeed.MIN_PICKED_WALK, owned)
end

--- Where the old treadmill cap was. Nothing clamps to it; it is the reference the
--- Spec's dig-reveal check measures against.
WalkSpeed.ENDGAME_WALK = 100

--- The price of the first purchase (walk 30 -> 31), and how much dearer each point of
--- walk makes the next one.
WalkSpeed.FIRST_PRICE = 500
WalkSpeed.PRICE_GROWTH = 1.18

--- Walk speed per purchase, by the deepest stage reached: STAGE_STEPS[stage]. Two
--- stages a row, 1 to 6 over the twelve.
WalkSpeed.STAGE_STEPS = { 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6 }

--- The fixed amounts the panel's bulk cash buttons buy (bulkPriceFor).
WalkSpeed.BULK = { 3, 10 }

--- The Developer Product the panel's purple button sells: ROBUX_WALK walk speed, flat,
--- nothing spent. 0 would mean not set up, and the button would read SOON.
--- Creator Dashboard -> Monetization -> Developer Products: "+10 Speed".
WalkSpeed.PRODUCT_ID = 3717600113
WalkSpeed.ROBUX_WALK = 10

--- Three significant figures: $1,530 rather than $1,527.70.
local function roundNice(n: number): number
	if n < 1000 then
		return math.floor(n / 10 + 0.5) * 10
	end
	local magnitude = 10 ^ (math.floor(math.log10(n)) - 2)
	return math.floor(n / magnitude + 0.5) * magnitude
end

--- `walkBought` from a save, sanitised: a whole number, 0 or more (NaN reads as 0).
function WalkSpeed.bought(raw: any): number
	if type(raw) ~= "number" or raw ~= raw then
		return 0
	end
	return math.max(0, math.floor(raw))
end

--- The walk speed `walkBought` buys.
function WalkSpeed.walkFor(walkBought: number): number
	return WalkSpeed.START_WALK + WalkSpeed.bought(walkBought)
end

--- Walk speed one purchase adds for a player whose deepest stage is `deepestStage`.
function WalkSpeed.stepFor(deepestStage: number?): number
	local steps = WalkSpeed.STAGE_STEPS
	local stage = math.clamp(math.floor(tonumber(deepestStage) or 1), 1, #steps)
	return steps[stage]
end

local function rawPrice(walkBought: number): number
	return WalkSpeed.FIRST_PRICE * WalkSpeed.PRICE_GROWTH ^ WalkSpeed.bought(walkBought)
end

--- The price of the next purchase (one step) at `walkBought`.
function WalkSpeed.priceFor(walkBought: number): number
	return roundNice(rawPrice(walkBought))
end

--- The price of exactly `amount` walk speed from `walkBought`, for a player whose step
--- is `step`: each point priced as its share of a step purchase at that walk.
function WalkSpeed.bulkPriceFor(walkBought: number, amount: number, step: number): number
	local from = WalkSpeed.bought(walkBought)
	local share = math.max(1, math.floor(step))
	local total = 0
	for i = 0, math.max(0, math.floor(amount)) - 1 do
		total += rawPrice(from + i) / share
	end
	return roundNice(total)
end

--- "$25,000": a price as every sign, prompt and notice prints it. A million and up is
--- short instead, "$360M" / "$1.2B" (Mastery.short's ladder, inlined: Config requires nothing).
function WalkSpeed.priceText(amount: number): string
	for _, step in { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" } } do
		local size, suffix = step[1] :: number, step[2] :: string
		if math.abs(amount) >= size then
			local scaled = amount / size
			local text = if scaled >= 100 then string.format("%d", math.floor(scaled)) else string.format("%.1f", math.floor(scaled * 10) / 10)
			return "$" .. (string.gsub(text, "%.0$", "")) .. suffix
		end
	end
	local digits = tostring(math.floor(amount))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return "$" .. (string.gsub(grouped, "^,", ""))
end

-- ── Save conversion ───────────────────────────────────────────────────────

--- The treadmill's level curve, kept ONLY to read a save banked against it: lifetime
--- Speed, level n needing the running sum of EARLY_COSTS then 630 x 1.091^(n-2), each
--- total rounded to three figures, one stud/sec of walk per level from 30.
local LEGACY_EARLY = { 300, 400, 500, 600, 750 }
local LEGACY_FIRST = 630
local LEGACY_GROWTH = 1.091
local LEGACY_LIMIT = 2000

--- Old lifetime `speedPoints` -> `walkBought`, keeping the walk speed it had trained.
function WalkSpeed.fromLegacyPoints(points: any): number
	local banked = if type(points) == "number" and points == points then math.max(0, points) else 0
	local total, level = 0, 1
	while level < LEGACY_LIMIT do
		total += LEGACY_EARLY[level] or LEGACY_FIRST * LEGACY_GROWTH ^ (level - 1)
		if banked < roundNice(total) then
			break
		end
		level += 1
	end
	return level - 1
end

return WalkSpeed
