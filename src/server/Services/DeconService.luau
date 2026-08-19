--!strict
--[[
	DeconService.lua — base camp: the decon station and the trader.

	TWO OBJECTS, NOT ONE, and PLAN §2 is right to insist. The decon station is what
	stops the decay clock; the trader is only a till. Keeping them apart means "I am
	safe" and "my loot is safe" stay two different problems.

	DOCKING IS THE WIN CONDITION (PLAN §3.6). Walking into the decon station's radius
	freezes every carried item at whatever stage it arrived in, permanently. Cleaning
	it afterwards is unhurried — the run home was the challenge, and turning "clean
	your backlog before it rots" into a second chore would sour a mechanic that works
	because it is short and sharp. So the freeze is generous and one-way.

	THE POTENCY GATE is the other half. A patch harder than your cleaner never comes
	off. The item is not destroyed and not lost — it can be racked in the Quarantine
	Locker as a labelled reminder of exactly which tool you need, or dirty-sold at 20%.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
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
local EconomyService = require(script.Parent.EconomyService)

local DeconService = {}

local XP_PER_HARDNESS = 5

type Scrub = { uid: string, elapsed: number, target: number, hardness: number }

local scrubbing: { [Player]: Scrub? } = {}
local holding: { [Player]: boolean } = {}
local atStation: { [Player]: string? } = {}

local stateRemote: any = nil
local actionRemote: any = nil
local resultRemote: any = nil

-- ── Where are you standing ──────────────────────────────────────────────────

local function stationAt(position: Vector3): string?
	local camp = Workspace:FindFirstChild("BaseCamp")
	if camp == nil then
		return nil
	end

	local bestKind: string? = nil
	local bestDistance = math.huge

	-- Descendants, not children: a station is a MODEL made of many parts, and only
	-- one of them carries the attributes. Scanning children only worked while the
	-- stations were single cubes.
	for _, part in camp:GetDescendants() do
		if part:IsA("BasePart") then
			local kind = part:GetAttribute("StationKind") :: string?
			local radius = (part:GetAttribute("Radius") :: number?) or 12
			if kind then
				local distance = (part.Position - position).Magnitude
				if distance <= radius and distance < bestDistance then
					bestKind, bestDistance = kind, distance
				end
			end
		end
	end

	return bestKind
end

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

local function cleanerNameFor(potencyNeeded: number): string
	for _, tier in Gear.Cleaner do
		if tier.potency >= potencyNeeded then
			return tier.name
		end
	end
	return "something stronger"
end

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
		return `nothing you can shift \u{2014} needs {cleanerNameFor(blocked)}`
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

local function rack(player: Player, data: any, uid: string): string
	local item, list, index = EconomyService.find(data, uid)
	if item == nil or list ~= data.carry or index == nil then
		return "that isn't in your bag"
	end

	table.remove(data.carry, index)
	table.insert(data.locker, item)
	Decay.freeze(item)

	local def = Items.get(item.itemId)
	local blocked = Contamination.blockedBy(item.patches or {}, StatResolver.get(data).cleanPotency)
	if blocked then
		return `{def.name} racked \u{2014} waiting on {cleanerNameFor(blocked)}`
	end
	return `{def.name} racked`
end

-- ── Tick ────────────────────────────────────────────────────────────

local function describe(item: any, stats: any): any
	local def = Items.get(item.itemId)
	local patches = item.patches or {}
	local value, clean = EconomyService.valueOf(item, stats)
	local _, stage = Decay.stageOf(item, stats.satchelFuseMult)
	local blocked = Contamination.blockedBy(patches, stats.cleanPotency)

	return {
		uid = item.uid,
		name = def.name,
		flavor = def.flavor,
		rarity = item.rarity,
		modifier = item.modifier,
		patches = table.clone(patches),
		clean = clean,
		blockedBy = blocked,
		needs = if blocked then cleanerNameFor(blocked) else nil,
		value = value,
		stage = stage.name,
		frozen = item.frozen,
	}
end

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
	local kind = stationAt(root.Position)

	if kind ~= atStation[player] then
		atStation[player] = kind
		if kind == "decon" then
			dock(player, data)
		end
		if kind == nil then
			scrubbing[player] = nil
		end
	end

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
		table.insert(carried, describe(item, stats))
	end

	local locker = {}
	for _, item in data.locker do
		table.insert(locker, describe(item, stats))
	end

	local current = scrubbing[player]
	stateRemote:FireClient(player, {
		station = kind,
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
	return atStation[player]
end

function DeconService.init()
	stateRemote = Net.get("StationState")
	actionRemote = Net.get("StationAction")
	resultRemote = Net.get("StationResult")
end

function DeconService.start()
	actionRemote.OnServerEvent:Connect(function(player: Player, request: any)
		if type(request) ~= "table" or type(request.action) ~= "string" then
			return
		end

		local data = DataService.data(player)
		if data == nil then
			return
		end
		local stats = StatResolver.get(data)
		local kind = atStation[player]

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
			end
		elseif request.action == "rack" then
			if kind ~= "decon" then
				resultRemote:FireClient(player, "racking happens at the decon station")
				return
			end
			resultRemote:FireClient(player, rack(player, data, tostring(request.uid)))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		scrubbing[player] = nil
		holding[player] = nil
		atStation[player] = nil
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
