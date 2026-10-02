--!strict
--[[
	GearProducts.luau — every gear tier you can buy with Robux instead of cash.

	One Developer Product per tier (Creator Dashboard -> Monetization -> Developer
	Products), keyed by the tier's NAME rather than its number, so a tier added or
	moved in Config/Gear can't shift every id onto the wrong rung. A tier missing here
	(Bent Coil, the free starters) simply has no purple button.

	The Robux price lives on the product and the card reads it from there, so a price
	change on the dashboard needs no code change. Selling it follows the cash rules: the
	button only shows on a tier you don't own, at the stall that sells it. The grant
	itself is ShopService's (`grantRobuxTier`), through ProductService.
]]

local Gear = require(script.Parent.Gear)

local GearProducts = {}

local BY_NAME: { [string]: { [string]: number } } = {
	Detector = {
		["Scrap Sweeper"] = 3716008913,
		["Surplus Geiger"] = 3716008995,
		["Pulse Array"] = 3716009586,
		["Isotope Scanner"] = 3716010031,
		["Resonance Mapper"] = 3716010262,
		["Deep Core Array"] = 3716010602,
		["The Oracle"] = 3716010737,
		["Vein Whisperer"] = 3716010889,
		["Aurora Rake"] = 3716011004,
		["Strata Lance"] = 3716011128,
		["Leyline Tap"] = 3716011266,
		["Null Compass"] = 3716011327,
		["Prime Meridian"] = 3716011392,
	},
	Magnet = {
		["Salvage Magnet"] = 3716011649,
		["Electromagnet"] = 3716012144,
		["Winch Coil"] = 3716012184,
		["Rail Coil"] = 3716012252,
		["Singularity Coil"] = 3716012298,
		["Lattice Magnet"] = 3716012447,
		["Solar Magnet"] = 3716012563,
		["Void Magnet"] = 3716012624,
		["Nebula Magnet"] = 3716012693,
		["Omega Magnet"] = 3716012789,
	},
	Cleaner = {
		["Patched Fire Hose"] = 3716016289,
		["Pressure Lance"] = 3716016333,
		["Chem Injector"] = 3716016761,
		["Ion Cannon"] = 3716016819,
		["Plasma Lance"] = 3716016857,
		["Singularity Nozzle"] = 3716016962,
		["Cryo Nova"] = 3716017065,
		["Solar Forge"] = 3716017112,
		["Quantum Rift"] = 3716017232,
		["Celestial Deluge"] = 3716017266,
	},
	Aura = {
		["Static Veil"] = 3716013691,
		["Lead Halo"] = 3716013759,
		["Ion Shroud"] = 3716013885,
		["Isotope Mantle"] = 3716014993,
		["Containment Nimbus"] = 3716015069,
		["Toxic Aurora"] = 3716015270,
		["Eclipse Veil"] = 3716015378,
		["Twilight Singularity"] = 3716015485,
		["Seraph"] = 3716015531,
		["Crimson Vortex"] = 3716015563,
	},
}

--- The product id for `track`'s tier `tier`, or nil when that tier isn't sold for Robux.
function GearProducts.idFor(track: string, tier: number): number?
	local names = BY_NAME[track]
	if names == nil or tier < 1 or tier > Gear.maxTier(track) then
		return nil
	end
	return names[Gear.tier(track, tier).name]
end

--- Every (productId, track, tier) sold, resolved against Config/Gear. A name here that
--- no longer matches a tier is a typo or a rename, and it warns rather than selling
--- nothing in silence.
function GearProducts.all(): { { id: number, track: string, tier: number } }
	local out = {}
	for track, names in BY_NAME do
		local found: { [string]: boolean } = {}
		for tier = 1, Gear.maxTier(track) do
			local name = Gear.tier(track, tier).name
			local id = names[name]
			if id then
				found[name] = true
				table.insert(out, { id = id, track = track, tier = tier })
			end
		end
		for name in names do
			if not found[name] then
				warn(`[GearProducts] {track} "{name}" matches no tier in Config/Gear -- not sold`)
			end
		end
	end
	return out
end

return GearProducts
