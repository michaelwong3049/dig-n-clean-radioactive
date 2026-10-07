--!strict
--[[
	CrateShop.luau — the crate pads: two in Base Camp, either side of the group chest, and
	two more in every camp after it (Services/CrateShopService). Each pad holds two crates
	hovering side by side, each turning and bobbing on its own; walk up to one and press E
	to buy it.

	TWO FOR CASH, TWO FOR ROBUX (user's call, 2026-10-05): the Scrap Nuke Crate and the
	Coolant Chem Crate for in-game cash, and the maxed-out crate of each kind -- Fusion
	Core (nuke5) and Plasma Charge (liquid5) -- for Robux.

	WHICH SIDE (user's call, 2026-10-05): seen as a player walking up from the shops
	(+X), facing the chest (-X), the cash pad is on the RIGHT (-Z) and the Robux pad on
	the LEFT (+Z). The nuke crate of each pair sits nearest the chest.

	AN UPGRADED PAIR IN EVERY CAMP (user's call, 2026-10-07): Toxic Twilight sells the Field
	Nuke Crate + Isotope Chem Crate for cash, Magma Hollow the Void Nuke Crate + Nitro Fuel
	Crate. Each camp also gets a Robux pad copying Base Camp's (Fusion + Plasma, the same
	two products). The Scrap crate went $15K -> $75K the same day; Coolant stays $40K.

	CAMP PRICES FOLLOW WHAT'S INSIDE: Scrap at $75K is ~27x its average nuke's value
	(~$2.8K), and the camp nuke crates keep that markup -- Field ~$26K inside -> $700K
	(about Twilight's cheapest gear), Void ~$432K inside -> $12M. Each liquid crate is a
	bit over half its pad's nuke crate, the same ratio as Base Camp's Coolant to Scrap.

	CAMP PADS SIT ON THE PLAZA'S WEST SIDE, flanking the entry path the way Base Camp's
	flank the chest: just inside the octagon, west of the paver square, crates facing the
	way you walk in (-X). Walking in (facing +X) the cash pad is on your right (+Z), the
	same hand as at Base Camp. `camp` + `offset` place them off the camp's plaza centre
	(build/CrateShopPads resolves it), so moving a camp carries its pads along.

	A BOUGHT CRATE ALWAYS FITS, the same rule as the packs (Config/Packs): straight
	into `data.crates` whatever the bag holds.

	ROBUX PRICES LIVE ON THE PRODUCT, so the tag reads its live R$ price. While a
	`productId` is 0 the tag reads COMING SOON and pressing E says so.

	THE TWO ROBUX PRODUCTS ARE THE OLD MYSTERY CRATES' (user's call, 2026-10-05): the
	Shop panel's Mystery Nuke / Mystery Liquid crates were retired and their products
	reused -- 3716022009 sells the Fusion crate, 3716022046 the Plasma crate. The user
	renames them on the dashboard.
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
	-- Base Camp: the pad centre, on the floor. A camp pad gives `camp` (a Config/Camps key)
	-- and `offset` from that camp's plaza centre instead.
	position: Vector3?,
	camp: string?,
	offset: Vector3?,
	facing: Vector3, -- the way the crates' fronts point
	offers: { Offer },
}

-- The group chest is at (-95, -1.15, 0) with its gold ring out to ~9.1 studs; the
-- pads line up with it on X and sit just clear of the ring, all three on the prize
-- square (build/PrizeSquare, inner half-width 28 > PAD_Z + SPREAD + END_RADIUS 25.5).
-- Same floor top as the chest: PLAZA.topY -1.5 + SHOP_FLOOR_LIFT 0.35.
local CHEST_X = -95
local FLOOR_Y = -1.15
local PAD_Z = 18

-- Each pad is a stadium: a round end round each crate, joined down the middle.
CrateShop.SPREAD = 3.3 -- pad centre to each crate's centre, along Z
CrateShop.END_RADIUS = 4.2 -- each round end's radius, centred on its crate

CrateShop.HOVER_HEIGHT = 5.4 -- pad top to each crate's centre (~3 studs of air under it)
CrateShop.CRATE_SCALE = 1.3 -- x the bag-sized crate (CrateModels' 3.2-stud footprint)

-- Studs from the player. Each prompt is on its own part, and the default OnePerButton
-- exclusivity shows only the nearest one, so neighbours never fight over E.
CrateShop.PROMPT_DISTANCE = 6

-- A camp pad's centre from its plaza centre: 88 west lands it between the octagon's west
-- edge (110) and the paver square (66) with room either side; 24 off the axis clears the
-- entry path (half-width 10) by the pad's 7.5-stud half-length and some.
local CAMP_PAD_X = -88
local CAMP_PAD_Z = 24

--- A camp's cash pad (right hand walking in, +Z) and Robux pad (left, -Z).
local function campPads(campKey: string, label: string, nuke: string, nukeCash: number, liquid: string, liquidCash: number): { Pad }
	return {
		{
			name = `{label}CashCratePad`,
			title = "CRATE SHOP",
			camp = campKey,
			offset = Vector3.new(CAMP_PAD_X, 0, CAMP_PAD_Z),
			facing = -Vector3.xAxis,
			offers = {
				{ crateId = nuke, cash = nukeCash, offset = -CrateShop.SPREAD },
				{ crateId = liquid, cash = liquidCash, offset = CrateShop.SPREAD },
			},
		},
		{
			name = `{label}RobuxCratePad`,
			title = "PREMIUM CRATES",
			camp = campKey,
			offset = Vector3.new(CAMP_PAD_X, 0, -CAMP_PAD_Z),
			facing = -Vector3.xAxis,
			offers = {
				{ crateId = "nuke5", productId = 3716022009, offset = CrateShop.SPREAD },
				{ crateId = "liquid5", productId = 3716022046, offset = -CrateShop.SPREAD },
			},
		},
	}
end

CrateShop.PADS = {
	{
		name = "CashCratePad",
		title = "CRATE SHOP",
		position = Vector3.new(CHEST_X, FLOOR_Y, -PAD_Z),
		facing = Vector3.xAxis,
		offers = {
			{ crateId = "nuke1", cash = 75_000, offset = CrateShop.SPREAD },
			{ crateId = "liquid3", cash = 40_000, offset = -CrateShop.SPREAD },
		},
	},
	{
		name = "RobuxCratePad",
		title = "PREMIUM CRATES",
		position = Vector3.new(CHEST_X, FLOOR_Y, PAD_Z),
		facing = Vector3.xAxis,
		offers = {
			{ crateId = "nuke5", productId = 3716022009, offset = -CrateShop.SPREAD },
			{ crateId = "liquid5", productId = 3716022046, offset = CrateShop.SPREAD },
		},
	},
} :: { Pad }

for _, pad in campPads("twilight", "Twilight", "nuke2", 700_000, "liquid2", 400_000) do
	table.insert(CrateShop.PADS, pad)
end
for _, pad in campPads("magma", "Magma", "nuke3", 12_000_000, "liquid1", 6_500_000) do
	table.insert(CrateShop.PADS, pad)
end

return CrateShop
