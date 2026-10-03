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
	then sellMultiplier from rebirth, gamepasses and completed index stages
	(Tuning.INDEX_COMPLETE_CASH), via StatResolver like everything else.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Crates = require(Shared.Config.Crates)
local Weight = require(Shared.Config.Weight)
local Payload = require(Shared.Config.Payload)
local Merge = require(Shared.Config.Merge)
local ShopProducts = require(Shared.Config.ShopProducts)
local Decay = require(Shared.Decay)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local IdentifyService = require(script.Parent.IdentifyService)
local SfxService = require(script.Parent.SfxService)
local ProductService = require(script.Parent.ProductService)

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
	local clean = Contamination.isClean(item.patches or {})
	local retained = Decay.valueRetained(item, stats.fuseMult)

	-- Heavier items are worth more (Config/Weight.valueMult). Rides ON TOP of the
	-- authored baseValue exactly like the quality valueMult does — see Config/Items' header.
	--
	-- Payload is this SPECIFIC dig's own random roll (Config/Payload), separate from
	-- the item's intrinsic weight -- a 0.6x roll sells for 0.6x, a 2.5x "giga nuke"
	-- for 2.5x, same number that scaled its display size everywhere it showed up.
	--
	-- And the Merge Reactor's stars (Config/Merge), x1.5 each, stored on the copy.
	local value = def.baseValue
		* Rarity.valueMult(item.modifier, item.bonus) -- every quality, stacked ones too
		* Weight.valueMult(def.weight)
		* Payload.forUid(item.uid)
		* Merge.valueMult(Merge.levelOf(item))
		* retained
		* stats.sellMultiplier
	if clean then
		value *= Tuning.CLEAN_SELL_MULTIPLIER
	else
		value *= Tuning.DIRTY_SELL_MULTIPLIER
	end

	-- Never zero. Even Slag sells for a token amount (PLAN §3.6) — a wasted run is
	-- never a FULLY wasted run, and that is the anti-frustration floor.
	return math.max(1, math.floor(value + 0.5)), clean
end

--- Name a find sold blind: write it into the index and tell the client, now. The
--- client shows no banner for a sale (DetectorController); the remote is how the index
--- GUI learns what was just sold, so it is never held back -- a bulk sale used to
--- stagger these 1.2 s apart for the old banner, which left the index stale for
--- seconds after a big SELL ALL ???.
local function revealSold(player: Player, item: any)
	if item.crateId and Crates.has(item.crateId) then
		IdentifyService.announceCrate(player, item.crateId, item.rarity)
		return
	end
	IdentifyService.reveal(player, item)
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
	stats: any
): (number, boolean, string)
	local value, clean = EconomyService.valueOf(item, stats)
	local def = Items.get(item.itemId)

	table.remove(list, index)
	data.cash += value
	data.cashEarned = (data.cashEarned or 0) + value

	-- SELLING A "???" IS HOW YOU FIND OUT WHAT IT WAS. An item still in its crust has no
	-- name on any surface (Services/IdentifyService) -- but the trader has to say what he
	-- just bought, and the moment he does the player knows, so the index has to know too.
	-- That is the whole shape of the gamble: 12% and an answer, or the hose and the full
	-- price. Idempotent for a clean item, which was identified at the tub already.
	--
	-- A DIRTY SUPPLY CRATE (DigService.unearth) sells as the nuke it was passing for --
	-- same 12% -- and the trader names the crate rather than its stand-in, which never
	-- reaches the index.
	local name = def.name
	if item.crateId and Crates.has(item.crateId) then
		name = Crates.get(item.crateId).name
		revealSold(player, item)
	elseif not clean then
		revealSold(player, item)
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

	local value, clean, name = takeSale(player, data, item, list, index, StatResolver.get(data))
	EconomyService.pushCash(player, "sell")

	local note = if clean then "" else ` (dirty, {math.floor(Tuning.DIRTY_SELL_MULTIPLIER * 100)}%)`
	return true, `sold {name} for ${value}{note}`
