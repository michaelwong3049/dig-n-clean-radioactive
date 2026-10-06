--!strict
--[[
	MergeService.luau — the Merge Reactor at Toxic Twilight (build/MergeReactor).

	Three copies of one nuke go in, one comes out. Every number and the roll itself are
	Config/Merge's; this file is the gatekeeper and the bookkeeper:

	  * WHERE: you are standing at a reactor (StationKind = "merge"), re-derived here
	    from StationService, never taken from the client. Reaching Toxic Twilight on
	    foot is the unlock -- the reactor only stands there.
	  * WHAT: three different uids, all yours, in the bag or the Quarantine Locker, all
	    the same itemId, all washed (identified), none Slagged, none on the tub right now
	    and not already at Merge.MAX_LEVEL.
	  * COST: Merge.fee (less the Reactor mastery), through EconomyService.spend.

	EVERY MERGE SUCCEEDS (2026-10-06): +1 merge star, or +2 on a luck crit. The result
	is written into the best copy's own record, in place, so it stays in the list (bag
	or locker) and the slot it was in, and the other two are removed. That record takes
	Merge.result: the biggest payload's uid (Config/Payload derives size from uid), the
	best-ranked modifier (Merge.MODIFIER_RANK) and the new merge level.

	THE MACHINE ANIMATES FOR EVERYONE NEARBY. The server does not move a part: it bumps
	`MergeSeq` on the reactor model and writes what went in and what came out beside
	it, and client/Controllers/MergeReactorController plays the drop, the charge and
	the lift off those attributes -- the StationMotion split.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Merge = require(Shared.Config.Merge)
local Contamination = require(Shared.Contamination)
local Decay = require(Shared.Decay)
local StatResolver = require(Shared.StatResolver)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local CarryService = require(script.Parent.CarryService)
local StationService = require(script.Parent.StationService)
local ExhibitService = require(script.Parent.ExhibitService)
local WashService = require(script.Parent.WashService)

local MergeService = {}

--- One merge per player per this many seconds: about as long as the machine takes
--- to play one, so a double-click cannot queue a second fee behind the first.
local COOLDOWN = 2.5

local actionRemote: any = nil
local resultRemote: any = nil
local mergeRemote: any = nil
local lastMerge: { [Player]: number } = {}
local rng = Random.new()

type Input = { item: any, list: any }

--- The three records behind `uids`, or nil and why not.
local function gather(player: Player, data: any, uids: any): ({ Input }?, string?)
	if type(uids) ~= "table" or #uids ~= Merge.INPUTS then
		return nil, `pick {Merge.INPUTS} copies of one nuke`
	end
	local seen: { [string]: boolean } = {}
	local inputs: { Input } = {}
	local itemId: string? = nil
	for _, raw in uids do
		local uid = tostring(raw)
		if seen[uid] then
			return nil, `pick {Merge.INPUTS} different copies`
		end
		seen[uid] = true
		local item, list = EconomyService.find(data, uid)
		if item == nil or list == nil then
			return nil, "one of those isn't in your bag or locker any more"
		end
		if not Contamination.isClean(item.patches or {}) then
			return nil, "wash it first \u{2014} the reactor only takes identified nukes"
		end
		if item.modifier == "Slagged" then
			return nil, "slag can't be merged"
		end
		if data.heldUid == uid and WashService.isWashing(player) then
			return nil, "finish washing it first"
		end
		if itemId ~= nil and item.itemId ~= itemId then
			return nil, "all three have to be the same nuke"
		end
		itemId = item.itemId
		table.insert(inputs, { item = item, list = list })
	end
	return inputs, nil
end

local function removeUid(list: any, uid: string)
	for index = #list, 1, -1 do
		if list[index].uid == uid then
			table.remove(list, index)
			return
		end
	end
end

--- Tell every client near this reactor to play one merge.
local function animate(player: Player, outcome: string, itemId: string, modifier: string, uid: string, level: number)
	local part = StationService.partOf(player)
	local machine = if part then part:FindFirstAncestorOfClass("Model") else nil
	if machine == nil then
		return
	end
	machine:SetAttribute("MergeItem", itemId)
	machine:SetAttribute("MergeModifier", modifier)
	machine:SetAttribute("MergeUid", uid)
	machine:SetAttribute("MergeOutcome", outcome)
	machine:SetAttribute("MergeLevel", level)
	machine:SetAttribute("MergeUser", player.UserId)
	-- Last, so a client reading the others off this change sees this merge's values.
	machine:SetAttribute("MergeSeq", ((machine:GetAttribute("MergeSeq") :: number?) or 0) + 1)
end

--- One merge. Returns (ok, message) for the station toast.
function MergeService.merge(player: Player, uids: any): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	if StationService.kindOf(player) ~= "merge" then
		return false, "that happens at the Merge Reactor"
	end
	local now = os.clock()
	if now - (lastMerge[player] or -math.huge) < COOLDOWN then
		return false, "the reactor is still cooling down"
	end

	local inputs, why = gather(player, data, uids)
	if inputs == nil then
		return false, why or "can't merge those"
	end
	local itemId = inputs[1].item.itemId :: string
	local name = Items.get(itemId).name

	local from = 0
	for _, input in inputs do
		from = math.max(from, Merge.levelOf(input.item))
	end
	local stats = StatResolver.get(data)
	local odds = Merge.odds(from, stats.luckMultiplier)
	if odds == nil then
		return false, `that {name} is already at max merge stars`
	end

	local paid, spendMessage = EconomyService.spend(player, Merge.fee(itemId, from, stats.mergeFeeMult))
	if not paid then
		return false, spendMessage
	end
	lastMerge[player] = now

	-- The record that carries the result: the copy worth most as it stands, so it keeps
	-- its list (bag or locker) and its slot.
	local best = inputs[1]
	local bestValue = -math.huge
	for _, input in inputs do
		local value = EconomyService.valueOf(input.item, stats)
		if value > bestValue then
			best, bestValue = input, value
		end
	end
	local keep = best.item
	local inputUids: { [string]: boolean } = {}
	local records: { any } = {}
	for _, input in inputs do
		inputUids[input.item.uid] = true
		table.insert(records, input.item)
	end
	local held = inputUids[data.heldUid] == true

	local gain = Merge.gain(odds, rng:NextNumber())
	-- Best of all three: the biggest size roll's uid, the best modifier, every stacked quality.
	local result = Merge.result(records, gain)
	for _, input in inputs do
		if input ~= best then
			removeUid(input.list, input.item.uid)
		end
	end
	keep.uid = result.uid
	keep.modifier = result.modifier
	keep.bonus = result.bonus
	keep.merge = result.level
	keep.patches = {}
	Decay.freeze(keep)
	-- The Reactor mastery's counter (Config/Masteries).
	data.stats.merges = (data.stats.merges or 0) + 1

	-- Whatever you were holding went into the machine; the result comes back to your
	-- hands if it lives in the bag.
	if held then
		data.heldUid = if best.list == data.carry then keep.uid else ""
	end
	ExhibitService.refreshLocker(player)

	local outcome = if gain >= 2 then "crit" else "success"
	animate(player, outcome, itemId, keep.modifier or "None", keep.uid, Merge.levelOf(keep))
	mergeRemote:FireClient(player, {
		outcome = outcome,
		from = from,
		to = Merge.levelOf(keep),
		item = CarryService.describe(keep, stats),
	})

	local stars = Merge.text(Merge.levelOf(keep))
	if outcome == "crit" then
		return true, `CRITICAL MERGE! {name} jumped to {stars}`
	end
	return true, `Merged! {name} is now {stars}`
end

function MergeService.init()
	actionRemote = Net.get("StationAction")
	resultRemote = Net.get("StationResult")
	mergeRemote = Net.get("MergeResult")
end

function MergeService.start()
	actionRemote.OnServerEvent:Connect(function(player: Player, request: any)
		if type(request) ~= "table" or request.action ~= "merge" then
			return
		end
		local ok, message = MergeService.merge(player, request.uids)
		resultRemote:FireClient(player, message)
		if ok then
			print(`[merge] {player.Name}: {message}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastMerge[player] = nil
	end)
end

return MergeService
