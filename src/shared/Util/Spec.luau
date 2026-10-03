--!strict
--[[
	Spec.lua — assertions that pin the DESIGN INTENT, not the implementation.

	Run in Studio's command bar:
	    require(game.ReplicatedStorage.Shared.Util.Spec).run()

	Every check here corresponds to a sentence in PLAN.md. When you retune Config/,
	these tell you which part of the design you just broke. They are deliberately
	written as ranges, not exact values — the point is to catch "you moved a number
	and the Dive is now 4 seconds", not to freeze the balance.

	Two of these exist because the first draft of the config got them WRONG, and only
	running the numbers caught it:
	  * "hot bag does not trip aura failure" — carried emission was counting toward
	    aura tolerance, so a full backpack triggered the white-screen over-tier state
	    inside your own rated stage.
	  * "the bag, not the world, is what is killing you" — the aura's reduction was
	    being applied to your own backpack, which erased 99% of a screaming Legendary
	    and quietly switched off the greed dial (§3.3), the mechanic the whole game is
	    built on.

	Keep both. They guard the two most load-bearing sentences in the design.
]]

local Config = script.Parent.Parent.Config
local Stages = require(Config.Stages)
local StageCraters = require(Config.StageCraters)
local SkyConfig = require(Config.Sky)
local Gear = require(Config.Gear)
local Tuning = require(Config.Tuning)
local Rarity = require(Config.Rarity)
local Liquids = require(Config.Liquids)
local Items = require(Config.Items)
local Weight = require(Config.Weight)
local Payload = require(Config.Payload)
local Treadmill = require(Config.Treadmill)
local Floors = require(Config.Floors)
local LuckBoost = require(Config.LuckBoost)
local GamePasses = require(Config.GamePasses)
local CashBoost = require(Config.CashBoost)
local Packs = require(Config.Packs)
local RareDrop = require(Config.RareDrop)
local Masteries = require(Config.Masteries)
local Crates = require(Config.Crates)
local AuraLook = require(script.Parent.Parent.AuraLook)
local Bag = require(script.Parent.Parent.Bag)
local CrateModels = require(script.Parent.Parent.CrateModels)
local ItemModels = require(script.Parent.Parent.ItemModels)
local ItemFxConfig = require(Config.ItemFx)
local ItemFx = require(script.Parent.Parent.ItemFx)
local ToolModels = require(script.Parent.Parent.ToolModels)
local ToolTiers = require(Config.ToolTiers)
local Camps = require(Config.Camps)
local Merge = require(Config.Merge)
local Radiation = require(script.Parent.Parent.Radiation)
local Decay = require(script.Parent.Parent.Decay)
local DetonationConfig = require(Config.Detonation)
local Detonation = require(script.Parent.Parent.Detonation)
local Contamination = require(script.Parent.Parent.Contamination)
local ItemCrust = require(script.Parent.Parent.ItemCrust)
local StatResolver = require(script.Parent.Parent.StatResolver)
local IndexProgress = require(script.Parent.Parent.IndexProgress)

local Spec = {}

local function statsFor(auraTier: number)
	local aura = Gear.tier("Aura", auraTier)
	return {
		auraReduction = aura.reduction,
		auraTolerance = aura.tolerance,
		levelResist = 0,
	}
end

--- `depthFrac` picks WHERE in the stage to test: 0 (entrance) for "can you work
--- here safely", 1 (deepest) for "what happens if you actually push in" -- see
--- Stages.radsAt. Defaults to 0 so existing call sites that don't care about depth
--- keep testing the same "just inside the stage" point they always did.
---
--- Resolved WITH a zone, exactly as ExposureService does, so the aura's damage comes
--- off the zone survival curve (Radiation.zoneSurvival). A flat 100 HP: the curve is
--- in seconds of a full bar, so max health cancels out.
local function readingAt(stageId: number, auraTier: number, carried: number, depthFrac: number?)
	local d = depthFrac or 0
	return Radiation.resolve(Radiation.ambientAt(Stages.radsAt(stageId, d)), carried, statsFor(auraTier), {
		stageId = stageId,
		depthFrac = d,
		auraTier = auraTier,
		maxHealth = 100,
	})
end

local function survive(stageId: number, auraTier: number, carried: number, depthFrac: number?): number
	return Radiation.survivableSeconds(readingAt(stageId, auraTier, carried, depthFrac), 0, 100)
end

local function bagOf(rarity: string, modifier: string, count: number, elapsed: number)
	local bag = {}
	for i = 1, count do
		table.insert(bag, { uid = "spec" .. i, itemId = "spec", rarity = rarity, modifier = modifier, elapsed = elapsed, frozen = false })
	end
	return bag
end

