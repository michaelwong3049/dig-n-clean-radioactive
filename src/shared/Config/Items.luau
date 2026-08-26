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
	a tragedy" — same six stages, same rarity ladder, same six items with real 3D
	models untouched (bottle_cap, steel_rod, tin_can, house_key, stopped_watch).

	A STAGE WITH NO ITEMS IS NOT A CRASH ANY MORE, BUT IT IS STILL BROKEN. DigService
	rolls a rarity from the stage's loot table and then steps DOWN through the
	catalogue looking for something to hand you. That step-down only goes downward —
	so a stage stocked only at Rare and above silently fails every Scrap and Common
	roll and fills its field at a fraction of the intended rate. Stock the LOW end of
	every stage you add, not just the exciting end.

	STAGES 3-6 NO LONGER STOCK SCRAP, ON REQUEST. Their old Scrap-tier items folded
	up into Common (and Stage 5/6 also promoted one former Common slot to Uncommon),
	so the loot FLOOR for those four stages is now Common rather than Scrap. See
	Config/Stages.luau's own loot-odds tables — their Scrap weight was folded into
	Common to match, so a Scrap roll there doesn't produce a dead roll.

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

	`model` is optional while the catalogue art is produced. Entries without one keep
	the rarity-coloured placeholder; entries with one resolve through Shared.ItemModels.
]]

export type ItemDef = {
	id: string,
	name: string,
	flavor: string,
	rarity: string,
	stages: { number },
	appeal: string, -- "Researcher" | "Collector" | "Gearhead"
	sets: { string },
	baseValue: number,
	model: string?,
}

local Items = {}

