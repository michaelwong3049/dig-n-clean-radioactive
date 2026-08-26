--!strict
-- Rarity.lua — the single column that drives three gates (PLAN §7).
--   hardness → can you CLEAN it      (cleaning tool potency, PLAN §2 step 4)
--   fuse     → can you GET IT HOME   (decay clock, PLAN §3.6)
--   yield    → what it pays DISPLAYED (exhibition, PLAN §8.2)

export type RarityDef = {
	order: number,
	color: Color3,
	hardness: number,
	fuse: number, -- seconds per decay condition
	displayYield: number, -- fraction of sale value paid per minute on a pedestal
	minValue: number,
	maxValue: number,
}

local Rarity = {}

Rarity.ORDER = {
	"Scrap",
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Anomaly",
}

Rarity.DEFS = {
	Scrap = { order = 1, color = Color3.fromHex("9AA0A6"), hardness = 1, fuse = 300, displayYield = 0.0200, minValue = 1, maxValue = 5 },
	Common = { order = 2, color = Color3.fromHex("E8EAED"), hardness = 1, fuse = 300, displayYield = 0.0200, minValue = 5, maxValue = 25 },
	Uncommon = { order = 3, color = Color3.fromHex("5CD65C"), hardness = 2, fuse = 240, displayYield = 0.0180, minValue = 25, maxValue = 120 },
	Rare = { order = 4, color = Color3.fromHex("4C9BE8"), hardness = 3, fuse = 180, displayYield = 0.0150, minValue = 120, maxValue = 700 },
	Epic = { order = 5, color = Color3.fromHex("A855F7"), hardness = 4, fuse = 150, displayYield = 0.0120, minValue = 700, maxValue = 4000 },
	Legendary = { order = 6, color = Color3.fromHex("F59E0B"), hardness = 5, fuse = 120, displayYield = 0.0080, minValue = 4000, maxValue = 30000 },
	Mythic = { order = 7, color = Color3.fromHex("EF4444"), hardness = 6, fuse = 90, displayYield = 0.0050, minValue = 30000, maxValue = 250000 },
	Anomaly = { order = 8, color = Color3.fromHex("FFFFFF"), hardness = 7, fuse = 75, displayYield = 0.0025, minValue = 250000, maxValue = 2000000 },
} :: { [string]: RarityDef }

-- Rolled on top of rarity (PLAN §7). fuseMult < 1 means it burns FASTER.
export type ModifierDef = {
	valueMult: number,
	fuseMult: number,
	emissionMult: number,
	yieldMult: number,
	needsCleaning: boolean,
	weight: number, -- relative roll weight; 0 = never rolled (Slagged is earned)
}

Rarity.MODIFIERS = {
	None = { valueMult = 1.0, fuseMult = 1.0, emissionMult = 1.0, yieldMult = 1.0, needsCleaning = true, weight = 100 },
	Pristine = { valueMult = 2.0, fuseMult = 1.0, emissionMult = 1.0, yieldMult = 1.3, needsCleaning = true, weight = 14 },
	Irradiated = { valueMult = 3.0, fuseMult = 0.6, emissionMult = 2.0, yieldMult = 1.0, needsCleaning = true, weight = 8 },
	Fused = { valueMult = 2.5, fuseMult = 1.0, emissionMult = 1.0, yieldMult = 1.0, needsCleaning = true, weight = 6 },
	PrewarSealed = { valueMult = 4.0, fuseMult = math.huge, emissionMult = 0.0, yieldMult = 1.0, needsCleaning = false, weight = 3 },
	Cracked = { valueMult = 0.4, fuseMult = 1.0, emissionMult = 1.0, yieldMult = 0.6, needsCleaning = true, weight = 20 },
	-- Not rolled. Applied by CarryService when the clock runs out. PLAN §7.
	Slagged = { valueMult = 0.1, fuseMult = 1.0, emissionMult = 1.0, yieldMult = 0.0, needsCleaning = true, weight = 0 },
}

function Rarity.get(name: string): RarityDef
	local def = Rarity.DEFS[name]
	assert(def, `unknown rarity "{name}"`)
	return def
end

function Rarity.byOrder(order: number): (string, RarityDef)
	local name = Rarity.ORDER[order]
	assert(name, `no rarity at order {order}`)
	return name, Rarity.DEFS[name]
end

return Rarity
