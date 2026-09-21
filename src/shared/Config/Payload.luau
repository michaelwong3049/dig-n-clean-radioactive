--!strict
--[[
	Payload.luau — every DIG gets its own random size/value roll, independent of
	the item's own intrinsic weight (Config/Weight).

	Config/ RULE (Tuning.luau's header): data only, no game logic, no requires of
	anything outside Config/. This file requires nothing.

	WHY THIS IS SEPARATE FROM Config/Weight. Weight is INTRINSIC per item TYPE — a
	Bottle Cap is always ~0.05 kg, a buried safe always ~220, and it never varies
	between two Bottle Caps. Payload is the opposite: a per-DIG roll, so two Rusty
	Nukes sitting side by side can be wildly different sizes. They stack
	multiplicatively (both feed the same `model:ScaleTo`/value formulas) rather
	than one replacing the other — a heavy item type rolling a big payload is a
	genuine giant; a light item type rolling a big payload is still bigger than
	its usual self, just not as big in absolute terms as the heavy one.

	SEEDED ON THE ITEM'S OWN uid, NEVER STORED. Same trick ItemCrust.encase uses
	for crust shape, for the same reason: the payload has to read the same
	everywhere the item shows up (the haul crust's size, the wash stand, held in
	hand, on exhibit) without persisting a new field through every place an item
	record gets copied or reconstructed (DeconService's locker move, ExhibitService's
	pedestal round-trip — the pedestal record is a stripped-down schema that would
	silently drop anything not already in it). Re-deriving from `uid` on every read
	means there is nothing to lose: `Payload.forUid(item.uid)` gives the same
	number today, tomorrow, and after a server restart, forever, for that one dig.

	SAME MULTIPLIER DRIVES BOTH SIZE AND VALUE, on request — a 0.6x roll is a 0.6x
	nuke worth 0.6x as much; a 2.5x roll is a 2.5x giant worth 2.5x as much. No
	separate dampened curve the way Weight.valueMult tames Weight.sizeScale.
]]

local Payload = {}

Payload.MIN = 0.6
Payload.MAX = 2.5

-- The odds, band by band. Each band runs from the previous band's `upTo` (the
-- first from MIN) to its own, and `chance` is the percent of digs that land in
-- it -- spread evenly inside the band. Bands must run in order, end at MAX, and
-- their chances must total 100 (Spec pins all three). Most digs sit around 1x;
-- the OVERSIZED/GIGA bands above 1.6x are ~10% of digs between them.
Payload.BANDS = {
	{ upTo = 0.8, chance = 24 },
	{ upTo = 1.0, chance = 28 },
	{ upTo = 1.6, chance = 38 },
	{ upTo = 2.2, chance = 8 },
	{ upTo = 2.5, chance = 2 },
}

-- THE ONE THING A DIG CAN TELL YOU. What comes out of the ground is a nameless lump
-- (Shared/ItemCrust) whose rarity you already read off the spot and the haul panel,
-- so the dig itself announces nothing -- except a big payload roll, which is news:
-- it is worth that many times its usual price, and nothing else on screen says so.
-- Highest `min` first; the first tier a roll clears names it, below the last one
-- the dig stays silent. With the BANDS above, ~10% of digs clear 1.6x and ~2%
-- clear 2.2x.
Payload.CALLOUTS = {
	{ min = 2.2, label = "GIGA" },
	{ min = 1.6, label = "OVERSIZED" },
}

--- The callout tier a roll earns, or nil for an ordinary-sized dig.
function Payload.calloutFor(mult: number): string?
	for _, tier in Payload.CALLOUTS do
		if mult >= tier.min then
			return tier.label
		end
	end
	return nil
end

--- A stable integer for `Random.new` out of a carry uid. Salted differently from
--- ItemCrust's own `seedOf` (same shape, different string prefix) so a payload
--- roll doesn't visibly correlate with that item's crust arrangement -- two
--- unrelated facts about the same dig, not one fact wearing two names.
local function seedOf(uid: string): number
	local total = 0
	for index = 1, #uid do
		total = (total * 31 + string.byte(uid, index)) % 2147483647
	end
	return total
end

--- The multiplier a raw [0,1) roll maps to under Payload.BANDS: walk the bands
--- until the roll's share of 100 runs out, then land that far across the band.
--- Split out of forUid so Spec can pin the band edges exactly, not by sampling.
function Payload.fromRoll(roll: number): number
	local pick = roll * 100
	local low = Payload.MIN
	for _, band in Payload.BANDS do
		if pick < band.chance then
			return low + (band.upTo - low) * (pick / band.chance)
		end
		pick -= band.chance
		low = band.upTo
	end
	return Payload.MAX
end

--- This dig's size/value multiplier, in Payload.MIN..MAX. Deterministic per uid
--- -- call it as often as you like from anywhere the item shows up; it never
--- needs to be rolled once and threaded through.
function Payload.forUid(uid: string): number
	local rng = Random.new(seedOf("payload:" .. uid))
	return Payload.fromRoll(rng:NextNumber())
end

return Payload
