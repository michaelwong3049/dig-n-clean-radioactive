--!strict
--[[
	DigService.lua — the buried signal field, and the two verbs on top of it.

	THE ONE RULE THIS FILE EXISTS TO ENFORCE (ARCHITECTURE.md, server/client boundary):
	buried item positions never leave this server. Not as a position, not as a list,
	not "just the nearest one's coordinates". The client is told a DIRECTION and a
	STRENGTH for where it is currently standing, which is exactly what the sweep
	indicator needs to draw and nothing more. A dig game that replicates loot
	positions has an ESP script written for it inside a week, and at that point the
	rarity economy — which is the entire product — is dead.

	The client also never names what it wants to dig. It sends "I am holding the
	button"; the server decides which signal that means, based on where the player
	actually is.

	EXTRACTION IS A HAUL, NOT A DIG. You drop a magnet and pull the thing up through
	the soil. Holding the button raises it; letting go lets it sink back. What survives
	out here is metal and whatever the fallout soaked into, so the magnet is the tool.

	THREE GATES, all from Gear.lua, all enforced here:
	  detector.maxRarity — a Bent Coil physically cannot register a Rare. It does not
	                       ping quietly; it does not ping at all. (PLAN §2 step 1)
	  detector.depth     — deeper items are rarer, and a weak detector cannot see them.
	  magnet.maxGrip     — you can find ground your magnet cannot rip anything out of.
	                       This one is deliberately NOT an error message: an under-rated
	                       magnet lifts the item partway and stalls, so the player watches
	                       it strain three feet down and cannot have it.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local ZoneService = require(script.Parent.ZoneService)

local DigService = {}


-- ── Tuning that is Phase-1 shaped and will move to Config once it settles ────────

local SIGNALS_PER_ZONE = 45
local DIG_RADIUS = 5 -- studs you must be within to get a magnet onto a signal
local DEPTH_BASE = 1.0
local DEPTH_PER_RARITY = 1.6 -- rarer buries deeper, which is what makes depth a gate
local DEPTH_JITTER = 1.0
local PULL_SECONDS_PER_STUD = 1.2
local SLIP_RATE = 1.6 -- let go and it sinks back faster than you raised it
local STRAIN_CEILING = 0.25 -- how far an under-rated magnet gets before it stalls

-- ── State ──────────────────────────────────────────────────────────────

type Signal = {
	uid: string,
	zoneId: number,
	position: Vector3, -- SERVER ONLY. Never put this on a remote.
	itemId: string,
	rarity: string,
	modifier: string,
	depth: number,
	soil: number,
}

local signalsByZone: { [number]: { Signal } } = {}
local holding: { [Player]: boolean } = {}
local pulling: { [Player]: boolean } = {} -- holding AND actually on a signal
local overSignal: { [Player]: boolean } = {} -- standing on one, hauling or not
local digProgress: { [Player]: number } = {}
local digTarget: { [Player]: string? } = {}

local sweepRemote: any = nil
local digRemote: any = nil
local unearthedRemote: any = nil

-- ── Rolling ───────────────────────────────────────────────────────────

local function rollRarity(zoneId: number): string
	local loot = Zones.get(zoneId).loot

	local total = 0
	for _, weight in loot do
		total += weight
	end

	local pick = math.random() * total
	for _, name in Rarity.ORDER do -- deterministic order; pairs() order is not stable
		local weight = loot[name]
		if weight then
			pick -= weight
			if pick <= 0 then
				return name
			end
		end
	end

	return "Scrap"
end

local function rollModifier(): string
	local total = 0
	for _, def in Rarity.MODIFIERS do
		total += def.weight -- Slagged is weight 0: earned, never rolled
	end

	local pick = math.random() * total
	for name, def in Rarity.MODIFIERS do
		pick -= def.weight
		if pick <= 0 and def.weight > 0 then
			return name
		end
	end

	return "None"
end

--- Zone 1 has no Mythic or Anomaly entries but its loot table can still roll them.
--- Step down until the catalogue actually has something, rather than erroring or
--- silently dropping the dig.
---
--- Returns nil when the zone has NOTHING at any rarity. That used to be an error(),
--- which was a live landmine: this runs inside the 10 Hz tick, so an unstocked zone
--- threw ten times a second and — before Ticker gained per-subscriber isolation —
--- took down every service booted after this one. An unstocked zone is a content
--- gap, not a crash; it should degrade to "no signals here" and say so once.
local unstockedWarned: { [number]: boolean } = {}

local function rollItemId(zoneId: number, rarity: string): (string?, string?)
	local order = Rarity.get(rarity).order

	for step = order, 1, -1 do
		local name = Rarity.ORDER[step]
		local pool = Items.inZone(zoneId, name)
		if #pool > 0 then
			return pool[math.random(1, #pool)].id, name
		end
	end

	if not unstockedWarned[zoneId] then
		unstockedWarned[zoneId] = true
		warn(`[dig] zone {zoneId} has no items at any rarity — Config/Items.luau does not stock it. No signals will spawn there.`)
	end
	return nil, nil
end

-- ── The signal field ────────────────────────────────────────────────────

local function zonePart(zoneId: number): BasePart?
	local folder = Workspace:FindFirstChild("Zones")
	if folder == nil then
		return nil
	end
	local part = folder:FindFirstChild(`Zone{zoneId}`)
	return if part and part:IsA("BasePart") then part else nil
end

local function randomPointOn(part: BasePart): Vector3
	local size = part.Size
	local x = (math.random() - 0.5) * size.X
	local z = (math.random() - 0.5) * size.Z
	return part.CFrame:PointToWorldSpace(Vector3.new(x, size.Y / 2, z))
end

local function spawnSignal(zoneId: number)
	local part = zonePart(zoneId)
	if part == nil then
		return
	end

	local rarity = rollRarity(zoneId)
	local itemId, actualRarity = rollItemId(zoneId, rarity)
	if itemId == nil or actualRarity == nil then
		return -- zone isn't stocked; rollItemId has already said so, once
	end
	local order = Rarity.get(actualRarity).order

	local signal: Signal = {
		uid = HttpService:GenerateGUID(false),
		zoneId = zoneId,
		position = randomPointOn(part),
		itemId = itemId,
		rarity = actualRarity,
		modifier = rollModifier(),
		depth = DEPTH_BASE + (order - 1) * DEPTH_PER_RARITY + math.random() * DEPTH_JITTER,
		soil = Zones.get(zoneId).soilHardness,
	}

	table.insert(signalsByZone[zoneId], signal)
end

local function removeSignal(zoneId: number, uid: string)
	local list = signalsByZone[zoneId]
	for index, signal in list do
		if signal.uid == uid then
			table.remove(list, index)
			return
		end
	end
end

local function topUpField()
	for zoneId, list in signalsByZone do
		while #list < SIGNALS_PER_ZONE do
			local before = #list
			spawnSignal(zoneId)
			if #list == before then
				break -- no zone part in the world yet; try again next tick
			end
		end
	end
end

-- ── The sweep ─────────────────────────────────────────────────────────

--- Nearest signal this player's detector can actually register. Both gates are
--- absolute: an unregisterable signal is invisible, not faint.
local function nearestVisible(zoneId: number, position: Vector3, stats: any): (Signal?, number)
	local list = signalsByZone[zoneId]
	if list == nil then
		return nil, math.huge
	end

	local best: Signal? = nil
	local bestDistance = math.huge

	for _, signal in list do
		if Rarity.get(signal.rarity).order > stats.detectorMaxRarity then
			continue
		end
		if signal.depth > stats.detectorDepth then
			continue
		end

		local delta = signal.position - position
		local distance = math.sqrt(delta.X * delta.X + delta.Z * delta.Z) -- XZ only
		if distance < bestDistance then
			best = signal
			bestDistance = distance
		end
	end

	if best == nil or bestDistance > stats.detectorRadius then
		return nil, math.huge
	end
	return best, bestDistance
end

--- What the ping is allowed to reveal before you dig. PLAN §2 step 1: high-tier
--- detectors show rarity on the ping so you stop wasting time digging Scrap.
local function hintFor(signal: Signal, clarity: number): (string?, string?)
	if clarity <= 0 then
		return nil, nil
	end
	if clarity >= 3 then
		return signal.rarity, signal.modifier
	end
	return signal.rarity, nil
end

-- ── The dig ──────────────────────────────────────────────────────────

-- The item, physically rising. This is the only place a signal's position reaches
-- the world, and it is safe to: the player is already standing within DIG_RADIUS of
-- it and has committed to the pull. The FIELD stays invisible — only the one thing
-- you are actively hauling shows itself.
local hauled: { [Player]: BasePart } = {}

local function clearHaul(player: Player)
	local part = hauled[player]
	if part then
		part:Destroy()
		hauled[player] = nil
	end
end

local function updateHaul(player: Player, signal: Signal, progress: number, rarityHint: string?)
	if progress <= 0.01 then
		clearHaul(player)
		return
	end

	local part = hauled[player]
	if part == nil or part.Parent == nil then
		part = Instance.new("Part")
		part.Name = `Haul_{player.Name}`
		part.Size = Vector3.new(1.4, 1.4, 1.4)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Material = Enum.Material.Metal
		part.Parent = Workspace
		hauled[player] = part
	end

	-- Only wear a rarity colour if the detector was good enough to reveal it. A Bent
	-- Coil user hauls up an anonymous lump and finds out when it breaks the surface.
	part.Color = if rarityHint then Rarity.get(rarityHint).color else Color3.fromHex("6E6A62")
	part.CFrame = CFrame.new(signal.position - Vector3.new(0, signal.depth * (1 - progress), 0))
		* CFrame.Angles(0, progress * 8, 0)
end

local function unearth(player: Player, data: any, signal: Signal)
	clearHaul(player)
	local item = Items.get(signal.itemId)

	table.insert(data.carry, {
		uid = signal.uid,
		itemId = signal.itemId,
		rarity = signal.rarity,
		modifier = signal.modifier,
		elapsed = 0, -- the decay clock starts HERE (PLAN §3.6). Phase 3 ticks it.
		frozen = false,
		-- Contamination is rolled the moment it leaves the ground, not at the station,
		-- because that is when it picked the dirt up. Extends ARCHITECTURE's CarriedItem.
		patches = Contamination.rollPatches(signal.rarity, signal.modifier),
	})

	data.discovered[signal.itemId] = true

	removeSignal(signal.zoneId, signal.uid)
	spawnSignal(signal.zoneId) -- keep the field populated

	unearthedRemote:FireClient(player, {
		itemId = item.id,
		name = item.name,
		flavor = item.flavor,
		rarity = signal.rarity,
		modifier = signal.modifier,
		baseValue = item.baseValue,
		carrying = #data.carry,
	})

	print(`[dig] {player.Name} unearthed {signal.modifier} {signal.rarity} — {item.name}`)
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
	local position = root.Position
	local zoneId = ZoneService.zoneOf(player)

	if zoneId == nil then
		digProgress[player] = 0
		digTarget[player] = nil
		pulling[player] = false
		overSignal[player] = false
		clearHaul(player)
		-- carrying/capacity ride along on EVERY payload: the bag counter should be
		-- true all the time, not only while something is pinging.
		sweepRemote:FireClient(player, {
			inZone = false,
			carrying = #data.carry,
			capacity = stats.capacity,
		})
		return
	end

	local signal, distance = nearestVisible(zoneId, position, stats)


	if signal == nil then
		digProgress[player] = 0
		digTarget[player] = nil
		pulling[player] = false
		overSignal[player] = false
		clearHaul(player)
		sweepRemote:FireClient(player, {
			inZone = true,
			zoneId = zoneId,
			hasSignal = false,
			carrying = #data.carry,
			capacity = stats.capacity,
		})
		return
	end

	local delta = signal.position - position
	local strength = math.clamp(1 - (distance / stats.detectorRadius), 0, 1)
	local rarityHint, modifierHint = hintFor(signal, stats.detectorClarity)

	-- Reset progress if they wandered off this signal onto another one.
	if digTarget[player] ~= signal.uid then
		digTarget[player] = signal.uid
		digProgress[player] = 0
	end

	local inRange = distance <= DIG_RADIUS
	local strongEnough = signal.soil <= stats.maxGrip
	local hasRoom = #data.carry < stats.capacity

	local blocked: string? = nil
	if not strongEnough then
		blocked = "weak"
	elseif not hasRoom then
		blocked = "full"
	end

	local required = PULL_SECONDS_PER_STUD * signal.depth / stats.pullSpeed
	local progress = digProgress[player] or 0

	-- Drives which tool is visible in the player's hands (ToolService).
	pulling[player] = holding[player] == true and inRange and blocked ~= "full"
	overSignal[player] = inRange and blocked ~= "full"

	-- A full bag is the one hard stop — there is nowhere to put it. An under-rated
	-- magnet still gets to try, and that trying is the whole teaching moment.
	if holding[player] and inRange and blocked ~= "full" then
		progress += dt / required
		if not strongEnough then
			progress = math.min(progress, STRAIN_CEILING)
		end

		if progress >= 1 then
			digProgress[player] = 0
			digTarget[player] = nil
			unearth(player, data, signal)
			sweepRemote:FireClient(player, {
				inZone = true,
				zoneId = zoneId,
				hasSignal = false,
				carrying = #data.carry,
				capacity = stats.capacity,
			})
			return
		end
	else
		-- Let go and it sinks. The haul is a commitment, not a checkpoint you bank.
		progress = math.max(0, progress - dt * SLIP_RATE / required)
	end

	digProgress[player] = progress
	updateHaul(player, signal, progress, rarityHint)

	-- DIRECTION AND STRENGTH ONLY. No position, no uid, no list.
	sweepRemote:FireClient(player, {
		inZone = true,
		zoneId = zoneId,
		hasSignal = true,
		strength = strength,
		angle = math.atan2(delta.Z, delta.X),
		rarityHint = rarityHint,
		modifierHint = modifierHint,
		inRange = inRange,
		blocked = blocked,
		digProgress = digProgress[player] or 0,
		carrying = #data.carry,
		capacity = stats.capacity,
	})
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

--- Is this player currently hauling something up? Read by ToolService to decide
--- whether the magnet or the detector belongs in their hands.
function DigService.isPulling(player: Player): boolean
	return pulling[player] == true
end

--- Standing close enough to haul, whether or not they have started. ToolService
--- swaps to the magnet on THIS rather than on isPulling: a pull lasts a couple of
--- seconds, so keying the model to it made the magnet flicker in and out too fast
--- to register. Swapping on approach reads as "found it, now get the magnet out".
function DigService.isOverSignal(player: Player): boolean
	return overSignal[player] == true
end

--- Kept as a thin delegate so callers written during Phase 1 keep working.
--- ZoneService is the authority now.
function DigService.zoneOf(player: Player): number?
	return ZoneService.zoneOf(player)
end

function DigService.init()
	sweepRemote = Net.get("SweepState")
	digRemote = Net.get("DigInput")
	unearthedRemote = Net.get("Unearthed")

	-- Phase 1 is one zone. The loop is written for all six.
	for _, zone in Zones.DEFS do
		signalsByZone[zone.id] = {}
	end
end

function DigService.start()
	topUpField()

	digRemote.OnServerEvent:Connect(function(player: Player, isHolding: any)
		holding[player] = isHolding == true
	end)

	Players.PlayerRemoving:Connect(function(player)
		holding[player] = nil
		digProgress[player] = nil
		digTarget[player] = nil
		pulling[player] = nil
		overSignal[player] = nil
		clearHaul(player)
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		topUpField()
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player, dt)
			if not ok then
				warn(`[dig] tick failed for {player.Name}: {err}`)
			end
		end
	end)

	local total = 0
	for _, list in signalsByZone do
		total += #list
	end
	print(`[dig] signal field seeded — {total} buried signal(s)`)
end

return DigService
