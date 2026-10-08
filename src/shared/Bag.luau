--!strict
--[[
	Bag.luau — how many backpack slots a player is using.

	The backpack holds two lists that share one set of slots: `data.carry` (nukes,
	Decay.CarriedItem -- and dirty crates disguised as crusted nukes) and `data.crates`
	(CLEAN crates, Config/Crates, `{ uid, crateId }`). See Config/Crates' header for
	why a crate only joins `data.crates` once it is washed. Every "is the bag full?"
	question has to count both,
	and this is the one place that knows it. Shared so a service at any depth of the
	require graph can ask without reaching for CarryService.
]]

local Bag = {}

export type CrateEntry = {
	uid: string,
	crateId: string,
}

function Bag.used(data: any): number
	return #data.carry + #(data.crates or {})
end

--- The crate entry with this uid and its index, or nil.
function Bag.findCrate(data: any, uid: string): (CrateEntry?, number?)
	for index, entry in data.crates or {} do
		if entry.uid == uid then
			return entry, index
		end
	end
	return nil, nil
end

--- HEARTED NUKES (InventoryController: right-click a slot, or double-tap on touch).
--- A heart is the player's "keep this": it rides on the item record itself
--- (`item.hearted`), so it follows the nuke into the locker and onto a stand, and
--- every way a nuke can leave you for good -- the trader, a gift, the Merge Reactor,
--- the Slag Furnace, a bomb drop -- asks here and refuses with HEART_REFUSAL.
Bag.HEART_REFUSAL = "that nuke is hearted \u{2014} right-click it (double-tap on mobile) to unheart"

function Bag.isHearted(item: any): boolean
	return type(item) == "table" and item.hearted == true
end

return Bag
