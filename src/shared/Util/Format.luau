--!strict
--[[
	Format.luau — the number-to-text helpers the controllers each used to carry their own
	copy of: money, $/s rates, weights, clocks and durations.

	EVERY FUNCTION HERE IS A BODY MOVED UNCHANGED from the controllers that had it, so what
	a player reads is the same as before. Several of them are near-twins that differ in how
	far the ladder goes or how many decimals they print (`rate` vs `rateWithT`, `cashShort`
	vs `cashMK` vs `moneyQa` vs `moneyT`). They are kept apart, named for how they differ,
	rather than merged, because merging would change some screen's text. Folding any pair
	into one is a separate decision.
]]

local Format = {}

-- ── Cash ─────────────────────────────────────────────────────────────────────

--- "$850", "$1.2K", "$3.4M", "$5.6B": the ladder stops at billions.
function Format.cashShort(amount: number): string
	if amount >= 1_000_000_000 then
		return string.format("$%.1fB", amount / 1_000_000_000)
	elseif amount >= 1_000_000 then
		return string.format("$%.1fM", amount / 1_000_000)
	elseif amount >= 1_000 then
		return string.format("$%.1fK", amount / 1_000)
	end
	return string.format("$%d", math.floor(amount))
end

--- "$1.5K", "$2M": thousands and millions only, whole numbers left bare (".0" trimmed).
function Format.cashMK(amount: number): string
	local function trim(n: number): string
		return (string.format("%.1f", n):gsub("%.0$", ""))
	end
	if amount >= 1_000_000 then
		return `${trim(amount / 1_000_000)}M`
	elseif amount >= 1_000 then
		return `${trim(amount / 1_000)}K`
	end
	return `${amount}`
end

--- "$1.5K" ... "$2Qa": the ladder up to quadrillions, ".0" trimmed.
function Format.moneyQa(amount: number): string
	for _, unit in { { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if amount >= unit[1] then
			local s = string.format("%.1f", amount / unit[1])
			s = (string.gsub(s, "%.0$", ""))
			return `${s}{unit[2]}`
		end
	end
	return `${math.floor(amount)}`
end

--- "$1.5K" ... "$2T": the same ladder as moneyQa but stopping at trillions.
function Format.moneyT(amount: number): string
	for _, unit in { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if amount >= unit[1] then
			local s = string.format("%.1f", amount / unit[1])
			s = (string.gsub(s, "%.0$", ""))
			return `${s}{unit[2]}`
		end
	end
	return `${math.floor(amount)}`
end

-- ── Rates ────────────────────────────────────────────────────────────────────

--- "$2.00/s", "$48.6/s", "$236/s", "$6.1K/s", "$118K/s", "$1.2M/s": up to billions.
function Format.rate(perSecond: number): string
	if perSecond >= 1_000_000_000 then
		return string.format("$%.1fB/s", perSecond / 1_000_000_000)
	elseif perSecond >= 1_000_000 then
		return string.format("$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 100_000 then
		return string.format("$%.0fK/s", perSecond / 1000)
	elseif perSecond >= 1000 then
		return string.format("$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("$%.1f/s", perSecond)
	end
	return string.format("$%.2f/s", perSecond)
end

--- Like `rate`, but the ladder reaches trillions and a K rate always keeps its decimal.
function Format.rateWithT(perSecond: number): string
	if perSecond >= 1_000_000_000_000 then
		return string.format("$%.1fT/s", perSecond / 1_000_000_000_000)
	elseif perSecond >= 1_000_000_000 then
		return string.format("$%.1fB/s", perSecond / 1_000_000_000)
	elseif perSecond >= 1_000_000 then
		return string.format("$%.1fM/s", perSecond / 1_000_000)
	elseif perSecond >= 1000 then
		return string.format("$%.1fK/s", perSecond / 1000)
	elseif perSecond >= 100 then
		return string.format("$%.0f/s", perSecond)
	elseif perSecond >= 10 then
		return string.format("$%.1f/s", perSecond)
	end
	return string.format("$%.2f/s", perSecond)
end

-- ── Weight ───────────────────────────────────────────────────────────────────

--- Same ladder as IndexController and the wash reveal: two sig figs under a kilo.
function Format.weight(kg: number): string
	if kg < 1 then
		return string.format("%.2g kg", kg)
	end
	return string.format("%d kg", math.floor(kg + 0.5))
end

-- ── Time ─────────────────────────────────────────────────────────────────────

--- "4:05" under an hour, "1:04:05" from an hour up. Rounds seconds UP, so a countdown
--- never reads 0:00 before it is over.
function Format.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local r = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

--- "2 hr" for a whole number of hours, otherwise "45 min".
function Format.hoursOrMinutes(seconds: number): string
	if seconds >= 3600 and seconds % 3600 == 0 then
		return `{seconds // 3600} hr`
	end
	return `{math.floor(seconds / 60)} min`
end

return Format
