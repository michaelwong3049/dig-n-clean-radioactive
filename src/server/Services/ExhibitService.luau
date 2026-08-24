--!strict
--[[
	ExhibitService.lua — the second exit for an item, and the one that keeps paying.

	AN ITEM YOU SELL IS GONE. AN ITEM YOU DISPLAY KEEPS PAYING (PLAN §8). Everything
	this file needs was already sitting in the codebase waiting for a service to
	read it: the profile schema (`data.exhibit`), every tuning number
	(`Tuning.EXHIBIT_*`), the world contract (`Plots.luau`'s ClaimBoard/Stand
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
local Gear = require(Shared.Config.Gear)
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)

local ExhibitService = {}

local PLOT_COUNT = 6 -- matches build/Plots.Plots.COUNT; not required so Services never depend on build/

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

--- Repaint one stand: coloured and lit when occupied, transparent when empty. The
--- colour matches DigService.updateHaul's convention for the same rarity, so the
--- colour on the plinth is the same one the player watched come out of the ground.
local function renderStand(index: number, slot: number, rarity: string?)
	local plot = plotModel(index)
	if plot == nil then
		return
	end
	local display = plot:FindFirstChild(`Display{slot}`, true) :: BasePart?
	if display == nil then
		return
	end
	if rarity then
		display.Color = Rarity.get(rarity).color
		display.Transparency = 0
	else
		display.Transparency = 1
	end
end

--- Redraw everything on a plot from the profile — called once on assignment so a
--- returning player's collection shows up on whichever physical plot they land on.
local function renderAll(index: number, data: any)
	local owner = plotOwner[index]
	renderName(index, if owner then owner.DisplayName else nil)
	for slot = 1, Tuning.EXHIBIT_MAX_SLOTS do
		renderStand(index, slot, nil)
	end
	for _, entry in data.exhibit.pedestals do
		renderStand(index, entry.slot, entry.rarity)
	end
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
			renderStand(index, slot, nil)
		end
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
--- bankedCash (not straight into cash) so it's something to walk over and
--- collect, matching the "waiting at the door" framing in PLAN §13.
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

local function tickPlayer(player: Player, dt: number)
	local data = DataService.data(player)
	if data == nil or #data.exhibit.pedestals == 0 then
		return
	end

	local stats = StatResolver.get(data)
	local rate = cappedRatePerSecond(data, stats)
	data.exhibit.bankedCash += rate * dt
	data.exhibit.bankedAt = os.time()
end

-- ── Actions ───────────────────────────────────────────────────────────────────

--- Everything StationController needs to draw the plot / pedestal panels.
export type PlotView = {
	plotIndex: number,
	isOwner: boolean,
	bankedCash: number,
	slots: number,
	maxSlots: number,
	nextSlotPrice: number?,
}

function ExhibitService.plotViewFor(player: Player, plotIndex: number, data: any): PlotView
	local nextSlotPrice = if data.exhibit.slots < Tuning.EXHIBIT_MAX_SLOTS
		then Gear.pedestalPrice(data.exhibit.slots + 1)
		else nil

	return {
		plotIndex = plotIndex,
		isOwner = plotOf[player] == plotIndex,
		bankedCash = math.floor(data.exhibit.bankedCash),
		slots = data.exhibit.slots,
		maxSlots = Tuning.EXHIBIT_MAX_SLOTS,
		nextSlotPrice = nextSlotPrice,
	}
end

export type StandView = {
	plotIndex: number,
	slot: number,
	isOwner: boolean,
	locked: boolean,
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
		locked = slot > data.exhibit.slots,
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
	if slot > data.exhibit.slots then
		return false, `locked \u{2014} buy slot {slot} at the claim board first`
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

	renderStand(plot, slot, item.rarity)
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

	renderStand(plot, slot, nil)
	return true, `{Items.get(entry.itemId).name} back in your bag`
end

--- Drain bankedCash into spendable cash. Only the plot's owner, standing at
--- their own claim board.
function ExhibitService.collect(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local kind = StationService.kindOf(player)
	local stationId = StationService.idOf(player)
	if kind ~= "plot" or stationId == nil then
		return false, "you need to be at a claim board"
	end
	if plotOf[player] ~= tonumber(stationId) then
		return false, "that isn't your plot"
	end

	local amount = math.floor(data.exhibit.bankedCash)
	if amount <= 0 then
		return false, "nothing banked yet"
	end

	data.exhibit.bankedCash -= amount
	EconomyService.award(player, amount)
	return true, `collected ${amount}`
end

--- Buy the next pedestal slot (PLAN §8.5's endgame money sink).
function ExhibitService.buySlot(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local kind = StationService.kindOf(player)
	local stationId = StationService.idOf(player)
	if kind ~= "plot" or stationId == nil then
		return false, "you need to be at a claim board"
	end
	if plotOf[player] ~= tonumber(stationId) then
		return false, "that isn't your plot"
	end

	if data.exhibit.slots >= Tuning.EXHIBIT_MAX_SLOTS then
		return false, "every slot is already yours"
	end

	local nextSlot = data.exhibit.slots + 1
	local price = Gear.pedestalPrice(nextSlot)

	local paid, reason = EconomyService.spend(player, price)
	if not paid then
		return false, reason
	end

	data.exhibit.slots = nextSlot
	local plot = plotOf[player]
	if plot then
		renderStand(plot, nextSlot, nil) -- clears the locked look; still empty
	end
	return true, `slot {nextSlot} unlocked for ${price}`
end

-- ── Bootstrap ─────────────────────────────────────────────────────────────────

function ExhibitService.init() end

function ExhibitService.start()
	DataService.onLoaded(function(player, data)
		bankOffline(data)
		assign(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		release(player)
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(tickPlayer, player, dt)
			if not ok then
				warn(`[exhibit] tick failed for {player.Name}: {err}`)
			end
		end
	end, "ExhibitService")
end

return ExhibitService
