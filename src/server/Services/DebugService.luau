--!strict
--[[
	DebugService.lua — SCAFFOLDING, and labelled as such on purpose.

	BUILD-ORDER Phase 0 asks for a debug HUD before any real UI, on the grounds that
	you are about to spend weeks tuning invisible rates and being able to see them is
	worth more than art. But at Phase 0 nothing produces those numbers yet — exposure
	is Phase 2 and the backpack is Phase 3 — so a HUD alone would render zeroes
	forever.

	PHASE 2 UPDATE: that is no longer what this is. ZoneService and ExposureService
	exist now and own the zone, the meter, the health and the blackout for real. This
	file kept its promise and gave all of that up — nothing here simulates anything any
	more. It READS the live services and renders them to the debug HUD, and it carries
	the tuning console.

	That distinction matters: while this file owned a private exposure meter there were
	two answers to "how irradiated am I", and only one of them could put you down.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Zones = require(Shared.Config.Zones)
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Contamination = require(Shared.Contamination)
local Radiation = require(Shared.Radiation)
local Decay = require(Shared.Decay)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local ZoneService = require(script.Parent.ZoneService)
local ExposureService = require(script.Parent.ExposureService)

local Workspace = game:GetService("Workspace")

local DebugService = {}

-- Nothing is stored per player any more; this exists only so the console can tell
-- "profile loaded" from "still loading".
type Sandbox = { ready: boolean }

local sandboxes: { [Player]: Sandbox } = {}
local stateRemote: any = nil

local INFINITE = -1 -- wire sentinel; math.huge is awkward to read on the far side

local function finite(n: number): number
	return if n == math.huge or n ~= n then INFINITE else n
end

-- ── The tick ───────────────────────────────────────────────────────────────

local function step(player: Player, _dt: number)
	local data = DataService.data(player)
	if data == nil then
		return
	end

	local stats = StatResolver.get(data)
	local zoneId = ZoneService.zoneOf(player)
	local ambient = ZoneService.ambientFor(player)
	local carried = Decay.totalEmission(data.carry, stats.satchelFuseMult)
	local reading = Radiation.resolve(ambient, carried, stats)

	-- Read, never simulate. ExposureService owns these.
	local exposure = ExposureService.exposureOf(player)
	local health = ExposureService.healthOf(player)

	local items = {}
	for _, item in data.carry do
		local stageIndex, stage = Decay.stageOf(item, stats.satchelFuseMult)
		table.insert(items, {
			uid = item.uid,
			rarity = item.rarity,
			modifier = item.modifier,
			stage = stage.name,
			stageIndex = stageIndex,
			toNext = finite(Decay.secondsToNextStage(item, stats.satchelFuseMult)),
			emission = Decay.emissionOf(item, stats.satchelFuseMult),
			valueRetained = stage.valueRetained,
			frozen = item.frozen,
		})
	end

	stateRemote:FireClient(player, {
		zoneId = zoneId,
		zoneName = if zoneId then Zones.get(zoneId).name else "Base Camp",
		ambient = ambient,
		hotPocket = ZoneService.hotPocketFor(player),

		exposure = exposure,
		exposureFrac = Radiation.exposureFraction(exposure),
		health = health,
		maxHealth = Tuning.MAX_HEALTH,
		downed = false,

		net = reading.net,
		carried = reading.carried,
		excess = reading.excess,
		healthBurn = reading.healthBurn,
		failing = reading.failing,

		greed = Radiation.greedFraction(reading, stats),
		survivable = finite(Radiation.survivableSeconds(reading, exposure, health)),
		threat = Radiation.dominantThreat(reading, exposure, health),

		capacity = stats.capacity,
		suitTolerance = stats.suitTolerance,
		gear = data.gear,

		items = items,
	})
end

-- ── The tuning console ──────────────────────────────────────────────────────
--
-- BUILD-ORDER: "argue with the matrix". These are how you argue with it while
-- standing inside the game rather than reading a printout.

local COMMANDS: { [string]: { help: string, run: (Player, Sandbox, { string }) -> string } } = {}

COMMANDS["/zone"] = {
	-- Zones are physical volumes now, so this teleports rather than overriding a
	-- number. You cannot be in a zone you are not standing in.
	help = "/zone <1-6> — teleport into that zone's field",
	run = function(player, _sandbox, args)
		local id = tonumber(args[1])
		if id == nil or Zones.DEFS[id] == nil then
			return "usage: /zone <1-6>"
		end

		local folder = Workspace:FindFirstChild("Zones")
		local part = folder and folder:FindFirstChild(`Zone{id}`)
		if part == nil or not part:IsA("BasePart") then
			return `zone {id} ({Zones.get(id).name}) has no field built in the world yet`
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			return "no character to move"
		end

		root.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 4, 0))
		local zone = Zones.get(id)
		return `moved into zone {id}: {zone.name} — {zone.baseRads} rads/s ambient`
	end,
}

