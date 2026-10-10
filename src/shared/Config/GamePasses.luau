--!strict
--[[
	GamePasses.luau — the eight permanent Robux passes sold at the top of the Shop panel.

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
	  digPower      the magnet's whole side of a haul (yank + draw) x DIG_POWER (DigService)
	  luck          luckBoost x LUCK, so it stacks with the Violet Aurora and the clover
	                (2x / 4x / 8x) and reaches both the dig roll and the wash pad's luck
	  cash          sales and stand income x CASH (sellMultiplier + yieldMultiplier)
	  health        max health x HEALTH (healthMult, read by ExposureService.maxHealthOf)

	THE ONE EXCEPTION is autoMagnet, which is not a stat: while you are hauling, the
	client yanks the magnet for you AUTO_MAGNET_CPS times a second (DetectorController),
	through the same DigYank remote and the same server token bucket as a click, so it
	can never pull faster than a hand could. An AUTO pill on the haul bar turns it off
	and on, and offers the pass to anyone who does not own it.
]]

local GamePasses = {}

export type Pass = { key: string, id: number, name: string, image: string, blurb: string, color: Color3 }

GamePasses.BACKPACK_SLOTS = 50
GamePasses.BOMB_DAMAGE = 1.5
GamePasses.DIG_POWER = 2
GamePasses.LUCK = 2
GamePasses.CASH = 2
GamePasses.HEALTH = 2
-- Yanks a second while Auto Magnet is on: a brisk human mash, under the server's
-- sustained cap (Tuning.PULL_YANK_SUSTAINED_CPS), so mashing on top still helps.
GamePasses.AUTO_MAGNET_CPS = 6

-- In Shop order. Ids are the Creator Dashboard's Pass IDs (Monetization -> Passes);
-- 0 = not set up yet, and the card shows COMING SOON. `image` is the card's picture,
-- drawn in tools/hud-icons (pass_*.svg) like the HUD's other symbols. `color` tints
-- the card's name: cash green, luck clover, dig orange, bag leather, bomb red, clean
-- water cyan, health red, auto magnet steel blue. The 2x Speed pass (2005118459) went
-- with the treadmill (2026-10-09, on request); take it off sale on the Creator
-- Dashboard. Auto Magnet took its slot (2026-10-10) and wears the haul bar's own
-- magnet picture (tools/haul-art/magnet_icon.png).
local PASSES: { Pass } = {
	{ key = "cash", id = 2006306411, name = "2x Cash", image = "rbxassetid://130869946174411", blurb = "Sales and stand income", color = Color3.fromRGB(90, 230, 90) },
	{ key = "luck", id = 2005322454, name = "2x Luck", image = "rbxassetid://75584960857266", blurb = "Dig and wash luck", color = Color3.fromRGB(80, 220, 140) },
	{ key = "digPower", id = 2006432462, name = "2x Dig Power", image = "rbxassetid://129327782508122", blurb = "Hauls come up faster", color = Color3.fromRGB(255, 150, 50) },
	{ key = "autoMagnet", id = 0, name = "Auto Magnet", image = "rbxassetid://134150298550869", blurb = "Reels hauls in for you", color = Color3.fromRGB(130, 200, 255) },
	{ key = "backpack", id = 2006444530, name = "+50 Backpack Slots", image = "rbxassetid://86368048642838", blurb = "Bigger bag, forever", color = Color3.fromRGB(205, 160, 105) },
	{ key = "bombDamage", id = 2006456437, name = "1.5x Bomb Damage", image = "rbxassetid://103781789657404", blurb = "Every bomb hits harder", color = Color3.fromRGB(255, 75, 60) },
	{ key = "instantClean", id = 2006714459, name = "Instant Clean", image = "rbxassetid://119627521657381", blurb = "Crust breaks on contact", color = Color3.fromRGB(120, 235, 255) },
	{ key = "health", id = 2006078957, name = "2x Health", image = "rbxassetid://129831727951720", blurb = "Double your max HP", color = Color3.fromRGB(255, 110, 120) },
}

GamePasses.PASSES = PASSES

-- Group roles comped every pass (GamePassService). Matched by NAME, not rank: in the
-- game's group (GroupReward.GROUP_ID) Playtest shares rank 1 with plain Member, so a
-- rank threshold would hand passes to everyone who joins for the chest. The group's
-- owner (rank 255) is always comped too. Lose the role and the next join clears them.
GamePasses.COMP_ROLES = { Playtest = true }
GamePasses.COMP_MIN_RANK = 255

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
