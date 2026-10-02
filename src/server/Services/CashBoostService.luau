--!strict
--[[
	CashBoostService.luau — the 2x cash clock (Config/CashBoost), bought inside a pack.

	THIS SERVICE ONLY KEEPS THE CLOCK. StatResolver applies it, off `data.cashBoostLeft`,
	to sellMultiplier and yieldMultiplier, so a sale and a stand payout cannot disagree
	about whether you are boosted.

	It is LuckBoostService's clover clock, copied rather than shared because the two are
	sold, shown and tuned separately. Seconds banked on the profile; while the player is
	here they are held as an end time (`endsAt`) against the real clock and the saved
	seconds rewritten from it every tick, so a hitching server never boosts a player
	whose countdown has already hit zero. The same end time goes to the client as a
	Player attribute.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local CashBoost = require(Shared.Config.CashBoost)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)

local CashBoostService = {}

-- Player -> server time their boost runs out. Only players with time left.
local endsAt: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Always a number once loaded, 0 for none (LuckBoostService.publish's reason).
local function publish(player: Player)
	player:SetAttribute(CashBoost.PERSONAL_ATTR, endsAt[player] or 0)
end

--- Bank `seconds` more 2x cash on this player (negative takes it away). Mutates only
--- `data` and the in-memory clock and never yields: ProductService's grant contract.
function CashBoostService.grant(player: Player, data: any, seconds: number)
	local t = now()
	local ends = endsAt[player]
	local left = if ends then math.max(0, ends - t) else (data.cashBoostLeft or 0)
	left = math.clamp(left + seconds, 0, CashBoost.MAX_BANKED_SECONDS)
	data.cashBoostLeft = left
	endsAt[player] = if left > 0 then t + left else nil
	publish(player)
end

local function onLoaded(player: Player, data: any)
	local left = data.cashBoostLeft or 0
	if left > 0 then
		endsAt[player] = now() + left
	end
	publish(player)
end

local function step()
	local t = now()
	for player, ends in endsAt do
		local data = DataService.data(player)
		if data == nil then
			continue
		end
		local left = math.max(0, ends - t)
		data.cashBoostLeft = left
		if left <= 0 then
			endsAt[player] = nil
			publish(player)
		end
	end
end

function CashBoostService.start()
	DataService.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(function(player)
		endsAt[player] = nil
	end)
	Ticker.every(Tuning.TICK_RATE, step, "CashBoostService")
end

return CashBoostService
