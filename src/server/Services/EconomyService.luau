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
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local EconomyService = {}

local cashRemote: any = nil

--- The wallet's one broadcast point, matching the file's own "one place to look"
--- rule for MUTATING data.cash -- this is that rule's other half, for anyone who
--- needs to tell the client it changed. DebugService's /cash calls this too, since
--- it pokes data.cash directly the same way /gear pokes data.gear.
function EconomyService.pushCash(player: Player)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	cashRemote:FireClient(player, data.cash)
end

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
	EconomyService.pushCash(player)

	local note = if clean then "" else ` (dirty, {math.floor(Tuning.DIRTY_SELL_MULTIPLIER * 100)}%)`
	return true, `sold {def.name} for ${value}{note}`
end

--- Take cash off a player, or refuse. THE ONLY DEBIT IN THE GAME.
---
--- `data.cash += value` in sell() above was, until this function existed, the only
--- line in the entire codebase that touched a player's money. That is a property
--- worth keeping: one file owns the wallet, so "where did my cash go" has exactly
--- one place to look. Shops call this rather than reaching into the profile.
---
--- Check-and-debit are deliberately in the same function. Split across two calls
--- they become a window where a second purchase can be approved against money the
--- first one already spent.
function EconomyService.spend(player: Player, amount: number): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	assert(amount >= 0, "spend() takes a positive amount; use award() to give cash")
	local price = math.floor(amount + 0.5)

	if data.cash < price then
		return false, `you need ${price - data.cash} more`
	end

	data.cash -= price
	EconomyService.pushCash(player)
	return true, `paid ${price}`
end

--- The counterpart, so refunds and payouts do not open-code the field either.
function EconomyService.award(player: Player, amount: number): boolean
	local data = DataService.data(player)
	if data == nil then
		return false
	end
	data.cash += math.max(0, math.floor(amount + 0.5))
	EconomyService.pushCash(player)
	return true
end

function EconomyService.init()
	cashRemote = Net.get("CashState")
end

function EconomyService.start()
	-- The initial snapshot, same shape as DigService's IndexState hook: a returning
	-- player's badge should show their real balance from the first frame, not $0
	-- until their next sell/spend.
	DataService.onLoaded(function(player, _data)
		EconomyService.pushCash(player)
	end)
end

return EconomyService
