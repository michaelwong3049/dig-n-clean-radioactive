--!strict
--[[
	EconomyService.lua — what an item is worth, and the till.

	THE DIRTY SELL IS AN ESCAPE VALVE, NOT A PUNISHMENT (PLAN §2 step 5). A player who
	cannot clean a thing is never hard-blocked — they are taxed 80% and sent on their
	way. That is deliberate: "I can't clean this yet" has to stay a reason to upgrade,
	not a reason to quit.

	Four multipliers stack into one number, and each is a different system asking to
	be respected:
	  base value        — the item (Items.lua)
	  modifier          — the roll   (Rarity.MODIFIERS)
	  value retained    — the decay clock, so the run home has a felt cost (§3.6)
	  clean / dirty     — the cleaning gate (§2 step 4)
	then sellMultiplier from rebirth and gamepasses, via StatResolver like everything else.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Decay = require(Shared.Decay)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)

local DataService = require(script.Parent.DataService)

local EconomyService = {}

--- Find an item in either the backpack or the Quarantine Locker. Returns the item,
--- the list it lives in, and its index.
function EconomyService.find(data: any, uid: string): (any?, any?, number?)
	for index, item in data.carry do
		if item.uid == uid then
			return item, data.carry, index
		end
	end
	for index, item in data.locker do
		if item.uid == uid then
			return item, data.locker, index
		end
	end
	return nil, nil, nil
end

--- What this item sells for right now, and whether it is clean.
function EconomyService.valueOf(item: any, stats: any): (number, boolean)
	local def = Items.get(item.itemId)
	local mod = Rarity.MODIFIERS[item.modifier] or Rarity.MODIFIERS.None
	local clean = Contamination.isClean(item.patches or {})
	local retained = Decay.valueRetained(item, stats.satchelFuseMult)

	local value = def.baseValue * mod.valueMult * retained * stats.sellMultiplier
	if not clean then
		value *= Tuning.DIRTY_SELL_MULTIPLIER
	end

	-- Never zero. Even Slag sells for a token amount (PLAN §3.6) — a wasted run is
	-- never a FULLY wasted run, and that is the anti-frustration floor.
	return math.max(1, math.floor(value + 0.5)), clean
end

--- Sell one item. Server-side ownership check on every call — the client asks by
--- uid and is never trusted about what it holds.
function EconomyService.sell(player: Player, uid: string): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local item, list, index = EconomyService.find(data, uid)
	if item == nil or list == nil or index == nil then
		return false, "you aren't carrying that"
	end

	local stats = StatResolver.get(data)
	local value, clean = EconomyService.valueOf(item, stats)
	local def = Items.get(item.itemId)

	table.remove(list, index)
	data.cash += value

	local note = if clean then "" else ` (dirty, {math.floor(Tuning.DIRTY_SELL_MULTIPLIER * 100)}%)`
	return true, `sold {def.name} for ${value}{note}`
end

function EconomyService.init() end
function EconomyService.start() end

return EconomyService
