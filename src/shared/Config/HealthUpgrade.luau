--!strict
--[[
	HealthUpgrade.luau — max health bought at the Upgrades booth, under the walk speed
	(client/SpeedPanel, Services/SpeedService). Added 2026-10-10 on request: "add a
	health upgrade purchase too like this" (the +1 / +3 / +10 / Robux row).

	ONE POINT = HP_PER_POINT max health, on top of Tuning.maxHealthFor (the aura's) and
	BEFORE the 2x Health pass doubles it (ExposureService.maxHealthOf). +10 = +50, one
	aura tier's worth.

	THE PRICE is the speed curve (on request, "same curve as speed"), on its own counter
	`data.healthBought`: FIRST_PRICE for the first point, PRICE_GROWTH dearer every point
	after. Its own constants, so a speed retune doesn't move health with it. No depth
	discount: speed's comes from the stage step, health has none.

	Config modules require nothing, so roundNice is a copy of WalkSpeed's.
]]

local HealthUpgrade = {}

--- Max health each point bought adds (before the 2x Health pass).
HealthUpgrade.HP_PER_POINT = 5

--- The first point's price, and how much dearer each point makes the next.
HealthUpgrade.FIRST_PRICE = 1000
HealthUpgrade.PRICE_GROWTH = 1.20

--- The cash buttons: exactly that many points.
HealthUpgrade.BULK = { 1, 3, 10 }

--- The Developer Product the purple button sells: ROBUX_POINTS points, flat. 0 = not
--- set up yet, and the button reads SOON.
--- Creator Dashboard -> Monetization -> Developer Products: "+10 Health".
HealthUpgrade.PRODUCT_ID = 0
HealthUpgrade.ROBUX_POINTS = 10

local function roundNice(n: number): number
	if n < 1000 then
		return math.floor(n / 10 + 0.5) * 10
	end
	local magnitude = 10 ^ (math.floor(math.log10(n)) - 2)
	return math.floor(n / magnitude + 0.5) * magnitude
end

--- `healthBought` from a save, sanitised: a whole number, 0 or more (NaN reads as 0).
function HealthUpgrade.bought(raw: any): number
	if type(raw) ~= "number" or raw ~= raw then
		return 0
	end
	return math.max(0, math.floor(raw))
end

--- The max health `healthBought` points add.
function HealthUpgrade.bonusFor(healthBought: any): number
	return HealthUpgrade.bought(healthBought) * HealthUpgrade.HP_PER_POINT
end

--- The price of exactly `amount` points from `healthBought`, point by point.
function HealthUpgrade.priceFor(healthBought: any, amount: number): number
	local from = HealthUpgrade.bought(healthBought)
	local total = 0
	for i = 0, math.max(0, math.floor(amount)) - 1 do
		total += HealthUpgrade.FIRST_PRICE * HealthUpgrade.PRICE_GROWTH ^ (from + i)
	end
	return roundNice(total)
end

return HealthUpgrade
