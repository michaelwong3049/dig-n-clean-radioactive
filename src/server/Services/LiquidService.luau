--!strict
--[[
	LiquidService.lua — the fluid bottle. Press E on it, spin for a fluid, load the hose.

	THE WASH PAD IS GONE, on request. It was a step-on pressure plate across the aisle
	that charged a fee per roll and flashed the result on its own sign. The mechanic
	is simpler now and lives next to the tub it feeds: a big glass bottle beside the
	washer (build/Plots.buildFluidBottle), full of whatever fluid is loaded. Press E on
	it and a spin plays on your screen (the client's LiquidController), landing on a
	fluid; when it lands, the bottle recolours to match.

	FREE, AND THE COOLDOWN IS THE ONLY LIMITER. Tuning.LIQUID_SPIN_COOLDOWN, per player.
	There is no fee and no first-spin-free special case. While it runs, the owner's
	bottle prompt counts down in its own ActionText ("Ready in 42s"), so the answer to
	"why won't it spin" is on the bottle rather than in a toast that has no panel to
	render into (station-result-toast-needs-panel). The cooldown is per server session
	-- rejoining resets it, which costs at most one early spin and is not worth a
	profile field.

	ONLY THE OWNER SPINS THEIR OWN BOTTLE. The bottle wears its owner's fluid, so a
	visitor spinning it would change their own hose while the bottle went on showing
	someone else's. The plot is read off the bottle's own ancestry (the `Plot{n}` model
	it was built into), not from where the player happens to be standing.

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

local DataService = require(script.Parent.DataService)
local ExhibitService = require(script.Parent.ExhibitService)

local LiquidService = {}

--- build/Kit.FLUID_TAG. Not required from build/ — Services never depend on it (see
--- ExhibitService's PLOT_COUNT) — so the string is repeated, and World.verify()
--- asserts every plot has a bottle carrying it.
local FLUID_TAG = "FluidSpin"

local spinRemote: any = nil

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
	local def = Liquids.get(id)

	-- Stacking, capped. A repeat spin of something you already hold tops it up rather
	-- than replacing it, which is what makes the common end of the table feel like a
	-- consolation prize instead of a wasted spin.
	local ceiling = def.charges * Tuning.LIQUID_MAX_STACK
	local held = data.liquids[id] or 0
	data.liquids[id] = math.min(held + def.charges, ceiling)

	data.stats.rolls = (data.stats.rolls or 0) + 1

	-- Auto-equip anything strictly better than what is loaded. Spinning something
	-- WORSE never silently downgrades you -- that would be a punishment for spinning.
	local _, current = LiquidService.equipped(data)
	if def.order > current.order then
		data.equippedLiquid = id
	end

	return id, nil
end

-- ── The bottle answers a refusal for itself ────────────────────────────

--- How long a refusal stays on the bottle's sign before it settles back.
local REFUSAL_SECONDS = 3
--- Amber, because "not yet" is information, not an error.
local REFUSAL_HEX = "F2B134"

local refusalToken: { [BasePart]: number } = {}

--- Put a refusal on the bottle's own sign for a few seconds: the subtitle turns amber
--- and says why nothing happened. SERVER-SIDE ON PURPOSE -- the bottle is a physical
--- thing, and a physical thing answers on itself, not on a screen.
---
--- The subtitle's resting colour is the plot's accent, which Plots.setPlotAccent can
--- repaint at any time, so it is captured when the first of a run of flashes starts
--- and put back after the last one; the resting TEXT is not remembered at all, it is
--- re-rendered from the plot owner's profile (ExhibitService.refreshBottleAt), because
--- the fluid it names can change while the refusal is up.
local function flashRefusal(bottle: BasePart, index: number?, text: string)
	local sign = bottle:FindFirstChild("Sign")
	local subtitle = sign and sign:FindFirstChild("Subtitle")
	if subtitle == nil or not subtitle:IsA("TextLabel") then
		return
	end

	local token = (refusalToken[bottle] or 0) + 1
	refusalToken[bottle] = token
	if subtitle:GetAttribute("RestColor") == nil then
		subtitle:SetAttribute("RestColor", subtitle.TextColor3)
	end
	subtitle.Text = text
	subtitle.TextColor3 = Color3.fromHex(REFUSAL_HEX)

	task.delay(REFUSAL_SECONDS, function()
		if refusalToken[bottle] ~= token or subtitle.Parent == nil then
			return -- a newer refusal owns the sign now
		end
		local rest = subtitle:GetAttribute("RestColor")
		if typeof(rest) == "Color3" then
			subtitle.TextColor3 = rest
		end
		subtitle:SetAttribute("RestColor", nil)
		if index then
			ExhibitService.refreshBottleAt(index)
		end
	end)
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

--- Fingerprints everything the bottle shows, so it repaints on a real change and not
--- ten times a second. Same rule CarryService.signatureOf spells out: anything drawn
--- has to be in here or it silently goes stale.
local function signatureOf(data: any, stats: any): string
	local parts = { stats.liquidId, string.format("%.4f", stats.luckMultiplier) }
	for _, id in Liquids.ORDER do
		table.insert(parts, `{id}:{data.liquids[id] or 0}`)
	end
	return table.concat(parts, "|")
end

--- Repaint the owner's bottle, only on a real change. Two things move it: a spin, and
--- a charge spent at the tub (the bottle's subtitle counts washes left, and a canister
--- running dry turns it back to water).
---
--- THERE USED TO BE A LiquidState REMOTE HERE feeding the wash pad's per-player
--- readout. The bottle's colour and sign replaced that readout, and a remote nobody
--- listens to queues on the client, so it went with the pad.
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

--- The owner pressed E on their bottle: spin, tell their client to play it, and
--- recolour the bottle once it lands.
function LiquidService.spin(player: Player, bottle: BasePart)
	local data = DataService.data(player)
	if data == nil then
		return
	end

	local index = plotIndexOf(bottle)
	if index == nil or ExhibitService.plotOf(player) ~= index then
		flashRefusal(bottle, index, "not your bottle")
		return
	end

	local id, refusal = pull(player, data)
	if id == nil then
		flashRefusal(bottle, index, tostring(refusal))
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

	task.delay(Tuning.LIQUID_SPIN_SECONDS, function()
		spinning[player] = nil
		if player.Parent then
			ExhibitService.refreshBottle(player)
		end
	end)
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

--- Connect one bottle's prompt. Built by build/Plots.buildFluidBottle and saved with
--- the place; wired here at boot, the same build-time/runtime split every prompt in
--- the world uses.
local function wireBottle(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if prompt == nil then
		warn(`[liquid] {part:GetFullName()} is tagged as a fluid bottle but has no ProximityPrompt — nobody can spin it`)
		return
	end
	prompt.Triggered:Connect(function(player: Player)
		LiquidService.spin(player, part)
	end)
end

--- The owner's bottle prompt counts their cooldown down. The prompt is one shared
--- instance, but only the owner can use it, so the owner's clock is the right one to
--- show everybody. Written only on a change, so it is one string compare per plot per
--- tick at rest.
local function paintCountdown(player: Player)
	local index = ExhibitService.plotOf(player)
	if index == nil then
		return
	end
	for _, part in CollectionService:GetTagged(FLUID_TAG) do
		if plotIndexOf(part) == index then
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				local left = LiquidService.cooldownLeft(player)
				local text = if left > 0 then `Ready in {math.ceil(left)}s` else "Spin Fluid"
				if prompt.ActionText ~= text then
					prompt.ActionText = text
				end
			end
		end
	end
end

function LiquidService.init()
	spinRemote = Net.get("FluidSpin")
end

function LiquidService.start()
	-- Tag-indexed and live, not a one-shot Workspace walk: World.rebuild() can be run
	-- from the command bar mid-session and a bottle built then would otherwise sit
	-- inert until the next server start.
	for _, part in CollectionService:GetTagged(FLUID_TAG) do
		wireBottle(part)
	end
	CollectionService:GetInstanceAddedSignal(FLUID_TAG):Connect(wireBottle)

	-- A returning player's bottle has to show their fluid, and plot assignment and
	-- data load race each other — refreshBottle is a no-op until they have a plot, and
	-- assign() renders it again from its own side.
	DataService.onLoaded(function(player)
		ExhibitService.refreshBottle(player)
	end)

	-- PUSHED ON THE TICK, GATED BY THE SIGNATURE — the CarryService pattern. Charges
	-- are spent from WashService mid-session and have no reason to know this service
	-- exists; a tick that almost always compares one string and returns is cheaper
	-- than the bug where a caller forgets.
	Ticker.every(Tuning.TICK_RATE, function()
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(LiquidService.push, player)
			if not ok then
				warn(`[liquid] push failed for {player.Name}: {err}`)
			end
			ok, err = pcall(paintCountdown, player)
			if not ok then
				warn(`[liquid] countdown failed for {player.Name}: {err}`)
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
