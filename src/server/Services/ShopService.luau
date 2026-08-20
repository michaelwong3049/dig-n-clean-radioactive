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

	THE CLIENT IS NEVER TRUSTED ABOUT WHERE IT IS STANDING.
	The buy request carries a track name and nothing else. The server independently
	asks StationService which shop this player is actually at and refuses if it is
	not the one they claim. A crafted remote call from anywhere on the map buys
	nothing — the same shape of guard DeconService already applies to sell and scrub.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Gear = require(Shared.Config.Gear)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)

local ShopService = {}

export type Offer = {
	track: string,
	currentTier: number,
	currentName: string,
	nextTier: number?,
	nextName: string?,
	price: number?,
	maxed: boolean,
	affordable: boolean,
	deltas: { string },
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

--- What changes if you buy the next tier, as human-readable lines.
---
--- Computed by diffing the two tier tables rather than written by hand, so it works
--- for all six tracks automatically and cannot go stale when a number is retuned.
--- A shop that says "radius 21 -> 27" sells itself; one that says "Pulse Array"
--- makes the player go and look it up.
local function deltasBetween(current: any, next: any): { string }
	local lines = {}
	for key, value in next do
		if key == "name" or key == "price" then
			continue
		end
		local before = current[key]
		if before == value then
			continue
		end

		if type(value) == "number" and type(before) == "number" then
			local a = if before % 1 == 0 then tostring(before) else string.format("%.2f", before)
			local b = if value % 1 == 0 then tostring(value) else string.format("%.2f", value)
			table.insert(lines, `{key} {a} → {b}`)
		elseif type(value) == "boolean" and value and not before then
			table.insert(lines, `unlocks {key}`)
		end
	end
	table.sort(lines)
	return lines
end

--- Pure. Safe to call every tick to drive the panel.
function ShopService.offerFor(data: any, track: string): Offer?
	if not isTrack(track) or data == nil then
		return nil
	end

	local key = Gear.profileKey(track)
	local currentTier = data.gear[key] or 1
	local currentDef = Gear.tier(track, currentTier)
	local maxTier = Gear.maxTier(track)

	if currentTier >= maxTier then
		return {
			track = track,
			currentTier = currentTier,
			currentName = currentDef.name,
			nextTier = nil,
			nextName = nil,
			price = nil,
			maxed = true,
			affordable = false,
			deltas = {},
		}
	end

	local nextTier = currentTier + 1
	local nextDef = Gear.tier(track, nextTier)

	return {
		track = track,
		currentTier = currentTier,
		currentName = currentDef.name,
		nextTier = nextTier,
		nextName = nextDef.name,
		price = nextDef.price,
		maxed = false,
		affordable = data.cash >= nextDef.price,
		deltas = deltasBetween(currentDef, nextDef),
	}
end

--- Buy the next tier of `track`. Returns (ok, message) like EconomyService.sell.
function ShopService.buy(player: Player, track: string): (boolean, string)
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

	local key = Gear.profileKey(track)
	local currentTier = data.gear[key] or 1
	if currentTier >= Gear.maxTier(track) then
		return false, "that's the best there is"
	end

	local nextTier = currentTier + 1
	local nextDef = Gear.tier(track, nextTier)

	-- Debit first. If this fails nothing else has happened yet, so there is no
	-- half-applied purchase to unwind.
	local paid, reason = EconomyService.spend(player, nextDef.price)
	if not paid then
		return false, reason
	end

	data.gear[key] = nextTier

	return true, `bought {nextDef.name} for ${nextDef.price}`
end

function ShopService.init() end
function ShopService.start() end

return ShopService
