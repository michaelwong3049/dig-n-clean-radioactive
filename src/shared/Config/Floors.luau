--!strict
--[[
	Floors.luau — the storeys a base can be built up to.

	A base starts as ONE floor: the ground deck with its gallery of 12 stands (a full
	3 x 4 grid; it was cut to 9 and put back on request). Two more floors
	can be bought on top of it, one at a time, for cash, so a base tops out at MAX = 3
	floors. Every floor past the ground carries UPPER_SLOTS stands in the same layout,
	reached by a flight of stairs from the floor below.

	SLOT NUMBERS RUN ON ACROSS FLOORS, they do not restart. Slots 1..12 are the ground
	floor, 13..24 are floor 2 and 25..36 are floor 3. (Cut to 9 a floor and back to 12
	before anyone had played, so no save needs moving.) `data.exhibit.floors` is the only new piece of saved state; how many
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
--- Raised on request to 50M (floor 2) and 1B (floor 3), then moved with their stages in
--- the early-easier / late-harder refit (Config/Gear's header): floor 2 is part of the
--- Stage 5 bill (x0.78 -> 40M), floor 3 of the Stage 9 bill (x1.55 -> 1.5B). Floor 3 then
--- went to 1.4B when floors dropped to nine stands, then 8.7M / 2.2B in the new-map
--- price curve, with twelve stands again (Config/Gear's header).
Floors.PRICES = {
	[2] = 8700000,
	[3] = 2200000000,
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
