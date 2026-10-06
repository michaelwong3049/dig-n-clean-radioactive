--!strict
--[[
	WeatherService.luau — the server-wide weather (Config/Weather).

	ONE CLOCK FOR EVERY WEATHER. Clear sky for Weather.GAP_MIN..MAX seconds, then one
	weather picked at random (Weather.pick, by weight) for its `seconds`, then clear
	again. The gap is measured from the moment the sky CLEARS, whatever cleared it --
	a rolled weather running out, a bought aurora, a debug stop -- so no weather ever
	shortens the quiet after it.

	IT APPLIES NOTHING ITSELF, the same split as LuckBoostService. Each weather is a
	pair of ReplicatedStorage attributes (start and end, server time); StatResolver
	reads Golden Hour off them for the cash multiplier, and every client paints the
	sky and the banner off them. The aurora's clock stays LuckBoostService's -- this
	file only says WHEN it starts.

	THE METEOR SHOWER is the one weather with work to do while it is up: METEOR_COUNT
	meteors over the shower (Weather.meteorAt). Each picks a random dig stage and an
	open point in it, tells every client (Net MeteorFall) so the streak can aim at the
	point, and METEOR_FALL_SECONDS later plants the spot there (DigService.plantMeteor).
	An undug spot sinks after METEOR_LIFETIME -- never out from under a magnet.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Weather = require(Shared.Config.Weather)
local Stages = require(Shared.Config.Stages)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DigService = require(script.Parent.DigService)
local LuckBoostService = require(script.Parent.LuckBoostService)

local WeatherService = {}

local rng = Random.new()

-- When the next weather rolls, once the sky is clear. 0 = roll a gap at the next clear tick.
local nextAt = 0
-- What was up on the last tick, so the tick that sees the sky clear can roll the gap.
local lastCurrent: string? = nil

-- The shower's state: how many meteors have fallen this shower, and when it began.
local meteorsFallen = 0
local showerStart = 0
-- Meteors in the air: the impact time, stage and point. Planted at `landsAt`.
type Fall = { stageId: number, position: Vector3, landsAt: number }
local falling: { Fall } = {}
-- Live meteor spots by uid -> when they sink.
local spots: { [string]: number } = {}

local fallRemote: any = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function scheduleNext(from: number)
	nextAt = from + rng:NextInteger(Weather.GAP_MIN, Weather.GAP_MAX)
end

-- ── Golden Hour / Meteor Shower clocks ────────────────────────────────────────

local function setClock(id: string, startsAt: number?, endsAt: number?)
	local def = Weather.get(id)
	ReplicatedStorage:SetAttribute(def.startAttr, startsAt)
	ReplicatedStorage:SetAttribute(def.endsAttr, endsAt)
end

--- End whatever weather is up, now. WeatherService's own two and the aurora alike.
function WeatherService.stop()
	if Weather.active("aurora") then
		LuckBoostService.stopEvent()
	end
	for _, id in { "golden", "meteor" } do
		if Weather.active(id) then
			setClock(id, nil, nil)
			print(`[weather] {Weather.get(id).name} is over`)
		end
	end
end

--- Start weather `id` now for `seconds` (its own length by default), ending any other
--- one first: there is only ever one sky.
function WeatherService.begin(id: string, seconds: number?)
	local def = Weather.get(id)
	local length = seconds or def.seconds
	WeatherService.stop()
	if id == "aurora" then
		LuckBoostService.startEvent(length)
		return
	end
	local t = now()
	if id == "meteor" then
		meteorsFallen = 0
		showerStart = t
	end
	-- The start first: the client banners on the END changing, and reads the start.
	setClock(id, t, t + length)
	print(`[weather] {def.name} is up for {math.floor(length)}s`)
end

--- Seconds until the next weather rolls, or 0 while one is up. For /weather.
function WeatherService.secondsToNext(): number
	if Weather.current() ~= nil then
		return 0
	end
	return math.max(0, nextAt - now())
end

-- ── Meteors ──────────────────────────────────────────────────────────────────

--- Send one meteor down: a random dig stage, an open point in it. False when no stage
--- has open ground this tick (the step simply tries again next tick).
function WeatherService.dropMeteor(stageId: number?): boolean
	local stages = DigService.digStages()
	if #stages == 0 then
		return false
	end
	local stage = stageId or stages[rng:NextInteger(1, #stages)]
	local position = DigService.meteorTarget(stage)
	if position == nil then
		return false
	end
	local landsAt = now() + Weather.METEOR_FALL_SECONDS
	table.insert(falling, { stageId = stage, position = position, landsAt = landsAt })
	fallRemote:FireAllClients({ position = position, landsAt = landsAt })
	print(`[weather] meteor falling into stage {stage} {Stages.get(stage).name}`)
	return true
end

local function stepMeteors(t: number)
	-- The shower's schedule. Only while it is up: an early stop drops the rest.
	if Weather.active("meteor") then
		while meteorsFallen < Weather.METEOR_COUNT and t - showerStart >= Weather.meteorAt(meteorsFallen + 1) do
			if not WeatherService.dropMeteor() then
				break
			end
			meteorsFallen += 1
		end
	end

	-- Impacts. A meteor already in the air lands even if the shower just ended.
	for i = #falling, 1, -1 do
		local fall = falling[i]
		if t >= fall.landsAt then
			table.remove(falling, i)
			local uid = DigService.plantMeteor(fall.stageId, fall.position)
			if uid then
				spots[uid] = t + Weather.METEOR_LIFETIME
			end
		end
	end

	-- Sinking. sinkMeteor refuses while someone is locked on; it is asked again next tick.
	for uid, sinksAt in spots do
		if t >= sinksAt and DigService.sinkMeteor(uid) then
			spots[uid] = nil
		end
	end
end

-- ── The clock ────────────────────────────────────────────────────────────────

local function step()
	local t = now()

	for _, id in { "golden", "meteor" } do
		local ends = ReplicatedStorage:GetAttribute(Weather.get(id).endsAttr)
		if type(ends) == "number" and t >= ends then
			setClock(id, nil, nil)
			print(`[weather] {Weather.get(id).name} is over`)
		end
	end

	local current = Weather.current()
	if current == nil and (lastCurrent ~= nil or nextAt == 0) then
		scheduleNext(t)
		if lastCurrent then
			print(`[weather] clear sky; next weather in {math.floor(nextAt - t)}s`)
		end
	end
	lastCurrent = current

	-- A bought aurora waiting on the sky goes first (LuckBoostService starts it).
	if current == nil and t >= nextAt and not LuckBoostService.hasQueued() then
		WeatherService.begin(Weather.pick(rng:NextNumber()))
		lastCurrent = Weather.current()
	end

	stepMeteors(t)
end

function WeatherService.init()
	fallRemote = Net.get("MeteorFall")
end

function WeatherService.start()
	Ticker.every(Tuning.TICK_RATE, step, "WeatherService")
end

return WeatherService
