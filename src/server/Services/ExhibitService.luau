--!strict
--[[
	ExhibitService.lua — the second exit for an item, and the one that keeps paying.

	AN ITEM YOU SELL IS GONE. AN ITEM YOU DISPLAY KEEPS PAYING (PLAN §8). Everything
	this file needs was already sitting in the codebase waiting for a service to
	read it: the profile schema (`data.exhibit`), every tuning number
	(`Tuning.EXHIBIT_*`), the world contract (`Plots.luau`'s Stand
	attributes), and even the multiplier hook (`StatResolver.yieldMultiplier`,
	wired to the Curator perk before this file existed to use it). This is the
	service that plugs all of that together.

	PLOTS ARE ASSIGNED, NOT OWNED. Per-session only, exactly as `Plots.luau`'s own
	header promised: "a player's plot contents persist; their plot number is
	meaningless across servers." `data.exhibit.pedestals` is the persistent part;
	`plotOf` here is a runtime map that gets rebuilt every time someone joins. A
	returning player may land on a different physical plot and see their own
	collection re-rendered onto it.

	THE SLOT ARRAY MUST STAY DENSE. ProfileStore forbids gaps in numeric arrays
	(DataService's own comment), so `pedestals` is `{ {slot=1,...}, {slot=3,...} }`
	with a `slot` field on each entry, not a sparse table indexed BY slot. Undisplay
	removes the entry (`table.remove`); it never sets one to nil.

	THE HOURLY CAP IS APPROXIMATED, NOT TRACKED. PLAN §8.7 wants income "capped per
	real-time hour" so an early lucky Legendary cannot fund the whole midgame while
	AFK. A true rolling-window tracker is more bookkeeping than the number is worth
	right now, so the cap is applied by clamping the RATE itself
	(`Tuning.EXHIBIT_HOURLY_CAP_PER_LEVEL * level` per hour, converted to per
	second) — cheaper, and the player-facing result is identical: money never
	arrives faster than the cap allows, online or offline.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local ItemModels = require(Shared.ItemModels)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)

local ExhibitService = {}

local PLOT_COUNT = 6 -- matches build/Plots.Plots.COUNT; not required so Services never depend on build/
local LOCKER_VISIBLE = 3 -- matches build/Plots.Plots.LOCKER_SLOTS; overflow racked items just aren't shown
local LOCKER_ITEM_SIZE = 1.2 -- longest axis a racked item model is scaled to; the cabinet bays are cramped

-- Who is sitting on which physical plot this session. Never persisted — see header.
local plotOf: { [Player]: number } = {}
local plotOwner: { [number]: Player? } = {}

-- ── Rendering ─────────────────────────────────────────────────────────────────
-- The only place this file touches Workspace directly. Kept small and separate so
-- the rest of the service can be reasoned about as pure data manipulation.

local function plotModel(index: number): Model?
	local row = Workspace:FindFirstChild("Plots")
	if row == nil then
		return nil
	end
	return row:FindFirstChild(`Plot{index}`) :: Model?
end

--- Repaint one plot's name sign. Empty name clears it back to "UNCLAIMED".
local function renderName(index: number, displayName: string?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local sign = plot:FindFirstChild("NameSign", true)
	local gui = sign and sign:FindFirstChildWhichIsA("SurfaceGui")
	local label = gui and gui:FindFirstChildWhichIsA("TextLabel")
	if label then
		(label :: TextLabel).Text = if displayName and displayName ~= "" then string.upper(displayName) else "UNCLAIMED"
	end
end

--- Repaint one stand with real item art when it exists, or the old rarity-coloured
--- block while that catalogue entry is still waiting for a model.
local function renderStand(index: number, slot: number, itemId: string?, rarity: string?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local display = plot:FindFirstChild(`Display{slot}`, true) :: BasePart?
	if display == nil then
		return
	end

	local previous = display:FindFirstChild("ItemModel")
	if previous then
		previous:Destroy()
	end

	local model: Model? = nil
	if itemId then
		local item = Items.get(itemId)
		model = ItemModels.create(item.model)
	end

	if model then
		display.Transparency = 1
		model.Name = "ItemModel"
		model:SetAttribute("ItemId", itemId)
		model.Parent = display
		model:PivotTo(
			display.CFrame
				* CFrame.new(0, -0.72, 0)
				* ItemModels.rotation(model, "Display")
		)
	elseif rarity then
		display.Color = Rarity.get(rarity).color
		display.Transparency = 0
	else
		display.Transparency = 1
	end
end

--- Fill one plot's Quarantine Locker (build/Plots.buildQuarantineLocker) from
--- `data.locker`, and swing its door: open the moment anything is racked, shut
--- when the last item leaves. `data == nil` clears it — used on release.
---
--- The locker has no station of its own; racking still happens at the cleansing
--- station. This only mirrors the profile's `locker` array onto the cabinet the
--- same way renderStand mirrors `exhibit.pedestals` onto the plinths.
local function renderLocker(index: number, data: any)
	local plot = plotModel(index)
	if plot == nil then
		return
	end

	local locker = if data ~= nil then data.locker else {}

	local door = plot:FindFirstChild("LockerDoor", true) :: Model?
	if door then
		local pivot = door:GetAttribute(if #locker > 0 then "OpenPivot" else "ClosedPivot")
		if typeof(pivot) == "CFrame" then
			door:PivotTo(pivot)
		end
	end

	for i = 1, LOCKER_VISIBLE do
		local anchor = plot:FindFirstChild(`LockerSlot{i}`, true) :: BasePart?
		if anchor then
			local previous = anchor:FindFirstChild("ItemModel")
			if previous then
				previous:Destroy()
			end

			local entry = locker[i]
			if entry == nil then
				anchor.Transparency = 1
			else
				local model = ItemModels.create(Items.get(entry.itemId).model)
				if model then
					anchor.Transparency = 1
					model.Name = "ItemModel"
					model:SetAttribute("ItemId", entry.itemId)
					model.Parent = anchor

					-- The bays are ~1.5 studs tall; normalise every model to a common
					-- longest-axis size (unlike the pedestals, which show items life-ish
					-- size on an open plinth) and seat it on the bay floor.
					model:PivotTo(CFrame.identity)
					local extents = model:GetExtentsSize()
					local longest = math.max(extents.X, extents.Y, extents.Z)
					if longest > 0 then
						model:ScaleTo(LOCKER_ITEM_SIZE / longest)
					end
					model:PivotTo(anchor.CFrame * ItemModels.rotation(model, "Display"))
					local bounds, size = model:GetBoundingBox()
					local floorY = anchor.Position.Y - anchor.Size.Y / 2
					model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - (bounds.Position.Y - size.Y / 2) + 0.03, 0))
				else
					anchor.Color = Rarity.get(entry.rarity).color
					anchor.Transparency = 0
				end
			end
		end
	end
end

--- Redraw everything on a plot from the profile — called once on assignment so a
--- returning player's collection shows up on whichever physical plot they land on.
local function renderAll(index: number, data: any)
	local owner = plotOwner[index]
	renderName(index, if owner then owner.DisplayName else nil)
	for slot = 1, Tuning.EXHIBIT_MAX_SLOTS do
		renderStand(index, slot, nil, nil)
	end
	for _, entry in data.exhibit.pedestals do
		renderStand(index, entry.slot, entry.itemId, entry.rarity)
	end
	renderLocker(index, data)
end

-- ── Spawning ──────────────────────────────────────────────────────────────────
--
-- BaseCamp no longer carries a spawn of its own (see BaseCamp.luau) — every
-- player's character has to land on their own assigned PlotSpawn instead, and
-- setting player.RespawnLocation alone is not enough for that: it only takes
-- effect on the player's NEXT respawn, and by the time assign() runs (after
-- DataService's async load) the player's character has usually already spawned
-- once, at Roblox's undefined "no enabled SpawnLocation yet" fallback position.
-- This moves that already-existing character over explicitly, the one time it
-- matters — every respawn after this one is already correctly routed by
-- RespawnLocation on its own.

--- Move `player`'s current character onto `spawn`, waiting for the character to
--- exist first if this somehow runs before it does (should not happen in
--- practice — CharacterAutoLoads fires immediately on join, well before a
--- profile finishes loading — but a spawn point silently doing nothing is a
--- much worse failure than a few seconds of extra caution here).
local function teleportToSpawn(player: Player, spawn: SpawnLocation)
	local character = player.Character
	if character == nil then
		local connection
		connection = player.CharacterAdded:Connect(function(newCharacter)
			connection:Disconnect()
			local root = newCharacter:WaitForChild("HumanoidRootPart", 5)
			if root then
				root.CFrame = spawn.CFrame + Vector3.new(0, 4, 0)
			end
		end)
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = spawn.CFrame + Vector3.new(0, 4, 0)
	end
end

-- ── Plot assignment ──────────────────────────────────────────────────────────

function ExhibitService.plotOf(player: Player): number?
	return plotOf[player]
end

--- Re-mirror `data.locker` onto this player's plot cabinet. Called by DeconService
--- after a rack or a (dirty-)sell, since those are the only two things that move
--- an item in or out of the locker. No-op if the player has no plot this session.
function ExhibitService.refreshLocker(player: Player)
	local index = plotOf[player]
	local data = DataService.data(player)
	if index ~= nil and data ~= nil then
		renderLocker(index, data)
	end
end

local function assign(player: Player)
	for index = 1, PLOT_COUNT do
		if plotOwner[index] == nil then
			plotOwner[index] = player
			plotOf[player] = index

			local plot = plotModel(index)
			if plot then
				local spawn = plot:FindFirstChild("PlotSpawn", true) :: SpawnLocation?
				if spawn then
					spawn.Enabled = true
					player.RespawnLocation = spawn
					teleportToSpawn(player, spawn)
				end
			end

			local data = DataService.data(player)
			if data then
				renderAll(index, data)
			end
			return
		end
	end
	-- All 6 plots taken (should not happen with MaxPlayers = 6, but a place
	-- setting is not something this code can enforce). Used to mean only "nowhere
	-- to display"; now that BaseCamp carries no fallback spawn, it also means this
	-- player never gets a RespawnLocation or a teleport, and is stuck wherever
	-- their character's initial undefined-position spawn happened to land. Selling
	-- and upgrading still work regardless.
	warn(`[exhibit] no free plot for {player.Name} — all {PLOT_COUNT} are taken, and they have nowhere to spawn`)
end

local function release(player: Player)
	local index = plotOf[player]
	if index == nil then
		return
	end
	plotOf[player] = nil
	plotOwner[index] = nil

	local plot = plotModel(index)
	if plot then
		local spawn = plot:FindFirstChild("PlotSpawn", true) :: SpawnLocation?
		if spawn then
			spawn.Enabled = false
		end
		renderName(index, nil)
		for slot = 1, Tuning.EXHIBIT_MAX_SLOTS do
			renderStand(index, slot, nil, nil)
		end
		renderLocker(index, nil)
	end
end

-- ── Yield ─────────────────────────────────────────────────────────────────────

--- Dollars per second this profile's exhibit is currently worth, BEFORE the
--- hourly cap. Duplicate damping (Tuning.EXHIBIT_DUPLICATE_YIELD) keys off how
--- many other displayed pieces share the same item id, so breadth beats depth —
--- one of everything outperforms four of a single Legendary.
local function rawRatePerSecond(data: any, stats: any): number
	local seen: { [string]: number } = {}
	local total = 0

	for _, entry in data.exhibit.pedestals do
		local copyIndex = (seen[entry.itemId] or 0) + 1
		seen[entry.itemId] = copyIndex
		local damping = Tuning.EXHIBIT_DUPLICATE_YIELD[math.min(copyIndex, #Tuning.EXHIBIT_DUPLICATE_YIELD)]

		local def = Items.get(entry.itemId)
		local rarity = Rarity.get(entry.rarity)
		local mod = Rarity.MODIFIERS[entry.modifier] or Rarity.MODIFIERS.None

		-- Per-minute in the design doc; converted to per-second here since that's
		-- the unit everything else in this codebase ticks in.
		local perMinute = def.baseValue * mod.valueMult * rarity.displayYield * damping * stats.yieldMultiplier
		total += perMinute / 60
	end

	return total
end

--- The rate, WITH the hourly cap applied. See the header for why this is a clamp
--- on the rate rather than a tracked rolling window.
local function cappedRatePerSecond(data: any, stats: any): number
	local raw = rawRatePerSecond(data, stats)
	local cap = (Tuning.EXHIBIT_HOURLY_CAP_PER_LEVEL * math.max(1, data.level)) / 3600
	return math.min(raw, cap)
end

--- Called once, right after a profile loads. Credits time spent offline into
--- bankedCash; start()'s loaded hook then calls deposit() straight away, so the
--- offline haul just lands in the wallet on login rather than waiting to be
--- collected. Still capped at EXHIBIT_OFFLINE_BANK_HOURS.
local function bankOffline(data: any)
	local now = os.time()
	if data.exhibit.bankedAt <= 0 then
		data.exhibit.bankedAt = now
		return
	end

	local elapsed = math.clamp(now - data.exhibit.bankedAt, 0, Tuning.EXHIBIT_OFFLINE_BANK_HOURS * 3600)
	if elapsed <= 0 then
		data.exhibit.bankedAt = now
		return
	end

	local stats = StatResolver.get(data)
	local rate = cappedRatePerSecond(data, stats)
	local credit = rate * elapsed * Tuning.EXHIBIT_OFFLINE_RATE
	if credit > 0 then
		data.exhibit.bankedCash += math.floor(credit + 0.5)
	end
	data.exhibit.bankedAt = now
end

--- Whole dollars are swept from bankedCash into spendable cash on a slow cadence,
--- not every tick: CashController documents that CashState must never fire per-tick,
--- and passive income trickles slowly enough that a DEPOSIT_INTERVAL batch is
--- invisible to the player — the badge just counts up on its own.
local DEPOSIT_INTERVAL = 5
local sinceDeposit = 0

--- Move the whole-dollar part of this profile's accrued exhibit income into
--- spendable cash, leaving the sub-dollar remainder in bankedCash so nothing is
--- lost to flooring each deposit. EconomyService.award fires CashState itself.
local function deposit(player: Player, data: any)
	local whole = math.floor(data.exhibit.bankedCash)
	if whole >= 1 then
		data.exhibit.bankedCash -= whole
		EconomyService.award(player, whole)
	end
end

local function tickPlayer(player: Player, dt: number, flush: boolean)
	local data = DataService.data(player)
	if data == nil or #data.exhibit.pedestals == 0 then
		return
	end

	local stats = StatResolver.get(data)
	local rate = cappedRatePerSecond(data, stats)
	data.exhibit.bankedCash += rate * dt
	data.exhibit.bankedAt = os.time()

	if flush then
		deposit(player, data)
	end
end

-- ── Actions ───────────────────────────────────────────────────────────────────

--- Everything StationController needs to draw the pedestal (stand) panel.
export type StandView = {
	plotIndex: number,
	slot: number,
	isOwner: boolean,
	occupied: boolean,
	itemName: string?,
	rarity: string?,
	uncrateSecondsLeft: number?,
}

function ExhibitService.standViewFor(player: Player, plotIndex: number, slot: number, data: any): StandView
	local entry = nil
	for _, e in data.exhibit.pedestals do
		if e.slot == slot then
			entry = e
			break
		end
	end

	local secondsLeft = nil
	if entry then
		local elapsed = os.time() - entry.placedAt
		secondsLeft = math.max(0, Tuning.EXHIBIT_UNCRATE_SECONDS - elapsed)
	end

	return {
		plotIndex = plotIndex,
		slot = slot,
		isOwner = plotOf[player] == plotIndex,
		occupied = entry ~= nil,
		itemName = if entry then Items.get(entry.itemId).name else nil,
		rarity = if entry then entry.rarity else nil,
		uncrateSecondsLeft = secondsLeft,
	}
end

--- Move an item from the backpack onto a specific stand. The stand (plot + slot)
--- is derived from where the player is STANDING, exactly like ShopService derives
--- the track — never taken from the request.
function ExhibitService.display(player: Player, uid: string): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local kind = StationService.kindOf(player)
	local stationId = StationService.idOf(player)
	if kind ~= "pedestal" or stationId == nil then
		return false, "you need to be at one of your stands"
	end

	local plotIndex, slotStr = string.match(stationId, "^(%d+):(%d+)$")
	if plotIndex == nil then
		return false, "that stand didn't resolve"
	end
	local plot, slot = tonumber(plotIndex) :: number, tonumber(slotStr) :: number

	if plotOf[player] ~= plot then
		return false, "that isn't your plot"
	end
	if slot < 1 or slot > data.exhibit.slots then
		return false, "that stand doesn't exist"
	end
	for _, entry in data.exhibit.pedestals do
		if entry.slot == slot then
			return false, "something's already here"
		end
	end

	local item, list, index = EconomyService.find(data, uid)
	if item == nil or list ~= data.carry or index == nil then
		return false, "you aren't carrying that"
	end
	if not Contamination.isClean(item.patches or {}) then
		return false, "clean it first"
	end
	if item.modifier == "Slagged" then
		return false, "slag can't be displayed"
	end

	table.remove(data.carry, index)
	table.insert(data.exhibit.pedestals, {
		slot = slot,
		uid = item.uid,
		itemId = item.itemId,
		rarity = item.rarity,
		modifier = item.modifier,
		placedAt = os.time(),
	})

	renderStand(plot, slot, item.itemId, item.rarity)
	return true, `{Items.get(item.itemId).name} is on display`
end

--- Pull an item back off a stand into the backpack, frozen (it was already docked
--- — pulling it off must not restart the decay clock). Respects the crating delay.
function ExhibitService.undisplay(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local kind = StationService.kindOf(player)
	local stationId = StationService.idOf(player)
	if kind ~= "pedestal" or stationId == nil then
		return false, "you need to be at the stand"
	end

	local plotIndex, slotStr = string.match(stationId, "^(%d+):(%d+)$")
	if plotIndex == nil then
		return false, "that stand didn't resolve"
	end
	local plot, slot = tonumber(plotIndex) :: number, tonumber(slotStr) :: number

	if plotOf[player] ~= plot then
		return false, "that isn't your plot"
	end

	local entryIndex = nil
	for i, entry in data.exhibit.pedestals do
		if entry.slot == slot then
			entryIndex = i
			break
		end
	end
	if entryIndex == nil then
		return false, "nothing here"
	end

	local entry = data.exhibit.pedestals[entryIndex]
	local elapsed = os.time() - entry.placedAt
	if elapsed < Tuning.EXHIBIT_UNCRATE_SECONDS then
		return false, `still crating \u{2014} {Tuning.EXHIBIT_UNCRATE_SECONDS - elapsed}s left`
	end

	table.remove(data.exhibit.pedestals, entryIndex)
	table.insert(data.carry, {
		uid = entry.uid,
		itemId = entry.itemId,
		rarity = entry.rarity,
		modifier = entry.modifier,
		elapsed = 0,
		frozen = true,
		patches = {},
	})

	renderStand(plot, slot, nil, nil)
	return true, `{Items.get(entry.itemId).name} back in your bag`
end

-- ── Bootstrap ─────────────────────────────────────────────────────────────────

function ExhibitService.init() end

function ExhibitService.start()
	DataService.onLoaded(function(player, data)
		-- Saves made before every stand was free stored a lower slot count (the old
		-- EXHIBIT_STARTING_SLOTS was 3, upgraded with cash). Bring anyone below the
		-- current count up to it; Reconcile can't, since the key already exists.
		if data.exhibit.slots < Tuning.EXHIBIT_MAX_SLOTS then
			data.exhibit.slots = Tuning.EXHIBIT_MAX_SLOTS
		end
		bankOffline(data)
		deposit(player, data)
		assign(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		release(player)
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		sinceDeposit += dt
		local flush = sinceDeposit >= DEPOSIT_INTERVAL
		if flush then
			sinceDeposit = 0
		end
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(tickPlayer, player, dt, flush)
			if not ok then
				warn(`[exhibit] tick failed for {player.Name}: {err}`)
			end
		end
	end, "ExhibitService")
end

return ExhibitService
