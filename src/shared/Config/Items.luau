--!strict
--[[
	Items.lua — the catalogue. Data only, like everything else in Config/.

	MVP scope (PLAN §15): Zones 1-4, ~41 items, Scrap through Legendary.

	A ZONE WITH NO ITEMS IS NOT A CRASH ANY MORE, BUT IT IS STILL BROKEN. DigService
	rolls a rarity from the zone's loot table and then steps DOWN through the
	catalogue looking for something to hand you. That step-down only goes downward —
	so a zone stocked only at Rare and above silently fails every Scrap and Common
	roll and fills its field at a fraction of the intended rate. Stock the LOW end of
	every zone you add, not just the exciting end.

	TWO RULES, both from ARCHITECTURE.md, both cheap now and miserable to retrofit:

	1. FLAVOR TEXT CARRIES A STORY. "Child's lunchbox, dented, still latched" hits
	   far harder than "Rare Metal Object #7", costs the same to store, and doubles as
	   the game's best marketing surface once exhibits are public (PLAN §8.6).

	2. EVERY ITEM HAS AN `appeal`. Researcher / Collector / Gearhead — the visitor
	   type that comes to see it (PLAN §8.3). Tag it as you write the item. That one
	   field is what turns a loot table into a museum, and adding it across a finished
	   catalogue later is exactly the job nobody does.

	baseValue must sit inside its rarity's band in Rarity.DEFS. Zone 1 deliberately
	carries a Legendary: PLAN §4 wants "it could happen right here" live from minute
	one, because that chance is what keeps a new player sweeping.

	No `model` field yet — DigService renders a rarity-coloured placeholder until art
	exists.
]]

export type ItemDef = {
	id: string,
	name: string,
	flavor: string,
	rarity: string,
	zones: { number },
	appeal: string, -- "Researcher" | "Collector" | "Gearhead"
	sets: { string },
	baseValue: number,
}

local Items = {}

