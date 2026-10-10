--!strict
--[[
	ShopProducts.luau — the Shop panel's Robux cash packs.

	The Robux prices live on each product, and the panel reads them from there, so a
	price change on the dashboard needs no code change. Grants run on the server through
	ProductService, through EconomyService.award.

	The four cash amounts were raised 2026-10-10 (on request) from $50K/$500K/$1M/$10M
	to $500K/$2M/$10M/$100M on the SAME product ids: rename them on the Creator
	Dashboard (and revisit their Robux prices) to match.

	The four WALK SPEED packs (3716090761, 3716090932, 3716090970, 3716090999 -- the old
	treadmill "100K Speed" products) were retired 2026-10-10 (on request): speed is
	bought at the Upgrades booth. Take them off sale on the Creator Dashboard.

	The Mystery crates that used to live here were retired 2026-10-05 (user's call):
	their two products (3716022009, 3716022046) now sell the Fusion and Plasma crates on
	Base Camp's PREMIUM CRATES pad -- see Config/CrateShop.
]]

local ShopProducts = {}

export type CashPack = { id: number, amount: number, label: string }

local CASH: { CashPack } = {
	{ id = 3716021044, amount = 500_000, label = "$500K" },
	{ id = 3716021385, amount = 2_000_000, label = "$2M" },
	{ id = 3716021444, amount = 10_000_000, label = "$10M" },
	{ id = 3716021693, amount = 100_000_000, label = "$100M" },
}

ShopProducts.CASH = CASH

return ShopProducts
