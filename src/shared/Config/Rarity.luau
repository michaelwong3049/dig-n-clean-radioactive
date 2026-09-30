--!strict
-- Rarity.lua — the single column that drives three gates (PLAN §7).
--   hardness → can you CLEAN it      (cleaning tool potency, PLAN §2 step 4)
--   fuse     → can you GET IT HOME   (decay clock, PLAN §3.6)
--   yield    → what it pays DISPLAYED (exhibition, PLAN §8.2)
--
-- ECONOMY RESCALE (feat/economy-rescale-display-income): the whole economy was
-- multiplied by 20/3 (~6.667x) so the cheapest item, the Bottle Cap, sells for $20 --
-- item baseValues, the minValue/maxValue bands here, every shop price in Config/Gear,
-- Gear.LUCK_START_PRICE and Tuning.LIQUID_ROLL_COST all moved by that one factor, so the
-- active sell->buy loop plays at exactly the pace it did before. `displayYield` is the
-- deliberate exception: it moved x300 (not x6.667), taking per-displayed-item income up
-- x2000 overall, which is what turns the Exhibition from a rounding error into the
-- primary loop (Bottle Cap: $0.001/sec -> $2.00/sec). The hourly income cap that used
-- to sit on top of it is gone (balance/economy-pacing-pass); stands pay in full.

export type RarityDef = {
	order: number,
	color: Color3,
	hardness: number,
	fuse: number, -- seconds per decay condition
	displayYield: number, -- multiple of sale value paid per minute on a pedestal (6.0 = 600%/min)
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

-- `color` is the one rarity signal shared across the whole game: the aura well tint
-- and radar blip (DigService/FieldController), the index cards, the hotbar slots, the
-- station list, the exhibit pedestals, the unearth banner. It has to read at a glance
-- against the brown/green stage grounds AND as small HUD text.
--   * Rare is a TRUE blue (3D7BF5), deliberately clear of the instrument cyan (2E9FD8)
--     the neutral well and the range ring use — the two were near-identical before.
--   * Common is a pale slate, not pure white, so white belongs to Anomaly alone.
--   * Scrap stays a dull grey (it is junk) but lifted enough to hold on dark ground.
Rarity.DEFS = {
	Scrap = { order = 1, color = Color3.fromHex("AAB2BC"), hardness = 1, fuse = 300, displayYield = 6.0, minValue = 5, maxValue = 35 },
	Common = { order = 2, color = Color3.fromHex("CFDCEA"), hardness = 1, fuse = 300, displayYield = 6.0, minValue = 35, maxValue = 170 },
	Uncommon = { order = 3, color = Color3.fromHex("5CD65C"), hardness = 2, fuse = 240, displayYield = 5.4, minValue = 170, maxValue = 800 },
	Rare = { order = 4, color = Color3.fromHex("3D7BF5"), hardness = 3, fuse = 180, displayYield = 4.5, minValue = 800, maxValue = 4700 },
	Epic = { order = 5, color = Color3.fromHex("A855F7"), hardness = 4, fuse = 150, displayYield = 3.6, minValue = 4700, maxValue = 27000 },
	Legendary = { order = 6, color = Color3.fromHex("F59E0B"), hardness = 5, fuse = 120, displayYield = 2.4, minValue = 27000, maxValue = 200000 },
	Mythic = { order = 7, color = Color3.fromHex("EF4444"), hardness = 6, fuse = 90, displayYield = 1.5, minValue = 200000, maxValue = 1700000 },
	Anomaly = { order = 8, color = Color3.fromHex("FFFFFF"), hardness = 7, fuse = 75, displayYield = 0.75, minValue = 1700000, maxValue = 13300000 },
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

-- THE STAR RATING, 1..Rarity.MAX_STARS. The rarity tier is the base (Rare = 4); this
-- copy's quality modifier and its per-dig size roll (Config/Payload) then nudge it up or
-- down, and the total is clamped. A modifier left out of STAR_MODIFIER moves nothing.
Rarity.MAX_STARS = #Rarity.ORDER

Rarity.STAR_MODIFIER = {
	Pristine = 1,
	PrewarSealed = 1,
	Cracked = -1,
	Slagged = -2,
} :: { [string]: number }

-- Payload roll bands, checked in order: the first band the roll clears (`min`) or
-- falls under (`below`) sets the nudge; a roll matching none moves nothing. The two
-- upper edges are Payload.CALLOUTS' GIGA and OVERSIZED, so a stickered find always
-- reads as more stars.
Rarity.STAR_SIZE = {
	{ min = 2.2, stars = 2 },
	{ min = 1.6, stars = 1 },
	{ below = 0.8, stars = -1 },
} :: { { min: number?, below: number?, stars: number } }

--- How many stars a find rates. `modifier` and `payload` are optional: leave them out
--- (a crate, a surface with no uid) and it is the plain rarity tier. 0 for an unknown
--- or missing rarity.
function Rarity.stars(name: string?, modifier: string?, payload: number?): number
	local def = if name then Rarity.DEFS[name] else nil
	if def == nil then
		return 0
	end
	local stars = def.order + (if modifier then Rarity.STAR_MODIFIER[modifier] or 0 else 0)
	if payload then
		for _, band in Rarity.STAR_SIZE do
			if (band.min and payload >= band.min) or (band.below and payload < band.below) then
				stars += band.stars
				break
			end
		end
	end
	return math.clamp(stars, 1, Rarity.MAX_STARS)
end

--- The star rating as text, one filled star each ("★★★★"). Empty for an unknown or
--- missing rarity.
function Rarity.starText(name: string?, modifier: string?, payload: number?): string
	return string.rep("\u{2605}", Rarity.stars(name, modifier, payload))
end

function Rarity.byOrder(order: number): (string, RarityDef)
	local name = Rarity.ORDER[order]
	assert(name, `no rarity at order {order}`)
	return name, Rarity.DEFS[name]
end

return Rarity
