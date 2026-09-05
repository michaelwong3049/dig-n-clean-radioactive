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

	SCRUBBING LEFT THIS FILE. It used to live here as a timer driven by a HOLD TO
	SCRUB button on the station panel — you held a button and an item you could not
	see got cleaner. That is now WashService: you hold the item, press E at the tub,
	and hose it down in third person. The maths did not change at all (Contamination,
	the potency gate, one charge per patch); only who owns the clock did.

	What is left here is what still has no world object: docking, the bag list, RACK,
	the Quarantine Locker, and the panel payload for the shop/plot/pedestal modes.
	`rack()` below still reports the potency gate, so this file still reads
	Contamination -- it just no longer runs a scrub.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Items = require(Shared.Config.Items)
local Gear = require(Shared.Config.Gear)
local Decay = require(Shared.Decay)
local Liquids = require(Shared.Config.Liquids)
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

-- beginScrub used to live here, driving a HOLD TO SCRUB timer. It left with the rest
-- of scrubbing (see this file's header) -- WashService owns the hose session now, and
-- nothing in this file calls into a `scrubbing` table any more.
local function rack(_player: Player, data: any, uid: string): (boolean, string)
	local item, list, index = EconomyService.find(data, uid)
	if item == nil or list ~= data.carry or index == nil then
		return false, "that isn't in your bag"
	end

	table.remove(data.carry, index)
	table.insert(data.locker, item)
	Decay.freeze(item)

	local def = Items.get(item.itemId)
	-- cleanPotency, NOT effectivePotency: the locker's label is a shopping list, and
	-- a shopping list written against a liquid you are three patches from running out
	-- of is worse than no label. The Locker names the permanent fix.
	local blocked = Contamination.blockedBy(item.patches or {}, StatResolver.get(data).cleanPotency)
	if blocked then
		return true, `{def.name} racked \u{2014} waiting on {CarryService.hoseNameFor(blocked)}`
	end
	return true, `{def.name} racked`
end

-- ── Tick ────────────────────────────────────────────────────────────

local function stepPlayer(player: Player, _dt: number)
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

	local carried = {}
	for _, item in data.carry do
		table.insert(carried, CarryService.describe(item, stats))
	end

	local locker = {}
	for _, item in data.locker do
		table.insert(locker, CarryService.describe(item, stats))
	end

	local offer = if kind == "shop" and stationId then ShopService.offerFor(data, stationId) else nil

	-- Pedestals have no panel of their own any more: placing and retrieving are
	-- both a "Place"/"Take" ProximityPrompt on the stand itself (ExhibitService),
	-- not something this tick+payload needs to describe.
	stateRemote:FireClient(player, {
		station = kind,
		stationId = stationId,
		offer = offer,
		cash = data.cash,
		xp = data.xp,
		potency = stats.cleanPotency,
		effectivePotency = stats.effectivePotency,
		liquidName = Liquids.get(stats.liquidId).name,
		liquidColor = Liquids.get(stats.liquidId).color,
		liquidCharges = data.liquids[stats.liquidId] or 0,
		hoseName = Gear.tier("Cleaner", data.gear.cleaner or 1).name,
		capacity = stats.capacity,
		items = carried,
		locker = locker,
	})
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

--- "decon", "trader" or nil. Read by ToolService to put your hose in your hands
--- when you are somewhere it makes sense to be cleaning.
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
	end)

	actionRemote.OnServerEvent:Connect(function(player: Player, request: any)
		if type(request) ~= "table" or type(request.action) ~= "string" then
			return
		end

		local data = DataService.data(player)
		if data == nil then
			return
		end
		local kind = StationService.kindOf(player)

		if request.action == "sell" then
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
		elseif request.action == "equip" then
			-- Costs nothing, so there is no wallet to guard -- ShopService.equip still
			-- re-derives the station itself, because the thing being protected is that
			-- a shop is somewhere you walk to. Ownership is checked there too.
			local ok, message = ShopService.equip(player, tostring(request.track), tonumber(request.tier))
			resultRemote:FireClient(player, message)
			if ok then
				print(`[shop] {player.Name}: {message}`)
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
