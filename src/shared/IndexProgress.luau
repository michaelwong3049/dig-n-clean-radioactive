--!strict
--[[
	IndexProgress.luau — what the index knows about you, as pure functions both sides
	can run: how far through each stage you are, whether that has earned the stage's
	luck reward, and what a saved record weighs.

	THE SERVER OWNS THE RECORDS (IdentifyService writes `data.indexStats`); this file
	only reads them. It lives in Shared so the client's IndexController and the
	server's DigService agree about "complete" without a remote carrying the answer --
	both derive it from the same `discovered` set.

	ONE RECORD PER ITEM, KEYED BY ITS ID:
	  best   the biggest payload roll (Config/Payload) you have identified of it. Stored
	         as the MULTIPLIER, not kilograms: the kilograms are `weight * best`, so a
	         retune of an item's intrinsic weight moves its record with it instead of
	         leaving a number no dig can match any more. 0 = no roll on file (a find
	         from before records were kept, whose copy you no longer own).
	  count  how many of it you have identified.
	  first  os.time() of the first one. 0 = before records were kept.
	  new    identified and not yet looked at in the index (the NEW badge).
]]

local Config = script.Parent.Config
local Items = require(Config.Items)
local Weight = require(Config.Weight)
local Stages = require(Config.Stages)
local Tuning = require(Config.Tuning)

export type Entry = {
	best: number,
	count: number,
	first: number,
	new: boolean,
}

local IndexProgress = {}

-- stageId -> the items it stocks. A retired item (`stages = {}`) is in no list, so it
-- never counts against completion.
local byStage: { [number]: { Items.ItemDef } } = {}
for _, stage in Stages.DEFS do
	byStage[stage.id] = {}
end
for _, item in Items.DEFS do
	for _, stageId in item.stages do
		local list = byStage[stageId]
		if list then
			table.insert(list, item)
		end
	end
end

--- Every item a stage stocks. Shared, not copied: do not mutate it.
function IndexProgress.stageItems(stageId: number): { Items.ItemDef }
	return byStage[stageId] or {}
end

--- How many of a stage's items are in `discovered`, and how many it stocks.
function IndexProgress.stageCount(discovered: { [string]: boolean }, stageId: number): (number, number)
	local found, total = 0, 0
	for _, item in IndexProgress.stageItems(stageId) do
		total += 1
		if discovered[item.id] then
			found += 1
		end
	end
	return found, total
end

function IndexProgress.isComplete(discovered: { [string]: boolean }, stageId: number): boolean
	local found, total = IndexProgress.stageCount(discovered, stageId)
	return total > 0 and found == total
end

--- stageId -> the extra dig luck its completed index grants. Stages you have not
--- finished are absent, so `bonus[stageId] or 0` is the whole read.
function IndexProgress.stageLuck(discovered: { [string]: boolean }): { [number]: number }
	local bonus = {}
	for _, stage in Stages.DEFS do
		if IndexProgress.isComplete(discovered, stage.id) then
			bonus[stage.id] = Tuning.INDEX_COMPLETE_LUCK
		end
	end
	return bonus
end

--- A record's weight in kg, or nil when there is no roll on file.
function IndexProgress.bestKg(itemId: string, entry: Entry?): number?
	if entry == nil or type(entry.best) ~= "number" or entry.best <= 0 then
		return nil
	end
	return Weight.shownKg(Items.get(itemId).weight, entry.best)
end

return IndexProgress
