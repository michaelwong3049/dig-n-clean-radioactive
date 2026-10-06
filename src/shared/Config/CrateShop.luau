--!strict
--[[
	CrateShop.luau — the crate pad in Base Camp, beside the group chest
	(Services/CrateShopService). Four crates hover in a ring over a round pad, each
	turning and bobbing on its own; walk up to one and press E to buy it.

	TWO FOR CASH, TWO FOR ROBUX (user's call, 2026-10-05): the Scrap Nuke Crate and the
	Coolant Chem Crate for in-game cash, and the maxed-out crate of each kind -- Fusion
	Core (nuke5) and Plasma Charge (liquid5) -- for Robux. Nuke crates sit on the +Z
	half of the ring, liquid crates on the -Z half; the cash pair faces the shops (+X),
	so they are the first two a player walks up to.

	A BOUGHT CRATE ALWAYS FITS, the same rule as the Shop's Mystery crates
	(Config/ShopProducts): straight into `data.crates` whatever the bag holds.

	ROBUX PRICES LIVE ON THE PRODUCT. While a `productId` is 0 the crate's tag reads
	COMING SOON and pressing E says so; create the Developer Product on the Creator
	Dashboard, paste its id here, and the tag reads its live R$ price.
]]

local CrateShop = {}

export type Offer = {
	crateId: string, -- a Config/Crates id
	cash: number?, -- in-game cash price, or nil for a Robux crate
	productId: number?, -- Robux Developer Product id (0 = not created yet)
	angle: number, -- degrees round the ring, 0 = +X (toward the shops), 90 = +Z
}

-- On the grey floor between the base rows, between the group chest (x -113, ring out
-- to x -104.5) and the shops (+X). Same floor top as the chest: PLAZA.topY -1.5 +
-- PLAZA_LIFT 0.15.
CrateShop.PAD_POSITION = Vector3.new(-88, -1.35, 0)
CrateShop.PAD_RADIUS = 8.5

CrateShop.ORBIT_RADIUS = 5.6 -- pad centre to each crate's centre
CrateShop.HOVER_HEIGHT = 5.4 -- pad top to each crate's centre (~3 studs of air under it)
CrateShop.CRATE_SCALE = 1.3 -- x the bag-sized crate (CrateModels' 3.2-stud footprint)

-- Studs from the player. Each prompt is on its own part, and the default OnePerButton
-- exclusivity shows only the nearest one, so neighbours never fight over E.
CrateShop.PROMPT_DISTANCE = 6

CrateShop.OFFERS = {
	{ crateId = "nuke1", cash = 15_000, angle = 45 },
	{ crateId = "liquid3", cash = 40_000, angle = -45 },
	{ crateId = "nuke5", productId = 0, angle = 135 },
	{ crateId = "liquid5", productId = 0, angle = -135 },
} :: { Offer }

return CrateShop
