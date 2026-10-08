--!strict
--[[
	FurnaceService.luau — the Slag Furnace at Magma Hollow (build/SlagFurnace).

	Throw nukes in, fill the meter, roll prizes. Every number and the prize table are
	Config/Furnace's; this file is the gatekeeper and the bookkeeper:

	  * WHERE: you are standing at a furnace (StationKind = "furnace"), re-derived here
	    from StationService, never taken from the client.
	  * DUMP: the uids must be yours, in the bag or the Quarantine Locker, not crates,
	    not on the tub right now, and either washed or Slagged. Each one is removed for
	    good and adds Furnace.fillOf to `furnaceFill`; every full meter moves into
	    `furnaceRolls`.
	  * ROLL: spends one banked roll and grants the prize HERE, before the client's
	    reel has even started, so leaving mid-reel loses nothing.

	THE FURNACE FLARES FOR EVERYONE NEARBY: the server bumps `FurnaceSeq` on the model
	(with `FurnaceOutcome` "dump" / "roll" / the prize's tier), and
	client/Controllers/FurnaceStationController plays the mouth flaring and the sparks.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Crates = require(Shared.Config.Crates)
local Potions = require(Shared.Config.Potions)
local Furnace = require(Shared.Config.Furnace)
local Contamination = require(Shared.Contamination)
local Decay = require(Shared.Decay)
local StatResolver = require(Shared.StatResolver)
local Net = require(Shared.Net)
local Bag = require(Shared.Bag)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local CarryService = require(script.Parent.CarryService)
local StationService = require(script.Parent.StationService)
local ExhibitService = require(script.Parent.ExhibitService)
local WashService = require(script.Parent.WashService)
local IdentifyService = require(script.Parent.IdentifyService)
local PotionService = require(script.Parent.PotionService)
local CrateService = require(script.Parent.CrateService)
local LuckBoostService = require(script.Parent.LuckBoostService)
local CashBoostService = require(script.Parent.CashBoostService)

local FurnaceService = {}

local actionRemote: any = nil
local resultRemote: any = nil
local furnaceRemote: any = nil
local lastRoll: { [Player]: number } = {}
--- A jackpot nuke's "new find" announce, held until the reel lands: run by the
--- reel's SKIP (furnaceSkip) or the ROLL_SECONDS timer, whichever comes first.
local pendingAnnounce: { [Player]: () -> () } = {}
local rng = Random.new()

--- The jackpot pools, rarity -> item ids stocked on Furnace.JACKPOT_STAGES. Built once.
local jackpot: { [string]: { string } }? = nil
local function jackpotPool(rarity: string): { string }
	if jackpot == nil then
		local pools: { [string]: { string } } = {}
		local seen: { [string]: boolean } = {}
		for _, stageId in Furnace.JACKPOT_STAGES do
			for _, name in { "Legendary", "Mythic", "Anomaly" } do
				for _, def in Items.inStage(stageId, name) do
					if not seen[def.id] then
						seen[def.id] = true
						pools[name] = pools[name] or {}
						table.insert(pools[name], def.id)
					end
				end
			end
		end
		for _, list in pools do
			table.sort(list)
		end
		jackpot = pools
	end
	return (jackpot :: any)[rarity] or {}
end

local function animate(player: Player, outcome: string)
	local part = StationService.partOf(player)
	local machine = if part then part:FindFirstAncestorOfClass("Model") else nil
	if machine == nil then
		return
	end
	machine:SetAttribute("FurnaceOutcome", outcome)
	machine:SetAttribute("FurnaceUser", player.UserId)
	-- Last, so a client reading the others off this change sees this one's values.
	machine:SetAttribute("FurnaceSeq", ((machine:GetAttribute("FurnaceSeq") :: number?) or 0) + 1)
end

local function meterOf(data: any): (number, number)
	local fill = if type(data.furnaceFill) == "number" then data.furnaceFill else 0
	local rolls = if type(data.furnaceRolls) == "number" then data.furnaceRolls else 0
	return fill, rolls
end

--- Can this copy go in? nil when it can, else why not.
local function refusal(player: Player, data: any, item: any): string?
	if item.crateId ~= nil then
		return "crates can't go in the furnace"
	end
	if item.modifier ~= "Slagged" and not Contamination.isClean(item.patches or {}) then
		return "wash it first \u{2014} the furnace only takes identified nukes"
	end
	if data.heldUid == item.uid and WashService.isWashing(player) then
		return "finish washing it first"
	end
	if Bag.isHearted(item) then
		return Bag.HEART_REFUSAL
	end
	return nil
end

--- Burn these copies. Returns (ok, message) for the station toast.
function FurnaceService.dump(player: Player, uids: any): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	if StationService.kindOf(player) ~= "furnace" then
		return false, "that happens at the Slag Furnace"
	end
	if type(uids) ~= "table" then
		return false, "pick some nukes first"
	end

	local seen: { [string]: boolean } = {}
	local added, burned = 0, 0
	local why: string? = nil
	for index, uid in ipairs(uids) do
		if index > Furnace.MAX_DUMP then
			break
		end
		if type(uid) ~= "string" or seen[uid] then
			continue
		end
		seen[uid] = true
		local item, list, at = EconomyService.find(data, uid)
		if item == nil or list == nil or at == nil then
			continue
		end
		local no = refusal(player, data, item)
		if no then
			why = why or no
			continue
		end
		added += Furnace.fillOf(item)
		burned += 1
		table.remove(list, at)
		if data.heldUid == uid then
			data.heldUid = ""
		end
	end
	if burned == 0 then
		return false, why or "none of those are in your bag or locker"
	end

	local fill, rolls = meterOf(data)
	fill += added
	local banked = math.floor(fill / Furnace.FULL)
	fill -= banked * Furnace.FULL
	rolls += banked
	data.furnaceFill = fill
	data.furnaceRolls = rolls
	data.stats.furnaceBurned = (data.stats.furnaceBurned or 0) + burned
	ExhibitService.refreshLocker(player)

	animate(player, "dump")
	furnaceRemote:FireClient(player, {
		kind = "dump",
		added = added,
		burned = burned,
		banked = banked,
		fill = fill,
		rolls = rolls,
	})

	local noun = if burned == 1 then "nuke" else "nukes"
	if banked > 0 then
		return true, `Burned {burned} {noun} (+{added}%) \u{2014} {banked} roll{if banked == 1 then "" else "s"} banked!`
	end
	return true, `Burned {burned} {noun} (+{added}%)`
end

--- Hand over one prize. Returns its card for the reel: { id, name, tier, kind, ... }.
local function grant(player: Player, data: any, prize: Furnace.PrizeDef): any
	local card: any = { id = prize.id, name = prize.name, tier = prize.tier, kind = prize.kind }
	if prize.kind == "potion" then
		PotionService.give(player, data, prize.potion :: string, 1)
		card.potion = prize.potion
	elseif prize.kind == "potionPack" then
		local got: { string } = {}
		for _ = 1, prize.count or 3 do
			local id = Potions.roll(rng:NextNumber())
			PotionService.give(player, data, id, 1)
			table.insert(got, Potions.get(id).short)
		end
		card.detail = table.concat(got, " + ")
	elseif prize.kind == "crate" then
		CrateService.give(data, prize.crate :: string)
		card.crate = prize.crate
	elseif prize.kind == "cash" then
		local rate = ExhibitService.ratePerSecond(data)
		local amount = math.max(prize.floor or 0, math.floor(rate * 60 * (prize.minutes or 0)))
		EconomyService.award(player, amount, "furnace")
		card.amount = amount
	elseif prize.kind == "luckBoost" then
		LuckBoostService.grant(player, data, prize.seconds or 0)
	elseif prize.kind == "cashBoost" then
		CashBoostService.grant(player, data, prize.seconds or 0)
	elseif prize.kind == "nuke" then
		local pool = jackpotPool(prize.rarity :: string)
		local itemId = if #pool > 0 then pool[rng:NextInteger(1, #pool)] else nil
		if itemId == nil then
			-- No nuke of that rarity on the jackpot stages: pay a vault instead.
			warn(`[furnace] no {prize.rarity} nuke on stages {table.concat(Furnace.JACKPOT_STAGES, ",")}`)
			return grant(player, data, Furnace.get("cashVault"))
		end
		local def = Items.get(itemId)
		local carried = {
			uid = HttpService:GenerateGUID(false),
			itemId = itemId,
			rarity = def.rarity,
			modifier = "None",
			elapsed = 0,
			frozen = true,
			patches = {},
		}
		Decay.freeze(carried)
		table.insert(data.carry, carried)
		local first, previous = IdentifyService.identify(player, carried)
		local function announce()
			if pendingAnnounce[player] ~= announce then
				return
			end
			pendingAnnounce[player] = nil
			if player.Parent then
				IdentifyService.announce(player, carried, first, { staged = true, previousBest = previous })
			end
		end
		pendingAnnounce[player] = announce
		task.delay(Furnace.ROLL_SECONDS, announce)
		card.itemId = itemId
		card.uid = carried.uid
		card.name = def.name
		card.item = CarryService.describe(carried, StatResolver.get(data))
	end
	return card
end

--- A cosmetic card for the reel's filler: a weighted roll's prize, no grant.
local function fillerCard(): any
	local prize = Furnace.get(Furnace.roll(rng:NextNumber()))
	local card: any = { id = prize.id, name = prize.name, tier = prize.tier, kind = prize.kind }
	if prize.kind == "potion" then
		card.potion = prize.potion
	elseif prize.kind == "crate" then
		card.crate = prize.crate
	elseif prize.kind == "nuke" then
		local pool = jackpotPool(prize.rarity :: string)
		if #pool > 0 then
			local itemId = pool[rng:NextInteger(1, #pool)]
			card.itemId = itemId
			card.name = Items.get(itemId).name
		end
	end
	return card
end

--- The reel's SKIP landed it early. The prize was granted when the roll started, so
--- this only fires a held nuke announce now and lifts the cooldown (which exists to
--- cover the reel), so the next ROLL works straight away.
function FurnaceService.skip(player: Player)
	if lastRoll[player] == nil then
		return
	end
	lastRoll[player] = nil
	local announce = pendingAnnounce[player]
	if announce then
		announce()
	end
end

--- Spend one banked roll. Returns (ok, message) for the station toast.
function FurnaceService.roll(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	if StationService.kindOf(player) ~= "furnace" then
		return false, "that happens at the Slag Furnace"
	end
	local now = os.clock()
	if now - (lastRoll[player] or -math.huge) < Furnace.COOLDOWN then
		return false, "the furnace is still pouring"
	end
	local fill, rolls = meterOf(data)
	if rolls < 1 then
		return false, `fill the meter to {Furnace.FULL}% first`
	end
	lastRoll[player] = now
	data.furnaceRolls = rolls - 1
	data.stats.furnaceRolls = (data.stats.furnaceRolls or 0) + 1

	local prize = Furnace.get(Furnace.roll(rng:NextNumber()))
	local card = grant(player, data, prize)

	-- The reel: weighted filler (so what flashes past is honest to the odds), the
	-- prize at REEL_LAND, a short tail after it.
	local reel = table.create(Furnace.REEL_LAND + Furnace.REEL_TAIL)
	for i = 1, Furnace.REEL_LAND + Furnace.REEL_TAIL do
		reel[i] = if i == Furnace.REEL_LAND then card else fillerCard()
	end

	animate(player, card.tier)
	furnaceRemote:FireClient(player, {
		kind = "roll",
		reel = reel,
		land = Furnace.REEL_LAND,
		seconds = Furnace.ROLL_SECONDS,
		prize = card,
		fill = fill,
		rolls = data.furnaceRolls,
	})
	print(`[furnace] {player.Name} rolled {prize.id}`)
	return true, `Rolling\u{2026}`
end

function FurnaceService.init()
	actionRemote = Net.get("StationAction")
	resultRemote = Net.get("StationResult")
	furnaceRemote = Net.get("FurnaceResult")
end

function FurnaceService.start()
	actionRemote.OnServerEvent:Connect(function(player: Player, request: any)
		if type(request) ~= "table" then
			return
		end
		local ok, message
		if request.action == "furnaceDump" then
			ok, message = FurnaceService.dump(player, request.uids)
		elseif request.action == "furnaceRoll" then
			ok, message = FurnaceService.roll(player)
		elseif request.action == "furnaceSkip" then
			FurnaceService.skip(player)
			return
		else
			return
		end
		-- A roll's "Rolling..." is the reel's job; only refusals toast.
		if not ok or request.action ~= "furnaceRoll" then
			resultRemote:FireClient(player, message)
		end
		if ok then
			print(`[furnace] {player.Name}: {message}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		pendingAnnounce[player] = nil
	end)
end

-- A bad crate or potion id in Config/Furnace fails at boot, not mid-roll.
for _, prize in Furnace.PRIZES do
	if prize.kind == "crate" then
		assert(Crates.has(prize.crate), `Furnace: {prize.id} names unknown crate {prize.crate}`)
	elseif prize.kind == "potion" then
		assert(Potions.has(prize.potion), `Furnace: {prize.id} names unknown potion {prize.potion}`)
	end
end

return FurnaceService
