--!strict
--[[
	Ticker.lua — the abstraction the whole game runs on.

	Exposure, the decay clock, exhibition yield and stamina are the same shape:

	    value += rate * dt   (clamped, with thresholds that fire events)

	Build that once, at a fixed step, and three of the four new systems in PLAN.md
	stop being new systems and become new *consumers*. That is why the decay clock
	(§3.6) and the exhibition (§8) are cheap to add once this file exists, and it is
	the main reason to build this layer before any gameplay.

	Fixed timestep, not delta-time-per-frame: rates in the design are all per-second,
	and a fixed step means a 15 FPS client and a 240 FPS client accumulate identically.
]]

local RunService = game:GetService("RunService")

local Ticker = {}
Ticker.__index = Ticker

export type Handle = {
	stop: (Handle) -> (),
	setPaused: (Handle, boolean) -> (),
	isPaused: (Handle) -> boolean,
	failures: (Handle) -> number,
}

local activeConnection: RBXScriptConnection? = nil
local subscribers: { any } = {}
local hasDead = false

-- One throwing subscriber used to take down every subscriber registered after it,
-- forever, because they all share this single Heartbeat connection. DigService is
-- 4th in the boot ORDER, so a single bad stage silently killed docking, scrubbing,
-- selling, tool-equipping and the debug console — server-wide, until restart.
--
-- Now a thrower is isolated and loud. It is warned about ONCE, not ten times a
-- second: a 10 Hz error spamming the output is how you lose the rest of the log,
-- which is the log you need to diagnose it.
local function runSubscriber(sub: any, step: number)
	local ok, err = pcall(sub.fn, step)
	if ok then
		return
	end

	sub.failures += 1
	if not sub.warned then
		sub.warned = true
		warn(`[ticker] subscriber "{sub.name}" errored and is now isolated: {err}`)
	end
end

local function ensureLoop(rateHz: number)
	if activeConnection then
		return
	end
	local step = 1 / rateHz
	local accumulator = 0

	activeConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		-- Cap catch-up so a hitch or a resumed-from-sleep server does not fire
		-- fifty ticks at once and blackout everybody. PLAN §3.1 is unforgiving
		-- enough without a scheduling bug helping it along.
		local maxSteps = 5
		local steps = 0
		while accumulator >= step and steps < maxSteps do
			accumulator -= step
			steps += 1
			-- Indexed, not generic-for: a subscriber is allowed to call stop() on
			-- itself or on anything else from inside its own callback, and that
			-- used to mutate this array mid-iteration.
			for index = 1, #subscribers do
				local sub = subscribers[index]
				if sub and not sub.paused and not sub.dead then
					runSubscriber(sub, step)
				end
			end
		end
		if steps >= maxSteps then
			accumulator = 0
		end

		-- Compact outside the iteration, and only when something actually died.
		if hasDead then
			hasDead = false
			for index = #subscribers, 1, -1 do
				if subscribers[index].dead then
					table.remove(subscribers, index)
				end
			end
			if #subscribers == 0 and activeConnection then
				activeConnection:Disconnect()
				activeConnection = nil
			end
		end
	end)
end

--- Register a callback to run every fixed step. Returns a handle you must stop().
---
--- NOTE: the rate is set by the FIRST caller and every later subscriber inherits it.
--- That is fine today because everything runs at Tuning.TICK_RATE, but it means a
--- second rate passed here is silently ignored rather than honoured.
---
--- `name` is optional and only used to make a thrown error identifiable in the log.
function Ticker.every(rateHz: number, fn: (dt: number) -> (), name: string?): Handle
	ensureLoop(rateHz)

	local sub = {
		fn = fn,
		paused = false,
		dead = false,
		warned = false,
		failures = 0,
		name = name or "anonymous",
	}
	table.insert(subscribers, sub)

	local handle = setmetatable({}, Ticker)
	handle._sub = sub
	return (handle :: any) :: Handle
end

--- Safe to call from inside a tick callback — the entry is flagged here and swept
--- after the iteration finishes, never removed underneath the loop.
function Ticker:stop()
	if self._sub.dead then
		return
	end
	self._sub.dead = true
	hasDead = true
end

--- How many times this subscriber has thrown. Zero for a healthy one.
function Ticker:failures(): number
	return self._sub.failures
end

function Ticker:setPaused(paused: boolean)
	self._sub.paused = paused
end

function Ticker:isPaused(): boolean
	return self._sub.paused
end

--- A single clamped accumulator with threshold callbacks — the exposure meter,
--- a stamina bar, a fuse, anything with a 0..max range and states along the way.
export type Meter = {
	value: number,
	max: number,
	add: (Meter, amount: number) -> string?,
	fraction: (Meter) -> number,
	reset: (Meter) -> (),
}

local Meter = {}
Meter.__index = Meter

--- thresholds: array of { at = 0..1, name = "danger" }, ascending.
function Ticker.meter(max: number, thresholds: { { at: number, name: string } }?): Meter
	local self = setmetatable({}, Meter)
	self.value = 0
	self.max = max
	self._thresholds = thresholds or {}
	self._lastBand = nil
	return (self :: any) :: Meter
end

--- Returns the threshold name if the meter CROSSED into a new band this call.
function Meter:add(amount: number): string?
	self.value = math.clamp(self.value + amount, 0, self.max)
	local frac = self.value / self.max

	local band = nil
	for _, t in self._thresholds do
		if frac >= t.at then
			band = t.name
		end
	end

	if band ~= self._lastBand then
		self._lastBand = band
		return band
	end
	return nil
end

function Meter:fraction(): number
	return self.value / self.max
end

function Meter:reset()
	self.value = 0
	self._lastBand = nil
end

return Ticker
