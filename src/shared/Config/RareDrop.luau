--!strict
--[[
	RareDrop.luau — THE ANNOUNCED DROP. Every GAP_MIN..MAX seconds the server buries one
	guaranteed Epic-or-better nuke in a random dig stage and tells the whole server
	where: a banner on every screen, "A LEGENDARY DROP SURFACED IN OOZE MARSH". Whoever
	pulls it out first keeps it. Nobody in LIFETIME seconds and it sinks back.

	WHAT IT IS, IN THE FIELD. An ordinary signal (Services/DigService.plantRareDrop) with
	three differences:
	  * its identity is FIXED. No per-player luck re-roll -- the rarity the banner
	    promised is the rarity everyone digs up. Luck is spent once, at the roll.
	  * it is buried at the shallowest band, so a starter detector registers it: the
	    race is to get there, not to own the right gear. Soil hardness still slows a
	    weak magnet (soft gate, not a wall -- see magnet-over-tier-grind).
	  * its aura is ALWAYS lit, for everyone, not only inside somebody's detector
	    radius. "Surfaced in Ooze Marsh" plus a glow you can spot across the stage is
	    what makes it a race rather than a needle in 75 haystacks.
	It still carries crust and a pull fuse like any other nuke, and always at least
	one buff (BUFFS below).

	THE ROLL. TIER_WEIGHTS below, and the Violet Aurora (Config/LuckBoost) amplifies
	it: every rung above Epic is multiplied by the server's luck boost once per rung,
	so under a 2x aurora Legendary is x2, Mythic x4, Anomaly x8. That is "server luck"
	-- the drop is server-wide, so a player's own clover does not bend it.

	A STAGE THAT STOCKS NO ITEM OF THE ROLLED RARITY (Stage 1 has no Mythic or
	Anomaly) steps DOWN a rung until it finds one. The banner reads the rarity that was
	actually buried, never the one that was rolled.

	Replicated like LuckBoost's clocks: attributes on ReplicatedStorage, so a late
	joiner sees a live drop the moment they arrive.
]]

local RareDrop = {}

-- Quiet time between one drop ENDING (claimed, blown up or sunk) and the next.
RareDrop.GAP_MIN = 5 * 60
RareDrop.GAP_MAX = 6 * 60
-- How long a drop waits for somebody before it sinks back.
RareDrop.LIFETIME = 4 * 60

