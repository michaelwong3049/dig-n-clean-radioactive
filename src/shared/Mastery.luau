--!strict
--[[
	Mastery.luau — a profile's masteries (Config/Masteries): what each counter reads,
	which tier it has reached, and what that pays.

	Pure and side-effect free, and the ONE reader of Config/Masteries' numbers:
	StatResolver folds `value` into the player's stats, MasteryService ships `snapshot`
	to the panel, and the panel writes its text through `rewardText` / `goalText`, so the
	reward a row promises is the one StatResolver applies.

	`profile` is the saved data table (or anything with the same fields). Every field is
	optional here because Util/Spec builds fake profiles by hand: a missing counter is 0.
]]

local Config = script.Parent.Config
local Masteries = require(Config.Masteries)
local Stages = require(Config.Stages)
local IndexProgress = require(script.Parent.IndexProgress)

local Mastery = {}

local byId: { [string]: Masteries.Def } = {}
for _, def in Masteries.LIST do
	byId[def.id] = def
end

--- The mastery `id`, or nil.
function Mastery.get(id: string): Masteries.Def?
	return byId[id]
end

--- How much of the whole index has been found, 0-100, rounded down. Every stage's
--- stock counts, so 100 is every nuke in the game.
function Mastery.indexPercent(discovered: { [string]: boolean }?): number
	if discovered == nil then
		return 0
	end
	local found, total = 0, 0
	for _, stage in Stages.DEFS do
		local have, of = IndexProgress.stageCount(discovered, stage.id)
		found += have
		total += of
	end
	if total <= 0 then
		return 0
	end
	return math.floor(found / total * 100)
end

--- The counter behind `def`, in real units.
function Mastery.count(profile: any, def: Masteries.Def): number
	local source = def.source
	local n: any
	if source == "indexPercent" then
		n = Mastery.indexPercent(profile.discovered)
	elseif source == "cashEarned" then
		n = profile[source]
	else
		n = if type(profile.stats) == "table" then profile.stats[source] else nil
	end
	return if type(n) == "number" then n else 0
end

--- The tier `count` has reached against `def`: 0 (none) to #goals (Gold).
function Mastery.tierFor(def: Masteries.Def, count: number): number
	local tier = 0
	for index, goal in def.goals do
		if count >= goal then
			tier = index
		end
	end
	return tier
end

function Mastery.tierOf(profile: any, def: Masteries.Def): number
	return Mastery.tierFor(def, Mastery.count(profile, def))
end

--- The reward `kind` this profile has earned: the highest reached tier's value of the
--- mastery that pays it, or Masteries.BASE[kind]. A higher tier REPLACES the lower.
--- When several masteries pay the same kind, each one's step away from base adds up
--- (Bomber + Thief walk speed).
function Mastery.value(profile: any, kind: string): number
	local base = Masteries.BASE[kind]
	base = if base ~= nil then base else 1
	local total = base
	for _, def in Masteries.LIST do
		if def.reward == kind then
			local tier = Mastery.tierOf(profile, def)
			if tier > 0 then
				total += def.values[tier] - base
			end
		end
	end
	return total
end

export type Entry = { id: string, count: number, tier: number }

--- Every mastery's counter and tier, in Config order: what MasteryService sends.
function Mastery.snapshot(profile: any): { Entry }
	local out = {}
	for _, def in Masteries.LIST do
		local count = Mastery.count(profile, def)
		table.insert(out, { id = def.id, count = count, tier = Mastery.tierFor(def, count) })
	end
	return out
end

-- ── Words ──────────────────────────────────────────────────────────────

--- 950, 12.5K, 3.4M, 10B, 1.2T.
function Mastery.short(n: number): string
	local abs = math.abs(n)
	for _, step in { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		local size, suffix = step[1] :: number, step[2] :: string
		if abs >= size then
			local scaled = n / size
			local text = if scaled >= 100 then string.format("%d", math.floor(scaled)) else string.format("%.1f", math.floor(scaled * 10) / 10)
			return (string.gsub(text, "%.0$", "")) .. suffix
		end
	end
	return tostring(math.floor(n))
end

--- A count or goal of `def` as the panel prints it: "400", "$1B", "50%", "500K".
function Mastery.goalText(def: Masteries.Def, n: number): string
	local shown = n * (def.shown or 1)
	if def.unit == "$" then
		return "$" .. Mastery.short(shown)
	elseif def.unit == "%" then
		return `{math.floor(shown)}%`
	end
	return Mastery.short(shown)
end

local function percentOff(mult: number): string
	return `{math.floor((1 - mult) * 100 + 0.5)}%`
end

--- What `def` pays at `tier` (1-3): "x2 cash", "-30% radiation damage".
function Mastery.rewardText(def: Masteries.Def, tier: number): string
	local v = def.values[tier]
	local kind = def.reward
	local x = "x" .. (string.gsub(string.format("%.2f", v), "%.?0+$", ""))
	if kind == "cash" then
		return `{x} cash`
	elseif kind == "walkSpeed" then
		return `+{math.floor(v * 100 + 0.5)}% walk speed`
	elseif kind == "speedPrice" then
		return `-{percentOff(v)} speed upgrade price`
	elseif kind == "luck" then
		return `{x} luck`
	elseif kind == "capacity" then
		return `+{v} bag slots`
	elseif kind == "radDamage" then
		return `-{percentOff(v)} radiation damage`
	elseif kind == "mergeFee" then
		return `-{percentOff(v)} merge fee`
	elseif kind == "brewCooldown" then
		return `-{percentOff(v)} brew cooldown`
	elseif kind == "awayRate" then
		return `{(string.gsub(string.format("%.1f", v * 100), "%.0$", ""))}% away earnings`
	end
	return x
end

return Mastery
