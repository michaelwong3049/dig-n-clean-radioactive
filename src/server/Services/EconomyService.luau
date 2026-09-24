--!strict
--[[
	EconomyService.lua — what an item is worth, and the till.

	THE DIRTY SELL IS AN ESCAPE VALVE, NOT A PUNISHMENT (PLAN §2 step 5). A player who
	cannot clean a thing is never hard-blocked — they are taxed 80% and sent on their
	way. That is deliberate: "I can't clean this yet" has to stay a reason to upgrade,
	not a reason to quit.

	Multipliers stack into one number, and each is a different system asking to be
	respected:
	  base value        — the item (Items.lua)
	  modifier          — the roll   (Rarity.MODIFIERS)
	  weight            — intrinsic per item TYPE (Config/Weight)
	  payload           — this dig's OWN random roll (Config/Payload)
	  value retained    — the decay clock, so the run home has a felt cost (§3.6)
	  clean / dirty     — the cleaning gate (§2 step 4)
	then sellMultiplier from rebirth and gamepasses, via StatResolver like everything else.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Crates = require(Shared.Config.Crates)
local Weight = require(Shared.Config.Weight)
local Payload = require(Shared.Config.Payload)
local Decay = require(Shared.Decay)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IdentifyService = require(script.Parent.IdentifyService)

local EconomyService = {}

local cashRemote: any = nil

--- The wallet's one broadcast point, matching the file's own "one place to look"
--- rule for MUTATING data.cash -- this is that rule's other half, for anyone who
--- needs to tell the client it changed. DebugService's /cash calls this too, since
--- it pokes data.cash directly the same way /gear pokes data.gear.
---
--- `source` rides along so the badge can tell a sale from background income -- only
--- "exhibit" (ExhibitService's passive deposits) means anything to it today.
function EconomyService.pushCash(player: Player, source: string?)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	cashRemote:FireClient(player, data.cash, source)
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

	-- Heavier items are worth more (Config/Weight.valueMult). Rides ON TOP of the
	-- authored baseValue exactly like mod.valueMult does — see Config/Items' header.
	--
	-- Payload is this SPECIFIC dig's own random roll (Config/Payload), separate from
	-- the item's intrinsic weight -- a 0.6x roll sells for 0.6x, a 2.5x "giga nuke"
	-- for 2.5x, same number that scaled its display size everywhere it showed up.
	local value = def.baseValue
		* mod.valueMult
		* Weight.valueMult(def.weight)
		* Payload.forUid(item.uid)
		* retained
		* stats.sellMultiplier
	if not clean then
		value *= Tuning.DIRTY_SELL_MULTIPLIER
	end

	-- Never zero. Even Slag sells for a token amount (PLAN §3.6) — a wasted run is
	-- never a FULLY wasted run, and that is the anti-frustration floor.
	return math.max(1, math.floor(value + 0.5)), clean
end

--- How far apart a bulk sale's "???" reveals land, in seconds. See sellAll.
local REVEAL_STAGGER = 1.2

--- Name a find sold blind, now or `delay` seconds from now. The index write is never
--- the part that waits -- only the banner does -- so a player who leaves mid-queue has
--- still learnt everything they sold.
local function revealSold(player: Player, item: any, delay: number)
	if item.crateId and Crates.has(item.crateId) then
		if delay <= 0 then
			IdentifyService.announceCrate(player, item.crateId, item.rarity)
		else
			task.delay(delay, function()
				if player.Parent then
					IdentifyService.announceCrate(player, item.crateId, item.rarity)
				end
			end)
		end
		return
	end
	local first, previous = IdentifyService.identify(player, item)
	if delay <= 0 then
		IdentifyService.announce(player, item, first, { previousBest = previous })
	else
		task.delay(delay, function()
			if player.Parent then
				IdentifyService.announce(player, item, first, { previousBest = previous })
			end
		end)
	end
end

--- The till itself, shared by SELL and both SELL ALLs: take the item out of `list`,
--- pay for it, and name it if it went blind. Does NOT push the wallet -- a bulk sale
--- pushes once at the end rather than once per item. Returns (value, clean, name).
local function takeSale(
	player: Player,
	data: any,
	item: any,
	list: any,
	index: number,
	stats: any,
	revealDelay: number
): (number, boolean, string)
	local value, clean = EconomyService.valueOf(item, stats)
	local def = Items.get(item.itemId)

	table.remove(list, index)
	data.cash += value

	-- SELLING A "???" IS HOW YOU FIND OUT WHAT IT WAS. An item still in its crust has no
	-- name on any surface (Services/IdentifyService) -- but the trader has to say what he
	-- just bought, and the moment he does the player knows, so the index has to know too.
	-- That is the whole shape of the gamble: 20% and an answer, or the hose and the full
	-- price. Idempotent for a clean item, which was identified at the tub already.
	--
	-- A DIRTY SUPPLY CRATE (DigService.unearth) sells as the nuke it was passing for --
	-- same 20% -- and the trader names the crate rather than its stand-in, which never
	-- reaches the index.
	local name = def.name
	if item.crateId and Crates.has(item.crateId) then
		name = Crates.get(item.crateId).name
		revealSold(player, item, revealDelay)
	elseif not clean then
		revealSold(player, item, revealDelay)
	end
	return value, clean, name
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

	local value, clean, name = takeSale(player, data, item, list, index, StatResolver.get(data), 0)
	EconomyService.pushCash(player)

	local note = if clean then "" else ` (dirty, {math.floor(Tuning.DIRTY_SELL_MULTIPLIER * 100)}%)`
	return true, `sold {name} for ${value}{note}`
end

--- The trader's SELL ALL CLEAN / SELL ALL ???. `which` is "clean" or "dirty", and
--- only the BAG is swept -- the Quarantine Locker is a shelf you chose to keep things
--- on, and a bulk button reaching into it would sell what the player filed away.
---
--- Every item goes through the same takeSale as a single SELL, so the price, the 20%
--- and the "???" reveal cannot drift between the two. The reveals are STAGGERED:
--- DetectorController's find banner shows one find at a time and the newest replaces
--- it, so five blind sales announced in one frame would show the player one name and
--- swallow four. The index learns all of them now; only the banners wait their turn.
function EconomyService.sellAll(player: Player, which: string): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	if which ~= "clean" and which ~= "dirty" then
		return false, "sell what?"
	end

	local stats = StatResolver.get(data)
	local total, count, reveals = 0, 0, 0
	-- Backwards, so removing an entry never skips the one after it.
	for index = #data.carry, 1, -1 do
		local item = data.carry[index]
		local _, clean = EconomyService.valueOf(item, stats)
		if clean ~= (which == "clean") then
			continue
		end
		local value, _, _ = takeSale(player, data, item, data.carry, index, stats, reveals * REVEAL_STAGGER)
		if not clean then
			reveals += 1
		end
		total += value
		count += 1
	end

	if count == 0 then
		return false, if which == "clean" then "nothing clean to sell" else "nothing crusted to sell"
	end
	EconomyService.pushCash(player)
	local noun = if count == 1 then "item" else "items"
	local note = if which == "clean" then "" else ` (dirty, {math.floor(Tuning.DIRTY_SELL_MULTIPLIER * 100)}%)`
	return true, `sold {count} {noun} for ${total}{note}`
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
function EconomyService.award(player: Player, amount: number, source: string?): boolean
	local data = DataService.data(player)
	if data == nil then
		return false
	end
	data.cash += math.max(0, math.floor(amount + 0.5))
	EconomyService.pushCash(player, source)
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
