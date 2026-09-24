--!strict
--[[
	IdentifyService.lua — the moment a "???" becomes a thing with a name.

	WHAT YOU DIG UP IS A LUMP OF SLAG (Shared/ItemCrust). It goes in the bag as "???",
	it sits in your hand as a rock, and the ONE thing anybody knows about it is the
	rarity the detector read on the way in. Taking the crust off is what turns it into
	an item — that is the point of the wash bay now, and this file is the single place
	that moment is allowed to happen.

	THREE WAYS TO LEARN WHAT YOU HAVE, and all three come through here:

	  1. YOU CLEAN IT.        WashService, when the last patch pops. The intended one.
	  2. YOU SELL IT BLIND.   EconomyService, at 20% (Tuning.DIRTY_SELL_MULTIPLIER).
	                          The trader tells you what it was as he takes it — which is
	                          the gamble: cash now, or the hose and the full price.
	  3. IT NEEDED NO CLEAN.  DigService, for a Prewar Sealed pull. It came out of the
	                          ground in its packaging, so there was never a mystery.

	A SUPPLY CRATE CAN BE UNDER THE CRUST TOO (DigService.unearth): it rides in the bag
	as a "???" with a stand-in nuke's itemId, and the wash or a blind sale is where it
	turns out to be a crate. That goes out through `announceCrate`, which writes nothing
	-- the stand-in was never really dug, so it must never reach the index.

	WHY THIS IS NOT JUST A LINE IN EACH OF THOSE FILES. `data.discovered` is the index,
	and the index is a spoiler surface: it used to be written in `unearth`, which meant
	the catalogue tile for a Gold Ring lit up the instant one broke the surface, some
	minutes before the player was supposed to find out they had a Gold Ring. Moving the
	write to "you actually know what this is" is the whole fix, and it only stays fixed
	if there is one function to move it to.

	MARKING AND ANNOUNCING ARE SEPARATE ON PURPOSE. The wash bay hides every
	LayerCollector while you are in the first-person view (WashController), so the
	banner has to wait until the session has handed the screen back — but the profile
	write must NOT wait, or a player who disconnects during the reveal beat comes back
	holding a clean item their index has never heard of. `identify` writes; `announce`
	shows. The wash now calls them back to back and stages the reveal itself, inside the
	bay (client WashReveal), so it marks its announcement `staged` for the banner to skip.

	IT ALSO KEEPS THE INDEX'S RECORDS (`data.indexStats`, Shared/IndexProgress): the
	heaviest payload of each item you have identified, how many, and when the first one
	was. Same reason as the discovery write -- a record is set by the moment you learn
	what you had, so it lives with that moment. `identify` hands back the old best when
	a find beats it, and the callers pass that on as `previousBest` for the NEW HEAVIEST
	callout. Saves from before records were kept get theirs filled in on load from
	whatever clean copies the player still owns (backfill below).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Items = require(Shared.Config.Items)
local Crates = require(Shared.Config.Crates)
local Payload = require(Shared.Config.Payload)
local Contamination = require(Shared.Contamination)
local IndexProgress = require(Shared.IndexProgress)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)

local IdentifyService = {}

local identifiedRemote: any = nil
local indexRemote: any = nil
local seenRemote: any = nil

-- UserId -> IndexProgress.stageLuck of their discovered set. DigService reads it on
-- every roll, so it is worked out when the set changes (load, a first find) rather
-- than per read. Keyed by UserId because that is what DigService's rollFor holds.
local stageLuckCache: { [number]: { [number]: number } } = {}
local NO_LUCK: { [number]: number } = table.freeze({})

local function copyEntry(entry: IndexProgress.Entry?): IndexProgress.Entry?
	if entry == nil then
		return nil
	end
	return { best = entry.best, count = entry.count, first = entry.first, new = entry.new }
end

--- Write it into the index. Returns whether this was the FIRST of its kind, so the
--- announcement can say so — a first find is the only reason to look at the banner
--- twice — and, when this one out-weighs the heaviest already on file, that old
--- record in kg (never on a first find: there was nothing to beat).
function IdentifyService.identify(player: Player, item: any): (boolean, number?)
	local data = DataService.data(player)
	if data == nil or item == nil or item.itemId == nil then
		return false, nil
	end

	local itemId = item.itemId
	local first = data.discovered[itemId] ~= true
	data.discovered[itemId] = true

	local entry: IndexProgress.Entry = data.indexStats[itemId]
	if entry == nil then
		entry = { best = 0, count = 0, first = 0, new = false }
		data.indexStats[itemId] = entry
	end
	entry.count += 1
	if first then
		entry.first = os.time()
		entry.new = true
		stageLuckCache[player.UserId] = IndexProgress.stageLuck(data.discovered)
	end

	local previous: number? = nil
	if type(item.uid) == "string" then
		local mult = Payload.forUid(item.uid)
		if mult > entry.best then
			if entry.best > 0 and not first then
				previous = IndexProgress.bestKg(itemId, entry)
			end
			entry.best = mult
		end
	end

	return first, previous
end

--- Put it on screen. Same shape as the Unearthed payload, because it lands in the same
--- banner (client DetectorController) — one renderer, two moments.
---
--- `weight` is THIS dig's weight (catalogue weight x its payload roll), the number the
--- index records, not the catalogue's typical one. `index` is the item's record after
--- the write, which is how the index GUI stays current without a second remote.
---
--- `extra` rides along on top, for a caller with more to say than the banner does: the
--- wash bay stages its own reveal on the real model (client WashReveal) and passes
--- `staged = true` so the banner stands down, plus the `value` it counts up to;
--- `previousBest` (from `identify`) turns on the NEW HEAVIEST callout.
function IdentifyService.announce(player: Player, item: any, firstFind: boolean, extra: { [string]: any }?)
	if identifiedRemote == nil or item == nil then
		return
	end
	local def = Items.get(item.itemId)
	local data = DataService.data(player)
	local mult = if type(item.uid) == "string" then Payload.forUid(item.uid) else 1
	local payload: { [string]: any } = {
		itemId = def.id,
		name = def.name,
		flavor = def.flavor,
		rarity = item.rarity,
		modifier = item.modifier,
		weight = def.weight * mult,
		firstFind = firstFind,
		index = if data then copyEntry(data.indexStats[def.id]) else nil,
	}
	for key, value in extra or {} do
		payload[key] = value
	end
	identifiedRemote:FireClient(player, payload)
end

--- "It was a supply crate." The ItemIdentified banner for a dirty crate coming clean
--- (WashService) or being sold blind (EconomyService). No itemId and no `index`, so
--- the index never hears of the stand-in; `crate` is what tells the client this reveal
--- is a crate. `extra` rides along as in `announce` (`staged` for the wash bay).
function IdentifyService.announceCrate(player: Player, crateId: string, rarity: string, extra: { [string]: any }?)
	if identifiedRemote == nil or not Crates.has(crateId) then
		return
	end
	local crate = Crates.get(crateId)
	local payload: { [string]: any } = {
		crate = crateId,
		name = crate.name,
		flavor = crate.flavor,
		rarity = rarity,
		modifier = "None",
		firstFind = false,
	}
	for key, value in extra or {} do
		payload[key] = value
	end
	identifiedRemote:FireClient(player, payload)
end

--- Both halves, for the callers with nothing to wait for.
function IdentifyService.reveal(player: Player, item: any)
	local first, previous = IdentifyService.identify(player, item)
	IdentifyService.announce(player, item, first, { previousBest = previous })
end

--- A copy of one item's record, for a payload that is not an announcement (a sealed
--- find rides on Unearthed instead).
function IdentifyService.entry(player: Player, itemId: string): IndexProgress.Entry?
	local data = DataService.data(player)
	return if data then copyEntry(data.indexStats[itemId]) else nil
