--!strict
--[[
	Config/Furnace.luau — every number for the Slag Furnace at Magma Hollow
	(build/SlagFurnace, Services/FurnaceService, client/FurnacePanel).

	DUMP NUKES, FILL THE METER, ROLL PRIZES. Every nuke you throw in is gone for good
	and fills the meter by its rarity (FILL), more for a better copy of that rarity
	(QUALITY_BONUS per good quality, MERGE_BONUS per merge star). Every full 100% banks
	one roll (`furnaceRolls` on the save) and the rest stays on the meter
	(`furnaceFill`), so dumping a Mythic stack can bank several rolls at once.

	A ROLL draws one prize off PRIZES by weight: potions, crates, cash, timed boosts,
	the jackpot crates (Ground Zero ~2%, Rift ~0.5%), and a small chance of a
	Legendary / Mythic / Anomaly nuke from Magma Hollow's own stages (JACKPOT_STAGES).
	The client plays it as a card reel (client/PrizeReel); the server has already
	granted the prize when the reel starts.

	SLAGGED COPIES COUNT, ON PURPOSE. A Slagged nuke is worth a tenth and no stand
	will take it; the furnace is the one place it is worth anything (SLAG_FILL).
]]

local Rarity = require(script.Parent.Rarity)
local Merge = require(script.Parent.Merge)

local Furnace = {}

--- The panel's accent: molten orange.
Furnace.COLOR = Color3.fromHex("FF7A2E")

--- Meter percent per copy, by rarity. Doubles each step, on request.
Furnace.FILL = {
	Scrap = 1,
	Common = 2,
	Uncommon = 4,
	Rare = 8,
	Epic = 15,
	Legendary = 30,
	Mythic = 60,
	Anomaly = 100,
} :: { [string]: number }

--- "Better versions of the rarities add %", on request: +50% of the base for each good
--- quality the copy carries (they stack), and +25% for each merge star.
Furnace.QUALITY_BONUS = 0.5
Furnace.GOOD_QUALITIES = { Pristine = true, Irradiated = true, Fused = true }
Furnace.MERGE_BONUS = 0.25

--- A Slagged copy's flat fill, whatever its rarity.
Furnace.SLAG_FILL = 1

--- One full meter = one roll.
Furnace.FULL = 100

--- The panel asks before it burns anything at or above this rarity.
Furnace.CONFIRM_FROM = "Legendary"

--- The most copies one dump request may name.
Furnace.MAX_DUMP = 100

--- One roll per player per this many seconds: the reel plays that long.
Furnace.ROLL_SECONDS = 5
Furnace.COOLDOWN = Furnace.ROLL_SECONDS + 0.5

--- The reel the client draws: REEL_LAND cards before the prize, REEL_TAIL after.
Furnace.REEL_LAND = 34
Furnace.REEL_TAIL = 5

--- Where the jackpot nukes come from: Magma Hollow's own stages.
Furnace.JACKPOT_STAGES = { 9, 10, 11, 12 }

--- Cash prizes pay `minutes` of the player's stand income, never under `floor`.
export type PrizeDef = {
	id: string,
	name: string,
	-- "potion" | "potionPack" | "crate" | "cash" | "luckBoost" | "cashBoost" | "nuke"
	kind: string,
	-- The card's colour on the reel, as a Rarity name.
	tier: string,
	weight: number,
	potion: string?, -- Config/Potions id (kind "potion")
	count: number?, -- potions in a pack (kind "potionPack")
	crate: string?, -- Config/Crates id (kind "crate")
	minutes: number?, -- kind "cash"
	floor: number?, -- kind "cash"
	seconds: number?, -- kind "luckBoost" / "cashBoost"
	rarity: string?, -- kind "nuke": the jackpot's rarity
}

