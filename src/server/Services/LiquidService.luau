--!strict
--[[
	LiquidService.lua — the fluid bottle and its panel. Roll for a fluid, load the hose,
	upgrade Luck.

	THE WASH PAD IS GONE, on request. It was a step-on pressure plate across the aisle
	that charged a fee per roll and flashed the result on its own sign. The mechanic
	is simpler now and lives next to the tub it feeds: a big glass bottle beside the
	washer (build/Plots.buildFluidBottle), full of whatever fluid is loaded. Walk up to
	your own and a panel opens on your screen (the client's LiquidController) showing
	the loaded fluid, a ROLL button and the Luck upgrade (which used to be a lever out
	on the floor). ROLL plays a spin that lands on a fluid; when it lands, the bottle
	recolours to match. Both buttons send FluidAction, and the server checks the player
	is actually standing at their own bottle before doing anything.

	FREE, AND THE COOLDOWN IS THE ONLY LIMITER. Tuning.LIQUID_SPIN_COOLDOWN, per player.
	There is no fee and no first-spin-free special case. While it runs, the panel's
	ROLL button counts down, so the answer to "why won't it spin" is on the button.
	The cooldown is per server session
	-- rejoining resets it, which costs at most one early spin and is not worth a
	profile field.

	ONLY THE OWNER USES THEIR OWN BOTTLE. The bottle wears its owner's fluid, so a
	visitor rolling at it would change their own hose while the bottle went on showing
	someone else's. The panel only opens at your own, and the server resolves "your
	bottle" from your plot, never from the client.

	THE ODDS ARE UNCHANGED. `roll()` below is the same deterministic-order weighted walk
	`DigService.rollRarity` uses, sampled against `Liquids.effectiveWeight` at the
	player's luck, and `/odds` prints the same table from `Liquids.oddsAt`. The reel the
	client scrolls through is made of real rolls too, so the fluids that flash past most
	are the ones that actually come up most.

	CHARGES ARE THE SCARCITY. A spun liquid clears `def.charges` patches and then
	quietly reverts to water — see StatResolver.liquidFor, which is the single place
	"...unless it ran out" is written down. Stacking is capped at
	Tuning.LIQUID_MAX_STACK multiples so a player who spins every minute cannot
	accumulate an unbounded supply of the top of the table.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Liquids = require(Shared.Config.Liquids)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)
local Gear = require(Shared.Config.Gear)
local Crates = require(Shared.Config.Crates)

local DataService = require(script.Parent.DataService)
local ExhibitService = require(script.Parent.ExhibitService)
local ShopService = require(script.Parent.ShopService)

local LiquidService = {}

--- build/Kit.FLUID_TAG. Not required from build/ — Services never depend on it (see
--- ExhibitService's PLOT_COUNT) — so the string is repeated, and World.verify()
--- asserts every plot has a bottle carrying it.
local FLUID_TAG = "FluidSpin"

local stateRemote: any = nil
local spinRemote: any = nil
local actionRemote: any = nil

--- Last spin time per player, for the cooldown. Wall clock rather than a tick counter:
--- this is a "how long since a human did a thing" question.
local lastSpin: { [Player]: number } = {}
local lastSignature: { [Player]: string } = {}
--- Set while a player's spin is still playing on their screen. The bottle holds its
--- old colour until the spin lands, so the world behind the popup does not give the
--- result away first.
local spinning: { [Player]: boolean } = {}

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
		-- catalogue. Water is still a correct answer, so degrade rather than error.
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
	-- liquid rather than water: a spin always pays out something.
	for _, id in Liquids.ORDER do
		if Liquids.isRollable(id) then
			return id
		end
	end
	return Liquids.WATER
end

--- How many fluids scroll past before the one the spin lands on, and how many sit
--- after it so the window is never empty at the end. The client centres the reel on
--- `REEL_LAND`.
local REEL_LAND = 28
local REEL_TAIL = 4

--- The strip the client scrolls through: real rolls at this luck, with the result
--- dropped in at REEL_LAND. Rolled rather than drawn uniformly so the reel teaches the
--- odds the same way the old pad's jars did -- the common fluids flash past often, the
--- rare ones once in a while.
local function reelFor(luck: number, result: string): { string }
	local reel = table.create(REEL_LAND + REEL_TAIL)
	for i = 1, REEL_LAND + REEL_TAIL do
		reel[i] = if i == REEL_LAND then result else roll(luck)
	end
	return reel
end

--- Seconds left on a player's cooldown, 0 when a spin is ready.
function LiquidService.cooldownLeft(player: Player): number
	local previous = lastSpin[player]
	if previous == nil then
		return 0
	end
	return math.max(0, Tuning.LIQUID_SPIN_COOLDOWN - (os.clock() - previous))
end

--- Put one roll's worth of `id` in the player's hose. Shared by the bottle and the
--- liquid crates (CrateService) so both stack and auto-load the same way.
local function grant(data: any, id: string)
	local def = Liquids.get(id)

	-- Stacking, capped. A repeat spin of something you already hold tops it up rather
	-- than replacing it, which is what makes the common end of the table feel like a
	-- consolation prize instead of a wasted spin.
	local ceiling = def.charges * Tuning.LIQUID_MAX_STACK
	local held = data.liquids[id] or 0
	data.liquids[id] = math.min(held + def.charges, ceiling)

	-- Auto-equip anything strictly better than what is loaded. Spinning something
	-- WORSE never silently downgrades you -- that would be a punishment for spinning.
	local _, current = LiquidService.equipped(data)
	if def.order > current.order then
		data.equippedLiquid = id
	end
end

--- Perform one spin. Returns the liquid id, or nil plus a reason. Refusal strings are
--- kept SHORT because they are shown on the bottle's own sign.
local function pull(player: Player, data: any): (string?, string?)
	local left = LiquidService.cooldownLeft(player)
	if left > 0 then
		return nil, `ready in {math.ceil(left)}s`
	end
	lastSpin[player] = os.clock()

	local stats = StatResolver.get(data)
	local id = roll(stats.luckMultiplier)
	grant(data, id)
	data.stats.rolls = (data.stats.rolls or 0) + 1
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
		-- water" state DataService's TEMPLATE documents.
		data.liquids[id] = nil
		data.equippedLiquid = ""
	else
		data.liquids[id] = left
	end
end

--- Everything the fluid panel draws. `cooldown` is seconds left as of now; the client
--- counts it down itself, and a push lands again the moment it reaches zero (the
--- signature carries readiness), so the two never drift far.
local function stateFor(player: Player, data: any): any
	local stats = StatResolver.get(data)
	local level = data.gear.luck or 1
	return {
		liquid = stats.liquidId,
		held = data.liquids[stats.liquidId] or 0,
		cooldown = LiquidService.cooldownLeft(player),
		luck = Gear.luckMultiplier(level),
		-- What `roll()` actually sees: bought luck times any boost. The panel prices
		-- its "next +0.1x" jackpot line off this so the odds it shows are the real ones.
		rollLuck = stats.luckMultiplier,
		luckLevel = level,
		luckPrice = Gear.luckPrice(level),
		boost = stats.luckBoost,
	}
end

--- Fingerprints everything the bottle and the panel show, so they repaint on a real
--- change and not ten times a second. Same rule CarryService.signatureOf spells out:
--- anything drawn has to be in here or it silently goes stale.
local function signatureOf(player: Player, data: any, stats: any): string
	local parts = {
		stats.liquidId,
		tostring(data.gear.luck or 1),
		tostring(stats.luckBoost),
		tostring(stats.luckMultiplier),
		tostring(LiquidService.cooldownLeft(player) > 0),
	}
	for _, id in Liquids.ORDER do
		table.insert(parts, `{id}:{data.liquids[id] or 0}`)
	end
	return table.concat(parts, "|")
end

--- Repaint the owner's bottle and push their panel state, only on a real change. What
--- moves them: a roll, a charge spent at the tub (a canister running dry turns the
--- bottle back to water), a Luck purchase, a luck boost starting or ending, and the
--- cooldown running out.
function LiquidService.push(player: Player, notice: string?)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local stats = StatResolver.get(data)
	local signature = signatureOf(player, data, stats)
	if lastSignature[player] == signature and notice == nil then
		return
	end
	lastSignature[player] = signature
	local state = stateFor(player, data)
	state.notice = notice
	stateRemote:FireClient(player, state)
	if not spinning[player] then
		ExhibitService.refreshBottle(player)
	end
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

--- Which plot a bottle belongs to, read off the `Plot{n}` model it was built into.
local function plotIndexOf(part: Instance): number?
	local node: Instance? = part
	while node do
		local index = string.match(node.Name, "^Plot(%d+)$")
		if index and node:IsA("Model") then
			return tonumber(index)
		end
		node = node.Parent
	end
	return nil
end

--- The player's own bottle, or nil if they have no plot (or a world built before the
--- bottle existed).
local function bottleOf(player: Player): BasePart?
	local index = ExhibitService.plotOf(player)
	if index == nil then
		return nil
	end
	for _, part in CollectionService:GetTagged(FLUID_TAG) do
		if part:IsA("BasePart") and plotIndexOf(part) == index then
			return part
		end
	end
	return nil
end

--- How far from the bottle the server still accepts a panel action. The client opens
--- the panel inside LiquidController's PANEL_REACH; this is that plus slack for
--- latency, so a player who is visibly at the table is never refused.
local ACTION_REACH = 12

--- Is the player standing at their own bottle? The panel is only ever shown there,
--- but the remote is a client's claim, so the server checks for itself.
local function atBottle(player: Player): boolean
	local bottle = bottleOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if bottle == nil or root == nil or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - bottle.Position).Magnitude <= ACTION_REACH
end

--- ROLL: spin, tell the client to play it, and recolour the bottle once it lands.
local function spin(player: Player, data: any)
	local id, refusal = pull(player, data)
	if id == nil then
		LiquidService.push(player, refusal)
		return
	end

	local def = Liquids.get(id)
	local loaded = LiquidService.equipped(data)
	spinning[player] = true
	spinRemote:FireClient(player, {
		reel = reelFor(StatResolver.get(data).luckMultiplier, id),
		land = REEL_LAND,
		seconds = Tuning.LIQUID_SPIN_SECONDS,
		result = id,
		held = data.liquids[id] or 0,
		loaded = loaded,
	})
	print(`[liquid] {player.Name} spun {def.name}`)
	LiquidService.push(player)

	task.delay(Tuning.LIQUID_SPIN_SECONDS, function()
		spinning[player] = nil
		if player.Parent then
			ExhibitService.refreshBottle(player)
		end
	end)
end

--- OPEN A LIQUID CRATE (Config/Crates). Rolls off the crate's floored table at the
--- player's fluid luck times the crate's, grants it exactly like a bottle roll, and
--- plays the SAME brew popup (FluidSpin) with a reel drawn from the crate's own odds,
--- so the fluids flashing past are the ones this crate can really give. Ignores the
--- bottle's cooldown: the crate is what you paid. Returns the liquid id.
function LiquidService.openCrate(player: Player, data: any, crateId: string): string
	local playerLuck = StatResolver.get(data).luckMultiplier
	local id = Crates.rollLiquid(crateId, playerLuck, math.random())
	grant(data, id)

	local reel = table.create(REEL_LAND + REEL_TAIL)
	for i = 1, REEL_LAND + REEL_TAIL do
		reel[i] = if i == REEL_LAND then id else Crates.rollLiquid(crateId, playerLuck, math.random())
	end

	spinning[player] = true
	spinRemote:FireClient(player, {
		reel = reel,
		land = REEL_LAND,
		seconds = Tuning.LIQUID_SPIN_SECONDS,
		result = id,
		held = data.liquids[id] or 0,
		loaded = LiquidService.equipped(data),
		crate = crateId,
	})
	print(`[liquid] {player.Name} opened a {Crates.get(crateId).name}: {Liquids.get(id).name}`)
	LiquidService.push(player)

	task.delay(Tuning.LIQUID_SPIN_SECONDS, function()
		spinning[player] = nil
		if player.Parent then
			ExhibitService.refreshBottle(player)
		end
	end)
	return id
end

--- UPGRADE LUCK: the same purchase the luck lever used to make (ShopService.buyLuck),
--- moved onto the panel on request. Luck weights the roll, so the button sits under
--- ROLL where you can see what you are buying odds for.
local function buyLuck(player: Player)
	local ok, message = ShopService.buyLuck(player)
	if ok then
		print(`[liquid] {player.Name}: {message}`)
		LiquidService.push(player)
	else
		LiquidService.push(player, message)
	end
end

local function onAction(player: Player, verb: any)
	if verb ~= "roll" and verb ~= "luck" then
		return
	end
	local data = DataService.data(player)
	if data == nil then
		return
	end
	if not atBottle(player) then
		LiquidService.push(player, "walk up to your bottle")
		return
	end
	if verb == "roll" then
		spin(player, data)
	else
		buyLuck(player)
	end
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

function LiquidService.init()
	stateRemote = Net.get("FluidState")
	spinRemote = Net.get("FluidSpin")
	actionRemote = Net.get("FluidAction")
end

function LiquidService.start()
	actionRemote.OnServerEvent:Connect(onAction)

	-- A returning player's bottle has to show their fluid, and plot assignment and
	-- data load race each other — refreshBottle is a no-op until they have a plot, and
	-- assign() renders it again from its own side.
	DataService.onLoaded(function(player)
		ExhibitService.refreshBottle(player)
		LiquidService.push(player)
	end)

	-- PUSHED ON THE TICK, GATED BY THE SIGNATURE — the CarryService pattern. Charges
	-- are spent from WashService mid-session, and a luck boost starts and ends in
	-- LuckBoostService; neither has any reason to know this service exists, and a tick
	-- that almost always compares one string and returns is cheaper than the bug where
	-- a caller forgets.
	Ticker.every(Tuning.TICK_RATE, function()
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(LiquidService.push, player)
			if not ok then
				warn(`[liquid] push failed for {player.Name}: {err}`)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSpin[player] = nil
		lastSignature[player] = nil
		spinning[player] = nil
	end)
end

return LiquidService
