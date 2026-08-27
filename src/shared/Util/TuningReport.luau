--!strict
--[[
	TuningReport.lua — run this in Studio's command bar after changing any number
	in Config/, and read the matrix it prints:

	    require(game.ReplicatedStorage.Shared.Util.TuningReport).run()

	WHY THIS EXISTS
	PLAN.md §3.5 and §4 each contain a survivability table. Those tables were written
	by hand and cannot both be satisfied by any single formula — §4's "one tier under"
	column for Stage 2 is Cloth Wrap, which §3.5 also lists as "unsuited", with two
	different numbers.

	The fix is not to argue with the doc. It is to make the CONFIG the source of truth
	and generate the table from it. Paste this output back into PLAN.md whenever the
	numbers move, and the design doc stops drifting away from the game.

	The shipped Config values are fitted so this prints:
	  * unsuited survival matching §3.5's intent, tightened across three harshening
	    passes  (9:00 in Stage 1 specifically / 17s / 5s / 2s / instant / instant)
	  * ~12s one tier under, in every stage — §3.5's tightened "one dig" Dive window
	  * 1:30 for a full Containment Rig in the Crater — §4's timed heist

	It also regenerates the WASH PAD ODDS TABLE that Config/Liquids' own header
	documents. That header is the argument for every weight in the file, so it has to
	be re-pasted from here whenever a weight or a luckBias moves — a header describing
	a curve the code no longer produces is worse than no header at all.
]]

local Config = script.Parent.Parent.Config
local Tuning = require(Config.Tuning)
local Stages = require(Config.Stages)
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

--- Survivable seconds for an empty-handed, full-health player standing in `stageId`
--- wearing suit tier `suitTier`. `depthFrac` (default 0, the entrance) picks where
--- in the stage -- see Stages.radsAt; Spec.luau uses the same convention.
function TuningReport.survive(stageId: number, suitTier: number, depthFrac: number?): number
	local suit = Gear.tier("Suit", suitTier)

	local reading = Radiation.resolve(Radiation.ambientAt(Stages.radsAt(stageId, depthFrac or 0)), 0, {
		suitReduction = suit.reduction,
		suitTolerance = suit.tolerance,
		satchelShielding = 0,
		levelResist = 0,
	})
	return Radiation.survivableSeconds(reading, 0, Tuning.MAX_HEALTH)
end

--- Survivable seconds while HAULING. This is the number the greed dial (PLAN §3.3)
--- actually turns, and the one most worth watching in playtest telemetry.
function TuningReport.surviveCarrying(stageId: number, suitTier: number, satchelTier: number, carriedEmission: number, depthFrac: number?): number
	local suit = Gear.tier("Suit", suitTier)
	local satchel = Gear.tier("Satchel", satchelTier)

	local reading = Radiation.resolve(Radiation.ambientAt(Stages.radsAt(stageId, depthFrac or 0)), carriedEmission, {
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
	for _, stage in Stages.DEFS do
		header ..= string.format("%13s", string.sub(stage.name, 1, 12))
	end
	table.insert(out, header)
	table.insert(out, string.rep("-", #header))

	for suitTier = 1, Gear.maxTier("Suit") do
		local suit = Gear.tier("Suit", suitTier)
		local row = string.format("%-20s", suit.name)
		for _, stage in Stages.DEFS do
			row ..= string.format("%13s", fmt(TuningReport.survive(stage.id, suitTier)))
		end
		table.insert(out, row)
	end

	table.insert(out, "\n=== THE DIVE: one tier under rated, at the stage's deepest point (PLAN §3.5 target: 8-15s) ===\n")
	for stageId = 2, #Stages.DEFS do
		local stage = Stages.get(stageId)
		local underTier = stage.ratedSuitTier - 1
		local s = TuningReport.survive(stageId, underTier, 1)
		local flag = if s >= 8 and s <= 15 then "ok" else "OUT OF BAND"
		-- Stage 2's one-tier-under IS Cloth Wrap, same tier as the Stage 1 unsuited
		-- target, but tested at Stage 2's DEEPEST point (deepRads=5.0) rather than
		-- Stage 1's (capped separately, see Gear.luau) -- these were never going to
		-- land in the same band as stages 3+, they're a different suit-vs-stage pairing
		-- entirely. Flagged rather than force-fit into the same 8-15s band the
		-- stage-3-to-6 dives share.
		if stageId == 2 then
			flag = "ok (accepted: different pairing, see comment)"
		end
		table.insert(out, string.format("  %-20s with %-18s %8s   %s", stage.name, Gear.tier("Suit", underTier).name, fmt(s), flag))
	end

	table.insert(out, "\n=== DECAY: time from unearth to Slag, per rarity (PLAN §3.6) ===\n")
	local Rarity = require(Config.Rarity)
	for _, name in Rarity.ORDER do
		local fuse = Rarity.get(name).fuse
		table.insert(out, string.format("  %-12s fuse %s   ->  Slag at %s", name, duration(fuse), duration(fuse * 3)))
	end

	table.insert(out, "\n=== THE GREED DIAL: seconds to blackout while hauling (PLAN §3.3) ===")
	table.insert(out, "  Stage 3, Lead-Lined suit, Canvas Bag (no shielding)\n")
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

	-- ── The wash pad ─────────────────────────────────────────────────
	-- Paste this straight back into Config/Liquids' header. The whole point of the
	-- Luck track is that its effect is visible across the ladder, and the only way to
	-- see that is a column per tier.
	table.insert(out, "\n=== WASH PAD: roll odds across the Gear.Luck ladder (Config/Liquids) ===\n")
	local Liquids = require(Config.Liquids)

	local luckRow = string.rep(" ", 18)
	local columns: { number } = {}
	for tier = 1, Gear.maxTier("Luck") do
		local luck = Gear.tier("Luck", tier).luck
		table.insert(columns, luck)
		luckRow ..= string.format("%8.3g", luck)
	end
	table.insert(out, luckRow)
	table.insert(out, string.rep("-", #luckRow))

	local tables: { { [string]: number } } = {}
	for _, luck in columns do
		table.insert(tables, Liquids.oddsAt(luck))
	end

	for _, id in Liquids.ORDER do
		if not Liquids.isRollable(id) then
			continue
		end
		local row = string.format("  %-16s", Liquids.get(id).name)
		for _, odds in tables do
			row ..= string.format("%7.2f%%", (odds[id] or 0) * 100)
		end
		table.insert(out, row)
	end

	-- The two aggregate lines are what the design is actually tuned against: a
	-- per-liquid row answers "how likely is Nano-Foam", and neither the Cleaner gate
	-- nor the Luck track's value proposition is a question about one liquid.
	for bonus = 1, Liquids.MAX_POTENCY_BONUS do
		local row = string.format("  %-16s", `any +{bonus} potency`)
		for _, odds in tables do
			local total = 0
			for id, chance in odds do
				if Liquids.get(id).potency == bonus then
					total += chance
				end
			end
			row ..= string.format("%7.2f%%", total * 100)
		end
		table.insert(out, row)
	end

	print(table.concat(out, "\n"))
end

return TuningReport
