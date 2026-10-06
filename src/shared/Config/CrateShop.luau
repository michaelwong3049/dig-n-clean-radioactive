--!strict
--[[
	CrateShop.luau — the two crate pads in Base Camp, either side of the group chest
	(Services/CrateShopService). Each pad holds two crates hovering side by side, each
	turning and bobbing on its own; walk up to one and press E to buy it.

	TWO FOR CASH, TWO FOR ROBUX (user's call, 2026-10-05): the Scrap Nuke Crate and the
	Coolant Chem Crate for in-game cash, and the maxed-out crate of each kind -- Fusion
	Core (nuke5) and Plasma Charge (liquid5) -- for Robux.

	WHICH SIDE (user's call, 2026-10-05): seen as a player walking up from the shops
	(+X), facing the chest (-X), the cash pad is on the RIGHT (-Z) and the Robux pad on
	the LEFT (+Z). The nuke crate of each pair sits nearest the chest.

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
	offset: number, -- studs along Z from the pad's centre
}

export type Pad = {
	name: string,
	title: string, -- the sign over the pad
	position: Vector3, -- pad centre, on the floor
	offers: { Offer },
}

-- The group chest is at (-113, -1.35, 0) with its gold ring out to ~9.1 studs; the
-- pads line up with it on X and sit just clear of the ring. Same floor top as the
-- chest: PLAZA.topY -1.5 + PLAZA_LIFT 0.15.
local CHEST_X = -113
local FLOOR_Y = -1.35
local PAD_Z = 18

-- Each pad is a stadium: a round end round each crate, joined down the middle.
CrateShop.SPREAD = 3.3 -- pad centre to each crate's centre, along Z
CrateShop.END_RADIUS = 4.2 -- each round end's radius, centred on its crate

CrateShop.HOVER_HEIGHT = 5.4 -- pad top to each crate's centre (~3 studs of air under it)
CrateShop.CRATE_SCALE = 1.3 -- x the bag-sized crate (CrateModels' 3.2-stud footprint)

-- Studs from the player. Each prompt is on its own part, and the default OnePerButton
-- exclusivity shows only the nearest one, so neighbours never fight over E.
CrateShop.PROMPT_DISTANCE = 6

CrateShop.PADS = {
	{
		name = "CashCratePad",
		title = "CRATE SHOP",
		position = Vector3.new(CHEST_X, FLOOR_Y, -PAD_Z),
		offers = {
			{ crateId = "nuke1", cash = 15_000, offset = CrateShop.SPREAD },
			{ crateId = "liquid3", cash = 40_000, offset = -CrateShop.SPREAD },
		},
	},
	{
		name = "RobuxCratePad",
		title = "PREMIUM CRATES",
		position = Vector3.new(CHEST_X, FLOOR_Y, PAD_Z),
		offers = {
			{ crateId = "nuke5", productId = 0, offset = -CrateShop.SPREAD },
			{ crateId = "liquid5", productId = 0, offset = CrateShop.SPREAD },
		},
	},
} :: { Pad }

return CrateShop