end

--- The trader's bulk sales. Only the BAG is swept -- the Quarantine Locker is a shelf
--- you chose to keep things on, and a bulk button reaching into it would sell what the
--- player filed away.
---
--- Every item goes through the same takeSale as a single SELL, so the price, the 12%
--- and the "???" reveal cannot drift between the two.
---
--- `wants(item, clean)` picks what goes. Returns the count, the total and how many of
--- them went blind.
local function sweepBag(player: Player, data: any, wants: (item: any, clean: boolean) -> boolean): (number, number, number)
	local stats = StatResolver.get(data)
	local total, count, reveals = 0, 0, 0
	-- Backwards, so removing an entry never skips the one after it.
	for index = #data.carry, 1, -1 do
		local item = data.carry[index]
		local _, clean = EconomyService.valueOf(item, stats)
		if not wants(item, clean) then
			continue
		end
		local value, _, _ = takeSale(player, data, item, data.carry, index, stats)
		if not clean then
			reveals += 1
		end
		total += value
		count += 1
	end
	if count > 0 then
		EconomyService.pushCash(player, "sellAll")
	end
	return count, total, reveals
end

local function soldMessage(count: number, total: number, blind: number): string
	local noun = if count == 1 then "item" else "items"
	local note = if blind == 0
		then ""
		elseif blind == count then ` (dirty, {math.floor(Tuning.DIRTY_SELL_MULTIPLIER * 100)}%)`
		else ` ({blind} dirty, {math.floor(Tuning.DIRTY_SELL_MULTIPLIER * 100)}%)`
	return `sold {count} {noun} for ${total}{note}`
end

--- SELL ALL CLEAN / SELL ALL ???, by kind. `which` is "clean" or "dirty".
function EconomyService.sellAll(player: Player, which: string): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	if which ~= "clean" and which ~= "dirty" then
		return false, "sell what?"
	end

	local wantClean = which == "clean"
	local count, total, blind = sweepBag(player, data, function(_, clean)
		return clean == wantClean
	end)
	if count == 0 then
		return false, if wantClean then "nothing clean to sell" else "nothing crusted to sell"
	end
	return true, soldMessage(count, total, blind)
end

--- The trader's receipt: sell exactly these bag items. The client says which uids it
--- ticked; anything not in the bag (sold already, stored, made up) is simply skipped.
--- Capped at MAX_RECEIPT uids so a junk request cannot make the server build a huge set.
local MAX_RECEIPT = 200
function EconomyService.sellMany(player: Player, uids: { any }): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local wanted: { [string]: boolean } = {}
	for index, uid in ipairs(uids) do
		if index > MAX_RECEIPT then
			break
		end
		if type(uid) == "string" then
			wanted[uid] = true
		end
	end

	local count, total, blind = sweepBag(player, data, function(item, _)
		return wanted[item.uid] == true
	end)
	if count == 0 then
		return false, "nothing on the receipt is in your bag"
	end
	return true, soldMessage(count, total, blind)
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
		SfxService.play(player, "denied")
		return false, `you need ${price - data.cash} more`
	end

	data.cash -= price
	EconomyService.pushCash(player, "spend")
	return true, `paid ${price}`
end

--- The counterpart, so refunds and payouts do not open-code the field either.
function EconomyService.award(player: Player, amount: number, source: string?): boolean
	local data = DataService.data(player)
	if data == nil then
		return false
	end
	local paid = math.max(0, math.floor(amount + 0.5))
	data.cash += paid
	data.cashEarned = (data.cashEarned or 0) + paid
	EconomyService.pushCash(player, source)
	return true
end

function EconomyService.init()
	cashRemote = Net.get("CashState")
	-- The Shop's Robux cash packs (Config/ShopProducts). Registered in init so no
	-- receipt can land first; award only mutates `data` and fires the cash badge.
	for _, pack in ShopProducts.CASH do
		ProductService.register(pack.id, function(player, _data)
			EconomyService.award(player, pack.amount, "robux")
		end)
	end
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
