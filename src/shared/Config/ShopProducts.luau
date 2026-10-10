--!strict
--[[
	ShopProducts.luau — the Shop panel's Robux cash and speed packs.

	The Robux prices live on each product, and the panel reads them from there, so a
	price change on the dashboard needs no code change. Grants run on the server through
	ProductService: cash goes through EconomyService.award, speed through
	SpeedService.

	The Mystery crates that used to live here were retired 2026-10-05 (user's call):
	their two products (3716022009, 3716022046) now sell the Fusion and Plasma crates on
	Base Camp's PREMIUM CRATES pad -- see Config/CrateShop.
]]

local ShopProducts = {}

export type CashPack = { id: number, amount: number, label: string }

local CASH: { CashPack } = {
	{ id = 3716021044, amount = 50_000, label = "$50K" },
	{ id = 3716021385, amount = 500_000, label = "$500K" },
	{ id = 3716021444, amount = 1_000_000, label = "$1M" },
	{ id = 3716021693, amount = 10_000_000, label = "$10M" },
}

-- Speed packs: `amount` is WALK SPEED added to `data.walkBought` (Config/WalkSpeed).
-- They used to be raw treadmill Speed that took a fresh player from walk 30 to about
-- 41 / 54 / 71 / 91; with the treadmill gone (2026-10-09) they hand over about that
-- much walk straight. Fixed amounts, so they matter most early. The products are the
-- same; their dashboard names still say "100K Speed" etc. until renamed there.
local SPEED: { CashPack } = {
	{ id = 3716090761, amount = 10, label = "+10" },
	{ id = 3716090932, amount = 25, label = "+25" },
	{ id = 3716090970, amount = 40, label = "+40" },
	{ id = 3716090999, amount = 60, label = "+60" },
}

ShopProducts.CASH = CASH
ShopProducts.SPEED = SPEED

return ShopProducts