function Spec.run(): boolean
	local passed, failed = 0, 0
	local lines = { "\n=== DESIGN SPEC ===\n" }

	local function check(label: string, ok: boolean)
		if ok then
			passed += 1
			table.insert(lines, "  PASS  " .. label)
		else
			failed += 1
			table.insert(lines, "  FAIL  " .. label)
		end
	end

	-- Catalogue art is intentionally arriving item by item, but every key that has
	-- been assigned must resolve. A typo here would otherwise degrade silently to a
	-- placeholder and make a finished asset look as though it had never shipped.
	for _, item in Items.DEFS do
		if item.model then
			check(`item model resolves: {item.id} -> {item.model}`, ItemModels.has(item.model))
		end
		-- `odds` DRIVES THE ROLL now (weight = 1/odds), so a zero or missing one is a
		-- divide-by-zero in Items.effectiveWeight, not just a bad "1 in 0" on the HUD.
		check(`item has a positive odds: {item.id}`, type(item.odds) == "number" and item.odds >= 1)
		-- `weight` (kg) feeds five curves in Config/Weight; a nil or out-of-band value
		-- degrades as silently as a bad model key. Weight.norm clamps, so out-of-band
		-- would not throw -- it would just quietly saturate a curve.
		check(
			`item weight is in Weight.MIN..MAX: {item.id}`,
			type(item.weight) == "number" and item.weight >= Weight.MIN and item.weight <= Weight.MAX
		)
	end

	-- Config/ItemFx. Every entry has to land on a real, modelled item and name parts
	-- that exist, or the effect silently never shows. The part-name check runs only
	-- where the imported templates live (Studio, or a published place): they are
	-- installed by migration, not synced from git.
	do
		local byId: { [string]: any } = {}
		for _, item in Items.DEFS do
			byId[item.id] = item
		end
		-- ServerStorage once the server has booted (Services/ModelCacheService),
		-- ReplicatedStorage.Assets as the place is saved.
		local templates = game:GetService("ServerStorage"):FindFirstChild("ImportedNukeTemplates")
		if templates == nil then
			templates = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
			templates = templates and templates:FindFirstChild("ImportedNukeTemplates")
		end

		for itemId, def in ItemFxConfig.DEFS do
			local item = byId[itemId]
			check(`item fx names a modelled item: {itemId}`, item ~= nil and item.model == "ImportedNuke")

			local lightAnims, periodsOk, parentsOk, finishOk = 0, true, true, true
			for _, anim in def.anims or {} do
				if anim.light then
					lightAnims += 1
				end
				if not (anim.period >= 0.05 and anim.period <= 10) then
					periodsOk = false
				end
			end
			for index, spin in def.spins or {} do
				-- swing/twitch spins have no rpm.
				if math.abs(spin.rpm or 0) > 60 or (spin.parent and spin.parent >= index) then
					parentsOk = false
				end
			end
			local tintOk = true
			for _, finish in def.finish or {} do
				-- A material without a colour strips the SurfaceAppearance and leaves the
				-- part flat default grey.
				if finish.material and finish.color == nil then
					finishOk = false
				end
				-- A tint lives on the SurfaceAppearance, which a material or colour
				-- destroys: it would silently do nothing.
				if finish.tint and (finish.material or finish.color) then
					tintOk = false
				end
			end
			check(`item fx drives its light from at most one anim: {itemId}`, lightAnims <= 1)
			check(`item fx anim periods are 0.05-10s: {itemId}`, periodsOk)
			check(`item fx spins stay under 60 rpm and nest parents-first: {itemId}`, parentsOk)
			check(`item fx finishes that set a material also set a colour: {itemId}`, finishOk)
			check(`item fx tints aren't on parts a material or colour strips: {itemId}`, tintOk)

			local glint = def.glint
			if glint then
				-- A pass has to finish well inside its period, and a strength under 1
				-- is dimmer than white paint, over 5 blows out to a flat white slab.
				check(
					`item fx glint: pass shorter than its period, strength 1-5: {itemId}`,
					#glint.parts > 0
						and glint.sweep > 0
						and glint.sweep < glint.period * 0.5
						and glint.strength >= 1
						and glint.strength <= 5
				)
			end

			local template = templates and templates:FindFirstChild(itemId)
			if template then
				local missing = {}
				for _, name in ItemFx.referencedNames(def) do
					if #ItemFx.partsNamed(template, { name }) == 0 then
						table.insert(missing, name)
					end
				end
				check(
					`item fx part names all exist in the template: {itemId}` .. (if #missing > 0
						then ` (missing {table.concat(missing, ", ")})`
						else ""),
					#missing == 0
				)
			end
		end
	end

	-- Config/Weight — the five curves and the one U-shaped bias. These pin the shape,
	-- not the exact endpoints: "heavier is bigger / harder / worth more", and "weight
	-- never makes an item COMMONER" (rollBias <= 1), and the middle of the range is
	-- untouched (rollBias == 1) so a mid-weight catalogue is exactly as #61 tuned it.
	do
		local mono = true
		local prev = { s = -1, a = -1, p = -1, v = -1 }
		for i = 0, 40 do
			local kg = Weight.MIN * (Weight.MAX / Weight.MIN) ^ (i / 40)
			local s, p, v = Weight.sizeScale(kg), Weight.pullFactor(kg), Weight.valueMult(kg)
			-- Cracks follow the nuke's SIZE, so walk them along the same size curve.
			local a = Weight.crackScale(s)
			if s < prev.s - 1e-9 or a < prev.a - 1e-9 or p < prev.p - 1e-9 or v < prev.v - 1e-9 then
				mono = false
			end
			prev = { s = s, a = a, p = p, v = v }
			if Weight.rollBias(kg) > 1 + 1e-9 then
				mono = false
			end
		end
		check("§weight sizeScale/crackScale/pullFactor/valueMult all rise with mass; rollBias never exceeds 1", mono)

		-- Bigger cracks = bigger nuke, STRICTLY, across the whole real size span: two
		-- nukes that come up at different sizes never show the same or inverted cracks.
		local strict = true
		local last = -1
		for i = 0, 60 do
			local size = Weight.CRACK_SIZE_MIN * (Weight.CRACK_SIZE_MAX / Weight.CRACK_SIZE_MIN) ^ (i / 60)
			local c = Weight.crackScale(size)
			if c <= last then
				strict = false
			end
			last = c
		end
		check("§weight crackScale strictly rises with nuke size", strict)

		local mid = math.sqrt(Weight.MIN * Weight.MAX) -- geometric middle == norm 0.5
		check("§weight the mid of the range is roll-unbiased (rollBias == 1)", math.abs(Weight.rollBias(mid) - 1) < 1e-6)
		check("§weight the feather end is a touch rarer, not commoner", Weight.rollBias(Weight.MIN) < 1 and Weight.rollBias(Weight.MIN) >= 0.75)
		check("§weight the heavy end is buried deep but still rolls", Weight.rollBias(Weight.MAX) < 0.5 and Weight.rollBias(Weight.MAX) > 0.15)
		check("§weight heaviest item's valueMult stays sane (<= 2.0, like a modifier)", Weight.valueMult(Weight.MAX) <= 2.0)

		-- Weight and rarity are orthogonal by design, but a genuinely HEAVY find should
		-- also be scarce, or the physical slog and the payoff come apart. Pin the
		-- heaviest catalogue item to Rare or better.
		local heaviest = Items.DEFS[1]
		for _, item in Items.DEFS do
			if item.weight > heaviest.weight then
				heaviest = item
			end
		end
		check(
			string.format("§weight the heaviest item (%s, %gkg) is Rare or better", heaviest.id, heaviest.weight),
			Rarity.get(heaviest.rarity).order >= Rarity.get("Rare").order
		)

		-- No nuke under 5 kg: authored weights sit at or above the floor, and the
		-- shown kg (weight x the 0.6x-2.5x payload roll) is floored at it too.
		local lightest = Items.DEFS[1].weight
		for _, item in Items.DEFS do
			lightest = math.min(lightest, item.weight)
		end
		check(string.format("§weight no nuke is authored under 5 kg (lightest %gkg)", lightest), lightest >= 5)
		check("§weight shownKg floors a low roll at 5 kg", Weight.shownKg(5, 0.6) == 5 and Weight.shownKg(100, 2) == 200)

		-- `sizeMult` is a gentle visual nudge on top of sizeScale, never a resize.
		local sizeMultOk = true
		for _, item in Items.DEFS do
			if item.sizeMult ~= nil and not (item.sizeMult >= 0.5 and item.sizeMult <= 8) then
				sizeMultOk = false
			end
		end
		check("§weight every item's sizeMult is a nudge (0.5-8x) when set", sizeMultOk)
	end

	-- Shared/IndexProgress — the index's stage-completion reward and record weights.
	-- Pins: every stage can be completed, the reward is all-or-nothing per stage (one
	-- missing nuke withholds it), it stays smaller than one detector rung, and a record
	-- with no roll on file reads as "none", not 0 kg.
	do
		-- Stages 7-12 are floor only with dig OFF (Config/Stages): they stock nothing, so
		-- they are held to "never completes" instead of "can be completed".
		local all: { [string]: boolean } = {}
		local stocked = true
		for _, stage in Stages.DEFS do
			local list = IndexProgress.stageItems(stage.id)
			if #list == 0 and stage.id <= 6 then
				stocked = false
			end
			for _, item in list do
				all[item.id] = true
			end
		end
		check("§index every stage 1-6 stocks at least one nuke to complete", stocked)

		local none = IndexProgress.stageLuck({})
		check("§index an empty index earns no stage luck", next(none) == nil)

		local full = IndexProgress.stageLuck(all)
		local fullOk = true
		local emptyNever = true
		local fullMult = IndexProgress.stageLuckMult(all)
		local splitOk = true
		for _, stage in Stages.DEFS do
			local empty = #IndexProgress.stageItems(stage.id) == 0
			local isMult = IndexProgress.luckIsMult(stage.id)
			local want = if isMult then fullMult[stage.id] else full[stage.id]
			local wantValue = if isMult then Tuning.INDEX_COMPLETE_LUCK_MULT else Tuning.INDEX_COMPLETE_LUCK
			if not empty and want ~= wantValue then
				fullOk = false
			end
			if empty and (full[stage.id] ~= nil or fullMult[stage.id] ~= nil) then
				emptyNever = false
			end
			-- Each stage pays ONE kind of luck reward, never both.
			if full[stage.id] ~= nil and fullMult[stage.id] ~= nil then
				splitOk = false
			end
		end
		check("§index a stage pays a flat OR a multiplied luck reward, never both", splitOk)
		check(
			"§index the Stage 7+ luck reward is a real multiplier",
			Tuning.INDEX_COMPLETE_LUCK_MULT > 1 and next(IndexProgress.stageLuckMult({})) == nil
		)
		check("§index identifying everything completes every stocked stage", fullOk)
		check("§index a stage that stocks nothing never grants its luck", emptyNever)

		-- The cash half: x1 with nothing complete, each complete stage's stageCash
		-- (x1.1, x1.2 from Stage 7), stacked, and resolved into BOTH payout multipliers.
		local stockedProduct = 1
		for _, stage in Stages.DEFS do
			if #IndexProgress.stageItems(stage.id) > 0 then
				stockedProduct *= IndexProgress.stageCash(stage.id)
			end
		end
		check("§index an empty index earns no cash bonus", IndexProgress.cashMultiplier({}) == 1)
		check(
			"§index every complete stage stacks its cash multiplier",
			math.abs(IndexProgress.cashMultiplier(all) - stockedProduct) < 1e-9
		)
		check(
			"§index Stages 7+ pay the bigger cash multiplier",
			IndexProgress.stageCash(Tuning.INDEX_CASH_LATE_FROM_STAGE) == Tuning.INDEX_COMPLETE_CASH_LATE
				and IndexProgress.stageCash(Tuning.INDEX_CASH_LATE_FROM_STAGE - 1) == Tuning.INDEX_COMPLETE_CASH
		)
		local bare = StatResolver.get({ level = 1, gear = {}, perks = {} })
		local done = StatResolver.get({ level = 1, gear = {}, perks = {}, discovered = all })
		local want = IndexProgress.cashMultiplier(all)
		check(
			"§index the cash bonus reaches both sales and stand income",
			math.abs(done.sellMultiplier - bare.sellMultiplier * want) < 1e-9
				and math.abs(done.yieldMultiplier - bare.yieldMultiplier * want) < 1e-9
		)

		local firstStage = Stages.DEFS[1].id
		local missing = table.clone(all)
		missing[IndexProgress.stageItems(firstStage)[1].id] = nil
		check(
			"§index one missing nuke withholds that stage's luck",
			IndexProgress.stageLuck(missing)[firstStage] == nil
		)
		check(
			"§index one missing nuke withholds that stage's cash bonus",
			IndexProgress.cashMultiplier(missing) < want
		)

		-- Measured from the free starter to the first detector that costs real money
		-- (the Scrap Sweeper, tier 3). Tier 2 is the tutorial's $15 Bent Coil, a
		-- deliberately tiny step (Config/Gear), and before it existed this exact
		-- comparison was starter -> Scrap Sweeper too: 1.00 -> 1.12, unchanged.
		local rung = Gear.tier("Detector", 3).luck - Gear.tier("Detector", 1).luck
		check(
			string.format("§index stage luck is positive and under one detector rung (%.2f)", rung),
			Tuning.INDEX_COMPLETE_LUCK > 0 and Tuning.INDEX_COMPLETE_LUCK < rung
		)

		local sample = IndexProgress.stageItems(firstStage)[1]
		local entry = { best = 2, count = 1, first = 0, new = false }
		check(
			"§index a record weighs catalogue weight x its payload roll",
			math.abs((IndexProgress.bestKg(sample.id, entry) or 0) - sample.weight * 2) < 1e-9
		)
		check(
			"§index a record with no roll on file has no weight",
			IndexProgress.bestKg(sample.id, { best = 0, count = 1, first = 0, new = false }) == nil
		)
	end

	-- §raredrop buffs: an announced drop always carries 1..4 distinct buffs, its
	-- qualities best first, and every size outcome is reachable inside Payload's band.
	do
		local rng = Random.new(7)
		local ok, seen = true, {}
		for _ = 1, 4000 do
			local buffs = RareDrop.rollBuffs(rng)
			local count = #buffs.qualities + (if buffs.size then 1 else 0)
			seen[count] = true
			if count < 1 or count > 4 then
				ok = false
			end
			for i, name in buffs.qualities do
				if Rarity.MODIFIERS[name] == nil or (i > 1 and Merge.modifierRank(buffs.qualities[i - 1]) >= Merge.modifierRank(name)) then
					ok = false
				end
			end
		end
		check("§raredrop every drop rolls 1-4 distinct buffs, best quality first", ok and seen[1] and seen[2] and seen[3] and seen[4] or false)
		local reach = true
		for _, size in { "GIGA", "OVERSIZED" } do
			local range = RareDrop.SIZE_RANGES[size]
			if range.min >= Payload.MAX or Payload.calloutFor(range.min) ~= size then
				reach = false
			end
		end
		check("§raredrop each size buff lands on its own Payload callout", reach and Payload.calloutFor(RareDrop.SIZE_RANGES.plain.min) == nil)
		check(
			"§raredrop stacked qualities multiply (Pristine + Irradiated = x6)",
			math.abs(Rarity.valueMult("Pristine", { "Irradiated" }) - 6) < 1e-9 and Rarity.valueMult("None", nil) == 1
		)
	end


	-- Config/Payload — the per-DIG size/value roll, separate from Weight's per-item-
	-- TYPE intrinsic. Pins: never outside its own band, deterministic per uid (the
	-- whole point of seeding on uid instead of storing a rolled field), and the
	-- distribution actually leans toward MIN the way "bigger is rarer" promises.
	do
		local inBand = true
		local deterministic = true
		local sampleSum = 0
		local sampleCount = 2000
		for i = 1, sampleCount do
			local uid = `spec-payload-sample-{i}`
			local a = Payload.forUid(uid)
			local b = Payload.forUid(uid)
			if a < Payload.MIN - 1e-9 or a > Payload.MAX + 1e-9 then
				inBand = false
			end
			if math.abs(a - b) > 1e-9 then
				deterministic = false
			end
			sampleSum += a
		end
		check("§payload every roll stays inside Payload.MIN..MAX", inBand)
		check("§payload the same uid always rolls the same number", deterministic)

		-- A flat/uniform roll would average to the midpoint of the band; "bigger is
		-- rarer" means the real average has to sit below that midpoint.
		local mean = sampleSum / sampleCount
		local midpoint = (Payload.MIN + Payload.MAX) / 2
		check(
			string.format("§payload the roll leans toward MIN, not flat (mean %.3f < midpoint %.3f)", mean, midpoint),
			mean < midpoint
		)

		-- The dig callout: tiers run highest-first inside the band, an ordinary roll
		-- says nothing, and the top of the band earns the top tier.
		local tiersOk = #Payload.CALLOUTS > 0
		for i, tier in Payload.CALLOUTS do
			local prev = Payload.CALLOUTS[i - 1]
			if tier.min <= 1 or tier.min > Payload.MAX or (prev and prev.min <= tier.min) then
				tiersOk = false
			end
		end
		check("§payload callout tiers are above 1x, inside the band, highest first", tiersOk)

		-- The odds table: bands run upward from MIN and end at MAX, chances total
		-- 100, and fromRoll lands every band edge exactly where its running total
		-- says (24% of rolls below 0.8x, 52% below 1.0x, and so on).
		local bandsOk = #Payload.BANDS > 0 and Payload.BANDS[#Payload.BANDS].upTo == Payload.MAX
		local edgesOk = true
		local low, cumulative = Payload.MIN, 0
		for _, band in Payload.BANDS do
			if band.upTo <= low or band.chance <= 0 then
				bandsOk = false
			end
			cumulative += band.chance
			if cumulative < 100 and math.abs(Payload.fromRoll(cumulative / 100) - band.upTo) > 1e-6 then
				edgesOk = false
			end
			low = band.upTo
		end
		check(
			string.format("§payload bands climb MIN..MAX and their chances total 100 (got %d)", cumulative),
			bandsOk and cumulative == 100
		)
		check("§payload fromRoll puts each band edge at its running chance", edgesOk)
		check(
			"§payload an ordinary roll has no callout; MAX earns the top one",
			Payload.calloutFor(1) == nil and Payload.calloutFor(Payload.MAX) == Payload.CALLOUTS[1].label
		)
		-- The star rating: rarity tier, quality and size nudges, clamped 1..MAX_STARS.
		check(
			"§stars an ordinary find rates its rarity tier",
			Rarity.stars("Rare", "None", 1) == Rarity.DEFS.Rare.order and Rarity.stars("Rare") == Rarity.DEFS.Rare.order
		)
		check(
			"§stars quality and size move it (Pristine GIGA Rare 7, Cracked small Rare 2)",
			Rarity.stars("Rare", "Pristine", Payload.MAX) == 7 and Rarity.stars("Rare", "Cracked", Payload.MIN) == 2
		)
		check(
			"§stars clamp to 1..MAX_STARS and every callout adds a star",
			Rarity.stars("Anomaly", "Pristine", Payload.MAX) == Rarity.MAX_STARS
				and Rarity.stars("Scrap", "Slagged", Payload.MIN) == 1
				and Rarity.stars("Rare", nil, Payload.CALLOUTS[#Payload.CALLOUTS].min) > Rarity.DEFS.Rare.order
				and Rarity.stars(nil) == 0
		)
		check(
			"§stars early stages rate lower (S4 Legendary Pristine 6, S1 Common 1, S12 Anomaly 9)",
			Rarity.stars("Legendary", "Pristine", 1, nil, 4) == 6
				and Rarity.stars("Common", nil, 1, nil, 1) == 1
				and Rarity.stars("Anomaly", nil, 1, nil, 12) == 9
				and Rarity.stars("Anomaly", "Pristine", 1, nil, 12) == Rarity.MAX_STARS
				and Rarity.MAX_STARS == 10
		)
		check(
			"§stars move in half stars (S3 Rare 2.5, a 1.3x roll +0.5, a 0.9x roll -0.5)",
			Rarity.stars("Rare", nil, 1, nil, 3) == 2.5
				and Rarity.stars("Rare", nil, 1.3) == 4.5
				and Rarity.stars("Rare", nil, 0.9) == 3.5
		)

		-- The Merge Reactor (Config/Merge): harder per level, pity and luck help but
		-- are capped, a crit is part of a success and only exists while +2 fits, and
		-- every merge star is worth more than the last.
		local climbing = #Merge.SUCCESS == Merge.MAX_LEVEL
		for index = 2, #Merge.SUCCESS do
			climbing = climbing and Merge.SUCCESS[index] < Merge.SUCCESS[index - 1]
		end
		check("§merge success falls level by level, one entry per level", climbing)
		local plain = Merge.odds(0, 0, 1)
		local lucky = Merge.odds(0, 0, 100)
		local pitied = Merge.odds(0, 100, 1)
		local last = Merge.odds(Merge.MAX_LEVEL - 1, 0, 100)
		check(
			"§merge pity and luck are capped, and a crit never outruns the success",
			plain ~= nil
				and lucky ~= nil
				and pitied ~= nil
				and plain.crit == Merge.CRIT
				and lucky.crit == Merge.CRIT_MAX
				and pitied.success == Merge.SUCCESS_MAX
				and lucky.crit <= lucky.success
		)
		check(
			"§merge no crit where +2 would pass MAX_LEVEL, and nothing past MAX_LEVEL",
			last ~= nil and last.crit == 0 and Merge.odds(Merge.MAX_LEVEL, 0, 1) == nil
		)
		check(
			"§merge a roll under the crit is +2, under the success +1, else a fail",
			plain ~= nil
				and Merge.gain(plain, 0) == 2
				and Merge.gain(plain, plain.success - 1e-6) == 1
				and Merge.gain(plain, plain.success) == 0
		)
		check(
			"§merge each star multiplies value; a missing field is level 0",
			Merge.valueMult(0) == 1
				and Merge.valueMult(1) == Merge.VALUE_STEP
				and Merge.valueMult(Merge.MAX_LEVEL) > Merge.valueMult(Merge.MAX_LEVEL - 1)
				and Merge.levelOf({}) == 0
				and Merge.levelOf({ merge = 99 }) == Merge.MAX_LEVEL
		)
		local feesOk = true
		for _, def in Items.DEFS do
			if Merge.fee(def.id, 0) < Merge.FEE_MIN or Merge.fee(def.id, 1) < Merge.fee(def.id, 0) then
				feesOk = false
			end
		end
		check("§merge every nuke has a fee, and it grows with the level", feesOk)
		local reactors = 0
		for _, def in Camps.DEFS do
			if def.mergeReactor then
				reactors += 1
				check(`§merge {def.name} stands a reactor, so it must be a site camp`, def.center ~= nil)
			end
		end
		check("§merge Toxic Twilight stands a Merge Reactor", (Camps.get("twilight") :: any) ~= nil and (Camps.get("twilight") :: any).mergeReactor == true and reactors >= 1)
	end

	-- THE ZONE SURVIVAL CURVE (Tuning.ZONE_SURVIVAL), pinned to the user's targets.
	-- Read straight off Radiation.zoneSurvival: the aura's share of the damage only,
	-- seconds a full health bar lasts. The exposure meter stacks on top of this.
	--   * your own stage: minimal drain over the first 60%, then steadier and harsher
	--   * one tier under: 20-30s at the entrance, under 3s past 60%
	--   * stages 7-12 harsher than 1-6 on both
	--   * the top aura in Stage 12 (rated past the ladder): about a minute
	do
		local Z = Tuning.ZONE_SURVIVAL
		local smooth, ratedOk, underOk, harsher = true, true, true, true
		local detail = ""
		for stageId = 1, #Stages.DEFS do
			local rated = Stages.get(stageId).ratedAuraTier
			if rated <= Gear.maxTier("Aura") then
				-- Rated: never steps -- every 1% further in is at most a few % shorter.
				-- The one allowed step is the line into a dead zone (checked below).
				local dz = Z.DEAD_ZONE[stageId]
				local prev = Radiation.zoneSurvival(stageId, 0, rated)
				for i = 1, 100 do
					local now = Radiation.zoneSurvival(stageId, i / 100, rated)
					local crossed = dz ~= nil and (i - 1) / 100 < dz.from and i / 100 >= dz.from
					if now > prev + 1e-6 or (now < prev * 0.95 and not crossed) then
						smooth = false
						detail = `stage {stageId} at {i}%`
					end
					prev = now
				end
				local entrance = Radiation.zoneSurvival(stageId, 0, rated)
				local brk = Radiation.zoneSurvival(stageId, if dz then math.min(Z.BREAK, dz.from - 0.01) else Z.BREAK, rated)
				local far = Radiation.zoneSurvival(stageId, 1, rated)
				if not (entrance >= 300 and brk >= 180 and (dz ~= nil or far >= 60) and far < brk) then
					ratedOk = false
				end
			end
			if rated >= 2 and rated - 1 <= Gear.maxTier("Aura") and rated <= Gear.maxTier("Aura") then
				local under = rated - 1
				local entrance = Radiation.zoneSurvival(stageId, 0, under)
				local past = Radiation.zoneSurvival(stageId, Z.BREAK + 0.01, under)
				-- The authored 20-30s / under-3s bands, plus the flat UNDER_GRACE on top.
				local lo = (if stageId >= Z.HARSH_FROM_STAGE then 15 else 20) + Z.UNDER_GRACE
				if not (entrance >= lo and entrance <= 30 + Z.UNDER_GRACE and past < 3 + Z.UNDER_GRACE) then
					underOk = false
				end
				if stageId >= Z.HARSH_FROM_STAGE then
					local early = Radiation.zoneSurvival(2, 0, 1)
					if not (entrance < early) then
						harsher = false
					end
				end
			end
		end
		check(`§zone the rated drain climbs smoothly, no steps ({detail ~= "" and detail or "ok"})`, smooth)
		check("§zone a rated aura lasts minutes: >=5m entrance, >=3m at 60%, >=1m at the far edge (outside dead zones)", ratedOk)
		-- Stage 6's last 40% is a dead zone, on request: the Nimbus fails out there.
		do
			local dz = Z.DEAD_ZONE[6]
			local nimbus = Stages.get(6).ratedAuraTier
			local into = dz and Radiation.zoneSurvival(6, dz.from, nimbus) or math.huge
			local edge = Radiation.zoneSurvival(6, 1, nimbus)
			check(
				string.format("§zone Stage 6's last 40%% is deadly for the Nimbus: %.0fs at 60%%, %.0fs at the far edge (want <= 30, <= 10)", into, edge),
				dz ~= nil and dz.from <= 0.6 and into <= 30 and edge <= 10
			)
			check("§zone ...and the Nimbus is failing there, not wearing", dz ~= nil and readingAt(6, nimbus, 0, dz.from).failing)
			check("§zone ...but still holds just before it", dz ~= nil and not readingAt(6, nimbus, 0, dz.from - 0.01).failing)
			check("§zone ...and the aura above it (Stage 7's) takes nothing there", Radiation.zoneSurvival(6, 1, nimbus + 1) == math.huge)
		end
		check(
			string.format("§zone one tier under: 20-30s at the entrance (15-30s in the harsh stages), under 3s past 60%%, +%ds grace", Z.UNDER_GRACE),
			underOk
		)
		check("§zone the harsh stages (6-12) are harsher than 1-5 one tier under", harsher)
		check(
			string.format("§zone two tiers under is about a second, +%ds grace", Z.UNDER_GRACE),
			Radiation.zoneSurvival(5, 0, 3) <= 1.5 + Z.UNDER_GRACE
		)
		check("§zone the under-tier grace is about 20s", Z.UNDER_GRACE >= 15 and Z.UNDER_GRACE <= 25)
		check("§zone an aura above the stage's rating takes no aura damage", Radiation.zoneSurvival(3, 1, 5) == math.huge)
		local top = Gear.maxTier("Aura")
		local last = #Stages.DEFS
		local mid = Radiation.zoneSurvival(last, 0.5, top)
		check(
			string.format("§zone the strongest aura (%s) lasts about a minute in Stage %d: %.0fs mid-stage (want 45-75)", Gear.tier("Aura", top).name, last, mid),
			Stages.get(last).ratedAuraTier > top and mid >= 45 and mid <= 75
		)
	end

	-- PLAN §3.4 — a rated aura means you can work, not just survive. Entrance,
	-- same reasoning as the zone checks above: ten minutes at the gate.
	--
	-- STAGE 1 IS DELIBERATELY EXCLUDED FROM THIS LOOP. Stage 1's rated aura tier IS
	-- Faint Glow (the starting/no-gear tier), capped at ~9 minutes by its own
	-- `reduction` (see Gear.luau). Checked on its own immediately below.
	for stageId = 2, 5 do
		local s = survive(stageId, Stages.get(stageId).ratedAuraTier, 0)
		check(string.format("§3.4 rated aura workable at stage %d's entrance = %.0fs (want >= 600)", stageId, s), s >= 600)
	end
	do
		local s = survive(1, 1, 0)
		check(string.format("§3.4 stage 1 unshielded capped at ~9min = %.0fs (want 480-600)", s), s >= 480 and s <= 600)
	end

	-- PLAN §4 — the Crater (Stage 6). Was "never a farm, at any gear level, forever";
	-- that cap was dropped on request (see Config/Gear's reduction note).
	-- The Nimbus follows the curve in the Crater now (its heist cap was dropped on
	-- request), and the far rim bites: the curve has to make it, since the air is flat.
	do
		local entrance, rim = survive(6, 6, 0, 0), survive(6, 6, 0, 1)
		check(string.format("§4 Crater with the Nimbus: %.0fs at the entrance, %.0fs at the far rim (want 300+ then under 90)", entrance, rim), entrance >= 300 and rim < 90)
	end
	-- No aura soaks more of the stage than the one below it.
	do
		local climbs = true
		for tier = 2, Gear.maxTier("Aura") do
			if Gear.tier("Aura", tier).reduction < Gear.tier("Aura", tier - 1).reduction then
				climbs = false
			end
		end
		check("§4 aura reduction never drops from one rung to the next (except the Nimbus's old dip, now gone)", climbs)
	end
	-- TOXIC TWILIGHT'S AURAS THRIVE BELOW THEIR STAGES (Config/Gear's reduction note). The
	-- old rule was the opposite -- no aura past the Nimbus could farm the Crater -- and it
	-- capped every Twilight aura at ~90s in Stages 6-7. Now: at least five minutes in
	-- Stages 5-6, and in Stage 7 a higher aura always lasts longer than a lower one.
	do
		local weak: string? = nil
		for tier = 7, Gear.maxTier("Aura") do
			for stageId = 5, 6 do
				local s = survive(stageId, tier, 0, 1)
				if s < 300 then
					weak = string.format("%s %.0fs in stage %d", Gear.tier("Aura", tier).name, s, stageId)
				end
			end
		end
		check(`§4 every Twilight aura thrives in stages 5-6, 5m+ at the far edge ({weak or "ok"})`, weak == nil)
		local climbs = true
		for tier = 8, Gear.maxTier("Aura") do
			if survive(7, tier, 0, 0.6) <= survive(7, tier - 1, 0, 0.6) then
				climbs = false
			end
		end
		check("§4 in Stage 7, every Twilight aura lasts longer than the one below it", climbs)
		-- ...and in its own stage the meter never beats the zone curve.
		local meterFirst: string? = nil
		for tier = 7, Gear.maxTier("Aura") do
			local stageId = tier
			local aura = Gear.tier("Aura", tier)
			local fill = 100 / (Stages.radsAt(stageId, 1) * (1 - aura.reduction))
			if fill < 240 then
				meterFirst = string.format("%s fills in %.0fs", aura.name, fill)
			end
		end
		check(`§4 a Twilight aura's meter takes 4m+ to fill at its own stage's far edge ({meterFirst or "ok"})`, meterFirst == nil)
	end

	-- THE CRATER'S FAR EDGE IS TOXIC TWILIGHT'S DOORSTEP (Config/Camps). The top aura has
	-- to be able to walk out into the camp -- its aura holding at the east edge, where
	-- the camp's gate is -- and the aura under it must not, or reaching the camp stops
	-- being earned. Checked on the zone curve, then as a survival time, so the Nimbus's
	-- exposure clock still leaves room for the walk.
	-- The Crater's last 40% is a dead zone now (Tuning.ZONE_SURVIVAL.DEAD_ZONE), so the
	-- Nimbus no longer HOLDS at the gate -- it has to SPRINT there. Pinned as a crossing:
	-- an untrained walker (Treadmill.START_WALK) from the dead zone's line to the east
	-- edge, integrating the aura's share of the damage, arrives with health to spare.
	do
		local function crossingCost(auraTier: number): number
			local from = (Tuning.ZONE_SURVIVAL.DEAD_ZONE[6] or { from = 1 }).from
			local minX, _, maxX = Stages.bounds(6)
			local seconds = (1 - from) * (maxX - minX) / Treadmill.START_WALK
			local steps, lost = 50, 0
			for i = 1, steps do
				local d = from + (1 - from) * (i - 0.5) / steps
				lost += (seconds / steps) / Radiation.zoneSurvival(6, d, auraTier)
			end
			return lost
		end
		local nimbusCost = crossingCost(6)
		check(
			string.format("§camp the Nimbus can sprint the Crater's dead zone to Toxic Twilight: %.0f%% of a health bar (want < 60%%)", nimbusCost * 100),
			nimbusCost < 0.6
		)
		check("§camp ...and the Isotope Mantle fails at the east edge — only the top aura walks in", readingAt(6, 5, 0, 1).failing)
	end

	-- Config/StageCraters — the craters pocking the Crater. Level design, so what is
	-- pinned is placement: every crater stands wholly on its own plate, off the side
	-- walls, clear of the seam you arrive over and of Toxic Twilight's gate on the east
	-- edge; no two run into each other; and the no-dig ground they claim stays a
	-- minority of the plate, since DigService re-rolls those spawns onto the rest.
	do
		local placed, walled, seams, apart = true, true, true, true
		local detail = ""
		for _, c in StageCraters.DEFS do
			local minX, minZ, maxX, maxZ = Stages.bounds(c.stageId)
			local reach = StageCraters.reach(c)
			local cx, cz = c.center[1], c.center[2]
			if cx - reach < minX or cx + reach > maxX or cz - reach < minZ or cz + reach > maxZ then
				placed = false
				detail ..= ` {c.name}`
			end
			if cz - reach < minZ + 8 or cz + reach > maxZ - 8 then
				walled = false
			end
			if cx - reach < minX + 20 or cx + reach > maxX - 20 then
				seams = false
			end
		end
		for i = 1, #StageCraters.DEFS do
			for j = i + 1, #StageCraters.DEFS do
				local a, b = StageCraters.DEFS[i], StageCraters.DEFS[j]
				local d = math.sqrt((a.center[1] - b.center[1]) ^ 2 + (a.center[2] - b.center[2]) ^ 2)
				if a.stageId == b.stageId and d < StageCraters.reach(a) + StageCraters.reach(b) + 6 then
					apart = false
				end
			end
		end
		check(`§craters every crater lies wholly on its own stage plate{detail}`, placed)
		check("§craters ...at least 8 studs off the side walls", walled)
		check("§craters ...and 20 studs clear of the entrance seam and the far edge (Toxic Twilight's gate)", seams)
		check("§craters no two craters' outer feet come within 6 studs of each other", apart)

		for _, id in Stages.builtIds() do
			local minX, minZ, maxX, maxZ = Stages.bounds(id)
			local blocked, total = 0, 0
			for x = minX + 1, maxX - 1, 2 do
				for z = minZ + 1, maxZ - 1, 2 do
					total += 1
					if StageCraters.blocksDig(id, x, z) then
						blocked += 1
					end
				end
			end
			local share = blocked / total
			if #StageCraters.forStage(id) > 0 then
				check(string.format("§craters stage %d keeps most of its plate diggable (%.1f%% under rims, want < 20%%)", id, share * 100), share < 0.2)
			else
				check(string.format("§craters stage %d has no crater, so nothing blocks a dig", id), blocked == 0)
			end
		end

		for _, c in StageCraters.DEFS do
			if c.digFloor then
				check(`§craters {c.name}'s floor is open to digging at its centre`, not StageCraters.blocksDig(c.stageId, c.center[1], c.center[2]))
			end
		end
	end

	-- NEW: depth-based radiation itself (PLAN's "make it harsher, and make going
	-- deeper and crossing stages feel like it" request). Checked directly against
	-- Stages.radsAt rather than through survival-time math, which is sensitive
	-- enough to small ambient changes that it's the wrong tool for pinning a
	-- geometry fact.
	for _, id in Stages.builtIds() do
		check(string.format("§new stage %d radiation climbs with depth", id), Stages.radsAt(id, 1) > Stages.radsAt(id, 0))
	end
	for id = 2, #Stages.builtIds() do
		check(
			string.format("§new stage %d entrance beats stage %d's deepest point", id, id - 1),
			Stages.radsAt(id, 0) > Stages.radsAt(id - 1, 1)
		)
	end

	-- Config/Sky — the per-stage sky. Art direction, not simulation, so what is
	-- pinned here is the SHAPE of the arc rather than any hex value: the sky only
	-- ever gets thicker, hazier, cloudier and dimmer as you go east, and base camp
	-- is the clearest place in the game. Fourteen hand-authored numbers across seven
	-- rows is exactly the sort of table where one typo silently makes Stage 5 the
	-- pleasant one, and nothing in play would ever tell you.
	do
		-- The arc is Stages 1-6 -- the run out of Base Camp. Stages 7-12 are floor only
		-- (Config/Stages) and fall back to BASE until they get their own looks; add them
		-- here when they do.
		local looks = { SkyConfig.BASE }
		local everyStageSkinned = true
		for _, id in Stages.builtIds() do
			if id > 6 then
				continue
			end
			if SkyConfig.LOOKS[id] == nil then
				everyStageSkinned = false
			end
			table.insert(looks, SkyConfig.get(id))
		end
		check("§sky every stage 1-6 has its own look (none silently falling back to camp)", everyStageSkinned)

		local worsens, brightens, sealed = true, true, false
		for i = 2, #looks do
			local prev, cur = looks[i - 1], looks[i]
			if
				cur.atmoDensity < prev.atmoDensity
				or cur.atmoHaze < prev.atmoHaze
				or cur.atmoGlare < prev.atmoGlare
				or cur.cloudCover < prev.cloudCover
				or cur.cloudDensity < prev.cloudDensity
				or cur.sunRays < prev.sunRays
				or cur.sunSize < prev.sunSize
				or cur.clockTime < prev.clockTime
			then
				worsens = false
			end
			if cur.brightness > prev.brightness then
				brightens = false
			end
		end
		for _, look in looks do
			-- Config/Sky's measured ceilings. Haze is the one that matters and the
			-- one somebody will be tempted to raise, because it is also the knob
			-- that makes the sky take its colour at all: at 4.8 the Crater flattened
			-- into a single amber field with no walls, no ground and no cloud deck.
			-- Density past ~0.6 does the same to distance. And a fully sealed deck
			-- turns the Crater heist into a dark room (PLAN §16).
			if look.cloudCover >= 1 or look.atmoDensity > 0.6 or look.atmoHaze > 3.4 then
				sealed = true
			end
		end
		-- The other lesson from the same afternoon: a cloud deck the same brightness
		-- as the air behind it does not render as a deck, it disappears. Only
		-- enforced once the haze is high enough that the sky has actually TAKEN
		-- atmoColor (~2); below that the sky is still procedural blue and camp's
		-- white clouds are correct precisely because they are brighter than it.
		local function luma(c: Color3): number
			return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
		end
		local deckReads = true
		for _, look in looks do
			if look.atmoHaze >= 2 and luma(look.cloudColor) >= luma(look.atmoColor) then
				deckReads = false
			end
		end
		check("§sky every coloured sky has a cloud deck darker than it (or it vanishes)", deckReads)

		check("§sky air thickens and the sun sinks monotonically with depth", worsens)
		check("§sky the light only ever gets dimmer going east", brightens)
		check("§sky no stage seals the sky over or fogs out the horizon", not sealed)
		check(
			"§sky base camp is the clearest, brightest place in the game",
			SkyConfig.BASE.atmoDensity < SkyConfig.get(1).atmoDensity
				and SkyConfig.BASE.brightness > SkyConfig.get(6).brightness
		)
	end

	-- PLAN §3.5 — over-tier is the WHITE failure state and it ignores your bag.
	-- Tested at depthFrac=0: if being under-tiered fails you even at the shallow
	-- edge, it fails you everywhere, which is the point being checked.
	local overEmpty = survive(5, 3, 0, 0)
	local overFull = survive(5, 3, Decay.totalEmission(bagOf("Rare", "None", 8, 0), 1), 0)
	check("§3.5 over-tier burn is unaffected by what you carry", math.abs(overEmpty - overFull) < 1)
	local overReading = readingAt(5, 3, 0, 0)
	check("§3.5 over-tier flags aura failure", overReading.failing)
	check("§3.5 over-tier dominant threat is burn", Radiation.dominantThreat(overReading, 0, 100) == "burn")

	-- PLAN §3.3 — the greed dial. Carrying loot is the GREEN threat, never the
	-- white one. Tested at depthFrac=0, same "safe at the entrance" reasoning.
	local hotBag = { bagOf("Epic", "None", 1, 0)[1], bagOf("Legendary", "Irradiated", 1, 200)[1] }
	local hotReading = readingAt(3, 3, Decay.totalEmission(hotBag, 1), 0)
	check("§3.3 a hot bag does NOT trip aura failure in your rated stage", not hotReading.failing)
	check("§3.3 a hot bag's threat is exposure, not burn", Radiation.dominantThreat(hotReading, 0, 100) == "exposure")
	local hotS = Radiation.survivableSeconds(hotReading, 0, 100)
	check(string.format("§3.3 cooking Legendary creates real pressure: %.0fs (want 20-90)", hotS), hotS > 20 and hotS < 90)
	check("§3.3 the bag, not the world, is what is killing you", Radiation.greedFraction(hotReading, statsFor(3)) > 0.9)

	-- PLAN §3.3 — but a normal full bag is comfortable. Greed should be a choice, not a tax.
	local fullS = survive(3, 3, Decay.totalEmission(bagOf("Rare", "None", 8, 0), 1))
	check(string.format("§3.3 a full bag of rated loot is comfortable: %.0fs (want 150-330)", fullS), fullS > 150 and fullS < 330)
	check("§3.3 an empty bag at your rated stage's entrance lasts ten minutes+", survive(3, 3, 0) >= 600)

	-- PLAN §5.1 — the haul penalty lives on the Aura now (the Satchel track is retired,
	-- Config/Gear's RETIRED block). Every rung still drags a loaded player, and a better
	-- aura never drags harder per item than the one below it.
	do
		local floored, easing = true, true
		for tier = 1, Gear.maxTier("Aura") do
			local haul = Gear.tier("Aura", tier).haulPenalty
			if type(haul) ~= "number" or haul <= 0 then
				floored = false
			end
			if tier > 1 and haul > Gear.tier("Aura", tier - 1).haulPenalty then
				easing = false
			end
		end
		check("§5.1 every aura's haul penalty stays above zero (capacity is never free)", floored)
		check("§5.1 a better aura never drags harder per item", easing)
		check("§5.1 a new player's first haul drags 0.60/item (halved on request)", Gear.tier("Aura", 1).haulPenalty == 0.60)
	end

	-- The Aura's look (Shared/AuraLook): one per rung, a ladder you can read off the
	-- rings, and never either of the HUD's two reserved colours (PLAN §14's one
	-- colour rule: white is aura failure, green is exposure).
	do
		check("§5.1 every Aura rung has a look", AuraLook.count() == Gear.maxTier("Aura"))
		local climbing, offLimits, sparkling = true, true, true
		local burn, exposure = Color3.fromHex("FFFFFF"), Color3.fromHex("22C55E")
		local function near(a: Color3, b: Color3): boolean
			return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.35
		end
		for tier = 1, AuraLook.count() do
			local look = AuraLook.get(tier)
			if tier > 1 then
				local below = AuraLook.get(tier - 1)
				if look.rings < below.rings or look.width <= below.width or look.speed <= below.speed or look.transparency >= below.transparency then
					climbing = false
				end
				-- The sparkle storm only ever adds: no layer thins out going up.
				for layer, rate in below.sparkle do
					if (look.sparkle :: any)[layer] < rate then
						sparkling = false
					end
				end
			end
			if near(look.color, burn) or near(look.color, exposure) then
				offLimits = false
			end
		end
		check("§5.1 each aura rung is wider, faster and brighter than the one below, never fewer rings", climbing)
		check("§14 no aura is burn-white or exposure-green", offLimits)
		check("§5.1 the top aura has the most rings", AuraLook.get(AuraLook.count()).rings == #AuraLook.TILTS)
		check("§5.1 no aura rung sparkles less than the one below", sparkling)
		local plain = AuraLook.get(2).sparkle
		check("§5.1 auras 1-2 are plain, the sparkles start at 3", plain.dust + plain.shed + plain.embers + plain.burst == 0 and AuraLook.get(3).sparkle.dust > 0)
		check("§5.1 the Nimbus (tier 6) is the helix, the rung under it an atom", AuraLook.get(6).form == "helix" and AuraLook.get(5).form == "atom")
		-- Past the Nimbus, every rung is a shape of its own, drawn from moving curves.
		local ownShapes = true
		local shapes: { [string]: boolean } = {}
		for tier = 7, AuraLook.count() do
			local look = AuraLook.get(tier)
			local form = AuraLook.curveForm(look)
			if form == nil or shapes[look.form] or #form.curves == 0 or #form.riders(0) == 0 then
				ownShapes = false
			end
			shapes[look.form] = true
		end
		check("§5.1 each aura past the Nimbus has its own moving shape", ownShapes)
	end

	-- PLAN §3.6 — the decay clock
	local leg = bagOf("Legendary", "None", 1, 0)[1]
	check("§3.6 Legendary fuse is 2:00", Decay.fuseFor(leg, 1) == 120)
	leg.elapsed = 119
	local s1 = Decay.conditionOf(leg, 1)
	leg.elapsed = 121
	local s2 = Decay.conditionOf(leg, 1)
	leg.elapsed = 361
	local s3 = Decay.conditionOf(leg, 1)
	check("§3.6 Fresh -> Hot at T, Slag past 3T", s1 == 1 and s2 == 2 and s3 == 4)
	check("§3.6 rarer items burn faster", Decay.fuseFor(bagOf("Anomaly", "None", 1, 0)[1], 1) < Decay.fuseFor(bagOf("Common", "None", 1, 0)[1], 1))
	check("§3.6 Slag still retains a token 10%", math.abs(Decay.valueRetained(leg, 1) - 0.10) < 1e-9)

	-- PLAN §3.6 — freezing is total and one-way
	local frozen = bagOf("Mythic", "None", 1, 10)[1]
	frozen.frozen = true
	Decay.tick(frozen, 5, 1)
	check("§3.6 a docked item stops emitting, ticking, and counting down", Decay.totalEmission({ frozen }, 1) == 0 and frozen.elapsed == 10 and Decay.secondsToNextCondition(frozen, 1) == math.huge)

	-- MASTERIES (Config/Masteries) — permanent, tiered, highest tier only
	do
		local Mastery = require(script.Parent.Parent.Mastery)
		local idsOk, goalsOk, valuesOk, baseOk = true, true, true, true
		local seenIds = {}
		for _, def in Masteries.LIST do
			if seenIds[def.id] then
				idsOk = false
			end
			seenIds[def.id] = true
			if #def.goals ~= #Masteries.TIER_NAMES or #def.values ~= #def.goals then
				goalsOk = false
			end
			for i = 2, #def.goals do
				if def.goals[i] <= def.goals[i - 1] then
					goalsOk = false
				end
			end
			local base = Masteries.BASE[def.reward]
			if base == nil then
				baseOk = false
			else
				-- Every tier moves the reward the same way from base, and further each tier.
				local sign = if def.values[1] > base then 1 else -1
				local last = base
				for _, v in def.values do
					if (v - last) * sign <= 0 then
						valuesOk = false
					end
					last = v
				end
			end
		end
		check("§mastery ids are unique", idsOk)
		check("§mastery every mastery has Bronze/Silver/Gold goals, strictly rising", goalsOk)
		check("§mastery every reward kind has a base", baseOk)
		check("§mastery each tier pays more than the one below", valuesOk)

		local scrub = Mastery.get("scrubber") :: any
		check("§mastery below Bronze is no tier", Mastery.tierFor(scrub, scrub.goals[1] - 1) == 0)
		check("§mastery exactly the goal reaches the tier", Mastery.tierFor(scrub, scrub.goals[2]) == 2)
		local fresh = { level = 1, gear = {}, perks = {} }
		local gold = { level = 1, gear = {}, perks = {}, stats = { itemsCleaned = scrub.goals[3], bagsStolen = 1e9 } }
		check("§mastery a fresh save pays every reward at base", Mastery.value(fresh, "cash") == 1 and Mastery.value(fresh, "awayRate") == Tuning.EXHIBIT_OFFLINE_RATE)
		check("§mastery a higher tier REPLACES the lower (Gold Scrubber = its own value)", Mastery.value(gold, "cash") == scrub.values[3])
		local bare = StatResolver.get(fresh)
		local rich = StatResolver.get(gold)
		check(
			"§mastery the cash reward reaches both sales and stand income",
			math.abs(rich.sellMultiplier - bare.sellMultiplier * scrub.values[3]) < 1e-9
				and math.abs(rich.yieldMultiplier - bare.yieldMultiplier * scrub.values[3]) < 1e-9
		)
		local thief = Mastery.get("thief") :: any
		check("§mastery the Thief reward cuts haul drag", math.abs(rich.haulPenalty - bare.haulPenalty * thief.values[3]) < 1e-9)
		local collector = Mastery.get("collector") :: any
		local all = {}
		for _, item in Items.DEFS do
			all[item.id] = true
		end
		check("§mastery the whole index is 100%", Mastery.indexPercent(all) == 100 and Mastery.indexPercent({}) == 0)
		check(
			"§mastery Collector Gold adds its bag slots",
			StatResolver.get({ level = 1, gear = {}, perks = {}, discovered = all }).capacity - bare.capacity == collector.values[3]
		)
		check("§mastery the Reactor bonus raises merge odds", (Merge.odds(0, 0, 1, 0.1) :: any).success > (Merge.odds(0, 0, 1) :: any).success)
		check("§mastery the Brewer can never brew faster than the spin lasts", Tuning.LIQUID_SPIN_COOLDOWN * (Mastery.get("brewer") :: any).values[3] > Tuning.LIQUID_SPIN_SECONDS)
		check("§mastery reward text reads like a reward", Mastery.rewardText(scrub, 3) == "x2 cash" and Mastery.rewardText(thief, 3) == "-50% haul drag")
		check("§mastery goals print short", Mastery.goalText(Mastery.get("tycoon") :: any, 1e9) == "$1B" and Mastery.goalText(Mastery.get("runner") :: any, 50000) == "500K")
	end

	-- PLAN §9.2 / §5.1 — one resolver, perks folded in exactly once
	local profile = {
		level = 20,
		-- No `boots` key: the track is retired (Config/Gear's Gear.Boots header) and
		-- StatResolver no longer looks for one. Speed comes from `speedPoints` below.
		gear = { detector = 3, magnet = 2, cleaner = 4, aura = 3 },
		perks = { steadyHands = true, sureFooting = true },
		multipliers = { sell = 2 },
		speedPoints = Treadmill.requirementFor(45 - Treadmill.START_WALK + 1),
	}
	local stats = StatResolver.get(profile)
	check("§9.2 Steady Hands adds exactly +1 potency", stats.cleanPotency == Gear.tier("Cleaner", 4).power + 1)
	check("§9.2 level 20 = 20% resist", math.abs(stats.levelResist - 0.20) < 1e-9)
	check("§9.2 level 20 = +4 carry capacity", stats.capacity == Gear.tier("Aura", 3).capacity + 4)
	check("§9.2 Sure Footing halves the haul penalty", math.abs(stats.haulPenalty - Gear.tier("Aura", 3).haulPenalty * 0.5) < 1e-9)
	-- SPEED COMES OUT OF THE TREADMILL AND NOTHING ELSE. The profile above holds
	-- exactly the requirement for walk 45, so this is also the check that a player
	-- sitting on a requirement reads as that level and not the one below it.
	check("§5.1 walk speed is whatever the treadmill trained", stats.walkSpeed == 45)
	check("§5.1 a full bag physically slows you", StatResolver.effectiveWalkSpeed(stats, stats.capacity, false) < stats.walkSpeed)
	check("§5.1 but never immobilises you", StatResolver.effectiveWalkSpeed(stats, 999, false) >= 6)

	-- ── §8 BASE FLOORS ────────────────────────────────────────────────────
	--
	-- A base is the ground floor plus up to two bought storeys (Config/Floors). Slot
	-- numbers run on across floors: the ground is 1..9, and each storey adds 9 more.

	check("§8 a base tops out at three floors", Floors.MAX == 3)
	check("§8 the ground floor has 9 free stands", Floors.GROUND_SLOTS == 9 and Floors.slotsFor(1) == 9)
	check("§8 each floor bought adds 9 stands", Floors.slotsFor(2) == 18 and Floors.slotsFor(3) == 27)
	check("§8 the exhibit ceiling is every stand on every floor", Tuning.EXHIBIT_MAX_SLOTS == Floors.slotsFor(Floors.MAX))
	check("§8 a nonsense floor count clamps to a real one", Floors.slotsFor(0) == 9 and Floors.slotsFor(99) == 27 and Floors.clamp(0 / 0) == 1)
	do
		local ok = true
		for slot = 1, Floors.MAX_SLOTS do
			local floor, i = Floors.floorOf(slot)
			if floor == nil or i == nil or Floors.firstSlot(floor) + i - 1 ~= slot then
				ok = false
			end
			-- unlocked by buying `floor`, and not by anything less
			if floor ~= nil and (slot > Floors.slotsFor(floor) or (floor > 1 and slot <= Floors.slotsFor(floor - 1))) then
				ok = false
			end
		end
		check("§8 every slot sits on exactly one floor, numbered on from the one below", ok and Floors.floorOf(Floors.MAX_SLOTS + 1) == nil)
	end
	do
		local rising = true
		for floor = 2, Floors.MAX do
			local price = Floors.PRICES[floor]
			if price == nil or price <= 0 or (floor > 2 and price <= (Floors.PRICES[floor - 1] :: number)) then
				rising = false
			end
		end
		check("§8 every floor above the ground has a price, each dearer than the last", rising and Floors.PRICES[1] == nil)
		check("§8 a full base has nothing left to buy", Floors.nextPrice(Floors.MAX) == nil and Floors.nextPrice(1) == Floors.PRICES[2])
	end

	-- ── §5.1 THE TREADMILL ────────────────────────────────────────────────
	--
	-- The Speed unit and its levels (Config/Treadmill). These are the checks that stop
	-- a retune from quietly turning an 11-hour endgame into a 2-hour one.

	check("§5.1 level 1 walks at the starting speed, 30", Treadmill.walkSpeedFor(1) == 30)
	check("§5.1 one level is one stud/sec: level 71 walks at 100, the old cap", Treadmill.walkSpeedFor(71) == Treadmill.ENDGAME_WALK)
	check("§5.1 level 1 needs no Speed", Treadmill.requirementFor(1) == 0 and Treadmill.levelFor(0) == 1)
	check(
		"§5.1 there is no top level: past the old cap still has a next requirement",
		Treadmill.requirementFor(76) ~= nil and Treadmill.requirementFor(150) ~= nil and Treadmill.walkSpeedFor(150) == 179
	)

	-- Every requirement is dearer than the last, and holding EXACTLY a requirement
	-- reads as that level with an empty bar — never the level below with a full one,
	-- which is the most visible bug this feature could have.
	do
		local rising, exact = true, true
		for level = 1, 150 do
			local req = Treadmill.requirementFor(level) :: number
			if level > 1 and req <= (Treadmill.requirementFor(level - 1) :: number) then
				rising = false
			end
			local got, progress = Treadmill.levelFor(req)
			if got ~= level or progress ~= 0 then
				exact = false
			end
			if level > 1 and Treadmill.levelFor(req - 0.01) ~= level - 1 then
				exact = false
			end
		end
		check("§5.1 each level's Speed requirement is higher than the last", rising)
		check("§5.1 reaching a requirement levels you up exactly on it", exact)
		-- A huge or broken total still reads as a finite level, not a hang or an error.
		local huge = Treadmill.levelFor(1e12)
		check("§5.1 any Speed total reads as a finite level", huge > 75 and huge < 1000 and Treadmill.levelFor(0 / 0) == 1)
	end

	-- THE BELTS: dearer each rung, and each pays meaningfully more Speed/sec. With no
	-- rated-speed falloff left, the rate ladder is the whole reason to upgrade.
	do
		local rising = true
		for index = 2, Treadmill.maxTier() do
			local prev, def = Treadmill.TIERS[index - 1], Treadmill.TIERS[index]
			if def.price <= prev.price or def.rate < prev.rate * 1.5 then
				rising = false
			end
		end
		check("§5.1 each belt costs more and pays at least 1.5x the Speed/sec of the last", rising)
		check("§5.1 a belt's rate does not fall off with level", Treadmill.rateFor(1) == Treadmill.TIERS[1].rate)
	end

	-- The three numbers the curve was tuned against, measured the way a player
	-- experiences them: buying one belt per 18 levels (four belts over 75 levels). Bands are ±25%, wide enough that
	-- a cosmetic tweak to one rung does not fail the suite and narrow enough that
	-- "11 hours" cannot drift into "3 hours" unnoticed.
	do
		local function hoursTo(walk: number, belt: ((level: number) -> number)?): number
			local seconds = 0
			for level = 1, walk - Treadmill.START_WALK do
				local tier = if belt then belt(level) else math.min(Treadmill.maxTier(), (level - 1) // 18 + 1)
				local cost = (Treadmill.requirementFor(level + 1) :: number) - (Treadmill.requirementFor(level) :: number)
				seconds += cost / Treadmill.rateFor(tier)
			end
			return seconds / 3600
		end

		for _, milestone in { { at = 45, hours = 0.24 }, { at = 70, hours = 1.05 }, { at = 100, hours = 3.7 } } do
			local actual = hoursTo(milestone.at)
			check(
				string.format("§5.1 walk %d is about %.1f h of training (got %.2f h)", milestone.at, milestone.hours, actual),
				actual > milestone.hours * 0.75 and actual < milestone.hours * 1.25
			)
		end

		-- ...and never upgrading costs something real without walling anyone out.
		local stuck = hoursTo(64, function()
			return 1
		end)
		check(
			string.format("§5.1 skipping the belts is slow, not blocked (%.1f h to walk 64 on the free belt)", stuck),
			stuck > hoursTo(64) * 2 and stuck < math.huge
		)
	end

	-- THE CONVERSION KEEPS EVERY LEVEL. Old saves banked hidden `speedXp` on a
	-- different curve; DataService converts it once. A player must land on the same
	-- walk speed with the same fraction of the bar, at every walk speed.
	do
		local kept = true
		for walk = Treadmill.START_WALK, Treadmill.ENDGAME_WALK - 1 do
			local n = walk - Treadmill.START_WALK
			local base = 110 * (1.068 ^ n - 1) / 0.068
			local halfway = base + 0.5 * 110 * 1.068 ^ n
			local w1, p1 = Treadmill.walkFor(Treadmill.fromLegacyXp(base))
			local w2, p2 = Treadmill.walkFor(Treadmill.fromLegacyXp(halfway))
			if w1 ~= walk or p1 > 1e-6 or w2 ~= walk or math.abs(p2 - 0.5) > 1e-6 then
				kept = false
			end
		end
		check("§5.1 converting an old save keeps its walk speed and its bar", kept)
		check("§5.1 a maxed old save converts to walk 100, its old cap", Treadmill.walkFor(Treadmill.fromLegacyXp(1e9)) == Treadmill.ENDGAME_WALK)
	end

	-- THE FOUR-BELT COLLAPSE LOSES NOBODY A DOLLAR. The ladder went from six belts to
	-- four (one imported model each); DataService moves an old save onto the best new
	-- belt its old spend covers and pays the rest back. New belt + refund must add back
	-- up to exactly what the old rungs cost, at every old rung, and never hand anyone a
	-- belt dearer than they paid for.
	do
		local oldPrices = { 0, 11500, 32500, 90000, 255000, 700000 }
		local fair = true
		local spent = 0
		for oldTier = 1, #oldPrices do
			spent += oldPrices[oldTier]
			local tier, refund = Treadmill.fromSixRungLadder(oldTier)
			local newSpent = 0
			for index = 2, tier do
				newSpent += Treadmill.TIERS[index].price
			end
			local nextRung = Treadmill.TIERS[tier + 1]
			if newSpent + refund ~= spent or refund < 0 or (nextRung and refund >= nextRung.price) then
				fair = false
			end
		end
		check("§5.1 collapsing a six-belt save refunds exactly what the new belt does not cover", fair)
		-- "A maxed six-belt save lands on the top belt" used to be pinned here. It only held
		-- while the top belt kept the old ladder's $700k price; the economy pacing pass
		-- repriced every belt, so a maxed old save now lands lower and takes the rest as
		-- cash -- still exactly what it spent, which the check above pins.
		check("§5.1 a free-belt save stays on the free belt with no refund", select(2, Treadmill.fromSixRungLadder(1)) == 0)
	end

	-- Treadmill ACCESS is free on request (it used to cost $1,000): every player starts
	-- on the Scrap Belt, and only the belt upgrades cost cash.
	check(
		string.format("§5.1 unlocking the treadmill is free (%s)", Treadmill.unlockPriceText()),
		Treadmill.UNLOCK_PRICE == 0 and Treadmill.unlockPriceText() == "Free"
	)

	-- Every belt names the imported model it wears (build/Plots.setTreadmillTier).
	do
		local named = true
		for _, belt in Treadmill.TIERS do
			if type(belt.model) ~= "string" or belt.model == "" then
				named = false
			end
		end
		check("§5.1 every belt rung names its treadmill model", named)
	end

	-- The track really is gone from the storefront. `Gear.Boots` surviving as data for
	-- the refund is exactly the state that could rot into "it is still half-sold".
	do
		local listed = false
		for _, track in Gear.TRACKS do
			if track == "Boots" then
				listed = true
			end
		end
		check("§5.1 the Boots track is retired, not merely unstocked", not listed and Gear.STAT_META.Boots == nil)
	end

	-- The liquid folds into effectivePotency and NOWHERE ELSE. `cleanPotency` is the
	-- permanent capability the Locker and the hose shop both read; the day someone
	-- "simplifies" this by adding the bonus into cleanPotency directly, the Locker
	-- starts promising items it cannot keep once the canister empties.
	check("§2.4 no liquid loaded means the two potencies agree", stats.effectivePotency == stats.cleanPotency)

	local hosed = table.clone(profile) :: any
	hosed.liquids = { lava = 3 }
	hosed.equippedLiquid = "lava"
	local hosedStats = StatResolver.get(hosed)
	check("§2.4 a loaded liquid raises effectivePotency", hosedStats.effectivePotency == stats.cleanPotency + Liquids.get("lava").potency)
	check("§2.4 ...and leaves cleanPotency alone", hosedStats.cleanPotency == stats.cleanPotency)

	-- AN EMPTY CANISTER IS THE SAME THING AS NO CANISTER. StatResolver.liquidFor is
	-- the single place that rule is written down, which is the only reason
	-- DeconService, CarryService and the panel cannot each forget it separately.
	local dry = table.clone(profile) :: any
	dry.liquids = { lava = 0 }
	dry.equippedLiquid = "lava"
	local dryStats = StatResolver.get(dry)
	check("§2.4 a spent canister falls back to Plain Water", dryStats.liquidId == Liquids.WATER and dryStats.effectivePotency == stats.cleanPotency)

	-- ── The wash pad (Config/Liquids, Config/Gear's luckMultiplier/luckPrice) ──────
	--
	-- THE ONE THAT MATTERS MOST IS THE POTENCY CAP. Liquids lend potency on top of
	-- the Cleaner track, and the Cleaner track is PLAN §2 step 4's second hard gate —
	-- the thing that makes the Quarantine Locker fill and the hose shop sell.
	-- Nudging one liquid's `potency` to 5 because a playtester found the wall
	-- annoying would silently delete that gate, and it would not fail anywhere else.
	local worstBonus = 0
	for _, id in Liquids.ORDER do
		worstBonus = math.max(worstBonus, Liquids.get(id).potency)
	end
	check(
		string.format("§2.4 no liquid lends more than +%d potency (found +%d)", Liquids.MAX_POTENCY_BONUS, worstBonus),
		worstBonus <= Liquids.MAX_POTENCY_BONUS
	)

	-- ── The hose ladder (Config/Gear.Cleaner, Config/ToolTiers, ToolModels/Hose) ──
	--
	-- THREE TABLES DESCRIBE ONE LADDER and nothing but these checks stops them
	-- diverging. Gear.Cleaner is the rungs (price, power, volume), ToolTiers is
	-- their palette, ToolModels/Hose is their geometry. Every one of the three clamps
	-- an out-of-range tier rather than erroring — which is right for a live server and
	-- exactly why a mismatch is invisible in play: add an eighth rung to Gear and the
	-- shop sells it, takes the money, and hands you the seventh hose forever.
	local cleanerRungs = Gear.maxTier("Cleaner")
	check(
		string.format("the hose ladder has one look per rung (%d rungs, %d looks)", cleanerRungs, ToolTiers.count("Cleaner")),
		ToolTiers.count("Cleaner") == cleanerRungs
	)
	check(
		string.format("the hose ladder has one model per rung (%d rungs, %d forms)", cleanerRungs, ToolModels.Hose.count()),
		ToolModels.Hose.count() == cleanerRungs
	)

	-- ToolTiers' own header says "names mirror Gear.lua exactly; if they ever disagree,
	-- Gear.lua wins". That was a comment for six years and a rule for none of them.
	for tier = 1, cleanerRungs do
		local rung, look = Gear.tier("Cleaner", tier), ToolTiers.get("Cleaner", tier)
		check(`hose {tier} agrees on its name: "{rung.name}" / "{look.name}"`, rung.name == look.name)

		-- build/Plots.paintHoseRig repaints the reel drum, its coil band and the Beam to
		-- this so the hose "still on the reel" follows the nozzle a purchase swaps in.
		-- The drum is the body colour and the coil is strictly darker, same as the grip.
		local rig = ToolModels.Hose.rigLook(tier)
		check(`hose {tier} rig drum matches the tier body`, rig.body == look.body)
		check(`hose {tier} rig coil is darker than the drum`, rig.coil ~= rig.body and rig.coil.R <= rig.body.R and rig.coil.G <= rig.body.G and rig.coil.B <= rig.body.B)
	end

	-- CarryService.hoseNameFor WALKS THIS TABLE IN ORDER and returns the first rung
	-- that reaches a hardness, so ascending `power` is not a nicety — a table sorted
	-- any other way makes "needs the Chem Injector" name the wrong hose, and it names
	-- it confidently. Ascending price is the same promise made to the shop rack.
	--
	-- ASCENDING VOLUME IS THE NEWER HALF, and it is checked for a reason that only
	-- exists now that the hose is a machine you look at: WashController scales the
	-- stream's girth off `volume` (WashService.push sends it), so a rung whose volume
	-- went DOWN would visibly dribble harder than the rung below it while costing more.
	-- Volume gates nothing, which is exactly why nothing else would catch it.
	for tier = 2, cleanerRungs do
		local prev, this = Gear.tier("Cleaner", tier - 1), Gear.tier("Cleaner", tier)
		check(`hose {tier} costs more than {tier - 1}`, this.price > prev.price)
		check(`hose {tier} reaches further than {tier - 1}`, this.power > prev.power)
		check(`hose {tier} throws more water than {tier - 1}`, this.volume > prev.volume)
	end

	-- THE HOSE ON THE MAST IS THE ONE THE LADDER SELLS. build/Plots parks the station's
	-- monitor at STATION_TIER for a plot nobody owns yet, and ExhibitService swaps it to
	-- the owner's rung from the same factory — so a STATION_TIER off the end of the
	-- ladder would silently clamp and an unclaimed plot would show a hose that is not
	-- for sale anywhere.
	check(
		`the station's parked hose is a real rung (tier {ToolModels.Hose.STATION_TIER})`,
		ToolModels.Hose.STATION_TIER >= 1 and ToolModels.Hose.STATION_TIER <= cleanerRungs
	)

	-- The starting hose plus the best possible roll must still hit a wall inside the
	-- catalogue, or the Cleaner track is decorative for a lucky player. Named off the
	-- table rather than hardcoded to "Garden Hose": the ladder has been renamed once
	-- already (it was Wire Brush -> Plasma Scour before the seven hoses), and a check
	-- whose MESSAGE goes stale while its assertion still passes is a check nobody
	-- trusts the second time they read it.
	local startingHose = Gear.tier("Cleaner", 1)
	local startingReach = startingHose.power + Liquids.MAX_POTENCY_BONUS
	check(
		string.format("§2.4 %s + the best liquid reaches hardness %d, short of Epic (%d)", startingHose.name, startingReach, Rarity.get("Epic").hardness),
		startingReach < Rarity.get("Epic").hardness
	)

	-- ── The storefront ──────────────────────────────────────────────────
	--
	-- WHAT THE SHOP SELLS IS A LIST IN Config/Gear, AND THIS IS WHAT KEEPS IT HONEST.
	-- The panel used to build a card's stat block by walking the tier table itself, so
	-- every column was advertised whether or not it did anything — which is how
	-- `clarity` came to be sold on every detector for months after DigService stopped
	-- reading it. `Gear.STAT_META[track].order` is the list now, and a column that is
	-- in neither `order` nor `hidden` is a stat that silently vanished from the
	-- storefront (or a dead one that silently appeared in it). Both are failures; this
	-- is the only thing that would ever notice.
	for _, track in Gear.TRACKS do
		local meta = Gear.STAT_META[track]
		check(`{track} has a shop stat list`, meta ~= nil and meta.order ~= nil)
		if meta == nil or meta.order == nil then
			continue
		end

		local colours = {}
		for _, key in meta.order do
			check(`{track}'s "{key}" column has a shop label`, meta[key] ~= nil and meta[key].label ~= nil)
			-- Every stat has its own colour, and no gear shows the same colour twice.
			local colour = meta[key] and meta[key].color
			check(`{track}'s "{key}" column has a stat colour`, typeof(colour) == "Color3")
			if typeof(colour) == "Color3" then
				local hex = colour:ToHex()
				check(`{track}'s "{key}" colour is not shared with another {track} stat`, colours[hex] == nil)
				colours[hex] = true
			end
		end

		for tier = 1, Gear.maxTier(track) do
			local def = Gear.tier(track, tier)

			-- ONE LINE OF COPY PER RUNG, and it is not optional: the card is laid out
			-- around it, so a missing blurb is a hole in the middle of the card rather
			-- than a graceful absence.
			check(
				`{track} {tier} ({def.name}) has a blurb`,
				type(def.blurb) == "string" and #def.blurb > 0
			)

			for key, value in def :: any do
				if Gear.STAT_CHROME[key] then
					continue
				end
				if type(value) ~= "number" and type(value) ~= "boolean" then
					continue
				end
				local sold = false
				for _, ordered in meta.order do
					if ordered == key then
						sold = true
						break
					end
				end
				check(
					`{track}'s "{key}" is either sold or deliberately hidden`,
					sold or (meta.hidden ~= nil and meta.hidden[key] == true)
				)
			end
		end
	end

	-- PLAIN WATER IS THE FLOOR, AND IT IS THE ANTI-SOFTLOCK. A player with no cash
	-- and no canisters must still be able to clean something, or "I cannot progress
	-- and cannot fix it" becomes reachable — the one state this design has no answer
	-- for. Three properties make that true and all three are load-bearing.
	local water = Liquids.get(Liquids.WATER)
	check("§2.4 Plain Water is the bottom of the table", water.order == 1)
	check("§2.4 Plain Water lends no potency (it cannot be a gate key)", water.potency == 0)
	check("§2.4 Plain Water is never rolled (it is always simply there)", not Liquids.isRollable(Liquids.WATER))

	-- LUCK MUST NEVER MAKE ANYTHING YOU WANTED RARER. `effectiveWeight` raises luck
	-- to a per-entry exponent, so a negative or accidentally-zero bias on a top-end
	-- entry would make buying Luck actively harmful — invisible in play until someone
	-- well into the button notices they stopped seeing Stardust.
	--
	-- LUCK HAS NO CEILING ANY MORE (Config/Gear.luau's header) — every purchase is a
	-- flat +Gear.LUCK_STEP forever, at a compounding price. 8.0x is not a real cap; it is the
	-- old seven-tier ladder's top rung, kept here as a fixed, well-understood
	-- reference point so the invariants below (and the numbers in their own
	-- descriptions, like "12.5%" and "28.5x") keep meaning the same thing across a
	-- refactor of how a player actually GETS there.
	local luckFloor = Gear.luckMultiplier(1)
	local luckCeiling = 8.0
	local oddsLo, oddsHi = Liquids.oddsAt(luckFloor), Liquids.oddsAt(luckCeiling)

	-- THE INVARIANT IS "MASS MOVES UP THE TABLE", NOT "EVERY ENTRY GETS LIKELIER",
	-- and the first draft of this check asserted the second one and failed. It failed
	-- CORRECTLY: Fizzy Pop's share drops 17.9% -> 9.8% across the ladder despite a
	-- positive bias, because it gains on Soapy Suds while losing to everything above
	-- it. That is what a luck curve is supposed to do. What must never happen is an
	-- INVERSION -- a rarer liquid becoming relatively rarer than a commoner one --
	-- so the pairwise ratio is the thing to pin.
	local rollable: { string } = {}
	for _, id in Liquids.ORDER do
		if Liquids.isRollable(id) then
			table.insert(rollable, id)
		end
	end

	local monotone = true
	local biasAscending = true
	for index = 2, #rollable do
		local rarer, commoner = rollable[index], rollable[index - 1]
		if oddsHi[rarer] / oddsHi[commoner] <= oddsLo[rarer] / oddsLo[commoner] then
			monotone = false
		end
		if Liquids.get(rarer).luckBias <= Liquids.get(commoner).luckBias then
			biasAscending = false
		end
	end
	check("§6 luck only ever moves mass UP the table (no inversions)", monotone)
	check("§6 luckBias rises with every rung, which is what guarantees that", biasAscending)

	-- The brew reveal's tier chip (LiquidController) reads `tier` off the def and its
	-- colour off Config/Rarity, so a typo there is a nil index mid-reveal.
	local tiersValid = true
	for index, id in rollable do
		local tier = Liquids.get(id).tier
		local def = tier and Rarity.DEFS[tier]
		if def == nil then
			tiersValid = false
		elseif index > 1 then
			local below = Rarity.DEFS[Liquids.get(rollable[index - 1]).tier or ""]
			if below and def.order < below.order then
				tiersValid = false
			end
		end
	end
	check("§6 every rollable liquid has a real Rarity tier, never stepping down the table", tiersValid)

	local sumLo, sumHi = 0, 0
	for _, chance in oddsLo do
		sumLo += chance
	end
	for _, chance in oddsHi do
		sumHi += chance
	end
	check("§6 the odds table is a probability distribution at both ends", math.abs(sumLo - 1) < 1e-9 and math.abs(sumHi - 1) < 1e-9)

	-- THE FLOOR NEVER DISAPPEARS. A roll you can predict is not a roll; if pushing
	-- luck this far ever drops the commonest liquid under ~10% the pad has become a
	-- vending machine and the reveal animation is lying about there being a moment.
	local commonest = Liquids.ORDER[2]
	check(
		string.format("§6 the common end survives luck %.1fx: %s at %.1f%% (want >= 10%%)", luckCeiling, Liquids.get(commonest).name, oddsHi[commonest] * 100),
		oddsHi[commonest] >= 0.10
	)

	-- ...and the jackpot has to visibly move, or the button reads as a tax.
	local jackpot = Liquids.ORDER[#Liquids.ORDER]
	check(
		string.format("§6 luck %.1fx multiplies the jackpot %.1fx (want >= 5x)", luckCeiling, oddsHi[jackpot] / oddsLo[jackpot]),
		oddsHi[jackpot] / oddsLo[jackpot] >= 5
	)

	-- EVERY PURCHASE MUST BE BOTH LUCKIER AND PRICIER THAN THE LAST, forever — the
	-- one invariant a fixed ladder used to guarantee by construction and a formula
	-- has to be checked instead. 200 purchases is arbitrary and large: a formula that
	-- breaks monotonicity does so either immediately or via a slow float-precision
	-- drift, and 200 steps is enough runway to catch either.
	local luckAscending = true
	for level = 2, 200 do
		if Gear.luckMultiplier(level) <= Gear.luckMultiplier(level - 1) or Gear.luckPrice(level) <= Gear.luckPrice(level - 1) then
			luckAscending = false
		end
	end
	check("§6 every luck purchase is both luckier and pricier than the last", luckAscending)

	-- THE SPIN MUST LAND BEFORE THE NEXT ONE IS ALLOWED. The fluid spin is free and
	-- the cooldown is its only limiter (Tuning's fluid-spin block); a cooldown shorter
	-- than the on-screen spin would let a second spin start under the first one's
	-- reveal, and the bottle would recolour out of order.
	check(
		string.format("§6 the fluid spin (%ds) lands inside its own cooldown (%ds)", Tuning.LIQUID_SPIN_SECONDS, Tuning.LIQUID_SPIN_COOLDOWN),
		Tuning.LIQUID_SPIN_SECONDS < Tuning.LIQUID_SPIN_COOLDOWN
	)

	-- PLAN §2 step 1 — the reveal. These are the checks that catch someone "fixing"
	-- the Detector track's weak payoff by widening the radius, which is the one lever
	-- the design says must not move (see the header of Config/Gear).
	local ascending = true
	for tier = 2, Gear.maxTier("Detector") do
		if Gear.tier("Detector", tier).radius <= Gear.tier("Detector", tier - 1).radius then
			ascending = false
		end
	end
	check("§2.1 every detector tier reveals further than the last", ascending)

	-- `luck` replaced `maxRarity`. Tier 1 must be exactly 1.0 -- Config/Items.luckBias
	-- treats <=1 as "no bias", so a Rust Bucket rolls the raw per-stage distribution --
	-- and every tier above must buy strictly more of it.
	check("§2.1 the starting detector has luck 1.0 (no dig bias)", Gear.tier("Detector", 1).luck == 1.0)
	local luckAsc = true
	for tier = 2, Gear.maxTier("Detector") do
		if Gear.tier("Detector", tier).luck <= Gear.tier("Detector", tier - 1).luck then
			luckAsc = false
		end
	end
	check("§2.1 every detector tier is luckier than the last", luckAsc)

	-- ── The detector ladder is ONE ladder sold at more than one camp ──────────────
	--
	-- Config/Gear's `camp` column says whose stall sells a rung (nil is Base Camp), and
	-- Toxic Twilight sells tiers 10-15. Three things quietly go wrong if that column and
	-- its neighbours drift, and none of them errors:
	--
	--   * ToolTiers is the palette AND the name ToolFX keys off, and ToolTiers.get CLAMPS. A
	--     rung with no row of its own reads as the last row that has one, so a sixteenth
	--     detector would light up with The Oracle's lens and glints.
	--   * a `camp` that is not a Config/Camps key is a rung no stall in the world sells (a
	--     typo, or a camp that was renamed), which the shop would price and never offer.
	--   * the rack hangs a stall's rungs left to right in ladder order, so a camp whose rungs
	--     are not one unbroken run would hang a rack with a hole in the price ladder.
	local detectorRungs = Gear.maxTier("Detector")
	check(
		string.format("the detector ladder has one look per rung (%d rungs, %d looks)", detectorRungs, ToolTiers.count("Detector")),
		ToolTiers.count("Detector") == detectorRungs
	)
	local looksAgree = true
	for tier = 1, detectorRungs do
		if Gear.tier("Detector", tier).name ~= ToolTiers.get("Detector", tier).name then
			looksAgree = false
		end
	end
	check("the detector ladder's looks carry the rungs' own names (ToolFX keys off them)", looksAgree)

	local campsReal, campsUnbroken = true, true
	local campsSeen: { [string]: boolean } = {}
	local previousCamp = ""
	for tier = 1, detectorRungs do
		local camp = Gear.campOf("Detector", tier)
		if camp ~= Camps.BASE and Camps.get(camp) == nil then
			campsReal = false
		end
		if camp ~= previousCamp then
			if campsSeen[camp] then
				campsUnbroken = false
			end
			campsSeen[camp] = true
			previousCamp = camp
		end
	end
	check("every detector rung is sold at a real camp (Config/Camps)", campsReal)
	check("each camp's detector rungs are one unbroken run of the ladder", campsUnbroken)
	check("Base Camp sells the first rung of every track (the free one)", (function()
		for _, track in Gear.TRACKS do
			if Gear.campOf(track, 1) ~= Camps.BASE then
				return false
			end
		end
		return true
	end)())

	-- Twilight's six, pinned by name so a reorder of the ladder is a decision, not a drift:
	-- the shop's rack and cards, the model templates (Assets/Tools/Detector/T10-T15) and
	-- the hold poses were all made for exactly this order.
	local twilightWant = { "Vein Whisperer", "Aurora Rake", "Strata Lance", "Leyline Tap", "Null Compass", "Prime Meridian" }
	local twilightHave = Gear.tiersAt("Detector", "twilight")
	local twilightOk = #twilightHave == #twilightWant
	for slot, tier in twilightHave do
		if Gear.tier("Detector", tier).name ~= twilightWant[slot] or tier ~= 9 + slot then
			twilightOk = false
		end
	end
	check("Toxic Twilight sells detector tiers 10-15, in the order they were drawn", twilightOk)

	-- The magnet ladder is sold the same way (Twilight sells tiers 7-11), so the same
	-- three drifts apply: a look per rung (ToolFX keys off the name, and get clamps, so
	-- an Omega with no row would sprout the Singularity Coil's core halo), real camps,
	-- and one unbroken run per camp. Then the five pinned by name, because the templates
	-- (Assets/Tools/Magnet/T7-T11) were made for exactly this order.
	local magnetRungs = Gear.maxTier("Magnet")
	local magnetLooks = ToolTiers.count("Magnet") == magnetRungs
	local magnetCampsOk = true
	local magnetSeen: { [string]: boolean } = {}
	local magnetPrevious = ""
	for tier = 1, magnetRungs do
		if Gear.tier("Magnet", tier).name ~= ToolTiers.get("Magnet", tier).name then
			magnetLooks = false
		end
		local camp = Gear.campOf("Magnet", tier)
		if camp ~= Camps.BASE and Camps.get(camp) == nil then
			magnetCampsOk = false
		end
		if camp ~= magnetPrevious then
			if magnetSeen[camp] then
				magnetCampsOk = false
			end
			magnetSeen[camp] = true
			magnetPrevious = camp
		end
	end
	check(string.format("the magnet ladder has one look per rung, by name (%d rungs, %d looks)", magnetRungs, ToolTiers.count("Magnet")), magnetLooks)
	check("each camp's magnet rungs are one unbroken run at a real camp", magnetCampsOk)

	local twilightMagnetsWant = { "Lattice Magnet", "Solar Magnet", "Void Magnet", "Nebula Magnet", "Omega Magnet" }
	local twilightMagnetsHave = Gear.tiersAt("Magnet", "twilight")
	local twilightMagnetsOk = #twilightMagnetsHave == #twilightMagnetsWant
	for slot, tier in twilightMagnetsHave do
		if Gear.tier("Magnet", tier).name ~= twilightMagnetsWant[slot] or tier ~= 6 + slot then
			twilightMagnetsOk = false
		end
	end
	check("Toxic Twilight sells magnet tiers 7-11, in the art pack's order", twilightMagnetsOk)

	-- Twilight's five hoses, pinned by name for the same reason: the templates
	-- (Assets/HoseModels/T8-T12, via ToolModels/Hose's ART_SLOTS) were made for
	-- exactly this order, the user's. Tiers 7-11 since the Ultrasonic Jet was cut.
	local twilightHosesWant = { "Singularity Nozzle", "Cryo Nova", "Solar Forge", "Quantum Rift", "Celestial Deluge" }
	local twilightHosesHave = Gear.tiersAt("Cleaner", "twilight")
	local twilightHosesOk = #twilightHosesHave == #twilightHosesWant
	for slot, tier in twilightHosesHave do
		if Gear.tier("Cleaner", tier).name ~= twilightHosesWant[slot] or tier ~= 6 + slot then
			twilightHosesOk = false
		end
	end
	check("Toxic Twilight sells hose tiers 7-11, in the user's order", twilightHosesOk)

	-- Twilight's five auras, pinned by name: AuraLook's shapes (aurora, torus, wings,
	-- seraph, vortex) are drawn per tier in exactly this order. Dusk Corona was cut
	-- and the rest slid down one rung (Config/Gear).
	local twilightAurasWant = { "Toxic Aurora", "Eclipse Veil", "Twilight Singularity", "Seraph", "Crimson Vortex" }
	local twilightAurasHave = Gear.tiersAt("Aura", "twilight")
	local twilightAurasOk = #twilightAurasHave == #twilightAurasWant
	for slot, tier in twilightAurasHave do
		if Gear.tier("Aura", tier).name ~= twilightAurasWant[slot] or tier ~= 6 + slot then
			twilightAurasOk = false
		end
	end
	check("Toxic Twilight sells aura tiers 7-11, in the order their shapes were picked", twilightAurasOk)

	-- Revealing is not the same as reaching. If the pull radius ever grows into the
	-- reveal radius, the walk to the glow disappears and the loop is one button.
	check(
		string.format("§2.1 the walk to the glow survives (dig %d vs reveal %d)", Tuning.DIG_RADIUS, Gear.tier("Detector", 1).radius),
		Tuning.DIG_RADIUS * 2 < Gear.tier("Detector", 1).radius
	)

	-- A spot surfaces at the edge of your detector radius and you can stand on it at
	-- DIG_RADIUS, so the gap between the two is all the time client/SpotCracks has to
	-- fade the thing in before the player is on top of it — and it is the STARTING
	-- detector against the FASTEST a player can ever move that sets the floor, since a
	-- wider radius only ever buys more walk. It came to 0.22s, and the reveal was 0.6:
	-- the pick-up card landed on ground that was still bare. Widening DIG_RADIUS or
	-- narrowing the first detector shrinks this again, silently, from two files away.
	--
	-- *** THIS CHECK FAILS ON PURPOSE, AND IT IS THE THIRD KNOWN FAILURE. ***
	--
	-- The ceiling used to be the top Boots rung (36), then the treadmill cap (100). There
	-- is no cap now, so this measures at Treadmill.ENDGAME_WALK (100), the old one.
	-- That is not a rename — it is a real and unsolvable tightening. The gap
	-- between the starting detector's reveal edge and DIG_RADIUS is 8 studs; a fully
	-- trained player crosses it in 0.08s, and client/SpotCracks' REVEAL is 0.25s on an
	-- ease-out (~70% up at 0.08s since the pop pass). So a maxed player still arrives
	-- at ground that is coming up, just much less of it.
	--
	-- IT CANNOT BE FIXED FROM HERE. Holding 0.2s of walk at speed 100 needs `reach`
	-- >= 20 studs, and the starting detector's whole radius is 13 — shrinking
	-- DIG_RADIUS cannot get there. The two real fixes are both design calls:
	--
	--   * widen the starting detector (radius 25+), which makes §2.1's two other
	--     known failures — contact density already being too fast — worse; or
	--   * scale the REVEAL RADIUS with trained speed in DigService, so a fast player
	--     simply has spots surface further out. This is the better one.
	--
	-- Left failing rather than re-pointed at a friendlier speed, because a check that
	-- is quietly weakened to go green stops being a check. What currently carries the
	-- player-facing half of this is DetectorController's PROMPT_MIN_SHOWN — the PICK
	-- UP card waits a beat for the spot, which SpotCracks' own header calls "the
	-- cheaper half" of exactly this fix.
	do
		local reach = Gear.tier("Detector", 1).radius - Tuning.DIG_RADIUS
		local fastest = Treadmill.ENDGAME_WALK
		check(
			string.format("§2.1 a spot has time to fade in before you reach it (%.2fs of walk)", reach / fastest),
			reach / fastest >= 0.2
		)
	end

	-- An aura nobody is revealing lingers so the clients can fade it out instead of it
	-- vanishing between two frames (Tuning.AURA_LINGER). Two things have to hold, and
	-- both are easy to break from the other end of the codebase:
	--   * the linger has to outlast client/SpotCracks' FADE_OUT (0.6s) with room for the
	--     flag to replicate, or the part is deleted mid-fade and the pop is back;
	--   * it has to stay SHORT. It is also the window in which a glow stands over ground
	--     the player can no longer read, and (DigService.standingOnUnregistered) counts
	--     as a glow to be confused by. A second is a fade; five is a lie.
	check(
		string.format("§2.1 an unrevealed aura fades out rather than vanishing (%.2fs linger)", Tuning.AURA_LINGER),
		Tuning.AURA_LINGER >= 0.8 and Tuning.AURA_LINGER <= 1.5
	)

	local field = Stages.builtIds()[1]
	if field then
		local walk = Treadmill.START_WALK
		local lo = Gear.tier("Detector", 1).radius
		local hi = Gear.tier("Detector", Gear.maxTier("Detector")).radius
		local slow = Stages.secondsBetweenContacts(field, lo, walk, Tuning.SIGNALS_PER_STAGE)
		local fast = Stages.secondsBetweenContacts(field, hi, walk, Tuning.SIGNALS_PER_STAGE)
		-- BANDS RE-FITTED TO THE UNIFORM-LENGTH PASS (Config/Stages header), then left
		-- alone through three footprint moves because the numbers stayed inside them.
		-- (Fewer-signals pass: N 75 -> 40 put slow/fast back at ~1.8s / ~0.5s; the second,
		-- 40 -> 28, at ~2.2s / ~0.60s.)
		-- Every stage is 290 x 170 = 49,300 studs; SIGNALS_PER_STAGE was 75, so
		-- `area / N` = 657.33 -- the starting detector turns up a contact about every
		-- 1.3s of walking (slow) and a maxed one about every 0.48s (fast). Denser than
		-- the old targets (3-12s / >=2s) and denser again with each footprint shrink
		-- that held N; that is the accepted cost of small stages with the signal count
		-- left alone. The 240 -> 200 width pass held `area / N` so slow and fast did
		-- not move; the 15% pass dropped it to 0.7225x and the length pass to 0.853x
		-- again, so both came down by those factors. `slow` is now ~1.26 against the
		-- 1.2 floor -- the length pass was the last free one; a fourth shrink needs N
		-- to drop with it (and see §7 -- below ~69 the per-stage rarityTilt moves too).
		-- What must NEVER move: this stays a WALK not a stand-still (slow floor > 0), and the
		-- reveal curve stays FLAT end to end -- that ratio guard is area-independent
		-- and is the real check against "fixing" the Detector track's payoff by
		-- widening radius (see Config/Gear's header). Retarget via SIGNALS_PER_STAGE.
		check(string.format("§2.1 starting detector walks %.1fs between contacts (want 1.2-5)", slow), slow >= 1.2 and slow <= 5)
		check(string.format("§2.1 a maxed detector still has a beat between contacts: %.2fs (want >= 0.4)", fast), fast >= 0.4)
		check(string.format("§2.1 the reveal curve stays flat: %.1fx end to end (want <= 4)", slow / fast), slow / fast <= 4)
	end

	-- PLAN §Step 2 — THE PULL IS A MASH, AND `draw` IS WHAT KEEPS IT PLAYABLE.
	--
	-- Every check below is a restatement of one number: the clicks per second a tier
	-- needs just to HOLD an item where it is,
	--     (PULL_DRAG_RATE - draw) / (PULL_YANK_PER_CLICK * pullSpeed)
	-- which is the thing a player actually experiences when they buy a magnet. It is
	-- worth pinning rather than eyeballing because it falls out of FOUR numbers spread
	-- across two files, and moving any one of them silently moves it.
	local function clicksToHold(tier: number): number
		local magnet = Gear.tier("Magnet", tier)
		return (Tuning.PULL_DRAG_RATE - magnet.draw) / (Tuning.PULL_YANK_PER_CLICK * magnet.pullSpeed)
	end

	-- Same number, but with the soil OUTCLASSING the magnet by `deficit` stages:
	-- DigService bends both magnet terms (yank + draw) by Tuning.PULL_GRIP_FALLOFF ^
	-- deficit and leaves the drag alone, so clicks-to-hold climbs steeply.
	local function holdAtDeficit(tier: number, deficit: number): number
		local magnet = Gear.tier("Magnet", tier)
		local e = Tuning.PULL_GRIP_FALLOFF ^ deficit
		return (Tuning.PULL_DRAG_RATE - magnet.draw * e) / (Tuning.PULL_YANK_PER_CLICK * magnet.pullSpeed * e)
	end

	do
		local starting = clicksToHold(1)
		check(
			string.format("§Step2 the starting magnet is a real mash but a mashable one: %.2f clicks/sec (want 2-3.5)", starting),
			starting >= 2 and starting <= 3.5
		)

		-- THE MOBILE CHECK, and the most load-bearing line in this block. PLAN §Step 2
		-- is explicit that the pull must never be balanced around desktop mash rate,
		-- because doing so quietly locks half the Roblox audience out of deep stages —
		-- and a mash is exactly the mechanic most likely to drift that way under
		-- "make tier 1 feel weightier" pressure. `draw` is the promise that it will
		-- not, and this is where the promise is kept: by the mid magnet the answer has
		-- to be about one click every two seconds, which is comfortable on a phone.
		-- The middle of BASE CAMP's ladder (the Winch Coil): Toxic Twilight's magnets
		-- are all near hands-free, and letting them drag "mid" up the ladder would turn
		-- this into a check nothing can fail.
		local mid = math.ceil(#Gear.tiersAt("Magnet", Camps.BASE) / 2) + 1
		check(
			string.format("§Step2 a mid magnet (%s) is comfortable on a phone: %.2f clicks/sec (want <= 1)", Gear.tier("Magnet", mid).name, clicksToHold(mid)),
			clicksToHold(mid) <= 1
		)

		local easing = true
		for tier = 2, Gear.maxTier("Magnet") do
			if clicksToHold(tier) >= clicksToHold(tier - 1) then
				easing = false
			end
		end
		check("§Step2 every magnet tier asks for fewer clicks than the last", easing)

		-- The pull must stay a BEAT, not a tap, AND never a chore. The worst case is the
		-- deepest rarity carried by the HEAVIEST catalogue item (Config/Weight.pullFactor
		-- multiplies `required` in DigService) against the best magnet. If even that is
		-- instant the mash has stopped mattering; if it runs past ~15s the weight curve
		-- has turned a haul into homework.
		local heaviestKg = Items.DEFS[1].weight
		for _, item in Items.DEFS do
			heaviestKg = math.max(heaviestKg, item.weight)
		end
		local deepest = (Tuning.DIG_DEPTH_BASE + (#Rarity.ORDER - 1) * Tuning.DIG_DEPTH_PER_RARITY)
			* Weight.pullFactor(heaviestKg)
		local best = Gear.tier("Magnet", Gear.maxTier("Magnet"))
		local netPerSecond = 4 * Tuning.PULL_YANK_PER_CLICK * best.pullSpeed - (Tuning.PULL_DRAG_RATE - best.draw)
		local fastest = (Tuning.PULL_SECONDS_PER_STUD * deepest) / netPerSecond
		check(
			string.format("§Step2 the heaviest deep item takes %.1fs at 4 clicks/sec with the best magnet (want 2-15)", fastest),
			fastest >= 2 and fastest <= 15
		)

		-- The home-turf Common ease (Config/Tuning.PULL_HOME_COMMON_EASE) shortens
		-- `required` for Common items pulled on soil the magnet is rated for. Its two
		-- conditions -- Common-only, gripDeficit == 0 -- are code properties in
		-- DigService (Config sees neither the roll nor the soil), so what this pins is
		-- the one thing Config owns: the size of the cut. A real break, but not so deep
		-- the floor of the catalogue stops being a mash.
		check(
			string.format("§Step2 the home-turf Common ease is a real cut, not a giveaway: %.2fx (want 0.55-0.8)", Tuning.PULL_HOME_COMMON_EASE),
			Tuning.PULL_HOME_COMMON_EASE >= 0.55 and Tuning.PULL_HOME_COMMON_EASE < 0.8
		)
	end

	-- PLAN §Step 2 continued — maxGrip IS NOT A WALL ANY MORE, IT IS A STEEP GRIND.
	--
	-- Soil past a magnet's maxGrip used to clamp the haul at a quarter and paint
	-- "MAGNET TOO WEAK". Now it scales the pull down by Tuning.PULL_GRIP_FALLOFF per
	-- stage of deficit, with no clamp. These pin the shape the user asked for: one
	-- stage over is a grind you can still win, two lurches then sinks, three is
	-- unwinnable -- and a better magnet always rescues what the tier below cannot.
	do
		local cap = Tuning.PULL_YANK_SUSTAINED_CPS -- the click rate a strong human sustains
		local start = Gear.tier("Magnet", 1)

		-- Deficit 0 has to be the untouched pull, or every check above stops describing
		-- the game: gripEff is exactly 1 when the magnet is rated for its soil.
		check(
			"§Step2 a magnet rated for its soil pulls exactly as before (no penalty at deficit 0)",
			holdAtDeficit(1, 0) == clicksToHold(1)
		)

		-- Every stage the soil gains on the magnet costs strictly more mash.
		check(
			"§Step2 each stage over tier is strictly harder to hold than the last",
			holdAtDeficit(1, 0) < holdAtDeficit(1, 1)
				and holdAtDeficit(1, 1) < holdAtDeficit(1, 2)
				and holdAtDeficit(1, 2) < holdAtDeficit(1, 3)
		)

		-- +1: past the starting magnet's own mash band (Spec pins that at <= 3.5 above),
		-- but a strong masher still out-pulls the drag, so the item does come free.
		local overByOne = holdAtDeficit(1, 1)
		check(
			string.format("§Step2 one stage over tier is a grind you can still win: %.2f clicks/sec (want 3.5-%.0f)", overByOne, cap),
			overByOne > 3.5 and overByOne <= cap
		)

		-- +2: past what a human sustains. The opening token-bucket burst still lurches it
		-- upward, then it sinks -- "almost impossible", deliberately not "impossible".
		check(
			string.format("§Step2 two stages over tier cannot be sustained: %.2f clicks/sec (want > %.0f)", holdAtDeficit(1, 2), cap),
			holdAtDeficit(1, 2) > cap
		)

		-- +3: the wall enforces itself. Flat out at the sustained cap, the starting
		-- magnet's net progress is still negative -- it can only sink.
		local e3 = Tuning.PULL_GRIP_FALLOFF ^ 3
		local netAtCap = cap * Tuning.PULL_YANK_PER_CLICK * start.pullSpeed * e3
			- (Tuning.PULL_DRAG_RATE - start.draw * e3)
		check(
			string.format("§Step2 three stages over tier is unwinnable: %.3f net pull-sec/sec at the mash cap (want < 0)", netAtCap),
			netAtCap < 0
		)

		-- The whole point of the redesign: one tier up the magnet track rescues an
		-- over-tier soil the tier below cannot hold at all.
		check(
			"§Step2 a better magnet claws out an over-tier soil the tier below cannot",
			holdAtDeficit(2, 2) < holdAtDeficit(1, 2)
		)
	end

	-- PLAN §Step 2 — THE PULL FUSE (Config/Detonation). Lock onto a nuke and its fuse
	-- lights; let go before ARM_AT and you walk away, hang on past it and you pull it out
	-- or it goes off and leaves a burning crater. These pin the shape: about twenty
	-- seconds on average but wildly uneven (5-30s, some hair-triggers under eight),
	-- rarer is shorter, bigger is longer, an honest pull never arms, and the bang scales
	-- with the find.
	do
		local D = DetonationConfig

		check(
			string.format("§fuse arms at %.0f%% of the window (want 70-90%%)", D.ARM_AT * 100),
			D.ARM_AT >= 0.7 and D.ARM_AT <= 0.9
		)
		check("§fuse warns before it arms", D.WARN_AT < D.ARM_AT)

		local shorter = true
		for index = 2, #Rarity.ORDER do
			if Detonation.baseWindow(Rarity.ORDER[index], 3) > Detonation.baseWindow(Rarity.ORDER[index - 1], 3) + 1e-9 then
				shorter = false
			end
		end
		check("§fuse rarer nukes get less time (the window never grows down Rarity.ORDER)", shorter)
		check(
			"§fuse bigger nukes get more time (they take longer to pull)",
			Detonation.baseWindow("Rare", Weight.MAX) > Detonation.baseWindow("Rare", Weight.MIN)
		)

		local ordinary = Detonation.baseWindow("Uncommon", D.WEIGHT_REF_KG)
		check(
			string.format("§fuse an ordinary Uncommon is centred on about six seconds: %.1fs (want 5-8)", ordinary),
			ordinary >= 5 and ordinary <= 8
		)

		-- THE TEMPER: every nuke rolls its own multiplier off its uid, and the bands that
		-- make the roll have to be well-formed (the same three rules Payload.BANDS keeps).
		local bandsOrdered, bandTotal, bandLow = true, 0, D.TEMPER_MIN
		for _, band in D.TEMPER_BANDS do
			if band.upTo <= bandLow or band.chance <= 0 then
				bandsOrdered = false
			end
			bandLow = band.upTo
			bandTotal += band.chance
		end
		check("§fuse temper bands ascend from TEMPER_MIN with a positive chance each", bandsOrdered)
		check(string.format("§fuse temper chances total 100 (got %d)", bandTotal), bandTotal == 100)
		check(
			"§fuse temper roll runs from TEMPER_MIN up to the last band's edge",
			math.abs(Detonation.temperFromRoll(0) - D.TEMPER_MIN) < 1e-9
				and math.abs(Detonation.temperFromRoll(0.999999) - bandLow) < 1e-3
		)
		check(
			"§fuse a nuke's temper is fixed by its uid (both sides of the network read one number)",
			Detonation.temperFor("spec-uid-a") == Detonation.temperFor("spec-uid-a")
		)
		-- The tutorial spot re-rolls its uid against isCalmFuse: enough uids must pass,
		-- and none that pass may be a troll or a hair-trigger.
		local calmCount, calmHeld = 0, true
		for sample = 1, 400 do
			local uid = "spec-calm-" .. sample
			if Detonation.isCalmFuse(uid) then
				calmCount += 1
				calmHeld = calmHeld
					and Detonation.trollWindowFor(uid) == nil
					and Detonation.temperFor(uid) >= D.TUTORIAL_MIN_TEMPER
			end
		end
		check(
			"§fuse the tutorial's calm-fuse re-roll passes often and never lets a quick fuse through",
			calmHeld and calmCount >= 100
		)

		-- THE ANNOUNCED DROP's fuse (RARE_DROP_*): far longer than any ordinary one, and
		-- long enough that the slowest guaranteed pull (MIN_PULL_SECONDS at MIN_PULL_CPS) lands
		-- before SAFE_AT of the SHORTEST rare window.
		local rareHeld, rareSum, rareCount = true, 0, 0
		for sample = 1, 200 do
			local window = Detonation.rareDropWindowFor("Legendary", 25, 1.5, 3, `spec:rare:{sample}`, RareDrop.PULL_MULT)
			rareSum += window
			rareCount += 1
			if window < D.RARE_DROP_MIN - 1e-9 or window > D.RARE_DROP_CAP + 1e-9 then
				rareHeld = false
			end
		end
		check("§fuse an announced drop's fuse stays in RARE_DROP_MIN..RARE_DROP_CAP", rareHeld)
		check(
			string.format("§fuse an announced drop's fuse averages way past MAX_WINDOW: %.1fs", rareSum / rareCount),
			rareSum / rareCount >= 2 * D.MAX_WINDOW
		)
		check(
			"§fuse the announced drop's minimum pull lands before SAFE_AT of its shortest fuse",
			RareDrop.MIN_PULL_SECONDS <= D.RARE_DROP_MIN * D.SAFE_AT
		)

		-- THE WINDOWS THEMSELVES. Every stocked item, in every stage it stocks, buried at
		-- its rarity's DEEPEST (full jitter), across a spread of uids. Independent of
		-- Detonation's own pieces: the rated pull is re-derived here from Tuning the way
		-- DigService runs it, not read back through Detonation.ratedRope / floorFor.
		local SAMPLES = 40
		local windowSum, windowSq, windowCount, underEight, trolls, trollHeld = 0, 0, 0, 0, 0, true
		local windowMin, windowMax = math.huge, 0
		local rangeHeld, floorHeld = true, true
		local worstFrac, worstId = 0, "none"
		local worstSustained, worstSustainedId = 0, "none"
		for _, item in Items.DEFS do
			local order = Rarity.get(item.rarity).order
			local depth = Tuning.DIG_DEPTH_BASE + (order - 1) * Tuning.DIG_DEPTH_PER_RARITY + Tuning.DIG_DEPTH_JITTER
			for _, stageId in item.stages do
				local soil = Stages.get(stageId).soilHardness
				local magnet = Detonation.ratedMagnet(soil)
				local rope = Tuning.PULL_SECONDS_PER_STUD * depth * Weight.pullFactor(item.weight)
				if item.rarity == "Common" then
					rope *= Tuning.PULL_HOME_COMMON_EASE
				end
				local function rateAt(cps: number): number
					return cps * Tuning.PULL_YANK_PER_CLICK * magnet.pullSpeed - (Tuning.PULL_DRAG_RATE - magnet.draw)
				end
				-- What the fairness floor asks for, and what it can actually give: the
				-- floor lifts a fuse up to MAX_WINDOW and no further.
				local needed = rope / rateAt(D.REF_CPS) / D.SAFE_AT
				local floorWindow = math.clamp(needed, D.MIN_WINDOW, D.MAX_WINDOW)
				for sample = 1, SAMPLES do
					local uid = `spec:{item.id}:{stageId}:{sample}`
					local window = Detonation.windowFor(item.rarity, item.weight, depth, soil, uid)
					if Detonation.trollWindowFor(uid) then
						trolls += 1
						if window < D.TROLL_MIN - 1e-9 or window > D.TROLL_MAX + 1e-9 or window >= 3 then
							trollHeld = false
						end
						continue
					end
					windowSum += window
					windowSq += window * window
					windowCount += 1
					windowMin, windowMax = math.min(windowMin, window), math.max(windowMax, window)
					if window < 5 then
						underEight += 1
					end
					if window < D.MIN_WINDOW - 1e-9 or window > D.MAX_WINDOW + 1e-9 then
						rangeHeld = false
					end
					-- Never shorter than the floor allows for this pull...
					if window < floorWindow - 1e-9 then
						floorHeld = false
					end
					-- ...so wherever the floor CAN be met, the rated magnet at REF_CPS lands
					-- the nuke by SAFE_AT of its window.
					if needed <= D.MAX_WINDOW then
						local frac = (rope / rateAt(D.REF_CPS)) / window
						if frac > worstFrac then
							worstFrac, worstId = frac, item.id
						end
					end
				end
				-- The promise for the pulls the cap leaves short: even against the
				-- SHORTEST window this pull can have, a rated magnet at the sustained mash
				-- rate lands it before it arms.
				local sustained = (rope / rateAt(Tuning.PULL_YANK_SUSTAINED_CPS)) / floorWindow
				if sustained > worstSustained then
					worstSustained, worstSustainedId = sustained, item.id
				end
			end
		end
		local mean = windowSum / windowCount
		local spread = math.sqrt(math.max(0, windowSq / windowCount - mean * mean))
		local hairTrigger = underEight / windowCount
		local trollShare = trolls / (windowCount + trolls)
		check(
			string.format("§fuse troll nukes are rare and go off under three seconds: %.1f%% (want 2-10%%)", trollShare * 100),
			trollHeld and trollShare >= 0.02 and trollShare <= 0.10
		)

		check(
			string.format("§fuse every window sits in %d-%ds: %.1f-%.1fs", D.MIN_WINDOW, D.MAX_WINDOW, windowMin, windowMax),
			rangeHeld
		)
		check(
			string.format("§fuse the average window is about seven seconds: %.1fs (want 5.5-8.5)", mean),
			mean >= 5.5 and mean <= 8.5
		)
		check(
			string.format("§fuse windows vary widely, not a nudge off one number: sd %.1fs (want >= 2.5)", spread),
			spread >= 2.5
		)
		check(
			string.format("§fuse a real share of nukes are hair-triggers under five seconds: %.1f%% (want 10-40%%)", hairTrigger * 100),
			hairTrigger >= 0.10 and hairTrigger <= 0.40
		)
		check(
			string.format("§fuse the slowest burns reach the cap and the fastest the floor: %.1f..%.1fs", windowMin, windowMax),
			windowMin <= D.MIN_WINDOW + 1 and windowMax >= D.MAX_WINDOW - 1
		)

		-- THE FAIRNESS FLOOR, and the reason the window is not just the roll. A rated
		-- magnet at a brisk REF_CPS must have the nuke out by SAFE_AT of its window
		-- whenever the cap allows a window that long -- so an honest pull on your own tier
		-- gets nowhere near the arm line...
		check("§fuse no window is shorter than its pull's floor (up to the cap)", floorHeld)
		check(
			string.format(
				"§fuse the rated magnet at %d clicks/sec lands every floor-able nuke well before it arms: worst %s at %.0f%% (want <= %.0f%%)",
				D.REF_CPS,
				worstId,
				worstFrac * 100,
				D.SAFE_AT * 100
			),
			worstFrac <= D.SAFE_AT + 1e-6
		)
		-- ...and for the few slow deep pulls the 30s cap cannot cover at REF_CPS, a rated
		-- magnet mashing at the sustained rate still gets it out before ARM_AT.
		check(
			string.format(
				"§fuse the rated magnet at the sustained %d clicks/sec lands EVERY nuke before it arms: worst %s at %.0f%% (want <= %.0f%%)",
				Tuning.PULL_YANK_SUSTAINED_CPS,
				worstSustainedId,
				worstSustained * 100,
				D.ARM_AT * 100
			),
			worstSustained <= D.ARM_AT + 1e-6
		)

		check(
			"§fuse letting go and grabbing straight back does not reset it",
			Detonation.stepHeat(0.79, 0.25, 30, false) > 0.75
		)
		check("§fuse an unheld fuse cools no faster than it burned", D.COOL_RATE <= 1)
		check(
			"§fuse once armed it burns out in exactly (1 - ARM_AT) of its window",
			math.abs(Detonation.secondsLeft(D.ARM_AT, 30) - (1 - D.ARM_AT) * 30) < 1e-6
		)

		local grows = true
		for index = 2, #Rarity.ORDER do
			local lower = D.BLAST[Rarity.ORDER[index - 1]]
			local higher = D.BLAST[Rarity.ORDER[index]]
			if
				lower == nil
				or higher == nil
				or higher.hit < lower.hit
				or higher.orbRadius < lower.orbRadius
				or higher.orbBurn < lower.orbBurn
				or higher.orbLife < lower.orbLife
			then
				grows = false
			end
		end
		check("§fuse every rarity has a blast, and a rarer one is never smaller, weaker or shorter", grows)
		check(
			"§fuse a bigger nuke leaves a bigger crater, within the clamp",
			Detonation.blastFor("Rare", 3).orbRadius > Detonation.blastFor("Rare", 0.5).orbRadius
				and Detonation.sizeMult(1000) <= D.SIZE_MAX
				and Detonation.sizeMult(0.001) >= D.SIZE_MIN
		)

		local epic = Detonation.blastFor("Epic", D.SIZE_REF)
		check(
			"§fuse the orb burns hardest at its heart and not at all past its edge",
			Detonation.orbBurnAt(0, epic.orbRadius, epic.orbBurn, 1) > Detonation.orbBurnAt(epic.orbRadius * 0.9, epic.orbRadius, epic.orbBurn, 1)
				and Detonation.orbBurnAt(epic.orbRadius * 1.01, epic.orbRadius, epic.orbBurn, 1) == 0
		)
		check(
			"§fuse the orb is full strength when it forms and gone at the end of its life",
			Detonation.orbStrength(0, epic.orbLife) == 1 and Detonation.orbStrength(epic.orbLife, epic.orbLife) == 0
		)
		check(
			"§fuse the blast hits hardest at ground zero and not at all past its rim",
			Detonation.hitAt(0, epic) == epic.hit and Detonation.hitAt(epic.blastRadius + 0.1, epic) == 0
		)

		-- A Common going off in your hands is a bruise, not a blackout: the point-blank
		-- hit, then walking straight out of the orb at HALF an UNTRAINED player's speed.
		-- Deliberately the floor of the speed curve rather than anything a treadmill
		-- buys: the worst case is the player who has never trained, and a check written
		-- against a trained speed would pass while that player died.
		local common = Detonation.blastFor("Common", D.SIZE_REF)
		local walk = Treadmill.START_WALK * 0.5
		local taken, walked, step = common.hit, 0, 0.02
		while walked < common.orbRadius do
			taken += Detonation.orbBurnAt(walked, common.orbRadius, common.orbBurn, 1) * step
			walked += walk * step
		end
		check(
			string.format("§fuse a Common nuke going off in your hands is survivable on foot: %.0f of %d health", taken, Tuning.MAX_HEALTH),
			taken < Tuning.MAX_HEALTH
		)

		-- Farther stages hit harder, but gently: rarity still decides most of a blast,
		-- and the Common walk-out above still holds at the last stage.
		local lastStage = #Stages.DEFS
		local lastHit, lastRadius = Detonation.stageMults(lastStage)
		local firstHit, firstRadius = Detonation.stageMults(1)
		check(
			"§fuse a farther stage's nuke hits harder and reaches farther, by at most half again",
			firstHit == 1 and firstRadius == 1 and lastHit > 1 and lastRadius > 1 and lastHit <= 1.5 and lastRadius <= 1.5
		)
		local farCommon = Detonation.blastFor("Common", D.SIZE_REF, lastStage)
		local farTaken, farWalked = farCommon.hit, 0
		while farWalked < farCommon.orbRadius do
			farTaken += Detonation.orbBurnAt(farWalked, farCommon.orbRadius, farCommon.orbBurn, 1) * step
			farWalked += walk * step
		end
		check(
			string.format("§fuse a last-stage Common going off in your hands is survivable on foot: %.0f of %d health", farTaken, Tuning.MAX_HEALTH),
			farTaken < Tuning.MAX_HEALTH
		)
	end

	-- PLAN §7 — DENSITY AND RARITY ARE ONE DECISION, NOT TWO.
	--
	-- The old per-rarity `loot` weight tables are gone: the dig roll walks a stage's
	-- stocked items weighted by 1/odds (Config/Items), and one scalar per stage --
	-- Stages.rarityTilt -- shapes the rarity curve on top. SIGNALS_PER_STAGE (28) times
	-- the Rare+ share is the count of jackpots buried in the starter field, and that
	-- product is the number this pins: raise the density on its own, or nudge the tilt,
	-- and the field quietly starts holding more jackpots -- invisible in play until the
	-- economy is already ruined. FLOOR 1.7 -> 1.0 WITH THE FEWER-SIGNALS PASS (N 75 ->
	-- 40, on request): the count is ~1.2 now. FLOOR 1.0 -> 0.7 WITH THE SECOND ONE (N 40
	-- -> 28, on request 2026-10-03): ~0.74 now, per-dig odds untouched again -- the
	-- user wants rares harder, so the floor moves, not the tilt. The ceiling is the half that guards the
	-- economy and it is unchanged. Band was ~1.9 at the solved Stage 1 tilt (see
	-- Config/Stages' header); a fourth footprint shrink that drops N below ~69 needs the
	-- tilt to move with it to hold this.
	--
	-- STARTER FIELD ONLY. This is what a new player, tier-1 detector, rolls against.
	-- Stages 4-6 are deliberately far richer (Config/Stages) -- folding them in would
	-- destroy the check, not tighten it.
	local function shareAtOrAbove(stageId: number, minOrder: number): number
		local wanted = 0
		for name, share in Items.rarityWeights(stageId, Stages.get(stageId).rarityTilt) do
			if Rarity.get(name).order >= minOrder then
				wanted += share -- rarityWeights already sums to 1
			end
		end
		return wanted
	end

	local rarePlus = Tuning.SIGNALS_PER_STAGE * shareAtOrAbove(1, 4) -- Rare and up
	check(
		string.format("§7 the starter field holds %.2f Rare-or-better signals at a tier-1 detector (want 0.7-3.0)", rarePlus),
		rarePlus >= 0.7 and rarePlus <= 3.0
	)

	-- ...and the flip side: the rest have to be junk, or "more items" just means "more
	-- of everything".
	local plentiful = 1 - shareAtOrAbove(1, 3) -- Scrap + Common
	check(
		string.format("§2.1 stage 1 is mostly Scrap/Common: %.0f%% (want >= 70)", plentiful * 100),
		plentiful >= 0.70
	)

	-- Every built, stocked stage must actually hand out an item -- rollItem returns nil
	-- only for a stage Config/Items forgot entirely, which should spawn no signals and
	-- warn, never crash. Rarer-only luck must also never invert the ladder: pushing
	-- detector luck up can only raise a stage's Rare+ share, never drop it, and no
	-- rarity may overtake a rarer one (the property Config/Liquids pins for the pad).
	local topLuck = Gear.tier("Detector", Gear.maxTier("Detector")).luck
	for _, id in Stages.builtIds() do
		local tilt = Stages.get(id).rarityTilt
		-- Dig is OFF on a stage that stocks nothing (7-12 for now): no roll, no crash.
		if #IndexProgress.stageItems(id) == 0 then
			check(string.format("§7 unstocked stage %d rolls nothing", id), Items.rollItem(id, tilt, 1) == nil and id > 6)
			continue
		end
		check(string.format("§7 stage %d rolls a stocked item", id), Items.rollItem(id, tilt, 1) ~= nil)

		local base = Items.rarityWeights(id, tilt)
		local lucky: { [string]: number } = {}
		for itemId, p in Items.rollWeights(id, tilt, topLuck) do
			local r = Items.get(itemId).rarity
			lucky[r] = (lucky[r] or 0) + p
		end

		local baseRarePlus, luckyRarePlus = 0, 0
		local noInversion = true
		local prevBase, prevLucky = 0, 0
		for _, name in Rarity.ORDER do
			local b, l = base[name] or 0, lucky[name] or 0
			if Rarity.get(name).order >= 4 then
				baseRarePlus += b
				luckyRarePlus += l
			end
			-- ratio to the previous rung must not fall as luck rises (only meaningful
			-- where both rungs are actually stocked)
			if b > 0 and l > 0 and prevBase > 0 and prevLucky > 0 then
				if (l / prevLucky) < (b / prevBase) - 1e-9 then
					noInversion = false
				end
			end
			if b > 0 then
				prevBase, prevLucky = b, l
			end
		end
		check(string.format("§7 stage %d: detector luck only raises Rare+ share", id), luckyRarePlus >= baseRarePlus - 1e-9)
		check(string.format("§7 stage %d: detector luck never inverts the rarity ladder", id), noInversion)
	end

	-- PLAN §3.5 — no stage is gated by anything except arithmetic
	for _, stage in Stages.DEFS do
		check(string.format("§3.5 stage %d has no unlock field", stage.id), (stage :: any).locked == nil and (stage :: any).requiresGamepass == nil)
	end

	-- `initialCount` is what makes "how dirty was this to begin with" answerable without
	-- storing a second number on every carried item, so it has to keep agreeing with the
	-- roll it was extracted from.
	--
	-- IT IS ALSO THE CRUST'S CHUNK COUNT, which is why this check matters more than it
	-- used to: one chunk of slag per patch is what hides the item, and a roll that came
	-- back with fewer patches than the count says would leave a find you could read the
	-- shape of straight out of the ground.
	do
		local agrees = true
		for _, rarity in Rarity.ORDER do
			for modifier in Rarity.MODIFIERS do
				local rolled = Contamination.rollPatches(rarity, modifier)
				if #rolled ~= Contamination.initialCount(rarity, modifier) then
					agrees = false
				end
			end
		end
		check("§2 initialCount agrees with the roll it was pulled out of", agrees)
	end

	-- A FAR STAGE'S CRUST IS HARDER AT THE SAME RARITY (Tuning.CRUST_STAGE_BONUS): a
	-- Stage 11 Legendary must out-gate a Stage 4 one, on every patch, not just the top.
	do
		local stage4 = Contamination.rollPatches("Legendary", "None", 4)
		local stage11 = Contamination.rollPatches("Legendary", "None", 11)
		local softest11 = math.huge
		for _, hardness in stage11 do
			softest11 = math.min(softest11, hardness)
		end
		check(
			"§2 a Stage 11 Legendary's crust is harder than a Stage 4 one",
			Contamination.gateHardness("Legendary", 11) > Contamination.gateHardness("Legendary", 4)
				and math.max(table.unpack(stage11)) > math.max(table.unpack(stage4))
				and softest11 > 1 + Contamination.stageBonus(4)
		)
		check("§2 Base Camp crust is the rarity's own hardness", Contamination.gateHardness("Legendary", 4) == Rarity.get("Legendary").hardness)
	end

	-- YOU CLEAN THE PATCH YOU AIMED AT. The wash bay times one bank per dirty area and
	-- names the index when that bank fills (WashService's tick), which only means
	-- anything if `clearAt` removes THAT patch. Its predecessor `clearOne` picked the
	-- easiest itself -- invisible while there was one shared clock, and a live bug the
	-- moment there are six: eight seconds of work on a crusted corner would pop an easy
	-- patch on the far side of the object instead. The potency gate USED to live in here
	-- too; it is the soak clock now (below), which only the server runs.
	do
		local patches = { 1, 4, 2 }
		local hardness, index = Contamination.clearAt(patches, 2)
		check("§2 clearAt removes the patch it was told to", hardness == 4 and index == 2 and #patches == 2 and patches[2] == 2)

		local missing = Contamination.clearAt(patches, 9)
		check("§2 clearAt refuses an index that names nothing", missing == nil and #patches == 2)
	end

	-- OVER-POTENCY CRUST IS A GRIND, NOT A WALL (Tuning.WASH_POTENCY_FALLOFF). The
	-- reported bug: an Epic or Legendary under a tier 2-3 hose would not move at all.
	-- Pinned the same way the magnet's over-tier grind is (§Step2): +1 a slog, +2 a
	-- real ask, +3 minutes on one chunk, and the far end possible but absurd -- every
	-- step finite, every step steeper than the last.
	do
		local function hoseSeconds(hardness: number, tier: number): number
			local hose = Gear.tier("Cleaner", tier)
			return Contamination.secondsFor(hardness, hose.volume, hose.power)
		end
		local rated = Contamination.secondsFor(4, 1, 4)
		check("§2 a patch inside potency pays no overmatch", rated == (0.9 + 4 * 0.5))
		check("§2 overmatch counts only the hardness past the stream", Contamination.overmatch(5, 2) == 3 and Contamination.overmatch(2, 5) == 0)

		local steps = {}
		for deficit = 0, 6 do
			steps[deficit] = Contamination.secondsFor(1 + deficit, 1, 1) / Contamination.secondsFor(1 + deficit, 1, 1 + deficit)
		end
		local steepening = true
		for deficit = 1, 6 do
			if not (steps[deficit] > steps[deficit - 1] * 2.5) then
				steepening = false
			end
		end
		check("§2 each point of overmatch multiplies the clock by well over double", steepening)

		local epic = hoseSeconds(Rarity.get("Epic").hardness, 2)
		local legendary = hoseSeconds(Rarity.get("Legendary").hardness, 2)
		local anomaly = hoseSeconds(Rarity.get("Anomaly").hardness, 1)
		check(
			string.format("§2 an Epic's gate chunk on a tier-2 hose is a grind, not a wall (%.0fs, want 15-60)", epic),
			epic >= 15 and epic <= 60
		)
		check(
			string.format("§2 a Legendary's gate chunk on a tier-2 hose is extremely hard (%.0fs, want 60-240)", legendary),
			legendary >= 60 and legendary <= 240
		)
		check(
			string.format("§2 an Anomaly under a Garden Hose is finite but absurd (%.0f min, want > 30)", anomaly / 60),
			anomaly < math.huge and anomaly > 30 * 60
		)
	end

	-- THE CRUST HAS TO ACTUALLY HIDE IT. This is the whole feature in one check: an item
	-- comes out of the ground encased in one chunk of slag per patch, is "???" on every
	-- surface until those chunks are off, and the reveal is the wash bay taking them off.
	-- If the shell does not enclose the item, the reveal has already happened in the soil
	-- and there is nothing left for the hose to be for.
	--
	-- Built as a thin disc rather than a cube, because a flat coin-shaped item is the
	-- awkward case the sizing rules exist for: millimetres thick, so its own bounding box
	-- is nearly flat and MIN_BODY is what stops the crust being a sheet of paper. This
	-- used to run against the real "Bottle Cap" catalogue model; feat/nuke-arsenal-retheme
	-- retired that model key, so the thin edge case is built directly instead of hoping a
	-- future catalogue keeps a suitably thin entry around.
	do
		local sample: Model? = (function()
			local model = Instance.new("Model")
			local disc = Instance.new("Part")
			disc.Size = Vector3.new(1.4, 0.25, 1.4)
			disc.Anchored = true
			disc.CanCollide = false
			disc.Parent = model
			model.PrimaryPart = disc
			return model
		end)()
		if sample then
			local _, bare = sample:GetBoundingBox()

			local zones, anchors = ItemCrust.encase(sample, 4, "Rare", "spec-uid")
			local chunked = true
			for zone = 1, 4 do
				if zones[zone] == nil or #zones[zone] == 0 or anchors[zone] == nil then
					chunked = false
				end
			end

			local _, encased = sample:GetBoundingBox()
			local swallowed = encased.X > bare.X and encased.Y > bare.Y and encased.Z > bare.Z

			-- The server only STAMPS the level (CrustController draws it smooth on each
			-- client), so erode must leave the part's own size alone -- a server write
			-- would replicate over the client's eased one in ten-hertz steps again.
			local before = {}
			for _, part in zones[1] do
				before[part] = part.Size
			end
			ItemCrust.erode(zones[1], 0.5, false)
			local stamped = true
			for _, part in zones[1] do
				local shed = part:GetAttribute(ItemCrust.SHED_ATTR) == true
				if part.Size ~= before[part] or (not shed and part:GetAttribute(ItemCrust.LEVEL_ATTR) ~= 0.5) then
					stamped = false
				end
			end

			-- Painting runs every frame on the client, so it has to be idempotent the same
			-- way the film it replaced was: the SECOND paint at one level must land on the
			-- same size as the first, or a chunk shrinks away under a stream that is not
			-- moving.
			for _, part in zones[1] do
				ItemCrust.paint(part, 0.5, false)
			end
			local once = {}
			for _, part in zones[1] do
				once[part] = part.Size
			end
			for _, part in zones[1] do
				ItemCrust.paint(part, 0.5, false)
			end
			local stable = true
			for _, part in zones[1] do
				if part.Size ~= once[part] then
					stable = false
				end
			end

			-- ...and a chunk past this potency STILL ERODES. It used to freeze dry and full
			-- size -- the potency wall -- and that is exactly the bug that got reported: an
			-- Epic under a tier 2-3 hose would not move. It shrinks now like any other chunk
			-- at the same level, and is only drawn as tougher rock.
			for _, part in zones[2] do
				ItemCrust.paint(part, 0.5, true)
			end
			local toughErodes = true
			for _, part in zones[2] do
				local full = part:GetAttribute("CrustSize") :: Vector3
				if part.Size.Magnitude >= full.Magnitude or part.Material ~= Enum.Material.Slate then
					toughErodes = false
				end
			end

			ItemCrust.strip(zones[3])
			local stripped = true
			for _, part in zones[3] do
				if part.Parent ~= nil then
					stripped = false
				end
			end

			check("§2 the crust builds one chunk per patch", chunked)
			check("§2 the crust encloses the item it is hiding", swallowed)
			check("§2 the server stamps the erode level and leaves the drawing to the client", stamped)
			check("§2 painting at one level does not compound", stable)
			check("§2 a chunk past this potency still erodes, drawn as tougher slate", toughErodes)
			check("§2 a cleared patch takes its chunk off the item", stripped)
			sample:Destroy()
		end
	end

	-- ── 2x luck (Config/LuckBoost) ────────────────────────────────────────────────
	do
		check(
			"§luck no boost is 1x, the aurora or a clover is MULT, both together stack",
			LuckBoost.multiplier(false, false) == 1
				and LuckBoost.multiplier(true, false) == LuckBoost.MULT
				and LuckBoost.multiplier(false, true) == LuckBoost.MULT
				and LuckBoost.multiplier(true, true) == LuckBoost.MULT * LuckBoost.MULT
		)

		-- The dig boost is a flat MULT on the Rare+ weight, outside the detector's cap,
		-- and exactly nothing below Rare -- at both ends of the detector ladder.
		local maxLuck = Gear.tier("Detector", Gear.maxTier("Detector")).luck
		local exact = true
		for _, luck in { 1, maxLuck } do
			for _, name in Rarity.ORDER do
				local base = Items.luckBias(name, luck)
				local want = if Rarity.get(name).order >= Items.DIG_LUCK_MIN_ORDER then base * LuckBoost.MULT else base
				if math.abs(Items.luckBias(name, luck, LuckBoost.MULT) - want) > 1e-9 then
					exact = false
				end
			end
		end
		check("§luck the dig boost multiplies every Rare+ weight and nothing below Rare", exact)

		-- THE REASON IT IS A WEIGHT AND NOT THE DETECTOR'S `luck` STAT: doubling the
		-- stat runs into DIG_LUCK_BIAS_CAP and LOWERS a maxed detector's Legendary+
		-- share in the late stages (Config/LuckBoost's header). The boost must raise it
		-- everywhere, for everyone.
		local legendary = Rarity.get("Legendary").order
		local rises = true
		for _, stage in Stages.DEFS do
			for _, luck in { 1, maxLuck } do
				local function share(boost: number): number
					local total = 0
					for id, p in Items.rollWeights(stage.id, stage.rarityTilt, luck, boost) do
						if Rarity.get(Items.get(id).rarity).order >= legendary then
							total += p
						end
					end
					return total
				end
				local before = share(1)
				if before > 0 and share(LuckBoost.MULT) <= before then
					rises = false
				end
			end
		end
		check("§luck 2x luck raises Legendary+ odds in every stage, even on a maxed detector", rises)

		-- The wash pad: a bought clover doubles the luck the pad rolls AND displays.
		-- Measured as a ratio so an aurora running while Spec runs cannot fail it.
		local plain = StatResolver.get({ level = 1, gear = {}, perks = {} })
		local clover = StatResolver.get({ level = 1, gear = {}, perks = {}, luckBoostLeft = 60 })
		check(
			"§luck a bought clover doubles the wash pad's luck and the dig boost",
			math.abs(clover.luckMultiplier / plain.luckMultiplier - LuckBoost.MULT) < 1e-9
				and clover.luckBoost == plain.luckBoost * LuckBoost.MULT
		)
		check(
			"§luck a spent clover is no boost at all",
			StatResolver.get({ level = 1, gear = {}, perks = {}, luckBoostLeft = 0 }).luckBoost == plain.luckBoost
		)

		-- The game passes (Config/GamePasses): each lands on its own stat and nothing else.
		do
			local all = {}
			for _, pass in GamePasses.PASSES do
				all[pass.key] = true
			end
			local owned = StatResolver.get({ level = 1, gear = {}, perks = {}, passes = all })
			check(
				"§pass every pass moves its own stat",
				owned.capacity == plain.capacity + GamePasses.BACKPACK_SLOTS
					and math.abs(owned.bombDamageMult / plain.bombDamageMult - GamePasses.BOMB_DAMAGE) < 1e-9
					and math.abs(owned.trainingMult / plain.trainingMult - GamePasses.SPEED) < 1e-9
					and owned.digPower == GamePasses.DIG_POWER
					and owned.luckBoost == plain.luckBoost * GamePasses.LUCK
					and math.abs(owned.sellMultiplier / plain.sellMultiplier - GamePasses.CASH) < 1e-9
					and math.abs(owned.yieldMultiplier / plain.yieldMultiplier - GamePasses.CASH) < 1e-9
					and owned.instantClean == true
					and plain.instantClean == false
					and plain.digPower == 1
					and owned.walkSpeed == plain.walkSpeed
			)
			local seen = {}
			local unique = true
			for _, pass in GamePasses.PASSES do
				if seen[pass.id] or seen[pass.key] then
					unique = false
				end
				seen[pass.id] = true
				seen[pass.key] = true
			end
			check("§pass every pass has its own key and id", unique)
		end

		-- A pack's timed 2x cash (Config/CashBoost): both payouts double, nothing else
		-- moves, it stacks with the 2x Cash pass (x4), and spent time is no boost.
		do
			local boosted = StatResolver.get({ level = 1, gear = {}, perks = {}, cashBoostLeft = 60 })
			local both = StatResolver.get({ level = 1, gear = {}, perks = {}, cashBoostLeft = 60, passes = { cash = true } })
			local spent = StatResolver.get({ level = 1, gear = {}, perks = {}, cashBoostLeft = 0 })
			check(
				"§cashboost doubles sales and stand income and nothing else",
				math.abs(boosted.sellMultiplier / plain.sellMultiplier - CashBoost.MULT) < 1e-9
					and math.abs(boosted.yieldMultiplier / plain.yieldMultiplier - CashBoost.MULT) < 1e-9
					and boosted.luckBoost == plain.luckBoost
					and boosted.capacity == plain.capacity
			)
			check(
				"§cashboost stacks with the 2x Cash pass",
				math.abs(both.sellMultiplier / plain.sellMultiplier - CashBoost.MULT * GamePasses.CASH) < 1e-9
			)
			check("§cashboost spent time is no boost", spent.sellMultiplier == plain.sellMultiplier)
		end

		-- The packs (Config/Packs): real crates, own keys and ids, and the contents the
		-- user named (2026-10-02).
		do
			local ok, seen = true, {}
			for _, pack in Packs.PACKS do
				if seen[pack.key] or seen[pack.id] then
					ok = false
				end
				seen[pack.key] = true
				seen[pack.id] = true
				for _, crateId in pack.crates do
					if not Crates.has(crateId) then
						ok = false
					end
				end
			end
			check("§pack every pack has its own key and id, and only real crates", ok)
			local starter, pro = Packs.byKey("starter"), Packs.byKey("pro")
			check(
				"§pack Starter: $200K, 2x Isotope Chem + 1x Field Nuke, 30 min luck",
				starter ~= nil
					and starter.cash == 200_000
					and #starter.crates == 3
					and starter.luckSeconds == 30 * 60
					and starter.cashBoostSeconds == 0
			)
			check(
				"§pack Pro: $5M, 2x Quicksilver + 2x Void + 1x Cobalt, 1 hr luck + 1 hr cash",
				pro ~= nil
					and pro.cash == 5_000_000
					and #pro.crates == 5
					and pro.luckSeconds == 60 * 60
					and pro.cashBoostSeconds == 60 * 60
			)
			local counts = Packs.crateCounts(pro :: Packs.Pack)
			check(
				"§pack crateCounts folds repeats in order",
				#counts == 3 and counts[1].crateId == "liquid4" and counts[1].count == 2 and counts[3].count == 1
			)
		end

		-- The Violet Aurora sits OVER every stage's sky (Config/Sky.blend), so every
		-- blend has to clear the same ceilings the stages do, and keep a deck darker
		-- than its air.
		local function luma(c: Color3): number
			return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
		end
		local legal, deck = true, true
		local looks ={ SkyConfig.blend(SkyConfig.BASE, SkyConfig.AURORA, SkyConfig.AURORA_BLEND) }
		for _, stage in Stages.DEFS do
			table.insert(looks, SkyConfig.blend(SkyConfig.get(stage.id), SkyConfig.AURORA, SkyConfig.AURORA_BLEND))
		end
		for _, look in looks do
			if look.cloudCover >= 1 or look.atmoDensity > 0.6 or look.atmoHaze > 3.4 then
				legal = false
			end
			if look.atmoHaze >= 2 and luma(look.cloudColor) >= luma(look.atmoColor) then
				deck = false
			end
		end
		check("§sky the Violet Aurora stays under the sky's ceilings over every stage", legal)
		check("§sky the Violet Aurora's cloud deck is darker than its air over every stage", deck)
		check(
			"§sky the Violet Aurora is violet (blue over green, red over green)",
			SkyConfig.AURORA.atmoColor.B > SkyConfig.AURORA.atmoColor.G
				and SkyConfig.AURORA.atmoColor.R > SkyConfig.AURORA.atmoColor.G
		)
	end

	-- ── Supply crates (Config/Crates) ─────────────────────────────────
	do
		local function near1(x: number): boolean
			return math.abs(x - 1) < 1e-6
		end

		local defsOk, sums, floors, variantsOk = true, true, true, true
		for _, id in Crates.ORDER do
			local def = Crates.DEFS[id]
			if def == nil or def.id ~= id or Rarity.DEFS[def.tier] == nil or Crates.idFor(def.kind, def.variant) ~= id then
				defsOk = false
				continue
			end
			if def.kind == "nuke" then
				local odds = Crates.nukeOdds(id)
				local total, lowest = 0, math.huge
				for itemId, p in odds do
					total += p
					lowest = math.min(lowest, Rarity.get(Items.get(itemId).rarity).order)
				end
				if not near1(total) then
					sums = false
				end
				-- The floor: nothing under the crate's lowest listed rarity.
				local floor = math.huge
				for rarity in def.rarities or {} do
					floor = math.min(floor, Rarity.get(rarity).order)
				end
				if lowest < floor then
					floors = false
				end
			else
				local odds = Crates.liquidOdds(id, 1)
				local total = 0
				for liquidId, p in odds do
					total += p
					if Liquids.get(liquidId).order < Liquids.get(def.liquidFloor).order then
						floors = false
					end
				end
				if not near1(total) then
					sums = false
				end
			end
		end
		for _, kind in { "nuke", "liquid" } do
			for variant = 1, Crates.VARIANTS do
				if not Crates.has(Crates.idFor(kind, variant)) then
					variantsOk = false
				end
			end
		end
		check("§crate every crate is well-formed (id, tier, kind + variant)", defsOk and variantsOk)
		check("§crate every crate's prize table sums to 1", sums)
		check("§crate no crate ever hands out anything under its floor", floors)

		-- Better crate, better prize: the chance of Epic-or-better climbs up each band's
		-- ladder (early nuke1 -> nuke3, late nuke4 -> nuke5), and Scrap and Field never
		-- roll an Anomaly.
		local function epicPlus(id: string): number
			local total = 0
			for itemId, p in Crates.nukeOdds(id) do
				if Rarity.get(Items.get(itemId).rarity).order >= Rarity.get("Epic").order then
					total += p
				end
			end
			return total
		end
		local function anomaly(id: string): number
			local total = 0
			for itemId, p in Crates.nukeOdds(id) do
				if Items.get(itemId).rarity == "Anomaly" then
					total += p
				end
			end
			return total
		end
		check(
			"§crate nuke crates get better up the ladder",
			epicPlus("nuke1") < epicPlus("nuke2") and epicPlus("nuke2") < epicPlus("nuke3") and epicPlus("nuke4") < epicPlus("nuke5")
		)
		check(
			"§crate Scrap and Field never roll an Anomaly; Void and up can",
			anomaly("nuke1") == 0 and anomaly("nuke2") == 0 and anomaly("nuke3") > 0 and anomaly("nuke4") > 0 and anomaly("nuke5") > anomaly("nuke4")
		)

		-- A nuke crate only hands out nukes stocked inside its stage range.
		local ranged = true
		for _, id in Crates.ORDER do
			local def = Crates.DEFS[id]
			if def.kind == "nuke" then
				if def.stages == nil or next(Crates.nukeOdds(id)) == nil then
					ranged = false
				end
				for itemId in Crates.nukeOdds(id) do
					if not Crates.inStageRange(def, Items.get(itemId)) then
						ranged = false
					end
				end
			end
		end
		check("§crate nuke crates only roll nukes from their own stage range", ranged)

		-- Deeper stages drop better crates (the average variant climbs); detector luck
		-- only ever moves the odds up the ladder.
		local function meanVariant(odds: { number }): number
			local mean = 0
			for variant = 1, Crates.VARIANTS do
				mean += variant * odds[variant]
			end
			return mean
		end
		local deeper, lucky = true, true
		for stageId = 2, #Stages.DEFS do
			if meanVariant(Crates.variantOdds(stageId, 1)) < meanVariant(Crates.variantOdds(stageId - 1, 1)) then
				deeper = false
			end
		end
		for stageId = 1, #Stages.DEFS do
			local plain, boosted = Crates.variantOdds(stageId, 1), Crates.variantOdds(stageId, 2.5)
			local total = 0
			for variant = 1, Crates.VARIANTS do
				total += boosted[variant]
				if (plain[variant] == 0) ~= (boosted[variant] == 0) then
					lucky = false -- luck never makes an absent crate drop
				end
			end
			if meanVariant(boosted) < meanVariant(plain) or not near1(total) then
				lucky = false
			end
		end
		check("§crate deeper stages drop more top-tier crates", deeper)
		local banded = true
		for stageId = 1, #Stages.DEFS do
			local odds = Crates.variantOdds(stageId, 2.5)
			if stageId <= 6 and (odds[4] > 0 or odds[5] > 0) then
				banded = false
			elseif stageId >= 7 and (odds[1] > 0 or odds[2] > 0 or odds[4] <= 0) then
				banded = false
			end
		end
		check("§crate Stages 1-6 drop only the early crates, 7+ the late ones", banded)
		check("§crate detector luck moves crate odds up, never down", lucky)

		-- Crates share the bag's slots but never enter `carry`.
		local data = { carry = { {}, {} }, crates = { { uid = "a", crateId = "nuke1" } } }
		check("§crate crates count toward the bag's slots", Bag.used(data) == 3)
		check("§crate Bag.findCrate finds a crate and nothing else", Bag.findCrate(data, "a") ~= nil and Bag.findCrate(data, "b") == nil)

		-- Every crate builds: a PrimaryPart to weld by, its id stamped, and CrateFx's
		-- carriers + at least one effect on it.
		local builds = true
		for _, id in Crates.ORDER do
			local ok, model = pcall(CrateModels.create, id)
			if not ok or model.PrimaryPart == nil or model:GetAttribute("CrateId") ~= id
				or model:FindFirstChild("FxCore") == nil or model:FindFirstChildWhichIsA("ParticleEmitter", true) == nil then
				builds = false
			end
			if ok then
				model:Destroy()
			end
		end
		check("§crate every crate model builds with its effects", builds)

		-- A DUG CRATE PASSES FOR A NUKE until washed (DigService.standInFor): every tier
		-- a crate can be needs a real nuke of that tier somewhere to stand in for it...
		local standIns = true
		for _, id in Crates.ORDER do
			local found = false
			for _, stageId in Stages.builtIds() do
				if Items.hasAny(stageId, Crates.DEFS[id].tier) then
					found = true
					break
				end
			end
			standIns = standIns and found
		end
		check("§crate every crate tier has a stand-in nuke to hide as", standIns)

		-- ...and the crusted crate under the rock says nothing: no effects, no attributes
		-- (CrateId hangs the Open prompt; SourceName names the template), no crate name.
		local hidden = true
		for _, id in Crates.ORDER do
			local ok, model = pcall(CrateModels.createHidden, id)
			if not ok or model.PrimaryPart == nil or next(model:GetAttributes()) ~= nil
				or model.Name == Crates.DEFS[id].name or model:FindFirstChild("FxCore") ~= nil
				or model:FindFirstChildWhichIsA("ParticleEmitter", true) ~= nil
				or model:FindFirstChildWhichIsA("Light", true) ~= nil then
				hidden = false
			end
			if ok then
				model:Destroy()
			end
		end
		check("§crate a crusted crate model carries nothing that says crate", hidden)
	end

	table.insert(lines, string.format("\n%d passed, %d failed", passed, failed))
	print(table.concat(lines, "\n"))
	return failed == 0
end

return Spec
