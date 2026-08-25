--!strict
--[[
	ShopService.lua — turning cash back into capability.

	THE APPLY STEP IS ONE LINE, AND THAT IS BY DESIGN, NOT BY ACCIDENT.
	Buying a tier is `data.gear[key] = next`. Nothing else. StatResolver.get() is
	recomputed from the profile every tick, and ToolService compares the held model's
	tier against the profile every third tick and re-equips on a mismatch. So the new
	detector is in your hands within about a third of a second with no event, no
	replication step and no cache to invalidate. ToolService's own comment says as
	much ("buying an upgrade changes what is in your hands the moment it lands") —
	written for a shop that did not exist yet.

	Resist the urge to add machinery here. Anything that fires an event on purchase
	is duplicating a path that already works.

	ANY TIER YOU CAN AFFORD, NOT JUST THE NEXT ONE. `buy()` used to only ever sell
	`currentTier + 1` — a player had to own every rung below the one they wanted.
	That is gone: `buy()` takes a tier number and sells THAT tier directly, for
	exactly its own listed price, as long as it is not already owned. Skipping from
	Bent Coil straight to The Oracle costs The Oracle's price and nothing else — there
	is no toll for the rungs you walked past.

	`offerFor` returns a `tiers` catalog — every tier of the track, worst first, each
	tagged owned/current/buyable/affordable — so the panel can draw all of them as
	cards with the right one enabled. `buyable` now means "not owned", not "the very
	next one"; see `CatalogEntry` below.

	THE CLIENT IS NEVER TRUSTED ABOUT WHERE IT IS STANDING, OR WHAT THINGS COST.
	The buy request carries a track name and a tier number, and neither is trusted on
	its own. The server independently asks StationService which shop this player is
	actually at and refuses if it is not the one they claim; the tier is checked
	against that track's own length and against what the player already owns; and the
	price is read back out of Gear.tier(), never out of the request. A crafted remote
	call from anywhere on the map, naming any tier, buys nothing but what a real click
	at that shop could have bought — the same shape of guard DeconService already
	applies to sell and scrub.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)

local ShopService = {}

--- One rung of the ladder, as the shop panel draws it.
---
--- `buyable` IS `not owned` now — every tier past what you already have, all at
--- once, each gated only by its OWN price. There is no "buy them in order" rule left
--- to encode; the panel shows every locked tier as a live purchase button rather
--- than a preview of what comes next.
export type CatalogEntry = {
	tier: number,
	name: string,
	price: number,
	stats: { string },
	owned: boolean, -- tier <= currentTier
	current: boolean, -- tier == currentTier: what is in your hands now
	buyable: boolean, -- tier > currentTier: not owned, purchasable on its own
	affordable: boolean, -- buyable AND you have the cash for THIS tier's price
}

export type Offer = {
	track: string,
	maxed: boolean, -- currentTier is already the top of the ladder
	tiers: { CatalogEntry },
}

local function isTrack(track: string?): boolean
	if track == nil then
		return false
	end
	for _, known in Gear.TRACKS do
		if known == track then
			return true
		end
	end
	return false
end

--- 0.9970 and 0.9988 are two different suits; "1.00" and "1.00" are not. Suit
--- `reduction` is the one stat whose whole ladder lives in the fourth decimal, so
--- format wide and trim the trailing zeros rather than picking a fixed precision
--- that flattens it.
local function num(value: number): string
	if value % 1 == 0 then
		return tostring(value)
	end
	local s = string.format("%.4f", value)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s
end

--- `maxRarity` is a field name; "max rarity" is a label. The catalog is read by a
--- player, not by whoever wrote Config/Gear.
local function pretty(key: string): string
	local spaced = string.gsub(key, "(%l)(%u)", "%1 %2")
	return string.lower(spaced)
end

--- Everything this tier IS, rather than what it adds. Absolute stats on every card
--- so the ladder can be read across — deltas describe one step and are useless for
--- comparing rung 2 against rung 7 at a glance.
local function statLines(def: any): { string }
	local lines = {}
	for key, value in def do
		if key == "name" or key == "price" then
			continue
		end
		if type(value) == "number" then
			table.insert(lines, `{pretty(key)} {num(value)}`)
		elseif type(value) == "boolean" and value then
			table.insert(lines, pretty(key))
		end
	end
	table.sort(lines)
	return lines
end

--- Every tier of `track`, worst first, tagged with where the player sits on it.
---
--- Worst-first needs no sorting: Config/Gear already lists each track in ascending
--- tier order, and `Gear.tier(track, n)` indexes that list directly. If a track is
--- ever reordered there, this comes out reordered too — which is correct, since the
--- tier NUMBER is the thing the profile stores.
local function catalogFor(data: any, track: string): { CatalogEntry }
	local currentTier = data.gear[Gear.profileKey(track)] or 1
	local entries = {}

	for tier = 1, Gear.maxTier(track) do
		local def = Gear.tier(track, tier)
		local buyable = tier > currentTier
		table.insert(entries, {
			tier = tier,
			name = def.name,
			price = def.price,
			stats = statLines(def),
			owned = tier <= currentTier,
			current = tier == currentTier,
			buyable = buyable,
			affordable = buyable and data.cash >= def.price,
		})
	end

	return entries
end

--- Pure. Safe to call every tick to drive the panel.
function ShopService.offerFor(data: any, track: string): Offer?
	if not isTrack(track) or data == nil then
		return nil
	end

	local key = Gear.profileKey(track)
	local currentTier = data.gear[key] or 1

	return {
		track = track,
		maxed = currentTier >= Gear.maxTier(track),
		tiers = catalogFor(data, track),
	}
end

--- Buy a SPECIFIC tier of `track`, not necessarily the next one. Returns (ok,
--- message) like EconomyService.sell.
---
--- `tier` is the one number in this request that used to not exist — `buy()` used
--- to infer it as `currentTier + 1` and there was nothing else it could be. Now the
--- client says which card it clicked, so this validates that number the same way any
--- other player-supplied value gets validated at a boundary: a real tier of THIS
--- track, and not one already owned. Neither check is a security boundary on its
--- own — the price still comes from Gear.tier(track, tier), server-side, never from
--- the request — they exist so a malformed tier fails with a message instead of
--- indexing past the end of the array or silently re-selling something you own.
function ShopService.buy(player: Player, track: string, tier: number?): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	-- Reject anything that is not a real track before it can index a table.
	if not isTrack(track) then
		return false, "no such shop"
	end

	-- The player must actually be standing at THIS shop. Derived server-side from
	-- their position, never taken from the request.
	local kind = StationService.kindOf(player)
	local id = StationService.idOf(player)
	if kind ~= "shop" or id ~= track then
		return false, "you aren't at that shop"
	end

	local maxTier = Gear.maxTier(track)
	if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > maxTier then
		return false, "no such tier"
	end

	local key = Gear.profileKey(track)
	local currentTier = data.gear[key] or 1
	if tier <= currentTier then
		return false, "you already have that"
	end

	local def = Gear.tier(track, tier)

	-- Debit first, at THIS tier's own price — not the sum of what it skipped past.
	-- If this fails nothing else has happened yet, so there is no half-applied
	-- purchase to unwind.
	local paid, reason = EconomyService.spend(player, def.price)
	if not paid then
		return false, reason
	end

	data.gear[key] = tier

	return true, `bought {def.name} for ${def.price}`
end

function ShopService.init() end
function ShopService.start() end

return ShopService
