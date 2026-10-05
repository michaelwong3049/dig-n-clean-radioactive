--!strict
--[[
	Potions.luau — ten-minute boosts that come out of the Potion Crate (Config/Crates
	`potion1`). Nothing is held: opening the crate drops one potion into a stash
	(`data.potions`, id -> count), and you drink from the Potions panel (top-right
	corner row, PotionController).

	DRINKING BANKS TIME, like the Lucky Clover (Config/LuckBoost): each potion adds
	DURATION seconds to its own clock (`data.potionLeft[id]`), which counts down only
	while the player is in a server. Drinking one that is already running adds another
	ten minutes on top. Different potions run side by side and stack with each other
	and with every other boost.

	THE EFFECTS ARE APPLIED IN ONE PLACE, StatResolver, off `potionLeft`, so the dig
	roll, the sale, the stand payout, the haul, the wash and the walk speed all read
	the same answer:

	            (luckMultiplier). The same x2 as the Clover, and it stacks on top of it.
	            better buy; it stacks on top of it.
	  cash      x2   on every sale and every stand's income (sell + yield multipliers).
	  speed     x1.25 walk speed, on the same footing as the aura's speed bonus: after
	            the picker and the haul penalty (StatResolver.walkBonus), and shown on
	            the Walk Speed badge.
	  strength  x2   on `digPower`, the magnet's whole side of a haul (DigService).
	  clean     x2   on `scrubRate`, so the wash bay strips crust faster.

	The server publishes each running potion's end time as a Player attribute
	(`attrFor(id)`), so a late joiner's HUD has it on arrival (LuckBoost's note).
]]

local Potions = {}

export type PotionDef = {
	id: string,
	name: string,
	short: string, -- the HUD timer chip
	blurb: string, -- what it does, in the panel
	color: string, -- hex: the liquid, the card edge, the timer pill
	image: string, -- rbxassetid (tools/hud-icons/potion_<id>.svg)
	mult: number,
}

--- Seconds one potion adds to its clock.
Potions.DURATION = 10 * 60

--- A sanity ceiling on one potion's banked time, not a design lever.
Potions.MAX_BANKED_SECONDS = 6 * 60 * 60

--- The potion panel tile's own picture (tools/hud-icons/potions_tile.svg).
Potions.TILE_IMAGE = "rbxassetid://137386317510309"

--- Stable order: the panel's rows, the HUD chips, and the crate roll.
Potions.ORDER = { "luck", "cash", "speed", "strength", "clean" }

Potions.DEFS = {
	luck = {
		id = "luck",
		name = "Luck Potion",
		short = "Luck",
		blurb = "x2 luck on digs and the wash pad",
		color = "3FC94F",
		image = "rbxassetid://109888002736859",
		mult = 2,
	},
	cash = {
		id = "cash",
		name = "Cash Potion",
		short = "Cash",
		blurb = "x2 cash from sales and stands",
		color = "FFBE21",
		image = "rbxassetid://120916555692019",
		mult = 2,
	},
	speed = {
		id = "speed",
		name = "Speed Potion",
		short = "Speed",
		blurb = "+25% walk speed",
		color = "3F74FF",
		image = "rbxassetid://113485053938419",
		mult = 1.25,
	},
	strength = {
		id = "strength",
		name = "Strength Potion",
		short = "Strength",
		blurb = "x2 magnet power, so hauls come up faster",
		color = "F04A2E",
		image = "rbxassetid://119308481222971",
		mult = 2,
	},
	clean = {
		id = "clean",
		name = "Cleaning Potion",
		short = "Clean",
		blurb = "x2 wash speed on crusted finds",
		color = "25D3C9",
		image = "rbxassetid://97159203394716",
		mult = 2,
	},
} :: { [string]: PotionDef }

function Potions.has(id: any): boolean
	return type(id) == "string" and Potions.DEFS[id] ~= nil
end

function Potions.get(id: string): PotionDef
	local def = Potions.DEFS[id]
	assert(def, `unknown potion "{id}"`)
	return def
end

--- The Player attribute holding a running potion's end (server time); 0 = not running.
function Potions.attrFor(id: string): string
	return `Potion_{id}_EndsAt`
end

--- This potion's multiplier for a profile's banked seconds (`potionLeft`), or 1.
function Potions.multiplier(potionLeft: { [string]: number }?, id: string): number
	local left = potionLeft and potionLeft[id] or 0
	return if left > 0 then Potions.get(id).mult else 1
end

--- What the Potion Crate hands out: one potion, every one equally likely. `rng` is a
--- number in [0, 1).
function Potions.roll(rng: number): string
	local index = math.clamp(math.floor(rng * #Potions.ORDER) + 1, 1, #Potions.ORDER)
	return Potions.ORDER[index]
end

return Potions