Items.DEFS = {
	-- ── Scrap ── $1-5 ──────────────────────────────────────────────────────
	{
		id = "bottle_cap",
		name = "Bottle Cap",
		flavor = "Bent double. The logo is still readable if you squint.",
		rarity = "Scrap",
		zones = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 3,
	},
	{
		id = "rebar_stub",
		name = "Rebar Stub",
		flavor = "Snapped clean through. Something very large came this way.",
		rarity = "Scrap",
		zones = { 1 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 4,
	},
	{
		id = "fused_glass",
		name = "Fused Glass Lump",
		flavor = "Sand that stood too close.",
		rarity = "Scrap",
		zones = { 1 },
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
		zones = { 1 },
		appeal = "Collector",
		sets = {},
		baseValue = 12,
	},
	{
		id = "house_key",
		name = "House Key",
		flavor = "Still on its ring, with two smaller ones beside it.",
		rarity = "Common",
		zones = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 18,
	},
	{
		id = "stopped_watch",
		name = "Stopped Wristwatch",
		flavor = "Stopped at 8:14. So did everyone else's.",
		rarity = "Common",
		zones = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 22,
	},

	-- ── Uncommon ── $25-120 ─────────────────────────────────────────────
	-- NOTE: Uncommon is hardness 2 and a Wire Brush is potency 1, so the first of
	-- these a new player digs CANNOT be cleaned yet. That is the §6 staggered reveal
	-- working — but it also contradicts PLAN §12, whose scripted tutorial has you
	-- clean and sell a rigged Uncommon 90 seconds in. Flagged, not silently patched.
	{
		id = "tin_soldier",
		name = "Tin Soldier",
		flavor = "Paint worn off the face. Still standing at attention.",
		rarity = "Uncommon",
		zones = { 1 },
		appeal = "Collector",
		sets = { "childrens_toys" },
		baseValue = 45,
	},
	{
		id = "field_multimeter",
		name = "Field Multimeter",
		flavor = "Needle pinned hard right. It was working when it stopped.",
		rarity = "Uncommon",
		zones = { 1 },
		appeal = "Gearhead",
		sets = { "salvage_kit" },
		baseValue = 60,
	},
	{
		id = "wedding_band",
		name = "Wedding Band",
		flavor = "Inscribed inside. The engraving outlasted everything it was about.",
		rarity = "Uncommon",
		zones = { 1 },
		appeal = "Collector",
		sets = { "left_behind" },
		baseValue = 85,
	},

	-- ── Rare ── $120-700 ───────────────────────────────────────────────
	{
		id = "geiger_handset",
		name = "Prewar Geiger Handset",
		flavor = "Someone taped a photograph to the back. It did not survive.",
		rarity = "Rare",
		zones = { 1 },
		appeal = "Gearhead",
		sets = { "salvage_kit" },
		baseValue = 340,
	},
	{
		id = "film_canister",
		name = "Sealed Film Canister",
		flavor = "Thirty-six exposures. Nobody has ever looked at them.",
		rarity = "Rare",
		zones = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 480,
	},

	-- ── Epic ── $700-4k ─────────────────────────────────────────────────
	{
		id = "lab_sample_case",
		name = "Lab Sample Case",
		flavor = "Six vials, five intact. The sixth is why the grass here is white.",
		rarity = "Epic",
		zones = { 1 },
		appeal = "Researcher",
		sets = { "field_medicine" },
		baseValue = 1900,
	},

	-- ── Legendary ── $4k-30k ────────────────────────────────────────────
	-- 0.15% in Zone 1. Almost nobody will see this. That is the point.
	{
		id = "evac_ledger",
		name = "Evacuation Ledger",
		flavor = "Four hundred names. Three hundred and eleven crossed out.",
		rarity = "Legendary",
		zones = { 1 },
		appeal = "Researcher",
		sets = {},
		baseValue = 9500,
	},

	-- ══ ZONE 2 — THE SUBURBS ═══════════════════════════════════════════════
	-- Collapsed houses and half-buried cars (PLAN §4). The theme is a life
	-- interrupted mid-sentence, so the flavor leans domestic rather than martial.

	{
		id = "cracked_tile",
		name = "Cracked Tile",
		flavor = "Someone chose this pattern. Stood in a shop and chose it.",
		rarity = "Scrap",
		zones = { 2 },
		appeal = "Collector",
		sets = { "suburban_kitchen" },
		baseValue = 3,
	},
	{
		id = "door_hinge",
		name = "Door Hinge",
		flavor = "Still swings. There is no longer a door, or a wall.",
		rarity = "Scrap",
		zones = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 4,
	},
	{
		id = "cutlery_set",
		name = "Cutlery Set",
		flavor = "Wrapped in a napkin, in a drawer, waiting for a dinner that never happened.",
		rarity = "Common",
		zones = { 2 },
		appeal = "Collector",
		sets = { "suburban_kitchen" },
		baseValue = 14,
	},
	{
		id = "garden_trowel",
		name = "Garden Trowel",
		flavor = "Left in the soil, handle up, like it would be picked up tomorrow.",
		rarity = "Common",
		zones = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 19,
	},
	{
		id = "doll_head",
		name = "Porcelain Doll Head",
		flavor = "The eyes still open and close. Please stop testing whether the eyes still open and close.",
		rarity = "Common",
		zones = { 2 },
		appeal = "Collector",
		sets = { "childrens_toys" },
		baseValue = 23,
	},
	{
		id = "charm_bracelet",
		name = "Charm Bracelet",
		flavor = "Eleven charms. A tiny bicycle, a tiny cat, a tiny house.",
		rarity = "Uncommon",
		zones = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 55,
	},
	{
		id = "socket_set",
		name = "Socket Wrench Set",
		flavor = "Every socket in its slot. Whoever owned this was particular about it.",
		rarity = "Uncommon",
		zones = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 72,
	},
	{
		id = "photo_locket",
		name = "Photo Locket",
		flavor = "Two faces, one hinge. The catch still works.",
		rarity = "Uncommon",
		zones = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 98,
	},
	{
		id = "pearl_necklace",
		name = "Pearl Necklace",
		flavor = "Kept for good occasions. There was one more, and nobody knew.",
		rarity = "Rare",
		zones = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 310,
	},
	{
		id = "ignition_coil",
		name = "Ignition Coil",
		flavor = "Pulled from a car pointed away from the city, tank full, doors open.",
		rarity = "Rare",
		zones = { 2 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 450,
	},
	{
		id = "clock_movement",
		name = "Grandfather Clock Movement",
		flavor = "Brass, hand-cut, unbothered. It would run today if you wound it.",
		rarity = "Epic",
		zones = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 1650,
	},
	{
		id = "deposit_box",
		name = "Safe Deposit Box",
		flavor = "Whatever was worth a bank vault is still inside, and still yours now.",
		rarity = "Legendary",
		zones = { 2 },
		appeal = "Collector",
		sets = {},
		baseValue = 8200,
	},

	-- ══ ZONE 3 — FALLOUT FIELDS ════════════════════════════════════════════
	-- Military tags, ordnance, gold (PLAN §4). Several of these are also tagged
	-- for Zone 4: the Exclusion Belt is the same war, further in, and a dive needs
	-- a stocked catalogue at EVERY rarity or rollItemId's step-down finds nothing.

	{
		id = "spent_casing",
		name = "Spent Casing",
		flavor = "Brass lasts. That is the whole story of this place, in one object.",
		rarity = "Scrap",
		zones = { 3, 4 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 4,
	},
	{
		id = "melted_button",
		name = "Melted Button",
		flavor = "Uniform issue. The thread survived; the man did not.",
		rarity = "Scrap",
		zones = { 3, 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 5,
	},
	{
		id = "dog_tag",
		name = "Dog Tag",
		flavor = "Stamped, notched, and still legible. Someone is owed this back.",
		rarity = "Common",
		zones = { 3, 4 },
		appeal = "Collector",
		sets = {},
		baseValue = 16,
	},
	{
		id = "ration_tin",
		name = "Ration Tin",
		flavor = "Unopened. The label promises peaches.",
		rarity = "Common",
		zones = { 3, 4 },
		appeal = "Collector",
		sets = {},
		baseValue = 21,
	},
	{
		id = "dressing_kit",
		name = "Field Dressing Kit",
		flavor = "Opened, used, repacked, opened again. Somebody was very busy here.",
		rarity = "Uncommon",
		zones = { 3, 4 },
		appeal = "Researcher",
		sets = { "field_medicine" },
		baseValue = 58,
	},
	{
		id = "signal_flare",
		name = "Signal Flare",
		flavor = "Never fired. Whatever it was meant to summon was not coming.",
		rarity = "Uncommon",
		zones = { 3 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 80,
	},
	{
		id = "officers_compass",
		name = "Officer's Compass",
		flavor = "The needle spins here. It has been spinning for a long time.",
		rarity = "Uncommon",
		zones = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 110,
	},
	{
		id = "gold_signet",
		name = "Gold Signet Ring",
		flavor = "Gold does not care about any of this. That is why it is worth something.",
		rarity = "Rare",
		zones = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 380,
	},
	{
		id = "inert_mortar",
		name = "Inert Mortar Round",
		flavor = "The fuse was pulled. Probably. The magnet does not ask.",
		rarity = "Rare",
		zones = { 3 },
		appeal = "Gearhead",
		sets = {},
		baseValue = 560,
	},
	{
		id = "dosimeter",
		name = "Radiation Dosimeter",
		flavor = "Pegged at maximum and stayed there. Its owner did not leave with it.",
		rarity = "Rare",
		zones = { 3, 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 640,
	},
	{
		id = "bullion_bar",
		name = "Gold Bullion Bar",
		flavor = "Someone carried this out of a vault, into a field, and got no further.",
		rarity = "Epic",
		zones = { 3 },
		appeal = "Collector",
		sets = {},
		baseValue = 2400,
	},
	{
		id = "field_radio",
		name = "Encrypted Field Radio",
		flavor = "Set to a frequency that still, very occasionally, answers.",
		rarity = "Epic",
		zones = { 3, 4 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 3100,
	},
	{
		id = "cipher_case",
		name = "Command Cipher Case",
		flavor = "The orders are inside. Nobody has wanted to be the one to read them.",
		rarity = "Legendary",
		zones = { 3, 4 },
		appeal = "Researcher",
		sets = {},
		baseValue = 12000,
	},

	-- ══ ZONE 4 — THE EXCLUSION BELT ════════════════════════════════════════
	-- Prewar tech and lab samples (PLAN §4). Deliberately thin and top-heavy:
	-- PLAN §15 wants Zone 4 to have a loot table and a rad rate and nothing else,
	-- because its job is to answer "will players dive?", not to be farmed. The
	-- Zone-3 items tagged { 3, 4 } above carry its lower rarities.

	{
		id = "sealed_sample",
		name = "Sealed Lab Sample",
		flavor = "Still sealed. Still humming. Still, by every measure, alive.",
		rarity = "Rare",
		zones = { 4 },
		appeal = "Researcher",
		sets = { "field_medicine" },
		baseValue = 660,
	},
	{
		id = "microprocessor",
		name = "Prewar Microprocessor",
		flavor = "Nobody left knows how to make one of these. Several would like to.",
		rarity = "Epic",
		zones = { 4 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 3400,
	},
	{
		id = "control_rod",
		name = "Reactor Control Rod",
		flavor = "It did its job. It is the reason there is a Belt and not a second Crater.",
		rarity = "Legendary",
		zones = { 4 },
		appeal = "Researcher",
		sets = { "reactor_control" },
		baseValue = 18000,
	},
} :: { ItemDef }

-- ── Indexes, built once ──────────────────────────────────────────────────

local byId: { [string]: ItemDef } = {}
local byZoneRarity: { [number]: { [string]: { ItemDef } } } = {}

for _, item in Items.DEFS do
	assert(byId[item.id] == nil, `duplicate item id "{item.id}"`)
	byId[item.id] = item

	for _, zoneId in item.zones do
		local zone = byZoneRarity[zoneId]
		if zone == nil then
			zone = {}
			byZoneRarity[zoneId] = zone
		end
		local bucket = zone[item.rarity]
		if bucket == nil then
			bucket = {}
			zone[item.rarity] = bucket
		end
		table.insert(bucket, item)
	end
end

function Items.get(id: string): ItemDef
	local item = byId[id]
	assert(item, `unknown item id "{id}"`)
	return item
end

--- Every item of one rarity that can spawn in one zone. May be empty — Zone 1 has
--- no Mythic or Anomaly entries, and the loot table can still roll them, so callers
--- must handle the empty case rather than assuming a hit.
function Items.inZone(zoneId: number, rarity: string): { ItemDef }
	local zone = byZoneRarity[zoneId]
	if zone == nil then
		return {}
	end
	return zone[rarity] or {}
end

function Items.hasAny(zoneId: number, rarity: string): boolean
	return #Items.inZone(zoneId, rarity) > 0
end

return Items
