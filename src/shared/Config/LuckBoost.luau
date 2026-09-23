--!strict
--[[
	LuckBoost.luau — 2x LUCK, for a while. The clover in the bottom-right corner.

	Two ways to be boosted, and they stack:

	  THE VIOLET AURORA   a server-wide event. Every EVENT_GAP_MIN..MAX seconds of
	                      quiet, the sky turns violet for EVENT_SECONDS and everybody
	                      on the server is lucky at once (Services/LuckBoostService).
	                      It is a shared moment on purpose -- PLAN §10.8's storms
	                      argument: a whole server making the same decision at once is
	                      what makes a shared server feel alive.

	  THE LUCKY CLOVER    a personal boost bought with Robux from the Shop tile
	                      (PRODUCT_ID, PLAN §11's "Lucky Sweep" slot). PRODUCT_SECONDS
	                      per purchase; buying again while one is running adds to it.
	                      The time is BANKED, not scheduled: it only counts down while
	                      you are in a server, so logging off never burns what you paid
	                      for. Saved as `data.luckBoostLeft` (seconds).

	Both at once is MULT x MULT (4x). That is the reward for buying during an event
	rather than a reason not to, and it is what the clover's "x4" says.

	WHAT "2x LUCK" MEANS -- ONE WORD, TWO LUCKS. The game has two luck numbers and
	they are deliberately separate (Config/Gear's header): the detector's DIG luck and
	the wash pad's luck. The boost doubles both, each in its own unit:

	  * DIG: every Rare-or-better item's roll weight is multiplied by the boost, on
	    top of the detector's own `luckBias` (Config/Items.luckBias). So a Legendary
	    is twice as likely to come up, whatever detector you hold. It does NOT double
	    the detector's `luck` stat, and that was measured, not assumed: luckBias is
	    capped (Items.DIG_LUCK_BIAS_CAP), so doubling the stat grows Rare far faster
	    than the capped top end and LOWERS Legendary+ odds for a maxed detector -- an
	    Oracle in the Crater went 61.5% -> 42.4% Legendary+ under a "2x luck" event.
	    Multiplying the weight is monotone for every detector in every stage.
	  * WASH PAD: the luck multiplier itself doubles (StatResolver's `luckMultiplier`),
	    the same slot PLAN §11's 2x Luck gamepass was always meant to fill. Config/
	    Liquids has no cap, so there doubling the stat is the honest reading, and the
	    rarest liquids gain the most (weight x luck^luckBias).

	UPTIME, written down because it is the balance number. A 10-minute event after
	20-30 minutes of quiet is ~25-33% of a session spent boosted. That is generous
	on purpose (the user asked for it) and it is the first knob to turn if rare
	finds start to feel cheap: widen EVENT_GAP_*, not MULT.
]]

local LuckBoost = {}

--- What a boost multiplies luck by. The event and a bought clover each apply it once.
LuckBoost.MULT = 2

-- ── The server-wide event ──────────────────────────────────────────────────────
LuckBoost.EVENT_NAME = "Violet Aurora"
LuckBoost.EVENT_SECONDS = 10 * 60
-- Quiet time between one event ENDING and the next one starting, rolled uniformly
-- per gap. Measured from the end, not the start, so a 10-minute event can never
-- shorten the quiet stretch after it.
LuckBoost.EVENT_GAP_MIN = 20 * 60
LuckBoost.EVENT_GAP_MAX = 30 * 60

-- ── The Robux product ──────────────────────────────────────────────────────────
-- The Developer Product's id from the Creator Dashboard (Monetization -> Developer
-- Products). 0 = not set up yet: the Shop card shows but its button stays disabled,
-- and Services/ProductService registers nothing. Use /luckboost to test without it.
LuckBoost.PRODUCT_ID = 0
LuckBoost.PRODUCT_SECONDS = 10 * 60
-- The most boost time one player can bank. A sanity ceiling, not a design lever --
-- nobody should be able to hold a week of 2x from a stuck purchase loop.
LuckBoost.MAX_BANKED_SECONDS = 24 * 60 * 60

-- ── Replication ────────────────────────────────────────────────────────────────
-- Both clocks cross to clients as ATTRIBUTES rather than a Net remote, because both
-- are state a late joiner needs immediately and an attribute is already there when
-- they arrive. Values are `workspace:GetServerTimeNow()` seconds; 0 / absent = off.
LuckBoost.EVENT_ATTR = "LuckEventEndsAt" -- on ReplicatedStorage
LuckBoost.EVENT_START_ATTR = "LuckEventStartedAt" -- on ReplicatedStorage
LuckBoost.PERSONAL_ATTR = "LuckBoostEndsAt" -- on the Player

--- The combined multiplier: MULT per active source, so 1, 2 or 4.
function LuckBoost.multiplier(eventActive: boolean, personalActive: boolean): number
	return (if eventActive then LuckBoost.MULT else 1) * (if personalActive then LuckBoost.MULT else 1)
end

return LuckBoost
