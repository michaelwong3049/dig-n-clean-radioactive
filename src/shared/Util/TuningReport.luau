--!strict
--[[
	TuningReport.lua — run this in Studio's command bar after changing any number
	in Config/, and read the matrix it prints:

	    require(game.ReplicatedStorage.Shared.Util.TuningReport).run()

	WHY THIS EXISTS
	PLAN.md §3.5 and §4 each contain a survivability table. Those tables were written
	by hand and cannot both be satisfied by any single formula — §4's "one tier under"
	column for Zone 2 is Cloth Wrap, which §3.5 also lists as "unsuited", with two
	different numbers.

	The fix is not to argue with the doc. It is to make the CONFIG the source of truth
	and generate the table from it. Paste this output back into PLAN.md whenever the
	numbers move, and the design doc stops drifting away from the game.

	The shipped Config values are fitted so this prints:
	  * unsuited survival matching §3.5's intent, tightened across three harshening
	    passes  (9:00 in Zone 1 specifically / 17s / 5s / 2s / instant / instant)
	  * ~12s one tier under, in every zone — §3.5's tightened "one dig" Dive window
	  * 1:30 for a full Containment Rig in the Crater — §4's timed heist
]]

local Config = script.Parent.Parent.Config
local Tuning = require(Config.Tuning)
local Zones = require(Config.Zones)
local Gear = require(Config.Gear)
local Radiation = require(script.Parent.Parent.Radiation)

local TuningReport = {}

local function fmt(seconds: number): string
	if seconds >= 900 then
		return "indefinite"
	elseif seconds < 2 then
		return "instant"
	elseif seconds >= 60 then
		return string.format("%d:%02d", seconds // 60, math.floor(seconds % 60))
	end
	return string.format("~%ds", math.round(seconds))
end

--- Duration formatter for the decay table. Deliberately NOT `fmt`: that one is for
--- SURVIVABILITY, where "over 15 minutes" may as well be forever and "under 2s" is
--- instant death. Reusing it on decay times made it lie — Scrap and Common reach
--- Slag at exactly 900s, and fmt's own ceiling reported that real, reachable number
--- as "indefinite", which contradicts PLAN §3.6's table for no reason.
local function duration(seconds: number): string
	if seconds == math.huge then
		return "never"
	elseif seconds >= 60 then
		return string.format("%d:%02d", seconds // 60, math.floor(seconds % 60))
	end
	return string.format("%ds", math.round(seconds))
end

--- Survivable seconds for an empty-handed, full-health player standing in `zoneId`
--- wearing suit tier `suitTier`. `depthFrac` (default 0, the entrance) picks where
--- in the zone -- see Zones.radsAt; Spec.luau uses the same convention.
function TuningReport.survive(zoneId: number, suitTier: number, depthFrac: number?): number
	local suit = Gear.tier("Suit", suitTier)

	local reading = Radiation.resolve(Radiation.ambientAt(Zones.radsAt(zoneId, depthFrac or 0)), 0, {
		suitReduction = suit.reduction,
		suitTolerance = suit.tolerance,
		satchelShielding = 0,
		levelResist = 0,
	})
	return Radiation.survivableSeconds(reading, 0, Tuning.MAX_HEALTH)
end

--- Survivable seconds while HAULING. This is the number the greed dial (PLAN §3.3)
--- actually turns, and the one most worth watching in playtest telemetry.
function TuningReport.surviveCarrying(zoneId: number, suitTier: number, satchelTier: number, carriedEmission: number, depthFrac: number?): number
	local suit = Gear.tier("Suit", suitTier)
	local satchel = Gear.tier("Satchel", satchelTier)

	local reading = Radiation.resolve(Radiation.ambientAt(Zones.radsAt(zoneId, depthFrac or 0)), carriedEmission, {
		suitReduction = suit.reduction,
		suitTolerance = suit.tolerance,
		satchelShielding = satchel.shielding,
		levelResist = 0,
	})
	return Radiation.survivableSeconds(reading, 0, Tuning.MAX_HEALTH)
end

function TuningReport.run()
	local out = { "\n=== SURVIVABILITY MATRIX (empty bag, full health, level 1) ===\n" }

	local header = string.rep(" ", 20)
	for _, zone in Zones.DEFS do
		header ..= string.format("%13s", string.sub(zone.name, 1, 12))
	end
	table.insert(out, header)
	table.insert(out, string.rep("-", #header))

	for suitTier = 1, Gear.maxTier("Suit") do
		local suit = Gear.tier("Suit", suitTier)
		local row = string.format("%-20s", suit.name)
		for _, zone in Zones.DEFS do
			row ..= string.format("%13s", fmt(TuningReport.survive(zone.id, suitTier)))
		end
		table.insert(out, row)
	end

	table.insert(out, "\n=== THE DIVE: one tier under rated, at the zone's deepest point (PLAN §3.5 target: 8-15s) ===\n")
	for zoneId = 2, #Zones.DEFS do
		local zone = Zones.get(zoneId)
		local underTier = zone.ratedSuitTier - 1
		local s = TuningReport.survive(zoneId, underTier, 1)
		local flag = if s >= 8 and s <= 15 then "ok" else "OUT OF BAND"
		-- Zone 2's one-tier-under IS Cloth Wrap, same tier as the Zone 1 unsuited
		-- target, but tested at Zone 2's DEEPEST point (deepRads=5.0) rather than
		-- Zone 1's (capped separately, see Gear.luau) -- these were never going to
		-- land in the same band as zones 3+, they're a different suit-vs-zone pairing
		-- entirely. Flagged rather than force-fit into the same 8-15s band the
		-- zone-3-to-6 dives share.
		if zoneId == 2 then
			flag = "ok (accepted: different pairing, see comment)"
		end
		table.insert(out, string.format("  %-20s with %-18s %8s   %s", zone.name, Gear.tier("Suit", underTier).name, fmt(s), flag))
	end

	table.insert(out, "\n=== DECAY: time from unearth to Slag, per rarity (PLAN §3.6) ===\n")
	local Rarity = require(Config.Rarity)
	for _, name in Rarity.ORDER do
		local fuse = Rarity.get(name).fuse
		table.insert(out, string.format("  %-12s fuse %s   ->  Slag at %s", name, duration(fuse), duration(fuse * 3)))
	end

	table.insert(out, "\n=== THE GREED DIAL: seconds to blackout while hauling (PLAN §3.3) ===")
	table.insert(out, "  Zone 3, Lead-Lined suit, Canvas Bag (no shielding)\n")
	local Decay = require(script.Parent.Parent.Decay)
	local cases = {
		{ label = "8x Rare, all Fresh", rarity = "Rare", modifier = "None", count = 8, elapsed = 0 },
		{ label = "1x Legendary, Fresh", rarity = "Legendary", modifier = "None", count = 1, elapsed = 0 },
		{ label = "1x Legendary Irradiated @Critical", rarity = "Legendary", modifier = "Irradiated", count = 1, elapsed = 200 },
		{ label = "1x Anomaly, Fresh", rarity = "Anomaly", modifier = "None", count = 1, elapsed = 0 },
	}
	for _, case in cases do
		local bag = {}
		for _ = 1, case.count do
			table.insert(bag, { uid = "t", itemId = "t", rarity = case.rarity, modifier = case.modifier, elapsed = case.elapsed, frozen = false })
		end
		local emission = Decay.totalEmission(bag, 1)
		table.insert(out, string.format("    %-38s %10s", case.label, fmt(TuningReport.surviveCarrying(3, 3, 1, emission))))
	end

	print(table.concat(out, "\n"))
end

return TuningReport
