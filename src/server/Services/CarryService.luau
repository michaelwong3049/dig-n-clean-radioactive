--!strict
--[[
	CarryService.lua — what is in your bag, and what state it is in.

	ONE DESCRIPTION OF AN ITEM, FOR EVERY SURFACE THAT SHOWS ONE.
	`describe` used to be a local inside DeconService, which was correct while the
	station panel was the only thing that ever rendered a carried item. The hotbar is
	the second, and a second copy of this function is how the panel ends up saying an
	item is worth $340 while the hotbar says $306 — the two would drift the first time
	anyone touched the decay or contamination maths and only remembered one call site.
	It lives here, both of them call it, and there is nothing to keep in sync.

	WHY THE BROADCAST IS CHANGE-DRIVEN AND NOT PER-TICK.
	A backpack is static for most of a run. Streaming twenty described items ten times
	a second to say "still the same twenty items" is most of a remote's budget spent on
	nothing. This fires only when the bag's SIGNATURE moves, which in practice is on a
	pull, a sale, a scrub tick, a condition transition and a dock. What counts as the
	signature is spelled out at signatureOf, and the rule that keeps this honest is
	there too: anything the client can render has to be in it, or it goes stale.

	The countdown the player watches is not streamed at all. `elapsed` goes out with
	the payload and the client runs Shared/Decay on it locally, which is the same
	reason Radiation and Decay are shared in the first place (ARCHITECTURE.md): the
	number on the HUD and the number the server enforces come out of one function, so
	they cannot disagree.

	WHAT THIS DOES NOT OWN, DELIBERATELY: the decay tick itself. See the note in
	ExposureService — moving it here would reorder it against the emission read in the
	same pass, and that is a radiation change wearing an inventory change's clothes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tuning = require(Shared.Config.Tuning)
local Gear = require(Shared.Config.Gear)
local Items = require(Shared.Config.Items)
local Rarity = require(Shared.Config.Rarity)
local Weight = require(Shared.Config.Weight)
local Decay = require(Shared.Decay)
local Liquids = require(Shared.Config.Liquids)
local Contamination = require(Shared.Contamination)
local StatResolver = require(Shared.StatResolver)
local Ticker = require(Shared.Util.Ticker)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local DigService = require(script.Parent.DigService)

local CarryService = {}

local carryRemote: any = nil
local holdRemote: any = nil
local lastSignature: { [Player]: string } = {}

--- The cheapest hose that can shift a patch of this hardness. Lives here rather
--- than in DeconService because `describe` needs it to fill in "needs Chem Injector",
--- and DeconService's scrub messages need the same string for the same reason.
---
--- Walks Gear.Cleaner in order, so it depends on `power` ASCENDING down that table.
--- It always has, and the shop's own price ladder would be nonsense otherwise, but the
--- dependency is worth writing down: a table sorted any other way makes this return
--- the wrong rung rather than fail, which is the kind of bug that ships.
function CarryService.hoseNameFor(potencyNeeded: number): string
	for _, tier in Gear.Cleaner do
		if tier.power >= potencyNeeded then
			return tier.name
		end
	end
	return "something stronger"
end

--- Everything any surface is allowed to know about one carried item.
---
--- `elapsed` is on here so the client can run the decay clock itself; it is the
--- item's own accrued decay seconds and reveals nothing the player does not already
--- own. Never put an absolute timestamp here — see the header of Shared/Decay for
--- what that costs.
function CarryService.describe(item: any, stats: any): any
	local def = Items.get(item.itemId)
	local patches = item.patches or {}
	local value, clean = EconomyService.valueOf(item, stats)
	local _, condition = Decay.conditionOf(item, stats.satchelFuseMult)

	-- TWO GATES, ASKED SEPARATELY, because the card has to answer two questions that
	-- stopped having the same answer when Config/Liquids landed:
	--
	--   blocked        against effectivePotency -- "can I clean this RIGHT NOW", which
	--                  is what the CLEAN button has to be honest about. A card that
	--                  says NEEDS CHEM BATH over an item the loaded Molten Lava can
	--                  crack is a card lying to the player about their own inventory.
	--   blockedByTool  against cleanPotency -- "would this still be blocked once the
	--                  canister runs out". This is what `needs` is named from and
	--                  what the Quarantine Locker shops against, because a shopping
	--                  list written against a rented key is worthless.
	--
	-- When they disagree, the liquid is the only reason this item is cleanable, and
	-- `unlockedByLiquid` says so out loud so the UI can credit it rather than letting
	-- the player think their cleaner quietly got better.
	local blocked = Contamination.blockedBy(patches, stats.effectivePotency)
	local blockedByTool = Contamination.blockedBy(patches, stats.cleanPotency)
	local unlockedByLiquid = blocked == nil and blockedByTool ~= nil

	-- The cheapest liquid that would close the gap, when one exists at all. nil once
	-- the shortfall is past Liquids.MAX_POTENCY_BONUS, which is the honest answer:
	-- past that point no roll saves you and only the Cleaner track will.
	local rescue = if blocked then Liquids.cheapestWithPotency(blocked - stats.cleanPotency) else nil

	-- What this item would earn per second on a pedestal, IF you displayed it —
	-- undamped, since ExhibitService's duplicate-copy damping depends on what
	-- else is already on your own plot, which this function has no visibility
	-- into (it describes a bag item, not a placement). nil whenever
	-- ExhibitService.display would actually refuse it (dirty, or Slagged), so
	-- this is never a number the game won't actually pay out.
	local perSecond: number? = nil
	if clean and item.modifier ~= "Slagged" then
		local rarity = Rarity.get(item.rarity)
		local mod = Rarity.MODIFIERS[item.modifier] or Rarity.MODIFIERS.None
		-- Same Weight.valueMult factor ExhibitService.entryYieldPerSecond applies, so the
		-- bag's "would earn $/s" preview matches what the pedestal actually pays.
		perSecond = def.baseValue
			* mod.valueMult
			* Weight.valueMult(def.weight)
			* rarity.displayYield
			* stats.yieldMultiplier
			/ 60
	end

	return {
		uid = item.uid,
		name = def.name,
		flavor = def.flavor,
		rarity = item.rarity,
		modifier = item.modifier,
		patches = table.clone(patches),
		clean = clean,
		blockedBy = blocked,
		needs = if blocked then CarryService.hoseNameFor(blocked) else nil,
		unlockedByLiquid = unlockedByLiquid,
		rescueLiquid = if rescue then rescue.name else nil,
		value = value,
		perSecond = perSecond,
		condition = condition.name,
		elapsed = item.elapsed,
		frozen = item.frozen,
	}
end

--- Put a carried item in the player's hands, or empty them.
---
--- Lives here rather than in ToolService because this file already owns "what is in
--- your bag and what state it is in", and holding is a property of the bag, not of
--- the models ToolService welds. ToolService READS heldUid and renders it; it does
--- not decide it.
function CarryService.hold(player: Player, uid: string?): boolean
	local data = DataService.data(player)
	if data == nil then
		return false
	end

	if uid == nil or uid == "" then
		data.heldUid = ""
		return true
	end

	-- BOTH HANDS ARE ON THE MAGNET DURING A PULL. Committing to a signal (see
	-- DigService.isLocked) roots the player and puts the magnet in their hands the
	-- same way ToolService's `wanted` does for the detector — reaching into the bag
	-- for something else at the same time is the exact "two things in your hands at
	-- once" look this file exists to prevent, so the request is refused outright
	-- rather than accepted and then fought over which model wins the off hand.
	if DigService.isLocked(player) then
		return false
	end

	-- Only out of the BAG. The Quarantine Locker is a shelf, not a pocket: racking is
	-- how you put something down, and being able to pull a racked item back into your
	-- hands would quietly undo that.
	for _, item in data.carry do
		if item.uid == uid then
			data.heldUid = uid
			return true
		end
	end
	return false
end

--- What has to change before the client is told anything. A bag sitting still costs
--- one string compare per player per tick, so this can afford to be thorough — and it
--- has to be, because ANYTHING the card can render but the signature cannot see is a
--- field that silently goes stale on the client forever.
---
--- That is not hypothetical. The first version was uid + condition + value + clean, and
--- `frozen` is none of those: docking at a station stopped the clocks server-side
--- while the hotbar carried on counting down, because nothing in the signature had
--- moved. The rule when adding to the payload is to add here too.
---
---   frozen     — docking and the locker stop the clock without touching anything else
---   #patches   — a scrub removes them one at a time; `clean` only flips at the end
---   blockedBy  — buying a better cleaner unblocks an item with no change to patches
---   unlockedByLiquid / rescueLiquid
---              — loading, spending or running out of a liquid (Config/Liquids)
---                moves BOTH of these with nothing about the item itself changing.
---                `blockedBy` alone does not cover it: swapping Molten Lava for
---                Nano-Foam leaves an already-unblocked item unblocked while the
---                rescue name on the card changes underneath it.
---   perSecond  — depends on stats.yieldMultiplier, which the Index completion bonus
---                (DigService.grantStageCompletionBonus) can change mid-session with
---                nothing else about the item itself moving
local function signatureOf(described: { any }, capacity: number): string
	local parts = { tostring(capacity) }
	for _, item in described do
		table.insert(
			parts,
			`{item.uid}:{item.condition}:{item.value}:{item.perSecond}:{tostring(item.clean)}:{tostring(item.frozen)}:{#item.patches}:{tostring(item.blockedBy)}:{tostring(item.unlockedByLiquid)}:{tostring(item.rescueLiquid)}`
		)
	end
	return table.concat(parts, "|")
end

local function stepPlayer(player: Player)
	local data = DataService.data(player)
	if data == nil then
		return
	end

	-- SELF-HEALING RATHER THAN SIX CALL SITES. An item can leave the bag by being
	-- sold, racked, slagged, or dropped on blackout, and each of those lives in a
	-- different service. Patching all four to clear heldUid is four chances to forget
	-- and one stale weld left in the player's hand; checking it here, where the bag is
	-- already being walked every tick, cannot be forgotten.
	if data.heldUid ~= "" and EconomyService.find(data, data.heldUid) == nil then
		data.heldUid = ""
	end

	-- Same self-healing, for the case `hold()`'s guard cannot reach: a player already
	-- carrying an item who then locks onto a NEW signal — locking on does not itself
	-- go through `hold()`, so nothing upstream stops the item riding along into the
	-- pull. Released, not dropped: it stays in the bag, just out of the player's
	-- hands until the pull ends.
	if data.heldUid ~= "" and DigService.isLocked(player) then
		data.heldUid = ""
	end

	local stats = StatResolver.get(data)

	local described = {}
	for _, item in data.carry do
		table.insert(described, CarryService.describe(item, stats))
	end

	local signature = signatureOf(described, stats.capacity)
	if lastSignature[player] == signature then
		return
	end
	lastSignature[player] = signature

	carryRemote:FireClient(player, {
		capacity = stats.capacity,
		-- The client needs this to run Decay locally. It is a gear stat the player
		-- already owns, so it leaks nothing.
		fuseMult = stats.satchelFuseMult,
		items = described,
	})
end

-- ── Bootstrap ──────────────────────────────────────────────────────────

function CarryService.init()
	carryRemote = Net.get("CarryState")
	holdRemote = Net.get("HoldInput")
end

function CarryService.start()
	holdRemote.OnServerEvent:Connect(function(player: Player, uid: any)
		-- tostring(nil) is "nil", not nil, so guard the type rather than coercing:
		-- an empty-hands request has to be expressible, and it is `nil` or "".
		CarryService.hold(player, if type(uid) == "string" then uid else nil)
	end)

	Ticker.every(Tuning.TICK_RATE, function()
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(stepPlayer, player)
			if not ok then
				warn(`[carry] tick failed for {player.Name}: {err}`)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSignature[player] = nil
	end)
end

return CarryService
