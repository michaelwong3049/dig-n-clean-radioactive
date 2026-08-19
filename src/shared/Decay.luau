--!strict
--[[
	Decay.lua — PURE MATH for the decay clock (PLAN §3.6). Shared, same reason as
	Radiation: the fuse bar the player watches and the fuse the server enforces must
	be the same arithmetic.

	THE ONE THING TO GET RIGHT HERE is that a carried item stores ELAPSED SECONDS,
	never an absolute timestamp. Storing `unearthedAt = os.time()` looks fine and then
	silently slags every player's backpack the first time someone logs off for a day.
	Elapsed time only advances while a tick says it does, which means freezing is just
	"stop ticking" and persistence is free.
]]

local Config = script.Parent.Config
local Tuning = require(Config.Tuning)
local Rarity = require(Config.Rarity)

local Decay = {}

export type CarriedItem = {
	uid: string,
	itemId: string,
	rarity: string,
	modifier: string,
	elapsed: number, -- seconds of DECAY time accrued. Not wall-clock.
	frozen: boolean, -- true once docked at a station / locker / on logout
}

--- Effective fuse length for one item, after satchel and modifier.
function Decay.fuseFor(item: CarriedItem, satchelFuseMult: number): number
	local base = Rarity.get(item.rarity).fuse
	local mod = Rarity.MODIFIERS[item.modifier] or Rarity.MODIFIERS.None
	return base * satchelFuseMult * mod.fuseMult
end

--- Returns stage index (1..4) and the definition. Fresh / Hot / Critical / Slag.
function Decay.stageOf(item: CarriedItem, satchelFuseMult: number): (number, any)
	local fuse = Decay.fuseFor(item, satchelFuseMult)
	if fuse == math.huge or fuse <= 0 then
		return 1, Tuning.DECAY_STAGES[1] -- Prewar Sealed never starts
	end

	local multiple = item.elapsed / fuse
	local index = 1
	for i = #Tuning.DECAY_STAGES, 1, -1 do
		if multiple >= Tuning.DECAY_STAGES[i].atFuseMultiple then
			index = i
			break
		end
	end
	return index, Tuning.DECAY_STAGES[index]
end

--- Seconds until this item drops to the NEXT stage. math.huge if it is already Slag
--- or frozen. This is what the fuse bar counts down.
function Decay.secondsToNextStage(item: CarriedItem, satchelFuseMult: number): number
	if item.frozen then
		return math.huge
	end
	local fuse = Decay.fuseFor(item, satchelFuseMult)
	if fuse == math.huge then
		return math.huge
	end

	local index = Decay.stageOf(item, satchelFuseMult)
	local nextStage = Tuning.DECAY_STAGES[index + 1]
	if not nextStage then
		return math.huge
	end
	return (nextStage.atFuseMultiple * fuse) - item.elapsed
end

--- rads/sec this single item contributes to the player right now.
function Decay.emissionOf(item: CarriedItem, satchelFuseMult: number): number
	local _, stage = Decay.stageOf(item, satchelFuseMult)
	local order = Rarity.get(item.rarity).order
	local base = Tuning.CARRY_EMISSION[order] or 0
	local mod = Rarity.MODIFIERS[item.modifier] or Rarity.MODIFIERS.None
	return base * stage.emission * mod.emissionMult
end

--- Total rads/sec from a whole backpack. Feeds Radiation.resolve().
function Decay.totalEmission(carry: { CarriedItem }, satchelFuseMult: number): number
	local sum = 0
	for _, item in carry do
		if not item.frozen then
			sum += Decay.emissionOf(item, satchelFuseMult)
		end
	end
	return sum
end

--- Fraction of base value this item is still worth. PLAN §3.6 — the value BLEEDS,
--- it does not fall off a cliff, so every second of the run home has a felt cost.
function Decay.valueRetained(item: CarriedItem, satchelFuseMult: number): number
	local _, stage = Decay.stageOf(item, satchelFuseMult)
	return stage.valueRetained
end

--- Advance one item by dt. Returns the new stage index if it CHANGED, else nil —
--- callers use that to fire the audio ladder and the "your Legendary is cooking" alert.
function Decay.tick(item: CarriedItem, dt: number, satchelFuseMult: number): number?
	if item.frozen then
		return nil
	end
	local before = Decay.stageOf(item, satchelFuseMult)
	item.elapsed += dt
	local after = Decay.stageOf(item, satchelFuseMult)
	return if after ~= before then after else nil
end

--- Docking at a decon station, racking in the locker, or logging out.
--- One-way: PLAN §3.6 says reaching a station stops the clock for good.
function Decay.freeze(item: CarriedItem)
	item.frozen = true
end

return Decay
