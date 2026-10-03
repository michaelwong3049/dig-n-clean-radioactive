--!strict
--[[
	DailyRewards.luau — the 7-day login calendar (Services/DailyRewardService,
	client DailyRewardsController). Contents picked by the user 2026-10-02.

	ONE CLAIM EVERY CLAIM_GAP SECONDS (24 h after the last claim, not at midnight), and a
	claim later than RESET_AFTER (48 h) restarts the streak at Day 1. After Day 7 it
	loops back to Day 1. Only the server clock counts (os.time()), so a device clock
	changes nothing.

	REWARDS SCALE WITH HOW FAR YOU HAVE GOT, because prices run from thousands at Stage 1
	to billions at Stage 12 and a flat number is huge early and worthless late:

	  cash    `cashMinutes` minutes of your stand income, never less than that many
	          minutes at the deepest stage's floor rate (FLOOR_RATE) -- so a new player
	          with empty stands still gets something worth having.
	  crates  the best variant your deepest stage drops (`crateVariant`), `+1` on the
	          crates marked `bump` (Day 7's better nuke crate), capped at the top.

	Everything is a grant the game already has (the same pieces as Config/Packs): cash,
	crates straight into the bag, Lucky Clover time, 2x Cash time.
]]

local Crates = require(script.Parent.Crates)

local DailyRewards = {}

DailyRewards.DAYS_IN_CYCLE = 7
DailyRewards.CLAIM_GAP = 24 * 60 * 60
DailyRewards.RESET_AFTER = 48 * 60 * 60

-- RESTORE STREAK: a Developer Product offered on the panel while a streak has broken
-- and the Day 1 restart has not been claimed yet. It makes the claim ready now on the
-- day you had reached. 0 = not set up yet (the button shows SOON).
DailyRewards.RESTORE_PRODUCT_ID = 3716086045

export type CrateGrant = {
	kind: string, -- "nuke" | "liquid"
	count: number,
	bump: number?, -- variants above the stage's best (Day 7)
}

export type Day = {
	cashMinutes: number,
	crates: { CrateGrant },
	luckSeconds: number,
	cashBoostSeconds: number,
	big: boolean?, -- the gold Day 7 card
}

DailyRewards.DAYS = {
	{ cashMinutes = 1, crates = {}, luckSeconds = 0, cashBoostSeconds = 0 },
	{ cashMinutes = 0, crates = { { kind = "liquid", count = 1 } }, luckSeconds = 10 * 60, cashBoostSeconds = 0 },
	{ cashMinutes = 2, crates = { { kind = "nuke", count = 1 } }, luckSeconds = 0, cashBoostSeconds = 0 },
	{ cashMinutes = 0, crates = { { kind = "nuke", count = 1 } }, luckSeconds = 0, cashBoostSeconds = 15 * 60 },
	{ cashMinutes = 3, crates = { { kind = "liquid", count = 2 } }, luckSeconds = 0, cashBoostSeconds = 0 },
	{ cashMinutes = 0, crates = { { kind = "nuke", count = 1 } }, luckSeconds = 20 * 60, cashBoostSeconds = 0 },
	{
		cashMinutes = 6,
		crates = { { kind = "nuke", count = 1 }, { kind = "nuke", count = 1, bump = 1 } },
		luckSeconds = 30 * 60,
		cashBoostSeconds = 30 * 60,
		big = true,
	},
} :: { Day }

-- The least $/s a day's cash minutes are worth, by deepest stage reached. Rough
-- fractions of what a player progressing on pace earns there (the pacing pass fits
-- ~20 min a stage early, ~2 h late); live stand income above it wins.
-- NERFED 2026-10-03 (user: "heavily nerf"): minutes cut ~5x (5/10/15/30 -> 1/2/3/6)
-- and these floors cut 5x, so cash is a small top-up, not a skip -- the crates and
-- boosts are the real prizes.
DailyRewards.FLOOR_RATE = {
	[1] = 5,
	[2] = 30,
	[3] = 180,
	[4] = 800,
	[5] = 2_400,
	[6] = 8_000,
	[7] = 24_000,
	[8] = 80_000,
	[9] = 300_000,
	[10] = 1_200_000,
	[11] = 5_000_000,
	[12] = 16_000_000,
} :: { [number]: number }

local function clampStage(stage: number): number
	return math.clamp(math.floor(stage), 1, #DailyRewards.FLOOR_RATE)
end

--- The day's cash for a player at `stage` earning `rate` $/s from their stands.
function DailyRewards.cashFor(day: Day, stage: number, rate: number): number
	if day.cashMinutes <= 0 then
		return 0
	end
	local perSecond = math.max(rate, DailyRewards.FLOOR_RATE[clampStage(stage)])
	return math.floor(perSecond * day.cashMinutes * 60)
end

--- The best crate variant `stage` drops: the highest nuke crate whose stage range
--- holds it (Scrap 1-4, Field 2-5, Void 4-7, Cobalt 7-10, Fusion 9-12). The liquid
--- side follows the same ladder.
function DailyRewards.crateVariant(stage: number): number
	local s = clampStage(stage)
	local best = 1
	for variant = 1, Crates.VARIANTS do
		local def = Crates.DEFS[Crates.idFor("nuke", variant)]
		local range = def and def.stages
		if range and s >= range[1] and s <= range[2] then
			best = variant
		end
	end
	return best
end

--- Every crate id the day grants at `stage`, one entry per crate.
function DailyRewards.crateIds(day: Day, stage: number): { string }
	local base = DailyRewards.crateVariant(stage)
	local out = {}
	for _, grant in day.crates do
		local variant = math.min(base + (grant.bump or 0), Crates.VARIANTS)
		for _ = 1, grant.count do
			table.insert(out, Crates.idFor(grant.kind, variant))
		end
	end
	return out
end

return DailyRewards
