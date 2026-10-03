--!strict
--[[
	PlaytimeGifts.luau — the "Free Gifts" ladder: stay in the game and a gift opens every
	few minutes, each one better than the last (Services/PlaytimeGiftService, client
	PlaytimeGiftController).

	THE CLOCK IS THE SESSION. It starts when you join and is never saved, so leaving
	resets every gift ("Leaving Resets Gifts!" on the panel). Only the server clock
	counts.

	A GIFT OPENS AT `minutes` AND STAYS OPEN until it is claimed (or you leave), so a
	player who is busy digging claims the lot in one go.

	WHAT A GIFT CAN HOLD (every field optional):
	  cashMinutes        minutes of your stand income, never less than that many minutes
	                     at your deepest stage's floor rate (DailyRewards.FLOOR_RATE) -- the
	                     same scaling as the daily calendar, so it is never huge early or
	                     worthless late
	  speed              Speed points (the treadmill stat)
	  luckSeconds        seconds of 2x luck
	  cashBoostSeconds   seconds of 2x cash
	  potions            { { id = Potions id, count = n } } into the potion stash
	  crates             { { kind = "nuke" | "liquid", count = n, bump = n? } }, the best
	                     variant your stage drops (DailyRewards.crateIds), `bump` above it

	Crates only turn up from the hour mark: they take bag space.
]]

local DailyRewards = require(script.Parent.DailyRewards)

local PlaytimeGifts = {}

export type Potion = { id: string, count: number }
export type CrateGrant = { kind: string, count: number, bump: number? }

export type Gift = {
	minutes: number,
	cashMinutes: number?,
	speed: number?,
	luckSeconds: number?,
	cashBoostSeconds: number?,
	potions: { Potion }?,
	crates: { CrateGrant }?,
	big: boolean?, -- the gold last card
}

PlaytimeGifts.GIFTS = {
	{ minutes = 1, cashMinutes = 1 },
	{ minutes = 3, potions = { { id = "luck", count = 1 } } },
	{ minutes = 5, cashMinutes = 2, speed = 250 },
	{ minutes = 8, potions = { { id = "cash", count = 1 } } },
	{ minutes = 10, cashMinutes = 3, speed = 500 },
	{ minutes = 15, cashBoostSeconds = 5 * 60, potions = { { id = "speed", count = 1 } } },
	{ minutes = 20, cashMinutes = 4, luckSeconds = 5 * 60, speed = 1_000 },
	{ minutes = 30, cashMinutes = 6, potions = { { id = "strength", count = 1 }, { id = "clean", count = 1 } }, speed = 2_000 },
	{ minutes = 45, cashMinutes = 8, luckSeconds = 10 * 60, cashBoostSeconds = 10 * 60, speed = 4_000 },
	{
		minutes = 60,
		cashMinutes = 10,
		potions = { { id = "luck", count = 1 }, { id = "cash", count = 1 }, { id = "speed", count = 1 } },
		crates = { { kind = "liquid", count = 1 } },
		speed = 7_500,
	},
	{
		minutes = 90,
		cashMinutes = 15,
		luckSeconds = 20 * 60,
		cashBoostSeconds = 20 * 60,
		crates = { { kind = "nuke", count = 1 } },
		speed = 12_000,
	},
	{
		minutes = 120,
		cashMinutes = 25,
		luckSeconds = 30 * 60,
		cashBoostSeconds = 30 * 60,
		potions = { { id = "luck", count = 2 }, { id = "cash", count = 2 }, { id = "strength", count = 1 } },
		crates = { { kind = "nuke", count = 1 }, { kind = "nuke", count = 1, bump = 1 } },
		speed = 20_000,
		big = true,
	},
} :: { Gift }

local function clampStage(stage: number): number
	return math.clamp(math.floor(stage), 1, #DailyRewards.FLOOR_RATE)
end

--- The gift's cash for a player at `stage` earning `rate` $/s from their stands.
function PlaytimeGifts.cashFor(gift: Gift, stage: number, rate: number): number
	local minutes = gift.cashMinutes or 0
	if minutes <= 0 then
		return 0
	end
	local perSecond = math.max(rate, DailyRewards.FLOOR_RATE[clampStage(stage)])
	return math.floor(perSecond * minutes * 60)
end

--- Every crate id the gift grants at `stage`, one entry per crate.
function PlaytimeGifts.crateIds(gift: Gift, stage: number): { string }
	local day: any = { crates = gift.crates or {} }
	return DailyRewards.crateIds(day, stage)
end

--- Seconds of session time the gift opens at.
function PlaytimeGifts.openAt(gift: Gift): number
	return gift.minutes * 60
end

return PlaytimeGifts
