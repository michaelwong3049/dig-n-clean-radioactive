--!strict
--[[
	GamePasses.luau — the seven permanent Robux passes sold at the top of the Shop panel.

	A PASS IS OWNED, NOT GRANTED. Unlike a developer product there is no receipt and no
	"exactly once" to get right: Roblox remembers who owns what. Services/GamePassService
	asks it on every join (UserOwnsGamePassAsync) and on a purchase in-session, and mirrors
	the answer into `data.passes` (key -> true) so StatResolver -- pure, profile-only --
	can fold the effects in with everything else. The saved copy is only a cache for a
	join where the ownership check fails; a successful check always overwrites it.

	WHAT EACH ONE DOES, all applied in ONE place (StatResolver), so a pass cannot work in
	one system and silently not in another:

	  backpack      +BACKPACK_SLOTS bag capacity
	  bombDamage    bombDamageMult x BOMB_DAMAGE (BombService)
	  instantClean  every crust patch breaks the moment the hose's water touches it
	                (WashService.soakTarget); you still have to aim at each one
	  speed         treadmill training x SPEED (trainingMult). The user's call: it is the
	                training that doubles, not the walk speed
	  digPower      the magnet's whole side of a haul (yank + draw) x DIG_POWER (DigService)
	  luck          luckBoost x LUCK, so it stacks with the Violet Aurora and the clover
	                (2x / 4x / 8x) and reaches both the dig roll and the wash pad's luck
	  cash          sales and stand income x CASH (sellMultiplier + yieldMultiplier)
]]

local GamePasses = {}

export type Pass = { key: string, id: number, name: string, big: string, blurb: string }

GamePasses.BACKPACK_SLOTS = 50
GamePasses.BOMB_DAMAGE = 1.5
GamePasses.SPEED = 2
GamePasses.DIG_POWER = 2
GamePasses.LUCK = 2
GamePasses.CASH = 2

-- In Shop order. `big` is the card's headline number; ids are the Creator Dashboard's
-- Pass IDs (Monetization -> Passes). 0 = not set up yet: the card shows COMING SOON.
local PASSES: { Pass } = {
	{ key = "cash", id = 2006306411, name = "2x Cash", big = "2x", blurb = "Sales and stand income" },
	{ key = "luck", id = 2005322454, name = "2x Luck", big = "2x", blurb = "Dig and wash luck" },
	{ key = "digPower", id = 2006432462, name = "2x Dig Power", big = "2x", blurb = "Hauls come up faster" },
	{ key = "speed", id = 2005118459, name = "2x Speed", big = "2x", blurb = "Treadmills train 2x faster" },
	{ key = "backpack", id = 2006444530, name = "+50 Backpack Slots", big = "+50", blurb = "Bigger bag, forever" },
	{ key = "bombDamage", id = 2006456437, name = "1.5x Bomb Damage", big = "1.5x", blurb = "Every bomb hits harder" },
	{ key = "instantClean", id = 2006714459, name = "Instant Clean", big = "FAST", blurb = "Crust breaks on contact" },
}

GamePasses.PASSES = PASSES

-- Player attribute a pass is mirrored to, for the Shop card's OWNED state.
function GamePasses.attr(key: string): string
	return `Pass_{key}`
end

function GamePasses.byKey(key: string): Pass?
	for _, pass in PASSES do
		if pass.key == key then
			return pass
		end
	end
	return nil
end

function GamePasses.byId(id: number): Pass?
	for _, pass in PASSES do
		if pass.id == id then
			return pass
		end
	end
	return nil
end

--- Does this profile own `key`? Reads the `data.passes` mirror GamePassService writes.
function GamePasses.owns(profile: any, key: string): boolean
	local passes = profile.passes
	return passes ~= nil and passes[key] == true
end

return GamePasses
