--!strict
--[[
	TreadmillService.lua — the Speed grind. Stand on a belt, earn Speed, level up.

	SPEED IS A LIFETIME TOTAL (`data.speedPoints`). Every second on a belt adds that
	belt's rate; every walk-speed level has a Speed requirement (Config/Treadmill), and
	crossing one levels you up on the spot. Nothing is ever spent.

	THE BELT IS A PLACE, NOT A BUTTON. There is no "start training" action and no
	session to open: `StationService.onChanged` says the moment a player's feet land
	inside a `StationKind = "treadmill"` radius, and from then until they step off,
	the tick loop below banks Speed. That is the same arrival edge the old wash
	pad rolled on (and DeconService still docks on), minus the one-shot — the pad paid
	out once on the edge, this pays out continuously between two edges.

	NOBODY IS EVER ROOTED BY THIS, on purpose. DigService's haul lock and WashService's
	session both pin WalkSpeed to zero and both carry a written-down list of every path
	that could strand a player as a result. A treadmill has no such excuse: the player
	is meant to be able to walk away at any instant, most of them will be AFK while it
	runs, and "you cannot move" is a catastrophic state to leave someone in while they
	are not looking at the screen. So the belt never touches the character. Stepping
	off is walking off.

	WHOSE BELT DOES NOT MATTER. Any treadmill trains any player standing on it, at that
	PLAYER's own tier — never the plot owner's. This is the rule the cleansing station
	already set (build/Plots.buildCleansingStation: "washing there still uses the
	washer's own Cleaner stats"), and it means a player with no plot this session — all
	six taken, see ExhibitService.assign — can still train at someone else's base
	instead of being locked out of a whole progression track by a full server.

	WHAT THE UPGRADE BUYS is `rate` — Speed per second (Config/Treadmill) — not Speed
	itself. Cash cannot buy a single level anywhere in this game; it can only buy a
	belt that converts your time into Speed faster. That is the entire
	reason the Boots track was retired — see Config/Treadmill's header — and it is the
	property to protect if anyone ever adds a gamepass here.

	THE SERVER OWNS THE CLOCK, as it does for the wash timer and the pull fuse. The
	client is told its Speed; it never reports training. There is no remote in
	this file that a client can send, which makes the whole feature unexploitable by
	construction rather than by validation.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Treadmill = require(Shared.Config.Treadmill)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)
local ExhibitService = require(script.Parent.ExhibitService)

local TreadmillService = {}

local STATION_KIND = "treadmill"

--- Matches Kit.TREADMILL_TAG. Hardcoded rather than required for the same reason
--- ShopService hardcodes UPGRADE_TAG: build/ is server-only and a Services/ file that
--- requires it drags the whole builder into every service's dependency graph.
local UPGRADE_TAG = "TreadmillUpgrade"

--- How often a trainee's readout is re-sent while they run. The Speed total moves
--- every tick, but the client counts it up locally from `rate` between pushes (see
--- TreadmillController / SpeedController), so once a second is only a drift correction.
--- Edges — stepping on or off, a level-up, a new belt, loading in — always push at once.
local PUSH_INTERVAL = 1

local stateRemote: any = nil
local resultRemote: any = nil

--- Who is standing on a belt right now. Written only by the StationService edge, so
--- it cannot drift from what the world thinks — and read by the tick loop as its
--- entire work list, which is why an empty camp costs nothing per tick.
local training: { [Player]: boolean } = {}

--- When each trainee was last sent a readout (os.clock), for PUSH_INTERVAL.
local lastPush: { [Player]: number } = {}

-- ── The readout ───────────────────────────────────────────────────────────

--- This player's Speed, as the client renders it: the HUD counter reads `points` and
--- `level`, the treadmill card reads the rest.
---
--- `rate` is what they would earn per second ON A BELT — reported even when they are
--- not standing on one, because what the card wants to show is "this is what going
--- back to the treadmill is worth". `training` says whether it is being paid now.
local function snapshot(player: Player, data: any)
	local tier = math.clamp(math.floor(data.treadmill or 1), 1, Treadmill.maxTier())
	local points = data.speedPoints or 0
	local level, progress = Treadmill.levelFor(points)
	local nextTier = Treadmill.TIERS[tier + 1]
	return {
		points = points,
		level = level,
		maxLevel = Treadmill.MAX_LEVEL,
		walk = Treadmill.walkSpeedFor(level),
		progress = progress,
		current = Treadmill.requirementFor(level),
		nextReq = Treadmill.requirementFor(level + 1),
		rate = Treadmill.rateFor(tier),
		training = training[player] == true,
		tier = tier,
		tierName = Treadmill.tier(tier).name,
		nextCost = if nextTier then nextTier.price else nil,
		nextName = if nextTier then nextTier.name else nil,
		nextRate = if nextTier then nextTier.rate else nil,
	}
end

local function push(player: Player)
	local data = DataService.data(player)
	if data == nil or stateRemote == nil then
		return
	end
	lastPush[player] = os.clock()
	stateRemote:FireClient(player, snapshot(player, data))
end

-- ── Training ──────────────────────────────────────────────────────────────

--- One tick of Speed for every player currently standing on a belt. The belt is
--- re-read every tick, so an upgrade bought mid-run pays from the next tick on.
---
--- Speed keeps counting past the top level. It is a lifetime total, not a bar, and a
--- maxed player's number still going up is the only thing their belt has left to say.
local function step(dt: number)
	local now = os.clock()
	for player in training do
		local data = DataService.data(player)
		if data == nil then
			continue
		end

		local tier = math.clamp(math.floor(data.treadmill or 1), 1, Treadmill.maxTier())
		local banked = data.speedPoints or 0
		local before = Treadmill.levelFor(banked)
		data.speedPoints = banked + Treadmill.rateFor(tier) * dt
		local after = Treadmill.levelFor(data.speedPoints)

		if after > before then
			-- The only moment in this feature where walk speed changes. Pushed at once
			-- so the level-up lands on screen the same tick StatResolver starts
			-- reporting the faster walk.
			print(`[treadmill] {player.Name}: level {before} -> {after} (walk {Treadmill.walkSpeedFor(after)})`)
			push(player)
		elseif now - (lastPush[player] or 0) >= PUSH_INTERVAL then
			push(player)
		end
	end
end

--- Re-send this player's readout now. For DebugService's /train, which pokes
--- `speedPoints` directly and would otherwise leave the HUD a second stale.
function TreadmillService.refresh(player: Player)
	push(player)
end

-- ── Buying a rung ─────────────────────────────────────────────────────────

--- Upgrade this player's belt one rung. Same shape as ShopService.buyLuck: price the
--- rung they are on, debit FIRST, and only mutate the profile once the debit lands —
--- so a refused purchase leaves nothing half-applied to unwind.
---
--- NO PROXIMITY CHECK, and that is not an omission: this is only ever reached from a
--- ProximityPrompt.Triggered, which fires on the server with MaxActivationDistance
--- already enforced by the engine. ShopService.wireUpgrade's header sets out the same
--- reasoning at more length.
function TreadmillService.buy(player: Player): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end

	local tier = math.clamp(math.floor(data.treadmill or 1), 1, Treadmill.maxTier())
	local price = Treadmill.priceFor(tier)
	if price == nil then
		return false, `{Treadmill.tier(tier).name} is the last belt there is`
	end

	local paid, reason = EconomyService.spend(player, price)
	if not paid then
		return false, reason
	end

	data.treadmill = tier + 1
	local bought = Treadmill.tier(data.treadmill)
	ExhibitService.refreshTreadmill(player)
	push(player)
	return true, `{bought.name} installed — +{bought.rate} Speed/s (paid ${price})`
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

--- Connect one console's prompt to the purchase. Built by build/Plots.buildTreadmill
--- and saved with the place; wired here at boot. The same build-time/runtime split
--- every station uses, and the reason a rebuilt plot needs no service change.
local function wireConsole(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt == nil then
		warn(`[treadmill] {part:GetFullName()} is tagged for upgrades but has no ProximityPrompt — nobody can buy from it`)
		return
	end

	prompt.Triggered:Connect(function(player: Player)
		local ok, message = TreadmillService.buy(player)
		resultRemote:FireClient(player, message)
		if ok then
			print(`[treadmill] {player.Name}: {message}`)
		end
	end)
end

function TreadmillService.init()
	stateRemote = Net.get("SpeedState")
	-- The console answers on the same channel every other world purchase does, so a
	-- refused upgrade reads exactly like a refused rung at a shop rack.
	resultRemote = Net.get("StationResult")
end

function TreadmillService.start()
	-- Tag-indexed and live, not a one-shot Workspace walk: World.rebuild() can be run
	-- from the command bar mid-session and a console built then would otherwise sit
	-- inert until the next server start. Straight out of ShopService.start.
	for _, part in CollectionService:GetTagged(UPGRADE_TAG) do
		wireConsole(part)
	end
	CollectionService:GetInstanceAddedSignal(UPGRADE_TAG):Connect(wireConsole)

	StationService.onChanged(function(player, kind, _id, previousKind)
		if kind == STATION_KIND then
			training[player] = true
			push(player)
		elseif previousKind == STATION_KIND then
			training[player] = nil
			-- Their plot's console shows the owner's level; bring it up to date with
			-- whatever this run earned. Once per run, not per tick.
			ExhibitService.refreshTreadmill(player)
			push(player)
		end
	end)

	DataService.onLoaded(function(player)
		-- The belt on their own plot has to wear the rung they own, and plot assignment
		-- and data load race each other — ExhibitService.refreshTreadmill is a no-op
		-- until they have a plot, and assign() calls it again from its own side.
		ExhibitService.refreshTreadmill(player)
		push(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		training[player] = nil
		lastPush[player] = nil
	end)

	Ticker.every(Tuning.TICK_RATE, step, "treadmill")
end

return TreadmillService
