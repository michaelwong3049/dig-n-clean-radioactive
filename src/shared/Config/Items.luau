--!strict
--[[
	Items.lua — the catalogue. Data only, like everything else in Config/.

	Stages 1-6, ~68 items, Scrap through Anomaly.

	REWORKED FOR A LIGHTER, TREASURE-HUNT TONE, ON REQUEST. The catalogue used to
	lean on real-world war and disaster imagery (dog tags, mortar rounds, cipher
	cases, an evacuation ledger counting the dead) — evocative, but too dark and
	too specific for the audience this game is actually for. The radioactive
	wasteland setting stays; what changed is what you find in it. Gold, jewelry,
	old toys, and a few things that are frankly a little silly (a rubber duck,
	a mutant carrot, a mini nuke) read as "dig for treasure" instead of "excavate
	a tragedy" — same six stages, same rarity ladder, with seven items modelled in 3D
	(bottle_cap, steel_rod, tin_can, house_key, stopped_watch, rubber_duck, gold_ring).

	A STAGE WITH NO ITEMS IS NOT A CRASH ANY MORE, BUT IT IS STILL BROKEN. The dig roll
	(see "The dig roll" at the foot of this file) only picks from what a stage actually
	stocks -- there is no rarity step-down any more -- so an unstocked stage simply
	spawns no signals and warns once. But a stage stocked only at the top still fills
	slowly and reads wrong: stock the LOW end of every stage you add, weighted by
	`odds`, and let Config/Stages' `rarityTilt` do the "this stage is rich" work.

	STAGES 3-6 NO LONGER STOCK SCRAP, ON REQUEST. Their old Scrap-tier items folded up
	into Common (and Stage 5/6 also promoted one former Common slot to Uncommon), so the
	FLOOR for those four stages is Common rather than Scrap. Nothing special is needed
	to make that work now -- the roll picks from stocked items only.

	TWO RULES, both from ARCHITECTURE.md, both cheap now and miserable to retrofit:

	1. FLAVOR TEXT CARRIES A STORY. "Child's lunchbox, dented, still latched" hits
	   far harder than "Rare Metal Object #7", costs the same to store, and doubles as
	   the game's best marketing surface once exhibits are public (PLAN §8.6).

	2. EVERY ITEM HAS AN `appeal`. Researcher / Collector / Gearhead — the visitor
	   type that comes to see it (PLAN §8.3). Tag it as you write the item. That one
	   field is what turns a loot table into a museum, and adding it across a finished
	   catalogue later is exactly the job nobody does.

	baseValue must sit inside its rarity's band in Rarity.DEFS. Stage 1 deliberately
	carries a Legendary: PLAN §4 wants "it could happen right here" live from minute
	one, because that chance is what keeps a new player sweeping.

	ECONOMY RESCALE (feat/economy-rescale-display-income): every baseValue below was
	multiplied by 20/3 (~6.667x) and rounded to two significant figures, anchored so the
	Bottle Cap sells for $20. The rarity bands in Rarity.DEFS moved by the same factor, so
	every entry still sits inside its band. See Config/Rarity.luau's header for the whole
	picture -- the short version is that shop prices moved by the same 20/3, so the
	sell->buy loop is unchanged, and only Rarity.displayYield moved differently (x300).

	`model` is optional while the catalogue art is produced. Entries without one keep
	the rarity-coloured placeholder; entries with one resolve through Shared.ItemModels.
]]

local Rarity = require(script.Parent.Rarity)

export type ItemDef = {
	id: string,
	name: string,
	flavor: string,
	rarity: string,
	-- Authored "1 in N" find-rarity. It DRIVES THE ROLL now (it used to be display
	-- only): an item's base weight in a stage is 1/odds, so a "1 in 100" item turns up
	-- a tenth as often as a "1 in 10" one. Two knobs bend that base -- Config/Stages'
	-- per-stage `rarityTilt`, and the digging player's detector luck at Rare and above
	-- -- see "The dig roll" at the foot of this file. It is still the collectible
	-- headline shown in the Index and on a sharp detector ping, hand-set per item so it
	-- can be round and readable; the tilt means the number a player SEES is the
	-- across-the-catalogue rarity, not the literal in-stage rate. One value covers
	-- every stage an item is stocked in (the handful that span Stage 3<->4 share it on
	-- purpose).
	odds: number,
	stages: { number },
	appeal: string, -- "Researcher" | "Collector" | "Gearhead"
	sets: { string },
	baseValue: number,
	model: string?,
}

