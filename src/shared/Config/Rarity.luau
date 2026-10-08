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

-- Anomaly has no single colour: anything that can animate walks it round this
-- spectrum (the user's pick off the rare-drop font mockup). Red, gold, green, sky,
-- violet, and back to red. `color` above stays white for anything that cannot move.
Rarity.ANOMALY_SPECTRUM = {
	Color3.fromHex("FF5F6D"),
	Color3.fromHex("FFC371"),
	Color3.fromHex("7EE06A"),
	Color3.fromHex("4FC3F7"),
	Color3.fromHex("B388FF"),
}
Rarity.ANOMALY_CYCLE = 6 -- seconds round the whole spectrum

--- The Anomaly colour at `phase` (any number; only its fraction counts), blended
--- smoothly between neighbouring stops.
function Rarity.anomalyHue(phase: number): Color3
	local stops = Rarity.ANOMALY_SPECTRUM
	local at = (phase % 1) * #stops
	local i = math.floor(at)
	return stops[i + 1]:Lerp(stops[(i + 1) % #stops + 1], at - i)
end

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
	Cracked = { valueMult = 0.4, fuseMult = 1.0, emissionMult = 1.0, yieldMult = 0.6, needsCleaning = true, weight = 20 },
	-- Not rolled. Applied by CarryService when the clock runs out. PLAN §7.
	Slagged = { valueMult = 0.1, fuseMult = 1.0, emissionMult = 1.0, yieldMult = 0.0, needsCleaning = true, weight = 0 },
}

-- EXTRA QUALITIES. A copy's `modifier` is its one rolled quality; a server-announced
-- drop (Config/RareDrop) can stack more on top, stored as `bonus` -- a list of
-- MODIFIERS keys, best first. Every quality's valueMult multiplies into the value and
-- each one nudges the stars; everything else (fuse, emission, crust) reads `modifier`
-- alone. A record without `bonus` (every ordinary dig) behaves exactly as before.

--- Every quality a copy carries, `modifier` first, "None" left out.
function Rarity.qualities(modifier: string?, bonus: { string }?): { string }
	local out = {}
	if modifier and modifier ~= "" and modifier ~= "None" then
		table.insert(out, modifier)
	end
	if type(bonus) == "table" then
		for _, name in bonus do
			if type(name) == "string" and name ~= "None" and not table.find(out, name) then
				table.insert(out, name)
			end
		end
	end
	return out
end

--- The value multiplier of all a copy's qualities together, multiplied.
function Rarity.valueMult(modifier: string?, bonus: { string }?): number
	local mult = 1
	for _, name in Rarity.qualities(modifier, bonus) do
		mult *= (Rarity.MODIFIERS[name] or Rarity.MODIFIERS.None).valueMult
	end
	return mult
end

--- `bonus` as one attribute-safe string ("Irradiated,Fused"), nil when empty.
function Rarity.bonusText(bonus: { string }?): string?
	if type(bonus) ~= "table" or #bonus == 0 then
		return nil
	end
	return table.concat(bonus, ",")
end

--- The reverse of bonusText, for an attribute read back on the client.
function Rarity.bonusFrom(text: any): { string }?
	if type(text) ~= "string" or text == "" then
		return nil
	end
	return string.split(text, ",")
end

function Rarity.get(name: string): RarityDef
	local def = Rarity.DEFS[name]
	assert(def, `unknown rarity "{name}"`)
	return def
end

-- THE STAR RATING, 1..Rarity.MAX_STARS (10). The rarity tier is the base (Rare = 4);
-- this copy's quality modifier, its per-dig size roll (Config/Payload) and the stage it
-- comes from then nudge it up or down, and the total is clamped. A modifier left out
-- of STAR_MODIFIER moves nothing. The scale is strict on purpose: a Stage 4 Legendary
-- Pristine is a good find (6) but 8-10 is kept for rare, late-stage, well-rolled copies.
-- It moves in HALF STARS: the size and stage nudges come in 0.5 steps and the total is
-- snapped to the nearest half. Client/StarRow draws the half as a real half star.
Rarity.MAX_STARS = 10

Rarity.STAR_MODIFIER = {
	Pristine = 1,
	Cracked = -1,
	Slagged = -2,
} :: { [string]: number }

-- Payload roll bands, checked in order: the first band the roll clears (`min`) or
-- falls under (`below`) sets the nudge; a roll matching none moves nothing. The two
-- upper edges are Payload.CALLOUTS' GIGA and HUGE, so a stickered find always
-- reads as more stars.
Rarity.STAR_SIZE = {
	{ min = 2.2, stars = 2 },
	{ min = 1.6, stars = 1 },
	{ min = 1.25, stars = 0.5 },
	{ below = 0.8, stars = -1 },
	{ below = 0.95, stars = -0.5 },
} :: { { min: number?, below: number?, stars: number } }

-- The nudge for the stage a nuke comes from (its home stage, Items.stageOf), indexed by
-- stage id; a stage past the end reads the last entry. Early-stage finds rate lower for
-- being early, climbing half a star every stage or two: -2 at Stages 1-2, -1 at 4-5,
-- none at 8-9, +1 at 12. No stage (a crate, a surface that doesn't know the item)
-- moves nothing.
Rarity.STAR_STAGE = { -2, -2, -1.5, -1, -1, -0.5, -0.5, 0, 0, 0.5, 0.5, 1 } :: { number }

--- How many stars a find rates. `modifier`, `payload`, `bonus` and `stage` are
--- optional: leave them out (a crate, a surface with no uid) and it is the plain rarity
--- tier. 0 for an unknown or missing rarity.
function Rarity.stars(name: string?, modifier: string?, payload: number?, bonus: { string }?, stage: number?): number
	local def = if name then Rarity.DEFS[name] else nil
	if def == nil then
		return 0
	end
	local stars = def.order
	for _, quality in Rarity.qualities(modifier, bonus) do
		stars += Rarity.STAR_MODIFIER[quality] or 0
	end
	if payload then
		for _, band in Rarity.STAR_SIZE do
			if (band.min and payload >= band.min) or (band.below and payload < band.below) then
				stars += band.stars
				break
			end
		end
	end
	if type(stage) == "number" and stage >= 1 then
		stars += Rarity.STAR_STAGE[math.min(math.floor(stage), #Rarity.STAR_STAGE)]
	end
	return math.clamp(math.floor(stars * 2 + 0.5) / 2, 1, Rarity.MAX_STARS)
end

function Rarity.byOrder(order: number): (string, RarityDef)
	local name = Rarity.ORDER[order]
	assert(name, `no rarity at order {order}`)
	return name, Rarity.DEFS[name]
end

return Rarity
