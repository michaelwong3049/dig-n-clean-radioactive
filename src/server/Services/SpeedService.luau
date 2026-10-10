--!strict
--[[
	SpeedService.lua — walk speed, bought at the Upgrades booth.

	The treadmill that used to train speed is gone (2026-10-09, on request). Walk speed is
	now `data.walkBought` on top of WalkSpeed.START_WALK (Config/WalkSpeed), and it is
	BOUGHT: the booth that was the Magnet Shop is the UPGRADES booth (Config/Booths), and
	its speed panel's BUY (client/SpeedPanel) fires Net.SpeedBuy.

	ONE PURCHASE = ONE STEP, and the step is set by the deepest stage reached
	(`data.stats.deepestStage`, WalkSpeed.stepFor): +1 in Stages 1-2 up to +6 in 11-12.
	The price is set by the walk bought so far (WalkSpeed.priceFor), so going deeper buys
	more speed for the same money. The +3 / +10 cash buttons buy exactly that much walk
	(WalkSpeed.bulkPriceFor).

	THE SERVER RE-DERIVES EVERYTHING. Net.SpeedBuy carries at most an amount, which must
	be one of WalkSpeed.BULK (nil = one step): the price and step come from the save, and
	the player must be standing at an Upgrades booth (StationService), not mid-tutorial,
	and able to pay.

	Robux: the panel's purple button is WalkSpeed.PRODUCT_ID (a flat +ROBUX_WALK walk),
	granted through ProductService. The Shop's walk-speed packs were retired 2026-10-10.

	SpeedState carries everything the client shows about speed: the HUD badge and walk
	picker (client SpeedController) and the booth's panel. It is pushed on load, on every
	change, and when the deepest stage moves (the step grows).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tutorial = require(Shared.Config.Tutorial)
local WalkSpeed = require(Shared.Config.WalkSpeed)
local Booths = require(Shared.Config.Booths)
local StatResolver = require(Shared.StatResolver)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local StationService = require(script.Parent.StationService)
local ProductService = require(script.Parent.ProductService)

local SpeedService = {}

local stateRemote: any = nil
local noticeRemote: any = nil

--- One cash press per player per this many seconds: a double click buys one step.
local BUY_COOLDOWN = 0.25
local lastBuy: { [Player]: number } = {}

--- The player attribute MasteryService publishes the deepest stage on.
local DEEPEST_ATTR = "DeepestStage"

local function deepestOf(data: any): number
	return tonumber(data.stats and data.stats.deepestStage) or 1
end

-- ── The readout ───────────────────────────────────────────────────────────

local function bulkPrices(bought: number, step: number): { number }
	local prices = {}
	for i, amount in WalkSpeed.BULK do
		prices[i] = WalkSpeed.bulkPriceFor(bought, amount, step)
	end
	return prices
end

--- This player's speed, as the client renders it.
local function snapshot(player: Player, data: any)
	local stats = StatResolver.get(data)
	local bought = WalkSpeed.bought(data.walkBought)
	local deepest = deepestOf(data)
	return {
		walk = WalkSpeed.walkFor(bought),
		-- The walk-speed picker's cap (0 = full speed). The HUD shows chosenWalk(walk, walkCap).
		walkCap = if type(data.walkCap) == "number" then data.walkCap else 0,
		-- Every walk-speed bonus as one fraction: the worn aura's, the Speed Potion's and
		-- the masteries' (StatResolver.walkBonus). The badge shows the chosen walk times
		-- (1 + this), which is what ExposureService really walks you at.
		auraSpeed = StatResolver.walkBonus(stats) - 1,
		-- The debug /speed pin, when set: the badge shows it in place of the chosen walk, with
		-- the aura bonus on top as for any speed (Lazy require: ExposureService reaches back here).
		override = require(script.Parent.ExposureService).speedOverrideOf(player),
		-- The Upgrades booth's next purchase.
		bought = bought,
		step = WalkSpeed.stepFor(deepest),
		price = WalkSpeed.priceFor(bought),
		-- The bulk buttons' prices, BULK[i] walk for bulkPrices[i].
		bulkPrices = bulkPrices(bought, WalkSpeed.stepFor(deepest)),
		deepestStage = deepest,
		upgrades = tonumber(data.stats and data.stats.speedUpgrades) or 0,
	}
end

local function push(player: Player)
	local data = DataService.data(player)
	if data == nil or stateRemote == nil then
		return
	end
	stateRemote:FireClient(player, snapshot(player, data))
end

--- Re-send this player's readout now: after anything that moves their walk speed or its
--- bonuses (a potion, an aura, /speed, a code, the group chest).
function SpeedService.refresh(player: Player)
	push(player)
end

-- ── Buying ────────────────────────────────────────────────────────────────

--- Add `amount` walk speed to the save. The one writer of `walkBought`, besides the save
--- conversion and /walk.
local function addWalk(data: any, amount: number)
	data.walkBought = WalkSpeed.bought(data.walkBought) + math.max(0, math.floor(amount))
end

--- One purchase for cash: one step, or exactly `amount` walk (one of WalkSpeed.BULK).
--- Price and step re-derived from the save; debit FIRST, and only touch the profile
--- once the debit lands. No standing check: onBuy does that.
function SpeedService.buy(player: Player, amount: number?): (boolean, string)
	local data = DataService.data(player)
	if data == nil then
		return false, "your save hasn't loaded"
	end
	local bought = WalkSpeed.bought(data.walkBought)
	local step = WalkSpeed.stepFor(deepestOf(data))
	local gain, price = step, WalkSpeed.priceFor(bought)
	if amount ~= nil then
		gain, price = amount, WalkSpeed.bulkPriceFor(bought, amount, step)
	end

	local paid, reason = EconomyService.spend(player, price)
	if not paid then
		return false, reason
	end

	addWalk(data, gain)
	data.stats.speedUpgrades = (tonumber(data.stats.speedUpgrades) or 0) + 1
	push(player)
	return true, `walk speed {WalkSpeed.walkFor(data.walkBought)} (+{gain}, paid {WalkSpeed.priceText(price)})`
end

--- Net.SpeedBuy: the speed panel's cash buttons, with an optional bulk `amount` that
--- must be one of WalkSpeed.BULK. At an Upgrades booth, not mid-tutorial.
local function onBuy(player: Player, amount: any)
	if amount ~= nil and not table.find(WalkSpeed.BULK, amount) then
		return
	end
	local now = os.clock()
	if now - (lastBuy[player] or 0) < BUY_COOLDOWN then
		return
	end
	lastBuy[player] = now

	if Tutorial.gated(player) then
		noticeRemote:FireClient(player, "FINISH THE TUTORIAL FIRST")
		return
	end
	if StationService.kindOf(player) ~= "shop" or not Booths.sellsSpeed(StationService.idOf(player)) then
		noticeRemote:FireClient(player, "WALK UP TO AN UPGRADES BOOTH", "info")
		return
	end

	local ok, message = SpeedService.buy(player, amount)
	noticeRemote:FireClient(player, string.upper(message), if ok then "success" else "error")
	if ok then
		print(`[speed] {player.Name}: {message}`)
	end
end

--- A purchase bought with Robux (WalkSpeed.PRODUCT_ID): a flat ROBUX_WALK, nothing
--- spent. Runs inside ProductService's receipt step, so it only touches `data` and never
--- yields; the readout follows in a deferred step.
local function grantRobuxUpgrade(player: Player, data: any)
	local step = WalkSpeed.ROBUX_WALK
	addWalk(data, step)
	data.stats.speedUpgrades = (tonumber(data.stats.speedUpgrades) or 0) + 1
	task.defer(function()
		if player.Parent == nil then
			return
		end
		push(player)
		noticeRemote:FireClient(player, `+{step} WALK SPEED`, "success")
	end)
end

--- Walk speed handed out by something other than a purchase (a code, the group chest).
--- Touches `data` only; the caller pushes with `refresh`.
function SpeedService.grantWalk(data: any, amount: number)
	addWalk(data, amount)
end

-- ── The walk-speed picker ───────────────────────────────────────────────────

--- Net.WalkCap. A number is the walk to cap at; 0, or anything at or over what they
--- own, saves as 0 = "always full speed", so the next purchase is felt at once instead
--- of being held back by an old pick. Always pushes back, so a refused pick snaps the
--- client's slider to what actually stuck.
local PICK_COOLDOWN = 0.2
local lastPick: { [Player]: number } = {}

local function onWalkCap(player: Player, picked: any)
	local data = DataService.data(player)
	if data == nil then
		return
	end
	local now = os.clock()
	if type(picked) == "number" and picked == picked and now - (lastPick[player] or 0) >= PICK_COOLDOWN then
		lastPick[player] = now
		local owned = WalkSpeed.walkFor(data.walkBought)
		local walk = math.floor(picked + 0.5)
		if walk <= 0 or walk >= owned then
			data.walkCap = 0
		else
			data.walkCap = math.max(walk, WalkSpeed.MIN_PICKED_WALK)
		end
	end
	push(player)
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

function SpeedService.init()
	stateRemote = Net.get("SpeedState")
	-- The hotbar popup ("INVENTORY FULL"): a bought or refused purchase is said here.
	noticeRemote = Net.get("Notice")
	-- In init, not start: ProductService.start() switches ProcessReceipt on, and a
	-- receipt landing before a product was registered would be bounced.
	ProductService.register(WalkSpeed.PRODUCT_ID, grantRobuxUpgrade)
end

function SpeedService.start()
	Net.get("SpeedBuy").OnServerEvent:Connect(onBuy)
	Net.get("WalkCap").OnServerEvent:Connect(onWalkCap)

	DataService.onLoaded(function(player)
		push(player)
		-- A deeper stage grows the step the booth sells: resend so its panel follows.
		player:GetAttributeChangedSignal(DEEPEST_ATTR):Connect(function()
			push(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastPick[player] = nil
		lastBuy[player] = nil
	end)
end

return SpeedService
