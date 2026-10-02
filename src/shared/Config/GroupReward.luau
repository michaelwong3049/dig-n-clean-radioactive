--!strict
--[[
	GroupReward.luau — the chest against Stage 1's brown wall (Services/GroupRewardService,
	client GroupRewardController). Join the group (and like the game) for a one-time gift.

	ONLY THE GROUP IS CHECKED. Roblox has no API that tells a game whether a player
	liked it, so "like the game" is asked for on the sign and never verified; group
	membership is the real gate (user's call, 2026-10-02).

	ONCE PER PLAYER, EVER: `data.groupRewardClaimed` on the save.
]]

local GroupReward = {}

GroupReward.GROUP_ID = 924430099

GroupReward.CASH = 25_000
GroupReward.SPEED = 25_000
GroupReward.LUCK_SECONDS = 5 * 60

-- Stage 1 runs X 100..376 with its brown north wall (the one on your LEFT walking in
-- from camp) at Z -89, inner face -85; the field floor's top is Y -1.5. The chest sits
-- near the entrance against that face, its front turned to the field (+Z).
GroupReward.CHEST_POSITION = Vector3.new(124, -1.5, -82)

--- Player attribute the client reads to hide the prompt once it has paid out.
GroupReward.CLAIMED_ATTR = "GroupRewardClaimed"

--- The line on the sign and the toast: what the chest pays.
function GroupReward.rewardText(): string
	return `$25K Cash  •  25K Speed  •  2x Luck {math.floor(GroupReward.LUCK_SECONDS / 60)} min`
end

return GroupReward
