--!strict
--[[
	ShopProducts.luau — the Shop panel's Robux cash packs and Mystery crates.

	The Robux prices live on each product, and the panel reads them from there, so a
	price change on the dashboard needs no code change. Grants run on the server through
	ProductService: cash goes through EconomyService.award, and crates through
	CrateService.

	A BOUGHT CRATE ALWAYS FITS. It goes straight into `data.crates` whatever the bag
	holds, so a full backpack runs over capacity rather than eating a purchase. The
	bag's overflow tile and panel already show slots past the hotbar.

	A MYSTERY CRATE ROLLS ITS TIER on each purchase, out of Config/Crates' five variants
	of its kind, weighted toward the middle with a small shot at the best one. It is the
	same crate a dig would hand you, so opening it is the normal crate open.
]]

local ShopProducts = {}

export type CashPack = { id: number, amount: number, label: string }
export type MysteryCrate = { id: number, kind: string, name: string, weights: { number } }

local CASH: { CashPack } = {
	{ id = 3716021044, amount = 50_000, label = "$50K" },
	{ id = 3716021385, amount = 500_000, label = "$500K" },
	{ id = 3716021444, amount = 1_000_000, label = "$1M" },
	{ id = 3716021693, amount = 10_000_000, label = "$10M" },
}

-- Speed packs: `amount` is raw Speed (data.speedPoints); `label` is as players see it
-- (Treadmill.DISPLAY_SCALE x10). Fixed amounts, so they matter most early: from walk 30
-- they reach about 41 / 54 / 71 / 91. Ids are 0 (COMING SOON) until the products exist.
local SPEED: { CashPack } = {
	{ id = 0, amount = 10_000, label = "100K" },
	{ id = 0, amount = 50_000, label = "500K" },
	{ id = 0, amount = 250_000, label = "2.5M" },
	{ id = 0, amount = 1_500_000, label = "15M" },
}

-- `weights` are per Config/Crates variant, worst (1) to best (5).
local CRATES: { MysteryCrate } = {
	{ id = 3716022009, kind = "nuke", name = "Mystery Nuke Crate", weights = { 30, 30, 22, 13, 5 } },
	{ id = 3716022046, kind = "liquid", name = "Mystery Liquid Crate", weights = { 30, 30, 22, 13, 5 } },
}

ShopProducts.CASH = CASH
ShopProducts.SPEED = SPEED
ShopProducts.CRATES = CRATES

--- Roll a variant (1-5) off `weights`. `roll` is a 0-1 number, so the test can pin it.
function ShopProducts.rollVariant(weights: { number }, roll: number): number
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local pick = roll * total
	for variant, weight in weights do
		pick -= weight
		if pick < 0 then
			return variant
		end
	end
	return #weights
end

return ShopProducts
