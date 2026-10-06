--!strict
--[[
	LuckBoostService.luau — 2x luck (Config/LuckBoost): the server-wide Violet Aurora
	and the Lucky Clover players buy from the Shop tile.

	THIS SERVICE ONLY KEEPS TWO CLOCKS. It applies nothing. StatResolver folds the
	boost into every luck number the game rolls against (`stats.luckBoost`, and
	`luckMultiplier` for the wash pad), reading exactly what is written here: the event
	off a ReplicatedStorage attribute, the clover off `data.luckBoostLeft`. So the dig
	roll, the wash pad and its displayed odds cannot disagree about whether you are
	lucky -- there is one answer and this file owns it.

	THE EVENT CLOCK. The aurora is one of three weathers now, and WHEN it comes is
	Services/WeatherService's call (Config/Weather: one weather at a time, picked at
	random after a quiet gap). This file still owns the aurora's own clock -- start,
	extend, stop, and the bought Server Luck Boost, which waits behind any other
	weather that is up (`queued`) rather than painting over it. Live on
	ReplicatedStorage as two attributes (the
	start and the end, in `workspace:GetServerTimeNow()` seconds): every client sees it
	the instant it changes, a late joiner sees it on arrival, and the client paints the
	sky and the clover's countdown straight off them (LuckBoostController).

	THE CLOVER CLOCK. Seconds BANKED on the profile, not an end time, so it only runs
	while the player is in a server. While they are here it is held as an end time
	(`endsAt`) against the real clock and the saved seconds are rewritten from it every
	tick -- not decremented by the tick's fixed step, which falls behind real time when
	the server hitches and would leave the server boosting a player whose countdown had
	already hit zero. The same end time goes to the client as a Player attribute.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local LuckBoost = require(Shared.Config.LuckBoost)
local Weather = require(Shared.Config.Weather)
local Ticker = require(Shared.Util.Ticker)

local DataService = require(script.Parent.DataService)
local ProductService = require(script.Parent.ProductService)
local CrateService = require(script.Parent.CrateService)

local LuckBoostService = {}

-- The event. `eventEndsAt` mirrors the attribute (0 = no event running) so the tick
-- does not read an attribute back to find out what it wrote itself.
local eventEndsAt = 0
-- Server Luck Boost seconds bought while another weather was up: the aurora starts
-- with them the moment that weather clears (step).
local queued = 0

-- Player -> server time their clover runs out. Only players with time left.
local endsAt: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- ── The Violet Aurora ────────────────────────────────────────────────────────

--- Start the aurora now, for `seconds` (EVENT_SECONDS by default). Restarting one
--- that is already up just moves its end.
function LuckBoostService.startEvent(seconds: number?)
	local t = now()
	if eventEndsAt <= t then
		ReplicatedStorage:SetAttribute(LuckBoost.EVENT_START_ATTR, t)
	end
	eventEndsAt = t + (seconds or LuckBoost.EVENT_SECONDS)
	ReplicatedStorage:SetAttribute(LuckBoost.EVENT_ATTR, eventEndsAt)
	print(`[luck] {LuckBoost.EVENT_NAME} is up: {LuckBoost.MULT}x luck for {math.floor(eventEndsAt - t)}s`)
end

--- Add `seconds` to the aurora (starting it if it is down), capped at
--- SERVER_MAX_SECONDS left. The Server Luck Boost product. Never yields. While another
--- weather is up the seconds are queued instead, and true comes back: the aurora
--- starts with them when that weather clears.
function LuckBoostService.extendEvent(seconds: number): boolean
	local t = now()
	local other = Weather.current()
	if eventEndsAt <= t and other ~= nil and other ~= "aurora" then
		queued = math.min(queued + seconds, LuckBoost.SERVER_MAX_SECONDS)
		return true
	end
	if eventEndsAt <= t then
		LuckBoostService.startEvent(seconds)
		return false
	end
	eventEndsAt = math.min(eventEndsAt + seconds, t + LuckBoost.SERVER_MAX_SECONDS)
	ReplicatedStorage:SetAttribute(LuckBoost.EVENT_ATTR, eventEndsAt)
	return false
end

--- End the aurora now. WeatherService rolls the quiet gap after it.
function LuckBoostService.stopEvent()
	eventEndsAt = 0
	ReplicatedStorage:SetAttribute(LuckBoost.EVENT_ATTR, nil)
	print(`[luck] {LuckBoost.EVENT_NAME} is over`)
end

--- Is a bought aurora waiting for the sky to clear? WeatherService holds its own roll
--- while one is, so the buyer's aurora is the next weather.
function LuckBoostService.hasQueued(): boolean
	return queued > 0
end

-- ── The Lucky Clover ─────────────────────────────────────────────────────────

-- Always a number once loaded, 0 for none: the client reads the first value it sees
-- as the baseline, and a nil -> nil "change" would never reach it.
local function publish(player: Player)
	player:SetAttribute(LuckBoost.PERSONAL_ATTR, endsAt[player] or 0)
end

--- Bank `seconds` more clover time on this player (negative takes it away). Mutates
--- only `data` and the in-memory clock and never yields, which is what
--- ProductService's grant contract asks for.
function LuckBoostService.grant(player: Player, data: any, seconds: number)
	local t = now()
	-- Off the running clock when there is one; off the save when there is not (a
	-- receipt can land in the moment between the profile loading and onLoaded below
	-- starting the clock, and must add to what is banked rather than replace it).
	local ends = endsAt[player]
	local left = if ends then math.max(0, ends - t) else (data.luckBoostLeft or 0)
	left = math.clamp(left + seconds, 0, LuckBoost.MAX_BANKED_SECONDS)
	data.luckBoostLeft = left
	endsAt[player] = if left > 0 then t + left else nil
	publish(player)
end

local function onLoaded(player: Player, data: any)
	local left = data.luckBoostLeft or 0
	if left > 0 then
		endsAt[player] = now() + left
	end
	publish(player)
end

local function step()
	local t = now()

	if eventEndsAt > 0 then
		if t >= eventEndsAt then
			LuckBoostService.stopEvent()
		end
	elseif queued > 0 and Weather.current() == nil then
		local seconds = queued
		queued = 0
		LuckBoostService.startEvent(seconds)
	end

	for player, ends in endsAt do
		local data = DataService.data(player)
		if data == nil then
			continue
		end
		local left = math.max(0, ends - t)
		data.luckBoostLeft = left
		if left <= 0 then
			endsAt[player] = nil
			publish(player)
		end
	end
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────

function LuckBoostService.init()
	-- In init, not start: ProductService.start() switches ProcessReceipt on, and a
	-- receipt landing before the clover was registered would be bounced.
	ProductService.register(LuckBoost.PRODUCT_ID, function(player, data)
		LuckBoostService.grant(player, data, LuckBoost.PRODUCT_SECONDS)
	end)
	ProductService.register(LuckBoost.SERVER_PRODUCT_ID, function(player)
		local waiting = LuckBoostService.extendEvent(LuckBoost.SERVER_SECONDS)
		local minutes = math.floor(LuckBoost.SERVER_SECONDS / 60)
		local current = Weather.current()
		local after = if waiting and current then ` after the {Weather.get(current).name}` else ""
		-- Deferred: the grant must not yield, and the notice is not part of the receipt.
		task.defer(function()
			for _, other in Players:GetPlayers() do
				CrateService.notify(other, `{player.DisplayName} boosted the server: {LuckBoost.MULT}x luck for {minutes} min{after}!`)
			end
		end)
	end)
end

function LuckBoostService.start()
	DataService.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(function(player)
		endsAt[player] = nil
	end)
	Ticker.every(Tuning.TICK_RATE, step, "LuckBoostService")
end

return LuckBoostService
