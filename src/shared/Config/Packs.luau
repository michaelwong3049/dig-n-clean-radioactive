--!strict
--[[
	Packs.luau — the Starter Pack and the Pro Pack: one Robux purchase, a bundle of
	things the game already sells, ONCE PER PLAYER.

	They are DEVELOPER PRODUCTS, not passes: everything inside is used up (cash, crates,
	timed boosts), and a product lets the code decide who still sees it. Services/
	PackService grants them through ProductService and marks `data.packs[key] = true`;
	the Shop's card turns OWNED off the Player attribute that mirrors it, and its button
	stops prompting.

	ONCE PER PLAYER IS A CLIENT GATE PLUS AN HONEST SERVER. Roblox has no way to refuse
	a developer product before the prompt, so a second receipt can still arrive (two
	clicks before the first grant lands, two devices). The player has paid by then, so
	the server grants the pack again rather than eat the Robux.

	The Robux prices live on the dashboard products (Starter 49, Pro 499); the Shop reads
	them from there. Contents are named here once; the Shop card lists them from this.
]]

local Packs = {}

export type Pack = {
	key: string,
	id: number,
	name: string,
	cash: number,
	-- Config/Crates ids, one entry per crate (repeat an id for two).
	crates: { string },
	luckSeconds: number, -- Lucky Clover time (Config/LuckBoost)
	cashBoostSeconds: number, -- 2x cash time (Config/CashBoost)
}

local PACKS: { Pack } = {
	{
		key = "starter",
		id = 3716047255,
		name = "Starter Pack",
		cash = 200_000,
		crates = { "liquid2", "liquid2", "nuke2" }, -- 2x Isotope Chem, 1x Field Nuke
		luckSeconds = 30 * 60,
		cashBoostSeconds = 0,
	},
	{
		key = "pro",
		id = 3716047476,
		name = "Pro Pack",
		cash = 5_000_000,
		-- 2x Quicksilver, 2x Void Nuke, 1x Cobalt Bomb
		crates = { "liquid4", "liquid4", "nuke3", "nuke3", "nuke4" },
		luckSeconds = 60 * 60,
		cashBoostSeconds = 60 * 60,
	},
}

Packs.PACKS = PACKS

-- Player attribute a bought pack is mirrored to, for the Shop card's OWNED state.
function Packs.attr(key: string): string
	return `Pack_{key}`
end

function Packs.byKey(key: string): Pack?
	for _, pack in PACKS do
		if pack.key == key then
			return pack
		end
	end
	return nil
end

--- Has this profile bought `key`?
function Packs.owns(profile: any, key: string): boolean
	local packs = profile.packs
	return packs ~= nil and packs[key] == true
end

--- The crate list folded to counts in first-seen order: { {crateId, count}, ... }.
function Packs.crateCounts(pack: Pack): { { crateId: string, count: number } }
	local out = {}
	local index: { [string]: number } = {}
	for _, crateId in pack.crates do
		local at = index[crateId]
		if at then
			out[at].count += 1
		else
			table.insert(out, { crateId = crateId, count = 1 })
			index[crateId] = #out
		end
	end
	return out
end

return Packs
