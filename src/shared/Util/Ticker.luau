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
}

local activeConnection: RBXScriptConnection? = nil
local subscribers: { any } = {}

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
			for _, sub in subscribers do
				if not sub.paused then
					sub.fn(step)
				end
			end
		end
		if steps >= maxSteps then
			accumulator = 0
		end
	end)
end

--- Register a callback to run every fixed step. Returns a handle you must stop().
function Ticker.every(rateHz: number, fn: (dt: number) -> ()): Handle
	ensureLoop(rateHz)

	local sub = { fn = fn, paused = false }
	table.insert(subscribers, sub)

	local handle = setmetatable({}, Ticker)
	handle._sub = sub
	return (handle :: any) :: Handle
end

function Ticker:stop()
	local index = table.find(subscribers, self._sub)
	if index then
		table.remove(subscribers, index)
	end
	if #subscribers == 0 and activeConnection then
		activeConnection:Disconnect()
		activeConnection = nil
	end
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
