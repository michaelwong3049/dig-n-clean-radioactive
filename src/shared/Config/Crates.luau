--!strict
--[[
	Crates.lua — supply crates you dig up, carry home, and crack open for a prize.

	WHAT A CRATE IS. About one buried signal in CRATE_CHANCE is not a nuke but a
	crate. You haul it out like anything else (no pull fuse -- a crate cannot go off),
	it rides in your backpack taking a slot, and when you hold it an OPEN keycap
	appears. Opening it spends the crate and rolls a prize:

	  * NUKE CRATES roll one nuke off the whole catalogue with a RARITY FLOOR. The
	    prize comes out CLEAN, IDENTIFIED and FROZEN (no decay clock) -- it was sealed
	    in a crate, not buried in slag -- and takes the crate's slot in the bag.
	  * LIQUID CRATES roll one fluid off Config/Liquids with a FLOOR on the table, and
	    load it exactly the way a bottle roll does (charges stack, a better fluid
	    auto-loads). The popup is the bottle's own brew reel.

	THREE VARIANTS OF EACH, and the better the crate, the higher the floor and the
	fatter the top of its table. Only the Void crate can ever hand you an Anomaly.

	CRATES ARE NOT IN `data.carry`. They live in their own list, `data.crates`, and
	share the backpack's SLOTS with it (CarryService.used). Every service that walks
	`data.carry` -- decay, exposure, washing, selling, the stands -- assumes each entry
	is a nuke with an Items.DEFS id, and a crate in there would crash the first
	`Items.get` it met. Keeping them apart means none of that code can see a crate,
	so none of it can break.

	WHERE THEY DROP. Deeper stages drop better crates (STAGE_VARIANT_WEIGHTS), and a
	detector with luck nudges the variant up the same way it nudges a nuke's rarity:
	`weight * luck ^ (variant - 1)`, re-rolled per player like DigService.rollFor.

	THE ODDS SHOWN AND THE ODDS ROLLED ARE ONE FUNCTION (`nukeOdds`, `liquidOdds`),
	the same rule Liquids.oddsAt and Items.rollWeights follow. Util/Spec pins the
	floors, the monotone stage curve, and that every variant's table sums to 1.
]]

local Rarity = require(script.Parent.Rarity)
local Items = require(script.Parent.Items)
local Liquids = require(script.Parent.Liquids)

local Crates = {}

export type CrateDef = {
	id: string,
	kind: string, -- "nuke" | "liquid"
	variant: number, -- 1 basic, 2 mid, 3 top
	name: string,
	short: string, -- hotbar / keycap label
	flavor: string,
	color: string, -- hex; the aura, the hotbar border, the banner
	tier: string, -- a Config/Rarity name, for the chip colour. A label, not a mechanic.
	-- NUKE: rarity name -> relative weight. Rarities absent here never roll.
	rarities: { [string]: number }?,
	-- LIQUID: the lowest Liquids.ORDER entry this crate can hand out, and a luck
	-- multiplier on top of the player's own fluid luck.
	liquidFloor: string?,
	liquidLuck: number?,
	pullWeight: number, -- kg, for the haul (Config/Weight), like an item's `weight`
	-- Visual size nudge on top of the shared crate footprint (CrateModels), for a model
	-- that reads small next to the others. 1 when absent.
	sizeMult: number?,
}

--- One in this many spawned signals is a crate instead of a nuke.
Crates.CRATE_CHANCE = 15

--- Of the crates, the share that are nuke crates (the rest are liquid crates).
Crates.NUKE_SHARE = 0.5

--- Detector luck can multiply a variant's drop weight by at most this much.
Crates.VARIANT_LUCK_CAP = 6

Crates.ORDER = {
	"nuke1",
	"nuke2",
	"nuke3",
	"liquid1",
	"liquid2",
	"liquid3",
}

