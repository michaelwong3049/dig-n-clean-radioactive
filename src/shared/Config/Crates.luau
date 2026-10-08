--!strict
--[[
	Crates.lua — supply crates you dig up, carry home, and crack open for a prize.

	WHAT A CRATE IS. About one buried signal in CRATE_CHANCE is not a nuke but a
	crate -- AND NOTHING SAYS SO UNTIL IT IS WASHED. At the dig it passes for a nuke of
	its own tier (DigService.standInFor): same ping, odds, pull, lump and fuse (if the
	fuse goes, the crate goes with it). It rides in the bag as a crusted "???" like any
	find, and the wash bay's last chunk is where it turns out to be a crate
	(WashService.revealAndFinish). A clean crate takes a slot, and when you hold it an
	OPEN keycap appears. Opening it spends the crate and rolls a prize:

	  * NUKE CRATES roll one nuke with a RARITY FLOOR, from the nukes stocked in the
	    crate's own STAGE RANGE (`stages`) -- never the whole catalogue, so an early
	    crate can't hand out a far-stage nuke. The prize comes out CLEAN, IDENTIFIED
	    and FROZEN (no decay clock) -- it was sealed in a crate, not buried in slag --
	    and takes the crate's slot in the bag.
	  * LIQUID CRATES roll one fluid off Config/Liquids with a FLOOR on the table, and
	    load it exactly the way a bottle roll does (charges stack, a better fluid
	    auto-loads). The popup is the bottle's own brew reel.
	  * THE POTION CRATE (one variant, `potion1`) drops one potion (Config/Potions)
	    into the player's stash, every potion equally likely. It drops just as often
	    on every stage and ignores detector luck (Crates.dropId).

	THE JACKPOT CRATES (nuke6 Mythic Crate, nuke7 Anomaly Crate; were Ground Zero / Rift) sit off the
	ladder. Each rolls EVERY nuke of its one rarity in the game, Stage 1 to 12, with a
	later stage's nukes rarer (`stageFalloff` per stage after the first). They never
	come out of the ordinary crate roll: they are their own very rare dig drop on
	Stages 8-12 (`digStages` / `digChance`, Crates.rollSpecial), dressed as a spot of
	their own tier, and a rare Slag Furnace prize. Detector luck never re-rolls one.

	FIVE VARIANTS OF EACH, and the better the crate, the higher the floor and the
	fatter the top of its table. Variants 1-3 are the early crates (Stages 1-6);
	4-5 only drop from Stage 7 on. Scrap and Field never hand out an Anomaly.

	A CLEAN CRATE IS NOT IN `data.carry`. It lives in its own list, `data.crates`, and
	shares the backpack's SLOTS with it (Shared/Bag). Every service that walks
	`data.carry` -- decay, exposure, washing, selling, the stands -- assumes each entry
	is a nuke with an Items.DEFS id.

	A DIRTY CRATE IS, on purpose: it is a normal carried item whose `itemId` is its
	stand-in nuke, plus a `crateId`. Every one of those services sees a crusted nuke
	and treats it as one, which is exactly the disguise. It never stays in
	`data.carry` clean -- the wash moves it to `data.crates` the moment the last patch
	goes, and a blind sale names the crate (IdentifyService.announceCrate), never the
	stand-in.

	WHERE THEY DROP. Deeper stages drop better crates (STAGE_VARIANT_WEIGHTS), and a
	detector with luck nudges the variant up the same way it nudges a nuke's rarity:
	`weight * luck ^ (variant - lowest)`, where `lowest` is the stage's first variant
	that drops at all, re-rolled per player like DigService.rollFor.

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
	kind: string, -- "nuke" | "liquid" | "potion"
	variant: number, -- 1 (worst) .. Crates.VARIANTS (best)
	name: string,
	short: string, -- hotbar / keycap label
	flavor: string,
	color: string, -- hex; the aura, the hotbar border, the banner
	tier: string, -- a Config/Rarity name, for the chip colour. A label, not a mechanic.
	-- NUKE: rarity name -> relative weight. Rarities absent here never roll.
	rarities: { [string]: number }?,
	-- NUKE: { first, last } stage the prize can come from. An item stocked on any
	-- stage in the range is in the pool.
	stages: { number }?,
	-- NUKE: inside a rarity, each stage after the first multiplies an item's weight by
	-- this (its earliest stage counts), so later stages' nukes come up rarer. 1 if absent.
	stageFalloff: number?,
	-- A JACKPOT crate: off the variant ladder, never re-rolled by detector luck, and
	-- dug only as its own drop -- `digChance` per spawned signal on `digStages`.
	special: boolean?,
	digStages: { number }?,
	digChance: number?,
	-- LIQUID: the lowest Liquids.ORDER entry this crate can hand out, and a luck
	-- multiplier on top of the player's own fluid luck.
	liquidFloor: string?,
	liquidLuck: number?,
	pullWeight: number, -- kg, for the haul (Config/Weight), like an item's `weight`
	-- Visual size nudge on top of the shared crate footprint (CrateModels), for a model
	-- that reads small next to the others. 1 when absent.
	sizeMult: number?,
	-- The crate's picture (tools/crate-art/crate_<id>.png, set from Crates.IMAGES below):
	-- every 2D spot a crate shows (hotbar, bag, reels, shop, offers) draws this instead
	-- of rendering the 3D model in a viewport.
	image: string?,
}

--- One in this many spawned signals is a crate instead of a nuke.
Crates.CRATE_CHANCE = 15

--- Of the crates, how often each KIND drops (relative weights). Equal thirds, the
--- same on every stage. The potion crate has one variant and ignores the stage ladder
--- and detector luck: a Potion Crate is a Potion Crate wherever it is dug up.
Crates.KIND_WEIGHTS = { nuke = 1, liquid = 1, potion = 1 }
Crates.KIND_ORDER = { "nuke", "liquid", "potion" }

--- The kinds that come in a ladder of Crates.VARIANTS (nuke1..5, liquid1..5).
Crates.LADDER_KINDS = { nuke = true, liquid = true }

--- Variants per kind: nuke1..nuke5, liquid1..liquid5.
Crates.VARIANTS = 5

--- Detector luck can multiply a variant's drop weight by at most this much.
Crates.VARIANT_LUCK_CAP = 6

Crates.ORDER = {
	"nuke1",
	"nuke2",
	"nuke3",
	"nuke4",
	"nuke5",
	"nuke6",
	"nuke7",
	"liquid1",
	"liquid2",
	"liquid3",
	"liquid4",
	"liquid5",
	"potion1",
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
		stages = { 1, 4 },
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
		stages = { 2, 5 },
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
		stages = { 4, 7 },
		pullWeight = 110,
	},
	nuke4 = {
		id = "nuke4",
		kind = "nuke",
		variant = 4,
		name = "Cobalt Bomb Crate",
		short = "Cobalt Crate",
		flavor = "Blue-steel bomb case on a launch deck. The vents are still warm.",
		color = "2F6BFF",
		tier = "Rare",
		rarities = { Rare = 50, Epic = 35.9, Legendary = 11, Mythic = 3, Anomaly = 0.1 },
		stages = { 7, 10 },
		pullWeight = 150,
	},
	nuke5 = {
		id = "nuke5",
		kind = "nuke",
		variant = 5,
		name = "Fusion Core Crate",
		short = "Fusion Crate",
		flavor = "A reactor plinth in a case. Whatever is inside is still fusing.",
		color = "FFB020",
		tier = "Epic",
		rarities = { Epic = 55, Legendary = 32, Mythic = 11, Anomaly = 2 },
		stages = { 9, 12 },
		pullWeight = 200,
	},
	-- The jackpot crates: every Mythic / every Anomaly in the game, later stages rarer.
	-- Dug about as often as a natural Mythic / Anomaly spot on those stages.
	nuke6 = {
		id = "nuke6",
		kind = "nuke",
		variant = 6,
		name = "Mythic Crate",
		short = "Mythic Crate",
		flavor = "A mushroom cloud frozen under glass, the case cracked with magma. Every Mythic ever dug is in the draw.",
		color = "EF4444",
		tier = "Mythic",
		rarities = { Mythic = 1 },
		stages = { 1, 12 },
		stageFalloff = 0.8,
		special = true,
		digStages = { 8, 12 },
		digChance = 1 / 300000,
		pullWeight = 250,
	},
	nuke7 = {
		id = "nuke7",
		kind = "nuke",
		variant = 7,
		name = "Anomaly Crate",
		short = "Anomaly Crate",
		flavor = "A portal held open in a steel frame, stars pouring through. Every Anomaly ever dug is on the other side.",
		color = "FFFFFF",
		tier = "Anomaly",
		rarities = { Anomaly = 1 },
		stages = { 1, 12 },
		stageFalloff = 0.8,
		special = true,
		digStages = { 8, 12 },
		digChance = 1 / 3000000,
		pullWeight = 300,
	},
	liquid1 = {
		id = "liquid1",
		kind = "liquid",
		variant = 1,
		-- Was the Toxic Chem Crate; the id stays so saved crates open as Nitro.
		name = "Nitro Fuel Crate",
		short = "Nitro Crate",
		flavor = "A strapped fuel tank, bubbling behind the glass. Keep it away from sparks.",
		color = "FF6A1F",
		tier = "Uncommon",
		liquidFloor = "gel",
		liquidLuck = 1.5,
		pullWeight = 35,
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
	liquid4 = {
		id = "liquid4",
		kind = "liquid",
		variant = 4,
		name = "Quicksilver Crate",
		short = "Quicksilver",
		flavor = "A caged orb of mercury, rolling on its own. Don't touch the beads.",
		color = "C9D3DE",
		tier = "Rare",
		liquidFloor = "lava",
		liquidLuck = 6,
		pullWeight = 120,
	},
	liquid5 = {
		id = "liquid5",
		kind = "liquid",
		variant = 5,
		name = "Plasma Charge Crate",
		short = "Plasma Crate",
		flavor = "A tesla coil in a box, arcing at the lid. The hum gets in your teeth.",
		color = "FF4FD8",
		tier = "Epic",
		liquidFloor = "nano",
		liquidLuck = 9,
		pullWeight = 150,
	},
	-- One potion (Config/Potions), each equally likely. Same crate on every stage.
	potion1 = {
		id = "potion1",
		kind = "potion",
		variant = 1,
		name = "Potion Crate",
		short = "Potion Crate",
		flavor = "A padded case of stoppered flasks, still bubbling. Drink responsibly.",
		color = "B455FF",
		tier = "Rare",
		pullWeight = 60,
	},
} :: { [string]: CrateDef }

--- Each crate's picture, on request (2026-10-08): the user's AI crate art with the
--- white background cut out, 512x512 (tools/crate-art).
Crates.IMAGES = {
	nuke1 = "rbxassetid://110943154893005",
	nuke2 = "rbxassetid://89771862781115",
	nuke3 = "rbxassetid://111339322979744",
	nuke4 = "rbxassetid://138340475194178",
	nuke5 = "rbxassetid://70848925473815",
	nuke6 = "rbxassetid://117182713481345",
	nuke7 = "rbxassetid://138263067071021",
	liquid1 = "rbxassetid://87548059959283",
	liquid2 = "rbxassetid://117050988206747",
	liquid3 = "rbxassetid://103980106023210",
	liquid4 = "rbxassetid://138432481087528",
	liquid5 = "rbxassetid://108404964594991",
	potion1 = "rbxassetid://91093973499188",
} :: { [string]: string }
for id, image in Crates.IMAGES do
	Crates.DEFS[id].image = image
end

--- The picture of the best crate among `ids` (highest tier; the first one listed wins a
--- tie), for a reward card that shows one crate for the lot. nil when none has one.
function Crates.bestImage(ids: { string }?): string?
	local best: CrateDef? = nil
	local bestRank = -1
	for _, id in ids or {} do
		local def = Crates.DEFS[id]
		if def and def.image then
			local rank = table.find(Rarity.ORDER, def.tier) or 0
			if rank > bestRank then
				best, bestRank = def, rank
			end
		end
	end
	return if best then best.image else nil
end

--- Drop weights for variants 1..5 per stage, at detector luck 1. Deeper stages lean
--- up the ladder. Stages 1-6 drop the early three (Scrap/Field/Void); from Stage 7
--- the late two (Cobalt/Fusion) take over, with the Void fading out by Stage 12. The
--- liquid side rolls on the same ladder (Nitro .. Plasma).
Crates.STAGE_VARIANT_WEIGHTS = {
	[1] = { 80, 18, 2, 0, 0 },
	[2] = { 70, 26, 4, 0, 0 },
	[3] = { 57, 34, 9, 0, 0 },
	[4] = { 45, 40, 15, 0, 0 },
	[5] = { 34, 45, 21, 0, 0 },
	[6] = { 27, 45, 28, 0, 0 },
	[7] = { 0, 0, 35, 55, 10 },
	[8] = { 0, 0, 25, 58, 17 },
	[9] = { 0, 0, 15, 60, 25 },
	[10] = { 0, 0, 8, 60, 32 },
	[11] = { 0, 0, 3, 58, 39 },
	[12] = { 0, 0, 0, 55, 45 },
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

--- Which kind of crate a crate signal is. `rng` is a number in [0, 1).
function Crates.rollKind(rng: number): string
	local total = 0
	for _, kind in Crates.KIND_ORDER do
		total += Crates.KIND_WEIGHTS[kind] or 0
	end
	local pick = rng * total
	for _, kind in Crates.KIND_ORDER do
		pick -= Crates.KIND_WEIGHTS[kind] or 0
		if pick < 0 then
			return kind
		end
	end
	return Crates.KIND_ORDER[#Crates.KIND_ORDER]
end

--- The crate id a signal of `kind` drops on `stageId` at this detector luck. Ladder
--- kinds roll a variant (variantOdds); the potion crate is always potion1.
function Crates.dropId(kind: string, stageId: number, luck: number, rng: number): string
	if not Crates.LADDER_KINDS[kind] then
		return Crates.idFor(kind, 1)
	end
	return Crates.idFor(kind, Crates.rollVariant(stageId, luck, rng))
end

--- Normalised variant odds { 1 .. VARIANTS } for a stage at this detector luck. Luck
--- counts up from the stage's lowest dropping variant, so a late stage's Void (its
--- worst) gets no boost and Fusion gets the most, the way Scrap/Void do early.
function Crates.variantOdds(stageId: number, luck: number): { number }
	local base = Crates.STAGE_VARIANT_WEIGHTS[stageId] or Crates.STAGE_VARIANT_WEIGHTS[1]
	local lowest = 1
	for variant = 1, Crates.VARIANTS do
		if (base[variant] or 0) > 0 then
			lowest = variant
			break
		end
	end
	local weights = table.create(Crates.VARIANTS, 0)
	local total = 0
	for variant = 1, Crates.VARIANTS do
		local bias = math.min(math.max(luck, 1) ^ math.max(variant - lowest, 0), Crates.VARIANT_LUCK_CAP)
		weights[variant] = (base[variant] or 0) * bias
		total += weights[variant]
	end
	for variant = 1, Crates.VARIANTS do
		weights[variant] /= total
	end
	return weights
end

--- Roll a variant (1-VARIANTS) for a stage. `rng` is a number in [0, 1).
function Crates.rollVariant(stageId: number, luck: number, rng: number): number
	local odds = Crates.variantOdds(stageId, luck)
	local pick = rng
	local last = 1
	for variant = 1, Crates.VARIANTS do
		if odds[variant] > 0 then
			last = variant
			pick -= odds[variant]
			if pick <= 0 then
				return variant
			end
		end
	end
	return last
end

--- The jackpot crates' dig drop, rarest first.
Crates.SPECIAL_ORDER = { "nuke7", "nuke6" }

--- Which jackpot crate (if any) a fresh signal on `stageId` is. `rng` is a number in
--- [0, 1). Ignores detector luck. `stocked(tier)` says whether the stage has a nuke of
--- that tier for the crate to pass for (DigService.standInFor); if not, no drop.
function Crates.rollSpecial(stageId: number, rng: number, stocked: (string) -> boolean): string?
	local pick = rng
	for _, id in Crates.SPECIAL_ORDER do
		local def = Crates.get(id)
		local range = def.digStages
		if range and def.digChance and stageId >= range[1] and stageId <= range[2] then
			if pick < def.digChance then
				return if stocked(def.tier) then id else nil
			end
			pick -= def.digChance
		end
	end
	return nil
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

--- Is `item` stocked on any stage inside the crate's `stages` range? No range = any.
function Crates.inStageRange(def: CrateDef, item: Items.ItemDef): boolean
	local range = def.stages
	if range == nil then
		return true
	end
	for _, stageId in item.stages do
		if stageId >= range[1] and stageId <= range[2] then
			return true
		end
	end
	return false
end

--- An item's weight inside its rarity: 1/odds like the dig roll, times the crate's
--- `stageFalloff` for every stage its earliest stage sits past Stage 1.
local function withinWeight(def: CrateDef, item: Items.ItemDef): number
	local w = 1 / item.odds
	local falloff = def.stageFalloff
	if falloff and #item.stages > 0 then
		w *= falloff ^ (math.min(table.unpack(item.stages)) - 1)
	end
	return w
end

--- Normalised prize odds for a nuke crate, keyed by item id. Only nukes in the crate's
--- stage range are in it. The rarity is picked off the crate's `rarities` table (a
--- rarity the range doesn't stock drops out and the rest renormalise); within a
--- rarity, rarer items (bigger `odds`) come up less (withinWeight). Sums to 1.
function Crates.nukeOdds(crateId: string): { [string]: number }
	local def = Crates.get(crateId)
	local rarities = def.rarities or {}

	local withinTotal: { [string]: number } = {}
	for _, item in nukePool() do
		if rarities[item.rarity] and Crates.inStageRange(def, item) then
			withinTotal[item.rarity] = (withinTotal[item.rarity] or 0) + withinWeight(def, item)
		end
	end

	local rarityTotal = 0
	for rarity, w in rarities do
		if withinTotal[rarity] then
			rarityTotal += w
		end
	end

	local out: { [string]: number } = {}
	if rarityTotal <= 0 then
		return out
	end
	for _, item in nukePool() do
		local w = rarities[item.rarity]
		local within = withinTotal[item.rarity]
		if w and within and within > 0 and Crates.inStageRange(def, item) then
			out[item.id] = (w / rarityTotal) * (withinWeight(def, item) / within)
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
