--!strict
--[[
	NukePack.luau — the big card at the top of the Shop: one pack crate (Config/Crates
	`crateId`, a fixed five-nuke draw) sold for Robux in x1 / x3 / x5 / x10 bundles,
	after a reference "pack" card the user sent (2026-10-10). No end date or LIMITED
	TIME label, on request: it is simply always on sale.

	Each bundle is its own DEVELOPER PRODUCT. Services/PackService grants it: `count`
	pack crates straight into the bag (CrateService.give, past capacity like a pack's),
	opened from the hotbar with the ordinary crate reel. Buy it again as often as you
	like. The Robux prices live on the dashboard products (planned R$ 68 / 149 / 239 /
	399, the bigger bundles cheaper per crate); the Shop reads them from there. A
	`productId` of 0 is a bundle not created yet: its button reads COMING SOON.

	To run a different pack later, point `crateId` at another `prizes` crate.
]]

local NukePack = {}

export type Bundle = {
	count: number,
	productId: number,
	-- The button's colour (the reference's green, green, gold, purple).
	color: string,
}

NukePack.crateId = "nuke8"

NukePack.BUNDLES = {
	{ count = 1, productId = 0, color = "5CFE01" },
	{ count = 3, productId = 0, color = "5CFE01" },
	{ count = 5, productId = 0, color = "FFC81E" },
	{ count = 10, productId = 0, color = "D23CFF" },
} :: { Bundle }

return NukePack