Crates.DEFS = {
	nuke1 = {
		id = "nuke1",
		kind = "nuke",
		variant = 1,
		name = "Scrap Nuke Crate",
		short = "Scrap Crate",
		flavor = "Dented red steel, a stencilled trefoil, and something heavy rattling inside.",
		color = "D9453A",
		tier = "Uncommon",
		rarities = { Uncommon = 70, Rare = 24, Epic = 5.5, Legendary = 0.5 },
		pullWeight = 40,
	},
	nuke2 = {
		id = "nuke2",
		kind = "nuke",
		variant = 2,
		name = "Field Nuke Crate",
		short = "Field Crate",
		flavor = "Olive field-issue case, antenna still up. Somebody meant to come back for it.",
		color = "7FA35B",
		tier = "Rare",
		rarities = { Rare = 68, Epic = 26, Legendary = 5.4, Mythic = 0.6 },
		pullWeight = 70,
	},
	nuke3 = {
		id = "nuke3",
		kind = "nuke",
		variant = 3,
		name = "Void Nuke Crate",
		short = "Void Crate",
		flavor = "Purple, humming, and colder than it should be. Open it somewhere safe.",
		color = "B26BFF",
		tier = "Epic",
		rarities = { Epic = 64, Legendary = 29, Mythic = 6, Anomaly = 1 },
		pullWeight = 110,
	},
	liquid1 = {
		id = "liquid1",
		kind = "liquid",
		variant = 1,
		name = "Toxic Chem Crate",
		short = "Toxic Crate",
		flavor = "Green sludge bubbling over the lid. At least it isn't water.",
		color = "5CD65C",
		tier = "Uncommon",
		liquidFloor = "gel",
		liquidLuck = 1.5,
		pullWeight = 35,
		sizeMult = 1.25, -- on request: the Toxic model read small beside the rest
	},
	liquid2 = {
		id = "liquid2",
		kind = "liquid",
		variant = 2,
		name = "Isotope Chem Crate",
		short = "Isotope Crate",
		flavor = "Sealed canisters behind vented steel. Somebody cared about these.",
		color = "3D7BF5",
		tier = "Rare",
		liquidFloor = "glacier",
		liquidLuck = 2.5,
		pullWeight = 60,
	},
	liquid3 = {
		id = "liquid3",
		kind = "liquid",
		variant = 3,
		name = "Coolant Chem Crate",
		short = "Coolant Crate",
		flavor = "A reactor's worth of coolant, still cold, gauge still reading full.",
		color = "5EC8FF",
		tier = "Epic",
		liquidFloor = "ghost",
		liquidLuck = 4,
		pullWeight = 90,
	},
} :: { [string]: CrateDef }

--- Basic / mid / top drop weights per stage, at detector luck 1. Deeper stages lean
--- up the ladder: Stage 1 is nearly all basic crates, the Crater is a real shot at
--- a top one every few crates.
Crates.STAGE_VARIANT_WEIGHTS = {
	[1] = { 85, 14, 1 },
	[2] = { 75, 22, 3 },
	[3] = { 62, 31, 7 },
	[4] = { 50, 38, 12 },
	[5] = { 38, 44, 18 },
	[6] = { 30, 45, 25 },
} :: { [number]: { number } }

function Crates.get(id: string): CrateDef
	local def = Crates.DEFS[id]
	assert(def, `unknown crate id "{id}"`)
	return def
end

function Crates.has(id: any): boolean
	return type(id) == "string" and Crates.DEFS[id] ~= nil
end

--- The crate of `kind` at `variant`.
function Crates.idFor(kind: string, variant: number): string
	return `{kind}{variant}`
end

-- ── Which crate drops ─────────────────────────────────────────────────

--- Normalised variant odds { basic, mid, top } for a stage at this detector luck.
function Crates.variantOdds(stageId: number, luck: number): { number }
	local base = Crates.STAGE_VARIANT_WEIGHTS[stageId] or Crates.STAGE_VARIANT_WEIGHTS[1]
	local weights = table.create(3, 0)
	local total = 0
	for variant = 1, 3 do
		local bias = math.min(math.max(luck, 1) ^ (variant - 1), Crates.VARIANT_LUCK_CAP)
		weights[variant] = base[variant] * bias
		total += weights[variant]
	end
	for variant = 1, 3 do
		weights[variant] /= total
	end
	return weights
end

--- Roll a variant (1-3) for a stage. `rng` is a number in [0, 1).
function Crates.rollVariant(stageId: number, luck: number, rng: number): number
	local odds = Crates.variantOdds(stageId, luck)
	local pick = rng
	for variant = 1, 3 do
		pick -= odds[variant]
		if pick <= 0 then
			return variant
		end
	end
	return 1
