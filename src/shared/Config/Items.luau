--!strict
--[[
	Items.lua — the catalogue. Data only, like everything else in Config/.

	Stages 1-6, ~68 items, Common through Anomaly.

	NO ITEM IS AT SCRAP ANY MORE, ON REQUEST. Every former Scrap item was folded
	into Common (across all stages now, not just 3-6). The Scrap tier still exists in
	Config/Rarity (order 1) as the rarityTilt anchor -- it is simply unstocked.

	EVERY ITEM IS A NUKE NOW, ON REQUEST (feat/nuke-arsenal-retheme). `name`/`flavor`
	follow one idea -- short "[Adjective] Nuke" pairs, not invented lore per item, with
	only a couple of top-tier finds ("Atomic Bomb", "The Big One") earning a standout
	unique name. `id`, `rarity`, `odds`, `weight`, and `baseValue` were left untouched
	by the retheme: those numbers are what the dig roll, hardness gates, and economy
	actually run on, and `id` in particular is what player saves reference
	(DataService's `carry`/`locker`/`exhibit.pedestals`/`discovered`), so renaming it
	would break Items.get() for any saved profile still holding the old id.

	MODEL IS NOW EITHER REAL ART OR NOTHING (feat/imported-nuke-gameplay). The
	procedural 7-tier capsule system (NukeCommon..NukeAnomaly, NukeBase.luau,
	NukeSignatures.luau) is retired -- `model` is `"ImportedNuke"` for the handful of
	items with hand-imported mesh art (Shared.Config.ImportedNukeMeshes resolves which
	mesh by `id`) and `nil` for everything else, which falls back to the plain rarity-
	coloured placeholder cube everywhere (WashService/ToolService/ExhibitService each
	already handle `ItemModels.create() == nil`). Catalogue art keeps arriving item by
	item; an unmodelled item is not a bug.

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

	EVERY ITEM HAS A `weight`, IN KILOGRAMS (feat/item-weight-system). It is INTRINSIC
	and ORTHOGONAL to rarity. Config/Weight.luau turns it into five felt consequences: the
	hauled model's size, the aura's crack reach, how long the mash takes, a value/$/sec
	multiplier, and a dig-roll bias (`rollBias`, <= 1) that leaves the feather end a
	touch rarer and buries the heavy end deep. The "1 in N" a sharp ping or the Index
	prints is `Items.shownOdds` = `odds / rollBias`, so the display carries the weight
	penalty too. AUTHORING RULE: keep `weight` inside Weight.MIN..Weight.MAX
	(5..500; Small 5-15, Normal 16-50, Large 51-250, XL 250+), and roughly correlate the heavy end with rarity -- a genuinely heavy
	thing (a buried safe) should also be Rare or better, so the physical slog and the
	scarcity land together.

	baseValue must sit inside its rarity's band in Rarity.DEFS. Stage 1 deliberately
	carries a Legendary: that chance is what keeps a new player sweeping. Config/Weight's
	`valueMult` rides ON TOP of that authored number (like Rarity.MODIFIERS' valueMult
	already does), so the band rule is about the AUTHORED baseValue only.

	ECONOMY RESCALE (feat/economy-rescale-display-income): every baseValue below was
	multiplied by 20/3 (~6.667x) and rounded to two significant figures, anchored so the
	Dud Nuke (Common, Stage 1) sells for $20. The rarity bands in Rarity.DEFS moved by
	the same factor, so every entry still sits inside its band. See Config/Rarity.luau's
	header for the whole picture.

	`appeal` (Researcher/Collector/Gearhead) and `sets` are untouched by the retheme --
	they were already inert, display-only/unconsumed fields and stayed that way.

	RETIRED ITEMS KEEP THEIR DEFS ENTRY, WITH `stages = {}`. An id is forever, once
	shipped -- see the `id` note above on why renaming breaks old saves; deleting the
	whole entry is the same problem, since `Items.get()` asserts on an unknown id and
	a saved profile's carry/locker/exhibit/discovered can still name it. `stages = {}`
	unstocks it everywhere (it never joins byStageRarity/stageItems, so the dig roll
	can't produce it again) while leaving `byId` able to resolve it. IndexController's
	`totalItems` only counts items with at least one stage, so a retired item doesn't
	sit in the denominator as permanently unreachable.
]]

local Rarity = require(script.Parent.Rarity)
local Weight = require(script.Parent.Weight)

export type ItemDef = {
	id: string,
	name: string,
	flavor: string,
	rarity: string,
	-- Authored "1 in N" find-rarity. It DRIVES THE ROLL now (it used to be display
	-- only): an item's base weight in a stage is 1/odds, so a "1 in 100" item turns up
	-- a tenth as often as a "1 in 10" one. THREE knobs bend that base -- Config/Stages'
	-- per-stage `rarityTilt`, the digging player's detector luck at Rare and above, and
	-- the item's own `weight` (Config/Weight.rollBias, <= 1) -- see "The dig roll" at
	-- the foot of this file. It is still the collectible headline shown in the Index and
	-- on a sharp detector ping, hand-set per item so it can be round and readable; the
	-- number a player SEES is Items.shownOdds (odds inflated by the weight penalty), not
	-- the literal in-stage rate. One value covers every stage an item is stocked in (the
	-- handful that span Stage 3<->4 share it on purpose).
	odds: number,
	weight: number, -- kilograms; Config/Weight turns it into size/glow/pull/value/roll
	-- Optional VISUAL-ONLY nudge on the hauled size, multiplied onto Weight.sizeScale
	-- (default 1). Exists because `weight` also drives pull time, value, dig odds and
	-- aura, and sits at the very floor / ceiling of Weight's curve for the lightest and
	-- heaviest items, so it cannot resize those without moving balance. Only the haul
	-- reads it; wash / held / locker / pedestal displays normalise to fixed sizes.
	sizeMult: number?,
	stages: { number },
	appeal: string, -- "Researcher" | "Collector" | "Gearhead"
	sets: { string },
	baseValue: number,
	model: string?,
}

local Items = {}

Items.DEFS = {
	-- ── Common (former Scrap tier, folded in on request) ────────────────────
	{
		id = "bottle_cap",
		name = "Dud Nuke",
		flavor = "Tiny, dented, and never going off.",
		rarity = "Common",
		odds = 5, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 20,
		model = "ImportedNuke",
	},
	{
		id = "steel_rod",
		name = "Rusty Nuke",
		flavor = "Rusted solid. The fins fell off years ago.",
		rarity = "Common",
		odds = 6, -- 1 in N per dig in a stocking stage
		weight = 70,
		stages = { 1 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 27,
		model = "ImportedNuke",
	},
	{
		id = "glass_pebble",
		name = "Marble Nuke",
		flavor = "Melted down and rolled smooth.",
		rarity = "Common",
		odds = 8, -- 1 in N per dig in a stocking stage
		weight = 5,
		sizeMult = 0.8, -- smaller
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 33,
		model = "ImportedNuke",
	},

	-- ── Common ── $35-170 ─────────────────────────────────────────────────
	{
		id = "tin_can",
		name = "Dented Nuke",
		flavor = "Dented like it rolled down a hill.",
		rarity = "Common",
		odds = 9, -- 1 in N per dig in a stocking stage
		weight = 15,
		sizeMult = 0.8, -- smaller
		stages = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 80,
		model = "ImportedNuke",
	},
	{
		id = "house_key",
		name = "Keychain Nuke",
		flavor = "Small enough to carry on a keyring.",
		rarity = "Common",
		odds = 12, -- 1 in N per dig in a stocking stage
		weight = 6,
		sizeMult = 1.2, -- bigger
		stages = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 120,
		model = "ImportedNuke",
	},
	{
		id = "stopped_watch",
		name = "Stopped Nuke",
		flavor = "The countdown clock froze at 8:14.",
		rarity = "Common",
		odds = 15, -- 1 in N per dig in a stocking stage
		weight = 7,
		stages = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 150,
		model = "ImportedNuke",
	},
	{
		-- RETIRED, ON REQUEST (see "RETIRED ITEMS" note up top) -- dropped from the
		-- dig roll and the Index total, but the entry itself stays so old saves
		-- holding this id don't crash Items.get().
		id = "radioactive_rubber_duck",
		name = "Rubber Nuke",
		flavor = "Squeaks. Glows a little. Definitely not real.",
		rarity = "Common",
		odds = 40, -- 1 in N per dig in a stocking stage
		weight = 6,
		stages = {},
		appeal = "Collector",
		sets = {},
		baseValue = 93,
		model = nil,
	},

	-- ── Uncommon ── $170-800 ─────────────────────────────────────────────
	-- NOTE: Uncommon is hardness 2 and a Wire Brush is potency 1, so the first of
	-- these a new player digs CANNOT be cleaned yet. That is the §6 staggered reveal
	-- working — but it also contradicts PLAN §12, whose scripted tutorial has you
	-- clean and sell a rigged Uncommon 90 seconds in. Flagged, not silently patched.
	{
		id = "tin_soldier",
		name = "Tin Nuke",
		flavor = "Stands at attention. Paint chipped, never armed.",
		rarity = "Uncommon",
		odds = 45, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 1 },
		appeal = "Collector",
		sets = { "childrens_toys" },
		baseValue = 300,
		model = "ImportedNuke",
	},
	{
		id = "wind_up_flashlight",
		name = "Wind-Up Nuke",
		flavor = "Give it a crank and the lights blink on.",
		rarity = "Uncommon",
		odds = 60, -- 1 in N per dig in a stocking stage
		weight = 14,
		stages = { 1 },
		appeal = "Gearhead",
		sets = { "salvage_kit" },
		baseValue = 400,
		model = "ImportedNuke",
	},
	{
		id = "gold_ring",
		name = "Golden Nuke",
		flavor = "Gold-plated. Somebody really wanted this one to shine.",
		rarity = "Uncommon",
		odds = 90, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 570,
		model = "ImportedNuke",
	},

	-- ── Rare ── $800-4.7k ───────────────────────────────────────────────
	{
		id = "radiation_scanner",
		name = "Clicking Nuke",
		flavor = "Clicks faster the closer you carry it.",
		rarity = "Rare",
		odds = 200, -- 1 in N per dig in a stocking stage
		weight = 28,
		stages = { 1 },
		appeal = "Gearhead",
		sets = { "salvage_kit" },
		baseValue = 2300,
		model = "ImportedNuke",
	},
	{
		id = "film_canister",
		name = "Exposed Nuke",
		flavor = "Thirty-six photos in here. Nobody's developed them.",
		rarity = "Rare",
		odds = 260, -- 1 in N per dig in a stocking stage
		weight = 6,
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 3200,
		model = "ImportedNuke",
	},

	-- ── Epic ── $4.7k-27k ─────────────────────────────────────────────────
	{
		id = "sample_case",
		name = "Strapped Nuke",
		flavor = "Six glass vials strapped on. One glows on its own.",
		rarity = "Epic",
		odds = 1200, -- 1 in N per dig in a stocking stage
		weight = 50,
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 13000,
		model = "ImportedNuke",
	},

	-- ── Legendary ── $27k-200k ────────────────────────────────────────────
	-- 0.15% in Stage 1. Almost nobody will see this. That is the point.
	{
		id = "treasure_map",
		name = "Blueprint Nuke",
		flavor = "Half-burnt plans marked with three stars and no name.",
		rarity = "Legendary",
		odds = 2500, -- 1 in N per dig in a stocking stage
		weight = 6,
		stages = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 63000,
		model = "ImportedNuke",
	},

	-- ══ STAGE 2 — THE SUBURBS ═══════════════════════════════════════════════

	{
		id = "cracked_tile",
		name = "Cracked Nuke",
		flavor = "Split clean down the middle. Harmless now.",
		rarity = "Common",
		odds = 5, -- 1 in N per dig in a stocking stage
		weight = 25,
		stages = { 2 },
		appeal = "Collector",
		sets = { "suburban_kitchen" },
		baseValue = 20,
		model = "ImportedNuke",
	},
	{
		id = "door_hinge",
		name = "Creaky Nuke",
		flavor = "The casing still swings open with a creak.",
		rarity = "Common",
		odds = 7, -- 1 in N per dig in a stocking stage
		weight = 17,
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 27,
		model = "ImportedNuke",
	},
	{
		id = "cutlery_set",
		name = "Tarnished Nuke",
		flavor = "Dull metal, dinner-table sized.",
		rarity = "Common",
		odds = 10, -- 1 in N per dig in a stocking stage
		weight = 22,
		stages = { 2 },
		appeal = "Collector",
		sets = { "suburban_kitchen" },
		baseValue = 93,
		model = "ImportedNuke",
	},
	{
		id = "garden_trowel",
		name = "Abandoned Nuke",
		flavor = "Someone started digging this up and gave up.",
		rarity = "Common",
		odds = 13, -- 1 in N per dig in a stocking stage
		weight = 15,
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 130,
		model = "ImportedNuke",
	},
	{
		id = "doll_head",
		name = "Toy Nuke",
		flavor = "A kid's replica, paint chipped, still cute.",
		rarity = "Common",
		odds = 25, -- 1 in N per dig in a stocking stage
		weight = 13,
		stages = { 2 },
		appeal = "Collector",
		sets = { "childrens_toys" },
		baseValue = 150,
		model = "ImportedNuke",
	},
	{
		id = "charm_bracelet",
		name = "Trinket Nuke",
		flavor = "Eleven tiny charms dangling off a live-looking casing.",
		rarity = "Uncommon",
		odds = 45, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 370,
		model = "ImportedNuke",
	},
	{
		id = "socket_set",
		name = "Socketed Nuke",
		flavor = "Every socket still in its slot, oddly tidy.",
		rarity = "Uncommon",
		odds = 55, -- 1 in N per dig in a stocking stage
		weight = 40,
		sizeMult = 0.8, -- smaller
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 480,
		model = "ImportedNuke",
	},
	{
		id = "photo_locket",
		name = "Keepsake Nuke",
		flavor = "Opens up to two tiny photographs.",
		rarity = "Uncommon",
		odds = 70, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 650,
		model = "ImportedNuke",
	},
	{
		id = "mutant_carrot",
		name = "Mutant Nuke",
		flavor = "Grew a weird orange bulge. The rabbits love it.",
		rarity = "Uncommon",
		odds = 120, -- 1 in N per dig in a stocking stage
		weight = 55,
		stages = { 2 },
		appeal = "Researcher",
		sets = {},
		baseValue = 330,
		model = "ImportedNuke",
	},
	{
		id = "pearl_necklace",
		name = "Pearl Nuke",
		flavor = "Strung with pearls, saved for good occasions.",
		rarity = "Rare",
		odds = 240, -- 1 in N per dig in a stocking stage
		weight = 6,
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 2100,
		model = "ImportedNuke",
	},
	{
		id = "ignition_coil",
		name = "Ignition Nuke",
		flavor = "Pulled from a car pointed away from town, tank full, doors open.",
		rarity = "Rare",
		odds = 200, -- 1 in N per dig in a stocking stage
		weight = 30,
		stages = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 3000,
		model = "ImportedNuke",
	},
	{
		id = "clock_movement",
		name = "Clockwork Nuke",
		flavor = "Brass gears ticking away inside, unbothered.",
		rarity = "Epic",
		odds = 1500, -- 1 in N per dig in a stocking stage
		weight = 95,
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 11000,
		model = "ImportedNuke",
	},
	{
		id = "deposit_box",
		name = "Vault Nuke",
		flavor = "Whatever was worth a bank vault is still attached.",
		rarity = "Legendary",
		odds = 3000, -- 1 in N per dig in a stocking stage
		weight = 420,
		stages = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 55000,
		model = "ImportedNuke",
	},

	-- ══ STAGE 3 — FALLOUT FIELDS ════════════════════════════════════════════
	-- NO SCRAP TIER (see this file's header) -- its old Scrap items folded into
	-- Common. Several of these are also tagged for Stage 4: the Exclusion Belt is
	-- the same stretch of country, further in, and a dive still wants a stocked low
	-- end so the roll is not all Legendaries.

	{
		id = "rusty_horseshoe",
		name = "Lucky Nuke",
		flavor = "Shaped like luck. Never actually worked.",
		rarity = "Common",
		odds = 8, -- 1 in N per dig in a stocking stage
		weight = 19,
		stages = { 3, 4 },
		appeal = "Gearhead",
		sets = { "abandoned_farm" },
		baseValue = 53,
		model = "ImportedNuke",
	},
	{
		id = "gate_latch",
		name = "Split Nuke",
		flavor = "Torn clean off whatever it used to arm.",
		rarity = "Common",
		odds = 10, -- 1 in N per dig in a stocking stage
		weight = 22,
		stages = { 3, 4 },
		appeal = "Gearhead",
		sets = { "abandoned_farm" },
		baseValue = 73,
		model = "ImportedNuke",
	},
	{
		id = "old_food_tin",
		name = "Canned Nuke",
		flavor = "Sealed up tight like it's still fresh.",
		rarity = "Common",
		odds = 14, -- 1 in N per dig in a stocking stage
		weight = 17,
		sizeMult = 0.8, -- smaller
		stages = { 3, 4 },
		appeal = "Collector",
		sets = {},
		baseValue = 110,
		model = "ImportedNuke",
	},
	{
		id = "first_aid_tin",
		name = "Airtight Nuke",
		flavor = "A little dented, but still sealed tight.",
		rarity = "Uncommon",
		odds = 40, -- 1 in N per dig in a stocking stage
		weight = 28,
		stages = { 3, 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 300,
		model = "ImportedNuke",
	},
	{
		id = "unlit_signal_flare",
		name = "Flare Nuke",
		flavor = "Never got its chance to light up the sky.",
		rarity = "Uncommon",
		odds = 55, -- 1 in N per dig in a stocking stage
		weight = 13,
		stages = { 3 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 500,
		model = "ImportedNuke",
	},
	{
		id = "old_compass",
		name = "Guided Nuke",
		flavor = "Still points somewhere. Just not always north.",
		rarity = "Uncommon",
		odds = 60, -- 1 in N per dig in a stocking stage
		weight = 9,
		sizeMult = 1.2, -- bigger
		stages = { 3 },
		appeal = "Researcher",
		sets = {},
		baseValue = 430,
		model = "ImportedNuke",
	},
	{
		id = "broken_lantern",
		name = "Glowless Nuke",
		flavor = "Used to glow. Ran out of whatever that was.",
		rarity = "Uncommon",
		odds = 50, -- 1 in N per dig in a stocking stage
		weight = 35,
		stages = { 3, 4 },
		appeal = "Gearhead",
		sets = { "abandoned_farm" },
		baseValue = 630,
		model = "ImportedNuke",
	},
	{
		id = "gold_signet",
		name = "Gilded Nuke",
		flavor = "Gold doesn't care what it's welded to.",
		rarity = "Rare",
		odds = 300, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 2500,
		model = "ImportedNuke",
	},
	{
		id = "radiation_badge",
		name = "Telltale Nuke",
		flavor = "Changes color the longer it sits out here.",
		rarity = "Rare",
		odds = 220, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 3, 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 4300,
		model = "ImportedNuke",
	},
	{
		id = "buried_coin_jar",
		name = "Bottled Nuke",
		flavor = "Packed in a glass jar like loose change.",
		rarity = "Rare",
		odds = 280, -- 1 in N per dig in a stocking stage
		weight = 50,
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 3700,
		model = "ImportedNuke",
	},
	{
		id = "bullion_bar",
		name = "Bullion Nuke",
		flavor = "Cast in gold. Somebody got greedy.",
		rarity = "Epic",
		odds = 1600, -- 1 in N per dig in a stocking stage
		weight = 100,
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 16000,
		model = "ImportedNuke",
	},
	{
		id = "diamond_brooch",
		name = "Diamond Nuke",
		flavor = "Catches light nobody else out here can see.",
		rarity = "Epic",
		odds = 2200, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 19000,
		model = "ImportedNuke",
	},
	{
		id = "rusted_farm_safe",
		name = "Buried Nuke",
		flavor = "Under the old farmhouse. Somebody hid this well.",
		rarity = "Legendary",
		odds = 4000, -- 1 in N per dig in a stocking stage
		weight = 470,
		stages = { 3, 4 },
		appeal = "Collector",
		sets = {},
		baseValue = 60000,
		model = "ImportedNuke",
	},

	-- ══ STAGE 4 — THE EXCLUSION BELT ════════════════════════════════════════
	-- Deliberately thin and top-heavy: its job is to answer "will players dive?",
	-- not to be farmed. The Stage-3 items tagged { 3, 4 } above carry its lower
	-- rarities; no Scrap tier here either, same as Stage 3.

	{
		id = "glowing_sample_jar",
		name = "Glowing Nuke",
		flavor = "Glows a soft green, even in the dark.",
		rarity = "Rare",
		odds = 180, -- 1 in N per dig in a stocking stage
		weight = 25,
		stages = { 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 4400,
		model = "ImportedNuke",
	},
	{
		id = "strange_metal_chip",
		name = "Humming Nuke",
		flavor = "Covered in markings nobody recognizes. Hums if you hold it.",
		rarity = "Epic",
		odds = 1400, -- 1 in N per dig in a stocking stage
		weight = 11,
		stages = { 4 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 23000,
		model = "ImportedNuke",
	},
	{
		id = "reactor_rod",
		name = "Reactor Nuke",
		flavor = "The whole reason there's a Belt and not something worse.",
		rarity = "Legendary",
		odds = 5000, -- 1 in N per dig in a stocking stage
		weight = 200,
		stages = { 4 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 120000,
		model = "ImportedNuke",
	},

	-- ══ STAGE 5 — REACTOR GROUNDS ═══════════════════════════════════════════
	-- `reactor_control` extends across the Stage 4 boundary on purpose -- Stage 5
	-- sits right next to the Belt in the chain, so the set reads as one storyline.
	-- NO SCRAP TIER (see this file's header) -- its old Scrap items folded into
	-- Common, and the old pressure_gauge Common slot promoted to Uncommon.

	{
		id = "old_pipe_scrap",
		name = "Pipe Nuke",
		flavor = "A crude little thing, cobbled together in a hurry.",
		rarity = "Common",
		odds = 7, -- 1 in N per dig in a stocking stage
		weight = 55,
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 60,
		model = "ImportedNuke",
	},
	{
		id = "shiny_metal_blade",
		name = "Polished Nuke",
		flavor = "Mirror-bright, curved like it was cutting something once.",
		rarity = "Common",
		odds = 9, -- 1 in N per dig in a stocking stage
		weight = 30,
		stages = { 5 },
		appeal = "Researcher",
		sets = {},
		baseValue = 67,
		model = "ImportedNuke",
	},
	{
		id = "rad_warning_placard",
		name = "Labelled Nuke",
		flavor = "The markings are brighter than the actual danger.",
		rarity = "Common",
		odds = 12, -- 1 in N per dig in a stocking stage
		weight = 35,
		stages = { 5 },
		appeal = "Collector",
		sets = {},
		baseValue = 100,
		model = "ImportedNuke",
	},
	{
		id = "pressure_gauge",
		name = "Pressurized Nuke",
		flavor = "Needle buried past the red for years.",
		rarity = "Uncommon",
		odds = 40, -- 1 in N per dig in a stocking stage
		weight = 22,
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 400,
		model = "ImportedNuke",
	},
	{
		id = "old_headphones",
		name = "Static Nuke",
		flavor = "One side still crackles if you listen close.",
		rarity = "Uncommon",
		odds = 50, -- 1 in N per dig in a stocking stage
		weight = 15,
		stages = { 5 },
		appeal = "Gearhead",
		sets = { "reactor_control" },
		baseValue = 430,
		model = "ImportedNuke",
	},
	{
		id = "cooling_valve_wheel",
		name = "Seized Nuke",
		flavor = "A big wheel that won't turn any more.",
		rarity = "Uncommon",
		odds = 65, -- 1 in N per dig in a stocking stage
		weight = 85,
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 600,
		model = "ImportedNuke",
	},
	{
		id = "reactor_logbook",
		name = "Marked Nuke",
		flavor = "One word on the casing, underlined twice.",
		rarity = "Rare",
		odds = 240, -- 1 in N per dig in a stocking stage
		weight = 28,
		stages = { 5 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 2800,
		model = "ImportedNuke",
	},
	{
		id = "sealed_data_drive",
		name = "Encrypted Nuke",
		flavor = "Locked in a lead case. Someone wanted this kept safe.",
		rarity = "Rare",
		odds = 300, -- 1 in N per dig in a stocking stage
		weight = 50,
		stages = { 5 },
		appeal = "Researcher",
		sets = {},
		baseValue = 3900,
		model = "ImportedNuke",
	},
	{
		id = "blackbox_recorder",
		name = "Black-Box Nuke",
		flavor = "Built to survive anything. Lots of practice at it.",
		rarity = "Epic",
		odds = 1500, -- 1 in N per dig in a stocking stage
		weight = 65,
		stages = { 5 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 17000,
		model = "ImportedNuke",
	},
	{
		id = "sealed_fuel_casing",
		name = "Drained Nuke",
		flavor = "Empty now, but it used to hold something that glowed.",
		rarity = "Epic",
		odds = 1800, -- 1 in N per dig in a stocking stage
		weight = 130,
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 21000,
		model = "ImportedNuke",
	},
	{
		id = "reactor_core_sample",
		name = "Core Nuke",
		flavor = "Warm through three layers of metal. Never once cooled.",
		rarity = "Legendary",
		odds = 6000, -- 1 in N per dig in a stocking stage
		weight = 160,
		stages = { 5 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 100000,
		model = "ImportedNuke",
	},
	{
		id = "live_fuel_rod",
		name = "Atomic Bomb",
		flavor = "Still glowing. Still humming. Exactly as dangerous as the day it was made.",
		rarity = "Mythic",
		odds = 50000, -- 1 in N per dig in a stocking stage
		weight = 220,
		stages = { 5 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 600000,
		model = "ImportedNuke",
	},

	-- ══ STAGE 6 — THE CRATER ════════════════════════════════════════════════
	-- `crater_relics` ties three showpiece items into one thread, the way
	-- `left_behind` does for Stage 1. NO SCRAP TIER (see this file's header) --
	-- its old Scrap item folded into Common.

	{
		id = "glassy_ground_chip",
		name = "Glassy Nuke",
		flavor = "Fused into glass by something bigger nearby.",
		rarity = "Common",
		odds = 8, -- 1 in N per dig in a stocking stage
		weight = 13,
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 47,
		model = "ImportedNuke",
	},
	{
		id = "scorched_metal_plate",
		name = "Scorched Nuke",
		flavor = "Rated to hold back anything. Didn't.",
		rarity = "Common",
		odds = 11, -- 1 in N per dig in a stocking stage
		weight = 65,
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 120,
		model = "ImportedNuke",
	},
	{
		id = "sealed_air_filter",
		name = "Unopened Nuke",
		flavor = "Still wrapped, still sealed, still waiting.",
		rarity = "Uncommon",
		odds = 35, -- 1 in N per dig in a stocking stage
		weight = 22,
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 470,
		model = "ImportedNuke",
	},
	{
		id = "bent_door_wheel",
		name = "Warped Nuke",
		flavor = "Spun the wrong way, hard.",
		rarity = "Uncommon",
		odds = 55, -- 1 in N per dig in a stocking stage
		weight = 70,
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 700,
		model = "ImportedNuke",
	},
	{
		id = "cracked_glow_badge",
		name = "Fading Nuke",
		flavor = "Went dark in under a second.",
		rarity = "Rare",
		odds = 220, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 3100,
		model = "ImportedNuke",
	},
	{
		id = "fused_tool_roll",
		name = "Welded Nuke",
		flavor = "Every tool on it fused solid.",
		rarity = "Rare",
		odds = 260, -- 1 in N per dig in a stocking stage
		weight = 60,
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 4300,
		model = "ImportedNuke",
	},
	{
		id = "untouched_ground_sample",
		name = "Pristine Nuke",
		flavor = "Not a scratch on it. Nobody knows how.",
		rarity = "Epic",
		odds = 1400, -- 1 in N per dig in a stocking stage
		weight = 110,
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 22000,
		model = "ImportedNuke",
	},
	{
		id = "skyglow_core_fragment",
		name = "Sky-Glow Nuke",
		flavor = "Lights up the crater at night, all by itself.",
		rarity = "Epic",
		odds = 1700, -- 1 in N per dig in a stocking stage
		weight = 80,
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 26000,
		model = "ImportedNuke",
	},
	{
		id = "ufo_fragment",
		name = "Alien Nuke",
		flavor = "Not from here. Not from anywhere else, either.",
		rarity = "Epic",
		odds = 2000, -- 1 in N per dig in a stocking stage
		weight = 45,
		stages = { 6 },
		appeal = "Researcher",
		sets = {},
		baseValue = 24000,
		model = "ImportedNuke",
	},
	{
		id = "explorers_helmet",
		name = "Pioneer Nuke",
		flavor = "Carried by whoever mapped this place first.",
		rarity = "Legendary",
		odds = 7000, -- 1 in N per dig in a stocking stage
		weight = 35,
		stages = { 6 },
		appeal = "Collector",
		sets = { "crater_relics" },
		baseValue = 140000,
		model = "ImportedNuke",
	},
	{
		id = "mini_nuke",
		name = "Mini Nuke",
		flavor = "Bright yellow, comically oversized, and definitely not armed. Probably.",
		rarity = "Legendary",
		odds = 9000, -- 1 in N per dig in a stocking stage
		weight = 290,
		stages = { 6 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 160000,
		model = "ImportedNuke",
	},
	{
		id = "stopped_second_hand",
		name = "Cosmic Nuke",
		flavor = "A single glowing hand, pointing at nothing in particular.",
		rarity = "Mythic",
		odds = 60000, -- 1 in N per dig in a stocking stage
		weight = 5,
		stages = { 6 },
		appeal = "Collector",
		sets = { "crater_relics" },
		baseValue = 930000,
		model = "ImportedNuke",
	},
	{
		id = "unlabeled_cylinder",
		name = "The Big One",
		flavor = "Heavier than it looks. Nobody's brave enough to open it.",
		rarity = "Anomaly",
		odds = 500000, -- 1 in N per dig in a stocking stage
		weight = 490,
		sizeMult = 1.2, -- bigger
		stages = { 6 },
		appeal = "Researcher",
		sets = { "crater_relics" },
		baseValue = 6000000,
		model = "ImportedNuke",
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

--- Whether `id` names a catalogue entry. For input that did not come from the
--- catalogue itself (a client remote, an old save), where `get`'s assert would throw.
function Items.has(id: string): boolean
	return byId[id] ~= nil
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

--- The "1 in N" a surface should PRINT for an item: its authored `odds` headline
--- inflated by the weight penalty (Config/Weight.rollBias), so what a player reads
--- moves with what the roll actually does. One place, so no surface open-codes it.
function Items.shownOdds(item: ItemDef): number
	return Weight.shownOdds(item.odds, item.weight)
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
--   weight (Config/Weight.rollBias, per item) multiplies the weight by a <= 1 factor:
--     the feather end a touch rarer, the heavy end buried deep. Mid-weight items are
--     untouched (factor exactly 1). Items.shownOdds carries the same factor to the HUD.
--
-- Shared, like Liquids.oddsAt / Radiation / Decay: the weight a HUD could DISPLAY and
-- the weight DigService rolls come out of ONE function so they cannot disagree.

--- Luck is inert below this rarity order (Rare). "Rarer-only" -- see the header.
Items.DIG_LUCK_MIN_ORDER = Rarity.get("Rare").order
--- The most detector luck can ever multiply one item's roll weight.
Items.DIG_LUCK_BIAS_CAP = 20

--- The luck exponent for a rarity: luck^1 at Rare, luck^2 at Epic, ... clamped to
--- DIG_LUCK_BIAS_CAP. Exactly 1 (untouched) for anything below DIG_LUCK_MIN_ORDER.
---
--- `boost` is 2x luck (Config/LuckBoost, 1 when absent): a flat multiplier on the
--- same Rare+ rungs, applied OUTSIDE the cap. The cap bounds what a detector can do;
--- the boost is "twice as likely" on top of whatever that is. Folding it into `luck`
--- instead would hit the cap and lower a maxed detector's Legendary odds -- see
--- Config/LuckBoost's header for the measured numbers.
function Items.luckBias(rarity: string, luck: number, boost: number?): number
	local order = Rarity.get(rarity).order
	if order < Items.DIG_LUCK_MIN_ORDER then
		return 1
	end
	return math.min(luck ^ (order - Items.DIG_LUCK_MIN_ORDER + 1), Items.DIG_LUCK_BIAS_CAP) * (boost or 1)
end

--- One item's roll weight in a stage: 1/odds, tilted by rarity, luck-boosted at the
--- top, and biased down by its physical weight (Config/Weight.rollBias).
function Items.effectiveWeight(item: ItemDef, tilt: number, luck: number, boost: number?): number
	local order = Rarity.get(item.rarity).order
	return (1 / item.odds)
		* tilt ^ (order - 1)
		* Items.luckBias(item.rarity, luck, boost)
		* Weight.rollBias(item.weight)
end

--- Normalised roll probability per stocked item in a stage, keyed by id. Sums to 1.
--- Empty when the stage stocks nothing. The odds this could be shown next to and the
--- odds Items.rollItem draws against come out of here together.
function Items.rollWeights(stageId: number, tilt: number, luck: number, boost: number?): { [string]: number }
	local pool = stageItems[stageId]
	local out: { [string]: number } = {}
	if pool == nil then
		return out
	end

	local total = 0
	for _, item in pool do
		total += Items.effectiveWeight(item, tilt, luck, boost)
	end
	if total <= 0 then
		return out
	end
	for _, item in pool do
		out[item.id] = Items.effectiveWeight(item, tilt, luck, boost) / total
	end
	return out
end

--- Weighted pick of one item id from a stage's pool. Walks `stageItems` in its stable
--- order so the roll is reproducible. Returns nil ONLY when the stage stocks nothing at
--- all -- callers treat that as a content gap (no signals spawn), not a crash.
function Items.rollItem(stageId: number, tilt: number, luck: number, boost: number?): string?
	local pool = stageItems[stageId]
	if pool == nil or #pool == 0 then
		return nil
	end

	local total = 0
	for _, item in pool do
		total += Items.effectiveWeight(item, tilt, luck, boost)
	end

	local pick = math.random() * total
	for _, item in pool do
		pick -= Items.effectiveWeight(item, tilt, luck, boost)
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
