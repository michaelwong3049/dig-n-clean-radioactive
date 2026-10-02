--!strict
--[[
	CashBoost.luau — 2x CASH, for a while. Bought only as part of a pack (Config/Packs);
	there is no product that sells it on its own yet.

	It is the Lucky Clover's clock for money instead of luck (Config/LuckBoost): seconds
	BANKED on the profile (`data.cashBoostLeft`), counting down only while the player is
	in a server, so logging off never burns what they paid for. Buying more while one is
	running adds to it.

	WHAT IT DOUBLES: every sale and every stand's income -- StatResolver folds it into
	BOTH sellMultiplier and yieldMultiplier, the same two the 2x Cash pass reaches. The
	two STACK (x2 x x2 = x4), on request, like the pass and the clover do for luck.
]]

local CashBoost = {}

CashBoost.MULT = 2
-- A sanity ceiling, not a design lever (LuckBoost.MAX_BANKED_SECONDS's reasoning).
CashBoost.MAX_BANKED_SECONDS = 24 * 60 * 60

-- Server time the boost runs out, on the Player; 0 = none. An attribute rather than a
-- remote so a late joiner's HUD has it on arrival (LuckBoost's replication note).
CashBoost.PERSONAL_ATTR = "CashBoostEndsAt"

function CashBoost.multiplier(active: boolean): number
	return if active then CashBoost.MULT else 1
end

return CashBoost