end

--- stageId -> extra dig luck from completed stages. Empty (never nil) for anyone not
--- loaded yet, so DigService can index it unconditionally.
function IdentifyService.stageLuck(userId: number): { [number]: number }
	return stageLuckCache[userId] or NO_LUCK
end

--- FILL IN RECORDS FOR FINDS FROM BEFORE THEY WERE KEPT. Every discovered item gets an
--- entry; the heaviest and the count come from the clean copies still owned (bag,
--- locker, stands), since those uids still roll their payload. Anything already sold
--- is gone for good, so an item with no owned copy keeps `best = 0` ("—" in the index)
--- until the next one is identified, and counts as found once. `first` stays 0
--- (unknown), and none of it is NEW: the player has seen all of these before.
local function backfill(data: any)
	local fresh: { [string]: IndexProgress.Entry } = {}
	for itemId in data.discovered do
		if data.indexStats[itemId] == nil and Items.has(itemId) then
			local entry = { best = 0, count = 0, first = 0, new = false }
			data.indexStats[itemId] = entry
			fresh[itemId] = entry
		end
	end
	if next(fresh) == nil then
		return
	end

	local function consider(record: any)
		if type(record) ~= "table" or type(record.uid) ~= "string" or type(record.itemId) ~= "string" then
			return
		end
		local entry = fresh[record.itemId]
		if entry == nil or not Contamination.isClean(record.patches or {}) then
			return
		end
		entry.count += 1
		entry.best = math.max(entry.best, Payload.forUid(record.uid))
	end
	for _, record in data.carry do
		consider(record)
	end
	for _, record in data.locker do
		consider(record)
	end
	for _, record in data.exhibit.pedestals do
		consider(record)
	end

	for _, entry in fresh do
		entry.count = math.max(entry.count, 1)
	end
end

function IdentifyService.init()
	identifiedRemote = Net.get("ItemIdentified")
	indexRemote = Net.get("IndexState")
	seenRemote = Net.get("IndexSeen")
end

function IdentifyService.start()
	-- The index GUI's one and only snapshot (moved here from DigService with the
	-- records it now carries). Everything identified AFTER this arrives incrementally,
	-- on the `index` record each announcement carries.
	DataService.onLoaded(function(player, data)
		backfill(data)
		stageLuckCache[player.UserId] = IndexProgress.stageLuck(data.discovered)
		indexRemote:FireClient(player, { discovered = data.discovered, stats = data.indexStats })
	end)

	-- The NEW badge comes off when the player opens the entry. Only ever clears a flag
	-- this service set, so a made-up id finds no entry and does nothing.
	seenRemote.OnServerEvent:Connect(function(player: Player, itemId: any)
		if type(itemId) ~= "string" then
			return
		end
		local data = DataService.data(player)
		local entry = if data then data.indexStats[itemId] else nil
		if type(entry) == "table" then
			entry.new = false
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		stageLuckCache[player.UserId] = nil
	end)
end

return IdentifyService