local Items = {}

Items.DEFS = {
	-- ── Scrap ── $5-35 ──────────────────────────────────────────────────────
	{
		id = "bottle_cap",
		name = "Bottle Cap",
		flavor = "Bent double. The logo is still readable if you squint.",
		rarity = "Scrap",
		odds = 5, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 20,
		model = "BottleCap",
	},
	{
		id = "steel_rod",
		name = "Steel Rod",
		flavor = "Snapped clean through. Something very large came this way.",
		rarity = "Scrap",
		odds = 6, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 27,
		model = "SteelRod",
	},
	{
		id = "glass_pebble",
		name = "Glass Pebble",
		flavor = "Sand that got so hot it melted into a smooth little marble.",
		rarity = "Scrap",
		odds = 8, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 33,
	},

	-- ── Common ── $35-170 ─────────────────────────────────────────────────
	{
		id = "tin_can",
		name = "Dented Tin Can",
		flavor = "Peaches. The label survived better than the peaches did.",
		rarity = "Common",
		odds = 9, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 80,
		model = "DentedTinCan",
	},
	{
		id = "house_key",
		name = "House Key",
		flavor = "Still on its ring, with two smaller ones beside it.",
		rarity = "Common",
		odds = 12, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 120,
		model = "HouseKey",
	},
	{
		id = "stopped_watch",
		name = "Stopped Wristwatch",
		flavor = "Stopped at 8:14. So did everyone else's.",
		rarity = "Common",
		odds = 15, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 150,
		model = "Wristwatch",
	},
	{
		id = "radioactive_rubber_duck",
		name = "Radioactive Rubber Duck",
		flavor = "It glows in the dark. It always did, actually.",
		rarity = "Common",
		odds = 40, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 93,
		model = "RubberDuck",
	},

	-- ── Uncommon ── $170-800 ─────────────────────────────────────────────
	-- NOTE: Uncommon is hardness 2 and a Wire Brush is potency 1, so the first of
	-- these a new player digs CANNOT be cleaned yet. That is the §6 staggered reveal
	-- working — but it also contradicts PLAN §12, whose scripted tutorial has you
	-- clean and sell a rigged Uncommon 90 seconds in. Flagged, not silently patched.
	{
		id = "tin_soldier",
		name = "Tin Soldier",
		flavor = "A tiny toy soldier, paint chipped, forever standing guard.",
		rarity = "Uncommon",
		odds = 45, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Collector",
		sets = { "childrens_toys" },
		baseValue = 300,
	},
	{
		id = "wind_up_flashlight",
		name = "Wind-Up Flashlight",
		flavor = "Give the crank a few turns and it still lights up, just for a second.",
		rarity = "Uncommon",
		odds = 60, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Gearhead",
		sets = { "salvage_kit" },
		baseValue = 400,
	},
	{
		id = "gold_ring",
		name = "Gold Ring",
		flavor = "A gold ring, still shining under all the dust.",
		rarity = "Uncommon",
		odds = 90, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 570,
		model = "GoldRing",
	},

	-- ── Rare ── $800-4.7k ───────────────────────────────────────────────
	{
		id = "radiation_scanner",
		name = "Radiation Scanner",
		flavor = "Clicks faster the closer you get to something glowing.",
		rarity = "Rare",
		odds = 200, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Gearhead",
		sets = { "salvage_kit" },
		baseValue = 2300,
	},
	{
		id = "film_canister",
		name = "Sealed Film Canister",
		flavor = "Thirty-six photos, never developed. Who knows what's on them.",
		rarity = "Rare",
		odds = 260, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 3200,
	},

	-- ── Epic ── $4.7k-27k ─────────────────────────────────────────────────
	{
		id = "sample_case",
		name = "Sample Case",
		flavor = "Six glass vials. One of them glows all on its own.",
		rarity = "Epic",
		odds = 1200, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 13000,
	},

	-- ── Legendary ── $27k-200k ────────────────────────────────────────────
	-- 0.15% in Stage 1. Almost nobody will see this. That is the point.
	{
		id = "treasure_map",
		name = "Old Treasure Map",
		flavor = "A hand-drawn map, half burnt. Something's marked with three stars and no name.",
		rarity = "Legendary",
		odds = 2500, -- 1 in N per dig in a stocking stage
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 63000,
	},

	-- ══ STAGE 2 — THE SUBURBS ═══════════════════════════════════════════════
	-- Collapsed houses and half-buried cars (PLAN §4). The theme is a life
	-- interrupted mid-sentence, so the flavor leans domestic rather than martial.

	{
		id = "cracked_tile",
		name = "Cracked Tile",
		flavor = "Someone chose this pattern once.",
		rarity = "Scrap",
		odds = 5, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Collector",
		sets = { "suburban_kitchen" },
		baseValue = 20,
	},
	{
		id = "door_hinge",
		name = "Door Hinge",
		flavor = "Still swings, even with no door left to hold.",
		rarity = "Scrap",
		odds = 7, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 27,
	},
	{
		id = "cutlery_set",
		name = "Cutlery Set",
		flavor = "Wrapped in a napkin, waiting for a dinner that never happened.",
		rarity = "Common",
		odds = 10, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Collector",
		sets = { "suburban_kitchen" },
		baseValue = 93,
	},
	{
		id = "garden_trowel",
		name = "Garden Trowel",
		flavor = "Left in the soil, handle up, like it would be picked up tomorrow.",
		rarity = "Common",
		odds = 13, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 130,
	},
	{
		id = "doll_head",
		name = "Porcelain Doll Head",
		flavor = "The eyes still blink open and shut. A little spooky, a little funny.",
		rarity = "Common",
		odds = 25, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Collector",
		sets = { "childrens_toys" },
		baseValue = 150,
	},
	{
		id = "charm_bracelet",
		name = "Charm Bracelet",
		flavor = "Eleven tiny charms — a bicycle, a cat, a little house.",
		rarity = "Uncommon",
		odds = 45, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 370,
	},
	{
		id = "socket_set",
		name = "Socket Wrench Set",
		flavor = "Every socket still in its slot. Whoever owned this was particular about it.",
		rarity = "Uncommon",
		odds = 55, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 480,
	},
	{
		id = "photo_locket",
		name = "Photo Locket",
		flavor = "Two tiny photos, one hinge. The catch still works.",
		rarity = "Uncommon",
		odds = 70, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 650,
	},
	{
		id = "mutant_carrot",
		name = "Mutant Carrot",
		flavor = "Three feet long and still bright orange. The rabbits are thrilled.",
		rarity = "Uncommon",
		odds = 120, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Researcher",
		sets = {},
		baseValue = 330,
	},
	{
		id = "pearl_necklace",
		name = "Pearl Necklace",
		flavor = "Kept for good occasions — there was one more pearl, somewhere.",
		rarity = "Rare",
		odds = 240, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 2100,
	},
	{
		id = "ignition_coil",
		name = "Ignition Coil",
		flavor = "Pulled from a car pointed away from town, tank full, doors open.",
		rarity = "Rare",
		odds = 200, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 3000,
	},
	{
		id = "clock_movement",
		name = "Grandfather Clock Movement",
		flavor = "Brass gears, hand-cut, unbothered. It would still run today.",
		rarity = "Epic",
		odds = 1500, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 11000,
	},
	{
		id = "deposit_box",
		name = "Safe Deposit Box",
		flavor = "Whatever was worth a bank vault is still inside, and it's yours now.",
		rarity = "Legendary",
		odds = 3000, -- 1 in N per dig in a stocking stage
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 55000,
	},

	-- ══ STAGE 3 — FALLOUT FIELDS ════════════════════════════════════════════
	-- Old farmland scorched by the fallout, not a battlefield — reworked on
	-- request to drop the military angle (dog tags, ordnance, cipher cases)
	-- in favor of what you'd actually expect buried under an abandoned
	-- homestead: buried coins, gold, farm tools, everyday relics. NO SCRAP
	-- TIER (see this file's header) — its old Scrap items folded into Common.
	-- Several of these are also tagged for Stage 4: the Exclusion Belt is the
	-- same stretch of country, further in, and a dive still wants a stocked low
	-- end so the roll is not all Legendaries.

	{
		id = "rusty_horseshoe",
		name = "Rusty Horseshoe",
		flavor = "A rusted horseshoe. There was a barn out here once.",
		rarity = "Common",
		odds = 8, -- 1 in N per dig in a stocking stage
		stages = { 3, 4 },
		appeal = "Gearhead",
		sets = { "abandoned_farm" },
		baseValue = 53,
	},
	{
		id = "gate_latch",
		name = "Bent Gate Latch",
		flavor = "Snapped clean off. The fence went with it.",
		rarity = "Common",
		odds = 10, -- 1 in N per dig in a stocking stage
		stages = { 3, 4 },
		appeal = "Gearhead",
		sets = { "abandoned_farm" },
		baseValue = 73,
	},
	{
		id = "old_food_tin",
		name = "Old Food Tin",
		flavor = "Unopened. The label wore off long ago.",
		rarity = "Common",
		odds = 14, -- 1 in N per dig in a stocking stage
		stages = { 3, 4 },
		appeal = "Collector",
		sets = {},
		baseValue = 110,
	},
	{
		id = "first_aid_tin",
		name = "First-Aid Tin",
		flavor = "A little dented, but everything inside is still sealed.",
		rarity = "Uncommon",
		odds = 40, -- 1 in N per dig in a stocking stage
		stages = { 3, 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 300,
	},
	{
		id = "unlit_signal_flare",
		name = "Unlit Signal Flare",
		flavor = "Never got its chance to light up the sky.",
		rarity = "Uncommon",
		odds = 55, -- 1 in N per dig in a stocking stage
		stages = { 3 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 500,
	},
	{
		id = "old_compass",
		name = "Old Compass",
		flavor = "Still points somewhere — just not always north anymore.",
		rarity = "Uncommon",
		odds = 60, -- 1 in N per dig in a stocking stage
		stages = { 3 },
		appeal = "Researcher",
		sets = {},
		baseValue = 430,
	},
	{
		id = "broken_lantern",
		name = "Broken Lantern",
		flavor = "No oil left, but it still swings a little in the wind.",
		rarity = "Uncommon",
		odds = 50, -- 1 in N per dig in a stocking stage
		stages = { 3, 4 },
		appeal = "Gearhead",
		sets = { "abandoned_farm" },
		baseValue = 630,
	},
	{
		id = "gold_signet",
		name = "Gold Signet Ring",
		flavor = "Gold doesn't care about any of this. That's why it's worth something.",
		rarity = "Rare",
		odds = 300, -- 1 in N per dig in a stocking stage
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 2500,
	},
	{
		id = "radiation_badge",
		name = "Radiation Badge",
		flavor = "Changes color the longer it sits out here. It's been out here a while.",
		rarity = "Rare",
		odds = 220, -- 1 in N per dig in a stocking stage
		stages = { 3, 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 4300,
	},
	{
		id = "buried_coin_jar",
		name = "Buried Coin Jar",
		flavor = "A glass jar, still packed with old coins. Somebody was saving up.",
		rarity = "Rare",
		odds = 280, -- 1 in N per dig in a stocking stage
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 3700,
	},
	{
		id = "bullion_bar",
		name = "Gold Bullion Bar",
		flavor = "Someone carried this out of a vault, into a field, and got no further.",
		rarity = "Epic",
		odds = 1600, -- 1 in N per dig in a stocking stage
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 16000,
	},
	{
		id = "diamond_brooch",
		name = "Diamond Brooch",
		flavor = "A stone that catches light no one else out here can see.",
		rarity = "Epic",
		odds = 2200, -- 1 in N per dig in a stocking stage
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 19000,
	},
	{
		id = "rusted_farm_safe",
		name = "Rusted Farm Safe",
		flavor = "Buried under the old farmhouse. Whatever's inside has been waiting a long time.",
		rarity = "Legendary",
		odds = 4000, -- 1 in N per dig in a stocking stage
		stages = { 3, 4 },
		appeal = "Collector",
		sets = {},
		baseValue = 60000,
	},

	-- ══ STAGE 4 — THE EXCLUSION BELT ════════════════════════════════════════
	-- Prewar tech and lab samples (PLAN §4). Deliberately thin and top-heavy:
	-- PLAN §15 wants Stage 4 to have a loot table and a rad rate and nothing else,
	-- because its job is to answer "will players dive?", not to be farmed. The
	-- Stage-3 items tagged { 3, 4 } above carry its lower rarities; no Scrap tier
	-- here either, same as Stage 3.

	{
		id = "glowing_sample_jar",
		name = "Glowing Sample Jar",
		flavor = "A jar that glows a soft green, even in the dark.",
		rarity = "Rare",
		odds = 180, -- 1 in N per dig in a stocking stage
		stages = { 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 4400,
	},
	{
		id = "strange_metal_chip",
		name = "Strange Metal Chip",
		flavor = "Covered in markings nobody recognizes. Hums faintly if you hold it.",
		rarity = "Epic",
		odds = 1400, -- 1 in N per dig in a stocking stage
		stages = { 4 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 23000,
	},
	{
		id = "reactor_rod",
		name = "The Reactor Rod",
		flavor = "The rod that kept the reactor calm. It's the whole reason there's a Belt and not something worse.",
		rarity = "Legendary",
		odds = 5000, -- 1 in N per dig in a stocking stage
		stages = { 4 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 120000,
	},

	-- ══ STAGE 5 — REACTOR GROUNDS ═══════════════════════════════════════════
	-- Cooling towers and heat shimmer (PLAN §4). Fuel rods, control tech, black-box
	-- data. `reactor_control` extends across the Stage 4 boundary on purpose — Stage 5
	-- sits right next to the Belt in the chain and both are reactor-adjacent tech,
	-- so the set reads as one storyline rather than two unrelated tags. NO SCRAP
	-- TIER (see this file's header) — its old Scrap items folded into Common, and
	-- the old pressure_gauge Common slot promoted to Uncommon.

	{
		id = "old_pipe_scrap",
		name = "Old Pipe Scrap",
		flavor = "Split down a seam. Whatever it carried isn't in it anymore.",
		rarity = "Common",
		odds = 7, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 60,
	},
	{
		id = "shiny_metal_blade",
		name = "Shiny Metal Blade",
		flavor = "Curved like it was cutting something, once.",
		rarity = "Common",
		odds = 9, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Researcher",
		sets = {},
		baseValue = 67,
	},
	{
		id = "rad_warning_placard",
		name = "Radiation Warning Placard",
		flavor = "The symbol's still bright. Everything around it isn't.",
		rarity = "Common",
		odds = 12, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Collector",
		sets = {},
		baseValue = 100,
	},
	{
		id = "pressure_gauge",
		name = "Pressure Gauge",
		flavor = "Needle buried past the red.",
		rarity = "Uncommon",
		odds = 40, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 400,
	},
	{
		id = "old_headphones",
		name = "Old Headphones",
		flavor = "Big and cushioned. Only one side still crackles with static.",
		rarity = "Uncommon",
		odds = 50, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Gearhead",
		sets = { "reactor_control" },
		baseValue = 430,
	},
	{
		id = "cooling_valve_wheel",
		name = "Cooling Valve Wheel",
		flavor = "A big metal wheel that used to turn off the water. It won't budge now.",
		rarity = "Uncommon",
		odds = 65, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 600,
	},
	{
		id = "reactor_logbook",
		name = "Reactor Logbook",
		flavor = "The last page has one word on it, underlined twice.",
		rarity = "Rare",
		odds = 240, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 2800,
	},
	{
		id = "sealed_data_drive",
		name = "Sealed Data Drive",
		flavor = "Locked in a lead case. Someone wanted this kept safe.",
		rarity = "Rare",
		odds = 300, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Researcher",
		sets = {},
		baseValue = 3900,
	},
	{
		id = "blackbox_recorder",
		name = "Black-Box Recorder",
		flavor = "Built to survive anything. Lots of practice at it.",
		rarity = "Epic",
		odds = 1500, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 17000,
	},
	{
		id = "sealed_fuel_casing",
		name = "Sealed Fuel Rod Casing",
		flavor = "Empty now, but it used to hold something that glowed.",
		rarity = "Epic",
		odds = 1800, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 21000,
	},
	{
		id = "reactor_core_sample",
		name = "Reactor Core Sample",
		flavor = "Warm through three layers of metal. Never once cooled down.",
		rarity = "Legendary",
		odds = 6000, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 100000,
	},
	{
		id = "live_fuel_rod",
		name = "Live Fuel Rod",
		flavor = "Still glowing. Still humming. Exactly as dangerous as the day it was made.",
		rarity = "Mythic",
		odds = 50000, -- 1 in N per dig in a stocking stage
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 600000,
	},

	-- ══ STAGE 6 — THE CRATER ════════════════════════════════════════════════
	-- Glassed floor, sky-glow, no ambient sound (PLAN §4). Anomalies, one-of-a-kind
	-- relics — plus a couple of fun, deliberately-not-realistic finds (on request,
	-- the game doesn't have to play it straight everywhere). `crater_relics` ties
	-- the three showpiece items into one thread, the way `left_behind` does for
	-- Stage 1. NO SCRAP TIER (see this file's header) — its old Scrap item folded
	-- into Common.

	{
		id = "glassy_ground_chip",
		name = "Glassy Ground Chip",
		flavor = "The sand didn't burn — it turned to glass, all at once.",
		rarity = "Common",
		odds = 8, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 47,
	},
	{
		id = "scorched_metal_plate",
		name = "Scorched Metal Plate",
		flavor = "Rated to hold back anything. Didn't.",
		rarity = "Common",
		odds = 11, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 120,
	},
	{
		id = "sealed_air_filter",
		name = "Sealed Air Filter",
		flavor = "Still wrapped. Nobody who needed it got the chance to open it.",
		rarity = "Uncommon",
		odds = 35, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 470,
	},
	{
		id = "bent_door_wheel",
		name = "Bent Door Wheel",
		flavor = "Spun the wrong way, hard.",
		rarity = "Uncommon",
		odds = 55, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 700,
	},
	{
		id = "cracked_glow_badge",
		name = "Cracked Glow Badge",
		flavor = "Went dark in under a second.",
		rarity = "Rare",
		odds = 220, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 3100,
	},
	{
		id = "fused_tool_roll",
		name = "Fused Tool Roll",
		flavor = "Every tool welded to the canvas, and to each other.",
		rarity = "Rare",
		odds = 260, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 4300,
	},
	{
		id = "untouched_ground_sample",
		name = "Untouched Ground Sample",
		flavor = "One square foot of ordinary dirt, sealed in glass, found at the center of everything.",
		rarity = "Epic",
		odds = 1400, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 22000,
	},
	{
		id = "skyglow_core_fragment",
		name = "Sky-Glow Core Fragment",
		flavor = "Lights the crater up at night. Nobody's explained how, this far out.",
		rarity = "Epic",
		odds = 1700, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 26000,
	},
	{
		id = "ufo_fragment",
		name = "UFO Fragment",
		flavor = "Not from here. Not from anywhere else, as far as anyone can tell.",
		rarity = "Epic",
		odds = 2000, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 24000,
	},
	{
		id = "explorers_helmet",
		name = "Explorer's Helmet",
		flavor = "Worn by whoever mapped this place first. It's why there's a map at all.",
		rarity = "Legendary",
		odds = 7000, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Collector",
		sets = { "crater_relics" },
		baseValue = 140000,
	},
	{
		id = "mini_nuke",
		name = "Mini Nuke",
		flavor = "Bright yellow, comically oversized, and definitely not armed. Probably.",
		rarity = "Legendary",
		odds = 9000, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 160000,
	},
	{
		id = "stopped_second_hand",
		name = "The Second Hand",
		flavor = "A single watch hand, glowing faintly, pointing at nothing in particular.",
		rarity = "Mythic",
		odds = 60000, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Collector",
		sets = { "crater_relics" },
		baseValue = 930000,
	},
	{
		id = "unlabeled_cylinder",
		name = "Unlabeled Containment Cylinder",
		flavor = "Heavier than it looks. Nobody's brave enough to open it.",
		rarity = "Anomaly",
		odds = 500000, -- 1 in N per dig in a stocking stage
		stages = { 6 },
		appeal = "Researcher",
		sets = { "crater_relics" },
		baseValue = 6000000,
	},
} :: { ItemDef }

-- ── Indexes, built once ──────────────────────────────────────────────────

local byId: { [string]: ItemDef } = {}
local byStageRarity: { [number]: { [string]: { ItemDef } } } = {}

-- The same items as byStageRarity, flattened per stage into ONE list in a STABLE order
-- (Rarity.ORDER, then file order within a rarity). The dig roll walks this: a weighted
-- pick that walks an unstable order is a weighted pick with unstable odds -- the same
-- reason Liquids iterates an explicit ORDER list.
local stageItems: { [number]: { ItemDef } } = {}

for _, item in Items.DEFS do
	assert(byId[item.id] == nil, `duplicate item id "{item.id}"`)
	byId[item.id] = item

	for _, stageId in item.stages do
		local stage = byStageRarity[stageId]
		if stage == nil then
			stage = {}
			byStageRarity[stageId] = stage
		end
		local bucket = stage[item.rarity]
		if bucket == nil then
			bucket = {}
			stage[item.rarity] = bucket
		end
		table.insert(bucket, item)
	end
end

for stageId, buckets in byStageRarity do
	local flat: { ItemDef } = {}
	for _, rarityName in Rarity.ORDER do
		for _, item in buckets[rarityName] or {} do
			table.insert(flat, item)
		end
	end
	stageItems[stageId] = flat
end

function Items.get(id: string): ItemDef
	local item = byId[id]
	assert(item, `unknown item id "{id}"`)
	return item
end

--- Every item of one rarity that can spawn in one stage. May be empty — Stage 1 has
--- no Mythic or Anomaly entries, so callers must handle the empty case rather than
--- assuming a hit.
function Items.inStage(stageId: number, rarity: string): { ItemDef }
	local stage = byStageRarity[stageId]
	if stage == nil then
		return {}
	end
	return stage[rarity] or {}
end

function Items.hasAny(stageId: number, rarity: string): boolean
	return #Items.inStage(stageId, rarity) > 0
end

--- "1 in 100", "1 in 9000", "1 in 50k", "1 in 500k", "1 in 1.2M". Abbreviates at
--- 10k so the big Legendary/Mythic/Anomaly numbers stay short on a HUD line while
--- the four-digit Rare/Epic ones read exactly. The player-facing headline for `odds`;
--- the real in-stage rate is tilted per stage (see "The dig roll" below).
function Items.oddsText(n: number): string
	local body: string
	if n >= 1e6 then
		body = string.gsub(string.format("%.1f", n / 1e6), "%.0$", "") .. "M"
	elseif n >= 1e4 then
		body = string.gsub(string.format("%.1f", n / 1e3), "%.0$", "") .. "k"
	else
		body = string.format("%d", n)
	end
	return "1 in " .. body
end

-- ── The dig roll ────────────────────────────────────────────────────────────────
--
-- Replaces the old two-step roll (a rarity off Stages.loot, then a UNIFORM pick among
-- that stage's items of that rarity). Now every stocked item competes directly, with
-- base weight 1/odds, and the whole per-rarity `loot` weight table collapses into ONE
-- number per stage:
--
--   rarityTilt (Config/Stages) multiplies each item's weight by tilt^(rarityOrder-1).
--     Scrap (order 1) is the anchor at tilt^0 = 1; every rung above it is lifted, and a
--     bigger tilt is what makes a late stage read as "everything here is good".
--
--   detector luck (Config/Gear, per player) multiplies weights at Rare and above by
--     luck raised to a per-rarity exponent, capped at DIG_LUCK_BIAS_CAP -- the same
--     shape Config/Liquids' luckBias gives the wash pad. Below Rare it is exactly 1, so
--     the early grind is luck-proof and a tier-1 detector (luck 1.0) rolls the raw
--     tilted distribution.
--
-- Shared, like Liquids.oddsAt / Radiation / Decay: the weight a HUD could DISPLAY and
-- the weight DigService rolls come out of ONE function so they cannot disagree.

--- Luck is inert below this rarity order (Rare). "Rarer-only" -- see the header.
Items.DIG_LUCK_MIN_ORDER = Rarity.get("Rare").order
--- The most detector luck can ever multiply one item's roll weight.
Items.DIG_LUCK_BIAS_CAP = 20

--- The luck exponent for a rarity: luck^1 at Rare, luck^2 at Epic, ... clamped to
--- DIG_LUCK_BIAS_CAP. Exactly 1 (untouched) for anything below DIG_LUCK_MIN_ORDER.
function Items.luckBias(rarity: string, luck: number): number
	local order = Rarity.get(rarity).order
	if order < Items.DIG_LUCK_MIN_ORDER then
		return 1
	end
	return math.min(luck ^ (order - Items.DIG_LUCK_MIN_ORDER + 1), Items.DIG_LUCK_BIAS_CAP)
end

--- One item's roll weight in a stage: 1/odds, tilted by rarity, luck-boosted at the top.
function Items.effectiveWeight(item: ItemDef, tilt: number, luck: number): number
	local order = Rarity.get(item.rarity).order
	return (1 / item.odds) * tilt ^ (order - 1) * Items.luckBias(item.rarity, luck)
end

--- Normalised roll probability per stocked item in a stage, keyed by id. Sums to 1.
--- Empty when the stage stocks nothing. The odds this could be shown next to and the
--- odds Items.rollItem draws against come out of here together.
function Items.rollWeights(stageId: number, tilt: number, luck: number): { [string]: number }
	local pool = stageItems[stageId]
	local out: { [string]: number } = {}
	if pool == nil then
		return out
	end

	local total = 0
	for _, item in pool do
		total += Items.effectiveWeight(item, tilt, luck)
	end
	if total <= 0 then
		return out
	end
	for _, item in pool do
		out[item.id] = Items.effectiveWeight(item, tilt, luck) / total
	end
	return out
end

--- Weighted pick of one item id from a stage's pool. Walks `stageItems` in its stable
--- order so the roll is reproducible. Returns nil ONLY when the stage stocks nothing at
--- all -- callers treat that as a content gap (no signals spawn), not a crash.
function Items.rollItem(stageId: number, tilt: number, luck: number): string?
	local pool = stageItems[stageId]
	if pool == nil or #pool == 0 then
		return nil
	end

	local total = 0
	for _, item in pool do
		total += Items.effectiveWeight(item, tilt, luck)
	end

	local pick = math.random() * total
	for _, item in pool do
		pick -= Items.effectiveWeight(item, tilt, luck)
		if pick <= 0 then
			return item.id
		end
	end
	return pool[#pool].id
end

--- The stage's rarity distribution at baseline luck (1.0), keyed by rarity name, summing
--- to 1. DigService picks a burial-depth band from this; Util/Spec pins its Rare+ share.
function Items.rarityWeights(stageId: number, tilt: number): { [string]: number }
	local out: { [string]: number } = {}
	for id, p in Items.rollWeights(stageId, tilt, 1) do
		local r = byId[id].rarity
		out[r] = (out[r] or 0) + p
	end
	return out
end

return Items
