--!strict
--[[
	ExposureService.lua — the rad meter. This is the differentiator (PLAN §3).

	Every number here comes out of Shared/Radiation, the same module the client uses to
	draw the HUD, so the meter a player watches and the meter that puts them down can
	never disagree. This service owns the TRUTH; the client owns the picture.

	TWO WAYS TO GO DOWN, kept apart on purpose (PLAN §14):
	  exposure hits 100%  — the green death. Ambient plus what you are carrying.
	  health hits 0       — the white death. Only ever from suit failure, over-tier.

	BLACKOUT IS NOT A DEATH PENALTY. You keep cash, gear, the locker and anything
	displayed. You lose the dirty bag you were greedily hauling, and it stays on the
	ground where you fell for ninety seconds — glowing, server-visible, and grabbable
	by anyone including the player who watched you go down. PLAN §3.1 is emphatic that
	this punishes greed rather than existence, and that losing progress in a casual
	Roblox digging game kills retention.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)
local Radiation = require(Shared.Radiation)
local Decay = require(Shared.Decay)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local ZoneService = require(script.Parent.ZoneService)

local ExposureService = {}

local HEALTH_REGEN_PER_SEC = 2.5 -- PLAN §3.5: slowly out of radiation...
local BAG_LIFETIME = 90 -- §3.1, exactly ninety seconds
local DEFAULT_SHOWER_RADIUS = 10

type State = {
	exposure: number,
	health: number,
	downed: boolean,
}

local states: { [Player]: State } = {}
local bagContents: { [Instance]: { any } } = {}

local stateRemote: any = nil
local blackoutRemote: any = nil

local INFINITE = -1
local function finite(n: number): number
	return if n == math.huge or n ~= n then INFINITE else n
end

local function stateFor(player: Player): State
	local existing = states[player]
	if existing then
		return existing
	end
	local fresh: State = { exposure = 0, health = Tuning.MAX_HEALTH, downed = false }
	states[player] = fresh
	return fresh
end

-- ── Showers (PLAN §3.2) ───────────────────────────────────────────────────
--
-- These flush YOU. They do not clean items and they do not stop the decay clock —
-- only a decon station does that. "I am fine" and "my loot is fine" stay two
-- different problems, and a player can be perfectly safe while their bag rots.

-- Cached, because the naive version walked EVERY descendant of Workspace once per
-- player per tick. That is 10 full-world scans a second per player, against a world
-- that will eventually hold six zones of scenery — it was fine at 60 parts and would
-- have quietly become the most expensive thing in the game.
local showerCache: { { position: Vector3, radius: number } } = {}
local cacheAge = math.huge
local CACHE_REFRESH = 2

local function refreshShowerCache()
	table.clear(showerCache)
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Shower") == true then
			table.insert(showerCache, {
				position = descendant.Position,
				radius = (descendant:GetAttribute("Radius") :: number?) or DEFAULT_SHOWER_RADIUS,
			})
		end
	end
end

local function inShower(position: Vector3): boolean
	for _, shower in showerCache do
		if (shower.position - position).Magnitude <= shower.radius then
			return true
		end
	end
	return false
end

-- ── The dropped bag (PLAN §3.1) ────────────────────────────────────────────

local function giveBagTo(bag: BasePart, taker: Player)
	local contents = bagContents[bag]
	if contents == nil then
		return
	end

	local data = DataService.data(taker)
	if data == nil then
		return
	end

	local stats = StatResolver.get(data)
	local taken = 0
	while #contents > 0 and #data.carry < stats.capacity do
		table.insert(data.carry, table.remove(contents, 1))
		taken += 1
	end

	print(`[bag] {taker.Name} recovered {taken} item(s); {#contents} left in the bag`)

	-- Keep the label honest. Carry capacity means a full bag usually CANNOT be
	-- recovered in one go, so "12 item(s)" hovering over a bag holding 8 is an
	-- outright lie at exactly the moment the player is deciding whether to risk
	-- another trip out to it.
	local prompt = bag:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ObjectText = `{#contents} item(s)`
	end
	local billboard = bag:FindFirstChildOfClass("BillboardGui")
	local label = billboard and billboard:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = `dropped bag\n{#contents} item(s)`
	end

	if #contents == 0 then
		bagContents[bag] = nil
		bag:Destroy()
	end
end

local function dropBag(player: Player, data: any, position: Vector3): number
	-- PLAN §3.1 says you drop your UNCLEANED carry. Read literally: anything you
	-- already scrubbed clean stays with you. Being generous here is deliberate — a
	-- cleaned item represents work already done, and taking it back would punish the
	-- player twice for one mistake.
	local dropped = {}
	for index = #data.carry, 1, -1 do
		local item = data.carry[index]
		if not Contamination.isClean(item.patches or {}) then
			table.insert(dropped, item)
			table.remove(data.carry, index)
		end
	end

	if #dropped == 0 then
		return 0
	end

	local bag = Instance.new("Part")
	bag.Name = `DroppedBag_{player.Name}`
	bag.Size = Vector3.new(2.2, 1.6, 2.2)
	bag.Position = position + Vector3.new(0, 1, 0)
	bag.Anchored = true
	bag.CanCollide = false
	bag.Color = Color3.fromHex("8FE04A")
	bag.Material = Enum.Material.Neon
	bag.Parent = Workspace

	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex("8FE04A")
	light.Range = 18
	light.Brightness = 2.2
	light.Parent = bag

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(190, 44)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = bag

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromHex("D6FFB0")
	label.TextStrokeTransparency = 0.35
	label.Text = `{player.Name}'s bag\n{#dropped} item(s)`
	label.Parent = billboard

	-- Anyone can take it. That is the point (§3.1): a free social system that costs
	-- almost nothing to build.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab bag"
	prompt.ObjectText = `{#dropped} item(s)`
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = bag
	prompt.Triggered:Connect(function(taker: Player)
		giveBagTo(bag, taker)
	end)

	bagContents[bag] = dropped
	Debris:AddItem(bag, BAG_LIFETIME)

	return #dropped
end

-- ── Blackout ───────────────────────────────────────────────────────────

--- Where a blacked-out player wakes up.
---
--- This used to be FindFirstChildWhichIsA("SpawnLocation") — which searches DIRECT
--- CHILDREN OF WORKSPACE ONLY. BaseCamp parents its spawn inside the camp model, so
--- the search never matched and every blackout fell through to the hardcoded
--- CFrame.new(0, 8, 0) below. That point sat inside Zone 1's footprint: blacking out
--- teleported you into the radioactive field you had just escaped. It was silent for
--- the entire life of the project, which is why the last resort now warns.
---
--- The anchor is a NAMED part rather than "whichever SpawnLocation turns up first",
--- because the world now contains seven of those and picking one arbitrarily would
--- have swapped one wrong answer for another. It sits on the camp's shower grate, so
--- you come round already being flushed — a relief beat instead of a punishment one.
local warnedNoAnchor = false

local function baseCampCFrame(): CFrame
	local anchor = Workspace:FindFirstChild("RespawnAnchor", true)
	if anchor and anchor:IsA("BasePart") then
		return anchor.CFrame + Vector3.new(0, 4, 0)
	end

	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawn then
		return spawn.CFrame + Vector3.new(0, 4, 0)
	end

	if not warnedNoAnchor then
		warnedNoAnchor = true
		warn("[exposure] no RespawnAnchor and no SpawnLocation in Workspace — blacking out to (0, 8, 0), which may be inside a zone")
	end
	return CFrame.new(0, 8, 0)
end

local function blackout(player: Player, state: State, cause: string)
	state.downed = true

	local data = DataService.data(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	local lost = 0
	if data and root and root:IsA("BasePart") then
		lost = dropBag(player, data, root.Position)
	end

	state.exposure = 0
	state.health = Tuning.MAX_HEALTH

	if root and root:IsA("BasePart") then
		root.CFrame = baseCampCFrame()
	end

	blackoutRemote:FireClient(player, { cause = cause, itemsDropped = lost })
	print(`[rads] {player.Name} blacked out ({cause}) — dropped {lost} item(s)`)

	-- Brief grace so they do not immediately re-accrue while the screen is still white.
	task.delay(1.5, function()
		state.downed = false
	end)
end

-- ── Tick ────────────────────────────────────────────────────────────

local function stepPlayer(player: Player, dt: number)
	local data = DataService.data(player)
	if data == nil then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local state = stateFor(player)
	local stats = StatResolver.get(data)
	local zoneId = ZoneService.zoneOf(player)
	local ambient = ZoneService.ambientFor(player)
	-- The decay clock. CarryService owns this properly in Phase 3; it runs here
	-- meanwhile because this is already the one service walking the backpack every
	-- tick, and the clock must not stop merely because its permanent home is not
	-- built yet. It used to live in DebugService, which was worse: the real decay
	-- mechanic depending on a scaffolding file.
	for _, item in data.carry do
		local changedTo = Decay.tick(item, dt, stats.satchelFuseMult)
		if changedTo then
			print(`[decay] {player.Name}: {item.modifier} {item.rarity} -> {Tuning.DECAY_STAGES[changedTo].name}`)
		end
	end

	local carried = Decay.totalEmission(data.carry, stats.satchelFuseMult)
	local reading = Radiation.resolve(ambient, carried, stats)

	local showering = inShower(root.Position)

	if not state.downed then
		if showering then
			state.exposure = math.max(0, state.exposure - Tuning.SHOWER_FLUSH_RATE * dt)
		else
			state.exposure = math.clamp(state.exposure + reading.net * dt, 0, Tuning.EXPOSURE_CAP)
		end

		if reading.healthBurn > 0 then
			state.health = math.max(0, state.health - reading.healthBurn * dt)
		else
			-- ...and fully at base camp (PLAN §3.5).
			local rate = if zoneId == nil then HEALTH_REGEN_PER_SEC * 6 else HEALTH_REGEN_PER_SEC
			state.health = math.min(Tuning.MAX_HEALTH, state.health + rate * dt)
		end

		if state.health <= 0 then
			blackout(player, state, "burn")
		elseif state.exposure >= Tuning.EXPOSURE_CAP then
			blackout(player, state, "exposure")
		end
	end

	stateRemote:FireClient(player, {
		zoneId = zoneId,
		zoneName = if zoneId then Zones.get(zoneId).name else "Base Camp",
		ambient = ambient,
		inShower = showering,

		exposure = state.exposure,
		exposureFrac = Radiation.exposureFraction(state.exposure),
		health = state.health,
		maxHealth = Tuning.MAX_HEALTH,
		downed = state.downed,

		net = reading.net,
		carried = reading.carried,
		excess = reading.excess,
		healthBurn = reading.healthBurn,
		failing = reading.failing,

		greed = Radiation.greedFraction(reading, stats),
		survivable = finite(Radiation.survivableSeconds(reading, state.exposure, state.health)),
		threat = Radiation.dominantThreat(reading, state.exposure, state.health),

		carrying = #data.carry,
		capacity = stats.capacity,
		suitTolerance = stats.suitTolerance,
		gear = data.gear,
	})
end

-- ── API ─────────────────────────────────────────────────────────────

function ExposureService.exposureOf(player: Player): number
	return stateFor(player).exposure
end

function ExposureService.healthOf(player: Player): number
	return stateFor(player).health
end

--- Used by the debug console's /flush, and by anything that grants a rad flush.
function ExposureService.flush(player: Player)
	local state = stateFor(player)
	state.exposure = 0
	state.health = Tuning.MAX_HEALTH
	state.downed = false
end

function ExposureService.init()
	stateRemote = Net.get("ExposureState")
	blackoutRemote = Net.get("Blackout")
end

function ExposureService.start()
	DataService.onLoaded(function(player, _data)
		stateFor(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	Ticker.every(Tuning.TICK_RATE, function(dt)
		-- Once per interval for the whole server, not once per player per tick.
		cacheAge += dt
		if cacheAge >= CACHE_REFRESH then
			cacheAge = 0
			refreshShowerCache()
		end

		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player, dt)
			if not ok then
				warn(`[rads] tick failed for {player.Name}: {err}`)
			end
		end
	end)
end

return ExposureService
