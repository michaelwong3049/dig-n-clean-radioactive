--!strict
--[[
	DebugService.lua — SCAFFOLDING, and labelled as such on purpose.

	BUILD-ORDER Phase 0 asks for a debug HUD before any real UI, on the grounds that
	you are about to spend weeks tuning invisible rates and being able to see them is
	worth more than art. But at Phase 0 nothing produces those numbers yet — exposure
	is Phase 2 and the backpack is Phase 3 — so a HUD alone would render zeroes
	forever.

	PHASE 2 UPDATE: that is no longer what this is. StageService and ExposureService
	exist now and own the stage, the meter, the health and the blackout for real. This
	file kept its promise and gave all of that up — nothing here simulates anything any
	more.

	HUD REMOVAL UPDATE: the Rad Debug on-screen HUD is gone, and the per-tick telemetry
	that fed it went with it — a DebugState payload was rebuilt from the live services
	every tick, and with no client listening that remote just filled its queue and
	Roblox logged "invocation queue exhausted" ten times a second. What is left is the
	tuning console: the /radhelp chat commands and the SetAttribute("DebugCmd", …) hook.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Stages = require(Shared.Config.Stages)
local Rarity = require(Shared.Config.Rarity)
local Items = require(Shared.Config.Items)
local Gear = require(Shared.Config.Gear)
local Liquids = require(Shared.Config.Liquids)
local Contamination = require(Shared.Contamination)
local Decay = require(Shared.Decay)
local StatResolver = require(Shared.StatResolver)

local DataService = require(script.Parent.DataService)
local ExposureService = require(script.Parent.ExposureService)
local EconomyService = require(script.Parent.EconomyService)
local ExhibitService = require(script.Parent.ExhibitService)

local Workspace = game:GetService("Workspace")

local DebugService = {}

-- Nothing is stored per player any more; this exists only so the console can tell
-- "profile loaded" from "still loading".
type Sandbox = { ready: boolean }

local sandboxes: { [Player]: Sandbox } = {}

-- ── The tuning console ──────────────────────────────────────────────────────
--
-- BUILD-ORDER: "argue with the matrix". These are how you argue with it while
-- standing inside the game rather than reading a printout.

local COMMANDS: { [string]: { help: string, run: (Player, Sandbox, { string }) -> string } } = {}

COMMANDS["/stage"] = {
	-- Stages are physical volumes now, so this teleports rather than overriding a
	-- number. You cannot be in a stage you are not standing in.
	help = "/stage <1-6> — teleport into that stage's field",
	run = function(player, _sandbox, args)
		local id = tonumber(args[1])
		if id == nil or Stages.DEFS[id] == nil then
			return "usage: /stage <1-6>"
		end

		local folder = Workspace:FindFirstChild("Stages")
		local part = folder and folder:FindFirstChild(`Stage{id}`)
		if part == nil or not part:IsA("BasePart") then
			return `stage {id} ({Stages.get(id).name}) has no field built in the world yet`
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") then
			return "no character to move"
		end

		root.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 4, 0))
		local stage = Stages.get(id)
		-- Lands at the plate's centre, i.e. depthFrac ~0.5 -- computed live rather
		-- than printing the old flat baseRads, which would understate what's
		-- actually here now that radiation ramps with depth. StageService's own
		-- tick hasn't caught up to the teleport yet, so this can't just call
		-- ambientFor(player) -- same depthFrac math, evaluated immediately instead.
		local ambientHere = Stages.radsAt(id, 0.5)
		return `moved into stage {id}: {stage.name} — {stage.baseRads}-{stage.deepRads} rads/s across the stage, ~{string.format("%.1f", ambientHere)} here`
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
		local pool = Items.inStage(1, rarity)
		if #pool == 0 then
			return `stage 1 has no {rarity} items in the catalogue yet`
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

-- DERIVED FROM Gear.TRACKS, not typed out. The old hardcoded list went stale the
-- moment Luck became the seventh track: the command still WORKED (it validates
-- against data.gear, not against the help string), so nothing failed loudly -- the
-- help text just quietly stopped mentioning a whole track.
--
-- "luck" IS APPENDED BY HAND, not derived, because Luck left Gear.TRACKS the moment
-- it stopped having tiers (Config/Gear.luau) -- but data.gear.luck is still a real,
-- directly-settable field (now a purchase level, not a tier index), and this exact
-- comment already warned once about a command silently going stale for Luck. Do not
-- let it happen a second time by "cleaning up" this line.
local GEAR_USAGE = `/gear <{table.concat((function()
	local keys = { "luck" }
	for _, track in Gear.TRACKS do
		table.insert(keys, Gear.profileKey(track))
	end
	return keys
end)(), "|")}> <tier>`

COMMANDS["/gear"] = {
	help = GEAR_USAGE,
	run = function(player, _sandbox, args)
		local data = DataService.data(player)
		if data == nil then
			return "your profile hasn't loaded yet"
		end
		local track, tier = args[1], tonumber(args[2])
		if track == nil or data.gear[track] == nil or tier == nil then
			return `usage: {GEAR_USAGE}`
		end
		local want = math.max(1, math.floor(tier))
		data.gear[track] = want

		-- GRANT THE LADDER UP TO IT, not just the rung. This command exists to put a
		-- tester where a real player would be after playing to that point, and a real
		-- player owns what they bought on the way -- equipping a tier the profile does
		-- not list as owned would leave the shop offering to sell you the thing in
		-- your own hands. `luck` has no ladder and no owned set, so it is skipped.
		if data.gearOwned and data.gearOwned[track] then
			local owned = {}
			for t = 1, want do
				table.insert(owned, t)
			end
			data.gearOwned[track] = owned
		end

		-- WRITING THE PROFILE IS NOT THE WHOLE PURCHASE for the cleaner track: the rung
		-- you own is also the machine bolted to your own wash bay, and ShopService pokes
		-- ExhibitService to swap it when a real purchase lands. A debug command that set
		-- the number and left a Garden Hose standing on the mast would be a testing tool
		-- that lies about the thing it exists to test. Last, so it renders the profile
		-- as it finally stands rather than as it stood mid-write.
		if track == "cleaner" then
			ExhibitService.refreshHose(player)
		end

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
		-- Pokes data.cash directly, same as /gear does with data.gear -- so it also
		-- has to push the badge itself rather than going through EconomyService's
		-- own mutation paths.
		EconomyService.pushCash(player)
		return `cash -> ${data.cash}`
	end,
}

COMMANDS["/speed"] = {
	-- ExposureService's per-tick loop is the ONLY thing allowed to write WalkSpeed
	-- (its own header says so). The previous version of this command poked the
	-- Humanoid directly and the write was gone within ~0.1s, the moment that loop
	-- recomputed speed from boots gear. It now hands a sustained override to that
	-- loop, which applies it every tick until cleared. The override ignores the
	-- boots tier and the haul penalty while set; `/speed off` returns you to normal
	-- gear-derived speed. It does NOT override the dig/wash root -- you still stand
	-- still while locked to a signal.
	help = "/speed <value> — pin WalkSpeed there for the session (ignores boots + haul); /speed off to clear",
	run = function(player, _sandbox, args)
		local raw = args[1]
		if raw == nil or raw == "off" or raw == "clear" or raw == "reset" then
			ExposureService.setSpeedOverride(player, nil)
			return "speed override cleared — back to boots gear"
		end
		local value = tonumber(raw)
		if value == nil then
			return "usage: /speed <value>  |  /speed off"
		end
		value = math.clamp(math.floor(value), 0, 500)
		ExposureService.setSpeedOverride(player, value)
		return `WalkSpeed pinned to {value} — /speed off to undo`
	end,
}

COMMANDS["/pocket"] = {
	help = "/pocket — hot pockets belong to StageService and arrive in Phase 4",
	run = function(_player, _sandbox, _args)
		return "hot pockets are not built yet (PLAN §4, Phase 4)"
	end,
}

COMMANDS["/liquid"] = {
	help = "/liquid <id> [charges] — put a canister in the hose without paying the pad",
	run = function(player, _sandbox, args)
		local data = DataService.data(player)
		if data == nil then
			return "your profile hasn't loaded yet"
		end

		local id = args[1]
		if id == nil or (id ~= Liquids.WATER and not Liquids.isRollable(id)) then
			local ids = {}
			for _, key in Liquids.ORDER do
				table.insert(ids, key)
			end
			return `usage: /liquid <{table.concat(ids, "|")}> [charges]`
		end

		if id == Liquids.WATER then
			data.equippedLiquid = ""
			return "hose -> Plain Water"
		end

		local def = Liquids.get(id)
		local charges = math.max(1, math.floor(tonumber(args[2]) or def.charges))
		data.liquids[id] = charges
		data.equippedLiquid = id
		return `hose -> {def.name}, {charges} charge(s), +{def.potency} potency`
	end,
}

COMMANDS["/odds"] = {
	help = "/odds — the wash pad's table at your current luck",
	run = function(player)
		local data = DataService.data(player)
		if data == nil then
			return "your profile hasn't loaded yet"
		end

		-- Reads Liquids.oddsAt, the SAME function LiquidService rolls against and the
		-- panel displays. This command is only useful if it cannot disagree with
		-- either, which is exactly why none of the three has its own copy.
		local stats = StatResolver.get(data)
		local odds = Liquids.oddsAt(stats.luckMultiplier)
		local level = data.gear.luck or 1
		local lines = {
			string.format("luck %.3gx (level %d, next +0.1x for $%d)", stats.luckMultiplier, level, Gear.luckPrice(level)),
		}
		for _, id in Liquids.ORDER do
			local chance = odds[id]
			if chance then
				local def = Liquids.get(id)
				table.insert(lines, string.format("  %-16s %6.2f%%   1 in %d", def.name, chance * 100, math.floor(1 / chance + 0.5)))
			end
		end
		return table.concat(lines, "\n")
	end,
}

COMMANDS["/field"] = {
	help = "/field <1-6> — the dig roll for that stage at your detector's luck",
	run = function(player, _sandbox, args)
		local stageId = tonumber(args[1])
		if stageId == nil or Stages.DEFS[stageId] == nil then
			return "usage: /field <1-6>"
		end
		local data = DataService.data(player)
		if data == nil then
			return "your profile hasn't loaded yet"
		end

		-- Reads Items.rollWeights, the SAME function DigService rolls against -- the dig
		-- analogue of /odds. tilt from the stage, luck from the player's detector.
		local stats = StatResolver.get(data)
		local tilt = Stages.get(stageId).rarityTilt
		local weights = Items.rollWeights(stageId, tilt, stats.detectorLuck)

		local byRarity: { [string]: number } = {}
		local ordered = {}
		for id, chance in weights do
			table.insert(ordered, { id = id, chance = chance })
			local r = Items.get(id).rarity
			byRarity[r] = (byRarity[r] or 0) + chance
		end
		table.sort(ordered, function(a, b)
			return a.chance > b.chance
		end)

		local lines = {
			string.format("stage %d — tilt %.2f, detector luck %.2fx", stageId, tilt, stats.detectorLuck),
		}
		for _, name in Rarity.ORDER do
			if byRarity[name] then
				table.insert(lines, string.format("  %-10s %6.2f%%", name, byRarity[name] * 100))
			end
		end
		table.insert(lines, "  ---")
		table.insert(lines, string.format("  %-26s %8s %6s %10s   %s", "id", "roll%", "wt(kg)", "true", "shown"))
		for _, e in ordered do
			local item = Items.get(e.id)
			table.insert(lines, string.format(
				"  %-26s %7.2f%% %6.4g   1 in %-6d   %s",
				e.id,
				e.chance * 100,
				item.weight,
				math.floor(1 / e.chance + 0.5),
				Items.oddsText(Items.shownOdds(item))
			))
		end
		return table.concat(lines, "\n")
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
--- through here, so the two can never drift apart. Accepts "/stage 3" or "stage 3".
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

-- No init(): there is no remote to wire any more. The console is all chat- and
-- attribute-driven, and both are set up in start().

function DebugService.start()
	DataService.onLoaded(function(player, _data)
		sandboxes[player] = { ready = true }
		attachScriptableHook(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		sandboxes[player] = nil
	end)

	registerCommands()

	print("[debug] tuning console ready — type /radhelp in chat")
end

return DebugService