--- Best last, so the panel's odds list reads cheap to dear. Weights are relative.
Furnace.PRIZES = {
	{ id = "luckPotion", name = "Luck Potion", kind = "potion", potion = "luck", tier = "Common", weight = 13 },
	{ id = "speedPotion", name = "Speed Potion", kind = "potion", potion = "speed", tier = "Common", weight = 11 },
	{ id = "cleanPotion", name = "Cleaning Potion", kind = "potion", potion = "clean", tier = "Common", weight = 10 },
	{ id = "cashPotion", name = "Cash Potion", kind = "potion", potion = "cash", tier = "Uncommon", weight = 10 },
	{ id = "strengthPotion", name = "Strength Potion", kind = "potion", potion = "strength", tier = "Uncommon", weight = 8 },
	{ id = "potionCrate", name = "Potion Crate", kind = "crate", crate = "potion1", tier = "Uncommon", weight = 7 },
	{ id = "voidCrate", name = "Void Nuke Crate", kind = "crate", crate = "nuke3", tier = "Uncommon", weight = 7 },
	{ id = "potionPack", name = "3 Potions", kind = "potionPack", count = 3, tier = "Rare", weight = 5 },
	{ id = "cashPile", name = "Cash Pile", kind = "cash", minutes = 10, floor = 100000, tier = "Rare", weight = 7 },
	{ id = "cobaltCrate", name = "Cobalt Bomb Crate", kind = "crate", crate = "nuke4", tier = "Rare", weight = 6 },
	{ id = "quicksilverCrate", name = "Quicksilver Crate", kind = "crate", crate = "liquid4", tier = "Rare", weight = 5 },
	{ id = "fusionCrate", name = "Fusion Core Crate", kind = "crate", crate = "nuke5", tier = "Epic", weight = 3 },
	{ id = "plasmaCrate", name = "Plasma Charge Crate", kind = "crate", crate = "liquid5", tier = "Epic", weight = 2.5 },
	{ id = "luckBoost", name = "2x Luck 15 min", kind = "luckBoost", seconds = 15 * 60, tier = "Epic", weight = 2.5 },
	{ id = "cashBoost", name = "2x Cash 15 min", kind = "cashBoost", seconds = 15 * 60, tier = "Epic", weight = 2.5 },
	{ id = "cashVault", name = "Cash Vault", kind = "cash", minutes = 45, floor = 1000000, tier = "Legendary", weight = 1.2 },
	{ id = "legendaryNuke", name = "Legendary Nuke", kind = "nuke", rarity = "Legendary", tier = "Legendary", weight = 1 },
	{ id = "groundZeroCrate", name = "Mythic Crate", kind = "crate", crate = "nuke6", tier = "Mythic", weight = 2.1 },
	{ id = "mythicNuke", name = "Mythic Nuke", kind = "nuke", rarity = "Mythic", tier = "Mythic", weight = 0.3 },
	{ id = "riftCrate", name = "Anomaly Crate", kind = "crate", crate = "nuke7", tier = "Anomaly", weight = 0.53 },
	{ id = "anomalyNuke", name = "Anomaly Nuke", kind = "nuke", rarity = "Anomaly", tier = "Anomaly", weight = 0.05 },
} :: { PrizeDef }

local byId: { [string]: PrizeDef } = {}
local totalWeight = 0
for _, prize in Furnace.PRIZES do
	assert(byId[prize.id] == nil, `Furnace: duplicate prize {prize.id}`)
	assert(Rarity.DEFS[prize.tier] ~= nil, `Furnace: {prize.id} has unknown tier {prize.tier}`)
	byId[prize.id] = prize
	totalWeight += prize.weight
end

function Furnace.has(id: any): boolean
	return type(id) == "string" and byId[id] ~= nil
end

function Furnace.get(id: string): PrizeDef
	local prize = byId[id]
	assert(prize, `unknown furnace prize "{id}"`)
	return prize
end

--- One prize id from a 0..1 draw, by weight.
function Furnace.roll(u: number): string
	local pick = math.clamp(u, 0, 1) * totalWeight
	for _, prize in Furnace.PRIZES do
		pick -= prize.weight
		if pick <= 0 then
			return prize.id
		end
	end
	return Furnace.PRIZES[#Furnace.PRIZES].id
end

--- Each prize's chance, 0..1, for the panel's odds list.
function Furnace.chance(id: string): number
	return Furnace.get(id).weight / totalWeight
end

--- How much of the meter one copy fills. `item` is a save record or a described copy
--- (both carry `rarity`, `modifier`, `bonus` and `merge`).
function Furnace.fillOf(item: any): number
	if type(item) ~= "table" then
		return 0
	end
	if item.modifier == "Slagged" then
		return Furnace.SLAG_FILL
	end
	local base = Furnace.FILL[item.rarity] or Furnace.FILL.Common
	local good = 0
	for _, name in Rarity.qualities(item.modifier, item.bonus) do
		if Furnace.GOOD_QUALITIES[name] then
			good += 1
		end
	end
	local bonus = Furnace.QUALITY_BONUS * good + Furnace.MERGE_BONUS * Merge.levelOf(item)
	return math.max(1, math.floor(base * (1 + bonus) + 0.5))
end

--- Whether the panel should ask before burning this copy.
function Furnace.needsConfirm(item: any): boolean
	local def = if type(item) == "table" then Rarity.DEFS[item.rarity] else nil
	return def ~= nil and item.modifier ~= "Slagged" and def.order >= Rarity.get(Furnace.CONFIRM_FROM).order
end

return Furnace
