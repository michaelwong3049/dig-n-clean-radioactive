--!strict
--[[
	Masteries.luau — permanent all-time goals. DATA ONLY.

	Each mastery counts one lifetime number and has three tiers, Bronze, Silver and
	Gold. Reaching a tier sets that mastery's reward to the tier's value, and a higher
	tier REPLACES the one under it: Gold Scrubber is x2 cash, not 1.25 x 1.5 x 2.
	Two masteries paying the SAME kind add their tiers' steps from base together (none
	share one today; Mastery.value still adds them if they ever do).

	NOTHING ABOUT A MASTERY IS STORED BUT ITS COUNTER. Every counter only ever goes up
	(cleans, kills, lifetime cash, the deepest stage, the index), so the
	tier is read off it on demand (Shared/Mastery) and a tier once reached can never be
	lost. Retuning a goal re-tiers everyone on their next read, with no migration.

	THE REWARD IS FOLDED IN BY StatResolver, the one place gear math happens, so a
	mastery cannot work in one system and silently not in another. `reward` names the
	knob; Shared/Mastery.value turns a profile into its number, and `base` is that
	number before any tier is reached (a multiplier's 1, a bonus's 0, the away rate's
	stock 4%).

	`source` is what Shared/Mastery.count reads:
	  * a key of `data.stats` ("itemsCleaned", "kills", "dug", ...);
	  * "cashEarned", the lifetime number on the profile itself;
	  * "indexPercent", how much of the whole index has been found, 0-100.
]]

local Tuning = require(script.Parent.Tuning)

local Masteries = {}

export type Def = {
	id: string,
	name: string,
	-- What the counter is, as the panel captions it.
	counts: string,
	source: string,
	-- How many it takes to reach Bronze, Silver, Gold.
	goals: { number },
	-- How the goals are written: "$" for cash, "%" for a share, nil for a plain count.
	unit: string?,
	-- Shown counts and goals are the real number times this. Goals are in REAL units.
	shown: number?,
	reward: string,
	-- The reward at Bronze, Silver, Gold.
	values: { number },
	-- The panel's medal-well tint, so the rows tell apart at a glance.
	color: Color3,
}

Masteries.TIER_NAMES = { "Bronze", "Silver", "Gold" }
Masteries.TIER_COLORS = {
	Color3.fromRGB(214, 133, 74),
	Color3.fromRGB(205, 216, 228),
	Color3.fromRGB(255, 205, 52),
}

--- What each reward is before any tier: the value Shared/Mastery.value falls back to.
Masteries.BASE = {
	cash = 1, -- x on every sale and every stand's income
	bombDamage = 1, -- x on a dropped nuke's blast
	walkSpeed = 0, -- + share of walk speed (0.02 = +2%); every mastery paying it ADDS
	luck = 1, -- x on luck (the wash pad's roll and the merge crit)
	capacity = 0, -- + bag slots
	radDamage = 1, -- x on the health radiation takes (aura wear, aura failure, sickness)
	mergeFee = 1, -- x on the Merge Reactor's fee
	brewCooldown = 1, -- x on the fluid bottle's cooldown
	awayRate = Tuning.EXHIBIT_OFFLINE_RATE, -- the share of $/s the stands pay offline
}

Masteries.LIST = {
	{
		id = "scrubber",
		name = "Scrubber",
		counts = "Nukes cleaned",
		source = "itemsCleaned",
		goals = { 100, 400, 1000 },
		reward = "cash",
		values = { 1.25, 1.5, 2 },
		color = Color3.fromRGB(86, 212, 71),
	},
	{
		id = "bomber",
		name = "Bomber",
		counts = "Players blown up",
		source = "kills",
		goals = { 10, 25, 50 },
		-- Walk speed 2026-10-08 (#1150), back to bomb damage 2026-10-10 on request.
		reward = "bombDamage",
		values = { 1.15, 1.3, 1.5 },
		color = Color3.fromRGB(229, 72, 77),
	},
	{
		id = "prospector",
		name = "Prospector",
		counts = "Nukes dug up",
		source = "dug",
		goals = { 250, 1000, 3000 },
		reward = "luck",
		values = { 1.1, 1.2, 1.35 },
		color = Color3.fromRGB(196, 140, 72),
	},
	{
		id = "collector",
		name = "Collector",
		counts = "Index found",
		source = "indexPercent",
		goals = { 25, 50, 100 },
		unit = "%",
		reward = "capacity",
		values = { 2, 4, 6 },
		color = Color3.fromRGB(171, 112, 255),
	},
	{
		id = "deepDiver",
		name = "Deep Diver",
		counts = "Deepest stage",
		source = "deepestStage",
		goals = { 4, 8, 12 },
		reward = "radDamage",
		values = { 0.9, 0.8, 0.7 },
		color = Color3.fromRGB(64, 224, 140),
	},
	{
		id = "reactor",
		name = "Reactor",
		counts = "Merges",
		source = "merges",
		goals = { 10, 50, 150 },
		reward = "mergeFee",
		values = { 0.9, 0.8, 0.7 },
		color = Color3.fromRGB(255, 120, 200),
	},
	{
		id = "thief",
		name = "Thief",
		counts = "Bags stolen",
		source = "bagsStolen",
		goals = { 10, 25, 50 },
		reward = "walkSpeed",
		values = { 0.02, 0.04, 0.06 },
		color = Color3.fromRGB(150, 160, 175),
	},
	{
		id = "brewer",
		name = "Brewer",
		counts = "Fluids brewed",
		source = "rolls",
		goals = { 25, 100, 300 },
		reward = "brewCooldown",
		values = { 0.85, 0.7, 0.5 },
		color = Color3.fromRGB(80, 220, 230),
	},
	{
		id = "tycoon",
		name = "Tycoon",
		counts = "Lifetime cash",
		source = "cashEarned",
		goals = { 10e6, 1e9, 50e9 },
		unit = "$",
		reward = "awayRate",
		-- A third of the old 0.05/0.06/0.08, to match the 12 h bank (Tuning.EXHIBIT_OFFLINE_*).
		values = { 0.016, 0.02, 0.026 },
		color = Color3.fromRGB(255, 205, 52),
	},
} :: { Def }

return Masteries
