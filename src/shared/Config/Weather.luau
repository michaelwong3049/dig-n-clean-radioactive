--!strict
--[[
	Weather.luau — the server-wide weather: one at a time, picked at random.

	Every GAP_MIN..MAX seconds of clear sky (measured from the END of the last
	weather, so a weather never shortens the gap after it), Services/WeatherService
	rolls one of ORDER by `weight` and runs it for its `seconds`:

	  VIOLET AURORA   2x luck (Config/LuckBoost owns it -- its clock, its Robux
	                  product and its sky predate this file and are unchanged).
	  GOLDEN HOUR     2x cash, on everything the Cash pill multiplies: sales and
	                  every stand's income (StatResolver folds it into passCash).
	  METEOR SHOWER   METEOR_COUNT meteors fall into random dig stages, one every
	                  `seconds / METEOR_COUNT`. Each one plants a METEOR SPOT
	                  (DigService.plantMeteor): an ordinary dig spot, shallow so the
	                  starter detector reaches it, lit for everybody from anywhere,
	                  whose per-player roll gets METEOR_LUCK on top of the player's own
	                  luck boost. First to dig it keeps it; METEOR_LIFETIME unclaimed
	                  and it sinks.

	ONE AT A TIME, ON PURPOSE. Each weather repaints the whole sky
	(AtmosphereController), and two at once would fight over it. The bought Server
	Luck Boost respects this too: bought during another weather, the aurora waits
	for it to clear and then starts (LuckBoostService's queue).

	Every clock crosses to clients as ReplicatedStorage attributes (server time),
	like the aurora's, so a late joiner sees the sky and the Boosts pill on arrival.
	The aurora's own pair stays LuckBoost.EVENT_ATTR / EVENT_START_ATTR.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LuckBoost = require(script.Parent.LuckBoost)

local Weather = {}

export type Def = {
	id: string,
	name: string,
	seconds: number,
	weight: number,
	endsAttr: string,
	startAttr: string,
}

-- Clear sky between one weather ending and the next one starting, rolled per gap.
-- These were LuckBoost.EVENT_GAP_* while the aurora was the only weather.
Weather.GAP_MIN = 15 * 60
Weather.GAP_MAX = 20 * 60

Weather.ORDER = { "aurora", "golden", "meteor" }

Weather.DEFS = {
	aurora = {
		id = "aurora",
		name = LuckBoost.EVENT_NAME,
		seconds = LuckBoost.EVENT_SECONDS,
		weight = 1,
		endsAttr = LuckBoost.EVENT_ATTR,
		startAttr = LuckBoost.EVENT_START_ATTR,
	},
	golden = {
		id = "golden",
		name = "Golden Hour",
		seconds = 5 * 60,
		weight = 1,
		endsAttr = "GoldenHourEndsAt",
		startAttr = "GoldenHourStartedAt",
	},
	meteor = {
		id = "meteor",
		name = "Meteor Shower",
		seconds = 5 * 60,
		weight = 1,
		endsAttr = "MeteorShowerEndsAt",
		startAttr = "MeteorShowerStartedAt",
	},
} :: { [string]: Def }

-- ── Golden Hour ────────────────────────────────────────────────────────────────
Weather.GOLDEN_MULT = 2

-- ── Meteor Shower ──────────────────────────────────────────────────────────────
-- Meteors per shower, spread evenly over it (the first lands FIRST_METEOR_AFTER in).
Weather.METEOR_COUNT = 6
Weather.FIRST_METEOR_AFTER = 8
-- Seconds from the streak appearing in the sky to the impact. The spot is planted
-- at the impact, so the fall is the "where is it going" warning.
Weather.METEOR_FALL_SECONDS = 2.5
-- Extra luck on a meteor spot's roll: a weight on Rare+ exactly like 2x luck
-- (Config/Items.luckBias), multiplied onto the player's own luckBoost.
Weather.METEOR_LUCK = 3
-- An unclaimed meteor spot sinks after this long (never out from under a magnet).
Weather.METEOR_LIFETIME = 3 * 60
-- On the meteor spot's aura, so every client knows it is one without a reading.
Weather.METEOR_AURA_ATTR = "MeteorSpot"

--- The weather def, or an error for an unknown id.
function Weather.get(id: string): Def
	local def = Weather.DEFS[id]
	assert(def, `unknown weather {id}`)
	return def
end

--- When `id` ends (server time), or 0 when it is not running.
function Weather.endsAt(id: string): number
	local value = ReplicatedStorage:GetAttribute(Weather.get(id).endsAttr)
	return if type(value) == "number" and value > Workspace:GetServerTimeNow() then value else 0
end

function Weather.active(id: string): boolean
	return Weather.endsAt(id) > 0
end

--- The weather running right now, or nil for a clear sky.
function Weather.current(): string?
	for _, id in Weather.ORDER do
		if Weather.active(id) then
			return id
		end
	end
	return nil
end

--- Which weather a roll `r` in [0, 1) picks, by weight.
function Weather.pick(r: number): string
	local total = 0
	for _, id in Weather.ORDER do
		total += Weather.DEFS[id].weight
	end
	local at = r * total
	for _, id in Weather.ORDER do
		at -= Weather.DEFS[id].weight
		if at < 0 then
			return id
		end
	end
	return Weather.ORDER[#Weather.ORDER]
end

--- Seconds into a shower that meteor `i` (1..METEOR_COUNT) falls.
function Weather.meteorAt(i: number): number
	local spacing = (Weather.DEFS.meteor.seconds - Weather.FIRST_METEOR_AFTER) / Weather.METEOR_COUNT
	return Weather.FIRST_METEOR_AFTER + (i - 1) * spacing
end

return Weather
