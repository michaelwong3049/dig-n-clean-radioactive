--!strict
--[[
	ReforgeService.luau — the Reforge Station at Toxic Twilight (build/ReforgeStation).

	Pay cash, reroll one washed nuke's bomb damage and radius, with a rare chance of a
	new quality on top. Every number and the shape of the roll are Config/Reforge's;
	this file is the gatekeeper and the bookkeeper:

	  * WHERE: you are standing at a forge (StationKind = "reforge"), re-derived here
	    from StationService, never taken from the client.
	  * WHAT: one uid, yours, in the bag or the Quarantine Locker, washed, not Slagged,
	    not a crate, not on the tub right now.
	  * COST: Reforge.cost(value, reforges), paid whatever comes out, through
	    EconomyService.spend.

	KEEP OR REVERT. The rolled pair is held HERE (`pending`), not written to the record,
	until the player answers "reforgeKeep". Anything else -- walking off the station,
	reforging again, leaving the game -- drops it, which keeps the old pair. The cash
	and the reforge count are spent the moment the roll is made.

	A QUALITY IS WRITTEN AT ONCE. It is the rare jackpot (Reforge.QUALITY_CHANCE), not
	part of the stat pair, so REVERT does not take it back. It joins the copy's
	qualities best first (Merge.MODIFIER_RANK): the best is worn as `modifier`, the rest
	ride in `bonus`, the same shape a rare drop's stacked qualities have. A Cracked copy
	that rolls one loses the crack -- the forge mended it.

	THE ANVIL ANIMATES FOR EVERYONE NEARBY: the server bumps `ReforgeSeq` on the station
	model, and client/Controllers/ReforgeStationController plays the strike and sparks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Merge = require(Shared.Config.Merge)
local Rarity = require(Shared.Config.Rarity)
local Reforge = require(Shared.Config.Reforge)
local Bombing = require(Shared.Bombing)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local CarryService = require(script.Parent.CarryService)
local StationService = require(script.Parent.StationService)
local ExhibitService = require(script.Parent.ExhibitService)
local WashService = require(script.Parent.WashService)

local ReforgeService = {}

type Pending = { uid: string, dmg: number, rad: number }

local actionRemote: any = nil
local resultRemote: any = nil
local reforgeRemote: any = nil
local lastReforge: { [Player]: number } = {}
local pending: { [Player]: Pending } = {}
local rng = Random.new()

--- The record behind `uid`, or nil and why not.
local function find(player: Player, data: any, raw: any): (any?, any?, string?)
	if type(raw) ~= "string" or raw == "" then
		return nil, nil, "pick a nuke first"
	end
	local item, list = EconomyService.find(data, raw)
	if item == nil or list == nil then
		return nil, nil, "that nuke isn't in your bag or locker any more"
	end
	if item.crateId ~= nil then
		return nil, nil, "crates can't be reforged"
	end
	if not Contamination.isClean(item.patches or {}) then
		return nil, nil, "wash it first \u{2014} the forge only takes identified nukes"
	end
	if item.modifier == "Slagged" then
		return nil, nil, "slag can't be reforged"
	end
	if data.heldUid == raw and WashService.isWashing(player) then
		return nil, nil, "finish washing it first"
	end
	return item, list, nil
end

--- Add one quality the copy lacks, picked by Rarity.MODIFIERS weight. Returns its
--- name, or nil when the copy already has every one.
local function addQuality(item: any): string?
	local have = Rarity.qualities(item.modifier, item.bonus)
	local pool: { string } = {}
	local total = 0
	for _, name in Reforge.QUALITIES do
		if not table.find(have, name) then
			table.insert(pool, name)
			total += Rarity.MODIFIERS[name].weight
		end
	end
	if #pool == 0 or total <= 0 then
		return nil
	end
	local pick = rng:NextNumber() * total
	local chosen = pool[#pool]
	for _, name in pool do
		pick -= Rarity.MODIFIERS[name].weight
		if pick <= 0 then
			chosen = name
			break
		end
	end

	-- Best first; the forge mends a crack, so Cracked drops out of the list.
	local all: { string } = {}
	for _, name in have do
		if name ~= "Cracked" then
			table.insert(all, name)
		end
	end
	table.insert(all, chosen)
	table.sort(all, function(a, b)
		return Merge.modifierRank(a) < Merge.modifierRank(b)
	end)
	item.modifier = table.remove(all, 1)
	item.bonus = if #all > 0 then all else nil
	return chosen
end

local function animate(player: Player, itemId: string, outcome: string)
	local part = StationService.partOf(player)
	local machine = if part then part:FindFirstAncestorOfClass("Model") else nil
	if machine == nil then
		return
	end
	machine:SetAttribute("ReforgeItem", itemId)
	machine:SetAttribute("ReforgeOutcome", outcome)
	machine:SetAttribute("ReforgeUser", player.UserId)
	-- Last, so a client reading the others off this change sees this strike's values.
	machine:SetAttribute("ReforgeSeq", ((machine:GetAttribute("ReforgeSeq") :: number?) or 0) + 1)
end

--- One paid reforge. Returns (ok, message) for the station toast.
function ReforgeService.reforge(player: Player, uid: any): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	if StationService.kindOf(player) ~= "reforge" then
		return false, "that happens at the Reforge Station"
	end
	local now = os.clock()
	if now - (lastReforge[player] or -math.huge) < Reforge.COOLDOWN then
		return false, "the anvil is still hot"
	end
	local item, _, why = find(player, data, uid)
	if item == nil then
		return false, why or "can't reforge that"
	end

	local stats = StatResolver.get(data)
	local count = if type(item.reforges) == "number" then item.reforges else 0
	local price = Reforge.cost(EconomyService.valueOf(item, stats), count)
	local paid, spendMessage = EconomyService.spend(player, price)
	if not paid then
		return false, spendMessage
	end
	lastReforge[player] = now

	local oldDmg, oldRad = Bombing.forgeOf(item)
	local roll: Pending = {
		uid = item.uid,
		dmg = Reforge.rollStat(rng:NextNumber()),
		rad = Reforge.rollStat(rng:NextNumber()),
	}
	pending[player] = roll
	item.reforges = count + 1
	data.stats.reforges = (data.stats.reforges or 0) + 1

	local quality = if rng:NextNumber() < Reforge.QUALITY_CHANCE then addQuality(item) else nil
	if quality then
		ExhibitService.refreshLocker(player)
	end

	local name = Items.get(item.itemId).name
	animate(player, item.itemId, if quality then "quality" else "roll")
	reforgeRemote:FireClient(player, {
		uid = item.uid,
		old = { dmg = oldDmg, rad = oldRad },
		new = { dmg = roll.dmg, rad = roll.rad },
		quality = quality,
		item = CarryService.describe(item, stats),
	})

	if quality then
		return true, `{string.upper(quality)}! The forge made your {name} {quality} \u{2014} keep or revert the new stats`
	end
	return true, `Reforged your {name} \u{2014} keep the new stats or revert`
end

--- Answer the pending roll: `keep` writes it, anything else drops it.
function ReforgeService.settle(player: Player, uid: any, keep: boolean): (boolean, string)
	local roll = pending[player]
	pending[player] = nil
	if roll == nil or roll.uid ~= uid then
		return false, "nothing to keep \u{2014} reforge first"
	end
	if not keep then
		return true, "Reverted \u{2014} kept the old stats"
	end
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	local item = EconomyService.find(data, roll.uid)
	if item == nil then
		return false, "that nuke isn't in your bag or locker any more"
	end
	item.forge = { dmg = roll.dmg, rad = roll.rad }
	return true, `Kept! Damage {Reforge.percentText(roll.dmg)}, radius {Reforge.percentText(roll.rad)}`
end

function ReforgeService.init()
	actionRemote = Net.get("StationAction")
	resultRemote = Net.get("StationResult")
	reforgeRemote = Net.get("ReforgeResult")
end

function ReforgeService.start()
	actionRemote.OnServerEvent:Connect(function(player: Player, request: any)
		if type(request) ~= "table" then
			return
		end
		local ok, message
		if request.action == "reforge" then
			ok, message = ReforgeService.reforge(player, request.uid)
		elseif request.action == "reforgeKeep" then
			ok, message = ReforgeService.settle(player, request.uid, request.keep == true)
		else
			return
		end
		resultRemote:FireClient(player, message)
		if ok then
			print(`[reforge] {player.Name}: {message}`)
		end
	end)

	-- Walking off the forge with a roll unanswered keeps the old stats.
	StationService.onChanged(function(player: Player, kind: string?)
		if kind ~= "reforge" then
			pending[player] = nil
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastReforge[player] = nil
		pending[player] = nil
	end)
end

return ReforgeService
