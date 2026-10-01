--!strict
--[[
	Floors.luau — the storeys a base can be built up to.

	A base starts as ONE floor: the ground deck with its 3 x 4 gallery of stands. Two
	more floors can be bought on top of it, one at a time, for cash, so a base tops out
	at MAX = 3 floors. Every floor past the ground carries UPPER_SLOTS stands (a 3 x 4
	gallery), reached by a flight of stairs from the floor below.

	SLOT NUMBERS RUN ON ACROSS FLOORS, they do not restart. Slots 1..12 are the ground
	floor exactly as they always were (so every existing save's `pedestals` entries
	keep pointing at the stand they were placed on), 13..24 are floor 2 and 25..36 are
	floor 3. `data.exhibit.floors` is the only new piece of saved state; how many
	stands that unlocks is always derived from it (`slotsFor`), never stored on its own.

	The geometry lives in build/Plots (buildFloor); ExhibitService sells the floors and
	shows/hides them per owner. This file is the numbers both of them — and the client's
	"YOUR BASE" beacon, which floats higher as the base grows — agree on.
]]

local Floors = {}

Floors.MAX = 3
Floors.GROUND_SLOTS = 12
Floors.UPPER_SLOTS = 12

--- Deck-top to deck-top, in studs. Tall enough that a stand on its plinth, a GIGA
--- roll on top of it and its trophy card all clear the deck overhead with room to
--- spare. The stairs rise exactly this far (Plots.buildFloor), so changing it
--- changes the step count too. 16, then 28 on request ("way taller"): the flights
--- now run the whole depth of the deck to a landing at the back. 33 on request
--- ("shorten the ~2-stud treads to 1.75"): 33 steps over the same 58.6 run = 1.78 treads.
Floors.HEIGHT = 33

--- Cash price of each floor, by the floor it buys. Floor 1 is the ground and free.
--- Sized in the economy pacing pass (see Config/Gear's header) with no stand income
--- cap: floor 2 is a Stage 4 purchase, floor 3 a Stage 8 one. Twelve more stands
--- doubles or triples passive income, so each is priced like a stage's worth of gear.
--- Raised on request to 50M (floor 2) and 1B (floor 3).
Floors.PRICES = {
	[2] = 50000000,
	[3] = 1000000000,
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