Items.DEFS = {
	-- ── Scrap ── $1-5 ──────────────────────────────────────────────────────
	{
		id = "bottle_cap",
		name = "Bottle Cap",
		flavor = "Bent double. The logo is still readable if you squint.",
		rarity = "Scrap",
		stages = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 3,
		model = "BottleCap",
	},
	{
		id = "steel_rod",
		name = "Steel Rod",
		flavor = "Snapped clean through. Something very large came this way.",
		rarity = "Scrap",
		stages = { 1 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 4,
		model = "SteelRod",
	},
	{
		id = "glass_pebble",
		name = "Glass Pebble",
		flavor = "Sand that got so hot it melted into a smooth little marble.",
		rarity = "Scrap",
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 5,
	},

	-- ── Common ── $5-25 ─────────────────────────────────────────────────
	{
		id = "tin_can",
		name = "Dented Tin Can",
		flavor = "Peaches. The label survived better than the peaches did.",
		rarity = "Common",
		stages = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 12,
		model = "DentedTinCan",
	},
	{
		id = "house_key",
		name = "House Key",
		flavor = "Still on its ring, with two smaller ones beside it.",
		rarity = "Common",
		stages = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 18,
		model = "HouseKey",
	},
	{
		id = "stopped_watch",
		name = "Stopped Wristwatch",
		flavor = "Stopped at 8:14. So did everyone else's.",
		rarity = "Common",
		stages = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 22,
		model = "Wristwatch",
	},
	{
		id = "radioactive_rubber_duck",
		name = "Radioactive Rubber Duck",
		flavor = "It glows in the dark. It always did, actually.",
		rarity = "Common",
		stages = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 14,
	},

	-- ── Uncommon ── $25-120 ─────────────────────────────────────────────
	-- NOTE: Uncommon is hardness 2 and a Wire Brush is potency 1, so the first of
	-- these a new player digs CANNOT be cleaned yet. That is the §6 staggered reveal
	-- working — but it also contradicts PLAN §12, whose scripted tutorial has you
	-- clean and sell a rigged Uncommon 90 seconds in. Flagged, not silently patched.
	{
		id = "tin_soldier",
		name = "Tin Soldier",
		flavor = "A tiny toy soldier, paint chipped, forever standing guard.",
		rarity = "Uncommon",
		stages = { 1 },
		appeal = "Collector",
		sets = { "childrens_toys" },
		baseValue = 45,
	},
	{
		id = "wind_up_flashlight",
		name = "Wind-Up Flashlight",
		flavor = "Give the crank a few turns and it still lights up, just for a second.",
		rarity = "Uncommon",
		stages = { 1 },
		appeal = "Gearhead",
		sets = { "salvage_kit" },
		baseValue = 60,
	},
	{
		id = "gold_ring",
		name = "Gold Ring",
		flavor = "A plain gold ring, still shining under all the dust.",
		rarity = "Uncommon",
		stages = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 85,
	},

	-- ── Rare ── $120-700 ───────────────────────────────────────────────
	{
		id = "radiation_scanner",
		name = "Radiation Scanner",
		flavor = "Clicks faster the closer you get to something glowing.",
		rarity = "Rare",
		stages = { 1 },
		appeal = "Gearhead",
		sets = { "salvage_kit" },
		baseValue = 340,
	},
	{
		id = "film_canister",
		name = "Sealed Film Canister",
		flavor = "Thirty-six photos, never developed. Who knows what's on them.",
		rarity = "Rare",
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 480,
	},

	-- ── Epic ── $700-4k ─────────────────────────────────────────────────
	{
		id = "sample_case",
		name = "Sample Case",
		flavor = "Six glass vials. One of them glows all on its own.",
		rarity = "Epic",
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 1900,
	},

	-- ── Legendary ── $4k-30k ────────────────────────────────────────────
	-- 0.15% in Stage 1. Almost nobody will see this. That is the point.
	{
		id = "treasure_map",
		name = "Old Treasure Map",
		flavor = "A hand-drawn map, half burnt. Something's marked with three stars and no name.",
		rarity = "Legendary",
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 9500,
	},

	-- ══ STAGE 2 — THE SUBURBS ═══════════════════════════════════════════════
	-- Collapsed houses and half-buried cars (PLAN §4). The theme is a life
	-- interrupted mid-sentence, so the flavor leans domestic rather than martial.

	{
		id = "cracked_tile",
		name = "Cracked Tile",
		flavor = "Someone chose this pattern once.",
		rarity = "Scrap",
		stages = { 2 },
		appeal = "Collector",
		sets = { "suburban_kitchen" },
		baseValue = 3,
	},
	{
		id = "door_hinge",
		name = "Door Hinge",
		flavor = "Still swings, even with no door left to hold.",
		rarity = "Scrap",
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 4,
	},
	{
		id = "cutlery_set",
		name = "Cutlery Set",
		flavor = "Wrapped in a napkin, waiting for a dinner that never happened.",
		rarity = "Common",
		stages = { 2 },
		appeal = "Collector",
		sets = { "suburban_kitchen" },
		baseValue = 14,
	},
	{
		id = "garden_trowel",
		name = "Garden Trowel",
		flavor = "Left in the soil, handle up, like it would be picked up tomorrow.",
		rarity = "Common",
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 19,
	},
	{
		id = "doll_head",
		name = "Porcelain Doll Head",
		flavor = "The eyes still blink open and shut. A little spooky, a little funny.",
		rarity = "Common",
		stages = { 2 },
		appeal = "Collector",
		sets = { "childrens_toys" },
		baseValue = 23,
	},
	{
		id = "charm_bracelet",
		name = "Charm Bracelet",
		flavor = "Eleven tiny charms — a bicycle, a cat, a little house.",
		rarity = "Uncommon",
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 55,
	},
	{
		id = "socket_set",
		name = "Socket Wrench Set",
		flavor = "Every socket still in its slot. Whoever owned this was particular about it.",
		rarity = "Uncommon",
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 72,
	},
	{
		id = "photo_locket",
		name = "Photo Locket",
		flavor = "Two tiny photos, one hinge. The catch still works.",
		rarity = "Uncommon",
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 98,
	},
	{
		id = "mutant_carrot",
		name = "Mutant Carrot",
		flavor = "Three feet long and still bright orange. The rabbits are thrilled.",
		rarity = "Uncommon",
		stages = { 2 },
		appeal = "Researcher",
		sets = {},
		baseValue = 50,
	},
	{
		id = "pearl_necklace",
		name = "Pearl Necklace",
		flavor = "Kept for good occasions — there was one more pearl, somewhere.",
		rarity = "Rare",
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 310,
	},
	{
		id = "ignition_coil",
		name = "Ignition Coil",
		flavor = "Pulled from a car pointed away from town, tank full, doors open.",
		rarity = "Rare",
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 450,
	},
	{
		id = "clock_movement",
		name = "Grandfather Clock Movement",
		flavor = "Brass gears, hand-cut, unbothered. It would still run today.",
		rarity = "Epic",
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 1650,
	},
	{
		id = "deposit_box",
		name = "Safe Deposit Box",
		flavor = "Whatever was worth a bank vault is still inside, and it's yours now.",
		rarity = "Legendary",
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 8200,
	},

	-- ══ STAGE 3 — FALLOUT FIELDS ════════════════════════════════════════════
	-- Old farmland scorched by the fallout, not a battlefield — reworked on
	-- request to drop the military angle (dog tags, ordnance, cipher cases)
	-- in favor of what you'd actually expect buried under an abandoned
	-- homestead: buried coins, gold, farm tools, everyday relics. NO SCRAP
	-- TIER (see this file's header) — its old Scrap items folded into Common.
	-- Several of these are also tagged for Stage 4: the Exclusion Belt is the
	-- same stretch of country, further in, and a dive needs a stocked
	-- catalogue at EVERY rarity or rollItemId's step-down finds nothing.

	{
		id = "rusty_horseshoe",
		name = "Rusty Horseshoe",
		flavor = "A rusted horseshoe. There was a barn out here once.",
		rarity = "Common",
		stages = { 3, 4 },
		appeal = "Gearhead",
		sets = { "abandoned_farm" },
		baseValue = 8,
	},
	{
		id = "gate_latch",
		name = "Bent Gate Latch",
		flavor = "Snapped clean off. The fence went with it.",
		rarity = "Common",
		stages = { 3, 4 },
		appeal = "Gearhead",
		sets = { "abandoned_farm" },
		baseValue = 11,
	},
	{
		id = "old_food_tin",
		name = "Old Food Tin",
		flavor = "Unopened. The label wore off long ago.",
		rarity = "Common",
		stages = { 3, 4 },
		appeal = "Collector",
		sets = {},
		baseValue = 16,
	},
	{
		id = "first_aid_tin",
		name = "First-Aid Tin",
		flavor = "A little dented, but everything inside is still sealed.",
		rarity = "Uncommon",
		stages = { 3, 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 45,
	},
	{
		id = "unlit_signal_flare",
		name = "Unlit Signal Flare",
		flavor = "Never got its chance to light up the sky.",
		rarity = "Uncommon",
		stages = { 3 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 75,
	},
	{
		id = "old_compass",
		name = "Old Compass",
		flavor = "Still points somewhere — just not always north anymore.",
		rarity = "Uncommon",
		stages = { 3 },
		appeal = "Researcher",
		sets = {},
		baseValue = 65,
	},
	{
		id = "broken_lantern",
		name = "Broken Lantern",
		flavor = "No oil left, but it still swings a little in the wind.",
		rarity = "Uncommon",
		stages = { 3, 4 },
		appeal = "Gearhead",
		sets = { "abandoned_farm" },
		baseValue = 95,
	},
	{
		id = "gold_signet",
		name = "Gold Signet Ring",
		flavor = "Gold doesn't care about any of this. That's why it's worth something.",
		rarity = "Rare",
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 380,
	},
	{
		id = "radiation_badge",
		name = "Radiation Badge",
		flavor = "Changes color the longer it sits out here. It's been out here a while.",
		rarity = "Rare",
		stages = { 3, 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 640,
	},
	{
		id = "buried_coin_jar",
		name = "Buried Coin Jar",
		flavor = "A glass jar, still packed with old coins. Somebody was saving up.",
		rarity = "Rare",
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 560,
	},
	{
		id = "bullion_bar",
		name = "Gold Bullion Bar",
		flavor = "Someone carried this out of a vault, into a field, and got no further.",
		rarity = "Epic",
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 2400,
	},
	{
		id = "diamond_brooch",
		name = "Diamond Brooch",
		flavor = "A stone that catches light no one else out here can see.",
		rarity = "Epic",
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 2800,
	},
	{
		id = "rusted_farm_safe",
		name = "Rusted Farm Safe",
		flavor = "Buried under the old farmhouse. Whatever's inside has been waiting a long time.",
		rarity = "Legendary",
		stages = { 3, 4 },
		appeal = "Collector",
		sets = {},
		baseValue = 9000,
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
		stages = { 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 660,
	},
	{
		id = "strange_metal_chip",
		name = "Strange Metal Chip",
		flavor = "Covered in markings nobody recognizes. Hums faintly if you hold it.",
		rarity = "Epic",
		stages = { 4 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 3400,
	},
	{
		id = "reactor_rod",
		name = "The Reactor Rod",
		flavor = "The rod that kept the reactor calm. It's the whole reason there's a Belt and not something worse.",
		rarity = "Legendary",
		stages = { 4 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 18000,
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
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 9,
	},
	{
		id = "shiny_metal_blade",
		name = "Shiny Metal Blade",
		flavor = "Curved like it was cutting something, once.",
		rarity = "Common",
		stages = { 5 },
		appeal = "Researcher",
		sets = {},
		baseValue = 10,
	},
	{
		id = "rad_warning_placard",
		name = "Radiation Warning Placard",
		flavor = "The symbol's still bright. Everything around it isn't.",
		rarity = "Common",
		stages = { 5 },
		appeal = "Collector",
		sets = {},
		baseValue = 15,
	},
	{
		id = "pressure_gauge",
		name = "Pressure Gauge",
		flavor = "Needle buried past the red.",
		rarity = "Uncommon",
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 60,
	},
	{
		id = "old_headphones",
		name = "Old Headphones",
		flavor = "Big and cushioned. Only one side still crackles with static.",
		rarity = "Uncommon",
		stages = { 5 },
		appeal = "Gearhead",
		sets = { "reactor_control" },
		baseValue = 65,
	},
	{
		id = "cooling_valve_wheel",
		name = "Cooling Valve Wheel",
		flavor = "A big metal wheel that used to turn off the water. It won't budge now.",
		rarity = "Uncommon",
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 90,
	},
	{
		id = "reactor_logbook",
		name = "Reactor Logbook",
		flavor = "The last page has one word on it, underlined twice.",
		rarity = "Rare",
		stages = { 5 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 420,
	},
	{
		id = "sealed_data_drive",
		name = "Sealed Data Drive",
		flavor = "Locked in a lead case. Someone wanted this kept safe.",
		rarity = "Rare",
		stages = { 5 },
		appeal = "Researcher",
		sets = {},
		baseValue = 580,
	},
	{
		id = "blackbox_recorder",
		name = "Black-Box Recorder",
		flavor = "Built to survive anything. Lots of practice at it.",
		rarity = "Epic",
		stages = { 5 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 2600,
	},
	{
		id = "sealed_fuel_casing",
		name = "Sealed Fuel Rod Casing",
		flavor = "Empty now, but it used to hold something that glowed.",
		rarity = "Epic",
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 3200,
	},
	{
		id = "reactor_core_sample",
		name = "Reactor Core Sample",
		flavor = "Warm through three layers of metal. Never once cooled down.",
		rarity = "Legendary",
		stages = { 5 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 15000,
	},
	{
		id = "live_fuel_rod",
		name = "Live Fuel Rod",
		flavor = "Still glowing. Still humming. Exactly as dangerous as the day it was made.",
		rarity = "Mythic",
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 90000,
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
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 7,
	},
	{
		id = "scorched_metal_plate",
		name = "Scorched Metal Plate",
		flavor = "Rated to hold back anything. Didn't.",
		rarity = "Common",
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 18,
	},
	{
		id = "sealed_air_filter",
		name = "Sealed Air Filter",
		flavor = "Still wrapped. Nobody who needed it got the chance to open it.",
		rarity = "Uncommon",
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 70,
	},
	{
		id = "bent_door_wheel",
		name = "Bent Door Wheel",
		flavor = "Spun the wrong way, hard.",
		rarity = "Uncommon",
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 105,
	},
	{
		id = "cracked_glow_badge",
		name = "Cracked Glow Badge",
		flavor = "Went dark in under a second.",
		rarity = "Rare",
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 460,
	},
	{
		id = "fused_tool_roll",
		name = "Fused Tool Roll",
		flavor = "Every tool welded to the canvas, and to each other.",
		rarity = "Rare",
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 640,
	},
	{
		id = "untouched_ground_sample",
		name = "Untouched Ground Sample",
		flavor = "One square foot of ordinary dirt, sealed in glass, found at the center of everything.",
		rarity = "Epic",
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 3300,
	},
	{
		id = "skyglow_core_fragment",
		name = "Sky-Glow Core Fragment",
		flavor = "Lights the crater up at night. Nobody's explained how, this far out.",
		rarity = "Epic",
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 3900,
	},
	{
		id = "ufo_fragment",
		name = "UFO Fragment",
		flavor = "Not from here. Not from anywhere else, as far as anyone can tell.",
		rarity = "Epic",
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 3600,
	},
	{
		id = "explorers_helmet",
		name = "Explorer's Helmet",
		flavor = "Worn by whoever mapped this place first. It's why there's a map at all.",
		rarity = "Legendary",
		stages = { 6 },
		appeal = "Collector",
		sets = { "crater_relics" },
		baseValue = 21000,
	},
	{
		id = "mini_nuke",
		name = "Mini Nuke",
		flavor = "Bright yellow, comically oversized, and definitely not armed. Probably.",
		rarity = "Legendary",
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 24000,
	},
	{
		id = "stopped_second_hand",
		name = "The Second Hand",
		flavor = "A single watch hand, glowing faintly, pointing at nothing in particular.",
		rarity = "Mythic",
		stages = { 6 },
		appeal = "Collector",
		sets = { "crater_relics" },
		baseValue = 140000,
	},
	{
		id = "unlabeled_cylinder",
		name = "Unlabeled Containment Cylinder",
		flavor = "Heavier than it looks. Nobody's brave enough to open it.",
		rarity = "Anomaly",
		stages = { 6 },
		appeal = "Researcher",
		sets = { "crater_relics" },
		baseValue = 900000,
	},
} :: { ItemDef }

-- ── Indexes, built once ──────────────────────────────────────────────────

local byId: { [string]: ItemDef } = {}
local byStageRarity: { [number]: { [string]: { ItemDef } } } = {}

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

function Items.get(id: string): ItemDef
	local item = byId[id]
	assert(item, `unknown item id "{id}"`)
	return item
end

--- Every item of one rarity that can spawn in one stage. May be empty — Stage 1 has
--- no Mythic or Anomaly entries, and the loot table can still roll them, so callers
--- must handle the empty case rather than assuming a hit.
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

return Items
