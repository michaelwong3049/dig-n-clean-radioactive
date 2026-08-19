--!strict
--[[
	Items.lua — the catalogue. Data only, like everything else in Config/.

	Phase 1 scope: Zone 1 (Ash Flats) only, ~12 items, Scrap through Legendary.

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
