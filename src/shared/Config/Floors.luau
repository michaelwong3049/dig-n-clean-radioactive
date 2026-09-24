--!strict
--[[
	Floors.luau — the storeys a base can be built up to.

	A base starts as ONE floor: the ground deck with its 3 x 4 gallery of stands. Two
	more floors can be bought on top of it, one at a time, for cash, so a base tops out
	at MAX = 3 floors. Every floor past the ground carries UPPER_SLOTS stands (a 4 x 2
	gallery), reached by a flight of stairs from the floor below.

	SLOT NUMBERS RUN ON ACROSS FLOORS, they do not restart. Slots 1..12 are the ground
	floor exactly as they always were (so every existing save's `pedestals` entries
	keep pointing at the stand they were placed on), 13..20 are floor 2 and 21..28 are
	floor 3. `data.exhibit.floors` is the only new piece of saved state; how many
	stands that unlocks is always derived from it (`slotsFor`), never stored on its own.

	The geometry lives in build/Plots (buildFloor); ExhibitService sells the floors and
	shows/hides them per owner. This file is the numbers both of them — and the client's
	"YOUR BASE" beacon, which floats higher as the base grows — agree on.
]]

local Floors = {}

Floors.MAX = 3
Floors.GROUND_SLOTS = 12
Floors.UPPER_SLOTS = 8

--- Deck-top to deck-top, in studs. Tall enough that a stand on its plinth, a GIGA
--- roll on top of it and its trophy card all clear the deck overhead with room to
--- spare. The stairs rise exactly this far (Plots.buildFloor), so changing it
--- changes the step count too.
Floors.HEIGHT = 16

--- Cash price of each floor, by the floor it buys. Floor 1 is the ground and free.
--- Sized against the gear ladders (Config/Gear, Config/Treadmill): floor 2 lands
--- around a mid-ladder rung, floor 3 around the top rungs — a real goal, not a
--- first-session purchase, because eight more stands is a lot of passive income.
Floors.PRICES = {
	[2] = 75000,
	[3] = 400000,
}

--- Every stand across every floor. Loops that clear or scan "all stands" walk this.
Floors.MAX_SLOTS = Floors.GROUND_SLOTS + (Floors.MAX - 1) * Floors.UPPER_SLOTS

--- How many floors this many is, clamped to a real count (a save carries a number,
--- and a number can be anything).
function Floors.clamp(floors: number?): number
	local n = if type(floors) == "number" and floors == floors then floors else 1
	return math.clamp(math.floor(n), 1, Floors.MAX)
end

--- How many stands a base with `floors` floors has unlocked.
function Floors.slotsFor(floors: number?): number
	return Floors.GROUND_SLOTS + (Floors.clamp(floors) - 1) * Floors.UPPER_SLOTS
end

--- Which floor a slot stands on, and its 1-based index among that floor's stands.
--- nil for a slot number that is on no floor at all.
function Floors.floorOf(slot: number): (number?, number?)
	if slot < 1 or slot > Floors.MAX_SLOTS then
		return nil, nil
	end
	if slot <= Floors.GROUND_SLOTS then
		return 1, slot
	end
	local upper = slot - Floors.GROUND_SLOTS - 1
	return 2 + math.floor(upper / Floors.UPPER_SLOTS), upper % Floors.UPPER_SLOTS + 1
end

--- The first slot number on `floor`.
function Floors.firstSlot(floor: number): number
	if floor <= 1 then
		return 1
	end
	return Floors.GROUND_SLOTS + (floor - 2) * Floors.UPPER_SLOTS + 1
end

--- The price of the floor AFTER `owned`, or nil when the base is already at MAX.
function Floors.nextPrice(owned: number?): number?
	return Floors.PRICES[Floors.clamp(owned) + 1]
end

return Floors
