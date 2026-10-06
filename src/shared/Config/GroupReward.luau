--!strict
--[[
	GroupReward.luau — the group chest just outside Stage 1 (Services/GroupRewardService,
	client GroupRewardController). Join the group (and like the game) for a one-time gift.

	ONLY THE GROUP IS CHECKED. Roblox has no API that tells a game whether a player
	liked it, so "like the game" is asked for on the sign and never verified; group
	membership is the real gate (user's call, 2026-10-02).

	ONCE PER PLAYER, EVER: `data.groupRewardClaimed` on the save.

	STEP IN THE RING. A gold ring on the ground round the chest; standing inside it
	opens the rewards card (GroupRewardController), whose CLAIM button asks the server.
	There is no E prompt -- the ring is the one way in.
]]

local GroupReward = {}

GroupReward.GROUP_ID = 924430099

GroupReward.CASH = 25_000
GroupReward.SPEED = 25_000
GroupReward.LUCK_SECONDS = 15 * 60
-- PERMANENT: once claimed, every sale and every stand's income pays this much more
-- for good (StatResolver folds it into sellMultiplier + yieldMultiplier, like the
-- 2x Cash pass). Keyed off `data.groupRewardClaimed`, so it never expires.
GroupReward.CASH_MULT = 1.1

-- On the camp side of the Stage 1 entrance, by the brown shoulder wall that runs out
-- from the entrance's left corner (its camp-facing face is X 96, from Z -85 outward).
-- The camp floor's top is Y -1.5. The ring's edge just clears the wall; the chest's
-- front faces the camp (-X). 2026-10-04: 8 studs toward the entrance (was Z -104).
-- 2026-10-04, on request: MOVED TO THE MIDDLE of the compact shop square, on PLAZA_MID
-- (the booths ring it, the Trader in the SE corner), standing on the raised shop floor
-- (Hub PLAZA.topY -1.5 + SHOP_FLOOR_LIFT 0.35). Respawns land 13 out round it.
-- 2026-10-04, on request ("move leaderboards and the group chest near the backend"): to
-- the back of the camp, on the grey floor between the two rows of bases, in front of
-- the leaderboards on the back wall (x -147). The grey path's top is PLAZA.topY -1.5 +
-- PLAZA_LIFT 0.15. 2026-10-05, on request: 12 studs toward the shops (+X, was x -125);
-- the ring now reaches x ~ -122.5, further still off the boards.
-- 2026-10-06, on request: 18 nearer the shops (was x -113), on its own raised square
-- (build/PrizeSquare, centred here) with a path to the shop square; Y is that square's
-- top, PLAZA.topY -1.5 + SHOP_FLOOR_LIFT 0.35.
GroupReward.CHEST_POSITION = Vector3.new(-95, -1.15, 0)
-- Yaw. The imported model's front is its local -Z (the opposite of the part chest's),
-- so +90 degrees is what turns that front to the camp (world -X). User flagged -90 as
-- facing the wrong way.
GroupReward.CHEST_FACING = -math.pi / 2 -- front to world +X, toward Stage 1 and the shops (2026-10-04)

GroupReward.RING_RADIUS = 8.5 -- to the ring's centre line
GroupReward.RING_WIDTH = 1.2

--- Player attribute the client reads to show the card as claimed.
GroupReward.CLAIMED_ATTR = "GroupRewardClaimed"

--- The line on the sign and the toast: what the chest pays.
function GroupReward.rewardText(): string
	return `$25K Cash  •  25K Speed  •  2x Luck {math.floor(GroupReward.LUCK_SECONDS / 60)} min  •  +{GroupReward.cashPercent()}% Cash forever`
end

--- The permanent cash bonus as a whole percent (10 for CASH_MULT 1.1).
function GroupReward.cashPercent(): number
	return math.floor((GroupReward.CASH_MULT - 1) * 100 + 0.5)
end

--- The permanent cash multiplier for a profile: CASH_MULT once claimed, else 1.
function GroupReward.cashMultiplier(claimed: boolean?): number
	return if claimed then GroupReward.CASH_MULT else 1
end

--- Whether a point is standing in the ring (flat distance; a few studs of height either
--- way so jumping inside it still counts).
function GroupReward.inRing(position: Vector3): boolean
	local centre = GroupReward.CHEST_POSITION
	local flat = Vector3.new(position.X - centre.X, 0, position.Z - centre.Z)
	return flat.Magnitude <= GroupReward.RING_RADIUS + GroupReward.RING_WIDTH / 2
		and math.abs(position.Y - centre.Y) < 12
end

return GroupReward