end

-- ── What a nuke crate holds ───────────────────────────────────────────

--- Every nuke still in the catalogue (retired items have `stages = {}`), in a STABLE
--- order: Rarity.ORDER, then id. Built lazily once.
local catalogue: { Items.ItemDef }? = nil

local function nukePool(): { Items.ItemDef }
	if catalogue then
		return catalogue
	end
	local out: { Items.ItemDef } = {}
	for _, item in Items.DEFS do
		if #item.stages > 0 then
			table.insert(out, item)
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = Rarity.get(a.rarity).order, Rarity.get(b.rarity).order
		if ra ~= rb then
			return ra < rb
		end
		return a.id < b.id
	end)
	catalogue = out
	return out
end

--- Normalised prize odds for a nuke crate, keyed by item id. The rarity is picked off
--- the crate's `rarities` table; within a rarity, rarer items (bigger `odds`) come up
--- less, 1/odds like the dig roll. Sums to 1.
function Crates.nukeOdds(crateId: string): { [string]: number }
	local def = Crates.get(crateId)
	local rarities = def.rarities or {}

	local rarityTotal = 0
	for _, w in rarities do
		rarityTotal += w
	end

	local withinTotal: { [string]: number } = {}
	for _, item in nukePool() do
		if rarities[item.rarity] then
			withinTotal[item.rarity] = (withinTotal[item.rarity] or 0) + 1 / item.odds
		end
	end

	local out: { [string]: number } = {}
	if rarityTotal <= 0 then
		return out
	end
	for _, item in nukePool() do
		local w = rarities[item.rarity]
		local within = withinTotal[item.rarity]
		if w and within and within > 0 then
			out[item.id] = (w / rarityTotal) * ((1 / item.odds) / within)
		end
	end
	return out
end

--- Roll a nuke crate's prize. `rng` is a number in [0, 1). Walks the stable pool.
function Crates.rollNuke(crateId: string, rng: number): string?
	local odds = Crates.nukeOdds(crateId)
	local pick = rng
	local last: string? = nil
	for _, item in nukePool() do
		local p = odds[item.id]
		if p then
			last = item.id
			pick -= p
			if pick <= 0 then
				return item.id
			end
		end
	end
	return last
end

-- ── What a liquid crate holds ─────────────────────────────────────────

--- The luck a liquid crate rolls at: the player's own fluid luck times the crate's.
function Crates.liquidLuckFor(crateId: string, playerLuck: number): number
	return math.max(playerLuck, 1) * (Crates.get(crateId).liquidLuck or 1)
end

--- Normalised fluid odds for a liquid crate at a player's fluid luck, keyed by liquid
--- id. Only liquids at or above the crate's floor appear. Sums to 1.
function Crates.liquidOdds(crateId: string, playerLuck: number): { [string]: number }
	local def = Crates.get(crateId)
	local floor = Liquids.get(def.liquidFloor).order
	local luck = Crates.liquidLuckFor(crateId, playerLuck)

	local total = 0
	for _, id in Liquids.ORDER do
		local liquid = Liquids.DEFS[id]
		if liquid.order >= floor then
			total += Liquids.effectiveWeight(liquid, luck)
		end
	end

	local out: { [string]: number } = {}
	if total <= 0 then
		return out
	end
	for _, id in Liquids.ORDER do
		local liquid = Liquids.DEFS[id]
		if liquid.order >= floor then
			local w = Liquids.effectiveWeight(liquid, luck)
			if w > 0 then
				out[id] = w / total
			end
		end
	end
	return out
end

--- Roll a liquid crate's fluid. `rng` is a number in [0, 1).
function Crates.rollLiquid(crateId: string, playerLuck: number, rng: number): string
	local odds = Crates.liquidOdds(crateId, playerLuck)
	local pick = rng
	local last = Crates.get(crateId).liquidFloor or Liquids.WATER
	for _, id in Liquids.ORDER do
		local p = odds[id]
		if p then
			last = id
			pick -= p
			if pick <= 0 then
				return id
			end
		end
	end
	return last
end

return Crates