COMMANDS["/dig"] = {
	help = "/dig <Rarity> [Modifier] — put a fake item in your bag, clock running",
	run = function(player, _sandbox, args)
		local data = DataService.data(player)
		if data == nil then
			return "your profile hasn't loaded yet"
		end

		local rarity = args[1] or "Rare"
		if Rarity.DEFS[rarity] == nil then
			return `unknown rarity "{rarity}" — one of: {table.concat(Rarity.ORDER, ", ")}`
		end

		local modifier = args[2] or "None"
		if Rarity.MODIFIERS[modifier] == nil then
			return `unknown modifier "{modifier}"`
		end

		-- Must be a REAL catalogue item: everything downstream does Items.get(itemId)
		-- and asserts. A synthetic "debug_item" blew up DeconService the moment you
		-- carried one to a station.
		local pool = Items.inZone(1, rarity)
		if #pool == 0 then
			return `zone 1 has no {rarity} items in the catalogue yet`
		end
		local def = pool[math.random(1, #pool)]

		table.insert(data.carry, {
			uid = HttpService:GenerateGUID(false),
			itemId = def.id,
			rarity = rarity,
			modifier = modifier,
			elapsed = 0,
			frozen = false,
			patches = Contamination.rollPatches(rarity, modifier),
		})
		return `dug {def.name} ({modifier} {rarity}) — carrying {#data.carry}`
	end,
}

COMMANDS["/clear"] = {
	help = "/clear — empty your bag",
	run = function(player, _sandbox, _args)
		local data = DataService.data(player)
		if data == nil then
			return "your profile hasn't loaded yet"
		end
		local n = #data.carry
		table.clear(data.carry)
		return `dropped {n} item(s)`
	end,
}

COMMANDS["/dock"] = {
	help = "/dock — simulate reaching a decon station: freezes every clock, for good",
	run = function(player, _sandbox, _args)
		local data = DataService.data(player)
		if data == nil then
			return "your profile hasn't loaded yet"
		end
		for _, item in data.carry do
			Decay.freeze(item)
		end
		return `docked {#data.carry} item(s) — clocks stopped permanently`
	end,
}

COMMANDS["/flush"] = {
	help = "/flush — rad flush: exposure to zero, health full. Does NOT touch your loot.",
	run = function(player, _sandbox, _args)
		ExposureService.flush(player)
		return "flushed — you are clean, your bag is not"
	end,
}

COMMANDS["/gear"] = {
	help = "/gear <detector|magnet|cleaner|suit|boots|satchel> <tier>",
	run = function(player, _sandbox, args)
		local data = DataService.data(player)
		if data == nil then
			return "your profile hasn't loaded yet"
		end
		local track, tier = args[1], tonumber(args[2])
		if track == nil or data.gear[track] == nil or tier == nil then
			return "usage: /gear <detector|magnet|cleaner|suit|boots|satchel> <tier>"
		end
		data.gear[track] = math.max(1, math.floor(tier))
		return `{track} -> tier {data.gear[track]}`
	end,
}

COMMANDS["/cash"] = {
	help = "/cash <amount> — set your wallet (testing the shop needs a way to be rich)",
	run = function(player, _sandbox, args)
		local data = DataService.data(player)
		if data == nil then
			return "your profile hasn't loaded yet"
		end
		local amount = tonumber(args[1])
		if amount == nil then
			return "usage: /cash <amount>"
		end
		data.cash = math.max(0, math.floor(amount))
		return `cash -> ${data.cash}`
	end,
}

COMMANDS["/pocket"] = {
	help = "/pocket — hot pockets belong to ZoneService and arrive in Phase 4",
	run = function(_player, _sandbox, _args)
		return "hot pockets are not built yet (PLAN §4, Phase 4)"
	end,
}

COMMANDS["/radhelp"] = {
	help = "/radhelp — list these commands",
	run = function(_player, _sandbox, _args)
		local lines = {}
		for _, entry in COMMANDS do
			table.insert(lines, entry.help)
		end
		table.sort(lines)
		return "\n" .. table.concat(lines, "\n")
	end,
}

--- Run one console line for a player. Chat and the scriptable hook below both go
--- through here, so the two can never drift apart. Accepts "/zone 3" or "zone 3".
local function dispatch(player: Player, line: string): string
	local sandbox = sandboxes[player]
	if sandbox == nil then
		return "no sandbox yet — is the profile still loading?"
	end

	local args = {}
	for word in string.gmatch(line, "%S+") do
		table.insert(args, word)
	end

	local alias = table.remove(args, 1)
	if alias == nil then
		return "empty command"
	end
	if string.sub(alias, 1, 1) ~= "/" then
		alias = "/" .. alias
	end

	local entry = COMMANDS[alias]
	if entry == nil then
		return `unknown command "{alias}" — try /radhelp`
	end

	local ok, result = pcall(entry.run, player, sandbox, args)
	return if ok then result else `ERROR {result}`
end

--- Who may use the tuning console.
---
--- This used to be EVERYONE, on EVERY server, with no check at all -- and the
--- commands write straight to the persisted profile, so any player could hand
--- themselves max gear and unlimited cash on a live server. It was survivable only
--- while the game had never shipped and nobody else had ever joined.
---
--- Adding /cash is what made this urgent rather than theoretical, so it is fixed
--- here rather than filed. Studio is always allowed (that is the whole point of the
--- console); in a real server it is the place owner and nobody else.
local function mayUseConsole(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end

	-- Group-owned places have no single owner id; fall back to closed.
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end

	return false
end

-- The scriptable hook. Roblox's command bar runs in its own Luau VM with its own
-- module cache, so `require(DebugService)` from there gets a fresh copy with an
-- empty sandbox table and cannot touch the live service. Instances ARE shared,
-- though, so an attribute on the Player is a channel that actually reaches us:
--
--     game.Players.SomeName:SetAttribute("DebugCmd", "/dig Legendary Irradiated")
--
-- Useful for pasting a whole tuning scenario in one go instead of typing six
-- chat lines.
local function attachScriptableHook(player: Player)
	player:GetAttributeChangedSignal("DebugCmd"):Connect(function()
		if not mayUseConsole(player) then
			return
		end
		local line = player:GetAttribute("DebugCmd")
		if type(line) ~= "string" or line == "" then
			return
		end
		player:SetAttribute("DebugCmd", "") -- consume it so the same line can repeat
		print(`[debug] {player.Name} {line}: {dispatch(player, line)}`)
	end)
end

local function registerCommands()
	for alias, entry in COMMANDS do
		local command = Instance.new("TextChatCommand")
		command.Name = `Debug_{string.gsub(alias, "/", "")}`
		command.PrimaryAlias = alias
		command.AutocompleteVisible = true

		-- `text` arrives as the whole typed line, alias included.
		command.Triggered:Connect(function(source: TextSource, text: string)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player == nil then
				return
			end
			if not mayUseConsole(player) then
				return
			end
			print(`[debug] {player.Name} {text}: {dispatch(player, text)}`)
		end)

		command.Parent = TextChatService
	end
end

-- ── Bootstrap ─────────────────────────────────────────────────────────────────

function DebugService.init()
	stateRemote = Net.get("DebugState")
end

function DebugService.start()
	DataService.onLoaded(function(player, _data)
		sandboxes[player] = { ready = true }
		attachScriptableHook(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		sandboxes[player] = nil
	end)

	registerCommands()

	Ticker.every(Tuning.TICK_RATE, function(dt)
		for player in sandboxes do
			local ok, err = pcall(step, player, dt)
			if not ok then
				warn(`[debug] tick failed for {player.Name}: {err}`)
			end
		end
	end)

	print("[debug] tuning console ready — type /radhelp in chat")
end

return DebugService
