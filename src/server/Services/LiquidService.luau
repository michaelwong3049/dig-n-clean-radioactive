--!strict
--[[
	LiquidService.lua — the wash pad. Step on it, roll a liquid, load the hose.

	THE ROLL IS AN EDGE, NOT AN ACTION, and that is the whole design. There is no
	"ROLL" button anywhere: `StationService.onChanged` tells this service the moment a
	player's feet arrive inside a `StationKind = "roller"` radius and the pad pays out
	right there. Stepping on a thing and having it go off is a five-year-old's idea of
	a good time, and a confirmation dialog in front of it would be worth exactly
	nothing. DeconService already sets this precedent — docking is an edge for the
	same reason — so the machinery for it exists and this file just subscribes.

	WHAT STOPS AN INFINITE RE-ROLL IS THE FEE, NOT THE COOLDOWN. Those two constants
	do genuinely different jobs and swapping them breaks the pad:

	  Tuning.LIQUID_ROLL_COST      the actual limiter. Without it, hopping on and off
	                               until Stardust lands is strictly optimal and every
	                               weight in Config/Liquids is decoration.
	  Tuning.LIQUID_ROLL_COOLDOWN  a debounce, nothing more. One roll per crossing
	                               would otherwise machine-gun the reveal animation.

	A PLAYER WHO CANNOT AFFORD A ROLL IS NOT STUCK. Plain Water is unlimited and
	always loaded (Config/Liquids), so a broke player cleans slowly rather than not at
	all. The pad says so out loud rather than silently doing nothing, because a pad
	that ignores you is indistinguishable from a pad that is broken.

	THE ODDS COME OUT OF THE SAME FUNCTION THE PANEL DISPLAYS. `Liquids.oddsAt` is
	shared, and `roll()` below walks `Liquids.ORDER` against `Liquids.effectiveWeight`
	— the same deterministic-order weighted walk `DigService.rollRarity` uses, for the
	same reason (`pairs()` order is not stable, and a weighted roll over an unstable
	order has unstable odds). A pad that advertises 1-in-40 and rolls 1-in-800 is the
	worst bug this feature could ship, and the only way to guarantee it cannot happen
	is for both numbers to be the same code.

	CHARGES ARE THE SCARCITY. A rolled liquid clears `def.charges` patches and then
	quietly reverts to water — see StatResolver.liquidFor, which is the single place
	"...unless it ran out" is written down. Stacking is capped at
	Tuning.LIQUID_MAX_STACK multiples so an idle player parked on the pad cannot
	accumulate an unbounded supply of the top of the table.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Liquids = require(Shared.Config.Liquids)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)

local LiquidService = {}

local stateRemote: any = nil
local rollRemote: any = nil
local resultRemote: any = nil

--- Last roll time per player, for the debounce. Wall clock rather than a tick
--- counter: this is a "how long since a human did a thing" question, and nothing
--- else in this file runs on the Ticker at all.
local lastRoll: { [Player]: number } = {}
local lastSignature: { [Player]: string } = {}

-- ── Rolling ───────────────────────────────────────────────────────────

--- Deterministic-order weighted pick, mirroring DigService.rollRarity. Walks
--- `Liquids.ORDER` rather than the DEFS table so the odds cannot drift with
--- whatever order Lua feels like handing back today.
local function roll(luck: number): string
	local total = 0
	for _, id in Liquids.ORDER do
		total += Liquids.effectiveWeight(Liquids.DEFS[id], luck)
	end

	if total <= 0 then
		-- Every rollable liquid has weight 0, which means somebody emptied the
		-- catalogue. Water is still a correct answer, so degrade rather than error:
		-- this runs off a movement edge and an error here would fire every time
		-- anyone walked over the pad.
		return Liquids.WATER
	end

	local pick = math.random() * total
	for _, id in Liquids.ORDER do
		local weight = Liquids.effectiveWeight(Liquids.DEFS[id], luck)
		if weight > 0 then
			pick -= weight
			if pick <= 0 then
				return id
			end
		end
	end

	-- Floating-point undershoot on the last entry. Take the commonest rollable
	-- liquid rather than water: the player paid, so they get something.
	for _, id in Liquids.ORDER do
		if Liquids.isRollable(id) then
			return id
		end
	end
	return Liquids.WATER
end

--- Pay for and perform one roll. Returns the liquid id, or nil plus a reason.
local function pull(player: Player, data: any): (string?, string?)
	local now = os.clock()
	local previous = lastRoll[player]
	if previous and now - previous < Tuning.LIQUID_ROLL_COOLDOWN then
		return nil, "the pad is still resetting"
	end

	if data.cash < Tuning.LIQUID_ROLL_COST then
		return nil, `the pad takes ${Tuning.LIQUID_ROLL_COST} \u{2014} you're still on Plain Water`
	end

	data.cash -= Tuning.LIQUID_ROLL_COST
	EconomyService.pushCash(player)
	lastRoll[player] = now

	local stats = StatResolver.get(data)
	local id = roll(stats.luckMultiplier)
	local def = Liquids.get(id)

	-- Stacking, capped. A repeat roll of something you already hold tops it up
	-- rather than replacing it, which is what makes the common end of the table
	-- feel like a consolation prize instead of a wasted fee.
	local ceiling = def.charges * Tuning.LIQUID_MAX_STACK
	local held = data.liquids[id] or 0
	data.liquids[id] = math.min(held + def.charges, ceiling)

	data.stats.rolls = (data.stats.rolls or 0) + 1

	-- Auto-equip anything strictly better than what is loaded. A player who rolls
	-- Stardust and then has to find the equip button before it means anything has
	-- had the moment taken off them. Rolling something WORSE never silently
	-- downgrades you -- that would be a punishment for engaging with the pad.
	local _, current = LiquidService.equipped(data)
	if def.order > current.order then
		data.equippedLiquid = id
	end

	return id, nil
end

-- ── Reading ───────────────────────────────────────────────────────────

--- The loaded liquid: its id and its definition. Thin delegate over StatResolver so
--- callers do not each re-derive "equipped, unless the charges ran out".
function LiquidService.equipped(data: any): (string, Liquids.LiquidDef)
	local stats = StatResolver.get(data)
	return stats.liquidId, Liquids.get(stats.liquidId)
end

--- Spend one charge against the loaded liquid. Called once per cleared patch.
--- Water is unlimited, so this is a no-op on the floor — which is what makes
--- "always able to clean something" true rather than aspirational.
function LiquidService.spendCharge(data: any): ()
	local id = LiquidService.equipped(data)
	if id == Liquids.WATER then
		return
	end

	local left = (data.liquids[id] or 0) - 1
	if left <= 0 then
		-- Drop the key rather than storing a 0. An empty table is exactly the "on
		-- water" state DataService's TEMPLATE documents, and leaving zeroed entries
		-- behind would grow the profile with rows the panel then has to filter.
		data.liquids[id] = nil
		data.equippedLiquid = ""
	else
		data.liquids[id] = left
	end
end

--- Everything the roll pad's panel draws: what is on the shelf, what is loaded,
--- and the live odds at this player's current luck.
function LiquidService.viewFor(data: any): any
	local stats = StatResolver.get(data)
	local odds = Liquids.oddsAt(stats.luckMultiplier)

	local shelf: { any } = {}
	for _, id in Liquids.ORDER do
		local def = Liquids.DEFS[id]
		if def.weight <= 0 then
			continue
		end
		table.insert(shelf, {
			id = id,
			name = def.name,
			color = def.color,
			flavor = def.flavor,
			potency = def.potency,
			rateMult = def.rateMult,
			xpMult = def.xpMult,
			charges = def.charges,
			odds = odds[id] or 0,
			held = data.liquids[id] or 0,
		})
	end

	return {
		luck = stats.luckMultiplier,
		cost = Tuning.LIQUID_ROLL_COST,
		equipped = stats.liquidId,
		equippedName = Liquids.get(stats.liquidId).name,
		potency = stats.cleanPotency,
		effectivePotency = stats.effectivePotency,
		liquids = shelf,
	}
end

--- Fingerprints everything `viewFor` can render, so LiquidState fires on a real
--- change and not ten times a second. Same rule CarryService.signatureOf spells
--- out: anything the client draws has to be in here or it silently goes stale.
--- `luck` is in it because buying a Luck tier moves every odds figure on the panel
--- with nothing about the shelf itself having moved.
local function signatureOf(data: any, stats: any): string
	local parts = { stats.liquidId, string.format("%.4f", stats.luckMultiplier), tostring(data.cash >= Tuning.LIQUID_ROLL_COST) }
	for _, id in Liquids.ORDER do
		table.insert(parts, `{id}:{data.liquids[id] or 0}`)
	end
	return table.concat(parts, "|")
end

function LiquidService.push(player: Player)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local stats = StatResolver.get(data)
	local signature = signatureOf(data, stats)
	if lastSignature[player] == signature then
		return
	end
	lastSignature[player] = signature
	stateRemote:FireClient(player, LiquidService.viewFor(data))
end

-- ── Actions ───────────────────────────────────────────────────────────

--- Load a canister into the hose. "" and "water" both mean the floor, and both are
--- always allowed — a player must be able to put the good stuff away and save it.
function LiquidService.equip(player: Player, id: string): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "no profile"
	end

	if id == "" or id == Liquids.WATER then
		data.equippedLiquid = ""
		return true, "loaded Plain Water"
	end

	if not Liquids.isRollable(id) then
		return false, "no such liquid"
	end
	if (data.liquids[id] or 0) <= 0 then
		return false, `you have no {Liquids.get(id).name} left`
	end

	data.equippedLiquid = id
	return true, `loaded {Liquids.get(id).name}`
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

function LiquidService.init()
	stateRemote = Net.get("LiquidState")
	rollRemote = Net.get("LiquidRoll")
	resultRemote = Net.get("StationResult")
end

function LiquidService.start()
	StationService.onChanged(function(player, kind)
		if kind ~= "roller" then
			return
		end

		local data = DataService.data(player)
		if data == nil then
			return
		end

		local id, refusal = pull(player, data)
		if id == nil then
			resultRemote:FireClient(player, refusal)
			return
		end

		local def = Liquids.get(id)
		rollRemote:FireClient(player, {
			id = id,
			name = def.name,
			color = def.color,
			flavor = def.flavor,
			potency = def.potency,
			rateMult = def.rateMult,
			xpMult = def.xpMult,
			charges = def.charges,
			held = data.liquids[id] or 0,
			equipped = data.equippedLiquid == id,
		})
		print(`[liquid] {player.Name} rolled {def.name}`)
	end)

	-- PUSHED ON THE TICK, GATED BY THE SIGNATURE — the CarryService pattern, and
	-- chosen over calling push() from each mutation site for one specific reason:
	-- the panel shows whether you can AFFORD a roll, and cash moves from six places
	-- (a sale, a shop, an exhibit payout, three debug commands) that have no reason
	-- to know this service exists. A tick that almost always compares one string and
	-- returns is cheaper than the bug where one of those six forgets.
	Ticker.every(Tuning.TICK_RATE, function()
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(LiquidService.push, player)
			if not ok then
				warn(`[liquid] push failed for {player.Name}: {err}`)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRoll[player] = nil
		lastSignature[player] = nil
	end)
end

return LiquidService
