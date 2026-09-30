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
	It still carries crust, a modifier and a pull fuse like any other nuke.

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

-- The drop's aura, as the server builds it, carries its rarity under this attribute
-- and streams to every client wherever they stand (ModelStreamingMode.Persistent),
-- so anybody can see it from across the map: the client lights it without waiting for
-- a detector reading and stands a pillar of light on it (FieldController).
RareDrop.AURA_ATTR = "RareDrop"

-- Relative weights, before the aurora. ~70 / 24 / 5 / 1 %.
RareDrop.TIER_WEIGHTS = {
	{ rarity = "Epic", weight = 70 },
	{ rarity = "Legendary", weight = 24 },
	{ rarity = "Mythic", weight = 5 },
	{ rarity = "Anomaly", weight = 1 },
}

-- ── Replication (ReplicatedStorage attributes) ─────────────────────────────────
-- A live drop: its end time (server time, `workspace:GetServerTimeNow()`), stage and
-- rarity. EndsAt absent / 0 = no drop live.
RareDrop.ENDS_ATTR = "RareDropEndsAt"
RareDrop.STAGE_ATTR = "RareDropStage"
RareDrop.RARITY_ATTR = "RareDropRarity"
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
