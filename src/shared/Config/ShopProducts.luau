--!strict
--[[
	ShopProducts.luau — the Shop panel's Robux cash and speed packs.

	The Robux prices live on each product, and the panel reads them from there, so a
	price change on the dashboard needs no code change. Grants run on the server through
	ProductService: cash goes through EconomyService.award, speed through
	TreadmillService.

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

-- Speed packs: `amount` is raw Speed (data.speedPoints); `label` is as players see it
-- (Treadmill.DISPLAY_SCALE x10). Fixed amounts, so they matter most early: from walk 30
-- they reach about 41 / 54 / 71 / 91.
local SPEED: { CashPack } = {
	{ id = 3716090761, amount = 10_000, label = "100K" },
	{ id = 3716090932, amount = 50_000, label = "500K" },
	{ id = 3716090970, amount = 250_000, label = "2.5M" },
	{ id = 3716090999, amount = 1_500_000, label = "15M" },
}

ShopProducts.CASH = CASH
ShopProducts.SPEED = SPEED

return ShopProducts
