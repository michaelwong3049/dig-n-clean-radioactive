--!strict
--[[
	DeconService.lua — base camp: the decon station and the trader.

	TWO OBJECTS, NOT ONE, and PLAN §2 is right to insist. The decon station is what
	stops the decay clock; the trader is only a till. Keeping them apart means "I am
	safe" and "my loot is safe" stay two different problems.

	DOCKING IS THE WIN CONDITION (PLAN §3.6). Walking into the decon station's radius
	freezes every carried item at whatever condition it arrived in, permanently. Cleaning
	it afterwards is unhurried — the run home was the challenge, and turning "clean
	your backlog before it rots" into a second chore would sour a mechanic that works
	because it is short and sharp. So the freeze is generous and one-way.

	THE POTENCY GATE is the other half. A patch harder than your cleaner never comes
	off. The item is not destroyed and not lost — it can be racked in the Quarantine
	Locker as a labelled reminder of exactly which tool you need, or dirty-sold at 20%.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Items = require(Shared.Config.Items)
local Gear = require(Shared.Config.Gear)
local Decay = require(Shared.Decay)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local CarryService = require(script.Parent.CarryService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)
local ShopService = require(script.Parent.ShopService)
local ExhibitService = require(script.Parent.ExhibitService)

local DeconService = {}

local XP_PER_HARDNESS = 5

type Scrub = { uid: string, elapsed: number, target: number, hardness: number }

local scrubbing: { [Player]: Scrub? } = {}
local holding: { [Player]: boolean } = {}

local stateRemote: any = nil
local actionRemote: any = nil
local resultRemote: any = nil

-- ── Where are you standing ──────────────────────────────────────────────────

-- Station detection now lives in StationService, which indexes by CollectionService
-- tag instead of walking Workspace.BaseCamp's descendants per player per tick. The
-- old scan was both O(#camp) at 10 Hz AND scoped to the camp model, which made every
-- shop on the plaza and every pedestal on a plot structurally invisible to the game.
--
-- DigService.stageOf already set the precedent of keeping a thin delegate so callers
-- written against the old name keep working; stationOf below does the same, which is
-- why ToolService needed no changes at all.

--- PLAN §3.6: reaching a station stops the clock, for good.
local function dock(player: Player, data: any)
	local frozen = 0
	for _, item in data.carry do
		if not item.frozen then
			Decay.freeze(item)
			frozen += 1
		end
	end
	if frozen > 0 then
		resultRemote:FireClient(player, `docked \u{2014} {frozen} item(s) locked in, clocks stopped`)
		print(`[decon] {player.Name} docked {frozen} item(s)`)
	end
end

-- ── Actions ───────────────────────────────────────────────────────────

local function beginScrub(player: Player, data: any, stats: any, uid: string): string?
	local item = EconomyService.find(data, uid)
	if item == nil then
		return "you aren't carrying that"
	end

	local patches = item.patches or {}
	if #patches == 0 then
		return "already clean"
	end

	local blocked = Contamination.blockedBy(patches, stats.cleanPotency)
	local reachable = false
	for _, hardness in patches do
		if hardness <= stats.cleanPotency then
			reachable = true
			break
		end
	end

	if not reachable and blocked then
		return `nothing you can shift \u{2014} needs {CarryService.cleanerNameFor(blocked)}`
	end

	-- Target the easiest remaining patch, so progress feels steady and the wall
	-- (if there is one) arrives last.
	local easiest = math.huge
	for _, hardness in patches do
		if hardness <= stats.cleanPotency and hardness < easiest then
			easiest = hardness
		end
	end

	scrubbing[player] = {
		uid = uid,
		elapsed = 0,
		target = Contamination.secondsFor(easiest, stats.scrubRate),
		hardness = easiest,
	}
	return nil
end

local function rack(player: Player, data: any, uid: string): (boolean, string)
	local item, list, index = EconomyService.find(data, uid)
	if item == nil or list ~= data.carry or index == nil then
		return false, "that isn't in your bag"
	end

	table.remove(data.carry, index)
	table.insert(data.locker, item)
	Decay.freeze(item)

	local def = Items.get(item.itemId)
	local blocked = Contamination.blockedBy(item.patches or {}, StatResolver.get(data).cleanPotency)
	if blocked then
		return true, `{def.name} racked \u{2014} waiting on {CarryService.cleanerNameFor(blocked)}`
	end
	return true, `{def.name} racked`
end

-- ── Tick ────────────────────────────────────────────────────────────

local function stepPlayer(player: Player, dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local data = DataService.data(player)
	if data == nil then
		return
	end

	local stats = StatResolver.get(data)
	local kind = StationService.kindOf(player)
	local stationId = StationService.idOf(player)

	if kind == nil then
		stateRemote:FireClient(player, { station = nil })
		return
	end

	-- Scrub only happens at the decon station, and only while held.
	local scrub = scrubbing[player]
	if scrub and kind == "decon" and holding[player] then
		local item = EconomyService.find(data, scrub.uid)
		if item == nil then
			scrubbing[player] = nil
		else
			scrub.elapsed += dt
			if scrub.elapsed >= scrub.target then
				local cleared = Contamination.clearOne(item.patches, stats.cleanPotency)
				if cleared then
					-- Partial progress pays. PLAN §2: a failed clean is never wasted.
					data.xp += cleared * XP_PER_HARDNESS
				end
				scrubbing[player] = nil

				if #item.patches == 0 then
					data.stats.itemsCleaned += 1
					resultRemote:FireClient(player, `{Items.get(item.itemId).name} is clean`)
				else
					local message = beginScrub(player, data, stats, scrub.uid)
					if message then
						resultRemote:FireClient(player, message)
					end
				end
			end
		end
	end

	local carried = {}
	for _, item in data.carry do
		table.insert(carried, CarryService.describe(item, stats))
	end

	local locker = {}
	for _, item in data.locker do
		table.insert(locker, CarryService.describe(item, stats))
	end

	local current = scrubbing[player]
	local offer = if kind == "shop" and stationId then ShopService.offerFor(data, stationId) else nil

	-- Plot/pedestal panels reuse this same tick+payload rather than a fourth
	-- remote — see the trader/decon/shop precedent this file already sets.
	local plotView = if kind == "plot" and stationId then ExhibitService.plotViewFor(player, tonumber(stationId) :: number, data) else nil
	local standView = nil
	if kind == "pedestal" and stationId then
		local plotIndex, slotStr = string.match(stationId, "^(%d+):(%d+)$")
		if plotIndex and slotStr then
			standView = ExhibitService.standViewFor(player, tonumber(plotIndex) :: number, tonumber(slotStr) :: number, data)
		end
	end

	stateRemote:FireClient(player, {
		station = kind,
		stationId = stationId,
		offer = offer,
		plotView = plotView,
		standView = standView,
		cash = data.cash,
		xp = data.xp,
		potency = stats.cleanPotency,
		cleanerName = Gear.tier("Cleaner", data.gear.cleaner or 1).name,
		capacity = stats.capacity,
		items = carried,
		locker = locker,
		scrubUid = if current then current.uid else nil,
		scrubProgress = if current then math.clamp(current.elapsed / current.target, 0, 1) else 0,
	})
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

--- "decon", "trader" or nil. Read by ToolService to put the brush in your hands
--- when you are somewhere it makes sense to be scrubbing.
function DeconService.stationOf(player: Player): string?
	return StationService.kindOf(player)
end

function DeconService.init()
	stateRemote = Net.get("StationState")
	actionRemote = Net.get("StationAction")
	resultRemote = Net.get("StationResult")
end

function DeconService.start()
	-- DOCKING IS AN EDGE, NOT A STATE (PLAN §3.6). Freezing the decay clock has to
	-- happen once, on ARRIVAL at the decon station -- it used to be driven by
	-- comparing this tick's station against last tick's. StationService now owns
	-- that comparison, so the trigger moves here rather than being recomputed.
	StationService.onChanged(function(player, kind, _id, _prevKind, _prevId)
		local data = DataService.data(player)
		if data == nil then
			return
		end
		if kind == "decon" then
			dock(player, data)
		end
		if kind == nil then
			scrubbing[player] = nil
		end
	end)

	actionRemote.OnServerEvent:Connect(function(player: Player, request: any)
		if type(request) ~= "table" or type(request.action) ~= "string" then
			return
		end

		local data = DataService.data(player)
		if data == nil then
			return
		end
		local stats = StatResolver.get(data)
		local kind = StationService.kindOf(player)

		if request.action == "scrub" then
			if kind ~= "decon" then
				resultRemote:FireClient(player, "you need to be at the decon station")
				return
			end
			holding[player] = request.holding == true
			if request.holding == true and type(request.uid) == "string" then
				local existing = scrubbing[player]
				if existing == nil or existing.uid ~= request.uid then
					local message = beginScrub(player, data, stats, request.uid)
					if message then
						resultRemote:FireClient(player, message)
					end
				end
			end
		elseif request.action == "sell" then
			if kind ~= "trader" then
				resultRemote:FireClient(player, "the trader is the other one")
				return
			end
			local ok, message = EconomyService.sell(player, tostring(request.uid))
			resultRemote:FireClient(player, message)
			if ok then
				print(`[econ] {player.Name}: {message}`)
				-- The sold item may have been sitting in the Quarantine Locker; keep
				-- the physical cabinet in step. Cheap and idempotent for a bag sale.
				ExhibitService.refreshLocker(player)
			end
		elseif request.action == "buy" then
			-- ShopService re-derives the station from the player's position itself,
			-- so this is not the security boundary -- it is just a better message.
			-- tonumber(nil) is nil, not an error, so an omitted/malformed tier reaches
			-- ShopService.buy as nil and fails its own type check there.
			local ok, message = ShopService.buy(player, tostring(request.track), tonumber(request.tier))
			resultRemote:FireClient(player, message)
			if ok then
				print(`[shop] {player.Name}: {message}`)
			end
		elseif request.action == "display" then
			local ok, message = ExhibitService.display(player, tostring(request.uid))
			resultRemote:FireClient(player, message)
			if ok then
				print(`[exhibit] {player.Name}: {message}`)
			end
		elseif request.action == "undisplay" then
			local ok, message = ExhibitService.undisplay(player)
			resultRemote:FireClient(player, message)
			if ok then
				print(`[exhibit] {player.Name}: {message}`)
			end
		elseif request.action == "collect" then
			local ok, message = ExhibitService.collect(player)
			resultRemote:FireClient(player, message)
			if ok then
				print(`[exhibit] {player.Name}: {message}`)
			end
		elseif request.action == "rack" then
			if kind ~= "decon" then
				resultRemote:FireClient(player, "racking happens at the decon station")
				return
			end
			local ok, message = rack(player, data, tostring(request.uid))
			resultRemote:FireClient(player, message)
			if ok then
				print(`[decon] {player.Name}: {message}`)
				ExhibitService.refreshLocker(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		scrubbing[player] = nil
		holding[player] = nil
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player, dt)
			if not ok then
				warn(`[decon] tick failed for {player.Name}: {err}`)
			end
		end
	end)
end

return DeconService
