--!strict
--[[
	FriendBoost.luau — +10% cash for every Roblox friend in the same server, up to
	MAX_FRIENDS of them (Services/FriendBoostService, StatResolver).

	LIVE, NEVER SAVED. FriendBoostService writes `data.friendBoost` (how many friends are
	here) on join, whenever anyone joins or leaves, and clears it before the save closes,
	so it can never leak into offline earnings or a later session. The moment the last
	friend leaves, the bonus is gone.

	PER FRIEND, CAPPED. It was a flat +10% for one friend or five (2026-10-07); the user
	asked for the percent to depend on how many friends are here (2026-10-08), so each
	one adds PER_FRIEND, up to MAX_FRIENDS (+50%). The line above the speed badge
	(SpeedController) shows the current percent.
]]

local FriendBoost = {}

-- Each friend here adds this much to every sale and every stand's income.
FriendBoost.PER_FRIEND = 0.1
-- Friends past this many add nothing more.
FriendBoost.MAX_FRIENDS = 5

--- Player attribute the client can read: how many friends count right now (0 = none).
FriendBoost.ATTR = "FriendBoost"

--- How many friends actually count toward the bonus.
function FriendBoost.counted(friends: number?): number
	return math.clamp(math.floor(friends or 0), 0, FriendBoost.MAX_FRIENDS)
end

--- The multiplier for a profile's live friend count.
function FriendBoost.cashMultiplier(friends: number?): number
	return 1 + FriendBoost.PER_FRIEND * FriendBoost.counted(friends)
end

--- "20" for two friends, for the toasts and the speed-badge line.
function FriendBoost.cashPercent(friends: number?): number
	return math.floor(FriendBoost.PER_FRIEND * FriendBoost.counted(friends) * 100 + 0.5)
end

return FriendBoost
