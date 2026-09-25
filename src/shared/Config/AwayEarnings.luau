--!strict
--[[
	AwayEarnings.luau — the "While you were away" card a returning player gets on
	login (client AwayEarningsController), and the Robux product that doubles it.

	The money itself is not new. Your stands have always paid while you are offline
	(Tuning.EXHIBIT_OFFLINE_RATE of their live $/s, for at most
	Tuning.EXHIBIT_OFFLINE_BANK_HOURS), but it used to drop silently into the wallet
	on join, so nobody knew it had happened. Now it waits on the profile
	(`data.awayPending`) until the player presses COLLECT, so the number is shown
	before it is paid, and the card can offer DOUBLE IT for Robux.

	Nothing is lost by not pressing it. A player who leaves with the card still up
	keeps `awayPending` in their save, and it is added to their next offer.
]]

local AwayEarnings = {}

-- A quick rejoin is not "away". Under this many seconds offline, the credit goes
-- straight into the wallet the old way and no card shows.
AwayEarnings.MIN_AWAY_SECONDS = 60

-- The Developer Product's id from the Creator Dashboard (Monetization -> Developer
-- Products). 0 = not set up yet: DOUBLE IT shows COMING SOON and is disabled, and
-- Services/ProductService registers nothing. /away tests the card without it.
AwayEarnings.PRODUCT_ID = 0

-- What DOUBLE IT pays, as a multiple of the amount on the card.
AwayEarnings.DOUBLE_MULT = 2

return AwayEarnings
