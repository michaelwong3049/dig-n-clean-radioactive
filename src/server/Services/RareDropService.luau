--!strict
--[[
	RareDropService.luau — the announced drop's clock (Config/RareDrop).

	Quiet for GAP_MIN..MAX seconds, then one guaranteed Epic-or-better nuke goes into a
	random dig stage and every client is told where, then quiet again -- measured from
	the END, like the Violet Aurora, so a drop that sat unclaimed for its full lifetime
	never shortens the gap after it.

	THIS FILE DECIDES WHAT AND WHERE; DigService OWNS THE SIGNAL. Planting, the fixed
	identity, the always-lit aura and the first-to-dig-it rule all live in the dig code
	(DigService.plantRareDrop): the drop is an ordinary signal, so the lock, the pull,
	the fuse and unearth() are the same code every other dig runs. "Whoever gets there
	first" is simply whoever finishes the haul first -- unearth removes the signal and
	anyone else on it loses their lump, exactly as with two players on any nuke.

	It ends one of three ways, each published as OUTCOME_ATTR for the closing banner:
	  claimed  somebody dug it up (DigService.onRareDropGone, with the player)
	  blown    its pull fuse went off (onRareDropGone, no player)
	  sunk     LIFETIME ran out. Not while somebody is locked on to it -- the sink waits
	           for them (DigService.sinkRareDrop refuses), so it is never snatched out
	           from under a magnet; the banner's clock just sits at 0:00 meanwhile.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Stages = require(Shared.Config.Stages)
local LuckBoost = require(Shared.Config.LuckBoost)
local RareDrop = require(Shared.Config.RareDrop)
local Ticker = require(Shared.Util.Ticker)

local DigService = require(script.Parent.DigService)

local RareDropService = {}

local rng = Random.new()

-- The live drop, if any. `endsAt` mirrors RareDrop.ENDS_ATTR.
local liveUid: string? = nil
local endsAt = 0
local nextAt = 0

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function scheduleNext(from: number)
	nextAt = from + rng:NextInteger(RareDrop.GAP_MIN, RareDrop.GAP_MAX)
end

--- The server's luck boost right now: the Violet Aurora's multiplier, or 1.
local function serverBoost(): number
	local ends = ReplicatedStorage:GetAttribute(LuckBoost.EVENT_ATTR)
	return if type(ends) == "number" and ends > now() then LuckBoost.MULT else 1
end

--- An item of `rarity` stocked in `stageId`, stepping DOWN a rung while the stage has
--- none (Config/RareDrop): Stage 1's "Mythic" drop is its best Legendary.
local function pickItem(stageId: number, rarity: string): string?
	local order = Rarity.get(rarity).order
	for o = order, 1, -1 do
		local pool = Items.inStage(stageId, Rarity.ORDER[o])
		if #pool > 0 then
			return pool[rng:NextInteger(1, #pool)].id
		end
	end
	return nil
end

local function finish(outcome: string)
	liveUid = nil
	endsAt = 0
	local t = now()
	ReplicatedStorage:SetAttribute(RareDrop.ENDS_ATTR, nil)
	ReplicatedStorage:SetAttribute(RareDrop.OUTCOME_ATTR, outcome)
	ReplicatedStorage:SetAttribute(RareDrop.ENDED_AT_ATTR, t)
	scheduleNext(t)
	print(`[raredrop] ended ({outcome}); next in {math.floor(nextAt - t)}s`)
end

--- Drop one now. `stageId` / `rarity` force the pick (for /raredrop); otherwise a
--- random dig stage and a RareDrop.rollRarity at the server's luck. Replaces a live
--- one. Returns a line saying what happened.
function RareDropService.startDrop(stageId: number?, rarity: string?): string
	local stages = DigService.digStages()
	if #stages == 0 then
		scheduleNext(now())
		return "no dig stage has signals yet"
	end
	if stageId and not table.find(stages, stageId) then
		return `stage {stageId} is not a dig stage (dig stages: {table.concat(stages, ", ")})`
	end
	if liveUid then
		if not DigService.sinkRareDrop(liveUid) then
			return "a drop is live and someone is locked on to it"
		end
		liveUid = nil
	end
	local stage = stageId or stages[rng:NextInteger(1, #stages)]
	local rolled = rarity or RareDrop.rollRarity(serverBoost(), rng:NextNumber())
	local itemId = pickItem(stage, rolled)
	if itemId == nil then
		scheduleNext(now())
		return `stage {stage} stocks no items`
	end

	local uid = DigService.plantRareDrop(stage, itemId)
	if uid == nil then
		-- No open spot this time (crater rims). Try again shortly, not in 8 minutes.
		nextAt = now() + 5
		return `no open spot in stage {stage}; retrying`
	end

	local buried = Items.get(itemId).rarity
	liveUid = uid
	endsAt = now() + RareDrop.LIFETIME
	ReplicatedStorage:SetAttribute(RareDrop.STAGE_ATTR, stage)
	ReplicatedStorage:SetAttribute(RareDrop.RARITY_ATTR, buried)
	ReplicatedStorage:SetAttribute(RareDrop.ENDS_ATTR, endsAt)
	local line = `{buried} drop ({itemId}) in stage {stage} {Stages.get(stage).name}, {RareDrop.LIFETIME}s`
	print(`[raredrop] {line}`)
	return line
end

--- Sink the live drop now (for /raredrop stop). Honours a locked-on digger.
function RareDropService.stopDrop(): boolean
	if liveUid and DigService.sinkRareDrop(liveUid) then
		finish("sunk")
		return true
	end
	return false
end

--- Seconds until the next drop, or 0 while one is live.
function RareDropService.secondsToNext(): number
	return if liveUid then 0 else math.max(0, nextAt - now())
end

--- The live drop's position, for /raredrop where. Server-side only.
function RareDropService.livePosition(): Vector3?
	return if liveUid then DigService.rareDropPosition(liveUid) else nil
end

local function step()
	local t = now()
	if liveUid then
		if t >= endsAt and DigService.sinkRareDrop(liveUid) then
			finish("sunk")
		end
	elseif t >= nextAt then
		RareDropService.startDrop()
	end
end

function RareDropService.start()
	scheduleNext(now())
	DigService.onRareDropGone(function(uid, claimer)
		if uid ~= liveUid then
			return
		end
		finish(if claimer then `claimed:{claimer.DisplayName}` else "blown")
	end)
	Ticker.every(Tuning.TICK_RATE, step, "RareDropService")
end

return RareDropService
