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

-- Skews the roll toward MIN. 1 would be a flat/uniform roll; every step above 1
-- makes the top end rarer. At 3, a 2.5x "giga nuke" (the top ~1% of rolls) needs
-- the raw [0,1) roll above ~0.997 -- a real jackpot, not just an uncommon sight.
Payload.POWER = 3

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

--- This dig's size/value multiplier, in Payload.MIN..MAX. Deterministic per uid
--- -- call it as often as you like from anywhere the item shows up; it never
--- needs to be rolled once and threaded through.
function Payload.forUid(uid: string): number
	local rng = Random.new(seedOf("payload:" .. uid))
	local t = rng:NextNumber() ^ Payload.POWER
	return Payload.MIN + (Payload.MAX - Payload.MIN) * t
end

return Payload
