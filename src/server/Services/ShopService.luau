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

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)

local ShopService = {}

local resultRemote: any = nil

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
--- The purchase itself, with NO opinion about where the player is standing.
---
--- Split out of `buy` when the Luck track moved from a shop counter to a wooden sign
--- with a ProximityPrompt on it (build/Plots.buildLuckSign). Everything that makes a
--- purchase safe is in here — the track is checked against Gear.TRACKS before it can
--- index anything, the tier against that track's own length and against what you
--- already own, and the price is read back out of Gear.tier() and never taken from a
--- caller. What is NOT in here is the proximity check, because the two call sites
--- prove proximity in genuinely different ways:
---
---   buy()            a client sent a request naming a shop, so the server has to
---                    re-derive the player's position itself and refuse a mismatch.
---   the sign prompt  ProximityPrompt.Triggered fires ON THE SERVER, and Roblox
---                    enforces MaxActivationDistance before it ever fires. The
---                    proximity is not a claim to be checked; it is a precondition
---                    the engine already established.
---
--- That is why the sign can skip StationService entirely and the counters cannot.
function ShopService.buyTier(player: Player, track: string, tier: number?): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	-- Reject anything that is not a real track before it can index a table.
	if not isTrack(track) then
		return false, "no such shop"
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

--- The NEXT rung of a track, for callers that sell one step at a time rather than
--- offering a ladder. The sign uses this: a wooden plank has no room for eight buy
--- buttons, and "press E to upgrade" is the whole interaction.
function ShopService.buyNext(player: Player, track: string): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	if not isTrack(track) then
		return false, "no such track"
	end

	local key = Gear.profileKey(track)
	local nextTier = (data.gear[key] or 1) + 1
	if nextTier > Gear.maxTier(track) then
		return false, `{Gear.tier(track, Gear.maxTier(track)).name} is the top of the {track} line`
	end
	return ShopService.buyTier(player, track, nextTier)
end

function ShopService.buy(player: Player, track: string, tier: number?): (boolean, string)
	-- THE CLIENT IS NEVER TRUSTED ABOUT WHERE IT IS STANDING. The request names a
	-- shop; the server independently asks StationService which shop this player is
	-- actually at and refuses if it is not the one they claim. Everything else about
	-- the purchase lives in buyTier.
	if not isTrack(track) then
		return false, "no such shop"
	end
	local kind = StationService.kindOf(player)
	local id = StationService.idOf(player)
	if kind ~= "shop" or id ~= track then
		return false, "you aren't at that shop"
	end

	return ShopService.buyTier(player, track, tier)
end

-- ── Upgrade signs ─────────────────────────────────────────────────────

--- Matches Kit.UPGRADE_TAG. Hardcoded rather than required, for the same reason
--- Tuning.AURA_TAG is: build/Kit lives in ServerScriptService and this is a service,
--- so a require would work today and stop working the moment anything client-side
--- needs the same string. One name, two places, and World.verify() asserts they agree.
local UPGRADE_TAG = "Upgrade"

--- Wire one world object that sells a track by proximity instead of by panel.
---
--- The prompt is created by the BUILDER (build/Plots.buildLuckSign) and saved with
--- the place; this connects behaviour to it at boot. Splitting it that way is the
--- same split every station already uses — geometry and attributes are build-time,
--- behaviour is runtime — and it is what lets the sign be rebuilt without touching
--- a service.
local function wireUpgrade(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local track = part:GetAttribute("SellsTrack")
	if type(track) ~= "string" then
		return
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt == nil then
		warn(`[shop] {part:GetFullName()} sells "{track}" but has no ProximityPrompt — nobody can buy from it`)
		return
	end

	prompt.Triggered:Connect(function(player: Player)
		local ok, message = ShopService.buyNext(player, track)
		resultRemote:FireClient(player, message)
		if ok then
			print(`[shop] {player.Name}: {message}`)
		end
	end)
end

function ShopService.init()
	resultRemote = Net.get("StationResult")
end

function ShopService.start()
	-- Tag-indexed rather than a Workspace walk, and it covers signs that appear LATER:
	-- World.rebuild() can be run from the command bar mid-session, and a sign built
	-- then would otherwise sit there inert until the next server start.
	for _, part in CollectionService:GetTagged(UPGRADE_TAG) do
		wireUpgrade(part)
	end
	CollectionService:GetInstanceAddedSignal(UPGRADE_TAG):Connect(wireUpgrade)
end

return ShopService