-- How much longer the drop takes to pull out of the ground than the same nuke would
-- normally (DigService's `required`). Paired with Config/Detonation's RARE_DROP_* fuse
-- so the haul is long enough for other players to show up and contest it.
RareDrop.PULL_MULT = 3
-- And never quicker than this many seconds for anyone mashing at MIN_PULL_CPS with
-- their own magnet, however strong -- so a top-tier magnet cannot snatch it before
-- anyone else arrives. Must sit well under Detonation.RARE_DROP_MIN * ARM_AT.
-- MIN_PULL_CPS is its own number, not Detonation.REF_CPS, so tightening ordinary fuses
-- does not lengthen this standoff too.
RareDrop.MIN_PULL_SECONDS = 20
RareDrop.MIN_PULL_CPS = 4

-- The drop's aura, as the server builds it, carries its rarity under this attribute
-- and streams to every client wherever they stand (ModelStreamingMode.Persistent),
-- so anybody can see it from across the map: the client lights it without waiting for
-- a detector reading and stands a pillar of light on it (FieldController).
RareDrop.AURA_ATTR = "RareDrop"

-- Relative weights, before the aurora: 50 / 34 / 12 / 4 %. Under a 2x aurora that
-- becomes ~25 / 34 / 24 / 16 %.
RareDrop.TIER_WEIGHTS = {
	{ rarity = "Epic", weight = 50 },
	{ rarity = "Legendary", weight = 34 },
	{ rarity = "Mythic", weight = 12 },
	{ rarity = "Anomaly", weight = 4 },
}

-- ── Buffs ──────────────────────────────────────────────────────────────────────
-- An announced drop is never a plain copy: it always carries at least one buff, and
-- often more. The buffs are a big size (OVERSIZED or GIGA, Config/Payload's callouts)
-- and the good qualities (Rarity.MODIFIERS), STACKED -- the first quality is the
-- copy's `modifier`, the rest ride in its `bonus` list (Rarity.qualities), and every
-- one multiplies the value. So 4 buffs = GIGA + Pristine + Irradiated + Fused.
--
-- How many, by weight: 1 (38%), 2 (50%), 3 (10%), 4 (2%).
RareDrop.BUFF_COUNT_WEIGHTS = {
	{ count = 1, weight = 38 },
	{ count = 2, weight = 50 },
	{ count = 3, weight = 10 },
	{ count = 4, weight = 2 },
}
-- The qualities a drop can stack, best first (Merge.MODIFIER_RANK's order), so the
-- best one picked is always the copy's `modifier`.
RareDrop.QUALITIES = { "Pristine", "Irradiated", "Fused" }
-- When the size buff is picked, the share of drops that come up GIGA, not OVERSIZED.
RareDrop.GIGA_SHARE = 0.25
-- The payload ranges each size outcome lands in (Payload.CALLOUTS' edges). A drop
-- that did NOT pick the size buff still lands at a full 1x or more -- never a
-- shrunken copy, and never a size sticker it did not roll.
RareDrop.SIZE_RANGES = {
	GIGA = { min = 2.2, max = math.huge },
	OVERSIZED = { min = 1.6, max = 2.2 },
	plain = { min = 1.0, max = 1.6 },
}

export type Buffs = {
	size: string?, -- "GIGA" / "OVERSIZED", nil for no size buff
	qualities: { string }, -- best first; [1] is the modifier, the rest the bonus
}

--- Roll one drop's buffs. `rng` is a Random.
function RareDrop.rollBuffs(rng: Random): Buffs
	local total = 0
	for _, entry in RareDrop.BUFF_COUNT_WEIGHTS do
		total += entry.weight
	end
	local count = 1
	local pick = rng:NextNumber() * total
	for _, entry in RareDrop.BUFF_COUNT_WEIGHTS do
		pick -= entry.weight
		if pick < 0 then
			count = entry.count
			break
		end
	end

	-- Draw `count` distinct buffs out of size + every quality.
	local pool = { "size" }
	for _, name in RareDrop.QUALITIES do
		table.insert(pool, name)
	end
	local picked: { [string]: boolean } = {}
	for _ = 1, math.min(count, #pool) do
		local index = rng:NextInteger(1, #pool)
		picked[pool[index]] = true
		table.remove(pool, index)
	end

	local qualities = {}
	for _, name in RareDrop.QUALITIES do
		if picked[name] then
			table.insert(qualities, name)
		end
	end
	local size = if picked.size then (if rng:NextNumber() < RareDrop.GIGA_SHARE then "GIGA" else "OVERSIZED") else nil
	return { size = size, qualities = qualities }
end

--- Whether a payload roll `mult` fits `size` (a Buffs.size; nil = the plain range).
function RareDrop.sizeFits(size: string?, mult: number): boolean
	local range = RareDrop.SIZE_RANGES[size or "plain"]
	return mult >= range.min and mult < range.max
end

--- The buffs as banner words, size first: "GIGA PRISTINE IRRADIATED".
function RareDrop.buffWords(size: string?, qualities: { string }): string
	local words = {}
	if size then
		table.insert(words, size)
	end
	for _, name in qualities do
		table.insert(words, string.upper(name))
	end
	return table.concat(words, " ")
end

-- ── Replication (ReplicatedStorage attributes) ─────────────────────────────────
-- A live drop: its end time (server time, `workspace:GetServerTimeNow()`), stage and
-- rarity. EndsAt absent / 0 = no drop live.
RareDrop.ENDS_ATTR = "RareDropEndsAt"
RareDrop.STAGE_ATTR = "RareDropStage"
RareDrop.RARITY_ATTR = "RareDropRarity"
-- Its buffs as banner words (RareDrop.buffWords), "GIGA PRISTINE".
RareDrop.BUFFS_ATTR = "RareDropBuffs"
-- How the last drop ended, for the closing banner: "claimed:<name>", "blown", "sunk".
-- Set once as the drop ends, next to a fresh ENDED_AT so the same outcome twice in a
-- row still fires a change.
RareDrop.OUTCOME_ATTR = "RareDropOutcome"
RareDrop.ENDED_AT_ATTR = "RareDropEndedAt"

--- Weights for one roll at `boost` (1 = no aurora). Epic is the floor rung.
function RareDrop.weights(boost: number): { { rarity: string, weight: number } }
	local out = {}
	for rung, entry in RareDrop.TIER_WEIGHTS do
		table.insert(out, { rarity = entry.rarity, weight = entry.weight * boost ^ (rung - 1) })
	end
	return out
end

--- Pick a rarity. `r` in [0, 1).
function RareDrop.rollRarity(boost: number, r: number): string
	local list = RareDrop.weights(boost)
	local total = 0
	for _, entry in list do
		total += entry.weight
	end
	local pick = r * total
	for _, entry in list do
		pick -= entry.weight
		if pick < 0 then
			return entry.rarity
		end
	end
	return list[#list].rarity
end

return RareDrop
