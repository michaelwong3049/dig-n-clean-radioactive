--!strict
--[[
	TreadmillService.lua — the speed grind. Stand on a belt, get faster, forever.

	THE BELT IS A PLACE, NOT A BUTTON. There is no "start training" action and no
	session to open: `StationService.onChanged` says the moment a player's feet land
	inside a `StationKind = "treadmill"` radius, and from then until they step off,
	the tick loop below banks training. That is the same arrival edge the old wash
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

	WHAT THE UPGRADE BUYS is `rate` and `rated` (Config/Treadmill), not speed itself.
	Cash cannot buy a single point of walk speed anywhere in this game any more; it can
	only buy a belt that converts your time into speed less slowly. That is the entire
	reason the Boots track was retired — see Config/Treadmill's header — and it is the
	property to protect if anyone ever adds a gamepass here.

	THE SERVER OWNS THE CLOCK, as it does for the wash timer and the pull fuse. The
	client is told what its speed is; it never reports training. There is no remote in
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

--- The hard ceiling on banked training, in the same units `speedXp` is stored in.
--- Computed once: it is what MAX_SPEED costs, and clamping to it is what keeps a
--- number that only ever grows out of the save file's tail.
local XP_MAX = Treadmill.xpForSpeed(Treadmill.MAX_SPEED)

local stateRemote: any = nil
local resultRemote: any = nil

--- Who is standing on a belt right now. Written only by the StationService edge, so
--- it cannot drift from what the world thinks — and read by the tick loop as its
--- entire work list, which is why an empty camp costs nothing per tick.
local training: { [Player]: boolean } = {}

--- The last payload each player was sent, to keep the remote quiet when nothing has
--- moved. Keyed by player and cleared on leave; a string rather than a table so the
--- comparison is one equality test rather than a field-by-field walk.
local lastSignature: { [Player]: string } = {}

-- ── The readout ───────────────────────────────────────────────────────────

--- What this player's training is worth, as the client renders it.
---
--- `rate` is what they would earn per second ON A BELT — reported even when they are
--- not standing on one, because the number the HUD wants to show an idle player is
--- "this is what going back to the treadmill is worth", not zero. `training` is the
--- flag that says whether it is actually being paid right now.
---
--- `nextCost` is the price of the next RUNG, not of the next point of speed. Points
--- are not for sale (see the header).
local function snapshot(player: Player, data: any)
	local tier = math.clamp(math.floor(data.treadmill or 1), 1, Treadmill.maxTier())
	local speed, progress = Treadmill.speedFor(data.speedXp or 0)
	return {
		speed = speed,
		progress = progress,
		maxSpeed = Treadmill.MAX_SPEED,
		tier = tier,
		tierName = Treadmill.tier(tier).name,
		rated = Treadmill.tier(tier).rated,
		rate = Treadmill.rateFor(tier, speed),
		training = training[player] == true,
		nextCost = Treadmill.priceFor(tier),
	}
end

--- Fire SpeedState, but only if this player's readout actually changed.
---
--- The signature deliberately rounds `progress` to a thousandth. At the top of the
--- curve one tick of training moves the bar by about a millionth of a percent, and
--- without the rounding this would fire ten times a second, forever, for every AFK
--- player on the server — to redraw a bar that has not visibly moved. Three decimals
--- is finer than a pixel on any bar the client draws.
local function push(player: Player, force: boolean?)
	local data = DataService.data(player)
	if data == nil or stateRemote == nil then
		return
	end

	local state = snapshot(player, data)
	local signature = string.format(
		"%d|%.3f|%d|%s|%.3f",
		state.speed,
		state.progress,
		state.tier,
		tostring(state.training),
		state.rate
	)
	if not force and lastSignature[player] == signature then
		return
	end
	lastSignature[player] = signature
	stateRemote:FireClient(player, state)
end

-- ── Training ──────────────────────────────────────────────────────────────

--- One tick of banked training for every player currently standing on a belt.
---
--- THE RATE IS RE-RESOLVED EVERY TICK, against the speed they are at THIS instant
--- rather than the one they stepped on at. That matters at a band edge: crossing your
--- belt's `rated` speed mid-session has to start the falloff immediately, or a player
--- who parks at 39 on a belt rated for 40 trains the next twenty points at full rate
--- because nothing re-asked. It is the same reason ShopService refuses to cache gear
--- and ExposureService recomputes stats per tick — a number derived from live state is
--- cheaper to recompute than to invalidate.
local function step(dt: number)
	for player in training do
		local data = DataService.data(player)
		if data == nil then
			continue
		end

		local banked = data.speedXp or 0
		if banked >= XP_MAX then
			continue -- maxed; the belt still turns, it just has nothing left to teach
		end

		local tier = math.clamp(math.floor(data.treadmill or 1), 1, Treadmill.maxTier())
		local speed = Treadmill.speedFor(banked)
		local before = speed

		data.speedXp = math.min(banked + Treadmill.rateFor(tier, speed) * dt, XP_MAX)

		-- A crossed point is worth saying out loud in the log: it is the only moment
		-- in this whole feature where a number a player cares about changes, and it is
		-- otherwise invisible in a server that is doing nothing but idling.
		local after = Treadmill.speedFor(data.speedXp)
		if after > before then
			print(`[treadmill] {player.Name}: speed {before} -> {after}`)
		end
	end

	-- Trainees only. A player who steps OFF is no longer in this table, and does not
	-- need to be: the StationService edge that removed them already forced a final
	-- push to clear the `training` flag on their readout. An idle camp therefore costs
	-- exactly one empty loop per tick.
	for player in training do
		push(player)
	end
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
	push(player, true)
	return true, `{bought.name} installed — rated to speed {bought.rated} (paid ${price})`
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
			push(player, true)
		elseif previousKind == STATION_KIND then
			training[player] = nil
			push(player, true)
		end
	end)

	DataService.onLoaded(function(player)
		-- The belt on their own plot has to wear the rung they own, and plot assignment
		-- and data load race each other — ExhibitService.refreshTreadmill is a no-op
		-- until they have a plot, and assign() calls it again from its own side.
		ExhibitService.refreshTreadmill(player)
		push(player, true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		training[player] = nil
		lastSignature[player] = nil
	end)

	Ticker.every(Tuning.TICK_RATE, step, "treadmill")
end

return TreadmillService
