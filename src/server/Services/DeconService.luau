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

	THE POTENCY GATE is the other half. A patch harder than your hose comes off slowly
	(WashService's soak clock). The item is not destroyed and not lost — it can be
	parked in the Quarantine Locker, labelled with exactly which hose washes it at full
	speed, or dirty-sold at 20%.

	SCRUBBING LEFT THIS FILE. It used to live here as a timer driven by a HOLD TO
	SCRUB button on the station panel — you held a button and an item you could not
	see got cleaner. That is now WashService: you hold the item, press E at the tub,
	and hose it down in third person. The maths did not change at all (Contamination,
	the potency gate, one charge per patch); only who owns the clock did.

	What is left here: docking, the panel payload for the trader / shop / locker panels,
	and the locker's two verbs. THE LOCKER IS A STATION AGAIN (StationKind = "locker",
	build/Plots.buildQuarantineLocker's tube rack, opened with its own E prompt), after
	a stretch where removing the decon panel had left STORE with nothing in the world
	to press it. `store` and `take` below move items between `data.carry` and
	`data.locker`; both ask that you are at YOUR OWN rack.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
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
local WashService = require(script.Parent.WashService)
local Bag = require(Shared.Bag)

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

--- Is `stationId` the locker on this player's own plot? A locker is a station anyone
--- can walk up to, but `data.locker` is only ever the player's own, so a neighbour's
--- rack must neither open the panel nor take a store.
local function ownsLocker(player: Player, stationId: string?): boolean
	local plot = ExhibitService.plotOf(player)
	return plot ~= nil and tonumber(stationId) == plot
end

--- Bag -> locker. Freezes the decay clock for good, like docking.
local function store(player: Player, data: any, uid: string): (boolean, string)
	local item, list, index = EconomyService.find(data, uid)
	if item == nil or list ~= data.carry or index == nil then
		if Bag.findCrate(data, uid) then
			return false, "crates don't go in the locker \u{2014} open it first"
		end
		return false, "that isn't in your bag"
	end
	-- The one held item WashService may have on the tub right now.
	if data.heldUid == uid and WashService.isWashing(player) then
		return false, "finish washing it first"
	end
	if #data.locker >= Tuning.LOCKER_SLOTS then
		return false, `locker full \u{2014} {Tuning.LOCKER_SLOTS} tubes`
	end

	table.remove(data.carry, index)
	table.insert(data.locker, item)
	Decay.freeze(item)
	-- Out of your hands too: CarryService's self-heal would not catch it, because
	-- EconomyService.find still finds a locker item.
	if data.heldUid == uid then
		data.heldUid = ""
	end

	-- "???" FOR ANYTHING STILL IN ITS CRUST (CarryService.nameOf) -- the shelf must not
	-- answer the question the hose is supposed to.
	local label = CarryService.nameOf(item)
	-- cleanPotency, NOT effectivePotency: the label is a shopping list, and a shopping
	-- list written against a liquid you are three patches from running out of is worse
	-- than no label.
	local blocked = Contamination.blockedBy(item.patches or {}, StatResolver.get(data).cleanPotency)
	if blocked then
		return true, `{label} sealed in \u{2014} {CarryService.hoseNameFor(blocked)} washes it fast`
	end
	return true, `{label} sealed in`
end

--- Locker -> bag, when there is room. The item stays frozen: it was docked the
--- moment it went in, and coming out must not restart its clock.
local function take(data: any, uid: string): (boolean, string)
	local item, list, index = EconomyService.find(data, uid)
	if item == nil or list ~= data.locker or index == nil then
		return false, "that isn't in your locker"
	end
	if Bag.used(data) >= StatResolver.get(data).capacity then
		return false, "inventory full"
	end

	table.remove(data.locker, index)
	table.insert(data.carry, item)
	return true, `{CarryService.nameOf(item)} back in your bag`
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
	-- Somebody else's rack is not a station you are at (see ownsLocker).
	if kind == "locker" and not ownsLocker(player, stationId) then
		kind, stationId = nil, nil
	end

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
		lockerSlots = Tuning.LOCKER_SLOTS,
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
		elseif request.action == "sellAll" then
			-- The trader panel's SELL ALL CLEAN / SELL ALL ???. Bag only, so no locker
			-- refresh -- see EconomyService.sellAll.
			if kind ~= "trader" then
				resultRemote:FireClient(player, "the trader is the other one")
				return
			end
			local ok, message = EconomyService.sellAll(player, tostring(request.which))
			resultRemote:FireClient(player, message)
			if ok then
				print(`[econ] {player.Name}: {message}`)
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
		elseif request.action == "store" or request.action == "take" then
			-- The locker panel's two verbs. Standing at your own rack is the gate; the
			-- station is re-derived here, never taken from the client.
			if kind ~= "locker" or not ownsLocker(player, StationService.idOf(player)) then
				resultRemote:FireClient(player, "that happens at your own locker")
				return
			end
			local uid = tostring(request.uid)
			local ok, message
			if request.action == "store" then
				ok, message = store(player, data, uid)
			else
				ok, message = take(data, uid)
			end
			resultRemote:FireClient(player, message)
			if ok then
				print(`[locker] {player.Name}: {message}`)
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
