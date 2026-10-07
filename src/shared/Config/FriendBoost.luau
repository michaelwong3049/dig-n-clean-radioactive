--!strict
--[[
	FriendBoost.luau — +10% cash while a Roblox friend is in the same server
	(Services/FriendBoostService, StatResolver).

	LIVE, NEVER SAVED. FriendBoostService writes `data.friendBoost` on join, whenever
	anyone joins or leaves, and clears it before the save closes, so it can never leak
	into offline earnings or a later session. The moment the last friend leaves, the
	bonus is gone.

	FLAT, NOT PER FRIEND. One friend or five, it is the same +10% (user's call,
	2026-10-07: "10% cash bonus with a friend in your game").
]]

local FriendBoost = {}

-- On every sale and every stand's income, like the group chest's +10%.
FriendBoost.CASH_MULT = 1.1

--- Player attribute the client can read: true while a friend is here.
FriendBoost.ATTR = "FriendBoost"

--- The multiplier for a profile's live flag.
function FriendBoost.cashMultiplier(active: boolean?): number
	return if active then FriendBoost.CASH_MULT else 1
end

--- "10", for the toasts.
function FriendBoost.cashPercent(): number
	return math.floor((FriendBoost.CASH_MULT - 1) * 100 + 0.5)
end

return FriendBoost
